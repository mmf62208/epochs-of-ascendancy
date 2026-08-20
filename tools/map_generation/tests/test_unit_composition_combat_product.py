#!/usr/bin/env python3
"""Gate: infantry + vehicles, min-speed, armor, att/def manpower+equip losses."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_composition_combat_product import (  # noqa: E402
    build_unit_composition_combat_product,
    compose,
    daily_losses,
    manpower_lost,
    unit_composition_combat_integrity,
)


class TestUnitCompositionCombatProduct(unittest.TestCase):
    def test_math(self) -> None:
        foot = compose(mobility="foot")
        truck = compose(mobility="truck")
        mixed = compose(mobility="truck", armor="medium_tank")
        foot_tank = compose(mobility="foot", armor="medium_tank")
        self.assertEqual(float(foot["speed"]), 1.0)
        self.assertEqual(float(truck["speed"]), 2.0)
        self.assertEqual(float(mixed["speed"]), 1.5)
        self.assertEqual(float(foot_tank["speed"]), 1.0)
        self.assertGreater(float(mixed["armor"]), float(truck["armor"]))
        self.assertGreater(manpower_lost(3200, 0.05), 0)
        att = daily_losses(role="attacker", lean="defender", composition=truck)
        dfn = daily_losses(role="defender", lean="defender", composition=truck)
        self.assertGreater(int(att["manpower_lost"]), 0)
        self.assertGreater(int(dfn["manpower_lost"]), 0)
        self.assertGreaterEqual(int(att["manpower_lost"]), int(dfn["manpower_lost"]))

    def test_product_wiring(self) -> None:
        p = build_unit_composition_combat_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        i = unit_composition_combat_integrity()
        self.assertTrue(i.get("ok"), msg=i)


if __name__ == "__main__":
    unittest.main()
