#!/usr/bin/env python3
"""Gates: OrderCommandPanel play-strip membership (no harness dual leak)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from order_panel_play_strip_product import (  # noqa: E402
    HARNESS_ACTION_IDS,
    PLAY_ACTIONS,
    build_order_panel_play_strip_product,
    is_harness_action,
    order_panel_play_strip_integrity,
    play_strip_actions,
    play_strip_membership_audit,
)

PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"


class TestOrderPanelPlayStripProduct(unittest.TestCase):
    def test_play_actions_include_assault_and_production(self) -> None:
        acts = play_strip_actions()
        ids = {a["action_id"] for a in acts}
        self.assertIn("apply_assault", ids)
        self.assertIn("apply_production", ids)
        self.assertGreaterEqual(len(acts), 4)
        self.assertLessEqual(len(acts), 8)

    def test_membership_no_harness_leak(self) -> None:
        audit = play_strip_membership_audit()
        self.assertTrue(audit.get("ok"), msg=audit)
        self.assertEqual(int(audit.get("leaked_n") or 0), 0)
        for hid in HARNESS_ACTION_IDS:
            self.assertTrue(is_harness_action(hid))
        for a in PLAY_ACTIONS:
            self.assertFalse(is_harness_action(str(a["action_id"])))

    def test_product_builder(self) -> None:
        p = build_order_panel_play_strip_product(check_wiring=False)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertGreaterEqual(int(p.get("action_n") or 0), 4)
        self.assertIn("has_assault", p.get("pass") or [])

    def test_integrity(self) -> None:
        g = order_panel_play_strip_integrity(check_wiring=False)
        self.assertTrue(g.get("ok"), msg=g)

    def test_wiring_play_mode_strip(self) -> None:
        self.assertTrue(PANEL.is_file())
        src = PANEL.read_text(encoding="utf-8")
        # Must ship play-mode rebuild (EOA_PLAY_STRIP marker)
        self.assertIn("EOA_PLAY_STRIP", src)
        self.assertIn("_rebuild_play_mode_strip", src)
        # Harness dual packs not forced on always-visible path when play mode
        self.assertIn("is_debug_build", src)
        p = build_order_panel_play_strip_product(check_wiring=True)
        self.assertTrue(p.get("wiring", {}).get("play_strip_section"), msg=p)


if __name__ == "__main__":
    unittest.main()
