class_name CityLabelsLayer
extends Node2D

## ATLAS-1 view-only city names. Candidates load once. Collision runs again
## only when the zoom band changes or the camera moves by more than half a screen.
## Nation labels win: a city label whose rect sits inside a nation rect is dropped.

const _LOD := preload("res://scripts/map/MapZoomLOD.gd")
const _Canvas := preload("res://scripts/map/MapCanvasConfig.gd")

const CITY_Z := 19
const MAX_ON_SCREEN := 60
const MID_TIER2_SCORE_FLOOR := 400.0
const LABEL_SHIFT_PX := 72.0
const FILL_COLOR := Color(0.08, 0.07, 0.05, 1.0)
const OUTLINE_COLOR := Color(1.0, 0.97, 0.88, 1.0)

const _CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const _ECON_PATH := "res://data/provinces_world_accurate/province_economy_layer.json"
const _BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const _OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const _GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const _SCENARIO_PATH := "res://data/scenarios/world_accurate.json"

var rebuild_count: int = 0

var _candidates: Array = []
var _candidates_ready: bool = false
var _placed: Array = []
var _layout_ready: bool = false
var _last_band: int = -1
var _last_cam: Vector2 = Vector2(-1.0e9, -1.0e9)
var _last_vp: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _cam: Vector2 = Vector2.ZERO
var _vp: Vector2 = Vector2(1920, 1080)
var _nation_override: Array = []
var _use_nation_override: bool = false
var _show_labels: bool = true
var _mode: String = "political"
var _font: Font = null
var _by_pid: Dictionary = {}
var _build_ms: float = -1.0
var _dots: Node2D = null


func _ready() -> void:
	z_as_relative = false
	z_index = CITY_Z
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	var dots := _DotMarks.new()
	dots.name = "CityLabelDots"
	dots.host = self
	dots.z_as_relative = false
	dots.z_index = 46
	dots.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dots)
	_dots = dots
	ensure_candidates()


func bind_centroids(cents: Dictionary) -> void:
	if cents.is_empty() or _candidates.is_empty():
		ensure_candidates()
	for c in _candidates:
		var pid := int(c.get("pid", 0))
		if cents.has(pid):
			var w: Vector2 = cents[pid] as Vector2
			if w != Vector2.ZERO:
				c["world"] = w
				_by_pid[pid] = c
	_layout_ready = false


func set_map_mode(mode: String) -> void:
	var m := mode.strip_edges().to_lower()
	if m.is_empty():
		m = "political"
	var show := m != "states"
	if m == _mode and show == _show_labels:
		return
	_mode = m
	_show_labels = show
	_layout_ready = false
	if _candidates_ready:
		_resolve_layout()
	_queue_paint()


func ensure_candidates() -> void:
	if _candidates_ready:
		return
	var t0 := Time.get_ticks_usec()
	_load_candidates()
	_candidates_ready = true
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func rebuild_candidates() -> void:
	_candidates_ready = false
	_candidates.clear()
	_by_pid.clear()
	rebuild_count += 1
	ensure_candidates()
	_layout_ready = false


func build_ms() -> float:
	ensure_candidates()
	return _build_ms


func fade_alpha(zoom: float, enter_zoom: float) -> float:
	return _LOD.city_label_fade_alpha(zoom, enter_zoom)


func score_of(pid: int) -> float:
	ensure_candidates()
	if not _by_pid.has(pid):
		return -1.0
	return float((_by_pid[pid] as Dictionary).get("score", -1.0))


func world_of(pid: int) -> Vector2:
	ensure_candidates()
	if not _by_pid.has(pid):
		return Vector2.ZERO
	return (_by_pid[pid] as Dictionary).get("world", Vector2.ZERO) as Vector2


func display_name_of(pid: int) -> String:
	ensure_candidates()
	if not _by_pid.has(pid):
		return ""
	return str((_by_pid[pid] as Dictionary).get("name", ""))


func is_eligible(pid: int, band_name: String) -> bool:
	ensure_candidates()
	if not _by_pid.has(pid):
		return false
	return _in_band(_by_pid[pid], _zoom_for_band(band_name))


func eligible_count(band_name: String) -> int:
	ensure_candidates()
	var zoom := _zoom_for_band(band_name)
	var n := 0
	for c in _candidates:
		if _in_band(c, zoom):
			n += 1
	return n


func candidate_count() -> int:
	ensure_candidates()
	return _candidates.size()


func placed() -> Array:
	return _placed


