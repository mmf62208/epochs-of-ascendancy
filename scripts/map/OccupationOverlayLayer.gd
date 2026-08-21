# scripts/map/OccupationOverlayLayer.gd
## Occupation visual feedback layer (gap-closure Phase 1 — major #24 depth).
## Contested provinces: control/resistance tint + garrison strength icon.
## Data-driven from GameData occupation_province + occupation_revolt; cheap _draw.

class_name OccupationOverlayLayer
extends Node2D

const ProvincePolygonUtil = preload("res://scripts/map/ProvincePolygonUtil.gd")

@export var enabled: bool = true
@export var show_resistance_heatmap: bool = true
@export var show_garrison_icons: bool = true
@export var show_compliance_ring: bool = true
## Phase 2: partisan activity markers + full occupation mapmode
@export var show_partisan_markers: bool = true
@export var mapmode: String = "occupation"  # occupation | resistance | compliance
@export var include_non_contested_heatmap: bool = false  # resistance mapmode can tint all with state
@export var max_icons: int = 48  # budget at world_full zoom
@export var max_fill_polys: int = 64  # full poly fills are expensive + many world_full polys fail triangulation
@export var icon_radius: float = 7.0
@export var fill_alpha_base: float = 0.12
@export var fill_alpha_max: float = 0.28
## Prefer centroid circle tints on large boards (avoids invalid poly triangulation spam/hang).
@export var prefer_centroid_fills_on_large_boards: bool = true
@export var large_board_threshold: int = 800

var _map_container: Node2D
var _centroids: Dictionary = {}
var _provinces: Dictionary = {}
var _geometry: Dictionary = {}
var _highlight_province_id: int = -1
var _last_draw_count: int = 0
var _last_icon_count: int = 0
var _last_partisan_n: int = 0
var _redraw_pending: bool = false
var _last_tri_fail_log_ms: int = 0
var _tri_fail_n: int = 0


func set_highlight_province(province_id: int) -> void:
	if _highlight_province_id == province_id:
		return
	_highlight_province_id = province_id
	_request_redraw()


func setup(centroids: Dictionary, provinces: Dictionary, geometry: Dictionary = {}) -> void:
	_centroids = centroids
	_provinces = provinces
	_geometry = geometry
	_request_redraw()


func setup_with_map(
	map_container: Node2D,
	centroids: Dictionary,
	provinces: Dictionary,
	geometry: Dictionary = {},
) -> void:
	_map_container = map_container
	setup(centroids, provinces, geometry)


func _ready() -> void:
	z_index = 0  # above ConflictOverlay (-1), under labels
	if typeof(MapManager) != TYPE_NIL and MapManager.has_signal("province_data_changed"):
		if not MapManager.province_data_changed.is_connected(_on_province_data_changed):
			MapManager.province_data_changed.connect(_on_province_data_changed)


func _on_province_data_changed(_pid: int, what: String) -> void:
	if what in ["owner", "controller", "all"]:
		if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_interactive_light_sim") and bool(TimeManager.is_interactive_light_sim()):
			return
	if what in ["owner", "controller", "all", "occupation", "garrison"]:
		_request_redraw()


func refresh() -> void:
	_request_redraw()


## Debounce redraw — province_data_changed fires often; full redraw of invalid polys hung F5.
func _request_redraw() -> void:
	if _redraw_pending:
		return
	_redraw_pending = true
	# Call deferred chain so we coalesce many change signals into one draw.
	call_deferred("_flush_redraw")


func _flush_redraw() -> void:
	_redraw_pending = false
	if is_inside_tree():
		queue_redraw()


func get_draw_stats() -> Dictionary:
	return {
		"draw_n": _last_draw_count,
		"icon_n": _last_icon_count,
		"partisan_n": _last_partisan_n,
		"enabled": enabled,
		"heatmap": show_resistance_heatmap,
		"garrison_icons": show_garrison_icons,
		"mapmode": mapmode,
	}


func set_mapmode(mode: String) -> void:
	var m := mode.strip_edges().to_lower()
	if m in ["occupation", "resistance", "compliance"]:
		mapmode = m
	_request_redraw()


static func _is_occupied(province: Province) -> bool:
	if province == null or province.controller_tag.is_empty():
		return false
	# Unowned / empty owner is not "occupation" for overlay purposes.
	if province.owner_tag.is_empty():
		return false
	return province.owner_tag != province.controller_tag


func _board_province_count() -> int:
	if not _provinces.is_empty():
		return _provinces.size()
	if not _centroids.is_empty():
		return _centroids.size()
	return 0


