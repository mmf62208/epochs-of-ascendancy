class_name UnitTemplate
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var base_type: String = ""
@export var size_category: String = ""
@export var visual_archetype: String = ""
@export var design_family: String = ""
@export var crew_required: int = 0
@export var base_training_level: int = 0
@export var max_experience_level: int = 100
@export var base_stats: Dictionary = {}
@export var slots: Dictionary = {}
@export var module_loadout: Dictionary = {}
@export var unlock_tech: Array[String] = []
@export var can_mount_drones: bool = false
@export var is_vehicle: bool = true
@export var base_production_days: float = 60.0
## Production Points to complete one unit (0 = auto from category + build days).
@export var production_cost: float = 0.0
@export var production_category: String = ""
@export var production_era: String = ""
## Calendar year design enters service (0 = infer from era / id).
@export var unlock_year: int = 0
## Lifecycle grouping for obsolescence (e.g. mbt, fighter); defaults to inferred production category.
@export var lifecycle_category: String = ""
@export var lifecycle_role: String = ""
## UI domain filter: land, naval, air, support (empty = infer).
@export var design_domain: String = ""

## Nation-specific design support (Phase 1 for Map Build Eligibility + future trade/capture).
## Empty or ["all"] = available to every country by default (exportable baseline).
## Otherwise, list of country_tags that own this design natively.
@export var owner_countries: Array[String] = []

## Explicitly marked as exportable / tradeable even if not natively owned.
## Future trade/capture mechanics will add designs to a country's acquired list.
@export var exportable: bool = false
## ISO-style country tag (GER, USA). Empty = infer from design_family / id, or universal generic.
@export var design_nation: String = ""
@export var production_complexity: float = 1.0
@export var daily_resource_cost: Dictionary = {}
## Equipment template id -> count required to field this design at full strength.
@export var required_equipment: Dictionary = {}
## Small-arms profile: rifle, assault_rifle, lmg, heavy_machine_gun, etc.
@export var infantry_equipment_type: String = ""
## 1 = bolt, 2 = semi-auto, 3 = assault, 4 = modern
@export var infantry_equipment_generation: int = 0
## soft_attack, hard_attack, reliability, supply_consumption
@export var infantry_equipment_stats: Dictionary = {}
## Production / supply draw per soldier when this weapon is issued.
@export var infantry_equipment_per_soldier: float = 1.0
@export var sustainment_equipment_per_soldier: float = 1.0
@export var description: String = ""
## Fielded-template land composition (designer duties). Empty = infer from id/visual.
@export var composition: Dictionary = {}


func get_module_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot_name in module_loadout:
		var module_id := str(module_loadout[slot_name])
		if not module_id.is_empty():
			ids.append(module_id)
	return ids


func count_filled_slots() -> int:
	return get_module_ids().size()


func get_base_reliability() -> float:
	return float(base_stats.get("reliability", 50.0))


func get_stat(stat_name: String, default_value: float = 0.0) -> float:
	return float(base_stats.get(stat_name, default_value))


func get_fuel_consumption() -> float:
	return get_stat("fuel_consumption", 0.0)


func get_supply_need() -> float:
	return get_stat("supply_need", 0.0)


## STORED (in port/airfield), READIED, TRAINING, COMBAT — see supply_rules.json consumption_rates.
func get_daily_supply_draw(mode: String, rules: SupplyRules) -> Dictionary:
	var req := UnitSupplyRequirements.from_template(self, rules)
	return req.daily_consumption_cargo(mode, rules)


