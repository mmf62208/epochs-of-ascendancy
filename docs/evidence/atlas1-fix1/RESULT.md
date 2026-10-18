# ATLAS-1 FIX #1 — city labels (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. Do not merge.

**FIX code tip:** `0dd7bc6f` (`0dd7bc6f6dd424f7190998e792321e496ca5750e`)
**Base:** `a1b4d11c` (rebase onto `origin/main`). Pre-rebase WIP saved at `backup/pr109-a93feda5`.
**Playtest that this FIX answers:** `/home/ubuntu/.cursor/projects/workspace/uploads/RESULT_a6b8.md` (MIXED on `5636fe2c`).

FIX commits on top of `40dd947f`:

| SHA | Change |
|---|---|
| `3a6a8ebd` | Ruhr labels, zoom-stable anchors, close-zoom culling/stagger, counter nudge, city-name dedupe + tests |
| `1fe914a3` | Explicit `Vector2` types in collision (parse error on inferred `baseline_s`) |
| `0dd7bc6f` | Anchor slack 32 px so a 22 px collision slot still passes the distance guard |

This evidence file is the next commit on the same branch.

Hard rules kept: no `world_full` ID renumber; Godot only via `tools/run_godot.sh` (4.7.1-rc2, one instance); no GameData rewrite; no new dual packages; no merge of `origin/cursor/*` or `execute-plan/ceb60fdd-*`.

---

## What each playtest failure changed

### 1. Mid zoom (z1.2–1.9) Ruhr — Essen missing, only Köln

**Cause.** Layout rebuilt on band change / 15% pan, not on in-band zoom. Home-camera band entry filled the 60-cap with central-Germany names; zooming to Essen at z1.5 reused that set.

**Fix.** `CityLabelsLayer._should_rebuild` also fires when `|zoom - last_layout_zoom| >= ZOOM_REBUILD` (0.03). Priority is still capital → tier → population/importance score (`_priority_before`). Essen score 470 vs Mettmann 220; Mettmann stays out of mid.

**Guard.** `_test_essen_at_mid_z15` (Home cam z1.02 → `sync_view` 1.50 must rebuild and label Essen) and `_test_ruhr` (Essen + Köln at z1.55).

### 2. Labels far from their dots / wrong geographic order (Duisburg SW of Köln)

**Cause.** `LABEL_SHIFT_PX` was 72. Ruhr dots are 10–40 px apart at mid, so collision packing shoved names across the cluster. Screen-rect vs `draw_string` baseline also drifted.

**Fix.** Max shift 22 px; slot rings 8 / 12 / 16 / 22. Collision AABB is baseline + ascent (not the draw origin). Failed slots are culled, not shoved across the basin. `_resolve_layout` always re-places when it runs (no leftover screen positions from another zoom).

**Guard.** `_test_anchor_distance` at z 0.80 / 1.20 / 1.50 / 2.40 / 2.90 (`ANCHOR_MAX_PX=32`). Worst this box: **30.1 px** (Suhl at z1.20). Essen at mid: **8.2 px**.

### 3. Visible label set changed with no camera move (map-mode round trip)

**Cause.** `set_map_mode` always rebuilt. Idle `_process` was already gated; mode flips were not.

**Fix.** `set_map_mode` rebuilds only when `show_labels` flips. `sync_view` is a no-op unless `_should_rebuild`.

**Guard.** `_test_label_set_stable` — 30 idle `sync_view` frames at fixed cam/zoom (`stable_rebuild delta=0`) and political↔terrain round trip keeps the same name set.

### 4. Close zoom (z2.3–2.9) mass pop-in and overlaps

**Cause.** Every close-band city became eligible at z>2.0 at alpha 0 and fought for slots at once.

**Fix.** Skip `alpha < 0.04`. Close-only names enter at `CITY_LABEL_MID_MAX + t * 0.85` (score-staggered). Fade span 0.08. Screen-space collision in priority order, 60 cap.

**Guard.** `_test_close_no_overlap` at z 2.30 / 2.60 / 2.90 Ruhr (`n=60`, no pairwise rect overlap). Fade still ramps (`fade_1_02=0.250`).

