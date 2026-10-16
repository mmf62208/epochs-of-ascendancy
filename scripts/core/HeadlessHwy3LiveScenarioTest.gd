extends SceneTree

## HWY-3 FIX #4: live ScenarioLoader city layer (TestScenario / Begin path).
## Must FAIL if hubs come from the JSON file only, or if the second-sector
## capital span is dropped. Same city layer Play uses.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3LiveScenarioTest.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_LOADER := "res://scripts/core/ScenarioLoader.gd"
const SRC_VIS := "res://scripts/map/RoadTierVisual.gd"

var _failures: int = 0
var _ol: Node2D = null
var _loader: Node = null
var _cache: Array = []


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessHwy3LiveScenarioTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessHwy3LiveScenarioTest: ", msg)


func _run_and_quit() -> void:
	await _run()
	var ok: bool = _failures == 0
	print("HeadlessHwy3LiveScenarioTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessHwy3LiveScenarioTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	OS.set_environment("EOA_HWY3_MUTANT", "")
	if not await _boot_live_scenario():
		return
	_print_live_routes()
	_test_city_source_is_scenario()
	_test_rome_north()
	_test_ruhr()
	_test_paris_one_north()
	_test_highway_count()
	_test_json_layer_mutant()
	_test_no_second_sector_mutant()
	if _ol != null:
		_ol.queue_free()
	if _loader != null:
		_loader.queue_free()


func _boot_live_scenario() -> bool:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail("MapManager autoload missing")
		return false
	var LoaderScr: GDScript = load(SRC_LOADER) as GDScript
	if LoaderScr == null:
		_fail("could not load ScenarioLoader.gd")
		return false
	_loader = LoaderScr.new()
	if _loader == null:
		_fail("could not instantiate ScenarioLoader")
		return false
	_loader.name = "ScenarioLoader"
	root.add_child(_loader)
	if _loader.has_method("load_base_provinces"):
		_loader.call("load_base_provinces")
	if not _loader.has_method("load_scenario"):
		_fail("ScenarioLoader.load_scenario missing")
		return false
	var ok: bool = bool(await _loader.load_scenario("world_accurate"))
	if not ok:
		_fail("load_scenario(world_accurate) failed")
		return false
	if not _loader.has_method("get_map_data"):
		_fail("ScenarioLoader.get_map_data missing")
		return false
	var map_data: Variant = _loader.call("get_map_data")
	if map_data == null:
		_fail("ScenarioLoader.get_map_data returned null")
		return false
	if mm.has_method("initialize_from_map_data"):
		mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	var ol_script: GDScript = load(SRC_OL) as GDScript
	if ol_script == null:
		_fail("could not load InfrastructureOverlayLayer.gd")
		return false
	_ol = ol_script.new() as Node2D
	if _ol == null:
		_fail("could not instantiate overlay")
		return false
	root.add_child(_ol)
	_ol.set("map_manager", mm)
	if _ol.has_method("_ensure_sub_layers"):
		_ol.call("_ensure_sub_layers")
	_ol.call("_rebuild_road_layer_inner")
	if _ol.has_method("get_road_tier_cache"):
		var cache_v: Variant = _ol.call("get_road_tier_cache")
		if typeof(cache_v) == TYPE_ARRAY:
			_cache = cache_v
	if _cache.is_empty():
		_fail("live scenario trunk cache is empty")
		return false
	return true


func _debug() -> Dictionary:
	if "static func hwy3_debug" not in _read_text(SRC_VIS):
		return {}
	var v: Variant = RoadTierVisualScript.hwy3_debug()
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}


func _routes() -> Array:
	var r_v: Variant = _debug().get("routes", [])
	if typeof(r_v) != TYPE_ARRAY:
		return []
	return r_v


func _records() -> Array:
	var r_v: Variant = _debug().get("records", [])
	if typeof(r_v) != TYPE_ARRAY:
		return []
	return r_v


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


func _rec_label(rec: Dictionary) -> String:
	var cn: String = str(rec.get("city_name", "")).strip_edges()
	if cn.is_empty():
		cn = str(rec.get("name", "")).strip_edges()
	var comma: int = cn.find(",")
	if comma >= 0:
		cn = cn.substr(0, comma).strip_edges()
	return cn


func _rec_by_pid() -> Dictionary:
	var out: Dictionary = {}
	for rec_v in _records():
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		out[int(rec.get("pid", 0))] = rec
	return out


func _name_of(pid: int, rec_by: Dictionary) -> String:
	var rec_v: Variant = rec_by.get(pid, {})
	var rec: Dictionary = rec_v if typeof(rec_v) == TYPE_DICTIONARY else {}
	var nm: String = _rec_label(rec)
	if nm.is_empty():
		return str(pid)
	return nm


func _route_name_chain(rt: Dictionary, rec_by: Dictionary) -> String:
	var names: Array = []
	var pids_v: Variant = rt.get("pids", [])
	var pids: Array = pids_v if typeof(pids_v) == TYPE_ARRAY else []
	for pv in pids:
		names.append(_name_of(int(pv), rec_by))
	return " → ".join(names)


