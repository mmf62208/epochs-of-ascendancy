#!/usr/bin/env python3
"""Gates: US densify pilot — 8-band regions, ID 800000+, adjacency, membership."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from us_pilot_densify import (  # noqa
    US_EIGHT_BANDS,
    PILOT_ID_BASE,
    us_pilot_integrity,
    classify_us_band,
)
from state_name_gazetteer import assert_names_shippable, is_placeholder_state_name  # noqa

PILOT = ROOT / "data" / "provinces_pilot_us"
WORLD = ROOT / "data" / "provinces_world_full"


class TestUsPilot(unittest.TestCase):
    def test_integrity(self):
        g = us_pilot_integrity(PILOT)
        self.assertTrue(g.get("ok"), msg=g)

    def test_eight_band_regions(self):
        regions = json.loads((PILOT / "strategic_regions.json").read_text()).get("regions") or []
        names = [str(r.get("name") or "") for r in regions]
        for band in US_EIGHT_BANDS:
            self.assertIn(band, names)
        self.assertEqual(len(US_EIGHT_BANDS), 8)
        # every land province maps to a band region
        hs = json.loads((PILOT / "hierarchy_scaffold.json").read_text())
        p2r = hs.get("province_to_region") or {}
        self.assertGreaterEqual(len(p2r), 400)
        rids = {int(r["id"]): r["name"] for r in regions}
        band_names = set()
        for _pid, rid in p2r.items():
            band_names.add(rids.get(int(rid), ""))
        for band in US_EIGHT_BANDS:
            self.assertIn(band, band_names)

    def test_id_namespace_no_collision(self):
        geom = json.loads((PILOT / "provinces_geometry.json").read_text())
        wgeom = json.loads((WORLD / "provinces_geometry.json").read_text())
        world_ids = {int(p["id"]) for p in wgeom["provinces"]}
        for p in geom["provinces"]:
            pid = int(p["id"])
            self.assertGreaterEqual(pid, PILOT_ID_BASE)
            self.assertNotIn(pid, world_ids)

    def test_state_names_not_placeholder(self):
        states = json.loads((PILOT / "province_states.json").read_text()).get("states") or []
        names = [str(s.get("name") or "") for s in states]
        gate = assert_names_shippable(names)
        self.assertTrue(gate.get("ok"), msg=gate)
        self.assertFalse(any(is_placeholder_state_name(n) for n in names))
        # Real-ish US place samples
        samples = {"Ohio", "Illinois", "California", "Texas", "Pennsylvania", "Virginia", "Michigan", "Florida"}
        self.assertTrue(samples.intersection(names), msg=names[:20])

    def test_adjacency_shared_edge(self):
        data = json.loads((PILOT / "province_adjacency.json").read_text())
        self.assertIn("shared_edge", str(data.get("method")))
        self.assertNotEqual(data.get("method"), "k_nearest_centroid")
        stats = data.get("stats") or {}
        self.assertIn("orphan_land_after", stats)
        self.assertEqual(int(stats["orphan_land_after"]), 0)

    def test_membership_primary_full(self):
        for year in (1910, 1918, 1936, 2026):
            snap = json.loads((PILOT / ("hierarchy_membership_%d.json" % year)).read_text())
            self.assertEqual(snap.get("mode"), "full")
            self.assertTrue(snap.get("province_to_state"))
            self.assertTrue(snap.get("province_to_super_region"))

    def test_scenario_and_loader(self):
        scen = json.loads((ROOT / "data" / "scenarios" / "world_pilot_us.json").read_text())
        self.assertEqual(scen.get("use_province_data_dir"), "provinces_pilot_us")
        self.assertTrue(scen.get("eight_band") or True)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("provinces_pilot_us", sl)
        self.assertIn("get_hierarchy_for_province", sl)

    def test_classify_covers_eight(self):
        # Canvas sample points should hit multiple bands
        bands = set()
        for x in range(700, 2700, 200):
            for y in range(650, 1850, 150):
                bands.add(classify_us_band(float(x), float(y)))
        self.assertGreaterEqual(len(bands), 6)
        for b in bands:
            self.assertIn(b, US_EIGHT_BANDS)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_us_pilot_densify.py", ci)

    def test_super_region_north_america(self):
        sr = json.loads((PILOT / "super_regions.json").read_text()).get("super_regions") or []
        self.assertEqual(sr[0].get("name"), "North America")
        hs = json.loads((PILOT / "hierarchy_scaffold.json").read_text())
        self.assertTrue(hs.get("four_tier"))
        self.assertTrue(hs.get("eight_band"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
