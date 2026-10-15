extends Node2D

## Batched L-overlay rings as pre-built ArrayMesh (thick-line extrusion + glow
## underlay). One mesh pair per (role colour × map chunk). Steady _draw only
## submits those meshes via draw_mesh. Home-zoom uses decimated rings; close-up
## uses full geometry plus a view-rect cull. Pulse is modulate-only.

const CHUNK_WORLD := 192.0
const HOME_ZOOM := 0.318
const LOD_HOME := 0
const LOD_FULL := 1
const LOD_ENTER_HOME := 0.38
const LOD_LEAVE_HOME := 0.48
const LOD_SCREEN_PX := 2.0
const LOD_HOME_MAX_PTS := 6
const LOD_RDP_MAX_SRC := 24
const MITER_LIMIT := 4.0

var _items: Array[Dictionary] = []
var _src_points: Dictionary[int, PackedVector2Array] = {}
var _skip_pids: Dictionary = {}
var _pulse_phase: float = 0.0
var _item_count: int = 0

var _zoom: float = HOME_ZOOM
var _view_rect: Rect2 = Rect2(-1.0e7, -1.0e7, 2.0e7, 2.0e7)
var _view_rect_valid: bool = false
var _lod_level: int = LOD_HOME
var _lod_home_pts: Dictionary[int, PackedVector2Array] = {}
var _lod_full_pts: Dictionary[int, PackedVector2Array] = {}

var _pid_meta: Dictionary = {}
var _pid_to_chunk: Dictionary = {}
var _chunk_pids: Dictionary = {}
var _chunks: Dictionary = {}
var _item_by_pid: Dictionary = {}

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

var _scratch_ox: PackedFloat32Array = PackedFloat32Array()
var _scratch_oy: PackedFloat32Array = PackedFloat32Array()
var _scratch_ix: PackedFloat32Array = PackedFloat32Array()
var _scratch_iy: PackedFloat32Array = PackedFloat32Array()

## Test sink: optional Object with note_draw_mesh(mesh, vertex_count, index_count).
var draw_sink: Object = null

const IDLE_PREBUILD_NONE := 0
const IDLE_PREBUILD_INGEST := 1
const IDLE_PREBUILD_MESH := 2
const IDLE_PREBUILD_WARM := 3
const IDLE_PREBUILD_DONE := 4

var _idle_phase: int = IDLE_PREBUILD_NONE
var _idle_item_source: Array[Dictionary] = []
var _idle_ingest_at: int = 0
var _idle_chunk_keys: PackedStringArray = PackedStringArray()
var _idle_chunk_at: int = 0
var _last_idle_step_ms: float = 0.0
var _idle_total_ms: float = 0.0
var _idle_warm_saved_modulate: Color = Color.WHITE
var _idle_warmed: bool = false


func _ready() -> void:
	z_as_relative = false
	z_index = ProvinceMapVisuals.Z_SUPPLY
	name = "SupplyOutlineBatch"
	visible = false


func _clear_state() -> void:
	_items.clear()
	_src_points.clear()
	_lod_home_pts.clear()
	_lod_full_pts.clear()
	_pid_meta.clear()
	_pid_to_chunk.clear()
	_chunk_pids.clear()
	_chunks.clear()
	_item_by_pid.clear()
	_item_count = 0
	_built_vertex_count = 0
	_built_index_count = 0
	_last_chunk_rebuild_count = 0
	_last_rebuilt_chunk_keys = PackedStringArray()
	_idle_item_source.clear()
	_idle_ingest_at = 0
	_idle_chunk_keys = PackedStringArray()
	_idle_chunk_at = 0
	_idle_phase = IDLE_PREBUILD_NONE


func clear_items() -> void:
	_clear_state()
	queue_redraw()


func set_items(items: Array[Dictionary]) -> void:
	var t0 := Time.get_ticks_usec()
	_clear_state()
	_items = items
	var idx := 0
	var n := _items.size()
	while idx < n:
		var item: Dictionary = _items[idx]
		var pid := int(item.get("pid", -1))
		if pid >= 0:
			_item_by_pid[pid] = idx
		_ingest_item(item, false)
		idx += 1
	_rebuild_dirty_chunks(_all_chunk_keys(), true)
	_last_mesh_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_idle_phase = IDLE_PREBUILD_DONE
	_idle_warmed = false
	queue_redraw()


