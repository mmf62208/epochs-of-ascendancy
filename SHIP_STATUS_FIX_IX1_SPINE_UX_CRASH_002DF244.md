# STATUS — FIX IX-1 spine UX + silent exit after zoom — tip `002df244`

Updated: Fri Sep 25, 2026
From: Ship · CA (this run)
PR 55 HOLD: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 · branch `cursor/ix1-road-spine-9d9b` · draft

## Verdict: machine FIX (Play rebound still required)

Start tip: `002df244b3df91ca358be7c44e7314ddb2e430c4`

## Root cause (silent Godot exit)

Play MIXED `002df244`: Search→Köln→Go + spine visible PASS; start **logic** PASS (`InfrastructureDevelopmentManager: started IX-1 road spine on province 710417 for GER` + `EOA_SMOKE_SPINE_START visible=1 armed=1`). No toast / Building… / progress. Clock reached ~21 Feb 1936 at 1x. Then a map zoom blanked the window. Log ended at SPINE_START — **no crash trace, no SCRIPT ERROR, no quit line**.

1. `_on_build_road_spine_pressed` called `focus_province_by_id(pid)` with default **tactical 2.4** (same class as Search after +6d, already documented as a softpipe process death). Toast and button state ran **after** that zoom, so UX never painted if the process died.
2. `build_road_connection` scheduled a **full** city/sites infra rebuild that could race the zoom / RoadLayer redraw.
3. stdout was not flushed, so later clock / zoom lines vanished when the process died.

Not the smoke harness calling quit (stay-alive `no_quit=1` was already on). The harness now logs `EOA_HARNESS_QUIT reason=…` for any intended quit.

## What changed

1. Toast + **Building…** (disabled) **before** any camera work; persists while the project runs.
2. Spine start soft-pans only. `focus_province_by_id` default is **soft**; leftover tactical is redirected (`tactical_redirected_soft`).
3. `EOA_ZOOM_BEGIN` / `EOA_ZOOM_END` on MapRenderer + CameraController, flushed via `OS.flush_stdout`.
4. Road writes use **light** RoadLayer rebuild (not full city/sites). Rebuild is re-entrancy-guarded; IX-1 corridor IDs are force-included.
5. Köln panel `LabelSpineProgress` + invest bar when spine is active; `EOA_SMOKE_SPINE_PROGRESS` / `EOA_SMOKE_SPINE_COMPLETE`.
6. `HeadlessIx1RoadSpineCompleteTest` — start→complete, RoadLayer Bonn–Köln–Leverkusen, Essen off-spine + higher move cost, zoom+redraw stays alive.
7. TestRunner `_quit_logged` — no silent `get_tree().quit`. Stay-alive still suppresses smoke-window quits.
8. Optional: hide Steel/Al before they clip Search at ~1280px.

Sticky Search / stay-alive / catch-up / hatch / `EOA_SMOKE_SPINE_START` **kept**. Corridor IDs unchanged (Köln 710417, Bonn 710416, Leverkusen 710418, Essen 710403). Dig2/G / rail / industry PARKED.

## Play launch

```bash
tools/eoa_play_f5_smoke_auto_begin.sh
```

The smoke harness is **not** the product. Product Begin / Esc / mouse CC / 4x / clock stay **FAIL**. Play-F5 delivery stays **UNFIXED**.

## Headless

Existing IX-1 headless + new CompleteTest + `test_ix1_road_spine_product`. Require SCRIPT ERROR **0**.

## Next

Scott rebound Play on the GitHub head after this STATUS. PR 55 stays draft **HOLD**. No merge.
