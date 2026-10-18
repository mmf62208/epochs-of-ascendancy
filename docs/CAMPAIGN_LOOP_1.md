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
