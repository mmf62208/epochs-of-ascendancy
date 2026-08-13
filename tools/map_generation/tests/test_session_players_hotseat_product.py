#!/usr/bin/env python3
"""Gates: SessionPlayers hotseat multiplayer foundation."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from session_players_hotseat_product import (  # noqa
    close_hotseat_session,
    session_players_hotseat_integrity,
    apply_session_step,
    _new_runtime,
)


class TestSessionPlayersHotseat(unittest.TestCase):
    def test_close_hotseat(self):
        r = close_hotseat_session()
        self.assertTrue(r.get("ok"), msg=r)
        self.assertGreaterEqual(int(r["runtime"].get("turn") or 0), 2)
        self.assertGreaterEqual(int(r["runtime"].get("commands_applied") or 0), 1)

    def test_rotate_changes_active(self):
        rt = _new_runtime()
        first = str(rt.get("active_tag"))
        apply_session_step(rt, "rotate")
        # after full cycle might return; at least turn increments
        self.assertGreaterEqual(int(rt.get("turn") or 0), 2)
        self.assertTrue(rt.get("active_tag"))
        # with 4 slots, one rotate should change tag unless only 1
        if len(rt.get("slots") or []) > 1:
            self.assertNotEqual(first, rt.get("active_tag"))

    def test_command_queue(self):
        rt = _new_runtime()
        apply_session_step(rt, "enqueue", {"action": "apply_focus"})
        self.assertEqual(len(rt.get("command_queue") or []), 1)
        apply_session_step(rt, "execute")
        self.assertEqual(len(rt.get("command_queue") or []), 0)
        self.assertGreaterEqual(int(rt.get("commands_applied") or 0), 1)

    def test_wired(self):
        g = session_players_hotseat_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        sp = (ROOT / "scripts" / "autoload" / "SessionPlayers.gd").read_text()
        pg = (ROOT / "project.godot").read_text()
        self.assertIn("apply_session_players_hotseat_live", gd)
        self.assertIn("session_players_hotseat_live=1", sl)
        self.assertIn("rotate_active_player", sp)
        self.assertIn("SessionPlayers=", pg)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_session_players_hotseat_product.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
