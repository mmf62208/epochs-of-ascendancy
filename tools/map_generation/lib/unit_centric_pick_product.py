"""Unit-centric pin pick integrity — pin-first hit disk + selected chip, no inspector.

Grep/wiring gate for MapRenderer unit pick path (L1 war-loop slice 1).
Does not rewrite assault/move behavior or unit-card assign mode.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"

# Discoverability / integrity strings grepped from MapRenderer (must stay in live path).
STRATEGIC_PICK_TOAST = "Click a unit chip to command (Shift+U toggles counters)."
STACK_CYCLE_HINT = "Stack %d/%d · [ ] or buttons to cycle"
SELECTED_FRAME_HOOK = "_refresh_selected_unit_chip"
HIT_RADIUS_PX = 80.0
HIT_RADIUS_FLOOR = 40.0


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


def _hit_radius_ok(pick_fn: str) -> bool:
    if not pick_fn:
        return False
    has_80 = bool(re.search(r"\b80(?:\.0)?\b", pick_fn))
    has_40 = bool(re.search(r"\b40(?:\.0)?\b", pick_fn))
    has_maxf_floor = "maxf" in pick_fn and ("40.0" in pick_fn or "40" in pick_fn)
    return has_80 and has_40 and has_maxf_floor


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
    hit_ok = _hit_radius_ok(pick_fn)
    wiring["hit_radius_80_floor_40"] = hit_ok
    if hit_ok:
        passes.append("hit_radius_80_floor_40")
    else:
        fails.append("hit_radius_80_floor_40")

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

    cycle_fn = _gd_func_slice(ren, "_cycle_selected_stack_unit")
    stack_map = (
        bool(cycle_fn)
        and "_bind_chip_to_selected_formation" in cycle_fn
        and "_sync_selected_unit_order_paths" in cycle_fn
    )
    wiring["stack_cycle_map_chip"] = stack_map
    if stack_map:
        passes.append("stack_cycle_map_chip")
    else:
        fails.append("stack_cycle_map_chip")

    cycle_no_rebuild = (
        bool(cycle_fn)
        and "_show_unit_detail_popup_for_selected" not in cycle_fn
        and "_patch_open_unit_card_for_selected" in cycle_fn
    )
    wiring["stack_cycle_no_card_rebuild"] = cycle_no_rebuild
    if cycle_no_rebuild:
        passes.append("stack_cycle_no_card_rebuild")
    else:
        fails.append("stack_cycle_no_card_rebuild")

    land_open = _gd_func_slice(ren, "_try_open_land_unit_at_world")
    left_cycles = (
        bool(land_open)
        and "_cycle_selected_stack_unit(1)" in land_open
        and "_prompt_cancel_selected_orders" not in land_open
    )
    wiring["left_click_cycles_not_cancel"] = left_cycles
    if left_cycles:
        passes.append("left_click_cycles_not_cancel")
    else:
        fails.append("left_click_cycles_not_cancel")
    own_hex = _gd_func_slice(ren, "order_selected_unit_at_province")
    right_cancel = (
        bool(own_hex)
        and "_prompt_cancel_selected_orders" in own_hex
        and 'from_pid == int(province.id)' in own_hex
    )
    wiring["right_click_same_hex_cancel"] = right_cancel
    if right_cancel:
        passes.append("right_click_same_hex_cancel")
    else:
        fails.append("right_click_same_hex_cancel")

    hover_fn = _gd_func_slice(ren, "_update_spatial_hover")
    hover_pin = (
        bool(hover_fn)
        and "_pick_unit_formation_at_world" in hover_fn
        and "stationed_province_id" in hover_fn
    )
    wiring["hover_pin_first"] = hover_pin
    if hover_pin:
        passes.append("hover_pin_first")
    else:
        fails.append("hover_pin_first")

    stw = _gd_func_slice(ren, "_screen_to_world")
    canvas_hover = (
        bool(stw)
        and "get_canvas_transform().affine_inverse()" in stw
        and "cam.get_canvas_transform()" not in stw
    )
    wiring["hover_canvas_not_camera_node"] = canvas_hover
    if canvas_hover:
        passes.append("hover_canvas_not_camera_node")
    else:
        fails.append("hover_canvas_not_camera_node")

    badge_fn = _gd_func_slice(ren, "_make_formation_stack_badge")
    plates_fn = _gd_func_slice(ren, "_make_stack_offset_plates")
    stack_vis = (
        "_make_stack_offset_plates" in ren
        and "StackBack" in ren
        and bool(badge_fn)
        and "Label.new" not in badge_fn
        and ("_UnitChipTextScr" in badge_fn or "UnitChipText" in badge_fn)
        and "Line2D" in plates_fn
        and "StackEdge" in plates_fn
    )
    wiring["stack_visible_badge"] = stack_vis
    if stack_vis:
        passes.append("stack_visible_badge")
    else:
        fails.append("stack_visible_badge")

    land_fn = _gd_func_slice(ren, "_try_open_land_unit_at_world")
    deferred_fn = _gd_func_slice(ren, "_deferred_command_click")
    i_chip = deferred_fn.find("_try_open_land_unit_at_world") if deferred_fn else -1
    i_arrow = deferred_fn.find("_try_pick_order_intent") if deferred_fn else -1
    chip_before_arrow = i_chip >= 0 and i_arrow >= 0 and i_chip < i_arrow
    wiring["chip_before_fight_arrow"] = chip_before_arrow
    if chip_before_arrow:
        passes.append("chip_before_fight_arrow")
    else:
        fails.append("chip_before_fight_arrow")
    ctrl_safe = (
        bool(deferred_fn)
        and "ctrl_click" in deferred_fn
        and "ctrl-order enemy chip" in deferred_fn
        and bool(land_fn)
        and "_open_fight_from_formation_id" not in land_fn
        and "not event.shift_pressed" in spatial
        and "_deferred_command_click" in spatial
    )
    wiring["ctrl_click_no_stack_freeze"] = ctrl_safe
    if ctrl_safe:
        passes.append("ctrl_click_no_stack_freeze")
    else:
        fails.append("ctrl_click_no_stack_freeze")

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
        "; capital_star_before_chip; chip_match_station_province_one_pin_per_hex",
    }


def unit_centric_pick_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_centric_pick_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
