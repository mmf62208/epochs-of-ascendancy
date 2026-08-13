#!/usr/bin/env python3
"""Pure/static: assault estimate/pick prefers equipped land formations."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class TestAssaultEstimateEquipmentWiring(unittest.TestCase):
    def test_estimate_and_pick_use_equipment_aware_power(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func _estimate_attack_power", bm)
        self.assertIn("func _pick_strongest_division", bm)
        self.assertIn("get_effective_combat_power", bm)
        self.assertIn("formation_id, formation_id, formation_id", bm)
        self.assertIn("_estimate_attack_power(fid", bm)

    def test_headless_drives_estimate_pick_and_cycle(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessAssaultEstimateEquipmentTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "_estimate_attack_power",
            "_pick_strongest_division",
            "apply_combat_outcome",
            "daily_formation_reinforce_from_stockpile",
            "has_shortages",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
