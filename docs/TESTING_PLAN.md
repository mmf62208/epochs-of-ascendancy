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
- First-session **G** (GER Maginot, after Begin → Europe → Home): toast plus a readable cyan supply-route polyline (camera-space ~26 screen px, dark halo, follow-viewport layer 10, `highlight_supply_route_path`). Hang-safe: no corridor BFS on the G key frame.
- Begin GER → Europe Home: ≥1 GER land Division chip is **visibly painted** (`show_unit_counters_for_zoom` Home floor 0.24; `_sync_unit_counter_paint` after Home/Begin). World Shift+Home still culls. Still-click chip chrome/label (plate + UnitChipText, not only the half-plate disk) opens the docked **GER** Fill%/TOE card (not PER/SOV/DNK/province-only) — Home-band hit covers the full painted AABB (`_unit_counter_hit_radius_world` live DemoUnitIcon half-diagonal, else `0.5 × sprite × scale × √2 + label_pad`). Land still-click is player-tag land only (no foreign `best_any`). Disk miss resolves **hex-only** province under click (`_resolve_hex_pick_pid`, not capital-star `_resolve_map_pick_pid`) → `_player_land_formation_at_province` before star/tooltip. If that hex has no player land (Home chrome spill onto Neustadt / Schwäbisch Hall / FRA **or Berlin-Home / capital neighborhood** while GER stays on `710173` ~278u away), `_nearest_player_land_formation_at_world` binds the closest visible player-land `DemoUnitIcon` when `d <= max(hit_r, CHROME_SPILL_WORLD)` (spill ≥320 covers Berlin↔Maginot). If an air_wing / fleet / space_wing shares the disk, still-click re-picks player land (`_pick_land_unit_formation_at_world`) and resolves stack land at the chrome province via `_collect_formations_at_province` before neighbor icons; `_try_open_unit_at_world` after land attempt is air/fleet/space only (never foreign land). Air-only clicks still lose to capital stars (star is the **next** still-click step after land-open false).
- Province click → scrollable InfoPanel; Close/Esc keep Europe framed (north-strip edge-pan must not unlock/fly to Greenland; no Home required) and keep fills; empty-area left-drag after 8px slop pans (drag up = camera north) even after Esc/Close and while paused — `_process` `_left_drag_should_pan` → `_left_pan_active` → camera; finished drag must not pick land or sea or coarse or capital-star snap (Area2D never pick on press; hold+slop/skip returns before inspector; `_left_release_must_skip_pick` + `_left_live_slop_is_drag` on `_unhandled_input` / coarse / title / Area2D release; mid-gesture left-down + live slop ≥8px latches `_left_skip_next_pick` before `_note` — eed9b5f Drag2 Labrador Approaches West `_unhandled_input` spatial pick; leftover `_rearm` must not clear skip/slop/cam latch — 51dc2a4 Rio Grande Rise; `genuine_new_press` is not leftover-hold; sticky slop + camera-move latch survive leftover `_begin`; 2nd/3rd empty-area drags re-arm after leftover hold / `genuine_new_press`; idle `_allow` unsticks leftover `_left_btn_down` on physical up so Drag1–3 can genuine-reset origin (47af97a CC dimmer / swallowed `_end`); leftover hold also unsticks btn-down without `_rearm`; idle-up `_begin(true)` is not first-line blocked; `_input` reseeds on idle-up `event.pressed` (650c85c-cc no-move; Input singleton can stay stale); leftover-hold Drag2+3 reseeds origin from `_input` after idle-up only (1f48f56 no-move; not PR 24 `_begin` seed); closing/queued MainMenu must not `modal_blocks_map_nav`; hover glance hidden while left-down + slop/pan/skip (MAR North); edge-pan while left-down counts as THIS drag; Home clears sticky; search LineEdit must take focus); **Esc dismiss-then-idle CC** (`_handle_escape_key` same-press `_esc_stack_frame`: 1st Esc closes settle/inspector, idle Esc `call_deferred("_on_menu_pressed")`; leftover FileDialog exclusive / hidden MainMenu must not sticky-block; never `queue_free` MainMenu); unit-card Open fight must open Maginot Attacker/Defender sheet (not tooltip-only); unit-card Fill%/TOE is a 16px CYAN/SUCCESS/WARNING wrap line + thin bar on the 320×220 dock above the clip fold (Fill is not Strength%; Org/Str/Rdy/XP/plan/trench/Speed/Armor/Men + last-3 combat log on tooltip; GER Division chip still-click opens it from `_input` — province tooltip IGNORE, not a pick blocker); **first** End shows Tokyo + Beiping standalone gold stars + China label (no SOV red hulls over China/Mongolia, no RUS West)
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

