#!/usr/bin/env python3
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from intel_network_primary_command_product import LIVE_API_BY_STEP, build_intel_network_primary_command_product, close_intel_network_primary_command_package, intel_network_primary_command_integrity, primary_command_dead_audit
GD = ROOT / "scripts" / "autoload" / "GameData.gd"

class T(unittest.TestCase):
    def test_majors(self):
        p = build_intel_network_primary_command_product()
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))
        self.assertEqual(int(p.get("dead_n", 1)), 0)
    def test_live_apis(self):
        gd = GD.read_text(encoding="utf-8")
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s(" % api, gd, msg=api)
            self.assertNotEqual(api, "apply_focus")
    def test_no_bare_apply_focus(self):
        p = build_intel_network_primary_command_product()
        for row in p.get("steps") or []:
            self.assertNotEqual(str(row.get("live_api")), "apply_focus")
    def test_close_integrity(self):
        self.assertTrue(close_intel_network_primary_command_package().get("ok"))
        self.assertTrue(intel_network_primary_command_integrity().get("ok"))
    def test_dead(self):
        self.assertEqual(int(primary_command_dead_audit().get("dead_n", 1)), 0)
    def test_plain(self):
        self.assertTrue(str(build_intel_network_primary_command_product(province_id=2).get("plain") or "").strip())

if __name__ == "__main__":
    unittest.main()