func _print_live_routes() -> void:
	var rec_by: Dictionary = _rec_by_pid()
	var dbg: Dictionary = _debug()
	print(
		"HWY3_LIVE_MEASURE mode=%s city_source=%s hubs=%d routes=%d used=%d"
		% [
			str(dbg.get("mode", "")),
			str(dbg.get("city_source", "")),
			(_debug().get("hubs", []) as Array).size() if typeof(dbg.get("hubs", [])) == TYPE_ARRAY else 0,
			_routes().size(),
			int(dbg.get("used", 0)),
		]
	)
	print("HWY3_LIVE_SECOND %s" % str(dbg.get("second_by_tag", {})))
	print("HWY3_LIVE_SECTOR2 %s" % str(dbg.get("sector2_by_tag", {})))
	print("HWY3_LIVE_TRUNKS %s" % str(dbg.get("trunks", [])))
	for rt_v in _routes():
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		print("HWY3_LIVE_ROUTE %s" % _route_name_chain(rt, rec_by))


func _find_named(needles: Array) -> Dictionary:
	for rec_v in _records():
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var blob: String = (
			"%s %s" % [str(rec.get("city_name", "")), str(rec.get("name", ""))]
		).strip_edges().to_lower()
		for n_v in needles:
			var n: String = str(n_v)
			if blob.contains(n):
				return rec
	return {}


func _rome_reaches_north() -> Dictionary:
	var rec_by: Dictionary = _rec_by_pid()
	var rome: Dictionary = _find_named(["rome", "roma"])
	var rome_pid: int = int(rome.get("pid", 0))
	var out: Dictionary = {"ok": false, "chain": "", "hit": ""}
	if rome_pid <= 0:
		return out
	for rt_v in _routes():
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var pids_v: Variant = rt.get("pids", [])
		var pids: Array = pids_v if typeof(pids_v) == TYPE_ARRAY else []
		var has_rome: bool = false
		var hit: String = ""
		for pv in pids:
			var pid: int = int(pv)
			if pid == rome_pid:
				has_rome = true
			var nm: String = _name_of(pid, rec_by).to_lower()
			if (
				nm.contains("firenze")
				or nm.contains("florence")
				or nm.contains("bologna")
				or nm.contains("milano")
				or nm.contains("milan")
			):
				hit = nm
		if has_rome and hit != "":
			out["ok"] = true
			out["hit"] = hit
			out["chain"] = _route_name_chain(rt, rec_by)
			return out
	return out


func _test_city_source_is_scenario() -> void:
	if _loader == null or not _loader.has_method("get_city_layer") or _ol == null:
		_fail("live city source: loader/overlay missing")
		return
	if not _ol.has_method("get_hwy3_city_layer"):
		_fail("live city source: overlay has no get_hwy3_city_layer")
		return
	var live_v: Variant = _loader.call("get_city_layer")
	var used_v: Variant = _ol.call("get_hwy3_city_layer")
	if typeof(live_v) != TYPE_DICTIONARY or typeof(used_v) != TYPE_DICTIONARY:
		_fail("live city source: city layer type mismatch")
		return
	if used_v != live_v:
		_fail("live city source: overlay did not use ScenarioLoader.get_city_layer()")
	else:
		_pass("live city source is ScenarioLoader.get_city_layer()")


func _test_rome_north() -> void:
	var got: Dictionary = _rome_reaches_north()
	print("HWY3_LIVE_ROME_NORTH %s" % str(got))
	if bool(got.get("ok", false)):
		_pass("Rome-north live: %s" % str(got.get("chain", "")))
	else:
		_fail("Rome-north live: no Roma route reaches Firenze/Bologna/Milano")


func _test_ruhr() -> void:
	var recs: Array = _records()
	var ruhr: Dictionary = {}
	for rec_v in recs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if str(rec.get("tag", "")).to_upper() != "GER":
			continue
		var nm: String = str(rec.get("name", "")).to_lower()
		var cnm: String = str(rec.get("city_name", "")).to_lower()
		var hit: String = ""
		if cnm.contains("duisburg") or nm.contains("duisburg"):
			hit = "duisburg"
		elif cnm.contains("essen") or nm.contains("essen, kreisfreie"):
			hit = "essen"
		elif cnm.contains("dortmund") or nm.contains("dortmund"):
			hit = "dortmund"
		if hit != "":
			ruhr[int(rec.get("pid", 0))] = hit
	if ruhr.size() < 3:
		_fail("Ruhr live: city records missing (have %d)" % ruhr.size())
		return
	var best: int = 0
	var best_names: Array = []
	for rt_v in _routes():
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var pids_v: Variant = rt.get("pids", [])
		var pids: Array = pids_v if typeof(pids_v) == TYPE_ARRAY else []
		var names: Dictionary = {}
		for pv in pids:
			var pid: int = int(pv)
			if ruhr.has(pid):
				names[str(ruhr[pid])] = true
		if names.size() > best:
			best = names.size()
			best_names = names.keys()
	print("HWY3_LIVE_RUHR n=%d %s" % [best, str(best_names)])
	if best < 3:
		_fail("Ruhr live: Duisburg/Essen/Dortmund not on one route %s" % str(best_names))
	else:
		_pass("Ruhr live: %d of Duisburg/Essen/Dortmund on one route %s" % [best, str(best_names)])


