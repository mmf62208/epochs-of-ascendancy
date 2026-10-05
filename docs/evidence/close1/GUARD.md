# CLOSE-1 headless guard

Tip `4037dac2`. `tools/eoa_close1_guard.sh`. xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

| mode | result | peak RSS MB |
|---|---|---|
| hd | PASS | **1207.6** |
| xvfb | PASS | **1339.0** |

Close via real `BtnClose` (`pressed.emit` after `_input` left-press). Large `InputEventMouseMotion` with and without `button_mask`. Camera unmoved on first move; leftover press/drag cleared; swallowed-release + stale mask ignored; unit-card Close does not set `_close_suppress_edge`; first edge after Close pans north (hd dy=−174.8 / xvfb dy=−1192.7); UI-1 click-through + CRASH-1 latches stay in source; normal map drag still pans.

`EOA_CLOSE1_GUARD RESULT=PASS hd+xvfb`
