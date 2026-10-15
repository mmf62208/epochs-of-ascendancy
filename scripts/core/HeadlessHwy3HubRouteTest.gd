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

var _failures: int = 0
var _ol: Node2D = null
var _cache: Array = []


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
	if not _boot_live_1936():
		return
	_test_h1_hubs()
	_test_h2_routes()
	_test_h3_simple_paths()
	_test_h4_germany()
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


func _debug() -> Dictionary:
	return RoadTierVisualScript.last_hwy3_debug


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
		"HWY3_MEASURE mode=%s hubs=%d routes=%d used=%d budget=%d cache=%d adj_ms=%.2f ends=%s"
		% [
			str(dbg.get("mode", "")),
			(_debug().get("hubs", []) as Array).size() if typeof(dbg.get("hubs", [])) == TYPE_ARRAY else 0,
			_routes().size(),
			int(dbg.get("used", 0)),
			int(dbg.get("budget", 0)),
			_cache.size(),
			float(dbg.get("adj_ms", 0.0)),
			str(ends),
		]
	)
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
	var off: Array = RoadTierVisualScript.select_display_hubs(recs, false)
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
	var adj: Dictionary = RoadTierVisualScript.build_hub_route_adj(graph, recs_h2, true)
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
		var got: PackedInt32Array = RoadTierVisualScript.shortest_hub_path(adj, a, b, false, attrs_h2)
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


func _test_h3_simple_paths() -> void:
	var routes: Array = _routes()
	if routes.is_empty():
		_fail("H3: no routes")
		return
	var recs: Array = _records()
	var cents: Dictionary = {}
	for rec_v in recs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		cents[int(rec.get("pid", 0))] = rec.get("centroid", Vector2.ZERO)
	var bad: int = 0
	for rt_v in routes:
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var pids_v: Variant = rt.get("pids", [])
		var packed: PackedInt32Array = PackedInt32Array()
		if typeof(pids_v) == TYPE_ARRAY:
			for pv in pids_v:
				packed.append(int(pv))
		var shape: Dictionary = RoadTierVisualScript.path_shape_report(
			packed, cents, int(rt.get("a", 0)), int(rt.get("b", 0)), ""
		)
		if not bool(shape.get("ok", false)):
			bad += 1
	if bad > 0:
		_fail("H3: %d routes fail simple-path / zigzag / hook-back" % bad)
	else:
		_pass("H3: every route is a simple path within turn/length bars")


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
		if RoadTierVisualScript.is_urban_district_name(str(rec.get("name", ""))):
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


func _test_h5_budget() -> void:
	var st: Dictionary = _component_stats(_cache)
	var hwy: int = int(st.get("highways", 0))
	var sings: int = int(st.get("singletons", 0))
	var median: float = float(st.get("median", 0.0))
	print(
		"HWY3_BARS highways=%d comps=%d sings=%d median=%.2f sizes=%s"
		% [hwy, int(st.get("components", 0)), sings, median, str(st.get("sizes", []))]
	)
	if hwy < 45 or hwy > 59:
		_fail("H5: highway count %d not within 52 ±15%%" % hwy)
	else:
		_pass("H5: highway count %d within 52 ±15%%" % hwy)
	if sings != 0:
		_fail("H5: singletons=%d want 0" % sings)
	else:
		_pass("H5: 0 singletons")
	if median + 0.0001 < 4.0:
		_fail("H5: median chain %.2f < 4" % median)
	else:
		_pass("H5: median chain %.2f ≥ 4" % median)


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
			if RoadTierVisualScript._hwy3_rec_is_hub_candidate(rec_h6):
				select_h6.append(rec_h6)
	var ctx: Dictionary = {
		"records": recs_h6,
		"select_records": select_h6,
		"by_pid": by_pid_h6,
		"graph": graph,
		"use_urban": true,
		"tag_borders": {},
	}
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
		RoadTierVisualScript.assign_rare_display_tiers(clone, ctx)
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
	OS.set_environment("EOA_HWY3_MUTANT", "")


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
	RoadTierVisualScript.assign_rare_display_tiers(clone, ctx2)
	var dbg: Dictionary = _debug()
	var killed: bool = false
	if bar == "H2":
		if str(dbg.get("mode", "")) == "rank_grow":
			killed = true
		else:
			var adj: Dictionary = RoadTierVisualScript.build_hub_route_adj(
				ctx2.get("graph", []), rec_copy, true
			)
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
				var got: PackedInt32Array = RoadTierVisualScript.shortest_hub_path(
					adj, int(rt.get("a", 0)), int(rt.get("b", 0)), false, attrs_m
				)
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
			var off: Array = RoadTierVisualScript.select_display_hubs(rec_copy, false)
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
		# Mutant disables shape checks, so a known-bad polyline must be accepted.
		var cents: Dictionary = {}
		var pids: PackedInt32Array = PackedInt32Array()
		if name == "hook_back":
			pids.append(1)
			pids.append(2)
			pids.append(1)
			cents[1] = Vector2(0, 0)
			cents[2] = Vector2(10, 0)
			var shape_h: Dictionary = RoadTierVisualScript.path_shape_report(pids, cents, 1, 1, name)
			killed = bool(shape_h.get("ok", false))
		else:
			# Alternating zigzag, no vertex repeat; turn sum 2.5π > 1.5π per 6 edges.
			for zi in range(7):
				pids.append(zi + 1)
				cents[zi + 1] = Vector2(float(zi) * 10.0, 0.0 if (zi % 2) == 0 else 10.0)
			var shape_z: Dictionary = RoadTierVisualScript.path_shape_report(
				pids, cents, 1, 7, name
			)
			killed = bool(shape_z.get("ok", false))
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
