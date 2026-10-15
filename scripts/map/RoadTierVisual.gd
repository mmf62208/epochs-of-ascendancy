# scripts/map/RoadTierVisual.gd
## RT-1 Phase 1 — pure road-tier + edge-sanity helpers (visual only).
## Source of truth for the era-relative formula already used by
## InfrastructureOverlayLayer._rebuild_road_layer_inner (no gameplay change).
## Dirt=0, Paved=1, Highway=2. Explicit built_road_neighbors edges are highway.
class_name RoadTierVisual
extends RefCounted

const TIER_DIRT := 0
const TIER_PAVED := 1
const TIER_HIGHWAY := 2

## Screen-pixel design widths (recomputed from zoom in _draw, never world-locked).
const DIRT_SCREEN_PX := 2.6
const PAVED_SCREEN_PX := 4.0
const PAVED_EDGE_SCREEN_PX := 1.2
## Mid: casing 12 (paved+2 at default is 6; 12 reads over red fills, gold mid 28 is ≥1.8×).
## Close: casing 16 (dark outline vs fills; gold close stays 16/20 halo).
## Far: casing 12 so the fixed-pair pixel run is ≥9 px at Europe/Home (measured 7 at 9).
const HIGHWAY_SCREEN_PX := 8.0
const HIGHWAY_CASING_SCREEN_PX := 12.0
const HIGHWAY_CLOSE_CASING_SCREEN_PX := 16.0
const HIGHWAY_CLOSE_CORE_SCREEN_PX := 12.0
const HIGHWAY_STRIPE_SCREEN_PX := 3.2
## Europe/Home only: keep the rare trunk visible without a continent carpet.
const HIGHWAY_FAR_CASING_SCREEN_PX := 12.0
const HIGHWAY_FAR_CORE_SCREEN_PX := 8.0
const DIRT_DASH_SCREEN_PX := 9.0
const DIRT_GAP_SCREEN_PX := 6.0

## Palette: saturated enough to read on political fills (not thin grey).
const DIRT_COLOR := Color(0.84, 0.56, 0.18, 0.96)
const PAVED_COLOR := Color(0.34, 0.36, 0.40, 0.94)
const PAVED_EDGE_COLOR := Color(0.16, 0.17, 0.20, 0.82)
const HIGHWAY_CASING_COLOR := Color(0.05, 0.05, 0.07, 1.0)
const HIGHWAY_CORE_COLOR := Color(0.22, 0.24, 0.28, 1.0)
const HIGHWAY_STRIPE_COLOR := Color(0.98, 0.94, 0.62, 1.0)

## Zoom LOD. Europe Home is ~0.33–0.69 (strategic / low operational). The
## previous FAR_MAX=0.45 left Home in the mid band, so every NUTS3 dirt
## edge painted a continent-wide grey mesh. Keep far above Home so the
## first wheel-in still hides paved. Europe/Home = highways only.
const ZOOM_FAR_MAX := 1.15
const ZOOM_CLOSE_MIN := 2.60
const DIRT_ZOOM_FLOOR := 2.60
## Bonn / Köln / Leverkusen city labels: mid (1.80) and close. Europe Home stays off.
const END_LABEL_ZOOM_MIN := 1.50
const END_LABEL_FONT_PX := 14

## Visual-only trunk. Gameplay adjacency / movement / formula tier stay intact.
## Each province keeps its nearest 1–2 shared-border neighbours; Kruskal then
## drops cycles so the drawn set is a forest (no triangle mesh).
const TRUNK_DEGREE_CAP := 2
const TRUNK_HUB_DEGREE_CAP := 3
const TRUNK_HUB_FRAC := 0.08
const HIGHWAY_RARE_FRAC := 0.04
const HIGHWAY_RARE_RANK := 0.96
const PAVED_RANK_FLOOR := 0.51
## HWY-2 corridors: grow past the HWY-1 3-stub cap. Min 3 keeps Part A stars;
## max 6 targets a live median of 4–6 and ≤12 components at the same ~4% budget.
const HWY1_CHAIN_MIN := 3
const HWY1_CHAIN_MAX := 6
## Continuation along a seeded chain may use typical trunk weights (NUTS3 ~10.1)
## so a corridor can walk off a heavy hub. Dirt tails (weight ~2) stay out.
const HWY1_GROW_WEIGHT_FLOOR := 7.0
## HWY-3: display highways are trunk shortest paths between hubs, not rank-grow.
const HWY3_HUB_K := 2
const HWY3_PATH_LEN_RATIO := 1.6
const HWY3_ZIGZAG_TURN_BUDGET := 4.71238898038469 ## 1.5π
const HWY3_HOOK_TURN := 2.61799387799149 ## 150°
const HWY3_BUDGET_SLACK := 0.15
const HWY3_SCORE_CAPITAL := 100000.0
const HWY3_SCORE_TIER := 800.0
const HWY3_SCORE_POP_DIV := 1000.0
const HWY3_SCORE_INDUSTRIAL := 500.0
const HWY3_SCORE_CITY_HUB := 400.0
const HWY3_SCORE_PORT := 200.0
const HWY3_SCORE_URBAN := 200.0
const HWY3_SCORE_URBAN_NBR := 120.0
const HWY3_MIN_PATH_EDGES := 3
## Last hub-route rebuild (tests / overlay logs). Not gameplay state.
static var last_hwy3_debug: Dictionary = {}
static var _hwy3_adj_memo_key: String = ""
static var _hwy3_adj_memo: Dictionary = {}
static var _hwy3_route_memo_key: String = ""
static var _hwy3_route_memo_marked: Dictionary = {}
static var _hwy3_route_memo_debug: Dictionary = {}

## Fallback when the board has no usable shared-border set.
## Tuned on the Rhineland: Bonn–Köln 7.86 and Köln–Leverkusen 3.15 pass;
## Köln–Düren 12.78 and Köln–Essen 14.62 fail. Largest real Köln neighbour
## on world_accurate is Neuss at 9.40.
const RHINE_CENTROID_GAP_CAP := 11.0

const KOELN_ID := 710417
const BONN_ID := 710416
const LEVERKUSEN_ID := 710418
const ESSEN_ID := 710403
const DUREN_ID := 710419

## NUTS3 Europe id block (pilot board + world_accurate Europe).
const NUTS3_ID_MIN := 710000
const NUTS3_ID_MAX := 799999


## Keep today's era-relative formula: road_infra_min / +3 / +6; explicit ⇒ 2.
static func road_tier_for_edge(avg_infra: float, era_profile: Dictionary, explicit: bool) -> int:
	if explicit:
		return TIER_HIGHWAY
	var road_min: float = float(era_profile.get("road_infra_min", 3.0))
	var tier: int = TIER_DIRT
	if avg_infra >= road_min + 3.0:
		tier = TIER_HIGHWAY if avg_infra >= road_min + 6.0 else TIER_PAVED
	elif avg_infra >= road_min:
		tier = TIER_PAVED
	return tier


static func lod_band_for_zoom(zoom: float) -> int:
	var z: float = zoom
	if not is_finite(z):
		z = 1.0
	if z <= ZOOM_FAR_MAX:
		return 0
	if z >= ZOOM_CLOSE_MIN:
		return 2
	return 1


static func dirt_hidden_at_zoom(zoom: float) -> bool:
	return zoom < DIRT_ZOOM_FLOOR


## Europe/Home: rare highways only (explicit + top few percent). Mid AND close:
## highways stay on (the mid band is paved+highway). Close also shows dirt.
## Formula `tier` is unchanged.
static func tier_visible_at_zoom(formula_tier: int, explicit: bool, display_tier: int, zoom: float) -> bool:
	var z: float = zoom
	if not is_finite(z):
		z = 1.0
	var lod: int = lod_band_for_zoom(z)
	if display_tier == TIER_HIGHWAY or explicit:
		return true
	if lod <= 0:
		return false
	if lod == 1:
		return display_tier >= TIER_PAVED
	# Close: every trunk edge. formula_tier is the intact gameplay/formula value.
	return formula_tier >= TIER_DIRT


static func display_tier_from_rank(rank01: float, explicit: bool) -> int:
	if explicit:
		return TIER_HIGHWAY
	var r: float = rank01
	if not is_finite(r):
		r = 0.0
	r = clampf(r, 0.0, 0.999)
	# 1936: explicit + top few percent only. Terciles painted NL/UK/BE as
	# highways. Rank is lowest→highest infra/size on the visual trunk.
	if r >= HIGHWAY_RARE_RANK:
		return TIER_HIGHWAY
	if r >= PAVED_RANK_FLOOR:
		return TIER_PAVED
	return TIER_DIRT


static func end_labels_visible_at_zoom(zoom: float) -> bool:
	return zoom >= END_LABEL_ZOOM_MIN


static func end_labels_visible_for_span(zoom: float, _spine_span_world: float) -> bool:
	return end_labels_visible_at_zoom(zoom)


static func screen_width_for_tier(tier: int, lod_band: int) -> float:
	var w: float = DIRT_SCREEN_PX
	match tier:
		TIER_PAVED:
			w = PAVED_SCREEN_PX
		TIER_HIGHWAY:
			if lod_band <= 0:
				w = HIGHWAY_FAR_CASING_SCREEN_PX
			elif lod_band >= 2:
				w = HIGHWAY_CLOSE_CASING_SCREEN_PX
			else:
				w = HIGHWAY_CASING_SCREEN_PX
		_:
			w = DIRT_SCREEN_PX
	return w


static func edge_key(a: int, b: int) -> String:
	return "%d_%d" % [mini(a, b), maxi(a, b)]


