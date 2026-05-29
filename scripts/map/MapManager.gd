# scripts/map/MapManager.gd
## Central authority for province data, geometry, adjacency, and ProvinceEffects queries.
## Replaces scattered find_child("ScenarioLoader") and direct node walks across the codebase.
##
## Usage:
##   var p := MapManager.get_province(42)
##   var fx := MapManager.get_province_effects(42, "GER")
##   var resist := fx.get_effective_interdiction_resistance()
##
## Note: MapManager is an autoload singleton (no class_name on purpose to keep the GDScript analyzer happy).

extends Node

# NOTE: We intentionally do NOT declare `class_name MapManager`.
# This script is registered as an autoload singleton named "MapManager".
# Using class_name on an autoload causes Godot's GDScript analyzer to emit
# "Class 'MapManager' hides an autoload singleton" + errors when calling its methods
# (has_method, get_province, get_province_effects, etc.) from static context.
#
# Removing class_name makes the static analyzer happy while runtime behavior is unchanged.

signal scenario_map_ready()
signal provinces_loaded(province_count: int)
signal province_hovered(province_id: int)
signal province_selected(province_id: int)
signal province_data_changed(province_id: int, what_changed: String)  # e.g. "owner", "development", "effects"

var _provinces: Dictionary[int, Province] = {}           # id -> Province
var _geometry: Dictionary = {}            # id -> {points, label_anchor, ...}
var _adjacency: AdjacencySystem = null
var _countries: Dictionary[String, Variant] = {}           # tag -> Country or Dictionary

var _is_initialized: bool = false

# Cached for fast queries and picking
var _centroids: Dictionary[int, Vector2] = {}   # id -> Vector2 (world/map space)
var _province_bounds: Dictionary[int, Rect2] = {}  # id -> AABB in map space
var _world_bounds: Rect2 = Rect2()        # rough axis-aligned bounds of all provinces

# Optional high-performance picker (created on demand or by MapRenderer)
var pick_grid: MapPickGrid = null
var pick_grid_cell_size: float = 64.0

func _ready() -> void:
	# Try to connect to ScenarioLoader if it is already in the tree (common autoload ordering)
	_connect_to_scenario_loader()

	# Connect to central daily clock for automatic infrastructure repair
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)

func _connect_to_scenario_loader() -> void:
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if loader != null:
		if not loader.scenario_loaded.is_connected(_on_scenario_loaded):
			loader.scenario_loaded.connect(_on_scenario_loaded)
		# If a scenario was already loaded before we connected, pull it now
		if loader.provinces.size() > 0 and not _is_initialized:
			_pull_from_loader(loader)

func _on_scenario_loaded() -> void:
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if loader != null:
		_pull_from_loader(loader)

func _pull_from_loader(loader: ScenarioLoader) -> void:
	if loader == null:
		return
	var map_data := loader.get_map_data()
	initialize_from_map_data(map_data)

## Primary initialization path (called by ScenarioLoader signal or explicitly by TestRunner / scenes)
func initialize_from_map_data(map_data: MapScenarioData) -> void:
	if map_data == null:
		push_error("MapManager: initialize_from_map_data received null MapScenarioData")
		return

	# Clear previous state for clean reloads
	_clear_internal_caches()

	_provinces = MapScenarioData.coerce_provinces(map_data.provinces)
	_geometry = map_data.geometry.duplicate(true) if map_data.geometry else {}
	_adjacency = map_data.adjacency_system
	_countries = MapScenarioData.coerce_countries(map_data.countries)

	_is_initialized = _provinces.size() > 0

	_recompute_centroids_and_bounds()
	_try_build_pick_grid()

	print("🗺️ MapManager initialized with %d provinces (bounds: %s)" % [_provinces.size(), _world_bounds])
	scenario_map_ready.emit()
	provinces_loaded.emit(_provinces.size())

## --- Public Query API ---

func has_province_data() -> bool:
	return _is_initialized and _provinces.size() > 0

func get_province(province_id: int) -> Province:
	return _provinces.get(province_id)

func get_all_provinces() -> Dictionary[int, Province]:
	return _provinces

func get_province_geometry(province_id: int) -> Dictionary:
	return _geometry.get(province_id, {})

func get_adjacency_system() -> AdjacencySystem:
	return _adjacency

