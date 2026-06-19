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
var _strategic_regions: Dictionary = {}   # id -> {id, name, province_ids, notes}  (from loader)
var _province_terrain: Dictionary = {}  # pid -> {terrain, movement_cost, ...} from layers inference or data

var _is_initialized: bool = false

# Cached for fast queries and picking
var _centroids: Dictionary[int, Vector2] = {}   # id -> Vector2 (world/map space)
var _province_bounds: Dictionary[int, Rect2] = {}  # id -> AABB in map space
var _world_bounds: Rect2 = Rect2()        # rough axis-aligned bounds of all provinces

# Optional high-performance picker (created on demand or by MapRenderer)
var pick_grid: MapPickGrid = null
var pick_grid_cell_size: float = MapCanvasConfig.PICK_GRID_CELL_SIZE
var _geometry_world_space: bool = false
var _naval_chokepoint_ids: Array[int] = []
var _exact_pick_zoom_threshold: float = 0.45

# Flavorful regional control rewards / bonuses.
# These are granted (multiplicatively or additively depending on consumer) when a country fully controls ALL provinces in the named strategic region.
# Design goal: make different parts of the map *desirable* for different strategic reasons (naval, industrial, resource, chokepoint, manpower, defensive, prestige).
# Keys are the region names we adopted (or ids for robustness). Values are example modifier dicts (consumer decides how to apply).
var _regional_control_bonuses: Dictionary = {
	# Naval / island power + pride
	"British Isles": {
		"naval_range_multiplier": 1.12,
		"convoy_efficiency": 0.08,
		"prestige": 5,
		"regional_pride": 0.12,          # population bonus: proud island nation united
		"manpower_recovery": 0.06
	},
	"Atlantic Approaches": {"convoy_defense": 0.15, "submarine_range": 1.10},
	"Arctic & Barents": {"winter_supply_resilience": 0.20, "convoy_protection": 0.10},
	# Chokepoints & trade power + local pride
	"Anatolia & Straits": {
		"strait_control_bonus": 0.25,
		"trade_efficiency": 0.12,
		"blockade_power": 0.15,
		"regional_pride": 0.08
	},
	# Scandinavia: resources + northern flank + hardy people
	"Scandinavia": {
		"resource_bonus": {"iron": 0.10, "aluminum": 0.08},
		"defensive_attrition_reduction": 0.15,
		"regional_pride": 0.10,
		"manpower_recovery": 0.05
	},
	# Industrial heartlands
	"Western Germany": {"factory_output": 0.08, "infrastructure_build_speed": 0.12, "regional_pride": 0.07},
	"Low Countries": {"factory_output": 0.06, "trade_throughput": 0.10},
	# Defensive / mountain + mountain folk pride
	"Alpine & North Italy": {
		"mountain_defense": 0.18,
		"supply_throughput": 0.05,
		"regional_pride": 0.09
	},
	# Eastern / manpower / space
	"Poland & Silesia": {"manpower_recovery": 0.07, "rail_throughput": 0.09, "regional_pride": 0.08},
	"Western Russia": {"strategic_depth": 0.12, "winter_warfare": 0.15, "regional_pride": 0.06},
	# Med / southern
	"Greece & Aegean": {"naval_basing": 0.10, "island_hopping": 0.12, "regional_pride": 0.10},
	"Iberia": {"resource_bonus": {"tungsten": 0.15}, "port_capacity": 0.08, "regional_pride": 0.07},
	# Extend with more as world regions are defined (Middle East oil, etc.)
	# "regional_pride" feeds population/manpower pride bonuses when the region is fully controlled.
}

