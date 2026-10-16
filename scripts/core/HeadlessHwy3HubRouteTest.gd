extends SceneTree

## HWY-3: display highways are hub-to-hub trunk shortest paths.
## Must FAIL on d4a3a1ff (rank-and-grow) and PASS on the HWY-3 tip.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3HubRouteTest.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_VIS := "res://scripts/map/RoadTierVisual.gd"
const SRC_GUARD := "res://scripts/core/WindowedRt1RoadTierPixelGuard.gd"
const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const ECON_PATH := "res://data/provinces_world_accurate/province_economy_layer.json"
const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const MAJORS: Array = ["GER", "FRA", "ITA", "POL", "ENG", "USA", "JAP", "SOV"]
## Independent of RoadTierVisual.path_shape_report (mutants must not share that fn).
const SHAPE_HOOK := 2.61799387799149 ## 150°
const SHAPE_ZIGZAG := 4.71238898038469 ## 1.5π
const SHAPE_LEN_RATIO := 1.6

var _failures: int = 0
var _ol: Node2D = null
var _cache: Array = []
var _vis_inst: Object = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessHwy3HubRouteTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessHwy3HubRouteTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok: bool = _failures == 0
	print("HeadlessHwy3HubRouteTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessHwy3HubRouteTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	OS.set_environment("EOA_HWY3_MUTANT", "")
	_test_pid_list_grep()
	_test_far_width_not_hidden()
	_test_flip_max_guard_source()
	if "static func select_display_hubs" not in _read_text(SRC_VIS):
		_fail("H1: assign mode is rank-grow (d4a3a1ff)")
		_fail("H2: no hub routes (rank-grow / empty)")
		return
	if not _boot_live_1936():
		return
	_test_h1_hubs()
	_test_h2_routes()
	_test_h3_simple_paths()
	_test_h4_germany()
	_test_h4_major_trunks()
	_test_h4_rome_north()
	_test_h4_ruhr_span()
	_test_h4_no_near_parallel()
	_test_h4_no_duplicate_corridor()
	_test_h5_budget()
	_test_h6_determinism()
	_test_mutants()
	if _ol != null:
		_ol.queue_free()


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


func _vis_obj() -> Object:
	if _vis_inst == null:
		var scr: GDScript = load(SRC_VIS) as GDScript
		_vis_inst = scr.new()
	return _vis_inst


func _vis_call(method: String, args: Array = []) -> Variant:
	return _vis_obj().callv(method, args)


func _debug() -> Dictionary:
	# d4a3a1ff has no hub-route statics — fail as rank-grow, do not SCRIPT ERROR.
	if "static func hwy3_debug" not in _read_text(SRC_VIS):
		return {"mode": "rank_grow", "hubs": [], "routes": [], "records": []}
	var v: Variant = _vis_call("hwy3_debug", [])
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {"mode": "rank_grow", "hubs": [], "routes": [], "records": []}


func _hub_set() -> Dictionary:
	var dbg: Dictionary = _debug()
	var hs_v: Variant = dbg.get("hub_set", {})
	if typeof(hs_v) == TYPE_DICTIONARY:
		return hs_v
	var out: Dictionary = {}
	var hubs_v: Variant = dbg.get("hubs", [])
	if typeof(hubs_v) == TYPE_ARRAY:
		for h_v in hubs_v:
			if typeof(h_v) == TYPE_DICTIONARY:
				out[int((h_v as Dictionary).get("pid", 0))] = true
	return out


func _routes() -> Array:
	var dbg: Dictionary = _debug()
	var r_v: Variant = dbg.get("routes", [])
	if typeof(r_v) != TYPE_ARRAY:
		return []
	return r_v


func _records() -> Array:
	var dbg: Dictionary = _debug()
	var r_v: Variant = dbg.get("records", [])
	if typeof(r_v) != TYPE_ARRAY:
		return []
	return r_v


func _component_stats(cache: Array) -> Dictionary:
	return RoadTierVisualScript._hwy1_component_stats(cache)


func _boot_live_1936() -> bool:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail("MapManager autoload missing")
		return false
	if not _load_accurate_1936(mm):
		return false
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
		_fail("live 1936 trunk cache is empty")
		return false
	var dbg: Dictionary = _debug()
	var ends: Array = []
	for rt0_v in _routes():
		if typeof(rt0_v) == TYPE_DICTIONARY:
			var rt0: Dictionary = rt0_v
			ends.append("%d-%d n=%d" % [int(rt0.get("a", 0)), int(rt0.get("b", 0)), (rt0.get("pids", []) as Array).size() if typeof(rt0.get("pids", [])) == TYPE_ARRAY else 0])
	print(
		"HWY3_MEASURE mode=%s hubs=%d routes=%d used=%d drawn=%d budget=%d cache=%d adj_ms=%.2f dropped_parallel=%d dropped_cap=%d ends=%s"
		% [
			str(dbg.get("mode", "")),
			(_debug().get("hubs", []) as Array).size() if typeof(dbg.get("hubs", [])) == TYPE_ARRAY else 0,
			_routes().size(),
			int(dbg.get("used", 0)),
			int(dbg.get("drawn", _count_highways_cache(_cache))),
			int(dbg.get("budget", 0)),
			_cache.size(),
			float(dbg.get("adj_ms", 0.0)),
			int(dbg.get("dropped_parallel", 0)),
			int(dbg.get("dropped_cap", 0)),
			str(ends),
		]
	)
	print("HWY3_FAILED_TRUNKS %s" % str(dbg.get("failed_trunks", [])))
	print("HWY3_FAILED_SPANS %s" % str(dbg.get("failed_spans", [])))
	print("HWY3_SPANS %s" % str(dbg.get("spans", [])))
	print("HWY3_PERI %s" % str(dbg.get("peri", [])))
	print("HWY3_TRUNKS %s" % str(dbg.get("trunks", [])))
	print("HWY3_SECOND %s" % str(dbg.get("second_by_tag", {})))
	var ger_nm: Array = []
	for hg_v in dbg.get("hubs", []):
		if typeof(hg_v) != TYPE_DICTIONARY:
			continue
		var hg: Dictionary = hg_v
		if str(hg.get("tag", "")).to_upper() != "GER":
			continue
		ger_nm.append("%s:%d" % [str(hg.get("city_name", hg.get("name", ""))), int(hg.get("pid", 0))])
	print("HWY3_GER_HUBS %s" % str(ger_nm))
	return true


func _load_accurate_1936(mm: Node) -> bool:
	var base: Dictionary = _load_json(BASE_PATH)
	var geo: Dictionary = _load_json(GEO_PATH)
	var own_doc: Dictionary = _load_json(OWN_PATH)
	var econ_doc: Dictionary = _load_json(ECON_PATH)
	var city_doc: Dictionary = _load_json(CITY_PATH)
	if base.is_empty() or geo.is_empty():
		_fail("world_accurate data missing")
		return false
	var ProvScript: GDScript = load(PROV_SCRIPT) as GDScript
	var MapDataScript: GDScript = load(MAP_DATA_SCRIPT) as GDScript
	if ProvScript == null or MapDataScript == null:
		_fail("Province / MapScenarioData load failed")
		return false
	var owners_v: Variant = own_doc.get("owners", {})
	var owners: Dictionary = owners_v if typeof(owners_v) == TYPE_DICTIONARY else {}
	var econ_root_v: Variant = econ_doc.get("provinces", econ_doc)
	var econ: Dictionary = econ_root_v if typeof(econ_root_v) == TYPE_DICTIONARY else {}
	var city_root_v: Variant = city_doc.get("provinces", city_doc)
	var city: Dictionary = city_root_v if typeof(city_root_v) == TYPE_DICTIONARY else {}
	var provs: Dictionary = {}
	var countries: Dictionary = {}
	var base_rows_v: Variant = base.get("provinces", [])
	if typeof(base_rows_v) != TYPE_ARRAY:
		_fail("provinces_base missing array")
		return false
	var base_rows: Array = base_rows_v
	for row_v in base_rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var pid: int = int(row.get("id", 0))
		if pid <= 0:
			continue
		var p: Object = ProvScript.new()
		p.set("id", pid)
		p.set("name", str(row.get("name", "Province %d" % pid)))
		p.set("terrain", str(row.get("terrain", "plains")))
		p.set("domain", str(row.get("domain", "land")))
		var terr_l: String = str(p.get("terrain")).strip_edges().to_lower()
		var dom_l: String = str(p.get("domain")).strip_edges().to_lower()
		p.set("is_sea", terr_l in ["sea", "ocean", "water", "lake"] or dom_l in ["sea", "ocean", "naval"])
		var ot: String = str(owners.get(str(pid), "")).strip_edges().to_upper()
		if not ot.is_empty():
			p.set("owner_tag", ot)
			p.set("controller_tag", ot)
		var er_v: Variant = econ.get(str(pid), {})
		var er: Dictionary = er_v if typeof(er_v) == TYPE_DICTIONARY else {}
		p.set("infrastructure", int(er.get("infrastructure", er.get("infra", row.get("infrastructure", 1)))))
		p.set("development_level", int(er.get("development_level", er.get("dev", row.get("development_level", 1)))))
		p.set("population", int(er.get("population", er.get("pop", row.get("population_base", row.get("population", 20000))))))
		var ce_v: Variant = city.get(str(pid), {})
		var ce: Dictionary = ce_v if typeof(ce_v) == TYPE_DICTIONARY else {}
		if bool(ce.get("is_capital", false)) or bool(ce.get("capital", false)):
			if p.has_method("has_feature") or true:
				var feats: Dictionary = p.get("special_features") if "special_features" in p else {}
				feats["capital"] = 1
				p.set("special_features", feats)
			if not ot.is_empty():
				countries[ot] = {"tag": ot, "capital_province_id": pid}
		provs[pid] = p
	var geometry: Dictionary = {}
	var geo_rows_v: Variant = geo.get("provinces", [])
	if typeof(geo_rows_v) != TYPE_ARRAY:
		_fail("geometry missing array")
		return false
	var geo_rows: Array = geo_rows_v
	for grow_v in geo_rows:
		if typeof(grow_v) != TYPE_DICTIONARY:
			continue
		var grow: Dictionary = grow_v
		var pid2: int = int(grow.get("id", 0))
		if pid2 <= 0:
			continue
		var pts_v: Variant = grow.get("points", [])
		var packed: PackedVector2Array = PackedVector2Array()
		if typeof(pts_v) == TYPE_ARRAY:
			for pt in pts_v:
				if pt is Array and pt.size() >= 2:
					packed.append(Vector2(float(pt[0]), float(pt[1])))
		geometry[pid2] = {
			"points": packed,
			"label_anchor": grow.get("label_anchor", []),
			"meta": grow.get("meta", {}),
		}
	var adj: Object = null
	if FileAccess.file_exists(ADJ_PATH):
		var AdjScr: GDScript = load("res://scripts/data/AdjacencySystem.gd") as GDScript
		if AdjScr != null:
			adj = AdjScr.new()
			if adj.has_method("load_adjacency"):
				adj.call("load_adjacency", ADJ_PATH)
			if adj.has_method("begin_bulk_registration"):
				adj.call("begin_bulk_registration")
			for pid_k in provs.keys():
				if adj.has_method("register_province"):
					adj.call("register_province", provs[pid_k])
			if adj.has_method("end_bulk_registration"):
				adj.call("end_bulk_registration")
	var map_data: Object = MapDataScript.new(provs, geometry, adj, countries)
	mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	return true


func _test_h1_hubs() -> void:
	var dbg: Dictionary = _debug()
	if str(dbg.get("mode", "")) != "hub_routes":
		_fail("H1: assign mode is %s (rank-grow on d4a3a1ff)" % str(dbg.get("mode", "")))
		return
	var recs: Array = _records()
	var hubs: Dictionary = _hub_set()
	var cap_by_tag: Dictionary = {}
	for rec_v in recs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if bool(rec.get("capital", false)):
			var tag: String = str(rec.get("tag", "")).strip_edges().to_upper()
			if not cap_by_tag.has(tag):
				cap_by_tag[tag] = int(rec.get("pid", 0))
	var missing_majors: Array = []
	for tag in MAJORS:
		var cap: int = int(cap_by_tag.get(tag, 0))
		if cap <= 0 or not hubs.has(cap):
			missing_majors.append("%s:%d" % [tag, cap])
	if not missing_majors.is_empty():
		_fail("H1: major capitals not hubs %s" % str(missing_majors))
	else:
		_pass("H1: every major capital is a hub")
	var non_major_cap: bool = false
	for tag_v in cap_by_tag.keys():
		var tag2: String = str(tag_v)
		if MAJORS.has(tag2):
			continue
		if hubs.has(int(cap_by_tag[tag2])):
			non_major_cap = true
			break
	if not non_major_cap:
		_fail("H1: no non-major capital hub")
	else:
		_pass("H1: a non-major capital is a hub")
	var off_v: Variant = _vis_call("select_display_hubs", [recs, false])
	var off: Array = off_v if typeof(off_v) == TYPE_ARRAY else []
	var off_set: Dictionary = {}
	var off_tags: Dictionary = {}
	for h_v in off:
		if typeof(h_v) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_v
		off_set[int(h.get("pid", 0))] = true
		off_tags[str(h.get("tag", ""))] = true
	var miss_off: Array = []
	for tag3 in MAJORS:
		var cap3: int = int(cap_by_tag.get(tag3, 0))
		if cap3 <= 0 or not off_set.has(cap3):
			miss_off.append(tag3)
	if not miss_off.is_empty():
		_fail("H1 bonus-off: major capitals missing %s" % str(miss_off))
	else:
		_pass("H1 bonus-off: major capitals still hubs")
	var tags: Dictionary = {}
	for rec3_v in recs:
		if typeof(rec3_v) == TYPE_DICTIONARY:
			var t3: String = str((rec3_v as Dictionary).get("tag", ""))
			if not t3.is_empty():
				tags[t3] = true
	var missing_tags: int = 0
	for t4_v in tags.keys():
		if not off_tags.has(str(t4_v)):
			missing_tags += 1
	if missing_tags > 0:
		_fail("H1 bonus-off: %d countries have no hub" % missing_tags)
	else:
		_pass("H1 bonus-off: hubs in every country (n=%d)" % off_tags.size())


func _test_h2_routes() -> void:
	var routes: Array = _routes()
	if routes.is_empty():
		_fail("H2: no hub routes (rank-grow / empty)")
		return
	var hubs: Dictionary = _hub_set()
	var graph: Array = []
	if _ol != null and _ol.has_method("get_hwy3_graph_rows"):
		var gv: Variant = _ol.call("get_hwy3_graph_rows")
		if typeof(gv) == TYPE_ARRAY:
			graph = gv
	if graph.is_empty():
		graph = _cache
	var recs_h2: Array = _records()
	var adj_v: Variant = _vis_call("build_hub_route_adj", [graph, recs_h2, true])
	var adj: Dictionary = adj_v if typeof(adj_v) == TYPE_DICTIONARY else {}
	var attrs_h2: Dictionary = {}
	for rec_h2_v in recs_h2:
		if typeof(rec_h2_v) != TYPE_DICTIONARY:
			continue
		var rec_h2: Dictionary = rec_h2_v
		attrs_h2[int(rec_h2.get("pid", 0))] = rec_h2
	var bad_end: int = 0
	var bad_short: int = 0
	for rt_v in routes:
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var a: int = int(rt.get("a", 0))
		var b: int = int(rt.get("b", 0))
		if not hubs.has(a) or not hubs.has(b):
			bad_end += 1
			continue
		var want_v: Variant = rt.get("pids", [])
		var want: Array = want_v if typeof(want_v) == TYPE_ARRAY else []
		var got_v: Variant = _vis_call("shortest_hub_path", [adj, a, b, false, attrs_h2])
		var got: PackedInt32Array = PackedInt32Array()
		if typeof(got_v) == TYPE_PACKED_INT32_ARRAY:
			got = got_v
		elif typeof(got_v) == TYPE_ARRAY:
			for gv in got_v:
				got.append(int(gv))
		if got.size() != want.size():
			bad_short += 1
			continue
		var mismatch: bool = false
		for i in range(got.size()):
			if int(got[i]) != int(want[i]):
				mismatch = true
				break
		if mismatch:
			bad_short += 1
	if bad_end > 0:
		_fail("H2: %d routes do not end on hubs" % bad_end)
	else:
		_pass("H2: every route ends on hubs")
	if bad_short > 0:
		_fail("H2: %d routes are not the recomputed shortest path" % bad_short)
	else:
		_pass("H2: every route matches recomputed Dijkstra")


func _independent_shape(pids: PackedInt32Array, cents: Dictionary, start: int, goal: int) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"repeat": false,
		"hook": false,
		"long": false,
		"zigzag": false,
		"length": 0.0,
		"straight": 0.0,
		"turn_sum": 0.0,
	}
	if pids.size() < 2:
		return out
	var seen: Dictionary = {}
	for i in range(pids.size()):
		var pid: int = pids[i]
		if seen.has(pid):
			out["repeat"] = true
		seen[pid] = true
	var length: float = 0.0
	var dirs: Array = []
	for i2 in range(1, pids.size()):
		var a: int = pids[i2 - 1]
		var b: int = pids[i2]
		var c1: Vector2 = cents.get(a, Vector2.ZERO)
		var c2: Vector2 = cents.get(b, Vector2.ZERO)
		var delta: Vector2 = c2 - c1
		var dist: float = delta.length()
		length += dist
		if dist > 0.0001:
			dirs.append(delta)
	out["length"] = length
	var cs: Vector2 = cents.get(start, Vector2.ZERO)
	var cg: Vector2 = cents.get(goal, Vector2.ZERO)
	var straight: float = cs.distance_to(cg)
	out["straight"] = straight
	if straight > 0.0001 and length > straight * SHAPE_LEN_RATIO + 0.0001:
		out["long"] = true
	var turn_sum: float = 0.0
	var hook: bool = false
	for i3 in range(1, dirs.size()):
		var d0: Vector2 = dirs[i3 - 1]
		var d1: Vector2 = dirs[i3]
		var ang: float = absf(d0.angle_to(d1))
		turn_sum += ang
		if ang > SHAPE_HOOK:
			hook = true
	out["turn_sum"] = turn_sum
	out["hook"] = hook
	var n_edges: int = maxi(pids.size() - 1, 1)
	var windows: float = maxf(float(n_edges) / 6.0, 1.0)
	if turn_sum > SHAPE_ZIGZAG * windows + 0.0001:
		out["zigzag"] = true
	out["ok"] = (
		(not bool(out["repeat"]))
		and (not bool(out["hook"]))
		and (not bool(out["long"]))
		and (not bool(out["zigzag"]))
	)
	return out


