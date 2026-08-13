# Documentation Index — Epochs of Ascendancy

**Start here** after the root [README.md](../README.md). For day-to-day full-test work: **[GAME_STATUS_SNAPSHOT.md](GAME_STATUS_SNAPSHOT.md)** + **[GAME_DIRECTOR_PLAN.md](GAME_DIRECTOR_PLAN.md)**. Dual backlog: root **[TODO.md](../TODO.md)**. Session log: [CURRENT_STATE.md](CURRENT_STATE.md).

---

## Quick links

| Doc | Use when you need… |
|-----|-------------------|
| [GAME_STATUS_SNAPSHOT.md](GAME_STATUS_SNAPSHOT.md) | **What is true now** (default board, gaps) |
| [GAME_DIRECTOR_PLAN.md](GAME_DIRECTOR_PLAN.md) | **Phases + agent roles** toward full-test |
| [PLAYTEST_AND_DECISION_GUIDE.md](PLAYTEST_AND_DECISION_GUIDE.md) | Launch + human full-test checklists |
| [MAP_ACCURACY_BUILD.md](MAP_ACCURACY_BUILD.md) | GIS dual-board pipeline / QC |
| [MASTER_COMPLETION_PLAN.md](MASTER_COMPLETION_PLAN.md) | Long pillar program (no permanent deferrals) |
| [CURRENT_STATE.md](CURRENT_STATE.md) | Append-only session log |
| [TODO.md](../TODO.md) | Dual markers / task list |
| [TESTING_PLAN.md](TESTING_PLAN.md) | Manual + headless regression |

---

## Playtest & controls

1. Godot **4.7.1+** → `scenes/TestScenario.tscn` → **F5** (default **`world_accurate`** ~3520)
2. Scaffold: `EOA_SCENARIO=world_full tools/run_godot.sh`
3. **F10** — Debug overlay (draggable title bar, **⤡** resize grip, collapsible sections)
4. **L / R / T / C / Y** — supply and infrastructure map layers
5. Map QC: `python3 -m unittest tools.map_generation.tests.test_world_accurate_board -v`

---

## Map & content pipeline

| Doc | Topic |
|-----|--------|
| [MAP_ACCURACY_BUILD.md](MAP_ACCURACY_BUILD.md) | Accurate board assemble / densify / polish |
| [MAP_GENERATION_PIPELINE_DESIGN.md](MAP_GENERATION_PIPELINE_DESIGN.md) | Phase 1 Europe generation |
| [MAP_IMPLEMENTATION_PLAN.md](MAP_IMPLEMENTATION_PLAN.md) | Sequenced map/combat wiring |
| [MAP_SYSTEM_DESIGN.md](MAP_SYSTEM_DESIGN.md) | Long-form map vision |
| [PROVINCE_EDITOR_IN_GAME_DESIGN.md](PROVINCE_EDITOR_IN_GAME_DESIGN.md) | In-game border editor |
| [tools/map_generation/README.md](../tools/map_generation/README.md) | Python tooling |

---

## Gameplay systems (design)

| Doc | Topic |
|-----|--------|
| [DESIGN_InfrastructureDevelopmentSystem.md](DESIGN_InfrastructureDevelopmentSystem.md) | Active infra/dev investment |
| [LEADER_SYSTEM_DESIGN.md](LEADER_SYSTEM_DESIGN.md) | Leaders, traits, training |
| [TECHNOLOGY_SYSTEM_DESIGN.md](TECHNOLOGY_SYSTEM_DESIGN.md) | Research trees |
| [WEATHER_AND_ENVIRONMENT_SYSTEM_DESIGN.md](WEATHER_AND_ENVIRONMENT_SYSTEM_DESIGN.md) | Weather overlays |
| [HIDDEN_HAND_DESIGN.md](HIDDEN_HAND_DESIGN.md) | Covert / narrative layer |
| [AIRCRAFT_RANGE_MAINTENANCE_PROTOTYPING_DESIGN.md](AIRCRAFT_RANGE_MAINTENANCE_PROTOTYPING_DESIGN.md) | Air design loop |

---

## UI specs

| Doc | Topic |
|-----|--------|
| [UI_DESIGN_REFERENCE.md](UI_DESIGN_REFERENCE.md) | Principles + screen patterns |
| [PRODUCTION_ASSIGNMENT_SCREEN.md](PRODUCTION_ASSIGNMENT_SCREEN.md) | Production UI spec |
| [LEADER_ASSIGNMENT_SCREEN.md](LEADER_ASSIGNMENT_SCREEN.md) | Leader UI spec |

---

## Data schemas (repo root + `data/`)

| Doc | Topic |
|-----|--------|
| [DATA_MODELS.md](../DATA_MODELS.md) | Core data overview |
| [data/provinces/SCHEMA.md](../data/provinces/SCHEMA.md) | Province JSON |
| [data/technology/SCHEMA.md](../data/technology/SCHEMA.md) | Tech nodes |
| [data/combat/COMBAT_PHILOSOPHY.md](../data/combat/COMBAT_PHILOSOPHY.md) | Combat design notes |
| [data/supply/SUPPLY_SYSTEM.md](../data/supply/SUPPLY_SYSTEM.md) | Supply model |
| [data/production/PRODUCTION_SYSTEM.md](../data/production/PRODUCTION_SYSTEM.md) | Production model |

---

## Session notes (archive)

- [SESSION_NOTES/2026-06-05.md](SESSION_NOTES/2026-06-05.md)
- [SESSION_NOTES/2026-05-28.md](SESSION_NOTES/2026-05-28.md)

Older detail lives in design docs and TODO history; prefer **CURRENT_STATE** over stale session bullets.

## Map expansion (2026-07)

- [MAP_MULTI_THEATER_EXPANSION.md](MAP_MULTI_THEATER_EXPANSION.md) — **full world** budgets, island/facility rules, phases
- **Primary:** `data/provinces_world_full/` (~1600) · Scenario: `data/scenarios/world_full.json`
- Intermediate: `data/provinces_grand_theater/` · Europe baseline: `data/provinces_full_europe/`
