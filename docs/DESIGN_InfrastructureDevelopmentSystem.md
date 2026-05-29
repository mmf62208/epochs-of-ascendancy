# Province Infrastructure & Development System — Design Document

**Status:** Design Complete — Ready for Implementation  
**Date:** May 28, 2026  
**Priority:** Highest foundational (unlocks meaningful long-term play, production scaling, combat depth, tech gating payoff)  
**Related:** `docs/MAP_IMPLEMENTATION_PLAN.md` (Phase 1 complete), `scripts/data/Province.gd`, `scripts/map/MapManager.gd`, `scripts/map/ProvinceEffects.gd`, `data/production/province_build_gates.json`, `TECHNOLOGY_SYSTEM_DESIGN.md`

---

## 1. Executive Summary & Current State

### What Exists Today (Strong Foundation)
- **Province** (`scripts/data/Province.gd`): `development_level` (float source → int runtime) and `infrastructure` (int 0–50) are first-class fields with rich computed getters:
  - `get_supply_throughput_modifier()`, `get_local_supply_generation_modifier()`
  - `get_combat_width_modifier()`, `get_organization_recovery_modifier()`, `get_attrition_modifier()`
  - `get_interdiction_resistance_modifier()`, `get_reinforcement_speed_modifier()`, `get_logistics_quality()`, `get_movement_cost()`
- **ProvinceEffects** (`scripts/map/ProvinceEffects.gd`): Clean aggregator that layers base province values + `NationalSpiritManager` + `NationalModifierManager` (spirits + temp agent effects). `for_country_province()` is the canonical query point.
- **MapManager** (`scripts/map/MapManager.gd`): Central authority. Exposes `get_province_effects()`, effective value helpers, `update_province_development/infrastructure()`, daily repair via `TimeManager.game_day_advanced`.
- **Daily Repair + Sabotage Duel** (fully live):
  - `advance_daily_infrastructure_repair()` with breakdown (base 0.08 + infra_pride + stability + tech_focus + engineer_brigades).
  - Engineer bonus from `CombatPresenceRegistry` / `SupplyManager` (real formations with engineer subunits boost repair).
  - Agent infra sabotage (focus + `sabotage_level` on `ProvinceDepotState`) creates "duel" visible in tooltips/overlays.
  - `clear_daily_sabotage_effects()` (counter-intel) + depot sabotage clear.
- **Build Eligibility Gates** (`data/production/province_build_gates.json` + `MapTechnologyContext`):
  - Dev requirements by era, domain (land/air/naval/space), factory_type (standard/shipyard/aircraft_factory/tank_plant).
  - Terrain blocks + port requirements.
  - Already drives `DesignPickerPopup`, production line placement, and rich tooltip strings talking about "Invest here".
- **Passive Dev Growth Hints**: Comments and UI strings say "factories running + infra repair gradually raise dev". Not yet implemented as a real mechanic.
- **Save/Load**: `SaveLoadManager` already snapshots and restores `development_level` + `infrastructure` per province (plus owner/controller/factories). Projects will need extension.
- **Wiring**: CombatResolver, SupplyManager, SupplyNetworkBuilder, ProvinceInsight, MapRenderer overlays, tooltips, and InfoPanel all consume real dev/infra values.

### The Gap (Why This Is the Highest-Leverage Upgrade)
The **passive simulation and effects** are excellent and already create "map feels alive" feedback.  
The **active player-driven development** is missing:
- No way for the player (or AI) to deliberately raise infrastructure or development in a province.
- "Invest here" strings exist in the UI but have no backend action.
- Higher dev/infra is the primary gate to advanced production (tank plants, aircraft factories, shipyards, future space). Without a lever, the tech + designer investment has limited map payoff.
- Factory efficiency, construction speed, and long-term economic snowballing are not yet tied to infra/dev.
- Agent sabotage feels impactful on repair but has no counter-play via construction.

**This system turns the excellent passive foundation into a strategic core loop**: "I will develop this region into my industrial heartland" becomes a real, multi-week decision with visible map + production + combat consequences.

---

## 2. Vision & Success Criteria

