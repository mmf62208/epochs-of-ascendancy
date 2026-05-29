# scripts/technology/TechnologyManager.gd
extends Node

## Research trees, per-country progress, RP pool, and unlock application (Phase A).

signal research_started(country_tag: String, tech_id: String)
signal research_completed(country_tag: String, tech_id: String)
signal technology_unlocked(country_tag: String, tech_id: String, unlock: Dictionary)
signal research_state_changed(country_tag: String)
signal agent_tech_state_changed(country_tag: String)

const TREES_DIR := "res://data/technology/trees/"
const STARTING_DIR := "res://data/technology/starting/"
const DAYS_PER_YEAR := 365.0
const DEFAULT_RESEARCH_SLOTS := 2
const BASE_RP_PER_DAY := 1.0

const DOMAIN_ORDER: Array[String] = [
	"all",
	"support",
	"industry",
	"land_equipment",
	"naval_equipment",
	"air_equipment",
	"space_equipment",
	"doctrine",
	"strategic_future",
]

const DOCTRINE_DOMAIN_IDS: Array[String] = [
	"land_doctrine",
	"naval_doctrine",
	"air_doctrine",
	"space_doctrine",
]

## Era swimlanes for graph/list filtering (Phase C).
const ERA_SWIMLANES: Array[Dictionary] = [
	{"key": "all", "label": "All eras"},
	{"key": "pre_war", "label": "1900–1918"},
	{"key": "interwar", "label": "1919–1938"},
	{"key": "industrial_war", "label": "1936–1955"},
	{"key": "cold_war", "label": "1946–1989"},
	{"key": "modern", "label": "1970–2010"},
	{"key": "information", "label": "1990–2030"},
	{"key": "near_future", "label": "2020–2040"},
	{"key": "far_future", "label": "2040–2050+"},
]

var technology_nodes: Dictionary = {}
var country_state: Dictionary = {}

## template_id -> tech_id that grants the design (built from tree data)
var _gated_unit_designs: Dictionary = {}
## production_category -> true when any tech unlocks the category
var _gated_production_categories: Dictionary = {}

var _current_year: int = 1936
var _last_year_ticked: int = -1  # Dedup guard: TM + Leader year signals both connected during transition
var _unlock_registry := TechnologyUnlockRegistry.new()


func _ready() -> void:
	_load_all_trees()
	_rebuild_unlock_indices()
	if not research_completed.is_connected(_on_research_completed_toast):
		research_completed.connect(_on_research_completed_toast)

	# Prefer central TimeManager when available (migration path toward single source of truth).
	if typeof(TimeManager) != TYPE_NIL:
		_current_year = TimeManager.get_current_year()
	elif typeof(LeaderManager) != TYPE_NIL:
		_current_year = LeaderManager.get_current_year()

	# Primary listener: TimeManager (central clock)
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(_on_game_year_advanced):
			TimeManager.game_year_advanced.connect(_on_game_year_advanced)

	# Backward-compat listener during transition
	if typeof(LeaderManager) != TYPE_NIL:
		if not LeaderManager.game_year_advanced.is_connected(_on_game_year_advanced):
			LeaderManager.game_year_advanced.connect(_on_game_year_advanced)

	print("TechnologyManager: Loaded %d technology nodes" % technology_nodes.size())


func _on_game_year_advanced(year: int) -> void:
	if year == _last_year_ticked:
		return
	_last_year_ticked = year
	set_current_year(year)
	advance_research(DAYS_PER_YEAR)


func set_current_year(year: int) -> void:
	_current_year = maxi(year, 1)


func get_current_year() -> int:
	return _current_year


# === Loading ===

