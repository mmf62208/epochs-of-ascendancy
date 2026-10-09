class_name SupplyPathfinder
extends RefCounted

## Multimodal supply paths: land columns, sealift (ports/sea), airlift (airports).
##
## PERF-4 FIX #4: binary min-heap + sorted neighbors + equal-cost predecessor-pid
## tie-break. FIX #3 sorted the whole open set on every pop (O(n² log n)); a
## large frontier after captures could take 0.9–9.3 s for one AI supply day.
## Incremental refill now uses the same deterministic path as a full rebuild.

static var last_search_pops: int = 0
static var last_search_open_peak: int = 0
static var last_search_ms: float = 0.0
## Friendly-neighbor lists are stable until a control / infra change.
static var _land_nbr_cache: Dictionary = {}
static var _friendly_cache: Dictionary = {}
static var _cache_owner_tag: String = ""


static func clear_neighbor_cache() -> void:
	_land_nbr_cache.clear()
	_friendly_cache.clear()
	_cache_owner_tag = ""


static func find_route(
	source_id: int,
	target_id: int,
	owner_tag: String,
	provinces: Dictionary,
	adjacency: AdjacencySystem,
	hubs: Dictionary,
	rules: SupplyRules,
	waypoints: Array[int] = [],
) -> SupplyRoutePlan:
	return find_route_for_mode(
		"land", source_id, target_id, owner_tag, provinces, adjacency, hubs, rules, waypoints,
	)


static func find_route_for_mode(
	mode: String,
	source_id: int,
	target_id: int,
	owner_tag: String,
	provinces: Dictionary,
	adjacency: AdjacencySystem,
	hubs: Dictionary,
	rules: SupplyRules,
	waypoints: Array[int] = [],
) -> SupplyRoutePlan:
	var plan := SupplyRoutePlan.new()
	plan.owner_tag = owner_tag
	plan.source_province_id = source_id
	plan.target_province_id = target_id
	plan.routing_mode = mode
	plan.is_player_override = not waypoints.is_empty()

	if source_id == target_id:
		plan.province_path = [source_id]
		return plan

	var path: Array[int] = []
	if waypoints.is_empty():
		path = _mode_dijkstra(mode, source_id, target_id, owner_tag, provinces, adjacency, hubs, rules)
	else:
		var chain: Array[int] = [source_id]
		chain.append_array(waypoints)
		chain.append(target_id)
		for i in range(chain.size() - 1):
			var leg := _mode_dijkstra(
				mode, int(chain[i]), int(chain[i + 1]), owner_tag, provinces, adjacency, hubs, rules,
			)
			if leg.is_empty():
				path = []
				break
			if path.is_empty():
				path = leg
			else:
				for j in range(1, leg.size()):
					path.append(leg[j])

	if path.is_empty():
		return plan

	plan.province_path = path
	_populate_timing(plan, mode, provinces, adjacency, hubs, rules, owner_tag)
	return plan


static func _heap_less(a: Array, b: Array) -> bool:
	var ca: float = float(a[0])
	var cb: float = float(b[0])
	if ca < cb:
		return true
	if ca > cb:
		return false
	return int(a[1]) < int(b[1])


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = int((i - 1) / 2)
		var cur_item: Array = heap[i]
		var par_item: Array = heap[parent]
		if _heap_less(cur_item, par_item):
			heap[parent] = cur_item
			heap[i] = par_item
			i = parent
		else:
			break


static func _heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var i: int = 0
	var n: int = heap.size()
	while true:
		var left: int = 2 * i + 1
		var right: int = 2 * i + 2
		var smallest: int = i
		if left < n:
			var left_item: Array = heap[left]
			var small_item: Array = heap[smallest]
			if _heap_less(left_item, small_item):
				smallest = left
		if right < n:
			var right_item: Array = heap[right]
			var small2: Array = heap[smallest]
			if _heap_less(right_item, small2):
				smallest = right
		if smallest == i:
			break
		var tmp: Array = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return result


