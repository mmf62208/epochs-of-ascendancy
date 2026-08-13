# MapRenderer performance & visual gap-closure

**Status:** Phase 1 **map gap** closure landed (signal graph · occupation visuals · perf hooks · CI fingerprint).  
Catalogue labels: map gap · occupation overlay · signal graph · map_gap_closure · phase1_gap · world_class_map  
**Quality bar:** dual `world_full` 2665 green · pure map CI · no province renumbering · guarded writes only.

## Hotkeys / harness

| Key | Action |
|-----|--------|
| **F10** | DebugOverlay (existing) |
| **F11** | SignalGraphVisualizer via `SignalGraphHarness` — live MapManager / day-package / OrderCommandPanel signal graph |
| **O** | Toggle occupation overlay (resistance tint + garrison icons) |
| **L** | Supply overlay (existing) |
| F10 → **Signal Graph** / **Occupation Overlay** / **Map Perf** buttons | Same tools without hotkeys |

Env flags:

- `EOA_MAP_PERF=1` — continuous MapRenderer section sampling; logs `[PERF MAP EVIDENCE]` / `[PERF MAP HOTSPOT]`.
- `EOA_HEADLESS_EVIDENCE=1` — never use (dual bar). Signal harness inventory-only in ScenarioLoader evidence path.
- Dual marker: `map_gap_closure_live=1 occ=1 sig=1 perf=1 overlay=1`

## How to profile (Phase 1 + Director D4)

1. Graphical: F5 `TestScenario` (default **world_accurate** ~3520) → F10 → **Toggle continuous MapRenderer perf sampling** → pan/zoom to max with overlays on (O + L + infra) → **MapRenderer Perf Profile dump**.
2. **CI dual smoke (lighter SCRIPT 0):** `EOA_MAP_PERF=1 EOA_SCENARIO=world_full tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 90` and grep `[PERF MAP`.
3. **Accurate optional longer job:** `EOA_MAP_PERF=1 EOA_SCENARIO=world_accurate tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 120` (may be heavy / OOM-sensitive — prefer graphical sample on developer machine). Feed mean/p95 ms into pure `map_perf_fps_harness_product` (`pilot_name=world_accurate`); empty samples stay honest FAIL not fake PASS.
4. **M5 headless map-tick proxy (landed):** `tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMapPerfTest.gd` → writes `tools/map_generation/output/map_perf_world_accurate_samples.json` + `/tmp/eoa-map-perf-world-accurate.json`. Ingest: `build_m5_measured_product()`. **2026-07-31 post-sparse sample:** n=60 · mean 34.01ms · p50 33.62 · p95 35.61 · ~29.4 fps · soft 30 **FAIL** honest · kind=`map_tick_proxy_headless` (not GPU renderer frames).
5. **Graphical dump:** F10 → Map Perf export calls `export_map_perf_session` (session p50/p95 + samples JSON).
4. Godot debugger: Debugger → Profiler / Monitors while at max zoom with 20+ day packages open in OrderCommandPanel.

Pure pilot plan constants: `tools/map_generation/lib/map_perf_fps_harness_product.py` — live `world_accurate` land~3180 / provinces~3520 · soft 30fps primary · 60fps stretch.

### Known / expected hotspots (instrumented sections)

| Section | Why it matters | Mitigations in tree |
|---------|----------------|---------------------|
| `process_total` | Per-frame camera + pulse + LOD | Already throttled (every 2 frames for detail visibility) |
| `force_full_map_refresh` | Full fill recompute | Owner-scoped refresh APIs; avoid full refresh in daily tick |
| Province fill / poly tint | 2665 polys | Phase E batched mesh fills @ strategic zoom (`BATCHED_MESH_ZOOM_MAX`) |
| Overlay `_draw` (conflict / occupation / weather / infra) | Contested subsets | Occupation icon budget `max_icons=48`; conflict only contested |
| Labels / name LOD | Zoom bands | `MapZoomLOD` + name outline boost only when L on |

Document new hotspots here when `[PERF MAP HOTSPOT]` top-5 changes after a dual run.

## Occupation visual layer (#24 depth)

- Script: `scripts/map/OccupationOverlayLayer.gd`
- Data: `GameData.get_occupation_province_state` (resistance/compliance) + `get_occupation_revolt_state` (garrison mode/strength)
- Visuals: resistance heatmap tint · compliance ring · garrison diamond icons (light/standard/heavy colors)
- Toggle: **O** / F10 button / `MapRenderer.toggle_occupation_overlay()`
- PI chip: `build_occupation_visual_chip_bbcode` — R% · C% · garr%

Phase 2 extensions (planned): full resistance heatmap mapmode, partisan markers, supply-flow arrows, battle indicators, LOD label batching to 60 fps.

## Signal graph

- Visualizer: `SignalGraphVisualizer.gd` (root)
- Harness: `scripts/debug/SignalGraphHarness.gd` — F11, headless `scan_signal_summary()` for CI inventory
- Use when tracing day-package apply routes, MapManager `province_data_changed`, overlay refresh edges

## Visual regression CI

