# EOA — Game Director Plan (phases + agents → full-test world-class)

**Date:** 2026-08-12 (keep-going board · reconciled to live SNAPSHOT · board ~3520)  
**Role of this doc:** Single **orchestration** board for implementer agents and human director sessions.  
**Status truth:** [`GAME_STATUS_SNAPSHOT.md`](GAME_STATUS_SNAPSHOT.md) · **always win** if this file disagrees  
**Keep-going (this DAG):** SNAPSHOT §0 · [`FORWARD_PROGRAM_2026_08_12.md`](FORWARD_PROGRAM_2026_08_12.md) · residual [`EOA_RESIDUAL_PRIORITY_BOARD.md`](EOA_RESIDUAL_PRIORITY_BOARD.md)  
**Map as living star (HOI4/V3 structure review):** [`WORLD_CLASS_MAP_REVIEW.md`](WORLD_CLASS_MAP_REVIEW.md)  
**Long program (no permanent deferrals):** [`MASTER_COMPLETION_PLAN.md`](MASTER_COMPLETION_PLAN.md) — catalogue only; SNAPSHOT wins  
**Human play:** [`PLAYTEST_AND_DECISION_GUIDE.md`](PLAYTEST_AND_DECISION_GUIDE.md)

---

## 0. North star (full-test readiness)

A **great full-test state** is when:

| # | Exit |
|---|------|
| 1 | Default F5 loads **`world_accurate`** (~3520) without SCRIPT ERROR |
| 2 | Map integrity machine gates stay green (QC + unit tests) |
| 3 | Majors have **leaders, capitals, basic OOB** on accurate IDs |
| 4 | Player can run **produce → equip → stage → assault** on accurate board |
| 5 | Political/mapmode readability over 20–60 days without freeze |
| 6 | Docs + agents share one phase board (this file) |
| 7 | Map is the **interaction star**: hierarchy readable; resources/states/supply mapmodes usable; density feels good (see WORLD_CLASS_MAP_REVIEW) |

**Out of scope for “full-test ready”:** finished multiplayer product, HOI-depth designers, 13k provinces, museum borders, full V3 markets/pops.

**Map truth:** Default board already has province→state→strategic-region data + GIS hybrid + multi-front live assaults + **M0–M5** (regions, mapmodes, corridor **G**, FPS samples p50/p95). Remaining map-star work is **human campaign notes (M6)**—not GIS renumber.

---

## 1. Agent roster (roles)

Use **one agent role per session** (or parallel only if files don’t thrash). Copy the **entry prompt** at session start; stop when **exit criteria** pass.

| Role ID | Owns | Entry prompt (copy) | Do not touch |
|---------|------|---------------------|--------------|
| **Director** | Prioritize phase, accept/reject exits, playtest notes | “You are Game Director. Read `docs/GAME_STATUS_SNAPSHOT.md` + this plan. Pick next open phase task. Do not implement unless a one-line doc fix.” | Large code refactors |
| **MapAgent** | Accurate board, QC, densify, adjacency, pick policy | “You are MapAgent. MAP_ACCURACY_BUILD + densify/polish scripts only. Never renumber `world_full` IDs. Dual green map tests required.” | Combat/UI freezes |
| **ContentAgent** | Scenario content on `world_accurate`: leaders, tech start, OOB seeds, focus paths | “You are ContentAgent. Wire content for `world_accurate` using existing 1936 assets where possible (alias/copy). Prove load log shows leaders/factories on accurate capitals.” | Map geometry renumber |
| **CombatLoopAgent** | Land/naval/air assault loop on accurate province IDs | “You are CombatLoopAgent. Vertical play: stage on accurate GER capital neighborhood → assault adjacent. Pure tests where possible; no new dual package unless play-blocked.” | Map GIS ingest |
| **ProductionAgent** | Factories, stockpile, EquipmentFlow visibility on dense map | “You are ProductionAgent. Ensure production/reinforce story works on world_accurate; KEY_I flows readable. Prefer balance/scalars over new domains.” | Netcode |
| **UIUXAgent** | First-session path, inspector, clutter at 8k polys, Campaign Alpha strip | “You are UIUXAgent. Full-test UX: load → pick nation feel → order strip → province panel. Fix blockers only; no residual dual spam.” | GIS pipelines |
| **PerfCIAgent** | FPS budgets, headless dual smoke, CI commands | “You are PerfCIAgent. Measure/document FPS on world_accurate; keep dual smoke path for world_full CI. Capture numbers in SCRATCH/docs.” | Feature scope creep |
| **QAAgent** | Regression: map unit tests, QC, dual harnesses, checklist | “You are QAAgent. Run verification commands in GAME_STATUS_SNAPSHOT §4; write SCRATCH logs; file bugs as phase tasks only.” | Implement features |

**Parallel safety:** MapAgent ∥ ContentAgent OK · CombatLoop ∥ Production OK · never two agents rewrite `GameData.gd` / `ScenarioLoader.gd` same day without Director lock.