static func _mode_dijkstra(
	mode: String,
	source_id: int,
	target_id: int,
	owner_tag: String,
	provinces: Dictionary,
	adjacency: AdjacencySystem,
	hubs: Dictionary,
	rules: SupplyRules,
) -> Array[int]:
	last_search_pops = 0
	last_search_open_peak = 1
	var t0: int = Time.get_ticks_usec()
	var dist: Dictionary = {source_id: 0.0}
	var prev: Dictionary = {}
	var open: Array = []
	_heap_push(open, [0.0, source_id])

	while not open.is_empty():
		if open.size() > last_search_open_peak:
			last_search_open_peak = open.size()
		var entry: Array = _heap_pop(open)
		last_search_pops += 1
		var cost: float = float(entry[0])
		var pid: int = int(entry[1])
		if pid == target_id:
			break
		if cost > float(dist.get(pid, INF)):
			continue

		for neighbor_id in _supply_neighbors(mode, pid, owner_tag, provinces, adjacency, hubs, rules):
			var edge_cost: float = _edge_cost_for_mode(mode, pid, neighbor_id, provinces, hubs, rules)
			var new_cost: float = cost + edge_cost
			var old_cost: float = float(dist.get(neighbor_id, INF))
			if new_cost < old_cost:
				dist[neighbor_id] = new_cost
				prev[neighbor_id] = pid
				_heap_push(open, [new_cost, neighbor_id])
			elif is_equal_approx(new_cost, old_cost) and prev.has(neighbor_id):
				# Same length: keep the smaller predecessor pid so incremental
				# refill matches a full rebuild (not first-found visit order).
				if pid < int(prev[neighbor_id]):
					prev[neighbor_id] = pid

	last_search_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if not dist.has(target_id):
		return []

	var path: Array[int] = [target_id]
	var cur: int = target_id
	while prev.has(cur):
		cur = int(prev[cur])
		path.push_front(cur)
	return path


static func _supply_neighbors(
	mode: String,
	pid: int,
	owner_tag: String,
	provinces: Dictionary,
	adjacency: AdjacencySystem,
	hubs: Dictionary,
	rules: SupplyRules,
) -> Array[int]:
	var out: Array[int] = []
	var route_rules := rules.get_block("routing")
	var min_port := int(route_rules.get("min_port_level_for_sealift", 1))
	var min_air := int(route_rules.get("min_airport_level_for_airlift", 1))

	match mode:
		"sea":
			# Open-sea hops (seas are always friendly for sealift).
			for nid in adjacency.get_sea_neighbors(pid):
				if _is_friendly(nid, owner_tag, provinces):
					out.append(nid)
			var hub: ProvinceSupplyHub = hubs.get(pid)
			var here: Province = provinces.get(pid)
			# Coastal land with a port can embark into adjacent sea zones.
			if hub != null and hub.port_level >= min_port and here != null and not here.is_sea:
				for nid in adjacency.get_neighbors(pid):
					var np: Province = provinces.get(nid)
					if np == null:
						continue
					if np.is_sea:
						out.append(nid)
						continue
					# Port-to-port short hop on friendly land (same nation / access).
					if not _is_friendly(nid, owner_tag, provinces):
						continue
					var nh: ProvinceSupplyHub = hubs.get(nid)
					if nh != null and nh.port_level >= min_port:
						out.append(nid)
			# At sea: can also touch friendly coastal ports for disembark.
			elif here != null and here.is_sea:
				for nid in adjacency.get_neighbors(pid):
					if not _is_friendly(nid, owner_tag, provinces):
						continue
					var nh2: ProvinceSupplyHub = hubs.get(nid)
					if nh2 != null and nh2.port_level >= min_port:
						out.append(nid)
		"air":
			var hub_a: ProvinceSupplyHub = hubs.get(pid)
			if hub_a == null or hub_a.airport_level < min_air:
				return out
			for nid in adjacency.get_neighbors(pid):
				if not _is_friendly(nid, owner_tag, provinces):
					continue
				var nh: ProvinceSupplyHub = hubs.get(nid)
				if nh != null and nh.airport_level >= min_air:
					out.append(nid)
		_:
			if _cache_owner_tag != owner_tag:
				clear_neighbor_cache()
				_cache_owner_tag = owner_tag
			if _land_nbr_cache.has(pid):
				return _land_nbr_cache[pid]
			for nid in adjacency.get_land_neighbors(pid):
				if _is_friendly(nid, owner_tag, provinces):
					out.append(nid)
			if out.is_empty():
				for nid in adjacency.get_neighbors(pid):
					var np: Province = provinces.get(nid)
					if np != null and not np.is_sea and _is_friendly(nid, owner_tag, provinces):
						out.append(nid)
			out.sort()
			var stored: Array[int] = []
			for stored_id in out:
				stored.append(int(stored_id))
			_land_nbr_cache[pid] = stored
			return out
	out.sort()
	return out


static func _edge_cost_for_mode(
	mode: String,
	from_id: int,
	to_id: int,
	provinces: Dictionary,
	hubs: Dictionary,
	rules: SupplyRules,
) -> float:
	var base := _edge_cost(from_id, to_id, provinces, hubs, rules)
	match mode:
		"sea":
			return base * rules.get_float("routing", "port_sea_cost_multiplier", 0.55)
		"air":
			return base * rules.get_float("routing", "airport_air_cost_multiplier", 0.38)
		_:
			return base