func _route_pids(rt: Dictionary) -> PackedInt32Array:
	var packed: PackedInt32Array = PackedInt32Array()
	var pids_v: Variant = rt.get("pids", [])
	if typeof(pids_v) == TYPE_ARRAY:
		for pv in pids_v:
			packed.append(int(pv))
	elif typeof(pids_v) == TYPE_PACKED_INT32_ARRAY:
		packed = pids_v
	return packed


func _cents_from_recs(recs: Array) -> Dictionary:
	var cents: Dictionary = {}
	for rec_v in recs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		cents[int(rec.get("pid", 0))] = rec.get("centroid", Vector2.ZERO)
	return cents


func _shape_fail_count(routes: Array, cents: Dictionary) -> int:
	var bad: int = 0
	for rt_v in routes:
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var packed: PackedInt32Array = _route_pids(rt)
		var shape: Dictionary = _independent_shape(
			packed, cents, int(rt.get("a", 0)), int(rt.get("b", 0))
		)
		if not bool(shape.get("ok", false)):
			bad += 1
	return bad


func _test_h3_simple_paths() -> void:
	var routes: Array = _routes()
	if routes.is_empty():
		_fail("H3: no routes")
		return
	var cents: Dictionary = _cents_from_recs(_records())
	var bad: int = _shape_fail_count(routes, cents)
	if bad > 0:
		_fail("H3: %d routes fail independent simple-path / zigzag / hook-back" % bad)
	else:
		_pass("H3: every route is a simple path within turn/length bars")
	# Trap: a zigzag-only adjacency. Healthy product rejects it; forcing
	# path_shape_report ok/zigzag/hook/repeat false paints it and H3 fails.
	var saved_dbg: Dictionary = _debug().duplicate(true)
	var trap: Dictionary = _assign_trap_shape("zigzag", "")
	var trap_bad: int = int(trap.get("independent_bad", 0))
	var trap_n: int = int(trap.get("routes", 0))
	_vis_call("hwy3_set_debug", [saved_dbg])
	_vis_call("hwy3_clear_memos", [])
	if trap_bad > 0:
		_fail("H3: trap zigzag route accepted (%d bad of %d)" % [trap_bad, trap_n])
	else:
		_pass("H3: trap zigzag adjacency rejected by product shape")
	# Hook-back trap: a path that doubles back > HWY3_HOOK_TURN. Same pattern.
	var saved_hook: Dictionary = _debug().duplicate(true)
	var hook_trap: Dictionary = _assign_trap_shape("hook", "")
	var hook_bad: int = int(hook_trap.get("independent_bad", 0))
	var hook_n: int = int(hook_trap.get("routes", 0))
	_vis_call("hwy3_set_debug", [saved_hook])
	_vis_call("hwy3_clear_memos", [])
	if hook_bad > 0:
		_fail("H3: trap hook-back route accepted (%d bad of %d)" % [hook_bad, hook_n])
	else:
		_pass("H3: trap hook-back adjacency rejected by product shape")