### Player Fantasy
- "I captured these low-infra border provinces in the 1918 scenario. Over the next 40 in-game days I station engineers, run supply, keep stability high, and run a focused Infrastructure Investment project. By 1922 they are proper industrial hubs with tank plants online."
- "My 2026 opponent is running heavy agent networks. I see infra sabotage on the map. I respond by surging engineers + a rapid repair + development surge project while my counter-intel teams roll up the cells."
- "I researched 'Advanced Rail Networks' (tech). Now my high-infra core provinces get a construction speed bonus and I can push a province to infra 12, unlocking the next tier of factory slots and local supply generation."

### Success Metrics (MVP)
- Player can start an "Infrastructure Investment" or "Development Project" on an owned province from InfoPanel or a new dedicated view.
- Project consumes a clear, limited national resource (Political Power + optional resources or "Construction Capacity" derived from civilian output).
- Progress ticks daily via TimeManager. Visible ETA, % complete, and "under construction" visual state on map.
- On completion: infra or dev level rises by 1 (or more for big projects). ProvinceEffects immediately reflect the change. Build eligibility updates. Tooltips announce the upgrade.
- Sabotage during construction slows or damages progress (real counter-play).
- Tech nodes can unlock higher max levels or grant build speed bonuses.
- Save/load round-trips a project in progress + completed levels.
- At least one visible downstream effect beyond "number went up" (e.g. +factory efficiency in high-infra provinces, or new factory slot unlocked at certain dev thresholds).

### Non-Goals for First Iteration
- Full civilian vs military factory split (related but can be parallel or follow-on; see Section 8).
- 3D construction animations or complex particle effects.
- Per-building "urbanization" sub-levels inside a province (keep infra/dev as the two primary axes for now).

---

## 3. Data Model & Core Concepts

### 3.1 Core Axes (Keep as Province Fields)
- `infrastructure` (int, 0–50 soft cap, typical playable range 1–15 for 1918–2026): Represents physical transport/logistics backbone (rails, roads, ports, pipelines, airfields). Primary driver of supply throughput, movement cost, combat width, reinforcement speed, interdiction resistance, repair rate (pride bonus).
- `development_level` (int, 0–20+): Represents overall economic/industrial maturity of the province (factories, education, institutions, urbanization). Primary driver of local supply generation, factory efficiency, build eligibility for advanced factory types, and long-term economic output.

These remain on `Province` (lightweight Resource). Mutation goes through `MapManager.update_province_*` (which emits `province_data_changed`).

### 3.2 New Concepts

**InfrastructureLevelDef / DevelopmentLevelDef** (data-driven tables)
- JSON-driven breakpoints for costs, max levels per era, effects, and unlock messages.
- Example skeleton (`data/infrastructure/infra_levels.json` and `development_levels.json` — new files).

**ProvincialProject** (runtime object, saved)
- `project_id`: stable (e.g. "infra_upgrade_berlin_1943")
- `province_id`
- `project_type`: "infrastructure" | "development" | "combined_hub" | future "urbanization" / "fortification"
- `target_level`: the level we are pushing toward
- `progress`: 0.0–100.0 (or accumulated "work points")
- `base_work_per_day`: from project definition + current infra/dev (higher infra speeds future infra projects — nice feedback)
- `modifiers`: dynamic (tech, national spirits, leader bonuses, engineer presence, stability, agent interference)
- `start_day`, `estimated_completion_day`
- `status`: "active" | "paused" | "sabotaged" | "complete"
- Optional: resources committed, political_power invested

**InfrastructureDevelopmentManager** (new autoload or extension of MapManager)
- Owns the active project registry per country (or global with owner tag).
- Daily tick handler connected to `TimeManager.game_day_advanced`.
- Public API:
  - `can_start_infrastructure_project(province_id, country_tag) -> bool + reason`
  - `start_infrastructure_project(...) -> ProvincialProject`
  - `get_active_project(province_id) -> ProvincialProject?`
  - `get_projects_for_country(tag) -> Array`
  - `cancel_project(...)`
  - `get_project_eta(project) -> int days`
  - `get_construction_capacity(tag) -> float` (how much "work" this country can apply per day across all projects)
