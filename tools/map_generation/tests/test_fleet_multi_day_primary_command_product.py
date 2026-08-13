#!/usr/bin/env python3
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from fleet_multi_day_primary_command_product import (
    LIVE_API_BY_STEP, build_fleet_multi_day_primary_command_product, close_fleet_multi_day_primary_command_package, fleet_multi_day_primary_command_integrity,
    primary_command_dead_audit, apply_fleet_multi_day_primary_command_step,
)
class TestFMDPrimary(unittest.TestCase):
    def test_build(self):
        p = build_fleet_multi_day_primary_command_product()
        self.assertFalse(p.get("empty"))
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("all_majors_ok"))
        self.assertEqual(len(p.get("steps") or []), 5)
    def test_no_focus(self):
        for api in LIVE_API_BY_STEP.values():
            self.assertNotEqual(api, "apply_focus")
    def test_dead_audit(self):
        self.assertTrue(primary_command_dead_audit().get("ok"))
    def test_close_integrity(self):
        self.assertTrue(close_fleet_multi_day_primary_command_package().get("ok"))
        self.assertTrue(fleet_multi_day_primary_command_integrity().get("ok"))
    def test_province(self):
        self.assertEqual(int(build_fleet_multi_day_primary_command_product(province_id=2).get("province_id")), 2)
    def test_step(self):
        r = apply_fleet_multi_day_primary_command_step("posture", 1)
        self.assertTrue(r.get("ok"))
        self.assertEqual(r.get("live_api"), LIVE_API_BY_STEP["fmd_posture"])
if __name__ == "__main__":
    unittest.main()
