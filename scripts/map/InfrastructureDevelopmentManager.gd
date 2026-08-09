# scripts/map/InfrastructureDevelopmentManager.gd
## Central manager for active provincial infrastructure and development projects.
##
## This is the implementation target for DESIGN_InfrastructureDevelopmentSystem.md (May 28, 2026).
## MVP goal: player (and later AI) can start "Invest" projects that raise province dev/infra over days/weeks,
## with full daily tick integration, engineer bonuses, agent sabotage interaction, tech modifiers,
## cost preview, save/load, and visible feedback in tooltips + InfoPanel.
##
## Register as autoload "InfrastructureDevelopmentManager" after MapManager and before heavy UI.
##
## Status: Phase A + Phase B core loop — daily ticks, Invest UI, PP spend, cancel, development,
## save/load, passive factory→dev growth, hostile capture cancel, light AI investment.

extends Node

signal project_started(project: ProvincialProject)
signal project_progress_updated(province_id: int, project: ProvincialProject, work_delta: float)
signal project_completed(province_id: int, new_level: int, axis: String, project: ProvincialProject)
signal project_cancelled(province_id: int, reason: String)
signal project_sabotaged(province_id: int, work_lost: float, severity: String)
signal political_power_changed(country_tag: String, new_amount: float)

# --- Inner data model (can be promoted to its own Resource later) ---
class ProvincialProject:
	var id: String = ""
	var province_id: int = 0
	var axis: String = "infrastructure"          # "infrastructure" | "development" | future "combined"
	var owner_tag: String = ""
	var starting_level: int = 1
	var target_level: int = 2
	var progress: float = 0.0                    # 0.0 – 100.0
	var work_per_day_base: float = 2.8
	var modifiers: Dictionary = {}               # "engineer": 0.9, "sabotage": -0.7, "tech": 0.25, "stability": 0.15, ...
	var political_power_cost: int = 45
	var start_day: int = 0
	var status: String = "active"                # active | paused | sabotaged | complete | cancelled

	func get_id() -> String:
		if id.is_empty():
			id = "proj_%s_%d_%s_%d" % [owner_tag, province_id, axis, Time.get_unix_time_from_system()]
		return id

	func get_current_work_per_day() -> float:
		var total := work_per_day_base
		for key in modifiers:
			total += float(modifiers[key])
		return maxf(0.05, total)

	func get_progress_percent() -> float:
		return clampf(progress, 0.0, 100.0)

	func get_remaining_work() -> float:
		return 100.0 - progress

	func get_eta_days() -> int:
		var daily := get_current_work_per_day()
		if daily <= 0.01:
			return 999
		return int(ceil(get_remaining_work() / daily))

	func to_save_dict() -> Dictionary:
		return {
			"id": id,
			"province_id": province_id,
			"axis": axis,
			"owner_tag": owner_tag,
			"starting_level": starting_level,
			"target_level": target_level,
			"progress": progress,
			"work_per_day_base": work_per_day_base,
			"modifiers": modifiers.duplicate(true),
			"political_power_cost": political_power_cost,
			"start_day": start_day,
			"status": status
		}

	static func from_save_dict(d: Dictionary) -> ProvincialProject:
		var p := ProvincialProject.new()
		p.id = d.get("id", "")
		p.province_id = int(d.get("province_id", 0))
		p.axis = d.get("axis", "infrastructure")
		p.owner_tag = d.get("owner_tag", "")
		p.starting_level = int(d.get("starting_level", 1))
		p.target_level = int(d.get("target_level", 2))
		p.progress = float(d.get("progress", 0.0))
		p.work_per_day_base = float(d.get("work_per_day_base", 2.8))
		p.modifiers = d.get("modifiers", {}).duplicate(true)
		p.political_power_cost = int(d.get("political_power_cost", 45))
		p.start_day = int(d.get("start_day", 0))
		p.status = d.get("status", "active")
		return p


# --- Runtime state ---
var active_projects: Dictionary = {}          # province_id (int) -> ProvincialProject
var _level_defs: Dictionary = {}              # lazy loaded from data/infrastructure/*.json
var _dev_level_defs: Dictionary = {}

## Lightweight Political Power ledger (MVP national resource for investment).
## Keys: country tag (upper) → float PP balance.
var political_power: Dictionary = {}
const PP_STARTING_BALANCE := 120.0
const PP_DAILY_REGEN := 2.5
const PP_REFUND_ON_CANCEL := 0.45
const PASSIVE_DEV_DAILY := 0.035
const AI_INVEST_INTERVAL_DAYS := 7
const AI_MAX_PROJECTS_PER_COUNTRY := 2

var _is_initialized: bool = false
var _ai_day_counter: int = 0


func _ready() -> void:
	_load_level_definitions()
	# Best-effort auto wire. Safe if TimeManager arrives later.
	call_deferred("_try_auto_initialize")


