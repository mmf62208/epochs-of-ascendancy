#!/usr/bin/env python3
"""Gates: continuous sea + solid political land fills (no void-hex ocean stack)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_political_fill_visual_product import (  # noqa: E402
    antarctica_fill_class,
    build_map_political_fill_visual_product,
    continuous_sea_fill_rgba,
    ice_fill_not_eng_red,
    ice_ocean_fill_rgba,
    land_fill_alpha,
    map_political_fill_visual_integrity,
    political_stack_readable,
    world_board_fill_alpha,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


class TestMapPoliticalFillVisual(unittest.TestCase):
    def test_continuous_sea_is_deep_water(self) -> None:
        # Even if base is land-like, output should pull to deep ocean
        sea = continuous_sea_fill_rgba((0.8, 0.2, 0.2), sea_political_trace=0.08, clean_political=True)
        self.assertGreater(sea[2], sea[0])  # bluer than red
        self.assertGreaterEqual(sea[3], 0.9)
        # Flat: two different bases stay close after flatten
        s2 = continuous_sea_fill_rgba((0.1, 0.5, 0.9), sea_political_trace=0.08, clean_political=True)
        dist = abs(sea[0] - s2[0]) + abs(sea[1] - s2[1]) + abs(sea[2] - s2[2])
        self.assertLess(dist, 0.25, msg="sea tiles must not vary like land ownership")

    def test_land_alpha_solid_when_clean(self) -> None:
        self.assertGreaterEqual(land_fill_alpha(clean_political=True, terrain_layer_on=False), 0.88)
        self.assertGreaterEqual(world_board_fill_alpha(terrain_layer_on=False, clean_political=True), 0.88)
        self.assertLess(
            world_board_fill_alpha(terrain_layer_on=True, clean_political=False),
            world_board_fill_alpha(terrain_layer_on=False, clean_political=True),
        )

    def test_ownership_distinct_vs_sea(self) -> None:
        sea = continuous_sea_fill_rgba(clean_political=True)
        self.assertTrue(
            political_stack_readable((0.75, 0.2, 0.2), sea, (0.2, 0.35, 0.8)),
            msg=sea,
        )

    def test_product_and_renderer_wiring(self) -> None:
        p = build_map_political_fill_visual_product()
        self.assertTrue(p.get("ok"), msg=p)
        g = map_political_fill_visual_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("func _shade_sea_province_fill", ren)
        self.assertIn("show_terrain_layer", ren)
        # Clean political default for world playability
        self.assertRegex(ren, r"show_terrain_layer\s*(:\s*bool\s*)?=\s*false")
        # Void-hex fix: continuous ocean floor + underlay gated by terrain flag
        self.assertIn("func _ensure_ocean_floor", ren)
        self.assertIn("bg.visible = show_terrain_layer", ren)
        self.assertIn("func _apply_clean_political_clear_color", ren)
        self.assertGreaterEqual(continuous_sea_fill_rgba(clean_political=True)[3], 0.95)

    def test_antarctica_is_ice_ocean_not_eng_red(self) -> None:
        self.assertEqual(antarctica_fill_class(902133, "ENG"), "ice_ocean")
        self.assertEqual(antarctica_fill_class(902134, "ENG"), "ice_ocean")
        ice = ice_ocean_fill_rgba()
        self.assertTrue(ice_fill_not_eng_red(ice), msg=ice)
        self.assertGreater(ice[2], ice[0])
        p = build_map_political_fill_visual_product()
        self.assertIn("antarctica_ice_ocean_not_eng", p.get("pass") or [])
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("func ice_ocean_fill_color", ren)
        self.assertIn("902133", ren)
        self.assertIn("902134", ren)

    def test_sea_flat_across_bases(self) -> None:
        """Different owner bases must collapse to nearly the same continuous ocean."""
        a = continuous_sea_fill_rgba((0.9, 0.1, 0.1), sea_political_trace=0.08)
        b = continuous_sea_fill_rgba((0.1, 0.9, 0.1), sea_political_trace=0.08)
        dist = abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
        self.assertLess(dist, 0.12, msg=(a, b, dist))

    def test_sea_zone_shift_is_subtle(self) -> None:
        """Zones differ slightly but stay continuous ocean family (not neon tiles)."""
        a = continuous_sea_fill_rgba(zone_hue_shift=0.1)
        b = continuous_sea_fill_rgba(zone_hue_shift=0.9)
        dist = abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
        self.assertGreater(dist, 0.01, msg="zones should be distinguishable")
        self.assertLess(dist, 0.12, msg="zones must not look like land tiles")
        self.assertGreater(a[2], a[0])
        self.assertGreater(b[2], b[0])


if __name__ == "__main__":
    unittest.main()
