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
    HARNESS,
    JAP_FRONT,
    MAGINOT_REGION,
    TIME_MANAGER,
    build_living_unit_order_loop_product,
    living_clock_skips_ai_starts,
    living_clock_skips_occupation_ticks,
    living_clock_theater_beat_ok,
    living_playtest_theater_beat_keys,
    living_unit_order_loop_integrity,
)
from order_panel_play_strip_product import (  # noqa: E402
    build_order_panel_play_strip_product,
)
from play_next_hook_product import rank_next_beat  # noqa: E402


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

    def test_living_playtest_theater_beat(self) -> None:
        keys = living_playtest_theater_beat_keys()
        self.assertEqual(keys.get("source"), "choke")
        self.assertEqual(keys.get("action"), "choke_flag")
        self.assertEqual(keys.get("from_id"), 950001)
        self.assertEqual(keys.get("to_id"), 950001)
        self.assertEqual(keys.get("from_id"), ENG_CHANNEL)
        self.assertEqual(keys.get("news_headline"), "Channel choke 950001")
        self.assertEqual(keys.get("choke_flag"), True)
        tm = TIME_MANAGER.read_text(encoding="utf-8")
        harness = HARNESS.read_text(encoding="utf-8")
        self.assertTrue(living_clock_skips_ai_starts(tm), msg="living clock must skip unbounded try_ai")
        self.assertTrue(living_clock_theater_beat_ok(tm, harness), msg=tm[tm.find("_record_living_playtest_theater_beat"): tm.find("_record_living_playtest_theater_beat") + 900])
        mag = rank_next_beat(
            {
                "maginot_ready": True,
                "maginot_fid": "ger_front",
                "maginot_from": GER_FRONT,
                "maginot_to": FRA_FRONT,
            }
        )
        self.assertEqual(mag.get("source"), "maginot")
        self.assertEqual(mag.get("action"), "open_fight")
        self.assertEqual(mag.get("from_id"), GER_FRONT)
        self.assertEqual(mag.get("to_id"), FRA_FRONT)
        self.assertNotEqual(mag.get("source"), "first_session")
        self.assertNotEqual(mag.get("action"), "show_war_loop")
        strip = build_order_panel_play_strip_product()
        self.assertTrue(strip.get("ok"), msg=strip)

    def test_playtest_clock_skips_unbounded_ai_starts(self) -> None:
        tm = TIME_MANAGER.read_text(encoding="utf-8")
        self.assertTrue(living_clock_skips_ai_starts(tm), msg=tm[tm.find("_maybe_run_ai_land_battle_starts"): tm.find("_maybe_run_ai_land_battle_starts") + 900])
        self.assertIn("try_ai_start_land_battles", tm)
        self.assertIn("_record_living_playtest_theater_beat", tm)

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
