# PERF-5 keep-green

- `HeadlessPerf3SupplyToggleTest` unedited — second L-on role compute unchanged.
- `HeadlessPerf5LegendDayTickTest` — StyleBox.changed=0, hint theme_changed=0,
  ≤1 board walk/day, 0 walks at pulse expiry, pulse modulate differs, contested
  count updates after controller flip.
- `HeadlessPerf5SupplyOverlayFreshTest` — B1 real API, B2 silent in-place
  mutation (no signal), B3 30 no-change frames + L off/on cache hit.
- `tools/eoa_full_test_gates.sh --quick` — exactly the 14 known
  `unit_board_play_path` reds.
- Seed 193601 infra picks unchanged.
- File fence: MapRenderer listed functions + SupplyOutlineBatchLayer + new tests
  + gates step after `launch_perf3_supply_toggle` + docs. No SupplyManager.gd.
