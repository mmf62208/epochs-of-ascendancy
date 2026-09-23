#!/usr/bin/env python3
"""Pure tests: unit counter LOD (strategic hide / operational show / U toggle wiring)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_unit_counter_lod_product import (  # noqa: E402
    EUROPE_HOME_ZOOM_HI,
    EUROPE_HOME_ZOOM_LO,
    build_map_unit_counter_lod_product,
    europe_home_zoom_wants_counters,
    show_unit_counters,
    show_unit_counters_for_zoom,
    TIER_STRATEGIC,
    TIER_OPERATIONAL,
    TIER_TACTICAL,
)


class TestUnitCounterLod(unittest.TestCase):
    def test_policy(self) -> None:
        self.assertFalse(show_unit_counters(TIER_STRATEGIC, True))
        self.assertTrue(show_unit_counters(TIER_OPERATIONAL, True))
        self.assertTrue(show_unit_counters(TIER_TACTICAL, True))
        self.assertFalse(show_unit_counters(TIER_TACTICAL, False))

    def test_europe_home_zoom_band_paints(self) -> None:
        self.assertTrue(europe_home_zoom_wants_counters())
        self.assertTrue(show_unit_counters_for_zoom(EUROPE_HOME_ZOOM_LO, True))
        self.assertTrue(show_unit_counters_for_zoom(0.49, True))
        self.assertTrue(show_unit_counters_for_zoom(1.3, True))
        self.assertTrue(show_unit_counters_for_zoom(EUROPE_HOME_ZOOM_HI, True))
        self.assertFalse(show_unit_counters_for_zoom(0.14, True))
        self.assertFalse(show_unit_counters_for_zoom(0.24, True))

    def test_product(self) -> None:
        p = build_map_unit_counter_lod_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertIn("europe_home_zoom_wants_counters", p.get("pass") or [])
        self.assertIn("home_syncs_counter_paint", p.get("pass") or [])


if __name__ == "__main__":
    unittest.main()
