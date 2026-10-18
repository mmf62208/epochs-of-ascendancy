class_name MajorRiversLayer
extends Node2D

## ATLAS-1 major rivers from rivers_world.json (mercator bake → equirect 8192).
## Scalerank ≤ MAX_SCALERANK, plus the named rivers the atlas must show.
## The Rhine stroke stays on Rx1RhineLayer. This layer skips Rhein / Rhine / Rhin
## so the river is not drawn twice. A single Rhine name label still follows the
## raw RX-1 course.

const _Canvas := preload("res://scripts/map/MapCanvasConfig.gd")
const _Rx1 := preload("res://scripts/map/Rx1RhineCrossing.gd")

const RIVER_Z := 15
const MAX_SCALERANK := 4
const RDP_EPS := 1.6
const VERTEX_CAP := 20000
const JOIN_EPS := 12.0
const SUBDIVIDE_LEN := 8.0
const HALO_COLOR := Color(0.04, 0.10, 0.20, 0.88)
const RIVER_COLOR := Color(0.22, 0.58, 0.92, 0.98)
const LABEL_COLOR := Color(0.75, 0.88, 0.98, 0.92)
const RIVERS_PATH := "res://data/map/rivers_world.json"

const LON_MIN := -180.0
const LAT_MIN := -56.0
const LON_MAX := 180.0
const LAT_MAX := 83.0
const CANVAS_W := 8192.0
const CANVAS_H := 4096.0

const _SHOWCASE := {
	"Danube": true, "Donau": true, "Elbe": true, "Oder": true, "Vistula": true,
	"Seine": true, "Loire": true, "Rhône": true, "Rhone": true, "Po": true,
	"Thames": true, "Dnipro": true, "Dnieper": true, "Volga": true,
	"Rhein": true, "Rhine": true, "Rhin": true,
}
const _LABEL_NAMES := {
	"Danube": true, "Elbe": true, "Oder": true, "Vistula": true, "Seine": true,
	"Loire": true, "Rhône": true, "Po": true, "Thames": true, "Dnieper": true,
	"Volga": true, "Rhine": true,
}

var _ready_geom: bool = false
var _records: Array = []
var _selected_name_set: Dictionary = {}
var _stroke_name_set: Dictionary = {}
var _vertex_count: int = 0
var _build_ms: float = -1.0
var _merc_lat_max: float = 0.0
var _merc_lat_min: float = 0.0
var _equirect_y_lut: PackedFloat32Array = PackedFloat32Array()
var _font: Font = null
var _labels: Array = []
var _label_zoom: float = -1.0
var _label_cam: Vector2 = Vector2(-1.0e9, -1.0e9)
var _zoom: float = 1.0
var _cam: Vector2 = Vector2.ZERO
var _vp: Vector2 = Vector2(1920, 1080)


func _ready() -> void:
	z_as_relative = false
	z_index = RIVER_Z
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	refresh()


func refresh() -> void:
	_ensure_geometry()
	queue_redraw()


func build_ms() -> float:
	_ensure_geometry()
	return _build_ms


func vertex_count() -> int:
	_ensure_geometry()
	return _vertex_count


func selected_vertex_count() -> int:
	return vertex_count()


func selected_names() -> PackedStringArray:
	_ensure_geometry()
	var out := PackedStringArray()
	var keys: Array = _selected_name_set.keys()
	keys.sort()
	for k in keys:
		out.append(str(k))
	return out


func draws_rhine_stroke() -> bool:
	_ensure_geometry()
	return _stroke_name_set.has("Rhein") or _stroke_name_set.has("Rhine") or _stroke_name_set.has("Rhin")


func raw_polylines() -> Array:
	_ensure_geometry()
	var out: Array = []
	for rec in _records:
		out.append(rec.get("raw", PackedVector2Array()))
	return out


func smoothed_polylines() -> Array:
	_ensure_geometry()
	var out: Array = []
	for rec in _records:
		out.append(rec.get("smooth", PackedVector2Array()))
	return out


func river_records() -> Array:
	_ensure_geometry()
	return _records


func set_view(zoom: float, camera_world: Vector2, viewport: Vector2) -> void:
	_zoom = zoom
	_cam = camera_world
	_vp = viewport
	_refresh_labels(true)
	queue_redraw()