- Integrates with existing repair system (construction projects should stack with or accelerate the passive repair).

### 3.3 Recommended Level Tables (MVP)

**infrastructure_levels.json** (proposed)
```json
{
  "version": 1,
  "levels": {
    "1": { "max": 5, "name": "Dirt Roads", "supply_mult": 0.54, "movement": 0.96, "width": 0.72, "repair_pride": 0.004 },
    "6": { "max": 10, "name": "Improved Roads & Light Rail", ... },
    "11": { "max": 15, "name": "Standard Rail Network", "unlocks": ["motorized_priority", "advanced_depot"] },
    ...
  },
  "era_max": { "ww1": 6, "interwar": 8, "ww2": 12, "modern": 18, "future": 25 }
}
```

**development_levels.json** similar, focused on factory efficiency, local supply gen, build eligibility thresholds (many already live in `province_build_gates.json` — we can reference or migrate).

---

## 4. Core Mechanics (MVP Proposal — Recommended Path)

### 4.1 Primary Action: "Infrastructure Investment Project"
- Triggered from: Province InfoPanel (new "Develop" section or "Invest" button), or future dedicated Infrastructure screen.
- Cost (MVP):
  - Political Power: 25–75 scaled by target level gap and current infra.
  - Optional: small resource bundle (steel + concrete or "industrial goods" abstract).
  - Opportunity cost: locks a small slice of national "construction capacity".
- Duration: 12–45 days typical (visible ETA, can be shortened by engineers on site, high stability, relevant tech, high current infra "pride").
- On daily tick:
  - Apply base work + modifiers (including negative from active enemy infra sabotage networks in the province).
  - If progress >= 100: raise level by 1 (or to target), emit signal, toast, update ProvinceEffects consumers, refresh build eligibility.
- During project: province shows "under construction" overlay glyph (can reuse/extend existing infra_repair visuals — cyan/magenta construction bars).
- Sabotage interaction: Active "infrastructure_sabotage" agent networks in the province add a "sabotage_chips" debuff to project progress (or rare critical sabotage can set back progress or damage the new level).

### 4.2 Secondary / Passive Path (Make the UI Strings True)
- Every day a province has 1+ active military factories + positive supply connection + no active sabotage: small chance or flat daily progress toward +1 development (very slow, e.g. 0.02–0.05 per day).
- This makes "just assign good production here and defend it" a valid long-term strategy, matching existing tooltip language.
- Bonus: higher infrastructure accelerates passive dev growth (the two axes reinforce).

### 4.3 Construction Capacity (Simple National Pool — MVP)
Instead of full civ/mil factory split immediately:
- Derive a daily "Construction Capacity" value for each country:
  - Base from number of owned core factories (or a tunable "industrial_base" national value).
  - Modified by stability, relevant national spirits ("Industrial Mobilization"), tech ("Construction Engineering"), leaders (Chief of Industry or equivalent).
- Projects consume from this pool. If total demand > supply, projects slow proportionally or player prioritizes.
- This is a clean abstraction that can later be replaced or augmented by explicit civilian factory assignment without breaking the project model.

### 4.4 Tech & Doctrine Integration
- New (or extended) technology nodes grant:
  - `infrastructure_repair_speed`, `construction_speed`, `max_infrastructure_level`, `province_dev_growth`.
  - Unlock specific high-tier projects ("Heavy Engineering Project" that can push infra +2 in one go in high-dev provinces).
- Doctrine training paths (already strong) can provide "field fortification" or "logistics engineering" modifiers that affect construction in controlled provinces.

---

## 5. Detailed Integration Points

### Must-Hook Locations (exact as of late May 2026)

