# scripts/air/AircraftDesignSystem.gd
class_name AircraftDesignSystem
extends Node

## Aircraft Range, Maintenance & Prototyping System
## 
## Builds directly on the existing production/reliability systems:
## - Reuses/extends ReliabilityCalculator, DesignLineState, RefinementProject
## - Integrates with TechnologyManager (air_equipment domain, engine families)
## - Agent assignment for "Lead Engineer / Test Pilot" projects
## - SpecialSiteManager (R&D labs, test airfields, maintenance depots)
## - Province / Infrastructure for basing effects
##
## See full design: docs/AIRCRAFT_RANGE_MAINTENANCE_PROTOTYPING_DESIGN.md
##
## Philosophy: Real historical trade-offs and improvement curves.
##   - Prototypes start powerful but unreliable/expensive.
##   - Combat use + deliberate investment (agents + resources + sites) drives iteration.
##   - Player choices in loadouts and design philosophy matter for campaigns.

signal design_prototype_created(design_id: String, template_id: String)
signal design_maturity_advanced(design_id: String, new_maturity: float, reason: String)
signal design_reliability_changed(design_id: String, old_reliability: float, new_reliability: float)
signal aircraft_config_changed(formation_id: int, config: String)  # Ferry / Combat / Escort

# --- Range Configuration Profiles (player chooses per mission or default for formation)
enum RangeConfig {
	FERRY_LONG_RANGE,   # Drop tanks, max range, reduced payload
	COMBAT_LOAD,        # Standard weapons, normal range
	ESCORT_BALANCED     # Compromise for range + combat capability
}

# --- Core Data
var _design_states: Dictionary = {}           # design_id (or template_id) -> AircraftDesignState
var _formation_configs: Dictionary = {}       # formation_id -> RangeConfig

# Reference to other systems (wired in _ready or via autoloads)
var tech_manager: Node = null
var agent_manager: Node = null
var special_site_manager: Node = null
var infra_manager: Node = null
var reliability_calculator: Node = null   # Existing production/ReliabilityCalculator

func _ready() -> void:
	_connect_to_managers()
	print("AircraftDesignSystem: Initialized (range, maintenance, prototyping)")

func _connect_to_managers() -> void:
	# Prefer autoloads / singletons
	if typeof(TechnologyManager) != TYPE_NIL:
		tech_manager = TechnologyManager
	if typeof(AgentManager) != TYPE_NIL:
		agent_manager = AgentManager
	if typeof(SpecialSiteManager) != TYPE_NIL:
		special_site_manager = SpecialSiteManager
	if typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		infra_manager = InfrastructureDevelopmentManager

	# ReliabilityCalculator is a RefCounted helper; we can call it statically or wrap
	# For now we assume we can call static methods or find a ProductionManager instance.

func get_or_create_design_state(design_id: String, base_template: Variant = null) -> Dictionary:
	if _design_states.has(design_id):
		return _design_states[design_id]

	var template_id := _resolve_air_template_id(base_template)

	# New prototype starts with significant drawbacks (per design doc)
	var state := {
		"design_id": design_id,
		"template_id": template_id,
		"maturity": 0.15,                    # Starts low (prototype)
		"reliability_offset": -25.0,         # Big initial penalty
		"maintenance_multiplier": 2.2,
		"range_multiplier": 0.85,
		"combat_xp": 0,
		"agent_assigned_ids": [],            # Agents currently working on this design
		"refinement_projects": [],           # Ties into existing RefinementProject
		"historical_notes": "",
		"created_at_year": 1936
	}
	_design_states[design_id] = state
	design_prototype_created.emit(design_id, state["template_id"])
	return state


func _resolve_air_template_id(base_template: Variant) -> String:
	if base_template is UnitTemplate:
		return (base_template as UnitTemplate).id
	if base_template is Dictionary:
		return str((base_template as Dictionary).get("id", ""))
	if base_template == null:
		return ""
	return str(base_template)

