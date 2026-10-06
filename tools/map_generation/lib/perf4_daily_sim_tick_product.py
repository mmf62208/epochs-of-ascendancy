"""PERF-4 daily sim-tick hitch — instrument + cheap peace_state + owner index.

Live 1x Play (Begin GER 1936) hitch ~1.7–1.9s once per in-game day, aligned
with AI infra start / land-battle attrition. Dominant cost: GameData.get_peace_state
deep-copied the peace blob on every read (invest, battle preview, production).
Secondary: MapManager.get_provinces_by_owner walked ~3520 hexes per call.

This product greps the shipped path. Headless
`HeadlessPerf4DailySimTickTest` times the live-F5 day flush and checks
outcome equivalence (same AI infra decisions, same seed).
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
    if ensure_fn and "_owner_index" in ensure_fn:
        passes.append("owner_index_builder")
    else:
        fails.append("owner_index_builder")

    try_fn = extract_gd_func_body(idm, "try_start_infrastructure_investment")
    if try_fn and "peek_peace_state" in try_fn:
        passes.append("infra_start_peeks_peace")
    else:
        fails.append("infra_start_peeks_peace")

    if HD_GD.is_file() and "DAY_TICK_FRAME_BUDGET_MS" in hd and "RESULT=" in hd:
        passes.append("headless_budget_test")
    else:
        fails.append("headless_budget_test")
    if "launch_perf4_daily_sim_tick" in gates:
        passes.append("wired_into_gates")
    else:
        fails.append("wired_into_gates")
    if "test_perf4_daily_sim_tick_product" in gates:
        passes.append("wired_into_quick")
    else:
        fails.append("wired_into_quick")

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
    }


def perf4_daily_sim_tick_integrity() -> Dict[str, Any]:
    p = build_perf4_daily_sim_tick_product()
    return {"ok": bool(p.get("ok")), "fails": list(p.get("fails") or [])}
