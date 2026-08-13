#!/usr/bin/env python3
"""Gates: Di2 war goal + alliance primary."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from war_goal_alliance_primary_command_product import (
    LIVE_API_BY_STEP, build_war_goal_alliance_primary_command_product,
    close_war_goal_alliance_primary_command_package, war_goal_alliance_primary_command_integrity,
    primary_command_dead_audit, PRIMARY_COMMAND_STEPS,
)
GD = ROOT / "scripts" / "autoload" / "GameData.gd"

class TestWarGoalAlliancePrimary(unittest.TestCase):
    def test_five_majors(self):
        p = build_war_goal_alliance_primary_command_product()
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertEqual(len(PRIMARY_COMMAND_STEPS), 5)
    def test_live_apis_in_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s(" % api, gd, msg=api)
            self.assertNotIn("apply_focus", api)
    def test_no_apply_focus(self):
        p = build_war_goal_alliance_primary_command_product()
        for row in p.get("steps") or []:
            self.assertNotIn("apply_focus", str(row.get("live_api")))
        for item in p.get("apply_queue") or []:
            self.assertNotEqual(str(item.get("action_id")), "apply_focus")
    def test_close_integrity(self):
        self.assertTrue(close_war_goal_alliance_primary_command_package().get("ok"))
        self.assertTrue(war_goal_alliance_primary_command_integrity().get("ok"))
    def test_dead_audit(self):
        self.assertEqual(int(primary_command_dead_audit().get("dead_n", 1)), 0)
    def test_plain(self):
        p = build_war_goal_alliance_primary_command_product(province_id=2)
        self.assertTrue(str(p.get("plain") or "").strip())
        self.assertGreaterEqual(float(p.get("score") or 0), 0.35)

if __name__ == "__main__":
    unittest.main()
