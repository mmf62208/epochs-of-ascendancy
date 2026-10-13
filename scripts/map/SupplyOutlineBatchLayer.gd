extends Node2D

## Batched supply rings for the L overlay. Same colors / widths / glow as
## `ProvinceMapVisuals.get_supply_outline_style` + per-province Line2D rings.
## Built once; L toggle only flips `visible`. Pulse uses modulate so a paused
## session matches the static main look (session-paused Play smoke).
##
## Draw path: one merged `draw_multiline` per role/colour per spatial bucket
## that intersects the camera rect. Never antialiased — AA over thousands of
## merged rings was the FIX #3 Home-zoom hitch. Glow is a second non-AA pass
## only above `GLOW_MIN_ZOOM`; Home drops it. Rebuild bucket arrays only on
## set_items / patch_items / skip changes. Pulse stays modulate-only.

const BUCKET_SIZE := 512.0
const GLOW_MIN_ZOOM := 1.15
const LOD_MAX_ZOOM := 1.15
const LOD_MAX_POINTS := 10
const DEFAULT_RING_EXTENT := 64.0

var _items: Array[Dictionary] = []
var _closed_points: Dictionary[int, PackedVector2Array] = {}
var _skip_pids: Dictionary = {}
var _pulse_phase: float = 0.0
var _item_count: int = 0

## style_key -> {color, glow, width, glow_extra, z_index, rings: Dictionary}
var _style_groups: Dictionary = {}
## pid -> style_key
var _pid_to_style: Dictionary = {}
## style_key -> {color, glow, width, glow_extra, z_index, buckets: Dictionary}
var _style_merged: Dictionary = {}
var _dirty_styles: Dictionary = {}
var _last_draw_commands: int = 0
var _last_style_rebuilds: int = 0
var _last_geometry_touched: Dictionary = {}
var _last_aa_line_commands: int = 0
var _last_drawn_segments: int = 0
var _last_drawn_vertices: int = 0
var _last_drawn_items: int = 0
var _ring_extent: float = DEFAULT_RING_EXTENT
var _view_manual: bool = false
var _has_cached_view: bool = false
var _view_rect: Rect2 = Rect2()
var _view_zoom: float = 1.0
var _last_view_sig: String = ""


func _ready() -> void:
	z_as_relative = false
	z_index = ProvinceMapVisuals.Z_SUPPLY
	name = "SupplyOutlineBatch"
	visible = false


func clear_items() -> void:
	_items.clear()
	_closed_points.clear()
	_style_groups.clear()
	_pid_to_style.clear()
	_style_merged.clear()
	_dirty_styles.clear()
	_last_geometry_touched.clear()
	_item_count = 0
	_last_draw_commands = 0
	_last_aa_line_commands = 0
	_last_drawn_segments = 0
	_last_drawn_vertices = 0
	_last_drawn_items = 0
	_ring_extent = DEFAULT_RING_EXTENT
	queue_redraw()


func set_items(items: Array[Dictionary]) -> void:
	_items = items
	_closed_points.clear()
	_style_groups.clear()
	_pid_to_style.clear()
	_style_merged.clear()
	_dirty_styles.clear()
	_last_geometry_touched.clear()
	_item_count = 0
	_ring_extent = DEFAULT_RING_EXTENT
	for item in items:
		var pid: int = int(item.get("pid", -1))
		var pts: PackedVector2Array = item.get("points", PackedVector2Array()) as PackedVector2Array
		if pid < 0 or pts.size() < 3:
			continue
		_closed_points[pid] = ProvinceMapVisuals.close_outline_points(pts)
		_item_count += 1
		_last_geometry_touched[pid] = true
		_upsert_item_geometry(item)
	_flush_dirty_styles()
	queue_redraw()


