# AI-CREDIBLE-1

Credible opposing nations for the 1936 campaign. Branch `grok/ai-credible-1`.

Engine Godot 4.7.1 (`tools/run_godot.sh`). No engine bump. No `project.godot` edit. No new autoload. No province or map edit. GameData was not edited.

## Base

Work started at `9c2a97607e948bd237c485801b7283be1f03faff` (CL1 FIX #2, tip of `grok/campaign-loop-1`, second parent of the #113 merge).

Before the soak gate, the branch was fast-forwarded onto `origin/main` `d00dc8ed68e8e3d3253bdd50cb9eb890251603b9` (`Merge pull request #113`). That merge also contains UI-POLISH-1 (#114). SAVE-RELOAD-1 (`origin/grok/save-reload-1` `c7b93255`) is not an ancestor of this tip. The fast-forward happened before any push of `grok/ai-credible-1`, so the first push does not need `--force-with-lease`.

`docs/CURRENT_STATE.md` and `docs/GAME_STATUS_SNAPSHOT.md` were not edited by this job. The lines they gained came from the main fast-forward.

Slices AIC1a–e were implemented and verified together on one tip. There are no intermediate slice SHAs.

## What shipped

Static domains, called from the existing day tick:

| Domain | Role |
|---|---|
| `scripts/core/AiCredibleDomain.gd` | Killswitch, goals file, trace, `tick_day` |
| `scripts/core/AiWarPlannerDomain.gd` | Scored justify / cancel, peace |
| `scripts/core/AiDefenceDomain.gd` | Capital march |
| `scripts/core/AiEconomyDomain.gd` | Needs-biased production and research upkeep |
| `scripts/core/AiFrontPlanDomain.gd` | Main axis, air assignment, at-war start cap |
| `scripts/ui/AiPeaceNotice.gd` | Accept / decline notice for a player war |
| `data/scenarios/ai_goals_1936.json` | Weights and preconditions. No dated events |

Call sites:

- `TimeManager._profile_day_ai_steps` runs `ai_credible` after `ai_land`.
- `WarStateDomain.try_ai_declare_wars` calls the planner when the killswitch is on, and still uses `_begin_justify` / `_complete_ready_justifies`.
- `BattleManager.try_ai_start_land_battles` raises the start cap to `at_war_starts_per_day` (default 2, and `LandBattleAi.plan_day` still clamps to 1..2) and filters opportunities onto the axis when one matches. A tag whose axis matches nothing keeps its original opportunities.

`EOA_AI_CREDIBLE=0` is the only new environment switch. Unset means on. Off skips `tick_day`, falls back to `_pick_declare_target`, keeps start cap 1, and writes no credible trace.

Decisions are pure functions of world state and day. Ties break on the tag string. Dictionaries of neighbours and backers are walked in sorted key order. No `randf`, `randi`, or `randomize` on the credible path. The three soak seeds therefore produce the same trace. The seed labels the run. The double run is the process-determinism check.

## Clock fix that the soak required

`advance_live_f5_equivalent_days(20)` advances the clock to the chunk end, then flushes one `day_ai` event per day. Those handlers were reading `total_days_elapsed`, so every day in the chunk decided as the chunk-end day. With `ai_declare_checks_per_day` 1 and 8 declare tags, a multiple of 20 lands only on GER or USA. USA is under `ai_declare_min_aggression` 0.6, so only GER ever justified. The 1461-day probe before the fix declared only GER–POL (trace md5 `fa5ba3592b517c6181689f70351f0631`, 4 lines).

The `day_ai` event now stores `elapsed` at queue time. While `EOA_AI_CREDIBLE` is not `0`, declare, land-battle start, and `tick_day` use that day. The killswitch path still reads the chunk-end clock, which is the previous behaviour. `total_days_elapsed` itself is not rewritten, so `WarStateDomain._day()` (war `start_day`, truce, `make_peace`) stays on the flush clock. In a 20-day soak chunk the event-log day can be up to 19 days later than the trace day. Play at 1× flushes one day at a time, so the two match.

## Seed

`HeadlessPerf4LiveMultiAiDayTest`. Hash is md5 of the text after `HeadlessPerf4LiveMultiAiDayTest: ` on the `multi_ai_decisions=` line, plus a trailing newline. The collector calls `apply_interactive_multi_ai_day_live` directly. That function was not edited.

Target `20fe9063de285f19d4f9b8a105abfd31`. No new hash. Mike does not need to approve one.

Measured on the pre-hook tree (evidence `~/ai1_evidence/base_seed_1.log`): hash `20fe9063`, `worst_day_ai=5.2ms`, budget 500. The profile steps were `multi_ai`, `ai_infra`, `ai_land` (no `ai_credible`).

Measured with the feature on, before the per-day flush fix (`seed_new_1/2/3.log`): hash `20fe9063` three times. `worst_day_ai` 5.5ms, 5.5ms, 5.8ms. Sample `ai_credible` step 0.5–0.6ms.

Final tip, feature on, three runs (`seed_on_1/2/3.log`), 0 SCRIPT ERROR:

| Run | Hash | `worst_day_ai` |
|---|---|---|
| 1 | `20fe9063de285f19d4f9b8a105abfd31` | 5.2ms |
| 2 | same | 4.9ms |
| 3 | same | 5.1ms |

Run 1 day profiles: `ai_credible` 0.5, 0.5, 0.5, 0.6, 0.5ms beside `ai_infra` about 3.5–3.9ms. +15% of the 5.2ms baseline is 5.98ms. All three final samples are at or under 5.2ms. The earlier 5.8ms sample is still under 5.98ms.

Killswitch and campaign-loop-off runs on this same tree:

| Run | Hash | `worst_day_ai` | Result |
|---|---|---|---|
| `EOA_AI_CREDIBLE=0` | `20fe9063de285f19d4f9b8a105abfd31` | 4.2ms | PASS, 0 SCRIPT ERROR |
| `EOA_CAMPAIGN_LOOP=0` | `20fe9063de285f19d4f9b8a105abfd31` | 9.2ms | PASS, 0 SCRIPT ERROR |

Both are one sample. The test budget is 500ms. 9.2ms is the campaign-loop-off day path, not the credible step.

## `--quick` and map

`--quick` on this tree: exit 1, `FAILED (failures=14)`. The 14 are the known reds:

- `test_living_unit_order_loop_product`: `test_integrity`, `test_playtest_clock_does_not_skip_ai_starts`, `test_playtest_clock_does_not_skip_occupation_ticks`, `test_product_wiring`
- `test_unit_card_fill_toe_visibility_product`: `test_integrity`, `test_product_ok`, `test_renderer_source_lock`
- `test_unit_centric_pick_product`: `test_integrity`, `test_product_wiring`, `test_renderer_integrity_strings`
- `test_unit_counter_chrome_product`: `test_integrity`, `test_product_wiring`
- `test_se_england_shire_land_uniformity_product`: `test_prior_feed_products_and_fill_toe_still_pass`
- `test_first_session_play_surface_product`: `test_real_builder_ands_shipped_children`

NE land hit rate `0.9853` (3148/3195). Province md5s unchanged:

- `provinces_base.json` `3f1622a720b6d5a5ce806d7b58626af4`
- `provinces_geometry.json` `1e4f34270e8e89635804dbce4a6f54f6`
- `province_ownership_1936.json` `6643e9466052efc4c20b3f2797052637`
- `province_adjacency.json` `7244fc4ebd28905e82f5033abe0e8953`

## Domain audit

Live on the interactive day tick (`TimeManager._profile_day_ai_steps` and the campaign hooks around it):

| Piece | Live? |
|---|---|
| `GameData.apply_interactive_multi_ai_day_live` | Live. This is the hashed production rotator. Not edited. |
| `InfrastructureDevelopmentManager.try_ai_start_infra_project` | Live. Unchanged. Infra political-power warnings in the soak logs are the pre-existing "need 85, have ~80" warning. |
| `WarStateDomain.try_ai_declare_wars` | Live. Planner hooked in front of the same justify API. |
| `BattleManager.try_ai_start_land_battles` / `LandBattleAi` | Live. Start cap and axis filter hooked. |
| `CapitulationDomain.check_all`, `CampaignEndDomain` | Live. Not edited. |
| `AiCredibleDomain.tick_day` | Live. New. |

Not called from the day tick. Left alone. Each file names itself in a `"manager"` string. These are the thin duals (~46–57 lines): `FactionPersonalityDomain`, `MultiFactionAIDomain`, `StrategicWarGoalDomain`, `CampaignAiMultiMonthDomain`, `GrandStrategyCycleDomain`, `FrontContinuityDomain`, `MultiFrontDomain`, `AiLogisticsDayDomain`, `AiTrainingPolicyDomain`, `AiDifficultyDomain`, `TradeAIDomain`, `ResearchQueueDomain`, `AirTheaterDomain`, `WarEconomyDomain`, `DiplomacyPeaceDomain`. `AirTheaterDomain` is not used for wing assignment. Wings go through `LeaderManager.assign_air_wing_to_region`. There is no `scripts/ai/` package and no new `*_product.py`.

Code vs the launch table: `LandBattleAi` `HARD_MAX_STARTS_PER_DAY` is still 1. The at-war cap is applied in `BattleManager` and then clamped again by `plan_day` to at most 2. ITA personality aggression is 0.60, so ITA is allowed through `ai_declare_min_aggression` 0.6. FRA 0.45, ENG 0.50, USA 0.55, and POL 0.52 are not.

## Rules the planner keeps

CL1 `data/scenarios/campaign_rules_1936.json` is still the source for justify days, `ai_declare_min_day` 180, `ai_declare_min_ratio` 1.5, `ai_max_wars` 1, `ai_declare_min_aggression` 0.6, truce 365, and `ai_may_declare_on_player` true. Goal `min_strength_ratio` can only raise that floor.

A justify is scored from goal weight, coalition strength ratio, shared land border count, and personality aggression. Coalition strength adds every major (and relation tag) for whom `is_formal_ally_or_guaranteed` is true. That relation is symmetric in the existing RelationsManager: a one-way guarantee makes both sides backers. This job does not change call-to-arms.

No declare when the coalition ratio is under the threshold, when an existing war is already losing (`losing_ratio` default 1.05 or `losing_progress` default 0.15), or on a second front under `second_front_ratio` 2.25. A pending AI justify is cancelled when that target fails those guards. Human justifies are not cancelled. Goal `min_day` is lifted only when the campaign `ai_declare_min_day` is set below 180, so the CL1 day-0 JAP–CHI golden still passes.

Q1: AI may declare on the player (rules flag, default true). Q2: `ai_max_wars` 1. A defensive war joined by call-to-arms uses the existing `declare_war` goal `call_to_arms`, which does not go through the justify slot. Q3: player peace offers default on. Q4: soak is 1461 days × 3 seeds. No fallback. First seed wall was 42s, under the 15 minute bar.

## Defence, economy, peace, fronts

Capital-empty counts a day only when that nation has a division, an enemy borders the capital, and no division is stationed on the capital or already marching there. A same-day march is not an empty day. A nation with no divisions is not counted. Headless campaign boot does not spawn an OOB, so the soak's capital-empty count is 0 because the metric does not apply. B4 is the march proof. POL capital from the city layer, via `AiDefenceDomain.capital_pid`, is province `711112`.

Production: at war, that tag gets `infantry_equipment` +1 per day. At peace, one civilian tag per day gets `support_equipment` +1. If a major's production gap exceeds 7 days, `apply_production_for_tag` backfills, at most 8 tags a day. Research scans the first 32 sorted tech ids, then the rest of the list once if those 32 are not available, and starts at most 2 techs a day. The global production stance is not changed.

Peace: the loser is the side with weighted progress ≥ 0.35, or the side whose capital is bordered by the enemy while its strength ratio stays under 0.5 for 60 days. Auto `make_peace` also needs quiet days ≥ 45 (above the CL1 soak stall window of 40) and either progress ≥ 0.35 or war age ≥ 730. Player wars post `AiPeaceNotice` and do not auto-peace. Headless does not parent the notice (`DisplayServer` name `headless`). Accept and decline set mouse filter to ignore, then `queue_free`, before the next map click. B8 checks that click with a full-rect catcher.

Fronts: highest segment score first (`sort_custom` returns true when `a` should come before `b`). The axis is kept for `axis_stable_days` (10) while that segment still exists. On this campaign boot, `strategic_region_id` is 0, so soak axis strings look like `POL:0`. Air assignment requires a region id above 0, so the soak assigns no wings. B10 stamps region 77 and assigns `aic_ger_air`.

## History weights

`offensive_only_listed` is true for every major, so an unlisted neighbour cannot win on weakness alone.

Measured factory weights on the campaign boot (factories 1, city tier ≥ 2 → 2): GER 1263, ENG 1506, POL 159, JAP 235, CHI 66, ITA 361, YUG 257, AUS 105, SOV 256, LIT 30. Land borders that matter: GER–POL 43, JAP–CHI 7, ITA–AUS 10, ITA–YUG 8, ITA–ALB 0. ETH has 0 provinces in `province_ownership_1936.json`.

ITA vs YUG ratio is 1.405, under 1.5, so YUG is refused. ALB is not land-adjacent. ITA's first war is AUS (ratio 3.438, weight 5), and AUS is weaker than ITA. JAP vs CHI ratio is 3.561, so CHI passes the 1.5 floor without lowering it.

## Behaviour tests

`HeadlessAiCredible1BehaviorTest` after the per-day flush fix: `RESULT=PASS`, exit 0, 0 SCRIPT ERROR (`~/ai1_evidence/behavior6.log`).

| Test | Result | Evidence |
|---|---|---|
| Golden JAP–CHI, credible on and killswitch off | PASS | Day 0 justify, day 30 declare. Killswitch writes no trace. |
| B1 coalition | PASS | GER 1263, POL 159, ENG 1506, solo 7.943, coalition 0.759. Threshold 4.351. GER does not justify POL. |
| B2 losing second front | PASS | GER/ENG ratio 0.839. No GER justify. |
| B3 justify, cancel, 30-day wait, no declare before day 180 | PASS | |
| B4 capital | PASS | POL capital 711112. marches=1, capital_empty=0. |
| B5 production | PASS | No idle breach over 9 days. At war, GER bias `military`, infantry equipment stock increased. |
| B6 research | PASS | TechnologyManager loaded 113 nodes. No idle breach. |
| B7 peace and truce | PASS | One POL province flipped, progress 0.0616. Peace, then truce blocks the next declare. |
| B8 player notice | PASS | Accept ends the war and the next click hits the catcher. Decline keeps SOV–POL and the next click is not swallowed. |
| B9 axis | PASS | POL:5 held across day 405, refreshed to CZE:9 at day 420, concentration 0.75. |
| B10 air | PASS | Axis `POL:77`, wing region 77. |

Both headless scripts `load()` domain scripts inside `_run`, after autoloads exist. A `-s` script that names those classes at parse time fails to compile them.

## Soak

`tools/eoa_ai_credible1_soak.sh`. Player tag `OBS` (owns nothing). 1936-01-01 through day 1461 (1940-01-01). Seeds 193601, 193602, 193603, each twice. There is no RNG, so the three seeds match. That is expected. The history bar is 3/3, not a spread.

Harness `~/ai1_evidence/soak_harness.log`: `AIC_SOAK_HARNESS RESULT=PASS days=1461`. 0 SCRIPT ERROR in each log. No Q4 fallback.

| Seed | Wall sec (pair) | Sim `wall_ms` | max chunk ms | Trace md5 (both runs) |
|---|---|---|---|---|
| 193601 | 42 and 42 | 33689 | 585 | `3d3cc06ae166f35b5263663c52edb986` |
| 193602 | 43 and 42 | 33871 | 591 | same |
| 193603 | 42 and 42 | 33049 | 577 | same |
| killswitch 193601 | 33 and 34 | 24561 | 435 | `d41d8cd98f00b204e9800998ecf8427e` (empty) |

Credible trace (same on every seed), from `soak_193601_a.log`:

```
JUSTIFY day=184 GER -> POL score=83.14 ratio=7.943
JUSTIFY day=185 JAP -> CHI score=92.14 ratio=3.561
JUSTIFY day=187 ITA -> AUS score=52.00 ratio=3.438
DECLARE day=214 GER -> POL
DECLARE day=215 JAP -> CHI
DECLARE day=217 ITA -> AUS
JUSTIFY day=802 SOV -> LIT score=22.20 ratio=8.533
DECLARE day=832 SOV -> LIT
```

Event-log war days (flush clock): GER–POL 220, JAP–CHI 220, ITA–AUS 220, SOV–LIT 840. Peaces 0. Capitulations 0. Capital-empty days 0. Research idle breaches 0. Production idle breaches 0. Nonsense declares 0.

History, all 3 seeds: GER neighbour (POL) yes. JAP–CHI event-log day 220, which is on or before day 731. SOV did not declare on a stronger major (LIT is a minor, ratio 8.533). FRA/ENG/USA offensive declares 0. ITA first war AUS, and AUS is weaker.

Wars still open after day 1461 with age over 730: GER–POL, JAP–CHI, ITA–AUS. They have no clear loser. Campaign boot spawns no divisions, provinces do not flip, and the peace loser test never becomes true. SOV–LIT starts at event-log day 840, so its age at day 1461 is 621 days, under the 2-year flag.

Killswitch trace is empty on both runs. The legacy picker, still on the chunk-end clock, declared GER–FRA at event-log day 240 and nothing else. That is the base rotation bug the credible path no longer has. The killswitch comparison required by the brief is the trace, which matches the empty base trace.

## Mutants

Temporary edits, one at a time, then reverted. File md5s after the set matched the pre-mutant md5s. 0 SCRIPT ERROR in every mutant log.

| Mutant | Edit | Result |
|---|---|---|
| M1 | `_coalition_strength` returns only the defender | B1 FAIL. GER justified POL. Threshold 4.351. |
| M2 | `pick_target` no longer returns on `_existing_war_block` | B2 FAIL. GER justified POL while already at war with ENG. |
| M3 | `declare_war` in place of `_begin_justify` | B3 FAIL (`day 180 produced no justify`). Golden and killswitch golden also failed because the war existed before the justify assertions. |
| M4 | `_march_one_to` returns false | B4 FAIL. inbound false, capital_empty 1. |
| M5 | peace `accept` forced false | B7 FAIL. War still on, peaces 0. |
| M6 | Axis index `(day + 1) % n`, stability hold disabled | B9 FAIL. First axis `CZE:9`. A first attempt (`day % n` with stability disabled) happened to land on the expected segments and was not counted. |
| M7 | `randf()` added to the target score | Two 250-day soaks, seed 193601: trace md5 `3ec5f1df…` vs `a038376f…`. Determinism failed. |
| M8 | `_assign_air` returns 0 | B10 FAIL. `assigned=false`, segment still `POL:77`. |

## Persistent state for SR1

One key: `GameData.peace_state["ai_credible_state"]`. Not added to SaveLoadManager.

Subkeys written by this job: `last_research_day`, `last_production_day`, `seen_day`, `axes`, `threatened_since`, `quiet`, `bias`, `air`, `declined`, `counters`, `trace`, `player_offer`, `starts`.

`trace` is capped: when it grows past 8000 lines it keeps the last 4000. Counters include `capital_empty_days`, `research_idle_breaches`, `production_idle_breaches`.

## CL1 notes

The chunk-end `day_ai` clock is the bug above. Repro with the killswitch: 1461-day OBS soak, `EOA_AI_CREDIBLE=0`, only war is GER–FRA on event-log day 240. Credible mode on the same harness declares GER, JAP, ITA, and SOV on their own days.

`has_guarantee` symmetry is existing CL1 behaviour. B1 uses it so ENG backs POL. Tests clear that guarantee in reset. The soak boots with no guarantees, and the war list shows no `call_to_arms` row.

Peace quiet default 45 stays above the CL1 soak stall window of 40, and player wars are not auto-peaced, so the CL1 fight loop is not closed by this peace rule. The full gate re-ran the CL1 scripts on this tip. All six CL1 steps passed, including the soak and the end screen. 0 SCRIPT ERROR in the CL1 soak log.

## Full gate

`bash tools/eoa_full_test_gates.sh --log ~/ai1_evidence/full_gate_steps` on this uncommitted tip. Exit 1. Log `~/ai1_evidence/full_gate.log`. `--with-perf` was not passed, so `map_perf` did not run. That flag is off by default.

In-gate `HeadlessPerf4LiveMultiAiDayTest`: RESULT=PASS, `worst_day_ai=5.1ms`, decision-line md5 `20fe9063de285f19d4f9b8a105abfd31`. 0 SCRIPT ERROR was not re-counted on that log beyond the PASS line.

`launch_ai_credible1_behavior` PASS. 0 SCRIPT ERROR. B1–B10, both goldens, both B8 paths.

`launch_ai_credible1_soak` PASS, 1461 days, Q4 did not fire. Trace md5 `3d3cc06ae166f35b5263663c52edb986` on all six credible runs (seeds 193601, 193602, 193603, each twice). Killswitch pair both `d41d8cd98f00b204e9800998ecf8427e`. Sim wall_ms: 32836, 33236, 33416, 32680, 32656, 33285. Killswitch wall_ms 24341 and 24194. Same wars and history counts as the earlier harness. 0 peaces, 0 capitulations, 0 capital-empty days, 0 idle breaches, nonsense empty.

Steps that failed, and why they are not this job:

| Step | What failed | Why it is not AIC |
|---|---|---|
| `unit_board_play_path` | the 14 known `--quick` reds | Same names as the base `--quick` log. The full path runs them as one unittest. |
| `launch_unit_order` | no Channel `DemoUnitIcon`; war-goal `pushes` stayed 0 | Fleet fail is before any `AiCredible:` line. `pushes` stays 0 because `PlayNextHook.apply` returns from `player_declare_from_province` (`b677890f`, CL1 FIX #1) and never calls `apply_war_goal_execute`. That function and PlayNextHook are unchanged vs `d00dc8ed`. The gate then also prints `launch_unit_order missing RESULT=PASS` for the same log. |
| `launch_perf2_fleet_refresh_budget` | 36 px star count 0 | Non-supply layout restores idle capital px, and `_capital_star_font_px` clamps at 20 (`03cb7a99`, early continue from VIS-2 `b4140930`). MapRenderer was not edited. |
| `launch_vis1_map_readability` | SupplyOutline still visible after L off, plus a source lock on `_refresh_supply_highlights` | MapRenderer supply path. 0 `AiCredible` lines. `launch_vis2_capital_stars_after_l` passed. |
| `launch_render1_draw_guard`, `launch_render1_live_cold`, `launch_hwy3_ruhr_legibility`, `launch_rx1_pixel`, `launch_mv1_pixel`, `launch_mv1_card_up_input`, `launch_rh1_pixel` | `RESULT=FAIL need xvfb-run` | This PC has no `xvfb-run`. Guards fail closed. Not product Play. |
| `launch_fac1a_pixel` | `mkdir: cannot create directory '/opt/cursor': Permission denied` | The guard's default out dir is `/opt/cursor/artifacts/fac1a` and `mkdir` runs before the xvfb check. |

No untouched-base full-gate log exists in this session, so "also red on base" is inferred from the commits above and from the files this job did not edit. The 14 `--quick` reds were measured on this tree and match the names recorded before the feature. The xvfb and `/opt/cursor` failures are this machine.

## Year multi-AI

`tools/eoa_year_multi_ai_test.sh` is not in the full gate. Full 365 days, all owners, not `--smoke`. Log `~/ai1_evidence/year_ai/`. `YEAR_EXIT:0`. `[year-ai] PASS`. `end ok=true`. 0 SCRIPT ERROR.

65 factions, `ai_day_ok=365`, `ai_day_fail=0`, `ai_applied_sum=23725`, `major_apply_sum=2920`, `minor_soft_sum=20805`, start 1936-01-01, end 1937-01-01, `elapsed_ms=25034`, `loaded_provinces=3536`.

The harness is lean. It bumps `current_day` and `total_days_elapsed` and does not emit the `day_ai` cascade, so this run does not exercise `AiCredibleDomain.tick_day`. It does prove the year production loop still completes with the TimeManager edit present.

The run rewrote `tools/map_generation/output/year_multi_ai_campaign_evidence.json` (`elapsed_ms_outer` 6755 to 25034, and a different tag order). That file was restored to the committed copy and is not part of this change.

## Play

Not run by Build. No Play verdict. Steps for Play are in the launch brief §9. Xvfb only, never display `:0`.
