#!/usr/bin/env python3
"""Pure: post-load combat equip cycle — loss, shortages, re-reinforce."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCapturePostLoadCombatEquipCycleWiring(unittest.TestCase):
    def test_production_equip_cycle_apis(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_combat_equipment_loss", pm)
        self.assertIn("func request_equipment_for_unit", pm)
        self.assertIn("func daily_formation_reinforce_from_stockpile", pm)
        self.assertIn("func get_formation_equipment_combat_stats", pm)
        self.assertIn("func get_save_data", pm)
        self.assertIn("func apply_save_data", pm)

    def test_leader_design_id_save(self) -> None:
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn('"design_id"', lm)
        self.assertIn("f.design_id", lm)

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

    def test_headless_drives_postload_equip_cycle(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCapturePostLoadCombatEquipCycleTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "apply_combat_equipment_loss",
            "get_formation_equipment_combat_stats",
            "request_equipment_for_unit",
            "daily_formation_reinforce_from_stockpile",
            "_serialize_map_state",
            "_apply_map_state",
            "get_save_data",
            "apply_save_data",
            "design_id",
            "9276",
            "9281",
            "e1",
            "e2",
            "e3",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