func _load_level_definitions() -> void:
	# MVP: load the two JSON files. Errors are non-fatal during early integration.
	var infra_path := "res://data/infrastructure/infra_levels.json"
	if ResourceLoader.exists(infra_path):
		var f := FileAccess.open(infra_path, FileAccess.READ)
		if f:
			var parser := JSON.new()
			if parser.parse(f.get_as_text()) == OK:
				_level_defs = parser.data
			f.close()

	var dev_path := "res://data/infrastructure/development_levels.json"
	if ResourceLoader.exists(dev_path):
		var f2 := FileAccess.open(dev_path, FileAccess.READ)
		if f2:
			var parser2 := JSON.new()
			if parser2.parse(f2.get_as_text()) == OK:
				_dev_level_defs = parser2.data
			f2.close()


## Call this once (e.g. from MapManager after it connects to TimeManager, or from TestRunner).
func initialize_with_time() -> void:
	if _is_initialized:
		return
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)
	_is_initialized = true
	print("InfrastructureDevelopmentManager: connected to daily tick.")

	# After (re)connecting to time, make sure any restored projects show their construction state on the map.
	refresh_all_project_visuals()


func _on_game_day_advanced(year: int, month: int, day: int) -> void:
	_regen_political_power_daily()
	advance_daily_projects(year, month, day)
	advance_passive_development_growth()
	_ai_day_counter += 1
	if _ai_day_counter % AI_INVEST_INTERVAL_DAYS == 0:
		advance_ai_investments()


func _current_game_day_index() -> int:
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		return TimeManager.get_total_days_elapsed()
	return 0


## === Public API (the contract other systems should use) ===

func has_active_project(province_id: int) -> bool:
	return active_projects.has(province_id)


func get_active_project(province_id: int) -> ProvincialProject:
	return active_projects.get(province_id)


func get_all_projects_for_country(country_tag: String) -> Array[ProvincialProject]:
	var tag := country_tag.strip_edges().to_upper()
	var result: Array[ProvincialProject] = []
	for proj in active_projects.values():
		if proj.owner_tag.to_upper() == tag:
			result.append(proj)
	return result


func can_start_project(
	province_id: int,
	axis: String,
	investor_tag: String,
	require_pp: bool = true,
) -> Dictionary:
	"""Returns { ok: bool, reason: String, cost_pp: int, eta_days: int, work_per_day: float }"""
	var result := {"ok": false, "reason": "", "cost_pp": 0, "eta_days": 0, "work_per_day": 0.0}

	if has_active_project(province_id):
		result.reason = "A project is already active in this province."
		return result

	var p: Province = null
	if typeof(MapManager) != TYPE_NIL:
		p = MapManager.get_province(province_id)
	if p == null:
		result.reason = "Province not found."
		return result

	var tag := investor_tag.strip_edges().to_upper()
	if p.owner_tag.to_upper() != tag and p.controller_tag.to_upper() != tag:
		result.reason = "You must control the province to invest in it."
		return result

	var current_level := p.infrastructure if axis == "infrastructure" else p.development_level
	var max_for_era := _get_era_max(tag, axis)

	if current_level >= max_for_era:
		result.reason = "Already at maximum level for current era (%d)." % max_for_era
		return result

	# MVP cost curve (tune aggressively in Phase B)
	var gap := 1  # always +1 for MVP simplicity
	var base_pp := 35 if axis == "infrastructure" else 28
	var cost := base_pp + (current_level * 6) + (gap * 8)
	result.cost_pp = cost

	# Rough work rate preview (will be refined with real engineer/tech/stability pulls)
	var preview_work := _calculate_base_work_rate(p, axis, tag)
	result.work_per_day = preview_work
	result.eta_days = int(ceil(100.0 / maxf(0.1, preview_work))) if preview_work > 0 else 60

	var pp_have := get_political_power(tag)
	result["pp_available"] = pp_have
	if require_pp and pp_have + 0.01 < float(cost):
		result.reason = "Need %d Political Power (have %.0f)." % [cost, pp_have]
		return result

	result.ok = true
	result.reason = "Ready to start %s investment toward level %d." % [axis, current_level + gap]
	return result


func start_infrastructure_project(
	province_id: int,
	target_level: int,
	investor_tag: String,
	spend_pp: bool = true,
) -> ProvincialProject:
	"""Main entry point from UI / AI. Returns the project or null on failure."""
	var tag := investor_tag.strip_edges().to_upper()
	ensure_political_power_seed(tag)
	var preview := can_start_project(province_id, "infrastructure", tag, spend_pp)
	if not preview.get("ok", false):
		push_warning("InfrastructureDevelopmentManager: cannot start project — %s" % preview.get("reason", "unknown"))
		return null

	var p: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	if p == null:
		return null

	var cost := int(preview.get("cost_pp", 45))
	if spend_pp and not spend_political_power(tag, float(cost)):
		push_warning("InfrastructureDevelopmentManager: insufficient PP for infra project")
		return null

	var proj := ProvincialProject.new()
	proj.province_id = province_id
	proj.axis = "infrastructure"
	proj.owner_tag = tag
	proj.starting_level = p.infrastructure
	proj.target_level = maxi(target_level, p.infrastructure + 1)
	proj.work_per_day_base = _calculate_base_work_rate(p, "infrastructure", proj.owner_tag)
	proj.political_power_cost = cost if spend_pp else 0
	proj.start_day = _current_game_day_index()
	proj.status = "active"

	# Seed initial modifiers (engineers already present give immediate bonus)
	_refresh_project_modifiers(proj, p)

	active_projects[province_id] = proj
	project_started.emit(proj)

	# Optional: immediately notify MapManager / visuals that this province is now "under construction"
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(province_id, "infrastructure_project")

	print("InfrastructureDevelopmentManager: started infra project on province %d (target %d) for %s" % [province_id, proj.target_level, proj.owner_tag])
	return proj


