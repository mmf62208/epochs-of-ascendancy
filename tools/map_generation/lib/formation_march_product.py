"""Formation march integrity — own-land hops + pin lerp wiring (PR 4).

Grep/wiring gate for MapManager.find_land_path(own_land_only), BattleManager
issue_march_order / station_formation_on_province / tick_marches_for_day,
MapRenderer march path, SaveLoadManager marches blob, FormationMovement.issue_march.
Does not execute Godot. G / corridor keep find_land_path default own_land_only=false.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
BATTLE_MANAGER = ROOT / "scripts" / "combat" / "BattleManager.gd"
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
FORMATION_MOVEMENT = ROOT / "scripts" / "formations" / "FormationMovement.gd"
SAVE_LOAD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"

MARCH_TOAST_PREFIX = "March ·"
OWN_LAND_ARG = "own_land_only"


def _gd_func_slice(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    lines = src[i:].splitlines()
    out = [lines[0]]
    for line in lines[1:]:
        if line.startswith("func "):
            break
        out.append(line)
    return "\n".join(out)


def build_formation_march_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    mm = MAP_MANAGER.read_text(encoding="utf-8") if MAP_MANAGER.is_file() else ""
    bm = BATTLE_MANAGER.read_text(encoding="utf-8") if BATTLE_MANAGER.is_file() else ""
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    fm = FORMATION_MOVEMENT.read_text(encoding="utf-8") if FORMATION_MOVEMENT.is_file() else ""
    sl = SAVE_LOAD.read_text(encoding="utf-8") if SAVE_LOAD.is_file() else ""

    if not mm:
        fails.append("missing_map_manager")
    if not bm:
        fails.append("missing_battle_manager")
    if not ren:
        fails.append("missing_map_renderer")
    if fails and (not mm or not bm or not ren):
        return {
            "ok": False,
            "status": "FAIL",
            "pass": passes,
            "fail": fails,
            "wiring": wiring,
            "summary": "formation_march · FAIL · missing sources",
        }

    # 1) find_land_path has own_land_only default false
    flp = _gd_func_slice(mm, "find_land_path")
    own_arg = OWN_LAND_ARG in flp and "bool = false" in flp
    wiring["find_land_path_own_land_only"] = own_arg
    if own_arg:
        passes.append("find_land_path_own_land_only")
    else:
        fails.append("find_land_path_own_land_only")

    # BFS must gate on controller when own_land_only (not post-filter only).
    own_bfs = (
        "own_land_only" in flp
        and ("controller_tag" in flp or "ctrl" in flp)
        and "if own_land_only" in flp
    )
    wiring["own_land_bfs_gate"] = own_bfs
    if own_bfs:
        passes.append("own_land_bfs_gate")
    else:
        fails.append("own_land_bfs_gate")

    # 2) station_formation_on_province: LeaderManager first, not SupplyManager alone
    station_fn = _gd_func_slice(bm, "station_formation_on_province")
    station_ok = (
        bool(station_fn)
        and "stationed_province_id" in station_fn
        and "LeaderManager" in station_fn
        and "division_deployments" in station_fn
    )
    wiring["station_formation_on_province"] = station_ok
    if station_ok:
        passes.append("station_formation_on_province")
    else:
        fails.append("station_formation_on_province")

    # 3) issue_march_order: own_land_only=true, max hops 48, battle block, instant
    issue_fn = _gd_func_slice(bm, "issue_march_order")
    issue_ok = (
        bool(issue_fn)
        and "find_land_path" in issue_fn
        and ("own_land_only" in issue_fn or ", true)" in issue_fn)
        and "instant" in issue_fn
        and ("_battles" in issue_fn or "_formation_in_active_battle" in issue_fn)
        and "station_formation_on_province" in issue_fn
    )
    # Prefer explicit true 5th arg for own-land
    issue_own = "true)" in issue_fn or "own_land_only" in issue_fn
    wiring["issue_march_order"] = issue_ok and issue_own
    if issue_ok and issue_own:
        passes.append("issue_march_order")
    else:
        fails.append("issue_march_order")

    # 4) tick_marches_for_day: hours_acc += 24, station hop, notify light
    tick_fn = _gd_func_slice(bm, "tick_marches_for_day")
    tick_ok = (
        bool(tick_fn)
        and "hours_acc" in tick_fn
        and "station_formation_on_province" in tick_fn
        and ("_notify_map_refresh" in tick_fn or "_update_unit_icons_for_pids" in tick_fn)
    )
    wiring["tick_marches_for_day"] = tick_ok
    if tick_ok:
        passes.append("tick_marches_for_day")
    else:
        fails.append("tick_marches_for_day")

    # Connected to game_day_advanced (no TimeManager flush rewrite)
    day_conn = (
        "game_day_advanced" in bm
        and "tick_marches_for_day" in bm
        and ("_on_game_day_advanced_marches" in bm or "tick_marches_for_day" in _gd_func_slice(bm, "_ready"))
    )
    wiring["day_tick_connect"] = day_conn
    if day_conn:
        passes.append("day_tick_connect")
    else:
        fails.append("day_tick_connect")

    # 5) MapRenderer move → issue_march_order; toast; lerp; Line2D budget 8
    move_fn = _gd_func_slice(ren, "_try_move_selected_unit_to_province")
    move_march = bool(move_fn) and "issue_march_order" in move_fn
    wiring["renderer_issue_march"] = move_march
    if move_march:
        passes.append("renderer_issue_march")
    else:
        fails.append("renderer_issue_march")

    toast_ok = MARCH_TOAST_PREFIX in ren and "hexes" in ren
    wiring["march_toast"] = toast_ok
    if toast_ok:
        passes.append("march_toast")
    else:
        fails.append("march_toast")

    lerp_ok = (
        "_update_march_visuals" in ren
        and "visual_t" in ren
        and "lerp" in ren.lower()
    )
    wiring["pin_lerp"] = lerp_ok
    if lerp_ok:
        passes.append("pin_lerp")
    else:
        fails.append("pin_lerp")

    line_ok = (
        "MARCH_PATH_LINE_BUDGET" in ren
        and ("8" in ren)
        and ("MarchPath" in ren or "_march_path" in ren)
        and "Line2D" in ren
    )
    wiring["path_line_budget_8"] = line_ok
    if line_ok:
        passes.append("path_line_budget_8")
    else:
        fails.append("path_line_budget_8")

    # No full-board icon rebuild on hop from BM tick path
    no_full = "rebuild_demo_unit_icons({})" not in tick_fn and "_update_unit_icons_for_test" not in tick_fn
    wiring["no_full_board_on_hop"] = no_full
    if no_full:
        passes.append("no_full_board_on_hop")
    else:
        fails.append("no_full_board_on_hop")

    # 6) FormationMovement.issue_march delegates
    fm_ok = "func issue_march" in fm and "issue_march_order" in fm
    wiring["formation_movement_issue_march"] = fm_ok
    if fm_ok:
        passes.append("formation_movement_issue_march")
    else:
        fails.append("formation_movement_issue_march")

    # 7) SaveLoadManager marches blob
    save_ok = (
        '"marches"' in sl
        and "BattleManager" in sl
        and ("apply_save_data" in sl)
    )
    wiring["save_marches_blob"] = save_ok
    if save_ok:
        passes.append("save_marches_blob")
    else:
        fails.append("save_marches_blob")

    # 8) Block on _battles row not is_in_combat alone
    block_ok = (
        "_formation_in_active_battle" in bm or ("_battles" in issue_fn)
    ) and (
        "is_in_combat" not in issue_fn
        or issue_fn.find("_battles") < issue_fn.find("is_in_combat")
        if "is_in_combat" in issue_fn
        else True
    )
    wiring["block_on_battles_not_flag"] = block_ok
    if block_ok:
        passes.append("block_on_battles_not_flag")
    else:
        fails.append("block_on_battles_not_flag")

    if not check_wiring:
        ok = own_arg and issue_ok
    else:
        ok = len(fails) == 0

    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "formation_march · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "integration": [
            "formation_march_product",
            "MapManager.find_land_path own_land_only",
            "BattleManager.issue_march_order",
            "BattleManager.station_formation_on_province",
            "MapRenderer._try_move_selected_unit_to_province",
        ],
        "policy": (
            "own_land_bfs_no_post_filter"
            "; station_leader_first"
            "; block_active_battles_row_not_is_in_combat_alone"
            "; pid_scoped_icons_on_hop"
        ),
    }


def formation_march_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_formation_march_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
