#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "ManpowerLawsDomain.gd"
from intel_network_primary_command_product import LIVE_API_BY_STEP as I2, intel_network_primary_command_integrity
from product_ux_primary_command_product import LIVE_API_BY_STEP as U2, product_ux_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintI2U2G0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(intel_network_primary_command_integrity().get("ok"))
        self.assertTrue(product_ux_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_intel_network_primary_live",
            "apply_product_ux_primary_live",
            "apply_intel_network_primary_step_live",
            "apply_product_ux_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_i2_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_intel_network_primary_step_live")
        for api in I2.values():
            self.assertIn(api, b)
            self.assertNotIn("apply_focus", api)
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_u2_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_product_ux_primary_step_live")
        for api in U2.values():
            self.assertIn(api, b)
            self.assertNotIn("apply_focus", api)
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_manpower_laws_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name ManpowerLawsDomain", dom)
        self.assertIn("static func apply_primary_step", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("ManpowerLawsDomain", gd)
        b = body(gd, "apply_manpower_laws_primary_step_live")
        self.assertIn("ManpowerLawsDomain", b)
        b2 = body(gd, "apply_manpower_laws_primary_live")
        self.assertIn("ManpowerLawsDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("intel_network_primary_live=1", sl)
        self.assertIn("product_ux_primary_live=1", sl)
        self.assertIn("_print_intel_network_primary_live_evidence", sl)
        self.assertIn("_print_product_ux_primary_live_evidence", sl)


if __name__ == "__main__":
    unittest.main()