func patch_items(upserts: Array, removed_pids: Array) -> void:
	var remove_set: Dictionary = {}
	_last_geometry_touched.clear()
	for pid_var in removed_pids:
		remove_set[int(pid_var)] = true
	var upsert_by_pid: Dictionary = {}
	for item_var in upserts:
		if typeof(item_var) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_var
		var pid: int = int(item.get("pid", -1))
		if pid < 0:
			continue
		upsert_by_pid[pid] = item
		remove_set.erase(pid)
	var kept: Array[Dictionary] = []
	for old_item in _items:
		var pid: int = int(old_item.get("pid", -1))
		if remove_set.has(pid):
			_closed_points.erase(pid)
			_remove_pid_geometry(pid)
			_last_geometry_touched[pid] = true
			continue
		if upsert_by_pid.has(pid):
			continue
		kept.append(old_item)
	for pid_var in upsert_by_pid.keys():
		var item: Dictionary = upsert_by_pid[pid_var]
		var pid: int = int(pid_var)
		var pts: PackedVector2Array = item.get("points", PackedVector2Array()) as PackedVector2Array
		if pts.size() < 3:
			_closed_points.erase(pid)
			_remove_pid_geometry(pid)
			_last_geometry_touched[pid] = true
			continue
		_closed_points[pid] = ProvinceMapVisuals.close_outline_points(pts)
		_last_geometry_touched[pid] = true
		_upsert_item_geometry(item)
		kept.append(item)
	_items = kept
	_item_count = 0
	for item2 in _items:
		var pid2: int = int(item2.get("pid", -1))
		if pid2 >= 0 and _closed_points.has(pid2):
			_item_count += 1
	_flush_dirty_styles()
	queue_redraw()


func item_count() -> int:
	return _item_count


func visible_item_count() -> int:
	if not visible:
		return 0
	return _item_count


func last_draw_command_count() -> int:
	return _last_draw_commands


func last_style_rebuilds() -> int:
	return _last_style_rebuilds


func last_aa_line_command_count() -> int:
	return _last_aa_line_commands


func last_drawn_segment_count() -> int:
	return _last_drawn_segments


func last_drawn_vertex_count() -> int:
	return _last_drawn_vertices


func last_drawn_item_count() -> int:
	return _last_drawn_items


func last_geometry_touched_pids() -> Array[int]:
	var out: Array[int] = []
	for pid_var in _last_geometry_touched.keys():
		out.append(int(pid_var))
	out.sort()
	return out


func style_group_count() -> int:
	return _style_merged.size()


func set_pulse_phase(phase: float) -> void:
	_pulse_phase = phase
	# Alpha-only pulse (width pulse on 3k Line2Ds was the L-on hang). Matches
	# apply_pulse_to_line alpha_min_scale 0.75 on the main ring.
	var raw: float = 0.5 + 0.5 * sin(phase)
	var t: float = raw * raw * (3.0 - 2.0 * raw)
	var a: float = lerpf(0.75, 1.0, t)
	modulate = Color(1.0, 1.0, 1.0, a)


func set_skip_pids(skip: Dictionary) -> void:
	var same: bool = skip.size() == _skip_pids.size()
	if same:
		for k in skip.keys():
			if not _skip_pids.has(k):
				same = false
				break
	if same:
		return
	var changed: Dictionary = {}
	for k in skip.keys():
		if not _skip_pids.has(k):
			changed[int(k)] = true
	for k2 in _skip_pids.keys():
		if not skip.has(k2):
			changed[int(k2)] = true
	_skip_pids = skip.duplicate()
	for pid_var in changed.keys():
		var pid: int = int(pid_var)
		if _pid_to_style.has(pid):
			_dirty_styles[str(_pid_to_style[pid])] = true
	_flush_dirty_styles()
	queue_redraw()


func set_view_rect(rect: Rect2) -> void:
	_view_manual = true
	_view_rect = rect
	_has_cached_view = rect.size.x > 1.0 and rect.size.y > 1.0
	_last_view_sig = ""
	queue_redraw()


func set_view_zoom(zoom: float) -> void:
	_view_manual = true
	_view_zoom = zoom
	_last_view_sig = ""
	queue_redraw()


func clear_view_override() -> void:
	_view_manual = false
	_has_cached_view = false
	_last_view_sig = ""
	queue_redraw()


func notify_view() -> void:
	if _view_manual:
		return
	var rect: Rect2 = _query_camera_rect()
	var zoom: float = _query_camera_zoom()
	var sig: String = _view_signature(rect, zoom)
	if sig == _last_view_sig:
		return
	_view_rect = rect
	_view_zoom = zoom
	_has_cached_view = rect.size.x > 1.0 and rect.size.y > 1.0
	_last_view_sig = sig
	queue_redraw()