func _draw() -> void:
	_last_draw_count = 0
	_last_icon_count = 0
	_last_partisan_n = 0
	if not enabled:
		return
	var entries := _collect_occupied()
	if mapmode == "resistance" or mapmode == "compliance":
		entries = _collect_heatmap_entries(entries)
	# Sort by resistance desc so icons prioritize hotspots under budget.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("resistance", 0.0)) > float(b.get("resistance", 0.0))
	)
	var icons_left := max_icons
	var fills_left := max_fill_polys
	var use_centroid_only := prefer_centroid_fills_on_large_boards and _board_province_count() >= large_board_threshold
	for entry in entries:
		_draw_occupation_province(entry, icons_left > 0, fills_left > 0, use_centroid_only)
		_last_draw_count += 1
		if bool(entry.get("drew_fill", false)):
			fills_left -= 1
		if bool(entry.get("drew_icon", false)):
			icons_left -= 1
			_last_icon_count += 1
		if show_partisan_markers and float(entry.get("revolt_risk", 0.0)) >= 0.18:
			_draw_partisan_marker(entry)
			_last_partisan_n += 1


func _collect_occupied() -> Array:
	var out: Array = []
	var src: Dictionary = _provinces
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
		src = MapManager.get_all_provinces()
	for pid_var in src.keys():
		var p: Province = src[pid_var] as Province
		if p == null or not _is_occupied(p):
			continue
		var pid := int(pid_var)
		var occ := _occ_state(pid)
		var rev := _revolt_state(pid)
		out.append({
			"pid": pid,
			"owner": p.owner_tag,
			"controller": p.controller_tag,
			"resistance": float(occ.get("resistance_level", 0.55)),
			"compliance": float(occ.get("compliance_level", 0.40)),
			"revolt_risk": float(occ.get("revolt_risk", 0.12)),
			"garrison_strength": float(rev.get("garrison_strength", 0.45)),
			"garrison_mode": str(rev.get("garrison_mode", "standard")),
			"flashpoint": float(rev.get("flashpoint", 0.48)),
		})
	return out


func _occ_state(pid: int) -> Dictionary:
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_occupation_province_state"):
		return GameData.get_occupation_province_state(pid)
	return {"resistance_level": 0.55, "compliance_level": 0.4, "revolt_risk": 0.12}


func _revolt_state(pid: int) -> Dictionary:
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_occupation_revolt_state"):
		return GameData.get_occupation_revolt_state(pid)
	return {"garrison_strength": 0.45, "garrison_mode": "standard", "flashpoint": 0.48}


func _collect_heatmap_entries(base: Array) -> Array:
	## Phase 2 mapmode: include stored occupation state provinces even if not contested.
	if not include_non_contested_heatmap and mapmode == "occupation":
		return base
	var seen: Dictionary = {}
	var out: Array = []
	for e in base:
		var pid := int(e.get("pid", -1))
		seen[pid] = true
		out.append(e)
	if typeof(GameData) != TYPE_NIL and GameData.get("peace_state") is Dictionary:
		var ps: Dictionary = GameData.peace_state
		var store: Dictionary = ps.get("occupation_province", {}) if ps.has("occupation_province") else {}
		if store is Dictionary:
			for key in store.keys():
				var pid2 := int(key) if str(key).is_valid_int() else -1
				if pid2 < 0 or seen.has(pid2):
					continue
				var occ: Dictionary = store[key] if store[key] is Dictionary else {}
				var rev := _revolt_state(pid2)
				out.append({
					"pid": pid2,
					"owner": "",
					"controller": "",
					"resistance": float(occ.get("resistance_level", 0.55)),
					"compliance": float(occ.get("compliance_level", 0.4)),
					"revolt_risk": float(occ.get("revolt_risk", 0.12)),
					"garrison_strength": float(rev.get("garrison_strength", 0.45)),
					"garrison_mode": str(rev.get("garrison_mode", "standard")),
					"flashpoint": float(rev.get("flashpoint", 0.48)),
				})
	return out


func _draw_partisan_marker(entry: Dictionary) -> void:
	var pid := int(entry.get("pid", -1))
	if pid < 0:
		return
	var center: Vector2 = _centroids.get(pid, Vector2.ZERO)
	var points := _polygon_points_for(pid)
	if points.size() >= 3:
		center = _centroid_of(_offset_points(points, _province_node_offset(pid)))
	var risk := clampf(float(entry.get("revolt_risk", 0.2)), 0.0, 1.0)
	var col := Color(0.95, 0.35, 0.2, 0.55 + 0.35 * risk)
	# Partisan chevron cluster
	var o := Vector2(10, -8)
	draw_colored_polygon(PackedVector2Array([
		center + o + Vector2(0, -5), center + o + Vector2(4, 3), center + o + Vector2(-4, 3),
	]), col)
	if risk >= 0.35:
		draw_circle(center + o + Vector2(8, 2), 2.0, col)


