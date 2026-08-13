# scripts/map/Factory.gd
class_name Factory
extends Resource

## Province-scoped id: `province_id * ID_SLOT_SCALE + slot` (slot 1–99 per province). 0 = unset.
const ID_SLOT_SCALE := 100
const MAX_SLOTS_PER_PROVINCE := 99

@export var factory_id: int = 0
@export var province_id: int = 0  # Matches Province.id (map province key)
@export var owner_tag: String = ""
@export var is_seized: bool = false
@export var current_damage: float = 0.0
@export var repair_progress: float = 0.0
@export var is_annexed: bool = false

@export var assigned_lines: Array[String] = []  # Active ProductionLine ids (production slots)
@export var max_production_lines: int = 1
@export var factory_type: String = "standard"  # standard | shipyard | aircraft_factory | coal_plant | refinery | …
@export var size_tier: int = 1  ## Resource/energy plant size (1–5); scales harvest output
@export var current_production_design: String = ""

@export var is_retooling: bool = false
@export var retooling_progress: float = 0.0
@export var retooling_required: float = 0.0
@export var retooling_recovery_progress: float = 0.0
@export var retooling_recovery_required: float = 0.0
@export var previous_design: String = ""

var current_efficiency: float = 1.0
var base_retained_efficiency: float = 1.0

const RULES_PATH := "res://data/production/factory_rules.json"

static var _rules_cache: Dictionary = {}
static var _rules_loaded: bool = false


# === Static ID helpers ===

static func make_id(p_province_id: int, slot: int) -> int:
	return p_province_id * ID_SLOT_SCALE + slot


static func province_from_id(f_id: int) -> int:
	var scale := float(ID_SLOT_SCALE)
	return int(float(f_id) / scale)


static func slot_from_id(f_id: int) -> int:
	return f_id % ID_SLOT_SCALE


func apply_damage(amount: float) -> void:
	current_damage = clampf(current_damage + amount, 0.0, 100.0)
	_recalculate_efficiency()


func start_repair() -> void:
	repair_progress = 0.0


func advance_repair(days: float, supply_connected: bool, rules: Dictionary = {}) -> void:
	if current_damage <= 0.0:
		return
	var repair_rules: Dictionary = rules.get("repair", _get_rules().get("repair", {}))
	if not supply_connected and bool(repair_rules.get("requires_supply_connection", true)):
		return

	var base := float(repair_rules.get("base_repair_per_day", 5.0))
	var mult := float(repair_rules.get("annexed_multiplier", 2.5)) if is_annexed else float(
		repair_rules.get("occupied_multiplier", 1.0),
	)

	repair_progress += base * mult * days
	if repair_progress >= 100.0:
		current_damage = maxf(0.0, current_damage - (repair_progress - 100.0))
		repair_progress = 0.0
		if current_damage < float(repair_rules.get("min_repair_threshold_for_production", 30.0)):
			current_damage = 0.0
	_recalculate_efficiency()


func get_daily_output_estimate() -> float:
	## Production Points per day contributed by this factory (before concentration).
	return ProductionCostCalculator.get_base_daily_points() * get_production_efficiency()


func get_production_efficiency() -> float:
	return current_efficiency * get_current_efficiency()


func start_retooling(
	old_design: String,
	new_design: String,
	retool_days: float,
	recovery_days: float,
	retained_efficiency: float,
) -> void:
	if old_design == new_design:
		return

	previous_design = old_design
	current_production_design = new_design
	retooling_required = maxf(retool_days, 0.0)
	retooling_progress = 0.0
	retooling_recovery_required = maxf(recovery_days, 0.0)
	retooling_recovery_progress = 0.0
	base_retained_efficiency = clampf(retained_efficiency, 0.0, 1.0)
	is_retooling = true


func get_current_efficiency() -> float:
	if not is_retooling:
		return 1.0

	if retooling_progress < retooling_required:
		return base_retained_efficiency

	if retooling_recovery_required <= 0.0:
		return 1.0

	var recovery_percent := retooling_recovery_progress / retooling_recovery_required
	return lerpf(base_retained_efficiency, 1.0, clampf(recovery_percent, 0.0, 1.0))


func advance_retooling(days: float) -> void:
	if not is_retooling or days <= 0.0:
		return

	if retooling_progress < retooling_required:
		retooling_progress += days
	elif retooling_recovery_progress < retooling_recovery_required:
		retooling_recovery_progress = minf(
			retooling_recovery_progress + days,
			retooling_recovery_required,
		)

	if retooling_progress >= retooling_required and retooling_recovery_progress >= retooling_recovery_required:
		is_retooling = false
		retooling_progress = 0.0
		retooling_recovery_progress = 0.0
		retooling_required = 0.0
		retooling_recovery_required = 0.0


func get_available_line_slots() -> int:
	return maxi(0, max_production_lines - assigned_lines.size())


func can_add_more_lines() -> bool:
	return assigned_lines.size() < max_production_lines


func has_assigned_line(line_id: String) -> bool:
	return line_id in assigned_lines


func sync_production_design(design_id: String) -> void:
	current_production_design = design_id


func _recalculate_efficiency() -> void:
	var rules := _get_rules()
	var eff_rules: Dictionary = rules.get("efficiency", {})
	var base := float(eff_rules.get("base_efficiency", 1.0))
	var damage_penalty := current_damage * float(eff_rules.get("damage_penalty_per_percent", 0.008))
	current_efficiency = clampf(
		base - damage_penalty,
		float(eff_rules.get("min_efficiency", 0.3)),
		float(eff_rules.get("max_efficiency", 1.5)),
	)


static func _get_rules() -> Dictionary:
	if _rules_loaded:
		return _rules_cache
	_rules_loaded = true
	if not FileAccess.file_exists(RULES_PATH):
		push_warning("Factory: missing rules ", RULES_PATH)
		return _rules_cache
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return _rules_cache
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) == OK and typeof(parser.data) == TYPE_DICTIONARY:
		_rules_cache = parser.data
	return _rules_cache
