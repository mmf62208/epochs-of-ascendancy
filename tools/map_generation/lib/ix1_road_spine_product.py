"""IX-1 Road Spine — Layer 2 first player↔map interconnect vertical.

Home Europe theater: GER-owned Rhineland city spine
Bonn 710416 — Köln 710417 — Leverkusen 710418 (3 adjacent land cells).

Player order (inspector Build Road Spine / Invest-style project) completes into:
  * MapManager.build_road_connection edges on the corridor
  * infrastructure +1 on the ordered province
  * built_road_neighbors movement discount in Province.get_movement_cost

RoadLayer draws those explicit edges at playable mid-zoom without F10-only toggles.

This product is a **one-corridor proof**. It does not mesh a continent, open
rail/industry, resume Dig2 / G polyline, or rewrite Maginot / Channel / Italy /
SE England / Tyrrhenian land or sea.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
SPEC_PATH = ROOT / "data" / "infrastructure" / "ix1_road_spine.json"
IDM_GD = ROOT / "scripts" / "map" / "InfrastructureDevelopmentManager.gd"
PROVINCE_GD = ROOT / "scripts" / "data" / "Province.gd"
MAP_MANAGER_GD = ROOT / "scripts" / "map" / "MapManager.gd"
OVERLAY_GD = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"
RENDERER_GD = ROOT / "scripts" / "map" / "MapRenderer.gd"
SEARCH_GD = ROOT / "scripts" / "ui" / "map" / "MapProvinceSearch.gd"
FORMATTERS_GD = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
FORMATTERS_PY = ROOT / "tools" / "map_generation" / "lib" / "map_polish_formatters.py"
SAVE_LOAD_GD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"
TIME_MANAGER_GD = ROOT / "scripts" / "autoload" / "TimeManager.gd"
DAY_TICK_HARNESS = ROOT / "scripts" / "core" / "HeadlessIx1RoadSpineDayTickTest.gd"
GATES_SH = ROOT / "tools" / "eoa_full_test_gates.sh"
ADJ_PATH = ROOT / "data" / "provinces_world_accurate" / "province_adjacency.json"
BASE_PATH = ROOT / "data" / "provinces_world_accurate" / "provinces_base.json"

SLICE_NAME = "IX-1 Road Spine"
OWNER_TAG = "GER"
HUB_ID = 710417
BONN_ID = 710416
LEVERKUSEN_ID = 710418
ESSEN_CONTROL_ID = 710403
# Fresh Begin · Germany · 1936: peace_state mandate map is empty → 0.
# Generic Köln Invest is 73; IX-1 uses this first-session starter cost only.
IX1_FIRST_SESSION_MANDATE_COST = 0
GER_1936_DAY0_MANDATE = 0
CORRIDOR_IDS: Tuple[int, ...] = (BONN_ID, HUB_ID, LEVERKUSEN_ID)
SPINE_EDGES: Tuple[Tuple[int, int], ...] = (
    (HUB_ID, BONN_ID),
    (HUB_ID, LEVERKUSEN_ID),
)
ROAD_INFRA_BONUS = 2.0
ROAD_NEIGHBOR_BONUS = 0.5
INFRA_STEP = 1
SHIPPED_API_NEEDLES: Tuple[Tuple[Path, str], ...] = (
    (IDM_GD, "try_start_road_spine"),
    (IDM_GD, "link_ix1_road_spine_edges"),
    (IDM_GD, "should_show_road_spine_button"),
    (IDM_GD, "get_ix1_road_spine_mandate_cost"),
    (IDM_GD, "ix1_day0_mandate_can_start"),
    (IDM_GD, "IX1_FIRST_SESSION_MANDATE_COST"),
    (IDM_GD, "_should_run_full_board_ai_invest"),
    (IDM_GD, "simulate_ix1_spine_days"),
    (SAVE_LOAD_GD, "_deferred_calendar_autosave"),
    (DAY_TICK_HARNESS, "past_freeze"),
    (GATES_SH, "HeadlessIx1RoadSpineDayTickTest"),
    (SPEC_PATH, "first_session_mandate_cost"),
    (IDM_GD, "710417"),
    (MAP_MANAGER_GD, "func build_road_connection"),
    (PROVINCE_GD, "built_road_neighbors"),
    (PROVINCE_GD, "ROAD_SPINE_INFRA_BONUS"),
    (OVERLAY_GD, "explicit"),
    (OVERLAY_GD, "_road_layer_has_explicit_lines"),
    (RENDERER_GD, "BtnBuildRoadSpine"),
    (RENDERER_GD, "_on_build_road_spine_pressed"),
    (RENDERER_GD, "_hide_unit_card_keep_map_focus"),
    (RENDERER_GD, "_dismiss_unit_card_restore_province"),
    (RENDERER_GD, "_map_prefers_province_over_unit"),
    (RENDERER_GD, "chip_disk_only"),
    (SEARCH_GD, "focus_province_by_id"),
    (FORMATTERS_GD, "Road Spine"),
    (FORMATTERS_PY, "Road Spine"),
)


def load_ix1_spec(path: Path = SPEC_PATH) -> Dict[str, Any]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        return {}
    return raw


def corridor_ids(spec: Optional[Mapping[str, Any]] = None) -> Tuple[int, ...]:
    data = spec if spec is not None else load_ix1_spec()
    raw = data.get("corridor_ids") if isinstance(data, Mapping) else None
    if isinstance(raw, list) and raw:
        return tuple(int(x) for x in raw)
    return CORRIDOR_IDS


def spine_edges(spec: Optional[Mapping[str, Any]] = None) -> Tuple[Tuple[int, int], ...]:
    data = spec if spec is not None else load_ix1_spec()
    raw = data.get("edges") if isinstance(data, Mapping) else None
    if isinstance(raw, list) and raw:
        out: List[Tuple[int, int]] = []
        for pair in raw:
            if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                a, b = int(pair[0]), int(pair[1])
                if a != b:
                    out.append((a, b))
        if out:
            return tuple(out)
    return SPINE_EDGES


def hub_id(spec: Optional[Mapping[str, Any]] = None) -> int:
    data = spec if spec is not None else load_ix1_spec()
    if isinstance(data, Mapping) and data.get("hub_id") is not None:
        return int(data["hub_id"])
    return HUB_ID


def off_spine_control_id(spec: Optional[Mapping[str, Any]] = None) -> int:
    data = spec if spec is not None else load_ix1_spec()
    if isinstance(data, Mapping) and data.get("off_spine_control_id") is not None:
        return int(data["off_spine_control_id"])
    return ESSEN_CONTROL_ID


def ix1_road_spine_mandate_cost(spec: Optional[Mapping[str, Any]] = None) -> int:
    """IX-1 first-session starter cost. Generic Invest stays on the Köln 73 curve."""
    data = spec if spec is not None else load_ix1_spec()
    if isinstance(data, Mapping) and data.get("first_session_mandate_cost") is not None:
        return max(0, int(data["first_session_mandate_cost"]))
    return IX1_FIRST_SESSION_MANDATE_COST


def ix1_day0_mandate_gate(
    mandate: int = GER_1936_DAY0_MANDATE,
    spec: Optional[Mapping[str, Any]] = None,
    tag: str = OWNER_TAG,
) -> Dict[str, Any]:
    """Headless-assertable GER 1936 day-0 Mandate gate for the IX-1 order."""
    cost = ix1_road_spine_mandate_cost(spec)
    current = int(mandate)
    return {
        "ok": current >= cost,
        "mandate": current,
        "cost": cost,
        "tag": str(tag or OWNER_TAG).upper(),
        "start": "1936-01-01",
        "generic_koeln_invest_cost": 73,
    }


def _edge_key(a: int, b: int) -> Tuple[int, int]:
    return (a, b) if a < b else (b, a)


def neighbors_for(pid: int, spec: Optional[Mapping[str, Any]] = None) -> List[int]:
    out: List[int] = []
    seen: Set[int] = set()
    for a, b in spine_edges(spec):
        if a == pid and b not in seen:
            seen.add(b)
            out.append(b)
        elif b == pid and a not in seen:
            seen.add(a)
            out.append(a)
    return out


def movement_cost(
    infrastructure: int,
    development_level: int = 1,
    terrain: str = "plains",
    road_neighbor_n: int = 0,
    weather_mult: float = 1.0,
) -> float:
    """Mirrors Province.get_movement_cost (no MapManager river lookup)."""
    terr = str(terrain or "plains").strip().lower()
    terrain_mult = {
        "urban": 0.9,
        "metro": 0.9,
        "hills": 1.35,
        "mountains": 2.15,
        "desert": 1.45,
        "jungle": 1.45,
        "tundra": 1.25,
        "forest": 1.25,
        "marshes": 1.5,
        "swamp": 1.5,
        "coastal": 1.1,
        "snow_capped": 2.8,
    }.get(terr, 1.0)
    infra = float(max(0, min(int(infrastructure), 50)))
    if int(road_neighbor_n) > 0:
        infra += ROAD_INFRA_BONUS + float(road_neighbor_n) * ROAD_NEIGHBOR_BONUS
        if infra > 50.0:
            infra = 50.0
    dev = float(max(0, min(int(development_level), 50)))
    infra_factor = 1.0 / (1.0 + infra * 0.04)
    dev_factor = 1.0 / (1.0 + dev * 0.02)
    return terrain_mult * infra_factor * dev_factor * float(weather_mult)


def empty_board(
    infra: int = 4,
    development_level: int = 2,
    spec: Optional[Mapping[str, Any]] = None,
) -> Dict[int, Dict[str, Any]]:
    board: Dict[int, Dict[str, Any]] = {}
    for pid in set(corridor_ids(spec)) | {off_spine_control_id(spec)}:
        board[int(pid)] = {
            "pid": int(pid),
            "infrastructure": int(infra),
            "development_level": int(development_level),
            "terrain": "plains",
            "built_road_neighbors": [],
            "owner_tag": OWNER_TAG,
        }
    return board


def _ensure_edge(board: Dict[int, Dict[str, Any]], a: int, b: int) -> None:
    pa = board.setdefault(int(a), {"pid": int(a), "built_road_neighbors": [], "infrastructure": 4})
    pb = board.setdefault(int(b), {"pid": int(b), "built_road_neighbors": [], "infrastructure": 4})
    na = [int(x) for x in (pa.get("built_road_neighbors") or [])]
    nb = [int(x) for x in (pb.get("built_road_neighbors") or [])]
    if int(b) not in na:
        na.append(int(b))
    if int(a) not in nb:
        nb.append(int(a))
    pa["built_road_neighbors"] = na
    pb["built_road_neighbors"] = nb


def apply_road_spine_order(
    board: Mapping[int, Mapping[str, Any]],
    province_id: int,
    spec: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Player-order complete: infra +1 on the ordered pid + spine edges."""
    pid = int(province_id)
    allowed = set(corridor_ids(spec))
    if pid not in allowed:
        return {"ok": False, "reason": "not_on_ix1_corridor", "province_id": pid}
    out: Dict[int, Dict[str, Any]] = {}
    for key, row in board.items():
        out[int(key)] = dict(row)
        roads = row.get("built_road_neighbors") or []
        out[int(key)]["built_road_neighbors"] = [int(x) for x in roads]
    if pid not in out:
        return {"ok": False, "reason": "province_missing", "province_id": pid}
    before_cost = movement_cost(
        int(out[pid].get("infrastructure", 1)),
        int(out[pid].get("development_level", 1)),
        str(out[pid].get("terrain", "plains")),
        len(out[pid].get("built_road_neighbors") or []),
    )
    out[pid]["infrastructure"] = int(out[pid].get("infrastructure", 1)) + INFRA_STEP
    linked: List[Tuple[int, int]] = []
    for nid in neighbors_for(pid, spec):
        _ensure_edge(out, pid, nid)
        linked.append(_edge_key(pid, nid))
    after_cost = movement_cost(
        int(out[pid].get("infrastructure", 1)),
        int(out[pid].get("development_level", 1)),
        str(out[pid].get("terrain", "plains")),
        len(out[pid].get("built_road_neighbors") or []),
    )
    ctrl = off_spine_control_id(spec)
    control_cost = movement_cost(
        int(out.get(ctrl, {}).get("infrastructure", out[pid].get("infrastructure", 1) - INFRA_STEP)),
        int(out.get(ctrl, {}).get("development_level", out[pid].get("development_level", 1))),
        str(out.get(ctrl, {}).get("terrain", "plains")),
        len(out.get(ctrl, {}).get("built_road_neighbors") or []),
    )
    return {
        "ok": True,
        "slice": SLICE_NAME,
        "province_id": pid,
        "edges": linked,
        "board": out,
        "move_cost_before": before_cost,
        "move_cost_after": after_cost,
        "control_id": ctrl,
        "control_move_cost": control_cost,
        "cheaper_than_before": after_cost < before_cost,
        "cheaper_than_control": after_cost < control_cost,
    }


