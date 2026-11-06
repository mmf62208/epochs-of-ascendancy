"""FIRST20-P2 F7 — mapmode F-key toggle + strip overflow (pure).

Ink §F7: F2 (and peer F-keys) toggle back to the prior mode. Strain
sub-bar uses Intensity + Low/Med/High/Max. Preset/secondary rows are
HFlowContainers clamped to viewport−48; chips past two rows go into
More ▾. Active mode chip is CYAN fill + BG_DEEP text.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"

HOTKEY_MODES: Dict[str, str] = {
    "F1": "political",
    "F2": "strain",
    "F3": "vitality",
    "F4": "development",
    "F5": "supply",
    "F6": "loyalty",
    "F7": "infra",
    "F8": "weather",
    "F9": "resources",
    "Shift+F9": "states",
    "Ctrl+F9": "terrain",
}

INTENSITY_LABELS: Tuple[str, str, str, str] = ("Low", "Med", "High", "Max")
STRIP_VIEWPORT_INSET = 48
STRIP_RIGHT_EDGE_INSET = 8
STRIP_MAX_ROWS = 2


def toggle_map_mode(
    current: str,
    hotkey_mode: str,
    prior: str = "political",
) -> Tuple[str, str]:
    """Return (new_mode, new_prior) for one F-key press."""
    cur = str(current or "political").strip().lower() or "political"
    mode = str(hotkey_mode or "political").strip().lower() or "political"
    prev = str(prior or "political").strip().lower() or "political"
    if cur == mode:
        if mode == "political":
            return cur, prev
        back = prev if prev and prev != mode else "political"
        return back, prev
    return mode, cur


def toolbar_flow_max_width(viewport_w: float) -> float:
    return max(200.0, float(viewport_w) - float(STRIP_VIEWPORT_INSET))


def chips_fit_in_rows(
    chip_widths: List[float],
    max_width: float,
    max_rows: int = STRIP_MAX_ROWS,
    sep: float = 4.0,
) -> Tuple[int, int]:
    """Return (kept, overflow) counts for a 2-row HFlow pack."""
    rows = 1
    used = 0.0
    kept = 0
    for w in chip_widths:
        need = float(w) + (sep if used > 0.0 else 0.0)
        if used > 0.0 and used + need > float(max_width):
            rows += 1
            used = 0.0
            need = float(w)
        if rows > int(max_rows):
            break
        used += need
        kept += 1
    return kept, max(0, len(chip_widths) - kept)


def _gd_func_slice(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
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


def build_first20_p2_mapmode_toggle_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    a, prior = toggle_map_mode("political", "strain")
    if a == "strain" and prior == "political":
        passes.append("f2_enters_strain")
    else:
        fails.append("f2_enters_strain")
    b, _p = toggle_map_mode("strain", "strain", "political")
    if b == "political":
        passes.append("f2_returns_political")
    else:
        fails.append("f2_returns_political")
    c, prior2 = toggle_map_mode("strain", "vitality", "political")
    d, _p2 = toggle_map_mode(c, "vitality", prior2)
    if c == "vitality" and d == "strain":
        passes.append("f3_toggles_prior")
    else:
        fails.append("f3_toggles_prior")
    e, _p3 = toggle_map_mode("political", "political", "strain")
    if e == "political":
        passes.append("f1_stays_political")
    else:
        fails.append("f1_stays_political")

    if toolbar_flow_max_width(1024) == 976.0:
        passes.append("flow_width_1024")
    else:
        fails.append("flow_width_1024")
    kept, overflow = chips_fit_in_rows([70.0] * 24, 580.0, 2, 4.0)
    if overflow > 0 and kept >= 10:
        passes.append("overflow_more")
    else:
        fails.append("overflow_more")
    kept2, overflow2 = chips_fit_in_rows([70.0] * 4, 580.0, 2, 4.0)
    if overflow2 == 0 and kept2 == 4:
        passes.append("short_row_no_more")
    else:
        fails.append("short_row_no_more")

    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    tb = TOOLBAR.read_text(encoding="utf-8") if TOOLBAR.is_file() else ""
    if not ren:
        fails.append("missing_renderer")
    if not tb:
        fails.append("missing_toolbar")

    handle_fn = _gd_func_slice(ren, "_handle_mapmode_hotkey")
    toggle_fn = _gd_func_slice(ren, "_toggle_map_mode_hotkey")
    input_i = ren.find("func _input")
    unh_i = ren.find("func _unhandled_input")
    input_fn = ren[input_i:unh_i] if input_i >= 0 and unh_i > input_i else ""
    if "_handle_mapmode_hotkey" in input_fn and bool(handle_fn):
        passes.append("fkeys_merged_helper")
    else:
        fails.append("fkeys_merged_helper")
    if "_handle_mapmode_hotkey" in _gd_func_slice(ren, "_unhandled_input"):
        passes.append("unhandled_uses_helper")
    else:
        fails.append("unhandled_uses_helper")
    if bool(toggle_fn) and "current_map_mode==" in toggle_fn.replace(" ", ""):
        passes.append("toggle_compares_current")
    else:
        fails.append("toggle_compares_current")
    for key, mode in (
        ("KEY_F2", "strain"),
        ("KEY_F3", "vitality"),
        ("KEY_F9", "resources"),
    ):
        if key in handle_fn and ('_toggle_map_mode_hotkey("%s")' % mode) in handle_fn:
            passes.append("hotkey_%s" % mode)
        else:
            fails.append("hotkey_%s" % mode)
    if "ctrl_pressed" in handle_fn and '_toggle_map_mode_hotkey("terrain")' in handle_fn:
        passes.append("ctrl_f9_terrain_toggle")
    else:
        fails.append("ctrl_f9_terrain_toggle")

    if 'HFlowContainer' in tb and "_preset_row" in tb and "_secondary_row" in tb:
        passes.append("flow_rows")
    else:
        fails.append("flow_rows")
    if "More ▾" in tb or "More \\u25be" in tb:
        passes.append("more_menu")
    else:
        fails.append("more_menu")
    if 'text = "Intensity"' in tb or 'cap.text = "Intensity"' in tb:
        passes.append("intensity_caption")
    else:
        fails.append("intensity_caption")
    for lab in INTENSITY_LABELS:
        if '"%s"' % lab in tb:
            passes.append("intensity_%s" % lab.lower())
        else:
            fails.append("intensity_%s" % lab.lower())
    if "120" in tb and ("GradientTexture2D" in tb or "gradient" in tb.lower()):
        passes.append("intensity_swatch")
    else:
        fails.append("intensity_swatch")
    pack_fn = _gd_func_slice(tb, "_pack_flow_with_more")
    discard_fn = _gd_func_slice(tb, "_discard_node")
    if "old.free()" not in pack_fn and "queue_free" in discard_fn:
        passes.append("pack_queue_free")
    else:
        fails.append("pack_queue_free")
    if "CONNECT_DEFERRED" in tb:
        passes.append("deferred_strip_press")
    else:
        fails.append("deferred_strip_press")
    char_fn = _gd_func_slice(ren, "_characterize_province_fill")
    infra_i = char_fn.find('debug_tint_mode == "infra"')
    infra_slice = char_fn[infra_i : infra_i + 1200] if infra_i >= 0 else ""
    if infra_i >= 0 and "0.12" not in infra_slice and "infra_col" in infra_slice:
        passes.append("f7_infra_visible_tint")
    else:
        fails.append("f7_infra_visible_tint")
    style_fn = _gd_func_slice(tb, "_apply_mode_chip_idle_style")
    if "CYAN" in style_fn and "BG_DEEP" in style_fn:
        passes.append("active_cyan_fill")
    else:
        fails.append("active_cyan_fill")
    layout_fn = _gd_func_slice(ren, "_layout_map_ui")
    if "offset_right" in layout_fn:
        passes.append("toolbar_layout_right")
    else:
        fails.append("toolbar_layout_right")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "hotkeys": dict(HOTKEY_MODES),
        "intensity_labels": list(INTENSITY_LABELS),
        "summary": "FIRST20-P2 F7 mapmode toggle/strip · %s · fail=%s"
        % ("PASS" if ok else "FAIL", ",".join(fails) or "none"),
        "integration": [
            "first20_p2_mapmode_toggle_product",
            "MapRenderer._toggle_map_mode_hotkey",
            "MapModeToolbar HFlowContainer",
        ],
    }


def first20_p2_mapmode_toggle_integrity() -> Dict[str, Any]:
    p = build_first20_p2_mapmode_toggle_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
