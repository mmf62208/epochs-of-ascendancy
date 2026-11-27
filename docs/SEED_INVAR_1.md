# SEED-INVAR-1 (#215)

Diagnosis only. No product change. Base `d38cb4d2`. Commit 2 was not taken. The reason is in section 5.

Prior soaks on this tip, one seed per process, reported one controller map for several seeds. Sim's Nov 25 aivai d180 (no AI lines) gave `ctrl_md5=6b7fe902cfb5e26c68ae7053c56910d9` for seeds 1, 2, 3, and `20fe9063`. After AI-PROD-1, with lines on, seeds `20fe9063`, 1, 2, and 3 at d180 gave `ctrl_md5=b081be2ae62329fa44eab875affbce78` (13 lines, 24 battles, total_changes 36). This note does not re-run d180. The d30 measurement below is a different harness and is not that hash.

`HeadlessSeedInvar1Test` is a measurement. `RESULT=PASS` means the runs finished and printed the table. It does not require seeds to differ unless `SEED_INVAR_1_ASSERT=differs`. That env stays unset in this commit.

## 1. Where randomness enters

`TimeManager.run_seed` defaults to 0 (`scripts/autoload/TimeManager.gd:80`). The comment at `:77–79` says AI land-battle start, empty-hex siege, and light capture do not draw the reseeded RNG, so soak seeds stay identical. The d30 run below does draw during land-battle start. The comment describes the intended design. It does not describe this path. This slice does not edit `TimeManager.gd`.

`_reseed_sim_day` (`:2063`) returns when `run_seed == 0` (`:2064`). Otherwise it calls global `seed(hash([run_seed, day]))` (`:2067`). On Godot 4.7.1 that global stream is not the `RandomNumberGenerator` class. A probe with `seed(424242)` drew `0.4071629345417` from `randf()` and `0.34554859995842` from `RandomNumberGenerator.seed = 424242`. `HeadlessSeedInvar1Test` prints `rng_api_match=false`. Draw counts in this note use only the global RNG. A class-RNG count of zero would be the wrong tool.

The live F5 path reseeds again at the start of each queued phase, all with the same day index:

- calendar roll, `advance_days` `:1155`
- `day_emit` flush `:1444`
- `day_ai` flush `:1467`
- `day_battles` flush `:1473`

A draw in an earlier phase cannot change the RNG the next phase sees. Only a write of game state survives the next reseed. The next day reseeds from `(run_seed, next_day)` before its listeners.

The harness calls `advance_live_f5_equivalent_days` (`:1236`). That sets the live-F5 clock, so `is_interactive_light_sim` (`:1945`) is true for the flush. The call clamps to 1–20 days. The test calls it once per day, then waits two frames so `_flush_pending_light_captures` runs.

A temporary phase counter (not committed; removed from `TimeManager.gd` and `BattleManager.gd` before this commit) counted global draws inside each phase and restored the stream afterward. Controller hashes did not change when the counter was inserted. On d30 with AI lines on, seeds 1, 2, 3, and a repeat of seed 1:

| Phase | Seed 1 | Seed 2 | Seed 3 | Seed 1 again |
|---|---:|---:|---:|---:|
| calendar, day_emit, multi_ai, ai_infra, ai_declare, ai_cover, day_battles | 0 | 0 | 0 | 0 |
| `try_ai_start_land_battles` after the two cover calls | 1340 | 1355 | 1395 | 1340 |

About 45 global draws per day, all inside `BattleManager.try_ai_start_land_battles` (`scripts/combat/BattleManager.gd:1021`) after `try_ai_cover_threatened_borders` (`:686`) and `try_ai_cover_capital_approaches`. The seed-1 repeat of the count matches, so the count follows `run_seed`, not process position. The test's own `rng_draws` column stays 0: it counts draws after the day returns, which is after the `day_battles` reseed, and that phase draws 0 times.

No other `randf` / `randi` on the traced light path accounts for that volume. The call that does is `can_assault_province` (`:346–352`), reached from the border scan (`:1115`) and from `_border_targets_have_division` (`:1367`). It calls `ProvinceInsight.get_battle_preview` (`scripts/map/ProvinceInsight.gd:9428`). That function draws global `randf` at:

