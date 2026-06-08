class_name DivisionTemplate
extends Resource

@export var id: String = ""
@export var display_name: String = ""
## Scenario country tag (e.g. USA, GER). Inferred from division id when omitted in data.
@export var country_tag: String = ""
@export var manpower: int = 0
@export var support_supply_per_day: float = 0.0
@export var equipment: Array[Dictionary] = []
## Equipment template id (or category key) -> count. Falls back to `equipment` entries when empty.
@export var required_equipment: Dictionary = {}
## Division-wide default infantry weapon template (e.g. infantry_k98_bolt_action).
@export var infantry_equipment_template: String = ""
## Battalion / subunit definitions from JSON (may override infantry_equipment_template per entry).
@export var subunit_defs: Array[Dictionary] = []
## Abstracted bulk gear: uniforms, helmets, ammo, tools, medical, etc.
@export var sustainment_equipment_template: String = "basic_sustainment"

var _resolved_subunits: Array[Dictionary] = []


static func from_dict(data: Dictionary) -> DivisionTemplate:
	var div := DivisionTemplate.new()
	div.id = str(data.get("id", data.get("template_id", "")))
	div.display_name = str(data.get("name", div.id))
	div.country_tag = str(data.get("country_tag", ""))
	div.manpower = int(data.get("manpower", 0))
	div.support_supply_per_day = float(data.get("support_supply_per_day", 0.0))
	var raw_equipment: Variant = data.get("equipment", [])
	if typeof(raw_equipment) == TYPE_ARRAY:
		for item in raw_equipment:
			if typeof(item) == TYPE_DICTIONARY:
				div.equipment.append((item as Dictionary).duplicate(true))
	div.required_equipment = _dict_from_variant(data.get("required_equipment", {}))
	div.infantry_equipment_template = str(data.get("infantry_equipment_template", ""))
	div.sustainment_equipment_template = str(
		data.get("sustainment_equipment_template", "basic_sustainment")
	)
	var raw_subunits: Variant = data.get("subunits", [])
	if typeof(raw_subunits) == TYPE_ARRAY:
		for item in raw_subunits:
			if typeof(item) == TYPE_DICTIONARY:
				div.subunit_defs.append((item as Dictionary).duplicate(true))
	return div


func resolve_subunits(design_data: DesignDataLoader = null) -> void:
	_resolved_subunits.clear()
	var loader := _resolve_design_data(design_data)
	if loader == null:
		return

	for subunit_def in subunit_defs:
		if typeof(subunit_def) != TYPE_DICTIONARY:
			continue
		var resolved := (subunit_def as Dictionary).duplicate(true)
		var equipment_template_id := str(
			resolved.get("infantry_equipment_template", resolved.get("infantry_equipment_override", ""))
		)
		if equipment_template_id.is_empty():
			equipment_template_id = infantry_equipment_template
		_apply_infantry_template_to_subunit(resolved, equipment_template_id, loader)
		_resolved_subunits.append(resolved)

	if _resolved_subunits.is_empty():
		for entry in equipment:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if str(entry.get("type", "")).to_lower() != "infantry":
				continue
			var resolved := entry.duplicate(true)
			var equipment_template_id := _infantry_template_id_for_equipment_entry(entry)
			_apply_infantry_template_to_subunit(resolved, equipment_template_id, loader)
			_resolved_subunits.append(resolved)

	if _resolved_subunits.is_empty() and not infantry_equipment_template.is_empty():
		var division_block := {"source": "division_default"}
		_apply_infantry_template_to_subunit(division_block, infantry_equipment_template, loader)
		_resolved_subunits.append(division_block)


func get_aggregated_infantry_stats(design_data: DesignDataLoader = null) -> Dictionary:
	resolve_subunits(design_data)

	var total_soft := 0.0
	var total_hard := 0.0
	var total_supply := 0.0
	var total_reliability := 0.0
	var sample_count := 0

	for subunit in _resolved_subunits:
		if not subunit.has("infantry_equipment_stats"):
			continue
		var stats: Dictionary = subunit["infantry_equipment_stats"]
		var weight := maxi(int(subunit.get("count", 1)), 1)
		for _i in weight:
			total_soft += float(stats.get("soft_attack", 0.9))
			total_hard += float(stats.get("hard_attack", 0.03))
			total_supply += float(stats.get("supply_consumption", 1.0))
			total_reliability += float(stats.get("reliability", 0.95))
			sample_count += 1

	if sample_count == 0:
		return _default_infantry_stats()

	return {
		"soft_attack": total_soft / float(sample_count),
		"hard_attack": total_hard / float(sample_count),
		"supply_consumption": total_supply / float(sample_count),
		"reliability": total_reliability / float(sample_count),
		"generation": get_reported_generation(),
		"average_generation": get_average_generation(),
		"peak_generation": get_peak_generation(),
	}


