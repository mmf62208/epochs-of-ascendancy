# ATLAS-1 FIX #6 — 40 px own-side sit; Düsseldorf stays south of Essen (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. **Merge HOLD** until live Play.

**FIX #6 tip:** this evidence commit on `66314c6d`
**Parent:** `a65b7829` (FIX #5). Test-only `8dfa34c3` fails on FIX #5 packing.

Play MIXED on `a65b7829`: from Home ~0.818 wheeling (455,455), Düsseldorf at z1.264/1.572 sat ~73/71 px (37 E / 62 N) north of Essen+Duisburg on Borken. Close z3.019 was fine.

Hard rules kept: seed `20fe9063` unedited; no `world_full` ID renumber; Godot 4.7.1 via `tools/run_godot.sh`; Prod / TopInfoBar / GameData unedited; no force-push.

---

## What changed

`CityLabelsLayer.gd`

- `RUHR_ANCHOR_MAX_PX` 80 → **40**. Chip-avoid never walks far enough to read as another city.
- Own-side filter: a city south of Essen/Duisburg cannot put its glyph north of them. Düsseldorf prefers south/west slots.
- Chip-clear inside 40 px first; else a nearby own-side sit even on a plate (dimmed 0.72, z 30 above chips); never a 60+ px jump.

`HeadlessAtlas1LiveRuhrTest.gd`

- Every Ruhr core within **45 px** of its dot at 1.217 / 1.512 / 2.904.
- Label centres: Duisburg/Essen north of Düsseldorf, Düsseldorf north of Köln, at all three zooms.
- Must FAIL on `a65b7829` packing (Düsseldorf ~73 px / north of Essen). Commit `8dfa34c3` is that test on FIX #5 packing.

---

## Commands and results

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3HubRouteTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3LiveScenarioTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix6 tools/eoa_atlas1_live_ruhr.sh
EOA_ATLAS1_PIXEL_OUT=/tmp/eoa-atlas1-pixel tools/eoa_atlas1_pixel_guard.sh
EOA_HWY3_RUHR_OUT=/tmp/eoa-hwy3-ruhr tools/eoa_hwy3_ruhr_legibility_guard.sh
tools/eoa_full_test_gates.sh --quick
```

| Claim | Result | Log |
|---|---|---|
| Live test on FIX #5 packing | **FAIL** (as required) | `8dfa34c3` 45 px + N/S at mid zoom. Play Düsseldorf 73/71 px north of Essen |
| Isolated city labels | **PASS** | candidates=2050 `build_ms=143.9`. Five cores at Ruhr-cam. max_anchor **36.0** |
| Rivers | **PASS** | `build_ms=167.9` |
| Hwy3HubRoute | **PASS** | failures=0 |
| Hwy3LiveScenario | **PASS** | failures=0. Paris one north line; Köln alias |
| Live Ruhr | **PASS** | failures=0. cam_z 1.270/1.578/3.031. Düsseldorf dist **8.0** all three. N/S PASS all three. Worst Dortmund 30 / Köln 36 |
| Pixel guard | **PASS** | `reasons=[]` |
| HWY-3 Ruhr legibility | **PASS** | z2.4/z4.0 4 names Essen/Duisburg/Düsseldorf/Dortmund; labels-off 4→0 killed |
| `--quick` | **14** known reds | `unit_board_play_path` FAILED (failures=**14**). NE **0.9853** (3148/3195) |
| SCRIPT ERROR | **0** | none in city/rivers/HubRoute/LiveScenario/live/pixel/Ruhr guard |

Seed was not re-run (packing / live asserts only).

---

## Pixel / live shots

1280×800 `live_ruhr_z*.png`.

- **z1.217 / z1.512:** Düsseldorf sits by its own mark, south of Essen/Duisburg, north of Köln — not on Borken.
- **z2.904:** Duisburg W, Essen, Dortmund E, Düsseldorf south, Köln further south.

---

## Merge HOLD

Headless + xvfb, **not** live Play.
