"""Pure tests: space layer gates, graph, SpaceFlow interdict, colony strain, live hooks."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from space_layer_product import (  # noqa: E402
    bodies_for_unlocked_layers,
    build_space_layer_primary_command_product,
    colony_strain,
    interdict_attribution_plain,
    layer_unlocked,
    load_space_rules,
    open_corridors,
    primary_command_dead_audit,
    spaceflow_hit_chance,
    visible_layers,
)


class TestSpaceLayer(unittest.TestCase):
    def test_rules_model(self):
        r = load_space_rules()
        self.assertEqual(r["model"], "orbital_compact_ledger")
        self.assertGreaterEqual(len(r.get("layers") or []), 5)
        self.assertGreaterEqual(len(r.get("bodies") or []), 5)

    def test_gates_progressive(self):
        r = load_space_rules()
        earth = next(L for L in r["layers"] if L["id"] == "earth_surface")
        self.assertTrue(layer_unlocked(earth, [], []))
        near = next(L for L in r["layers"] if L["id"] == "near_earth")
        self.assertFalse(layer_unlocked(near, [], []))
        self.assertTrue(layer_unlocked(near, ["allow_satellites"], []))
        self.assertTrue(layer_unlocked(near, [], ["first_satellite"]))
        early = visible_layers([], [])
        self.assertEqual([x["id"] for x in early if x["unlocked"]], ["earth_surface"])

    def test_graph_and_corridors(self):
        bodies = bodies_for_unlocked_layers(["allow_satellites"], ["first_satellite"])
        ids = {b["id"] for b in bodies}
        self.assertIn("leo_band", ids)
        self.assertNotIn("mars", ids)
        cors = open_corridors(["allow_satellites", "allow_lunar_operations"], ["moon_landing"])
        self.assertGreaterEqual(len(cors), 2)

    def test_spaceflow_and_strain(self):
        self.assertIn("ASAT", interdict_attribution_plain("asat", "leo", "earth", "luna"))
        self.assertGreater(spaceflow_hit_chance(0.4), 0.1)
        st = colony_strain(10, 4, 1.0, 2.5)
        self.assertTrue(st["starvation_risk"])
        self.assertTrue(st["mc_over"])

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_space_layer_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_space_layer_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("space_layer_primary_live=1", sl)
        self.assertTrue((ROOT / "data" / "space" / "space_layer_rules.json").is_file())
        self.assertTrue((ROOT / "docs" / "SPACE_STRATEGIC_LAYER_DESIGN.md").is_file())


if __name__ == "__main__":
    unittest.main()
