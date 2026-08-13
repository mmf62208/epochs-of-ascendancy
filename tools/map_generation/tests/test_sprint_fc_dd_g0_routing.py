#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "LogisticsSupplyDomain.gd"
from front_continuity_primary_command_product import LIVE_API_BY_STEP as FC, front_continuity_primary_command_integrity
from designer_depth_primary_command_product import LIVE_API_BY_STEP as DD, designer_depth_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintFCDDG0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(front_continuity_primary_command_integrity().get("ok"))
        self.assertTrue(designer_depth_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_front_continuity_primary_live",
            "apply_designer_depth_primary_live",
            "apply_front_continuity_primary_step_live",
            "apply_designer_depth_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_fc_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_front_continuity_primary_step_live")
        for api in FC.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_dd_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_designer_depth_primary_step_live")
        for api in DD.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_logistics_supply_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name LogisticsSupplyDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("LogisticsSupplyDomain", gd)
        b = body(gd, "apply_logistics_supply_primary_step_live")
        self.assertIn("LogisticsSupplyDomain", b)
        b2 = body(gd, "apply_logistics_supply_primary_live")
        self.assertIn("LogisticsSupplyDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("front_continuity_primary_live=1", sl)
        self.assertIn("designer_depth_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
