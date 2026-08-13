"""Pure tests for RF5 reinforce story product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from reinforce_story_product import (
    build_reinforce_story_primary_command_product,
    primary_command_dead_audit,
)


class TestReinforceStory(unittest.TestCase):
    def test_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_reinforce_story_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_reinforce_story_primary_live", gd)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("reinforce_story_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
