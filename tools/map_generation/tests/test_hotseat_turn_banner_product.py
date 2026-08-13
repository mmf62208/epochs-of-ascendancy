#!/usr/bin/env python3
"""Gates: Hotseat turn banner polish (Master Plan Phase N1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from hotseat_turn_banner_product import (  # noqa: E402
    REQUIRED_UX_FIELDS,
    apply_hotseat_end_turn,
    build_hotseat_turn_banner_from_runtime,
    build_hotseat_turn_banner_product,
    close_hotseat_turn_banner_loop,
    format_hotseat_banner_text,
    hotseat_lock_audit,
    hotseat_turn_banner_dead_audit,
    hotseat_turn_banner_integrity,
)
from session_players_hotseat_product import (  # noqa: E402
    _new_runtime,
    apply_session_step,
    close_hotseat_session,
)


class TestHotseatLock(unittest.TestCase):
    def test_active_allowed(self):
        r = hotseat_lock_audit("USA", "USA")
        self.assertTrue(r.get("allowed"))
        self.assertTrue(r.get("non_active_locked"))

    def test_non_active_denied(self):
        r = hotseat_lock_audit("USA", "GER")
        self.assertFalse(r.get("allowed"))
        self.assertEqual(r.get("reason"), "non_active_locked")

    def test_empty_tags(self):
        self.assertFalse(hotseat_lock_audit("", "USA").get("allowed"))
        self.assertFalse(hotseat_lock_audit("USA", "").get("allowed"))


class TestBannerProduct(unittest.TestCase):
    def test_required_fields_and_dead_n_zero(self):
        p = build_hotseat_turn_banner_product(
            slots=[
                {"tag": "USA", "control": "human", "name": "P1"},
                {"tag": "GER", "control": "ai", "name": "AI GER"},
            ],
            active_tag="USA",
            turn=3,
            commands=[{"action": "apply_focus", "tag": "USA"}],
        )
        for field in REQUIRED_UX_FIELDS:
            self.assertIn(field, p, msg=field)
            self.assertIsNotNone(p.get(field), msg=field)
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertEqual(int(p.get("turn_index")), 3)
        self.assertEqual(p.get("active_tag"), "USA")
        self.assertEqual(int(p.get("command_journal_len")), 1)
        self.assertTrue(p.get("non_active_locked"))
        self.assertTrue(p.get("can_end_turn"))
        self.assertIn("Turn 3", str(p.get("banner_text")))
        self.assertIn("USA", str(p.get("banner_text")))
        self.assertIn("HUMAN", str(p.get("banner_text")))
        self.assertTrue(p.get("ok"))

    def test_ai_banner_locked_copy(self):
        p = build_hotseat_turn_banner_product(
            slots=[
                {"tag": "USA", "control": "human"},
                {"tag": "GER", "control": "ai"},
            ],
            active_tag="GER",
            turn=2,
            commands=[],
        )
        self.assertIn("AI (input locked)", str(p.get("banner_text")))
        self.assertFalse(p.get("is_active_human"))

    def test_dead_audit_missing_field(self):
        bad = {"slots": [], "active_tag": "USA"}
        audit = hotseat_turn_banner_dead_audit(bad)
        self.assertGreaterEqual(int(audit.get("dead_n", 0)), 1)
        self.assertFalse(audit.get("ok"))
        self.assertIn("banner_text", audit.get("dead") or [])

    def test_banner_text_formatter(self):
        t = format_hotseat_banner_text(1, "ENG", control="ai")
        self.assertEqual(t, "Hotseat · Turn 1 · Active ENG · AI (input locked)")


class TestComposeSession(unittest.TestCase):
    def test_from_runtime_after_enqueue(self):
        rt = _new_runtime()
        apply_session_step(rt, "enqueue", {"action": "apply_production"})
        p = build_hotseat_turn_banner_from_runtime(rt)
        self.assertEqual(int(p.get("command_journal_len")), 1)
        self.assertEqual(p.get("active_tag"), rt.get("active_tag"))
        self.assertEqual(int(p.get("turn_index")), int(rt.get("turn") or 1))
        self.assertEqual(int(p.get("dead_n", 1)), 0)

    def test_end_turn_rotates_and_flushes(self):
        rt = _new_runtime()
        first = str(rt.get("active_tag"))
        apply_session_step(rt, "enqueue", {"action": "apply_focus"})
        self.assertEqual(len(rt.get("command_queue") or []), 1)
        end = apply_hotseat_end_turn(rt, flush=True)
        self.assertTrue(end.get("ok"), msg=end)
        self.assertEqual(len(rt.get("command_queue") or []), 0)
        self.assertGreaterEqual(int(rt.get("turn") or 0), 2)
        if len(rt.get("slots") or []) > 1:
            self.assertNotEqual(first, rt.get("active_tag"))
        after = end.get("banner_after") or {}
        self.assertEqual(after.get("active_tag"), rt.get("active_tag"))

    def test_close_loop(self):
        r = close_hotseat_turn_banner_loop()
        self.assertTrue(r.get("ok"), msg=r)
        self.assertEqual(int(r.get("dead_n", 1)), 0)
        self.assertTrue((r.get("allow") or {}).get("allowed"))
        self.assertFalse((r.get("deny") or {}).get("allowed"))
        self.assertTrue((r.get("session_close") or {}).get("ok"))

    def test_session_foundation_still_closes(self):
        # Compose, don't fork: foundation product still passes.
        r = close_hotseat_session()
        self.assertTrue(r.get("ok"), msg=r)


class TestIntegrity(unittest.TestCase):
    def test_integrity(self):
        g = hotseat_turn_banner_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertEqual(int(g.get("dead_n", 1)), 0)
        self.assertTrue(g.get("wired"))

    def test_session_players_helpers(self):
        sp = (ROOT / "scripts" / "autoload" / "SessionPlayers.gd").read_text(encoding="utf-8")
        self.assertIn("func get_turn_banner_state", sp)
        self.assertIn("func is_command_allowed_for_tag", sp)
        self.assertIn("banner_text", sp)
        self.assertIn("non_active_locked", sp)
        self.assertIn("can_end_turn", sp)
        self.assertIn("command_journal_len", sp)

    def test_dual_live_wiring(self):
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_hotseat_turn_banner_live", gd)
        self.assertIn("is_command_allowed_for_tag", gd)
        self.assertIn("get_turn_banner_state", gd)
        self.assertIn("hotseat_turn_banner_live=1", sl)
        self.assertIn("apply_hotseat_turn_banner_live", sl)

    def test_top_info_bar_banner(self):
        top = (ROOT / "scripts" / "ui" / "TopInfoBar.gd").read_text(encoding="utf-8")
        self.assertIn("_refresh_hotseat_banner", top)
        self.assertIn("_on_hotseat_end_turn", top)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text(encoding="utf-8")
        self.assertIn("test_hotseat_turn_banner_product.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
