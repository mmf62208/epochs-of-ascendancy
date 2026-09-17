# scripts/map/LandBattleBubbleLayer.gd
## HOI-like land battle bubble (org plate only). NATO chips live on the Fight card.
## Director instances this from MapRenderer. Data only via set_battles.

class_name LandBattleBubbleLayer
extends Node2D

const Z_BUBBLE := 30
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
var _last_n: int = 0
var _nato_tex: Dictionary = {}


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
	set_process(not _battles.is_empty())
	queue_redraw()


func clear_battles() -> void:
	_battles.clear()
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


func _draw_side_pips(pos: Vector2, entry: Dictionary, attacker: bool, pulse: float) -> void:
	var letters: Array = entry.get("att_letters" if attacker else "def_letters", []) as Array
	var n := mini(letters.size(), 4)
	if n <= 0:
		return
	var pip := 12.0
	var gap := 2.0
	var y := pos.y + 12.0
	var inner_l := pos.x - 32.0
	var inner_r := pos.x + 32.0
	for i in n:
		var row: Dictionary = letters[i] if letters[i] is Dictionary else {"letter": str(letters[i]), "joining": false}
		var joining := bool(row.get("joining", false))
		var tex := _tex_for_letter(str(row.get("letter", "I")))
		var x: float
		if attacker:
			x = inner_l + float(i) * (pip + gap)
		else:
			x = inner_r - pip - float(i) * (pip + gap)
		var col := Color(0.55, 0.95, 0.62, 0.95 * pulse) if attacker else Color(0.95, 0.42, 0.32, 0.95 * pulse)
		if joining:
			col.a *= 0.42
		if tex != null:
			draw_texture_rect(tex, Rect2(x, y, pip, pip), false, col)
		else:
			draw_rect(Rect2(x + 1.0, y + 1.0, pip - 2.0, pip - 2.0), col, true)


func _stamp_letters(entry: Dictionary, attacker: bool) -> Array:
	var out: Array = []
	var raw_f: Variant = entry.get("att_fids" if attacker else "def_fids", [])
	var raw_p: Variant = entry.get("att_pending_fids" if attacker else "def_pending_fids", [])
	if raw_f is Array:
		for fid_v in raw_f:
			out.append({"letter": _letter_for_fid(str(fid_v)), "joining": false})
	if raw_p is Array:
		for fid_p in raw_p:
			out.append({"letter": _letter_for_fid(str(fid_p)), "joining": true})
	if out.is_empty():
		var n := maxi(int(entry.get("att_n" if attacker else "def_n", 1)), 1)
		for _i in mini(n, 4):
			out.append({"letter": "I", "joining": false})
	return out


func _letter_for_fid(fid: String) -> String:
	if fid.is_empty() or typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formation"):
		return "I"
	var f: Formation = LeaderManager.get_formation(fid)
	if f == null:
		return "I"
	var blob := ""
	if f.has_meta("visual_archetype"):
		blob = str(f.get_meta("visual_archetype"))
	if "design_id" in f:
		blob += " " + str(f.design_id)
	if "name" in f:
		blob += " " + str(f.name)
	var k := blob.to_lower()
	if "artillery" in k:
		return "G"
	if "panzer" in k or "armor" in k or "tank" in k:
		return "A"
	return "I"


func _tex_for_letter(letter: String) -> Texture2D:
	if _nato_tex.has(letter):
		return _nato_tex[letter] as Texture2D
	var stem := "infantry_32.png"
	if letter == "A" or letter == "H" or letter == "L":
		stem = "medium_tank_32.png"
	elif letter == "G" or letter == "R":
		stem = "artillery_32.png"
	var path := "res://assets/graphics/units/nato/ww2/" + stem
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_nato_tex[letter] = tex
	return tex


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