def board_has_edge(board: Mapping[int, Mapping[str, Any]], a: int, b: int) -> bool:
    pa = board.get(int(a)) or {}
    pb = board.get(int(b)) or {}
    na = [int(x) for x in (pa.get("built_road_neighbors") or [])]
    nb = [int(x) for x in (pb.get("built_road_neighbors") or [])]
    return int(b) in na and int(a) in nb


def load_accurate_adjacency() -> Dict[int, List[int]]:
    raw = json.loads(ADJ_PATH.read_text(encoding="utf-8"))
    adj = raw.get("adjacency") if isinstance(raw, dict) else {}
    out: Dict[int, List[int]] = {}
    if isinstance(adj, dict):
        for key, nbrs in adj.items():
            if not isinstance(nbrs, list):
                continue
            out[int(key)] = [int(x) for x in nbrs]
    return out


def corridor_is_owned_adjacent(spec: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
    ids = list(corridor_ids(spec))
    adj = load_accurate_adjacency()
    edges = list(spine_edges(spec))
    missing: List[str] = []
    for a, b in edges:
        if b not in (adj.get(a) or []) or a not in (adj.get(b) or []):
            missing.append("%d-%d" % (a, b))
    names: Dict[int, str] = {}
    if BASE_PATH.is_file():
        base = json.loads(BASE_PATH.read_text(encoding="utf-8"))
        rows = base.get("provinces") if isinstance(base, dict) else base
        want = set(ids)
        if isinstance(rows, list):
            for row in rows:
                if not isinstance(row, dict):
                    continue
                pid = int(row.get("id", 0))
                if pid in want:
                    names[pid] = str(row.get("name", ""))
                    cores = [str(x).upper() for x in (row.get("core_for_tags") or [])]
                    cntr = str(row.get("cntr_code", "")).upper()
                    if "GER" not in cores and cntr != "DE":
                        missing.append("owner_%d" % pid)
    return {
        "ok": not missing and len(ids) >= 2 and len(ids) <= 4,
        "ids": ids,
        "edges": edges,
        "names": names,
        "missing": missing,
        "n": len(ids),
    }


def _read(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8")


def shipped_api_integrity() -> Dict[str, Any]:
    missing: List[str] = []
    found: List[str] = []
    for path, needle in SHIPPED_API_NEEDLES:
        text = _read(path)
        label = "%s:%s" % (path.name, needle)
        if needle in text:
            found.append(label)
        else:
            missing.append(label)
    return {
        "ok": not missing,
        "found": found,
        "missing": missing,
    }


def _slice_func(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    nxt = src.find("\nfunc ", i + len(needle))
    if nxt < 0:
        return src[i:]
    return src[i:nxt]


def ix1_day_tick_unblocked() -> Dict[str, Any]:
    """Active spine must not enable the 3520×N AI invest scan or inspector notify loop."""
    idm = _read(IDM_GD)
    ren = _read(RENDERER_GD)
    save = _read(SAVE_LOAD_GD)
    tm = _read(TIME_MANAGER_GD)
    harness = _read(DAY_TICK_HARNESS)
    gates = _read(GATES_SH)
    gate = _slice_func(idm, "_should_run_full_board_ai_invest")
    adv = _slice_func(idm, "advance_daily_projects")
    pick = _slice_func(idm, "_pick_ai_infra_province")
    start = _slice_func(idm, "start_infrastructure_project")
    prog = _slice_func(ren, "_on_infra_progress_for_inspector")
    changed = _slice_func(ren, "_on_map_province_data_changed")
    rings = _slice_func(ren, "_refresh_feature_progress_rings")
    sim = _slice_func(idm, "simulate_ix1_spine_days")
    live_sim = _slice_func(idm, "simulate_live_f5_day_advance")
    live_clock = _slice_func(tm, "advance_live_f5_equivalent_days")
    missing: List[str] = []
    if "is_interactive_light_sim" not in gate:
        missing.append("light_sim_gate")
    if "is_live_f5_play_path" not in gate and "DisplayServer.get_name()" not in gate:
        missing.append("graphical_play_gate")
    if "_should_run_full_board_ai_invest" not in adv:
        missing.append("advance_uses_gate")
    if "get_all_provinces(" in pick or "get_provinces_by_owner(" in pick:
        missing.append("pick_full_board_scan")
    if "AI_INFRA_PICK_CAP" not in pick:
        missing.append("pick_cap")
    if "_should_quiet_ai_infra_start" not in start:
        missing.append("quiet_ai_toast")
    if "notify_province_changed(" in prog:
        missing.append("progress_renotify")
    if "selected_province_id" not in changed or "infrastructure_project" not in changed:
        missing.append("selected_only_inspector")
    if "is_interactive_light_sim" not in rings:
        missing.append("ring_walk_gated")
    if "_deferred_calendar_autosave" not in save:
        missing.append("deferred_autosave")
    if "past_freeze" not in sim or "advance_living_playtest_days" not in sim:
        missing.append("simulate_ix1_spine_days")
    if "advance_live_f5_equivalent_days" not in live_sim or "past_plus2" not in live_sim:
        missing.append("simulate_live_f5_day_advance")
    if "past_plus6" not in live_sim or "calendar_autosave_gathers" not in live_sim:
        missing.append("live_equiv_past_plus6")
    if "_living_playtest_clock = true" in live_clock:
        missing.append("live_equiv_uses_playtest_clock")
    if "_live_f5_equiv_clock = true" not in live_clock:
        missing.append("live_equiv_clock")
    if "past_plus2" not in harness or "simulate_live_f5_day_advance" not in harness:
        missing.append("live_equiv_harness")
    if "past_plus6" not in harness or "calendar_autosave_gathers" not in harness:
        missing.append("live_equiv_plus6_harness")
    save_hook = _slice_func(save, "_on_day_advanced_for_autosave")
    if "is_live_f5_play_path" not in save_hook and "_should_skip_live_f5_calendar_autosave" not in save_hook:
        missing.append("live_f5_autosave_skip")
    if "past_freeze" not in harness or "RESULT=" not in harness:
        missing.append("day_tick_harness")
    if "HeadlessIx1RoadSpineDayTickTest" not in gates:
        missing.append("day_tick_on_gates")
    return {
        "ok": not missing,
        "missing": missing,
    }


def ix1_province_select_under_garrison() -> Dict[str, Any]:
    """Search/Go + Alt/infra empty-terrain must open province inspector under garrison."""
    ren = _read(RENDERER_GD)
    search = _read(SEARCH_GD)
    focus = _slice_func(ren, "focus_province_by_id")
    show = _slice_func(ren, "show_info_panel")
    land = _slice_func(ren, "_try_open_land_unit_at_world")
    chip = _slice_func(ren, "_try_open_land_chip_from_input")
    esc = _slice_func(ren, "_handle_escape_key")
    prefer = _slice_func(ren, "_map_prefers_province_over_unit")
    hide = _slice_func(ren, "_hide_unit_card_keep_map_focus")
    restore = _slice_func(ren, "_dismiss_unit_card_restore_province")
    popup = _slice_func(ren, "_show_unit_detail_popup")
    missing: List[str] = []
    if "focus_province_by_id" not in search:
        missing.append("search_calls_focus")
    if "_hide_unit_card_keep_map_focus" not in focus:
        missing.append("search_hides_garrison")
    if "show_info_panel(province, true)" not in focus:
        missing.append("search_force_inspector")
    if "_camera_is_held" not in focus:
        missing.append("focus_keeps_camera_is_held")
    if "force_open" not in show or "keep_camera" not in show:
        missing.append("show_force_keep_camera")
    if "chip_disk_only" not in land:
        missing.append("chip_disk_only")
    if "_resolve_hex_pick_pid" not in land or "_nearest_player_land_formation_at_world" not in land:
        missing.append("land_fallbacks_kept")
    if land.count("_player_land_formation_at_province") < 2:
        missing.append("land_province_stack_kept")
    if "_map_prefers_province_over_unit" not in chip:
        missing.append("chip_uses_prefer")
    if "show_info_panel" in chip or "show_info_panel" in land:
        missing.append("land_open_no_inspector")
    if "_dismiss_unit_card_restore_province" not in esc:
        missing.append("esc_restores_province")
    if "KEY_ALT" not in prefer or '"infra"' not in prefer:
        missing.append("prefer_alt_or_infra")
    if "event.alt_pressed" not in _slice_func(ren, "_input"):
        missing.append("alt_skips_land_chip")
    if "chip_disk_only" not in hide and "UnitDetailPopup" not in hide:
        missing.append("hide_unit_card")
    if "show_info_panel(p, true, true)" not in restore:
        missing.append("restore_keep_camera")
    if "_dismiss_unit_card_restore_province" not in popup:
        missing.append("garrison_close_restores")
    if "710417" not in _read(SPEC_PATH) or "710416" not in _read(SPEC_PATH):
        missing.append("corridor_ids")
    return {
        "ok": not missing,
        "missing": missing,
        "hub_id": HUB_ID,
        "corridor_ids": list(CORRIDOR_IDS),
    }


def build_ix1_road_spine_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    spec = load_ix1_spec()
    ids = corridor_ids(spec)
    if spec.get("slice") == SLICE_NAME and 2 <= len(ids) <= 4:
        passes.append("spec_named_ix1")
    else:
        fails.append("spec_named_ix1")
    if int(spec.get("hub_id", 0)) == HUB_ID and int(spec.get("off_spine_control_id", 0)) == ESSEN_CONTROL_ID:
        passes.append("rhineland_ids")
    else:
        fails.append("rhineland_ids")

    adj = corridor_is_owned_adjacent(spec)
    if adj.get("ok"):
        passes.append("owned_adjacent_corridor")
    else:
        fails.append("owned_adjacent_corridor")

    board = empty_board(infra=4, development_level=2, spec=spec)
    applied = apply_road_spine_order(board, hub_id(spec), spec)
    if applied.get("ok") and applied.get("cheaper_than_before"):
        passes.append("move_cost_strictly_less")
    else:
        fails.append("move_cost_strictly_less")
    if applied.get("cheaper_than_control"):
        passes.append("cheaper_than_off_spine_control")
    else:
        fails.append("cheaper_than_off_spine_control")
    post = applied.get("board") or {}
    edges_ok = True
    for a, b in spine_edges(spec):
        if not board_has_edge(post, a, b):
            edges_ok = False
    if edges_ok and applied.get("ok"):
        passes.append("edges_present")
    else:
        fails.append("edges_present")

    # Control Essen must not gain a road from the Köln order.
    if not board_has_edge(post, hub_id(spec), off_spine_control_id(spec)):
        passes.append("no_continent_mesh")
    else:
        fails.append("no_continent_mesh")

    api = shipped_api_integrity()
    if api.get("ok"):
        passes.append("shipped_apis")
    else:
        fails.append("shipped_apis")

    gate = ix1_day0_mandate_gate(GER_1936_DAY0_MANDATE, spec)
    if gate.get("ok") and int(gate.get("cost", -1)) == IX1_FIRST_SESSION_MANDATE_COST:
        passes.append("day0_mandate_gate")
    else:
        fails.append("day0_mandate_gate")

    day_tick = ix1_day_tick_unblocked()
    if day_tick.get("ok"):
        passes.append("day_tick_unblocked")
    else:
        fails.append("day_tick_unblocked")

    select_gate = ix1_province_select_under_garrison()
    if select_gate.get("ok"):
        passes.append("province_select_under_garrison")
    else:
        fails.append("province_select_under_garrison")

    return {
        "ok": not fails,
        "slice": SLICE_NAME,
        "theater": "rhineland_west_german",
        "corridor_ids": list(ids),
        "edges": [list(e) for e in spine_edges(spec)],
        "hub_id": hub_id(spec),
        "off_spine_control_id": off_spine_control_id(spec),
        "move_cost_before": applied.get("move_cost_before"),
        "move_cost_after": applied.get("move_cost_after"),
        "control_move_cost": applied.get("control_move_cost"),
        "passes": passes,
        "fails": fails,
        "adjacency": adj,
        "shipped": api,
        "day0_mandate_gate": gate,
        "day_tick_unblocked": day_tick,
        "province_select_under_garrison": select_gate,
        "parked": [
            "Dig2 pan",
            "old G polyline dig",
            "Maginot combat",
            "rail vertical",
            "industry vertical",
            "Hampshire",
            "continent mesh",
            "Tyrrhenian/Ligurian/Flanders/SE England/pale-map/Fill%·TOE",
        ],
    }
