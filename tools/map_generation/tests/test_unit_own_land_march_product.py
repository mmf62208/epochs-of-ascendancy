#!/usr/bin/env python3
"""Gates: own-land march hop ETA + legality (synthetic graph)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_own_land_march_product import (  # noqa: E402
    ARMOR_SPEED,
    FIXTURE_INFRA,
    INFANTRY_SPEED,
    build_unit_own_land_march_product,
    calendar_days,
    hop_days,
    march_legal,
    path_eta_days,
    unit_own_land_march_integrity,
)


class TestUnitOwnLandMarchProduct(unittest.TestCase):
    def test_product_ok(self) -> None:
        p = build_unit_own_land_march_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS", msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        g = unit_own_land_march_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_adjacent_plains_infantry_one_calendar_day(self) -> None:
        eta = hop_days(
            terrain="plains",
            infra=FIXTURE_INFRA,
            template_speed=INFANTRY_SPEED,
            template_kind="infantry",
        )
        self.assertEqual(calendar_days(eta), 1)

    def test_three_hop_plains_multi_day(self) -> None:
        hops = [
            {
                "terrain": "plains",
                "infra": FIXTURE_INFRA,
                "template_speed": INFANTRY_SPEED,
                "template_kind": "infantry",
            }
            for _ in range(3)
        ]
        eta = path_eta_days(hops)
        self.assertGreater(eta, 1.0)
        self.assertGreaterEqual(calendar_days(eta), 3)

    def test_mountain_costs_more_than_plains(self) -> None:
        plains = hop_days(
            terrain="plains",
            infra=FIXTURE_INFRA,
            template_speed=INFANTRY_SPEED,
            template_kind="infantry",
        )
        mountain = hop_days(
            terrain="mountain",
            infra=FIXTURE_INFRA,
            template_speed=INFANTRY_SPEED,
            template_kind="infantry",
        )
        self.assertGreater(mountain, plains)

    def test_armor_faster_plains_not_faster_mountain(self) -> None:
        inf_plains = hop_days(
            terrain="plains",
            infra=FIXTURE_INFRA,
            template_speed=INFANTRY_SPEED,
            template_kind="infantry",
        )
        arm_plains = hop_days(
            terrain="plains",
            infra=FIXTURE_INFRA,
            template_speed=ARMOR_SPEED,
            template_kind="armor",
        )
        inf_mtn = hop_days(
            terrain="mountain",
            infra=FIXTURE_INFRA,
            template_speed=INFANTRY_SPEED,
            template_kind="infantry",
        )
        arm_mtn = hop_days(
            terrain="mountain",
            infra=FIXTURE_INFRA,
            template_speed=ARMOR_SPEED,
            template_kind="armor",
        )
        self.assertLess(arm_plains, inf_plains)
        self.assertGreaterEqual(arm_mtn, inf_mtn)

    def test_enemy_and_sea_rejected(self) -> None:
        self.assertFalse(
            march_legal(dest_owner="FRA", player_tag="GER", dest_is_land=True)
        )
        self.assertFalse(
            march_legal(dest_owner="GER", player_tag="GER", dest_is_land=False)
        )
        self.assertTrue(
            march_legal(dest_owner="GER", player_tag="GER", dest_is_land=True)
        )


if __name__ == "__main__":
    unittest.main()
