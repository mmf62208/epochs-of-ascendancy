# STATUS — FIX IX-1 spine UX + silent exit after zoom — tip `002df244`

Updated: Fri Sep 25, 2026
From: Ship · CA (this run)
PR 55 HOLD: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 · branch `cursor/ix1-road-spine-9d9b` · draft

## Verdict: machine FIX (Play rebound still required)

Start tip: `002df244b3df91ca358be7c44e7314ddb2e430c4`
**GitHub head.sha (STATUS snapshot):** `f5ba54612ab1f01d3f8fe6820c11ae099d4b4da8` (`f5ba5461`)

## Root cause (silent Godot exit)

Play MIXED `002df244`: Search→Köln→Go + spine visible PASS; start **logic** PASS (`InfrastructureDevelopmentManager: started IX-1 road spine on province 710417 for GER` + `EOA_SMOKE_SPINE_START visible=1 armed=1`). No toast / Building… / progress. Clock reached ~21 Feb 1936 at 1x. Then a map zoom blanked the window. Log ended at SPINE_START — **no crash trace, no SCRIPT ERROR, no quit line**.

1. `_on_build_road_spine_pressed` called `focus_province_by_id(pid)` with default **tactical 2.4** (same class as Search after +6d, already documented as a softpipe process death). Toast and button state ran **after** that zoom, so UX never painted if the process died.
2. `build_road_connection` scheduled a **full** city/sites infra rebuild that could race the zoom / RoadLayer redraw.
3. RoadLayer `_get_provinces_for_layers` added **all** major-owner hexes; `MAX_LAYER_PROVINCES` 120 never capped after majors (OOM / silent kill class during zoom redraw).
4. stdout was not flushed, so later clock / zoom lines vanished when the process died.

Not the smoke harness calling quit (stay-alive `no_quit=1` was already on). The harness now logs `EOA_HARNESS_QUIT reason=…` for any intended quit.

Headless CompleteTest hang (same revision): first progress toast after 90% called `LeaderEventUI.show_toast` without `_should_skip_toast_ui` (known `-s` CanvasLayer/timer hang). `advance_daily_projects` could also run the 3520×N AI consider while the spine was active.

## What changed

1. Toast + **Building…** (disabled) **before** any camera work; persists while the project runs (graphical Play).
2. Spine start soft-pans only. `focus_province_by_id` default is **soft**; leftover tactical is redirected (`tactical_redirected_soft`).
3. `EOA_ZOOM_BEGIN` / `EOA_ZOOM_END` on MapRenderer + CameraController, flushed via `OS.flush_stdout`.
4. Road writes use **light** RoadLayer rebuild (not full city/sites). Rebuild is re-entrancy-guarded; IX-1 corridor IDs are force-included; major-owner paint is capped at 120.
5. Köln panel `LabelSpineProgress` + invest bar when spine is active; `EOA_SMOKE_SPINE_PROGRESS` / `EOA_SMOKE_SPINE_COMPLETE`.
6. `HeadlessIx1RoadSpineCompleteTest` — start→complete days=36, visual states queued→construction→built, RoadLayer Bonn–Köln–Leverkusen, Essen off-spine + higher move cost, zoom+preview redraw stays alive.
7. TestRunner `_quit_logged` — no silent `get_tree().quit` outside that helper. Stay-alive still suppresses smoke-window quits.
8. Headless `show_toast` no-ops; spine complete sim skips full-board AI invest.
9. Optional: hide Steel/Al before they clip Search at ~1280px.
10. **(c) three visual states** on Bonn–Köln–Leverkusen (IDs unchanged): **queued** faint dashed `_draw`; **construction** hatched/partial line advancing with `%`; **built** existing RoadLayer. `EOA_SMOKE_SPINE_STATE state=queued|construction|built pid=…`. Preview is `Ix1SpinePreviewDraw` (2 edges, no Line2D children). Zoom only toggles visibility / `queue_redraw` — never `rebuild_road_layer`. CompleteTest asserts queued → construction → built in order.

Sticky Search / stay-alive / catch-up / hatch / `EOA_SMOKE_SPINE_START` **kept**. Corridor IDs unchanged (Köln 710417, Bonn 710416, Leverkusen 710418, Essen 710403). Dig2/G / rail / industry PARKED.

## Road effects (proposal, later)

Proposal only — **no code in this revision**. Built-state movement discount already exists (`ROAD_SPINE_INFRA_BONUS`). Do not wire these until Scott asks; do not invent a new dual package.

| Effect | Fits current systems? | Hook (or none) | Rough number |
|--------|------------------------|----------------|--------------|
| Faster movement through the province | **Yes — already shipped on complete** | `Province.get_movement_cost` / `get_effective_infrastructure_for_movement` (`ROAD_SPINE_INFRA_BONUS` 2.0 + `ROAD_SPINE_NEIGHBOR_BONUS` 0.5); `FormationMovement._infra_unit`; `SupplyPathfinder` already consumes move cost | Extra **−12%** move cost / **+15%** hop speed on-spine vs same-infra off-spine (on top of today's bonus, or as a documented target if we retune) |
| More resource output leaving the province | **Partial** | `ProductionManager.daily_resource_harvest_tick` + `Province.resources` / `ResourceHarvestCalculator`. **No** dedicated export-throughput field today; harvest is deposit × occ × plants, not a road leave-rate | Harvest leave-rate **+10–15%** on spine hexes only |
| Faster supply distribution | **Yes, unused by roads today** | `SupplyManager` depot `infra_factor` (`0.8 + hub.infrastructure * 0.04`) does **not** read `built_road_neighbors`; path cost already cheaper via `SupplyPathfinder` + `get_movement_cost` | Depot throughput **+8–12%** when hub or edge is on-spine |
| Less fuel for units passing through | **No land-hex fuel** | `Formation.fuel_level` exists; `SupplyManager` burns/refuels **naval** fuel only. No land-fuel-per-hex | **−8%** fuel burn if a land-hop fuel tick is wired later |

Keep the existing Essen control: off-spine hexes get none of the above. Visual states (queued / construction / built) stay presentation-only until a later slice.

## Play launch

```bash
tools/eoa_play_f5_smoke_auto_begin.sh
```

The smoke harness is **not** the product. Product Begin / Esc / mouse CC / 4x / clock stay **FAIL**. Play-F5 delivery stays **UNFIXED**.

## Headless (this revision, SCRIPT ERROR 0)

| Test | Result |
|------|--------|
| `test_ix1_road_spine_product` | 15/15 OK |
| `HeadlessIx1RoadSpineCompleteTest` | RESULT=PASS · days=36 · states queued→construction→built · RoadLayer Bonn–Köln + Köln–Leverkusen · Essen off |
| `HeadlessIx1RoadSpineMandateGateTest` | PASS (failures=0) |
| `HeadlessIx1RoadSpineDayTickTest` | RESULT=PASS |
| `HeadlessIx1SearchGoInspectorTest` | RESULT=PASS |
| `HeadlessIx1LivingTitleEscBeginTest` | RESULT=PASS |
| pick harness accurate | ok=true |
| `HeadlessWorldAccurateMultiFrontAssaultTest` | PASS (failures=0) |
| `HeadlessWorldAccurateUnitOrderLoopTest` | RESULT=PASS |

`--quick` `unit_board_play_path` still has pre-existing living-unit product fails (`air_region_cas`, `peace_occupation`, `nation_era_next`, `map_country_select`, `playtest_clock`) — not this spine slice.

## Next

Scott rebound Play on the GitHub head after this STATUS. PR 55 stays draft **HOLD**. No merge.
