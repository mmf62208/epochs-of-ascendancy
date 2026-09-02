# Testing Plan — Epochs of Ascendancy

## Goals

- Ensure new systems (especially Time + Daily Effects) work reliably.
- Catch regressions when adding new features.
- Make it easy to verify that daily/monthly/yearly systems behave correctly.

## Recommended Testing Approach

### 1. Core Time System Tests

- Load a scenario and verify the top bar date matches `start_date`.
- Let the game run for several in-game days/months/years.
- Test Pause / Speed buttons.
- Verify that yearly systems (research, agent missions, leader events) still trigger correctly.

### 2. Daily Agent Pressure Tests

- Create or load a scenario with active `supply_disruption` and `infrastructure_sabotage` networks.
- Observe daily changes in:
  - Province infrastructure level
  - Local supply generation
  - Depot stock / throughput
- Use counter-intel missions and verify `clear_daily_sabotage_effects` works.
- On the map: confirm ⛟/⚙ pressure tint, ring glyphs, status bars (infra/depot), and tooltip repair lines.
- New events: advance to 1938+ (or use harness), check logs/toasts for Anschluss, Munich, 1939 war trigger, econ crises, hand rev events, peace ripples. Use LeaderEventUI icons visible.

### 3. Technology Tests (Support/Radio)

- Research `radio_ii` and verify supply route performance improves.
- Check that `planning_speed` and `reconnaissance` bonuses appear in tooltips and the map.
- Verify ETA and progress display correctly in the Technology screen.

### 4. Multi-Overlay Map Tests

- Enable Supply overlay (L) while having both contested and agent pressure provinces.
- Verify legend, tooltips, and hover states remain readable.
- Check that daily time pulses and Technology bonuses display cleanly.
- Hover pressure provinces: legend footer should show compact repair/depot info.

### 4b. Map Data Validation (CI / agent cycles)

```bash
bash tools/run_map_ci.sh data/provinces_phase1_test
# Or step-by-step:
python3 tools/map_generation/scripts/repair_city_positions.py --dir data/provinces_phase1_test
python3 tools/map_generation/scripts/promote_map_master.py
python3 tools/map_generation/scripts/add_sea_zone_prototype.py --dir data/provinces_phase1_test   # optional; 471→472
python3 tools/map_generation/scripts/sync_phase1_base_catalog.py --dir data/provinces_phase1_test
python3 tools/map_generation/scripts/repair_phase1_references.py --dir data/provinces_phase1_test
python3 tools/validate_province_layers.py --dir data/provinces_phase1_test --strict-base
python3 tools/map_generation/scripts/export_naval_chokepoints.py
python3 tools/map_generation/scripts/sync_river_aware_terrain.py --dir data/provinces_phase1_test
python3 tools/map_generation/scripts/align_province_spot_check.py --dir data/provinces_phase1_test --europe-only
```

Expected: `VALIDATION PASSED`, 471–472 provinces (472 with sea zone prototype), base ids == geometry ids, alignment 0 warnings with `--europe-only`, `[MAP UX EVIDENCE]`, `[GRAND THEATER QC EVIDENCE]`, and `[ERA INFRA]` / era profile in infra layer logs when `EOA_RUN_SIM_CYCLES=1`.

**Era infra (in-game):** Press **R** / **T** for roads/rails; density/style shifts by year — sparse ≤1924, standard 1925–1999, dense ≥2000. F10 → Preview Era Infra 1918/1936/2026 buttons.

**Phase E perf:** At strategic zoom (≤0.55) in clean political view, `ProvinceMeshLayer` batches owner fills. F10 → Toggle Batched Mesh Fills. Headless logs `[PERF MAP EVIDENCE]`.

**Grand theater QC (automated):**
```bash
python3 tools/run_grand_theater_qc.py          # full incl. godot --check-only
python3 tools/run_grand_theater_qc.py --skip-godot
bash tools/run_map_ci.sh                       # data validators + QC
```
Rebuild art from cached NASA/Natural Earth tiles:
```bash
python3 tools/map_generation/scripts/build_real_world_map_layers.py --region world_full --skip-download
python3 tools/map_generation/scripts/build_real_world_map_layers.py --region europe_grand_theater --skip-download
python3 tools/map_generation/scripts/split_world_canonical_chunks.py
python3 tools/map_generation/scripts/promote_map_master.py
```

### 5. Regression Tests

- After any `TimeManager` change, verify yearly systems still fire.
- After any `AgentManager` change, verify daily + yearly paths both work.

## Suggested Test Scenarios

- **1936 start** with radio tech already granted.
- Scenario with **active enemy agent networks** on key provinces.
- **Long play session** (multiple in-game months) to test cumulative effects.

