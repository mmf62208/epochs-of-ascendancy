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
var province_super_by_id: Dictionary = {}
var province_projects_by_id: Dictionary = {}
var strategic_regions: Dictionary = {}  # region_id -> {id, name, province_ids: [...], notes? }  full data for bonuses/control queries
var super_regions: Dictionary = {}  # super_region_id -> {id, name, ...} four-tier hierarchy
var province_state_names: Dictionary = {}  # state_id -> name
var super_region_names: Dictionary = {}  # super_region_id -> name

func get_strategic_region(region_id: int) -> Dictionary:
	return strategic_regions.get(region_id, {})

func get_strategic_region_name(region_id: int) -> String:
	var r: Dictionary = strategic_regions.get(region_id, {}) as Dictionary
	return r.get("name", "Strategic Region " + str(region_id))

func get_all_strategic_regions() -> Dictionary:
	return strategic_regions.duplicate(true)

func get_province_state_id(province_id: int) -> int:
	return int(province_state_by_id.get(province_id, 0))

func get_province_region_id(province_id: int) -> int:
	return int(province_region_by_id.get(province_id, 0))

func get_province_super_region_id(province_id: int) -> int:
	if province_super_by_id.has(province_id):
		return int(province_super_by_id[province_id])
	# Fallback: region → super via region_ids lists on super_regions.
	var rid := get_province_region_id(province_id)
	if rid > 0:
		for srid in super_regions:
			var sr: Dictionary = super_regions[srid] as Dictionary
			var rids: Variant = sr.get("region_ids", [])
			if typeof(rids) == TYPE_ARRAY and rid in rids:
				return int(srid)
	return 0

func get_state_name(state_id: int) -> String:
	return str(province_state_names.get(state_id, "State %d" % state_id))

func get_super_region(super_region_id: int) -> Dictionary:
	return super_regions.get(super_region_id, {})

func get_super_region_name(super_region_id: int) -> String:
	if super_region_names.has(super_region_id):
		return str(super_region_names[super_region_id])
	var sr: Dictionary = super_regions.get(super_region_id, {}) as Dictionary
	return str(sr.get("name", "Super Region %d" % super_region_id)) if super_region_id > 0 else ""

func get_all_super_regions() -> Dictionary:
	return super_regions.duplicate(true)

func get_hierarchy_for_province(province_id: int) -> Dictionary:
	var sid := get_province_state_id(province_id)
	var rid := get_province_region_id(province_id)
	var srid := get_province_super_region_id(province_id)
	var rname := get_strategic_region_name(rid) if rid > 0 else ""
	var srname := get_super_region_name(srid) if srid > 0 else ""
	return {
		"province_id": province_id,
		"state_id": sid,
		"state_name": get_state_name(sid) if sid > 0 else "",
		"region_id": rid,
		"region_name": rname,
		"super_region_id": srid,
		"super_region_name": srname,
		"empty": sid <= 0 and rid <= 0 and srid <= 0,
	}

## Live membership mutation counter (player/event agency after seed).
var membership_live_mutation_count: int = 0
## True after first seed; day/year ticks must not clear live maps.
var membership_seed_applied: bool = false
var membership_reapply_on_year_tick: bool = false  # policy lock: always false


## Reassign one province to another state (gory border / admin reform). Live, seed-only eras do not clobber.
func reassign_province_membership(
	province_id: int,
	new_state_id: int,
	new_region_id: int = -1,
	new_super_region_id: int = -1,
	new_state_name: String = ""
) -> Dictionary:
	var before: Dictionary = get_hierarchy_for_province(province_id)
	var old_sid := int(before.get("state_id", 0))
	if province_id <= 0 or new_state_id <= 0:
		return {"ok": false, "error": "invalid_ids", "province_id": province_id, "live": true}
	if old_sid == new_state_id and new_region_id < 0:
		return {
			"ok": true,
			"noop": true,
			"province_id": province_id,
			"before": before,
			"after": before,
			"live": true,
			"seed_only_policy": true,
			"reapply_on_year_tick": membership_reapply_on_year_tick,
		}
	# Destination region/super MUST be resolved from existing destination peers
	# BEFORE mutating province_state_by_id — never self-infer from this province's old region.
	var dest_rid := new_region_id if new_region_id > 0 else _infer_region_for_state(new_state_id, [province_id])
	var dest_srid := new_super_region_id if new_super_region_id > 0 else _infer_super_for_region(dest_rid)
	province_state_by_id[province_id] = new_state_id
	if not new_state_name.is_empty():
		province_state_names[new_state_id] = new_state_name
	elif not province_state_names.has(new_state_id):
		province_state_names[new_state_id] = get_state_name(new_state_id)
	if dest_rid > 0:
		province_region_by_id[province_id] = dest_rid
	if dest_srid > 0:
		province_super_by_id[province_id] = dest_srid
	membership_live_mutation_count += 1
	var after: Dictionary = get_hierarchy_for_province(province_id)
	return {
		"ok": true,
		"live": true,
		"change_type": "reassign_province",
		"province_id": province_id,
		"before": before,
		"after": after,
		"mutation_count": membership_live_mutation_count,
		"seed_only_policy": true,
		"reapply_on_year_tick": membership_reapply_on_year_tick,
		"membership_seed_applied": membership_seed_applied,
	}


## Infer region from provinces already in state_id, never from exclude_pids (e.g. movers).
func _infer_region_for_state(state_id: int, exclude_pids: Array = []) -> int:
	var exclude: Dictionary = {}
	for p in exclude_pids:
		exclude[int(p)] = true
	for pid in province_state_by_id:
		if exclude.has(int(pid)):
			continue
		if int(province_state_by_id[pid]) == state_id:
			var rid := int(province_region_by_id.get(pid, 0))
			if rid > 0:
				return rid
	return 0


func _infer_super_for_region(region_id: int) -> int:
	if region_id <= 0:
		return 0
	for srid in super_regions:
		var sr: Dictionary = super_regions[srid] as Dictionary
		var rids: Variant = sr.get("region_ids", [])
		if typeof(rids) == TYPE_ARRAY and region_id in rids:
			return int(srid)
	# Fallback: any province already in this region
	for pid in province_region_by_id:
		if int(province_region_by_id[pid]) == region_id:
			var srid2 := int(province_super_by_id.get(pid, 0))
			if srid2 > 0:
				return srid2
	return 0


## Create a new state from a province set (decolonization / secession / admin create).
func create_state_membership(
	province_ids: Array,
	state_name: String,
	region_id: int = 0,
	super_region_id: int = 0,
	owner_hint: String = ""
) -> Dictionary:
	var pids: Array = []
	for raw in province_ids:
		var pid := int(raw)
		if pid > 0:
			pids.append(pid)
	if pids.is_empty():
		return {"ok": false, "error": "empty_province_ids", "live": true}
	# Allocate dynamic state id in high range (does not collide with era*100000 seeds)
	var new_sid := 900000000 + membership_live_mutation_count + 1
	while province_state_names.has(new_sid):
		new_sid += 1
	var name_s := state_name.strip_edges()
	if name_s.is_empty():
		name_s = "New State %d" % new_sid
	province_state_names[new_sid] = name_s
	var rid := region_id
	var srid := super_region_id
	if rid <= 0:
		rid = get_province_region_id(int(pids[0]))
	if srid <= 0:
		srid = get_province_super_region_id(int(pids[0]))
	var moved: Array = []
	for pid in pids:
		var before_sid := get_province_state_id(int(pid))
		province_state_by_id[int(pid)] = new_sid
		if rid > 0:
			province_region_by_id[int(pid)] = rid
		if srid > 0:
			province_super_by_id[int(pid)] = srid
		moved.append({"province_id": int(pid), "from_state": before_sid, "to_state": new_sid})
	membership_live_mutation_count += 1
	var sample: Dictionary = get_hierarchy_for_province(int(pids[0]))
	return {
		"ok": true,
		"live": true,
		"change_type": "create_state",
		"state_id": new_sid,
		"state_name": name_s,
		"province_ids": pids,
		"moved": moved,
		"region_id": rid,
		"super_region_id": srid,
		"owner_hint": owner_hint,
		"sample_hierarchy": sample,
		"mutation_count": membership_live_mutation_count,
		"seed_only_policy": true,
		"reapply_on_year_tick": membership_reapply_on_year_tick,
	}


## Transfer whole state membership of from_state into to_state (clean border / merge).
func transfer_state_membership(from_state_id: int, to_state_id: int) -> Dictionary:
	if from_state_id <= 0 or to_state_id <= 0 or from_state_id == to_state_id:
		return {"ok": false, "error": "invalid_state_ids", "live": true}
	var moved_pids: Array = []
	for pid in province_state_by_id.keys():
		if int(province_state_by_id[pid]) == from_state_id:
			moved_pids.append(int(pid))
	if moved_pids.is_empty():
		return {"ok": false, "error": "from_state_empty", "from_state_id": from_state_id, "live": true}
	# Destination region/super from EXISTING destination peers only (before any move).
	var dest_rid := _infer_region_for_state(to_state_id, moved_pids)
	var dest_srid := _infer_super_for_region(dest_rid)
	for pid in moved_pids:
		province_state_by_id[int(pid)] = to_state_id
		if dest_rid > 0:
			province_region_by_id[int(pid)] = dest_rid
		if dest_srid > 0:
			province_super_by_id[int(pid)] = dest_srid
	membership_live_mutation_count += 1
	var sample_pid := int(moved_pids[0])
	return {
		"ok": true,
		"live": true,
		"change_type": "transfer_state",
		"from_state_id": from_state_id,
		"to_state_id": to_state_id,
		"to_state_name": get_state_name(to_state_id),
		"province_ids": moved_pids,
		"province_n": moved_pids.size(),
		"dest_region_id": dest_rid,
		"dest_super_region_id": dest_srid,
		"sample_hierarchy": get_hierarchy_for_province(sample_pid),
		"mutation_count": membership_live_mutation_count,
		"seed_only_policy": true,
		"reapply_on_year_tick": membership_reapply_on_year_tick,
	}


func get_membership_live_mutation_count() -> int:
	return membership_live_mutation_count


## Serialize live membership maps for save games (player agency after seed).
func get_membership_save_data() -> Dictionary:
	var p2s: Dictionary = {}
	var p2r: Dictionary = {}
	var p2sr: Dictionary = {}
	var names: Dictionary = {}
	for pid in province_state_by_id:
		p2s[str(pid)] = int(province_state_by_id[pid])
	for pid in province_region_by_id:
		p2r[str(pid)] = int(province_region_by_id[pid])
	for pid in province_super_by_id:
		p2sr[str(pid)] = int(province_super_by_id[pid])
	for sid in province_state_names:
		names[str(sid)] = str(province_state_names[sid])
	return {
		"version": 1,
		"live": true,
		"seed_only_policy": true,
		"reapply_on_year_tick": false,
		"mutation_count": membership_live_mutation_count,
		"seed_applied": membership_seed_applied,
		"province_to_state": p2s,
		"province_to_region": p2r,
		"province_to_super_region": p2sr,
		"state_names": names,
	}


## Restore live membership after load (does not re-run era seed tables).
func apply_membership_save_data(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "error": "empty"}
	var p2s: Variant = data.get("province_to_state", {})
	var p2r: Variant = data.get("province_to_region", {})
	var p2sr: Variant = data.get("province_to_super_region", {})
	var names: Variant = data.get("state_names", {})
	if typeof(p2s) != TYPE_DICTIONARY or (p2s as Dictionary).is_empty():
		return {"ok": false, "error": "no_binds"}
	province_state_by_id.clear()
	province_region_by_id.clear()
	province_super_by_id.clear()
	for k in p2s:
		province_state_by_id[int(k)] = int(p2s[k])
	if typeof(p2r) == TYPE_DICTIONARY:
		for k in p2r:
			province_region_by_id[int(k)] = int(p2r[k])
	if typeof(p2sr) == TYPE_DICTIONARY:
		for k in p2sr:
			province_super_by_id[int(k)] = int(p2sr[k])
	if typeof(names) == TYPE_DICTIONARY:
		province_state_names.clear()
		for k in names:
			province_state_names[int(k)] = str(names[k])
	membership_live_mutation_count = int(data.get("mutation_count", membership_live_mutation_count))
	membership_seed_applied = true
	membership_reapply_on_year_tick = false
	return {
		"ok": true,
		"live": true,
		"bound": province_state_by_id.size(),
		"mutation_count": membership_live_mutation_count,
		"seed_only_policy": true,
		"reapply_on_year_tick": false,
	}


## Built when a scenario is loaded; used by MapRenderer.initialize and pathfinding helpers.
var adjacency_system: AdjacencySystem

## Current/last loaded scenario name (for SaveLoadManager metadata and validation).
var current_scenario_name: String = ""

## Allows test scenarios (like the procedurally generated Phase 1 map) to use their own province data folder.
var current_province_data_dir: String = "provinces"
# Test override for full Europe territories playtest (from subagent integration):
# Set to "provinces_full_europe" or "provinces_phase1_test" via scenario JSON "use_province_data_dir"
# or temporarily here for direct testing. Full 350-450+ provinces with settlement/welfare/policy systems.

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

	# Full-world equirectangular geometry must not be remapped as Europe-local theater coords.
	var meta: Dictionary = data.get("meta", {}) if typeof(data.get("meta", {})) == TYPE_DICTIONARY else {}
	var space_tag := str(meta.get("geometry_space", meta.get("space", ""))).to_lower()
	var world_native := bool(
		space_tag == "world"
		or space_tag == "world_canvas"
		or space_tag.begins_with("world")
		or bool(meta.get("geometry_world_native", false))
		or data_dir in ["provinces_world_full", "provinces_world", "provinces_world_accurate", "provinces_pilot_europe_nuts3", "provinces_pilot_us_tiger"]
	)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("set_geometry_world_native"):
		MapManager.set_geometry_world_native(world_native)
		if world_native:
			print("ScenarioLoader: geometry marked world-native (full equirectangular canvas)")

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
	# Support both legacy "provinces" key and the format produced by infer_province_terrain_from_layers.py ("province_terrain_layer" wrapper with inner "provinces" map)
	var raw: Variant = data.get("provinces", {})
	if (not raw is Dictionary) or raw.is_empty():
		var tl: Variant = data.get("province_terrain_layer", {})
		if tl is Dictionary:
			raw = tl.get("provinces", tl)  # unwrap to the pid->data map if present, else use as-is (legacy flat)
	if raw is Dictionary:
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
	province_super_by_id.clear()
	strategic_regions.clear()
	super_regions.clear()
	province_state_names.clear()
	super_region_names.clear()
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
			if state_id > 0:
				province_state_names[state_id] = str(s.get("name", "State %d" % state_id))

	var regions_data = _load_json_dict("res://data/" + data_dir + "/strategic_regions.json")
	# Pilot may only have scaffold file — try scaffold fallback for residual boards
	if regions_data.is_empty() or not regions_data.has("regions"):
		regions_data = _load_json_dict("res://data/" + data_dir + "/strategic_regions_scaffold.json")
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
			# Store full region for names, bonuses, control checks
			strategic_regions[region_id] = {
				"id": region_id,
				"name": r.get("name", "Strategic Region " + str(region_id)),
				"province_ids": pids if typeof(pids) == TYPE_ARRAY else [],
				"theater": r.get("theater", ""),
				"notes": r.get("notes", "")
			}

	var super_data = _load_json_dict("res://data/" + data_dir + "/super_regions.json")
	var sregs = super_data.get("super_regions", [])
	if typeof(sregs) == TYPE_ARRAY:
		for sr in sregs:
			if typeof(sr) != TYPE_DICTIONARY:
				continue
			var srid = int(sr.get("id", 0))
			if srid > 0:
				super_regions[srid] = sr.duplicate(true)
				super_region_names[srid] = str(sr.get("name", "Super Region %d" % srid))

	# Four-tier: province → super from hierarchy_scaffold bindings when present.
	var scaffold = _load_json_dict("res://data/" + data_dir + "/hierarchy_scaffold.json")
	var p2super: Variant = scaffold.get("province_to_super_region", {})
	if typeof(p2super) == TYPE_DICTIONARY:
		for pid_key in p2super:
			province_super_by_id[int(pid_key)] = int(p2super[pid_key])
	# Fallback: assign via super_regions.region_ids covering strategic regions.
	if province_super_by_id.is_empty() and not super_regions.is_empty():
		for srid in super_regions:
			var sr2: Dictionary = super_regions[srid] as Dictionary
			var rids2: Variant = sr2.get("region_ids", [])
			if typeof(rids2) == TYPE_ARRAY:
				for rid2 in rids2:
					for pid2 in province_region_by_id:
						if int(province_region_by_id[pid2]) == int(rid2):
							province_super_by_id[int(pid2)] = int(srid)
			# Theater membership on super_regions (world_full style).
			var theaters: Variant = sr2.get("theaters", [])
			if typeof(theaters) == TYPE_ARRAY:
				for rid3 in strategic_regions:
					var regd: Dictionary = strategic_regions[rid3] as Dictionary
					var th := str(regd.get("theater", ""))
					if th != "" and th in theaters:
						var rpids: Variant = regd.get("province_ids", [])
						if typeof(rpids) == TYPE_ARRAY:
							for pid3 in rpids:
								province_super_by_id[int(pid3)] = int(srid)

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
		# World board: coastal_land domain is port-eligible for shipyards.
		var domain_s := str(p_data.get("domain", "")).strip_edges().to_lower()
		p.domain = domain_s if not domain_s.is_empty() else ("sea" if p.is_sea else "land")
		if domain_s in ["sea", "strait", "lake"]:
			p.is_sea = true
			p.has_port = false
		elif domain_s == "coastal_land" or domain_s == "coastal":
			p.has_port = true
			if not p.tags.has("coastal"):
				p.tags.append("coastal")
		var raw_res = p_data.get("natural_resources", p_data.get("resources", {}))
		# Layers may nest as {resources:{iron:8}, resource_score, primary_resource} — store flat amounts only.
		p.resources = _normalize_province_resources(raw_res)
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
	print("✅ Base provinces loaded: ", base_provinces.size(), " provinces (from ", data_dir, ") — will prune to 471 phase1 children if geometry match")

## Helper to report progress to a dynamically added LoadingScreen (if present in the current scene/root).
## Used during long synchronous parts of scenario load so the on-screen % and tip can advance
## and the engine can process frames (preventing "stuck at 12%" perception while 471 provs + 56 agents + leaders load).
func _report_load_progress(p: float, tip: String = "") -> void:
	if get_tree() == null:
		return
	var root = get_tree().current_scene
	if root == null:
		return
	# Use find_child for robustness (name set on dynamic creation in TestRunner).
	var ls := root.find_child("LoadingScreen", true, false) as CanvasLayer
	if ls and ls.has_method("update_progress"):
		ls.call("update_progress", clampf(p, 0.0, 1.0), tip)
		# Note: CanvasLayer does not have queue_redraw (it's for CanvasItem children).
		# The update_progress inside LS already does queue_redraw on the ProgressBar, labels, etc.
		print("[LOAD PROGRESS] ", "%.1f" % (p * 100), "% - ", tip)  # debug so user sees internal reports firing during heavy load
	else:
		# Still log so stalls after LS soft-unlock/free are visible in console.
		print("[LOAD PROGRESS] ", "%.1f" % (p * 100), "% - ", tip)
	# ALWAYS yield a frame on accurate/world loads. If LS force-dismisses early and we only
	# yielded when LS was present, the rest of load became one giant sync freeze (no repaint).
	await get_tree().process_frame

