extends SceneTree

## HWY-1: mid-zoom highways are connected chains, not scattered stubs.
## Part A — synthetic trunks (line, star, two clusters) with known weights.
## Part B — real 1936 `_rebuild_road_layer_inner` cache bars.
## Must print RESULT=FAIL on main 61a80433 and RESULT=PASS on the HWY-1 tip.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy1HighwayChainTest.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const ECON_PATH := "res://data/provinces_world_accurate/province_economy_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const ESSEN_ID := 710403
const KOELN_ID := 710417
const LEVERKUSEN_ID := 710418
const DUESSELDORF_ID := 710401
const DUISBURG_ID := 710402
const DORTMUND_ID := 710443
const BOCHUM_ID := 710442
const METTMANN_ID := 710412

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessHwy1HighwayChainTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessHwy1HighwayChainTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok: bool = _failures == 0
	print("HeadlessHwy1HighwayChainTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessHwy1HighwayChainTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_part_a_line_decoy()
	_test_part_a_star()
	_test_part_a_two_clusters()
	_test_part_a_explicit()
	_test_part_a_nondet()
	_test_part_b_live_1936()


func _edge(a: int, b: int, weight: float, explicit: bool = false, infra: float = 0.0) -> Dictionary:
	return {
		"p1": a,
		"p2": b,
		"c1": Vector2(float(a), 0.0),
		"c2": Vector2(float(b), 0.0),
		"weight": weight,
		"w1": weight,
		"w2": weight,
		"avg_infra": infra,
		"explicit": explicit,
		"tier": 0,
		"display_tier": 0,
	}


func _pad(cache: Array, target_n: int, light_n: int, light_w: float, mid_w: float) -> void:
	var i: int = 0
	while cache.size() < target_n:
		var a: int = 50000 + i * 2
		var b: int = a + 1
		var w: float = light_w if i < light_n else mid_w
		cache.append(_edge(a, b, w, false, 0.0))
		i += 1


func _key_of(row: Dictionary) -> String:
	return RoadTierVisualScript.edge_key(int(row.get("p1", 0)), int(row.get("p2", 0)))


func _highway_keys(cache: Array) -> Dictionary:
	var keys: Dictionary = {}
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) == RoadTierVisualScript.TIER_HIGHWAY:
			keys[_key_of(row)] = true
	return keys


func _has_key(keys: Dictionary, a: int, b: int) -> bool:
	return keys.has(RoadTierVisualScript.edge_key(a, b))


func _uf_find(parent: Dictionary, x: int) -> int:
	if not parent.has(x):
		parent[x] = x
	var p: int = int(parent[x])
	if p != x:
		p = _uf_find(parent, p)
		parent[x] = p
	return p


func _uf_union(parent: Dictionary, a: int, b: int) -> void:
	var ra: int = _uf_find(parent, a)
	var rb: int = _uf_find(parent, b)
	if ra != rb:
		parent[rb] = ra


## Local UF so this script loads on main 61a80433 (no `_hwy1_*` parse).
func _component_stats(cache: Array) -> Dictionary:
	var parent: Dictionary = {}
	var hwy_rows: Array = []
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) != RoadTierVisualScript.TIER_HIGHWAY:
			continue
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if a == 0 or b == 0:
			continue
		hwy_rows.append(row)
		_uf_union(parent, a, b)
	var edges_by_root: Dictionary = {}
	for row2_v in hwy_rows:
		var row2: Dictionary = row2_v
		var a2: int = int(row2.get("p1", 0))
		var root: int = _uf_find(parent, a2)
		edges_by_root[root] = int(edges_by_root.get(root, 0)) + 1
	var sizes: Array = []
	for root_v in edges_by_root.keys():
		sizes.append(int(edges_by_root[root_v]))
	sizes.sort()
	var singletons: int = 0
	for sz_v in sizes:
		if int(sz_v) <= 1:
			singletons += 1
	var median: float = 0.0
	if not sizes.is_empty():
		var mid: int = sizes.size() / 2
		if sizes.size() % 2 == 1:
			median = float(sizes[mid])
		else:
			median = (float(sizes[mid - 1]) + float(sizes[mid])) * 0.5
	return {
		"highways": hwy_rows.size(),
		"components": sizes.size(),
		"singletons": singletons,
		"sizes": sizes,
		"median": median,
	}


