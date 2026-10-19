class_name Rx1RhineLayer
extends Node2D

## Vector Rhine (Bonn→Köln→Düsseldorf→Duisburg). _draw only — never rebuild on zoom.
## Play MIXED 816cdc9: z=36 sat under country Labels (z=40 absolute) and
## draw_line widths 2.8/5.6 were world units — sub-pixel at mid Camera2D.zoom.
## FIX2 keeps theater-scale + screen-space width. Owner: units stay on top
## (z=28); river sits above labels and below counters. U hides counters.

const _Rx1 := preload("res://scripts/map/Rx1RhineCrossing.gd")
const _Canvas := preload("res://scripts/map/MapCanvasConfig.gd")

## DemoUnitIcon_* uses z_as_relative=false, z_index=28 (MapRenderer).
## Nation labels stay under the river (NATION_LABEL_Z=18).
const UNIT_COUNTER_Z := 28
const NATION_LABEL_Z := 18
const MAP_BELOW_UNITS_Z := 22
const HALO_COLOR := Color(0.04, 0.10, 0.20, 0.88)
const RIVER_COLOR := Color(0.22, 0.58, 0.92, 0.98)
const BRIDGE_COLOR := Color(0.42, 0.32, 0.16, 0.95)
const UNBRIDGED_COLOR := Color(0.72, 0.22, 0.16, 0.88)
## Screen pixels — converted to world width via 1/camera.zoom each _draw.
const HALO_SCREEN_PX := 14.0
const RIVER_SCREEN_PX := 7.0
const BRIDGE_SCREEN_PX := 5.0
## Display simplify. Fidelity clamp below keeps every painted vertex on the raw course.
const DISPLAY_RDP_EPS := 1.2
const DISPLAY_SUBDIVIDE := 4.0
const DISPLAY_FIDELITY := 1.35

var _last_zoom: float = -1.0
## Smoothed display polyline in 8192-space. Built once. course_points() stays raw.
var _display_8192: PackedVector2Array = PackedVector2Array()
var _draw_pts: PackedVector2Array = PackedVector2Array()
var _display_ready: bool = false


func _ready() -> void:
	z_as_relative = false
	z_index = MAP_BELOW_UNITS_Z
	visible = true
	modulate = Color(1, 1, 1, 1)
	set_process(true)
	_Rx1.ensure_loaded()
	_ensure_display_cache()
	_ensure_draw_pts()
	queue_redraw()


func refresh() -> void:
	_ensure_draw_pts()
	queue_redraw()


## 8192-space smoothed course used by _draw. Endpoints match the raw course.
func display_points() -> PackedVector2Array:
	_ensure_display_cache()
	return _display_8192


func _process(_delta: float) -> void:
	var z := _canvas_zoom()
	if absf(z - _last_zoom) > 0.008:
		_last_zoom = z
		_ensure_draw_pts()
		queue_redraw()


func _ensure_display_cache() -> void:
	if _display_ready:
		return
	_display_ready = true
	# Raw course stays on Rx1RhineCrossing.course_points(). This cache is paint-only.
	_display_8192 = _smooth_course(_Rx1.course_points())


func _ensure_draw_pts() -> void:
	_ensure_display_cache()
	if _draw_pts.size() == _display_8192.size() and _draw_pts.size() > 1:
		return
	_draw_pts = _Canvas.scale_points(_display_8192)


## Collinear/stair drop, two Chaikin passes, then a small axis nudge.
## Endpoints stay identical to the raw course. Every vertex stays within 1.5 wu.
func _smooth_course(raw: PackedVector2Array) -> PackedVector2Array:
	if raw.size() < 2:
		return raw
	var simple := _rdp(raw, DISPLAY_RDP_EPS)
	var dense := _subdivide(simple, DISPLAY_SUBDIVIDE)
	var curved := _chaikin(_chaikin(dense))
	curved = _nudge_axis(curved, 0.28, 0.08)
	curved = _clamp_to_polyline(curved, raw, DISPLAY_FIDELITY)
	curved = _nudge_axis(curved, 0.22, 0.08)
	curved = _clamp_to_polyline(curved, raw, 1.40)
	if curved.size() >= 2:
		curved[0] = raw[0]
		curved[curved.size() - 1] = raw[raw.size() - 1]
	return curved