func _style_key(item: Dictionary) -> String:
	var role: String = str(item.get("role", ""))
	var color: Color = item.get("color", Color.WHITE) as Color
	var glow: Color = item.get("glow", Color.WHITE) as Color
	var width: float = float(item.get("width", 1.8))
	var glow_extra: float = float(item.get("glow_extra", 2.0))
	return "%s|%d|%d|%.2f|%.2f" % [role, color.to_rgba32(), glow.to_rgba32(), width, glow_extra]


func _remove_pid_geometry(pid: int) -> void:
	if not _pid_to_style.has(pid):
		return
	var key: String = str(_pid_to_style[pid])
	_pid_to_style.erase(pid)
	if not _style_groups.has(key):
		_style_merged.erase(key)
		return
	var group: Dictionary = _style_groups[key]
	var rings: Dictionary = group.get("rings", {})
	rings.erase(pid)
	if rings.is_empty():
		_style_groups.erase(key)
		_style_merged.erase(key)
		_dirty_styles.erase(key)
		return
	group["rings"] = rings
	_style_groups[key] = group
	_dirty_styles[key] = true


func _upsert_item_geometry(item: Dictionary) -> void:
	var pid: int = int(item.get("pid", -1))
	if pid < 0:
		return
	var pts: PackedVector2Array = _closed_points.get(pid, PackedVector2Array()) as PackedVector2Array
	if pts.size() < 3:
		_remove_pid_geometry(pid)
		return
	var key: String = _style_key(item)
	var old_key: String = str(_pid_to_style.get(pid, ""))
	if old_key != "" and old_key != key:
		_remove_pid_geometry(pid)
	_pid_to_style[pid] = key
	var group: Dictionary = _style_groups.get(key, {})
	if group.is_empty():
		group = {
			"color": item.get("color", Color.WHITE) as Color,
			"glow": item.get("glow", Color.WHITE) as Color,
			"width": float(item.get("width", 1.8)),
			"glow_extra": float(item.get("glow_extra", 2.0)),
			"z_index": int(item.get("z_index", ProvinceMapVisuals.Z_SUPPLY)),
			"rings": {},
		}
	var rings: Dictionary = group.get("rings", {})
	rings[pid] = pts
	group["rings"] = rings
	_style_groups[key] = group
	_dirty_styles[key] = true


func _append_ring_segments(dest: PackedVector2Array, pts: PackedVector2Array) -> PackedVector2Array:
	var n: int = pts.size()
	if n < 2:
		return dest
	var seg_n: int = n - 1
	var start: int = dest.size()
	dest.resize(start + seg_n * 2)
	var i: int = 0
	while i < seg_n:
		dest[start + i * 2] = pts[i]
		dest[start + i * 2 + 1] = pts[i + 1]
		i += 1
	return dest


func _append_packed(dest: PackedVector2Array, src: PackedVector2Array) -> PackedVector2Array:
	var start: int = dest.size()
	dest.resize(start + src.size())
	var i: int = 0
	while i < src.size():
		dest[start + i] = src[i]
		i += 1
	return dest


func _ring_centroid(pts: PackedVector2Array) -> Vector2:
	var n: int = pts.size()
	if n <= 0:
		return Vector2.ZERO
	var acc: Vector2 = Vector2.ZERO
	var i: int = 0
	while i < n:
		acc += pts[i]
		i += 1
	return acc / float(n)


func _note_ring_extent(pts: PackedVector2Array) -> void:
	var n: int = pts.size()
	if n <= 0:
		return
	var min_v: Vector2 = pts[0]
	var max_v: Vector2 = pts[0]
	var i: int = 1
	while i < n:
		min_v.x = minf(min_v.x, pts[i].x)
		min_v.y = minf(min_v.y, pts[i].y)
		max_v.x = maxf(max_v.x, pts[i].x)
		max_v.y = maxf(max_v.y, pts[i].y)
		i += 1
	var ext: float = (max_v - min_v).length() * 0.5
	if ext > _ring_extent:
		_ring_extent = ext