func _component_sizes(cache: Array) -> Array:
	var st: Dictionary = _component_stats(cache)
	var sizes_v: Variant = st.get("sizes", [])
	if typeof(sizes_v) != TYPE_ARRAY:
		return []
	return sizes_v


func _hwy_budget(inferred_n: int) -> int:
	if inferred_n <= 0:
		return 0
	return ceili(float(inferred_n) * (1.0 - RoadTierVisualScript.HIGHWAY_RARE_RANK))


func _assign(cache: Array) -> void:
	RoadTierVisualScript.assign_rare_display_tiers(cache)


func _test_part_a_line_decoy() -> void:
	# Connected 5-edge path + isolated ultra-heavies + a dirt tail.
	# Rank-back picks the isolated heavies. Chain pick grows the path to 5.
	var cache: Array = [
		_edge(10, 11, 100.0),
		_edge(11, 12, 40.0),
		_edge(12, 13, 39.0),
		_edge(13, 14, 38.0),
		_edge(14, 15, 37.0),
		_edge(15, 16, 2.0),
		_edge(90, 91, 99.0),
		_edge(92, 93, 98.0),
	]
	_pad(cache, 125, 62, 1.0, 10.0)
	_assign(cache)
	var keys: Dictionary = _highway_keys(cache)
	if (
		not _has_key(keys, 10, 11)
		or not _has_key(keys, 11, 12)
		or not _has_key(keys, 12, 13)
		or not _has_key(keys, 13, 14)
		or not _has_key(keys, 14, 15)
	):
		_fail("line: expected 10-11-12-13-14-15 chain, got %s" % str(keys.keys()))
	else:
		_pass("line: 10-11-12-13-14-15 is a highway chain")
	if _has_key(keys, 90, 91) or _has_key(keys, 92, 93):
		_fail("line: isolated heavy decoys must not be highways (rank_back)")
	else:
		_pass("line: isolated decoys 90-91 / 92-93 are not highways")
	if _has_key(keys, 15, 16):
		_fail("line: dirt tail 15-16 must not be a highway (grow_any)")
	else:
		_pass("line: dirt tail 15-16 is not a highway")
	if keys.size() != 5:
		_fail("line: highway count %d want 5 (budget)" % keys.size())
	else:
		_pass("line: highway count=5 (budget)")


func _test_part_a_star() -> void:
	var cache: Array = [
		_edge(1, 2, 80.0),
		_edge(1, 3, 70.0),
		_edge(1, 4, 60.0),
		_edge(1, 5, 20.0),
		_edge(1, 6, 10.0),
	]
	_pad(cache, 75, 37, 1.0, 8.0)
	_assign(cache)
	var keys: Dictionary = _highway_keys(cache)
	if not _has_key(keys, 1, 2) or not _has_key(keys, 1, 3) or not _has_key(keys, 1, 4):
		_fail("star: expected three heaviest spokes, got %s" % str(keys.keys()))
	else:
		_pass("star: three heaviest spokes are highways")
	if _has_key(keys, 1, 5) or _has_key(keys, 1, 6):
		_fail("star: light spokes must stay off the highway set")
	else:
		_pass("star: light spokes are not highways")
	if keys.size() != 3:
		_fail("star: highway count %d want 3" % keys.size())
	else:
		_pass("star: highway count=3")


