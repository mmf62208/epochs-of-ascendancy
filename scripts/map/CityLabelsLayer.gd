class_name CityLabelsLayer
extends Node2D

## ATLAS-1 view-only city names. Candidates load once. Collision reruns when
## the zoom band, zoom (±0.03), or camera (~15% of the view) changes — not on
## idle frames. Labels stay next to their own dots (small screen-space shift);
## overlapping lower-priority names are culled. Same-city names collapse to one.

const _LOD := preload("res://scripts/map/MapZoomLOD.gd")
const _Canvas := preload("res://scripts/map/MapCanvasConfig.gd")

const CITY_Z := 19
const MAX_ON_SCREEN := 60
const MID_TIER2_SCORE_FLOOR := 400.0
const LABEL_SHIFT_PX := 22.0
const ZOOM_REBUILD := 0.03
const PAN_REBUILD_FRAC := 0.15
const DEDUPE_WORLD := 36.0
const COUNTER_HALF := Vector2(28.0, 32.0)
const FILL_COLOR := Color(0.08, 0.07, 0.05, 1.0)
const OUTLINE_COLOR := Color(1.0, 0.97, 0.88, 1.0)

const _CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const _ECON_PATH := "res://data/provinces_world_accurate/province_economy_layer.json"
const _BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const _OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const _GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const _SCENARIO_PATH := "res://data/scenarios/world_accurate.json"

const _ALIAS_FOLD := {
	"vienna": "wien",
	"munich": "munchen",
	"muenchen": "munchen",
	"cologne": "koln",
	"nuremberg": "nurnberg",
	"nurnberg": "nurnberg",
}

const _ALIAS_LOCAL := {
	"vienna": "Wien",
	"munich": "München",
	"muenchen": "München",
	"cologne": "Köln",
	"nuremberg": "Nürnberg",
	"nurnberg": "Nürnberg",
}

var rebuild_count: int = 0

var _candidates: Array = []
var _candidates_ready: bool = false
var _placed: Array = []
var _layout_ready: bool = false
var _last_band: int = -1
var _last_cam: Vector2 = Vector2(-1.0e9, -1.0e9)
var _last_vp: Vector2 = Vector2.ZERO
var _last_layout_zoom: float = -1.0
var _zoom: float = 1.0
var _cam: Vector2 = Vector2.ZERO
var _vp: Vector2 = Vector2(1920, 1080)
var _nation_override: Array = []
var _use_nation_override: bool = false
var _counter_override: Array = []
var _use_counter_override: bool = false
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
	var labels_changed := show != _show_labels
	_mode = m
	_show_labels = show
	if labels_changed:
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


func cluster_key_of(pid: int) -> String:
	ensure_candidates()
	if not _by_pid.has(pid):
		return ""
	return str((_by_pid[pid] as Dictionary).get("cluster", _cluster_key(display_name_of(pid))))


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


func last_layout_zoom() -> float:
	return _last_layout_zoom


func set_view(zoom: float, camera_world: Vector2, viewport: Vector2, nation_rects: Array = [], counter_rects: Array = []) -> void:
	_zoom = zoom
	_cam = camera_world
	_vp = viewport
	if _vp.x < 8.0 or _vp.y < 8.0:
		_vp = Vector2(1920, 1080)
	_nation_override = nation_rects
	_use_nation_override = true
	_counter_override = counter_rects
	_use_counter_override = true
	_layout_ready = false
	_resolve_layout()
	_queue_paint()


## Live hysteresis. Idle frames with the same camera/zoom do not rebuild.
func sync_view(zoom: float, camera_world: Vector2, viewport: Vector2, force: bool = false) -> void:
	var vp := viewport
	if vp.x < 8.0 or vp.y < 8.0:
		vp = Vector2(1920, 1080)
	if not force and not _should_rebuild(zoom, camera_world, vp):
		_zoom = zoom
		return
	_zoom = zoom
	_cam = camera_world
	_vp = vp
	_resolve_layout()
	_queue_paint()


