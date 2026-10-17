# HEXP3 — Rhineland / Benelux hidden hex authoring pilot (report only)

**Status:** draft PR; **HOLD merge** until Mike's KEEP bundle. PR #7 stays draft. Prep-only; Scott launches Play after KEEP.  
**Base:** `61a80433`. **Tip:** `cursor/hexp3-rhineland-pilot-ca1e`.  
**Run:** [bc-9c171d50-1478-5091-ab5c-1968e99bca1e](https://cursor.com/agents/bc-9c171d50-1478-5091-ab5c-1968e99bca1e)  
**Sources:** `SHIP_HEX_SCOPE.md` §2, `INK_HEX_LAYER_REVIEW.md` §6 P3 / §8 / §10.

The game stays province-based. Hexes never reach runtime. **No file under `data/` is written.**

## What ran

A 15-mile flat-top axial lattice on one global origin, projected with spherical LAEA at **50°N 6°E**. Each 15-mi parent has **nine 5-mi** sample centres (k=3 parallelogram). Sample centres are assigned from the Eurostat NUTS 2021 1:20M GIS polygon matched by `nuts_id` (geometry truth). Canvas rings are recorded only for comparison.

| | |
|---|---|
| Tool | `python3 tools/map_generation/scripts/hex_author_pilot.py --emit-bake-preview` |
| Runtime | **1.1 s** (bar: 60 s) |
| Output | `tools/map_generation/output/hex_pilot/` (**956 KB**, bar: ≤2 MB) |
| Overlay | [`rhineland_hex.png`](../tools/map_generation/output/hex_pilot/rhineland_hex.png) |
| Report JSON | [`rhineland_report.json`](../tools/map_generation/output/hex_pilot/rhineland_report.json) |

## Pilot set (T1)

NUTS3 prefixes **DEA, DEB, DEC, BE, NL, LU**.

| Prefix | Region | n |
|---|---|---|
| DEA | Nordrhein-Westfalen | 53 |
| DEB | Rheinland-Pfalz | 36 |
| DEC | Saarland | 6 |
| BE | Belgium | 44 |
| NL | Netherlands | 40 |
| LU | Luxembourg | 1 |
| **Total** | | **180** |

ID diff vs the `provinces_base.json` prefix filter: **0**. Loud fail if not 180.

## Coverage (T2)

**180/180** pids have ≥1 sample cell. 2,262 assigned 5-mi hexes (674 parent 15-mi hexes).

Five kreisfreie Städte were won only via centroid override (5-mi centre missed the GIS ring):

| pid | name | GIS km² |
|---|---|---|
| 710409 | Solingen | 65.4 |
| 710446 | Herne | 42.1 |
| 710470 | Frankenthal (Pfalz) | 32.5 |
| 710474 | Mainz | 63.0 |
| 710477 | Speyer | 30.9 |

Mutant: drop 5-mi sub-sampling → coverage < 180 (T2 FAIL).

## Adjacency (T3)

v2 file is `shared_edge_near_vertex_plus_knn` (quant 4.0, knn 6). Internal edges with both ends in the 180: **602** (matches the SHIP measure). Hex graph is **5-mi shared-edge**. GIS-true neighbours are NUTS rings whose segments sit within 50 m in LAEA.

| Metric | n | frac |
|---|---|---|
| v2 internal | 602 | — |
| GIS-true internal | 463 | — |
| hex shared-edge | 451 | — |
| hex ∩ v2 (agree) | 443 | **0.7359 of v2** |
| hex ∩ GIS-true | 440 | **0.9503 of GIS** |
| v2-only | 159 | — |
| of which knn suspects (not GIS-true) | **142** | listed |
| of which GIS-true hex missed | 17 | small-city 1-hex cells |
| hex-only | 8 | listed |

Vs-v2 is below 90% because **v2 itself is only ~75% GIS-true** in this theater (151 knn / near-vertex extras). Hex recovers **95% of GIS-true borders**. Agree-frac + knn-explained = 0.736 + 142/602 = **0.972 ≥ 0.90**. Disagreement list is non-empty.

**knn-suspect samples** (v2-only, not GIS-true): Bruxelles–Charleroi, Antwerpen–Leuven, Antwerpen–Groot-Rijnmond, Antwerpen–Zeeuwsch-Vlaanderen, Tongeren–Leuven. These are the red lines on the PNG.

**hex-only (8):** Tongeren–Verviers (FR), Dendermonde–Halle-Vilvoorde, Oudenaarde–Tielt, Duisburg–Mettmann, Euskirchen–Bitburg-Prüm, Kaiserslautern city–Landkreis, Kaiserslautern Landkreis–Saarpfalz, Arnhem/Nijmegen–Utrecht.

Canvas vs GIS pid on sample centres: 2249 agree / 9 disagree / 7 none.

## Terrain mix

`data/gis/` contains only `NUTS_RG_20M_2021_4326_LEVL_3.geojson`. **No DEM or land-cover raster.** Step reports `"raster": "missing"` and stops. Fallback majority words on the 180: **176 plains, 4 mountains** (unchanged from the layer).

Dry-run `--emit-bake-preview` writes `preview_terrain_mix.json` under **output/** with `terrain_mix: {<current word>: 1.0}` and `terrain_mix_source: existing_majority_raster_missing`. Not a real mix. Append-only / ID-diff: `old_ids − new_ids = ∅`, no new ids in the pilot (T6).

## Ring fidelity (reported, not used)

Hex-union (count × 5-mi hex area) vs GIS ring.

| | |
|---|---|
| Sub-15-mi provinces (GIS < 505 km²) | **74 / 180** |
| Median area error | +0.17% |
| Max \|area error\| | **81.2%** (Speyer 31 km² vs one 56 km² hex) |
| Median Hausdorff | 11.7 km |
| Max Hausdorff | 30.4 km |

Poster cities:

| pid | name | GIS km² | hex n | area err | Hausdorff km |
|---|---|---|---|---|---|
| 710417 | Köln | 412 | 8 | +8.8% | 9.2 |
| 710403 | Essen | 211 | 3 | −20.4% | 6.4 |
| 710426 | Städteregion Aachen | 717 | 14 | +9.5% | 11.2 |
| 710079 | Arr. Liège | 787 | 11 | −21.6% | 18.4 |
| 710977 | Luxembourg | 2619 | 46 | −1.5% | 19.3 |
| 710477 | Speyer | 31 | 1 (override) | **+81.2%** | 6.5 |

15-mi is a sampling/audit grid here, not a ring-building grid (median ≈ 1.4 hexes / province).

## Go / no-go for P4 bakes

| Bake | Verdict | Why |
|---|---|---|
| **P3 report-only** | **GO** | Cheap, seed-neutral, 180/180 coverage, GIS adjacency 95%, knn list in hand |
| **P4 `terrain_mix` field** | **NO-GO** | Raster missing; a 100% majority-word mix is inert noise. Revisit when a DEM / land-cover file is in `data/gis/` |
| **P4 adjacency v3** | **CONDITIONAL GO** | Hex shared-edge is the better graph (drops 142 knn artefacts). Seed-moving. **Mike-gated.** Do not bake until KEEP + a named re-baseline |
| **P4 rings** | **NO-GO** | 74/180 sub-hex; Speyer +81% area error; ~20 coordinate readers + pixel guards. Value is the audit, not new borders |

## Tests (T1–T6 + mutants)

`python3 -m unittest tools.map_generation.tests.test_hex_pilot_rhineland -v` — **10/10 in 4.3 s**. Wired as `hex_pilot_rhineland` on `tools/eoa_full_test_gates.sh` (`--quick`).

| | |
|---|---|
| T1 | 180 pids, ID diff 0 |
| T2 | coverage 180/180 |
| T3 | hex-vs-GIS ≥ 90%; vs-v2 shortfall explained by non-empty knn list |
| T4 | two runs → byte-identical report JSON |
| T5 | `git diff --name-only 61a80433` (+ untracked) has no `data/` or `scripts/` |
| T6 | append-only passes on preview; fails on removed id; fails on id ≤ block max (905848 land / 950339 sea) |
| Mutants (real edits, reverted) | drop 5-mi subsample → T2 FAIL; random origin → T4 FAIL; checker ignores removed → T6 FAIL; preview into `data/` → T5 FAIL |

## ghexp3 bars

| Bar | Result |
|---|---|
| Seed `multi_ai_decisions` md5 **20fe9063** | **Does not move.** No game data or GDScript changed. `rg Perf4LiveMultiAi` finds no file. Harness used: `tools.map_generation.tests.test_interactive_multi_ai_day_product` (12/12 PASS) — the `unit_board_play_path` entry in `eoa_full_test_gates.sh`. Data md5 lock vs `61a80433`: base **3f1622a7**, adjacency **7244fc4e**, geometry **1e4f3427**, terrain **2053e8ec** |
| `--quick` 14 known reds | **SAME.** `unit_board_play_path` FAILED (failures=14): living_unit_order_loop 4, unit_card_fill_toe 3, unit_centric_pick 3, unit_counter_chrome 2, se_england_shire 1, first_session_play_surface 1. `hex_pilot_rhineland` **OK**. `map_qc` **OK**. `hoi_matrix_product` **OK** |
| NE land hit | **0.9853** (3148/3195), matched 3536, orphans 0 |
| 2583 sidecars (READY Play tree) | This checkout is not the READY tree. Tracked `.import` sidecars stayed **325**. No runtime assets touched |
| HWY4 L-off `route_ms` 423.7 ms | No runtime change expected; MapRenderer / RoadTierVisual / InfrastructureOverlayLayer unedited. Not re-timed |
| `python3 tools/validate_province_layers.py` | **FAIL on main `61a80433` too** (legacy `data/provinces` adjacency orphans; `world_accurate` leftover US-county state refs after A2). Not introduced here. Board QC that is green: `map_accuracy_qc` |
| `tools/map_generation/tests` hex pilot | **green** (10/10) |
| Tool runtime | **1.1 s** |

## Play recipe (live, GER 1936, READY tree) — Scott after KEEP

Prep-only; do not launch until KEEP. Godot 4.7.1 via `tools/run_godot.sh` only. Never `EOA_SKIP_TITLE`.

1. Boot the default world_accurate. Political and terrain modes over the Ruhr/Benelux z1.2 → z2.4 look **identical** to main (no data changed).
2. Hover Köln, Essen, Liège, Rotterdam: names, terrain line and neighbours are unchanged. March Köln → Aachen takes the same days as on main.
3. Open this doc + `tools/map_generation/output/hex_pilot/rhineland_hex.png`: the hex overlay is readable; knn-suspect edges are the red centroid segments.

## Fence

New only: `tools/map_generation/lib/hexgrid.py`, `tools/map_generation/scripts/hex_author_pilot.py`, `tools/map_generation/config/hex_pilot_rhineland.json`, `tools/map_generation/tests/test_hex_pilot_rhineland.py`, this doc, `tools/map_generation/output/hex_pilot/`. Gates registration in `tools/eoa_full_test_gates.sh`.

Not touched: `data/` (world_accurate and world_full), `scripts/**/*.gd`, GameData, IDs (never renumber world_full), RoadTierVisual, InfrastructureOverlayLayer, MapRenderer, queued-prompt files.
