# VP-READOUT-1 — Command Center Victory Paths readout

Pillar: campaign loop to win/loss. Revives POST-VP1 POLISH: heading, no clip of Conquest at 1280, day-1 progress. Branch `grok/vp-readout-1`. Base `5d099346af1304eccf71bcf6e0d9c0afb4b715c0`. Draft MERGE HOLD. Headless is not live Play.

Victory Paths stay **opt-in**. Default `EOA_VICTORY_PATHS` is unchanged. With the flag off, `_add_victory_paths_readout` still returns before creating nodes, so the Command Center tree matches main.

## What changed (`MainMenu.gd` only)

`_add_victory_paths_readout` now:

1. Adds a `VictoryPathsHeading` Label with text `Victory Paths`.
2. Always builds `VictoryPathsReadout` when the flag is on. Progress comes from `GameData.victory_paths_progress_text()`. When that string is empty, `_victory_paths_zero_state_text()` fills a 0-state line per enabled path from the public `VictoryPathsDomain.load_rules()` read API (Conquest `0/{majors-1} enemy capitals`, Atomic `0/{hold_days}`, Arsenal `0% · 0/{sustain_days}`, Score `0`). `VictoryPathsDomain.gd` and `GameData.gd` are unedited.
3. Wraps heading + readout in a `MarginContainer` with 12 px left/right and `SIZE_EXPAND_FILL`. The menu panel frame is 48 px of chrome vs 40 px content margin; the inset keeps the first glyph of Conquest at or past the inner frame instead of under it. No magic negative offsets.

## Guard

`scripts/core/HeadlessVpReadout1Test.gd` — standalone, not added to `tools/eoa_full_test_gates.sh`.

With `EOA_VICTORY_PATHS=1`, fresh 1936 GER at day 0 and day 7, viewports 1280×720 and 1280×800:

- `VictoryPathsHeading` exists, text `Victory Paths`.
- `VictoryPathsReadout` has one line per enabled path (Conquest, Atomic, Arsenal of the World, Score), each with a concrete digit.
- Label global x ≥ GameActions column x; line text width ≤ column width; first glyph x ≥ MenuPanel x + 48.

With the flag off, neither node exists.

### FAIL on base `5d099346` (current test, unfixed `MainMenu.gd`)

```
  [FAIL] HeadlessVpReadout1Test: day 0: VictoryPathsHeading missing
  [FAIL] HeadlessVpReadout1Test: day 0 1280x720: first glyph clipped under panel frame x=200.0 frame_inner=208.0
  [FAIL] HeadlessVpReadout1Test: day 0: VictoryPathsHeading missing
  [FAIL] HeadlessVpReadout1Test: day 0 1280x800: first glyph clipped under panel frame x=200.0 frame_inner=208.0
HeadlessVpReadout1Test: FAIL (failures=8)
HeadlessVpReadout1Test: RESULT=FAIL
```

On that tree `GameData.victory_paths_progress_text()` is already non-empty at day 0 (`Conquest 0/8 | Atomic 0/30 | Arsenal of the World 0% · 0/90 | Score 0 | Satellite deferred`), so the empty-text early return was not the day-0 hole. The missing heading and the 8 px chrome clip were. The 0-state helper still covers the empty-text path.

### PASS on tip

See proof section below. Heading `'Victory Paths'`, four path lines with digits, `lines fit column x=200.0 w=432.0`, `RESULT=PASS`.

## Screenshot

1280×800 Command Center left column (flag on, GER 1936 day 0). Heading + Conquest / Atomic / Arsenal of the World / Score visible; C of Conquest not under the frame.

- `/opt/cursor/artifacts/vp-readout-1/vp_readout_1280x800.png`
- `/opt/cursor/artifacts/vp-readout-1/vp_readout_column_1280x800.png`

## Proof (fill after gates)

- HeadlessVpReadout1Test: pending
- HeadlessVictoryPaths1Test (unmodified): pending
- HeadlessSettingsToggles1Test (unmodified): pending
- `tools/eoa_full_test_gates.sh --quick`: pending
- b / d map-select max of 3: pending
- Seed `20fe9063de285f19d4f9b8a105abfd31` default and `EOA_VICTORY_PATHS=1`: pending
- SCRIPT ERROR: pending
