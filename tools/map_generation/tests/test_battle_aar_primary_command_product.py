#!/usr/bin/env python3
"""Gates: Battle AAR primary command package (C4)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from battle_aar_primary_command_product import (
    LIVE_API_BY_STEP, PRIMARY_COMMAND_STEPS, SURFACE_KEYS,
    apply_battle_aar_primary_command_step, battle_aar_primary_command_integrity,
    build_battle_aar_entries, build_battle_aar_primary_command_product,
    close_battle_aar_primary_command_package, primary_command_dead_audit,
)
GD = ROOT / "scripts" / "autoload" / "GameData.gd"

class TestBattleAARPrimary(unittest.TestCase):
    def test_five_surfaces(self):
        self.assertEqual(len(SURFACE_KEYS), 5)
        p = build_battle_aar_primary_command_product()
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))
        self.assertGreaterEqual(int(p.get("entry_n") or 0), 1)
        self.assertEqual(int(p.get("dead_n", 1)), 0)
    def test_existing_combat_apis_in_gamedata(self):
        gd = GD.read_text(encoding="utf-8")
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s(" % api, gd, msg=api)
            self.assertNotIn("apply_focus", api)
    def test_entries_from_shipped_builder(self):
        combat = {"score": 0.7, "overall": 0.7, "phase_actions": [{"phase": "engage"}], "recommendation": {"step": "press"}}
        entries = build_battle_aar_entries(combat, province_id=3)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["province_id"], 3)
        self.assertIn("key_factors", entries[0])
    def test_no_apply_focus(self):
        p = build_battle_aar_primary_command_product()
        for row in p.get("steps") or []:
            self.assertNotIn("apply_focus", str(row.get("live_api")))
    def test_close_integrity(self):
        r = apply_battle_aar_primary_command_step("record", 1)
        self.assertEqual(r.get("live_api"), "apply_combat_ops_close_live")
        c = close_battle_aar_primary_command_package()
        self.assertTrue(c.get("ok"))
        self.assertTrue(battle_aar_primary_command_integrity().get("ok"))
    def test_plain_score(self):
        p = build_battle_aar_primary_command_product(province_id=2)
        self.assertTrue(str(p.get("plain") or "").strip())
        self.assertGreaterEqual(float(p.get("score") or 0), 0.35)
        self.assertEqual(len(PRIMARY_COMMAND_STEPS), 5)
    def test_dead_audit(self):
        self.assertEqual(int(primary_command_dead_audit().get("dead_n", 1)), 0)

if __name__ == "__main__":
    unittest.main()
