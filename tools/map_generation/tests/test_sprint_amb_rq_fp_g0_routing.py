#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
AMB = ROOT / "scripts" / "core" / "AgentMissionBoardDomain.gd"
RQ = ROOT / "scripts" / "core" / "ResearchQueueDomain.gd"
FP = ROOT / "scripts" / "core" / "FactionPersonalityDomain.gd"


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#region|\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintAmbRqFpG0(unittest.TestCase):
    def test_domain_files(self):
        for p, name in [
            (AMB, "AgentMissionBoardDomain"),
            (RQ, "ResearchQueueDomain"),
            (FP, "FactionPersonalityDomain"),
        ]:
            self.assertTrue(p.exists(), name)
            self.assertIn("class_name %s" % name, p.read_text(encoding="utf-8"))

    def test_agent_mission_board_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_agent_mission_board_primary_command_step_live")
        self.assertIn("AgentMissionBoardDomain", b)
        self.assertNotIn('"leaf": leaf,\n' if False else "NEVER", b)  # noop
        b2 = body(gd, "apply_agent_mission_board_primary_command_live")
        self.assertIn("AgentMissionBoardDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_research_queue_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_research_queue_primary_command_step_live")
        self.assertIn("ResearchQueueDomain", b)
        b2 = body(gd, "apply_research_queue_primary_command_live")
        self.assertIn("ResearchQueueDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_faction_personality_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_faction_personality_primary_step_live")
        self.assertIn("FactionPersonalityDomain", b)
        self.assertNotIn('"leaf": leaf', b)
        b2 = body(gd, "apply_faction_personality_primary_live")
        self.assertIn("FactionPersonalityDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_scenario_markers(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("agent_mission_board_primary_live=1", sl)
        self.assertIn("research_queue_primary_live=1", sl)
        self.assertIn("faction_personality_primary_live=1", sl)

    def test_no_focus_step_live_api(self):
        gd = GD.read_text(encoding="utf-8")
        for fn in (
            "apply_agent_mission_board_primary_command_step_live",
            "apply_research_queue_primary_command_step_live",
            "apply_faction_personality_primary_step_live",
        ):
            b = body(gd, fn)
            self.assertNotIn('live_api = "apply_focus"', b)


if __name__ == "__main__":
    unittest.main()
