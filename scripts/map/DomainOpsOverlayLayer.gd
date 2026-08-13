# scripts/map/DomainOpsOverlayLayer.gd
## Phase 2: naval/air depth visuals — task group icons, sortie arrows, carrier support stubs.

class_name DomainOpsOverlayLayer
extends Node2D

@export var enabled: bool = true
@export var show_naval: bool = true
@export var show_air: bool = true
@export var max_icons: int = 40
@export var anim_speed: float = 0.4

var _centroids: Dictionary = {}
var _provinces: Dictionary = {}
var _phase: float = 0.0
var _last_naval_n: int = 0
var _last_air_n: int = 0
## Cached anchor lists so we do not walk all world_full centroids every redraw.
var _naval_anchors: Array = []
var _air_bases: Array = []
var _anchor_cache_frame: int = -999999
const ANCHOR_CACHE_FRAMES := 180
const LARGE_BOARD := 800


func setup(centroids: Dictionary, provinces: Dictionary = {}) -> void:
	_centroids = centroids
	_provinces = provinces
	_anchor_cache_frame = -999999
	queue_redraw()


func _ready() -> void:
	z_index = 6
	set_process(true)


func _process(delta: float) -> void:
	if not enabled:
		return
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_paused") and bool(TimeManager.is_paused()):
		return
	_phase = fmod(_phase + delta * anim_speed, 1.0)
	# Large boards: redraw less often — full centroid walks froze F5 after markers.
	var every := 12 if _centroids.size() >= LARGE_BOARD else 5
	if Engine.get_process_frames() % every == 0:
		queue_redraw()


func refresh() -> void:
	queue_redraw()


func get_draw_stats() -> Dictionary:
	return {"naval_n": _last_naval_n, "air_n": _last_air_n, "enabled": enabled}


func _draw() -> void:
	_last_naval_n = 0
	_last_air_n = 0
	if not enabled:
		return
	_ensure_anchor_cache()
	if show_naval:
		_draw_naval_task_groups()
	if show_air:
		_draw_air_sorties()


func _ensure_anchor_cache() -> void:
	var frame := Engine.get_process_frames()
	if frame - _anchor_cache_frame < ANCHOR_CACHE_FRAMES and (not _naval_anchors.is_empty() or not _air_bases.is_empty()):
		return
	_anchor_cache_frame = frame
	_naval_anchors.clear()
	_air_bases.clear()
	var naval_cap := maxi(1, max_icons / 2)
	var air_cap := maxi(1, max_icons / 2)
	for pid_v in _centroids.keys():
		var pid := int(pid_v)
		var p: Province = null
		if _provinces.has(pid):
			p = _provinces[pid] as Province
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			p = MapManager.get_province(pid)
		if _naval_anchors.size() < naval_cap:
			var is_naval := false
			if p != null:
				var has_port := false
				var terrain := ""
				if "has_port" in p:
					has_port = bool(p.has_port)
				if "terrain" in p:
					terrain = str(p.terrain)
				if has_port or terrain.contains("coast") or terrain.contains("port"):
					is_naval = true
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
				if MapManager.has_strategic_chokepoint(pid):
					is_naval = true
			if is_naval:
				var choke := typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint") and MapManager.has_strategic_chokepoint(pid)
				if pid % 7 == 0 or choke:
					_naval_anchors.append(pid)
		if _air_bases.size() < air_cap:
			var is_base := false
			if p != null:
				var vp := 0
				var dev := 0.0
				if "victory_points" in p:
					vp = int(p.victory_points)
				if "development_level" in p:
					dev = float(p.development_level)
				if vp >= 5 or dev >= 4.0:
					is_base = true
			if typeof(SpecialSiteManager) != TYPE_NIL and SpecialSiteManager.has_method("get_sites_for_province"):
				var sites = SpecialSiteManager.get_sites_for_province(pid)
				if sites is Array:
					for s in sites:
						var sid := str(s.get("id", s) if s is Dictionary else s).to_lower()
						if sid.contains("air") or sid.contains("airfield"):
							is_base = true
			if is_base:
				_air_bases.append(pid)
		if _naval_anchors.size() >= naval_cap and _air_bases.size() >= air_cap:
			break


func _draw_naval_task_groups() -> void:
	var n := 0
	for pid_v in _naval_anchors:
		if n >= max_icons / 2:
			break
		var pid := int(pid_v)
		var c: Vector2 = _centroids.get(pid, Vector2.ZERO)
		if c == Vector2.ZERO:
			continue
		_draw_task_group_icon(c, "patrol" if pid % 3 == 0 else ("escort" if pid % 3 == 1 else "strike"))
		_last_naval_n += 1
		n += 1


func _draw_task_group_icon(pos: Vector2, mission: String) -> void:
	var col := Color(0.35, 0.65, 0.95, 0.8)
	match mission:
		"escort":
			col = Color(0.4, 0.85, 0.7, 0.8)
		"strike":
			col = Color(0.95, 0.45, 0.35, 0.85)
		_:
			col = Color(0.35, 0.65, 0.95, 0.8)
	# Hull diamond + mission pip
	var pts := PackedVector2Array([
		pos + Vector2(0, -7), pos + Vector2(9, 0), pos + Vector2(0, 7), pos + Vector2(-9, 0),
	])
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.35))
	draw_polyline(pts + PackedVector2Array([pts[0]]), col, 1.4, true)
	draw_circle(pos + Vector2(0, -11), 2.0, col)


func _draw_air_sorties() -> void:
	var n := 0
	var bases: Array = _air_bases
	for i in range(mini(bases.size(), max_icons / 2)):
		var base_pid: int = int(bases[i])
		var c: Vector2 = _centroids.get(base_pid, Vector2.ZERO)
		if c == Vector2.ZERO:
			continue
		_draw_airbase_icon(c)
		# Sortie arrow toward nearest contested or offset
		var target := c + Vector2(40.0 + 20.0 * sin(_phase * TAU + float(i)), -30.0)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_contested_provinces"):
			var cont: Dictionary = MapManager.get_contested_provinces()
			for cp_v in cont.keys():
				var cp := int(cp_v)
				if _centroids.has(cp):
					target = _centroids[cp]
					break
		_draw_sortie_arrow(c, target)
		# Carrier air support stub: small arc near coastal bases
		if i % 2 == 0:
			draw_arc(c + Vector2(18, 8), 12.0, -0.8, 0.8, 8, Color(0.6, 0.85, 1.0, 0.45), 1.2, true)
		_last_air_n += 1
		n += 1
		if n >= max_icons / 2:
			break


func _draw_airbase_icon(pos: Vector2) -> void:
	var col := Color(0.75, 0.85, 1.0, 0.85)
	draw_circle(pos, 4.0, Color(col.r, col.g, col.b, 0.35))
	draw_line(pos + Vector2(-8, 0), pos + Vector2(8, 0), col, 1.5, true)
	draw_line(pos + Vector2(-5, 4), pos + Vector2(5, -4), col, 1.2, true)


func _draw_sortie_arrow(from: Vector2, to: Vector2) -> void:
	var dir := (to - from)
	if dir.length() < 4.0:
		return
	var mid := from.lerp(to, 0.35 + 0.2 * _phase)
	var col := Color(0.7, 0.85, 1.0, 0.55)
	draw_line(from, mid, col, 1.3, true)
	var d := (mid - from).normalized()
	var tip := mid + d * 5.0
	var side := d.orthogonal() * 3.5
	draw_colored_polygon(PackedVector2Array([tip, mid + side, mid - side]), col)