static func from_dict(data: Dictionary) -> UnitTemplate:
	var tpl := UnitTemplate.new()
	tpl.id = str(data.get("id", data.get("template_id", "")))
	tpl.display_name = str(data.get("name", tpl.id))
	tpl.description = str(data.get("description", ""))
	tpl.base_type = str(data.get("base_type", ""))
	tpl.size_category = str(data.get("size_category", ""))
	tpl.visual_archetype = str(data.get("visual_archetype", ""))
	tpl.design_family = str(data.get("design_family", ""))
	tpl.crew_required = int(data.get("crew_required", 0))
	tpl.base_training_level = int(data.get("base_training_level", 0))
	tpl.max_experience_level = int(data.get("max_experience_level", 100))
	tpl.base_stats = _dict_from_variant(data.get("base_stats", {}))
	tpl.slots = _dict_from_variant(data.get("slots", {}))
	tpl.module_loadout = _dict_from_variant(data.get("module_loadout", {}))
	tpl.unlock_tech = _string_array(data.get("unlock_tech", []))
	tpl.can_mount_drones = bool(data.get("can_mount_drones", false))
	tpl.is_vehicle = bool(data.get("is_vehicle", true))
	tpl.base_production_days = float(data.get("base_production_days", data.get("production_days", 60)))
	tpl.production_cost = float(data.get("production_cost", 0.0))
	tpl.production_category = str(data.get("production_category", data.get("category", "")))
	tpl.production_era = str(data.get("era", data.get("production_era", "")))
	tpl.unlock_year = int(data.get("unlock_year", 0))
	tpl.lifecycle_category = str(data.get("lifecycle_category", data.get("category", "")))
	tpl.lifecycle_role = str(data.get("lifecycle_role", data.get("role", "")))
	tpl.design_domain = str(data.get("design_domain", data.get("domain", "")))
	tpl.design_nation = str(data.get("design_nation", data.get("nation", ""))).strip_edges().to_upper()

	# Nation-specific design support (new)
	tpl.owner_countries = _string_array(data.get("owner_countries", data.get("nations", [])))
	tpl.exportable = bool(data.get("exportable", false))
	if tpl.owner_countries.is_empty() and data.has("design_nation"):
		# Back-compat: single nation field becomes owner list
		var single = str(data.get("design_nation", "")).strip_edges().to_upper()
		if not single.is_empty() and single != "ALL":
			tpl.owner_countries = [single]
	tpl.production_complexity = float(data.get("production_complexity", data.get("complexity", 1.0)))
	tpl.daily_resource_cost = _dict_from_variant(data.get("daily_resource_cost", {}))
	tpl.required_equipment = _dict_from_variant(data.get("required_equipment", {}))
	tpl.infantry_equipment_type = str(data.get("infantry_equipment_type", ""))
	tpl.infantry_equipment_generation = int(data.get("infantry_equipment_generation", 0))
	tpl.infantry_equipment_per_soldier = float(data.get("infantry_equipment_per_soldier", 1.0))
	tpl.sustainment_equipment_per_soldier = float(data.get("sustainment_equipment_per_soldier", 1.0))
	tpl.infantry_equipment_stats = _parse_infantry_equipment_stats(data)
	tpl.composition = _dict_from_variant(data.get("composition", {}))
	if tpl.composition.is_empty():
		for key in ["mobility", "armor_element", "support", "infantry_bns", "tank_bns"]:
			if data.has(key) and str(data.get(key, "")).strip_edges() != "":
				tpl.composition[str(key)] = data[key]
	if tpl.is_infantry_equipment():
		if tpl.base_type.is_empty():
			tpl.base_type = "InfantryEquipment"
		if tpl.production_category.is_empty():
			tpl.production_category = "infantry_equipment"
		if tpl.visual_archetype.is_empty():
			tpl.visual_archetype = tpl.infantry_equipment_type
		tpl.is_vehicle = bool(data.get("is_vehicle", false))
		if tpl.design_family.is_empty():
			tpl.design_family = "infantry_equipment"
	return tpl


static func _parse_infantry_equipment_stats(data: Dictionary) -> Dictionary:
	var stats := _float_dict_from_variant(data.get("infantry_equipment", {}))
	for key in ["soft_attack", "hard_attack", "reliability", "supply_consumption"]:
		if data.has(key):
			stats[key] = float(data[key])
	return stats


func get_required_equipment() -> Dictionary:
	return required_equipment.duplicate(true)


func is_infantry_equipment() -> bool:
	return (
		infantry_equipment_type != ""
		or infantry_equipment_generation > 0
		or not infantry_equipment_stats.is_empty()
		or production_category == "infantry_equipment"
	)


func get_infantry_equipment_stats() -> Dictionary:
	return get_infantry_stats()


func get_infantry_stats() -> Dictionary:
	if infantry_equipment_stats.is_empty():
		return {
			"soft_attack": 0.9,
			"hard_attack": 0.03,
			"supply_consumption": 1.0,
			"reliability": 0.95,
		}
	return infantry_equipment_stats.duplicate(true)


func get_infantry_generation_multiplier() -> float:
	return 1.0 + float(infantry_equipment_generation - 1) * 0.08


func get_daily_resource_cost_dict() -> Dictionary:
	if not daily_resource_cost.is_empty():
		return daily_resource_cost.duplicate(true)
	return ProductionCostCalculator.resolve_daily_resource_cost(self)


func get_production_point_cost(
	design_data: DesignDataLoader = null,
	loadout_override: Dictionary = {},
) -> float:
	return ProductionCostCalculator.resolve_cost(self, design_data, loadout_override)


func get_production_cost_breakdown(
	design_data: DesignDataLoader = null,
	loadout_override: Dictionary = {},
) -> Dictionary:
	return ProductionCostCalculator.resolve_cost_breakdown(self, design_data, loadout_override)


func get_inferred_production_category() -> String:
	if not production_category.is_empty():
		return production_category
	return ProductionCostCalculator.infer_category(self)


func get_inferred_production_era() -> String:
	return ProductionCostCalculator.infer_era(self)


static func _dict_from_variant(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw.duplicate(true)


static func _float_dict_from_variant(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for key in raw:
		out[str(key)] = float(raw[key])
	return out


static func _string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		out.append(str(item))
	return out