- Pure fingerprint: `map_visual_gap_product.compute_visual_fingerprint()` → `mvg1-…`
- Baseline: `tools/map_generation/baselines/map_visual_fingerprint.txt` (auto-created on first green test)
- Tests: `test_map_visual_gap_product.py`, `test_map_visual_regression_fingerprint.py` via `tools/run_map_ci.sh`
- **Screenshot path (graphical):** fixed camera on key provinces / full canvas — store under `tools/map_generation/baselines/screenshots/` when running non-headless; fingerprint remains the CI gate so dual/headless stays green without GPU golden images.

Optional graphical capture recipe:

```bash
# Future: EOA_MAP_SCREENSHOT=1 graphical run writes baselines/screenshots/*.png
# Diff with perceptual hash in a follow-up CI step when assets are checked in.
```

## Gap plan alignment

| Plan item | Status |
|-----------|--------|
| 1 SignalGraphVisualizer in TestScenario/debug (F11) | **DONE** |
| 2 MapRenderer perf profile + hotspot doc | **DONE** (hooks + this doc; re-run after overlay waves) |
| 3 Occupation tint + garrison icons | **DONE** |
| 4 Visual regression hooks in map CI | **DONE** (fingerprint; screenshot optional) |
| 5–9 Phase 2 map layers / 60 fps pass | **DONE** |
| 10–14 Phase 3 polish / GPU streaming | **DONE** (soft targets) |

## Guardrails

- No renumbering of provinces  
- Guarded writes only (live occupation state under `peace_state`)  
- Dual 2665 bar stays green; never `EOA_HEADLESS_EVIDENCE=1`  


## Harness product (Master Plan M3)

Pure FPS / frame-time harness for map density pilots (no Godot required for the pure gate):

| Item | Path / API |
|------|------------|
| Product | `tools/map_generation/lib/map_perf_fps_harness_product.py` |
| Tests | `tools/map_generation/tests/test_map_perf_fps_harness_product.py` |
| Entry | `build_map_perf_fps_harness_product(land_n=…, frame_times_ms=[…], pilot_name=…)` |
| Helper | `measure_frame_budget(frame_times_ms, target_fps)` → mean/p95/min/max · estimated_fps · budget_ok |
| Plans | `pilot_budget_plan("density"\|"nuts3"\|"world_full")` → land_n + soft budgets |

| Pilot | Expected land / count | Soft 30 fps | Soft 60 fps (stretch) |
|-------|----------------------|-------------|------------------------|
| **density** | ~4650 land (`provinces_pilot_global_density`) | 33.3 ms | 18 ms soft |
| **nuts3** | ~1514 land (`provinces_pilot_europe_nuts3`) | 33.3 ms | 16.7 ms |
| **world_full** | 2665 provinces | 33.3 ms | 16.7 ms |

**Honesty:** empty `frame_times_ms` → `empty=True`, `budget_ok_30/60=False`, score 0 — no fake PASS.

**Dual / headless later (phase 1 note — pure product is enough for M3.1):**

```bash
# Collect MapRenderer section samples (existing):
EOA_MAP_PERF=1 EOA_SCENARIO=world_full \
  tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 120
# grep '[PERF MAP'  — feed frame_avg_ms series into build_map_perf_fps_harness_product(...)
# Optional GD: MapRendererPerf.passes_budget / write_scratch_budget → SCRATCH JSON
```

MapRendererPerf already exposes `passes_budget(target_ms)` and `write_scratch_budget` for live sampling; the pure product is the CI-stable aggregator for density/NUTS pilot budgets.


## Phase 2 + Phase 3 (map gap-closure) · phase2 · phase3 · map_phase23 · supply flow · battle indicator

| Item | Status | Toggle |
|------|--------|--------|
| Occupation resistance/compliance mapmode + partisans | DONE | map modes / F10 |
| Supply/sealane flow arrows | DONE | **U** |
| Battle/assault indicators | DONE | **J** |
| LOD budgets + lower-vert far zoom | DONE | automatic via MapZoomLOD |
| Naval/air domain ops | DONE | **K** |
| Construction progress rings | DONE | F10 / default on |
| Leader station markers | DONE | F10 |
| Editor property inspector + export roundtrip | DONE | ProvinceEditor APIs |
| Weather movement-cost tint | DONE | WeatherOverlayLayer |
| GPU pan/zoom soft targets (60 fps ms) | DONE | MapZoomLOD.target_frame_ms_mid_hardware |

Dual: `map_phase23_live=1` · pure fingerprint `mvp23-*` · tests `test_map_visual_phase23_product.py`

### Hotkeys (Phase 2/3)
| Key | Overlay |
|-----|---------|
| O | Occupation |
| U | Supply/sealane flow |
| J | Battle indicators |
| K | Naval/air domain ops |
| L | Supply logistics (existing) |


## Pack I / M3 — FPS budget harness (2026-07-15)

- `MapRendererPerf.passes_budget(target_ms=16.67)` — compare `frame_avg_ms` vs 60 fps target
- `MapRendererPerf.write_scratch_budget("/tmp/eoa-map-perf-budget.json")` — SCRATCH JSON
- ScenarioLoader prints `map_fps_budget_live=1 target_ms=…` (soft advisory)
- Measure: `EOA_MAP_PERF=1 EOA_SCENARIO=world_pilot_global_density tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 120`
- Graphical: F5 + F10 Map Perf with overlays; then dump + `passes_budget`