func get_country(tag: String) -> Variant:
	if tag.is_empty():
		return null
	return _countries.get(tag) if _countries.has(tag) else _countries.get(tag.to_upper())

func get_player_country_tag_fallback() -> String:
	# Useful for early UI before player selection is wired
	for t in _countries.keys():
		return str(t)
	return "USA"

## --- ProvinceEffects exposure (the main value of this manager) ---

func get_province_effects(province_id: int, country_tag: String = "") -> ProvinceEffects:
	var province: Province = get_province(province_id)
	if province == null:
		return null

	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = province.controller_tag if not province.controller_tag.is_empty() else province.owner_tag

	if typeof(ProvinceEffects) == TYPE_NIL:
		# Fallback during early boot or tests
		return ProvinceEffects.new(province, {})

	return ProvinceEffects.for_country_province(province, tag)

## Convenience wrappers for the most common effective values (used by UI and systems)
func get_effective_interdiction_resistance(province_id: int, country_tag: String = "") -> float:
	var fx := get_province_effects(province_id, country_tag)
	return fx.get_effective_interdiction_resistance() if fx else 1.0

func get_effective_reinforcement_speed(province_id: int, country_tag: String = "") -> float:
	var fx := get_province_effects(province_id, country_tag)
	return fx.get_effective_reinforcement_speed() if fx else 1.0

func get_effective_organization_recovery(province_id: int, country_tag: String = "") -> float:
	var fx := get_province_effects(province_id, country_tag)
	return fx.get_effective_organization_recovery() if fx else 1.0

func get_effective_attrition_multiplier(province_id: int, country_tag: String = "") -> float:
	var fx := get_province_effects(province_id, country_tag)
	return fx.get_effective_attrition_multiplier() if fx else 1.0

func get_effective_logistics_quality(province_id: int, country_tag: String = "") -> float:
	var fx := get_province_effects(province_id, country_tag)
	return fx.get_effective_logistics_quality() if fx else 50.0

## --- Light integration helpers (used by Combat / Supply during transition) ---

func get_province_or_null(province_id: int) -> Province:
	return get_province(province_id)

## Allows MapRenderer or scenes to push data directly (used in TestRunner before signal wiring is perfect)
func force_initialize(provinces: Dictionary, geometry: Dictionary, adjacency: AdjacencySystem, countries: Dictionary = {}) -> void:
	var fake := MapScenarioData.new(provinces, geometry, adjacency, countries)
	initialize_from_map_data(fake)

## --- Query API (MapManager is the single source of truth) ---
## All province lookups, spatial queries, and ProvinceEffects should go through here.
## The position-based picking methods below are the recommended way to resolve "what province is under the mouse?"

func get_provinces_by_owner(owner_tag: String) -> Array[int]:
	if owner_tag.is_empty():
		return []
	var result: Array[int] = []
	var tag := owner_tag.strip_edges().to_upper()
	for pid in _provinces.keys():
		var p: Province = _provinces[pid]
		if p != null and p.owner_tag.strip_edges().to_upper() == tag:
			result.append(int(pid))
	return result

func get_provinces_by_controller(controller_tag: String) -> Array[int]:
	if controller_tag.is_empty():
		return []
	var result: Array[int] = []
	var tag := controller_tag.strip_edges().to_upper()
	for pid in _provinces.keys():
		var p: Province = _provinces[pid]
		if p != null:
			var ctrl := p.controller_tag.strip_edges().to_upper()
			if ctrl == tag or (ctrl.is_empty() and p.owner_tag.strip_edges().to_upper() == tag):
				result.append(int(pid))
	return result

## Delegates to AdjacencySystem (preferred source of truth)
func get_adjacent_provinces(province_id: int, only_land: bool = true) -> Array[int]:
	if _adjacency == null:
		return []
	if only_land:
		return _adjacency.get_land_neighbors(province_id)
	else:
		return _adjacency.get_sea_neighbors(province_id)

## Very useful for camera frustum culling, minimap, and bulk effects
func get_provinces_in_rect(world_rect: Rect2, margin: float = 0.0) -> Array[int]:
	if not _is_initialized or world_rect.size == Vector2.ZERO:
		return []

	var expanded := world_rect.grow(margin)
	var result: Array[int] = []

	for pid_var in _provinces.keys():
		var pid := int(pid_var)
		var c: Vector2 = _centroids.get(pid, Vector2.INF)
		if c != Vector2.INF and expanded.has_point(c):
			result.append(int(pid))
	return result