- `:9481` encircled (`supply_mod < 0.7 or randf() < 0.1`)
- `:9495` sabotage, only if `AgentManager.get_depot_state` is missing and `get_active_missions` exists
- `:9508` leader impact
- `:9516` counter
- `:9578` air-factor string
- `:9592` marine modifier (`"marine" in terrain or randf() > 0.7`)

`AgentManager` has neither `get_depot_state` nor `get_active_missions`, so `:9495` does not run. The other five run on a normal preview. Five draws times roughly nine previews per day is the measured ~45. This slice did not leave a counter on that single call. The volume, and the absence of any other `randf` on this path, is the identification.

Sites that do **not** draw on this path (phase count 0, or no `randf` in the file):

| Site | Depends on `run_seed` | Reached on this light day |
|---|---|---|
| `BattleManager.execute_province_assault` casualty rolls `:492–494` | Yes, if called after a reseed | No. Light empty hex uses `_tick_empty_hex_capture` (`:575` in `start_land_battle`). Light empty-fid defender uses `_apply_attacker_win_capture_light` (`:616`). The non-light `else` branches call `execute_province_assault`. |
| `BattleManager.apply_combat_outcome` org/ready/strength jitter `:3441–3461` | Yes | No. Caller is `execute_province_assault`. Open-battle `cas_total` stayed 0, which matches: those casualty keys are not written. |
| Naval fallback `:3911`, `:3913` | Yes | No. Light sim skips daily AI combat (`TimeManager._should_run_daily_ai_combat` `:1530`). |
| `CombatResolver` `:860`, `:895–896`, `:2081` | Yes | No. Not on the light flush. `get_combat_width_for_battle` (`:1339`) has no `randf`. |
| `LandCombatPower.combat_power` `:598` and `BattleManager.land_combat_power` `:1640` | No `randf` in the file | Yes, via `_ai_front_powers` `:2399`. They do not draw. |
| `WarStateDomain.try_ai_declare_wars` | No `randf` in the file | The call runs (`TimeManager.gd:1636`). Draw count for that step was 0. |
| Cover / garrison raise (`BattleManager.gd:686`, `:815`) | No draw measured | The calls run. Draw count before the planner was 0. |
| `InfrastructureDevelopmentManager` full-board `randi` `:406` and `randf` `:1973` | Yes | No. `_should_run_full_board_ai_invest` (`:1484`) is false on the live-F5 path. `try_ai_start_infra_project` (`:2019`) does not draw. Phase `ai_infra` was 0. |
| `SupplyManager` heavy-day `randf` (`:1292`, `:2492`, `:2507`, `:2602`, `:2612`, `:2618`) | Yes | No. Light listener does not take that path. `day_emit` draws were 0. `get_depot_state` (`:266`) is a dictionary read. |
| `GameData` monthly/crisis `randf` | Yes | Not in a January d30 window, and not inside `apply_interactive_multi_ai_day_live` (no `randf` in that function, `:26429–26662`). |
| `RelationsManager` alliance roll | No. `hash(key + day) % 100`, not `run_seed`. | Listener can run. It does not follow the sim seed. |
| Trade / Space `RandomNumberGenerator.randomize()` | No. Wall clock, not `run_seed`. | Not the land-battle flush. |

`LandBattleAi.gd` and `CapitulationDomain.gd` contain no `randf` / `randi`. No AI decision script reads `run_seed`. The only way `run_seed` changes the day is the global `seed()` in `_reseed_sim_day`.

## 2. Why control still moves

The open-land winner is deterministic. `_land_daily_tick` (`BattleManager.gd:3206`) drains org by `2 * LAND_EVEN_DRAIN * (enemy_power / total_power) / terrain_stretch` (`:3230–3233`). The side under `LAND_ORG_BREAK` loses; the higher remaining org wins; a tie is a draw (`:3234–3242`). No `randf`. That tick runs in `day_battles`, which drew 0 times. It cannot be the first place the seeds diverge. It resolves whatever board `day_ai` already wrote.

`plan_day` does not read the preview rolls. `can_assault_province` copies only `air_dominance_level`, `air_power_ratio`, and `air_superiority` (`:350–352`). `get_battle_preview` never sets those keys, so they stay `"none"`, `1.0`, and `false`. `encircled`, `leader_imp`, and `counter` are locals and are not stored. Sabotage mutates a local `def_pow` that is stored on the returned dict and then ignored: the scan at `:1115` keeps `ok`, `formation_id`, and `defender_tag`, and scores with `_ai_front_powers` (`:1119`), which has no `randf`. `start_land_battle` (`:546`) calls `can_assault_province` again and, on the light path, does not call `execute_province_assault`.

