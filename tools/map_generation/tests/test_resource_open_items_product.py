"""Pure tests for resource open items (plants UI, endgame, majors trade)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from resource_open_items_product import (  # noqa: E402
    apply_endgame_deposits,
    build_place_plant_action,
    build_plant_browser_rows,
    build_resource_browser,
    build_resource_open_items_primary_command_product,
    major_trade_unit_value,
    primary_command_dead_audit,
)


class TestResourceOpenItems(unittest.TestCase):
    def test_plant_browser_and_place(self):
        rows = build_plant_browser_rows([{"factory_type": "coal_plant", "size_tier": 2}])
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0]["can_upgrade"])
        self.assertEqual(rows[0]["next_size_tier"], 3)
        place = build_place_plant_action({"coal": 200.0})
        self.assertTrue(place.get("ok"))
        self.assertEqual(place.get("plant_type"), "coal_plant")

    def test_endgame_year_gate(self):
        early = apply_endgame_deposits(
            [{"province_id": 1, "owner_tag": "USA", "resources": {"uranium": 80.0}}],
            1936,
            {"USA": {"rule_flags": ["fusion_power_industry"]}},
        )
        self.assertEqual(early.get("skipped"), "year_gate")
        late = apply_endgame_deposits(
            [{"province_id": 1, "owner_tag": "USA", "resources": {"uranium": 80.0}}],
            2045,
            {"USA": {"rule_flags": ["fusion_power_industry"]}},
        )
        self.assertGreaterEqual(int(late.get("helium3_added", 0)), 1)

    def test_trade_scarcity_pricing(self):
        scarce = major_trade_unit_value("electronics", {"electronics": 5.0})
        plenty = major_trade_unit_value("electronics", {"electronics": 300.0})
        self.assertGreater(scarce, plenty)
        self.assertGreater(major_trade_unit_value("fuel"), major_trade_unit_value("steel"))

    def test_browser_hides_fissiles_until_unlock(self):
        ww1 = build_resource_browser({}, {}, 1918)
        self.assertFalse(any(m["id"] == "fissiles" for m in ww1["majors"]))
        nuke = build_resource_browser({}, {"rule_flags": ["nuclear_fuel"]}, 1950)
        self.assertTrue(any(m["id"] == "fissiles" for m in nuke["majors"]))

    def test_primary_and_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_resource_open_items_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        self.assertTrue(p["plants_ok"])
        self.assertTrue(p["endgame_ok"])
        self.assertTrue(p["trade_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_resource_open_items_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("resource_open_items_primary_live=1", sl)
        tm = (ROOT / "scripts" / "national" / "TradeManager.gd").read_text(encoding="utf-8")
        self.assertIn("func create_major_resource_trade", tm)
        self.assertIn("func build_major_resource_trade_board", tm)


if __name__ == "__main__":
    unittest.main()
