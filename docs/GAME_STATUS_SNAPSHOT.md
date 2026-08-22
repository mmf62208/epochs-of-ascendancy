# EOA — Game Status Snapshot (full-test readiness)

**Date:** 2026-08-22 (L1 land loop + living units + organize + composition + industry TOE + era resources + occupier harvest + **NEXT daily command beat** + **capture AAR economy** + completing bars · `--quick` green · board ~3520 · M6 human-only open)  
**Residual board:** [`EOA_RESIDUAL_PRIORITY_BOARD.md`](EOA_RESIDUAL_PRIORITY_BOARD.md) · skeptic [`EOA_SKEPTIC_PASS_2026_08_03.md`](EOA_SKEPTIC_PASS_2026_08_03.md) · forward program [`FORWARD_PROGRAM_2026_08_12.md`](FORWARD_PROGRAM_2026_08_12.md)  
**How to keep going:** 5-step protocol in §0. Next human: F5 §0b 3–15 + a 20d unpause (M6 notes). Next machine: only playtest-driven shipped-path fixes. Do **not** merge `origin/cursor/*` or `execute-plan/ceb60fdd-*`.

**Audience:** Human playtester, game director, implementer agents  
**Source of truth for “what is true now”:** this file + [`GAME_DIRECTOR_PLAN.md`](GAME_DIRECTOR_PLAN.md)  
**Map star analysis (HOI4/V3 structure):** [`WORLD_CLASS_MAP_REVIEW.md`](WORLD_CLASS_MAP_REVIEW.md)  
**HOI4 pillar gap review:** [`HOI4_EOA_GAP_REVIEW.md`](HOI4_EOA_GAP_REVIEW.md) · pure `hoi_full_test_gap_matrix_product` (17/17 P0 landed · open P0=0)  
**Grok partner setup:** [`EOA_GROK_SETUP.md`](EOA_GROK_SETUP.md) · skill `eoa-full-test` · gates `tools/eoa_full_test_gates.sh` · `/eoa-gates`  
**Year multi-AI campaign:** `tools/eoa_year_multi_ai_test.sh` · **71 factions all AI** · lean 365d **PASS** (majors real production apply · minors soft ticks · calendar 1936-01-01→1937-01-01 · ~7s · evidence `tools/map_generation/output/year_multi_ai_campaign_evidence.json`)  
**Interactive multi-AI (graphical F5):** budgeted **3** production + **1** soft supply/day · **personality aggression rank** · **tag-scoped** `apply_production_for_tag` (not player stockpile) · pure `interactive_multi_ai_day_product` · **on official `--quick` gate** · killswitch `EOA_INTERACTIVE_MULTI_AI=0`

---

## 0. How to keep going (session protocol)

Every Cursor / Grok / human session on this tree:

1. **Read SNAPSHOT** (this file, one screen). If MASTER or TODO disagrees, **this file wins**.
2. **Load `/eoa-full-test`** (`.grok/skills/eoa-full-test/SKILL.md`).
3. **Run `tools/eoa_full_test_gates.sh --quick`** while iterating; full script before merge.
4. **One play-loop slice** — fix the shipped API; extend the existing product/test. No new dual package. No GameData split.
5. **Human §0b notes** — play [`PLAYTEST_AND_DECISION_GUIDE.md`](PLAYTEST_AND_DECISION_GUIDE.md) §0b and **append** [`SESSION_NOTES/2026-08-05_m6_smoke.md`](SESSION_NOTES/2026-08-05_m6_smoke.md). Do not invent M6 complete.

| Next | Action |
|------|--------|
| **Human** | Not required for units. When you do open the map: Maginot chips sit on the hex (centroid), player is GER. M6 20d/60d still open. |
| **Machine** | `--quick` **PASS** + `HeadlessWorldAccurateUnitOrderLoopTest` **RESULT=PASS** (organize/train/priority included). Soft 30fps still FAIL honest. |
| **GitHub** | `origin/main` @ `72a2ce3` (20d clock land_war save/load). Play branch `eoa/l1-war-loop-slice` matches. Do not force-push over June Cursor history. |

**This DAG (PR 1–3 under `505d91d`; this file is PR 4 — not the only PR):**