func label_names_for_view() -> PackedStringArray:
	var out := PackedStringArray()
	for lbl in _labels:
		out.append(str(lbl.get("text", "")))
	return out


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var cam := viewport.get_camera_2d()
	if cam == null:
		return
	var vp_size := viewport.get_visible_rect().size
	if vp_size.x < 8.0:
		vp_size = Vector2(1920, 1080)
	var zoom := maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	var pos := cam.global_position
	var half_x := vp_size.x * 0.5 / maxf(zoom, 0.04)
	var half_y := vp_size.y * 0.5 / maxf(zoom, 0.04)
	var moved := absf(pos.x - _cam.x) > half_x or absf(pos.y - _cam.y) > half_y
	var zoom_changed := absf(zoom - _zoom) > 0.02
	if not moved and not zoom_changed and not _labels.is_empty():
		return
	_zoom = zoom
	_cam = pos
	_vp = vp_size
	_refresh_labels(false)
	queue_redraw()


func _draw() -> void:
	if _records.is_empty():
		return
	var zoom := _zoom
	var cam := _cam
	var vp := _vp
	var viewport := get_viewport()
	if viewport != null:
		var live := viewport.get_camera_2d()
		if live != null:
			zoom = maxf(absf(live.zoom.x), absf(live.zoom.y))
			cam = live.global_position
			var vp_size := viewport.get_visible_rect().size
			if vp_size.x >= 8.0:
				vp = vp_size
	var z := maxf(zoom, 0.04)
	var view := Rect2(cam - vp * 0.5 / z, vp / z)
	for rec in _records:
		var box: Rect2 = rec.get("bbox", Rect2())
		if box.size != Vector2.ZERO and not box.intersects(view):
			continue
		var pts: PackedVector2Array = rec.get("draw", PackedVector2Array())
		if pts.size() < 2:
			continue
		var width := _width_px(int(rec.get("rank", 4))) / z
		draw_polyline(pts, HALO_COLOR, width * 1.5, true)
		draw_polyline(pts, RIVER_COLOR, width, true)
	if zoom < 0.95 or zoom > 2.2:
		return
	var font := _font
	if font == null:
		font = ThemeDB.fallback_font
		_font = font
	if font == null:
		return
	var font_px := maxi(int(round(14.0 / z)), 8)
	for lbl in _labels:
		var pos: Vector2 = lbl.get("world", Vector2.ZERO)
		var ang := float(lbl.get("angle", 0.0))
		var text := str(lbl.get("text", ""))
		draw_set_transform(pos, ang, Vector2.ONE)
		draw_string_outline(font, Vector2(0, 4.0 / z), text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_px, maxi(int(2.0 / z), 1), Color(0.05, 0.08, 0.14, 0.9))
		draw_string(font, Vector2(0, 4.0 / z), text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_px, LABEL_COLOR)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _width_px(rank: int) -> float:
	var t := clampf(float(rank - 1) / 3.0, 0.0, 1.0)
	return lerpf(6.0, 3.0, t)


func _ensure_geometry() -> void:
	if _ready_geom:
		return
	_ready_geom = true
	var t0 := Time.get_ticks_usec()
	_merc_lat_max = _merc_y(LAT_MAX)
	_merc_lat_min = _merc_y(LAT_MIN)
	_build_equirect_lut()
	var text := FileAccess.get_file_as_string(RIVERS_PATH)
	var parts: Array = []
	if not text.is_empty():
		parts = _parse_selected(text)
	_records = _stitch_and_smooth(parts)
	_vertex_count = 0
	for rec in _records:
		_vertex_count += (rec.get("raw", PackedVector2Array()) as PackedVector2Array).size()
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _parse_selected(text: String) -> Array:
	var parts: Array = []
	var name_rx := RegEx.new()
	name_rx.compile("\"name\": \"([^\"]*)\",\\s*\"scalerank\":\\s*(\\d+)")
	var matches := name_rx.search_all(text)
	for i in matches.size():
		var match: RegExMatch = matches[i]
		var name := _unescape(match.get_string(1))
		var rank := int(match.get_string(2))
		var take := rank >= 1 and (rank <= MAX_SCALERANK or _SHOWCASE.has(name))
		if not take:
			continue
		_selected_name_set[name] = true
		if name == "Rhein" or name == "Rhine" or name == "Rhin":
			# Rx1RhineLayer owns the Rhine stroke (bridges + pixel guards).
			continue
		var start := match.get_end()
		var end := text.length()
		if i + 1 < matches.size():
			end = (matches[i + 1] as RegExMatch).get_start()
		var points_at := text.find("\"points\"", start)
		if points_at < 0 or points_at > end:
			continue
		var obj_end := text.find("}", points_at)
		if obj_end < 0 or obj_end > end:
			obj_end = end
		var br0 := text.find("[", points_at)
		var br1 := text.rfind("]", obj_end)
		if br0 < 0 or br1 <= br0:
			continue
		var body := text.substr(br0, br1 - br0 + 1)
		var parsed: Variant = JSON.parse_string(body)
		var raw := _equirect_points(parsed)
		if raw.size() >= 2 and _in_playable(raw):
			raw = _rdp(raw, RDP_EPS)
			if raw.size() >= 2:
				parts.append({
					"name": name,
					"canonical": _canonical(name),
					"rank": rank,
					"raw": raw,
				})
				_stroke_name_set[name] = true
	return parts