func screen_count() -> int:
	var n := 0
	for p in _placed:
		if float(p.get("alpha", 0.0)) >= 0.04:
			n += 1
	return n


func set_view(zoom: float, camera_world: Vector2, viewport: Vector2, nation_rects: Array = []) -> void:
	_zoom = zoom
	_cam = camera_world
	_vp = viewport
	if _vp.x < 8.0 or _vp.y < 8.0:
		_vp = Vector2(1920, 1080)
	_nation_override = nation_rects
	_use_nation_override = true
	# Callers pass an explicit view. Always rebuild so a nation-rect or zoom
	# change is not dropped when the camera sample has not moved half a screen.
	_layout_ready = false
	_resolve_layout()
	_queue_paint()


func place_competing(cands: Array, zoom: float, cam: Vector2, vp: Vector2, nation_rects: Array, max_shift: float) -> Array:
	var list: Array = cands.duplicate(true)
	for c in list:
		var world: Vector2 = c.get("world", Vector2.ZERO)
		c["dist"] = world.distance_to(cam)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _priority_before(a, b)
	)
	var placed: Array = []
	var font := _font_or_null()
	for c in list:
		if not _in_band(c, zoom):
			continue
		var enter := float(c.get("enter", 0.0))
		var alpha := _LOD.city_label_fade_alpha(zoom, enter)
		var world: Vector2 = c.get("world", Vector2.ZERO)
		var anchor_s := (world - cam) * zoom + vp * 0.5
		if anchor_s.x < -120.0 or anchor_s.y < -80.0 or anchor_s.x > vp.x + 120.0 or anchor_s.y > vp.y + 80.0:
			continue
		var tier := int(c.get("tier", 1))
		var px := _LOD.city_label_font_px(tier)
		var text := str(c.get("name", ""))
		var size := _measure(font, text, px)
		var base := Vector2(6.0, -size.y * 0.72)
		if bool(c.get("capital", false)):
			base = Vector2(14.0, -size.y * 0.72)
		var accepted := false
		var chosen := Rect2()
		var chosen_off := base
		for off in _slot_offsets(base, max_shift):
			var rect := Rect2(anchor_s + off, size)
			if _rects_clear(rect, placed, nation_rects, vp):
				chosen = rect
				chosen_off = off
				accepted = true
				break
		if not accepted:
			continue
		if placed.size() >= MAX_ON_SCREEN:
			break
		placed.append({
			"name": text,
			"pid": int(c.get("pid", 0)),
			"screen_rect": chosen,
			"screen_offset": chosen_off,
			"capital": bool(c.get("capital", false)),
			"tier": tier,
			"alpha": alpha,
			"score": float(c.get("score", 0.0)),
			"world": world,
			"enter": enter,
			"font_px": px,
		})
	return placed


func _priority_before(a: Dictionary, b: Dictionary) -> bool:
	var ac := bool(a.get("capital", false))
	var bc := bool(b.get("capital", false))
	if ac != bc:
		return ac
	var at := int(a.get("tier", 0))
	var bt := int(b.get("tier", 0))
	if at != bt:
		return at > bt
	var ascore := float(a.get("score", 0.0))
	var bscore := float(b.get("score", 0.0))
	if absf(ascore - bscore) > 0.05:
		return ascore > bscore
	var ad := float(a.get("dist", 0.0))
	var bd := float(b.get("dist", 0.0))
	if absf(ad - bd) > 0.5:
		return ad < bd
	var an := str(a.get("name", ""))
	var bn := str(b.get("name", ""))
	if an.length() != bn.length():
		return an.length() < bn.length()
	return int(a.get("pid", 0)) < int(b.get("pid", 0))


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var cam := viewport.get_camera_2d()
	if cam == null:
		return
	var vp_size := viewport.get_visible_rect().size
	if vp_size.x < 8.0 or vp_size.y < 8.0:
		vp_size = Vector2(1920, 1080)
	var zoom := maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	var band := _LOD.city_label_band_for_zoom(zoom)
	var half_x := vp_size.x * 0.5 / maxf(zoom, 0.04)
	var half_y := vp_size.y * 0.5 / maxf(zoom, 0.04)
	var pos := cam.global_position
	var moved := absf(pos.x - _cam.x) > half_x or absf(pos.y - _cam.y) > half_y
	var band_changed := band != _last_band
	var zoom_changed := absf(zoom - _zoom) > 0.004
	if not _layout_ready or band_changed or moved:
		_zoom = zoom
		_cam = pos
		_vp = vp_size
		_use_nation_override = false
		_resolve_layout()
		_queue_paint()
	elif zoom_changed:
		_zoom = zoom
		_queue_paint()


