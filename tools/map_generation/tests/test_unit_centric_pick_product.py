#!/usr/bin/env python3
"""Gates: unit-centric pin pick (hit disk, selected chip, no inspector)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_centric_pick_product import (  # noqa: E402
    EUROPE_HOME_HIT_Z,
    HIT_RADIUS_FLOOR,
    HIT_RADIUS_PX,
    STRATEGIC_PICK_TOAST,
    build_unit_centric_pick_product,
    home_band_hit_disk_tracks_scale,
    unit_centric_pick_integrity,
    unit_chip_hit_screen_px,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


class TestUnitCentricPickProduct(unittest.TestCase):
    def test_constants(self) -> None:
        self.assertGreaterEqual(HIT_RADIUS_PX, 48.0)
        self.assertGreaterEqual(HIT_RADIUS_FLOOR, 20.0)
        self.assertIn("Shift+U", STRATEGIC_PICK_TOAST)
        self.assertIn("unit chip", STRATEGIC_PICK_TOAST)
        self.assertIn("toggles counters", STRATEGIC_PICK_TOAST)
        self.assertTrue(home_band_hit_disk_tracks_scale())
        self.assertGreater(unit_chip_hit_screen_px(EUROPE_HOME_HIT_Z), HIT_RADIUS_PX)
        self.assertAlmostEqual(unit_chip_hit_screen_px(1.0), HIT_RADIUS_PX, places=2)

    def test_product_wiring(self) -> None:
        p = build_unit_centric_pick_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "pin_before_hex",
            "capital_star_before_chip",
            "hit_radius_48_floor_20",
            "home_hit_disk_tracks_counter_scale",
            "pin_select_no_inspector",
            "selected_frame_hook",
            "hidden_pins_skip",
            "prefer_player_pin",
            "strategic_pick_toast",
            "stack_cycle",
            "select_refreshes_chip",
            "chip_match_by_province",
            "selected_frame_immediate_free",
            "land_chip_in_input",
            "land_still_click_skips_air_fleet",
            "land_still_click_player_tag_only",
            "tooltip_not_pick_blocker",
            "europe_home_counters_want_visible",
            "home_syncs_counter_visibility",
            "counter_scale_floor_readable",
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
        self.assertIn("func _unit_counter_hit_radius_world", ren)
        self.assertIn("0.5 * sprite_px", ren)
        self.assertIn("sqrt(2.0)", ren)
        self.assertIn("label_pad", ren)
        self.assertIn("func _unit_counter_aabb_hit_screen", ren)
        pick_i = ren.find("func _pick_unit_formation_at_world")
        self.assertGreaterEqual(pick_i, 0)
        pick_slice = ren[pick_i : pick_i + 2200]
        next_pick = pick_slice.find("\nfunc ", 1)
        if next_pick > 0:
            pick_slice = pick_slice[:next_pick]
        self.assertIn("_unit_counter_hit_radius_world", pick_slice)
        self.assertIn("counter.position", pick_slice)
        self.assertIn("SelectedFrame", ren)
        self.assertIn("_refresh_selected_unit_chip", ren)
        self.assertIn(STRATEGIC_PICK_TOAST, ren)
        self.assertIn("_cycle_selected_stack_unit", ren)
        self.assertIn("not counter.visible", ren)
        self.assertIn("func _pick_land_unit_formation_at_world", ren)
        self.assertIn("func _formation_type_blocks_land_open", ren)
        self.assertIn("func _player_land_formation_at_province", ren)
        self.assertIn("func _formation_is_player_tag", ren)
        self.assertIn("_pick_unit_formation_at_world(world_pos, land_only, player_only)", ren)
        self.assertIn("player_only", ren)
        self.assertNotIn("DIG_CHIP_MISS", ren)
        self.assertNotIn("DIG_CHIP_SKIP", ren)
        land_i = ren.find("func _try_open_land_unit_at_world")
        self.assertGreaterEqual(land_i, 0)
        land_slice = ren[land_i : land_i + 1400]
        next_land = land_slice.find("\nfunc ", 1)
        if next_land > 0:
            land_slice = land_slice[:next_land]
        self.assertIn("_pick_land_unit_formation_at_world", land_slice)
        self.assertIn("_player_land_formation_at_province", land_slice)
        self.assertIn("_formation_is_player_tag", land_slice)
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
