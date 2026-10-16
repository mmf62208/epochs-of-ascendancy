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
const HWY3_BUDGET_MULT := 2
const HWY3_BUDGET_CAP := 114
const HWY3_SCORE_CAPITAL := 100000.0
const HWY3_SCORE_TIER := 800.0
const HWY3_SCORE_POP_DIV := 1000.0
const HWY3_SCORE_INDUSTRIAL := 500.0
const HWY3_SCORE_CITY_HUB := 400.0
const HWY3_SCORE_PORT := 200.0
const HWY3_SCORE_URBAN := 200.0
const HWY3_SCORE_URBAN_NBR := 120.0
const HWY3_MIN_PATH_EDGES := 2
## Urban agglomeration span (world units, ~NUTS3 hops). No pid whitelist.
const HWY3_URBAN_SPAN_MIN := 8.0
const HWY3_URBAN_SPAN_MAX := 28.0
const HWY3_URBAN_CLUSTER_R := 20.0
## Metro corridor: ≥3 named hubs inside this radius get thicker casing + labels.
const HWY3_METRO_CLUSTER_R := 30.0
const HWY3_METRO_MIN_HUBS := 3
const HWY3_METRO_CASING_MULT := 1.3
## Hub city labels (display only). Population is the province/city-layer pop on the hub record.
const HWY3_HUB_LABEL_ZOOM_MIN := 2.0
const HWY3_HUB_LABEL_POP_MIN := 15000
## Near-parallel drop: partial cover of sampled length within this distance.
const HWY3_PARALLEL_HAUSDORFF := 12.0
const HWY3_PARALLEL_END := 18.0
const HWY3_PARALLEL_COVER := 0.45
## Same-corridor drop: Jaccard on province sets, or one shared end + half the hops.
const HWY3_CORRIDOR_JACCARD := 0.5
const HWY3_CORRIDOR_SHARE := 0.5
const HWY3_TRUNK_MAX_DIST := 400.0
const HWY3_TRUNK_MIN_DIST := 32.0
## Capital connects to the top-2 hubs by score in distinct bearing sectors.
const HWY3_SECTOR_MIN_ANGLE := 1.5707963267948966 ## 90°
const HWY3_COVER_RESERVE := 24
## Trunks may overflow the paint hi so a second capital sector still commits.
## SPANs get a smaller overflow so Munich–Frankfurt is not starved after that.
const HWY3_TRUNK_OVERFLOW := 48
const HWY3_SPAN_OVERFLOW := 24
const HWY3_KIND_TRUNK := 2
const HWY3_KIND_SPAN := 1
const HWY3_KIND_OTHER := 0
const HWY3_MAJOR_TAGS := ["GER", "FRA", "ITA", "POL", "ENG", "USA", "JAP", "SOV"]
## Last hub-route rebuild (tests / overlay logs). Not gameplay state.
static var last_hwy3_debug: Dictionary = {}


static func hwy3_debug() -> Dictionary:
	return last_hwy3_debug


static func hwy3_set_debug(d: Dictionary) -> void:
	last_hwy3_debug = d


static var _hwy3_adj_memo_key: String = ""
static var _hwy3_adj_memo: Dictionary = {}
static var _hwy3_route_memo_key: String = ""
static var _hwy3_route_memo_marked: Dictionary = {}
static var _hwy3_route_memo_debug: Dictionary = {}


static func hwy3_clear_memos() -> void:
	_hwy3_adj_memo_key = ""
	_hwy3_adj_memo = {}
	_hwy3_route_memo_key = ""
	_hwy3_route_memo_marked = {}
	_hwy3_route_memo_debug = {}

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


static func hub_city_labels_visible_at_zoom(zoom: float) -> bool:
	return zoom + 0.0001 >= HWY3_HUB_LABEL_ZOOM_MIN


static func hwy3_city_label_text(rec: Dictionary) -> String:
	var cn: String = str(rec.get("city_name", "")).strip_edges()
	if cn.is_empty():
		cn = str(rec.get("name", "")).strip_edges()
	var comma: int = cn.find(",")
	if comma >= 0:
		cn = cn.substr(0, comma).strip_edges()
	return cn


static func should_label_hub_city(rec: Dictionary, zoom: float, cluster_n: int) -> bool:
	if not hub_city_labels_visible_at_zoom(zoom):
		return false
	if hwy3_city_label_text(rec).is_empty():
		return false
	if cluster_n >= HWY3_METRO_MIN_HUBS:
		return true
	if bool(rec.get("city_hub", false)) or bool(rec.get("capital", false)):
		return int(rec.get("population", 0)) >= HWY3_HUB_LABEL_POP_MIN or bool(rec.get("city_hub", false))
	if bool(rec.get("urban", false)) and int(rec.get("population", 0)) >= HWY3_HUB_LABEL_POP_MIN:
		return true
	return int(rec.get("population", 0)) >= HWY3_HUB_LABEL_POP_MIN and int(rec.get("tier", 0)) >= 2


static func hwy3_metro_cluster_n(hubs: Array, rec: Dictionary) -> int:
	var c: Vector2 = rec.get("centroid", Vector2.ZERO)
	if c == Vector2.ZERO:
		return 0
	var n: int = 0
	for h_v in hubs:
		if typeof(h_v) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_v
		if hwy3_city_label_text(h).is_empty():
			continue
		var hc: Vector2 = h.get("centroid", Vector2.ZERO)
		if hc == Vector2.ZERO:
			continue
		if c.distance_to(hc) <= HWY3_METRO_CLUSTER_R + 0.0001:
			n += 1
	return n


static func hwy3_metro_cluster_pids(hubs: Array) -> Dictionary:
	var out: Dictionary = {}
	for h_v in hubs:
		if typeof(h_v) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_v
		if hwy3_metro_cluster_n(hubs, h) >= HWY3_METRO_MIN_HUBS:
			var pid: int = int(h.get("pid", 0))
			if pid > 0:
				out[pid] = true
	return out


static func hwy3_drawn_highway_count(cache: Array) -> int:
	return _hwy3_count_highways(cache)


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
	var mutant: String = hwy3_mutant_name()
	var records_v: Variant = hub_ctx.get("records", [])
	var has_hubs: bool = typeof(records_v) == TYPE_ARRAY and (records_v as Array).size() > 0
	var graph_fast_v: Variant = hub_ctx.get("graph", cache)
	var graph_fast: Array = graph_fast_v if typeof(graph_fast_v) == TYPE_ARRAY else cache
	var use_urban_fast: bool = bool(hub_ctx.get("use_urban", true))
	if mutant == "urban_required":
		use_urban_fast = true
	var route_key_fast: String = "%s|%s|%d" % [
		_hwy3_adj_cache_key(graph_fast, use_urban_fast), mutant, (records_v as Array).size() if has_hubs else 0
	]
	if (
		has_hubs
		and mutant != "rank_grow_back"
		and mutant != "not_shortest"
		and route_key_fast == _hwy3_route_memo_key
		and not _hwy3_route_memo_marked.is_empty()
	):
		var used_fast: int = _hwy3_apply_marked_highways(cache, graph_fast, _hwy3_route_memo_marked)
		last_hwy3_debug = _hwy3_route_memo_debug.duplicate()
		var hubs_fast_v: Variant = last_hwy3_debug.get("hubs", [])
		var hubs_fast: Array = hubs_fast_v if typeof(hubs_fast_v) == TYPE_ARRAY else []
		_hwy3_stamp_metro_edges(cache, hubs_fast)
		last_hwy3_debug["used"] = used_fast
		last_hwy3_debug["drawn"] = _hwy3_count_highways(cache)
		last_hwy3_debug["mutant"] = mutant
		last_hwy3_debug["total_ms"] = 0.0
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
		return 4
	if land_n < 320:
		return 8
	if land_n < 500:
		return 12
	return 16


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
		var kept_pids: Dictionary = {}
		for rec3_v in lst2:
			if kept >= n_keep:
				break
			var rec3: Dictionary = rec3_v
			var sc3: float = float(rec3.get("score", 0.0))
			var is_cap3: bool = bool(rec3.get("capital", false))
			if is_cap3 or sc3 >= 50.0:
				hubs.append(rec3)
				kept_pids[int(rec3.get("pid", 0))] = true
				kept += 1
		if use_urban:
			var span_hubs: Array = _hwy3_select_urban_span_hubs(lst2, kept_pids)
			for su_v in span_hubs:
				if typeof(su_v) != TYPE_DICTIONARY:
					continue
				var su: Dictionary = su_v
				var spid: int = int(su.get("pid", 0))
				if spid <= 0 or kept_pids.has(spid):
					continue
				hubs.append(su)
				kept_pids[spid] = true
		var cap_keep: int = _hwy3_capital_hub_pid(lst2)
		var sector_keep: PackedInt32Array = _hwy3_sector_hub_pids(lst2, cap_keep)
		var second_keep: int = int(sector_keep[0]) if sector_keep.size() > 0 else 0
		if land_n >= 80:
			for si_k in range(sector_keep.size()):
				var keep_pid: int = int(sector_keep[si_k])
				if keep_pid <= 0 or kept_pids.has(keep_pid):
					continue
				for rec5_v in lst2:
					if typeof(rec5_v) != TYPE_DICTIONARY:
						continue
					var rec5: Dictionary = rec5_v
					if int(rec5.get("pid", 0)) != keep_pid:
						continue
					hubs.append(rec5)
					kept_pids[keep_pid] = true
					break
		var extra_spread: int = 0
		if HWY3_MAJOR_TAGS.has(tag):
			extra_spread = 3
		elif land_n >= 180:
			extra_spread = 2
		elif land_n >= 80:
			extra_spread = 1
		if extra_spread > 0:
			_hwy3_add_spread_hubs(lst2, hubs, kept_pids, extra_spread)
		if HWY3_MAJOR_TAGS.has(tag):
			_hwy3_add_steiner_hubs(lst2, hubs, kept_pids, 2)
		_hwy3_mark_periphery_hub(hubs, kept_pids, cap_keep, second_keep)
	hubs.sort_custom(_hwy3_score_pid_less)
	return hubs


static func _hwy3_is_spread_candidate(rec: Dictionary) -> bool:
	if bool(rec.get("capital", false)):
		return false
	if bool(rec.get("city_hub", false)):
		return true
	if int(rec.get("tier", 0)) >= 3:
		return true
	return false


static func _hwy3_add_spread_hubs(lst: Array, hubs: Array, kept_pids: Dictionary, extra: int) -> void:
	var guard: int = 0
	while extra > 0 and guard < 8:
		guard += 1
		var best_rec: Dictionary = {}
		var best_pid: int = 0
		var best_d: float = -1.0
		for rec_v in lst:
			if typeof(rec_v) != TYPE_DICTIONARY:
				continue
			var rec: Dictionary = rec_v
			var pid: int = int(rec.get("pid", 0))
			if pid <= 0 or kept_pids.has(pid):
				continue
			if not _hwy3_is_spread_candidate(rec):
				continue
			var c: Vector2 = rec.get("centroid", Vector2.ZERO)
			var md: float = 1.0e18
			for h_v in hubs:
				if typeof(h_v) != TYPE_DICTIONARY:
					continue
				var h: Dictionary = h_v
				if not kept_pids.has(int(h.get("pid", 0))):
					continue
				var d: float = c.distance_to(h.get("centroid", Vector2.ZERO))
				if is_finite(d) and d < md:
					md = d
			if not is_finite(md) or md < HWY3_TRUNK_MIN_DIST:
				continue
			if md > best_d or (md == best_d and pid < best_pid):
				best_d = md
				best_pid = pid
				best_rec = rec
		if best_pid <= 0:
			break
		best_rec["periphery"] = true
		hubs.append(best_rec)
		kept_pids[best_pid] = true
		extra -= 1


