#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "IntelNetworkDomain.gd"
from historical_oob_primary_command_product import LIVE_API_BY_STEP as X1, historical_oob_primary_command_integrity
from intel_counter_primary_command_product import LIVE_API_BY_STEP as I3, intel_counter_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintX1I3G0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(historical_oob_primary_command_integrity().get("ok"))
        self.assertTrue(intel_counter_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_historical_oob_primary_live",
            "apply_intel_counter_primary_live",
            "apply_historical_oob_primary_step_live",
            "apply_intel_counter_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_x1_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_historical_oob_primary_step_live")
        for api in X1.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_i3_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_intel_counter_primary_step_live")
        for api in I3.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_intel_network_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name IntelNetworkDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("IntelNetworkDomain", gd)
        b = body(gd, "apply_intel_network_primary_step_live")
        self.assertIn("IntelNetworkDomain", b)
        b2 = body(gd, "apply_intel_network_primary_live")
        self.assertIn("IntelNetworkDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("historical_oob_primary_live=1", sl)
        self.assertIn("intel_counter_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