func _lod_ring(pts: PackedVector2Array) -> PackedVector2Array:
	var n: int = pts.size()
	if n <= LOD_MAX_POINTS + 1:
		return pts
	var closed: bool = n >= 2 and pts[0].distance_squared_to(pts[n - 1]) < 0.01
	var unique: int = (n - 1) if closed else n
	if unique <= LOD_MAX_POINTS:
		return pts
	var out: PackedVector2Array = PackedVector2Array()
	var out_n: int = LOD_MAX_POINTS + (1 if closed else 0)
	out.resize(out_n)
	var i: int = 0
	while i < LOD_MAX_POINTS:
		var idx: int = int(floor(float(i) * float(unique) / float(LOD_MAX_POINTS)))
		if idx >= unique:
			idx = unique - 1
		out[i] = pts[idx]
		i += 1
	if closed:
		out[LOD_MAX_POINTS] = out[0]
	return out


func _bucket_of(pt: Vector2) -> Vector2i:
	return Vector2i(floori(pt.x / BUCKET_SIZE), floori(pt.y / BUCKET_SIZE))


func _rebuild_style_merged(key: String) -> void:
	if not _style_groups.has(key):
		_style_merged.erase(key)
		return
	var group: Dictionary = _style_groups[key]
	var rings: Dictionary = group.get("rings", {})
	var buckets: Dictionary = {}
	for pid_var in rings.keys():
		var pid: int = int(pid_var)
		if _skip_pids.has(pid):
			continue
		var pts: PackedVector2Array = rings[pid] as PackedVector2Array
		if pts.size() < 2:
			continue
		_note_ring_extent(pts)
		var cell: Vector2i = _bucket_of(_ring_centroid(pts))
		var bucket: Dictionary = buckets.get(cell, {
			"pts": PackedVector2Array(),
			"lod_pts": PackedVector2Array(),
			"item_n": 0,
		})
		var segs: PackedVector2Array = _append_ring_segments(
			bucket.get("pts", PackedVector2Array()) as PackedVector2Array,
			pts,
		)
		var lod: PackedVector2Array = _lod_ring(pts)
		var lod_segs: PackedVector2Array = _append_ring_segments(
			bucket.get("lod_pts", PackedVector2Array()) as PackedVector2Array,
			lod,
		)
		bucket["pts"] = segs
		bucket["lod_pts"] = lod_segs
		bucket["item_n"] = int(bucket.get("item_n", 0)) + 1
		buckets[cell] = bucket
	if buckets.is_empty():
		_style_merged.erase(key)
		return
	_style_merged[key] = {
		"color": group.get("color", Color.WHITE) as Color,
		"glow": group.get("glow", Color.WHITE) as Color,
		"width": float(group.get("width", 1.8)),
		"glow_extra": float(group.get("glow_extra", 2.0)),
		"z_index": int(group.get("z_index", ProvinceMapVisuals.Z_SUPPLY)),
		"buckets": buckets,
	}


func _flush_dirty_styles() -> void:
	if _dirty_styles.is_empty():
		return
	_last_style_rebuilds = 0
	for key_var in _dirty_styles.keys():
		var key: String = str(key_var)
		_rebuild_style_merged(key)
		_last_style_rebuilds += 1
	_dirty_styles.clear()


func _draw_multiline_counted(
	points: PackedVector2Array,
	color: Color,
	width: float,
	antialiased: bool,
) -> void:
	if points.size() < 2:
		return
	draw_multiline(points, color, width, antialiased)
	_last_draw_commands += 1
	if antialiased:
		_last_aa_line_commands += 1
	var verts: int = points.size()
	_last_drawn_vertices += verts
	_last_drawn_segments += verts / 2


func _style_draw_less(a: Variant, b: Variant) -> bool:
	var za: int = int((_style_merged[a] as Dictionary).get("z_index", 0))
	var zb: int = int((_style_merged[b] as Dictionary).get("z_index", 0))
	if za == zb:
		return str(a) < str(b)
	return za < zb


func _query_camera_zoom() -> float:
	var vp: Viewport = get_viewport()
	if vp == null:
		return 1.0
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return 1.0
	return maxf(cam.zoom.x, cam.zoom.y)


