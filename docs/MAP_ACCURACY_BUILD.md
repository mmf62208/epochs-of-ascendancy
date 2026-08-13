# Map accuracy build — dual boards & GIS path

**Status:** **Test/default launch uses the accurate GIS board** (`TestRunner` → `world_accurate` → `provinces_world_accurate`, **~3520** post US + full RoW sparse; was ~5670 / ~8761). Scaffold `world_full` remains available via `EOA_SCENARIO=world_full` (IDs never renumbered in place).

**World-class HOI4/V3 map review (living star):** [`WORLD_CLASS_MAP_REVIEW.md`](WORLD_CLASS_MAP_REVIEW.md) — hierarchy inventory, landed-vs-gap matrix; **M0–M5 done**; **A2 US merge done**; next **M6** human notes (+ post-merge FPS re-sample).

## Boards

| Scenario / env | Data dir | Accuracy |
|----------------|----------|----------|
| **Default F5 / TestScenario** | `data/provinces_world_accurate/` | **GIS hybrid + us_merge_v1 + row_sparse_merge_v1** (~**3520**); NUTS-3 + **US 130 playable** + RoW sparse + seas |
| `EOA_SCENARIO=world_full` | `data/provinces_world_full/` | Structural 2665 scaffold (legacy dual board) |
| `EOA_SCENARIO=world_pilot_europe_nuts3` | `data/provinces_pilot_europe_nuts3/` | **Eurostat NUTS-3 GIS** (1514 land, IDs 710000+) |
| `EOA_SCENARIO=world_pilot_us` | `data/provinces_pilot_us/` | Procedural US densify (not TIGER yet) |
| `EOA_SCENARIO=world_accurate` | `data/provinces_world_accurate/` | Same as default test path |
| `provinces_pilot_us_tiger` | US county GIS pilot | TIGER fixture or real CB counties (IDs 800000+) |

**Guardrail:** never renumber shipped `world_full` province IDs in place. Use dual dirs + remap tables (`nuts3_to_world_full_overlap.json` pattern).

## QC commands

```bash
# Orphans + names + Natural Earth land-mask hit rate
python3 tools/map_generation/scripts/map_accuracy_qc.py \
  --dir data/provinces_world_full \
  --json-out tools/map_generation/output/qc_world_full.json

# GIS Europe pilot should score high on NE land
python3 tools/map_generation/scripts/map_accuracy_qc.py \
  --dir data/provinces_pilot_europe_nuts3 \
  --min-land-hit 0.90 \
  --json-out tools/map_generation/output/qc_nuts3.json

# Play path pick quality (scaffold dual — world_full city IDs)
tools/run_godot.sh --headless -s res://tools/map_pick_policy_test.gd
tools/run_godot.sh --headless -s res://tools/map_manager_pick_harness.gd
# Accurate capital samples (pure + MapManager-only GD harness)
python3 -m unittest tools.map_generation.tests.test_world_accurate_capital_pick_product -v
tools/run_godot.sh --headless -s res://tools/map_manager_pick_harness_accurate.gd
# Ownership / political mapmode readability (D3.3)
python3 -m unittest tools.map_generation.tests.test_ownership_mapmode_readability_product -v
# FPS pilot + M5 measured samples @ ~8761
python3 -m unittest tools.map_generation.tests.test_map_perf_fps_harness_world_accurate -v
python3 -m unittest tools.map_generation.tests.test_map_perf_m5_measured -v
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMapPerfTest.gd
```

Optional NE full align (gated write):

```bash
python3 tools/map_generation/scripts/align_ne_full_geometry.py --dir data/provinces_world_full
# mutation requires: --write --full --backup
```

## Build order (accuracy program)

1. **Phase 0** — QC tool + freeze freehand densify as the accuracy path (hotfixes only on world_full).
2. **Phase 1** — Harden Europe NUTS-3 (names, states, ownership, shared-edge adj).
3. **Phase 2** — US TIGER county ingest → pilot dir.
4. **Phase 3** — Rest-of-world GADM/geoBoundaries + sparse merges + seas.
5. **Phase 4** — Cutover default scenario to accuracy board when dual green.