func _stitch_and_smooth(parts: Array) -> Array:
	var groups: Dictionary = {}
	var order: Array = []
	for part in parts:
		var key := str(part.get("canonical", ""))
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(part)
	var records: Array = []
	for key in order:
		var group: Array = groups[key]
		var chains := _stitch_group(group)
		for chain in chains:
			var raw: PackedVector2Array = chain.get("raw", PackedVector2Array())
			if raw.size() < 2:
				continue
			var smooth := _smooth_line(raw)
			var draw := _Canvas.scale_points(smooth)
			records.append({
				"name": chain.get("name", key),
				"canonical": key,
				"rank": int(chain.get("rank", 4)),
				"raw": raw,
				"smooth": smooth,
				"draw": draw,
				"bbox": _bbox_of(draw),
			})
	return records


func _stitch_group(group: Array) -> Array:
	var pool: Array = group.duplicate(true)
	var chains: Array = []
	while not pool.is_empty():
		var chain: Dictionary = pool.pop_back()
		var grew := true
		while grew:
			grew = false
			for i in range(pool.size() - 1, -1, -1):
				var other: Dictionary = pool[i]
				var joined := _try_join(chain, other)
				if not joined.is_empty():
					chain = joined
					pool.remove_at(i)
					grew = true
					break
		chains.append(chain)
	return chains


func _try_join(a: Dictionary, b: Dictionary) -> Dictionary:
	var pa: PackedVector2Array = a.get("raw", PackedVector2Array())
	var pb: PackedVector2Array = b.get("raw", PackedVector2Array())
	if pa.size() < 2 or pb.size() < 2:
		return {}
	var rank := mini(int(a.get("rank", 9)), int(b.get("rank", 9)))
	var name := str(a.get("name", ""))
	var combos: Array = [
		[pa, pb, false, false],
		[pa, pb, false, true],
		[pa, pb, true, false],
		[pa, pb, true, true],
	]
	for combo in combos:
		var left := _oriented(combo[0], bool(combo[2]))
		var right := _oriented(combo[1], bool(combo[3]))
		if left[left.size() - 1].distance_to(right[0]) <= JOIN_EPS:
			var merged := PackedVector2Array()
			merged.append_array(left)
			var start_j := 0
			if left[left.size() - 1].distance_squared_to(right[0]) < 1.0:
				start_j = 1
			for j in range(start_j, right.size()):
				merged.append(right[j])
			return {
				"name": name,
				"canonical": a.get("canonical", name),
				"rank": rank,
				"raw": merged,
			}
	return {}


func _oriented(pts: PackedVector2Array, reverse: bool) -> PackedVector2Array:
	if not reverse:
		return pts
	var out := PackedVector2Array()
	out.resize(pts.size())
	var n := pts.size()
	for i in n:
		out[i] = pts[n - 1 - i]
	return out


func _smooth_line(raw: PackedVector2Array) -> PackedVector2Array:
	var dense := _subdivide(raw, SUBDIVIDE_LEN)
	var curved := _chaikin(_chaikin(dense))
	if curved.size() >= 2 and raw.size() >= 2:
		curved[0] = raw[0]
		curved[curved.size() - 1] = raw[raw.size() - 1]
	return curved


func _refresh_labels(force: bool) -> void:
	if not force and absf(_zoom - _label_zoom) < 0.02 and _cam.distance_to(_label_cam) < 8.0 and not _labels.is_empty():
		return
	_label_zoom = _zoom
	_label_cam = _cam
	_labels = []
	if _zoom < 0.95 or _zoom > 2.2:
		return
	_ensure_geometry()
	var seen: Dictionary = {}
	var z := maxf(_zoom, 0.04)
	for rec in _records:
		var canon := str(rec.get("canonical", ""))
		if not _LABEL_NAMES.has(canon) or seen.has(canon):
			continue
		var best := _best_label_segment(rec.get("raw", PackedVector2Array()), z)
		if best.is_empty():
			continue
		seen[canon] = true
		_labels.append({
			"text": canon,
			"world": (best.get("mid", Vector2.ZERO) as Vector2) * _Canvas.THEATER_SCALE,
			"angle": float(best.get("angle", 0.0)),
		})
	if not seen.has("Rhine"):
		var course := _Rx1.course_points()
		var best_rhine := _best_label_segment(course, z)
		if not best_rhine.is_empty():
			_labels.append({
				"text": "Rhine",
				"world": (best_rhine.get("mid", Vector2.ZERO) as Vector2) * _Canvas.THEATER_SCALE,
				"angle": float(best_rhine.get("angle", 0.0)),
			})


