#!/usr/bin/env python3
"""Pure/static: integrated equip→loss→shortage→reinforce cycle wiring."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class TestCombatEquipCycleWiring(unittest.TestCase):
    def test_shipped_apis_present(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        cr = (ROOT / "scripts" / "combat" / "CombatResolver.gd").read_text(encoding="utf-8")
        for needle, src in [
            ("func apply_combat_equipment_loss", pm),
            ("func get_formation_equipment_combat_stats", pm),
            ("func daily_formation_reinforce_from_stockpile", pm),
            ("has_shortages", pm),
            ("func apply_combat_outcome", bm),
            ("_apply_combat_equipment_loss_for_formation", bm),
            ("get_formation_equipment_combat_stats", cr),
            ("has_shortages", cr),
        ]:
            self.assertIn(needle, src, msg=needle)

    def test_headless_cycle_drives_shipped_end_to_end(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessCombatEquipCycleTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "apply_combat_outcome",
            "get_formation_equipment_combat_stats",
            "get_effective_combat_power",
            "daily_formation_reinforce_from_stockpile",
            "has_shortages",
            "get_country_equipment_stockpile",
            "get_unit_equipment_stock",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
