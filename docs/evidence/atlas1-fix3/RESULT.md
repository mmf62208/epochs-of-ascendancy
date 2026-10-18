# ATLAS-1 FIX #3 — live Ruhr labels after Begin (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. Do not merge.

**FIX #3 tip:** `005d10fb`
**On top of FIX #2:** `f9cac5f9`

Box gate on `f9cac5f9` was green. The playtester's live run on that tip was MIXED, leaning FAIL: Essen missing at z1.217/1.512, close-zoom overlaps/ghosted doubles, air-wing covering Essen/Hamm. Isolated headless tests had been passing a different view.

Hard rules kept: no `world_full` ID renumber; Godot only via `tools/run_godot.sh` (one instance); Prod files not touched.

---

## Root causes (live ≠ headless)

1. **Wrong camera path.** Isolated tests (and the first live harness) called `set_view` / `lock_pixel_guard_camera` onto Essen or Home-in-place. Play is Home 0.787 then `_zoom_toward_mouse` at (455,455). Jumping to Essen recentred the Ruhr; zooming in place left Essen under chips. Wheel at a screen pixel that is *not* the Ruhr on this Home frame flew to France by z2.904.
2. **Empty counter overrides.** `set_view(..., [], [])` froze obstacles to nothing. Live Play after Begin has ~250 DemoUnitIcon chips (70 on-screen at z1.217), including air-wing plates.
3. **Chip AABB space.** Obstacle rects used `(world - cam) * zoom + vp/2` and merged designation text into 400px boxes. Packing did not see the plates the player sees.
4. **Draw order.** City names at z 19 sat under DemoUnitIcon z 28 (only "Ess" visible). Dots at z 46 sat on Essen.
5. **Close-zoom last-resort.** Hub 120px slots stacked Duisburg/Herne/Dortmund. Outline px was not in the collision pad, so touching names looked doubled.
6. **Second name draw.** `MapRenderer._province_name_labels` at tactical zoom redrew Köln/Essen on top of `CityLabelsLayer` (already hidden in this FIX).

Not: 36 wu cluster drop, alias dedupe, set stability, Paris/capitals (those stayed PASS).

---

## What changed

`CityLabelsLayer.gd`

- Names z 30 / dots z 29 (above chips 28, under capital stars 40).
- Counter AABBs from `get_global_transform_with_canvas` on the plate (not designation text).
- Ruhr cores (Essen, Köln, Düsseldorf, Duisburg, Dortmund) stay by their dots; Essen remains `must_keep`.
- Close zoom culls instead of 120px last-resort. Collision grows by outline pad; labels shift off neighbour dots.
- Layout camera args are applied inside `place_competing` so isolated fixtures match live packing.

`MapRenderer.gd`

- `player_path_wheel_toward_world` uses the same pan math as `_zoom_toward_mouse`, keyed on world (no racy mouse warp).
- Legacy `_province_name_labels` stay hidden while CityLabelsLayer is on.

Tests

- Isolated Essen/overlap/home-cam cases inject air-wing-sized plates, not empty arrays. Doubled-name/pid check kept.
- `HeadlessAtlas1LiveRuhrTest`: TestScenario after Begin, units ON, Home 0.787, wheel toward Essen (the Ruhr under the playtester's wheel). Fails if zoom does not stick, Essen is off-screen, names overlap, names double, or legacy Labels are visible. xvfb 1280×800 shots at z1.217 / 1.512 / 2.904.

---

## Commands and results

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix3 tools/eoa_atlas1_live_ruhr.sh
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix3 tools/eoa_atlas1_pixel_guard.sh
tools/eoa_full_test_gates.sh --quick
```

| Claim | Result | Log |
|---|---|---|
| Isolated city labels + FIX #1/#2 tests | **PASS** | `HeadlessAtlas1CityLabelsTest: RESULT=PASS` candidates=2050 `build_ms=154.8` |
| Essen + Ruhr cores at Home-cam z1.217/1.512 with chips | **PASS** | isolated; Essen, Köln, Duisburg, Düsseldorf, Dortmund |
| Doubled draws / legacy Labels | **PASS** | isolated + live `no doubled names` / `no legacy province-name draw` |
| Live Begin + 250 counters, wheel from Home 0.787 | **PASS** | `HeadlessAtlas1LiveRuhrTest: RESULT=PASS` `cam_z=1.216/1.511/2.903` `essen_s≈607,189` |
| Close overlap z2.3–2.904 | **PASS** | isolated + live `has_visual_overlap` |
| Rivers | **PASS** | `build_ms=161.7` |
| Pixel guard | **PASS** | `WindowedAtlas1PixelGuard: RESULT=PASS` `reasons=[]` |
| Essen cream-run (units ON) | **PASS** | mid/close cam-on-Essen run=16/8; live wheel z1.217/1.512/2.904 run=8/8/8 |
| Paris mid/close | **PASS** | run=13 / run=16 |

`--quick`: **14** known `unit_board_play_path` reds, no new ones. `map_qc` NE **0.9853** (3148/3195).

Seed was not re-run (city-label only). `HeadlessPerf4LiveMultiAiDayTest` seed `20fe9063` is untouched.

---

## Pixel shots

From this run (`docs/evidence/atlas1-fix3/`):

- `live_ruhr_z1217.png` / `z1512.png` / `z2904.png` — xvfb 1280×800 after Begin, units ON, Home 0.787 then wheel toward Essen. Layout at all three zooms includes Essen, Köln, Duisburg, Düsseldorf, Dortmund. Essen stays near screen (607, 189).
- `tip_live_ruhr_z1217.png` / `z1512.png` / `z2904.png` — 1920×1080 pixel-guard copies of the same wheel path.
- `tip_mid_paris.png`, `tip_close_ruhr.png`, `tip_mid_danube.png` — FIX #2 surfaces still PASS.

z1.217 on 1280×800 is still a Europe frame (1280/1.217 ≈ 1052 wu). The playtester's Ruhr cluster is in that frame with Essen labelled. z2.904 tightens on the Rhine around Essen.

**Merge HOLD** until live Play.