func _draw_occupation_province(entry: Dictionary, allow_icon: bool, allow_fill: bool = true, centroid_only: bool = false) -> void:
	var pid := int(entry.get("pid", -1))
	if pid < 0:
		return
	var resistance := clampf(float(entry.get("resistance", 0.55)), 0.0, 1.0)
	var compliance := clampf(float(entry.get("compliance", 0.4)), 0.0, 1.0)
	var garr := clampf(float(entry.get("garrison_strength", 0.45)), 0.0, 1.0)
	var emphasized := pid == _highlight_province_id
	var points := _polygon_points_for(pid)
	var offset := _province_node_offset(pid)
	var world_pts := _offset_points(points, offset) if points.size() >= 3 else PackedVector2Array()
	var center: Vector2 = _centroids.get(pid, Vector2.ZERO)
	if world_pts.size() >= 3 and not centroid_only:
		center = _centroid_of(world_pts)
	if center == Vector2.ZERO and world_pts.size() >= 3:
		center = _centroid_of(world_pts)

	if allow_fill and (show_resistance_heatmap or mapmode in ["resistance", "compliance"]):
		# Red = resistance, green lean = compliance; alpha scales with heat.
		var heat := clampf(resistance * 0.7 + float(entry.get("revolt_risk", 0.12)) * 0.3, 0.0, 1.0)
		if mapmode == "compliance":
			heat = clampf(1.0 - compliance, 0.0, 1.0)
		var alpha := lerpf(fill_alpha_base, fill_alpha_max, heat)
		if mapmode == "compliance":
			alpha = lerpf(fill_alpha_base, fill_alpha_max, compliance)
		if emphasized:
			alpha = minf(alpha * 1.6, 0.4)
		var fill: Color
		if mapmode == "compliance":
			fill = Color(
				lerpf(0.9, 0.2, compliance),
				lerpf(0.35, 0.9, compliance),
				lerpf(0.25, 0.45, compliance),
				alpha,
			)
		else:
			fill = Color(
				lerpf(0.25, 0.95, heat),
				lerpf(0.55, 0.18, heat) * (0.5 + 0.5 * compliance),
				0.18,
				alpha,
			)
		# Safe fill via shared util (triangulate / hull / circle) — any province clickable safely.
		if not centroid_only and world_pts.size() >= 3:
			var mode := ProvincePolygonUtil.draw_fill(self, world_pts, fill, center, 18.0 if centroid_only else 22.0)
			entry["drew_fill"] = mode != "none"
			if mode == "circle":
				_note_tri_fail()
		else:
			draw_circle(center, 18.0 if centroid_only else 22.0, fill)
			entry["drew_fill"] = true

	if show_compliance_ring and compliance > 0.01:
		var ring_a := 0.25 + 0.45 * compliance
		if emphasized:
			ring_a = minf(ring_a * 1.3, 0.9)
		draw_arc(center, 14.0 + 4.0 * compliance, 0.0, TAU, 24,
			Color(0.35, 0.85, 0.55, ring_a), 1.5 + compliance, true)

	if show_garrison_icons and allow_icon:
		_draw_garrison_icon(center, garr, str(entry.get("garrison_mode", "standard")), emphasized)
		entry["drew_icon"] = true


func _note_tri_fail() -> void:
	_tri_fail_n += 1
	var now := Time.get_ticks_msec()
	if now - _last_tri_fail_log_ms > 5000:
		_last_tri_fail_log_ms = now
		print("[OccupationOverlay] used circle fallback for %d invalid poly fill(s)" % _tri_fail_n)
		_tri_fail_n = 0


func _draw_garrison_icon(center: Vector2, strength: float, mode: String, emphasized: bool) -> void:
	var r := icon_radius * (0.85 + 0.45 * strength)
	if emphasized:
		r *= 1.15
	var col := Color(0.55, 0.75, 0.95, 0.85)
	match mode:
		"light":
			col = Color(0.7, 0.85, 0.55, 0.8)
		"heavy":
			col = Color(0.95, 0.55, 0.35, 0.9)
		_:
			col = Color(0.55, 0.75, 0.95, 0.85)
	# Shield-ish diamond + fill proportional to strength.
	var pts := PackedVector2Array([
		center + Vector2(0, -r),
		center + Vector2(r * 0.75, 0),
		center + Vector2(0, r),
		center + Vector2(-r * 0.75, 0),
	])
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.35 + 0.45 * strength))
	draw_polyline(pts + PackedVector2Array([pts[0]]), col, 1.5 if not emphasized else 2.2, true)
	# Inner strength pip
	if strength >= 0.55:
		draw_circle(center, r * 0.28, Color(1, 1, 1, 0.55 + 0.3 * strength))


func _centroid_of(points: PackedVector2Array) -> Vector2:
	var acc := Vector2.ZERO
	for p in points:
		acc += p
	return acc / float(points.size())


func _province_node_offset(pid: int) -> Vector2:
	if _map_container == null:
		return Vector2.ZERO
	var node := _map_container.get_node_or_null("Prov_%d" % pid) as Node2D
	if node == null:
		return Vector2.ZERO
	return node.position


func _polygon_points_for(pid: int) -> PackedVector2Array:
	if _map_container != null:
		var node := _map_container.get_node_or_null("Prov_%d" % pid)
		if node != null:
			for child in node.get_children():
				if child is Polygon2D:
					return ProvincePolygonUtil.make_drawable((child as Polygon2D).polygon)
	if _geometry.has(pid):
		var geo: Dictionary = _geometry[pid]
		return ProvincePolygonUtil.make_drawable(
			ProvincePolygonUtil.from_variant_points(geo.get("points", []))
		)
	return PackedVector2Array()


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	if offset == Vector2.ZERO:
		return points
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in range(points.size()):
		out[i] = points[i] + offset
	return out