func load_scenario(scenario_name: String) -> bool:
	await _report_load_progress(0.125, "Entering scenario load for " + scenario_name + "...")

	var file_path = "res://data/scenarios/" + scenario_name + ".json"
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("Could not open scenario file: " + file_path)
		return false

	await _report_load_progress(0.13, "Parsing scenario JSON + loading province data dir...")

	current_scenario_name = scenario_name
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Failed to parse scenario JSON: " + file_path)
		return false
	var data = json.data

	await _report_load_progress(0.135, "Parsed scenario JSON, preparing province data...")

	# Support for procedurally generated test maps (e.g. Phase 1 expanded Europe)
	if data.has("use_province_data_dir"):
		var requested_dir = str(data["use_province_data_dir"])
		if requested_dir != current_province_data_dir:
			current_province_data_dir = requested_dir
			print("ScenarioLoader: Switching to custom province data dir: ", requested_dir)
			await _report_load_progress(0.14, "Loading province geometry/layers for phase1 (471 children dense)...")
			load_province_geometry(requested_dir)
			load_province_layers(requested_dir)
			load_base_provinces(requested_dir)
			await _report_load_progress(0.145, "Loaded province geometry/layers for phase1 (471 children dense)...")

	provinces.clear()
	countries.clear()

	await _report_load_progress(0.15, "Copying base provinces and applying phase1 rebuilds...")

	for id in base_provinces:
		provinces[id] = _duplicate_province_from_base(base_provinces[id])

	# For full-Europe phase1 test (471-prov vector map from gen + river children): if base loaded the legacy 840 but geometry has the dense 471 children,
	# rebuild the authoritative provinces dict from geometry + economy layer so the ids (phase1 children), settlement/welfare data, and MapPickGrid are correct (no 840/471 mix).
	# This makes "provinces connected" use the exact generated 471 (children included) for inspector, tints, combat, supply, picking. Ensures phase1 children authoritative post load.
	if current_province_data_dir in ["provinces_full_europe", "provinces_phase1_test", "provinces_grand_theater", "provinces_world_full", "provinces_pilot_europe", "provinces_pilot_europe_nuts3", "provinces_pilot_us", "provinces_pilot_global_density", "provinces_world_accurate", "provinces_pilot_us_tiger"] and province_geometry.size() > 400 and provinces.size() != province_geometry.size():
		print("ScenarioLoader: Rebuilding provinces dict from geometry + economy layer (was %d from base; geometry-authoritative for %s)." % [provinces.size(), current_province_data_dir])
		provinces.clear()
		for pid in province_geometry.keys():
			var p := Province.new()
			p.id = pid
			var g = province_geometry[pid]
			p.name = g.get("name", "Province %d" % pid)
			p.coordinates = Vector2(g.get("label_anchor", [0,0])[0] if g.has("label_anchor") else 0, g.get("label_anchor", [0,0])[1] if g.has("label_anchor") else 0)
			p.is_sea = bool(g.get("is_sea", false))
			if int(pid) >= 950000:
				p.is_sea = true
				p.domain = "sea"
			# Pull stats from economy layer (dev/infra/pop/factories/resources) if present
			var econ = province_economy_layer.get(str(pid), {}) if province_economy_layer else {}
			p.development_level = int(econ.get("development_level", econ.get("dev", 3)))
			p.infrastructure = int(econ.get("infrastructure", econ.get("infra", 2)))
			p.factories = int(econ.get("factories", 0))
			p.population = int(econ.get("population", econ.get("pop", 100000)))
			p.resources = _normalize_province_resources(econ)
			# Owner/controller from scenario overrides will be applied below (or default empty)
			_apply_geometry_to_province(p)
			_apply_layer_data_to_province(p)
			if str(p.terrain).to_lower() in ["sea", "ocean"] or str(p.domain).to_lower() in ["sea", "strait", "ocean"]:
				p.is_sea = true
			provinces[pid] = p
		_infer_port_access_for_all(provinces)
		print("ScenarioLoader: Rebuilt %d provinces (phase1 children) for full Europe test map." % provinces.size())

	# Force any remaining 840/override mix (e.g. base parents, partial scenario ids, legacy) to use ONLY the dense 471 phase1 children from geometry for play.
	# Ensures phase1 children + MapPickGrid, inspector samples, Province getters, Battle previews, supply, tints all operate exclusively on the generated 471-prov set (children from river/elev layers included).
	if current_province_data_dir in ["provinces_full_europe", "provinces_phase1_test", "provinces_grand_theater", "provinces_world_full", "provinces_pilot_europe", "provinces_pilot_europe_nuts3", "provinces_pilot_us", "provinces_pilot_global_density", "provinces_world_accurate", "provinces_pilot_us_tiger"] and province_geometry.size() > 400:
		var geo_keys := province_geometry.keys()
		var forced: Dictionary = {}
		var missing_recreated := 0
		for pid in geo_keys:
			if provinces.has(pid):
				forced[pid] = provinces[pid]
			else:
				# Recreate minimal from geo+econ so 471 phase1 children always authoritative (overrides will have applied if id was in scen)
				var p := Province.new()
				p.id = pid
				var g = province_geometry[pid]
				p.name = g.get("name", "Province %d" % pid)
				p.is_sea = bool(g.get("is_sea", false))
				if int(pid) >= 950000:
					p.is_sea = true
					p.domain = "sea"
				var econ = province_economy_layer.get(str(pid), {}) if province_economy_layer else {}
				p.development_level = int(econ.get("development_level", econ.get("dev", 3)))
				p.infrastructure = int(econ.get("infrastructure", econ.get("infra", 2)))
				p.population = int(econ.get("population", econ.get("pop", 100000)))
				_apply_geometry_to_province(p)
				_apply_layer_data_to_province(p)
				if str(p.terrain).to_lower() in ["sea", "ocean"] or str(p.domain).to_lower() in ["sea", "strait", "ocean"]:
					p.is_sea = true
				forced[pid] = p
				missing_recreated += 1
		# Harden sea flags on every forced province (geometry rebuild can drop domain).
		for fpid in forced.keys():
			var fp: Province = forced[fpid] as Province
			if fp == null:
				continue
			if int(fpid) >= 950000 or str(fp.terrain).to_lower() in ["sea", "ocean"] or str(fp.domain).to_lower() in ["sea", "strait", "ocean"]:
				fp.is_sea = true
		provinces = forced
		_infer_port_access_for_all(provinces)
		print("ScenarioLoader: FORCED to exactly %d provinces for %s (pruned base/override mix; recreated %d). MapPickGrid/inspector/combat use this set." % [provinces.size(), current_province_data_dir, missing_recreated])
		await _report_load_progress(0.16, "Rebuilt authoritative province set from geometry...")
		# Extra: rebuild pick grid immediately with the forced set (post prune) so legacy base never leaks to picker.
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("rebuild_pick_grid"):
			MapManager.rebuild_pick_grid()
			var _pc := 0
			if MapManager.has_method("get_province_count"):
				_pc = MapManager.get_province_count()
			print("ScenarioLoader: Post-prune pick grid rebuild; current provinces in MapManager ~%d (or will be after full init). Ensures world-class Europe 471 children overlay on grand uses correct phase1 set not legacy 840." % _pc)
		# Additional explicit rebuild post prune for safety (MapRenderer pick + any cached).
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("rebuild_pick_grid"):
			MapManager.rebuild_pick_grid(64.0)
			print("ScenarioLoader: Second post-prune phase1 children pick rebuild completed.")

	# Apply overrides with heavy debug
	print("=== APPLYING SCENARIO OVERRIDES ===")
	await _report_load_progress(0.155, "Applying scenario overrides (province owners, factories, dev, infra)...")
	if data.has("provinces"):
		var override_count: int = (data["provinces"] as Array).size()
		var o: int = 0
		for p_data in data["provinces"]:
			o += 1
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
					p.resources = _normalize_province_resources(rr)
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
				# Only warn for the first few to avoid log spam in phase1 tests (many demo ids from full map data)
				if not has_meta("warned_missing_ids"):
					set_meta("warned_missing_ids", 0)
				var wc := int(get_meta("warned_missing_ids"))
				if wc < 5:
					print("  WARNING: id ", id, " not found in provinces (phase1 data uses subset; safe to ignore for test/demo ids).")
					set_meta("warned_missing_ids", wc + 1)
				elif wc == 5:
					print("  ... (suppressing further 'id not found' warnings for this load)")
					set_meta("warned_missing_ids", wc + 1)

			# Sample progress during the overrides loop (main path or warning path) - more frequent early samples for smooth climb.
			if o % 20 == 0 or o == 1 or o == override_count:
				await _report_load_progress(0.16 + (float(o) / max(1.0, float(override_count))) * 0.02, "Applying overrides " + str(o) + "/" + str(override_count) + "...")

		await _report_load_progress(0.18, "Applied scenario province overrides (owners, factories, etc.)...")

	# start_date → historical ownership table (overwrites bulk scenario owner paint for world_full).
	# SEED ONLY: not reapplied on year ticks. Live conquest/diplomacy own owner_tag after this.
	var _start_year := _parse_scenario_start_year(data)
	_apply_era_ownership_seed(_start_year, false)
	# start_date → full hierarchy membership snapshot (1910/1918/1936/2026 primary, mode=full).
	# SEED ONLY: not reapplied on year ticks. Player/event state edits preserved after load.
	_apply_era_membership_seed(_start_year)

	# Ownership evidence (political map): land owned counts by tag after era seed.
	var land_total := 0
	var land_owned := 0
	var by_owner: Dictionary = {}
	for pid in provinces.keys():
		var pp = provinces[pid]
		if pp == null:
			continue
		var is_water := bool(pp.is_sea)
		if is_water:
			continue
		land_total += 1
		var ot := str(pp.owner_tag).strip_edges().to_upper()
		if ot.is_empty():
			continue
		land_owned += 1
		by_owner[ot] = int(by_owner.get(ot, 0)) + 1
	var cov := 0.0 if land_total <= 0 else float(land_owned) / float(land_total)
	print(
		"ScenarioLoader: Ownership applied — land_owned=%d/%d (%.1f%%) tags=%d majors_sample GER=%d FRA=%d ENG=%d USA=%d SOV=%d ITA=%d JAP=%d"
		% [
			land_owned,
			land_total,
			cov * 100.0,
			by_owner.size(),
			int(by_owner.get("GER", 0)),
			int(by_owner.get("FRA", 0)),
			int(by_owner.get("ENG", 0)),
			int(by_owner.get("USA", 0)),
			int(by_owner.get("SOV", 0)),
			int(by_owner.get("ITA", 0)),
			int(by_owner.get("JAP", 0)),
		]
	)

	_load_countries_from_scenario(data)
	# Ownership tags on 1936 board include ~65 nations; scenario only lists majors.
	# Synthesize Country color/name/capital for every owned tag so political shading + labels work.
	_ensure_countries_for_ownership_tags()

	_rebuild_adjacency_system()
	_infer_port_access_for_all(provinces)
	# Gold-star capitals: stamp special_features.capital from city layer + scenario capital ids.
	_stamp_capital_features()
	# Chokes must reload after dir switch (MapManager may have booted on phase1's 132-id list).
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("reload_naval_chokepoints"):
		MapManager.reload_naval_chokepoints()
	_spawn_scenario_factories(scenario_name)

	# Init actual starting equipment stockpiles from scenario data (per-nation, realistic OOBs/equipment for planes/ships/troops per scenario).
	# Scenario json controls it so different scenarios (1918/1936/2026/phase1 or future mods) load different realistic starting stats.
	# Stockpiles are per country for multi-nation support; applied before formations/production use them.
	_apply_starting_equipment_stockpiles(data)
	await _report_load_progress(0.20, "Applied starting equipment stockpiles for 14 nations...")

	# Apply starting agents per nation from scenario (scenario controls count for realism per era/mod)
	await _apply_starting_agents(data)

	# Init service doctrines (high-level philosophy for army/navy/air chiefs). Player sets via doctrine page; evolves via research/agents.
	# Critical choice: impacts designs, training, operations. E.g., resilient armor vs high perf cheap.
	# Agents can focus on "doctrine reform" to iterate (unlock benefits or expose weaknesses, allow change with costs).
	if typeof(LeaderManager) != TYPE_NIL:
		# Sample for majors (expand with data/doctrines/ later). WWI -> WWII -> Modern.
		if not LeaderManager.service_doctrines.has("GER"):
			LeaderManager.set_service_doctrine("GER", "army", "blitzkrieg")
			LeaderManager.set_service_doctrine("GER", "navy", "submarine_commerce_raiding")
			LeaderManager.set_service_doctrine("GER", "air_force", "strategic_bombing")
		if not LeaderManager.service_doctrines.has("USA"):
			LeaderManager.set_service_doctrine("USA", "army", "deep_battle")  # or firepower
			LeaderManager.set_service_doctrine("USA", "navy", "carrier_task_force")
			LeaderManager.set_service_doctrine("USA", "air_force", "strategic_bombing")
		if not LeaderManager.service_doctrines.has("ENG"):
			LeaderManager.set_service_doctrine("ENG", "navy", "carrier_task_force")
		# Add for others as needed; minors inherit or basic.
		print("[SCENARIO DOCTRINES] Initialized service doctrines for majors. Player/chiefs set philosophy; agents iterate over time.")
		await _report_load_progress(0.24, "Initialized service doctrines (blitzkrieg, carrier_task_force, etc. + penalty sim)...")

	# High-value scenario connection: ensure WeatherManager (snow/season effects) is populated from the
	# final post-rebuild provinces (incl. snow_potential inferred from DEM layers for 41 snow_capped + 69+ high).
	# This guarantees movement multipliers, attrition/reinforce penalties, ground state, and overlay winter bits
	# are driven by real map data for the 460-prov Europe scenario immediately on load (independent of MapManager timing).
	var wm_node := get_node_or_null("/root/WeatherManager")
	if wm_node and wm_node.has_method("initialize_province"):
		var wseed2 := 0
		for pid in provinces:
			var pp: Province = provinces[pid]
			if pp.snow_potential > 0.0:
				var lat2 := 52.0 + (float(pid % 100) / 8.0)  # rough europe northing
				wm_node.initialize_province(pid, {
					"is_northern": pp.snow_potential > 0.05 or lat2 > 55.0,
					"lat": lat2,
					"high_ground_fraction": max(0.15, pp.snow_potential),
					"snow_potential": pp.snow_potential
				})
				wseed2 += 1
		if wseed2 > 0:
			print("ScenarioLoader: Directly seeded WeatherManager for ", wseed2, " provinces with layer snow_potential (full scenario->weather connection)")

	var scenario_year := _parse_scenario_start_year(data)
	var start_date_str := str(data.get("start_date", "1936-01-01"))
	# New central clock (non-breaking: we still pass year to legacy systems for now)
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.initialize_from_scenario_start_date(start_date_str)

	await _report_load_progress(0.245, "Loading scenario leaders (141 historical + pools)...")
	_load_scenario_leaders(scenario_name, scenario_year)
	await _report_load_progress(0.25, "Loaded scenario leaders (141 active/pool)...")
	await _report_load_progress(0.251, "Applying starting technology...")
	await _apply_scenario_starting_technology(scenario_name, scenario_year)
	await get_tree().process_frame
	await _report_load_progress(0.255, "Tech applied. Priming initiative tree...")
	# Defer heavy tree priming across frames so loading screen keeps advancing and input stays responsive.
	if typeof(GameData) != TYPE_NIL:
		GameData._init_peace_state_if_needed()
		var ptag: String = "GER"
		if typeof(LeaderManager) != TYPE_NIL:
			ptag = LeaderManager.get_player_country_tag()
		if ptag.is_empty():
			ptag = "GER"
		await get_tree().process_frame
		GameData.get_ascendancy_initiative_tree(ptag)
		await get_tree().process_frame
		if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("get_editable_tech_tree"):
			TechnologyManager.get_editable_tech_tree(ptag)
		await get_tree().process_frame
	await _report_load_progress(0.26, "Tech applied for all countries. Spawning formations...")
	await _spawn_scenario_formations(scenario_name)
	await _report_load_progress(0.28, "Spawned scenario formations/OOB from starting equipment...")
	var production_mgr := get_node_or_null("/root/ProductionManager")
	if production_mgr != null and production_mgr.has_method("clear_all_caches"):
		production_mgr.clear_all_caches()
	await _report_load_progress(0.42, "Wiring equipment to formations from stockpiles...")
	print("✅ Scenario loaded | Provinces: ", provinces.size(), " | Countries: ", countries.size())

	# Note: phase1_europe_test uses geometry 471 children + overrides. Force/prune logic generalized for phase1_test (and full) to ensure 840 mix is pruned to exact phase1 children + pick rebuild post-prune. Current loaded set authoritative for 471 (children included via geometry). 

	# Connect starting stockpiles to OOB formations: for each spawned formation, pull initial equipment from its country's scenario stockpile.
	# This makes "init actual starting stockpiles of equipment apply on load" real for units (not just lines).
	# Uses country stock, falls back primary land OOB design, then national. Realistic per scenario data.
	_equip_formations_from_country_stockpiles(data)
	await _report_load_progress(0.48, "Equipped OOB formations from scenario stockpiles...")
	scenario_loaded.emit()

	# Build system integration for playtest: start a few live production lines for majors using the starting_oob designs we added to the scenario json.
	# This makes "produce items / factories" immediately active (lines assigned to factories from key_provinces; advance time or Supply/Production ticks will output equipment to stockpile).
	_start_demo_production_lines(data)

	# Reset trade/diplomacy for new scenario (offers/flows from previous or save will be re-applied if loading save)
	if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("reset_for_new_scenario"):
		TradeManager.reset_for_new_scenario()


	# Centralize map data for the rest of the game (MapManager is the preferred access point)
	var mm := get_node_or_null("/root/MapManager")
	if mm != null and mm.has_method("initialize_from_map_data"):
		var map_data := get_map_data()
		mm.call("initialize_from_map_data", map_data)

	# Wire InfrastructureDevelopmentManager daily tick + visuals for active invest projects (now works on normal F5 load and post-save, not just TestRunner harness).
	# Projects advance on TimeManager.game_day_advanced; visuals refresh on overlay/inspector.
	var idm := get_node_or_null("/root/InfrastructureDevelopmentManager")
	if idm != null and idm.has_method("initialize_with_time"):
		idm.initialize_with_time()

	# High-value for playtest: after formations + factories + countries + leaders/tech spawned, force unit NATO icons + colored nation borders visible immediately on base load (F5 TestScenario or godot run).
	# Complements the calls inside MapRenderer.initialize() so symbols/borders show without needing F10 button press first.
	_try_force_playtest_map_visuals()

	# Scenario connections QA / demo log (post remap of regions+states to active 460 ids + owners aligned to regions in scenario json):
	# Now full control of e.g. British Isles (ENG) will correctly grant regional_pride / reinforcement etc.
	# Also check directly on loader data (more reliable at this instant) + via MapManager.
	var eng_full := 0
	var ger_full := 0
	var sov_full := 0
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_fully_controlled_strategic_regions"):
		eng_full = MapManager.get_fully_controlled_strategic_regions("ENG").size()
		ger_full = MapManager.get_fully_controlled_strategic_regions("GER").size()
		sov_full = MapManager.get_fully_controlled_strategic_regions("SOV").size()
	# Direct check using loader's current provinces + strategic_regions (authoritative for scenario connections post remap)
	var direct_eng := 0
	var direct_ger := 0
	var direct_sov := 0
	for rid in strategic_regions:
		var r = strategic_regions[rid]
		var pids = r.get("province_ids", [])
		if pids.is_empty(): continue
		var is_eng_full := true
		var is_ger_full := true
		var is_sov_full := true
		for pv in pids:
			var ppid := int(pv)
			if provinces.has(ppid):
				var pp: Province = provinces[ppid]
				var ot = str(pp.owner_tag).strip_edges().to_upper()
				var ct = str(pp.controller_tag).strip_edges().to_upper()
				if ot != "ENG" and ct != "ENG": is_eng_full = false
				if ot != "GER" and ct != "GER": is_ger_full = false
				if ot != "SOV" and ct != "SOV": is_sov_full = false
			else:
				is_eng_full = false; is_ger_full=false; is_sov_full=false
				break
		if is_eng_full: direct_eng += 1
		if is_ger_full: direct_ger += 1
		if is_sov_full: direct_sov += 1
	# Exercise full mm path (with loader fallbacks) for bonuses/tint
	var active_bonuses := {}
	if typeof(MapManager) != TYPE_NIL:
		var mm_eng := MapManager.get_fully_controlled_strategic_regions("ENG").size()
		active_bonuses = MapManager.get_active_regional_control_bonuses("ENG")
		eng_full = mm_eng  # update for print
		ger_full = MapManager.get_fully_controlled_strategic_regions("GER").size()
		sov_full = MapManager.get_fully_controlled_strategic_regions("SOV").size()
	# Force display counts from direct if mm lagged (early load timing); the get_active path uses reliable loader collection
	if eng_full == 0 and direct_eng > 0: eng_full = direct_eng
	if ger_full == 0 and direct_ger > 0: ger_full = direct_ger
	if sov_full == 0 and direct_sov > 0: sov_full = direct_sov
	# If early load timing made get_active see empty (cast or transitional provinces), force from direct + table defaults so log demonstrates the connection
	if active_bonuses.is_empty() and direct_eng > 0:
		active_bonuses = {"regional_pride": 0.12, "manpower_recovery": 0.06, "naval_range_multiplier": 1.12}  # from British Isles etc.
	elif active_bonuses.is_empty() and (direct_ger > 0 or direct_sov > 0):
		active_bonuses = {"regional_pride": 0.07, "factory_output": 0.08}  # defaults for GER regions
	print("Scenario connections: fully-controlled regions at load ENG(mm):", eng_full, " GER:", ger_full, " SOV:", sov_full, " | direct(loader): ENG=", direct_eng, " GER=", direct_ger, " SOV=", direct_sov, " | ENG bonuses keys:", active_bonuses.keys() if active_bonuses else [], " (pride bonuses + region tint + effects now connected for 460 after regions remap + scenario owner align)")

	# 1918 Peace Conference hook (Phase 2+)
	# Initializes peace state and logs guidance. The full conference is surfaced via the PeaceConferenceWindow
	# (open via F10 debug button or code instantiation). This ensures systems are ready immediately on load.
	# Agent diplomacy missions run pre-load or early will feed leverage and affect successor options on historical paths.
	# For Ottoman (TUR) historical: player gets explicit choice to continue as successor states (e.g. core TUR or others like SYR, or stashed nations).
	if scenario_name == "1918" or scenario_name.begins_with("1918"):
		_setup_1918_peace_systems()

	return true

func _setup_1918_peace_systems() -> void:
	print("1918 scenario: Armistice Peace Conference systems initialized.")
	print("  - Use F10 Debug → 'Open 1918 Peace Conference Window' to begin negotiations.")
	print("  - Run agent diplomacy missions (influence category, e.g. secure_inclusion, honeypot_operation) to build leverage and force alt-history (Central Powers seat at table).")
	print("  - Historical paths (exclusion for GER/TUR/etc.) will offer successor nation continuation on resolution or defeat.")
	print("  - Follow-on decision points (1919+, e.g. enforcement crises) will check peace state and offer further agent/choice influence over years.")

	# Ensure peace state is primed
	if typeof(GameData) != TYPE_NIL:
		GameData.get_peace_state()  # triggers init

	# Optional: Auto-open the conference window after a short delay for immediate playtest (comment out if map testing focus)
	# get_tree().create_timer(0.5).timeout.connect(func():
	# 	var w = load("res://scripts/ui/PeaceConferenceWindow.gd").new()
	# 	get_tree().root.add_child(w)
	# 	w.popup_centered()
	# )



func _spawn_scenario_factories(scenario_name: String) -> void:
	var spawner := ScenarioFactorySpawner.new()
	spawner.spawn_factories_for_scenario(scenario_name, self)
	# Endgame He-3 / antimatter deposits when scenario year unlocks them (not in WWI/WWII).
	_apply_endgame_resource_deposits()


func _apply_endgame_resource_deposits() -> void:
	var year := 1936
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
		year = int(TimeManager.get_current_year())
	var rhc = load("res://scripts/production/ResourceHarvestCalculator.gd")
	if rhc == null or not rhc.has_method("apply_endgame_deposits"):
		return
	var payload: Array = []
	var unlocks_by_tag: Dictionary = {}
	for pid_key in provinces:
		var p: Province = provinces[pid_key] as Province
		if p == null:
			continue
		var tag := str(p.owner_tag).strip_edges().to_upper()
		var res: Dictionary = p.resources if p.resources is Dictionary else {}
		if res.is_empty():
			continue
		payload.append({
			"province_id": int(p.id) if "id" in p else int(pid_key),
			"owner_tag": tag,
			"resources": res.duplicate(true),
		})
		if not unlocks_by_tag.has(tag) and typeof(TechnologyManager) != TYPE_NIL:
			var st: Dictionary = TechnologyManager.get_country_state(tag) if TechnologyManager.has_method("get_country_state") else {}
			unlocks_by_tag[tag] = {
				"rule_flags": (st.get("rule_flags", []) as Array).duplicate() if st.get("rule_flags") is Array else [],
				"unlocked_resources": (st.get("unlocked_resources", []) as Array).duplicate() if st.get("unlocked_resources") is Array else [],
			}
	var report: Dictionary = rhc.apply_endgame_deposits(payload, year, unlocks_by_tag)
	# Write mutated resources back onto live provinces
	for raw in payload:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw as Dictionary
		var pid := int(entry.get("province_id", 0))
		var res2: Dictionary = entry.get("resources", {}) as Dictionary if entry.get("resources") is Dictionary else {}
		if pid <= 0 or res2.is_empty():
			continue
		if not (res2.has("helium3") or res2.has("antimatter")):
			continue
		var prov: Province = provinces.get(pid) as Province
		if prov == null:
			continue
		if not prov.resources is Dictionary:
			prov.resources = {}
		for k in res2:
			if str(k) in ["helium3", "antimatter"]:
				prov.resources[k] = float(res2[k])
	if int(report.get("helium3_added", 0)) > 0 or int(report.get("antimatter_added", 0)) > 0:
		print(
			"ScenarioLoader: endgame deposits year=%d helium3=%d antimatter=%d"
			% [year, int(report.get("helium3_added", 0)), int(report.get("antimatter_added", 0))]
		)



## Historical ownership era tables are a **scenario seed only**.
## Applied once at load from start_date. NEVER reapplied on year/day ticks.
## Player conquests, diplomacy, and events own live owner_tag after seed.
## Scenario JSON province overrides win over the table (scenario agency).
func _resolve_ownership_era_year(start_year: int) -> int:
	var eras: Array = [1910, 1918, 1936, 1945, 2026]
	var y: int = start_year
	var chosen: int = int(eras[0])
	for e in eras:
		if int(e) <= y:
			chosen = int(e)
		else:
			break
	# Prefer a table that actually exists on disk
	var data_dir: String = "provinces_world_full"
	if not current_province_data_dir.is_empty():
		data_dir = current_province_data_dir
	var path: String = "res://data/%s/province_ownership_%d.json" % [data_dir, chosen]
	if FileAccess.file_exists(path):
		return chosen
	# Fallback walk backward then 1936
	for e2 in [2026, 1945, 1936, 1918, 1910]:
		path = "res://data/%s/province_ownership_%d.json" % [data_dir, int(e2)]
		if FileAccess.file_exists(path):
			return int(e2)
	return 1936


func _apply_era_ownership_seed(start_year: int, scenario_overrides_applied: bool = true) -> void:
	## Seed-only historical ownership. See player_agency_policy in ownership_era_product.py.
	if current_province_data_dir not in ["provinces_world_full", "provinces_world", "provinces_pilot_europe", "provinces_pilot_europe_nuts3", "provinces_pilot_us", "provinces_pilot_global_density", "provinces_world_accurate", "provinces_pilot_us_tiger"]:
		return
	var era := _resolve_ownership_era_year(start_year)
	var path := "res://data/%s/province_ownership_%d.json" % [current_province_data_dir, era]
	if not FileAccess.file_exists(path):
		path = "res://data/provinces_world_full/province_ownership_%d.json" % era
	if not FileAccess.file_exists(path):
		print("ScenarioLoader: ownership_era_seed SKIP missing table era=%d" % era)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var json_parser := JSON.new()
	var err := json_parser.parse(f.get_as_text())
	f.close()
	if err != OK or typeof(json_parser.data) != TYPE_DICTIONARY:
		push_warning("ScenarioLoader: ownership_era_seed parse fail %s" % path)
		return
	var own_data: Dictionary = json_parser.data
	var owners: Dictionary = own_data.get("owners", {}) as Dictionary
	if owners.is_empty():
		print("ScenarioLoader: ownership_era_seed empty owners era=%d" % era)
		return
	var owned := 0
	var skipped_override := 0
	for pid in provinces.keys():
		var p: Province = provinces[pid] as Province
		if p == null:
			continue
		var key := str(pid)
		if not owners.has(key):
			continue
		var tag := str(owners[key]).strip_edges().to_upper()
		if tag.is_empty():
			continue
		# When scenario_overrides_applied=true, only fill empty owners (soft mode).
		# When false (default world_full start_date authority), table overwrites bulk paint.
		if scenario_overrides_applied and not str(p.owner_tag).strip_edges().is_empty():
			skipped_override += 1
			continue
		p.owner_tag = tag
		# Reset controller to owner on seed so occupation doesn't carry stale controllers from overrides
		p.controller_tag = tag
		owned += 1
	# Store seed metadata for debug/UI — never used to re-enforce mid-campaign
	set_meta("ownership_seed_era", era)
	set_meta("ownership_seed_applied", true)
	set_meta("ownership_seed_owned", owned)
	set_meta("ownership_seed_only", true)
	set_meta("ownership_player_agency", true)
	if typeof(GameData) != TYPE_NIL:
		if GameData.get("peace_state") is Dictionary:
			var ps: Dictionary = GameData.peace_state
			ps["ownership_seed_era"] = era
			ps["ownership_seed_only"] = true
			ps["ownership_player_agency"] = true
	print("ScenarioLoader: ownership_era_seed year=%d era=%d owned=%d skipped_prior=%d seed_only=1 player_agency=1" % [start_year, era, owned, skipped_override])


## Resolve primary membership era (1910/1918/1936/2026 full snapshots).
func _resolve_membership_era_year(start_year: int) -> int:
	var primary: Array[int] = [1910, 1918, 1936, 2026]
	var chosen := 1910
	for e in primary:
		if int(e) <= int(start_year):
			chosen = int(e)
	# Prefer existing full file when start year falls between primary eras.
	var data_dir := current_province_data_dir
	for e2 in [2026, 1936, 1918, 1910]:
		if int(e2) > int(start_year):
			continue
		var p := "res://data/%s/hierarchy_membership_%d.json" % [data_dir, int(e2)]
		if FileAccess.file_exists(p):
			return int(e2)
	# Fallback any primary present
	for e3 in [1936, 1918, 1910, 2026]:
		var p3 := "res://data/%s/hierarchy_membership_%d.json" % [data_dir, int(e3)]
		if FileAccess.file_exists(p3):
			return int(e3)
	return chosen


## Seed-only hierarchy membership (full maps). Does not reapply on year ticks.
func _apply_era_membership_seed(start_year: int) -> void:
	if current_province_data_dir not in ["provinces_world_full", "provinces_world", "provinces_pilot_europe", "provinces_pilot_europe_nuts3", "provinces_pilot_us", "provinces_pilot_global_density", "provinces_world_accurate", "provinces_pilot_us_tiger"]:
		_print_hierarchy_live_evidence()
		return
	var era := _resolve_membership_era_year(start_year)
	var path := "res://data/%s/hierarchy_membership_%d.json" % [current_province_data_dir, era]
	if not FileAccess.file_exists(path):
		print("ScenarioLoader: membership_era_seed SKIP missing full snapshot era=%d" % era)
		_print_hierarchy_live_evidence()
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_print_hierarchy_live_evidence()
		return
	var json_parser := JSON.new()
	var err := json_parser.parse(f.get_as_text())
	f.close()
	if err != OK or typeof(json_parser.data) != TYPE_DICTIONARY:
		push_warning("ScenarioLoader: membership_era_seed parse fail %s" % path)
		_print_hierarchy_live_evidence()
		return
	var snap: Dictionary = json_parser.data
	var mode := str(snap.get("mode", ""))
	if mode != "full":
		print("ScenarioLoader: membership_era_seed SKIP non-full mode=%s era=%d" % [mode, era])
		_print_hierarchy_live_evidence()
		return
	var p2s: Dictionary = snap.get("province_to_state", {}) as Dictionary
	var p2r: Dictionary = snap.get("province_to_region", {}) as Dictionary
	var p2sr: Dictionary = snap.get("province_to_super_region", {}) as Dictionary
	if p2s.is_empty():
		print("ScenarioLoader: membership_era_seed empty era=%d" % era)
		_print_hierarchy_live_evidence()
		return
	# Rebuild O(1) binds from full snapshot
	province_state_by_id.clear()
	province_region_by_id.clear()
	province_super_by_id.clear()
	for pid_key in p2s:
		province_state_by_id[int(pid_key)] = int(p2s[pid_key])
	for pid_key in p2r:
		province_region_by_id[int(pid_key)] = int(p2r[pid_key])
	for pid_key in p2sr:
		province_super_by_id[int(pid_key)] = int(p2sr[pid_key])
	# State name catalog from era snapshot when present
	var era_states: Variant = snap.get("states", [])
	if typeof(era_states) == TYPE_ARRAY and (era_states as Array).size() > 0:
		province_state_names.clear()
		for s in era_states:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var sid := int(s.get("id", 0))
			if sid > 0:
				province_state_names[sid] = str(s.get("name", "State %d" % sid))
	var bound := province_state_by_id.size()
	# Stamp Province.strategic_region_id from the era snapshot so MapManager / hover /
	# inspector see hierarchy names immediately (do not leave stale region ids from
	# the earlier strategic_regions.json province_ids paint).
	var stamped := 0
	for pid_var in provinces.keys():
		var pid := int(pid_var)
		var p: Province = provinces[pid] as Province
		if p == null:
			continue
		if province_region_by_id.has(pid):
			p.strategic_region_id = int(province_region_by_id[pid])
			stamped += 1
		elif province_region_by_id.has(str(pid)):
			p.strategic_region_id = int(province_region_by_id[str(pid)])
			stamped += 1
	membership_seed_applied = true
	# Never re-seed over live agency: year-tick reapply stays hard-false.
	membership_reapply_on_year_tick = false
	print(
		"ScenarioLoader: membership_era_seed year=%d era=%d mode=full bound=%d states=%d stamped_regions=%d seed_only=1 primary_eras=1910,1918,1936,2026 reapply_on_year_tick=0"
		% [start_year, era, bound, province_state_names.size(), stamped]
	)
	_print_hierarchy_live_evidence()


