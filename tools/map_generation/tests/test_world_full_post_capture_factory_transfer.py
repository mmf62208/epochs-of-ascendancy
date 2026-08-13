#!/usr/bin/env python3
"""Pure: post-capture factory transfer wiring (MapManager → FactoryManager)."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureFactoryTransferWiring(unittest.TestCase):
    def test_mapmanager_owner_update_calls_factory_capture(self) -> None:
        mm = (ROOT / "scripts" / "map" / "MapManager.gd").read_text(encoding="utf-8")
        self.assertIn("func update_province_owner", mm)
        self.assertIn("skip_capture", mm)
        self.assertIn("FactoryManager.capture_province_factories", mm)
        # Non-skip path invokes capture
        self.assertIn("if not skip_capture", mm)

    def test_factory_manager_capture_sets_owner_and_seized(self) -> None:
        fm = (ROOT / "scripts" / "production" / "FactoryManager.gd").read_text(encoding="utf-8")
        self.assertIn("func capture_province_factories", fm)
        self.assertIn("f.owner_tag = new_owner", fm)
        self.assertIn("f.is_seized = true", fm)

    def test_bm_capture_uses_non_skip_owner_update(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_combat_outcome", bm)
        self.assertIn("update_province_owner(target_pid, attacker_tag, attacker_tag, false)", bm)

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

    def test_headless_drives_factory_transfer(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessWorldFullPostCaptureFactoryTransferTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "FactoryManager",
            "register_factory",
            "apply_combat_outcome",
            "execute_province_assault",
            "is_seized",
            "owner_tag",
            "daily_formation_reinforce_from_stockpile",
            "9276",
            "9281",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
