#!/usr/bin/env python3
"""Pure: post-capture conquest state save/load wiring (design, factory, stations)."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureSaveLoadConquestStateWiring(unittest.TestCase):
    def test_design_manager_saves_acquired_designs(self) -> None:
        dm = (ROOT / "scripts" / "production" / "DesignManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_save_data", dm)
        self.assertIn("func apply_save_data", dm)
        self.assertIn("acquired_designs", dm)
        self.assertIn("func has_acquired_design", dm)
        self.assertIn("try_grant_captured_designs_from_factory", dm)

    def test_factory_manager_saves_owner_and_seized(self) -> None:
        fm = (ROOT / "scripts" / "production" / "FactoryManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_save_data", fm)
        self.assertIn("func apply_save_data", fm)
        self.assertIn("is_seized", fm)
        self.assertIn("owner_tag", fm)
        self.assertIn("province_to_factories", fm)

    def test_leader_manager_saves_stations(self) -> None:
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_save_data", lm)
        self.assertIn("func apply_save_data", lm)
        self.assertIn("stationed_province_id", lm)
        self.assertIn("formations", lm)

    def test_capture_non_skip_path(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("update_province_owner(target_pid, attacker_tag, attacker_tag, false)", bm)
        mm = (ROOT / "scripts" / "map" / "MapManager.gd").read_text(encoding="utf-8")
        self.assertIn("FactoryManager.capture_province_factories", mm)

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

    def test_headless_drives_capture_then_saveload(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCaptureSaveLoadConquestStateTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "get_save_data",
            "apply_save_data",
            "has_acquired_design",
            "is_seized",
            "stationed_province_id",
            "apply_combat_outcome",
            "execute_province_assault",
            "somua_s35_medium",
            "9276",
            "9281",
            "e1",
            "e2",
            "e3",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
