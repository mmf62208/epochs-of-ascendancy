#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
DOM = ROOT / "scripts" / "core" / "FleetMultiDayDomain.gd"
MM = ROOT / "scripts" / "map" / "MapManager.gd"
MPF = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
OCP = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"

ACP = {
    "acp_board": "apply_agent_product_board",
    "acp_dispatch": "apply_agent_product_dispatch",
    "acp_counterplay": "apply_agent_product_counterplay",
    "acp_sequence": "apply_agent_campaign_sequence",
    "acp_product": "apply_agent_campaign_product",
}
GSC = {
    "gsc_product": "apply_grand_strategy_cycle_product",
    "gsc_scan": "apply_gs_cycle_scan",
    "gsc_rank": "apply_gs_cycle_rank",
    "gsc_execute": "apply_gs_cycle_execute",
    "gsc_close": "apply_grand_strategy_cycle_close_day",
}


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintACPGSCG0(unittest.TestCase):
    def test_gamedata_funcs(self):
        gd = GD.read_text(encoding="utf-8")
        for n in (
            "apply_agent_campaign_primary_live",
            "apply_grand_strategy_cycle_primary_live",
            "apply_agent_campaign_primary_step_live",
            "apply_grand_strategy_cycle_primary_step_live",
        ):
            self.assertIn("func %s(" % n, gd)

    def test_acp_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_agent_campaign_primary_step_live")
        for api in ACP.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_gsc_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_grand_strategy_cycle_primary_step_live")
        for api in GSC.values():
            self.assertIn(api, b)
            self.assertNotEqual(api, "apply_focus")
        self.assertNotIn('live_api = "apply_focus"', b)

    def test_g0_fleet_multi_day_domain(self):
        self.assertTrue(DOM.exists())
        dom = DOM.read_text(encoding="utf-8")
        self.assertIn("class_name FleetMultiDayDomain", dom)
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("FleetMultiDayDomain", gd)
        b = body(gd, "apply_fleet_multi_day_primary_step_live")
        self.assertIn("FleetMultiDayDomain", b)
        b2 = body(gd, "apply_fleet_multi_day_primary_live")
        self.assertIn("FleetMultiDayDomain", b2)

    def test_scenario(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("agent_campaign_primary_live=1", sl)
        self.assertIn("grand_strategy_cycle_primary_live=1", sl)

    def test_formatters_mm_ocp(self):
        mpf = MPF.read_text(encoding="utf-8")
        self.assertIn("static func agent_campaign_primary_command_product", mpf)
        self.assertIn("static func grand_strategy_cycle_primary_command_product", mpf)
        mm = MM.read_text(encoding="utf-8")
        self.assertIn("func apply_agent_campaign_primary_command_product", mm)
        self.assertIn("func apply_grand_strategy_cycle_primary_command_product", mm)
        ocp = OCP.read_text(encoding="utf-8")
        self.assertIn("_rebuild_agent_campaign_primary_command", ocp)
        self.assertIn("_rebuild_grand_strategy_cycle_primary_command", ocp)


if __name__ == "__main__":
    unittest.main()
