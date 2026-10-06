# PERF-2 isolated keep-green

Off trusted main `d008ca42094bcb6df58872d0bd421f08a87c76b0` (EDGE-1 #79).
Tip `1421609c3cba82b35c36ab9b2d0230632bb0369b`.
xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only
(Godot 4.7.1-rc2). HOLD merge.

Fences kept: FacilityIconLayer **unedited**. MapZoomLOD / country labels
**unedited**. Pick / draw-order / hit-test / spill **unedited**. TipDismiss /
ORDERS / camera / edge-pan **unedited**.

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
| `HeadlessPerf2FleetRefreshBudgetTest` | hd | PASS | (a) Channel/NS offsets + plate worlds identical; (b) detail 554 µs / wheel 640 µs / cache-hit 3 µs (raw 3153 µs) |
| `HeadlessFleet2SharedSeaMarkerTest` | hd | PASS (a–p) | plate positions unchanged |
| `HeadlessFleet2SharedSeaMarkerTest` | xvfb | PASS (a–p) | 1280×740 |
| `HeadlessFleet1LandSpillGateTest` | hd | PASS (a–h) | unedited |
| `WindowedFleet2LiveScaleCheck` | xvfb | PASS | RSS **2041.2** · 1280×740 GER Home |
| `--quick` `unit_board_play_path` | py | FAIL 14 | same known reds as main; no new |
| `--quick` `map_qc` / HOI / save | py | OK | NE hit 0.9853 |

## Test-merge

- PR **#82** `cursor/label-1-mid-zoom-crisp-f97e`: **CLEAN** (MapRenderer / labels do not overlap).
- PR **#81** `cursor/eoa-perf1b-hover-cache-396d`: **docs-only conflict** in `docs/CURRENT_STATE.md` changelog header (both prepend a HOLD paragraph). `MapRenderer.gd` and `TESTING_PLAN.md` auto-merged.

Recipe: `docs/evidence/perf2/CLICKS.md`.
