# ATLAS-1 FIX #4 — merge main, one name owner, playtester wheel (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. **Merge HOLD** until live Play.

**FIX #4 tip:** `e8d647e9`
**Merge parent:** `f5f502fe` (`origin/main` `05602912`, plain merge, no force-push)

Box gate on `a28af75d` was NOT READY: conflict vs main, hand-merge failed pixel guard `essen_label_run_1` at live-wheel z2.904, HWY-3 `#104` drew a second crisp name layer, and the FIX #3 shots did not match the summary.

Hard rules kept: seed `20fe9063` unedited; no `world_full` ID renumber; Godot 4.7.1 via `tools/run_godot.sh` only; Prod / TopInfoBar files not edited beyond the merge; no Godot bump; no GameData rewrite.

---

## Root causes

1. **Wheel conflict.** Main `#105` (WHEELDRIFT-1) and `#106` (EDGE-2) rewrote `_zoom_toward_mouse(factor, screen_pos)`. ATLAS-1 still had `_zoom_toward_screen` / overshoot clamp. Isolated tip passed; merge failed.
2. **Two name owners.** `#104` Hwy3HubCityLabels (CanvasLayer 19, `follow_viewport=false`) painted crisp white Duisburg / Dortmund / Essen / Düsseldorf / Köln on top of ATLAS-1. The doubled-name check only looked at `CityLabelsLayer._placed`.
3. **Live harness ≠ playtester.** Tests wheeled toward Essen (HUD y≈189) or `lock_pixel_guard_camera`, not screen `(455,455)` on 1280×800 with Map Mode + notice open. They checked the placed-name list, not pixels / UI / HWY-3 Labels.
4. **Close glyphs.** World-space `px/z` `draw_string` was blurry and faded. 120 px last-resort put labels ~75 px east of their dots. Duisburg packed south of Köln when Essen took flush-left.
5. **Pixel-guard cream.** A 12 px disc on the city mark missed the glyph (chip on the dot → `essen_label_run_1`). Searching only the glyph box missed the filled mark (`paris_label_run_2`, AA outline run=2). Guard ran at 1920×1080; wheel at (455,455) is 505 px left of center, so theater clamp walked Essen to x=67 (`essen_label_run_0`).

Not: 36 wu cluster drop, alias dedupe, Paris/capitals (those stayed PASS). Overlay routing vs main is label-suppress only.

---

## What changed

`MapRenderer.gd`

- Plain merge kept main `_zoom_toward_mouse(factor, screen_pos)` and `_wheel_zoom_factor` (in/out exact inverses). No second zoom path, no overshoot clamp.
- `player_path_wheel_toward_screen` loops that path and keeps the closest discrete notch.
- `player_path_place_world_at_screen` zooms toward on-screen Essen until z≥0.75, then Camera2D-pans Essen onto (455,455) without theater clamp.
- `_hide_hwy3_hub_city_labels` while CityLabelsLayer is live.

`InfrastructureOverlayLayer.gd`

- `set_suppress_hub_city_labels` / `_atlas1_owns_city_names`. Isolated HWY-3 tests still boot the overlay without CityLabelsLayer, so hub Labels still resolve.

`CityLabelsLayer.gd`

- Close-zoom rasterize at screen pixels (`draw_set_transform(world, 0, 1/z)`), outline 3, full opacity.
- Ruhr cores before generic capitals; flush-left only when keep-to-the-east; never drop ruhr_keep at close.
- `duplicate_drawn_names` walks HWY-3 / any screen-space Label.

`HeadlessAtlas1LiveRuhrTest.gd`

- 1280×800, Home, place Essen on (455,455), wheel that pixel. Default UI open.
- Fail required names under UI/tooltip, >30 px from their dot, pixel overlap, or N/S order wrong.
- Essen at z1.2–1.5; Essen / Duisburg / Düsseldorf / Dortmund / Köln at z2.3–2.9.

`WindowedAtlas1PixelGuard.gd` + `tools/eoa_atlas1_pixel_guard.sh`