### Maginot land uniformity (FEED-2)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_maginot_land_uniformity_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Combat / Esc / G / Dig2 are out of scope for this theater proof.

### Gibraltar island-scale land (FEED-3)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_gibraltar_island_land_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Seas coarsening / Hong Kong / Maginot combat / Esc / G / Dig2 are out of scope for this theater proof.

Honest: `--quick` still fails `test_living_unit_order_loop_product` on tip `caa3c8e7` (playtest-clock / air-CAS / peace / nation-era / map-country wiring). This FEED does not touch those files.

### Alboran seas coarsen (FEED-4)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_seas_coarsen_feed4_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Gibraltar land / Maginot land / Great Lakes / Esc / G / Dig2 / combat are out of scope for this theater proof.

Honest: `--quick` living-unit wiring fails are **tip-pre-existing** on `8340c05d` (same files). This FEED does not touch those GD files.

### Hong Kong island-scale land (FEED-5)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_hong_kong_island_land_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Gibraltar land / Alboran seas / Maginot land / Great Lakes / Esc / G / Dig2 / combat are out of scope for this theater proof.

Honest: `--quick` living-unit wiring fails are **tip-pre-existing** on `ce8d7c2021a5bf01eeb841edfd9f379ad82847b5` (same files). This FEED does not touch those GD files.

### Caribbean ordinary-island sizing (FEED-6)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_caribbean_island_sizing_feed6_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Gibraltar land / Hong Kong land / Alboran seas / Maginot land / Great Lakes / Esc / G / Dig2 / combat are out of scope for this theater proof.

Honest: `--quick` living-unit wiring fails are **tip-pre-existing** on `8bd654c206a20833ce9d446061f93ed964d55d88` (same files). This FEED does not touch those GD files.

### Flanders / Nord land uniformity (FEED-7)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_flanders_nord_land_uniformity_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Maginot re-touch / Ruhr/NRW / Dig2 / G / combat / Taken / JOINING / Esc are out of scope for this theater proof.

Honest: `--quick` living-unit wiring fails are **tip-pre-existing** on `8cae5f903dbcc5dce4cbbdfff2cbb3826636753b` (same files). This FEED does not touch those GD files.

### Ligurian Sea basin reshape (FEED-8)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_seas_coarsen_feed8_ligurian_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Alboran / Tyrrhenian / Adriatic meshes / Maginot land / Flanders land / Great Lakes / Esc / G / Dig2 / combat are out of scope for this theater proof.

Honest: `--quick` living-unit wiring fails (if any) are **tip-pre-existing** on `665970c641baf10aed756e6354093b4fed250ae0` (same files). This FEED does not touch those GD files.

### SE England shire land uniformity (FEED-9)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_se_england_shire_land_uniformity_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Maginot / Flanders / Ligurian remesh / Greater London grow / Central Hampshire split / Dig2 / G / combat / Fill%·TOE / pale-map / Esc are out of scope for this theater proof.

Honest: `--quick` living-unit wiring fails are **tip-pre-existing** on `1388a3ecae54635e57ea0e9a10b801ca895ddca2` (same files). This FEED does not touch those GD files.

### Tyrrhenian Sea basin reshape (FEED-10)

Pure product + board QC (no Godot):

```bash
python3 -m unittest tools.map_generation.tests.test_seas_coarsen_feed10_tyrrhenian_product -v
```

On `--quick` via `tools/eoa_full_test_gates.sh`. Ligurian / Alboran / Adriatic meshes / Maginot land / Flanders land / SE England land / Great Lakes / Esc / G / Dig2 / combat are out of scope for this theater proof.

Honest: `--quick` living-unit wiring fails (if any) are **tip-pre-existing** on `b335344c4c9d0cba1aa6c1ae7f51733e9e249731` (same files). This FEED does not touch those GD files.

### IX-1 Play F5 smoke-only auto-begin (delivery hatch)

Play F5 computerUse on `6573d01` never delivered post-boot `EOA_LIVE_RAW_*` into the Godot X11 window (`title.ready` only). Product Begin / Esc / mouse CC stay **FAIL**.

For IX-1 **softpipe only** (past-+6 → Search Köln/Cologne + Go → spine), Play must launch:

```bash
EOA_SMOKE_AUTO_BEGIN=1 tools/run_godot.sh --path . res://scenes/TestScenario.tscn
# or
tools/eoa_play_f5_smoke_auto_begin.sh
```