static func _hwy3_add_steiner_hubs(lst: Array, hubs: Array, kept_pids: Dictionary, extra: int) -> void:
	var guard: int = 0
	while extra > 0 and guard < 6:
		guard += 1
		var kept: Array = []
		for h_v in hubs:
			if typeof(h_v) != TYPE_DICTIONARY:
				continue
			var h: Dictionary = h_v
			if kept_pids.has(int(h.get("pid", 0))):
				kept.append(h)
		if kept.size() < 2:
			break
		var far_a: Dictionary = {}
		var far_b: Dictionary = {}
		var far_d: float = -1.0
		for i in range(kept.size()):
			var a: Dictionary = kept[i]
			var ac: Vector2 = a.get("centroid", Vector2.ZERO)
			for j in range(i + 1, kept.size()):
				var b: Dictionary = kept[j]
				var d: float = ac.distance_to(b.get("centroid", Vector2.ZERO))
				if d > far_d:
					far_d = d
					far_a = a
					far_b = b
		if far_d < HWY3_TRUNK_MIN_DIST * 2.0:
			break
		var mid: Vector2 = (far_a.get("centroid", Vector2.ZERO) + far_b.get("centroid", Vector2.ZERO)) * 0.5
		var best_rec: Dictionary = {}
		var best_pid: int = 0
		var best_d: float = 1.0e18
		for rec_v in lst:
			if typeof(rec_v) != TYPE_DICTIONARY:
				continue
			var rec: Dictionary = rec_v
			var pid: int = int(rec.get("pid", 0))
			if pid <= 0 or kept_pids.has(pid):
				continue
			if not _hwy3_is_spread_candidate(rec):
				continue
			var c: Vector2 = rec.get("centroid", Vector2.ZERO)
			var da: float = c.distance_to(far_a.get("centroid", Vector2.ZERO))
			var db: float = c.distance_to(far_b.get("centroid", Vector2.ZERO))
			if da < HWY3_TRUNK_MIN_DIST or db < HWY3_TRUNK_MIN_DIST:
				continue
			var dm: float = c.distance_to(mid)
			if not is_finite(dm):
				continue
			if dm < best_d or (dm == best_d and pid < best_pid):
				best_d = dm
				best_pid = pid
				best_rec = rec
		if best_pid <= 0:
			break
		hubs.append(best_rec)
		kept_pids[best_pid] = true
		extra -= 1


static func _hwy3_mark_periphery_hub(
	hubs: Array, kept_pids: Dictionary, cap_pid: int, second_pid: int = 0
) -> void:
	var cap_c: Vector2 = Vector2.ZERO
	var sec_c: Vector2 = Vector2.ZERO
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var pid0: int = int(rec.get("pid", 0))
		if pid0 == cap_pid:
			cap_c = rec.get("centroid", Vector2.ZERO)
		if second_pid > 0 and pid0 == second_pid:
			sec_c = rec.get("centroid", Vector2.ZERO)
	var outlier_min: float = HWY3_TRUNK_MIN_DIST * 2.5
	var best_pid: int = 0
	var best_d: float = -1.0
	var best_city: int = 0
	var best_city_d: float = -1.0
	for rec2_v in hubs:
		if typeof(rec2_v) != TYPE_DICTIONARY:
			continue
		var rec2: Dictionary = rec2_v
		var pid: int = int(rec2.get("pid", 0))
		if pid <= 0 or pid == cap_pid or pid == second_pid or not kept_pids.has(pid):
			continue
		if not _hwy3_is_spread_candidate(rec2):
			continue
		var c2: Vector2 = rec2.get("centroid", Vector2.ZERO)
		var d_cap: float = cap_c.distance_to(c2)
		var d_sec: float = sec_c.distance_to(c2) if sec_c != Vector2.ZERO else d_cap
		var d_near: float = minf(d_cap, d_sec)
		if not is_finite(d_near):
			continue
		if d_cap > best_d:
			best_d = d_cap
			best_pid = pid
		var is_city: bool = bool(rec2.get("city_hub", false)) or int(rec2.get("tier", 0)) >= 3
		if is_city and (d_cap > best_city_d or (d_cap == best_city_d and (best_city <= 0 or pid < best_city))):
			best_city_d = d_cap
			best_city = pid
		if d_near >= outlier_min:
			rec2["periphery"] = true
	if best_city > 0:
		best_pid = best_city
	if best_pid <= 0:
		return
	for rec3_v in hubs:
		if typeof(rec3_v) != TYPE_DICTIONARY:
			continue
		var rec3: Dictionary = rec3_v
		if int(rec3.get("pid", 0)) == best_pid:
			rec3["periphery"] = true
			rec3["periphery_primary"] = true
			break


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
	var cap_pid: int = _hwy3_capital_hub_pid(hubs)
	var sector_pids: PackedInt32Array = _hwy3_sector_hub_pids(hubs, cap_pid)
	for spi in range(sector_pids.size()):
		var sector_pid: int = int(sector_pids[spi])
		if cap_pid > 0 and sector_pid > 0:
			_hwy3_add_pair(pairs, cap_pid, sector_pid)
	var span: Vector2i = _hwy3_urban_span_pair_ids(hubs)
	if span.x > 0 and span.y > 0:
		_hwy3_add_pair(pairs, span.x, span.y)
		var att: Vector2i = _hwy3_urban_span_attach_ids(hubs, span)
		if att.x > 0 and att.y > 0:
			_hwy3_add_pair(pairs, att.x, att.y)
	_hwy3_add_periphery_pairs(pairs, hubs)


static func _hwy3_add_periphery_pairs(pairs: Dictionary, hubs: Array) -> void:
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if not bool(rec.get("periphery", false)):
			continue
		var peri_pid: int = int(rec.get("pid", 0))
		if peri_pid <= 0:
			continue
		var attach: int = _hwy3_nearest_city_hub(hubs, Vector2i(peri_pid, peri_pid))
		if attach <= 0:
			attach = _hwy3_farthest_city_hub(hubs, peri_pid)
		if attach > 0:
			_hwy3_add_pair(pairs, peri_pid, attach)


static func _hwy3_capital_hub_pid(hubs: Array) -> int:
	var best: int = 0
	var best_sc: float = -1.0
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if not bool(rec.get("capital", false)):
			continue
		var sc: float = float(rec.get("score", 0.0))
		var pid: int = int(rec.get("pid", 0))
		if sc > best_sc or (sc == best_sc and (best <= 0 or pid < best)):
			best_sc = sc
			best = pid
	return best


static func _hwy3_hub_dist_ok(cap_c: Vector2, rec: Dictionary) -> bool:
	if cap_c == Vector2.ZERO:
		return true
	var d: float = cap_c.distance_to(rec.get("centroid", Vector2.ZERO))
	if not is_finite(d):
		return false
	if d < HWY3_TRUNK_MIN_DIST:
		return false
	if d > HWY3_TRUNK_MAX_DIST:
		return false
	return true


static func _hwy3_second_hub_pid(hubs: Array, cap_pid: int) -> int:
	var cap_c: Vector2 = Vector2.ZERO
	for rec0_v in hubs:
		if typeof(rec0_v) != TYPE_DICTIONARY:
			continue
		var rec0: Dictionary = rec0_v
		if int(rec0.get("pid", 0)) == cap_pid:
			cap_c = rec0.get("centroid", Vector2.ZERO)
			break
	var rows: Array = []
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		rows.append(rec_v)
	rows.sort_custom(_hwy3_score_pid_less)
	for rec2_v in rows:
		var rec2: Dictionary = rec2_v
		var pid: int = int(rec2.get("pid", 0))
		if pid <= 0 or pid == cap_pid:
			continue
		if not bool(rec2.get("city_hub", false)):
			continue
		if not _hwy3_hub_dist_ok(cap_c, rec2):
			continue
		return pid
	for rec3_v in rows:
		var rec3: Dictionary = rec3_v
		var pid3: int = int(rec3.get("pid", 0))
		if pid3 <= 0 or pid3 == cap_pid:
			continue
		if int(rec3.get("tier", 0)) < 3:
			continue
		if not _hwy3_hub_dist_ok(cap_c, rec3):
			continue
		return pid3
	for rec4_v in rows:
		var rec4: Dictionary = rec4_v
		var pid4: int = int(rec4.get("pid", 0))
		if pid4 <= 0 or pid4 == cap_pid:
			continue
		if not _hwy3_hub_dist_ok(cap_c, rec4):
			continue
		return pid4
	return 0


static func _hwy3_bearing(from_c: Vector2, to_c: Vector2) -> float:
	var d: Vector2 = to_c - from_c
	if d == Vector2.ZERO:
		return 0.0
	return d.angle()


static func _hwy3_sectors_apart(a: float, b: float) -> bool:
	return absf(angle_difference(a, b)) + 0.0001 >= HWY3_SECTOR_MIN_ANGLE


static func _hwy3_unpicked_second_sector_hub(
	pid: int,
	tag: String,
	second_by_tag: Dictionary,
	sector2_by_tag: Dictionary,
	rec_by_pid: Dictionary,
	hubs_by_tag: Dictionary
) -> bool:
	if not HWY3_MAJOR_TAGS.has(tag):
		return false
	if int(sector2_by_tag.get(tag, 0)) > 0:
		return false
	var first: int = int(second_by_tag.get(tag, 0))
	if first <= 0 or pid == first or pid <= 0:
		return false
	var hl_v: Variant = hubs_by_tag.get(tag, [])
	var hl: Array = hl_v if typeof(hl_v) == TYPE_ARRAY else []
	var cap: int = _hwy3_capital_hub_pid(hl)
	if cap <= 0 or pid == cap:
		return false
	var cap_v: Variant = rec_by_pid.get(cap, {})
	var first_v: Variant = rec_by_pid.get(first, {})
	var other_v: Variant = rec_by_pid.get(pid, {})
	if typeof(cap_v) != TYPE_DICTIONARY or typeof(first_v) != TYPE_DICTIONARY or typeof(other_v) != TYPE_DICTIONARY:
		return false
	var cap_c: Vector2 = (cap_v as Dictionary).get("centroid", Vector2.ZERO)
	var first_br: float = _hwy3_bearing(cap_c, (first_v as Dictionary).get("centroid", Vector2.ZERO))
	var other_br: float = _hwy3_bearing(cap_c, (other_v as Dictionary).get("centroid", Vector2.ZERO))
	return _hwy3_sectors_apart(first_br, other_br)


static func _hwy3_pair_is_dropped_second_sector(
	a: int,
	b: int,
	tag: String,
	second_by_tag: Dictionary,
	sector2_by_tag: Dictionary,
	rec_by_pid: Dictionary,
	hubs_by_tag: Dictionary
) -> bool:
	if int(sector2_by_tag.get(tag, 0)) > 0:
		return false
	var hl_v: Variant = hubs_by_tag.get(tag, [])
	var hl: Array = hl_v if typeof(hl_v) == TYPE_ARRAY else []
	var cap: int = _hwy3_capital_hub_pid(hl)
	if cap <= 0:
		return false
	if a == cap:
		return _hwy3_unpicked_second_sector_hub(
			b, tag, second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		)
	if b == cap:
		return _hwy3_unpicked_second_sector_hub(
			a, tag, second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		)
	return false


static func _hwy3_path_touches_dropped_second_sector(
	pids_any: Variant,
	tag: String,
	second_by_tag: Dictionary,
	sector2_by_tag: Dictionary,
	rec_by_pid: Dictionary,
	hubs_by_tag: Dictionary
) -> bool:
	if int(sector2_by_tag.get(tag, 0)) > 0:
		return false
	var hl_v: Variant = hubs_by_tag.get(tag, [])
	var hl: Array = hl_v if typeof(hl_v) == TYPE_ARRAY else []
	var cap: int = _hwy3_capital_hub_pid(hl)
	if cap <= 0:
		return false
	var pids: Array = pids_any if typeof(pids_any) == TYPE_ARRAY else []
	if pids.is_empty() and typeof(pids_any) == TYPE_PACKED_INT32_ARRAY:
		for pi in range((pids_any as PackedInt32Array).size()):
			pids.append(int((pids_any as PackedInt32Array)[pi]))
	var has_cap: bool = false
	var has_opp: bool = false
	for pv in pids:
		var pid: int = int(pv)
		if pid == cap:
			has_cap = true
		elif _hwy3_unpicked_second_sector_hub(
			pid, tag, second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		):
			has_opp = true
	return has_cap and has_opp


