#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "BalanceDomain.gd"
MM = ROOT / "scripts" / "map" / "MapManager.gd"
MPF = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
OCP = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"

WCC = {
    "wcc_product": "apply_world_class_campaign_command_product",
    "wcc_scan": "apply_world_class_scan",
    "wcc_rank": "apply_world_class_rank",
    "wcc_execute": "apply_world_class_execute",
    "wcc_close": "apply_world_class_campaign_close_day",
}
MFC = {
    "mfc_product": "apply_multi_front_campaign_ai_product",
    "mfc_plan": "apply_multi_front_plan",
    "mfc_weekly": "apply_multi_front_weekly",
    "mfc_execute": "apply_multi_front_execute",
    "mfc_close": "apply_multi_front_campaign_ai_close_day",
}


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintWCCMFCG0(unittest.TestCase):
    def test_gamedata_funcs(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_world_class_primary_live",
            "apply_multi_front_primary_live",
            "apply_world_class_primary_step_live",
            "apply_multi_front_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_wcc_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_world_class_primary_step_live")
        for api in WCC.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_mfc_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_multi_front_primary_step_live")
        for api in MFC.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_balance_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name BalanceDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("BalanceDomain", gd)
        b = body(gd, "apply_balance_combat_supply_primary_step_live")
        self.assertIn("BalanceDomain", b)
        b2 = body(gd, "apply_balance_combat_supply_primary_live")
        self.assertIn("BalanceDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("world_class_primary_live=1", sl)
        self.assertIn("multi_front_primary_live=1", sl)

    def test_formatters_mm_ocp(self):
        mpf = MPF.read_text(encoding="utf-8")
        self.assertIn("static func world_class_primary_command_product", mpf)
        self.assertIn("static func multi_front_primary_command_product", mpf)
        mm = MM.read_text(encoding="utf-8")
        self.assertIn("func apply_world_class_primary_command_product", mm)
        self.assertIn("func apply_multi_front_primary_command_product", mm)
        ocp = OCP.read_text(encoding="utf-8")
        self.assertIn("_rebuild_world_class_primary_command", ocp)
        self.assertIn("_rebuild_multi_front_primary_command", ocp)


if __name__ == "__main__":
    unittest.main()
