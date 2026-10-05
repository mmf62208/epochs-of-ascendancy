# CLOSE-1 root cause

Play live `9c9c5f20` incidents 19:35:44 and 20:04:17; `97d6ea45` check 5.

## What happened

After pressing a unit card **Close** at screen ~(304, 551) on 1280×740, the next mouse move to the top bar panned the camera at `middle_mouse_pan_speed` (1.2) × delta / zoom. Both jumps shared the same screen delta. First top-edge pan after Close did nothing until one empty drag.

## Verified cause (not only the UI-1 hunch)

1. `MapRenderer._input` on left-press always calls `_begin_left_map_gesture(true)` **before** the Close path. That sets `_left_btn_down = true`.
2. Close is `ACTION_MODE_BUTTON_PRESS`. `_dismiss_inspector_and_restore_input` (when `_mouse_over_close_control` hits) used to `_reset_left_gesture_state()` then **re-arm** `_left_btn_down = true` because `Input.is_mouse_button_pressed(LEFT)` was still true.
3. The card is hidden / `queue_free()`d while the button is still down. The matching release is often lost (GUI capture dies with the card; Input singleton can stay stale — same class as the CC-dimmer swallowed `_end`).
4. `_process` / `_input` `InputEventMouseMotion` / `_left_drag_should_pan` still saw `_left_btn_down` or leftover Input-down. The next move exceeded 8px slop and applied `cam.global_position -= drag_delta * 1.2 / zoom`.
5. `_lock_close_camera` also set `_close_camera_locked` + `_close_click_guard` + `_close_suppress_edge`. `_handle_camera_input` refused edge pan until an empty drag called `_unlock_close_camera_for_left_drag_pan`. Unit-card Close at y≈551 is **not** in the 6px north strip.

CRASH-1 `card_press_armed` / `card_release_eaten` is a different latch (Halt / Press / Hold / Withdraw / Assign) and was not the writer.

## Fix

`_consume_close_press_left_gesture` on inspector Close and unit-card Close: reset press/drag, skip-pick the matching release, set `_close_ignore_stale_left_down`, set `_close_suppress_edge` only if Close is in the 6px north strip. First edge after Close unlocks the GIS lock without dropping the click-through skip-pick.

UI-1 no-click-through, CRASH-1 latches, Halt-march, and normal map drags unchanged.
