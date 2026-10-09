#!/usr/bin/env python3
"""SHORE-1: land-sea coast ink stays 4.5 screen px. ProvEdge_ stays tactical."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCREEN_PX = 4.5


def _world_width(zoom: float) -> float:
    z = zoom
    if z != z or z == float("inf") or z == float("-inf"):
        z = 1.0
    return SCREEN_PX / max(z, 0.04)


class TestShore1CoastInk(unittest.TestCase):
    def test_home_shore_is_screen_ink(self) -> None:
        home = _world_width(0.318)
        self.assertAlmostEqual(home * 0.318, SCREEN_PX, places=5)
        self.assertGreater(home, 1.4)
        self.assertAlmostEqual(_world_width(2.60) * 2.60, SCREEN_PX, places=5)
        self.assertAlmostEqual(_world_width(float("inf")), SCREEN_PX, places=5)
        self.assertAlmostEqual(_world_width(0.0), SCREEN_PX / 0.04, places=5)

    def test_source_locks_coast_and_leaves_edges(self) -> None:
        lod = (ROOT / "scripts/map/MapZoomLOD.gd").read_text(encoding="utf-8")
        ren = (ROOT / "scripts/map/MapRenderer.gd").read_text(encoding="utf-8")
        roads = (ROOT / "scripts/map/RoadTierVisual.gd").read_text(encoding="utf-8")
        self.assertIn("const COAST_SCREEN_PX := 4.5", lod)
        self.assertIn("static func coast_border_width_for_zoom", lod)
        self.assertIn("return COAST_SCREEN_PX / maxf(z, 0.04)", lod)
        self.assertNotIn("static func coast_border_width(", lod)
        self.assertIn("return t == Tier.TACTICAL", lod)
        self.assertIn("return 4.2", lod)
        self.assertIn(
            "const COAST_BORDER_COLOR := Color(0.02, 0.04, 0.08, 0.94)",
            ren,
        )
        self.assertNotIn("coast_border_width(tier)", ren)
        self.assertNotIn("coast_border_width(_map_lod_tier)", ren)
        self.assertIn("coast_border_width_for_zoom", ren)
        self.assertIn("func _apply_coast_ink_width", ren)
        self.assertIn("seg.visible = want_internal", ren)
        self.assertIn('const PROVINCE_EDGE_PREFIX := "ProvEdge_"', ren)
        apply_at = ren.find("func _apply_coast_ink_width")
        next_fn = ren.find("\nfunc ", apply_at + 8)
        apply = ren[apply_at:next_fn]
        self.assertNotIn("_update_country_borders", apply)
        self.assertNotIn("_sync_border_lod", apply)
        self.assertIn("const HIGHWAY_FAR_CASING_SCREEN_PX := 5.5", roads)
        self.assertIn("const HIGHWAY_FAR_CORE_SCREEN_PX := 3.2", roads)
        self.assertIn("const END_LABEL_ZOOM_MIN := 1.50", roads)
        self.assertIn("return zoom >= END_LABEL_ZOOM_MIN", roads)


if __name__ == "__main__":
    unittest.main()
