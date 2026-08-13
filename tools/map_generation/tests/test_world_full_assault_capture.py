#!/usr/bin/env python3
"""Pure: world_full assault capture ownership wiring + GER–FRA edge."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullAssaultCaptureWiring(unittest.TestCase):
    def test_outcome_capture_symbols(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("province_control_change", bm)
        self.assertIn("update_province_owner", bm)
        self.assertIn("func apply_combat_outcome", bm)
        self.assertIn("func can_assault_province", bm)
        self.assertIn("func execute_province_assault", bm)
        cr = (ROOT / "scripts" / "combat" / "CombatResolver.gd").read_text(encoding="utf-8")
        self.assertIn("province_control_change", cr)
        # Winner from final scores (capture consistent with score bias)
        self.assertIn("Winner / capture from **final** scores", cr)

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

    def test_headless_capture_test_drives_shipped_apis(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessWorldFullAssaultCaptureTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "can_assault_province",
            "execute_province_assault",
            "apply_combat_outcome",
            "update_province_owner",
            "province_control_change",
            "daily_formation_reinforce_from_stockpile",
            "stationed_province_id",
            "9276",
            "9281",
        ):
            self.assertIn(needle, src, msg=needle)

    def test_capture_path_stations_attacker(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("_station_attacker_on_captured_province", bm)
        self.assertIn("stationed_province_id = target_pid", bm)


if __name__ == "__main__":
    unittest.main(verbosity=2)
