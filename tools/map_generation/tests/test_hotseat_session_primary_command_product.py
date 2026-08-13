#!/usr/bin/env python3
from __future__ import annotations
import unittest, sys
from pathlib import Path
LIB = Path(__file__).resolve().parents[1] / "lib"
PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(LIB))
from hotseat_session_primary_command_product import (
    LIVE_API_BY_STEP, PRIMARY_COMMAND_STEPS, build_hotseat_session_primary_command_product,
    apply_hotseat_session_primary_command_step, primary_command_dead_audit,
)

class TestHsp(unittest.TestCase):
    def test_build(self):
        p = build_hotseat_session_primary_command_product()
        self.assertEqual(p["majors_ok_n"], 5)
        self.assertEqual(p["dead_n"], 0)
        self.assertTrue(p.get("not_netcode"))
        for api in LIVE_API_BY_STEP.values():
            self.assertNotEqual(api, "apply_focus")
    def test_gamedata(self):
        gd = (PROJECT / "scripts/autoload/GameData.gd").read_text()
        for api in LIVE_API_BY_STEP.values():
            self.assertIn(f"func {api}", gd, api)
        self.assertIn("HotseatSessionDomain", gd)
        self.assertIn("hotseat_session_primary_live=1", (PROJECT/"scripts/core/ScenarioLoader.gd").read_text())
    def test_steps(self):
        rt={}
        for s in PRIMARY_COMMAND_STEPS:
            r=apply_hotseat_session_primary_command_step(s, runtime=rt)
            self.assertTrue(r["ok"])

if __name__=="__main__":
    unittest.main()