func start_development_project(
	province_id: int,
	target_level: int,
	investor_tag: String,
	spend_pp: bool = true,
) -> ProvincialProject:
	"""Start a development (+1 economic maturity) project."""
	var tag := investor_tag.strip_edges().to_upper()
	ensure_political_power_seed(tag)
	var preview := can_start_project(province_id, "development", tag, spend_pp)
	if not preview.get("ok", false):
		push_warning("InfrastructureDevelopmentManager: cannot start development — %s" % preview.get("reason", "unknown"))
		return null

	var p: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	if p == null:
		return null

	var cost := int(preview.get("cost_pp", 35))
	if spend_pp and not spend_political_power(tag, float(cost)):
		push_warning("InfrastructureDevelopmentManager: insufficient PP for development project")
		return null

	var proj := ProvincialProject.new()
	proj.province_id = province_id
	proj.axis = "development"
	proj.owner_tag = tag
	proj.starting_level = p.development_level
	proj.target_level = maxi(target_level, p.development_level + 1)
	proj.work_per_day_base = _calculate_base_work_rate(p, "development", proj.owner_tag)
	proj.political_power_cost = cost if spend_pp else 0
	proj.start_day = _current_game_day_index()
	proj.status = "active"
	_refresh_project_modifiers(proj, p)

	active_projects[province_id] = proj
	project_started.emit(proj)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(province_id, "infrastructure_project")

	print("InfrastructureDevelopmentManager: started development project on province %d → Lv.%d for %s" % [province_id, proj.target_level, tag])
	return proj


func cancel_project(province_id: int, reason: String = "player_cancelled") -> bool:
	if not active_projects.has(province_id):
		return false
	var proj: ProvincialProject = active_projects[province_id]
	proj.status = "cancelled"
	# Partial PP refund for voluntary cancel; none for hostile capture.
	if reason == "player_cancelled" or reason == "ai_cancelled":
		var refund := float(proj.political_power_cost) * PP_REFUND_ON_CANCEL * (1.0 - proj.progress / 100.0)
		if refund > 0.5:
			add_political_power(proj.owner_tag, refund)
	active_projects.erase(province_id)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(province_id, "infrastructure_project")
	project_cancelled.emit(province_id, reason)
	return true


## Called when a province changes controller mid-project (hostile capture cancels with no refund).
func on_province_captured(province_id: int, new_controller_tag: String) -> void:
	if not active_projects.has(province_id):
		return
	var proj: ProvincialProject = active_projects[province_id]
	var new_tag := new_controller_tag.strip_edges().to_upper()
	if proj.owner_tag.to_upper() == new_tag:
		return
	cancel_project(province_id, "hostile_capture")
	print("InfrastructureDevelopmentManager: project on %d cancelled — hostile capture by %s" % [province_id, new_tag])


## Called daily by the time signal (or manually from tests).
func advance_daily_projects(_year: int, _month: int, _day: int) -> void:
	if active_projects.is_empty():
		return

	var to_complete: Array = []

	for pid_var in active_projects.keys():
		var pid := int(pid_var)
		var proj: ProvincialProject = active_projects[pid]

		if proj.status != "active":
			continue

		var p: Province = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
		if p == null:
			continue

		# Re-evaluate modifiers every day (engineers can arrive/leave, new tech, new sabotage)
		_refresh_project_modifiers(proj, p)

		var work := proj.get_current_work_per_day()
		var before := proj.progress
		proj.progress = clampf(proj.progress + work, 0.0, 100.0)
		var delta := proj.progress - before

		if delta > 0.001:
			project_progress_updated.emit(pid, proj, delta)

		if proj.progress >= 100.0:
			to_complete.append({"pid": pid, "proj": proj})

	# Complete outside the iteration
	for item in to_complete:
		_complete_project(int(item.pid), item.proj)


func apply_sabotage_to_province(province_id: int, chip_amount: float, source: String = "agent_network") -> void:
	"""Called by AgentManager when an infrastructure_sabotage network does work in this province."""
	if not active_projects.has(province_id):
		return
	var proj: ProvincialProject = active_projects[province_id]
	var old_sab := float(proj.modifiers.get("sabotage", 0.0))
	proj.modifiers["sabotage"] = old_sab - absf(chip_amount)

	var work_lost := absf(chip_amount) * 0.6  # heuristic: sabotage hurts progress
	proj.progress = maxf(0.0, proj.progress - work_lost)

	project_sabotaged.emit(province_id, work_lost, source)

	if proj.progress < 5.0 and proj.status == "active":
		proj.status = "sabotaged"