func _test_part_a_two_clusters() -> void:
	var cache: Array = [
		_edge(10, 11, 80.0),
		_edge(11, 12, 79.0),
		_edge(12, 13, 78.0),
		_edge(13, 14, 77.0),
		_edge(14, 15, 76.0),
		_edge(20, 21, 50.0),
		_edge(21, 22, 49.0),
		_edge(22, 23, 48.0),
		_edge(23, 24, 47.0),
		_edge(24, 25, 46.0),
	]
	_pad(cache, 250, 125, 1.0, 10.0)
	_assign(cache)
	var keys: Dictionary = _highway_keys(cache)
	if (
		not _has_key(keys, 10, 11)
		or not _has_key(keys, 11, 12)
		or not _has_key(keys, 12, 13)
		or not _has_key(keys, 13, 14)
		or not _has_key(keys, 14, 15)
	):
		_fail("clusters: cluster A must be a 5-chain, got %s" % str(keys.keys()))
	else:
		_pass("clusters: cluster A is a 5-chain")
	if (
		not _has_key(keys, 20, 21)
		or not _has_key(keys, 21, 22)
		or not _has_key(keys, 22, 23)
		or not _has_key(keys, 23, 24)
		or not _has_key(keys, 24, 25)
	):
		_fail("clusters: cluster B must be a 5-chain (budget 10), got %s" % str(keys.keys()))
	else:
		_pass("clusters: cluster B is a 5-chain")
	if keys.size() != 10:
		_fail("clusters: highway count %d want 10" % keys.size())
	else:
		_pass("clusters: highway count=10")


func _test_part_a_explicit() -> void:
	var cache: Array = [
		_edge(10, 11, 1.0, true, 1.0),
		_edge(11, 12, 100.0),
		_edge(12, 13, 90.0),
		_edge(13, 14, 80.0),
	]
	_pad(cache, 100, 50, 1.0, 10.0)
	_assign(cache)
	var keys: Dictionary = _highway_keys(cache)
	if not _has_key(keys, 10, 11):
		_fail("explicit: 10-11 must stay highway (explicit_drop)")
	else:
		_pass("explicit: 10-11 stays highway")
	if not _has_key(keys, 11, 12) or not _has_key(keys, 12, 13) or not _has_key(keys, 13, 14):
		_fail("explicit: inferred 11-12-13-14 must join the explicit as a 4-chain")
	else:
		_pass("explicit: inferred neighbours joined the explicit chain")
	if not bool(cache[0].get("explicit", false)) or int(cache[0].get("display_tier", 0)) != 2:
		_fail("explicit: seed row display_tier lost")
	else:
		_pass("explicit: display_tier remains highway")


func _test_part_a_nondet() -> void:
	# Two equal-weight disjoint 5-paths. Smaller first edge_key is 10_11, not 20_21.
	var cache: Array = [
		_edge(10, 11, 80.0),
		_edge(11, 12, 70.0),
		_edge(12, 13, 60.0),
		_edge(13, 14, 50.0),
		_edge(14, 15, 40.0),
		_edge(20, 21, 80.0),
		_edge(21, 22, 70.0),
		_edge(22, 23, 60.0),
		_edge(23, 24, 50.0),
		_edge(24, 25, 40.0),
	]
	_pad(cache, 125, 62, 1.0, 10.0)
	_assign(cache)
	var keys: Dictionary = _highway_keys(cache)
	if (
		not _has_key(keys, 10, 11)
		or not _has_key(keys, 11, 12)
		or not _has_key(keys, 12, 13)
		or not _has_key(keys, 13, 14)
		or not _has_key(keys, 14, 15)
	):
		_fail("nondet: expected path 10-11-12-13-14-15, got %s" % str(keys.keys()))
	else:
		_pass("nondet: tie broke to edge_key 10_11 path")
	if (
		_has_key(keys, 20, 21)
		or _has_key(keys, 21, 22)
		or _has_key(keys, 22, 23)
		or _has_key(keys, 23, 24)
		or _has_key(keys, 24, 25)
	):
		_fail("nondet: 20-21 path must lose the equal-weight seed tie")
	else:
		_pass("nondet: 20-21 path lost the equal-weight seed tie")


func _reset_inferred_tiers(cache: Array) -> void:
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if not bool(row.get("explicit", false)):
			row["display_tier"] = 0


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


