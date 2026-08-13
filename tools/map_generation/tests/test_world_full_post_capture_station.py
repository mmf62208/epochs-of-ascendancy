#!/usr/bin/env python3
"""Pure: post-capture attacker station wiring + GER–FRA edge."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureStationWiring(unittest.TestCase):
    def test_bm_stations_attacker_on_capture(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_combat_outcome", bm)
        self.assertIn("update_province_owner", bm)
        self.assertIn("_station_attacker_on_captured_province", bm)
        self.assertIn("stationed_province_id = target_pid", bm)
        # Capture path must call the station helper (not only FormationMovement).
        self.assertIn("_station_attacker_on_captured_province(attacker_formation_id, target_pid, attacker_tag)", bm)
        self.assertIn("FormationMovement.move_formation_to_province", bm)

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

    def test_headless_station_test_drives_shipped_apis(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessWorldFullPostCaptureStationTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "apply_combat_outcome",
            "execute_province_assault",
            "stationed_province_id",
            "update_province_owner",
            "province_control_change",
            "daily_formation_reinforce_from_stockpile",
            "9276",
            "9281",
        ):
            self.assertIn(needle, src, msg=needle)

    def test_capture_headless_also_asserts_station(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessWorldFullAssaultCaptureTest.gd"
        src = path.read_text(encoding="utf-8")
        self.assertIn("station_after", src)
        self.assertIn("attacker station should be captured province", src)


if __name__ == "__main__":
    unittest.main(verbosity=2)