| System | Hook Point | What to Do |
|--------|------------|------------|
| **TimeManager** | `game_day_advanced` signal | Call `InfrastructureDevelopmentManager.advance_daily_projects()` (after or before current repair call; order matters for sabotage duel feel). |
| **MapManager** | `update_province_development/infrastructure` + new `apply_construction_progress(pid, work)` | Already exist for levels. Add project-aware wrappers that also notify active projects. Emit `province_data_changed("infrastructure_project")`. |
| **ProvinceEffects** | Extend with `get_effective_construction_speed()`, `get_effective_development_growth()` | Pull from NationalModifierManager keys we will standardize (`construction_speed`, `infra_investment_cost_reduction`). |
| **NationalModifierManager** | Add keys: `construction_speed`, `infra_investment_cost`, `development_growth`, `max_infrastructure_bonus` | Already pattern exists for supply/combat keys. |
| **AgentManager** | `advance_networks_daily()` | When a network has focus `infrastructure_sabotage`, call into the new manager to apply sabotage_chips to any active project in that province. |
| **TechnologyManager** | On research complete / `get_effective_*` queries | Expose `get_construction_speed_modifier(tag)`, `get_max_infra_level(tag)`. Wire into project start validation and daily work calculation. |
| **SupplyManager / CombatPresenceRegistry** | Engineer presence already works for repair | Reuse/extend `get_engineer_brigades_in_province` for construction bonus (engineers speed building the thing they will later defend). |
| **SaveLoadManager** | `get_full_save_data` / `apply_loaded_state` | Persist `active_projects` dict per country (or global). Version the schema. Provide migration path. |
| **CombatResolver** | Post-battle / province capture | If a province changes controller mid-project, cancel or transfer the project (with heavy progress loss on hostile capture). |
| **ProductionManager** | Daily tick + factory assignment | (Future) When a factory is assigned in a province under active infra project, give small efficiency bonus or accelerate the project slightly ("synergy"). |
| **InfoPanel / ProvinceInsight** | Hover + detail view | Add "Development & Infrastructure" block showing current levels, effective modifiers (via ProvinceEffects), active project progress bar + ETA, "Start Investment" button (disabled with reason if invalid). |
| **MapRenderer / Overlays** | Existing infra repair visuals | Extend "under construction" state with distinct (but related) styling. Construction projects should pulse or use a building icon glyph. |

### Signals to Add / Leverage
- `InfrastructureDevelopmentManager.project_started(project)`
- `...project_progress_updated(project, delta)`
- `...project_completed(province_id, new_level, project_type)`
- `...project_sabotaged(province_id, severity)`
- Reuse `MapManager.province_data_changed`

---

## 6. UI / UX Surface (MVP Scope)

1. **Province InfoPanel** (highest impact)
   - New section or tab: "Infrastructure & Development"
   - Two progress-style bars or big numbers for current infra / dev with effective modifiers in tooltip.
   - "Active Project" card if one exists (progress bar, ETA, cancel button, sabotage warning).
   - "Invest in Infrastructure" button → opens small confirmation popup (cost preview, expected duration, benefits at next level).
   - "Accelerate Development" (the passive path button that perhaps spends a burst of PP or resources for faster passive tick).

2. **Map Hover Tooltip** (ProvinceHoverTooltip / ProvinceInsight)
   - Append 1–2 lines when a project is active: "Infra Investment 68% → Level 9 in 11 days (Engineers +1.4, Sabotage -0.6)"

3. **Technology Screen**
   - Nodes that affect construction show "Affects Provincial Projects" tag + concrete bonus in inspector.

4. **New (or stub) Infrastructure Screen** (medium priority)
   - National view: list of all active provincial projects + quick "focus on map" buttons.
   - Summary of total construction capacity usage.

5. **Toasts / News**
   - "Berlin infrastructure upgraded to level 9. Supply throughput +8%. New factory slots available."
   - Critical sabotage: "Saboteurs damaged the Berlin rail project — 18% progress lost."

---

## 7. Balance & Tuning Levers

- **Base project cost curve**: Linear or mildly exponential in target gap. Higher infra provinces are cheaper/faster to upgrade further (pride + existing logistics).
- **Engineer multiplier**: 1 brigade = +25–40% work per day (strong incentive to station real units for construction, not just repair).
- **Sabotage power**: A skilled province ring with "infrastructure_sabotage" focus should be able to slow a project by 30–70% or occasionally set it back. Counter-intel is the direct counter.
- **Tech multiplier**: "Construction Engineering" tree can easily give +15–30% national construction speed — this is how you out-develop your neighbors.
- **Stability gate**: Very low stability (<30) should make projects risky or slow (represents internal unrest, strikes, corruption).
- **Era feel**: 1918 projects are slow and expensive. 2026 projects on modern provinces are fast because base infra is already high.