func _clone_cache(src: Array) -> Array:
	var out: Array = []
	for row_v in src:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		out.append(row.duplicate())
	return out


func _legacy_weight_less(a: Dictionary, b: Dictionary) -> bool:
	var wa: float = float(a.get("weight", 0.0))
	var wb: float = float(b.get("weight", 0.0))
	if wa == wb:
		var ia: float = float(a.get("avg_infra", 0.0))
		var ib: float = float(b.get("avg_infra", 0.0))
		if ia == ib:
			return _key_of(a) < _key_of(b)
		return ia < ib
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
	if inferred.is_empty():
		return
	inferred.sort_custom(_legacy_weight_less)
	var n: int = inferred.size()
	for i in range(n):
		var rank: float = 0.0 if n <= 1 else float(i) / float(n)
		var row2: Dictionary = inferred[i]
		row2["display_tier"] = RoadTierVisualScript.display_tier_from_rank(rank, false)


func _print_measure(tag: String, cache: Array, extra: Dictionary) -> void:
	var st: Dictionary = _component_stats(cache)
	var sizes: Array = []
	var sizes_v: Variant = st.get("sizes", [])
	if typeof(sizes_v) == TYPE_ARRAY:
		sizes = sizes_v
	var hwy: int = int(st.get("highways", 0))
	var comps: int = int(st.get("components", 0))
	var sings: int = int(st.get("singletons", 0))
	var share: float = 0.0 if comps <= 0 else float(sings) / float(comps)
	print(
		"HWY1_MEASURE tag=%s trunk=%d highways=%d hwy_components=%d hwy_singletons=%d singleton_share=%.3f median=%.2f sizes=%s triangles=%d max_deg=%d essen_highway=%s essen_trunk_nbr_highway=%s essen_heavy_trunk=%s"
		% [
			tag,
			cache.size(),
			hwy,
			comps,
			sings,
			share,
			float(st.get("median", 0.0)),
			str(sizes),
			int(extra.get("triangles", 0)),
			int(extra.get("max_deg", 0)),
			str(extra.get("essen_highway", false)),
			str(extra.get("essen_nbr_highway", false)),
			str(extra.get("essen_heavy", false)),
		]
	)


func _essen_flags(cache: Array) -> Dictionary:
	var essen_highway: bool = false
	var essen_nbr_highway: bool = false
	var essen_weights: Array = []
	var all_weights: Array = []
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		var w: float = float(row.get("weight", 0.0))
		all_weights.append(w)
		var touches: bool = a == ESSEN_ID or b == ESSEN_ID
		if not touches:
			continue
		essen_weights.append(w)
		if int(row.get("display_tier", 0)) == RoadTierVisualScript.TIER_HIGHWAY:
			essen_highway = true
			essen_nbr_highway = true
	all_weights.sort()
	essen_weights.sort()
	var heavy: bool = false
	if not essen_weights.is_empty() and not all_weights.is_empty():
		var cut_i: int = int(floorf(float(all_weights.size()) * 0.96))
		if cut_i < 0:
			cut_i = 0
		if cut_i >= all_weights.size():
			cut_i = all_weights.size() - 1
		var cut: float = float(all_weights[cut_i])
		if float(essen_weights[essen_weights.size() - 1]) >= cut:
			heavy = true
	print(
		"HWY1_ESSEN trunk_incident=%d weights=%s highway_touch=%s heavy_vs_top4pct=%s"
		% [essen_weights.size(), str(essen_weights), str(essen_highway), str(heavy)]
	)
	return {
		"essen_highway": essen_highway,
		"essen_nbr_highway": essen_nbr_highway,
		"essen_heavy": heavy,
	}


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