## Get air mission modifier for a formation, factoring its design (if set) and range config.
## Returns multiplier for effectiveness (range/reliability impact).
func get_formation_air_modifier(formation: Formation) -> float:
	if formation == null:
		return 1.0
	var mod := 1.0
	var design_id := formation.get_air_design_id() if formation.has_method("get_air_design_id") else ""
	if design_id != "" and _design_states.has(design_id):
		var state: Dictionary = _design_states[design_id]
		var mat := clampf(float(state.get("maturity", 0.0)), 0.0, 1.0)
		mod *= lerpf(0.6, 1.0, mat)  # immature designs hurt missions
		if state.has("reliability_offset"):
			var rel_off := float(state["reliability_offset"])
			mod *= clampf(1.0 + rel_off / 100.0, 0.5, 1.3)
	var cfg_enum := formation.get_air_range_config_enum() if formation.has_method("get_air_range_config_enum") else 1
	match cfg_enum:
		0:  # FERRY
			mod *= 0.7  # lower combat eff for long range ferry
		2:  # ESCORT
			mod *= 0.95
		_: pass
	return clampf(mod, 0.3, 1.5)

## Demo helper for ADS impact without full formation (used in intel bridge etc for prototyping demo)
func get_demo_air_modifier(design_id: String = "demo_p51_prototype") -> float:
	if not _design_states.has(design_id):
		return 1.0
	var state: Dictionary = _design_states[design_id]
	var mat := clampf(float(state.get("maturity", 0.0)), 0.0, 1.0)
	var mod := lerpf(0.6, 1.0, mat)
	if state.has("reliability_offset"):
		var rel_off := float(state["reliability_offset"])
		mod *= clampf(1.0 + rel_off / 100.0, 0.5, 1.3)
	return clampf(mod, 0.3, 1.5)

## Create or get AirMissionProfile for a formation (integrates range/config with ADS for Supply/Combat use).
func get_or_create_mission_profile(formation: Formation) -> AirMissionProfile:
	var prof := AirMissionProfile.new(formation.formation_id if formation else "", formation.get_air_design_id() if formation and formation.has_method("get_air_design_id") else "", formation.air_range_config if formation else "COMBAT_LOAD")
	return prof

# === RANGE SYSTEM ===

func get_effective_range(base_range: float, design_id: String, config: RangeConfig, province_id: int = -1) -> float:
	var state: Dictionary = _design_states.get(design_id, {})
	var mult := 1.0

	# Design maturity & tech
	mult *= lerpf(0.75, 1.0, float(state.get("maturity", 0.0)))
	if state.has("range_multiplier"):
		mult *= float(state["range_multiplier"])

	# Tech modifiers (example: advanced engines)
	if tech_manager and tech_manager.has_method("has_tech_unlock"):
		if tech_manager.has_tech_unlock("GER", "air_equipment", "rolls_royce_merlin_equiv"):
			mult *= 1.32

	# Configuration trade-off
	match config:
		RangeConfig.FERRY_LONG_RANGE:
			mult *= 1.85   # Big range boost
			# Payload penalty handled elsewhere (in mission planning / logistics)
		RangeConfig.ESCORT_BALANCED:
			mult *= 1.15
		_:
			pass  # COMBAT_LOAD = baseline

	# Basing / province modifiers (forward airfields, terrain) — extend ProvinceEffects when wired.
	if province_id >= 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
		var prov: Province = MapManager.get_province(province_id)
		if prov != null:
			mult *= 1.0 + clampf(float(prov.infrastructure) * 0.01, 0.0, 0.15)

	# Mid-air refueling (future: check for tanker presence + tech)
	# if has_active_refueling_support(...): mult *= 2.5 or more

	return base_range * mult

func set_formation_range_config(formation_id: int, config: RangeConfig) -> void:
	_formation_configs[formation_id] = config
	aircraft_config_changed.emit(formation_id, str(config))
	# TODO: Notify Supply / AirMission system so range is recalculated for planning

# === MAINTENANCE & RELIABILITY ===

func get_effective_reliability(base_reliability: float, design_id: String, current_supply: float = 1.0) -> float:
	var state: Dictionary = _design_states.get(design_id, {})
	var rel := base_reliability

	rel += float(state.get("reliability_offset", 0.0))

	# Maturity improves it (ties into existing ReliabilityCalculator logic)
	var maturity := float(state.get("maturity", 0.0))
	rel = rel * lerpf(0.65, 1.0, maturity)

	# Supply impact (low supply = faster degradation)
	rel *= clampf(0.7 + current_supply * 0.4, 0.5, 1.1)

	return clampf(rel, 5.0, 98.0)

