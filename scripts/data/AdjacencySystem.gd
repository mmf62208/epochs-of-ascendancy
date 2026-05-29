# scripts/data/AdjacencySystem.gd
# Optional JSON on the adjacency file root:
#   "straits": [ { "a": 1, "b": 43, "extra": 2 }, ... ]
#   or "straits": { "1_43": 2 }  (extra movement cost added to the base edge cost of 1)
class_name AdjacencySystem
extends RefCounted

## int province id -> all neighbors (immutable after load).
var _neighbors_by_id: Dictionary = {}

## Cached int id -> PackedInt32Array of land-only / sea-only neighbors (rebuilt when dirty).
var _land_neighbors_by_id: Dictionary = {}
var _sea_neighbors_by_id: Dictionary = {}
var _neighbor_caches_dirty: bool = true

## Undirected edge key "min_max" -> additional movement cost on top of base cost 1.
var _strait_extra: Dictionary = {}

## Registered provinces for land/sea classification (id -> Province).
var _provinces: Dictionary = {}

var _bulk_registration_depth: int = 0


func load_adjacency(path: String = "res://data/provinces/province_adjacency.json") -> void:
	_neighbors_by_id.clear()
	_strait_extra.clear()
	_invalidate_neighbor_caches()
	if path.is_empty():
		push_warning("AdjacencySystem.load_adjacency: empty path")
		return
	if not FileAccess.file_exists(path):
		push_warning("Adjacency file missing: ", path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Cannot open adjacency file: ", path)
		return
	var text := file.get_as_text()

	var parser := JSON.new()
	if parser.parse(text) != OK:
		push_warning("Invalid JSON adjacency: ", path)
		return
	var root: Variant = parser.data
	if typeof(root) != TYPE_DICTIONARY:
		push_warning("Adjacency root must be an object: ", path)
		return
	var adj: Variant = root.get("adjacency", {})
	if typeof(adj) != TYPE_DICTIONARY:
		push_warning("Missing or invalid 'adjacency' object: ", path)
		return

	for k in adj:
		var pid := int(k)
		if pid <= 0:
			continue
		var raw: Variant = adj[k]
		if typeof(raw) != TYPE_ARRAY:
			continue
		var packed := PackedInt32Array()
		packed.resize(raw.size())
		for i in raw.size():
			packed[i] = int(raw[i])
		_neighbors_by_id[pid] = packed

	_load_straits_from_root(root)


## Load adjacency directly from a parsed dictionary (the value of the "adjacency" key or the full root).
## Extremely useful for debug hot-swaps and map generation test merges.
func load_from_dict(adj_data: Dictionary) -> void:
	_neighbors_by_id.clear()
	_strait_extra.clear()
	_invalidate_neighbor_caches()

	var adj: Dictionary = {}
	if adj_data.has("adjacency") and typeof(adj_data["adjacency"]) == TYPE_DICTIONARY:
		adj = adj_data["adjacency"]
	elif typeof(adj_data) == TYPE_DICTIONARY:
		adj = adj_data

	for k in adj:
		var pid := int(k)
		if pid <= 0:
			continue
		var raw: Variant = adj[k]
		if typeof(raw) != TYPE_ARRAY:
			continue
		var packed := PackedInt32Array()
		packed.resize(raw.size())
		for i in raw.size():
			packed[i] = int(raw[i])
		_neighbors_by_id[pid] = packed

	# Optional straits support
	if adj_data.has("straits"):
		_load_straits_from_root(adj_data)


func register_province(province: Province) -> void:
	if province == null:
		return
	_provinces[province.id] = province
	if _bulk_registration_depth == 0:
		_invalidate_neighbor_caches()


func begin_bulk_registration() -> void:
	_bulk_registration_depth += 1


func end_bulk_registration() -> void:
	_bulk_registration_depth = maxi(0, _bulk_registration_depth - 1)
	if _bulk_registration_depth == 0:
		_invalidate_neighbor_caches()


func get_neighbors(id: int) -> Array[int]:
	var packed: Variant = _neighbors_by_id.get(id, null)
	if packed == null:
		return []
	return _packed32_to_array_int(packed as PackedInt32Array)


func get_land_neighbors(id: int) -> Array[int]:
	_ensure_neighbor_caches()
	var lx: Variant = _land_neighbors_by_id.get(id, null)
	if lx == null:
		return []
	return _packed32_to_array_int(lx as PackedInt32Array)


func get_sea_neighbors(id: int) -> Array[int]:
	_ensure_neighbor_caches()
	var sx: Variant = _sea_neighbors_by_id.get(id, null)
	if sx == null:
		return []
	return _packed32_to_array_int(sx as PackedInt32Array)


func are_adjacent(a: int, b: int) -> bool:
	if a == b:
		return false
	return _packed_has_neighbor(a, b) or _packed_has_neighbor(b, a)


## Returns provinces on a minimum-movement-cost walk; empty if unreachable.
## Base step cost is 1 per edge; strait edges add the loaded "extra" penalty.
func shortest_path(from_id: int, to_id: int, only_land: bool = true) -> Array[int]:
	_ensure_neighbor_caches()
	if from_id == to_id:
		return [from_id]
	if _strait_extra.is_empty():
		return _shortest_path_bfs(from_id, to_id, only_land)
	return _shortest_path_dijkstra(from_id, to_id, only_land)


func get_connected_component(start_id: int, only_land: bool = true) -> Array[int]:
	_ensure_neighbor_caches()
	var visited: Dictionary = {}
	var order: Array[int] = []
	var queue: Array[int] = [start_id]
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		if visited.has(cur):
			continue
		visited[cur] = true
		order.append(cur)
		var nbr := _movement_neighbors_packed(cur, only_land)
		for i in nbr.size():
			var nid := int(nbr[i])
			if not visited.has(nid):
				queue.append(nid)
	return order


func _shortest_path_bfs(from_id: int, to_id: int, only_land: bool) -> Array[int]:
	var prev: Dictionary = {}
	var visited: Dictionary = {from_id: true}
	var q: Array[int] = [from_id]
	var head := 0
	while head < q.size():
		var u: int = q[head]
		head += 1
		if u == to_id:
			break
		var nbr := _movement_neighbors_packed(u, only_land)
		for i in nbr.size():
			var v := int(nbr[i])
			if visited.has(v):
				continue
			visited[v] = true
			prev[v] = u
			q.append(v)
	if from_id != to_id and not visited.has(to_id):
		return []
	return _reconstruct_path(prev, from_id, to_id)


func _shortest_path_dijkstra(from_id: int, to_id: int, only_land: bool) -> Array[int]:
	const INF := 1_000_000_000
	var dist: Dictionary = {from_id: 0}
	var prev: Dictionary = {}
	var visited: Dictionary = {}
	while true:
		var u := -1
		var best := INF
		for node in dist:
			if visited.has(node):
				continue
			var d: int = dist[node]
			if d < best:
				best = d
				u = node
		if u == -1:
			break
		if u == to_id:
			break
		visited[u] = true
		var nbr := _movement_neighbors_packed(u, only_land)
		for i in nbr.size():
			var v := int(nbr[i])
			var w := _edge_movement_cost(u, v)
			var alt: int = dist[u] + w
			if not dist.has(v) or alt < dist[v]:
				dist[v] = alt
				prev[v] = u
	if not dist.has(to_id):
		return []
	return _reconstruct_path(prev, from_id, to_id)


func _reconstruct_path(prev: Dictionary, from_id: int, to_id: int) -> Array[int]:
	var out: Array[int] = []
	var cur := to_id
	var guard := 0
	while cur != from_id:
		out.push_front(cur)
		if not prev.has(cur):
			return []
		cur = int(prev[cur])
		guard += 1
		if guard > 200_000:
			push_error("AdjacencySystem: path reconstruction exceeded guard")
			return []
	out.push_front(from_id)
	return out


func _edge_movement_cost(u: int, v: int) -> int:
	var base := 1
	var k := _undirected_key(u, v)
	if _strait_extra.has(k):
		return base + int(_strait_extra[k])
	return base


func _undirected_key(a: int, b: int) -> String:
	if a < b:
		return str(a) + "_" + str(b)
	return str(b) + "_" + str(a)


func _movement_neighbors_packed(id: int, only_land: bool) -> PackedInt32Array:
	if only_land:
		var lx: Variant = _land_neighbors_by_id.get(id, null)
		if lx == null:
			return PackedInt32Array()
		return lx as PackedInt32Array
	var gx: Variant = _neighbors_by_id.get(id, null)
	if gx == null:
		return PackedInt32Array()
	return gx as PackedInt32Array


func _invalidate_neighbor_caches() -> void:
	_land_neighbors_by_id.clear()
	_sea_neighbors_by_id.clear()
	_neighbor_caches_dirty = true


func _ensure_neighbor_caches() -> void:
	if not _neighbor_caches_dirty:
		return
	_land_neighbors_by_id.clear()
	_sea_neighbors_by_id.clear()
	for pid in _neighbors_by_id:
		var packed: PackedInt32Array = _neighbors_by_id[pid] as PackedInt32Array
		var land := PackedInt32Array()
		var sea := PackedInt32Array()
		for i in packed.size():
			var nid := int(packed[i])
			if not _provinces.has(nid):
				continue
			if (_provinces[nid] as Province).is_sea:
				sea.append(nid)
			else:
				land.append(nid)
		_land_neighbors_by_id[pid] = land
		_sea_neighbors_by_id[pid] = sea
	_neighbor_caches_dirty = false


func _packed32_to_array_int(p: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	out.resize(p.size())
	for i in p.size():
		out[i] = int(p[i])
	return out


func _packed_has_neighbor(from_id: int, to_id: int) -> bool:
	var packed: Variant = _neighbors_by_id.get(from_id, null)
	if packed == null:
		return false
	var arr := packed as PackedInt32Array
	return arr.find(to_id) != -1


func _load_straits_from_root(root: Dictionary) -> void:
	var straits: Variant = root.get("straits", null)
	if straits == null:
		return
	if typeof(straits) == TYPE_ARRAY:
		for entry in straits:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var a := int(entry.get("a", entry.get("from", 0)))
			var b := int(entry.get("b", entry.get("to", 0)))
			if a <= 0 or b <= 0:
				continue
			var extra := int(entry.get("extra", entry.get("penalty", 0)))
			if extra <= 0:
				continue
			_strait_extra[_undirected_key(a, b)] = extra
	elif typeof(straits) == TYPE_DICTIONARY:
		for kk in straits:
			var key := str(kk)
			var parts := key.split("_")
			if parts.size() != 2:
				continue
			var aa := int(parts[0])
			var bb := int(parts[1])
			var ex := int(straits[kk])
			if aa <= 0 or bb <= 0 or ex <= 0:
				continue
			_strait_extra[_undirected_key(aa, bb)] = ex