Watch `godot.log` for `EOA_SMOKE_AUTO_BEGIN who=title.apply_smoke_auto_begin` then `LivingTitleBoot: live Begin`, then `EOA_SMOKE_ADVANCE_PAST_PLUS6 who=tm.softpipe_catchup` and `tm.apply_smoke_advance_past_plus6` with `past7=true` **and** `window_stay=1` **and** `catchup=1` (chunked live path; on-screen date past 7 Jan), then **`EOA_SMOKE_STAYALIVE` `no_quit=1` `window_alive=1`** (window remains for Search Köln → Go → spine), then **`EOA_SMOKE_SEARCH_CHROME` + `EOA_SMOKE_SEARCH_CHROME_PIXEL` `on_screen=1` `in_bar=1` `live=1` `sticky=1`** including **`who=TestRunner.layout_settle`** after More+/Steel/Al reflow (first-paint live=1 alone is FAIL if chrome vanishes). Search LineEdit+Go must stay **pixel-visible and focusable** on the TopInfoBar right strip through resource-strip settle (log flags alone are not enough). After Search+Go, **Build Road Spine** must toast + show **Building…** (disabled) and `EOA_SMOKE_SPINE_START visible=1 armed=1`; Köln panel shows progress/ETA (`EOA_SMOKE_SPINE_PROGRESS`); corridor draws **queued → construction → built** (`EOA_SMOKE_SPINE_STATE`); complete logs `EOA_SMOKE_SPINE_COMPLETE` and RoadLayer Bonn–Köln–Leverkusen (Essen off-spine). Zoom is bracketed `EOA_ZOOM_BEGIN` / `EOA_ZOOM_END` (flushed) and must not rebuild the preview as Line2D. Any harness quit logs `EOA_HARNESS_QUIT` with a reason. Companion `EOA_SMOKE_ADVANCE_PAST_PLUS6` is default OFF and is implied by `EOA_SMOKE_AUTO_BEGIN=1` unless set to `0`. Live windowed smoke uses the chunked stepper with **softpipe catch-up when idle frames are scarce** and **stay-alive after past7** (never sync ×48 + combat flush; no unit-icon flood / 4x self-drive after past7). Do **not** score product Begin/Esc/clock PASS because the hatch or smoke advance fired. Default F5 (flags unset) keeps the living title and leaves the clock paused. Do not use `EOA_SKIP_TITLE` (skips clock/Search/spine arm). After the press, windowed xvfb `tools/eoa_ix1_spine_frame_guard.sh` must launch **the same way Play does** (`eoa_play_f5_smoke_auto_begin.sh`) and deliver a real viewport mouse event to Build Road Spine (not the spine helper/API). It must log `EOA_SMOKE_FRAME_GUARD frames=… rss_mb=… PASS` (frames keep advancing, sidecar RSS < 3 GB for 60 s; toast + Building… visible after press; `LeaderEventUI._trim_live_f5_toast_stack` must `remove_child` not spin on `queue_free`; not the product Play path). Headless: `HeadlessIx1LivingTitleEscBeginTest` + `HeadlessIx1RoadSpineDayTickTest` + `HeadlessIx1RoadSpineCompleteTest` + `HeadlessIx1SearchGoInspectorTest` + `test_ix1_road_spine_product`. Dig2/G PARKED.

### RH-1 hide resource glyphs except F9 (draft HOLD)

Political / diplomacy / other mapmodes must not stamp coal/oil/etc. glyphs. `InfrastructureOverlayLayer.show_resource_icons` defaults false; `set_map_mode_for_glyphs` is true only for `resources`. `MapRenderer.set_map_mode` + boot init call that hook. Current icon art is unchanged.

```bash
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRh1ResourceGlyphMapModeTest.gd
tools/eoa_rh1_pixel_guard.sh
python3 -m unittest tools.map_generation.tests.test_resource_icon_lod tools.map_generation.tests.test_map_resources_mapmode_product -v
```

On `tools/eoa_full_test_gates.sh` (`--quick` has the py needles; full has headless + xvfb). Headless `HeadlessRh1ResourceGlyphMapModeTest` **RESULT=PASS** (failures=0): default/political/diplomacy/other `show_resource_icons=false`; resources true; switch-back false. xvfb `tools/eoa_rh1_pixel_guard.sh` **RESULT=PASS** at zoom **0.638** over Essen (`political_hits=907` / `resources_hits=1252` / `back_hits=907`, icons false/true/false; wrapper peak **2030.0 MB**). Label **NOT live Play**. Peak RSS < 3 GB. Merge **HOLD**.

### FAC-1a airfield facility icons (L1–L4, draft HOLD)

