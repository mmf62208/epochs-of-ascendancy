# RT-1 — Readable road tiers (intact only)

**Status:** draft · **HOLD merge** · visual only · base `94295fc` (RT-1 KEEP).  
**Scope:** Phase 1 of `EOA_ROAD_TIERS_DAMAGE_LOGISTICS_SPEC` — dirt / paved / highway look, zoom LOD, batched `_draw`. **RT-1b** is **gold-only**: mid gold 1.8× highway (28/34). No `ProvEdge_` hide, no border-LOD force, no overlay extras. No damage, no gameplay, no logistics pathing.

The smoke harness and headless guards are **not** a live product Play PASS.

**Harness (FIX #2, not product Play):** headless tier / edge-filter / no-rebuild **RESULT=PASS**. Seeded windowed `tools/eoa_rt1_pixel_guard.sh` still covers S1/S2. `tools/eoa_rt1_live_look_guard.sh` samples the **unseeded 1936 board** through the **player camera path** (Europe Home → Search/Go Köln → `_zoom_toward_mouse`) at **1600×900** (live Play window, not 1280×720). Mesh/triangle density at Europe + mid + close. Mid gold ≥ 1.8× highway (28/34); close gold 16/20 unchanged. Sage-web pixel frac must stay under 0.035 (the `5c60f366` live pale-green carpet). Must **FAIL on 94295fc** (mid gold 17 vs 13). Tan NUTS cells at mid are **backlog** if they are just borders. xvfb ≠ product Play.

## What changed

| Item | Tip |
|------|-----|
| Tier formula | Same era-relative rule as `_rebuild_road_layer_inner` (`road_infra_min` / +3 / +6; explicit `built_road_neighbors` ⇒ highway). Extracted to `RoadTierVisual.road_tier_for_edge`. |
| Looks | Screen-pixel strokes: dirt ~2.6 px dashed tan; paved ~4 px solid; highway **12 px** dark casing + pale stripe as **non-AA quads** (thicker than paved, thinner than gold 16). Far/Europe uses a 5.5 px casing so Home stays clean. 1936 highways = explicit + top ~4% of the **visual trunk**. Formula `tier` unchanged. |
| Visual network | Shared-border candidates → nearest 1–2 neighbours → degree-capped Kruskal forest. Gameplay adjacency / movement / formula stay intact. Far: rare highways. Mid: paved+highway of the tree. Close: + dirt. |
| LOD | Europe/Home (`zoom <= 1.15`): rare highways only. Mid: paved+highway. Close (`>= 2.60`): dirt too. No cache rebuild on zoom. |
| Batching | One `RoadTierDraw` node per tier. Per-edge `Line2D`s remain only as hidden explicit lookup stubs (`find_road_node` / IX-1 reports). |
| Edge filter | Shared-border from quantized rings when geometry exists; else Rhineland centroid-gap cap **11.0**. Must-draw Bonn–Köln / Köln–Leverkusen. Must-not Köln–Essen / Köln–Düren. |
| Visibility | Intact tiers on the political map inside the NUTS3 id block (`710000–799999`). Infra mode keeps its extras. |
| Gold spine | z=23, non-AA filled quads. **Close/far 16 px / halo 20** (Play PASS `94295fc`). **Mid only 28 px / halo 34** so measured on-screen gold ≥ **1.8×** highway. Same `_draw` as `94295fc` (caps at Bonn/Köln/Leverkusen; no miter/buffer extras). Never antialiased `draw_line` (IX-1 windowed OOM). |
| Mid NUTS cells | **Withdrawn.** Live Play `5c60f366` hid `ProvEdge_` and painted a thick sage web; a click near Köln selected Luxembourg. Internals stay as on `94295fc` (needed for pick). Closed tan cells at mid are **backlog** if they are just borders. |
| S1 | Selection outline z=22 (below spine). Cleared on `hide_info_panel`. |
| S2 | Constant-screen 14 px Labels on a **CanvasLayer**: Bonn, **Köln**, Leverkusen. Visible at mid and close (`zoom >= 1.50`). No overlap with each other or the gold hub. |
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
