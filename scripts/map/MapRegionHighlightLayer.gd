# scripts/map/MapRegionHighlightLayer.gd
## Vic3-style soft region tint + thin border — visible only for the region under the cursor.
class_name MapRegionHighlightLayer
extends Node2D

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")

const FILL_ALPHA: float = 0.28
const BORDER_ALPHA: float = 0.72
const BORDER_WIDTH: float = 2.0

var _province_points: Dictionary = {}  # pid -> PackedVector2Array
var _overlay_root: Node2D = null
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
	_clear_overlay()
	_hover_region_id = -1


func sync_tier(tier: int) -> void:
	if tier == _current_tier:
		return
	_current_tier = tier
	if _hover_region_id >= 0:
		_paint_region(_hover_region_id)


func set_hovered_region(region_id: int, tier: int) -> void:
	_current_tier = tier
	if region_id == _hover_region_id:
		_apply_visibility()
		return
	_hover_region_id = region_id
	if region_id < 0:
		_clear_overlay()
		return
	_paint_region(region_id)


func _apply_visibility() -> void:
	var show := (
		_hover_region_id >= 0
		and _current_tier == MapZoomLODScript.Tier.OPERATIONAL
	)
	if _overlay_root != null and is_instance_valid(_overlay_root):
		_overlay_root.visible = show


func _clear_overlay() -> void:
	if _overlay_root != null and is_instance_valid(_overlay_root):
		_overlay_root.queue_free()
	_overlay_root = null


func _paint_region(region_id: int) -> void:
	_clear_overlay()
	if region_id < 0:
		return
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

		var border := Line2D.new()
		border.points = pts
		border.closed = true
		border.width = BORDER_WIDTH
		border.default_color = border_col
		border.antialiased = true
		border.z_index = 1
		_overlay_root.add_child(border)

	_apply_visibility()


func _region_tint(region_id: int) -> Color:
	# Stable, desaturated Vic3-like hues per region id.
	var h := fmod(float(region_id) * 0.137, 1.0)
	return Color.from_hsv(h, 0.35, 0.82)
