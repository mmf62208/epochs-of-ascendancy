# SHIP STATUS — FIX2 RX-1 pixels + Köln panel (PR 57)

**HOLD for Play. Do not merge. Same draft PR 57.**

| | |
|--|--|
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/57 (draft) |
| **Branch** | `cursor/rx1-rhine-crossing-e117` |
| **Base Play fail** | `816cdc921c8072928d24a90a71a0d4088e9cde05` (mechanics PASS; screen FAIL) |
| **Implementation** | `69b6d8d3` (screen-space / labels / Köln built) + `c128ca78` (theater scale) |
| **Pixel guard** | `73dc3dc3` (Köln frame + local-stroke sample) |

## Root cause (items 1–2)

1. **Rhine off the live canvas.** Spec course is 8192-space. Live `world_accurate` is × `THEATER_SCALE` 1.728. Unscaled points sat near 4254,944; Köln is 7351,1631. World-width `draw_line` 2.8 was sub-pixel at mid zoom. Nation Labels z=40 buried Rhine z=36 / roads z=32. FIX1 z>28 passed on paper.
2. **Built spine.** Same world-width + z-under-labels. Political `show_roads` is off; explicit IX-1 lines were 2.8u under chips. Play saw only the short Köln preview zig-zag.

## Product fix

- Scale course/midpoints with `MapCanvasConfig.scale_points`.
- Screen-space Rhine 7px / halo 14px at z=90; roads 7px at z=88.
- Nation labels z=18; fade from zoom 0.62; hide at 0.88.
- `is_ix1_road_spine_built` / no fall-through on `should_show`; `_show_ix1_spine_built_state`.
- Bridge chrome only Neuss 710413 / Mettmann 710412.

## Guards (816cdc9 vs tip)

| Guard | `816cdc9` | tip |
|-------|-----------|-----|
| `WindowedRx1RhinePixelGuard` (xvfb, live TestScenario) | **RESULT=FAIL** mid=0.174 close=0.138 Köln offer=true built=false | **RESULT=PASS** mid=0.944 close=0.915 road=0.667 offer=false built=true |
| `HeadlessRx1RhinePanelStateTest` | **RESULT=FAIL** | **RESULT=PASS** |
| `HeadlessRx1RhineVisibilityTest` | n/a (FIX1 already green) | **RESULT=PASS** |
| `HeadlessRx1RhineCrossingTest` | n/a | **RESULT=PASS** |
| `HeadlessRx1RhineLiveStayAliveTickTest` | n/a | **RESULT=PASS** |
| `HeadlessIx1RoadSpineLiveStayAliveTickTest` | n/a | **RESULT=PASS** |
| `HeadlessIx1SearchGoInspectorTest` | n/a | **RESULT=PASS** |
| `test_rx1_rhine_crossing_product` | n/a | **8/8** |
| `test_ix1_road_spine_product` | n/a | **15/15** |

Artifacts are **real** viewport PNGs (not mocks). Smoke harness is **not** the product.

## Out of scope (unchanged)

Move ETA preview · bridge blow/capture · hills · road tiers · `world_full` / NUTS3 IDs · Godot bump · `EOA_SKIP_TITLE`.
