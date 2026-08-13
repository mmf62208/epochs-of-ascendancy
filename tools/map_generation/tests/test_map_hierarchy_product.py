#!/usr/bin/env python3
"""Gates: map hierarchy scaffold province→state→region→super (real state names)."""
from __future__ import annotations
import sys, unittest, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from map_hierarchy_product import *  # noqa
from state_name_gazetteer import assert_names_shippable, is_placeholder_state_name  # noqa

DATA = ROOT / "data" / "provinces_world_full"

class TestHierarchy(unittest.TestCase):
    def test_build(self):
        h = build_hierarchy_scaffold(DATA)
        self.assertFalse(h.get("empty"))
        self.assertGreaterEqual(int(h.get("state_n", 0)), 40)
        self.assertGreaterEqual(int(h.get("region_n", 0)), 8)
        self.assertGreaterEqual(int(h.get("land_n", 0)), 1000)
        names = [str(s.get("name", "")) for s in (h.get("states") or [])]
        gate = assert_names_shippable(names)
        self.assertTrue(gate.get("ok"), msg=gate)

    def test_files(self):
        st = json.loads((DATA / "province_states.json").read_text())
        states = st.get("states") or []
        self.assertGreaterEqual(len(states), 40)
        names = [s.get("name", "") for s in states]
        # Honest gate: reject Area N / TAG · … / State N placeholders on ALL states.
        gate = assert_names_shippable(names)
        self.assertTrue(gate.get("ok"), msg=gate)
        self.assertEqual(int(gate.get("placeholder_n") or 0), 0)
        # Sample must look like real place labels (not algorithmic Area pattern).
        self.assertTrue(any(n in names for n in ("Maghreb Coast", "Flanders", "Brandenburg", "New England", "Île-de-France", "Lombardy", "Nile Valley", "Manchuria", "Kazakh Steppe", "Atlas Mountains")))
        self.assertFalse(any(is_placeholder_state_name(n) for n in names))
        hs = json.loads((DATA / "hierarchy_scaffold.json").read_text())
        self.assertTrue((DATA / "hierarchy_scaffold.json").is_file())
        self.assertTrue(hs.get("province_to_super_region"), msg="super_region bindings required")
        self.assertTrue(hs.get("four_tier") or hs.get("province_to_super_region"))

    def test_integrity(self):
        g = hierarchy_integrity(DATA)
        self.assertTrue(g.get("ok"), msg=g)

    def test_loader_super_region_query(self):
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("get_hierarchy_for_province", sl)
        self.assertIn("super_region_id", sl)
        self.assertIn("super_region_name", sl)
        self.assertIn("get_province_super_region_id", sl)
        self.assertIn("province_to_super_region", sl)
        self.assertIn("hierarchy_query", sl)

if __name__ == "__main__":
    unittest.main(verbosity=2)
