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
signal equipment_flow_created(flow_id: String, equipment_id: String, amount: int, mode: String)
signal equipment_flow_interdicted(flow_id: String, cause: String, lost: int, delivered: int)
signal equipment_flow_delivered(flow_id: String, equipment_id: String, amount: int, to_unit_id: String)

const GLOBAL_MODIFIERS_PATH := "res://data/production/global_modifiers.json"
const EQUIP_FLOW_CALC_PATH := "res://scripts/production/EquipmentFlowCalculator.gd"
const REINF_LOG_CALC_PATH := "res://scripts/production/ReinforcementLogisticsCalculator.gd"
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
## Rolling average production reliability by design (from resource shortage at completion).
## design_id -> { "reliability": float 0.72–1.0, "samples": int }
var equipment_production_reliability: Dictionary = {}
## One-shot auto-seed flag so daily harvest does not spam plants.
var _resource_plants_seeded: bool = false
## pid → {resource_key: develop_level 0–3}. Expand existing deposits; never invent geology.
var province_resource_dev: Dictionary = {}

var _equipment_shortage_tracker := EquipmentShortageTracker.new()

# === Reinforcement & priority system ===
var priority_reinforcement_units: Dictionary = {}  # unit_id -> bool

# === EquipmentFlow ledger (CP1 — factory/stock → front; interdictable) ===
## flow_id -> EquipmentFlow dict
var _equipment_flows: Dictionary = {}
var _equipment_flow_seq: int = 0

# === RF1 reinforcement logistics (experience + transit policy) ===
## country_tag -> training policy id (see ReinforcementLogisticsCalculator.TRAINING_POLICIES)
var country_training_policy: Dictionary = {}

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



# === Layered production per-line API (minimal wiring for player/AI choice + tech rule_flag unlocks) ===
func get_available_production_layers(country_tag: String) -> Array[String]:
	var layers: Array[String] = ["mass"]
	var tag := country_tag.strip_edges().to_upper()
	if typeof(TechnologyManager) != TYPE_NIL:
		if TechnologyManager.has_rule_flag(tag, "mass_production"):
			if not "mass" in layers: layers.append("mass")
		if TechnologyManager.has_rule_flag(tag, "automated_production"):
			layers.append("automated")
		if TechnologyManager.has_rule_flag(tag, "additive_manuf"):
			layers.append("additive")
		if TechnologyManager.has_rule_flag(tag, "nanotech"):
			layers.append("nano")
	return layers

