## Production Point costs: (base + modules) × era × (1 + complexity penalty).
## Modules only add to total cost; era scales the combined base+module subtotal.
class_name ProductionCostCalculator
extends RefCounted

const RULES_PATH := "res://data/production/production_cost_rules.json"

static var _rules: Dictionary = {}
static var _loaded: bool = false


static func get_rules() -> Dictionary:
	_load_rules()
	return _rules


static func get_base_daily_points() -> float:
	return float(get_rules().get("base_daily_points", 12.0))


## Dictionary-based API for generators and JSON templates.
static func calculate_production_cost(template: Dictionary) -> float:
	if template.is_empty():
		return 100.0

	if float(template.get("production_cost", 0)) > 0.0 and bool(template.get("_cost_locked", false)):
		return float(template["production_cost"])

	_load_rules()
	var category := _infer_category_from_dict(template)
	var era := _infer_era_from_dict(template)
	var module_ids := _extract_module_ids_from_dict(template)
	var complexity := maxf(float(template.get("production_complexity", template.get("complexity", 1.0))), 0.1)

	return _compute_total(category, era, module_ids, complexity, null)


static func resolve_cost(
	template: UnitTemplate,
	design_data: DesignDataLoader = null,
	loadout_override: Dictionary = {},
) -> float:
	var breakdown := resolve_cost_breakdown(template, design_data, loadout_override)
	return float(breakdown.get("total", 100.0))


static func resolve_cost_breakdown(
	template: UnitTemplate,
	design_data: DesignDataLoader = null,
	loadout_override: Dictionary = {},
) -> Dictionary:
	if template == null:
		return {"total": 100.0}

	_load_rules()
	var category := infer_category(template)
	var era := infer_era(template)
	var module_ids := _collect_module_ids(template, loadout_override)
	var complexity := maxf(template.production_complexity, 0.1)
	var total := _compute_total(category, era, module_ids, complexity, design_data)

	var module_total := 0.0
	var module_details: Array[Dictionary] = []
	for module_id in module_ids:
		var mod := _get_module(design_data, module_id)
		var mod_cost := _module_production_cost(mod, module_id)
		module_total += mod_cost
		module_details.append({"id": module_id, "cost": mod_cost, "type": _infer_module_cost_key(mod, module_id)})

	var base := float(_rules.get("base_costs", {}).get(category, _rules.get("base_costs", {}).get("default", 100.0)))
	var era_mult := float(_rules.get("era_multipliers", {}).get(era, 1.0))
	var penalty := _complexity_penalty_additive(module_ids.size())

	return {
		"total": total,
		"category": category,
		"era": era,
		"base_cost": base,
		"era_multiplier": era_mult,
		"module_count": module_ids.size(),
		"module_cost_total": module_total,
		"module_details": module_details,
		"complexity_penalty": penalty,
		"template_complexity": complexity,
	}


static func _compute_total(
	category: String,
	era: String,
	module_ids: Array,
	template_complexity: float,
	design_data: DesignDataLoader,
) -> float:
	_load_rules()
	var base_costs: Dictionary = _rules.get("base_costs", {})
	var base := float(base_costs.get(category, base_costs.get("default", 100.0)))

	var module_total := 0.0
	for module_id in module_ids:
		var mod := _get_module(design_data, str(module_id))
		module_total += _module_production_cost(mod, str(module_id))

	var era_mult := float(_rules.get("era_multipliers", {}).get(era, 1.0))
	var penalty := _complexity_penalty_additive(module_ids.size())
	var total := (base + module_total) * era_mult * (1.0 + penalty) * template_complexity
	return maxf(round(total), 1.0)


static func infer_category(template: UnitTemplate) -> String:
	return _infer_category_from_dict(_template_to_dict(template))


static func infer_era(template: UnitTemplate) -> String:
	return _infer_era_from_dict(_template_to_dict(template))


static func estimate_build_days(production_cost: float, daily_points: float = -1.0) -> float:
	if daily_points < 0.0:
		daily_points = get_base_daily_points()
	if daily_points <= 0.0:
		return 9999.0
	return production_cost / daily_points


static func _template_to_dict(template: UnitTemplate) -> Dictionary:
	return {
		"id": template.id,
		"name": template.display_name,
		"base_type": template.base_type,
		"size_category": template.size_category,
		"visual_archetype": template.visual_archetype,
		"design_family": template.design_family,
		"base_production_days": template.base_production_days,
		"production_category": template.production_category,
		"era": template.production_era,
		"production_era": template.production_era,
		"module_loadout": template.module_loadout,
		"base_stats": template.base_stats,
	}


