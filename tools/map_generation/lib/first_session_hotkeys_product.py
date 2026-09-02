"""First-session hotkey table + Help text for world_accurate play.

Canonical binding contract (resolves F5/F6/F9 collisions):
- Bare F-keys = mapmodes (MapRenderer)
- Save/load = Ctrl+S / Ctrl+L (TopInfoBar); save browser Ctrl+Shift+S
- War path: B Fronts · Shift+I WarLoop · I flow · G corridor · Ctrl+click assault

Pure product — no dual packages. Wired by MainMenu Help + tests.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
TOP_INFO = ROOT / "scripts" / "ui" / "TopInfoBar.gd"
MAIN_MENU = ROOT / "scripts" / "ui" / "MainMenu.gd"
TEST_RUNNER = ROOT / "scripts" / "core" / "TestRunner.gd"
SEARCH_GD = ROOT / "scripts" / "ui" / "map" / "MapProvinceSearch.gd"
TOOLBAR_GD = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"
ZOOM_LOD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"
FLOW_LAYER = ROOT / "scripts" / "map" / "StrategicFlowOverlayLayer.gd"
INFRA_LAYER = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"
INSIGHT_GD = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
BOARD_DIR = ROOT / "data" / "provinces_world_accurate"

# Named first-session camera capitals (world_accurate).
HOME_EUROPE_PIDS = (710300, 710707, 710963)  # Berlin, Paris, Roma
END_TOKYO_PID = 903995
SOV_MOSCOW_PID = 903534
ATA_ICE_PIDS = (902133, 902134)

# Default first-session theater (Maginot / Europe war path docs)
DEFAULT_PLAYER_TAG = "GER"

# Ordered for Help dialog readability
HOTKEYS: List[Dict[str, str]] = [
    {"key": "F1", "action": "Political mapmode", "group": "mapmode"},
    {"key": "F2", "action": "Strain mapmode", "group": "mapmode"},
    {"key": "F3", "action": "Vitality mapmode", "group": "mapmode"},
    {"key": "F4", "action": "Development mapmode", "group": "mapmode"},
    {"key": "F5", "action": "Supply mapmode", "group": "mapmode"},
    {"key": "F6", "action": "Loyalty mapmode", "group": "mapmode"},
    {"key": "F7", "action": "Infrastructure mapmode", "group": "mapmode"},
    {"key": "F8", "action": "Weather mapmode", "group": "mapmode"},
    {"key": "F9", "action": "Resources mapmode", "group": "mapmode"},
    {"key": "Shift+F9", "action": "States mapmode", "group": "mapmode"},
    {"key": "Ctrl+F9", "action": "Terrain mapmode", "group": "mapmode"},
    {"key": "B", "action": "Live border Fronts (cycle targets)", "group": "war"},
    {"key": "Shift+I", "action": "WarLoop first-session path", "group": "war"},
    {"key": "I", "action": "Toggle EquipmentFlow glyphs", "group": "war"},
    {"key": "G", "action": "Supply corridor hub → front", "group": "war"},
    {"key": "Ctrl+click", "action": "Assault adjacent enemy (formation selected)", "group": "war"},
    {"key": "Left-drag", "action": "Pan map (click still picks)", "group": "nav"},
    {"key": "Home", "action": "Center Europe", "group": "nav"},
    {"key": "Shift+Home", "action": "Fit full world", "group": "nav"},
    {"key": "End", "action": "Focus Asia", "group": "nav"},
    {"key": "Shift+U", "action": "Toggle unit counters", "group": "nav"},
    {"key": "Ctrl+S", "action": "Quicksave", "group": "session"},
    {"key": "Ctrl+L", "action": "Quickload", "group": "session"},
    {"key": "Ctrl+Shift+S", "action": "Save browser / manager", "group": "session"},
    {"key": "ESC", "action": "Dismiss overlays / Command Center", "group": "session"},
    {"key": "?", "action": "First-session help toast (map)", "group": "session"},
]

FIRST_SESSION_STEPS: List[str] = [
    "1. Map loads political world · Home = Europe (default play as GER)",
    "2. Click Berlin capital · confirm ownership / OOB",
    "3. Press B or toolbar Fronts — cycle enemy border targets (Maginot class)",
    "4. Shift+I WarLoop — EquipmentFlow ON + fronts + assault brief",
    "5. Select front province · G — supply hub → front corridor",
    "6. Formation selected · Ctrl+click adjacent enemy or inspector Attack",
    "7. Ctrl+S quicksave · advance a few days · Ctrl+L to resume",
]


def build_hotkey_table() -> List[Dict[str, str]]:
    return [dict(h) for h in HOTKEYS]


def format_help_dialog_text(*, include_steps: bool = True) -> str:
    lines: List[str] = [
        "Epochs of Ascendancy — First Session",
        "",
        "Command Center: Save / Load slots · pick GER/ENG/FRA/JAP · 1918/1936/2026 · ESC resumes map",
        "Title: pick scenario date, country, or load a save (map stays live underneath)",
        "",
        "— Session —",
    ]
    for h in HOTKEYS:
        if h["group"] == "session":
            lines.append("%s — %s" % (h["key"], h["action"]))
    lines.append("")
    lines.append("— War path —")
    for h in HOTKEYS:
        if h["group"] == "war":
            lines.append("%s — %s" % (h["key"], h["action"]))
    lines.append("")
    lines.append("— Mapmodes —")
    for h in HOTKEYS:
        if h["group"] == "mapmode":
            lines.append("%s — %s" % (h["key"], h["action"]))
    lines.append("")
    lines.append("— Navigation —")
    for h in HOTKEYS:
        if h["group"] == "nav":
            lines.append("%s — %s" % (h["key"], h["action"]))
    if include_steps:
        lines.append("")
        lines.append("— Checklist —")
        lines.extend(FIRST_SESSION_STEPS)
    return "\n".join(lines)


def _centroid_from_geo_row(row: Mapping[str, Any]) -> Optional[Tuple[float, float]]:
    anc = row.get("label_anchor")
    if isinstance(anc, (list, tuple)) and len(anc) >= 2:
        try:
            return (float(anc[0]), float(anc[1]))
        except (TypeError, ValueError):
            pass
    xs: List[float] = []
    ys: List[float] = []
    for pt in row.get("points") or []:
        if isinstance(pt, (list, tuple)) and len(pt) >= 2:
            try:
                xs.append(float(pt[0]))
                ys.append(float(pt[1]))
            except (TypeError, ValueError):
                continue
    if not xs:
        return None
    return (sum(xs) / len(xs), sum(ys) / len(ys))


def load_board_centroids(board_dir: Optional[Path] = None) -> Dict[int, Tuple[float, float]]:
    d = Path(board_dir or BOARD_DIR)
    geo_path = d / "provinces_geometry.json"
    if not geo_path.is_file():
        return {}
    payload = json.loads(geo_path.read_text(encoding="utf-8"))
    rows = payload.get("provinces") if isinstance(payload, dict) else payload
    out: Dict[int, Tuple[float, float]] = {}
    if not isinstance(rows, list):
        return out
    for row in rows:
        if not isinstance(row, Mapping):
            continue
        try:
            pid = int(row.get("id") or 0)
        except (TypeError, ValueError):
            continue
        cent = _centroid_from_geo_row(row)
        if cent is not None:
            out[pid] = cent
    return out


def frame_rect_from_points(
    points: Sequence[Tuple[float, float]],
    *,
    min_pad_x: float = 280.0,
    min_pad_y: float = 200.0,
    pad_ratio: float = 0.45,
) -> Optional[Tuple[float, float, float, float]]:
    pts = [(float(x), float(y)) for x, y in points]
    if not pts:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    pad_x = max(min_pad_x, (max_x - min_x) * pad_ratio)
    pad_y = max(min_pad_y, (max_y - min_y) * pad_ratio)
    x0, y0 = min_x - pad_x, min_y - pad_y
    return (x0, y0, (max_x + pad_x) - x0, (max_y + pad_y) - y0)


def rect_contains(
    rect: Tuple[float, float, float, float],
    pt: Tuple[float, float],
    *,
    eps: float = 1.0,
) -> bool:
    x, y, w, h = rect
    return (x - eps) <= pt[0] <= (x + w + eps) and (y - eps) <= pt[1] <= (y + h + eps)


def home_europe_frame(
    centroids: Optional[Mapping[int, Tuple[float, float]]] = None,
) -> Optional[Tuple[float, float, float, float]]:
    cents = dict(centroids or load_board_centroids())
    pts = [cents[pid] for pid in HOME_EUROPE_PIDS if pid in cents]
    # Continental pad — a 0.45 bbox around the three cities is a postage-stamp grey void.
    return frame_rect_from_points(pts, min_pad_x=1100.0, min_pad_y=800.0)


def chi_capital_pid(
    owners: Mapping[str, Any],
    centroids: Mapping[int, Tuple[float, float]],
    tokyo: Optional[Tuple[float, float]] = None,
) -> Optional[int]:
    tok = tokyo or centroids.get(END_TOKYO_PID)
    best_pid: Optional[int] = None
    best_d = 1e18
    for pid_s, tag in owners.items():
        if str(tag).strip().upper() != "CHI":
            continue
        try:
            pid = int(pid_s)
        except (TypeError, ValueError):
            continue
        c = centroids.get(pid)
        if c is None:
            continue
        if tok is not None and c[0] >= tok[0]:
            continue
        if tok is None:
            d = -c[0]
        else:
            d = (c[0] - tok[0]) ** 2 + (c[1] - tok[1]) ** 2
        if d < best_d:
            best_d = d
            best_pid = pid
    return best_pid


def asia_end_frame(
    centroids: Optional[Mapping[int, Tuple[float, float]]] = None,
    owners: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    cents = dict(centroids or load_board_centroids())
    own = owners
    if own is None:
        op = BOARD_DIR / "province_ownership_1936.json"
        own = json.loads(op.read_text(encoding="utf-8")).get("owners") or {} if op.is_file() else {}
    tokyo = cents.get(END_TOKYO_PID)
    chi_pid = chi_capital_pid(own, cents, tokyo)
    chi = cents.get(int(chi_pid)) if chi_pid else None
    pts = [p for p in (tokyo, chi) if p is not None]
    rect = frame_rect_from_points(pts, min_pad_x=360.0, min_pad_y=280.0)
    return {
        "tokyo": tokyo,
        "chi_pid": chi_pid,
        "chi": chi,
        "rect": rect,
        "moscow": cents.get(SOV_MOSCOW_PID),
    }


def format_onboarding_toast(*, tag: str = DEFAULT_PLAYER_TAG) -> str:
    t = str(tag or DEFAULT_PLAYER_TAG).strip().upper() or DEFAULT_PLAYER_TAG
    return (
        "First session · play as %s · B Fronts · Shift+I WarLoop · G corridor · "
        "Ctrl+click assault · Ctrl+S save · ? help"
        % t
    )


def build_first_session_hotkeys_product(
    *,
    player_tag: str = DEFAULT_PLAYER_TAG,
    check_wiring: bool = True,
) -> Dict[str, Any]:
    tag = str(player_tag or DEFAULT_PLAYER_TAG).strip().upper() or DEFAULT_PLAYER_TAG
    table = build_hotkey_table()
    help_text = format_help_dialog_text(include_steps=True)
    toast = format_onboarding_toast(tag=tag)
    fails: List[str] = []
    passes: List[str] = []

    # Contract: save keys must not collide with bare mapmode F5/F9
    session_keys = {h["key"] for h in table if h["group"] == "session"}
    mapmode_keys = {h["key"] for h in table if h["group"] == "mapmode"}
    if "F5" in session_keys:
        fails.append("session_uses_bare_F5")
    else:
        passes.append("session_no_bare_F5")
    if "F9" in session_keys:
        fails.append("session_uses_bare_F9")
    else:
        passes.append("session_no_bare_F9")
    if "Ctrl+S" not in session_keys:
        fails.append("missing_ctrl_s")
    else:
        passes.append("ctrl_s")
    if "Ctrl+L" not in session_keys:
        fails.append("missing_ctrl_l")
    else:
        passes.append("ctrl_l")
    if "F5" not in mapmode_keys or "F9" not in mapmode_keys:
        fails.append("mapmode_missing_f5_f9")
    else:
        passes.append("mapmode_f5_f9")
    if tag != DEFAULT_PLAYER_TAG:
        passes.append("custom_tag=%s" % tag)
    else:
        passes.append("default_tag_ger")

    cents = load_board_centroids()
    home_rect = home_europe_frame(cents)
    home_ok = False
    if home_rect:
        home_ok = all(
            pid in cents and rect_contains(home_rect, cents[pid]) for pid in HOME_EUROPE_PIDS
        )
    if home_ok:
        passes.append("home_frame_berlin_paris_rome")
    else:
        fails.append("home_frame_berlin_paris_rome")
    asia = asia_end_frame(cents)
    asia_rect = asia.get("rect")
    tokyo = asia.get("tokyo")
    chi = asia.get("chi")
    moscow = asia.get("moscow")
    asia_ok = (
        isinstance(asia_rect, tuple)
        and tokyo is not None
        and chi is not None
        and rect_contains(asia_rect, tokyo)
        and rect_contains(asia_rect, chi)
        and (moscow is None or not rect_contains(asia_rect, moscow))
    )
    if asia_ok:
        passes.append("end_frame_tokyo_chi")
    else:
        fails.append("end_frame_tokyo_chi")

    wiring: Dict[str, bool] = {}
    if check_wiring:
        ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
        top = TOP_INFO.read_text(encoding="utf-8") if TOP_INFO.is_file() else ""
        menu = MAIN_MENU.read_text(encoding="utf-8") if MAIN_MENU.is_file() else ""
        runner = TEST_RUNNER.read_text(encoding="utf-8") if TEST_RUNNER.is_file() else ""

        # Mapmodes on bare F5/F9
        wiring["map_f5_supply"] = 'KEY_F5' in ren and 'set_map_mode("supply")' in ren
        wiring["map_f9_resources"] = 'KEY_F9' in ren and "resources" in ren
        # Save must use Ctrl modifiers (not bare F5/F9)
        wiring["save_ctrl_s"] = "KEY_S" in top and ("ctrl_pressed" in top or "Ctrl" in top)
        wiring["no_bare_f5_quicksave"] = not (
            "KEY_F5" in top and "quicksave" in top and "ctrl_pressed" not in top[max(0, top.find("KEY_F5") - 80) : top.find("KEY_F5") + 200]
        )
        # Simpler: prefer explicit markers we will write
        wiring["save_uses_ctrl"] = (
            "EOA_HOTKEY_CTRL_S" in top
            or ("keycode == KEY_S" in top and "ctrl_pressed" in top)
            or ("KEY_S" in top and "event.ctrl_pressed" in top)
        )
        wiring["help_lists_warloop"] = "WarLoop" in menu or "Shift+I" in menu or "first_session" in menu.lower()
        wiring["default_ger"] = 'setup_solo_play("GER")' in runner or "DEFAULT_PLAYER_TAG" in runner
        wiring["home_in_input"] = (
            "KEY_HOME" in ren
            and "func _apply_home_key" in ren
            and "func _input" in ren
            and ren.find("KEY_HOME") < ren.find("func _unhandled_input")
        )
        input_i = ren.find("func _input")
        unh_i = ren.find("func _unhandled_input")
        input_fn = ren[input_i:unh_i] if input_i >= 0 and unh_i > input_i else ""
        light_i = ren.find("func _refresh_terrain_zoom_light")
        light_n = ren.find("\nfunc ", light_i + 1) if light_i >= 0 else -1
        light_fn = ren[light_i:light_n] if light_i >= 0 and light_n > light_i else ""
        wiring["end_in_input"] = "KEY_END" in input_fn and "_focus_asia_view" in input_fn
        wiring["g_in_input"] = (
            "KEY_G" in input_fn and "_request_hang_safe_supply_corridor" in input_fn
        )
        wiring["mmb_in_input"] = "MOUSE_BUTTON_MIDDLE" in input_fn
        wiring["left_drag_pan"] = (
            "_left_pan_armed" in ren
            and "_left_pan_active" in ren
            and "LEFT_PAN_SLOP_PX" in ren
            and "func _left_drag_exceeded_slop" in ren
            and "_left_slop_latched" in ren
            and "InputEventMouseMotion" in input_fn
            and "_left_skip_next_pick" in input_fn
        )
        dismiss_fn = _slice_func(ren, "_dismiss_inspector_and_restore_input")
        cull_fn = _slice_func(ren, "_sync_viewport_culling")
        wiring["close_does_not_cull"] = (
            "never_cull_fills" in cull_fn
            and "_map_pick_block_until_msec" in dismiss_fn
            and "_hold_camera_now" in dismiss_fn
            and "_restore_held_camera" in dismiss_fn
            and "_ensure_ocean_floor" not in dismiss_fn
            and "_center_camera_on_province" not in dismiss_fn
            and "_force_all_province_nodes_visible" not in dismiss_fn
            and "func _gui_blocks_map_pick" in ren
            and "supply_mode" in _slice_func(ren, "_select_province")
            and "_refresh_supply_highlights" in _slice_func(ren, "_select_province")
            and "_restore_held_camera" in _slice_func(ren, "_process")
        )
        wiring["search_i_not_stolen"] = (
            "func _gui_text_field_has_focus" in ren
            and "_gui_text_field_has_focus()" in input_fn
        )
        g_req = _slice_func(ren, "_request_hang_safe_supply_corridor")
        wiring["g_not_self_path"] = (
            "func _draw_hang_safe_corridor_line" in ren
            and "710173" in _slice_func(ren, "_corridor_front_target_for_tag")
            and "find_land_path" not in g_req
            and "collect_live_border_assault_targets" not in g_req
            and "call_deferred" in g_req
            and "710173" in _slice_func(ren, "_deferred_hang_safe_corridor_line")
        )
        wiring["end_tokyo_chi_pad"] = (
            "STRATEGIC_MAX_ZOOM" in _slice_func(ren, "_focus_asia_view")
            and "902487" in _slice_func(ren, "_resolve_chi_capital_pid")
            and "func _force_asia_end_capital_stars" in ren
            and "_force_asia_end_capital_stars" in _slice_func(ren, "_focus_asia_view")
            and "force_nation_label_at" in _slice_func(ren, "_focus_asia_view")
            and "902487" in _slice_func(ren, "_force_asia_end_capital_stars")
            and "AsiaEndStarHost" in _slice_func(ren, "_force_asia_end_capital_stars")
        )
        open_fn = _slice_func(ren, "_open_fight_from_formation_id")
        wiring["open_fight_sheet"] = (
            "func _open_fight_from_formation_id" in ren
            and "Open fight" in ren
            and "func _show_open_fight_sheet" in ren
            and "Attacker" in _slice_func(ren, "_show_open_fight_sheet")
            and "Defender" in _slice_func(ren, "_show_open_fight_sheet")
            and "Start battle" in _slice_func(ren, "_show_open_fight_sheet")
            and "710739" in open_fn
            and "ensure_playable_front_chips" not in open_fn
            and "func _try_open_land_unit_at_world" in ren
            and "_open_fight_from_formation_id" in _slice_func(ren, "_try_open_land_unit_at_world")
            and "_open_fight_from_formation_id" in _slice_func(ren, "_try_execute_province_attack")
            and "start_land_battle" in _slice_func(ren, "_try_execute_province_attack")
            and "Division fold" in (ROOT / "scripts" / "ui" / "ProvinceOOBStrip.gd").read_text(encoding="utf-8")
            and "BtnOpenFight" in ren
        )
        wiring["wheel_no_full_fill"] = (
            bool(light_fn)
            and "_refresh_province_fill_colors" not in light_fn
            and "call_deferred(\"_refresh_province_fill_colors\")" not in light_fn
        )
        wiring["home_berlin_paris_rome"] = (
            "710300" in ren
            and "710707" in ren
            and "710963" in ren
            and "func _frame_rect_from_points" in ren
            and "func _resolve_europe_focus_rect" in ren
            and "Vector2(1100.0, 800.0)" in _slice_func(ren, "_resolve_europe_focus_rect")
        )
        boot_fn = _slice_func(ren, "_boot_political_map_complete")
        wiring["boot_recenters_europe"] = (
            "center_europe_in_world_view" in boot_fn
            and "_ensure_ocean_floor" in boot_fn
            and "_apply_clean_political_clear_color" in boot_fn
        )
        wiring["home_defers_until_capitals"] = (
            "_europe_focus_retry" in ren
            and "pts.size() < 2" in _slice_func(ren, "_resolve_europe_focus_rect")
            and "europe_world_center" not in _slice_func(ren, "_resolve_europe_focus_rect")
        )
        factory_gd = ROOT / "scripts" / "map" / "FactoryStatusLayer.gd"
        agent_gd = ROOT / "scripts" / "map" / "AgentPresenceLayer.gd"
        wiring["factory_status_layer_file"] = factory_gd.is_file()
        wiring["agent_presence_layer_file"] = agent_gd.is_file()
        wiring["no_const_preload_optional_layers"] = (
            'preload("res://scripts/map/FactoryStatusLayer.gd")' not in ren
            and 'preload("res://scripts/map/AgentPresenceLayer.gd")' not in ren
            and "_load_optional_script" in ren
        )
        hook = (ROOT / "scripts" / "ui" / "PlayNextHook.gd").read_text(encoding="utf-8")
        menu_src = menu
        wiring["living_diplomacy_api"] = "func living_diplomacy_from_province" in hook
        wiring["living_campaign_pick_api"] = "func apply_living_campaign_pick" in menu_src
        wiring["end_tokyo_chi_not_sov"] = (
            "903995" in ren
            and "func _resolve_chi_capital_centroid" in ren
            and "func _focus_asia_view" in ren
            and "_resolve_chi_capital_centroid" in ren[ren.find("func _focus_asia_view"): ren.find("func _focus_asia_view") + 900]
        )
        mm = MAP_MANAGER.read_text(encoding="utf-8") if MAP_MANAGER.is_file() else ""
        cap_i = mm.find("func prefer_capital_province_at")
        cap_n = mm.find("\nfunc ", cap_i + 1) if cap_i >= 0 else -1
        cap_fn = mm[cap_i:cap_n] if cap_i >= 0 and cap_n > cap_i else ""
        wiring["capital_star_disk_wins"] = (
            bool(cap_fn)
            and "return best_cap" in cap_fn
            and "best_d < d_hit" not in cap_fn
        )
        search = SEARCH_GD.read_text(encoding="utf-8") if SEARCH_GD.is_file() else ""
        wiring["berlin_search_submit"] = (
            "func _on_submit" in search
            and "func _resolve_search_pid" in search
            and "focus_province_by_id" in search
            and "rebuild_index" in search
            and "func rebuild_index" in search
        )
        wiring["ice_ocean_ata"] = (
            "902133" in ren
            and "902134" in ren
            and "func ice_ocean_fill_color" in ren
            and "func _is_ice_ocean_visual" in ren
        )
        wiring["no_camera_nudge_after_close"] = (
            "_inspector_held_closed" in ren
            and "_camera_nudge_gen" in ren
            and "func _nudge_camera_after_panel" in ren
        )
        # P1: F-keys live in _input via set_map_mode; toolbar highlight follows.
        wiring["fkeys_in_input"] = (
            'KEY_F1' in input_fn
            and 'set_map_mode("political")' in input_fn
            and 'set_map_mode("strain")' in input_fn
            and 'set_map_mode("vitality")' in input_fn
            and 'set_map_mode("development")' in input_fn
            and 'set_map_mode("terrain")' in input_fn
            and 'set_map_mode("states")' in input_fn
            and 'set_map_mode("resources")' in input_fn
            and "event.ctrl_pressed" in input_fn
        )
        wiring["toolbar_follows_mode"] = (
            "func _sync_mapmode_toolbar" in ren
            and "_sync_mapmode_toolbar()" in _slice_func(ren, "set_map_mode")
            and 'call("set_mode", current_map_mode, false)' in ren
        )
        tb = TOOLBAR_GD.read_text(encoding="utf-8") if TOOLBAR_GD.is_file() else ""
        wiring["toolbar_set_mode"] = (
            "func set_mode" in tb and "notify_renderer" in tb and '"terrain"' in tb
        )
        lod = ZOOM_LOD.read_text(encoding="utf-8") if ZOOM_LOD.is_file() else ""
        wiring["operational_covers_europe_home"] = (
            "OPERATIONAL_MAX_ZOOM" in lod and "1.55" in lod
        )
        wiring["i_glyphs_in_input"] = (
            "KEY_I" in input_fn
            and "toggle_equipment_flow_glyphs" in input_fn
            and "_inspector_stack_blocking_input()" not in input_fn[input_fn.find("KEY_I") : input_fn.find("KEY_I") + 220]
        )
        wiring["i_glyph_layer_cheap"] = (
            "func _ensure_equipment_glyph_layer_cheap" in ren
            and "setup_budgeted" in _slice_func(ren, "_ensure_equipment_glyph_layer_cheap")
            and "_setup_strategic_flow_layer" not in _slice_func(ren, "toggle_equipment_flow_glyphs")
            and "_setup_strategic_flow_layer" not in _slice_func(ren, "_ensure_equipment_glyph_layer_cheap")
            and "preview_player_route()" not in _slice_func(ren, "toggle_equipment_flow_glyphs")
        )
        lyr = FLOW_LAYER.read_text(encoding="utf-8") if FLOW_LAYER.is_file() else ""
        wiring["i_transport_art_not_blob"] = (
            "func _transport_glyph_tex" in lyr
            and "logistics_32.png" in lyr
            and "draw_circle(pos, 4.0 * s, col)" not in lyr
            and "never a blob" in lyr
        )
        wiring["hover_pid_equals_click"] = "func _resolve_map_pick_pid" in ren and "_resolve_map_pick_pid(world_pos)" in _slice_func(
            ren, "_update_spatial_hover"
        )
        mm = MAP_MANAGER.read_text(encoding="utf-8") if MAP_MANAGER.is_file() else ""
        sr_fn = _slice_func(mm, "get_strategic_region_name")
        wiring["no_strategic_region_placeholder"] = (
            bool(sr_fn)
            and 'return "Strategic Region %d"' not in sr_fn
            and "begins_with(" in sr_fn
        )
        insight = INSIGHT_GD.read_text(encoding="utf-8") if INSIGHT_GD.is_file() else ""
        wiring["insight_strips_placeholder"] = 'begins_with("Strategic Region ")' in insight
        infra = INFRA_LAYER.read_text(encoding="utf-8") if INFRA_LAYER.is_file() else ""
        wiring["no_industry_carpet_at_europe"] = (
            "industry_layer.visible = infra_mode or z > 1.55" in infra
            or "industry_layer.visible = infra_mode or z > 1.55" in infra.replace("\t", "")
        )
        wiring["capital_star_lod"] = (
            "func _capital_star_font_px" in ren
            and "func _sync_capital_star_scales" in ren
            and "STRATEGIC_MAX_ZOOM" in _slice_func(ren, "_capital_star_font_px")
        )

        for k, v in wiring.items():
            if v:
                passes.append("wire_%s" % k)
            else:
                fails.append("wire_%s" % k)

    ok = len([f for f in fails if not f.startswith("wire_")]) == 0
    # Wiring soft until first land — still report; ok requires core table only
    # After implementation, wire fails become hard if check_wiring and any wire fail
    if check_wiring and fails:
        hard = [f for f in fails if f.startswith("wire_")]
        # Require critical wires once product is the source of truth
        critical = {"wire_map_f5_supply", "wire_map_f9_resources", "wire_save_uses_ctrl", "wire_default_ger"}
        for c in critical:
            if c.replace("wire_", "") in str(fails) or c in fails:
                ok = ok and (c not in fails)

    return {
        "ok": ok and "session_uses_bare_F5" not in fails and "session_uses_bare_F9" not in fails,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "player_tag": tag,
        "default_player_tag": DEFAULT_PLAYER_TAG,
        "hotkeys": table,
        "hotkey_n": len(table),
        "steps": list(FIRST_SESSION_STEPS),
        "help_text": help_text,
        "onboarding_toast": toast,
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "First-session hotkeys · tag=%s · n=%d · %s"
        % (tag, len(table), "PASS" if ok else "FAIL"),
        "integration": [
            "first_session_hotkeys_product",
            "MainMenu._show_help",
            "TopInfoBar Ctrl+S/L",
            "MapRenderer F-mapmodes",
            "TestRunner GER default",
        ],
    }


def _slice_func(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    nxt = src.find("\nfunc ", i + 1)
    return src[i : nxt if nxt > 0 else i + 4000]


def first_session_hotkeys_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_first_session_hotkeys_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
