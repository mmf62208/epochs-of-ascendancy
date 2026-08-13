#!/usr/bin/env python3
"""Pure: foreign design reinforce + combat power + equip-loss wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureForeignDesignCombatLoopWiring(unittest.TestCase):
    def test_reinforce_and_equip_loss_symbols(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func daily_formation_reinforce_from_stockpile", pm)
        self.assertIn("func get_formation_equipment_combat_stats", pm)
        self.assertIn("func apply_combat_equipment_loss", pm)
        self.assertIn("has_shortages", pm)
        self.assertIn("func get_formation_required_equipment", pm)

    def test_bm_assault_estimate_and_outcome_loss(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func can_assault_province", bm)
        self.assertIn("func _estimate_attack_power", bm)
        self.assertIn("func apply_combat_outcome", bm)
        self.assertIn("_apply_combat_equipment_loss_for_formation", bm)
        self.assertIn("update_province_owner(target_pid, attacker_tag, attacker_tag, false)", bm)

    def test_design_grant_on_capture(self) -> None:
        fm = (ROOT / "scripts" / "production" / "FactoryManager.gd").read_text(encoding="utf-8")
        self.assertIn("try_grant_captured_designs_from_factory", fm)
        dm = (ROOT / "scripts" / "production" / "DesignManager.gd").read_text(encoding="utf-8")
        self.assertIn("func has_acquired_design", dm)

    def test_world_full_edge_ownership(self) -> None:
        adj = json.loads((WF / "province_adjacency.json").read_text()).get("adjacency") or {}
        self.assertIn(TO_PID, [int(x) for x in adj.get(str(FROM_PID), [])])
        owners = {
            int(p["id"]): str(p.get("owner_tag") or "").upper()
            for p in json.loads(SCEN.read_text()).get("provinces") or []
            if isinstance(p, dict)
        }
        self.assertEqual(owners.get(FROM_PID), "GER")
        self.assertEqual(owners.get(TO_PID), "FRA")

    def test_headless_drives_three_elements(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "daily_formation_reinforce_from_stockpile",
            "get_formation_equipment_combat_stats",
            "can_assault_province",
            "attack_power",
            "apply_combat_equipment_loss",
            "apply_combat_outcome",
            "somua_s35_medium",
            "has_shortages",
            "9276",
            "9281",
            "e1",
            "e2",
            "e3",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
