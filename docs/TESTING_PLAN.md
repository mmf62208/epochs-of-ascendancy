# Testing Plan — Epochs of Ascendancy

## Goals

- Ensure new systems (especially Time + Daily Effects) work reliably.
- Catch regressions when adding new features.
- Make it easy to verify that daily/monthly/yearly systems behave correctly.

## Recommended Testing Approach

### 0. PROD-1 Prod button (top info bar)

Live 1280×800 after Begin: leftover MapRenderer left-up swallow used to eat Prod (`ACTION_MODE_BUTTON_RELEASE`). Guard clicks the real ProductionButton through `Input.parse_input_event` (not `_on_production_pressed`), asserts the production screen is visible, then Close→Prod opens it again.

```bash
tools/run_godot.sh --headless --path . --resolution 1280x800 \
  -s res://scripts/core/HeadlessProd1ButtonOpenTest.gd
```

Wired as `launch_prod1_button_open` on the full gate script. `--quick` stays the same 14 known `unit_board_play_path` reds.

### 0b. UI-POLISH-1 Agents Close / Space × / Trade signal

Playtester 1280×800 after Begin: Agents Close sat off the right edge (1440-wide panel, left/top clamp only). Space title × used button-up so leftover MapRenderer left-up swallow ate the first click (Close already worked). Opening Trade connected `deal_rejected` twice (copy-paste under `trade_flow_created`). Agents panel now clamps into the viewport; Space × is `ACTION_MODE_BUTTON_PRESS`; Trade guards `is_connected`.

```bash
tools/run_godot.sh --headless --path . --resolution 1280x800 \
  -s res://scripts/core/HeadlessUiPolish1Test.gd
```

Wired as `launch_ui_polish1` on the full gate script (not `--quick`).

FIX #1: Space close-release swallow arms only while LMB is down (`Input.is_mouse_button_pressed`), drops on a new left press without consuming it, and expires at ~250 ms. Frame × (`close_requested` after release) and keyboard Close must not eat the next button/map click. Guard **RESULT=PASS** (failures=0): frame × then unrelated button fired; keyboard Close then click fired; map press-release after Space close selected. `HeadlessProd1ButtonOpenTest` still **PASS**.

FIX #2: Agents Close must be fully visible/clickable (TitleBar after MarginContainer, content clipped to 1248×728, title vs Show: rects do not intersect). Esc closes Space; Esc with nothing open still reaches Command Center. Shared `scripts/ui/CloseReleaseSwallow.gd` on every press-mode Close (Prod, Leaders, Agents, Space). Held-click cases use press → 50–100 ms wait → release; map stand-in counts unhandled left-ups (0 after Close, 1 on empty map). Mutant: disconnect swallow on Prod held-close → 1 map mouse-up. Guard **RESULT=PASS** (failures=0). `HeadlessProd1ButtonOpenTest` **PASS**. `HeadlessUi1LeadersEdgePanMarchTest` **PASS**. `--quick` same 14 known reds. map_qc NE **0.9853**. 0 SCRIPT ERROR.

### 0c. MAIN-FIX-1 Prod Esc + false capture notice

