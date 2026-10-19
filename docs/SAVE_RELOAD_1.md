# SAVE-RELOAD-1

Mid-campaign save, quit, and load. A named slot written on day 200 reloads to the same state hash, and the next days match a run that never saved. Format is v2 (`EOASAVE2`). Draft PR is on HOLD. No Play verdict.

## Branch

- Work clone: `~/Projects/epochs-of-ascendancy-save1`
- Branch: `grok/save-reload-1`
- Rebased feature commit: `180e3dba63be7dc3dcc882126bc296fb7b276d07` (was `1a894de4` before the rebase)
- Rebased hour / `run_seed` guard, current tip: `fd7cbd72127df4282961d27e6449e731e2d7cf5f` (was `630a8599`)
- Base: `2a7da052f77fe938f2c246236a90d519c13981cd` (`origin/grok/campaign-loop-1`, CL1 FIX #1 evidence). #113 was not in `origin/main` (`0560291280cf7a3642bd551cc0211042a573c9fc`).
- Brief pin `25599270` is an ancestor. The rebase replayed the two SR1 commits onto `2a7da052` with no conflicts. `git diff --stat 2a7da052 HEAD` is 27 files, +5159 / −274.

## Format

File: `user://saves/<slot>.eoasave`.

- Magic `EOASAVE2`, u32le header length, JSON header, then a zstd body.
- Header: `format=eoa-save`, `save_version=2`, `game_version`, `scenario_id`, `player_tag`, `nation_name`, `game_date` (`yyyy-mm-dd hh:00`), `days_elapsed`, `campaign_status`, `wall_time`, `kind` (`manual` / `quick` / `auto`), `body_md5`, `body_bytes`.
- Body: `var_to_bytes` of the gathered dictionary, `COMPRESSION_ZSTD`, objects off.
- Load order: magic and version, md5, decompress, `bytes_to_var`, `SaveFormat.migrate`, `SaveFormat.validate`, and only then `clear_for_load` plus `_apply_save_data`.
- Atomic write: `<slot>.eoasave.tmp`, reopen and check the md5, rename the current file to `.bak`, rename the tmp into place. A failed write leaves the previous file byte-identical and removes the tmp.
- v1 `<slot>.json` is listed and loaded best-effort through migrate. Load never rewrites or deletes the v1 file. Saving that name writes a new `.eoasave` beside it. The load list marks v1 as `old format`.
- `save_game`, `save_game_detailed`, `quicksave`, `load_game`, `load_game_detailed`, and `quickload` keep their names and all call `_save_v2` / `_load_v2`. `const SAVE_VERSION := 1` stays. Format 2 is a separate field.
- `read_save_body(slot)` is the helper for tests that used to parse the raw JSON.

`player_tag` in the gathered metadata is overwritten by `_stamp_live_metadata` from the live leader tag. The literal `"USA"` remains only as the initial placeholder before that stamp.

## Coverage

`scripts/core/SaveCoverageManifest.gd`.

Autoloads: 19 saved, 5 exempt.

| Exempt | Reason |
|---|---|
| LeaderEventUI | UI only (toasts and news) |
| NetSessionManager | net-only; offline play has no sim peer |
| SpecialSiteManager | static JSON; province sites ride in `map.special_sites` |
| SaveLoadManager | slot index is derived from autosave mtimes |
| DialogueManager | conversation UI; no daily sim state |

Extras: FormationMovement, WarStateDomain, CapitulationDomain, and CampaignEndDomain are saved. CombatPresenceRegistry is rebuilt from supply deployments. LandBattleAi is static personality data. `WarStateDomain._override` is a test-rules static and is not saved.

Peace keys: 376 saved, 10 exempt. Every exempt key is `map_perf_*` telemetry with no sim reader.

Rebuilt after apply, not stored: MapManager owner index, supply regional bonuses, live fronts (`WarStateDomain.invalidate_fronts`), factory owners, the production AI day cache, and the technology unlock index.

`hierarchy_membership_live` is in the GameData body (`_export_hierarchy_membership_live`) and applied on load. It is not dropped on the live path.

`current_hour` is the only saved copy of the hour. `current_date.hour` and `date_string` are stripped in `TimeManager.get_save_data`, because a second copy restored the hour even when `current_hour` was removed. Apply still accepts `current_date.hour` from a v1 file that has no `current_hour` key.

`clear_for_load` resets `campaign_wars`, `campaign_capitulation`, `campaign_end`, and the added peace keys, so a v1 load cannot keep a running war.

## Determinism

`run_seed` lives on TimeManager and is saved in `time`. At the start of each real day tick, before listeners, `seed(hash([run_seed, total_days_elapsed]))` runs when `run_seed` is not 0. `EOA_SIM_DAY_RESEED=0` skips that call. `run_seed` 0 does not reseed (legacy). A new campaign draws it once from `Time.get_ticks_usec()` inside `LeaderManager.boot_living_player`. Harnesses set it. The perf seed test never sets it, so `20fe9063` is unchanged.

The in-process determinism load sets `run_seed` to 0 before `load_game_detailed`, because a same-process load would otherwise keep the live value and hide a missing restore. A fresh process already starts at 0.

Save, load, and autosave do not call `randf`, `randi`, or `seed`, except the load restoring `run_seed`.

Reseed cost on the reference trace: 0.0007 ms/call (`~/save1_evidence/logs/sr1_det_ref.log`).

### Trace md5

On the rebased tip, reference, two-process load, in-process, and autosave-inert all match:

`0a625e185f3f9b882d18294252b8a6b7`

The earlier build, before the hour lived only in `current_hour`, matched `70ac59acf8f59827198f74f4da9d84a2`. Stripping `hour` and `date_string` from the saved date changes `state_hash` inside every trace row. Both sides of one build still match. That is not a determinism break.

- Ref wall 24.4 s. In-process wall 49.9 s. Autosave-inert wall 25.4 s. Autosaves at day 212 (`sr1test_auto_1`) and day 243 (`sr1test_auto_2`). Quit autosave left the state hash unchanged.
- Gate wrapper (`launch_save_reload1_determinism.log`): seed `20fe9063de285f19d4f9b8a105abfd31`, then `PASS: two-process traces match 0a625e185f3f9b882d18294252b8a6b7`.
- Logs: `~/save1_evidence/logs/sr1_det_ref.log`, `sr1_det_load.log`, `sr1_det_inproc.log`, `sr1_det_autosave.log`. Traces: `~/save1_evidence/sr1_ref.trace` and `sr1_load.trace`.

### RNG leaks (not changed)

These use a local `RandomNumberGenerator.randomize()`, not the global seed. Touching them was not required for the headless gate, and a global-seed change was out of bounds because of `20fe9063`.

- `TradeManager.process_monthly_trade_risks` (`TradeManager.gd` around line 1265). Not the light F5 daily path.
- `SpaceLayerManager._roll_asteroid_resources` (around 376), `process_monthly_space_risks` (around 630), `advance_surveys` (around 1495). Empty flows and surveys no-op. A later campaign with a live space flow is not cross-process deterministic. `advance_surveys` honors `opts.seed` after `randomize()`.
- `SpaceLayerCalculator.pick_discovery_class` (around 335) randomizes only when the caller passes no RNG.
- Dialogue Manager and the ant-hill demo are not the 1936 sim.

UI and render `randf` (weather overlay, province insight) is not instanced by the headless `-s` gate. Supply slice pacing uses `Time.get_ticks_usec` for a wall budget, not for a roll.

## UI

`SaveLoadDialog` is a code-built `CanvasLayer` named `SaveLoadPopup`, layer 128. It is not shown headless. Menu Save opens save mode and does not write a file until the player confirms. Menu Load and the end-screen Load open load mode. Overwrite asks `Overwrite <name> (<date>, <nation>)?`. Quicksave and autosave slots are not overwritten from the named-save dialog. Ctrl+S and Ctrl+L stay, go through `_save_v2` / `_load_v2`, and toast. Ctrl+L is handled in `TopInfoBar._input` so MapRenderer's unhandled L (supply overlay) cannot eat it. Every dialog button uses `ACTION_MODE_BUTTON_PRESS`. Esc, Cancel, and the close button arm `arm_ui_close_release_swallow` for that release only.

Settings still opens the Command Center. That is backlog, not this slice.

## Autosave

`AUTOSAVE_FREQUENCY := "monthly"`. Three rotating slots `autosave_1` .. `autosave_3`, plus quit autosave. `EOA_CALENDAR_AUTOSAVE=0` still disables both. Headless writes a calendar autosave only when that env is exactly `1`. Windowed play with the env unset still autosaves. The old live-path skip is not the return path. The helper `_should_skip_live_f5_calendar_autosave` is still called so the IX-1 source lock can see the name. Autosave is deferred off `day_emit`. It is skipped when `CampaignEndDomain.clock_locked()` or `_living_playtest_clock` is set. There is no settings-store selector. The frequency stays the constant.

## Tests

Wired in `tools/eoa_full_test_gates.sh` as `launch_save_reload1_roundtrip`, `_midwar`, `_corrupt`, `_determinism`, and `_ui`. The determinism and UI wrappers take the Godot lock themselves. The other three steps flock inside the gate script. Do not wrap the whole gate in a second flock.

MW200 (`SaveReload1Mw200`, `run_seed` 193601): player justifies on POL at day 150 and declares through `WarStateDomain`. A forced `declare_war` / `make_peace` makes the ITA-FRA war and the SOV-FIN truce. LUX is declared on, its provinces are flipped to GER, and the daily hook capitulates it. Headless then auto-applies the settlement. On a windowed display the same capitulation opens the peace sheet and does not append `peace_settlements` until the player confirms (`CapitulationDomain._capitulate`). At day 200 the headless fixture has 1 player war, 1 AI war, a FRA justify with 8 days left, 1 battle, 1 march, 2 truces, 1 settlement, LUX capitulated (`sr1_midwar.log`).

Headless round-trip after the hour guard (`sr1_rerun_greenA.log`, RESULT=PASS):

| Point | save ms | load ms | bytes |
|---|---:|---:|---:|
| day 0 | 33.7 | 437.8 | 32357 |
| day 60 | 34.2 | 437.4 | 34301 |
| MW200 | 37.3 | 448.0 | 51906 |

Corrupt (`sr1a_corrupt.log`) RESULT=PASS. Mid-war C (`sr1_midwar.log`) RESULT=PASS. UI guard (`sr1_ui_guard.log`) RESULT=PASS, wrapper exit 0. No `SCRIPT ERROR`.

## Mutants

Each patch was reverted. The hour and `run_seed` guards that made M2, M3, and M8 fail are committed in `fd7cbd72`. The first-pass traces for those three were recorded on `630a8599`.

| Mutant | Guard | Result |
|---|---|---|
| M1 drop `campaign_wars` on the save path | A and C | killed. day60 and MW200 hash mismatch; justify, truce, BEL capitulation, and the defeat latch diverged |
| M2 do not restore `run_seed` | B in-process | first pass lived, because the live variable survived. After the test clears `run_seed` before load: killed, traces `0a625e18…` vs `3284a64e…` |
| M3 drop `current_hour` | A | first pass lived, because `current_date.hour` still restored it. After the hour lives only in `current_hour`: killed, `current_hour=0 want 7` |
| M4 apply before validate | D | killed. hash changed on the bad map, the scenario mismatch, and the quickload land-war case |
| M5 write the body straight to the final path | D | killed. the baseline save failed the tmp header check, so the previous file was not replaced by a verified tmp |
| M6 skip the overwrite confirm | E | killed. `overwrite confirm missing` |
| M7 default button release mode | E | killed under the swallow. `save file missing after Save` |
| M8 autosave touches sim state | B autosave-inert | a single `randf()` in the day listener lived: the trace stayed `70ac59ac…`, because the next day's reseed wiped the stolen roll and nothing recorded it. Incrementing `run_seed` killed it: `70ac59ac…` vs `f16523c8…` |
| M9 quickload skips migrate and validate | D | killed. quickload of the bad land-war and the v1 array returned ok |
| M10 `clear_for_load` leaves `campaign_*` | C | killed. `stripped v1 left 1 wars` |
| M11 apply the tag without the setter | A | killed. `supply=USA leader=GER` |
| M12 metadata tag forced to `USA` | A | killed. `metadata player_tag=USA` |

## Gates recorded on `630a8599` (before the campaign-loop rebase)

Seed `multi_ai_decisions` md5, method as in the CL1 docs, five runs in `~/save1_evidence/logs/sr1_seed_x3.log`. All `20fe9063de285f19d4f9b8a105abfd31`, exit 0:

- `sr1_seed_1`, `sr1_seed_2`, `sr1_seed_3`
- `EOA_SIM_DAY_RESEED=0` (`sr1_seed_reseed0`)
- `EOA_CAMPAIGN_LOOP=0` (`sr1_seed_loop0`)

`EOA_CALENDAR_AUTOSAVE=0` on those runs. Feature-on worst `day_ai` in seed 1 was 5.3 ms (samples 5.0–5.4 across seeds 1–3 and the reseed-off run). Worst `day_battles` sample was 0.4 ms. The campaign-loop-off run's worst `day_ai` was 10.0 ms, with `ai_land` about 4.3–4.8 ms. CL1 already recorded that killswitch above the old 9.68 ms bar because neighbour attacks return. The 0.4 ms battle sample also appears with `EOA_SIM_DAY_RESEED=0`, so the reseed is not the source. CL1's published base was worst `day_ai` 8.8 ms and `day_battles` 0.3 ms (`docs/CAMPAIGN_LOOP_1.md`). This slice did not re-profile that untouched base. The +10% comparison against a profile captured before any SR1 edit is UNKNOWN.

`--quick` on the pre-commit tree (`~/save1_evidence/logs/quick_base.log`): `FAILED (failures=14)`, exactly the known 14:

- `test_living_unit_order_loop_product`: `test_integrity`, `test_playtest_clock_does_not_skip_ai_starts`, `test_playtest_clock_does_not_skip_occupation_ticks`, `test_product_wiring`
- `test_unit_card_fill_toe_visibility_product`: `test_integrity`, `test_product_ok`, `test_renderer_source_lock`
- `test_unit_centric_pick_product`: `test_integrity`, `test_product_wiring`, `test_renderer_integrity_strings`
- `test_unit_counter_chrome_product`: `test_integrity`, `test_product_wiring`
- `test_se_england_shire_land_uniformity_product`: `test_prior_feed_products_and_fill_toe_still_pass`
- `test_first_session_play_surface_product`: `test_real_builder_ands_shipped_children`

NE land hit `0.9853 (3148/3195)` (`~/save1_evidence/logs/ne_base.log`). Province data was not edited.

`perf2_fleet_refresh_budget` and `vis1_map_readability` were red on the rebased tip. Ship's CL1 verdict had already flagged both. See the next section.

## Gates on the rebased tip `fd7cbd72`

`tools/eoa_full_test_gates.sh` was re-run with `EOA_CALENDAR_AUTOSAVE=0` and no outer flock. Summary: `~/save1_evidence/logs/sr1_full_gates_summary.log`. The script exits 1 (`FAILED — see steps above`). SR1 steps are green. The reds are the known 14, two steps Ship already flagged, the unit-order loop (CL1 diplomatic Declare), and windowed guards that ask for `xvfb-run` (this PC has none).

SR1:

- `launch_save_reload1_roundtrip` RESULT=PASS. day 0 save 34.0 ms, load 437.9 ms, 32361 bytes. Day 60: 34.6 / 438.1 / 34299. MW200: 36.6 / 449.3 / 51909.
- `launch_save_reload1_midwar` RESULT=PASS.
- `launch_save_reload1_corrupt` RESULT=PASS.
- `launch_save_reload1_determinism` seed `20fe9063de285f19d4f9b8a105abfd31`, two-process `0a625e185f3f9b882d18294252b8a6b7`. In-process and autosave-inert match that same md5.
- `launch_save_reload1_ui` RESULT=PASS (gamescope headless backend). No `SCRIPT ERROR` in the SR1 logs.

Seed inside that gate, from `launch_perf4_live_multi_ai_day.log` and the determinism wrapper, is `20fe9063de285f19d4f9b8a105abfd31`. Dedicated ×3 plus both killswitches on this tip, `EOA_CALENDAR_AUTOSAVE=0`, log `~/save1_evidence/logs/sr1_seed_rebase_summary.log`. All five are `20fe9063de285f19d4f9b8a105abfd31` and `RESULT=PASS`:

- `sr1_seed_rebase_1`, `_2`, `_3`
- `EOA_SIM_DAY_RESEED=0` (`sr1_seed_rebase_reseed0`), worst `day_ai` 5.2 ms, battle samples 0.3–0.4
- `EOA_CAMPAIGN_LOOP=0` (`sr1_seed_rebase_loop0`), worst `day_ai` 9.9 ms, `ai_land` about 4.4–4.8 ms

Seed 1's worst `day_ai` was 5.4 ms. Its battle samples were 0.3, 0.4, 0.5, 0.3, 0.3. The gate run on the same tip printed 0.3 five times. The reseed-off run also reaches 0.4, so the 0.5 ms sample is not the day reseed (0.0007 ms/call).

`unit_board_play_path` is `FAILED (failures=14)`, the same 14 names as the pre-rebase `--quick` list above. Log: `sr1_full_gates/unit_board_play_path.log`.

NE land hit `0.9853 (3148/3195)` in `sr1_full_gates/map_qc.log`.

`launch_perf4_live_multi_ai_day` RESULT=PASS. Worst `day_ai` 5.3 ms. The five printed battle samples are all `battles=0.3`. Reseed cost on the reference trace is 0.0007 ms/call, under 0.1 ms. CL1's published base was worst `day_ai` 8.8 ms and `day_battles` 0.3 ms. This job did not capture an untouched pre-SR1 profile, so a +10% comparison against that missing profile is UNKNOWN. The gate profile (5.3 ms and 0.3 ms) is inside the published CL1 figures. The dedicated seed-1 run later printed one `battles=0.5` sample.

Also green on this tip: `unit_save_path`, `hoi_matrix_product`, `air_physics_p1`, `launch_perf4_daily_sim_tick`, `launch_campaign_loop1_war_gate`, `launch_campaign_loop1_declare_click`, `launch_campaign_loop1_capitulation`, `launch_campaign_loop1_soak`, `launch_campaign_loop1_end_screen`, `launch_prod1_button_open`, `launch_input1_close_click`.

Reds that are not an SR1 save bug:

- `launch_unit_order`: `HeadlessWorldAccurateUnitOrderLoopTest` FAIL (failures=2). `no DemoUnitIcon on Channel fleet 950001`. `war goal not declared (pushes): { "top_id": "conquer_border", "goal_n": 5, "justified": true, "pushes": 0, "tick_count": 1 }`. `pushes=0` matches CL1 FIX #1 (Declare is diplomatic only; the base is `b677890f` / `2a7da052`). Not fixed here. The later summary line `FAIL launch_unit_order missing RESULT=PASS` is the same step. Whether the DemoUnitIcon half was already red on the untouched CL1 tip was not re-run.
- `launch_perf2_fleet_refresh_budget`: `(d) supply glyph pass should enlarge stars (36 px count=0)`. Ship flagged this.
- `launch_vis1_map_readability`: `_refresh_supply_highlights must hide leftover SupplyOutline on L off`, and `L off left 2 SupplyOutline/Glow nodes visible`. Ship flagged this.
- `need xvfb-run`: `launch_render1_draw_guard`, `launch_render1_live_cold`, `launch_hwy3_ruhr_legibility`, `launch_rx1_pixel`, `launch_mv1_pixel`, `launch_mv1_card_up_input`, `launch_rh1_pixel`. `launch_fac1a_pixel` logged only `mkdir: cannot create directory ‘/opt/cursor’: Permission denied`. These fail on this machine on any branch. UNKNOWN on a host that has `xvfb-run`.

The full gate script does not launch the post-capture save/load tests, the command-center smoke, `HeadlessCombat1FightResolveTest`, or `HeadlessOrders1HaltHoldWithdrawTest`. Those were run separately on this tip (`~/save1_evidence/logs/sr1_extra/summary.log`), one Godot at a time, `EOA_CALENDAR_AUTOSAVE=0`.

Green: `HeadlessWorldFullPostCaptureSaveLoadConquestStateTest`, `HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest`, `HeadlessWorldFullPostCapturePostLoadCombatEquipCycleTest`, `tools/command_center_save_load_smoke.gd` (`CC_SMOKE PASS`), `HeadlessCombat1FightResolveTest` RESULT=PASS, `HeadlessOrders1HaltHoldWithdrawTest` RESULT=PASS.

Red, one failure each, and not an SR1 save miss: `PostLoadPlayability`, `PostLoadConquestLoop`, `PostLoadChainAssault`, `PostLoadSecondProvinceFlip`, `PostLoadSlotSaveLoad`. Each dies on `can_assault` with `Not at war with France` or `Not at war with BEL`. That return is `BattleManager.can_assault_province` when `WarStateDomain.loop_enabled()` and the pair is not at war. The line is already on `2a7da052` (`BattleManager.gd` line 281). This branch does not modify `BattleManager.gd`. The tests restore map, production, and leaders. They never call `declare_war`. The same diplomatic-only assault rule turns the unit-order push count to 0. Not fixed here.

The smoke left `slot_cc_smoke.eoasave` and `slot_cc_ui.eoasave`. Both were removed by exact path. Mike's two JSON files were unchanged.

`launch_live_lon_probe` (ScenarioLoader autosave session) writes the real slot `autosave` through `_save_v2`. The gate left `autosave.eoasave` (md5 `d8161044c595ede1e2daa0d34fcb9672`, 68349 bytes, kind auto, USA, day 0, wall `2026-10-19T00:28:30`) and `autosave.eoasave.bak` (`5efdea355a34c9c3d767aa30e5b5ed1f`). Both were removed by exact path. Mike's `autosave.json` (`31b34b8d3b843d1ffd2bda86b582d443`) and `quicksave.json` (`3170392a409d9aa0b944d625de65f6d4`) were not modified. Headless calendar and quit autosave stay off unless `EOA_CALENDAR_AUTOSAVE=1`. This write is the named slot, not the monthly path.

## Windowed perf

Private gamescope headless backend, 1280×800. `DisplayServer` name `X11`. Not the live `:0` desktop. `EOA_SLOW_BOX` was not set. Log: `~/save1_evidence/logs/sr1_windowed_perf.log`.

The helper's `ok` flag was false because a windowed player-win capitulation leaves the peace sheet pending and does not append `peace_settlements` (`CapitulationDomain._capitulate`). Day was 200, with one player war. The measurement ran on that world.

| | measured | bar |
|---|---:|---:|
| save | 40.2 ms | 1000 ms |
| load | 447.7 ms | 3000 ms |
| quit autosave | 42.8 ms | 1000 ms |
| file | 51740 bytes | 8 MB |
| VmHWM increase across save, load, and quit | 4 KB | 300 MB |

VmRSS immediately before the save was 1,718,576 KB (1678 MiB), which is the booted world, not the save spike. RESULT=PASS. gamescope 3.16.25 printed `No CAP_SYS_NICE` and can segfault on teardown (exit 139) after the script has quit. That teardown is not a sim failure.

Headless MW200, for comparison only: save 37.3 ms, load 448.0 ms, 51906 bytes.

## Differences from the brief's read of `25599270`

- `player_tag` is stamped from the live nation after the `"USA"` placeholder. It is not left as USA.
- `quicksave` / `quickload` / `load_game` go through the v2 path, including migrate and validate.
- `current_hour` and `run_seed` are in `time`. The flush queue is not saved. Saves run when the caller is between days (the tests) or on the deferred autosave after `day_emit`. A save requested mid-flush waits only in the sense that calendar autosave is deferred off the emit. A manual save writes on the call.
- `SessionPlayers` and `NationalSpiritManager` are gathered. Dialogue and net session are exempt, as in the manifest.
- Live autosave is no longer skipped. `map_ui` is still omitted when `is_live_f5_play_path()` is true (UI only).
- `hierarchy_membership_live` is saved, not re-seeded empty.
- Province `factories` are in the map payload. v1 files lack the key and apply skips them. That closed a JAP/CHI factory-weight drift after load.

## CL1 note (not fixed)

`WarStateDomain.ai_stopped()` returns true when `campaign_end` has an `outcome`, including when `keep_playing` is true. `CampaignEndDomain.clock_locked()` honors `keep_playing`. A keep-playing load restores the clock run, but AI stop follows `ai_stopped()`. Repro: latch an outcome, set `keep_playing`, call both. Left for a CL1 fix.

## Existing-test edits

Additive, so the old names and strings stay:

- `HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest` reads `read_save_body(SLOT)` instead of parsing the file as JSON.
- `tools/command_center_save_load_smoke.gd` expects `slot_cc_ui.eoasave`.
- `tools/save_smoke_runner.gd` checks the absolute path the save returned.
- `NationalSpiritManager` gained `get_save_data` / `apply_save_data`.
- `CampaignEndScreen` load button uses press action mode. Its Load opens the load dialog.

GameData versus `c4280e38` in the feature commit: +51 / −6 lines. No `project.godot` change, no new autoload, no province data change.

## Evidence

Outside the tree, `~/save1_evidence/`:

- `user_saves_backup_2026-10-18/` copy of Mike's saves before the first test.
- `v1_fixtures/sr1test_v1_day0.json`, `sr1test_v1_day40.json`, `sr1test_v1_end.json` (made on the base build).
- Logs named above, plus `sr1_mutants.log` and `sr1_rerun.log`.
- Screenshots: `save_dialog.png`, `overwrite_confirm.png`, `load_list.png`, `load_damaged_row.png`.

In the tree, `docs/evidence/save_reload1/save_dialog.png` (36829 bytes) and `load_list.png` (37820 bytes).

Mike's `user://saves/` after the gate cleanup holds only `autosave.json` (`31b34b8d3b843d1ffd2bda86b582d443`, mtime Oct 18 15:03) and `quicksave.json` (`3170392a409d9aa0b944d625de65f6d4`, mtime Oct 8). The two `.eoasave` files the LON probe wrote were deleted by exact path.

## Decisions implemented

No Ironman. Unlimited named slots, one quicksave, three rotating autosaves. Monthly autosave and quit autosave. No cloud saves. A declared war with no player orders is in `campaign_wars` and round-trips.

## UNKNOWNs

- gamescope teardown can exit 139 after a passing script. The save numbers above are from the script's own print, before that teardown.
- Untouched-base `day_ai` / `day_battles` profile, so the +10% bar against a pre-SR1 capture is UNKNOWN. On this tip the live profile is 5.3 ms and 0.3 ms. CL1 published 8.8 ms and 0.3 ms.
- `perf2_fleet_refresh_budget` and `vis1_map_readability` are red on `2a7da052` plus this branch. Ship flagged both on the CL1 verdict. Whether they were red on `c4280e38` before FIX #1 was not re-run.
- Whether `no DemoUnitIcon on Channel fleet 950001` was already red on untouched `2a7da052`. The `pushes=0` half is the diplomatic-only Declare rule on that base.
- Pixel guards that require `xvfb-run`. This PC has `gamescope` and no `xvfb-run`.
- `WarStateDomain.ai_stopped()` versus `keep_playing`, noted above and not fixed.