Default F5 board is **`world_accurate`**. Four Rhineland airfields seed through `project_sites.json` → `ScenarioLoader.apply_seeded_special_sites_to_provinces` so `Province.special_sites` has real `SpecialSite` AIRFIELD rows. **FIX #3 reseed (never renumbered):** Borken `710430` L1, Warendorf `710434` L2, Oberbergischer Kreis `710423` L3, Siegen-Wittgenstein `710451` L4. Cannot-fit: Neuwied `710460`, Viersen `710414`, Hunsrück `710464`, Kreuznach `710457`. Same IDs on `provinces_pilot_europe_nuts3`. New `FacilityIconLayer` (`_draw` + `draw_texture_rect` + `draw_circle` badge disc; no Line2D / per-icon nodes). World-space **polylabel** interior anchors precomputed on rebuild (JSON + GDScript). Cluster + hysteresis when screen rects collide. Badges **16px** with dark disc. Close icons grow to **32px** at zoom ≥2.0. `show_facilities` defaults **ON**; **P** toggles on the layer (MapRenderer input untouched). Hidden below `MapZoomLOD.site_marker_min_zoom_for_board` (0.62 on the default board). Hidden in F9 resources. Old `rebuild_sites_layer` stays default-off. Damaged is a data flag (intact art + TODO). `set_map_mode` RH-1 glyph lines **untouched**.

```bash
python3 -m unittest tools.map_generation.tests.test_fac1a_airfield_icons -v
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFac1aAirfieldIconTest.gd
tools/eoa_fac1a_pixel_guard.sh
```

xvfb screenshots go to `/opt/cursor/artifacts/fac1a/`, `/opt/cursor/artifacts/fac1a_fix2/`, `/opt/cursor/artifacts/fac1a_fix2b/`, `/opt/cursor/artifacts/fac1a_fix2c/`, `/opt/cursor/artifacts/fac1a_fix3/`, and `/opt/cursor/artifacts/fac1a_fix4/` and are **NOT live Play**. Peak RSS must stay under 3 GB (isolated process tree — do not sum leftover Godot). Merge **HOLD**.

**FIX #4 (Play MIXED `76fb4808`):** click ownership + badge-in-footprint + cluster digit + lone min size + split guard 1.53. Seeds unchanged. Isolated keep-green recorded after the xvfb run.

**FIX #3 (Play MIXED `234e12b8`):** Rhine/spine/border clearance + cluster L4 tag. Split expected ~1.59. Isolated keep-green (`637ca02e`):

| gate | kind | result | peak MB isolated |
|---|---|---|---|
| py_fac1a | py | PASS | 1.9 |
| hd_fac1a | headless | PASS (L4 tag, 710430/434/423/451) | 1194.1 |
| xvfb_fac1a | xvfb | PASS clearance 0.65–2.27 · own=0 · cluster L4 count=2 · split 1.59 · occl=0.000 · rx1 0.843/0.843 | **2056.6** |
| xvfb_rx1 ON / OFF | xvfb | PASS mid_river **0.749 / 0.749** close 0.775 / 0.775 spine 1.000 | **2046.7 / 2050.0** |
| xvfb_rt1_seeded | xvfb | PASS | **2067.6** |
| py_ix1 | py | PASS | 54.7 |
| hd_mv1 / hd_mv1b / hd_rh1 | headless | PASS | 1193.9 / 1193.9 / 1193.8 |
| hd_ix1_* (6) | headless | PASS | ~1194 |
| hd_rx1_* (4) | headless | PASS | ~1194 |
| hd_rt1_* (3) | headless | PASS | ~1194 |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | 2063.3 / 2067.3 / 2063.2 |
| xvfb_rt1_live_look | xvfb | PASS | 2064.4 |

Screenshots FIX #3 (xvfb **NOT live Play**): `/opt/cursor/artifacts/fac1a_fix3/01_operational_z1.30_rhineland_NOT_live_play.png`, `02_mid_z0.99_cluster_tag_NOT_live_play.png`, `03_close_koln_bonn_z2.25_counter_NOT_live_play.png`, `04_split_z1.59_NOT_live_play.png`, `05_l1_z0.92_NOT_live_play.png`, `05_l1_z0.98_NOT_live_play.png`.

**FIX #1 occlusion (A/B/C prove, xvfb ≠ live Play):** icons sat on Bonn–Köln–Lev centroids (gold spine + Rhine). Same commands:

| | RX-1 `mid_river` | RT-1 `s1_gold_cover` |
|---|---|---|
| (a) base `8b7e46de` | **0.749 PASS** | **1.000 PASS** |
| (b) tip ON | **0.653 FAIL** | **0.556 FAIL** |
| (c) tip OFF | **0.749 PASS** | **1.000 PASS** |