func get_province_centroid(province_id: int) -> Vector2:
	return _centroids.get(province_id, Vector2.ZERO)

func get_all_centroids() -> Dictionary:
	# Returns a copy for safety (used by pickers, minimaps, overlays)
	return _centroids.duplicate()

func get_world_bounds() -> Rect2:
	return _world_bounds

## === RECOMMENDED PICKING APIs (use these everywhere) ===
## High-performance province picking powered by MapPickGrid when available.
## These are the primary entry points for hover, click, and spatial queries from UI / systems.

## World-space version (preferred when you already have world coordinates)
func get_province_at_world_pos(world_pos: Vector2, use_pick_grid: bool = true) -> int:
	if use_pick_grid and pick_grid != null and pick_grid.is_built():
		return pick_grid.get_province_at(world_pos, 1, false)

	# Fallback: brute force among centroids (acceptable while < 150 provinces)
	var best := -1
	var best_d := INF
	for pid_var in _centroids.keys():
		var pid := int(pid_var)
		var c: Vector2 = _centroids.get(pid, Vector2.ZERO)
		var d := world_pos.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = pid
	return best

## Convenience for MapRenderer / UI (converts screen mouse pos using the current Camera2D).
func get_province_at_screen_pos(screen_pos: Vector2, use_pick_grid: bool = true) -> int:
	var cam := get_viewport().get_camera_2d() if Engine.get_main_loop() else null
	if cam:
		var world_pos := cam.get_canvas_transform().affine_inverse() * screen_pos
		return get_province_at_world_pos(world_pos, use_pick_grid)
	return -1

func get_nearest_provinces(world_pos: Vector2, count: int = 5) -> Array[int]:
	if pick_grid != null and pick_grid.is_built():
		return pick_grid.get_nearest_provinces(world_pos, count, 2)

	# Brute fallback
	var scored: Array = []
	for pid_var in _centroids.keys():
		var pid := int(pid_var)
		var c: Vector2 = _centroids.get(pid, Vector2.ZERO)
		scored.append({"id": pid, "dist2": world_pos.distance_squared_to(c)})
	scored.sort_custom(func(a, b): return a["dist2"] < b["dist2"])

	var out: Array[int] = []
	for i in mini(count, scored.size()):
		out.append(scored[i]["id"])
	return out

## Recommended high-level entry points for all spatial queries (use these!)
## They automatically use the fast MapPickGrid when available.
func get_province_at_mouse() -> int:
	var cam := get_viewport().get_camera_2d() if Engine.get_main_loop() else null
	if not cam:
		return -1
	var screen_pos := get_viewport().get_mouse_position()
	return get_province_at_screen_pos(screen_pos)

## Filtered province lists (very useful for UI, AI, overlays)
func get_provinces_with_feature(feature: String) -> Array[int]:
	var result: Array[int] = []
	for pid in _provinces.keys():
		var p: Province = _provinces[pid]
		if p != null and p.has_feature(feature):
			result.append(int(pid))
	return result

func get_provinces_by_terrain(terrain: String) -> Array[int]:
	var result: Array[int] = []
	var t := terrain.to_lower().strip_edges()
	for pid in _provinces.keys():
		var p: Province = _provinces[pid]
		if p != null and p.terrain.to_lower() == t:
			result.append(int(pid))
	return result

## Quick bounds + centroid helpers for culling / camera logic
func get_centroids_in_rect(rect: Rect2) -> Dictionary[int, Vector2]:
	var out: Dictionary[int, Vector2] = {}
	for pid_var in _centroids.keys():
		var pid := int(pid_var)
		var c: Vector2 = _centroids.get(pid, Vector2.ZERO)
		if rect.has_point(c):
			out[pid] = c
	return out