static func _hwy3_second_sector_hub_pid(hubs: Array, cap_pid: int, first_pid: int) -> int:
	if first_pid <= 0:
		return 0
	var cap_c: Vector2 = Vector2.ZERO
	var first_c: Vector2 = Vector2.ZERO
	for rec0_v in hubs:
		if typeof(rec0_v) != TYPE_DICTIONARY:
			continue
		var rec0: Dictionary = rec0_v
		var pid0: int = int(rec0.get("pid", 0))
		if pid0 == cap_pid:
			cap_c = rec0.get("centroid", Vector2.ZERO)
		elif pid0 == first_pid:
			first_c = rec0.get("centroid", Vector2.ZERO)
	var first_br: float = _hwy3_bearing(cap_c, first_c)
	var rows: Array = []
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		rows.append(rec_v)
	rows.sort_custom(_hwy3_score_pid_less)
	var passes: Array = [
		{"city": true, "tier": 0},
		{"city": false, "tier": 3},
		{"city": false, "tier": 0},
	]
	for pass_v in passes:
		var prow: Dictionary = pass_v
		var need_city: bool = bool(prow.get("city", false))
		var need_tier: int = int(prow.get("tier", 0))
		for rec2_v in rows:
			var rec2: Dictionary = rec2_v
			var pid: int = int(rec2.get("pid", 0))
			if pid <= 0 or pid == cap_pid or pid == first_pid:
				continue
			if need_city and not bool(rec2.get("city_hub", false)):
				continue
			if need_tier > 0 and int(rec2.get("tier", 0)) < need_tier:
				continue
			if not _hwy3_hub_dist_ok(cap_c, rec2):
				continue
			var br: float = _hwy3_bearing(cap_c, rec2.get("centroid", Vector2.ZERO))
			if not _hwy3_sectors_apart(first_br, br):
				continue
			return pid
	return 0


static func _hwy3_sector_hub_pids(hubs: Array, cap_pid: int) -> PackedInt32Array:
	## Score #2 only. The opposite-sector capital span (Rome-north) is added
	## exclusively by _hwy3_reachable_sectors so a source-edit on that line
	## can kill it. Bearing-only second here is not the live path.
	var out: PackedInt32Array = PackedInt32Array()
	var first: int = _hwy3_second_hub_pid(hubs, cap_pid)
	if first > 0:
		out.append(first)
	return out


static func _hwy3_reachable_second(hubs: Array, cap_pid: int, adj: Dictionary, attrs: Dictionary) -> int:
	var cap_c: Vector2 = Vector2.ZERO
	for rec0_v in hubs:
		if typeof(rec0_v) != TYPE_DICTIONARY:
			continue
		var rec0: Dictionary = rec0_v
		if int(rec0.get("pid", 0)) == cap_pid:
			cap_c = rec0.get("centroid", Vector2.ZERO)
			break
	var rows: Array = []
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		rows.append(rec_v)
	rows.sort_custom(_hwy3_score_pid_less)
	var tf: String = ""
	if cap_pid > 0 and attrs.has(cap_pid):
		var cap_rec_v: Variant = attrs.get(cap_pid, {})
		if typeof(cap_rec_v) == TYPE_DICTIONARY:
			tf = str((cap_rec_v as Dictionary).get("tag", "")).strip_edges().to_upper()
	var prev: Dictionary = {}
	if cap_pid > 0 and adj.has(cap_pid):
		prev = _hwy3_dijkstra_prev(adj, cap_pid, tf, attrs, 0)
	if prev.is_empty():
		return 0
	var found: int = _hwy3_second_from_rows(rows, cap_pid, cap_c, prev, attrs)
	if found > 0:
		return found
	var extra_rows: Array = []
	for ak in attrs.keys():
		var ar_v: Variant = attrs.get(ak, {})
		if typeof(ar_v) != TYPE_DICTIONARY:
			continue
		var ar: Dictionary = ar_v
		if str(ar.get("tag", "")).strip_edges().to_upper() != tf:
			continue
		if int(ar.get("pid", 0)) == cap_pid:
			continue
		extra_rows.append(ar)
	extra_rows.sort_custom(_hwy3_score_pid_less)
	return _hwy3_second_from_rows(extra_rows, cap_pid, cap_c, prev, attrs)


static func _hwy3_second_sector_from_rows(
	rows: Array,
	cap_pid: int,
	cap_c: Vector2,
	first_pid: int,
	first_br: float,
	prev: Dictionary,
	attrs: Dictionary
) -> int:
	var passes: Array = [
		{"city": true, "tier": 0},
		{"city": false, "tier": 3},
		{"city": false, "tier": 0},
	]
	for pass_v in passes:
		var prow: Dictionary = pass_v
		var need_city: bool = bool(prow.get("city", false))
		var need_tier: int = int(prow.get("tier", 0))
		for rec2_v in rows:
			if typeof(rec2_v) != TYPE_DICTIONARY:
				continue
			var rec2: Dictionary = rec2_v
			var pid: int = int(rec2.get("pid", 0))
			if pid <= 0 or pid == cap_pid or pid == first_pid:
				continue
			if need_city and not bool(rec2.get("city_hub", false)):
				continue
			if need_tier > 0 and int(rec2.get("tier", 0)) < need_tier:
				continue
			if cap_c != Vector2.ZERO:
				var d2: float = cap_c.distance_to(rec2.get("centroid", Vector2.ZERO))
				if not is_finite(d2) or d2 < HWY3_TRUNK_MIN_DIST:
					continue
			var br: float = _hwy3_bearing(cap_c, rec2.get("centroid", Vector2.ZERO))
			if not _hwy3_sectors_apart(first_br, br):
				continue
			if not prev.has(pid):
				continue
			var packed: PackedInt32Array = _hwy3_extract_path(prev, cap_pid, pid)
			if packed.size() - 1 < HWY3_MIN_PATH_EDGES:
				continue
			var shp: Dictionary = path_shape_report(packed, attrs, cap_pid, pid, "")
			if not bool(shp.get("ok", false)):
				continue
			return pid
	return 0


static func _hwy3_reachable_second_sector(
	hubs: Array, cap_pid: int, first_pid: int, adj: Dictionary, attrs: Dictionary
) -> int:
	if first_pid <= 0:
		return 0
	var cap_c: Vector2 = Vector2.ZERO
	var first_c: Vector2 = Vector2.ZERO
	for rec0_v in hubs:
		if typeof(rec0_v) != TYPE_DICTIONARY:
			continue
		var rec0: Dictionary = rec0_v
		var pid0: int = int(rec0.get("pid", 0))
		if pid0 == cap_pid:
			cap_c = rec0.get("centroid", Vector2.ZERO)
		elif pid0 == first_pid:
			first_c = rec0.get("centroid", Vector2.ZERO)
	var first_br: float = _hwy3_bearing(cap_c, first_c)
	var rows: Array = []
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		rows.append(rec_v)
	rows.sort_custom(_hwy3_score_pid_less)
	var tf: String = ""
	if cap_pid > 0 and attrs.has(cap_pid):
		var cap_rec_v: Variant = attrs.get(cap_pid, {})
		if typeof(cap_rec_v) == TYPE_DICTIONARY:
			tf = str((cap_rec_v as Dictionary).get("tag", "")).strip_edges().to_upper()
	var prev: Dictionary = {}
	if cap_pid > 0 and adj.has(cap_pid):
		prev = _hwy3_dijkstra_prev(adj, cap_pid, tf, attrs, 0)
	if prev.is_empty():
		return 0
	var found: int = _hwy3_second_sector_from_rows(
		rows, cap_pid, cap_c, first_pid, first_br, prev, attrs
	)
	if found > 0:
		return found
	var extra_rows: Array = []
	for ak in attrs.keys():
		var ar_v: Variant = attrs.get(ak, {})
		if typeof(ar_v) != TYPE_DICTIONARY:
			continue
		var ar: Dictionary = ar_v
		if str(ar.get("tag", "")).strip_edges().to_upper() != tf:
			continue
		if int(ar.get("pid", 0)) == cap_pid or int(ar.get("pid", 0)) == first_pid:
			continue
		extra_rows.append(ar)
	extra_rows.sort_custom(_hwy3_score_pid_less)
	return _hwy3_second_sector_from_rows(
		extra_rows, cap_pid, cap_c, first_pid, first_br, prev, attrs
	)


static func _hwy3_reachable_sectors(
	hubs: Array, cap_pid: int, adj: Dictionary, attrs: Dictionary
) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var first: int = _hwy3_reachable_second(hubs, cap_pid, adj, attrs)
	if first > 0:
		out.append(first)
	var second: int = _hwy3_reachable_second_sector(hubs, cap_pid, first, adj, attrs)
	if second > 0:
		out.append(second)
	return out


static func _hwy3_farthest_valid_second(
	rows: Array, cap_pid: int, cap_c: Vector2, prev: Dictionary, attrs: Dictionary
) -> int:
	var best: int = 0
	var best_d: float = -1.0
	for rec_v in rows:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var pid: int = int(rec.get("pid", 0))
		if pid <= 0 or pid == cap_pid:
			continue
		if not bool(rec.get("city_hub", false)) and int(rec.get("tier", 0)) < 3:
			continue
		if not prev.has(pid):
			continue
		var packed: PackedInt32Array = _hwy3_extract_path(prev, cap_pid, pid)
		if packed.size() - 1 < HWY3_MIN_PATH_EDGES:
			continue
		var shp: Dictionary = path_shape_report(packed, attrs, cap_pid, pid, "")
		if not bool(shp.get("ok", false)):
			continue
		var d: float = cap_c.distance_to(rec.get("centroid", Vector2.ZERO))
		if cap_c == Vector2.ZERO:
			d = float(packed.size())
		if not is_finite(d) or d < HWY3_TRUNK_MIN_DIST:
			continue
		if d > best_d or (d == best_d and pid < best):
			best_d = d
			best = pid
	return best


static func _hwy3_second_from_rows(
	rows: Array, cap_pid: int, cap_c: Vector2, prev: Dictionary, attrs: Dictionary
) -> int:
	var passes: Array = [
		{"city": true, "tier": 0},
		{"city": false, "tier": 3},
		{"city": false, "tier": 0},
	]
	for pass_v in passes:
		var prow: Dictionary = pass_v
		var need_city: bool = bool(prow.get("city", false))
		var need_tier: int = int(prow.get("tier", 0))
		for rec2_v in rows:
			var rec2: Dictionary = rec2_v
			var pid: int = int(rec2.get("pid", 0))
			if pid <= 0 or pid == cap_pid:
				continue
			if need_city and not bool(rec2.get("city_hub", false)):
				continue
			if need_tier > 0 and int(rec2.get("tier", 0)) < need_tier:
				continue
			if cap_c != Vector2.ZERO:
				var d2: float = cap_c.distance_to(rec2.get("centroid", Vector2.ZERO))
				if not is_finite(d2) or d2 < HWY3_TRUNK_MIN_DIST:
					continue
			if not prev.has(pid):
				continue
			var packed: PackedInt32Array = _hwy3_extract_path(prev, cap_pid, pid)
			if packed.size() - 1 < HWY3_MIN_PATH_EDGES:
				continue
			var shp: Dictionary = path_shape_report(packed, attrs, cap_pid, pid, "")
			if not bool(shp.get("ok", false)):
				continue
			return pid
	return 0


static func _hwy3_select_urban_span_hubs(lst: Array, kept_pids: Dictionary) -> Array:
	var cands: Array = []
	for rec_v in lst:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var pid0: int = int(rec.get("pid", 0))
		if pid0 <= 0 or kept_pids.has(pid0):
			continue
		if not bool(rec.get("urban", false)):
			continue
		if int(rec.get("urban_nbr", 0)) < 2:
			continue
		cands.append(rec)
	var pair: Vector2i = _hwy3_urban_span_pair_ids(cands)
	var out: Array = []
	if pair.x > 0 and pair.y > 0:
		for rec2_v in cands:
			var rec2: Dictionary = rec2_v
			var pid2: int = int(rec2.get("pid", 0))
			if pid2 == pair.x or pid2 == pair.y:
				if not kept_pids.has(pid2):
					out.append(rec2)
		return out
	var best_u: Dictionary = {}
	var best_un: int = -1
	var best_us: float = -1.0
	var best_up: int = 1 << 30
	for rec3_v in cands:
		var rec3: Dictionary = rec3_v
		var pid3: int = int(rec3.get("pid", 0))
		if kept_pids.has(pid3):
			continue
		var un3: int = int(rec3.get("urban_nbr", 0))
		var sc3: float = float(rec3.get("score", 0.0))
		if (
			un3 > best_un
			or (un3 == best_un and sc3 > best_us)
			or (un3 == best_un and sc3 == best_us and pid3 < best_up)
		):
			best_u = rec3
			best_un = un3
			best_us = sc3
			best_up = pid3
	if not best_u.is_empty():
		out.append(best_u)
	return out