So the rolls are not an input to the attack pick, and the battle tick does not roll. d30 control still differs across seeds 1, 2, and 3 (section Measured). The same seed repeated in-process matches control. Starting armies match (`start_n=557`, one `start_str_md5`). The difference is `run_seed`, and it is created during `try_ai_start_land_battles`, which is the only phase that draws. The assignment that flips a province was not isolated past that function. A callee of `get_battle_preview` that writes state was not found in the function body (`get_depot_state` reads, the assault card is an estimate, combat width returns a float). This slice stops there. It does not edit `BattleManager.gd` or `ProvinceInsight.gd` to split the call.

`cas_total=0` is not evidence that assaults were skipped. The casualty keys are written by `execute_province_assault`, and the light path does not call it. Open battles at day 30 are the ones still running, not the captures already applied.

The seed-1 repeat matches `ctrl_md5`, `battles`, `org_sum`, and `str_sum` (printed to 6 decimals) and does not match `str_md5`. That fingerprint is per-formation `%.5f` strength and org. The sums match and the per-unit string does not, so a small redistribution remains that does not move the controller map. The test does not assert `str_md5`.

An earlier run that wiped production lines after `boot_ai_production` is discarded. It is not in the table. The runs cited here keep 13 lines, restore `ProductionManager` stockpiles at the start of each seed, and drain four frames before the boot so a previous seed's deferred capture hits the old map.

## 3. What AI decisions read

These picks do not call `randf`. They are functions of tags, powers, and `day_index`.

- Attack order: `try_ai_start_land_battles` sorts majors by `LandBattleAi.personality_aggression`, then rotates with `day_index % n` (`BattleManager.gd:1059–1064`).
- Target pick: `LandBattleAi.plan_day` (`:117`) scores with `score_opportunity` (`:48`), sorts by score then tag (`:167–171`), and rotates ties within 2.0 score by `day_index % ties` (`:173–184`). `run_seed` is not an input.
- Siege continue: `BattleManager.gd:1241–1270` forces the open siege and skips `plan_day`.
- Capture: `_apply_attacker_win_capture_light` (`:2542`) writes the attacker tag. No roll. Empty-hex progress is `_tick_empty_hex_capture` (`:2026`).
- Production pick: `GameData.apply_interactive_multi_ai_day_live` (`:26429`) rotates with `day_index % n` (`:26521`). No `randf`. Called from `TimeManager._maybe_run_interactive_multi_ai` (`:1550`).
- Infra pick: `try_ai_start_infra_project` (`InfrastructureDevelopmentManager.gd:2019`) uses `posmod(day_index, majors)`. No roll.
- Declare war: `WarStateDomain.try_ai_declare_wars`, no `randf`.

The preview `randf` calls are the exception. They run inside the assault check the planner uses as a gate, and their results are not copied into the opportunity dict. They are not a named decision.

## 4. Seed-pin interaction

`run_seed == 0` skips `_reseed_sim_day` (`:2064`). The global RNG is then whatever the process already had. The preview `randf` calls still run, because nothing in `get_battle_preview` checks `run_seed`.

The Perf4 pin `20fe9063de285f19d4f9b8a105abfd31` is the md5 of the `multi_ai_decisions=` line from `HeadlessPerf4LiveMultiAiDayTest` with `EOA_PERF4_SEED_ONLY=1`. That harness calls `seed()` itself and does not set `run_seed`. The line it hashes is the `day_index` rotate in `apply_interactive_multi_ai_day_live`, which has no `randf`. Inside a day, multi-AI production runs before land-battle start (`_profile_day_ai_steps`). A change that only adds draws when `run_seed != 0` leaves that pin on the `run_seed == 0` path. Removing or gating the preview `randf` calls would change the `run_seed == 0` path too, because those calls already draw when the reseed is skipped. That can move any later global consumer in the same process. This slice does not do it.

Identity, twin, and trace (`tools/eoa_campaign_save1_identity.sh`) use the `run_seed == 0` save/reload path. A branch that is dead at `run_seed == 0` does not move them. A change to `_reseed_sim_day`, to the production rotate, or to battle resolution that still runs at `run_seed == 0` can move them. This commit edits neither `TimeManager.gd` nor `BattleManager.gd`.