Fix: landward screen-space offset (28px, east of the corridor) in `_draw` only — not under fills, not a threshold weaken, not a guard disable. Headless **RESULT=PASS** (offset asserted). Post-offset seeded xvfb (same thresholds, icons ON): RX-1 `mid_river=0.749` / spine cover `1.000` **PASS** (isolated peak **2046.7 MB**); RT-1 `s1_gold_cover=1.000` **PASS** (2067.8 MB). Sequential keep-green first marked RX-1 FAIL at 4446.3 MB because the sampler summed leftover Godot; isolated tree RSS is under 3 GB.

**Keep-green after FIX #1** (xvfb ≠ live Play; `py_eoa_quick` map_qc FAIL is pre-existing on base `8b7e46de`, Pillow):

| gate | kind | result | peak MB |
|---|---|---|---|
| py_fac1a / py_ix1_rx1_march_resource | py | PASS | 2.0 / 58.3 |
| py_eoa_quick | py | FAIL (base map_qc) | 100.3 |
| hd_fac1a / hd_mv1 / hd_mv1b | headless | PASS | 2388 / 2388 / 2388 |
| hd_ix1 (6) / hd_rx1 (4) / hd_rt1 (3) / hd_rh1 | headless | PASS | ~2388 |
| xvfb_fac1a | xvfb | PASS mid=4 close=4 out=4 res=4 back=4 | 2061.3 |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | 2065 / 2066 / 2066 |
| xvfb_rx1_seeded | xvfb | PASS mid_river=0.749 spine=1.000 | **2046.7** isolated |
| xvfb_rt1_seeded | xvfb | PASS s1_gold_cover=1.000 | 2067.8 |
| xvfb_rt1_live_look | xvfb | PASS mesh_frac=0.00078 gold_w=14 | 2238.5 |

Screenshots FIX #1 (NOT live Play): `/opt/cursor/artifacts/fac1a/fac1a_political_mid_NOT_live_play.png`, `fac1a_political_close_NOT_live_play.png`, `fac1a_zoomed_out_NOT_live_play.png`, `fac1a_resources_F9_NOT_live_play.png`, `fac1a_political_back_NOT_live_play.png`.

**FIX #2c:** same seeds; cluster marker sits on the highest-level member interior (nudged inside that province if the larger rect still hits Rhine/spine/star/counter; AABB-clear of sibling isolates). Occlusion samples cluster markers at 0.70 / 0.99 / 1.30. RX-1 mid_river ON vs OFF must match within 0.02. Close 03 is Köln Play-style with the unit counter drawn. Composites `/opt/cursor/artifacts/fac1a_fix2c/` — **NOT live Play**.

Keep-green after FIX #2c `86bdd723` (isolated process-tree RSS via `pgrep -P` only; xvfb ≠ live Play; `py_eoa_quick` map_qc FAIL is pre-existing on base `8b7e46de`, Pillow):

| gate | kind | result | peak MB |
|---|---|---|---|
| py_fac1a / py_ix1_rx1_march_resource | py | PASS | 1.9 / 61.5 |
| py_eoa_quick | py | FAIL (base map_qc) | — |
| hd_fac1a / hd_mv1 / hd_mv1b | headless | PASS | 1194 / 1194 / 1194 |
| hd_ix1 (6) / hd_rx1 (4) / hd_rt1 (3) / hd_rh1 | headless | PASS | ~1194 isolated |
| xvfb_fac1a | xvfb | PASS cluster_mid count=3 L4 · split 1.9/2.27 · counter_drawn · counter_clear Neuwied · occl=0.000 · overlap=0 · own=0 · rx1_mid ON/OFF 0.843/0.843 | **2056.4** isolated |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | 2065 / 2061 / 2061 |
| xvfb_rx1_seeded | xvfb | PASS mid_river=0.664 close_river=0.749 spine=1.000 (later proved FAC-1a vs OFF/base 0.749) | **2046.7** isolated |
| xvfb_rt1_seeded | xvfb | PASS s1_gold_cover=1.000 | 2071.0 |
| xvfb_rt1_live_look | xvfb | PASS mesh_frac=0.00079 gold_w=14 | 2061.2 |

Screenshots FIX #2c (xvfb **NOT live Play**): `/opt/cursor/artifacts/fac1a_fix2c/01_operational_z1.30_rhineland_NOT_live_play.png`, `02_mid_z0.99_cluster_NOT_live_play.png` (3-cluster off the Rhine + Viersen isolate), `03_close_koln_bonn_z2.27_counter_NOT_live_play.png` (Neuwied beside drawn Köln counter).

Keep-green after FIX #2c Rhine-host `1d7e3219` (isolated `pgrep -P` tree RSS; xvfb ≠ live Play). Seeded RX-1 on `beb3ed09` ON 0.664 vs OFF/base 0.749 proved FAC-1a (Neuwied L4 on the real course). Host prefers ≥22 world from `Rx1RhineCrossing.course_points()` (Ober L3).

