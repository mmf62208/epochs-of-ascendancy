# scripts/map/MapPickGrid.gd
## Spatial hash / grid-based province picker for high province counts (250–400+).
##
## Goal (per MAP_IMPLEMENTATION_PLAN.md): Replace or supplement the expensive
## per-province Area2D + CollisionPolygon2D approach used in MapRenderer.
##
## Current design (MVP):
## - Buckets provinces by rounded centroid into a coarse grid (default cell ~64px in world/map space).
## - On query: look at the mouse cell + small neighborhood (usually 1-2 cells).
## - Among candidates, do cheap distance-to-centroid filter, then (optional) exact point-in-polygon.
## - Very fast even at 1000 provinces because we touch << 10 provinces per query.
##
## Usage (intended):
##   var picker := MapPickGrid.new()
##   picker.build(centroids_dict, cell_size=64.0)   # centroids: {id: Vector2}
##   var pid := picker.get_province_at(world_pos)
##
## Integration:
##   MapManager will own or hold a MapPickGrid instance and expose
##   get_province_at_world_pos() / get_province_at_screen_pos() that delegates here.
##
## Hybrid friendly: MapRenderer can keep lightweight Area2D nodes only when zoomed in (tactical view).

class_name MapPickGrid
extends RefCounted

## Config
var cell_size: float = 64.0
var _cell_size_inv: float = 1.0 / 64.0

## Mode flags for robustness vs performance tradeoffs
var centroid_only_mode: bool = false          # When true, skip expensive point-in-polygon (much faster, good for low zoom or dense areas)
var adaptive_radius: bool = true              # Automatically increase search radius at low zoom / large cells
var min_cell_radius: int = 1
var max_cell_radius: int = 3

## Data
var _grid: Dictionary[Vector2i, Array] = {}               # Vector2i -> Array[int] (province ids in that cell)
var _centroids: Dictionary[int, Vector2] = {}               # id -> Vector2 (world/map space)
var _province_bounds: Dictionary[int, Rect2] = {}           # id -> Rect2 (rough AABB for quick reject, optional)
var _all_ids: Array[int] = []

var _min_cell: Vector2i = Vector2i(0, 0)
var _max_cell: Vector2i = Vector2i(0, 0)
var _is_built: bool = false

## Demo virtual support: child polys from subdiv overrides become pickable (virtual ids like 82000+)
var _virtual_centroids: Dictionary = {}  # vid -> Vector2
var _virtual_polys: Dictionary = {}      # vid -> PackedVector2Array
var _virtual_to_parent: Dictionary = {}  # vid -> parent_id

## --- Build ---

## centroids: Dictionary[int, Vector2]   (province_id -> centroid in the same coordinate space as the map polygons)
func build(centroids: Dictionary[int, Vector2], p_cell_size: float = 64.0) -> void:
	clear()

	cell_size = maxf(16.0, p_cell_size)
	_cell_size_inv = 1.0 / cell_size

	_centroids = centroids.duplicate()
	_all_ids.clear()

	for pid_var in centroids.keys():
		var pid := int(pid_var)
		var c: Vector2 = centroids.get(pid, Vector2.ZERO)
		_centroids[pid] = c
		_all_ids.append(pid)

		var cell := _world_to_cell(c)
		_add_to_cell(cell, pid)

		# Optional: store a very rough AABB (single point for now; can be expanded later with full geometry)
		_province_bounds[pid] = Rect2(c, Vector2.ZERO)

	_update_bounds()

	_is_built = _all_ids.size() > 0
	print("🗺️ MapPickGrid built with %d provinces, cell_size=%.1f, %d cells" % [_all_ids.size(), cell_size, _grid.size()])

func clear() -> void:
	_grid.clear()
	_centroids.clear()
	_province_bounds.clear()
	_all_ids.clear()
	_min_cell = Vector2i(0, 0)
	_max_cell = Vector2i(0, 0)
	_is_built = false
	clear_virtuals()

func is_built() -> bool:
	return _is_built

## --- Query ---