## share_border_known=true uses the geometry flag. Otherwise centroid-gap fallback.
static func road_edge_passes_sanity(
	distance: float,
	share_border_known: bool,
	share_border: bool,
	centroid_cap: float = RHINE_CENTROID_GAP_CAP,
) -> bool:
	if share_border_known:
		return share_border
	if not is_finite(distance) or distance <= 0.0:
		return false
	return distance <= centroid_cap


static func must_draw_pairs() -> Array:
	return [[BONN_ID, KOELN_ID], [KOELN_ID, LEVERKUSEN_ID]]


static func must_not_draw_pairs() -> Array:
	return [[KOELN_ID, ESSEN_ID], [KOELN_ID, DUREN_ID]]


## Quantized undirected segment key (same idea as shared_edge_adjacency_product).
static func quantized_segment_key(a: Vector2, b: Vector2, quant: float) -> String:
	var q: float = maxf(quant, 0.5)
	var ax: int = int(round(a.x / q))
	var ay: int = int(round(a.y / q))
	var bx: int = int(round(b.x / q))
	var by: int = int(round(b.y / q))
	if ax > bx or (ax == bx and ay > by):
		var tx: int = ax
		var ty: int = ay
		ax = bx
		ay = by
		bx = tx
		by = ty
	if ax == bx and ay == by:
		return ""
	return "%d_%d_%d_%d" % [ax, ay, bx, by]


## pid → PackedVector2Array rings → undirected "min_max" keys that share a border.
static func shared_border_keys_from_rings(rings: Dictionary, quant: float = 4.0) -> Dictionary:
	var edge_to_pids: Dictionary = {}
	for pid_v in rings.keys():
		var pid: int = int(pid_v)
		var ring_v: Variant = rings[pid_v]
		if typeof(ring_v) != TYPE_PACKED_VECTOR2_ARRAY:
			continue
		var ring: PackedVector2Array = ring_v
		if ring.size() < 3:
			continue
		var n: int = ring.size()
		for i in range(n):
			var a: Vector2 = ring[i]
			var b: Vector2 = ring[(i + 1) % n]
			var sk: String = quantized_segment_key(a, b, quant)
			if sk.is_empty():
				continue
			var owners: Variant = edge_to_pids.get(sk, PackedInt32Array())
			var packed: PackedInt32Array = owners
			var found := false
			for j in packed.size():
				if int(packed[j]) == pid:
					found = true
					break
			if not found:
				packed.append(pid)
				edge_to_pids[sk] = packed
	var keys: Dictionary = {}
	for sk in edge_to_pids.keys():
		var packed2: PackedInt32Array = edge_to_pids[sk]
		if packed2.size() < 2:
			continue
		for i in range(packed2.size()):
			for j in range(i + 1, packed2.size()):
				keys[edge_key(int(packed2[i]), int(packed2[j]))] = true
	return keys


static func is_nuts3_pid(pid: int) -> bool:
	return pid >= NUTS3_ID_MIN and pid <= NUTS3_ID_MAX


static func province_weight(infra: float, development: float, population: float) -> float:
	return maxf(infra, 0.0) * 2.0 + maxf(development, 1.0) + maxf(population, 0.0) / 200000.0


static func trunk_edge_score(entry: Dictionary) -> float:
	var c1: Vector2 = entry.get("c1", Vector2.ZERO)
	var c2: Vector2 = entry.get("c2", Vector2.ZERO)
	var dist: float = c1.distance_to(c2)
	if not is_finite(dist) or dist <= 0.0:
		dist = 9999.0
	var infra: float = float(entry.get("avg_infra", 0.0))
	var w: float = float(entry.get("weight", 1.0))
	return infra * 14.0 + w * 6.0 - dist * 0.28


static func _uf_find(parent: Dictionary, x: int) -> int:
	if not parent.has(x):
		parent[x] = x
	var p: int = int(parent[x])
	if p != x:
		p = _uf_find(parent, p)
		parent[x] = p
	return p


static func _uf_union(parent: Dictionary, a: int, b: int) -> bool:
	var ra: int = _uf_find(parent, a)
	var rb: int = _uf_find(parent, b)
	if ra == rb:
		return false
	parent[rb] = ra
	return true


static func _entry_key(entry: Dictionary) -> String:
	return edge_key(int(entry.get("p1", 0)), int(entry.get("p2", 0)))


static func _score_less(a: Dictionary, b: Dictionary) -> bool:
	var sa: float = float(a.get("_score", 0.0))
	var sb: float = float(b.get("_score", 0.0))
	if sa == sb:
		return _entry_key(a) < _entry_key(b)
	return sa > sb


static func _dist_less(a: Dictionary, b: Dictionary) -> bool:
	var da: float = float(a.get("_dist", 9999.0))
	var db: float = float(b.get("_dist", 9999.0))
	if da == db:
		return _entry_key(a) < _entry_key(b)
	return da < db


static func _weight_less(a: Dictionary, b: Dictionary) -> bool:
	var wa: float = float(a.get("weight", 0.0))
	var wb: float = float(b.get("weight", 0.0))
	if wa == wb:
		var ia: float = float(a.get("avg_infra", 0.0))
		var ib: float = float(b.get("avg_infra", 0.0))
		if ia == ib:
			return _entry_key(a) < _entry_key(b)
		return ia < ib
	return wa < wb


static func count_undirected_triangles(edges: Array) -> int:
	var adj: Dictionary = {}
	for row_v in edges:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if a == 0 or b == 0 or a == b:
			continue
		if not adj.has(a):
			adj[a] = {}
		if not adj.has(b):
			adj[b] = {}
		var na: Dictionary = adj[a]
		var nb: Dictionary = adj[b]
		na[b] = true
		nb[a] = true
		adj[a] = na
		adj[b] = nb
	var pids: Array = adj.keys()
	pids.sort()
	var count: int = 0
	for a_v in pids:
		var a: int = int(a_v)
		var nbrs_v: Variant = adj[a]
		if typeof(nbrs_v) != TYPE_DICTIONARY:
			continue
		var nbrs: Array = (nbrs_v as Dictionary).keys()
		nbrs.sort()
		for i in range(nbrs.size()):
			var b: int = int(nbrs[i])
			if b <= a:
				continue
			var bset_v: Variant = adj.get(b, {})
			if typeof(bset_v) != TYPE_DICTIONARY:
				continue
			var bset: Dictionary = bset_v
			for j in range(i + 1, nbrs.size()):
				var c: int = int(nbrs[j])
				if c <= b:
					continue
				if bset.has(c):
					count += 1
	return count


static func degree_stats(edges: Array) -> Dictionary:
	var deg: Dictionary = {}
	for row_v in edges:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if a == 0 or b == 0:
			continue
		deg[a] = int(deg.get(a, 0)) + 1
		deg[b] = int(deg.get(b, 0)) + 1
	var max_d: int = 0
	var sum_d: int = 0
	var n: int = 0
	for pid_v in deg.keys():
		var d: int = int(deg[pid_v])
		max_d = maxi(max_d, d)
		sum_d += d
		n += 1
	var avg: float = 0.0 if n <= 0 else float(sum_d) / float(n)
	return {"max": max_d, "avg": avg, "provinces": n, "edges": edges.size()}


