# SHIP_STATUS CLOSE-1b

**HOLD merge.** Do not merge. xvfb / headless ≠ live Play.

| | |
|---|---|
| Branch | `cursor/close1b-first-edge-dy0-017a` |
| Tip | `46a160f07816114fffaf6862270ad2a2409edfc8` |
| Code | `d293f5da` (needle + leftover ticks) on `32b5c17f` / main `3276be5d` (CLOSE-1 KEEP == PASS tip `008e5c30`) |
| PR | https://github.com/mmf62208/epochs-of-ascendancy/pull/72 (draft) |

## Symptom (Play soft on `008e5c30`)

3/11 Close→first-top-edge: `edgepan≥2` but `dy=0` / cam0==cam1 (EDGE032_c8 z≈0.32; EDGE080_c1 / c4 z≈0.80). Retry later panned. Not MIXED `ce5d3304`.

## Root

`_close_click_is_north_edge_strip` fell back to viewport mouse at y=0 after the card hid → latched `_close_suppress_edge`. First rim hold never left the 6px strip so suppress never cleared (logs still count edgepan). `_process` GIS reassert after `_handle_camera_input` snapped any delta. CLOSE-1 windowed y=20 first-move hid it.

## Fix

Button-only strip + `_close_click_was_north_strip`. First edge after a mid-panel Close pans and skips same-frame reassert. HUD rim Close still suppresses (Greenland leftover). CLOSE-1 consume / FIX #1 clamp / unit-card not via HUD lock **kept**.

## Guards (NOT live Play)

| gate | result | RSS MB |
|---|---|---|
| CLOSE-1b hd / xvfb | PASS leftover 11/11 | **1209.3 / 1348.0** |
| Windowed 1280×740 GER Home | first_move **20/20** · first_edge **20/20** · first_edge_direct **16/16** (z0.32 cam_y≈1076 / z0.80=382.5) | counts isolated |
| Isolated keep-green | **FAILS=0** | see `docs/evidence/close1b/KEEP_GREEN.md` |

xvfb / headless ≠ live Play. Never claim live Play PASS.
