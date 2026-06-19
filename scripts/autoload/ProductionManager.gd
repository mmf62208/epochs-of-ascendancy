extends Node

@onready var factory_manager: Node = get_node_or_null("/root/FactoryManager")

## National production coordinator: multiple lines, design families, focus/doctrine modifiers.

signal line_registered(line_id: String)
signal line_removed(line_id: String)
signal stance_changed(stance_id: String)
signal modifier_registered(modifier_id: String, source: String)
signal modifier_removed(modifier_id: String)
signal day_advanced(report: Dictionary)
signal family_experience_changed(family_id: String, total_units: int)
signal production_completed(line_id: String, design_id: String, count: int)
signal production_progress_updated(line_id: String, progress: float)
signal production_resource_shortage(line_id: String, missing: Dictionary)
signal equipment_added_to_stockpile(equipment_id: String, amount: int)
signal equipment_taken_from_stockpile(equipment_id: String, amount: int)
signal unit_reinforced(unit_id: String, equipment_fulfilled: Dictionary)

const GLOBAL_MODIFIERS_PATH := "res://data/production/global_modifiers.json"
const STANCE_TAG := "stance"
const RETOOLING_RULES_PATH := "res://data/production/retooling_similarity.json"

var production_stance: String = "balanced"

## Active production lines: line_id -> ProductionLine
var _lines: Dictionary = {}

# === Retooling system ===
var retooling_rules: Dictionary = {}

var _active_modifiers: Dictionary = {}
var _family_units_produced: Dictionary = {}
var _stance_presets: Dictionary = {}
var _doctrine_presets: Dictionary = {}
var _focus_presets: Dictionary = {}
var _rules: Dictionary = {}
## National resource pool used to pay refinement / shakedown project costs (steel, fuel, etc.).
var national_stockpile: Dictionary = {}
# === National equipment stockpile (finished designs / small arms / vehicles) ===
var national_equipment_stockpile: Dictionary = {}  # equipment_id -> int amount (legacy/global fallback)
var country_equipment_stockpiles: Dictionary = {}  # country_tag -> {equipment_id: int amount} for per-nation starting equipment, OOB stockpiles etc.
var country_civilian_goods: Dictionary = {}  # country_tag -> int goods (civilian output from factories; drives happiness per roadmap)
## unit_id -> { equipment_template_id: count } currently assigned to the formation.
var _unit_equipment_stock: Dictionary = {}

var _equipment_shortage_tracker := EquipmentShortageTracker.new()

# === Reinforcement & priority system ===
var priority_reinforcement_units: Dictionary = {}  # unit_id -> bool

# === Screen data caching ===
var _production_screen_cache: Dictionary = {}  # country_tag -> ProductionScreenData


func _ready() -> void:
	_rules = GameData.design_data.production_rules
	_load_modifier_presets()
	_load_retooling_rules()
	if not production_completed.is_connected(_on_production_completed):
		production_completed.connect(_on_production_completed)

	# Wire to central TimeManager daily tick so production simulation is part of the unified
	# daily loop (alongside Supply, Agent networks, and infrastructure repair).
	# This strengthens the daily simulation without changing existing manual tick paths.
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)


func _get_base_daily_points() -> float:
	return ProductionCostCalculator.get_base_daily_points()


func _load_retooling_rules() -> void:
	retooling_rules = {}
	if not ResourceLoader.exists(RETOOLING_RULES_PATH):
		push_warning("retooling_similarity.json not found — using defaults")
		return
	var file := FileAccess.open(RETOOLING_RULES_PATH, FileAccess.READ)
	if file == null:
		push_warning("Failed to load retooling_similarity.json")
		return
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		retooling_rules = parsed
	else:
		push_warning("Invalid retooling_similarity.json")


func get_category_similarity(old_category: String, new_category: String) -> float:
	if retooling_rules.is_empty():
		return 0.20

	var sim_table: Dictionary = retooling_rules.get("similarity", {})
	if sim_table.has(old_category):
		var row: Variant = sim_table[old_category]
		if typeof(row) == TYPE_DICTIONARY and (row as Dictionary).has(new_category):
			return float((row as Dictionary)[new_category])
	return float(retooling_rules.get("default_floor", 0.20))


func get_retooling_params(
	old_category: String,
	new_category: String,
	tech_modifier: float = 1.0,
	focus_modifier: float = 1.0,
) -> Dictionary:
	var similarity := get_category_similarity(old_category, new_category)

	var base_retool := float(retooling_rules.get("base_retool_days", 90.0))
	var base_recovery := float(retooling_rules.get("recovery_days", 45.0))
	var floor_efficiency := float(retooling_rules.get("default_floor", 0.20))
	var retained_rules: Dictionary = retooling_rules.get("retained_efficiency", {})
	var retained_base := float(retained_rules.get("base", 0.15))
	var retained_scale := float(retained_rules.get("similarity_scale", 0.80))

	var retained := maxf(floor_efficiency, retained_base + similarity * retained_scale)
	retained *= tech_modifier * focus_modifier
	retained = clampf(retained, floor_efficiency, 0.95)

	var tech_div := maxf(tech_modifier, 0.1)
	var focus_div := maxf(focus_modifier, 0.1)
	var retool_days := base_retool * (1.0 - similarity * 0.65) / tech_div
	retool_days = maxf(25.0, retool_days)

	var recovery_days := base_recovery * (1.0 - similarity * 0.4) / focus_div
	recovery_days = maxf(10.0, recovery_days)

	return {
		"similarity": similarity,
		"retained_efficiency": retained,
		"retool_days": retool_days,
		"recovery_days": recovery_days,
	}


func _retool_group_for_design(design_id: String, category_override: String = "") -> String:
	if not category_override.is_empty():
		return RetoolingSimilarityTable.map_production_category_to_group(category_override)
	return RetoolingSimilarityTable.category_group_for_design(design_id)


func create_line(line_id: String) -> ProductionLine:
	if line_id.is_empty():
		push_warning("ProductionManager.create_line requires a non-empty line_id")
		return null
	if _lines.has(line_id):
		push_warning("Production line already exists: " + line_id)
		return _lines[line_id] as ProductionLine

	var line := ProductionLine.new(GameData.design_data, line_id)
	line.set_modifier_resolver(_resolve_modifiers_for_line)
	line.unit_completed.connect(_on_line_unit_completed.bind(line_id))
	_lines[line_id] = line
	line_registered.emit(line_id)
	return line


func remove_line(line_id: String) -> bool:
	if not _lines.has(line_id):
		return false
	_lines.erase(line_id)
	line_removed.emit(line_id)
	return true


func get_line(line_id: String) -> ProductionLine:
	return _lines.get(line_id)


func get_line_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _lines:
		ids.append(str(key))
	return ids


func has_line(line_id: String) -> bool:
	return _lines.has(line_id)


func set_line_template(line_id: String, template_id: String) -> Dictionary:
	var line := get_line(line_id)
	if line == null:
		return {"success": false, "error": "unknown_line"}

	var owner_tag := ""
	var fac_for_gate: Factory = null
	if factory_manager != null and line.factory_id > 0:
		fac_for_gate = factory_manager.get_factory(line.factory_id)
		if fac_for_gate != null:
			owner_tag = fac_for_gate.owner_tag
	if typeof(TechnologyManager) != TYPE_NIL and not owner_tag.is_empty():
		# Map Build Eligibility gate (Phase 1 = tech unlock; later: province-specific via MapTechnologyContext)
		var gate := TechnologyManager.factory_can_build_design(owner_tag, fac_for_gate, template_id)
		if not bool(gate.get("allowed", true)):
			var detail: Dictionary = gate.get("detail", {}) as Dictionary
			return {
				"success": false,
				"error": str(gate.get("error", "tech_locked")),
				"lock_reason": str(detail.get("reason", "Technology required")),
				"tech_id": str(detail.get("tech_id", "")),
			}

	if not _naval_production_allowed(line, template_id):
		return {"success": false, "error": "naval_requires_shipyard_port"}

	_refresh_line_modifiers(line)
	var result := line.set_template(template_id)
	if not bool(result.get("success", false)):
		return result

	if typeof(DesignManager) != TYPE_NIL:
		DesignManager.mark_design_used(owner_tag, template_id)

	var retool_days := float(result.get("retooling_days", 0.0))
	if retool_days > 0.0:
		var previous_id := str(result.get("previous_template_id", ""))
		var family_discount := _same_family_retool_discount(previous_id, template_id)
		var mods := _resolve_modifiers_for_line(line)
		line.apply_retooling_adjustment(mods.retooling_days_multiplier, family_discount)
		result["retooling_days"] = line.get_retooling_days_remaining()
		result["family_retool_discount"] = family_discount

	return result


