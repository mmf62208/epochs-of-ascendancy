#!/usr/bin/env python3
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from logistics_supply_primary_command_product import (
    LIVE_API_BY_STEP, build_logistics_supply_primary_command_product, close_logistics_supply_primary_command_package, logistics_supply_primary_command_integrity,
    primary_command_dead_audit, apply_logistics_supply_primary_command_step,
)
class TestLOGPrimary(unittest.TestCase):
    def test_build(self):
        p = build_logistics_supply_primary_command_product()
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
        self.assertTrue(close_logistics_supply_primary_command_package().get("ok"))
        self.assertTrue(logistics_supply_primary_command_integrity().get("ok"))
    def test_province(self):
        self.assertEqual(int(build_logistics_supply_primary_command_product(province_id=2).get("province_id")), 2)
    def test_step(self):
        r = apply_logistics_supply_primary_command_step("route", 1)
        self.assertTrue(r.get("ok"))
        self.assertEqual(r.get("live_api"), LIVE_API_BY_STEP["log_route"])
if __name__ == "__main__":
    unittest.main()
