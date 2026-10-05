# CLOSE-1b root cause

Play live PASS (soft) on CLOSE-1 tip `008e5c30` / main `3276be5d`. 3 of 11 Close→first-top-edge cycles: `edgepan≥2` but `dy=0.0` / `cam0==cam1` (EDGE032_c8 z≈0.32; EDGE080_c1 / c4 z≈0.80). Retry later panned without an empty drag. Not MIXED `ce5d3304` empty-drag / runaway.

## Verified writers

1. **`_close_click_is_north_edge_strip` mouse fallback.** When the unit card is already hidden, the helper used `get_viewport().get_mouse_position()`. Headless warp and a fast first push leave that at **y=0**, so `_consume_close_press_left_gesture` / `_lock_close_camera` latched `_close_suppress_edge = true` even though Close was the docked card at ~y=551.

2. **Suppress sticks for the whole rim hold.** `_handle_camera_input` only clears `_close_suppress_edge` when the cursor *leaves* the 6px strip. A first top-edge push stays on the rim, so `edge_dir` is never applied. A logging patch that still queries `edge_pan_direction_screen` reports `edgepan≥2` with `dy=0`.

3. **Same-frame GIS reassert.** `_process` runs `_reassert_locked_close_camera()` *after* `_handle_camera_input` when `_left_pan_active` is false. If a later inspector-dismiss path locked GIS, any delta is snapped back (`cam0==cam1`).

4. **Why CLOSE-1 guards missed it.** Windowed trials always first-moved to **y=20** (clears suppress) then held the rim. Headless first-edge force-cleared `_close_camera_locked` and did not inject leftover suppress.

Unit-card `_close_suppress_edge = false` is not enough: a later `_lock_close_camera` / `_consume` with a dead card + mouse already at y=0 re-sets suppress.

## FIX (CLOSE-1b)

- Close-in-strip is the **button centre only** (unit card or inspector). No mouse fallback when the button is gone.
- `_close_click_was_north_strip` records that. First edge clears suppress unless the Close *was* on the 6px rim (Greenland leftover kept).
- `_process` skips GIS reassert while a mid-panel Close + north-rim cursor wants to pan.
- MapViewInput chrome fallback does not treat an unsettled InfoPanel rect as covering y=0.

`_close_ignore_stale_left_down` / `_consume_close_press_left_gesture` / FIX #1 clamp-only-while-GIS-locked / unit-card Close not via HUD lock / dying-card hover ignore **kept**.

xvfb / headless ≠ live Play.
