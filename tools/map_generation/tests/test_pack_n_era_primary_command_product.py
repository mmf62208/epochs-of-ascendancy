#!/usr/bin/env python3
from __future__ import annotations
import unittest, sys
from pathlib import Path
LIB = Path(__file__).resolve().parents[1] / "lib"
PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(LIB))
from pack_n_era_primary_command_product import (
    LIVE_API_BY_STEP, PRIMARY_COMMAND_STEPS, build_pack_n_era_primary_command_product,
    apply_pack_n_era_primary_command_step,
)

class TestPne(unittest.TestCase):
    def test_build(self):
        p = build_pack_n_era_primary_command_product()
        self.assertEqual(p["majors_ok_n"], 5)
        self.assertEqual(p["dead_n"], 0)
        for api in LIVE_API_BY_STEP.values():
            self.assertNotEqual(api, "apply_focus")
            self.assertTrue(api.startswith("apply_"))
    def test_gamedata(self):
        gd = (PROJECT / "scripts/autoload/GameData.gd").read_text()
        for api in LIVE_API_BY_STEP.values():
            self.assertIn(f"func {api}", gd, api)
        self.assertIn("PackNEraDomain", gd)
        self.assertIn("pack_n_era_primary_live=1", (PROJECT/"scripts/core/ScenarioLoader.gd").read_text())
    def test_steps(self):
        for s in PRIMARY_COMMAND_STEPS:
            self.assertTrue(apply_pack_n_era_primary_command_step(s)["ok"])

if __name__=="__main__":
    unittest.main()