static func _hwy3_nearest_city_hub(hubs: Array, span: Vector2i) -> int:
	var best: int = 0
	var best_d: float = 1.0e18
	var ca: Vector2 = Vector2.ZERO
	var cb: Vector2 = Vector2.ZERO
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var pid: int = int(rec.get("pid", 0))
		if pid == span.x:
			ca = rec.get("centroid", Vector2.ZERO)
		elif pid == span.y:
			cb = rec.get("centroid", Vector2.ZERO)
	for rec2_v in hubs:
		if typeof(rec2_v) != TYPE_DICTIONARY:
			continue
		var rec2: Dictionary = rec2_v
		var pid2: int = int(rec2.get("pid", 0))
		if pid2 == span.x or pid2 == span.y:
			continue
		if not bool(rec2.get("city_hub", false)) and int(rec2.get("tier", 0)) < 3:
			continue
		var c2: Vector2 = rec2.get("centroid", Vector2.ZERO)
		var d: float = minf(c2.distance_to(ca), c2.distance_to(cb))
		if not is_finite(d) or d <= 0.0:
			continue
		if d < best_d or (d == best_d and pid2 < best):
			best_d = d
			best = pid2
	return best


static func _hwy3_urban_span_attach_ids(hubs: Array, span: Vector2i) -> Vector2i:
	if span.x <= 0 or span.y <= 0:
		return Vector2i.ZERO
	var attach: int = _hwy3_nearest_city_hub(hubs, span)
	if attach <= 0:
		return Vector2i.ZERO
	var rec_a: Dictionary = {}
	var rec_b: Dictionary = {}
	var rec_t: Dictionary = {}
	for hv in hubs:
		if typeof(hv) != TYPE_DICTIONARY:
			continue
		var hr: Dictionary = hv
		var hpid: int = int(hr.get("pid", 0))
		if hpid == span.x:
			rec_a = hr
		elif hpid == span.y:
			rec_b = hr
		elif hpid == attach:
			rec_t = hr
	var near_span: int = span.x
	var tc: Vector2 = rec_t.get("centroid", Vector2.ZERO)
	var da: float = tc.distance_to(rec_a.get("centroid", Vector2.ZERO))
	var db: float = tc.distance_to(rec_b.get("centroid", Vector2.ZERO))
	if db < da:
		near_span = span.y
	return Vector2i(near_span, attach)


static func _hwy3_farthest_city_hub(hubs: Array, from_pid: int) -> int:
	var from_c: Vector2 = Vector2.ZERO
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if int(rec.get("pid", 0)) == from_pid:
			from_c = rec.get("centroid", Vector2.ZERO)
			break
	var best: int = 0
	var best_d: float = -1.0
	for rec2_v in hubs:
		if typeof(rec2_v) != TYPE_DICTIONARY:
			continue
		var rec2: Dictionary = rec2_v
		var pid2: int = int(rec2.get("pid", 0))
		if pid2 == from_pid:
			continue
		if not bool(rec2.get("city_hub", false)) and int(rec2.get("tier", 0)) < 3:
			continue
		var d: float = from_c.distance_to(rec2.get("centroid", Vector2.ZERO))
		if not is_finite(d) or d < HWY3_TRUNK_MIN_DIST:
			continue
		if d > best_d or (d == best_d and pid2 < best):
			best_d = d
			best = pid2
	return best


static func _hwy3_city_hubs_by_dist(hubs: Array, from_pid: int) -> Array:
	var from_c: Vector2 = Vector2.ZERO
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if int(rec.get("pid", 0)) == from_pid:
			from_c = rec.get("centroid", Vector2.ZERO)
			break
	var rows: Array = []
	for rec2_v in hubs:
		if typeof(rec2_v) != TYPE_DICTIONARY:
			continue
		var rec2: Dictionary = rec2_v
		var pid2: int = int(rec2.get("pid", 0))
		if pid2 <= 0 or pid2 == from_pid:
			continue
		if not bool(rec2.get("city_hub", false)) and int(rec2.get("tier", 0)) < 3:
			continue
		var d: float = from_c.distance_to(rec2.get("centroid", Vector2.ZERO))
		if not is_finite(d) or d < HWY3_TRUNK_MIN_DIST:
			continue
		rows.append({"pid": pid2, "dist": d, "key": _hwy3_pair_key(from_pid, pid2)})
	rows.sort_custom(_hwy3_dist_pid_less)
	return rows


static func _hwy3_is_major_city_hub(rec: Dictionary) -> bool:
	if bool(rec.get("capital", false)):
		return false
	var tag: String = str(rec.get("tag", "")).strip_edges().to_upper()
	if not HWY3_MAJOR_TAGS.has(tag):
		return false
	if bool(rec.get("city_hub", false)):
		return true
	return int(rec.get("tier", 0)) >= 3


static func _hwy3_is_urban_span_candidate(rec: Dictionary) -> bool:
	if not bool(rec.get("urban", false)):
		return false
	if int(rec.get("urban_nbr", 0)) < 2:
		return false
	if bool(rec.get("capital", false)):
		return false
	if int(rec.get("tier", 0)) >= 3 and bool(rec.get("city_hub", false)):
		return false
	return true


static func _hwy3_urban_span_pair_ids(hubs: Array) -> Vector2i:
	var cands: Array = []
	for rec_v in hubs:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if _hwy3_is_urban_span_candidate(rec):
			cands.append(rec)
	if cands.size() < 2:
		return Vector2i.ZERO
	var seed_i: int = 0
	var seed_sc: float = -1.0
	for i in range(cands.size()):
		var a: Dictionary = cands[i]
		var ac: Vector2 = a.get("centroid", Vector2.ZERO)
		var sc: float = 0.0
		for j in range(cands.size()):
			var b: Dictionary = cands[j]
			var d: float = ac.distance_to(b.get("centroid", Vector2.ZERO))
			if is_finite(d) and d <= HWY3_URBAN_CLUSTER_R:
				sc += 1.0 + float(int(b.get("urban_nbr", 0)))
		if sc > seed_sc or (sc == seed_sc and int(a.get("pid", 0)) < int((cands[seed_i] as Dictionary).get("pid", 0))):
			seed_sc = sc
			seed_i = i
	var cluster: Array = []
	var seed_c: Vector2 = (cands[seed_i] as Dictionary).get("centroid", Vector2.ZERO)
	for c2_v in cands:
		var c2: Dictionary = c2_v
		var d2: float = seed_c.distance_to(c2.get("centroid", Vector2.ZERO))
		if is_finite(d2) and d2 <= HWY3_URBAN_CLUSTER_R:
			cluster.append(c2)
	var best_a: int = 0
	var best_b: int = 0
	var best_val: float = -1.0
	for i2 in range(cluster.size()):
		var u: Dictionary = cluster[i2]
		var up: int = int(u.get("pid", 0))
		var ua: int = int(u.get("urban_nbr", 0))
		var uc: Vector2 = u.get("centroid", Vector2.ZERO)
		for j2 in range(i2 + 1, cluster.size()):
			var v: Dictionary = cluster[j2]
			var vp: int = int(v.get("pid", 0))
			var ub: int = int(v.get("urban_nbr", 0))
			var d3: float = uc.distance_to(v.get("centroid", Vector2.ZERO))
			if not is_finite(d3) or d3 < HWY3_URBAN_SPAN_MIN:
				continue
			var val: float = d3 * float(ua + ub)
			if val > best_val or (val == best_val and mini(up, vp) < mini(best_a, best_b)):
				best_val = val
				best_a = mini(up, vp)
				best_b = maxi(up, vp)
	return Vector2i(best_a, best_b)


