# STATUS — FIX IX-1 spine press hangs main thread + OOM (windowed only) — start tip `9ebd17f`

Updated: Fri Sep 25, 2026
From: Ship · CA (this run)
PR 55 HOLD: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 · branch `cursor/ix1-road-spine-9d9b` · draft

## Verdict: machine FIX (Play rebound still required)

Start tip: `9ebd17f109f0060b9b2ae14d418ae8856844d97a`
**GitHub head.sha (verified after headless 5/5 + xvfb frame guard):** see the follow-up STATUS-pointer commit on `cursor/ix1-road-spine-9d9b`.

## Root cause (kernel OOM, not a crash)

Play FAIL `9ebd17f`: Search→Köln→Go PASS; spine **logic** PASS (`started IX-1 road spine on province 710417` + `EOA_SMOKE_SPINE_STATE queued` + `EOA_SMOKE_SPINE_START visible=1 armed=1`). No toast / Building… / progress on screen. Clock frozen 14 Jan 1936 20:00. Frames byte-identical after the press. No `EOA_ZOOM_BEGIN/END`. Then kernel OOM:

| When | pid | anon-rss |
|------|-----|----------|
| earlier tip | 1164433 | 8.3 GB |
| `002df244` | 1242086 | 9.4 GB |
| `9ebd17f` | 1297892 | 9.9 GB |

Headless 5/5 stayed PASS (DisplayServer skips the canvas `_draw` path).

The press logged button state, then `show_info_panel` flushed the windowed canvas. `Ix1SpinePreviewDraw._draw` painted **absolute** GIS cents (Köln ~4254,944; Bonn/Leverkusen edges only 3–8 world units) with **antialiased** `draw_line`. That blows the CanvasItem AABB to a multi-thousand-unit box on llvmpipe and can spin/allocate without returning to the frame loop. `notify_province_changed("infrastructure_project")` also scheduled a light RoadLayer/sites rebuild on start (no built edges yet). A dash/hatch `while` with a 0/NaN step would never advance — hard caps were incomplete.

Isolated xvfb repro of two short AA dashes at those cents **did** keep ticking (~300 frames/s). The live hang is the same `_draw` **inside the full map tree** after the press flush (preview + overlay + inspector), not a harness quit.

## What changed

1. Preview draws **hub-local** (`position = hub centroid`) so the AABB is ~8u, not a 4k×1k world box.
2. Dash/hatch loops: `is_finite` reject, `IX1_PREVIEW_MIN_STEP`, `IX1_PREVIEW_MAX_SEGS` / `MAX_HATCHES`, **no** antialiased `draw_line`. Re-entrant `queue_redraw` from `_draw` blocked.
3. Toast + **Building…** on the press frame; `show_info_panel` + soft-pan `call_deferred` (`_ix1_spine_start_after_first_frame`).
4. Preview notify is **sync** (hub-local `_draw` is cheap; CompleteTest construction same-tick). Spine start/progress does **not** light-rebuild RoadLayer/sites (preview only). Rail ties capped (`MAX_RAIL_TIES_PER_EDGE`).
5. Windowed guard: `tools/eoa_ix1_spine_frame_guard.sh` (xvfb) · `EOA_SMOKE_FRAME_GUARD frames=… rss_mb=… PASS|FAIL` · frames keep advancing · RSS < 2 GB for 60 s after a simulated press.

## Verified evidence (this run)

| Gate | Result |
|------|--------|
| `test_ix1_road_spine_product` | 15/15 OK |
| Headless IX-1 5/5 (`Mandate` / `DayTick` / `SearchGo` / `LivingTitle` / `CompleteTest`) | PASS · SCRIPT_ERROR 0 |
| xvfb `eoa_ix1_spine_frame_guard.sh` 60 s | **PASS** · frames **16488** · sidecar RSS **370 → 1317 MB flat** (under 2 GB; pre-fix Play OOM 8.3 / 9.4 / **9.9 GB**) |
| xvfb guard 8 s (RSS reader confirm) | **PASS** · `EOA_SMOKE_FRAME_GUARD frames=2389 rss_mb=1314 PASS` · sidecar_max **1314** |

Smoke harness is **not** the product. Product Begin / Esc / mouse CC / 4x / clock stay **FAIL**. Play-F5 stays **UNFIXED**.

Three corridor states, progress/ETA, CompleteTest, sticky Search, stay-alive, catch-up, smoke auto-begin hatch, `EOA_SMOKE_SPINE_START` **kept**. Corridor IDs unchanged.

## Play launch

```bash
tools/eoa_play_f5_smoke_auto_begin.sh
```

The smoke harness is **not** the product. Product Begin / Esc / mouse CC / 4x / clock stay **FAIL**. Play-F5 delivery stays **UNFIXED**. Road effects stay proposal-only.

## Next

Scott rebound Play on the GitHub head after this STATUS. PR 55 stays draft **HOLD**. No merge.
