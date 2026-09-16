# scripts/map/LandBattleBubbleLayer.gd
## HOI-like land battle bubble (org plate + day chip). No 3D soldiers.
## Director instances this from MapRenderer. Data only via set_battles.

class_name LandBattleBubbleLayer
extends Node2D

const Z_BUBBLE := 25
const MAX_BUBBLES := 24
const PULSE_EVERY_FRAMES := 8
const PULSE_SPEED := 2.8

const COL_PLATE := Color(0.06, 0.07, 0.10, 0.90)
const COL_EDGE := Color(0.22, 0.24, 0.28, 0.92)
const COL_ATT := Color(0.28, 0.82, 0.42, 0.95)
const COL_DEF := Color(0.90, 0.30, 0.22, 0.95)
const COL_DEF_AMBER := Color(0.95, 0.62, 0.22, 0.95)
const COL_BAR_BG := Color(0.12, 0.13, 0.16, 0.92)
const COL_LIKELY := Color(0.32, 0.84, 0.46, 0.95)
const COL_TIGHT := Color(0.95, 0.78, 0.22, 0.95)
const COL_BAD := Color(0.90, 0.32, 0.22, 0.95)

var _centroids: Dictionary = {}
var _battles: Array = []
var _phase: float = 0.0
var _day_labels: Array[Label] = []
var _last_n: int = 0


func setup(centroids: Dictionary) -> void:
	_centroids = centroids
	queue_redraw()


func set_battles(battles: Array) -> void:
	_battles.clear()
	if battles != null:
		for entry in battles:
			if _battles.size() >= MAX_BUBBLES:
				break
			if entry is Dictionary:
				_battles.append(entry)
	_sync_day_labels()
	set_process(not _battles.is_empty())
	queue_redraw()


func clear_battles() -> void:
	_battles.clear()
	_sync_day_labels()
	set_process(false)
	queue_redraw()


func get_draw_stats() -> Dictionary:
	return {"bubble_n": _last_n, "cap": MAX_BUBBLES}


func _ready() -> void:
	z_index = Z_BUBBLE
	set_process(false)


func _process(delta: float) -> void:
	if _battles.is_empty():
		set_process(false)
		return
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_paused") and bool(TimeManager.is_paused()):
		return
	_phase = fmod(_phase + delta * PULSE_SPEED, TAU)
	if Engine.get_process_frames() % PULSE_EVERY_FRAMES == 0:
		queue_redraw()


func _draw() -> void:
	_last_n = 0
	var pulse := 0.82 + 0.18 * (0.5 + 0.5 * sin(_phase))
	for entry in _battles:
		if not (entry is Dictionary):
			continue
		var pos := _bubble_pos(entry)
		if not pos.is_finite():
			continue
		var att_org := clampf(float(entry.get("att_org", 0.0)), 0.0, 1.0)
		var def_org := clampf(float(entry.get("def_org", 0.0)), 0.0, 1.0)
		var att_p := maxf(0.0, float(entry.get("att_power", 0.0)))
		var def_p := maxf(0.0, float(entry.get("def_power", 0.0)))
		var band := "tight"
		if att_p > def_p * 1.15:
			band = "likely"
		elif def_p > att_p * 1.15:
			band = "bad"
		var denom := att_org + def_org
		var progress := 0.5 if denom <= 0.001 else att_org / denom
		_draw_org_plate(pos, progress, band, pulse)
		_last_n += 1


func _draw_org_plate(pos: Vector2, progress: float, band: String, pulse: float) -> void:
	var w := 62.0
	var h := 16.0
	var plate := Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h)
	var plate_col := Color(COL_PLATE.r, COL_PLATE.g, COL_PLATE.b, COL_PLATE.a * pulse)
	draw_rect(plate, plate_col, true)
	var edge := COL_TIGHT
	var fill := COL_TIGHT
	if band == "likely":
		edge = COL_LIKELY
		fill = COL_LIKELY
	elif band == "bad":
		edge = COL_BAD
		fill = COL_BAD
	draw_rect(plate, edge, false, 1.2)
	var bar_w := w - 8.0
	var bar_h := 6.0
	var ax := pos.x - bar_w * 0.5
	var ay := pos.y - bar_h * 0.5
	draw_rect(Rect2(ax, ay, bar_w, bar_h), COL_BAR_BG, true)
	var fw := bar_w * clampf(progress, 0.0, 1.0)
	if fw > 0.5:
		draw_rect(Rect2(ax, ay, fw, bar_h), fill, true)