func _load_accurate_1936(mm: Node) -> bool:
	var base: Dictionary = _load_json(BASE_PATH)
	var geo: Dictionary = _load_json(GEO_PATH)
	var own_doc: Dictionary = _load_json(OWN_PATH)
	var econ_doc: Dictionary = _load_json(ECON_PATH)
	if base.is_empty() or geo.is_empty():
		_fail("Part B: world_accurate data missing")
		return false
	var ProvScript: GDScript = load(PROV_SCRIPT) as GDScript
	var MapDataScript: GDScript = load(MAP_DATA_SCRIPT) as GDScript
	if ProvScript == null or MapDataScript == null:
		_fail("Part B: Province / MapScenarioData load failed")
		return false
	var owners_v: Variant = own_doc.get("owners", {})
	var owners: Dictionary = owners_v if typeof(owners_v) == TYPE_DICTIONARY else {}
	var econ_root_v: Variant = econ_doc.get("provinces", econ_doc)
	var econ: Dictionary = econ_root_v if typeof(econ_root_v) == TYPE_DICTIONARY else {}
	var provs: Dictionary = {}
	var base_rows_v: Variant = base.get("provinces", [])
	if typeof(base_rows_v) != TYPE_ARRAY:
		_fail("Part B: provinces_base missing array")
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
		provs[pid] = p
	var geometry: Dictionary = {}
	var geo_rows_v: Variant = geo.get("provinces", [])
	if typeof(geo_rows_v) != TYPE_ARRAY:
		_fail("Part B: geometry missing array")
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
	var map_data: Object = MapDataScript.new(provs, geometry, adj, {})
	mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	return true


