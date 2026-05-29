class_name ScenarioLoader
extends Node

var base_provinces: Dictionary = {}
var provinces: Dictionary = {}
## Key = country tag (e.g. "GER"); value = Country resource or plain Dictionary with at least `color` (and usually `tag`, `name`).
var countries: Dictionary = {}
var province_geometry: Dictionary = {}
var province_adjacency: Dictionary = {}
var province_terrain_layer: Dictionary = {}
var province_city_layer: Dictionary = {}
var province_economy_layer: Dictionary = {}
var province_resources_layer: Dictionary = {}
var province_state_by_id: Dictionary = {}
var province_region_by_id: Dictionary = {}
var province_projects_by_id: Dictionary = {}

## Built when a scenario is loaded; used by MapRenderer.initialize and pathfinding helpers.
var adjacency_system: AdjacencySystem

## Current/last loaded scenario name (for SaveLoadManager metadata and validation).
var current_scenario_name: String = ""

## Allows test scenarios (like the procedurally generated Phase 1 map) to use their own province data folder.
var current_province_data_dir: String = "provinces"

signal scenario_loaded()

func get_current_scenario_name() -> String:
	return current_scenario_name

func _ready():
	load_province_geometry()
	load_province_layers()
	load_base_provinces()
	add_to_group("scenario_loader")