## Convenience bundle for overlay layers (Agent, Conflict, Supply tint, etc.)
## Returns common data needed by most overlays without multiple calls.
func get_overlay_data_for_province(province_id: int, country_tag: String = "") -> Dictionary[String, Variant]:
	var p: Province = get_province(province_id)
	if p == null:
		var empty: Dictionary[String, Variant] = {}
		return empty
	var tag := country_tag
	if tag.is_empty():
		tag = p.controller_tag if not p.controller_tag.is_empty() else p.owner_tag
	var fx: ProvinceEffects = get_province_effects(province_id, tag)
	return {
		"province": p,
		"centroid": get_province_centroid(province_id),
		"effects": fx,
		"geometry": get_province_geometry(province_id),
		"adjacent": get_adjacent_provinces(province_id),
		"owner": p.owner_tag,
		"controller": p.controller_tag,
		"dev": p.development_level,
		"infra": p.infrastructure,
		"terrain": p.terrain,
	}

## High-value helper for Conflict / Agent overlays: provinces where controller != owner (occupied/contested).
## Returns dict of pid -> {"owner", "controller", "centroid", "effects"}
func get_contested_provinces(country_tag: String = "") -> Dictionary:
	var result := {}
	for pid in _provinces.keys():
		var p: Province = _provinces[pid]
		if p == null:
			continue
		if p.owner_tag != p.controller_tag and not p.controller_tag.is_empty():
			var data: Dictionary = get_overlay_data_for_province(int(pid), country_tag)
			if not data.is_empty():
				result[int(pid)] = {
					"owner": p.owner_tag,
					"controller": p.controller_tag,
					"centroid": data["centroid"],
					"effects": data["effects"],
				}
	return result

## Combined helper very useful for AgentNetworkLayer (enemy pressure from contested + adjacent contested).
## Returns for each pid a "pressure" score (0.0 - 1.0+) based on local + neighboring enemy control.
func get_agent_pressure_map(country_tag: String = "") -> Dictionary:
	var pressure := {}
	var contested := get_contested_provinces(country_tag)

	for pid in _provinces.keys():
		var p: Province = _provinces[pid]
		if p == null:
			continue
		var local_pressure := 0.0
		if p.owner_tag != p.controller_tag and not p.controller_tag.is_empty():
			local_pressure += 0.6

		# Adjacent pressure
		var adj := get_adjacent_provinces(int(pid), true)
		for nid in adj:
			if contested.has(nid):
				local_pressure += 0.2

		pressure[int(pid)] = clampf(local_pressure, 0.0, 1.5)

	return pressure

## Convenience for AgentNetworkLayer and similar: returns a dict ready for overlay drawing.
## pid -> { "centroid", "effective_strength", "pressure", "owner", "controller", "dev" }
func get_agent_network_overlay_data(target_country: String = "") -> Dictionary:
	var result := {}
	var pressure_map := get_agent_pressure_map(target_country)
	for pid in get_all_provinces().keys():
		var pid_int := int(pid)
		var data := get_overlay_data_for_province(pid_int, target_country)
		if data.is_empty():
			continue
		var p := data["province"] as Province
		var pressure := float(pressure_map.get(pid_int, 0.0))
		# Synthesize a strength (real systems would pull from AgentManager)
		var strength := clampf(float(p.development_level) / 9.0 + 0.1, 0.1, 1.1)
		var effective := clampf(strength * (1.0 - pressure * 0.6), 0.05, 1.0)
		result[pid_int] = {
			"centroid": data["centroid"],
			"effective_strength": effective,
			"pressure": pressure,
			"owner": p.owner_tag,
			"controller": p.controller_tag,
			"dev": p.development_level,
		}
	return result

## Public API for mutating province data at runtime (e.g. from Production, Technology, Diplomacy, or events).
## Always emits province_data_changed so overlays, UI, and AI can react.
func update_province_owner(
	province_id: int,
	new_owner: String,
	new_controller: String = "",
	skip_capture: bool = false,
) -> bool:
	var p: Province = _provinces.get(province_id)
	if p == null:
		return false
	var changed := false
	if p.owner_tag != new_owner:
		p.owner_tag = new_owner
		changed = true
	if new_controller != "" and p.controller_tag != new_controller:
		p.controller_tag = new_controller
		changed = true
	if changed:
		province_data_changed.emit(province_id, "owner")

		if not skip_capture and typeof(FactoryManager) != TYPE_NIL:
			FactoryManager.capture_province_factories(province_id, new_owner)

		return true
	return false

func update_province_development(province_id: int, new_dev: int) -> bool:
	var p: Province = _provinces.get(province_id)
	if p == null:
		return false
	if p.development_level != new_dev:
		p.development_level = max(0, new_dev)
		province_data_changed.emit(province_id, "development")
		return true
	return false

