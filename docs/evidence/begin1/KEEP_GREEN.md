# BEGIN-1 keep-green (isolated)

Headless / xvfb ≠ live Play. Never `EOA_SKIP_TITLE`.
Code SHA `f18a341a`. Later commits are test / docs only.

| gate | kind | expected |
|---|---|---|
| `HeadlessBegin1TitleReleaseFallthroughTest` | hd+xvfb | PASS — T1 real-pipeline 80 ms leftover no pick; T2 later click picks; T3 poll expiry then first click picks; T4 same-frame 900 ms release N+2 swallowed; T5(b) poll + outside-button M3; keyboard Enter/Space |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS — TipDismiss × still swallows |
| `HeadlessIx1LivingTitleEscBeginTest` | hd | PASS — Begin PRESS + Esc/CC routing |
| `HeadlessFleet1LandSpillGateTest` | hd | PASS |
| `HeadlessFleet2SharedSeaMarkerTest` | hd | PASS |
| `HeadlessFac1aPanIconsTest` | hd | PASS |
| `HeadlessFac1aHoverCacheTest` | hd | PASS |
| `HeadlessLabel1NationZoomTest` | hd | PASS |
| `tools/eoa_full_test_gates.sh --quick` | pure | same known 14 `unit_board_play_path` reds as main; no new red |

Pre-step: `timeout 1500 tools/run_godot.sh --headless --path . --import --quit`

Fences: FacilityIconLayer, MapZoomLOD / political labels, unit pick /
draw-order / spill, fleet stack layout, camera, edge-pan **unedited**.