func get_peak_generation() -> int:
	resolve_subunits()
	var peak := 1
	for subunit in _resolved_subunits:
		if subunit.has("infantry_equipment_generation"):
			peak = maxi(peak, int(subunit["infantry_equipment_generation"]))
	return peak


## Mixed divisions report the highest generation present (e.g. bolt action + assault rifle → gen 3).
func get_reported_generation() -> int:
	return maxi(get_peak_generation(), get_average_generation())


func get_average_generation() -> int:
	resolve_subunits()
	var total := 0
	var count := 0
	for subunit in _resolved_subunits:
		if subunit.has("infantry_equipment_generation"):
			var weight := maxi(int(subunit.get("count", 1)), 1)
			total += int(subunit["infantry_equipment_generation"]) * weight
			count += weight
	if count == 0:
		return 1
	return int(round(float(total) / float(count)))


func get_resolved_subunits() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for subunit in _resolved_subunits:
		if typeof(subunit) == TYPE_DICTIONARY:
			copy.append((subunit as Dictionary).duplicate(true))
	return copy


func get_sustainment_equipment_template() -> String:
	return sustainment_equipment_template


func get_sustainment_stats(design_data: DesignDataLoader = null) -> Dictionary:
	var loader := _resolve_design_data(design_data)
	if loader == null:
		return {}
	var data := loader.get_sustainment_equipment(sustainment_equipment_template)
	if data.is_empty():
		return {
			"supply_consumption": get_sustainment_consumption_multiplier(design_data),
			"reliability_impact": 0.0,
			"readiness_bonus": 0.0,
		}
	return {
		"supply_consumption": float(data.get("supply_consumption", 1.0)),
		"reliability_impact": float(data.get("reliability_impact", 0.0)),
		"readiness_bonus": float(data.get("readiness_bonus", 0.0)),
		"description": str(data.get("description", "")),
	}


func get_sustainment_consumption_multiplier(design_data: DesignDataLoader = null) -> float:
	return float(get_sustainment_stats(design_data).get("supply_consumption", 1.0))


func get_sustainment_readiness_bonus(design_data: DesignDataLoader = null) -> float:
	return float(get_sustainment_stats(design_data).get("readiness_bonus", 0.0))


func get_sustainment_reliability_impact(design_data: DesignDataLoader = null) -> float:
	return float(get_sustainment_stats(design_data).get("reliability_impact", 0.0))


func get_total_infantry_headcount() -> int:
	var count := 0
	for entry in equipment:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")).to_lower() == "infantry":
			count += int(entry.get("count", 0))
	if count > 0:
		return count
	if manpower > 0:
		return manpower
	return 0


func count_engineer_brigade_equivalent() -> float:
	var total := 0.0
	var division_sustainment := sustainment_equipment_template.to_lower()
	if division_sustainment.contains("engineer"):
		total += 1.0
	for subunit_def in subunit_defs:
		if typeof(subunit_def) != TYPE_DICTIONARY:
			continue
		var subunit_type := _subunit_type_key(subunit_def as Dictionary)
		var weight := maxf(float(maxi(int(subunit_def.get("count", 1)), 1)), 1.0)
		if subunit_type in ["engineer", "combat_engineer"]:
			total += weight
	return total


func get_specialized_sustainment_demand() -> float:
	var extra := 0.0
	var division_sustainment := sustainment_equipment_template.to_lower()
	if division_sustainment.contains("marine") or division_sustainment.contains("amphibious"):
		extra += 180.0
	elif division_sustainment.contains("engineer"):
		extra += 120.0

	for subunit_def in subunit_defs:
		if typeof(subunit_def) != TYPE_DICTIONARY:
			continue
		var subunit_type := _subunit_type_key(subunit_def as Dictionary)
		var weight := maxf(float(maxi(int(subunit_def.get("count", 1)), 1)), 1.0)
		match subunit_type:
			"engineer", "combat_engineer":
				extra += 120.0 * weight
			"marine", "amphibious":
				extra += 180.0 * weight
			"recon", "reconnaissance":
				extra += 60.0 * weight
			"medical", "field_hospital":
				extra += 40.0 * weight
			"signals", "communications":
				extra += 35.0 * weight
			_:
				pass

	return extra


