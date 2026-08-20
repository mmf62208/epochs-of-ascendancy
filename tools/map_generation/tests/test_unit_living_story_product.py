#!/usr/bin/env python3
"""Gate: living unit story — look, org/str/rdy, XP, replacements, history."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_living_story_product import (  # noqa: E402
    build_unit_living_story_product,
    dilute_xp_heavy_loss,
    dilute_xp_replacements,
    history_line,
    nato_letter,
    record_battle,
    unit_living_story_integrity,
    xp_power_mult,
)


class TestUnitLivingStoryProduct(unittest.TestCase):
    def test_math(self) -> None:
        self.assertEqual(nato_letter("medium_tank"), "A")
        self.assertEqual(nato_letter("infantry"), "I")
        self.assertEqual(nato_letter("artillery"), "G")
        self.assertLess(xp_power_mult(12.0), xp_power_mult(48.0))
        self.assertLess(xp_power_mult(48.0), xp_power_mult(92.0))
        diluted = dilute_xp_replacements(90.0, 0.4, 1.0)
        self.assertLess(diluted, 80.0)
        self.assertGreater(diluted, 40.0)
        self.assertAlmostEqual(dilute_xp_heavy_loss(90.0, 0.02), 90.0)
        self.assertLess(dilute_xp_heavy_loss(90.0, 0.25), 90.0)
        rec = record_battle(date="1936-03-01", outcome="hold")
        self.assertIn("hold", history_line(rec))

    def test_product_wiring(self) -> None:
        p = build_unit_living_story_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        i = unit_living_story_integrity()
        self.assertTrue(i.get("ok"), msg=i)


if __name__ == "__main__":
    unittest.main()
