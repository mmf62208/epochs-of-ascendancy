# scripts/national/NationalModifierManager.gd
extends Node

## Lightweight system for temporary national-level modifiers (debuffs and buffs).
## Used by Agent influence missions, future National Spirits, Focuses, Events, etc.
##
## Effects are simple dictionaries with modifiers, duration, and source tracking.

signal national_modifier_applied(country_tag: String, effect_id: String)
signal national_modifier_expired(country_tag: String, effect_id: String)

var country_modifiers: Dictionary = {}  # country_tag -> Array[Dictionary]

var _current_year: int = 1936
var _last_year_ticked: int = -1  # Dedup guard for year signal (TM + Leader both may fire during migration)


func _ready() -> void:
	# Prefer central TimeManager for monthly (and yearly) ticks.
	# Decay of temp modifiers is driven by game_month_advanced (1 per month).
	# game_year_advanced is connected for year sync / legacy fan-out only (no batch tick).
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_month_advanced.is_connected(_on_game_month_advanced):
			TimeManager.game_month_advanced.connect(_on_game_month_advanced)
		if not TimeManager.game_year_advanced.is_connected(_on_game_year_advanced):
			TimeManager.game_year_advanced.connect(_on_game_year_advanced)
	elif typeof(LeaderManager) != TYPE_NIL:
		# Fallback during transition
		LeaderManager.game_year_advanced.connect(_on_game_year_advanced)


func _on_game_year_advanced(year: int) -> void:
	if year == _last_year_ticked:
		return
	_last_year_ticked = year
	set_current_year(year)
	# Yearly boundary sync only (no decay work here — monthly signal drives tick_modifiers(1) x12).
	# Guard prevents double execution if both TimeManager and LeaderManager year signals fire.

func _on_game_month_advanced(year: int, month: int) -> void:
	set_current_year(year)
	# Monthly decay/tick for temporary national effects (the main point of monthly ticks)
	tick_modifiers(1)


func set_current_year(year: int) -> void:
	_current_year = year


# === Core API ===

## Applies a temporary national effect.
## effect_data should follow the standard structure:
## {
##   "effect_id": String (unique),
##   "source": String (e.g. "agent_mission", "national_focus"),
##   "source_detail": String (optional),
##   "modifiers": Dictionary (e.g. {"stability": -5.0, "prestige_gain": -0.2}),
##   "duration_months": int,
##   "remaining_months": int,
##   "is_debuff": bool (optional)
## }
func apply_national_effect(country_tag: String, effect_data: Dictionary) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() or effect_data.is_empty():
		return false

	var effect := effect_data.duplicate(true)

	# Ensure required fields
	if not effect.has("effect_id"):
		effect["effect_id"] = "%s_%s_%d" % [tag, effect.get("source", "unknown"), Time.get_unix_time_from_system()]

	if not effect.has("remaining_months"):
		effect["remaining_months"] = int(effect.get("duration_months", 6))

	if not effect.has("duration_months"):
		effect["duration_months"] = int(effect["remaining_months"])

	if not effect.has("modifiers"):
		effect["modifiers"] = {}

	if not effect.has("source"):
		effect["source"] = "unknown"

	# Remove any existing effect with the same ID (refresh behavior).
	# remove_effect() erases the country key when the last effect is removed — re-create the bucket before append.
	remove_effect(tag, effect["effect_id"])

	if not country_modifiers.has(tag):
		var bucket: Array[Dictionary] = []
		country_modifiers[tag] = bucket
	var effects: Array[Dictionary] = country_modifiers[tag]
	effects.append(effect)
	national_modifier_applied.emit(tag, effect["effect_id"])
	return true


## Advances all modifiers by the given number of months.
func tick_modifiers(months: int = 12) -> void:
	for country_tag in country_modifiers.keys():
		var effects: Array = country_modifiers[country_tag]
		var to_remove: Array = []

		for i in range(effects.size()):
			var effect: Dictionary = effects[i]
			var remaining := int(effect.get("remaining_months", 0)) - months
			effect["remaining_months"] = remaining

			if remaining <= 0:
				to_remove.append(i)
				national_modifier_expired.emit(country_tag, str(effect.get("effect_id", "")))

		# Remove expired effects (in reverse order)
		for i in range(to_remove.size() - 1, -1, -1):
			effects.remove_at(to_remove[i])

		if effects.is_empty():
			country_modifiers.erase(country_tag)


