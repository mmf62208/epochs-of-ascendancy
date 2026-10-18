# ROADS-1 + OLDMAP_TURKEY

Branch `grok/roads1-oldmap`. Render-only. Draft stays on HOLD. No merge.

Base before these slices: `a1b4d11c` (P1 air physics, #108). Rebased onto `origin/main` `99e8d8f8` (FAC-1a #98, PERF-5 #110, INPUT-1 #89) before the final push. The briefs were written against `6f0e5389`, which is not an ancestor of this branch. Line numbers in the briefs are stale.

`data/` has no diff against `a1b4d11c`. No new `EOA_*` switch. Godot stays 4.7.1 via `tools/run_godot.sh`.

Munitions is in the **other** bucket (highway 0.12 at z≥1.5, paved/dirt/rail hidden, no casing). Supply, infra, resources, and any mode while L (`supply_mode`) is on are logistics (every tier a=1.0, casing on).

## Province borders and layers left above them

Live z dump, political, Xvfb 1280×800 (`roads1_after/run2.log`):

| Node | abs z |
|---|---|
| OceanFloorContinuous | −30 |
| WorldBackground | −20 (hidden outside terrain) |
| ElevationLayer | −18 (hidden outside terrain) |
| RiversLayer | −17 (hidden outside terrain) |
| TerrainLayerStack | −15 |
| UssrWestGapMask | −14 (land tint child −13) |
| Rx1RhineLayer | 9 |
| RoadCasingDraw | 10 |
| RoadLayer / RoadTierDraw | 11 |
| BorderLayer | 15 |

Internal province edges are `ProvEdge_` Line2Ds on BorderLayer with relative z 0, so absolute z 15. Country frontier segments on that layer are relative z 2 (absolute 17). Coast segments are relative z 1 (absolute 16). Hover and select outlines are `ProvinceMapVisuals` `Z_HOVER` 14 and `Z_SELECT` 16 on the province node. The live dump did not include a `ProvEdge_` node.

Source, not live-dumped: `PoliticalLabelsLayer` z 12, nation-label const `NATION_LABEL_Z` 18, province name labels 82 (100 while L is on), supply fill 90, units `UNIT_COUNTER_Z` 28.

Spine layers left above borders, on purpose: `Ix1SpinePreview` `SPINE_BELOW_UNITS_Z` 21 and `Ix1GoldSpine` `GOLD_SPINE_Z` 23.

Rhine headless: `Rhine z=9 < road z=11 < 15; gold z=23`.

## Seed, NE, --quick

Seed `HeadlessPerf4LiveMultiAiDayTest`, three runs, each `RESULT=PASS`. The md5 is of the `multi_ai_decisions=` line (text after `HeadlessPerf4LiveMultiAiDayTest: `) plus a trailing newline.

| Run | md5 | first 8 |
|---|---|---|
| 1 | `20fe9063de285f19d4f9b8a105abfd31` | `20fe9063` |
| 2 | same | `20fe9063` |
| 3 | same | `20fe9063` |

The full logger line (`HeadlessPerf4LiveMultiAiDayTest: multi_ai_decisions=...`) hashes to `2f108bae…`, which is a different string. The pinned prefix matches the `multi_ai_decisions=` line.

NE land hit, inside `--quick` `map_qc`: **0.9853 (3148/3195)**.

`--quick` on the untouched base (`/tmp/roads1_quick_base.log`) and on this tip (`/tmp/roads1_quick_tip2.log`): exit 1, **14 failures, same names**. No new red, none cleared.

1. `test_integrity` living unit order loop
2. `test_playtest_clock_does_not_skip_ai_starts`
3. `test_playtest_clock_does_not_skip_occupation_ticks`
4. `test_product_wiring` living unit order loop
5. `test_integrity` unit card fill/toe
6. `test_product_ok` unit card fill/toe
7. `test_renderer_source_lock` unit card fill/toe
8. `test_integrity` unit centric pick
9. `test_product_wiring` unit centric pick
10. `test_renderer_integrity_strings` unit centric pick
11. `test_integrity` unit counter chrome
12. `test_product_wiring` unit counter chrome
13. `test_prior_feed_products_and_fill_toe_still_pass` SE England shire
14. `test_real_builder_ands_shipped_children` first session play surface

An intermediate `--quick` (`/tmp/roads1_quick_tip.log`) had 16 failures. The two extra were `test_ix1_road_spine_product` `test_product` and `test_spine_complete_zoom_gate`, missing token `preview_antialiased_oom`. The IX-1 slicer treats the source text `, true)` anywhere after `_draw_spine_dashed` as an antialiased preview dash. The casing draw called `build_road_draw_plan(chains, zoom, true)`. That call now uses a local `logistics_casing`. The preview dash is still `draw_line(..., false)`. The follow-up `--quick` is the 14-red run above.

Headless after that fix: `HeadlessRoads1QuietGuard` RESULT=PASS, `HeadlessRt1RoadTierForEdgeTest` RESULT=PASS, `HeadlessRx1RhineVisibilityTest` RESULT=PASS. Turkey mask unit tests 3/3 OK. Rhine product tests OK.

Europe-view frame mean, first 25 frames with dt under 5000 ms, llvmpipe, run 2: **51.95 ms**. BEFORE frame time is not in the evidence pack. The +5% bar is **UNKNOWN**.

## ROADS-1 widths

BEFORE `_measure_edge` on 710401–710412 (evidence pack, tree `6f0e5389`): z 0.45 / 0.70 / 1.0 / 1.6 / 2.4 / 2.8 / 4 / 6 = **23 / 14 / 19 / 20 / 17 / 29 / 16 / 16**.

AFTER, same pair, logistics, run 2 (`roads1_after/run2.log`): **4 / 1 / 7 / 6 / 8 / 9 / 8 / 8**.

The acceptance caps are ≤4 at z 0.45–1.0, ≤6 at z 1.6 and 2.4, ≤9 at z 2.8 / 4 / 6, monotonic, never under 1 where visible. The live scan **fails** ≤4 at z 1.0 (measured 7), **fails** ≤6 at z 2.4 (measured 8), and is **not monotonic** (4, 1, 7, 6, 8, 9, 8, 8). z 4 and z 6 are 8, which is the clamped casing. The pair is about 7 world units long. `_measure_edge` walks ±12 screen px and picks up neighbouring Ruhr strokes at low zoom. The geometric table in `highway_casing_px` / `tier_outer_px` passes `HeadlessRoads1QuietGuard` (≤4 / ≤6 / ≤9, monotonic, z1 casing 2.6, z4 casing 8). There is no 20 px far floor on this tree. Mutant (a) adds one and the guard fails.

## Mode nodes

Run 2. Node `modulate.a` and `visible` are the mode bar. The full-frame palette count collides with political fills (political z0.7 reports stripe=77 and casing=20481 while every road node is `visible=false`). Those counts are not road pixels.

| Mode | z | bucket | highway | paved/dirt | casing |
|---|---|---|---|---|---|
| political | 0.70 | political | vis false a 0 | hidden | hidden |
| terrain | 0.70 | terrain | hidden | hidden | hidden |
| states | 0.70 | other | hidden | hidden | hidden |
| munitions | 0.70 | other | hidden | hidden | hidden |
| political | 2.40 | political | vis true a **0.180** | hidden | hidden |
| terrain | 2.40 | terrain | a **0.250** | hidden | hidden |
| states | 2.40 | other | a **0.120** | hidden | hidden |
| munitions | 2.40 | other | a **0.120** | hidden | hidden |
| supply | 2.40 | logistics | a 1 | a 1 | on |
| infra | 2.40 | logistics | a 1 | a 1 | on |
| resources | 2.40 | logistics | a 1 | a 1 | on |
| political + L | 2.40 | logistics | a 1 | a 1 | on |

Logistics stripe pixels at Ruhr z2.4 from the same contaminated classifier: supply 40, infra 272, resources 205, political+L 20. BEFORE Ship count was 1248. 90% of that is 1123. This probe does **not** meet that bar. A count of 77 stripe pixels with roads hidden shows the classifier is not Ship's.

## Casing

Headless: casing ops precede fill ops, one disc per interior vertex, no casing outside logistics. PASS.

Live literal offset `fill/2 + 1 px` (`run2.log`):

| Site | z | result |
|---|---|---|
| italy 710882 | 0.70 | strict 0/14. Offset 1.62, casing half-width 0.52, so the sample is outside the stroke. |
| germany_n 710321 | 0.70 | same, strict 0/14 |
| france | 0.70 | NO_BEND |
| frankfurt | 4.00 | NO_BEND |
| bonn 710409 | 4.00 | seg1 strict 3/14 dark 2; seg2 strict 0 |
| ruhr 710409 | 4.00 | same as bonn |

The 98% bar is **not** met. Casing colour is drawn at alpha 0.85, so an unblended casing key misses blended pixels.

## Lithuania stub

Geometry points are canvas units. Live centroids and Polygon2D rings are canvas × `THEATER_SCALE` 1.728. The first filter compared world centroids to raw rings and dropped 53 edges, including real Ruhr pairs `710401_710412`, `710416_710417`, `710417_710418` (`roads1_after/run.log`). That list is a coordinate bug, not the Lithuania stub. Draw rings are now scaled. Shared-border keys stay unscaled.

AFTER (`roads1_after/stub3_run.log`): `dropped_n=0` `rings=1525`. No tier-2 edge has an endpoint outside a drawn ring.

The gap filter drops a tier-2 edge when an endpoint is a 36- or 37-vertex RoW placeholder (pid 900000–949999) and the segment leaves every drawn ring. Headless synthetic circles at that pattern fail closed. An edge that stays inside one ring, a gap between Europe pids, and an empty ring list stay open. Live `dropped_n` is still 0: those RoW blobs are not in the 1525 draw rings unless the road cache loaded them, and no drawn highway crosses one.

Offline adjacency (not the drawn-highway list) that matches the old description:

- `710967` Vilniaus apskritis (36 pts, Europe pid) → `905817` BLR 36-pt blob, canvas distance 44
- `905809` BLR (y 807.2) → `903534` Moscow (y 807.5, 36 pts), nearly horizontal

BEFORE edge list of drawn highways on `6f0e5389`: **UNKNOWN** (the brief did not have the pids).

AFTER frame, infra, zoom 0.55, camera on the Vilnius–Moscow midpoint (`roads1_after/stub3/shots/lithuania_stub_infra.png`). Screen centerline from Vilnius `(509,410)` to Moscow `(771,390)`: pixel 0 is Lithuania green `(6,107,73)`; samples at 1/4, 1/2, 3/4, and the Moscow end are `(92,26,26)` / `(94,34,36)`, the SOV mask. Road-coloured samples in a ±6 px band: **1 / 2665**. The thick bar in `oldmap-before-6f0e5389/demo_frames/01_network_t2.png` is not in this frame.

## Mutants

Each road mutant was applied, the quiet guard failed, and the file was restored (md5 match).

| Mutant | Guard line |
|---|---|
| (a) 20 px far floor | `casing 20.00 > 4 at z=0.45` RESULT=FAIL |
| (b) casing and fill interleaved per edge | `casing ops must all precede fill ops` RESULT=FAIL |
| (c) `ROAD_BELOW_UNITS_Z` 21 | `got 10 11 21` RESULT=FAIL |
| (d) `road_tier_mode_alpha` always 1 | `political=1.000 terrain=1.000 other=1.000` RESULT=FAIL |
| (e) `highway_endpoints_in_rings` always true | `an endpoint outside the ring must drop` RESULT=FAIL |

Turkey: renaming the mask call makes `renderer_mount_ok` false (`missing: call _ensure_ussr_west_gap_mask()`). The unsubtracted bbox ring at step 8 fails the overlap guard with **1090** samples (`test_unsubtracted_window_fails_overlap_guard` OK). The committed mask reports overlap 0, Kiev in land and in no province.

## OLDMAP_TURKEY live hits

Run 2, political, rasters hidden. Mask is the top hit where there is no province. n0 is Sinop `711300`. n2 is sea zone `950006`. The mask is subtracted there on purpose, so it is not the top item. WorldBackground, RiversLayer, and ElevationLayer are hidden at all eight points.

| Point | mask | pick |
|---|---|---|
| line_sinop n0 `(8448.3, 2105.9)` | miss | 711300 |
| n1 `(8448.3, 1989.2)` | sea z −14 | −1 |
| n2 `(8448.3, 1872.6)` | miss | 950006 |
| n3 `(8448.3, 1755.9)` | land_tint z −13 | −1 |
| n4 `(8448.3, 1639.2)` | land_tint z −13 | −1 |
| n5 `(8448.3, 1522.6)` | land_tint z −13 | −1 |
| n6 `(8448.3, 1405.9)` | land_tint z −13 | −1 |
| crimea_guess `(8388.3, 1625.9)` | land_tint z −13 | −1 |

Kiev mean, 169 center pixels: rgb `(0.361, 0.102, 0.102)`, delta 0 against `#5C1A1A`. The political polygon is still alpha 0.85 over an opaque plate of the same RGB.

Hover at Kiev: pick −1, `_hover_province` null. The probe read the stored field. It did not warp the mouse. Click-to-selection was not driven separately. Pick at the mask points above is −1.

`turkey_bs_z10` riverish=47 and `crimea_z24` riverish=75 use a blue heuristic (`b>0.45`). RiversLayer was hidden, so those pixels are not that raster. The BEFORE river hex was not pinned. Claim of 0 river-raster pixels by Ship's key: **UNKNOWN**. The raster node is not the top item, and it is not visible in political mode.

Mask asset: `assets/maps/layers/uncovered_land_ussr_west.json`. Bake subtracts province rings. Sea hole uses the ocean-floor colour at the same z.
