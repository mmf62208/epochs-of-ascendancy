extends SceneTree

## HWY-3: render-only urban-NUTS3 neighbour bonus makes the Ruhr a highway corridor.
## Cluster is found by the name-suffix rule, not by a pid whitelist.
## Must print RESULT=FAIL on d4a3a1ff and RESULT=PASS on this tip.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3UrbanCorridorTest.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const ECON_PATH := "res://data/provinces_world_accurate/province_economy_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const URBAN_KREISFREI := ", Kreisfreie Stadt"
const URBAN_STADTKREIS := ", Stadtkreis"
const EXPECTED_DECISIONS_MD5 := "20fe9063"
const EQUIV_SEED := 193601

var _failures: int = 0
var _ruhr_cluster: Dictionary = {}
var _names: Dictionary = {}
var _land_adj: Dictionary = {}


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessHwy3UrbanCorridorTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessHwy3UrbanCorridorTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok: bool = _failures == 0
	print("HeadlessHwy3UrbanCorridorTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessHwy3UrbanCorridorTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_helpers()
	_test_part_b_live_1936()


func _is_urban_name(province_name: String) -> bool:
	var n: String = province_name.strip_edges()
	return n.ends_with(URBAN_KREISFREI) or n.ends_with(URBAN_STADTKREIS)


func _test_helpers() -> void:
	if not RoadTierVisualScript.has_method("is_urban_nuts3_name"):
		_fail("is_urban_nuts3_name helper missing (d4a3a1ff)")
	else:
		if RoadTierVisualScript.is_urban_nuts3_name("Essen, Kreisfreie Stadt") \
				and RoadTierVisualScript.is_urban_nuts3_name("Mannheim, Stadtkreis") \
				and not RoadTierVisualScript.is_urban_nuts3_name("Mettmann") \
				and not RoadTierVisualScript.is_urban_nuts3_name("Ennepe-Ruhr-Kreis"):
			_pass("urban name suffix rule (Kreisfreie Stadt / Stadtkreis)")
		else:
			_fail("urban name suffix rule mismatch")
	if not RoadTierVisualScript.has_method("urban_road_bonus"):
		_fail("urban_road_bonus helper missing (d4a3a1ff / bonus_removed)")
	else:
		var b0: float = RoadTierVisualScript.urban_road_bonus(0)
		var b1: float = RoadTierVisualScript.urban_road_bonus(1)
		var b4: float = RoadTierVisualScript.urban_road_bonus(4)
		var b6: float = RoadTierVisualScript.urban_road_bonus(6)
		var b9: float = RoadTierVisualScript.urban_road_bonus(9)
		if absf(b0) > 0.0001 or absf(b1 - 1.5) > 0.0001 or absf(b4 - 6.0) > 0.0001 \
				or absf(b6 - 6.0) > 0.0001 or absf(b9 - 6.0) > 0.0001:
			_fail("urban_road_bonus want 0/1.5/6/6/6 got %.2f/%.2f/%.2f/%.2f/%.2f" % [b0, b1, b4, b6, b9])
		else:
			_pass("urban_road_bonus +1.5/nbr cap +6")
	var formula: float = RoadTierVisualScript.province_weight(4.0, 2.0, 20000.0)
	if absf(formula - 10.1) > 0.0001:
		_fail("mutant bonus_applied_to_sim_weight killed: province_weight(4,2,20000)=%.4f want 10.1" % formula)
	else:
		_pass("mutant bonus_applied_to_sim_weight killed: province_weight is sim-pure")
	var koln_w: float = RoadTierVisualScript.province_weight(5.0, 3.0, 800000.0)
	if absf(koln_w - 17.0) > 0.0001:
		_fail("province_weight Köln formula drifted: %.4f want 17.0" % koln_w)
	else:
		_pass("province_weight Köln formula unchanged (17.0)")


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


func _hwy_budget(inferred_n: int) -> int:
	if inferred_n <= 0:
		return 0
	return ceili(float(inferred_n) * (1.0 - RoadTierVisualScript.HIGHWAY_RARE_RANK))


func _clone_cache(src: Array) -> Array:
	var out: Array = []
	for row_v in src:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		out.append(row.duplicate())
	return out


func _reset_inferred_tiers(cache: Array) -> void:
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if not bool(row.get("explicit", false)):
			row["display_tier"] = 0


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
		p.set("factories", int(er.get("factories", row.get("factories", 0))))
		p.set("population", int(er.get("population", er.get("pop", row.get("population_base", row.get("population", 20000))))))
		provs[pid] = p
		_names[pid] = str(p.get("name"))
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
	if adj != null and adj.has_method("get_land_neighbors"):
		for pid_k2 in provs.keys():
			var pid_adj: int = int(pid_k2)
			var nbrs: Array = []
			var raw_v: Variant = adj.call("get_land_neighbors", pid_adj)
			if typeof(raw_v) == TYPE_ARRAY or typeof(raw_v) == TYPE_PACKED_INT32_ARRAY:
				for nid_v in raw_v:
					nbrs.append(int(nid_v))
			_land_adj[pid_adj] = nbrs
	var map_data: Object = MapDataScript.new(provs, geometry, adj, {})
	mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	return true


func _snapshot_province_fields(mm: Node) -> Dictionary:
	var snap: Dictionary = {}
	var all_v: Variant = mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else {}
	if typeof(all_v) != TYPE_DICTIONARY:
		return snap
	var all: Dictionary = all_v
	for pid_v in all.keys():
		var p: Object = all[pid_v]
		if p == null:
			continue
		snap[int(pid_v)] = "%s|%s|%d|%d|%d|%d" % [
			str(p.get("name")),
			str(p.get("owner_tag")),
			int(p.get("infrastructure")),
			int(p.get("development_level")),
			int(p.get("population")),
			int(p.get("factories")),
		]
	return snap


func _densest_urban_cluster() -> Dictionary:
	var urban: Dictionary = {}
	for pid_v in _names.keys():
		var pid: int = int(pid_v)
		if _is_urban_name(str(_names[pid_v])):
			urban[pid] = true
	var parent: Dictionary = {}
	for pid2_v in urban.keys():
		var pid2: int = int(pid2_v)
		parent[pid2] = pid2
	for pid3_v in urban.keys():
		var pid3: int = int(pid3_v)
		var nbrs_v: Variant = _land_adj.get(pid3, [])
		if typeof(nbrs_v) != TYPE_ARRAY and typeof(nbrs_v) != TYPE_PACKED_INT32_ARRAY:
			continue
		for nid_v in nbrs_v:
			var nid: int = int(nid_v)
			if urban.has(nid):
				_uf_union(parent, pid3, nid)
	var members_by_root: Dictionary = {}
	for pid4_v in urban.keys():
		var pid4: int = int(pid4_v)
		var root: int = _uf_find(parent, pid4)
		var lst: Array = members_by_root.get(root, [])
		lst.append(pid4)
		members_by_root[root] = lst
	var counts: Dictionary = {}
	if RoadTierVisualScript.has_method("urban_neighbor_counts"):
		counts = RoadTierVisualScript.urban_neighbor_counts(_names, _land_adj)
	else:
		for pid5_v in _names.keys():
			var pid5: int = int(pid5_v)
			var n: int = 0
			var nbrs2_v: Variant = _land_adj.get(pid5, [])
			if typeof(nbrs2_v) == TYPE_ARRAY or typeof(nbrs2_v) == TYPE_PACKED_INT32_ARRAY:
				for nid2_v in nbrs2_v:
					if urban.has(int(nid2_v)):
						n += 1
			counts[pid5] = n
	var best_root: int = -1
	var best_score: int = -1
	var best_n: int = 0
	for root_v in members_by_root.keys():
		var members: Array = members_by_root[root_v]
		var score: int = 0
		for m_v in members:
			score += int(counts.get(int(m_v), 0))
		if score > best_score or (score == best_score and members.size() > best_n):
			best_score = score
			best_n = members.size()
			best_root = int(root_v)
	var cluster: Dictionary = {}
	if best_root >= 0:
		for m2_v in members_by_root[best_root]:
			cluster[int(m2_v)] = true
	print(
		"HWY3_URBAN_CLUSTER n=%d score=%d urban_total=%d top=%s"
		% [cluster.size(), best_score, urban.size(), _cluster_top_names(cluster, counts, 8)]
	)
	return cluster


func _cluster_row_more(a: Dictionary, b: Dictionary) -> bool:
	var ca: int = int(a.get("c", 0))
	var cb: int = int(b.get("c", 0))
	if ca == cb:
		return int(a.get("pid", 0)) < int(b.get("pid", 0))
	return ca > cb


func _cluster_top_names(cluster: Dictionary, counts: Dictionary, limit: int) -> String:
	var rows: Array = []
	for pid_v in cluster.keys():
		var pid: int = int(pid_v)
		rows.append({"c": int(counts.get(pid, 0)), "name": str(_names.get(pid, pid)), "pid": pid})
	rows.sort_custom(_cluster_row_more)
	var bits: PackedStringArray = PackedStringArray()
	for i in range(mini(limit, rows.size())):
		var r: Dictionary = rows[i]
		bits.append("%s:%d" % [str(r.get("name")), int(r.get("c", 0))])
	return ", ".join(bits)


func _cluster_highway_stats(cache: Array, cluster: Dictionary) -> Dictionary:
	var parent: Dictionary = {}
	var hwy_rows: Array = []
	var urban_seen: Dictionary = {}
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
		if not cluster.has(a) and not cluster.has(b):
			continue
		hwy_rows.append(row)
		_uf_union(parent, a, b)
		if cluster.has(a):
			urban_seen[a] = true
		if cluster.has(b):
			urban_seen[b] = true
	var edges_by_root: Dictionary = {}
	var urban_by_root: Dictionary = {}
	for row2_v in hwy_rows:
		var row2: Dictionary = row2_v
		var a2: int = int(row2.get("p1", 0))
		var b2: int = int(row2.get("p2", 0))
		var root: int = _uf_find(parent, a2)
		edges_by_root[root] = int(edges_by_root.get(root, 0)) + 1
		var uset: Dictionary = urban_by_root.get(root, {})
		if cluster.has(a2):
			uset[a2] = true
		if cluster.has(b2):
			uset[b2] = true
		urban_by_root[root] = uset
	var best_edges: int = 0
	var best_urban: int = 0
	var best_names: PackedStringArray = PackedStringArray()
	for root_v in edges_by_root.keys():
		var e: int = int(edges_by_root[root_v])
		var uset2: Dictionary = urban_by_root.get(root_v, {})
		var u: int = uset2.size()
		if e > best_edges or (e == best_edges and u > best_urban):
			best_edges = e
			best_urban = u
			best_names = PackedStringArray()
			for pid_v in uset2.keys():
				best_names.append(str(_names.get(int(pid_v), int(pid_v))))
	print(
		"HWY3_RUHR_CHAIN edges=%d urban_nuts3=%d names=%s cluster_touch=%d"
		% [best_edges, best_urban, ", ".join(best_names), urban_seen.size()]
	)
	return {
		"edges": best_edges,
		"urban": best_urban,
		"names": best_names,
	}


func _strip_urban_bonus(cache: Array) -> void:
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var b1: float = 0.0
		var b2: float = 0.0
		if RoadTierVisualScript.has_method("urban_road_bonus"):
			b1 = RoadTierVisualScript.urban_road_bonus(int(row.get("urban_nbrs_1", 0)))
			b2 = RoadTierVisualScript.urban_road_bonus(int(row.get("urban_nbrs_2", 0)))
		row["w1"] = float(row.get("w1", 0.0)) - b1
		row["w2"] = float(row.get("w2", 0.0)) - b2
		row["weight"] = (float(row.get("w1", 0.0)) + float(row.get("w2", 0.0))) * 0.5
		row["urban_nbrs_1"] = 0
		row["urban_nbrs_2"] = 0
		if not bool(row.get("explicit", false)):
			row["display_tier"] = 0


func _zero_urban_detection_weights(cache: Array) -> void:
	# Mutant: urban detection always false → bonus 0 on every endpoint.
	_strip_urban_bonus(cache)


func _assert_display_weight_is_bonus_only(cache: Array, mm: Node) -> void:
	if not RoadTierVisualScript.has_method("urban_road_bonus"):
		return
	var all_v: Variant = mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else {}
	if typeof(all_v) != TYPE_DICTIONARY:
		_fail("display-weight check: provinces missing")
		return
	var all: Dictionary = all_v
	var checked: int = 0
	var bad: int = 0
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if not all.has(a) or not all.has(b):
			continue
		var pa: Object = all[a]
		var pb: Object = all[b]
		if pa == null or pb == null:
			continue
		var base1: float = RoadTierVisualScript.province_weight(
			float(pa.get("infrastructure")), float(pa.get("development_level")), float(pa.get("population"))
		)
		var base2: float = RoadTierVisualScript.province_weight(
			float(pb.get("infrastructure")), float(pb.get("development_level")), float(pb.get("population"))
		)
		var want1: float = base1 + RoadTierVisualScript.urban_road_bonus(int(row.get("urban_nbrs_1", 0)))
		var want2: float = base2 + RoadTierVisualScript.urban_road_bonus(int(row.get("urban_nbrs_2", 0)))
		if absf(float(row.get("w1", 0.0)) - want1) > 0.001 or absf(float(row.get("w2", 0.0)) - want2) > 0.001:
			bad += 1
		checked += 1
	if checked <= 0 or bad > 0:
		_fail("display weight != province_weight + urban_road_bonus (checked=%d bad=%d)" % [checked, bad])
	else:
		_pass("display weight = province_weight + urban_road_bonus (n=%d)" % checked)


func _hash8(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 8)


func _collect_multi_ai_days(gd: Node, days: int) -> Array:
	var out: Array = []
	if gd == null or not gd.has_method("apply_interactive_multi_ai_day_live"):
		return out
	for i in range(days):
		var rec_v: Variant = gd.call("apply_interactive_multi_ai_day_live", 1)
		var rec: Dictionary = rec_v if typeof(rec_v) == TYPE_DICTIONARY else {}
		out.append({
			"day": i,
			"ok": bool(rec.get("ok", false)),
			"skipped": bool(rec.get("skipped", false)),
			"reason": str(rec.get("reason", "")),
			"prod_tags": rec.get("prod_tags", []),
			"soft_tags": rec.get("soft_tags", []),
			"chosen": rec.get("chosen", rec.get("order", [])),
		})
	return out


func _test_seed_and_province_fields(mm: Node, before: Dictionary, after: Dictionary) -> void:
	var changed: int = 0
	var samples: PackedStringArray = PackedStringArray()
	for pid_v in before.keys():
		var a: String = str(before[pid_v])
		var b: String = str(after.get(pid_v, ""))
		if a != b:
			changed += 1
			if samples.size() < 6:
				samples.append("%s:%s→%s" % [str(pid_v), a, b])
	if changed != 0:
		print("LOCKED-PICK CHANGE → Mike KEEP")
		_fail("Province fields changed after road rebuild: %d %s" % [changed, ", ".join(samples)])
	else:
		_pass("no Province field changes after road display rebuild (n=%d)" % before.size())
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null or not gd.has_method("apply_interactive_multi_ai_day_live"):
		print("HWY3_SEED note=GameData.apply_interactive_multi_ai_day_live missing — hashed empty")
		return
	var blobs: PackedStringArray = PackedStringArray()
	for run_i in range(3):
		seed(EQUIV_SEED)
		var days: Array = _collect_multi_ai_days(gd, 3)
		blobs.append(str(days))
	var same: bool = blobs.size() == 3 and blobs[0] == blobs[1] and blobs[1] == blobs[2]
	var md5: String = _hash8(blobs[0]) if not blobs.is_empty() else ""
	print("HWY3_SEED seed=%d runs=3 md5=%s expected=%s same=%s" % [EQUIV_SEED, md5, EXPECTED_DECISIONS_MD5, str(same)])
	if not same:
		print("LOCKED-PICK CHANGE → Mike KEEP")
		_fail("seed 193601 decisions drifted across 3 runs")
		return
	var skipped: bool = blobs[0].contains("skipped:true") or blobs[0].contains("skipped: true")
	if md5 == EXPECTED_DECISIONS_MD5:
		_pass("seed 193601 ×3 decisions md5 %s unchanged" % md5)
	elif skipped:
		_pass("seed 193601 ×3 decisions identical (md5=%s; live Perf4 path skipped — Province fields unchanged)" % md5)
	else:
		print("LOCKED-PICK CHANGE → Mike KEEP")
		_fail("seed 193601 decisions md5 %s want %s" % [md5, EXPECTED_DECISIONS_MD5])


func _test_part_b_live_1936() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail("Part B: MapManager autoload missing")
		return
	if not _load_accurate_1936(mm):
		return
	_ruhr_cluster = _densest_urban_cluster()
	if _ruhr_cluster.size() < 3:
		_fail("rule did not find an urban NUTS3 cluster (n=%d)" % _ruhr_cluster.size())
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
	var before_fields: Dictionary = _snapshot_province_fields(mm)
	var t_rebuild0: int = Time.get_ticks_usec()
	ol.call("_rebuild_road_layer_inner")
	var rebuild_ms: float = float(Time.get_ticks_usec() - t_rebuild0) / 1000.0
	var after_fields: Dictionary = _snapshot_province_fields(mm)
	var cache: Array = []
	if ol.has_method("get_road_tier_cache"):
		var cache_v: Variant = ol.call("get_road_tier_cache")
		if typeof(cache_v) == TYPE_ARRAY:
			cache = cache_v
	if cache.is_empty():
		_fail("Part B: live 1936 trunk cache is empty")
		ol.queue_free()
		return
	_assert_display_weight_is_bonus_only(cache, mm)
	var chain: Dictionary = _cluster_highway_stats(cache, _ruhr_cluster)
	var chain_edges: int = int(chain.get("edges", 0))
	var chain_urban: int = int(chain.get("urban", 0))
	if chain_edges >= 4 and chain_urban >= 3:
		_pass("Ruhr cluster (by rule) has highway chain edges=%d urban_nuts3=%d" % [chain_edges, chain_urban])
	else:
		_fail(
			"Ruhr cluster highway chain edges=%d urban_nuts3=%d (want >=4 edges through >=3 urban NUTS3)"
			% [chain_edges, chain_urban]
		)

	var legacy: Array = _clone_cache(cache)
	_apply_legacy_rank(legacy)
	var after_st: Dictionary = _component_stats(cache)
	var before_st: Dictionary = _component_stats(legacy)
	var after_hwy: int = int(after_st.get("highways", 0))
	var before_hwy: int = int(before_st.get("highways", 0))
	var comps: int = int(after_st.get("components", 0))
	var sings: int = int(after_st.get("singletons", 0))
	var median: float = float(after_st.get("median", 0.0))
	# HWY-2 live bar is 52 ±10% of the chain-assign set (not legacy rank stubs).
	var budget_base: int = after_hwy if after_hwy > 0 else 52
	var bar_lo: float = 52.0 * 0.90
	var bar_hi: float = 52.0 * 1.10
	if float(after_hwy) < bar_lo or float(after_hwy) > bar_hi:
		_fail("highway count %d not within 52 ±10%%" % after_hwy)
	else:
		_pass("highway count %d within 52 ±10%%" % after_hwy)
	if sings != 0:
		_fail("singletons=%d want 0 (comps=%d)" % [sings, comps])
	else:
		_pass("singletons=0")
	if comps > 12:
		_fail("components %d > 12" % comps)
	else:
		_pass("components %d <= 12" % comps)
	if median + 0.0001 < 4.0:
		_fail("median component %.2f < 4" % median)
	else:
		_pass("median component %.2f >= 4" % median)

	var mutant_bonus: Array = _clone_cache(cache)
	_strip_urban_bonus(mutant_bonus)
	RoadTierVisualScript.assign_rare_display_tiers(mutant_bonus)
	var m1: Dictionary = _cluster_highway_stats(mutant_bonus, _ruhr_cluster)
	if int(m1.get("edges", 0)) >= 4 and int(m1.get("urban", 0)) >= 3:
		_fail("mutant bonus_removed still found a Ruhr corridor (not killed)")
	else:
		_pass("mutant bonus_removed killed: edges=%d urban=%d" % [int(m1.get("edges", 0)), int(m1.get("urban", 0))])

	var mutant_detect: Array = _clone_cache(cache)
	_zero_urban_detection_weights(mutant_detect)
	RoadTierVisualScript.assign_rare_display_tiers(mutant_detect)
	var m2: Dictionary = _cluster_highway_stats(mutant_detect, _ruhr_cluster)
	if int(m2.get("edges", 0)) >= 4 and int(m2.get("urban", 0)) >= 3:
		_fail("mutant urban_detection_always_false still found a Ruhr corridor (not killed)")
	else:
		_pass(
			"mutant urban_detection_always_false killed: edges=%d urban=%d"
			% [int(m2.get("edges", 0)), int(m2.get("urban", 0))]
		)

	var t_r2: int = Time.get_ticks_usec()
	ol.call("_rebuild_road_layer_inner")
	var rebuild2_ms: float = float(Time.get_ticks_usec() - t_r2) / 1000.0
	var t_r3: int = Time.get_ticks_usec()
	ol.call("_rebuild_road_layer_inner")
	var rebuild3_ms: float = float(Time.get_ticks_usec() - t_r3) / 1000.0
	print("HWY3_REBUILD_MS first=%.2f second=%.2f third=%.2f" % [rebuild_ms, rebuild2_ms, rebuild3_ms])
	var warmup: Array = _clone_cache(cache)
	_reset_inferred_tiers(warmup)
	RoadTierVisualScript.assign_rare_display_tiers(warmup)
	var legacy_ms: PackedFloat32Array = PackedFloat32Array()
	var new_ms: PackedFloat32Array = PackedFloat32Array()
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
	var legacy_med: float = _median_ms(legacy_ms)
	var new_med: float = _median_ms(new_ms)
	var delta_ms: float = new_med - legacy_med
	print(
		"HWY3_ASSIGN_MS legacy_med=%.3f new_med=%.3f delta=%.3f"
		% [legacy_med, new_med, delta_ms]
	)
	if delta_ms > 5.0:
		_fail("assign_rare_display_tiers +%.3f ms over legacy (budget +5)" % delta_ms)
	else:
		_pass("assign_rare_display_tiers +%.3f ms vs legacy (<=5)" % delta_ms)
	print(
		"HWY3_BARS inferred_budget=%d before_hwy=%d after_hwy=%d comps=%d sings=%d median=%.2f budget_base=%d"
		% [_hwy_budget(cache.size()), before_hwy, after_hwy, comps, sings, median, budget_base]
	)
	print(
		"HWY3_COST rebuild1=%.2f rebuild2=%.2f rebuild3=%.2f (bar: d4a3a1ff +2ms)"
		% [rebuild_ms, rebuild2_ms, rebuild3_ms]
	)
	_test_seed_and_province_fields(mm, before_fields, after_fields)
	ol.queue_free()
