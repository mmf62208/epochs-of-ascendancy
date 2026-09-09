"""Unit-card Fill%/TOE first-session visibility — promoted fold line above clip.

Player value: first click on a unit always shows Fill NN% · TOE … as its own
15–16px SUCCESS/WARNING label (not TEXT_DIM body), unclipped. Speed/Armor/Men
and last-3 combat log stay on tooltip, not equal-weight body lines.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
STRIP_GD = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
TOOLTIP_GD = ROOT / "scripts" / "map" / "ProvinceHoverTooltip.gd"


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


def fill_fold_color_token(fill_ratio: float) -> str:
    """SUCCESS (or CYAN) at ≥50% fill; WARNING below. Matches MapRenderer fill_lbl."""
    try:
        r = float(fill_ratio)
    except (TypeError, ValueError):
        r = 0.0
    return "WARNING" if r < 0.5 else "SUCCESS"


def _panel_min_height(popup: str) -> Optional[float]:
    m = re.search(
        r"custom_minimum_size\s*=\s*Vector2\(\s*[\d.]+\s*,\s*([\d.]+)\s*\)",
        popup,
    )
    if not m:
        return None
    try:
        return float(m.group(1))
    except (TypeError, ValueError):
        return None


def _fill_label_block(popup: str) -> str:
    i = popup.find("fill_lbl")
    if i < 0:
        return ""
    j = popup.find("var body :=", i)
    if j < 0:
        j = popup.find("var body =", i)
    if j < 0:
        return popup[i : i + 1800]
    return popup[i:j]


def build_unit_card_fill_toe_visibility_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    color_ok = (
        fill_fold_color_token(0.5) == "SUCCESS"
        and fill_fold_color_token(1.0) == "SUCCESS"
        and fill_fold_color_token(0.49) == "WARNING"
        and fill_fold_color_token(0.0) == "WARNING"
    )
    wiring["fill_color_threshold"] = color_ok
    (passes if color_ok else fails).append("fill_color_threshold")

    if not check_wiring:
        ok = len(fails) == 0
        return {
            "ok": ok,
            "empty": False,
            "status": "PASS" if ok else "FAIL",
            "wiring": wiring,
            "pass": passes,
            "fail": fails,
            "summary": "unit_card_fill_toe_visibility · %s · fail=%s"
            % ("PASS" if ok else "FAIL", ",".join(fails) or "none"),
            "integration": [
                "unit_card_fill_toe_visibility_product",
                "MapRenderer._show_unit_detail_popup",
                "MapRenderer._try_open_land_chip_from_input",
                "UnitCardCombatStrip.lines_for",
            ],
        }

    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    strip = STRIP_GD.read_text(encoding="utf-8") if STRIP_GD.is_file() else ""
    popup = _gd_func_slice(ren, "_show_unit_detail_popup")
    fill_blk = _fill_label_block(popup)
    lines_fn = _gd_func_slice(strip, "lines_for")
    tip_fn = _gd_func_slice(strip, "tooltip_lines_for")

    if not ren or not popup:
        fails.append("missing_popup")
    if not strip or not lines_fn:
        fails.append("missing_strip")

    promoted = (
        bool(fill_blk)
        and "Label.new()" in fill_blk
        and "vbox.add_child(fill_lbl)" in fill_blk
        and "var body :=" in popup
        and popup.find("fill_lbl") < popup.find("var body :=")
        and ("strip0[0]" in fill_blk or "strip[0]" in fill_blk or "_fill_toe_fold_line" in fill_blk)
    )
    wiring["promoted_fill_label_before_body"] = promoted
    (passes if promoted else fails).append("promoted_fill_label_before_body")

    font_ok = bool(
        re.search(r'add_theme_font_size_override\(\s*"font_size"\s*,\s*1[56]\s*\)', fill_blk)
    )
    wiring["fill_font_15_or_16"] = font_ok
    (passes if font_ok else fails).append("fill_font_15_or_16")

    warn_ok = "RetrowaveTheme.WARNING" in fill_blk and (
        "fill_ratio < 0.5" in fill_blk or "fill < 0.5" in fill_blk
    )
    ok_col = "RetrowaveTheme.SUCCESS" in fill_blk or "RetrowaveTheme.CYAN" in fill_blk
    ratio_ok = "_fill_ratio_for" in fill_blk
    not_dim = "TEXT_DIM" not in fill_blk
    color_path = warn_ok and ok_col and ratio_ok and not_dim
    wiring["fill_warning_success_color"] = color_path
    (passes if color_path else fails).append("fill_warning_success_color")

    clip_off = "clip_contents = false" in popup
    min_h = _panel_min_height(popup)
    tall_enough = min_h is not None and min_h >= 350.0
    clip_or_tall = clip_off or tall_enough
    wiring["clip_false_or_min_height_360"] = clip_or_tall
    (passes if clip_or_tall else fails).append("clip_false_or_min_height_360")

    speed_not_body = (
        "Speed %.1f" not in popup
        and 'lines.append("Speed' not in popup
        and "Speed %.1f" in tip_fn
        and "Width %.0f" in tip_fn
        and "Speed %.1f" not in lines_fn
    )
    wiring["speed_armor_men_tooltip_not_body"] = speed_not_body
    (passes if speed_not_body else fails).append("speed_armor_men_tooltip_not_body")

    clog_in_lines_logic = (
        '"combat_log" in formation' in lines_fn
        or "formation.get(\"combat_log\")" in lines_fn
        or 'data.get("combat_log")' in lines_fn
    )
    clog_not_body = not clog_in_lines_logic
    clog_tip_or_skip = (
        "_combat_log_tip_lines" in tip_fn
        or '"combat_log" in formation' in tip_fn
        or 'rest_ln[4] == "-"' in popup
    )
    clog_ok = clog_not_body and clog_tip_or_skip
    wiring["combat_log_not_card_body"] = clog_ok
    (passes if clog_ok else fails).append("combat_log_not_card_body")

    fold_first = (
        "_fill_toe_fold_line" in lines_fn
        and "lines.append(fold)" in lines_fn
        and lines_fn.find("_fill_toe_fold_line") < lines_fn.find("XP %s")
    )
    wiring["fold_fill_toe_first"] = fold_first
    (passes if fold_first else fails).append("fold_fill_toe_first")

    # Play c6a06cc: province glance tooltip stole GER Division clicks so the
    # Fill%/TOE card never opened. Chip still-click must run in `_input`
    # (before GUI) and tooltip children must IGNORE.
    tip = TOOLTIP_GD.read_text(encoding="utf-8") if TOOLTIP_GD.is_file() else ""
    input_i = ren.find("func _input")
    unh_i = ren.find("func _unhandled_input")
    input_fn = ren[input_i:unh_i] if input_i >= 0 and unh_i > input_i else ""
    chip_in_fn = _gd_func_slice(ren, "_try_open_land_chip_from_input")
    block_fn = _gd_func_slice(ren, "_is_mouse_over_blocking_ui")
    land_fn = _gd_func_slice(ren, "_try_open_land_unit_at_world")
    tooltip_ignore = (
        bool(tip)
        and "func _ignore_mouse_tree" in tip
        and "margin.mouse_filter = Control.MOUSE_FILTER_IGNORE" in tip
        and "_ignore_mouse_tree(self)" in tip
        and "MOUSE_FILTER_IGNORE" in tip
    )
    wiring["tooltip_mouse_ignore"] = tooltip_ignore
    (passes if tooltip_ignore else fails).append("tooltip_mouse_ignore")

    tooltip_not_blocker = bool(block_fn) and '"ProvinceHoverTooltip"' not in block_fn
    wiring["tooltip_not_map_pick_blocker"] = tooltip_not_blocker
    (passes if tooltip_not_blocker else fails).append("tooltip_not_map_pick_blocker")

    chip_open_in_input = (
        "_try_open_land_chip_from_input" in input_fn
        and bool(chip_in_fn)
        and "_try_open_land_unit_at_world" in chip_in_fn
        and "_show_unit_detail_popup" in land_fn
        and "show_info_panel" not in land_fn
        and "_handle_escape_key" not in chip_in_fn
        and "_mouse_over_search_control" in chip_in_fn
        and "_is_mouse_over_blocking_ui" in chip_in_fn
    )
    wiring["chip_open_in_input"] = chip_open_in_input
    (passes if chip_open_in_input else fails).append("chip_open_in_input")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "unit_card_fill_toe_visibility · %s · fail=%s"
        % ("PASS" if ok else "FAIL", ",".join(fails) or "none"),
        "integration": [
            "unit_card_fill_toe_visibility_product",
            "MapRenderer._show_unit_detail_popup",
            "MapRenderer._try_open_land_chip_from_input",
            "UnitCardCombatStrip.lines_for",
        ],
    }


def unit_card_fill_toe_visibility_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_card_fill_toe_visibility_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
