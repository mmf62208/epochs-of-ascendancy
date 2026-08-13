#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "InspectorDecisionDomain.gd"
MM = ROOT / "scripts" / "map" / "MapManager.gd"
MPF = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
OCP = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"

NMP = {
    "nmp_product": "apply_naval_multi_phase_campaign_product",
    "nmp_posture": "apply_naval_phase_posture",
    "nmp_escort": "apply_naval_phase_escort",
    "nmp_strike": "apply_naval_phase_strike",
    "nmp_close": "apply_naval_multi_phase_close_day",
}
DPC = {
    "dpc_product": "apply_diplomacy_peace_campaign_product",
    "dpc_board": "apply_diplomacy_peace_board",
    "dpc_leverage": "apply_diplomacy_peace_leverage",
    "dpc_settle": "apply_diplomacy_peace_settle",
    "dpc_close": "apply_diplomacy_peace_close_day",
}


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintNMPDPCG0(unittest.TestCase):
    def test_gamedata_funcs(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_naval_multi_phase_primary_live",
            "apply_diplomacy_peace_primary_live",
            "apply_naval_multi_phase_primary_step_live",
            "apply_diplomacy_peace_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_nmp_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_naval_multi_phase_primary_step_live")
        for api in NMP.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_dpc_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_diplomacy_peace_primary_step_live")
        for api in DPC.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_inspector_decision_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name InspectorDecisionDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("InspectorDecisionDomain", gd)
        b = body(gd, "apply_inspector_decision_primary_step_live")
        self.assertIn("InspectorDecisionDomain", b)
        b2 = body(gd, "apply_inspector_decision_primary_live")
        self.assertIn("InspectorDecisionDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("naval_multi_phase_primary_live=1", sl)
        self.assertIn("diplomacy_peace_primary_live=1", sl)

    def test_formatters_mm_ocp(self):
        mpf = MPF.read_text(encoding="utf-8")
        self.assertIn("static func naval_multi_phase_primary_command_product", mpf)
        self.assertIn("static func diplomacy_peace_primary_command_product", mpf)
        mm = MM.read_text(encoding="utf-8")
        self.assertIn("func apply_naval_multi_phase_primary_command_product", mm)
        self.assertIn("func apply_diplomacy_peace_primary_command_product", mm)
        ocp = OCP.read_text(encoding="utf-8")
        self.assertIn("_rebuild_naval_multi_phase_primary_command", ocp)
        self.assertIn("_rebuild_diplomacy_peace_primary_command", ocp)


if __name__ == "__main__":
    unittest.main()