## 5. Options for OP

No option is applied here.

### A. Treat a 3-seed soak as one sample

That matches the older d180 soaks (one controller map for seeds 1, 2, 3, and `20fe9063`). It does not match this d30 harness with AI lines on: seeds 1, 2, and 3 already differ, and seed 1 repeated matches. Documenting "the light path never draws" would repeat the comment at `TimeManager.gd:77–79`, which this measurement contradicts.

- Files: this note only.
- Pins: unchanged.
- Risk: a later soak that uses this harness will report three worlds and look like a regression against the d180 writeup. The d180 run was not repeated here, so this note does not say the d180 map has started to move.

### B. Feed `run_seed` into a few AI decision draws, only when it is non-zero

The hook that stays out of the forbidden files is `LandBattleAi.plan_day` tie start (`:184`): when `TimeManager.run_seed != 0`, use `hash([run_seed, day_index]) % ties` instead of `day_index % ties`. About five lines. `TimeManager` stays read-only. `BattleManager` stays untouched.

That hook is not the measured draw. The draws that already follow `run_seed` are the preview `randf` calls inside `can_assault_province`. Control at d30 already differs with no product edit. A test that asserts `SEED_VARIANCE=differs` would pass with the hook compiled out, so the required mutant (fix disabled, test FAIL) cannot fail. Shipping the hook would add a second lever on top of an effect this slice did not isolate, and it would not explain the draws.

- Files if OP still wants it later: `scripts/combat/LandBattleAi.gd`, this note, and the assert in `HeadlessSeedInvar1Test.gd`.
- Pins: the `run_seed == 0` path stays byte-identical if the new branch is dead at 0. The Perf4 seed and the identity/twin/trace pins should not move. Non-zero seeds change only when a day has two or more picks within 2.0 score and the siege-continue branch did not already force the pick.
- Risk: the mutant proof does not work while d30 control already differs. Not done in this slice.

### C. Stop the preview from drawing on the headless decision path

The live draws are `ProvinceInsight.get_battle_preview:9481–9592`, called from `BattleManager.can_assault_province:346–352`. A fix that skips that call, or that builds the assault gate without `randf`, touches `BattleManager.gd` or `ProvinceInsight.gd`. `BattleManager.gd` is forbidden here (open drafts own it). `ProvinceInsight.gd` is a map preview, not a small AI-decision hook, and gating its existing `randf` calls changes the `run_seed == 0` path (section 4). Either file is outside the ~60-line option-B cap as specified. Not done.

- Pins: unknown until measured. Stopping the draws can make d30 control identical again, and can move identity/twin/trace if those runs still call `can_assault_province` at `run_seed == 0`.
- Risk: control, battle count, and the d180 bands can all move, because the draws already depend on `run_seed` once the reseed runs. OP should see a before/after on the pin and on d180 before this lands.

Recommendation: stop after this diagnosis. Do not add the `LandBattleAi` tie hook. Do not edit `BattleManager` or `ProvinceInsight` in this branch.

## OP decision (Nov 26, after #220 KEEP)

**A accepted as a caveat for the old d180 soaks only:** a multi-seed aivai d180 writeup whose seeds shared one `ctrl_md5` counts as one sample, not three independent worlds. This d30 harness with AI lines on already differs across seeds 1/2/3 and is not covered by A. **B rejected.** Do not add the `LandBattleAi.plan_day` tie-hash hook. It is not the measured lever. **C deferred** to its own slice (gating the preview `randf` calls). Not in this PR. Any later C needs its own OP GO, with a before/after on the seed pin, identity/twin/trace pins, and the d180 bands. This note does not re-run d180 and does not claim the old d180 map has started to move.

## Measured (d30, AI lines on)

Harness: `HeadlessSeedInvar1Test`. Player USA. `boot_ai_production("USA")` (13 lines, kept). `seed(1)` and `run_seed = 0` during boot, then `run_seed` in {1, 2, 3, 1}. Stockpiles snapshotted once and restored each seed. `seed_1936_start_garrisons`. GER declares on POL. Each day is `advance_live_f5_equivalent_days(1)` plus two idle frames. `ctrl_md5` is md5 of sorted `pid=controller` land lines. It is not the unsorted `JSON.stringify` the d180 sim prints, so it will not equal `b081be2a` even when the map matches that run. Compare seeds to each other.