## === Internal helpers (MVP — will grow) ===

func _calculate_base_work_rate(province: Province, axis: String, country_tag: String) -> float:
	var base := 2.6

	if axis == "infrastructure":
		base = 2.6
		if province != null:
			base += float(clampi(province.infrastructure, 0, 12)) * 0.06
	elif axis == "special_site":
		base = 2.2   # Slightly slower, more "major project" feel
		if province != null:
			base += float(clampi(province.infrastructure, 0, 12)) * 0.04
	else:
		base = 2.1

	# Very light stability / national modifier hook
	if typeof(NationalModifierManager) != TYPE_NIL and not country_tag.is_empty():
		var stab := float(NationalModifierManager.get_national_modifier(country_tag, "stability"))
		if stab > 0.0:
			base += stab * 0.8

	return maxf(0.8, base)


func _refresh_project_modifiers(proj: ProvincialProject, province: Province) -> void:
	proj.modifiers.clear()

	# Engineer bonus (reuse the excellent existing detection)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_engineer_brigades_in_province"):
		var eng := MapManager.get_engineer_brigades_in_province(proj.province_id, proj.owner_tag)
		if eng > 0.0:
			proj.modifiers["engineer"] = clampf(0.35 + eng * 0.28, 0.0, 1.4)

	# Tech / national construction speed (placeholder keys — wire real ones in Phase C)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var tech_speed := float(NationalModifierManager.get_national_modifier(proj.owner_tag, "construction_speed"))
		if tech_speed != 0.0:
			proj.modifiers["tech"] = tech_speed

	# Current sabotage from agent networks (the duel)
	if typeof(AgentManager) != TYPE_NIL:
		var net = AgentManager.networks.get(proj.province_id)
		if net != null and net.is_active() and net.focus == "infrastructure_sabotage":
			proj.modifiers["sabotage"] = -0.55  # tune in balance pass

	# Light stability effect (positive or negative)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var stab := float(NationalModifierManager.get_national_modifier(proj.owner_tag, "stability"))
		if absf(stab) > 0.05:
			proj.modifiers["stability"] = stab * 0.7


func _complete_project(province_id: int, proj: ProvincialProject) -> void:
	var p: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	if p == null:
		active_projects.erase(province_id)
		return

	var new_level := proj.target_level
	var axis := proj.axis

	if axis == "infrastructure":
		MapManager.update_province_infrastructure(province_id, new_level)
	elif axis == "development":
		MapManager.update_province_development(province_id, new_level)
	elif axis == "special_site":
		_complete_special_site_project(province_id, proj)
	else:
		# Fallback for unknown axes
		pass

	proj.status = "complete"
	active_projects.erase(province_id)

	project_completed.emit(province_id, new_level, axis, proj)

	# Rich toast / news hook (if NewsFeed or similar exists)
	# Use get_node_or_null to avoid parser errors for non-existent autoloads
	var news_feed = get_node_or_null("/root/NewsFeed")
	if news_feed != null:  # soft dependency
		# news_feed.add_entry(...) — implement when news system is ready
		pass

	print("InfrastructureDevelopmentManager: COMPLETED %s project on province %d → level %d for %s" % [axis, province_id, new_level, proj.owner_tag])


func _get_era_max(country_tag: String, axis: String) -> int:
	# MVP: read from the loaded JSON. Fall back to generous numbers.
	var defs := _level_defs if axis == "infrastructure" else _dev_level_defs
	if defs.has("era_max"):
		# We don't yet have per-country era detection here — use a safe default
		# In real integration, ask TechnologyManager or Scenario for current era band.
		var maxes: Dictionary = defs["era_max"]
		# Simple heuristic: 2026-ish games get modern cap
		return int(maxes.get("modern", 22))
	return 25 if axis == "infrastructure" else 18


## === Save / Load helpers (called by SaveLoadManager) ===

func get_save_data() -> Dictionary:
	var data := {
		"version": 2,
		"active_projects": {},
		"political_power": {},
	}
	for pid in active_projects.keys():
		var proj: ProvincialProject = active_projects[pid]
		data["active_projects"][str(pid)] = proj.to_save_dict()
	for tag in political_power.keys():
		data["political_power"][str(tag)] = float(political_power[tag])
	return data


func apply_loaded_data(data: Dictionary) -> void:
	active_projects.clear()
	political_power.clear()

	if data.has("political_power") and typeof(data["political_power"]) == TYPE_DICTIONARY:
		for tag in data["political_power"].keys():
			political_power[str(tag).to_upper()] = float(data["political_power"][tag])

	if not data.has("active_projects"):
		_notify_all_projects_for_visuals()
		return

	for pid_str in data["active_projects"].keys():
		var pid := int(pid_str)
		var d: Dictionary = data["active_projects"][pid_str]
		var proj := ProvincialProject.from_save_dict(d)
		active_projects[pid] = proj

	print("InfrastructureDevelopmentManager: restored %d active projects from save." % active_projects.size())
	_notify_all_projects_for_visuals()