func _load_all_trees() -> void:
	technology_nodes.clear()
	var dir := DirAccess.open(TREES_DIR)
	if dir == null:
		push_warning("TechnologyManager: Cannot open %s" % TREES_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			if ".example." in file_name:
				file_name = dir.get_next()
				continue
			_merge_tree_file(TREES_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	_rebuild_unlock_indices()


func _merge_tree_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("TechnologyManager: Invalid tree JSON at %s" % path)
		return
	for key in (parsed as Dictionary).keys():
		if str(key).begins_with("_"):
			continue
		var node: Dictionary = (parsed as Dictionary)[key] as Dictionary
		var tech_id := str(node.get("id", key))
		node["id"] = tech_id
		technology_nodes[tech_id] = node


func _rebuild_unlock_indices() -> void:
	_gated_unit_designs.clear()
	_gated_production_categories.clear()
	for tech_id in technology_nodes.keys():
		var node: Dictionary = technology_nodes[tech_id] as Dictionary
		for raw in node.get("unlocks", []) as Array:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var unlock: Dictionary = raw as Dictionary
			match str(unlock.get("type", "")):
				"unit_design":
					for template_id in _template_ids_from_unlock(unlock):
						_gated_unit_designs[template_id] = tech_id
				"production_category":
					var category := str(unlock.get("category", ""))
					if not category.is_empty():
						_gated_production_categories[category] = true


func _template_ids_from_unlock(unlock: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	if unlock.has("template_ids"):
		for raw in unlock.get("template_ids", []) as Array:
			ids.append(str(raw))
	elif unlock.has("template_id"):
		ids.append(str(unlock.get("template_id", "")))
	return ids


# === Country state ===

func _ensure_country(tag: String) -> Dictionary:
	if country_state.has(tag):
		return country_state[tag] as Dictionary
	var state := {
		"completed": {},
		"active": [],
		"permanent_modifiers": {},
		"unlocked_doctrine_keys": [],
		"division_capabilities": [],
		"unlocked_agent_missions": [],
		"unlocked_unit_designs": [],
		"unlocked_factory_types": [],
		"unlocked_production_categories": {},
		"rule_flags": [],
		"deferred_unlocks": [],
		"doctrine_xp": 0,
		"stolen_progress_bank": {},
		"compromised_tech": {},
		"tech_intel_rp_bonus": 0.0,
		"tech_theft_protection_until": 0,
		"agent_tech_log": [],
		"research_slots": DEFAULT_RESEARCH_SLOTS,
	}
	country_state[tag] = state
	_migrate_legacy_state(tag, state)
	return state


func _migrate_legacy_state(tag: String, state: Dictionary) -> void:
	if state.has("pending_production_unlocks"):
		for raw in state.get("pending_production_unlocks", []) as Array:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = raw as Dictionary
			var unlock_type := str(entry.get("type", ""))
			var data: Dictionary = entry.get("data", {}) as Dictionary
			if not data.has("type"):
				data["type"] = unlock_type
			_unlock_registry.apply_unlock(tag, "legacy", data, state)
		state.erase("pending_production_unlocks")
	for key in [
		"unlocked_unit_designs",
		"unlocked_factory_types",
		"rule_flags",
	]:
		if not state.has(key):
			state[key] = []
	if not state.has("unlocked_production_categories"):
		state["unlocked_production_categories"] = {}
	for key in ["stolen_progress_bank", "compromised_tech", "agent_tech_log"]:
		if not state.has(key):
			state[key] = {} if key != "agent_tech_log" else []
	if not state.has("tech_intel_rp_bonus"):
		state["tech_intel_rp_bonus"] = 0.0
	if not state.has("tech_theft_protection_until"):
		state["tech_theft_protection_until"] = 0


func get_country_state(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	return _ensure_country(tag).duplicate(true)


func is_tech_completed(country_tag: String, tech_id: String) -> bool:
	var state := _ensure_country(country_tag.strip_edges().to_upper())
	return bool((state["completed"] as Dictionary).get(tech_id, false))


func is_doctrine_key_unlocked(country_tag: String, doctrine_key: String) -> bool:
	var key := doctrine_key.strip_edges()
	if key.is_empty():
		return true
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	if key in (state["unlocked_doctrine_keys"] as Array):
		return true
	if typeof(LeaderManager) != TYPE_NIL:
		return LeaderManager.country_has_military_doctrine(tag, key)
	return false


func get_doctrine_xp(country_tag: String) -> int:
	return int(_ensure_country(country_tag.strip_edges().to_upper()).get("doctrine_xp", 0))


func get_era_swimlane_labels() -> Array[String]:
	var labels: Array[String] = []
	for lane in ERA_SWIMLANES:
		labels.append(str(lane.get("label", "")))
	return labels


func get_era_swimlane_keys() -> Array[String]:
	var keys: Array[String] = []
	for lane in ERA_SWIMLANES:
		keys.append(str(lane.get("key", "all")))
	return keys


func has_division_capability(country_tag: String, capability: String) -> bool:
	var state := _ensure_country(country_tag.strip_edges().to_upper())
	return capability in (state["division_capabilities"] as Array)


## Returns the list of factory/building types unlocked by technology for this country.
## Used by MapTechnologyContext and Production for build eligibility and map highlights.
func get_unlocked_factory_types(country_tag: String) -> Array[String]:
	var state := _ensure_country(country_tag.strip_edges().to_upper())
	var arr: Array = state.get("unlocked_factory_types", []) as Array
	var result: Array[String] = []
	for v in arr:
		result.append(str(v))
	return result


func get_technology_modifiers(country_tag: String) -> Dictionary:
	var state := _ensure_country(country_tag.strip_edges().to_upper())
	return (state.get("permanent_modifiers", {}) as Dictionary).duplicate()


## === Radio / Support tech effect helpers (for Supply, Combat, Map, Agents) ===
## These expose the concrete gameplay impact of the Support/Radio tree (and future support tech).
## Other systems should prefer these over raw get_technology_modifiers() when possible.
func get_effective_planning_speed(country_tag: String) -> float:
	if typeof(NationalModifierManager) == TYPE_NIL:
		return 0.0
	var mods := NationalModifierManager.get_combat_modifiers(country_tag)
	return float(mods.get("planning_speed", 0.0))


func get_effective_reconnaissance(country_tag: String) -> float:
	if typeof(NationalModifierManager) == TYPE_NIL:
		return 0.0
	var mods := NationalModifierManager.get_combat_modifiers(country_tag)
	var base := float(mods.get("reconnaissance", 0.0))

	# Airfield special sites provide additional reconnaissance (Phase 2)
	if typeof(MapManager) != TYPE_NIL:
		var air_recon := 0.0
		for pid in MapManager.get_provinces_by_owner(country_tag):
			var p := MapManager.get_province(pid)
			if p and p.has_special_site_of_type(SpecialSite.SiteType.AIRFIELD):
				var pe := MapManager.get_province_effects(pid, country_tag) if MapManager.has_method("get_province_effects") else null
				if pe and pe.has_method("get_special_site_air_recon_bonus"):
					air_recon += pe.get_special_site_air_recon_bonus()
		base += air_recon * 0.01  # Scale to match other recon values

	return base


## Public helper for map, production, and other systems to query tech unlocks without
## reaching directly into country_state.
##
## Usage examples:
##   if TechnologyManager.has_tech_unlock("GER", "factory_type", "tank_plant"): ...
##   if TechnologyManager.has_tech_unlock(tag, "agent_mission", "infiltrate_research_lab"): ...
##   if TechnologyManager.has_tech_unlock(tag, "division_capability", "motorized_logistics"): ...
##
## Supported unlock_types: "division_capability", "agent_mission", "doctrine_key",
## "rule_flag", "factory_type", "unit_design"
func has_tech_unlock(country_tag: String, unlock_type: String, value: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	match unlock_type:
		"division_capability":
			return value in (state.get("division_capabilities", []) as Array)
		"agent_mission":
			return value in (state.get("unlocked_agent_missions", []) as Array)
		"doctrine_key":
			return value in (state.get("unlocked_doctrine_keys", []) as Array)
		"rule_flag":
			return value in (state.get("rule_flags", []) as Array)
		"factory_type":
			return value in (state.get("unlocked_factory_types", []) as Array)
		"unit_design":
			return value in (state.get("unlocked_unit_designs", []) as Array)
		_:
			return false


# === Production gates (Phase B) ===

func get_design_availability(country_tag: String, template_id: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var tid := template_id.strip_edges()
	if tid.is_empty():
		return {"available": false, "reason": "Invalid design", "tech_id": "", "tech_name": ""}

	if not _gated_unit_designs.has(tid) and not _is_category_gated_for_template(tag, tid):
		return {"available": true, "reason": "", "tech_id": "", "tech_name": ""}

	if _gated_unit_designs.has(tid) and not _has_unlocked_design(tag, tid):
		return _lock_info_for_tech(str(_gated_unit_designs[tid]))

	var category := _template_production_category(tid)
	if _gated_production_categories.has(category) and not _has_unlocked_category(tag, category):
		var source_tech := _category_source_tech(tag, category)
		if not source_tech.is_empty():
			return _lock_info_for_tech(source_tech)
		return {
			"available": false,
			"reason": "Requires production research (%s)" % category,
			"tech_id": "",
			"tech_name": category.capitalize(),
		}

	return {"available": true, "reason": "", "tech_id": "", "tech_name": ""}


func is_unit_design_available(country_tag: String, template_id: String) -> bool:
	return bool(get_design_availability(country_tag, template_id).get("available", true))


func factory_can_build_design(country_tag: String, factory: Factory, template_id: String) -> Dictionary:
	var availability := get_design_availability(country_tag, template_id)
	if not bool(availability.get("available", false)):
		return {"allowed": false, "error": "tech_locked", "detail": availability}

	if factory == null:
		return {"allowed": false, "error": "no_factory", "detail": availability}

	var category := _template_production_category(template_id)
	var state := _ensure_country(country_tag.strip_edges().to_upper())
	var cats: Dictionary = state.get("unlocked_production_categories", {}) as Dictionary
	if cats.has(category):
		var req: Dictionary = cats[category] as Dictionary
		var min_type := str(req.get("min_factory_type", ""))
		if not min_type.is_empty() and not _factory_matches_type(factory, min_type):
			return {
				"allowed": false,
				"error": "wrong_factory_type",
				"detail": {
					"reason": "Requires %s factory" % min_type.replace("_", " "),
					"tech_id": str(req.get("source_tech", "")),
					"tech_name": _tech_display_name(str(req.get("source_tech", ""))),
				},
			}

	return {"allowed": true, "error": "", "detail": availability}


func has_rule_flag(country_tag: String, flag: String) -> bool:
	var state := _ensure_country(country_tag.strip_edges().to_upper())
	return flag in (state.get("rule_flags", []) as Array)


func is_factory_type_unlocked(country_tag: String, factory_type: String) -> bool:
	if factory_type.is_empty() or factory_type == "standard":
		return true
	var state := _ensure_country(country_tag.strip_edges().to_upper())
	return factory_type in (state.get("unlocked_factory_types", []) as Array)


func can_convert_factory_to_shipyard(country_tag: String) -> bool:
	return has_rule_flag(country_tag, "allow_port_shipyard_conversion")


func _on_research_completed_toast(country_tag: String, tech_id: String) -> void:
	if typeof(LeaderEventUI) == TYPE_NIL:
		return
	var player_tag := ""
	if typeof(LeaderManager) != TYPE_NIL:
		player_tag = LeaderManager.get_player_country_tag()
	if not player_tag.is_empty() and country_tag != player_tag:
		return
	var node: Dictionary = technology_nodes.get(tech_id, {}) as Dictionary
	var tech_name := str(node.get("name", tech_id))
	var ui: Dictionary = node.get("ui", {}) as Dictionary
	var effect := str(ui.get("short_effect", ""))
	var body := effect if not effect.is_empty() else "New production and capabilities are now available."
	LeaderEventUI.post_news("Research Complete: %s" % tech_name, body, "technology")


func _has_unlocked_design(tag: String, template_id: String) -> bool:
	var state := _ensure_country(tag)
	return template_id in (state.get("unlocked_unit_designs", []) as Array)


func _has_unlocked_category(tag: String, category: String) -> bool:
	var state := _ensure_country(tag)
	var cats: Dictionary = state.get("unlocked_production_categories", {}) as Dictionary
	return cats.has(category)


func _is_category_gated_for_template(tag: String, template_id: String) -> bool:
	var category := _template_production_category(template_id)
	return _gated_production_categories.has(category)


func _category_source_tech(tag: String, category: String) -> String:
	var state := _ensure_country(tag)
	var cats: Dictionary = state.get("unlocked_production_categories", {}) as Dictionary
	if not cats.has(category):
		return ""
	return str((cats[category] as Dictionary).get("source_tech", ""))


func _template_production_category(template_id: String) -> String:
	if typeof(GameData) == TYPE_NIL or GameData.design_data == null:
		return ""
	var template: UnitTemplate = GameData.design_data.get_template(template_id)
	if template == null:
		return ""
	return template.get_inferred_production_category()


func _factory_matches_type(factory: Factory, factory_type: String) -> bool:
	if factory == null:
		return false
	if factory.factory_type == factory_type:
		return true
	if factory_type == "shipyard" and factory.factory_type == "shipyard":
		return true
	if factory_type == "tank_plant":
		return factory.factory_type == "tank_plant"
	return false


func _lock_info_for_tech(tech_id: String) -> Dictionary:
	var name := _tech_display_name(tech_id)
	return {
		"available": false,
		"reason": "Requires: %s" % name,
		"tech_id": tech_id,
		"tech_name": name,
	}


func get_tech_display_name(tech_id: String) -> String:
	return _tech_display_name(tech_id)


func _tech_display_name(tech_id: String) -> String:
	if tech_id.is_empty():
		return "Unknown technology"
	var node: Dictionary = technology_nodes.get(tech_id, {}) as Dictionary
	return str(node.get("name", tech_id))


# === Research logic ===

func get_research_slots_max(country_tag: String) -> int:
	return int(_ensure_country(country_tag.strip_edges().to_upper()).get("research_slots", DEFAULT_RESEARCH_SLOTS))


func get_active_research_count(country_tag: String) -> int:
	return (_ensure_country(country_tag.strip_edges().to_upper())["active"] as Array).size()


func get_daily_rp(country_tag: String) -> float:
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	var total := BASE_RP_PER_DAY
	total += float(state.get("tech_intel_rp_bonus", 0.0))
	if typeof(NationalModifierManager) != TYPE_NIL:
		total += NationalModifierManager.get_national_modifier(tag, "research_speed")

	# Special Project sites give research speed (Phase 2)
	if typeof(MapManager) != TYPE_NIL:
		var special_bonus := 0.0
		for pid in MapManager.get_provinces_by_owner(tag):
			var p := MapManager.get_province(pid)
			if p:
				for site in p.special_sites:
					if site != null and site.is_completed() and site.site_type == SpecialSite.SiteType.SPECIAL_PROJECT:
						special_bonus += 5.0 * site.tier   # Tier 1 = +5 RP/day, Tier 2 = +10, etc.
		total += special_bonus

	return maxf(total, 0.1)


func get_effective_cost_days(node: Dictionary, year: int) -> float:
	var research: Dictionary = node.get("research", {}) as Dictionary
	var base := float(research.get("base_cost_days", 90.0))
	var era_min := int(node.get("era_min", year))
	if year < era_min:
		var years_early := era_min - year
		var penalty := float(research.get("ahead_of_time_penalty_per_year", 0.1))
		base *= 1.0 + penalty * float(years_early)
	return maxf(base, 1.0)


func get_node_status(country_tag: String, tech_id: String) -> String:
	var tag := country_tag.strip_edges().to_upper()
	if not technology_nodes.has(tech_id):
		return "unknown"
	if is_tech_compromised(tag, tech_id):
		return "compromised"
	var state := _ensure_country(tag)
	if bool((state["completed"] as Dictionary).get(tech_id, false)):
		return "completed"
	for slot in state["active"] as Array:
		if typeof(slot) == TYPE_DICTIONARY and str((slot as Dictionary).get("tech_id", "")) == tech_id:
			return "in_progress"
	if _is_research_blocked(tag, tech_id, state):
		return "locked"
	if can_research(tag, tech_id):
		return "available"
	return "locked"


func _is_research_blocked(tag: String, tech_id: String, state: Dictionary) -> bool:
	if not technology_nodes.has(tech_id):
		return true
	var node: Dictionary = technology_nodes[tech_id] as Dictionary
	for prereq in node.get("prerequisites", []) as Array:
		if not bool((state["completed"] as Dictionary).get(str(prereq), false)):
			return true
	for mutex_id in node.get("mutually_exclusive_with", []) as Array:
		if bool((state["completed"] as Dictionary).get(str(mutex_id), false)):
			return true
	return false


func can_research(country_tag: String, tech_id: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	if not technology_nodes.has(tech_id):
		return false
	var status := get_node_status(tag, tech_id)
	if status != "available":
		return false
	return get_active_research_count(tag) < get_research_slots_max(tag)


func start_research(country_tag: String, tech_id: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	if not can_research(tag, tech_id):
		return false
	var node: Dictionary = technology_nodes[tech_id] as Dictionary
	var total_days := get_effective_cost_days(node, _current_year)
	var state := _ensure_country(tag)
	var progress_start := 0.0
	var bank: Dictionary = state.get("stolen_progress_bank", {}) as Dictionary
	if bank.has(tech_id):
		progress_start = float(bank[tech_id])
		bank.erase(tech_id)
	(state["active"] as Array).append({
		"tech_id": tech_id,
		"progress_days": progress_start,
		"total_days": total_days,
	})
	research_started.emit(tag, tech_id)
	research_state_changed.emit(tag)
	return true


func cancel_research(country_tag: String, tech_id: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	var active: Array = state["active"]
	for i in range(active.size()):
		var slot: Dictionary = active[i] as Dictionary
		if str(slot.get("tech_id", "")) == tech_id:
			active.remove_at(i)
			research_state_changed.emit(tag)
			return true
	return false


func advance_research(days: float) -> void:
	if days <= 0.0:
		return
	for tag in country_state.keys():
		_tick_country_research(str(tag), days)


func _tick_country_research(tag: String, days: float) -> void:
	var state := _ensure_country(tag)
	var active: Array = state["active"]
	if active.is_empty():
		return
	var daily_rp := get_daily_rp(tag)
	var progress_delta := days * daily_rp
	var completed_ids: Array[String] = []
	for slot in active:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = slot as Dictionary
		entry["progress_days"] = float(entry.get("progress_days", 0.0)) + progress_delta
		if float(entry.get("progress_days", 0.0)) >= float(entry.get("total_days", 1.0)):
			completed_ids.append(str(entry.get("tech_id", "")))
	for tech_id in completed_ids:
		_complete_research(tag, tech_id)
	if not completed_ids.is_empty():
		research_state_changed.emit(tag)


func _complete_research(tag: String, tech_id: String) -> void:
	var state := _ensure_country(tag)
	var active: Array = state["active"]
	for i in range(active.size() - 1, -1, -1):
		if str((active[i] as Dictionary).get("tech_id", "")) == tech_id:
			active.remove_at(i)
			break
	(state["completed"] as Dictionary)[tech_id] = true
	var node: Dictionary = technology_nodes.get(tech_id, {}) as Dictionary
	var unlocks: Array = node.get("unlocks", []) as Array
	_unlock_registry.apply_unlocks(
		tag,
		tech_id,
		unlocks,
		state,
		func(country: String, tid: String, unlock: Dictionary) -> void:
			technology_unlocked.emit(country, tid, unlock),
	)
	research_completed.emit(tag, tech_id)
	_sync_doctrine_keys_to_leader_manager(tag)
	research_state_changed.emit(tag)


func _sync_doctrine_keys_to_leader_manager(country_tag: String) -> void:
	if typeof(LeaderManager) == TYPE_NIL:
		return
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	for key in state.get("unlocked_doctrine_keys", []) as Array:
		LeaderManager.set_country_military_doctrine(tag, str(key), true)


# === Screen data ===

func get_technology_screen_data(
	country_tag: String,
	domain_filter: String = "all",
	selected_tech_id: String = "",
	era_epoch_filter: String = "all",
) -> TechnologyScreenData:
	var tag := country_tag.strip_edges().to_upper()
	_ensure_country(tag)

	var data := TechnologyScreenData.new()
	data.country_tag = tag
	data.current_year = _current_year
	data.domain_filter = domain_filter
	data.research_slots_max = get_research_slots_max(tag)
	data.research_slots_used = get_active_research_count(tag)
	data.daily_rp = get_daily_rp(tag)
	data.daily_rp_tooltip = "Base %.1f RP/day (+ national modifiers)" % BASE_RP_PER_DAY
	data.active_research = _build_active_summaries(tag)
	data.domains_present = _domains_with_nodes()
	data.selected_tech_id = selected_tech_id
	data.era_epoch_filter = era_epoch_filter
	data.doctrine_xp = get_doctrine_xp(tag)
	data.doctrine_xp_hint = "Earned from combat and exercises (leader training uses leader XP)."
	data.doctrine_training_entries = get_doctrine_training_entries(tag)
	data.agent_tech_summary = get_agent_tech_summary(tag)
	var leader_pick := _pick_leader_for_training_paths(tag)
	data.primary_leader_id = leader_pick.get("leader_id", "")
	data.primary_leader_name = leader_pick.get("leader_name", "")

	var nodes: Array[Dictionary] = []
	for tech_id in technology_nodes.keys():
		var node: Dictionary = technology_nodes[tech_id] as Dictionary
		if not _node_matches_domain_filter(node, domain_filter):
			continue
		if not _node_matches_era_filter(node, era_epoch_filter):
			continue
		nodes.append(_node_to_summary(tag, tech_id, node))

	nodes.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var da := str(a.get("domain", ""))
			var db := str(b.get("domain", ""))
			if da != db:
				return da < db
			return int(a.get("tier", 0)) < int(b.get("tier", 0)),
	)
	data.research_entries = nodes
	for entry in nodes:
		match str(entry.get("status", "")):
			"available":
				data.available_count += 1
			"completed":
				data.completed_count += 1
			"in_progress":
				data.in_progress_count += 1
			"compromised":
				data.compromised_count += 1
			_:
				data.locked_count += 1

	if selected_tech_id.is_empty() and not nodes.is_empty():
		data.selected_tech_id = str(nodes[0].get("tech_id", ""))
	data.inspector = _build_inspector(tag, data.selected_tech_id)
	var graph := _build_graph_layout(tag, nodes)
	data.graph_nodes = graph.get("nodes", []) as Array[Dictionary]
	data.graph_edges = graph.get("edges", []) as Array[Dictionary]
	if typeof(MapTechnologyContext) != TYPE_NIL:
		data.map_integration_note = MapTechnologyContext.get_map_integration_note(tag)
		var preview: Dictionary = MapTechnologyContext.get_build_mode_preview(tag)
		data.map_build_mode_active = bool(preview.get("active", false))
		data.map_build_target_tech_id = str(preview.get("target_tech_id", ""))
		data.map_build_target_label = str(preview.get("target_label", ""))
		data.map_legend_bbcode = str(preview.get("legend_line", ""))
	return data


func get_doctrine_training_entries(country_tag: String) -> Array[Dictionary]:
	var tag := country_tag.strip_edges().to_upper()
	var entries: Array[Dictionary] = []
	if typeof(LeaderManager) == TYPE_NIL:
		return entries
	for path_id in LeaderManager.training_path_definitions.keys():
		var def: Dictionary = LeaderManager.get_training_path_definition(str(path_id))
		if def.is_empty():
			continue
		var requirement := str(def.get("doctrine_requirement", ""))
		var source_tech := _tech_id_for_doctrine_key(requirement)
		entries.append({
			"path_id": str(path_id),
			"name": str(def.get("name", path_id)),
			"description": str(def.get("description", "")),
			"doctrine_requirement": requirement,
			"doctrine_unlocked": is_doctrine_key_unlocked(tag, requirement),
			"unlock_tech_id": source_tech,
			"unlock_tech_name": _tech_display_name(source_tech),
			"max_level": int(def.get("max_level", 3)),
		})
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("name", "")) < str(b.get("name", "")),
	)
	return entries


func _tech_id_for_doctrine_key(doctrine_key: String) -> String:
	var key := doctrine_key.strip_edges()
	if key.is_empty():
		return ""
	for tech_id in technology_nodes.keys():
		var node: Dictionary = technology_nodes[tech_id] as Dictionary
		for raw in node.get("unlocks", []) as Array:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var unlock: Dictionary = raw as Dictionary
			if str(unlock.get("type", "")) == "doctrine_key" and str(unlock.get("key", "")) == key:
				return str(tech_id)
	return ""


func _pick_leader_for_training_paths(country_tag: String) -> Dictionary:
	if typeof(LeaderManager) == TYPE_NIL:
		return {}
	var leaders := LeaderManager.get_leaders_for_country(country_tag)
	for leader in leaders:
		if leader == null:
			continue
		if leader.is_active and not leader.is_dead:
			return {"leader_id": leader.id, "leader_name": leader.name}
	if leaders.size() > 0 and leaders[0] != null:
		return {"leader_id": leaders[0].id, "leader_name": leaders[0].name}
	return {}


func _build_graph_layout(tag: String, entries: Array[Dictionary]) -> Dictionary:
	var graph_nodes: Array[Dictionary] = []
	var graph_edges: Array[Dictionary] = []
	var state := _ensure_country(tag)
	var completed: Dictionary = state["completed"] as Dictionary

	for entry in entries:
		graph_nodes.append({
			"tech_id": str(entry.get("tech_id", "")),
			"name": str(entry.get("name", "")),
			"status": str(entry.get("status", "")),
			"column": int(entry.get("column", 0)),
			"row": int(entry.get("row", 0)),
			"progress_pct": float(entry.get("progress_pct", 0.0)),
		})

	for entry in entries:
		var tech_id := str(entry.get("tech_id", ""))
		if not technology_nodes.has(tech_id):
			continue
		for prereq in (technology_nodes[tech_id] as Dictionary).get("prerequisites", []) as Array:
			var pid := str(prereq)
			graph_edges.append({
				"from": pid,
				"to": tech_id,
				"satisfied": bool(completed.get(pid, false)),
			})

	return {"nodes": graph_nodes, "edges": graph_edges}


func _node_matches_era_filter(node: Dictionary, era_epoch_filter: String) -> bool:
	if era_epoch_filter == "all" or era_epoch_filter.is_empty():
		return true
	return str(node.get("epoch", "")) == era_epoch_filter


func _build_active_summaries(tag: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state := _ensure_country(tag)
	for slot in state["active"] as Array:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = slot as Dictionary
		var tech_id := str(entry.get("tech_id", ""))
		var node: Dictionary = technology_nodes.get(tech_id, {}) as Dictionary
		var total := float(entry.get("total_days", 1.0))
		var progress := float(entry.get("progress_days", 0.0))
		var left := maxf(total - progress, 0.0)
		var rp := get_daily_rp(tag)
		var eta := left / rp if rp > 0.01 else left
		result.append({
			"tech_id": tech_id,
			"name": str(node.get("name", tech_id)),
			"domain": str(node.get("domain", "")),
			"progress_days": progress,
			"total_days": total,
			"days_remaining": left,
			"eta_days": eta,
			"progress_pct": clampf(progress / total, 0.0, 1.0) if total > 0.0 else 0.0,
		})
	return result


func _node_to_summary(tag: String, tech_id: String, node: Dictionary) -> Dictionary:
	var status := get_node_status(tag, tech_id)
	var research: Dictionary = node.get("research", {}) as Dictionary
	var ui: Dictionary = node.get("ui", {}) as Dictionary
	var cost_days := get_effective_cost_days(node, _current_year)
	var progress_pct := 0.0
	var progress_days := 0.0
	var total_days := float(cost_days)
	var days_remaining := 0.0
	var eta_days := 0.0
	if status == "in_progress":
		var state := _ensure_country(tag)
		for slot in state["active"] as Array:
			var entry: Dictionary = slot as Dictionary
			if str(entry.get("tech_id", "")) == tech_id:
				total_days = maxf(float(entry.get("total_days", 1.0)), 1.0)
				progress_days = float(entry.get("progress_days", 0.0))
				progress_pct = clampf(progress_days / total_days, 0.0, 1.0)
				cost_days = int(round(total_days))
				days_remaining = maxf(total_days - progress_days, 0.0)
				var rp := get_daily_rp(tag)
				eta_days = days_remaining / rp if rp > 0.01 else days_remaining
				break
	return {
		"tech_id": tech_id,
		"name": str(node.get("name", tech_id)),
		"domain": str(node.get("domain", "")),
		"node_kind": str(node.get("node_kind", "research")),
		"tree_id": str(node.get("tree_id", "")),
		"column": int(node.get("column", 0)),
		"row": int(node.get("row", 0)),
		"epoch": str(node.get("epoch", "")),
		"tier": int(node.get("tier", 0)),
		"era_min": int(node.get("era_min", 0)),
		"era_max": int(node.get("era_max", 9999)),
		"category": str(research.get("category", "")),
		"cost_days": cost_days,
		"status": status,
		"progress_pct": progress_pct,
		"progress_days": progress_days,
		"total_days": total_days,
		"days_remaining": days_remaining,
		"eta_days": eta_days,
		"short_effect": str(ui.get("short_effect", "")),
		"flavor": str(ui.get("flavor", "")),
		"prerequisites": (node.get("prerequisites", []) as Array).duplicate(),
	}


func _build_inspector(tag: String, tech_id: String) -> Dictionary:
	if tech_id.is_empty() or not technology_nodes.has(tech_id):
		return {}
	var node: Dictionary = technology_nodes[tech_id] as Dictionary
	var status := get_node_status(tag, tech_id)
	var unlock_lines: PackedStringArray = []
	for raw in node.get("unlocks", []) as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		unlock_lines.append(_format_unlock_line(raw as Dictionary))
	var prereq_lines: PackedStringArray = []
	for prereq in node.get("prerequisites", []) as Array:
		var pid := str(prereq)
		var pname := str((technology_nodes.get(pid, {}) as Dictionary).get("name", pid))
		var done := is_tech_completed(tag, pid)
		prereq_lines.append("%s%s" % [pname, " ✓" if done else " ✗"])
	var progress_days := 0.0
	var total_days := float(get_effective_cost_days(node, _current_year))
	if status == "in_progress":
		var state := _ensure_country(tag)
		for slot in state["active"] as Array:
			var entry: Dictionary = slot as Dictionary
			if str(entry.get("tech_id", "")) == tech_id:
				progress_days = float(entry.get("progress_days", 0.0))
				total_days = maxf(float(entry.get("total_days", total_days)), 1.0)
				break
	var days_remaining := maxf(total_days - progress_days, 0.0)
	var progress_pct := clampf(progress_days / total_days, 0.0, 1.0) if total_days > 0.0 else 0.0
	var daily_rp := get_daily_rp(tag)
	var eta_days := days_remaining / daily_rp if daily_rp > 0.01 else days_remaining
	return {
		"tech_id": tech_id,
		"name": str(node.get("name", tech_id)),
		"status": status,
		"domain": str(node.get("domain", "")),
		"node_kind": str(node.get("node_kind", "")),
		"epoch": str(node.get("epoch", "")),
		"era_range": "%d–%d" % [int(node.get("era_min", 0)), int(node.get("era_max", 0))],
		"cost_days": int(round(total_days)),
		"progress_days": progress_days,
		"total_days": total_days,
		"days_remaining": days_remaining,
		"progress_pct": progress_pct,
		"eta_days": eta_days,
		"daily_rp": daily_rp,
		"can_start": can_research(tag, tech_id),
		"can_cancel": status == "in_progress",
		"short_effect": str((node.get("ui", {}) as Dictionary).get("short_effect", "")),
		"flavor": str((node.get("ui", {}) as Dictionary).get("flavor", "")),
		"unlock_lines": unlock_lines,
		"prerequisite_lines": prereq_lines,
		"agent_lines": get_tech_agent_inspector_lines(tag, tech_id),
	}


func _format_unlock_line(unlock: Dictionary) -> String:
	match str(unlock.get("type", "")):
		"modifier":
			return "+%s %s" % [unlock.get("value", 0), unlock.get("stat", "")]
		"doctrine_key":
			return "Unlock doctrine study: %s" % unlock.get("key", "")
		"division_capability":
			return "Division capability: %s" % unlock.get("capability", "")
		"agent_mission":
			return "Agent mission: %s" % unlock.get("mission_id", "")
		"unit_design":
			var ids: PackedStringArray = []
			for tid in _template_ids_from_unlock(unlock):
				ids.append(tid)
			return "Unit design: %s" % ", ".join(ids)
		"factory_type":
			return "Factory type: %s" % unlock.get("factory_type", "")
		"production_category":
			return "Production: %s (%s)" % [
				unlock.get("category", ""),
				unlock.get("min_factory_type", "any"),
			]
		"rule_flag":
			return "Rule: %s" % unlock.get("flag", "")
		_:
			return str(unlock.get("type", "unlock"))


func _node_matches_domain_filter(node: Dictionary, domain_filter: String) -> bool:
	var domain := str(node.get("domain", ""))
	if domain_filter == "all" or domain_filter.is_empty():
		return true
	if domain_filter == "doctrine":
		return domain in DOCTRINE_DOMAIN_IDS or str(node.get("node_kind", "")) == "doctrine"
	return domain == domain_filter


func _domains_with_nodes() -> Array[String]:
	var found: Dictionary = {}
	for node in technology_nodes.values():
		var n: Dictionary = node as Dictionary
		var domain := str(n.get("domain", ""))
		if domain in DOCTRINE_DOMAIN_IDS or str(n.get("node_kind", "")) == "doctrine":
			found["doctrine"] = true
		elif not domain.is_empty():
			found[domain] = true
	var result: Array[String] = ["all"]
	for domain_id in DOMAIN_ORDER:
		if domain_id == "all":
			continue
		if found.has(domain_id):
			result.append(domain_id)
	for domain_key in found.keys():
		var domain_str := str(domain_key)
		if domain_str not in result:
			result.append(domain_str)
	return result


func get_domain_tab_labels() -> Array[String]:
	var labels: Array[String] = []
	for domain_id in DOMAIN_ORDER:
		if domain_id == "all":
			labels.append("All")
		elif domain_id == "doctrine":
			labels.append("Doctrine")
		else:
			labels.append(domain_id.replace("_", " ").capitalize())
	return labels


func get_domain_tab_ids() -> Array[String]:
	return DOMAIN_ORDER.duplicate()


# === Agent / espionage integration (Phase D) ===

func is_tech_compromised(country_tag: String, tech_id: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	var compromised: Dictionary = _ensure_country(tag).get("compromised_tech", {}) as Dictionary
	if not compromised.has(tech_id):
		return false
	var entry: Dictionary = compromised[tech_id] as Dictionary
	return _current_year < int(entry.get("until_year", 0))


func has_theft_protection(country_tag: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	return _current_year <= int(_ensure_country(tag).get("tech_theft_protection_until", 0))


func is_theft_target(tech_id: String) -> bool:
	if not technology_nodes.has(tech_id):
		return false
	var agent_block: Dictionary = (technology_nodes[tech_id] as Dictionary).get("agent", {}) as Dictionary
	return bool(agent_block.get("theft_target", false))


func get_stealable_tech_targets(actor_tag: String, victim_tag: String) -> Array[Dictionary]:
	var actor := actor_tag.strip_edges().to_upper()
	var victim := victim_tag.strip_edges().to_upper()
	var entries: Array[Dictionary] = []
	for tech_id in technology_nodes.keys():
		if not is_theft_target(str(tech_id)):
			continue
		var victim_status := get_node_status(victim, str(tech_id))
		if victim_status in ["locked", "unknown"]:
			continue
		var node: Dictionary = technology_nodes[tech_id] as Dictionary
		entries.append({
			"tech_id": str(tech_id),
			"name": str(node.get("name", tech_id)),
			"victim_status": victim_status,
			"actor_status": get_node_status(actor, str(tech_id)),
			"tree_id": str(node.get("tree_id", "")),
		})
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("name", "")) < str(b.get("name", "")),
	)
	return entries


func mission_requires_tech_target(mission_id: String) -> bool:
	if typeof(AgentManager) == TYPE_NIL:
		return mission_id == "steal_research"
	var mission: Dictionary = AgentManager.get_mission_definition(mission_id)
	return bool(mission.get("target_tech_required", mission_id == "steal_research"))


func apply_research_theft_from_mission(
	actor_tag: String,
	victim_tag: String,
	tech_id: String,
	progress_days: float,
	detected: bool,
	source_detail: String = "",
) -> Dictionary:
	var actor := actor_tag.strip_edges().to_upper()
	var victim := victim_tag.strip_edges().to_upper()
	var tid := tech_id.strip_edges()
	if tid.is_empty():
		tid = _best_steal_target_for_actor(actor, victim)
	var result := {
		"tech_id": tid,
		"tech_name": _tech_display_name(tid),
		"actor_days_applied": 0.0,
		"victim_days_lost": 0.0,
		"compromised": false,
		"blocked_by_protection": false,
	}
	if tid.is_empty():
		return result

	var effective_days := progress_days
	if has_theft_protection(victim):
		effective_days *= 0.45
		result["blocked_by_protection"] = true

	result["actor_days_applied"] = _add_research_progress_days(actor, tid, effective_days)
	result["victim_days_lost"] = _steal_progress_from_victim(victim, tid, effective_days * 0.65)

	if detected:
		_set_tech_compromised(victim, tid, _current_year + 2, source_detail)
		result["compromised"] = true

	_log_agent_tech_operation(actor, {
		"kind": "theft",
		"tech_id": tid,
		"victim_tag": victim,
		"days": effective_days,
		"detected": detected,
		"detail": source_detail,
	})
	_log_agent_tech_operation(victim, {
		"kind": "theft_victim",
		"tech_id": tid,
		"actor_tag": actor,
		"days": effective_days,
		"detected": detected,
		"detail": source_detail,
	})
	agent_tech_state_changed.emit(actor)
	agent_tech_state_changed.emit(victim)
	research_state_changed.emit(actor)
	research_state_changed.emit(victim)
	return result


func apply_tech_intel_bonus(actor_tag: String, rp_bonus: float, source_detail: String = "") -> void:
	var tag := actor_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	state["tech_intel_rp_bonus"] = float(state.get("tech_intel_rp_bonus", 0.0)) + rp_bonus
	_log_agent_tech_operation(tag, {
		"kind": "intel_bonus",
		"bonus": rp_bonus,
		"detail": source_detail,
	})
	agent_tech_state_changed.emit(tag)
	research_state_changed.emit(tag)


func apply_tech_theft_protection(country_tag: String, years: int = 3, source_detail: String = "") -> void:
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	var until_year := _current_year + maxi(years, 1)
	state["tech_theft_protection_until"] = maxi(
		int(state.get("tech_theft_protection_until", 0)),
		until_year,
	)
	_log_agent_tech_operation(tag, {
		"kind": "protection",
		"until_year": until_year,
		"detail": source_detail,
	})
	agent_tech_state_changed.emit(tag)


func get_agent_tech_summary(country_tag: String) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	var active_missions: Array[Dictionary] = []
	var compromised_count := 0
	var compromised: Dictionary = state.get("compromised_tech", {}) as Dictionary
	for tech_key in compromised.keys():
		if is_tech_compromised(tag, str(tech_key)):
			compromised_count += 1

	if typeof(AgentManager) != TYPE_NIL:
		for agent in AgentManager.get_agents_for_country(tag):
			if agent == null or not agent.is_on_mission():
				continue
			var mission: Dictionary = AgentManager.get_mission_definition(agent.current_mission_id)
			if str(mission.get("category", "")) != "technology":
				continue
			active_missions.append({
				"agent_name": agent.name,
				"mission_name": str(mission.get("name", agent.current_mission_id)),
				"target_tag": agent.assigned_target_tag,
				"target_tech_id": agent.assigned_target_tech_id,
				"target_tech_name": _tech_display_name(agent.assigned_target_tech_id),
				"progress_pct": int(agent.mission_progress * 100.0),
			})

	var log: Array = state.get("agent_tech_log", []) as Array
	var recent: Array[Dictionary] = []
	for i in range(mini(log.size(), 5)):
		if typeof(log[i]) == TYPE_DICTIONARY:
			recent.append((log[i] as Dictionary).duplicate())

	return {
		"tech_intel_rp_bonus": float(state.get("tech_intel_rp_bonus", 0.0)),
		"theft_protection_active": has_theft_protection(tag),
		"theft_protection_until": int(state.get("tech_theft_protection_until", 0)),
		"compromised_tech_count": compromised_count,
		"active_tech_missions": active_missions,
		"recent_operations": recent,
		"stolen_bank_count": (state.get("stolen_progress_bank", {}) as Dictionary).size(),
	}


func get_tech_agent_inspector_lines(country_tag: String, tech_id: String) -> Array[String]:
	var tag := country_tag.strip_edges().to_upper()
	var lines: Array[String] = []
	if not is_theft_target(tech_id):
		lines.append("Not a priority target for foreign espionage.")
		return lines

	var agent_meta: Dictionary = (technology_nodes.get(tech_id, {}) as Dictionary).get("agent", {}) as Dictionary
	if str(agent_meta.get("intel_domain", "")) == "technology":
		lines.append("Technology intel target — agents can accelerate or steal progress.")

	if is_tech_compromised(tag, tech_id):
		var entry: Dictionary = (_ensure_country(tag)["compromised_tech"] as Dictionary)[tech_id] as Dictionary
		lines.append(
			"Compromised until %d — research halted (%s)"
			% [int(entry.get("until_year", 0)), entry.get("detail", "espionage")]
		)

	var bank: Dictionary = _ensure_country(tag).get("stolen_progress_bank", {}) as Dictionary
	if bank.has(tech_id):
		lines.append(
			"Banked stolen progress: %.0f days (applies when research starts)"
			% float(bank[tech_id])
		)

	if has_theft_protection(tag):
		lines.append("Research security heightened — theft effectiveness reduced.")

	if typeof(AgentManager) != TYPE_NIL:
		for agent in AgentManager.get_agents_for_country(tag):
			if agent == null or not agent.is_on_mission():
				continue
			if agent.assigned_target_tech_id == tech_id:
				lines.append("Friendly op: %s — %s" % [
					agent.name,
					AgentManager.get_mission_definition(agent.current_mission_id).get("name", ""),
				])
		for agent in AgentManager.get_agents_for_country(tag):
			if agent == null or not agent.is_on_mission():
				continue
			if (
				agent.assigned_target_tag == tag
				and agent.assigned_target_tech_id == tech_id
				and agent.country_tag != tag
			):
				lines.append("Hostile op incoming: %s (%s)" % [agent.name, agent.country_tag])

	return lines


func _best_steal_target_for_actor(actor_tag: String, victim_tag: String) -> String:
	var options := get_stealable_tech_targets(actor_tag, victim_tag)
	for entry in options:
		if str(entry.get("victim_status", "")) == "in_progress":
			return str(entry.get("tech_id", ""))
	for entry in options:
		if str(entry.get("victim_status", "")) == "available":
			return str(entry.get("tech_id", ""))
	if not options.is_empty():
		return str(options[0].get("tech_id", ""))
	return ""


func _add_research_progress_days(country_tag: String, tech_id: String, days: float) -> float:
	if days <= 0.0 or tech_id.is_empty():
		return 0.0
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	for slot in state["active"] as Array:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = slot as Dictionary
		if str(entry.get("tech_id", "")) == tech_id:
			entry["progress_days"] = float(entry.get("progress_days", 0.0)) + days
			return days
	var bank: Dictionary = state.get("stolen_progress_bank", {}) as Dictionary
	bank[tech_id] = float(bank.get(tech_id, 0.0)) + days
	return days


func _steal_progress_from_victim(victim_tag: String, tech_id: String, days: float) -> float:
	if days <= 0.0:
		return 0.0
	var tag := victim_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	var removed := 0.0
	for slot in state["active"] as Array:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = slot as Dictionary
		if str(entry.get("tech_id", "")) != tech_id:
			continue
		var before := float(entry.get("progress_days", 0.0))
		entry["progress_days"] = maxf(0.0, before - days)
		removed = before - float(entry["progress_days"])
		break
	return removed


func _set_tech_compromised(
	country_tag: String,
	tech_id: String,
	until_year: int,
	detail: String,
) -> void:
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	var compromised: Dictionary = state.get("compromised_tech", {}) as Dictionary
	compromised[tech_id] = {
		"until_year": until_year,
		"detail": detail,
		"since_year": _current_year,
	}


func _log_agent_tech_operation(country_tag: String, entry: Dictionary) -> void:
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	var log: Array = state.get("agent_tech_log", []) as Array
	var row := entry.duplicate()
	row["year"] = _current_year
	log.insert(0, row)
	while log.size() > 20:
		log.pop_back()


# === Scenario starting tech (Phase E) ===

func reset_for_scenario() -> void:
	country_state.clear()


func apply_scenario_starting_tech(
	scenario_name: String,
	country_tags: Array,
	start_year: int,
) -> void:
	reset_for_scenario()
	set_current_year(start_year)
	var pack := _load_starting_pack(scenario_name.strip_edges())
	var defaults: Dictionary = {}
	var per_country: Dictionary = {}
	if not pack.is_empty():
		defaults = pack.get("defaults", {}) as Dictionary
		per_country = pack.get("countries", {}) as Dictionary
	else:
		defaults = {"completed": ["basic_machine_tools"], "research_slots": DEFAULT_RESEARCH_SLOTS}
		push_warning(
			"TechnologyManager: No starting tech file for scenario '%s', using minimal defaults"
			% scenario_name
		)

	var applied := 0
	for raw_tag in country_tags:
		var tag := str(raw_tag).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var override: Dictionary = per_country.get(tag, {}) as Dictionary
		var entry := _merge_starting_entry(defaults, override)
		_apply_country_starting_entry(tag, entry)
		applied += 1
	print(
		"TechnologyManager: Applied starting tech for scenario '%s' (%d countries, year %d)"
		% [scenario_name, applied, start_year]
	)


func _load_starting_pack(scenario_name: String) -> Dictionary:
	var path := STARTING_DIR + scenario_name + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("TechnologyManager: Invalid starting tech JSON at %s" % path)
		return {}
	return parsed as Dictionary


func _merge_starting_entry(defaults: Dictionary, override: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	for key in override.keys():
		var value: Variant = override[key]
		if value is Array and out.get(key) is Array:
			var merged: Array = (out[key] as Array).duplicate()
			for item in value as Array:
				var s := str(item)
				if not s.is_empty() and s not in merged:
					merged.append(s)
			out[key] = merged
		else:
			out[key] = value
	return out


## === Save/Load support (SaveLoadManager extensibility contract) ===
## Returns the full mutable per-country research state. Trees and unlock registry
## are data-driven and rebuilt on _ready / apply.
func get_save_data() -> Dictionary:
	return {
		"country_state": country_state.duplicate(true),
		# _current_year is usually driven by TimeManager; include for robustness
		"current_year": _current_year,
	}

## Replaces research state and rebuilds derived indices. Call after scenario is loaded.
func apply_save_data(data: Dictionary) -> void:
	if data.has("country_state"):
		country_state = (data["country_state"] as Dictionary).duplicate(true)
	if data.has("current_year"):
		_current_year = int(data["current_year"])

	_rebuild_unlock_indices()

	# Notify listeners so TechnologyScreen, map context, etc. refresh
	for tag in country_state.keys():
		research_state_changed.emit(str(tag))


func _apply_country_starting_entry(country_tag: String, entry: Dictionary) -> void:
	var tag := country_tag.strip_edges().to_upper()
	var state := _ensure_country(tag)
	if entry.has("research_slots"):
		state["research_slots"] = maxi(int(entry["research_slots"]), 1)
	if entry.has("doctrine_xp"):
		state["doctrine_xp"] = maxi(int(entry["doctrine_xp"]), 0)

	for raw_key in entry.get("doctrine_keys_granted", []) as Array:
		var doctrine_key := str(raw_key).strip_edges()
		if doctrine_key.is_empty():
			continue
		var keys: Array = state["unlocked_doctrine_keys"] as Array
		if doctrine_key not in keys:
			keys.append(doctrine_key)

	var completed_ids: Array[String] = []
	for raw_id in entry.get("completed", []) as Array:
		var tech_id := str(raw_id).strip_edges()
		if not tech_id.is_empty():
			completed_ids.append(tech_id)
	_apply_completed_techs_in_order(tag, completed_ids)
	_sync_doctrine_keys_to_leader_manager(tag)


func _apply_completed_techs_in_order(country_tag: String, tech_ids: Array[String]) -> void:
	var pending := tech_ids.duplicate()
	for _attempt in range(32):
		if pending.is_empty():
			return
		var progressed := false
		for tech_id in pending.duplicate():
			if not technology_nodes.has(tech_id):
				push_warning(
					"TechnologyManager: Unknown starting tech '%s' for %s"
					% [tech_id, country_tag]
				)
				pending.erase(tech_id)
				continue
			if is_tech_completed(country_tag, tech_id):
				pending.erase(tech_id)
				progressed = true
				continue
			if not _starting_prerequisites_met(country_tag, tech_id):
				continue
			_grant_completed_tech_silent(country_tag, tech_id)
			pending.erase(tech_id)
			progressed = true
		if not progressed:
			for tech_id in pending:
				push_warning(
					"TechnologyManager: Could not grant starting tech '%s' for %s (missing prerequisites)"
					% [tech_id, country_tag]
				)
			return


func _starting_prerequisites_met(country_tag: String, tech_id: String) -> bool:
	var node: Dictionary = technology_nodes.get(tech_id, {}) as Dictionary
	for raw_prereq in node.get("prerequisites", []) as Array:
		var prereq_id := str(raw_prereq)
		if prereq_id.is_empty():
			continue
		if not is_tech_completed(country_tag, prereq_id):
			return false
	return true


func _grant_completed_tech_silent(country_tag: String, tech_id: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if is_tech_completed(tag, tech_id):
		return
	var state := _ensure_country(tag)
	(state["completed"] as Dictionary)[tech_id] = true
	var node: Dictionary = technology_nodes.get(tech_id, {}) as Dictionary
	var unlocks: Array = node.get("unlocks", []) as Array
	_unlock_registry.apply_unlocks(tag, tech_id, unlocks, state)
