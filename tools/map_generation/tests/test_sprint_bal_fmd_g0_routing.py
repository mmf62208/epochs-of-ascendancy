#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "AirMultiPhaseDomain.gd"
from balance_combat_supply_primary_command_product import LIVE_API_BY_STEP as BAL, balance_combat_supply_primary_command_integrity
from fleet_multi_day_primary_command_product import LIVE_API_BY_STEP as FMD, fleet_multi_day_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintBALFMDG0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(balance_combat_supply_primary_command_integrity().get("ok"))
        self.assertTrue(fleet_multi_day_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_balance_combat_supply_primary_live",
            "apply_fleet_multi_day_primary_live",
            "apply_balance_combat_supply_primary_step_live",
            "apply_fleet_multi_day_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_bal_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_balance_combat_supply_primary_step_live")
        for api in BAL.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_fmd_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_fleet_multi_day_primary_step_live")
        for api in FMD.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_air_multi_phase_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name AirMultiPhaseDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("AirMultiPhaseDomain", gd)
        b = body(gd, "apply_air_multi_phase_primary_step_live")
        self.assertIn("AirMultiPhaseDomain", b)
        b2 = body(gd, "apply_air_multi_phase_primary_live")
        self.assertIn("AirMultiPhaseDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("balance_combat_supply_primary_live=1", sl)
        self.assertIn("fleet_multi_day_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
