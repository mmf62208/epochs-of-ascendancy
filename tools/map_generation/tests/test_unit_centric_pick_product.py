#!/usr/bin/env python3
"""Gates: unit-centric pin pick (hit disk, selected chip, no inspector)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_centric_pick_product import (  # noqa: E402
    HIT_RADIUS_FLOOR,
    HIT_RADIUS_PX,
    STRATEGIC_PICK_TOAST,
    build_unit_centric_pick_product,
    unit_centric_pick_integrity,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


class TestUnitCentricPickProduct(unittest.TestCase):
    def test_constants(self) -> None:
        self.assertGreaterEqual(HIT_RADIUS_PX, 48.0)
        self.assertGreaterEqual(HIT_RADIUS_FLOOR, 20.0)
        self.assertIn("Shift+U", STRATEGIC_PICK_TOAST)
        self.assertIn("unit chip", STRATEGIC_PICK_TOAST)
        self.assertIn("toggles counters", STRATEGIC_PICK_TOAST)

    def test_product_wiring(self) -> None:
        p = build_unit_centric_pick_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "pin_before_hex",
            "hit_radius_48_floor_20",
            "pin_select_no_inspector",
            "selected_frame_hook",
            "hidden_pins_skip",
            "prefer_player_pin",
            "strategic_pick_toast",
            "stack_cycle",
            "select_refreshes_chip",
            "chip_match_by_province",
            "selected_frame_immediate_free",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))

    def test_integrity(self) -> None:
        g = unit_centric_pick_integrity(check_wiring=True)
        self.assertTrue(g.get("ok"), msg=g)

    def test_renderer_integrity_strings(self) -> None:
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("_try_open_unit_at_world", ren)
        self.assertIn("maxf(48.0", ren)
        self.assertIn("20.0", ren)
        self.assertIn("SelectedFrame", ren)
        self.assertIn("_refresh_selected_unit_chip", ren)
        self.assertIn(STRATEGIC_PICK_TOAST, ren)
        self.assertIn("_cycle_selected_stack_unit", ren)
        self.assertIn("not counter.visible", ren)
        # Hang-class: pin open path must not open inspector.
        pin_i = ren.find("func _try_open_unit_at_world")
        self.assertGreaterEqual(pin_i, 0)
        pin_slice = ren[pin_i : pin_i + 800]
        next_fn = pin_slice.find("\nfunc ", 1)
        if next_fn > 0:
            pin_slice = pin_slice[:next_fn]
        self.assertNotIn("show_info_panel", pin_slice)
        # Stack-cycle chip contract: match station province, free frame same-frame.
        chip_i = ren.find("func _refresh_selected_unit_chip")
        self.assertGreaterEqual(chip_i, 0)
        chip_slice = ren[chip_i : chip_i + 1600]
        next_chip = chip_slice.find("\nfunc ", 1)
        if next_chip > 0:
            chip_slice = chip_slice[:next_chip]
        self.assertIn("stationed_province_id", chip_slice)
        self.assertIn("pin_pid", chip_slice)
        self.assertIn("sel_pid", chip_slice)
        self.assertIn(".free()", chip_slice)


if __name__ == "__main__":
    unittest.main()