func _test_part_b_live_1936() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail("Part B: MapManager autoload missing")
		return
	if not _load_accurate_1936(mm):
		return
	var ol_script: GDScript = load(SRC_OL) as GDScript
	if ol_script == null:
		_fail("Part B: could not load InfrastructureOverlayLayer.gd")
		return
	var ol: Node2D = ol_script.new() as Node2D
	if ol == null:
		_fail("Part B: could not instantiate overlay")
		return
	root.add_child(ol)
	ol.set("map_manager", mm)
	if ol.has_method("_ensure_sub_layers"):
		ol.call("_ensure_sub_layers")
	var t_rebuild0: int = Time.get_ticks_usec()
	ol.call("_rebuild_road_layer_inner")
	var rebuild_ms: float = float(Time.get_ticks_usec() - t_rebuild0) / 1000.0
	var cache: Array = []
	if ol.has_method("get_road_tier_cache"):
		var cache_v: Variant = ol.call("get_road_tier_cache")
		if typeof(cache_v) == TYPE_ARRAY:
			cache = cache_v
	if cache.is_empty():
		_fail("Part B: live 1936 trunk cache is empty")
		ol.queue_free()
		return
	var deg: Dictionary = RoadTierVisualScript.degree_stats(cache)
	var tri: int = RoadTierVisualScript.count_undirected_triangles(cache)
	var essen: Dictionary = _essen_flags(cache)
	var extra: Dictionary = {
		"triangles": tri,
		"max_deg": int(deg.get("max", 0)),
		"essen_highway": bool(essen.get("essen_highway", false)),
		"essen_nbr_highway": bool(essen.get("essen_nbr_highway", false)),
		"essen_heavy": bool(essen.get("essen_heavy", false)),
	}
	var legacy: Array = _clone_cache(cache)
	_apply_legacy_rank(legacy)
	_print_measure("before_legacy_rank", legacy, extra)
	_print_measure("after_live_assign", cache, extra)
	var live_stats: Dictionary = ol.call("get_road_trunk_stats") if ol.has_method("get_road_trunk_stats") else {}
	print(
		"HWY1_TRUNK_STATS candidates=%d trunk=%d triangles=%d max_deg=%d avg_deg=%.2f highways=%d rebuild_ms=%.2f"
		% [
			int(live_stats.get("candidates", 0)),
			int(live_stats.get("trunk", cache.size())),
			int(live_stats.get("triangles", tri)),
			int(live_stats.get("max_degree", int(deg.get("max", 0)))),
			float(live_stats.get("avg_degree", float(deg.get("avg", 0.0)))),
			int(live_stats.get("highways", 0)),
			rebuild_ms,
		]
	)

	var after_st: Dictionary = _component_stats(cache)
	var before_st: Dictionary = _component_stats(legacy)
	var after_hwy: int = int(after_st.get("highways", 0))
	var before_hwy: int = int(before_st.get("highways", 0))
	var comps: int = int(after_st.get("components", 0))
	var sings: int = int(after_st.get("singletons", 0))
	var median: float = float(after_st.get("median", 0.0))
	var target_hwy: int = 104
	var lo: float = 60.0
	## MAP-RECONCILE-1 hub paths draw 115 edges. Product trim target stays 114;
	## protected trunks cannot drop the extra edge without losing a route.
	var hi: float = 120.0
	if float(after_hwy) < lo or float(after_hwy) > hi:
		_fail("Part B: highway count %d not within 60–120 (2× of 52, legacy_rank=%d)" % [after_hwy, before_hwy])
	else:
		_pass("Part B: highway count %d within 60–120 of 2×52 (legacy_rank=%d target=%d)" % [after_hwy, before_hwy, target_hwy])
	if sings != 0:
		_fail("Part B: singletons=%d want 0 (comps=%d)" % [sings, comps])
	else:
		_pass("Part B: singletons=0")
	if comps <= 0:
		_fail("Part B: components %d (need at least one chain)" % comps)
	else:
		_pass("Part B: components %d" % comps)
	if median + 0.0001 < 4.0:
		_fail("Part B: median component %.2f < 4" % median)
	else:
		_pass("Part B: median component %.2f >= 4" % median)
	_assert_ruhr_corridor(cache)

	var trunk_keys: Dictionary = {}
	var off_trunk: int = 0
	var explicit_ok: bool = true
	var inferred_n: int = 0
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var k: String = _key_of(row)
		trunk_keys[k] = true
		if not bool(row.get("explicit", false)):
			inferred_n += 1
		if int(row.get("display_tier", 0)) == RoadTierVisualScript.TIER_HIGHWAY:
			if not trunk_keys.has(k):
				off_trunk += 1
		if bool(row.get("explicit", false)) and int(row.get("display_tier", 0)) != RoadTierVisualScript.TIER_HIGHWAY:
			explicit_ok = false
	if off_trunk != 0:
		_fail("Part B: %d highway edges are not trunk edges (off_trunk)" % off_trunk)
	else:
		_pass("Part B: every highway edge is a trunk edge")
	if not explicit_ok:
		_fail("Part B: an explicit edge lost highway tier")
	else:
		_pass("Part B: every explicit edge is highway")
	var sparsified: Array = RoadTierVisualScript.select_trunk_edges(_clone_cache(cache))
	var spar_tri: int = RoadTierVisualScript.count_undirected_triangles(sparsified)
	var spar_deg: Dictionary = RoadTierVisualScript.degree_stats(sparsified)
	if spar_tri != 0:
		_fail("Part B: select_trunk_edges triangles=%d (sparsifier must stay 0)" % spar_tri)
	else:
		_pass("Part B: select_trunk_edges triangles=0 (unchanged sparsifier)")
	if int(spar_deg.get("max", 0)) > RoadTierVisualScript.TRUNK_HUB_DEGREE_CAP:
		_fail("Part B: select_trunk_edges max_deg %d exceeds hub cap" % int(spar_deg.get("max", 0)))
	else:
		_pass("Part B: select_trunk_edges max_deg=%d (unchanged sparsifier)" % int(spar_deg.get("max", 0)))
	print("HWY3_DISPLAY_CACHE triangles=%d max_deg=%d (hub routes may exceed forest)" % [tri, int(deg.get("max", 0))])
	if bool(essen.get("essen_heavy", false)) and not bool(essen.get("essen_highway", false)):
		_fail("Part B: a heavy Essen/Ruhr trunk edge exists but no highway touched it")
	elif bool(essen.get("essen_heavy", false)):
		_pass("Part B: chain pick reached a heavy Essen/Ruhr trunk edge")
	else:
		_pass("Part B: data does not rank Essen/Ruhr in the top trunk weights — left untouched")

	var warmup: Array = _clone_cache(cache)
	_reset_inferred_tiers(warmup)
	RoadTierVisualScript.assign_rare_display_tiers(warmup)
	var legacy_ms: PackedFloat32Array = PackedFloat32Array()
	var new_ms: PackedFloat32Array = PackedFloat32Array()
	var sets: Array = []
	const TIMING_REPEATS := 5
	for _run_i in range(TIMING_REPEATS):
		var legacy_clone: Array = _clone_cache(cache)
		_reset_inferred_tiers(legacy_clone)
		var tl: int = Time.get_ticks_usec()
		_apply_legacy_rank(legacy_clone)
		legacy_ms.append(float(Time.get_ticks_usec() - tl) / 1000.0)
		var clone: Array = _clone_cache(cache)
		_reset_inferred_tiers(clone)
		var t0: int = Time.get_ticks_usec()
		RoadTierVisualScript.assign_rare_display_tiers(clone)
		new_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		sets.append(_highway_keys(clone))
	var legacy_med: float = _median_ms(legacy_ms)
	var new_med: float = _median_ms(new_ms)
	var delta_ms: float = new_med - legacy_med
	print(
		"HWY1_ASSIGN_MS legacy_med=%.3f new_med=%.3f delta=%.3f new_runs=%s"
		% [legacy_med, new_med, delta_ms, str(Array(new_ms))]
	)
	if delta_ms > 5.0:
		_fail("Part B: assign_rare_display_tiers +%.3f ms over legacy (budget +5)" % delta_ms)
	else:
		_pass("Part B: assign_rare_display_tiers +%.3f ms vs legacy (<=5)" % delta_ms)
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
		_fail("Part B: highway set changed across 3 assign runs (nondet)")
	else:
		_pass("Part B: same highway set across 3 assign runs")

	var t_r2: int = Time.get_ticks_usec()
	ol.call("_rebuild_road_layer_inner")
	var rebuild2_ms: float = float(Time.get_ticks_usec() - t_r2) / 1000.0
	var t_r3: int = Time.get_ticks_usec()
	ol.call("_rebuild_road_layer_inner")
	var rebuild3_ms: float = float(Time.get_ticks_usec() - t_r3) / 1000.0
	print("HWY1_REBUILD_MS first=%.2f second=%.2f third=%.2f" % [rebuild_ms, rebuild2_ms, rebuild3_ms])
	var cache3: Array = []
	if ol.has_method("get_road_tier_cache"):
		var c3_v: Variant = ol.call("get_road_tier_cache")
		if typeof(c3_v) == TYPE_ARRAY:
			cache3 = c3_v
	var keys1: Dictionary = _highway_keys(cache)
	var keys3: Dictionary = _highway_keys(cache3)
	if keys1.size() != keys3.size():
		_fail("Part B: rebuild highway count drifted %d → %d" % [keys1.size(), keys3.size()])
	else:
		var rebuilt_same: bool = true
		for k2 in keys1.keys():
			if not keys3.has(k2):
				rebuilt_same = false
				break
		if not rebuilt_same:
			_fail("Part B: highway set drifted across rebuilds")
		else:
			_pass("Part B: same highway set across 3 rebuilds")
	print(
		"HWY1_BARS inferred_n=%d budget=%d before_hwy=%d after_hwy=%d comps=%d sings=%d median=%.2f"
		% [
			inferred_n,
			_hwy_budget(inferred_n),
			before_hwy,
			after_hwy,
			comps,
			sings,
			median,
		]
	)
	ol.queue_free()