func _resolve_layout() -> void:
	ensure_candidates()
	if not _show_labels:
		if not _placed.is_empty():
			_placed = []
		_layout_ready = true
		_last_band = _LOD.city_label_band_for_zoom(_zoom)
		return
	var band := _LOD.city_label_band_for_zoom(_zoom)
	var half_x := _vp.x * 0.5 / maxf(_zoom, 0.04)
	var half_y := _vp.y * 0.5 / maxf(_zoom, 0.04)
	var moved := absf(_cam.x - _last_cam.x) > half_x or absf(_cam.y - _last_cam.y) > half_y
	var band_changed := band != _last_band
	var vp_changed := _last_vp.distance_squared_to(_vp) > 4.0
	if _layout_ready and not band_changed and not moved and not vp_changed:
		return
	_last_band = band
	_last_cam = _cam
	_last_vp = _vp
	_layout_ready = true
	rebuild_count += 1
	var nations := _nation_rects_for_layout()
	_placed = place_competing(_candidates, _zoom, _cam, _vp, nations, LABEL_SHIFT_PX)


func _nation_rects_for_layout() -> Array:
	if _use_nation_override:
		return _nation_override
	return _live_nation_rects()


func _live_nation_rects() -> Array:
	var parent_node := get_parent()
	if parent_node == null:
		return []
	var layer := parent_node.get_node_or_null("PoliticalLabelsLayer")
	if layer == null:
		return []
	var out: Array = []
	var zoom := maxf(_zoom, 0.04)
	for child in layer.get_children():
		if not (child is Label):
			continue
		var lbl := child as Label
		if not lbl.visible:
			continue
		if not str(lbl.name).begins_with("NationLabel_"):
			continue
		var world_pos := lbl.global_position
		var screen_pos := (world_pos - _cam) * zoom + _vp * 0.5
		var screen_size := lbl.size * zoom
		out.append(Rect2(screen_pos, screen_size))
	return out


func _draw() -> void:
	if not _show_labels or _placed.is_empty():
		return
	var font := _font
	if font == null:
		font = _font_or_null()
	if font == null:
		return
	var zoom := _zoom
	var viewport := get_viewport()
	if viewport != null:
		var cam := viewport.get_camera_2d()
		if cam != null:
			zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	var z := maxf(zoom, 0.04)
	for item in _placed:
		var enter := float(item.get("enter", 0.0))
		var alpha := _LOD.city_label_fade_alpha(zoom, enter)
		if alpha < 0.04:
			continue
		var world: Vector2 = item.get("world", Vector2.ZERO)
		var off: Vector2 = item.get("screen_offset", Vector2(6, -8))
		var world_text := world + off / z
		var px := maxi(int(item.get("font_px", 11)), 8)
		var world_px := maxi(int(round(float(px) / z)), 8)
		var outline_px := maxi(int(round(3.0 / z)), 1)
		var text := str(item.get("name", ""))
		draw_string_outline(font, world_text, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, world_px, outline_px, Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, alpha))
		draw_string(font, world_text, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, world_px, Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, alpha))


func _rects_clear(rect: Rect2, placed: Array, nations: Array, vp: Vector2) -> bool:
	var view := Rect2(Vector2.ZERO, vp).grow(8.0)
	if not rect.intersects(view):
		return false
	for p in placed:
		var other: Rect2 = p.get("screen_rect", Rect2())
		if rect.intersects(other.grow(1.0)):
			return false
	for n in nations:
		if n is Rect2 and rect.intersects((n as Rect2).grow(1.0)):
			return false
	return true


func _slot_offsets(base: Vector2, max_shift: float) -> Array:
	var out: Array = [base]
	if max_shift < 1.0:
		return out
	var radii: Array[float] = [10.0, 16.0, 24.0, 34.0, 46.0, 58.0, 72.0]
	var dirs: Array[Vector2] = [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(0.7071, -0.7071), Vector2(-0.7071, -0.7071),
		Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071),
	]
	for radius in radii:
		if radius > max_shift + 0.01:
			break
		for dir in dirs:
			out.append(base + dir * radius)
	return out


func _measure(font: Font, text: String, px: int) -> Vector2:
	if font != null:
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		return Vector2(maxf(sz.x, float(px)) + 4.0, maxf(sz.y, float(px) + 2.0))
	return Vector2(float(text.length()) * float(px) * 0.56 + 4.0, float(px) + 4.0)


