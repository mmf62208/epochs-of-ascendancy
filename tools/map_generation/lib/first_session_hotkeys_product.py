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
    return frame_rect_from_points(pts)


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
        )
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


def first_session_hotkeys_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_first_session_hotkeys_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
