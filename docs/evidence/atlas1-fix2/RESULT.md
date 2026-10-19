# ATLAS-1 FIX #2 — Paris capital at mid zoom (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. Do not merge.

**FIX #2 code tip:** `06af75f2`
**On top of FIX #1:** `a8d7c63a`
**This evidence file** is the next commit on the same branch.

Box gate on `a8d7c63a` (alone and merged onto `main` `e4fc2d90`) failed `paris_label_run_0` at `mid_paris` z1.35. The same guard passed on `5636fe2c`. FIX #1 caused it.

Hard rules kept: no `world_full` ID renumber; Godot only via `tools/run_godot.sh` (one instance); Prod files not touched.

---

## Root cause

Paris is pid **710707**, FRA capital, tier 4. Dots are drawn only from `placed`. FIX #1 cut `LABEL_SHIFT_PX` 72→22 and treated live nation-label AABBs (and counters) as hard blockers. At mid_paris the **France** nation label still occupied the capital (pixel guard also freezes `MapRenderer._process`, so nation labels can lag a shot behind and stay visible past hide-zoom 0.98). With only 22 px of slot search, every slot intersected that rect, Paris was skipped, and the cream dot never drew → `paris_label_run_0`.

On `5636fe2c` the 72 px shift could still park a slot beside “France”, so the dot at the city passed the 12 px probe.

Not the 36 wu cluster drop (Paris cluster is unique), not alias dedupe, not `alpha<0.04` (tier-4 enter is 0).

A first cut of FIX #2 also skipped the **off-screen cull for every `capital=true`**. Extra imputed capitals worldwide then filled the 60-cap (62 labels) and Essen/Köln vanished. FIX #2b restored the view cull and reserved `must_keep` for the 8 scenario capitals only.

---

## What changed

`CityLabelsLayer.gd`:

- Scenario / JSON capitals get `must_keep`. They ignore nation/counter obstacles, force-place at the base offset if every slot is blocked, and are never cluster- or satellite-dropped.
- Live nation rects are ignored at `NATION_LABEL_HIDE_ZOOM` (0.98).
- Off-screen cull still applies to everyone (including extra capitals).
- Extra `capital=true` (best city per minor tag) still counts toward the 60-cap. District satellites that only inherited that flag (Vienna Umland) still drop.
- `_better_capital` prefers a non-district when AUS/Wien scores tie.

`HeadlessAtlas1CityLabelsTest.gd`:

- `_test_mid_scenario_capitals` — each of the 8 scenario capitals (Berlin, Paris, Rome, Warsaw, London, Washington, Tokyo, Moscow) has a candidate, a label, and therefore a dot at z1.35 on its own view, **and** still does with a covering nation+counter rect.
- `_test_nation_rect` now allows leftover capitals and still forbids non-capital leftovers.

---

## Commands and results

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessStair1RhineSmoothTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix2 tools/eoa_atlas1_pixel_guard.sh
tools/eoa_full_test_gates.sh --quick
```

| Claim | Result | Log |
|---|---|---|
| City labels + FIX #1 tests | **PASS** | `HeadlessAtlas1CityLabelsTest: RESULT=PASS` candidates=2050 `build_ms=166.3` |
| 8 scenario capitals at z1.35 | **PASS** | `ATLAS1 city mid_capital pid=710707 name=Paris` (and the other seven) |
| Essen mid / close / stable / dedupe / counter | **PASS** | same as FIX #1 |
| Rivers | **PASS** | `ATLAS1 rivers build_ms=183.1` (retry; first sample 214.6 was VM noise over the 200 bar) |
| Stair | **PASS** | `HeadlessStair1RhineSmoothTest: RESULT=PASS` |
| Pixel guard | **PASS** | `WindowedAtlas1PixelGuard: RESULT=PASS` `reasons=[]` |
| Paris mid probe | **PASS** | `guard.label Paris screen=960.0,540.0 run=8` (was `run_0`) |
| Paris close | **PASS** | `run=16` |
| Essen mid/close | **PASS** | `run=8` / `run=8` |
| Danube | **PASS** | `run=70` |

`--quick`: **14** known `unit_board_play_path` reds, no new ones. `map_qc` NE **0.9853** (3148/3195).

Seed was not re-run here (city-label only). FIX #1 left `HeadlessPerf4LiveMultiAiDayTest RESULT=PASS` with the 5-day cycle; this FIX does not touch GameData / AI.

---

## Pixel shots

From this guard (`docs/evidence/atlas1-fix2/`):

- `tip_mid_paris.png` — Paris labelled at z1.35 (the failing shot on `a8d7c63a`)
- `tip_close_paris.png`, `tip_mid_ruhr.png`, `tip_close_ruhr.png`, `tip_mid_danube.png`

**Merge HOLD** until live Play.
