#!/usr/bin/env python3
"""Pure/static: combat equipment shortage + reinforce-from-stockpile wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class TestCombatEquipWiring(unittest.TestCase):
    def test_production_manager_formation_combat_and_reinforce_apis(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        for needle in (
            "func get_formation_equipment_combat_stats",
            "func get_unit_on_hand_shortages",
            "func get_formation_required_equipment",
            "func daily_formation_reinforce_from_stockpile",
            "func auto_reinforce_unit_from_stockpile",
            "has_shortages",
            "daily_formation_reinforce_from_stockpile()",
        ):
            self.assertIn(needle, pm, msg=needle)
        # Daily tick runs reinforce after production
        idx = pm.find("func _on_game_day_advanced")
        self.assertGreaterEqual(idx, 0)
        slice_ = pm[idx : idx + 350]
        self.assertIn("daily_production_tick", slice_)
        self.assertIn("daily_formation_reinforce_from_stockpile", slice_)

    def test_combat_resolver_uses_formation_equipment_stats(self) -> None:
        cr = (ROOT / "scripts" / "combat" / "CombatResolver.gd").read_text(encoding="utf-8")
        self.assertIn("get_division_final_combat_stats", cr)
        self.assertIn("get_formation_equipment_combat_stats", cr)
        self.assertIn("has_shortages", cr)

    def test_headless_combat_equip_test_drives_shipped_apis(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessCombatEquipShortageTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "get_formation_equipment_combat_stats",
            "get_effective_combat_power",
            "auto_reinforce_unit_from_stockpile",
            "daily_formation_reinforce_from_stockpile",
            "has_shortages",
            "get_country_equipment_stockpile",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
