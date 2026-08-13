#!/usr/bin/env python3
"""Pure: post-capture full slot save_game_detailed / load_game_detailed wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCapturePostLoadSlotSaveLoadWiring(unittest.TestCase):
    def test_slot_apis_in_saveload_manager(self) -> None:
        sl = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        self.assertIn("func save_game_detailed", sl)
        self.assertIn("func load_game_detailed", sl)
        self.assertIn("func get_save_path", sl)
        self.assertIn("func _gather_save_data", sl)
        self.assertIn("func _apply_save_data", sl)
        self.assertIn("func _serialize_map_state", sl)
        self.assertIn("ProductionManager.get_save_data", sl)
        self.assertIn("LeaderManager.get_save_data", sl)

    def test_leader_design_id(self) -> None:
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn('"design_id"', lm)
        self.assertIn("f.design_id", lm)

    def test_world_full_edge(self) -> None:
        adj = json.loads((WF / "province_adjacency.json").read_text()).get("adjacency") or {}
        self.assertIn(TO_PID, [int(x) for x in adj.get(str(FROM_PID), [])])
        owners = {
            int(p["id"]): str(p.get("owner_tag") or "").upper()
            for p in json.loads(SCEN.read_text()).get("provinces") or []
            if isinstance(p, dict)
        }
        self.assertEqual(owners.get(FROM_PID), "GER")
        self.assertEqual(owners.get(TO_PID), "FRA")

    def test_headless_drives_slot_saveload(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "save_game_detailed",
            "load_game_detailed",
            "get_save_path",
            "can_assault_province",
            "design_id",
            "9276",
            "9281",
            "e1",
            "e2",
            "e3",
            "country_equipment",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