`cas_total` sums `attacker_casualties` + `defender_casualties` on battles still open. `rng_draws` is the sum of global draws after each day's `day_battles` reseed (0, as explained above). `str_md5` is formation id, strength, and organization for GER, FRA, ENG, SOV, ITA, JAP, POL, and USA.

The phase split above is from the temporary counter (`/tmp/seed-invar-1-meas/meas.log`). That counter was removed before commit. The controller table is from that run and from a clean rerun with the counter gone (`/tmp/seed-invar-1-clean/meas.log`, exit 0, 0 SCRIPT ERROR). The four `ctrl_md5` values match. Loadavg on the clean run was `4.12 3.82 3.88` at start and `4.80 4.03 3.95` at end.

| Seed | ctrl_md5 | battles | cas | org_sum | str_sum | changes | ai_start draws | lines | start_n |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | `2d960fd86cbfef86c84b015077af627d` | 6 | 0 | 549.079975 | 554.630000 | 6 | 1340 | 13 | 557 |
| 2 | `c62ea066c6e75005149393086214e0ff` | 8 | 0 | 543.684343 | 554.480000 | 12 | 1355 | 13 | 557 |
| 3 | `ea1339dc86b417f1a1ba4991d4fa9bd2` | 7 | 0 | 548.331556 | 555.560000 | 7 | 1395 | 13 | 557 |
| 1 again | `2d960fd86cbfef86c84b015077af627d` | 6 | 0 | 549.079975 | 554.630000 | 6 | 1340 | 13 | 557 |

`start_str_md5=a4c671c1fb981c707e4f81c8a6ca0067` on all four. Seed-1 `str_md5` is `cbac3af9e53766e51e08ed66aba01914`. The repeat is `b13c60e0d7868002700ea89e89224007` (ctrl identical, str fingerprint not). Seed 2 `str_md5=073e94d3d68b0aef13da9b6e73a507c1`. Seed 3 `str_md5=62a42d36761346e6b176cee54e9f390f`.

`SEED_VARIANCE=differs`. `REPEAT seed=1 ctrl=identical str=differs`. `RESULT=PASS`. 0 SCRIPT ERROR on that log.

## STRMD5-DRIFT-1 (Nov 26, after #220 KEEP)

Measuring harness: `HeadlessStrMd5Drift1Test`. Same boot/wipe as `HeadlessSeedInvar1Test` (copied, that file not edited). Player USA, AI lines on, GER declares on POL, `run_seed = 1` twice in one process, d30. `RESULT=PASS` means both runs finished and the per-unit / id diff was printed. No assert on drift.

### Measured (in-process seed 1 ×2)

`start_str_md5=a4c671c1fb981c707e4f81c8a6ca0067` on both. `start_ctrl_md5=88d8432561d7b781976f8b874a83cf62` on both. `run_seed` stayed 1 on both (day 1 and day 30). `hash([1,1])` and `hash([2,1])` were stable across passes. Daily reseed ran (4 calls/day). All 557 FORM_TAGS units are `garr1936_*`. `fielded_seq=0`, `leader_id_seq=0`, `replacement_seq=0`, `equipment_flow_seq=0` at start and end of both runs. No id only on one run.

| Pass | ctrl_md5 | battles | changes | org_sum | str_sum | str_md5 | next_land_battle_seq end | reseed_calls start→end |
|---|---|---:|---:|---:|---:|---|---:|---|
| 1 | `2d960fd86cbfef86c84b015077af627d` | 6 | 6 | 549.079975 | 554.630000 | `cbac3af9e53766e51e08ed66aba01914` | 7 | 0→120 |
| 2 | `c62ea066c6e75005149393086214e0ff` | 8 | 12 | 543.684343 | 554.480000 | `073e94d3d68b0aef13da9b6e73a507c1` | 16 | 120→240 |

Pass 1 matches the #220 seed-1 row (including `str_md5`). Pass 2 matches the #220 **in-process seed-2** row (`ctrl_md5`, battles, changes, sums, `str_md5`), not the #220 seed-1-repeat row (`str_md5=b13c60e0…` with identical ctrl). This 1→1 repeat is a different war, not a same-map fingerprint drift. `str_sum` d=−0.150000 and `org_sum` d=−5.395631 do **not** cancel. 24 same-id GER/POL garrisons changed strength and/or org (and several changed `stationed_province_id`). `_unit_equipment_stock` has the same 576 keys; 24 of those keys changed, matching the 24 units. 0 SCRIPT ERROR on the clean re-run (`/tmp/strmd5-drift-1-r1.log`).

