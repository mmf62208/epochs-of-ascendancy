# scripts/map/BattleIndicatorOverlayLayer.gd
## Phase 2: battle / assault indicators on map (combat phase ribbon integration).
## Contested fronts + recent assault outcome markers; cheap and budgeted.

class_name BattleIndicatorOverlayLayer
extends Node2D

@export var enabled: bool = true
@export var show_front_clash: bool = true
@export var show_assault_markers: bool = true
@export var max_markers: int = 36
@export var pulse_speed: float = 3.2

var _centroids: Dictionary = {}
var _provinces: Dictionary = {}
var _map_container: Node2D
var _phase: float = 0.0
var _last_marker_n: int = 0
## Optional external assault trail: [{pid, phase, strength}]
var _assault_trail: Array = []
## Cached province_ids with stationed formations — rebuilt sparingly (not every draw).
var _stationed_pids: Dictionary = {}
var _stationed_cache_frame: int = -999999
const STATIONED_CACHE_FRAMES := 120
## world_full: avoid full-board adjacency walk every few frames (F5 freeze).
const LARGE_BOARD_PROVINCES := 800
const REDRAW_EVERY_SMALL := 4
const REDRAW_EVERY_LARGE := 12


func setup_with_map(map_container: Node2D, centroids: Dictionary, provinces: Dictionary) -> void:
	_map_container = map_container
	_centroids = centroids
	_provinces = provinces
	_stationed_cache_frame = -999999
	queue_redraw()


func set_assault_trail(trail: Array) -> void:
	_assault_trail = trail
	queue_redraw()


func push_assault_marker(province_id: int, phase: String = "engage", strength: float = 0.7) -> void:
	_assault_trail.append({
		"pid": province_id,
		"phase": phase,
		"strength": strength,
		"t": Time.get_ticks_msec(),
	})
	if _assault_trail.size() > max_markers:
		_assault_trail = _assault_trail.slice(_assault_trail.size() - max_markers)
	queue_redraw()


func _ready() -> void:
	z_index = 5
	set_process(true)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_signal("province_data_changed"):
		if not MapManager.province_data_changed.is_connected(_on_data):
			MapManager.province_data_changed.connect(_on_data)


func _on_data(_pid: int, what: String) -> void:
	if what in ["owner", "controller", "all", "combat"]:
		_stationed_cache_frame = -999999
		queue_redraw()


func _process(delta: float) -> void:
	if not enabled:
		return
	# Pause: no pulse redraws — keeps map pan/hover responsive during playtest pause.
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_paused") and bool(TimeManager.is_paused()):
		return
	_phase = fmod(_phase + delta * pulse_speed, TAU)
	var every := REDRAW_EVERY_LARGE if _board_province_count() >= LARGE_BOARD_PROVINCES else REDRAW_EVERY_SMALL
	if Engine.get_process_frames() % every == 0:
		queue_redraw()


func _board_province_count() -> int:
	if not _provinces.is_empty():
		return _provinces.size()
	if not _centroids.is_empty():
		return _centroids.size()
	return 0


func refresh() -> void:
	_stationed_cache_frame = -999999
	queue_redraw()


func get_draw_stats() -> Dictionary:
	return {"marker_n": _last_marker_n, "enabled": enabled, "trail_n": _assault_trail.size()}


func _draw() -> void:
	_last_marker_n = 0
	if not enabled:
		return
	if show_front_clash:
		_draw_fronts()
	if show_assault_markers:
		_draw_assault_trail()
		_draw_contested_phase_markers()


func _ensure_stationed_cache() -> void:
	var frame := Engine.get_process_frames()
	if frame - _stationed_cache_frame < STATIONED_CACHE_FRAMES and not _stationed_pids.is_empty():
		return
	_stationed_cache_frame = frame
	_stationed_pids.clear()
	if typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
		for fid_v in LeaderManager.formations.keys():
			var f: Variant = LeaderManager.formations[fid_v]
			if f == null or not (f is Object):
				continue
			var fo: Object = f as Object
			if "stationed_province_id" in fo:
				var sid := int(fo.stationed_province_id)
				if sid >= 0:
					_stationed_pids[sid] = true
	if typeof(SupplyManager) != TYPE_NIL and "division_deployments" in SupplyManager:
		for fid2 in SupplyManager.division_deployments.keys():
			var dep: Dictionary = SupplyManager.division_deployments[fid2] as Dictionary
			var pid2 := int(dep.get("province_id", -1))
			if pid2 >= 0:
				_stationed_pids[pid2] = true


