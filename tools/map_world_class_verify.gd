# tools/map_world_class_verify.gd
## Headless map world-class checks: land-over-sea pick, region names, boot readiness.
## Run:
##   tools/run_godot.sh --headless -s res://tools/map_world_class_verify.gd
extends SceneTree

const SCENE := "res://scenes/TestScenario.tscn"
const MAX_WAIT_FRAMES := 4800
const SETTLE_FRAMES := 90
const OUT_DIR := "user://map_world_class_verify"

var _frames := 0
var _phase := "boot"
var _fail: PackedStringArray = []
var _pass: PackedStringArray = []
var _pick_rows: Array = []


func _init() -> void:
	print("=== MAP WORLD-CLASS VERIFY start ===")
	root.ready.connect(_on_root_ready, CONNECT_ONE_SHOT)


func _on_root_ready() -> void:
	var err := change_scene_to_file(SCENE)
	if err != OK:
		_fail.append("change_scene failed %d" % err)
		_finish()
		return
	_phase = "wait_load"
	print("VERIFY: loading ", SCENE)


func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == "wait_load":
		_poll_load()
	elif _phase == "settle":
		if _frames >= SETTLE_FRAMES:
			_phase = "run"
			_run_checks()
	return false


func _poll_load() -> void:
	if _frames > MAX_WAIT_FRAMES:
		_fail.append("timeout frames=%d" % _frames)
		_finish()
		return
	var scene := current_scene
	if scene == null:
		return
	var mr := _find_map_renderer(scene)
	if mr == null:
		return
	var n_prov := 0
	if "provinces" in mr:
		n_prov = (mr.provinces as Dictionary).size()
	if n_prov < 100:
		return
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null or not mm.has_method("get_province_at_world_pos"):
		return
	if mm.has_method("is_ready") and not bool(mm.call("is_ready")):
		return
	_pass.append("boot_provinces=%d" % n_prov)
	_phase = "settle"
	_frames = 0
	print("VERIFY: map ready provinces=%d" % n_prov)


func _run_checks() -> void:
	_check_placeholder_name_helper()
	_check_picks()
	_check_region_names()
	_finish()


func _check_placeholder_name_helper() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null or not mm.has_method("is_ocean_latlon_placeholder_name"):
		_fail.append("placeholder_api_missing")
		return
	var ok_a := bool(mm.call("is_ocean_latlon_placeholder_name", "Atlantic -38E -2N"))
	var ok_b := not bool(mm.call("is_ocean_latlon_placeholder_name", "Pacific Northwest North Reach"))
	var ok_c := not bool(mm.call("is_ocean_latlon_placeholder_name", "London"))
	var ok_d := bool(mm.call("is_ocean_latlon_placeholder_name", "North Atlantic Waters (-38E -2N)"))
	if ok_a and ok_b and ok_c and ok_d:
		_pass.append("placeholder_name_helper")
	else:
		_fail.append("placeholder_name_helper a=%s b=%s c=%s d=%s" % [ok_a, ok_b, ok_c, ok_d])


