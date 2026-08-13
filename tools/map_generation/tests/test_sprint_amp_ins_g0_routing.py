#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "FrontContinuityDomain.gd"
from air_multi_phase_primary_command_product import LIVE_API_BY_STEP as AMP, air_multi_phase_primary_command_integrity
from inspector_decision_primary_command_product import LIVE_API_BY_STEP as INS, inspector_decision_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintAMPINSG0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(air_multi_phase_primary_command_integrity().get("ok"))
        self.assertTrue(inspector_decision_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_air_multi_phase_primary_live",
            "apply_inspector_decision_primary_live",
            "apply_air_multi_phase_primary_step_live",
            "apply_inspector_decision_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_amp_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_air_multi_phase_primary_step_live")
        for api in AMP.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_ins_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_inspector_decision_primary_step_live")
        for api in INS.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_front_continuity_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name FrontContinuityDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("FrontContinuityDomain", gd)
        b = body(gd, "apply_front_continuity_primary_step_live")
        self.assertIn("FrontContinuityDomain", b)
        b2 = body(gd, "apply_front_continuity_primary_live")
        self.assertIn("FrontContinuityDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("air_multi_phase_primary_live=1", sl)
        self.assertIn("inspector_decision_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
