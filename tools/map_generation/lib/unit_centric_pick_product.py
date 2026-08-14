"""Unit-centric pin pick integrity — pin-first hit disk + selected chip, no inspector.

Grep/wiring gate for MapRenderer unit pick path (PR 1 of unit-centric war loop).
Does not rewrite ASSAULT_STEPS or assault/move behavior.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
DESIGN_PICKER = ROOT / "scripts" / "ui" / "DesignPickerPopup.gd"

# Discoverability / integrity strings grepped from MapRenderer (must stay in live path).
STRATEGIC_PICK_TOAST = "Zoom in to pick units (Shift+U toggles counters)."
STACK_CYCLE_HINT = "Stack %d/%d · [ ] or buttons to cycle"
SELECTED_FRAME_HOOK = "_refresh_selected_unit_chip"
HIT_RADIUS_PX = 48.0
HIT_RADIUS_FLOOR = 20.0
# Unit card design surface (PR 6) — integrity strings for discoverability greps.
UNIT_CARD_MIN_SIZE = "Vector2(320, 360)"
UNIT_CARD_ASSIGN_COPY = "Designs you produce show up here — assign to this unit."
UNIT_CARD_ASSIGN_BTN = "Assign design"


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
    # Prefer the LEFT branch near this marker.
    left = renderer_src.find("MOUSE_BUTTON_LEFT", i)
    if left < 0:
        left = i
    # End at next major key/right-click spatial block or a distant func.
    end = renderer_src.find("MOUSE_BUTTON_RIGHT", left)
    if end < 0 or end - left > 12000:
        end = left + 8000
    return renderer_src[left:end]


def _hit_radius_ok(pick_fn: str) -> bool:
    if not pick_fn:
        return False
    # Require 48 screen-px radius and world floor of 20.
    has_48 = bool(re.search(r"\b48(?:\.0)?\b", pick_fn))
    has_20 = bool(re.search(r"\b20(?:\.0)?\b", pick_fn))
    has_maxf_floor = "maxf" in pick_fn and ("20.0" in pick_fn or "20" in pick_fn)
    return has_48 and has_20 and has_maxf_floor


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
    pin_first = False
    if spatial:
        i_pin = spatial.find("_try_open_unit_at_world")
        i_hex = spatial.find("get_province_at_world_pos")
        pin_first = i_pin >= 0 and i_hex >= 0 and i_pin < i_hex
    wiring["pin_before_hex"] = pin_first
    if pin_first:
        passes.append("pin_before_hex")
    else:
        fails.append("pin_before_hex")

    # 2) Hit disk ≥48 px / zoom with floor ≥20 world units.
    hit_ok = _hit_radius_ok(pick_fn)
    wiring["hit_radius_48_floor_20"] = hit_ok
    if hit_ok:
        passes.append("hit_radius_48_floor_20")
    else:
        fails.append("hit_radius_48_floor_20")

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

    # 10) Unit card design surface (PR 6): 320×360 + scroll + template/stockpile/assign.
    card_fn = _gd_func_slice(ren, "_show_unit_detail_popup")
    card_size_ok = bool(card_fn) and UNIT_CARD_MIN_SIZE in card_fn
    wiring["unit_card_320x360"] = card_size_ok
    if card_size_ok:
        passes.append("unit_card_320x360")
    else:
        fails.append("unit_card_320x360")

    card_scroll_ok = bool(card_fn) and (
        "ScrollContainer" in card_fn or "UnitDetailScroll" in card_fn
    )
    wiring["unit_card_scroll"] = card_scroll_ok
    if card_scroll_ok:
        passes.append("unit_card_scroll")
    else:
        fails.append("unit_card_scroll")

    card_template_ok = bool(card_fn) and (
        "get_template" in card_fn
        and "visual_archetype" in card_fn
        and "get_country_equipment_stockpile" in card_fn
        and "get_unit_equipment_stock" in card_fn
    )
    wiring["unit_card_template_stockpile"] = card_template_ok
    if card_template_ok:
        passes.append("unit_card_template_stockpile")
    else:
        fails.append("unit_card_template_stockpile")

    card_assign_copy = UNIT_CARD_ASSIGN_COPY in ren
    wiring["unit_card_assign_copy"] = card_assign_copy
    if card_assign_copy:
        passes.append("unit_card_assign_copy")
    else:
        fails.append("unit_card_assign_copy")

    card_assign_path = (
        "_open_unit_design_assign_picker" in ren
        and "_apply_unit_design_assign" in ren
        and UNIT_CARD_ASSIGN_BTN in ren
        and "assign_mode = true" in ren
    )
    wiring["unit_card_assign_mode"] = card_assign_path
    if card_assign_path:
        passes.append("unit_card_assign_mode")
    else:
        fails.append("unit_card_assign_mode")

    # Chip/pin refresh after assign (visual_archetype may change).
    apply_fn = _gd_func_slice(ren, "_apply_unit_design_assign")
    assign_refresh = bool(apply_fn) and (
        "_refresh_selected_unit_chip" in apply_fn
        and "_update_unit_icons_for_pids" in apply_fn
    )
    wiring["unit_card_assign_refreshes_pin"] = assign_refresh
    if assign_refresh:
        passes.append("unit_card_assign_refreshes_pin")
    else:
        fails.append("unit_card_assign_refreshes_pin")

    # 11) DesignPickerPopup: assign_mode skips RetoolingWarningPopup + factory_can_build.
    picker = DESIGN_PICKER.read_text(encoding="utf-8") if DESIGN_PICKER.is_file() else ""
    picker_fn = _gd_func_slice(picker, "_on_confirm_pressed") if picker else ""
    sel_fn = _gd_func_slice(picker, "_is_design_selectable") if picker else ""
    fac_fn = _gd_func_slice(picker, "_factory_allows_design") if picker else ""
    assign_skip_retool = bool(picker_fn) and (
        "_is_assign_mode" in picker
        and "var assign_mode" in picker
        and "RetoolingWarningPopup" in picker_fn
        and (
            "design_chosen" in picker_fn
            or "assign_callback" in picker_fn
            or "assign_callback" in picker
        )
        and ("return" in picker_fn)
        and picker_fn.find("_is_assign_mode") < picker_fn.find("RetoolingWarningPopup")
    )
    wiring["design_picker_assign_skips_retool"] = assign_skip_retool
    if assign_skip_retool:
        passes.append("design_picker_assign_skips_retool")
    else:
        fails.append("design_picker_assign_skips_retool")

    # Selectability short-circuit: assign mode must not call factory_can_build_design.
    assign_selectable = bool(sel_fn) and (
        "_is_assign_mode" in sel_fn
        and "country_may_use_design" in sel_fn
        and sel_fn.find("_is_assign_mode") < sel_fn.find("is_design_factory_compatible")
        and "factory_can_build_design" not in sel_fn
    )
    wiring["design_picker_assign_selectable"] = assign_selectable
    if assign_selectable:
        passes.append("design_picker_assign_selectable")
    else:
        fails.append("design_picker_assign_selectable")

    fac_assign_bypass = bool(fac_fn) and (
        "_is_assign_mode" in fac_fn
        and fac_fn.find("_is_assign_mode") < fac_fn.find("factory_can_build_design")
    )
    wiring["design_picker_factory_allows_assign_bypass"] = fac_assign_bypass
    if fac_assign_bypass:
        passes.append("design_picker_factory_allows_assign_bypass")
    else:
        fails.append("design_picker_factory_allows_assign_bypass")

    # Assign mode predicate is explicit flag, not bare factory_id==0.
    assign_flag_only = bool(picker) and (
        "return assign_mode" in picker
        or ("return assign_mode" in _gd_func_slice(picker, "_is_assign_mode"))
    )
    wiring["design_picker_assign_flag_only"] = assign_flag_only
    if assign_flag_only:
        passes.append("design_picker_assign_flag_only")
    else:
        fails.append("design_picker_assign_flag_only")

    if not check_wiring:
        # Format-only mode still reports integrity strings.
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
        "unit_card_assign_copy": UNIT_CARD_ASSIGN_COPY,
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
            "MapRenderer _show_unit_detail_popup",
            "DesignPickerPopup assign mode",
        ],
        "policy": (
            "pin_first_hit_disk_48_floor_20_selected_chip_no_inspector"
            "; chip_match_station_province_one_pin_per_hex"
            "; unit_card_template_stockpile_assign_no_factory_retool"
        ),
    }


def unit_centric_pick_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_centric_pick_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
