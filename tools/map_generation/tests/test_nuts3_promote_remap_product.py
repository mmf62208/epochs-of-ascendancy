#!/usr/bin/env python3
"""Gates: NUTS-3 promote remap (Pack H / M1) — id-stable, no world_full renumber."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from nuts3_promote_remap_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(
            1 for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_remap(self):
        p = build_nuts3_promote_remap(sample_limit=200)
        self.assertFalse(p.get("empty"))
        self.assertFalse(p.get("renumber_world_full"))
        self.assertGreaterEqual(int(p.get("pair_count", 0)), 100)
        for pair in p.get("pairs") or []:
            self.assertGreaterEqual(int(pair["nuts3_id"]), 710000)
            self.assertLessEqual(int(pair["world_full_id"]), 99999)
            self.assertGreaterEqual(int(pair["world_full_id"]), 1)
        self.assertTrue(nuts3_promote_remap_integrity().get("ok"))

    def test_write_json(self):
        out = ROOT / "data/provinces_pilot_europe_nuts3/nuts3_to_world_full_overlap.json"
        p = write_remap_json(out, sample_limit=250)
        self.assertTrue(out.exists())
        self.assertGreaterEqual(int(p.get("pair_count", 0)), 100)
        self.assertFalse(p.get("renumber_world_full"))


class TestDocs(unittest.TestCase):
    def test_roadmap(self):
        road = (ROOT / "docs/MAP_HIERARCHY_AND_GIS_ROADMAP.md").read_text().lower()
        self.assertIn("nuts", road)
        self.assertTrue("remap" in road or "promote" in road or "overlap" in road)


if __name__ == "__main__":
    unittest.main(verbosity=2)