| gate | kind | result | peak MB |
|---|---|---|---|
| py_fac1a | py | PASS | 1.9 |
| hd_fac1a | headless | PASS | 1193.9 |
| xvfb_fac1a | xvfb | PASS cluster_mid · split_close · counter_drawn/clear · occl=0.000 · overlap_z0.70=0 · rx1_mid 0.843/0.843 | **2056.9** isolated |
| xvfb_rx1_seeded ON | xvfb | PASS mid_river=0.749 close_river=0.749 spine=1.000 | **2050.0** isolated |
| xvfb_rx1_seeded OFF | xvfb | PASS mid_river=0.749 close_river=0.775 spine=1.000 | **2050.0** isolated |
| xvfb_rx1_seeded base `8b7e46de` | xvfb | PASS mid_river=0.749 close_river=0.775 spine=1.000 | **2045.0** isolated |

**FIX #2b:** same mechanics; Rhineland-only reseed so Play can see cluster-split and counter clearance. Viersen `710414` L1, Rhein-Hunsrück-Kreis `710464` L2, Oberbergischer Kreis `710423` L3, Neuwied `710460` L4 (Bonn-adjacent, LUX-disk-safe — Ahrweiler `710455` interiors sit inside the LUX capital-star disk and snapped into the Köln counter). Cluster is Neuwied–Ober (live world ~28). xvfb asserts cluster at 0.99 (count=3, max L4), split at ≥1.9, Neuwied vs Köln counter at 2.27, occlusion ≤5%, click-own all 4. Composites `/opt/cursor/artifacts/fac1a_fix2b/` — **NOT live Play**.

Keep-green after FIX #2b Neuwied reseed `e32095ed` (isolated process-tree RSS via `pgrep -P` only; xvfb ≠ live Play; `py_eoa_quick` map_qc FAIL is pre-existing on base `8b7e46de`, Pillow):

| gate | kind | result | peak MB |
|---|---|---|---|
| py_fac1a / py_ix1_rx1_march_resource | py | PASS | 1.9 / 54.7 |
| py_eoa_quick | py | FAIL (base map_qc) | — |
| hd_fac1a / hd_mv1 / hd_mv1b | headless | PASS | 1194 / 1194 / 1194 |
| hd_ix1 (6) / hd_rx1 (4) / hd_rt1 (3) / hd_rh1 | headless | PASS | ~1194–1198 isolated |
| xvfb_fac1a | xvfb | PASS cluster_mid count=3 L4 · split 1.9/2.27 · counter_clear Neuwied · occl=0.000 · own=0 | **2059.6** isolated |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | 2158 / 2062 / 2064 |
| xvfb_rx1_seeded | xvfb | PASS mid_river=0.631 spine=1.000 | **2043.3** isolated |
| xvfb_rt1_seeded | xvfb | PASS s1_gold_cover=1.000 | 2060.2 |
| xvfb_rt1_live_look | xvfb | PASS mesh_frac=0.00078 gold_w=14 | 2065.9 |

Screenshots FIX #2b (xvfb **NOT live Play**): `/opt/cursor/artifacts/fac1a_fix2b/01_operational_z1.30_rhineland_NOT_live_play.png`, `02_mid_z0.99_cluster_NOT_live_play.png` (3-cluster + Viersen), `03_close_koln_bonn_z2.27_counter_NOT_live_play.png` (Neuwied beside Köln counter).

**FIX #2 (live Play MIXED look on `2e5bc186`):** 28px screen offset + adjacent NUTS3 centroids clumped four icons (~40px), mid badges ~11px, Köln unit buried all four, Neuss sat on Rhine ≥1.9 / gold ≥1.35, Köln icon click marched to Rheinisch-Bergischer Kreis. Drop the screen offset. Interior polylabel + reseed (later corrected by FIX #2b). Cluster+hysteresis. 16px outlined badges. 32px at zoom ≥2.0. RT-1 `s1_gold_cover=1.000` false-passed because S1 walks Bonn–Köln–Lev **centroids only** — Neuss / Leverkusen cap were never sampled. New FAC-1a occlusion (ON vs OFF gold/river ≤5% at 1.35/1.9/2.3, anchors + spine walk including Neuss), no-overlap (0.70/0.99/1.30/1.90/2.30 + Köln counter), click-own (`get_province_at_world_pos` at icon center), badge ≥16px. RX-1/RT-1 thresholds **untouched**. Input / `set_map_mode` / label LOD / RoadTierVisual / Rhine / MapZoomLOD **untouched**.