func begin_idle_set_items(items: Array[Dictionary]) -> void:
	_clear_state()
	_idle_item_source = items
	_idle_ingest_at = 0
	_idle_chunk_keys = PackedStringArray()
	_idle_chunk_at = 0
	_idle_phase = IDLE_PREBUILD_INGEST
	_idle_total_ms = 0.0
	_last_idle_step_ms = 0.0
	_idle_warmed = false


func step_idle_prebuild(budget_ms: float) -> bool:
	if _idle_phase == IDLE_PREBUILD_DONE:
		_last_idle_step_ms = 0.0
		return true
	if _idle_phase == IDLE_PREBUILD_NONE or _idle_phase == IDLE_PREBUILD_WARM:
		_last_idle_step_ms = 0.0
		return _idle_phase == IDLE_PREBUILD_WARM
	var t0 := Time.get_ticks_usec()
	# Leave headroom so one last ingest/chunk cannot push the MapRenderer tick over 8.0.
	var capped_ms := minf(maxf(budget_ms, 0.25), 5.5)
	var budget_usec := maxi(1, int(capped_ms * 1000.0))
	if _idle_phase == IDLE_PREBUILD_INGEST:
		_step_idle_ingest(t0, budget_usec)
	elif _idle_phase == IDLE_PREBUILD_MESH:
		_step_idle_mesh(t0, budget_usec)
	_last_idle_step_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_idle_total_ms += _last_idle_step_ms
	if _idle_phase == IDLE_PREBUILD_WARM or _idle_phase == IDLE_PREBUILD_DONE:
		_last_mesh_build_ms = 0.0
	return _idle_phase == IDLE_PREBUILD_WARM or _idle_phase == IDLE_PREBUILD_DONE


func finish_idle_prebuild() -> void:
	while _idle_phase == IDLE_PREBUILD_INGEST or _idle_phase == IDLE_PREBUILD_MESH:
		step_idle_prebuild(10000.0)


func begin_hidden_warm() -> void:
	if _idle_warmed or _item_count <= 0:
		_idle_phase = IDLE_PREBUILD_DONE
		return
	_idle_warm_saved_modulate = modulate
	# a=0 is culled; a real first submit is required so GPU upload is not on L.
	modulate = Color.WHITE
	visible = true
	queue_redraw()
	_idle_phase = IDLE_PREBUILD_WARM


func step_hidden_warm() -> void:
	if _idle_phase != IDLE_PREBUILD_WARM:
		return
	visible = true
	queue_redraw()


func finish_hidden_warm() -> void:
	if _idle_phase != IDLE_PREBUILD_WARM and not _idle_warmed:
		_idle_phase = IDLE_PREBUILD_DONE
		return
	visible = false
	modulate = _idle_warm_saved_modulate
	_idle_warmed = true
	_last_mesh_build_ms = 0.0
	_idle_phase = IDLE_PREBUILD_DONE


func is_idle_prebuild_ready() -> bool:
	return _idle_phase == IDLE_PREBUILD_DONE and _item_count > 0


func get_idle_prebuild_stats() -> Dictionary:
	return {
		"phase": _idle_phase,
		"last_step_ms": _last_idle_step_ms,
		"total_ms": _idle_total_ms,
		"warmed": _idle_warmed,
		"item_count": _item_count,
		"ingest_at": _idle_ingest_at,
		"chunk_at": _idle_chunk_at,
		"chunk_n": _idle_chunk_keys.size(),
	}


func _usec_left(t0: int, budget_usec: int) -> int:
	return budget_usec - (Time.get_ticks_usec() - t0)


