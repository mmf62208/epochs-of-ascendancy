#!/usr/bin/env python3
"""Pure tests: FIRST20-P2 F6 start-zoom unit LOD thresholds."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from first20_p2_unit_lod_product import (  # noqa: E402
    UNIT_LOD_FULL_MIN_ZOOM,
    UNIT_LOD_STACK_MAX_ZOOM,
    build_first20_p2_unit_lod_product,
    first20_p2_unit_lod_integrity,
    hide_default_unit_name,
    is_default_unit_name,
    unit_lod_band,
    unit_lod_mid_letter,
    unit_lod_policy,
)


class TestFirst20P2UnitLod(unittest.TestCase):
    def test_thresholds(self) -> None:
        self.assertEqual(UNIT_LOD_STACK_MAX_ZOOM, 0.6)
        self.assertEqual(UNIT_LOD_FULL_MIN_ZOOM, 1.2)
        self.assertEqual(unit_lod_band(0.39), "stack")
        self.assertEqual(unit_lod_band(0.599), "stack")
        self.assertEqual(unit_lod_band(0.6), "mid")
        self.assertEqual(unit_lod_band(0.8), "mid")
        self.assertEqual(unit_lod_band(1.19), "mid")
        self.assertEqual(unit_lod_band(1.2), "full")
        self.assertEqual(unit_lod_band(2.0), "full")

    def test_mutant_wrong_cut_fails(self) -> None:
        # A 0.5 / 1.0 cut would put Home-adjacent start zoom in mid/full.
        self.assertNotEqual(unit_lod_band(0.55), "mid")
        self.assertNotEqual(unit_lod_band(1.1), "full")

    def test_policy_start_zoom(self) -> None:
        pol = unit_lod_policy(0.4)
        self.assertEqual(pol["band"], "stack")
        self.assertFalse(pol["show_bars"])
        self.assertTrue(pol["stack_chip"])
        self.assertEqual(pol["chip_w"], 22.0)
        self.assertEqual(pol["chip_h"], 16.0)
        self.assertLess(pol["chip_z"], pol["label_z"])
        sel = unit_lod_policy(0.4, selected_own=True)
        self.assertEqual(sel["band"], "full")
        self.assertTrue(sel["show_bars"])
        fleet = unit_lod_policy(0.35, is_fleet=True)
        self.assertTrue(fleet["fleet_anchor"])
        self.assertFalse(fleet["stack_chip"])

    def test_names_and_letters(self) -> None:
        self.assertTrue(is_default_unit_name("Division 0"))
        self.assertTrue(is_default_unit_name("Division 12"))
        self.assertFalse(is_default_unit_name("1. Infanterie"))
        self.assertTrue(hide_default_unit_name(0.8, "Division 0"))
        self.assertFalse(hide_default_unit_name(1.2, "Division 0"))
        self.assertFalse(hide_default_unit_name(0.4, "Division 0", selected_own=True))
        self.assertEqual(unit_lod_mid_letter("H"), "A")
        self.assertEqual(unit_lod_mid_letter("L"), "L")
        self.assertEqual(unit_lod_mid_letter("G"), "I")

    def test_product(self) -> None:
        p = build_first20_p2_unit_lod_product()
        self.assertTrue(p.get("ok"), msg=p)
        g = first20_p2_unit_lod_integrity()
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
