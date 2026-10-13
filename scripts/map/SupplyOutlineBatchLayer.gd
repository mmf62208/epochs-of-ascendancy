extends Node2D

## Batched supply rings for the L overlay. Same colors / widths / glow as
## `ProvinceMapVisuals.get_supply_outline_style` + per-province Line2D rings.
## Built once; L toggle only flips `visible`. Pulse uses modulate so a paused
## session matches the static main look (session-paused Play smoke).
##
## Draw path: one merged `draw_multiline` for glow and one for the stroke per
## role/colour. Rebuild those arrays only on set_items / patch_items / skip
## changes. Pulse stays modulate-only.

var _items: Array[Dictionary] = []
var _closed_points: Dictionary[int, PackedVector2Array] = {}
var _skip_pids: Dictionary = {}
var _pulse_phase: float = 0.0
var _item_count: int = 0

## style_key -> {color, glow, width, glow_extra, z_index, rings: Dictionary}
var _style_groups: Dictionary = {}
## pid -> style_key
var _pid_to_style: Dictionary = {}
## style_key -> {color, glow, width, glow_extra, z_index, glow_pts, main_pts}
var _style_merged: Dictionary = {}
var _dirty_styles: Dictionary = {}
var _last_draw_commands: int = 0
var _last_style_rebuilds: int = 0
var _last_geometry_touched: Dictionary = {}


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


func _append_ring_segments(dest: PackedVector2Array, pts: PackedVector2Array) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var seg_n: int = n - 1
	var start: int = dest.size()
	dest.resize(start + seg_n * 2)
	var i: int = 0
	while i < seg_n:
		dest[start + i * 2] = pts[i]
		dest[start + i * 2 + 1] = pts[i + 1]
		i += 1


func _rebuild_style_merged(key: String) -> void:
	if not _style_groups.has(key):
		_style_merged.erase(key)
		return
	var group: Dictionary = _style_groups[key]
	var rings: Dictionary = group.get("rings", {})
	var glow_pts: PackedVector2Array = PackedVector2Array()
	var main_pts: PackedVector2Array = PackedVector2Array()
	for pid_var in rings.keys():
		var pid: int = int(pid_var)
		if _skip_pids.has(pid):
			continue
		var pts: PackedVector2Array = rings[pid] as PackedVector2Array
		_append_ring_segments(glow_pts, pts)
		_append_ring_segments(main_pts, pts)
	if glow_pts.is_empty() and main_pts.is_empty():
		_style_merged.erase(key)
		return
	_style_merged[key] = {
		"color": group.get("color", Color.WHITE) as Color,
		"glow": group.get("glow", Color.WHITE) as Color,
		"width": float(group.get("width", 1.8)),
		"glow_extra": float(group.get("glow_extra", 2.0)),
		"z_index": int(group.get("z_index", ProvinceMapVisuals.Z_SUPPLY)),
		"glow_pts": glow_pts,
		"main_pts": main_pts,
	}


func _flush_dirty_styles() -> void:
	_last_style_rebuilds = 0
	if _dirty_styles.is_empty():
		return
	for key_var in _dirty_styles.keys():
		var key: String = str(key_var)
		_rebuild_style_merged(key)
		_last_style_rebuilds += 1
	_dirty_styles.clear()


func _draw_multiline_counted(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	draw_multiline(points, color, width, true)
	_last_draw_commands += 1


func _style_draw_less(a: Variant, b: Variant) -> bool:
	var za: int = int((_style_merged[a] as Dictionary).get("z_index", 0))
	var zb: int = int((_style_merged[b] as Dictionary).get("z_index", 0))
	if za == zb:
		return str(a) < str(b)
	return za < zb


func _draw() -> void:
	_flush_dirty_styles()
	_last_draw_commands = 0
	var keys: Array = _style_merged.keys()
	keys.sort_custom(_style_draw_less)
	for key_var in keys:
		var batch: Dictionary = _style_merged[key_var]
		var width: float = float(batch.get("width", 1.8))
		var glow_extra: float = float(batch.get("glow_extra", 2.0))
		var glow_pts: PackedVector2Array = batch.get("glow_pts", PackedVector2Array()) as PackedVector2Array
		var main_pts: PackedVector2Array = batch.get("main_pts", PackedVector2Array()) as PackedVector2Array
		_draw_multiline_counted(glow_pts, batch.get("glow", Color.WHITE) as Color, width + glow_extra)
		_draw_multiline_counted(main_pts, batch.get("color", Color.WHITE) as Color, width)