static func _infer_category_from_dict(template: Dictionary) -> String:
	var cat := str(template.get("production_category", template.get("category", "")))
	if not cat.is_empty():
		return _normalize_category(cat)

	var id_lower := str(template.get("id", "")).to_lower()
	var arch := str(template.get("visual_archetype", "")).to_lower()
	var size := str(template.get("size_category", "")).to_lower()
	var bt := str(template.get("base_type", "")).to_lower()
	var name_lower := str(template.get("name", "")).to_lower()

	if "icbm" in id_lower or "rocket" in id_lower or "missile" in id_lower or "ballistic" in id_lower:
		return "rocket"
	if bt == "submarine" or "submarine" in arch or "ssn" in id_lower or "ssbn" in id_lower:
		return "submarine"
	if "carrier" in id_lower or "carrier" in name_lower or "lhd" in id_lower or "cvb" in id_lower:
		return "carrier"
	if "battleship" in id_lower or "battleship" in name_lower or "_bb" in id_lower or id_lower.ends_with("_bb"):
		return "battleship"
	if "cruiser" in id_lower or "cruiser" in name_lower or "_ca" in id_lower:
		return "cruiser"
	if bt == "naval":
		return "destroyer"
	if bt == "air":
		if "bomber" in id_lower or "bomber" in arch or "strategic" in name_lower:
			return "bomber"
		return "fighter"
	if bt == "armored":
		if size == "heavy" or "heavy" in id_lower:
			return "heavy_tank"
		if size == "light" or "light_tank" in arch:
			return "light_tank"
		return "medium_tank"
	if bt == "land":
		if "truck" in id_lower or "transport" in id_lower or "cargo" in id_lower:
			return "light_tank"
		if "infantry" in id_lower or "rifle" in id_lower:
			return "infantry_equipment"
		if "mbt" in id_lower or "tank" in id_lower:
			return "medium_tank"
		return "light_tank"
	if "space" in bt or "orbital" in id_lower:
		return "space"
	return "medium_tank"


static func _infer_era_from_dict(template: Dictionary) -> String:
	var era := str(template.get("era", template.get("production_era", "")))
	if not era.is_empty():
		if era == "cold_war":
			return "early_cold_war"
		return era

	var base_stats: Variant = template.get("base_stats", {})
	if typeof(base_stats) == TYPE_DICTIONARY:
		var era_override := str((base_stats as Dictionary).get("production_era", ""))
		if not era_override.is_empty():
			return era_override

	var id_lower := str(template.get("id", "")).to_lower()
	var family := str(template.get("design_family", "")).to_lower()

	if "2030" in id_lower or "2040" in id_lower or "space" in family or "orbital" in id_lower:
		return "future"
	if "2026" in id_lower or "2020" in id_lower or "2010" in id_lower or "2000" in id_lower:
		return "modern"
	if "1990" in id_lower or "1980" in id_lower or "1970" in id_lower or "sixties" in family:
		return "late_cold_war"
	if "1960" in id_lower or "1950" in id_lower or "cold_war" in family:
		return "early_cold_war"
	if "1945" in id_lower or "1944" in id_lower or "1943" in id_lower or "1942" in id_lower or "1940" in id_lower:
		return "ww2"
	if "1936" in id_lower or "1939" in id_lower or "interwar" in family:
		return "interwar"
	if "1918" in id_lower or "ww1" in family or "great_war" in family:
		return "ww1"
	if "ww2" in family or "world_war_2" in family or "naval_ww2" in family:
		return "ww2"
	if "cold_war" in family:
		return "early_cold_war"
	if "2026" in family or "2030" in family or "modern" in family:
		return "modern"
	if "space" in family:
		return "future"

	var days := float(template.get("base_production_days", template.get("production_days", 60)))
	if days >= 280.0:
		return "modern"
	if days >= 200.0:
		return "late_cold_war"
	if days >= 140.0:
		return "early_cold_war"
	if days >= 90.0:
		return "ww2"
	if days >= 55.0:
		return "interwar"
	return "ww1"


