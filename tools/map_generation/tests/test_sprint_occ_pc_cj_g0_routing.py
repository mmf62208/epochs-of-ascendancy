#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
OCC = ROOT / "scripts" / "core" / "OccupationDomain.gd"
PC = ROOT / "scripts" / "core" / "PeaceConferenceDomain.gd"
CJ = ROOT / "scripts" / "core" / "CommandJournalDomain.gd"


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintOccPcCjG0(unittest.TestCase):
    def test_domain_files(self):
        self.assertTrue(OCC.exists())
        self.assertTrue(PC.exists())
        self.assertTrue(CJ.exists())
        self.assertIn("class_name OccupationDomain", OCC.read_text(encoding="utf-8"))
        self.assertIn("class_name PeaceConferenceDomain", PC.read_text(encoding="utf-8"))
        self.assertIn("class_name CommandJournalDomain", CJ.read_text(encoding="utf-8"))

    def test_occupation_g0(self):
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("OccupationDomain", gd)
        b = body(gd, "apply_occupation_primary_command_step_live")
        self.assertIn("OccupationDomain", b)
        self.assertIn("commit_state", b)
        b2 = body(gd, "apply_occupation_primary_command_live")
        self.assertIn("OccupationDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_peace_g0(self):
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("PeaceConferenceDomain", gd)
        b = body(gd, "apply_peace_conference_primary_command_step_live")
        self.assertIn("PeaceConferenceDomain", b)
        self.assertIn("commit_state", b)
        b2 = body(gd, "apply_peace_conference_primary_command_live")
        self.assertIn("PeaceConferenceDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_command_journal_g0(self):
        gd = GD.read_text(encoding="utf-8")
        self.assertIn("CommandJournalDomain", gd)
        b = body(gd, "apply_command_journal_primary_command_step_live")
        self.assertIn("CommandJournalDomain", b)
        b2 = body(gd, "apply_command_journal_primary_command_live")
        self.assertIn("CommandJournalDomain", b2)

    def test_scenario_markers(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("occupation_primary_live=1", sl)
        self.assertIn("peace_conference_primary_live=1", sl)
        self.assertIn("command_journal_primary_live=1", sl)

    def test_no_focus_in_live_apis(self):
        gd = GD.read_text(encoding="utf-8")
        for fn in (
            "apply_occupation_primary_command_step_live",
            "apply_peace_conference_primary_command_step_live",
            "apply_command_journal_primary_command_step_live",
        ):
            b = body(gd, fn)
            self.assertNotIn('live_api = "apply_focus"', b)


if __name__ == "__main__":
    unittest.main()
