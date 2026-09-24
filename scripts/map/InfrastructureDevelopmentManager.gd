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
## Status: Phase A/B/C complete + polish for 50+ turn integrated playtest (inspector full w/ bar/cancel/ETA/modifiers; map active-project visuals; AI auto-invest daily+harness; persist; toasts; pop/econ wire on complete; balance gates). Wired globally + signals. Ready.

extends Node

signal project_started(project: ProvincialProject)
signal project_progress_updated(province_id: int, project: ProvincialProject, work_delta: float)
signal project_completed(province_id: int, new_level: int, axis: String, project: ProvincialProject)
signal project_cancelled(province_id: int, reason: String)
signal project_sabotaged(province_id: int, work_lost: float, severity: String)

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
	var days_remaining: int = 0                  # daily tick clock (save + AI/player progress)
	var status: String = "active"                # active | paused | sabotaged | complete | cancelled
	var build_road_spine: bool = false           # IX-1: complete also writes built_road_neighbors
	var spine_neighbor_ids: Array[int] = []

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
		if days_remaining > 0:
			return days_remaining
		var daily := get_current_work_per_day()
		if daily <= 0.01:
			return 999
		return int(ceil(get_remaining_work() / daily))

	func to_save_dict() -> Dictionary:
		return {
			"id": id,
			"province_id": province_id,
			"pid": province_id,
			"axis": axis,
			"kind": axis,
			"owner_tag": owner_tag,
			"tag": owner_tag,
			"starting_level": starting_level,
			"target_level": target_level,
			"progress": progress,
			"work_per_day_base": work_per_day_base,
			"modifiers": modifiers.duplicate(true),
			"political_power_cost": political_power_cost,
			"start_day": start_day,
			"days_remaining": days_remaining,
			"status": status,
			"build_road_spine": build_road_spine,
			"spine_neighbor_ids": spine_neighbor_ids.duplicate()
		}

	static func from_save_dict(d: Dictionary) -> ProvincialProject:
		var p := ProvincialProject.new()
		p.id = d.get("id", "")
		p.province_id = int(d.get("province_id", d.get("pid", 0)))
		p.axis = str(d.get("axis", d.get("kind", "infrastructure")))
		p.owner_tag = str(d.get("owner_tag", d.get("tag", "")))
		p.starting_level = int(d.get("starting_level", 1))
		p.target_level = int(d.get("target_level", 2))
		p.progress = float(d.get("progress", 0.0))
		p.work_per_day_base = float(d.get("work_per_day_base", 2.8))
		p.modifiers = d.get("modifiers", {}).duplicate(true)
		p.political_power_cost = int(d.get("political_power_cost", 45))
		p.start_day = int(d.get("start_day", 0))
		p.days_remaining = int(d.get("days_remaining", d.get("days_left", 0)))
		p.status = d.get("status", "active")
		p.build_road_spine = bool(d.get("build_road_spine", false))
		var raw_n: Variant = d.get("spine_neighbor_ids", [])
		if raw_n is Array:
			p.spine_neighbor_ids = Array(raw_n, TYPE_INT, "", null)
		return p


# --- Runtime state ---
var active_projects: Dictionary = {}          # province_id (int) -> ProvincialProject
var _level_defs: Dictionary = {}              # lazy loaded from data/infrastructure/*.json
var _dev_level_defs: Dictionary = {}

var _is_initialized: bool = false
var _ai_infra_budget_day: int = -1
var _ai_infra_starts_today: int = 0
## Test / gate counters — live F5 must keep these at 0 / tiny.
var _full_board_ai_invest_calls: int = 0
var _ai_infra_provinces_considered: int = 0
const AI_INFRA_PICK_CAP := 8

# IX-1 Road Spine (Rhineland Bonn–Köln–Leverkusen). Spec is the source of IDs.
const IX1_SPEC_PATH := "res://data/infrastructure/ix1_road_spine.json"
const IX1_FALLBACK_HUB := 710417
const IX1_FALLBACK_CORRIDOR: Array[int] = [710416, 710417, 710418]
## First-session interconnect grant. Fresh Begin · Germany · 1936 has Mandate 0;
## generic Köln Invest is 73 and stays gated. IX-1 uses this starter cost only.
const IX1_FIRST_SESSION_MANDATE_COST := 0
var _ix1_spec: Dictionary = {}


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
	advance_daily_projects(year, month, day)


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


func can_start_project(province_id: int, axis: String, investor_tag: String) -> Dictionary:
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

	# Stability gate per DESIGN (low/unstable < ~30 makes projects risky or blocked for flavor + balance)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var stab := float(NationalModifierManager.get_national_modifier(tag, "stability"))
		if stab < -0.35:  # very negative stability blocks (unrest, strikes)
			result.reason = "National stability too low for major investment (%.0f%%)." % (stab * 100.0 + 50.0)
			return result
		if stab < 0.0:
			# light warning in preview (slows via modifiers anyway)
			pass

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

	var active_for_country := _count_active_projects_for(tag)
	var capacity := _national_construction_capacity(tag)
	if active_for_country >= capacity:
		result.reason = "National construction capacity reached (%d/%d active projects)." % [active_for_country, capacity]
		return result
	if cost > _available_political_power(tag):
		result.reason = "Insufficient political power (need %d, have ~%d)." % [cost, _available_political_power(tag)]
		return result

	result.ok = true
	result.reason = "Ready to start %s investment toward level %d." % [axis, current_level + gap]
	return result