- 1280×800 (same as Play). Cream = filled city mark **and** glyph box, via MapCamera canvas. live_ruhr shots keep the wheeled camera (no `lock_pixel_guard_camera`).

---

## Commands and results

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix4 tools/eoa_atlas1_live_ruhr.sh
EOA_ATLAS1_PIXEL_OUT=/tmp/eoa-atlas1-pixel tools/eoa_atlas1_pixel_guard.sh
tools/eoa_full_test_gates.sh --quick
```

| Claim | Result | Log |
|---|---|---|
| Isolated city labels + FIX #1/#2/#3 tests | **PASS** | `HeadlessAtlas1CityLabelsTest: RESULT=PASS` candidates=2050 `build_ms=149.8` (under 150) |
| Doubled-name check sees HWY-3 Labels | **PASS** | isolated `doubled-name check sees HWY-3 / screen-space Labels` |
| Rivers | **PASS** | `build_ms=179.0` (under 200 with `EOA_SLOW_BOX=1`) |
| Hwy3SupplyToggleCache | **PASS** | failures=0 |
| Hwy1HighwayChain | **PASS** | failures=0 |
| Hwy3HubRoute / Hwy3LiveScenario | **FAIL** (pre-existing routing) | Köln not on hub route; Paris 3 north lines. Overlay diff vs `05602912` is label-suppress only |
| Live Begin + counters, Home, wheel (455,455) | **PASS** | `HeadlessAtlas1LiveRuhrTest` cam_z **1.270 / 1.578 / 3.031** (discrete notches; slack 0.14). dist=0.0. Essen all three; five cores + N/S at z≥2.3; HWY-3 hidden; no overlap/doubles |
| Pixel guard Essen / live-wheel / Paris | **PASS** | `WindowedAtlas1PixelGuard: RESULT=PASS` `reasons=[]`. Essen mid/close run=10/10; Paris 13/16; live-wheel 8/8/10; Danube 70 |
| `--quick` | **14** known reds | `unit_board_play_path` FAILED (failures=**14**), same pick/chrome/fill-toe/living-loop set. map_qc NE **0.9853** (3148/3195). unit_save_path / hoi_matrix / air_physics_p1 OK |

Seed was not re-run (city-label / camera-display only). `HeadlessPerf4LiveMultiAiDayTest` seed `20fe9063` is untouched.

---

## Pixel / live shots (inspected before claiming)

All 1280×800. Live-test captures are `live_ruhr_z*.png`. Pixel-guard copies are `tip_*.png`.

- **z1.217** (`live_ruhr_z1217.png` / `tip_live_ruhr_z1217.png`): Ruhr in frame, not under Map Mode / notice. UI open. Essen labelled; Duisburg, Düsseldorf, Dortmund (and Köln) visible in the western-Germany cluster. Not the FIX #3 miss (Essen/Duisburg/Düsseldorf absent, Ruhr under the top HUD).
- **z1.512** (`live_ruhr_z1512.png` / `tip_live_ruhr_z1512.png`): Five cores visible. Labels sit by their dots (not ~75 px east). Düsseldorf present. Duisburg is not south of Köln.
- **z2.904** (`live_ruhr_z2904.png` / `tip_live_ruhr_z2904.png`): Northern/central Germany with the Ruhr on the left — **not** southern Germany. Cream outlines, dark fill, full opacity, sharp (not blurry/faded). Geographic N/S: Dortmund / Essen north, Düsseldorf / Köln south, Duisburg west. A unit plate sits on the Rhine but names remain readable (z 30 above chips 28).
- **close_ruhr** (`tip_close_ruhr.png`): camera on Essen, units off. All five cores, sharp cream.
- **close_paris** (`tip_close_paris.png`): camera on Paris. Cream `Paris` on the mark.

Discrete WHEELDRIFT-1 notches at this zoom_speed are 1.270 / 1.578 / 3.031, not the exact 1.217 / 1.512 / 2.904 literals. The live test allows 0.14 slack and keeps the closest notch.

---

## Merge HOLD

Headless + xvfb, **not** live Play. Do not merge until a human wheels at (455,455) on 1280×800 after Home.
