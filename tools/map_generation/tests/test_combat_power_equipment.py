#!/usr/bin/env python3
"""Pure/static: equipment-aware combat power on BattleManager/CombatResolver paths."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class TestCombatPowerEquipmentWiring(unittest.TestCase):
    def test_battle_manager_estimate_passes_unit_id(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func _estimate_attack_power", bm)
        self.assertIn("get_effective_combat_power", bm)
        # unit_id and army_id both formation_id for equipment awareness
        self.assertIn("formation_id, formation_id, formation_id", bm)

    def test_resolve_combat_passes_army_as_unit_id(self) -> None:
        cr = (ROOT / "scripts" / "combat" / "CombatResolver.gd").read_text(encoding="utf-8")
        self.assertIn("func resolve_combat", cr)
        self.assertIn("attacker_army_id, attacker_army_id", cr)
        self.assertIn("defender_army_id, defender_army_id", cr)
        self.assertIn("has_shortages", cr)
        self.assertIn("get_formation_equipment_combat_stats", cr)

    def test_headless_power_test_drives_shipped_paths(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessCombatPowerEquipmentTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "get_effective_combat_power",
            "resolve_combat",
            "apply_combat_outcome",
            "daily_formation_reinforce_from_stockpile",
            "has_shortages",
            "attacker_score",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