## Automated / Headless Hooks (Existing)

| Script | Purpose |
|--------|---------|
| `scripts/core/TestRunner.gd` | Entry point for headless test runs |
| `scripts/core/HeadlessSupplyTest.gd` | Supply system smoke tests |
| `scripts/core/ProductionLineTest.gd` | Production line tests |
| `scripts/core/SupplyLineTest.gd` | Supply routing tests |

Run from Godot with the project’s test scene or headless entry (see `TestRunner.gd` for invocation).

### Headless status (June 6, 2026)

**Fast smoke (recommended):**
```bash
godot --headless --path . res://scenes/TestScenario.tscn --quit-after 15
```

**Full leader roster reload (heavy, may OOM):**
```bash
EOA_RUN_FULL_LEADER_TESTS=1 godot --headless --path . res://scenes/TestScenario.tscn --quit-after 45
```

**ProductionLineTest suite:** passes design, stockpile, mixed divisions, marine readiness, phased combat, formation spawner, cargo logistics.

| Suite | Result |
|-------|--------|
| Design / production / refinement | ✅ Pass |
| National stockpile / auto-reinforce | ✅ Pass |
| Mixed division generation | ✅ Pass |
| Marine readiness | ✅ Pass |
| Leader replacement enqueue | ✅ Pass |
| Phased combat resolution (4 phases) | ✅ Pass |
| Combat width | ✅ Pass |
| Formation spawner / cargo logistics | ✅ Pass |
| Full 1918/2026/1936 roster reload | ⏭ Skipped unless `EOA_RUN_FULL_LEADER_TESTS=1` |

**Interactive checks (F5):**
- Province click → scrollable InfoPanel; Close/Esc keep Europe framed (north-strip edge-pan must not unlock/fly to Greenland; no Home required) and keep fills; left-drag pan must not pick land or sea or coarse or capital-star snap (leftover `pressed=true` keeps slop until Home/End/wheel/WASD — not mouse-up motion; `_left_map_pick_blocked` is true while not ready); End shows Tokyo + Beiping/CHI overlay star + China label
- **F10** debug overlay: full-width buttons, no horizontal scroll; drag title; resize **⤡**
- Menu open/close restores pause + speed on TopInfoBar

**Grand theater load:** console should show high-res map line + `Loaded 141 leaders` for `phase1_europe_test`.

**Map visual QC:** [TEST_MAP_GRAND_THEATER_FOUNDATION.md](TEST_MAP_GRAND_THEATER_FOUNDATION.md)

## Future: Structured Harness

- [ ] Scenario fixtures for “agent pressure on capital + hub”
- [ ] Assert infra repair rate and depot `sabotage_level` after N days
- [ ] Snapshot tests for `ProvinceInsight` tooltip BBCode keys (optional)

## 50+ Turn Integrated Playtest Harness (2026-06 update)

For full polished 50+ turn validation with combat/AI/infra/peace/econ + living world events (riots ownership-conditional + research ethics) + save/load integrated:

**Headless CI-like (recommended for validation of parallel agent work):**
```bash
# Short smoke still:
godot --headless --path . res://scenes/TestScenario.tscn --quit-after 15

# Full 50-turn econ+war+infra+peace sim (pop growth, factory assign/train/produce/recruit, AI assaults/chain, infra projects advance, policy/peace events + NEW 1936+ scripted like Anschluss/Munich/war/econ/hand, mem guard, progress logs; new weather penalties + portraits in UI):
EOA_RUN_50_TURN_SIM=1 godot --headless --path . res://scenes/TestScenario.tscn --quit-after 300

# Or alias + with full harness cycles:
EOA_RUN_LONG_SIM=1 EOA_RUN_SIM_CYCLES=1 godot --headless --path . res://scenes/TestScenario.tscn --quit-after 240
```

**F5 Interactive + F10 harness:**
- Load TestScenario.tscn
- F10 → "▶ Run 30 day econ+war playtest sim (pop/prod/train/recruit + AI assaults + infra + peace/events)"
- Watch console for [50T SIM PROGRESS] / [30D ...] every 5d: assaults, recruits, prod, infra, pop, coh, mem.
- 50t mode via env for full multi-month/year (use terminal godot ... with env).

