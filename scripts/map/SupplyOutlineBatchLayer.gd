extends Node2D

## Batched L-overlay rings as pre-built ArrayMesh (thick-line extrusion + glow
## underlay). One mesh pair per (role colour × map chunk). Steady _draw only
## submits those meshes. Home-zoom uses decimated rings; close-up uses full
## geometry plus a view-rect cull. Pulse is modulate-only.

const CHUNK_WORLD := 512.0
const HOME_ZOOM := 0.318
const LOD_HOME := 0
const LOD_FULL := 1
const LOD_ENTER_HOME := 0.38
const LOD_LEAVE_HOME := 0.48
const LOD_SCREEN_PX := 2.0
const LOD_HOME_MAX_PTS := 10
const MITER_LIMIT := 4.0

var _items: Array[Dictionary] = []
var _closed_points: Dictionary[int, PackedVector2Array] = {}
var _skip_pids: Dictionary = {}
var _pulse_phase: float = 0.0
var _item_count: int = 0

var _zoom: float = HOME_ZOOM
var _view_rect: Rect2 = Rect2(-1.0e7, -1.0e7, 2.0e7, 2.0e7)
var _view_rect_valid: bool = false
var _lod_level: int = LOD_HOME
var _lod_home_pts: Dictionary[int, PackedVector2Array] = {}

var _pid_meta: Dictionary = {}
var _pid_to_chunk: Dictionary = {}
var _chunk_pids: Dictionary = {}
var _chunks: Dictionary = {}

var _mesh_rebuild_count: int = 0
var _last_chunk_rebuild_count: int = 0
var _last_rebuilt_chunk_keys: PackedStringArray = PackedStringArray()
var _last_mesh_build_ms: float = 0.0
var _built_vertex_count: int = 0
var _built_index_count: int = 0

var _last_mesh_calls: int = 0
var _last_line_calls: int = 0
var _last_aa_calls: int = 0
var _last_drawn_vertex_count: int = 0
var _last_drawn_index_count: int = 0
var _last_drawn_meshes: Array = []
var _last_culled_chunks: int = 0

## Test sink: optional Object with note_draw_mesh(mesh, vertex_count, index_count).
var draw_sink: Object = null


func _ready() -> void:
	z_as_relative = false
	z_index = ProvinceMapVisuals.Z_SUPPLY
	name = "SupplyOutlineBatch"
	visible = false


func clear_items() -> void:
	_items.clear()
	_closed_points.clear()
	_lod_home_pts.clear()
	_pid_meta.clear()
	_pid_to_chunk.clear()
	_chunk_pids.clear()
	_chunks.clear()
	_item_count = 0
	_built_vertex_count = 0
	_built_index_count = 0
	_last_chunk_rebuild_count = 0
	_last_rebuilt_chunk_keys = PackedStringArray()
	queue_redraw()


func set_items(items: Array[Dictionary]) -> void:
	var t0 := Time.get_ticks_usec()
	clear_items()
	_items = items
	for item in items:
		_ingest_item(item, false)
	_rebuild_dirty_chunks(_all_chunk_keys(), true)
	_last_mesh_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	queue_redraw()


