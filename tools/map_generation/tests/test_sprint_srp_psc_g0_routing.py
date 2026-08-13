#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "ProductionHonestyDomain.gd"
MM = ROOT / "scripts" / "map" / "MapManager.gd"
MPF = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
OCP = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"

SRP = {
    "srp_product": "apply_save_resume_campaign_product",
    "srp_checkpoint": "apply_save_resume_checkpoint",
    "srp_save": "apply_save_resume_save",
    "srp_resume": "apply_save_resume_resume",
    "srp_close": "apply_save_resume_campaign_close_day",
}
PSC = {
    "psc_product": "apply_play_session_campaign_product",
    "psc_brief": "apply_play_session_brief",
    "psc_execute": "apply_play_session_execute",
    "psc_resolve": "apply_play_session_resolve",
    "psc_close": "apply_play_session_campaign_close_day",
}


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintSRPPSCG0(unittest.TestCase):
    def test_gamedata_funcs(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_save_resume_primary_live",
            "apply_play_session_primary_live",
            "apply_save_resume_primary_step_live",
            "apply_play_session_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_srp_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_save_resume_primary_step_live")
        for api in SRP.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_psc_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_play_session_primary_step_live")
        for api in PSC.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_production_honesty_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name ProductionHonestyDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("ProductionHonestyDomain", gd)
        b = body(gd, "apply_production_honesty_primary_step_live")
        self.assertIn("ProductionHonestyDomain", b)
        b2 = body(gd, "apply_production_honesty_primary_live")
        self.assertIn("ProductionHonestyDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("save_resume_primary_live=1", sl)
        self.assertIn("play_session_primary_live=1", sl)

    def test_formatters_mm_ocp(self):
        mpf = MPF.read_text(encoding="utf-8")
        self.assertIn("static func save_resume_primary_command_product", mpf)
        self.assertIn("static func play_session_primary_command_product", mpf)
        mm = MM.read_text(encoding="utf-8")
        self.assertIn("func apply_save_resume_primary_command_product", mm)
        self.assertIn("func apply_play_session_primary_command_product", mm)
        ocp = OCP.read_text(encoding="utf-8")
        self.assertIn("_rebuild_save_resume_primary_command", ocp)
        self.assertIn("_rebuild_play_session_primary_command", ocp)


if __name__ == "__main__":
    unittest.main()
