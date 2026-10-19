extends SceneTree

## ROADS-1 FIX: no drawn highway east of Lithuania may be an orphan stub
## (a component that is not connected to the NUTS network and is too small
## to be a real RoW hub network). Must FAIL on c5590af7 (Moscow–BLR stub
## still drawn) and PASS after the filter honors endpoints / network.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRoads1LithuaniaStubTest.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_VIS := "res://scripts/map/RoadTierVisual.gd"
const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const ECON_PATH := "res://data/provinces_world_accurate/province_economy_layer.json"
const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const VILNIUS := 710967
const MOSCOW := 903534
const BLR_EAST := 905809
const NETWORK_MIN_EDGES := 3

var _failures: int = 0
var _ol: Node2D = null
var _cache: Array = []


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRoads1LithuaniaStubTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRoads1LithuaniaStubTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok: bool = _failures == 0
	print("HeadlessRoads1LithuaniaStubTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRoads1LithuaniaStubTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_overlay_honors_endpoint_check()
	if not _boot_live_1936():
		return
	_test_no_east_lithuania_orphan()
	_test_stub_report_lists_demoted()
	_test_hub_routes_kept()
	if _ol != null:
		_ol.queue_free()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


func _test_overlay_honors_endpoint_check() -> void:
	var ol: String = _read_text(SRC_OL)
	if "highway_endpoints_in_rings" not in ol:
		_fail("overlay must call highway_endpoints_in_rings")
		return
	## c5590af7 calls the helper and discards the bool. The result must gate draw.
	if "if in_rings" not in ol and "if not in_rings" not in ol:
		_fail("overlay must honor highway_endpoints_in_rings (c5590af7 discarded the bool)")
		return
	_pass("overlay honors highway_endpoints_in_rings")


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
	for row_v in base_rows_v:
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
	for grow_v in geo_rows_v:
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


func _drawn_highways() -> Array:
	var out: Array = []
	if _ol != null and _ol.has_method("get_road_tier_draw"):
		var node_v: Variant = _ol.call("get_road_tier_draw", 2)
		if node_v is Node2D and "edges" in node_v:
			var ev: Variant = node_v.get("edges")
			if typeof(ev) == TYPE_ARRAY:
				for row_v in ev:
					if typeof(row_v) == TYPE_DICTIONARY:
						out.append(row_v)
	if not out.is_empty():
		return out
	for row_v2 in _cache:
		if typeof(row_v2) != TYPE_DICTIONARY:
			continue
		if int((row_v2 as Dictionary).get("display_tier", 0)) == RoadTierVisualScript.TIER_HIGHWAY:
			out.append(row_v2)
	return out


func _component_info(edges: Array) -> Dictionary:
	var parent: Dictionary = {}
	for row_v in edges:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if a <= 0 or b <= 0:
			continue
		RoadTierVisualScript._uf_union(parent, a, b)
	var edges_by_root: Dictionary = {}
	var nuts_by_root: Dictionary = {}
	for row2_v in edges:
		if typeof(row2_v) != TYPE_DICTIONARY:
			continue
		var row2: Dictionary = row2_v
		var a2: int = int(row2.get("p1", 0))
		var b2: int = int(row2.get("p2", 0))
		if a2 <= 0 or b2 <= 0:
			continue
		var root: int = RoadTierVisualScript._uf_find(parent, a2)
		edges_by_root[root] = int(edges_by_root.get(root, 0)) + 1
		if RoadTierVisualScript.is_nuts3_pid(a2) or RoadTierVisualScript.is_nuts3_pid(b2):
			nuts_by_root[root] = true
	return {
		"parent": parent,
		"edges_by_root": edges_by_root,
		"nuts_by_root": nuts_by_root,
	}


func _edge_on_connected_route(info: Dictionary, p1: int, p2: int) -> bool:
	var parent_v: Variant = info.get("parent", {})
	var parent: Dictionary = parent_v if typeof(parent_v) == TYPE_DICTIONARY else {}
	if p1 <= 0 or p2 <= 0 or parent.is_empty():
		return false
	var root: int = RoadTierVisualScript._uf_find(parent, p1)
	var n: int = int((info.get("edges_by_root", {}) as Dictionary).get(root, 0))
	var nuts: bool = bool((info.get("nuts_by_root", {}) as Dictionary).get(root, false))
	return nuts or n >= NETWORK_MIN_EDGES


func _test_no_east_lithuania_orphan() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null or not mm.has_method("get_province_centroid"):
		_fail("MapManager centroid missing")
		return
	var vil: Vector2 = mm.get_province_centroid(VILNIUS)
	if vil == Vector2.ZERO:
		_fail("Vilnius centroid missing")
		return
	var drawn: Array = _drawn_highways()
	var info: Dictionary = _component_info(drawn)
	var orphans: Array = []
	var east_n: int = 0
	for row_v in drawn:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var p1: int = int(row.get("p1", 0))
		var p2: int = int(row.get("p2", 0))
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		if minf(c1.x, c2.x) + 0.01 < vil.x:
			continue
		east_n += 1
		var key: String = RoadTierVisualScript.edge_key(p1, p2)
		if _edge_on_connected_route(info, p1, p2):
			continue
		orphans.append("%s c1=%s c2=%s" % [key, str(c1), str(c2)])
	var moscow_key: String = RoadTierVisualScript.edge_key(MOSCOW, BLR_EAST)
	var moscow_drawn: bool = false
	for row2_v in drawn:
		if typeof(row2_v) != TYPE_DICTIONARY:
			continue
		var row2: Dictionary = row2_v
		if RoadTierVisualScript.edge_key(int(row2.get("p1", 0)), int(row2.get("p2", 0))) == moscow_key:
			moscow_drawn = true
			break
	print(
		"ROADS1_LIT_STUB east_n=%d orphans=%d moscow_blr_drawn=%s vil_x=%.1f drawn=%d"
		% [east_n, orphans.size(), str(moscow_drawn), vil.x, drawn.size()]
	)
	for o in orphans:
		print("ROADS1_LIT_ORPHAN %s" % str(o))
	if moscow_drawn:
		_fail("Moscow–BLR highway stub still drawn (c5590af7)")
	if not orphans.is_empty():
		_fail("drawn highway east of Lithuania lacks a connected route: %s" % str(orphans))
	elif not moscow_drawn:
		_pass("no east-of-Lithuania highway lacks a connected route")


func _test_stub_report_lists_demoted() -> void:
	if _ol == null or not _ol.has_method("get_highway_stub_report"):
		_fail("get_highway_stub_report missing")
		return
	var report_v: Variant = _ol.call("get_highway_stub_report")
	if typeof(report_v) != TYPE_DICTIONARY:
		_fail("stub report is not a Dictionary")
		return
	var report: Dictionary = report_v
	var n: int = int(report.get("dropped_n", -1))
	var keys_v: Variant = report.get("dropped", [])
	var keys: Array = keys_v if typeof(keys_v) == TYPE_ARRAY else []
	var edges_v: Variant = report.get("edges", [])
	var edges: Array = edges_v if typeof(edges_v) == TYPE_ARRAY else []
	var want_a: String = RoadTierVisualScript.edge_key(MOSCOW, BLR_EAST)
	var want_b: String = RoadTierVisualScript.edge_key(905807, BLR_EAST)
	var have_a: bool = keys.has(want_a)
	var have_b: bool = keys.has(want_b)
	var named: int = 0
	for ev in edges:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = ev
		print(
			"ROADS1_STUB_EDGE %s %d %s — %d %s"
			% [str(e.get("key", "")), int(e.get("p1", 0)), str(e.get("n1", "")), int(e.get("p2", 0)), str(e.get("n2", ""))]
		)
		if not str(e.get("n1", "")).is_empty() and not str(e.get("n2", "")).is_empty():
			named += 1
	print("ROADS1_STUB_REPORT n=%d keys=%s named=%d" % [n, str(keys), named])
	if n < 2 or not have_a or not have_b:
		_fail("stub report must list demoted Moscow stub edges (n=%d)" % n)
	elif named < 2:
		_fail("stub report must name the demoted provinces")
	else:
		_pass("stub report lists demoted Belarus→Moscow edges by pid + name")


func _test_hub_routes_kept() -> void:
	var dbg: Dictionary = {}
	if "static func hwy3_debug" in _read_text(SRC_VIS):
		var dv: Variant = RoadTierVisualScript.hwy3_debug()
		if typeof(dv) == TYPE_DICTIONARY:
			dbg = dv
	var routes_v: Variant = dbg.get("routes", [])
	var routes: Array = routes_v if typeof(routes_v) == TYPE_ARRAY else []
	var route_keys: Dictionary = {}
	for rt_v in routes:
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var pids_v: Variant = (rt_v as Dictionary).get("pids", [])
		var pids: Array = pids_v if typeof(pids_v) == TYPE_ARRAY else []
		for i in range(pids.size() - 1):
			route_keys[RoadTierVisualScript.edge_key(int(pids[i]), int(pids[i + 1]))] = true
	var drawn: Array = _drawn_highways()
	var drawn_keys: Dictionary = {}
	for row_v in drawn:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		drawn_keys[RoadTierVisualScript.edge_key(int(row.get("p1", 0)), int(row.get("p2", 0)))] = true
	var missing: Array = []
	var stub_key: String = RoadTierVisualScript.edge_key(MOSCOW, BLR_EAST)
	for k_v in route_keys.keys():
		var k: String = str(k_v)
		if k == stub_key or k == RoadTierVisualScript.edge_key(905807, BLR_EAST):
			continue
		if not drawn_keys.has(k):
			missing.append(k)
	print(
		"ROADS1_LIT_ROUTES routes=%d route_keys=%d drawn=%d missing_non_stub=%d"
		% [routes.size(), route_keys.size(), drawn_keys.size(), missing.size()]
	)
	if routes.size() != 18:
		_fail("want 18 HWY-3 hub routes, got %d" % routes.size())
	elif missing.is_empty():
		_pass("18 HWY-3 hub routes kept (non-stub route edges drawn)")
	else:
		_fail("hub-route edges missing from draw: %s" % str(missing))