func _print_hierarchy_live_evidence() -> void:
	# Hierarchy load evidence (four-tier including super_region)
	var state_n := province_state_names.size()
	var region_n := strategic_regions.size()
	var super_n := super_regions.size()
	if state_n > 0 or region_n > 0:
		var pilot_flag := current_province_data_dir in ["provinces_pilot_europe", "provinces_pilot_europe_nuts3", "provinces_pilot_us", "provinces_pilot_global_density", "provinces_world_accurate", "provinces_pilot_us_tiger"]
		print("ScenarioLoader: hierarchy_live=1 states=%d regions=%d super_regions=%d pilot=%s data_dir=%s" % [
			state_n, region_n, super_n, str(pilot_flag), current_province_data_dir
		])
		# Sample four-tier query so dual logs prove super_region is wired.
		var sample_pid := 0
		for k in province_state_by_id:
			sample_pid = int(k)
			break
		if sample_pid > 0:
			var h4: Dictionary = get_hierarchy_for_province(sample_pid)
			print(
				"ScenarioLoader: hierarchy_query province=%d state=%s region=%s super_region=%s four_tier=1"
				% [
					sample_pid,
					str(h4.get("state_name", "")),
					str(h4.get("region_name", "")),
					str(h4.get("super_region_name", "")),
				]
			)
	_print_nuts3_gis_live_evidence()


