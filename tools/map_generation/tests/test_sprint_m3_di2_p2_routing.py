#!/usr/bin/env python3
"""Structural routing honesty for sprint M3 measured · Di2 · P2."""
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
from map_perf_measured_primary_command_product import LIVE_API_BY_STEP as M3, map_perf_measured_primary_command_integrity
from war_goal_alliance_primary_command_product import LIVE_API_BY_STEP as DI2, war_goal_alliance_primary_command_integrity
from factory_retool_primary_command_product import LIVE_API_BY_STEP as P2, factory_retool_primary_command_integrity

def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m: return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]

class TestSprintM3Di2P2Routing(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(map_perf_measured_primary_command_integrity().get("ok"))
        self.assertTrue(war_goal_alliance_primary_command_integrity().get("ok"))
        self.assertTrue(factory_retool_primary_command_integrity().get("ok"))
    def test_gamedata_funcs(self):
        gd = GD.read_text(encoding="utf-8")
        for name in (
            "apply_map_perf_sample_frames_live", "apply_map_perf_budget_30_live",
            "apply_map_perf_budget_60_live", "apply_map_perf_measured_close_live",
            "apply_map_perf_measured_primary_live",
            "apply_war_goal_alliance_primary_live", "apply_factory_retool_primary_live",
        ):
            self.assertIn("func %s(" % name, gd, msg=name)
    def test_sample_uses_performance_or_maprenderer(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_map_perf_sample_frames_live")
        self.assertIn("Performance.get_monitor", b)
        self.assertIn("TIME_PROCESS", b)
        self.assertNotIn('live_api = "apply_focus"', b)
    def test_m3_step_apis(self):
        for api in M3.values():
            self.assertNotIn("apply_focus", api)
    def test_di2_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_war_goal_alliance_primary_step_live")
        for api in DI2.values():
            self.assertIn(api, b)
            self.assertNotIn("apply_focus", api)
        self.assertNotIn('live_api = "apply_focus"', b)
    def test_p2_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_factory_retool_primary_step_live")
        for api in P2.values():
            self.assertIn(api, b)
            self.assertNotIn("apply_focus", api)
    def test_scenario_markers(self):
        sl = SL.read_text(encoding="utf-8")
        for m in ("map_perf_measured_primary_live=1", "war_goal_alliance_primary_live=1", "factory_retool_primary_live=1"):
            self.assertIn(m, sl)

if __name__ == "__main__":
    unittest.main()