func patch_items(upserts: Array, removed_pids: Array) -> void:
	var t0 := Time.get_ticks_usec()
	var dirty: Dictionary = {}
	var remove_set: Dictionary = {}
	for pid_var in removed_pids:
		remove_set[int(pid_var)] = true
	var upsert_by_pid: Dictionary = {}
	for item_var in upserts:
		if typeof(item_var) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_var
		var pid := int(item.get("pid", -1))
		if pid < 0:
			continue
		upsert_by_pid[pid] = item
		remove_set.erase(pid)
	for pid_var in remove_set.keys():
		var pid := int(pid_var)
		var old_key := str(_pid_to_chunk.get(pid, ""))
		if not old_key.is_empty():
			dirty[old_key] = true
		_drop_pid(pid)
	var kept: Array[Dictionary] = []
	for old_item in _items:
		var pid := int(old_item.get("pid", -1))
		if remove_set.has(pid) or upsert_by_pid.has(pid):
			continue
		kept.append(old_item)
	for pid_var in upsert_by_pid.keys():
		var item: Dictionary = upsert_by_pid[pid_var]
		var pid := int(pid_var)
		var old_key := str(_pid_to_chunk.get(pid, ""))
		if not old_key.is_empty():
			dirty[old_key] = true
		_drop_pid(pid)
		if _ingest_item(item, true):
			kept.append(item)
			var new_key := str(_pid_to_chunk.get(pid, ""))
			if not new_key.is_empty():
				dirty[new_key] = true
	_items = kept
	_item_count = 0
	for item2 in _items:
		var pid2 := int(item2.get("pid", -1))
		if pid2 >= 0 and _closed_points.has(pid2):
			_item_count += 1
	_rebuild_dirty_chunks(dirty, true)
	_last_mesh_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	queue_redraw()


func item_count() -> int:
	return _item_count


func visible_item_count() -> int:
	if not visible:
		return 0
	if _skip_pids.is_empty():
		return _item_count
	var n := 0
	for item in _items:
		var pid := int(item.get("pid", -1))
		if _skip_pids.has(pid):
			continue
		if pid >= 0 and _closed_points.has(pid):
			n += 1
	return n


func set_pulse_phase(phase: float) -> void:
	_pulse_phase = phase
	var raw := 0.5 + 0.5 * sin(phase)
	var t := raw * raw * (3.0 - 2.0 * raw)
	var a := lerpf(0.75, 1.0, t)
	modulate = Color(1.0, 1.0, 1.0, a)


func set_skip_pids(skip: Dictionary) -> void:
	var same := skip.size() == _skip_pids.size()
	if same:
		for k in skip.keys():
			if not _skip_pids.has(k):
				same = false
				break
	if same:
		return
	var dirty: Dictionary = {}
	for pid_var in _skip_pids.keys():
		var key := str(_pid_to_chunk.get(int(pid_var), ""))
		if not key.is_empty():
			dirty[key] = true
	for pid_var2 in skip.keys():
		var key2 := str(_pid_to_chunk.get(int(pid_var2), ""))
		if not key2.is_empty():
			dirty[key2] = true
	_skip_pids = skip.duplicate()
	_rebuild_dirty_chunks(dirty, false)
	queue_redraw()


func set_view(zoom: float, view_rect: Rect2) -> void:
	_zoom = zoom
	_view_rect = view_rect
	_view_rect_valid = true
	var new_lod := _lod_for_zoom(zoom, _lod_level)
	if new_lod != _lod_level:
		_lod_level = new_lod
		_rebuild_dirty_chunks(_all_chunk_keys(), true)
	queue_redraw()


func get_mesh_rebuild_count() -> int:
	return _mesh_rebuild_count


func get_last_chunk_rebuild_count() -> int:
	return _last_chunk_rebuild_count


func get_last_rebuilt_chunk_keys() -> PackedStringArray:
	return _last_rebuilt_chunk_keys


func get_last_mesh_build_ms() -> float:
	return _last_mesh_build_ms


func get_built_vertex_count() -> int:
	return _built_vertex_count


func get_built_index_count() -> int:
	return _built_index_count


func get_chunk_count() -> int:
	return _chunks.size()


func get_lod_level() -> int:
	return _lod_level


func get_last_draw_stats() -> Dictionary:
	return {
		"mesh_calls": _last_mesh_calls,
		"line_calls": _last_line_calls,
		"aa_calls": _last_aa_calls,
		"drawn_vertices": _last_drawn_vertex_count,
		"drawn_indices": _last_drawn_index_count,
		"drawn_mesh_n": _last_drawn_meshes.size(),
		"culled_chunks": _last_culled_chunks,
		"built_vertices": _built_vertex_count,
		"built_indices": _built_index_count,
		"rebuilds": _mesh_rebuild_count,
		"chunk_n": _chunks.size(),
	}


