# Technology Node Schema (authoring reference)

See [docs/TECHNOLOGY_SYSTEM_DESIGN.md](../../docs/TECHNOLOGY_SYSTEM_DESIGN.md) for full system design.

## Required fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Globally unique |
| `name` | string | Display name |
| `domain` | string | `industry`, `land_equipment`, `naval_equipment`, `air_equipment`, `space_equipment`, `land_doctrine`, `naval_doctrine`, `air_doctrine`, `space_doctrine`, `support`, `strategic_future` |
| `tree_id` | string | Layout group |
| `node_kind` | string | `research`, `doctrine`, `building`, `passive`, `project`, `repeatable` |

## Layout (graph UI)

| Field | Type | Description |
|-------|------|-------------|
| `column` | int | Horizontal column (HOI4-style) |
| `row` | int | Vertical position within column |
| `tier` | int | Optional sort tier |

## Time gates

| Field | Type | Description |
|-------|------|-------------|
| `era_min` | int | First year node is sensible (ahead-of-time before this) |
| `era_max` | int | Soft “obsolete” for UI greying |
| `epoch` | string | Swimlane key (`industrial_war`, `modern`, `near_future`, …) |

## Dependencies

| Field | Type | Description |
|-------|------|-------------|
| `prerequisites` | string[] | Tech ids that must be completed |
| `mutually_exclusive_with` | string[] | Only one branch allowed |
| `hidden_until` | object | `{ "year": 1936, "requires_any": ["focus_id"] }` |

## Research cost

```json
"research": {
  "base_cost_days": 120,
  "category": "armor",
  "ahead_of_time_penalty_per_year": 0.15,

# New: knowledge diffusion & agent early unlock (2026 expansions, updated per feedback)
# Diffusion (get_knowledge_diffusion_discount): Hybrid to protect vs single/small-nation rushes (count bonus only >=3 nations; normal 2yr time floor) BUT if LARGE # (>=5 nations have completed it), even only 1 year behind gets early catch-up discount bonus. Time ramp + count add when thresholds met. Prevents one-rush making everything cheap for others, while rewarding widespread adoption with earlier bonuses for advancing ahead penalty.
# Agent trait early: get_early_unlock_years_bonus (e.g. breakthrough_visionary trait) reduces effective era_min when sponsoring agent assigned to tech_id. Not hard lock - enables alt-history "sooner" unlocks if conditions right.
# Defend secrecy: new "defend_tech_secrecy" mission targets tech, enhances theft protection (Manhattan-style compartmentalization); theft logic checks for active defender agent on exact tech for extra block.
  "repeatable": false
}
```

## Unlocks (array of objects)

Each entry must include `type`. Supported types:

- `unit_design` — `{ "type": "unit_design", "template_ids": ["m4_sherman_medium"] }`
- `production_category` — `{ "type": "production_category", "category": "armor", "min_factory_type": "tank_plant" }`
- `factory_type` — `{ "type": "factory_type", "factory_type": "shipyard" }`
- `building` — `{ "type": "building", "building_id": "naval_yard_ii" }`
- `division_template` — `{ "type": "division_template", "template_id": "us_armored_div_ww2" }`
- `division_capability` — `{ "type": "division_capability", "capability": "mechanized" }`
- `equipment_module` — `{ "type": "equipment_module", "module_id": "apds_rounds" }`
- `doctrine_key` — `{ "type": "doctrine_key", "key": "mobile_warfare" }`
- `modifier` — `{ "type": "modifier", "stat": "production_speed", "value": 0.05 }`
- `rule_flag` — `{ "type": "rule_flag", "flag": "allow_port_shipyard_conversion" }`

## Agent hooks

```json
"agent": {
  "theft_target": true,
  "sabotage_delay_days": 30,
  "intel_domain": "technology",
  "counter_intel_node": "secure_research_facility"
}
```

## Scenario starting tech (`data/technology/starting/`)

Per-scenario JSON: `defaults` plus `countries` tag overrides. Loaded by `TechnologyManager.apply_scenario_starting_tech()`. See `starting/README.md`.

## UI

```json
"ui": {
  "icon": "res://assets/tech/icons/example.png",
  "short_effect": "One-line player summary",
  "flavor": "Optional historical flavor text",
  "tooltip_stats": ["production_speed +5%"]
}
```

## File layout

One tree file = JSON object keyed by tech id, or `{ "nodes": [ ... ] }` array—loader normalizes both.
