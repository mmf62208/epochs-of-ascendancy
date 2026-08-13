#!/usr/bin/env python3
"""Pure tests: capital landmass centroid + shipped wiring (labels + CanvasLayer menu)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_nation_label_landmass_product import (  # noqa: E402
    build_map_nation_label_landmass_product,
    capital_landmass_centroid,
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


if __name__ == "__main__":
    unittest.main()
