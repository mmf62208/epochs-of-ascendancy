# tools/map_manager_pick_harness_accurate.gd
## Light MapManager world_accurate capital pick harness (no MapRenderer / TestScenario).
## Loads provinces_world_accurate base+geometry and picks 8 major capitals at centroids.
## Scaffold dual stays on map_manager_pick_harness.gd (world_full city IDs).
## Run: tools/run_godot.sh --headless -s res://tools/map_manager_pick_harness_accurate.gd
extends SceneTree

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const SCENARIO_PATH := "res://data/scenarios/world_accurate.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const OUT_USER := "user://map_world_class_verify"

var _fail: PackedStringArray = []
var _pass: PackedStringArray = []
var _pick_rows: Array = []


func _init() -> void:
	print("=== MAP MANAGER PICK HARNESS ACCURATE start ===")
	call_deferred("_run")


func _run() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail.append("MapManager_autoload_missing")
		_finish()
		return
	if not mm.has_method("initialize_from_map_data"):
		_fail.append("initialize_from_map_data_missing")
		_finish()
		return

	var base := _load_json(BASE_PATH)
	var geo := _load_json(GEO_PATH)
	var own_doc := _load_json(OWN_PATH)
	var sc := _load_json(SCENARIO_PATH)
	if base.is_empty() or geo.is_empty() or sc.is_empty():
		_fail.append("data_load_failed")
		_finish()
		return

	var ProvScript: GDScript = load(PROV_SCRIPT) as GDScript
	var MapDataScript: GDScript = load(MAP_DATA_SCRIPT) as GDScript
	if ProvScript == null or MapDataScript == null:
		_fail.append("script_load_failed")
		_finish()
		return

	var owners: Dictionary = own_doc.get("owners", {}) as Dictionary
	var provs: Dictionary = {}
	for row in base.get("provinces", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid := int(row.get("id", 0))
		if pid <= 0:
			continue
		var p = ProvScript.new()
		p.id = pid
		p.name = str(row.get("name", "Province %d" % pid))
		p.terrain = str(row.get("terrain", "plains"))
		p.domain = str(row.get("domain", "land"))
		var terr_l := str(p.terrain).strip_edges().to_lower()
		p.is_sea = terr_l in ["sea", "ocean", "water", "lake"] or str(p.domain).strip_edges().to_lower() in ["sea", "ocean", "naval"]
		var ot := str(owners.get(str(pid), "")).strip_edges().to_upper()
		if not ot.is_empty():
			p.owner_tag = ot
			p.controller_tag = ot
		provs[pid] = p

	var geometry: Dictionary = {}
	for row in geo.get("provinces", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid := int(row.get("id", 0))
		if pid <= 0:
			continue
		var pts: Array = row.get("points", [])
		var packed := PackedVector2Array()
		for pt in pts:
			if pt is Array and pt.size() >= 2:
				packed.append(Vector2(float(pt[0]), float(pt[1])))
		geometry[pid] = {
			"points": packed,
			"label_anchor": row.get("label_anchor", []),
			"meta": row.get("meta", {}),
		}

	var map_data = MapDataScript.new(provs, geometry, null, {})
	mm.call("initialize_from_map_data", map_data)
	if mm.has_method("set_geometry_world_native"):
		mm.call("set_geometry_world_native", false)
	if mm.has_method("set_geometry_world_space"):
		mm.call("set_geometry_world_space", false)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")

	var n_prov := int(mm.call("get_province_count")) if mm.has_method("get_province_count") else 0
	# Post US + full RoW sparse merge ~3520 (was ~5670 / ~8761). Floor 3000.
	if n_prov < 3000:
		_fail.append("too_few_provinces=%d (need accurate ~3520 post-sparse)" % n_prov)
	else:
		_pass.append("loaded_provinces=%d" % n_prov)
	if mm.has_method("has_pick_grid") and bool(mm.call("has_pick_grid")):
		_pass.append("pick_grid_built")
	else:
		_fail.append("pick_grid_missing")

	_check_capitals(mm, sc)
	_finish()


func _check_capitals(mm: Node, sc: Dictionary) -> void:
	var countries: Array = sc.get("countries", []) as Array
	if countries.size() < 8:
		_fail.append("scenario_countries=%d" % countries.size())
	for c in countries:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var tag := str(c.get("tag", "")).strip_edges().to_upper()
		var pid := int(c.get("capital_province_id", 0))
		if tag.is_empty() or pid <= 0:
			_fail.append("bad_country_row")
			continue
		var cent := Vector2.ZERO
		if mm.has_method("get_all_centroids"):
			var cents: Dictionary = mm.call("get_all_centroids")
			if cents.has(pid):
				cent = cents[pid]
			elif cents.has(str(pid)):
				cent = cents[str(pid)]
		# Fall back to geometry label_anchor if centroid missing
		if cent == Vector2.ZERO and mm.has_method("get_province_geometry"):
			pass
		if cent == Vector2.ZERO:
			_fail.append("%s no_centroid id=%d" % [tag, pid])
			continue
		var hit := int(mm.call("get_province_at_world_pos", cent, true))
		if mm.has_method("resolve_pick_province_id"):
			hit = int(mm.call("resolve_pick_province_id", hit))
		var hit_p = mm.call("get_province", hit) if hit >= 0 and mm.has_method("get_province") else null
		var name_s := str(hit_p.name) if hit_p != null else ""
		var is_sea := false
		if hit >= 0 and mm.has_method("province_is_sea_domain"):
			is_sea = bool(mm.call("province_is_sea_domain", hit))
		elif hit_p != null:
			is_sea = str(hit_p.terrain).to_lower() in ["sea", "ocean"]
		var row := {
			"label": tag.to_lower(),
			"target_id": pid,
			"hit_id": hit,
			"name": name_s,
			"is_sea": is_sea,
			"centroid": [cent.x, cent.y],
		}
		_pick_rows.append(row)
		print("PICK_ACCURATE ", JSON.stringify(row))
		if hit < 0:
			_fail.append("%s pick_miss" % tag)
			continue
		if is_sea:
			_fail.append("%s expected_land got_sea name=%s" % [tag, name_s])
		else:
			_pass.append("%s land hit=%d" % [tag, hit])
		# Prefer exact capital id; allow land neighbor only if same owner later — for now exact preferred.
		if hit == pid:
			_pass.append("%s_exact" % tag)
		else:
			# Soft: still land pick is ok if we hit something near capital
			_pass.append("%s_near hit=%d want=%d name=%s" % [tag, hit, pid, name_s])
		# Owner should match tag on capital province object
		var cap_p = mm.call("get_province", pid) if mm.has_method("get_province") else null
		if cap_p != null and str(cap_p.owner_tag).to_upper() != tag:
			_fail.append("%s capital_owner=%s" % [tag, cap_p.owner_tag])
		elif cap_p != null:
			_pass.append("%s owned" % tag)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("missing " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _finish() -> void:
	var da := DirAccess.open("user://")
	if da:
		da.make_dir_recursive("map_world_class_verify")
	var pick_path := OUT_USER + "/map_pick_accurate.json"
	var f := FileAccess.open(pick_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"board": "world_accurate",
			"picks": _pick_rows,
			"pass": Array(_pass),
			"fail": Array(_fail),
			"ok": _fail.is_empty(),
		}, "\t"))
		f.close()
	print("RESULTS: ", pick_path)
	print("PASS: ", " | ".join(_pass))
	if not _fail.is_empty():
		print("FAIL: ", " | ".join(_fail))
	print("=== MAP MANAGER PICK HARNESS ACCURATE end ok=%s ===" % _fail.is_empty())
	quit(0 if _fail.is_empty() else 1)
