# scripts/map/OrderIntentLayer.gd
## Gold march path + red attack arrows. Only the given points — never walks 3520.
extends Node2D

const Z_INTENT := 26
const MARCH_COL := Color(1.0, 0.82, 0.22, 0.92)
const ATTACK_COL := Color(0.92, 0.18, 0.16, 0.95)
const ATTACK_GLOW := Color(0.95, 0.28, 0.18, 0.28)
const RETREAT_COL := Color(0.94, 0.94, 0.96, 0.92)
const RETREAT_GLOW := Color(0.85, 0.85, 0.90, 0.28)
const MARCH_WIDTH := 3.6
const ATTACK_WIDTH := 4.4
const RETREAT_WIDTH := 3.8
const HEAD_LEN := 16.0
const HEAD_HALF := 9.0
const HIT_R := 22.0

var _march: PackedVector2Array = PackedVector2Array()
var _attacks: Array = []
var _phase: float = 0.0


func _ready() -> void:
	z_index = Z_INTENT
	z_as_relative = false
	set_process(false)


func set_march_points(pts: PackedVector2Array) -> void:
	_march = pts
	_arm_process()
	queue_redraw()


func clear_march() -> void:
	_march = PackedVector2Array()
	_arm_process()
	queue_redraw()


func set_attacks(rows: Array) -> void:
	_attacks.clear()
	for raw in rows:
		if raw is Dictionary:
			_attacks.append(raw)
	_arm_process()
	queue_redraw()


func pick_attack_at(world: Vector2, hit_r: float = HIT_R) -> Dictionary:
	var best: Dictionary = {}
	var best_d := hit_r
	for raw in _attacks:
		if not (raw is Dictionary):
			continue
		var a: Vector2 = raw.get("from", Vector2.ZERO)
		var b: Vector2 = raw.get("to", Vector2.ZERO)
		if a == Vector2.ZERO or b == Vector2.ZERO:
			continue
		if bool(raw.get("occupy", false)) or bool(raw.get("retreat", false)):
			continue
		# Dim arrows belong to another stack member — do not steal that unit's hex click.
		if bool(raw.get("dim", false)):
			continue
		var d := _dist_to_segment(world, a, b)
		if d <= best_d:
			best_d = d
			best = raw
	return best


func _arm_process() -> void:
	set_process(not _attacks.is_empty())


func _process(delta: float) -> void:
	if _attacks.is_empty():
		set_process(false)
		return
	_phase = fmod(_phase + delta * 2.4, TAU)
	if Engine.get_process_frames() % 8 == 0:
		queue_redraw()


func _draw() -> void:
	if _march.size() >= 2:
		draw_polyline(_march, MARCH_COL, MARCH_WIDTH, true)
		_draw_head(_march[_march.size() - 2], _march[_march.size() - 1], MARCH_COL)
	var pulse := 0.78 + 0.22 * (0.5 + 0.5 * sin(_phase))
	for raw in _attacks:
		if not (raw is Dictionary):
			continue
		var a: Vector2 = raw.get("from", Vector2.ZERO)
		var b: Vector2 = raw.get("to", Vector2.ZERO)
		if a == Vector2.ZERO or b == Vector2.ZERO or a.distance_squared_to(b) < 4.0:
			continue
		var dim := bool(raw.get("dim", false))
		var a_mul := 0.12 if dim else 1.0
		var w_mul := 0.40 if dim else 1.0
		if bool(raw.get("retreat", false)):
			var rc := Color(RETREAT_COL.r, RETREAT_COL.g, RETREAT_COL.b, RETREAT_COL.a * pulse * a_mul)
			draw_line(a, b, RETREAT_GLOW, (RETREAT_WIDTH + 5.0) * w_mul, true)
			draw_line(a, b, rc, RETREAT_WIDTH * w_mul, true)
			_draw_head(a, b, rc)
			continue
		var col := Color(ATTACK_COL.r, ATTACK_COL.g, ATTACK_COL.b, ATTACK_COL.a * pulse * a_mul)
		if bool(raw.get("planned", false)):
			col = Color(0.95, 0.55, 0.18, 0.72 * pulse * a_mul)
		draw_line(a, b, ATTACK_GLOW, (ATTACK_WIDTH + 6.0) * w_mul, true)
		draw_line(a, b, col, ATTACK_WIDTH * w_mul, true)
		_draw_head(a, b, col)


func _draw_head(from_pt: Vector2, to_pt: Vector2, col: Color) -> void:
	var delta: Vector2 = to_pt - from_pt
	if delta.length_squared() < 4.0:
		return
	var dir := delta.normalized()
	var n := Vector2(-dir.y, dir.x)
	var tip := to_pt
	var base := to_pt - dir * HEAD_LEN
	var poly := PackedVector2Array([tip, base + n * HEAD_HALF, base - n * HEAD_HALF])
	draw_colored_polygon(poly, col)


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
