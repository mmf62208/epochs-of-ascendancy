"""Unit counter chrome — HOI-like chip stats + strategic cull.

Grep/wiring gate: nation plate + org/str bars on DemoUnitIcon, docked HUD card,
strategic chips culled so capitals/fronts stay clickable; pin-first when visible.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from map_unit_counter_lod_product import (  # type: ignore
    TIER_OPERATIONAL,
    TIER_STRATEGIC,
    show_unit_counters,
    unit_counter_compact,
)

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
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


def build_unit_counter_chrome_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    lod = LOD_GD.read_text(encoding="utf-8") if LOD_GD.is_file() else ""

    if not ren:
        fails.append("missing_map_renderer")
        return {
            "ok": False,
            "status": "FAIL",
            "pass": passes,
            "fail": fails,
            "wiring": wiring,
            "summary": "unit_counter_chrome · FAIL · missing MapRenderer",
        }

    cull_ok = (not show_unit_counters(TIER_STRATEGIC, True)) and unit_counter_compact(
        TIER_STRATEGIC
    )
    wiring["strategic_cull"] = cull_ok
    if cull_ok:
        passes.append("strategic_cull")
    else:
        fails.append("strategic_cull")

    counters_slice = _gd_func_slice(lod, "show_unit_counters")
    lod_cull = (
        bool(counters_slice)
        and "return t != Tier.STRATEGIC" in counters_slice
    )
    lod_compact_fn = "func unit_counter_compact" in lod
    wiring["lod_strategic_cull"] = lod_cull
    wiring["lod_compact_fn"] = lod_compact_fn
    if lod_cull:
        passes.append("lod_strategic_cull")
    else:
        fails.append("lod_strategic_cull")
    if lod_compact_fn:
        passes.append("lod_compact_fn")
    else:
        fails.append("lod_compact_fn")

    bars_fn = _gd_func_slice(ren, "_make_unit_stat_bars")
    bars_ok = bool(bars_fn) and "OrgBar" in bars_fn and "StrBar" in bars_fn
    wiring["stat_bars"] = bars_ok
    if bars_ok:
        passes.append("stat_bars")
    else:
        fails.append("stat_bars")

    plate_fn = _gd_func_slice(ren, "_make_unit_nation_plate")
    plate_ok = bool(plate_fn) and "NationPlate" in plate_fn
    wiring["nation_plate"] = plate_ok
    if plate_ok:
        passes.append("nation_plate")
    else:
        fails.append("nation_plate")

    attach_fn = _gd_func_slice(ren, "_attach_unit_counter_chrome")
    attach_ok = (
        bool(attach_fn)
        and "_make_unit_stat_bars" in attach_fn
        and "_make_unit_nation_plate" in attach_fn
    )
    rebuild = _gd_func_slice(ren, "_rebuild_demo_unit_icons")
    rebuild_attaches = "_attach_unit_counter_chrome" in rebuild
    wiring["chrome_on_rebuild"] = attach_ok and rebuild_attaches
    if attach_ok and rebuild_attaches:
        passes.append("chrome_on_rebuild")
    else:
        fails.append("chrome_on_rebuild")

    letter_ok = (
        "func _unit_type_letter" in ren
        and "func _make_unit_type_letter" in ren
        and "TypeLetter" in ren
        and "_make_unit_type_letter" in attach_fn
    )
    wiring["type_letter"] = letter_ok
    if letter_ok:
        passes.append("type_letter")
    else:
        fails.append("type_letter")

    desig_ok = (
        "func _unit_counter_designation" in ren
        and "Designation" in attach_fn
        and "_unit_counter_designation" in attach_fn
    )
    wiring["designation"] = desig_ok
    if desig_ok:
        passes.append("designation")
    else:
        fails.append("designation")

    land_nato_ok = (
        "infantry" in _gd_func_slice(ren, "_prefer_retrowave_unit_icon")
        and "opaque dark plates" in _gd_func_slice(ren, "_prefer_retrowave_unit_icon")
    )
    wiring["land_nato_not_retrowave"] = land_nato_ok
    if land_nato_ok:
        passes.append("land_nato_not_retrowave")
    else:
        fails.append("land_nato_not_retrowave")

    create_fn = _gd_func_slice(ren, "_create_province_node")
    no_dummy_furniture = (
        "unclickable dummy units" in create_fn
        and "continue" in create_fn
        and "_special_feature_sprite_path" in create_fn
    )
    wiring["no_retrowave_feature_dummy_units"] = no_dummy_furniture
    if no_dummy_furniture:
        passes.append("no_retrowave_feature_dummy_units")
    else:
        fails.append("no_retrowave_feature_dummy_units")

    no_sheet = "Do not atlas-crop nato_counters_sheet" in _gd_func_slice(
        ren, "_rebuild_demo_unit_icons"
    )
    wiring["no_nato_sheet_on_chips"] = no_sheet
    if no_sheet:
        passes.append("no_nato_sheet_on_chips")
    else:
        fails.append("no_nato_sheet_on_chips")

    chip_text_ok = "UnitChipText.gd" in ren and "_UnitChipTextScr" in attach_fn
    wiring["chip_text_not_control"] = chip_text_ok
    if chip_text_ok:
        passes.append("chip_text_not_control")
    else:
        fails.append("chip_text_not_control")

    popup = _gd_func_slice(ren, "_show_unit_detail_popup")
    dock_ok = bool(popup) and (
        "unit_card_dock" in popup or "UNIT_CARD_DOCK" in popup
    )
    stats_in_card = bool(popup) and "Org" in popup and ("Str" in popup or "strength" in popup)
    wiring["docked_unit_card"] = dock_ok
    wiring["card_has_stats"] = stats_in_card
    if dock_ok:
        passes.append("docked_unit_card")
    else:
        fails.append("docked_unit_card")
    if stats_in_card:
        passes.append("card_has_stats")
    else:
        fails.append("card_has_stats")

    pick_fn = _gd_func_slice(ren, "_pick_unit_formation_at_world")
    # Hidden chips (strategic cull / master off) must not steal hex clicks.
    pick_ok = (
        bool(pick_fn)
        and "not counter.visible" in pick_fn
        and "_unit_counters_want_visible" in pick_fn
    )
    wiring["pick_skips_hidden_only"] = pick_ok
    if pick_ok:
        passes.append("pick_skips_hidden_only")
    else:
        fails.append("pick_skips_hidden_only")

    # Shift+U must be handled before plain KEY_U (supply-flow toggle used to swallow it).
    i_shift_u = ren.find("event.shift_pressed")
    i_toggle = ren.find("toggle_unit_counters()")
    i_flow_u = ren.find("toggle_strategic_flow_overlay()")
    shift_u_first = i_toggle >= 0 and i_flow_u >= 0 and i_toggle < i_flow_u
    wiring["shift_u_before_plain_u"] = shift_u_first
    if shift_u_first:
        passes.append("shift_u_before_plain_u")
    else:
        fails.append("shift_u_before_plain_u")

    if not check_wiring:
        ok = cull_ok and bars_ok
    else:
        ok = len(fails) == 0

    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "unit_counter_chrome · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "integration": [
            "unit_counter_chrome_product",
            "map_unit_counter_lod_product",
            "unit_centric_pick_product",
        ],
        "policy": "hoi_chip_org_str_plate_docked_card_strategic_cull_pin_first_when_visible",
        "operational_shows": show_unit_counters(TIER_OPERATIONAL, True),
    }


def unit_counter_chrome_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_counter_chrome_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
