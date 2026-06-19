## Produces one [UnitTemplate] at a time with tooling efficiency, retooling, and refinement.
##
## Basic loop:
##   line.set_template("m4_sherman_medium")
##   line.advance_days(1.0)  # daily tick; emits unit_completed when a unit finishes
##   line.start_refinement("quality_control")
##
## Use [ProductionManager] autoload to manage multiple lines nationally.
class_name ProductionLine
extends RefCounted

signal template_changed(old_template_id: String, new_template_id: String, retooling_days: float)
signal unit_completed(template_id: String, reliability: float, profile: ReliabilityProfile)
signal refinement_started(project_id: String, template_id: String)
signal refinement_completed(project_id: String, template_id: String, reliability_gain: float)

var line_id: String = ""
@export var factory_id: int = 0  # Encoded ID (e.g. 4201)
@export var design_id: String = ""  # What this line is producing
@export var progress: float = 0.0  # Accumulated Production Points toward current design
@export var completed_count: int = 0  # Items finished on this line (item-progression track)
@export var design_production_cost: float = 100.0  # PP required for one unit (from template data)
@export var daily_resource_cost: Dictionary = {}  # Resources consumed per production day
@export var resource_shortage_penalty: float = 1.0  # Speed multiplier during shortages (0.4–1.0)
var shortage_reliability_multiplier: float = 1.0  # Applied to units completed under shortage

var required_progress: float = 100.0  # Alias for design_production_cost (legacy)
var current_template_id: String = ""
var design_states: Dictionary = {}
var retooling_days_remaining: float = 0.0
var production_progress: float = 0.0
var active_refinement: RefinementProject = null
## Overrides template module_loadout for weapon/cargo slots (empty string clears a slot).
var custom_module_loadout: Dictionary = {}

var _design_data: DesignDataLoader = null
var _rules: Dictionary = {}
var _modifier_resolver: Callable = Callable()
var _runtime_modifiers: ProductionModifiers = ProductionModifiers.new()


func _init(design_data: DesignDataLoader, p_line_id: String = "") -> void:
	_design_data = design_data
	line_id = p_line_id
	_rules = design_data.production_rules if design_data else {}


func reset_progress() -> void:
	progress = 0.0


func add_progress(amount: float) -> void:
	if amount <= 0.0:
		return
	progress += amount


func refresh_design_production_cost() -> void:
	var template: UnitTemplate = get_current_template()
	if template == null:
		if design_id.begins_with("civilian_"):
			# Fixed low cost for civilian consumer goods demo (happiness loop).
			design_production_cost = 60.0
			daily_resource_cost = {"steel": 2, "energy": 1}  # light inputs for goods
		else:
			design_production_cost = 100.0
			daily_resource_cost = {}
	else:
		design_production_cost = ProductionCostCalculator.resolve_cost(
			template, _design_data, get_effective_loadout()
		)
		daily_resource_cost = template.get_daily_resource_cost_dict()
	required_progress = design_production_cost


func refresh_required_progress() -> void:
	refresh_design_production_cost()


func get_progress_percent() -> float:
	if design_production_cost <= 0.0:
		return 0.0
	return clampf(progress / design_production_cost, 0.0, 1.0)


func set_modifier_resolver(resolver: Callable) -> void:
	_modifier_resolver = resolver


func set_runtime_modifiers(mods: ProductionModifiers) -> void:
	_runtime_modifiers = mods if mods != null else ProductionModifiers.new()


func set_template(template_id: String) -> Dictionary:
	var result := {
		"success": false,
		"previous_template_id": current_template_id,
		"new_template_id": template_id,
		"similarity": 1.0,
		"retooling_days": 0.0,
	}

	if _design_data == null:
		push_warning("ProductionLine has no DesignDataLoader")
		return result

	var new_template : UnitTemplate = _design_data.get_template(template_id)
	if new_template == null:
		if template_id.begins_with("civilian_"):
			# Civilian goods lines (roadmap): no unit template, fixed consumer output for pop happiness.
			# Allowed for any factory to demo civilian production.
			print("ProductionLine: civilian goods mode set for %s (no template, fixed cost/happiness effect)." % template_id)
		else:
			push_warning("Unknown unit template: " + template_id)
			return result

	_persist_current_state()

	var old_template: UnitTemplate = null
	if not current_template_id.is_empty():
		old_template = _design_data.get_template(current_template_id)

	if old_template != null and old_template.id != template_id:
		var similarity : float = RetoolingCalculator.compute_similarity(old_template, new_template, _rules)
		result["similarity"] = similarity
		result["retooling_days"] = RetoolingCalculator.compute_retooling_days(similarity, _rules)
		retooling_days_remaining = result["retooling_days"]
		production_progress = 0.0
		template_changed.emit(current_template_id, template_id, retooling_days_remaining)
	elif current_template_id != template_id:
		retooling_days_remaining = 0.0
		production_progress = 0.0
		template_changed.emit(current_template_id, template_id, 0.0)

	current_template_id = template_id
	design_id = template_id
	_sync_factory_production_design()
	custom_module_loadout.clear()
	_ensure_design_state(template_id)
	refresh_required_progress()
	reset_progress()
	result["success"] = true
	return result


