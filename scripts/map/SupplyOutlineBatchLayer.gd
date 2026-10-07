extends Node2D

## Batched supply rings for the L overlay. Same colors / widths / glow as
## `ProvinceMapVisuals.get_supply_outline_style` + per-province Line2D rings.
## Built once; L toggle only flips `visible`. Pulse uses modulate so a paused
## session matches the static main look (session-paused Play smoke).

var _items: Array[Dictionary] = []
var _closed_points: Dictionary[int, PackedVector2Array] = {}
var _skip_pids: Dictionary = {}
var _pulse_phase: float = 0.0
var _item_count: int = 0


func _ready() -> void:
	z_as_relative = false
	z_index = ProvinceMapVisuals.Z_SUPPLY
	name = "SupplyOutlineBatch"
	visible = false


func clear_items() -> void:
	_items.clear()
	_closed_points.clear()
	_item_count = 0
	queue_redraw()


func set_items(items: Array[Dictionary]) -> void:
	_items = items
	_closed_points.clear()
	_item_count = 0
	for item in items:
		var pid := int(item.get("pid", -1))
		var pts: PackedVector2Array = item.get("points", PackedVector2Array()) as PackedVector2Array
		if pid < 0 or pts.size() < 3:
			continue
		_closed_points[pid] = ProvinceMapVisuals.close_outline_points(pts)
		_item_count += 1
	queue_redraw()


func patch_items(upserts: Array, removed_pids: Array) -> void:
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
	var kept: Array[Dictionary] = []
	for old_item in _items:
		var pid := int(old_item.get("pid", -1))
		if remove_set.has(pid):
			_closed_points.erase(pid)
			continue
		if upsert_by_pid.has(pid):
			continue
		kept.append(old_item)
	for pid_var in upsert_by_pid.keys():
		var item: Dictionary = upsert_by_pid[pid_var]
		var pid := int(pid_var)
		var pts: PackedVector2Array = item.get("points", PackedVector2Array()) as PackedVector2Array
		if pts.size() < 3:
			continue
		_closed_points[pid] = ProvinceMapVisuals.close_outline_points(pts)
		kept.append(item)
	_items = kept
	_item_count = 0
	for item2 in _items:
		var pid2 := int(item2.get("pid", -1))
		if pid2 >= 0 and _closed_points.has(pid2):
			_item_count += 1
	queue_redraw()


func item_count() -> int:
	return _item_count


func visible_item_count() -> int:
	if not visible:
		return 0
	return _item_count


func set_pulse_phase(phase: float) -> void:
	_pulse_phase = phase
	# Alpha-only pulse (width pulse on 3k Line2Ds was the L-on hang). Matches
	# apply_pulse_to_line alpha_min_scale 0.75 on the main ring.
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
	_skip_pids = skip.duplicate()
	queue_redraw()


func _draw() -> void:
	for item in _items:
		var pid := int(item.get("pid", -1))
		if _skip_pids.has(pid):
			continue
		var pts: PackedVector2Array = _closed_points.get(pid, PackedVector2Array())
		if pts.size() < 3:
			continue
		ProvinceMapVisuals.draw_polished_ring(
			self,
			pts,
			item.get("color", Color.WHITE) as Color,
			float(item.get("width", 1.8)),
			item.get("glow", Color.WHITE) as Color,
			float(item.get("glow_extra", 2.0)),
		)
