#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "TutorialSessionDomain.gd"
from tutorial_first_session_primary_command_product import LIVE_API_BY_STEP as U1, tutorial_first_session_primary_command_integrity
from multi_faction_ai_primary_command_product import LIVE_API_BY_STEP as A3, multi_faction_ai_primary_command_integrity

def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m: return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]

class TestSprintU1A3G0Routing(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(tutorial_first_session_primary_command_integrity().get("ok"))
        self.assertTrue(multi_faction_ai_primary_command_integrity().get("ok"))
    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in ("apply_tutorial_first_session_primary_live", "apply_multi_faction_ai_primary_live",
                  "apply_tutorial_first_session_primary_step_live", "apply_multi_faction_ai_primary_step_live"):
            self.assertIn("func %s(" % n, gd)
    def test_u1_no_focus_and_g0_domain(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_tutorial_first_session_primary_step_live")
        for api in U1.values():
            self.assertIn(api, b)
            self.assertNotIn("apply_focus", api)
        self.assertIn("TutorialSessionDomain", b)
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name TutorialSessionDomain", dom)
        self.assertIn("func apply_primary_step", dom)
        self.assertIn("func majors_ok_count", dom)
    def test_a3_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_multi_faction_ai_primary_step_live")
        for api in A3.values():
            self.assertIn(api, b)
            self.assertNotIn("apply_focus", api)
        self.assertNotIn('live_api = "apply_focus"', b)
    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("tutorial_first_session_primary_live=1", sl)
        self.assertIn("multi_faction_ai_primary_live=1", sl)
        self.assertIn("TutorialSessionDomain", sl)

if __name__ == "__main__":
    unittest.main()