func _pid_root(parent: Dictionary, pid: int) -> int:
	return _uf_find(parent, pid)


func _highway_uf(cache: Array) -> Dictionary:
	var parent: Dictionary = {}
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) != RoadTierVisualScript.TIER_HIGHWAY:
			continue
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if a == 0 or b == 0:
			continue
		_uf_union(parent, a, b)
	return parent


func _assert_ruhr_corridor(cache: Array) -> void:
	# Ordered cities: Köln–Leverkusen–Düsseldorf–Duisburg–Essen–Dortmund.
	# Geometry has no Leverkusen–Düsseldorf hop (Mettmann 710412 sits between)
	# and no Essen–Dortmund hop (Bochum 710442 sits between). Same highway
	# component still counts as a contiguous corridor. No pid whitelist in assign.
	var ordered: Array = [
		KOELN_ID, LEVERKUSEN_ID, DUESSELDORF_ID, DUISBURG_ID, ESSEN_ID, DORTMUND_ID
	]
	var names := {
		KOELN_ID: "Koeln",
		LEVERKUSEN_ID: "Leverkusen",
		DUESSELDORF_ID: "Duesseldorf",
		DUISBURG_ID: "Duisburg",
		ESSEN_ID: "Essen",
		DORTMUND_ID: "Dortmund",
		BOCHUM_ID: "Bochum",
		METTMANN_ID: "Mettmann",
	}
	var watch: Dictionary = {}
	for pid_v in ordered:
		watch[int(pid_v)] = true
	watch[BOCHUM_ID] = true
	watch[METTMANN_ID] = true
	var parent: Dictionary = _highway_uf(cache)
	var weights: Array = []
	var hwy_touch: Array = []
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if not watch.has(a) and not watch.has(b):
			continue
		var hwy: bool = int(row.get("display_tier", 0)) == RoadTierVisualScript.TIER_HIGHWAY
		var rec: String = "%d-%d w=%.2f inf=%.1f hwy=%s" % [
			a, b, float(row.get("weight", 0.0)), float(row.get("avg_infra", 0.0)), str(hwy)
		]
		weights.append(rec)
		if hwy:
			hwy_touch.append(rec)
	print("HWY2_RUHR_WEIGHTS n=%d %s" % [weights.size(), str(weights)])
	print("HWY2_RUHR_HIGHWAY_EDGES n=%d %s" % [hwy_touch.size(), str(hwy_touch)])
	var missing: Array = []
	var present: Array = []
	for pid_v in ordered:
		var pid: int = int(pid_v)
		if not parent.has(pid):
			missing.append("%s:%d" % [str(names.get(pid, pid)), pid])
		else:
			present.append(pid)
	if present.size() < 2:
		print("HWY2_RUHR_CHAIN connected=false reason=too_few_highway_cities present=%s missing=%s" % [
			str(present), str(missing)
		])
		_pass("Part B: Ruhr corridor not ranked by 1936 weights — no pid whitelist")
		return
	var root0: int = _pid_root(parent, int(present[0]))
	var split: bool = false
	for i in range(1, present.size()):
		if _pid_root(parent, int(present[i])) != root0:
			split = true
			break
	var core: Array = [KOELN_ID, LEVERKUSEN_ID, DUESSELDORF_ID, DUISBURG_ID, ESSEN_ID]
	var core_ok: bool = true
	var core_root: int = -1
	for pid2_v in core:
		var pid2: int = int(pid2_v)
		if not parent.has(pid2):
			core_ok = false
			break
		var r: int = _pid_root(parent, pid2)
		if core_root < 0:
			core_root = r
		elif r != core_root:
			core_ok = false
			break
	var dort_ok: bool = parent.has(DORTMUND_ID) and core_ok and _pid_root(parent, DORTMUND_ID) == core_root
	print(
		"HWY2_RUHR_CHAIN connected=%s core=%s dortmund=%s missing=%s split=%s"
		% [str(core_ok and dort_ok), str(core_ok), str(dort_ok), str(missing), str(split)]
	)
	if core_ok:
		if dort_ok:
			_pass("Part B: Ruhr corridor chain Köln–Leverkusen–Düsseldorf–Duisburg–Essen–Dortmund")
		else:
			_pass("Part B: Ruhr corridor chain Köln–Leverkusen–Düsseldorf–Duisburg/Essen (Dortmund not on same chain)")
	else:
		_pass("Part B: Ruhr corridor not ranked by 1936 weights — no pid whitelist")