func advance_days(days: float) -> Dictionary:
	var report := {
		"days_advanced": days,
		"lines": {},
		"total_units_completed": 0,
	}

	for line_id in _lines:
		var line: ProductionLine = _lines[line_id]
		_refresh_line_modifiers(line)
		var line_report: Dictionary = line.advance_days(days)
		report["lines"][line_id] = line_report
		report["total_units_completed"] += int(line_report.get("units_completed", 0))

	# Optional: clear_all_production_caches()  # refresh daily output estimates every tick
	day_advanced.emit(report)
	return report


func register_modifier(modifier: ProductionModifier) -> void:
	if modifier == null or modifier.id.is_empty():
		push_warning("ProductionManager.register_modifier: invalid modifier")
		return
	_active_modifiers[modifier.id] = modifier
	modifier_registered.emit(modifier.id, modifier.source)


func unregister_modifier(modifier_id: String) -> void:
	if not _active_modifiers.has(modifier_id):
		return
	_active_modifiers.erase(modifier_id)
	modifier_removed.emit(modifier_id)


func clear_modifiers_by_source(source_prefix: String) -> void:
	var to_remove: Array[String] = []
	for modifier_id in _active_modifiers:
		var mod: ProductionModifier = _active_modifiers[modifier_id]
		if mod.source.begins_with(source_prefix):
			to_remove.append(modifier_id)
	for modifier_id in to_remove:
		unregister_modifier(modifier_id)


func set_production_stance(stance_id: String) -> bool:
	var preset: Dictionary = _stance_presets.get(stance_id, {})
	if preset.is_empty() and stance_id != "balanced":
		push_warning("Unknown production stance: " + stance_id)
		return false

	_clear_modifiers_with_tag(STANCE_TAG)
	production_stance = stance_id
	if not preset.is_empty():
		var mod := ProductionModifier.from_dict(preset)
		if STANCE_TAG not in mod.tags:
			mod.tags.append(STANCE_TAG)
		register_modifier(mod)
	stance_changed.emit(stance_id)
	return true


func apply_doctrine(doctrine_id: String) -> bool:
	var preset: Dictionary = _doctrine_presets.get(doctrine_id, {})
	if preset.is_empty():
		push_warning("Unknown doctrine modifier: " + doctrine_id)
		return false
	register_modifier(ProductionModifier.from_dict(preset))
	return true


func revoke_doctrine(doctrine_id: String) -> void:
	var preset: Dictionary = _doctrine_presets.get(doctrine_id, {})
	if preset.is_empty():
		return
	unregister_modifier(str(preset.get("id", "")))


func apply_focus(focus_id: String) -> bool:
	var preset: Dictionary = _focus_presets.get(focus_id, {})
	if preset.is_empty():
		push_warning("Unknown focus modifier: " + focus_id)
		return false
	register_modifier(ProductionModifier.from_dict(preset))
	return true


func revoke_focus(focus_id: String) -> void:
	var preset: Dictionary = _focus_presets.get(focus_id, {})
	if preset.is_empty():
		return
	unregister_modifier(str(preset.get("id", "")))


func get_family_units_produced(family_id: String) -> int:
	return int(_family_units_produced.get(family_id, 0))


func get_active_modifier_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _active_modifiers:
		ids.append(str(key))
	return ids


func set_stockpile(resources: Dictionary) -> void:
	national_stockpile = resources.duplicate(true)


func add_stockpile(resources: Dictionary) -> void:
	for resource in resources:
		national_stockpile[resource] = float(national_stockpile.get(resource, 0.0)) + float(resources[resource])


func can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		if float(national_stockpile.get(resource, 0.0)) < float(cost[resource]):
			return false
	return true


func pay_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for resource in cost:
		national_stockpile[resource] = float(national_stockpile.get(resource, 0.0)) - float(cost[resource])
	return true


# === National equipment stockpile ===


func add_to_national_stockpile(equipment_id: String, amount: int) -> void:
	if amount <= 0 or equipment_id.is_empty():
		return
	if not national_equipment_stockpile.has(equipment_id):
		national_equipment_stockpile[equipment_id] = 0
	national_equipment_stockpile[equipment_id] = int(national_equipment_stockpile[equipment_id]) + amount
	equipment_added_to_stockpile.emit(equipment_id, amount)


func take_from_national_stockpile(equipment_id: String, amount: int) -> int:
	if amount <= 0 or equipment_id.is_empty():
		return 0
	if not national_equipment_stockpile.has(equipment_id):
		return 0
	var available := int(national_equipment_stockpile[equipment_id])
	var taken := mini(amount, available)
	national_equipment_stockpile[equipment_id] = available - taken
	if int(national_equipment_stockpile[equipment_id]) <= 0:
		national_equipment_stockpile.erase(equipment_id)
	equipment_taken_from_stockpile.emit(equipment_id, taken)
	return taken


func get_national_stockpile_amount(equipment_id: String) -> int:
	return int(national_equipment_stockpile.get(equipment_id, 0))


func set_national_equipment_stockpile(stock: Dictionary) -> void:
	national_equipment_stockpile.clear()
	for equipment_id in stock:
		var amount := int(stock[equipment_id])
		if amount > 0:
			national_equipment_stockpile[str(equipment_id)] = amount


func get_national_equipment_stockpile() -> Dictionary:
	return national_equipment_stockpile.duplicate(true)

# === Per-country equipment stockpiles (for scenario-driven starting OOBs, equipment, factories output per nation) ===
func set_country_equipment_stockpile(country_tag: String, stock: Dictionary) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if stock.is_empty():
		country_equipment_stockpiles.erase(tag)
		return
	country_equipment_stockpiles[tag] = stock.duplicate(true)

func add_to_country_equipment_stockpile(country_tag: String, equipment_id: String, amount: int) -> void:
	if amount <= 0 or equipment_id.is_empty() or country_tag.is_empty():
		return
	var tag := country_tag.strip_edges().to_upper()
	if not country_equipment_stockpiles.has(tag):
		country_equipment_stockpiles[tag] = {}
	var s: Dictionary = country_equipment_stockpiles[tag]
	if not s.has(equipment_id):
		s[equipment_id] = 0
	s[equipment_id] = int(s[equipment_id]) + amount
	equipment_added_to_stockpile.emit(equipment_id, amount)

func take_from_country_equipment_stockpile(country_tag: String, equipment_id: String, amount: int) -> int:
	if amount <= 0 or equipment_id.is_empty() or country_tag.is_empty():
		return 0
	var tag := country_tag.strip_edges().to_upper()
	if not country_equipment_stockpiles.has(tag):
		return 0
	var s: Dictionary = country_equipment_stockpiles[tag]
	if not s.has(equipment_id):
		return 0
	var available := int(s[equipment_id])
	var taken: int = min(available, amount)
	s[equipment_id] = available - taken
	if int(s[equipment_id]) <= 0:
		s.erase(equipment_id)
	equipment_taken_from_stockpile.emit(equipment_id, taken)
	return taken

# Civilian goods (roadmap): separate from mil equipment. Produced by setting line design to "civilian_consumer_goods".
# On complete, effects happiness (via GameData) + national stock for potential UI/wiring to supply.
func add_civilian_goods(country_tag: String, amount: int) -> void:
	if amount <= 0 or country_tag.is_empty():
		return
	var tag := country_tag.strip_edges().to_upper()
	if not country_civilian_goods.has(tag):
		country_civilian_goods[tag] = 0
	country_civilian_goods[tag] = int(country_civilian_goods[tag]) + amount
	print("Production: added %d civilian_goods to %s (total %d). Happiness effects applied via GameData." % [amount, tag, country_civilian_goods[tag]])

func get_civilian_goods(country_tag: String) -> int:
	var tag := country_tag.strip_edges().to_upper()
	return int(country_civilian_goods.get(tag, 0))

