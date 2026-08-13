#!/usr/bin/env python3
"""Gates: first-session hotkey contract (no F5/F9 save collision) + Help content."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from first_session_hotkeys_product import (  # noqa: E402
    DEFAULT_PLAYER_TAG,
    FIRST_SESSION_STEPS,
    build_first_session_hotkeys_product,
    build_hotkey_table,
    first_session_hotkeys_integrity,
    format_help_dialog_text,
    format_onboarding_toast,
)


class TestFirstSessionHotkeysProduct(unittest.TestCase):
    def test_table_has_war_and_session(self) -> None:
        table = build_hotkey_table()
        keys = {h["key"] for h in table}
        self.assertIn("B", keys)
        self.assertIn("Shift+I", keys)
        self.assertIn("G", keys)
        self.assertIn("Ctrl+S", keys)
        self.assertIn("Ctrl+L", keys)
        self.assertIn("F9", keys)
        self.assertIn("F5", keys)
        # Bare F5/F9 are mapmodes only
        session = {h["key"] for h in table if h["group"] == "session"}
        self.assertNotIn("F5", session)
        self.assertNotIn("F9", session)

    def test_help_text(self) -> None:
        t = format_help_dialog_text()
        self.assertIn("WarLoop", t)
        self.assertIn("Ctrl+S", t)
        self.assertIn("F9", t)
        self.assertIn("G", t)

    def test_onboarding_toast(self) -> None:
        toast = format_onboarding_toast(tag="GER")
        self.assertIn("GER", toast)
        self.assertIn("WarLoop", toast)
        self.assertIn("Ctrl+S", toast)

    def test_default_tag_ger(self) -> None:
        self.assertEqual(DEFAULT_PLAYER_TAG, "GER")
        self.assertGreaterEqual(len(FIRST_SESSION_STEPS), 5)

    def test_product_build(self) -> None:
        p = build_first_session_hotkeys_product(player_tag="GER", check_wiring=False)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("player_tag"), "GER")
        self.assertGreaterEqual(int(p.get("hotkey_n") or 0), 20)
        self.assertIn("Ctrl+S", p.get("help_text") or "")

    def test_integrity_no_wire(self) -> None:
        g = first_session_hotkeys_integrity(check_wiring=False)
        self.assertTrue(g.get("ok"), msg=g)

    def test_wiring_after_land(self) -> None:
        """Soft until agents land; when wires exist they must stay green."""
        p = build_first_session_hotkeys_product(check_wiring=True)
        # Core table always ok independent of partial wires during rollout
        self.assertNotIn("session_uses_bare_F5", p.get("fail") or [])
        self.assertNotIn("session_uses_bare_F9", p.get("fail") or [])
        # Prefer green wiring when files updated
        top = (ROOT / "scripts" / "ui" / "TopInfoBar.gd").read_text(encoding="utf-8")
        if "EOA_HOTKEY_CTRL_S" in top or (
            "keycode == KEY_S" in top and "ctrl_pressed" in top
        ):
            self.assertTrue(
                p.get("wiring", {}).get("save_uses_ctrl"),
                msg=p.get("wiring"),
            )
        runner = (ROOT / "scripts" / "core" / "TestRunner.gd").read_text(encoding="utf-8")
        if 'setup_solo_play("GER")' in runner:
            self.assertTrue(p.get("wiring", {}).get("default_ger"), msg=p.get("wiring"))


if __name__ == "__main__":
    unittest.main()