## === Political Power (MVP national ledger) ===

func ensure_political_power_seed(country_tag: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return
	if not political_power.has(tag):
		political_power[tag] = PP_STARTING_BALANCE
		political_power_changed.emit(tag, PP_STARTING_BALANCE)


func get_political_power(country_tag: String) -> float:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return 0.0
	ensure_political_power_seed(tag)
	return float(political_power.get(tag, 0.0))


func add_political_power(country_tag: String, amount: float) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() or amount == 0.0:
		return
	ensure_political_power_seed(tag)
	political_power[tag] = float(political_power[tag]) + amount
	political_power_changed.emit(tag, float(political_power[tag]))


func spend_political_power(country_tag: String, amount: float) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() or amount <= 0.0:
		return true
	ensure_political_power_seed(tag)
	if float(political_power[tag]) + 0.01 < amount:
		return false
	political_power[tag] = float(political_power[tag]) - amount
	political_power_changed.emit(tag, float(political_power[tag]))
	return true


func _regen_political_power_daily() -> void:
	# Regen for every tag that already has a ledger entry, plus any active project owners.
	var tags: Dictionary = {}
	for t in political_power.keys():
		tags[str(t).to_upper()] = true
	for proj in active_projects.values():
		tags[str(proj.owner_tag).to_upper()] = true
	for tag in tags.keys():
		add_political_power(str(tag), PP_DAILY_REGEN)


## Factories running in a connected province slowly raise development (makes UI strings true).
func advance_passive_development_growth() -> void:
	if typeof(MapManager) == TYPE_NIL:
		return
	for pid in MapManager.get_all_provinces().keys():
		if has_active_project(int(pid)):
			continue
		var p: Province = MapManager.get_province(int(pid))
		if p == null:
			continue
		var factory_count := int(p.factories)
		if factory_count <= 0:
			continue
		# Skip heavily sabotaged provinces
		if typeof(AgentManager) != TYPE_NIL and "networks" in AgentManager:
			var net = AgentManager.networks.get(int(pid))
			if net != null and net.has_method("is_active") and net.is_active() and str(net.focus) == "infrastructure_sabotage":
				continue
		var gain := PASSIVE_DEV_DAILY * (1.0 + float(clampi(p.infrastructure, 0, 12)) * 0.04)
		gain *= clampf(0.5 + float(factory_count) * 0.25, 0.5, 2.0)
		var accum_key := "_passive_dev_progress"
		var accum := float(p.get_meta(accum_key, 0.0)) if p.has_meta(accum_key) else 0.0
		accum += gain
		if accum >= 1.0:
			var steps := int(floor(accum))
			accum -= float(steps)
			MapManager.update_province_development(int(pid), p.development_level + steps)
			p = MapManager.get_province(int(pid))
		if p != null:
			p.set_meta(accum_key, accum)


## AI: invest PP into owned high-value provinces lacking projects.
func advance_ai_investments() -> void:
	if typeof(MapManager) == TYPE_NIL:
		return
	var player := _player_country_tag()
	var by_country: Dictionary = {}  # tag -> Array[int] province ids
	for pid in MapManager.get_all_provinces().keys():
		var p: Province = MapManager.get_province(int(pid))
		if p == null:
			continue
		var tag := p.controller_tag.strip_edges().to_upper()
		if tag.is_empty():
			tag = p.owner_tag.strip_edges().to_upper()
		if tag.is_empty() or tag == player:
			continue
		if not by_country.has(tag):
			by_country[tag] = []
		by_country[tag].append(int(pid))

	for tag in by_country.keys():
		var owned: Array = by_country[tag]
		var active_count := get_all_projects_for_country(str(tag)).size()
		if active_count >= AI_MAX_PROJECTS_PER_COUNTRY:
			continue
		ensure_political_power_seed(str(tag))
		# Prefer higher VP / infra cores
		owned.sort_custom(func(a, b): return _ai_province_score(int(a)) > _ai_province_score(int(b)))
		for pid_var in owned:
			if active_count >= AI_MAX_PROJECTS_PER_COUNTRY:
				break
			var pid := int(pid_var)
			if has_active_project(pid):
				continue
			var p: Province = MapManager.get_province(pid)
			if p == null:
				continue
			# Prefer infra until mid levels, then development
			var axis := "infrastructure" if p.infrastructure < 8 else "development"
			var preview := can_start_project(pid, axis, str(tag))
			if not preview.get("ok", false):
				continue
			var started: ProvincialProject = null
			if axis == "infrastructure":
				started = start_infrastructure_project(pid, p.infrastructure + 1, str(tag), true)
			else:
				started = start_development_project(pid, p.development_level + 1, str(tag), true)
			if started != null:
				active_count += 1


func _ai_province_score(province_id: int) -> float:
	var p: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	if p == null:
		return 0.0
	return float(p.victory_points) * 3.0 + float(p.infrastructure) + float(p.development_level) * 1.5


func _player_country_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var t := str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
		if not t.is_empty():
			return t
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.get("player_tag"):
		return str(SupplyManager.player_tag).strip_edges().to_upper()
	return "USA"


## After restoring projects (especially on load), tell the map + UI to refresh construction visuals.
func _notify_all_projects_for_visuals() -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("notify_province_changed"):
		return
	for pid in active_projects.keys():
		MapManager.notify_province_changed(int(pid), "infrastructure_project")
		# Also bump the generic "effects" in case overlays are listening
		MapManager.notify_province_changed(int(pid), "effects")


## Public helper: forces map + InfoPanel to repaint any active project state.
## Call this after loading a save or when you want to force construction visuals to sync.
func refresh_all_project_visuals() -> void:
	_notify_all_projects_for_visuals()


## === Debug / Overlay Helper (for DebugOverlay + InfrastructureOverlayLayer) ===
## Returns a simple array of dicts describing all currently active projects.
## This is the method the DebugOverlay and map visual layers expect.
func get_all_active_projects() -> Array:
	var result := []
	for province_id in active_projects.keys():
		var proj: ProvincialProject = active_projects[province_id]
		var p: Province = null
		if typeof(MapManager) != TYPE_NIL:
			p = MapManager.get_province(int(province_id))

		result.append({
			"province_id": int(province_id),
			"province_name": p.name if p else str(province_id),
			"axis": proj.axis,
			"target_level": proj.target_level,
			"starting_level": proj.starting_level,
			"progress_percent": proj.get_progress_percent(),
			"eta_days": proj.get_eta_days(),
			"is_sabotaged": proj.modifiers.has("sabotage") and float(proj.modifiers.get("sabotage", 0.0)) < -0.1,
			"work_per_day": proj.get_current_work_per_day(),
			"owner_tag": proj.owner_tag
		})
	return result


## Returns 0.0–1.0 progress for a specific project (used by visual layers)
func get_project_progress(province_id: int) -> float:
	if not active_projects.has(province_id):
		return 0.0
	var proj: ProvincialProject = active_projects[province_id]
	return clampf(proj.progress / 100.0, 0.0, 1.0)


## Used by visual layers to choose warning color
func is_project_sabotaged(province_id: int) -> bool:
	if not active_projects.has(province_id):
		return false
	var proj: ProvincialProject = active_projects[province_id]
	return proj.modifiers.has("sabotage") and float(proj.modifiers.get("sabotage", 0.0)) < -0.1


# === Special Site Support (Phase 2 integration) ===

## Starts a construction project that will result in a SpecialSite when completed.
func start_special_site_project(province_id: int, site_id: String, investor_tag: String) -> ProvincialProject:
	var preview := can_start_project(province_id, "special_site", investor_tag)
	if not preview.get("ok", false):
		push_warning("Cannot start special site project: " + str(preview.get("reason")))
		return null

	var proj := ProvincialProject.new()
	proj.province_id = province_id
	proj.axis = "special_site"
	proj.owner_tag = investor_tag.strip_edges().to_upper()
	proj.starting_level = 0
	proj.target_level = 1
	proj.work_per_day_base = 2.5
	proj.political_power_cost = int(preview.get("cost_pp", 80))
	proj.status = "active"

	# Store the target special site definition
	proj.modifiers["special_site_id"] = site_id

	_refresh_project_modifiers(proj, MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null)

	active_projects[province_id] = proj
	project_started.emit(proj)

	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(province_id, "infrastructure_project")

	print("InfrastructureDevelopmentManager: Started special site project '%s' in province %d" % [site_id, province_id])
	return proj


## Called internally when a special_site project reaches 100%
func _complete_special_site_project(province_id: int, proj: ProvincialProject) -> void:
	var site_id: String = proj.modifiers.get("special_site_id", "")
	if site_id.is_empty():
		push_warning("Special site project completed with no site_id")
		# Robust recovery for demos, old projects, or partial data (prevents silent failure to create visible site)
		if proj.modifiers.has("special_site"):
			site_id = str(proj.modifiers["special_site"])
		elif province_id == 2 or province_id == 10:
			site_id = "airfield_tier_1" if province_id == 2 else "port_tier_2"
		if site_id.is_empty():
			return

	var province: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	if province == null:
		return

	# Prefer the dedicated manager if available (use node lookup for robustness)
	var site: SpecialSite = null
	var ssm = get_node_or_null("/root/SpecialSiteManager")
	if ssm and ssm.has_method("create_special_site"):
		site = ssm.create_special_site(site_id, province_id, proj.owner_tag)
	else:
		# Fallback inline creation
		site = SpecialSite.new()
		site.id = site_id
		site.province_id = province_id
		site.owner_tag = proj.owner_tag
		site.complete_construction()

	if site:
		province.add_special_site(site)
		if typeof(MapManager) != TYPE_NIL:
			MapManager.notify_province_changed(province_id, "special_site")

		print("InfrastructureDevelopmentManager: Completed special site '%s' in province %d" % [site_id, province_id])


## Creates a SpecialSite directly (used by debug tools and legacy paths)
func create_special_site(province_id: int, site_id: String, owner: String) -> SpecialSite:
	var province: Province = null
	if typeof(MapManager) != TYPE_NIL:
		province = MapManager.get_province(province_id)
	if province == null:
		return null

	var site: SpecialSite = null
	var ssm = get_node_or_null("/root/SpecialSiteManager")
	if ssm and ssm.has_method("create_special_site"):
		site = ssm.create_special_site(site_id, province_id, owner)
	else:
		site = SpecialSite.new()
		site.id = site_id
		site.province_id = province_id
		site.owner_tag = owner
		site.complete_construction()

	if site:
		province.add_special_site(site)
		if typeof(MapManager) != TYPE_NIL:
			MapManager.notify_province_changed(province_id, "special_site")

	return site


## Debug helper to instantly spawn a special site
func debug_spawn_special_site(province_id: int, site_id: String = "port_tier_2"):
	var site := create_special_site(province_id, site_id, "")
	if site and typeof(MapManager) != TYPE_NIL:
		MapManager.notify_province_changed(province_id, "special_site")
	print("Debug: Spawned special site '%s' in province %d" % [site_id, province_id])


## Debug: Start a real special site construction project (will complete over time or via boost)
func debug_start_special_site_project(province_id: int, site_id: String = "port_tier_2", investor: String = ""):
	if investor.is_empty():
		var p := MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
		investor = p.owner_tag if p else "USA"

	var proj := start_special_site_project(province_id, site_id, investor)
	if proj:
		print("Debug: Started special site construction project for %s in province %d" % [site_id, province_id])
	else:
		print("Debug: Failed to start special site project")


# === Upgrade Special Site Projects ===

func start_special_site_upgrade_project(province_id: int, current_site: SpecialSite, investor_tag: String) -> ProvincialProject:
	if current_site == null or not current_site.can_be_upgraded():
		return null

	var target_id := current_site.get_upgrade_target_id()
	var preview := can_start_project(province_id, "special_site_upgrade", investor_tag)
	if not preview.get("ok", false):
		return null

	var proj := ProvincialProject.new()
	proj.province_id = province_id
	proj.axis = "special_site_upgrade"
	proj.owner_tag = investor_tag.strip_edges().to_upper()
	proj.starting_level = current_site.tier
	proj.target_level = current_site.tier + 1
	proj.work_per_day_base = 2.0
	proj.political_power_cost = int(preview.get("cost_pp", 120))
	proj.status = "active"
	proj.modifiers["special_site_id"] = current_site.id
	proj.modifiers["upgrade_target_id"] = target_id
	proj.modifiers["site_instance"] = current_site   # reference for completion

	_refresh_project_modifiers(proj, MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null)

	active_projects[province_id] = proj
	project_started.emit(proj)

	if typeof(MapManager) != TYPE_NIL:
		MapManager.notify_province_changed(province_id, "special_site")

	return proj


func _complete_special_site_upgrade_project(province_id: int, proj: ProvincialProject) -> void:
	var site: SpecialSite = proj.modifiers.get("site_instance")
	var target_id: String = proj.modifiers.get("upgrade_target_id", "")

	if site == null or target_id.is_empty():
		return

	var province: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	if province == null:
		return

	# Create the upgraded site
	var upgraded_site: SpecialSite = null
	var ssm = get_node_or_null("/root/SpecialSiteManager")
	if ssm and ssm.has_method("create_special_site"):
		upgraded_site = ssm.create_special_site(target_id, province_id, proj.owner_tag)
	else:
		upgraded_site = SpecialSite.new()
		upgraded_site.id = target_id
		upgraded_site.province_id = province_id
		upgraded_site.owner_tag = proj.owner_tag
		upgraded_site.complete_construction()

	if upgraded_site:
		# Remove old site, add new one
		province.special_sites.erase(site)
		province.add_special_site(upgraded_site)

		if typeof(MapManager) != TYPE_NIL:
			MapManager.notify_province_changed(province_id, "special_site")

		print("Completed upgrade of special site %s → %s in province %d" % [site.id, target_id, province_id])


## Restore a single project (useful for targeted load paths or future migration).
## Prefer `apply_loaded_data` for full session restore.
func restore_project(province_id: int, project_data: Dictionary) -> bool:
	if typeof(project_data) != TYPE_DICTIONARY or project_data.is_empty():
		return false

	var proj := ProvincialProject.from_save_dict(project_data)
	proj.province_id = province_id  # ensure consistency
	active_projects[province_id] = proj

	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(province_id, "infrastructure_project")
		MapManager.notify_province_changed(province_id, "effects")

	return true


## Debug helpers
func debug_start_test_project(province_id: int, axis: String = "infrastructure") -> void:
	# Useful from TestRunner or console for rapid iteration
	var tag := "USA"
	if typeof(MapManager) != TYPE_NIL:
		var p := MapManager.get_province(province_id)
		if p:
			tag = p.owner_tag if not p.owner_tag.is_empty() else p.controller_tag
	start_infrastructure_project(province_id, 99, tag)  # will clamp via can_start logic in real version


func get_debug_summary() -> String:
	return "Active projects: %d" % active_projects.size()


func _try_auto_initialize() -> void:
	if _is_initialized:
		return
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)
		_is_initialized = true
		print("InfrastructureDevelopmentManager: auto-connected to daily tick.")


