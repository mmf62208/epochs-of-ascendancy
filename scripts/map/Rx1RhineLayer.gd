class_name Rx1RhineLayer
extends Node2D

## Vector Rhine (Bonn→Köln→Düsseldorf→Duisburg). _draw only — never rebuild on zoom.
## Play MIXED 816cdc9: z=36 sat under country Labels (z=40 absolute) and
## draw_line widths 2.8/5.6 were world units — sub-pixel at mid Camera2D.zoom.
## Screen-space stroke + z above labels so the river reads at mid and close.

const _Rx1 := preload("res://scripts/map/Rx1RhineCrossing.gd")

## DemoUnitIcon_* uses z_as_relative=false, z_index=28 (MapRenderer).
## MapPoliticalLabelsLayer nation Labels use z_as_relative=false, z_index=40.
const UNIT_COUNTER_Z := 28
const NATION_LABEL_Z := 40
const ABOVE_UNIT_COUNTERS_Z := 90
const HALO_COLOR := Color(0.04, 0.10, 0.20, 0.88)
const RIVER_COLOR := Color(0.22, 0.58, 0.92, 0.98)
const BRIDGE_COLOR := Color(0.42, 0.32, 0.16, 0.95)
const UNBRIDGED_COLOR := Color(0.72, 0.22, 0.16, 0.88)
## Screen pixels — converted to world width via 1/camera.zoom each _draw.
const HALO_SCREEN_PX := 14.0
const RIVER_SCREEN_PX := 7.0
const BRIDGE_SCREEN_PX := 5.0
const MAX_SEGS := 160

var _last_zoom: float = -1.0


func _ready() -> void:
	z_as_relative = false
	z_index = ABOVE_UNIT_COUNTERS_Z
	visible = true
	modulate = Color(1, 1, 1, 1)
	set_process(true)
	_Rx1.ensure_loaded()
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	var z := _canvas_zoom()
	if absf(z - _last_zoom) > 0.008:
		_last_zoom = z
		queue_redraw()


func _canvas_zoom() -> float:
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_2d()
		if cam != null:
			return maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	return 1.0


func _world_width(screen_px: float) -> float:
	return screen_px / maxf(_canvas_zoom(), 0.04)


func _draw() -> void:
	var pts: PackedVector2Array = _Rx1.course_points()
	if pts.size() < 2:
		return
	var halo_w := _world_width(HALO_SCREEN_PX)
	var river_w := _world_width(RIVER_SCREEN_PX)
	var n := mini(pts.size(), MAX_SEGS + 1)
	var last: Vector2 = pts[0]
	var drawn := 0
	for i in range(1, n):
		var nxt: Vector2 = pts[i]
		if not last.is_finite() or not nxt.is_finite():
			last = nxt
			continue
		if last.distance_squared_to(nxt) < 0.04:
			last = nxt
			continue
		# Halo first so the river stays readable through unit plates and fills.
		draw_line(last, nxt, HALO_COLOR, halo_w, true)
		draw_line(last, nxt, RIVER_COLOR, river_w, true)
		drawn += 1
		if drawn >= MAX_SEGS:
			break
		last = nxt
	_draw_bridge_markers()


func _draw_bridge_markers() -> void:
	var tick_w := _world_width(BRIDGE_SCREEN_PX)
	var half := _world_width(8.0)
	for key in _Rx1._edges.keys():
		var row: Dictionary = _Rx1._edges[key]
		var mid_v: Variant = row.get("midpoint", [])
		if typeof(mid_v) != TYPE_ARRAY or (mid_v as Array).size() < 2:
			continue
		var mid := Vector2(float((mid_v as Array)[0]), float((mid_v as Array)[1]))
		if not mid.is_finite():
			continue
		var pair: Variant = row.get("edge", [])
		var bridged := false
		if pair is Array and (pair as Array).size() >= 2:
			bridged = _Rx1.is_bridged(int(pair[0]), int(pair[1]))
		var col := BRIDGE_COLOR if bridged else UNBRIDGED_COLOR
		var h := half if bridged else half * 0.7
		draw_line(mid + Vector2(-h, 0.0), mid + Vector2(h, 0.0), col, tick_w, true)
		if not bridged:
			draw_line(mid + Vector2(0.0, -h * 0.5), mid + Vector2(0.0, h * 0.5), col, tick_w * 0.6, true)
