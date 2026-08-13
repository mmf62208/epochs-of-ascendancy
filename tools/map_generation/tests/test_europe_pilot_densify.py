#!/usr/bin/env python3
"""Gates: Europe densify pilot geometry + hierarchy + 2026 ownership."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from europe_pilot_densify import europe_pilot_integrity, PILOT_ID_BASE  # noqa
from state_name_gazetteer import assert_names_shippable, is_placeholder_state_name  # noqa

PILOT = ROOT / "data" / "provinces_pilot_europe"
WORLD = ROOT / "data" / "provinces_world_full"


class TestEuropePilot(unittest.TestCase):
    def test_integrity(self):
        g = europe_pilot_integrity(PILOT)
        self.assertTrue(g.get("ok"), msg=g.get("summary"))

    def test_denser_than_europe_core_scaffold(self):
        geom = json.loads((PILOT / "provinces_geometry.json").read_text())
        meta = geom.get("meta") or {}
        land_before = int(meta.get("land_before") or 0)
        land_after = int(meta.get("land_after") or 0)
        self.assertEqual(land_before, 460)
        self.assertGreaterEqual(land_after, int(land_before * 1.5))
        self.assertGreaterEqual(len(geom.get("provinces") or []), 600)

    def test_id_namespace_no_collision(self):
        geom = json.loads((PILOT / "provinces_geometry.json").read_text())
        wgeom = json.loads((WORLD / "provinces_geometry.json").read_text())
        world_ids = {int(p["id"]) for p in wgeom["provinces"]}
        for p in geom["provinces"]:
            pid = int(p["id"])
            self.assertGreaterEqual(pid, PILOT_ID_BASE)
            self.assertNotIn(pid, world_ids)

    def test_mean_verts_and_hierarchy_names(self):
        geom = json.loads((PILOT / "provinces_geometry.json").read_text())
        verts = [len(p.get("points") or []) for p in geom["provinces"]]
        self.assertGreaterEqual(sum(verts) / max(1, len(verts)), 18)
        states = json.loads((PILOT / "province_states.json").read_text()).get("states") or []
        self.assertGreaterEqual(len(states), 40)
        names = [str(s.get("name", "")) for s in states]
        # Honest gate: reject ALL Area N / TAG · Region · Area patterns.
        gate = assert_names_shippable(names)
        self.assertTrue(gate.get("ok"), msg=gate)
        self.assertEqual(int(gate.get("placeholder_n") or 0), 0)
        self.assertFalse(any(is_placeholder_state_name(n) for n in names))
        # Real-ish European place labels present.
        real_samples = {
            "Flanders", "Brabant", "Île-de-France", "Normandy", "Bavaria", "Rhineland",
            "Lombardy", "Castile", "Thrace", "Bohemia", "Zealand", "Holland", "Wallonia",
            "Provence", "Saxony", "Tuscany", "Aragon",
        }
        self.assertTrue(real_samples.intersection(names), msg="expected real place-state samples, got %s" % names[:20])
        regions = json.loads((PILOT / "strategic_regions.json").read_text()).get("regions") or []
        self.assertGreaterEqual(len(regions), 6)
        self.assertTrue((PILOT / "super_regions.json").is_file())
        self.assertTrue((PILOT / "province_ownership_2026.json").is_file())
        hs = json.loads((PILOT / "hierarchy_scaffold.json").read_text())
        self.assertTrue(hs.get("province_to_super_region"), msg="pilot must bind super_region")
        self.assertTrue(hs.get("four_tier"))

    def test_scenario_and_loader_wiring(self):
        scen = json.loads((ROOT / "data" / "scenarios" / "world_pilot_europe.json").read_text())
        self.assertEqual(scen.get("use_province_data_dir"), "provinces_pilot_europe")
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("provinces_pilot_europe", sl)
        self.assertIn("get_hierarchy_for_province", sl)
        self.assertIn("super_region_id", sl)
        self.assertIn("super_region_name", sl)
        self.assertIn("get_province_super_region_id", sl)
        self.assertIn("super_regions", sl)
        self.assertIn("hierarchy_live", sl)
        self.assertIn("hierarchy_query", sl)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_europe_pilot_densify.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