func update_province_infrastructure(province_id: int, new_infra: int) -> bool:
	var p: Province = _provinces.get(province_id)
	if p == null:
		return false
	if p.infrastructure != new_infra:
		p.infrastructure = max(0, new_infra)
		province_data_changed.emit(province_id, "infrastructure")
		return true
	return false

## Legacy compatibility helper
func notify_province_changed(province_id: int, what: String) -> void:
	if _provinces.has(province_id):
		province_data_changed.emit(province_id, what)

## Clears active daily sabotage effects for a province (used by counter-intel operations).
## Removes temporary supply disruption debuffs associated with this province.
## Infrastructure damage is "repaired" via the normal slow repair rate (not instantly cleared).
## Called by AgentManager counter-intel mission outcomes (e.g. successful "Counter-Intelligence Sweep")
## to give players (and AI) an active response tool against daily agent pressure.
func clear_daily_sabotage_effects(province_id: int) -> void:
	var p: Province = get_province(province_id)
	if p == null or typeof(NationalModifierManager) == TYPE_NIL:
		return

	var tag := p.controller_tag if not p.controller_tag.is_empty() else p.owner_tag
	if tag.is_empty():
		return

	# Remove supply sabotage effects tied to this province
	var effect_id := "agent_net_supply_%d" % province_id
	NationalModifierManager.remove_effect(tag, effect_id)

	# Also clear per-depot sabotage state (targeted supply disruption). This is the direct
	# "repair" response when counter-intel succeeds — removes lingering throughput penalties.
	if typeof(SupplyManager) != TYPE_NIL:
		var depot = SupplyManager.depot_states.get(province_id)
		if depot != null:
			depot.sabotage_level = 0.0

	# Note: infrastructure recovers through the automatic repair system (see get_infrastructure_repair_rate).

	notify_province_changed(province_id, "effects")

func _on_game_day_advanced(_year: int, _month: int, _day: int) -> void:
	# Automatic slow repair driven by the central clock
	advance_daily_infrastructure_repair()

## Automatic slow repair for province infrastructure.
## Called daily by the central TimeManager.
## Base rate is deliberately low so that sustained agent sabotage or bombing can cause lasting damage.
## Higher infrastructure creates a "pride" feedback loop (easier to maintain good infrastructure).
## Bonuses: stability (national pride via NationalModifierManager), engineer formations (via CombatPresenceRegistry
##   + SupplyManager.register_division_presence using DivisionTemplate.count_engineer_brigade_equivalent()),
##   and technology/national focus "infrastructure_repair" modifier.
## This makes repair strategic: station engineers, maintain high stability, research/focus repair tech to counter
## agent infrastructure sabotage and depot effects.
func advance_daily_infrastructure_repair() -> void:
	for pid in _provinces.keys():
		var p: Province = _provinces[pid]
		if p == null or p.infrastructure <= 0:
			continue

		var rate := get_infrastructure_repair_rate(int(pid))
		if rate <= 0.0:
			continue

		var current_infra: float = float(p.infrastructure)
		var new_infra: float = minf(50.0, current_infra + rate)  # soft cap at 50 for MVP
		if int(new_infra) > p.infrastructure:
			update_province_infrastructure(int(pid), int(new_infra))

const INFRA_REPAIR_BASE := 0.08
const INFRA_REPAIR_PER_LEVEL := 0.004
const INFRA_REPAIR_STABILITY_FACTOR := 0.005
const INFRA_REPAIR_ENGINEER_BASE := 0.06
const INFRA_REPAIR_ENGINEER_PER_BRIGADE := 0.035
const INFRA_REPAIR_ENGINEER_CAP := 0.28
const INFRA_SOFT_CAP := 50


