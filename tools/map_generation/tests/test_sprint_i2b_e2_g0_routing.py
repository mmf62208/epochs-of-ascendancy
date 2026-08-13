#!/usr/bin/env python3
from __future__ import annotations
import re, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "FocusTreeDomain.gd"
from combat_intel_estimate_primary_command_product import LIVE_API_BY_STEP as I2B, combat_intel_estimate_primary_command_integrity
from convoy_sealane_primary_command_product import LIVE_API_BY_STEP as E2, convoy_sealane_primary_command_integrity


def body(src, name):
    m = re.search(r"(?m)^func %s\b.*$" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    e = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    return src[m.start(): m.end() + (e.start() if e else len(rest))]


class TestSprintI2bE2G0(unittest.TestCase):
    def test_integrity(self):
        self.assertTrue(combat_intel_estimate_primary_command_integrity().get("ok"))
        self.assertTrue(convoy_sealane_primary_command_integrity().get("ok"))

    def test_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_combat_intel_estimate_primary_live",
            "apply_convoy_sealane_primary_live",
            "apply_combat_intel_estimate_primary_step_live",
            "apply_convoy_sealane_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_i2b_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_combat_intel_estimate_primary_step_live")
        for api in I2B.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)
        self.assertIn("intel_impact_visible", b)

    def test_e2_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_convoy_sealane_primary_step_live")
        for api in E2.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_focus_tree_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name FocusTreeDomain", dom)
        self.assertIn("static func apply_primary_step", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("FocusTreeDomain", gd)
        b = body(gd, "apply_focus_tree_primary_step_live")
        self.assertIn("FocusTreeDomain", b)
        b2 = body(gd, "apply_focus_tree_primary_live")
        self.assertIn("FocusTreeDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("combat_intel_estimate_primary_live=1", sl)
        self.assertIn("convoy_sealane_primary_live=1", sl)
        self.assertIn("_print_combat_intel_estimate_primary_live_evidence", sl)
        self.assertIn("_print_convoy_sealane_primary_live_evidence", sl)


if __name__ == "__main__":
    unittest.main()
