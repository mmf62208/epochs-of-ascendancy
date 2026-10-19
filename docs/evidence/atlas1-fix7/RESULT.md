# ATLAS-1 FIX #7 — Play-centre distance; compact Ruhr sit (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. **Merge HOLD** until live Play.

**FIX #7 tip:** this evidence commit  
**Parent packing:** `59c85d54` (FIX #6) + merge `origin/main` `d00dc8ed` (`70a516a9`)

Play MIXED/FAIL on `59c85d54` (RESULT_6702): live Ruhr reported Düsseldorf **8** px and Dortmund **24–30** px. Play measured Düsseldorf **44 / 44 / 33** and Dortmund **57 / 51 / 67** at z1.270 / 1.578 / 3.031. Mouse parked at **(500, 85)**; wheel from Home z0.344 toward the Ruhr.

Hard rules kept: seed `20fe9063` unedited; no `world_full` ID renumber; Godot 4.7.1 via `tools/run_godot.sh`; Prod / TopInfoBar unedited on this slice (campaign-loop files arrived only via the main merge); no force-push.

---

## What the old test measured wrong

FIX #6 `anchor_distance_px` was **nearest edge of the packing AABB**:

- `_measure` = `font.get_string_size` **+ 4 px**, so the box is larger than the drawn glyphs.
- Flush-left sit `(-size.x - 8, -2)` puts that box’s **east edge ~8 px** from the city mark.
- The live harness then **re-aimed every wheel notch at Essen** (`player_path_wheel_toward_world`), so the camera at z1.270 was ~`(7345, 1664)`, not Play’s `(7521.68, 1557.15)`.

Play’s `lbl.py` colour-masks the **drawn** cream outline + fill and reports **label centre − dot**. Flush-left “Düsseldorf” is a ~70 px-wide word: centre ≈ 44 W even while the packing near-edge is 8. Isolated synthetic on this tip:

```
flush-left Düsseldorf Play-centre 41.4  edge 9.0  pack_edge 8.0
```

That is Play’s 44 W vs FIX #6’s 8.

This FIX measures **the label actually rasterized that frame**: font metrics + 3 px outline, after `get_global_transform_with_canvas()`, centre-to-dot (`play_label_distance_px`). Wheel from Home with the mouse parked off-map at `(500, 85)`; Play’s cameras applied. No Essen re-aim.

---

## What changed

`CityLabelsLayer.gd`

- `drawn_label_rect` / `play_label_distance_px` / `play_label_offset_px`.
- Ruhr cores placed first, compact directional sits with **Play-centre ≤ 16 px** (Düsseldorf south/east of its mark — not flush-left into NL; Dortmund east of its own mark — not 67 px under Bielefeld).
- Band-keyed `_stable_off` so zoom in and out to the same zoom reuse the sit (Köln / cores delta 0).
- Düsseldorf (all five cores) in-band from strategic through close, so z1.022 is labelled.
- Ruhr-core AABB overlap allowed: dots are ~13 px apart at z1.27; 70 px names cannot stay disjoint at a 16 px centre. Satellites still yield.

`HeadlessAtlas1LiveRuhrTest.gd` / `HeadlessAtlas1CityLabelsTest.gd`

- Play cameras z1.022 / 1.270 / 1.578 / 3.031, mouse `(500, 85)`.
- Assert Play-centre ≤ 16 at the three mid/close zooms; Düsseldorf present at z1.0; in/out stability.

---

## Play-centre distances (px) — live, new metric

| city | z1.270 | z1.578 | z3.031 |
|---|---|---|---|
| Düsseldorf | **13.4 S** | **13.4 S** | **13.4 S** |
| Dortmund | **13.4 E** | **13.4 E** | **14.0 E** |
| Duisburg | **14.6 W** | **14.6 W** | **14.6 W** |
| Essen | **12.0 N** | **12.0 N** | **12.0 N** |
| Köln | **14.4 S** | **14.4 S** | **14.4 S** |

Play on `59c85d54` (same cameras, colour-mask centre): Düsseldorf 44 W / 44 W / 33 E; Dortmund 57 E / 51 E / 67 ENE.

Düsseldorf at z1.022: **labelled**. In vs out at z1.270 and z1.578: cores + Köln **delta 0.0**. N–S order PASS. No duplicates.

---

## Commands and results

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3HubRouteTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3LiveScenarioTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix7 tools/eoa_atlas1_live_ruhr.sh
EOA_ATLAS1_PIXEL_OUT=/tmp/eoa-atlas1-pixel tools/eoa_atlas1_pixel_guard.sh
EOA_HWY3_RUHR_OUT=/tmp/eoa-hwy3-ruhr tools/eoa_hwy3_ruhr_legibility_guard.sh
tools/eoa_full_test_gates.sh --quick
```

| Claim | Result | Log |
|---|---|---|
| Play-metric on flush-left packing | **PASS** | centre **41.4** (Play ~44) vs pack_edge **8.0** |
| Isolated city labels | **PASS** | candidates=2050 `build_ms=149.6`. Five cores. max Play-centre **14.6**. Düsseldorf at z1.022 |
| Rivers | **PASS** | `build_ms=149.5`–`166.4` (bar 200) |
| Hwy3HubRoute | **PASS** | failures=0 |
| Hwy3LiveScenario | **PASS** | failures=0. Paris one north line; Köln alias |
| Live Ruhr | **PASS** | failures=0. cams 1.022 / 1.270 / 1.578 / 3.031. Düsseldorf labelled at z1.0. Play-centre ≤16 all five. N/S PASS. in/out delta 0 |
| Pixel guard | **PASS** | `reasons=[]` |
| HWY-3 Ruhr legibility | **PASS** | z2.4/z4.0 4 names Essen/Duisburg/Düsseldorf/Dortmund; labels-off killed |
| `--quick` | **14** known reds | `unit_board_play_path` FAILED (failures=**14**). NE **0.9853** (3148/3195) |
| SCRIPT ERROR | **0** | none in city/rivers/HubRoute/LiveScenario/live/pixel/Ruhr guard |

Seed was not re-run (packing / live asserts only). `GameData.gd` unchanged on this slice except files that arrived with merge `d00dc8ed`.

---

## Pixel / live shots

1280×800 `docs/evidence/atlas1-fix7/live_ruhr_z*.png`.

- **z1.022:** Düsseldorf present.
- **z1.270 / z1.578 / z3.031:** five cores on their marks (Play-centre 12–15 px), Düsseldorf south of Essen/Duisburg, Dortmund east of its own dot.

---

## Merge HOLD

Headless + xvfb, **not** live Play.
