"""Pure tests for reinforcement depth RF2–RF4 product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from reinforcement_depth_product import (
    build_reinforcement_depth_primary_command_product,
    primary_command_dead_audit,
)


class TestReinforcementDepth(unittest.TestCase):
    def test_audit_and_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_reinforcement_depth_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        self.assertTrue(p["hooks_ok"])
        self.assertTrue(p["non_instant_math"])
        self.assertTrue(p["combat_ok"])
        self.assertTrue(p["policy_ok"])
        self.assertTrue(p["era_ok"])
        self.assertIn("RF2", p["phases"])
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_reinforcement_depth_primary_live", gd)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("reinforcement_depth_primary_live=1", sl)
        pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func run_non_instant_reinforce_demo", pm)
        self.assertIn("func apply_training_policy_decision", pm)


if __name__ == "__main__":
    unittest.main()