Plan detail: session `plan.md` (full accurate world map — province board v2) and `docs/MAP_HIERARCHY_AND_GIS_ROADMAP.md`.

## What “full map done” means

| Question | Answer |
|----------|--------|
| Every province id has base + geometry + region? | world_full **yes (2665)** · world_accurate **yes (~8761)** |
| GIS-accurate coasts/admin shapes default? | **yes for TestRunner/F5** (`world_accurate` v1.7 hybrid) |
| Major-city pick quality? | scaffold harness green; accurate capital pick product green; human click still recommended |
| Phase 4 test cutover? | **done** — default scenario `world_accurate` |
| Shared-edge residual? | **D5.1 done** — near_vertex · coverage ~0.971 · method `shared_edge_near_vertex_plus_knn` |
| Strategic resources / chokes? | **D5.4 done** — `paint_world_accurate_strategic_resources.py` + strategic map product |
| Multi-front live assaults? | **D5.5 done** — border targets + Maginot/Polish headless |
| Province→state→region hierarchy data? | **yes (M0)** — **31** regions (file=membership, multi=0) · **429** land states · **4** super |
| Resources mapmode (player UX)? | **yes (M1)** — F9 + toolbar Resources |
| States mapmode (player UX)? | **yes (M2)** — Shift+F9 + toolbar States |
| Terrain mapmode (player UX)? | **yes (M3)** — Ctrl+F9 + toolbar Terrain |
| Supply corridor (capital→front)? | **yes (M4)** — G + supply-click polyline · land BFS/infra |
| FPS budget @ ~8761? | **M5 samples** — p50 50.2ms · p95 53.0ms · soft 30 **FAIL** (map-tick proxy); artifact `output/map_perf_world_accurate_samples.json` |
| CI dual path? | `world_full` SCRIPT 0 smoke; accurate optional longer job |

## License notes

- Natural Earth: public domain.
- Eurostat GISCO NUTS: check Eurostat reuse policy for redistribution.
- Prefer geoBoundaries / public admin sources over proprietary GADM commercial licenses when packaging data.

## US TIGER pilot (offline)

```bash
python3 tools/map_generation/scripts/ingest_us_tiger_counties.py \
  --source tools/map_generation/fixtures/us_tiger_counties_fixture.geojson --write
# → data/provinces_pilot_us_tiger/ (IDs 800000+, no world_full renumber)
```

## Europe NUTS-3 gold QC

```bash
python3 tools/map_generation/scripts/europe_nuts3_harden_qc.py --min-land-hit 0.95
```

## Assemble GIS hybrid full board

```bash
# Requires NE admin_1 cache + NUTS-3 pilot (and optional US TIGER pilot)
python3 tools/map_generation/scripts/assemble_world_accurate.py --us-mode ne --write
# QC (expect NE land hit ≳ 0.95)
python3 tools/map_generation/scripts/map_accuracy_qc.py \
  --dir data/provinces_world_accurate --min-land-hit 0.90
# Play
EOA_SCENARIO=world_accurate tools/run_godot.sh --path .
```

## Full US counties → TIGER pilot

```bash
# Uses cached plotly FIPS county GeoJSON (~3221 features)
python3 tools/map_generation/scripts/ingest_us_tiger_counties.py \
  --source tools/map_generation/data/cache/us_counties_fips.geojson --write

# Rebuild hybrid full board with TIGER US block
python3 tools/map_generation/scripts/assemble_world_accurate.py --us-mode tiger --write
```

## Enrich accurate board layers

```bash
python3 tools/map_generation/scripts/enrich_world_accurate_layers.py --write
# states (EU NUTS + US FIPS + RoW countries), super_regions, economy/city/resources, era ownership stubs
```

## Polish accurate board (ownership / chokes / adj / capitals)

