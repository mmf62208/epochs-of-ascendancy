#!/usr/bin/env python3
"""Pure: post-capture follow-on can_assault from captured province wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureFollowOnAssaultWiring(unittest.TestCase):
    def test_bm_capture_path_still_stations_and_displaces(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_combat_outcome", bm)
        self.assertIn("func can_assault_province", bm)
        self.assertIn("func find_attack_source", bm)
        self.assertIn("func get_divisions_at_province", bm)
        self.assertIn("_station_attacker_on_captured_province", bm)
        self.assertIn("_displace_defender_from_captured_province", bm)
        self.assertIn("_land_formations_stationed_at", bm)

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

    def test_headless_follow_on_drives_shipped_apis(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessWorldFullPostCaptureFollowOnAssaultTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "apply_combat_outcome",
            "execute_province_assault",
            "can_assault_province",
            "get_divisions_at_province",
            "stationed_province_id",
            "from_province_id",
            "formation_id",
            "daily_formation_reinforce_from_stockpile",
            "9276",
            "9281",
            "92991",
        ):
            self.assertIn(needle, src, msg=needle)

    def test_headless_asserts_follow_on_from_captured(self) -> None:
        src = (
            ROOT / "scripts" / "core" / "HeadlessWorldFullPostCaptureFollowOnAssaultTest.gd"
        ).read_text(encoding="utf-8")
        self.assertIn("can_assault from captured province", src)
        self.assertIn("follow-on can_assault", src)


if __name__ == "__main__":
    unittest.main(verbosity=2)
