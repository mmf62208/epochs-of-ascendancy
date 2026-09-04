#!/usr/bin/env python3
"""Gate: living unit order loop wiring (Maginot chips + march + assault)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from living_unit_order_loop_product import (  # noqa: E402
    CHI_FRONT,
    ENG_CHANNEL,
    ENG_NORTH_SEA,
    FRA_FRONT,
    GER_CAPITAL,
    GER_FRONT,
    JAP_FRONT,
    MAGINOT_REGION,
    TIME_MANAGER,
    build_living_unit_order_loop_product,
    living_clock_skips_ai_starts,
    living_clock_skips_occupation_ticks,
    living_unit_order_loop_integrity,
)


class TestLivingUnitOrderLoopProduct(unittest.TestCase):
    def test_front_ids(self) -> None:
        self.assertEqual(GER_FRONT, 710173)
        self.assertEqual(FRA_FRONT, 710739)
        self.assertEqual(JAP_FRONT, 903981)
        self.assertEqual(CHI_FRONT, 902598)
        self.assertEqual(ENG_CHANNEL, 950001)
        self.assertEqual(ENG_NORTH_SEA, 950000)
        self.assertEqual(MAGINOT_REGION, 100)
        self.assertEqual(GER_CAPITAL, 710300)

    def test_product_wiring(self) -> None:
        p = build_living_unit_order_loop_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "park_maginot",
            "world_oob_majors",
            "park_channel_fleet",
            "sea_hop_api",
            "choke_flag",
            "air_region_cas",
            "world_oob_air_naval",
            "peace_occupation",
            "ai_take_land",
            "nation_era_next",
            "map_country_select",
            "playtest_clock",
            "f5_boot_unlocks",
            "chip_str_num",
            "inverse_zoom_scale",
            "chip_on_centroid",
            "pin_before_hex",
            "capital_star_before_chip",
            "click_own_land_marches",
            "ctrl_click_starts_battle",
            "g_hang_safe",
            "inspector_close_restores",
            "i_hang_safe",
            "warloop_hang_safe",
            "resolve_hang_safe",
            "strategic_pick_skip",
            "march_api",
            "battle_api",
            "f5_boot_and_qa",
            "headless_harness",
            "on_official_quick",
        ):
            self.assertTrue(wiring.get(key), msg=(key, p))

    def test_integrity(self) -> None:
        i = living_unit_order_loop_integrity()
        self.assertTrue(i.get("ok"), msg=i)

    def test_playtest_clock_does_not_skip_ai_starts(self) -> None:
        tm = TIME_MANAGER.read_text(encoding="utf-8")
        self.assertFalse(living_clock_skips_ai_starts(tm), msg=tm[tm.find("_maybe_run_ai_land_battle_starts"): tm.find("_maybe_run_ai_land_battle_starts") + 900])
        self.assertIn("try_ai_start_land_battles", tm)
        self.assertIn("ai_land_started_n", tm)

    def test_playtest_clock_does_not_skip_occupation_ticks(self) -> None:
        tm = TIME_MANAGER.read_text(encoding="utf-8")
        self.assertFalse(
            living_clock_skips_occupation_ticks(tm),
            msg=tm[tm.find("_maybe_tick_occupation_unrest") : tm.find("_maybe_tick_occupation_unrest") + 900],
        )
        self.assertIn("apply_occupation_daily_tick_live", tm)
        self.assertIn("occupation_tick_n", tm)


if __name__ == "__main__":
    unittest.main()