## Returns per-day repair components for UI, tooltips, and balance tuning.
## Full breakdown:
## - base: INFRA_REPAIR_BASE (0.08) — low so pressure matters.
## - infra_bonus: pride from current infrastructure level.
## - stability_bonus: from controlling country's "stability" modifier (NationalModifierManager).
## - tech_focus_bonus: from "infrastructure_repair" modifier (ready for tech + national focuses).
## - engineer_bonus: from friendly engineer/combat_engineer brigades present (via CombatPresenceRegistry
##   populated by SupplyManager.register_division_presence when divisions are in-province; uses
##   DivisionTemplate.count_engineer_brigade_equivalent()).
## All components (plus sabotage state) are exposed so players can see exactly why repair is fast/slow
## and make strategic decisions (station engineers, raise stability, counter-intel to clear sabotage sources).
func get_infrastructure_repair_breakdown(province_id: int) -> Dictionary:
	var empty := {
		"base": 0.0,
		"infra_bonus": 0.0,
		"stability_bonus": 0.0,
		"tech_focus_bonus": 0.0,
		"engineer_bonus": 0.0,
		"engineer_brigades": 0.0,
		"total": 0.0,
		"infrastructure": 0,
		"under_infra_sabotage": false,
		"depot_sabotage_level": 0.0,
		"eta_days_to_cap": -1,
		"country_tag": "",
	}
	var p: Province = get_province(province_id)
	if p == null:
		return empty

	var tag := _repair_country_tag(p)
	var base := INFRA_REPAIR_BASE
	var infra_bonus := float(clampi(p.infrastructure, 0, INFRA_SOFT_CAP)) * INFRA_REPAIR_PER_LEVEL

	var stability_bonus := 0.0
	var tech_focus_bonus := 0.0
	if typeof(NationalModifierManager) != TYPE_NIL and not tag.is_empty():
		var stab := NationalModifierManager.get_national_modifier(tag, "stability")
		stability_bonus = clampf(stab * INFRA_REPAIR_STABILITY_FACTOR, -0.06, 0.12)
		tech_focus_bonus = NationalModifierManager.get_national_modifier(tag, "infrastructure_repair")

	var engineer_brigades := get_engineer_brigades_in_province(province_id, tag)
	var engineer_bonus := _engineer_repair_bonus(engineer_brigades)

	var total := base + infra_bonus + stability_bonus + tech_focus_bonus + engineer_bonus
	total = maxf(0.01, total)

	var depot_sabotage := _depot_sabotage_level(province_id)
	var under_sabotage := _province_under_infra_sabotage(p, province_id)

	var eta := -1
	if p.infrastructure < INFRA_SOFT_CAP and total > 0.0:
		eta = int(ceil(float(INFRA_SOFT_CAP - p.infrastructure) / total))

	return {
		"base": base,
		"infra_bonus": infra_bonus,
		"stability_bonus": stability_bonus,
		"tech_focus_bonus": tech_focus_bonus,
		"engineer_bonus": engineer_bonus,
		"engineer_brigades": engineer_brigades,
		"total": total,
		"infrastructure": p.infrastructure,
		"under_infra_sabotage": under_sabotage,
		"depot_sabotage_level": depot_sabotage,
		"eta_days_to_cap": eta,
		"country_tag": tag,
	}


## Returns the daily infrastructure repair rate for a province.
func get_infrastructure_repair_rate(province_id: int) -> float:
	return float(get_infrastructure_repair_breakdown(province_id).get("total", 0.0))


func get_engineer_brigades_in_province(province_id: int, country_tag: String = "") -> float:
	## Engineer detection for repair bonus.
	## Properly uses the CombatPresenceRegistry (via SupplyManager) which is populated when
	## Engineer divisions stationed via SupplyManager.deploy_engineer_formation_to_province()
	## (division_deployments + register_division_presence).
	## (or add_unit paths). DivisionTemplate.count_engineer_brigade_equivalent() identifies
	## "engineer" / "combat_engineer" sustainment and subunits. Only friendly (controlling country)
	## engineers contribute to repair (strategic: station your own engineers in threatened provinces).
	if typeof(SupplyManager) == TYPE_NIL:
		return 0.0
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		var p := get_province(province_id)
		if p == null:
			return 0.0
		tag = _repair_country_tag(p)
	if tag.is_empty():
		return 0.0
	return SupplyManager.get_engineer_brigades_in_province(province_id, tag)


func get_engineer_divisions_at_province(province_id: int, country_tag: String = "") -> Array[Dictionary]:
	if typeof(SupplyManager) == TYPE_NIL:
		return []
	return SupplyManager.get_formations_stationed_at_province(province_id, country_tag)


func get_engineer_capable_divisions(country_tag: String = "") -> Array[Dictionary]:
	if typeof(SupplyManager) == TYPE_NIL:
		return []
	return SupplyManager.get_engineer_capable_formations(country_tag)