func get_combined_combat_modifiers(design_data: DesignDataLoader = null) -> Dictionary:
	var infantry_stats := get_aggregated_infantry_stats(design_data)
	var sustainment_mult := get_sustainment_consumption_multiplier(design_data)
	var base_reliability := float(infantry_stats.get("reliability", 0.95))
	base_reliability += get_sustainment_reliability_impact(design_data)
	base_reliability = clampf(base_reliability, 0.5, 1.0)

	return {
		"soft_attack": float(infantry_stats.get("soft_attack", 0.9)),
		"hard_attack": float(infantry_stats.get("hard_attack", 0.03)),
		"supply_consumption": float(infantry_stats.get("supply_consumption", 1.0)) * sustainment_mult,
		"reliability": base_reliability,
		"readiness_bonus": get_sustainment_readiness_bonus(design_data),
		"infantry_generation": int(infantry_stats.get("generation", infantry_stats.get("average_generation", 1))),
	}


func get_final_combat_stats(
	current_shortages: Dictionary = {},
	design_data: DesignDataLoader = null,
) -> Dictionary:
	var base := get_combined_combat_modifiers(design_data)

	var soft_attack := float(base.get("soft_attack", 0.9))
	var hard_attack := float(base.get("hard_attack", 0.03))
	var supply_consumption := float(base.get("supply_consumption", 1.0))
	var reliability := float(base.get("reliability", 0.95))
	var readiness := 1.0 + float(base.get("readiness_bonus", 0.0))

	if _shortages_affect_infantry(current_shortages, design_data):
		soft_attack *= 0.7
		reliability *= 0.85

	if _shortages_affect_sustainment(current_shortages, design_data):
		readiness *= 0.75
		supply_consumption *= 1.15

	return {
		"soft_attack": soft_attack,
		"hard_attack": hard_attack,
		"supply_consumption": supply_consumption,
		"reliability": clampf(reliability, 0.5, 1.0),
		"readiness": clampf(readiness, 0.3, 1.5),
		"infantry_generation": int(base.get("infantry_generation", 1)),
		"has_shortages": not current_shortages.is_empty(),
		"has_infantry_shortage": _shortages_affect_infantry(current_shortages, design_data),
		"has_sustainment_shortage": _shortages_affect_sustainment(current_shortages, design_data),
	}


func _shortages_affect_infantry(current_shortages: Dictionary, design_data: DesignDataLoader) -> bool:
	if current_shortages.is_empty():
		return false
	var loader := _resolve_design_data(design_data)
	for equipment_id in current_shortages:
		var key := str(equipment_id)
		if not infantry_equipment_template.is_empty() and key == infantry_equipment_template:
			return true
		if loader != null and loader.get_infantry_equipment(key) != null:
			return true
		if key.begins_with("infantry_"):
			return true
	return false


func _shortages_affect_sustainment(current_shortages: Dictionary, design_data: DesignDataLoader) -> bool:
	if current_shortages.is_empty():
		return false
	var loader := _resolve_design_data(design_data)
	for equipment_id in current_shortages:
		var key := str(equipment_id)
		if not sustainment_equipment_template.is_empty() and key == sustainment_equipment_template:
			return true
		if loader != null and not loader.get_sustainment_equipment(key).is_empty():
			return true
		if key.contains("sustainment"):
			return true
	return false


func get_required_equipment(design_data: DesignDataLoader = null) -> Dictionary:
	var requirements := _build_required_equipment(design_data)
	for equipment_id in required_equipment:
		requirements[str(equipment_id)] = int(required_equipment[equipment_id])
	return requirements


