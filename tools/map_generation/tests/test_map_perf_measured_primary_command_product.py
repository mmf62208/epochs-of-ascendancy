#!/usr/bin/env python3
"""Gates: M3 measured FPS primary package."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from map_perf_measured_primary_command_product import (
    LIVE_API_BY_STEP, build_map_perf_measured_primary_command_product,
    close_map_perf_measured_primary_command_package, map_perf_measured_primary_command_integrity,
    primary_command_dead_audit,
)
GD = ROOT / "scripts" / "autoload" / "GameData.gd"

class TestMapPerfMeasuredPrimary(unittest.TestCase):
    def test_empty_honest_no_fake_budget(self):
        p = build_map_perf_measured_primary_command_product(frame_times_ms=[])
        self.assertTrue(p.get("empty"))
        self.assertFalse(p.get("measured_ok"))
        self.assertFalse(p.get("budget_ok_30"))
        self.assertFalse(p.get("budget_ok_60"))
        self.assertEqual(int(p.get("sample_n") or 0), 0)
    def test_measured_samples_pass_30(self):
        # ~16ms frames → ~60fps, pass both
        p = build_map_perf_measured_primary_command_product(frame_times_ms=[16.0, 15.5, 16.2, 15.8])
        self.assertFalse(p.get("empty"))
        self.assertTrue(p.get("measured_ok"))
        self.assertGreaterEqual(int(p.get("sample_n") or 0), 4)
        self.assertTrue(p.get("budget_ok_30"))
        self.assertTrue(p.get("budget_ok_60"))
    def test_measured_fail_slow_frames(self):
        p = build_map_perf_measured_primary_command_product(frame_times_ms=[50.0, 55.0, 48.0])
        self.assertTrue(p.get("measured_ok"))
        self.assertFalse(p.get("budget_ok_30"))
    def test_dead_and_no_focus(self):
        self.assertEqual(int(primary_command_dead_audit().get("dead_n", 1)), 0)
        for api in LIVE_API_BY_STEP.values():
            self.assertNotIn("apply_focus", api)
    def test_integrity(self):
        self.assertTrue(map_perf_measured_primary_command_integrity().get("ok"))
        c = close_map_perf_measured_primary_command_package(frame_times_ms=[20.0, 22.0, 19.0])
        self.assertTrue(c.get("ok"))
    def test_gamedata_will_have_sample_api_after_wire(self):
        # Structural: pure live_api names are stable contract
        self.assertEqual(LIVE_API_BY_STEP["map_perf_sample_frames"], "apply_map_perf_sample_frames_live")

if __name__ == "__main__":
    unittest.main()