static func _hwy3_point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 <= 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _hwy3_point_poly_dist(p: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() <= 0:
		return 1.0e18
	if poly.size() == 1:
		return p.distance_to(poly[0])
	var best: float = 1.0e18
	for i in range(1, poly.size()):
		var d: float = _hwy3_point_seg_dist(p, poly[i - 1], poly[i])
		if d < best:
			best = d
	return best


static func _hwy3_route_polyline(pids: Array, cents: Dictionary) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array()
	for pv in pids:
		var pid: int = int(pv)
		poly.append(_hwy3_cent_from(cents, pid))
	return poly


static func _hwy3_partial_cover(a: PackedVector2Array, b: PackedVector2Array, thresh: float) -> float:
	if a.size() < 2:
		return 0.0
	var covered: float = 0.0
	var total: float = 0.0
	for i in range(1, a.size()):
		var p0: Vector2 = a[i - 1]
		var p1: Vector2 = a[i]
		var seg: float = p0.distance_to(p1)
		if seg <= 0.0001:
			continue
		total += seg
		var mid: Vector2 = (p0 + p1) * 0.5
		if _hwy3_point_poly_dist(mid, b) <= thresh + 0.0001:
			covered += seg
	if total <= 0.0001:
		return 0.0
	return covered / total


static func _hwy3_end_region_share(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> int:
	var same: float = a0.distance_to(b0) + a1.distance_to(b1)
	var swap: float = a0.distance_to(b1) + a1.distance_to(b0)
	var aligned: bool = same <= swap
	var d0: float = a0.distance_to(b0) if aligned else a0.distance_to(b1)
	var d1: float = a1.distance_to(b1) if aligned else a1.distance_to(b0)
	var n: int = 0
	if d0 <= HWY3_PARALLEL_END + 0.0001:
		n += 1
	if d1 <= HWY3_PARALLEL_END + 0.0001:
		n += 1
	return n


static func _hwy3_route_pid_set(rt: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var pids_v: Variant = rt.get("pids", [])
	if typeof(pids_v) == TYPE_ARRAY:
		var pids: Array = pids_v
		for pv in pids:
			var pid: int = int(pv)
			if pid > 0:
				out[pid] = true
	elif typeof(pids_v) == TYPE_PACKED_INT32_ARRAY:
		var packed: PackedInt32Array = pids_v
		for i in range(packed.size()):
			var pid2: int = int(packed[i])
			if pid2 > 0:
				out[pid2] = true
	return out


## Same drawn corridor: Jaccard ≥ 0.5, or a shared endpoint plus ≥50% of either set.
## overlap_ok leaves both copies so the independent Hub3 assert can kill the mutant.
static func _hwy3_routes_share_corridor(ra: Dictionary, rb: Dictionary) -> bool:
	if hwy3_mutant_name() == "overlap_ok":
		return false
	var sa: Dictionary = _hwy3_route_pid_set(ra)
	var sb: Dictionary = _hwy3_route_pid_set(rb)
	if sa.is_empty() or sb.is_empty():
		return false
	var inter: int = 0
	for k_v in sa.keys():
		if sb.has(k_v):
			inter += 1
	if inter <= 0:
		return false
	var uni: int = sa.size() + sb.size() - inter
	var jaccard: float = float(inter) / float(maxi(uni, 1))
	if jaccard + 0.0001 >= HWY3_CORRIDOR_JACCARD:
		return true
	var share_end: bool = (
		int(ra.get("a", 0)) == int(rb.get("a", 0))
		or int(ra.get("a", 0)) == int(rb.get("b", 0))
		or int(ra.get("b", 0)) == int(rb.get("a", 0))
		or int(ra.get("b", 0)) == int(rb.get("b", 0))
	)
	if not share_end:
		return false
	var frac_a: float = float(inter) / float(maxi(sa.size(), 1))
	var frac_b: float = float(inter) / float(maxi(sb.size(), 1))
	return frac_a + 0.0001 >= HWY3_CORRIDOR_SHARE or frac_b + 0.0001 >= HWY3_CORRIDOR_SHARE


static func _hwy3_routes_near_parallel(ra: Dictionary, rb: Dictionary, cents: Dictionary) -> bool:
	if hwy3_mutant_name() == "overlap_ok":
		return false
	var pa_v: Variant = ra.get("pids", [])
	var pb_v: Variant = rb.get("pids", [])
	var pa: Array = pa_v if typeof(pa_v) == TYPE_ARRAY else []
	var pb: Array = pb_v if typeof(pb_v) == TYPE_ARRAY else []
	if pa.size() < 2 or pb.size() < 2:
		return false
	if _hwy3_routes_share_corridor(ra, rb):
		return true
	var poly_a: PackedVector2Array = _hwy3_route_polyline(pa, cents)
	var poly_b: PackedVector2Array = _hwy3_route_polyline(pb, cents)
	if poly_a.size() < 2 or poly_b.size() < 2:
		return false
	var share_pid: bool = (
		int(ra.get("a", 0)) == int(rb.get("a", 0))
		or int(ra.get("a", 0)) == int(rb.get("b", 0))
		or int(ra.get("b", 0)) == int(rb.get("a", 0))
		or int(ra.get("b", 0)) == int(rb.get("b", 0))
	)
	var ends: int = _hwy3_end_region_share(poly_a[0], poly_a[poly_a.size() - 1], poly_b[0], poly_b[poly_b.size() - 1])
	if ends < 2 and not share_pid:
		return false
	var cover_ab: float = _hwy3_partial_cover(poly_a, poly_b, HWY3_PARALLEL_HAUSDORFF)
	var cover_ba: float = _hwy3_partial_cover(poly_b, poly_a, HWY3_PARALLEL_HAUSDORFF)
	var need: float = HWY3_PARALLEL_COVER
	if ends >= 2:
		return cover_ab >= need or cover_ba >= need
	if share_pid:
		# One shared end is a fork (Ruhr span vs Ruhr→Cologne attach), not a
		# duplicate corridor, unless each path almost sits on the other.
		return cover_ab >= 0.75 and cover_ba >= 0.75
	return false


static func _hwy3_keep_parallel_less(a: Dictionary, b: Dictionary) -> bool:
	var ca: bool = bool(a.get("span_core", false))
	var cb: bool = bool(b.get("span_core", false))
	if ca != cb:
		return ca
	var ka: int = int(a.get("kind", 0))
	var kb: int = int(b.get("kind", 0))
	if ka != kb:
		return ka > kb
	var sa: float = float(a.get("score", 0.0))
	var sb: float = float(b.get("score", 0.0))
	if sa != sb:
		return sa > sb
	var la: float = float(a.get("length", 0.0))
	var lb: float = float(b.get("length", 0.0))
	if la != lb:
		return la > lb
	return int(a.get("key", 0)) < int(b.get("key", 0))


static func _hwy3_drop_near_parallel(cands: Array, cents: Dictionary) -> Dictionary:
	var ranked: Array = []
	for c_v in cands:
		if typeof(c_v) == TYPE_DICTIONARY:
			ranked.append(c_v)
	ranked.sort_custom(_hwy3_keep_parallel_less)
	var kept: Array = []
	var dropped: int = 0
	for c2_v in ranked:
		var c2: Dictionary = c2_v
		var is_par: bool = false
		if not bool(c2.get("peri_keep", false)):
			for k_v in kept:
				var krow: Dictionary = k_v
				if _hwy3_routes_near_parallel(c2, krow, cents):
					is_par = true
					break
		if is_par:
			dropped += 1
			continue
		kept.append(c2)
	return {"kept": kept, "dropped": dropped}


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
		out["long"] = false
		out["zigzag"] = false
	if allow_zig:
		out["zigzag"] = false
		out["long"] = false
	out["ok"] = (
		(not bool(out["repeat"]) or allow_hook)
		and (not bool(out["hook"]) or allow_hook)
		and (not bool(out["long"]) or allow_zig or allow_hook)
		and (not bool(out["zigzag"]) or allow_zig or allow_hook)
	)
	return out


static func _hwy3_maybe_hook_repeat(pids: PackedInt32Array, mutant: String) -> PackedInt32Array:
	if mutant != "hook_back" or pids.size() < 3:
		return pids
	var out: PackedInt32Array = PackedInt32Array()
	out.append(pids[0])
	out.append(pids[1])
	out.append(pids[0])
	for i in range(1, pids.size()):
		out.append(pids[i])
	return out


static func _hwy3_union_path_hubs(tree_parent: Dictionary, pids: PackedInt32Array) -> void:
	var prev_h: int = 0
	for i in range(pids.size()):
		var pid: int = int(pids[i])
		if not tree_parent.has(pid):
			continue
		if prev_h > 0:
			_uf_union(tree_parent, prev_h, pid)
		prev_h = pid


static func _hwy3_commit_hub_path(
	cache: Array,
	cache_by_key: Dictionary,
	graph_by_key: Dictionary,
	marked: Dictionary,
	routes: Array,
	tree_parent: Dictionary,
	pids: PackedInt32Array,
	a: int,
	b: int,
	shape: Dictionary,
	used: int,
	hi: int,
	min_edges: int = -1
) -> int:
	var need_e: int = HWY3_MIN_PATH_EDGES if min_edges < 0 else min_edges
	if pids.size() - 1 < need_e:
		return used
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
		return used
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
		"a": a,
		"b": b,
		"pids": pid_arr,
		"keys": keys,
		"length": float(shape.get("length", 0.0)),
		"straight": float(shape.get("straight", 0.0)),
	})
	_hwy3_union_path_hubs(tree_parent, pids)
	return used


static func _hwy3_stamp_last_route(routes: Array, kind: int, score: float, span_core: bool = false) -> void:
	if routes.is_empty():
		return
	var last_v: Variant = routes[routes.size() - 1]
	if typeof(last_v) != TYPE_DICTIONARY:
		return
	var last: Dictionary = last_v
	last["kind"] = kind
	last["score"] = score
	last["span_core"] = span_core


static func _hwy3_count_highways(cache: Array) -> int:
	var n: int = 0
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		if int((row_v as Dictionary).get("display_tier", 0)) == TIER_HIGHWAY:
			n += 1
	return n


static func _hwy3_stamp_metro_edges(cache: Array, hubs: Array) -> void:
	var metro: Dictionary = hwy3_metro_cluster_pids(hubs)
	if metro.is_empty():
		return
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) != TIER_HIGHWAY:
			continue
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if metro.has(a) or metro.has(b):
			row["metro"] = true


static func _hwy3_route_is_trim_protected(rt: Dictionary) -> bool:
	if int(rt.get("kind", 0)) >= HWY3_KIND_TRUNK:
		return true
	if bool(rt.get("span_core", false)):
		return true
	if bool(rt.get("sector_keep", false)):
		return true
	if bool(rt.get("peri_keep", false)):
		return true
	return false


static func _hwy3_route_unique_keys(rt: Dictionary, routes: Array, skip_i: int) -> Array:
	var own_v: Variant = rt.get("keys", [])
	var own: Array = own_v if typeof(own_v) == TYPE_ARRAY else []
	var unique: Array = []
	for k_v in own:
		var k: int = int(k_v)
		var shared: bool = false
		for ri in range(routes.size()):
			if ri == skip_i:
				continue
			if typeof(routes[ri]) != TYPE_DICTIONARY:
				continue
			var other: Dictionary = routes[ri]
			var ok_v: Variant = other.get("keys", [])
			var ok: Array = ok_v if typeof(ok_v) == TYPE_ARRAY else []
			for ok2_v in ok:
				if int(ok2_v) == k:
					shared = true
					break
			if shared:
				break
		if not shared:
			unique.append(k)
	return unique


static func _hwy3_trim_victim_less(a: Dictionary, b: Dictionary) -> bool:
	var ka: int = int(a.get("kind", 0))
	var kb: int = int(b.get("kind", 0))
	if ka != kb:
		return ka < kb
	var sa: float = float(a.get("score", 0.0))
	var sb: float = float(b.get("score", 0.0))
	if sa != sb:
		return sa < sb
	return int(a.get("a", 0)) + int(a.get("b", 0)) < int(b.get("a", 0)) + int(b.get("b", 0))


static func _hwy3_trim_over_cap(
	cache: Array,
	cache_by_key: Dictionary,
	marked: Dictionary,
	routes: Array,
	used: int,
	cap: int
) -> int:
	var hwy: int = _hwy3_count_highways(cache)
	if hwy <= cap:
		return used
	var victims: Array = []
	for ri in range(routes.size()):
		if typeof(routes[ri]) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = routes[ri]
		if _hwy3_route_is_trim_protected(rt):
			continue
		victims.append({
			"i": ri,
			"kind": int(rt.get("kind", 0)),
			"score": float(rt.get("score", 0.0)),
			"a": int(rt.get("a", 0)),
			"b": int(rt.get("b", 0)),
		})
	victims.sort_custom(_hwy3_trim_victim_less)
	var drop_idx: Dictionary = {}
	for vic_v in victims:
		if hwy <= cap:
			break
		var vic: Dictionary = vic_v
		var vi: int = int(vic.get("i", -1))
		if vi < 0 or vi >= routes.size() or typeof(routes[vi]) != TYPE_DICTIONARY:
			continue
		var rt2: Dictionary = routes[vi]
		if _hwy3_route_is_trim_protected(rt2):
			continue
		var uniq: Array = _hwy3_route_unique_keys(rt2, routes, vi)
		if uniq.is_empty():
			continue
		var dropped_any: bool = false
		for k_v in uniq:
			if hwy <= cap:
				break
			var k: int = int(k_v)
			var idx_v: Variant = cache_by_key.get(k, -1)
			if int(idx_v) < 0:
				continue
			var er: Dictionary = cache[int(idx_v)]
			if bool(er.get("explicit", false)):
				continue
			if int(er.get("display_tier", 0)) != TIER_HIGHWAY:
				continue
			er["display_tier"] = TIER_PAVED
			marked.erase(k)
			used = maxi(used - 1, 0)
			hwy -= 1
			dropped_any = true
		if dropped_any:
			drop_idx[vi] = true
	if not drop_idx.is_empty():
		var kept: Array = []
		for ri2 in range(routes.size()):
			if drop_idx.has(ri2):
				continue
			kept.append(routes[ri2])
		routes.clear()
		for kr in kept:
			routes.append(kr)
	return used


static func _hwy3_drop_singleton_highways(cache: Array, marked: Dictionary, used: int) -> int:
	var parent: Dictionary = {}
	var hwy_idx: Array = []
	for ci in range(cache.size()):
		var crow_v: Variant = cache[ci]
		if typeof(crow_v) != TYPE_DICTIONARY:
			continue
		var crow: Dictionary = crow_v
		if int(crow.get("display_tier", 0)) != TIER_HIGHWAY:
			continue
		var a: int = int(crow.get("p1", 0))
		var b: int = int(crow.get("p2", 0))
		if a <= 0 or b <= 0:
			continue
		hwy_idx.append(ci)
		_uf_union(parent, a, b)
	var size_by_root: Dictionary = {}
	for ci2_v in hwy_idx:
		var ci2: int = int(ci2_v)
		var row2: Dictionary = cache[ci2]
		var root: int = _uf_find(parent, int(row2.get("p1", 0)))
		size_by_root[root] = int(size_by_root.get(root, 0)) + 1
	for ci3_v in hwy_idx:
		var ci3: int = int(ci3_v)
		var row3: Dictionary = cache[ci3]
		if bool(row3.get("explicit", false)):
			continue
		var root3: int = _uf_find(parent, int(row3.get("p1", 0)))
		if int(size_by_root.get(root3, 0)) != 1:
			continue
		row3["display_tier"] = TIER_PAVED
		marked.erase(_hwy1_row_key(row3))
		used = maxi(used - 1, 0)
	return used


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
					w += float(int(ra.get("urban_nbr", 0))) * 2.4
					if bool(ra.get("urban", false)):
						w += 7.5
			if attrs.has(b):
				var rb_v: Variant = attrs[b]
				if typeof(rb_v) == TYPE_DICTIONARY:
					var rb: Dictionary = rb_v
					w += float(int(rb.get("urban_nbr", 0))) * 2.4
					if bool(rb.get("urban", false)):
						w += 7.5
		var cost: float = dist / maxf(w, 0.08)
		var la: Array = adj.get(a, [])
		la.append(Vector2(float(b), cost))
		adj[a] = la
		var lb: Array = adj.get(b, [])
		lb.append(Vector2(float(a), cost))
		adj[b] = lb
	return adj


static func _hwy3_pair_priority_less(a: Dictionary, b: Dictionary) -> bool:
	var ka: int = int(a.get("kind", 0))
	var kb: int = int(b.get("kind", 0))
	if ka != kb:
		return ka > kb
	var da: float = float(a.get("dist", 999999.0))
	var db: float = float(b.get("dist", 999999.0))
	if da != db:
		return da < db
	var sa: float = float(a.get("score", 0.0))
	var sb: float = float(b.get("score", 0.0))
	if sa != sb:
		return sa > sb
	return int(a.get("key", 0)) < int(b.get("key", 0))


static func _hwy3_tag_land_less(a: Dictionary, b: Dictionary) -> bool:
	var la: int = int(a.get("land_n", 0))
	var lb: int = int(b.get("land_n", 0))
	if la != lb:
		return la > lb
	return str(a.get("tag", "")) < str(b.get("tag", ""))