---

## 8. Relationship to Other Major Systems (Civilian/Military Split, etc.)

**Civilian vs Military Factories** (strong synergy, can be parallel track)
- Once we have explicit civ factories, a large fraction of "Construction Capacity" should come from assigned civilian factories in core/high-infra provinces.
- Conversion mechanics (democracies especially) become meaningful: "I need to convert 8 civ factories to mil to surge tank production for the coming war, but that will crater my ability to develop new industrial provinces."

**Trade** (already strong)
- "Construction goods" or "industrial equipment" can become a trade commodity that directly boosts a country's construction capacity when imported.

**Diplomacy / Focuses** (future)
- Focus trees can grant timed "Five Year Plan" or "Marshall Aid" style massive construction speed or free infra levels in specific regions.

**Full Combat Resolution** (in flight)
- High-infra provinces should be harder to take (better org recovery for defender, faster reinforcement) and more valuable to hold post-capture (instant access to higher supply throughput).

---

## 9. Phased Implementation Roadmap

### Phase A — Foundation (2–4 days of focused work)
- Create `data/infrastructure/` folder + `infra_levels.json` + `development_levels.json` (minimal viable tables; can start with 8–10 breakpoints).
- Create `scripts/map/InfrastructureDevelopmentManager.gd` (new autoload).
  - Skeleton with `ProvincialProject` inner class or separate Resource.
  - `start_infrastructure_project(province_id, target_infra_level, investor_tag)` with validation.
  - Basic daily advance that only applies base work + engineer bonus + simple sabotage hook.
- Wire `TimeManager.game_day_advanced` → manager.
- Add 2–3 new NationalModifierManager keys and expose getters.
- Extend `ProvinceEffects` with construction-related effective values.
- Minimal InfoPanel integration: show active project if present + disabled "Invest" button with "Coming in next build" or wire the start flow behind a debug hotkey first.

### Phase B — Core Loop & Feedback (3–5 days)
- Full cost/ETA/preview calculation (Political Power + optional resource cost).
- Real level-up effect on completion + `province_data_changed` + toast.
- Wire agent sabotage into project progress (use existing network focus).
- Extend MapRenderer / ProvinceMapVisuals with "construction" visual state (reuse infra repair styling with distinct accent).
- Update `ProvinceInsight.build_hover_tooltip` and InfoPanel with rich project lines.
- Save/Load for active projects (add to the existing province + manager save sections).

### Phase C — Polish, Tech Integration, Balance (2–4 days)
- Wire TechnologyManager bonuses into project work rates and max level validation.
- Add "passive dev growth from active factories" (make the existing UI strings true).
- Production efficiency bonus from high infrastructure (small but meaningful — e.g. +1–2% per infra above 5 in the province).
- Engineer construction bonus fully using the existing brigade detection.
- First real tech node that affects the system (e.g. extend Support/Radio or a small Industry Foundations slice).
- Testing harness entries in `docs/TESTING_PLAN.md` (daily tick with project + sabotage duel, save/load mid-project, build eligibility change after upgrade).

### Phase D — Downstream Payoff (parallel or follow)
- New factory slots or factory_type unlocks at certain dev thresholds (via the existing build gates system).
- Construction projects that also add a special feature (e.g. "build naval base" project in a coastal province).
- AI use of the system (very high value — the AI should aggressively develop its core while contesting enemy infra via agents).

---

## 10. Open Questions & Decision Points (Resolve Before or During Phase A)

