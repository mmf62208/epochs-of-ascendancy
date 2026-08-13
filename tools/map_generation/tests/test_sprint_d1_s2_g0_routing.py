#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "LeaderTheaterDomain.gd"
from designer_suite_primary_command_product import LIVE_API_BY_STEP as D1, designer_suite_primary_command_integrity
from autosave_session_primary_command_product import LIVE_API_BY_STEP as S2, autosave_session_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintD1S2G0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(designer_suite_primary_command_integrity().get("ok"))
        self.assertTrue(autosave_session_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_designer_suite_primary_live",
            "apply_autosave_session_primary_live",
            "apply_designer_suite_primary_step_live",
            "apply_autosave_session_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_d1_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_designer_suite_primary_step_live")
        for api in D1.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_s2_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_autosave_session_primary_step_live")
        for api in S2.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_leader_theater_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name LeaderTheaterDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("LeaderTheaterDomain", gd)
        b = body(gd, "apply_leader_theater_primary_step_live")
        self.assertIn("LeaderTheaterDomain", b)
        b2 = body(gd, "apply_leader_theater_primary_live")
        self.assertIn("LeaderTheaterDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("designer_suite_primary_live=1", sl)
        self.assertIn("autosave_session_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