Keep-green after FIX #2 (isolated process-tree RSS; xvfb ≠ live Play; `py_eoa_quick` map_qc FAIL is pre-existing on base `8b7e46de`, Pillow):

| gate | kind | result | peak MB |
|---|---|---|---|
| py_fac1a / py_ix1_rx1_march_resource | py | PASS | 2.1 / 76.6 |
| py_eoa_quick | py | FAIL (base map_qc) | 106.3 |
| hd_fac1a / hd_mv1 / hd_mv1b | headless | PASS | 1194 / 1194 / 1194 |
| hd_ix1 (6) / hd_rx1 (4) / hd_rt1 (3) / hd_rh1 | headless | PASS | ~1194 isolated |
| xvfb_fac1a | xvfb | PASS mid=4 close=4 out=1 res=0 back=4 badge=16 occl=0.000 overlap=0 own=0 | **2063.3** isolated |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | 2060 / 2062 / 2061 |
| xvfb_rx1_seeded | xvfb | PASS mid_river=0.749 spine=1.000 | **2046.7** isolated |
| xvfb_rt1_seeded | xvfb | PASS s1_gold_cover=1.000 | 2062.0 |
| xvfb_rt1_live_look | xvfb | PASS mesh_frac=0.00079 gold_w=14 | 2098.7 |

Screenshots FIX #2 (xvfb **NOT live Play**, matching Play composites): `/opt/cursor/artifacts/fac1a_fix2/01_operational_z1.30_all4_airfields_NOT_live_play.png`, `02_mid_z0.99_badges_or_cluster_NOT_live_play.png`, `03_close_koln_z2.27_counters_NOT_live_play.png`.

### MV-1 move ETA preview (gameplay UI, draft HOLD)

With a unit selected, hovering own/controlled land shows a dimmer dashed `MarchPreviewLine` plus a cursor chip (`N hops · arrives in D days · <Province>` or `Can't march · <reason>`) **before click**. `FormationMovement.preview_own_land_march` is the pure SOT (same BFS / `_hop_cost_into` / IX-1 road + RX-1 Rhine multipliers); `enqueue_own_land_march` calls it then writes `_orders`. Hover BFS runs on province **change only** (cached by fid/dest/day). Headless: `HeadlessMv1MarchPreviewTest` **RESULT=PASS** (preview==commit path + calendar_days; no order after preview; reasons; spine ETA < same-length off-road; NUTS3 Bonn/Köln/Leverkusen + Neuss–Mettmann). Windowed xvfb `tools/eoa_mv1_pixel_guard.sh` at **1600×900** **RESULT=PASS** (line on hover, gone after unhover; Köln mid-zoom lock; wrapper peak ~2029 MB) — **not live Play** (llvmpipe/OpenGL can miss Vulkan). **FIX #1 (Play live FAIL `388c5828`):** docked unit card must not wipe the preview (`_update_spatial_hover` still runs `_refresh_march_preview_for_hover` when the card is up and the mouse is on the map; tooltip only is suppressed). Still map click with the card up must not latch as a drag (`_clear_left_slop_after_still_click` + leftover-origin live-slop gate). New xvfb guard `tools/eoa_mv1_card_up_input_guard.sh` selects by simulated real mouse at the counter (never assigns `selected_formation_id`), asserts card + chip `2 hops · arrives in 3 days · Leverkusen`, still-click commit `has_march` with preview==commit, and a real drag pans without committing. **FIX #2 (Play live MIXED `8089bbd4`):** leftover `_begin` early-return on `dragged and not _left_ready_for_still_click` (and stuck `_left_btn_down` after Close) re-latched every click after inspector/Open-fight Close — a real MouseButton press always resets left-gesture state; those panels' open/close also reset. Input model: plain click on a different own counter switches; plain click on empty own land / the selected unit's own chip area commits (or no-op on own province); Ctrl stays assault/Open fight. Peak slop from the press origin latches dragged even if release returns near origin. Guard covers inspector + Open-fight open/close, A→B switch, adjacent-in-chip commit, return-to-origin drag, 5 still clicks after drag. Map drawing layers (roads, borders, labels, `InfrastructureOverlayLayer`, `RoadTierVisual`, `MapZoomLOD`, `BorderLayer`) are **untouched**. Merge **HOLD** until live Play. Ctrl+click assault stays assault (not switch).

