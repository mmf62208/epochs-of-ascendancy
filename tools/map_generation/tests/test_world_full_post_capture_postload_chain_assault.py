#!/usr/bin/env python3
"""Pure: post-load chain/flank assault + daily reinforce wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCapturePostLoadChainAssaultWiring(unittest.TestCase):
    def test_chain_and_saveload_apis(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func execute_chain_assault_or_flank", bm)
        self.assertIn("func can_assault_province", bm)
        sl = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        self.assertIn("func _serialize_map_state", sl)
        self.assertIn("func _apply_map_state", sl)
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn('"design_id"', lm)
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func daily_formation_reinforce_from_stockpile", pm)

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

    def test_headless_drives_postload_chain(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCapturePostLoadChainAssaultTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "execute_chain_assault_or_flank",
            "_serialize_map_state",
            "_apply_map_state",
            "get_save_data",
            "apply_save_data",
            "daily_formation_reinforce_from_stockpile",
            "design_id",
            "9276",
            "9281",
            "92991",
            "e1",
            "e2",
            "e3",
        ):
            self.assertIn(needle, src, msg=needle)
        self.assertIn("daily_formation_reinforce_from_stockpile()", src)


if __name__ == "__main__":
    unittest.main(verbosity=2)