### 5. Labels under army/unit counters (Essen half under a chip)

**Fix.** Live `DemoUnitIcon_*` screen rects (`COUNTER_HALF` 28×32 via `get_global_transform_with_canvas`) are obstacles in `place_competing`. Labels take the next free slot or are culled. Nation labels use the same canvas transform.

**Guard.** `_test_counter_avoidance` — Essen stays labelled and its rect does not intersect a covering counter; nudge stays within 32 px.

### 6. Duplicate names (Vienna ×3, Manchester ×5, München + Munich)

**Fix in data** (`data/provinces_world_accurate/province_city_layer.json`, **no ID renumber**):

| pid | was | now |
|---|---|---|
| 710020 | Vienna | Wiener Umland/Nordteil |
| 710021 | Vienna | Wiener Umland/Südteil |
| 710022 | Vienna | Wien |
| 710205 | Munich | München |
| 710220 | Munich | München, Landkreis |
| 711345–348 | Manchester | Greater Manchester (SW/SE/NW/NE) |

**Fix at load.** Canonical alias fold (vienna→Wien, munich/muenchen→München, cologne→Köln). Same-cluster nearby drop (`DEDUPE_WORLD=36`). District satellite drop (Landkreis / Umland / Greater * next to a core). Candidates **2050** (was 2085).

**Guard.** `_test_no_duplicate_names` — one Wien at z1.35, one München at z1.55, one Manchester at z2.4; satellites empty.

### 7. Prod panel never opens / 4+ min stall after Close → Prod

**Finding: pre-existing. ATLAS-1 did not cause it.**

```
git diff --stat a1b4d11c -- \
  scripts/ui/TopInfoBar.gd \
  scripts/ui/ProductionAssignmentScreen.gd \
  scripts/autoload/ProductionManager.gd \
  scripts/ui/MunitionsDeskChip.gd
```

Empty. ATLAS-1 this FIX only touches `CityLabelsLayer.gd`, `HeadlessAtlas1CityLabelsTest.gd`, and city-name strings in `province_city_layer.json`. Close→Prod with `use_cache=false` plus a llvmpipe hitch is the same class as #108 air-physics slowness on this box. Not fixed here.

---

## Headless tests added (would FAIL before the FIX)

All in `scripts/core/HeadlessAtlas1CityLabelsTest.gd`. Command:

```bash
EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
```

| Test | What it would catch on the MIXED tree |
|---|---|
| `_test_anchor_distance` | 72 px shove / stale transform (Duisburg SW of Köln) |
| `_test_close_no_overlap` | Essen/Dortmund/Herne and Solingen/Gelsenkirchen pile-up at z2.3–2.9 |
| `_test_no_duplicate_names` | Vienna ×3, Manchester ×5, München+Munich |
| `_test_essen_at_mid_z15` | In-band zoom keeping the Home 60-cap (Essen missing, only Köln) |
| `_test_label_set_stable` | Label set changing with no camera move / map-mode flip |
| `_test_counter_avoidance` | Essen drawn under a unit-counter rect |

Kept: bands, home 8, Ruhr Essen+Köln, nation rect, cap 60, idle rebuild 0, fade ramp, capital priority, Essen>Mettmann score, states hide.

---

## Commands and results (this VM)

Godot `4.7.1.rc2` via `tools/run_godot.sh`. `EOA_ATLAS1_BUILD_BAR_MS=200` (`EOA_SLOW_BOX=1` equivalent). One Godot at a time.

