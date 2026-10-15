# EDGE-2 keep-green (headless ≠ live Play)

Recorded on the EDGE-2 tip vs WHEELDRIFT-1 `b7affe58`.

| gate | kind | result | notes |
|---|---|---|---|
| `HeadlessEdge2RimFeelTest` | hd | FAIL on `b7affe58` / PASS on tip | dwell / ramp / cap / left HUD |
| `HeadlessEdge1CameraFeelTest` | hd | PASS | 6/10 px strips, Close-held |
| `HeadlessUi1LeadersEdgePanMarchTest` | hd | PASS | top-bar strip + rest |
| `HeadlessClose1StaleDragGuardTest` | hd | PASS | leftover first-edge |
| `HeadlessWheelDrift1Test` | hd | PASS | 350+150 wheel hold kept |
| `HeadlessVis2CapitalStarsAfterLTest` | hd | PASS | L cycle stars |
| `HeadlessIx1SearchGoInspectorTest` | hd | PASS | Search→Go |
| `HeadlessRt1RoadTierForEdgeTest` | hd | PASS | road tiers |
| `HeadlessRt1RoadEdgeFilterTest` | hd | PASS | road edge filter |
| `HeadlessVis1MapReadabilityTest` | hd | FAIL (pre-existing on main and #105) | not this slice |
| `tools/eoa_full_test_gates.sh --quick` | py | FAIL failures=14 | same known reds as base |
| `map_qc` | py | NE land hit **0.9853** | unchanged |
| seed 193601 day-sim | — | md5 `20fe9063` | no GameData/sim edits |