func _bubble_pos(entry: Dictionary) -> Vector2:
	var to_id := int(entry.get("to_id", -1))
	var from_id := int(entry.get("from_id", -1))
	var to_c := _centroid_of(to_id)
	var from_c := _centroid_of(from_id)
	if to_c.is_finite() and from_c.is_finite():
		return from_c.lerp(to_c, 0.5)
	if to_c.is_finite():
		return to_c
	return from_c


func _centroid_of(pid: int) -> Vector2:
	if pid < 0:
		return Vector2(INF, INF)
	# TypedDictionary[int] errors on has(String). Always coerce to int first.
	var want := int(pid)
	if _centroids.has(want):
		return _as_vec(_centroids[want])
	# Untyped maps may store string keys — walk keys; never has(String) on a typed int dict.
	for k in _centroids.keys():
		if int(k) == want:
			return _as_vec(_centroids[k])
	return Vector2(INF, INF)


func _as_vec(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if v is Dictionary:
		return Vector2(float(v.get("x", INF)), float(v.get("y", INF)))
	return Vector2(INF, INF)


func _sync_day_labels() -> void:
	while _day_labels.size() < _battles.size():
		var lb := Label.new()
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.add_theme_font_size_override("font_size", 9)
		lb.add_theme_color_override("font_color", Color(0.92, 0.94, 0.90, 0.95))
		lb.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.92))
		lb.add_theme_constant_override("outline_size", 3)
		lb.z_index = Z_BUBBLE + 1
		add_child(lb)
		_day_labels.append(lb)
	for i in range(_day_labels.size()):
		var lb: Label = _day_labels[i]
		if i >= _battles.size():
			lb.visible = false
			continue
		var entry: Dictionary = _battles[i]
		var pos := _bubble_pos(entry)
		if not pos.is_finite():
			lb.visible = false
			continue
		var day_n := int(entry.get("days_elapsed", 0))
		var est := int(entry.get("est_days", 0))
		var att_n := int(entry.get("att_n", 0))
		var def_n := int(entry.get("def_n", 0))
		var att_p := maxf(0.0, float(entry.get("att_power", 0.0)))
		var def_p := maxf(0.0, float(entry.get("def_power", 0.0)))
		var word := "TIGHT"
		if att_p > def_p * 1.15:
			word = "LIKELY"
		elif def_p > att_p * 1.15:
			word = "BAD"
		var join_n := 0
		var pend: Variant = entry.get("att_pending_fids", [])
		if pend is Array:
			join_n = (pend as Array).size()
		var vs := "%dv%d" % [att_n, def_n] if att_n > 0 and def_n > 0 else ""
		if join_n > 0:
			vs = ("%s +%d" % [vs, join_n]).strip_edges()
		var day_s := "D%d/%d" % [day_n, est] if est > 0 else "D%d" % day_n
		if vs.is_empty():
			lb.text = "%s · %s" % [word, day_s]
		else:
			lb.text = "%s · %s · %s" % [word, vs, day_s]
		# Cheap CAS / planning chips — text only, no extra nodes.
		if float(entry.get("cas_att", 0.0)) > 0.0 or float(entry.get("cas_def", 0.0)) > 0.0:
			lb.text += " CAS"
		if bool(entry.get("planning_used", false)):
			lb.text += " P"
		if bool(entry.get("enc_att", false)) or bool(entry.get("enc_def", false)) \
				or bool(entry.get("pocket_att", false)) or bool(entry.get("pocket_def", false)):
			lb.text += " ENC"
		lb.position = pos + Vector2(-40.0, 10.0)
		lb.visible = true
