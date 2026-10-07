"""PERF-4 daily sim-tick hitch — instrument + cheap peace_state + owner index.

Live 1x Play (Begin GER 1936) hitch ~1.7–1.9s once per in-game day. First
slice: GameData.get_peace_state deepcopy + 3520 owner walk. FIX #1: the
remaining live hitch was `_maybe_run_interactive_multi_ai` → apply_supply
→ SupplyManager.set_player_depot(1) rebuilding the F5 supply network every
day. The stripped HeadlessPerf4DailySimTickTest never built that network.

This product greps the shipped path. Headless
`HeadlessPerf4DailySimTickTest` times the cheap day flush.
`HeadlessPerf4LiveMultiAiDayTest` and `HeadlessPerf4InteractiveMultiAiTest`
boot GER + a live-weight supply network and time the Play multi-AI step.
Soft theater tick does not rebuild the network for dummy pid 1. Live Play
still runs the full advance_supply_day steps (air / naval / shipping).
A depot/hub owner flip retags the hub and drops touching routes (no
24-route rebuild). Depot add/remove patches one hub. Daily listener
stays on main's light path so apply_supply is the one full day.
Production shares a per-day line-owner cache; owner index is counted + timed.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
TM_GD = ROOT / "scripts" / "autoload" / "TimeManager.gd"
MM_GD = ROOT / "scripts" / "map" / "MapManager.gd"
IDM_GD = ROOT / "scripts" / "map" / "InfrastructureDevelopmentManager.gd"
HD_GD = ROOT / "scripts" / "core" / "HeadlessPerf4DailySimTickTest.gd"
HD_MULTI_GD = ROOT / "scripts" / "core" / "HeadlessPerf4InteractiveMultiAiTest.gd"
HD_LIVE_GD = ROOT / "scripts" / "core" / "HeadlessPerf4LiveMultiAiDayTest.gd"
PM_GD = ROOT / "scripts" / "autoload" / "ProductionManager.gd"
SM_GD = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GATES_SH = ROOT / "tools" / "eoa_full_test_gates.sh"

DAY_TICK_FRAME_BUDGET_MS = 500
AIM_FRAME_BUDGET_MS = 250
KILLSWITCH_INFRA = "EOA_AI_INFRA=0"
PROFILE_ENV = "EOA_DAY_TICK_PROFILE"


def extract_gd_func_body(src: str, func_name: str) -> str:
    needle = "func %s(" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    lines = src[i:].splitlines()
    out = [lines[0]]
    for line in lines[1:]:
        if line.startswith("func ") or line.startswith("static func "):
            break
        out.append(line)
    return "\n".join(out)


def _read(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8")


def build_perf4_daily_sim_tick_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    gd = _read(GD_GD)
    tm = _read(TM_GD)
    mm = _read(MM_GD)
    idm = _read(IDM_GD)
    hd = _read(HD_GD)
    hd_multi = _read(HD_MULTI_GD)
    hd_live = _read(HD_LIVE_GD)
    pm = _read(PM_GD)
    sm = _read(SM_GD)
    gates = _read(GATES_SH)

    peek = extract_gd_func_body(gd, "peek_peace_state")
    get_ps = extract_gd_func_body(gd, "get_peace_state")
    copy_ps = extract_gd_func_body(gd, "get_peace_state_copy")
    if peek and "return peace_state" in peek and "duplicate(" not in peek:
        passes.append("peek_peace_state_live_ref")
    else:
        fails.append("peek_peace_state_live_ref")
    if get_ps and "duplicate(true)" not in get_ps and "peek_peace_state" in get_ps:
        passes.append("get_peace_state_no_deepcopy")
    else:
        fails.append("get_peace_state_no_deepcopy")
    if copy_ps and "duplicate(true)" in copy_ps:
        passes.append("get_peace_state_copy_snapshot")
    else:
        fails.append("get_peace_state_copy_snapshot")

    if "DAY_TICK_FRAME_BUDGET_MS" in tm and str(DAY_TICK_FRAME_BUDGET_MS) in tm:
        passes.append("day_tick_budget_const")
    else:
        fails.append("day_tick_budget_const")
    emit_fn = extract_gd_func_body(tm, "_emit_game_day_advanced_profiled")
    if emit_fn and "get_signal_connection_list" in emit_fn and "game_day_advanced" in emit_fn:
        passes.append("per_listener_timers")
    else:
        fails.append("per_listener_timers")
    if "_profile_day_ai_steps" in tm and "ai_infra" in tm and "ai_land" in tm:
        passes.append("day_ai_step_timers")
    else:
        fails.append("day_ai_step_timers")
    if tm.count("game_day_advanced.emit") == 0 and "_emit_game_day_advanced_profiled" in tm:
        passes.append("emit_routed_through_profile")
    else:
        fails.append("emit_routed_through_profile")

    owner_fn = extract_gd_func_body(mm, "get_provinces_by_owner")
    ensure_fn = extract_gd_func_body(mm, "_ensure_owner_index")
    if owner_fn and "_ensure_owner_index" in owner_fn:
        passes.append("owner_index_hot_path")
    else:
        fails.append("owner_index_hot_path")
    if ensure_fn and "_owner_index" in ensure_fn and "owner_index_build_count" in ensure_fn:
        passes.append("owner_index_builder")
    else:
        fails.append("owner_index_builder")
    if "var owner_index_build_count" in mm:
        passes.append("owner_index_build_count")
    else:
        fails.append("owner_index_build_count")

    try_fn = extract_gd_func_body(idm, "try_start_infrastructure_investment")
    if try_fn and "peek_peace_state" in try_fn:
        passes.append("infra_start_peeks_peace")
    else:
        fails.append("infra_start_peeks_peace")

    depot_fn = extract_gd_func_body(sm, "set_player_depot")
    if (
        depot_fn
        and "changed" in depot_fn
        and "build_network" not in depot_fn
        and "_patch_player_depot_hub" in depot_fn
    ):
        passes.append("depot_rebuild_on_change_only")
        passes.append("depot_one_hub_patch")
    else:
        fails.append("depot_rebuild_on_change_only")
        fails.append("depot_one_hub_patch")
    if depot_fn and "provinces.has" in depot_fn:
        passes.append("depot_skips_missing_pid")
    else:
        fails.append("depot_skips_missing_pid")
    adv_fn = extract_gd_func_body(sm, "advance_supply_day")
    if (
        adv_fn
        and "_process_air_missions" in adv_fn
        and "_process_naval_recon" in adv_fn
        and "is_live_f5_play_path" not in adv_fn
        and "is_interactive_light_sim" not in adv_fn
    ):
        passes.append("supply_day_full_steps_in_live")
    else:
        fails.append("supply_day_full_steps_in_live")
    notify_fn = extract_gd_func_body(sm, "notify_province_control_changed")
    if (
        notify_fn
        and "network_ownership_refresh_count" in notify_fn
        and "_rebuild_default_routes" not in notify_fn
        and "_drop_routes_touching_pid" in notify_fn
    ):
        passes.append("supply_capture_owner_refresh")
        passes.append("supply_capture_no_full_route_rebuild")
    else:
        fails.append("supply_capture_owner_refresh")
        fails.append("supply_capture_no_full_route_rebuild")
    day_listen = extract_gd_func_body(sm, "_on_game_day_advanced")
    if day_listen and "_advance_supply_day_light" in day_listen and "is_interactive_light_sim" in day_listen:
        passes.append("daily_listener_light_split")
    else:
        fails.append("daily_listener_light_split")
    if "var full_supply_day_count" in sm:
        passes.append("full_supply_day_count")
    else:
        fails.append("full_supply_day_count")
    peace_fn = extract_gd_func_body(gd, "apply_peace_conference_settlement_live")
    if peace_fn and (
        "update_province_owner" in peace_fn or "notify_province_control_changed" in peace_fn
    ):
        passes.append("peace_annex_notifies_supply")
    else:
        fails.append("peace_annex_notifies_supply")
    owner_upd = extract_gd_func_body(mm, "update_province_owner")
    if owner_upd and "notify_province_control_changed" in owner_upd:
        passes.append("map_owner_notifies_supply")
    else:
        fails.append("map_owner_notifies_supply")
    if "network_build_count" in sm:
        passes.append("supply_network_build_count")
    else:
        fails.append("supply_network_build_count")
    supply_fn = extract_gd_func_body(gd, "apply_supply_route_mutation")
    if supply_fn and "get_province" in supply_fn and "set_player_depot" in supply_fn:
        passes.append("apply_supply_requires_real_province")
    else:
        fails.append("apply_supply_requires_real_province")
    live_fn = extract_gd_func_body(gd, "apply_interactive_multi_ai_day_live")
    if live_fn and "apply_production_for_tag" in live_fn and "apply_order_panel_action" in live_fn:
        passes.append("multi_ai_still_runs_prod_and_supply")
    else:
        fails.append("multi_ai_still_runs_prod_and_supply")

    if HD_GD.is_file() and "DAY_TICK_FRAME_BUDGET_MS" in hd and "RESULT=" in hd and "FRA no_candidate" in hd:
        passes.append("headless_budget_test")
    else:
        fails.append("headless_budget_test")
    if (
        HD_LIVE_GD.is_file()
        and "apply_interactive_multi_ai_day_live" in hd_live
        and "RESULT=" in hd_live
        and "CAPTURE_HUB_PID" in hd_live
        and "REPEAT_DEPOT_ADDS" in hd_live
    ):
        passes.append("headless_live_multi_ai_test")
    else:
        fails.append("headless_live_multi_ai_test")
    if HD_LIVE_GD.is_file() and "_test_capture_matches_full_rebuild" in hd_live:
        passes.append("headless_capture_rebuild_case")
    else:
        fails.append("headless_capture_rebuild_case")
    if HD_LIVE_GD.is_file() and "_test_repeated_real_depot_guard" in hd_live:
        passes.append("headless_repeated_real_depot")
    else:
        fails.append("headless_repeated_real_depot")
    if HD_LIVE_GD.is_file() and "_test_production_cache_measured" in hd_live:
        passes.append("headless_production_cache_timing")
    else:
        fails.append("headless_production_cache_timing")
    if HD_LIVE_GD.is_file() and "_test_owner_index_measured" in hd_live:
        passes.append("headless_owner_index_timing")
    else:
        fails.append("headless_owner_index_timing")
    if HD_LIVE_GD.is_file() and "_test_capture_frame_budgets" in hd_live:
        passes.append("headless_capture_frame_budget")
    else:
        fails.append("headless_capture_frame_budget")
    if HD_LIVE_GD.is_file() and "_test_peace_annexation_updates_supply" in hd_live:
        passes.append("headless_peace_annex_supply")
    else:
        fails.append("headless_peace_annex_supply")
    if HD_LIVE_GD.is_file() and "_test_one_full_supply_day_per_game_day" in hd_live:
        passes.append("headless_one_full_supply_day")
    else:
        fails.append("headless_one_full_supply_day")
    if "launch_perf4_daily_sim_tick" in gates:
        passes.append("wired_into_gates")
    else:
        fails.append("wired_into_gates")
    if "launch_perf4_live_multi_ai_day" in gates:
        passes.append("live_multi_ai_wired_into_gates")
    else:
        fails.append("live_multi_ai_wired_into_gates")
    if "test_perf4_daily_sim_tick_product" in gates:
        passes.append("wired_into_quick")
    else:
        fails.append("wired_into_quick")

    live_ai = extract_gd_func_body(gd, "apply_interactive_multi_ai_day_live")
    if live_ai and "country_profile" in live_ai and "begin_interactive_multi_ai_day_cache" in live_ai:
        passes.append("multi_ai_country_profile")
    else:
        fails.append("multi_ai_country_profile")
    supply_fn = extract_gd_func_body(gd, "apply_supply_route_mutation")
    if (
        supply_fn
        and "advance_supply_day" in supply_fn
        and "advance_supply_day_interactive_light" not in supply_fn
    ):
        passes.append("soft_supply_uses_full_day")
    else:
        fails.append("soft_supply_uses_full_day")
    if "func begin_interactive_multi_ai_day_cache" in pm:
        passes.append("production_day_cache")
    else:
        fails.append("production_day_cache")
    if "interactive_ai_line_scan_count" in pm:
        passes.append("production_line_scan_count")
    else:
        fails.append("production_line_scan_count")
    adv_fn = extract_gd_func_body(pm, "advance_days_for_country")
    if adv_fn and "_interactive_ai_line_ids_by_owner" in adv_fn and "interactive_ai_line_scan_count" in adv_fn:
        passes.append("line_owner_index_hot_path")
    else:
        fails.append("line_owner_index_hot_path")
    if "func advance_supply_day_interactive_light" in sm:
        passes.append("supply_interactive_light")
    else:
        fails.append("supply_interactive_light")
    owner_set_fn = extract_gd_func_body(mm, "get_fully_controlled_strategic_regions")
    if owner_set_fn and "_owned_or_controlled_pid_set" in owner_set_fn:
        passes.append("regional_control_owner_index")
    else:
        fails.append("regional_control_owner_index")
    if HD_MULTI_GD.is_file() and "_maybe_run_interactive_multi_ai" in hd_multi and "FRAME_BUDGET_MS" in hd_multi:
        passes.append("headless_multi_ai_budget_test")
    else:
        fails.append("headless_multi_ai_budget_test")
    if "launch_perf4_interactive_multi_ai" in gates:
        passes.append("multi_ai_wired_into_gates")
    else:
        fails.append("multi_ai_wired_into_gates")

    ok = not fails
    return {
        "ok": ok,
        "passes": passes,
        "fails": fails,
        "budget_ms": DAY_TICK_FRAME_BUDGET_MS,
        "aim_ms": AIM_FRAME_BUDGET_MS,
        "killswitch": KILLSWITCH_INFRA,
        "profile_env": PROFILE_ENV,
        "live_api": "TimeManager.advance_live_f5_equivalent_days",
        "headless": "scripts/core/HeadlessPerf4DailySimTickTest.gd",
        "headless_live_multi_ai": "scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd",
        "headless_interactive_multi_ai": "scripts/core/HeadlessPerf4InteractiveMultiAiTest.gd",
    }


def perf4_daily_sim_tick_integrity() -> Dict[str, Any]:
    p = build_perf4_daily_sim_tick_product()
    return {"ok": bool(p.get("ok")), "fails": list(p.get("fails") or [])}
