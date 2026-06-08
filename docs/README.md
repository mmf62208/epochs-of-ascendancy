# Documentation Index — Epochs of Ascendancy

**Start here** after the root [README.md](../README.md). For day-to-day work, read **[CURRENT_STATE.md](CURRENT_STATE.md)** first, then **[TODO.md](../TODO.md)** for the backlog.

---

## Quick links

| Doc | Use when you need… |
|-----|-------------------|
| [CURRENT_STATE.md](CURRENT_STATE.md) | What works today, gaps, playtest entry |
| [TODO.md](../TODO.md) | Prioritized task list |
| [TESTING_PLAN.md](TESTING_PLAN.md) | Manual + headless regression |
| [SESSION_NOTES/2026-06-05.md](SESSION_NOTES/2026-06-05.md) | Recent multi-day review |
| [TEST_MAP_GRAND_THEATER_FOUNDATION.md](TEST_MAP_GRAND_THEATER_FOUNDATION.md) | Map art / editor QC checklist |

---

## Playtest & controls

1. Godot **4.6.2+** → `scenes/TestScenario.tscn` → **F5**
2. **F10** — Debug overlay (draggable title bar, **⤡** resize grip, collapsible sections)
3. **L / R / T / C / Y** — supply and infrastructure map layers
4. Headless smoke: `godot --headless --path . res://scenes/TestScenario.tscn --quit-after 15`
5. Full leader roster tests (heavy): `EOA_RUN_FULL_LEADER_TESTS=1 godot --headless …`

---

## Map & content pipeline

| Doc | Topic |
|-----|--------|
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
