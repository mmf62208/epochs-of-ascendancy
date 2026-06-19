## Cross-category retooling similarity for factory design changes.
class_name RetoolingSimilarityTable
extends RefCounted

const DATA_PATH := "res://data/production/retooling_similarity.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func get_data() -> Dictionary:
	_load()
	return _data


static func get_similarity(from_group: String, to_group: String) -> float:
	_load()
	var table: Dictionary = _data.get("similarity", {})
	var from_row: Variant = table.get(from_group, {})
	if typeof(from_row) != TYPE_DICTIONARY:
		return float(_data.get("default_floor", 0.20))
	var score := float((from_row as Dictionary).get(to_group, _data.get("default_floor", 0.20)))
	return clampf(score, 0.0, 1.0)


static func map_production_category_to_group(category: String) -> String:
	var cat := category.to_lower()
	match cat:
		"medium_tank", "heavy_tank", "light_tank", "tank_afv":
			return "tank_afv"
		"light_vehicle", "light_tank", "vehicle_truck":
			return "vehicle_truck"
		"fighter", "bomber", "airplane", "air":
			return "airplane"
		"destroyer", "cruiser", "battleship", "carrier", "submarine", "ship", "naval":
			return "ship"
		"rocket", "rocket_missile", "missile":
			return "rocket_missile"
		"infantry_equipment", "infantry":
			return "infantry_equipment"
		"artillery":
			return "artillery"
		"space":
			return "rocket_missile"
		_:
			return "tank_afv"


static func category_group_for_design(design_id: String) -> String:
	if design_id.is_empty() or GameData.design_data == null:
		return "tank_afv"
	var template: UnitTemplate = GameData.design_data.get_template(design_id)
	if template == null:
		return "tank_afv"
	return map_production_category_to_group(template.get_inferred_production_category())


static func compute_retool_plan(from_group: String, to_group: String) -> Dictionary:
	_load()
	var similarity := get_similarity(from_group, to_group)
	var efficiency_floor := float(_data.get("default_floor", 0.20))
	var retained_rules: Dictionary = _data.get("retained_efficiency", {})
	var retained_base := float(retained_rules.get("base", 0.15))
	var retained_scale := float(retained_rules.get("similarity_scale", 0.80))
	var retained := maxf(efficiency_floor, retained_base + similarity * retained_scale)

	var base_days := float(_data.get("base_retool_days", 90.0))
	var recovery := float(_data.get("recovery_days", 45.0))
	var dissimilarity := 1.0 - similarity
	var retool_days := maxf(base_days * dissimilarity, 3.0)
	var recovery_days := maxf(recovery * dissimilarity, 1.0)

	return {
		"from_group": from_group,
		"to_group": to_group,
		"similarity": similarity,
		"retained_efficiency": retained,
		"retool_days": retool_days,
		"recovery_days": recovery_days,
	}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("RetoolingSimilarityTable: missing ", DATA_PATH)
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) == OK and typeof(parser.data) == TYPE_DICTIONARY:
		_data = parser.data
