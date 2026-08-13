# scripts/map/ProvinceMeshLayer.gd
## Batched country fill layer (M2 perf path). Draws simplified fills per owner bucket in one _draw pass.
extends Node2D

const ProvincePolygonUtil = preload("res://scripts/map/ProvincePolygonUtil.gd")

var _buckets: Dictionary = {}  # owner_tag -> Array[PackedVector2Array]
var _colors: Dictionary = {}  # owner_tag -> Color
var _enabled: bool = false
var _poly_count: int = 0
var _bucket_count: int = 0
var _color_resolver: Callable


func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


func set_color_resolver(resolver: Callable) -> void:
	_color_resolver = resolver


func rebuild_from_provinces(
	province_dict: Dictionary,
	geometry: Dictionary,
	owner_resolver: Callable,
	world_mode: bool = false,
	geometry_is_world_native: bool = false,
) -> void:
	## Must use the same MapCanvasConfig transform as MapRenderer._create_province_node.
	## Raw 8192-space points against THEATER_SCALE polys/underlay = dual map (small card + giant mesh).
	_buckets.clear()
	_colors.clear()
	_poly_count = 0
	for pid_var in province_dict.keys():
		var pid := int(pid_var)
		var prov: Province = province_dict[pid_var] as Province
		if prov != null and prov.is_sea:
			continue
		var geo: Dictionary = geometry.get(pid, {})
		var raw := ProvincePolygonUtil.from_variant_points(geo.get("points", []))
		var xformed := MapCanvasConfig.transform_province_points(
			raw, world_mode, true, geometry_is_world_native
		)
		var poly := ProvincePolygonUtil.make_drawable(xformed)
		if poly.size() < 3:
			continue
		var tag := "NEU"
		if owner_resolver.is_valid():
			tag = str(owner_resolver.call(pid))
		if not _buckets.has(tag):
			_buckets[tag] = []
		(_buckets[tag] as Array).append(poly)
		_poly_count += 1
	_bucket_count = _buckets.size()
	for tag in _buckets.keys():
		if _color_resolver.is_valid():
			_colors[tag] = _color_resolver.call(tag) as Color
		else:
			_colors[tag] = _color_for_tag(str(tag))
	queue_redraw()


func get_stats() -> Dictionary:
	return {
		"enabled": _enabled,
		"polygons": _poly_count,
		"buckets": _bucket_count,
		"draw_calls": _bucket_count,
	}


func _draw() -> void:
	if not _enabled:
		return
	for tag in _buckets.keys():
		var col: Color = _colors.get(tag, _color_for_tag(str(tag)))
		for poly in _buckets[tag] as Array:
			var pts: PackedVector2Array = poly as PackedVector2Array
			if pts.size() >= 3:
				ProvincePolygonUtil.draw_fill(self, pts, col)


func _color_for_tag(tag: String) -> Color:
	var h := float(tag.hash()) / float(0x7FFFFFFF)
	return Color.from_hsv(fmod(h, 1.0), 0.45, 0.55, 0.72)