static func _edge_cost(
	_from_id: int,
	to_id: int,
	provinces: Dictionary,
	hubs: Dictionary,
	rules: SupplyRules,
) -> float:
	var to_p: Province = provinces.get(to_id)
	if to_p == null:
		return 999.0
	var move := to_p.get_movement_cost()
	var cost := move * rules.get_float("routing", "base_days_per_movement_cost", 0.45)
	# RX-1: trivial supply-pathing hook — same edge multiplier as movement.
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("rx1_move_mult"):
		cost *= float(MapManager.rx1_move_mult(int(_from_id), int(to_id)))
	var hub: ProvinceSupplyHub = hubs.get(to_id)
	if hub != null:
		cost *= rules.get_float("routing", "hub_transit_discount", 0.72)
	if to_p.is_sea:
		cost *= rules.get_float("routing", "port_sea_cost_multiplier", 0.55)
	return maxf(cost, 0.05)


static func _populate_timing(
	plan: SupplyRoutePlan,
	mode: String,
	provinces: Dictionary,
	_adjacency: AdjacencySystem,
	hubs: Dictionary,
	rules: SupplyRules,
	owner_tag: String,
) -> void:
	var days := 0.0
	plan.segment_modes.clear()
	for i in range(plan.province_path.size() - 1):
		var a := int(plan.province_path[i])
		var b := int(plan.province_path[i + 1])
		days += _edge_cost_for_mode(mode, a, b, provinces, hubs, rules)
		plan.segment_modes.append(mode if mode != "land" else _segment_mode(a, b, provinces, hubs, rules))

	plan.total_days = days
	var hub: ProvinceSupplyHub = hubs.get(plan.source_province_id)
	if hub != null and hub.has_kind(ProvinceSupplyHub.DepotKind.CAPITAL):
		plan.total_days /= rules.get_float("routing", "capital_primary_source_multiplier", 1.35)

	plan.uses_port = mode == "sea"
	plan.uses_airport = mode == "air"
	for pid in plan.province_path:
		var h: ProvinceSupplyHub = hubs.get(pid)
		if h == null:
			continue
		if h.spaceport_level > 0:
			plan.uses_spaceport = true


static func _segment_mode(
	_from_id: int,
	to_id: int,
	provinces: Dictionary,
	hubs: Dictionary,
	rules: SupplyRules,
) -> String:
	var to_p: Province = provinces.get(to_id)
	if to_p != null and to_p.is_sea:
		return "sea"
	var to_hub: ProvinceSupplyHub = hubs.get(to_id)
	if to_hub != null and to_hub.airport_level >= int(
		rules.get_block("routing").get("min_airport_level_for_airlift", 1),
	):
		return "air"
	if to_hub != null and to_hub.port_level > 0:
		return "sea"
	return "land"


## Own land, open sea, unowned land, OR transit rights (alliance / military access / basing / docking).
## Neutral foreign land without agreement blocks overland supply (East Prussia → Baltic sea path).
static func _is_friendly(province_id: int, owner_tag: String, provinces: Dictionary) -> bool:
	if _cache_owner_tag != owner_tag:
		clear_neighbor_cache()
		_cache_owner_tag = owner_tag
	if _friendly_cache.has(province_id):
		return bool(_friendly_cache[province_id])
	var p: Province = provinces.get(province_id)
	if p == null:
		_friendly_cache[province_id] = false
		return false
	# Open water is always usable for sealift (enemy fleets handled via interdiction, not block).
	if p.is_sea:
		_friendly_cache[province_id] = true
		return true
	var ctrl := str(p.controller_tag).strip_edges().to_upper() if not str(p.controller_tag).is_empty() else str(p.owner_tag).strip_edges().to_upper()
	if ctrl.is_empty():
		_friendly_cache[province_id] = true
		return true  # unowned land
	var tag := owner_tag.strip_edges().to_upper()
	if tag.is_empty():
		_friendly_cache[province_id] = true
		return true
	if ctrl == tag:
		_friendly_cache[province_id] = true
		return true
	# Diplomatic transit: alliance or explicit basing / military access / docking rights.
	var ok: bool = false
	if typeof(RelationsManager) != TYPE_NIL:
		if RelationsManager.has_method("is_allied") and RelationsManager.is_allied(tag, ctrl):
			ok = true
		elif RelationsManager.has_method("get_policy"):
			var pol: Dictionary = RelationsManager.get_policy(tag, ctrl)
			if bool(pol.get("military_access", false)) \
				or bool(pol.get("docking_rights", false)) \
				or bool(pol.get("basing_rights", false)) \
				or bool(pol.get("supply_transit", false)):
				ok = true
	_friendly_cache[province_id] = ok
	return ok