The #220 leftover-in-process-state reading still holds. The missed state is not a formation-id or equipment-flow allocator on this path: `LeaderManager._alloc_fielded_formation_id` (`scripts/leaders/LeaderManager.gd:464–469`) never ran, and `ProductionManager._equipment_flow_seq` (`scripts/autoload/ProductionManager.gd:76`, `:1688`) stayed 0. `_next_land_battle_seq` (`scripts/combat/BattleManager.gd:46`) is reset to 1 by `_clear_battle_residue` and then diverges because the wars diverge.

### What the copied wipe does not touch (file:line)

`HeadlessSeedInvar1Test._wipe_sim_state` / `_clear_battle_residue` (copied into the new test) clear formations, production lines, factories, open battles, pending captures, empty-hex sieges, land-battle seq, pending sim events, infra projects, and `_garrisons_1936_seeded`. Boot reloads the board (`MapManager.initialize_from_map_data` `:146`) and `SupplyManager.build_network` (`scripts/supply/SupplyManager.gd:212`) rebuilds hubs and depots. That is why start ctrl and start `str_md5` match.

It does **not** reset:

- `SupplyManager.division_deployments` (`scripts/supply/SupplyManager.gd:22`). `build_network` (`:212–236`) does not clear it. Keys are formation ids. Garrison ids are stable (`garr1936_{TAG}_{pid}`, `LeaderManager.gd:726` / `field_1936_garrison` `:800`). Pass 1’s end-of-war stations can still be in the dict when pass 2 reseeds the same ids.
- `SupplyManager.force_registry` (`:18`, a process-lifetime `CombatPresenceRegistry`) and `attrition_ledger` (`:23`).
- `LeaderManager._fielded_seq` / `_leader_id_seq` / `_replacement_seq` (`scripts/leaders/LeaderManager.gd:177–181`). `clear_all_formations` (`:1629–1633`) clears the formation dict and the garrison latch only. Latent: not the lever here because those seqs stayed 0.
- `LeaderManager.leader_pool` (`:170`; count 18 both passes, values not hashed).
- `ProductionManager` interactive-AI caches (`_interactive_ai_day_cache_ready` `:86`, `:350–372`). Stockpiles and `_equipment_flow_seq` are restored from the pre-run snapshot; the cache flag is not.
- `TimeManager._reseed_calls` (`scripts/autoload/TimeManager.gd:82`; 0 vs 120 at ALLOC_START). Cosmetic; `_reseed_sim_day` (`:2063`) does not read it.
- `TimeManager._playtest_ai_started_to_ids` (`:95`).

The 24 changed units are the GER/POL garrisons that fought. Same ids, different str/org/station at d30, sums do not cancel. That matches leftover per-unit supply/combat/station state keyed by stable `garr1936_*` ids, not a new-id allocator.

The #220 fourth row (seed 1 after seeds 1/2/3) matching ctrl with a `str_md5`-only drift is a milder leftover at a different in-process position. This slice did not re-run that 1/2/3/1 order.

### Fix options (not applied)

No option is applied here. Any product wipe/allocator fix needs its own OP GO.

1. **Clear `SupplyManager.division_deployments` (and `force_registry` / `attrition_ledger`) in the test wipe, or at the start of `build_network`.** Expected: the in-process seed-1 repeat keeps pass 1’s ctrl/sums/`str_md5`. Risk: `build_network` is on the live F5 reload path; clearing presence there can move identity/twin/trace and the d180 bands if those runs rebuild the network mid-process. A test-only wipe is the smaller first check.
2. **Reset `_fielded_seq` / `_leader_id_seq` / `_replacement_seq` in `clear_all_formations`.** Hygiene for a later fielded-unit path. Not the measured d30 lever (`fielded_seq` stayed 0).
3. **Option C** (gate preview `randf` in `can_assault_province` / `get_battle_preview`) stays deferred. It is a different lever. Own OP GO, with a before/after on the seed pin, identity/twin/trace, and the d180 bands.