static func _hwy3_order_pairs_for_paint(scored_pairs: Array) -> Array:
	var trunks: Array = []
	var spans: Array = []
	var large: Array = []
	var small: Array = []
	var foreign: Array = []
	for sp_v in scored_pairs:
		if typeof(sp_v) != TYPE_DICTIONARY:
			continue
		var sp: Dictionary = sp_v
		var kind: int = int(sp.get("kind", 0))
		var tag: String = str(sp.get("tag", "")).strip_edges().to_upper()
		if kind >= HWY3_KIND_TRUNK:
			trunks.append(sp)
			continue
		if kind == HWY3_KIND_SPAN:
			spans.append(sp)
			continue
		if tag.is_empty():
			foreign.append(sp)
			continue
		if int(sp.get("land_n", 0)) >= 180:
			large.append(sp)
		else:
			small.append(sp)
	trunks.sort_custom(_hwy3_pair_priority_less)
	spans.sort_custom(_hwy3_pair_priority_less)
	large.sort_custom(_hwy3_pair_priority_less)
	small.sort_custom(_hwy3_pair_priority_less)
	foreign.sort_custom(_hwy3_pair_priority_less)
	var out: Array = []
	for sp_t in trunks:
		out.append(sp_t)
	for sp_s in spans:
		out.append(sp_s)
	for sp_l in large:
		out.append(sp_l)
	for sp_m in small:
		out.append(sp_m)
	for sp_f in foreign:
		out.append(sp_f)
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
		var hubs_m_v: Variant = last_hwy3_debug.get("hubs", [])
		var hubs_m: Array = hubs_m_v if typeof(hubs_m_v) == TYPE_ARRAY else []
		_hwy3_stamp_metro_edges(cache, hubs_m)
		last_hwy3_debug["used"] = used_m
		last_hwy3_debug["drawn"] = _hwy3_count_highways(cache)
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
	var second_by_tag: Dictionary = {}
	var sector2_by_tag: Dictionary = {}
	var span_by_tag: Dictionary = {}
	var hubs_by_tag: Dictionary = {}
	for h0_v in hubs:
		if typeof(h0_v) != TYPE_DICTIONARY:
			continue
		var h0: Dictionary = h0_v
		var tg0: String = str(h0.get("tag", "")).strip_edges().to_upper()
		if tg0.is_empty():
			continue
		if not hubs_by_tag.has(tg0):
			hubs_by_tag[tg0] = []
		var hl0: Array = hubs_by_tag[tg0]
		hl0.append(h0)
		hubs_by_tag[tg0] = hl0
	for tg1_v in hubs_by_tag.keys():
		var tg1: String = str(tg1_v)
		var hl1: Array = hubs_by_tag[tg1]
		var cap1: int = _hwy3_capital_hub_pid(hl1)
		var sectors1: PackedInt32Array = _hwy3_reachable_sectors(hl1, cap1, adj, attrs)
		var first_sec1: int = int(sectors1[0]) if sectors1.size() > 0 else 0
		var second_sec1: int = int(sectors1[1]) if sectors1.size() > 1 else 0
		second_by_tag[tg1] = first_sec1
		sector2_by_tag[tg1] = second_sec1
		span_by_tag[tg1] = _hwy3_urban_span_pair_ids(hl1)
		for si1 in range(sectors1.size()):
			var sec1: int = int(sectors1[si1])
			if sec1 > 0 and not hub_set.has(sec1) and rec_by_pid.has(sec1):
				var rec_sec_v: Variant = rec_by_pid.get(sec1, {})
				if typeof(rec_sec_v) == TYPE_DICTIONARY:
					var rec_sec: Dictionary = rec_sec_v
					hubs.append(rec_sec)
					hub_set[sec1] = true
					hl1.append(rec_sec)
					hubs_by_tag[tg1] = hl1
			if cap1 > 0 and sec1 > 0:
				var already: bool = false
				for pr_v in pair_ids:
					if typeof(pr_v) != TYPE_ARRAY:
						continue
					var pr: Array = pr_v
					if pr.size() < 2:
						continue
					if (int(pr[0]) == cap1 and int(pr[1]) == sec1) or (int(pr[0]) == sec1 and int(pr[1]) == cap1):
						already = true
						break
				if not already:
					pair_ids.append([mini(cap1, sec1), maxi(cap1, sec1)])
		for hp1_v in hl1:
			if typeof(hp1_v) != TYPE_DICTIONARY:
				continue
			var hp1: Dictionary = hp1_v
			if not bool(hp1.get("periphery", false)):
				continue
			var peri1: int = int(hp1.get("pid", 0))
			if peri1 <= 0:
				continue
			var attach1: int = _hwy3_nearest_city_hub(hl1, Vector2i(peri1, peri1))
			if attach1 <= 0:
				attach1 = _hwy3_farthest_city_hub(hl1, peri1)
			if attach1 <= 0:
				continue
			var already_p: bool = false
			for pr2_v in pair_ids:
				if typeof(pr2_v) != TYPE_ARRAY:
					continue
				var pr2: Array = pr2_v
				if pr2.size() < 2:
					continue
				if (int(pr2[0]) == peri1 and int(pr2[1]) == attach1) or (
					int(pr2[0]) == attach1 and int(pr2[1]) == peri1
				):
					already_p = true
					break
			if not already_p:
				pair_ids.append([mini(peri1, attach1), maxi(peri1, attach1)])
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
		var tag_ab_early: String = ta if ta == tb else ""
		if _hwy3_pair_is_dropped_second_sector(
			a, b, tag_ab_early, second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		):
			continue
		var sc: float = float(ra.get("score", 0.0)) + float(rb.get("score", 0.0))
		var ca: Vector2 = ra.get("centroid", Vector2.ZERO)
		var cb: Vector2 = rb.get("centroid", Vector2.ZERO)
		var pd: float = ca.distance_to(cb)
		if not is_finite(pd) or pd <= 0.0:
			pd = 999999.0
		var tag_ab: String = ta if ta == tb else ""
		var kind: int = HWY3_KIND_OTHER
		var span_core: bool = false
		var sector_keep: bool = false
		var peri_keep: bool = false
		if not tag_ab.is_empty():
			var second_n: int = int(second_by_tag.get(tag_ab, 0))
			var sector2_n: int = int(sector2_by_tag.get(tag_ab, 0))
			var hl_ab_v: Variant = hubs_by_tag.get(tag_ab, [])
			var hl_ab: Array = hl_ab_v if typeof(hl_ab_v) == TYPE_ARRAY else []
			var cap_n: int = _hwy3_capital_hub_pid(hl_ab)
			if cap_n > 0 and HWY3_MAJOR_TAGS.has(tag_ab) and second_n > 0 and (
				(a == cap_n and b == second_n) or (b == cap_n and a == second_n)
			):
				kind = HWY3_KIND_TRUNK
			elif (
				cap_n > 0
				and HWY3_MAJOR_TAGS.has(tag_ab)
				and sector2_n > 0
				and (
					(a == cap_n and b == sector2_n) or (b == cap_n and a == sector2_n)
				)
			):
				kind = HWY3_KIND_SPAN
				sector_keep = true
			if HWY3_MAJOR_TAGS.has(tag_ab) and second_n > 0:
				var city_rec: Dictionary = {}
				var city_pid: int = 0
				if a == second_n and _hwy3_is_major_city_hub(rb):
					city_rec = rb
					city_pid = b
				elif b == second_n and _hwy3_is_major_city_hub(ra):
					city_rec = ra
					city_pid = a
				if city_pid > 0 and cap_n > 0 and city_pid != sector2_n:
					var cap_keep_v: Variant = rec_by_pid.get(cap_n, {})
					var cap_keep_rec: Dictionary = cap_keep_v if typeof(cap_keep_v) == TYPE_DICTIONARY else {}
					var d_city: float = cap_keep_rec.get("centroid", Vector2.ZERO).distance_to(
						city_rec.get("centroid", Vector2.ZERO)
					)
					if is_finite(d_city) and d_city >= HWY3_TRUNK_MIN_DIST * 2.5:
						peri_keep = true
						if kind < HWY3_KIND_SPAN:
							kind = HWY3_KIND_SPAN
			if kind == HWY3_KIND_TRUNK:
				pass
			elif kind == HWY3_KIND_SPAN and sector_keep:
				pass
			else:
				var spn_v: Variant = span_by_tag.get(tag_ab, Vector2i.ZERO)
				var spn: Vector2i = spn_v if typeof(spn_v) == TYPE_VECTOR2I else Vector2i.ZERO
				if spn.x > 0 and (
					(mini(a, b) == mini(spn.x, spn.y) and maxi(a, b) == maxi(spn.x, spn.y))
				):
					kind = HWY3_KIND_SPAN
					span_core = true
				elif spn.x > 0:
					var att_ab: Vector2i = _hwy3_urban_span_attach_ids(hl_ab, spn)
					if att_ab.x > 0 and (
						(mini(a, b) == mini(att_ab.x, att_ab.y) and maxi(a, b) == maxi(att_ab.x, att_ab.y))
					):
						kind = HWY3_KIND_SPAN
						span_core = true
					elif att_ab.y > 0 and second_n > 0 and (
						(a == second_n and b == att_ab.y) or (b == second_n and a == att_ab.y)
					):
						kind = HWY3_KIND_SPAN
						span_core = true
				if kind < HWY3_KIND_SPAN:
					for hp_ab_v in hl_ab:
						if typeof(hp_ab_v) != TYPE_DICTIONARY:
							continue
						var hp_ab: Dictionary = hp_ab_v
						if not bool(hp_ab.get("periphery", false)):
							continue
						var peri_pid2: int = int(hp_ab.get("pid", 0))
						if peri_pid2 <= 0:
							continue
						var attach_p: int = _hwy3_nearest_city_hub(hl_ab, Vector2i(peri_pid2, peri_pid2))
						if attach_p <= 0:
							attach_p = _hwy3_farthest_city_hub(hl_ab, peri_pid2)
						if attach_p > 0 and (
							(a == peri_pid2 and b == attach_p) or (b == peri_pid2 and a == attach_p)
						):
							kind = HWY3_KIND_SPAN
							break
		scored_pairs.append({
			"a": a,
			"b": b,
			"score": sc,
			"key": _hwy3_pair_key(a, b),
			"dist": pd,
			"tag": tag_ab,
			"land_n": maxi(int(ra.get("land_n", 0)), int(rb.get("land_n", 0))),
			"kind": kind,
			"span_core": span_core,
			"sector_keep": sector_keep,
			"peri_keep": peri_keep,
		})
	var best_peri_d: Dictionary = {}
	var best_peri_key: Dictionary = {}
	for spk_v in scored_pairs:
		if typeof(spk_v) != TYPE_DICTIONARY:
			continue
		var spk: Dictionary = spk_v
		if not bool(spk.get("peri_keep", false)):
			continue
		var tgk: String = str(spk.get("tag", "")).strip_edges().to_upper()
		var d_pk: float = float(spk.get("dist", 0.0))
		if not best_peri_d.has(tgk) or d_pk > float(best_peri_d.get(tgk, -1.0)):
			best_peri_d[tgk] = d_pk
			best_peri_key[tgk] = int(spk.get("key", 0))
	for spk2_v in scored_pairs:
		if typeof(spk2_v) != TYPE_DICTIONARY:
			continue
		var spk2: Dictionary = spk2_v
		if not bool(spk2.get("peri_keep", false)):
			continue
		var tgk2: String = str(spk2.get("tag", "")).strip_edges().to_upper()
		if int(spk2.get("key", 0)) != int(best_peri_key.get(tgk2, 0)):
			spk2["peri_keep"] = false
	var tags_with_span: Dictionary = {}
	for sps_v in scored_pairs:
		if typeof(sps_v) != TYPE_DICTIONARY:
			continue
		var sps: Dictionary = sps_v
		if bool(sps.get("span_core", false)):
			tags_with_span[str(sps.get("tag", "")).strip_edges().to_upper()] = true
	for sps2_v in scored_pairs:
		if typeof(sps2_v) != TYPE_DICTIONARY:
			continue
		var sps2: Dictionary = sps2_v
		if not bool(sps2.get("peri_keep", false)):
			continue
		var tgs2: String = str(sps2.get("tag", "")).strip_edges().to_upper()
		if not tags_with_span.has(tgs2):
			sps2["peri_keep"] = false
	var paint_pairs: Array = _hwy3_order_pairs_for_paint(scored_pairs)
	var inferred_n: int = inferred.size()
	if inferred_n <= 0:
		inferred_n = graph.size()
	var budget: int = _hwy1_budget(inferred_n)
	if budget <= 0:
		budget = 52
	var paint_budget: int = budget * HWY3_BUDGET_MULT
	if paint_budget < budget:
		paint_budget = budget
	var hi: int = int(floor(float(paint_budget) * (1.0 + HWY3_BUDGET_SLACK)))
	if hi > HWY3_BUDGET_CAP:
		hi = HWY3_BUDGET_CAP
	if hi < 45:
		hi = 45
	var used: int = 0
	var routes: Array = []
	var marked: Dictionary = {}
	var not_shortest: bool = mutant == "not_shortest"
	var tree_parent: Dictionary = {}
	for hp_v in hub_set.keys():
		var hp: int = int(hp_v)
		tree_parent[hp] = hp
	var candidates: Array = []
	var failed_trunks: Array = []
	var failed_spans: Array = []
	var trunk_ids: Array = []
	var span_ids: Array = []
	for sp_v in paint_pairs:
		var sp: Dictionary = sp_v
		var a2: int = int(sp.get("a", 0))
		var b2: int = int(sp.get("b", 0))
		var kind2: int = int(sp.get("kind", 0))
		if _hwy3_pair_is_dropped_second_sector(
			a2, b2, str(sp.get("tag", "")), second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		):
			continue
		if not adj.has(a2) or not adj.has(b2):
			if kind2 >= HWY3_KIND_TRUNK:
				failed_trunks.append("%d-%d no_adj" % [a2, b2])
			elif kind2 == HWY3_KIND_SPAN:
				failed_spans.append("%d-%d no_adj" % [a2, b2])
			continue
		if kind2 >= HWY3_KIND_TRUNK:
			trunk_ids.append("%s:%d-%d" % [str(sp.get("tag", "")), a2, b2])
		elif kind2 == HWY3_KIND_SPAN:
			span_ids.append("%s:%d-%d" % [str(sp.get("tag", "")), a2, b2])
		var pids: PackedInt32Array = shortest_hub_path(adj, a2, b2, not_shortest, attrs)
		pids = _hwy3_maybe_hook_repeat(pids, mutant)
		if pids.size() - 1 < HWY3_MIN_PATH_EDGES and kind2 >= HWY3_KIND_TRUNK and mutant != "not_shortest":
			var tf2: String = _hwy3_same_tag_filter(a2, b2, attrs)
			var prev_t: Dictionary = _hwy3_dijkstra_prev(adj, a2, tf2, attrs, 0)
			pids = _hwy3_extract_path(prev_t, a2, b2)
			pids = _hwy3_maybe_hook_repeat(pids, mutant)
		if pids.size() - 1 < HWY3_MIN_PATH_EDGES:
			if kind2 >= HWY3_KIND_TRUNK:
				failed_trunks.append("%d-%d empty_n=%d" % [a2, b2, pids.size()])
			elif kind2 == HWY3_KIND_SPAN:
				failed_spans.append("%d-%d empty_n=%d" % [a2, b2, pids.size()])
			continue
		var shape: Dictionary = path_shape_report(pids, centroids, a2, b2, mutant)
		if _hwy3_path_touches_dropped_second_sector(
			pids, str(sp.get("tag", "")), second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		):
			continue
		if not bool(shape.get("ok", false)):
			var shape_msg: String = (
				"%d-%d hook=%s zig=%s long=%s n=%d len=%.1f str=%.1f"
				% [
					a2, b2,
					str(shape.get("hook", false)),
					str(shape.get("zigzag", false)),
					str(shape.get("long", false)),
					pids.size(),
					float(shape.get("length", 0.0)),
					float(shape.get("straight", 0.0)),
				]
			)
			if kind2 >= HWY3_KIND_TRUNK:
				failed_trunks.append(shape_msg)
			elif kind2 == HWY3_KIND_SPAN:
				failed_spans.append(shape_msg)
			continue
		var pid_arr_c: Array = []
		for pii_c in range(pids.size()):
			pid_arr_c.append(int(pids[pii_c]))
		var cand: Dictionary = sp.duplicate()
		cand["pids"] = pid_arr_c
		cand["packed"] = pids
		cand["shape"] = shape
		cand["length"] = float(shape.get("length", 0.0))
		candidates.append(cand)
	var peri_has: Dictionary = {}
	for cand_p_v in candidates:
		if typeof(cand_p_v) != TYPE_DICTIONARY:
			continue
		var cand_p: Dictionary = cand_p_v
		peri_has[int(cand_p.get("a", 0))] = true
		peri_has[int(cand_p.get("b", 0))] = true
	for hperi_c_v in hubs:
		if typeof(hperi_c_v) != TYPE_DICTIONARY:
			continue
		var hperi_c: Dictionary = hperi_c_v
		if not bool(hperi_c.get("periphery", false)):
			continue
		var peri_c: int = int(hperi_c.get("pid", 0))
		if peri_c <= 0 or peri_has.has(peri_c) or not adj.has(peri_c):
			continue
		var tag_pc: String = str(hperi_c.get("tag", "")).strip_edges().to_upper()
		var hl_pc_v: Variant = hubs_by_tag.get(tag_pc, [])
		var hl_pc: Array = hl_pc_v if typeof(hl_pc_v) == TYPE_ARRAY else []
		var attach_rows: Array = _hwy3_city_hubs_by_dist(hl_pc, peri_c)
		for ar_v in attach_rows:
			if typeof(ar_v) != TYPE_DICTIONARY:
				continue
			var ar: Dictionary = ar_v
			var attach_c: int = int(ar.get("pid", 0))
			if attach_c <= 0 or not adj.has(attach_c):
				continue
			var pids_pc: PackedInt32Array = shortest_hub_path(adj, peri_c, attach_c, not_shortest, attrs)
			pids_pc = _hwy3_maybe_hook_repeat(pids_pc, mutant)
			if pids_pc.size() - 1 < HWY3_MIN_PATH_EDGES:
				continue
			var shape_pc: Dictionary = path_shape_report(pids_pc, centroids, peri_c, attach_c, mutant)
			if not bool(shape_pc.get("ok", false)):
				continue
			var pid_arr_pc: Array = []
			for pii_pc in range(pids_pc.size()):
				pid_arr_pc.append(int(pids_pc[pii_pc]))
			var ra_pc: Dictionary = rec_by_pid.get(peri_c, hperi_c)
			var rb_pc: Dictionary = rec_by_pid.get(attach_c, {})
			candidates.append({
				"a": peri_c,
				"b": attach_c,
				"score": float(ra_pc.get("score", 0.0)) + float(rb_pc.get("score", 0.0)),
				"key": _hwy3_pair_key(peri_c, attach_c),
				"dist": float(ar.get("dist", 0.0)),
				"tag": tag_pc,
				"land_n": maxi(int(ra_pc.get("land_n", 0)), int(rb_pc.get("land_n", 0))),
				"kind": HWY3_KIND_SPAN,
				"span_core": false,
				"sector_keep": false,
				"peri_keep": bool(hperi_c.get("periphery_primary", false)) and HWY3_MAJOR_TAGS.has(tag_pc),
				"pids": pid_arr_pc,
				"packed": pids_pc,
				"shape": shape_pc,
				"length": float(shape_pc.get("length", 0.0)),
			})
			peri_has[peri_c] = true
			break
	var par_drop: Dictionary = _hwy3_drop_near_parallel(candidates, centroids)
	var kept_v: Variant = par_drop.get("kept", [])
	var kept_cands: Array = kept_v if typeof(kept_v) == TYPE_ARRAY else []
	var dropped_parallel: int = int(par_drop.get("dropped", 0))
	kept_cands.sort_custom(_hwy3_pair_priority_less)
	var kept_ends: Dictionary = {}
	for ke_v in kept_cands:
		if typeof(ke_v) != TYPE_DICTIONARY:
			continue
		var ke: Dictionary = ke_v
		kept_ends[int(ke.get("a", 0))] = true
		kept_ends[int(ke.get("b", 0))] = true
		var kps_v: Variant = ke.get("pids", [])
		if typeof(kps_v) == TYPE_ARRAY:
			for kp_v in kps_v:
				kept_ends[int(kp_v)] = true
	for hperi_v in hubs:
		if typeof(hperi_v) != TYPE_DICTIONARY:
			continue
		var hperi: Dictionary = hperi_v
		if not bool(hperi.get("periphery", false)):
			continue
		var peri_e: int = int(hperi.get("pid", 0))
		if peri_e <= 0 or kept_ends.has(peri_e):
			continue
		var best_rest: Dictionary = {}
		for cand_r_v in candidates:
			if typeof(cand_r_v) != TYPE_DICTIONARY:
				continue
			var cand_r: Dictionary = cand_r_v
			if int(cand_r.get("a", 0)) != peri_e and int(cand_r.get("b", 0)) != peri_e:
				continue
			var par_k: bool = false
			for ke2_v in kept_cands:
				if typeof(ke2_v) != TYPE_DICTIONARY:
					continue
				if _hwy3_routes_near_parallel(cand_r, ke2_v as Dictionary, centroids):
					par_k = true
					break
			if par_k:
				continue
			if best_rest.is_empty() or int(cand_r.get("kind", 0)) > int(best_rest.get("kind", 0)):
				best_rest = cand_r
		if not best_rest.is_empty():
			kept_cands.append(best_rest)
			dropped_parallel = maxi(dropped_parallel - 1, 0)
			kept_ends[peri_e] = true
	for horph_v in hubs:
		if typeof(horph_v) != TYPE_DICTIONARY:
			continue
		var horph: Dictionary = horph_v
		if not _hwy3_is_major_city_hub(horph) and not bool(horph.get("periphery", false)):
			continue
		var orph_pid: int = int(horph.get("pid", 0))
		if orph_pid <= 0 or kept_ends.has(orph_pid) or not adj.has(orph_pid):
			continue
		var tag_or: String = str(horph.get("tag", "")).strip_edges().to_upper()
		var hl_or_v: Variant = hubs_by_tag.get(tag_or, [])
		var hl_or: Array = hl_or_v if typeof(hl_or_v) == TYPE_ARRAY else []
		var attach_or: Array = _hwy3_city_hubs_by_dist(hl_or, orph_pid)
		var second_or: int = int(second_by_tag.get(tag_or, 0))
		var cap_or: int = _hwy3_capital_hub_pid(hl_or)
		var far_from_cap: bool = false
		if cap_or > 0 and rec_by_pid.has(cap_or):
			var cap_rec_or_v: Variant = rec_by_pid.get(cap_or, {})
			var cap_rec_or: Dictionary = cap_rec_or_v if typeof(cap_rec_or_v) == TYPE_DICTIONARY else {}
			var d_cap_or: float = cap_rec_or.get("centroid", Vector2.ZERO).distance_to(
				horph.get("centroid", Vector2.ZERO)
			)
			far_from_cap = is_finite(d_cap_or) and d_cap_or >= HWY3_TRUNK_MIN_DIST * 2.5
		var attach_kept: Array = []
		var attach_rest: Array = []
		for ars_v in attach_or:
			if typeof(ars_v) != TYPE_DICTIONARY:
				continue
			var ars: Dictionary = ars_v
			if kept_ends.has(int(ars.get("pid", 0))):
				attach_kept.append(ars)
			else:
				attach_rest.append(ars)
		attach_or = []
		if _hwy3_is_major_city_hub(horph) and second_or > 0 and far_from_cap:
			attach_or.append({"pid": second_or, "dist": 0.0, "key": _hwy3_pair_key(orph_pid, second_or)})
		for ak_v in attach_kept:
			if far_from_cap and int((ak_v as Dictionary).get("pid", 0)) == second_or:
				continue
			attach_or.append(ak_v)
		for ar2_v in attach_rest:
			if far_from_cap and int((ar2_v as Dictionary).get("pid", 0)) == second_or:
				continue
			attach_or.append(ar2_v)
		for ao_v in attach_or:
			if typeof(ao_v) != TYPE_DICTIONARY:
				continue
			var ao: Dictionary = ao_v
			var attach_o: int = int(ao.get("pid", 0))
			if attach_o <= 0 or not adj.has(attach_o):
				continue
			var pids_o: PackedInt32Array = shortest_hub_path(adj, orph_pid, attach_o, not_shortest, attrs)
			pids_o = _hwy3_maybe_hook_repeat(pids_o, mutant)
			if pids_o.size() - 1 < HWY3_MIN_PATH_EDGES:
				continue
			var shape_o: Dictionary = path_shape_report(pids_o, centroids, orph_pid, attach_o, mutant)
			if not bool(shape_o.get("ok", false)):
				continue
			var pid_arr_o: Array = []
			for pii_o in range(pids_o.size()):
				pid_arr_o.append(int(pids_o[pii_o]))
			var ra_o: Dictionary = rec_by_pid.get(orph_pid, horph)
			var rb_o: Dictionary = rec_by_pid.get(attach_o, {})
			var cand_o: Dictionary = {
				"a": orph_pid,
				"b": attach_o,
				"score": float(ra_o.get("score", 0.0)) + float(rb_o.get("score", 0.0)),
				"key": _hwy3_pair_key(orph_pid, attach_o),
				"dist": float(ao.get("dist", 0.0)),
				"tag": tag_or,
				"land_n": maxi(int(ra_o.get("land_n", 0)), int(rb_o.get("land_n", 0))),
				"kind": HWY3_KIND_SPAN,
				"span_core": false,
				"sector_keep": false,
				"peri_keep": HWY3_MAJOR_TAGS.has(tag_or) and _hwy3_is_major_city_hub(horph) and far_from_cap and (
					attach_o == int(second_by_tag.get(tag_or, 0))
				),
				"pids": pid_arr_o,
				"packed": pids_o,
				"shape": shape_o,
				"length": float(shape_o.get("length", 0.0)),
			}
			var par_o: bool = false
			for ke3_v in kept_cands:
				if typeof(ke3_v) != TYPE_DICTIONARY:
					continue
				if _hwy3_routes_near_parallel(cand_o, ke3_v as Dictionary, centroids):
					par_o = true
					break
			if par_o and not (far_from_cap and _hwy3_is_major_city_hub(horph)):
				continue
			kept_cands.append(cand_o)
			kept_ends[orph_pid] = true
			for po_v in pid_arr_o:
				kept_ends[int(po_v)] = true
			break
	kept_cands.sort_custom(_hwy3_pair_priority_less)
	var dropped_cap: int = 0
	var marked_verts: Dictionary = {}
	for kc_v in kept_cands:
		if typeof(kc_v) != TYPE_DICTIONARY:
			continue
		var kc: Dictionary = kc_v
		var a3: int = int(kc.get("a", 0))
		var b3: int = int(kc.get("b", 0))
		var kind3: int = int(kc.get("kind", 0))
		var tag_sp: String = str(kc.get("tag", "")).strip_edges().to_upper()
		if _hwy3_pair_is_dropped_second_sector(
			a3, b3, tag_sp, second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		):
			continue
		if _hwy3_path_touches_dropped_second_sector(
			kc.get("pids", []), tag_sp, second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		):
			continue
		var commit_hi: int = hi
		var span_core3: bool = bool(kc.get("span_core", false))
		var sector_keep3: bool = bool(kc.get("sector_keep", false))
		var peri_keep3: bool = bool(kc.get("peri_keep", false))
		if kind3 >= HWY3_KIND_TRUNK or span_core3 or sector_keep3 or peri_keep3:
			commit_hi = hi + HWY3_TRUNK_OVERFLOW
		elif kind3 == HWY3_KIND_SPAN:
			commit_hi = hi + HWY3_SPAN_OVERFLOW
		elif kind3 == HWY3_KIND_OTHER:
			commit_hi = maxi(hi - HWY3_COVER_RESERVE, 45)
		if (
			kind3 == HWY3_KIND_OTHER
			and not tag_sp.is_empty()
			and tree_parent.has(a3)
			and tree_parent.has(b3)
			and _uf_find(tree_parent, a3) == _uf_find(tree_parent, b3)
		):
			continue
		if kind3 == HWY3_KIND_OTHER and used >= commit_hi:
			dropped_cap += 1
			continue
		var packed_v: Variant = kc.get("packed", PackedInt32Array())
		var pids_k: PackedInt32Array = PackedInt32Array()
		if typeof(packed_v) == TYPE_PACKED_INT32_ARRAY:
			pids_k = packed_v
		var shape_v: Variant = kc.get("shape", {})
		var shape_k: Dictionary = shape_v if typeof(shape_v) == TYPE_DICTIONARY else {}
		var used_before: int = used
		var routes_before: int = routes.size()
		used = _hwy3_commit_hub_path(
			cache, cache_by_key, graph_by_key, marked, routes, tree_parent,
			pids_k, a3, b3, shape_k, used, commit_hi
		)
		if routes.size() > routes_before:
			_hwy3_stamp_last_route(routes, kind3, float(kc.get("score", 0.0)), span_core3)
			var last_rt_v: Variant = routes[routes.size() - 1]
			if typeof(last_rt_v) == TYPE_DICTIONARY:
				var last_rt: Dictionary = last_rt_v
				last_rt["sector_keep"] = sector_keep3
				last_rt["peri_keep"] = peri_keep3
		if used > used_before:
			for pi_v in range(pids_k.size()):
				marked_verts[int(pids_k[pi_v])] = true
		if used == used_before and used_before >= commit_hi:
			dropped_cap += 1
		elif used == used_before and pids_k.size() - 1 >= HWY3_MIN_PATH_EDGES:
			var new_need: int = 0
			for pi_n in range(1, pids_k.size()):
				var kn: int = _hwy3_pair_key(int(pids_k[pi_n - 1]), int(pids_k[pi_n]))
				if not marked.has(kn):
					new_need += 1
			if used + new_need > commit_hi:
				dropped_cap += 1
	var cover_tried: Dictionary = {}
	var cover_guard: int = 0
	while used < hi and cover_guard < 96:
		cover_guard += 1
		var best_a: int = 0
		var best_b: int = 0
		var best_sc: float = -1.0e18
		for h5_v in hubs:
			var h5: Dictionary = h5_v
			var hp5: int = int(h5.get("pid", 0))
			if hp5 <= 0 or not adj.has(hp5) or not tree_parent.has(hp5):
				continue
			var tag5: String = str(h5.get("tag", "")).strip_edges().to_upper()
			if tag5.is_empty():
				continue
			var c5: Vector2 = h5.get("centroid", Vector2.ZERO)
			var root5: int = _uf_find(tree_parent, hp5)
			var land5: int = int(h5.get("land_n", 0))
			var city5: bool = bool(h5.get("city_hub", false)) or int(h5.get("tier", 0)) >= 3
			for h6_v in hubs:
				var h6: Dictionary = h6_v
				var op6: int = int(h6.get("pid", 0))
				if op6 <= hp5 or not adj.has(op6) or not tree_parent.has(op6):
					continue
				var ot6: String = str(h6.get("tag", "")).strip_edges().to_upper()
				if ot6 != tag5:
					continue
				if _hwy3_pair_is_dropped_second_sector(
					hp5, op6, tag5, second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
				):
					continue
				if _uf_find(tree_parent, op6) == root5:
					continue
				var pk6: int = _hwy3_pair_key(hp5, op6)
				if cover_tried.has(pk6):
					continue
				var d6: float = c5.distance_to(h6.get("centroid", Vector2.ZERO))
				if not is_finite(d6) or d6 <= 0.0:
					continue
				var city6: bool = bool(h6.get("city_hub", false)) or int(h6.get("tier", 0)) >= 3
				var sc6: float = -d6
				if HWY3_MAJOR_TAGS.has(tag5) or land5 >= 180:
					sc6 += 10000.0
				elif land5 >= 50:
					sc6 += 3000.0
				if city5 and city6:
					sc6 += 500.0
				var on5: bool = marked_verts.has(hp5)
				var on6: bool = marked_verts.has(op6)
				if on5 and on6:
					sc6 += 40000.0
				elif on5 or on6:
					sc6 += 15000.0
				if sc6 > best_sc or (sc6 == best_sc and op6 < best_b):
					best_sc = sc6
					best_a = hp5
					best_b = op6
		if best_a <= 0 or best_b <= 0:
			break
		cover_tried[_hwy3_pair_key(best_a, best_b)] = true
		var pids5: PackedInt32Array = shortest_hub_path(adj, best_a, best_b, not_shortest, attrs)
		pids5 = _hwy3_maybe_hook_repeat(pids5, mutant)
		if pids5.size() < 2:
			continue
		var cover_tag: String = ""
		var cover_rec_v: Variant = rec_by_pid.get(best_a, {})
		if typeof(cover_rec_v) == TYPE_DICTIONARY:
			cover_tag = str((cover_rec_v as Dictionary).get("tag", "")).strip_edges().to_upper()
		if _hwy3_path_touches_dropped_second_sector(
			pids5, cover_tag, second_by_tag, sector2_by_tag, rec_by_pid, hubs_by_tag
		):
			continue
		var shape5: Dictionary = path_shape_report(pids5, centroids, best_a, best_b, mutant)
		if not bool(shape5.get("ok", false)):
			continue
		var pid_arr5: Array = []
		for pii5 in range(pids5.size()):
			pid_arr5.append(int(pids5[pii5]))
		var cover_min: int = HWY3_MIN_PATH_EDGES
		if pids5.size() == 2:
			if marked_verts.has(int(pids5[0])) or marked_verts.has(int(pids5[1])):
				cover_min = 1
		var cover_row: Dictionary = {
			"a": best_a,
			"b": best_b,
			"pids": pid_arr5,
			"kind": HWY3_KIND_OTHER,
		}
		var cover_par: bool = false
		for rt5_v in routes:
			if typeof(rt5_v) != TYPE_DICTIONARY:
				continue
			if _hwy3_routes_near_parallel(cover_row, rt5_v as Dictionary, centroids):
				cover_par = true
				break
		if cover_par:
			dropped_parallel += 1
			continue
		var used_cover: int = used
		used = _hwy3_commit_hub_path(
			cache, cache_by_key, graph_by_key, marked, routes, tree_parent,
			pids5, best_a, best_b, shape5, used, hi, cover_min
		)
		_hwy3_stamp_last_route(routes, HWY3_KIND_OTHER, best_sc)
		if used > used_cover:
			for pi5b in range(pids5.size()):
				marked_verts[int(pids5[pi5b])] = true
	if mutant != "overlap_ok":
		used = _hwy3_trim_over_cap(cache, cache_by_key, marked, routes, used, HWY3_BUDGET_CAP)
		used = _hwy3_drop_singleton_highways(cache, marked, used)
	_hwy3_stamp_metro_edges(cache, hubs)
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
			"city_hub": bool(h2.get("city_hub", false)),
			"city_name": str(h2.get("city_name", "")),
			"name": str(h2.get("name", "")),
			"centroid": h2.get("centroid", Vector2.ZERO),
			"land_n": int(h2.get("land_n", 0)),
			"periphery": bool(h2.get("periphery", false)),
		})
	var peri_dbg: Array = []
	for h3_v in hubs:
		if typeof(h3_v) != TYPE_DICTIONARY:
			continue
		var h3: Dictionary = h3_v
		if not bool(h3.get("periphery", false)):
			continue
		peri_dbg.append("%s:%d" % [str(h3.get("city_name", h3.get("name", ""))), int(h3.get("pid", 0))])
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
		"drawn": _hwy3_count_highways(cache),
		"budget": paint_budget,
		"dropped_parallel": dropped_parallel,
		"dropped_cap": dropped_cap,
		"candidates": candidates.size(),
		"failed_trunks": failed_trunks,
		"failed_spans": failed_spans,
		"trunks": trunk_ids,
		"spans": span_ids,
		"peri": peri_dbg,
		"second_by_tag": second_by_tag,
		"sector2_by_tag": sector2_by_tag,
		"city_source": str(hub_ctx.get("city_source", "")),
		"adj_ms": t_adj_ms,
		"hubs_ms": t_hubs_ms,
		"route_ms": float(Time.get_ticks_usec() - t_route0) / 1000.0,
		"total_ms": float(Time.get_ticks_usec() - t_all0) / 1000.0,
	}
	if mutant != "not_shortest":
		_hwy3_route_memo_key = route_key
		_hwy3_route_memo_marked = marked.duplicate()
		_hwy3_route_memo_debug = last_hwy3_debug.duplicate()
