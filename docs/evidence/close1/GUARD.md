# CLOSE-1 headless guard (FIX #1)

Tip `1519fe700889e4e132bec5ba70078f474c7d1ee7` (+ windowed recenter `5ad300e3`). `tools/eoa_close1_guard.sh`. xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

| mode | result | peak RSS MB |
|---|---|---|
| hd | PASS | **1204.3** |
| xvfb | PASS | **1339.1** |

Close via real `BtnClose`. Mid-map first-move camera_delta=0 with and without leftover mask; swallowed-release ignored; no click-through; `_close_suppress_edge` off after unit-card Close. First edge pans (hd dy=−206.8 / xvfb dy=−1192.7). First edge with leftover `_close_click_guard` + hold timers **clamps** (dy=−143.8 cy=1156.2 = `_apply_camera_bounds`). `_clamp_camera_to_theater` while guard set pulls cy=−20000 → 1156.2. Normal map drag still pans. UI-1 / CRASH-1 source needles kept.

`EOA_CLOSE1_GUARD RESULT=PASS hd+xvfb`