## Visual-only sparsifier. Shared-border candidates in; forest trunk out.
## Always keeps explicit + must-draw (Bonn–Köln / Köln–Leverkusen).
static func select_trunk_edges(candidates: Array) -> Array:
	if candidates.is_empty():
		return []
	var must: Dictionary = {}
	for pair_v in must_draw_pairs():
		if typeof(pair_v) != TYPE_ARRAY:
			continue
		var pair: Array = pair_v
		if pair.size() < 2:
			continue
		must[edge_key(int(pair[0]), int(pair[1]))] = true
	var by_pid: Dictionary = {}
	var prepared: Array = []
	var weights: Dictionary = {}
	for row_v in candidates:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if a == 0 or b == 0 or a == b:
			continue
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		var dist: float = c1.distance_to(c2)
		if not is_finite(dist) or dist <= 0.0:
			dist = 9999.0
		row["_dist"] = dist
		row["_score"] = trunk_edge_score(row)
		prepared.append(row)
		if not by_pid.has(a):
			by_pid[a] = []
		if not by_pid.has(b):
			by_pid[b] = []
		var la: Array = by_pid[a]
		var lb: Array = by_pid[b]
		la.append(row)
		lb.append(row)
		by_pid[a] = la
		by_pid[b] = lb
		weights[a] = maxf(float(weights.get(a, 0.0)), float(row.get("w1", row.get("weight", 1.0))))
		weights[b] = maxf(float(weights.get(b, 0.0)), float(row.get("w2", row.get("weight", 1.0))))
	if prepared.is_empty():
		return []
	var hub: Dictionary = {}
	hub[KOELN_ID] = true
	var wrows: Array = []
	for pid_v in weights.keys():
		wrows.append({"pid": int(pid_v), "weight": float(weights[pid_v]), "avg_infra": 0.0, "p1": int(pid_v), "p2": 0})
	wrows.sort_custom(_weight_less)
	var hub_n: int = maxi(1, int(ceil(float(wrows.size()) * TRUNK_HUB_FRAC)))
	for i in range(wrows.size() - hub_n, wrows.size()):
		hub[int(wrows[i].get("pid", 0))] = true
	var nearest_keys: Dictionary = {}
	for pid_v in by_pid.keys():
		var list: Array = by_pid[pid_v]
		list.sort_custom(_dist_less)
		var keep_n: int = 2
		for i in range(mini(keep_n, list.size())):
			nearest_keys[_entry_key(list[i])] = true
	var parent: Dictionary = {}
	for pid_v in by_pid.keys():
		parent[int(pid_v)] = int(pid_v)
	var degree: Dictionary = {}
	var selected: Array = []
	var selected_keys: Dictionary = {}
	var scored: Array = prepared.duplicate()
	scored.sort_custom(_score_less)
	for row_v in scored:
		var row: Dictionary = row_v
		var key: String = _entry_key(row)
		var keep: bool = bool(row.get("explicit", false)) or must.has(key)
		if not keep:
			continue
		if selected_keys.has(key):
			continue
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		_uf_union(parent, a, b)
		degree[a] = int(degree.get(a, 0)) + 1
		degree[b] = int(degree.get(b, 0)) + 1
		selected.append(row)
		selected_keys[key] = true
	for row_v in scored:
		var row2: Dictionary = row_v
		var key2: String = _entry_key(row2)
		if selected_keys.has(key2):
			continue
		if not nearest_keys.has(key2):
			continue
		var a2: int = int(row2.get("p1", 0))
		var b2: int = int(row2.get("p2", 0))
		if _uf_find(parent, a2) == _uf_find(parent, b2):
			continue
		var cap_a: int = TRUNK_HUB_DEGREE_CAP if hub.has(a2) else TRUNK_DEGREE_CAP
		var cap_b: int = TRUNK_HUB_DEGREE_CAP if hub.has(b2) else TRUNK_DEGREE_CAP
		if int(degree.get(a2, 0)) >= cap_a or int(degree.get(b2, 0)) >= cap_b:
			continue
		_uf_union(parent, a2, b2)
		degree[a2] = int(degree.get(a2, 0)) + 1
		degree[b2] = int(degree.get(b2, 0)) + 1
		selected.append(row2)
		selected_keys[key2] = true
	# Connect leftover isolates to their nearest already-kept neighbour.
	for row_v in scored:
		var row3: Dictionary = row_v
		var key3: String = _entry_key(row3)
		if selected_keys.has(key3):
			continue
		var a3: int = int(row3.get("p1", 0))
		var b3: int = int(row3.get("p2", 0))
		var da: int = int(degree.get(a3, 0))
		var db: int = int(degree.get(b3, 0))
		if da > 0 and db > 0:
			continue
		if _uf_find(parent, a3) == _uf_find(parent, b3):
			continue
		var cap_a3: int = TRUNK_HUB_DEGREE_CAP if hub.has(a3) else TRUNK_DEGREE_CAP
		var cap_b3: int = TRUNK_HUB_DEGREE_CAP if hub.has(b3) else TRUNK_DEGREE_CAP
		if da >= cap_a3 and db >= cap_b3:
			continue
		if da >= cap_a3 + 1 or db >= cap_b3 + 1:
			continue
		_uf_union(parent, a3, b3)
		degree[a3] = da + 1
		degree[b3] = db + 1
		selected.append(row3)
		selected_keys[key3] = true
	for row_v in selected:
		if typeof(row_v) == TYPE_DICTIONARY:
			var cleaned: Dictionary = row_v
			cleaned.erase("_dist")
			cleaned.erase("_score")
	return selected


static func assign_rare_display_tiers(cache: Array, hub_ctx: Dictionary = {}) -> void:
	var inferred: Array = []
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if bool(row.get("explicit", false)):
			row["display_tier"] = TIER_HIGHWAY
			continue
		inferred.append(row)
	if inferred.is_empty() and hub_ctx.is_empty():
		return
	var ranked: Dictionary = _hwy1_rank_inferred(inferred) if not inferred.is_empty() else {"ranks": {}, "seeds_desc": []}
	var ranks: Dictionary = ranked.get("ranks", {})
	var seeds_desc: Array = ranked.get("seeds_desc", [])
	for row2_v in inferred:
		var row2: Dictionary = row2_v
		var rank: float = float(ranks.get(_hwy1_row_key(row2), 0.0))
		var tier: int = display_tier_from_rank(rank, false)
		# Highways come from chain pick only. Rank still paints paved/dirt.
		if tier == TIER_HIGHWAY:
			tier = TIER_PAVED
		row2["display_tier"] = tier
	var mutant: String = hwy3_mutant_name()
	var records_v: Variant = hub_ctx.get("records", [])
	var has_hubs: bool = typeof(records_v) == TYPE_ARRAY and (records_v as Array).size() > 0
	if mutant == "rank_grow_back" or (not has_hubs):
		_hwy1_pick_highway_chains(cache, inferred, ranks, seeds_desc)
		last_hwy3_debug = {"mutant": mutant, "hubs": [], "routes": [], "mode": "rank_grow", "records": hub_ctx.get("records", [])}
		return
	_hwy3_pick_hub_routes(cache, inferred, hub_ctx, mutant)


## Weight desc, infra desc, int pair-key asc (same as string edge_key on 6-digit pids).
static func _hwy1_weight_more_int(a: Dictionary, b: Dictionary) -> bool:
	var wa: float = float(a.get("weight", 0.0))
	var wb: float = float(b.get("weight", 0.0))
	if wa == wb:
		var ia: float = float(a.get("avg_infra", 0.0))
		var ib: float = float(b.get("avg_infra", 0.0))
		if ia == ib:
			return _hwy1_row_key(a) < _hwy1_row_key(b)
		return ia > ib
	return wa > wb


## One sort (heaviest first). Rank i/n matches lowest→highest weight (light groups first).
static func _hwy1_rank_inferred(inferred: Array) -> Dictionary:
	inferred.sort_custom(_hwy1_weight_more_int)
	var n: int = inferred.size()
	var ranks: Dictionary = {}
	var rank_i: int = 0
	var i: int = n - 1
	while i >= 0:
		var i_lo: int = i
		while i_lo > 0:
			var left: Dictionary = inferred[i_lo - 1]
			var right: Dictionary = inferred[i_lo]
			if float(left.get("weight", 0.0)) != float(right.get("weight", 0.0)):
				break
			if float(left.get("avg_infra", 0.0)) != float(right.get("avg_infra", 0.0)):
				break
			i_lo -= 1
		for j in range(i_lo, i + 1):
			var row: Dictionary = inferred[j]
			var rank: float = 0.0 if n <= 1 else float(rank_i) / float(n)
			ranks[_hwy1_row_key(row)] = rank
			rank_i += 1
		i = i_lo - 1
	return {"ranks": ranks, "seeds_desc": inferred}


static func _hwy1_row_key(row: Dictionary) -> int:
	return _hwy1_pair_key(int(row.get("p1", 0)), int(row.get("p2", 0)))


static func _hwy1_pair_key(a: int, b: int) -> int:
	return mini(a, b) * 1000000 + maxi(a, b)


static func _hwy1_budget(inferred_n: int) -> int:
	if inferred_n <= 0:
		return 0
	return ceili(float(inferred_n) * (1.0 - HIGHWAY_RARE_RANK))


static func _hwy1_add_pid(pids: PackedInt32Array, pid: int) -> void:
	if pid == 0:
		return
	for i in range(pids.size()):
		if pids[i] == pid:
			return
	pids.append(pid)


static func _hwy1_idx_more(cache: Array, ia: int, ib: int) -> bool:
	var a: Dictionary = cache[ia]
	var b: Dictionary = cache[ib]
	var wa: float = float(a.get("weight", 0.0))
	var wb: float = float(b.get("weight", 0.0))
	if wa == wb:
		var infa: float = float(a.get("avg_infra", 0.0))
		var infb: float = float(b.get("avg_infra", 0.0))
		if infa == infb:
			return _hwy1_row_key(a) < _hwy1_row_key(b)
		return infa > infb
	return wa > wb


static func _hwy1_absorb_explicit_idx(
	cache: Array,
	chain: Array,
	in_chain: Dictionary,
	pids: PackedInt32Array,
	by_pid: Dictionary,
	explicit_flags: PackedByteArray,
) -> void:
	var grew: bool = true
	while grew:
		grew = false
		var snap: int = pids.size()
		for pi in range(snap):
			var list_v: Variant = by_pid.get(pids[pi], [])
			if typeof(list_v) != TYPE_ARRAY:
				continue
			var list: Array = list_v
			for j in range(list.size()):
				var ei: int = int(list[j])
				if in_chain.has(ei):
					continue
				if explicit_flags[ei] != 1:
					continue
				chain.append(ei)
				in_chain[ei] = true
				var row: Dictionary = cache[ei]
				_hwy1_add_pid(pids, int(row.get("p1", 0)))
				_hwy1_add_pid(pids, int(row.get("p2", 0)))
				grew = true


static func _hwy1_grow_ok(
	cache: Array,
	ei: int,
	explicit_flags: PackedByteArray,
	rank_at: PackedFloat32Array,
) -> bool:
	if ei < 0 or ei >= cache.size():
		return false
	if explicit_flags[ei] == 1:
		return true
	if rank_at[ei] + 0.0001 >= PAVED_RANK_FLOOR:
		return true
	var row: Dictionary = cache[ei]
	return float(row.get("weight", 0.0)) + 0.0001 >= HWY1_GROW_WEIGHT_FLOOR


static func _hwy1_heaviest_nbr_idx(
	cache: Array,
	pids: PackedInt32Array,
	by_pid: Dictionary,
	in_chain: Dictionary,
	picked: PackedByteArray,
	explicit_flags: PackedByteArray,
	rank_at: PackedFloat32Array,
	deg: Dictionary,
	endpoints_only: bool,
) -> int:
	var best_i: int = -1
	for pi in range(pids.size()):
		var pid: int = pids[pi]
		if endpoints_only and int(deg.get(pid, 0)) != 1:
			continue
		var list_v: Variant = by_pid.get(pid, [])
		if typeof(list_v) != TYPE_ARRAY:
			continue
		var list: Array = list_v
		for j in range(list.size()):
			var ei: int = int(list[j])
			if in_chain.has(ei) or picked[ei] == 1:
				continue
			if not _hwy1_grow_ok(cache, ei, explicit_flags, rank_at):
				continue
			if best_i < 0 or _hwy1_idx_more(cache, ei, best_i):
				best_i = ei
	return best_i