## Returns the best matching province id near the world position, or -1.
## Robust version with adaptive radius, centroid-only fast path, and better tie-breaking for close provinces.
func get_province_at(world_pos: Vector2, max_cell_radius: int = -1, use_exact_polygon: bool = false, geometry_provider: Callable = Callable()) -> int:
	if not _is_built:
		return -1

	# Demo virtual children (from override geo) are always exact-polygon tested first (cheap, 5 max) so subdivided children are pickable in demo.
	for vkey in _virtual_polys.keys():
		var poly: PackedVector2Array = _virtual_polys[vkey]
		if poly.size() >= 3 and _point_in_polygon(world_pos, poly):
			return int(vkey)

	var effective_radius := max_cell_radius
	if effective_radius < 0:
		effective_radius = min_cell_radius
		if adaptive_radius:
			# Larger radius at low zoom / big cells helps near borders and dense areas
			var scale_factor := clampf(cell_size / 64.0, 1.0, 2.5)
			effective_radius = int(clampf(min_cell_radius * scale_factor, min_cell_radius, max_cell_radius))

	var center_cell := _world_to_cell(world_pos)
	var candidates := _get_cells_in_radius(center_cell, effective_radius)

	var best_id := -1
	var best_dist := INF
	var best_area := 0.0   # tie-breaker for very close provinces

	for cell in candidates:
		if not _grid.has(cell):
			continue
		for pid in _grid[cell] as Array:
			var c: Vector2 = _centroids.get(pid, Vector2.INF)
			if c == Vector2.INF:
				continue

			var d := world_pos.distance_squared_to(c)
			if d < best_dist - 0.0001 or (absf(d - best_dist) < 0.0001 and false):  # basic distance
				best_dist = d
				best_id = pid
				best_area = 0.0
			elif absf(d - best_dist) < 0.0001:
				# Very close centroids — prefer larger area if we can get geometry cheaply
				if geometry_provider.is_valid():
					var poly := geometry_provider.call(pid) as PackedVector2Array
					var area := _approx_polygon_area(poly)
					if area > best_area:
						best_area = area
						best_id = pid

	# Stricter exact check when requested and not in fast centroid-only mode
	if not centroid_only_mode and use_exact_polygon and best_id != -1 and geometry_provider.is_valid():
		var poly: PackedVector2Array = geometry_provider.call(best_id)
		if poly.size() >= 3 and not _point_in_polygon(world_pos, poly):
			return _brute_force_best_in_candidates(world_pos, candidates, geometry_provider)

	return best_id

## Returns up to N closest provinces (by centroid) around the position.
func get_nearest_provinces(world_pos: Vector2, count: int = 5, max_cell_radius: int = 2) -> Array[int]:
	if not _is_built or count <= 0:
		return []

	var center_cell := _world_to_cell(world_pos)
	var scored: Array = []

	var candidates := _get_cells_in_radius(center_cell, max_cell_radius)
	for cell in candidates:
		if not _grid.has(cell):
			continue
		for pid in (_grid[cell] as Array):
			var c: Vector2 = _centroids.get(pid, Vector2.INF)
			if c == Vector2.INF:
				continue
			scored.append({"id": pid, "dist2": world_pos.distance_squared_to(c)})

	scored.sort_custom(func(a, b): return a["dist2"] < b["dist2"])

	var result: Array[int] = []
	for i in mini(count, scored.size()):
		result.append(scored[i]["id"])
	return result

## --- Internal grid helpers ---

func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x * _cell_size_inv)), int(floor(p.y * _cell_size_inv)))

func _add_to_cell(cell: Vector2i, pid: int) -> void:
	if not _grid.has(cell):
		_grid[cell] = []
	(_grid[cell] as Array).append(pid)

func _get_cells_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			cells.append(Vector2i(x, y))
	return cells

func _update_bounds() -> void:
	if _grid.is_empty():
		_min_cell = Vector2i.ZERO
		_max_cell = Vector2i.ZERO
		return

	var first := true
	for cell in _grid.keys():
		var c: Vector2i = cell
		if first:
			_min_cell = c
			_max_cell = c
			first = false
		else:
			_min_cell.x = mini(_min_cell.x, c.x)
			_min_cell.y = mini(_min_cell.y, c.y)
			_max_cell.x = maxi(_max_cell.x, c.x)
			_max_cell.y = maxi(_max_cell.y, c.y)

func _brute_force_best_in_candidates(world_pos: Vector2, cells: Array[Vector2i], geometry_provider: Callable) -> int:
	var best := -1
	var best_d := INF
	for cell in cells:
		if not _grid.has(cell):
			continue
		for pid in (_grid[cell] as Array):
			var poly: PackedVector2Array = geometry_provider.call(pid)
			if poly.size() < 3:
				continue
			if _point_in_polygon(world_pos, poly):
				var c: Vector2 = _centroids.get(pid, world_pos)
				var d := world_pos.distance_squared_to(c)
				if d < best_d:
					best_d = d
					best = pid
	return best

## --- Point in Polygon (ray casting, robust enough for our use) ---

