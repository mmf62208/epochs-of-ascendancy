#!/usr/bin/env python3
"""Gates: multi-day land battle estimate + daily org tick (synthetic)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_multi_day_battle_product import (  # noqa: E402
    ARMOR_ATT_POWER,
    EVEN_POWER,
    ORG_BREAK,
    build_unit_multi_day_battle_product,
    daily_tick,
    estimate_battle_days,
    should_resolve_instant,
    unit_multi_day_battle_integrity,
)


class TestUnitMultiDayBattleProduct(unittest.TestCase):
    def test_product_ok(self) -> None:
        p = build_unit_multi_day_battle_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS", msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        g = unit_multi_day_battle_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_empty_defender_instant(self) -> None:
        days = estimate_battle_days(
            att_power=EVEN_POWER,
            def_power=0.0,
            terrain="plains",
            empty_defender=True,
        )
        self.assertEqual(days, 0)
        self.assertTrue(should_resolve_instant(empty_defender=True))
        self.assertFalse(should_resolve_instant(empty_defender=False))

    def test_even_fight_at_least_two_days(self) -> None:
        days = estimate_battle_days(
            att_power=EVEN_POWER,
            def_power=EVEN_POWER,
            terrain="plains",
            empty_defender=False,
        )
        self.assertGreaterEqual(days, 2)

    def test_armor_plains_faster_than_inf_mountain(self) -> None:
        armor_plains = estimate_battle_days(
            att_power=ARMOR_ATT_POWER,
            def_power=EVEN_POWER,
            terrain="plains",
            empty_defender=False,
        )
        inf_mtn = estimate_battle_days(
            att_power=EVEN_POWER,
            def_power=EVEN_POWER,
            terrain="mountain",
            empty_defender=False,
        )
        self.assertLess(armor_plains, inf_mtn)

    def test_shipped_path_wiring(self) -> None:
        p = build_unit_multi_day_battle_product()
        self.assertIn("battle_manager_land_battle_api", list(p.get("pass") or []), msg=p)
        self.assertIn("time_manager_land_battle_tick", list(p.get("pass") or []), msg=p)

    def test_even_first_tick_open_then_resolves(self) -> None:
        first = daily_tick(
            att_org=1.0,
            def_org=1.0,
            att_power=EVEN_POWER,
            def_power=EVEN_POWER,
            terrain="plains",
        )
        self.assertFalse(first.get("resolved"))
        self.assertGreaterEqual(float(first.get("att_org") or 0.0), ORG_BREAK)
        self.assertGreaterEqual(float(first.get("def_org") or 0.0), ORG_BREAK)

        state = first
        resolved = False
        for _ in range(23):
            state = daily_tick(
                att_org=float(state["att_org"]),
                def_org=float(state["def_org"]),
                att_power=EVEN_POWER,
                def_power=EVEN_POWER,
                terrain="plains",
            )
            if state.get("resolved"):
                resolved = True
                break
        self.assertTrue(resolved, msg=state)
        self.assertTrue(
            float(state["att_org"]) < ORG_BREAK or float(state["def_org"]) < ORG_BREAK
        )


if __name__ == "__main__":
    unittest.main()
