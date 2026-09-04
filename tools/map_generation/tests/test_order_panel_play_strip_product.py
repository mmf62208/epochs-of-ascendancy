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
from play_next_hook_product import rank_next_beat  # noqa: E402

PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
TOP_BAR = ROOT / "scripts" / "ui" / "TopInfoBar.gd"
HOOK_GD = ROOT / "scripts" / "ui" / "PlayNextHook.gd"


class TestOrderPanelPlayStripProduct(unittest.TestCase):
    def test_play_actions_include_assault_and_production(self) -> None:
        acts = play_strip_actions()
        ids = {a["action_id"] for a in acts}
        self.assertIn("apply_assault", ids)
        self.assertIn("open_living_production", ids)
        self.assertNotIn("apply_production", ids)
        prod = next(a for a in acts if a["action_id"] == "open_living_production")
        self.assertEqual(prod.get("living_surface"), "production")
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
        self.assertTrue(p.get("ok"), msg=p)

    def test_play_mode_production_opens_living_surface(self) -> None:
        src = PANEL.read_text(encoding="utf-8")
        play_i = src.find("func _rebuild_play_mode_strip")
        play_n = src.find("\nfunc ", play_i + 1) if play_i >= 0 else -1
        play_fn = src[play_i:play_n] if play_i >= 0 else ""
        open_i = src.find("func _open_play_strip_production")
        open_n = src.find("\nfunc ", open_i + 1) if open_i >= 0 else -1
        open_fn = src[open_i:open_n] if open_i >= 0 else ""
        btn_i = src.find("func _add_play_strip_production_button")
        btn_n = src.find("\nfunc ", btn_i + 1) if btn_i >= 0 else -1
        btn_fn = src[btn_i:btn_n] if btn_i >= 0 else ""
        self.assertTrue(play_fn, msg="missing _rebuild_play_mode_strip")
        self.assertTrue(open_fn, msg="missing _open_play_strip_production")
        self.assertTrue(btn_fn, msg="missing _add_play_strip_production_button")
        self.assertNotIn('_add_apply_button("[3] Production", "apply_production"', play_fn)
        self.assertNotIn('"apply_production"', play_fn)
        self.assertIn("_add_play_strip_production_button", play_fn)
        self.assertIn("open_living_surface", open_fn)
        self.assertIn('"production"', open_fn)
        self.assertIn("pressed.connect(_open_play_strip_production)", btn_fn)
        self.assertNotIn("apply_production", btn_fn)
        self.assertIn("typeof(PlayNextHook) != TYPE_NIL", open_fn)
        self.assertNotIn('has_method("open_living_production")', open_fn)
        bar = TOP_BAR.read_text(encoding="utf-8")
        bar_i = bar.find("func open_living_surface")
        bar_n = bar.find("\nfunc ", bar_i + 1) if bar_i >= 0 else -1
        bar_fn = bar[bar_i:bar_n] if bar_i >= 0 else ""
        self.assertIn("_on_production_pressed", bar_fn)
        self.assertIn("get_player_country_tag", bar_fn)
        self.assertIn("player_country_tag = pt", bar_fn)
        hook = HOOK_GD.read_text(encoding="utf-8")
        self.assertIn("func open_living_production", hook)
        apply_i = hook.find("static func apply")
        apply_n = hook.find("\nstatic func ", apply_i + 1) if apply_i >= 0 else -1
        apply_fn = hook[apply_i:apply_n] if apply_i >= 0 and apply_n > apply_i else ""
        self.assertIn('_open_living_surface("production"', apply_fn)
        p = build_order_panel_play_strip_product(check_wiring=True)
        self.assertTrue(p.get("wiring", {}).get("play_mode_opens_living_production"), msg=p)
        self.assertTrue(p.get("wiring", {}).get("play_mode_not_apply_production"), msg=p)
        self.assertIn("unit_card_fill_stockpile", p.get("pass") or [])
        self.assertIn("top_bar_binds_living_tag", p.get("pass") or [])
        self.assertIn("hook_apply_opens_production", p.get("pass") or [])

    def test_maginot_idle_still_maginot_not_warloop(self) -> None:
        mag = rank_next_beat(
            {"maginot_fid": "ger_front", "maginot_from": 710173, "maginot_to": 710739}
        )
        self.assertEqual(mag.get("source"), "maginot")
        self.assertEqual(mag.get("action"), "open_fight")
        self.assertNotEqual(mag.get("action"), "show_war_loop")
        self.assertNotEqual(mag.get("source"), "first_session")
        self.assertEqual(mag.get("fid"), "ger_front")
        self.assertEqual(mag.get("from_id"), 710173)
        self.assertEqual(mag.get("to_id"), 710739)
        idle = rank_next_beat({})
        self.assertEqual(idle.get("action"), "show_war_loop")
        self.assertEqual(idle.get("source"), "first_session")
        short = rank_next_beat({"steel_stock": 0.0, "has_vehicle": True})
        self.assertEqual(short.get("action"), "shortage")
        hook = HOOK_GD.read_text(encoding="utf-8")
        apply_i = hook.find("static func apply")
        apply_n = hook.find("\nstatic func ", apply_i + 1) if apply_i >= 0 else -1
        apply_fn = hook[apply_i:apply_n] if apply_i >= 0 and apply_n > apply_i else ""
        self.assertIn('_open_living_surface("production"', apply_fn)


if __name__ == "__main__":
    unittest.main()