func _repair_country_tag(province: Province) -> String:
	if province == null:
		return ""
	var tag := province.controller_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = province.owner_tag.strip_edges().to_upper()
	return tag


func project_engineer_repair_bonus(brigade_equiv: float) -> float:
	return _engineer_repair_bonus(brigade_equiv)


## Repair rate if exactly `brigade_equiv` engineer brigades were on station (replaces current engineer count).
func get_repair_rate_with_engineer_brigades(province_id: int, brigade_equiv: float) -> float:
	var bd := get_infrastructure_repair_breakdown(province_id)
	var without := maxf(0.01, float(bd.get("total", 0.0)) - float(bd.get("engineer_bonus", 0.0)))
	return without + project_engineer_repair_bonus(maxf(0.0, brigade_equiv))


## Snapshot for map UI: guidance level, duel context, projected rates at 0/1/2 brigades.
func get_engineer_assignment_snapshot(province_id: int) -> Dictionary:
	var bd := get_infrastructure_repair_breakdown(province_id)
	var p := get_province(province_id)
	var tag := str(bd.get("country_tag", ""))
	var eng_n := float(bd.get("engineer_brigades", 0.0))
	var rate := float(bd.get("total", 0.0))
	var without_eng := maxf(0.01, rate - float(bd.get("engineer_bonus", 0.0)))
	var chip := 0
	if p != null and typeof(ProvinceInsight) != TYPE_NIL:
		chip = ProvinceInsight.estimate_daily_infra_chip_damage(p)
	var under_sab := bool(bd.get("under_infra_sabotage", false))
	var winner := ""
	if p != null and typeof(ProvinceInsight) != TYPE_NIL:
		winner = ProvinceInsight.daily_infra_duel_winner(p, bd)
	var level := "none"
	if p != null and not tag.is_empty() and typeof(ProvinceInsight) != TYPE_NIL:
		var owned: bool = ProvinceInsight.province_benefits_country(p, tag)
		if not owned:
			level = "foreign"
		elif eng_n >= 0.05:
			if under_sab and winner == "sabotage":
				level = "present_insufficient"
			else:
				level = "present"
		elif under_sab:
			if winner == "sabotage" or chip > int(floor(rate)):
				level = "critical"
			else:
				level = "recommended"
		elif int(bd.get("infrastructure", 0)) < 45:
			level = "recommended"
	return {
		"country_tag": tag,
		"engineer_brigades": eng_n,
		"repair_total": rate,
		"repair_without_engineers": without_eng,
		"engineer_bonus": float(bd.get("engineer_bonus", 0.0)),
		"chip_damage_per_day": chip,
		"under_infra_sabotage": under_sab,
		"duel_winner": winner,
		"guidance_level": level,
		"rate_at_0_brigades": without_eng,
		"rate_at_1_brigade": get_repair_rate_with_engineer_brigades(province_id, 1.0),
		"rate_at_2_brigades": get_repair_rate_with_engineer_brigades(province_id, 2.0),
		"engineer_cap": INFRA_REPAIR_ENGINEER_CAP,
	}


func _engineer_repair_bonus(engineer_brigades: float) -> float:
	if engineer_brigades <= 0.0:
		return 0.0
	return clampf(
		INFRA_REPAIR_ENGINEER_BASE + engineer_brigades * INFRA_REPAIR_ENGINEER_PER_BRIGADE,
		INFRA_REPAIR_ENGINEER_BASE,
		INFRA_REPAIR_ENGINEER_CAP,
	)


func _depot_sabotage_level(province_id: int) -> float:
	if typeof(SupplyManager) == TYPE_NIL:
		return 0.0
	var depot = SupplyManager.depot_states.get(province_id)
	if depot == null:
		return 0.0
	return float(depot.sabotage_level)


func _province_under_infra_sabotage(province: Province, province_id: int) -> bool:
	if province == null:
		return false
	if typeof(AgentManager) != TYPE_NIL:
		var net: AgentNetwork = AgentManager.networks.get(province_id)
		if (
			net != null
			and net.is_active()
			and net.focus == "infrastructure_sabotage"
		):
			return true
	return false

## --- Internal helpers ---

