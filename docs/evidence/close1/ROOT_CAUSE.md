# CLOSE-1 root cause

Play live `9c9c5f20` incidents 19:35:44 / 20:04:17; `97d6ea45` check 5; Play MIXED `ce5d3304` (RESULT.md + `edge_pan_results.txt`).

## What still PASSes (do not regress)

After unit-card Close, mid-map first-move toward the top bar is camera-delta 0 (`_close_ignore_stale_left_down` / `_consume_close_press_left_gesture`). UI-1 no click-through, CRASH-1 Halt (exactly one `card_release_eaten`), and normal mid-map drag pans.

## Play MIXED `ce5d3304` check #2 only

1. **z≈0.32 RUNAWAY** (`EDGE032b_try1`): first top-edge pans but **uncalamped** — dy≈−14409, cam to cy≈−12384, 100+ camjumps. `_clamp_camera_to_theater` early-returned while `_camera_is_held()`.
2. **z≈0.80 FAIL_NO_PAN** (`EDGE080_try1`): first try `edgepan=0 dy=0`; try2 / after empty drag still dy=0; **EDGE080_baseline without Close PASS** dy=−528.

## Verified writers

### Runaway — `MapRenderer._clamp_camera_to_theater` / `_handle_camera_input` / `_camera_is_held`

First-edge after Close called `_unlock_close_camera()` (clears `_close_camera_locked`) but **kept `_close_click_guard`**. `_camera_is_held()` is true when `_close_click_guard` or hold / pick-block timers are set, so `_clamp_camera_to_theater` returned without `_apply_camera_bounds`. Edge speed 2600 / zoom 0.32 ≈ 8125 u/s flew off the world AABB (`WORLD_CANONICAL` min centre y≈1156 at 1280×740). WASD already cleared hold timers + unlocked before moving; first-edge did not.

`_input` on unit-card `BtnClose` also called `_dismiss_inspector_and_restore_input` (`_mouse_over_close_control` matches any BtnClose). That path `_lock_close_camera` + `_hold_camera_now` + 800ms pick-block, which is the HUD Close lock, not the docked card at y≈551.

### No-pan — `_lock_close_camera` + `MapViewInput` sticky hover

`_lock_close_camera` forced `_close_suppress_edge = true`. If Close then jumps to y=0 without an intermediate frame below the 6px strip, suppress never clears and `_handle_camera_input` zeros `move_dir` (or never queries `edge_pan_direction_screen` → `edgepan=0`). A just-Closed `UnitDetailPopup` (hidden / IGNORE / queued) can remain `gui_get_hovered_control()`, so `control_or_ancestor_blocks_edge_pan` / `non_topbar_overlay_contains_mouse` return true at the north rim while baseline (no Close) is TopInfoBar-exempt and pans.

CRASH-1 `card_press_armed` / `card_release_eaten` is a different latch and was not the writer.

## FIX #1

- `_clamp_camera_to_theater` skips **only** while `_close_camera_locked`. Click-through / hold timers never skip theater clamp.
- First edge / WASD call `_clear_camera_hold_timers_for_nav`. `_close_click_guard` / `_left_skip_next_pick` stay so Close release cannot pick (UI-1).
- `_input` / `_unhandled_input` route unit-card Close through `_dismiss_unit_card_restore_province`.
- `_lock_close_camera` sets `_close_suppress_edge` only for the true 6px north strip.
- `MapViewInput` ignores a dead/hidden unit-card hover so first top-edge is not `edge_dir=0`.

`_close_ignore_stale_left_down` / `_consume_close_press_left_gesture` unchanged. FLEET-1 / FLEET-2 / MV-1 / MV-1b pick rules **unedited**.

## Guard / check (not live Play)

See `GUARD.md` / `CLICKS.md` / `KEEP_GREEN.md`.
