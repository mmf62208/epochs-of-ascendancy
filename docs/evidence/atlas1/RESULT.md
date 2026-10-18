# ATLAS-1 cities + major rivers — result

Branch `grok/atlas1-cities-rivers` on base `61a80433`. Draft only. Do not merge.

## Rhine renderer

`Rx1RhineLayer` stays the Rhine stroke (bridges, crossings, existing pixel guards). `MajorRiversLayer` skips stroke names Rhein, Rhine, and Rhin. The Rhine name can still be placed along the Rx1 course. The Rx1 course is the gameplay line through Bonn–Köln–Düsseldorf–Duisburg. The `rivers_world` Rhein/Rhine/Rhin parts are a different bake, and a second stroke would draw the river twice. Rhône stays in the major-river layer.

## Commands and results

| Claim | Result | Log line |
|---|---|---|
| City candidates and bands | PASS | `ATLAS1 city candidates=2085 home=8 strategic=88 mid=369 close=2085 build_ms=106.5` |
| Ruhr five at mid, screen cap | PASS | `ATLAS1 city ruhr_screen=60` and Ruhr five with no pairwise overlap |
| No per-frame rebuild | PASS | `ATLAS1 city rebuild_idle=0 rebuild_after_band=1` |
| Fade ramp | PASS | `ATLAS1 city fade_1_02=0.250 layer=0.250` |
| Essen scores above Mettmann | PASS | `ATLAS1 city score_essen=470.0 score_mettmann=220.0` |
| City headless | PASS | `HeadlessAtlas1CityLabelsTest: RESULT=PASS` |
| Major rivers | PASS | `ATLAS1 rivers build_ms=132.7 wall_ms=151.2 verts=5378` |
| Smooth fidelity | PASS | `ATLAS1 rivers max_dev=0.500 raw_verts=5378 smooth_verts=32408` |
| Danube near Vienna | PASS | `ATLAS1 rivers danube_vienna_wu=2.78` |
| Rivers headless | PASS | `HeadlessAtlas1RiversTest: RESULT=PASS` |
| Rhine stairs | PASS | `ATLAS1 rhine axis=0.0000 max_dev=0.928 display=132 raw=86 ends=true` |
| Stair headless | PASS | `HeadlessStair1RhineSmoothTest: RESULT=PASS` |
| Windowed pixel guard | PASS | `WindowedAtlas1PixelGuard: RESULT=PASS` |
| Essen / Paris / Danube pixels | PASS | Essen run 25 (mid) and 8 (close); Paris run 13 and 16; Danube run 70 |

Pixel guard command (this machine has no `xvfb-run`; the wrapper uses the live `DISPLAY=:0` at 1920×1080):

```bash
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1 tools/eoa_atlas1_pixel_guard.sh
```

Headless:

```bash
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessStair1RhineSmoothTest.gd
```

## Mutants

Each row is a source edit, then the real test, then the edit was reverted. None of these were killed only by a grep.

| Mutant | Test | Kill line |
|---|---|---|
| `tier_only` (score = tier×100) | City labels | `mid Ruhr missing Essen` (also Düsseldorf, Duisburg, Dortmund); `score_essen=200.0` |
| `labels_every_frame` (`rebuild_candidates()` in `_process`) | City labels | `rebuild_count moved across 120 idle frames (5 -> 125)` |
| `no_collision` (`_rects_clear` returns true) | City labels | `Ruhr labels overlap` and `nation rect covering the view still left 60 city labels` |
| `no_capital_priority` | City labels | `non-capital beat the capital (Town)` |
| `fixed_fade_off` (alpha jumps to 1) | City labels | `fade at zoom 1.02 enter 1.0 is 1.000` |
| `rivers_all_ranks` (scalerank ≤ 10) | Rivers | `vertex count 21351 > 20000` |
| `rhine_double` (Rhein/Rhine/Rhin strokes kept) | Rivers | `MajorRiversLayer strokes Rhein/Rhine (double draw)` |
| `no_smoothing` (`_smooth_course` returns raw) | Stair | `axis-aligned segment share 0.812 >= 0.10` |
| `raw_course_changed` (`course_points` shifted) | Stair | `course_points() does not match the raw json course` |
| anchor dots not drawn | Pixel guard | `reasons=["essen_label_run_0", "essen_label_run_0", "paris_label_run_0", "paris_label_run_0"]` `RESULT=FAIL` |

