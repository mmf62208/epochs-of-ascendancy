# PERF-1b isolated keep-green

Stacked on PERF-1 FIX #1 tip `0d8e2cff` (PR #80). This tip after hover-cache
guards. FAILS=0 on the listed Godot slice. KEEP_GREEN_RESULT=PASS.
xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only
(Godot 4.7.1-rc2).

Fences kept: chip draw-order / hit ranking **unedited**. TipDismiss **unedited**.
ORDERS card **unedited**. Camera / edge-pan **unedited**. No new systems.

**Verdict: isolated keep-green PASS** (required slice). Official `--quick`
`unit_board_play_path` (fill-toe / unit_pick / living_unit wiring) and `map_qc`
(Pillow missing in this env) stay red on main `d008ca42` — pre-existing; not
this slice.

| gate | kind | result | note |
|---|---|---|---|
| `HeadlessFac1aHoverCacheTest` | hd+xvfb | PASS | Home 12 hovers 2→2; close 4→4; data 6→6; split A=`710430` B=`710434`; FAR_C `710451` |
| `HeadlessFac1aPanIconsTest` | hd | PASS | pan builds 2→2; hover 0 extra; drawn=1 |
| `HeadlessFac1aAirfieldIconTest` | hd | PASS | hit / cluster / oval unchanged |
| `HeadlessClose1StaleDragGuardTest` | hd | PASS | CLOSE-1/1b leftover + first-edge |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS | TipDismiss × |
| `HeadlessOrders1HaltHoldWithdrawTest` | hd | PASS | Halt / Hold ● / Withdraw ● / Start |
| `HeadlessCombat1FightResolveTest` | hd | PASS | Took/Held |
| `HeadlessUi1LeadersEdgePanMarchTest` | hd | PASS | top-bar strip + rest |
| `HeadlessEdge1CameraFeelTest` | hd | PASS | L/R/T/B + x=1270 |
| `HeadlessMarchZoomDestPickTest` | hd | PASS | dest 710380 |
| `HeadlessFleet1LandSpillGateTest` | hd | PASS | (a)–(h) |
| `HeadlessFleet2SharedSeaMarkerTest` | hd | PASS | painted-pixel |
| `HeadlessRx1RhineCrossingTest` | hd | PASS | vector Rhine |
| `HeadlessRx1RhineVisibilityTest` | hd | PASS | U / units-on-top |

Budget timing (xvfb 1280×740, 180 dummy icons, z0.776): 8× uncached
`compute_markers_at_zoom` **46.3 ms** vs 8× cached `hit_test_at_zoom` **10.0 ms**.
Did **not** re-run full F5 Begin GER 15-frame hover windows (no harness in this
slice). Human recipe: `CLICKS.md`.
