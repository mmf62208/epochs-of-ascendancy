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
## Mid/close: casing must read wider than paved (~5.2) and thinner than gold (16).
const HIGHWAY_SCREEN_PX := 7.5
const HIGHWAY_CASING_SCREEN_PX := 11.0
const HIGHWAY_STRIPE_SCREEN_PX := 2.6
## Europe/Home only: keep the rare trunk visible without a continent carpet.
const HIGHWAY_FAR_CASING_SCREEN_PX := 5.5
const HIGHWAY_FAR_CORE_SCREEN_PX := 3.2
const DIRT_DASH_SCREEN_PX := 9.0
const DIRT_GAP_SCREEN_PX := 6.0

## Palette: saturated enough to read on political fills (not thin grey).
const DIRT_COLOR := Color(0.84, 0.56, 0.18, 0.96)
const PAVED_COLOR := Color(0.34, 0.36, 0.40, 0.94)
const PAVED_EDGE_COLOR := Color(0.16, 0.17, 0.20, 0.82)
const HIGHWAY_CASING_COLOR := Color(0.05, 0.05, 0.07, 0.96)
const HIGHWAY_CORE_COLOR := Color(0.22, 0.24, 0.28, 0.95)
const HIGHWAY_STRIPE_COLOR := Color(0.98, 0.94, 0.62, 0.98)

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
			w = HIGHWAY_CASING_SCREEN_PX if lod_band >= 1 else HIGHWAY_FAR_CASING_SCREEN_PX
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


static func assign_rare_display_tiers(cache: Array) -> void:
	var inferred: Array = []
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if bool(row.get("explicit", false)):
			row["display_tier"] = TIER_HIGHWAY
			continue
		inferred.append(row)
	if inferred.is_empty():
		return
	inferred.sort_custom(_weight_less)
	var n: int = inferred.size()
	for i in range(n):
		var rank: float = 0.0 if n <= 1 else float(i) / float(n)
		var row2: Dictionary = inferred[i]
		row2["display_tier"] = display_tier_from_rank(rank, false)
