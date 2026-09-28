# RT-1 — Readable road tiers (intact only)

**Status:** draft · **HOLD merge** · visual only · base `497731dd` (GS-1 KEEP).  
**Scope:** Phase 1 of `EOA_ROAD_TIERS_DAMAGE_LOGISTICS_SPEC` — dirt / paved / highway look, zoom LOD, batched `_draw`. No damage, no gameplay, no logistics pathing.

The smoke harness and headless guards are **not** a live product Play PASS.

**Harness (tip `b437cb70`, not product Play):** headless tier / edge-filter / no-rebuild **RESULT=PASS**. Windowed `tools/eoa_rt1_pixel_guard.sh` **RESULT=PASS** (S1 gold_cover=1.000, hex after close=0, S2 labels, 3×3 captures=15). RSS peak **2027 MB** (xvfb llvmpipe). Every new guard **FAIL** on `497731dd` (missing `RoadTierVisual.gd` / `RoadTierDraw`).

## What changed

| Item | Tip |
|------|-----|
| Tier formula | Same era-relative rule as `_rebuild_road_layer_inner` (`road_infra_min` / +3 / +6; explicit `built_road_neighbors` ⇒ highway). Extracted to `RoadTierVisual.road_tier_for_edge`. |
| Looks | Screen-pixel strokes: dirt ~2 px dashed tan; paved ~3.5 px mid-grey + 1 px edge; highway ~5.5 px dark casing + light stripe. |
| LOD | Far / default / close. Widths recomputed in `_draw` from zoom. Dirt hides below zoom 0.22. No cache rebuild on zoom. |
| Batching | One `RoadTierDraw` node per tier. Per-edge `Line2D`s remain only as hidden explicit lookup stubs (`find_road_node` / IX-1 reports). |
| Edge filter | Shared-border from quantized rings when geometry exists; else Rhineland centroid-gap cap **11.0**. Must-draw Bonn–Köln / Köln–Leverkusen. Must-not Köln–Essen / Köln–Düren. |
| Visibility | Intact tiers on the political map inside the NUTS3 id block (`710000–799999`). Infra mode keeps its extras. |
| Gold spine | Unchanged z=23, 9 px gold on 13 px halo. Highway casing may sit under it. |
| S1 | Selection outline z=22 (below spine). Cleared on `hide_info_panel`. |
| S2 | Small "Bonn" / "Leverkusen" end labels at mid/close (`zoom >= 0.55`). |
| S3 | Hover-exit now clears compare-candidate / preview rings (salmon/orange leftover west of the Rhine). |

**Not in this slice:** damage states, move-cost scaling, construction UI, other boards.

## Guards

```bash
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadTierForEdgeTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadEdgeFilterTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadNoRebuildTest.gd
tools/eoa_rt1_pixel_guard.sh   # xvfb; NOT product Play
```

The windowed guard dismisses the living title via `EOA_SMOKE_AUTO_BEGIN` (never `EOA_SKIP_TITLE`), then waits on `TimeManager.living_title_has_closed` / the TestScenario scene meta — the scene root is not named `TestRunner`. Companion `EOA_SMOKE_ADVANCE_PAST_PLUS6=0` keeps January 1936 for the 3×3 matrix.

Every new guard must **FAIL on 497731dd** and **PASS on tip**.

Kept regressions: GS-1 spine continuity (`tools/eoa_rx1_pixel_guard.sh`), RX-1 river sample, units-on chip-over-spine, Search→Go (`HeadlessIx1SearchGoInspectorTest`).