## Perf

- City candidate build: **106.5 ms** (bar ≤ 150).
- Major-river build: **132.7 ms** (bar ≤ 150).
- Together that is about **239 ms** at load. That is not a single combined 150 ms budget.
- Home frame p50 with both layers on versus off was **not measured**. Headless `_draw` timing was not a full F5 frame. No 30 fps claim.

## Seed

`scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd` is **not in this tree**. It is not on base `61a80433`. This branch was not rebased and main was not merged. The seed gate (md5 of the `multi_ai_decisions=` line, expected `20fe9063`) **was not run**.

## `--quick`

`tools/eoa_full_test_gates.sh --quick` → `FAILED (quick pure-only)` `EXIT:1`.

14 failures, all in `unit_board_play_path`. No new red.

1. `test_prior_feed_products_and_fill_toe_still_pass`
2. `test_real_builder_ands_shipped_children`
3. `test_unit_centric_pick` integrity
4. `test_unit_centric_pick` product_wiring
5. `test_unit_centric_pick` renderer_integrity_strings
6. `test_unit_counter_chrome` integrity
7. `test_unit_counter_chrome` product_wiring
8. `test_unit_card_fill_toe_visibility` integrity
9. `test_unit_card_fill_toe_visibility` product_ok
10. `test_unit_card_fill_toe_visibility` renderer_source_lock
11. `test_living_unit_order_loop` integrity
12. `test_playtest_clock_does_not_skip_ai_starts`
13. `test_playtest_clock_does_not_skip_occupation_ticks`
14. `test_living_unit_order_loop` product_wiring

`map_qc`: `NE land hit rate=0.9853 (3148/3195)`.

## Screenshots

Tip captures from the passing pixel guard (`docs/evidence/atlas1/`):

- Europe wide: `docs/evidence/atlas1/tip_europe_wide.png`
- Germany mid: `docs/evidence/atlas1/tip_germany_mid.png`
- Ruhr close: `docs/evidence/atlas1/tip_close_ruhr.png`
- Beauty (Rhine / Köln): `docs/evidence/atlas1/tip_beauty_rhine.png`
- Also: `tip_home_ruhr.png`, `tip_mid_ruhr.png`, `tip_home_paris.png`, `tip_mid_paris.png`, `tip_close_paris.png`, `tip_mid_danube.png`

A matching capture on `main` was not taken. Checking out another branch is out of bounds for this session.

## Full gates

`tools/eoa_full_test_gates.sh` → `FAILED — see steps above` `EXIT:1`.

ATLAS-1 steps inside that run all passed, including a second windowed capture:

- `launch_atlas1_city_labels` OK — `HeadlessAtlas1CityLabelsTest: RESULT=PASS`
- `launch_atlas1_rivers` OK — `HeadlessAtlas1RiversTest: RESULT=PASS`
- `launch_atlas1_rhine_smooth` OK — `HeadlessStair1RhineSmoothTest: RESULT=PASS`
- `launch_atlas1_pixel` OK — `WindowedAtlas1PixelGuard: RESULT=PASS`

Also green in this run: `map_qc`, `launch_rx1_rhine_crossing`, `launch_rx1_visibility`, `launch_rx1_panel_state`, `launch_rx1_live_stay_alive_tick`, Fac1a headless icon/pan/hover, Vis2, RT-1 road tier / edge filter / no-rebuild, pick, assault, march preview.

Reds that are not the ATLAS-1 tests:

| Step | Why |
|---|---|
| `unit_board_play_path` | Same 14 known pure reds as `--quick` |
| `launch_unit_order` | `no DemoUnitIcon on Channel fleet 950001` |
| `launch_perf2_fleet_refresh_budget` | `(d) supply glyph pass should enlarge stars (36 px count=0)` |
| `launch_vis1_map_readability` | L-off left 2 SupplyOutline nodes visible. Supply outline code was not edited |
| `launch_rx1_pixel`, `launch_mv1_pixel`, `launch_mv1_card_up_input`, `launch_rh1_pixel` | `need xvfb-run` (not installed) |
| `launch_fac1a_pixel` | `mkdir: cannot create directory '/opt/cursor': Permission denied` |