func start_infrastructure_project(province_id: int, target_level: int, investor_tag: String) -> ProvincialProject:
	"""Main entry point from UI / AI. Returns the project or null on failure."""
	var preview: Dictionary = can_start_project(province_id, "infrastructure", investor_tag)
	if not preview.get("ok", false):
		push_warning("InfrastructureDevelopmentManager: cannot start project — %s" % preview.get("reason", "unknown"))
		return null

	var p: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	if p == null:
		return null

	var proj := ProvincialProject.new()
	proj.province_id = province_id
	proj.axis = "infrastructure"
	proj.owner_tag = investor_tag.strip_edges().to_upper()
	proj.starting_level = p.infrastructure
	proj.target_level = target_level
	proj.work_per_day_base = _calculate_base_work_rate(p, "infrastructure", proj.owner_tag)
	proj.political_power_cost = int(preview.get("cost_pp", 45))
	proj.start_day = _current_game_day_index()
	proj.status = "active"

	# Seed initial modifiers (engineers already present give immediate bonus)
	_refresh_project_modifiers(proj, p)
	proj.days_remaining = maxi(1, proj.get_eta_days())

	active_projects[province_id] = proj
	project_started.emit(proj)

	# Live F5 / softpipe: remote AI invest must not toast or notify (toast panels +
	# province_data_changed → riot/fill dirty a 3520-poly canvas and wedge the clock).
	if not _should_quiet_ai_infra_start(proj.owner_tag):
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
			MapManager.notify_province_changed(province_id, "infrastructure_project")
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			var prov: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
			var pname := prov.name if prov else str(province_id)
			LeaderEventUI.post_news("Investment Started", "%s begins infrastructure project in %s (target level %d)." % [proj.owner_tag, pname, target_level], "infrastructure")

	print("InfrastructureDevelopmentManager: started infra project on province %d (target %d) for %s" % [province_id, target_level, proj.owner_tag])
	return proj


func cancel_project(province_id: int, reason: String = "player_cancelled") -> bool:
	if not active_projects.has(province_id):
		return false
	var proj: ProvincialProject = active_projects[province_id]
	proj.status = "cancelled"
	active_projects.erase(province_id)
	project_cancelled.emit(province_id, reason)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(province_id, "infrastructure_project")
		MapManager.notify_province_changed(province_id, "effects")
	return true


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
		# Tick progress even if the hex is not on this tree (headless -s / mid-load).
		# Missing province only skips modifier refresh + map complete.
		if p != null:
			_refresh_project_modifiers(proj, p)

		var work := proj.get_current_work_per_day()
		var before := proj.progress
		proj.progress = clampf(proj.progress + work, 0.0, 100.0)
		var delta := proj.progress - before

		if proj.days_remaining <= 0:
			proj.days_remaining = maxi(1, proj.get_eta_days())
		proj.days_remaining = maxi(0, proj.days_remaining - 1)

		if delta > 0.001:
			project_progress_updated.emit(pid, proj, delta)
			# Light event feedback for playability (avoid spam; only on significant chunks or high %).
			if (int(proj.progress) % 25 == 0 or proj.progress > 90) and typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				var pname := p.name if p else str(pid)
				LeaderEventUI.show_toast("%s infra project ~%d%% complete (ETA %d days)" % [pname, int(proj.progress), proj.get_eta_days()], 2.0)

		if proj.progress >= 100.0 or proj.days_remaining <= 0:
			to_complete.append({"pid": pid, "proj": proj})

	# Complete outside the iteration
	for item in to_complete:
		_complete_project(int(item.pid), item.proj)

	# Full-board AI invest scan is 3520×N and only runs because a project is active.
	# F5 already budgets 1 AI infra start/day via try_ai_start_infra_project — do not
	# turn an IX-1 spine into a continent mesh consider. Headless/harness keep the scan.
	if _should_run_full_board_ai_invest() and randi() % 5 == 0:
		ai_consider_daily_invests([], 0.08)


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

	# Event hook: sabotage is agent-driven, surface as news for player (Hidden Hand flavor).
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		var prov: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
		var pname := prov.name if prov else str(province_id)
		LeaderEventUI.post_news("Infrastructure Sabotaged", "Project in %s hit by %s (%.1f work lost). Progress set back." % [pname, source, work_lost], "sabotage")


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

	# Regional control build speed (full control of industrial regions e.g. Western Germany gives infrastructure_build_speed bonus; wired as next step for scenario connections)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
		var reg := MapManager.get_active_regional_control_bonuses(proj.owner_tag)
		var build_sp := float(reg.get("infrastructure_build_speed", 0.0))
		if build_sp != 0.0:
			proj.modifiers["regional"] = build_sp

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

	if proj.build_road_spine:
		link_ix1_road_spine_edges(province_id, proj.spine_neighbor_ids)

	# Wire to pop/econ (per goals + DESIGN): infra upgrade attracts population (industrialization pull) + labor for future production.
	# Uses direct mutate + notify (pop is runtime in Province; settlement also boosted for org/attrit/supply combat payoff).
	if p.population > 0:
		var pop_influx := maxi(800, int(p.population * 0.012 + new_level * 180))
		p.population += pop_influx
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(province_id, "population")
	# Also nudge settlement for immediate "our industrial heartland grows" (ties to existing 2.5%/sett combat def etc).
	if p.settlement_level < 3.0:
		p.settlement_level = clampf(p.settlement_level + 0.04, 0.0, 5.0)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
			MapManager.notify_province_changed(province_id, "settlement")

	proj.status = "complete"
	active_projects.erase(province_id)

	project_completed.emit(province_id, new_level, axis, proj)

	# Flesh out events: post news + toast on infra complete (player-visible payoff for investment; ties to supply/combat width/org recovery).
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		var prov: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
		var pname := prov.name if prov else str(province_id)
		if proj.build_road_spine:
			LeaderEventUI.post_news(
				"IX-1 Road Spine Complete",
				"Road spine finished in %s (infra %d). Corridor edges painted; move/supply on the spine is cheaper." % [pname, new_level],
				"infrastructure",
			)
			if LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Road spine complete in %s · infra %d · edges live" % [pname, new_level], 4.0)
		else:
			LeaderEventUI.post_news("Infrastructure Complete", "%s project finished in %s (now level %d). Local supply, org recovery, and combat width improved for %s." % [axis.capitalize(), pname, new_level, proj.owner_tag], "infrastructure")
			if LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Investment complete in %s: %s now level %d" % [pname, axis, new_level], 4.0)

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
		"version": 1,
		"active_projects": {}
	}
	for pid in active_projects.keys():
		var proj: ProvincialProject = active_projects[pid]
		data["active_projects"][str(pid)] = proj.to_save_dict()
	return data


