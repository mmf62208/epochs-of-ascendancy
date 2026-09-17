#!/usr/bin/env python3
"""M4 gates: supply corridor path product + MapRenderer/MapManager wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_supply_corridor_product import (  # noqa: E402
    GER_CAPITAL,
    GER_FRONT,
    _slice_func,
    bfs_land_path,
    build_supply_corridor_product,
    g_polyline_visibility_wiring,
    supply_corridor_integrity_from_board,
)

D = ROOT / "data" / "provinces_world_accurate"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"


class TestMapSupplyCorridorProduct(unittest.TestCase):
    def test_ger_capital_to_front_path(self) -> None:
        p = build_supply_corridor_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertGreaterEqual(int(p.get("bfs_len") or 0), 2)
        path = p.get("bfs_path") or []
        self.assertEqual(int(path[0]), int(p.get("capital") or GER_CAPITAL))
        self.assertEqual(int(path[-1]), GER_FRONT)
        w = p.get("weighted_path") or []
        self.assertGreaterEqual(len(w), 2)

    def test_integrity_from_board(self) -> None:
        self.assertTrue(D.is_dir())
        g = supply_corridor_integrity_from_board(str(D))
        self.assertTrue(g.get("ok"), msg=g)
        self.assertGreaterEqual(int(g.get("bfs_len") or 0), 2)

    def test_bfs_self_and_missing(self) -> None:
        self.assertEqual(bfs_land_path({}, 1, 1), [1])
        self.assertIsNone(bfs_land_path({"1": [2]}, 1, 99, limit=5))

    def test_renderer_and_manager_wire_corridor(self) -> None:
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("func highlight_supply_corridor", ren)
        self.assertIn("func highlight_corridor_capital_to_selected", ren)
        self.assertIn("KEY_G", ren)
        self.assertIn("highlight_supply_route_path", ren)
        self.assertIn("func _request_hang_safe_supply_corridor", ren)
        self.assertIn("func _deferred_budgeted_supply_corridor", ren)
        gi = ren.find("keycode == KEY_G")
        g_slice = ren[gi : gi + 400] if gi >= 0 else ""
        self.assertIn("_request_hang_safe_supply_corridor", g_slice)
        self.assertNotIn("highlight_corridor_capital_to_selected", g_slice)
        self.assertNotIn("preview_player_route", g_slice)
        # supply preview pulses corridor polyline
        self.assertIn("M4:", ren)
        mm = MAP_MANAGER.read_text(encoding="utf-8")
        self.assertIn("func find_land_path", mm)
        self.assertIn("func find_infra_weighted_land_path", mm)
        tb = TOOLBAR.read_text(encoding="utf-8")
        self.assertIn("corridor", tb.lower())
        self.assertIn("Corridor", tb)

    def test_g_polyline_visibility_wiring(self) -> None:
        vis = g_polyline_visibility_wiring()
        self.assertTrue(vis.get("ok"), msg=vis)
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("func _supply_route_polyline_width", ren)
        self.assertIn("func _apply_visible_supply_route_polyline", ren)
        self.assertIn("z_as_relative = false", ren)
        self.assertIn("map_host.add_child(host)", ren)
        host = _slice_func(ren, "_ensure_supply_route_highlight_host")
        request = _slice_func(ren, "_request_hang_safe_supply_corridor")
        self.assertNotIn("follow_viewport_enabled = true", host)
        self.assertIn("_draw_hang_safe_corridor_line", request)
        hang = _slice_func(ren, "_draw_hang_safe_corridor_line")
        self.assertIn("highlight_supply_route_path", hang)
        self.assertNotIn("find_land_path", hang)
        self.assertNotIn("highlight_supply_corridor", hang)


if __name__ == "__main__":
    unittest.main()