func place_competing(cands: Array, zoom: float, cam: Vector2, vp: Vector2, nation_rects: Array, max_shift: float, obstacles: Array = []) -> Array:
	var list: Array = cands.duplicate(true)
	for c in list:
		var world: Vector2 = c.get("world", Vector2.ZERO)
		c["dist"] = world.distance_to(cam)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _priority_before(a, b)
	)
	var placed: Array = []
	var font := _font_or_null()
	var blockers: Array = []
	for n in nation_rects:
		blockers.append(n)
	for o in obstacles:
		blockers.append(o)
	for c in list:
		if not _in_band(c, zoom):
			continue
		var enter := float(c.get("enter", 0.0))
		var alpha := _LOD.city_label_fade_alpha(zoom, enter)
		if alpha < 0.04:
			continue
		var world: Vector2 = c.get("world", Vector2.ZERO)
		var anchor_s := (world - cam) * zoom + vp * 0.5
		if anchor_s.x < -120.0 or anchor_s.y < -80.0 or anchor_s.x > vp.x + 120.0 or anchor_s.y > vp.y + 80.0:
			continue
		var tier := int(c.get("tier", 1))
		var px := _LOD.city_label_font_px(tier)
		var text := str(c.get("name", ""))
		var size := _measure(font, text, px)
		var ascent := size.y * 0.78
		var base := Vector2(8.0, -2.0)
		if bool(c.get("capital", false)):
			base = Vector2(14.0, -2.0)
		var accepted := false
		var chosen := Rect2()
		var chosen_off := base
		for off_v in _slot_offsets(base, max_shift):
			var off: Vector2 = off_v as Vector2
			var baseline_s: Vector2 = anchor_s + off
			var rect := Rect2(baseline_s + Vector2(0.0, -ascent), size)
			if _rects_clear(rect, placed, blockers, vp):
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
			"ascent": ascent,
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
	var pos := cam.global_position
	if _should_rebuild(zoom, pos, vp_size):
		_zoom = zoom
		_cam = pos
		_vp = vp_size
		_use_nation_override = false
		_use_counter_override = false
		_resolve_layout()
		_queue_paint()
	elif absf(zoom - _zoom) > 0.001:
		_zoom = zoom
		_queue_paint()


func _should_rebuild(zoom: float, pos: Vector2, vp_size: Vector2) -> bool:
	if not _layout_ready:
		return true
	if not _show_labels:
		return false
	var band := _LOD.city_label_band_for_zoom(zoom)
	if band != _last_band:
		return true
	if absf(zoom - _last_layout_zoom) >= ZOOM_REBUILD:
		return true
	var z := maxf(zoom, 0.04)
	var pan_x := vp_size.x * PAN_REBUILD_FRAC / z
	var pan_y := vp_size.y * PAN_REBUILD_FRAC / z
	if absf(pos.x - _last_cam.x) > pan_x or absf(pos.y - _last_cam.y) > pan_y:
		return true
	if vp_size.distance_squared_to(_last_vp) > 4.0:
		return true
	return false


func _resolve_layout() -> void:
	ensure_candidates()
	if not _show_labels:
		if not _placed.is_empty():
			_placed = []
		_layout_ready = true
		_last_band = _LOD.city_label_band_for_zoom(_zoom)
		_last_layout_zoom = _zoom
		_last_cam = _cam
		_last_vp = _vp
		return
	_last_band = _LOD.city_label_band_for_zoom(_zoom)
	_last_layout_zoom = _zoom
	_last_cam = _cam
	_last_vp = _vp
	_layout_ready = true
	rebuild_count += 1
	var nations := _nation_rects_for_layout()
	var counters := _counter_rects_for_layout()
	_placed = place_competing(_candidates, _zoom, _cam, _vp, nations, LABEL_SHIFT_PX, counters)


func _nation_rects_for_layout() -> Array:
	if _use_nation_override:
		return _nation_override
	return _live_nation_rects()


func _counter_rects_for_layout() -> Array:
	if _use_counter_override:
		return _counter_override
	return _live_counter_rects()


func _live_nation_rects() -> Array:
	var parent_node := get_parent()
	if parent_node == null:
		return []
	var layer := parent_node.get_node_or_null("PoliticalLabelsLayer")
	if layer == null:
		return []
	var out: Array = []
	for child in layer.get_children():
		if not (child is Label):
			continue
		var lbl := child as Label
		if not lbl.visible:
			continue
		if not str(lbl.name).begins_with("NationLabel_"):
			continue
		var rect := _control_screen_rect(lbl)
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			out.append(rect)
	return out


func _live_counter_rects() -> Array:
	var parent_node := get_parent()
	if parent_node == null:
		return []
	var out: Array = []
	_collect_counter_rects(parent_node, out, 0)
	return out


func _collect_counter_rects(node: Node, out: Array, depth: int) -> void:
	if node == null or depth > 2:
		return
	if str(node.name).begins_with("DemoUnitIcon_") and node is Node2D:
		var icon := node as Node2D
		if icon.visible:
			out.append(_counter_screen_rect(icon))
	for child in node.get_children():
		_collect_counter_rects(child, out, depth + 1)


