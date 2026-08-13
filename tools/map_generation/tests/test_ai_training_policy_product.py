"""Pure tests for RF6 AI training policy product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from ai_training_policy_product import (
    ai_pick_pure,
    build_ai_training_policy_primary_command_product,
    primary_command_dead_audit,
)


class TestAiTrainingPolicy(unittest.TestCase):
    def test_picks(self):
        self.assertEqual(ai_pick_pure(True, 0.9, False, 1942), "wartime_crash")
        self.assertEqual(ai_pick_pure(False, 0.1, True, 1936), "volunteer_cadre")
        self.assertEqual(ai_pick_pure(True, 0.9, False, 2050, 0.8), "clone_batch_fill")

    def test_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_ai_training_policy_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)


if __name__ == "__main__":
    unittest.main()