func _step_idle_ingest(t0: int, budget_usec: int) -> void:
	var n := _idle_item_source.size()
	var last_item_usec := 0
	while _idle_ingest_at < n:
		var left := _usec_left(t0, budget_usec)
		if left <= 0:
			break
		if last_item_usec > 0 and left < last_item_usec:
			break
		var item_t0 := Time.get_ticks_usec()
		var item: Dictionary = _idle_item_source[_idle_ingest_at]
		var pid := int(item.get("pid", -1))
		if pid >= 0:
			_item_by_pid[pid] = _items.size()
		_items.append(item)
		_ingest_item(item, false)
		_idle_ingest_at += 1
		last_item_usec = Time.get_ticks_usec() - item_t0
	if _idle_ingest_at >= n:
		_idle_chunk_keys = PackedStringArray()
		for key_var in _chunk_pids.keys():
			_idle_chunk_keys.append(str(key_var))
		_idle_chunk_at = 0
		_last_rebuilt_chunk_keys = PackedStringArray()
		_last_chunk_rebuild_count = 0
		_idle_phase = IDLE_PREBUILD_MESH
		if _idle_chunk_keys.is_empty():
			_recount_built_geometry()
			_last_mesh_build_ms = 0.0
			_idle_phase = IDLE_PREBUILD_WARM


func _step_idle_mesh(t0: int, budget_usec: int) -> void:
	var n := _idle_chunk_keys.size()
	var last_chunk_usec := 0
	while _idle_chunk_at < n:
		var left := _usec_left(t0, budget_usec)
		if left <= 0:
			break
		if last_chunk_usec > 0 and left < last_chunk_usec:
			break
		var chunk_t0 := Time.get_ticks_usec()
		var key := _idle_chunk_keys[_idle_chunk_at]
		_rebuild_chunk(key)
		_last_rebuilt_chunk_keys.append(key)
		_last_chunk_rebuild_count += 1
		_mesh_rebuild_count += 1
		_idle_chunk_at += 1
		last_chunk_usec = Time.get_ticks_usec() - chunk_t0
	if _idle_chunk_at >= n:
		_recount_built_geometry()
		_last_mesh_build_ms = 0.0
		_idle_phase = IDLE_PREBUILD_WARM


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
		if _src_points.has(pid):
			_item_count = maxi(0, _item_count - 1)
		_drop_pid(pid)
		_remove_item_pid(pid)
	for pid_var in upsert_by_pid.keys():
		var item: Dictionary = upsert_by_pid[pid_var]
		var pid := int(pid_var)
		var old_key := str(_pid_to_chunk.get(pid, ""))
		if not old_key.is_empty():
			dirty[old_key] = true
		if _src_points.has(pid):
			_item_count = maxi(0, _item_count - 1)
		_drop_pid(pid)
		if _ingest_item(item, true):
			_item_count += 1
			_upsert_item_pid(pid, item)
			var new_key := str(_pid_to_chunk.get(pid, ""))
			if not new_key.is_empty():
				dirty[new_key] = true
		else:
			_remove_item_pid(pid)
	_rebuild_dirty_chunks(dirty, true)
	_last_mesh_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	queue_redraw()


func _remove_item_pid(pid: int) -> void:
	if not _item_by_pid.has(pid):
		return
	var idx := int(_item_by_pid[pid])
	var last := _items.size() - 1
	if idx != last:
		var swapped: Dictionary = _items[last]
		_items[idx] = swapped
		var swapped_pid := int(swapped.get("pid", -1))
		if swapped_pid >= 0:
			_item_by_pid[swapped_pid] = idx
	_items.pop_back()
	_item_by_pid.erase(pid)


func _upsert_item_pid(pid: int, item: Dictionary) -> void:
	if _item_by_pid.has(pid):
		_items[int(_item_by_pid[pid])] = item
		return
	_item_by_pid[pid] = _items.size()
	_items.append(item)


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
		if pid >= 0 and _src_points.has(pid):
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
	if _item_count <= 0:
		queue_redraw()
		return
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
			_ci_draw_mesh(
				glow_mesh,
				ch.get("glow", Color.WHITE) as Color,
				int(ch.get("glow_verts", 0)),
				int(ch.get("glow_idx", 0)),
			)
		if core_mesh != null:
			_ci_draw_mesh(
				core_mesh,
				ch.get("color", Color.WHITE) as Color,
				int(ch.get("core_verts", 0)),
				int(ch.get("core_idx", 0)),
			)


