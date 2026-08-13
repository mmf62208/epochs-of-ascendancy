#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "WeatherTheaterDomain.gd"
from focus_tree_primary_command_product import LIVE_API_BY_STEP as T2, focus_tree_primary_command_integrity
from leader_theater_primary_command_product import LIVE_API_BY_STEP as L2, leader_theater_primary_command_integrity

def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m: return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]

class TestSprintT2L2G0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(focus_tree_primary_command_integrity().get("ok"))
        self.assertTrue(leader_theater_primary_command_integrity().get("ok"))
    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in ("apply_focus_tree_primary_live", "apply_leader_theater_primary_live",
                  "apply_focus_tree_primary_step_live", "apply_leader_theater_primary_step_live"):
            self.assertIn("func %s(" % n, gd)
    def test_t2_apis(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_focus_tree_primary_step_live")
        for api in T2.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
    def test_l2_apis(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_leader_theater_primary_step_live")
        for api in L2.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
    def test_g0_weather_domain(self):
        self.assertTrue(DOM.exists())
        self.assertIn("class_name WeatherTheaterDomain", DOM.read_text(encoding="utf-8"))
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("WeatherTheaterDomain", gd)
        b = body(gd, "apply_weather_theater_primary_step_live")
        self.assertIn("WeatherTheaterDomain", b)
    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("focus_tree_primary_live=1", sl)
        self.assertIn("leader_theater_primary_live=1", sl)

if __name__ == "__main__":
    unittest.main()
