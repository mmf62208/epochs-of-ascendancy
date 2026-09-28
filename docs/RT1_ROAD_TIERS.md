# RT-1 — Readable road tiers (intact only)

**Status:** draft · **HOLD merge** · visual only · base `497731dd` (GS-1 KEEP).  
**Scope:** Phase 1 of `EOA_ROAD_TIERS_DAMAGE_LOGISTICS_SPEC` — dirt / paved / highway look, zoom LOD, batched `_draw`. No damage, no gameplay, no logistics pathing.

The smoke harness and headless guards are **not** a live product Play PASS.

**Harness (FIX #2, not product Play):** headless tier / edge-filter / no-rebuild **RESULT=PASS**. Seeded windowed `tools/eoa_rt1_pixel_guard.sh` still covers S1/S2. `tools/eoa_rt1_live_look_guard.sh` samples the **unseeded 1936 board** through the **player camera path** (Europe Home → Search/Go Köln → `_zoom_toward_mouse`). Mesh/triangle density at Europe + mid + close. Gold on-screen width vs cased highway. Must **FAIL on 79de1c6** (full shared-border triangle mesh); **PASS on tip**. xvfb ≠ product Play.

## What changed

| Item | Tip |
|------|-----|
| Tier formula | Same era-relative rule as `_rebuild_road_layer_inner` (`road_infra_min` / +3 / +6; explicit `built_road_neighbors` ⇒ highway). Extracted to `RoadTierVisual.road_tier_for_edge`. |
| Looks | Screen-pixel strokes: dirt ~2.6 px dashed tan; paved ~4 px solid; highway ~8.5 px dark casing + pale stripe. 1936 highways = explicit + top ~4% of the **visual trunk** (not terciles — those painted NL/UK/BE as highways). Formula `tier` unchanged. |
| Visual network | Shared-border candidates → nearest 1–2 neighbours → degree-capped Kruskal forest. Gameplay adjacency / movement / formula stay intact. Far: rare highways. Mid: paved+highway of the tree. Close: + dirt. |
| LOD | Europe/Home (`zoom <= 1.15`): rare highways only. Mid: paved+highway. Close (`>= 2.60`): dirt too. No cache rebuild on zoom. |
| Batching | One `RoadTierDraw` node per tier. Per-edge `Line2D`s remain only as hidden explicit lookup stubs (`find_road_node` / IX-1 reports). |
| Edge filter | Shared-border from quantized rings when geometry exists; else Rhineland centroid-gap cap **11.0**. Must-draw Bonn–Köln / Köln–Leverkusen. Must-not Köln–Essen / Köln–Düren. |
| Visibility | Intact tiers on the political map inside the NUTS3 id block (`710000–799999`). Infra mode keeps its extras. |
| Gold spine | z=23, **16 px** non-AA filled quads on 20 px halo (MapCamera zoom). Must read thicker than 8.5 px casing at mid and close. Never `draw_line(..., true)` (IX-1 windowed OOM). |
| S1 | Selection outline z=22 (below spine). Cleared on `hide_info_panel`. |
| S2 | Constant-screen 14 px Labels on a **CanvasLayer** (same outline family as political map labels). Visible at `zoom >= 2.60`. |
| S3 | Hover-exit now clears compare-candidate / preview rings (salmon/orange leftover west of the Rhine). |

**Not in this slice:** damage states, move-cost scaling, construction UI, other boards.

## Guards

```bash
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadTierForEdgeTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadEdgeFilterTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadNoRebuildTest.gd
tools/eoa_rt1_pixel_guard.sh       # xvfb seeded 3×3; NOT product Play
tools/eoa_rt1_live_look_guard.sh   # xvfb unseeded looks + Europe density
```

The windowed guard dismisses the living title via `EOA_SMOKE_AUTO_BEGIN` (never `EOA_SKIP_TITLE`), then waits on `TimeManager.living_title_has_closed` / the TestScenario scene meta — the scene root is not named `TestRunner`. Companion `EOA_SMOKE_ADVANCE_PAST_PLUS6=0` keeps January 1936 for the 3×3 matrix.

Every new mesh/triangle check must **FAIL on 79de1c6** and **PASS on tip**. xvfb ≠ product Play.

Kept regressions: GS-1 spine continuity (`tools/eoa_rx1_pixel_guard.sh`), RX-1 river sample, units-on chip-over-spine, Search→Go (`HeadlessIx1SearchGoInspectorTest`).
