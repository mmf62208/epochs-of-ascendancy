"""Unit-centric pin pick integrity — pin-first hit disk + selected chip, no inspector.

Grep/wiring gate for MapRenderer unit pick path (L1 war-loop slice 1).
Does not rewrite assault/move behavior or unit-card assign mode.
"""
from __future__ import annotations

import math
import re
from pathlib import Path
from typing import Any, Dict, List

from map_unit_counter_lod_product import europe_home_zoom_wants_counters

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
LOD_GD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"

# Discoverability / integrity strings grepped from MapRenderer (must stay in live path).
STRATEGIC_PICK_TOAST = "Click a unit chip to command (Shift+U toggles counters)."
STACK_CYCLE_HINT = "Stack %d/%d · [ ] or buttons to cycle"
SELECTED_FRAME_HOOK = "_refresh_selected_unit_chip"
HIT_RADIUS_PX = 48.0
HIT_RADIUS_FLOOR = 20.0
SPRITE_PX = 32.0
COUNTER_SCALE_FLOOR = 0.85
COUNTER_SCALE_CEIL = 16.0
EUROPE_HOME_HIT_Z = 0.33


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


def _spatial_left_click_slice(renderer_src: str) -> str:
    """Rough slice of spatial MOUSE_BUTTON_LEFT pick block for pin-before-hex order."""
    marker = "use_spatial_picking and event is InputEventMouseButton"
    i = renderer_src.find(marker)
    if i < 0:
        return ""
    left = renderer_src.find("MOUSE_BUTTON_LEFT", i)
    if left < 0:
        left = i
    end = renderer_src.find("MOUSE_BUTTON_RIGHT", left)
    if end < 0 or end - left > 12000:
        end = left + 8000
    return renderer_src[left:end]


def unit_counter_scale_for_zoom(z: float) -> float:
    """Mirror MapRenderer._unit_counter_scale_for_zoom (paint scale)."""
    zz = max(float(z), 0.04)
    t = min(1.0, max(0.0, (zz - 0.2) / 1.6))
    screen_px = 48.0 + (58.0 - 48.0) * t
    target = screen_px / (SPRITE_PX * zz)
    return min(COUNTER_SCALE_CEIL, max(COUNTER_SCALE_FLOOR, target))


def unit_chip_hit_screen_px(z: float) -> float:
    """Screen-space hit radius. Home-band covers full plate+label AABB, not half-plate."""
    cscale = unit_counter_scale_for_zoom(z)
    label_pad = 16.0 if cscale >= 2.0 else 0.0
    return max(HIT_RADIUS_PX, 0.5 * SPRITE_PX * cscale * math.sqrt(2.0) + label_pad)


def home_band_hit_disk_tracks_scale() -> bool:
    """Europe Home (~0.33–0.49) must cover plate+label, not half-plate only."""
    home = unit_chip_hit_screen_px(EUROPE_HOME_HIT_Z)
    mid = unit_chip_hit_screen_px(0.49)
    tactical = unit_chip_hit_screen_px(1.0)
    old_half_plate = max(
        HIT_RADIUS_PX, 0.5 * SPRITE_PX * unit_counter_scale_for_zoom(EUROPE_HOME_HIT_Z)
    )
    return (
        home > HIT_RADIUS_PX + 8.0
        and home >= old_half_plate * 1.35
        and home >= 100.0
        and mid > HIT_RADIUS_PX
        and abs(tactical - HIT_RADIUS_PX) < 0.05
    )


def _hit_radius_ok(pick_fn: str, helper_fn: str = "") -> bool:
    if not pick_fn:
        return False
    blob = pick_fn + "\n" + helper_fn
    has_48 = bool(re.search(r"\b48(?:\.0)?\b", blob))
    has_20 = bool(re.search(r"\b20(?:\.0)?\b", blob))
    has_maxf_floor = "maxf" in blob and ("20.0" in blob or "20" in blob)
    return has_48 and has_20 and has_maxf_floor


def _home_hit_disk_wiring_ok(pick_fn: str, helper_fn: str) -> bool:
    """Pick must cover full plate+label AABB (not a half-plate / 48-only disk)."""
    if not pick_fn or not helper_fn:
        return False
    uses_helper = "_unit_counter_hit_radius_world" in pick_fn
    helper_tracks = (
        "0.5 * sprite_px" in helper_fn
        and "sqrt(2.0)" in helper_fn
        and "label_pad" in helper_fn
        and "_unit_counter_aabb_hit_screen" in helper_fn
        and "_unit_counter_scale_for_zoom" in helper_fn
        and "maxf(48.0" in helper_fn
        and "20.0" in helper_fn
    )
    live_plate = "counter.position" in pick_fn
    return uses_helper and helper_tracks and live_plate and home_band_hit_disk_tracks_scale()


