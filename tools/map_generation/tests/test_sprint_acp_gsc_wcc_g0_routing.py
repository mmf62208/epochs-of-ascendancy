#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
ACP = ROOT / "scripts" / "core" / "AgentCampaignDomain.gd"
GSC = ROOT / "scripts" / "core" / "GrandStrategyCycleDomain.gd"
WCC = ROOT / "scripts" / "core" / "WorldClassDomain.gd"


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#region|\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintAcpGscWccG0(unittest.TestCase):
    def test_domain_files(self):
        for p, name in [
            (ACP, "AgentCampaignDomain"),
            (GSC, "GrandStrategyCycleDomain"),
            (WCC, "WorldClassDomain"),
        ]:
            self.assertTrue(p.exists(), name)
            self.assertIn("class_name %s" % name, p.read_text(encoding="utf-8"))

    def test_agent_campaign_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_agent_campaign_primary_step_live")
        self.assertIn("AgentCampaignDomain", b)
        self.assertIn("live_api_final", b)
        self.assertNotIn("else leaf", b)
        b2 = body(gd, "apply_agent_campaign_primary_live")
        self.assertIn("AgentCampaignDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_grand_strategy_cycle_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_grand_strategy_cycle_primary_step_live")
        self.assertIn("GrandStrategyCycleDomain", b)
        self.assertIn("live_api_final", b)
        self.assertNotIn("else leaf", b)
        b2 = body(gd, "apply_grand_strategy_cycle_primary_live")
        self.assertIn("GrandStrategyCycleDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_world_class_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_world_class_primary_step_live")
        self.assertIn("WorldClassDomain", b)
        self.assertIn("live_api_final", b)
        self.assertNotIn("else leaf", b)
        b2 = body(gd, "apply_world_class_primary_live")
        self.assertIn("WorldClassDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_scenario_markers(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("agent_campaign_primary_live=1", sl)
        self.assertIn("grand_strategy_cycle_primary_live=1", sl)
        self.assertIn("world_class_primary_live=1", sl)

    def test_no_focus_step_live_api(self):
        gd = GD.read_text(encoding="utf-8")
        for fn in (
            "apply_agent_campaign_primary_step_live",
            "apply_grand_strategy_cycle_primary_step_live",
            "apply_world_class_primary_step_live",
        ):
            b = body(gd, fn)
            self.assertNotIn('live_api = "apply_focus"', b)


if __name__ == "__main__":
    unittest.main()
