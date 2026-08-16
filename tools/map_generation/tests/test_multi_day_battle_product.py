#!/usr/bin/env python3
"""Gates: multi-day battle daily slices + Maginot break math + wiring (PR 5)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from multi_day_battle_product import (  # noqa: E402
    ATTACKER_INITIATIVE,
    build_multi_day_battle_product,
    daily_deltas,
    multi_day_battle_integrity,
    simulate_maginot_slices,
    unit_power,
)


class TestMultiDayBattleProduct(unittest.TestCase):
    def test_unit_power_initiative(self) -> None:
        base = unit_power(0.9, 0.955, 1.0, 1.0, 0.85, 0.0)
        with_i = unit_power(0.9, 0.955, 1.0, 1.0, 0.85, ATTACKER_INITIATIVE)
        self.assertAlmostEqual(with_i - base, ATTACKER_INITIATIVE, places=5)
        self.assertGreater(with_i, 2.0)
        self.assertLess(with_i, 3.0)

    def test_daily_deltas(self) -> None:
        lo, wo, ls, ws = daily_deltas(0.036)
        self.assertAlmostEqual(lo, 0.12 + 0.08 * 0.036, places=5)
        self.assertAlmostEqual(ls, 0.10 + 0.06 * 0.036, places=5)
        self.assertLess(wo, lo)

    def test_maginot_defender_broke_band(self) -> None:
        sim = simulate_maginot_slices()
        self.assertTrue(sim.get("att_wins_slice0"), msg=sim)
        self.assertEqual(sim.get("terminal"), "defender_broke", msg=sim)
        day = int(sim.get("break_day") or -1)
        self.assertGreaterEqual(day, 5, msg=sim)
        self.assertLessEqual(day, 8, msg=sim)

    def test_without_initiative_attacker_not_favored(self) -> None:
        no_i = simulate_maginot_slices(initiative=0.0, recompute_power=False)
        self.assertFalse(no_i.get("att_wins_slice0"), msg=no_i)

    def test_product_math_only(self) -> None:
        p = build_multi_day_battle_product(check_wiring=False)
        self.assertTrue(p.get("ok"), msg=p)

    def test_product_wiring(self) -> None:
        p = build_multi_day_battle_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p.get("fail") or p)
        wiring = p.get("wiring") or {}
        for key in (
            "maginot_defender_broke_day_5_8",
            "initiative_flips_slice",
            "start_province_battle",
            "tick_battles_additive",
            "tick_round_robin",
            "start_blocks_shared_defender",
            "is_in_combat_clear_if_not_other",
            "can_blocks_engaged_fid",
            "str_break_constants",
            "apply_province_capture",
            "end_and_withdraw",
            "execute_stays_one_shot",
            "map_confirm_starts_battle",
            "esc_withdraw_then_card",
            "strip_starts_battle",
            "mapmanager_stage_oneshot",
            "preview_join_battle_copy",
            "battles_save_blob",
            "one_shot_clears_is_in_combat",
            "live_battle_day_toast",
            "live_unit_card_battle_refresh",
            "live_battle_pin_chrome",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))

    def test_integrity(self) -> None:
        g = multi_day_battle_integrity(check_wiring=True)
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
