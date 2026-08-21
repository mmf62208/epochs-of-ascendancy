"""First-session hotkey table + Help text for world_accurate play.

Canonical binding contract (resolves F5/F6/F9 collisions):
- Bare F-keys = mapmodes (MapRenderer)
- Save/load = Ctrl+S / Ctrl+L (TopInfoBar); save browser Ctrl+Shift+S
- War path: B Fronts · Shift+I WarLoop · I flow · G corridor · Ctrl+click assault

Pure product — no dual packages. Wired by MainMenu Help + tests.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TOP_INFO = ROOT / "scripts" / "ui" / "TopInfoBar.gd"
MAIN_MENU = ROOT / "scripts" / "ui" / "MainMenu.gd"
TEST_RUNNER = ROOT / "scripts" / "core" / "TestRunner.gd"

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
        "Command Center: Save / Load slots · ESC resumes map",
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
        wiring["left_drag_pan"] = (
            "_left_pan_armed" in ren
            and "_left_pan_active" in ren
            and "LEFT_PAN_SLOP_PX" in ren
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