func _check_picks() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail.append("MapManager missing")
		return
	# Known land centroids from world_full geometry (shipped data).
	var cases: Array = [
		{"label": "london_land", "id": 9275, "expect_land": true, "forbid_atl": true},
		{"label": "leicester_land", "id": 9270, "expect_land": true, "forbid_atl": true},
		{"label": "cairo_land", "id": 20000, "expect_land": true, "forbid_atl": true},
		{"label": "casablanca_land", "id": 30, "expect_land": true, "forbid_atl": true},
		{"label": "atlantic_sea", "id": 20161, "expect_land": false, "forbid_atl": false},
	]
	for c in cases:
		var pid := int(c["id"])
		var p = mm.call("get_province", pid) if mm.has_method("get_province") else null
		var cent := Vector2.ZERO
		if mm.has_method("get_all_centroids"):
			var cents: Dictionary = mm.call("get_all_centroids")
			if cents.has(pid):
				cent = cents[pid]
			elif cents.has(str(pid)):
				cent = cents[str(pid)]
		if cent == Vector2.ZERO and p != null and "center" in p:
			cent = p.center
		if cent == Vector2.ZERO:
			_fail.append("%s no_centroid" % c["label"])
			continue
		var hit := int(mm.call("get_province_at_world_pos", cent, true))
		if mm.has_method("resolve_pick_province_id"):
			hit = int(mm.call("resolve_pick_province_id", hit))
		var hit_p = mm.call("get_province", hit) if hit >= 0 and mm.has_method("get_province") else null
		var name_s := str(hit_p.name) if hit_p != null and "name" in hit_p else ""
		var terr := str(hit_p.terrain) if hit_p != null and "terrain" in hit_p else ""
		var is_sea := false
		if mm.has_method("province_is_sea_domain"):
			is_sea = bool(mm.call("province_is_sea_domain", hit))
		else:
			is_sea = terr.to_lower() in ["sea", "ocean"]
		var row := {
			"label": c["label"],
			"target_id": pid,
			"hit_id": hit,
			"name": name_s,
			"terrain": terr,
			"is_sea": is_sea,
			"centroid": [cent.x, cent.y],
		}
		_pick_rows.append(row)
		var expect_land: bool = bool(c["expect_land"])
		if hit < 0:
			_fail.append("%s pick_miss" % c["label"])
			continue
		if expect_land and is_sea:
			_fail.append("%s expected_land got_sea name=%s" % [c["label"], name_s])
		elif expect_land and bool(c["forbid_atl"]) and mm.has_method("is_ocean_latlon_placeholder_name") and bool(mm.call("is_ocean_latlon_placeholder_name", name_s)):
			_fail.append("%s ocean_placeholder name=%s" % [c["label"], name_s])
		elif not expect_land and not is_sea:
			_fail.append("%s expected_sea got_land name=%s" % [c["label"], name_s])
		else:
			_pass.append("%s hit=%d name=%s sea=%s" % [c["label"], hit, name_s, is_sea])
		# Land cases should resolve near the target province (same id or another land cell).
		if expect_land and hit != pid and hit_p != null:
			# Accept if land and not ocean placeholder — geometry overlaps may rematch smaller neighbor.
			if not is_sea:
				_pass.append("%s_land_neighbor_ok target=%d hit=%d" % [c["label"], pid, hit])


func _check_region_names() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null or not mm.has_method("get_strategic_region_name"):
		_fail.append("region_api_missing")
		return
	var ok := 0
	var samples := [1, 2, 3, 4, 5, 9, 10]
	for rid in samples:
		var n := str(mm.call("get_strategic_region_name", rid)).strip_edges()
		if n.is_empty() or n.begins_with("Strategic Region "):
			_fail.append("region_%d generic_or_empty '%s'" % [rid, n])
		else:
			ok += 1
			_pass.append("region_%d=%s" % [rid, n])
	# Province-linked region for London
	if mm.has_method("get_province_region_id") and mm.has_method("get_strategic_region_name"):
		var rid_l := int(mm.call("get_province_region_id", 9275))
		if rid_l > 0:
			var rn := str(mm.call("get_strategic_region_name", rid_l))
			if rn.begins_with("Strategic Region "):
				_fail.append("london_region_generic rid=%d" % rid_l)
			else:
				_pass.append("london_region=%s" % rn)
		else:
			_pass.append("london_region_unassigned")
	if ok < 3:
		_fail.append("too_few_named_regions ok=%d" % ok)


func _find_map_renderer(scene: Node) -> Node:
	if scene == null:
		return null
	if scene.get_class() == "Node2D" and scene.get_script() != null:
		var sn := str(scene.get_script().resource_path)
		if sn.ends_with("MapRenderer.gd"):
			return scene
	return scene.find_child("WorldMap", true, false)


func _finish() -> void:
	# Persist under user:// then copy path for harness (also print JSON).
	var da := DirAccess.open("user://")
	if da:
		da.make_dir_recursive("map_world_class_verify")
	var path := "user://map_world_class_verify/results.json"
	var payload := {
		"pass": Array(_pass),
		"fail": Array(_fail),
		"picks": _pick_rows,
		"ok": _fail.is_empty(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
	print("VERIFY_PASS: ", " | ".join(_pass))
	if not _fail.is_empty():
		print("VERIFY_FAIL: ", " | ".join(_fail))
	print("VERIFY_JSON: ", path)
	print("=== MAP WORLD-CLASS VERIFY end ok=%s ===" % _fail.is_empty())
	quit(0 if _fail.is_empty() else 1)