func _ci_draw_mesh(mesh: Mesh, mesh_modulate: Color, cached_v: int = 0, cached_i: int = 0) -> void:
	if mesh == null or mesh.get_surface_count() < 1:
		return
	var v_n := cached_v
	var i_n := cached_i
	draw_mesh(mesh, null, Transform2D(), mesh_modulate)
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
	if origin != Vector2.ZERO:
		var shifted := PackedVector2Array()
		shifted.resize(pts.size())
		var i := 0
		while i < pts.size():
			shifted[i] = pts[i] + origin
			i += 1
		pts = shifted
	_src_points[pid] = pts
	_lod_home_pts.erase(pid)
	_lod_full_pts.erase(pid)
	var role := str(item.get("role", "hub"))
	var color := item.get("color", Color.WHITE) as Color
	var glow := item.get("glow", Color.WHITE) as Color
	var width := float(item.get("width", 1.8))
	var glow_extra := float(item.get("glow_extra", 2.0))
	var anchor := pts[0]
	var cx := int(floor(anchor.x / CHUNK_WORLD))
	var cy := int(floor(anchor.y / CHUNK_WORLD))
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
	_src_points.erase(pid)
	_lod_home_pts.erase(pid)
	_lod_full_pts.erase(pid)
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
	var pid_list: PackedInt32Array = PackedInt32Array()
	for pid_var in pids_dict.keys():
		var pid := int(pid_var)
		if _skip_pids.has(pid):
			continue
		if not _pid_meta.has(pid) or not _src_points.has(pid):
			continue
		pid_list.append(pid)
	if pid_list.is_empty():
		_chunks.erase(key)
		return
	var glow_n := 0
	var p_i := 0
	while p_i < pid_list.size():
		glow_n += _ring_vert_count(_points_for_lod(pid_list[p_i]))
		p_i += 1
	var glow_v := PackedVector3Array()
	var core_v := PackedVector3Array()
	glow_v.resize(glow_n)
	core_v.resize(glow_n)
	var glow_at := 0
	var core_at := 0
	var role := ""
	var color := Color.WHITE
	var glow := Color.WHITE
	var width := 1.8
	var glow_extra := 2.0
	var aabb := Rect2()
	var aabb_set := false
	var radial := _lod_level == LOD_HOME
	p_i = 0
	while p_i < pid_list.size():
		var pid := pid_list[p_i]
		var meta: Dictionary = _pid_meta[pid]
		if role.is_empty():
			role = str(meta.get("role", ""))
			color = meta.get("color", Color.WHITE) as Color
			glow = meta.get("glow", Color.WHITE) as Color
			width = float(meta.get("width", 1.8))
			glow_extra = float(meta.get("glow_extra", 2.0))
		var ring := _points_for_lod(pid)
		var hw_glow := width + glow_extra
		if radial:
			glow_at = _write_radial(ring, hw_glow, glow_v, glow_at)
			core_at = _write_radial(ring, width, core_v, core_at)
		else:
			glow_at = _write_miter(ring, hw_glow, glow_v, glow_at)
			core_at = _write_miter(ring, width, core_v, core_at)
		var ring_aabb := _ring_aabb(ring, hw_glow * 0.5)
		if not aabb_set:
			aabb = ring_aabb
			aabb_set = true
		else:
			aabb = aabb.merge(ring_aabb)
		p_i += 1
	if glow_at < glow_v.size():
		glow_v.resize(glow_at)
	if core_at < core_v.size():
		core_v.resize(core_at)
	if glow_v.is_empty() and core_v.is_empty():
		_chunks.erase(key)
		return
	var prev: Dictionary = _chunks.get(key, {}) as Dictionary
	var mesh_glow: ArrayMesh = prev.get("mesh_glow", null) as ArrayMesh
	var mesh_core: ArrayMesh = prev.get("mesh_core", null) as ArrayMesh
	mesh_glow = _fill_mesh(mesh_glow, glow_v)
	mesh_core = _fill_mesh(mesh_core, core_v)
	_chunks[key] = {
		"role": role,
		"color": color,
		"glow": glow,
		"width": width,
		"glow_extra": glow_extra,
		"mesh_glow": mesh_glow,
		"mesh_core": mesh_core,
		"aabb": aabb,
		"glow_verts": glow_v.size(),
		"core_verts": core_v.size(),
		"glow_idx": 0,
		"core_idx": 0,
		"vertex_count": glow_v.size() + core_v.size(),
		"index_count": 0,
	}