## === UI-Friendly Helpers (for InfoPanel, tooltips, etc.) ===

## Returns rich status for a province, safe to call from UI every frame.
func get_project_status(province_id: int) -> Dictionary:
	if not active_projects.has(province_id):
		var empty: Dictionary = {}
		return empty

	var proj: ProvincialProject = active_projects[province_id]
	var p: Province = null
	if typeof(MapManager) != TYPE_NIL:
		p = MapManager.get_province(province_id)

	return {
		"active": true,
		"axis": proj.axis,
		"progress": proj.progress,
		"eta_days": proj.get_eta_days(),
		"work_per_day": proj.get_current_work_per_day(),
		"target_level": proj.target_level,
		"starting_level": proj.starting_level,
		"owner": proj.owner_tag,
		"is_sabotaged": proj.modifiers.has("sabotage") and float(proj.modifiers["sabotage"]) < -0.1,
		"modifiers": proj.modifiers.duplicate(),
		"current_infra": p.infrastructure if p else 0,
		"current_dev": p.development_level if p else 0,
	}


## Convenience for the most common case (InfoPanel "Invest" button).
## Returns { success: bool, reason: String, project: ProvincialProject? }
func try_start_infrastructure_investment(province_id: int, investor_tag: String) -> Dictionary:
	ensure_political_power_seed(investor_tag)
	var preview := can_start_project(province_id, "infrastructure", investor_tag)
	if not preview.get("ok", false):
		return {
			"success": false,
			"reason": preview.get("reason", "Cannot start project"),
			"preview": preview,
			"pp_available": get_political_power(investor_tag),
		}

	var p_for_target: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	var cur := p_for_target.infrastructure if p_for_target else 1
	var tgt := cur + 1
	var proj := start_infrastructure_project(province_id, tgt, investor_tag, true)
	if proj == null:
		return {"success": false, "reason": "Failed to create project (internal error)"}

	return {
		"success": true,
		"reason": "Investment project started",
		"project": proj,
		"eta_days": proj.get_eta_days(),
		"cost_pp": preview.get("cost_pp", 0),
		"pp_remaining": get_political_power(investor_tag),
	}


