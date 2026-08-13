#!/usr/bin/env python3
"""Routing gate for residual G0 domain extracts (14 packages)."""
from __future__ import annotations
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
CORE = ROOT / "scripts" / "core"

# (domain_class, step_fn, live_fn, marker substring)
PACKAGES = [
    ("CombatIntelEstimateDomain", "apply_combat_intel_estimate_primary_step_live",
     "apply_combat_intel_estimate_primary_live", "combat_intel_estimate_primary_live=1"),
    ("AutosaveSessionDomain", "apply_autosave_session_primary_step_live",
     "apply_autosave_session_primary_live", "autosave_session_primary_live=1"),
    ("DesignerDepthDomain", "apply_designer_depth_primary_step_live",
     "apply_designer_depth_primary_live", "designer_depth_primary_live=1"),
    ("MultiFrontDomain", "apply_multi_front_primary_step_live",
     "apply_multi_front_primary_live", "multi_front_primary_live=1"),
    ("StrategicWarGoalDomain", "apply_strategic_war_goal_primary_step_live",
     "apply_strategic_war_goal_primary_live", "strategic_war_goal_primary_live=1"),
    ("NavalSearchStrikeDomain", "apply_naval_search_strike_primary_step_live",
     "apply_naval_search_strike_primary_live", "naval_search_strike_primary_live=1"),
    ("WeatherCrisisDomain", "apply_weather_crisis_primary_step_live",
     "apply_weather_crisis_primary_live", "weather_crisis_primary_live=1"),
    ("CampaignAiMultiMonthDomain", "apply_campaign_ai_multi_month_primary_step_live",
     "apply_campaign_ai_multi_month_primary_live", "campaign_ai_multi_month_primary_live=1"),
    ("TechResearchDomain", "apply_tech_research_primary_step_live",
     "apply_tech_research_primary_live", "tech_research_primary_live=1"),
    ("FocusWarPathDomain", "apply_focus_war_path_primary_step_live",
     "apply_focus_war_path_primary_live", "focus_war_path_primary_live=1"),
    ("NavalMultiPhaseDomain", "apply_naval_multi_phase_primary_step_live",
     "apply_naval_multi_phase_primary_live", "naval_multi_phase_primary_live=1"),
    ("DiplomacyPeaceDomain", "apply_diplomacy_peace_primary_step_live",
     "apply_diplomacy_peace_primary_live", "diplomacy_peace_primary_live=1"),
    ("SaveResumeDomain", "apply_save_resume_primary_step_live",
     "apply_save_resume_primary_live", "save_resume_primary_live=1"),
    ("PlaySessionDomain", "apply_play_session_primary_step_live",
     "apply_play_session_primary_live", "play_session_primary_live=1"),
]


def body(src: str, name: str) -> str:
    m = re.search(
        r"func %s\b.*?(?=\nfunc |\nconst |\n#region|\n#endregion|\Z)" % re.escape(name),
        src,
        re.S,
    )
    return m.group(0) if m else ""


class TestResidualG0Queue(unittest.TestCase):
    def test_domain_files(self):
        for cls, *_ in PACKAGES:
            p = CORE / f"{cls}.gd"
            self.assertTrue(p.exists(), cls)
            txt = p.read_text(encoding="utf-8")
            self.assertIn(f"class_name {cls}", txt)
            self.assertIn("apply_primary_step", txt)
            self.assertIn("majors_ok_count", txt)

    def test_step_live_routes_to_domain(self):
        gd = GD.read_text(encoding="utf-8")
        for cls, step_fn, _live, _m in PACKAGES:
            b = body(gd, step_fn)
            self.assertTrue(b, step_fn)
            self.assertIn(cls, b, step_fn)
            self.assertIn("live_api_final", b, step_fn)
            self.assertIn("apply_primary_step", b, step_fn)
            self.assertNotIn('live_api = "apply_focus"', b, step_fn)

    def test_live_uses_majors_ok_count(self):
        gd = GD.read_text(encoding="utf-8")
        for cls, _s, live_fn, _m in PACKAGES:
            b = body(gd, live_fn)
            self.assertTrue(b, live_fn)
            self.assertIn(cls, b, live_fn)
            self.assertIn("majors_ok_count", b, live_fn)

    def test_scenario_markers(self):
        sl = SL.read_text(encoding="utf-8")
        for _c, _s, _l, marker in PACKAGES:
            self.assertIn(marker, sl, marker)


if __name__ == "__main__":
    unittest.main()
