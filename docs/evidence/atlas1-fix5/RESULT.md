# ATLAS-1 FIX #5 — drop Ruhr hub flags; mid-zoom cores off chips (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. **Merge HOLD** until live Play.

**FIX #5 tip:** `7c6a7cd7` + this evidence commit
**Base:** `origin/main` `05602912` (via `f5f502fe`)

Box gate on `c482d00a` was NOT READY: two HWY-3 regressions (`Hwy3HubRoute` FAIL 4, `Hwy3LiveScenario` FAIL 1) from `"hub": true` on Düsseldorf / Duisburg / Essen / Dortmund. Both tests PASS on main `05602912` and on a mutant with only those four flags removed.

Hard rules kept: seed `20fe9063` unedited; no `world_full` ID renumber; Godot 4.7.1 via `tools/run_godot.sh` only; Prod / TopInfoBar / GameData unedited; no Godot bump; no force-push.

---

## Root causes

1. **HWY-3 routing.** FIX #4 added `"hub": true` on 710401 / 710402 / 710403 / 710443. `InfrastructureOverlayLayer` reads that as HWY-3 `city_hub`, so four extra hubs reshaped routes (Köln off, GER 2 components, Paris 3 north lines, duplicate Paris→Lille).
2. **Duisburg on the Dutch stack.** The keep-name second pass ignored unit plates, so flush-left Duisburg sat on the L100 / Air Wing AABB at z1.217 / 1.512.
3. **Live harness ≠ Play.** Pre-pan Essen onto (455,455) walked into France if that pixel was held from Home; mid-zoom did not require all five Ruhr cores.

---

## What changed

`data/provinces_world_accurate/province_city_layer.json`

- Removed `"hub": true` from Düsseldorf, Duisburg, Essen, Dortmund only. Köln `710417` stays a hub (same as main).

`CityLabelsLayer.gd`

- Ruhr cores stay keep-names via `_RUHR_CORE` (no JSON hub flag).
- Chip-clear walk out to 80 px. Ignore-chips second pass is capitals/must-keep only.
- No on-mark last-resort onto a plate.

`HeadlessAtlas1LiveRuhrTest.gd` / `WindowedAtlas1PixelGuard.gd`

- Home, no Essen pre-pan. Each wheel notch re-aims on Essen world (`player_path_wheel_toward_world`).
- Lands on WHEELDRIFT-1 notches about 1.217 / 1.512 / 2.904 (slack 0.14).
- All five cores required at every live zoom; fail if a core sits on a counter.

`InfrastructureOverlayLayer.gd`

- `get_hub_city_label_names` / `get_visible_hub_label_rects` proxy ATLAS-1 placed names when `CityLabelsLayer` exists. Isolated HWY-3 without that layer still uses Hwy3Hub Labels.

---

## Commands and results

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3HubRouteTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3LiveScenarioTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix5 tools/eoa_atlas1_live_ruhr.sh
EOA_ATLAS1_PIXEL_OUT=/tmp/eoa-atlas1-pixel tools/eoa_atlas1_pixel_guard.sh
EOA_HWY3_RUHR_OUT=/tmp/eoa-hwy3-ruhr tools/eoa_hwy3_ruhr_legibility_guard.sh
tools/eoa_full_test_gates.sh --quick
```

| Claim | Result | Log |
|---|---|---|
| Hwy3HubRoute | **PASS** | `HeadlessHwy3HubRouteTest: RESULT=PASS` failures=0. Köln on a hub route; GER one tree |
| Hwy3LiveScenario | **PASS** | `HeadlessHwy3LiveScenarioTest: RESULT=PASS` failures=0. Paris one north line `Paris → Val-d’Oise → Oise → Somme → Lille`; Köln alias; Ruhr 3 of Duisburg/Essen/Dortmund |
| Isolated city labels | **PASS** | `HeadlessAtlas1CityLabelsTest: RESULT=PASS` candidates=2050 `build_ms=148.7`. Five cores at Ruhr-cam 1.217 / 1.512 / 2.904 |
| Rivers | **PASS** | `HeadlessAtlas1RiversTest: RESULT=PASS` `build_ms=171.4` (under 200 with `EOA_SLOW_BOX=1`) |
| Hwy1HighwayChain | **PASS** | failures=0 |
| Hwy3SupplyToggleCache | **PASS** | failures=0 |
| Live Begin + counters, Home, wheel toward Essen | **PASS** | `HeadlessAtlas1LiveRuhrTest: RESULT=PASS` failures=0. home_z=0.344 wheel on Essen pixel (not 455,455; dist455=628.2). cam_z **1.270 / 1.578 / 3.031**. Five cores + clear of counters at all three; HWY-3 Labels hidden; no overlap/doubles |
| Pixel guard | **PASS** | `WindowedAtlas1PixelGuard: RESULT=PASS` `reasons=[]`. Essen run 8/11; Paris 13/16; live-wheel 8/8/22; Danube 70 |
| HWY-3 Ruhr legibility (labels via ATLAS-1) | **PASS** | z2.4 casing 187 / 3 names Essen, Duisburg, Dortmund; z4.0 casing 311 / 4 names + Düsseldorf. `mutant_labels_off` before=4 after=0 killed |
| `--quick` | **14** known reds | `unit_board_play_path` FAILED (failures=**14**), same pick/chrome/fill-toe/living-loop set. map_qc NE **0.9853** (3148/3195). unit_save_path / hoi_matrix / air_physics_p1 OK |
| SCRIPT ERROR | **0** | none in HubRoute, LiveScenario, city, rivers, live Ruhr, pixel, Hwy3 Ruhr, Hwy1, SupplyToggle |

Seed was not re-run (city-label / packing / JSON hub flags only). `HeadlessPerf4LiveMultiAiDayTest` seed `20fe9063` is untouched.

---

## Pixel / live shots (inspected before claiming)

All 1280×800. Live-test captures are `live_ruhr_z*.png`.

- **z1.217** (`live_ruhr_z1217.png`): Essen, Dortmund, Duisburg, Düsseldorf, Köln all placed. Duisburg sits beside (not on) the Dutch L100/Air Wing stack. Köln is readable.
- **z1.512** (`live_ruhr_z1512.png`): All five cores clear of counters. Dortmund is labelled (the FIX #4 miss).
- **z2.904** (`live_ruhr_z2904.png`): Geographic N/S: Dortmund / Essen north, Düsseldorf / Köln south, Duisburg west. Cream outlines, dark fill, full opacity.

Discrete WHEELDRIFT-1 notches from Play Home ~0.344 are 1.270 / 1.578 / 3.031. The live test allows 0.14 slack around 1.217 / 1.512 / 2.904.

---

## Merge HOLD

Headless + xvfb, **not** live Play. Do not merge until a human Homes on 1280×800 and wheels the Ruhr at those three zooms.
