# BEGIN-1 keep-green (isolated)

Headless / xvfb ≠ live Play. Never `EOA_SKIP_TITLE`.

| gate | kind | expected |
|---|---|---|
| `HeadlessBegin1TitleReleaseFallthroughTest` | hd+xvfb | PASS — 80 ms leftover no pick / inspect / zoom; follow-up + keyboard-Begin + expiry clicks select via real pick (pid != -1) |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS — TipDismiss × still swallows |
| `HeadlessIx1LivingTitleEscBeginTest` | hd | PASS — Begin PRESS + Esc/CC routing |
| `tools/eoa_full_test_gates.sh --quick` | pure | same known `unit_board_play_path` reds as main; no new red |

Fences: FacilityIconLayer, MapZoomLOD / political labels, unit pick /
draw-order / spill, fleet stack layout, camera, edge-pan **unedited**.