func _best_label_segment(pts: PackedVector2Array, zoom: float) -> Dictionary:
	if pts.size() < 2:
		return {}
	var best_len := 24.0
	var best := {}
	for i in range(pts.size() - 1):
		var a := pts[i] * _Canvas.THEATER_SCALE
		var b := pts[i + 1] * _Canvas.THEATER_SCALE
		var mid := (a + b) * 0.5
		var screen := (mid - _cam) * zoom + _vp * 0.5
		if screen.x < 40.0 or screen.y < 24.0 or screen.x > _vp.x - 40.0 or screen.y > _vp.y - 24.0:
			continue
		var delta := b - a
		var screen_len := delta.length() * zoom
		if screen_len < best_len:
			continue
		best_len = screen_len
		var ang := delta.angle()
		if ang > PI * 0.5 or ang < -PI * 0.5:
			ang += PI
		# Label sits in 8192-space; caller scales.
		best = {"mid": (pts[i] + pts[i + 1]) * 0.5, "angle": ang}
	return best


func _canonical(name: String) -> String:
	match name:
		"Donau", "Danube":
			return "Danube"
		"Dnipro", "Dnieper":
			return "Dnieper"
		"Rhône", "Rhone":
			return "Rhône"
		"Rhein", "Rhine", "Rhin":
			return "Rhine"
		_:
			return name


func _build_equirect_lut() -> void:
	_equirect_y_lut = PackedFloat32Array()
	_equirect_y_lut.resize(int(CANVAS_H))
	for i in int(CANVAS_H):
		_equirect_y_lut[i] = _equirect_y(float(i))


func _equirect_points(parsed: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not (parsed is Array):
		return out
	var lut_n := _equirect_y_lut.size()
	var prev := Vector2(1.0e12, 1.0e12)
	for pair in parsed:
		if not (pair is Array) or (pair as Array).size() < 2:
			continue
		var x := float((pair as Array)[0])
		var y := float((pair as Array)[1])
		var yi := int(y)
		var ey: float
		if yi >= 0 and yi < lut_n and absf(y - float(yi)) < 0.05:
			ey = _equirect_y_lut[yi]
		else:
			ey = _equirect_y(y)
		var p := Vector2(x, ey)
		if p.distance_squared_to(prev) < 0.04:
			continue
		out.append(p)
		prev = p
	return out


func _in_playable(pts: PackedVector2Array) -> bool:
	var min_v := pts[0]
	var max_v := pts[0]
	for p in pts:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	if max_v.x < -80.0 or min_v.x > CANVAS_W + 80.0:
		return false
	if max_v.y < -80.0 or min_v.y > CANVAS_H + 80.0:
		return false
	return true


func _merc_y(lat: float) -> float:
	var c := clampf(lat, -85.05112878, 85.05112878)
	return (1.0 - asinh(tan(deg_to_rad(c))) / PI) * 0.5


func _equirect_y(pixel_y: float) -> float:
	var my := _merc_lat_max + (pixel_y / (CANVAS_H - 1.0)) * (_merc_lat_min - _merc_lat_max)
	var lat := rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * my))))
	return (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * (CANVAS_H - 1.0)


func _unescape(s: String) -> String:
	if s.find("\\") < 0:
		return s
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "\\" and i + 1 < s.length():
			var n := s[i + 1]
			if n == "u" and i + 5 < s.length():
				out += char(s.substr(i + 2, 4).hex_to_int())
				i += 6
				continue
			out += n
			i += 2
			continue
		out += s[i]
		i += 1
	return out


func _rdp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array = [Vector2i(0, n - 1)]
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
				var dx := p.x - (pa.x + t * vx)
				var dy := p.y - (pa.y + t * vy)
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
		if max_len > 0.01 and dist > max_len:
			steps = int(ceil(dist / max_len))
		for s in range(1, steps + 1):
			out.append(a.lerp(b, float(s) / float(steps)))
	return out


func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(pts.size() - 1):
		var p := pts[i]
		var q := pts[i + 1]
		out.append(p * 0.75 + q * 0.25)
		out.append(p * 0.25 + q * 0.75)
	out.append(pts[pts.size() - 1])
	return out


func _bbox_of(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var min_v := pts[0]
	var max_v := pts[0]
	for p in pts:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return Rect2(min_v, max_v - min_v)