func load_province_geometry(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir

	var file_path = "res://data/" + data_dir + "/provinces_geometry.json"
	province_geometry.clear()
	if not FileAccess.file_exists(file_path):
		push_warning("Province geometry file missing: " + file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("Could not open province geometry file: " + file_path)
		return

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		push_warning("Failed to parse province geometry JSON")
		return

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Province geometry JSON root must be a dictionary")
		return

	var entries = data.get("provinces", [])
	if typeof(entries) != TYPE_ARRAY:
		push_warning("Province geometry 'provinces' must be an array")
		return

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var province_id = int(entry.get("id", 0))
		if province_id <= 0:
			continue
		province_geometry[province_id] = entry

	print("✅ Province geometry loaded: ", province_geometry.size(), " (from ", data_dir, ")")

func load_province_layers(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	_load_adjacency_layer(data_dir)
	_load_terrain_layer(data_dir)
	_load_city_layer(data_dir)
	_load_resources_layer(data_dir)
	_load_economy_layer(data_dir)
	_load_state_and_region_layers(data_dir)
	_load_project_sites_layer(data_dir)

func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Missing layer file: " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("Could not open layer file: " + path)
		return {}
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Failed to parse layer file: " + path)
		return {}
	return json.data

func _load_adjacency_layer(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	province_adjacency.clear()
	var data = _load_json_dict("res://data/" + data_dir + "/province_adjacency.json")
	var raw = data.get("adjacency", {})
	if typeof(raw) == TYPE_DICTIONARY:
		province_adjacency = raw

func _load_terrain_layer(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	province_terrain_layer.clear()
	var data = _load_json_dict("res://data/" + data_dir + "/province_terrain_layer.json")
	var raw = data.get("provinces", {})
	if typeof(raw) == TYPE_DICTIONARY:
		province_terrain_layer = raw

func _load_city_layer(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	province_city_layer.clear()
	var data = _load_json_dict("res://data/" + data_dir + "/province_city_layer.json")
	var raw = data.get("provinces", {})
	if typeof(raw) == TYPE_DICTIONARY:
		province_city_layer = raw

func _load_resources_layer(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	province_resources_layer.clear()
	var data = _load_json_dict("res://data/" + data_dir + "/province_resources_layer.json")
	var raw = data.get("provinces", {})
	if typeof(raw) == TYPE_DICTIONARY:
		province_resources_layer = raw

func _load_economy_layer(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	province_economy_layer.clear()
	var data = _load_json_dict("res://data/" + data_dir + "/province_economy_layer.json")
	var raw = data.get("provinces", {})
	if typeof(raw) == TYPE_DICTIONARY:
		province_economy_layer = raw

func _load_state_and_region_layers(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	province_state_by_id.clear()
	province_region_by_id.clear()
	var states_data = _load_json_dict("res://data/" + data_dir + "/province_states.json")
	var states = states_data.get("states", [])
	if typeof(states) == TYPE_ARRAY:
		for s in states:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var state_id = int(s.get("id", 0))
			var pids = s.get("province_ids", [])
			if typeof(pids) == TYPE_ARRAY:
				for pid in pids:
					province_state_by_id[int(pid)] = state_id

	var regions_data = _load_json_dict("res://data/" + data_dir + "/strategic_regions.json")
	var regions = regions_data.get("regions", [])
	if typeof(regions) == TYPE_ARRAY:
		for r in regions:
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var region_id = int(r.get("id", 0))
			var pids = r.get("province_ids", [])
			if typeof(pids) == TYPE_ARRAY:
				for pid in pids:
					province_region_by_id[int(pid)] = region_id

func _load_project_sites_layer(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	province_projects_by_id.clear()
	var data = _load_json_dict("res://data/" + data_dir + "/project_sites.json")
	var sites = data.get("sites", [])
	if typeof(sites) != TYPE_ARRAY:
		return
	for site in sites:
		if typeof(site) != TYPE_DICTIONARY:
			continue
		var pid = int(site.get("province_id", 0))
		if pid <= 0:
			continue
		if not province_projects_by_id.has(pid):
			province_projects_by_id[pid] = []
		province_projects_by_id[pid].append(site)

func load_base_provinces(data_dir: String = ""):
	if data_dir.is_empty():
		data_dir = current_province_data_dir
	var file_path = "res://data/" + data_dir + "/provinces_base.json"
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("Could not open base provinces file: " + file_path)
		return
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Failed to parse base provinces JSON: " + file_path)
		return
	var data = json.data
	if not data.has("provinces") or typeof(data["provinces"]) != TYPE_ARRAY:
		push_warning("Base provinces JSON missing 'provinces' array")
		return
	base_provinces.clear()
	for p_data in data["provinces"]:
		var p = Province.new()
		p.id = int(p_data.get("id", 0))
		p.name = str(p_data.get("name", "Unnamed"))
		p.terrain = str(p_data.get("terrain", "plains"))
		p.is_sea = bool(p_data.get("is_sea", false))
		if not p.is_sea and (p.terrain.to_lower() == "sea" or p.terrain.to_lower() == "ocean"):
			p.is_sea = true
		if p_data.has("has_port"):
			p.has_port = bool(p_data["has_port"])
		var raw_res = p_data.get("natural_resources", p_data.get("resources", {}))
		p.resources = raw_res.duplicate(true) if typeof(raw_res) == TYPE_DICTIONARY else {}
		p.owner_tag = str(p_data.get("owner_tag", ""))
		p.controller_tag = str(p_data.get("controller_tag", ""))
		p.core_for = _string_array_from_json(p_data.get("core_for_tags", p_data.get("core_for", [])))
		p.tags = _string_array_from_json(p_data.get("tags", []))
		p.development_level = int(p_data.get("development_level", 1))
		p.infrastructure = int(p_data.get("infrastructure", 1))
		p.factories = int(p_data.get("factories", 0))
		p.population = int(p_data.get("population_base", p_data.get("population", 1_000_000)))
		p.victory_points = int(p_data.get("victory_points", 0))
		p.special_features = _merged_special_features_from(p_data.get("special_features", []), p_data.get("special_levels", {}))
		_apply_geometry_to_province(p)
		_apply_layer_data_to_province(p)
		base_provinces[p.id] = p
	_infer_port_access_for_all(base_provinces)
	print("✅ Base provinces loaded: ", base_provinces.size(), " provinces (from ", data_dir, ")")

func load_scenario(scenario_name: String) -> bool:
	var file_path = "res://data/scenarios/" + scenario_name + ".json"
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("Could not open scenario file: " + file_path)
		return false

	current_scenario_name = scenario_name
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Failed to parse scenario JSON: " + file_path)
		return false
	var data = json.data

	# Support for procedurally generated test maps (e.g. Phase 1 expanded Europe)
	if data.has("use_province_data_dir"):
		var requested_dir = str(data["use_province_data_dir"])
		if requested_dir != current_province_data_dir:
			current_province_data_dir = requested_dir
			print("ScenarioLoader: Switching to custom province data dir: ", requested_dir)
			load_province_geometry(requested_dir)
			load_province_layers(requested_dir)
			load_base_provinces(requested_dir)

	provinces.clear()
	countries.clear()

	for id in base_provinces:
		provinces[id] = _duplicate_province_from_base(base_provinces[id])

	# Apply overrides with heavy debug
	print("=== APPLYING SCENARIO OVERRIDES ===")
	if data.has("provinces"):
		for p_data in data["provinces"]:
			var raw_id = p_data.get("id", 0)
			var id = int(raw_id)                     # ← THIS IS THE FIX
			if provinces.has(id):
				var p = provinces[id]
				p.owner_tag = str(p_data.get("owner_tag", p.owner_tag))
				p.controller_tag = str(p_data.get("controller_tag", p.controller_tag))
				p.factories = int(p_data.get("factories", p.factories))
				p.development_level = int(p_data.get("development_level", p.development_level))
				p.infrastructure = int(p_data.get("infrastructure", p.infrastructure))
				if p_data.has("population"):
					p.population = int(p_data["population"])
				p.victory_points = int(p_data.get("victory_points", p.victory_points))
				if p_data.has("core_for_tags") or p_data.has("core_for"):
					p.core_for = _string_array_from_json(p_data.get("core_for_tags", p_data.get("core_for", [])))
				if p_data.has("tags"):
					p.tags = _string_array_from_json(p_data["tags"])
				if p_data.has("terrain"):
					p.terrain = str(p_data["terrain"])
				if p_data.has("is_sea"):
					p.is_sea = bool(p_data["is_sea"])
				if p_data.has("has_port"):
					p.has_port = bool(p_data["has_port"])
				if p_data.has("natural_resources") or p_data.has("resources"):
					var rr = p_data.get("natural_resources", p_data.get("resources", {}))
					p.resources = rr.duplicate(true) if typeof(rr) == TYPE_DICTIONARY else {}
				if p_data.has("special_features"):
					p.special_features = _merged_special_features_from(p_data["special_features"], p_data.get("special_levels", {}))
				elif p_data.has("special_levels"):
					var merged: Dictionary = p.special_features.duplicate(true)
					var lvls = p_data["special_levels"]
					if typeof(lvls) == TYPE_DICTIONARY:
						for k in lvls:
							merged[str(k)] = int(lvls[k])
					p.special_features = merged
				
				if id <= 6:   # Debug the first few provinces
					print("  id ", id, " | owner=", p.owner_tag, " | specials=", p.special_features)
			else:
				print("  WARNING: id ", id, " not found in provinces!")

	_load_countries_from_scenario(data)

	_rebuild_adjacency_system()
	_infer_port_access_for_all(provinces)
	_spawn_scenario_factories(scenario_name)
	var scenario_year := _parse_scenario_start_year(data)
	var start_date_str := str(data.get("start_date", "1936-01-01"))
	# New central clock (non-breaking: we still pass year to legacy systems for now)
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.initialize_from_scenario_start_date(start_date_str)

	_load_scenario_leaders(scenario_name, scenario_year)
	_apply_scenario_starting_technology(scenario_name, scenario_year)
	_spawn_scenario_formations(scenario_name)
	var production_mgr := get_node_or_null("/root/ProductionManager")
	if production_mgr != null and production_mgr.has_method("clear_all_caches"):
		production_mgr.clear_all_caches()
	print("✅ Scenario loaded | Provinces: ", provinces.size(), " | Countries: ", countries.size())
	scenario_loaded.emit()

	# Centralize map data for the rest of the game (MapManager is the preferred access point)
	var mm := get_node_or_null("/root/MapManager")
	if mm != null and mm.has_method("initialize_from_map_data"):
		var map_data := get_map_data()
		mm.call("initialize_from_map_data", map_data)

	return true


func _spawn_scenario_factories(scenario_name: String) -> void:
	var spawner := ScenarioFactorySpawner.new()
	spawner.spawn_factories_for_scenario(scenario_name, self)


func _parse_scenario_start_year(data: Dictionary) -> int:
	var start_date := str(data.get("start_date", "1936-01-01"))
	var parts := start_date.split("-")
	if parts.size() >= 1 and parts[0].is_valid_int():
		return int(parts[0])
	return 1936


func _load_scenario_leaders(scenario_name: String, start_year: int) -> void:
	if typeof(LeaderManager) == TYPE_NIL:
		return
	var loaded := LeaderManager.load_leaders_for_scenario(scenario_name, start_year)
	print(
		"✅ Scenario leaders loaded (%s, %d): %d active, %d pooled"
		% [
			scenario_name,
			start_year,
			loaded,
			LeaderManager.get_pool_leader_count(),
		]
	)


func _apply_scenario_starting_technology(scenario_name: String, start_year: int) -> void:
	if typeof(TechnologyManager) == TYPE_NIL:
		return
	var tags: Array[String] = []
	for tag in countries.keys():
		tags.append(str(tag))
	TechnologyManager.apply_scenario_starting_tech(scenario_name, tags, start_year)


func _spawn_scenario_formations(scenario_name: String) -> void:
	LeaderManager.clear_all_formations()
	var formation_spawner := FormationSpawner.new()
	var countries_to_spawn: Array[String] = _get_formation_spawn_countries(scenario_name)
	var count_by_tag: Dictionary = _get_formation_counts_for_scenario(scenario_name)
	for country_tag in countries_to_spawn:
		var count := int(count_by_tag.get(country_tag, 4))
		formation_spawner.spawn_test_formations_for_country(country_tag, count)
	LeaderManager.clear_all_leader_caches()
	print(
		"Scenario loaded with formations for %d countries (leader assignment)."
		% countries_to_spawn.size()
	)


func _get_formation_spawn_countries(_scenario_name: String) -> Array[String]:
	var tags: Array[String] = []
	for tag in countries.keys():
		tags.append(str(tag))
	if tags.is_empty():
		return ["GER", "USA", "SOV"] as Array[String]
	tags.sort()
	return tags


func _get_formation_counts_for_scenario(scenario_name: String) -> Dictionary:
	var counts: Dictionary = {}
	for tag in countries.keys():
		var country: Variant = countries[tag]
		var is_major := false
		if typeof(country) == TYPE_DICTIONARY:
			is_major = bool((country as Dictionary).get("major_power", false))
		counts[str(tag)] = 8 if is_major else 4
	if scenario_name == "1918":
		for major_tag in ["GER", "FRA", "ENG", "USA", "SOV", "JAP"]:
			counts[major_tag] = 8
	return counts


func get_country(tag: String) -> Variant:
	return countries.get(tag)


func get_map_data() -> MapScenarioData:
	return MapScenarioData.new(provinces, build_geometry_dict_for_map(), adjacency_system, countries)


func _load_countries_from_scenario(data: Dictionary) -> void:
	if not data.has("countries"):
		return
	var block: Variant = data["countries"]
	if typeof(block) == TYPE_ARRAY:
		for item in block:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = item
			var tag := str(d.get("tag", ""))
			if tag.is_empty():
				continue
			var entry: Variant = _make_country_entry(tag, d)
			if entry != null:
				countries[_storage_tag_for_country(entry, tag)] = entry
	elif typeof(block) == TYPE_DICTIONARY:
		for key in block:
			var inner: Variant = block[key]
			if typeof(inner) != TYPE_DICTIONARY:
				push_warning("ScenarioLoader: skipped country '" + str(key) + "' (expected object)")
				continue
			var tag_key := str(key)
			var entry: Variant = _make_country_entry(tag_key, inner as Dictionary)
			if entry != null:
				countries[_storage_tag_for_country(entry, tag_key)] = entry
	else:
		push_warning("ScenarioLoader: 'countries' must be an array or object")


func _make_country_entry(tag_hint: String, d: Dictionary) -> Variant:
	var eff_tag := str(d.get("tag", tag_hint))
	if eff_tag.is_empty():
		push_warning("ScenarioLoader: country entry missing tag (hint='" + tag_hint + "')")
		return null
	var name_str := str(d.get("name", eff_tag))
	var col := _parse_country_color(d.get("color", "#CCCCCC"))
	if bool(d.get("plain_dictionary", false)):
		return {"tag": eff_tag, "name": name_str, "color": col}
	var c := Country.new()
	c.tag = eff_tag
	c.name = name_str
	c.color = col
	c.capital_province_id = int(d.get("capital_province_id", 0))
	return c


func _storage_tag_for_country(entry: Variant, fallback_tag: String) -> String:
	if entry is Country:
		return (entry as Country).tag
	if typeof(entry) == TYPE_DICTIONARY:
		var t := str((entry as Dictionary).get("tag", fallback_tag))
		return t if not t.is_empty() else fallback_tag
	return fallback_tag


func _parse_country_color(raw: Variant) -> Color:
	match typeof(raw):
		TYPE_COLOR:
			return raw as Color
		TYPE_STRING:
			return Color(String(raw))
		TYPE_ARRAY:
			var a: Array = raw
			if a.size() < 3:
				return Color(0.65, 0.65, 0.65)
			var rf := float(a[0])
			var gf := float(a[1])
			var bf := float(a[2])
			var af := float(a[3]) if a.size() > 3 else 1.0
			if rf > 1.0 or gf > 1.0 or bf > 1.0:
				rf /= 255.0
				gf /= 255.0
				bf /= 255.0
				if a.size() > 3 and af > 1.0:
					af /= 255.0
			return Color(rf, gf, bf, af)
		_:
			return Color(0.65, 0.65, 0.65)


## Geometry dict keyed by province id → { "points": PackedVector2Array, "label_anchor": Vector2 } for MapRenderer.
func build_geometry_dict_for_map() -> Dictionary:
	var out: Dictionary = {}
	for gid in province_geometry:
		var entry: Variant = province_geometry[gid]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pid := int(gid)
		var pts := PackedVector2Array()
		var raw_points = entry.get("points", [])
		if typeof(raw_points) == TYPE_ARRAY:
			for rp in raw_points:
				if typeof(rp) == TYPE_ARRAY and rp.size() >= 2:
					pts.append(Vector2(float(rp[0]), float(rp[1])))
		var anchor := Vector2.ZERO
		var raw_anchor = entry.get("label_anchor", [])
		if typeof(raw_anchor) == TYPE_ARRAY and raw_anchor.size() >= 2:
			anchor = Vector2(float(raw_anchor[0]), float(raw_anchor[1]))
		elif pts.size() > 0:
			var c := Vector2.ZERO
			for pt in pts:
				c += pt
			anchor = c / pts.size()
		out[pid] = {"points": pts, "label_anchor": anchor}
	return out


func _infer_port_access_for_all(province_map: Dictionary) -> void:
	for id in province_map:
		var p: Province = province_map[id]
		if p == null or p.is_sea:
			p.has_port = false
			continue
		if p.has_port or p.resolve_has_port():
			p.has_port = true
			continue
		for neighbor_id in p.adjacencies:
			var neighbor: Province = province_map.get(neighbor_id)
			if neighbor != null and neighbor.is_sea:
				p.has_port = true
				break


func _rebuild_adjacency_system() -> void:
	adjacency_system = AdjacencySystem.new()
	adjacency_system.load_adjacency()
	adjacency_system.begin_bulk_registration()
	for p in provinces.values():
		adjacency_system.register_province(p)
	adjacency_system.end_bulk_registration()


func get_city_layer() -> Dictionary:
	return province_city_layer


func get_city_count(province_id: int) -> int:
	var pid_key := str(province_id)
	if province_city_layer.has(pid_key):
		var city_entry = province_city_layer[pid_key]
		if typeof(city_entry) == TYPE_DICTIONARY:
			var cities = city_entry.get("cities", [])
			if typeof(cities) == TYPE_ARRAY:
				return cities.size()
	return 0


func _duplicate_province_from_base(base_p: Province) -> Province:
	var p := Province.new()
	p.id = base_p.id
	p.name = base_p.name
	p.terrain = base_p.terrain
	p.is_sea = base_p.is_sea
	p.has_port = base_p.has_port
	p.coordinates = base_p.coordinates
	p.adjacencies = base_p.adjacencies.duplicate()
	p.owner_tag = base_p.owner_tag
	p.controller_tag = base_p.controller_tag
	p.core_for = base_p.core_for.duplicate()
	p.development_level = base_p.development_level
	p.infrastructure = base_p.infrastructure
	p.factories = base_p.factories
	p.population = base_p.population
	p.resources = base_p.resources.duplicate(true)
	p.victory_points = base_p.victory_points
	p.special_features = base_p.special_features.duplicate(true)
	p.tags = base_p.tags.duplicate()
	return p


func _string_array_from_json(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		out.append(str(item))
	return out


func _merged_special_features_from(features_variant: Variant, levels_variant: Variant) -> Dictionary:
	var levels: Dictionary = levels_variant if typeof(levels_variant) == TYPE_DICTIONARY else {}
	var out: Dictionary = {}
	if typeof(features_variant) == TYPE_DICTIONARY:
		for k in features_variant:
			var ks := str(k)
			out[ks] = _special_level_coerce(features_variant[k], levels, ks)
	elif typeof(features_variant) == TYPE_ARRAY:
		for item in features_variant:
			var ks := str(item)
			var lvl := 1
			if levels.has(item):
				lvl = int(levels[item])
			elif levels.has(ks):
				lvl = int(levels[ks])
			out[ks] = lvl
	for k in levels:
		var ks := str(k)
		if not out.has(ks):
			out[ks] = int(levels[k])
	return out


func _special_level_coerce(v: Variant, levels: Dictionary, key: String) -> int:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return int(v)
		TYPE_BOOL:
			return 1 if v else 0
		_:
			if levels.has(key):
				return int(levels[key])
			return 1


func _apply_geometry_to_province(p: Province):
	if not province_geometry.has(p.id):
		p.coordinates = Vector2.ZERO
		return

	var geometry = province_geometry[p.id]
	if typeof(geometry) != TYPE_DICTIONARY:
		return

	var raw_points = geometry.get("points", [])
	var points := PackedVector2Array()
	if typeof(raw_points) == TYPE_ARRAY:
		for raw_point in raw_points:
			if typeof(raw_point) == TYPE_ARRAY and raw_point.size() >= 2:
				points.append(Vector2(float(raw_point[0]), float(raw_point[1])))

	var raw_anchor = geometry.get("label_anchor", [])
	if typeof(raw_anchor) == TYPE_ARRAY and raw_anchor.size() >= 2:
		p.coordinates = Vector2(float(raw_anchor[0]), float(raw_anchor[1]))
	elif points.size() > 0:
		var center := Vector2.ZERO
		for point in points:
			center += point
		p.coordinates = center / points.size()
	else:
		p.coordinates = Vector2.ZERO


func _apply_layer_data_to_province(p: Province):
	var pid_key := str(p.id)
	p.adjacencies.clear()
	if province_adjacency.has(pid_key) and typeof(province_adjacency[pid_key]) == TYPE_ARRAY:
		for neighbor in province_adjacency[pid_key]:
			p.adjacencies.append(int(neighbor))

	if province_terrain_layer.has(pid_key) and typeof(province_terrain_layer[pid_key]) == TYPE_DICTIONARY:
		var terrain_data: Dictionary = province_terrain_layer[pid_key].duplicate(true)
		if terrain_data.has("terrain"):
			p.terrain = str(terrain_data["terrain"])
			if not p.is_sea:
				var tt := str(terrain_data["terrain"]).to_lower()
				if tt == "sea" or tt == "ocean":
					p.is_sea = true

	if province_resources_layer.has(pid_key) and typeof(province_resources_layer[pid_key]) == TYPE_DICTIONARY:
		var resources_data: Dictionary = province_resources_layer[pid_key].duplicate(true)
		if resources_data.has("resources"):
			p.resources = resources_data["resources"].duplicate(true)

	if province_economy_layer.has(pid_key) and typeof(province_economy_layer[pid_key]) == TYPE_DICTIONARY:
		var economy_data: Dictionary = province_economy_layer[pid_key].duplicate(true)
		p.population = int(economy_data.get("population", p.population))
		p.factories = int(economy_data.get("factories", p.factories))
		p.infrastructure = int(economy_data.get("infrastructure", p.infrastructure))
		p.development_level = int(round(float(economy_data.get("development_level", p.development_level))))
		if economy_data.has("resources"):
			p.resources = economy_data["resources"].duplicate(true)
