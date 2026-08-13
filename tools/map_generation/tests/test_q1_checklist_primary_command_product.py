#!/usr/bin/env python3
from __future__ import annotations
import unittest, sys
from pathlib import Path
LIB=Path(__file__).resolve().parents[1]/"lib"; PROJECT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(LIB))
from q1_checklist_primary_command_product import LIVE_API_BY_STEP, PRIMARY_COMMAND_STEPS, build_q1_checklist_primary_command_product, apply_q1_checklist_primary_command_step
class TestQ1ChecklistDomain(unittest.TestCase):
    def test_build(self):
        p=build_q1_checklist_primary_command_product()
        self.assertEqual(int(p["majors_ok_n"]),5)
        self.assertEqual(int(p["dead_n"]),0)
        for api in LIVE_API_BY_STEP.values():
            self.assertNotEqual(api,"apply_focus")
            self.assertTrue(str(api).startswith("apply_"))
    def test_gamedata(self):
        gd=(PROJECT/"scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s"%api, gd, api)
        self.assertIn("Q1ChecklistDomain", gd)
        self.assertIn("func apply_q1_checklist_primary_step_live", gd)
        self.assertIn("func apply_q1_checklist_primary_live", gd)
        sl=(PROJECT/"scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("q1_checklist_primary_live=1", sl)
    def test_steps(self):
        for s in PRIMARY_COMMAND_STEPS:
            self.assertTrue(apply_q1_checklist_primary_command_step(s)["ok"])
if __name__=="__main__":
    unittest.main()
