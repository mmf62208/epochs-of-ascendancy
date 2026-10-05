# March dest pick at lower zoom (Heidekreis)

**HOLD merge.** Headless + xvfb ≠ live Play. No product change unless a fresh interior screen misses.

## Symptom (live smoke, soft)

A march from selected own unit (GER Garrison 4) aimed at Heidekreis `710380`:

| zoom | logged dest |
|---|---|
| ~0.80 | `Harz` hops=6 days=8 **or** `Börde` hops=7 days=10 |
| ~1.50 | `pick commit dest=710380` · `move_commit Heidekreis hops=7 days=10` |

## Why this is not a 1-hex product offset

Heidekreis neighbors are Diepholz / Nienburg / Hannover / Celle / Harburg / Lüneburg / Rotenburg / Stade / Uelzen / Verden. **Harz `710517` and Börde `710515` are not adjacent.** A few-pixel screen-to-world or hex miss at the interior would land on a neighbor, not Saxony-Anhalt.

Those dests sit well south of Heidekreis, toward Europe Home / Köln. That is the geometry of **reusing a z=1.50 screen point after zooming out** (same pixel maps closer to camera center).

## Product contract (this slice)

A known GIS-interior screen point, recomputed at the current zoom, must pick that province at z **0.32 / 0.80 / 1.50**. March commit uses `_map_pick_screen_pos` (`event.position`) → `_screen_to_world` (camera canvas inverse) → `_mv1_event_province_pid` / `_mv1_re_resolve_commit_pid` (GIS re-resolve; MV-1e).

Shared chip / spill / title / Fill% pick code is **untouched**.

## Guards

- `HeadlessMarchZoomDestPickTest` + `tools/eoa_march_zoom_pick_guard.sh`
- Windowed 1280×740 `tools/eoa_march_zoom_pick_windowed_check.sh`