func _test_paris_one_north() -> void:
	var rec_by: Dictionary = _rec_by_pid()
	var paris: Dictionary = _find_named(["paris"])
	var paris_pid: int = int(paris.get("pid", 0))
	if paris_pid <= 0:
		_fail("Paris live: Paris record missing")
		return
	var paris_c: Vector2 = paris.get("centroid", Vector2.ZERO)
	var north_chains: Array = []
	for rt_v in _routes():
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var pids_v: Variant = rt.get("pids", [])
		var pids: Array = pids_v if typeof(pids_v) == TYPE_ARRAY else []
		var has_paris: bool = false
		var north_end: bool = false
		for pv in pids:
			var pid: int = int(pv)
			if pid == paris_pid:
				has_paris = true
				continue
			var rec_v: Variant = rec_by.get(pid, {})
			var rec: Dictionary = rec_v if typeof(rec_v) == TYPE_DICTIONARY else {}
			var c: Vector2 = rec.get("centroid", Vector2.ZERO)
			if c.y + 0.01 < paris_c.y:
				north_end = true
		if has_paris and north_end:
			north_chains.append(_route_name_chain(rt, rec_by))
	print("HWY3_LIVE_PARIS_NORTH n=%d %s" % [north_chains.size(), str(north_chains)])
	if north_chains.size() == 1:
		_pass("Paris live: one line north %s" % str(north_chains[0]))
	else:
		_fail("Paris live: want one north line, got %d %s" % [north_chains.size(), str(north_chains)])


func _count_highways() -> int:
	var n: int = 0
	for row_v in _cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		if int((row_v as Dictionary).get("display_tier", 0)) == RoadTierVisualScript.TIER_HIGHWAY:
			n += 1
	return n


func _test_highway_count() -> void:
	if _ol != null and _ol.has_method("get_road_tier_cache"):
		var cache_v: Variant = _ol.call("get_road_tier_cache")
		if typeof(cache_v) == TYPE_ARRAY:
			_cache = cache_v
	var hwy: int = _count_highways()
	print("HWY3_LIVE_BARS highways=%d" % hwy)
	if hwy < 60 or hwy > 114:
		_fail("live highway count %d not within 60–114" % hwy)
	else:
		_pass("live highway count %d within 60–114" % hwy)


func _rebuild_with_mutant(name: String) -> void:
	OS.set_environment("EOA_HWY3_MUTANT", name)
	RoadTierVisualScript.hwy3_clear_memos()
	if _ol != null and _ol.has_method("reset_hwy3_layers"):
		_ol.call("reset_hwy3_layers")
	if _ol != null:
		_ol.call("_rebuild_road_layer_inner")
		if _ol.has_method("get_road_tier_cache"):
			var cache_v: Variant = _ol.call("get_road_tier_cache")
			if typeof(cache_v) == TYPE_ARRAY:
				_cache = cache_v
	OS.set_environment("EOA_HWY3_MUTANT", "")


func _test_json_layer_mutant() -> void:
	if _loader == null or _ol == null or not _ol.has_method("get_hwy3_city_layer"):
		_fail("json_layer: overlay/loader missing")
		return
	_rebuild_with_mutant("json_layer")
	var live_v: Variant = _loader.call("get_city_layer")
	var used_v: Variant = _ol.call("get_hwy3_city_layer")
	var same: bool = typeof(used_v) == TYPE_DICTIONARY and used_v == live_v
	if same:
		_fail("mutant json_layer survived (still ScenarioLoader city layer)")
	else:
		_pass("mutant json_layer killed (JSON layer only)")
	RoadTierVisualScript.hwy3_clear_memos()
	if _ol.has_method("reset_hwy3_layers"):
		_ol.call("reset_hwy3_layers")
	_ol.call("_rebuild_road_layer_inner")


func _test_no_second_sector_mutant() -> void:
	_rebuild_with_mutant("no_second_sector")
	var got: Dictionary = _rome_reaches_north()
	print("HWY3_LIVE_NO_SECTOR2 %s" % str(got))
	if bool(got.get("ok", false)):
		_fail("mutant no_second_sector survived Rome-north %s" % str(got.get("chain", "")))
	else:
		_pass("mutant no_second_sector killed (no Rome-north span)")
	RoadTierVisualScript.hwy3_clear_memos()
	if _ol != null and _ol.has_method("reset_hwy3_layers"):
		_ol.call("reset_hwy3_layers")
	if _ol != null:
		_ol.call("_rebuild_road_layer_inner")
