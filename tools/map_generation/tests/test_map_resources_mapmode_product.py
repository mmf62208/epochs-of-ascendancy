#!/usr/bin/env python3
"""M1 gates: resources mapmode tint helper + MapRenderer wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_resources_mapmode_product import (  # noqa: E402
    EMPTY_LAND,
    build_resources_mapmode_product,
    resources_mapmode_integrity_from_board,
    resources_mapmode_rgb,
)

D = ROOT / "data" / "provinces_world_accurate"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"


class TestMapResourcesMapmodeProduct(unittest.TestCase):
    def test_tint_oil_steel_empty_sea(self) -> None:
        p = build_resources_mapmode_product()
        self.assertTrue(p.get("ok"), msg=p)
        oil = resources_mapmode_rgb({"oil": 3})
        empty = resources_mapmode_rgb({})
        self.assertNotEqual(oil, empty)
        self.assertNotEqual(oil, EMPTY_LAND)
        steel = resources_mapmode_rgb({"steel": 2})
        self.assertNotEqual(oil, steel)
        sea = resources_mapmode_rgb({}, is_sea=True)
        self.assertGreater(sea[2], sea[0])

    def test_board_integrity_baku_oil(self) -> None:
        self.assertTrue(D.is_dir())
        g = resources_mapmode_integrity_from_board(str(D))
        self.assertTrue(g.get("ok"), msg=g)
        self.assertIn("baku_oil_tint", g.get("pass") or [])

    def test_renderer_and_toolbar_wire_resources_mode(self) -> None:
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn('set_map_mode("resources")', ren)
        self.assertIn("KEY_F9", ren)
        self.assertIn("debug_tint_mode == \"resources\"", ren)
        self.assertIn("func resources_mapmode_color_from_dict", ren)
        self.assertIn("_resources_mapmode_color_for_province", ren)
        tb = TOOLBAR.read_text(encoding="utf-8")
        self.assertIn('"resources"', tb)
        self.assertIn("Resources", tb)


if __name__ == "__main__":
    unittest.main()
