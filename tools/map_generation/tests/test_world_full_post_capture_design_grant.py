#!/usr/bin/env python3
"""Pure: post-capture foreign design grant on factory capture wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureDesignGrantWiring(unittest.TestCase):
    def test_factory_capture_calls_design_grant(self) -> None:
        fm = (ROOT / "scripts" / "production" / "FactoryManager.gd").read_text(encoding="utf-8")
        self.assertIn("func capture_province_factories", fm)
        self.assertIn("try_grant_captured_designs_from_factory", fm)
        dm = (ROOT / "scripts" / "production" / "DesignManager.gd").read_text(encoding="utf-8")
        self.assertIn("func try_grant_captured_designs_from_factory", dm)
        self.assertIn("current_production_design", dm)
        self.assertIn("func grant_acquired_design", dm)
        self.assertIn("func has_acquired_design", dm)
        self.assertIn("ACQUISITION_CAPTURED", dm)

    def test_combat_capture_non_skip_owner_update(self) -> None:
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

    def test_headless_drives_capture_and_design_assert(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessWorldFullPostCaptureDesignGrantTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "apply_combat_outcome",
            "execute_province_assault",
            "register_factory",
            "current_production_design",
            "has_acquired_design",
            "somua_s35_medium",
            "is_seized",
            "daily_formation_reinforce_from_stockpile",
            "9276",
            "9281",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
