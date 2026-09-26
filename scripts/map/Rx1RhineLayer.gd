class_name Rx1RhineLayer
extends Node2D

## Vector Rhine (Bonn→Köln→Düsseldorf→Duisburg). _draw only — never rebuild on zoom.

const RIVER_COLOR := Color(0.18, 0.46, 0.78, 0.92)
const RIVER_WIDTH := 2.35
const BRIDGE_COLOR := Color(0.42, 0.32, 0.16, 0.95)
const UNBRIDGED_COLOR := Color(0.72, 0.22, 0.16, 0.88)
const MAX_SEGS := 160


func _ready() -> void:
	z_as_relative = false
	z_index = 7
	set_process(false)
	Rx1RhineCrossing.ensure_loaded()
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var pts: PackedVector2Array = Rx1RhineCrossing.course_points()
	if pts.size() < 2:
		return
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
		draw_line(last, nxt, RIVER_COLOR, RIVER_WIDTH, false)
		drawn += 1
		if drawn >= MAX_SEGS:
			break
		last = nxt
	_draw_bridge_markers()


func _draw_bridge_markers() -> void:
	for key in Rx1RhineCrossing._edges.keys():
		var row: Dictionary = Rx1RhineCrossing._edges[key]
		var mid_v: Variant = row.get("midpoint", [])
		if typeof(mid_v) != TYPE_ARRAY or (mid_v as Array).size() < 2:
			continue
		var mid := Vector2(float((mid_v as Array)[0]), float((mid_v as Array)[1]))
		if not mid.is_finite():
			continue
		var pair: Variant = row.get("edge", [])
		var bridged := false
		if pair is Array and (pair as Array).size() >= 2:
			bridged = Rx1RhineCrossing.is_bridged(int(pair[0]), int(pair[1]))
		var col := BRIDGE_COLOR if bridged else UNBRIDGED_COLOR
		var half := 3.4 if bridged else 2.4
		# Short bar across the river (east–west tick, river runs ~N–S).
		draw_line(mid + Vector2(-half, 0.0), mid + Vector2(half, 0.0), col, 1.8 if bridged else 1.2, false)
		if not bridged:
			draw_line(mid + Vector2(0.0, -1.6), mid + Vector2(0.0, 1.6), col, 1.0, false)