static func _hwy1_bump_deg(deg: Dictionary, pid: int) -> void:
	if pid == 0:
		return
	deg[pid] = int(deg.get(pid, 0)) + 1


static func _hwy1_grow_chain_idx(
	cache: Array,
	seed_i: int,
	picked: PackedByteArray,
	by_pid: Dictionary,
	explicit_flags: PackedByteArray,
	rank_at: PackedFloat32Array,
	has_explicit: bool,
) -> Array:
	var chain: Array = [seed_i]
	var in_chain: Dictionary = {}
	in_chain[seed_i] = true
	var seed_row: Dictionary = cache[seed_i]
	var pids: PackedInt32Array = PackedInt32Array()
	var deg: Dictionary = {}
	var a0: int = int(seed_row.get("p1", 0))
	var b0: int = int(seed_row.get("p2", 0))
	_hwy1_add_pid(pids, a0)
	_hwy1_add_pid(pids, b0)
	_hwy1_bump_deg(deg, a0)
	_hwy1_bump_deg(deg, b0)
	if has_explicit:
		var before: int = chain.size()
		_hwy1_absorb_explicit_idx(cache, chain, in_chain, pids, by_pid, explicit_flags)
		for ci in range(before, chain.size()):
			var er: Dictionary = cache[int(chain[ci])]
			_hwy1_bump_deg(deg, int(er.get("p1", 0)))
			_hwy1_bump_deg(deg, int(er.get("p2", 0)))
	while chain.size() < HWY1_CHAIN_MAX:
		# Below min length: blob (star spokes). At min+: endpoints only so a
		# heavy hub walks a corridor instead of spending the budget on spokes.
		var endpoints_only: bool = chain.size() >= HWY1_CHAIN_MIN
		var nxt: int = _hwy1_heaviest_nbr_idx(
			cache, pids, by_pid, in_chain, picked, explicit_flags, rank_at, deg, endpoints_only
		)
		if nxt < 0:
			break
		chain.append(nxt)
		in_chain[nxt] = true
		var nxt_row: Dictionary = cache[nxt]
		var na: int = int(nxt_row.get("p1", 0))
		var nb: int = int(nxt_row.get("p2", 0))
		_hwy1_add_pid(pids, na)
		_hwy1_add_pid(pids, nb)
		_hwy1_bump_deg(deg, na)
		_hwy1_bump_deg(deg, nb)
		if has_explicit:
			var before2: int = chain.size()
			_hwy1_absorb_explicit_idx(cache, chain, in_chain, pids, by_pid, explicit_flags)
			for ci2 in range(before2, chain.size()):
				var er2: Dictionary = cache[int(chain[ci2])]
				_hwy1_bump_deg(deg, int(er2.get("p1", 0)))
				_hwy1_bump_deg(deg, int(er2.get("p2", 0)))
	return chain


## One adjacency (int pid → Array of cache indices). No String keys, no per-seed rebuild.
static func _hwy1_pick_highway_chains(
	cache: Array,
	inferred: Array,
	ranks: Dictionary,
	seeds_desc: Array,
) -> void:
	var budget: int = _hwy1_budget(inferred.size())
	if budget <= 0:
		return
	var n: int = cache.size()
	var rank_at: PackedFloat32Array = PackedFloat32Array()
	var explicit_flags: PackedByteArray = PackedByteArray()
	var picked: PackedByteArray = PackedByteArray()
	rank_at.resize(n)
	explicit_flags.resize(n)
	picked.resize(n)
	var idx_by_key: Dictionary = {}
	var by_pid: Dictionary = {}
	var has_explicit: bool = false
	for i in range(n):
		var row_v: Variant = cache[i]
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		var k: int = _hwy1_pair_key(a, b)
		idx_by_key[k] = i
		rank_at[i] = float(ranks.get(k, 0.0))
		if bool(row.get("explicit", false)):
			explicit_flags[i] = 1
			picked[i] = 1
			has_explicit = true
		if a == 0 or b == 0 or a == b:
			continue
		var lst_a: Array = by_pid.get(a, [])
		lst_a.append(i)
		by_pid[a] = lst_a
		var lst_b: Array = by_pid.get(b, [])
		lst_b.append(i)
		by_pid[b] = lst_b
	var seeds: Array = seeds_desc
	if seeds.is_empty():
		seeds = inferred
	var used: int = 0
	var seed_cap: int = mini(seeds.size(), maxi(budget * 4, 16))
	var seed_i: int = 0
	for seed_v in seeds:
		if used >= budget:
			break
		seed_i += 1
		if seed_i > seed_cap:
			break
		if typeof(seed_v) != TYPE_DICTIONARY:
			continue
		var seed: Dictionary = seed_v
		var si: int = int(idx_by_key.get(_hwy1_row_key(seed), -1))
		if si < 0 or picked[si] == 1:
			continue
		var chain: Array = _hwy1_grow_chain_idx(
			cache, si, picked, by_pid, explicit_flags, rank_at, has_explicit
		)
		if chain.size() < HWY1_CHAIN_MIN:
			continue
		var inferred_n: int = 0
		for ci in range(chain.size()):
			if explicit_flags[int(chain[ci])] != 1:
				inferred_n += 1
		var room: int = budget - used
		if inferred_n <= 0:
			continue
		var take_n: int = inferred_n
		if take_n > room:
			if room < HWY1_CHAIN_MIN:
				continue
			take_n = room
		var taken: int = 0
		for ci2 in range(chain.size()):
			var ei2: int = int(chain[ci2])
			picked[ei2] = 1
			if explicit_flags[ei2] == 1:
				continue
			if taken >= take_n:
				picked[ei2] = 0
				continue
			var ch2: Dictionary = cache[ei2]
			ch2["display_tier"] = TIER_HIGHWAY
			used += 1
			taken += 1
	# Leftover budget extends already-picked corridor endpoints (not new stubs).
	if used < budget:
		_hwy1_extend_picked(cache, picked, by_pid, explicit_flags, rank_at, budget, used)


static func _hwy1_extend_picked(
	cache: Array,
	picked: PackedByteArray,
	by_pid: Dictionary,
	explicit_flags: PackedByteArray,
	rank_at: PackedFloat32Array,
	budget: int,
	used_in: int,
) -> void:
	var used: int = used_in
	while used < budget:
		var deg: Dictionary = {}
		var pids: PackedInt32Array = PackedInt32Array()
		var in_chain: Dictionary = {}
		for i in range(cache.size()):
			if picked[i] != 1:
				continue
			in_chain[i] = true
			var row: Dictionary = cache[i]
			var a: int = int(row.get("p1", 0))
			var b: int = int(row.get("p2", 0))
			_hwy1_add_pid(pids, a)
			_hwy1_add_pid(pids, b)
			_hwy1_bump_deg(deg, a)
			_hwy1_bump_deg(deg, b)
		var nxt: int = _hwy1_heaviest_nbr_idx(
			cache, pids, by_pid, in_chain, picked, explicit_flags, rank_at, deg, true
		)
		if nxt < 0:
			break
		picked[nxt] = 1
		if explicit_flags[nxt] == 1:
			continue
		var row2: Dictionary = cache[nxt]
		row2["display_tier"] = TIER_HIGHWAY
		used += 1


## HWY-1 log / bars: connected components of highway edges (size = edge count).
static func _hwy1_component_stats(cache: Array) -> Dictionary:
	var parent: Dictionary = {}
	var hwy_rows: Array = []
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) != TIER_HIGHWAY:
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


static func hwy3_mutant_name() -> String:
	return OS.get_environment("EOA_HWY3_MUTANT").strip_edges()


static func is_urban_district_name(province_name: String) -> bool:
	var n: String = province_name.strip_edges().to_lower()
	if n.is_empty():
		return false
	return (
		n.ends_with("kreisfreie stadt")
		or n.ends_with("stadtkreis")
		or n.contains(", kreisfreie stadt")
		or n.contains(", stadtkreis")
	)


static func hwy3_hub_score(rec: Dictionary, use_urban: bool) -> float:
	var score: float = 0.0
	if bool(rec.get("capital", false)):
		score += HWY3_SCORE_CAPITAL
	score += float(int(rec.get("tier", 0))) * HWY3_SCORE_TIER
	score += float(int(rec.get("population", 0))) / HWY3_SCORE_POP_DIV
	if bool(rec.get("industrial", false)):
		score += HWY3_SCORE_INDUSTRIAL
	if bool(rec.get("city_hub", false)):
		score += HWY3_SCORE_CITY_HUB
	var port_ok: bool = bool(rec.get("port", false))
	if port_ok:
		if int(rec.get("tier", 0)) >= 3 or int(rec.get("population", 0)) >= 400000:
			score += HWY3_SCORE_PORT
	if use_urban:
		if bool(rec.get("urban", false)):
			score += HWY3_SCORE_URBAN
		score += float(int(rec.get("urban_nbr", 0))) * HWY3_SCORE_URBAN_NBR
	return score


static func _hwy3_hub_n_for_land(land_n: int) -> int:
	if land_n <= 0:
		return 0
	if land_n < 24:
		return 1
	if land_n < 80:
		return 2
	if land_n < 180:
		return 3
	if land_n < 320:
		return 4
	if land_n < 500:
		return 6
	return 8