- §0b first-session surfaces are **machine-composited** (`first_session_play_surface_product` ANDs eight prior builders **+ unit_pick**). That is **not** M6.
- Assault hang-class **closed** at `30910c2` (greps green: fill-pids, no full icon rebuild, BM notify `target_pid`, success-path busy clears in `_assault_post_ui_light`; failure still clears synchronously).
- Interactive multi-AI tag-scope is on the **official gate** (`test_interactive_multi_ai_day_product` in `eoa_full_test_gates.sh`).
- **L1 living unit order loop (machine):** `living_unit_order_loop_product` on `--quick` · `HeadlessWorldAccurateUnitOrderLoopTest` parks GER `710173` / FRA `710739`, proves DemoUnitIcon + org/str/str% + `enqueue_own_land_march` + `start_land_battle`. F5 QA: `EOA_UNIT_ORDER_QA=1`. Strategic chips culled; pick also early-outs when counters not wanted (ocean/terrain/capitals beat chips). Pin-first when chips visible. Inspector Close restores input.
- **Beta B1 world living OOB (machine):** `ensure_playable_front_chips` also stations ENG/USA/SOV/ITA/POL at capitals and **JAP `903981`** on the CHI–JAP edge (`902598`, rear `903966`). Headless: JAP chip pickable; Maginot still **RESULT=PASS**. Not beta-complete (naval/air/peace/AI still dual-thin).
- **Beta B2 second theater (machine):** CHI–JAP living march + `start_land_battle` **opened** (not empty-hex instant). Maginot GER→FRA still PASS.
- **Beta B3 naval living loop (machine):** ENG fleet chip on English Channel sea `950001`, adjacent-sea hop to North Sea `950000` (`enqueue_own_sea_hop`, no land BFS). Channel choke flagged (G toast / NEXT `choke_flag`, supply × from shipped choke bonus). Maginot + CHI–JAP still PASS. Not beta-complete (air/peace/AI/UX still open).
- **Beta B4 air living loop (machine):** GER CAS wing assigned to Maginot strategic region **100** (Germany, contains `710173`; based at Berlin `710300`). Land-tick CAS via `land_battle_cas_power` is higher assigned vs unassigned/wrong-region. Card shows range/fuel. Maginot + CHI–JAP + Channel still PASS. Not beta-complete (peace/AI/UX still open).
- **Beta B5 war/peace/occupation (machine):** NEXT justify/declare calls `apply_war_goal_justify` / `apply_war_goal_execute` (not dual `_day` buttons). After Maginot-scale win, `PeaceConferenceWindow.apply_living_transfer` / `apply_peace_conference_settlement_live` annexes one pid and seeds occupation unrest (overlay + NEXT `occupation_unrest` + inspector chip). Occupier harvest sentence still names era oil/steel/coal at ×0.65. Maginot + CHI–JAP + Channel + air still PASS. Not beta-complete (campaign AI / nation-era UX still open).
- **Beta B6 campaign AI takes land (machine):** Budgeted `try_ai_start_land_battles` opens CHI–JAP (`903981`→`902598`) via `start_land_battle` (never `execute_province_assault` on the initiator; killswitch `EOA_AI_LAND_BATTLES=0`). Live-border scan includes JAP/CHI RoW 900k+ plus hang-safe JAP emergency seed. Headless: second-theater owner of `902598` becomes JAP after AI open+resolve (not Maginot `710739`). Maginot + Channel + air + B5 still PASS. Not beta-complete (nation-era UX / human B0 still open).
- **Beta B7 nation/era/NEXT panels (machine):** `boot_living_player` picks ENG (and other majors); default F5 stays GER Maginot unless `EOA_PLAYER_TAG`. `boot_living_era` boots 1918/1936/2026 (`EOA_START_YEAR`). NEXT `recommend()` omitted tag uses `get_player_country_tag()`; F5 chip/strip pass the living tag. NEXT apply for `tech_done` / `focus_done` / `shortage` opens research / focus / production (`unpause_only=false`) via TopInfoBar `open_living_surface`. Maginot + Channel + air + B5 + B6 still PASS. Not beta-complete (human B0 still open).
- **Beta playtest clock (machine):** `TimeManager.advance_living_playtest_days(20)` drives the **real F5 1x path** (`advance_days` + split `day_emit` / `day_ai` / `day_battles` flush, 60 events for 20 days). Light capture, hang-safe AAR + capture news. Skips new AI land-battle starts, calendar 7d autosave, toast UI, and deferred map refresh on that clock. Never `execute_province_assault`. Maginot harness: `+20 days flushed=60 → 1936-01-21`. After that clock, `living_playtest_saveload_roundtrip` (shipped `_gather_save_data` / `_apply_save_data`) restores elapsed=20 and land_war AAR — PLAYTEST §0b 13 machine, not a human Ctrl+S note. Headless load skips deferred full-board refresh. Not beta-complete (human B0 still open).
- **F5 boot UNIT ORDER QA (machine):** `TechnologyUnlockRegistry` treats `module_unlock` as equipment modules (no per-country warning flood). Headless starting-tech yields less often; UNIT ORDER QA spawns 8 majors only, skips the 3520 map-evidence burst and 4-month settle cycles. `EOA_UNIT_ORDER_QA=1` TestScenario **RESULT=PASS**. Not beta-complete.
- **L1 designer → map unit (machine):** Finalize in DomainDesignPopup / Field seed calls `LeaderManager.field_designed_unit` (via `DesignManager.field_design_on_map`). Custom template becomes a division on Maginot, chip rebuilds, pick/march/assault still **RESULT=PASS**. Product `designer_field_map_unit_product` on `--quick`.
- **L1 unit creator + loop SFX (machine):** Unit Designer picks NATO **symbol** + **strength/org** sliders, fields that chip. Combat bubble pulses; `LandBattleSfx.key_for_unit` maps armor/infantry **move** and **clash** to existing pack keys (no new wavs). Product `unit_design_creator_loop_product` on `--quick`.
- **L1 organize / recruit queue (machine):** Designer **existing vs new** template · multi-recruit (1–8) · core-province deploy · field-vs-new equipment priority. New units train 14d (existing template 10d) at reduced org/rdy/str; refit of fielded units 7d with org/rdy/str dip until ready. Daily chip refresh (amber **TrainPulse**) · unit-card **Training N/Dd** · save round-trips `organize_priority` + days/mode. Equip share 1.0 vs 0.35 into `daily_reinforcement_tick`. `LeaderManager.enqueue_organize` + `tick_organize_day`. Product `unit_organize_queue_product` on `--quick`. Headless `_test_organize`. Not commercial HOI designer.
- **Stockpile → TOE (playtest):** unit card shows Fill% + stock rifles/trucks; daily reinforce toasts `Stockpile → TOE · N units · N eq`.
- **NEXT live fight (playtest):** any open land battle outranks first-session WarLoop copy (`Open fight`). Completing bars / player fights / train / fuel still outrank that.
- **First-session NEXT (playtest):** with no fight/AAR, the NEXT chip shows `WarLoop · B Fronts · Ctrl+click` and applies `show_first_session_war_path`. Completing bars and live fights still outrank it.
- **Panel close (playtest):** Close / Esc holds the inspector shut and cancels the deferred camera nudge so the map does not teleport. A new hex pick reopens it.
- **Pan-from-drag (playtest):** left-drag pans after 8px slop; a click still picks. Chip / Ctrl / Shift clicks stay immediate. MMB and right-drag unchanged.
- **Home key (playtest):** Home / Shift+Home handled in `_input` so search/GUI focus cannot swallow recenter Europe / fit world.
- **Settle titles (playtest):** inspector Settle button uses the province name (London / Devon), not `#id`. Click nearer a capital star than the polygon hit picks the capital (ENG London 711414, not Devon 711467).
- **L1 resolve hang-class (playtest):** F5 day flush is split (`day_emit` / `day_ai` / `day_battles`) so a 6h-cap midnight crossing cannot freeze the clock at 22:00. AI starts skip own-land BFS; empty-hex starts are data-only capture. Attacker-win is `_apply_attacker_win_capture_light`. Time keeps advancing after `open land battles resolved`.
- **L1 G/WarLoop hang-class (playtest):** **G** key frame never BFS/preview_player_route (toast + deferred hop-capped land path, or click-to-show). Polyline via `highlight_supply_route_path`. **L-on** still no 3520 BFS. Shift+I stays toast-only. **I** never builds the flow overlay (flag + existing layer only; WarLoop-armed overlay used to deferred-hang the next frame). Plain **I** also dismisses leftover inspector / unit card / tooltip. Inspector **Close** / Esc (`_input` beats search focus) / unit-card Close hide the stack immediately and `gui_release_focus` so keys/clicks return. `highlight_supply_corridor` still exists for tests.
- **L1 march live (machine):** click friendly land enqueues `enqueue_own_land_march`. TimeManager walks one hop per day. Amber path preview.
- **L1 multi-day battle live (machine):** `start_land_battle` opens a front (F5 empty hex is data-only capture). TimeManager `_tick_open_land_battles` drains org 2–6 days. F5 day flush is emit/AI/battles on separate frames. `LandBattleBubbleLayer` + card Halt/Withdraw/Assign. Template power via `LandCombatPower` (armor ≠ infantry).
- **L1 reinforce + width (machine):** march onto `from_id`/`to_id` of an open fight calls `try_reinforce_land_battle`. Combat width (terrain/infra) caps engaged power; overflow ×0.35. Bubble shows `2v1`.
- **L1 combat depth (machine):** daily equip write-off (`LandBattleAttrition`) + strength drip; nearby air wings add **CAS** to the land tick; **planning** spent on first day; **entrenchment** buffs defender; XP +1.5/day; out-of-combat org/rdy/plan/trench recovery. Card strip shows XP band / plan / trench / last loss.
- **L1 encircle / pocket (machine):** own-land BFS to capital. Connected 100% · thin corridor 75% · encircled 40% +0.08 org/day · pocket 15% +0.14 org/day. Bubble `ENC`. Card `Supply N%`.
- **L1 stance / tomorrow hook (machine):** card **Press** / **Hold** / Withdraw. River/fort extra Press cost. Toast when they **break tomorrow** or a **reinforce arrives tomorrow**.
- **L1 Next chip (machine):** `PlayNextHook` ranks war-loop first (Hold if unit arrives tomorrow, Press if they break tomorrow), then **training ready tomorrow**, **dry tanks / empty fuel**, **steel shortage**, then **research/focus completing tomorrow** (`tech_done` / `focus_done`) — idle unpause last. Map **NEXT** chip + play-strip “Next: …” apply stance, refuel, or unpause. Headless: NEXT is `send_trained` with 1d left on organize, not idle; `rank_from_snapshot` research/focus 1d left is not idle. Develop-mine is instant (no fake multi-day project).
- **L1 after-action (machine):** fight end writes one line (`Took X · N days · loss — Press Y next?`). NEXT chip starts the follow-on assault. Board **~3520**.
- **L1 capture AAR economy (machine):** attacker-win AAR appends era-visible oil/steel/coal (`Now pumping oil (occupied ×0.65).`) via harvest holder + `scale_deposits_for_year` on the captured pid only. NEXT hint carries the line. Headless occupy FRA `710739` oil asserts AAR/NEXT names oil.
- **L1 NEXT completing bars (machine):** `rank_from_snapshot` / `rank_next_beat` take `research_days_left` / `focus_days_left`. War + organize + fuel + shortage still beat these. `TechnologyManager.completing_snapshot` is tag-scoped (no world scan). Develop mine/well stays instant.
- **L1 AI battle start (machine):** budgeted **1** `start_land_battle` / day on a live border (personality + vs-player bonus). Never `execute_province_assault`. Killswitch `EOA_AI_LAND_BATTLES=0`. Full `simulate_daily_ai_combat` stays off in F5.
- **L1 land_war save (machine):** `SaveLoadManager` blob `land_war` round-trips open battles (org/stance/days) + march queues + last AAR. Legacy saves without the key stay empty-ok.
- **L1 long-session save (machine):** `validate_long_session_save` requires metadata/time/map/leaders/infra/land_war/production. Gather always emits `land_war` shape; `save_game_detailed` refuses a missing key. `is_in_combat` already on leaders.
- **L1 leader in live land battle (machine):** `LandCombatPower.leader_power_mult` +0–25% from assigned commander (attack; defend uses defense or attack×0.6). No leader = 1.0.
- **L1 AI campaign (machine):** spare rear `enqueue_own_land_march` to a live-border `from_id` (1/day) + one follow-on `start_land_battle` after attacker AAR. Still never `execute_province_assault`.
- **L1 AI infra invest (machine):** 1 new project/day (`try_ai_start_infra_project`); daily `advance_daily_projects` + `days_remaining`; complete bumps infra +1. Killswitch `EOA_AI_INFRA=0`. Player Invest button unchanged.
- **Gates host (machine):** `tools/map_generation/.venv` + requirements numpy/Pillow. `--quick` uses that Python. Missing deps fail with a one-line install hint. Soft 30fps still **FAIL** honest (~29.4).
- **L1 7-day autosave (machine):** `game_day_advanced` writes `autosave` every 7 elapsed days (1936 20–60d never hits a year tick). Year + quit still fire. Killswitch `EOA_CALENDAR_AUTOSAVE=0`.
- **L1 strength trickle (machine):** out-of-combat +0.03 strength/day (≈3 weeks 0.40→1.0). In combat: no replacements.
- **L1 type letter (machine):** chip shows **I** / **A** / **L** / **H** / **G** / **M** / **R** from designer `visual_archetype` (NATO glyph + colored letter).
- **L1 living unit story (machine):** Counter shows **org + str + readiness** bars. Troop XP (green→veteran) multiplies combat power (~0.80–1.18). Daily replacements dilute XP toward recruit 22; heavy combat strength loss (≥8%) trims veterans. Unit card keeps last battle records + commander initial on chip. Product `unit_living_story_product` on `--quick`.
- **L1 composition + combat losses (machine):** Designer mounts infantry with **motorcycle / truck / half-track**, optional tanks, optional **artillery** (trucks tow guns). Speed = **slowest remaining element**. Composition seeds vehicle TOE (rifles/trucks/tanks/guns); daily land tick writes **men + equipment for attacker and defender**, deducts national manpower, and defenders use armor/defense in `land_combat_power(..., defend)`. Card shows remaining men. Product `unit_composition_combat_product` on `--quick`.
- **L1 composition depth (machine):** Designer **1–6 infantry bns** + **0–3 tank bns** + support **artillery / recon / engineers / AT / AA** (two slots). Line battalions set **combat width**; support is 0-width and towed when mounted. **Fuel use** burns on march hops and daily combat; dry tanks/trucks slow and lose power (foot unhindered). Attacker **hard vs defender armor** is `pierce_mult`. On-hand stock vs TOE applies a **shortage** readiness hit. Card shows width, fuel, TOE. Save round-trips bns + `fuel_level`. Still not commercial HOI battalion designer.
- **L1 fielded-template persist (machine):** `register_custom_design` stores composition on the named template (`custom_designs` + UnitTemplate). **Existing template** reloads widgets from that blob. `field_designed_unit` stamps formation meta from the registered design when extras omit it. Headless fields truck+3inf+tank+arty at 710173 (speed 1.5, width 9) then march/assault **RESULT=PASS**.
- **L1 HOI-like attack/defend split (machine):** Composition **breakthrough** absorbs incoming fire on attack; **defense** on defend (per line-battalion so large TOE does not pin the cap). **Hardness** is a ratio of mixed attack to all-soft (`hardness_factor`) so it still bites on 3-inf templates. Headless same-armor targets: designed unit **197** vs soft / **129** vs hard; absorb att **0.98** def **1.08**. Designer shows Breakthrough / Hardness. Still not HOI numeric tables.
- **L1 industry TOE stockpile (machine):** Factories consume steel/oil/rubber/etc. to produce **the same keys as designer TOE** (rifles/trucks/tanks/guns). Completes credit country equipment stockpile. `reinforce_unit_toe_from_stockpile` fills a share of the gap (field-vs-new); empty stock invents nothing. Day tick `daily_formation_reinforce_from_stockpile` uses that share-capped path (not full TOE) and still delivers 1× `design_id` from factory stock. Headless: fill **0.20 → 0.28** after produce, day tick **0.20 → 0.21** (not 1.0), panzer_iii ×1, combat writes rifles/trucks/tanks. Save round-trips stockpiles. Not HOI efficiency/conversion tables.
- **L1 era resources → nation / industry (machine):** Painted deposits are 1936-baseline. Harvest **era-scales** them (1918 less oil/aluminum, more coal; 2026 more oil/aluminum, less coal; uranium hidden until modern). Income credits **factory-feed keys** (oil/coal/chromium/tungsten) as well as majors so TOE lines can pay from the national stockpile. **Develop Mine / Well** expands an existing era-visible deposit (+35%/level, steel cost, max 3) — cannot invent geology. F9 mapmode + overlay icons use era-scaled amounts (richer deposits draw larger `HudIconLibrary` glyphs). Product `era_resource_deposits_product` on `--quick`. Headless: 1918 oil < 1936 < 2026, develop oil on 710173, harvest credits oil. Not a V3 goods market.
- **L1 occupier harvest + stockpile refuel (machine):** Harvest pays the **controller** (occupier), not the legal owner; occupied yield ×0.65. Out-of-combat truck/tank **refuel draws national fuel/oil** — empty stock invents nothing (foot unhindered). Headless: GER holding FRA oil hex harvests; empty fuel stock no refill; stockpile 0.20→higher. Still not V3 occupation/markets.
- **L1 formation combat save (machine):** LeaderManager persists combat_experience + planning + entrenchment (and land mission). Mid-campaign load no longer resets XP/trench. Calendar autosave toasts “Autosaved · day N”.

