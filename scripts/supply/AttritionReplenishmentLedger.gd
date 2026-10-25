class_name AttritionReplenishmentLedger
extends RefCounted

## Tracks combat/attrition losses and converts them into cargo demand for supply routes.

var _losses: Dictionary = {}
var _division_leader_ids: Dictionary = {}  # division_id -> leader_id


func record_manpower_loss(division_id: String, amount: int, leader_id: String = "") -> void:
	if amount <= 0:
		return
	var key := "manpower:%s" % division_id
	_losses[key] = int(_losses.get(key, 0)) + amount
	if not leader_id.is_empty():
		_division_leader_ids[division_id] = leader_id


func record_equipment_loss(template_id: String, count: float) -> void:
	if count <= 0.0:
		return
	var key := "equip:%s" % template_id
	_losses[key] = float(_losses.get(key, 0.0)) + count


func clear() -> void:
	_losses.clear()
	_division_leader_ids.clear()


func to_save_dict() -> Dictionary:
	return {
		"losses": _losses.duplicate(true),
		"leaders": _division_leader_ids.duplicate(true),
	}


func apply_save_dict(data: Dictionary) -> void:
	_losses.clear()
	_division_leader_ids.clear()
	var losses: Variant = data.get("losses", {})
	if losses is Dictionary:
		for key in (losses as Dictionary).keys():
			_losses[str(key)] = (losses as Dictionary)[key]
	var leaders: Variant = data.get("leaders", {})
	if leaders is Dictionary:
		for key2 in (leaders as Dictionary).keys():
			_division_leader_ids[str(key2)] = str((leaders as Dictionary)[key2])


func get_primary_leader_id() -> String:
	for leader_id in _division_leader_ids.values():
		var lid := str(leader_id)
		if not lid.is_empty():
			return lid
	return ""


func get_leader_id_for_formation(formation_id: String) -> String:
	return str(_division_leader_ids.get(formation_id, ""))


## Applies training-path attrition_reduction for the formation's leader (if any).
func calculate_attrition(formation_id: String, base_attrition: float) -> float:
	if formation_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return maxf(base_attrition, 0.0)

	var leader_id := get_leader_id_for_formation(formation_id)
	if leader_id.is_empty():
		leader_id = LeaderManager.resolve_leader_id_for_formation(formation_id)
	if leader_id.is_empty():
		return maxf(base_attrition, 0.0)

	return LeaderManager.apply_attrition_for_leader(base_attrition, leader_id)


func compute_replenishment_cargo(
	_division_loader: DivisionTemplateLoader,
	design_data: DesignDataLoader,
	rules: SupplyRules,
) -> Dictionary:
	var cargo_rules := rules.get_block("cargo")
	var per_man := float(cargo_rules.get("crew_replacement_tons_per_man", 0.02))
	var attrition_frac := float(cargo_rules.get("attrition_replacement_fraction", 0.25))
	var out := {
		"crew_tons": 0.0,
		"fuel_tons": 0.0,
		"supply_tons": 0.0,
		"equipment_tons": 0.0,
		"total_tons": 0.0,
	}

	for key in _losses:
		var amount: float = float(_losses[key])
		if str(key).begins_with("manpower:"):
			var division_id := str(key).trim_prefix("manpower:")
			var replacement_burden := calculate_attrition(division_id, amount * attrition_frac)
			out["crew_tons"] += replacement_burden * per_man
		elif str(key).begins_with("equip:"):
			var tpl_id := str(key).trim_prefix("equip:")
			var tpl: UnitTemplate = design_data.get_template(tpl_id) if design_data else null
			if tpl != null:
				var req := UnitSupplyRequirements.from_template(tpl, rules)
				out["equipment_tons"] += amount * (req.crew_replacement_cargo + req.supply_cargo_per_day * 3.0)
			else:
				out["equipment_tons"] += amount * 2.0

	out["total_tons"] = out["crew_tons"] + out["fuel_tons"] + out["supply_tons"] + out["equipment_tons"]
	return out
