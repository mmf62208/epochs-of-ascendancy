#!/usr/bin/env python3
"""Pure/static: combat equipment loss + reinforce rebuild wiring."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class TestCombatEquipmentLossWiring(unittest.TestCase):
    def test_production_manager_has_apply_combat_equipment_loss(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_combat_equipment_loss", pm)
        self.assertIn("func daily_formation_reinforce_from_stockpile", pm)
        self.assertIn("func auto_reinforce_unit_from_stockpile", pm)

    def test_battle_manager_outcome_calls_equipment_loss(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_combat_outcome", bm)
        self.assertIn("_apply_combat_equipment_loss_for_formation", bm)
        self.assertIn("apply_combat_equipment_loss", bm)

    def test_headless_drives_shipped_outcome_and_reinforce(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessCombatEquipmentLossTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "apply_combat_equipment_loss",
            "apply_combat_outcome",
            "daily_formation_reinforce_from_stockpile",
            "get_unit_equipment_stock",
            "get_country_equipment_stockpile",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