```bash
# Full retune (shared-edge adjacency is the slow step)
python3 tools/map_generation/scripts/polish_world_accurate_board.py --write --quant 1.5

# Fast pass (skip adjacency rebuild)
python3 tools/map_generation/scripts/polish_world_accurate_board.py --write --skip-adj

# Integrity tests (drives map_accuracy_qc + ownership/choke/capital gates)
python3 -m unittest tools.map_generation.tests.test_world_accurate_board -v

# Light era ownership deltas (1910/1918/1945/2026) from polished 1936
python3 tools/map_generation/scripts/assign_world_accurate_ownership_eras.py --write

# Terrain + resource heuristics (lat/lon + adm0; not DEM)
python3 tools/map_generation/scripts/polish_world_accurate_terrain.py --write

# RoW densify (geoBoundaries open data; priority countries ADM2→merged targets)
# Caches under tools/map_generation/data/cache/geoboundaries/
python3 tools/map_generation/scripts/densify_row_geoboundaries.py --write
# Then re-run polish → eras → terrain → enrich → adjacency retune
```

**v1.7 + us_merge_v1 board results (approx):**

| Gate | Value |
|------|--------|
| Provinces | **~5670** (land ~5330 / sea 340) — pre-US-merge was ~8761 |
| US block | **130** playable (1–4/state by size); remap `us_county_to_playable_remap.json` |
| NE land hit | ≥ 0.90 |
| Land ownership | 100% (1936) |
| RoW densify | **~100+ countries**, ~3350 geoBoundaries cells (tranches 1–3) |
| Tranche 3 adds | UGA TZA AFG BGD + most remaining Africa/LATAM/CA/MENA NE leftovers (see densify script TARGETS) |
| Chokepoints | sea/strait + Panama only |
| Shared-edge land coverage | **~0.975** @ quant 4.0 + near_vertex 20 (orphans after KNN = 0; method `shared_edge_near_vertex_plus_knn`) |
| Capitals | GER Berlin · FRA Paris · ENG London · USA DC (`800792`) · SOV Moscow · ITA Rome · JAP Tokyo · POL Warsaw |
| Default F5 / TestRunner | **`world_accurate`** (GIS hybrid); scaffold via `EOA_SCENARIO=world_full` |

### US density merge (A2)

```bash
# Plan only
python3 tools/map_generation/scripts/merge_us_counties_to_state_provinces.py
# Write (backup + hull merge + adjacency + remap)
python3 tools/map_generation/scripts/merge_us_counties_to_state_provinces.py --write
# Pure product gates
python3 -m unittest tools.map_generation.tests.test_us_state_province_density_product -v
```

Never renumbers `world_full`. Protected USA capital + key_provinces remain survivors.

**License:** geoBoundaries `gbOpen` (CC-BY / ODbL-class open — check per-country source in metadata).

## Phase 4 cutover status

| Item | Status |
|------|--------|
| Accurate board dual-green (QC + unit tests) | **yes** |
| Default pick policy + MapManager harness | **ok=true** on scaffold (harness still exercises `world_full` samples) |
| Default **TestRunner / F5** scenario | **`world_accurate`** (cut over) |
| Scaffold still available | `EOA_SCENARIO=world_full` |
| Guardrail | `world_full` province IDs are **not** renumbered in place |

Heavy headless CI may still prefer `EOA_SCENARIO=world_full` or phase1 for speed/memory.

## Dual-board play harness

```bash
# Scaffold city-pick regression (samples world_full IDs — intentional dual)
tools/run_godot.sh --headless -s res://tools/map_pick_policy_test.gd
tools/run_godot.sh --headless -s res://tools/map_manager_pick_harness.gd

# Default interactive = accurate GIS board
tools/run_godot.sh --path . res://scenes/TestScenario.tscn
# Explicit accurate / scaffold
EOA_SCENARIO=world_accurate tools/run_godot.sh --path .
EOA_SCENARIO=world_full tools/run_godot.sh --path .
```

**Director / status:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md) · [`GAME_DIRECTOR_PLAN.md`](GAME_DIRECTOR_PLAN.md)