## Returns the combined modifier value for a given key across all active effects for the country.
## Positive and negative values are summed.
func get_national_modifier(country_tag: String, key: String) -> float:
	var tag := country_tag.strip_edges().to_upper()
	if not country_modifiers.has(tag):
		return 0.0

	var total := 0.0
	for effect in country_modifiers[tag] as Array:
		var mods: Dictionary = effect.get("modifiers", {})
		if mods.has(key):
			total += float(mods[key])

	return total


## Returns all currently active effects for a country.
func get_active_effects(country_tag: String) -> Array[Dictionary]:
	var tag := country_tag.strip_edges().to_upper()
	var out: Array[Dictionary] = []
	if not country_modifiers.has(tag):
		return out
	for item in country_modifiers[tag] as Array:
		if item is Dictionary:
			out.append((item as Dictionary).duplicate(true))
	return out


## Removes a specific effect by ID.
func remove_effect(country_tag: String, effect_id: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	if not country_modifiers.has(tag):
		return false

	var effects: Array = country_modifiers[tag]
	for i in range(effects.size()):
		if str(effects[i].get("effect_id", "")) == effect_id:
			effects.remove_at(i)
			national_modifier_expired.emit(tag, effect_id)
			if effects.is_empty():
				country_modifiers.erase(tag)
			return true
	return false


## Clears all modifiers for a country (useful on scenario reset).
func clear_country_modifiers(country_tag: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if country_modifiers.has(tag):
		country_modifiers.erase(tag)


## Clears everything (for full reset).
func clear_all_modifiers() -> void:
	country_modifiers.clear()


## Returns a dictionary of production-relevant modifiers for a country.
## This aggregates all active temporary effects and can be extended for stability baseline later.
func get_production_modifiers(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var result := {
		"output_multiplier": 1.0,
		"reliability_multiplier": 1.0,
		"retooling_days_multiplier": 1.0,
		"cost_multiplier": 1.0,
		"infrastructure_repair": 0.0,  # Consumed by MapManager repair system (tech + national focus support for infrastructure)
		"resource_output_multiplier": 1.0,  # For agent resource discovery / exploration boosts
	}

	if typeof(TechnologyManager) != TYPE_NIL:
		var tech_mods := TechnologyManager.get_technology_modifiers(tag)
		for key in tech_mods.keys():
			var val := float(tech_mods[key])
			match key:
				"production_speed", "factory_output", "output_multiplier":
					result["output_multiplier"] *= (1.0 + val)
				"reliability":
					result["reliability_multiplier"] *= (1.0 + val)
				"retooling_time", "retooling_days_multiplier":
					result["retooling_days_multiplier"] *= (1.0 + val)
				"production_cost", "cost_multiplier":
					result["cost_multiplier"] *= (1.0 + val)
				# Layered/additive manufacturing (additive_manuf_1985): flexibility speeds retool/custom, reduces waste/cost
				"production_flexibility":
					result["retooling_days_multiplier"] *= maxf(0.5, 1.0 - val * 0.6)  # e.g. 0.25 -> ~15% faster retool
					result["cost_multiplier"] *= maxf(0.6, 1.0 - val * 0.4)
				"material_efficiency":
					result["cost_multiplier"] *= maxf(0.5, 1.0 - val * 0.5)  # nanotech synergy too

	if not country_modifiers.has(tag):
		return result

	for effect in country_modifiers[tag] as Array:
		var mods: Dictionary = effect.get("modifiers", {})
		for key in mods.keys():
			var val := float(mods[key])
			match key:
				"production_speed", "factory_output", "output_multiplier":
					result["output_multiplier"] *= (1.0 + val)
				"reliability":
					result["reliability_multiplier"] *= (1.0 + val)
				"retooling_time", "retooling_days_multiplier":
					result["retooling_days_multiplier"] *= (1.0 + val)
				"production_cost", "cost_multiplier":
					result["cost_multiplier"] *= (1.0 + val)
				# Layered/additive manufacturing (additive_manuf_1985): flexibility speeds retool/custom, reduces waste/cost
				"production_flexibility":
					result["retooling_days_multiplier"] *= maxf(0.5, 1.0 - val * 0.6)  # e.g. 0.25 -> ~15% faster retool
					result["cost_multiplier"] *= maxf(0.6, 1.0 - val * 0.4)
				"material_efficiency":
					result["cost_multiplier"] *= maxf(0.5, 1.0 - val * 0.5)  # nanotech synergy too
				"stability":
					# Simple stability effect: negative stability reduces output
					if val < 0:
						var penalty := clampf(absf(val) * 0.01, 0.0, 0.25)  # 1% per stability point, capped
						result["output_multiplier"] *= (1.0 - penalty)
				"resource_output", "resource_output_multiplier", "resource_production":
					result["resource_output_multiplier"] *= (1.0 + val)

	return result

## Returns resource-relevant modifiers (for discovery, output from agents/exploration).
func get_resource_modifiers(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var result := {
		"resource_output_multiplier": 1.0,
	}
	if tag.is_empty() or not country_modifiers.has(tag):
		return result
	for effect in country_modifiers[tag] as Array:
		var mods: Dictionary = effect.get("modifiers", {})
		for key in mods.keys():
			var val := float(mods[key])
			match key:
				"resource_output", "resource_output_multiplier", "resource_production":
					result["resource_output_multiplier"] *= (1.0 + val)
	return result


## Returns combat-relevant modifiers for a country (army_org, defence, planning, etc.).
func get_combat_modifiers(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var result := {
		"army_org_factor": 0.0,
		"defence_factor": 0.0,
		"planning_speed": 0.0,
		"manpower_factor": 0.0,
		"attack_factor": 0.0,
		"reconnaissance": 0.0,
		"encryption": 0.0,
		"attrition_reduction": 0.0,
		"interdiction_resistance": 0.0,
		# New tech expansion wiring (biotech, sonic/CB, drones, scanners, shields, phasers, tele, layered, VR etc)
		"infantry_enhancement": 0.0,
		"soldier_enhancement": 0.0,
		"precision_strike": 0.0,
		"defensive_shielding": 0.0,
		"energy_weapon_dmg": 0.0,
		"area_denial": 0.0,
		"non_lethal_control": 0.0,
		"terror_factor": 0.0,
		"detection_range": 0.0,
		"stealth_detection": 0.0,
		"rapid_deployment": 0.0,
		"manpower_replacement": 0.0,
		"training_efficiency": 0.0,
	}

	if not country_modifiers.has(tag):
		return result

	for effect in country_modifiers[tag] as Array:
		var mods: Dictionary = effect.get("modifiers", {})
		for key in mods.keys():
			var val := float(mods[key])
			if key in result:
				result[key] += val

	if typeof(TechnologyManager) != TYPE_NIL:
		var tech_mods := TechnologyManager.get_technology_modifiers(tag)
		for key in tech_mods.keys():
			var val := float(tech_mods[key])
			if key in result:
				result[key] += val
			else:
				result[key] = val

	return result


## Returns supply-relevant modifiers for a country (primarily supply_consumption).
func get_supply_modifiers(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var result := {
		"supply_consumption": 0.0,   # additive to multiplier (negative = better)
		"attrition_reduction": 0.0,  # positive = reduces attrition (good)
		"interdiction_resistance": 0.0, # positive = reduces interdiction chance (good)
		"planning_speed": 0.0,
		"reconnaissance": 0.0,
		"encryption": 0.0,
		"infrastructure_repair": 0.0,
	}

	if not country_modifiers.has(tag):
		return result

	for effect in country_modifiers[tag] as Array:
		var mods: Dictionary = effect.get("modifiers", {})
		for key in mods.keys():
			var val := float(mods[key])
			match key:
				"supply_consumption", "supply_use", "logistics":
					result["supply_consumption"] += val
				"attrition_reduction", "attrition":
					result["attrition_reduction"] += val
				"interdiction_resistance", "interdiction_reduction", "logistics_security":
					result["interdiction_resistance"] += val
				"stability":
					# Negative stability increases supply consumption (worse logistics)
					if val < 0:
						result["supply_consumption"] += absf(val) * 0.005   # 0.5% extra consumption per stability point
						# Also slightly hurts attrition resistance
						result["attrition_reduction"] -= absf(val) * 0.003

	return result


# === Convenience Helpers ===

## Quick way for Influence-type effects to apply stability and/or prestige changes.
func apply_influence_effect(
	country_tag: String,
	stability_change: float = 0.0,
	prestige_change: float = 0.0,
	duration_months: int = 12,
	source: String = "influence",
	source_detail: String = "",
) -> String:
	var tag := country_tag.strip_edges().to_upper()
	var modifiers := {}
	if stability_change != 0.0:
		modifiers["stability"] = stability_change
	if prestige_change != 0.0:
		modifiers["prestige_gain"] = prestige_change

	if modifiers.is_empty():
		return ""

	var effect := {
		"source": source,
		"source_detail": source_detail.strip_edges(),
		"modifiers": modifiers,
		"duration_months": duration_months,
		"remaining_months": duration_months,
		"is_debuff": stability_change < 0.0 or prestige_change < 0.0,
	}

	apply_national_effect(tag, effect)
	return str(effect.get("effect_id", ""))