func _control_screen_rect(lbl: Control) -> Rect2:
	if lbl == null or not lbl.is_inside_tree():
		return Rect2()
	var xf := lbl.get_global_transform_with_canvas()
	var p0: Vector2 = xf * Vector2.ZERO
	var p1: Vector2 = xf * lbl.size
	var rect := Rect2(p0, p1 - p0).abs()
	return rect


func _counter_screen_rect(icon: Node2D) -> Rect2:
	var xf := icon.get_global_transform_with_canvas()
	var origin: Vector2 = xf * Vector2.ZERO
	var corner: Vector2 = xf * COUNTER_HALF
	var half := Vector2(absf(corner.x - origin.x), absf(corner.y - origin.y))
	if half.x < 18.0:
		half.x = 24.0
	if half.y < 18.0:
		half.y = 28.0
	return Rect2(origin - half, half * 2.0)


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
		var off: Vector2 = item.get("screen_offset", Vector2(8, -2))
		var world_text := world + off / z
		var px := maxi(int(item.get("font_px", 11)), 8)
		var world_px := maxi(int(round(float(px) / z)), 8)
		var outline_px := maxi(int(round(3.0 / z)), 1)
		var text := str(item.get("name", ""))
		draw_string_outline(font, world_text, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, world_px, outline_px, Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, alpha))
		draw_string(font, world_text, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, world_px, Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, alpha))


func _rects_clear(rect: Rect2, placed: Array, blockers: Array, vp: Vector2) -> bool:
	var view := Rect2(Vector2.ZERO, vp).grow(8.0)
	if not rect.intersects(view):
		return false
	for p in placed:
		var other: Rect2 = p.get("screen_rect", Rect2())
		if rect.intersects(other.grow(1.0)):
			return false
	for n in blockers:
		if n is Rect2 and rect.intersects((n as Rect2).grow(1.0)):
			return false
	return true


func _slot_offsets(base: Vector2, max_shift: float) -> Array:
	var out: Array = [base]
	if max_shift < 1.0:
		return out
	var radii: Array[float] = [8.0, 12.0, 16.0, 22.0]
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
	var t := clampf(1.0 - score / 600.0, 0.0, 1.0)
	return _LOD.CITY_LABEL_MID_MAX + t * 0.85


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
		var kreis := pname.ends_with(", Kreisfreie Stadt") or pname.ends_with(", Stadtkreis")
		var port := bool(ports.get(pid, false)) or str(row.get("city_name", "")).to_lower().find("port") >= 0
		var score := _score_city(tier, pop, kreis, port)
		var raw_name := str(row.get("city_name", pname))
		var display := _canonical_display(raw_name, pname, kreis)
		if display.is_empty():
			display = pname
		var world := Vector2.ZERO
		if anchors.has(pid):
			world = (anchors[pid] as Vector2) * _Canvas.THEATER_SCALE
		if world == Vector2.ZERO:
			continue
		var capital := bool(row.get("is_capital", false)) or bool(row.get("capital", false)) or explicit_pids.has(pid)
		var cluster := _cluster_key(raw_name)
		if cluster.is_empty():
			cluster = _cluster_key(display)
		var rec := {
			"pid": pid,
			"name": display,
			"pname": pname,
			"cluster": cluster,
			"local_core": _is_local_core(display, pname, cluster),
			"tier": tier,
			"score": score,
			"capital": capital,
			"world": world,
			"enter": 0.0,
			"tag": str(owners.get(str(pid), owners.get(pid, ""))),
		}
		_candidates.append(rec)
		_by_pid[pid] = rec
		var rec_tag := str(rec["tag"])
		if rec_tag.is_empty() or explicit_tags.has(rec_tag) or capital:
			continue
		if not best_extra.has(rec_tag):
			best_extra[rec_tag] = rec
		else:
			var prev: Dictionary = best_extra[rec_tag]
			if _better_capital(rec, prev):
				best_extra[rec_tag] = rec
	for extra_tag in best_extra.keys():
		var extra_rec: Dictionary = best_extra[extra_tag]
		extra_rec["capital"] = true
	_dedupe_same_city()
	_drop_district_satellites()
	for rec in _candidates:
		rec["enter"] = _enter_zoom(int(rec["tier"]), bool(rec["capital"]), float(rec["score"]))


func _canonical_display(city_name: String, pname: String, kreis: bool) -> String:
	if kreis:
		var core := pname.get_slice(",", 0).strip_edges()
		if not core.is_empty():
			return core
	var display := city_name.strip_edges()
	if display.is_empty():
		display = pname.strip_edges()
	var folded := _fold_name(display)
	if _ALIAS_LOCAL.has(folded):
		var local := str(_ALIAS_LOCAL[folded])
		var pn := pname.strip_edges()
		var pn_fold := _fold_name(pn.get_slice(",", 0).get_slice("/", 0))
		var local_fold := _fold_name(local)
		if pn_fold == local_fold or pn == local or pn.begins_with(local + ","):
			return local
		if not pn.is_empty() and pn_fold != local_fold:
			if pn.find("Landkreis") >= 0 or pn.find("Umland") >= 0 or pn.begins_with("Greater "):
				return pn
			return local
		return local
	return display