func _clear_internal_caches() -> void:
	_provinces.clear()
	_geometry.clear()
	_countries.clear()
	_centroids.clear()
	_province_bounds.clear()
	_world_bounds = Rect2()
	_adjacency = null
	if pick_grid != null:
		pick_grid.clear()
	_is_initialized = false

func _recompute_centroids_and_bounds() -> void:
	_centroids.clear()
	_province_bounds.clear()
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	var has_any := false

	for pid_var in _provinces.keys():
		var pid := int(pid_var)
		var geo: Dictionary = _geometry.get(pid, {})
		var points: PackedVector2Array = geo.get("points", PackedVector2Array())

		var c := Vector2.ZERO
		if points.size() >= 3:
			# Reuse the proven centroid math from MapRenderer (or compute average)
			c = _compute_centroid(points)
		else:
			# Fallback to label anchor or rough center
			var anchor: Array = geo.get("label_anchor", [])
			if anchor.size() >= 2:
				c = Vector2(float(anchor[0]), float(anchor[1]))
			elif points.size() > 0:
				c = points[0]

		_centroids[pid] = c
		if points.size() >= 1:
			_province_bounds[pid] = _aabb_from_points(points)
		else:
			_province_bounds[pid] = Rect2(c, Vector2.ZERO)

		if not has_any:
			min_v = c
			max_v = c
			has_any = true
		else:
			min_v.x = minf(min_v.x, c.x)
			min_v.y = minf(min_v.y, c.y)
			max_v.x = maxf(max_v.x, c.x)
			max_v.y = maxf(max_v.y, c.y)

	if has_any:
		_world_bounds = Rect2(min_v, max_v - min_v)
	else:
		_world_bounds = Rect2()

func _aabb_from_points(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var min_v := points[0]
	var max_v := points[0]
	for i in range(1, points.size()):
		var p := points[i]
		min_v.x = minf(min_v.x, p.x)
		min_v.y = minf(min_v.y, p.y)
		max_v.x = maxf(max_v.x, p.x)
		max_v.y = maxf(max_v.y, p.y)
	return Rect2(min_v, max_v - min_v)


func _compute_centroid(points: PackedVector2Array) -> Vector2:
	# Copied & adapted from MapRenderer._calculate_centroid for self-containment
	if points.size() < 3:
		return points[0] if points.size() > 0 else Vector2.ZERO

	var area := 0.0
	var cx := 0.0
	var cy := 0.0
	for i in points.size():
		var p1 := points[i]
		var p2 := points[(i + 1) % points.size()]
		var cross := p1.x * p2.y - p2.x * p1.y
		area += cross
		cx += (p1.x + p2.x) * cross
		cy += (p1.y + p2.y) * cross

	area *= 0.5
	if absf(area) < 0.0001:
		var sum := Vector2.ZERO
		for p in points:
			sum += p
		return sum / float(points.size())

	cx /= (6.0 * area)
	cy /= (6.0 * area)
	return Vector2(cx, cy)

func _try_build_pick_grid() -> void:
	if _centroids.is_empty():
		return
	if pick_grid == null:
		pick_grid = MapPickGrid.new()
	pick_grid.build(_centroids, pick_grid_cell_size)

## Debug / diagnostics
func get_province_count() -> int:
	return _provinces.size()

func is_ready() -> bool:
	return _is_initialized

func has_pick_grid() -> bool:
	return pick_grid != null and pick_grid.is_built()

## Call this after MapRenderer finishes rendering if you want the picker to be perfectly in sync
## (usually not needed because we build from centroids on scenario load).
func rebuild_pick_grid(cell_size: float = -1.0) -> void:
	if cell_size > 0.0:
		pick_grid_cell_size = cell_size
	_try_build_pick_grid()

## Configure picker behavior (useful for different zoom levels or performance tuning)
func configure_picker(centroid_only: bool = false, adaptive: bool = true, min_r: int = 1, max_r: int = 3) -> void:
	if pick_grid != null:
		pick_grid.centroid_only_mode = centroid_only
		pick_grid.adaptive_radius = adaptive
		pick_grid.min_cell_radius = min_r
		pick_grid.max_cell_radius = max_r

## Returns whether the high-performance picker is currently active and usable
func is_spatial_picking_available() -> bool:
	return has_pick_grid() and pick_grid != null and pick_grid.is_built()
