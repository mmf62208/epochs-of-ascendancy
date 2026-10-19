# ATLAS-1 FIX #8 — deterministic Ruhr slots; no label-on-dot (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. **Merge HOLD** until live Play.

**FIX #8 tip:** this evidence commit on `fe1c488d`  
**Parent:** `b20aa4c9` (FIX #7)

Play NOT READY on FIX #7: zoom-out Essen flipped south (remembered mid-band slot), ~1 px overlap with Duisburg; Dortmund `(14,0)` hid its own disc at z3.031; Düsseldorf at z1.022 covered most of Köln’s mark. Counters were off (Begin, U, Home). Cameras matched within 0.04 wu — placement, not camera.

Hard rules kept: seed `20fe9063` unedited; no `world_full` ID renumber; Godot 4.7.1 via `tools/run_godot.sh`; Prod / TopInfoBar / GameData unedited; no force-push; no `cursor/*` branch; no new PR.

---

## What changed

`CityLabelsLayer.gd`

- Ruhr compact sits are **default order only**. Dropped `_stable_off` (per-band memory reused before the defaults; last-resort `slots[0]` was the remembered south sit on the way out).
- Candidate scoring **rejects** a sit that buries its own 4 px disc or covers another Ruhr disc (`ruhr_dot_cover_names`). Interior bury > 8 px — graze at the box edge is allowed (70 px names on 13 px dots). Dortmund walks `(12,6)` before `(14,0)`.
- Side-jumps only vs already-placed cores (checking every Ruhr mark pushed Essen south of Duisburg). Other Ruhr label AABBs are still allowed.
- Duisburg prefers NE/NW German sits; west-into-NL `(-14,4)` is last.

`HeadlessAtlas1LiveRuhrTest.gd` / `HeadlessAtlas1CityLabelsTest.gd`

- Play path: Begin, **U (counters off)**, Home, wheel in and out.
- Live zooms **1.270 / 1.578 / 1.962 / 2.439 / 3.031**. 1.962 and 2.439 interpolated in **1/z** between Play cameras. Zoom-out asserts the same slots (≤3 px) and no extra overlaps.
- `ruhr_dot_cover_names` empty at every stop including z1.022.

---

## Live in/out slot table (Play-centre px, counters off)

`HeadlessAtlas1LiveRuhrTest` RESULT=PASS, failures=0. In vs out delta **0.0**. z3.031 is in-only (outermost stop).

| city | z1.270 | z1.578 | z1.962 | z2.439 | z3.031 |
|---|---|---|---|---|---|
| Essen | 0,-12 N | 0,-12 N | 0,-12 N | 0,-12 N | 0,-12 N |
| Duisburg | 8,-6 NE | 8,-6 NE | 8,-6 NE | -8,-8 NW | -8,-8 NW |
| Düsseldorf | 8,-6 NE | 8,-6 NE | 8,-6 NE | 8,-6 NE | 8,-6 NE |
| Dortmund | 12,6 E | 12,6 E | 12,6 E | 12,6 E | 12,6 E |
| Köln | 8,12 S | 8,12 S | 8,12 S | 8,12 S | 8,12 S |

Essen stays **north** on the way out through z1.578 (FIX #7 flipped it south). Dortmund is `(12,6)` at z3.031, not `(14,0)`. Düsseldorf at z1.022 is **8,-6 NE** (does not swallow Köln). Duisburg is NE/NW on the German side, not `(-14,4)` west into NL.

Play-centre distances (live): worst **14.4** (Köln). Essen 12.0 / Duisburg 10.0–11.3 / Düsseldorf 10.0 / Dortmund 13.4. n=60 at every stop (MAX_ON_SCREEN). No duplicates. No Ruhr label on a Ruhr dot. No live label overlap.

---

## Commands and results

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3HubRouteTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3LiveScenarioTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix8 tools/eoa_atlas1_live_ruhr.sh
EOA_ATLAS1_PIXEL_OUT=/tmp/eoa-atlas1-pixel tools/eoa_atlas1_pixel_guard.sh
EOA_HWY3_RUHR_OUT=/tmp/eoa-hwy3-ruhr tools/eoa_hwy3_ruhr_legibility_guard.sh
tools/eoa_full_test_gates.sh --quick
```

| Claim | Result | Log |
|---|---|---|
| Isolated city labels | **PASS** | candidates=2050 `build_ms=141.9` (bar 200). In/out slots match and miss Ruhr dots. Worst Play-centre **14.4**. Düsseldorf present at z1.022 |
| Rivers | **PASS** | `build_ms=173.8` wall 195.5 (bar 200) verts=5378 |
| Hwy3HubRoute | **PASS** | failures=0 |
| Hwy3LiveScenario | **PASS** | failures=0. Paris one north line; Köln alias |
| Live Ruhr | **PASS** | failures=0. Counters off. cams 1.022 / 1.270 / 1.578 / 1.962 / 2.439 / 3.031 in and 2.439→1.270 out. Düsseldorf labelled at z1.0. no-on-dot. in/out delta 0 |
| Pixel guard | **PASS** | `reasons=[]` shots `/tmp/eoa-atlas1-pixel/` |
| HWY-3 Ruhr legibility | **PASS** | z2.4/z4.0 4 names Essen/Duisburg/Düsseldorf/Dortmund; labels-off killed |
| `--quick` | **14** known reds | `unit_board_play_path` FAILED (failures=**14**). NE **0.9853** (3148/3195) |
| SCRIPT ERROR | **0** | none in city/rivers/HubRoute/LiveScenario/live |

Seed was not re-run (placement / live asserts only). `GameData.gd` unedited vs this slice (last GameData commit `b677890f`).

---

## Pixel / live shots

1280×800 `docs/evidence/atlas1-fix8/live_ruhr_z*.png`.

- **z1.022:** Düsseldorf present, NE of its mark, Köln’s disc clear.
- **z1.270 / 1.578 / 1.962 / 2.439 / 3.031:** five cores on their marks; Essen north in and out; Dortmund east `(12,6)`.

---

## Merge HOLD

Headless + xvfb, **not** live Play.
