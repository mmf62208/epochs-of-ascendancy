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
    bfs_land_path,
    build_supply_corridor_product,
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
        # supply preview pulses corridor polyline
        self.assertIn("M4:", ren)
        mm = MAP_MANAGER.read_text(encoding="utf-8")
        self.assertIn("func find_land_path", mm)
        self.assertIn("func find_infra_weighted_land_path", mm)
        tb = TOOLBAR.read_text(encoding="utf-8")
        self.assertIn("corridor", tb.lower())
        self.assertIn("Corridor", tb)


if __name__ == "__main__":
    unittest.main()