def build_unit_centric_pick_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""

    if not ren:
        fails.append("missing_map_renderer")
        return {
            "ok": False,
            "status": "FAIL",
            "pass": passes,
            "fail": fails,
            "wiring": wiring,
            "summary": "unit_centric_pick · FAIL · missing MapRenderer",
        }

    pin_fn = _gd_func_slice(ren, "_try_open_unit_at_world")
    pick_fn = _gd_func_slice(ren, "_pick_unit_formation_at_world")
    hit_fn = _gd_func_slice(ren, "_unit_counter_hit_radius_world")
    select_fn = _gd_func_slice(ren, "_select_map_unit")
    spatial = _spatial_left_click_slice(ren)

    # 1) Pin branch first: _try_open_unit_at_world before hex resolve.
    # Capital gold star wins over a colocated chip (Berlin Air Wing / London star).
    pin_first = False
    star_before_chip = False
    if spatial:
        i_pin = spatial.find("_try_open_unit_at_world")
        i_hex = spatial.find("get_province_at_world_pos")
        i_star = spatial.find("_capital_star_pid_at")
        pin_first = i_pin >= 0 and i_hex >= 0 and i_pin < i_hex
        star_before_chip = i_star >= 0 and i_pin >= 0 and i_star < i_pin
    wiring["pin_before_hex"] = pin_first
    if pin_first:
        passes.append("pin_before_hex")
    else:
        fails.append("pin_before_hex")
    wiring["capital_star_before_chip"] = star_before_chip
    if star_before_chip:
        passes.append("capital_star_before_chip")
    else:
        fails.append("capital_star_before_chip")

    # 2) Hit disk ≥48 px / zoom with floor ≥20 world units.
    hit_ok = _hit_radius_ok(pick_fn, hit_fn)
    wiring["hit_radius_48_floor_20"] = hit_ok
    if hit_ok:
        passes.append("hit_radius_48_floor_20")
    else:
        fails.append("hit_radius_48_floor_20")
    # 2b) Home-band painted chips are 2–3× the old 48px disk — track scale.
    home_hit_ok = _home_hit_disk_wiring_ok(pick_fn, hit_fn)
    wiring["home_hit_disk_tracks_counter_scale"] = home_hit_ok
    if home_hit_ok:
        passes.append("home_hit_disk_tracks_counter_scale")
    else:
        fails.append("home_hit_disk_tracks_counter_scale")

    # 3) hang-class: no show_info_panel in pin open path.
    pin_no_insp = bool(pin_fn) and "show_info_panel" not in pin_fn
    wiring["pin_select_no_inspector"] = pin_no_insp
    if pin_no_insp:
        passes.append("pin_select_no_inspector")
    else:
        fails.append("pin_select_no_inspector")

    # 4) Selected-frame hook present (gold/cyan chip, no full rebuild).
    sel_hook = SELECTED_FRAME_HOOK in ren and "SelectedFrame" in ren
    wiring["selected_frame_hook"] = sel_hook
    if sel_hook:
        passes.append("selected_frame_hook")
    else:
        fails.append("selected_frame_hook")

    # 5) Hidden pins do not steal hexes.
    skip_hidden = bool(pick_fn) and "not counter.visible" in pick_fn
    wiring["hidden_pins_skip"] = skip_hidden
    if skip_hidden:
        passes.append("hidden_pins_skip")
    else:
        fails.append("hidden_pins_skip")

    # 6) Prefer player-tag pins on overlap.
    prefer_player = bool(pick_fn) and (
        "best_player" in pick_fn or "player" in pick_fn.lower()
    ) and ("country_tag" in pick_fn)
    wiring["prefer_player_pin"] = prefer_player
    if prefer_player:
        passes.append("prefer_player_pin")
    else:
        fails.append("prefer_player_pin")

    # 7) Discoverability copy present for product greps.
    toast_ok = STRATEGIC_PICK_TOAST in ren
    wiring["strategic_pick_toast"] = toast_ok
    if toast_ok:
        passes.append("strategic_pick_toast")
    else:
        fails.append("strategic_pick_toast")

    stack_ok = (
        "get_divisions_at_province" in ren
        and ("_cycle_selected_stack_unit" in ren or "[ ]" in ren)
        and "Stack" in ren
    )
    wiring["stack_cycle"] = stack_ok
    if stack_ok:
        passes.append("stack_cycle")
    else:
        fails.append("stack_cycle")

    # 8) Selection applies chip chrome (select path calls refresh).
    select_refreshes = bool(select_fn) and SELECTED_FRAME_HOOK in select_fn
    wiring["select_refreshes_chip"] = select_refreshes
    if select_refreshes:
        passes.append("select_refreshes_chip")
    else:
        fails.append("select_refreshes_chip")

    # 9) One pin per province: chip must match station province (stack cycle safe).
    refresh_fn = _gd_func_slice(ren, "_refresh_selected_unit_chip")
    chip_by_province = (
        bool(refresh_fn)
        and "stationed_province_id" in refresh_fn
        and ("province_id" in refresh_fn or "sel_pid" in refresh_fn)
        and "pin_pid" in refresh_fn
    )
    wiring["chip_match_by_province"] = chip_by_province
    if chip_by_province:
        passes.append("chip_match_by_province")
    else:
        fails.append("chip_match_by_province")

    # free() same-frame (not queue_free alone) avoids SelectedFrame2 orphans on re-select.
    frame_free_ok = bool(refresh_fn) and (
        ".free()" in refresh_fn or "remove_child" in refresh_fn
    )
    wiring["selected_frame_immediate_free"] = frame_free_ok
    if frame_free_ok:
        passes.append("selected_frame_immediate_free")
    else:
        fails.append("selected_frame_immediate_free")

    # Play DIG FAIL: glance tooltip stole Division clicks. Land chip still-click
    # must run in `_input` (before GUI) and tooltip must not be a pick blocker.
    input_i = ren.find("func _input")
    unh_i = ren.find("func _unhandled_input")
    input_fn = ren[input_i:unh_i] if input_i >= 0 and unh_i > input_i else ""
    chip_in_fn = _gd_func_slice(ren, "_try_open_land_chip_from_input")
    block_fn = _gd_func_slice(ren, "_is_mouse_over_blocking_ui")
    land_chip_in_input = (
        "_try_open_land_chip_from_input" in input_fn
        and bool(chip_in_fn)
        and "_try_open_land_unit_at_world" in chip_in_fn
        and "show_info_panel" not in chip_in_fn
        and "_handle_escape_key" not in chip_in_fn
    )
    wiring["land_chip_in_input"] = land_chip_in_input
    if land_chip_in_input:
        passes.append("land_chip_in_input")
    else:
        fails.append("land_chip_in_input")
    land_fn = _gd_func_slice(ren, "_try_open_land_unit_at_world")
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
    if land_skips_air:
        passes.append("land_still_click_skips_air_fleet")
    else:
        fails.append("land_still_click_skips_air_fleet")
    tooltip_not_blocker = bool(block_fn) and '"ProvinceHoverTooltip"' not in block_fn
    wiring["tooltip_not_pick_blocker"] = tooltip_not_blocker
    if tooltip_not_blocker:
        passes.append("tooltip_not_pick_blocker")
    else:
        fails.append("tooltip_not_pick_blocker")

    # DIG-FIRST: chips were absent at Begin GER → Europe Home (zoom ~0.33–0.49
    # still strategic-tier). Lock counters-want-visible on that band + Home/Begin paint.
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
    if europe_want:
        passes.append("europe_home_counters_want_visible")
    else:
        fails.append("europe_home_counters_want_visible")
    home_sync = "_sync_unit_counter_paint" in home_fn and "_sync_unit_counter_paint" in begin_fn
    wiring["home_syncs_counter_visibility"] = home_sync
    if home_sync:
        passes.append("home_syncs_counter_visibility")
    else:
        fails.append("home_syncs_counter_visibility")
    scale_floor = "clampf(target, 0.85, 16.0)" in scale_fn
    wiring["counter_scale_floor_readable"] = scale_floor
    if scale_floor:
        passes.append("counter_scale_floor_readable")
    else:
        fails.append("counter_scale_floor_readable")

    if not check_wiring:
        ok = toast_ok and hit_ok
    else:
        ok = len(fails) == 0

    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "hit_radius_px": HIT_RADIUS_PX,
        "hit_radius_floor": HIT_RADIUS_FLOOR,
        "home_hit_screen_px": unit_chip_hit_screen_px(EUROPE_HOME_HIT_Z),
        "strategic_toast": STRATEGIC_PICK_TOAST,
        "stack_cycle_hint": STACK_CYCLE_HINT,
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "unit_centric_pick · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "integration": [
            "unit_centric_pick_product",
            "map_unit_counter_lod_product",
            "MapRenderer _try_open_unit_at_world",
            "MapRenderer _pick_unit_formation_at_world",
        ],
        "policy": "pin_first_hit_disk_48_floor_20_selected_chip_no_inspector"
        "; home_hit_disk_tracks_counter_scale"
        "; home_hit_covers_full_plate_label_aabb"
        "; capital_star_before_chip; chip_match_station_province_one_pin_per_hex"
        "; land_still_click_skips_air_fleet",
    }


def unit_centric_pick_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_centric_pick_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
