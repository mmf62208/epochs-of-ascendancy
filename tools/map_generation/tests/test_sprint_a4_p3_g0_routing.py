#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "DesignerSuiteDomain.gd"
from faction_personality_primary_command_product import LIVE_API_BY_STEP as A4, faction_personality_primary_command_integrity
from production_honesty_primary_command_product import LIVE_API_BY_STEP as P3, production_honesty_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintA4P3G0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(faction_personality_primary_command_integrity().get("ok"))
        self.assertTrue(production_honesty_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_faction_personality_primary_live",
            "apply_production_honesty_primary_live",
            "apply_faction_personality_primary_step_live",
            "apply_production_honesty_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_a4_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_faction_personality_primary_step_live")
        for api in A4.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_p3_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_production_honesty_primary_step_live")
        for api in P3.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_designer_suite_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name DesignerSuiteDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("DesignerSuiteDomain", gd)
        b = body(gd, "apply_designer_suite_primary_step_live")
        self.assertIn("DesignerSuiteDomain", b)
        b2 = body(gd, "apply_designer_suite_primary_live")
        self.assertIn("DesignerSuiteDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("faction_personality_primary_live=1", sl)
        self.assertIn("production_honesty_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