---

## 2. Phased roadmap (ordered)

### Phase D0 — Doc truth & director board *(this goal)*

| Task | Agent | Exit |
|------|-------|------|
| D0.1 Status snapshot dated | Director / docs | `GAME_STATUS_SNAPSHOT.md` matches TestRunner default |
| D0.2 Director plan published | Director | This file has phases + agents + exits |
| D0.3 Canonical docs synced | Docs | MAP_ACCURACY · MASTER snapshot · PLAYTEST · CURRENT_STATE entry · README |
| D0.4 Map regression green | QAAgent | Unit + QC + dual pick harnesses OK |

### Phase D1 — Accurate scenario content (play blockers)

| Task | Agent | Exit |
|------|-------|------|
| D1.1 Leaders for `world_accurate` | ContentAgent | **DONE 2026-07-20** — roster chain + `historical_leaders_world_accurate.json` |
| D1.2 Starting tech / focus for 8 majors | ContentAgent | **DONE 2026-07-20** — `world_accurate` → 1936 starting pack |
| D1.3 OOB / key formations on accurate capitals | ContentAgent + CombatLoop | **DONE (data+spawner)** — scenario OOB designs + owned-land stations; pure tests |
| D1.4 Capitals click checklist | QA / human | Machine: capitals land+owned; human click still recommended |

### Phase D2 — Vertical war loop on accurate board

| Task | Agent | Exit |
|------|-------|------|
| D2.1 Land assault path | CombatLoopAgent | **DONE (machine)** — `HeadlessWorldAccurateAssaultEntryTest` GER 710173→FRA 710739 PASS |
| D2.2 Production → stock → reinforce | ProductionAgent | **DONE (machine)** — stockpile seeds + ESR product on capital + reinforce-after-assault in headless |
| D2.3 EquipmentFlow / KEY_I visible | ProductionAgent + UIUX | **DONE (machine)** — accurate glyph/route/battle culls @ ≥7000 polys; KEY_I toggle still in MapRenderer |
| D2.4 20-day human session note | Human + Director | **Partial** — machine 20d product landed; human narrative note still open |

### Phase D3 — Full-test campaign feel (60d)

| Task | Agent | Exit |
|------|-------|------|
| D3.1 AI daily acts on accurate | CombatLoop / AI | **DONE (machine)** — strategic AI daily product @ capital 710300 |
| D3.2 Save/load mid-campaign | UIUX / Content | **DONE (machine product)** — save browser with world_accurate metadata; full F5/F9 human open |
| D3.3 Mapmode readability | UIUX | **DONE (machine)** — ownership spheres + major color sep (SOV≠GER) + political default gates |
| D3.4 60-day session note | Human | **Partial** — machine 60d + multi-front product; human narrative still open |

### Phase D4 — Perf & CI for dense board

| Task | Agent | Exit |
|------|-------|------|
| D4.1 FPS harness numbers on accurate | PerfCIAgent | **DONE (honest pilot)** — `world_accurate` in map_perf product; EMPTY until samples; soft 30fps |
| D4.2 CI dual path documented | PerfCIAgent | **DONE** — world_full SCRIPT 0 dual; accurate optional longer `EOA_MAP_PERF` job (SNAPSHOT §4 + dual_note) |
| D4.3 Pick harness note | MapAgent | **DONE** — scaffold dual stays world_full; pure product + `map_manager_pick_harness_accurate.gd` (8 exact) |

### Phase D5 — Map polish residual (non-blocking full-test)

| Task | Agent | Exit |
|------|-------|------|
| D5.1 Shared-edge residual | MapAgent | **DONE 2026-07-20** — near_vertex residual · coverage ~0.971 · GER–FRA edge kept |
| D5.2 Optional densify microstates | MapAgent | Only if playtest names thin coasts |
| D5.3 Log wording cleanup | MapAgent | **DONE** earlier; hierarchy_scaffold + project_sites shipped |
| D5.4 Strategic resources + chokes/supply gates | MapAgent | **DONE 2026-07-20** — oil/rubber/etc paint + strategic map product + front assault ranking |
| D5.5 Multi-front live execute on accurate edges | CombatLoop | **DONE 2026-07-20** — border targets API + multi-front assault day + Maginot/Polish headless PASS |
| D5.6 World-class map review + doc reconcile | Director / MapAgent | **DONE 2026-07-20** — [`WORLD_CLASS_MAP_REVIEW.md`](WORLD_CLASS_MAP_REVIEW.md) + SNAPSHOT sync |

### Phase M — Map-star interaction (after D5 machine land)

Priorities from WORLD_CLASS_MAP_REVIEW §4 (do **not** renumber boards):

