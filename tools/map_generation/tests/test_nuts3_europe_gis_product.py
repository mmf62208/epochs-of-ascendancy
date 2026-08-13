#!/usr/bin/env python3
"""Gates: Europe NUTS-3 GIS pilot product (ingest → project → emit)."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from nuts3_europe_gis_product import (  # noqa
    DEFAULT_GEOJSON,
    PILOT_ID_BASE,
    PILOT_DIR_NAME,
    build_nuts3_pilot,
    load_nuts3_features,
    nuts3_europe_gis_integrity,
    project_ring_lonlat,
    simplify_ring,
)


class TestNuts3EuropeGis(unittest.TestCase):
    def test_source_geojson_present(self):
        self.assertTrue(DEFAULT_GEOJSON.is_file(), msg="Eurostat NUTS-3 GeoJSON must be checked in under data/gis/")
        feats = load_nuts3_features(DEFAULT_GEOJSON)
        self.assertGreaterEqual(len(feats), 500)
        self.assertTrue(all(f.get("nuts_id") for f in feats[:10]))

    def test_build_product_real_path(self):
        out = build_nuts3_pilot(DEFAULT_GEOJSON)
        self.assertTrue(out.get("ok"), msg=out.get("stats"))
        stats = out["stats"]
        self.assertGreaterEqual(int(stats["land_n"]), 500)
        self.assertEqual(int(stats["id_base"]), PILOT_ID_BASE)
        self.assertGreaterEqual(float(stats["mean_verts"]), 12.0)
        self.assertTrue(stats.get("denser_than_europe_core"))
        # IDs disjoint from densify 700k and world_full
        self.assertGreaterEqual(int(stats["id_min"]), PILOT_ID_BASE)
        self.assertLess(int(stats["id_max"]), 800000)
        # real NUTS ids mapped
        self.assertGreaterEqual(len(out.get("nuts_id_to_province") or {}), 500)
        # hierarchy present
        self.assertGreaterEqual(len(out.get("states") or []), 40)
        self.assertGreaterEqual(len(out.get("regions") or []), 5)
        # Names must be NUTS unit labels, not country NAME_ENGL collapse (~37)
        self.assertTrue(stats.get("name_ok"), msg=stats)
        self.assertGreaterEqual(int(stats.get("unique_names") or 0), max(500, int(stats["land_n"] * 0.95)))
        names = [str(p.get("name") or "") for p in out["provinces_base"]["provinces"]]
        # Stuttgart district must not be labeled "Germany"
        st = [p for p in out["provinces_base"]["provinces"] if p.get("nuts_id") == "DE111"]
        if st:
            self.assertNotEqual(st[0]["name"], "Germany")
            self.assertIn("Stuttgart", st[0]["name"])
        self.assertNotIn("Germany", names[:20])  # first ids are AL/… not DE, but sanity

    def test_name_field_prefers_nuts_name_not_country_engl(self):
        feats = load_nuts3_features(DEFAULT_GEOJSON)
        de111 = next((f for f in feats if f.get("nuts_id") == "DE111"), None)
        self.assertIsNotNone(de111)
        self.assertNotEqual(de111["name"], "Germany")
        self.assertIn("Stuttgart", de111["name"])
        # Aggregate: unique names must be near feature count (not ~37 countries)
        unames = {f["name"] for f in feats}
        self.assertGreaterEqual(len(unames), 1000)

    def test_project_and_simplify_helpers(self):
        # Berlin-ish bbox ring
        ring_ll = [[13.0, 52.0], [14.0, 52.0], [14.0, 53.0], [13.0, 53.0], [13.0, 52.0]]
        ring_w = project_ring_lonlat(ring_ll)
        self.assertEqual(len(ring_w), 5)
        simp = simplify_ring(ring_w, max_verts=48, min_verts=20)
        self.assertGreaterEqual(len(simp), 20)

    def test_written_pilot_integrity(self):
        g = nuts3_europe_gis_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        pilot = ROOT / "data" / PILOT_DIR_NAME
        self.assertTrue((pilot / "provinces_geometry.json").is_file())
        self.assertTrue((pilot / "province_adjacency.json").is_file())
        self.assertTrue((pilot / "hierarchy_scaffold.json").is_file())
        geom = json.loads((pilot / "provinces_geometry.json").read_text())
        self.assertTrue((geom.get("meta") or {}).get("nuts3"))
        ids = [int(p["id"]) for p in geom.get("provinces") or []]
        self.assertTrue(all(i >= PILOT_ID_BASE for i in ids))
        # no world_full collision
        self.assertTrue(all(i >= 710000 for i in ids))
        # Honest orphan recompute + non-empty adjacency map
        self.assertIn("orphan_n", g)
        self.assertEqual(int(g["orphan_n"]), 0)
        self.assertGreaterEqual(int(g.get("adjacency_keys") or 0), 500)
        self.assertGreaterEqual(int(g.get("unique_names") or 0), max(500, int(len(ids) * 0.95)))
        base = json.loads((pilot / "provinces_base.json").read_text())
        unames = {str(p.get("name") or "") for p in base.get("provinces") or []}
        self.assertGreaterEqual(len(unames), 1000)
        # Country-label collapse must not reappear
        self.assertNotEqual(len(unames), 37)

    def test_orphan_count_rejects_empty_adjacency(self):
        from nuts3_europe_gis_product import _count_adjacency_orphans  # noqa

        ids = [710000, 710001, 710002]
        self.assertEqual(_count_adjacency_orphans(ids, {}), 3)
        self.assertEqual(_count_adjacency_orphans(ids, {"710000": [710001], "710001": [710000]}), 1)
        self.assertEqual(
            _count_adjacency_orphans(ids, {"710000": [710001], "710001": [710000], "710002": [710000]}),
            0,
        )

    def test_scenario_and_loader_wired(self):
        sc = ROOT / "data" / "scenarios" / "world_pilot_europe_nuts3.json"
        self.assertTrue(sc.is_file())
        data = json.loads(sc.read_text())
        self.assertEqual(data.get("use_province_data_dir"), PILOT_DIR_NAME)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("provinces_pilot_europe_nuts3", sl)
        self.assertIn("nuts3_gis_live=1", sl)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_nuts3_europe_gis_product.py", ci)

    def test_no_world_full_renumber(self):
        # world_full still has low IDs
        wf = ROOT / "data" / "provinces_world_full" / "provinces_geometry.json"
        g = json.loads(wf.read_text())
        ids = [int(p["id"]) for p in g.get("provinces") or []]
        self.assertTrue(any(i < 1000 for i in ids))
        self.assertFalse(any(710000 <= i < 720000 for i in ids))


if __name__ == "__main__":
    unittest.main(verbosity=2)
