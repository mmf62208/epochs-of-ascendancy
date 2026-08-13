#!/usr/bin/env python3
"""Gates: Air theater primary command package (C3)."""
from __future__ import annotations
import re
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from air_theater_primary_command_product import (
    LIVE_API_BY_STEP, PRIMARY_COMMAND_STEPS, SURFACE_KEYS,
    apply_air_theater_primary_command_step, air_theater_primary_command_integrity,
    build_air_theater_primary_command_product, close_air_theater_primary_command_package,
    primary_command_dead_audit,
)
GD = ROOT / "scripts" / "autoload" / "GameData.gd"

class TestAirTheaterPrimary(unittest.TestCase):
    def test_four_surfaces(self):
        self.assertEqual(len(SURFACE_KEYS), 4)
        p = build_air_theater_primary_command_product()
        self.assertEqual(int(p.get("majors_ok_n") or 0), 4)
        self.assertTrue(p.get("all_majors_ok"))
        self.assertEqual(int(p.get("dead_n", 1)), 0)
    def test_live_apis_exist_in_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for step, api in LIVE_API_BY_STEP.items():
            self.assertIn("func %s(" % api, gd, msg=api)
            self.assertNotIn("apply_focus", api)
    def test_structural_no_apply_focus(self):
        p = build_air_theater_primary_command_product()
        for row in p.get("steps") or []:
            self.assertNotIn("apply_focus", str(row.get("live_api")))
        for item in p.get("apply_queue") or []:
            self.assertNotEqual(str(item.get("action_id")), "apply_focus")
    def test_step_close_integrity(self):
        r = apply_air_theater_primary_command_step("recon", 1)
        self.assertTrue(r.get("ok"))
        self.assertEqual(r.get("live_api"), "apply_air_theater_recon")
        c = close_air_theater_primary_command_package()
        self.assertTrue(c.get("ok"))
        self.assertTrue(air_theater_primary_command_integrity().get("ok"))
    def test_plain_score(self):
        p = build_air_theater_primary_command_product(province_id=2, fuel=0.8)
        self.assertTrue(str(p.get("plain") or "").strip())
        self.assertGreaterEqual(float(p.get("score") or 0), 0.35)
        self.assertEqual(len(PRIMARY_COMMAND_STEPS), 4)
    def test_dead_audit(self):
        self.assertEqual(int(primary_command_dead_audit().get("dead_n", 1)), 0)

if __name__ == "__main__":
    unittest.main()