func _query_camera_rect() -> Rect2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return Rect2()
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return Rect2()
	var vp_size: Vector2 = vp.get_visible_rect().size
	var zoom: float = maxf(cam.zoom.x, cam.zoom.y)
	var half: Vector2 = vp_size * 0.5 / maxf(zoom, 0.01)
	var center: Vector2 = to_local(cam.global_position)
	return Rect2(center - half, half * 2.0)


func _effective_view_rect() -> Rect2:
	if _view_manual:
		return _view_rect
	if _has_cached_view:
		return _view_rect
	return _query_camera_rect()


func _effective_view_zoom() -> float:
	if _view_manual:
		return _view_zoom
	if _has_cached_view:
		return _view_zoom
	return _query_camera_zoom()


func _has_view_cull() -> bool:
	var r: Rect2 = _effective_view_rect()
	return r.size.x > 1.0 and r.size.y > 1.0


func _view_signature(rect: Rect2, zoom: float) -> String:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return "none"
	var pad: float = _ring_extent
	var x0: int = floori((rect.position.x - pad) / BUCKET_SIZE)
	var y0: int = floori((rect.position.y - pad) / BUCKET_SIZE)
	var x1: int = floori((rect.end.x + pad) / BUCKET_SIZE)
	var y1: int = floori((rect.end.y + pad) / BUCKET_SIZE)
	var glow: int = 1 if zoom >= GLOW_MIN_ZOOM else 0
	var lod: int = 1 if zoom < LOD_MAX_ZOOM else 0
	return "%d,%d,%d,%d,%d,%d" % [x0, y0, x1, y1, glow, lod]


func _visible_cells(rect: Rect2) -> Array[Vector2i]:
	var pad: float = _ring_extent
	var x0: int = floori((rect.position.x - pad) / BUCKET_SIZE)
	var y0: int = floori((rect.position.y - pad) / BUCKET_SIZE)
	var x1: int = floori((rect.end.x + pad) / BUCKET_SIZE)
	var y1: int = floori((rect.end.y + pad) / BUCKET_SIZE)
	var out: Array[Vector2i] = []
	var y: int = y0
	while y <= y1:
		var x: int = x0
		while x <= x1:
			out.append(Vector2i(x, y))
			x += 1
		y += 1
	return out


func _draw_bucket(batch: Dictionary, bucket: Dictionary, use_lod: bool, use_glow: bool) -> void:
	var pts: PackedVector2Array = bucket.get("pts", PackedVector2Array()) as PackedVector2Array
	if use_lod:
		pts = bucket.get("lod_pts", PackedVector2Array()) as PackedVector2Array
	if pts.size() < 2:
		return
	_last_drawn_items += int(bucket.get("item_n", 0))
	var width: float = float(batch.get("width", 1.8))
	var glow_extra: float = float(batch.get("glow_extra", 2.0))
	if use_glow:
		_draw_multiline_counted(
			pts,
			batch.get("glow", Color.WHITE) as Color,
			width + glow_extra,
			false,
		)
	_draw_multiline_counted(pts, batch.get("color", Color.WHITE) as Color, width, false)


func _draw() -> void:
	_flush_dirty_styles()
	_last_draw_commands = 0
	_last_aa_line_commands = 0
	_last_drawn_segments = 0
	_last_drawn_vertices = 0
	_last_drawn_items = 0
	var use_lod: bool = _effective_view_zoom() < LOD_MAX_ZOOM
	var use_glow: bool = _effective_view_zoom() >= GLOW_MIN_ZOOM
	var cull: bool = _has_view_cull()
	var cell_set: Dictionary = {}
	if cull:
		var cells: Array[Vector2i] = _visible_cells(_effective_view_rect())
		for cell in cells:
			cell_set[cell] = true
	var keys: Array = _style_merged.keys()
	keys.sort_custom(_style_draw_less)
	for key_var in keys:
		var batch: Dictionary = _style_merged[key_var]
		var buckets: Dictionary = batch.get("buckets", {})
		if cull:
			for cell_var in cell_set.keys():
				if not buckets.has(cell_var):
					continue
				_draw_bucket(batch, buckets[cell_var] as Dictionary, use_lod, use_glow)
		else:
			for cell_var2 in buckets.keys():
				_draw_bucket(batch, buckets[cell_var2] as Dictionary, use_lod, use_glow)
