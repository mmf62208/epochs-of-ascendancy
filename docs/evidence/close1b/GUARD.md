# CLOSE-1b guard

Tip `d293f5daf3549eb3da90e7622a5054ed109066b9` (parent `32b5c17f`). `tools/eoa_close1_guard.sh`. xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

| mode | result | peak RSS MB |
|---|---|---|
| hd | PASS | **1209.3** |
| xvfb | PASS | **1348.0** |

CLOSE-1 cases kept: Close via real `BtnClose`; mid-map first-move camera_delta=0 with and without leftover mask; swallowed-release ignored; no click-through; `_close_suppress_edge` off after unit-card Close. First edge pans (hd dy=−175.6 / xvfb dy=−1192.7). First edge with leftover `_close_click_guard` + hold timers **clamps** (dy=−143.8 cy=1156.2). `_clamp_camera_to_theater` while guard set pulls cy=−20000 → 1156.2. Normal map drag still pans.

CLOSE-1b needles:

- Close strip ignores stale/warped mouse at y=0 (button-only; no viewport fallback).
- Leftover suppress+GIS+guard+hold, `_close_click_was_north_strip=false`, immediate TOP_BAR: **11/11** pans+clamps at z0.32 / z0.80 (no y=20 first).
- HUD Close that *was* on the 6px rim still suppresses (Greenland leftover).

`EOA_CLOSE1_GUARD RESULT=PASS hd+xvfb`

Windowed xvfb 1280×740 GER Europe Home (`tools/eoa_close1_windowed_check.sh`): **first_move 20/20 · first_edge 20/20 · first_edge_direct 16/16**. Direct trials are Close→immediate y=0 (no y=20 first-move); half inject leftover suppress+GIS. z0.32 clamp cam_y≈1076; z0.80 cam_y≈382.5. See `CLICKS.md`. Wrapper RSS overlapped a parallel HD keep-green job and is not an isolated peak.

xvfb / headless ≠ live Play.
