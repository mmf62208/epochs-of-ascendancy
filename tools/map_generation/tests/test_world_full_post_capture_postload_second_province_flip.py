#!/usr/bin/env python3
"""Pure: post-load second-province ownership flip wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCapturePostLoadSecondProvinceFlipWiring(unittest.TestCase):
    def test_combat_and_saveload_apis(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func execute_province_assault", bm)
        self.assertIn("func apply_combat_outcome", bm)
        self.assertIn("func can_assault_province", bm)
        sl = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        self.assertIn("func _serialize_map_state", sl)
        self.assertIn("func _apply_map_state", sl)
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn('"design_id"', lm)

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

    def test_headless_drives_second_flip(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "execute_province_assault",
            "apply_combat_outcome",
            "_serialize_map_state",
            "_apply_map_state",
            "province_control_change",
            "92991",
            "9276",
            "9281",
            "e1",
            "e2",
            "e3",
            "design_id",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