**What the sim drives (exercises combat/infra/peace/econ features from parallel agents):**
- TimeManager advance_one_day (daily: supply, agents, infra tick, combat recovery; monthly: pop growth + labor to industrial_base, erosion, peace events like welfare/HH/hand revelation/Rhineland/social rev).
- ProductionManager.advance_days + assign_line_to_factory + training flags (produce + train loop).
- GameData.recruit_units + get_available_recruits (pop-driven manpower recruit).
- InfrastructureDevelopmentManager.advance_daily_projects + try_start_infrastructure_investment (infra invest complete + daily).
- DebugOverlay._simulate_ai_combat_turn + direct BattleManager.execute_chain_assault_or_flank (wars: AI multi-prov targeting low-org/infra, chain/flank, persist).
- GameData apply policies + get_peace_state (peace: hand, welfare_burden, cohesion, events).
- SaveLoad quick roundtrip post-sim (combat state + infra + pop + settlement persist).
- Memory guards (OS.get_static_memory_usage, warn >1400MB).
- Progress + final state logs ("50 turn" ready, no OOM/crash/hang).

**Production/Supply/Combat tests:** continue to pass (ProductionLineTest etc called in harness).

**Update TEST_MAP... or add:** expect no hang, "50T SIM PROGRESS" lines, "COMPLETE" with final pop/coh/hand/assault counts, mem <2GB typical.

**Python helper (tools/tester_enhancer.py --godot-test or extend for long):**
Use to auto-launch with env + parse logs for "50T SIM" success keywords.

**Recent validation (post edits):** headless runs produce clean progress without errors; 30d F10 from graphical interactive; guards prevent quickload OOM on short evidence. 50t full ~ reliable for "full 50+ turn polished".

