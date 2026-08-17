#!/usr/bin/env python3
"""Gates: land battle depth (equip / CAS / planning / trench / recovery)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_depth_product import (  # noqa: E402
    build_land_battle_depth_product,
    cas_wing_power,
    daily_equip_severity,
    land_battle_depth_integrity,
    planning_bonus,
    trench_bonus,
)


class TestLandBattleDepthProduct(unittest.TestCase):
    def test_product_ok(self) -> None:
        p = build_land_battle_depth_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS", msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        g = land_battle_depth_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_planning_bonus(self) -> None:
        self.assertAlmostEqual(planning_bonus(0.8), 1.2)
        self.assertAlmostEqual(planning_bonus(0.0), 1.0)
        self.assertAlmostEqual(planning_bonus(1.0), 1.25)

    def test_trench_bonus(self) -> None:
        self.assertAlmostEqual(trench_bonus(1.0), 1.2)
        self.assertAlmostEqual(trench_bonus(0.0), 1.0)
        self.assertAlmostEqual(trench_bonus(0.5), 1.1)

    def test_daily_equip_severity_loser_gt_winner(self) -> None:
        self.assertGreater(
            daily_equip_severity("defender", "attacker"),
            daily_equip_severity("attacker", "attacker"),
        )
        self.assertGreater(
            daily_equip_severity("attacker", "defender"),
            daily_equip_severity("defender", "defender"),
        )
        self.assertAlmostEqual(daily_equip_severity("attacker", "even"), 0.08)
        self.assertAlmostEqual(daily_equip_severity("defender", "even"), 0.10)

    def test_cas_wing_power(self) -> None:
        self.assertAlmostEqual(cas_wing_power(1.0, "CAS"), 30.0)
        self.assertAlmostEqual(cas_wing_power(0.5, "INTERDICTION"), 12.5)
        self.assertEqual(cas_wing_power(1.0, "RECON"), 0.0)


if __name__ == "__main__":
    unittest.main()