static func _hwy3_score_pid_less(a: Dictionary, b: Dictionary) -> bool:
	var sa: float = float(a.get("score", 0.0))
	var sb: float = float(b.get("score", 0.0))
	if sa == sb:
		return int(a.get("pid", 0)) < int(b.get("pid", 0))
	return sa > sb


static func _hwy3_rec_is_hub_candidate(rec: Dictionary) -> bool:
	if bool(rec.get("capital", false)):
		return true
	if int(rec.get("tier", 0)) >= 2:
		return true
	if int(rec.get("population", 0)) >= 80000:
		return true
	if bool(rec.get("industrial", false)) or bool(rec.get("city_hub", false)) or bool(rec.get("port", false)):
		return true
	if bool(rec.get("urban", false)) or int(rec.get("urban_nbr", 0)) >= 1:
		return true
	return false


static func select_display_hubs(records: Array, use_urban: bool) -> Array:
	var by_tag: Dictionary = {}
	for rec_v in records:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var pid: int = int(rec.get("pid", 0))
		if pid <= 0:
			continue
		if bool(rec.get("_skip", false)):
			continue
		var tag: String = str(rec.get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		if not _hwy3_rec_is_hub_candidate(rec):
			continue
		rec["score"] = hwy3_hub_score(rec, use_urban)
		if not by_tag.has(tag):
			by_tag[tag] = []
		var lst: Array = by_tag[tag]
		lst.append(rec)
		by_tag[tag] = lst
	var hubs: Array = []
	var tags: Array = by_tag.keys()
	tags.sort()
	for tag_v in tags:
		var tag: String = str(tag_v)
		var lst2: Array = by_tag[tag]
		lst2.sort_custom(_hwy3_score_pid_less)
		var land_n: int = 0
		for rec2_v in lst2:
			var rec2: Dictionary = rec2_v
			land_n = maxi(land_n, int(rec2.get("land_n", lst2.size())))
		var n_keep: int = _hwy3_hub_n_for_land(land_n)
		if n_keep <= 0:
			n_keep = 1
		var kept: int = 0
		for rec3_v in lst2:
			if kept >= n_keep:
				break
			var rec3: Dictionary = rec3_v
			var sc3: float = float(rec3.get("score", 0.0))
			var is_cap3: bool = bool(rec3.get("capital", false))
			if is_cap3 or sc3 >= 50.0:
				hubs.append(rec3)
				kept += 1
	hubs.sort_custom(_hwy3_score_pid_less)
	return hubs


static func _hwy3_pair_key(a: int, b: int) -> int:
	return _hwy1_pair_key(a, b)


static func _hwy3_add_pair(pairs: Dictionary, a: int, b: int) -> void:
	if a <= 0 or b <= 0 or a == b:
		return
	pairs[_hwy3_pair_key(a, b)] = Vector2i(mini(a, b), maxi(a, b))


static func pair_hub_routes(hubs: Array, tag_borders: Dictionary) -> Array:
	var by_tag: Dictionary = {}
	var rec_by_pid: Dictionary = {}
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var pid: int = int(rec.get("pid", 0))
		if pid <= 0:
			continue
		rec_by_pid[pid] = rec
		var tag: String = str(rec.get("tag", "")).strip_edges().to_upper()
		if not by_tag.has(tag):
			by_tag[tag] = []
		var lst: Array = by_tag[tag]
		lst.append(rec)
		by_tag[tag] = lst
	var pairs: Dictionary = {}
	var tags: Array = by_tag.keys()
	tags.sort()
	for tag_v in tags:
		var tag: String = str(tag_v)
		var lst2: Array = by_tag[tag]
		_hwy3_add_country_pairs(pairs, lst2)
	for tag2_v in tags:
		var tag2: String = str(tag2_v)
		var lst3: Array = by_tag[tag2]
		if lst3.is_empty():
			continue
		lst3.sort_custom(_hwy3_score_pid_less)
		var home: Dictionary = lst3[0]
		var home_pid: int = int(home.get("pid", 0))
		var best_f: int = 0
		var best_d: float = 1.0e18
		var borders_v: Variant = tag_borders.get(tag2, {})
		var borders: Dictionary = borders_v if typeof(borders_v) == TYPE_DICTIONARY else {}
		for other_v in hubs:
			if typeof(other_v) != TYPE_DICTIONARY:
				continue
			var other: Dictionary = other_v
			var ot: String = str(other.get("tag", "")).strip_edges().to_upper()
			if ot == tag2:
				continue
			var op: int = int(other.get("pid", 0))
			var c1: Vector2 = home.get("centroid", Vector2.ZERO)
			var c2: Vector2 = other.get("centroid", Vector2.ZERO)
			var d: float = c1.distance_to(c2)
			if not is_finite(d) or d <= 0.0:
				continue
			if not borders.is_empty() and not borders.has(ot):
				d *= 1.35
			if d < best_d or (d == best_d and op < best_f):
				best_d = d
				best_f = op
		if best_f > 0:
			_hwy3_add_pair(pairs, home_pid, best_f)
	var out: Array = []
	var keys: Array = pairs.keys()
	keys.sort()
	for k_v in keys:
		var p: Vector2i = pairs[k_v]
		out.append([int(p.x), int(p.y)])
	return out


static func _hwy3_add_country_pairs(pairs: Dictionary, hubs: Array) -> void:
	if hubs.size() < 2:
		return
	var dist_rows: Array = []
	for i in range(hubs.size()):
		var a: Dictionary = hubs[i]
		var ap: int = int(a.get("pid", 0))
		var ac: Vector2 = a.get("centroid", Vector2.ZERO)
		var nearest: Array = []
		for j in range(hubs.size()):
			if i == j:
				continue
			var b: Dictionary = hubs[j]
			var bp: int = int(b.get("pid", 0))
			var bc: Vector2 = b.get("centroid", Vector2.ZERO)
			var d: float = ac.distance_to(bc)
			if not is_finite(d) or d <= 0.0:
				d = 999999.0
			nearest.append({"pid": bp, "dist": d, "key": _hwy3_pair_key(ap, bp)})
			if i < j:
				dist_rows.append({"a": ap, "b": bp, "dist": d, "key": _hwy3_pair_key(ap, bp)})
		nearest.sort_custom(_hwy3_dist_pid_less)
		for k in range(mini(HWY3_HUB_K, nearest.size())):
			var nb: Dictionary = nearest[k]
			_hwy3_add_pair(pairs, ap, int(nb.get("pid", 0)))
	dist_rows.sort_custom(_hwy3_mst_less)
	var parent: Dictionary = {}
	for rec_v in hubs:
		var rec: Dictionary = rec_v
		var pid: int = int(rec.get("pid", 0))
		parent[pid] = pid
	for row_v in dist_rows:
		var row: Dictionary = row_v
		var a2: int = int(row.get("a", 0))
		var b2: int = int(row.get("b", 0))
		if _uf_union(parent, a2, b2):
			_hwy3_add_pair(pairs, a2, b2)


static func _hwy3_dist_pid_less(a: Dictionary, b: Dictionary) -> bool:
	var da: float = float(a.get("dist", 999999.0))
	var db: float = float(b.get("dist", 999999.0))
	if da == db:
		return int(a.get("pid", 0)) < int(b.get("pid", 0))
	return da < db


static func _hwy3_mst_less(a: Dictionary, b: Dictionary) -> bool:
	var da: float = float(a.get("dist", 999999.0))
	var db: float = float(b.get("dist", 999999.0))
	if da == db:
		return int(a.get("key", 0)) < int(b.get("key", 0))
	return da < db


static func _hwy3_heap_less(hc: PackedFloat64Array, hp: PackedInt32Array, i: int, j: int) -> bool:
	if hc[i] == hc[j]:
		return hp[i] < hp[j]
	return hc[i] < hc[j]


static func _hwy3_heap_swap(
	hc: PackedFloat64Array, hp: PackedInt32Array, hf: PackedInt32Array, i: int, j: int
) -> void:
	var tc: float = hc[i]
	hc[i] = hc[j]
	hc[j] = tc
	var tp: int = hp[i]
	hp[i] = hp[j]
	hp[j] = tp
	var tf: int = hf[i]
	hf[i] = hf[j]
	hf[j] = tf


static func _hwy3_heap_push(
	hc: PackedFloat64Array, hp: PackedInt32Array, hf: PackedInt32Array, cost: float, pid: int, from_pid: int
) -> void:
	hc.append(cost)
	hp.append(pid)
	hf.append(from_pid)
	var i: int = hc.size() - 1
	while i > 0:
		var p: int = (i - 1) / 2
		if not _hwy3_heap_less(hc, hp, i, p):
			break
		_hwy3_heap_swap(hc, hp, hf, i, p)
		i = p


static func _hwy3_heap_pop(hc: PackedFloat64Array, hp: PackedInt32Array, hf: PackedInt32Array) -> Vector3:
	var n: int = hc.size()
	if n <= 0:
		return Vector3(-1.0, -1.0, -1.0)
	var cost: float = hc[0]
	var pid: int = hp[0]
	var from_pid: int = hf[0]
	n -= 1
	if n > 0:
		hc[0] = hc[n]
		hp[0] = hp[n]
		hf[0] = hf[n]
	hc.resize(n)
	hp.resize(n)
	hf.resize(n)
	var i: int = 0
	while true:
		var l: int = i * 2 + 1
		var r: int = l + 1
		if l >= n:
			break
		var best: int = l
		if r < n and _hwy3_heap_less(hc, hp, r, l):
			best = r
		if not _hwy3_heap_less(hc, hp, best, i):
			break
		_hwy3_heap_swap(hc, hp, hf, i, best)
		i = best
	return Vector3(cost, float(pid), float(from_pid))


static func _hwy3_same_tag_filter(start: int, goal: int, attrs: Dictionary) -> String:
	if attrs.is_empty() or not attrs.has(start) or not attrs.has(goal):
		return ""
	var ra_v: Variant = attrs.get(start, {})
	var rb_v: Variant = attrs.get(goal, {})
	if typeof(ra_v) != TYPE_DICTIONARY or typeof(rb_v) != TYPE_DICTIONARY:
		return ""
	var ta: String = str((ra_v as Dictionary).get("tag", "")).strip_edges().to_upper()
	var tb: String = str((rb_v as Dictionary).get("tag", "")).strip_edges().to_upper()
	if ta.is_empty() or ta != tb:
		return ""
	return ta


static func _hwy3_nbr_allowed(nid: int, tag_filter: String, attrs: Dictionary) -> bool:
	if tag_filter.is_empty() or nid == 0:
		return true
	if not attrs.has(nid):
		return true
	var rec_v: Variant = attrs.get(nid, {})
	if typeof(rec_v) != TYPE_DICTIONARY:
		return true
	var nt: String = str((rec_v as Dictionary).get("tag", "")).strip_edges().to_upper()
	if nt.is_empty():
		return true
	return nt == tag_filter


static func _hwy3_cent_from(src: Dictionary, pid: int) -> Vector2:
	if not src.has(pid):
		return Vector2.ZERO
	var v: Variant = src[pid]
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_DICTIONARY:
		return (v as Dictionary).get("centroid", Vector2.ZERO)
	return Vector2.ZERO


static func _hwy3_centroid_of(pid: int, attrs: Dictionary) -> Vector2:
	return _hwy3_cent_from(attrs, pid)


static func _hwy3_dijkstra_prev(
	adj: Dictionary, start: int, tag_filter: String, attrs: Dictionary, goal: int = 0
) -> Dictionary:
	var prev: Dictionary = {}
	if start <= 0 or not adj.has(start):
		return prev
	var max_via: float = 0.0
	var cs: Vector2 = Vector2.ZERO
	var cg: Vector2 = Vector2.ZERO
	if goal > 0:
		cs = _hwy3_centroid_of(start, attrs)
		cg = _hwy3_centroid_of(goal, attrs)
		var straight: float = cs.distance_to(cg)
		if is_finite(straight) and straight > 0.0:
			max_via = straight * HWY3_PATH_LEN_RATIO
	var dist: Dictionary = {}
	var seen: Dictionary = {}
	dist[start] = 0.0
	prev[start] = -1
	var hc: PackedFloat64Array = PackedFloat64Array()
	var hp: PackedInt32Array = PackedInt32Array()
	var hf: PackedInt32Array = PackedInt32Array()
	_hwy3_heap_push(hc, hp, hf, 0.0, start, -1)
	while hc.size() > 0:
		var top: Vector3 = _hwy3_heap_pop(hc, hp, hf)
		var cost: float = top.x
		var pid: int = int(top.y)
		if seen.has(pid):
			continue
		seen[pid] = true
		if goal > 0 and pid == goal:
			break
		var nbrs_v: Variant = adj.get(pid, [])
		if typeof(nbrs_v) != TYPE_ARRAY:
			continue
		var nbrs: Array = nbrs_v
		for nb_v in nbrs:
			var nid: int = 0
			var edge_cost: float = 1.0
			if typeof(nb_v) == TYPE_VECTOR2:
				var nb2: Vector2 = nb_v
				nid = int(nb2.x)
				edge_cost = nb2.y
			elif typeof(nb_v) == TYPE_DICTIONARY:
				var nb: Dictionary = nb_v
				nid = int(nb.get("nbr", 0))
				edge_cost = float(nb.get("cost", 1.0))
			else:
				continue
			if nid == 0 or seen.has(nid):
				continue
			if not _hwy3_nbr_allowed(nid, tag_filter, attrs):
				continue
			if max_via > 0.0 and nid != goal:
				var cn: Vector2 = _hwy3_centroid_of(nid, attrs)
				if cn != Vector2.ZERO and cs.distance_to(cn) + cn.distance_to(cg) > max_via + 0.05:
					continue
			var ncost: float = cost + edge_cost
			var old_v: Variant = dist.get(nid, null)
			var better: bool = old_v == null
			if not better:
				var old: float = float(old_v)
				if ncost < old:
					better = true
				elif ncost == old and pid < int(prev.get(nid, 1 << 30)):
					better = true
			if better:
				dist[nid] = ncost
				prev[nid] = pid
				_hwy3_heap_push(hc, hp, hf, ncost, nid, pid)
	return prev


static func _hwy3_extract_path(prev: Dictionary, start: int, goal: int) -> PackedInt32Array:
	var empty: PackedInt32Array = PackedInt32Array()
	if start <= 0 or goal <= 0:
		return empty
	if start == goal:
		var one: PackedInt32Array = PackedInt32Array()
		one.append(start)
		return one
	if not prev.has(goal):
		return empty
	var rev: PackedInt32Array = PackedInt32Array()
	var cur: int = goal
	var guard: int = 0
	while cur > 0 and guard < 8192:
		rev.append(cur)
		if cur == start:
			break
		cur = int(prev.get(cur, -1))
		guard += 1
	if rev.is_empty() or rev[rev.size() - 1] != start:
		return empty
	var path: PackedInt32Array = PackedInt32Array()
	var ri: int = rev.size() - 1
	while ri >= 0:
		path.append(rev[ri])
		ri -= 1
	return path


static func shortest_hub_path(
	adj: Dictionary, start: int, goal: int, not_shortest: bool, attrs: Dictionary = {}
) -> PackedInt32Array:
	var empty: PackedInt32Array = PackedInt32Array()
	if start <= 0 or goal <= 0:
		return empty
	if start == goal:
		var one: PackedInt32Array = PackedInt32Array()
		one.append(start)
		return one
	if not adj.has(start) or not adj.has(goal):
		return empty
	if not_shortest:
		return _hwy3_random_trunk_walk(adj, start, goal)
	var tag_filter: String = _hwy3_same_tag_filter(start, goal, attrs)
	var prev: Dictionary = _hwy3_dijkstra_prev(adj, start, tag_filter, attrs, goal)
	return _hwy3_extract_path(prev, start, goal)


static func _hwy3_random_trunk_walk(adj: Dictionary, start: int, goal: int) -> PackedInt32Array:
	## Deterministic "random" walk (hash-ordered neighbours) so the mutant is stable.
	var path: PackedInt32Array = PackedInt32Array()
	var used: Dictionary = {}
	var cur: int = start
	path.append(cur)
	used[cur] = true
	var guard: int = 0
	while cur != goal and guard < 48:
		guard += 1
		var nbrs_v: Variant = adj.get(cur, [])
		if typeof(nbrs_v) != TYPE_ARRAY:
			break
		var nbrs: Array = nbrs_v
		var pick: int = 0
		var best_h: int = -1
		for nb_v in nbrs:
			var nid: int = 0
			if typeof(nb_v) == TYPE_VECTOR2:
				nid = int((nb_v as Vector2).x)
			elif typeof(nb_v) == TYPE_DICTIONARY:
				nid = int((nb_v as Dictionary).get("nbr", 0))
			else:
				continue
			if nid == 0 or used.has(nid):
				continue
			var h: int = (nid * 1103515245 + cur * 12345) & 0x7fffffff
			if best_h < 0 or h > best_h:
				best_h = h
				pick = nid
		if pick == 0:
			break
		path.append(pick)
		used[pick] = true
		cur = pick
	if path.size() < 2:
		return PackedInt32Array()
	return path


static func path_shape_report(
	pids: PackedInt32Array, centroids: Dictionary, start: int, goal: int, mutant: String
) -> Dictionary:
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
		var c1: Vector2 = _hwy3_cent_from(centroids, a)
		var c2: Vector2 = _hwy3_cent_from(centroids, b)
		var delta: Vector2 = c2 - c1
		var dist: float = delta.length()
		length += dist
		if dist > 0.0001:
			dirs.append(delta)
	out["length"] = length
	var cs: Vector2 = _hwy3_cent_from(centroids, start)
	var cg: Vector2 = _hwy3_cent_from(centroids, goal)
	var straight: float = cs.distance_to(cg)
	out["straight"] = straight
	if straight > 0.0001 and length > straight * HWY3_PATH_LEN_RATIO + 0.0001:
		out["long"] = true
	var turn_sum: float = 0.0
	var hook: bool = false
	for i3 in range(1, dirs.size()):
		var d0: Vector2 = dirs[i3 - 1]
		var d1: Vector2 = dirs[i3]
		var ang: float = absf(d0.angle_to(d1))
		turn_sum += ang
		if ang > HWY3_HOOK_TURN:
			hook = true
	out["turn_sum"] = turn_sum
	out["hook"] = hook
	var n_edges: int = maxi(pids.size() - 1, 1)
	var windows: float = maxf(float(n_edges) / 6.0, 1.0)
	if turn_sum > HWY3_ZIGZAG_TURN_BUDGET * windows + 0.0001:
		out["zigzag"] = true
	var allow_hook: bool = mutant == "hook_back"
	var allow_zig: bool = mutant == "zigzag_ok"
	if allow_hook:
		out["repeat"] = false
		out["hook"] = false
	if allow_zig:
		out["zigzag"] = false
		out["long"] = false
	out["ok"] = (
		(not bool(out["repeat"]) or allow_hook)
		and (not bool(out["hook"]) or allow_hook)
		and (not bool(out["long"]) or allow_zig)
		and (not bool(out["zigzag"]) or allow_zig)
	)
	return out


static func build_hub_route_adj(graph: Array, records: Array, use_urban: bool) -> Dictionary:
	var attrs: Dictionary = {}
	for rec_v in records:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		attrs[int(rec.get("pid", 0))] = rec
	return _hwy3_build_adj(graph, attrs, use_urban)


static func _hwy3_adj_cache_key(graph: Array, use_urban: bool) -> String:
	var n: int = graph.size()
	var a: int = 0
	var b: int = 0
	var c: int = 0
	var d: int = 0
	if n > 0 and typeof(graph[0]) == TYPE_DICTIONARY:
		var r0: Dictionary = graph[0]
		a = int(r0.get("p1", 0))
		b = int(r0.get("p2", 0))
	if n > 1 and typeof(graph[n - 1]) == TYPE_DICTIONARY:
		var r1: Dictionary = graph[n - 1]
		c = int(r1.get("p1", 0))
		d = int(r1.get("p2", 0))
	return "%d_%d_%d_%d_%d_%d" % [n, a, b, c, d, 1 if use_urban else 0]


static func _hwy3_build_adj(graph: Array, attrs: Dictionary, use_urban: bool) -> Dictionary:
	var adj: Dictionary = {}
	for row_v in graph:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if a == 0 or b == 0 or a == b:
			continue
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		var dist: float = c1.distance_to(c2)
		if not is_finite(dist) or dist <= 0.0:
			dist = 1.0
		var w: float = float(row.get("weight", 1.0))
		if use_urban:
			if attrs.has(a):
				var ra_v: Variant = attrs[a]
				if typeof(ra_v) == TYPE_DICTIONARY:
					var ra: Dictionary = ra_v
					w += float(int(ra.get("urban_nbr", 0))) * 1.15
					if bool(ra.get("urban", false)):
						w += 3.5
			if attrs.has(b):
				var rb_v: Variant = attrs[b]
				if typeof(rb_v) == TYPE_DICTIONARY:
					var rb: Dictionary = rb_v
					w += float(int(rb.get("urban_nbr", 0))) * 1.15
					if bool(rb.get("urban", false)):
						w += 3.5
		var cost: float = dist / maxf(w, 0.08)
		var la: Array = adj.get(a, [])
		la.append(Vector2(float(b), cost))
		adj[a] = la
		var lb: Array = adj.get(b, [])
		lb.append(Vector2(float(a), cost))
		adj[b] = lb
	return adj


static func _hwy3_pair_priority_less(a: Dictionary, b: Dictionary) -> bool:
	var da: float = float(a.get("dist", 999999.0))
	var db: float = float(b.get("dist", 999999.0))
	if da != db:
		return da < db
	var sa: float = float(a.get("score", 0.0))
	var sb: float = float(b.get("score", 0.0))
	if sa != sb:
		return sa > sb
	return int(a.get("key", 0)) < int(b.get("key", 0))


static func _hwy3_order_pairs_for_paint(scored_pairs: Array) -> Array:
	var by_tag: Dictionary = {}
	var foreign: Array = []
	for sp_v in scored_pairs:
		if typeof(sp_v) != TYPE_DICTIONARY:
			continue
		var sp: Dictionary = sp_v
		var tag: String = str(sp.get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			foreign.append(sp)
			continue
		if not by_tag.has(tag):
			by_tag[tag] = []
		var lst: Array = by_tag[tag]
		lst.append(sp)
		by_tag[tag] = lst
	var tags: Array = by_tag.keys()
	tags.sort()
	for tag_v in tags:
		var lst2: Array = by_tag[str(tag_v)]
		lst2.sort_custom(_hwy3_pair_priority_less)
		by_tag[str(tag_v)] = lst2
	foreign.sort_custom(_hwy3_pair_priority_less)
	var out: Array = []
	var round_i: int = 0
	var more: bool = true
	while more:
		more = false
		for tag2_v in tags:
			var lst3: Array = by_tag[str(tag2_v)]
			if round_i < lst3.size():
				out.append(lst3[round_i])
				more = true
		round_i += 1
		if round_i > 64:
			break
	for f_v in foreign:
		out.append(f_v)
	return out


static func _hwy3_apply_marked_highways(cache: Array, graph: Array, marked: Dictionary) -> int:
	var used: int = 0
	var found: int = 0
	var cache_by_key: Dictionary = {}
	for ci in range(cache.size()):
		var crow_v: Variant = cache[ci]
		if typeof(crow_v) != TYPE_DICTIONARY:
			continue
		var crow: Dictionary = crow_v
		var ck: int = _hwy1_row_key(crow)
		cache_by_key[ck] = ci
		if marked.has(ck):
			found += 1
			if not bool(crow.get("explicit", false)):
				crow["display_tier"] = TIER_HIGHWAY
				used += 1
	if found >= marked.size():
		return used
	for row_v in graph:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var gk: int = _hwy1_row_key(row)
		if not marked.has(gk) or cache_by_key.has(gk):
			continue
		var nrow: Dictionary = row.duplicate()
		nrow["display_tier"] = TIER_HIGHWAY
		cache.append(nrow)
		cache_by_key[gk] = cache.size() - 1
		if not bool(nrow.get("explicit", false)):
			used += 1
	return used


static func _hwy3_pick_hub_routes(cache: Array, inferred: Array, hub_ctx: Dictionary, mutant: String) -> void:
	var records_v: Variant = hub_ctx.get("records", [])
	var records: Array = records_v if typeof(records_v) == TYPE_ARRAY else []
	var use_urban: bool = bool(hub_ctx.get("use_urban", true))
	if mutant == "urban_required":
		use_urban = true
	var graph_v: Variant = hub_ctx.get("graph", cache)
	var graph: Array = graph_v if typeof(graph_v) == TYPE_ARRAY else cache
	var route_key: String = "%s|%s|%d" % [_hwy3_adj_cache_key(graph, use_urban), mutant, records.size()]
	if (
		mutant != "not_shortest"
		and route_key == _hwy3_route_memo_key
		and not _hwy3_route_memo_marked.is_empty()
	):
		var used_m: int = _hwy3_apply_marked_highways(cache, graph, _hwy3_route_memo_marked)
		last_hwy3_debug = _hwy3_route_memo_debug.duplicate()
		last_hwy3_debug["used"] = used_m
		last_hwy3_debug["mutant"] = mutant
		last_hwy3_debug["total_ms"] = 0.0
		return
	if mutant == "no_capitals":
		for rec_v in records:
			if typeof(rec_v) == TYPE_DICTIONARY:
				var rec_nc: Dictionary = rec_v
				if bool(rec_nc.get("capital", false)):
					rec_nc["_skip"] = true
	var t_all0: int = Time.get_ticks_usec()
	var recs_for_select: Array = records
	var select_v: Variant = hub_ctx.get("select_records", [])
	if typeof(select_v) == TYPE_ARRAY and (select_v as Array).size() > 0:
		recs_for_select = select_v
	if mutant == "urban_required":
		recs_for_select = []
		for rec2_v in records:
			if typeof(rec2_v) != TYPE_DICTIONARY:
				continue
			var rec2: Dictionary = rec2_v
			var only: Dictionary = rec2.duplicate()
			only["capital"] = false
			only["tier"] = 0
			only["population"] = 0
			only["industrial"] = false
			only["city_hub"] = false
			only["port"] = false
			recs_for_select.append(only)
	var hubs: Array = select_display_hubs(recs_for_select, use_urban)
	var hub_set: Dictionary = {}
	var rec_by_pid: Dictionary = {}
	var by_pid_v: Variant = hub_ctx.get("by_pid", {})
	if typeof(by_pid_v) == TYPE_DICTIONARY and not (by_pid_v as Dictionary).is_empty():
		rec_by_pid = by_pid_v
	else:
		for rec3_v in records:
			if typeof(rec3_v) != TYPE_DICTIONARY:
				continue
			var rec3: Dictionary = rec3_v
			var pid: int = int(rec3.get("pid", 0))
			if pid <= 0:
				continue
			rec_by_pid[pid] = rec3
	var attrs: Dictionary = rec_by_pid
	var centroids: Dictionary = rec_by_pid
	for h_v in hubs:
		var h: Dictionary = h_v
		hub_set[int(h.get("pid", 0))] = true
	var tag_borders_v: Variant = hub_ctx.get("tag_borders", {})
	var tag_borders: Dictionary = tag_borders_v if typeof(tag_borders_v) == TYPE_DICTIONARY else {}
	var pair_ids: Array = pair_hub_routes(hubs, tag_borders)
	var t_hubs_ms: float = float(Time.get_ticks_usec() - t_all0) / 1000.0
	var t_adj0: int = Time.get_ticks_usec()
	var adj_key: String = _hwy3_adj_cache_key(graph, use_urban)
	var adj: Dictionary = {}
	if adj_key != "" and adj_key == _hwy3_adj_memo_key and not _hwy3_adj_memo.is_empty():
		adj = _hwy3_adj_memo
	else:
		adj = _hwy3_build_adj(graph, attrs, use_urban)
		_hwy3_adj_memo_key = adj_key
		_hwy3_adj_memo = adj
	var t_adj_ms: float = float(Time.get_ticks_usec() - t_adj0) / 1000.0
	var t_route0: int = Time.get_ticks_usec()
	var graph_by_key: Dictionary = {}
	for row_v in graph:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		graph_by_key[_hwy1_row_key(row)] = row
	var cache_by_key: Dictionary = {}
	for ci in range(cache.size()):
		var crow_v: Variant = cache[ci]
		if typeof(crow_v) != TYPE_DICTIONARY:
			continue
		var crow: Dictionary = crow_v
		cache_by_key[_hwy1_row_key(crow)] = ci
	var scored_pairs: Array = []
	for pair_v in pair_ids:
		if typeof(pair_v) != TYPE_ARRAY:
			continue
		var pair: Array = pair_v
		if pair.size() < 2:
			continue
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		var ra: Dictionary = rec_by_pid.get(a, {})
		var rb: Dictionary = rec_by_pid.get(b, {})
		var ta: String = str(ra.get("tag", "")).strip_edges().to_upper()
		var tb: String = str(rb.get("tag", "")).strip_edges().to_upper()
		var sc: float = float(ra.get("score", 0.0)) + float(rb.get("score", 0.0))
		var ca: Vector2 = ra.get("centroid", Vector2.ZERO)
		var cb: Vector2 = rb.get("centroid", Vector2.ZERO)
		var pd: float = ca.distance_to(cb)
		if not is_finite(pd) or pd <= 0.0:
			pd = 999999.0
		scored_pairs.append({
			"a": a,
			"b": b,
			"score": sc,
			"key": _hwy3_pair_key(a, b),
			"dist": pd,
			"tag": ta if ta == tb else "",
		})
	var paint_pairs: Array = _hwy3_order_pairs_for_paint(scored_pairs)
	var inferred_n: int = inferred.size()
	if inferred_n <= 0:
		inferred_n = graph.size()
	var budget: int = _hwy1_budget(inferred_n)
	if budget <= 0:
		budget = 52
	var hi: int = int(floor(float(budget) * (1.0 + HWY3_BUDGET_SLACK)))
	if hi > 59:
		hi = 59
	if hi < 45:
		hi = 45
	var used: int = 0
	var routes: Array = []
	var marked: Dictionary = {}
	var not_shortest: bool = mutant == "not_shortest"
	for sp_v in paint_pairs:
		if used >= budget:
			break
		var sp: Dictionary = sp_v
		var a2: int = int(sp.get("a", 0))
		var b2: int = int(sp.get("b", 0))
		if not adj.has(a2) or not adj.has(b2):
			continue
		var pids: PackedInt32Array = shortest_hub_path(adj, a2, b2, not_shortest, attrs)
		if pids.size() - 1 < HWY3_MIN_PATH_EDGES:
			continue
		var shape: Dictionary = path_shape_report(pids, centroids, a2, b2, mutant)
		if not bool(shape.get("ok", false)):
			continue
		var keys: Array = []
		var new_n: int = 0
		for pi in range(1, pids.size()):
			var k: int = _hwy3_pair_key(int(pids[pi - 1]), int(pids[pi]))
			keys.append(k)
			if not marked.has(k):
				var cidx_v: Variant = cache_by_key.get(k, -1)
				var expl: bool = false
				if int(cidx_v) >= 0:
					expl = bool((cache[int(cidx_v)] as Dictionary).get("explicit", false))
				if not expl:
					new_n += 1
		if used + new_n > hi:
			continue
		for k2_v in keys:
			var k2: int = int(k2_v)
			if marked.has(k2):
				continue
			marked[k2] = true
			var idx_v: Variant = cache_by_key.get(k2, -1)
			if int(idx_v) >= 0:
				var er: Dictionary = cache[int(idx_v)]
				if not bool(er.get("explicit", false)):
					er["display_tier"] = TIER_HIGHWAY
					used += 1
			else:
				var grow: Variant = graph_by_key.get(k2, null)
				if typeof(grow) == TYPE_DICTIONARY:
					var nrow: Dictionary = (grow as Dictionary).duplicate()
					nrow["display_tier"] = TIER_HIGHWAY
					cache.append(nrow)
					cache_by_key[k2] = cache.size() - 1
					if not bool(nrow.get("explicit", false)):
						used += 1
		var pid_arr: Array = []
		for pii in range(pids.size()):
			pid_arr.append(int(pids[pii]))
		routes.append({
			"a": a2,
			"b": b2,
			"pids": pid_arr,
			"keys": keys,
			"length": float(shape.get("length", 0.0)),
			"straight": float(shape.get("straight", 0.0)),
		})
	var covered_hubs: Dictionary = {}
	for rt_c_v in routes:
		if typeof(rt_c_v) != TYPE_DICTIONARY:
			continue
		var rt_c: Dictionary = rt_c_v
		covered_hubs[int(rt_c.get("a", 0))] = true
		covered_hubs[int(rt_c.get("b", 0))] = true
		var pids_c_v: Variant = rt_c.get("pids", [])
		if typeof(pids_c_v) == TYPE_ARRAY:
			for pv_c in pids_c_v:
				covered_hubs[int(pv_c)] = true
	var do_cover: bool = used < 45
	for h5_v in hubs:
		if not do_cover or used >= hi:
			break
		var h5: Dictionary = h5_v
		var hp5: int = int(h5.get("pid", 0))
		if hp5 <= 0 or covered_hubs.has(hp5):
			continue
		if (
			(not bool(h5.get("capital", false)))
			and int(h5.get("tier", 0)) < 3
			and (not bool(h5.get("city_hub", false)))
		):
			continue
		if not adj.has(hp5):
			continue
		var tag5: String = str(h5.get("tag", "")).strip_edges().to_upper()
		var c5: Vector2 = h5.get("centroid", Vector2.ZERO)
		var best_o: int = 0
		var best_od: float = 1.0e18
		for h6_v in hubs:
			var h6: Dictionary = h6_v
			var op6: int = int(h6.get("pid", 0))
			if op6 == hp5 or not adj.has(op6):
				continue
			var d6: float = c5.distance_to(h6.get("centroid", Vector2.ZERO))
			if not is_finite(d6) or d6 <= 0.0:
				continue
			var ot6: String = str(h6.get("tag", "")).strip_edges().to_upper()
			if ot6 == tag5 and not tag5.is_empty():
				d6 *= 0.25
			if d6 < best_od or (d6 == best_od and op6 < best_o):
				best_od = d6
				best_o = op6
		if best_o <= 0:
			continue
		var pids5: PackedInt32Array = shortest_hub_path(adj, hp5, best_o, not_shortest, attrs)
		if pids5.size() - 1 < HWY3_MIN_PATH_EDGES:
			continue
		var shape5: Dictionary = path_shape_report(pids5, centroids, hp5, best_o, mutant)
		if not bool(shape5.get("ok", false)):
			continue
		var keys5: Array = []
		var new_n5: int = 0
		for pi5 in range(1, pids5.size()):
			var k5: int = _hwy3_pair_key(int(pids5[pi5 - 1]), int(pids5[pi5]))
			keys5.append(k5)
			if not marked.has(k5):
				var cidx5_v: Variant = cache_by_key.get(k5, -1)
				var expl5: bool = false
				if int(cidx5_v) >= 0:
					expl5 = bool((cache[int(cidx5_v)] as Dictionary).get("explicit", false))
				if not expl5:
					new_n5 += 1
		if used + new_n5 > hi:
			continue
		for k5b_v in keys5:
			var k5b: int = int(k5b_v)
			if marked.has(k5b):
				continue
			marked[k5b] = true
			var idx5_v: Variant = cache_by_key.get(k5b, -1)
			if int(idx5_v) >= 0:
				var er5: Dictionary = cache[int(idx5_v)]
				if not bool(er5.get("explicit", false)):
					er5["display_tier"] = TIER_HIGHWAY
					used += 1
			else:
				var grow5: Variant = graph_by_key.get(k5b, null)
				if typeof(grow5) == TYPE_DICTIONARY:
					var nrow5: Dictionary = (grow5 as Dictionary).duplicate()
					nrow5["display_tier"] = TIER_HIGHWAY
					cache.append(nrow5)
					cache_by_key[k5b] = cache.size() - 1
					if not bool(nrow5.get("explicit", false)):
						used += 1
		var pid_arr5: Array = []
		for pii5 in range(pids5.size()):
			pid_arr5.append(int(pids5[pii5]))
			covered_hubs[int(pids5[pii5])] = true
		routes.append({
			"a": hp5,
			"b": best_o,
			"pids": pid_arr5,
			"keys": keys5,
			"length": float(shape5.get("length", 0.0)),
			"straight": float(shape5.get("straight", 0.0)),
		})
	var hub_list: Array = []
	for h2_v in hubs:
		var h2: Dictionary = h2_v
		hub_list.append({
			"pid": int(h2.get("pid", 0)),
			"tag": str(h2.get("tag", "")),
			"score": float(h2.get("score", 0.0)),
			"capital": bool(h2.get("capital", false)),
			"tier": int(h2.get("tier", 0)),
			"urban": bool(h2.get("urban", false)),
			"urban_nbr": int(h2.get("urban_nbr", 0)),
		})
	last_hwy3_debug = {
		"mutant": mutant,
		"mode": "hub_routes",
		"use_urban": use_urban,
		"hubs": hub_list,
		"hub_set": hub_set,
		"pairs": pair_ids,
		"routes": routes,
		"records": records,
		"marked": marked.size(),
		"used": used,
		"budget": budget,
		"adj_ms": t_adj_ms,
		"hubs_ms": t_hubs_ms,
		"route_ms": float(Time.get_ticks_usec() - t_route0) / 1000.0,
		"total_ms": float(Time.get_ticks_usec() - t_all0) / 1000.0,
	}
	if mutant != "not_shortest":
		_hwy3_route_memo_key = route_key
		_hwy3_route_memo_marked = marked.duplicate()
		_hwy3_route_memo_debug = last_hwy3_debug.duplicate()