func _font_or_null() -> Font:
	if _font != null:
		return _font
	_font = ThemeDB.fallback_font
	return _font


func _zoom_for_band(band_name: String) -> float:
	match band_name:
		"home", "wide":
			return 0.40
		"strategic":
			return 0.70
		"mid", "operational":
			return 1.55
		_:
			return 2.40


func _in_band(c: Dictionary, zoom: float) -> bool:
	var band := _LOD.city_label_band_for_zoom(zoom)
	var tier := int(c.get("tier", 1))
	var capital := bool(c.get("capital", false))
	var score := float(c.get("score", 0.0))
	if band == _LOD.CITY_BAND_HOME:
		return tier >= 4
	if band == _LOD.CITY_BAND_STRATEGIC:
		return tier >= 3 or capital
	if band == _LOD.CITY_BAND_MID:
		return tier >= 3 or capital or (tier >= 2 and score >= MID_TIER2_SCORE_FLOOR)
	return true


func _score_city(tier: int, pop: float, kreis: bool, port: bool) -> float:
	var score := float(tier) * 100.0
	score += minf(pop, 5000000.0) * 0.001
	if kreis:
		score += 250.0
	if port:
		score += 40.0
	return score


func _enter_zoom(tier: int, capital: bool, score: float) -> float:
	if tier >= 4:
		return 0.0
	if tier >= 3 or capital:
		return _LOD.CITY_LABEL_HOME_MAX
	if tier >= 2 and score >= MID_TIER2_SCORE_FLOOR:
		return _LOD.CITY_LABEL_STRATEGIC_MAX
	return _LOD.CITY_LABEL_MID_MAX


func _load_candidates() -> void:
	_candidates.clear()
	_by_pid.clear()
	var city_text := FileAccess.get_file_as_string(_CITY_PATH)
	var econ_text := FileAccess.get_file_as_string(_ECON_PATH)
	var base_text := FileAccess.get_file_as_string(_BASE_PATH)
	var own_text := FileAccess.get_file_as_string(_OWN_PATH)
	var scenario_text := FileAccess.get_file_as_string(_SCENARIO_PATH)
	if city_text.is_empty():
		return
	var city_root: Variant = JSON.parse_string(city_text)
	var econ_root: Variant = JSON.parse_string(econ_text)
	var base_root: Variant = JSON.parse_string(base_text)
	var own_root: Variant = JSON.parse_string(own_text)
	var scenario_root: Variant = JSON.parse_string(scenario_text)
	if typeof(city_root) != TYPE_DICTIONARY:
		return
	var city_rows: Dictionary = (city_root as Dictionary).get("provinces", {})
	var econ_rows: Dictionary = {}
	if typeof(econ_root) == TYPE_DICTIONARY:
		econ_rows = (econ_root as Dictionary).get("provinces", {})
	var names: Dictionary = {}
	var ports: Dictionary = {}
	if typeof(base_root) == TYPE_DICTIONARY:
		var rows: Variant = (base_root as Dictionary).get("provinces", [])
		if rows is Array:
			for row in rows:
				if typeof(row) != TYPE_DICTIONARY:
					continue
				var pid := int((row as Dictionary).get("id", 0))
				var pname := str((row as Dictionary).get("name", ""))
				names[pid] = pname
				if _row_has_port(row, pname):
					ports[pid] = true
	var owners: Dictionary = {}
	if typeof(own_root) == TYPE_DICTIONARY:
		owners = (own_root as Dictionary).get("owners", {})
	var explicit_pids: Dictionary = {}
	var explicit_tags: Dictionary = {}
	if typeof(scenario_root) == TYPE_DICTIONARY:
		var countries: Variant = (scenario_root as Dictionary).get("countries", [])
		if countries is Array:
			for country in countries:
				if typeof(country) != TYPE_DICTIONARY:
					continue
				var tag := str((country as Dictionary).get("tag", ""))
				var cap := int((country as Dictionary).get("capital_province_id", 0))
				if not tag.is_empty():
					explicit_tags[tag] = true
				if cap > 0:
					explicit_pids[cap] = true
	var anchors := _scan_anchors()
	var best_extra: Dictionary = {}
	for key in city_rows.keys():
		var pid := int(key)
		var row: Dictionary = city_rows[key]
		var tier := int(row.get("tier", 1))
		var pop := 0.0
		if econ_rows.has(key):
			pop = float((econ_rows[key] as Dictionary).get("population", 0.0))
		elif econ_rows.has(pid):
			pop = float((econ_rows[pid] as Dictionary).get("population", 0.0))
		var pname := str(names.get(pid, ""))
		var kreis := pname.ends_with(", Kreisfreie Stadt")
		var port := bool(ports.get(pid, false)) or str(row.get("city_name", "")).to_lower().find("port") >= 0
		var score := _score_city(tier, pop, kreis, port)
		var display := str(row.get("city_name", pname))
		if kreis:
			display = pname.get_slice(",", 0).strip_edges()
		if display.is_empty():
			display = pname
		var world := Vector2.ZERO
		if anchors.has(pid):
			world = (anchors[pid] as Vector2) * _Canvas.THEATER_SCALE
		if world == Vector2.ZERO:
			continue
		var capital := bool(row.get("is_capital", false)) or bool(row.get("capital", false)) or explicit_pids.has(pid)
		var rec := {
			"pid": pid,
			"name": display,
			"tier": tier,
			"score": score,
			"capital": capital,
			"world": world,
			"enter": 0.0,
			"tag": str(owners.get(str(pid), owners.get(pid, ""))),
		}
		_candidates.append(rec)
		_by_pid[pid] = rec
		var tag := str(rec["tag"])
		if tag.is_empty() or explicit_tags.has(tag) or capital:
			continue
		if not best_extra.has(tag):
			best_extra[tag] = rec
		else:
			var prev: Dictionary = best_extra[tag]
			if _better_capital(rec, prev):
				best_extra[tag] = rec
	for tag in best_extra.keys():
		var rec: Dictionary = best_extra[tag]
		rec["capital"] = true
	for rec in _candidates:
		rec["enter"] = _enter_zoom(int(rec["tier"]), bool(rec["capital"]), float(rec["score"]))


