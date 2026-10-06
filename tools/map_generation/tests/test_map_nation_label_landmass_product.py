#!/usr/bin/env python3
"""Pure tests: capital landmass centroid + shipped wiring (labels + CanvasLayer menu)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_nation_label_landmass_product import (  # noqa: E402
    NATION_LABEL_CLOSE_ZOOM,
    NATION_LABEL_EUROPE_ZOOM,
    NATION_LABEL_MID_ZOOM,
    build_map_nation_label_landmass_product,
    capital_landmass_centroid,
    nation_label_effective_screen_px,
    nation_label_font_px_for_camera,
    nation_label_height_ratio,
    nation_label_is_texture_magnified,
)


class TestNationLabelLandmass(unittest.TestCase):
    def test_centroid_not_on_coastal_capital_pin(self) -> None:
        owned = [1, 2, 3, 4]
        centroids = {1: (20.0, 0.0), 2: (1.0, 0.0), 3: (0.0, 1.0), 4: (0.0, -1.0)}
        neighbors = {1: [2], 2: [1, 3, 4], 3: [2], 4: [2]}
        c = capital_landmass_centroid(owned, centroids, neighbors, 1, {1: 1, 2: 4, 3: 4, 4: 4})
        self.assertIsNotNone(c)
        assert c is not None
        self.assertLess(c[0], 8.0, msg="label must sit on landmass, not capital pin at x=20")

    def test_product_and_shipped_wiring(self) -> None:
        p = build_map_nation_label_landmass_product()
        self.assertTrue(p.get("ok"), msg=p)

    def test_label1_mid_zoom_band_not_magnified(self) -> None:
        h = 720.0
        eu = nation_label_font_px_for_camera(NATION_LABEL_EUROPE_ZOOM, h)
        mid = nation_label_font_px_for_camera(NATION_LABEL_MID_ZOOM, h)
        close = nation_label_font_px_for_camera(NATION_LABEL_CLOSE_ZOOM, h)
        self.assertGreater(eu, 0)
        self.assertGreater(mid, 0)
        self.assertEqual(close, 0)
        eu_r = nation_label_height_ratio(eu, NATION_LABEL_EUROPE_ZOOM, 1.0, h)
        mid_r = nation_label_height_ratio(mid, NATION_LABEL_MID_ZOOM, 1.0, h)
        self.assertGreaterEqual(eu_r, 0.018)
        self.assertLessEqual(eu_r, 0.045)
        self.assertGreaterEqual(mid_r, 0.016)
        self.assertLessEqual(mid_r, 0.038)
        self.assertLessEqual(mid_r, eu_r + 0.002)
        self.assertFalse(
            nation_label_is_texture_magnified(mid, NATION_LABEL_MID_ZOOM, 1.0)
        )
        self.assertTrue(
            nation_label_is_texture_magnified(20, NATION_LABEL_MID_ZOOM, 2.5)
        )
        # Effective screen px is font * zoom * 1, not a blown-up 20px texture.
        mid_eff = nation_label_effective_screen_px(mid, NATION_LABEL_MID_ZOOM, 1.0)
        self.assertLessEqual(mid_eff, float(mid) + 0.75)


if __name__ == "__main__":
    unittest.main()