| Task | Agent | Exit |
|------|-------|------|
| M0 strategic_regions dedupe | MapAgent | **DONE** — 31 rows = membership; multi=0; North America filled |
| M1 Resources mapmode | UIUX + Map | **DONE** — toolbar + F9; `resources_mapmode_color_from_dict` |
| M2 States mapmode | UIUX | **DONE** — Shift+F9 + toolbar; `states_mapmode_color_from_id` |
| M3 Terrain mapmode polish | UIUX | **DONE** — Ctrl+F9 + toolbar; `terrain_mapmode_color_from_key` |
| M4 Supply corridor highlight | Production + UIUX | **DONE** — G + supply preview polyline; `find_land_path` / `highlight_supply_corridor` |
| M5 Measured FPS @ live board | PerfCI | **DONE (post-sparse re-sample 2026-07-31)** — n=60 · mean 34.01ms · p50 33.62 · p95 35.61 · ~29.4 fps · soft 30 **FAIL** honest · `map_tick_proxy_headless` |
| M6 Human 20d + 60d notes | Human + Director | PLAYTEST notes filed — **still open** (not a machine gate) |

**Next session:** `tools/run_godot.sh --path . res://scenes/TestScenario.tscn` · play §0b items **3–15** · append [`SESSION_NOTES/2026-08-05_m6_smoke.md`](SESSION_NOTES/2026-08-05_m6_smoke.md). This DAG already landed on GitHub `main`: PR 1 §0b composer · PR 2 assault hang-class (**closed** at `30910c2`, greps green) · PR 3 multi-AI on official gates · PR 4 keep-going board (this file + SNAPSHOT §0) · tip **`51b52e1`**. Next machine work is only a playtest-driven shipped-path fix. M6 remains human-only. Do **not** merge `origin/cursor/*` (this clone has `fix-void-return-2453`), `feature/goals-forward-2026-06-18`, or `execute-plan/ceb60fdd-*`. **Work from `origin/main`.** Deferred: FPS, GameData split, densify, DESIGN_LADDER_A corridor/transit, museum/MP/V3.

### Phase D6+ — Long program (MASTER)

Continue MASTER phases (G0 GameData split, multiplayer product, HOI designers, etc.) **after** full-test map-star exits (D1–D3 human notes + M1–M5 as prioritized). Director re-prioritizes; do not start D6 mid full-test freeze.

---

## 3. Suggested agent sequence (first 2 weeks)

```
Week 1: D0 (done in-repo) → D1.1 leaders → D1.3 OOB seeds → human capital click
Week 2: D2.1 assault → D2.2 production → D2.4 20d note → open D3 or fix bugs
```

Freeze **new residual dual packages** during D1–D3 unless a dual is the only way to prove a play blocker (Director approval).

---

## 4. Verification commands (machine gate)

```bash
# Map integrity (always)
python3 -m unittest tools.map_generation.tests.test_world_accurate_board -v
python3 -m unittest tools.map_generation.tests.test_world_accurate_capital_pick_product -v
python3 -m unittest tools.map_generation.tests.test_ownership_mapmode_readability_product -v
python3 -m unittest tools.map_generation.tests.test_map_perf_fps_harness_world_accurate -v
python3 -m unittest tools.map_generation.tests.test_world_accurate_20day_campaign_product -v
python3 -m unittest tools.map_generation.tests.test_world_accurate_multi_front_and_deploy -v
python3 -m unittest tools.map_generation.tests.test_world_accurate_strategic_and_assault -v
python3 -m unittest tools.map_generation.tests.test_shared_edge_adjacency_product -v
python3 tools/map_generation/scripts/map_accuracy_qc.py \
  --dir data/provinces_world_accurate --min-land-hit 0.90

# Scaffold dual pick (regression — world_full city IDs, CI SCRIPT 0)
tools/run_godot.sh --headless -s res://tools/map_pick_policy_test.gd
tools/run_godot.sh --headless -s res://tools/map_manager_pick_harness.gd
# Accurate capital pick (MapManager-only)
tools/run_godot.sh --headless -s res://tools/map_manager_pick_harness_accurate.gd
# Multi-front land assault (Maginot + Polish edges)
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMultiFrontAssaultTest.gd

# Default accurate interactive
tools/run_godot.sh --path . res://scenes/TestScenario.tscn
# CI dual smoke (lighter board): EOA_SCENARIO=world_full …
```

Human full-test checklist: **PLAYTEST_AND_DECISION_GUIDE.md § Full-test (world_accurate)**.

---

## 5. How Director uses MASTER

| Need | Doc |
|------|-----|
| Day-to-day full-test push | **This file** |
| What is true now | **GAME_STATUS_SNAPSHOT** |
| Multi-month pillar inventory | **MASTER_COMPLETION_PLAN** |
| Combat/production freezes | COMBAT_PRODUCTION / REINFORCEMENT freezes |
| Map pipeline commands | MAP_ACCURACY_BUILD |

When MASTER §1 snapshot disagrees with SNAPSHOT on default board, **SNAPSHOT wins** until MASTER is refreshed (see §1 dated entry in MASTER).