func _better_capital(a: Dictionary, b: Dictionary) -> bool:
	if int(a["tier"]) != int(b["tier"]):
		return int(a["tier"]) > int(b["tier"])
	if absf(float(a["score"]) - float(b["score"])) > 0.05:
		return float(a["score"]) > float(b["score"])
	return int(a["pid"]) < int(b["pid"])


func _row_has_port(row: Dictionary, pname: String) -> bool:
	if pname.to_lower().find("port") >= 0:
		return true
	var feats: Variant = row.get("special_features", [])
	if feats is Array:
		for feat in feats:
			if str(feat).to_lower().find("port") >= 0:
				return true
	return false


func _scan_anchors() -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string(_GEO_PATH)
	if text.is_empty():
		return out
	var search := 0
	while true:
		var id_at := text.find("\"id\":", search)
		if id_at < 0:
			break
		var num_at := id_at + 5
		var pid := 0
		var k := num_at
		while k < text.length() and text[k] >= "0" and text[k] <= "9":
			pid = pid * 10 + int(text[k])
			k += 1
		var anchor_at := text.find("\"label_anchor\":[", id_at)
		var next_id := text.find("\"id\":", id_at + 5)
		if anchor_at < 0:
			break
		if next_id > 0 and anchor_at > next_id:
			search = next_id
			continue
		var x_at := anchor_at + 16
		var comma := text.find(",", x_at)
		var end_br := text.find("]", x_at)
		if comma < 0 or end_br < 0:
			search = anchor_at + 16
			continue
		var x := float(text.substr(x_at, comma - x_at))
		var y := float(text.substr(comma + 1, end_br - comma - 1))
		out[pid] = Vector2(x, y)
		search = end_br + 1
	return out


func _queue_paint() -> void:
	queue_redraw()
	if _dots != null:
		_dots.queue_redraw()


## Anchor dots sit above capital stars (z 40) and roads (z 21) so the
## cream mark stays on the city when those glyphs cover z 19.
class _DotMarks extends Node2D:
	var host: Node = null

	func _draw() -> void:
		if host == null or not host.has_method("placed"):
			return
		var zoom := 1.0
		var viewport := get_viewport()
		if viewport != null:
			var cam := viewport.get_camera_2d()
			if cam != null:
				zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
		var z := maxf(zoom, 0.04)
		var placed: Array = host.call("placed")
		for item in placed:
			var enter := float(item.get("enter", 0.0))
			var alpha := 1.0
			if host.has_method("fade_alpha"):
				alpha = float(host.call("fade_alpha", zoom, enter))
			if alpha < 0.04:
				continue
			var world: Vector2 = item.get("world", Vector2.ZERO)
			draw_circle(world, 4.0 / z, Color(1.0, 0.97, 0.88, alpha), true, -1.0, false)
