#!/usr/bin/env python3
"""Gates: out-of-combat strength trickle."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_recovery_replenish_product import (  # noqa: E402
    STRENGTH_PER_DAY,
    apply_strength_tick,
    build_unit_recovery_replenish_product,
    strength_delta,
    unit_recovery_replenish_integrity,
)


class TestUnitRecoveryReplenishProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_unit_recovery_replenish_product()
        self.assertTrue(p.get("ok"), msg=p)

    def test_integrity(self) -> None:
        self.assertTrue(unit_recovery_replenish_integrity().get("ok"))

    def test_math(self) -> None:
        self.assertEqual(strength_delta(in_combat=True, strength=0.2), 0.0)
        self.assertAlmostEqual(
            strength_delta(in_combat=False, strength=0.5), STRENGTH_PER_DAY
        )
        self.assertAlmostEqual(apply_strength_tick(in_combat=False, strength=0.99), 1.0)


if __name__ == "__main__":
    unittest.main()
