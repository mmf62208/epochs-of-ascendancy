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
HIT_RADIUS_PX = 48.0
HIT_RADIUS_FLOOR = 20.0


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
