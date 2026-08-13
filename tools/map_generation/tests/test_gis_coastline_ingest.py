#!/usr/bin/env python3
"""Gates: real GIS coastline align metrics + guarded pilot write (id-stable)."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import (  # noqa: E402
    align_gis_to_provinces,
    apply_pilot_write,
    build_pilot_fixture_from_geometry,
    coastal_province_ids_from_terrain,
    count_changed_provinces,
    expand_coastal_id_pool,
    geometry_stats,
    littoral_province_ids_from_adjacency,
    load_geometry_payload,
    point_in_polygon,
    polygon_centroid,
    province_id_set,
    run_align_pipeline,
)

WF = ROOT / "data" / "provinces_world_full"
GEOM = WF / "provinces_geometry.json"
CLI = ROOT / "tools" / "map_generation" / "scripts" / "ingest_gis_coastlines.py"
FIXTURE = ROOT / "tools" / "map_generation" / "fixtures" / "gis_coastline_pilot_rings.json"
LIB = ROOT / "tools" / "map_generation" / "lib" / "gis_coastline_ingest.py"


class TestGisPureHelpers(unittest.TestCase):
    def test_centroid_and_pip_on_controlled_ring(self) -> None:
        ring = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]]
        cx, cy = polygon_centroid(ring)
        self.assertAlmostEqual(cx, 5.0, places=5)
        self.assertAlmostEqual(cy, 5.0, places=5)
        self.assertTrue(point_in_polygon(5.0, 5.0, ring))
        self.assertFalse(point_in_polygon(15.0, 5.0, ring))

    def test_align_fixture_overlap_matched_gt0_id_stable(self) -> None:
        # Controlled fixture: three synthetic provinces + GIS rings with hints
        provinces = [
            {"id": 1, "points": [[0, 0], [4, 0], [4, 4], [0, 4]]},
            {"id": 2, "points": [[5, 0], [9, 0], [9, 4], [5, 4]]},
            {"id": 3, "points": [[0, 5], [4, 5], [4, 9], [0, 9]]},
        ]
        gis = [
            {
                "id": "g1",
                "province_id": 1,
                "points": [[0.2, 0.2], [3.8, 0.1], [3.9, 3.9], [0.1, 3.8]],
            },
            {
                "id": "g2",
                "province_id": 2,
                "points": [[5.1, 0.1], [8.9, 0.2], [8.8, 3.8], [5.2, 3.9]],
            },
            {
                "id": "orphan",
                "points": [[100, 100], [110, 100], [110, 110], [100, 110]],
            },
        ]
        align = align_gis_to_provinces(gis, provinces, max_centroid_dist=2.0)
        self.assertGreaterEqual(align["matched"], 2)
        self.assertTrue(align["id_stable"])
        self.assertEqual(align["province_count"], 3)
        self.assertIn(1, align["matched_ids"])
        self.assertIn(2, align["matched_ids"])
        # Orphan far away or unmatched
        self.assertGreaterEqual(align["orphan_gis_count"], 0)
        self.assertEqual(align["unmatched_existing_count"], 3 - align["matched"])

    def test_dry_run_no_mutate_write_changes_points(self) -> None:
        provinces = [
            {"id": 10, "points": [[0, 0], [6, 0], [6, 6], [0, 6]]},
            {"id": 11, "points": [[7, 0], [12, 0], [12, 5], [7, 5]]},
        ]
        payload = {"meta": {}, "provinces": deepcopy(provinces)}
        gis = build_pilot_fixture_from_geometry(provinces, [10, 11], limit=2, pull=0.05)
        self.assertGreaterEqual(len(gis), 1)

        dry = run_align_pipeline(payload, gis, apply_write=False)
        self.assertGreaterEqual(dry["matched"], 1)
        self.assertTrue(dry["id_stable"])
        self.assertIsNone(dry["payload"])
        self.assertEqual(dry["changed_provinces"], 0)
        # Original untouched
        self.assertEqual(payload["provinces"][0]["points"], provinces[0]["points"])

        wet = run_align_pipeline(payload, gis, apply_write=True, min_vertices=8)
        self.assertTrue(wet["id_stable"])
        self.assertTrue(wet["id_set_equal"])
        self.assertGreaterEqual(wet["changed_provinces"], 1)
        self.assertEqual(len(wet["id_set_after"]), 2)
        after = wet["payload"]
        self.assertIsNotNone(after)
        stats = geometry_stats(after["provinces"])
        self.assertEqual(stats["triangles"], 0)
        self.assertGreaterEqual(stats["min"], 8)
        # Matched id points actually differ
        self.assertGreater(
            count_changed_provinces(payload, after),
            0,
        )

    def test_apply_pilot_preserves_id_set(self) -> None:
        provinces = [
            {"id": 100, "points": [[0, 0], [2, 0], [2, 2], [0, 2]]},
            {"id": 101, "points": [[3, 0], [5, 0], [5, 2], [3, 2]]},
        ]
        payload = {"meta": {"total": 2}, "provinces": deepcopy(provinces)}
        matches = [
            {
                "province_id": 100,
                "gis_feature_id": "x",
                "method": "hint",
                "points": [[0, 0], [1, 0], [2, 0], [2, 1], [2, 2], [1, 2], [0, 2], [0, 1]],
            }
        ]
        newp = apply_pilot_write(payload, matches, min_vertices=8)
        self.assertEqual(province_id_set(payload["provinces"]), province_id_set(newp["provinces"]))
        self.assertEqual(len(newp["provinces"]), 2)
        # Unmatched province unchanged
        self.assertEqual(newp["provinces"][1]["points"], provinces[1]["points"])


class TestGisWorldFullCli(unittest.TestCase):
    def test_fixture_and_lib_shipped(self) -> None:
        self.assertTrue(LIB.is_file())
        self.assertTrue(CLI.is_file())
        self.assertTrue(FIXTURE.is_file(), msg="offline pilot fixture missing")
        feats = json.loads(FIXTURE.read_text(encoding="utf-8")).get("features") or []
        self.assertGreaterEqual(len(feats), 1)

    def test_dry_run_world_full_real_metrics(self) -> None:
        r = subprocess.run(
            [
                sys.executable,
                str(CLI),
                "--dir",
                "data/provinces_world_full",
                "--source",
                str(FIXTURE.relative_to(ROOT)),
                "--pilot-limit",
                "24",
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(r.returncode, 0, msg=r.stdout + r.stderr)
        out = r.stdout
        self.assertIn("DRY-RUN", out)
        self.assertIn("id_stable: true", out)
        # Not the fixed stub of all zeros with stub text
        self.assertNotIn("stub does not align GIS", out)
        self.assertNotRegex(out, r"matched:\s*0\s*\(stub")
        # Extract matched count
        matched = None
        for line in out.splitlines():
            if "matched:" in line and "unmatched" not in line:
                # "  matched: 24"
                try:
                    matched = int(line.split("matched:")[1].strip().split()[0])
                except (IndexError, ValueError):
                    pass
        self.assertIsNotNone(matched)
        self.assertGreaterEqual(matched, 1)
        # Disk unchanged after dry-run (count still 2665)
        geom = json.loads(GEOM.read_text(encoding="utf-8"))
        self.assertEqual(len(geom.get("provinces") or []), 2665)

    def test_write_without_pilot_refused(self) -> None:
        r = subprocess.run(
            [sys.executable, str(CLI), "--write"],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(r.returncode, 2)
        self.assertIn("REFUSED", r.stderr)

    def test_pilot_write_to_scratch_id_stable(self) -> None:
        """Write pilot rings into a scratch geometry file; id set stays 2665."""
        before = json.loads(GEOM.read_text(encoding="utf-8"))
        # Build a fresh stronger-pull pilot so points differ from current shipped rings.
        coastal_sample = []
        for p in before.get("provinces") or []:
            meta = p.get("meta") or {}
            # Prefer already-coastal pilot stamps or high-id coastal band
            if meta.get("gis_pilot") or int(p["id"]) >= 20000:
                coastal_sample.append(int(p["id"]))
            if len(coastal_sample) >= 8:
                break
        if len(coastal_sample) < 4:
            coastal_sample = [int(p["id"]) for p in (before.get("provinces") or [])[:8]]
        feats = build_pilot_fixture_from_geometry(
            before.get("provinces") or [],
            coastal_sample,
            limit=8,
            pull=0.18,
        )
        self.assertGreaterEqual(len(feats), 1)
        # Force observable point delta vs already-stamped geometry (idempotent re-refine risk).
        for f in feats:
            pts = f.get("points") or []
            f["points"] = [[float(x) + 1.25, float(y) - 0.75] for x, y in pts]
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "pilot_src.json"
            out_geom = Path(td) / "provinces_geometry.json"
            src.write_text(
                json.dumps({"features": feats}, indent=2), encoding="utf-8"
            )
            r = subprocess.run(
                [
                    sys.executable,
                    str(CLI),
                    "--dir",
                    "data/provinces_world_full",
                    "--source",
                    str(src),
                    "--write",
                    "--pilot",
                    "--pilot-limit",
                    "8",
                    "--out",
                    str(out_geom),
                    "--min-vertices",
                    "16",
                ],
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(r.returncode, 0, msg=r.stdout + r.stderr)
            self.assertIn("id_stable: true", r.stdout)
            self.assertIn("changed_provinces:", r.stdout)
            self.assertTrue(out_geom.is_file())
            after = json.loads(out_geom.read_text(encoding="utf-8"))
            self.assertEqual(len(after["provinces"]), 2665)
            self.assertEqual(
                province_id_set(before["provinces"]),
                province_id_set(after["provinces"]),
            )
            stats = geometry_stats(after["provinces"])
            self.assertEqual(stats["triangles"], 0)
            self.assertGreaterEqual(stats["min"], 16)
            changed = count_changed_provinces(before, after)
            self.assertGreaterEqual(changed, 1)
            # Shipped geometry untouched (write went to scratch)
            shipped = json.loads(GEOM.read_text(encoding="utf-8"))
            self.assertEqual(
                province_id_set(shipped["provinces"]),
                province_id_set(before["provinces"]),
            )




class TestGisLittoralExpand(unittest.TestCase):
    def test_littoral_pool_exceeds_coastal_land(self) -> None:
        terrain = json.loads((WF / "province_terrain_layer.json").read_text(encoding="utf-8"))
        adj = json.loads((WF / "province_adjacency.json").read_text(encoding="utf-8"))
        coastal = coastal_province_ids_from_terrain(terrain)
        lit = littoral_province_ids_from_adjacency(terrain, adj, exclude_ids=coastal)
        pool = expand_coastal_id_pool(terrain, adj, include_littoral=True, limit=0)
        self.assertGreaterEqual(len(coastal), 500)
        self.assertGreater(len(lit), 0, msg="expected unstamped land-near-water candidates at design time")
        self.assertGreater(len(pool), len(coastal))
        self.assertGreaterEqual(len(pool), 720)

    def test_world_full_gis_pilot_stamped_ge_720(self) -> None:
        """Shipped world_full: GIS pilot expanded via coastal+littoral (id-stable, no triangles)."""
        geom = load_geometry_payload(GEOM)
        stamped = sum(
            1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)
        stats = geometry_stats(geom["provinces"])
        self.assertEqual(stats.get("triangles"), 0)
        self.assertGreaterEqual(int(stats.get("min") or 0), 16)
        self.assertEqual(int(stats.get("count") or 0), 2665)
        # Fixture tracks expand
        feats = json.loads(FIXTURE.read_text(encoding="utf-8")).get("features") or []
        self.assertGreaterEqual(len(feats), 753)


if __name__ == "__main__":
    unittest.main(verbosity=2)