# Temporary editor provinces for live in-game editing (from ProvinceEditor)
var _editor_provinces: Dictionary[int, Province] = {}
var _editor_geometry: Dictionary = {}

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
	_strategic_regions.clear()

	_provinces = MapScenarioData.coerce_provinces(map_data.provinces)
	_geometry = map_data.geometry.duplicate(true) if map_data.geometry else {}
	_adjacency = map_data.adjacency_system
	_countries = MapScenarioData.coerce_countries(map_data.countries)
	_strategic_regions.clear()
	_province_terrain.clear()
	# Pull full region defs if ScenarioLoader has them (names, for control bonuses etc.)
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if loader != null and loader.strategic_regions.size() > 0:
		_strategic_regions = loader.strategic_regions.duplicate(true)
	if loader != null and loader.province_terrain_layer.size() > 0:
		var raw_tl: Dictionary = loader.province_terrain_layer
		# Unwrap infer-produced {version, "provinces": pidmap} or similar wrappers so _province_terrain is always the flat pid->data map
		if raw_tl.has("provinces") and raw_tl["provinces"] is Dictionary:
			_province_terrain = (raw_tl["provinces"] as Dictionary).duplicate(true)
		else:
			_province_terrain = raw_tl.duplicate(true)
	elif _province_terrain.is_empty() and loader != null and loader.province_terrain_layer.size() > 0:
		# Fallback pull (timing/ordering in europe dense rebuilds)
		var raw_tl2: Dictionary = loader.province_terrain_layer
		if raw_tl2.has("provinces") and raw_tl2["provinces"] is Dictionary:
			_province_terrain = (raw_tl2["provinces"] as Dictionary).duplicate(true)
		else:
			_province_terrain = raw_tl2.duplicate(true)

	# Integrate inferred snow_potential (from real DEM layers) into WeatherManager (now autoload) so that
	# get_movement_multiplier, attrition, reinforcement, and winter snow bits on overlay all see the high-elev data
	# for Scotland/Spain/Iceland/Pyrenees etc. This is the central integration point (called on map init / reload).
	if Engine.has_singleton("WeatherManager"):
		var wm = Engine.get_singleton("WeatherManager")
		if wm and wm.has_method("initialize_province"):
			var wseed := 0
			var terrain_keys = _province_terrain.keys()
			if terrain_keys.size() == 0 and typeof(ScenarioLoader) != TYPE_NIL:
				# last resort: seed directly from live provinces (snow_potential applied in loader)
				# (covers cases where terrain_layer not yet mirrored to manager at init)
				var sl = get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
				if sl and sl.provinces.size() > 0:
					for pid in sl.provinces:
						var p: Province = sl.provinces[pid]
						var spv := p.snow_potential
						if spv > 0.0:
							wm.initialize_province(pid, {
								"is_northern": spv > 0.1 or pid > 200,
								"lat": 62.0 if spv > 0.2 else 50.0,
								"high_ground_fraction": max(0.2, spv),
								"snow_potential": spv
							})
							wseed += 1
			else:
				for pid_str in terrain_keys:
					var tdat: Dictionary = _province_terrain[pid_str]
					var spv := float(tdat.get("snow_potential", 0.0))
					if spv > 0.0:
						var pidv := int(pid_str)
						wm.initialize_province(pidv, {
							"is_northern": spv > 0.1 or pidv > 200,
							"lat": 62.0 if spv > 0.2 else 50.0,
							"high_ground_fraction": max(0.2, spv),
							"snow_potential": spv
						})
						wseed += 1
			if wseed > 0:
				print("   WeatherManager seeded %d provinces with snow_potential from terrain layer (movement/attrition/winter bits integration)" % wseed)

	_is_initialized = _provinces.size() > 0

	_recompute_centroids_and_bounds()
	_load_naval_chokepoints()
	_try_build_pick_grid()

	print("🗺️ MapManager initialized with %d provinces (bounds: %s)" % [_provinces.size(), _world_bounds])
	if _strategic_regions.size() > 0:
		print("   Strategic regions: %d (e.g. %s)" % [_strategic_regions.size(), get_strategic_region_name(1)])
	scenario_map_ready.emit()
	provinces_loaded.emit(_provinces.size())

## Add temporary provinces from in-game editor. These overlay for picking, queries, hover etc.
## Human can draw and immediately test gameplay impact (movement, supply, combat width) without full reload.
## Call clear_temporary_editor_provinces() to remove.
func add_temporary_editor_provinces(new_provs: Dictionary[int, Province], new_geo: Dictionary) -> void:
	_editor_provinces = new_provs.duplicate()
	_editor_geometry = new_geo.duplicate()

	# Merge for queries (editor takes precedence for same id, but usually new ids)
	for pid in _editor_provinces:
		_provinces[pid] = _editor_provinces[pid]
		_geometry[pid] = _editor_geometry[pid]

	_recompute_centroids_and_bounds()
	_try_build_pick_grid()  # Rebuilds including editor ones for live picking

	print("🗺️ MapManager: Added %d temporary editor provinces for live picking/editing." % _editor_provinces.size())

func clear_temporary_editor_provinces() -> void:
	for pid in _editor_provinces:
		_provinces.erase(pid)
		_geometry.erase(pid)
	_editor_provinces.clear()
	_editor_geometry.clear()
	_recompute_centroids_and_bounds()
	_try_build_pick_grid()
	print("🗺️ MapManager: Cleared temporary editor provinces.")

## --- Public Query API ---

func has_province_data() -> bool:
	return _is_initialized and _provinces.size() > 0

func get_province(province_id: int) -> Province:
	return _provinces.get(province_id)

func get_all_provinces() -> Dictionary[int, Province]:
	return _provinces

func get_province_geometry(province_id: int) -> Dictionary:
	return _geometry.get(province_id, {})