func _rdp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	var eps2 := eps * eps
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var a := seg.x
		var b := seg.y
		if b <= a + 1:
			continue
		var pa := pts[a]
		var pb := pts[b]
		var vx := pb.x - pa.x
		var vy := pb.y - pa.y
		var l2 := vx * vx + vy * vy
		var best := -1
		var bestd := 0.0
		for i in range(a + 1, b):
			var p := pts[i]
			var d := 0.0
			if l2 < 1e-12:
				d = pa.distance_squared_to(p)
			else:
				var t := clampf(((p.x - pa.x) * vx + (p.y - pa.y) * vy) / l2, 0.0, 1.0)
				var qx := pa.x + t * vx
				var qy := pa.y + t * vy
				var dx := p.x - qx
				var dy := p.y - qy
				d = dx * dx + dy * dy
			if d > bestd:
				bestd = d
				best = i
		if best >= 0 and bestd > eps2:
			keep[best] = 1
			stack.append(Vector2i(a, best))
			stack.append(Vector2i(best, b))
	var out := PackedVector2Array()
	for i in n:
		if keep[i] != 0:
			out.append(pts[i])
	return out


func _subdivide(pts: PackedVector2Array, max_len: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var dist := a.distance_to(b)
		var steps := 1
		if dist > max_len and max_len > 0.01:
			steps = int(ceil(dist / max_len))
		for s in range(1, steps + 1):
			out.append(a.lerp(b, float(s) / float(steps)))
	return out


func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(n - 1):
		var p := pts[i]
		var q := pts[i + 1]
		out.append(p * 0.75 + q * 0.25)
		out.append(p * 0.25 + q * 0.75)
	out.append(pts[n - 1])
	return out


func _nudge_axis(pts: PackedVector2Array, amount: float, tol: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out := pts.duplicate()
	for i in range(n - 1):
		var dx := out[i + 1].x - out[i].x
		var dy := out[i + 1].y - out[i].y
		var l := sqrt(dx * dx + dy * dy)
		if l < 1e-6:
			continue
		if absf(dx) > tol and absf(dy) > tol:
			continue
		var px := -dy / l
		var py := dx / l
		var j := i + 1
		if j == n - 1:
			j = i
			if j == 0:
				continue
		out[j] = out[j] + Vector2(px, py) * amount
	out[0] = pts[0]
	out[n - 1] = pts[n - 1]
	return out


func _closest_on_polyline(p: Vector2, line: PackedVector2Array) -> Vector2:
	var best := line[0]
	var bestd := p.distance_squared_to(best)
	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		var vx := b.x - a.x
		var vy := b.y - a.y
		var l2 := vx * vx + vy * vy
		var t := 0.0
		if l2 > 1e-12:
			t = clampf(((p.x - a.x) * vx + (p.y - a.y) * vy) / l2, 0.0, 1.0)
		var q := Vector2(a.x + t * vx, a.y + t * vy)
		var d := p.distance_squared_to(q)
		if d < bestd:
			bestd = d
			best = q
	return best


func _clamp_to_polyline(pts: PackedVector2Array, raw: PackedVector2Array, limit: float) -> PackedVector2Array:
	if pts.size() < 2 or raw.size() < 2:
		return pts
	var out := PackedVector2Array()
	out.resize(pts.size())
	var limit2 := limit * limit
	for i in pts.size():
		if i == 0:
			out[i] = raw[0]
			continue
		if i == pts.size() - 1:
			out[i] = raw[raw.size() - 1]
			continue
		var p := pts[i]
		var q := _closest_on_polyline(p, raw)
		if p.distance_squared_to(q) <= limit2:
			out[i] = p
		else:
			var dir := p - q
			if dir.length_squared() < 1e-12:
				out[i] = q
			else:
				out[i] = q + dir.normalized() * limit
	return out


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
	# Spec course is 8192-space; live world_accurate board is × THEATER_SCALE (1.728).
	# Play MIXED 816cdc9: unscaled points sat near 4254,944 while Köln is 7351,1631.
	# Stroke uses the cached smoothed polyline (scale_points once). Bridges stay on the raw course.
	var pts := _draw_pts
	if pts.size() < 2:
		_ensure_draw_pts()
		pts = _draw_pts
	if pts.size() < 2:
		return
	var halo_w := _world_width(HALO_SCREEN_PX)
	var river_w := _world_width(RIVER_SCREEN_PX)
	draw_polyline(pts, HALO_COLOR, halo_w, true)
	draw_polyline(pts, RIVER_COLOR, river_w, true)
	_draw_bridge_markers()


func _draw_bridge_markers() -> void:
	var tick_w := _world_width(BRIDGE_SCREEN_PX)
	var half := _world_width(8.0)
	for key in _Rx1._edges.keys():
		var row: Dictionary = _Rx1._edges[key]
		var mid_v: Variant = row.get("midpoint", [])
		if typeof(mid_v) != TYPE_ARRAY or (mid_v as Array).size() < 2:
			continue
		var mid: Vector2 = _Canvas.scale_point(Vector2(float((mid_v as Array)[0]), float((mid_v as Array)[1])))
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
