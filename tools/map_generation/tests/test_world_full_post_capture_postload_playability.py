#!/usr/bin/env python3
"""Pure: post-save/load restore still enables assault, reinforce, combat equip stats."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCapturePostLoadPlayabilityWiring(unittest.TestCase):
    def test_leader_saves_design_id(self) -> None:
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_save_data", lm)
        self.assertIn("func apply_save_data", lm)
        self.assertIn('"design_id"', lm)
        self.assertIn("f.design_id", lm)
        self.assertIn("air_design_id", lm)
        self.assertIn("naval_design_id", lm)
        self.assertIn("stationed_province_id", lm)

    def test_saveload_map_and_production(self) -> None:
        sl = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        self.assertIn("func _serialize_map_state", sl)
        self.assertIn("func _apply_map_state", sl)
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_save_data", pm)
        self.assertIn("func apply_save_data", pm)
        self.assertIn("country_equipment_stockpiles", pm)
        self.assertIn("unit_equipment_stock", pm)
        self.assertIn("func request_equipment_for_unit", pm)
        self.assertIn("func daily_formation_reinforce_from_stockpile", pm)
        self.assertIn("func get_formation_equipment_combat_stats", pm)

    def test_battle_can_assault(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func can_assault_province", bm)
        self.assertIn("func execute_province_assault", bm)
        self.assertIn("apply_combat_outcome", bm)

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

    def test_headless_drives_postload_playability(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCapturePostLoadPlayabilityTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "_serialize_map_state",
            "_apply_map_state",
            "get_save_data",
            "apply_save_data",
            "design_id",
            "can_assault_province",
            "daily_formation_reinforce_from_stockpile",
            "get_formation_equipment_combat_stats",
            "apply_combat_outcome",
            "9276",
            "9281",
            "e1",
            "e2",
            "e3",
        ):
            self.assertIn(needle, src, msg=needle)
        # Criterion 2: e2 must drive daily reinforce (design_id via OOB), not only request_equipment
        self.assertIn("daily_formation_reinforce_from_stockpile()", src)
        e2_idx = src.find("e2 daily_formation_reinforce")
        if e2_idx < 0:
            e2_idx = src.find("Element 2")
        self.assertGreater(e2_idx, 0, msg="e2 daily reinforce section missing")
        # request_equipment must not be the primary e2 path (hardcoded design)
        e2_block = src[e2_idx : e2_idx + 1200]
        self.assertIn("daily_formation_reinforce_from_stockpile", e2_block)
        self.assertNotIn("request_equipment_for_unit", e2_block)


if __name__ == "__main__":
    unittest.main(verbosity=2)
