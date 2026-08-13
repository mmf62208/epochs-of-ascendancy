#!/usr/bin/env python3
"""Pure tests: unit counter LOD (strategic hide / operational show / U toggle wiring)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_unit_counter_lod_product import (  # noqa: E402
    build_map_unit_counter_lod_product,
    show_unit_counters,
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

    def test_product(self) -> None:
        p = build_map_unit_counter_lod_product()
        self.assertTrue(p.get("ok"), msg=p)


if __name__ == "__main__":
    unittest.main()
