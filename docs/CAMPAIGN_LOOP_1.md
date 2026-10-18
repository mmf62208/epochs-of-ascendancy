# CAMPAIGN-LOOP-1

1936 campaign loop: war graph, capitulation, peace, victory and defeat. Branch `grok/campaign-loop-1`. Base at start: `e4fc2d903b67f6c37adff500c243d2a3429586c2` (merge of #99). The launch brief named `a1b4d11c`; that SHA was already behind `origin/main`.

No Play verdict. Draft PR stays with Ship. Optimus Prime makes the KEEP call.

## Decisions in force

Mike via Optimus Prime, 18 Oct 2026 10:28am ET, supersedes the brief's day-1 wars:

- Start is historical peace on 1 Jan 1936. `start_wars` is empty.
- GER–FRA and JAP–CHI exist on day 1 only when `EOA_SCENARIO_EARLY_WARS=1`. Existing assault harnesses set that in `_init`. The multi-front harness also calls `declare_war("GER", "POL", "test")` because its fixture edge is not a start war.
- Victory: 2 scenario majors defeated. Time limit `1949-01-01`, ranked by world factory share.
- Keep playing default ON (`allow_keep_playing`). Continue as another nation OFF (`allow_continuation`).
- Killswitch `EOA_CAMPAIGN_LOOP=0` must still hash `20fe9063`.
- Factions are out of this slice. Minor capitals use the most-factory province, lowest pid on ties.
- Seed-test POL capital `711054` (Częstochowski) vs scenario Warsaw `711112` is logged only. Not fixed here.

Play step 1 in the brief ("At war: FRA" and Maginot on day 0) is stale. Default Begin is at peace. That HUD line and the day-0 Maginot fight need `EOA_SCENARIO_EARLY_WARS=1`.

## What differed from the brief's code read

- No pairwise war graph, and no end screen, matched the code.
- `SupplyManager._are_hostile` is still `a != b`. The campaign gate does not go through supply hostility.
- POL is not `major_power`. Peace default for POL is `annex_all`. The seven peace and victory majors are GER, FRA, ENG, USA, SOV, ITA, JAP.
- Perf-boot writes factories 1, or 2 when the city tier is at least 2. Capitulation goldens call `apply_economy_factories_to_map()` so weights use `province_economy_layer.json`.
- `advance_live_f5_equivalent_days` unpauses, sets the light-sim flag, and moves the calendar before the battle flush. A multi-day call can pass the end day inside the chunk. Exact end days advance one day at a time.
- Real 1936 GER–POL border used by the war-gate test is `711057 → 711054`, not the multi-front fixture `710302 → 711073` (that pid is GER on the real board, and POL only inside the fixture). GER–FRA Maginot `710173 → 710739` is a real border.
- Peacetime infrastructure still picks a geographic foreign border. `collect_owned_border_edges` is the ungated scan. `collect_live_border_assault_targets` stays war-gated and does not share that result into `_live_fronts_precompute`. The PERF-4 daily infra golden (JAP 903951, FRA 710739, ITA 710859, ENG 711481, POL 711054, SOV no candidate, JAP 902474) matched after that split. Assaults do not use the ungated list.
- City-layer capital flags with a tag are the eight scenario capitals. Pid `903446` is flagged capital and has no tag, so the city fallback does not use it. Zero tags resolved by the city fallback.

## Rules

File `data/scenarios/campaign_rules_1936.json`. The loop is active only when `EOA_CAMPAIGN_LOOP` is not `0`, `TimeManager.scenario_start_year` is 1936, and that file loads. Harness overrides are a dictionary on `WarStateDomain.set_rule_overrides`, not environment variables.

| Key | Value |
|---|---|
| start_wars | `[]` |
| early_wars | GER–FRA, JAP–CHI, only if `EOA_SCENARIO_EARLY_WARS=1` |
| player_justify_days | 14 |
| truce_days | 365 |
| province_base_weight / key_weight / capital_weight | 1 / 10 / 25 |
| threshold_base / coef / min / max | 0.40 / 0.40 / 0.40 / 0.85 |
| threshold_minor | 0.50 |
| capital_loss_bonus | 0 |
| peace major / minor | keep_occupied / annex_all |
| victory_min_majors_defeated | 2 |
| victory_count_minors | false |
| end_date | 1949-01-01 |
| allow_continuation / allow_keep_playing | false / true |
| stalemate_white_peace_days | null |
| ai_declare_min_day / min_aggression / min_ratio | 180 / 0.6 / 1.5 |
| ai_declare_checks_per_day / ai_max_wars / ai_justify_days | 1 / 1 / 30 |
| ai_may_declare_on_player | true |
| ai_border_target_cap | 64 |

Strength for the declare rule is the sum of `land_combat_power` over the tag's divisions. With no divisions, the fallback is the sum of `province_base_weight + factories` on owned land. No RNG. Attacker allies are not called. A runtime guarantee or formal alliance of the defender joins.

AI declare golden, measured on the war-gate boot with player GER and overrides `ai_declare_min_day=0`, `ai_declare_min_ratio=0`: JAP justifies against CHI on day 0 and declares on day 30.

## Capitulation arithmetic

Weight `w = 1 + factories + (key ? 10 : 0) + (capital ? 25 : 0)`. Progress is enemy-held start weight over total start weight. A tag at war with nobody stays at progress 0.

POL (scenario country, not a major): 53 provinces, factory sum 167, keys `711112`, `711048`, `711090`, capital `711112` (8 factories, also a key).

- Total `53*1 + 167 + 10*3 + 25 = 275`.
- Capital province `1 + 8 + 10 + 25 = 44`.
- Capital-only progress `44/275 = 0.16`.
- Threshold `clamp(0.40 + 0.40 * 55/100) = 0.62`. Held weight must reach `170.5`.
- Dropping the capital weight (mutant M4) makes that province 19 and the total 250, so `19/250`, which is not `44/275`.

LUX (minor): one province `710977`, 3 factories, no key, capital by the factory rule. Weight `1+3+25 = 29`. Threshold `0.50`. Outcome `annex_all`.

FRA (major): stability 70, threshold `0.68`, outcome `keep_occupied`.

The daily-check millisecond is the scan inside `check_all` and does not include annex. Annex time is `last_annex_ms`. Bars are 10 ms and 1500 ms, doubled when `EOA_SLOW_BOX=1`.

Poland's German border is 22 provinces and weight 99 (0.36 of 275). Hop 2 adds 68 (cumulative 167, ratio 0.607). Hop 3 crosses 0.62 (cumulative 263). A single border hex cannot capitulate Poland. Attacker-win capture already sets the attacker's `stationed_province_id` to the taken province (`BattleManager` capture path), so an existing battle can walk forward without a new march planner. The soak uses that. It does not add front planning.

## Derived capitals (65 land tags)

Scenario id when the scenario capital is owned. Otherwise the owned province with the most factories, lowest pid on a tie. City fallback added none.

| Tag | Pid | How | Owned |
|---|---:|---|---:|
| AFG | 904797 | factories | 30 |
| ALB | 710000 | factories | 12 |
| ARG | 903446 | factories | 11 |
| AUS | 710012 | factories | 35 |
| BEL | 904230 | factories | 55 |
| BHU | 900429 | factories | 5 |
| BOL | 903828 | factories | 6 |
| BRA | 902889 | factories | 16 |
| BUL | 710091 | factories | 28 |
| CHI | 902569 | factories | 22 |
| CHL | 903765 | factories | 6 |
| COL | 903700 | factories | 8 |
| COS | 905448 | factories | 3 |
| CUB | 904482 | factories | 3 |
| CYP | 710145 | factories | 1 |
| CZE | 710146 | factories | 22 |
| DNK | 710561 | factories | 28 |
| DOM | 904899 | factories | 3 |
| ECU | 904923 | factories | 5 |
| ELS | 905427 | factories | 3 |
| ENG | 711414 | scenario | 596 |
| EST | 710572 | factories | 5 |
| FIN | 710688 | factories | 22 |
| FRA | 710707 | scenario | 320 |
| GER | 710300 | scenario | 421 |
| GRE | 710577 | factories | 52 |
| GUA | 904998 | factories | 3 |
| HAI | 905412 | factories | 3 |
| HON | 905135 | factories | 3 |
| HUN | 710829 | factories | 20 |
| ICE | 710857 | factories | 2 |
| IRE | 710849 | factories | 8 |
| ITA | 710963 | scenario | 121 |
| JAP | 903995 | scenario | 116 |
| LAT | 710978 | factories | 6 |
| LIB | 900976 | factories | 3 |
| LIE | 710966 | factories | 1 |
| LIT | 710967 | factories | 10 |
| LUX | 710977 | factories | 1 |
| MEX | 903175 | factories | 6 |
| MLT | 710993 | factories | 2 |
| MON | 904102 | factories | 6 |
| NEP | 905306 | factories | 5 |
| NIC | 905181 | factories | 3 |
| NLD | 900319 | factories | 146 |
| NOR | 711035 | factories | 13 |
| NZL | 902458 | factories | 4 |
| PAN | 905404 | factories | 3 |
| PAR | 905156 | factories | 6 |
| PER | 903725 | factories | 74 |
| POL | 711112 | scenario | 53 |
| POR | 904461 | factories | 51 |
| ROM | 711146 | factories | 59 |
| SAU | 903838 | factories | 29 |
| SIA | 904506 | factories | 74 |
| SOV | 903534 | scenario | 110 |
| SPA | 902118 | factories | 62 |
| SWE | 711213 | factories | 21 |
| SWI | 710119 | factories | 26 |
| TUR | 711254 | factories | 82 |
| URG | 905089 | factories | 5 |
| USA | 800792 | scenario | 219 |
| VEN | 903792 | factories | 6 |
| YEM | 905066 | factories | 21 |
| YUG | 710808 | factories | 95 |

## Save keys

`GameData.get_save_data` / `apply_save_data` always carry `campaign_wars`, `campaign_capitulation`, and `campaign_end`. `SaveLoadManager._gather_save_data` stores that blob on `game_data`. No round-trip identity test (SAVE-RELOAD-1). GameData diff is +18 lines.

## Formations after annex

No disband API. `annex_all` sets `Formation.campaign_inactive`. `get_formations_for_country` and the map chip collector skip those. `keep_occupied` leaves formations active and clears `is_in_combat`.

## Gate record

Untouched base, before this branch's edits:

- Seed ×3 prefix `20fe9063` (full `20fe9063de285f19d4f9b8a105abfd31`). Method: md5 of the text after `HeadlessPerf4LiveMultiAiDayTest: ` on the `multi_ai_decisions=` line, plus a trailing newline.
- Worst `day_ai` 8.8 ms, worst `day_battles` 0.3 ms, worst phase `day_ai`. +10% bars are 9.68 ms and 0.33 ms.
- NE land hit 0.9853 (3148/3195).
- `--quick` exit 1 with exactly these 14 reds:

```
test_living_unit_order_loop_product: test_integrity, test_playtest_clock_does_not_skip_ai_starts, test_playtest_clock_does_not_skip_occupation_ticks, test_product_wiring
test_unit_card_fill_toe_visibility_product: test_integrity, test_product_ok, test_renderer_source_lock
test_unit_centric_pick_product: test_integrity, test_product_wiring, test_renderer_integrity_strings
test_unit_counter_chrome_product: test_integrity, test_product_wiring
test_se_england_shire_land_uniformity_product: test_prior_feed_products_and_fill_toe_still_pass
test_first_session_play_surface_product: test_real_builder_ands_shipped_children
```

Tip, first `HeadlessPerf4LiveMultiAiDayTest` on this tree (log `~/campaign1_evidence/perf4_live.log`):

- `multi_ai_decisions` md5 `20fe9063de285f19d4f9b8a105abfd31` (prefix `20fe9063`). Same method as the base. The expected hash in the test is not edited.
- Worst `day_ai` 5.1 ms (base 8.8, bar 9.68). Worst `day_battles` 0.3 ms on every profiled day (base 0.3, bar 0.33). `RESULT=PASS`. No `SCRIPT ERROR`.
- `HeadlessPerf4DailySimTickTest` `RESULT=PASS`. Infra golden matched. Worst phase on that board was `day_emit` 1.1 ms.

Tip runs 2 and 3 and the killswitch (`EOA_CAMPAIGN_LOOP=0`) are the same md5 `20fe9063de285f19d4f9b8a105abfd31`, each `RESULT=PASS`. Logs: `perf4_live_seed2.log`, `perf4_live_seed3.log`, `perf4_live_killswitch.log`. `--quick` exit 1 with the same 14 reds as the base (no added, none cleared). NE land hit 0.9853 (3148/3195). The seed did not move, so no re-baseline is requested.

## CL1a mutants

Each mutant is a temporary local edit. Test A is `HeadlessCampaignLoop1WarGateTest`. The file is restored from a copy taken before the edit, not with `git checkout`.

| Mutant | Edit | Result |
|---|---|---|
| M1 | `can_assault_province` skips the war check | KILLED. POL and FRA assaults returned ok at peace. `RESULT=FAIL`. Restored clean. |
| M2 | assault filter returns every row, and the in-scan war skip is off | KILLED. GER collect returned a non-enemy, included POL before declare, and kept POL after peace. Restored clean. |
| M6 | truce reject disabled | KILLED. Re-declare during the truce returned ok. Restored clean. |
| M11 | `include_player_in_ai_land_battles` default true | KILLED. Test A rejected the default. Restored clean. |
| M12 | `EOA_CAMPAIGN_LOOP=0` ignored | KILLED. POL assault stayed "Not at war with Poland". Restored clean. |

## CL1b capitulation test

`HeadlessCampaignLoop1CapitulationPeaceTest` `RESULT=PASS`. Economy factories applied on 3196 provinces. Thresholds POL 0.62, LUX 0.50, FRA 0.68. POL capital-only progress 0.160000. Daily check 2.055 ms (bar 10, `EOA_SLOW_BOX` unset). `annex_all` of POL 88.557 ms (bar 1500). One settlement row per capitulation. POL and LUX annexed to GER. FRA rump kept. 65 capitals resolve to an owned province. Save keys `campaign_wars`, `campaign_capitulation`, and `campaign_end` are present. No `SCRIPT ERROR`.

The seed hashes above were taken on this same tree (capitulation hooks were already in the CL1a commit). No further sim edit was required for test B.

## CL1b mutants

| Mutant | Edit | Result |
|---|---|---|
| M3 | daily hook never calls `check_all` | KILLED. POL, LUX, and FRA did not capitulate. Restored clean. |
| M4 | capital weight dropped | KILLED. POL capital progress 0.076000 instead of 0.160000. Restored clean. |
| M5 | `make_peace` does not erase the war pair | KILLED. POL, LUX, and FRA wars stayed open and re-declare was not blocked. Restored clean. |
| M10 | save whitelist omits `campaign_end` | KILLED. Whitelist missing `campaign_end`. Restored clean. |

Peace sheet: `~/campaign1_evidence/peace_sheet.png` (1280×800, 35 KB). Title "Peace with LUX", buttons "Annex all" and "Keep occupied", news "LUX capitulated. Choose annex or keep occupied." Not copied into `docs/evidence/` because that directory already holds the two chrome shots. Same private gamescope display. `RESULT=PASS`. No `SCRIPT ERROR`.

Chrome shots: `~/campaign1_evidence/war_hud.png` and `declare_button.png` (1280×800, about 21 KB each). `Xvfb` is not installed and sudo is unavailable, so the guard used `gamescope --backend headless` (private Xwayland, no window on the live desktop). The HUD label is one row in the top bar, reading "At war: France". The inspector button reads "Justify war on Poland". `WindowedCampaignLoop1EndScreenGuard` `RESULT=PASS`. No `SCRIPT ERROR`.

## CL1c soak and end screen

The first soak stalled. GER took the first border hexes, then the collector's cap of 4 kept returning those empty staging provinces, and light sim does not march spare divisions. Progress sat at 0.2214 (POL owned 40). No new march planner was added. `BattleManager._ai_border_targets` still asks for 4 targets. Only when the campaign loop is on, the tag has enemies, and none of those four can assault with a division, it asks again with `ai_border_target_cap` (64). `WarStateDomain.note_province_owner_changed` clears the front cache so a captured hex is not offered again. Real empty-hex captures then capitulated POL on day 39.

`HeadlessCampaignLoop1SoakTest` on that tree, log `~/campaign1_evidence/cl1c_soak2.log`, `RESULT=PASS`, no `SCRIPT ERROR`. Sim wall 9164 ms (budget 15 min). Not split into a `--long` step. After the peaceful-day early-out, `cl1c_soak3.log` passed again: same days, same owner md5 `61abc333aec39f9c61f17bc902aca1de`, sim wall 8209 ms.

| Run | Days | Wall | ms/day | Result |
|---|---|---|---|---|
| S4 time limit | 30 | 336 ms | — | 1936-01-31, rank0 USA, GER rank 3, title `Defeat: Eclipsed (rank 3)` |
| S2 player POL defeat | 39 | 1897 ms | 48.6 | outcome defeat, clock paused, +20 days do not move the date |
| S2b same seed | 39 | 1884 ms | 48.3 | owner md5 `61abc333aec39f9c61f17bc902aca1de` |
| S1 USA observer, GER annexes POL | 39 | 2229 ms | 57.2 | `annex_all`, leader GER, one settlement row, truce |
| S3 GER autopilot victory | 39 | 2228 ms | 57.1 | override `victory_min_majors_defeated` 1 and `victory_count_minors` true |

Day 20 of each fight: progress 0.3247, POL still owned 33, 16 GER divisions stationed on the border. The end-of-run progress print is 0.0000 because `progress()` is 0 once the tag has no enemies. That is not the stall number. `stalemate_white_peace_days` stayed null.

The latch pauses `TimeManager`. `advance_live_f5_equivalent_days` does not restore the pre-call pause flag when `clock_locked()` is true. A latch that forgets to pause stays unpaused, which is how M7 is visible. `ai_stopped` stays true while an outcome is latched. Keep playing is on the screen and does nothing until the button is pressed. Continue as another nation stays hidden.

A peaceful day does not build the capitulation dict. Scoring still runs when a war is open, someone has already surrendered, the end date is due, or an outcome is latched. The capitulation day is covered because `at_war` is sampled before `check_all` closes those wars.

Windowed guard, second run, log `~/campaign1_evidence/cl1c_end_screen2.log`. `RESULT=PASS`. No `SCRIPT ERROR`. Same gamescope headless 1280×800. The first run failed because `get_nodes_in_group` was called on the root `Window`. It is a `SceneTree` method.

| Shot | What it shows |
|---|---|
| `~/campaign1_evidence/end_defeat.png` (49 KB) | Title Defeat. Reason "Poland capitulated on 1936-01-02". Keep playing visible. Continue hidden. |
| `~/campaign1_evidence/end_victory.png` (52 KB) | Title Victory. Reason "Decisive victory. 1 nations capitulated." Date 1936-01-02. |
| `~/campaign1_evidence/end_time.png` (50 KB) | Title `Defeat: Eclipsed (rank 3)`. |
| `peace_sheet.png`, `war_hud.png`, `declare_button.png` | Recaptured in the same run. |

Main menu was a real click (`Input.parse_input_event` and `flush_buffered_events`). The probe consumed it. The map sentinel did not fire. `MainMenu` opened. The inspector child count did not change. The two repo PNGs under `docs/evidence/campaign_loop1/` stay the chrome pair. The end shots are outside the tree.

The end shots still show the LUX toast from the peace-sheet step earlier in the same process. The victory frame also shows the player peace sheet behind the modal (layer 124 under 125). That sheet opens on the same day the victory latches. The top-bar war line refreshes when the date line does, which is before capitulation, so a paused end frame can still name the enemy that just made peace.

## CL1c mutants

Copy, edit, run, restore from the copy. Not `git checkout`.

| Mutant | Edit | Result |
|---|---|---|
| M3 | `check_all` in `_campaign_after_battles` replaced with a no-op | KILLED on the soak. POL progress stuck at 0.9114. S1, S2, S2b, and S3 did not end. `RESULT=FAIL`. Restored. |
| M7 | latch does not set `TimeManager.paused` | KILLED. S4, S2, S2b, and S3 reported the clock not paused. `RESULT=FAIL`. Restored. |
| M8 | uncapitulated-major check forced false | KILLED. Victory latched while FRA was still an enemy major. `RESULT=FAIL`. Restored. |
| M9 | `CampaignEndScreen.present` removed | KILLED on the windowed guard. Defeat, victory, and time screens missing. Main menu click had no screen. `RESULT=FAIL`. No `SCRIPT ERROR`. gamescope exited 139 on teardown after the fail. Restored. `present` is back. |

M1, M2, M6, M11, and M12 were killed in CL1a. M3 (capitulation test), M4, M5, and M10 were killed in CL1b. All 12 are killed. The anchors are the live calls, not the mutant no-ops.

## CL1c seed and day cost

Same md5 method as the base. The expected hash in `HeadlessPerf4LiveMultiAiDayTest` is not edited.

Tip after the peaceful-day early-out and the boot-time rules read. Logs `cl1c_warm_seed1.log`, `cl1c_warm_seed2.log`, `cl1c_warm_seed3.log`, `cl1c_warm_kill.log`.

| Run | md5 | day_ai worst | day_battles samples | RESULT |
|---|---|---|---|---|
| seed 1 | `20fe9063de285f19d4f9b8a105abfd31` | 5.5 ms | 0.3, 0.3, 0.3, 0.4, 0.3 | PASS |
| seed 2 | `20fe9063de285f19d4f9b8a105abfd31` | 5.5 ms | 0.3 ×5 | PASS |
| seed 3 | `20fe9063de285f19d4f9b8a105abfd31` | 7.3 ms | 0.3, 0.4, 0.4, 0.3, 0.3 | PASS |
| `EOA_CAMPAIGN_LOOP=0` | `20fe9063de285f19d4f9b8a105abfd31` | 10.5 ms | 0.3 ×5 | PASS |

No `SCRIPT ERROR`. The seed did not move. No re-baseline is requested.

Base worst `day_ai` was 8.8 ms (the three base logs actually span 7.7–9.0). The +10% bar used in CL1a is 9.68 ms. Loop-on worst here is 7.3 ms, under that bar. It is lower than the base because January 1936 is at peace, so `ai_land` stays about 0.1 ms instead of the base's 3.7–4.3 ms of neighbour attacks.

Base `day_battles` was 0.3 ms on every sample. The +10% bar is 0.33 ms. Two of the three loop-on runs printed a 0.4 ms day. The phase is printed to 0.1 ms, so 0.4 is one step over 0.33. The other days are 0.3. The peaceful battle day does not scan provinces. It checks the killswitch, whether any war is open, and whether the end year has arrived. The killswitch run's battle days are 0.3, matching the base.

Killswitch `day_ai` 10.5 ms is above the 9.68 ms bar. The steps are `ai_land` 4.4–5.3 ms (base samples were 3.7–4.3) plus the same infra cost. The hash matches. `can_assault_province` still asks `loop_enabled()` on each preview so a test can flip `EOA_CAMPAIGN_LOOP` in-process. That env read is the likely extra millisecond. It was not cached, because the war-gate killswitch case depends on the next call seeing the new value.

## Pre-existing red on this base

`HeadlessWorldAccurateUnitOrderLoopTest` fails one assertion on `e4fc2d90` before any campaign battle: `no DemoUnitIcon on Channel fleet 950001`. `ensure_playable_front_chips` stations ENG, USA, ITA, and POL fleets on that sea hex. `MapRenderer._demo_icon_jobs_for_province` then names the plates `DemoUnitIcon_950001_<TAG>` on `SeaNationFleetLayer`. The test looks only for a province-node child `DemoUnitIcon_950001`. That naming is in the base renderer (sea-nation plates). The land chip on `710173`, the ENG fleet station, the sea hop, and the choke flag all pass. Not caused by the war gate.

## Early-war and declare setup lines

- `HeadlessWorldAccurateAssaultEntryTest._init`: `EOA_SCENARIO_EARLY_WARS=1`.
- `HeadlessWorldAccurateUnitOrderLoopTest._init`: `EOA_SCENARIO_EARLY_WARS=1`.
- `HeadlessCombat1FightResolveTest._init`: `EOA_SCENARIO_EARLY_WARS=1`.
- `HeadlessWorldAccurateMultiFrontAssaultTest._init`: `EOA_SCENARIO_EARLY_WARS=1`, then `load` of `WarStateDomain` and `declare_war("GER", "POL", "test")` after the fixture map. The domain is loaded at runtime so the `-s` script does not compile it before autoloads exist.
- `HeadlessOrders1HaltHoldWithdrawTest._init`: `EOA_SCENARIO_EARLY_WARS=1`. Open fight → Start battle is the Maginot edge GER `710173` → FRA `710739`.

## Open questions still pending

Q1, Q2, and Q6 are implemented as Mike answered them. Q7: if the seed moves, this doc states the new hash, the reason, and the diff summary for Ship to take to Optimus Prime. Q3, Q4, Q5, Q8, Q9, Q10 are closed as in the decisions above.

## FIX #1 (player Declare, inspector target, end-screen polish)

Box rules were already right: 2 majors, minors don't count; default start is peace; early wars only behind `EOA_SCENARIO_EARLY_WARS=1`; player 14 days, AI not before day 180 and 30 days to declare.

Bugs that were not:

1. **Player war auto-declared.** `WarStateDomain.try_ai_declare_wars` → `_complete_ready_justifies` completed every ready pair, including the player's. On day 14 GER was at war with Poland with no Declare click, so the inspector never showed the button. Fix: skip the player tag and any `SessionPlayers` human slot. Ready player claims stay pending until Declare. Guard `HeadlessCampaignLoop1DeclareClickTest`: justify POL, day 15 not at war, Declare enabled, leftover-release-swallow click via `Input.parse_input_event` (same class as `HeadlessProd1ButtonOpenTest`) starts the war.
2. **Inspector Declare on every neighbour.** `player_justify_is_ready()` is global, so a ready POL claim relabelled FRA/CZE/… as Declare, and those clicks failed. Declare is only for `player_justify_is_ready_for(owner)`. Others show `Justify (N days)` disabled. Same headless test mounts POL + FRA inspectors.
3. **End-screen polish** (checked in `WindowedCampaignLoop1EndScreenGuard`): opaque `EndPanel`; hide capitulation toast layer + peace sheet; `1 nation capitulated` / `N nations`; refresh `CampaignWarReadout` so a paused end frame is not still `At war:` with the nation that just made peace; province line is **controlled** (captures + annex, not only legal owner); Defeat with 0 provinces hides Keep playing and shows why.

**HOLD, do not change:** Declare still also issues an attack order through the old war-goal path. `CampaignWarChrome._on_pressed` calls `WarStateDomain.player_declare_from_province` then `GameData.apply_war_goal_live("execute", pid)`, which is `apply_order_panel_action("apply_assault", pid)` plus `_campaign_note_war_goal`. Waiting on a decision.

FIX #1 evidence on tip `c4280e38`:

- `HeadlessCampaignLoop1DeclareClickTest` `RESULT=PASS`: day 15 GER–POL not at war; POL inspector `Declare war on Poland`; FRA inspector `Justify (14 days)` disabled; leftover-swallow Declare click started the war.
- Existing CL1: WarGate, CapitulationPeace, Soak, EndScreenGuard all `RESULT=PASS`.
- Seed `multi_ai_decisions` md5 `20fe9063de285f19d4f9b8a105abfd31` default and `EOA_CAMPAIGN_LOOP=0`.
- `--quick` exit 1 with the same 14 `unit_board_play_path` reds. map_qc NE **0.9853** (3148/3195).

## Full gates on the rebased tip

Rebased onto `origin/main` `05602912`. Tip `56b31db5`. `tools/eoa_full_test_gates.sh` exited 1. Log `~/campaign1_evidence/cl1c_full_gates_stdout.log`. Wall about 25 minutes. The four campaign steps passed, including the soak and the gamescope end-screen guard. No `SCRIPT ERROR` in those logs.

`map_qc` passed (NE 0.9853). `launch_perf4_live_multi_ai_day` passed on this tip: md5 still `20fe9063de285f19d4f9b8a105abfd31`, worst `day_ai` 4.7 ms, `day_battles` 0.3 ms on all five days. `launch_perf4_daily_sim_tick` passed. `launch_assault` (multi-front) passed. After the gates, `HeadlessCombat1FightResolveTest` and `HeadlessOrders1HaltHoldWithdrawTest` were run again on this tip. Both `RESULT=PASS`, no `SCRIPT ERROR`.

Steps that failed, and why:

| Step | Why |
|---|---|
| `unit_board_play_path` | The same 14 known Python reds. No new product name in the failure list. |
| `launch_unit_order` and the later `missing RESULT=PASS` line | The known Channel icon name `DemoUnitIcon_950001` vs `DemoUnitIcon_950001_<TAG>`. |
| `launch_perf2_fleet_refresh_budget` | Supply glyph stars at 36 px count is 0. The campaign diff does not edit that draw. This session did not run the step on untouched main. |
| `launch_vis1_map_readability` | Leftover `SupplyOutline` nodes stay visible when L is off. `_refresh_supply_highlights` is not in the campaign diff. Not run on untouched main here. |
| `launch_render1_draw_guard`, `launch_render1_live_cold`, `launch_hwy3_ruhr_legibility`, `launch_rx1_pixel`, `launch_mv1_pixel`, `launch_mv1_card_up_input`, `launch_rh1_pixel` | `RESULT=FAIL need xvfb-run`. Xvfb is not installed. |
| `launch_fac1a_pixel` | `mkdir /opt/cursor/artifacts/fac1a` is permission denied, so the wrapper exits before its `xvfb-run` check. |

Every other gate step passed, including Rhine crossing, production-button open, capital stars, wheel drift, and the road and highway headless checks.