func get_current_template() -> UnitTemplate:
	if _design_data == null or current_template_id.is_empty():
		return null
	return _design_data.get_template(current_template_id)


func get_current_state() -> DesignLineState:
	return _ensure_design_state(current_template_id)


func get_tooling_efficiency() -> float:
	var state : DesignLineState = get_current_state()
	if state == null:
		return 0.0
	var max_eff := float(_rules.get("tooling", {}).get("max_efficiency", 100))
	return clampf(state.tooling_efficiency, 0.0, max_eff)


func get_output_multiplier() -> float:
	var multiplier : float = _base_output_multiplier()
	return multiplier * _active_modifiers().get_total_output_multiplier()


func _base_output_multiplier() -> float:
	if retooling_days_remaining > 0.0:
		return float(_rules.get("retooling", {}).get("efficiency_multiplier_during_retool", 0.45))

	var tooling_rules: Dictionary = _rules.get("tooling", {})
	var max_eff := float(tooling_rules.get("max_efficiency", 100))
	var at_zero := float(tooling_rules.get("output_multiplier_at_zero", 0.82))
	var at_max := float(tooling_rules.get("output_multiplier_at_max", 1.38))
	var tooling_ratio := get_tooling_efficiency() / maxf(max_eff, 0.001)
	var multiplier : float = lerpf(at_zero, at_max, tooling_ratio)

	if active_refinement != null and not active_refinement.blocks_production:
		multiplier *= 1.0 - active_refinement.production_penalty

	# Weather full penalties integration (econ polish): cold/mud/snow/blackout drag factory output (province targeted via factory if avail)
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_production_weather_mult"):
		var wmult : float = 1.0
		# Resolve pid from factory if tracked on line/factory
		if typeof(FactoryManager) != TYPE_NIL and "factory_id" in self and self.factory_id != null:
			var fdata = FactoryManager.get_factory(self.factory_id) if FactoryManager.has_method("get_factory") else null
			var pidv := -1
			if fdata:
				if "province_id" in fdata:
					pidv = int(fdata.province_id)
				elif typeof(fdata) == TYPE_DICTIONARY and fdata.has("province_id"):
					pidv = int(fdata.get("province_id"))
			if pidv >= 0:
				wmult = WeatherManager.get_production_weather_mult(pidv)
		multiplier *= wmult

	return multiplier


func get_effective_loadout() -> Dictionary:
	var template: UnitTemplate = get_current_template()
	if template == null:
		return {}
	return LogisticsCalculator.resolve_loadout(template, custom_module_loadout)


func _effective_module_ids() -> Array[String]:
	var ids: Array[String] = []
	for module_id in get_effective_loadout().values():
		var mid := str(module_id)
		if not mid.is_empty():
			ids.append(mid)
	return ids


func set_slot_module(slot_name: String, module_id: String) -> void:
	custom_module_loadout[slot_name] = module_id
	refresh_design_production_cost()


func clear_slot_module(slot_name: String) -> void:
	custom_module_loadout[slot_name] = ""
	refresh_design_production_cost()


func clear_custom_loadout() -> void:
	custom_module_loadout.clear()
	refresh_design_production_cost()


func get_reliability_profile() -> ReliabilityProfile:
	var template: UnitTemplate = get_current_template()
	var state : DesignLineState = get_current_state()
	if template == null or state == null:
		return ReliabilityProfile.new()
	return ReliabilityCalculator.compute_profile(
		template,
		state,
		_rules,
		get_tooling_efficiency(),
		_active_modifiers(),
		_design_data,
		active_refinement,
		custom_module_loadout,
	)


func get_effective_reliability() -> float:
	return get_reliability_profile().effective_reliability


