#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "HistoricalOobDomain.gd"
MM = ROOT / "scripts" / "map" / "MapManager.gd"
MPF = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
OCP = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"

TRC = {
    "trc_product": "apply_tech_research_campaign_product",
    "trc_catalog": "apply_tech_research_catalog",
    "trc_priority": "apply_tech_research_priority",
    "trc_field": "apply_tech_research_field",
    "trc_close": "apply_tech_research_close_day",
}
FWP = {
    "fwp_product": "apply_focus_war_path_product",
    "fwp_pick": "apply_focus_war_pick",
    "fwp_path": "apply_focus_war_path_step",
    "fwp_commit": "apply_focus_war_commit",
    "fwp_close": "apply_focus_war_path_close_day",
}


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintTRCFWPG0(unittest.TestCase):
    def test_gamedata_funcs(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_tech_research_primary_live",
            "apply_focus_war_path_primary_live",
            "apply_tech_research_primary_step_live",
            "apply_focus_war_path_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_trc_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_tech_research_primary_step_live")
        for api in TRC.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_fwp_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_focus_war_path_primary_step_live")
        for api in FWP.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_historical_oob_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name HistoricalOobDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("HistoricalOobDomain", gd)
        b = body(gd, "apply_historical_oob_primary_step_live")
        self.assertIn("HistoricalOobDomain", b)
        b2 = body(gd, "apply_historical_oob_primary_live")
        self.assertIn("HistoricalOobDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("tech_research_primary_live=1", sl)
        self.assertIn("focus_war_path_primary_live=1", sl)

    def test_formatters_mm_ocp(self):
        mpf = MPF.read_text(encoding="utf-8")
        self.assertIn("static func tech_research_primary_command_product", mpf)
        self.assertIn("static func focus_war_path_primary_command_product", mpf)
        mm = MM.read_text(encoding="utf-8")
        self.assertIn("func apply_tech_research_primary_command_product", mm)
        self.assertIn("func apply_focus_war_path_primary_command_product", mm)
        ocp = OCP.read_text(encoding="utf-8")
        self.assertIn("_rebuild_tech_research_primary_command", ocp)
        self.assertIn("_rebuild_focus_war_path_primary_command", ocp)


if __name__ == "__main__":
    unittest.main()