func _is_local_core(display: String, pname: String, cluster: String) -> bool:
	var pn := _cluster_key(pname.get_slice(",", 0).get_slice("/", 0))
	if pn == cluster:
		return true
	return _cluster_key(display) == cluster and pname.find("Landkreis") < 0 and pname.find("Umland") < 0 and not pname.begins_with("Greater ")


func _cluster_key(name: String) -> String:
	var folded := _fold_name(name.get_slice(",", 0).get_slice("/", 0))
	if _ALIAS_FOLD.has(folded):
		return str(_ALIAS_FOLD[folded])
	return folded


func _fold_name(s: String) -> String:
	var t := s.strip_edges().to_lower()
	t = t.replace("ü", "u").replace("ö", "o").replace("ä", "a").replace("ß", "ss")
	t = t.replace("é", "e").replace("è", "e").replace("ê", "e")
	t = t.replace("á", "a").replace("à", "a")
	t = t.replace("ó", "o").replace("ò", "o")
	t = t.replace("í", "i").replace("ì", "i")
	t = t.replace("ú", "u")
	t = t.replace("ñ", "n").replace("ç", "c")
	return t


func _dedupe_same_city() -> void:
	var groups: Dictionary = {}
	for rec in _candidates:
		var key := str(rec.get("cluster", ""))
		if key.is_empty():
			continue
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(rec)
	var drop: Dictionary = {}
	for key in groups.keys():
		var recs: Array = groups[key]
		if recs.size() < 2:
			continue
		var kept: Array = []
		recs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _better_keep(a, b)
		)
		for rec_v in recs:
			var rec: Dictionary = rec_v
			var world: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
			var pid := int(rec.get("pid", 0))
			var absorbed := false
			for other_v in kept:
				var other: Dictionary = other_v
				var ow: Vector2 = other.get("world", Vector2.ZERO) as Vector2
				if world.distance_to(ow) <= DEDUPE_WORLD:
					absorbed = true
					drop[pid] = true
					break
			if not absorbed:
				kept.append(rec)
	if drop.is_empty():
		return
	var kept_list: Array = []
	for rec in _candidates:
		var pid := int(rec.get("pid", 0))
		if drop.has(pid):
			_by_pid.erase(pid)
			continue
		kept_list.append(rec)
		_by_pid[pid] = rec
	_candidates = kept_list


func _is_district(rec: Dictionary) -> bool:
	var pn := str(rec.get("pname", ""))
	if pn.find("Landkreis") >= 0 or pn.find("Umland") >= 0:
		return true
	if pn.begins_with("Greater "):
		return true
	return false


func _drop_district_satellites() -> void:
	var cores: Array = []
	for rec in _candidates:
		if not _is_district(rec):
			cores.append(rec)
	if cores.is_empty():
		return
	var drop: Dictionary = {}
	for rec in _candidates:
		if not _is_district(rec):
			continue
		var world: Vector2 = rec.get("world", Vector2.ZERO)
		for core in cores:
			var ow: Vector2 = core.get("world", Vector2.ZERO)
			if world.distance_to(ow) <= DEDUPE_WORLD:
				drop[int(rec.get("pid", 0))] = true
				break
	if drop.is_empty():
		return
	var kept_list: Array = []
	for rec in _candidates:
		var pid := int(rec.get("pid", 0))
		if drop.has(pid):
			_by_pid.erase(pid)
			continue
		kept_list.append(rec)
		_by_pid[pid] = rec
	_candidates = kept_list


func _better_keep(a: Dictionary, b: Dictionary) -> bool:
	var ac := bool(a.get("capital", false))
	var bc := bool(b.get("capital", false))
	if ac != bc:
		return ac
	var al := bool(a.get("local_core", false))
	var bl := bool(b.get("local_core", false))
	if al != bl:
		return al
	var at := int(a.get("tier", 0))
	var bt := int(b.get("tier", 0))
	if at != bt:
		return at > bt
	var ascore := float(a.get("score", 0.0))
	var bscore := float(b.get("score", 0.0))
	if absf(ascore - bscore) > 0.05:
		return ascore > bscore
	return int(a.get("pid", 0)) < int(b.get("pid", 0))


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
