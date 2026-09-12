"""Smoke walls: left-drag pans (release skip-pick) + idle Esc → Command Center.

Play short-smoke MIXED (5c8e0f2 / b11cb4e / cf95762 / 51dc2a4 / eed9b5f /
a16ee8e / 47af97a): sea left-drag picked “Rio Grande Rise” / Drag2 “Labrador
Approaches West” / Drag2 “MAR North” (`_unhandled_input` spatial
`_select_province` or hover glance — not Area2D / coarse / title). Mid-gesture
left-down + live slop ≥8px latches `_left_skip_next_pick` before `_note`
(PR 22 — keep). a16ee8e Drag1–3 empty-area left-drags never moved the camera:
`_activate` must origin-seed `_last_mouse_pos` from the press origin captured
*before* `_left_drag_should_pan` / `_note` can reset it (PR 23 — keep).
47af97a Drag1–3 still never moved after Esc-then-CC: idle `_allow` must
unstick leftover `_left_btn_down` on physical button-up so the next
`_begin(true)` can genuine-reset origin (CC dimmer / swallowed release never
`_end`). 1f48f56 Drag1 move OK / Drag2+3 no camera move: leftover hold
blocks `genuine_new_press`, so `_input` reseeds origin after idle button-up
without clearing skip/cam (not PR 24 ungated `_begin` seed; not PR 26
chip / idle-stuck `_begin` seed). 650c85c-cc MIXED: Drag1–3 no camera
move after Esc→CC — leftover stuck `_left_btn_down` first-line-blocked
`_begin(true)`; idle `_allow` now unsticks btn-down during leftover hold
(no `_rearm`); `_input` reseeds on idle-up `event.pressed` (Input
singleton can stay stale after CC dimmer). Closing MainMenu must not
`modal_blocks_map_nav`. e611e7a MIXED: Drag1+3 move / first Drag2
clamp no move — leftover pressed=true can consume idle-up reseed so
`_activate` origin-seeds Drag1 and the first apply jump-clamps.
`_input` reseeds while leftover hold even if was_up was consumed;
`_activate` uses current mouse when leftover origin is far (keep PR 23
near-origin seed). Esc dismiss-then-CC and unit-chip
Fill%/TOE stay PASS — do not reintroduce the PR 16
`_ensure_left_drag_armed_from_physical` / `_left_pick_allowed_on_release`
stack.
Pure wiring product — no dual packages.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
MAP_VIEW = ROOT / "scripts" / "map" / "MapViewInput.gd"
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
    view = MAP_VIEW.read_text(encoding="utf-8") if MAP_VIEW.is_file() else ""
    top = TOP_INFO.read_text(encoding="utf-8") if TOP_INFO.is_file() else ""
    if not ren:
        fails.append("missing_map_renderer")
    if not view:
        fails.append("missing_map_view_input")
    if not top:
        fails.append("missing_top_info_bar")

    input_i = ren.find("func _input")
    unh_i = ren.find("func _unhandled_input")
    input_fn = ren[input_i:unh_i] if input_i >= 0 and unh_i > input_i else ""
    unh_fn = _gd_func_slice(ren, "_unhandled_input")
    prov_fn = _gd_func_slice(ren, "_on_province_input")
    cam_fn = _gd_func_slice(ren, "_handle_camera_input")
    process_fn = _gd_func_slice(ren, "_process")
    hover_fn = _gd_func_slice(ren, "_update_spatial_hover")
    skip_fn = _gd_func_slice(ren, "_left_release_must_skip_pick")
    pan_fn = _gd_func_slice(ren, "_left_drag_should_pan")
    activate_fn = _gd_func_slice(ren, "_activate_left_drag_pan_from_slop")
    unlock_drag_fn = _gd_func_slice(ren, "_unlock_close_camera_for_left_drag_pan")
    begin_fn = _gd_func_slice(ren, "_begin_left_map_gesture")
    allow_fn = _gd_func_slice(ren, "_allow_left_pan_skip_to_die")
    rearm_fn = _gd_func_slice(ren, "_rearm_left_drag_for_next_press")
    live_fn = _gd_func_slice(ren, "_left_live_slop_is_drag")
    latch_fn = _gd_func_slice(ren, "_latch_left_skip_pick_from_live_slop")
    reseed_fn = _gd_func_slice(ren, "_reseed_left_origin_from_idle_up")
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
        settle_btn_fn = _gd_func_slice(ren, "_ensure_settle_button")
        agent_path = ROOT / "scripts" / "ui" / "AgentAssignmentScreen.gd"
        agent_src = agent_path.read_text(encoding="utf-8") if agent_path.is_file() else ""
        agent_rel_fn = _gd_func_slice(agent_src, "_on_portrait_file_dialog_released")
        # Play ff63a46 HARD FAIL: settle dismissed, Command Center did not open.
        # 1st Esc closes settle/inspector; idle Esc opens CC via deferred _on_menu_pressed.
        wiring["esc_dismiss_then_idle_cc"] = (
            bool(esc_fn)
            and "_esc_stack_frame" in esc_fn
            and "get_process_frames" in esc_fn
            and esc_fn.find("_esc_stack_frame") < esc_fn.find("_inspector_stack_blocking_input")
            and esc_fn.find("if _dismiss_map_overlays_esc()")
            < esc_fn.find("_esc_open_command_center")
            and "return" in esc_fn[esc_fn.find("if _dismiss_map_overlays_esc()") : esc_fn.find("_esc_open_command_center")]
            and 'call_deferred("_on_menu_pressed")' in open_fn
            and "MainMenuLeftover" in open_fn
            and "queue_free(" not in open_fn
            and "FileDialog" in dismiss_fn
            and "exclusive = false" in dismiss_fn
            and '"MainMenu"' not in dismiss_fn
            and "FOCUS_NONE" in settle_btn_fn
            and "exclusive = false" in agent_rel_fn
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
        # f942ac3 Play: camera moved then sea-picked Tropical Atlantic Waters.
        # Area2D hold + all release pick sites gate skip + live slop only.
        wiring["area2d_hold_release_live_slop"] = (
            bool(prov_fn)
            and "is_mouse_button_pressed" in prov_fn
            and "_left_live_slop_is_drag" in prov_fn
            and "_left_release_must_skip_pick" in prov_fn
            and "if event.pressed:" in prov_fn
            and prov_fn.find("if event.pressed:") < prov_fn.find("_select_province")
            and prov_fn.find("is_mouse_button_pressed") < prov_fn.find("_select_province")
            and prov_fn.find("_left_live_slop_is_drag") < prov_fn.find("_select_province")
            and prov_fn.find("_left_release_must_skip_pick") < prov_fn.find("_select_province")
            and "_left_live_slop_is_drag" in unh_fn
            and unh_fn.rfind("_left_live_slop_is_drag") < unh_fn.rfind("_select_province")
            and unh_fn.rfind("_left_release_must_skip_pick") < unh_fn.rfind("_select_province")
            and "_left_live_slop_is_drag" in coarse_fn
            and "_left_release_must_skip_pick" in coarse_fn
            and "_left_live_slop_is_drag" in title_fn
            and "_left_release_must_skip_pick" in title_fn
            and "func _ensure_left_drag_armed_from_physical" not in ren
            and "func _left_pick_allowed_on_release" not in ren
            and "_ensure_left_drag_armed_from_physical" not in process_fn
            and "_left_pick_allowed_on_release" not in prov_fn
            and "_left_pick_allowed_on_release" not in unh_fn
        )
        # eed9b5f Drag2 Labrador Approaches West: `_unhandled_input` spatial
        # `_select_province` (named sea — not Area2D / coarse / title). Latch
        # skip from live slop mid-gesture before `_note` can reset origin.
        # Do not change rearm/activate/Esc/chip helpers.
        motion_i = input_fn.find("InputEventMouseMotion")
        motion_latch_i = (
            input_fn.find("_latch_left_skip_pick_from_live_slop", motion_i)
            if motion_i >= 0
            else -1
        )
        motion_note_i = (
            input_fn.find("_note_left_gesture_motion", motion_i)
            if motion_i >= 0
            else -1
        )
        wiring["early_live_slop_skip_latch"] = (
            bool(latch_fn)
            and "_left_live_slop_is_drag" in latch_fn
            and "_left_skip_next_pick = true" in latch_fn
            and "_left_skip_next_pick = false" not in latch_fn
            and "_note_left_gesture_motion" not in latch_fn
            and "_begin_left_map_gesture" not in latch_fn
            and "_activate_left_drag_pan_from_slop" not in latch_fn
            and "_rearm_left_drag_for_next_press" not in latch_fn
            and "_mark_left_pan_blocked_pick" not in latch_fn
            and "_allow_left_pan_skip_to_die" not in latch_fn
            and "is_mouse_button_pressed" in latch_fn
            and "_left_btn_down" in latch_fn
            and latch_fn.find("_left_live_slop_is_drag")
            < latch_fn.find("_left_skip_next_pick = true")
            and "_latch_left_skip_pick_from_live_slop" in process_fn
            and process_fn.find("_latch_left_skip_pick_from_live_slop")
            < process_fn.find("_accumulate_left_drag_slop")
            and motion_i >= 0
            and 0 <= motion_latch_i < motion_note_i
            and "_latch_left_skip_pick_from_live_slop" in input_fn
            and input_fn.find("_latch_left_skip_pick_from_live_slop")
            < input_fn.find("_note_left_gesture_motion")
            and "_latch_left_skip_pick_from_live_slop" in unh_fn
            and unh_fn.find("_latch_left_skip_pick_from_live_slop")
            < unh_fn.find("_note_left_gesture_motion")
            and unh_fn.find("_latch_left_skip_pick_from_live_slop")
            < unh_fn.rfind("_select_province")
            and unh_fn.find("_latch_left_skip_pick_from_live_slop")
            < unh_fn.find("_map_click_should_skip_pick")
            and "_left_skip_next_pick = false" not in rearm_fn
            and "_left_origin_screen" in activate_fn
            and "func _ensure_left_drag_armed_from_physical" not in ren
            and "func _left_pick_allowed_on_release" not in ren
            and "func _handle_escape_key" in ren
            and "func _try_open_land_unit_at_world" in ren
            and "func _try_open_unit_at_world" in ren
        )
        # a16ee8e Drag1–3: camera never moved. Origin-seed `_last_mouse_pos`
        # from press origin captured before `_left_drag_should_pan` / `_note`
        # can `_begin`-reset it (current-mouse seed zeroes first delta).
        # Activate only — do not rewrite latch / rearm / Esc / chip / PR 16.
        wiring["drag1_activate_origin_seed"] = (
            bool(activate_fn)
            and "seed_origin" in activate_fn
            and "have_seed_origin" in activate_fn
            and "if not _left_origin_valid:" in activate_fn
            and "_last_mouse_pos = seed_origin" in activate_fn
            and "_last_mouse_pos = _left_origin_screen" in activate_fn
            and activate_fn.find("seed_origin")
            < activate_fn.find("if not _left_drag_should_pan()")
            and activate_fn.find("if not _left_origin_valid:")
            < activate_fn.find("_last_mouse_pos = _left_origin_screen")
            and activate_fn.find("_left_origin_screen")
            < activate_fn.find("get_mouse_position")
            and "_left_press_screen" in activate_fn
            and "_left_sticky_origin" in activate_fn
            and "_left_pan_armed = true" not in activate_fn
            and "_ensure_left_drag_armed_from_physical" not in activate_fn
            and "_left_pick_allowed_on_release" not in activate_fn
            and "_rearm_left_drag_for_next_press" not in activate_fn
            and "_allow_left_pan_skip_to_die" not in activate_fn
            and "_latch_left_skip_pick_from_live_slop" not in activate_fn
            and "_handle_escape_key" not in activate_fn
            and "_try_open_land_unit_at_world" not in activate_fn
            and "_try_open_unit_at_world" not in activate_fn
        )
        # 47af97a Drag1–3: leftover `_left_btn_down` blocked `_begin(true)`
        # origin reset after Esc/CC dimmer (swallowed `_end`). Idle `_allow`
        # unsticks on physical up after leftover-hold; skip/cam stay.
        # Hover glance hidden while left is down + slop/pan/skip (MAR North).
        wiring["empty_drag_unstick_idle_btn_down"] = (
            bool(allow_fn)
            and "stuck_btn_down" in allow_fn
            and "_left_btn_down = false" in allow_fn
            and "_left_button_was_up = true" in allow_fn
            and allow_fn.find("is_mouse_button_pressed")
            < allow_fn.find("stuck_btn_down")
            and allow_fn.find("_left_in_leftover_hold")
            < allow_fn.find("_left_btn_down = false")
            and allow_fn.find("_left_btn_down = false")
            < allow_fn.find("_rearm_left_drag_for_next_press")
            and "_left_skip_next_pick = false" not in allow_fn
            and "_left_cam_moved_this_down = false" not in allow_fn
            and "_left_gesture_dragged = false" not in allow_fn
            and "func _seed_left_origin_for_repeat_press" not in ren
            and "func _seed_left_origin_for_idle_stuck_press" not in ren
            and "func _ensure_left_drag_armed_from_physical" not in ren
            and "func _left_pick_allowed_on_release" not in ren
            and "_try_open_land_chip_from_input" not in allow_fn
            and "_handle_escape_key" not in allow_fn
            and "_try_open_land_unit_at_world" not in allow_fn
            and bool(hover_fn)
            and "_left_live_slop_is_drag" in hover_fn
            and "_left_pan_active" in hover_fn
            and "_left_skip_next_pick" in hover_fn
            and "is_mouse_button_pressed" in hover_fn
            and hover_fn.find("is_mouse_button_pressed")
            < hover_fn.rfind("_clear_hover_state")
            and hover_fn.find("_is_mouse_over_blocking_ui")
            < hover_fn.find("is_mouse_button_pressed")
            and "_try_open_land_unit_at_world" not in hover_fn
            and "_handle_escape_key" not in hover_fn
            and "func _handle_escape_key" in ren
            and "func _try_open_land_unit_at_world" in ren
        )
        # 1f48f56 Drag2+3: leftover hold blocked `_begin(true)` origin reset.
        # `_input` only — capture idle-up *before* `_begin`, then reseed
        # origin/last_mouse/slop. Keep skip/cam. Not PR 24 `_begin` seed.
        left_i = input_fn.find("MOUSE_BUTTON_LEFT")
        idle_up_i = (
            input_fn.find("idle_up_for_repeat", left_i) if left_i >= 0 else -1
        )
        begin_press_i = (
            input_fn.find("_begin_left_map_gesture(true)", left_i)
            if left_i >= 0
            else -1
        )
        reseed_call_i = (
            input_fn.find("_reseed_left_origin_from_idle_up", left_i)
            if left_i >= 0
            else -1
        )
        wiring["drag2_idle_up_origin_reseed"] = (
            bool(reseed_fn)
            and "_left_origin_screen = mouse" in reseed_fn
            and "_last_mouse_pos = mouse" in reseed_fn
            and "_left_max_slop_sq = 0.0" in reseed_fn
            and "_left_button_was_up = false" in reseed_fn
            and "_left_skip_next_pick = false" not in reseed_fn
            and "_left_cam_moved_this_down = false" not in reseed_fn
            and "_left_gesture_dragged = false" not in reseed_fn
            and "_left_pan_committed = false" not in reseed_fn
            and "_handle_escape_key" not in reseed_fn
            and "_try_open_land_unit_at_world" not in reseed_fn
            and "_try_open_unit_at_world" not in reseed_fn
            and "_reseed_left_origin_from_idle_up" not in begin_fn
            and "_reseed_left_origin_from_idle_up" not in activate_fn
            and "_reseed_left_origin_from_idle_up" not in allow_fn
            and "_reseed_left_origin_from_idle_up" not in latch_fn
            and "_reseed_left_origin_from_idle_up" not in process_fn
            and "idle_up_for_repeat" in input_fn
            and left_i >= 0
            and 0 <= idle_up_i < begin_press_i < reseed_call_i
            and input_fn.find("_left_button_was_up") < begin_press_i
            and "func _seed_left_origin_for_repeat_press" not in ren
            and "func _seed_left_origin_for_idle_stuck_press" not in ren
            and "func _ensure_left_drag_armed_from_physical" not in ren
            and "func _left_pick_allowed_on_release" not in ren
            and "func _handle_escape_key" in ren
            and "func _try_open_land_unit_at_world" in ren
        )
        # 650c85c-cc: leftover stuck `_left_btn_down` first-line-blocked
        # `_begin(true)` after Esc→CC / swallowed `_end`. Idle-up new press
        # must fall through; leftover hold unsticks btn-down without `_rearm`;
        # `_input` reseeds on idle-up without Input-singleton gate.
        # Closing MainMenu must not freeze camera apply.
        view_block_fn = _gd_func_slice(view, "_is_visible_blocking_node")
        begin_stuck_i = begin_fn.find("if _left_btn_down")
        begin_idle_i = begin_fn.find("new_press and _left_button_was_up")
        leftover_hold_i = allow_fn.find("if _left_in_leftover_hold()")
        leftover_unstick_i = (
            allow_fn.find("_left_btn_down = false", leftover_hold_i)
            if leftover_hold_i >= 0
            else -1
        )
        leftover_rearm_i = allow_fn.find("_rearm_left_drag_for_next_press")
        reseed_block = ""
        if reseed_call_i >= 0:
            reseed_block = input_fn[max(0, idle_up_i) : reseed_call_i + 80]
        wiring["empty_drag_idle_up_begin_unstick"] = (
            bool(begin_fn)
            and 0 <= begin_stuck_i < begin_idle_i
            and "new_press and _left_button_was_up" in begin_fn
            and leftover_hold_i >= 0
            and leftover_hold_i < leftover_unstick_i < leftover_rearm_i
            and "_left_btn_down = false" in allow_fn[leftover_hold_i:leftover_rearm_i]
            and allow_fn.find("_rearm_left_drag_for_next_press", leftover_hold_i)
            > leftover_unstick_i
            and "idle_up_for_repeat" in input_fn
            and "_reseed_left_origin_from_idle_up" in input_fn
            and "is_mouse_button_pressed" not in reseed_block
            and "_reseed_left_origin_from_idle_up" not in begin_fn
            and "_reseed_left_origin_from_idle_up" not in activate_fn
            and "func _seed_left_origin_for_repeat_press" not in ren
            and "func _ensure_left_drag_armed_from_physical" not in ren
            and "func _left_pick_allowed_on_release" not in ren
            and bool(view_block_fn)
            and '"MainMenu"' in view_block_fn
            and "_closing" in view_block_fn
            and "is_queued_for_deletion" in view_block_fn
            and view_block_fn.find("is_queued_for_deletion")
            < view_block_fn.find("return true")
            and view_block_fn.find("_closing")
            < view_block_fn.find("return true")
            and "_handle_escape_key" not in begin_fn
            and "_try_open_land_unit_at_world" not in begin_fn
            and "func _handle_escape_key" in ren
        )
        # e611e7a first Drag2 clamp: leftover pressed=true consumes idle-up
        # reseed; leftover dragged flags activate immediately with Drag1
        # origin → huge first delta → theater clamp. Reseed on leftover
        # hold too; activate far leftover origin uses current mouse.
        leftover_reseed_i = (
            input_fn.find("_left_in_leftover_hold()", left_i) if left_i >= 0 else -1
        )
        wiring["drag2_stale_origin_no_clamp"] = (
            bool(activate_fn)
            and "leftover_committed" in activate_fn
            and "seed_far" in activate_fn
            and "stale_seed_lim" in activate_fn
            and "mouse_act" in activate_fn
            and "_last_mouse_pos = mouse_act" in activate_fn
            and "_last_mouse_pos = seed_origin" in activate_fn
            and activate_fn.find("leftover_committed")
            < activate_fn.find("_last_mouse_pos = mouse_act")
            < activate_fn.find("_last_mouse_pos = seed_origin")
            and activate_fn.find("seed_far and leftover_committed")
            < activate_fn.find("_last_mouse_pos = mouse_act")
            and "_left_pan_armed = true" not in activate_fn
            and "_ensure_left_drag_armed_from_physical" not in activate_fn
            and "_left_pick_allowed_on_release" not in activate_fn
            and "_rearm_left_drag_for_next_press" not in activate_fn
            and "_allow_left_pan_skip_to_die" not in activate_fn
            and "_reseed_left_origin_from_idle_up" not in activate_fn
            and "_handle_escape_key" not in activate_fn
            and "_try_open_land_unit_at_world" not in activate_fn
            and "_try_open_unit_at_world" not in activate_fn
            and "func _seed_left_origin_for_repeat_press" not in ren
            and "func _ensure_left_drag_armed_from_physical" not in ren
            and "func _left_pick_allowed_on_release" not in ren
            and leftover_reseed_i >= 0
            and idle_up_i >= 0
            and leftover_reseed_i < reseed_call_i
            and "idle_up_for_repeat or _left_in_leftover_hold()" in input_fn
            and "_reseed_left_origin_from_idle_up" not in begin_fn
            and "_reseed_left_origin_from_idle_up" not in process_fn
            and "func _handle_escape_key" in ren
            and "func _try_open_land_unit_at_world" in ren
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
