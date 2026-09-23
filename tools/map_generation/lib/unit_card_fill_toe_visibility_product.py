"""Unit-card Fill%/TOE first-session visibility — promoted fold line above clip.

Player value: first click on a unit always shows Fill NN% · TOE … as its own
15–16px CYAN/SUCCESS/WARNING label (not TEXT_DIM body) on a 320×220 dock,
unclipped and not Strength%. Org/Str/Rdy/XP/plan/trench/Speed/Armor/Men
and last-3 combat log stay on tooltip, not equal-weight body lines.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from map_unit_counter_lod_product import europe_home_zoom_wants_counters
from unit_card_combat_strip_product import fill_toe_fold_line, lines_for
from unit_centric_pick_product import (
    home_band_hit_disk_tracks_scale,
)

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
STRIP_GD = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
TOOLTIP_GD = ROOT / "scripts" / "map" / "ProvinceHoverTooltip.gd"
LOD_GD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"


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


def fill_not_aliased_to_strength() -> bool:
    """Fill% must not copy Strength% when toe_fill is absent or different."""
    strength_only = fill_toe_fold_line({"strength": 0.40})
    mixed = fill_toe_fold_line({"strength": 1.0, "toe_fill": 0.28})
    fold_lines = lines_for({"strength": 0.40, "toe_fill": 0.80})
    join = "\n".join(fold_lines)
    return (
        "Fill —%" in strength_only
        and "40%" not in strength_only
        and "Fill 28%" in mixed
        and "100%" not in mixed
        and fold_lines
        and fold_lines[0].startswith("Fill 80%")
        and "Strength 40%" in join
        and "Fill 80%" in join
    )


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
        and (
            "Fill —% · TOE —" in fill_blk
            or "strip0[0]" in fill_blk
            or "strip[0]" in fill_blk
            or "_fill_toe_fold_line" in fill_blk
        )
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
    # Ratio upgrade may run after body so a strip throw cannot abort Stationed/Leader.
    ratio_ok = "_fill_ratio_for" in popup or "_safe_unit_card_fill_ratio" in popup
    not_dim = "TEXT_DIM" not in fill_blk
    color_path = warn_ok and ok_col and ratio_ok and not_dim
    wiring["fill_warning_success_color"] = color_path
    (passes if color_path else fails).append("fill_warning_success_color")

    gd_no_str_fill = (
        'return "Fill —%"' in strip
        or 'return "Fill —%"' in lines_fn
        or "Fill —%" in strip
    )
    py_distinct = fill_not_aliased_to_strength()
    wiring["fill_distinct_from_strength"] = bool(gd_no_str_fill and py_distinct)
    (passes if wiring["fill_distinct_from_strength"] else fails).append(
        "fill_distinct_from_strength"
    )

    clip_off = "clip_contents = false" in popup
    min_h = _panel_min_height(popup)
    dock_220 = min_h is not None and 200.0 <= min_h <= 240.0
    clip_or_tall = clip_off and dock_220
    wiring["clip_false_or_min_height_360"] = clip_or_tall
    (passes if clip_or_tall else fails).append("clip_false_or_min_height_360")
    wiring["docked_320_220"] = bool(re.search(r"Vector2\(\s*320\s*,\s*220\s*\)", popup)) and dock_220
    (passes if wiring["docked_320_220"] else fails).append("docked_320_220")

    wrap_ok = (
        "AUTOWRAP_WORD" in fill_blk
        and "AUTOWRAP_OFF" not in fill_blk
        and "clip_text = false" in fill_blk
    )
    wiring["fill_wrap_not_clip"] = wrap_ok
    (passes if wrap_ok else fails).append("fill_wrap_not_clip")

    bar_ok = "FillToeBar" in popup and "ProgressBar.new()" in fill_blk
    wiring["fill_bar_present"] = bar_ok
    (passes if bar_ok else fails).append("fill_bar_present")

    # Strength% must not paint the Fill label (no fill_ratio = str_v).
    no_str_alias = "fill_ratio = str_v" not in fill_blk and "fill_ratio = str_v" not in popup
    wiring["fill_not_strength_fallback"] = no_str_alias
    (passes if no_str_alias else fails).append("fill_not_strength_fallback")

    org_tip = "Org %.0f%% · Str %.0f%%" in popup
    org_not_body_append = "lines.append(\n\t\t\"Org" not in popup and 'lines.append("Org' not in popup
    strip_rest_not_all_body = (
        "chrome_tips.append(rest_ln)" in popup
        and "begins_with(\"Training\")" in popup
    )
    chrome_tip_ok = org_tip and org_not_body_append and strip_rest_not_all_body
    wiring["chrome_org_str_tooltip_not_body"] = chrome_tip_ok
    (passes if chrome_tip_ok else fails).append("chrome_org_str_tooltip_not_body")

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

    # Play DIG FAIL: province glance tooltip stole GER Division clicks so the
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

    # DIG-FIRST: open-path is useless while chips are unpainted at Europe Home.
    lod = LOD_GD.read_text(encoding="utf-8") if LOD_GD.is_file() else ""
    want_fn = _gd_func_slice(ren, "_unit_counters_want_visible")
    home_fn = _gd_func_slice(ren, "center_europe_in_world_view")
    begin_fn = _gd_func_slice(ren, "_center_camera_on_province")
    scale_fn = _gd_func_slice(ren, "_unit_counter_scale_for_zoom")
    europe_want = (
        europe_home_zoom_wants_counters()
        and "show_unit_counters_for_zoom" in want_fn
        and "EUROPE_HOME_COUNTER_MIN_ZOOM" in lod
    )
    wiring["europe_home_counters_want_visible"] = europe_want
    (passes if europe_want else fails).append("europe_home_counters_want_visible")
    home_sync = "_sync_unit_counter_paint" in home_fn and "_sync_unit_counter_paint" in begin_fn
    wiring["home_syncs_counter_visibility"] = home_sync
    (passes if home_sync else fails).append("home_syncs_counter_visibility")
    scale_floor = "clampf(target, 0.85, 16.0)" in scale_fn
    wiring["counter_scale_floor_readable"] = scale_floor
    (passes if scale_floor else fails).append("counter_scale_floor_readable")

    # DIG-FIRST (be1d480): chips paint at Home but 48px disk misses chrome/label.
    pick_fn = _gd_func_slice(ren, "_pick_unit_formation_at_world")
    hit_fn = _gd_func_slice(ren, "_unit_counter_hit_radius_world")
    home_hit = (
        home_band_hit_disk_tracks_scale()
        and "_unit_counter_hit_radius_world" in pick_fn
        and "0.5 * sprite_px" in hit_fn
        and "sqrt(2.0)" in hit_fn
        and "label_pad" in hit_fn
        and "_unit_counter_aabb_hit_screen" in hit_fn
        and "_unit_counter_scale_for_zoom" in hit_fn
        and "maxf(48.0" in hit_fn
        and "counter.position" in pick_fn
    )
    wiring["home_hit_disk_tracks_counter_scale"] = home_hit
    (passes if home_hit else fails).append("home_hit_disk_tracks_counter_scale")
    land_pick_fn = _gd_func_slice(ren, "_pick_land_unit_formation_at_world")
    block_type_fn = _gd_func_slice(ren, "_formation_type_blocks_land_open")
    land_skips_air = (
        bool(land_fn)
        and "_pick_land_unit_formation_at_world" in land_fn
        and bool(land_pick_fn)
        and "land_only" in land_pick_fn
        and "land_only" in pick_fn
        and "_formation_type_blocks_land_open" in pick_fn
        and bool(block_type_fn)
        and "TYPE_AIR_WING" in block_type_fn
        and "TYPE_FLEET" in block_type_fn
        and "TYPE_SPACE_WING" in block_type_fn
        and "DIG_CHIP_MISS" not in ren
        and "DIG_CHIP_SKIP" not in ren
    )
    wiring["land_still_click_skips_air_fleet"] = land_skips_air
    (passes if land_skips_air else fails).append("land_still_click_skips_air_fleet")

    # DIG-FIRST (d998fcd): still-click opened title+Close only — strip fault before body.
    always_fill = (
        "Fill —% · TOE —" in fill_blk
        and "vbox.add_child(fill_lbl)" in fill_blk
        and popup.find("vbox.add_child(fill_lbl)") < popup.find("var body :=")
        and popup.find("body_scroll.add_child(body)") < popup.find("_safe_unit_card_strip_lines")
        and "_safe_unit_card_fill_ratio" in popup
        and "begins_with(\"Strength\")" in popup
    )
    wiring["always_paint_fill_before_strip"] = always_fill
    (passes if always_fill else fails).append("always_paint_fill_before_strip")

    force_sz = (
        "_apply_unit_detail_popup_min_size" in popup
        and "panel.size" in _gd_func_slice(ren, "_apply_unit_detail_popup_min_size")
        and "Vector2(320, 220)" in _gd_func_slice(ren, "_apply_unit_detail_popup_min_size")
    )
    wiring["force_popup_size_320_220"] = force_sz
    (passes if force_sz else fails).append("force_popup_size_320_220")

    refresh_fn = _gd_func_slice(ren, "_refresh_hover_tooltip")
    spatial_fn = _gd_func_slice(ren, "_update_spatial_hover")
    tip_hide = (
        "_unit_detail_popup_is_visible" in refresh_fn
        and "_hide_hover_tooltip" in refresh_fn
        and refresh_fn.find("_unit_detail_popup_is_visible") < refresh_fn.find("_is_mouse_over_blocking_ui")
        and "_unit_detail_popup_is_visible" in spatial_fn
        and "_hide_hover_tooltip" in popup
    )
    wiring["tooltip_suppressed_while_unit_card"] = tip_hide
    (passes if tip_hide else fails).append("tooltip_suppressed_while_unit_card")

    strip_safe = (
        "_safe_composition" in strip
        and "_safe_float_prop" in strip
        and "is_instance_valid(formation)" in lines_fn
        and "get_unit_equipment_stock" in _gd_func_slice(strip, "_fill_ratio_for")
        and "unit_toe_fill_ratio" in strip
        and "composition_from_formation" in _gd_func_slice(strip, "_safe_composition")
        and "_formation_has_composition_meta" not in strip
    )
    wiring["strip_safe_ger_demo"] = strip_safe
    (passes if strip_safe else fails).append("strip_safe_ger_demo")

    # Play FAIL tip 194027d: class_name.has_method is a Godot 4 parse error.
    ready_fn = _gd_func_slice(ren, "_unit_card_combat_strip_ready")
    fill_fn = _gd_func_slice(ren, "_safe_unit_card_fill_ratio")
    tip_safe_fn = _gd_func_slice(ren, "_safe_unit_card_tooltip_lines")
    no_class_has_method = (
        "UnitCardCombatStrip.has_method(" not in ren
        and "typeof(UnitCardCombatStrip) != TYPE_NIL" in ready_fn
        and "UnitCardCombatStrip.lines_for(" in _gd_func_slice(ren, "_safe_unit_card_strip_lines")
        and "UnitCardCombatStrip._fill_ratio_for(" in fill_fn
        and "UnitCardCombatStrip.tooltip_lines_for(" in tip_safe_fn
        and "has_method(" not in ready_fn
        and "has_method(" not in fill_fn
        and "has_method(" not in tip_safe_fn
    )
    wiring["no_class_has_method_on_strip"] = no_class_has_method
    (passes if no_class_has_method else fails).append("no_class_has_method_on_strip")

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
