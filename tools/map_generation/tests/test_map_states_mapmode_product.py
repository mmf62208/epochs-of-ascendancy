#!/usr/bin/env python3
"""M2/M3 gates: states + terrain mapmode tint helpers + MapRenderer/toolbar wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_states_mapmode_product import (  # noqa: E402
    EMPTY,
    SEA,
    build_states_mapmode_product,
    states_mapmode_integrity_from_board,
    states_mapmode_rgb,
    states_terrain_hotkey_integrity,
    terrain_mapmode_rgb,
)

D = ROOT / "data" / "provinces_world_accurate"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"


class TestMapStatesMapmodeProduct(unittest.TestCase):
    def test_states_distinct_empty_sea(self) -> None:
        p = build_states_mapmode_product()
        self.assertTrue(p.get("ok"), msg=p)
        a = states_mapmode_rgb(1)
        b = states_mapmode_rgb(2)
        empty = states_mapmode_rgb(0)
        self.assertNotEqual(a, b)
        self.assertNotEqual(a, empty)
        self.assertNotEqual(a, EMPTY)
        sea = states_mapmode_rgb(0, is_sea=True)
        self.assertEqual(sea, SEA)
        self.assertGreater(sea[2], sea[0])

    def test_terrain_palette_distinct(self) -> None:
        plains = terrain_mapmode_rgb("plains")
        forest = terrain_mapmode_rgb("forest")
        mtn = terrain_mapmode_rgb("mountains")
        desert = terrain_mapmode_rgb("desert")
        self.assertNotEqual(plains, forest)
        self.assertNotEqual(plains, mtn)
        self.assertNotEqual(forest, desert)
        sea = terrain_mapmode_rgb("ocean", is_sea=True)
        self.assertEqual(sea, SEA)

    def test_board_integrity_states_distinct(self) -> None:
        self.assertTrue(D.is_dir())
        g = states_mapmode_integrity_from_board(str(D))
        self.assertTrue(g.get("ok"), msg=g)
        self.assertIn("board_states_distinct", g.get("pass") or [])
        self.assertGreaterEqual(len(g.get("sample_state_ids") or []), 2)

    def test_renderer_and_toolbar_wire_states_terrain(self) -> None:
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn('set_map_mode("states")', ren)
        self.assertIn('set_map_mode("terrain")', ren)
        self.assertIn('set_map_mode("resources")', ren)
        self.assertIn("KEY_F9", ren)
        self.assertIn('debug_tint_mode == "states"', ren)
        self.assertIn('debug_tint_mode == "terrain"', ren)
        self.assertIn("func states_mapmode_color_from_id", ren)
        self.assertIn("func terrain_mapmode_color_from_key", ren)
        self.assertIn("_states_mapmode_color_for_province", ren)
        self.assertIn("_terrain_mapmode_color_for_province", ren)
        # Modifier branch must not let plain F9 always win
        self.assertIn("event.ctrl_pressed", ren)
        self.assertIn("event.shift_pressed", ren)
        tb = TOOLBAR.read_text(encoding="utf-8")
        self.assertIn('"states"', tb)
        self.assertIn('"terrain"', tb)
        self.assertIn("States", tb)
        self.assertIn("Terrain", tb)
        # F-keys must live in _input (GUI/search cannot swallow Ctrl+F9) and toolbar follows.
        g = states_terrain_hotkey_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        input_i = ren.find("func _input")
        unh_i = ren.find("func _unhandled_input")
        input_fn = ren[input_i:unh_i]
        self.assertIn('set_map_mode("terrain")', input_fn)
        self.assertIn('set_map_mode("states")', input_fn)
        self.assertIn("func _sync_mapmode_toolbar", ren)


if __name__ == "__main__":
    unittest.main()
