#!/usr/bin/env python3
"""Gates: Command journal determinism primary package (N2)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from command_journal_primary_command_product import (
    LIVE_API_BY_STEP, PRIMARY_COMMAND_STEPS, SURFACE_KEYS, DEFAULT_JOURNAL_ACTIONS,
    apply_command_journal_primary_command_step, build_command_journal_primary_command_product,
    close_command_journal_primary_command_package, command_journal_primary_command_integrity,
    journal_fingerprint, primary_command_dead_audit,
)

class TestCommandJournalPrimary(unittest.TestCase):
    def test_five_surfaces_verify(self):
        p = build_command_journal_primary_command_product()
        self.assertEqual(len(SURFACE_KEYS), 5)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))
        self.assertTrue(p.get("verify_ok"))
        self.assertTrue(p.get("no_focus_batch"))
        self.assertEqual(int(p.get("dead_n", 1)), 0)
    def test_deterministic_fingerprint(self):
        a = build_command_journal_primary_command_product(seed=1936)
        b = build_command_journal_primary_command_product(seed=1936)
        self.assertEqual(a.get("fingerprint"), b.get("fingerprint"))
        c = build_command_journal_primary_command_product(seed=1940)
        # different seed changes fingerprint payload
        self.assertNotEqual(a.get("fingerprint"), c.get("fingerprint"))
        fp = journal_fingerprint([{"action": "apply_production", "province_id": 1, "tag": "USA", "turn": 1}], seed=1)
        self.assertEqual(len(str(fp)), 16)
    def test_no_apply_focus_in_batch_or_apis(self):
        p = build_command_journal_primary_command_product()
        for a in p.get("actions") or []:
            self.assertNotIn("apply_focus", a)
        for row in p.get("steps") or []:
            self.assertNotIn("apply_focus", str(row.get("live_api")))
        for a in DEFAULT_JOURNAL_ACTIONS:
            self.assertNotIn("apply_focus", a)
    def test_rejects_focus_if_passed(self):
        p = build_command_journal_primary_command_product(actions=["apply_focus", "apply_production"])
        self.assertTrue(p.get("no_focus_batch"))
        self.assertNotIn("apply_focus", p.get("actions") or [])
        self.assertIn("apply_production", p.get("actions") or [])
    def test_close_integrity(self):
        r = apply_command_journal_primary_command_step("enqueue", 1)
        self.assertEqual(r.get("live_api"), "apply_command_journal_enqueue_live")
        c = close_command_journal_primary_command_package()
        self.assertTrue(c.get("ok"))
        self.assertTrue(command_journal_primary_command_integrity().get("ok"))
    def test_plain_score(self):
        p = build_command_journal_primary_command_product(province_id=2, seed=1918)
        self.assertTrue(str(p.get("plain") or "").strip())
        self.assertGreaterEqual(float(p.get("score") or 0), 0.35)
        self.assertEqual(len(PRIMARY_COMMAND_STEPS), 5)
    def test_dead_audit(self):
        self.assertEqual(int(primary_command_dead_audit().get("dead_n", 1)), 0)

    def test_verify_fails_on_mutated_applied_trail(self):
        """Honest verify: pre-flush journal vs divergent applied trail must fail."""
        from command_journal_primary_command_product import verify_journal_trail
        good = build_command_journal_primary_command_product(seed=1936)
        self.assertTrue(good.get("verify_ok"))
        mutated = [
            {"action": "apply_assault", "province_id": 1, "tag": "USA", "turn": 1},
            {"action": "apply_production", "province_id": 1, "tag": "USA", "turn": 1},
        ]
        bad = build_command_journal_primary_command_product(seed=1936, mutate_applied=mutated)
        self.assertFalse(bad.get("verify_ok"), msg="mutated applied trail must fail verify")
        self.assertFalse(bool((bad.get("majors_ok") or {}).get("journal_primary_verify")))
        self.assertNotEqual(bad.get("fingerprint_pre"), bad.get("fingerprint_applied"))
        # Direct helper: same pre vs wrong applied
        pre = list(good.get("journal") or [])
        v = verify_journal_trail(pre, mutated, seed=1936)
        self.assertFalse(v.get("ok"))
        v_ok = verify_journal_trail(pre, list(good.get("applied_trail") or pre), seed=1936)
        self.assertTrue(v_ok.get("ok"))

    def test_verify_fails_when_apply_focus_in_applied(self):
        from command_journal_primary_command_product import verify_journal_trail
        pre = [
            {"action": "apply_production", "province_id": 1, "tag": "USA", "turn": 1},
        ]
        applied = [
            {"action": "apply_focus", "province_id": 1, "tag": "USA", "turn": 1},
        ]
        v = verify_journal_trail(pre, applied, seed=1)
        self.assertFalse(v.get("ok"))
        self.assertTrue(v.get("has_focus"))

if __name__ == "__main__":
    unittest.main()
