# scripts/map/MapRegionHighlightLayer.gd
## Vic3-style soft region tint + merged outer border — hovered region only at operational zoom.
class_name MapRegionHighlightLayer
extends Node2D

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")

const FILL_ALPHA: float = 0.28
const BORDER_ALPHA: float = 0.72
const BORDER_WIDTH: float = 2.5
const EDGE_KEY_PRECISION: float = 1.0

var _province_points: Dictionary = {}  # pid -> PackedVector2Array
var _overlay_root: Node2D = null
var _overlay_cache: Dictionary = {}  # region_id -> Node2D (reuse on re-hover)
var _hover_region_id: int = -1
var _current_tier: int = MapZoomLODScript.Tier.STRATEGIC
var _world_canvas: bool = false


func _ready() -> void:
	z_index = 8
	set_process(false)


func rebuild_from_geometry(geometry: Dictionary, world_canvas: bool) -> void:
	_world_canvas = world_canvas
	_province_points.clear()
	for pid_var in geometry.keys():
		var pid := int(pid_var)
		var geo: Dictionary = geometry[pid_var]
		var raw: PackedVector2Array = geo.get("points", PackedVector2Array())
		if raw.size() < 3:
			continue
		_province_points[pid] = MapCanvasConfig.transform_province_points(raw, world_canvas, true)
	_clear_overlay_cache()
	_hover_region_id = -1


func sync_tier(tier: int) -> void:
	if tier == _current_tier:
		return
	_current_tier = tier
	_apply_visibility()


func set_hovered_region(region_id: int, tier: int) -> void:
	_current_tier = tier
	if region_id == _hover_region_id:
		_apply_visibility()
		return
	_hover_region_id = region_id
	if region_id < 0:
		_detach_active_overlay()
		return
	_show_region(region_id)


func _apply_visibility() -> void:
	var show := (
		_hover_region_id >= 0
		and _current_tier == MapZoomLODScript.Tier.OPERATIONAL
	)
	if _overlay_root != null and is_instance_valid(_overlay_root):
		_overlay_root.visible = show


func _detach_active_overlay() -> void:
	if _overlay_root != null and is_instance_valid(_overlay_root):
		if _overlay_root.get_parent() == self:
			remove_child(_overlay_root)
	_overlay_root = null


func _clear_overlay_cache() -> void:
	_detach_active_overlay()
	for rid_var in _overlay_cache.keys():
		var node: Node = _overlay_cache[rid_var]
		if node != null and is_instance_valid(node):
			node.queue_free()
	_overlay_cache.clear()


func _show_region(region_id: int) -> void:
	_detach_active_overlay()
	if _overlay_cache.has(region_id):
		var cached: Node2D = _overlay_cache[region_id] as Node2D
		if cached != null and is_instance_valid(cached):
			_overlay_root = cached
			add_child(_overlay_root)
			_apply_visibility()
			return
		_overlay_cache.erase(region_id)
	_build_region_overlay(region_id)


func _build_region_overlay(region_id: int) -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_strategic_region"):
		return
	var reg: Dictionary = MapManager.get_strategic_region(region_id)
	if reg.is_empty():
		return
	var pids: Array = reg.get("province_ids", [])
	if pids.is_empty():
		return

	_overlay_root = Node2D.new()
	_overlay_root.name = "RegionOverlay_%d" % region_id
	add_child(_overlay_root)

	var tint := _region_tint(region_id)
	var fill_col := Color(tint.r, tint.g, tint.b, FILL_ALPHA)
	var border_col := Color(tint.r * 0.85, tint.g * 0.85, tint.b * 0.95, BORDER_ALPHA)

	for pid_var in pids:
		var pid := int(pid_var)
		if not _province_points.has(pid):
			continue
		var pts: PackedVector2Array = _province_points[pid]
		if pts.size() < 3:
			continue

		var fill := Polygon2D.new()
		fill.polygon = pts
		fill.color = fill_col
		fill.antialiased = true
		fill.z_index = 0
		_overlay_root.add_child(fill)

	var boundary := _build_region_boundary_segments(pids)
	if not boundary.is_empty():
		var outline := Node2D.new()
		outline.name = "RegionOutline"
		outline.z_index = 1
		_overlay_root.add_child(outline)
		var seg_idx := 0
		for seg: Dictionary in boundary:
			var line := Line2D.new()
			line.name = "Seg_%d" % seg_idx
			line.points = PackedVector2Array([seg["a"] as Vector2, seg["b"] as Vector2])
			line.width = BORDER_WIDTH
			line.default_color = border_col
			line.antialiased = true
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			outline.add_child(line)
			seg_idx += 1

	_overlay_cache[region_id] = _overlay_root
	_apply_visibility()


func _build_region_boundary_segments(pids: Array) -> Array:
	var edge_map: Dictionary = {}
	for pid_var in pids:
		var pid := int(pid_var)
		if not _province_points.has(pid):
			continue
		var pts: PackedVector2Array = _province_points[pid]
		if pts.size() < 3:
			continue
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var key := _canonical_edge_key(a, b)
			if not edge_map.has(key):
				edge_map[key] = {"a": a, "b": b, "count": 0}
			var rec: Dictionary = edge_map[key]
			rec["count"] = int(rec.get("count", 0)) + 1

	var out: Array = []
	for key in edge_map.keys():
		var rec: Dictionary = edge_map[key]
		if int(rec.get("count", 0)) == 1:
			out.append(rec)
	return out


func _canonical_edge_key(a: Vector2, b: Vector2) -> String:
	var step := EDGE_KEY_PRECISION
	var ax := int(roundf(a.x / step))
	var ay := int(roundf(a.y / step))
	var bx := int(roundf(b.x / step))
	var by := int(roundf(b.y / step))
	if ax > bx or (ax == bx and ay > by):
		var tx := ax
		ax = bx
		bx = tx
		var ty := ay
		ay = by
		by = ty
	return "%d,%d|%d,%d" % [ax, ay, bx, by]


func _region_tint(region_id: int) -> Color:
	var h := fmod(float(region_id) * 0.137, 1.0)
	return Color.from_hsv(h, 0.35, 0.82)
