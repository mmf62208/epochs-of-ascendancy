#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "ConvoySealaneDomain.gd"
MM = ROOT / "scripts" / "map" / "MapManager.gd"
MPF = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
OCP = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"

WCR = {
    "wcr_product": "apply_weather_crisis_campaign_product",
    "wcr_forecast": "apply_weather_crisis_forecast",
    "wcr_gate": "apply_weather_crisis_gate_multi",
    "wcr_sustain": "apply_weather_crisis_sustain",
    "wcr_close": "apply_weather_crisis_campaign_close_day",
}
CAM = {
    "cam_product": "apply_campaign_ai_multi_month_product",
    "cam_board": "apply_campaign_ai_month_board",
    "cam_weekly": "apply_campaign_ai_weekly_plan",
    "cam_execute": "apply_campaign_ai_theater_execute",
    "cam_close": "apply_campaign_ai_multi_month_close_day",
}


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintWCRCAMG0(unittest.TestCase):
    def test_gamedata_funcs(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_weather_crisis_primary_live",
            "apply_campaign_ai_multi_month_primary_live",
            "apply_weather_crisis_primary_step_live",
            "apply_campaign_ai_multi_month_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_wcr_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_weather_crisis_primary_step_live")
        for api in WCR.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_cam_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_campaign_ai_multi_month_primary_step_live")
        for api in CAM.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_convoy_sealane_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name ConvoySealaneDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("ConvoySealaneDomain", gd)
        b = body(gd, "apply_convoy_sealane_primary_step_live")
        self.assertIn("ConvoySealaneDomain", b)
        b2 = body(gd, "apply_convoy_sealane_primary_live")
        self.assertIn("ConvoySealaneDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("weather_crisis_primary_live=1", sl)
        self.assertIn("campaign_ai_multi_month_primary_live=1", sl)

    def test_formatters_mm_ocp(self):
        mpf = MPF.read_text(encoding="utf-8")
        self.assertIn("static func weather_crisis_primary_command_product", mpf)
        self.assertIn("static func campaign_ai_multi_month_primary_command_product", mpf)
        mm = MM.read_text(encoding="utf-8")
        self.assertIn("func apply_weather_crisis_primary_command_product", mm)
        self.assertIn("func apply_campaign_ai_multi_month_primary_command_product", mm)
        ocp = OCP.read_text(encoding="utf-8")
        self.assertIn("_rebuild_weather_crisis_primary_command", ocp)
        self.assertIn("_rebuild_campaign_ai_multi_month_primary_command", ocp)


if __name__ == "__main__":
    unittest.main()