1. **Primary capacity source for MVP**: Pure Political Power + flat national "industrial rating" vs. deriving from current factory count? (Recommendation: start with PP + a simple derived capacity; migrate to civ factory assignment later.)
2. **Project granularity**: One project per province at a time, pushing one axis (infra or dev) by +1, or allow "Grand Development Plan" that targets both over longer time?
3. **Hard caps vs soft**: Do we enforce era_max strictly (you physically cannot push infra past 6 in 1918 even with god-tier engineers), or allow it with extreme cost/inefficiency?
4. **Hostile takeover of projects**: If you capture a province with an active enemy investment, do you inherit partial progress (risky — they might have left traps) or is it always cancelled with refund/penalty?
5. **Visual identity**: Should construction use the same "repair duel" visual language as current infra repair, or a distinct "building" mode (cranes, scaffolding overlay)?

---

## 11. Code Skeleton — InfrastructureDevelopmentManager (MVP)

```gdscript
# scripts/map/InfrastructureDevelopmentManager.gd
## Autoload: "InfrastructureDevelopmentManager"

signal project_started(project: ProvincialProject)
signal project_completed(province_id: int, new_level: int, axis: String)
signal project_sabotaged(province_id: int, work_lost: float)

class ProvincialProject:
	var id: String
	var province_id: int
	var axis: String              # "infrastructure" or "development"
	var starting_level: int
	var target_level: int
	var progress: float = 0.0
	var work_per_day_base: float = 2.5
	var modifiers: Dictionary = {}  # "engineer": 0.35, "sabotage": -0.6, "tech": 0.2, ...
	var owner_tag: String
	var start_day: int
	var political_power_committed: int = 0

	func get_current_work_per_day() -> float:
		var total := work_per_day_base
		for v in modifiers.values():
			total += v
		return maxf(0.1, total)

	func get_eta_days() -> int:
		var remaining := 100.0 - progress
		var daily := get_current_work_per_day()
		return int(ceil(remaining / daily)) if daily > 0 else 999

var active_projects: Dictionary = {}  # province_id -> ProvincialProject

func _ready() -> void:
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.game_day_advanced.connect(_on_day_advanced)

func can_start_project(province_id: int, axis: String, investor: String) -> Dictionary:
	# Checks: ownership, no existing project, level not at cap, PP >= cost, etc.
	...

func start_infrastructure_project(province_id: int, target_infra: int, investor: String) -> ProvincialProject:
	var p := ProvincialProject.new()
	# populate from province + costs + modifiers (engineers already present, tech, etc.)
	active_projects[province_id] = p
	project_started.emit(p)
	return p

func advance_daily_projects(_y: int, _m: int, _d: int) -> void:
	for pid in active_projects.keys():
		var proj: ProvincialProject = active_projects[pid]
		var work := proj.get_current_work_per_day()
		proj.progress += work
		if proj.progress >= 100.0:
			_complete_project(pid, proj)

func apply_sabotage_chips(province_id: int, chip_amount: float) -> void:
	if active_projects.has(province_id):
		active_projects[province_id].modifiers["sabotage"] = active_projects[province_id].modifiers.get("sabotage", 0.0) - chip_amount
		# possibly emit strong toast on heavy sabotage
```

Integration in MapManager (or direct):
```gdscript
# After level change in update_province_infrastructure
notify_province_changed(pid, "infrastructure")
InfrastructureDevelopmentManager.notify_level_changed(pid, "infrastructure", new_val)
```

---

## 12. Next Steps After This Design

1. Review & lock the decisions in Section 10 (especially capacity source and project granularity).
2. Implement Phase A skeleton + minimal UI hook (InfoPanel button that actually starts a 14-day project for 35 PP).
3. One end-to-end test: start project in a test province → advance 20 days with/without engineers and sabotage → observe level up + build eligibility change + save/load roundtrip.
4. Expand to full Phase B (visuals + agent wiring + rich tooltips).
5. Use the momentum to finally make the "Invest here" language in the existing production picker and tooltips become real, clickable, high-agency actions.

---

**This system is the missing bridge between the excellent daily simulation + modifier/agent/tech work of May 2026 and a truly strategic, replayable grand strategy experience.** Closing it will make every other system (production placement, supply arteries, agent targeting, tech value) feel more meaningful immediately.

Ready for implementation. Cursor can take this doc + the existing Province/MapManager/ProvinceEffects code and deliver a vertical slice in under two weeks of focused sessions.