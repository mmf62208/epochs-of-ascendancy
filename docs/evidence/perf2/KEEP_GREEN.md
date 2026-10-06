# PERF-2 isolated keep-green

Off trusted main `d008ca42094bcb6df58872d0bd421f08a87c76b0` (EDGE-1 #79).
Tip `1421609c3cba82b35c36ab9b2d0230632bb0369b` (pre-FIX #1). FIX #1 parent
`b2674c6c` (main `425b4448` merged). xvfb / headless ≠ live Play. Never
`EOA_SKIP_TITLE`. `tools/run_godot.sh` only (Godot 4.7.1-rc2). HOLD merge.

## FIX #1 capital-star stale skip (before / after)

`HeadlessPerf2FleetRefreshBudgetTest` (c)(d) on product `b2674c6c` vs this tip.
Import first: `tools/run_godot.sh --headless --import --quit`.

| repro | `b2674c6c` | after FIX #1 |
|---|---|---|
| (c) map-mode at Home z=0.32, then 2 same-px notches + Home | **FAIL** `37 stars visible (want 0)` | **PASS** 37 hidden |
| (d) supply glyph pass (36 px) + same-px notch | **FAIL** `20px=0 36px=37 (want 20px=37)` | **PASS** 37 restored to 20 px |
| source needle (live font-size + invalidate) | **FAIL** | **PASS** |
| (a)(b) fleet cache + wheel budget | PASS (wheel 694 µs) | PASS (wheel 646 µs; plates identical) |

FIX #1 tip `7fe129f8`. Fences kept: FacilityIconLayer **unedited**. MapZoomLOD /
country labels **unedited**. Pick / draw-order / hit-test / spill **unedited**.
TipDismiss / ORDERS / camera / edge-pan **unedited**.

Official `--quick` `unit_board_play_path` still has the **14 known reds** on
main (unit_pick / unit_chrome / fill-toe / living_unit greps:
`pin_before_hex`, `capital_star_before_chip`, `home_hit_disk_tracks_counter_scale`,
`land_still_click_chrome_spill_player_land`, `still_click_open_unit_skips_land`,
`shift_u_before_plain_u`, `air_region_cas`, `peace_occupation`, `nation_era_next`,
`map_country_select`, `playtest_clock`, plus the two composer children
`unit_pick`/`unit_chrome` and the SE-England fill-toe and-check). **No new
reds.** `map_qc` / `hoi_matrix_product` / `unit_save_path` OK.

**Verdict: isolated keep-green PASS** (required slice).

| gate | kind | result | note |
|---|---|---|---|
| `HeadlessPerf2FleetRefreshBudgetTest` | hd | PASS | (a)(b) kept; (c)(d) FAIL on `b2674c6c` / PASS on `7fe129f8`; detail 707 µs / wheel 646 µs / cache-hit 4 µs |
| `HeadlessFleet2SharedSeaMarkerTest` | hd | PASS (a–p) | plate positions unchanged · RSS **1213.2** |
| `HeadlessFleet2SharedSeaMarkerTest` | xvfb | PASS (a–p) | 1280×740 · RSS **1350.9** |
| `HeadlessFleet1LandSpillGateTest` | hd | PASS (a–h) | unedited · RSS **1207.5** |
| `HeadlessFleet1LandSpillGateTest` | xvfb | PASS (a–h) | unedited · RSS **1382.5** |
| `WindowedFleet2LiveScaleCheck` | xvfb | PASS | RSS **2040.1** · 1280×740 GER Home |
| `--quick` `unit_board_play_path` | py | FAIL 14 | same known reds: living_unit_order_loop 4, unit_card_fill_toe 3, unit_centric_pick 3, unit_counter_chrome 2, se_england_shire 1, first_session_play_surface 1; **no new** |
| `--quick` `map_qc` / HOI / save | py | OK | NE hit 0.9853 |

## Test-merge

- PR **#82** `cursor/label-1-mid-zoom-crisp-f97e`: **CLEAN** (MapRenderer / labels do not overlap).
- PR **#81** `cursor/eoa-perf1b-hover-cache-396d`: **docs-only conflict** in `docs/CURRENT_STATE.md` changelog header (both prepend a HOLD paragraph). `MapRenderer.gd` and `TESTING_PLAN.md` auto-merged.

Recipe: `docs/evidence/perf2/CLICKS.md`.