func _draw_fronts() -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_adjacent_provinces"):
		return
	_ensure_stationed_cache()
	var drawn: Dictionary = {}
	var n := 0
	var src: Dictionary = _provinces
	if src.is_empty() and MapManager.has_method("get_all_provinces"):
		src = MapManager.get_all_provinces()
	# Prefer scanning provinces that have forces or are already contested — not full world_full.
	var candidates: Array = []
	if not _stationed_pids.is_empty():
		for pid_s in _stationed_pids.keys():
			candidates.append(int(pid_s))
	# Contested controllers (cheap pass only when board is large)
	if _board_province_count() < LARGE_BOARD_PROVINCES or candidates.is_empty():
		for pid_v in src.keys():
			var a0 := int(pid_v)
			var pa0: Province = src.get(a0) as Province
			if pa0 == null:
				continue
			if pa0.controller_tag != pa0.owner_tag and not pa0.owner_tag.is_empty():
				candidates.append(a0)
	if candidates.is_empty():
		# Nothing to clash over — skip O(board) adjacency walk
		return
	for a in candidates:
		if n >= max_markers:
			break
		var pa: Province = src.get(a) as Province
		if pa == null and MapManager.has_method("get_province"):
			pa = MapManager.get_province(a)
		if pa == null or pa.owner_tag.is_empty():
			continue
		for nb in MapManager.get_adjacent_provinces(a):
			var b := int(nb)
			if b <= a:
				continue
			var key := "%d_%d" % [a, b]
			if drawn.has(key):
				continue
			var pb: Province = src.get(b) as Province
			if pb == null and MapManager.has_method("get_province"):
				pb = MapManager.get_province(b)
			if pb == null or pb.owner_tag.is_empty() or pa.owner_tag == pb.owner_tag:
				continue
			var contested := (pa.controller_tag != pa.owner_tag) or (pb.controller_tag != pb.owner_tag)
			if not contested and not _has_stationed_hint(a) and not _has_stationed_hint(b):
				continue
			drawn[key] = true
			var ca: Vector2 = _centroids.get(a, Vector2.ZERO)
			var cb: Vector2 = _centroids.get(b, Vector2.ZERO)
			if ca == Vector2.ZERO or cb == Vector2.ZERO:
				continue
			var mid := ca.lerp(cb, 0.5)
			var pulse := 0.55 + 0.35 * (0.5 + 0.5 * sin(_phase + float(a) * 0.1))
			draw_line(ca, cb, Color(1.0, 0.25, 0.2, 0.35 * pulse), 2.0, true)
			_draw_clash_glyph(mid, pulse)
			_last_marker_n += 1
			n += 1


func _has_stationed_hint(pid: int) -> bool:
	if _stationed_pids.has(pid):
		return true
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_formations_in_province"):
		var f = MapManager.get_formations_in_province(pid)
		return f is Array and not (f as Array).is_empty()
	return false


func _draw_clash_glyph(pos: Vector2, pulse: float) -> void:
	var r := 5.0 + 2.0 * pulse
	draw_circle(pos, r, Color(1.0, 0.35, 0.25, 0.35 * pulse))
	# Crossed swords simplified as X
	var s := 6.0 * pulse
	draw_line(pos + Vector2(-s, -s), pos + Vector2(s, s), Color(1.0, 0.85, 0.4, 0.85), 1.5, true)
	draw_line(pos + Vector2(s, -s), pos + Vector2(-s, s), Color(1.0, 0.85, 0.4, 0.85), 1.5, true)


func _draw_assault_trail() -> void:
	var now := Time.get_ticks_msec()
	for entry in _assault_trail:
		if not (entry is Dictionary):
			continue
		var pid := int(entry.get("pid", -1))
		if pid < 0 or not _centroids.has(pid):
			continue
		var age_ms := now - int(entry.get("t", now))
		if age_ms > 45000:
			continue
		var fade := clampf(1.0 - float(age_ms) / 45000.0, 0.15, 1.0)
		var phase := str(entry.get("phase", "engage"))
		var c: Vector2 = _centroids[pid]
		var col := Color(1.0, 0.55, 0.2, 0.7 * fade)
		match phase:
			"approach":
				col = Color(0.95, 0.85, 0.35, 0.65 * fade)
			"disengage":
				col = Color(0.55, 0.75, 0.95, 0.6 * fade)
			_:
				col = Color(1.0, 0.4, 0.25, 0.75 * fade)
		draw_arc(c, 14.0, 0.0, TAU, 20, col, 2.0, true)
		# Phase pip (approach=1, engage=2, disengage=3)
		var pip_n := 2
		if phase.begins_with("approach"):
			pip_n = 1
		elif phase.begins_with("disengage"):
			pip_n = 3
		for i in range(pip_n):
			draw_circle(c + Vector2(-6 + i * 6, -16), 2.2, col)
		_last_marker_n += 1


func _draw_contested_phase_markers() -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_contested_provinces"):
		return
	var contested: Dictionary = MapManager.get_contested_provinces()
	var n := 0
	for pid_v in contested.keys():
		if n >= max_markers / 2:
			break
		var pid := int(pid_v)
		if not _centroids.has(pid):
			continue
		var c: Vector2 = _centroids[pid]
		var pulse := 0.5 + 0.5 * sin(_phase + float(pid) * 0.17)
		draw_arc(c, 11.0 + 2.0 * pulse, 0.0, TAU, 18, Color(1.0, 0.3, 0.25, 0.4 + 0.3 * pulse), 1.5, true)
		# Phase ribbon stub: three ticks = approach/engage/disengage
		for i in range(3):
			var ang := -PI * 0.5 + float(i) * 0.45
			var p := c + Vector2(cos(ang), sin(ang)) * (18.0 + pulse)
			var tick_col := Color(0.95, 0.8, 0.3, 0.7) if i == 1 else Color(0.7, 0.7, 0.75, 0.45)
			draw_circle(p, 2.2, tick_col)
		_last_marker_n += 1
		n += 1
