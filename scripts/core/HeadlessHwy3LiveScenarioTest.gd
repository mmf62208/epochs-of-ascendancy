extends SceneTree

## HWY-3 FIX #5: live ScenarioLoader city layer (TestScenario / Begin path).
## Drawn-edge count is THE highway number (display_tier==2 RoadTierDraw).
## Rome-north comes from _hwy3_reachable_sectors; a source-edit mutant on
## that second-sector line must kill it. Same city layer Play uses.
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
	_test_highway_z_above_river()
	_test_ruhr_label_rule()
	_test_env_mutants_removed()
	_test_rome_north_source_mutant()
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
		"HWY3_LIVE_MEASURE mode=%s city_source=%s hubs=%d routes=%d used=%d drawn=%d"
		% [
			str(dbg.get("mode", "")),
			str(dbg.get("city_source", "")),
			(_debug().get("hubs", []) as Array).size() if typeof(dbg.get("hubs", [])) == TYPE_ARRAY else 0,
			_routes().size(),
			int(dbg.get("used", 0)),
			int(dbg.get("drawn", _count_highways())),
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
	var cache_n: int = _count_highways()
	var drawn: int = cache_n
	if _ol != null and _ol.has_method("get_drawn_highway_count"):
		drawn = int(_ol.call("get_drawn_highway_count"))
	var used: int = int(_debug().get("used", 0))
	var draw_n: int = -1
	if _ol != null and _ol.has_method("get_road_tier_draw"):
		var node_v: Variant = _ol.call("get_road_tier_draw", 2)
		if node_v is Node2D and "edges" in node_v:
			var ev: Variant = node_v.get("edges")
			if typeof(ev) == TYPE_ARRAY:
				draw_n = (ev as Array).size()
	print(
		"HWY3_LIVE_BARS drawn=%d used=%d cache=%d road_tier_draw=%d"
		% [drawn, used, cache_n, draw_n]
	)
	if draw_n >= 0 and draw_n != drawn:
		_fail("live drawn %d != RoadTierDraw edges %d" % [drawn, draw_n])
	if drawn != cache_n:
		_fail("live drawn %d != cache display_tier==2 %d" % [drawn, cache_n])
	if drawn < 60 or drawn > 114:
		_fail("live drawn highway count %d not within 60–114" % drawn)
	else:
		_pass("live drawn highway count %d within 60–114 (used=%d explicit_gap=%d)" % [
			drawn, used, drawn - used
		])


func _test_highway_z_above_river() -> void:
	if _ol == null or not _ol.has_method("get_highway_draw_z_index"):
		_fail("highway z: overlay missing get_highway_draw_z_index")
		return
	var z: int = int(_ol.call("get_highway_draw_z_index"))
	print("HWY3_LIVE_HWY_Z z=%d river=22" % z)
	if z <= 22:
		_fail("highway z %d not above river/IX-1 spine 22" % z)
	else:
		_pass("highway z %d above river 22" % z)


func _test_ruhr_label_rule() -> void:
	var recs: Array = _records()
	var ruhr: Array = []
	for rec_v in recs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var blob: String = (
			"%s %s" % [str(rec.get("city_name", "")), str(rec.get("name", ""))]
		).strip_edges().to_lower()
		if (
			blob.contains("duisburg")
			or blob.contains("essen, kreisfreie")
			or blob.contains("dortmund")
			or blob.contains("düsseldorf")
			or blob.contains("dusseldorf")
		):
			ruhr.append(rec)
	if ruhr.size() < 3:
		_fail("Ruhr labels: fewer than 3 named hub records")
		return
	var labeled: int = 0
	var metro_n: int = 0
	for rec2_v in ruhr:
		var rec2: Dictionary = rec2_v
		var cluster_n: int = RoadTierVisualScript.hwy3_metro_cluster_n(ruhr, rec2)
		if cluster_n >= RoadTierVisualScript.HWY3_METRO_MIN_HUBS:
			metro_n += 1
		if RoadTierVisualScript.should_label_hub_city(rec2, 2.4, cluster_n):
			labeled += 1
	var metro_edges: int = 0
	for row_v in _cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) != RoadTierVisualScript.TIER_HIGHWAY:
			continue
		if bool(row.get("metro", false)):
			metro_edges += 1
	print("HWY3_LIVE_RUHR_LABELS labeled=%d metro_hubs=%d metro_edges=%d" % [labeled, metro_n, metro_edges])
	if labeled < 3:
		_fail("Ruhr labels: should_label_hub_city at z2.4 hit %d want ≥3" % labeled)
	else:
		_pass("Ruhr labels: %d hubs labeled at z2.4" % labeled)
	if metro_edges < 1:
		_fail("Ruhr metro: no display_tier==2 edge stamped metro")
	else:
		_pass("Ruhr metro: %d highway edges stamped" % metro_edges)


func _test_env_mutants_removed() -> void:
	var ol_src: String = _read_text(SRC_OL)
	var vis_src: String = _read_text(SRC_VIS)
	if ol_src.contains("== \"json_layer\"") or vis_src.contains("== \"json_layer\""):
		_fail("json_layer env branch still in product")
	else:
		_pass("json_layer env branch removed from product")
	if ol_src.contains("== \"no_second_sector\"") or vis_src.contains("== \"no_second_sector\""):
		_fail("no_second_sector env branch still in product")
	else:
		_pass("no_second_sector env branch removed from product")


