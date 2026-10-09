#!/usr/bin/env python3
"""Gates: PERF-4 daily sim-tick hitch (peace_state peek + owner index + timers)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from perf4_daily_sim_tick_product import (  # noqa: E402
    AIM_FRAME_BUDGET_MS,
    DAY_TICK_FRAME_BUDGET_MS,
    build_perf4_daily_sim_tick_product,
    extract_gd_func_body,
    perf4_daily_sim_tick_integrity,
)


class TestPerf4DailySimTickProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_perf4_daily_sim_tick_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(int(p.get("budget_ms") or 0), DAY_TICK_FRAME_BUDGET_MS)
        self.assertEqual(int(p.get("aim_ms") or 0), AIM_FRAME_BUDGET_MS)

    def test_integrity(self) -> None:
        g = perf4_daily_sim_tick_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_budget_constants(self) -> None:
        self.assertEqual(DAY_TICK_FRAME_BUDGET_MS, 500)
        self.assertLess(AIM_FRAME_BUDGET_MS, DAY_TICK_FRAME_BUDGET_MS)

    def test_get_peace_state_body_has_no_deepcopy(self) -> None:
        src = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        body = extract_gd_func_body(src, "get_peace_state")
        self.assertIn("peek_peace_state", body)
        self.assertNotIn("duplicate(true)", body)

    def test_multi_ai_fix_needles(self) -> None:
        p = build_perf4_daily_sim_tick_product()
        for key in (
            "multi_ai_country_profile",
            "soft_supply_uses_full_day",
            "production_day_cache",
            "production_line_scan_count",
            "line_owner_index_hot_path",
            "supply_interactive_light",
            "supply_day_full_steps_in_live",
            "supply_capture_owner_refresh",
            "map_owner_notifies_supply",
            "supply_network_build_count",
            "regional_control_owner_index",
            "owner_index_build_count",
            "headless_multi_ai_budget_test",
            "multi_ai_wired_into_gates",
            "depot_rebuild_on_change_only",
            "depot_skips_missing_pid",
            "headless_live_multi_ai_test",
            "headless_capture_rebuild_case",
            "headless_repeated_real_depot",
            "headless_production_cache_timing",
            "headless_owner_index_timing",
            "headless_capture_frame_budget",
            "headless_peace_annex_supply",
            "headless_one_full_supply_day",
            "headless_replanned_off_must_fail",
            "headless_ten_capture_path_identity",
            "headless_annex_path_identity",
            "headless_hub_capacity_day40",
            "route_refresh_covers_all_dests_in_one_day",
            "supply_hub_stats_refresh",
            "infra_dev_notifies_hub_stats",
            "supply_day_spike_profile",
            "same_day_dest_drain",
            "pathfinder_binary_heap",
            "headless_depot_add_converges",
            "headless_recapture_converges",
            "headless_multi_round_capture_converges",
            "headless_keep_old_routes",
            "headless_ten_capture_1x_4x_drain",
            "headless_slice_plan_cap",
            "headless_no_200ms_wall",
            "headless_recapture_path_identity",
            "headless_access_path_identity",
            "headless_fifo_order",
            "headless_slice_estimate_seam",
            "headless_dayroll_capture_frame",
            "headless_dayroll_own_share",
            "headless_redrop_behaviour",
            "headless_depot_subset_replans",
            "headless_no_ten_capture_wall",
            "headless_gamedata_infra_behaviour",
            "fifo_refill_no_redrop",
            "predictive_40ms_slice",
            "slice_plan_cost_estimate_seam",
            "flush_redrop_counters_increment",
            "friendly_gain_enqueues_all_dests",
            "access_enqueues_all_dests",
            "access_deferred_player_party",
            "day_roll_defers_route_plans",
            "depot_enqueues_touched_dests_only",
            "keep_old_routes_until_swap",
            "relations_clears_friendly_cache",
            "gamedata_direct_infra_notifies_hub",
            "depot_one_hub_patch",
            "supply_capture_no_full_route_rebuild",
            "daily_listener_light_split",
            "full_supply_day_count",
            "peace_annex_notifies_supply",
            "live_multi_ai_wired_into_gates",
        ):
            self.assertIn(key, p.get("passes") or [], msg=p)

    def test_set_player_depot_rebuilds_only_on_change(self) -> None:
        src = (ROOT / "scripts" / "supply" / "SupplyManager.gd").read_text(
            encoding="utf-8"
        )
        body = extract_gd_func_body(src, "set_player_depot")
        self.assertIn("changed", body)
        self.assertNotIn("build_network", body)
        self.assertIn("_patch_player_depot_hub", body)
        self.assertIn("provinces.has", body)

    def test_supply_capture_refresh_and_full_day(self) -> None:
        src = (ROOT / "scripts" / "supply" / "SupplyManager.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("func notify_province_control_changed", src)
        self.assertIn("network_build_count", src)
        notify = extract_gd_func_body(src, "notify_province_control_changed")
        self.assertNotIn("_rebuild_default_routes", notify)
        self.assertIn("_drop_routes_touching_pid", notify)
        listen = extract_gd_func_body(src, "_on_game_day_advanced")
        self.assertIn("_advance_supply_day_light", listen)
        self.assertIn("is_interactive_light_sim", listen)
        adv = extract_gd_func_body(src, "advance_supply_day")
        self.assertIn("_process_air_missions", adv)
        self.assertIn("_process_naval_recon", adv)
        self.assertNotIn("is_live_f5_play_path", adv)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        mut = extract_gd_func_body(gd, "apply_supply_route_mutation")
        self.assertIn("advance_supply_day", mut)
        self.assertNotIn("advance_supply_day_interactive_light", mut)
        peace = extract_gd_func_body(gd, "apply_peace_conference_settlement_live")
        self.assertTrue(
            "update_province_owner" in peace or "notify_province_control_changed" in peace
        )

    def test_fix4_same_day_refill_and_hub_stats(self) -> None:
        sm = (ROOT / "scripts" / "supply" / "SupplyManager.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("DEFAULT_ROUTE_DEST_CAP: int = 24", sm)
        self.assertIn("ROUTE_REFRESH_BUDGET_PER_FLUSH: int = DEFAULT_ROUTE_DEST_CAP", sm)
        self.assertNotIn("ROUTE_REFRESH_BUDGET_PER_FLUSH: int = 2", sm)
        self.assertIn("ROUTE_REFRESH_MS_BUDGET", sm)
        self.assertIn("ROUTE_REFRESH_MS_BUDGET: float = 40.0", sm)
        self.assertIn("_refill_queue", sm)
        self.assertIn("func drain_pending_route_refresh", sm)
        self.assertIn("func notify_hub_stats_changed", sm)
        flush = extract_gd_func_body(sm, "flush_pending_control_route_refresh")
        self.assertNotIn("_drop_routes_touching_pid(", flush)
        self.assertIn("_refill_queued_dests", flush)
        self.assertIn("last_supply_day_profile", sm)
        mm = (ROOT / "scripts" / "map" / "MapManager.gd").read_text(encoding="utf-8")
        self.assertIn("notify_hub_stats_changed", extract_gd_func_body(mm, "update_province_infrastructure"))
        self.assertIn("notify_hub_stats_changed", extract_gd_func_body(mm, "update_province_development"))
        pf = (ROOT / "scripts" / "supply" / "SupplyPathfinder.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("_heap_push", pf)
        self.assertNotIn("open.sort_custom", pf)
        hd = (ROOT / "scripts" / "core" / "HeadlessPerf4LiveMultiAiDayTest.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("_test_replanned_off_must_fail", hd)
        self.assertIn("_test_ten_capture_path_identity_within_one_day", hd)
        self.assertIn("_test_annex_path_identity", hd)
        self.assertIn("_test_hub_capacity_matches_rebuild_at_day_40", hd)
        self.assertIn("_test_depot_add_710314_converges", hd)
        self.assertIn("_test_recapture_ger_converges", hd)
        self.assertIn("_test_keep_old_routes_until_swap", hd)
        self.assertIn("_test_recapture_710314_path_identity", hd)
        self.assertIn("_test_military_access_path_identity", hd)
        self.assertIn("_test_fifo_dequeue_matches_enqueue", hd)
        self.assertIn("_test_slice_predictive_vs_reactive_seam", hd)
        self.assertIn("_test_dayroll_event_own_share_under_300ms", hd)
        self.assertIn("_test_redrop_counter_increments_on_hostile_drop", hd)
        self.assertIn("_test_depot_add_replans_only_touched_dests", hd)
        self.assertIn("DAYROLL_OWN_SHARE_BUDGET_MS", hd)
        self.assertNotIn("QUIET_DAY_BUDGET_MS", hd)
        self.assertNotIn("TEN_CAPTURE_FRAME_BUDGET_MS", hd)

    def test_live_multi_ai_harness_exists(self) -> None:
        hd = ROOT / "scripts" / "core" / "HeadlessPerf4LiveMultiAiDayTest.gd"
        self.assertTrue(hd.is_file())
        text = hd.read_text(encoding="utf-8")
        self.assertIn("apply_interactive_multi_ai_day_live", text)
        self.assertIn("boot_living_player", text)


if __name__ == "__main__":
    unittest.main()
