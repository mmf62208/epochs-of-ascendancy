#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from island_viability import classify_island, polygon_area  # noqa: E402


class TestArea(unittest.TestCase):
    def test_square_area(self) -> None:
        sq = [[0, 0], [10, 0], [10, 10], [0, 10]]
        self.assertAlmostEqual(polygon_area(sq), 100.0, places=3)


class TestClassify(unittest.TestCase):
    def test_sea_no_facilities(self) -> None:
        r = classify_island(1000.0, domain="sea")
        self.assertEqual(r["facility_tier"], "none")
        self.assertTrue(r["keep_as_province"])

    def test_micro_exclude(self) -> None:
        r = classify_island(50.0, domain="land", critical=False)
        self.assertEqual(r["island_class"], "micro")
        self.assertFalse(r["keep_as_province"])

    def test_critical_micro_kept(self) -> None:
        r = classify_island(50.0, domain="land", critical=True)
        self.assertTrue(r["keep_as_province"])
        self.assertEqual(r["facility_tier"], "limited")

    def test_full_mainland(self) -> None:
        r = classify_island(5000.0, domain="land", explicit_class="mainland")
        self.assertEqual(r["facility_tier"], "full")
        self.assertTrue(r["can_factory"])

    def test_small_airfield_band(self) -> None:
        r = classify_island(200.0, domain="coastal_land")
        self.assertIn(r["island_class"], ("small", "medium"))
        self.assertIn(r["facility_tier"], ("limited", "anchor_only", "full"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