func get_last_drawn_meshes() -> Array:
	return _last_drawn_meshes.duplicate()


func get_role_style_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for item in _items:
		var role := str(item.get("role", ""))
		if role.is_empty() or seen.has(role):
			continue
		seen[role] = true
		out.append({
			"role": role,
			"color": item.get("color", Color.WHITE) as Color,
			"glow": item.get("glow", Color.WHITE) as Color,
			"width": float(item.get("width", 1.8)),
			"glow_extra": float(item.get("glow_extra", 2.0)),
		})
	return out


func get_roles_in_meshes() -> Dictionary:
	var roles: Dictionary = {}
	for key_var in _chunks.keys():
		var ch: Dictionary = _chunks[key_var]
		var role := str(ch.get("role", ""))
		if not role.is_empty():
			roles[role] = true
	return roles


func _draw() -> void:
	_last_mesh_calls = 0
	_last_line_calls = 0
	_last_aa_calls = 0
	_last_drawn_vertex_count = 0
	_last_drawn_index_count = 0
	_last_drawn_meshes.clear()
	_last_culled_chunks = 0
	var cull := _lod_level == LOD_FULL and _view_rect_valid
	for key_var in _chunks.keys():
		var ch: Dictionary = _chunks[key_var]
		if cull:
			var aabb: Rect2 = ch.get("aabb", Rect2()) as Rect2
			if not aabb.intersects(_view_rect):
				_last_culled_chunks += 1
				continue
		var glow_mesh: ArrayMesh = ch.get("mesh_glow", null) as ArrayMesh
		var core_mesh: ArrayMesh = ch.get("mesh_core", null) as ArrayMesh
		if glow_mesh != null:
			_ci_draw_mesh(glow_mesh)
		if core_mesh != null:
			_ci_draw_mesh(core_mesh)


func _ci_draw_mesh(mesh: Mesh, texture: Texture2D = null, xform: Transform2D = Transform2D(), mesh_modulate: Color = Color.WHITE) -> void:
	if mesh == null or mesh.get_surface_count() < 1:
		return
	var v_n := 0
	var i_n := 0
	var s := 0
	while s < mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var verts: Variant = arr[Mesh.ARRAY_VERTEX]
		if verts is PackedVector3Array:
			v_n += (verts as PackedVector3Array).size()
		elif verts is PackedVector2Array:
			v_n += (verts as PackedVector2Array).size()
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array:
			i_n += (idx as PackedInt32Array).size()
		s += 1
	draw_mesh(mesh, texture, xform, mesh_modulate)
	_last_mesh_calls += 1
	_last_drawn_vertex_count += v_n
	_last_drawn_index_count += i_n
	_last_drawn_meshes.append(mesh)
	if draw_sink != null and draw_sink.has_method("note_draw_mesh"):
		draw_sink.call("note_draw_mesh", mesh, v_n, i_n)


func _lod_for_zoom(zoom: float, current: int) -> int:
	if current == LOD_HOME:
		if zoom >= LOD_LEAVE_HOME:
			return LOD_FULL
		return LOD_HOME
	if zoom <= LOD_ENTER_HOME:
		return LOD_HOME
	return LOD_FULL