func _build_required_equipment(design_data: DesignDataLoader = null) -> Dictionary:
	var requirements: Dictionary = {}

	if not infantry_equipment_template.is_empty():
		var infantry_count := get_total_infantry_headcount()
		if infantry_count > 0:
			requirements[infantry_equipment_template] = int(
				requirements.get(infantry_equipment_template, 0)
			) + infantry_count

	var sustainment_id := get_sustainment_equipment_template()
	if sustainment_id.is_empty():
		sustainment_id = "basic_sustainment"
	var headcount := get_total_infantry_headcount()
	if headcount > 0:
		var base_sustainment := float(headcount) * 0.8
		var specialized_bonus := get_specialized_sustainment_demand()
		requirements[sustainment_id] = int(ceil(base_sustainment + specialized_bonus))

	for entry in equipment:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var eq_type := str(entry.get("type", "")).to_lower()
		if eq_type == "infantry":
			var infantry_id := _infantry_template_id_for_equipment_entry(entry)
			var infantry_amount := int(entry.get("count", 0))
			if not infantry_id.is_empty() and infantry_amount > 0:
				requirements[infantry_id] = int(requirements.get(infantry_id, 0)) + infantry_amount
			continue
		var template_id := str(entry.get("template_id", ""))
		var amount := int(entry.get("count", 0))
		if eq_type in ["artillery_towed", "truck"] or (template_id.is_empty() and not eq_type.is_empty()):
			var key := template_id if not template_id.is_empty() else eq_type
			if amount > 0:
				requirements[key] = int(requirements.get(key, 0)) + amount
			continue
		if not template_id.is_empty() and amount > 0:
			requirements[template_id] = int(requirements.get(template_id, 0)) + amount

	_append_subunit_sustainment_packages(requirements, design_data)
	return requirements


func _append_subunit_sustainment_packages(requirements: Dictionary, design_data: DesignDataLoader) -> void:
	var loader := _resolve_design_data(design_data)
	if loader == null:
		return
	for subunit_def in subunit_defs:
		if typeof(subunit_def) != TYPE_DICTIONARY:
			continue
		var sub_id := str(subunit_def.get("sustainment_equipment_template", ""))
		if sub_id.is_empty():
			continue
		var weight := maxi(int(subunit_def.get("count", 1)), 1)
		var sub_data := loader.get_sustainment_equipment(sub_id)
		var sub_per_soldier := float(sub_data.get("supply_consumption", 1.0))
		var extra := int(ceil(200.0 * float(weight) * sub_per_soldier))
		requirements[sub_id] = int(requirements.get(sub_id, 0)) + extra


func _subunit_type_key(subunit: Dictionary) -> String:
	var explicit := str(subunit.get("type", "")).to_lower()
	if not explicit.is_empty():
		return explicit
	var template_id := str(subunit.get("template_id", "")).to_lower()
	if template_id.contains("engineer"):
		return "combat_engineer"
	if template_id.contains("marine") or template_id.contains("amphibious"):
		return "marine"
	if template_id.contains("recon"):
		return "recon"
	if template_id.contains("medical") or template_id.contains("hospital"):
		return "medical"
	if template_id.contains("signal"):
		return "signals"
	return ""


func _infantry_template_id_for_equipment_entry(entry: Dictionary) -> String:
	var override: Variant = entry.get("infantry_equipment_override")
	if override != null:
		var override_text := str(override)
		if not override_text.is_empty() and override_text.to_lower() != "null":
			return override_text
	return infantry_equipment_template


func _apply_infantry_template_to_subunit(
	subunit: Dictionary,
	equipment_template_id: String,
	loader: DesignDataLoader,
) -> void:
	if equipment_template_id.is_empty():
		return
	var infantry_template := loader.get_infantry_equipment(equipment_template_id)
	if infantry_template == null:
		return
	subunit["infantry_equipment_template"] = equipment_template_id
	subunit["infantry_equipment_stats"] = infantry_template.get_infantry_stats()
	subunit["infantry_equipment_generation"] = infantry_template.infantry_equipment_generation
	subunit["infantry_equipment_type"] = infantry_template.infantry_equipment_type


func _resolve_design_data(design_data: DesignDataLoader) -> DesignDataLoader:
	if design_data != null:
		return design_data
	if GameData.design_data != null:
		return GameData.design_data
	return null


static func _default_infantry_stats() -> Dictionary:
	return {
		"soft_attack": 0.9,
		"hard_attack": 0.03,
		"supply_consumption": 1.0,
		"reliability": 0.95,
		"generation": 1,
		"average_generation": 1,
	}


static func _dict_from_variant(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for key in raw:
		out[str(key)] = int(raw[key])
	return out