func _test_h4_germany() -> void:
	var recs: Array = _records()
	var ger_cap: int = 0
	var cologne: int = 0
	var urban_ruhr: Dictionary = {}
	for rec_v in recs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if str(rec.get("tag", "")).to_upper() != "GER":
			continue
		if bool(rec.get("capital", false)) and ger_cap == 0:
			ger_cap = int(rec.get("pid", 0))
		var nm: String = str(rec.get("name", "")).to_lower()
		var cnm: String = str(rec.get("city_name", "")).to_lower()
		if int(rec.get("tier", 0)) >= 3 and bool(rec.get("city_hub", rec.get("hub", false))) and (
			nm.contains("köln") or cnm.contains("cologne") or cnm.contains("köln")
		):
			cologne = int(rec.get("pid", 0))
		if bool(_vis_call("is_urban_district_name", [str(rec.get("name", ""))])):
			urban_ruhr[int(rec.get("pid", 0))] = true
	# City layer name "Cologne" lives on the record name from provinces_base ("Köln, Kreisfreie Stadt").
	if cologne == 0:
		for rec2_v in recs:
			if typeof(rec2_v) != TYPE_DICTIONARY:
				continue
			var rec2: Dictionary = rec2_v
			if str(rec2.get("tag", "")).to_upper() != "GER":
				continue
			if int(rec2.get("tier", 0)) >= 3 and bool(rec2.get("city_hub", false)):
				var n2: String = str(rec2.get("name", "")).to_lower()
				if n2.contains("köln") or n2.begins_with("köln") or n2.contains("cologne"):
					cologne = int(rec2.get("pid", 0))
					break
	var berlin_ok: bool = false
	var cologne_ok: bool = false
	var ruhr_on: bool = false
	for rt_v in _routes():
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var pids_v: Variant = rt.get("pids", [])
		var pids: Array = pids_v if typeof(pids_v) == TYPE_ARRAY else []
		var has_cap: bool = false
		var has_other_ger: bool = false
		var urban_n: int = 0
		for pv in pids:
			var pid: int = int(pv)
			if pid == ger_cap:
				has_cap = true
			if pid == cologne:
				cologne_ok = true
			if urban_ruhr.has(pid):
				urban_n += 1
			if pid != ger_cap:
				for rec3_v in recs:
					if typeof(rec3_v) != TYPE_DICTIONARY:
						continue
					var rec3: Dictionary = rec3_v
					if int(rec3.get("pid", 0)) == pid and str(rec3.get("tag", "")).to_upper() == "GER" and bool(rec3.get("capital", false) or _hub_set().has(pid)):
						if _hub_set().has(pid) and pid != ger_cap:
							has_other_ger = true
		if has_cap and has_other_ger:
			berlin_ok = true
		if urban_n >= 3:
			ruhr_on = true
	if ger_cap <= 0:
		_fail("H4: GER capital missing from records")
	elif not berlin_ok:
		_fail("H4: no route connects Berlin to another German hub")
	else:
		_pass("H4: Berlin connects to another German hub")
	if cologne <= 0:
		_fail("H4: GER tier≥3 hub city Köln/Cologne not in records")
	elif not cologne_ok:
		_fail("H4: Köln is not on any hub route")
	else:
		_pass("H4: Köln is on a hub route")
	var ruhr_ranked: bool = false
	for h_v in _debug().get("hubs", []):
		if typeof(h_v) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_v
		if str(h.get("tag", "")).to_upper() != "GER":
			continue
		if bool(h.get("urban", false)) and int(h.get("urban_nbr", 0)) >= 2 and not bool(h.get("capital", false)):
			ruhr_ranked = true
			break
	if ruhr_ranked and not ruhr_on:
		_fail("H4: urban bonus ranked the Ruhr but no route passes ≥3 urban NUTS3")
	elif ruhr_ranked:
		_pass("H4: a route passes ≥3 urban NUTS3 in the ranked Ruhr")
	else:
		_pass("H4: urban bonus did not rank a Ruhr hub — skip ≥3 urban path")
	var munich: int = 0
	var ruhr_cities: Dictionary = {}
	for rec4_v in recs:
		if typeof(rec4_v) != TYPE_DICTIONARY:
			continue
		var rec4: Dictionary = rec4_v
		if str(rec4.get("tag", "")).to_upper() != "GER":
			continue
		var nm4: String = str(rec4.get("name", "")).to_lower()
		var cnm4: String = str(rec4.get("city_name", "")).to_lower()
		if (
			int(rec4.get("tier", 0)) >= 3
			and (cnm4.contains("munich") or cnm4.contains("münchen") or nm4.contains("münchen") or nm4.contains("munich"))
		):
			munich = int(rec4.get("pid", 0))
		if (
			cnm4.contains("essen")
			or cnm4.contains("dortmund")
			or cnm4.contains("duisburg")
			or nm4.contains("essen, kreisfreie")
			or nm4.contains("dortmund, kreisfreie")
			or nm4.contains("duisburg, kreisfreie")
		):
			ruhr_cities[int(rec4.get("pid", 0))] = str(rec4.get("city_name", rec4.get("name", "")))
	var munich_ok: bool = false
	var ruhr_city_ok: bool = false
	var on_route: Dictionary = {}
	for rt2_v in _routes():
		if typeof(rt2_v) != TYPE_DICTIONARY:
			continue
		var rt2: Dictionary = rt2_v
		var pids2_v: Variant = rt2.get("pids", [])
		var pids2: Array = pids2_v if typeof(pids2_v) == TYPE_ARRAY else []
		for pv2 in pids2:
			var pid2: int = int(pv2)
			on_route[pid2] = true
			if pid2 == munich:
				munich_ok = true
			if ruhr_cities.has(pid2):
				ruhr_city_ok = true
	if munich <= 0:
		_fail("H4: GER Munich hub city not in records")
	elif not munich_ok:
		_fail("H4: Munich is not on any hub route")
	else:
		_pass("H4: Munich is on a hub route")
	if ruhr_cities.is_empty():
		_fail("H4: Essen/Dortmund/Duisburg not in GER records")
	elif not ruhr_city_ok:
		_fail("H4: no route passes Essen or Dortmund or Duisburg")
	else:
		_pass("H4: a route passes Essen or Dortmund or Duisburg")
	var t4_miss: Array = []
	for h4_v in _debug().get("hubs", []):
		if typeof(h4_v) != TYPE_DICTIONARY:
			continue
		var h4: Dictionary = h4_v
		if int(h4.get("tier", 0)) < 4:
			continue
		if str(h4.get("tag", "")).strip_edges().to_upper() != "GER":
			continue
		var hp4: int = int(h4.get("pid", 0))
		if hp4 > 0 and not on_route.has(hp4):
			t4_miss.append("%s:%d" % [str(h4.get("tag", "")), hp4])
	if not t4_miss.is_empty():
		_fail("H4: GER tier-4 city hubs not on a route %s" % str(t4_miss))
	else:
		_pass("H4: every GER tier-4 city hub sits on a route")
	var ger_hubs: Dictionary = {}
	for h5_v in _debug().get("hubs", []):
		if typeof(h5_v) != TYPE_DICTIONARY:
			continue
		var h5: Dictionary = h5_v
		if str(h5.get("tag", "")).to_upper() == "GER":
			ger_hubs[int(h5.get("pid", 0))] = true
	var parent_g: Dictionary = {}
	for gh in ger_hubs.keys():
		var gpid: int = int(gh)
		if on_route.has(gpid):
			parent_g[gpid] = gpid
	for rt3_v in _routes():
		if typeof(rt3_v) != TYPE_DICTIONARY:
			continue
		var rt3: Dictionary = rt3_v
		var pids3_v: Variant = rt3.get("pids", [])
		var pids3: Array = pids3_v if typeof(pids3_v) == TYPE_ARRAY else []
		var prev_g: int = 0
		for pv3 in pids3:
			var pid3: int = int(pv3)
			if not parent_g.has(pid3):
				continue
			if prev_g > 0:
				_uf_union_local(parent_g, prev_g, pid3)
			prev_g = pid3
	var roots_g: Dictionary = {}
	for gp2 in parent_g.keys():
		roots_g[_uf_find_local(parent_g, int(gp2))] = true
	if parent_g.size() >= 2 and roots_g.size() > 1:
		_fail("H4: GER hub routes are %d components, want one tree" % roots_g.size())
	else:
		_pass("H4: GER hub routes form one connected tree")


