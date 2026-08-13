#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "FactoryRetoolDomain.gd"
from hh_multi_month_primary_command_product import LIVE_API_BY_STEP as HH, hh_multi_month_primary_command_integrity
from logistics_supply_primary_command_product import LIVE_API_BY_STEP as LOG, logistics_supply_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintHHLogG0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(hh_multi_month_primary_command_integrity().get("ok"))
        self.assertTrue(logistics_supply_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_hh_multi_month_primary_live",
            "apply_logistics_supply_primary_live",
            "apply_hh_multi_month_primary_step_live",
            "apply_logistics_supply_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_hh_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_hh_multi_month_primary_step_live")
        for api in HH.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_log_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_logistics_supply_primary_step_live")
        for api in LOG.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_factory_retool_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name FactoryRetoolDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("FactoryRetoolDomain", gd)
        b = body(gd, "apply_factory_retool_primary_step_live")
        self.assertIn("FactoryRetoolDomain", b)
        b2 = body(gd, "apply_factory_retool_primary_live")
        self.assertIn("FactoryRetoolDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("hh_multi_month_primary_live=1", sl)
        self.assertIn("logistics_supply_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