**MV-1b (input leftovers, draft HOLD):** air/foreign-fleet chip must not steal a still click while own land is selected and the march chip shows `N hops` — preview==commit; `_try_open_unit_at_world` is player-tag disk-only (foreign air/fleet falls through; own air/fleet still opens when nothing is selected). Province-panel Close and unit-card Close block edge-pan via `MapViewInput.control_or_ancestor_blocks_edge_pan` (InfoPanel / UnitDetailPopup / `unit_card_dock` / `blocks_edge_pan` meta; camera code untouched). **FIX #1 (Play live MIXED):** capital-star branch ran before `_mv1_selected_own_land_ready_to_commit` and cleared the selection / opened Berlin inspector over a valid N-hops preview. `mv1_commit` is computed once after the land-counter switch; when true the star, `_try_open_unit_at_world`, living-title, and inspector paths are skipped so the click enqueues the preview dest. Item 2 included: empty-select own air/fleet/space disk (`_try_open_unit_at_world`) runs before `_try_open_land_unit_at_world` in `_unhandled_input` and `_try_open_land_chip_from_input` (disk only; CHROME_SPILL / nearest-land fallback untouched). Headless: `HeadlessMv1bInputGateTest` + MV-1 source needles (player-tag before `_select_map_unit`; `mv1_commit` star skip; air disk before land fallback; CHROME_SPILL_WORLD stays 340). Windowed xvfb `tools/eoa_mv1_card_up_input_guard.sh` adds real-mouse (a) land selected + air/FRA chips over Leverkusen preview → commit, selection stays land; (b) nothing selected + FRA fleet click does not select FRA; (c) own air chip still opens; (d) rest 1s on inspector Close then unit-card Close, camera unchanged / `edge_pan_blocked_by_gui` true; FIX #1 capital+air: own air on Berlin, land selected, N-hops chip, still click on the star commits Berlin and keeps selection (no inspector); nothing selected, star still inspects; empty-select air disk opens the air wing; land disk off the air chip first-selects land — **not live Play**. Drawing layers / `set_map_mode` / `_render_provinces_finish` / fallback **untouched**. Merge **HOLD**.

**Backlog (no code this slice):** `_try_open_land_unit_at_world` nearest-player-land-icon fallback can arm a GER division from a French-land click (Play live: `any=FRA_formation_6 fo=GER_formation_7`). Pre-existing; do not change the fallback here. Item 2 (Attack-from-X vs Close overlap) and item 4 (fallback reach) are out of scope.

### RT-1 Readable road tiers (intact, visual only, draft HOLD)

Pure helpers in `scripts/map/RoadTierVisual.gd` (FIX #2 trunk; FIX #3 12 px non-AA highway quads + Köln label). Headless: `HeadlessRt1RoadTierForEdgeTest` (1936 3/6/9 + eras + explicit⇒highway + Europe LOD + trunk forest / 0 triangles + mid highway + Köln label) + `HeadlessRt1RoadEdgeFilterTest` (Bonn–Köln / Köln–Leverkusen must-draw; Köln–Essen / Köln–Düren must-not) + `HeadlessRt1RoadNoRebuildTest` (zoom/pan 0 rebuilds; one `infrastructure` notify → +1). Windowed seeded `tools/eoa_rt1_pixel_guard.sh` (3×3 + S1/S2) uses the player camera path (no `lock_pixel_guard_camera`). Windowed **live-look** `tools/eoa_rt1_live_look_guard.sh` does **not** seed infra: Europe Home → Search/Go Köln → `_zoom_toward_mouse` at **1600×900**; triangle/mesh density; **highway width > paved** at mid+close; **mid gold ≥ 1.8× highway** (close gold 16/20 unchanged); sage-web frac ≤ 0.035 (no `5c60f366` pale-green carpet). `ProvEdge_` hide is **not** in this slice (borders needed for pick; tan cells backlog). S2 Bonn/Köln/Leverkusen at mid+close. xvfb ≠ product Play. Live −12% road move bonus is unchanged.

### RX-1 Rhine Crossing (Phase B draft)

Pure product `test_rx1_rhine_crossing_product` is on `--quick`. Headless: `HeadlessRx1RhineCrossingTest` (edge penalties, shared-border guard, Build Bridge complete) + `HeadlessRx1RhineLiveStayAliveTickTest` (FIX3 calendar tick: 0% → >0 in ~5d → COMPLETE via `advance_real_time`) + `HeadlessRx1RhineVisibilityTest` (FIX1: Rhine/road z > DemoUnitIcon 28; spine chrome absent on Neuss). Windowed smoke `tools/eoa_rx1_bridge_live_progress_guard.sh` sets `EOA_SMOKE_RX1_LIVE_PROGRESS=1` and presses **Build Bridge** on Neuss `710413`. The smoke harness is **not** the product. IX-1 spine tests stay green and unchanged. `run_godot.sh` one-time `--import` when the class cache lacks `Rx1RhineCrossing`. 