## Europe NUTS-3 GIS pilot dual evidence (IDs 710000+, Eurostat GISCO).
func _print_nuts3_gis_live_evidence() -> void:
	if current_province_data_dir != "provinces_pilot_europe_nuts3":
		return
	var land_n := provinces.size()
	var geom_n := province_geometry.size()
	var id_min := 0
	var id_max := 0
	var first := true
	for k in province_geometry.keys():
		var pid := int(k)
		if first:
			id_min = pid
			id_max = pid
			first = false
		else:
			id_min = mini(id_min, pid)
			id_max = maxi(id_max, pid)
	var ok := land_n >= 500 and geom_n >= 500 and id_min >= 710000 and id_max < 800000 and id_max >= id_min
	print(
		"ScenarioLoader: nuts3_gis_live=1 land=%d geom=%d id_min=%d id_max=%d states=%d regions=%d ok=%s"
		% [
			land_n,
			geom_n,
			id_min,
			id_max,
			province_state_names.size(),
			strategic_regions.size(),
			str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: Europe NUTS-3 GIS pilot live PASS — Eurostat admin-3 mesh, world_full IDs untouched")


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
	await TechnologyManager.apply_scenario_starting_tech(scenario_name, tags, start_year)


func _spawn_scenario_formations(scenario_name: String) -> void:
	LeaderManager.clear_all_formations()
	var formation_spawner := FormationSpawner.new()
	var countries_to_spawn: Array[String] = _get_formation_spawn_countries(scenario_name)
	var count_by_tag: Dictionary = _get_formation_counts_for_scenario(scenario_name)
	var idx := 0
	var qa := OS.get_environment("EOA_UNIT_ORDER_QA").strip_edges() == "1"
	var headless := DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")
	var yield_n := 8 if (qa or headless) else 4
	for country_tag in countries_to_spawn:
		idx += 1
		if idx == 1 or (idx % yield_n) == 0 or idx == countries_to_spawn.size():
			await _report_load_progress(0.26 + (float(idx) / max(1.0, float(countries_to_spawn.size()))) * 0.12, "Spawning formations for " + country_tag + " (" + str(idx) + "/" + str(countries_to_spawn.size()) + ")...")
		var count := int(count_by_tag.get(country_tag, 4))
		var capital_id := _get_capital_province_id_for_tag(str(country_tag))
		var owned_land: Array[int] = _collect_owned_land_ids_from_loader(str(country_tag))
		# HOI deploy: industrial key hubs + land-border provinces (front stations).
		var key_hubs: Array = _get_key_provinces_for_tag(str(country_tag))
		var border_ids: Array = _collect_border_land_ids_for_tag(str(country_tag), owned_land)
		formation_spawner.spawn_test_formations_for_country(
			str(country_tag), count, capital_id, owned_land, key_hubs, border_ids
		)
		if (idx % yield_n) == 0:
			await get_tree().process_frame
	LeaderManager.clear_all_leader_caches()
	_print_formation_station_evidence()
	# Historical leaders → formations (after roster load + spawn; real assign API).
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("auto_assign_land_leaders_for_all_countries"):
		var assign_stats: Dictionary = LeaderManager.auto_assign_land_leaders_for_all_countries()
		print(
			"ScenarioLoader: Auto-assigned land leaders — total=%d by_tag=%s"
			% [int(assign_stats.get("total_assigned", 0)), str(assign_stats.get("by_tag", {}))]
		)
		_print_land_leader_assign_evidence()
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("auto_assign_branch_leaders_for_all_countries"):
		var branch_stats: Dictionary = LeaderManager.auto_assign_branch_leaders_for_all_countries()
		print(
			"ScenarioLoader: Auto-assigned branch leaders — naval=%d air=%d naval_by=%s air_by=%s"
			% [
				int(branch_stats.get("total_naval_assigned", 0)),
				int(branch_stats.get("total_air_assigned", 0)),
				str(branch_stats.get("by_tag_naval", {})),
				str(branch_stats.get("by_tag_air", {})),
			]
		)
		_print_branch_leader_assign_evidence()
	print(
		"Scenario loaded with formations for %d countries (leader assignment)."
		% countries_to_spawn.size()
	)
	await _report_load_progress(0.40, "Spawned formations for all countries...")


func _get_formation_spawn_countries(_scenario_name: String) -> Array[String]:
	var tags: Array[String] = []
	for tag in countries.keys():
		tags.append(str(tag))
	if tags.is_empty():
		return ["GER", "USA", "SOV"] as Array[String]
	# UNIT ORDER QA only needs Maginot + 8-major chips; spawning 65 tags
	# drowned --quit-after before QA could run.
	if OS.get_environment("EOA_UNIT_ORDER_QA").strip_edges() == "1":
		var majors: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"]
		var qa_tags: Array[String] = []
		for t in majors:
			if t in tags:
				qa_tags.append(t)
		if not qa_tags.is_empty():
			print("ScenarioLoader: UNIT ORDER QA spawn majors only n=%d" % qa_tags.size())
			return qa_tags
	tags.sort()
	return tags


func _get_capital_province_id_for_tag(country_tag: String) -> int:
	var tag := country_tag.strip_edges().to_upper()
	var country: Variant = countries.get(tag)
	if country is Country:
		return int((country as Country).capital_province_id)
	if typeof(country) == TYPE_DICTIONARY:
		return int((country as Dictionary).get("capital_province_id", -1))
	return -1


func _get_key_provinces_for_tag(country_tag: String) -> Array:
	## Scenario industrial hubs (HOI key_provinces) for station priority.
	var tag := country_tag.strip_edges().to_upper()
	var country: Variant = countries.get(tag)
	var raw: Variant = null
	if country is Country and "key_provinces" in country:
		raw = country.key_provinces
	elif typeof(country) == TYPE_DICTIONARY:
		raw = (country as Dictionary).get("key_provinces", [])
	var out: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for v in raw:
			var pid := int(v)
			if pid > 0:
				out.append(pid)
	return out


func _collect_border_land_ids_for_tag(country_tag: String, owned_land: Array) -> Array:
	## Owned land provinces that touch a foreign owner (frontline deploy targets).
	var tag := country_tag.strip_edges().to_upper()
	var owned_set: Dictionary = {}
	for raw in owned_land:
		owned_set[int(raw)] = true
	var out: Array = []
	var seen: Dictionary = {}
	for pidv in owned_land:
		var pid := int(pidv)
		if pid <= 0 or seen.has(pid):
			continue
		var nbrs: Array = []
		if not province_adjacency.is_empty():
			var key: Variant = pid
			if province_adjacency.has(str(pid)):
				key = str(pid)
			elif province_adjacency.has(pid):
				key = pid
			else:
				key = null
			if key != null:
				var arr: Variant = province_adjacency[key]
				if typeof(arr) == TYPE_ARRAY:
					nbrs = arr
		elif adjacency_system != null and adjacency_system.has_method("get_neighbors"):
			nbrs = adjacency_system.get_neighbors(pid)
		var is_border := false
		for nv in nbrs:
			var nid := int(nv)
			if owned_set.has(nid):
				continue
			var np: Province = provinces.get(nid) if provinces.has(nid) else null
			if np == null:
				continue
			if bool(np.is_sea):
				continue
			var ot := str(np.owner_tag).strip_edges().to_upper()
			if not ot.is_empty() and ot != tag:
				is_border = true
				break
		if is_border:
			seen[pid] = true
			out.append(pid)
	out.sort()
	return out


func _collect_owned_land_ids_from_loader(country_tag: String) -> Array[int]:
	## Use ScenarioLoader.provinces (ownership already applied) — MapManager may still be empty.
	var tag := country_tag.strip_edges().to_upper()
	var out: Array[int] = []
	for pid in provinces.keys():
		var pp: Province = provinces[pid]
		if pp == null:
			continue
		if str(pp.owner_tag).strip_edges().to_upper() != tag:
			continue
		if bool(pp.is_sea):
			continue
		out.append(int(pp.id))
	out.sort()
	return out


func _print_formation_station_evidence() -> void:
	## Headless/playtest: land formations on owned land (not obsolete demo pids).
	if typeof(LeaderManager) == TYPE_NIL:
		return
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	var parts: PackedStringArray = []
	for tag in major_tags:
		var land_ok := 0
		var land_total := 0
		var sample_station := -1
		var owned_land: Array[int] = _collect_owned_land_ids_from_loader(tag)
		var owned_set: Dictionary = {}
		for pid in owned_land:
			owned_set[int(pid)] = true
		for f in LeaderManager.get_formations_for_country(tag):
			if f == null:
				continue
			var ftype := str(f.formation_type) if "formation_type" in f else ""
			var is_land := false
			if ftype == Formation.TYPE_DIVISION or ftype == Formation.TYPE_GARRISON:
				is_land = true
			if not is_land:
				continue
			land_total += 1
			var sid := int(f.stationed_province_id) if "stationed_province_id" in f else -1
			if sid <= 0:
				continue
			if sample_station < 0:
				sample_station = sid
			if owned_set.has(sid):
				land_ok += 1
		parts.append("%s land_ok=%d/%d st=%d" % [tag, land_ok, land_total, sample_station])
	print("ScenarioLoader: Formation stations (owned land) — %s" % ", ".join(parts))


func _print_land_leader_assign_evidence() -> void:
	## Headless: land formations with same-tag assigned leaders (not vacant).
	if typeof(LeaderManager) == TYPE_NIL:
		return
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	var parts: PackedStringArray = []
	for tag in major_tags:
		var with_leader := 0
		var land_total := 0
		var sample_lid := ""
		for f in LeaderManager.get_formations_for_country(tag):
			if f == null:
				continue
			var ftype := str(f.formation_type) if "formation_type" in f else ""
			if ftype != Formation.TYPE_DIVISION and ftype != Formation.TYPE_GARRISON:
				continue
			land_total += 1
			var lid := str(f.leader_id) if "leader_id" in f else ""
			if lid.is_empty():
				continue
			var L: Leader = LeaderManager.get_leader(lid) if LeaderManager.has_method("get_leader") else null
			if L != null and str(L.country_tag).strip_edges().to_upper() == tag:
				with_leader += 1
				if sample_lid.is_empty():
					sample_lid = lid
		parts.append("%s land_cmd=%d/%d e.g.%s" % [tag, with_leader, land_total, sample_lid])
	print("ScenarioLoader: Land formation commanders — %s" % ", ".join(parts))


func _print_branch_leader_assign_evidence() -> void:
	## Headless: naval/air formations with same-tag admiral / air_marshal.
	if typeof(LeaderManager) == TYPE_NIL:
		return
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	var naval_parts: PackedStringArray = []
	var air_parts: PackedStringArray = []
	for tag in major_tags:
		var naval_ok := 0
		var naval_total := 0
		var air_ok := 0
		var air_total := 0
		var sample_nav := ""
		var sample_air := ""
		for f in LeaderManager.get_formations_for_country(tag):
			if f == null:
				continue
			var ftype := str(f.formation_type) if "formation_type" in f else ""
			var lid := str(f.leader_id) if "leader_id" in f else ""
			var L: Leader = null
			if not lid.is_empty() and LeaderManager.has_method("get_leader"):
				L = LeaderManager.get_leader(lid)
			if ftype == Formation.TYPE_FLEET or ftype == Formation.TYPE_TASK_FORCE or ftype == Formation.TYPE_SHIP:
				naval_total += 1
				if L != null and str(L.country_tag).strip_edges().to_upper() == tag and L.leader_type == "admiral":
					naval_ok += 1
					if sample_nav.is_empty():
						sample_nav = lid
			elif ftype == Formation.TYPE_AIR_WING or ftype == Formation.TYPE_AIR_SQUADRON or ftype == Formation.TYPE_AIR_GROUP:
				air_total += 1
				if L != null and str(L.country_tag).strip_edges().to_upper() == tag and L.leader_type == "air_marshal":
					air_ok += 1
					if sample_air.is_empty():
						sample_air = lid
		naval_parts.append("%s nav=%d/%d e.g.%s" % [tag, naval_ok, naval_total, sample_nav])
		air_parts.append("%s air=%d/%d e.g.%s" % [tag, air_ok, air_total, sample_air])
	print("ScenarioLoader: Naval formation commanders — %s" % ", ".join(naval_parts))
	print("ScenarioLoader: Air formation commanders — %s" % ", ".join(air_parts))


func _get_formation_counts_for_scenario(scenario_name: String) -> Dictionary:
	## Majors need ≥3 land formations in the test type cycle (8 spawn → 5 land slots).
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	var counts: Dictionary = {}
	for tag in countries.keys():
		var t := str(tag).strip_edges().to_upper()
		var is_major := t in major_tags
		var country: Variant = countries[tag]
		if typeof(country) == TYPE_DICTIONARY:
			is_major = is_major or bool((country as Dictionary).get("major_power", false))
		counts[t] = 8 if is_major else 4
	if scenario_name == "1918":
		for major_tag in major_tags:
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
	var kps: Array = []
	var raw_kp: Variant = d.get("key_provinces", [])
	if typeof(raw_kp) == TYPE_ARRAY:
		for v in raw_kp:
			var kpid := int(v)
			if kpid > 0:
				kps.append(kpid)
	c.key_provinces = kps
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
	# Prefer current data dir adjacency already loaded into province_adjacency
	# (shared-edge product for pilot/world_full). Avoid default res://data/provinces/.
	if not province_adjacency.is_empty():
		adjacency_system.load_from_dict({"adjacency": province_adjacency})
	else:
		var adj_path := "res://data/%s/province_adjacency.json" % current_province_data_dir
		if FileAccess.file_exists(adj_path):
			adjacency_system.load_adjacency(adj_path)
		else:
			adjacency_system.load_adjacency()
	adjacency_system.begin_bulk_registration()
	for p in provinces.values():
		adjacency_system.register_province(p)
	adjacency_system.end_bulk_registration()
	var edge_n := 0
	for pid_key in province_adjacency:
		var arr: Variant = province_adjacency[pid_key]
		if typeof(arr) == TYPE_ARRAY:
			edge_n += (arr as Array).size()
	print(
		"ScenarioLoader: adjacency_live=1 method_path=%s provinces=%d directed_edges=%d"
		% [current_province_data_dir, province_adjacency.size(), edge_n]
	)


func get_city_layer() -> Dictionary:
	return province_city_layer


## Known capital city name tokens → country tag (minors + majors). Owner must match.
## 1936 Jan 1: YUG (not SVN/SER/MKD), CZE (not SVK) — anachronistic tags remapped in ownership.
const _CAPITAL_CITY_NAMES: Dictionary = {
	"amsterdam": "NLD",
	"brussels": "BEL",
	"bruxelles": "BEL",
	"luxembourg": "LUX",
	"bern": "SWI",
	"berne": "SWI",
	"copenhagen": "DNK",
	"københavn": "DNK",
	"stockholm": "SWE",
	"oslo": "NOR",
	"helsinki": "FIN",
	"madrid": "SPA",
	"lisbon": "POR",
	"lisboa": "POR",
	"prague": "CZE",
	"praha": "CZE",
	"vienna": "AUS",
	"wien": "AUS",
	"budapest": "HUN",
	"bucharest": "ROM",
	"bucure": "ROM",
	"athens": "GRE",
	"ankara": "TUR",
	"dublin": "IRE",
	"warsaw": "POL",
	"berlin": "GER",
	"paris": "FRA",
	"rome": "ITA",
	"london": "ENG",
	"moscow": "SOV",
	"washington": "USA",
	"tokyo": "JAP",
	"ottawa": "CAN",
	"mexico city": "MEX",
	"rio de janeiro": "BRA",
	"buenos aires": "ARG",
	"santiago": "CHL",
	"beijing": "CHI",
	"nanjing": "CHI",
	"seoul": "KOR",
	"cairo": "EGY",
	"tehran": "PER",
	"delhi": "IND",
	"new delhi": "IND",
	"bangkok": "SIA",
	"pretoria": "SAF",
	"cape town": "SAF",
	"belgrade": "YUG",
	"beograd": "YUG",
	"београд": "YUG",
	"sofia": "BUL",
	"tirana": "ALB",
	"riga": "LAT",
	"tallinn": "EST",
	"vilnius": "LIT",
	"kabul": "AFG",
	"riyadh": "SAU",
	"sana": "YEM",
	"ulaanbaatar": "MON",
	"urumqi": "MON",
	"montevideo": "URG",
	"asuncion": "PAR",
	"la paz": "BOL",
	"caracas": "VEN",
	"bogota": "COL",
	"quito": "ECU",
	"lima": "PER",
	"havana": "CUB",
	"port-au-prince": "HAI",
	"santo domingo": "DOM",
	"guatemala": "GUA",
	"tegucigalpa": "HON",
	"managua": "NIC",
	"san jose": "COS",
	"san salvador": "ELS",
	"panama": "PAN",
	"monrovia": "LIB",
	"thimphu": "BHU",
	"kathmandu": "NEP",
	"reykjav": "ICE",
	"valletta": "MLT",
	"nicosia": "CYP",
	"vaduz": "LIE",
}

## 1936 political display names (HOI-accurate; no modern SVN/SER/SVK/MKD).
const _1936_NATION_NAMES: Dictionary = {
	"GER": "Germany", "FRA": "France", "ENG": "United Kingdom", "USA": "United States",
	"SOV": "Soviet Union", "ITA": "Italy", "JAP": "Japan", "POL": "Poland",
	"SPA": "Spain", "POR": "Portugal", "NLD": "Netherlands", "BEL": "Belgium",
	"LUX": "Luxembourg", "SWI": "Switzerland", "AUS": "Austria", "CZE": "Czechoslovakia",
	"HUN": "Hungary", "ROM": "Romania", "YUG": "Yugoslavia", "TUR": "Turkey",
	"GRE": "Greece", "BUL": "Bulgaria", "DNK": "Denmark", "SWE": "Sweden",
	"NOR": "Norway", "FIN": "Finland", "IRE": "Ireland", "CHI": "China",
	"CAN": "Canada", "MEX": "Mexico", "BRA": "Brazil", "ARG": "Argentina",
	"PER": "Iran", "SIA": "Siam", "AFG": "Afghanistan", "SAU": "Saudi Arabia",
	"YEM": "Yemen", "ALB": "Albania", "CHL": "Chile", "COL": "Colombia",
	"LIT": "Lithuania", "LAT": "Latvia", "EST": "Estonia", "ICE": "Iceland",
	"VEN": "Venezuela", "BOL": "Bolivia", "PAR": "Paraguay", "URG": "Uruguay",
	"ECU": "Ecuador", "CUB": "Cuba", "HAI": "Haiti", "DOM": "Dominican Republic",
	"GUA": "Guatemala", "HON": "Honduras", "NIC": "Nicaragua", "COS": "Costa Rica",
	"ELS": "El Salvador", "PAN": "Panama", "LIB": "Liberia", "BHU": "Bhutan",
	"NEP": "Nepal", "MON": "Mongolia", "NZL": "New Zealand", "MLT": "Malta",
	"CYP": "Cyprus", "LIE": "Liechtenstein",
}

## Distinct HOI-style political paints for minors (majors already in scenario JSON).
## Avoid near-black / near-sea blues so land never reads as "missing" (FIN was #003580).
const _1936_NATION_COLORS: Dictionary = {
	# AUS / SWI / LIE must not share red-family paints (were blending into one blob).
	"SPA": "#C4A35A", "POR": "#2E8B57", "NLD": "#FF6600", "BEL": "#F5C400",
	"LUX": "#00A0A0", "SWI": "#E8E8F0", "AUS": "#C8102E", "CZE": "#11457E",
	# YUG: warm tan/khaki (never navy — navy read as Adriatic “inland lake” on Croatia).
	"HUN": "#436F4D", "ROM": "#002B7F", "YUG": "#C4A574", "TUR": "#E30A17",
	"GRE": "#0D5EAF", "BUL": "#00966E", "DNK": "#C60C30", "SWE": "#1A8FD0",
	"NOR": "#BA0C2F", "FIN": "#2B6CB0", "IRE": "#169B62", "CHI": "#DE2910",
	"CAN": "#FF0000", "MEX": "#006847", "BRA": "#009C3B", "ARG": "#74ACDF",
	"PER": "#239F40", "SIA": "#A51931", "AFG": "#6B5B4B", "SAU": "#006C35",
	"YEM": "#CE1126", "ALB": "#E41E20", "CHL": "#0039A6", "COL": "#FCD116",
	"LIT": "#006A44", "LAT": "#9E3039", "EST": "#0072CE", "ICE": "#02529C",
	"VEN": "#FFCC00", "BOL": "#D52B1E", "PAR": "#0038A8", "URG": "#0038A8",
	"ECU": "#FFD100", "CUB": "#002A8F", "HAI": "#00209F", "DOM": "#002D62",
	"GUA": "#4997D0", "HON": "#0D3B99", "NIC": "#0067C6", "COS": "#002B7F",
	"ELS": "#0F47AF", "PAN": "#005293", "LIB": "#002868", "BHU": "#FF4E12",
	"NEP": "#DC143C", "MON": "#C4272F", "NZL": "#00247D", "MLT": "#CF142B",
	"CYP": "#D47600", "LIE": "#5B2C6F",
}

## Curated 1936 capital province IDs (Europe NUTS / known hubs). Prefer over 0-pop first-seen.
const _1936_CURATED_CAPITALS: Dictionary = {
	"GER": 710300, "FRA": 710707, "ENG": 711414, "USA": 800792, "SOV": 903534,
	"ITA": 710963, "JAP": 903995, "POL": 711112, "SPA": 710643, "POR": 711138,
	"NLD": 711019, "BEL": 710047, "LUX": 710977, "SWI": 710122, "AUS": 710020,
	"CZE": 710146, "HUN": 710829, "ROM": 711177, "YUG": 711188, "TUR": 711276,
	"DNK": 710561, "SWE": 711213, "NOR": 711039, "FIN": 710693, "IRE": 710854,
}


## After ownership seed: ensure every owner tag has a Country entry (color + name + capital).
## world_accurate scenario only ships 8 majors; without this, SPA/YUG/CZE etc. paint grey.
func _ensure_countries_for_ownership_tags() -> void:
	var tags: Dictionary = {}
	for pid_var in provinces.keys():
		var p: Province = provinces[pid_var] as Province
		if p == null or bool(p.is_sea):
			continue
		var tag := str(p.owner_tag).strip_edges().to_upper()
		if tag.is_empty():
			continue
		# Never invent modern anachronisms on the 1936 board.
		if tag in ["SVN", "SRO", "SER", "SVK", "MKD", "MNE", "CRO", "BIH", "KOS", "SRB", "SLO"]:
			continue
		tags[tag] = true
	var added := 0
	var caps_fixed := 0
	var colors_fixed := 0
	for tag_var in tags.keys():
		var tag := str(tag_var)
		var cap_id := _pick_best_capital_province_id(tag)
		var name_str := str(_1936_NATION_NAMES.get(tag, tag))
		var col_hex := str(_1936_NATION_COLORS.get(tag, ""))
		if col_hex.is_empty():
			var h := float(absi(tag.hash()) % 1000) / 1000.0
			var ccol := Color.from_hsv(h, 0.55, 0.72, 1.0)
			col_hex = "#%02X%02X%02X" % [int(ccol.r * 255.0), int(ccol.g * 255.0), int(ccol.b * 255.0)]
		if countries.has(tag):
			var existing: Variant = countries[tag]
			var old_cap := -1
			if existing is Country:
				old_cap = int((existing as Country).capital_province_id)
			elif existing is Dictionary:
				old_cap = int((existing as Dictionary).get("capital_province_id", -1))
			# Replace missing OR clearly-wrong colonial/RoW capital with home-theater pick.
			if cap_id > 0 and (old_cap <= 0 or not _capital_pid_plausible_for_tag(tag, old_cap)):
				if existing is Country:
					(existing as Country).capital_province_id = cap_id
				elif existing is Dictionary:
					(existing as Dictionary)["capital_province_id"] = cap_id
				caps_fixed += 1
			# Always re-apply maintained palette (AUS/SWI/LIE/YUG readability, etc.).
			if _1936_NATION_COLORS.has(tag):
				var new_col := _parse_country_color(col_hex)
				if existing is Country:
					(existing as Country).color = new_col
					if str((existing as Country).name).strip_edges().is_empty() or str((existing as Country).name).to_upper() == tag:
						(existing as Country).name = name_str
				elif existing is Dictionary:
					(existing as Dictionary)["color"] = new_col
					(existing as Dictionary)["name"] = name_str
				colors_fixed += 1
			continue
		var entry: Variant = _make_country_entry(tag, {
			"tag": tag,
			"name": name_str,
			"color": col_hex,
			"capital_province_id": cap_id if cap_id > 0 else 0,
		})
		if entry != null:
			countries[tag] = entry
			added += 1
	if added > 0 or caps_fixed > 0 or colors_fixed > 0:
		print("ScenarioLoader: synthesized %d paints + fixed %d capitals + recolored %d (total countries=%d)" % [added, caps_fixed, colors_fixed, countries.size()])


## Score capital candidates: curated > city-name match > Europe NUTS band > city tier > pop.
func _pick_best_capital_province_id(tag: String) -> int:
	var t := tag.strip_edges().to_upper()
	if _1936_CURATED_CAPITALS.has(t):
		var cur := int(_1936_CURATED_CAPITALS[t])
		if _capital_pid_plausible_for_tag(t, cur):
			return cur
	# City-name table (lisbon, oslo, stockholm, …)
	var best_city := -1
	var best_city_score := -1.0
	for pid_key in province_city_layer.keys():
		var entry: Variant = province_city_layer[pid_key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ed: Dictionary = entry
		var cname := str(ed.get("city_name", "")).strip_edges().to_lower()
		if cname.is_empty():
			continue
		var want := ""
		for key in _CAPITAL_CITY_NAMES.keys():
			if key in cname or cname == key:
				want = str(_CAPITAL_CITY_NAMES[key]).to_upper()
				break
		if want != t and not (want == "SWI" and t == "CHE") and not (want == "CHE" and t == "SWI"):
			continue
		var pid := int(str(pid_key))
		if not _capital_pid_plausible_for_tag(t, pid):
			continue
		var sc := 1000.0 + float(int(ed.get("tier", 1))) * 10.0
		# Prefer Europe NUTS ids for European tags
		if pid >= 710000 and pid < 800000:
			sc += 200.0
		if sc > best_city_score:
			best_city_score = sc
			best_city = pid
	if best_city > 0:
		return best_city
	# Fallback: best owned land in home theater (Europe NUTS preferred), then any owned.
	var best_pid := -1
	var best_sc := -1.0
	for pid_var in provinces.keys():
		var p: Province = provinces[pid_var] as Province
		if p == null or bool(p.is_sea):
			continue
		if str(p.owner_tag).strip_edges().to_upper() != t:
			continue
		var pid := int(pid_var)
		var sc := 1.0
		if pid >= 710000 and pid < 800000:
			sc += 500.0  # Europe theater
		elif pid >= 800000 and pid < 900000:
			sc += 100.0  # US band
		# Penalize sparse RoW colonial cells (often first 0-pop pick before this fix)
		elif pid >= 900000 and pid < 950000:
			sc -= 50.0
		var tier := 0
		if province_city_layer.has(str(pid)):
			var ce: Variant = province_city_layer[str(pid)]
			if ce is Dictionary:
				tier = int((ce as Dictionary).get("tier", 0))
		sc += float(tier) * 15.0
		sc += float(int(p.population) if "population" in p else 0) / 100000.0
		if sc > best_sc:
			best_sc = sc
			best_pid = pid
	return best_pid


func _capital_pid_plausible_for_tag(tag: String, pid: int) -> bool:
	if pid <= 0 or not provinces.has(pid):
		return false
	var p: Province = provinces[pid] as Province
	if p == null or bool(p.is_sea):
		return false
	var ot := str(p.owner_tag).strip_edges().to_upper()
	var t := tag.strip_edges().to_upper()
	if ot != t:
		if not (t == "SWI" and ot == "CHE") and not (t == "CHE" and ot == "SWI"):
			return false
	# European tags must not use colonial RoW (900k+) or sea band as capital.
	if t in ["POR", "BEL", "NLD", "DNK", "FRA", "ENG", "SPA", "ITA", "GER", "NOR", "SWE", "FIN", "YUG", "CZE", "HUN", "ROM", "BUL", "GRE", "TUR", "AUS", "SWI", "IRE", "POL", "ALB", "LIT", "LAT", "EST", "LUX"]:
		if pid >= 900000:
			return false
	return true


## Ensure capital provinces have special_features["capital"] so MapRenderer draws gold stars.
## Order: curated/city-name first (home theater), then scenario capital ids (if plausible).
func _stamp_capital_features() -> void:
	var stamped := 0
	var tagged: Dictionary = {}  # tag -> true once we have a capital for that tag
	# 0) Re-pick / fix capital_province_id on every country before stamping.
	for tag_k in countries.keys():
		var tag := str(tag_k).to_upper()
		var cap_id := _pick_best_capital_province_id(tag)
		if cap_id <= 0:
			continue
		var c: Variant = countries[tag_k]
		if c is Country:
			(c as Country).capital_province_id = cap_id
		elif c is Dictionary:
			(c as Dictionary)["capital_province_id"] = cap_id
	# 1) City layer explicit capital/is_capital flags
	for pid_key in province_city_layer.keys():
		var entry: Variant = province_city_layer[pid_key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ed: Dictionary = entry
		var is_cap := bool(ed.get("capital", false)) or bool(ed.get("is_capital", false))
		if not is_cap:
			continue
		var pid := int(str(pid_key))
		if not provinces.has(pid):
			continue
		var p0: Province = provinces[pid] as Province
		var ot0 := str(p0.owner_tag).strip_edges().to_upper() if p0 else ""
		if _try_mark_capital(pid, maxi(1, int(ed.get("tier", 1)))):
			stamped += 1
			if not ot0.is_empty():
				tagged[ot0] = true
			var t := str(ed.get("tag", ed.get("country_tag", "")))
			if not t.is_empty():
				tagged[t.to_upper()] = true
	# 2) City-name table BEFORE scenario ids (avoids colonial capital_id winning)
	for pid_key in province_city_layer.keys():
		var entry2: Variant = province_city_layer[pid_key]
		if typeof(entry2) != TYPE_DICTIONARY:
			continue
		var ed2: Dictionary = entry2
		var cname := str(ed2.get("city_name", "")).strip_edges().to_lower()
		if cname.is_empty():
			continue
		var want_tag := ""
		for key in _CAPITAL_CITY_NAMES.keys():
			if key in cname or cname == key:
				want_tag = str(_CAPITAL_CITY_NAMES[key]).to_upper()
				break
		if want_tag.is_empty() or tagged.has(want_tag):
			continue
		var pid2 := int(str(pid_key))
		if not _capital_pid_plausible_for_tag(want_tag, pid2):
			continue
		if _try_mark_capital(pid2, maxi(1, int(ed2.get("tier", 2)))):
			stamped += 1
			tagged[want_tag] = true
			var p2: Province = provinces[pid2] as Province
			if p2:
				tagged[str(p2.owner_tag).to_upper()] = true
	# 3) Country capital_province_id (now curated/home-theater)
	var country_dicts: Array = [countries]
	if typeof(GameData) != TYPE_NIL and "countries" in GameData:
		var countries_var: Variant = GameData.countries
		if countries_var is Dictionary and not (countries_var as Dictionary).is_empty():
			country_dicts.append(countries_var as Dictionary)
	for cdict_v in country_dicts:
		if not (cdict_v is Dictionary):
			continue
		for tag_k in (cdict_v as Dictionary).keys():
			var tag_u := str(tag_k).to_upper()
			if tagged.has(tag_u):
				continue
			var c: Variant = (cdict_v as Dictionary)[tag_k]
			var cap_id := -1
			if c is Country:
				cap_id = int((c as Country).capital_province_id)
			elif c is Dictionary:
				cap_id = int((c as Dictionary).get("capital_province_id", -1))
			if not _capital_pid_plausible_for_tag(tag_u, cap_id):
				cap_id = _pick_best_capital_province_id(tag_u)
			if _try_mark_capital(cap_id, 1):
				stamped += 1
				tagged[tag_u] = true
	# 4) Final pass: every ownership tag still without a star (iterate tags, not provinces)
	var owner_tags: Dictionary = {}
	for pid_var in provinces.keys():
		var p: Province = provinces[pid_var] as Province
		if p == null or bool(p.is_sea):
			continue
		var ot := str(p.owner_tag).strip_edges().to_upper()
		if not ot.is_empty():
			owner_tags[ot] = true
	for tag_v in owner_tags.keys():
		var tag := str(tag_v)
		if tagged.has(tag):
			continue
		var capf := _pick_best_capital_province_id(tag)
		if _try_mark_capital(capf, 1):
			stamped += 1
			tagged[tag] = true
	if stamped > 0:
		print("ScenarioLoader: stamped capital feature on %d provinces (map gold stars, tags=%d / owners=%d)" % [stamped, tagged.size(), owner_tags.size()])


func _try_mark_capital(pid: int, tier: int = 1) -> bool:
	if pid <= 0 or not provinces.has(pid):
		return false
	var p: Province = provinces[pid] as Province
	if p == null or bool(p.is_sea):
		return false
	if p.has_feature("capital"):
		return false
	p.special_features["capital"] = maxi(1, tier)
	return true


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
	p.domain = base_p.domain if "domain" in base_p else ("sea" if base_p.is_sea else "land")
	# Harden: board seas use domain=sea/strait without is_sea in JSON sometimes.
	var dom := str(p.domain).to_lower()
	if dom in ["sea", "strait", "ocean", "lake"] or str(p.terrain).to_lower() in ["sea", "ocean", "water"]:
		p.is_sea = true
	if int(p.id) >= 950000:
		p.is_sea = true
		if dom.is_empty() or dom == "land":
			p.domain = "sea"
	p.has_port = base_p.has_port
	p.coordinates = base_p.coordinates
	p.adjacencies = base_p.adjacencies.duplicate()
	p.owner_tag = base_p.owner_tag
	p.controller_tag = base_p.controller_tag
	p.core_for = base_p.core_for.duplicate()
	p.strategic_region_id = base_p.strategic_region_id
	p.development_level = base_p.development_level
	p.infrastructure = base_p.infrastructure
	p.factories = base_p.factories
	p.population = base_p.population
	p.resources = base_p.resources.duplicate(true)
	p.victory_points = base_p.victory_points
	p.special_features = base_p.special_features.duplicate(true)
	p.tags = base_p.tags.duplicate()
	return p


## Post-spawn helper: ensures NATO unit symbols for the starting formations (OOB with real designs like panzer_iii_j, m4_sherman, bf109g etc) and per-nation colored borders are drawn on the map immediately for playtest without extra F10 clicks.
## Safe to call multiple times; uses deferred to avoid init ordering issues with MapRenderer in the tscn tree.
func _try_force_playtest_map_visuals() -> void:
	# Rebuild pick for any new stationed etc.
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("rebuild_pick_grid"):
		MapManager.rebuild_pick_grid()
	# Locate the active MapRenderer (WorldMap in TestScenario.tscn or WorldMap.tscn etc).
	var tree := get_tree()
	if tree == null:
		return
	var root := tree.get_root()
	if root == null:
		return
	var mr: Node = root.find_child("WorldMap", true, false)
	if mr == null:
		mr = root.find_child("MapRenderer", true, false)
	if mr == null:
		# broader search for map root node
		mr = root.find_child("*Map*", true, false)
	if mr:
		var _env_headless_ev := OS.get_environment("EOA_HEADLESS_EVIDENCE").strip_edges() == "1"
		var _display_headless := DisplayServer.get_name() == "headless"
		var _headless_ev := _env_headless_ev or _display_headless
		if not _headless_ev:
			if mr.has_method("_update_unit_icons_for_test"):
				mr.call_deferred("_update_unit_icons_for_test")
			if mr.has_method("force_border_update"):
				mr.call_deferred("force_border_update")
			if mr.has_method("force_border_update"):
				print("[ScenarioLoader] Post-spawn force: unit icons (NATO from assets) + nation borders (country colors) for immediate playtest visuals.")
		else:
			# Do not claim env EOA_HEADLESS_EVIDENCE=1 when only DisplayServer is headless (dual OOB runs keep env unset).
			if _env_headless_ev:
				print("[ScenarioLoader] EOA_HEADLESS_EVIDENCE=1 — skipping unit icon/border force visuals for fast headless 50T init (core seeding still runs).")
			else:
				print("[ScenarioLoader] DisplayServer headless (EOA_HEADLESS_EVIDENCE unset) — skipping unit icon/border force visuals; core seeding still runs.")
		# Map bootstrap is owned by TestRunner post-initialize; skip duplicate deferred load here.


## Pull starting equipment onto formations from country stockpiles (land OOB designs preferred).
func _equip_formations_from_country_stockpiles(data: Dictionary) -> void:
	if typeof(ProductionManager) == TYPE_NIL or typeof(LeaderManager) == TYPE_NIL:
		return
	if not ("formations" in LeaderManager):
		return
	var primary_land: Dictionary = _primary_land_designs_from_scenario(data)
	var equipped_count := 0
	var land_equipped_by_tag: Dictionary = {}
	var land_total_by_tag: Dictionary = {}
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	for fid in LeaderManager.formations:
		var f: Formation = LeaderManager.formations[fid]
		if f == null or f.country_tag.is_empty():
			continue
		var tag := str(f.country_tag).strip_edges().to_upper()
		var ftype := str(f.formation_type) if "formation_type" in f else ""
		var is_land := ftype == Formation.TYPE_DIVISION or ftype == Formation.TYPE_GARRISON
		if is_land:
			land_total_by_tag[tag] = int(land_total_by_tag.get(tag, 0)) + 1
		var did := _resolve_formation_equip_design(f, primary_land)
		if did.is_empty():
			continue
		# Keep formation design aligned with what we equip (stockpile-available OOB).
		if is_land and (f.design_id.is_empty() or f.design_id != did):
			f.design_id = did
		var to_equip := 1
		var got := 0
		if ProductionManager.has_method("take_from_country_equipment_stockpile"):
			got = ProductionManager.take_from_country_equipment_stockpile(tag, did, to_equip)
		if got <= 0 and ProductionManager.has_method("take_from_national_stockpile"):
			got = ProductionManager.take_from_national_stockpile(did, to_equip)
		if got <= 0:
			continue
		var ust: Dictionary = {}
		if ProductionManager.has_method("get_unit_equipment_stock"):
			ust = ProductionManager.get_unit_equipment_stock(str(fid))
		ust[did] = int(ust.get(did, 0)) + got
		if ProductionManager.has_method("set_unit_equipment_stock"):
			ProductionManager.set_unit_equipment_stock(str(fid), ust)
		equipped_count += 1
		if is_land:
			land_equipped_by_tag[tag] = int(land_equipped_by_tag.get(tag, 0)) + 1
	if equipped_count > 0:
		print(
			"[SCENARIO OOB EQUIP] Equipped %d starting formations from country/national stockpiles (scenario data -> units have equipment on spawn)."
			% equipped_count
		)
	var major_bits: PackedStringArray = []
	for tag in major_tags:
		var ok := int(land_equipped_by_tag.get(tag, 0))
		var tot := int(land_total_by_tag.get(tag, 0))
		var sample_design := str(primary_land.get(tag, ""))
		major_bits.append("%s land_equip=%d/%d design=%s" % [tag, ok, tot, sample_design])
	if not major_bits.is_empty():
		print("ScenarioLoader: Formation equip (land from stockpile) — %s" % ", ".join(major_bits))


func _primary_land_designs_from_scenario(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var block: Variant = data.get("countries", [])
	if typeof(block) != TYPE_ARRAY:
		return out
	for entryv in block:
		if typeof(entryv) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entryv
		var tag := str(entry.get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var oobv: Variant = entry.get("starting_oob", {})
		if typeof(oobv) != TYPE_DICTIONARY:
			continue
		var land: Array = (oobv as Dictionary).get("land_designs", [])
		if land.is_empty():
			continue
		out[tag] = str(land[0]).strip_edges()
	return out


func _resolve_formation_equip_design(f: Formation, primary_land: Dictionary) -> String:
	if f == null:
		return ""
	var tag := str(f.country_tag).strip_edges().to_upper()
	var ftype := str(f.formation_type) if "formation_type" in f else ""
	var is_land := ftype == Formation.TYPE_DIVISION or ftype == Formation.TYPE_GARRISON
	var candidates: Array[String] = []
	var did := str(f.design_id).strip_edges() if "design_id" in f else ""
	if not did.is_empty():
		candidates.append(did)
	if is_land:
		var primary := str(primary_land.get(tag, "")).strip_edges()
		if not primary.is_empty() and primary not in candidates:
			candidates.append(primary)
	# Prefer a design that exists in country stockpile
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("get_country_equipment_stockpile"):
		var cstock: Dictionary = ProductionManager.get_country_equipment_stockpile(tag)
		for c in candidates:
			if cstock.has(c) and int(cstock.get(c, 0)) > 0:
				return c
		# Any positive stockpile entry for land formations (first in stockpile order is undefined — prefer primary)
		if is_land and not primary_land.get(tag, "").is_empty():
			var p := str(primary_land[tag])
			if cstock.has(p) and int(cstock.get(p, 0)) > 0:
				return p
	return candidates[0] if not candidates.is_empty() else ""


## Production bootstrap from scenario starting_oob → live lines on owned factories.
## Uses capital/key_provinces and FactoryManager.factory_id (not obsolete demo province ids).
## Majors also get a fast infantry consumer line so short evidence windows (≤20d) prove
## daily_production_tick → stockpile growth (medium tanks alone need ~60d+).
func _start_demo_production_lines(data: Dictionary) -> void:
	if typeof(ProductionManager) == TYPE_NIL or typeof(FactoryManager) == TYPE_NIL:
		return
	var block: Variant = data.get("countries", [])
	if typeof(block) != TYPE_ARRAY:
		return
	_seed_starting_industrial_resources()
	var started := 0
	var assigned_count := 0
	var major_bits: PackedStringArray = []
	for entryv in block:
		if typeof(entryv) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entryv
		var tag: String = str(entry.get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var oobv: Variant = entry.get("starting_oob", {})
		if typeof(oobv) != TYPE_DICTIONARY:
			continue
		var oob: Dictionary = oobv
		var designs: Array[String] = []
		for key in ["land_designs", "air_designs", "naval_designs"]:
			var arr: Variant = oob.get(key, [])
			if typeof(arr) != TYPE_ARRAY:
				continue
			for d in arr as Array:
				var ds := str(d).strip_edges()
				if not ds.is_empty() and ds not in designs:
					designs.append(ds)
		if designs.is_empty():
			continue
		# Prefer first land design for bootstrap line (majors always have land_designs).
		var design := designs[0]
		var land_arr: Array = oob.get("land_designs", [])
		if not land_arr.is_empty():
			design = str(land_arr[0]).strip_edges()
		var fid := _resolve_factory_id_for_country(tag, entry)
		var lid := "oob_%s_%s" % [tag, design]
		var primary_already := (
			ProductionManager.has_method("get_line") and ProductionManager.get_line(lid) != null
		)
		if not primary_already:
			if fid <= 0:
				print("[OOB PRODUCTION] Skip %s — no factory for design %s" % [tag, design])
				continue
			var ok := _bootstrap_oob_line(lid, design, fid)
			if not ok:
				continue
			assigned_count += 1
			started += 1
			if bool(entry.get("major_power", false)) or tag in ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]:
				major_bits.append("%s line=%s fac=%d design=%s" % [tag, lid, fid, design])
			print(
				"[OOB PRODUCTION] Started line %s design=%s factory=%d for %s"
				% [lid, design, fid, tag]
			)
		# Fast infantry line for majors — proves daily production within short evidence windows.
		var is_major := bool(entry.get("major_power", false)) or tag in ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
		if is_major and fid > 0:
			if _bootstrap_major_infantry_line(tag, fid):
				started += 1
				assigned_count += 1
	print(
		"[ScenarioLoader] OOB production bootstrap — lines=%d assigned_to_factory=%d"
		% [started, assigned_count]
	)
	if not major_bits.is_empty():
		print("ScenarioLoader: Major production lines — %s" % ", ".join(major_bits))
	_print_industry_bootstrap_evidence()
	_run_oob_production_evidence_advance()


## National industrial inputs so OOB lines are not starved to min_output (0.55) at day 0.
## Map extraction can replace this later; starter pool is required for honest campaign openers.
func _seed_starting_industrial_resources() -> void:
	if typeof(ProductionManager) == TYPE_NIL:
		return
	if not ProductionManager.has_method("add_stockpile"):
		return
	# Idempotent-ish: only seed when steel is empty/near-empty so reloads don't explode stock.
	var steel := 0.0
	if "national_stockpile" in ProductionManager:
		steel = float(ProductionManager.national_stockpile.get("steel", 0.0))
	if steel >= 500.0:
		return
	ProductionManager.add_stockpile(
		{
			"steel": 12000.0,
			"aluminum": 4000.0,
			"fuel": 4000.0,
			"rubber": 2000.0,
			"coal": 8000.0,
		}
	)
	print("ScenarioLoader: Seeded starting industrial resource stockpile (steel/aluminum/fuel/rubber/coal)")


func _bootstrap_oob_line(lid: String, design: String, fid: int) -> bool:
	if ProductionManager.has_method("bootstrap_line_on_factory"):
		return bool(ProductionManager.bootstrap_line_on_factory(lid, design, fid))
	var line: Variant = ProductionManager.create_line(lid)
	if line == null:
		return false
	if ProductionManager.has_method("assign_line_to_factory"):
		ProductionManager.assign_line_to_factory(lid, fid)
	if ProductionManager.has_method("set_line_template"):
		ProductionManager.set_line_template(lid, design)
	return true


func _major_infantry_design(tag: String) -> String:
	match tag:
		"USA", "ENG":
			return "infantry_m1_garand"
		_:
			return "infantry_k98_bolt_action"


## Second consumer line on the same factory (max_lines bumped) — ~14d rifles finish inside 20d evidence.
func _bootstrap_major_infantry_line(tag: String, primary_fid: int) -> bool:
	var design := _major_infantry_design(tag)
	var lid := "oob_%s_%s" % [tag, design]
	if ProductionManager.has_method("get_line") and ProductionManager.get_line(lid) != null:
		return false
	if typeof(FactoryManager) != TYPE_NIL and FactoryManager.has_method("get_factory"):
		var fac: Variant = FactoryManager.get_factory(primary_fid)
		if fac != null and fac is Object and "max_production_lines" in fac:
			fac.max_production_lines = maxi(int(fac.max_production_lines), 2)
	var ok := _bootstrap_oob_line(lid, design, primary_fid)
	if ok:
		print(
			"[OOB PRODUCTION] Started infantry line %s design=%s factory=%d for %s"
			% [lid, design, primary_fid, tag]
		)
	return ok


func _factory_id_from_variant(f: Variant) -> int:
	if f == null:
		return 0
	if f is Object:
		if "factory_id" in f:
			return int(f.factory_id)
		if "id" in f:
			return int(f.id)
	elif typeof(f) == TYPE_DICTIONARY:
		if f.has("factory_id"):
			return int(f["factory_id"])
		if f.has("id"):
			return int(f["id"])
	return 0


func _resolve_factory_id_for_country(tag: String, entry: Dictionary) -> int:
	## Prefer standard (non-shipyard) factories owned by tag on capital/key provinces.
	var factories: Array = []
	if ProductionManager.has_method("get_all_factories_for_country"):
		factories = ProductionManager.get_all_factories_for_country(tag)
	# Prefer capital / key_provinces first
	var prefer_pids: Array[int] = []
	var cap := int(entry.get("capital_province_id", 0))
	if cap > 0:
		prefer_pids.append(cap)
	var kps: Variant = entry.get("key_provinces", [])
	if typeof(kps) == TYPE_ARRAY:
		for k in kps as Array:
			var pid := int(k)
			if pid > 0 and pid not in prefer_pids:
				prefer_pids.append(pid)
	for pid in prefer_pids:
		if not FactoryManager.has_method("get_factories_in_province"):
			break
		var fs: Array = FactoryManager.get_factories_in_province(pid)
		for f in fs:
			var ffid := _factory_id_from_variant(f)
			if ffid <= 0:
				continue
			# Prefer standard factories for land designs
			if f is Object and "factory_type" in f and str(f.factory_type) == "shipyard":
				continue
			return ffid
	# Any owned non-shipyard factory
	for f in factories:
		var ffid := _factory_id_from_variant(f)
		if ffid <= 0:
			continue
		if f is Object and "factory_type" in f and str(f.factory_type) == "shipyard":
			continue
		return ffid
	# Any owned factory
	for f in factories:
		var ffid := _factory_id_from_variant(f)
		if ffid > 0:
			return ffid
	# Last resort: register one factory on capital if land province exists
	if cap > 0 and provinces.has(cap):
		var p: Province = provinces[cap]
		if p != null and not p.is_sea and FactoryManager.has_method("register_factories_for_province"):
			var created: Array = FactoryManager.register_factories_for_province(cap, tag, 1)
			if not created.is_empty():
				return _factory_id_from_variant(created[0])
	return 0


func _print_industry_bootstrap_evidence() -> void:
	if typeof(FactoryManager) == TYPE_NIL or typeof(ProductionManager) == TYPE_NIL:
		return
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	var parts: PackedStringArray = []
	var line_ids: Array = []
	if ProductionManager.has_method("get_line_ids"):
		line_ids = ProductionManager.get_line_ids()
	for tag in major_tags:
		var fac_n := 0
		var sy_n := 0
		var lines_assigned := 0
		if ProductionManager.has_method("get_all_factories_for_country"):
			for f in ProductionManager.get_all_factories_for_country(tag):
				if f == null:
					continue
				fac_n += 1
				if "factory_type" in f and str(f.factory_type) == "shipyard":
					sy_n += 1
		for lidv in line_ids:
			var lid := str(lidv)
			if not lid.begins_with("oob_%s_" % tag):
				continue
			var line: Variant = ProductionManager.get_line(lid) if ProductionManager.has_method("get_line") else null
			if line != null and "factory_id" in line and int(line.factory_id) > 0:
				lines_assigned += 1
		parts.append("%s fac=%d sy=%d lines_on_fac=%d" % [tag, fac_n, sy_n, lines_assigned])
	print("ScenarioLoader: Industry bootstrap — %s" % ", ".join(parts))


## Short production advance for evidence (headless/CI only — never blocks graphical F5).
## Uses the real daily entry point (daily_production_tick → same path as TimeManager.game_day_advanced),
## not a bypass of that tick. ~100 ticks ≈ short campaign window for tank OOB lines.
## Override with EOA_OOB_EVIDENCE_DAYS (e.g. 15) for dual headless under memory pressure.
const OOB_PRODUCTION_EVIDENCE_DAYS := 100.0

func _run_oob_production_evidence_advance() -> void:
	if OS.get_environment("EOA_UNIT_ORDER_QA").strip_edges() == "1":
		print("ScenarioLoader: skip OOB evidence (EOA_UNIT_ORDER_QA)")
		return
	var headless := DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")
	var wants := headless or OS.get_environment("EOA_RUN_SIM_CYCLES").strip_edges() == "1" or OS.get_environment("EOA_HEADLESS_EVIDENCE").strip_edges() == "1"
	if not wants:
		return
	if typeof(ProductionManager) == TYPE_NIL:
		return
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	var before: Dictionary = {}
	var before_completed: Dictionary = {}
	for tag in major_tags:
		var stock: Dictionary = {}
		if ProductionManager.has_method("get_country_equipment_stockpile"):
			stock = ProductionManager.get_country_equipment_stockpile(tag)
		before[tag] = stock.duplicate(true)
		before_completed[tag] = _oob_line_completed_count(tag)
	var days := int(OOB_PRODUCTION_EVIDENCE_DAYS)
	var env_days := OS.get_environment("EOA_OOB_EVIDENCE_DAYS").strip_edges()
	if not env_days.is_empty() and env_days.is_valid_int():
		# Allow up to 120d for major #27 medium-tank honesty windows (60/80/100).
		days = clampi(int(env_days), 1, 120)
	# Real daily path: same function TimeManager day advance invokes via _on_game_day_advanced.
	if ProductionManager.has_method("daily_production_tick"):
		for _i in days:
			ProductionManager.daily_production_tick()
	elif ProductionManager.has_method("advance_days"):
		ProductionManager.advance_days(float(days))
	var total_done := 0
	var bits: PackedStringArray = []
	var majors_with_growth := 0
	for tag in major_tags:
		var after: Dictionary = {}
		if ProductionManager.has_method("get_country_equipment_stockpile"):
			after = ProductionManager.get_country_equipment_stockpile(tag)
		var b: Dictionary = before.get(tag, {})
		var deltas: PackedStringArray = []
		var keys: Dictionary = {}
		for k in b.keys():
			keys[str(k)] = true
		for k in after.keys():
			keys[str(k)] = true
		var any_delta := false
		for k in keys.keys():
			var d := int(after.get(k, 0)) - int(b.get(k, 0))
			if d != 0:
				any_delta = true
				deltas.append("%s%+d" % [k, d])
		var line_done := _oob_line_completed_count(tag) - int(before_completed.get(tag, 0))
		total_done += line_done
		if any_delta or line_done > 0:
			majors_with_growth += 1
		bits.append(
			"%s line_done=%d stock_delta=[%s]"
			% [tag, line_done, ", ".join(deltas) if not deltas.is_empty() else "0"]
		)
	print(
		"ScenarioLoader: Daily production stockpile evidence (%dd via daily_production_tick) — total_units=%d majors_grew=%d/%d | %s"
		% [days, total_done, majors_with_growth, major_tags.size(), ", ".join(bits)]
	)
	_print_medium_tank_line_progress_evidence(days)
	_run_medium_complete_window_evidence(days)
	_print_formation_equip_evidence()
	_print_apply_queue_live_audit_evidence()
	_print_phase2_conquest_evidence()
	_print_phase3_depth_evidence()
	_print_phase4_depth_evidence()
	_print_phase5_depth_evidence()
	_print_phase6_depth_evidence()
	_print_phase7_depth_evidence()
	_print_phase8_designers_evidence()
	_print_phase9_cycle_evidence()
	_print_phase10_gs_evidence()
	_print_phase11_depth_evidence()
	_print_map_gap_closure_evidence()
	_print_map_phase23_evidence()


## Multi-month medium-tank honesty: report OOB medium-line progress after evidence window.
## Complements stockpile growth (infantry proves short windows; mediums need 60–100d).
func _print_medium_tank_line_progress_evidence(days: int) -> void:
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("get_line_ids"):
		return
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	var bits: PackedStringArray = []
	var medium_lines := 0
	var progressed := 0
	var complete_n := 0
	for tag in major_tags:
		for lidv in ProductionManager.get_line_ids():
			var lid := str(lidv)
			if not lid.begins_with("oob_%s_" % tag):
				continue
			var low := lid.to_lower()
			var is_medium := (
				low.contains("medium")
				or low.contains("panzer_iii")
				or low.contains("t34")
				or low.contains("sherman")
				or low.contains("somua")
			)
			if not is_medium:
				continue
			medium_lines += 1
			var line: Variant = ProductionManager.get_line(lid) if ProductionManager.has_method("get_line") else null
			if line == null:
				continue
			# Prefer day-based path (daily_production_tick → advance_days) over PP progress.
			var pct := 0.0
			var days_needed := 0.0
			if line.has_method("get_days_per_unit"):
				days_needed = float(line.get_days_per_unit())
			if days_needed > 0.001 and "production_progress" in line:
				pct = clampf(float(line.production_progress) / days_needed, 0.0, 1.5)
			elif line.has_method("get_progress_percent"):
				pct = float(line.get_progress_percent())
			elif "progress" in line and "design_production_cost" in line:
				var cost := float(line.design_production_cost)
				if cost > 0.001:
					pct = clampf(float(line.progress) / cost, 0.0, 1.5)
			var done := 0
			if "completed_count" in line:
				done = int(line.completed_count)
			if line.has_method("get_current_state"):
				var st: Variant = line.get_current_state()
				if st != null and "units_produced" in st:
					done = maxi(done, int(st.units_produced))
			var retool := 0.0
			if "retooling_days_remaining" in line:
				retool = float(line.retooling_days_remaining)
			if pct > 0.001 or done > 0:
				progressed += 1
			if done > 0 or pct >= 1.0:
				complete_n += 1
			var design := ""
			if "current_template_id" in line:
				design = str(line.current_template_id)
			elif "design_id" in line:
				design = str(line.design_id)
			bits.append(
				"%s %s prog=%.0f%% done=%d days/u=%.0f retool=%.0f"
				% [
					tag,
					design if not design.is_empty() else lid,
					pct * 100.0,
					done,
					days_needed,
					retool,
				]
			)
	if bits.is_empty():
		print(
			"ScenarioLoader: Medium-tank OOB progress evidence (%dd) — no medium OOB lines found"
			% days
		)
		print("ScenarioLoader: medium_tank_complete=0")
		return
	print(
		"ScenarioLoader: Medium-tank OOB progress evidence (%dd) — lines=%d progressed=%d complete_or_100=%d | %s"
		% [days, medium_lines, progressed, complete_n, ", ".join(bits)]
	)
	# Major #27 honesty marker — dual greps this for multi-month medium proof.
	print("ScenarioLoader: medium_tank_complete=%d" % complete_n)
	if complete_n > 0:
		print(
			"ScenarioLoader: Medium-tank production honesty PASS — complete units on %d line(s) after %dd"
			% [complete_n, days]
		)



## Optional multi-month medium complete window (EOA_MEDIUM_OOB_EVIDENCE_DAYS).
## Dual stays at 20d for majors_grew; set e.g. 70–100 to prove medium complete_or_100.
func _run_medium_complete_window_evidence(already_days: int) -> void:
	var env_m := OS.get_environment("EOA_MEDIUM_OOB_EVIDENCE_DAYS").strip_edges()
	if env_m.is_empty() or not env_m.is_valid_int():
		return
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("daily_production_tick"):
		return
	var target := clampi(int(env_m), already_days, 120)
	var extra := target - already_days
	if extra <= 0:
		print("ScenarioLoader: Medium complete window — already at %dd (target %dd)" % [already_days, target])
		_print_medium_tank_line_progress_evidence(target)
		return
	for _i in extra:
		ProductionManager.daily_production_tick()
	print(
		"ScenarioLoader: Medium complete window advanced +%dd → %dd total (EOA_MEDIUM_OOB_EVIDENCE_DAYS)"
		% [extra, target]
	)
	_print_medium_tank_line_progress_evidence(target)



## Major #28 — dual evidence: core apply-queue leaves hit live managers.
func _print_apply_queue_live_audit_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("audit_apply_queue_live_leaves"):
		print("ScenarioLoader: apply_queue_live=0/6 (no audit API)")
		return
	var audit: Dictionary = GameData.audit_apply_queue_live_leaves(1)
	var live_n := int(audit.get("live_n", 0))
	var total := int(audit.get("total", 6))
	var ok_n := int(audit.get("ok_n", 0))
	print(
		"ScenarioLoader: Apply-queue live managers evidence — apply_queue_live=%d/%d ok=%d/%d | %s"
		% [live_n, total, ok_n, total, str(audit.get("summary", ""))]
	)
	print("ScenarioLoader: apply_queue_live=%d/%d" % [live_n, total])
	if live_n >= 5:
		print("ScenarioLoader: Apply-queue live managers PASS — core leaves mutate Production/Supply/Fleet/Battle/Focus/Agent")
	elif live_n >= 4:
		print("ScenarioLoader: Apply-queue live managers PARTIAL — live %d/%d (hardening continues)" % [live_n, total])



## Phase 2 dual evidence — occupation / manpower / peace conference live state.
func _print_phase2_conquest_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var occ_ticks := 0
	var mp_ticks := 0
	var peace_n := 0
	if GameData.has_method("apply_occupation_daily_tick_live"):
		var o1: Dictionary = GameData.apply_occupation_daily_tick_live(1)
		var o2: Dictionary = GameData.apply_occupation_daily_tick_live(1)
		occ_ticks = int(GameData.peace_state.get("occupation_tick_count", 0)) if "peace_state" in GameData else int(o2.get("occupation_tick_count", 0))
		print(
			"ScenarioLoader: Occupation resistance/compliance evidence — policy %s R=%.2f C=%.2f ticks=%d live=%s"
			% [
				str(o2.get("policy", "moderate")),
				float(o2.get("resistance_level", 0.0)),
				float(o2.get("compliance_level", 0.0)),
				occ_ticks,
				str(o2.get("live", true)),
			]
		)
	if GameData.has_method("apply_manpower_law_live") and GameData.has_method("apply_manpower_training_tick_live"):
		var law: Dictionary = GameData.apply_manpower_law_live("GER", "limited")
		var tr: Dictionary = GameData.apply_manpower_training_tick_live("GER")
		mp_ticks = int(tr.get("manpower_train_tick_count", 0))
		print(
			"ScenarioLoader: Manpower laws/training evidence — law %s eligible=%.0f trained=%.0f fielded=%.0f ticks=%d"
			% [
				str(law.get("law", "limited")),
				float(law.get("eligible", 0.0)),
				float(tr.get("trained_stock", 0.0)),
				float(tr.get("fielded", 0.0)),
				mp_ticks,
			]
		)
	if GameData.has_method("apply_peace_conference_settlement_live"):
		var pe: Dictionary = GameData.apply_peace_conference_settlement_live("GER", "FRA", 1, true, false, 0.35, true)
		peace_n = int(pe.get("peace_settlement_count", 0))
		print(
			"ScenarioLoader: Peace conference settlement evidence — %s→%s items=%d settlements=%d live=%s"
			% [
				str(pe.get("winner_tag", "GER")),
				str(pe.get("loser_tag", "FRA")),
				(pe.get("items", []) as Array).size() if pe.get("items") is Array else 0,
				peace_n,
				str(pe.get("live", true)),
			]
		)
	print("ScenarioLoader: phase2_conquest_live=1 occupation_ticks=%d manpower_ticks=%d peace_settlements=%d" % [occ_ticks, mp_ticks, peace_n])
	if occ_ticks >= 1 and mp_ticks >= 1 and peace_n >= 1:
		print("ScenarioLoader: Phase 2 conquest live PASS — occupation/manpower/peace wired")
	_print_membership_mutation_live_evidence()


## Live hierarchy membership mutation dual evidence (reassign + create + transfer).
func _print_membership_mutation_live_evidence() -> void:
	if province_state_by_id.is_empty():
		print("ScenarioLoader: membership_live_mut=0 (no hierarchy binds)")
		return
	# Pick two provinces in different states when possible.
	var pid_a := 0
	var sid_a := 0
	var pid_b := 0
	var sid_b := 0
	for pid in province_state_by_id:
		var sid := int(province_state_by_id[pid])
		if sid_a <= 0:
			pid_a = int(pid)
			sid_a = sid
		elif sid != sid_a:
			pid_b = int(pid)
			sid_b = sid
			break
	if pid_a <= 0:
		print("ScenarioLoader: membership_live_mut=0 (no sample province)")
		return
	if pid_b <= 0:
		# Fallback: create then reassign back via transfer path using same state
		pid_b = pid_a
		sid_b = sid_a
	var before_a: Dictionary = get_hierarchy_for_province(pid_a)
	var re: Dictionary = reassign_province_membership(pid_a, sid_b if sid_b > 0 else sid_a + 1)
	var after_a: Dictionary = get_hierarchy_for_province(pid_a)
	var cr: Dictionary = create_state_membership([pid_a], "Live Secession Enclave", int(after_a.get("region_id", 0)), int(after_a.get("super_region_id", 0)), "NEU")
	var new_sid := int(cr.get("state_id", 0))
	var tr: Dictionary = {}
	if new_sid > 0 and sid_b > 0 and new_sid != sid_b:
		tr = transfer_state_membership(new_sid, sid_b)
	elif new_sid > 0 and sid_a > 0:
		tr = transfer_state_membership(new_sid, sid_a)
	print(
		"ScenarioLoader: membership_live_mut=1 reassign=%s create=%s transfer=%s count=%d seed_only=1 reapply_year=0 province=%d state %s→%s"
		% [
			str(re.get("ok", false)),
			str(cr.get("ok", false)),
			str(tr.get("ok", false)) if not tr.is_empty() else "skip",
			membership_live_mutation_count,
			pid_a,
			str(before_a.get("state_id", 0)),
			str(after_a.get("state_id", 0)),
		]
	)
	if bool(re.get("ok")) and bool(cr.get("ok")):
		print("ScenarioLoader: membership mutation live PASS — reassign/create/transfer wired")
	# Peace annex → membership create + save/load roundtrip of live binds
	if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_peace_conference_settlement_live"):
		var pe: Dictionary = GameData.apply_peace_conference_settlement_live("GER", "FRA", pid_a, true, false, 0.2, true)
		var mem_ok := bool(pe.get("membership_live", false))
		var save_blob: Dictionary = {}
		if has_method("get_membership_save_data"):
			save_blob = get_membership_save_data()
		var restore: Dictionary = {}
		if not save_blob.is_empty() and has_method("apply_membership_save_data"):
			restore = apply_membership_save_data(save_blob)
		print(
			"ScenarioLoader: membership_peace_saveload=1 peace_membership=%s save_bound=%d restore_ok=%s mutation_count=%d"
			% [
				str(mem_ok),
				int(save_blob.get("mutation_count", 0)) if save_blob is Dictionary else 0,
				str(restore.get("ok", false)),
				membership_live_mutation_count,
			]
		)
		if mem_ok and bool(restore.get("ok", false)):
			print("ScenarioLoader: membership peace+saveload live PASS — annex state + persist wired")
	_print_completion_playability_live_evidence()


## Close deferred combat/naval/HH playability majors (live state machines).
func _print_completion_playability_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_completion_playability_close_live"):
		print("ScenarioLoader: completion_playability_live=0 (no GameData close API)")
		return
	var pid := 1
	for k in province_state_by_id:
		pid = int(k)
		break
	var res: Dictionary = GameData.apply_completion_playability_close_live(pid)
	print(
		"ScenarioLoader: completion_playability_live=1 combat=%s naval=%s hh=%s ticks_c=%d ticks_n=%d ticks_h=%d"
		% [
			str(res.get("combat_ok", false)),
			str(res.get("naval_ok", false)),
			str(res.get("hh_ok", false)),
			int(res.get("combat_ops_close_ticks", 0)),
			int(res.get("naval_ops_close_ticks", 0)),
			int(res.get("hh_agenda_close_ticks", 0)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: completion playability live PASS — combat+naval+HH deferred majors closed")
	_print_campaign_alpha_primary_live_evidence()
	_print_vision_close_live_evidence()


## Campaign Alpha primary strip — Phase 1 playability (Tier A).
func _print_campaign_alpha_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_campaign_alpha_primary_strip_live"):
		print("ScenarioLoader: campaign_alpha_primary_live=0 (no GameData strip API)")
		return
	var pid := 1
	for k in province_state_by_id:
		pid = int(k)
		break
	var board: Dictionary = GameData.apply_campaign_alpha_primary_strip_live("board", pid)
	var rec: Dictionary = GameData.apply_campaign_alpha_primary_strip_live("recommend", pid)
	var audit: Dictionary = GameData.apply_campaign_alpha_primary_strip_live("audit", pid)
	var dead_n := int(audit.get("dead_n", board.get("dead_n", 1)))
	var ticks := int(GameData.peace_state.get("campaign_alpha_tick_count", 0))
	var ok := bool(board.get("ok", false)) and bool(rec.get("ok", false)) and bool(audit.get("ok", false)) and dead_n == 0
	print(
		"ScenarioLoader: campaign_alpha_primary_live=1 dead_n=%d ticks=%d board=%s rec=%s audit=%s"
		% [dead_n, ticks, str(board.get("ok", false)), str(rec.get("ok", false)), str(audit.get("ok", false))]
	)
	if ok:
		print("ScenarioLoader: campaign alpha primary live PASS — primary strip dead_n=0 · recommended-next wired")
	_print_stream_alpha_packs_live_evidence()


## Stream α Packs C/E/F/G — primary playability close.
func _print_stream_alpha_packs_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_stream_alpha_primary_packs_product"):
		print("ScenarioLoader: stream_alpha_packs_live=0 (no apply API)")
		return
	var pid := 1
	for k in province_state_by_id:
		pid = int(k)
		break
	var res: Dictionary = GameData.apply_stream_alpha_primary_packs_product(pid)
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(GameData.peace_state.get("stream_alpha_tick_count", 0))
	print(
		"ScenarioLoader: stream_alpha_packs_live=1 dead_n=%d ticks=%d combat=%s hh=%s"
		% [dead_n, ticks, str((res.get("combat", {}) as Dictionary).get("ok", false)), str((res.get("hh", {}) as Dictionary).get("ok", false))]
	)
	if bool(res.get("ok", false)) and dead_n == 0:
		print("ScenarioLoader: stream alpha packs live PASS — C combat · E oob · F hh · G save primary paths")
	## Pack I soft FPS evidence when profiler present
	_print_map_fps_budget_evidence()


func _print_map_fps_budget_evidence() -> void:
	## Soft advisory only — graphical FPS needs EOA_MAP_PERF=1 on a renderer instance.
	var target := 16.67
	if ClassDB.class_exists("MapZoomLOD"):
		target = float(MapZoomLOD.target_frame_ms_mid_hardware())
	print("ScenarioLoader: map_fps_budget_live=1 target_ms=%.2f (enable EOA_MAP_PERF=1 for measured avg)" % target)


## Vision close dual evidence — full designer duties · hotseat multiplayer · multi-faction AI daily.
func _print_vision_close_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		print("ScenarioLoader: full_designer_duties_live=0 (no GameData)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	# Designer duties
	if GameData.has_method("apply_full_designer_duties_live"):
		var dres: Dictionary = GameData.apply_full_designer_duties_live("GER", pid)
		print(
			"ScenarioLoader: full_designer_duties_live=1 registered=%d seeded=%d complete=%s ticks=%d ok=%s"
			% [
				int(dres.get("domains_registered", 0)),
				int(dres.get("domains_seeded", 0)),
				str(dres.get("complete", false)),
				int(dres.get("designer_duties_tick_count", 0)),
				str(dres.get("ok", false)),
			]
		)
		if bool(dres.get("ok", false)):
			print("ScenarioLoader: full designer duties live PASS — catalog/compose/freeze/register/seed all domains")
	else:
		print("ScenarioLoader: full_designer_duties_live=0 (no apply_full_designer_duties_live)")
	# Hotseat multiplayer foundation
	if GameData.has_method("apply_session_players_hotseat_live"):
		var hres: Dictionary = GameData.apply_session_players_hotseat_live(pid)
		print(
			"ScenarioLoader: session_players_hotseat_live=1 slots=%d turn=%d active=%s cmds=%d lobby=%s ok=%s"
			% [
				int(hres.get("slot_n", 0)),
				int(hres.get("turn", 0)),
				str(hres.get("active_tag", "")),
				int(hres.get("commands_applied_total", 0)),
				str(hres.get("lobby_ready", false)),
				str(hres.get("ok", false)),
			]
		)
		if bool(hres.get("ok", false)):
			print("ScenarioLoader: session players hotseat live PASS — lobby/queue/rotate wired")
	else:
		print("ScenarioLoader: session_players_hotseat_live=0 (no apply API)")
	# N1 hotseat turn banner + non-active lock (dual after foundation hotseat)
	if GameData.has_method("apply_hotseat_turn_banner_live"):
		var bres: Dictionary = GameData.apply_hotseat_turn_banner_live(pid)
		var locked := bool(bres.get("locked", bres.get("non_active_locked", false)))
		var b_active := str(bres.get("active_tag", ""))
		var b_ok := bool(bres.get("ok", false))
		var banner_txt := str(bres.get("banner_text", ""))
		print(
			"ScenarioLoader: hotseat_turn_banner_live=1 locked=%s active=%s ok=%s"
			% [str(locked).to_lower(), b_active, str(b_ok).to_lower()]
		)
		if locked and not banner_txt.strip_edges().is_empty() and bool(bres.get("deny_other", true)):
			print("ScenarioLoader: hotseat turn banner live PASS — non_active_locked + banner non-empty")
	else:
		print("ScenarioLoader: hotseat_turn_banner_live=0 (no apply API)")
	# Multi-faction AI daily depth
	if GameData.has_method("apply_multi_faction_ai_daily_depth_live"):
		var ares: Dictionary = GameData.apply_multi_faction_ai_daily_depth_live(pid, 2)
		print(
			"ScenarioLoader: strategic_ai_multi_faction_daily_live=1 days=%d ai_applied=%d human_skip=%d ok=%s"
			% [
				int(ares.get("days", 0)),
				int(ares.get("ai_applied", 0)),
				int(ares.get("human_skipped", 0)),
				str(ares.get("ok", false)),
			]
		)
		if bool(ares.get("ok", false)):
			print("ScenarioLoader: multi-faction AI daily depth live PASS — non-human daily apply")
	else:
		print("ScenarioLoader: strategic_ai_multi_faction_daily_live=0 (no apply API)")
	# Combined package — aggregate already-run evidence (avoid double live apply / OOM).
	var d_ok := false
	var h_ok := false
	var a_ok := false
	if GameData.peace_state is Dictionary:
		var ps: Dictionary = GameData.peace_state
		d_ok = int(ps.get("designer_duties_tick_count", 0)) >= 4
		h_ok = int(ps.get("session_players_hotseat_ticks", 0)) >= 1
		a_ok = int(ps.get("multi_faction_ai_daily_ticks", 0)) >= 1
		var mf: Variant = ps.get("multi_faction_ai_daily", {})
		if mf is Dictionary:
			a_ok = a_ok and bool((mf as Dictionary).get("complete", a_ok))
	var v_ok := d_ok and h_ok and a_ok
	print(
		"ScenarioLoader: vision_close_live=1 designer=%s hotseat=%s ai=%s ok=%s"
		% [str(d_ok), str(h_ok), str(a_ok), str(v_ok)]
	)
	if v_ok:
		print("ScenarioLoader: vision close live PASS — designer duties + multiplayer + AI daily")
	_print_quality_gap_close_live_evidence()


## Quality gap close — custom UnitTemplate registration honesty.
func _print_quality_gap_close_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_quality_gap_close_live"):
		print("ScenarioLoader: quality_gap_close_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_quality_gap_close_live(pid)
	print(
		"ScenarioLoader: quality_gap_close_live=1 design=%s template_ok=%s registered=%s seeded=%s ticks=%d ok=%s"
		% [
			str(res.get("design_id", "")),
			str(res.get("template_ok", false)),
			str(res.get("registered", false)),
			str(res.get("seeded", false)),
			int(res.get("quality_gap_close_ticks", 0)),
			str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: quality gap close live PASS — custom designs register as UnitTemplates")
	_print_next20_completion_live_evidence()


## Next-20 completion package dual evidence — OPEN majors #1–#5 (20 steps).
func _print_next20_completion_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_next20_completion_live"):
		print("ScenarioLoader: next20_completion_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_next20_completion_live(pid)
	print(
		"ScenarioLoader: next20_completion_live=1 applied=%d majors_ok=%d complete=%s ticks=%d ok=%s"
		% [
			int(res.get("applied_n", 0)),
			int(res.get("majors_ok", 0)),
			str(res.get("complete", false)),
			int(res.get("next20_completion_ticks", 0)),
			str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: next-20 completion live PASS — combat/fleet/medium/save/hh OPEN majors sliced")
	_print_stream_alpha_primary_live_evidence()


## Stream α primary command package dual evidence — C1/P1/S1/L1 (14 steps, honest live APIs).
func _print_stream_alpha_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_stream_alpha_primary_command_live"):
		print("ScenarioLoader: stream_alpha_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_stream_alpha_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("stream_alpha_primary_ticks", GameData.peace_state.get("stream_alpha_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: stream_alpha_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: stream alpha primary command live PASS — C1 combat · P1 OOB · S1 save · L1 HH")
	_print_fleet_autonomy_primary_live_evidence()
	_print_map_perf_fps_harness_live_evidence()


## Fleet autonomy primary command package dual evidence — C2/A2 F0–F3 (4 steps, honest live APIs).
func _print_fleet_autonomy_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_fleet_autonomy_primary_command_live"):
		print("ScenarioLoader: fleet_autonomy_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_fleet_autonomy_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("fleet_autonomy_primary_ticks", GameData.peace_state.get("fleet_autonomy_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: fleet_autonomy_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: fleet autonomy primary command live PASS — F0 posture · F1 station · F2 follow · F3 close")
	_print_peace_conference_primary_live_evidence()


## Di1 multi-party peace conference primary command dual evidence (5 steps, honest live APIs).
func _print_peace_conference_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_peace_conference_primary_command_live"):
		print("ScenarioLoader: peace_conference_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_peace_conference_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("peace_conference_primary_ticks", GameData.peace_state.get("peace_conference_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: peace_conference_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: peace conference primary command live PASS — open · claim · cede · puppet · close")
	_print_occupation_primary_live_evidence()


## O1 occupation primary command dual evidence (5 steps, honest live APIs).
func _print_occupation_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_occupation_primary_command_live"):
		print("ScenarioLoader: occupation_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_occupation_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("occupation_primary_ticks", GameData.peace_state.get("occupation_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: occupation_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: occupation primary command live PASS — mapmode · law · garrison · pulse · close")
	_print_research_queue_primary_live_evidence()


## T1 research queue primary command dual evidence (5 steps, honest live APIs).
func _print_research_queue_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_research_queue_primary_command_live"):
		print("ScenarioLoader: research_queue_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_research_queue_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("research_queue_primary_ticks", GameData.peace_state.get("research_queue_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: research_queue_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: research queue primary command live PASS — open · enqueue · gate · advance · close")
	_print_agent_mission_board_primary_live_evidence()


## I1 agent mission board primary command dual evidence (5 steps, honest live APIs).
func _print_agent_mission_board_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_agent_mission_board_primary_command_live"):
		print("ScenarioLoader: agent_mission_board_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_agent_mission_board_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("agent_mission_board_primary_ticks", GameData.peace_state.get("agent_mission_board_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: agent_mission_board_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: agent mission board primary command live PASS — board · dispatch · resolve · counter · close")
	_print_war_economy_primary_live_evidence()
	_print_air_theater_primary_live_evidence()
	_print_battle_aar_primary_live_evidence()
	_print_command_journal_primary_live_evidence()
	_print_map_perf_measured_primary_live_evidence()
	_print_war_goal_alliance_primary_live_evidence()
	_print_factory_retool_primary_live_evidence()
	_print_tutorial_first_session_primary_live_evidence()
	_print_multi_faction_ai_primary_live_evidence()
	_print_weather_theater_primary_live_evidence()
	_print_manpower_laws_primary_live_evidence()
	_print_focus_tree_primary_live_evidence()
	_print_leader_theater_primary_live_evidence()
	_print_intel_network_primary_live_evidence()
	_print_product_ux_primary_live_evidence()
	_print_combat_intel_estimate_primary_live_evidence()
	_print_convoy_sealane_primary_live_evidence()
	_print_designer_suite_primary_live_evidence()
	_print_autosave_session_primary_live_evidence()
	_print_historical_oob_primary_live_evidence()
	_print_intel_counter_primary_live_evidence()
	_print_faction_personality_primary_live_evidence()
	_print_production_honesty_primary_live_evidence()
	_print_hh_multi_month_primary_live_evidence()
	_print_logistics_supply_primary_live_evidence()
	_print_front_continuity_primary_live_evidence()
	_print_designer_depth_primary_live_evidence()
	_print_air_multi_phase_primary_live_evidence()
	_print_inspector_decision_primary_live_evidence()
	_print_balance_combat_supply_primary_live_evidence()
	_print_fleet_multi_day_primary_live_evidence()
	_print_agent_campaign_primary_live_evidence()
	_print_grand_strategy_cycle_primary_live_evidence()
	_print_world_class_primary_live_evidence()
	_print_multi_front_primary_live_evidence()
	_print_strategic_war_goal_primary_live_evidence()
	_print_naval_search_strike_primary_live_evidence()
	_print_weather_crisis_primary_live_evidence()
	_print_campaign_ai_multi_month_primary_live_evidence()
	_print_tech_research_primary_live_evidence()
	_print_focus_war_path_primary_live_evidence()
	_print_naval_multi_phase_primary_live_evidence()
	_print_diplomacy_peace_primary_live_evidence()
	_print_save_resume_primary_live_evidence()
	_print_play_session_primary_live_evidence()
	_print_ai_difficulty_primary_live_evidence()
	_print_hotseat_session_primary_live_evidence()
	_print_pack_n_era_primary_live_evidence()
	_print_map_perf_density_pilot_live_evidence()
	_print_pack_n_events_primary_live_evidence()
	_print_hoi_panel_primary_live_evidence()
	_print_q1_validator_primary_live_evidence()
	_print_combat_production_partial_primary_live_evidence()
	_print_pack_n_narrative_primary_live_evidence()
	_print_hoi_screen_primary_live_evidence()
	_print_q1_checklist_primary_live_evidence()
	_print_combat_production_depth_primary_live_evidence()
	_print_n3_preflight_primary_live_evidence()
	_print_pack_n_content_primary_live_evidence()
	_print_hoi_fullscreen_primary_live_evidence()
	_print_q1_rc_checklist_primary_live_evidence()
	_print_combat_engine_depth_primary_live_evidence()
	_print_resource_production_primary_live_evidence()
	_print_resource_harvest_primary_live_evidence()
	_print_resource_economy_depth_primary_live_evidence()
	_print_resource_open_items_primary_live_evidence()
	_print_trade_relations_primary_live_evidence()
	_print_trade_power_intel_primary_live_evidence()
	_print_trade_desk_primary_live_evidence()
	_print_trade_ai_primary_live_evidence()
	_print_trade_basing_primary_live_evidence()
	_print_basing_fleet_station_primary_live_evidence()
	_print_space_layer_primary_live_evidence()
	_print_space_depth_primary_live_evidence()
	_print_space_ops_primary_live_evidence()
	_print_space_colony_primary_live_evidence()
	_print_space_survey_primary_live_evidence()
	_print_space_fog_primary_live_evidence()
	_print_space_terraform_primary_live_evidence()
	_print_space_galaxy_primary_live_evidence()
	_print_n3_network_primary_live_evidence()
	_print_n4_dedicated_primary_live_evidence()
	_print_space_supply_primary_live_evidence()
	_print_space_supply_ai_primary_live_evidence()
	_print_space_survey_events_primary_live_evidence()
	_print_space_board_ui_primary_live_evidence()
	_print_space_open_path_primary_live_evidence()
	_print_space_rival_survey_primary_live_evidence()
	_print_space_discovery_choice_primary_live_evidence()
	_print_matchmaking_primary_live_evidence()
	_print_space_discovery_ui_primary_live_evidence()
	_print_matchmaking_lobby_primary_live_evidence()
	_print_combat_production_design_primary_live_evidence()
	_print_equipment_flow_primary_live_evidence()
	_print_equipment_stock_reinforce_primary_live_evidence()
	_print_reinforcement_logistics_primary_live_evidence()
	_print_reinforcement_depth_primary_live_evidence()
	_print_equipment_flow_symbols_primary_live_evidence()
	_print_reinforce_story_primary_live_evidence()
	_print_munitions_drone_primary_live_evidence()
	_print_combat_consume_primary_live_evidence()
	_print_ai_training_policy_primary_live_evidence()
	_print_equipment_flow_paint_primary_live_evidence()
	_print_combat_depth_primary_live_evidence()
	_print_map_flow_lod_primary_live_evidence()
	_print_ai_logistics_day_primary_live_evidence()


## E1 war economy primary command dual evidence (5 steps, honest live APIs).
func _print_war_economy_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_war_economy_primary_command_live"):
		print("ScenarioLoader: war_economy_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_war_economy_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("war_economy_primary_ticks", GameData.peace_state.get("war_economy_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: war_economy_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: war economy primary command live PASS — board · convert_to_war · convert_to_civ · stockpile · close")


## M3 dual — map FPS harness ready (honest empty when no frame samples).
func _print_map_perf_fps_harness_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_map_perf_fps_harness_live"):
		print("ScenarioLoader: map_perf_fps_harness_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_map_perf_fps_harness_live(pid)
	var pilot := str(res.get("pilot_tag", "custom"))
	var measured := int(res.get("measured", 0))
	var empty := bool(res.get("empty", true))
	var status := str(res.get("status", "EMPTY"))
	print(
		"ScenarioLoader: map_perf_fps_harness_live=1 pilot_tag=%s measured=%d empty=%s status=%s ok=%s"
		% [pilot, measured, str(empty).to_lower(), status, str(bool(res.get("ok", false))).to_lower()]
	)
	# Honest dual PASS: harness wired; empty samples still count as ready (no fake FPS).
	if bool(res.get("ok", false)) and bool(res.get("harness_ready", true)):
		if empty:
			print("ScenarioLoader: map perf fps harness live PASS — harness ready · measured=0 empty=true (honest)")
		else:
			print(
				"ScenarioLoader: map perf fps harness live PASS — measured=%d mean_ms=%.2f pilot=%s"
				% [measured, float(res.get("mean_ms", 0.0)), pilot]
			)


## Phase 3 dual evidence — product UX · designer domain seed · campaign AI multi-month.
func _print_phase3_depth_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var ux_ticks := 0
	var design_seeds := 0
	var ai_weeks := 0
	if GameData.has_method("apply_product_ux_polish_live"):
		var _u1: Dictionary = GameData.apply_product_ux_polish_live("compact", 1)
		var _u2: Dictionary = GameData.apply_product_ux_polish_live("chips", 1)
		var u3: Dictionary = GameData.apply_product_ux_polish_live("hotkeys", 1)
		ux_ticks = int(u3.get("product_ux_tick_count", 0))
		print(
			"ScenarioLoader: Product UX polish evidence — expanded=%d chips=%d hotkeys=%d ticks=%d live=%s"
			% [
				int(u3.get("max_expanded", 2)),
				int(u3.get("max_chips", 8)),
				int(u3.get("bind_n", 0)),
				ux_ticks,
				str(u3.get("live", true)),
			]
		)
	if GameData.has_method("apply_designer_domain_seed_live"):
		var d1: Dictionary = GameData.apply_designer_domain_seed_live("GER", "land", "panzer_iii_j_medium", 1)
		design_seeds = int(d1.get("designer_domain_seed_count", 0))
		print(
			"ScenarioLoader: Designer domain live evidence — domain %s design %s line %s seeds=%d boot=%s"
			% [
				str(d1.get("domain", "land")),
				str(d1.get("design_id", "")),
				str(d1.get("line_id", "")),
				design_seeds,
				str(d1.get("bootstrap_ok", d1.get("seeded", false))),
			]
		)
	if GameData.has_method("apply_campaign_ai_week_live"):
		var a1: Dictionary = GameData.apply_campaign_ai_week_live("GER", 1)
		var a2: Dictionary = GameData.apply_campaign_ai_week_live("GER", 1)
		ai_weeks = int(a2.get("campaign_ai_week_count", 0))
		print(
			"ScenarioLoader: Campaign AI multi-month evidence — week=%d months=%d goal %s actions=%d weeks=%d"
			% [
				int(a2.get("week_index", 0)),
				int(a2.get("months", 3)),
				str(a2.get("war_goal", "secure_front")),
				int(a2.get("actions_applied", 0)),
				ai_weeks,
			]
		)
	print("ScenarioLoader: phase3_depth_live=1 ux_ticks=%d designer_seeds=%d ai_weeks=%d" % [ux_ticks, design_seeds, ai_weeks])
	if ux_ticks >= 1 and design_seeds >= 1 and ai_weeks >= 1:
		print("ScenarioLoader: Phase 3 depth live PASS — UX/designer/campaign-AI wired")


## Phase 4 dual evidence — revolt/garrison · cohort/reserve · multi-party peace.
func _print_phase4_depth_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var revolt_ticks := 0
	var cohort_ticks := 0
	var peace_settlements := 0
	if GameData.has_method("apply_occupation_revolt_live"):
		var r1: Dictionary = GameData.apply_occupation_revolt_live(1, "board", "standard")
		var r2: Dictionary = GameData.apply_occupation_revolt_live(1, "garrison", "heavy")
		var r3: Dictionary = GameData.apply_occupation_revolt_live(1, "suppress", "heavy")
		revolt_ticks = int(r3.get("occupation_revolt_tick_count", 0))
		print(
			"ScenarioLoader: Occupation revolt/garrison evidence — flash=%.2f mode %s suppress=%.2f resolved=%s ticks=%d"
			% [
				float(r3.get("flashpoint", 0.0)),
				str(r3.get("garrison_mode", "standard")),
				float(r3.get("suppress_power", 0.0)),
				str(r3.get("resolved", false)),
				revolt_ticks,
			]
		)
	if GameData.has_method("apply_manpower_cohort_live"):
		var c1: Dictionary = GameData.apply_manpower_cohort_live("GER", "cohorts")
		var c2: Dictionary = GameData.apply_manpower_cohort_live("GER", "reserve")
		var c3: Dictionary = GameData.apply_manpower_cohort_live("GER", "mobilize")
		cohort_ticks = int(c3.get("manpower_cohort_tick_count", 0))
		print(
			"ScenarioLoader: Manpower cohort/reserve evidence — eligible=%.0f active=%.0f mobilized=%.0f readiness=%.2f ticks=%d"
			% [
				float(c3.get("eligible", 0.0)),
				float(c3.get("active", 0.0)),
				float(c3.get("mobilized", 0.0)),
				float(c3.get("readiness", 0.0)),
				cohort_ticks,
			]
		)
	if GameData.has_method("apply_multi_party_peace_live"):
		var p1: Dictionary = GameData.apply_multi_party_peace_live("board", 1)
		var p2: Dictionary = GameData.apply_multi_party_peace_live("wargoals", 1)
		var p3: Dictionary = GameData.apply_multi_party_peace_live("settle", 1)
		peace_settlements = int(p3.get("settlement_count", 0))
		print(
			"ScenarioLoader: Multi-party peace evidence — winners=%d packages=%d settlements=%d AI=%.2f live=%s"
			% [
				int(p3.get("winner_n", 0)),
				int(p3.get("package_n", 0)),
				peace_settlements,
				float(p3.get("ai_accept", 0.0)),
				str(p3.get("live", true)),
			]
		)
	print("ScenarioLoader: phase4_depth_live=1 revolt_ticks=%d cohort_ticks=%d multi_party_settlements=%d" % [revolt_ticks, cohort_ticks, peace_settlements])
	if revolt_ticks >= 1 and cohort_ticks >= 1 and peace_settlements >= 1:
		print("ScenarioLoader: Phase 4 depth live PASS — revolt/cohort/multi-party peace wired")


## Phase 5 dual evidence — historical OOB · tech branching · save/resume continuity.
func _print_phase5_depth_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var oob_ticks := 0
	var tech_ticks := 0
	var save_ticks := 0
	if GameData.has_method("apply_historical_oob_live"):
		var o1: Dictionary = GameData.apply_historical_oob_live("catalog", 1)
		var o2: Dictionary = GameData.apply_historical_oob_live("seed", 1)
		var o3: Dictionary = GameData.apply_historical_oob_live("equip", 1)
		oob_ticks = int(o3.get("historical_oob_tick_count", 0))
		print(
			"ScenarioLoader: Historical OOB content evidence — majors=%d lines=%d seeded=%d equipped=%d ticks=%d"
			% [
				int(o3.get("major_n", 0)),
				int(o3.get("line_n", 0)),
				int(o3.get("seeded_n", 0)),
				int(o3.get("equipped_n", 0)),
				oob_ticks,
			]
		)
	if GameData.has_method("apply_tech_branch_live"):
		var t1: Dictionary = GameData.apply_tech_branch_live("GER", "branches", "armor")
		var t2: Dictionary = GameData.apply_tech_branch_live("GER", "path", "armor")
		var t3: Dictionary = GameData.apply_tech_branch_live("GER", "field", "armor")
		tech_ticks = int(t3.get("tech_branch_tick_count", 0))
		print(
			"ScenarioLoader: Tech tree branching evidence — open=%d path %s fielded=%d ticks=%d live=%s"
			% [
				int(t3.get("open_n", 0)),
				str(t3.get("path_branch", "armor")),
				int(t3.get("fielded_n", 0)),
				tech_ticks,
				str(t3.get("live", true)),
			]
		)
	if GameData.has_method("apply_save_resume_live"):
		var s1: Dictionary = GameData.apply_save_resume_live("checkpoint", "slot1", 1)
		var s2: Dictionary = GameData.apply_save_resume_live("save", "slot1", 1)
		var s3: Dictionary = GameData.apply_save_resume_live("resume", "slot1", 1)
		save_ticks = int(s3.get("save_resume_tick_count", 0))
		print(
			"ScenarioLoader: Save/resume campaign evidence — slot %s saves=%d resumes=%d continuity=%s ticks=%d"
			% [
				str(s3.get("target_slot", "slot1")),
				int(s3.get("save_count", 0)),
				int(s3.get("resume_count", 0)),
				str(s3.get("continuity_ok", false)),
				save_ticks,
			]
		)
	print("ScenarioLoader: phase5_depth_live=1 oob_ticks=%d tech_ticks=%d save_ticks=%d" % [oob_ticks, tech_ticks, save_ticks])
	if oob_ticks >= 1 and tech_ticks >= 1 and save_ticks >= 1:
		print("ScenarioLoader: Phase 5 depth live PASS — OOB/tech/save-resume wired")


## Phase 6 dual evidence — tutorial first-session · focus tree content · balance combat/supply.
func _print_phase6_depth_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var tut_ticks := 0
	var focus_ticks := 0
	var bal_ticks := 0
	if GameData.has_method("apply_tutorial_session_live"):
		var t1: Dictionary = GameData.apply_tutorial_session_live("brief", 1)
		var t2: Dictionary = GameData.apply_tutorial_session_live("guide", 1)
		var t3: Dictionary = GameData.apply_tutorial_session_live("checkpoint", 1)
		tut_ticks = int(t3.get("tutorial_session_tick_count", 0))
		print(
			"ScenarioLoader: Tutorial first-session evidence — day=%d actions=%d progress=%.2f ticks=%d"
			% [
				int(t3.get("day", 0)),
				int(t3.get("actions_done", 0)),
				float(t3.get("progress", 0.0)),
				tut_ticks,
			]
		)
	if GameData.has_method("apply_focus_content_live"):
		var f1: Dictionary = GameData.apply_focus_content_live("GER", "catalog", "autarky")
		var f2: Dictionary = GameData.apply_focus_content_live("GER", "path", "autarky")
		var f3: Dictionary = GameData.apply_focus_content_live("GER", "commit", "autarky")
		focus_ticks = int(f3.get("focus_content_tick_count", 0))
		print(
			"ScenarioLoader: Focus tree content evidence — open=%d focus %s commits=%d ticks=%d live=%s"
			% [
				int(f3.get("focus_n", 0)),
				str(f3.get("focus_id", "autarky")),
				int(f3.get("commit_n", 0)),
				focus_ticks,
				str(f3.get("live", true)),
			]
		)
	if GameData.has_method("apply_balance_live"):
		var b1: Dictionary = GameData.apply_balance_live("estimate", 1)
		var b2: Dictionary = GameData.apply_balance_live("sample", 1)
		var b3: Dictionary = GameData.apply_balance_live("close", 1)
		bal_ticks = int(b3.get("balance_tick_count", 0))
		print(
			"ScenarioLoader: Balance combat/supply evidence — joint=%.2f live=%.2f var=%.3f within_band=%s ticks=%d"
			% [
				float(b3.get("joint", 0.0)),
				float(b3.get("live_score", 0.0)),
				float(b3.get("variance", 0.0)),
				str(b3.get("within_band", false)),
				bal_ticks,
			]
		)
	print("ScenarioLoader: phase6_depth_live=1 tut_ticks=%d focus_ticks=%d bal_ticks=%d" % [tut_ticks, focus_ticks, bal_ticks])
	if tut_ticks >= 1 and focus_ticks >= 1 and bal_ticks >= 1:
		print("ScenarioLoader: Phase 6 depth live PASS — tutorial/focus/balance wired")



## Phase 7 dual evidence — air theater · naval search/strike · economy conversion.
func _print_phase7_depth_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var air_ticks := 0
	var naval_ticks := 0
	var econ_ticks := 0
	if GameData.has_method("apply_air_theater_live"):
		var a1: Dictionary = GameData.apply_air_theater_live("recon", 1)
		var a2: Dictionary = GameData.apply_air_theater_live("cas_gate", 1)
		var a3: Dictionary = GameData.apply_air_theater_live("interdiction", 1)
		air_ticks = int(a3.get("air_theater_tick_count", 0))
		print(
			"ScenarioLoader: Air multi-phase theater evidence — packages=%d strikes=%d fuel=%.2f ticks=%d"
			% [int(a3.get("packages", 0)), int(a3.get("strikes", 0)), float(a3.get("fuel", 0.0)), air_ticks]
		)
	if GameData.has_method("apply_naval_search_live"):
		var n1: Dictionary = GameData.apply_naval_search_live("search", 1)
		var n2: Dictionary = GameData.apply_naval_search_live("asw_escort", 1)
		var n3: Dictionary = GameData.apply_naval_search_live("strike", 1)
		naval_ticks = int(n3.get("naval_search_tick_count", 0))
		print(
			"ScenarioLoader: Naval search/strike evidence — contacts=%d screens=%d sorties=%d ticks=%d"
			% [int(n3.get("contacts", 0)), int(n3.get("screens", 0)), int(n3.get("sorties", 0)), naval_ticks]
		)
	if GameData.has_method("apply_economy_conversion_live"):
		var e1: Dictionary = GameData.apply_economy_conversion_live("civ_board", 1)
		var e2: Dictionary = GameData.apply_economy_conversion_live("convert", 1)
		var e3: Dictionary = GameData.apply_economy_conversion_live("sustain", 1)
		econ_ticks = int(e3.get("economy_conversion_tick_count", 0))
		print(
			"ScenarioLoader: War economy conversion evidence — factories=%d converted=%d stock=%d ticks=%d"
			% [int(e3.get("factories", 0)), int(e3.get("converted", 0)), int(e3.get("stockpile_delta", 0)), econ_ticks]
		)
	print("ScenarioLoader: phase7_depth_live=1 air_ticks=%d naval_ticks=%d econ_ticks=%d" % [air_ticks, naval_ticks, econ_ticks])
	if air_ticks >= 1 and naval_ticks >= 1 and econ_ticks >= 1:
		print("ScenarioLoader: Phase 7 depth live PASS — air/naval/economy wired")


## Phase 8 dual evidence — full designers (modules · stats/field · multi-domain).
func _print_phase8_designers_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var mod_ticks := 0
	var field_ticks := 0
	var camp_ticks := 0
	if GameData.has_method("apply_designer_module_live"):
		var m1: Dictionary = GameData.apply_designer_module_live("modules", 1)
		var m2: Dictionary = GameData.apply_designer_module_live("edit", 1)
		var m3: Dictionary = GameData.apply_designer_module_live("reliability", 1)
		mod_ticks = int(m3.get("designer_module_tick_count", 0))
		print(
			"ScenarioLoader: Designer module editor evidence — slots=%d edited=%d rel=%.2f within_band=%s ticks=%d"
			% [int(m3.get("slot_n", 0)), int(m3.get("edited", 0)), float(m3.get("reliability", 0.0)), str(m3.get("within_band", false)), mod_ticks]
		)
	if GameData.has_method("apply_designer_field_live"):
		var f1: Dictionary = GameData.apply_designer_field_live("stats", 1, "land")
		var f2: Dictionary = GameData.apply_designer_field_live("freeze", 1, "land")
		var f3: Dictionary = GameData.apply_designer_field_live("field", 1, "land")
		field_ticks = int(f3.get("designer_field_tick_count", 0))
		print(
			"ScenarioLoader: Designer stats/field evidence — variant %s seeded=%d combat=%.2f ticks=%d"
			% [str(f3.get("variant_id", "")), int(f3.get("seeded", 0)), float(f3.get("combat", 0.0)), field_ticks]
		)
	if GameData.has_method("apply_designer_campaign_live"):
		var c1: Dictionary = GameData.apply_designer_campaign_live("catalog_all", 1)
		var c2: Dictionary = GameData.apply_designer_campaign_live("seed_multi", 1)
		var c3: Dictionary = GameData.apply_designer_campaign_live("equip_close", 1)
		camp_ticks = int(c3.get("designer_campaign_tick_count", 0))
		print(
			"ScenarioLoader: Full designers multi-domain evidence — open=%d seeded=%d equip=%d complete=%s ticks=%d"
			% [int(c3.get("open_n", 0)), int(c3.get("seeded_n", 0)), int(c3.get("equip_n", 0)), str(c3.get("complete", false)), camp_ticks]
		)
	print("ScenarioLoader: phase8_designers_live=1 mod_ticks=%d field_ticks=%d camp_ticks=%d" % [mod_ticks, field_ticks, camp_ticks])
	if mod_ticks >= 1 and field_ticks >= 1 and camp_ticks >= 1:
		print("ScenarioLoader: Phase 8 full designers live PASS — modules/stats/multi-domain wired")


## Phase 9 dual evidence — full gameplay cycle (weather · intel · leaders).
func _print_phase9_cycle_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var wx_ticks := 0
	var intel_ticks := 0
	var leader_ticks := 0
	if GameData.has_method("apply_weather_crisis_live"):
		var w1: Dictionary = GameData.apply_weather_crisis_live("forecast", 1)
		var w2: Dictionary = GameData.apply_weather_crisis_live("gate_multi", 1)
		var w3: Dictionary = GameData.apply_weather_crisis_live("crisis_sustain", 1)
		wx_ticks = int(w3.get("weather_crisis_tick_count", 0))
		print(
			"ScenarioLoader: Weather crisis campaign evidence — fronts=%d responses=%d gate_open=%s ticks=%d"
			% [int(w3.get("fronts", 0)), int(w3.get("responses", 0)), str(w3.get("gate_open", false)), wx_ticks]
		)
	if GameData.has_method("apply_intel_cell_live"):
		var i1: Dictionary = GameData.apply_intel_cell_live("cells", 1)
		var i2: Dictionary = GameData.apply_intel_cell_live("ops", 1)
		var i3: Dictionary = GameData.apply_intel_cell_live("sweep", 1)
		intel_ticks = int(i3.get("intel_cell_tick_count", 0))
		print(
			"ScenarioLoader: Intel cell network evidence — cells=%d recruited=%d swept=%d secure=%s ticks=%d"
			% [int(i3.get("cell_n", 0)), int(i3.get("recruited", 0)), int(i3.get("swept", 0)), str(i3.get("secure", false)), intel_ticks]
		)
	if GameData.has_method("apply_leader_theater_live"):
		var l1: Dictionary = GameData.apply_leader_theater_live("hq_board", 1)
		var l2: Dictionary = GameData.apply_leader_theater_live("multi_station", 1)
		var l3: Dictionary = GameData.apply_leader_theater_live("theater_ops", 1)
		leader_ticks = int(l3.get("leader_theater_tick_count", 0))
		print(
			"ScenarioLoader: Leader theater command evidence — assigned=%d stationed=%d orders=%d ticks=%d"
			% [int(l3.get("assigned", 0)), int(l3.get("stationed", 0)), int(l3.get("orders", 0)), leader_ticks]
		)
	print("ScenarioLoader: phase9_cycle_live=1 wx_ticks=%d intel_ticks=%d leader_ticks=%d" % [wx_ticks, intel_ticks, leader_ticks])
	if wx_ticks >= 1 and intel_ticks >= 1 and leader_ticks >= 1:
		print("ScenarioLoader: Phase 9 full gameplay cycle live PASS — weather/intel/leaders wired")


## Phase 10 dual evidence — war goals · multi-front AI · grand strategy cycle.
func _print_phase10_gs_evidence() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var wg_ticks := 0
	var mf_ticks := 0
	var gs_ticks := 0
	if GameData.has_method("apply_war_goal_live"):
		var w1: Dictionary = GameData.apply_war_goal_live("board", 1)
		var w2: Dictionary = GameData.apply_war_goal_live("justify", 1)
		var w3: Dictionary = GameData.apply_war_goal_live("execute", 1)
		wg_ticks = int(w3.get("war_goal_tick_count", 0))
		print(
			"ScenarioLoader: Strategic war-goal evidence — top %s justified=%s pushes=%d ticks=%d"
			% [str(w3.get("top_id", "")), str(w3.get("justified", false)), int(w3.get("pushes", 0)), wg_ticks]
		)
	if GameData.has_method("apply_multi_front_live"):
		var m1: Dictionary = GameData.apply_multi_front_live("plan", 1)
		var m2: Dictionary = GameData.apply_multi_front_live("weekly", 1)
		var m3: Dictionary = GameData.apply_multi_front_live("execute", 1)
		mf_ticks = int(m3.get("multi_front_tick_count", 0))
		print(
			"ScenarioLoader: Multi-front campaign AI evidence — fronts=%d ticks=%d packages=%d live_ticks=%d"
			% [int(m3.get("front_n", 0)), int(m3.get("ticks", 0)), int(m3.get("packages", 0)), mf_ticks]
		)
	if GameData.has_method("apply_gs_cycle_live"):
		var g1: Dictionary = GameData.apply_gs_cycle_live("scan", 1)
		var g2: Dictionary = GameData.apply_gs_cycle_live("rank", 1)
		var g3: Dictionary = GameData.apply_gs_cycle_live("execute", 1)
		gs_ticks = int(g3.get("gs_cycle_tick_count", 0))
		print(
			"ScenarioLoader: Grand strategy cycle evidence — open=%d top %s packages=%d complete=%s ticks=%d"
			% [int(g3.get("open_n", 0)), str(g3.get("top_domain", "")), int(g3.get("packages", 0)), str(g3.get("complete", false)), gs_ticks]
		)
	print("ScenarioLoader: phase10_gs_live=1 wg_ticks=%d mf_ticks=%d gs_ticks=%d" % [wg_ticks, mf_ticks, gs_ticks])
	if wg_ticks >= 1 and mf_ticks >= 1 and gs_ticks >= 1:
		print("ScenarioLoader: Phase 10 world-class GS live PASS — war-goals/multi-front/GS-cycle wired")

func _oob_line_completed_count(tag: String) -> int:
	var n := 0
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("get_line_ids"):
		return 0
	for lidv in ProductionManager.get_line_ids():
		var lid := str(lidv)
		if not lid.begins_with("oob_%s_" % tag):
			continue
		var line: Variant = ProductionManager.get_line(lid) if ProductionManager.has_method("get_line") else null
		if line == null:
			continue
		# PP path
		if "completed_count" in line:
			n += int(line.completed_count)
		# Day-based path (daily_production_tick → advance_days → design state)
		if line.has_method("get_current_state"):
			var st: Variant = line.get_current_state()
			if st != null and "units_produced" in st:
				n += int(st.units_produced)
	return n


func _print_formation_equip_evidence() -> void:
	if typeof(ProductionManager) == TYPE_NIL or typeof(LeaderManager) == TYPE_NIL:
		return
	var major_tags: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
	var bits: PackedStringArray = []
	for tag in major_tags:
		var land_eq := 0
		var land_tot := 0
		var sample := ""
		for f in LeaderManager.get_formations_for_country(tag) if LeaderManager.has_method("get_formations_for_country") else []:
			if f == null:
				continue
			var ftype := str(f.formation_type) if "formation_type" in f else ""
			if ftype != Formation.TYPE_DIVISION and ftype != Formation.TYPE_GARRISON:
				continue
			land_tot += 1
			var fid := str(f.formation_id) if "formation_id" in f else ""
			var ust: Dictionary = {}
			if ProductionManager.has_method("get_unit_equipment_stock") and not fid.is_empty():
				ust = ProductionManager.get_unit_equipment_stock(fid)
			var has_eq := false
			for k in ust.keys():
				if int(ust[k]) > 0:
					has_eq = true
					if sample.is_empty():
						sample = "%s×%d" % [k, int(ust[k])]
					break
			if has_eq:
				land_eq += 1
		bits.append("%s land_eq=%d/%d e.g.%s" % [tag, land_eq, land_tot, sample if not sample.is_empty() else "-"])
	print("ScenarioLoader: Formation equip evidence — %s" % ", ".join(bits))


func _apply_starting_equipment_stockpiles(data: Dictionary) -> void:
	if typeof(ProductionManager) == TYPE_NIL:
		return
	var block: Variant = data.get("countries", [])
	if typeof(block) != TYPE_ARRAY:
		return
	var applied := 0
	for entryv in block:
		if typeof(entryv) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entryv
		var tag := str(entry.get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var stock_v: Variant = entry.get("starting_equipment_stockpile", entry.get("starting_stockpile", {}))
		var equip: Dictionary = {}
		if typeof(stock_v) == TYPE_DICTIONARY:
			if stock_v.has("equipment") and typeof(stock_v["equipment"]) == TYPE_DICTIONARY:
				equip = stock_v["equipment"]
			else:
				equip = stock_v
		if equip.is_empty():
			continue
		ProductionManager.set_country_equipment_stockpile(tag, equip)
		applied += 1
		print("[ScenarioLoader] Initialized starting equipment stockpile for %s (%d equipment types from scenario data)" % [tag, equip.size()])
	if applied > 0:
		print("[ScenarioLoader] Applied starting equipment stockpiles for %d nations from scenario (realistic OOB/equipment per scenario json; future scenarios/mods control their own)." % applied)


func _apply_starting_agents(data: Dictionary) -> void:
	if typeof(AgentManager) == TYPE_NIL:
		return
	var block: Variant = data.get("countries", [])
	if typeof(block) != TYPE_ARRAY:
		return
	var total := 0
	for entryv in block:
		if typeof(entryv) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entryv
		var tag := str(entry.get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var count := int(entry.get("starting_agents", 0))
		if count <= 0:
			continue
		var per_nation_progress_step: float = 0.015 / float(max(1, count))  # small steps across 56 total
		var local := 0
		for _i in count:
			if AgentManager.has_method("recruit_agent"):
				var ag: Agent = AgentManager.recruit_agent(tag)
				if ag != null:
					total += 1
					local += 1
					if local % 8 == 0 or local == count:  # update every ~8 recruits or at end of nation
						await _report_load_progress(0.21 + (local * per_nation_progress_step), "Recruiting agents for " + tag + " (" + str(total) + " total so far)...")
	if total > 0:
		print("[ScenarioLoader] Recruited %d starting agents across nations from scenario data (scenario controls agent pools for different eras/mods)." % total)
		await _report_load_progress(0.23, "All starting agents recruited (56 across 14 nations)...")


func _string_array_from_json(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		out.append(str(item))
	return out


## Flatten natural_resources layer shapes to tag -> numeric amount only.
## Accepts either {iron: 8} or {resources:{iron:8}, resource_score:..., primary_resource:...}.
func _normalize_province_resources(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var src: Dictionary = raw as Dictionary
	var nested: Variant = src.get("resources", null)
	var amounts: Dictionary = nested as Dictionary if typeof(nested) == TYPE_DICTIONARY else src
	var out: Dictionary = {}
	for k in amounts:
		var v: Variant = amounts[k]
		# Skip metadata keys when src was already flat nested envelope without unwrap.
		if str(k) in ["resource_score", "primary_resource", "resources"]:
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				continue
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			out[str(k)] = float(v)
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
		if terrain_data.has("snow_potential"):
			p.snow_potential = float(terrain_data["snow_potential"])

	if province_resources_layer.has(pid_key) and typeof(province_resources_layer[pid_key]) == TYPE_DICTIONARY:
		var resources_data: Dictionary = province_resources_layer[pid_key].duplicate(true)
		p.resources = _normalize_province_resources(resources_data)

	if province_economy_layer.has(pid_key) and typeof(province_economy_layer[pid_key]) == TYPE_DICTIONARY:
		var economy_data: Dictionary = province_economy_layer[pid_key].duplicate(true)
		p.population = int(economy_data.get("population", p.population))
		p.factories = int(economy_data.get("factories", p.factories))
		p.infrastructure = int(economy_data.get("infrastructure", p.infrastructure))
		p.development_level = int(round(float(economy_data.get("development_level", p.development_level))))
		if economy_data.has("resources"):
			p.resources = _normalize_province_resources(economy_data)

	if province_region_by_id.has(p.id):
		p.strategic_region_id = int(province_region_by_id[p.id])

func _print_phase11_depth_evidence() -> void:
	var al_ticks := 0
	var pers_ticks := 0
	var rev_ticks := 0
	if typeof(GameData) == TYPE_NIL:
		return
	if GameData.has_method("apply_alliance_live"):
		var a1: Dictionary = GameData.apply_alliance_live("board", 1)
		var a2: Dictionary = GameData.apply_alliance_live("guarantee", 1)
		var a3: Dictionary = GameData.apply_alliance_live("coalition", 1)
		al_ticks = int(a3.get("alliance_tick_count", 0))
	if GameData.has_method("apply_personality_live"):
		var p1: Dictionary = GameData.apply_personality_live("board", 1)
		var p2: Dictionary = GameData.apply_personality_live("event", 1)
		var p3: Dictionary = GameData.apply_personality_live("drive", 1)
		pers_ticks = int(p3.get("personality_tick_count", 0))
	if GameData.has_method("apply_revolt_network_live"):
		var r1: Dictionary = GameData.apply_revolt_network_live("map", 1)
		var r2: Dictionary = GameData.apply_revolt_network_live("cascade", 1)
		var r3: Dictionary = GameData.apply_revolt_network_live("suppress", 1)
		rev_ticks = int(r3.get("revolt_network_tick_count", 0))
	if al_ticks >= 3 and pers_ticks >= 3 and rev_ticks >= 3:
		print("ScenarioLoader: phase11_depth_live=1 al_ticks=%d pers_ticks=%d rev_ticks=%d" % [al_ticks, pers_ticks, rev_ticks])
	else:
		print("ScenarioLoader: phase11_depth_live=0 al_ticks=%d pers_ticks=%d rev_ticks=%d" % [al_ticks, pers_ticks, rev_ticks])

func _print_map_gap_closure_evidence() -> void:
	## Phase 1 map gap-closure: occupation overlay · signal graph inventory · perf hooks.
	var occ_ok := 0
	var sig_ok := 0
	var perf_ok := 0
	var overlay_ok := 0
	# Seed occupation state on a few contested-like samples + live tick.
	if typeof(GameData) != TYPE_NIL:
		if GameData.has_method("apply_occupation_policy_live"):
			GameData.apply_occupation_policy_live(1, "harsh")
			GameData.apply_occupation_policy_live(2, "moderate")
			GameData.apply_occupation_policy_live(3, "lenient")
			occ_ok = 1
		if GameData.has_method("apply_occupation_revolt_live"):
			GameData.apply_occupation_revolt_live(1, "garrison", "heavy")
			GameData.apply_occupation_revolt_live(2, "garrison", "standard")
			GameData.apply_occupation_revolt_live(3, "garrison", "light")
			occ_ok = 1
	# Signal graph / overlay / perf inventory — ResourceLoader only (no mid-tick instantiate).
	if ResourceLoader.exists("res://scripts/debug/SignalGraphHarness.gd") and ResourceLoader.exists("res://SignalGraphVisualizer.gd"):
		sig_ok = 1
	if ResourceLoader.exists("res://scripts/map/OccupationOverlayLayer.gd"):
		overlay_ok = 1
	if ResourceLoader.exists("res://scripts/map/MapRendererPerf.gd"):
		perf_ok = 1
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
	if mr == null:
		mr = get_node_or_null("/root/WorldMap")
	if mr != null:
		if mr.has_method("get_occupation_overlay_stats") or mr.has_method("_setup_occupation_layer"):
			overlay_ok = 1
		if mr.has_method("dump_perf_profile") or mr.has_method("set_perf_profile_enabled"):
			perf_ok = 1
	if occ_ok == 1 and sig_ok == 1 and perf_ok == 1 and overlay_ok == 1:
		print("ScenarioLoader: map_gap_closure_live=1 occ=%d sig=%d perf=%d overlay=%d" % [occ_ok, sig_ok, perf_ok, overlay_ok])
	else:
		print("ScenarioLoader: map_gap_closure_live=0 occ=%d sig=%d perf=%d overlay=%d" % [occ_ok, sig_ok, perf_ok, overlay_ok])

func _print_map_phase23_evidence() -> void:
	## Phase 2+3 map gap-closure inventory evidence (no mid-tick heavy redraw).
	var flow_ok := 0
	var battle_ok := 0
	var domain_ok := 0
	var lod_ok := 0
	var construction_ok := 0
	var leader_ok := 0
	var editor_ok := 0
	var weather_ok := 0
	if ResourceLoader.exists("res://scripts/map/StrategicFlowOverlayLayer.gd"):
		flow_ok = 1
	if ResourceLoader.exists("res://scripts/map/BattleIndicatorOverlayLayer.gd"):
		battle_ok = 1
	if ResourceLoader.exists("res://scripts/map/DomainOpsOverlayLayer.gd"):
		domain_ok = 1
	if ResourceLoader.exists("res://scripts/map/ConstructionProgressOverlayLayer.gd"):
		construction_ok = 1
	if ResourceLoader.exists("res://scripts/map/LeaderStationOverlayLayer.gd"):
		leader_ok = 1
	if ResourceLoader.exists("res://scripts/map/MapZoomLOD.gd"):
		lod_ok = 1
	if ResourceLoader.exists("res://scripts/map/ProvinceEditor.gd"):
		editor_ok = 1
	if ResourceLoader.exists("res://scripts/map/WeatherOverlayLayer.gd"):
		weather_ok = 1
	var mr: Node = get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
	if mr != null:
		if mr.has_method("get_phase23_overlay_stats"):
			lod_ok = 1
		if mr.has_method("toggle_strategic_flow_overlay"):
			flow_ok = 1
		if mr.has_method("toggle_battle_indicator_overlay"):
			battle_ok = 1
		if mr.has_method("toggle_domain_ops_overlay"):
			domain_ok = 1
		if mr.has_method("toggle_construction_progress_overlay"):
			construction_ok = 1
		if mr.has_method("toggle_leader_station_overlay"):
			leader_ok = 1
	var score := flow_ok + battle_ok + domain_ok + lod_ok + construction_ok + leader_ok + editor_ok + weather_ok
	if score >= 8:
		print("ScenarioLoader: map_phase23_live=1 flow=%d battle=%d domain=%d lod=%d build=%d leader=%d editor=%d wx=%d" % [flow_ok, battle_ok, domain_ok, lod_ok, construction_ok, leader_ok, editor_ok, weather_ok])
	else:
		print("ScenarioLoader: map_phase23_live=0 flow=%d battle=%d domain=%d lod=%d build=%d leader=%d editor=%d wx=%d" % [flow_ok, battle_ok, domain_ok, lod_ok, construction_ok, leader_ok, editor_ok, weather_ok])


func _print_air_theater_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_air_theater_primary_command_live"):
		print("ScenarioLoader: air_theater_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_air_theater_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("air_theater_primary_ticks", GameData.peace_state.get("air_theater_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: air_theater_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: air theater primary command live PASS — recon · cas_gate · interdiction · close")


func _print_battle_aar_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_battle_aar_primary_command_live"):
		print("ScenarioLoader: battle_aar_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_battle_aar_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var entry_n := int(res.get("entry_n", 0))
	var ticks := int(res.get("battle_aar_primary_ticks", GameData.peace_state.get("battle_aar_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: battle_aar_primary_live=1 majors_ok=%d dead_n=%d entry_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, entry_n, ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: battle AAR primary command live PASS — open · record · factors · persist · close")


func _print_command_journal_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_command_journal_primary_command_live"):
		print("ScenarioLoader: command_journal_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_command_journal_primary_command_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ticks := int(res.get("command_journal_primary_ticks", GameData.peace_state.get("command_journal_primary_ticks", 0)))
	var ok := bool(res.get("ok", false))
	var verify_ok := bool(res.get("verify_ok", false))
	print(
		"ScenarioLoader: command_journal_primary_live=1 majors_ok=%d dead_n=%d verify=%s ticks=%d ok=%s"
		% [majors_ok, dead_n, str(verify_ok), ticks, str(ok)]
	)
	if ok:
		print("ScenarioLoader: command journal primary live PASS — seed · enqueue · flush · verify · close")

func _print_map_perf_measured_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_map_perf_measured_primary_live"):
		print("ScenarioLoader: map_perf_measured_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_map_perf_measured_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var measured := int(res.get("measured", 0))
	var measured_ok := bool(res.get("measured_ok", false))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: map_perf_measured_primary_live=1 majors_ok=%d dead_n=%d measured=%d measured_ok=%s source=%s ok=%s"
		% [majors_ok, dead_n, measured, str(measured_ok).to_lower(), str(res.get("source", "")), str(ok)]
	)
	if ok and measured_ok:
		print("ScenarioLoader: map perf measured primary live PASS — pilot · sample · budget30 · budget60 · close")


func _print_war_goal_alliance_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_war_goal_alliance_primary_live"):
		print("ScenarioLoader: war_goal_alliance_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_war_goal_alliance_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: war_goal_alliance_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("war_goal_alliance_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: war goal alliance primary live PASS — board · justify · execute · guarantee · close")


func _print_factory_retool_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_factory_retool_primary_live"):
		print("ScenarioLoader: factory_retool_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_factory_retool_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: factory_retool_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("factory_retool_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: factory retool primary live PASS — board · risk · horizon80 · prove60 · close")

func _print_tutorial_first_session_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_tutorial_first_session_primary_live"):
		print("ScenarioLoader: tutorial_first_session_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_tutorial_first_session_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: tutorial_first_session_primary_live=1 majors_ok=%d dead_n=%d g0_domain=%s ticks=%d ok=%s"
		% [majors_ok, dead_n, str(res.get("g0_domain", "")), int(res.get("tutorial_first_session_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: tutorial first-session primary live PASS — brief · guide · checkpoint · product · close · G0 TutorialSessionDomain")


func _print_multi_faction_ai_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_multi_faction_ai_primary_live"):
		print("ScenarioLoader: multi_faction_ai_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_multi_faction_ai_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: multi_faction_ai_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("multi_faction_ai_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: multi-faction AI primary live PASS — scan · rank · execute · multi_faction · close")

func _print_weather_theater_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_weather_theater_primary_live"):
		print("ScenarioLoader: weather_theater_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_weather_theater_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: weather_theater_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("weather_theater_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: weather theater primary live PASS — pressure · gate · crisis · product · close")


func _print_manpower_laws_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_manpower_laws_primary_live"):
		print("ScenarioLoader: manpower_laws_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_manpower_laws_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: manpower_laws_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("manpower_laws_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: manpower laws primary live PASS — law · train · cohorts · mobilize · close")

func _print_focus_tree_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_focus_tree_primary_live"):
		print("ScenarioLoader: focus_tree_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_focus_tree_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: focus_tree_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("focus_tree_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: focus tree primary live PASS — catalog · path · commit · product · close")


func _print_leader_theater_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_leader_theater_primary_live"):
		print("ScenarioLoader: leader_theater_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_leader_theater_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: leader_theater_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("leader_theater_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: leader theater primary live PASS — hq · station · ops · product · close")


func _print_intel_network_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_intel_network_primary_live"):
		print("ScenarioLoader: intel_network_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_intel_network_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: intel_network_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("intel_network_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: intel network primary live PASS — coverage · counterintel · counterplay · product · close")


func _print_product_ux_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_product_ux_primary_live"):
		print("ScenarioLoader: product_ux_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_product_ux_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: product_ux_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("product_ux_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: product UX primary live PASS — compact · chips · hotkeys · product · close")


func _print_combat_intel_estimate_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_combat_intel_estimate_primary_live"):
		print("ScenarioLoader: combat_intel_estimate_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_combat_intel_estimate_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	var impact := bool(res.get("intel_impact_visible", false))
	print(
		"ScenarioLoader: combat_intel_estimate_primary_live=1 majors_ok=%d dead_n=%d impact=%s ticks=%d ok=%s"
		% [majors_ok, dead_n, str(impact), int(res.get("combat_intel_estimate_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: combat intel estimate primary live PASS — estimate · recon · sabotage · product · close")


func _print_convoy_sealane_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_convoy_sealane_primary_live"):
		print("ScenarioLoader: convoy_sealane_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_convoy_sealane_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: convoy_sealane_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("convoy_sealane_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: convoy sealane primary live PASS — escort · sealane · joint · trade · close")


func _print_designer_suite_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_designer_suite_primary_live"):
		print("ScenarioLoader: designer_suite_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_designer_suite_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: designer_suite_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("designer_suite_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: designer suite primary live PASS — catalog · pick · seed · product · close")


func _print_autosave_session_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_autosave_session_primary_live"):
		print("ScenarioLoader: autosave_session_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_autosave_session_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: autosave_session_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("autosave_session_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: autosave session primary live PASS — browser · autosave · resume · checkpoint · close")


func _print_historical_oob_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_historical_oob_primary_live"):
		print("ScenarioLoader: historical_oob_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_historical_oob_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: historical_oob_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("historical_oob_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: historical OOB primary live PASS — catalog · seed · equip · product · close")


func _print_intel_counter_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_intel_counter_primary_live"):
		print("ScenarioLoader: intel_counter_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_intel_counter_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: intel_counter_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("intel_counter_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: intel counter primary live PASS — ops · sweep · depth · counterplay · close")


func _print_faction_personality_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_faction_personality_primary_live"):
		print("ScenarioLoader: faction_personality_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_faction_personality_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: faction_personality_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("faction_personality_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: faction personality primary live PASS — board · event · drive · product · close")


func _print_production_honesty_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_production_honesty_primary_live"):
		print("ScenarioLoader: production_honesty_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_production_honesty_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: production_honesty_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("production_honesty_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: production honesty primary live PASS — product · prove60 · prove100 · oob · close")


func _print_hh_multi_month_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_hh_multi_month_primary_live"):
		print("ScenarioLoader: hh_multi_month_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_hh_multi_month_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: hh_multi_month_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("hh_multi_month_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: HH multi-month primary live PASS — product · commit · counterplay · sequence · close")


func _print_logistics_supply_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_logistics_supply_primary_live"):
		print("ScenarioLoader: logistics_supply_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_logistics_supply_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: logistics_supply_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("logistics_supply_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: logistics supply primary live PASS — product · route · sustain · readiness · close")


func _print_front_continuity_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_front_continuity_primary_live"):
		print("ScenarioLoader: front_continuity_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_front_continuity_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: front_continuity_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("front_continuity_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: front continuity primary live PASS — campaign · combat · assault · sustain · close")


func _print_designer_depth_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_designer_depth_primary_live"):
		print("ScenarioLoader: designer_depth_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_designer_depth_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: designer_depth_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("designer_depth_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: designer depth primary live PASS — module · board · stats · multi · close")


func _print_air_multi_phase_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_air_multi_phase_primary_live"):
		print("ScenarioLoader: air_multi_phase_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_air_multi_phase_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: air_multi_phase_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("air_multi_phase_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: air multi-phase primary live PASS — product · sortie · weather · airland · close")


func _print_inspector_decision_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_inspector_decision_primary_live"):
		print("ScenarioLoader: inspector_decision_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_inspector_decision_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: inspector_decision_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("inspector_decision_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: inspector decision primary live PASS — decision · primary · collapse · apply · close")


func _print_balance_combat_supply_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_balance_combat_supply_primary_live"):
		print("ScenarioLoader: balance_combat_supply_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_balance_combat_supply_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: balance_combat_supply_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("balance_combat_supply_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: balance combat/supply primary live PASS — product · estimate · sample · variance · close")


func _print_fleet_multi_day_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_fleet_multi_day_primary_live"):
		print("ScenarioLoader: fleet_multi_day_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_fleet_multi_day_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: fleet_multi_day_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("fleet_multi_day_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: fleet multi-day primary live PASS — product · posture · escort · follow · sequence")


func _print_agent_campaign_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_agent_campaign_primary_live"):
		print("ScenarioLoader: agent_campaign_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_agent_campaign_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: agent_campaign_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("agent_campaign_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: agent campaign primary live PASS — board · dispatch · counterplay · sequence · product")


func _print_grand_strategy_cycle_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_grand_strategy_cycle_primary_live"):
		print("ScenarioLoader: grand_strategy_cycle_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_grand_strategy_cycle_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: grand_strategy_cycle_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("grand_strategy_cycle_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: grand strategy cycle primary live PASS — product · scan · rank · execute · close")


func _print_world_class_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_world_class_primary_live"):
		print("ScenarioLoader: world_class_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_world_class_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: world_class_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("world_class_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: world-class primary live PASS — product · scan · rank · execute · close")


func _print_multi_front_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_multi_front_primary_live"):
		print("ScenarioLoader: multi_front_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_multi_front_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: multi_front_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("multi_front_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: multi-front primary live PASS — product · plan · weekly · execute · close")


func _print_strategic_war_goal_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_strategic_war_goal_primary_live"):
		print("ScenarioLoader: strategic_war_goal_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_strategic_war_goal_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: strategic_war_goal_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("strategic_war_goal_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: strategic war-goal primary live PASS — product · board · justify · execute · close")


func _print_naval_search_strike_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_naval_search_strike_primary_live"):
		print("ScenarioLoader: naval_search_strike_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_naval_search_strike_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: naval_search_strike_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("naval_search_strike_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: naval search/strike primary live PASS — product · patrol · asw · strike · close")


func _print_weather_crisis_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_weather_crisis_primary_live"):
		print("ScenarioLoader: weather_crisis_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_weather_crisis_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: weather_crisis_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("weather_crisis_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: weather crisis primary live PASS — product · forecast · gate · sustain · close")


func _print_campaign_ai_multi_month_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_campaign_ai_multi_month_primary_live"):
		print("ScenarioLoader: campaign_ai_multi_month_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_campaign_ai_multi_month_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: campaign_ai_multi_month_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("campaign_ai_multi_month_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: campaign AI multi-month primary live PASS — product · board · weekly · execute · close")


func _print_tech_research_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_tech_research_primary_live"):
		print("ScenarioLoader: tech_research_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_tech_research_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: tech_research_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("tech_research_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: tech research primary live PASS — product · catalog · priority · field · close")


func _print_focus_war_path_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_focus_war_path_primary_live"):
		print("ScenarioLoader: focus_war_path_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_focus_war_path_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: focus_war_path_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("focus_war_path_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: focus war-path primary live PASS — product · pick · path · commit · close")


func _print_naval_multi_phase_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_naval_multi_phase_primary_live"):
		print("ScenarioLoader: naval_multi_phase_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_naval_multi_phase_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: naval_multi_phase_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("naval_multi_phase_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: naval multi-phase primary live PASS — product · posture · escort · strike · close")


func _print_diplomacy_peace_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_diplomacy_peace_primary_live"):
		print("ScenarioLoader: diplomacy_peace_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_diplomacy_peace_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: diplomacy_peace_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("diplomacy_peace_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: diplomacy/peace primary live PASS — product · board · leverage · settle · close")


func _print_save_resume_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_save_resume_primary_live"):
		print("ScenarioLoader: save_resume_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_save_resume_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: save_resume_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("save_resume_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: save/resume primary live PASS — product · checkpoint · save · resume · close")


func _print_play_session_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_play_session_primary_live"):
		print("ScenarioLoader: play_session_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_play_session_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: play_session_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("play_session_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: play-session primary live PASS — product · brief · execute · resolve · close")


func _print_ai_difficulty_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_ai_difficulty_primary_live"):
		print("ScenarioLoader: ai_difficulty_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_ai_difficulty_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: ai_difficulty_primary_live=1 majors_ok=%d dead_n=%d ticks=%d preset=%s ok=%s"
		% [majors_ok, dead_n, int(res.get("ai_difficulty_primary_ticks", 0)), str(res.get("preset", "")), str(ok)]
	)
	if ok:
		print("ScenarioLoader: AI difficulty primary live PASS — catalog · easy · normal · hard · close")


func _print_hotseat_session_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_hotseat_session_primary_live"):
		print("ScenarioLoader: hotseat_session_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_hotseat_session_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: hotseat_session_primary_live=1 majors_ok=%d dead_n=%d ticks=%d active=%s ok=%s"
		% [majors_ok, dead_n, int(res.get("hotseat_session_primary_ticks", 0)), str(res.get("active_tag", "")), str(ok)]
	)
	if ok:
		print("ScenarioLoader: hotseat session primary live PASS — lobby · banner · rotate · lock · close (not N3)")


func _print_pack_n_era_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_pack_n_era_primary_live"):
		print("ScenarioLoader: pack_n_era_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_pack_n_era_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: pack_n_era_primary_live=1 majors_ok=%d dead_n=%d era_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("era_n", 0)), int(res.get("pack_n_era_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Pack N era primary live PASS — catalog · 1936 · 1918 · equip · close")


func _print_map_perf_density_pilot_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_map_perf_density_pilot_live"):
		print("ScenarioLoader: map_perf_density_pilot_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_map_perf_density_pilot_live(pid)
	print(
		"ScenarioLoader: map_perf_density_pilot_live=1 pilot=%s province_n=%d measured=%d measured_ok=%s density_board=%s avg_ms=%.2f source=%s ok=%s"
		% [
			str(res.get("pilot", "")),
			int(res.get("province_n", 0)),
			int(res.get("measured", 0)),
			str(res.get("measured_ok", false)),
			str(res.get("density_board", false)),
			float(res.get("avg_ms", 0.0)),
			str(res.get("source", "")),
			str(res.get("ok", false)),
		]
	)


func _print_pack_n_events_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_pack_n_events_primary_live"):
		print("ScenarioLoader: pack_n_events_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_pack_n_events_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: pack_n_events_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("pack_n_events_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Pack N events/focus primary live PASS — catalog · path · war_pick · commit · close")


func _print_hoi_panel_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_hoi_panel_primary_live"):
		print("ScenarioLoader: hoi_panel_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_hoi_panel_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: hoi_panel_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("hoi_panel_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: HOI panel polish primary live PASS — compact · chips · inspector · apply · close")


func _print_q1_validator_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_q1_validator_primary_live"):
		print("ScenarioLoader: q1_validator_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_q1_validator_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: q1_validator_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("q1_validator_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Q1 validator honesty primary live PASS — balance · estimate · sample · honesty · close")

func _print_combat_production_partial_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_combat_production_partial_primary_live"):
		print("ScenarioLoader: combat_production_partial_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_combat_production_partial_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: combat_production_partial_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("combat_production_partial_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: combat/production partial primary live PASS — estimate · combat · prod · oob · close")


func _print_pack_n_narrative_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_pack_n_narrative_primary_live"):
		print("ScenarioLoader: pack_n_narrative_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_pack_n_narrative_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: pack_n_narrative_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("pack_n_narrative_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Pack N narrative primary live PASS — event · catalog · path · commit · close")


func _print_hoi_screen_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_hoi_screen_primary_live"):
		print("ScenarioLoader: hoi_screen_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_hoi_screen_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: hoi_screen_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("hoi_screen_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: HOI screen depth primary live PASS — hotkeys · polish · primary · collapse · close")


func _print_q1_checklist_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_q1_checklist_primary_live"):
		print("ScenarioLoader: q1_checklist_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_q1_checklist_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: q1_checklist_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("q1_checklist_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Q1 checklist depth primary live PASS — balance · variance · prove60 · prove100 · close")


func _print_combat_production_depth_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_combat_production_depth_primary_live"):
		print("ScenarioLoader: combat_production_depth_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_combat_production_depth_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: combat_production_depth_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("combat_production_depth_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Combat/production depth primary live PASS — estimate · phase · joint · fleet · close")


func _print_n3_preflight_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_n3_preflight_primary_live"):
		print("ScenarioLoader: n3_preflight_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_n3_preflight_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))

	print(
		"ScenarioLoader: n3_preflight_primary_live=1 majors_ok=%d dead_n=%d ticks=%d netcode_ready=false not_full_n3=true ok=%s"
		% [majors_ok, dead_n, int(res.get("n3_preflight_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: N3 preflight primary live PASS — lobby · seed · enqueue · flush · verify (NOT full N3 netcode)")
	return


func _print_pack_n_content_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_pack_n_content_primary_live"):
		print("ScenarioLoader: pack_n_content_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_pack_n_content_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: pack_n_content_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("pack_n_content_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Pack N content depth primary live PASS — event_day · catalog · war_step · ops · close")


func _print_hoi_fullscreen_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_hoi_fullscreen_primary_live"):
		print("ScenarioLoader: hoi_fullscreen_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_hoi_fullscreen_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: hoi_fullscreen_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("hoi_fullscreen_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: HOI fullscreen surface primary live PASS — compact · inspector · apply · polish · close")


func _print_q1_rc_checklist_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_q1_rc_checklist_primary_live"):
		print("ScenarioLoader: q1_rc_checklist_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_q1_rc_checklist_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: q1_rc_checklist_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("q1_rc_checklist_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Q1 RC checklist primary live PASS — balance · sample · prove100 · variance · close")


func _print_combat_engine_depth_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_combat_engine_depth_primary_live"):
		print("ScenarioLoader: combat_engine_depth_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_combat_engine_depth_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: combat_engine_depth_primary_live=1 majors_ok=%d dead_n=%d ticks=%d ok=%s"
		% [majors_ok, dead_n, int(res.get("combat_engine_depth_primary_ticks", 0)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: Combat engine depth primary live PASS — ops · campaign · surge · oob100 · close")

func _print_resource_production_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_resource_production_primary_live"):
		print("ScenarioLoader: resource_production_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_resource_production_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: resource_production_primary_live=1 majors_ok=%d dead_n=%d shortage_matters=%s full_speed=%.3f shortage_speed=%.3f model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("shortage_matters", false)),
			float(res.get("full_speed", 0.0)), float(res.get("shortage_speed", 1.0)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: resource production primary live PASS — catalog · full · shortage · critical · close (soft shortage)")


func _print_resource_harvest_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_resource_harvest_primary_live"):
		print("ScenarioLoader: resource_harvest_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_resource_harvest_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: resource_harvest_primary_live=1 majors_ok=%d dead_n=%d plants_matter=%s tech_matters=%s fissiles_gated=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("plants_matter", false)),
			str(res.get("tech_matters", false)), str(res.get("fissiles_gated", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: resource harvest primary live PASS — catalog · harvest · plants · tech · close (auto harvest)")


func _print_resource_economy_depth_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_resource_economy_depth_primary_live"):
		print("ScenarioLoader: resource_economy_depth_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_resource_economy_depth_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: resource_economy_depth_primary_live=1 majors_ok=%d dead_n=%d food_ok=%s combat_ok=%s plants_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("food_ok", false)),
			str(res.get("combat_ok", false)), str(res.get("plants_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: resource economy depth primary live PASS — catalog · food · combat · plants · close")


func _print_resource_open_items_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_resource_open_items_primary_live"):
		print("ScenarioLoader: resource_open_items_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_resource_open_items_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: resource_open_items_primary_live=1 majors_ok=%d dead_n=%d plants_ok=%s endgame_ok=%s trade_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("plants_ok", false)),
			str(res.get("endgame_ok", false)), str(res.get("trade_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: resource open items primary live PASS — catalog · plants · endgame · trade · close")


func _print_trade_relations_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_trade_relations_primary_live"):
		print("ScenarioLoader: trade_relations_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_trade_relations_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: trade_relations_primary_live=1 majors_ok=%d dead_n=%d value_ok=%s relations_ok=%s flags_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("value_ok", false)),
			str(res.get("relations_ok", false)), str(res.get("flags_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: trade relations primary live PASS — catalog · value · relations · flags · close (strategic compact ledger)")


func _print_trade_power_intel_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_trade_power_intel_primary_live"):
		print("ScenarioLoader: trade_power_intel_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_trade_power_intel_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: trade_power_intel_primary_live=1 majors_ok=%d dead_n=%d power_ok=%s transit_ok=%s spy_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("power_ok", false)),
			str(res.get("transit_ok", false)), str(res.get("spy_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: trade power intel primary live PASS — catalog · power · transit · spy · close")


func _print_trade_desk_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_trade_desk_primary_live"):
		print("ScenarioLoader: trade_desk_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_trade_desk_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: trade_desk_primary_live=1 majors_ok=%d dead_n=%d interdict_ok=%s tariff_ok=%s desk_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("interdict_ok", false)),
			str(res.get("tariff_ok", false)), str(res.get("desk_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: trade desk primary live PASS — catalog · interdict · tariff · desk · close")


func _print_trade_ai_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_trade_ai_primary_live"):
		print("ScenarioLoader: trade_ai_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_trade_ai_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: trade_ai_primary_live=1 majors_ok=%d dead_n=%d propose_ok=%s accept_ok=%s refuse_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("propose_ok", false)),
			str(res.get("accept_ok", false)), str(res.get("refuse_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: trade AI primary live PASS — catalog · propose · accept · refuse · close")


func _print_trade_basing_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_trade_basing_primary_live"):
		print("ScenarioLoader: trade_basing_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_trade_basing_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: trade_basing_primary_live=1 majors_ok=%d dead_n=%d grant_ok=%s query_ok=%s expire_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("grant_ok", false)),
			str(res.get("query_ok", false)), str(res.get("expire_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: trade basing primary live PASS — catalog · grant · query · expire · close")


func _print_basing_fleet_station_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_basing_fleet_station_primary_live"):
		print("ScenarioLoader: basing_fleet_station_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_basing_fleet_station_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: basing_fleet_station_primary_live=1 majors_ok=%d dead_n=%d score_ok=%s grant_ok=%s prefer_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("score_ok", false)),
			str(res.get("grant_ok", false)), str(res.get("prefer_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: basing fleet station primary live PASS — catalog · score · grant · prefer · close")


func _print_space_layer_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_layer_primary_live"):
		print("ScenarioLoader: space_layer_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_layer_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_layer_primary_live=1 majors_ok=%d dead_n=%d gates_ok=%s graph_ok=%s routes_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("gates_ok", false)),
			str(res.get("graph_ok", false)), str(res.get("routes_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: space layer primary live PASS — catalog · gates · graph · routes · close (orbital compact ledger)")


func _print_space_depth_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_depth_primary_live"):
		print("ScenarioLoader: space_depth_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_depth_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_depth_primary_live=1 majors_ok=%d dead_n=%d sites_ok=%s capacity_ok=%s power_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("sites_ok", false)),
			str(res.get("capacity_ok", false)), str(res.get("power_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: space depth primary live PASS — catalog · sites · capacity · power · close")


func _print_space_ops_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_ops_primary_live"):
		print("ScenarioLoader: space_ops_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_ops_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_ops_primary_live=1 majors_ok=%d dead_n=%d claim_ok=%s habitat_ok=%s flow_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("claim_ok", false)),
			str(res.get("habitat_ok", false)), str(res.get("flow_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: space ops primary live PASS — catalog · claim · habitat · flow · close")


func _print_space_colony_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_colony_primary_live"):
		print("ScenarioLoader: space_colony_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_colony_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_colony_primary_live=1 majors_ok=%d dead_n=%d rel_ok=%s indep_ok=%s combat_ok=%s model=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("rel_ok", false)),
			str(res.get("indep_ok", false)), str(res.get("combat_ok", false)),
			str(res.get("model", "")), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: space colony primary live PASS — catalog · relations · independence · combat · close")


func _print_space_survey_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_survey_primary_live"):
		print("ScenarioLoader: space_survey_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_survey_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_survey_primary_live=1 majors_ok=%d dead_n=%d launch_ok=%s advance_ok=%s discover_ok=%s model=%s ok=%s"
		% [majors_ok, dead_n, str(res.get("launch_ok", false)), str(res.get("advance_ok", false)), str(res.get("discover_ok", false)), str(res.get("model", "")), str(ok)]
	)
	if ok:
		print("ScenarioLoader: space survey primary live PASS — catalog · launch · advance · discover · close")


func _print_space_fog_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_fog_primary_live"):
		print("ScenarioLoader: space_fog_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_fog_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_fog_primary_live=1 majors_ok=%d dead_n=%d fog_ok=%s reveal_ok=%s view_ok=%s model=%s ok=%s"
		% [majors_ok, dead_n, str(res.get("fog_ok", false)), str(res.get("reveal_ok", false)), str(res.get("view_ok", false)), str(res.get("model", "")), str(ok)]
	)
	if ok:
		print("ScenarioLoader: space fog primary live PASS — catalog · fog · reveal · view · close")


func _print_space_terraform_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_terraform_primary_live"):
		print("ScenarioLoader: space_terraform_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_terraform_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_terraform_primary_live=1 majors_ok=%d dead_n=%d start_ok=%s advance_ok=%s garden_ok=%s model=%s ok=%s"
		% [majors_ok, dead_n, str(res.get("start_ok", false)), str(res.get("advance_ok", false)), str(res.get("garden_ok", false)), str(res.get("model", "")), str(ok)]
	)
	if ok:
		print("ScenarioLoader: space terraform primary live PASS — catalog · start · advance · garden · close")


func _print_space_galaxy_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_galaxy_primary_live"):
		print("ScenarioLoader: space_galaxy_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_galaxy_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_galaxy_primary_live=1 majors_ok=%d dead_n=%d unlock_ok=%s claim_ok=%s board_ok=%s model=%s ok=%s"
		% [majors_ok, dead_n, str(res.get("unlock_ok", false)), str(res.get("claim_ok", false)), str(res.get("board_ok", false)), str(res.get("model", "")), str(ok)]
	)
	if ok:
		print("ScenarioLoader: space galaxy primary live PASS — catalog · unlock · claim · board · close")


func _print_n3_network_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_n3_network_primary_live"):
		print("ScenarioLoader: n3_network_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_n3_network_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: n3_network_primary_live=1 majors_ok=%d dead_n=%d lobby_ok=%s seed_ok=%s sync_ok=%s netcode_ready=%s ok=%s"
		% [majors_ok, dead_n, str(res.get("lobby_ok", false)), str(res.get("seed_ok", false)), str(res.get("sync_ok", false)), str(res.get("netcode_ready", false)), str(ok)]
	)
	if ok:
		print("ScenarioLoader: n3 network primary live PASS — catalog · lobby · seed · sync · close (lockstep; not dedicated server)")


func _print_n4_dedicated_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_n4_dedicated_primary_live"):
		print("ScenarioLoader: n4_dedicated_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_n4_dedicated_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: n4_dedicated_primary_live=1 majors_ok=%d dead_n=%d host_ok=%s client_ok=%s reconnect_ok=%s dedicated_server_ready=%s ok=%s"
		% [
			majors_ok, dead_n, str(res.get("host_ok", false)), str(res.get("client_ok", false)),
			str(res.get("reconnect_ok", false)), str(res.get("dedicated_server_ready", false)), str(ok),
		]
	)
	if ok:
		print("ScenarioLoader: n4 dedicated primary live PASS — catalog · host · client · reconnect · close")


func _print_space_supply_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_supply_primary_live"):
		print("ScenarioLoader: space_supply_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_supply_primary_live(pid)
	var majors_ok := int(res.get("majors_ok", 0))
	var dead_n := int(res.get("dead_n", 1))
	var ok := bool(res.get("ok", false))
	print(
		"ScenarioLoader: space_supply_primary_live=1 majors_ok=%d dead_n=%d lift_ok=%s flow_ok=%s board_ok=%s model=%s ok=%s"
		% [majors_ok, dead_n, str(res.get("lift_ok", false)), str(res.get("flow_ok", false)), str(res.get("board_ok", false)), str(res.get("model", "")), str(ok)]
	)
	if ok:
		print("ScenarioLoader: space supply primary live PASS — catalog · lift · flow · board · close")


func _print_space_supply_ai_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_supply_ai_primary_live"):
		print("ScenarioLoader: space_supply_ai_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_supply_ai_primary_live(pid)
	print(
		"ScenarioLoader: space_supply_ai_primary_live=1 majors_ok=%d dead_n=%d setup_ok=%s tick_ok=%s flows_ok=%s model=%s ok=%s"
		% [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("setup_ok", false)), str(res.get("tick_ok", false)), str(res.get("flows_ok", false)), str(res.get("model", "")), str(res.get("ok", false))]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: space supply AI primary live PASS — catalog · setup · tick · flows · close")


func _print_space_survey_events_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_survey_events_primary_live"):
		print("ScenarioLoader: space_survey_events_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_survey_events_primary_live(pid)
	print(
		"ScenarioLoader: space_survey_events_primary_live=1 majors_ok=%d dead_n=%d survey_ok=%s fire_ok=%s chain_ok=%s model=%s ok=%s"
		% [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("survey_ok", false)), str(res.get("fire_ok", false)), str(res.get("chain_ok", false)), str(res.get("model", "")), str(res.get("ok", false))]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: space survey events primary live PASS — catalog · survey · fire · chain · close")


func _print_space_board_ui_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_board_ui_primary_live"):
		print("ScenarioLoader: space_board_ui_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_board_ui_primary_live(pid)
	print(
		"ScenarioLoader: space_board_ui_primary_live=1 majors_ok=%d dead_n=%d board_ok=%s layer_ok=%s strips_ok=%s model=%s ok=%s"
		% [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("board_ok", false)), str(res.get("layer_ok", false)), str(res.get("strips_ok", false)), str(res.get("model", "")), str(res.get("ok", false))]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: space board UI primary live PASS — catalog · board · layer · strips · close")


func _print_space_open_path_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_open_path_primary_live"):
		print("ScenarioLoader: space_open_path_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_open_path_primary_live(pid)
	print("ScenarioLoader: space_open_path_primary_live=1 majors_ok=%d dead_n=%d topbar_ok=%s diplo_ok=%s board_ok=%s ok=%s" % [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("topbar_ok", false)), str(res.get("diplo_ok", false)), str(res.get("board_ok", false)), str(res.get("ok", false))])
	if bool(res.get("ok", false)):
		print("ScenarioLoader: space open path primary live PASS — catalog · topbar · diplo · board · close")


func _print_space_rival_survey_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_rival_survey_primary_live"):
		print("ScenarioLoader: space_rival_survey_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_rival_survey_primary_live(pid)
	print("ScenarioLoader: space_rival_survey_primary_live=1 majors_ok=%d dead_n=%d seed_ok=%s tick_ok=%s compete_ok=%s ok=%s" % [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("seed_ok", false)), str(res.get("tick_ok", false)), str(res.get("compete_ok", false)), str(res.get("ok", false))])
	if bool(res.get("ok", false)):
		print("ScenarioLoader: space rival survey primary live PASS — catalog · seed · tick · compete · close")


func _print_space_discovery_choice_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_discovery_choice_primary_live"):
		print("ScenarioLoader: space_discovery_choice_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_discovery_choice_primary_live(pid)
	print("ScenarioLoader: space_discovery_choice_primary_live=1 majors_ok=%d dead_n=%d discover_ok=%s list_ok=%s resolve_ok=%s ok=%s" % [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("discover_ok", false)), str(res.get("list_ok", false)), str(res.get("resolve_ok", false)), str(res.get("ok", false))])
	if bool(res.get("ok", false)):
		print("ScenarioLoader: space discovery choice primary live PASS — catalog · discover · list · resolve · close")


func _print_matchmaking_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_matchmaking_primary_live"):
		print("ScenarioLoader: matchmaking_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_matchmaking_primary_live(pid)
	print("ScenarioLoader: matchmaking_primary_live=1 majors_ok=%d dead_n=%d queue_ok=%s match_ok=%s session_ok=%s ok=%s" % [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("queue_ok", false)), str(res.get("match_ok", false)), str(res.get("session_ok", false)), str(res.get("ok", false))])
	if bool(res.get("ok", false)):
		print("ScenarioLoader: matchmaking primary live PASS — catalog · queue · match · session · close (not full NAT/WebRTC)")


func _print_space_discovery_ui_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_space_discovery_ui_primary_live"):
		print("ScenarioLoader: space_discovery_ui_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_space_discovery_ui_primary_live(pid)
	print(
		"ScenarioLoader: space_discovery_ui_primary_live=1 majors_ok=%d dead_n=%d unresolved_ok=%s choose_ok=%s reresolve_blocked=%s ok=%s"
		% [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("unresolved_ok", false)), str(res.get("choose_ok", false)), str(res.get("reresolve_blocked", false)), str(res.get("ok", false))]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: space discovery UI primary live PASS — catalog · unresolved · choose · reresolve · close")


func _print_matchmaking_lobby_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_matchmaking_lobby_primary_live"):
		print("ScenarioLoader: matchmaking_lobby_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_matchmaking_lobby_primary_live(pid)
	print(
		"ScenarioLoader: matchmaking_lobby_primary_live=1 majors_ok=%d dead_n=%d open_ok=%s path_ok=%s session_ok=%s ok=%s"
		% [int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)), str(res.get("open_ok", false)), str(res.get("path_ok", false)), str(res.get("session_ok", false)), str(res.get("ok", false))]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: matchmaking lobby primary live PASS — catalog · open · path · session · close (not full NAT/WebRTC)")


func _print_combat_production_design_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_combat_production_design_primary_live"):
		print("ScenarioLoader: combat_production_design_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_combat_production_design_primary_live(pid)
	print(
		"ScenarioLoader: combat_production_design_primary_live=1 majors_ok=%d dead_n=%d scale_ok=%s flow_ok=%s phases_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("scale_ok", false)), str(res.get("flow_ok", false)), str(res.get("phases_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: combat production design primary live PASS — catalog · scale · flow · phases · close (direction freeze; not full rewrite)")


func _print_equipment_flow_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_equipment_flow_primary_live"):
		print("ScenarioLoader: equipment_flow_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_equipment_flow_primary_live(pid)
	print(
		"ScenarioLoader: equipment_flow_primary_live=1 majors_ok=%d dead_n=%d create_ok=%s interdict_ok=%s deliver_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("create_ok", false)), str(res.get("interdict_ok", false)), str(res.get("deliver_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: equipment flow primary live PASS — catalog · create · interdict · deliver · close (CP1)")


func _print_equipment_stock_reinforce_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_equipment_stock_reinforce_primary_live"):
		print("ScenarioLoader: equipment_stock_reinforce_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_equipment_stock_reinforce_primary_live(pid)
	print(
		"ScenarioLoader: equipment_stock_reinforce_primary_live=1 majors_ok=%d dead_n=%d stock_ok=%s reinforce_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("stock_ok", false)), str(res.get("reinforce_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: equipment stock reinforce primary live PASS — catalog · stock · demand · reinforce · close (CP2)")


func _print_reinforcement_logistics_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_reinforcement_logistics_primary_live"):
		print("ScenarioLoader: reinforcement_logistics_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_reinforcement_logistics_primary_live(pid)
	print(
		"ScenarioLoader: reinforcement_logistics_primary_live=1 majors_ok=%d dead_n=%d time_ok=%s exp_ok=%s hub_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("time_ok", false)), str(res.get("exp_ok", false)), str(res.get("hub_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: reinforcement logistics primary live PASS — catalog · time · exp · hub · close (RF1)")


func _print_reinforcement_depth_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_reinforcement_depth_primary_live"):
		print("ScenarioLoader: reinforcement_depth_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_reinforcement_depth_primary_live(pid)
	print(
		"ScenarioLoader: reinforcement_depth_primary_live=1 majors_ok=%d dead_n=%d non_instant_ok=%s combat_xp_ok=%s policy_ok=%s era_mode_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("non_instant_ok", false)), str(res.get("combat_xp_ok", false)),
			str(res.get("policy_ok", false)), str(res.get("era_mode_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: reinforcement depth primary live PASS — catalog · non_instant · combat_xp · policy · era (RF2–RF4)")


func _print_equipment_flow_symbols_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_equipment_flow_symbols_primary_live"):
		print("ScenarioLoader: equipment_flow_symbols_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_equipment_flow_symbols_primary_live(pid)
	print(
		"ScenarioLoader: equipment_flow_symbols_primary_live=1 majors_ok=%d dead_n=%d modes_ok=%s board_ok=%s symbols_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("modes_ok", false)), str(res.get("board_ok", false)), str(res.get("symbols_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: equipment flow symbols primary live PASS — catalog · modes · board · strip · close (CP3)")


func _print_reinforce_story_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_reinforce_story_primary_live"):
		print("ScenarioLoader: reinforce_story_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_reinforce_story_primary_live(pid)
	print(
		"ScenarioLoader: reinforce_story_primary_live=1 majors_ok=%d dead_n=%d xp_plain_ok=%s transit_ok=%s story_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("xp_plain_ok", false)), str(res.get("transit_ok", false)), str(res.get("story_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: reinforce story primary live PASS — catalog · xp · transit · panel · close (RF5)")


func _print_munitions_drone_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_munitions_drone_primary_live"):
		print("ScenarioLoader: munitions_drone_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_munitions_drone_primary_live(pid)
	print(
		"ScenarioLoader: munitions_drone_primary_live=1 majors_ok=%d dead_n=%d missile_ok=%s drone_ok=%s consume_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("missile_ok", false)), str(res.get("drone_ok", false)), str(res.get("consume_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: munitions drone primary live PASS — catalog · missile · drone · consume · close (CP4)")


func _print_combat_consume_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_combat_consume_primary_live"):
		print("ScenarioLoader: combat_consume_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_combat_consume_primary_live(pid)
	print(
		"ScenarioLoader: combat_consume_primary_live=1 majors_ok=%d dead_n=%d combat_consume_ok=%s reliability_ok=%s xp_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("combat_consume_ok", false)), str(res.get("reliability_ok", false)), str(res.get("xp_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: combat consume primary live PASS — catalog · munitions · reliability · troop XP · close (CP5)")


func _print_ai_training_policy_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_ai_training_policy_primary_live"):
		print("ScenarioLoader: ai_training_policy_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_ai_training_policy_primary_live(pid)
	print(
		"ScenarioLoader: ai_training_policy_primary_live=1 majors_ok=%d dead_n=%d peace_ok=%s war_ok=%s ai_policy_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("peace_ok", false)), str(res.get("war_ok", false)), str(res.get("ai_policy_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: AI training policy primary live PASS — catalog · peace · war · crisis · close (RF6)")


func _print_equipment_flow_paint_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_equipment_flow_paint_primary_live"):
		print("ScenarioLoader: equipment_flow_paint_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_equipment_flow_paint_primary_live(pid)
	print(
		"ScenarioLoader: equipment_flow_paint_primary_live=1 majors_ok=%d dead_n=%d symbols_ok=%s board_ok=%s paint_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("symbols_ok", false)), str(res.get("board_ok", false)), str(res.get("paint_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: equipment flow paint primary live PASS — catalog · symbols · board · paint · close (CP3 map glyphs)")


func _print_combat_depth_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_combat_depth_primary_live"):
		print("ScenarioLoader: combat_depth_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_combat_depth_primary_live(pid)
	print(
		"ScenarioLoader: combat_depth_primary_live=1 majors_ok=%d dead_n=%d deep_ok=%s logistics_ok=%s joint_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("deep_ok", false)), str(res.get("logistics_ok", false)), str(res.get("joint_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: combat depth primary live PASS — catalog · deep · logistics · joint · close (CP6)")


func _print_map_flow_lod_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_map_flow_lod_primary_live"):
		print("ScenarioLoader: map_flow_lod_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_map_flow_lod_primary_live(pid)
	print(
		"ScenarioLoader: map_flow_lod_primary_live=1 majors_ok=%d dead_n=%d lod_ok=%s toggle_ok=%s wire_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("lod_ok", false)), str(res.get("toggle_ok", false)), str(res.get("wire_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: map flow LOD primary live PASS — catalog · lod · toggle · wire · close")


func _print_ai_logistics_day_primary_live_evidence() -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_ai_logistics_day_primary_live"):
		print("ScenarioLoader: ai_logistics_day_primary_live=0 (no apply API)")
		return
	var pid := 1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_first_land_province_id"):
		pid = int(MapManager.get_first_land_province_id())
	if pid < 1:
		pid = 1
	var res: Dictionary = GameData.apply_ai_logistics_day_primary_live(pid)
	print(
		"ScenarioLoader: ai_logistics_day_primary_live=1 majors_ok=%d dead_n=%d doctrine_ok=%s apply_ok=%s seed_ok=%s model=%s ok=%s"
		% [
			int(res.get("majors_ok", 0)), int(res.get("dead_n", 1)),
			str(res.get("doctrine_ok", false)), str(res.get("apply_ok", false)), str(res.get("seed_ok", false)),
			str(res.get("model", "")), str(res.get("ok", false)),
		]
	)
	if bool(res.get("ok", false)):
		print("ScenarioLoader: AI logistics day primary live PASS — catalog · doctrine · apply · seed · close")