func list_refinement_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var state : DesignLineState = get_current_state()
	if state == null or _design_data == null:
		return options

	for def in _design_data.get_refinement_project_defs():
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var project_id := str(def.get("id", ""))
		if project_id.is_empty():
			continue
		var eligibility : Dictionary = _refinement_eligibility(project_id, def, state)
		options.append({
			"id": project_id,
			"name": str(def.get("name", project_id)),
			"category": str(def.get("category", "refinement")),
			"cost": def.get("cost", {}),
			"days": float(def.get("days", 0)),
			"reliability_gain": float(def.get("reliability_gain", 0)),
			"maturity_gain": float(def.get("maturity_gain", 0)),
			"maintenance_reduction": float(def.get("maintenance_reduction", 0)),
			"blocks_production": bool(def.get("blocks_production", false)),
			"production_penalty": float(def.get("production_penalty", 0)),
			"tradeoff_summary": str(def.get("tradeoff_summary", "")),
			"completions": state.get_refinement_completions(project_id),
			"max_completions": int(def.get("max_completions", 1)),
			"can_start": bool(eligibility.get("can_start", false)),
			"blocked_reason": str(eligibility.get("reason", "")),
		})
	return options


func can_start_refinement(project_id: String) -> Dictionary:
	var state : DesignLineState = get_current_state()
	if state == null:
		return {"can_start": false, "reason": "no_active_design"}
	var def: Dictionary = _design_data.get_refinement_def(project_id) if _design_data else {}
	return _refinement_eligibility(project_id, def, state)


func get_days_per_unit() -> float:
	var template: UnitTemplate = get_current_template()
	if template == null:
		return 9999.0
	var base_days := template.base_production_days
	for module_id in _effective_module_ids():
		var mod: EquipmentModule = _design_data.get_module(module_id)
		if mod != null:
			base_days += mod.production_time * 0.15
	return maxf(base_days, 1.0)


func get_production_cost() -> Dictionary:
	var template: UnitTemplate = get_current_template()
	if template == null:
		return {}
	var total: Dictionary = {}
	_merge_cost(total, _scaled_cost(template.base_stats.get("production_cost", {}), 1.0))
	for module_id in _effective_module_ids():
		var mod: EquipmentModule = _design_data.get_module(module_id)
		if mod != null:
			_merge_cost(total, mod.cost)
	return total


func start_refinement(project_id: String) -> bool:
	var eligibility : Dictionary = can_start_refinement(project_id)
	if not bool(eligibility.get("can_start", false)):
		return false

	var def: Dictionary = _design_data.get_refinement_def(project_id)
	active_refinement = RefinementProject.from_def(def, current_template_id)
	refinement_started.emit(project_id, current_template_id)
	return true


func cancel_refinement() -> void:
	active_refinement = null


func advance_days(days: float) -> Dictionary:
	var report := {
		"days_advanced": days,
		"units_completed": 0,
		"retooling_remaining": retooling_days_remaining,
		"refinement_completed": false,
	}

	if days <= 0.0 or current_template_id.is_empty():
		return report

	var state : DesignLineState = get_current_state()
	if state != null:
		state.days_on_design += days

	if retooling_days_remaining > 0.0:
		retooling_days_remaining = maxf(retooling_days_remaining - days, 0.0)
		report["retooling_remaining"] = retooling_days_remaining
		_advance_refinement(days, report)
		return report

	if active_refinement != null and active_refinement.blocks_production:
		_advance_refinement(days, report)
		return report

	_advance_refinement(days, report)

	var output_mult := get_output_multiplier()
	var effective_days := days * get_effective_daily_rate(output_mult)
	production_progress += effective_days

	var days_needed := get_days_per_unit()
	while production_progress >= days_needed:
		production_progress -= days_needed
		_complete_unit(state)
		report["units_completed"] += 1

	report["retooling_remaining"] = retooling_days_remaining
	return report


