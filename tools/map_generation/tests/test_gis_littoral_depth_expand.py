#!/usr/bin/env python3
"""Gates: GIS littoral depth-2 expand (753 → ≥1343 id-stable stamps)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import (  # noqa: E402
    expand_coastal_id_pool,
    geometry_stats,
    load_geometry_payload,
    near_coast_inland_ids,
    littoral_province_ids_from_adjacency,
)

WF = ROOT / "data" / "provinces_world_full"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
DESIGN = ROOT / "docs" / "GIS_COASTLINE_INGEST_DESIGN.md"
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "ingest_gis_coastlines.py"
CI = ROOT / "tools" / "run_map_ci.sh"
LIB = ROOT / "tools" / "map_generation" / "lib" / "gis_coastline_ingest.py"

GIS_STAMP_FLOOR = 1343


class TestPool(unittest.TestCase):
    def setUp(self):
        self.terr = json.loads((WF / "province_terrain_layer.json").read_text(encoding="utf-8"))
        self.adj = json.loads((WF / "province_adjacency.json").read_text(encoding="utf-8"))

    def test_depth2_superset(self):
        d1 = expand_coastal_id_pool(
            self.terr, self.adj, include_littoral=True, littoral_depth=1, limit=0
        )
        d2 = expand_coastal_id_pool(
            self.terr, self.adj, include_littoral=True, littoral_depth=2, limit=0
        )
        self.assertGreaterEqual(len(d1), 753)
        self.assertGreaterEqual(len(d2), GIS_STAMP_FLOOR)
        self.assertGreater(len(d2), len(d1))
        self.assertTrue(set(d1).issubset(set(d2)))
        # Ring-2 inland only
        inland = near_coast_inland_ids(self.terr, self.adj, d1, exclude_ids=d1)
        self.assertGreaterEqual(len(inland), 500)
        for pid in inland[:20]:
            self.assertNotIn(pid, d1)

    def test_depth1_unchanged_contract(self):
        d1 = expand_coastal_id_pool(
            self.terr, self.adj, include_littoral=True, littoral_depth=1, limit=0
        )
        lit = littoral_province_ids_from_adjacency(self.terr, self.adj)
        self.assertGreaterEqual(len(d1), 753)
        self.assertGreater(len(lit), 0)


class TestStampedGeometry(unittest.TestCase):
    def test_stamped_floor_and_quality(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        provs = geom["provinces"]
        stamped = [p for p in provs if (p.get("meta") or {}).get("gis_pilot")]
        self.assertGreaterEqual(len(stamped), GIS_STAMP_FLOOR)
        meta = geom.get("meta") or {}
        self.assertGreaterEqual(int(meta.get("gis_pilot_count") or 0), GIS_STAMP_FLOOR)
        stats = geometry_stats(provs)
        self.assertEqual(int(stats.get("triangles") or 0), 0)
        self.assertGreaterEqual(int(stats.get("min") or 0), 16)
        self.assertEqual(len(provs), 2665)
        # Id set stable (no renumber)
        ids = {int(p["id"]) for p in provs}
        self.assertEqual(len(ids), 2665)


class TestTooling(unittest.TestCase):
    def test_cli_and_lib_hooks(self):
        script = SCRIPT.read_text(encoding="utf-8")
        lib = LIB.read_text(encoding="utf-8")
        self.assertIn("--littoral-depth", script)
        self.assertIn("littoral_depth", script)
        self.assertIn("def near_coast_inland_ids", lib)
        self.assertIn("littoral_depth", lib)
        self.assertIn("test_gis_littoral_depth_expand.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "littoral depth",
            "gis×1343",
            "1343",
            "near-coast inland",
        ]
        for path in (TODO, SUMMARY, ROADMAP, DESIGN):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