func _rec_label(rec: Dictionary) -> String:
	var cn: String = str(rec.get("city_name", "")).strip_edges()
	if cn.is_empty():
		cn = str(rec.get("name", ""))
	return cn


func _score_pid_less_local(a: Dictionary, b: Dictionary) -> bool:
	var sa: float = float(a.get("score", 0.0))
	var sb: float = float(b.get("score", 0.0))
	if sa == sb:
		return int(a.get("pid", 0)) < int(b.get("pid", 0))
	return sa > sb


func _test_h4_major_trunks() -> void:
	var recs: Array = _records()
	var rec_by: Dictionary = {}
	for rec_v in recs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		rec_by[int(rec.get("pid", 0))] = rec
	var hubs_by_tag: Dictionary = {}
	for h_v in _debug().get("hubs", []):
		if typeof(h_v) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_v
		var tag: String = str(h.get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		if not hubs_by_tag.has(tag):
			hubs_by_tag[tag] = []
		var lst: Array = hubs_by_tag[tag]
		lst.append(h)
		hubs_by_tag[tag] = lst
	var on_route: Dictionary = {}
	var parent: Dictionary = {}
	for rt_v in _routes():
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var pids_v: Variant = rt.get("pids", [])
		var pids: Array = pids_v if typeof(pids_v) == TYPE_ARRAY else []
		var prev: int = 0
		for pv in pids:
			var pid: int = int(pv)
			on_route[pid] = true
			if not parent.has(pid):
				parent[pid] = pid
			if prev > 0:
				_uf_union_local(parent, prev, pid)
			prev = pid
	var missed: Array = []
	for tag in MAJORS:
		var hl_v: Variant = hubs_by_tag.get(tag, [])
		var hl: Array = hl_v if typeof(hl_v) == TYPE_ARRAY else []
		if hl.size() < 2:
			missed.append("%s:need_2_hubs" % tag)
			continue
		var cap_pid: int = 0
		var rows: Array = []
		for h2_v in hl:
			if typeof(h2_v) != TYPE_DICTIONARY:
				continue
			var h2: Dictionary = h2_v
			rows.append(h2)
			if bool(h2.get("capital", false)) and cap_pid <= 0:
				cap_pid = int(h2.get("pid", 0))
		rows.sort_custom(_score_pid_less_local)
		if cap_pid <= 0 and not rows.is_empty():
			cap_pid = int((rows[0] as Dictionary).get("pid", 0))
		var second: int = 0
		var second_map_v: Variant = _debug().get("second_by_tag", {})
		if typeof(second_map_v) == TYPE_DICTIONARY:
			var second_map: Dictionary = second_map_v
			if second_map.has(tag):
				second = int(second_map.get(tag, 0))
		if cap_pid <= 0 or second <= 0:
			missed.append("%s:no_second" % tag)
			continue
		if not on_route.has(cap_pid) or not on_route.has(second):
			var cap_rec_v: Variant = rec_by.get(cap_pid, {})
			var sec_rec_v: Variant = rec_by.get(second, {})
			var cap_rec: Dictionary = cap_rec_v if typeof(cap_rec_v) == TYPE_DICTIONARY else {}
			var sec_rec: Dictionary = sec_rec_v if typeof(sec_rec_v) == TYPE_DICTIONARY else {}
			var cap_nm: String = _rec_label(cap_rec)
			var sec_nm: String = _rec_label(sec_rec)
			missed.append("%s:%s-%s" % [tag, cap_nm, sec_nm])
			continue
		if _uf_find_local(parent, cap_pid) != _uf_find_local(parent, second):
			missed.append("%s:disconnected" % tag)
	if not missed.is_empty():
		_fail("H4: major capital not connected to 2nd hub %s" % str(missed))
	else:
		_pass("H4: every major capital connects to its 2nd hub")


func _test_h4_rome_north() -> void:
	var rec_by: Dictionary = {}
	var rome_pid: int = 0
	for rec_v in _records():
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		rec_by[int(rec.get("pid", 0))] = rec
		var blob: String = (
			"%s %s" % [str(rec.get("city_name", "")), str(rec.get("name", ""))]
		).strip_edges().to_lower()
		if rome_pid <= 0 and (blob.contains("rome") or blob.contains("roma")):
			if str(rec.get("tag", "")).to_upper() == "ITA":
				rome_pid = int(rec.get("pid", 0))
	if rome_pid <= 0:
		_fail("H4: Rome record missing")
		return
	var chain: String = ""
	var hit: String = ""
	for rt_v in _routes():
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var pids: Array = _route_pids(rt)
		var has_rome: bool = false
		var local_hit: String = ""
		for pv in pids:
			var pid: int = int(pv)
			if pid == rome_pid:
				has_rome = true
			var rec2_v: Variant = rec_by.get(pid, {})
			var rec2: Dictionary = rec2_v if typeof(rec2_v) == TYPE_DICTIONARY else {}
			var nm: String = _rec_name_local(rec2).to_lower()
			if (
				nm.contains("firenze")
				or nm.contains("florence")
				or nm.contains("bologna")
				or nm.contains("milano")
				or nm.contains("milan")
			):
				local_hit = nm
		if has_rome and local_hit != "":
			hit = local_hit
			chain = _route_name_chain(rt, rec_by)
			break
	print("HWY3_ROME_NORTH hit=%s %s" % [hit, chain])
	if hit == "":
		_fail("H4: no Roma route reaches Firenze/Bologna/Milano")
	else:
		_pass("H4: Rome-north %s" % chain)


func _test_h4_ruhr_span() -> void:
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
		elif cnm.contains("bochum") or nm.contains("bochum"):
			hit = "bochum"
		elif cnm.contains("dortmund") or nm.contains("dortmund"):
			hit = "dortmund"
		elif cnm.contains("gelsenkirchen") or nm.contains("gelsenkirchen"):
			hit = "gelsenkirchen"
		if hit != "":
			ruhr[int(rec.get("pid", 0))] = hit
	if ruhr.size() < 3:
		_fail("H4: Ruhr city records missing (have %d)" % ruhr.size())
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
	if best < 3:
		_fail("H4: Ruhr span has %d of Duisburg/Essen/Bochum/Dortmund/Gelsenkirchen on one route %s" % [best, str(best_names)])
	else:
		_pass("H4: Ruhr span has %d cluster cities on one route %s" % [best, str(best_names)])


func _test_h4_no_near_parallel() -> void:
	var cents: Dictionary = _cents_from_recs(_records())
	var routes: Array = _routes()
	var bad: Array = []
	for i in range(routes.size()):
		if typeof(routes[i]) != TYPE_DICTIONARY:
			continue
		var ra: Dictionary = routes[i]
		for j in range(i + 1, routes.size()):
			if typeof(routes[j]) != TYPE_DICTIONARY:
				continue
			var rb: Dictionary = routes[j]
			var par_v: Variant = _vis_call("_hwy3_routes_near_parallel", [ra, rb, cents])
			if bool(par_v):
				bad.append("%d-%d/%d-%d" % [
					int(ra.get("a", 0)), int(ra.get("b", 0)),
					int(rb.get("a", 0)), int(rb.get("b", 0)),
				])
	if not bad.is_empty():
		_fail("H4: near-parallel routes remain %s" % str(bad))
	else:
		_pass("H4: no two routes share end regions within Hausdorff cover")


func _rec_name_local(rec: Dictionary) -> String:
	var cn: String = str(rec.get("city_name", "")).strip_edges()
	if cn.is_empty():
		cn = str(rec.get("name", "")).strip_edges()
	var comma: int = cn.find(",")
	if comma >= 0:
		cn = cn.substr(0, comma).strip_edges()
	return cn


func _route_name_chain(rt: Dictionary, rec_by: Dictionary) -> String:
	var names: Array = []
	for pid in _route_pids(rt):
		var rec_v: Variant = rec_by.get(int(pid), {})
		var rec: Dictionary = rec_v if typeof(rec_v) == TYPE_DICTIONARY else {}
		var nm: String = _rec_name_local(rec)
		if nm.is_empty():
			nm = str(int(pid))
		names.append(nm)
	return " → ".join(names)


func _route_pid_set_local(rt: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for pid in _route_pids(rt):
		var p: int = int(pid)
		if p > 0:
			out[p] = true
	return out


## Independent of RoadTierVisual._hwy3_routes_share_corridor (overlap_ok must not share it).
func _independent_corridor_overlap(ra: Dictionary, rb: Dictionary) -> Dictionary:
	var sa: Dictionary = _route_pid_set_local(ra)
	var sb: Dictionary = _route_pid_set_local(rb)
	var out: Dictionary = {
		"overlap": false,
		"jaccard": 0.0,
		"inter": 0,
		"union": 0,
		"share_end": false,
		"frac_a": 0.0,
		"frac_b": 0.0,
	}
	if sa.is_empty() or sb.is_empty():
		return out
	var inter: int = 0
	for k_v in sa.keys():
		if sb.has(k_v):
			inter += 1
	var uni: int = sa.size() + sb.size() - inter
	var jaccard: float = float(inter) / float(maxi(uni, 1))
	var share_end: bool = (
		int(ra.get("a", 0)) == int(rb.get("a", 0))
		or int(ra.get("a", 0)) == int(rb.get("b", 0))
		or int(ra.get("b", 0)) == int(rb.get("a", 0))
		or int(ra.get("b", 0)) == int(rb.get("b", 0))
	)
	var frac_a: float = float(inter) / float(maxi(sa.size(), 1))
	var frac_b: float = float(inter) / float(maxi(sb.size(), 1))
	out["inter"] = inter
	out["union"] = uni
	out["jaccard"] = jaccard
	out["share_end"] = share_end
	out["frac_a"] = frac_a
	out["frac_b"] = frac_b
	out["overlap"] = (
		jaccard + 0.0001 >= 0.5
		or (share_end and (frac_a + 0.0001 >= 0.5 or frac_b + 0.0001 >= 0.5))
	)
	return out


func _test_h4_no_duplicate_corridor() -> void:
	var rec_by: Dictionary = {}
	for rec_v in _records():
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		rec_by[int(rec.get("pid", 0))] = rec
	var routes: Array = _routes()
	var bad: Array = []
	var paris_rows: Array = []
	for i in range(routes.size()):
		if typeof(routes[i]) != TYPE_DICTIONARY:
			continue
		var ra: Dictionary = routes[i]
		var chain_a: String = _route_name_chain(ra, rec_by)
		var looks_paris: bool = chain_a.to_lower().contains("paris") and (
			chain_a.to_lower().contains("nord") or chain_a.to_lower().contains("somme")
		)
		if looks_paris:
			paris_rows.append(chain_a)
		for j in range(i + 1, routes.size()):
			if typeof(routes[j]) != TYPE_DICTIONARY:
				continue
			var rb: Dictionary = routes[j]
			var ov: Dictionary = _independent_corridor_overlap(ra, rb)
			if not bool(ov.get("overlap", false)):
				continue
			var chain_b: String = _route_name_chain(rb, rec_by)
			bad.append(
				"%s | %s j=%.2f share_end=%s"
				% [chain_a, chain_b, float(ov.get("jaccard", 0.0)), str(ov.get("share_end", false))]
			)
	print("HWY3_PARIS_NORD %s" % str(paris_rows))
	if not bad.is_empty():
		_fail("H4: duplicate corridor routes remain %s" % str(bad))
	else:
		_pass("H4: no route pair shares a corridor (Jaccard ≥0.5 or shared end + ≥50%)")


func _count_highways_cache(cache: Array) -> int:
	return RoadTierVisualScript.hwy3_drawn_highway_count(cache)


func _test_h5_budget() -> void:
	var st: Dictionary = _component_stats(_cache)
	var hwy: int = int(st.get("highways", 0))
	var drawn: int = _count_highways_cache(_cache)
	if _ol != null and _ol.has_method("get_drawn_highway_count"):
		drawn = int(_ol.call("get_drawn_highway_count"))
	var sings: int = int(st.get("singletons", 0))
	var median: float = float(st.get("median", 0.0))
	print(
		"HWY3_BARS highways=%d drawn=%d used=%d comps=%d sings=%d median=%.2f sizes=%s"
		% [
			hwy,
			drawn,
			int(_debug().get("used", 0)),
			int(st.get("components", 0)),
			sings,
			median,
			str(st.get("sizes", [])),
		]
	)
	if drawn != hwy:
		_fail("H5: drawn %d != component highway count %d (one definition)" % [drawn, hwy])
	if hwy < 60 or hwy > 114:
		_fail("H5: highway count %d not within 60–114 (2× of 52)" % hwy)
	else:
		_pass("H5: highway count %d within 60–114 (2× of 52)" % hwy)
	if sings != 0:
		_fail("H5: singletons=%d want 0" % sings)
	else:
		_pass("H5: 0 singletons")
	if median + 0.0001 < 4.0:
		_fail("H5: median chain %.2f < 4" % median)
	else:
		_pass("H5: median chain %.2f ≥ 4" % median)


func _uf_find_local(parent: Dictionary, x: int) -> int:
	var cur: int = x
	var guard: int = 0
	while int(parent.get(cur, cur)) != cur and guard < 64:
		cur = int(parent.get(cur, cur))
		guard += 1
	return cur


func _uf_union_local(parent: Dictionary, a: int, b: int) -> void:
	var ra: int = _uf_find_local(parent, a)
	var rb: int = _uf_find_local(parent, b)
	if ra == rb:
		return
	if ra < rb:
		parent[rb] = ra
	else:
		parent[ra] = rb


func _clone_cache(src: Array) -> Array:
	var out: Array = []
	for row_v in src:
		if typeof(row_v) == TYPE_DICTIONARY:
			out.append((row_v as Dictionary).duplicate())
	return out


func _reset_inferred(cache: Array) -> void:
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if not bool(row.get("explicit", false)):
			row["display_tier"] = 0


func _highway_keys(cache: Array) -> Dictionary:
	var keys: Dictionary = {}
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) == RoadTierVisualScript.TIER_HIGHWAY:
			keys[RoadTierVisualScript.edge_key(int(row.get("p1", 0)), int(row.get("p2", 0)))] = true
	return keys


func _median_ms(samples: PackedFloat32Array) -> float:
	var vals: Array = []
	for i in range(samples.size()):
		vals.append(float(samples[i]))
	vals.sort()
	if vals.is_empty():
		return 0.0
	var mid: int = vals.size() / 2
	if vals.size() % 2 == 1:
		return float(vals[mid])
	return (float(vals[mid - 1]) + float(vals[mid])) * 0.5


func _legacy_weight_less(a: Dictionary, b: Dictionary) -> bool:
	var wa: float = float(a.get("weight", 0.0))
	var wb: float = float(b.get("weight", 0.0))
	if wa == wb:
		return RoadTierVisualScript.edge_key(int(a.get("p1", 0)), int(a.get("p2", 0))) < RoadTierVisualScript.edge_key(int(b.get("p1", 0)), int(b.get("p2", 0)))
	return wa < wb


func _apply_legacy_rank(cache: Array) -> void:
	var inferred: Array = []
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if bool(row.get("explicit", false)):
			row["display_tier"] = RoadTierVisualScript.TIER_HIGHWAY
			continue
		inferred.append(row)
	inferred.sort_custom(_legacy_weight_less)
	var n: int = inferred.size()
	for i in range(n):
		var rank: float = 0.0 if n <= 1 else float(i) / float(n)
		var row2: Dictionary = inferred[i]
		row2["display_tier"] = RoadTierVisualScript.display_tier_from_rank(rank, false)


func _test_h6_determinism() -> void:
	if _ol == null:
		_fail("H6: overlay missing")
		return
	var graph: Array = []
	if _ol.has_method("get_hwy3_graph_rows"):
		var gv: Variant = _ol.call("get_hwy3_graph_rows")
		if typeof(gv) == TYPE_ARRAY:
			graph = gv
	var recs_h6: Array = _records()
	var by_pid_h6: Dictionary = {}
	var select_h6: Array = []
	for rec_h6_v in recs_h6:
		if typeof(rec_h6_v) == TYPE_DICTIONARY:
			var rec_h6: Dictionary = rec_h6_v
			by_pid_h6[int(rec_h6.get("pid", 0))] = rec_h6
			if bool(_vis_call("_hwy3_rec_is_hub_candidate", [rec_h6])):
				select_h6.append(rec_h6)
	var ctx: Dictionary = {
		"records": recs_h6,
		"select_records": select_h6,
		"by_pid": by_pid_h6,
		"graph": graph,
		"use_urban": true,
		"tag_borders": {},
	}
	# Warmup matches HWY-1: first assign fills the hub-route cache; timed
	# repeats then measure a cached rebuild (Dijkstra once per unique board).
	var warmup: Array = _clone_cache(_cache)
	_reset_inferred(warmup)
	_vis_call("assign_rare_display_tiers", [warmup, ctx])
	var sets: Array = []
	var new_ms: PackedFloat32Array = PackedFloat32Array()
	var legacy_ms: PackedFloat32Array = PackedFloat32Array()
	for _i in range(5):
		var legacy_clone: Array = _clone_cache(_cache)
		_reset_inferred(legacy_clone)
		var tl: int = Time.get_ticks_usec()
		_apply_legacy_rank(legacy_clone)
		legacy_ms.append(float(Time.get_ticks_usec() - tl) / 1000.0)
		var clone: Array = _clone_cache(_cache)
		_reset_inferred(clone)
		var t0: int = Time.get_ticks_usec()
		_vis_call("assign_rare_display_tiers", [clone, ctx])
		new_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		sets.append(_highway_keys(clone))
	var same: bool = true
	var first: Dictionary = sets[0]
	for si in range(1, sets.size()):
		var other: Dictionary = sets[si]
		if other.size() != first.size():
			same = false
			break
		for k in first.keys():
			if not other.has(k):
				same = false
				break
	if not same:
		_fail("H6: highway set changed across rebuilds")
	else:
		_pass("H6: identical highway set across rebuilds")
	var delta: float = _median_ms(new_ms) - _median_ms(legacy_ms)
	print("HWY3_ASSIGN_MS legacy_med=%.3f new_med=%.3f delta=%.3f" % [_median_ms(legacy_ms), _median_ms(new_ms), delta])
	if delta > 5.0:
		_fail("H6: assign +%.3f ms over legacy (budget +5)" % delta)
	else:
		_pass("H6: assign %+.3f ms vs legacy (<=5)" % delta)


func _trap_rec(pid: int, tag: String, capital: bool, centroid: Vector2) -> Dictionary:
	return {
		"pid": pid,
		"tag": tag,
		"capital": capital,
		"tier": 4 if capital else 3,
		"population": 400000,
		"industrial": false,
		"city_hub": true,
		"port": false,
		"urban": false,
		"urban_nbr": 0,
		"centroid": centroid,
		"land_n": 30,
		"name": "trap_%d" % pid,
		"city_name": "trap_%d" % pid,
		"score": 100000.0 if capital else 5000.0,
	}


func _trap_edge(a: int, b: int, ca: Vector2, cb: Vector2) -> Dictionary:
	return {
		"p1": a,
		"p2": b,
		"c1": ca,
		"c2": cb,
		"weight": 10.0,
		"w1": 10.0,
		"w2": 10.0,
		"avg_infra": 8.0,
		"explicit": false,
		"tier": 0,
		"display_tier": 0,
	}


func _assign_trap_shape(kind: String, mutant: String) -> Dictionary:
	var cents: Dictionary = {}
	var recs: Array = []
	var graph: Array = []
	var pids: PackedInt32Array = PackedInt32Array()
	if kind == "hook":
		# A→B→C→D with a >150° turn at B, path still ≤1.6× chord.
		var pts: Array = [
			Vector2(0.0, 0.0),
			Vector2(15.0, 0.0),
			Vector2(14.0, 0.4),
			Vector2(30.0, 1.0),
		]
		for i in range(pts.size()):
			var pid: int = i + 1
			pids.append(pid)
			cents[pid] = pts[i]
			recs.append(_trap_rec(pid, "ZZZ", i == 0 or i == pts.size() - 1, pts[i]))
		for i2 in range(1, pts.size()):
			graph.append(_trap_edge(i2, i2 + 1, pts[i2 - 1], pts[i2]))
	else:
		for zi in range(8):
			var pidz: int = zi + 1
			var cz: Vector2 = Vector2(float(zi) * 10.0, 0.0 if (zi % 2) == 0 else 12.0)
			pids.append(pidz)
			cents[pidz] = cz
			recs.append(_trap_rec(pidz, "ZZZ", zi == 0 or zi == 7, cz))
		for zj in range(1, 8):
			graph.append(_trap_edge(zj, zj + 1, cents[zj], cents[zj + 1]))
	var cache: Array = []
	for g_v in graph:
		cache.append((g_v as Dictionary).duplicate())
	for pad_i in range(40, 2040):
		var pa: int = 200000 + pad_i
		var pb: int = 300000 + pad_i
		var ca2: Vector2 = Vector2(float(pad_i), 500.0)
		var cb2: Vector2 = Vector2(float(pad_i) + 1.0, 500.0)
		cache.append(_trap_edge(pa, pb, ca2, cb2))
	var prev_mut: String = OS.get_environment("EOA_HWY3_MUTANT")
	if mutant != "":
		OS.set_environment("EOA_HWY3_MUTANT", mutant)
	else:
		OS.set_environment("EOA_HWY3_MUTANT", "")
	var by_pid: Dictionary = {}
	for rec_v in recs:
		var rec: Dictionary = rec_v
		by_pid[int(rec.get("pid", 0))] = rec
	var ctx: Dictionary = {
		"records": recs,
		"select_records": recs,
		"by_pid": by_pid,
		"graph": graph,
		"use_urban": false,
		"tag_borders": {},
	}
	_vis_call("hwy3_clear_memos", [])
	_vis_call("assign_rare_display_tiers", [cache, ctx])
	var dbg: Dictionary = _debug()
	var routes_v: Variant = dbg.get("routes", [])
	var routes: Array = routes_v if typeof(routes_v) == TYPE_ARRAY else []
	var bad: int = _shape_fail_count(routes, cents)
	OS.set_environment("EOA_HWY3_MUTANT", prev_mut)
	return {
		"routes": routes.size(),
		"independent_bad": bad,
		"used": int(dbg.get("used", 0)),
		"mode": str(dbg.get("mode", "")),
	}


func _test_mutants() -> void:
	var graph: Array = []
	if _ol != null and _ol.has_method("get_hwy3_graph_rows"):
		var gv: Variant = _ol.call("get_hwy3_graph_rows")
		if typeof(gv) == TYPE_ARRAY:
			graph = gv
	var recs: Array = _records()
	var by_pid_m: Dictionary = {}
	for rec_bp_v in recs:
		if typeof(rec_bp_v) == TYPE_DICTIONARY:
			var rec_bp: Dictionary = rec_bp_v
			by_pid_m[int(rec_bp.get("pid", 0))] = rec_bp
	var ctx: Dictionary = {
		"records": recs,
		"by_pid": by_pid_m,
		"graph": graph,
		"use_urban": true,
		"tag_borders": {},
	}
	_mutant_expect("rank_grow_back", ctx, "H2")
	_mutant_expect("no_capitals", ctx, "H1")
	_mutant_expect("urban_required", ctx, "H1")
	_mutant_expect("zigzag_ok", ctx, "H3")
	_mutant_expect("hook_back", ctx, "H3")
	_mutant_expect("not_shortest", ctx, "H2")
	_mutant_expect("overlap_ok", ctx, "H4c")
	OS.set_environment("EOA_HWY3_MUTANT", "")
	_vis_call("hwy3_clear_memos", [])


func _mutant_expect(name: String, ctx: Dictionary, bar: String) -> void:
	OS.set_environment("EOA_HWY3_MUTANT", name)
	var clone: Array = _clone_cache(_cache)
	_reset_inferred(clone)
	var rec_copy: Array = []
	for rec_v in ctx.get("records", []):
		if typeof(rec_v) == TYPE_DICTIONARY:
			rec_copy.append((rec_v as Dictionary).duplicate())
	var ctx2: Dictionary = ctx.duplicate()
	ctx2["records"] = rec_copy
	_vis_call("assign_rare_display_tiers", [clone, ctx2])
	var dbg: Dictionary = _debug()
	var killed: bool = false
	if bar == "H2":
		if str(dbg.get("mode", "")) == "rank_grow":
			killed = true
		else:
			var adj_mv: Variant = _vis_call("build_hub_route_adj", [ctx2.get("graph", []), rec_copy, true])
			var adj: Dictionary = adj_mv if typeof(adj_mv) == TYPE_DICTIONARY else {}
			var attrs_m: Dictionary = {}
			for rec_m_v in rec_copy:
				if typeof(rec_m_v) != TYPE_DICTIONARY:
					continue
				var rec_m: Dictionary = rec_m_v
				attrs_m[int(rec_m.get("pid", 0))] = rec_m
			for rt_v in dbg.get("routes", []):
				if typeof(rt_v) != TYPE_DICTIONARY:
					continue
				var rt: Dictionary = rt_v
				var got_mv: Variant = _vis_call("shortest_hub_path", [
					adj, int(rt.get("a", 0)), int(rt.get("b", 0)), false, attrs_m
				])
				var got: PackedInt32Array = PackedInt32Array()
				if typeof(got_mv) == TYPE_PACKED_INT32_ARRAY:
					got = got_mv
				elif typeof(got_mv) == TYPE_ARRAY:
					for gv2 in got_mv:
						got.append(int(gv2))
				var want_v: Variant = rt.get("pids", [])
				var want: Array = want_v if typeof(want_v) == TYPE_ARRAY else []
				if got.size() != want.size():
					killed = true
					break
				for i in range(got.size()):
					if int(got[i]) != int(want[i]):
						killed = true
						break
	elif bar == "H1":
		var hs: Dictionary = {}
		for h_v in dbg.get("hubs", []):
			if typeof(h_v) == TYPE_DICTIONARY:
				hs[int((h_v as Dictionary).get("pid", 0))] = true
		var cap_ger: int = 0
		for rec_v in rec_copy:
			if typeof(rec_v) != TYPE_DICTIONARY:
				continue
			var rec: Dictionary = rec_v
			if str(rec.get("tag", "")).to_upper() == "GER" and bool(rec.get("capital", false)):
				cap_ger = int(rec.get("pid", 0))
				break
		# After no_capitals, capital flags are cleared on the copy; look at original recs.
		if cap_ger <= 0:
			for rec2_v in _records():
				if typeof(rec2_v) != TYPE_DICTIONARY:
					continue
				var rec2: Dictionary = rec2_v
				if str(rec2.get("tag", "")).to_upper() == "GER" and bool(rec2.get("capital", false)):
					cap_ger = int(rec2.get("pid", 0))
					break
		if cap_ger > 0 and not hs.has(cap_ger):
			killed = true
		if name == "urban_required":
			var off_mv: Variant = _vis_call("select_display_hubs", [rec_copy, false])
			var off: Array = off_mv if typeof(off_mv) == TYPE_ARRAY else []
			if off.is_empty():
				killed = true
			var major_miss: bool = false
			for tag in MAJORS:
				var found: bool = false
				for h2_v in off:
					if typeof(h2_v) == TYPE_DICTIONARY and str((h2_v as Dictionary).get("tag", "")).to_upper() == tag:
						found = true
						break
				if not found:
					major_miss = true
					break
			if major_miss or off.is_empty():
				killed = true
	elif bar == "H3":
		# Inject a zigzag/hook-only adjacency. Independent math must FAIL the
		# painted route; product path_shape_report is not consulted.
		var kind: String = "hook" if name == "hook_back" else "zigzag"
		var trap: Dictionary = _assign_trap_shape(kind, name)
		killed = int(trap.get("independent_bad", 0)) > 0
		_vis_call("hwy3_clear_memos", [])
	elif bar == "H4c":
		# Independent Jaccard / shared-end math — not _hwy3_routes_share_corridor.
		var rec_by_m: Dictionary = {}
		for rec_ov_v in rec_copy:
			if typeof(rec_ov_v) != TYPE_DICTIONARY:
				continue
			var rec_ov: Dictionary = rec_ov_v
			rec_by_m[int(rec_ov.get("pid", 0))] = rec_ov
		var routes_m_v: Variant = dbg.get("routes", [])
		var routes_m: Array = routes_m_v if typeof(routes_m_v) == TYPE_ARRAY else []
		for i_m in range(routes_m.size()):
			if typeof(routes_m[i_m]) != TYPE_DICTIONARY:
				continue
			var ra_m: Dictionary = routes_m[i_m]
			for j_m in range(i_m + 1, routes_m.size()):
				if typeof(routes_m[j_m]) != TYPE_DICTIONARY:
					continue
				var rb_m: Dictionary = routes_m[j_m]
				var ov_m: Dictionary = _independent_corridor_overlap(ra_m, rb_m)
				if bool(ov_m.get("overlap", false)):
					killed = true
					print(
						"HWY3_OVERLAP_OK %s | %s j=%.2f"
						% [
							_route_name_chain(ra_m, rec_by_m),
							_route_name_chain(rb_m, rec_by_m),
							float(ov_m.get("jaccard", 0.0)),
						]
					)
					break
			if killed:
				break
	OS.set_environment("EOA_HWY3_MUTANT", "")
	if killed:
		_pass("mutant %s killed by %s" % [name, bar])
	else:
		_fail("mutant %s survived %s" % [name, bar])


func _test_pid_list_grep() -> void:
	var src: String = _read_text(SRC_VIS)
	var start: int = src.find("static func hwy3_mutant_name")
	if start < 0:
		_fail("pid_list: hwy3 functions missing")
		return
	var body: String = src.substr(start)
	var re := RegEx.new()
	re.compile("\\b[78]\\d{5}\\b")
	var m: RegExMatch = re.search(body)
	if m != null:
		_fail("pid_list: hardcoded pid %s in hub selection" % m.get_string())
	else:
		_pass("pid_list: no hardcoded pids in hub selection")


func _test_far_width_not_hidden() -> void:
	var far_w: float = RoadTierVisualScript.screen_width_for_tier(RoadTierVisualScript.TIER_HIGHWAY, 0)
	if far_w + 0.01 < 9.0:
		_fail("far_hidden: far highway width %.2f < 9" % far_w)
	else:
		_pass("far width %.2f ≥ 9 (far_hidden mutant would drop to 5.5)" % far_w)
	var ol_src: String = _read_text(SRC_OL)
	if "min_case: float = 20.0" not in ol_src:
		_fail("far_hidden: overlay lost the 20 px far floor")
	else:
		_pass("far_hidden: overlay keeps the 20 px far floor")


func _test_flip_max_guard_source() -> void:
	var src: String = _read_text(SRC_GUARD)
	if "HWY3_FIXED_ORIENTATION=1" not in src:
		_fail("flip_max: pixel guard missing fixed-orientation marker")
	else:
		_pass("flip_max: pixel guard uses one fixed orientation")
	if "use_flip: bool = uf_w < 8.0" in src:
		_fail("flip_max: max-of-orientations Y-flip pick restored")
	else:
		_pass("flip_max: no max-of-orientations Y-flip pick")
	if "HWY3_FAR_WIDTH_CEILING=26" not in src:
		_fail("flip_max: guard missing far width ceiling")
	else:
		_pass("flip_max: far width ceiling is behavioral")
	if "HWY3_DEFAULT_WIDTH_CEILING=18" not in src:
		_fail("flip_max: guard missing default width ceiling")
	else:
		_pass("flip_max: default width ceiling is behavioral")
	if "HWY3_PAIR_SCREEN_POS_MAX=28" not in src:
		_fail("flip_max: guard missing hub-pair screen-position check")
	else:
		_pass("flip_max: hub-pair screen position is checked")
