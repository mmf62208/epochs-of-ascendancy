# IX-1 FIX3 — live spine stuck at 0% after stay-alive

**HOLD merge.** Draft PR 55. Do not merge other `origin/cursor/*`.

## Gap (named)

Live `MapRenderer._on_build_road_spine_pressed` stores the project on the **IDM autoload** `active_projects[710417]` (`try_start_road_spine` / `start_road_spine_project`). Daily advance is `TimeManager.game_day_advanced` → `IDM._on_game_day_advanced` → `advance_daily_projects`.

Windowed F5 (`is_interactive_light_sim`) `advance_days` only **queues** `day_emit`. After past7, stay-alive `_drop_smoke_deferred_load` **clears that queue** and `_flush_sim_events` early-returns. TopInfoBar `advance_real_time` still rolls the HUD calendar (Play: 17 Jan → 7 Apr, 80 days) so the panel keeps `Road spine 0% · ETA 35 days`. Headless sync `advance_days` emits immediately — Complete/DayTick 0→100% in 36 days.

**Not** a second IDM instance. **Not** a province-state copy. The store is correct; the live day signal never fires under stay-alive.

## Product fix

`TimeManager.advance_days` light path calls `_tick_live_construction_on_calendar_day` (same IDM store). Signal skips a second tick via `eoa_idm_calendar_tick_elapsed`. Stay-alive still drops `day_ai` / `day_battles` / queued `day_emit` (hang class kept). Toast-trim snapshot + `remove_child` kept. Off-tree `_complete_project` still marks spine `built` + COMPLETE (edges need the hex on-tree).

Also: toast timer WeakRef (no `Object → Object`); spine chrome **below** Settle; in-panel start notice.

## Guard

- `HeadlessIx1RoadSpineLiveStayAliveTickTest` — stay-alive + `advance_real_time` (FAIL on 2bc8f19).
- `tools/eoa_ix1_spine_live_progress_guard.sh` — Play wrapper + viewport mouse + `/proc` RSS.

## Honest labels

Harness-only: hatch, past7, stay-alive, this guard. Product Begin / Esc / mouse CC / 4x / clock remain **FAIL**. Road effects remain proposal-only.