func get_maintenance_cost(base_cost: float, design_id: String, province_infra: int = 1) -> float:
	var state: Dictionary = _design_states.get(design_id, {})
	var mult := float(state.get("maintenance_multiplier", 1.0))

	# Better basing reduces cost
	mult *= 1.0 / (1.0 + (province_infra * 0.03))

	# Special site bonuses (repair depots, etc.)
	if special_site_manager:
		# TODO: query sites in the province for "aircraft_maintenance" or "engine_rebuild"
		pass

	return base_cost * mult

func apply_field_degradation(design_id: String, days: float, conditions: Dictionary = {}) -> void:
	# Called from SupplyManager or daily tick for air formations in the field
	var state: Dictionary = _design_states.get(design_id, {})
	if state.is_empty():
		return

	var degradation := 0.08 * days   # base daily wear

	if conditions.get("bad_weather", false):
		degradation *= 1.6
	if conditions.get("low_supply", false):
		degradation *= 2.1
	if conditions.get("long_mission", false):
		degradation *= 1.3

	state["reliability_offset"] = float(state.get("reliability_offset", 0.0)) - degradation

	# Emit if crossed thresholds
	design_reliability_changed.emit(design_id, state.get("reliability_offset", 0.0) + degradation, state["reliability_offset"])

# === PROTOTYPING & ITERATION ===

func add_combat_experience(design_id: String, xp_gained: float) -> void:
	var state: Dictionary = _design_states.get(design_id, {})
	if state.is_empty(): return

	state["combat_xp"] = float(state.get("combat_xp", 0.0)) + xp_gained

	# Slow natural maturity from use (historical "teething problems get solved in the field")
	var natural_gain := xp_gained * 0.0008
	_advance_maturity(design_id, natural_gain, "combat_experience")

func assign_agent_to_design(design_id: String, agent_id: String, role: String = "engineer") -> bool:
	# Called from AgentAssignmentScreen or new R&D UI
	var state: Dictionary = _design_states.get(design_id, {})
	if state.is_empty(): return false

	if not state["agent_assigned_ids"].has(agent_id):
		state["agent_assigned_ids"].append(agent_id)

	# Big acceleration when good agents are assigned (core of the "player agency" loop)
	var accel := 0.012
	if role == "test_pilot":
		accel *= 1.4

	_advance_maturity(design_id, accel, "agent_" + role)
	return true

func invest_resources_in_iteration(design_id: String, political_power: float, resources: Dictionary) -> void:
	# Spend PP + industrial resources to push a design forward faster
	var state: Dictionary = _design_states.get(design_id, {})
	if state.is_empty():
		return

	var gain: float = (political_power * 0.002) + float(resources.get("aluminum", 0)) * 0.0001
	_advance_maturity(design_id, gain, "resource_investment")

func _advance_maturity(design_id: String, amount: float, reason: String) -> void:
	var state: Dictionary = _design_states.get(design_id, {})
	if state.is_empty(): return

	var old := float(state["maturity"])
	state["maturity"] = clampf(old + amount, 0.0, 1.0)

	if state["maturity"] > old + 0.01:
		design_maturity_advanced.emit(design_id, state["maturity"], reason)

		# As maturity rises, penalties reduce (the heart of the improvement curve)
		state["reliability_offset"] = lerp(state.get("reliability_offset", -25.0), 0.0, 0.6)
		state["maintenance_multiplier"] = lerp(state.get("maintenance_multiplier", 2.2), 1.0, 0.5)

# === Persistence Hooks (SaveLoadManager) ===

func get_save_data() -> Dictionary:
	return {
		"design_states": _design_states.duplicate(true),
		"formation_configs": _formation_configs.duplicate(true)
	}

func load_save_data(data: Dictionary) -> void:
	_design_states = data.get("design_states", {}).duplicate(true)
	_formation_configs = data.get("formation_configs", {}).duplicate(true)

# TODO next:
# - Wire into existing ProductionManager / DesignManager so new air designs start as prototypes.
# - Add air mission planning to use get_effective_range + config.
# - UI for choosing RangeConfig before launching air operations.
# - SpecialSite definitions for "jet_research_lab", "prototype_test_range", etc.
# - Daily tick integration for degradation/recovery.