func apply_loaded_data(data: Dictionary) -> void:
	active_projects.clear()
	if not data.has("active_projects"):
		_notify_all_projects_for_visuals()
		return

	for pid_str in data["active_projects"].keys():
		var pid := int(pid_str)
		var d: Dictionary = data["active_projects"][pid_str]
		var proj := ProvincialProject.from_save_dict(d)
		if proj.days_remaining <= 0:
			proj.days_remaining = maxi(1, proj.get_eta_days())
		active_projects[pid] = proj

	print("InfrastructureDevelopmentManager: restored %d active projects from save." % active_projects.size())
	_notify_all_projects_for_visuals()


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
			"days_remaining": proj.days_remaining,
			"is_sabotaged": proj.modifiers.has("sabotage") and float(proj.modifiers.get("sabotage", 0.0)) < -0.1,
			"work_per_day": proj.get_current_work_per_day(),
			"owner_tag": proj.owner_tag,
			"tag": proj.owner_tag,
			"kind": proj.axis
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
	var preview: Dictionary = can_start_project(province_id, "special_site", investor_tag)
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
	var preview: Dictionary = can_start_project(province_id, "special_site_upgrade", investor_tag)
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
		"days_remaining": proj.days_remaining,
		"work_per_day": proj.get_current_work_per_day(),
		"target_level": proj.target_level,
		"starting_level": proj.starting_level,
		"owner": proj.owner_tag,
		"is_sabotaged": proj.modifiers.has("sabotage") and float(proj.modifiers["sabotage"]) < -0.1,
		"modifiers": proj.modifiers.duplicate(),
		"current_infra": p.infrastructure if p else 0,
		"current_dev": p.development_level if p else 0,
		"build_road_spine": proj.build_road_spine,
		"spine_neighbor_ids": proj.spine_neighbor_ids.duplicate(),
	}