**Deferred (not this session, not a gate):** M6 human 20d/60d · soft 30fps FAIL honest · `renderer_frame` · GameData split · densify / SE Asia · DESIGN_LADDER_A corridor/transit (`ceb60fdd-pr-2` / `pr-3` stay parked) · museum / 13k / MP / V3.

**Do not merge:** `origin/cursor/*` (this clone has `origin/cursor/fix-void-return-2453`) · `feature/goals-forward-2026-06-18` · any `execute-plan/ceb60fdd-*` / `ceb60fdd-stack-assembly`. Work this tree (`505d91d`+). Dual board only via `EOA_SCENARIO=world_full`. Godot only via `tools/run_godot.sh`. Never renumber `world_full` IDs.

---

## 1. Default play path (landed)

| Item | Truth |
|------|-------|
| **Engine** | Godot **4.7.1** (`tools/run_godot.sh`) |
| **Command Center** | **CanvasLayer overlay** · wordmark + menu chrome · **✕ / ESC / click dimmer** · **Ctrl+S / Ctrl+L** save/load (no F5/F9 collision) · Help lists WarLoop path · `first_session_hotkeys_product` |
| **First-session play** | Default **GER** Maginot theater · onboarding toast · **B / Shift+I / G / ?** · mapmode icons for states/terrain/resources/fronts/war_loop · supply **fuel** brief on G · **play-strip** Assault/Production (harness debug-only) · assault toast after Fronts |
| **Order strip** | **EOA_PLAY_STRIP** player mode · pure `order_panel_play_strip_product` · dual/harness under `is_debug_build` only |
| **Interactive multi-AI** | Personality-weighted major order (aggression) + budget 3 prod + 1 soft · pure `interactive_multi_ai_day_product` |
| **Nation labels** | Capital **contiguous landmass** centroid (BFS) · scale by province n + pop · pure `map_nation_label_landmass_product` |
| **Unit counters (pins)** | OOB/NATO map chips · **culled at strategic** (ocean/terrain/capitals beat chips) · operational+ full chips · **Shift+U** master toggle · nation plate + org/str bars · docked unit card · **pin-first pick when visible** (48px disk / floor 20 · gold chip · no inspector · `[` `]` stack) · inspector **Close restores input** · `map_unit_counter_lod_product` + `unit_centric_pick_product` + `unit_counter_chrome_product` |
| **RoW sparse densify** | **FULL DONE** — T1 Africa/AUS/Oceania + T2 CA/SA/India/sparse Asia · **~2608 → ~458** scoped playable · board **~3520** · remap `row_sparse_to_playable_remap.json` · pure `row_sparse_density_product` · write `merge_row_sparse_to_playable.py` · adj land_shared **~0.974** · 0 orphans · NE hit **0.986** |
| **Map visual default** | **Clean political** — terrain underlay off · continuous sea + slight zone tint · solid land fills · **HOI-style borders** (dark international only; internal province edges tactical-only — fixes NUTS spiderweb) · pink select outline kept · nation labels high-contrast |
| **Default scenario** | **`world_accurate`** → `data/provinces_world_accurate/` **~3520** (post US + full RoW sparse; was **~5670** / **~8761**) |
| **Hierarchy** | Province → **429** land states → **31** strategic regions (file=membership, multi=0) → **4** super · p2r **3520** |
| **M0 strategic_regions** | **DONE** — rebuilt from membership; North America list 76 |
| **M1 resources mapmode** | **DONE** — toolbar + **F9** · tint from province.resources |
| **M2 states mapmode** | **DONE** — toolbar + **Shift+F9** · state_id golden-angle fills |
| **M3 terrain mapmode** | **DONE** — toolbar + **Ctrl+F9** · plains/forest/mtn/desert palette |
| **M4 supply corridor** | **DONE** — capital/**best key hub** → front · **G** + polyline · pure `map_supply_hub_brief_product` ranks hubs by hops + soft **fuel_score** · MapRenderer toast includes fuel |
| **M5 / A4 measured FPS** | **DONE post-sparse re-sample (2026-07-31)** — n=60 · mean **34.01ms** · p50 **33.62** · p95 **35.61** · ~**29.4 fps** · soft 30fps **FAIL** honest (proxy map-tick). Artifact `tools/map_generation/output/map_perf_world_accurate_samples.json` |
| **A2 US density merge** | **DONE** — TIGER **3221 → 130** playable (1–4/state) · `us_county_to_playable_remap.json` · `merge_us_counties_to_state_provinces.py` |
| **A2b RoW sparse merge** | **DONE full** — T1 Africa/AUS/Oceania + T2 CA/SA/India/sparse Asia · dead **~2150** total · Moscow/Tokyo protected · `merge_row_sparse_to_playable.py` |
| **A3 city/factory LOD** | **DONE** — accurate cull threshold **3000** (board ~3.5k) · city min zoom **0.58** · site min zoom **0.62** |
| **Phase C live fronts** | **DONE** — **B** hotkey + toolbar **Fronts** preset · `MapRenderer.show_live_border_fronts` → `MapManager.collect_live_border_assault_targets` · cycles targets + toast/legend |
| **Stream 2 state labels** | **DONE** — states mapmode (**Shift+F9**) @ operational · **Europe NUTS budget quota** + geo-grid (not pure province_n) so Maginot theater stays labeled · pure `select_state_labels_for_budget` |
| **WarLoop first-session** | **DONE** — toolbar **WarLoop** · **Shift+I** · `show_first_session_war_path` (EquipmentFlow ON + Fronts + assault brief) · pure `map_war_path_surface_product` |
| **Human playtest kit** | **DONE** — `PLAYTEST_AND_DECISION_GUIDE.md` §0b post-merge checklist · **M6 20d/60d narrative still open** |
| **§0b machine composer** | **DONE (PR 1)** — `first_session_play_surface_product` ANDs eight shipped builders **+ unit_pick** · on `eoa_full_test_gates.sh --quick` · **not M6** |
| **Assault hang-class** | **CLOSED (PR 2 · `30910c2` greps green)** — no inspector on execute success · pid-only fill/icons · BM notify `target_pid` · success busy in `_assault_post_ui_light` |
| **Adjacency** | `shared_edge_near_vertex_plus_knn` · land shared coverage **~0.974** · 0 land orphans · GER↔FRA kept |
| **Geometry** | GIS hybrid + **us_merge_v1** + **row_sparse_merge_v1** · NE land hit **0.986** |
| **Map finished (machine)** | **YES** — dual IDs intact · sparse densify closed · pick/multi-front/assault headless green · **M6 human notes not a gate** |
| **Multi-front map** | Maginot · Polish · Alps · Baltic · CHI–JAP (real edges) |
| **Multi-front live AI** | **Landed** — enemy border targets (not own stations) · Maginot+Polish headless PASS |
| **HOI OOB deploy** | capital → key hubs → border → rest |
| **Industrial hubs** | 31 key_provinces elevated factories/infra/city tier |
| **Strategic resources** | coal/steel/oil/rubber/aluminum/chromium/tungsten painted (data **yes**) |
| **Naval chokes** | **34** sea chokepoints |
| **Mapmodes (runtime)** | political, **resources (F9)**, **states (Shift+F9)**, **terrain (Ctrl+F9)**, supply + **corridor (G)**, development, infra, vitality/strain, loyalty, weather… |
| **Mapmode gaps** | Optional residual polish only (label density tuning) |
| **D1–D5.5 machine** | Leaders/tech/OOB · war loop · AI daily · save product · mapmode colors · FPS pilot · fronts live |
| **20d / 60d machine** | Pure products landed; **human narrative notes still open (M6)** |
| **Scaffold dual** | `EOA_SCENARIO=world_full` (~2665); IDs never renumbered |

### Map composition

| Block | Scale |
|-------|-------|
| Europe NUTS-3 | 1514 (IDs 710000+) |
| US playable (post merge) | **130** (IDs 800000+ survivors; was 3221 TIGER) |
| RoW (post full sparse) | **~1536** (IDs 900000+; was ~3686; SE Asia still denser) |
| Seas | 340 (IDs 950000+) |
| **Total** | **~3520** (land **~3180** + sea 340) |

---

## 2. Pillar health (map as living star)

| Pillar | Status | Still open |
|--------|--------|------------|
| Hierarchy data (prov/state/region) | **Landed (M0)** — 31 regions file=membership | |
| Resources mapmode | **Landed (M1)** — F9 + toolbar | |
| States mapmode | **Landed (M2 + Stream 2)** — Shift+F9 + **state names @ operational** | Label budget density polish |
| Terrain mapmode | **Landed (M3)** — Ctrl+F9 + toolbar | |
| GIS world default + pick | **Landed** | Human capital click checklist |
| Political / fronts / assault | **Landed** — machine + **B/Fronts** player surface | Multi-month AI personality |
| Resources / chokes / hubs | **Data + resources mapmode (M1)** | |
| Supply corridor UX | **Landed (M4)** — G + hub rank + fuel brief toast | Optional deeper network |
| Density / LOD | **Landed culls + A4 post-merge samples** | Graphical `renderer_frame` optional |
| Long campaign feel | Machine 20/60d | **Human 20–60d notes (M6 still open)** |

---

## 3. Next map-priority work (ordered)

From [`WORLD_CLASS_MAP_REVIEW.md`](WORLD_CLASS_MAP_REVIEW.md) §4 + forward plan:

1. **Human §0b items 3–15** — `tools/run_godot.sh --path . res://scenes/TestScenario.tscn` · append [`SESSION_NOTES/2026-08-05_m6_smoke.md`](SESSION_NOTES/2026-08-05_m6_smoke.md)  
2. **M6** Human 20d + 60d playtest notes (**still open — not automated, not a machine gate**)  
3. Next machine: playtest-driven shipped-path fix only (no dual, no GameData split, no `ceb60fdd-*`)  
4. Optional residual (post full-test, not P0): SE Asia micro-merge if noisy · graphical `renderer_frame` · deeper fuel networks · designer UX polish · persistent OOB Attack chip · DESIGN_LADDER_A corridor/transit (parked)




**Done (map machine closed + HOI P0 matrix closed):** **M0–M5** · **A2** · **A2b RoW full sparse** · **A3** · **A4** · **Phase C Fronts** · **Stream 2** · **WarLoop** · **Command Center save** · **unit counter LOD** · **HOI pillar matrix open P0=0** (industry/research/diplo/multi-front/supply/air/naval/intel/OOB/save).

### Map playtest follow-ups (2026-07-21 human + 2026-07-25 A2)

| Issue | Status |
|-------|--------|
| F2/F3/F4 looked dead | **Fixed** — full visible strain/vitality/dev gradients (not data-gated) |
| Void hex / can’t reach Europe | **Fixed v2** — content AABB underlay fit · wrap **off** · **Home** re-center |
| Notices unreadable (red corners) | **Fixed** — flat toast panels (no 9-slice ornament frame) |
| US too dense (3221 counties) | **DONE A2** — **130** playable (1–4/state) · remap table shipped |
| Cities/factories at zoom | **DONE A3** — higher min zoom on accurate boards |
| Artistic underlay vs GIS borders | **Known** — GIS pick/path is truth; underlay is atmosphere |

### A4 / M5 sample evidence (2026-07-29 post full RoW sparse)

| Field | Value |
|-------|-------|
| **kind** | `map_tick_proxy_headless` (pick + adj + land path ×60) |
| **provinces** | **3520** loaded |
| **n** | 60 |
| **mean / p50 / p95** | **34.01 / 33.62 / 35.61 ms** |
| **est. fps** | **~29.4** |
| **soft 30fps** | **FAIL** (mean 34.01 > 33.3ms) — honest; do not invent PASS |
| **artifact** | `tools/map_generation/output/map_perf_world_accurate_samples.json` |
| **capture** | `tools/run_godot.sh --headless -s res://scripts/core/HeadlessWorldAccurateMapPerfTest.gd` |

### Phase C fronts surface

| Control | Action |
|---------|--------|
| **B** | Cycle live border assault targets for player tag (default GER) |
| Toolbar **Fronts** | Same as B — toast + legend + select target + edge highlight |
| API | `MapManager.collect_live_border_assault_targets` · `MapRenderer.show_live_border_fronts` |

### Stream 2 state labels surface

| Control | Action |
|---------|--------|
| **Shift+F9** / toolbar **States** | States mapmode fills |
| Operational zoom | State **name labels** appear (hidden at strategic; nation labels suppressed in states mode) |
| API | `MapZoomLOD.show_state_labels` · `MapPoliticalLabelsLayer.set_map_mode_context` · pure `map_state_labels_surface_product` |

Proxy is **CPU map path**, not full MapRenderer GPU FPS. Soft gate remains FAIL until a lighter graphical sample passes mean ≤33.3ms.

Do **not** renumber boards or chase museum borders for full-test.

---

## 4. Evidence (machine)

```bash
python3 -m unittest tools.map_generation.tests.test_world_accurate_board -v
python3 -m unittest tools.map_generation.tests.test_row_sparse_density_product -v
python3 -m unittest tools.map_generation.tests.test_world_accurate_strategic_and_assault -v
python3 -m unittest tools.map_generation.tests.test_world_accurate_multi_front_and_deploy -v
python3 tools/map_generation/scripts/map_accuracy_qc.py \
  --dir data/provinces_world_accurate --min-land-hit 0.90
tools/run_godot.sh --headless -s res://tools/map_manager_pick_harness_accurate.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMultiFrontAssaultTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateUnitOrderLoopTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMapPerfTest.gd
python3 -m unittest tools.map_generation.tests.test_map_perf_m5_measured -v
tools/run_godot.sh --path . res://scenes/TestScenario.tscn
```

**Map machine gate status:** closed. **Full-test play path re-verified 2026-08-01** (unit + QC + headless pick/assault + save + year multi-AI 365d; SCRIPT ERROR 0).  

**§0b composer + hang-class + multi-AI + L1 living counters (2026-08-16):** `test_first_session_play_surface_product` (includes `unit_pick` + `unit_chrome`) · `test_first_session_assault_surface_product` (hang-class greps green at `30910c2`) · `test_unit_centric_pick_product` · `test_unit_counter_chrome_product` · `test_interactive_multi_ai_day_product` — all in `tools/eoa_full_test_gates.sh --quick`.

**Living unit order loop (2026-08-17):** `test_living_unit_order_loop_product` on `--quick` · `HeadlessWorldAccurateUnitOrderLoopTest` **RESULT=PASS** (GER 710173 chip + march + opened Maginot battle, not empty-defender instant). Full gates: `launch_unit_order`.

**Year multi-AI (lean) latest:** 71 nations · 365 days · major_apply_sum ≥ majors×days/2 · no OOM · shell fail-closed on SCRIPT ERROR / Killed.  

Remaining map-star open item is **human-only M6**. This keep-going board is **PR 4 of 4**, not the only PR.

Next orchestration: **[`GAME_DIRECTOR_PLAN.md`](GAME_DIRECTOR_PLAN.md)**.
