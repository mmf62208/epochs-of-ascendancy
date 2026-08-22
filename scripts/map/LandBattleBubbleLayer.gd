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
		var lean := str(entry.get("lean", "even")).strip_edges().to_lower()
		_draw_org_plate(pos, att_org, def_org, pulse, lean)
		_last_n += 1


func _draw_org_plate(pos: Vector2, att_org: float, def_org: float, pulse: float, lean: String) -> void:
	var w := 54.0
	var h := 20.0
	var plate := Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h)
	var plate_col := Color(COL_PLATE.r, COL_PLATE.g, COL_PLATE.b, COL_PLATE.a * pulse)
	draw_rect(plate, plate_col, true)
	var edge := COL_EDGE
	if lean == "attacker":
		edge = Color(0.28, 0.72, 0.40, 0.95)
	elif lean == "defender":
		edge = Color(0.90, 0.38, 0.24, 0.95)
	draw_rect(plate, edge, false, 1.0)
	var bar_w := w - 6.0
	var bar_h := 3.5
	var ax := pos.x - bar_w * 0.5
	var ay := pos.y - 5.0
	draw_rect(Rect2(ax, ay, bar_w, bar_h), COL_BAR_BG, true)
	# OrgBar: attacker org (green)
	var org_bar_w := bar_w * att_org
	if org_bar_w > 0.5:
		draw_rect(Rect2(ax, ay, org_bar_w, bar_h), COL_ATT, true)
	var dy := pos.y + 1.5
	draw_rect(Rect2(ax, dy, bar_w, bar_h), COL_BAR_BG, true)
	var def_w := bar_w * def_org
	if def_w > 0.5:
		var def_col := COL_DEF if def_org > 0.35 else COL_DEF_AMBER
		draw_rect(Rect2(ax, dy, def_w, bar_h), def_col, true)
	# Lean pip (who the fight is tilting toward).
	var pip := Color(0.70, 0.72, 0.74, 0.85)
	if lean == "attacker":
		pip = COL_ATT
	elif lean == "defender":
		pip = COL_DEF
	draw_circle(Vector2(pos.x - w * 0.5 + 3.0, pos.y - h * 0.5 + 3.0), 1.6, pip)


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
		var day_s := "Day %d/%d" % [day_n, est] if est > 0 else "Day %d" % day_n
		if att_n > 0 and def_n > 0:
			lb.text = "%s · %dv%d" % [day_s, att_n, def_n]
		else:
			lb.text = day_s
		# Cheap CAS / planning chips — text only, no extra nodes.
		if float(entry.get("cas_att", 0.0)) > 0.0 or float(entry.get("cas_def", 0.0)) > 0.0:
			lb.text += " CAS"
		if bool(entry.get("planning_used", false)):
			lb.text += " P"
		if bool(entry.get("enc_att", false)) or bool(entry.get("enc_def", false)) \
				or bool(entry.get("pocket_att", false)) or bool(entry.get("pocket_def", false)):
			lb.text += " ENC"
		lb.position = pos + Vector2(-22.0, -22.0)
		lb.visible = true
