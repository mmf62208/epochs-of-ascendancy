#!/usr/bin/env python3
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from grand_strategy_cycle_primary_command_product import (
    LIVE_API_BY_STEP, build_grand_strategy_cycle_primary_command_product,
    close_grand_strategy_cycle_primary_command_package, grand_strategy_cycle_primary_command_integrity,
    primary_command_dead_audit, apply_grand_strategy_cycle_primary_command_step,
)
class TestGSCPrimary(unittest.TestCase):
    def test_build(self):
        p = build_grand_strategy_cycle_primary_command_product()
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
        self.assertTrue(close_grand_strategy_cycle_primary_command_package().get("ok"))
        self.assertTrue(grand_strategy_cycle_primary_command_integrity().get("ok"))
    def test_province(self):
        self.assertEqual(int(build_grand_strategy_cycle_primary_command_product(province_id=2).get("province_id")), 2)
    def test_step(self):
        r = apply_grand_strategy_cycle_primary_command_step("scan", 1)
        self.assertTrue(r.get("ok"))
        self.assertEqual(r.get("live_api"), LIVE_API_BY_STEP["gsc_scan"])
if __name__ == "__main__":
    unittest.main()