func _ingest_item(item: Dictionary, patch: bool) -> bool:
	var pid := int(item.get("pid", -1))
	var pts: PackedVector2Array = item.get("points", PackedVector2Array()) as PackedVector2Array
	if pid < 0 or pts.size() < 3:
		return false
	var origin: Vector2 = item.get("origin", Vector2.ZERO) as Vector2
	var closed := ProvinceMapVisuals.close_outline_points(pts)
	if origin != Vector2.ZERO:
		var shifted := PackedVector2Array()
		shifted.resize(closed.size())
		var i := 0
		while i < closed.size():
			shifted[i] = closed[i] + origin
			i += 1
		closed = shifted
	_closed_points[pid] = closed
	_lod_home_pts.erase(pid)
	var role := str(item.get("role", "hub"))
	var color := item.get("color", Color.WHITE) as Color
	var glow := item.get("glow", Color.WHITE) as Color
	var width := float(item.get("width", 1.8))
	var glow_extra := float(item.get("glow_extra", 2.0))
	var c := _centroid(closed)
	var cx := int(floor(c.x / CHUNK_WORLD))
	var cy := int(floor(c.y / CHUNK_WORLD))
	var key := "%d,%d|%s" % [cx, cy, role]
	_pid_meta[pid] = {
		"role": role,
		"color": color,
		"glow": glow,
		"width": width,
		"glow_extra": glow_extra,
		"chunk": key,
	}
	_pid_to_chunk[pid] = key
	if not _chunk_pids.has(key):
		_chunk_pids[key] = {}
	(_chunk_pids[key] as Dictionary)[pid] = true
	if not patch:
		_item_count += 1
	return true


func _drop_pid(pid: int) -> void:
	var key := str(_pid_to_chunk.get(pid, ""))
	_closed_points.erase(pid)
	_lod_home_pts.erase(pid)
	_pid_meta.erase(pid)
	_pid_to_chunk.erase(pid)
	if key.is_empty():
		return
	if _chunk_pids.has(key):
		(_chunk_pids[key] as Dictionary).erase(pid)
		if (_chunk_pids[key] as Dictionary).is_empty():
			_chunk_pids.erase(key)


func _all_chunk_keys() -> Dictionary:
	var dirty: Dictionary = {}
	for key_var in _chunk_pids.keys():
		dirty[str(key_var)] = true
	return dirty


func _rebuild_dirty_chunks(dirty: Dictionary, count_as_item_rebuild: bool) -> void:
	_last_rebuilt_chunk_keys = PackedStringArray()
	_last_chunk_rebuild_count = 0
	for key_var in dirty.keys():
		var key := str(key_var)
		_rebuild_chunk(key)
		_last_rebuilt_chunk_keys.append(key)
		_last_chunk_rebuild_count += 1
	if count_as_item_rebuild:
		_mesh_rebuild_count += _last_chunk_rebuild_count
	_recount_built_geometry()


func _rebuild_chunk(key: String) -> void:
	var pids_dict: Dictionary = _chunk_pids.get(key, {}) as Dictionary
	if pids_dict.is_empty():
		_chunks.erase(key)
		return
	var role := ""
	var color := Color.WHITE
	var glow := Color.WHITE
	var width := 1.8
	var glow_extra := 2.0
	var core_v := PackedVector3Array()
	var core_c := PackedColorArray()
	var core_i := PackedInt32Array()
	var glow_v := PackedVector3Array()
	var glow_c := PackedColorArray()
	var glow_i := PackedInt32Array()
	var aabb := Rect2()
	var aabb_set := false
	for pid_var in pids_dict.keys():
		var pid := int(pid_var)
		if _skip_pids.has(pid):
			continue
		if not _pid_meta.has(pid) or not _closed_points.has(pid):
			continue
		var meta: Dictionary = _pid_meta[pid]
		if role.is_empty():
			role = str(meta.get("role", ""))
			color = meta.get("color", Color.WHITE) as Color
			glow = meta.get("glow", Color.WHITE) as Color
			width = float(meta.get("width", 1.8))
			glow_extra = float(meta.get("glow_extra", 2.0))
		var ring := _points_for_lod(pid)
		if ring.size() < 3:
			continue
		_append_extrusion(ring, width + glow_extra, glow, glow_v, glow_c, glow_i)
		_append_extrusion(ring, width, color, core_v, core_c, core_i)
		var ring_aabb := _ring_aabb(ring, (width + glow_extra) * 0.5)
		if not aabb_set:
			aabb = ring_aabb
			aabb_set = true
		else:
			aabb = aabb.merge(ring_aabb)
	if core_v.is_empty() and glow_v.is_empty():
		_chunks.erase(key)
		return
	var mesh_glow := _make_mesh(glow_v, glow_c, glow_i)
	var mesh_core := _make_mesh(core_v, core_c, core_i)
	_chunks[key] = {
		"role": role,
		"color": color,
		"glow": glow,
		"width": width,
		"glow_extra": glow_extra,
		"mesh_glow": mesh_glow,
		"mesh_core": mesh_core,
		"aabb": aabb,
		"vertex_count": glow_v.size() + core_v.size(),
		"index_count": glow_i.size() + core_i.size(),
	}


