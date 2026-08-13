# tools/map_pick_policy_test.gd
## Pure unit tests for MapProvincePickPolicy (no full world scene — avoids OOM kills).
## Run: tools/run_godot.sh --headless -s res://tools/map_pick_policy_test.gd
extends SceneTree

var _fail: PackedStringArray = []
var _pass: PackedStringArray = []


func _init() -> void:
	print("=== MAP PICK POLICY TEST start ===")
	_test_placeholder_names()
	_test_sea_terrain()
	_test_prefer_land()
	_test_region_json_names()
	_test_world_full_land_names()
	_write_results()
	print("PASS: ", " | ".join(_pass))
	if not _fail.is_empty():
		print("FAIL: ", " | ".join(_fail))
	print("=== MAP PICK POLICY TEST end ok=%s ===" % _fail.is_empty())
	quit(0 if _fail.is_empty() else 1)


func _test_placeholder_names() -> void:
	var P = preload("res://scripts/map/MapProvincePickPolicy.gd")
	if not P.is_ocean_latlon_placeholder_name("Atlantic -38E -2N"):
		_fail.append("expect atlantic latlon")
	else:
		_pass.append("atlantic_latlon")
	if P.is_ocean_latlon_placeholder_name("Pacific Northwest North Reach"):
		_fail.append("pacific_northwest_false_positive")
	else:
		_pass.append("pacific_northwest_ok")
	if not P.is_ocean_latlon_placeholder_name("North Atlantic Waters (-38E -2N)"):
		_fail.append("renamed_sea_not_detected")
	else:
		_pass.append("renamed_sea_ok")
	if P.is_ocean_latlon_placeholder_name("London"):
		_fail.append("london_false_positive")
	else:
		_pass.append("london_ok")


func _test_sea_terrain() -> void:
	var P = preload("res://scripts/map/MapProvincePickPolicy.gd")
	if not P.is_sea_terrain("sea", "", "Atlantic -38E -2N"):
		_fail.append("sea_terrain")
	else:
		_pass.append("sea_terrain")
	if P.is_sea_terrain("plains", "", "London"):
		_fail.append("london_not_sea")
	else:
		_pass.append("london_land_terrain")


func _test_prefer_land() -> void:
	var P = preload("res://scripts/map/MapProvincePickPolicy.gd")
	# Sea large + land small both contain → land (area when no dist2)
	var cands := [
		{"id": 20161, "sea": true, "area": 5000.0, "contains": true},
		{"id": 9275, "sea": false, "area": 100.0, "contains": true},
		{"id": 50914, "sea": false, "area": 2600.0, "contains": true},
	]
	var hit := int(P.prefer_land_among_candidates(cands, 20161))
	if hit != 9275:
		_fail.append("prefer_land got %d want 9275" % hit)
	else:
		_pass.append("prefer_land_smallest")
	# With dist2: nearer land wins even if larger area
	var cands_dist := [
		{"id": 9170, "sea": false, "area": 50.0, "dist2": 900.0, "contains": true},
		{"id": 20000, "sea": false, "area": 300.0, "dist2": 4.0, "contains": true},
	]
	var hit_d := int(P.prefer_land_among_candidates(cands_dist, 9170))
	if hit_d != 20000:
		_fail.append("prefer_nearest got %d want 20000" % hit_d)
	else:
		_pass.append("prefer_land_nearest")
	# Only sea contains → primary sea kept when primary is sea
	var sea_only := [
		{"id": 20161, "sea": true, "area": 5000.0, "contains": true},
	]
	var hit2 := int(P.prefer_land_among_candidates(sea_only, 20161))
	if hit2 != 20161:
		_fail.append("sea_only got %d" % hit2)
	else:
		_pass.append("sea_only_ok")


func _test_region_json_names() -> void:
	## Strategic region display names must be human, not only "Strategic Region N".
	var path := "res://data/provinces_world_full/strategic_regions.json"
	if not FileAccess.file_exists(path):
		_fail.append("strategic_regions_missing")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail.append("strategic_regions_bad_json")
		return
	var regions: Array = parsed.get("regions", [])
	var ok := 0
	for r in regions:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var rid := int(r.get("id", 0))
		var n := str(r.get("name", "")).strip_edges()
		if rid <= 0:
			continue
		if n.is_empty() or n.begins_with("Strategic Region "):
			_fail.append("region_%d_generic '%s'" % [rid, n])
		else:
			ok += 1
	if ok >= 10:
		_pass.append("region_names_ok count=%d" % ok)
	else:
		_fail.append("region_names_too_few %d" % ok)


func _test_world_full_land_names() -> void:
	## Land provinces must not ship ocean lat-lon placeholder names.
	var path := "res://data/provinces_world_full/provinces_base.json"
	if not FileAccess.file_exists(path):
		_fail.append("provinces_base_missing")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail.append("provinces_base_bad_json")
		return
	var P = preload("res://scripts/map/MapProvincePickPolicy.gd")
	var land_bad := 0
	var land_n := 0
	var sea_named := 0
	for p in parsed.get("provinces", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var terr := str(p.get("terrain", "")).to_lower()
		var nm := str(p.get("name", ""))
		if terr in ["sea", "ocean"]:
			if P.is_ocean_latlon_placeholder_name(nm) or " Waters (" in nm:
				sea_named += 1
			continue
		land_n += 1
		if P.is_ocean_latlon_placeholder_name(nm):
			land_bad += 1
			if land_bad <= 5:
				_fail.append("land_placeholder id=%s name=%s" % [str(p.get("id")), nm])
	if land_bad == 0:
		_pass.append("land_names_clean land_n=%d sea_named=%d" % [land_n, sea_named])
	else:
		_fail.append("land_placeholder_count=%d" % land_bad)


func _write_results() -> void:
	var da := DirAccess.open("user://")
	if da:
		da.make_dir_recursive("map_world_class_verify")
	var path := "user://map_world_class_verify/policy_results.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"pass": Array(_pass), "fail": Array(_fail), "ok": _fail.is_empty()}, "\t"))
		f.close()
	print("RESULTS: ", path)
