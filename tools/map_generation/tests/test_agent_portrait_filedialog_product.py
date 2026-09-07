#!/usr/bin/env python3
"""Gates: agent FileDialog portrait slot copies PNG to user:// only."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from agent_portrait_filedialog_product import (  # noqa: E402
    STOCK_FACES,
    USER_DIR,
    agent_portrait_filedialog_integrity,
    build_agent_portrait_filedialog_product,
    custom_portrait_user_path,
    dest_allowed_for_import,
    safe_portrait_agent_id,
    stock_sidecar_path,
)

SCREEN = ROOT / "scripts" / "ui" / "AgentAssignmentScreen.gd"


class TestAgentPortraitFileDialogProduct(unittest.TestCase):
    def test_safe_id_and_paths(self) -> None:
        self.assertEqual(safe_portrait_agent_id("GER/agent 1!"), "GERagent1")
        self.assertEqual(safe_portrait_agent_id("spy_01"), "spy_01")
        self.assertEqual(custom_portrait_user_path("spy_01"), "user://agent_portraits/spy_01.png")
        self.assertEqual(stock_sidecar_path("spy_01"), "user://agent_portraits/spy_01.stock")
        self.assertEqual(custom_portrait_user_path("!!!"), "")

    def test_dest_never_res_or_assets(self) -> None:
        self.assertTrue(dest_allowed_for_import("user://agent_portraits/a.png"))
        self.assertFalse(dest_allowed_for_import("res://assets/graphics/ui/x.png"))
        self.assertFalse(dest_allowed_for_import("res://agent_portraits/a.png"))
        self.assertFalse(dest_allowed_for_import("/home/me/assets/stolen.png"))
        self.assertFalse(dest_allowed_for_import(""))

    def test_six_stock_faces(self) -> None:
        self.assertEqual(len(STOCK_FACES), 6)
        self.assertEqual(USER_DIR, "user://agent_portraits")

    def test_product_ok(self) -> None:
        p = build_agent_portrait_filedialog_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS")
        self.assertEqual(int(p.get("stock_n") or 0), 6)

    def test_integrity(self) -> None:
        g = agent_portrait_filedialog_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_screen_wiring(self) -> None:
        src = SCREEN.read_text(encoding="utf-8")
        self.assertIn("FileDialog", src)
        self.assertIn("ACCESS_FILESYSTEM", src)
        self.assertIn("use_native_dialog = true", src)
        self.assertIn("user://agent_portraits", src)
        self.assertIn(".stock", src)
        self.assertIn("AGENT_PORTRAIT_SLOT_FRAME", src)
        p = build_agent_portrait_filedialog_product(check_wiring=True)
        for key in (
            "slot_36px",
            "six_stock_faces",
            "in_card_picker",
            "filedialog_native",
            "copy_user_only",
            "reset_deletes_custom",
            "delete_never_res",
            "close_does_not_wipe",
        ):
            self.assertTrue(p.get("wiring", {}).get(key), msg=(key, p.get("wiring"), p.get("fail")))


if __name__ == "__main__":
    unittest.main()