func _rome_reaches_north_from(dbg: Dictionary) -> Dictionary:
	var recs_v: Variant = dbg.get("records", [])
	var routes_v: Variant = dbg.get("routes", [])
	var recs: Array = recs_v if typeof(recs_v) == TYPE_ARRAY else []
	var routes: Array = routes_v if typeof(routes_v) == TYPE_ARRAY else []
	var rec_by: Dictionary = {}
	for rec_v in recs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		rec_by[int(rec.get("pid", 0))] = rec
	var rome_pid: int = 0
	for rec2_v in recs:
		if typeof(rec2_v) != TYPE_DICTIONARY:
			continue
		var rec2: Dictionary = rec2_v
		var blob: String = (
			"%s %s" % [str(rec2.get("city_name", "")), str(rec2.get("name", ""))]
		).strip_edges().to_lower()
		if blob.contains("rome") or blob.contains("roma"):
			rome_pid = int(rec2.get("pid", 0))
			break
	var out: Dictionary = {"ok": false, "chain": "", "hit": ""}
	if rome_pid <= 0:
		return out
	for rt_v in routes:
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
			var rec3_v: Variant = rec_by.get(pid, {})
			var rec3: Dictionary = rec3_v if typeof(rec3_v) == TYPE_DICTIONARY else {}
			var nm: String = _rec_label(rec3).to_lower()
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


func _write_text(path: String, text: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


func _vis_script() -> GDScript:
	return load(SRC_VIS) as GDScript


func _rebuild_live_cache() -> void:
	var vis_gs: GDScript = _vis_script()
	if vis_gs != null and vis_gs.has_method("hwy3_clear_memos"):
		vis_gs.call("hwy3_clear_memos")
	RoadTierVisualScript.hwy3_clear_memos()
	if _ol != null and _ol.has_method("reset_hwy3_layers"):
		_ol.call("reset_hwy3_layers")
	if _ol != null:
		_ol.call("_rebuild_road_layer_inner")
		if _ol.has_method("get_road_tier_cache"):
			var cache_v: Variant = _ol.call("get_road_tier_cache")
			if typeof(cache_v) == TYPE_ARRAY:
				_cache = cache_v


func _reload_vis_from_disk() -> bool:
	var vis_gs: GDScript = _vis_script()
	if vis_gs == null:
		return false
	return vis_gs.reload() == OK


func _test_rome_north_source_mutant() -> void:
	var src: String = _read_text(SRC_VIS)
	var needle: String = "var second: int = _hwy3_reachable_second_sector(hubs, cap_pid, first, adj, attrs)"
	if needle not in src:
		_fail("rome-north source mutant: _hwy3_reachable_sectors second-sector line missing")
		return
	if src.count(needle) != 1:
		_fail("rome-north source mutant: expected one second-sector assign, got %d" % src.count(needle))
		return
	var mutated: String = src.replace(needle, "var second: int = 0")
	mutated = mutated.replace("class_name RoadTierVisual\n", "")
	var inject_at: int = mutated.find("extends RefCounted\n")
	if inject_at < 0:
		_fail("rome-north source mutant: extends RefCounted missing")
		return
	inject_at += String("extends RefCounted\n").length()
	mutated = (
		mutated.substr(0, inject_at)
		+ "static func hwy3_fix5_mutant_token() -> String:\n	return \"second_zero\"\n"
		+ mutated.substr(inject_at)
	)
	var gs := GDScript.new()
	gs.source_code = mutated
	var reload_err: Error = gs.reload()
	if reload_err != OK:
		print("HWY3_LIVE_SOURCE_MUTANT reload_err=%s needle_left=%s" % [
			str(reload_err), str("var second: int = _hwy3_reachable_second_sector" in mutated)
		])
		_fail("rome-north source mutant: mutated script failed to parse")
		return
	var token: String = ""
	if gs.has_method("hwy3_fix5_mutant_token"):
		token = str(gs.call("hwy3_fix5_mutant_token"))
	print("HWY3_LIVE_SOURCE_MUTANT token=%s" % token)
	if token != "second_zero":
		_fail("rome-north source mutant: in-memory script is not the mutated source")
		return
	var cache_clone: Array = []
	for row_v in _cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var dup: Dictionary = (row_v as Dictionary).duplicate()
		if not bool(dup.get("explicit", false)):
			dup["display_tier"] = int(dup.get("tier", 0))
			dup.erase("metro")
		cache_clone.append(dup)
	if _ol == null or not _ol.has_method("_collect_hwy3_hub_ctx"):
		_fail("rome-north source mutant: overlay missing hub ctx")
		return
	var ctx: Dictionary = _ol.call("_collect_hwy3_hub_ctx")
	if _ol.has_method("get_hwy3_graph_rows"):
		var g_v: Variant = _ol.call("get_hwy3_graph_rows")
		if typeof(g_v) == TYPE_ARRAY and not (g_v as Array).is_empty():
			ctx["graph"] = g_v
	if gs.has_method("hwy3_clear_memos"):
		gs.call("hwy3_clear_memos")
	gs.call("assign_rare_display_tiers", cache_clone, ctx)
	var dbg_v: Variant = gs.call("hwy3_debug")
	var dbg: Dictionary = dbg_v if typeof(dbg_v) == TYPE_DICTIONARY else {}
	var got: Dictionary = _rome_reaches_north_from(dbg)
	var sector2: Variant = dbg.get("sector2_by_tag", {})
	var ita2: int = 0
	if typeof(sector2) == TYPE_DICTIONARY:
		ita2 = int((sector2 as Dictionary).get("ITA", 0))
	print("HWY3_LIVE_SOURCE_MUTANT %s ita_sector2=%d sector2=%s" % [str(got), ita2, str(sector2)])
	if ita2 != 0:
		_fail("mutant reachable_sectors second=0 left ITA sector2=%d" % ita2)
		return
	if bool(got.get("ok", false)):
		_fail("mutant reachable_sectors second=0 survived Rome-north %s" % str(got.get("chain", "")))
	else:
		_pass("mutant reachable_sectors second=0 killed Rome-north")
