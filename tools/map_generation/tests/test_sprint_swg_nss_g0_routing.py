#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "ProductUxDomain.gd"
MM = ROOT / "scripts" / "map" / "MapManager.gd"
MPF = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
OCP = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"

SWG = {
    "swg_product": "apply_strategic_war_goal_product",
    "swg_board": "apply_war_goal_board",
    "swg_justify": "apply_war_goal_justify",
    "swg_execute": "apply_war_goal_execute",
    "swg_close": "apply_strategic_war_goal_close_day",
}
NSS = {
    "nss_product": "apply_naval_search_strike_product",
    "nss_patrol": "apply_naval_search_patrol",
    "nss_asw": "apply_naval_asw_escort",
    "nss_strike": "apply_naval_carrier_strike",
    "nss_close": "apply_naval_search_strike_close_day",
}


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintSWGNSSG0(unittest.TestCase):
    def test_gamedata_funcs(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_strategic_war_goal_primary_live",
            "apply_naval_search_strike_primary_live",
            "apply_strategic_war_goal_primary_step_live",
            "apply_naval_search_strike_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_swg_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_strategic_war_goal_primary_step_live")
        for api in SWG.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_nss_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_naval_search_strike_primary_step_live")
        for api in NSS.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_product_ux_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name ProductUxDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("ProductUxDomain", gd)
        b = body(gd, "apply_product_ux_primary_step_live")
        self.assertIn("ProductUxDomain", b)
        b2 = body(gd, "apply_product_ux_primary_live")
        self.assertIn("ProductUxDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("strategic_war_goal_primary_live=1", sl)
        self.assertIn("naval_search_strike_primary_live=1", sl)

    def test_formatters_mm_ocp(self):
        mpf = MPF.read_text(encoding="utf-8")
        self.assertIn("static func strategic_war_goal_primary_command_product", mpf)
        self.assertIn("static func naval_search_strike_primary_command_product", mpf)
        mm = MM.read_text(encoding="utf-8")
        self.assertIn("func apply_strategic_war_goal_primary_command_product", mm)
        self.assertIn("func apply_naval_search_strike_primary_command_product", mm)
        ocp = OCP.read_text(encoding="utf-8")
        self.assertIn("_rebuild_strategic_war_goal_primary_command", ocp)
        self.assertIn("_rebuild_naval_search_strike_primary_command", ocp)


if __name__ == "__main__":
    unittest.main()
