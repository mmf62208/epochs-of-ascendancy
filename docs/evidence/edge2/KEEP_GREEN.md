# EDGE-2 keep-green (headless ≠ live Play)

Recorded on EDGE-2 tip `edd60db8`+ vs WHEELDRIFT-1 `b7affe58`.

| gate | kind | result | notes |
|---|---|---|---|
| `HeadlessEdge2RimFeelTest` | hd | **FAIL** on `b7affe58` / **PASS** on tip | `mutant no_dwell: EDGE_PAN_RIM_DWELL_SEC 0.250 missing` on base |
| `HeadlessEdge1CameraFeelTest` | hd | PASS | 6/10 px strips, Close-held |
| `HeadlessUi1LeadersEdgePanMarchTest` | hd | PASS | top-bar strip + rest |
| `HeadlessClose1StaleDragGuardTest` | hd | PASS | leftover first-edge; last drag re-seeds origin (see below) |
| `HeadlessWheelDrift1Test` | hd | PASS | 350+150 wheel hold kept |
| `HeadlessVis2CapitalStarsAfterLTest` | hd | PASS | L cycle stars |
| `HeadlessIx1SearchGoInspectorTest` | hd | PASS | Search→Go |
| `HeadlessRt1RoadTierForEdgeTest` | hd | PASS | road tiers |
| `HeadlessRt1RoadEdgeFilterTest` | hd | PASS | road edge filter |
| `HeadlessVis1MapReadabilityTest` | hd | FAIL (pre-existing on main and #105) | not this slice |
| `tools/eoa_full_test_gates.sh --quick` | py | FAIL `failures=14` | same known `unit_board_play_path` reds as base |
| `map_qc` | py | NE land hit **0.9853** (3148/3195) | unchanged |
| seed 193601 day-sim | — | md5 `20fe9063` | no GameData/sim edits (`git diff b7affe58 -- scripts/autoload/GameData.gd` empty) |

## Mutant kills (`HeadlessEdge2RimFeelTest` RESULT=FAIL)

| mutant | what it does | kill line |
|---|---|---|
| `no_dwell` | `edge_pan_feel_scale` always returns 1.0 | `feel_scale before 250 ms is 1.000 (want 0)` |
| `no_ramp` | 0 until dwell, then instant 1.0 | `feel_scale at 0.3 s is 1.000 (want < 0.25 of full)` |
| `no_cap` | `edge_pan_zoom_divisor` is raw zoom | `far zoom 0.11 divisor is 0.110 (want Home 0.330)` |
| `left_blocked` | drop `left_hud_only` / `left_strip_hud_exempt` | `left HUD in the 6px strip must pan west (dir=(0.0, 0.0))` |

## Close1 last-assert note

Headless `warp_mouse` leaves the viewport pointer at `(0, 0)`. On `b7affe58` that corner instantly edge-panned (false "drag" green, delta≈311). EDGE-2 dwell holds `(0, 0)` for 250 ms, so the last Close1 assert now re-seeds the synthetic press origin to `(80, 200)` and applies the intended last-pos delta. Product drag path is unchanged.

`tools/eoa_edge2_guard.sh` wraps the Edge2 fixture. Headless ≠ live Play.