func is_production_layer_unlocked(country_tag: String, layer: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	var l := layer.to_lower()
	if l == "mass":
		return true
	if typeof(TechnologyManager) == TYPE_NIL:
		return false
	if l == "automated":
		return TechnologyManager.has_rule_flag(tag, "automated_production")
	if l == "additive":
		return TechnologyManager.has_rule_flag(tag, "additive_manuf")
	if l == "nano":
		return TechnologyManager.has_rule_flag(tag, "nanotech")
	return false

func get_line_production_layer(line_id: String) -> String:
	var line := get_line(line_id)
	if line == null:
		return "mass"
	return line.get_current_layer()

func set_line_production_layer(line_id: String, layer: String) -> Dictionary:
	var line := get_line(line_id)
	if line == null:
		return {"success": false, "error": "unknown_line"}
	var owner := _get_line_owner_tag(line)
	if owner.is_empty():
		# allow during init
		pass
	elif not is_production_layer_unlocked(owner, layer):
		return {"success": false, "error": "layer_locked", "layer": layer, "required_flag": _layer_to_flag(layer)}
	var res := line.set_production_layer(layer)
	if res.get("success", false):
		_refresh_line_modifiers(line)  # pick up NMM layer fold
		invalidate_production_cache(owner)
	return res

func _layer_to_flag(layer: String) -> String:
	match layer.to_lower():
		"mass": return "mass_production"
		"automated": return "automated_production"
		"additive": return "additive_manuf"
		"nano": return "nanotech"
	return ""

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


## Tag-scoped day advance — only lines owned by country_tag (interactive multi-AI / lean majors).
## Does NOT run global daily_production_tick (avoids N× player harvest when N majors apply).
func advance_days_for_country(country_tag: String, days: float = 1.0) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var report := {
		"ok": true,
		"days_advanced": days,
		"country_tag": tag,
		"lines": {},
		"total_units_completed": 0,
		"lines_touched": 0,
		"empty": true,
	}
	if tag.is_empty() or days <= 0.0:
		report["ok"] = false
		report["reason"] = "bad_tag_or_days"
		return report
	for line_id in _lines:
		var line: ProductionLine = _lines[line_id]
		if line == null:
			continue
		var owner := _get_line_owner_tag(line)
		if owner.is_empty() and str(line_id).begins_with("oob_"):
			var parts: PackedStringArray = str(line_id).split("_", false, 2)
			if parts.size() >= 2:
				owner = parts[1].to_upper()
		if owner != tag:
			continue
		_refresh_line_modifiers(line)
		var line_report: Dictionary = line.advance_days(days)
		report["lines"][line_id] = line_report
		report["total_units_completed"] += int(line_report.get("units_completed", 0))
		report["lines_touched"] = int(report["lines_touched"]) + 1
		report["empty"] = false
	# Soft stockpile credit when no lines exist yet (majors without seeded OOB still "act")
	if bool(report["empty"]):
		add_to_country_equipment_stockpile(tag, "infantry_equipment", 1)
		report["soft_stock_credit"] = 1
		report["empty"] = false
		report["ok"] = true
		report["reason"] = "soft_stock_credit"
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
		var raw: Variant = _active_modifiers[modifier_id]
		var src := ""
		if raw is ProductionModifier:
			src = (raw as ProductionModifier).source
		elif typeof(raw) == TYPE_DICTIONARY:
			src = str((raw as Dictionary).get("source", ""))
		else:
			to_remove.append(str(modifier_id))
			continue
		if src.begins_with(source_prefix):
			to_remove.append(str(modifier_id))
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
	var owner_tag := _get_line_owner_tag(line) if line != null else ""
	# OOB line ids are oob_{TAG}_{design} — recover owner when factory lookup is empty.
	if owner_tag.is_empty() and str(_line_id).begins_with("oob_"):
		var parts: PackedStringArray = str(_line_id).split("_", false, 2)
		if parts.size() >= 2 and parts[1].length() >= 2 and parts[1].length() <= 4:
			owner_tag = parts[1].to_upper()
	if owner_tag != "":
		if design_id.begins_with("civilian_"):
			add_civilian_goods(owner_tag, count)
			# Also feed GameData for pop happiness/mandate effects (civilian output -> pop)
			if typeof(GameData) != TYPE_NIL and GameData.has_method("produce_civilian_goods"):
				GameData.produce_civilian_goods(owner_tag, count)
			print("Civilian production complete: %s × %d goods for %s (happiness/cohesion/mandate + local supply wiring hook)." % [design_id, count, owner_tag])
		else:
			# CP2: complete always lands batch-scaled stock units in country stockpile.
			var credit: Dictionary = credit_production_complete_to_stockpile(
				owner_tag, design_id, count, {},
			)
			var units := int(credit.get("stock_units", count))
			print("Production complete: %s × %d added to %s stockpile" % [design_id, units, owner_tag])
			# Stamp shortage reliability onto design quality for combat hook.
			if line != null:
				_record_equipment_production_reliability(design_id, float(line.shortage_reliability_multiplier), count)
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
		if line != null and not design_id.begins_with("civilian_"):
			_record_equipment_production_reliability(design_id, float(line.shortage_reliability_multiplier), count)


func _record_equipment_production_reliability(design_id: String, reliability: float, count: int = 1) -> void:
	if design_id.is_empty() or count <= 0:
		return
	var rhc = load("res://scripts/production/ResourceHarvestCalculator.gd")
	var rel := clampf(reliability, 0.5, 1.0)
	if rhc != null and rhc.has_method("combat_reliability_from_production"):
		rel = float(rhc.combat_reliability_from_production(rel))
	var prev: Dictionary = equipment_production_reliability.get(design_id, {}) as Dictionary if equipment_production_reliability.get(design_id) is Dictionary else {}
	var samples := int(prev.get("samples", 0))
	var old_r := float(prev.get("reliability", 1.0))
	var n := maxi(count, 1)
	var new_samples := samples + n
	var new_r := (old_r * float(samples) + rel * float(n)) / float(new_samples) if new_samples > 0 else rel
	equipment_production_reliability[design_id] = {
		"reliability": clampf(new_r, 0.5, 1.0),
		"samples": new_samples,
	}


func get_equipment_production_reliability(design_id: String) -> float:
	if design_id.is_empty() or not equipment_production_reliability.has(design_id):
		return 1.0
	var e: Dictionary = equipment_production_reliability[design_id] as Dictionary
	return clampf(float(e.get("reliability", 1.0)), 0.5, 1.0)


## Ops triad fuel burn: vehicle class (jet/rocket higher) draws national Fuel stockpile.
func burn_ops_fuel(vehicle_class: String, units: float = 1.0, days: float = 1.0) -> Dictionary:
	var rhc = load("res://scripts/production/ResourceHarvestCalculator.gd")
	var need := 0.25 * maxf(units, 0.0) * maxf(days, 0.0)
	if rhc != null and rhc.has_method("compute_ops_fuel_cost"):
		need = float(rhc.compute_ops_fuel_cost(vehicle_class, units, days))
	var have := float(national_stockpile.get("fuel", 0.0))
	var paid := minf(have, need)
	national_stockpile["fuel"] = have - paid
	var fill := 1.0 if need <= 0.0 else clampf(paid / need, 0.0, 1.0)
	# Soft ops mobility: empty fuel → ~55% mobility (mirrors production soft shortage floor)
	var mobility := 0.55 + 0.45 * fill
	return {
		"needed": need,
		"paid": paid,
		"fill_ratio": fill,
		"mobility_multiplier": mobility,
		"vehicle_class": vehicle_class,
		"shortage": paid + 0.001 < need,
	}


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


## Combat outcome: destroy/write-off unit equipment proportional to battle severity.
## severity 0–1 (losers typically ≥0.35). Returns {equipment_id: amount_removed, ...}.
## No-op / empty when unit has no on-hand stock (safe for unequipped formations).
func apply_combat_equipment_loss(formation_id: String, severity: float = 0.5) -> Dictionary:
	var removed: Dictionary = {}
	if formation_id.is_empty():
		return removed
	var sev := clampf(severity, 0.0, 1.0)
	if sev < 0.05:
		return removed
	var stock := get_unit_equipment_stock(formation_id)
	if stock.is_empty():
		return removed
	var next_stock: Dictionary = {}
	for equipment_id in stock.keys():
		var have := int(stock[equipment_id])
		if have <= 0:
			continue
		# At least 1 destroyed when severity is meaningful and unit had equipment.
		var loss := int(ceil(float(have) * sev))
		if loss < 1 and sev >= 0.25:
			loss = 1
		loss = mini(loss, have)
		if loss <= 0:
			next_stock[str(equipment_id)] = have
			continue
		removed[str(equipment_id)] = loss
		var left := have - loss
		if left > 0:
			next_stock[str(equipment_id)] = left
	set_unit_equipment_stock(formation_id, next_stock)
	if not removed.is_empty():
		print(
			"[COMBAT EQUIP LOSS] %s lost %s (severity=%.2f)"
			% [formation_id, str(removed), sev]
		)
	return removed


## Seed a small on-hand pack when the formation has no combat stock.
## CombatLoop / start_land_battle (BattleManager is file-locked):
##   ProductionManager.ensure_demo_combat_stock(fid, tag)
func ensure_demo_combat_stock(formation_id: String, country_tag: String = "") -> Dictionary:
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		return {}
	var stock := get_unit_equipment_stock(fid)
	for equipment_id in stock.keys():
		if int(stock[equipment_id]) > 0:
			return stock
	var seeded := {
		"infantry_equipment": 80,
		"support_equipment": 10,
	}
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		var form: Formation = LeaderManager.get_formation(fid)
		if form != null:
			var toe: Dictionary = LandCombatPower.equipment_toe(LandCombatPower.composition_from_formation(form))
			if not toe.is_empty():
				seeded = toe
	set_unit_equipment_stock(fid, seeded)
	var tag := country_tag.strip_edges().to_upper()
	print(
		"[DEMO COMBAT STOCK] %s (%s) seeded %s"
		% [fid, tag, str(seeded)]
	)
	return seeded.duplicate()


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
		# Formation-id callers (BattleManager passes formation_id as first arg): design equipment path.
		var fid := unit_id if not unit_id.is_empty() else division_template_id
		return get_formation_equipment_combat_stats(fid)
	var supply := get_node_or_null("/root/SupplyManager")
	if supply == null:
		return get_formation_equipment_combat_stats(unit_id if not unit_id.is_empty() else division_template_id)
	var template: DivisionTemplate = supply.division_templates.get_division(division_template_id)
	if template == null:
		# Not a division template — resolve as formation (world_full OOB land designs).
		var form_id := unit_id if not unit_id.is_empty() else division_template_id
		return get_formation_equipment_combat_stats(form_id)

	var shortages: Dictionary = {}
	if not unit_id.is_empty():
		var required := template.get_required_equipment(GameData.design_data)
		# On-hand equipment only for combat shortages (stockpile is reinforce pool, not free combat power).
		shortages = get_unit_on_hand_shortages(unit_id, required)

	var stats := template.get_final_combat_stats(shortages, GameData.design_data)
	if typeof(LeaderManager) != TYPE_NIL and not unit_id.is_empty():
		stats = LeaderManager.apply_training_path_supply_to_stats(stats, unit_id)
	return stats


## Shortages from unit equipment only (not country/national stockpile). Used for combat power.
func get_unit_on_hand_shortages(unit_id: String, required_equipment: Dictionary) -> Dictionary:
	var current_stock := get_unit_equipment_stock(unit_id)
	var shortages: Dictionary = {}
	for equipment_id in required_equipment:
		var needed := int(required_equipment[equipment_id])
		var have := int(current_stock.get(equipment_id, 0))
		if have < needed:
			shortages[str(equipment_id)] = needed - have
	return shortages


## Land OOB formations: required equipment is 1× formation.design_id (scenario equip path).
func get_formation_required_equipment(formation_id: String) -> Dictionary:
	if formation_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return {}
	var f: Formation = LeaderManager.get_formation(formation_id) if LeaderManager.has_method("get_formation") else null
	if f == null:
		return {}
	var did := str(f.design_id).strip_edges() if "design_id" in f else ""
	if did.is_empty():
		return {}
	return {did: 1}


## Combat stats for design-equipped land formations (no full DivisionTemplate required).
## Empty/insufficient unit equipment → has_shortages + reduced soft/hard/readiness.
func get_formation_equipment_combat_stats(formation_id: String) -> Dictionary:
	if formation_id.is_empty():
		return {}
	var f: Formation = null
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		f = LeaderManager.get_formation(formation_id)
	var design := ""
	if f != null and "design_id" in f:
		design = str(f.design_id).strip_edges()
	var required: Dictionary = {}
	if not design.is_empty():
		required[design] = 1
	elif f != null:
		# No design: treat as fully shorted soft infantry stub
		return {
			"soft_attack": 0.35,
			"hard_attack": 0.02,
			"readiness": 0.55,
			"organization": 0.7,
			"supply_consumption": 1.0,
			"has_shortages": true,
			"reliability": 0.6,
		}
	else:
		return {}

	var shortages := get_unit_on_hand_shortages(formation_id, required)
	var soft := 0.9
	var hard := 0.08
	var readiness := 1.0
	var reliability := 0.9
	var supply_need := 1.0
	if GameData.design_data != null and not design.is_empty():
		var tpl: UnitTemplate = GameData.design_data.get_template(design)
		if tpl != null:
			var bs: Dictionary = tpl.base_stats if "base_stats" in tpl else {}
			if typeof(bs) != TYPE_DICTIONARY:
				bs = {}
			var hardness := float(bs.get("hardness", 0.0))
			var armor := float(bs.get("armor", 0.0))
			reliability = clampf(float(bs.get("reliability", 70.0)) / 100.0, 0.4, 1.0)
			supply_need = maxf(float(bs.get("supply_need", 10.0)) / 12.0, 0.5)
			# Armor/hardness → hard attack; soft from inverse hardness (tanks still have soft).
			hard = clampf(0.05 + armor / 80.0 + hardness / 200.0, 0.05, 2.5)
			soft = clampf(0.7 + (100.0 - hardness) / 120.0, 0.4, 2.2)
	if not shortages.is_empty():
		soft *= 0.62
		hard *= 0.58
		readiness *= 0.68
		reliability *= 0.85
	# Production-era resource shortage reliability (soft floor ~0.72) hits field readiness/reliability.
	var prod_rel := get_equipment_production_reliability(design) if not design.is_empty() else 1.0
	if prod_rel < 0.999:
		reliability *= prod_rel
		soft *= lerpf(0.92, 1.0, prod_rel)
		hard *= lerpf(0.92, 1.0, prod_rel)
		readiness *= lerpf(0.9, 1.0, prod_rel)
	return {
		"soft_attack": soft,
		"hard_attack": hard,
		"readiness": clampf(readiness, 0.3, 1.5),
		"organization": 1.0 if shortages.is_empty() else 0.82,
		"supply_consumption": supply_need,
		"reliability": clampf(reliability, 0.4, 1.0),
		"production_reliability": prod_rel,
		"has_shortages": not shortages.is_empty(),
		"missing_equipment": shortages.duplicate(true),
	}


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
	var flows: Dictionary = advance_equipment_flows(1.0)
	# RF2 path: ship deficits via EquipmentFlow (in transit — not force-deliver).
	var via_flow: Dictionary = demand_reinforce_tick_via_flow(required_map, {"force_deliver": false})
	var toe_from_stockpile: Dictionary = {}
	for unit_id in required_map:
		var uid := str(unit_id)
		if uid.is_empty() or uid.begins_with("_"):
			continue
		toe_from_stockpile[uid] = reinforce_unit_toe_from_stockpile(uid)
	var reinf := {
		"units": {},
		"equipment_flows": flows,
		"via_flow": via_flow,
		"toe_from_stockpile": toe_from_stockpile,
		"instant_topup": false,
		"model": "reinforce_experience_logistics_ledger",
	}
	return reinf


## --- EquipmentFlow (CP1) + stock/reinforce (CP2) + RF logistics ----------------

func _equip_flow_calc():
	return load(EQUIP_FLOW_CALC_PATH)


func _reinf_log_calc():
	return load(REINF_LOG_CALC_PATH)


func set_country_training_policy(country_tag: String, policy_id: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return
	var pid := policy_id.strip_edges().to_lower()
	var calc = _reinf_log_calc()
	if calc != null and calc.has_method("list_training_policy_ids"):
		var ids: PackedStringArray = calc.list_training_policy_ids()
		if not ids.is_empty() and not ids.has(pid):
			pid = "two_year_service"
	country_training_policy[tag] = pid


func get_country_training_policy(country_tag: String) -> String:
	var tag := country_tag.strip_edges().to_upper()
	return str(country_training_policy.get(tag, "two_year_service"))


func list_training_policies() -> Array:
	var calc = _reinf_log_calc()
	var out: Array = []
	if calc == null or not calc.has_method("list_training_policy_ids"):
		return out
	for pid in calc.list_training_policy_ids():
		var score: Dictionary = {}
		if calc.has_method("policy_tradeoff_score"):
			score = calc.policy_tradeoff_score(str(pid)) as Dictionary
		else:
			score = {"policy_id": str(pid)}
		out.append(score)
	return out


## RF3: apply policy and return trade-off card (quantity vs quality).
## CP6: AI logistics doctrine — reinforce mode + escort preference for EquipmentFlows.
## context: { year, overseas, fuel 0–1, threat 0–1, high_value, tech_flags }
func ai_select_logistics_doctrine(country_tag: String, context: Dictionary = {}) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var year := int(context.get("year", 1939))
	var overseas := bool(context.get("overseas", false))
	var fuel := clampf(float(context.get("fuel", 1.0)), 0.0, 1.0)
	var threat := clampf(float(context.get("threat", 0.3)), 0.0, 1.0)
	var high_value := bool(context.get("high_value", false))
	var tech_flags: Dictionary = {}
	if context.get("tech_flags") is Dictionary:
		tech_flags = context.get("tech_flags") as Dictionary
	var mode := preferred_reinforce_mode(year, tech_flags, overseas)
	# Fuel starvation forces slower surface modes
	if fuel < 0.35 and mode in ["airlift", "helicopter", "drone_logistics", "orbital"]:
		mode = "sealift" if overseas else "rail"
	var escort := false
	var reason := "default_auto"
	if high_value or threat >= 0.55:
		escort = true
		reason = "escort_high_value_or_threat"
	elif mode in ["sealift", "airlift"] and threat >= 0.35:
		escort = true
		reason = "escort_exposed_mode"
	elif threat < 0.2 and fuel > 0.7:
		reason = "fast_unescorted"
	# Corridor risk bias
	var risk_bias := 0.08
	if mode == "airlift":
		risk_bias = 0.14
	elif mode == "sealift":
		risk_bias = 0.16
	elif mode == "drone_logistics":
		risk_bias = 0.11
	elif mode == "orbital":
		risk_bias = 0.18
	if escort:
		risk_bias *= 0.55
	return {
		"ok": true,
		"country_tag": tag,
		"mode": mode,
		"escort": escort,
		"corridor_risk_bias": risk_bias,
		"reason": reason,
		"year": year,
		"logistics_ok": true,
		"model": "reinforce_experience_logistics_ledger",
		"plain": "AI logistics: %s via %s%s." % [
			tag, mode, " (escorted)" if escort else "",
		],
	}


## RF6: AI doctrine pick for training/recruit policy (cadre vs crash vs clone).
## context: { at_war, manpower_strain 0–1, elite_focus, industry_stress 0–1, year }
func ai_select_training_policy(country_tag: String, context: Dictionary = {}) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var at_war := bool(context.get("at_war", false))
	var strain := clampf(float(context.get("manpower_strain", 0.0)), 0.0, 1.0)
	var elite := bool(context.get("elite_focus", false))
	var industry := clampf(float(context.get("industry_stress", 0.0)), 0.0, 1.0)
	var year := int(context.get("year", 1939))
	var pick := "two_year_service"
	var reason := "peacetime_balanced"
	if elite and not at_war:
		pick = "volunteer_cadre"
		reason = "elite_peacetime_cadre"
	elif at_war and strain >= 0.75:
		if year >= 2040 and industry >= 0.6:
			pick = "clone_batch_fill"
			reason = "existential_quantity_crisis_fiction"
		else:
			pick = "wartime_crash"
			reason = "high_strain_wartime_draft"
	elif at_war and strain >= 0.4:
		pick = "short_conscript" if year < 1970 else "selective_service"
		reason = "moderate_wartime_expansion"
	elif at_war and elite:
		pick = "all_volunteer_force" if year >= 1973 else "volunteer_cadre"
		reason = "quality_war_core"
	elif year >= 2000 and not at_war:
		pick = "all_volunteer_force"
		reason = "modern_avf"
	elif year >= 1950 and not at_war:
		pick = "national_service"
		reason = "cold_war_baseline"
	var applied: Dictionary = apply_training_policy_decision(tag, pick)
	applied["ai_pick"] = pick
	applied["ai_reason"] = reason
	applied["context"] = context.duplicate(true)
	applied["model"] = "reinforce_experience_logistics_ledger"
	return applied


func apply_training_policy_decision(country_tag: String, policy_id: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var before := get_country_training_policy(tag)
	set_country_training_policy(tag, policy_id)
	var after := get_country_training_policy(tag)
	var calc = _reinf_log_calc()
	var score: Dictionary = {}
	if calc != null and calc.has_method("policy_tradeoff_score"):
		score = calc.policy_tradeoff_score(after) as Dictionary
	var before_xp := 38.0
	var after_xp := float(score.get("recruit_xp", 38.0))
	if calc != null and calc.has_method("recruit_xp_for_policy"):
		before_xp = float(calc.recruit_xp_for_policy(before))
		after_xp = float(calc.recruit_xp_for_policy(after))
	var want := policy_id.strip_edges().to_lower()
	return {
		"ok": after == want and not after.is_empty(),
		"country_tag": tag,
		"policy_before": before,
		"policy_after": after,
		"recruit_xp_before": before_xp,
		"recruit_xp_after": after_xp,
		"tradeoff": score,
		"model": "reinforce_experience_logistics_ledger",
	}


func is_reinforce_mode_unlocked(mode: String, year: int = 1939, tech_flags: Dictionary = {}) -> bool:
	var calc = _reinf_log_calc()
	if calc != null and calc.has_method("mode_unlocked"):
		return bool(calc.mode_unlocked(mode, year, tech_flags))
	return mode in ["rail", "road", "sealift", "river"]


func preferred_reinforce_mode(year: int = 1939, tech_flags: Dictionary = {}, overseas: bool = false) -> String:
	var calc = _reinf_log_calc()
	if calc != null and calc.has_method("preferred_reinforce_mode"):
		return str(calc.preferred_reinforce_mode(year, tech_flags, overseas))
	return "rail"


## RF2: create in-transit flow (force_deliver false) and prove it remains active.
func run_non_instant_reinforce_demo(
	country_tag: String = "USA",
	equipment_id: String = "medium_tank_mk4",
	amount: int = 3,
	opts: Dictionary = {},
) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var eid := equipment_id.strip_edges()
	if has_method("reset_equipment_flows") and bool(opts.get("reset", true)):
		reset_equipment_flows()
	add_to_country_equipment_stockpile(tag, eid, maxi(amount, 1) + 2)
	var year := int(opts.get("year", 1916))
	var mode := str(opts.get("mode", "rail"))
	var unit_id := str(opts.get("to_unit_id", "usa_non_instant_demo"))
	clear_unit_equipment_stock(unit_id)
	var stock_before_unit := int(get_unit_equipment_stock(unit_id).get(eid, 0))
	var created: Dictionary = create_equipment_flow(
		tag, eid, amount,
		int(opts.get("from_province", 1)),
		int(opts.get("to_province", 2)),
		unit_id,
		mode,
		{
			"hops": int(opts.get("hops", 3)),
			"distance_km": float(opts.get("distance_km", 1200.0)),
			"year": year,
			"depot_fill": float(opts.get("depot_fill", 0.85)),
			"corridor_control": float(opts.get("corridor_control", 0.8)),
			"fuel": float(opts.get("fuel", 0.7)),
			"supplies": float(opts.get("supplies", 0.8)),
		},
	)
	if not bool(created.get("ok", false)):
		return created
	var flow: Dictionary = created.get("flow", {}) if created.get("flow") is Dictionary else {}
	var days_total := float(flow.get("days_total", 0.0))
	var fid := str(created.get("flow_id", ""))
	# Advance only 0.25 day — must still be active (non-instant)
	var adv: Dictionary = advance_equipment_flows(0.25)
	var after: Dictionary = get_equipment_flow(fid)
	var still_active := bool(after.get("active", false))
	var unit_after := int(get_unit_equipment_stock(unit_id).get(eid, 0))
	var calc = _reinf_log_calc()
	var non_instant := still_active and days_total >= 0.75 and unit_after == stock_before_unit
	if calc != null and calc.has_method("is_non_instant_flow"):
		non_instant = bool(calc.is_non_instant_flow(days_total, false, still_active)) and unit_after == stock_before_unit
	return {
		"ok": non_instant and bool(created.get("ok", false)),
		"non_instant_ok": non_instant,
		"days_total": days_total,
		"days_left": float(after.get("days_left", 0.0)),
		"still_active": still_active,
		"unit_received": unit_after,
		"advance": adv,
		"flow_id": fid,
		"model": "reinforce_experience_logistics_ledger",
	}


## RF2: combat mult from formation XP (uses calculator; optional real formation).
func evaluate_combat_experience_mult(formation_id: String = "") -> Dictionary:
	var calc = _reinf_log_calc()
	var green_xp := 15.0
	var vet_xp := 90.0
	var pair: Dictionary = {"ok": false, "green_mult": 0.8, "vet_mult": 1.1}
	if calc != null and calc.has_method("combat_xp_mult_ok_pair"):
		pair = calc.combat_xp_mult_ok_pair(green_xp, vet_xp) as Dictionary
	var form_mult := 1.0
	var form_xp := 48.0
	if not formation_id.is_empty():
		form_xp = get_formation_combat_experience(formation_id)
		if calc != null and calc.has_method("experience_combat_mult"):
			form_mult = float(calc.experience_combat_mult(form_xp))
	return {
		"ok": bool(pair.get("ok", false)),
		"combat_xp_ok": bool(pair.get("ok", false)),
		"green_mult": float(pair.get("green_mult", 0.0)),
		"vet_mult": float(pair.get("vet_mult", 0.0)),
		"formation_id": formation_id,
		"formation_xp": form_xp,
		"formation_mult": form_mult,
		"model": "reinforce_experience_logistics_ledger",
	}


func estimate_reinforce_transit_days(
	mode: String = "rail",
	hops: int = 1,
	distance_km: float = 0.0,
	year: int = 1939,
	opts: Dictionary = {},
) -> Dictionary:
	var calc = _reinf_log_calc()
	if calc == null or not calc.has_method("transit_days"):
		return {"ok": false, "days": 1.0, "error": "no_calc"}
	var policy := str(opts.get("policy_id", "two_year_service"))
	var days := float(calc.transit_days(
		mode, hops, distance_km, year,
		float(opts.get("depot_fill", 1.0)),
		float(opts.get("corridor_control", 1.0)),
		float(opts.get("fuel", 1.0)),
		float(opts.get("supplies", 1.0)),
		float(opts.get("electronics", 1.0)),
		policy,
		bool(opts.get("for_manpower", false)),
	))
	var plain := ""
	if calc.has_method("attribution_plain_transit"):
		plain = str(calc.attribution_plain_transit(mode, days, distance_km, year))
	return {
		"ok": true, "days": days, "mode": mode, "year": year, "distance_km": distance_km,
		"plain": plain, "model": "reinforce_experience_logistics_ledger",
	}


## Manpower strength fill with experience dilution (RF1). Caps daily absorb.
func apply_manpower_reinforce_with_experience(
	formation_id: String,
	strength_target_delta: float = 0.05,
	opts: Dictionary = {},
) -> Dictionary:
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formation"):
		return {"ok": false, "error": "no_leader_manager"}
	var f = LeaderManager.get_formation(formation_id)
	if f == null:
		return {"ok": false, "error": "no_formation"}
	var calc = _reinf_log_calc()
	var tag := str(f.country_tag).strip_edges().to_upper() if "country_tag" in f else ""
	var policy := str(opts.get("policy_id", get_country_training_policy(tag)))
	var old_xp := 48.0
	if "combat_experience" in f:
		old_xp = float(f.combat_experience)
	var old_str := float(f.strength) if "strength" in f else 1.0
	var recruit_xp := 30.0
	if calc != null and calc.has_method("recruit_xp_for_policy"):
		recruit_xp = float(calc.recruit_xp_for_policy(policy))
	if opts.has("recruit_xp"):
		recruit_xp = float(opts["recruit_xp"])
	var hub := float(opts.get("hub_access", 1.0))
	var org_v := float(f.organization) if "organization" in f else 1.0
	var cap := 0.05
	if calc != null and calc.has_method("daily_strength_absorb_cap"):
		cap = float(calc.daily_strength_absorb_cap(hub, policy, org_v))
	if bool(opts.get("force_full", false)):
		cap = clampf(absf(strength_target_delta), 0.0, 1.0)
	var delta := clampf(strength_target_delta, 0.0, cap)
	if bool(opts.get("force_full", false)):
		delta = clampf(strength_target_delta, 0.0, 1.0 - old_str + 0.001)
	var new_str := clampf(old_str + delta, 0.35, 1.0)
	var actual := new_str - old_str
	if actual <= 0.0001:
		return {"ok": false, "error": "no_room", "strength": old_str, "combat_experience": old_xp}
	var frac := actual / maxf(new_str, 0.05)
	var new_xp := old_xp
	if calc != null and calc.has_method("blend_combat_experience_manpower"):
		new_xp = float(calc.blend_combat_experience_manpower(old_xp, recruit_xp, frac))
	else:
		new_xp = clampf((1.0 - frac) * old_xp + frac * recruit_xp, 0.0, 100.0)
	f.strength = new_str
	if "combat_experience" in f:
		f.combat_experience = new_xp
	var plain := ""
	if calc != null and calc.has_method("attribution_plain_xp_dilution"):
		plain = str(calc.attribution_plain_xp_dilution(old_xp, new_xp, formation_id))
	return {
		"ok": true,
		"formation_id": formation_id,
		"strength_before": old_str,
		"strength_after": new_str,
		"strength_added": actual,
		"fraction_replaced": frac,
		"combat_experience_before": old_xp,
		"combat_experience_after": new_xp,
		"recruit_xp": recruit_xp,
		"policy_id": policy,
		"plain": plain,
		"model": "reinforce_experience_logistics_ledger",
	}


## Equipment rearm XP friction — much smaller than manpower (RF1 asymmetry).
func apply_equipment_rearm_experience(
	formation_id: String,
	rearm_fraction: float = 0.2,
	novelty: float = 0.35,
) -> Dictionary:
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formation"):
		return {"ok": false, "error": "no_leader_manager"}
	var f = LeaderManager.get_formation(formation_id)
	if f == null:
		return {"ok": false, "error": "no_formation"}
	var calc = _reinf_log_calc()
	var old_xp := 48.0
	if "combat_experience" in f:
		old_xp = float(f.combat_experience)
	var new_xp := old_xp
	if calc != null and calc.has_method("blend_combat_experience_rearm"):
		new_xp = float(calc.blend_combat_experience_rearm(old_xp, rearm_fraction, novelty))
	else:
		new_xp = clampf(old_xp - 8.0 * clampf(rearm_fraction, 0.0, 1.0) * clampf(novelty, 0.0, 1.0), 0.0, 100.0)
	if "combat_experience" in f:
		f.combat_experience = new_xp
	return {
		"ok": true,
		"formation_id": formation_id,
		"combat_experience_before": old_xp,
		"combat_experience_after": new_xp,
		"rearm_fraction": rearm_fraction,
		"novelty": novelty,
		"model": "reinforce_experience_logistics_ledger",
	}


func get_formation_combat_experience(formation_id: String) -> float:
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formation"):
		return 48.0
	var f = LeaderManager.get_formation(formation_id)
	if f == null:
		return 48.0
	if "combat_experience" in f:
		return float(f.combat_experience)
	return 48.0


func set_formation_combat_experience(formation_id: String, xp: float) -> void:
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formation"):
		return
	var f = LeaderManager.get_formation(formation_id)
	if f == null:
		return
	if "combat_experience" in f:
		f.combat_experience = clampf(xp, 0.0, 100.0)


func reset_equipment_flows() -> void:
	_equipment_flows.clear()
	_equipment_flow_seq = 0


func create_equipment_flow(
	country_tag: String,
	equipment_id: String,
	amount: int,
	from_province: int = 0,
	to_province: int = 0,
	to_unit_id: String = "",
	mode: String = "rail",
	opts: Dictionary = {},
) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var eid := equipment_id.strip_edges()
	var amt := maxi(0, amount)
	if tag.is_empty() or eid.is_empty() or amt <= 0:
		return {"ok": false, "error": "bad_args"}
	# Pull from country stockpile (in-transit reservation)
	var available := get_country_equipment_amount(tag, eid)
	if available < amt and not bool(opts.get("allow_overdraw", false)):
		if available <= 0:
			return {"ok": false, "error": "insufficient_stock", "have": available, "need": amt}
		amt = available
	var taken := take_from_country_equipment_stockpile(tag, eid, amt)
	if taken <= 0:
		return {"ok": false, "error": "stock_take_failed"}
	amt = taken
	var calc = _equip_flow_calc()
	var mode_n := "rail"
	var risk := 0.08
	var symbol := "train"
	var days := 1.0
	var hops := int(opts.get("hops", 1))
	if calc != null:
		if calc.has_method("normalize_mode"):
			mode_n = str(calc.normalize_mode(mode))
		if calc.has_method("base_corridor_risk"):
			risk = float(calc.base_corridor_risk(mode_n))
		if calc.has_method("symbol_for_mode"):
			symbol = str(calc.symbol_for_mode(mode_n))
		if calc.has_method("transit_days"):
			days = float(calc.transit_days(mode_n, hops))
	# RF1: hub distance / era / resources stretch EquipmentFlow clock (non-instant reinforce).
	if opts.has("distance_km") or opts.has("year") or opts.has("depot_fill"):
		var est: Dictionary = estimate_reinforce_transit_days(
			mode_n, hops, float(opts.get("distance_km", 0.0)), int(opts.get("year", 1939)), opts,
		)
		if bool(est.get("ok", false)):
			days = float(est.get("days", days))
	if opts.has("corridor_risk"):
		risk = clampf(float(opts["corridor_risk"]), 0.0, 1.0)
	_equipment_flow_seq += 1
	var fid := "eflow_%s_%d" % [tag.to_lower(), _equipment_flow_seq]
	var flow := {
		"flow_id": fid,
		"country_tag": tag,
		"equipment_id": eid,
		"amount": amt,
		"amount_remaining": amt,
		"from_province": from_province,
		"to_province": to_province,
		"to_unit_id": to_unit_id.strip_edges(),
		"mode": mode_n,
		"symbol": symbol,
		"corridor_risk": risk,
		"escort": bool(opts.get("escort", false)),
		"days_total": days,
		"days_left": days,
		"active": true,
		"delivered": 0,
		"lost": 0,
		"path": (opts.get("path", []) as Array).duplicate() if opts.get("path") is Array else [],
		"model": "equipment_flow_compact_ledger",
	}
	_equipment_flows[fid] = flow
	equipment_flow_created.emit(fid, eid, amt, mode_n)
	return {"ok": true, "flow": flow.duplicate(true), "flow_id": fid}


func get_equipment_flow(flow_id: String) -> Dictionary:
	if not _equipment_flows.has(flow_id):
		return {}
	return (_equipment_flows[flow_id] as Dictionary).duplicate(true)


func get_active_equipment_flows(country_tag: String = "") -> Array:
	var tag := country_tag.strip_edges().to_upper()
	var out: Array = []
	for fid in _equipment_flows.keys():
		var f: Dictionary = _equipment_flows[fid] as Dictionary
		if not bool(f.get("active", false)):
			continue
		if not tag.is_empty() and str(f.get("country_tag", "")) != tag:
			continue
		out.append(f.duplicate(true))
	return out


func interdict_equipment_flow(flow_id: String, cause: String, loss_fraction: float = 0.4, opts: Dictionary = {}) -> Dictionary:
	if not _equipment_flows.has(flow_id):
		return {"ok": false, "error": "unknown_flow"}
	var f: Dictionary = (_equipment_flows[flow_id] as Dictionary).duplicate(true)
	if not bool(f.get("active", false)):
		return {"ok": false, "error": "inactive"}
	var calc = _equip_flow_calc()
	var risk := float(f.get("corridor_risk", 0.1))
	var escorted := bool(f.get("escort", false))
	var effective := clampf(loss_fraction, 0.05, 0.95)
	if calc != null and calc.has_method("effective_interdict_loss"):
		effective = float(calc.effective_interdict_loss(loss_fraction, risk, escorted))
	var amt := int(f.get("amount_remaining", f.get("amount", 0)))
	var split: Dictionary = {"lost": 0, "delivered": amt}
	if calc != null and calc.has_method("amount_after_interdict"):
		split = calc.amount_after_interdict(amt, effective) as Dictionary
	else:
		var lost_i := int(floor(float(amt) * effective))
		split = {"lost": lost_i, "delivered": maxi(0, amt - lost_i)}
	var lost := int(split.get("lost", 0))
	var remaining := int(split.get("delivered", amt))
	f["lost"] = int(f.get("lost", 0)) + lost
	f["amount_remaining"] = remaining
	var plain := ""
	if calc != null and calc.has_method("attribution_plain"):
		plain = str(calc.attribution_plain(
			cause, str(f.get("mode", "rail")), str(f.get("equipment_id", "")),
			str(f.get("from_province", 0)), str(f.get("to_unit_id", f.get("to_province", 0))),
			lost, amt,
		))
	else:
		plain = "EquipmentFlow interdicted (%s): lost %d" % [cause, lost]
	if not f.get("metadata") is Dictionary:
		f["metadata"] = {}
	var md: Dictionary = f["metadata"] as Dictionary
	if not md.has("interdiction_history"):
		md["interdiction_history"] = []
	(md["interdiction_history"] as Array).append({
		"cause": cause, "loss": effective, "lost": lost, "plain": plain,
	})
	md["last_interdiction_plain"] = plain
	f["metadata"] = md
	if remaining <= 0:
		f["active"] = false
		f["amount_remaining"] = 0
	_equipment_flows[flow_id] = f
	equipment_flow_interdicted.emit(flow_id, cause, lost, remaining)
	return {
		"ok": true, "flow_id": flow_id, "lost": lost, "remaining": remaining,
		"effective_loss": effective, "plain": plain, "flow": f.duplicate(true),
	}


func advance_equipment_flows(days: float = 1.0) -> Dictionary:
	var report := {"advanced": 0, "delivered_n": 0, "delivered_amount": 0, "events": []}
	var d := maxf(0.0, days)
	for fid in _equipment_flows.keys():
		var f: Dictionary = (_equipment_flows[fid] as Dictionary).duplicate(true)
		if not bool(f.get("active", false)):
			continue
		report["advanced"] = int(report["advanced"]) + 1
		f["days_left"] = float(f.get("days_left", 1.0)) - d
		if float(f["days_left"]) > 0.001:
			_equipment_flows[fid] = f
			continue
		# Deliver remaining to unit or country stockpile at destination
		var amt := int(f.get("amount_remaining", 0))
		var tag := str(f.get("country_tag", ""))
		var eid := str(f.get("equipment_id", ""))
		var unit_id := str(f.get("to_unit_id", ""))
		if amt > 0:
			if not unit_id.is_empty():
				var cur := get_unit_equipment_stock(unit_id)
				cur[eid] = int(cur.get(eid, 0)) + amt
				set_unit_equipment_stock(unit_id, cur)
				unit_reinforced.emit(unit_id, {eid: int(cur[eid])})
			else:
				add_to_country_equipment_stockpile(tag, eid, amt)
			f["delivered"] = int(f.get("delivered", 0)) + amt
			report["delivered_n"] = int(report["delivered_n"]) + 1
			report["delivered_amount"] = int(report["delivered_amount"]) + amt
			(report["events"] as Array).append({
				"flow_id": fid, "equipment_id": eid, "amount": amt,
				"to_unit_id": unit_id, "symbol": f.get("symbol", ""),
			})
			equipment_flow_delivered.emit(fid, eid, amt, unit_id)
		f["amount_remaining"] = 0
		f["active"] = false
		f["days_left"] = 0.0
		_equipment_flows[fid] = f
	report["ok"] = true
	report["model"] = "equipment_flow_compact_ledger"
	return report


func get_equipment_flow_board(country_tag: String = "") -> Dictionary:
	var active := get_active_equipment_flows(country_tag)
	var by_symbol: Dictionary = {}
	var by_mode: Dictionary = {}
	var glyphs: Array = []
	for f in active:
		if not (f is Dictionary):
			continue
		var fd: Dictionary = f as Dictionary
		var sym := str(fd.get("symbol", "train"))
		var mode := str(fd.get("mode", "rail"))
		by_symbol[sym] = int(by_symbol.get(sym, 0)) + 1
		by_mode[mode] = int(by_mode.get(mode, 0)) + 1
		glyphs.append({
			"flow_id": str(fd.get("flow_id", "")),
			"symbol": sym,
			"mode": mode,
			"from_province": int(fd.get("from_province", 0)),
			"to_province": int(fd.get("to_province", 0)),
			"to_unit_id": str(fd.get("to_unit_id", "")),
			"amount_remaining": int(fd.get("amount_remaining", 0)),
			"days_left": float(fd.get("days_left", 0.0)),
			"equipment_id": str(fd.get("equipment_id", "")),
		})
	return {
		"ok": true,
		"active_n": active.size(),
		"flows": active,
		"symbols": by_symbol,
		"by_mode": by_mode,
		"glyphs": glyphs,
		"model": "equipment_flow_compact_ledger",
	}


## CP3: player-facing map symbol strip for active EquipmentFlows (story glyphs, not every vehicle).
## CP4: consume munitions/drone stock for a fire mission or sortie (burns country stockpile).
func consume_munitions_from_stockpile(
	country_tag: String,
	equipment_id: String,
	volleys: int = 1,
	intensity: float = 1.0,
	opts: Dictionary = {},
) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var eid := equipment_id.strip_edges()
	if tag.is_empty() or eid.is_empty():
		return {"ok": false, "error": "bad_args", "consumed": 0}
	var dclass := str(opts.get("design_class", ""))
	if dclass.is_empty():
		dclass = resolve_design_class_for_stock(eid)
	var calc = _equip_flow_calc()
	var need := maxi(1, volleys)
	if calc != null and calc.has_method("munitions_consume_amount"):
		need = int(calc.munitions_consume_amount(dclass, volleys, intensity))
	var have := get_country_equipment_amount(tag, eid)
	var taken := take_from_country_equipment_stockpile(tag, eid, need)
	var ok := taken > 0
	var short := need - taken
	return {
		"ok": ok,
		"country_tag": tag,
		"equipment_id": eid,
		"design_class": dclass,
		"needed": need,
		"consumed": taken,
		"short": maxi(0, short),
		"have_before": have,
		"have_after": get_country_equipment_amount(tag, eid),
		"model": "equipment_flow_compact_ledger",
	}


## RF5: player plain stories — XP dilution, transit, flow symbols, policy.
func format_reinforce_story_plain(country_tag: String = "USA", opts: Dictionary = {}) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = "USA"
	var lines: PackedStringArray = []
	var policy := get_country_training_policy(tag)
	var calc = _reinf_log_calc()
	var recruit_xp := 38.0
	if calc != null and calc.has_method("recruit_xp_for_policy"):
		recruit_xp = float(calc.recruit_xp_for_policy(policy))
	lines.append("Training policy: %s (recruit XP ~%.0f)." % [policy, recruit_xp])
	# Transit estimate
	var year := int(opts.get("year", 1939))
	var tech_flags: Dictionary = {}
	if opts.get("tech_flags") is Dictionary:
		tech_flags = opts.get("tech_flags") as Dictionary
	var mode := str(opts.get("mode", ""))
	if mode.is_empty():
		mode = preferred_reinforce_mode(year, tech_flags)
	var dist := float(opts.get("distance_km", 400.0))
	var est: Dictionary = estimate_reinforce_transit_days(mode, int(opts.get("hops", 2)), dist, year, opts)
	if bool(est.get("ok", false)):
		lines.append(str(est.get("plain", "Transit ~%.1f days via %s." % [float(est.get("days", 1)), mode])))
	# Active flows strip
	var strip: Dictionary = format_equipment_flow_map_strip(tag)
	if int(strip.get("active_n", 0)) > 0:
		lines.append(str(strip.get("plain", "")))
	else:
		lines.append("No equipment flows en route.")
	# Formation XP sample
	var xp_line := "No formation XP sample."
	if typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
		for k in LeaderManager.formations.keys():
			var f = LeaderManager.formations[k]
			if f == null:
				continue
			var ftag := str(f.country_tag).to_upper() if "country_tag" in f else ""
			if not ftag.is_empty() and ftag != tag:
				continue
			var xp := float(f.combat_experience) if "combat_experience" in f else 48.0
			var band := "regular"
			if calc != null and calc.has_method("experience_band"):
				band = str(calc.experience_band(xp))
			var name_s := str(f.name) if "name" in f else str(k)
			xp_line = "%s combat experience: %s (%.0f)." % [name_s, band, xp]
			break
	lines.append(xp_line)
	var plain := " ".join(lines)
	return {
		"ok": not plain.is_empty(),
		"plain": plain,
		"lines": Array(lines),
		"policy_id": policy,
		"recruit_xp": recruit_xp,
		"transit": est,
		"strip": strip,
		"model": "reinforce_experience_logistics_ledger",
	}


func format_equipment_flow_map_strip(country_tag: String = "") -> Dictionary:
	var board: Dictionary = get_equipment_flow_board(country_tag)
	var glyphs: Array = board.get("glyphs", []) if board.get("glyphs") is Array else []
	var symbols: Dictionary = board.get("symbols", {}) if board.get("symbols") is Dictionary else {}
	var parts: PackedStringArray = []
	for sym in symbols.keys():
		parts.append("%s×%d" % [str(sym), int(symbols[sym])])
	var plain := "No active equipment movements."
	if parts.size() > 0:
		plain = "Map flow symbols: %s (%d active)." % [", ".join(parts), int(board.get("active_n", 0))]
	elif glyphs.size() > 0:
		plain = "Map flow symbols: %d glyph(s) en route." % glyphs.size()
	# Sample attribution from first glyph
	if glyphs.size() > 0 and glyphs[0] is Dictionary:
		var g0: Dictionary = glyphs[0] as Dictionary
		plain += " e.g. %s %s → %s (%s, %.1fd left)." % [
			str(g0.get("symbol", "train")),
			str(g0.get("from_province", 0)),
			str(g0.get("to_unit_id", g0.get("to_province", 0))),
			str(g0.get("equipment_id", "")),
			float(g0.get("days_left", 0.0)),
		]
	return {
		"ok": true,
		"symbols_ok": true,
		"plain": plain,
		"glyphs": glyphs,
		"symbols": symbols,
		"active_n": int(board.get("active_n", 0)),
		"model": "equipment_flow_compact_ledger",
	}


## CP2 helper: stock → flow → (optional force deliver) → unit reinforce.
## opts.force_deliver (default true): advance full transit so unit receives now.
## opts.force_deliver=false: leave flow in transit for daily advance_equipment_flows.
func ship_and_reinforce_unit(
	country_tag: String,
	unit_id: String,
	equipment_id: String,
	amount: int,
	mode: String = "rail",
	opts: Dictionary = {},
) -> Dictionary:
	var created: Dictionary = create_equipment_flow(
		country_tag, equipment_id, amount, int(opts.get("from_province", 0)),
		int(opts.get("to_province", 0)), unit_id, mode, opts,
	)
	if not bool(created.get("ok", false)):
		return created
	var fid := str(created.get("flow_id", ""))
	if bool(opts.get("force_interdict", false)):
		interdict_equipment_flow(fid, str(opts.get("interdict_cause", "partisan")), float(opts.get("loss", 0.4)))
	var adv: Dictionary = {"advanced": 0, "delivered_n": 0, "delivered_amount": 0, "events": [], "skipped": true}
	var force_deliver := true if not opts.has("force_deliver") else bool(opts.get("force_deliver", true))
	if force_deliver:
		var days := 99.0
		if created.get("flow") is Dictionary:
			days = float((created["flow"] as Dictionary).get("days_total", 1.0)) + 0.01
		adv = advance_equipment_flows(days)
	var on_hand := get_unit_equipment_stock(unit_id)
	return {
		"ok": true,
		"create": created,
		"advance": adv,
		"unit_stock": on_hand.duplicate(true),
		"received": int(on_hand.get(equipment_id, 0)),
		"in_transit": not force_deliver,
		"flow_id": fid,
		"model": "equipment_flow_compact_ledger",
	}


## --- CP2: complete → stockpile (batch scale) + demand reinforce via flow ------

## Infer design class for hybrid batch scale (identity-weighted freeze §3).
func resolve_design_class_for_stock(design_id: String) -> String:
	var did := design_id.strip_edges()
	if did.is_empty():
		return "generic"
	var cat := ""
	if typeof(GameData) != TYPE_NIL and GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(did)
		if template != null:
			if "is_drone_swarm" in template and bool(template.is_drone_swarm):
				return "drone_swarm"
			if not str(template.production_category).is_empty():
				cat = str(template.production_category).strip_edges().to_lower()
			elif template.has_method("get_inferred_production_category"):
				cat = str(template.get_inferred_production_category()).strip_edges().to_lower()
	if cat.is_empty():
		var id_lower := did.to_lower()
		if "truck" in id_lower or "transport" in id_lower or "cargo" in id_lower:
			cat = "truck"
		elif "apc" in id_lower or "ifv" in id_lower:
			cat = "apc"
		elif "drone" in id_lower and ("swarm" in id_lower or "loiter" in id_lower or "is_drone" in id_lower):
			cat = "drone_swarm"
		elif "missile" in id_lower or ("rocket" in id_lower and "artillery" not in id_lower):
			cat = "missile"
		elif "rocket" in id_lower and "artillery" in id_lower:
			cat = "rocket_artillery"
		elif "towed" in id_lower and "artillery" in id_lower:
			cat = "artillery_towed"
		else:
			cat = "generic"
	# Map production categories onto freeze class keys (CP4 munitions/drone).
	match cat:
		"light_vehicle", "vehicle", "transport":
			return "truck"
		"mbt", "tank", "armor":
			return "tank"
		"fighter", "bomber", "attack_aircraft", "aircraft":
			return "fighter"
		"drone", "uav", "drone_system":
			return "drone_swarm"
		"missile", "missile_system", "ballistic_missile", "cruise_missile", "tactical_missile", "strategic_missile":
			return "missile"
		"munition", "munitions", "shell", "ammo_stock":
			return "munition"
		_:
			return cat


func resolve_batch_size_for_design(design_id: String) -> int:
	var did := design_id.strip_edges()
	if did.is_empty():
		return -1
	if typeof(GameData) != TYPE_NIL and GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(did)
		if template != null:
			var raw: Variant = template.get("batch_size")
			if raw != null and int(raw) >= 1:
				return int(raw)
	return -1


func resolve_stock_units_on_complete(design_id: String, completes: int = 1) -> int:
	var c := maxi(0, completes)
	var calc = _equip_flow_calc()
	var dclass := resolve_design_class_for_stock(design_id)
	var batch := resolve_batch_size_for_design(design_id)
	if calc != null and calc.has_method("stock_units_on_complete"):
		return int(calc.stock_units_on_complete(dclass, c, batch))
	if batch >= 1:
		return c * batch
	return c


## Always credit country equipment stockpile on line complete (CP2 P4).
## opts: design_class, batch_size, to_unit_id, mode, auto_flow (bool), from/to_province
func credit_production_complete_to_stockpile(
	country_tag: String,
	design_id: String,
	completes: int = 1,
	opts: Dictionary = {},
) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var eid := design_id.strip_edges()
	if tag.is_empty() or eid.is_empty() or completes <= 0:
		return {"ok": false, "error": "bad_args", "stock_units": 0}
	var dclass := str(opts.get("design_class", ""))
	if dclass.is_empty():
		dclass = resolve_design_class_for_stock(eid)
	var batch := int(opts.get("batch_size", -1))
	if batch < 1:
		batch = resolve_batch_size_for_design(eid)
	var units := completes
	var calc = _equip_flow_calc()
	if calc != null and calc.has_method("stock_units_on_complete"):
		units = int(calc.stock_units_on_complete(dclass, completes, batch))
	elif batch >= 1:
		units = completes * batch
	eid = resolve_toe_equipment_id(eid)
	var before := get_country_equipment_amount(tag, eid)
	add_to_country_equipment_stockpile(tag, eid, units)
	var after := get_country_equipment_amount(tag, eid)
	var flow_res: Dictionary = {}
	var auto_flow := bool(opts.get("auto_flow", false))
	var to_unit := str(opts.get("to_unit_id", "")).strip_edges()
	if auto_flow and not to_unit.is_empty() and units > 0:
		var ship_amt := int(opts.get("flow_amount", units))
		ship_amt = mini(ship_amt, units)
		flow_res = create_equipment_flow(
			tag, eid, ship_amt,
			int(opts.get("from_province", 0)),
			int(opts.get("to_province", 0)),
			to_unit,
			str(opts.get("mode", "rail")),
			opts,
		)
	return {
		"ok": after == before + units and units > 0,
		"country_tag": tag,
		"equipment_id": eid,
		"completes": completes,
		"design_class": dclass,
		"stock_units": units,
		"before": before,
		"after": after,
		"flow": flow_res,
		"model": "equipment_flow_compact_ledger",
	}


func equipment_demand_deficit(unit_id: String, required_equipment: Dictionary) -> Dictionary:
	var current := get_unit_equipment_stock(unit_id)
	var deficit: Dictionary = {}
	var total := 0
	for eid in required_equipment.keys():
		var need := int(required_equipment[eid])
		var have := int(current.get(eid, 0))
		var gap := maxi(0, need - have)
		if gap > 0:
			deficit[str(eid)] = gap
			total += gap
	return {"unit_id": unit_id, "deficit": deficit, "total": total, "ok": true}


## CP2 demand path: ship TOE deficit (need − on-hand) via EquipmentFlow.
## amount: absolute TOE need (≥0). If <0, uses formation required or opts.need.
## opts.as_ship_amount=true: treat amount as exact ship qty (skip deficit math).
func demand_reinforce_via_equipment_flow(
	country_tag: String,
	unit_id: String,
	equipment_id: String,
	amount: int = -1,
	mode: String = "rail",
	opts: Dictionary = {},
) -> Dictionary:
	var eid := equipment_id.strip_edges()
	var need := amount
	if need < 0:
		var req_map: Dictionary = get_formation_required_equipment(unit_id)
		if req_map.has(eid):
			need = int(req_map[eid])
		else:
			need = maxi(1, int(opts.get("need", 1)))
	var gap := maxi(0, need)
	if not bool(opts.get("as_ship_amount", false)):
		var have := int(get_unit_equipment_stock(unit_id).get(eid, 0))
		gap = maxi(0, need - have)
	if gap <= 0:
		return {"ok": false, "error": "no_deficit", "received": 0, "gap": 0, "need": need}
	var ship_opts := opts.duplicate(true)
	var res: Dictionary = ship_and_reinforce_unit(country_tag, unit_id, eid, gap, mode, ship_opts)
	res["gap"] = gap
	res["need"] = need
	res["demand"] = true
	return res


## Priority-first demand reinforce tick via EquipmentFlow (CP2).
## required_map: unit_id -> { equipment_id: need_count }
func demand_reinforce_tick_via_flow(required_map: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var report := {
		"ok": true,
		"units": {},
		"shipped_n": 0,
		"received_total": 0,
		"model": "equipment_flow_compact_ledger",
	}
	if required_map.is_empty():
		return report
	var mode := str(opts.get("mode", "rail"))
	var order: Array = []
	for unit_id in priority_reinforcement_units.keys():
		if required_map.has(unit_id) and is_unit_priority_reinforced(str(unit_id)):
			order.append(str(unit_id))
	for unit_id in required_map.keys():
		var uid := str(unit_id)
		if not order.has(uid):
			order.append(uid)
	for unit_id in order:
		var req: Variant = required_map[unit_id]
		if typeof(req) != TYPE_DICTIONARY:
			continue
		var tag := str(opts.get("country_tag", "")).strip_edges().to_upper()
		if tag.is_empty() and typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
			var f = LeaderManager.formations.get(unit_id) if LeaderManager.formations is Dictionary else null
			if f != null and "country_tag" in f:
				tag = str(f.country_tag).strip_edges().to_upper()
		if tag.is_empty():
			tag = str((req as Dictionary).get("_country_tag", "USA")).to_upper()
		var unit_report: Dictionary = {}
		for eid in (req as Dictionary).keys():
			if str(eid).begins_with("_"):
				continue
			var need := int((req as Dictionary)[eid])
			var ship_opts := opts.duplicate(true)
			ship_opts["as_deficit"] = true
			# When force_deliver (default true for dual), advance full transit immediately.
			if not ship_opts.has("force_deliver"):
				ship_opts["force_deliver"] = true
			var ship: Dictionary = demand_reinforce_via_equipment_flow(
				tag, str(unit_id), str(eid), need, mode, ship_opts,
			)
			unit_report[str(eid)] = ship
			if bool(ship.get("ok", false)):
				report["shipped_n"] = int(report["shipped_n"]) + 1
				report["received_total"] = int(report["received_total"]) + int(ship.get("received", 0))
		report["units"][str(unit_id)] = unit_report
	# ok when at least one ship succeeded, or nothing needed (no deficit path is still healthy)
	report["ok"] = int(report["shipped_n"]) > 0 or order.is_empty()
	return report


func get_country_equipment_amount(country_tag: String, equipment_id: String) -> int:
	var tag := country_tag.strip_edges().to_upper()
	var eid := equipment_id.strip_edges()
	if not country_equipment_stockpiles.has(tag):
		return 0
	return int((country_equipment_stockpiles[tag] as Dictionary).get(eid, 0))


const TOE_RESOURCE_COST := {
	"infantry_equipment": {"steel": 1.0, "coal": 1.0},
	"trucks": {"steel": 2.0, "rubber": 1.0, "oil": 1.0},
	"tanks": {"steel": 4.0, "oil": 1.0, "chromium": 1.0},
	"artillery": {"steel": 3.0, "tungsten": 1.0},
	"motorcycles": {"steel": 1.0, "rubber": 1.0},
	"halftracks": {"steel": 3.0, "rubber": 1.0, "oil": 1.0},
	"recon_equipment": {"steel": 1.0},
	"support_equipment": {"steel": 1.0},
	"anti_tank": {"steel": 2.0, "tungsten": 1.0},
	"anti_air": {"steel": 2.0, "aluminum": 1.0},
}


func resolve_toe_equipment_id(raw: String) -> String:
	var key := raw.strip_edges().to_lower()
	if TOE_RESOURCE_COST.has(key):
		return key
	match key:
		"truck", "motorized":
			return "trucks"
		"tank", "armor":
			return "tanks"
		"gun", "guns":
			return "artillery"
		"rifle", "rifles", "infantry":
			return "infantry_equipment"
		"motorcycle":
			return "motorcycles"
		"halftrack", "half-track":
			return "halftracks"
		"recon":
			return "recon_equipment"
		"engineer":
			return "support_equipment"
		"at":
			return "anti_tank"
		"aa":
			return "anti_air"
		_:
			return raw.strip_edges()


func toe_resource_cost(equipment_id: String, count: int = 1) -> Dictionary:
	var key := resolve_toe_equipment_id(equipment_id)
	var n := maxi(0, count)
	var base: Dictionary = TOE_RESOURCE_COST.get(key, {"steel": 1.0}) as Dictionary
	var out: Dictionary = {}
	for r in base.keys():
		out[str(r)] = float(base[r]) * float(n)
	return out


func get_formation_toe(formation_id: String) -> Dictionary:
	if formation_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return {}
	var f: Formation = LeaderManager.get_formation(formation_id) if LeaderManager.has_method("get_formation") else null
	if f == null:
		return {}
	return LandCombatPower.equipment_toe(LandCombatPower.composition_from_formation(f))


func unit_toe_fill_ratio(formation_id: String) -> float:
	var toe: Dictionary = get_formation_toe(formation_id)
	if toe.is_empty():
		return 1.0
	var have_stock: Dictionary = get_unit_equipment_stock(formation_id)
	var need := 0
	var have := 0
	for k in toe.keys():
		var n := int(toe[k])
		if n <= 0:
			continue
		need += n
		have += mini(n, maxi(0, int(have_stock.get(k, 0))))
	if need <= 0:
		return 1.0
	return float(have) / float(need)


func produce_toe_equipment(country_tag: String, equipment_id: String, count: int = 1) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var key := resolve_toe_equipment_id(equipment_id)
	var n := maxi(0, count)
	var before := get_country_equipment_amount(tag, key)
	if tag.is_empty() or key.is_empty() or n <= 0:
		return {"ok": false, "error": "bad_args", "added": 0, "stock_after": before, "equipment_id": key}
	var cost: Dictionary = toe_resource_cost(key, n)
	if not can_afford(cost):
		return {
			"ok": false,
			"error": "no_resources",
			"added": 0,
			"stock_after": before,
			"equipment_id": key,
			"cost": cost,
		}
	if not pay_cost(cost):
		return {"ok": false, "error": "pay_failed", "added": 0, "stock_after": before, "equipment_id": key}
	var credit: Dictionary = credit_production_complete_to_stockpile(tag, key, n, {"batch_size": 1, "design_class": key})
	return {
		"ok": bool(credit.get("ok", false)),
		"equipment_id": key,
		"added": int(credit.get("stock_units", 0)),
		"stock_before": before,
		"stock_after": int(credit.get("after", before)),
		"resources_paid": cost,
		"credit": credit,
	}


func reinforce_unit_toe_from_stockpile(formation_id: String, share: float = -1.0) -> Dictionary:
	var fid := formation_id.strip_edges()
	var toe: Dictionary = get_formation_toe(fid)
	var fill_before := unit_toe_fill_ratio(fid)
	if fid.is_empty() or toe.is_empty():
		return {"ok": false, "moved": {}, "fill_before": fill_before, "fill_after": fill_before, "error": "no_toe"}
	var sh := share
	if sh < 0.0:
		sh = 1.0
		if typeof(LeaderManager) != TYPE_NIL:
			var f: Formation = LeaderManager.get_formation(fid) if LeaderManager.has_method("get_formation") else null
			var training := f != null and "is_training" in f and bool(f.is_training)
			if LeaderManager.has_method("organize_equip_share"):
				sh = float(LeaderManager.organize_equip_share(training))
	sh = clampf(sh, 0.0, 1.0)
	var required: Dictionary = {}
	var have_stock: Dictionary = get_unit_equipment_stock(fid)
	for k in toe.keys():
		var need := int(toe[k])
		if need <= 0:
			continue
		var have := int(have_stock.get(k, 0))
		var gap := need - have
		if gap <= 0:
			continue
		var want := maxi(1, int(ceil(float(gap) * 0.25 * sh)))
		want = mini(want, gap)
		required[str(k)] = have + want
	var fulfilled: Dictionary = {}
	if not required.is_empty():
		fulfilled = auto_reinforce_unit_from_stockpile(fid, required)
	var fill_after := unit_toe_fill_ratio(fid)
	if fill_after > fill_before + 0.001 and typeof(LeaderManager) != TYPE_NIL:
		var form: Formation = LeaderManager.get_formation(fid) if LeaderManager.has_method("get_formation") else null
		if form != null and "strength" in form and float(form.strength) < 0.99:
			var gain := clampf((fill_after - fill_before) * 0.4, 0.0, 0.08)
			form.strength = clampf(float(form.strength) + gain, 0.0, 1.0)
	return {
		"ok": true,
		"moved": fulfilled,
		"fill_before": fill_before,
		"fill_after": fill_after,
		"share": sh,
	}


## Shipped recovery path: land formations pull missing design equipment from country stockpile,
## then slowly recover strength when equipped (combat losses → stockpile as repair pool).
func daily_formation_reinforce_from_stockpile() -> Dictionary:
	var report := {
		"units_reinforced": 0,
		"equipment_moved": 0,
		"strength_recovered": 0,
		"by_tag": {},
	}
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return report
	var formations: Array = []
	for fid in LeaderManager.formations:
		var ff = LeaderManager.formations[fid]
		if ff != null:
			formations.append(ff)
	for f in formations:
		if f == null:
			continue
		var ftype := str(f.formation_type) if "formation_type" in f else ""
		if ftype != Formation.TYPE_DIVISION and ftype != Formation.TYPE_GARRISON:
			continue
		var fid := str(f.formation_id) if "formation_id" in f else ""
		if fid.is_empty():
			continue
		var tag := str(f.country_tag).strip_edges().to_upper() if "country_tag" in f else ""
		# Composition TOE: share-capped (never dump full TOE on the day tick).
		var toe_rep: Dictionary = reinforce_unit_toe_from_stockpile(fid)
		if float(toe_rep.get("fill_after", 0.0)) > float(toe_rep.get("fill_before", 0.0)) + 0.001:
			report["units_reinforced"] = int(report["units_reinforced"]) + 1
			var moved_toe: Dictionary = toe_rep.get("moved", {}) as Dictionary
			for mk in moved_toe.keys():
				report["equipment_moved"] = int(report["equipment_moved"]) + int(moved_toe[mk])
		# Legacy factory/OOB path: 1× design_id from country stockpile.
		var required: Dictionary = get_formation_required_equipment(fid)
		if required.is_empty():
			continue
		var design := str(required.keys()[0]) if not required.is_empty() else ""
		var before_country := 0
		if not tag.is_empty() and not design.is_empty():
			before_country = int(get_country_equipment_stockpile(tag).get(design, 0))
		var fulfilled: Dictionary = auto_reinforce_unit_from_stockpile(fid, required)
		var after_country := before_country
		if not tag.is_empty() and not design.is_empty():
			after_country = int(get_country_equipment_stockpile(tag).get(design, 0))
		var taken := before_country - after_country
		if taken > 0:
			report["equipment_moved"] = int(report["equipment_moved"]) + taken
			report["units_reinforced"] = int(report["units_reinforced"]) + 1
			if not tag.is_empty():
				var bt: Dictionary = report["by_tag"]
				bt[tag] = int(bt.get(tag, 0)) + taken
		# Strength recovery when unit has on-hand equipment (stockpile paid the rebuild).
		# RF1: partial absorb + experience dilution (greens are not instant veterans).
		var on_hand := get_unit_equipment_stock(fid)
		var has_eq := false
		for k in on_hand.keys():
			if int(on_hand[k]) > 0:
				has_eq = true
				break
		if has_eq and "strength" in f and float(f.strength) < 0.99:
			var old_s := float(f.strength)
			var want := 0.05
			# Extra stockpile pull when heavily damaged (rebuild costs equipment).
			if old_s < 0.75 and not design.is_empty() and not tag.is_empty():
				var rebuild := take_from_country_equipment_stockpile(tag, design, 1)
				if rebuild > 0:
					report["equipment_moved"] = int(report["equipment_moved"]) + rebuild
					want = 0.08
					apply_equipment_rearm_experience(fid, 0.12, 0.25)
			var man: Dictionary = apply_manpower_reinforce_with_experience(fid, want, {
				"policy_id": get_country_training_policy(tag),
				"hub_access": 1.0,
			})
			if bool(man.get("ok", false)):
				report["strength_recovered"] = int(report["strength_recovered"]) + 1
				if not report.has("xp_events"):
					report["xp_events"] = []
				(report["xp_events"] as Array).append(man)
			elif float(f.strength) > old_s + 0.001:
				report["strength_recovered"] = int(report["strength_recovered"]) + 1
	return report


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
	return ProductionCostCalculator.get_critical_resource_set()


func _weighted_fill_ratio(needed: Dictionary) -> float:
	return ProductionCostCalculator.compute_weighted_fill_ratio(needed, national_stockpile)


func _shortage_multipliers(fill_ratio: float) -> Dictionary:
	return ProductionCostCalculator.compute_shortage_multipliers(fill_ratio)


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
		var raw_mod: Variant = _active_modifiers[modifier_id]
		# After JSON save/load, values may be Dictionary or corrupt String — rebuild safely.
		if raw_mod is ProductionModifier:
			mods.absorb(raw_mod as ProductionModifier)
		elif typeof(raw_mod) == TYPE_DICTIONARY:
			mods.absorb(ProductionModifier.from_dict(raw_mod as Dictionary))
		# else: skip non-modifier entries (do not SCRIPT ERROR on String/nil)

	# === National Spirit + Temporary Modifier Integration (Option B) ===
	var owner_tag := _get_line_owner_tag(line)
	if not owner_tag.is_empty():
		var national_mods := _get_national_production_modifiers(owner_tag, line.get_current_layer() if line else "")
		if national_mods.get("output_multiplier", 1.0) != 1.0:
			mods.output_multiplier *= float(national_mods["output_multiplier"])
		if national_mods.get("reliability_multiplier", 1.0) != 1.0:
			mods.reliability_multiplier *= float(national_mods["reliability_multiplier"])
		if national_mods.get("retooling_days_multiplier", 1.0) != 1.0:
			mods.retooling_days_multiplier *= float(national_mods["retooling_days_multiplier"])
		if national_mods.get("cost_multiplier", 1.0) != 1.0:
			mods.cost_multiplier *= float(national_mods["cost_multiplier"])
		if national_mods.get("resource_output_multiplier", 1.0) != 1.0:
			# Resource boost from agents can mitigate shortages or boost effective output.
			# ProductionModifiers is a RefCounted (not Dictionary) — apply only known fields.
			mods.output_multiplier *= float(national_mods["resource_output_multiplier"])

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


func _get_national_production_modifiers(country_tag: String, production_layer: String = "") -> Dictionary:
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
	line_id: String,
) -> void:
	# Family XP (optional when template missing family)
	if typeof(GameData) != TYPE_NIL and GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(template_id)
		if template != null and not template.design_family.is_empty():
			var family_id: String = template.design_family
			var total := int(_family_units_produced.get(family_id, 0)) + 1
			_family_units_produced[family_id] = total
			family_experience_changed.emit(family_id, total)
	# Deposit completed unit into country stockpile (factory→line→stockpile loop).
	# Same sink as production_completed path.
	if not template_id.is_empty():
		production_completed.emit(line_id, template_id, 1)


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
		var raw: Variant = _active_modifiers[modifier_id]
		var tags: Array = []
		if raw is ProductionModifier:
			tags = (raw as ProductionModifier).tags
		elif typeof(raw) == TYPE_DICTIONARY:
			var t: Variant = (raw as Dictionary).get("tags", [])
			if typeof(t) == TYPE_ARRAY:
				tags = t as Array
		else:
			to_remove.append(str(modifier_id))
			continue
		if tag in tags:
			to_remove.append(str(modifier_id))
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


## Scenario/OOB bootstrap: assign factory + design without tech/retool gates so starting lines produce.
## Seeds modest tooling (historical starting industry already builds these designs) and skips retool delay.
func bootstrap_line_on_factory(line_id: String, design_id: String, factory_id: int) -> bool:
	var line := get_line(line_id)
	if line == null:
		line = create_line(line_id)
	if line == null or design_id.is_empty() or factory_id <= 0:
		return false
	if not assign_line_to_factory(line_id, factory_id):
		# Still force factory_id if assign failed due to slot cap — allow production evidence path
		line.factory_id = factory_id
	var result: Dictionary = line.set_template(design_id)
	if not bool(result.get("success", false)):
		# Force design fields even if template lookup fails (still allows progress defaults)
		line.current_template_id = design_id
		line.design_id = design_id
		line.retooling_days_remaining = 0.0
		line.production_progress = 0.0
		if line.has_method("refresh_required_progress"):
			line.refresh_required_progress()
		if line.has_method("reset_progress"):
			line.reset_progress()
	else:
		# Scenario start: skip retooling delay so first days produce immediately
		line.retooling_days_remaining = 0.0
	# Starting OOB: factories are already tooled for their national designs (not greenfield).
	var state: DesignLineState = line.get_current_state() if line.has_method("get_current_state") else null
	if state != null:
		state.tooling_efficiency = maxf(state.tooling_efficiency, 45.0)
	return true


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
		"line_layers": _get_line_layers_for_factory(f),
	}



func _get_line_layers_for_factory(factory: Factory) -> Dictionary:
	var res := {}
	if factory == null: return res
	for lid in factory.assigned_lines:
		var ln := get_line(lid)
		if ln:
			res[lid] = ln.get_current_layer()
	return res

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
			"production_layer": line.current_production_layer if "current_production_layer" in line else "mass",
		}

	return {
		"production_stance": production_stance,
		"national_stockpile": national_stockpile.duplicate(true),
		"national_equipment_stockpile": national_equipment_stockpile.duplicate(true),
		"country_equipment_stockpiles": country_equipment_stockpiles.duplicate(true),
		"unit_equipment_stock": _unit_equipment_stock.duplicate(true),
		"province_resource_dev": province_resource_dev.duplicate(true),
		"active_modifiers": _serialize_active_modifiers(),
		"lines": lines_data,
		# family experience, priority etc. can be added later if they prove important
	}


func _serialize_active_modifiers() -> Dictionary:
	var out: Dictionary = {}
	for modifier_id in _active_modifiers:
		var raw: Variant = _active_modifiers[modifier_id]
		if raw is ProductionModifier:
			out[str(modifier_id)] = (raw as ProductionModifier).to_dict()
		elif typeof(raw) == TYPE_DICTIONARY:
			out[str(modifier_id)] = (raw as Dictionary).duplicate(true)
		# drop String/nil corrupt entries
	return out


func _restore_active_modifiers(raw: Variant) -> void:
	_active_modifiers.clear()
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var src: Dictionary = raw as Dictionary
	for modifier_id in src:
		var entry: Variant = src[modifier_id]
		if entry is ProductionModifier:
			_active_modifiers[str(modifier_id)] = entry
		elif typeof(entry) == TYPE_DICTIONARY:
			var mod := ProductionModifier.from_dict(entry as Dictionary)
			if mod.id.is_empty():
				mod.id = str(modifier_id)
			_active_modifiers[str(modifier_id)] = mod
		# ignore plain String keys-as-values from legacy/corrupt saves


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
	if data.has("province_resource_dev"):
		province_resource_dev = (data["province_resource_dev"] as Dictionary).duplicate(true)
	if data.has("active_modifiers"):
		_restore_active_modifiers(data["active_modifiers"])

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
				# persist per-line layer for layered prod
				if ld.has("production_layer"):
					line.current_production_layer = str(ld.get("production_layer", "mass"))
				elif "current_production_layer" in line:
					line.current_production_layer = "mass"

	clear_all_caches()
	print("ProductionManager: Save data applied (%d lines)" % (data.get("lines", {}).size() if data.has("lines") else 0))


## Game loop entry point: one day of national production (supply hooks can chain here later).
## Uses day-based line.advance_days (proven factory→stockpile for OOB lines), not only the
## separate PP accumulator in advance_production — so TimeManager days fill country stockpiles.
func daily_production_tick() -> void:
	# Province deposits → major stockpiles before equipment lines consume inputs.
	daily_resource_harvest_tick(1.0)
	advance_days(1.0)


## Auto-harvest strategic resources from owned provinces into national_stockpile.
## Plants (coal_plant, refinery, …) and tech (plastics, synthetic fuel, nuclear) scale income.
func daily_resource_harvest_tick(days: float = 1.0) -> Dictionary:
	var report := {"days": days, "by_tag": {}, "total_added": {}}
	if days <= 0.0:
		return report
	var rhc = load("res://scripts/production/ResourceHarvestCalculator.gd")
	if rhc == null or not rhc.has_method("compute_national_daily_income"):
		return report
	if typeof(MapManager) == TYPE_NIL:
		return report
	var provinces_payload: Array = []
	var unlocks_by_tag: Dictionary = {}
	var owners: Dictionary = {}
	var light := (
		typeof(TimeManager) != TYPE_NIL
		and TimeManager.has_method("is_interactive_light_sim")
		and bool(TimeManager.is_interactive_light_sim())
	)
	var player_tag_pref := ""
	if light and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		player_tag_pref = str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	# Collect owned land provinces with resources (MapManager.get_all_provinces → id→Province).
	# Interactive: prefer player-owned deposits and cap scan so world_full cannot stall the clock.
	var harvest_cap := 220 if light else 100000
	var harvested := 0
	if MapManager.has_method("get_all_provinces"):
		var all_p: Variant = MapManager.get_all_provinces()
		if all_p is Dictionary:
			for pid_key in (all_p as Dictionary):
				if harvested >= harvest_cap:
					break
				var p: Province = (all_p as Dictionary)[pid_key] as Province
				if p == null:
					continue
				var tag := str(p.owner_tag).strip_edges().to_upper()
				var res: Dictionary = p.resources if p.resources is Dictionary else {}
				var pid := int(p.id) if "id" in p else int(pid_key)
				if tag.is_empty() or res.is_empty():
					continue
				if light and not player_tag_pref.is_empty() and tag != player_tag_pref:
					continue
				var year := 1936
				if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
					year = int(TimeManager.get_current_year())
				var scaled: Dictionary = res
				if rhc.has_method("scale_deposits_for_year"):
					scaled = rhc.scale_deposits_for_year(res, year)
				if scaled.is_empty():
					continue
				owners[tag] = true
				var plants: Array = []
				if typeof(FactoryManager) != TYPE_NIL and FactoryManager.has_method("get_resource_plants_in_province") and pid > 0:
					plants = FactoryManager.get_resource_plants_in_province(pid)
				var development: Dictionary = {}
				if "resource_development" in p and p.resource_development is Dictionary:
					development = (p.resource_development as Dictionary).duplicate()
				var pid_s := str(pid)
				if province_resource_dev.has(pid_s) and province_resource_dev[pid_s] is Dictionary:
					var extra: Dictionary = province_resource_dev[pid_s] as Dictionary
					for dk in extra:
						development[str(dk)] = maxi(int(development.get(dk, 0)), int(extra[dk]))
				provinces_payload.append({
					"owner_tag": tag,
					"resources": scaled,
					"plants": plants,
					"development": development,
					"province_id": pid,
				})
				harvested += 1
	for tag in owners:
		unlocks_by_tag[tag] = _harvest_unlocks_for_tag(str(tag))
	var by_tag: Dictionary = rhc.compute_national_daily_income(provinces_payload, unlocks_by_tag) as Dictionary
	# Apply to player/national stockpile (single-nation production path uses national_stockpile).
	# Multi-tag: merge player country if GameData exposes it; otherwise sum all into national.
	var player_tag := ""
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		player_tag = str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	var total_added: Dictionary = {}
	var cohesion_events: Array = []
	for tag in by_tag:
		var income: Dictionary = by_tag[tag] as Dictionary
		# Single-nation / player stockpile path: apply player income, or all when player unknown.
		var apply := player_tag.is_empty() or str(tag) == player_tag or by_tag.size() == 1
		if not apply:
			continue
		for resource in income:
			var amt := float(income[resource]) * days
			if amt <= 0.0:
				continue
			# supplies is ops triad; store alongside majors in national_stockpile
			national_stockpile[resource] = float(national_stockpile.get(resource, 0.0)) + amt
			total_added[resource] = float(total_added.get(resource, 0.0)) + amt
		# Food → supplies → cohesion (ops triad; soft stability from harvest)
		if rhc.has_method("compute_food_cohesion_delta"):
			var sup_inc := float(income.get("supplies", 0.0)) * days
			var sup_stock := float(national_stockpile.get("supplies", 0.0))
			var coh: Dictionary = rhc.compute_food_cohesion_delta(sup_inc, sup_stock) as Dictionary
			var d_coh := int(coh.get("cohesion_delta", 0))
			if d_coh != 0 and typeof(GameData) != TYPE_NIL and GameData.has_method("apply_pillar_shift"):
				GameData.apply_pillar_shift(str(tag), "cohesion", d_coh, "food_supplies_harvest")
				cohesion_events.append({"tag": tag, "delta": d_coh, "reason": str(coh.get("reason", ""))})
	report["by_tag"] = by_tag
	report["total_added"] = total_added
	report["cohesion_events"] = cohesion_events
	return report


## Expand an existing era-visible deposit (mine/well). Pays steel. Does not invent geology.
func develop_province_resource(province_id: int, resource_key: String = "") -> Dictionary:
	var pid := int(province_id)
	if pid <= 0 or typeof(MapManager) == TYPE_NIL:
		return {"ok": false, "error": "no_province"}
	var p: Province = MapManager.get_province(pid) if MapManager.has_method("get_province") else null
	if p == null:
		return {"ok": false, "error": "no_province"}
	var res: Dictionary = p.resources if p.resources is Dictionary else {}
	var rhc = load("res://scripts/production/ResourceHarvestCalculator.gd")
	if rhc == null or not rhc.has_method("build_develop_resource_action"):
		return {"ok": false, "error": "no_calculator"}
	var year := 1936
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
		year = int(TimeManager.get_current_year())
	var pid_s := str(pid)
	var development: Dictionary = {}
	if "resource_development" in p and p.resource_development is Dictionary:
		development = (p.resource_development as Dictionary).duplicate()
	if province_resource_dev.has(pid_s) and province_resource_dev[pid_s] is Dictionary:
		var extra: Dictionary = province_resource_dev[pid_s] as Dictionary
		for dk in extra:
			development[str(dk)] = maxi(int(development.get(dk, 0)), int(extra[dk]))
	var action: Dictionary = rhc.build_develop_resource_action(
		res, resource_key, year, development, national_stockpile
	) as Dictionary
	if not bool(action.get("ok", false)):
		return {"ok": false, "error": str(action.get("error", "invalid")), "action": action}
	var cost: Dictionary = action.get("cost", {}) as Dictionary
	if not pay_cost(cost):
		return {"ok": false, "error": "pay_failed", "action": action}
	var want := str(action.get("key", ""))
	var after := int(action.get("level_after", 1))
	development[want] = after
	if "resource_development" in p:
		p.resource_development = development
	province_resource_dev[pid_s] = development.duplicate()
	return {
		"ok": true,
		"province_id": pid,
		"key": want,
		"level": after,
		"cost": cost,
		"year": year,
		"action": action,
	}


## Bootstrap resource/energy plants from province deposits (once per session unless force).
func auto_seed_resource_plants_from_map(force: bool = false, max_per_owner: int = 12) -> Dictionary:
	if _resource_plants_seeded and not force:
		return {"seeded": 0, "already_seeded": true}
	if typeof(FactoryManager) == TYPE_NIL or not FactoryManager.has_method("auto_seed_resource_plants"):
		return {"seeded": 0, "error": "no_factory_manager"}
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_all_provinces"):
		return {"seeded": 0, "error": "no_map"}
	var provinces_payload: Array = []
	var unlocks_by_tag: Dictionary = {}
	var all_p: Variant = MapManager.get_all_provinces()
	if all_p is Dictionary:
		for pid_key in (all_p as Dictionary):
			var p: Province = (all_p as Dictionary)[pid_key] as Province
			if p == null:
				continue
			var tag := str(p.owner_tag).strip_edges().to_upper()
			var res: Dictionary = p.resources if p.resources is Dictionary else {}
			var pid := int(p.id) if "id" in p else int(pid_key)
			if tag.is_empty() or res.is_empty():
				continue
			provinces_payload.append({"province_id": pid, "owner_tag": tag, "resources": res})
			if not unlocks_by_tag.has(tag):
				unlocks_by_tag[tag] = _harvest_unlocks_for_tag(tag)
	var report: Dictionary = FactoryManager.auto_seed_resource_plants(provinces_payload, unlocks_by_tag, max_per_owner)
	_resource_plants_seeded = true
	return report


func _harvest_unlocks_for_tag(tag: String) -> Dictionary:
	var unlocks := {"rule_flags": [], "unlocked_resources": [], "permanent_modifiers": {}}
	if typeof(TechnologyManager) == TYPE_NIL:
		return unlocks
	var state: Dictionary = TechnologyManager.get_country_state(tag) if TechnologyManager.has_method("get_country_state") else {}
	if state.get("rule_flags") is Array:
		unlocks["rule_flags"] = (state["rule_flags"] as Array).duplicate()
	if state.get("unlocked_resources") is Array:
		unlocks["unlocked_resources"] = (state["unlocked_resources"] as Array).duplicate()
	if state.get("permanent_modifiers") is Dictionary:
		unlocks["permanent_modifiers"] = (state["permanent_modifiers"] as Dictionary).duplicate(true)
	if TechnologyManager.has_method("get_technology_modifiers"):
		var mods: Dictionary = TechnologyManager.get_technology_modifiers(tag)
		for k in mods:
			var pm: Dictionary = unlocks["permanent_modifiers"] as Dictionary
			pm[k] = float(pm.get(k, 0.0)) + float(mods[k])
	return unlocks


## Listener for central TimeManager daily tick (wired in _ready).
## Keeps production in sync with the rest of the daily simulation loop (Supply/Agents/Repair).
func _on_game_day_advanced(_year: int, _month: int, _day: int) -> void:
	var light := (
		typeof(TimeManager) != TYPE_NIL
		and TimeManager.has_method("is_interactive_light_sim")
		and bool(TimeManager.is_interactive_light_sim())
	)
	var day_n := 0
	if typeof(TimeManager) != TYPE_NIL:
		if TimeManager.has_method("get_total_days_elapsed"):
			day_n = int(TimeManager.get_total_days_elapsed())
		elif "total_days_elapsed" in TimeManager:
			day_n = int(TimeManager.total_days_elapsed)
	# Interactive: keep production line ticks cheap; harvest/reinforce only every 5th day.
	# (Daily harvest + reinforce scans were still heavy enough to stall 1x near Feb→Mar.)
	if light:
		advance_days(1.0)
		if day_n % 5 == 0:
			daily_resource_harvest_tick(5.0)
			daily_formation_reinforce_from_stockpile()
		return
	daily_production_tick()
	daily_formation_reinforce_from_stockpile()


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