**Fast dedicated tests for riots/research events + save/load persist (key for this task's requirements) + 4-6 NEW major events:** 
EOA_TEST_SAVE_LOAD=1 or EOA_FAST_TEST=1 godot --headless res://scenes/TestScenario.tscn --quit-after 60 (or 90). 
- Early (in GameData _ready) or sync post "MAP SHOULD BE VISIBLE NOW" (in TestRunner): force low coh on GER/FRA + high hand + ignored ethics response, process_monthly_demographic_erosion (exercises riots ignition/spread/duration/HH amp + Paris pid4 ownership conditional + Berlin cond + research ethics 6mo delay via pending + Technology signal), + explicit calls to process_separatism_crises / process_*_sabotage / scandal / labor / naval / chain / weather_famine + record_ethics_response + handle_riot_player_choice + start_riot with dur bump, quicksave/load roundtrip, pre/post dumps of active_riots/pending + NEW separatism_risk/radicalization/ethics_responses/scandal_meter, explicit "RESULT: PASS".
- Evidence example (logs/gd_early_result_... + forced_fire_ev + process_call_ev + 50t_force_ev): "[GD_EARLY_TEST] pre-save: riots=[] pending=[] separatism=[...] radicalization=[...]" + "SaveLoadManager: Game saved → user://saves/quicksave.json (v1, 4532 bytes)" + ... "post: ... RESULT: PASS" + "[NEW EVENTS MONTHLY] Called all 4-6 new processors..." + "[SEPARATISM PROCESS CALL]..." + "[SABOTAGE PROCESS CALL]" + "[SCANDAL PROCESS CALL]" + "[FORCED DIRECT] start_separatism..." + "[50T EVENT SIM] Forced ... + NEW: ... SEPARATISM,SABOTAGE,LABOR(pid3),NAVAL/COASTAL,SCANDAL,ETHICS CHAINS,WEATHER FAMINE" + "[ETHICS RESPONSE] ... 'ignored'" + "[RIOT START]" + "[RIOT RESOLVE]" + erosion side-effect + social rev + HH. Logs show toasts/news via cats, persist checks.
- 50T launcher (EOA_RUN_50_TURN_SIM=1 --quit-after 80+) + forces every t%5 (high hand, ignored ethics, mandate low, explicit new procs + handle_riot) produce full "[NEW EVENTS MONTHLY]", process calls, riot start/resolve, ethics record, final state with sep/rad/ethics/scandal counts + samples. Check logs/50t_force_ev.log etc.
- Use to verify requirements (Paris only if owns pid 4, riots on coh<50% multi-prov duration hits depending on handling + radicalization from concede, research delay ethics concerns + chain sabotage if ignored, geo pid3 labor + coastal naval via MapManager.get_owned_coastal_or_port_provinces, HH scandal from high hand, player choices persist effects via dialogue record/handle + radicalization, save/load of new states, all integrated in monthly + TestRunner). Python: tools/validate_50t_logs.py or grep -E '\[SEPARATISM|\[SABOTAGE|\[HH SCANDAL' in logs. 

**NEW for 50T Validation & Harness Specialist (EOA_HEADLESS_EVIDENCE + rich verifiable logs):** 
- `EOA_HEADLESS_EVIDENCE=1 EOA_RUN_50_TURN_SIM=1 godot --headless --path . res://scenes/TestScenario.tscn --quit-after 1500` (or 5000; or EOA_RUN_LONG_SIM=1; use timeout 120s wrapper if --quit-after races). Skips heavy visuals (IconPreview, legend, extra demo seeds, grand bg, naval/air heavy) in TestRunner._deferred_grand... + ScenarioLoader for fast init to 50T while core sim (provinces/MapManager owners, basic seeding, GameData process/riots/pending) live. Graphical unaffected.
- Produces rich: "[50T SIM PROGRESS] Turn X/50" (every 5, x8+ in run), "[50T EVENT SIM] Forced monthly erosion..." + "[RIOT START] Riots break out in ... (pid ... owner GER/FRA)", "Paris (pid 4)", resolve_riot calls/samples with duration>1, research complete + "RESEARCH ETHICS EVENT"/"ETHICS RESPONSE", quicksave details, "[50T FINAL STATE]" / "[50T PERSIST CHECK]" / "POST-LOAD" with active_riots non-empty samples (dur>1) + pending, "COMPLETE".
- Fast + save: EOA_FAST_TEST=1 EOA_HEADLESS_EVIDENCE=1 + EOA_TEST_SAVE_LOAD=1 for early RESULT PASS + hardened asserts (non-empty riots dur>1 post force/save/load).
- Validate: `python tools/validate_50t_logs.py logs/50t_full_rich_....log` (enhanced parses RIOT START/ETHICS/Paris/resolve/pending/active_riots non-empty + progress x10+).
- Evidence paths: logs/50t_full_rich_final_*.log , 50t_rich_evidence_*.log (see 904+ lines with 50T x8, multiple RIOT/Paris/resolve + ethics response).
- Bugs fixed: early 50T schedule (pre-mm + direct sync for headless_evidence to beat defer/quit races); forced post prints; duration samples in checks. 50T now default 50 turns.

## Graphics Wiring + Perf Scale (EOA_HEADLESS_EVIDENCE + new assets + culling 2026-06-18)

New assets generated (image_gen grand strat/wargame flat bold 64px transparent style) + wired:
- riot_crowd_64.png + riot_marker_*.png (icons/events/) - wired to LeaderEventUI crisis/riot toasts (TextureRect) + MapRenderer riot tints/markers on active_riots pids.
- ethics_debate_32/64.png, separatism_flag_32/64.png, scandal_32/64.png (icons/events/)
- soviet_tank_variant_32/64.png, naval_destroyer_32/64.png, interwar_fighter_32/64.png (units/nato/modern/) + nato_counters_sheet.png already in units/ (now used for variants in MapRenderer unit icons).
- Also 32px variants for map counters.

**Fast 50T evidence with graphics/perf (skips heavy init for scale):**
```bash
# Fast headless evidence (skips chunks/elev/legend/IconPreviewTest/full demos/overlays in deferred; core 471 polys/owners/sim/GameData riots + culling active; timings + per-5 avgs printed):
EOA_HEADLESS_EVIDENCE=1 godot --headless --path . res://scenes/TestScenario.tscn --quit-after 120

# + fast test (erosion/riots/save + events):
EOA_HEADLESS_EVIDENCE=1 EOA_FAST_TEST=1 godot --headless ... --quit-after 30

# Full 50T integrated (with new env for speed):
EOA_HEADLESS_EVIDENCE=1 EOA_RUN_50_TURN_SIM=1 godot --headless --path . res://scenes/TestScenario.tscn --quit-after 180
```
- See TestRunner: _wants_headless_evidence + [HEADLESS EVIDENCE] skips + [TIMING] map init / deferred / 50T total + last5 avg ms/turn + godot --profile tip.
- Culling active: Weather/Infrastructure/MapRenderer _get_* use GameData.get_provinces_with_active_riots() + pending + majors/owned (lazy non-int skip unless dirty in fills).
- Riot visuals live: red tint on polys + sprite markers (using riot_*.png) for pids in active_riots; NATO sheet Atlas subregions by tag (SOV blue etc) for unit counters on majors.
- Verify in logs: riot toasts use custom icon, MapRenderer riot markers, fast "deferred skipped in X ms", progress with avg times, no heavy IconPreview etc.
- F5 graphical: all assets + full overlays + no skip (visuals for riots in F10 mapmodes or when events fire; unit variants on stationed).

Assets paths absolute: /home/mikef/epochs-of-ascendancy/assets/graphics/icons/events/riot_crowd_64.png etc + units/nato/modern/*. Also update imports on first graphical (or rm *.import for new pngs).

See CURRENT_STATE graphics/perf + TODO. Coords with 50T agent via env. 
