# scripts/technology/TechnologyUnlockRegistry.gd
class_name TechnologyUnlockRegistry
extends RefCounted

## Applies typed unlock entries when research completes.


func apply_unlocks(
	country_tag: String,
	tech_id: String,
	unlocks: Array,
	state: Dictionary,
	on_unlocked: Callable = Callable(),
) -> void:
	if unlocks.is_empty():
		return
	for raw in unlocks:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var unlock: Dictionary = raw as Dictionary
		apply_unlock(country_tag, tech_id, unlock, state)
		if on_unlocked.is_valid():
			on_unlocked.call(country_tag, tech_id, unlock)


func apply_unlock(
	country_tag: String,
	tech_id: String,
	unlock: Dictionary,
	state: Dictionary,
) -> void:
	var unlock_type := str(unlock.get("type", ""))
	match unlock_type:
		"modifier":
			_apply_modifier_unlock(state, unlock)
		"doctrine_key":
			_append_unique(state, "unlocked_doctrine_keys", str(unlock.get("key", "")))
		"division_capability":
			_append_unique(state, "division_capabilities", str(unlock.get("capability", "")))
		"agent_mission":
			_append_unique(state, "unlocked_agent_missions", str(unlock.get("mission_id", "")))
		"unit_design":
			_apply_unit_design_unlock(state, unlock)
		"factory_type":
			_append_unique(state, "unlocked_factory_types", str(unlock.get("factory_type", "")))
		"production_category":
			_apply_production_category_unlock(state, unlock, tech_id)
		"rule_flag":
			_append_unique(state, "rule_flags", str(unlock.get("flag", "")))
		"resource":
			_apply_resource_unlock(state, unlock)
		"building", "equipment_module":
			_store_deferred_unlock(state, unlock_type, unlock)
		"division_template":
			_apply_division_template_unlock(state, unlock)
			_store_deferred_unlock(state, unlock_type, unlock)
		_:
			push_warning(
				"TechnologyUnlockRegistry: Unhandled unlock type '%s' from %s for %s"
				% [unlock_type, tech_id, country_tag]
			)


func _apply_modifier_unlock(state: Dictionary, unlock: Dictionary) -> void:
	var stat := str(unlock.get("stat", ""))
	if stat.is_empty():
		return
	if not state.has("permanent_modifiers"):
		state["permanent_modifiers"] = {}
	var mods: Dictionary = state["permanent_modifiers"]
	mods[stat] = float(mods.get(stat, 0.0)) + float(unlock.get("value", 0.0))


func _apply_unit_design_unlock(state: Dictionary, unlock: Dictionary) -> void:
	var ids: Array = []
	if unlock.has("template_ids"):
		for raw in unlock.get("template_ids", []) as Array:
			ids.append(str(raw))
	elif unlock.has("template_id"):
		ids.append(str(unlock.get("template_id", "")))
	for template_id in ids:
		_append_unique(state, "unlocked_unit_designs", template_id)


func _apply_division_template_unlock(state: Dictionary, unlock: Dictionary) -> void:
	var ids: Array = []
	if unlock.has("template_ids"):
		for raw in unlock.get("template_ids", []) as Array:
			ids.append(str(raw))
	elif unlock.has("template_id"):
		ids.append(str(unlock.get("template_id", "")))
	for template_id in ids:
		_append_unique(state, "unlocked_division_templates", template_id)


func _apply_production_category_unlock(state: Dictionary, unlock: Dictionary, tech_id: String) -> void:
	var category := str(unlock.get("category", ""))
	if category.is_empty():
		return
	if not state.has("unlocked_production_categories"):
		state["unlocked_production_categories"] = {}
	var cats: Dictionary = state["unlocked_production_categories"]
	cats[category] = {
		"min_factory_type": str(unlock.get("min_factory_type", "")),
		"source_tech": tech_id,
	}


## Strategic resource unlock (fissiles / uranium visibility) + optional output bonus.
func _apply_resource_unlock(state: Dictionary, unlock: Dictionary) -> void:
	var resource := str(unlock.get("resource", "")).strip_edges().to_lower()
	if resource.is_empty():
		return
	_append_unique(state, "unlocked_resources", resource)
	# Map uranium → fissiles major visibility for harvest / UI
	if resource in ["uranium", "plutonium", "fissiles"]:
		_append_unique(state, "unlocked_resources", "fissiles")
		_append_unique(state, "rule_flags", "nuclear_fuel")
	var bonus := float(unlock.get("bonus", 0.0))
	if bonus != 0.0:
		if not state.has("permanent_modifiers"):
			state["permanent_modifiers"] = {}
		var mods: Dictionary = state["permanent_modifiers"]
		var key := "resource_output_%s" % resource
		mods[key] = float(mods.get(key, 0.0)) + bonus
		mods["resource_output"] = float(mods.get("resource_output", 0.0)) + bonus * 0.5


func _append_unique(state: Dictionary, key: String, value: String) -> void:
	if value.is_empty():
		return
	if not state.has(key):
		state[key] = []
	var list: Array = state[key]
	if value not in list:
		list.append(value)


func _store_deferred_unlock(state: Dictionary, unlock_type: String, unlock: Dictionary) -> void:
	if not state.has("deferred_unlocks"):
		state["deferred_unlocks"] = []
	(state["deferred_unlocks"] as Array).append({
		"type": unlock_type,
		"data": unlock.duplicate(true),
	})
