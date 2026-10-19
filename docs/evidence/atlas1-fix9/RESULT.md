# ATLAS-1 FIX #9 — hard-reject Ruhr label overlap; priority declutter (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. **Merge HOLD** until live Play.

**FIX #9 tip:** this evidence commit on `a573d0be`  
**Parent:** `7a3e1ebd` (FIX #8)

Play NOT READY on FIX #8: every gate passed and Duisburg was 0% over the Netherlands, but the Play path (Begin, U counters off, Home, wheel 1.022→3.031→1.022) stacked Ruhr names. RESULT.md allowed Ruhr AABB overlap, so the live test could not catch it. Dortmund’s disc was fully hidden at 1.022; Essen’s disc was about half covered at 1.022–1.578.

Hard rules kept: seed `20fe9063` unedited; no `world_full` ID renumber; Godot 4.7.1 via `tools/run_godot.sh`; Prod / TopInfoBar / GameData unedited; no force-push; no `cursor/*` branch; no new PR.

---

## What changed

`CityLabelsLayer.gd`

- Label-to-label overlap is a **hard reject** for every pair, Ruhr included. Collision is the rendered glyph box (font metrics + 3 px outline) grown 2 px; touching counts (`intersects(..., true)`).
- When no non-overlapping N/S slot exists, **declutter by priority** (population + hub + `_RUHR_CORE` score). Köln then Essen then Düsseldorf/Duisburg then Dortmund. Hidden cores reappear as zoom opens space. Camera + zoom + font only — in equals out.
- A visible cream disc (r=4) is covered when **>20%** of sampled pixels sit under a label, own mark included. Hidden cores have no disc.
- Exhaustive N/S assignment (priority bitmask) instead of more slot-list tuning. Play-centre cap 16 px. Duisburg west-into-NL sits are skipped.
- `_draw` uses packed `font_px` (no close-zoom 14 px bump that rasterized bigger than the collision box).
- `_drop_visual_overlaps` now drops the lower-priority keep when two keep labels still collide.

`HeadlessAtlas1LiveRuhrTest.gd` / `HeadlessAtlas1CityLabelsTest.gd`

- Fail on any label overlap and any covered Ruhr disc at every in and out stop.
- Assert the shown set and slots match in vs out (delta 0).
- Mid zoom may name 2–3 of 5; all five required from z≥2.4.

---

## Live in/out slot table (Play-centre px, counters off)

`HeadlessAtlas1LiveRuhrTest` RESULT=PASS, failures=0. In vs out delta **0.0**. z3.031 is in-only (outermost stop).

| city | z1.022 | z1.270 | z1.578 | z1.962 | z2.439 | z3.031 |
|---|---|---|---|---|---|---|
| Essen | 1.8,-15.9 N | same | same | 0,16 S | 0,14 S | 1.8,-15.9 N |
| Duisburg | — | 0,16 S | same | -6,-14 N | -6,-14 N | 4,15 S |
| Düsseldorf | — | — | — | — | 0,16 S | 0,16 S |
| Dortmund | — | — | — | 4,-15 N | 0,-16 N | 4,-15 N |
| Köln | -1.1,16.0 S | same | same | same | same | -1.1,16.0 S |

Named: **2** at z1.022 (Essen, Köln); **3** at z1.270–1.578; **4** at z1.962; **all 5** at z2.439 and z3.031. Duisburg sits are N/S/NNW on the German side, not due west into NL. Worst Play-centre **16.0**. n≤60. No duplicates. No Ruhr label on a Ruhr disc. No live label overlap.

---

## Commands and results

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3HubRouteTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3LiveScenarioTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix9 tools/eoa_atlas1_live_ruhr.sh
EOA_ATLAS1_PIXEL_OUT=/tmp/eoa-atlas1-pixel tools/eoa_atlas1_pixel_guard.sh
EOA_HWY3_RUHR_OUT=/tmp/eoa-hwy3-ruhr tools/eoa_hwy3_ruhr_legibility_guard.sh
tools/eoa_full_test_gates.sh --quick
```

| Claim | Result | Log |
|---|---|---|
| Isolated city labels | **PASS** | candidates=2050 `build_ms=152.3` (bar 200). In/out slots match. Worst Play-centre **16.0**. Mid named 3 (hid Düsseldorf/Dortmund). All 5 at z2.439 |
| Rivers | **PASS** | `build_ms=171.2` wall 192.3 (bar 200) verts=5378 |
| Hwy3HubRoute | **PASS** | failures=0 |
| Hwy3LiveScenario | **PASS** | failures=0 |
| Live Ruhr | **PASS** | failures=0. Counters off. cams 1.022 / 1.270 / 1.578 / 1.962 / 2.439 / 3.031 in and 2.439→1.022 out. no overlap. no-on-dot. in/out delta 0 |
| Pixel guard | **PASS** | `reasons=[]` shots `/tmp/eoa-atlas1-pixel/` |
| HWY-3 Ruhr legibility | **PASS** | z2.4/z4.0 names Essen/Duisburg/(Düsseldorf)/Dortmund; labels-off killed |
| `--quick` | **14** known reds | `unit_board_play_path` FAILED (failures=**14**). NE **0.9853** (3148/3195) |
| SCRIPT ERROR | **0** | none in city/rivers/HubRoute/LiveScenario/live |

Seed was not re-run (placement / live asserts only). `GameData.gd` unedited vs this slice (last GameData commit `b677890f`).

---

## Pixel / live shots

1280×800 `docs/evidence/atlas1-fix9/live_ruhr_z*.png`.

z1.022: Essen north of its mark, Köln south; Duisburg / Düsseldorf / Dortmund hidden. No stacked rows. z1.578: Essen N, Duisburg S (German side of the Rhine), Köln S. z2.439 and z3.031: all five named, no glyph overlap, discs visible.

Headless + xvfb, **NOT live Play**.