func _recount_built_geometry() -> void:
	_built_vertex_count = 0
	_built_index_count = 0
	for key_var in _chunks.keys():
		var ch: Dictionary = _chunks[key_var]
		_built_vertex_count += int(ch.get("vertex_count", 0))
		_built_index_count += int(ch.get("index_count", 0))


func _points_for_lod(pid: int) -> PackedVector2Array:
	var full: PackedVector2Array = _closed_points.get(pid, PackedVector2Array())
	if _lod_level == LOD_FULL:
		return full
	if _lod_home_pts.has(pid):
		return _lod_home_pts[pid]
	var dec := _decimate_home(full)
	_lod_home_pts[pid] = dec
	return dec


func _decimate_home(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= LOD_HOME_MAX_PTS:
		return points
	var z := maxf(_zoom, 0.05)
	var tol := LOD_SCREEN_PX / z
	var dec := _rdp_closed(points, tol)
	if dec.size() > LOD_HOME_MAX_PTS:
		dec = _stride_closed(dec, LOD_HOME_MAX_PTS)
	if dec.size() < 4:
		return _stride_closed(points, LOD_HOME_MAX_PTS)
	return dec


func _rdp_closed(points: PackedVector2Array, tol: float) -> PackedVector2Array:
	if points.size() < 4:
		return points
	var n := points.size()
	var closed := points[0].distance_squared_to(points[n - 1]) < 0.0001
	var last := n - 1 if closed else n
	if last < 3:
		return points
	var keep := PackedByteArray()
	keep.resize(last)
	keep.fill(0)
	keep[0] = 1
	keep[last - 1] = 1
	_rdp_rec(points, 0, last - 1, tol * tol, keep)
	var out := PackedVector2Array()
	var i := 0
	while i < last:
		if keep[i] == 1:
			out.append(points[i])
		i += 1
	if closed and out.size() > 0:
		if out[0].distance_squared_to(out[out.size() - 1]) > 0.0001:
			out.append(out[0])
	return out


func _rdp_rec(points: PackedVector2Array, a: int, b: int, tol_sq: float, keep: PackedByteArray) -> void:
	if b <= a + 1:
		return
	var ax := points[a].x
	var ay := points[a].y
	var bx := points[b].x
	var by := points[b].y
	var dx := bx - ax
	var dy := by - ay
	var len_sq := dx * dx + dy * dy
	var max_d := -1.0
	var max_i := a
	var i := a + 1
	while i < b:
		var px := points[i].x
		var py := points[i].y
		var dist_sq := 0.0
		if len_sq <= 0.0000001:
			var ex := px - ax
			var ey := py - ay
			dist_sq = ex * ex + ey * ey
		else:
			var t := ((px - ax) * dx + (py - ay) * dy) / len_sq
			t = clampf(t, 0.0, 1.0)
			var qx := ax + t * dx
			var qy := ay + t * dy
			var rx := px - qx
			var ry := py - qy
			dist_sq = rx * rx + ry * ry
		if dist_sq > max_d:
			max_d = dist_sq
			max_i = i
		i += 1
	if max_d > tol_sq:
		keep[max_i] = 1
		_rdp_rec(points, a, max_i, tol_sq, keep)
		_rdp_rec(points, max_i, b, tol_sq, keep)


func _stride_closed(points: PackedVector2Array, max_pts: int) -> PackedVector2Array:
	var n := points.size()
	if n <= max_pts:
		return points
	var closed := n >= 2 and points[0].distance_squared_to(points[n - 1]) < 0.0001
	var last := n - 1 if closed else n
	var keep_n := maxi(3, max_pts - (1 if closed else 0))
	var out := PackedVector2Array()
	var i := 0
	while i < keep_n:
		var idx := int(round(float(i) * float(last - 1) / float(keep_n - 1)))
		idx = clampi(idx, 0, last - 1)
		if out.is_empty() or out[out.size() - 1].distance_squared_to(points[idx]) > 0.0001:
			out.append(points[idx])
		i += 1
	if closed and out.size() > 0:
		out.append(out[0])
	return out


func _centroid(pts: PackedVector2Array) -> Vector2:
	var n := pts.size()
	if n >= 2 and pts[0].distance_squared_to(pts[n - 1]) < 0.0001:
		n -= 1
	if n <= 0:
		return Vector2.ZERO
	var s := Vector2.ZERO
	var i := 0
	while i < n:
		s += pts[i]
		i += 1
	return s / float(n)


func _ring_aabb(pts: PackedVector2Array, pad: float) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var min_v := pts[0]
	var max_v := pts[0]
	var i := 1
	while i < pts.size():
		min_v.x = minf(min_v.x, pts[i].x)
		min_v.y = minf(min_v.y, pts[i].y)
		max_v.x = maxf(max_v.x, pts[i].x)
		max_v.y = maxf(max_v.y, pts[i].y)
		i += 1
	return Rect2(min_v, max_v - min_v).grow(pad)


func _append_extrusion(
	pts: PackedVector2Array,
	width: float,
	color: Color,
	verts: PackedVector3Array,
	cols: PackedColorArray,
	indices: PackedInt32Array
) -> void:
	var n := pts.size()
	if n < 2:
		return
	var closed := pts[0].distance_squared_to(pts[n - 1]) < 0.0001
	var count := n - 1 if closed else n
	if count < 2:
		return
	var hw := width * 0.5
	var base := verts.size()
	var i := 0
	while i < count:
		var curr := pts[i]
		var prev := pts[(i - 1 + count) % count]
		var next := pts[(i + 1) % count]
		if not closed:
			if i == 0:
				prev = curr
			if i == count - 1:
				next = curr
		var d0 := curr - prev
		var d1 := next - curr
		if d0.length_squared() < 0.000001:
			d0 = d1
		if d1.length_squared() < 0.000001:
			d1 = d0
		if d0.length_squared() < 0.000001 and d1.length_squared() < 0.000001:
			d0 = Vector2(1.0, 0.0)
			d1 = d0
		d0 = d0.normalized()
		d1 = d1.normalized()
		var n0 := Vector2(-d0.y, d0.x)
		var n1 := Vector2(-d1.y, d1.x)
		var miter := n0 + n1
		var left: Vector2
		var right: Vector2
		if miter.length_squared() < 0.0001:
			left = curr + n1 * hw
			right = curr - n1 * hw
		else:
			miter = miter.normalized()
			var denom := absf(miter.dot(n1))
			var mlen := hw / maxf(0.25, denom)
			mlen = minf(mlen, hw * MITER_LIMIT)
			left = curr + miter * mlen
			right = curr - miter * mlen
		verts.append(Vector3(left.x, left.y, 0.0))
		verts.append(Vector3(right.x, right.y, 0.0))
		cols.append(color)
		cols.append(color)
		i += 1
	var s := 0
	while s < count:
		var i0 := base + s * 2
		var i1 := i0 + 1
		var nxt := (s + 1) % count
		var j0 := base + nxt * 2
		var j1 := j0 + 1
		if not closed and s == count - 1:
			break
		indices.append(i0)
		indices.append(j0)
		indices.append(i1)
		indices.append(i1)
		indices.append(j0)
		indices.append(j1)
		s += 1


func _make_mesh(verts: PackedVector3Array, cols: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty() or indices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