func _recount_built_geometry() -> void:
	_built_vertex_count = 0
	_built_index_count = 0
	for key_var in _chunks.keys():
		var ch: Dictionary = _chunks[key_var]
		_built_vertex_count += int(ch.get("vertex_count", 0))
		_built_index_count += int(ch.get("index_count", 0))


func _points_for_lod(pid: int) -> PackedVector2Array:
	if _lod_level == LOD_FULL:
		if _lod_full_pts.has(pid):
			return _lod_full_pts[pid]
		var src: PackedVector2Array = _src_points.get(pid, PackedVector2Array())
		var closed := ProvinceMapVisuals.close_outline_points(src)
		_lod_full_pts[pid] = closed
		return closed
	if _lod_home_pts.has(pid):
		return _lod_home_pts[pid]
	var dec := _decimate_home(_src_points.get(pid, PackedVector2Array()))
	_lod_home_pts[pid] = dec
	return dec


func _decimate_home(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= LOD_HOME_MAX_PTS:
		return _ensure_closed(points)
	if points.size() > LOD_RDP_MAX_SRC:
		return _ensure_closed(_stride_closed(points, LOD_HOME_MAX_PTS))
	var z := maxf(_zoom, 0.05)
	var tol := LOD_SCREEN_PX / z
	var dec := _rdp_closed(points, tol)
	if dec.size() > LOD_HOME_MAX_PTS:
		dec = _stride_closed(dec, LOD_HOME_MAX_PTS)
	if dec.size() < 4:
		dec = _stride_closed(points, LOD_HOME_MAX_PTS)
	return _ensure_closed(dec)


func _ensure_closed(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 2:
		return points
	if points[0].distance_squared_to(points[points.size() - 1]) < 0.0001:
		return points
	var out := PackedVector2Array(points)
	out.append(points[0])
	return out


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


func _seg_count(pts: PackedVector2Array) -> int:
	var n := pts.size()
	if n < 2:
		return 0
	var closed := pts[0].distance_squared_to(pts[n - 1]) < 0.0001
	var count := n - 1 if closed else n
	if count < 2:
		return 0
	if closed:
		return count
	return count - 1


func _ring_vert_count(pts: PackedVector2Array) -> int:
	return _seg_count(pts) * 6


func _write_radial(pts: PackedVector2Array, width: float, verts: PackedVector3Array, cursor: int) -> int:
	var n := pts.size()
	if n < 2:
		return cursor
	var closed := pts[0].distance_squared_to(pts[n - 1]) < 0.0001
	var count := n - 1 if closed else n
	if count < 2:
		return cursor
	var hw := width * 0.5
	var cx := 0.0
	var cy := 0.0
	var i := 0
	while i < count:
		cx += pts[i].x
		cy += pts[i].y
		i += 1
	var inv := 1.0 / float(count)
	cx *= inv
	cy *= inv
	if _scratch_ox.size() < count:
		_scratch_ox.resize(count)
		_scratch_oy.resize(count)
		_scratch_ix.resize(count)
		_scratch_iy.resize(count)
	i = 0
	while i < count:
		var px := pts[i].x
		var py := pts[i].y
		var dx := px - cx
		var dy := py - cy
		var ls := dx * dx + dy * dy
		if ls < 0.000001:
			dx = 1.0
			dy = 0.0
		else:
			var invl := 1.0 / sqrt(ls)
			dx *= invl
			dy *= invl
		_scratch_ox[i] = px + dx * hw
		_scratch_oy[i] = py + dy * hw
		_scratch_ix[i] = px - dx * hw
		_scratch_iy[i] = py - dy * hw
		i += 1
	var segs := count if closed else count - 1
	i = 0
	while i < segs:
		var nxt := (i + 1) % count
		verts[cursor] = Vector3(_scratch_ox[i], _scratch_oy[i], 0.0)
		verts[cursor + 1] = Vector3(_scratch_ox[nxt], _scratch_oy[nxt], 0.0)
		verts[cursor + 2] = Vector3(_scratch_ix[i], _scratch_iy[i], 0.0)
		verts[cursor + 3] = Vector3(_scratch_ix[i], _scratch_iy[i], 0.0)
		verts[cursor + 4] = Vector3(_scratch_ox[nxt], _scratch_oy[nxt], 0.0)
		verts[cursor + 5] = Vector3(_scratch_ix[nxt], _scratch_iy[nxt], 0.0)
		cursor += 6
		i += 1
	return cursor


func _write_miter(pts: PackedVector2Array, width: float, verts: PackedVector3Array, cursor: int) -> int:
	var n := pts.size()
	if n < 2:
		return cursor
	var closed := pts[0].distance_squared_to(pts[n - 1]) < 0.0001
	var count := n - 1 if closed else n
	if count < 2:
		return cursor
	var hw := width * 0.5
	if _scratch_ox.size() < count:
		_scratch_ox.resize(count)
		_scratch_oy.resize(count)
		_scratch_ix.resize(count)
		_scratch_iy.resize(count)
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
		var d0x := curr.x - prev.x
		var d0y := curr.y - prev.y
		var d1x := next.x - curr.x
		var d1y := next.y - curr.y
		var d0s := d0x * d0x + d0y * d0y
		var d1s := d1x * d1x + d1y * d1y
		if d0s < 0.000001:
			d0x = d1x
			d0y = d1y
			d0s = d1s
		if d1s < 0.000001:
			d1x = d0x
			d1y = d0y
			d1s = d0s
		if d0s < 0.000001:
			d0x = 1.0
			d0y = 0.0
			d0s = 1.0
			d1x = 1.0
			d1y = 0.0
			d1s = 1.0
		var inv0 := 1.0 / sqrt(d0s)
		var inv1 := 1.0 / sqrt(d1s)
		d0x *= inv0
		d0y *= inv0
		d1x *= inv1
		d1y *= inv1
		var n0x := -d0y
		var n0y := d0x
		var n1x := -d1y
		var n1y := d1x
		var mx := n0x + n1x
		var my := n0y + n1y
		var ms := mx * mx + my * my
		if ms < 0.0001:
			_scratch_ox[i] = curr.x + n1x * hw
			_scratch_oy[i] = curr.y + n1y * hw
			_scratch_ix[i] = curr.x - n1x * hw
			_scratch_iy[i] = curr.y - n1y * hw
		else:
			var invm := 1.0 / sqrt(ms)
			mx *= invm
			my *= invm
			var denom := absf(mx * n1x + my * n1y)
			var mlen := hw / maxf(0.25, denom)
			mlen = minf(mlen, hw * MITER_LIMIT)
			_scratch_ox[i] = curr.x + mx * mlen
			_scratch_oy[i] = curr.y + my * mlen
			_scratch_ix[i] = curr.x - mx * mlen
			_scratch_iy[i] = curr.y - my * mlen
		i += 1
	var segs := count if closed else count - 1
	i = 0
	while i < segs:
		var nxt := (i + 1) % count
		verts[cursor] = Vector3(_scratch_ox[i], _scratch_oy[i], 0.0)
		verts[cursor + 1] = Vector3(_scratch_ox[nxt], _scratch_oy[nxt], 0.0)
		verts[cursor + 2] = Vector3(_scratch_ix[i], _scratch_iy[i], 0.0)
		verts[cursor + 3] = Vector3(_scratch_ix[i], _scratch_iy[i], 0.0)
		verts[cursor + 4] = Vector3(_scratch_ox[nxt], _scratch_oy[nxt], 0.0)
		verts[cursor + 5] = Vector3(_scratch_ix[nxt], _scratch_iy[nxt], 0.0)
		cursor += 6
		i += 1
	return cursor


func _fill_mesh(mesh: ArrayMesh, verts: PackedVector3Array) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	elif mesh.get_surface_count() > 0:
		mesh.clear_surfaces()
	if verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
