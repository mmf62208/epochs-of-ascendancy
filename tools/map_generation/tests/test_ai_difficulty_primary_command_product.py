#!/usr/bin/env python3
from __future__ import annotations
import unittest
from pathlib import Path
import sys

LIB = Path(__file__).resolve().parents[1] / "lib"
PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(LIB))

from ai_difficulty_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    PRIMARY_COMMAND_STEPS,
    apply_ai_difficulty_primary_command_step,
    build_ai_difficulty_primary_command_product,
    primary_command_dead_audit,
)


class TestAiDifficultyPrimary(unittest.TestCase):
    def test_build_majors_and_no_focus(self):
        p = build_ai_difficulty_primary_command_product(province_id=1)
        self.assertFalse(p.get("empty"))
        self.assertEqual(int(p.get("majors_ok_n", 0)), 5)
        self.assertEqual(int(p.get("dead_n", 0)), 0)
        self.assertTrue(p.get("all_majors_ok"))
        for step, api in LIVE_API_BY_STEP.items():
            self.assertNotEqual(api, "apply_focus", step)
            self.assertTrue(str(api).startswith("apply_"), api)

    def test_dead_audit_live_ids(self):
        audit = primary_command_dead_audit()
        self.assertEqual(int(audit["dead_n"]), 0)
        self.assertTrue(audit["ok"])

    def test_step_execute_and_runtime_preset(self):
        rt: dict = {}
        for step in PRIMARY_COMMAND_STEPS:
            res = apply_ai_difficulty_primary_command_step(step, 1, runtime=rt)
            self.assertTrue(res.get("ok"))
            self.assertEqual(res.get("live_api"), LIVE_API_BY_STEP[step])
        self.assertEqual(rt.get("preset"), "hard")  # last difficulty step before close is hard; close overwrites?
        # re-run hard after close path: close sets preset close
        self.assertIn(rt.get("preset"), ("hard", "close"))
        rt2: dict = {}
        apply_ai_difficulty_primary_command_step("aid_easy", 1, runtime=rt2)
        self.assertEqual(rt2.get("preset"), "easy")

    def test_gamedata_live_apis_exist(self):
        gd = (PROJECT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        for api in LIVE_API_BY_STEP.values():
            self.assertIn(f"func {api}", gd, api)
        self.assertIn("func apply_ai_difficulty_primary_step_live", gd)
        self.assertIn("func apply_ai_difficulty_primary_live", gd)
        self.assertIn("AiDifficultyDomain", gd)


if __name__ == "__main__":
    unittest.main()
