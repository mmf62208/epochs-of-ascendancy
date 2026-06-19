# scripts/national/NationalSpiritManager.gd
extends Node

## National Spirits (persistent country traits) plus UI summaries for temporary modifiers.

signal spirits_initialized(country_tag: String)

const SPIRITS_PATH := "res://data/national/spirit_definitions.json"

var spirit_definitions: Dictionary = {}
var country_spirits: Dictionary = {}  # country_tag -> Array[String] spirit ids


func _ready() -> void:
	_load_spirit_definitions()
	if typeof(NationalModifierManager) != TYPE_NIL:
		NationalModifierManager.national_modifier_applied.connect(_on_modifier_changed)
		NationalModifierManager.national_modifier_expired.connect(_on_modifier_changed)


func _on_modifier_changed(country_tag: String, _effect_id: String = "") -> void:
	var screen := get_tree().get_first_node_in_group("national_spirits_screen") if get_tree() else null
	if screen != null and screen.has_method("refresh_screen"):
		screen.call("refresh_screen", country_tag)
	var agent_screen := get_tree().get_first_node_in_group("agent_screen") if get_tree() else null
	if agent_screen != null and agent_screen.has_method("refresh_screen"):
		agent_screen.call("refresh_screen")


func _load_spirit_definitions() -> void:
	if not FileAccess.file_exists(SPIRITS_PATH):
		push_error("NationalSpiritManager: Missing %s" % SPIRITS_PATH)
		return
	var file := FileAccess.open(SPIRITS_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		spirit_definitions = parsed
	else:
		push_error("NationalSpiritManager: Failed to parse spirit_definitions.json")


func ensure_country_spirits(country_tag: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if country_spirits.has(tag):
		return

	var ids: Array[String] = []
	for spirit_id in spirit_definitions.keys():
		var def: Dictionary = spirit_definitions[spirit_id] as Dictionary
		var countries: Array = def.get("countries", []) as Array
		if tag in countries:
			ids.append(str(spirit_id))

	country_spirits[tag] = ids
	spirits_initialized.emit(tag)


## Dynamic treaty / peace spirits (for 1918 Armistice outcomes + follow-ons). Allows runtime application of "versailles_humiliation", "inclusion_at_the_table" etc.
## These are added to the country's active list even if not in the static "countries" filter of definitions.
## Effects are read from spirit_definitions when building UI/modifiers (spirits are permanent-ish until removed by later events).
func apply_treaty_spirit(country_tag: String, spirit_id: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	var sid := spirit_id.strip_edges()
	if not spirit_definitions.has(sid):
		push_warning("NationalSpiritManager: Unknown spirit '%s' for treaty apply to %s" % [sid, tag])
		return false
	ensure_country_spirits(tag)  # ensure dict exists
	if not country_spirits.has(tag):
		country_spirits[tag] = []
	if sid not in country_spirits[tag]:
		country_spirits[tag].append(sid)
		spirits_initialized.emit(tag)
		print("NationalSpiritManager: Applied treaty spirit '%s' to %s" % [sid, tag])
		# Notify screens if open
		_on_modifier_changed(tag)
		return true
	return true  # already had it


func remove_treaty_spirit(country_tag: String, spirit_id: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	var sid := spirit_id.strip_edges()
	if country_spirits.has(tag) and sid in country_spirits[tag]:
		country_spirits[tag].erase(sid)
		_on_modifier_changed(tag)
		print("NationalSpiritManager: Removed treaty spirit '%s' from %s" % [sid, tag])


func get_spirits_screen_data(country_tag: String) -> NationalSpiritsScreenData:
	var tag := country_tag.strip_edges().to_upper()
	ensure_country_spirits(tag)

	var data := NationalSpiritsScreenData.new()
	data.country_tag = tag

	for spirit_id in country_spirits.get(tag, []) as Array:
		var row := _spirit_row(str(spirit_id))
		if not row.is_empty():
			data.permanent_spirits.append(row)

	data.temporary_effects = get_temporary_effect_rows(tag)
	data.permanent_spirit_count = data.permanent_spirits.size()
	data.temporary_effect_count = data.temporary_effects.size()
	data.spirit_categories = _collect_categories(data.permanent_spirits)
	data.effect_sources = _collect_effect_sources(data.temporary_effects)
	return data


func _collect_categories(spirits: Array[Dictionary]) -> Array[String]:
	var cats: Dictionary = {}
	for spirit in spirits:
		var cat := str(spirit.get("category", "")).strip_edges().to_lower()
		if not cat.is_empty():
			cats[cat] = true
	var result: Array[String] = []
	for cat in cats.keys():
		result.append(str(cat))
	result.sort()
	return result


func _collect_effect_sources(effects: Array[Dictionary]) -> Array[String]:
	var sources: Dictionary = {}
	for effect in effects:
		var src := str(effect.get("source", "")).strip_edges()
		if not src.is_empty():
			sources[src] = true
	var result: Array[String] = []
	for src in sources.keys():
		result.append(str(src))
	result.sort()
	return result


func get_temporary_effect_rows(country_tag: String) -> Array[Dictionary]:
	var tag := country_tag.strip_edges().to_upper()
	var rows: Array[Dictionary] = []
	if typeof(NationalModifierManager) == TYPE_NIL:
		return rows

	for effect in NationalModifierManager.get_active_effects(tag):
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		rows.append(_temporary_effect_row(effect as Dictionary))

	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("remaining_months", 0)) < int(b.get("remaining_months", 0))
	)
	return rows


func get_national_effects_snippet(country_tag: String, limit: int = 4) -> Array[Dictionary]:
	var rows := get_temporary_effect_rows(country_tag)
	var result: Array[Dictionary] = []
	for i in range(mini(rows.size(), limit)):
		result.append(rows[i])
	return result


func _spirit_row(spirit_id: String) -> Dictionary:
	if not spirit_definitions.has(spirit_id):
		return {}
	var def: Dictionary = spirit_definitions[spirit_id] as Dictionary
	var modifiers: Dictionary = def.get("modifiers", {})
	var modifier_details := NationalModifierDisplay.modifier_lines_detailed(modifiers)
	var row := {
		"spirit_id": spirit_id,
		"name": str(def.get("name", spirit_id)),
		"description": str(def.get("description", "")),
		"category": str(def.get("category", "")),
		"modifier_lines": _format_modifier_lines(modifiers),
		"modifier_details": modifier_details,
		"filter_kind": "permanent",
		"is_debuff": false,
	}
	row["tooltip_text"] = NationalModifierDisplay.build_spirit_tooltip(row)
	return row


func _temporary_effect_row(effect: Dictionary) -> Dictionary:
	var source := str(effect.get("source", "unknown"))
	var source_label := _source_display_name(source)
	var detail := str(effect.get("source_detail", "")).strip_edges()
	if not detail.is_empty():
		source_label = "%s — %s" % [source_label, detail]

	var modifiers: Dictionary = effect.get("modifiers", {})
	var modifier_details := NationalModifierDisplay.modifier_lines_detailed(modifiers)
	var is_debuff := bool(effect.get("is_debuff", false))
	var remaining := int(effect.get("remaining_months", 0))
	var duration := int(effect.get("duration_months", 0))
	var row := {
		"effect_id": str(effect.get("effect_id", "")),
		"source": source,
		"source_label": source_label,
		"modifier_lines": _format_modifier_lines(modifiers),
		"modifier_details": modifier_details,
		"remaining_months": remaining,
		"duration_months": duration,
		"progress_ratio": NationalModifierDisplay.duration_progress(remaining, duration),
		"is_debuff": is_debuff,
		"filter_kind": "debuff" if is_debuff else "buff",
	}
	row["tooltip_text"] = NationalModifierDisplay.build_effect_tooltip(row)
	return row


func _format_modifier_lines(modifiers: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for key in modifiers.keys():
		var value: float = float(modifiers[key])
		lines.append("%s: %s" % [_modifier_key_label(str(key)), _format_modifier_value(value)])
	return lines


func _modifier_key_label(key: String) -> String:
	return key.replace("_", " ").capitalize()


func _format_modifier_value(value: float) -> String:
	if absf(value) < 1.0 and value != 0.0:
		return "%+.0f%%" % (value * 100.0)
	return "%+.1f" % value


func _source_display_name(source: String) -> String:
	match source:
		"agent_mission", "influence":
			return "Agent operation"
		"agent_sabotage":
			return "Agent sabotage"
		"national_focus":
			return "National focus"
		"event":
			return "National event"
		_:
			return source.replace("_", " ").capitalize()


## Returns production-relevant modifiers from all permanent national spirits for a country.
func get_spirit_production_modifiers(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	ensure_country_spirits(tag)

	var result := {
		"output_multiplier": 1.0,
		"reliability_multiplier": 1.0,
		"retooling_days_multiplier": 1.0,
		"cost_multiplier": 1.0,
		# For layered/additive tech stacking with spirits
		"production_flexibility": 0.0,
		"material_efficiency": 0.0,
	}

	for spirit_id in country_spirits.get(tag, []) as Array:
		if not spirit_definitions.has(spirit_id):
			continue
		var def: Dictionary = spirit_definitions[spirit_id]
		var mods: Dictionary = def.get("modifiers", {})
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
				"production_flexibility":
					result["retooling_days_multiplier"] *= maxf(0.6, 1.0 - val * 0.5)
					result["cost_multiplier"] *= maxf(0.7, 1.0 - val * 0.3)
				"material_efficiency":
					result["cost_multiplier"] *= maxf(0.6, 1.0 - val * 0.4)

	return result


## Convenience: Returns the combined supply_consumption modifier from both permanent spirits and current temporary effects.
func get_total_supply_consumption_modifier(country_tag: String) -> float:
	var total := 0.0

	var spirit := get_spirit_supply_modifiers(country_tag)
	total += float(spirit.get("supply_consumption", 0.0))

	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp: Dictionary = NationalModifierManager.get_supply_modifiers(country_tag)
		total += float(temp.get("supply_consumption", 0.0))

	return total


func get_total_attrition_reduction_modifier(country_tag: String) -> float:
	var total := 0.0
	var spirit := get_spirit_supply_modifiers(country_tag)
	total += float(spirit.get("attrition_reduction", 0.0))

	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp: Dictionary = NationalModifierManager.get_supply_modifiers(country_tag)
		total += float(temp.get("attrition_reduction", 0.0))
	return total


func get_total_interdiction_resistance_modifier(country_tag: String) -> float:
	var total := 0.0
	var spirit := get_spirit_supply_modifiers(country_tag)
	total += float(spirit.get("interdiction_resistance", 0.0))

	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp: Dictionary = NationalModifierManager.get_supply_modifiers(country_tag)
		total += float(temp.get("interdiction_resistance", 0.0))
	return total


## Returns supply-relevant modifiers from permanent national spirits.
func get_spirit_supply_modifiers(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	ensure_country_spirits(tag)

	var result := {
		"supply_consumption": 0.0,
		"attrition_reduction": 0.0,
		"interdiction_resistance": 0.0,
	}

	for spirit_id in country_spirits.get(tag, []) as Array:
		if not spirit_definitions.has(spirit_id):
			continue
		var def: Dictionary = spirit_definitions[spirit_id]
		var mods: Dictionary = def.get("modifiers", {})
		for key in mods.keys():
			var val := float(mods[key])
			match key:
				"supply_consumption", "supply_use", "logistics":
					result["supply_consumption"] += val
				"attrition_reduction", "attrition":
					result["attrition_reduction"] += val
				"interdiction_resistance", "interdiction_reduction", "logistics_security":
					result["interdiction_resistance"] += val

	return result


## Returns combat-relevant modifiers from permanent national spirits.
func get_spirit_combat_modifiers(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	ensure_country_spirits(tag)

	var result := {
		"army_org_factor": 0.0,
		"defence_factor": 0.0,
		"planning_speed": 0.0,
		"manpower_factor": 0.0,
		"attack_factor": 0.0,
		"attrition_reduction": 0.0,
		"interdiction_resistance": 0.0,
		# Extended for new tech expansions (spirits + tech stack)
		"infantry_enhancement": 0.0,
		"soldier_enhancement": 0.0,
		"defensive_shielding": 0.0,
		"energy_weapon_dmg": 0.0,
		"manpower_replacement": 0.0,
		"rapid_deployment": 0.0,
		"precision_strike": 0.0,
	}

	for spirit_id in country_spirits.get(tag, []) as Array:
		if not spirit_definitions.has(spirit_id):
			continue
		var def: Dictionary = spirit_definitions[spirit_id]
		var mods: Dictionary = def.get("modifiers", {})
		for key in mods.keys():
			var val := float(mods[key])
			if key in result:
				result[key] += val
			# Also capture new explicit keys even if not pre-declared
			if key in ["attrition_reduction", "interdiction_resistance"]:
				result[key] = float(result.get(key, 0.0)) + val

	return result
