# STATUS — FIX IX-1 live clock / softpipe ROUND 2 on `9f09db2` (PR 55)

**HOLD merge.** Draft PR 55. Do not merge.

- Branch: `cursor/ix1-road-spine-9d9b`
- Start SHA: `9f09db2b67e14f3682e9b7c165e4438b485234b9`
- PR: https://github.com/mmf62208/epochs-of-ascendancy/pull/55

## Cause (Play FAIL `9f09db2` — second consecutive)

Round-1 CA claimed DisplayServer=live F5 + TopInfoBar Space + hour force. Play still stuck **1 Jan 1936 00:00** through 4x + pause/play (~15s+). Esc→CC PASS; Begin PASS; SCRIPT_ERROR 0. Search / spine / RoadLayer / Essen NOT RUN.

Play `godot.log` (X11 / llvmpipe / `tools/run_godot.sh`):
- `TimeManager: Paused = true`
- `TopInfoBar: start PAUSED …`
- Repeated `TestRunner: _ensure_game_interactive() — … sim paused for playtest.`
- After Begin: `TimeManager: Scenario start date set to 1936-01-01` then no `SPEED` / `RESUMED`

Deeper than light-sim / day_emit: MapRenderer `_input` leftover pick-block (`_left_map_pick_blocked` after title map-clicks / soft camera center) + `gui_get_hovered_control()` miss on softpipe **swallowed TopInfoBar 4x / pause** (`set_input_as_handled`) — same class as Search Go miss. `_ensure_game_interactive` still force-paused when `player_owns_clock` was unset. Begin never cleared leftover pan/pick.

Parent-of-regress `5732d34` had live past +6 PASS.

## Fix

1. `_top_bar_owns_click()` — rect-test TopInfoBar / speed row; `_input` / spatial pick / land-chip early-out before leftover swallow.
2. `release_play_clock_input_blockers()` on living-title Begin (clear leftover pick + Search focus).
3. `TimeManager.mark_living_title_closed` / `should_force_playtest_start_pause` — TestRunner **will not** re-pause after Begin.
4. TopInfoBar `arm_play_clock_after_begin` + speed `ACTION_MODE_BUTTON_PRESS`.
5. Windowed TimeManager hour fallback if unpaused after Begin (headless -s unchanged).
6. Gate `simulate_play_begin_clock_controls` **FAILS** if Begin+4x stays paused at 00:00 (not days-only).

Search Go wiring from `5732d34` and Build Road Spine CTA pin from `36485b9` **kept**. Corridor IDs unchanged. Dig2/G PARKED.

## Gates

See commit / PR body after headless run.

## HOLD

Do not merge until Scott/Play rebounds: past +6 → Search→spine visible+start → complete → RoadLayer → Essen.