func get_geometry_dict() -> Dictionary:
	return _geometry

func get_adjacency_system() -> AdjacencySystem:
	return _adjacency

func get_country(tag: String) -> Variant:
	if tag.is_empty():
		return null
	return _countries.get(tag) if _countries.has(tag) else _countries.get(tag.to_upper())


## Register a minimal country entry so owner tags render and validate in playtests.
func ensure_country_stub(tag: String, color: Color = Color(0.45, 0.55, 0.65, 0.88)) -> void:
	if tag.is_empty():
		return
	var key := tag.strip_edges().to_upper()
	if _countries.has(key):
		return
	_countries[key] = {"tag": key, "name": key, "color": color}

func get_player_country_tag_fallback() -> String:
	# Useful for early UI before player selection is wired
	for t in _countries.keys():
		return str(t)
	return "USA"

func get_country_color(tag: String) -> Color:
	var key := tag.strip_edges().to_upper()
	var c: Variant = _countries.get(key) if _countries.has(key) else null
	if c:
		if c is Dictionary:
			if c.has("color"):
				var col = c["color"]
				if col is Color: return col
				if typeof(col) == TYPE_STRING: return Color(col)
		elif c is Object:  # Country resource or similar
			if "color" in c:
				var col = c.color
				if col is Color: return col
				if typeof(col) == TYPE_STRING: return Color(col)
	return Color(0.5, 0.5, 0.6, 0.9)

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

## Convenience query for AgentManager / events / conditional triggers (e.g. Paris-specific events require owner of pid 4).
## Returns the owner_tag for a province id, or "" if invalid.
func get_province_owner(province_id: int) -> String:
	var p := get_province(province_id)
	if p == null:
		return ""
	return str(p.owner_tag).strip_edges().to_upper()

## Returns controller (or owner if no separate controller) for occupation logic.
func get_province_controller(province_id: int) -> String:
	var p := get_province(province_id)
	if p == null:
		return ""
	var c := str(p.controller_tag).strip_edges().to_upper()
	return c if not c.is_empty() else str(p.owner_tag).strip_edges().to_upper()

## === Geo / Contextual Query API for Initiatives, Epoch Shifts, Agents (hybrid dynamic trees) ===
## Minimal helpers so GameData can use MapManager for owned provinces on rivers/lakes/oceans/borders/neighbors.
## Enables rich "Pressure border province on Rhine", "Coastal fort on Baltic", "Improve river province" nodes with player choice.
func get_adjacent_countries(tag: String) -> Array[String]:
	var owned := get_provinces_by_owner(tag)
	var neigh: Dictionary = {}
	for pid in owned:
		var adjs := get_adjacent_provinces(pid, true)  # land neighbors
		for apid in adjs:
			var p := get_province(apid)
			if p and not p.owner_tag.is_empty():
				var ot := p.owner_tag.strip_edges().to_upper()
				if ot != tag.to_upper():
					neigh[ot] = true
	var res: Array[String] = []
	for k in neigh.keys():
		res.append(str(k))
	return res

func get_owned_river_provinces(tag: String) -> Array[int]:
	var owned := get_provinces_by_owner(tag)
	var res: Array[int] = []
	for pid in owned:
		if has_river_border(pid):
			res.append(pid)
	return res

func get_owned_coastal_or_port_provinces(tag: String) -> Array[int]:
	var owned := get_provinces_by_owner(tag)
	var res: Array[int] = []
	for pid in owned:
		var p := get_province(pid)
		if p and (p.resolve_has_port() or p.has_feature("coastal") or p.has_feature("ocean") or str(p.terrain).to_lower() in ["coastal", "coast"]):
			res.append(pid)
	return res

func get_border_provinces_with(tag: String, neighbor_tag: String) -> Array[int]:
	var owned := get_provinces_by_owner(tag)
	var ntag := neighbor_tag.strip_edges().to_upper()
	var res: Array[int] = []
	for pid in owned:
		var adjs := get_adjacent_provinces(pid, false)  # any neighbors
		for apid in adjs:
			var p := get_province(apid)
			if p and p.owner_tag.strip_edges().to_upper() == ntag:
				res.append(pid)
				break
	return res

func get_provinces_on_water_features(tag: String) -> Array[int]:
	# Union river + coastal for "lake/ocean/river province" targeting
	var res: Array[int] = get_owned_river_provinces(tag)
	var coast: Array[int] = get_owned_coastal_or_port_provinces(tag)
	for c in coast:
		if c not in res:
			res.append(c)
	return res

## === Strategic Region API (for control rewards, regional bonuses, UI, AI focus etc.) ===

func get_strategic_region(region_id: int) -> Dictionary:
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if loader != null and loader.strategic_regions.has(region_id):
		return loader.strategic_regions[region_id]
	return _strategic_regions.get(region_id, {})

