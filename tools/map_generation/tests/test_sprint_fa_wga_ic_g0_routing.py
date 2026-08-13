#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
FA = ROOT / "scripts" / "core" / "FleetAutonomyDomain.gd"
WGA = ROOT / "scripts" / "core" / "WarGoalAllianceDomain.gd"
IC = ROOT / "scripts" / "core" / "IntelCounterDomain.gd"


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#region|\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintFaWgaIcG0(unittest.TestCase):
    def test_domain_files(self):
        for p, name in [
            (FA, "FleetAutonomyDomain"),
            (WGA, "WarGoalAllianceDomain"),
            (IC, "IntelCounterDomain"),
        ]:
            self.assertTrue(p.exists(), name)
            self.assertIn("class_name %s" % name, p.read_text(encoding="utf-8"))

    def test_fleet_autonomy_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_fleet_autonomy_primary_command_step_live")
        self.assertIn("FleetAutonomyDomain", b)
        self.assertIn("var leaf", b)
        b2 = body(gd, "apply_fleet_autonomy_primary_command_live")
        self.assertIn("FleetAutonomyDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_war_goal_alliance_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_war_goal_alliance_primary_step_live")
        self.assertIn("WarGoalAllianceDomain", b)
        self.assertNotIn("else leaf", b)
        b2 = body(gd, "apply_war_goal_alliance_primary_live")
        self.assertIn("WarGoalAllianceDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_intel_counter_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_intel_counter_primary_step_live")
        self.assertIn("IntelCounterDomain", b)
        self.assertNotIn("else leaf", b)
        b2 = body(gd, "apply_intel_counter_primary_live")
        self.assertIn("IntelCounterDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_scenario_markers(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("fleet_autonomy_primary_live=1", sl)
        self.assertIn("war_goal_alliance_primary_live=1", sl)
        self.assertIn("intel_counter_primary_live=1", sl)

    def test_no_focus_step_live_api(self):
        gd = GD.read_text(encoding="utf-8")
        for fn in (
            "apply_fleet_autonomy_primary_command_step_live",
            "apply_war_goal_alliance_primary_step_live",
            "apply_intel_counter_primary_step_live",
        ):
            b = body(gd, fn)
            self.assertNotIn('live_api = "apply_focus"', b)


if __name__ == "__main__":
    unittest.main()
