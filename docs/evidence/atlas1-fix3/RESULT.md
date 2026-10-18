# ATLAS-1 FIX #3 — live Ruhr labels after Begin (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. Do not merge.

**FIX #3 code tip:** `8fe59618`
**On top of FIX #2:** `f9cac5f9`

Box gate on `f9cac5f9` was green. The playtester's live run on that tip was MIXED, leaning FAIL: Essen missing at z1.217/1.512, close-zoom overlaps/ghosted doubles, air-wing covering Essen/Hamm. Isolated headless tests had been passing a different view.

Hard rules kept: no `world_full` ID renumber; Godot only via `tools/run_godot.sh` (one instance); Prod files not touched.

---

## Root causes (live ≠ headless)

1. **Injected zoom.** Isolated tests (and the first live harness) called `set_live_view(1.217, …)` so layout could PASS while `MapCamera` stayed at Europe Home (~0.4). Draw used the live camera, so glyphs and collision did not match.
2. **Empty counter overrides.** `set_view(..., [], [])` froze obstacles to nothing. Live Play after Begin has ~250 DemoUnitIcon chips (65 on-screen at z1.217), including air-wing plates.
3. **Home-cam vs Ruhr.** Isolated tests panned onto Essen with no chips. The playtester wheeled in over the Ruhr (mouse ~455,455 on 1280×800). Equal-score Kreisfreie towns (Hamm/Münster 470) beat Essen until hub+core bonuses.
4. **Second name draw.** `MapRenderer._province_name_labels` turns on at tactical zoom (`show_province_labels`) and redrew Köln/Essen on top of `CityLabelsLayer` → ghosted doubles at z2.3–2.9.
5. **Close-zoom glyph floor.** `_draw` used `max(px/z, 8)` world px so collision was ~11 screen px while the glyph was ~8·z. Fixed earlier in this FIX (floor 1).
6. **Essen dropped under chips.** At live z1.217 with 65 chip AABBs, 22 px city packing could not place Essen beside Köln. Essen is now `must_keep` (pid 710403) and a second pass nudges it off live chip rects.

Not: 36 wu cluster drop, alias dedupe, set stability, Paris/capitals (those stayed PASS).

---

## What changed

`CityLabelsLayer.gd`

- Ruhr core scores: Essen 740, Duisburg/Düsseldorf 720, Dortmund 710, Köln extra core weight; Hamm/Münster stay 470.
- Hubs enter from home-band zoom and are eligible in strategic/mid.
- Collision AABBs match drawn glyph size (`world_px = max(px/z, 1)`).
- Live counters from `MapRenderer._demo_unit_icon_pids` (air-wing, land chips, pins), clamped, on-screen only; `notify_counters_dirty` on spawn/toggle.
- Essen `must_keep`; after packing, `_nudge_keep_off_counters` steps must-keep labels off live chip AABBs (up to 120 px) without overlapping other city labels.

`MapRenderer.gd`

- While `CityLabelsLayer` is active, legacy `_province_name_labels` stay hidden (no second draw at close zoom).
- `count_visible_province_name_labels()` for the doubled-draw live check.

Tests

- Isolated: Home-cam z1.217/1.512 Essen, Ruhr-cam live zooms, air-wing cover, doubled names/pids, 8 capitals. Still includes FIX #1/#2 cases.
- `HeadlessAtlas1LiveRuhrTest` (xvfb, not `--headless` evidence): TestScenario after Begin, units ON, **layout follows MapCamera** (fails if zoom does not stick). Home-cam z1.217 plus Ruhr-cam z1.217/1.512/2.904. Asserts Essen+Köln, no overlap, no doubled names, 1 `CityLabelsLayer`, 0 visible legacy province-name Labels, Ruhr labels clear of live counters.
- Pixel guard live_ruhr shots centered on Essen with units ON.

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
| Isolated city labels + FIX #1/#2 tests | **PASS** | `HeadlessAtlas1CityLabelsTest: RESULT=PASS` candidates=2050 `build_ms=166.2` |
| Essen Home-cam / Ruhr-cam z1.217 & 1.512 | **PASS** | isolated + live; live Home-cam names include Essen, Köln, Duisburg, Düsseldorf, Dortmund |
| Doubled draws / legacy Labels | **PASS** | `no doubled names` and `no legacy province-name draw` at all three live zooms |
| Live Begin + 250 counters | **PASS** | `HeadlessAtlas1LiveRuhrTest: RESULT=PASS` `cam_z=1.217` `counters_rect=65` |
| Ruhr labels clear of live chips | **PASS** | z1.217 / 1.512 / 2.904 |
| Close overlap z2.3–2.904 | **PASS** | isolated + live `has_visual_overlap` |
| Rivers | **PASS** | `build_ms=179.8` |
| Pixel guard | **PASS** | `WindowedAtlas1PixelGuard: RESULT=PASS` `reasons=[]` |
| Essen pixel probe (units ON, cam on Essen) | **PASS** | z1.217 run=16, z1.512 run=10, z2.904 run=8 (all screen 960,540) |
| Paris mid/close | **PASS** | run=13 / run=16 |

`--quick`: **14** known `unit_board_play_path` reds, no new ones. `map_qc` NE **0.9853** (3148/3195).

Seed was not re-run (city-label only). `HeadlessPerf4LiveMultiAiDayTest` seed `20fe9063` is untouched.

---

## Pixel shots

From this run (`docs/evidence/atlas1-fix3/`):

- `live_ruhr_z1217.png` / `z1512.png` / `z2904.png` — xvfb 1280×800 after Begin, units ON, MapCamera at Essen (playtester zooms). Layout list at z1.217 includes Essen, Köln, Duisburg, Düsseldorf, Dortmund; not Hamm over Essen.
- `tip_live_ruhr_z1217.png` / `z1512.png` / `z2904.png` — 1920×1080 pixel-guard copies, Essen cream-run 16/10/8 at screen centre.
- `tip_mid_paris.png`, `tip_close_ruhr.png`, `tip_mid_danube.png` — FIX #2 surfaces still PASS.

At z1.217 a 1280×800 (or 1920×1080) frame still shows most of NW Europe; that is the real Home-wheel geometry (1920/1.217 ≈ 1578 world units). The playtester's Ruhr cluster is the centre of that frame. z2.904 is the tight Rhine/Essen shot.

**Merge HOLD** until live Play.