static func _extract_module_ids_from_dict(template: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var modules: Variant = template.get("modules", [])
	if typeof(modules) == TYPE_ARRAY:
		for mod in modules:
			if mod is String and not mod.is_empty():
				ids.append(mod)
			elif typeof(mod) == TYPE_DICTIONARY:
				var mid := str(mod.get("module_id", mod.get("id", "")))
				if not mid.is_empty() and mid not in ids:
					ids.append(mid)
		if not ids.is_empty():
			return ids

	var loadout: Variant = template.get("module_loadout", {})
	if typeof(loadout) == TYPE_DICTIONARY:
		for key in loadout:
			var module_id := str(loadout[key])
			if not module_id.is_empty() and module_id not in ids:
				ids.append(module_id)
	return ids


static func _collect_module_ids(template: UnitTemplate, loadout_override: Dictionary) -> Array[String]:
	var dict := _template_to_dict(template)
	if not loadout_override.is_empty():
		dict["module_loadout"] = loadout_override
	return _extract_module_ids_from_dict(dict)


static func _get_module(design_data: DesignDataLoader, module_id: String) -> EquipmentModule:
	if design_data != null:
		return design_data.get_module(module_id)
	return null


static func _module_production_cost(mod: EquipmentModule, module_id: String) -> float:
	var module_costs: Dictionary = _rules.get("module_costs", {})
	var tier_rules: Dictionary = _rules.get("module_tier_scaling", {})
	var per_tier := float(tier_rules.get("per_tier_bonus", 0.12))
	var key := _infer_module_cost_key(mod, module_id)
	var base := float(module_costs.get(key, module_costs.get("default", 6.0)))
	var tier := mod.tier if mod != null else 1
	var tier_mult := 1.0 + maxf(float(tier) - 1.0, 0.0) * per_tier
	return base * tier_mult


static func _infer_module_cost_key(mod: EquipmentModule, module_id: String) -> String:
	var category := mod.category if mod != null else ""
	var flags: Array = mod.special_flags if mod != null else []
	return _infer_module_cost_key_from_id(module_id, category, flags)


static func _infer_module_cost_key_from_id(
	module_id: String,
	category: String = "",
	flags: Array = [],
) -> String:
	var id_lower := module_id.to_lower()
	var cat_lower := category.to_lower()

	for flag in flags:
		var f := str(flag).to_lower()
		if "stealth" in f:
			return "stealth_coating"

	if "stealth" in id_lower or "low_observable" in id_lower:
		return "stealth_coating"
	if "missile" in id_lower or "sam" in id_lower or "aam" in id_lower or "torpedo" in id_lower:
		return "missile_system"
	if "radar" in id_lower or "sonar" in id_lower or "asw" in id_lower:
		return "radar"
	if "fire_control" in id_lower or "fcs" in id_lower or "director" in id_lower:
		return "fire_control"
	if "computer" in id_lower or "electronics" in id_lower or "ew" in id_lower or "ecm" in id_lower:
		return "fire_control" if "fire" in id_lower else "advanced_electronics"
	if "engine" in id_lower or "turbine" in id_lower or "propulsion" in id_lower:
		return "engine"
	if "armor" in id_lower or "belt" in id_lower or "plate" in id_lower:
		return "armor_plate"
	if "gun" in id_lower or "cannon" in id_lower or "howitzer" in id_lower or "rifle" in id_lower:
		return "gun"

	if cat_lower.contains("weapon") or cat_lower == "mainweapon" or cat_lower == "secondaryweapon":
		return "gun"
	if cat_lower.contains("engine"):
		return "engine"
	if cat_lower.contains("armor"):
		return "armor_plate"
	if cat_lower.contains("sensor") or cat_lower.contains("fire"):
		return "fire_control"
	if cat_lower.contains("electronic"):
		return "advanced_electronics"
	return "default"


static func _complexity_penalty_additive(module_count: int) -> float:
	var penalty: Dictionary = _rules.get("complexity_penalty", {})
	var free_modules := int(penalty.get("free_modules", 4))
	var per_extra := float(penalty.get("per_module_after_4", penalty.get("per_module_after", 0.08)))
	var extra := maxi(module_count - free_modules, 0)
	return float(extra) * per_extra


static func _normalize_category(category: String) -> String:
	var cat := category.to_lower()
	if cat == "light_vehicle" or cat == "vehicle":
		return "light_tank"
	return cat


static func resolve_daily_resource_cost(template: UnitTemplate) -> Dictionary:
	if template == null:
		return {}
	_load_rules()
	if not template.daily_resource_cost.is_empty():
		return template.daily_resource_cost.duplicate(true)
	return resolve_daily_resource_cost_from_dict(_template_to_dict(template))


static func resolve_daily_resource_cost_from_dict(template: Dictionary) -> Dictionary:
	if template.is_empty():
		return {}
	var embedded: Variant = template.get("daily_resource_cost", {})
	if typeof(embedded) == TYPE_DICTIONARY and not (embedded as Dictionary).is_empty():
		return (embedded as Dictionary).duplicate(true)

	_load_rules()
	var category := _normalize_category(_infer_category_from_dict(template))
	var table: Dictionary = _rules.get("resource_costs_per_day", {})
	var base: Variant = table.get(category, table.get("default", {}))
	if typeof(base) != TYPE_DICTIONARY:
		return {}

	var era := _infer_era_from_dict(template)
	var era_mult := float(_rules.get("era_multipliers", {}).get(era, 1.0))
	var module_ids := _extract_module_ids_from_dict(template)
	var module_factor := 1.0 + maxf(float(module_ids.size() - 2), 0.0) * 0.05
	var complexity := maxf(float(template.get("production_complexity", 1.0)), 0.1)
	var scale := era_mult * module_factor * complexity

	var out: Dictionary = {}
	for resource in base:
		out[resource] = snappedf(float(base[resource]) * scale, 0.01)
	return out


## Strategic shortage math (single source for ProductionManager + pure tests).
## Soft shortage: never fully halt; floor from resource_shortage.min_output_multiplier.
static func get_major_resource_ids() -> PackedStringArray:
	_load_rules()
	var majors: Variant = _rules.get("major_resources", {})
	var out: PackedStringArray = []
	if majors is Dictionary:
		for k in majors:
			out.append(str(k))
	if out.is_empty():
		out = PackedStringArray([
			"steel", "aluminum", "energy", "fuel", "rubber", "electronics", "specials", "fissiles"
		])
	return out


static func get_critical_resource_set() -> Dictionary:
	_load_rules()
	var rs: Variant = _rules.get("resource_shortage", {})
	var raw: Variant = []
	if rs is Dictionary:
		raw = (rs as Dictionary).get("critical_resources", [])
	var critical_set: Dictionary = {}
	if typeof(raw) == TYPE_ARRAY:
		for item in raw:
			critical_set[str(item).to_lower()] = true
	return critical_set


static func compute_weighted_fill_ratio(needed: Dictionary, have: Dictionary) -> float:
	"""Fill ratio in [0,1] from stockpile vs daily need. Critical resources weight shortages harder."""
	if needed.is_empty():
		return 1.0
	_load_rules()
	var critical := get_critical_resource_set()
	var rs: Variant = _rules.get("resource_shortage", {})
	var speed_weight := 1.45
	if rs is Dictionary:
		speed_weight = float((rs as Dictionary).get("critical_speed_weight", 1.45))
	var effective := 1.0
	for resource in needed:
		var required := float(needed[resource])
		if required <= 0.0:
			continue
		var have_amt := float(have.get(resource, 0.0))
		var ratio := clampf(have_amt / required, 0.0, 1.0)
		# Critical shortages hurt more: power > 1 compresses fill (0.5^1.45 ≈ 0.37).
		if critical.has(str(resource).to_lower()):
			ratio = pow(ratio, maxf(speed_weight, 1.0))
		effective = minf(effective, ratio)
	return effective


static func compute_shortage_multipliers(fill_ratio: float) -> Dictionary:
	"""Map fill_ratio → production speed + finished-unit reliability multipliers."""
	_load_rules()
	var rules: Dictionary = {}
	if _rules.get("resource_shortage") is Dictionary:
		rules = _rules["resource_shortage"] as Dictionary
	var min_output := float(rules.get("min_output_multiplier", 0.55))
	var min_reliability := float(rules.get("min_reliability_multiplier", 0.72))
	var ratio := clampf(fill_ratio, 0.0, 1.0)
	var speed := lerpf(min_output, 1.0, ratio)
	var reliability := lerpf(min_reliability, 1.0, ratio)
	var critical := get_critical_resource_set()
	if not critical.is_empty() and ratio < 1.0:
		var crit_weight := float(rules.get("critical_reliability_weight", 1.25))
		var crit_floor := lerpf(min_reliability, min_reliability * 0.9, 1.0 - ratio)
		reliability = minf(reliability, lerpf(crit_floor, 1.0, pow(ratio, maxf(crit_weight, 1.0))))
	return {
		"speed": clampf(speed, min_output, 1.0),
		"reliability": clampf(reliability, min_reliability, 1.0),
		"fill_ratio": ratio,
	}


static func compute_resource_outcome(needed: Dictionary, have: Dictionary) -> Dictionary:
	"""End-to-end shortage outcome without mutating stockpiles (preview / dual evidence)."""
	var fill := compute_weighted_fill_ratio(needed, have)
	var mults := compute_shortage_multipliers(fill)
	var missing: Dictionary = {}
	for resource in needed:
		var required := float(needed[resource])
		var have_amt := float(have.get(resource, 0.0))
		if have_amt + 0.001 < required:
			missing[resource] = required - have_amt
	return {
		"fill_ratio": fill,
		"output_multiplier": float(mults.get("speed", 1.0)),
		"reliability_multiplier": float(mults.get("reliability", 1.0)),
		"afforded": fill >= 1.0,
		"partial": fill > 0.0 and fill < 1.0,
		"missing": missing,
		"shortage_ok": float(mults.get("speed", 1.0)) < 0.999 or fill >= 1.0,
	}


static func _load_rules() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(RULES_PATH):
		push_warning("ProductionCostCalculator: missing ", RULES_PATH)
		return
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) == OK and typeof(parser.data) == TYPE_DICTIONARY:
		_rules = parser.data
