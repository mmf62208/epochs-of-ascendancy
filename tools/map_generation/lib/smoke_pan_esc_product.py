"""Smoke walls: left-drag pans (release skip-pick) + idle Esc → Command Center.

Play short-smoke MIXED (5c8e0f2 / b11cb4e / cf95762 / 51dc2a4): sea left-drag
picked “Rio Grande Rise” (camera moved, then leftover/release selected sea).
Esc dismiss-then-CC and unit-chip Fill%/TOE stay PASS — do not reintroduce
the PR 16 `_ensure_left_drag_armed_from_physical` / `_left_pick_allowed_on_release`
stack.
Pure wiring product — no dual packages.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TOP_INFO = ROOT / "scripts" / "ui" / "TopInfoBar.gd"


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


def build_smoke_pan_esc_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    top = TOP_INFO.read_text(encoding="utf-8") if TOP_INFO.is_file() else ""
    if not ren:
        fails.append("missing_map_renderer")
    if not top:
        fails.append("missing_top_info_bar")

    input_i = ren.find("func _input")
    unh_i = ren.find("func _unhandled_input")
    input_fn = ren[input_i:unh_i] if input_i >= 0 and unh_i > input_i else ""
    unh_fn = _gd_func_slice(ren, "_unhandled_input")
    prov_fn = _gd_func_slice(ren, "_on_province_input")
    cam_fn = _gd_func_slice(ren, "_handle_camera_input")
    process_fn = _gd_func_slice(ren, "_process")
    skip_fn = _gd_func_slice(ren, "_left_release_must_skip_pick")
    pan_fn = _gd_func_slice(ren, "_left_drag_should_pan")
    activate_fn = _gd_func_slice(ren, "_activate_left_drag_pan_from_slop")
    unlock_drag_fn = _gd_func_slice(ren, "_unlock_close_camera_for_left_drag_pan")
    begin_fn = _gd_func_slice(ren, "_begin_left_map_gesture")
    allow_fn = _gd_func_slice(ren, "_allow_left_pan_skip_to_die")
    rearm_fn = _gd_func_slice(ren, "_rearm_left_drag_for_next_press")
    live_fn = _gd_func_slice(ren, "_left_live_slop_is_drag")
    exceeded_fn = _gd_func_slice(ren, "_left_drag_exceeded_slop")
    blocked_fn = _gd_func_slice(ren, "_left_map_pick_blocked")
    esc_fn = _gd_func_slice(ren, "_handle_escape_key")
    open_fn = _gd_func_slice(ren, "_esc_open_command_center")
    dismiss_fn = _gd_func_slice(ren, "_dismiss_map_overlays_esc")
    stack_fn = _gd_func_slice(ren, "_inspector_stack_blocking_input")
    coarse_fn = _gd_func_slice(ren, "_show_coarse_territory_info")
    title_fn = _gd_func_slice(ren, "_try_living_title_map_pick")

    if check_wiring:
        wiring["release_skip_pick_helper"] = (
            bool(skip_fn)
            and "_left_map_pick_blocked" in skip_fn
            and "_left_gesture_dragged" in skip_fn
            and "_left_max_slop_sq" in skip_fn
            and "_note_left_gesture_motion" not in skip_fn
        )
        wiring["pan_from_slop_helper"] = (
            bool(pan_fn)
            and "_left_pan_armed" in pan_fn
            and "_left_btn_down" in pan_fn
            and "is_mouse_button_pressed" in pan_fn
            and "_left_drag_exceeded_slop" in pan_fn
        )
        wiring["area2d_never_pick_on_press"] = (
            bool(prov_fn)
            and "_left_release_must_skip_pick" in prov_fn
            and "if event.pressed:" in prov_fn
            and prov_fn.find("if event.pressed:") < prov_fn.find("_left_release_must_skip_pick")
            and prov_fn.find("if event.pressed:") < prov_fn.find("_select_province")
        )
        wiring["unhandled_release_skip_and_block"] = (
            "_left_release_must_skip_pick" in unh_fn
            and "did_left_pan" in unh_fn
            and "_mark_left_pan_blocked_pick" in unh_fn
            and "_center_camera_on_province" in unh_fn
            and unh_fn.rfind("_left_release_must_skip_pick")
            < unh_fn.rfind("_center_camera_on_province")
        )
        wiring["coarse_and_title_honor_skip"] = (
            "_left_release_must_skip_pick" in coarse_fn
            and "_left_release_must_skip_pick" in title_fn
        )
        wiring["camera_slop_before_modal"] = (
            bool(cam_fn)
            and "_accumulate_left_drag_slop" in cam_fn
            and "_left_drag_should_pan" in cam_fn
            and cam_fn.find("_accumulate_left_drag_slop")
            < cam_fn.find("modal_blocks_map_nav")
        )
        wiring["input_motion_pans_from_slop"] = (
            "_left_drag_should_pan" in input_fn and "_left_pan_active" in input_fn
        )
        wiring["empty_area_process_armed_to_camera"] = (
            bool(process_fn)
            and "_accumulate_left_drag_slop" in process_fn
            and "_left_drag_should_pan" in activate_fn
            and "_left_drag_should_pan" in process_fn
            and "_activate_left_drag_pan_from_slop" in process_fn
            and "_left_pan_active" in process_fn
            and process_fn.find("_left_drag_should_pan")
            < process_fn.find("_handle_camera_input")
            and process_fn.find("_activate_left_drag_pan_from_slop")
            < process_fn.find("_handle_camera_input")
            and process_fn.find("_handle_camera_input")
            < process_fn.find("_reassert_locked_close_camera")
            and "if not _left_pan_active" in process_fn
            and bool(cam_fn)
            and "cam.global_position" in cam_fn
            and "_left_pan_active" in cam_fn
            and "_unlock_close_camera_for_left_drag_pan" in cam_fn
            and "_close_release_seen" in cam_fn
            and bool(unlock_drag_fn)
            and "_unlock_close_camera" in unlock_drag_fn
            and "_close_suppress_edge" not in unlock_drag_fn
            and input_fn.find("_finish_close_click_guard_on_new_press")
            < input_fn.find("_left_map_pick_blocked")
            and "_arm_left_map_press" in unh_fn
            and unh_fn.find("if event.pressed and _close_click_guard")
            < unh_fn.find(
                "_arm_left_map_press",
                max(0, unh_fn.find("if event.pressed and _close_click_guard")),
            )
            and "_close_release_seen" in esc_fn
        )
        wiring["esc_chain_in_input"] = (
            "KEY_ESCAPE" in input_fn
            and "_handle_escape_key" in input_fn
            and input_fn.find("KEY_ESCAPE") < input_fn.find("MOUSE_BUTTON_LEFT")
        )
        wiring["esc_idle_calls_menu"] = (
            bool(esc_fn)
            and "_dismiss_map_overlays_esc" in esc_fn
            and "_esc_open_command_center" in esc_fn
            and "_on_menu_pressed" in open_fn
            and "TopInfoBar.find_in_tree" in open_fn
        )
        wiring["dismiss_no_mainmenu_leftover"] = (
            bool(dismiss_fn)
            and '"MainMenu"' not in dismiss_fn
            and "_overlay_node_is_up" in dismiss_fn
            and "_overlay_node_is_up" in stack_fn
        )
        wiring["topbar_uses_esc_chain"] = (
            "_handle_escape_key" in top and "_on_menu_pressed" in top
        )
        # cf95762 residual: skip-pick on committed slop/pan (no sea pick path)
        # and re-arm so 2nd/3rd empty-area drags pan after release.
        wiring["drag_skip_pick_live_slop"] = (
            bool(live_fn)
            and "_note_left_gesture_motion" not in live_fn
            and "_begin_left_map_gesture" not in live_fn
            and "_left_live_slop_is_drag" in skip_fn
            and "_left_live_slop_is_drag" in blocked_fn
            and "_left_live_slop_is_drag" in exceeded_fn
            and exceeded_fn.find("_left_live_slop_is_drag")
            < exceeded_fn.find("_note_left_gesture_motion")
            and "_mark_left_pan_blocked_pick" in activate_fn
            and "_left_release_must_skip_pick" in unh_fn
            and unh_fn.rfind("_left_release_must_skip_pick")
            < unh_fn.rfind("_select_province")
            and unh_fn.rfind("_left_release_must_skip_pick")
            < unh_fn.rfind("_center_camera_on_province")
            and "_note_left_gesture_motion" not in skip_fn
        )
        wiring["repeat_empty_drag_rearm"] = (
            bool(begin_fn)
            and "genuine_new_press" in begin_fn
            and "_left_button_was_up" in begin_fn
            and "physically_down" in begin_fn
            and bool(rearm_fn)
            and "_left_pan_armed" in rearm_fn
            and "_left_ready_for_still_click" in rearm_fn
            and "_left_skip_next_pick = false" not in rearm_fn
            and "_left_cam_moved_this_down = false" not in rearm_fn
            and "_left_gesture_dragged = false" not in rearm_fn
            and "_left_skip_next_pick = false" in begin_fn
            and bool(allow_fn)
            and "_rearm_left_drag_for_next_press" in allow_fn
            and "_left_in_leftover_hold" in allow_fn
            and allow_fn.find("_left_in_leftover_hold")
            < allow_fn.find("_rearm_left_drag_for_next_press")
            and "_left_drag_should_pan" in process_fn
            and "_activate_left_drag_pan_from_slop" in process_fn
        )
        # 51dc2a4 / cf95762: empty-area drag must skip sea pick on press+release
        # (1st–3rd). Latch skip across leftover re-arm; leftover hold is not a
        # genuine new press. Do not reintroduce the PR 16 process/pick helpers.
        wiring["empty_drag_skip_pick_latch"] = (
            bool(rearm_fn)
            and "_left_skip_next_pick = false" not in rearm_fn
            and "_left_cam_moved_this_down = false" not in rearm_fn
            and "_left_gesture_dragged = false" not in rearm_fn
            and "_left_pan_committed = false" not in rearm_fn
            and "genuine_new_press: bool =" in begin_fn
            and "not _left_in_leftover_hold()" in begin_fn
            and begin_fn.find("genuine_new_press")
            < begin_fn.find("not _left_in_leftover_hold()")
            and "_left_skip_next_pick = false" in begin_fn
            and "func _ensure_left_drag_armed_from_physical" not in ren
            and "func _left_pick_allowed_on_release" not in ren
            and "_ensure_left_drag_armed_from_physical" not in process_fn
            and "_left_pick_allowed_on_release" not in prov_fn
            and "_left_pick_allowed_on_release" not in unh_fn
            and bool(prov_fn)
            and "if event.pressed:" in prov_fn
            and prov_fn.find("if event.pressed:") < prov_fn.find("_select_province")
            and prov_fn.find("if event.pressed:")
            < prov_fn.find("_left_release_must_skip_pick")
            and "_left_release_must_skip_pick" in unh_fn
            and unh_fn.rfind("_left_release_must_skip_pick")
            < unh_fn.rfind("_select_province")
            and bool(activate_fn)
            and "_left_origin_screen" in activate_fn
            and activate_fn.find("_left_origin_screen")
            < activate_fn.find("get_mouse_position")
        )

        for k, v in wiring.items():
            if v:
                passes.append("wire_%s" % k)
            else:
                fails.append("wire_%s" % k)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "Smoke pan+Esc walls · %s" % ("PASS" if ok else "FAIL"),
        "integration": [
            "smoke_pan_esc_product",
            "MapRenderer._left_release_must_skip_pick",
            "MapRenderer._handle_escape_key",
            "TopInfoBar._on_menu_pressed",
        ],
    }


def smoke_pan_esc_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_smoke_pan_esc_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
