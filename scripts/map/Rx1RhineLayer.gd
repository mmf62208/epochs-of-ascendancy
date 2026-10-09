class_name Rx1RhineLayer
extends Node2D

## Vector Rhine (Bonn→Köln→Düsseldorf→Duisburg). _draw only — never rebuild on zoom.
## Play MIXED 816cdc9: z=36 sat under country Labels (z=40 absolute) and
## draw_line widths 2.8/5.6 were world units — sub-pixel at mid Camera2D.zoom.
## FIX2 keeps theater-scale + screen-space width. Owner: units stay on top
## (z=28); river sits above labels and below counters. U hides counters.

const _Rx1 := preload("res://scripts/map/Rx1RhineCrossing.gd")
const _Canvas := preload("res://scripts/map/MapCanvasConfig.gd")
const _Road := preload("res://scripts/map/RoadTierVisual.gd")

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
const MAX_SEGS := 160
## North of Duisburg, beside the stroke. Bonn/Köln/Leverkusen sit on the south half.
const RHINE_LABEL := "Rhine"
const RHINE_LABEL_ALONG := 0.84
const RHINE_LABEL_OFFSET_PX := 18.0
const RHINE_LABEL_FONT_PX := 14.0
const RHINE_LABEL_COLOR := Color(0.85, 0.93, 1.0, 1.0)
const RHINE_LABEL_INK := Color(0.04, 0.08, 0.14, 1.0)

var _last_zoom: float = -1.0


func _ready() -> void:
	z_as_relative = false
	z_index = MAP_BELOW_UNITS_Z
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
	# Spec course is 8192-space; live world_accurate board is × THEATER_SCALE (1.728).
	# Play MIXED 816cdc9: unscaled points sat near 4254,944 while Köln is 7351,1631.
	var pts: PackedVector2Array = _Canvas.scale_points(_Rx1.course_points())
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
	if rhine_label_visible_at_zoom(_canvas_zoom()):
		_draw_rhine_name(pts)


## Far band, including the ceiling, stays unlabeled. Mid and close name the river.
static func rhine_label_visible_at_zoom(zoom: float) -> bool:
	var z: float = zoom
	if not is_finite(z):
		z = 1.0
	return z > _Road.ZOOM_FAR_MAX


func _draw_rhine_name(pts: PackedVector2Array) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null or pts.size() < 2:
		return
	var anchor := _rhine_label_point(pts)
	if not anchor.is_finite():
		return
	var z := maxf(_canvas_zoom(), 0.04)
	var font_sz := maxi(8, int(round(RHINE_LABEL_FONT_PX / z)))
	var size := font.get_string_size(RHINE_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz)
	var pos := anchor - size * 0.5
	var ink := _world_width(1.2)
	for step in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_string(font, pos + step * ink, RHINE_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, RHINE_LABEL_INK)
	draw_string(font, pos, RHINE_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, RHINE_LABEL_COLOR)


func _rhine_label_point(pts: PackedVector2Array) -> Vector2:
	var lengths: Array[float] = []
	var total := 0.0
	var i := 1
	while i < pts.size():
		var d := pts[i - 1].distance_to(pts[i])
		lengths.append(d)
		total += d
		i += 1
	if total <= 0.0:
		return pts[0]
	var target := total * RHINE_LABEL_ALONG
	var walked := 0.0
	i = 0
	while i < lengths.size():
		var span: float = lengths[i]
		if walked + span >= target or i == lengths.size() - 1:
			var t := 0.0 if span <= 0.0 else clampf((target - walked) / span, 0.0, 1.0)
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var tangent := b - a
			if tangent.length_squared() < 0.0001:
				tangent = Vector2.DOWN
			var normal := Vector2(-tangent.y, tangent.x).normalized()
			return a.lerp(b, t) + normal * _world_width(RHINE_LABEL_OFFSET_PX)
		walked += span
		i += 1
	return pts[pts.size() - 1]


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