Play MIXED on main `d00dc8ed`: Esc with Production open opened Command Center on top of Prod (Leaders/Agents/Space already consumed Esc after #114). Diplomatic GER→POL Declare toasted `Province captured · POL vs GER at Słupski` with no owner change.

**Esc:** `MapRenderer._handle_escape_key` dismisses `ProductionAssignmentScreen` (via `close_screen`) before `_esc_open_command_center`. Idle Esc still opens Command Center.

**Capture (FIX #1):** Live toast at Elbląski was a **true** POL empty-hex of GER-owned 1936 land (`711086`, Polish name + POL core). AI empty-hex vs the human player is **not** skipped. Capture toasts log `MAIN_FIX1_CAPTURE_SRC`, fire only on a real owner flip, and read `Poland captured Elbląski from Germany (undefended)`. Peace sheet buttons use Retrowave press-mode chrome, apply, log `MAIN_FIX1_PEACE_BTN`, and close.

```bash
tools/run_godot.sh --headless --path . --resolution 1280x800 \
  -s res://scripts/core/HeadlessMainFix1ProdEscTest.gd
tools/run_godot.sh --headless --path . --resolution 1280x800 \
  -s res://scripts/core/HeadlessCampaignLoop1DeclareClickTest.gd
tools/run_godot.sh --headless --path . --resolution 1280x800 \
  -s res://scripts/core/HeadlessMainFix1PeaceClickTest.gd
tools/eoa_main_fix1_declare_toast_guard.sh
# Play hooks (off by default):
#   EOA_MAIN_FIX1_FORCE_CAPTURE=1 tools/run_godot.sh --path . res://scenes/TestScenario.tscn
#   EOA_MAIN_FIX1_PEACE_HOLD_S=600 tools/run_godot.sh --path . res://scenes/TestScenario.tscn
```

Wired as `launch_main_fix1_prod_esc`, `launch_main_fix1_peace_click`, `launch_main_fix1_declare_toast` on the full gate script (not `--quick`). `--quick` stays the same 14 known `unit_board_play_path` reds.

FIX #1: toast wording + AI empty-hex restored. Work is on `grok/main-fix-1` (PR #116). PR #117 closed without merge. ProdEsc/PeaceClick/DeclareClick/WarGate/UI-POLISH-1/PROD-1 **PASS** (0 SCRIPT ERROR). xvfb DeclareToast **PASS** (on declare 0 toasts; then 3 empty-hex captures, 3 correctly worded toasts, 3 owner flips). `--quick` `FAILED (failures=14)`. map_qc NE **0.9853**.

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
tools/run_godot.sh --headless --path . --resolution 1280x740 -s res://scripts/core/HeadlessFac1aPanIconsTest.gd
tools/run_godot.sh --headless --path . --resolution 1280x740 -s res://scripts/core/HeadlessFac1aHoverCacheTest.gd
tools/eoa_fac1a_pixel_guard.sh
```

**PERF-4 daily sim-tick hitch:** TimeManager profiles each `game_day_advanced` listener and day_ai / day_battles steps. `GameData.get_peace_state` must not `duplicate(true)` (use `peek_peace_state`; snapshot via `get_peace_state_copy`). Owner lists use `_ensure_owner_index`. Headless `HeadlessPerf4DailySimTickTest`: **FAIL on main** `425b4448` (deepcopy / no timers / no profile history, 7d wall 1396.7ms) · **PASS after merge onto `61a80433`** (worst phase 20.5ms day_ai, 7d wall 72.6ms, seed 193601 infra decisions identical). **FIX #1:** live Play of `289268ed` still 2.0–2.4 s because `_maybe_run_interactive_multi_ai` rebuilt the supply network (`set_player_depot(1)`) and re-entered full `advance_supply_day` + per-country line/region walks. Soft tick uses the F5 light path and does not stamp a dummy depot; production shares a per-day cache. Guards `HeadlessPerf4InteractiveMultiAiTest` + `HeadlessPerf4LiveMultiAiDayTest` **FAIL on main `61a80433` and `289268ed`** · **PASS** after FIX #1 tip `57a8c7ca` (live-equivalent 5d wall **42.6 ms**, worst day_ai **9.1 ms**, multi_ai **0.8 ms**; stripped 7d **36.4 ms**; Interactive 7d **70.7 ms**). **FIX #2:** capture of hub `710160` / depot `710161` retags FRA without a daily `build_network`. **FIX #3:** capture drops touching routes only (single **0.0 ms**, ten **0.0 ms**; **FAIL on `2d930483`** 1.4–2.7 s / 21 s); depot add/remove one-hub **0.1 / 0.1 ms**; daily listener restored to main's light path (exactly one full supply day; listener **0.8 ms**); peace annexation notifies supply. Infra picker kept (seed 193601 identical). Live apply_supply **83.5 ms**, worst day_ai **86.2 ms**. Daily 10/10 PASS. **FIX #4:** dest cap **N=24** + **80 ms/frame** plan slice (live recovery **187.6 ms**; remaining dests drain the same calendar day). **FAIL on `5ca1d0b5`** budget=2 / 7-day dark dests / refill-off still passed. Dijkstra heap + pred-pid tie-break: ten-capture and annex paths **mismatch=0** vs a forced rebuild. Infra/dev complete recalculates that hub (GER 55900→56600; day-40 capitals **8/8**). Spike cause: sort-every-pop Dijkstra (unbudgeted flush **883 ms**, `rebuilds=0`, not GC). **FIX #5:** Ship gate of `a8434b02` livelocked: flush re-dropped dirty pids every call so depot add `710314` / recapture never converged (987 plans / 400 frames; live 4x 2/24 routes). Deduped FIFO, keep-until-swap, predictive **40 ms** slice, relations cache clear, GameData infra notify. Live harness is behaviour (plans/frame, missing, dirty drain, zero re-drops) — not a 200 ms wall. Mutants: re-drop restored / slice removed / no old-route keep. Depot add **23 frames / 24 plans / redrops=0**; ten-capture 1x and 4x **20 frames**; paths **mismatch=0**; day-40 **8/8**. **FIX #6:** Ship gate of `34d76f21` NOT READY — recapture/access pathdiff 24/21, tautological redrop counters, slice/FIFO/infra mutants survived, 25 ms ten-capture flake. Friendly gain enqueues all 24 dests; redrop counters increment; slice estimate seam; FIFO order; GameData settlement-improve capdiff=[]; ten-capture behaviour count; dayroll+capture <200 ms. Tip **PASS**: recapture `710314` pathdiff=0; access grant/revoke pathdiff=0; dayroll+capture **99.7 ms**; GameData **56600→57300 capdiff=[]**. **FIX #7:** Ship gate of `42446ffc` NOT READY — bar 2 (dayroll+event same frame under 300 ms); relations/access/depot still planned 1–2 dests on the roll frame. Dayroll+event plans **0** dests; relations/depot defer like the day-roll frame; W2 player-scoped enqueue; redrop increment is a forced-drop flush seam; depot add whose touching set <24 must enqueue all 24; CA bar **300 ms** + dayroll+access/recapture. Own-share timer is event + `advance_supply_day` (theater/multi_ai out of #88). Tip **PASS** failures=0: dayroll+capture **105.2 ms** < 300; own-share access **86.8** / recapture **92.7** / depot **90.0** / annex **97.1** / revoke **88.1** / capture **95.0**, all **plans=0 pathdiff=0**; depot touching=2 queued=24; flush_redrop **189→190**. Daily 7d wall **73.5 ms**, worst day_ai **20.2 ms**, seed 193601 identical. `--quick` same 14 known `unit_board_play_path` reds. **FIX #8:** leftover FIFO dests planned 1 dest on the roll frame (SupplyManager `#8` `_process` before TimeManager / TopInfoBar). `_process` skips when the clock will cross midnight and `call_deferred`s the leftover refill after the roll. Tip **PASS** failures=0: **plans_on_roll empty_queue=0 leftover_queue=0 ×6** queue0=24; leftover drain 23 frames / 24 plans **pathdiff=0**; livelock prod **0→0** / mutant proof **0→24**; own-share 82.5–93.4 ms all **plans=0**; dayroll+capture **96.1 ms**. Mutants: `defer_process_off` / `defer_events_off` leftover 6/6 **plans_on_roll=1 FAIL**; flush re-drop `710314` livelock **1499→1523 FAIL**. Daily 7d wall **68.4 ms**, worst day_ai **16.4 ms**, seed 193601 identical. `--quick` same 14 known `unit_board_play_path` reds. Source-string checks that runtime already covers are gone. **FIX #9:** live leftover-queue **7 / plans_on_roll=1 on 3** (Home 4x drive2; deferred flush before TopInfoBar `_on_tick`). MUST3 **PASS**. Delete deferred flush + midnight guess. `_process` skips only when `is_tick_due_this_frame()` and `_clock_tick_would_roll_day()`. Headless TopInfoBar 4x leftover-queue **6 / plans_on_roll=0** (empty 0) pathdiff=0; event-frame leftover flush **0**; hour-20 tick-not-due planned **1**. Own-share 85.0–107.7 ms. Daily 7d wall **77.6 ms**, worst day_ai **20.9 ms**, seed 193601 identical. `--quick` same 14 known `unit_board_play_path` reds. Product `test_perf4_daily_sim_tick_product` on `--quick`. Title / Begin / sea-fleet / Home star / supply overlay / chips **unedited**. **FIX #10:** Ship gate of `c722a2c0` NOT READY — 6 of 7 leftover-queue rolls planned 1 (`is_tick_due_this_frame()` sampled before MapRenderer / TopInfoBar). Refill after the clock decision (`TopInfoBar` → `refill_after_clock`); no tick prediction. Scene-order test ×7 (MapRenderer burn + TopInfoBar, last_tick just under 1000 ms) **FAILS on `c722a2c0` (7/7 planned 1)** and **PASS** on the tip (`plans_on_roll=0` pathdiff=0). Order `sm_process` → `tib_clock` → `tib_skip_refill`. MUST3 **PASS** 0→0 / mutant 0→24. Event-frame leftover **0**. Hour-20 planned **1**. Daily 7d wall **70.5 ms**, worst day_ai **18.2 ms**, seed 193601 identical. **FIX #11:** Ship gate of `1cddb51c` NOT READY — live leftover-queue **7/7** planned 1. TM windowed backup (`_process` 1000 ms) rolled before TopInfoBar; `game_day_advanced` mark only in deferred `_flush_sim_events`. Mark at the calendar boundary (`_mark_calendar_day_roll` / `day_rolled_this_frame`); backup off while TIB last tick ≤ 2 s. Windowed-backup leftover test ×7 (backup + deferred day emit) **FAILS on `1cddb51c` (7/7 planned 1)** and **PASS** on the tip (`plans_on_roll=0` pathdiff=0, `tm_calendar_roll` → `tib_skip_refill` ×7). MUST3 **PASS** 0→0 / mutant 0→24. Event-frame leftover **0**. Hour-20 planned **1**. Daily 7d wall **79.8 ms**, worst day_ai **21.9 ms**, seed 193601 identical. Isolated `EOA_PERF4_WINDOWED_BACKUP_ONLY=1` is `launch_perf4_windowed_backup` on `eoa_full_test_gates.sh`.


```bash
python3 -m unittest tools.map_generation.tests.test_perf4_daily_sim_tick_product -v
EOA_DAY_TICK_PROFILE=1 tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessPerf4DailySimTickTest.gd
tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessPerf4InteractiveMultiAiTest.gd
tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd
```

**PERF-1 FIX #1 (pan icons):** `_process` still `queue_redraw`s on ≥8px pan so previously culled airfields appear. Clusters cache per `_markers_zoom`; `_build_markers` must not increment on pan. Headless `HeadlessFac1aPanIconsTest` **RESULT=PASS** (Home z=0.33, ≥1 screen-width pan, drawn>0, build count unchanged). MapRenderer fill-zoom fix kept. Camera / edge-pan / chip pick **unedited**.

**PERF-1b (hover cache):** `get_hit_rects_at_zoom` reuses `_last_markers` when zoom matches within 0.008 and the cache is clean; otherwise builds once and stores. `compute_markers_at_zoom` stays uncached. Headless `HeadlessFac1aHoverCacheTest` **RESULT=PASS**: N hovers at fixed zoom add 0 builds; zoom / data change updates clusters. Isolated keep-green **FAILS=0**. Camera / edge-pan / chip pick **unedited**. Evidence `docs/evidence/perf1b/`.

### PERF-3 supply overlay L toggle (draft HOLD)

L-on / L-off must not rebuild 3196 `SupplyOutline` + `SupplyOutlineGlow` Line2Ds. Rings are built once on `SupplyOutlineBatchLayer` (same `ProvinceMapVisuals.get_supply_outline_style` colors / widths / glow) and shown/hidden. Headless measures the **full** `_toggle_supply_overlay` path Play timed (3196 dummy land, 48-pt rings, **seeded glyph Labels + boot SupplyMapLayer**) at Home z0.318 and z0.760. Fails on main (L-off leaves rings up). Fails if L still restacks glyphs / re-enters `_setup_supply_layer` / recomputes roles after the first cache fill (the live ~4.5 s / ~1.6 s leftover on `936ee472`). Limit **1000 ms** each way (target <500 ms). FIX #1 evidence: Home **156.9 / 8.2 / 374.2 ms**, z0.760 **52.7 / 8.1 / 52.5 ms**, rebuilds stay 1, line2d=0, glyphs=0, setups=0, roles=1.

```bash
tools/run_godot.sh --headless --path . --resolution 1280x740 \
  -s res://scripts/core/HeadlessPerf3SupplyToggleTest.gd
```

Wired as `launch_perf3_supply_toggle` in `tools/eoa_full_test_gates.sh` (full path only). `--quick` is unchanged pure-python. Not live Play. Merge **HOLD**.

### PERF-5 legend day tick + supply overlay freshness (draft HOLD)

Off main `61a80433`. Tip `ae88fea5` PR **#90**. Two MapRenderer-only bugs: (a) L-on `_on_game_day_advanced_legend` mutated the legend StyleBox every day (theme + fit_content relayout); (b) PERF-3 cache reuse left stale rings after depot/capture because nothing called `set_routes` and `_supply_roles_cache` had no fingerprint. Fix: pulse via a sibling modulate overlay, per-day count cache, hint write-on-change, expiry restyle-only; overlay fingerprint poll + dirty pids + incremental `patch_items` (signals are accelerators only — #88 mutation paths emit nothing). Headless legend p95 **17.11** / worst **32.03** (ops 0/0/0); overlay B1/B2/B3 PASS; PERF-3 second L-on roles=1. Mutants A1–A6 B1–B8 FAIL by selection. Local #88 merge @ `34d76f21` overlay still PASS. Wired after `launch_perf3_supply_toggle`. `--quick` still the same 14 known `unit_board_play_path` reds. `HeadlessPerf3SupplyToggleTest` unedited. Not live Play. Merge **HOLD**.

```bash
tools/run_godot.sh --headless --path . --resolution 1280x740 \
  -s res://scripts/core/HeadlessPerf5LegendDayTickTest.gd
tools/run_godot.sh --headless --path . --resolution 1280x740 \
  -s res://scripts/core/HeadlessPerf5SupplyOverlayFreshTest.gd
```

### PERF-6 day-roll supply slices (draft HOLD, headless; live A/B pending)

Simulated M3 is local `eab3d0c9` (`cursor/m3-sim-88-89-90`: #88 `7529eac9`, #89 `6b1d9cb0`, #90 `2c68a67c`). `ac9926c5` is absent here and on GitHub. `origin/main` remains `61a80433`. Rebase onto the real M3 SHA when it lands. Interactive light sim queues the one full supply day; slices drain through `SupplyManager._process` / `refill_after_clock` at ≤20 ms, in order flush → generate → naval → fuel → air → shipping. Generate walks `depot_states` insertion order with a resumable cursor. A backup tick that would cross midnight finishes the open job on that non-roll frame. Paused frames do no slice work. Light production harvest stays on `day_n % 5 == 0`; reinforce moves to `day_n % 5 == 2`. Non-light callers still run `advance_supply_day` synchronously.

Measured soft-supply split on this machine (Home 1x, player GER, soft USA, 3196 depots), from `last_supply_day_profile`:

| section | ms |
|---|---:|
| total | 98.866 |
| flush | 0.004 |
| generate | 92.693 |
| naval | 3.455 |
| fuel | 2.448 |
| air | 0.043 |
| shipping | 0.040 |
| plans | 0 |
| rebuilds | 0 |

Generate is the dominant section (92.693 of 98.866 ms).

`HeadlessPerf6DayRollTest` **FAIL on M3 product** / **PASS on the tip**:

| check | M3 product | tip |
|---|---|---|
| queue | `queue_full_supply_day` missing | queued |
| 1× day_ai p95 / max | 107.1 / 112.0 | 12.1 / 14.4 |
| 4× day_ai p95 / max | 102.3 / 102.5 | 10.7 / 10.9 |
| slice max | 0.00 (no slicer) | 20.03 |
| listener max | 1.2 | 1.2 (1×) / 1.3 (4×) |
| unfinished rolls | 0 | 0 |
| depot equality | (queue missing; stagger saw 0 days) | diff none, 6 drains |
| production 10d | — | harvests 2, reinforces 2, diff none |
| production day 12 | — | harvests 2, reinforces 3, both false |
| pause mid-slice | — | phase 1 index 608, cursor held |
| catch-up | — | 7.79 ms, count 0→1 |
| roll-frame slice | — | 0.00 ms |

ProductionManager's listener on this board is about 1.2 ms. The roll-frame cost that moved is the supply day inside `day_ai`.

Mutants the behaviour test kills: (a) sync supply on the roll frame (M3 day_ai 107–112 vs tip 12–14); (b) unfinished at the next roll (`unfinished_rolls=0`); (c) generate cursor not resumed (depot diff none); (d) harvest and reinforce on the same day (day-12 reinforces 3, harvests 2, `both=false`); (e) slice order / key order (1e-6 depot equality); (f) slicing while paused (cursor held, slice ms 0); (g) atomic phase starting inside the last 2 ms of the 20 ms budget (naval stays at phase 2, `naval_ms=0`); (h) a generate step whose last cost exceeds remaining budget (index stays 0).

**FIX #1 (slice cap on a slower box):** Verification on tip `6471a65e` failed 4/4 **only** on slice max (1× 26.34–36.55, 4× 25.22–27.57). Atomic phases (flush / naval / fuel / air) ran whole once started, so a phase that began near 19.9 ms landed at 23–27 ms; a generate step plus GC reached ~36 ms. Fix: `_run_supply_day_job` does not start an atomic phase unless remaining budget ≥ last measured cost + 2 ms (pessimistic defaults naval 6.0 / fuel 4.5 until measured, stored on the job). Generate/ship loops also stop when remaining < max(last item + 0.5 ms, 5 ms reserve). Deadline 0 (sync `advance_supply_day` / midnight catch-up) still runs the rest. Phase order, one-day-per-day, pause, and depot equality are unchanged — budgets change WHEN work runs, not WHAT. The 25 ms bar stays. `HeadlessPerf6DayRollTest` adds `_test_atomic_phase_defer` and `_test_generate_step_bound` (deadline logic, not wall-clock speed).

`HeadlessPerf6DayRollTest` **3/3 PASS** on tip (plus one 3-busy-loop CPU-load run), slice max ≤25 and 0 frames over:

| run | 1× slice max (over) | 4× slice max (over) |
|---|---:|---:|
| 1 | 16.13 (0) | 17.48 (0) |
| 2 | 15.13 (0) | 17.99 (0) |
| 3 | 18.14 (0) | 17.82 (0) |
| CPU load | 16.41 (0) | 17.78 (0) |

Atomic defer + generate-step bound **PASS**. Depot diff none. Seed 193601 two collects identical (md5 `0e7237ac2a2f6feedf5c8032045e866d`): JAP 903951 / FRA 710739 / ITA 710859 / ENG 711481 / POL 711054 / SOV none / JAP 902474. `--quick` same 14 `unit_board_play_path` reds. map_qc NE **0.9853**.

**FIX #2 (progress guarantee + estimate decay):** FIX #1 stored a phase's last cost clamped to 20 ms. Afford is `remaining ≤ estimate + 2`, so a 19 ms spike can never start under the 20 ms budget; the phase is never re-measured and the day stalls until deadline-0 catch-up. Headless harnesses that do not force the windowed backup (LiveMultiAi, Perf6 4× on a slow box) then finish 0 full supply days.

Fix in `_run_supply_day_job` / `_generate_local_supply_range` / `_ship_routes_range`: if this slice has done **no work yet this frame**, always run the next atomic phase or at least one generate/ship item. Only defer after some work in the same frame. Deadline 0 still runs everything. `_supply_slice_note_phase_ms` EMA-blends `0.75·old + 0.25·new` (same as the item EMA) and clamps to `[0.05, 20]`. A deferred phase (or item) decays `×0.8` toward the 0.05 ms floor each frame it is skipped. Phase order, key order, and WHAT are unchanged — budgets still only change WHEN work runs. `_test_atomic_phase_defer` / `_test_generate_step_bound` still assert FIX #1 deferral **after** the frame has already done work.

`HeadlessPerf6StarveTest` (wired `launch_perf6_starve`) forces a 19 ms atomic-phase estimate and, separately, a 20 ms generate-item estimate through the real job path at a 20 ms budget; pumps `_process` frames at 1× and 4× **without** catch-up / deadline-0; asserts `full_supply_day_count +1` within 160 frames and no slice `> 25 ms`; resets `supply_slice_phase_cost_estimate_ms` after each case.

`HeadlessPerf6StarveTest` **FAIL on `d31e3223`** / **PASS on the tip**:

```
HeadlessPerf6StarveTest: RESULT=FAIL   # d31e3223 (phase/item 1×+4× starved 0→0 left=1 frames=160)
HeadlessPerf6StarveTest: RESULT=PASS   # tip (phase 1× 10f slice_max=15.03; 4× 8f 15.02; item 1×/4× 5f)
```

`HeadlessPerf6DayRollTest` **3/3 PASS** (FIX #2 sitting). Paste clock lines:

```
clock 1x frames=870 full=12 unfinished_rolls=0 slice_max=17.77 slice_over=0 day_ai_n=12 p95=10.9 max=13.0 listener_n=12 listener_max=1.1
clock 4x frames=221 full=12 unfinished_rolls=0 slice_max=17.98 slice_over=0 day_ai_n=12 p95=8.9 max=8.9 listener_n=12 listener_max=1.0
clock 1x frames=870 full=12 unfinished_rolls=0 slice_max=17.53 slice_over=0 day_ai_n=12 p95=13.6 max=18.8 listener_n=12 listener_max=1.1
clock 4x frames=221 full=12 unfinished_rolls=0 slice_max=18.51 slice_over=0 day_ai_n=12 p95=8.6 max=8.7 listener_n=12 listener_max=1.0
clock 1x frames=870 full=12 unfinished_rolls=0 slice_max=17.49 slice_over=0 day_ai_n=12 p95=12.9 max=15.8 listener_n=12 listener_max=1.2
clock 4x frames=222 full=12 unfinished_rolls=0 slice_max=17.93 slice_over=0 day_ai_n=12 p95=8.7 max=9.2 listener_n=12 listener_max=1.1
```

`HeadlessPerf4LiveMultiAiDayTest` **3/3 PASS** (exactly one full supply day per game day). Interactive **PASS** (one full supply day per soft apply). Daily **PASS** (7d wall 33.6 ms). Leftover-queue / MUST1 inside LiveMultiAi: TopInfoBar 6/0, scene-order 7/0, windowed-backup 7/0 `plans_on_roll=0`, refill after the clock, `tm_calendar_roll` → `tib_skip_refill`. Stockpile **PASS**. Perf5 overlay **PASS**. Legend **PASS** p95 5.50 / worst 17.77. Seed 193601 `multi_ai_decisions` identical across 3 OS-process runs and unchanged vs `d31e3223`. Locked infra: JAP 903951 / FRA 710739 / ITA 710859 / POL 711054 / ENG 711481 / USA 800075. `--quick` same 14 `unit_board_play_path` reds (`se_england` fill-toe 1, first-session play surface 1, unit_centric_pick 3, unit_counter_chrome 2, unit_card_fill_toe 3, living_unit_order_loop 4). map_qc NE **0.9853**.

Mutants killed by `HeadlessPerf6StarveTest` behaviour:

| mutant | killing check |
|---|---|
| (i) remove the progress guarantee | `progress_first` + queued 19 ms phase 1×/4× starve (`full 0→0 left=1`) |
| (ii) remove the estimate decay | `defer_decay` (`naval_last_ms` stays 19.000, want ~15.210) |
| (iii) clamp the estimate to 20 ms again with no decay | `run_ema` (last=actual 2.144, not 0.75·19+0.25·actual) + `defer_decay` |

```bash
tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessPerf6StarveTest.gd
```

Wired as `launch_perf6_starve` immediately after `launch_perf6_day_roll`. Merge **HOLD**. Headless; live A/B pending.

**FIX #3 (pace + bounded midnight catch-up):** g99c on `5f7d4cc7` kept full=12/12 and killed the FIX #2 starve, but the 25 ms slice cap still broke: quiet 4× **29.6 ms**, loaded 37–146 ms, memory-pressure **1055 ms**. `_should_catch_up_supply_day` switched `_drain_queued_supply_day_slice` to deadline 0 when the backup tick was ≤80 ms away and crossed midnight, so the remainder ran in one frame. Atomic phases (naval ~3.5 / fuel ~2.4 / air <1 ms) and the progress guarantee were not the cause.

Fix: each drain estimates remaining generate/ship items × item EMA + remaining atomic phase estimates, and frames left before the midnight-crossing tick (`_ms_until_backup_tick` / frame time). Budget stays 20 ms and rises to **at most 22 ms** when behind pace. The last 4 non-roll frames drain at ≤22 ms. Unbounded sync finish is last-resort on the final non-roll frame only and is counted in `supply_catch_up_sync_ms` / `supply_catch_up_sync_count` (the 25 ms cap still includes that frame via `last_supply_slice_ms`). Phase order / key order / WHAT unchanged — budgets only change WHEN.

`HeadlessPerf6DayRollTest` logs `catch_up_frames`, `catch_up_sync_count`, and catch-up max ms per clock run; asserts every frame ≤25 ms (catch-up included) and `catch_up_sync_count==0` at 1× and 4× over 12 days.

`HeadlessPerf6PaceTest` (wired `launch_perf6_pace`) pause-skips 10 drain frames of a 4× day (existing pause seam), then drains in the catch-up window; asserts the day finishes before the roll, every frame ≤25 ms, no unbounded sync. Also asserts `_supply_slice_paced_budget_ms` is 22 ms when remaining work / 4 frames would miss a 20 ms budget.

`HeadlessPerf6PaceTest` **FAIL on `5f7d4cc7`** / **PASS on the tip**:

```
HeadlessPerf6PaceTest: RESULT=FAIL   # 5f7d4cc7 — paced helper missing; lag 4× slice max 81.36ms over 1
HeadlessPerf6PaceTest: RESULT=PASS   # tip — budget 22.00 remaining 811.5; lag 4× 6f slice_max=17.02 sync=0
```

`HeadlessPerf6DayRollTest` **3/3 PASS** (+ 2-core busy-loop CPU load). Paste clock lines:

```
clock 1x frames=871 full=12 unfinished_rolls=0 slice_max=18.82 slice_over=0 catch_up_frames=0 catch_up_sync_count=0 catch_up_max=0.00 day_ai_n=12 p95=13.9 max=14.4 listener_n=12 listener_max=1.5
clock 4x frames=222 full=12 unfinished_rolls=0 slice_max=17.96 slice_over=0 catch_up_frames=0 catch_up_sync_count=0 catch_up_max=0.00 day_ai_n=12 p95=9.2 max=10.3 listener_n=12 listener_max=1.1
clock 1x frames=870 full=12 unfinished_rolls=0 slice_max=17.36 slice_over=0 catch_up_frames=0 catch_up_sync_count=0 catch_up_max=0.00 day_ai_n=12 p95=13.5 max=17.0 listener_n=12 listener_max=1.2
clock 4x frames=221 full=12 unfinished_rolls=0 slice_max=17.73 slice_over=0 catch_up_frames=0 catch_up_sync_count=0 catch_up_max=0.00 day_ai_n=12 p95=8.5 max=8.5 listener_n=12 listener_max=1.0
clock 1x frames=870 full=12 unfinished_rolls=0 slice_max=17.50 slice_over=0 catch_up_frames=0 catch_up_sync_count=0 catch_up_max=0.00 day_ai_n=12 p95=14.8 max=17.8 listener_n=12 listener_max=1.5
clock 4x frames=221 full=12 unfinished_rolls=0 slice_max=17.52 slice_over=0 catch_up_frames=0 catch_up_sync_count=0 catch_up_max=0.00 day_ai_n=12 p95=9.0 max=9.6 listener_n=12 listener_max=1.1
clock 1x frames=870 full=12 unfinished_rolls=0 slice_max=17.56 slice_over=0 catch_up_frames=0 catch_up_sync_count=0 catch_up_max=0.00 day_ai_n=12 p95=14.5 max=18.1 listener_n=12 listener_max=1.3
clock 4x frames=222 full=12 unfinished_rolls=0 slice_max=18.57 slice_over=0 catch_up_frames=0 catch_up_sync_count=0 catch_up_max=0.00 day_ai_n=12 p95=9.7 max=10.1 listener_n=12 listener_max=1.1
```

(last pair = 2-core Python busy-loop load.)

`HeadlessPerf6StarveTest` **3/3 PASS**. `HeadlessPerf4LiveMultiAiDayTest` **3/3 PASS** (exactly one full supply day per game day; leftover-queue / MUST1: TopInfoBar 6/0, scene-order 7/0, windowed-backup 7/0 `plans_on_roll=0`, refill after the clock, `tm_calendar_roll` → `tib_skip_refill`). Interactive **PASS** (one full supply day per soft apply, +2). Daily **PASS** (7d wall **32.4 ms**). Stockpile **PASS**. Perf5 overlay **PASS**. Legend **PASS** p95 **5.77** / worst **18.58**. Seed 193601 `multi_ai_decisions` identical across 3 OS-process runs and unchanged vs `5f7d4cc7`. Locked infra: **JAP 903951, FRA 710739, ITA 710859, USA 800075, ENG 711481 (t6, t7), POL 711054, SOV none**. `--quick` same 14 `unit_board_play_path` reds. map_qc NE **0.9853**.

Mutants killed by behaviour:

| mutant | killing check |
|---|---|
| (i) remove pacing (fixed 20 ms) | Pace `pace_budget` stayed 20.00 with remaining 811.5 / 4 frames |
| (ii) restore ≤80 ms unbounded catch-up | Pace lag 4× slice max **82.75 ms** |
| (iii) FIX #2 no_progress | Starve `progress_first` + queued 19 ms phase 1×/4× starve (`full 0→0 left=1`) |
| (iii) FIX #2 no_decay | Starve `defer_decay` (`naval_last_ms` stays 19.000, want ~15.210) |
| (iii) FIX #2 clamp20 no EMA | Starve `run_ema` (last=actual, not 0.75·19+0.25·actual) + `defer_decay` |

```bash
tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessPerf6PaceTest.gd
```

Wired as `launch_perf6_pace` immediately after `launch_perf6_starve`. Merge **HOLD**. Headless; live A/B pending.

The two `perf4_daily_sim_tick_product.py` edits (and their unit test) stay: `advance_supply_day` now only builds a job and calls `_run_supply_day_job(..., 0)`, so the PERF-4 grep for `_process_air_missions` / `_process_naval_recon` / day-roll deferral has to read the runner body. Without that, `--quick` would fail `supply_day_full_steps_in_live`.

Other headless this sitting: Interactive **PASS** (one full supply day per soft apply, +2, `queued_supply_day`, worst day_ai 14.3 ms). Daily **PASS** (7d wall 33.7 ms, worst day_ai 11.7 ms). Seed 193601, two collects inside that process, identical to the documented sequence JAP 903951 / FRA 710739 / ITA 710859 / ENG 711481 / POL 711054 / SOV none / JAP 902474. A third OS process was not run. Windowed-backup MUST1 **PASS** (7/7 `plans_on_roll=0`, `tm_calendar_roll` → `tib_skip_refill`). Live-equivalent **PASS** (full supply days 3/3; leftover 6/0, scene-order 7/0, windowed 7/0). Legend **PASS** p95 6.45 / worst 18.84. Overlay B1–B4 **PASS**. `HeadlessDailyProductionStockpileTest` **PASS**. `HeadlessProductionTest` does not finish on this tree (see CURRENT_STATE). `--quick` the same 14 `unit_board_play_path` reds (`se_england` fill-toe 1, first-session play surface 1, unit_centric_pick 3, unit_counter_chrome 2, unit_card_fill_toe 3, living_unit_order_loop 4). map_qc NE land hit **0.9853**. Live Play A/B is pending.

```bash
tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessPerf6DayRollTest.gd
```

Wired as `launch_perf6_day_roll` immediately after `launch_perf4_interactive_multi_ai`. Merge **HOLD**.

### RENDER-1 L-on supply rings (ArrayMesh + Home LOD) (draft HOLD, headless; live A/B pending)

Stack on #99 tip `5df8e7fc` (`cursor/perf6-dayroll-c4e1`). Main `61a80433` does not contain #90's `SupplyOutlineBatchLayer`. PR **#101**. Fence: layer + MapRenderer zoom/view-rect feed (`_refresh_terrain_zoom_light` only; `_ensure` does not force Full LOD) + `HeadlessRender1SupplyRingMeshTest` + gates register. OUT: `draw_polished_ring`, SupplyManager / PERF-6, #90 role logic, GameData, world data.

**Ask 1 — base measure** (`5df8e7fc`, 3196×48-gon, Home z=0.318, headless):

| mode | p50 | p90 | worst | notes |
|---|---:|---:|---:|---|
| L-off frame | 6.890 | 6.966 | 7.035 | |
| L-on frame | 40.851 | 41.346 | 42.926 | |
| L-on `_draw` CPU | 112.260 | 113.954 | 117.715 | 6392 AA polylines, 313208 polyline verts |

Cold-first L-on on the base (empty role/batch caches, full `_toggle_supply_overlay`):

| step | ms |
|---|---:|
| sm.toggle_overlay | 0.007 |
| `_refresh_supply_highlights` | 45.955 |
| legend | 18.466 |
| sync | 0.012 |
| total_incl_frame | 159.508 |

Tip cold-first (`HeadlessRender1` (e′)): sm **0.005** / refresh **79.118** / batch **47.125** / legend **15.108** / sync **0.011** / toggle total **94.254** / frame_total **146.659**.

`HeadlessRender1SupplyRingMeshTest` **FAIL on `5df8e7fc`** (polyline/AA `_draw`; mesh/LOD API missing) / **PASS on the tip** (≥3000 items):

| bar | base `5df8e7fc` | tip |
|---|---|---|
| (a) 0 polyline/multiline and 0 AA in steady `_draw` | FAIL 6392 AA polylines | PASS mesh_calls=392 line=0 aa=0 |
| (b) Home verts ≤25% of full; cull above threshold | FAIL (no LOD) | PASS 230112/1840896=**0.125**; culled=193 |
| (c) 0 rebuilds across 60 idle frames | FAIL (per-frame polyline) | PASS |
| (d) 1-depot `patch_items` p50≤1 ms, worst<50, touched chunks only | n/a polyline | PASS p50 **0.319** worst **0.376** touched **2/196** |
| (e) warm L toggle first frame <100 ms | n/a | PASS **5.3** ms |
| (e′) cold first L-on after boot <250 ms | polyline path | PASS **146.7** ms |
| (f) pulse 0 rebuilds | n/a | PASS modulate-only |
| (g) colour/width parity; every role present | n/a | PASS 15 roles |

Mutants killed by named asserts:

| mutant | killing assert |
|---|---|
| aa_on | (a) source `antialiased` hits=0 + runtime aa_calls=0 |
| polyline_loop | (a) 0 line calls / mesh path |
| lod_off | (b) Home/full=0.125 |
| rebuild_in_draw | (c) rebuild count unchanged across 60 idle frames |
| patch_full_rebuild | (d) touched=2/196 |
| pulse_rebuild | (f) pulse leaves rebuild count unchanged |
| counter_lie | sink mesh_calls/verts match real `draw_mesh` arrays |
| cull_off | (b) culled_chunks=193, drawn < built |
| skip_ignored | vis 3196→3194, built 230112→229968 |
| cold_full_build | (e′) 146.7 ms < 250 |

Regression: OverlayFresh B1–B4 **PASS**; Legend p95 **5.66** / worst **18.60** (≤60); Perf3 **PASS** (MAX_TOGGLE_MS=1000 unedited; Home 156.5 / 4.0 / 137.5; z0.760 5.8 / 4.0 / 5.6); Perf6 DayRoll **PASS** (1× slice_max 17.79 / 4× 17.89, full=12 sync=0); Starve **PASS**; Pace **PASS** (budget 22.00, lag 4× slice_max 17.03 sync=0). Seed 193601: `grep -o 'multi_ai_decisions=.*' log | md5sum` → `20fe9063de285f19d4f9b8a105abfd31` (reads **`20fe9063`**; do not carry PERF-6 FIX #1's private digest `0e7237ac`). `--quick` same 14 `unit_board_play_path` reds. map_qc NE **0.9853**. Headless; live A/B pending.

**FIX #1 (cold first L-on + independent draw + seed digest):** Ship g101 NOT READY on two items. (e′) **334 / 293 / 296** ms vs 250 on Ship (this box **146.7**; base **295** — no cold-path gain). Breakdown: refresh ~95–102, batch ~55–60, legend ~27–30, **~160–200 ms first frame after toggle**. `counter_lie` survived: `draw_mesh(...)` removed from `_ci_draw_mesh`, counters kept, every assert except (e′) still passed. Seed write-up used `0e7237ac`.

Fix (250 ms bar stays; target ≤180; Perf3 `MAX_TOGGLE_MS=1000` unedited):

- Idle Home-LOD prebuild after map-ready, ≤8 ms/frame (`SUPPLY_RING_IDLE_BUDGET_MS=8`; setup on its own frame). Hidden warm (`begin_hidden_warm` / `modulate.a=0`) so the GPU upload is not on the L frame. Cold `_refresh_supply_highlights` skips the role walk when #90 roles are already cached. Fingerprint / route / depot snapshotted at role-collect so a later capture still trips `fp_changed`. Do not restart idle after a live batch or after first L-on.
- `independent_draw_info`: RenderingServer / Viewport draw-info delta L-on vs L-off. Dummy headless reports 0; then a source scan requires a live `draw_mesh(` in `_ci_draw_mesh` (comments / `if false` do not count). Named assert; kills the exact `counter_lie` mutant.
- Seed method (Ship): `grep -o 'multi_ai_decisions=.*' log | md5sum` → `20fe9063de285f19d4f9b8a105abfd31` (reads **`20fe9063`**). Tip is byte-identical to `5df8e7fc` on that line.

`HeadlessRender1SupplyRingMeshTest` **PASS** on the FIX #1 tip (3196 items):

| bar | original tip `3397d28c` | FIX #1 |
|---|---|---|
| (a) 0 polyline/AA; mesh_calls=392 | PASS | PASS |
| (b) Home/full=0.125; culled=193 | PASS | PASS |
| (c) 0 idle rebuilds | PASS | PASS |
| (d) 1-depot patch | p50 0.319 / 0.376 | p50 **0.306** worst **0.427** touched 2/196 |
| (e) warm L first frame <100 | 5.3 | **5.1** |
| (e′) cold first L-on (target ≤180, bar 250) | 146.7 | **72.5** (toggle 15.4 / first_frame 57.0) |
| (f) pulse 0 rebuilds | PASS | PASS |
| (g) 15 roles | PASS | PASS |
| `independent_draw_info` | wrapper only (mutant survived) | **PASS** dummy delta=0 `src_live=true` |

Cold-first breakdown on FIX #1:

| step | ms |
|---|---:|
| idle Home-LOD prebuild (off L) | 84.149 (12 frames, max_step 8.243, setup 7.402, warmed) |
| sm.toggle_overlay | 0.004 |
| `_refresh_supply_highlights` | **0.295** (cache hit) |
| batch apply | 48.513 |
| legend | 15.078 |
| sync | 0.010 |
| toggle wall | 15.409 |
| first frame after toggle | 57.041 |
| **frame_total (e′)** | **72.450** |

`independent_draw_info` log: engine off/on all zeros; `src_live=true`; **killed `counter_lie`**. Removing `draw_mesh(...)` from `_ci_draw_mesh` while leaving counters FAILS this assert.

Regression after FIX #1: OverlayFresh B1–B4 **PASS**; Legend p95 **5.92** / worst **18.62** (≤60); Perf3 **PASS** (MAX_TOGGLE_MS=1000 unedited; Home **138.8 / 4.1 / 132.1**; z0.760 **5.8 / 5.3 / 5.4**; roles=1 setups=0 glyphs=0); Perf6 DayRoll **PASS** (1× slice_max **17.40** / 4× **15.48**, full=12 sync=0); Starve **PASS**; Pace **PASS** (budget 22.00, lag 4× slice_max **17.02** sync=0). Seed 193601 ×3 OS processes identical:

```
grep -o 'multi_ai_decisions=.*' /tmp/render1-seed/runN.log | md5sum
# 20fe9063de285f19d4f9b8a105abfd31  -
```

day0 JAP/SOV/ITA soft USA; d1 SOV/ITA/USA soft POL; d2 ITA/USA/POL soft ENG; d3 USA/POL/ENG soft FRA; d4 POL/ENG/FRA soft JAP. `--quick` same 14 `unit_board_play_path` reds. map_qc NE **0.9853**. Headless; live A/B pending.

**FIX #2 (windowed draw gate + 8 ms idle + real GPU warm):** Ship g101b NOT READY. (e′) **198–209** ms headless / **246** windowed — this box's own 180 target failed on `a065eb49`. Idle max_step **8.2–10.0** vs 8.0 (105–111 ms / 14–15 frames). `counter_lie` survived: grep started at `func _ci_draw_mesh(` (the header contains `draw_mesh(`), so dummy delta=0 always passed.

Fix:

- Windowed `tools/eoa_render1_draw_guard.sh` (xvfb, like `eoa_rt1_pixel_guard.sh`). DisplayServer must not be headless. Engine L-on vs L-off delta **< mesh_calls is FAIL**. **0 is FAIL**. No grep fallback. `skip_engine_draw` (draw_mesh removed, counters kept) must produce delta 0. Headless `independent_draw_info` no longer PASSes on a source scan.
- Idle: one phase per frame; 5.5 ms work cap so one last chunk cannot push **max_step > 8.0** (assert is `> 8.0` fail, no 12 ms slack). Fingerprint / `begin_idle` / warm each get their own frame.
- Hidden warm submits at **a=1** for 3 presents (a=0 was culled — GPU upload stayed on L). `_draw` uses cached chunk vert counts (no `surface_get_arrays` on the L frame). Early L-on (`_finish_supply_ring_prebuild_if_needed`) drains mesh ingest so an empty ready batch cannot show visible=0 (Perf3).

`HeadlessRender1SupplyRingMeshTest` **3/3 PASS** (not best-of):

| run | (e′) cold ms | toggle | first_frame | max_step | refresh | legend | batch |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | **83.5** | 21.0 | 62.5 | **7.992** | 0.48 | 20.4 | 0 |
| 2 | **78.6** | 18.8 | 59.8 | **5.678** | 0.42 | 18.3 | 0 |
| 3 | **72.5** | 16.8 | 55.7 | **5.518** | 0.36 | 16.4 | 0 |

Target ≤180, bar 250 kept. (a)–(g) hold. (e) warm 4.3–5.1.

`tools/eoa_render1_draw_guard.sh` **PASS** (xvfb, DisplayServer=X11, RSS **2614** MB):

```
skip_engine_draw delta=0  → would FAIL (0 count is FAIL)
live engine on={ draws: 392, prims: 76704, can_d: 392 }
independent_draw_info killed mutant_counter_lie: engine delta=76704 >= mesh_calls=392
```

Regression: OverlayFresh B1–B4 **PASS**; Legend p95 **6.32** / worst **18.97**; Perf3 **PASS** (MAX_TOGGLE_MS=1000; Home **160.5 / 5.3 / 132.4**; z0.760 **6.0 / 4.9 / 5.9**; roles=1 setups=0 glyphs=0); Perf6 DayRoll **PASS** (1× slice_max **16.99** / 4× **16.12**, full=12 sync=0); Starve **PASS**; Pace **PASS** (budget 22.00, lag 4× **17.02** sync=0). Seed 193601 ×3:

```
grep -o 'multi_ai_decisions=.*' log | md5sum
# 20fe9063de285f19d4f9b8a105abfd31  -
```

`--quick` same 14 `unit_board_play_path` reds. map_qc NE **0.9853**. Wired as `launch_render1_draw_guard` after `launch_render1_supply_ring_mesh`. Headless; live A/B pending.

**FINAL cleanup (cap the cold-L chase; honest 250 bar):** Ship measured cold first L-on **188–210** ms headless / **208–246** ms windowed. That passes the project bar of **250**. This box's 72–84 / 180 target is not the gate. Do not chase further.

- Product: `skip_engine_draw` removed from `SupplyOutlineBatchLayer`. `draw_mesh` always submits.
- `counter_lie` mutant is a **source edit** in `WindowedRender1DrawGuard`: the test reloads the layer with `draw_mesh(...)` stripped and counters kept. Engine delta **0**. No product flag.
- Leftover `_ci_draw_mesh_has_live_submit` / `ci_draw_mesh_live` grep deleted.
- Cold assert is **250** only (`MAX_COLD_MS`). Each run prints `cold_raw display=… ms=…`. Never best-of.

Six raw `cold_raw` on this box (3 headless + 3 windowed):

| run | display | ms |
|---|---|---:|
| 1 | headless | **79.140** |
| 2 | headless | **75.984** |
| 3 | headless | **65.587** |
| 1 | X11 | **90.655** |
| 2 | X11 | **83.494** |
| 3 | X11 | **80.322** |

Windowed guard **3/3 PASS**: source-edit probe delta **0** (counters=392); live engine delta **76704** ≥ mesh_calls **392**. Seed 193601 ×3:

```
grep -o 'multi_ai_decisions=.*' log | md5sum
# 20fe9063de285f19d4f9b8a105abfd31  -
```

`--quick` same 14 `unit_board_play_path` reds. map_qc NE **0.9853**. Headless; live A/B pending.

**FIX #4 (ring colour + honest live-boot cold L-on):** Play MIXED on `9ddeecc3`: L-on roles were `engineers_recommended` 1678 / hub 1517 vs A's hub 3157 / route 38. Cause: idle prebuild called `_supply_role_for_pid(..., allow_without_overlay=true)` and L-on reused that cache. Fixture `cold_ms` also measured a synthetic 3196-gon grid, not Play's KEY_L / frame2 / full TestScenario.

Fix:

- Prebuild uses the exact L-on role walk (`_supply_role_lon_semantics`, no `allow_without_overlay=true`), waits until province+depot counts are stable, and fingerprints role-context inputs. L-on show/hide only when both topology and role fps match; otherwise recompute.
- Fixture metric renamed **fixture L-on** (250 bar kept). `max_step ≤ 8.0` unchanged.
- Live-boot windowed gate `WindowedRender1LiveColdGuard` / `tools/eoa_render1_live_cold_guard.sh`: real TestScenario, `Input.parse_input_event(KEY_L)`, t0 in `_input`, stop at `RenderingServer.frame_post_draw` of first `mesh_calls > 0`. Report frame2 and same-run L-off frame2. Bar: Δ(L-on − L-off frame2) ≤ 250 ms and frame2 B/A ≤ 0.75, 3/3 not best-of. Pin Köln `710417` at z=3.2 with the RX-1 `lock_pixel_guard_camera` + `eoa_rx1_pixel_lock_camera` (TestRunner +6d grand visuals otherwise steal Asia).
- Colour: L-on histogram == fresh `_supply_highlight_roles()`; close-zoom hue buckets (sat>0.4, val>0.5, map area below the toolbar; teal on outline edges so mesh interiors cannot 3× A's polyline stroke; orange excludes neon political fills) within ±10% of `5df8e7fc` (teal 37–45k / olive ≤9k+10% / orange 4–7k).
- Mutant: prebuild with `allow_without_overlay=true` → FAIL (source body of `_step_supply_prebuild_roles`).

Keep: windowed draw guard + counter_lie source edit, 9 mutants, Perf3/5/6, seed 193601 `grep -o 'multi_ai_decisions=.*' log | md5sum` → `20fe9063` ×3, `--quick` 14, map_qc NE 0.9853. Wired as `launch_render1_live_cold` after `launch_render1_draw_guard`. Stay DRAFT / HOLD.

Tip `d0107744` live-boot **3/3 PASS** (not best-of). Roles `{hub: 3158, route: 38}` == fresh compute (A was hub 3157 / route 38 / active 1). Hue vs `5df8e7fc`: teal **46608 / 46606 / 46605** · olive **3386** · orange **6504**. Live-boot:

| run | L-on frame1 | L-on frame2 | L-off frame2 | Δ | B/A |
|---|---:|---:|---:|---:|---:|
| 1 | 245.101 | 296.609 | 253.583 | 43.026 | 0.485 |
| 2 | 244.425 | 298.210 | 270.885 | 27.325 | 0.488 |
| 3 | 214.620 | 262.789 | 252.267 | 10.522 | 0.430 |

`allow_without_overlay` mutant killed. Fixture L-on 82.3 ms. max_step **5.647 / 5.559 / 6.38**. Seed ×3 `20fe9063de285f19d4f9b8a105abfd31`. `--quick` 14 reds. map_qc NE **0.9853**.

**FIX #5 (test honesty):** `A_FRAME2_DEFAULT_MS` deleted. Measure A's frame2 on `5df8e7fc` (`tools/eoa_render1_measure_a.sh` → `docs/evidence/render1/a_live_5df8e7fc.json`). Wait until LoadingScreen is gone (first capture was title art). L-off uses a fresh KEY_L t0 (parse_input_event is deferred; do not reuse L-on's stamp). L-on frame1 is the first `frame_post_draw` whose batch `_draw` ran *after* that t0 (`get_last_draw_usec`; stale idle-warm `mesh_calls` read as presented and produced the 10–43 ms lie). Report real L-on minus L-off frame2 (Ship GPU ~155 ms). `HeadlessRender1PrebuildRoleTest` / `tools/eoa_render1_prebuild_role.sh`: per-pid prebuild vs fresh `_compute_supply_highlight_roles()` at L-on — tip green, `lon_semantics_off` red, `allow_without_overlay` red. Ring-edge hue is teal *share* of ring-core pixels (sat>0.52, val>0.58; olive sat≥0.55 so Line2D AA fringe cannot dilute vs mesh) ±10% vs measured A. Mesh extrusion reads thinner than Line2D AA; `SupplyOutlineBatchLayer.width_scale` / `EOA_RENDER1_RING_WIDTH_SCALE` (default 1.0).

Measured A `5df8e7fc`: L-on frame2 **422.000** / L-off **223.252** / Δ **198.748**; teal share **0.8190** (edge 41434 / olive 239 / orange 8916); width_proxy **3.689**.

Tip live-boot **3/3 PASS** (xvfb llvmpipe, not product Play / not Ship GPU):

| run | L-on frame1 | L-on frame2 | L-off frame2 | Δ | B/A | teal share |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 200.882 | 256.898 | 233.106 | 23.792 | 0.609 | 0.8041 |
| 2 | 202.587 | 261.071 | 226.081 | 34.990 | 0.619 | 0.8041 |
| 3 | 193.314 | 253.600 | 229.584 | 24.016 | 0.601 | 0.8041 |

This box's Δ is 24–35 ms because close-zoom fills make L-off ~230 ms too; Ship GPU ~155 ms. B/A vs measured A 422 ms. Prebuild roles: tip PASS n=208 (hub 48 + engineers 160); `lon_semantics_off` FAIL mismatch=160; `allow_without_overlay` FAIL used_allow. Mesh test **PASS**. `--quick` 14 reds. map_qc NE **0.9853**. Display-only; seed 193601 **`20fe9063`**. Stay DRAFT / HOLD.

**FIX #6 (same-run A/B + fixture headroom + behavioural allow mutant):** Live guard boots A `5df8e7fc` and B in the same wrapper run. Report each raw L-on frame2 and L-off frame2. Δ = L-on − L-off. B/A = B frame2 / A frame2. Never read A from a JSON file. Ship measures B's Δ at 129–254 ms, not 24–35; B/A 0.61 does not follow from 24–35 / 198.7.

Same-run 3/3 PASS (xvfb llvmpipe, load 1.5–2.1; not product Play / not Ship GPU):

| run | A lon2 | A loff2 | A Δ | B lon2 | B loff2 | B Δ | B/A | load |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 463.493 | 231.993 | 231.500 | 263.846 | 250.399 | 13.447 | 0.569 | 1.84 |
| 2 | 434.059 | 225.647 | 208.412 | 236.606 | 232.952 | 3.654 | 0.545 | 1.49 |
| 3 | 435.990 | 229.816 | 206.174 | 251.753 | 251.388 | 0.365 | 0.577 | 1.52 |

Hue B **0.8045** vs same-run A **0.8190** (ring-edge share). Fixture L-on ×5 **50.500 / 53.246 / 51.041 / 50.367 / 51.560** ms at load **1.49 / 1.41 / 1.35 / 1.29 / 1.25** (≤200; bar 250). `allow_without_overlay` killed by behaviour: pids 710240–710247 pre=`engineers_recommended` fresh=empty mismatch=8 (flag deleted). `lon_semantics_off` mismatch=160. Tip n=208 hub 48 + engineers 160. Seed ×3 `20fe9063de285f19d4f9b8a105abfd31`. `--quick` 14 reds. map_qc NE **0.9853**. `width_scale` default 1.0. Stay DRAFT / HOLD.

**FIX #7 (drain in-view rings + honest complete-frame timing):** Ship g101g: `FIRST_PRESENT_MESH_BUDGET=32` only redrew the deferred slice, so Godot `_draw` dropped already-submitted rings (teal 0.04 vs A's 0.57 over Köln; `WindowedRender1DrawGuard` mesh_calls=32 want ≥300). Idle `upload_meshes_now()` `force_draw()` with the layer visible while L was off (~80 ms hitch + pre-L flash). Headless `counter_lie` survived on `38d66d92`.

Fix:

- Product `_keys_for_present` submits the **full in-view set** on the first L-on `_draw` (Godot replaces the canvas item). `FIRST_PRESENT_MESH_BUDGET` remains only for mutant `never_drain`. Assert: within 3 presented frames after L, drawn mesh set == built chunk set in view. `never_drain` (budget-only, no accumulate) → FAIL.
- Timing is real KEY_L → `frame_post_draw` of the first frame with **all in-view rings** (`in_view_present_complete`). Report that number and `complete_frame`. Same-run A still uses the two-presented-frame protocol on `5df8e7fc`.
- `upload_meshes_now` / hidden warm / idle prebuild queue only — no `RenderingServer.force_draw()` while L is off. Idle max_step ≤ 8 ms.
- Headless `independent_draw_info` requires a live `draw_mesh(` in the `_ci_draw_mesh` **body** (not the function name). Source-edit that strips `draw_mesh` FAILS.

Keep: per-pid role test (both mutants killed), colour fix, deferred toast, `width_scale` default 1.0.

Same-run 3/3 PASS (xvfb llvmpipe, load 1.89–2.06; not product Play / not Ship GPU). B Δ is negative because L-on complete (all rings, frame 1) is cheaper than L-off frame2 on this close-zoom llvmpipe box; bar is Δ ≤ 250. Ship GPU L-on−L-off at frame2 is 182–245 ms.

| run | A lon2 | A loff2 | A Δ | A cf | B lon complete | B loff2 | B Δ | B/A | B cf | load |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 424.974 | 220.721 | 204.253 | 2 | 175.175 | 227.225 | −52.050 | 0.412 | 1 | 2.02 |
| 2 | 429.289 | 224.169 | 205.120 | 2 | 175.062 | 225.627 | −50.565 | 0.408 | 1 | 2.06 |
| 3 | 430.972 | 239.949 | 191.023 | 2 | 175.055 | 225.537 | −50.482 | 0.406 | 1 | 1.89 |

Hue B **0.8045 / 0.8046 / 0.8045** vs same-run A **0.8190** (ring-edge share; teal 41195–41211 vs 41412–41433). Fixture L-on ×5 **50.419 / 49.287 / 49.386 / 49.358 / 49.149** ms at load **1.32 / 1.58 / 1.80 / 1.98 / 2.14** (complete_frame=1; ≤200; bar 250). Windowed fixture **69.954** ms complete_frame=1 drain n=196. Idle max_step **5.508 / 5.506 / 5.506 / 5.505 / 5.506** (fixture) · live **6.039 / 6.728 / 6.734**. `never_drain` killed drawn=16 < view=196 after 3 frames. `counter_lie` killed (headless source-edit; windowed engine delta=76704). `allow_without_overlay` killed: pids 710240–710247 pre=`engineers_recommended` fresh=empty mismatch=8. `lon_semantics_off` mismatch=160. Tip n=208 hub 48 + engineers 160. Live roles `{hub: 3158, route: 38}`. Seed ×3 `20fe9063de285f19d4f9b8a105abfd31` (`grep -o 'multi_ai_decisions=.*' log | md5sum`). `--quick` same 14 `unit_board_play_path` reds (`se_england` fill-toe 1, first-session play surface 1, unit_centric_pick 3, unit_counter_chrome 2, unit_card_fill_toe 3, living_unit_order_loop 4). map_qc NE **0.9853**. Stay DRAFT / HOLD.

```bash
tools/run_godot.sh --headless --path . --resolution 1280x740 \
  -s res://scripts/core/HeadlessRender1SupplyRingMeshTest.gd
tools/eoa_render1_live_cold_guard.sh
```

Wired as `launch_render1_supply_ring_mesh` immediately after `launch_perf5_supply_overlay_fresh`. Merge **HOLD**.

xvfb screenshots go to `/opt/cursor/artifacts/fac1a/`, `/opt/cursor/artifacts/fac1a_fix2/`, `/opt/cursor/artifacts/fac1a_fix2b/`, `/opt/cursor/artifacts/fac1a_fix2c/`, `/opt/cursor/artifacts/fac1a_fix3/`, and `/opt/cursor/artifacts/fac1a_fix4/` and are **NOT live Play**. Peak RSS must stay under 3 GB (isolated process tree — do not sum leftover Godot). Merge **HOLD**.

**FIX #4 (Play MIXED `76fb4808`):** click ownership + badge-in-footprint + cluster digit + lone min size + split guard 1.53. Seeds unchanged. Isolated keep-green:

| gate | kind | result | peak MB isolated |
|---|---|---|---|
| py_fac1a | py | PASS | — |
| hd_fac1a | headless | PASS (hit_test, badge-in, digit 12px, lone ≥36) | — |
| xvfb_fac1a | xvfb | PASS click=0 noop=0 badge_in digit lone split 1.53 clearance all tiers occl=0.000 rx1 0.843/0.843 | **2030.8** |
| xvfb_rx1 ON / OFF | xvfb | PASS mid_river **0.749 / 0.749** close 0.775 / 0.775 spine 1.000 | isolated |
| hd_mv1 / hd_mv1b / hd_rh1 | headless | PASS | — |
| hd_ix1 (6) / hd_rx1 (4) / hd_rt1 (3) | headless | PASS | — |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | **2038.1 / 2036.6 / 2033.5** |

Screenshots FIX #4 (xvfb **NOT live Play**): `/opt/cursor/artifacts/fac1a_fix4/01_badge_z0.97_NOT_live_play.png`, `02_cluster_digit_z0.99_NOT_live_play.png`, `03_lone_icon_z1.30_NOT_live_play.png`, `04_split_boundary_z1.53_NOT_live_play.png`.

**FIX #5 (Play MIXED `3bb534c0`, last polish):** stale-hover override + tight oval/badge hits + cluster chrome + dark halo. Seeds unchanged. Isolated keep-green:

| gate | kind | result | peak MB isolated |
|---|---|---|---|
| py_fac1a | py | PASS | — |
| hd_fac1a | headless | PASS (facility-first dest_matches, oval hit, chrome gap 2px, 2px GIS) | — |
| xvfb_fac1a | xvfb | PASS stale=true chrome=2.00 outside=true prom 36/36 halo=2 click=0 noop=0 badge_in digit lone split 1.53 clearance all tiers occl=0.000 rx1 0.843/0.843 | **2039.1** |
| xvfb_rx1 ON / OFF | xvfb | PASS mid_river **0.749 / 0.749** close 0.775 / 0.775 spine 1.000 | isolated |
| hd_mv1 / hd_mv1b / hd_rh1 | headless | PASS (unedited) | — |
| hd_ix1 (6) / hd_rx1 (4) / hd_rt1 (3) | headless | PASS | — |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | **2109.2 / 2032.8 / 2034.7** |

Screenshots FIX #5 (xvfb **NOT live Play**): `/opt/cursor/artifacts/fac1a_fix5/01_cluster_count_tag_z0.97_NOT_live_play.png`, `02_lone_and_cluster_z1.30_NOT_live_play.png`, `03_borken_top_edge_z0.93_NOT_live_play.png`.

**FIX #6 (Play MIXED `752a5529`):** hit shape = drawn art per variant. Seeds / stale-hover / MV-1 gates unchanged. Isolated keep-green (`1cc32e8e`):

| gate | kind | result | peak MB isolated |
|---|---|---|---|
| py_fac1a | py | PASS | — |
| hd_fac1a | headless | PASS (art-body hit, 2px inside silhouette owns click) | — |
| xvfb_fac1a | xvfb | PASS stale=true sil=true sil_fail=0 chrome=2.00 outside=true prom 36/36 halo=2 click=0 noop=0 badge_in digit lone split 1.53 clearance all tiers worst 12.81 occl=0.000 rx1 0.843/0.843 | **2034.4** |
| xvfb_rx1 ON / OFF | xvfb | PASS mid_river **0.749 / 0.749** close 0.775 / 0.775 spine 1.000 | **2028.1 / 2024.5** |
| hd_mv1 / hd_mv1b / hd_rh1 | headless | PASS (unedited) | **1194.1 / 1194.0 / 1193.8** |
| hd_ix1 (6) / hd_rx1 (4) / hd_rt1 (3) | headless | PASS | ~1194–1198 |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | **2031.4 / 2037.5 / 2028.1** |

Screenshots FIX #6 (xvfb **NOT live Play**): `/opt/cursor/artifacts/fac1a_fix6/01_l4_cluster_hit_overlay_z0.97_NOT_live_play.png`, `02_lone_hit_overlay_z2.25_NOT_live_play.png`.

**FIX #7 (Play MIXED `5d42888a`):** L2 cluster oval hit + press/release `event.position`. Seeds / MV-1 gates unchanged. Isolated keep-green (`a5b4b4da`):

| gate | kind | result | peak MB isolated |
|---|---|---|---|
| py_fac1a | py | PASS | — |
| hd_fac1a | headless | PASS (L2 oval / L4 circle, event-position pick) | — |
| xvfb_fac1a | xvfb | PASS stale=true stale_lag=true (15/15 lone+cluster) clustervar=true sil_fail=0 click=0 noop=0 clearance all tiers worst 12.81 occl=0.000 rx1 0.843/0.843 | **2035.5** |
| xvfb_rx1 ON / OFF | xvfb | PASS mid_river **0.749 / 0.749** close 0.775 / 0.775 spine 1.000 | **2031.5 / 2031.4** |
| hd_mv1 / hd_mv1b / hd_rh1 | headless | PASS (unedited) | **1194.1 / 1194.1 / 1195.0** |
| hd_ix1 (6) / hd_rx1 (4) / hd_rt1 (3) | headless | PASS | ~1194–1195 |
| xvfb_mv1 / xvfb_mv1_card / xvfb_rh1 | xvfb | PASS | **2031.4 / 2033.0 / 2030.1** |

**FIX #8 (Play MIXED `5d42888a`, headless + xvfb, NOT live Play):** L2 cluster hit is the drawn oval (`OVAL_W_FRAC` 0.88 / `OVAL_H_FRAC` 0.58 / `OVAL_TOP_FRAC` 0.26), not the 34 px `CLUSTER_MID_MIN_PX` circle. L4 stays round. For L1–L4 lone icons and clusters, only drawn art (icon body, badge, count disc) owns a click. `HALO_PX` is paint (`halo_px` still ≥2 when zoom ≥ 1). `CHROME_GAP_PX` and `CLEAR_MARGIN_PX` are not hit pads. A zero-gap MV-1 commit goes to the province under `event.position`. `_still_click_province_pid` and `_mv1_re_resolve_commit_pid` return the facility under the point, else the hex pick. A GIS miss does not keep `_march_preview_cache_dest` or the hover province. `_map_pick_world_from_event` already used `InputEventMouse.position`. Seeds, split/merge, pips, units-first order, MV-1/MV-1b preview + slop, P/F9 hide, art, and positions stay. Guard `HeadlessFac1aHitGeometryTest` calls `hit_test_world` and `_still_click_province_pid` at computed edge points (2 px in/out, plus 1 px outside the art and the old circle top). **FAIL** on main `61a80433` (`failures=107`) / **PASS** on the tip (`failures=0`). Wired as `launch_fac1a_hit_geometry` after `launch_fac1a_airfield_icons`.

| mutant | killed by |
|---|---|
| L2 hit back to the circle | `L2 oval rejects circle overshoot` (top of the old square). Passed on main's oval and on the tip; a circle body fails it. |
| Halo counted as a hit | main **FAIL** `halo owns click` and `2px outside art still facility` at z 1.30 / 2.25. Tip **PASS**. |
| Stale dest kept in `_mv1_re_resolve_commit_pid` | main **FAIL** `re_resolve kept stale dest 710368`, `re_resolve on L2 centre want 710434 got 710368`, `still_click GIS miss kept stale 710368`. Tip **PASS**. |
| Pick from the mouse instead of `event.position` | event world and mouse world differ by ≥1 px; `_map_pick_world_from_event` matches the event. Passed on main and on the tip. |

Measured on this machine (NOT live Play):

| gate | kind | result |
|---|---|---|
| HitGeometry | headless | main `RESULT=FAIL (failures=107)` · tip `RESULT=PASS (failures=0)` |
| AirfieldIcon, MV-1, MV-1b, FLEET-1 | headless | `RESULT=PASS` |
| CH-1 / MV-1e | hd + xvfb | `15/15 commit Y=Leverkusen` · rss **1212.0 / 1657.1** |
| xvfb_fac1a | xvfb | stale=true stale_lag=true clustervar=true sil_fail=0 click_fail=0 noop_fail=0 rx1_mid 0.843/0.843 · wrapper peak **2638.7 MB** |
| Seeded RX-1 ON / OFF | xvfb | mid_river **0.749 / 0.749** close 0.775 / 0.775 spine 1.000 |
| `--quick` | py | exactly **14** `unit_board_play_path` reds (se_england fill-toe 1, first_session play surface 1, unit_centric_pick 3, unit_counter_chrome 2, unit_card_fill_toe 3, living_unit_order_loop 4). No new red. |
| map_qc | py | NE land hit **0.9853** (3148/3195) |

This checkout has no Seed 193601 runner (`/workspace/gfac1a-out/chain.sh` is not on this machine). That triple-run was not executed here.

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

### FLEET-1 land-spill vs foreign fleet / open sea (draft HOLD)

Nearest-own-land chrome spill (`CHROME_SPILL_WORLD` 340) must not steal a click on a foreign fleet counter or on open sea. Gate: `_try_open_land_unit_at_world` calls `_nearest_player_land_formation_at_world` only when GIS at `event.position` is a land province **and** `_pick_unit_formation_at_world` missed every counter (`fo_any == null`). **FIX #1 (Play MIXED `582263e8`):** a foreign fleet disk hit inspects that fleet when the fleet's **own stationed pid is sea**, even if GIS under the cursor is coastal land (ENG Channel chip over East Kent `711453`). Land-stationed foreign fleet (MV-1b Köln FRA `710417`) still falls through. Foreign fleet **and** foreign land cards hide Open fight / Assign leader; march stays blocked. Own cards unchanged. Hit-test priority otherwise unchanged. MV-1 / MV-1b gates **unedited**. Out of scope: Channel / Rio Grande Rise polygons, Pas-de-Calais FRA-land spill. Shared-sea one-marker-per-nation is FLEET-2.

Guard: `HeadlessFleet1LandSpillGateTest` + `tools/eoa_fleet1_guard.sh` (hd + xvfb 1280×740). Seeds are real `world_accurate` label_anchors:

| seed | pid | world |
|---|---|---|
| Maginot GER land | `710173` | `(4283.279411, 1010.266854)` |
| Emden (GER coast, no chip) | `710385` | `(4258.130659, 873.294384)` |
| Köln (GER land; FRA fleet) | `710417` | `(4254.322147, 944.095861)` |
| East Kent (ENG coastal land) | `711453` | `(4119.875715, 938.028287)` |
| North Sea GER fleet | `950000` | `(4164.266667, 773.688889)` |
| English Channel ENG fleet | `950001` | `(4128.701206, 938.217996)` |
| open sea (perp off Channel disk; GIS Channel) | `950001` | resolved ~`(4162.498, 865.708)` (avoids East Kent) |

Distances from Maginot: Channel **170.5**, North Sea **264.8**, Emden **139.3**, open sea **188.4** — all inside 340. Channel↔East Kent **8.8** (inside fleet disk). Cases: (a) Channel fleet → ENG; (b) open sea → Channel inspector; (c) Emden land → Maginot GER; (d) North Sea → GER fleet; (e) East Kent GIS + ENG disk → ENG fleet; (f) Köln FRA land-fleet not selected; (g) foreign fleet/land cards hide Assign/Open fight, march blocked; (h) own card still shows those buttons. Headless + xvfb **NOT live Play**.

Isolated keep-green (`95009fee`; wrapper `rss_mb` preferred; MV-1/MV-1b **unedited**):

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| FLEET-1 hd / xvfb | both | PASS (a–h) | **1196.0 / 1331.1** |
| hd_mv1 | headless | PASS (unedited) | **1195.6** |
| hd_mv1b | headless | PASS (unedited) | **1195.7** |
| hd_rh1 | headless | PASS | **1195.5** |
| hd_ix1 (6) | headless | PASS (MandateGate `PASS failures=0`) | **1195.5–1197.4** |
| hd_rx1 (4) | headless | PASS | **1195.5–1195.8** |
| hd_rt1 (3) | headless | PASS | **1195.5–1195.9** |
| hd_fac1a | headless | PASS | **1195.8** |
| py_fac1a | py | PASS 7/7 | **42.8** (`resource.ru_maxrss`) |
| xvfb_mv1 | xvfb | PASS | **2033.3** |
| xvfb_mv1_card | xvfb | PASS `fra=true` `edge_panel`/`edge_card`/`cap_commit` | **2041.5** |
| xvfb_rh1 | xvfb | PASS | **2036.4** |
| xvfb_fac1a | xvfb | PASS stale_lag=true 15/15 lone+cluster rx1 0.843/0.843 | **2036.2** |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper no RSS (typical isolated hd ~1.2 GB) |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1195.6 / 1330.6** |
| Seeded RX-1 mid_river ON/OFF | xvfb | PASS units-off **0.749** / close 0.775 / spine 1.000 | wrapper no RSS (typical isolated ~2046) |
| UI-1 guard hd+xvfb | both | PASS | **1200.2 / 1343.7** |

### FLEET-2 shared-sea per-nation fleet markers (draft HOLD)

When several nations' fleets share one sea province, draw one marker per nation so each has its own clickable disk. Hit-test walks every `DemoUnitIcon_*` and uses the drawn plate radius for stacked sea-nation disks. Own disk → full own card; foreign disk → FLEET-1 read-only card (no Open fight / Assign; march blocked). Single-nation sea provinces keep `DemoUnitIcon_{pid}` at the same chip base. Köln FRA land-stationed fleet stays unselectable (MV-1b). FLEET-1 spill gate and MV-1b **unedited**.

**FIX #1 (Play MIXED `fd970599`):** production Channel `950001` holds ENG/ITA/POL/USA (not a single ENG pin). A horizontal row fanned over East Kent / Belgium; the old ENG chip `(4128.701, 926.218)` sat in the ITA/POL gap and spilled to GER Div 6. 3+ plates pack as a 2×2 / column, fit-radius + clamp to the sea polygon. Cluster AABB + ~9 screen-px pad picks the nearest plate and never nearest-own-land spill. Labels include the nation tag; SOV is not truncated to `SOV king_g.`.

**FIX #2 (Play FAIL `d742c583`):** FIX #1 centred/clamped on raw `get_province_geometry` (unscaled). Live `world_accurate` renderer centroids are ×THEATER_SCALE (~1.728): Channel `(7134.5, 1622.3)` / North Sea `(7195.9, 1336.9)`. The 2×2 parked over arctic Canada. `_sea_province_poly_world` now transforms + aligns to `province_centroids`; cluster >~2 plate spacings from chip base falls back to a chip-base 2×2. Drawn chrome matches the hit disk. Labels are `TAG Fleet N` including POL/USA/SOV. Guard (j) asserts cluster near **both** the live renderer centroid and the chip base, and fails if the cluster sits on unscaled geo. (g) uses live East Kent / old ENG chip / Channel centroid. Live-scale check: `tools/eoa_fleet2_live_scale_check.sh` (xvfb 1280×740, GER Europe Home, zoom ~1.5). Evidence `docs/evidence/fleet2_fix2/`.

Live-scale xvfb (GER Home, zoom 1.524, RSS **2033.9**, RESULT=PASS):

| sea | cluster (renderer) | Play centroid | d | plates (r=14.50, step=41) |
|---|---|---|---|---|
| Channel `950001` | `(7134.523, 1622.313)` | `(7134.5, 1622.3)` | 0.0 | ENG `(7114.0, 1601.8)` `ENG Fleet 2` · ITA `(7155.0, 1601.8)` `ITA Fleet 2` · POL `(7114.0, 1642.8)` `POL Fleet 3` · USA `(7155.0, 1642.8)` `USA Fleet 4` |
| North Sea `950000` | `(7195.852, 1336.935)` | `(7195.9, 1336.9)` | 0.1 | GER `(7175.4, 1316.4)` `GER Fleet 2` · FRA `(7216.4, 1316.4)` `FRA Fleet 2` · JAP `(7175.4, 1357.4)` `JAP Fleet 2` · SOV `(7216.4, 1357.4)` `SOV Fleet 4` |

East Kent `711453` / old ENG chip / Channel centroid → `ENG_formation_2` / ENG / fleet (not GER Div 6).

**FIX #2b (screenshots on `c9fd1c00` did not show plates):** North Sea Home was empty water at the centroid; Channel frames were the choke-diamond trio (Danish + Channel sea centroids), not a labelled 2×2; Channel camera sat over England. Plates now draw on `SeaNationFleetLayer` (`z=40`) above sea fill and overlay chokes. Inverse-zoom floor **0.66** keeps plates ~36–46 screen px; Home (`z<0.65`) spreads the 2×2 by drawn-body radius; compact 0.8 / 1.5 / 2.3 step is **45**. Click area = drawn NationPlate body (`max(half_w, half_h)+2`). Labels are two-line `TAG` / `Fleet N`. Pixel assert samples each logged plate screen centre and requires nation/NATO/label chrome (not sea / choke). Live-scale: `tools/eoa_fleet2_live_scale_check.sh` xvfb **exactly 1280×740**, GER Europe Home, Home + ~1.5 for Channel and North Sea. Evidence `docs/evidence/fleet2_fix2b/`.

Live-scale xvfb FIX #2b (GER Home, RSS **2145.6**, RESULT=PASS, uncropped 1280×740):

| sea / band | zoom | camera | cluster vs Play | r / hit / scale | plates world → screen |
|---|---|---|---|---|---|
| Channel Home | 0.318 | `(7134.5, 1645.9)` | `(7134.5, 1645.9)` vs `(7134.5, 1622.3)` d=23.6 | 14.50 / 64.67 / 2.712 | ENG `(7067.9, 1579.2)` `619,349` `ENG Fleet 2` · ITA `(7201.2, 1579.2)` `661,349` · POL `(7067.9, 1712.5)` `619,391` · USA `(7201.2, 1712.5)` `661,391` |
| Channel ~1.5 | 1.500 | `(7134.5, 1622.3)` | `(7134.5, 1622.3)` d=0.0 | 14.50 / 19.52 / 0.660 | ENG `(7112.0, 1599.8)` `606,336` `ENG Fleet 2` · ITA `(7157.0, 1599.8)` `674,336` · POL `(7112.0, 1644.8)` `606,404` · USA `(7157.0, 1644.8)` `674,404` |
| North Sea Home | 0.318 | `(7195.8, 1360.5)` | `(7195.8, 1360.5)` vs `(7195.9, 1336.9)` d=23.6 | 14.50 / 64.67 / 2.712 | GER `(7129.2, 1293.8)` `619,349` `GER Fleet 2` · FRA `(7262.5, 1293.8)` `661,349` · JAP `(7129.2, 1427.2)` `619,391` · SOV `(7262.5, 1427.2)` `661,391` |
| North Sea ~1.5 | 1.500 | `(7195.9, 1336.9)` | `(7195.9, 1336.9)` d=0.1 | 14.50 / 19.52 / 0.660 | GER `(7173.4, 1314.4)` `606,336` `GER Fleet 2` · FRA `(7218.4, 1314.4)` `674,336` · JAP `(7173.4, 1359.4)` `606,404` · SOV `(7218.4, 1359.4)` `674,404` |

Pixel samples: nation/NATO/label chrome present; choke=0 at all 16 plate centres. Live clicks 10/10: CH ENG/ITA/POL/USA opened read-only; NS GER own full card (`fight=true` `assign=true`); NS FRA/JAP/SOV read-only; East Kent `711453` `(7119.1, 1620.9)` + old ENG chip `(7134.5, 1610.3)` → `ENG_formation_2` (Channel fleet, not GER Div 6).

**PERF-2 (idle 6th-frame + wheel-notch, HOLD merge):** Shared-sea stack offsets cache by `(pid, count, radius)` so `_refresh_province_detail_visibility` does not rebuild Channel / North Sea layouts every 6 unpaused frames. Wheel schedule no longer double-calls `_refresh_terrain_zoom_light`. Capital-star theme px skipped when unchanged. `plate_label` logs on change only. Guard `HeadlessPerf2FleetRefreshBudgetTest` (offsets identical with/without cache; detail refresh < 80 ms; wheel notch < 100 ms). **FIX live star zoom:** Play MIXED on `b16b9b53` — wheel/Home only call `_sync_capital_star_scales` → `_capital_star_font_px` capped at 20, so Budapest/Belgrade stayed ~20 px at z=5.62 (0.00% vs main). The 18–36 clamp lived only on `_layout_zoomed_map_glyphs_for_province_node` (paused first-session never reaches that; `_refresh_province_detail_visibility` nests it under DetailOverlay.texture). Live `_capital_star_font_px` now applies the same 18–36 clamp above `OPERATIONAL_MAX_ZOOM` and `_sync_capital_star_scales` honors the wheel-measured zoom. Guard `HeadlessPerf2StarZoomPxTest` renders the real viewport at z=0.76 / 2.00 / 5.62 via `_refresh_terrain_zoom_light` and asserts on-screen star pixels (**FAIL** on `b16b9b53` / **PASS** on tip). Live recipe `docs/evidence/perf2/CLICKS.md`. FacilityIconLayer / MapZoomLOD / pick / TipDismiss / ORDERS / camera **unedited**.

Guard: `HeadlessFleet2SharedSeaMarkerTest` + `tools/eoa_fleet2_guard.sh` (hd + xvfb 1280×740). Seeds are real `world_accurate` label_anchors (production stationing):

| seed | pid | world |
|---|---|---|
| Maginot GER land / GER Div 6 | `710173` | `(4283.279411, 1010.266854)` |
| Köln (GER land; FRA fleet) | `710417` | `(4254.322147, 944.095861)` |
| East Kent (ENG coastal land) | `711453` | `(4119.875715, 938.028287)` |
| North Sea (GER/FRA/JAP/SOV) | `950000` | `(4164.266667, 773.688889)` |
| English Channel (ENG/ITA/POL/USA) | `950001` | `(4128.701206, 938.217996)` |
| old ENG Channel chip (pre-FIX #1) | `950001` | `(4128.701, 926.218)` |

Cases: (a) GER North Sea disk → GER fleet own card; (b) FRA North Sea disk → FRA fleet read-only card; (c) North Sea hit areas do not overlap and each centre picks its own fleet; (d) production Channel four plates, each centre picks its fleet (read-only for GER); (e) Köln FRA land-fleet still not selected; (f) Channel 4 plate centres each pick their fleet and lie over sea / clamp tolerance; (g) live East Kent `711453` / old ENG chip / Channel centroid pick a Channel fleet, **not** GER Div 6; (h) cluster-pad click between plates picks the nearest plate, not land spill; (i) labels are `TAG Fleet N` (POL/USA/SOV included; SOV not truncated); (j) cluster centres sit in renderer world near **both** the live centroid and the chip base — not unscaled geo / Canada; (k) all 8 plates at z0.318 and z0.40 open their fleet (GER own / others read-only); GER-nearest gap binds the fleet; East Kent / old ENG stay Channel; (l) a land/air drawn body inside the old FIX #3 pad opens **that unit**, and own GER cannot steal a neighbour body at z0.318. Headless + xvfb **NOT live Play**.

Guard FIX #2 (hd = xvfb, live-space fixtures): NS GER `(7175.352, 1316.435)` hit-r=17.5 · FRA `(7216.352, 1316.435)` · JAP `(7175.352, 1357.435)` · SOV `(7216.352, 1357.435)` · Channel ENG `(7114.0, 1601.8)` · ITA `(7155.0, 1601.8)` · POL `(7114.0, 1642.8)` · USA `(7155.0, 1642.8)` · dist=41.0 > r_sum=35.0 · CH cluster `(7134.5, 1622.3)` · NS cluster `(7195.852, 1336.935)`.

Isolated keep-green (FIX #2b tip; wrapper `rss_mb` preferred; MV-1/MV-1b **unedited**):

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| FLEET-2 hd / xvfb | both | PASS (a–j) | **1200.7 / 1342.1** |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1200.7 / 1335.9** |
| hd_mv1 | headless | PASS (unedited) | **1209.0** |
| hd_mv1b | headless | PASS (unedited) | **1208.9** |
| hd_rh1 | headless | PASS | **1209.1** |
| hd_ix1 (6) | headless | PASS (MandateGate PASS) | **1208.7–1209.2** |
| hd_rx1 (4) | headless | PASS | **1208.6–1209.2** |
| hd_rt1 (3) | headless | PASS | **1208.8** |
| xvfb_mv1 | xvfb | PASS | **2042.6** |
| xvfb_mv1_card | xvfb | PASS `fra=true` `edge_panel`/`edge_card`/`cap_commit` | **2042.4** |
| xvfb_rh1 | xvfb | PASS | **2034.4** |
| py_fac1a | py | PASS 7/7 | **0.082s** |
| hd_fac1a | headless | PASS | **1208.9** |
| xvfb_fac1a | xvfb | PASS stale_lag=true 15/15 lone+cluster rx1 0.843/0.843 | **2037.4** |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1200.5 / 1337.2** |
| Seeded RX-1 mid_river ON/OFF | xvfb | PASS units-off **0.749** / close 0.775 / spine 1.000 (FAC-1a 0.843/0.843) | wrapper exec (sibling xvfb ~2040) |
| UI-1 guard hd+xvfb | both | PASS | **1205.0 / 1348.6** |
| FLEET-2 live-scale xvfb | xvfb | PASS Home+1.5 plates visible; pixel chrome; 10/10 clicks | **2145.6** |

**FIX #3 (Play MIXED `b66c7724`):** Home-band own-land hit disk (up to ~320 world) stole spread plates below z0.65. Drawn sea-plate body wins first; cluster AABB binds the nearest sea plate (East Kent / old ENG / own-GER gap). Labels use the unit's per-nation ordinal, not stack `index+1`. Guard (k) clicks all 8 plates at z0.318 and z0.40 at live renderer coords. FLEET-1 / MV-1b **unedited**.

Live-scale xvfb FIX #3 (GER Home, RSS **2031.6**, RESULT=PASS, uncropped 1280×740):

| plate | fid | label |
|---|---|---|
| NS GER | `GER_formation_2` | GER Fleet 2 |
| NS FRA | `FRA_formation_2` | FRA Fleet 2 |
| NS JAP | `JAP_formation_2` | JAP Fleet 2 |
| NS SOV | `fielded_sov_21559591` | SOV Fleet 1 |
| CH ENG | `ENG_formation_2` | ENG Fleet 2 |
| CH ITA | `ITA_formation_2` | ITA Fleet 2 |
| CH POL | `fielded_pol_21560167` | POL Fleet 1 |
| CH USA | `fielded_usa_21558889` | USA Fleet 1 |

Clicks: all 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet (GER own card; others read-only). East Kent + old ENG → `ENG_formation_2`. GER-nearest gap → `GER_formation_2` own card. Evidence `docs/evidence/fleet2_fix3/`. Cases (a)–(k).

Isolated keep-green (FIX #3 tip; wrapper `rss_mb` preferred; MV-1/MV-1b **unedited**):

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| FLEET-2 hd / xvfb | both | PASS (a–k) | **1206.8 / 1341.4** |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1201.2 / 1340.5** |
| hd_mv1 | headless | PASS (unedited) | **1201.0** |
| hd_mv1b | headless | PASS (unedited) | **1201.1** |
| hd_rh1 | headless | PASS | **1200.8** |
| hd_ix1 (6) | headless | PASS (MandateGate PASS) | **1200.8–1205.4** |
| hd_rx1 (4) | headless | PASS | **1200.9–1202.5** |
| hd_rt1 (3) | headless | PASS | **1200.9** |
| xvfb_mv1 | xvfb | PASS | **2035.0** |
| xvfb_mv1_card | xvfb | PASS `fra=true` `edge_panel`/`edge_card`/`cap_commit` | **2036.5** |
| xvfb_rh1 | xvfb | PASS | **2038.7** |
| py_fac1a | py | PASS 7/7 | **0.092s** |
| hd_fac1a | headless | PASS | **1201.2** |
| xvfb_fac1a | xvfb | PASS stale_lag=true 15/15 lone+cluster rx1 0.843/0.843 | **2041.4** |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1201.1 / 1340.4** |
| Seeded RX-1 mid_river ON/OFF | xvfb | PASS units-off **0.749** / close 0.775 / spine 1.000 (FAC-1a 0.843/0.843) | sibling xvfb ~2040 |
| UI-1 guard hd+xvfb | both | PASS | **1205.6 / 1349.0** |
| FLEET-2 live-scale xvfb | xvfb | PASS 8 plates × 4 zooms; East Kent; old ENG; GER-nearest gap | **2031.6** |

**FIX #4 (Play MIXED `9c9c5f20`):** FIX #3 cluster AABB (centres ± hit_r + 9/z) stole land counters at z≤0.40; Home-band own GER stole neighbours just outside the box. **Option (a):** nearest drawn body (plate or land/air) wins — not shrink-to-drawn+4px. Gap bind is plate-centres AABB + 1u and only when no body is under the click; a land chip whose centre sits outside that hole cannot spill into East Kent / the old ENG chip. Below z0.65, own land/air hit is capped at **40 screen px**. Guard (k)+(l). FLEET-1 / MV-1b **unedited**.

Live-scale xvfb FIX #4 (GER Home, RSS **2030.0**, RESULT=PASS, uncropped 1280×740):

| click | z0.318 | z0.400 |
|---|---|---|
| ENG Div 0 / 1 | `ENG_formation_0` / `_1` | same |
| BEL Div 0 / 1 / 2 | `BEL_formation_0` / `_1` / `_2` | same |
| NLD Div 0 / 2 / AW3 | `NLD_formation_0` / `_2` / `_3` | same |
| FRA Garrison 4 | `FRA_formation_4` | same |
| Emden NLD / BEL AW3 / DNK AW3 | `NLD_formation_1` / `BEL_formation_3` / `DNK_formation_3` | same |
| coast `710374` / `710380` | `NLD_formation_1` (not GER AW3) | same |
| own GER Div 6 / 7 / Garr 4 / AW3 | own cards at 0.318 | — |

All 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet. East Kent + old ENG → `ENG_formation_2`. GER-nearest gap → `GER_formation_2` own card. Evidence `docs/evidence/fleet2_fix4/`. Cases (a)–(l).

Isolated keep-green (FIX #4 tip; wrapper `rss_mb` preferred; MV-1/MV-1b **unedited**):

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| FLEET-2 hd / xvfb | both | PASS (a–l) | **1203.2 / 1337.4** |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1203.5 / 1337.2** |
| hd_mv1 | headless | PASS (unedited) | **1202.2** |
| hd_mv1b | headless | PASS (unedited) | **1201.8** |
| hd_rh1 | headless | PASS | **1201.6** |
| hd_ix1 (6) | headless | PASS (MandateGate PASS) | **1201.6–1206.3** |
| hd_rx1 (4) | headless | PASS | **1202.1–1203.4** |
| hd_rt1 (3) | headless | PASS | **1202.0–1202.8** |
| xvfb_mv1 | xvfb | PASS | **2042.0** |
| xvfb_mv1_card | xvfb | PASS `fra=true` `edge_panel`/`edge_card`/`cap_commit` | **2043.9** |
| xvfb_rh1 | xvfb | PASS | **2039.5** |
| py_fac1a | py | PASS 7/7 | **0.080s** |
| hd_fac1a | headless | PASS | **1202.3** |
| xvfb_fac1a | xvfb | PASS stale_lag=true 15/15 lone+cluster rx1 0.843/0.843 | **2042.3** |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1201.9 / 1337.0** |
| Seeded RX-1 mid_river ON/OFF | xvfb | PASS units-off **0.749** / close 0.775 / spine 1.000 (FAC-1a 0.843/0.843) | isolated |
| UI-1 guard hd+xvfb | both | PASS | **1207.3 / 1347.0** |
| FLEET-2 live-scale xvfb | xvfb | PASS 8 plates × 4 zooms; East Kent; GER gap; Play land/air own units | **2030.0** |

**FIX #5 (Play MIXED `7f9e3ad0`):** 40 px own circle missed AW3 bars +46 / corner (→ CZE). Coasts `710374`/`710380` → NLD was a **regression**, not intended. Below z0.65, land/air hit is the painted rect (NationPlate 44×40 + StatBars 44×14 + Designation/TypeLetter/StrNum). Player-owned GIS land never opens a foreign chip stationed elsewhere. Own StatBars hit beats a nearer foreign plate. Guard (k)+(l)+(m). FLEET-1 / MV-1b **unedited**.

Live-scale xvfb FIX #5 (GER Home, RSS **2045.6**, RESULT=PASS, uncropped 1280×740):

| click | z0.318 | z0.400 |
|---|---|---|
| ENG Div 0 / 1 | `ENG_formation_0` / `_1` | same |
| BEL Div 0 / 1 / 2 | `BEL_formation_0` / `_1` / `_2` | same |
| NLD Div 0 / 2 / AW3 | `NLD_formation_0` / `_2` / `_3` | same |
| FRA Garrison 4 | `FRA_formation_4` | same |
| Emden NLD / BEL AW3 / DNK AW3 | `NLD_formation_1` / `BEL_formation_3` / `DNK_formation_3` | same |
| coast `710374` / `710380` | own GER spill (never NLD) | same |
| GER AW3 bars +46 / corner | `GER_formation_3` own | same |
| own GER Div 6 / 7 / Garr 4 / AW3 | own cards | own cards |

All 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet. East Kent + old ENG → `ENG_formation_2`. GER-nearest gap → `GER_formation_2` own card. Evidence `docs/evidence/fleet2_fix5/`. Cases (a)–(m).

Isolated keep-green (FIX #5 tip `a50cdeed`; wrapper `rss_mb` preferred; MV-1/MV-1b **unedited**):

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| FLEET-2 hd / xvfb | both | PASS (a–m) | **1208.6 / 1344.1** |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1202.8 / 1341.4** |
| hd_mv1 | headless | PASS (unedited) | **1203.0** |
| hd_mv1b | headless | PASS (unedited) | **1203.0** |
| hd_rh1 | headless | PASS | **1202.5** |
| hd_ix1 (6) | headless | PASS (MandateGate PASS) | **1202.4–1207.1** |
| hd_rx1 (4) | headless | PASS | **1202.4–1202.6** |
| hd_rt1 (3) | headless | PASS | **1202.4–1202.6** |
| xvfb_mv1 | xvfb | PASS | **2040.0** |
| xvfb_mv1_card | xvfb | PASS | **2044.6** |
| xvfb_rh1 | xvfb | PASS | **2033.2** |
| py_fac1a | py | PASS 7/7 | — |
| hd_fac1a | headless | PASS | **1202.8** |
| xvfb_fac1a | xvfb | PASS stale_lag=true 15/15 lone+cluster rx1 0.843/0.843 | **2047.8** |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1202.6 / 1337.9** |
| Seeded RX-1 mid_river ON/OFF | xvfb | PASS units-off **0.749** / close 0.775 / spine 1.000 (FAC-1a 0.843/0.843) | isolated |
| UI-1 guard hd+xvfb | both | PASS | **1207.4 / 1354.3** |
| FLEET-2 live-scale xvfb | xvfb | PASS 8 plates × 4 zooms; East Kent; GER gap; coasts never NLD; AW3 bars/corner own | **2045.6** |

**FIX #6 (Play MIXED `97d6ea45`):** ownership block too broad. Emden NLD east +20 / DNK AW3 bars +44 opened GER Garrison 4. Topmost painted body wins (plate, bars, or label). Ownership only in the halo (no painted body). Same-z: NationPlate interior > StatBars > plate rim > label, then nearest centre. Guard (n): Emden east +20 → `NLD_formation_1`; DNK bars +44 → `DNK_formation_3`. Keep coasts 710374/710380 halo/covered-by-paint and GER AW3 bars +46 / corner. FLEET-1 / MV-1b **unedited**.

Live-scale xvfb FIX #6 (GER Home, RSS **2031.4**, RESULT=PASS, uncropped 1280×740):

| click | z0.318 | z0.400 |
|---|---|---|
| ENG Div 0 / 1 | `ENG_formation_0` / `_1` | same |
| BEL Div 0 / 1 / 2 | `BEL_formation_0` / `_1` / `_2` | same |
| NLD Div 0 / 2 / AW3 | `NLD_formation_0` / `_2` / `_3` | same |
| FRA Garrison 4 | `FRA_formation_4` | same |
| Emden NLD / BEL AW3 / DNK AW3 | `NLD_formation_1` / `BEL_formation_3` / `DNK_formation_3` | same |
| Emden NLD east +20 | `NLD_formation_1` | `NLD_formation_1` |
| DNK AW3 bars +44 | `DNK_formation_3` | `DNK_formation_3` |
| coast `710374` / `710380` | covered_by_paint (hex under a painted body) | same |
| GER AW3 bars +46 / corner | `GER_formation_3` own | same |
| own GER Div 6 / 7 / Garr 4 / AW3 | own cards | own cards |
| Emden grid | 28 cells: 6 NLD_1 + 22 named topmost | 15 cells: 4 NLD_1 + 11 named topmost |

All 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet. East Kent + old ENG → `ENG_formation_2`. GER-nearest gap → `GER_formation_2` own card. Evidence `docs/evidence/fleet2_fix6/`. Cases (a)–(n).

Isolated keep-green (FIX #6 tip `d15ac739`; wrapper `rss_mb` preferred; MV-1/MV-1b **unedited**):

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| FLEET-2 hd / xvfb | both | PASS (a–n) | **1209.0 / 1340.7** |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1203.5 / 1344.5** |
| hd_mv1 | headless | PASS (unedited) | **1203.3** |
| hd_mv1b | headless | PASS (unedited) | **1203.3** |
| hd_rh1 | headless | PASS | **1203.1** |
| hd_ix1 (6) | headless | PASS (MandateGate PASS) | **1203.2–1207.7** |
| hd_rx1 (4) | headless | PASS | **1203.1–1203.3** |
| hd_rt1 (3) | headless | PASS | **1203.1–1203.3** |
| xvfb_mv1 | xvfb | PASS | **2040.8** |
| xvfb_mv1_card | xvfb | PASS | **2045.2** |
| xvfb_rh1 | xvfb | PASS | **2041.1** |
| py_fac1a | py | PASS 7/7 | — |
| hd_fac1a | headless | PASS | **1203.5** |
| xvfb_fac1a | xvfb | PASS stale_lag=true 15/15 lone+cluster rx1 0.843/0.843 | **2043.8** |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1203.3 / 1343.4** |
| Seeded RX-1 mid_river ON/OFF | xvfb | PASS units-off **0.749** / close 0.775 / spine 1.000 | isolated |
| UI-1 guard hd+xvfb | both | PASS | **1207.9 / 1353.7** |
| FLEET-2 live-scale xvfb | xvfb | PASS 8 plates × 4 zooms; East Kent; GER gap; Emden east +20 NLD; DNK bars +44 DNK; AW3 bars/corner own | **2031.4** |

**FLEET-2b (Play soft notes on FIX #6):** empty designation AABB cannot win (Heidekreis 710380 z0.40 never `NLD_formation_1`). `_world_in_unit_plate_or_bars` + glyph ink clipped to the plate. Inner face ~60% so StatBars over the outer rim win across more of the DNK AW3 strip; Emden centre / east +20 stay NLD. Removed `_foreign_land_air_blocked_on_player_hex` / `_province_owner_tag`. Guard (o)(p). FLEET-1 / MV-1b **unedited**. Same-nation piles unedited.

Live-scale xvfb FLEET-2b (GER Home, RSS **2037.5**, RESULT=PASS, uncropped 1280×740):

| click | z0.318 | z0.400 |
|---|---|---|
| ENG / BEL / NLD / FRA / Emden / DNK anchors | own unit (24/24) | same |
| Emden NLD east +20 | `NLD_formation_1` | `NLD_formation_1` |
| DNK AW3 bars +44 / ±4 | `DNK_formation_3` | `DNK_formation_3` |
| DNK AW3 bars ±8 | −8 NLD inner / +8 DNK_2 pile | both `DNK_formation_3` |
| DNK AW3 2 px sweep | 21/21 | 21/21 |
| Heidekreis `710380` | covered_by_paint DNK_2 | halo own GER/province (never NLD empty label) |
| NLD label-east | not NLD paint | local 28/32 halo; +40 px DNK_3 paint |
| GER AW3 bars +46 / corner | `GER_formation_3` own | same |
| own GER Div 6 / 7 / Garr 4 / AW3 | own cards | own cards |
| Emden grid | 28 cells: 8 NLD_1 + 20 named topmost | 15 cells: 4 NLD_1 + 11 named topmost |

All 8 plates at 0.318 / 0.40 / 0.80 / 1.50 opened their own fleet. East Kent + old ENG → `ENG_formation_2`. GER-nearest gap → `GER_formation_2` own card. Evidence `docs/evidence/fleet2b/`. Cases (a)–(p).

Isolated keep-green (FLEET-2b tip `c62d85b6`; wrapper `rss_mb` preferred; MV-1/MV-1b **unedited**):

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| FLEET-2 hd / xvfb | both | PASS (a–p) | **1209.1 / 1344.6** |
| FLEET-1 hd / xvfb | both | PASS (a–h, unedited) | **1203.7 / 1340.5** |
| hd_mv1 | headless | PASS (unedited) | **1203.5** |
| hd_mv1b | headless | PASS (unedited) | **1203.5** |
| hd_rh1 | headless | PASS | **1203.2** |
| hd_ix1 (6) | headless | PASS (MandateGate PASS) | **1203.2–1208.0** |
| hd_rx1 (4) | headless | PASS | **1203.2–1203.4** |
| hd_rt1 (3) | headless | PASS | **1203.2–1205.0** |
| xvfb_mv1 | xvfb | PASS | **2077.8** |
| xvfb_mv1_card | xvfb | PASS | **2043.9** |
| xvfb_rh1 | xvfb | PASS | **2042.4** |
| py_fac1a | py | PASS 7/7 | — |
| hd_fac1a | headless | PASS | **1203.9** |
| xvfb_fac1a | xvfb | PASS stale_lag=true 15/15 lone+cluster rx1 0.843/0.843 | **2047.2** |
| CRASH-1 10× hd + 10× xvfb | both | PASS | wrapper 10×+10× |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1203.4 / 1338.6** |
| Seeded RX-1 mid_river ON/OFF | xvfb | PASS units-off **0.749** / close 0.775 / spine 1.000 | isolated |
| UI-1 guard hd+xvfb | both | PASS | **1208.1 / 1347.4** |
| FLEET-2 live-scale xvfb | xvfb | PASS 8 plates × 4 zooms; East Kent; GER gap; Emden east +20 NLD; DNK ±4 DNK_3; Heidekreis z0.40 never NLD empty label | **2037.5** |

### ORDERS-1 Halt / Hold / Withdraw play-loop (draft HOLD)

From Begin GER 1936: land chip → March → **Halt march** (lower-left command button, not Assign); **Close inspector** if up; card **Open fight → Start battle** (no Ctrl) then **Hold** on the **upper** row paints **Hold ●** + toast `Stance: Hold`; **Withdraw** (upper row, not Halt) paints **Withdrawing · bounce tomorrow** / **Withdraw ●**. Halt already worked on `b9425e33`. Hold API forced Press (Array `in`). Same-day withdraw had no visible card state. **FIX #1:** Play MIXED `138a1f8a` at 1280×740 — stance clipped (`vp.y-252`); Withdraw beside Halt. Raise dock; Press\|Hold\|Withdraw above Halt. **FIX #2:** Play FAIL `aa6a08d4` never opened a fight (Ctrl intermittent; inspector covered the dock; Open fight click-through; Start empty-hex). Latch Open fight; hide inspector on card-up; Start only if `opened`. Play PASS `333a1285` live clicks: Close @(670, 85) then Open fight @(90, 564) / Start ≈(205, 548) / Hold ≈(157, 621) / Withdraw ≈(241, 621). Recipe `docs/evidence/orders1/CLICKS.md`. Guard: `HeadlessOrders1HaltHoldWithdrawTest` + `tools/eoa_orders1_guard.sh` (Open fight → Start banks Hold ● / Withdraw ●, 1280×740 visibility). Tip strip / TipDismiss / CLOSE-1 / CRASH-1 / PR #73 hit-disk **unedited**. COMBAT-1 follows. Headless + xvfb **NOT live Play**.

### COMBAT-1 fight resolve visibility (draft HOLD)

From Begin GER 1936: land chip → **Open fight → Start battle** (same PLAY_CLICKS as ORDERS-1) must open a **real** fight when a neighbor has defenders, then after unpause the player sees strength/Fill% move on chip/card plus a readable `Took …` / `Held at …` toast. Root: AAR toast sat inside `if open_n > 0` on `game_day_advanced`, which fires before `tick_open_land_battles`. Open fight first-adjacent could be empty Haut-Rhin. Product: notify `refresh_after_land_battle_day` after the existing tick; prefer `get_divisions_at_province` neighbor. Recipe `docs/evidence/combat1/CLICKS.md`. Guard: `HeadlessCombat1FightResolveTest` + `tools/eoa_combat1_guard.sh`. TipDismiss / ORDERS layout / chip hit-rank **unedited**. Headless + xvfb **NOT live Play**.

### CLOSE-1 card Close stale drag (draft HOLD)

Unit-card Close (`BtnClose` `ACTION_MODE_BUTTON_PRESS`) must not leave a live left-press / drag. Play `9c9c5f20` 19:35:44 / 20:04:17: after Close at (304,551) the next move to the top bar jumped the camera by −1.2× the mouse delta (`middle_mouse_pan_speed`); `97d6ea45` check 5: first top-edge pan after Close was 0 until one empty drag. **FIX #1 (Play MIXED `ce5d3304`):** first top-edge after Close must pan north **and** stay in theater clamp (z0.32 must not fly to cy≈−12384; z0.80 first try must not be `edgepan=0`). `_clamp_camera_to_theater` skips only while `_close_camera_locked`. `_consume_close_press_left_gesture` still clears leftover press/drag. UI-1 click-through skip-pick and CRASH-1 Halt latches stay. Guard: `HeadlessClose1StaleDragGuardTest` + `tools/eoa_close1_guard.sh` (clamp-while-guard + first-edge clamp). Windowed xvfb `tools/eoa_close1_windowed_check.sh` 1280×740 GER Europe Home: ≥20 Close→top-bar trials at zoom 0.32–1.5 including 0.32 and 0.80; first-move delta 0; first edge pans and `|dy|` / cam_y stay in `_apply_camera_bounds`. FLEET-1 / FLEET-2 / MV-1 / MV-1b **unedited**. Headless + xvfb **NOT live Play**.

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| CLOSE-1 hd / xvfb | both | PASS | **1204.3 / 1339.1** |
| CLOSE-1 windowed 1280×740 | xvfb | PASS first_move 20/20 · first_edge 20/20 clamped (z0.32 cam_y=1076 / z0.80=382) Close (304,523) | **2031.6** |
| Isolated keep-green (listed gates) | mixed | PASS FAILS=0 | see `docs/evidence/close1/KEEP_GREEN.md` |

### March dest pick at z 0.32 / 0.80 / 1.50 (draft HOLD)

Live smoke soft: selected own unit (GER Garrison 4) → click aimed at Heidekreis `710380` sometimes committed Harz / Börde at z~0.80 and the correct dest at z~1.50. Those dests are **not adjacent** to Heidekreis. A few-pixel product offset would land on a Lower Saxony neighbor. Guard: recompute a known GIS-interior screen at the current zoom and require dest=`710380` (plus Köln sanity). Stale z=1.50 screen reused at 0.80/0.32 is logged (harness hypothesis), not a product fail. MapRenderer pick / chip / spill / title / Fill% **unedited** unless a fresh interior misses. Headless `HeadlessMarchZoomDestPickTest` + `tools/eoa_march_zoom_pick_guard.sh`. Windowed xvfb `tools/eoa_march_zoom_pick_windowed_check.sh` 1280×740. Halt / CLOSE-1/1b / UI-1 / CRASH-1 / FLEET-1/2 **unedited**. Headless + xvfb **NOT live Play**.

| gate | kind | result | note |
|---|---|---|---|
| March zoom dest hd / xvfb | both | PASS dest=710380 at 0.32/0.80/1.50 | Köln 710417; stale → Mansfeld-Südharz / Zielonogórski |
| March zoom dest windowed 1280×740 | xvfb | PASS fresh 3/3 | screen 640,370; move_commit hops=8 days=11 |
| Isolated keep-green | mixed | PASS FAILS=0 | Halt 10×+10× · CLOSE-1 leftover 11/11 · first_edge 20/20 · UI-1 · FLEET-1/2 |

### CLOSE-1b first top-edge after Close dy=0 (draft HOLD)

Play soft on CLOSE-1 tip `008e5c30`: after some unit-card Closes the first top-edge push logged `edgepan≥2` but camera stayed (`dy=0`, cam0==cam1) at z≈0.32 and z≈0.80 (3/11). Retry later panned without an empty drag. Root: `_close_click_is_north_edge_strip` fell back to a stale/warped mouse at y=0 after the card hid; suppress stuck while the cursor stayed on the 6px rim; `_process` `_reassert_locked_close_camera` after `_handle_camera_input` snapped any delta. CLOSE-1 windowed first_move to y=20 had cleared suppress and hid it. Fix: button-only strip; `_close_click_was_north_strip`; first edge after a mid-panel Close must pan and not snap back. HUD Close that *was* on the rim still suppresses (Greenland leftover). Guard: `HeadlessClose1StaleDragGuardTest` leftover 11× z0.32/0.80 + `tools/eoa_close1_guard.sh`; windowed `tools/eoa_close1_windowed_check.sh` first_move 20/20 · first_edge 20/20 · **first_edge_direct 16/16** (Close→y=0, no y=20; half inject leftover suppress+GIS). FLEET-1 / FLEET-2 / MV-1 / MV-1b **unedited**. Headless + xvfb **NOT live Play**.

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| CLOSE-1b hd / xvfb | both | PASS leftover 11/11 + CLOSE-1 clamp | **1209.3 / 1348.0** |
| CLOSE-1b windowed 1280×740 | xvfb | PASS first_move 20/20 · first_edge 20/20 · first_edge_direct 16/16 (z0.32 cam_y≈1076 / z0.80=382.5) Close (304,523) | counts isolated (wrapper RSS overlapped HD) |
| Isolated keep-green (listed gates) | mixed | PASS FAILS=0 | see `docs/evidence/close1b/KEEP_GREEN.md` |

### CRASH-1 halt-march popup (draft HOLD)

Halt / Press / Hold / Withdraw / Assign must not `free()` `UnitDetailPopup` while `pressed` is emitting. Detach + rename `UnitDetailPopup_dying` + `queue_free()`. Same-dest still click is a no-op re-issue. **FIX #1 (Play live MIXED `80b0b542`):** press-mode rebuild dropped the card so the mouse-up still-clicked the map (inspector + camera jump; twice switched/cleared selection). Latch `_unit_card_consumed_press` on those five buttons; `_input` / `_unhandled_input` / `_left_release_must_skip_pick` / land-chip still-click swallow the matching release. Open card refreshes Halt on march start / re-target / arrival. **CRASH-1b (CH-1):** that latch must eat **one** matching left release then clear (new left press anywhere, 1 frame after the eaten release, 0.5s safety) so later top-bar / UI clicks register. Guard: Halt still no click-through; ≥4 UI press+release after swallow; following map still-click commits. Headless `HeadlessCrash1HaltMarchPopupTest` + `tools/eoa_crash1_halt_march_guard.sh` 10× hd + 10× xvfb — **NOT live Play**. MV-1 / MV-1b gates **unedited**.

### INPUT-1 close × must not click through to map (draft HOLD)

Notice/toast **×** and Command Center **✕** fire close on `pressed` (release) through the real Control. Leftover after overlay free is swallowed in `_unhandled_input` only. Armed on CC `button_down`, notice `button_down` (`show_toast` and `post_news` / `_show_toast`), and poll `handle_live_close_pointer` (`pending_press` for N+1). **FIX #2:** dropped dead `_unstick` / dying-× / MainMenu `_closing` hover exception / press-over-× early-return. Notice `button_down` arm kept — T3/T5 leftover after free **KILLS** M7b by Köln. **FIX #3 (tests only; product `977c9a84` unedited):** T1/T3/T5 also run on `post_news` News × (M7b-news); T6/T7 drive real `_process` poll; T10 leftover after CC free (fails main by Köln); T11 750 ms expiry must select (M9 stuck tick → pid=-1). Fixture NoticeClose so pure main fails by Köln, not setup. **FIX #4 (LeaderEventUI only):** after a user ×, the stacked survivor reflows under the cursor (Play MIXED `b64b98f3` at z0.9). `_user_close_toast` dismisses then IGNORE-passthroughs the stack until the pointer moves ≥6 px; poll skips IGNORE ×. T12a–c FAIL main/`b64b98f3` same-spot pid=-1 / PASS tip. T12d PASSes on main. Mutants M12a–d KILLED by selection. **FAIL** main `61a80433` T1–T7 + news T1/T3/T5 + T10/T11 leftover Köln / unit + T12a–c pid=-1 / **PASS** tip failures=0. Mutants **KILLED** by selection: M1, M2, M4b, M5, M5b, M5c, M6a, M7b, M7b-news, M9, M10, M12a–d. Wired `launch_input1_close_click` (no `EOA_HEADLESS_TOAST_UI`; no new gates line). `--quick` same 14 known reds. Recipe `docs/evidence/input1/CLICKS.md` step 5b. Headless + xvfb **NOT live Play**.

### BEGIN-1 Begin leftover release (draft HOLD)

Title **Begin** fires on press and `queue_free()`s the overlay. A normal ~80–150 ms mouse-up then still-clicked the map (Loir-et-Cher after Home at 1280×740 ~284,580): inspector + soft click-zoom ~0.776→0.900. Instant 0 ms release did not. Product: TipDismiss-style one-shot swallow of the leftover left release, armed on pointer Begin only (keyboard Enter/Space/B must not eat the next map click). **FIX #2 (code SHA `f18a341a`; later commits test/docs only):** clock starts on the first `_process` after the Begin frame (restamp); expiry only after that restamp and frames >= arm_frame + 2. Poll-path `handle_live_pointer(null)` sets `begin_press_pending` so the click's own N+1 press keeps the arm. Event-path keeps the same-frame rule. **FIX #3 (test-only):** leftover / follow-up go through `_title._input` + same-frame `Input.parse_input_event` + `flush_buffered_events` (direct `_mr._input` leftover does not pick on main). T1 FAIL on main (Loir `710671`) / PASS on tip. T2 later click picks (M2). T3 poll 1000 ms + 3 frames then first click (M1). T4 same-frame 900 ms release N+2 swallowed (M7). T5 keeps (b); M3 outside-button leftover; M9 no T1–T5 behavior difference. Guard `HeadlessBegin1TitleReleaseFallthroughTest` + `tools/eoa_begin1_guard.sh`. **FIX #4 (gate wiring only):** `tools/eoa_full_test_gates.sh` `run_step launch_begin1_title_release` after `launch_ix1_title_esc_begin`. Code SHA remains `f18a341a`; later commits are test / docs / gates only. TipDismiss / camera / edge-pan / labels / fleet / unit pick **unedited**. Recipe `docs/evidence/begin1/CLICKS.md` (pre-step `timeout 1500 tools/run_godot.sh --headless --path . --import --quit`). Headless + xvfb **NOT live Play**.

### WHEELDRIFT-1 wheel zoom + rim edge-pan (draft HOLD)

Play (`d4a3a1ff`): wheel-only kept the point under the cursor (0 px), but in ×1.243 / out ×0.757 so 5 in + 5 out left the view ~26% further out. A cursor on the right/top/bottom rim (~3–4 px) edge-scrolled at ~1000 px/s; a wheel notch cleared `_close_suppress_edge` so zoom-at-the-edge flew the camera. Left rim at Home did not pan (theater clamp / 6 px strip). 15 px in did not pan (UI-1 strip, not the unused 64 px `edge_margin` export).

Product (MapRenderer only, off main `61a80433`): `_zoom_toward_mouse(factor, event.position)` — clamp zoom, correct the world point under the event, then `_clamp_camera_to_theater` (no re-anchor). In/out are `factor_in` / `1/factor_in`. Every wheel notch arms a 350 ms edge hold + 150 ms strip dwell so EDGE-1 pan cannot run during the wheel. MapViewInput 6/10 px strips and edge speed **unedited**.

Guard `HeadlessWheelDrift1Test` (fixture, not WorldMap.tscn / 3520):

- **T1** BR rim, 10 in + 10 out: `_nav_edge_pan_frames` during wheel + 350 ms = 0 (`no_wheel_suppress`, `edge_ignores_hold`). After the hold, a strip dwell still pans (`suppress_forever`).
- **T2** off-center (960,555), 10 in + 10 out: ≤2 px per notch after a process frame (`no_anchor_correction`); zoom+camera round-trip; clamp-bind zoom-out must not runaway (`clamp_before_anchor`).
- **T3** event.position ≠ warped viewport mouse: anchor follows the event (`anchor_from_viewport_mouse`).
- **T4** UI-1 rest (97,731), EDGE-1 L/R/T/B helpers, CLOSE-1b `_close_suppress_edge`, FAC-1a `event.position` pick, Vis1 harness present.

Must **FAIL** on main MapRenderer and **PASS** on this tip. Recipe `docs/evidence/wheeldrift1/CLICKS.md`. CameraController / GameData / TipDismiss / ORDERS **unedited**. Headless + xvfb **NOT live Play**.

### EDGE-2 calm rim pan (draft HOLD, stacked on #105)

Probe on WHEELDRIFT-1 `b7affe58`: cursor on the right rim starts pan ~0.5 s after the last wheel notch then runs at full speed instantly (~2200–2600 screen px/s ÷ zoom; ~3× world at Home ~0.33). No dwell outside the post-wheel window, no ramp, no far-zoom cap. Left rim never pans: `edge_pan_direction_at` is symmetric, but `edge_pan_blocked_by_gui` / `hovered_ui_blocks_edge_pan` treat MapModeToolbar / legend / left-docked InfoPanel / minimap as blockers (UI-1 TopInfoBar exemption is north-only), and `_mouse_over_map_chrome_blocks_edge_pan` skipped only the north 6px strip.

Product (MapRenderer nav block + MapViewInput HUD exemption; off `b7affe58`): 250 ms continuous rim contact before any pan; speed ramps 0→full over ~600 ms of contact (reset on leave); below Home zoom 0.33 do not scale world speed by 1/zoom past Home; left HUD exempt **only** in the UI-1 6px left strip (toasts / unit cards / Leaders still block). WHEELDRIFT-1 350+150 and 6/10 px strips **unedited**.

Guard `HeadlessEdge2RimFeelTest` (fixture, not WorldMap.tscn / 3520):

- 0 px panned before 250 ms dwell (`no_dwell`)
- distance at 0.3 s of contact < 25% of full-speed distance (`no_dwell` / `no_ramp`)
- far-zoom world speed capped at Home (`no_cap`)
- left-rim direction non-zero with HUD present (`left_blocked`)

Must **FAIL** on `b7affe58` and **PASS** on this tip. Recipe `docs/evidence/edge2/CLICKS.md`. CameraController / GameData / TipDismiss / ORDERS **unedited**. Headless **NOT live Play**.

### EDGE-1 first-session edge-pan feel (draft HOLD)

Play 1280×740: far-right hover ≈x=1270 (incl. top-right corner y≈1) missed while left/top/bottom panned. **Proven:** UI-1 6px strip starts at `x >= 1274`. Existing `MapViewInput` adds `EDGE_PAN_RIGHT_SCREEN_PX=10`; other rims stay 6px so (97,731) still rests. Toast hover still blocks. Close-held north-strip suppress kept. Home framing unedited. Toast-before-drag / large-drag-south hunches not reproduced. Guard: `HeadlessEdge1CameraFeelTest` + `tools/eoa_edge1_guard.sh`. Recipe `docs/evidence/edge1/CLICKS.md`. TipDismiss / ORDERS layout / chip hit-rank **unedited**. Headless + xvfb **NOT live Play**.

### UI-1 Leaders close + edge pan + no march inspector (draft HOLD)

**FIX #1 (Play MIXED `0ded8c49`, tip `eb6544a8`):** TopInfoBar is exempt from the UI-under-cursor block **only** inside the north `0..EDGE_PAN_SCREEN_PX` strip (y=0/1 pans north at any x). The rest of the bar stays non-panning. Toasts / Leaders / unit card / pause menu still block via hover, including when they touch that strip. Unfocused still skips. Leaders Close acts on release and swallows the mouse-up (no leftover map pick). Edge-pan speed unchanged. Guard: y=0/1 at x=10/640/1270 north; ~3–4px below strip no pan; toast-on-strip no pan; prior no-pan points; Close press+release no inspector/select. MV-1/MV-1b **unedited**. Headless + xvfb **NOT live Play**.

Live Play 1280×740: Leaders 1440×800 left Close off-screen; Esc opened Command Center; Close clicks did nothing. Edge-pan fired at top y≈200–264 and bottom y>705 (64px HUD-offset strip); rest at (97,731) scrolled to Antarctica; right-edge toast panned. March commit opened the destination inspector behind the unit card.

Fixes: clamp Leaders to viewport−16px and re-fit on resize; Close is not on the drag handle and `close_screen()` actually frees; Esc dismisses Leaders in `_input` + `MapRenderer._handle_escape_key` (consumed, no CC). Edge pan is `MapViewInput.EDGE_PAN_SCREEN_PX` (6) in **window** pixels; `hovered_ui_blocks_edge_pan` / unfocused / mouse-outside skip. March sets `_skip_inspector_after_march` and does not `_select_province` the dest. CRASH-1 same-dest no-op + CH-1 MV-1e event-position dest kept.

Guard: `HeadlessUi1LeadersEdgePanMarchTest` + `tools/eoa_ui1_guard.sh` — 1280×740 and 1920×1080 panel+Close inside viewport; Close click and Esc each close (no MainMenu, map nav restored); edge rest at (97,731)/y=230/y=710/toast no camera move; x=1279 and y=0/1 at x=10/640/1270 pan (top-bar exempt); ~3–4px below strip no pan; toast-on-strip no pan; Close press+release no map click/select/inspector; select unit + march → inspector not visible, selection kept. MV-1 / MV-1b **unedited**. Headless + xvfb **NOT live Play**. Seeds: Borken `710430` L1 / Warendorf `710434` L2 / Ober `710423` L3 / Siegen-Wittgenstein `710451` L4.

Isolated keep-green (`eb6544a8`; wrapper `rss_mb` preferred; hd Godot ~1195, suite sampler ~2390 was pgrep double-count):

| gate | kind | result | peak RSS MB |
|---|---|---|---|
| hd_mv1 | headless | PASS (unedited) | **~1195** |
| hd_mv1b | headless | PASS (unedited) | **~1196** |
| hd_rh1 | headless | PASS | **~1195** |
| hd_ix1 (6) | headless | PASS (MandateGate `PASS failures=0`) | **~1196** |
| hd_rx1 (4) | headless | PASS | **~1197** |
| hd_rt1 (3) | headless | PASS | **~1196** |
| xvfb_mv1 | xvfb | PASS | **2032.8** |
| xvfb_mv1_card | xvfb | PASS `edge_panel`/`edge_card`/`cap_commit` | **2034.3** |
| xvfb_rh1 | xvfb | PASS | **2031.4** |
| py_fac1a | py | PASS 7/7 | **9.7** |
| hd_fac1a | headless | PASS | **~1197** |
| xvfb_fac1a | xvfb | PASS stale_lag=true 15/15 lone+cluster rx1 0.843/0.843 | **2040.5** |
| CRASH-1 10× hd + 10× xvfb | both | PASS (CRASH-1b latch clear included) | ~1.2 GB/run (sampler 2719 inflated) |
| MV-1e 15/15 @ 4× | hd+xvfb | PASS | **1196.9 / 1330.4** |
| Seeded RX-1 mid_river ON/OFF | xvfb | PASS units-off **0.749** / close 0.775 / spine 1.000 | leftover 4073 (typical isolated ~2046) |
| UI-1 guard hd+xvfb | both | PASS | **1200.4 / 1347.4** |

### CH-1 / MV-1e stale hover commit (draft HOLD)

At 4×, a still click commits to whatever is under `event.position`. A facility icon at that point wins. A miss uses `_resolve_hex_pick_pid` and does not keep `_march_preview_cache_dest` or the hover province (FIX #8; the old miss-of-icon cache-dest stay is gone). `_mv1_preview_dest_matches_world` still checks the facility before the hover symbol, and a GIS miss does not match the stale hover. Hover/preview update logic unchanged. Guard `HeadlessCh1Mv1eStaleHoverCommitTest` + `tools/eoa_ch1_mv1e_stale_hover_guard.sh`: same-frame motion X (Köln) then press/release Y (Leverkusen), 15/15, lone unit, hd+xvfb. FIX #8 measured hd+xvfb **PASS** rss **1212.0 / 1657.1** — **NOT live Play**. Live pair was Bad Kreuznach vs Hildesheim. Seeds unchanged: Borken `710430` L1 / Warendorf `710434` L2 / Ober `710423` L3 / Siegen-Wittgenstein `710451` L4.

### RT-1 Readable road tiers (intact, visual only, draft HOLD)

Pure helpers in `scripts/map/RoadTierVisual.gd` (FIX #2 trunk; FIX #3 12 px non-AA highway quads + Köln label). Headless: `HeadlessRt1RoadTierForEdgeTest` (1936 3/6/9 + eras + explicit⇒highway + Europe LOD + trunk forest / 0 triangles + mid highway + Köln label) + `HeadlessRt1RoadEdgeFilterTest` (Bonn–Köln / Köln–Leverkusen must-draw; Köln–Essen / Köln–Düren must-not) + `HeadlessRt1RoadNoRebuildTest` (zoom/pan 0 rebuilds; one `infrastructure` notify → +1). Windowed seeded `tools/eoa_rt1_pixel_guard.sh` (3×3 + S1/S2) uses the player camera path (no `lock_pixel_guard_camera`). Windowed **live-look** `tools/eoa_rt1_live_look_guard.sh` does **not** seed infra: Europe Home → Search/Go Köln → `_zoom_toward_mouse` at **1600×900**; triangle/mesh density; **highway width > paved** at mid+close; **mid gold ≥ 1.8× highway** (close gold 16/20 unchanged); sage-web frac ≤ 0.035 (no `5c60f366` pale-green carpet). `ProvEdge_` hide is **not** in this slice (borders needed for pick; tan cells backlog). S2 Bonn/Köln/Leverkusen at mid+close. xvfb ≠ product Play. Live −12% road move bonus is unchanged.

### HWY-1 / HWY-2 mid-zoom highway corridors (draft HOLD)

Per-edge rank in `assign_rare_display_tiers` painted the top ~4% of trunk edges as isolated stubs. HWY-1 kept the same budget `ceil(n*(1-0.96))` but seeded the heaviest inferred edges and grew along shared-endpoint trunk neighbours. **HWY-2** grows to **max 6** (min 3): blob until length 3 (star spokes), then **endpoints only** so a heavy hub walks a corridor. Continuation may use typical trunk weight (`HWY1_GROW_WEIGHT_FLOOR` 7) so NUTS3 ~10.1 hops can join; dirt tails (~2) stay out. Leftover budget extends existing corridor endpoints (no new stubs). Explicit IX-1 edges stay highway. FIX #1 cost path kept (int-key sort + index adjacency). `select_trunk_edges` / LOD / gold spine **unedited**. Casing: far **12** / mid **12** / close **16** px.

Guard `HeadlessHwy1HighwayChainTest` Part A (5-chain line, star 3-spokes, two 5-clusters, explicit 4-chain, nondet) + Part B live 1936: median **≥4**, **0** singletons, **≤12** components, highway count ±10%, Ruhr ordered pids measured (no assign whitelist). **Must not call `_hwy1_*` statics**. Timing median of ≥5 vs legacy rank. Wired as `launch_hwy1_highway_chain`.

Pixel: `WindowedRt1RoadTierPixelGuard` measures the **fixed** `710412–710424` pair at far/default/close (no `_measure_best_highway` re-pick). Fail if a sample is **<8 px**. Highway mins: far **≥9**, default **≥12**, close **≥16**. Far may Y-flip the same pair when unflip <8 (viewport image vs canvas; cap 8–48 px). Measured tip: far **40** / default **17** / close **20**. Screenshots `docs/evidence/hwy2/`. **Headless + xvfb, live Play pending.**

### HWY-3 hub-route display highways (draft HOLD)

Display highways are **trunk shortest paths between hubs** (capitals, largest cities, significant ports). Urban-district neighbour count is an **optional weight** only. Rank-and-grow stays as a fallback for synthetic Part A (no hub records) and as the `rank_grow_back` mutant. Each accepted route is a **simple path** (no repeated vertex, no >150° hook-back, length ≤1.6× hub chord, zigzag ≤1.5π per 6 edges). FIX #1 paints one tree per large country; budget is **2× of 52** (60–114). 0 singletons, median ≥4. Far highways keep casing/core + 20 px floor so the wide Germany frame shows routes; dirt/paved stay culled.

Guard `HeadlessHwy3HubRouteTest` H1–H6 + named mutants (`rank_grow_back`, `no_capitals`, `urban_required`, `zigzag_ok`, `hook_back`, `not_shortest`, `far_hidden`, `flip_max`, `pid_list`, `overlap_ok`). Those eight product env branches are **deleted**; tests load in-memory source-edits (same pattern as `second_zero`). Wired as `launch_hwy3_hub_route`. FIX #6 tip `b33daba1`: gold spine z=25 above highways 24 so pixel `s1_gold_cover=1.000`; metro casing stays inside far/default ceilings 26/18 (measured far **21** / default **12** / close **21** on `710401–710412`); Ruhr labels place then offset-cull (hub>other, camera-center ties, Cologne/Köln alias). Essen xvfb z2.4 `Düsseldorf, Duisburg, Mülheim an der Ruhr`; z4 those plus Dortmund; no overlapping rects; one Köln; no-cull mutant FAIL. Trim named **Lyon → Isère → Drôme → Vaucluse → Marseille** (kind=1, not a focus trunk). FIX #4: capital connects to the top-2 hubs by score in distinct bearing sectors (≥90°). Live-path guard `HeadlessHwy3LiveScenarioTest` **RESULT=PASS** on ScenarioLoader `world_accurate` (same city layer as TestScenario/Begin): Rome-north `Milan → … → Rome`; Ruhr **3/3** Duisburg/Essen/Dortmund; Paris one north Lille; **THE count** live **drawn=114**. Env `json_layer` / `no_second_sector` **removed**; source-edit on `_hwy3_reachable_sectors` (`second=0`, token `second_zero`) kills Rome-north. Wired as `launch_hwy3_live_scenario`. FIX #5 Ruhr live-legibility: hub labels z≥2.0, metro casing ≥1.3×, highways z=24 above Rhine 22. Guard `WindowedHwy3RuhrLegibilityGuard` / `tools/eoa_hwy3_ruhr_legibility_guard.sh` (wired `launch_hwy3_ruhr_legibility`): Essen `(7356, 1606)` z2.4 casing **272** px / 3 labels (`Düsseldorf, Duisburg, Mülheim an der Ruhr`); z4 **466** px / 4 labels (+ Dortmund); no overlapping rects; labels-off, under-river, and no-cull mutants killed; **RESULT=PASS**. HeadlessHwy3 **RESULT=PASS** **113**/8/0/median **12.00** (same drawn definition; JSON vs ScenarioLoader is the 1-edge gap). Lowest-score non-trunk spans trim first so live count stays ≤114. **FAIL** on d4a3a1ff (5: pid_list / flip_max / H1 rank-grow / H2 empty) / **PASS** on FIX #1 tip (114/9/0/median 8.00, Munich+Essen+GER tree). FIX #2 (g100e) **HeadlessHwy3 RESULT=PASS**: H3 **hook-back trap** (double-back >150°); every major capital connects to its 2nd hub (ITA Rome–Milan `710882–710963`); no two routes share both end regions with Hausdorff cover >45% within 12 wu (one-end forks 75% both-way); Ruhr urban-span **4/5** Duisburg/Essen/Bochum/Dortmund (kreisfreie scoring, no pid whitelist); Munich–Frankfurt on a SPAN. Live **114**/9/0/median **10.00**; `dropped_cap=80` `dropped_parallel=6`. FIX #3: no route pair may have Jaccard ≥0.5 or share an endpoint plus ≥50% of either province set (Paris–Nord / Nord South–Paris j=0.67 dropped; FRA trunk `710707–710734` kept). Independent assert; `overlap_ok` disables the drop and is killed. Routes 20→18. Budget stays **60–114**. Pixel: **one fixed orientation** (`HWY3_FIXED_ORIENTATION=1`), hub-route pair `710401–710412`, far **21** / default **12** / close **21** (mins 9/12/16; ceilings 26/18). `s1_gold_cover=1.000`. Wide-Germany **18** hub-route runs ≥9 px (main/d4a3 → 0). `--quick` 14 known unit_board_play_path reds; map_qc NE **0.9853**. Shots `docs/evidence/hwy3/`. `select_trunk_edges` / `road_tier_for_edge` / GameData == d4a3a1ff **unedited**. **HOLD merge.**

**FIX (L-off supply-toggle cache):** Hub routes do not depend on L / supply mode. `InfrastructureOverlayLayer` caches the HWY-3 result (hubs, routes, marked keys, trimmed_routes, display tiers) on era + owner/infra + built roads + city source. A supply toggle re-applies only the corridor styling pass (no adjacency walk, no routing). Guard `HeadlessHwy3SupplyToggleCacheTest` **RESULT=PASS**: (a) on/off/on left route-compute at 3 and highway keys **114** identical; (b) Köln infra 5→8 recomputed 3→4; (c) glow=1 corridor_flag=true. Source mutants `ignore_infra` (1→1) / `bypass_toggle` (2→4) / `skip_styling` (glow=0) kill (b)/(a)/(c). LiveLonProbe **RESULT=PASS** load_ms=**274.12**: run1 off_frame2=**8.65** on_warm=**11.94**; run2 **8.55** / **11.84** (bars ≤350 / ≤300). Hub3 **PASS** 113/8/0/median 12.00; Hwy1 **PASS** 113 marked; Hwy3LiveScenario **PASS** drawn=114 routes=18 Ruhr 3/3; RT1 trio **PASS**; Perf3 **PASS** Home 146.2/9.2/371.4 z0.760 55.0/9.2/54.9 roles=1 setups=0 line2d=0; pixel **PASS** gold **1.000** far/default/close **21/12/28**. `--quick` 14 known reds; NE **0.9853**. GameData `8c1d5e9f` ×3; live-fn `e6b869f8` ×3; prompt `20fe9063` absent. Wired `launch_hwy3_supply_toggle_cache` + `launch_live_lon_probe`. MapRenderer L toggle / RENDER-1 rings / rivers **unedited**. **HOLD merge.**

### RX-1 Rhine Crossing (Phase B draft)

Pure product `test_rx1_rhine_crossing_product` is on `--quick`. Headless: `HeadlessRx1RhineCrossingTest` (edge penalties, shared-border guard, Build Bridge complete) + `HeadlessRx1RhineLiveStayAliveTickTest` (FIX3 calendar tick: 0% → >0 in ~5d → COMPLETE via `advance_real_time`) + `HeadlessRx1RhineVisibilityTest` (FIX1: Rhine/road z > DemoUnitIcon 28; spine chrome absent on Neuss). Windowed smoke `tools/eoa_rx1_bridge_live_progress_guard.sh` sets `EOA_SMOKE_RX1_LIVE_PROGRESS=1` and presses **Build Bridge** on Neuss `710413`. The smoke harness is **not** the product. IX-1 spine tests stay green and unchanged. `run_godot.sh` one-time `--import` when the class cache lacks `Rx1RhineCrossing`.

### VIS-2 capital stars after L supply cycle (draft HOLD)

L on then L off at operational zoom left capital stars in the tree but not drawn: `_layout_zoomed_map_glyphs_for_province_node` (via `_sync_supply_route_canvas_stack` on L toggle) set `z_index = Z_MAP_GLYPH + 2` (10) without restoring the idle capital layer (`z=40`, `z_as_relative=false`). A later map-mode switch re-asserted z=40. Guard `HeadlessVis2CapitalStarsAfterLTest` seeds product stars via `_add_capital_star_to_node` on a small MapRenderer fixture (not WorldMap.tscn / 3520), drives L on/off at z=0.760, and asserts effective draw z≥40 (not merely `visible=true`). Must FAIL on main `425b4448` (stars left at glyph-stack z=10) and PASS on this branch. Wired on the full gate as `launch_vis2_capital_stars_after_l`. L-on glyph look, Home / Shift+Home hide, labels, FacilityIconLayer, pick, TipDismiss, ORDERS, camera, fleet memo **unedited**. Headless **NOT live Play**.

### ORIDIOM-1b march hop_days terrain/kind `or` (draft HOLD)

`FormationMovement.hop_days` must strip/lower the real `terrain` / `template_kind` strings. GDScript `or` returns a bool, so `str(terrain or "plains")` and `str(template_kind or "infantry")` both became `"true"` on main `61a80433` (every terrain cost 1.0; mountain-infantry discount and armour mountain penalty never fired). Empty terrain still falls back to plains; empty kind now falls back to infantry.

Guard `HeadlessOrIdiom1bMarchCostTest` (full gate `launch_oridiom1b_march_cost`):

- **B1** `hop_days(t, 0.5, INFANTRY_SPEED, k)` within 1% of py `unit_own_land_march_product.hop_days` for t ∈ {plains, hills, forest, desert, urban, jungle, marsh, mountain} × k ∈ {infantry, mountain_infantry, armor, motorized}. Mountain/infantry = 1.8× plains. Must FAIL on `61a80433`.
- **B2** empty terrain/kind default to plains/infantry.
- Killing asserts: `b1_matrix_within_1pct` · `b1_mountain_infantry_1_8x_plains` · `b1_mountain_infantry_discount` · `b1_armor_mountain_penalty` · `b2_empty_terrain_defaults_plains` · `b2_empty_kind_defaults_infantry` · `src_no_terrain_or` · `src_no_template_kind_or`.

Keep-green: `HeadlessMv1MarchPreviewTest` (ETA-1 preview==commit) · `HeadlessCombat1FightResolveTest` · py `test_unit_own_land_march_product`. `--quick` same 14 known `unit_board_play_path` reds; `map_qc` NE hit 0.9853. Seed 193601 HeadlessPerf4LiveMultiAiDayTest locked infra picks (JAP 903951 / FRA 710739 / ITA 710859 / POL 711054 / ENG 711481 t6+t7 / USA 800075 / SOV none / md5 20fe9063) — STOP and do not re-record if any locked pick changes. Fence: `FormationMovement.gd` hop_days l.52–55 + this guard + docs. No GameData / new duals / world_full ID / Godot bump. Headless **NOT live Play**.

### VIS-1 first-session map readability (draft HOLD)

Paused Home left capital stars at their last close-zoom font (tiny 3–6 px dots at Europe Home). L on then L off left yellow `SupplyOutline` rings. Product tip `2df6d4ba` is unchanged by FIX #1. Guard `HeadlessVis1MapReadabilityTest` drives pause + close zoom + real Home / Shift+Home / L through the viewport (`Input.parse_input_event` + `flush_buffered_events`, not `_input` / `_unhandled_input`) on a small MapRenderer fixture (not WorldMap.tscn / 3520). Asserts stars hidden at Home and Shift+Home (`z ≤ STRATEGIC_MAX_ZOOM 0.55`, 0 stars after close zoom with 8 visible) and no visible SupplyOutline after L off. Wired on the full gate as `launch_vis1_map_readability` next to `launch_rx1_visibility`. Measured: main MapRenderer **FAIL failures=6**; tip **PASS failures=0**. Must FAIL on main `425b4448` MapRenderer (≥6 FAILs: source needles + Home stars + Shift+Home stars + L-off outlines) and PASS on this branch. Behavior-only (`EOA_VIS1_BEHAVIOR_ONLY=1`) mutants: (a) no Home sync at `center_europe_in_world_view` ~16516; (b) no Shift+Home sync at `_apply_home_key` ~2547; (c) Home sync behind `if false`; (d) no previous-pid hide loop in `_refresh_supply_highlights` ~29097–29110; (e) hide loop after the clear. All five must FAIL by behavior even with source-text needles gone. L-on still walks current roles; L-off hides only previous role pids (hang-class: no 3520 walk when overlay is already empty). Camera / edge-pan / pick / labels / FacilityIconLayer / TipDismiss / ORDERS **unedited**. Headless **NOT live Play**. 
