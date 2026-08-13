#!/usr/bin/env python3
"""Gates: P2 factory retool primary."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from factory_retool_primary_command_product import (
    LIVE_API_BY_STEP, build_factory_retool_primary_command_product,
    close_factory_retool_primary_command_package, factory_retool_primary_command_integrity,
    primary_command_dead_audit, PRIMARY_COMMAND_STEPS,
)
GD = ROOT / "scripts" / "autoload" / "GameData.gd"

class TestFactoryRetoolPrimary(unittest.TestCase):
    def test_five_majors(self):
        p = build_factory_retool_primary_command_product()
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertGreaterEqual(int(p.get("retool_days") or 0), 1)
    def test_live_apis_in_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s(" % api, gd, msg=api)
            self.assertNotIn("apply_focus", api)
    def test_no_apply_focus(self):
        p = build_factory_retool_primary_command_product()
        for row in p.get("steps") or []:
            self.assertNotIn("apply_focus", str(row.get("live_api")))
    def test_close_integrity(self):
        self.assertTrue(close_factory_retool_primary_command_package().get("ok"))
        self.assertTrue(factory_retool_primary_command_integrity().get("ok"))
    def test_dead_audit(self):
        self.assertEqual(int(primary_command_dead_audit().get("dead_n", 1)), 0)
    def test_plain(self):
        p = build_factory_retool_primary_command_product(province_id=2)
        self.assertTrue(str(p.get("plain") or "").strip())
        self.assertEqual(len(PRIMARY_COMMAND_STEPS), 5)

if __name__ == "__main__":
    unittest.main()