func try_start_development_investment(province_id: int, investor_tag: String) -> Dictionary:
	ensure_political_power_seed(investor_tag)
	var preview := can_start_project(province_id, "development", investor_tag)
	if not preview.get("ok", false):
		return {
			"success": false,
			"reason": preview.get("reason", "Cannot start development"),
			"preview": preview,
			"pp_available": get_political_power(investor_tag),
		}

	var p_for_target: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	var cur := p_for_target.development_level if p_for_target else 1
	var tgt := cur + 1
	var proj := start_development_project(province_id, tgt, investor_tag, true)
	if proj == null:
		return {"success": false, "reason": "Failed to create development project"}

	return {
		"success": true,
		"reason": "Development project started",
		"project": proj,
		"eta_days": proj.get_eta_days(),
		"cost_pp": preview.get("cost_pp", 0),
		"pp_remaining": get_political_power(investor_tag),
	}


func try_cancel_project(province_id: int, requester_tag: String) -> Dictionary:
	if not active_projects.has(province_id):
		return {"success": false, "reason": "No active project"}
	var proj: ProvincialProject = active_projects[province_id]
	var tag := requester_tag.strip_edges().to_upper()
	if proj.owner_tag.to_upper() != tag:
		return {"success": false, "reason": "Only the investing country can cancel"}
	var ok := cancel_project(province_id, "player_cancelled")
	return {
		"success": ok,
		"reason": "Project cancelled" if ok else "Cancel failed",
		"pp_remaining": get_political_power(tag),
	}


## Returns true if we should show the "Invest" button for this province (player owns it, not at cap, etc.)
func should_show_investment_button(province_id: int, player_tag: String) -> bool:
	if has_active_project(province_id):
		return true  # show disabled "In Progress" state

	var p: Province = null
	if typeof(MapManager) != TYPE_NIL:
		p = MapManager.get_province(province_id)
	if p == null:
		return false

	var tag := player_tag.strip_edges().to_upper()
	if tag.is_empty():
		return false
	if p.owner_tag.to_upper() != tag and p.controller_tag.to_upper() != tag:
		return false

	# Don't offer on very low-value provinces (optional taste)
	if p.infrastructure >= 20 or p.development_level >= 14:
		return false

	return true