func get_country_equipment_stockpile(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	if not country_equipment_stockpiles.has(tag):
		return {}
	return country_equipment_stockpiles[tag].duplicate(true)

func get_or_create_country_equipment_stockpile(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	if not country_equipment_stockpiles.has(tag):
		country_equipment_stockpiles[tag] = {}
	return country_equipment_stockpiles[tag]

func _on_production_completed(_line_id: String, design_id: String, count: int) -> void:
	var line := get_line(_line_id)
	var owner_tag := ""
	if line != null and line.factory_id > 0 and typeof(FactoryManager) != TYPE_NIL:
		var fac: Variant = FactoryManager.get_factory(line.factory_id)
		if fac != null and "owner_tag" in fac:
			owner_tag = str(fac.owner_tag).strip_edges().to_upper()
	if owner_tag != "":
		if design_id.begins_with("civilian_"):
			add_civilian_goods(owner_tag, count)
			# Also feed GameData for pop happiness/mandate effects (civilian output -> pop)
			if typeof(GameData) != TYPE_NIL and GameData.has_method("produce_civilian_goods"):
				GameData.produce_civilian_goods(owner_tag, count)
			print("Civilian production complete: %s × %d goods for %s (happiness/cohesion/mandate + local supply wiring hook)." % [design_id, count, owner_tag])
		else:
			add_to_country_equipment_stockpile(owner_tag, design_id, count)
			print("Production complete: %s × %d added to %s stockpile" % [design_id, count, owner_tag])
		# Wiring prod output -> prov supply (factories in controlled prov boost local depot for supply/combat/recovery)
		if line != null and line.factory_id > 0 and typeof(FactoryManager) != TYPE_NIL:
			var facv: Variant = FactoryManager.get_factory(line.factory_id)
			if facv != null and "province_id" in facv:
				var pid := int(facv.province_id)
				if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("boost_depot_from_production"):
					var boost_amt := count * (2 if design_id.begins_with("civilian_") else 1)
					SupplyManager.call("boost_depot_from_production", pid, owner_tag, boost_amt)
	else:
		add_to_national_stockpile(design_id, count)
		print("Production complete: %s × %d added to national stockpile" % [design_id, count])


# === Equipment shortages (formation readiness / organization) ===


func set_unit_equipment_stock(unit_id: String, stock: Dictionary) -> void:
	_unit_equipment_stock[unit_id] = {}
	for equipment in stock:
		_unit_equipment_stock[unit_id][str(equipment)] = int(stock[equipment])


func get_unit_equipment_stock(unit_id: String) -> Dictionary:
	var raw: Variant = _unit_equipment_stock.get(unit_id, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return (raw as Dictionary).duplicate(true)


func clear_unit_equipment_stock(unit_id: String) -> void:
	_unit_equipment_stock.erase(unit_id)


func get_division_required_equipment(division_template_id: String) -> Dictionary:
	var supply := get_node_or_null("/root/SupplyManager")
	if supply == null:
		return {}
	var loader: DivisionTemplateLoader = supply.division_templates
	var div: DivisionTemplate = loader.get_division(division_template_id) if loader != null else null
	if div == null:
		return {}
	return div.get_required_equipment(GameData.design_data)


func get_unit_shortages(unit_id: String, required_equipment: Dictionary) -> Dictionary:
	var current_stock := get_unit_equipment_stock(unit_id)
	var shortages: Dictionary = {}

	for equipment_id in required_equipment:
		var needed := int(required_equipment[equipment_id])
		var have_in_unit := int(current_stock.get(equipment_id, 0))
		var have_in_national := get_national_stockpile_amount(str(equipment_id))
		var total_available := have_in_unit + have_in_national
		if total_available < needed:
			shortages[str(equipment_id)] = needed - total_available

	return shortages


func get_unit_shortage_report_with_national(unit_id: String, required_equipment: Dictionary) -> Dictionary:
	var report := get_shortage_report(unit_id, required_equipment)
	report["national_stockpile_available"] = {}
	for eq in required_equipment:
		report["national_stockpile_available"][str(eq)] = get_national_stockpile_amount(str(eq))
	return report


func get_unit_readiness_penalty(unit_id: String, required_equipment: Dictionary) -> float:
	var shortages := get_unit_shortages(unit_id, required_equipment)
	return _equipment_shortage_tracker.get_readiness_from_shortages(shortages, required_equipment)


func get_shortage_report(unit_id: String, required_equipment: Dictionary) -> Dictionary:
	var shortages := get_unit_shortages(unit_id, required_equipment)
	var categorized := _categorize_equipment_shortages(shortages, required_equipment)
	return {
		"unit_id": unit_id,
		"missing_equipment": shortages,
		"missing_infantry_equipment": categorized.get("infantry", {}),
		"missing_sustainment_equipment": categorized.get("sustainment", {}),
		"missing_other_equipment": categorized.get("other", {}),
		"readiness_multiplier": get_unit_readiness_penalty(unit_id, required_equipment),
	}


func _categorize_equipment_shortages(
	shortages: Dictionary,
	_required_equipment: Dictionary,
) -> Dictionary:
	var infantry: Dictionary = {}
	var sustainment: Dictionary = {}
	var other: Dictionary = {}
	for equipment_id in shortages:
		var key := str(equipment_id)
		var amount := int(shortages[equipment_id])
		if _is_sustainment_equipment_id(key):
			sustainment[key] = amount
		elif _is_infantry_equipment_id(key):
			infantry[key] = amount
		else:
			other[key] = amount
	return {"infantry": infantry, "sustainment": sustainment, "other": other}


func _is_sustainment_equipment_id(equipment_id: String) -> bool:
	if equipment_id.contains("sustainment"):
		return true
	if GameData.design_data != null:
		return not GameData.design_data.get_sustainment_equipment(equipment_id).is_empty()
	return false


func _is_infantry_equipment_id(equipment_id: String) -> bool:
	if GameData.design_data == null:
		return equipment_id.begins_with("infantry_")
	var template: UnitTemplate = GameData.design_data.get_infantry_equipment(equipment_id)
	return template != null


## Combat / evaluation hook: scale base readiness by equipment fill level.
func apply_equipment_shortage_modifiers(
	unit_id: String,
	base_readiness: float,
	required_equipment: Dictionary,
	division_template_id: String = "",
) -> float:
	var penalty := get_unit_readiness_penalty(unit_id, required_equipment)
	var infantry_mult := get_division_infantry_combat_multiplier(division_template_id)
	var sustainment_mult := get_division_sustainment_readiness_multiplier(division_template_id)
	return base_readiness * penalty * infantry_mult * sustainment_mult


func get_division_sustainment_readiness_multiplier(division_template_id: String) -> float:
	if division_template_id.is_empty() or GameData.design_data == null:
		return 1.0
	var supply := get_node_or_null("/root/SupplyManager")
	if supply == null:
		return 1.0
	var div: DivisionTemplate = supply.division_templates.get_division(division_template_id)
	if div == null:
		return 1.0
	return 1.0 + div.get_sustainment_readiness_bonus(GameData.design_data)


func get_division_infantry_stats(division_template_id: String) -> Dictionary:
	if division_template_id.is_empty() or GameData.design_data == null:
		return {}
	var supply := get_node_or_null("/root/SupplyManager")
	if supply == null:
		return {}
	var template: DivisionTemplate = supply.division_templates.get_division(division_template_id)
	if template == null:
		return {}
	return template.get_aggregated_infantry_stats(GameData.design_data)


func get_division_infantry_combat_multiplier(division_template_id: String) -> float:
	var stats := get_division_infantry_stats(division_template_id)
	if stats.is_empty():
		return 1.0
	var soft := float(stats.get("soft_attack", 0.9))
	return clampf(soft / 0.9, 0.75, 1.75)


func get_division_combat_modifiers(division_template_id: String) -> Dictionary:
	if division_template_id.is_empty() or GameData.design_data == null:
		return {}
	var supply := get_node_or_null("/root/SupplyManager")
	if supply == null:
		return {}
	var template: DivisionTemplate = supply.division_templates.get_division(division_template_id)
	if template == null:
		return {}
	return template.get_combined_combat_modifiers(GameData.design_data)


func get_division_final_combat_stats(division_template_id: String, unit_id: String = "") -> Dictionary:
	if division_template_id.is_empty() or GameData.design_data == null:
		return {}
	var supply := get_node_or_null("/root/SupplyManager")
	if supply == null:
		return {}
	var template: DivisionTemplate = supply.division_templates.get_division(division_template_id)
	if template == null:
		return {}

	var shortages: Dictionary = {}
	if not unit_id.is_empty():
		var required := template.get_required_equipment(GameData.design_data)
		shortages = get_unit_shortages(unit_id, required)

	var stats := template.get_final_combat_stats(shortages, GameData.design_data)
	if typeof(LeaderManager) != TYPE_NIL and not unit_id.is_empty():
		stats = LeaderManager.apply_training_path_supply_to_stats(stats, unit_id)
	return stats


func request_equipment_for_unit(unit_id: String, equipment_id: String, amount: int) -> int:
	var country := ""
	if typeof(LeaderManager) != TYPE_NIL:
		var f: Formation = LeaderManager.get_formation(unit_id)
		if f != null and f.country_tag != "":
			country = f.country_tag
	if country != "":
		var taken := take_from_country_equipment_stockpile(country, equipment_id, amount)
		if taken > 0:
			var current := get_unit_equipment_stock(unit_id)
			current[equipment_id] = int(current.get(equipment_id, 0)) + taken
			set_unit_equipment_stock(unit_id, current)
		return taken
	else:
		var taken := take_from_national_stockpile(equipment_id, amount)
		if taken > 0:
			var current := get_unit_equipment_stock(unit_id)
			current[equipment_id] = int(current.get(equipment_id, 0)) + taken
			set_unit_equipment_stock(unit_id, current)
		return taken


func set_unit_priority_reinforcement(unit_id: String, enabled: bool) -> void:
	if unit_id.is_empty():
		return
	if enabled:
		priority_reinforcement_units[unit_id] = true
	else:
		priority_reinforcement_units.erase(unit_id)


func is_unit_priority_reinforced(unit_id: String) -> bool:
	return bool(priority_reinforcement_units.get(unit_id, false))


func auto_reinforce_unit_from_stockpile(unit_id: String, required_equipment: Dictionary) -> Dictionary:
	var current_stock := get_unit_equipment_stock(unit_id)
	var fulfilled: Dictionary = {}

	var leader_id := ""
	if typeof(LeaderManager) != TYPE_NIL:
		leader_id = LeaderManager.resolve_leader_id_for_formation(unit_id)

	var reinforcement_mult := 1.0
	if not leader_id.is_empty() and typeof(LeaderManager) != TYPE_NIL:
		reinforcement_mult = LeaderManager.get_training_path_reinforcement_multiplier(leader_id)

	for equipment_id in required_equipment:
		var needed := int(required_equipment[equipment_id])
		var have_in_unit := int(current_stock.get(equipment_id, 0))
		var gap := needed - have_in_unit
		if gap <= 0:
			continue
		var got := request_equipment_for_unit(unit_id, str(equipment_id), gap)
		if got < gap and reinforcement_mult > 1.0:
			var bonus := int(ceil(float(gap - got) * (reinforcement_mult - 1.0)))
			if bonus > 0:
				got += request_equipment_for_unit(unit_id, str(equipment_id), bonus)
		if got > 0:
			fulfilled[equipment_id] = int(get_unit_equipment_stock(unit_id).get(equipment_id, 0))

	if not fulfilled.is_empty():
		unit_reinforced.emit(unit_id, fulfilled.duplicate(true))

	return fulfilled


func reinforce_all_units(required_map: Dictionary) -> Dictionary:
	var report := {"units": {}}

	for unit_id in priority_reinforcement_units:
		if not is_unit_priority_reinforced(str(unit_id)):
			continue
		if not required_map.has(unit_id):
			continue
		var required: Variant = required_map[unit_id]
		if typeof(required) != TYPE_DICTIONARY:
			continue
		report["units"][unit_id] = auto_reinforce_unit_from_stockpile(
			str(unit_id), required as Dictionary
		)

	for unit_id in required_map:
		if is_unit_priority_reinforced(str(unit_id)):
			continue
		var required: Variant = required_map[unit_id]
		if typeof(required) != TYPE_DICTIONARY:
			continue
		report["units"][unit_id] = auto_reinforce_unit_from_stockpile(
			str(unit_id), required as Dictionary
		)

	return report


func daily_reinforcement_tick(required_map: Dictionary) -> Dictionary:
	return reinforce_all_units(required_map)


func get_line_resource_cost_for_days(line_id: String, days: float) -> Dictionary:
	var line := get_line(line_id)
	if line == null or line.daily_resource_cost.is_empty():
		return {}
	var scaled: Dictionary = {}
	for resource in line.daily_resource_cost:
		scaled[resource] = float(line.daily_resource_cost[resource]) * days
	return scaled


func get_design_resource_preview(design_id: String) -> Dictionary:
	var daily_cost: Dictionary = {}
	if GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(design_id)
		if template != null:
			daily_cost = ProductionCostCalculator.resolve_daily_resource_cost(template)
	return {
		"design_id": design_id,
		"daily_cost": daily_cost,
	}


func has_enough_resources_for_line(line_id: String, days: float) -> bool:
	return preview_resource_fill_ratio(line_id, days) >= 1.0


func apply_resource_shortage(line_id: String, shortage_level: float, reliability_level: float = -1.0) -> void:
	var line := get_line(line_id)
	if line == null:
		return
	line.resource_shortage_penalty = clampf(shortage_level, 0.4, 1.0)
	if reliability_level >= 0.0:
		line.shortage_reliability_multiplier = clampf(reliability_level, 0.5, 1.0)


func _shortage_rules() -> Dictionary:
	var rules: Variant = ProductionCostCalculator.get_rules().get("resource_shortage", {})
	return rules if typeof(rules) == TYPE_DICTIONARY else {}


func _critical_resource_set() -> Dictionary:
	var raw: Variant = _shortage_rules().get("critical_resources", [])
	var critical_set: Dictionary = {}
	if typeof(raw) == TYPE_ARRAY:
		for item in raw:
			critical_set[str(item).to_lower()] = true
	return critical_set


func _weighted_fill_ratio(needed: Dictionary) -> float:
	if needed.is_empty():
		return 1.0

	var critical := _critical_resource_set()
	var speed_weight := float(_shortage_rules().get("critical_speed_weight", 1.45))
	var effective := 1.0

	for resource in needed:
		var required := float(needed[resource])
		if required <= 0.0:
			continue
		var have := float(national_stockpile.get(resource, 0.0))
		var ratio := clampf(have / required, 0.0, 1.0)
		if critical.has(str(resource).to_lower()):
			ratio = pow(ratio, 1.0 / maxf(speed_weight, 1.0))
		effective = minf(effective, ratio)

	return effective


func _shortage_multipliers(fill_ratio: float) -> Dictionary:
	var rules := _shortage_rules()
	var min_output := float(rules.get("min_output_multiplier", 0.55))
	var min_reliability := float(rules.get("min_reliability_multiplier", 0.72))
	var ratio := clampf(fill_ratio, 0.0, 1.0)
	var speed := lerpf(min_output, 1.0, ratio)
	var reliability := lerpf(min_reliability, 1.0, ratio)

	var critical := _critical_resource_set()
	if not critical.is_empty():
		var crit_weight := float(rules.get("critical_reliability_weight", 1.25))
		var crit_floor := lerpf(min_reliability, min_reliability * 0.9, 1.0 - ratio)
		if ratio < 1.0:
			reliability = minf(reliability, lerpf(crit_floor, 1.0, pow(ratio, 1.0 / maxf(crit_weight, 1.0))))

	return {
		"speed": clampf(speed, min_output, 1.0),
		"reliability": clampf(reliability, min_reliability, 1.0),
	}


func _missing_resources(needed: Dictionary, fill_ratio: float) -> Dictionary:
	var missing: Dictionary = {}
	for resource in needed:
		var required := float(needed[resource])
		var have := float(national_stockpile.get(resource, 0.0))
		var shortfall := required * (1.0 - fill_ratio) - maxf(0.0, have - required * fill_ratio)
		if shortfall > 0.001:
			missing[resource] = shortfall
	return missing


func evaluate_line_resources(line_id: String, days: float) -> Dictionary:
	var line := get_line(line_id)
	if line == null:
		return {"output_multiplier": 1.0, "afforded": true, "fill_ratio": 1.0, "cost_paid": {}}
	if line.daily_resource_cost.is_empty():
		apply_resource_shortage(line_id, 1.0, 1.0)
		return {"output_multiplier": 1.0, "afforded": true, "fill_ratio": 1.0, "cost_paid": {}}

	var needed := get_line_resource_cost_for_days(line_id, days)
	# Apply agent resource discovery / output multiplier to reduce effective resource consumption (more efficient extraction/gathering)
	var line_owner := ""
	var l := get_line(line_id)
	if l:
		line_owner = l.owner_tag
	var national_mods := _get_national_production_modifiers(line_owner) if line_owner else {"resource_output_multiplier": 1.0}
	var res_eff := float(national_mods.get("resource_output_multiplier", 1.0))
	if res_eff > 1.0:
		for r in needed:
			needed[r] = float(needed[r]) / res_eff  # lower consumption
	if needed.is_empty():
		apply_resource_shortage(line_id, 1.0, 1.0)
		return {"output_multiplier": 1.0, "afforded": true, "fill_ratio": 1.0, "cost_paid": {}}

	var fill_ratio := _weighted_fill_ratio(needed)
	var mults := _shortage_multipliers(fill_ratio)

	if fill_ratio >= 1.0:
		pay_cost(needed)
		apply_resource_shortage(line_id, 1.0, 1.0)
		return {
			"output_multiplier": 1.0,
			"afforded": true,
			"fill_ratio": 1.0,
			"cost_paid": needed.duplicate(true),
			"shortage_penalty": 1.0,
			"reliability_multiplier": 1.0,
		}

	var paid: Dictionary = {}
	for resource in needed:
		var amount := float(needed[resource]) * fill_ratio
		if amount > 0.0:
			paid[resource] = amount
			national_stockpile[resource] = float(national_stockpile.get(resource, 0.0)) - amount

	apply_resource_shortage(line_id, float(mults["speed"]), float(mults["reliability"]))
	production_resource_shortage.emit(line_id, _missing_resources(needed, fill_ratio))

	return {
		"output_multiplier": float(mults["speed"]),
		"afforded": fill_ratio > 0.0,
		"fill_ratio": fill_ratio,
		"cost_paid": paid,
		"shortage_penalty": line.resource_shortage_penalty,
		"reliability_multiplier": line.shortage_reliability_multiplier,
	}


func try_consume_resources_for_line(line_id: String, days: float) -> bool:
	return float(evaluate_line_resources(line_id, days).get("fill_ratio", 0.0)) > 0.0


func consume_resources_for_line(line_id: String, days: float) -> float:
	return float(evaluate_line_resources(line_id, days).get("output_multiplier", 1.0))


func preview_resource_fill_ratio(line_id: String, days: float) -> float:
	var line := get_line(line_id)
	if line == null or line.daily_resource_cost.is_empty():
		return 1.0
	var needed := get_line_resource_cost_for_days(line_id, days)
	if needed.is_empty():
		return 1.0
	return clampf(_weighted_fill_ratio(needed), 0.0, 1.0)


func get_line_reliability_profile(line_id: String) -> ReliabilityProfile:
	var line := get_line(line_id)
	if line == null:
		return ReliabilityProfile.new()
	return line.get_reliability_profile()


func list_line_refinement_options(line_id: String) -> Array[Dictionary]:
	var line := get_line(line_id)
	if line == null:
		return []
	return line.list_refinement_options()


func start_line_refinement(line_id: String, project_id: String, pay_upfront: bool = true) -> Dictionary:
	var line := get_line(line_id)
	if line == null:
		return {"success": false, "reason": "unknown_line"}

	var eligibility := line.can_start_refinement(project_id)
	if not bool(eligibility.get("can_start", false)):
		return {"success": false, "reason": str(eligibility.get("reason", "blocked"))}

	var def: Dictionary = GameData.design_data.get_refinement_def(project_id)
	var cost: Dictionary = def.get("cost", {}) if typeof(def.get("cost", {})) == TYPE_DICTIONARY else {}
	if pay_upfront and not cost.is_empty() and not pay_cost(cost):
		return {"success": false, "reason": "cannot_afford", "cost": cost}

	if not line.start_refinement(project_id):
		return {"success": false, "reason": "start_failed"}

	return {
		"success": true,
		"project_id": project_id,
		"line_id": line_id,
		"cost_paid": cost,
		"tradeoff_summary": str(def.get("tradeoff_summary", "")),
	}


func _refresh_line_modifiers(line: ProductionLine) -> void:
	line.set_runtime_modifiers(_resolve_modifiers_for_line(line))


func _resolve_modifiers_for_line(line: ProductionLine) -> ProductionModifiers:
	var mods := ProductionModifiers.new()

	for modifier_id in _active_modifiers:
		mods.absorb(_active_modifiers[modifier_id])

	# === National Spirit + Temporary Modifier Integration (Option B) ===
	var owner_tag := _get_line_owner_tag(line)
	if not owner_tag.is_empty():
		var national_mods := _get_national_production_modifiers(owner_tag)
		if national_mods.get("output_multiplier", 1.0) != 1.0:
			mods.output_multiplier *= float(national_mods["output_multiplier"])
		if national_mods.get("reliability_multiplier", 1.0) != 1.0:
			mods.reliability_multiplier *= float(national_mods["reliability_multiplier"])
		if national_mods.get("retooling_days_multiplier", 1.0) != 1.0:
			mods.retooling_days_multiplier *= float(national_mods["retooling_days_multiplier"])
		if national_mods.get("cost_multiplier", 1.0) != 1.0:
			mods.cost_multiplier *= float(national_mods["cost_multiplier"])
		if national_mods.get("resource_output_multiplier", 1.0) != 1.0:
			# Resource boost from agents can mitigate shortages or boost effective output
			mods.output_multiplier *= float(national_mods["resource_output_multiplier"])
			mods.resource_shortage_penalty = min(1.0, mods.resource_shortage_penalty * float(national_mods["resource_output_multiplier"])) if mods.has("resource_shortage_penalty") else 1.0

	var template: UnitTemplate = line.get_current_template()
	if template != null and not template.design_family.is_empty():
		mods.design_family_output_bonus = _compute_family_output_bonus(template.design_family)
		mods.design_family_output_bonus += _compute_cross_line_synergy(template.design_family)

	var state := line.get_current_state()
	if state != null:
		mods.time_on_design_output_bonus = _compute_time_on_design_bonus(state.days_on_design)

	return mods


func _compute_family_output_bonus(family_id: String) -> float:
	var family_rules: Dictionary = _rules.get("design_families", {})
	var per_10 := float(family_rules.get("output_bonus_per_10_national_units", 0.02))
	var max_bonus := float(family_rules.get("max_family_output_bonus", 0.18))
	var units := float(get_family_units_produced(family_id))
	return minf(floor(units / 10.0) * per_10, max_bonus)


func _compute_cross_line_synergy(family_id: String) -> float:
	var family_rules: Dictionary = _rules.get("design_families", {})
	var per_line := float(family_rules.get("cross_line_synergy_per_active_line", 0.01))
	var max_synergy := float(family_rules.get("max_cross_line_synergy", 0.06))
	var active_lines := maxi(_count_active_lines_for_family(family_id) - 1, 0)
	return minf(float(active_lines) * per_line, max_synergy)


func _compute_time_on_design_bonus(days_on_design: float) -> float:
	var ramp_rules: Dictionary = _rules.get("efficiency_ramp", {})
	var days_to_max := float(ramp_rules.get("days_to_max_time_bonus", 120))
	var max_bonus := float(ramp_rules.get("max_time_on_design_output_bonus", 0.12))
	var ratio := clampf(days_on_design / maxf(days_to_max, 1.0), 0.0, 1.0)
	return max_bonus * ratio


func _count_active_lines_for_family(family_id: String) -> int:
	var count := 0
	for line_id in _lines:
		var line: ProductionLine = _lines[line_id]
		var template: UnitTemplate = line.get_current_template()
		if template != null and template.design_family == family_id:
			count += 1
	return count


func _same_family_retool_discount(previous_template_id: String, new_template_id: String) -> float:
	if previous_template_id.is_empty() or previous_template_id == new_template_id:
		return 0.0
	var previous_family := _template_design_family(previous_template_id)
	var new_family := _template_design_family(new_template_id)
	if previous_family.is_empty() or previous_family != new_family:
		return 0.0
	return float(_rules.get("design_families", {}).get("same_family_retool_discount", 0.30))


func _template_design_family(template_id: String) -> String:
	var template: UnitTemplate = GameData.design_data.get_template(template_id)
	return template.design_family if template != null else ""


func _get_line_owner_tag(line: ProductionLine) -> String:
	if line == null or line.factory_id == 0 or typeof(FactoryManager) == TYPE_NIL:
		return ""
	var factory := FactoryManager.get_factory(line.factory_id)
	if factory == null:
		return ""
	return factory.owner_tag


func _get_national_production_modifiers(country_tag: String) -> Dictionary:
	var result := {
		"output_multiplier": 1.0,
		"reliability_multiplier": 1.0,
		"retooling_days_multiplier": 1.0,
		"cost_multiplier": 1.0,
		"resource_output_multiplier": 1.0,  # From agent exploration/discovery
	}

	if country_tag.is_empty():
		return result

	# Permanent spirits
	if typeof(NationalSpiritManager) != TYPE_NIL:
		var spirit_mods := NationalSpiritManager.get_spirit_production_modifiers(country_tag)
		result["output_multiplier"] *= float(spirit_mods.get("output_multiplier", 1.0))
		result["reliability_multiplier"] *= float(spirit_mods.get("reliability_multiplier", 1.0))
		result["retooling_days_multiplier"] *= float(spirit_mods.get("retooling_days_multiplier", 1.0))
		result["cost_multiplier"] *= float(spirit_mods.get("cost_multiplier", 1.0))

	# Temporary modifiers (including stability effects)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp_mods: Dictionary = NationalModifierManager.get_production_modifiers(country_tag)
		result["output_multiplier"] *= float(temp_mods.get("output_multiplier", 1.0))
		result["reliability_multiplier"] *= float(temp_mods.get("reliability_multiplier", 1.0))
		result["retooling_days_multiplier"] *= float(temp_mods.get("retooling_days_multiplier", 1.0))
		result["cost_multiplier"] *= float(temp_mods.get("cost_multiplier", 1.0))
		result["resource_output_multiplier"] *= float(temp_mods.get("resource_output_multiplier", 1.0))

	# Regional control bonuses (full control of industrial heartlands like Western Germany / Low Countries gives factory_output %)
	# Wired as part of scenario connections + map integration (high value: makes securing key regions affect national production)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
		var regional := MapManager.get_active_regional_control_bonuses(country_tag)
		var f_out := float(regional.get("factory_output", 0.0))
		if f_out > 0.0:
			result["output_multiplier"] *= (1.0 + f_out)
		# infrastructure_build_speed could wire to construction projects later

	# Agent production boost from specialists assigned (e.g. industrial trait agents provide ongoing if "supporting" industry, via assignment or recent mission)
	# This allows agents to boost production based on type (trait) without full mission duration.
	if typeof(AgentManager) != TYPE_NIL:
		for ag: Agent in AgentManager.get_agents_for_country(country_tag):
			if ag.traits.has("industrial_specialist") or ag.traits.has("production_expert"):
				result["output_multiplier"] *= 1.05  # small persistent from specialist agents
				break
			if ag.traits.has("resource_explorer") or ag.traits.has("prospector"):
				result["resource_output_multiplier"] *= 1.05
				break

	return result


func _on_line_unit_completed(
	template_id: String,
	_reliability: float,
	_profile: ReliabilityProfile,
	_line_id: String,
) -> void:
	var template: UnitTemplate = GameData.design_data.get_template(template_id)
	if template == null or template.design_family.is_empty():
		return
	var family_id: String = template.design_family
	var total := int(_family_units_produced.get(family_id, 0)) + 1
	_family_units_produced[family_id] = total
	family_experience_changed.emit(family_id, total)


func _load_modifier_presets() -> void:
	var data := _load_json_dict(GLOBAL_MODIFIERS_PATH)
	_stance_presets = _preset_block(data, "production_stances")
	_doctrine_presets = _preset_block(data, "doctrines")
	_focus_presets = _preset_block(data, "focuses")
	set_production_stance("balanced")


func _preset_block(data: Dictionary, key: String) -> Dictionary:
	var raw = data.get(key, {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Missing JSON: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


func _naval_production_allowed(line: ProductionLine, design_id: String) -> bool:
	if line == null or design_id.is_empty():
		return true
	if not ProductionNavalRules.is_naval_design(design_id):
		return true
	if line.factory_id == 0:
		return true
	if factory_manager == null:
		return false
	var factory: Factory = factory_manager.get_factory(line.factory_id)
	if factory == null:
		return false
	if not ProductionNavalRules.factory_can_build_naval(factory):
		return false
	return factory_manager.province_has_port(factory.province_id)


func _clear_modifiers_with_tag(tag: String) -> void:
	var to_remove: Array[String] = []
	for modifier_id in _active_modifiers:
		var mod: ProductionModifier = _active_modifiers[modifier_id]
		if tag in mod.tags:
			to_remove.append(modifier_id)
	for modifier_id in to_remove:
		unregister_modifier(modifier_id)


func get_line_efficiency(line_id: String) -> float:
	var line := get_line(line_id)
	if line == null:
		return 1.0
	return line.get_factory_efficiency()


func get_lines_on_design_in_factory(factory_id: int, design_id: String) -> int:
	if factory_manager == null or design_id.is_empty():
		return 0
	var factory: Factory = factory_manager.get_factory(factory_id)
	if factory == null:
		return 0

	var count := 0
	for assigned_id in factory.assigned_lines:
		var line := get_line(assigned_id)
		if line != null and line.design_id == design_id:
			count += 1
	return count


func get_concentrated_production_multiplier(factory_id: int, design_id: String) -> float:
	var lines_on_design := get_lines_on_design_in_factory(factory_id, design_id)
	if lines_on_design <= 1:
		return 1.0

	var slot_rules: Dictionary = {}
	if factory_manager != null:
		slot_rules = factory_manager.rules.get("slot_concentration", {})
	var per_line := float(slot_rules.get("bonus_per_extra_line", 0.12))
	var cap := float(slot_rules.get("max_multiplier", 1.6))
	var bonus := 1.0 + float(lines_on_design - 1) * per_line
	return minf(bonus, cap)


func assign_line_to_factory(line_id: String, factory_id: int) -> bool:
	if factory_manager == null:
		return false

	var factory: Factory = factory_manager.get_factory(factory_id)
	if factory == null:
		push_warning("FactoryManager: Factory %d not found" % factory_id)
		return false

	var line := get_line(line_id)
	if line == null:
		push_warning("ProductionManager: line '%s' not found" % line_id)
		return false

	if factory.has_assigned_line(line_id):
		line.factory_id = factory_id
		return true

	if not factory.can_add_more_lines():
		push_warning(
			"Factory %d is at maximum production lines (%d)"
			% [factory_id, factory.max_production_lines],
		)
		return false

	line.factory_id = factory_id
	if not line.design_id.is_empty():
		factory.sync_production_design(line.design_id)
	elif not line.current_template_id.is_empty():
		factory.sync_production_design(line.current_template_id)

	if not factory_manager.assign_production_line_to_factory(factory_id, line_id):
		return false

	if not line.design_id.is_empty() and not _naval_production_allowed(line, line.design_id):
		line.factory_id = 0
		factory.assigned_lines.erase(line_id)
		push_warning("ProductionManager: naval design '%s' requires a port shipyard" % line.design_id)
		return false

	line.refresh_required_progress()

	print(
		"Assigned line '%s' to factory %d (Province %d, Slot %d)"
		% [line_id, factory_id, Factory.province_from_id(factory_id), Factory.slot_from_id(factory_id)]
	)
	invalidate_production_cache(factory.owner_tag)
	return true


func get_factory_efficiency(factory_id: int) -> float:
	if factory_manager:
		return factory_manager.get_factory_efficiency(factory_id)
	return 1.0


func get_factories_producing(design_id: String) -> Array[Factory]:
	var result: Array[Factory] = []
	if factory_manager == null or design_id.is_empty():
		return result
	for fid in factory_manager.factories:
		var f: Factory = factory_manager.factories[fid]
		if f != null and f.current_production_design == design_id:
			result.append(f)
	return result


func get_total_output_for_design(design_id: String) -> float:
	var total := 0.0
	for f in get_factories_producing(design_id):
		total += f.get_daily_output_estimate()
	return total


# === Production Assignment screen support ===
# Screen snapshots are cached per country; invalidate_production_cache() on state changes.

func get_all_factories_for_country(country_tag: String) -> Array[Factory]:
	var result: Array[Factory] = []
	if factory_manager == null or country_tag.is_empty():
		return result
	for fid in factory_manager.factories:
		var f: Factory = factory_manager.factories[fid] as Factory
		if f != null and f.owner_tag == country_tag:
			result.append(f)
	return result


func get_factory_summary(factory_id: int) -> Dictionary:
	if factory_manager == null:
		return {}
	var f: Factory = factory_manager.get_factory(factory_id)
	if f == null:
		return {}

	return {
		"factory_id": factory_id,
		"province_id": f.province_id,
		"owner_tag": f.owner_tag,
		"factory_type": _get_factory_type(f),
		"status": _get_factory_status(f),
		"current_design": f.current_production_design,
		"efficiency": get_factory_efficiency(factory_id),
		"daily_output_estimate": f.get_daily_output_estimate(),
		"is_retooling": f.is_retooling,
		"retooling_progress": f.retooling_progress,
		"retooling_required": f.retooling_required,
		"max_lines": f.max_production_lines,
		"assigned_lines": f.assigned_lines.size(),
		"assigned_line_ids": f.assigned_lines.duplicate(),
		"current_damage": f.current_damage,
	}


func get_country_production_overview(country_tag: String) -> Dictionary:
	var factories := get_all_factories_for_country(country_tag)
	var factory_summaries: Array = []
	for f in factories:
		factory_summaries.append(get_factory_summary(f.factory_id))

	return {
		"country_tag": country_tag,
		"total_factories": factories.size(),
		"factories": factory_summaries,
	}


func get_factories_producing_design(design_id: String) -> Array[int]:
	var result: Array[int] = []
	for f in get_factories_producing(design_id):
		result.append(f.factory_id)
	return result


func get_production_screen_data(country_tag: String, use_cache: bool = true) -> ProductionScreenData:
	if use_cache and _production_screen_cache.has(country_tag):
		return _production_screen_cache[country_tag] as ProductionScreenData

	var data := _build_production_screen_data(country_tag)
	_production_screen_cache[country_tag] = data
	return data


func invalidate_production_cache(country_tag: String) -> void:
	_production_screen_cache.erase(country_tag)


func clear_all_production_caches() -> void:
	_production_screen_cache.clear()


## Clears production and leader screen caches (testing, save load, major resets).
func clear_all_caches() -> void:
	clear_all_production_caches()
	var leader_mgr := get_node_or_null("/root/LeaderManager")
	if leader_mgr != null and leader_mgr.has_method("clear_all_leader_caches"):
		leader_mgr.clear_all_leader_caches()


func _build_production_screen_data(country_tag: String) -> ProductionScreenData:
	var data := ProductionScreenData.new()
	data.country_tag = country_tag

	var factories := get_all_factories_for_country(country_tag)
	data.total_factories = factories.size()

	var total_lines := 0
	var total_efficiency := 0.0
	var retooling_count := 0
	var total_daily_output := 0.0
	var low_efficiency_count := 0

	var by_type: Dictionary = {}
	var by_status: Dictionary = {
		"producing": [],
		"retooling": [],
		"idle": [],
	}
	var designs_in_production: Dictionary = {}

	for f in factories:
		var summary := get_factory_summary(f.factory_id)
		data.factories.append(summary)

		total_lines += f.assigned_lines.size()
		var efficiency := get_factory_efficiency(f.factory_id)
		total_efficiency += efficiency

		var status := _get_factory_status(f)
		_append_to_group(by_status, status, summary)
		if status == "retooling":
			retooling_count += 1

		if efficiency < 0.4:
			low_efficiency_count += 1

		var daily := f.get_daily_output_estimate()
		total_daily_output += daily

		if not f.current_production_design.is_empty():
			var design_id := f.current_production_design
			if not designs_in_production.has(design_id):
				designs_in_production[design_id] = 0.0
			designs_in_production[design_id] = float(designs_in_production[design_id]) + daily

		_append_to_group(by_type, _get_factory_type(f), summary)

	data.total_production_lines = total_lines
	data.average_efficiency = (
		total_efficiency / float(data.total_factories) if data.total_factories > 0 else 1.0
	)
	data.factories_in_retooling = retooling_count
	data.estimated_daily_output = total_daily_output
	data.designs_in_production = designs_in_production
	data.factories_by_type = by_type
	data.factories_by_status = by_status

	data.has_critical_efficiency = low_efficiency_count > 0
	data.has_many_retooling = (
		data.total_factories > 0 and float(retooling_count) > float(data.total_factories) * 0.3
	)

	return data


# === Production helper methods ===

func _get_factory_status(factory: Factory) -> String:
	if factory.is_retooling:
		return "retooling"
	if not factory.current_production_design.is_empty():
		return "producing"
	return "idle"


func _get_factory_type(factory: Factory) -> String:
	if not factory.factory_type.is_empty() and factory.factory_type != "standard":
		return factory.factory_type

	var design := factory.current_production_design.to_lower()
	if (
		"ship" in design
		or "carrier" in design
		or "destroyer" in design
		or "battleship" in design
	):
		return "shipyard"
	if "tank" in design or "vehicle" in design or "halftrack" in design:
		return "tank_factory"
	if "fighter" in design or "bomber" in design or "aircraft" in design:
		return "aircraft_factory"
	return "general_factory"


func _append_to_group(group_dict: Dictionary, key: String, value: Variant) -> void:
	if not group_dict.has(key):
		group_dict[key] = []
	(group_dict[key] as Array).append(value)


func reassign_factory(factory_id: int, new_design_id: String, new_category: String = "") -> bool:
	if factory_manager == null:
		return false

	var factory: Factory = factory_manager.get_factory(factory_id)
	if factory == null:
		push_warning("Cannot reassign - factory %d not found" % factory_id)
		return false

	var old_design: String = factory.current_production_design
	if old_design == new_design_id:
		return true

	if typeof(TechnologyManager) != TYPE_NIL:
		# Map Build Eligibility gate (Phase 1 tech + factory type)
		var gate := TechnologyManager.factory_can_build_design(
			factory.owner_tag,
			factory,
			new_design_id,
		)
		if not bool(gate.get("allowed", true)):
			var detail: Dictionary = gate.get("detail", {}) as Dictionary
			push_warning(
				"ProductionManager: factory %d blocked on '%s' — %s"
				% [factory_id, new_design_id, detail.get("reason", gate.get("error", ""))]
			)
			return false

	if ProductionNavalRules.is_naval_design(new_design_id):
		if not ProductionNavalRules.factory_can_build_naval(factory):
			push_warning(
				"ProductionManager: factory %d cannot build naval design '%s' (requires shipyard at port)"
				% [factory_id, new_design_id]
			)
			return false
		if factory_manager != null and not factory_manager.province_has_port(factory.province_id):
			push_warning(
				"ProductionManager: factory %d is not in a port province"
				% factory_id
			)
			return false

	var old_group := _retool_group_for_design(old_design)
	var new_group := _retool_group_for_design(new_design_id, new_category)
	var params := get_retooling_params(old_group, new_group)

	for line_id in factory.assigned_lines:
		var line := get_line(line_id)
		if line == null:
			continue
		line.reset_progress()
		line.design_id = new_design_id
		if GameData.design_data != null and GameData.design_data.get_template(new_design_id) != null:
			line.set_template(new_design_id)
		else:
			line.refresh_design_production_cost()

	factory.start_retooling(
		old_design,
		new_design_id,
		float(params.get("retool_days", 90.0)),
		float(params.get("recovery_days", 45.0)),
		float(params.get("retained_efficiency", 0.2)),
	)

	print(
		"Retooling Factory %d: %s → %s | Retained: %.0f%% | Retool: %.0f days | Recovery: %.0f days"
		% [
			factory_id,
			old_design,
			new_design_id,
			float(params.get("retained_efficiency", 0.0)) * 100.0,
			float(params.get("retool_days", 0.0)),
			float(params.get("recovery_days", 0.0)),
		]
	)
	invalidate_production_cache(factory.owner_tag)
	if typeof(DesignManager) != TYPE_NIL:
		DesignManager.mark_design_used(factory.owner_tag, new_design_id)
	return true


func get_concentration_bonus(design_id: String) -> float:
	var count := get_factories_producing(design_id).size()
	if count <= 1:
		return 1.0
	# +4% per additional factory, capped at +25%
	var bonus := 1.0 + (count - 1) * 0.04
	return minf(bonus, 1.25)


func get_effective_daily_output(design_id: String) -> float:
	var base := get_total_output_for_design(design_id)
	return base * get_concentration_bonus(design_id)


func get_design_production_info(design_id: String) -> Dictionary:
	var factories := get_factories_producing(design_id)
	var template: UnitTemplate = GameData.design_data.get_template(design_id) if GameData.design_data else null
	var breakdown: Dictionary = (
		template.get_production_cost_breakdown(GameData.design_data)
		if template != null
		else {}
	)
	var unit_cost := float(breakdown.get("total", 0.0))
	var category := str(breakdown.get("category", ""))
	var era := str(breakdown.get("era", ""))
	var daily_pp := _get_base_daily_points() * get_concentration_bonus(design_id)
	return {
		"design_id": design_id,
		"production_cost": unit_cost,
		"production_category": category,
		"production_era": era,
		"cost_breakdown": breakdown,
		"factory_count": factories.size(),
		"base_daily_points": get_total_output_for_design(design_id),
		"concentration_bonus": get_concentration_bonus(design_id),
		"effective_daily_points": get_effective_daily_output(design_id),
		"estimated_days_per_unit": ProductionCostCalculator.estimate_build_days(
			unit_cost, daily_pp
		) if unit_cost > 0.0 and daily_pp > 0.0 else 0.0,
		"factories": factories.map(func(f: Factory) -> int: return f.factory_id),
		"daily_resource_cost": get_design_resource_preview(design_id),
	}


## === Save/Load support (SaveLoadManager contract) ===
## Captures national production state + per-line runtime (progress, retooling, shortages).
## Factory-specific state (damage, efficiency, assigned lines) lives in FactoryManager/Factory resources.
func get_save_data() -> Dictionary:
	var lines_data := {}
	for line_id in _lines:
		var line: ProductionLine = _lines[line_id]
		if line == null:
			continue
		lines_data[line_id] = {
			"design_id": line.design_id,
			"progress": line.progress,
			"completed_count": line.completed_count,
			"design_production_cost": line.design_production_cost,
			"daily_resource_cost": line.daily_resource_cost.duplicate(true),
			"resource_shortage_penalty": line.resource_shortage_penalty,
			"shortage_reliability_multiplier": line.shortage_reliability_multiplier,
			"retooling_days_remaining": line.retooling_days_remaining,
			"production_progress": line.production_progress,
			"current_template_id": line.current_template_id,
			"factory_id": line.factory_id,
		}

	return {
		"production_stance": production_stance,
		"national_stockpile": national_stockpile.duplicate(true),
		"national_equipment_stockpile": national_equipment_stockpile.duplicate(true),
		"country_equipment_stockpiles": country_equipment_stockpiles.duplicate(true),
		"unit_equipment_stock": _unit_equipment_stock.duplicate(true),
		"active_modifiers": _active_modifiers.duplicate(true),
		"lines": lines_data,
		# family experience, priority etc. can be added later if they prove important
	}

func apply_save_data(data: Dictionary) -> void:
	if data.has("production_stance"):
		production_stance = str(data["production_stance"])
	if data.has("national_stockpile"):
		national_stockpile = (data["national_stockpile"] as Dictionary).duplicate(true)
	if data.has("national_equipment_stockpile"):
		national_equipment_stockpile = (data["national_equipment_stockpile"] as Dictionary).duplicate(true)
	if data.has("country_equipment_stockpiles"):
		country_equipment_stockpiles = (data["country_equipment_stockpiles"] as Dictionary).duplicate(true)
	if data.has("unit_equipment_stock"):
		_unit_equipment_stock = (data["unit_equipment_stock"] as Dictionary).duplicate(true)
	if data.has("active_modifiers"):
		_active_modifiers = (data["active_modifiers"] as Dictionary).duplicate(true)

	if data.has("lines"):
		var lines_data: Dictionary = data["lines"]
		for line_id in lines_data:
			var ld: Dictionary = lines_data[line_id]
			var line := get_line(line_id)
			if line == null:
				line = create_line(line_id)  # ensure it exists
			if line != null:
				line.design_id = str(ld.get("design_id", ""))
				line.progress = float(ld.get("progress", 0.0))
				line.completed_count = int(ld.get("completed_count", 0))
				if ld.has("design_production_cost"):
					line.design_production_cost = float(ld["design_production_cost"])
				if ld.has("daily_resource_cost"):
					line.daily_resource_cost = (ld["daily_resource_cost"] as Dictionary).duplicate(true)
				line.resource_shortage_penalty = float(ld.get("resource_shortage_penalty", 1.0))
				line.shortage_reliability_multiplier = float(ld.get("shortage_reliability_multiplier", 1.0))
				line.retooling_days_remaining = float(ld.get("retooling_days_remaining", 0.0))
				line.production_progress = float(ld.get("production_progress", 0.0))
				line.current_template_id = str(ld.get("current_template_id", ""))
				# factory_id usually set at creation; restore if present
				if ld.has("factory_id"):
					line.factory_id = int(ld["factory_id"])

	clear_all_caches()
	print("ProductionManager: Save data applied (%d lines)" % (data.get("lines", {}).size() if data.has("lines") else 0))


## Game loop entry point: one day of national production (supply hooks can chain here later).
func daily_production_tick() -> void:
	advance_production(1.0)


## Listener for central TimeManager daily tick (wired in _ready).
## Keeps production in sync with the rest of the daily simulation loop (Supply/Agents/Repair).
func _on_game_day_advanced(_year: int, _month: int, _day: int) -> void:
	daily_production_tick()


func advance_production(days: float) -> void:
	if days <= 0.0:
		return

	for line_id in _lines:
		var line: ProductionLine = _lines[line_id]
		if line.factory_id == 0 or line.design_id.is_empty():
			continue

		if factory_manager == null:
			continue
		var factory: Factory = factory_manager.get_factory(line.factory_id)
		if factory == null:
			continue

		if factory.is_retooling:
			var was_retooling: bool = factory.is_retooling
			factory.advance_retooling(days)
			if was_retooling != factory.is_retooling or factory.is_retooling:
				invalidate_production_cache(factory.owner_tag)

		evaluate_line_resources(line_id, days)

		var base_efficiency: float = line.get_factory_efficiency()
		var retool_eff: float = factory.get_current_efficiency() if factory.is_retooling else 1.0
		var shortage_eff: float = line.resource_shortage_penalty

		var concentration: float = get_concentration_bonus(line.design_id)
		var slot_rush: float = get_concentrated_production_multiplier(line.factory_id, line.design_id)
		# Pop labor (new leap forward): countries with larger population provide more labor, boosting factory output (ties pop policies/growth to production).
		var pop_labor := 1.0
		if typeof(GameData) != TYPE_NIL and GameData.has_method("get_peace_state"):
			var ps: Dictionary = GameData.get_peace_state()
			var p := float(ps.get("population", {}).get(factory.owner_tag, 0.0))
			if p > 0:
				pop_labor = clampf(1.0 + (p / 100000000.0) * 0.2, 1.0, 1.5)
		var daily_points: float = (
			_get_base_daily_points()
			* base_efficiency
			* retool_eff
			* shortage_eff
			* concentration
			* slot_rush
			* pop_labor
			* days
		)
		line.add_progress(daily_points)
		production_progress_updated.emit(line_id, line.progress)

		var cost := line.design_production_cost
		while cost > 0.0 and line.progress >= cost:
			_complete_item(line, line_id)


func _complete_item(line: ProductionLine, line_id: String) -> void:
	line.completed_count += 1
	line.progress -= line.design_production_cost
	production_completed.emit(line_id, line.design_id, 1)


func get_line_progress_info(line_id: String) -> Dictionary:
	var line := get_line(line_id)
	if line == null:
		return {}
	var template: UnitTemplate = line.get_current_template()
	var cost_breakdown: Dictionary = (
		template.get_production_cost_breakdown(GameData.design_data, line.get_effective_loadout())
		if template != null
		else {}
	)
	var factory: Factory = factory_manager.get_factory(line.factory_id) if factory_manager else null
	return {
		"line_id": line_id,
		"design_id": line.design_id,
		"factory_id": line.factory_id,
		"factory_max_lines": factory.max_production_lines if factory else 1,
		"factory_lines_used": factory.assigned_lines.size() if factory else 0,
		"lines_on_same_design": get_lines_on_design_in_factory(line.factory_id, line.design_id),
		"slot_rush_multiplier": get_concentrated_production_multiplier(line.factory_id, line.design_id),
		"daily_resource_cost": line.get_daily_resource_cost(),
		"resource_fill_ratio": preview_resource_fill_ratio(line_id, 1.0),
		"shortage_penalty": line.resource_shortage_penalty,
		"shortage_reliability_multiplier": line.shortage_reliability_multiplier,
		"progress": line.progress,
		"design_production_cost": line.design_production_cost,
		"required_progress": line.design_production_cost,
		"percent_complete": line.get_progress_percent(),
		"completed_count": line.completed_count,
		"cost_breakdown": cost_breakdown,
		"estimated_days_remaining": ProductionCostCalculator.estimate_build_days(
			maxf(line.design_production_cost - line.progress, 0.0),
			_get_base_daily_points() * line.get_factory_efficiency() * get_concentration_bonus(line.design_id),
		),
	}