func _point_in_polygon(point: Vector2, poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false

	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var pi := poly[i]
		var pj := poly[j]

		if ((pi.y > point.y) != (pj.y > point.y)) and \
		   (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y + 0.000001) + pi.x):
			inside = not inside
		j = i
	return inside

## --- Debug / Introspection ---

func get_cell_count() -> int:
	return _grid.size()

func get_province_count() -> int:
	return _all_ids.size()

func get_cell_for_world_pos(pos: Vector2) -> Vector2i:
	return _world_to_cell(pos)

func debug_get_ids_in_cell(cell: Vector2i) -> Array[int]:
	return (_grid.get(cell, []) as Array).duplicate()

## New introspection for debugging / tuning
func get_grid_stats() -> Dictionary:
	return {
		"cell_size": cell_size,
		"total_cells": _grid.size(),
		"total_provinces": _all_ids.size(),
		"min_cell": _min_cell,
		"max_cell": _max_cell,
		"centroid_only_mode": centroid_only_mode,
		"adaptive_radius": adaptive_radius,
		"virtual_demo_children": _virtual_polys.size(),
	}

func debug_get_candidates_around(world_pos: Vector2, radius: int = 2) -> Array[int]:
	if not _is_built:
		return []
	var cell := _world_to_cell(world_pos)
	var cands: Array[int] = []
	for c in _get_cells_in_radius(cell, radius):
		if _grid.has(c):
			cands.append_array(_grid[c] as Array)
	return cands

func _approx_polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var area := 0.0
	var j := poly.size() - 1
	for i in poly.size():
		area += (poly[j].x + poly[i].x) * (poly[j].y - poly[i].y)
		j = i
	return absf(area) * 0.5

## --- Demo virtual children support (for MapPickGrid + override geo in tests) ---

## Add child polys for a parent as virtual pickable entries.
## Virtual ids are synthetic ints (parent*1000 + i) to avoid clashing real province ids; returned by get_province_at when point hits child poly exactly.
## child_polys: array of point-lists (each [[x,y], ...] or Vector2s)
func add_demo_children(parent_id: int, child_polys: Array) -> Array[int]:
	var vids: Array[int] = []
	var idx := 0
	for cp_raw in child_polys:
		var pts_arr: Array = []
		if cp_raw is Array:
			pts_arr = cp_raw
		elif cp_raw is PackedVector2Array:
			for p in cp_raw: pts_arr.append(p)
		if pts_arr.size() < 3: continue
		var ptsv := PackedVector2Array()
		var sx := 0.0
		var sy := 0.0
		var cnt := 0
		for pt in pts_arr:
			var vx: float = 0.0
			var vy: float = 0.0
			if pt is Array and pt.size() >= 2:
				vx = float(pt[0])
				vy = float(pt[1])
			elif pt is Vector2:
				vx = pt.x
				vy = pt.y
			elif pt is PackedFloat32Array and pt.size() >= 2:
				vx = pt[0]
				vy = pt[1]
			ptsv.append(Vector2(vx, vy))
			sx += vx
			sy += vy
			cnt += 1
		if cnt < 3: continue
		var c := Vector2(sx / cnt, sy / cnt)
		var vid := parent_id * 1000 + idx
		_virtual_centroids[vid] = c
		_virtual_polys[vid] = ptsv
		_virtual_to_parent[vid] = parent_id
		vids.append(vid)
		idx += 1
	if vids.size() > 0:
		print("🗺️ MapPickGrid: added ", vids.size(), " demo virtual children for parent ", parent_id, " vids=", vids, " (pickable via exact poly in get_province_at for demo test)")
	return vids

func remove_demo_children(parent_id: int = -1) -> void:
	var to_del: Array = []
	for vid in _virtual_to_parent.keys():
		if parent_id < 0 or _virtual_to_parent[vid] == parent_id:
			to_del.append(vid)
	for vid in to_del:
		_virtual_centroids.erase(vid)
		_virtual_polys.erase(vid)
		_virtual_to_parent.erase(vid)
	if to_del.size() > 0:
		print("🗺️ MapPickGrid: removed demo virtual children (parent ", parent_id if parent_id>=0 else "all", ")")

func clear_virtuals() -> void:
	_virtual_centroids.clear()
	_virtual_polys.clear()
	_virtual_to_parent.clear()

func get_virtual_count() -> int:
	return _virtual_polys.size()

func get_virtual_children_for_parent(parent_id: int) -> Array[int]:
	var res: Array[int] = []
	for vid in _virtual_to_parent:
		if _virtual_to_parent[vid] == parent_id:
			res.append(int(vid))
	return res

func has_virtual_demo() -> bool:
	return _virtual_polys.size() > 0