## Convenience for the most common case (InfoPanel "Invest" button).
## Returns { success: bool, reason: String, project: ProvincialProject? }
func try_start_infrastructure_investment(province_id: int, investor_tag: String) -> Dictionary:
	var preview: Dictionary = can_start_project(province_id, "infrastructure", investor_tag)
	if not preview.get("ok", false):
		return {
			"success": false,
			"reason": preview.get("reason", "Cannot start project"),
			"preview": preview
		}

	# Real Political Power / Mandate spend (high-value wiring for player investment loop)
	var pp_cost := int(preview.get("cost_pp", 0))
	if typeof(GameData) != TYPE_NIL:
		# Validate Mandate (primary for infra)
		var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
		var current_mand := int(ps.get("mandate", {}).get(investor_tag, 0))
		if current_mand < pp_cost:
			return {"success": false, "reason": "Insufficient Mandate (%d < %d)" % [current_mand, pp_cost], "preview": preview}
		# Spend Mandate (primary for infra); small Ascendancy cost
		GameData.apply_pillar_shift(investor_tag, "mandate", -pp_cost, "infra_invest_" + str(province_id))
		# Optional small ascendancy cost/gain
		GameData.apply_pillar_shift(investor_tag, "ascendancy", -int(pp_cost * 0.3), "infra_invest_prestige")

	# Compute sensible target (current +1 for MVP)
	var p_for_target: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	var cur := p_for_target.infrastructure if p_for_target else 1
	var tgt := cur + 1
	var proj := start_infrastructure_project(province_id, tgt, investor_tag)
	if proj == null:
		return {"success": false, "reason": "Failed to create project (internal error)"}

	return {
		"success": true,
		"reason": "Investment project started",
		"project": proj,
		"eta_days": proj.get_eta_days(),
		"cost_pp": preview.get("cost_pp", 0)
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


## === IX-1 Road Spine (Rhineland Bonn 710416 — Köln 710417 — Leverkusen 710418) ===

func _ix1_spec_dict() -> Dictionary:
	if not _ix1_spec.is_empty():
		return _ix1_spec
	if ResourceLoader.exists(IX1_SPEC_PATH):
		var f := FileAccess.open(IX1_SPEC_PATH, FileAccess.READ)
		if f:
			var parser := JSON.new()
			if parser.parse(f.get_as_text()) == OK and parser.data is Dictionary:
				_ix1_spec = parser.data
			f.close()
	if _ix1_spec.is_empty():
		_ix1_spec = {
			"hub_id": IX1_FALLBACK_HUB,
			"corridor_ids": IX1_FALLBACK_CORRIDOR.duplicate(),
			"edges": [[710417, 710416], [710417, 710418]],
			"owner_tag": "GER",
		}
	return _ix1_spec


func get_ix1_corridor_ids() -> Array[int]:
	var spec := _ix1_spec_dict()
	var out: Array[int] = []
	var raw: Variant = spec.get("corridor_ids", IX1_FALLBACK_CORRIDOR)
	if raw is Array:
		for v in raw:
			var pid := int(v)
			if pid > 0 and pid not in out:
				out.append(pid)
	if out.is_empty():
		return IX1_FALLBACK_CORRIDOR.duplicate()
	return out


func is_ix1_road_spine_province(province_id: int) -> bool:
	return province_id in get_ix1_corridor_ids()


func get_ix1_spine_neighbors(province_id: int) -> Array[int]:
	var spec := _ix1_spec_dict()
	var out: Array[int] = []
	var raw: Variant = spec.get("edges", [])
	if raw is Array:
		for pair in raw:
			if pair is Array and pair.size() >= 2:
				var a := int(pair[0])
				var b := int(pair[1])
				if a == province_id and b > 0 and b not in out:
					out.append(b)
				elif b == province_id and a > 0 and a not in out:
					out.append(a)
	return out


func link_ix1_road_spine_edges(province_id: int, neighbor_ids: Array = []) -> Dictionary:
	var nbrs: Array[int] = []
	if neighbor_ids is Array and not neighbor_ids.is_empty():
		for v in neighbor_ids:
			var nid := int(v)
			if nid > 0 and nid != province_id and nid not in nbrs:
				nbrs.append(nid)
	else:
		nbrs = get_ix1_spine_neighbors(province_id)
	var linked: Array[Dictionary] = []
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("build_road_connection"):
		for nid in nbrs:
			MapManager.build_road_connection(province_id, nid)
			linked.append({"a": province_id, "b": nid})
	return {
		"ok": not linked.is_empty() or nbrs.is_empty(),
		"province_id": province_id,
		"neighbors": nbrs,
		"linked": linked,
	}


func should_show_road_spine_button(province_id: int, player_tag: String) -> bool:
	if not is_ix1_road_spine_province(province_id):
		return false
	if has_active_project(province_id):
		return true
	var p: Province = null
	if typeof(MapManager) != TYPE_NIL:
		p = MapManager.get_province(province_id)
	var tag := player_tag.strip_edges().to_upper()
	if tag.is_empty():
		return false
	if p == null:
		# Search/Go may resolve Köln before MapManager cache; corridor + player tag is enough.
		return true
	if p.is_sea:
		return false
	if p.owner_tag.to_upper() != tag and p.controller_tag.to_upper() != tag:
		return false
	return true


func get_ix1_road_spine_mandate_cost() -> int:
	var spec := _ix1_spec_dict()
	if spec.has("first_session_mandate_cost"):
		return maxi(0, int(spec.get("first_session_mandate_cost", IX1_FIRST_SESSION_MANDATE_COST)))
	return IX1_FIRST_SESSION_MANDATE_COST


func get_ix1_displayed_mandate(tag: String = "GER") -> int:
	## Live HUD / Invest gate read the raw peace_state map (empty → 0), not get_pillar's 50 baseline.
	var t := tag.strip_edges().to_upper()
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_peace_state"):
		var ps: Dictionary = GameData.get_peace_state()
		return int(ps.get("mandate", {}).get(t, 0))
	return 0


func ix1_day0_mandate_can_start(tag: String = "GER") -> Dictionary:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		t = "GER"
	var cost := get_ix1_road_spine_mandate_cost()
	var current := get_ix1_displayed_mandate(t)
	return {
		"ok": current >= cost,
		"mandate": current,
		"cost": cost,
		"tag": t,
		"start": "1936-01-01",
	}


func try_start_road_spine(province_id: int, investor_tag: String) -> Dictionary:
	if not is_ix1_road_spine_province(province_id):
		return {"success": false, "reason": "Not on the IX-1 Rhineland road spine."}
	var preview: Dictionary = can_start_project(province_id, "infrastructure", investor_tag)
	if not preview.get("ok", false):
		return {
			"success": false,
			"reason": preview.get("reason", "Cannot start road spine"),
			"preview": preview
		}
	var pp_cost := get_ix1_road_spine_mandate_cost()
	var gate: Dictionary = ix1_day0_mandate_can_start(investor_tag)
	if not bool(gate.get("ok", false)):
		var current_mand := int(gate.get("mandate", 0))
		return {"success": false, "reason": "Insufficient Mandate (%d < %d)" % [current_mand, pp_cost], "preview": preview}
	if pp_cost > 0 and typeof(GameData) != TYPE_NIL:
		# Skip 0-cost apply_pillar_shift — that helper seeds missing tags at 50.
		GameData.apply_pillar_shift(investor_tag, "mandate", -pp_cost, "road_spine_" + str(province_id))
		GameData.apply_pillar_shift(investor_tag, "ascendancy", -int(pp_cost * 0.3), "road_spine_prestige")
	var p_for_target: Province = MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL else null
	var cur := p_for_target.infrastructure if p_for_target else 1
	var tgt := cur + 1
	var proj := start_infrastructure_project(province_id, tgt, investor_tag)
	if proj == null:
		return {"success": false, "reason": "Failed to create road spine project"}
	proj.build_road_spine = true
	proj.spine_neighbor_ids = get_ix1_spine_neighbors(province_id)
	proj.political_power_cost = pp_cost
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(province_id, "infrastructure_project")
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		var pname := p_for_target.name if p_for_target else str(province_id)
		LeaderEventUI.post_news(
			"IX-1 Road Spine Started",
			"%s begins a road-spine project in %s (ETA %d days)." % [proj.owner_tag, pname, proj.get_eta_days()],
			"infrastructure",
		)
	return {
		"success": true,
		"reason": "Road spine project started",
		"project": proj,
		"eta_days": proj.get_eta_days(),
		"cost_pp": pp_cost,
		"spine_neighbor_ids": proj.spine_neighbor_ids.duplicate(),
		"build_road_spine": true
	}


## F5 light sim already budgets 1 AI infra start/day. The full-board consider
## (get_all_provinces × every tag) is what wedged the clock once a spine existed.
## Graphical editor/export Play must skip even if light-sim is somehow false
## (softpipe smoke is DisplayServer X11/OpenGL, not headless).
func _should_run_full_board_ai_invest() -> bool:
	if typeof(TimeManager) != TYPE_NIL:
		if TimeManager.has_method("is_live_f5_play_path") and bool(TimeManager.is_live_f5_play_path()):
			return false
		if TimeManager.has_method("is_interactive_light_sim") and bool(TimeManager.is_interactive_light_sim()):
			return false
	if DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server"):
		return false
	if OS.get_environment("EOA_LIVE_F5_EQUIV").strip_edges() == "1":
		return false
	return true


func _should_quiet_ai_infra_start(investor_tag: String) -> bool:
	var tag := investor_tag.strip_edges().to_upper()
	if tag.is_empty() or tag == _player_tag_for_ai():
		return false
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_live_f5_play_path"):
		if bool(TimeManager.is_live_f5_play_path()):
			return true
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_interactive_light_sim"):
		if bool(TimeManager.is_interactive_light_sim()):
			return true
	if DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server"):
		return true
	return false


## Short automated path: seed Köln spine at the live freeze point (~17%) and
## drive the real F5 flush so the day clock + progress move past day 9 / 20%.
## Call again with more days to complete (ETA ~35 from 0%; ~29 from 17%).
func simulate_ix1_spine_days(days: int = 12, use_f5_flush: bool = true) -> Dictionary:
	var n := clampi(int(days), 1, 60)
	var hub := IX1_FALLBACK_HUB
	if typeof(TimeManager) != TYPE_NIL:
		if not _is_initialized:
			initialize_with_time()
	if not active_projects.has(hub):
		restore_project(hub, {
			"province_id": hub,
			"axis": "infrastructure",
			"owner_tag": "GER",
			"starting_level": 4,
			"target_level": 5,
			"progress": 17.0,
			"work_per_day_base": 2.8,
			"days_remaining": 29,
			"status": "active",
			"build_road_spine": true,
			"spine_neighbor_ids": [710416, 710418],
		})
	var start_prog := 0.0
	var live: ProvincialProject = active_projects.get(hub)
	if live != null:
		start_prog = float(live.progress)
	var start_elapsed := 0
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		start_elapsed = int(TimeManager.get_total_days_elapsed())
	# F5 flush proves the live clock (cap 12d — longer flush OOMs air/day listeners).
	# Complete path uses the cheap daily project tick only.
	var flush_n := mini(n, 12) if use_f5_flush else 0
	var rest := n - flush_n
	if flush_n > 0 and typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("advance_living_playtest_days"):
		TimeManager.call("advance_living_playtest_days", flush_n)
	if rest > 0:
		# Cheap days-remaining clock — no full-board AI invest, no F5 listener flush.
		tick_active_projects(rest)
	live = active_projects.get(hub)
	var end_prog := 100.0 if live == null else float(live.progress)
	var end_elapsed := start_elapsed
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		end_elapsed = int(TimeManager.get_total_days_elapsed())
	var completed := live == null or (live != null and str(live.status) == "complete")
	var elapsed_delta := end_elapsed - start_elapsed
	return {
		"ok": elapsed_delta >= n and (end_prog > start_prog or completed),
		"days": n,
		"elapsed_delta": elapsed_delta,
		"progress_before": start_prog,
		"progress_after": end_prog,
		"past_freeze": end_prog > 20.0 or completed,
		"completed": completed,
		"build_road_spine": true,
		"hub_id": hub,
		"full_board_ai_invest": _should_run_full_board_ai_invest(),
	}


## Live editor/export Play stand-in: day_ai + budgeted AI invest run, playtest
## skips do not. Fails closed if full-board consider would fire, calendar
## autosave gathers, or the clock does not move past day +6 in a short budget
## (headless-only green is not KEEP). Default 8d crosses the live +5/+6 wall.
func simulate_live_f5_day_advance(days: int = 8) -> Dictionary:
	var n := clampi(int(days), 1, 20)
	_full_board_ai_invest_calls = 0
	_ai_infra_provinces_considered = 0
	if typeof(TimeManager) != TYPE_NIL:
		if not _is_initialized:
			initialize_with_time()
	var sl: Node = null
	if typeof(SaveLoadManager) != TYPE_NIL:
		sl = SaveLoadManager
	if sl != null:
		sl.set("_calendar_autosave_gathers", 0)
		sl.set("_calendar_autosave_live_f5_skips", 0)
	var hub := IX1_FALLBACK_HUB
	if not active_projects.has(hub):
		restore_project(hub, {
			"province_id": hub,
			"axis": "infrastructure",
			"owner_tag": "GER",
			"starting_level": 4,
			"target_level": 5,
			"progress": 2.0,
			"work_per_day_base": 2.8,
			"days_remaining": 35,
			"status": "active",
			"build_road_spine": false,
			"spine_neighbor_ids": [],
		})
	var start_elapsed := 0
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		start_elapsed = int(TimeManager.get_total_days_elapsed())
	var gate_on := true
	if typeof(TimeManager) != TYPE_NIL:
		var was_equiv := bool(TimeManager.get("_live_f5_equiv_clock"))
		TimeManager.set("_live_f5_equiv_clock", true)
		gate_on = _should_run_full_board_ai_invest()
		TimeManager.set("_live_f5_equiv_clock", was_equiv)
	var mem0 := int(OS.get_static_memory_usage())
	var t0 := Time.get_ticks_msec()
	var clock: Dictionary = {}
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("advance_live_f5_equivalent_days"):
		clock = TimeManager.call("advance_live_f5_equivalent_days", n)
	elif typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("advance_days"):
		var was_paused := bool(TimeManager.paused)
		TimeManager.paused = false
		TimeManager.advance_days(float(n))
		if TimeManager.has_method("_drain_living_f5_flush"):
			TimeManager.call("_drain_living_f5_flush", n)
		TimeManager.paused = was_paused
	var ms := Time.get_ticks_msec() - t0
	var mem1 := int(OS.get_static_memory_usage())
	var mem_delta := maxi(0, mem1 - mem0)
	var end_elapsed := start_elapsed
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		end_elapsed = int(TimeManager.get_total_days_elapsed())
	var elapsed_delta := end_elapsed - start_elapsed
	var consider_calls := _full_board_ai_invest_calls
	var past_plus2 := elapsed_delta >= mini(n, 3)
	var past_plus6 := elapsed_delta >= mini(n, 7)
	var autosave_gathers := 0
	var autosave_skips := 0
	if sl != null:
		autosave_gathers = int(sl.get("_calendar_autosave_gathers"))
		autosave_skips = int(sl.get("_calendar_autosave_live_f5_skips"))
	var ms_budget := 12000 if n >= 7 else 8000
	var mem_budget := 48 * 1024 * 1024
	var ok := (
		elapsed_delta >= n
		and consider_calls == 0
		and not gate_on
		and past_plus2
		and past_plus6
		and autosave_gathers == 0
		and mem_delta <= mem_budget
		and ms <= ms_budget
	)
	return {
		"ok": ok,
		"days": n,
		"elapsed_delta": elapsed_delta,
		"past_plus2": past_plus2,
		"past_plus6": past_plus6,
		"full_board_ai_invest": gate_on,
		"full_board_ai_invest_calls": consider_calls,
		"provinces_considered": _ai_infra_provinces_considered,
		"calendar_autosave_gathers": autosave_gathers,
		"calendar_autosave_live_f5_skips": autosave_skips,
		"memory_delta_bytes": mem_delta,
		"elapsed_ms": ms,
		"live_f5_equiv": true,
		"living_playtest_clock": false,
		"clock": clock,
	}


## AI helper (called from DebugOverlay AI sim turns, TestRunner headless demos, or daily if extended).
## AI countries aggressively develop core / high-value low-infra provinces (per DESIGN Phase D).
## Uses same try_start so Mandate spend + full validation (engineer, tech, stab) applies.
## Probabilistic to avoid spam; prefers provinces with factories or high pop or in core.
func ai_consider_daily_invests(ai_country_tags: Array = [], chance_per_country: float = 0.35) -> int:
	_full_board_ai_invest_calls += 1
	var started := 0
	if ai_country_tags.is_empty():
		# Fallback: discover some non-player tags from MapManager
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
			var all_p := MapManager.get_all_provinces()
			var seen := {}
			for pid in all_p:
				var pr: Province = all_p[pid]
				if pr and not pr.owner_tag.is_empty():
					seen[pr.owner_tag] = true
			ai_country_tags = seen.keys()
			# crude: filter player later if known
	if ai_country_tags.is_empty():
		return 0

	var player := ""
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_player_tag"):
		player = GameData.get_player_tag()

	for raw_tag in ai_country_tags:
		var tag := str(raw_tag).strip_edges().to_upper()
		if tag.is_empty() or tag == player:
			continue
		if randf() > chance_per_country:
			continue  # probabilistic throttle for 50+ turn playtest feel

		# Collect candidate provinces for this AI: owned/controller, lowish infra, prefer core + factories
		var candidates: Array = []
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
			var allp := MapManager.get_all_provinces()
			for pidv in allp:
				var pid := int(pidv)
				var pr: Province = allp[pidv]
				if pr == null: continue
				if pr.owner_tag.to_upper() != tag and pr.controller_tag.to_upper() != tag: continue
				if has_active_project(pid): continue
				if pr.infrastructure >= _get_era_max(tag, "infrastructure") - 1: continue
				var score := 10.0
				score -= float(pr.infrastructure) * 0.6  # prefer lower infra
				var is_core := false
				if pr.core_for.size() > 0:
					is_core = pr.owner_tag.to_upper() == str(pr.core_for[0]).to_upper()
				if is_core:
					score += 8.0
				score += float(pr.factories) * 1.5
				score += float(pr.population) / 200000.0
				candidates.append({"pid": pid, "score": score, "prov": pr})

		if candidates.is_empty():
			continue
		candidates.sort_custom(func(a, b): return a.score > b.score)
		# Try top 1-2
		for i in range(min(2, candidates.size())):
			var c: Dictionary = candidates[i]
			var pid: int = c.pid
			var preview := can_start_project(pid, "infrastructure", tag)
			if preview.get("ok", false):
				# Use try_ for full Mandate/econ spend + event hooks (same as player)
				if has_method("try_start_infrastructure_investment"):
					var res: Dictionary = try_start_infrastructure_investment(pid, tag)
					if res.get("success", false):
						started += 1
						print("InfrastructureDevelopmentManager: AI %s auto-started infra invest on #%d (ETA %s)" % [tag, pid, str(res.get("eta_days", "?"))])
						break  # one per country per consider tick
	return started


## Interactive F5: at most one new AI infra project per day. Skip player tag.
## Prefers low-infra owned land near capital or a live border. Reuses start APIs.
func try_ai_start_infra_project(tag: String, day_index: int = 0) -> Dictionary:
	if OS.get_environment("EOA_AI_INFRA").strip_edges() == "0":
		return {"ok": true, "skipped": true, "started": false, "started_n": 0, "reason": "killswitch"}
	var player := _player_tag_for_ai()
	var chosen := tag.strip_edges().to_upper()
	if chosen.is_empty():
		chosen = _pick_ai_infra_tag(player, day_index)
	if chosen.is_empty() or chosen == player:
		return {"ok": true, "skipped": true, "started": false, "started_n": 0, "reason": "player", "tag": chosen}
	if _ai_infra_budget_day == day_index and _ai_infra_starts_today >= 1:
		return {"ok": true, "skipped": true, "started": false, "started_n": 0, "reason": "day_budget", "tag": chosen}
	_ai_infra_provinces_considered = 0
	var pid := _pick_ai_infra_province(chosen)
	if pid <= 0:
		return {"ok": true, "started": false, "started_n": 0, "reason": "no_candidate", "tag": chosen, "provinces_considered": _ai_infra_provinces_considered}
	var started := false
	if has_method("try_start_infrastructure_investment"):
		var res: Dictionary = try_start_infrastructure_investment(pid, chosen)
		started = bool(res.get("success", false))
	if not started:
		var p: Province = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
		if p != null and not has_active_project(pid):
			var cap := _get_era_max(chosen, "infrastructure")
			var tgt := clampi(int(p.infrastructure) + 1, 1, cap)
			var proj: ProvincialProject = start_infrastructure_project(pid, tgt, chosen)
			started = proj != null
	if not started:
		return {"ok": true, "started": false, "started_n": 0, "reason": "start_failed", "tag": chosen, "province_id": pid}
	if _ai_infra_budget_day != day_index:
		_ai_infra_budget_day = day_index
		_ai_infra_starts_today = 0
	_ai_infra_starts_today += 1
	var live: ProvincialProject = get_active_project(pid)
	if live != null and live.days_remaining <= 0:
		live.days_remaining = maxi(1, live.get_eta_days())
	return {
		"ok": true,
		"started": true,
		"started_n": 1,
		"tag": chosen,
		"province_id": pid,
		"pid": pid,
		"kind": "infrastructure",
		"days_remaining": live.days_remaining if live else 0,
		"provinces_considered": _ai_infra_provinces_considered,
	}


## Days-remaining clock. Completes via existing _complete_project and bumps infra +1 (clamp).
func tick_active_projects(days: int = 1) -> Dictionary:
	var n := maxi(int(days), 0)
	var completed: Array = []
	if n <= 0 or active_projects.is_empty():
		return {"ok": true, "ticked": n, "completed": completed, "completed_n": 0}
	var to_complete: Array = []
	for pid_var in active_projects.keys():
		var pid := int(pid_var)
		var proj: ProvincialProject = active_projects[pid]
		if proj == null or str(proj.status) != "active":
			continue
		if proj.days_remaining <= 0:
			proj.days_remaining = maxi(1, proj.get_eta_days())
		proj.days_remaining = maxi(0, proj.days_remaining - n)
		if proj.days_remaining <= 0:
			to_complete.append({"pid": pid, "proj": proj})
	for item in to_complete:
		var pid2 := int(item.pid)
		var proj2: ProvincialProject = item.proj
		if typeof(MapManager) != TYPE_NIL:
			var p: Province = MapManager.get_province(pid2)
			if p != null:
				var cap := _get_era_max(proj2.owner_tag, proj2.axis if proj2.axis != "" else "infrastructure")
				proj2.target_level = clampi(int(p.infrastructure) + 1, 1, cap)
		_complete_project(pid2, proj2)
		completed.append(pid2)
	return {"ok": true, "ticked": n, "completed": completed, "completed_n": completed.size()}


func _player_tag_for_ai() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var pt := str(LeaderManager.call("get_player_country_tag")).strip_edges().to_upper()
		if not pt.is_empty():
			return pt
	if typeof(SessionPlayers) != TYPE_NIL:
		for slot in SessionPlayers.slots:
			if slot is Dictionary and str((slot as Dictionary).get("control", "")).to_lower() == "human":
				var ht := str((slot as Dictionary).get("tag", "")).strip_edges().to_upper()
				if not ht.is_empty():
					return ht
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_player_tag"):
		var gt := str(GameData.get_player_tag()).strip_edges().to_upper()
		if not gt.is_empty():
			return gt
	return "GER"


func _pick_ai_infra_tag(player: String, day_index: int) -> String:
	# One rotated major — do not walk every tag calling a province scan.
	var majors: Array = ["SOV", "JAP", "FRA", "ITA", "USA", "ENG", "POL"]
	var filtered: Array = []
	for raw in majors:
		var t := str(raw).to_upper()
		if t.is_empty() or t == player:
			continue
		filtered.append(t)
	if filtered.is_empty():
		return ""
	return str(filtered[posmod(int(day_index), filtered.size())])


func _capital_pid_for_tag(tag: String) -> int:
	var t := tag.strip_edges().to_upper()
	if typeof(GameData) != TYPE_NIL and "countries" in GameData:
		var raw: Variant = GameData.countries.get(t)
		if raw is Dictionary:
			return int((raw as Dictionary).get("capital_province_id", 0))
		if raw != null and "capital_province_id" in raw:
			return int(raw.capital_province_id)
	return 0


func _pick_ai_infra_province(tag: String) -> int:
	# Live F5: never walk get_provinces_by_owner / get_all_provinces (3520).
	# Capital → a few capital neighbors → at most two cached border from_ids.
	if typeof(MapManager) == TYPE_NIL:
		return 0
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return 0
	var cap_pid := _capital_pid_for_tag(t)
	if _ai_infra_pid_ok(cap_pid, t):
		_ai_infra_provinces_considered += 1
		return cap_pid
	if cap_pid > 0 and MapManager.has_method("get_adjacent_provinces"):
		var nbr: Array = MapManager.get_adjacent_provinces(cap_pid, true)
		for pid_var in nbr:
			if _ai_infra_provinces_considered >= AI_INFRA_PICK_CAP:
				break
			var pid := int(pid_var)
			_ai_infra_provinces_considered += 1
			if _ai_infra_pid_ok(pid, t):
				return pid
	if MapManager.has_method("collect_live_border_assault_targets"):
		var fronts: Array = MapManager.collect_live_border_assault_targets(t, 2)
		for raw in fronts:
			if _ai_infra_provinces_considered >= AI_INFRA_PICK_CAP:
				break
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var from_id := int((raw as Dictionary).get("from_province_id", 0))
			_ai_infra_provinces_considered += 1
			if _ai_infra_pid_ok(from_id, t):
				return from_id
	return 0


func _ai_infra_pid_ok(pid: int, tag: String) -> bool:
	if pid <= 0 or has_active_project(pid):
		return false
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return false
	var p: Province = MapManager.get_province(pid)
	if p == null or bool(p.is_sea):
		return false
	var owner := str(p.owner_tag).strip_edges().to_upper()
	var ctrl := str(p.controller_tag).strip_edges().to_upper() if "controller_tag" in p else ""
	if owner != tag and ctrl != tag:
		return false
	var era_max := _get_era_max(tag, "infrastructure")
	if int(p.infrastructure) >= era_max:
		return false
	return true


func _count_active_projects_for(country_tag: String) -> int:
	var tag := country_tag.strip_edges().to_upper()
	var n := 0
	for proj in active_projects.values():
		if str(proj.owner_tag).to_upper() == tag and str(proj.status) == "active":
			n += 1
	return n


func _national_construction_capacity(country_tag: String) -> int:
	var tag := country_tag.strip_edges().to_upper()
	var cap := 3
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_public_cohesion"):
		var coh: int = int(GameData.get_public_cohesion(tag))
		cap += clampi(coh / 25, 0, 4)
	return cap


func _available_political_power(country_tag: String) -> int:
	var tag := country_tag.strip_edges().to_upper()
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_political_power"):
		return int(GameData.get_political_power(tag))
	# Live F5: never scan every owned hex for a PP proxy (that is a 3520 walk).
	if _should_quiet_ai_infra_start(tag) or (
		typeof(TimeManager) != TYPE_NIL
		and TimeManager.has_method("is_interactive_light_sim")
		and bool(TimeManager.is_interactive_light_sim())
	):
		return maxi(80 - _count_active_projects_for(tag) * 12, 0)
	# Proxy: factories + dev on owned provinces minus active project load
	var pp := 50
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
		for pid in MapManager.get_provinces_by_owner(tag):
			var p: Province = MapManager.get_province(int(pid))
			if p != null:
				pp += p.factories * 8 + int(p.development_level) * 2
	pp -= _count_active_projects_for(tag) * 12
	return maxi(pp, 0)