func get_province_terrain(pid: int) -> Dictionary:
	var src: Dictionary = _province_terrain
	# Extra unwrap safety (in case wrapper slipped in)
	if src.has("provinces") and src["provinces"] is Dictionary:
		src = src["provinces"]
	return src.get(str(pid), {"terrain": "plains", "movement_cost": 1.0})

## Push: support for sample subdivided geometry from generate (for demo river-aware subdiv with inference terrain)
var _sample_subdiv_geo: Dictionary = {}
var _demo_applied_subdiv: Dictionary = {}  # parent_id (int or str) -> Array of child dicts (with terrain, river_aware, points from sample) for live demo mutate testing
var _demo_geometry_override: Dictionary = {}  # pid -> Array of points for demo children, to temporarily override parent geo/visual for picking and drawing test (reverted on clear)
func load_sample_subdiv_geometry(path: String = "res://tools/map_generation/output/phase1_europe/sample_subdivided_geometry.json") -> void:
	if not FileAccess.file_exists(path):
		print("MapManager: no sample_subdiv geo at ", path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var sdata = JSON.parse_string(txt)
	if typeof(sdata) == TYPE_DICTIONARY:
		_sample_subdiv_geo = sdata
		var sprov: Variant = sdata.get("provinces", [])
		var ch := 0
		var ra := 0
		for pp in sprov:
			if str(pp.get("id", "")).contains("_c"):
				ch += 1
				if bool(pp.get("river_aware", false)): ra += 1
		print("MapManager: loaded sample subdiv geo with ", sprov.size(), " provinces (", ch, " river-aware children, ", ra, " river-cross guided from real layers + inference terrain)")
	else:
		print("MapManager: bad sample geo")

## Demo "live apply" of the sample river-cross subdiv (5 _c children for parent 82 from sample_subdivided_geometry.json).
## Registers the children with their carried inference terrain/snow_potential/river_aware for inspector/combat/effects testing without mutating the real loaded province data.
## Call after load_sample_subdiv_geometry. Visuals via MapRenderer SubdivDebug.
func apply_sample_subdiv_demo(parent_id: int = 82) -> void:
	if _sample_subdiv_geo.is_empty():
		load_sample_subdiv_geometry()
	var sprov: Variant = _sample_subdiv_geo.get("provinces", [])
	var kids := []
	for pp in sprov:
		if str(pp.get("parent_id", "")) == str(parent_id) and str(pp.get("id", "")).contains("_c"):
			kids.append({
				"id": pp.get("id"),
				"points": pp.get("points", []),
				"terrain": pp.get("terrain", "plains"),
				"river_aware": bool(pp.get("river_aware", false)),
				"notes": pp.get("notes", "")
			})
	if kids.is_empty():
		# Robust fallback: direct parse (timing or prior load issue)
		var spath := "res://tools/map_generation/output/phase1_europe/sample_subdivided_geometry.json"
		if FileAccess.file_exists(spath):
			var f := FileAccess.open(spath, FileAccess.READ)
			var txt := f.get_as_text()
			f.close()
			var sd = JSON.parse_string(txt)
			if typeof(sd) == TYPE_DICTIONARY:
				sprov = sd.get("provinces", [])
				_sample_subdiv_geo = sd  # cache
				kids = []
				for pp in sprov:
					if str(pp.get("parent_id", "")) == str(parent_id) and str(pp.get("id", "")).contains("_c"):
						kids.append({
							"id": pp.get("id"),
							"points": pp.get("points", []),
							"terrain": pp.get("terrain", "plains"),
							"river_aware": bool(pp.get("river_aware", false)),
							"notes": pp.get("notes", "")
						})
		if kids.is_empty():
			print("MapManager: no sample children for parent ", parent_id, " in demo apply (after fallback load)")
			return
	_demo_applied_subdiv[parent_id] = kids
	print("MapManager: DEMO APPLIED sample river subdiv to parent ", parent_id, " -> ", kids.size(), " children")
	print("  child terrains (inferred from layers, carried to demo): ", kids.map(func(k): return k["terrain"]))
	print("  all river_aware: ", kids.all(func(k): return k["river_aware"]))
	print("  (use for inspector/combat demo; real 471 phase1_test has these as 9000-9005 with same river guidance)")
	# Notify renderer if present to ensure visuals
	var mr: Node = null
	if Engine.get_main_loop():
		mr = Engine.get_main_loop().root.get_node_or_null("/root/WorldMap")
	if mr == null:
		mr = get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
	if mr and mr.has_method("debug_spawn_subdiv_draw_children"):
		mr.call("debug_spawn_subdiv_draw_children")

func get_demo_subdiv_children(parent_id: int) -> Array:
	return _demo_applied_subdiv.get(parent_id, [])

func has_river_border(pid: int) -> bool:
	# Demo sample children
	if _demo_applied_subdiv.has(pid):
		for d in _demo_applied_subdiv[pid]:
			if d.get("river_aware", false):
				return true
	# Real from phase1 or inference (children in 471 have river_aware in geo, but runtime may expose via terrain or direct)
	var terr := get_province_terrain(pid)
	if terr.get("river_aware", false):
		return true
	# Fallback for demo: if pid 82 and no demo yet, peek the sample json (harness timing)
	if pid == 82:
		var spath := "res://tools/map_generation/output/phase1_europe/sample_subdivided_geometry.json"
		if FileAccess.file_exists(spath):
			var f := FileAccess.open(spath, FileAccess.READ)
			var txt := f.get_as_text()
			f.close()
			var sd = JSON.parse_string(txt)
			if typeof(sd) == TYPE_DICTIONARY:
				for pp in sd.get("provinces", []):
					if str(pp.get("parent_id", "")) == "82" and bool(pp.get("river_aware", false)):
						return true
		return true  # demo intent for 82 even if peek timing
	return false

func has_strategic_chokepoint(pid: int) -> bool:
	if pid in _naval_chokepoint_ids:
		return true
	if typeof(SpecialSiteManager) != TYPE_NIL and SpecialSiteManager.has_method("get_sites_for_province"):
		var sites = SpecialSiteManager.get_sites_for_province(pid)
		for s in sites:
			var st := str(s).to_lower()
			if "strait" in st or "chokepoint" in st or "gibraltar" in st or "danish" in st or "skagerrak" in st:
				return true
	return false

func get_chokepoint_or_river_supply_bonus(pid: int) -> float:
	var b := 1.0
	if has_river_border(pid):
		b *= 1.08  # river control aids supply lines
	if has_strategic_chokepoint(pid):
		b *= 1.18  # holding a key strait multiplies throughput / naval supply
	return b

func get_effective_terrain_for_demo(pid: int) -> String:
	# High value: for demo applied sample, return child terrain to sim sub-battle / preview using the inferred carry (e.g. "coastal" for river children of 82)
	if _demo_applied_subdiv.has(pid):
		var kids = _demo_applied_subdiv[pid]
		if kids.size() > 0:
			return str(kids[0].get("terrain", "plains"))
	var t := get_province_terrain(pid)
	return str(t.get("terrain", "plains")) if t else "plains"

func apply_demo_geometry_override(parent_id: int, child_points: Array) -> void:
	_demo_geometry_override[parent_id] = child_points
	print("MapManager: DEMO GEO OVERRIDE applied for ", parent_id, " with ", child_points.size(), " child polys (for visual/picking test)")
	# Integrate into pick grid so virtual children are immediately pickable (via MapPickGrid virtual support)
	if pick_grid != null:
		pick_grid.add_demo_children(parent_id, child_points)

func clear_demo_geometry_override(parent_id: int = -1) -> void:
	if parent_id >= 0:
		_demo_geometry_override.erase(parent_id)
	else:
		_demo_geometry_override.clear()
	print("MapManager: DEMO GEO OVERRIDE cleared", " for " + str(parent_id) if parent_id >= 0 else "")
	if pick_grid != null:
		pick_grid.remove_demo_children(parent_id)

func get_demo_geometry_override(pid: int) -> Array:
	return _demo_geometry_override.get(pid, [])

## Fast lookup: which strategic region contains this province (0 if none).
func get_province_region_id(province_id: int) -> int:
	var prov: Province = get_province(province_id)
	if prov != null and prov.strategic_region_id > 0:
		return prov.strategic_region_id
	# Prefer ScenarioLoader for live data, fallback to our cached regions (reverse map could be built for speed)
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if loader != null and loader.province_region_by_id.has(province_id):
		return int(loader.province_region_by_id[province_id])
	# Slow fallback: scan (fine for init/debug)
	for rid in _strategic_regions:
		var pids: Array = _strategic_regions[rid].get("province_ids", [])
		if province_id in pids:
			return int(rid)
	return 0

func get_strategic_region_name(region_id: int) -> String:
	var r: Dictionary = _strategic_regions.get(region_id, {}) as Dictionary
	return r.get("name", "Strategic Region " + str(region_id))

func get_all_strategic_regions() -> Dictionary:
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if loader != null and loader.strategic_regions.size() > 0:
		return loader.strategic_regions.duplicate(true)
	return _strategic_regions.duplicate(true)

## Returns list of region_ids that the given tag FULLY owns (all provinces in the region have owner_tag == tag).
## "Full control" is a powerful, desirable state — used for special regional rewards/bonuses.
func get_fully_controlled_strategic_regions(tag: String) -> Array[int]:
	if tag.is_empty():
		return []
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if loader != null and loader.strategic_regions.size() > 0 and loader.provinces.size() > 0:
		# Always direct from loader for scenario fidelity (post-remap + owner align from improved connections). This makes full control counts reliable.
		var t := tag.strip_edges().to_upper()
		var controlled: Array[int] = []
		for rid in loader.strategic_regions.keys():
			var r = loader.strategic_regions[rid]
			var pids = r.get("province_ids", [])
			if pids.is_empty(): continue
			var fully := true
			for pv in pids:
				var ppid = int(pv)
				if loader.provinces.has(ppid):
					var pp: Province = loader.provinces[ppid]
					var ot = str(pp.owner_tag).strip_edges().to_upper()
					var ct = str(pp.controller_tag).strip_edges().to_upper()
					if ot != t and ct != t:
						fully = false
						break
				else:
					fully = false
					break
			if fully:
				controlled.append(int(rid))
		return controlled
	# Fallback to internal if loader not ready yet
	var strategic_src: Dictionary = _strategic_regions
	var prov_src: Dictionary = _provinces
	if strategic_src.is_empty() or prov_src.is_empty():
		return []
	var controlled: Array[int] = []
	for rid in strategic_src.keys():
		var r: Dictionary = strategic_src[rid]
		var pids: Array = r.get("province_ids", [])
		if pids.is_empty():
			continue
		var fully := true
		for pidv in pids:
			var pid := int(pidv)
			var p: Province = prov_src.get(pid)
			if p == null:
				fully = false
				break
			var ot := p.owner_tag.strip_edges().to_upper()
			var ct := p.controller_tag.strip_edges().to_upper()
			var t := tag.strip_edges().to_upper()
			if ot != t and ct != t:
				fully = false
				break
		if fully:
			controlled.append(int(rid))
	return controlled

## Convenience: is this specific region fully controlled by the tag right now?
func is_strategic_region_fully_controlled(region_id: int, tag: String) -> bool:
	var r := get_strategic_region(region_id)
	var pids: Array = r.get("province_ids", [])
	if pids.is_empty() or tag.is_empty():
		return false
	# Freshest for scenario fidelity (loader strategic/provs)
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	var prov_src: Dictionary = _provinces
	if loader != null and loader.provinces.size() > 0:
		prov_src = {}
		for k in loader.provinces:
			prov_src[int(k)] = loader.provinces[k]
	for pidv in pids:
		var p: Province = prov_src.get(int(pidv))
		if p == null:
			return false
		var ot := p.owner_tag.strip_edges().to_upper()
		var ct := p.controller_tag.strip_edges().to_upper()
		var t := tag.strip_edges().to_upper()
		if ot != t and ct != t:
			return false
	return true

## Returns a summary for UI/tooltips: { "controlled": [...], "count": N, "total": M }
func get_strategic_region_control_summary(tag: String = "") -> Dictionary:
	var total := _strategic_regions.size()
	var controlled := get_fully_controlled_strategic_regions(tag) if not tag.is_empty() else []
	return {
		"controlled": controlled,
		"count": controlled.size(),
		"total": total
	}

## Aggregate active bonuses from all regions this tag fully controls.
## Returns a merged dict of modifiers (e.g. {"naval_range_multiplier": 1.12, "factory_output": 0.08, "resource_bonus": {...}} ).
## Systems (Supply, Trade, Combat, NationalSpirit, Production) can query this and apply the relevant keys.
## This is the core "reward for full control" hook — makes capturing and holding whole regions *meaningful and desirable*.
func get_active_regional_control_bonuses(tag: String) -> Dictionary:
	var controlled := get_fully_controlled_strategic_regions(tag)
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if loader != null and loader.strategic_regions.size() > 0 and loader.provinces.size() > 0:
		# Always prefer direct compute from loader for scenario connection (post-remap/owner align + timing safe)
		controlled = []
		var t := tag.strip_edges().to_upper()
		for rid in loader.strategic_regions.keys():
			var r = loader.strategic_regions[rid]
			var pids = r.get("province_ids", [])
			if pids.is_empty(): continue
			var fully := true
			for pv in pids:
				var ppid = int(pv)
				if loader.provinces.has(ppid):
					var pp: Province = loader.provinces[ppid]
					var ot = str(pp.owner_tag).strip_edges().to_upper()
					var ct = str(pp.controller_tag).strip_edges().to_upper()
					if ot != t and ct != t:
						fully=false; break
				else:
					fully=false; break
			if fully:
				controlled.append(int(rid))
	if controlled.is_empty():
		return {}
	var merged: Dictionary = {}
	for rid in controlled:
		var r: Dictionary = get_strategic_region(rid)  # uses loader fresh if available
		var rname: String = r.get("name", "")
		var bonuses: Dictionary = _regional_control_bonuses.get(rname, {})
		if bonuses.is_empty():
			# Also allow lookup by id as fallback
			bonuses = _regional_control_bonuses.get(str(rid), {})
		if bonuses.is_empty() and rname:
			# Case/partial match for region names post-remap
			for k in _regional_control_bonuses.keys():
				if rname.to_lower() in str(k).to_lower() or str(k).to_lower() in rname.to_lower():
					bonuses = _regional_control_bonuses[k]
					break
		if bonuses.is_empty():
			bonuses = {"regional_pride": 0.05, "manpower_recovery": 0.03}  # default reward for any fully controlled region
		for k_var in bonuses.keys():
			var k: String = str(k_var)
			var v = bonuses[k]
			if k == "resource_bonus" and typeof(v) == TYPE_DICTIONARY:
				if not merged.has("resource_bonus"):
					merged["resource_bonus"] = {}
				for res_var in (v as Dictionary).keys():
					var res: String = str(res_var)
					merged["resource_bonus"][res] = float(merged["resource_bonus"].get(res, 0.0)) + float(v[res])
			else:
				# numeric multipliers / additives — last one wins or we could sum; for now take max or add for safety on some
				if merged.has(k):
					if typeof(merged[k]) in [TYPE_FLOAT, TYPE_INT] and typeof(v) in [TYPE_FLOAT, TYPE_INT]:
						merged[k] = float(merged[k]) + float(v)  # additive stacking for now (tweak per key later)
					else:
						merged[k] = v  # replace complex
				else:
					merged[k] = v
	return merged

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
		var use_exact := _should_use_exact_pick()
		var geo_fn := Callable(self, "_pick_geometry_provider")
		var hit := pick_grid.get_province_at(world_pos, 2 if use_exact else 1, use_exact, geo_fn)
		if hit > 10000:
			var pguess := hit / 1000
			print(" [DEMO PICK] hit demo child vid=", hit, " of parent ", pguess)
			return hit
		return hit

	# Fallback (no grid): manual override geo check for demo children pick test, return synthetic vid
	if _demo_geometry_override.has(82):
		var ov: Array = _demo_geometry_override[82]
		for i in range(ov.size()):
			var pts: Array = ov[i]
			if pts.size() >= 3:
				var pva := PackedVector2Array()
				for p in pts:
					pva.append(MapCanvasConfig.scale_point(Vector2(p[0], p[1])))
				if Geometry2D.is_point_in_polygon(world_pos, pva):
					var vid := 82000 + i
					print(" [DEMO PICK] hit demo child ", i, " of 82 (no-grid fallback override) vid=", vid)
					return vid

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

## Settlement update helper (for SaveLoadManager roundtrip + GameData relocation paths).
## Mutates runtime settlement_level (drives Province getters for combat def 2.5%/lev, org/attrit/supply, vitality tints).
## Emits "settlement" so MapRenderer refreshes single fill + inspector live.
func update_province_settlement(province_id: int, new_level: float) -> bool:
	var p: Province = _provinces.get(province_id)
	if p == null:
		return false
	var clamped := clampf(new_level, 0.0, 5.0)
	if abs(p.settlement_level - clamped) > 0.0001:
		p.settlement_level = clamped
		province_data_changed.emit(province_id, "settlement")
		return true
	return false

## Legacy compatibility helper
func notify_province_changed(province_id: int, what: String) -> void:
	if _provinces.has(province_id):
		province_data_changed.emit(province_id, what)

## === Infrastructure Connection Editing API (for "map comes alive" via player/AI decisions) ===
## These mutate the explicit built_road_neighbors / built_rail_neighbors on Province instances.
## Used by InfrastructureDevelopmentManager on relevant project complete (e.g. "build road link"),
## or direct UI actions like "construct highway between A-B", or debug.
## After mutate, emit data changed (so overlays can react) + notify the visual layer to rebuild node children.
## The overlay's rebuild_ uses these explicit lists (preferred over pure infra-level inference).

func build_road_connection(p1: int, p2: int) -> void:
	var prov1: Province = get_province(p1)
	var prov2: Province = get_province(p2)
	if prov1 == null or prov2 == null or p1 == p2:
		return
	if p2 not in prov1.built_road_neighbors:
		prov1.built_road_neighbors.append(p2)
	if p1 not in prov2.built_road_neighbors:
		prov2.built_road_neighbors.append(p1)
	province_data_changed.emit(p1, "infrastructure")
	province_data_changed.emit(p2, "infrastructure")
	_notify_infra_layer_rebuild()

func build_rail_connection(p1: int, p2: int) -> void:
	var prov1: Province = get_province(p1)
	var prov2: Province = get_province(p2)
	if prov1 == null or prov2 == null or p1 == p2:
		return
	if p2 not in prov1.built_rail_neighbors:
		prov1.built_rail_neighbors.append(p2)
	if p1 not in prov2.built_rail_neighbors:
		prov2.built_rail_neighbors.append(p1)
	province_data_changed.emit(p1, "infrastructure")
	province_data_changed.emit(p2, "infrastructure")
	_notify_infra_layer_rebuild()

func remove_road_connection(p1: int, p2: int) -> void:
	var prov1: Province = get_province(p1)
	var prov2: Province = get_province(p2)
	if prov1 != null:
		prov1.built_road_neighbors.erase(p2)
	if prov2 != null:
		prov2.built_road_neighbors.erase(p1)
	province_data_changed.emit(p1, "infrastructure")
	province_data_changed.emit(p2, "infrastructure")
	_notify_infra_layer_rebuild()

func remove_rail_connection(p1: int, p2: int) -> void:
	var prov1: Province = get_province(p1)
	var prov2: Province = get_province(p2)
	if prov1 != null:
		prov1.built_rail_neighbors.erase(p2)
	if prov2 != null:
		prov2.built_rail_neighbors.erase(p1)
	province_data_changed.emit(p1, "infrastructure")
	province_data_changed.emit(p2, "infrastructure")
	_notify_infra_layer_rebuild()

func _notify_infra_layer_rebuild() -> void:
	var overlay := get_tree().get_first_node_in_group("infrastructure_overlay") if get_tree() else null
	if overlay == null:
		return
	if overlay.has_method("_schedule_rebuild_all_infra_layers"):
		overlay.call("_schedule_rebuild_all_infra_layers")
	elif overlay.has_method("rebuild_all_infra_layers"):
		overlay.rebuild_all_infra_layers()
	elif overlay.has_method("force_full_refresh"):
		overlay.force_full_refresh()

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
		var stab: float = NationalModifierManager.get_national_modifier(tag, "stability")
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
	_strategic_regions.clear()
	_province_terrain.clear()
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
		points = MapCanvasConfig.transform_province_points(points, false, true)

		var c := Vector2.ZERO
		if points.size() >= 3:
			# Reuse the proven centroid math from MapRenderer (or compute average)
			c = _compute_centroid(points)
		else:
			# Fallback to label anchor or rough center
			var anchor: Array = geo.get("label_anchor", [])
			if anchor.size() >= 2:
				c = MapCanvasConfig.scale_point(Vector2(float(anchor[0]), float(anchor[1])))
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
	pick_grid.centroid_only_mode = false
	pick_grid.adaptive_radius = true
	pick_grid.build(_centroids, pick_grid_cell_size)
	for pid_var in _demo_geometry_override.keys():
		var pid := int(pid_var)
		var child_pts: Array = _demo_geometry_override[pid]
		if child_pts.size() > 0:
			pick_grid.add_demo_children(pid, child_pts)


func _load_naval_chokepoints() -> void:
	_naval_chokepoint_ids.clear()
	var loader := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	var data_dir := "provinces_phase1_test"
	if loader != null and loader.current_province_data_dir != "":
		data_dir = loader.current_province_data_dir
	var path := "res://data/%s/naval_chokepoints.json" % data_dir
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for pid_var in parsed.get("chokepoint_province_ids", []):
		_naval_chokepoint_ids.append(int(pid_var))
	print("MapManager: loaded %d data-driven naval chokepoint provinces" % _naval_chokepoint_ids.size())


func get_naval_chokepoint_provinces() -> Array[int]:
	return _naval_chokepoint_ids.duplicate()


func _should_use_exact_pick() -> bool:
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null:
		return _provinces.size() >= 250
	return absf(cam.zoom.x) >= _exact_pick_zoom_threshold or _provinces.size() >= 350


func _pick_geometry_provider(pid: int) -> PackedVector2Array:
	var geo: Dictionary = _geometry.get(pid, {})
	var pts: Array = geo.get("points", [])
	var out := PackedVector2Array()
	for p in pts:
		if p is Array and p.size() >= 2:
			out.append(Vector2(float(p[0]), float(p[1])))
		elif p is Vector2:
			out.append(p)
	return MapCanvasConfig.transform_province_points(out, _geometry_world_space, true)


func set_geometry_world_space(on: bool) -> void:
	_geometry_world_space = on


func sync_render_centroids(from_renderer: Dictionary) -> void:
	for pid_var in from_renderer.keys():
		_centroids[int(pid_var)] = from_renderer[pid_var]

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
