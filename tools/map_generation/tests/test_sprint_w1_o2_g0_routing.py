#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "MultiFactionAIDomain.gd"
from weather_theater_primary_command_product import LIVE_API_BY_STEP as W1, weather_theater_primary_command_integrity
from manpower_laws_primary_command_product import LIVE_API_BY_STEP as O2, manpower_laws_primary_command_integrity

def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m: return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]

class TestSprintW1O2G0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(weather_theater_primary_command_integrity().get("ok"))
        self.assertTrue(manpower_laws_primary_command_integrity().get("ok"))
    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in ("apply_weather_theater_primary_live", "apply_manpower_laws_primary_live",
                  "apply_weather_theater_primary_step_live", "apply_manpower_laws_primary_step_live"):
            self.assertIn("func %s(" % n, gd)
    def test_w1_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_weather_theater_primary_step_live")
        for api in W1.values():
            self.assertIn(api, b)
            self.assertNotIn("apply_focus", api)
    def test_o2_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_manpower_laws_primary_step_live")
        for api in O2.values():
            self.assertIn(api, b)
            self.assertNotIn("apply_focus", api)
    def test_g0_multi_faction_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name MultiFactionAIDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("MultiFactionAIDomain", gd)
        b = body(gd, "apply_multi_faction_ai_primary_step_live")
        self.assertIn("MultiFactionAIDomain", b)
    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("weather_theater_primary_live=1", sl)
        self.assertIn("manpower_laws_primary_live=1", sl)

if __name__ == "__main__":
    unittest.main()