func _complete_unit(state: DesignLineState) -> void:
	if state == null:
		return

	state.units_produced += 1
	ReliabilityCalculator.recompute_design_maturity(state, _rules)
	var tooling_rules: Dictionary = _rules.get("tooling", {})
	var gain := float(tooling_rules.get("gain_per_unit", 0.18))
	var max_eff := float(tooling_rules.get("max_efficiency", 100))
	var idle_gain := float(tooling_rules.get("gain_per_day_idle_on_design", 0.02))
	var tooling_mult := _active_modifiers().tooling_gain_multiplier
	state.tooling_efficiency = clampf(state.tooling_efficiency + (gain + idle_gain) * tooling_mult, 0.0, max_eff)

	var profile := get_reliability_profile()
	# High-value foreign military / loyalty hook: High national foreign_military_pct or low loyalty reduces effective reliability of completed units (integration strain, lower quality control, "bought" troops/equipment feel less reliable — historical parallel to mercenary or colonial production issues).
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_military_loyalty_multiplier"):
		var loyalty: float = GameData.get_military_loyalty_multiplier("player")  # or current owner if tracked
		var foreign_pct := 0.0
		if "foreign_military_pct" in GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}:
			foreign_pct = GameData.get_peace_state().get("foreign_military_pct", {}).get("player", 0.0)
		var foreign_penalty := 1.0 - (foreign_pct * 0.4) * (1.0 - loyalty)  # scales with both
		profile.effective_reliability = clampf(profile.effective_reliability * foreign_penalty, 0.5, 1.0)
	unit_completed.emit(current_template_id, profile.effective_reliability, profile)


func _advance_refinement(days: float, report: Dictionary) -> void:
	if active_refinement == null:
		return
	active_refinement.advance(days)
	if active_refinement.is_complete():
		_apply_refinement_completion(active_refinement)
		refinement_completed.emit(active_refinement.id, current_template_id, active_refinement.reliability_gain)
		report["refinement_completed"] = true
		active_refinement = null


func _persist_current_state() -> void:
	if current_template_id.is_empty():
		return
	var state : DesignLineState = get_current_state()
	if state != null:
		design_states[current_template_id] = state


func _ensure_design_state(template_id: String) -> DesignLineState:
	if template_id.is_empty():
		return null
	if design_states.has(template_id):
		return design_states[template_id] as DesignLineState
	var state := DesignLineState.new()
	state.template_id = template_id
	design_states[template_id] = state
	return state


func _apply_refinement_completion(project: RefinementProject) -> void:
	var state : DesignLineState = get_current_state()
	if state == null or project == null:
		return
	state.reliability_refinement_bonus += project.reliability_gain
	state.maturity_from_projects = clampf(state.maturity_from_projects + project.maturity_gain, 0.0, 1.0)
	state.maintenance_burden_multiplier *= 1.0 - clampf(project.maintenance_reduction, 0.0, 0.95)
	state.record_refinement_completion(project.id)
	ReliabilityCalculator.recompute_design_maturity(state, _rules)


func _refinement_eligibility(project_id: String, def: Dictionary, state: DesignLineState) -> Dictionary:
	if active_refinement != null:
		return {"can_start": false, "reason": "refinement_in_progress"}
	if current_template_id.is_empty() or _design_data == null:
		return {"can_start": false, "reason": "no_active_design"}
	if def.is_empty():
		return {"can_start": false, "reason": "unknown_project"}

	var max_completions := int(def.get("max_completions", 1))
	if state.get_refinement_completions(project_id) >= max_completions:
		return {"can_start": false, "reason": "max_completions_reached"}

	return {"can_start": true, "reason": ""}


func _merge_cost(target: Dictionary, addition: Dictionary) -> void:
	for resource in addition:
		target[resource] = float(target.get(resource, 0.0)) + float(addition[resource])


func apply_retooling_adjustment(multiplier: float, family_discount: float) -> void:
	if retooling_days_remaining <= 0.0:
		return
	var factor := multiplier * (1.0 - clampf(family_discount, 0.0, 0.95))
	retooling_days_remaining *= factor


func get_retooling_days_remaining() -> float:
	return retooling_days_remaining


func _active_modifiers() -> ProductionModifiers:
	if _modifier_resolver.is_valid():
		return _modifier_resolver.call(self)
	return _runtime_modifiers


func _scaled_cost(raw: Variant, scale: float) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for key in raw:
		out[key] = float(raw[key]) * scale
	return out


func get_assigned_factory() -> Factory:
	if factory_id == 0:
		return null
	var mgr := _factory_manager()
	if mgr == null:
		return null
	return mgr.get_factory(factory_id)


func get_factory_efficiency() -> float:
	if factory_id == 0:
		return 1.0
	var mgr := _factory_manager()
	if mgr == null:
		return 1.0
	return mgr.get_factory_efficiency(factory_id)


func get_effective_daily_rate(base_rate: float) -> float:
	return base_rate * get_factory_efficiency()


func _sync_factory_production_design() -> void:
	if factory_id == 0 or design_id.is_empty():
		return
	var factory := get_assigned_factory()
	if factory != null:
		factory.sync_production_design(design_id)


func _factory_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/FactoryManager")


func get_daily_resource_cost() -> Dictionary:
	return daily_resource_cost.duplicate(true)