| Claim | Result | Log line |
|---|---|---|
| City candidates and bands | PASS | `ATLAS1 city candidates=2050 home=8 strategic=87 mid=370 close=2050 build_ms=151.1` |
| Ruhr Essen + Köln, cap 60 | PASS | `ATLAS1 city ruhr_screen=60`; Essen 8.2 px from its dot |
| Idle no rebuild | PASS | `ATLAS1 city rebuild_idle=0 rebuild_after_band=1` |
| Fade ramp | PASS | `ATLAS1 city fade_1_02=0.250 layer=0.250` |
| Essen > Mettmann | PASS | `ATLAS1 city score_essen=470.0 score_mettmann=220.0` |
| Anchor distance | PASS | `ATLAS1 city max_anchor_px=30.1` |
| Close no overlap | PASS | `ATLAS1 city close_z2.30 n=60` / `2.60` / `2.90` |
| Dedupe names | PASS | Wien / München / Manchester satellites dropped; one label each |
| Essen at z1.5 | PASS | `ATLAS1 city zoom_rebuild delta=1` |
| Label set stable | PASS | `ATLAS1 city stable_rebuild delta=0 names=60` |
| Counter avoidance | PASS | Essen avoids the covering rect, stays ≤32 px |
| City headless | **PASS** | `HeadlessAtlas1CityLabelsTest: RESULT=PASS` (failures=0) |
| Major rivers | **PASS** | `ATLAS1 rivers build_ms=189.3 wall_ms=213.5 verts=5378` |
| Smooth fidelity | PASS | `ATLAS1 rivers max_dev=0.500 raw_verts=5378 smooth_verts=32408` |
| Danube near Vienna | PASS | `ATLAS1 rivers danube_vienna_wu=2.78` |
| Rivers headless | **PASS** | `HeadlessAtlas1RiversTest: RESULT=PASS` |
| Rhine stairs | **PASS** | `ATLAS1 rhine axis=0.0000 max_dev=0.928 display=132 raw=86 ends=true` |
| Stair headless | **PASS** | `HeadlessStair1RhineSmoothTest: RESULT=PASS` |

Label **building** is still one load-time candidate pass. 151.1 ms is this slow box (original evidence 106.5 ms on a different machine). Bar is 150 default, **200 when `EOA_SLOW_BOX=1`**. Rivers 189.3 ms under the same bar. No extra per-frame candidate rebuild.

---

## Seed (`HeadlessPerf4LiveMultiAiDayTest`)

```bash
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd
```

`HeadlessPerf4LiveMultiAiDayTest: RESULT=PASS` (failures=0). Two seeded 5-day runs identical; player `GER` not in `prod_tags`.

Printed `multi_ai_decisions=` (5-day rotation, 3 prod + 1 soft):

| day | prod_tags | soft_tag |
|---|---|---|
| 0 | JAP, SOV, ITA | USA |
| 1 | SOV, ITA, USA | POL |
| 2 | ITA, USA, POL | ENG |
| 3 | USA, POL, ENG | FRA |
| 4 | POL, ENG, FRA | JAP |

MD5 of that Godot print on this box:

- payload after `multi_ai_decisions=` → `dc774ef0` (`dc774ef05d7c645982cfb606dff61f6b`)
- full log line → `2f108bae` (`2f108bae9dc2db9e3bab32f80490ee26`)

The in-tree harness does **not** hash; it checks identity of two seeded collections. Ship’s external 8-hex `20fe9063` was not reproduced by hashing this Dictionary print form. The decision sequence itself is the known 5-day cycle and the test is PASS. ATLAS-1 does not touch GameData / AI apply.

---

## `--quick`

```bash
tools/eoa_full_test_gates.sh --quick
```

`FAILED (quick pure-only)` `EXIT:1`.

**14** failures, all in `unit_board_play_path`. **No new red.** `map_qc` **OK** after Pillow: `NE land hit rate=0.9853 (3148/3195)`.

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

---

## Prod finding (short)

ATLAS-1 **did not** cause Close→Prod never opening or the 4+ min stall. Production UI / manager files are identical to `a1b4d11c`. Treat as pre-existing #108-class hitch on llvmpipe. Not fixed in this PR.

---

## Not run this FIX pass

Windowed `WindowedAtlas1PixelGuard` / `tools/eoa_atlas1_pixel_guard.sh` — no xvfb on this agent. Original `docs/evidence/atlas1/` shots remain from the WIP pass; close-Ruhr pile-up in those shots is what this FIX addresses. Live Play is still required before merge.

**Merge HOLD.**
