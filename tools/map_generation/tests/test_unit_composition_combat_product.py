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
    fuel_burn,
    fuel_speed_mult,
    manpower_lost,
    pierce_mult,
    shortage_mult,
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
        guns = compose(mobility="truck", armor="medium_tank", support="artillery")
        self.assertEqual(float(guns["speed"]), 1.5)
        self.assertEqual(int((guns.get("equipment") or {}).get("artillery", 0)), 12)
        self.assertIn("trucks", att.get("removed") or {})
        triple = compose(
            mobility="truck",
            armor="medium_tank",
            support="artillery,recon",
            infantry_bns=3,
            tank_bns=2,
        )
        self.assertEqual(int(triple["infantry_bns"]), 3)
        self.assertEqual(int(triple["tank_bns"]), 2)
        self.assertGreater(int(triple["manpower"]), int(mixed["manpower"]))
        self.assertEqual(int((triple.get("equipment") or {}).get("tanks", 0)), 20)
        self.assertAlmostEqual(float(triple["width"]), 12.0)
        self.assertGreater(float(triple["fuel_use"]), float(truck["fuel_use"]))
        self.assertIn("recon", list(triple.get("supports") or []))
        atg = compose(mobility="truck", support="anti_tank,engineer")
        self.assertAlmostEqual(float(atg["speed"]), 2.0)
        self.assertGreater(float(atg["hard"]), float(truck["hard"]))
        self.assertGreater(pierce_mult(1.25, 0.0), pierce_mult(0.15, 0.70))
        self.assertLess(shortage_mult({"infantry_equipment": 20}, {"infantry_equipment": 80}), 0.85)
        self.assertEqual(shortage_mult({}, {"infantry_equipment": 80}), 1.0)
        self.assertLess(fuel_speed_mult(0.10, 0.20), 0.80)
        self.assertEqual(fuel_speed_mult(1.0, 0.0), 1.0)
        self.assertLess(fuel_burn(1.0, 0.20, "march"), 1.0)

    def test_product_wiring(self) -> None:
        p = build_unit_composition_combat_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        i = unit_composition_combat_integrity()
        self.assertTrue(i.get("ok"), msg=i)


if __name__ == "__main__":
    unittest.main()
