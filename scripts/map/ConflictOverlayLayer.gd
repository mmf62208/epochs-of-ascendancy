# scripts/map/ConflictOverlayLayer.gd
## Contested / occupied province overlay (controller != owner).
## Drawn under province outline nodes (z_index < 0 on the map container).

class_name ConflictOverlayLayer
extends Node2D

@export var stripe_color: Color = Color(1.0, 0.38, 0.38, 0.32)
@export var stripe_width: float = 3.0
@export var stripe_spacing: float = 10.0
@export var fill_tint: Color = Color(1.0, 0.25, 0.25, 0.08)
@export var draw_fill_tint: bool = true
@export var target_country: String = ""  # If non-empty, only show contested for provinces owned by this tag (e.g. "GER" or "USA")

var _map_container: Node2D
var _centroids: Dictionary = {}
var _provinces: Dictionary = {}
var _geometry: Dictionary = {}
var _highlight_province_id: int = -1


func set_highlight_province(province_id: int) -> void:
	if _highlight_province_id == province_id:
		return
	_highlight_province_id = province_id
	queue_redraw()


func setup(centroids: Dictionary, provinces: Dictionary, geometry: Dictionary = {}) -> void:
	_centroids = centroids
	_provinces = provinces
	_geometry = geometry
	queue_redraw()


func setup_with_map(
	map_container: Node2D,
	centroids: Dictionary,
	provinces: Dictionary,
	geometry: Dictionary = {},
) -> void:
	_map_container = map_container
	setup(centroids, provinces, geometry)


func _ready() -> void:
	z_index = -1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_signal("province_data_changed"):
		if not MapManager.province_data_changed.is_connected(_on_province_data_changed):
			MapManager.province_data_changed.connect(_on_province_data_changed)


func _on_province_data_changed(_pid: int, what: String) -> void:
	if what in ["owner", "controller", "all"]:
		queue_redraw()


func refresh() -> void:
	queue_redraw()


static func _is_contested(province: Province) -> bool:
	if province == null or province.controller_tag.is_empty():
		return false
	return province.owner_tag != province.controller_tag


static func count_contested(provinces: Dictionary = {}) -> int:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_contested_provinces"):
		return MapManager.get_contested_provinces().size()
	var n := 0
	for pid_var in provinces.keys():
		var p: Province = provinces[pid_var] as Province
		if p != null and _is_contested(p):
			n += 1
	return n


func _draw() -> void:
	var contested := _collect_contested()
	for entry in contested:
		_draw_contested_province(entry)
	_draw_front_lines()


func _draw_front_lines() -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_adjacent_provinces"):
		return
	var drawn: Dictionary = {}
	var sl := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if sl == null:
		return
	for pid_var in sl.provinces.keys():
		var a: int = int(pid_var)
		var pa: Province = sl.provinces[a] as Province
		if pa == null or pa.owner_tag.is_empty():
			continue
		for nb_var in MapManager.get_adjacent_provinces(a):
			var b: int = int(nb_var)
			if b <= a:
				continue
			var key := "%d_%d" % [mini(a, b), maxi(a, b)]
			if drawn.has(key):
				continue
			var pb: Province = sl.provinces.get(b) as Province
			if pb == null or pb.owner_tag.is_empty():
				continue
			if pa.owner_tag == pb.owner_tag:
				continue
			drawn[key] = true
			var ca := MapManager.get_province_centroid(a)
			var cb := MapManager.get_province_centroid(b)
			draw_line(ca, cb, Color(1.0, 0.15, 0.12, 0.75), 3.0)


func _collect_contested() -> Array:
	var out: Array = []
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_contested_provinces"):
		var contested_map := MapManager.get_contested_provinces(target_country) as Dictionary
		for pid in contested_map.keys():
			var bundle: Dictionary = contested_map[pid]
			out.append({
				"pid": int(pid),
				"owner": str(bundle.get("owner", "")),
				"controller": str(bundle.get("controller", "")),
			})
		return out
	# Legacy fallback (deprecated)
	for pid_var in _provinces.keys():
		var p: Province = _provinces[pid_var] as Province
		if p == null or not _is_contested(p):
			continue
		if target_country != "" and p.owner_tag != target_country:
			continue
		out.append({
			"pid": int(pid_var),
			"owner": p.owner_tag,
			"controller": p.controller_tag,
		})
	return out


func _draw_contested_province(entry: Dictionary) -> void:
	var pid := int(entry.get("pid", -1))
	if pid < 0:
		return
	var emphasized := pid == _highlight_province_id
	var stripe := stripe_color
	var fill := fill_tint
	var width := stripe_width
	if emphasized:
		stripe = Color(stripe.r, stripe.g, stripe.b, minf(stripe.a * 1.8, 0.55))
		fill = Color(fill.r, fill.g, fill.b, minf(fill.a * 2.2, 0.16))
		width = stripe_width + 1.0
	var points := _polygon_points_for(pid)
	if points.size() < 3:
		var c: Vector2 = _centroids.get(pid, Vector2.ZERO)
		_draw_centroid_hatch(c, stripe, width)
		return
	var offset := _province_node_offset(pid)
	var world_pts := _offset_points(points, offset)
	if draw_fill_tint:
		draw_colored_polygon(world_pts, fill)
	_draw_polygon_hatch(world_pts, stripe, width)


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
					return (child as Polygon2D).polygon
	if _geometry.has(pid):
		var geo: Dictionary = _geometry[pid]
		return geo.get("points", PackedVector2Array()) as PackedVector2Array
	return PackedVector2Array()


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	if offset == Vector2.ZERO:
		return points
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in range(points.size()):
		out[i] = points[i] + offset
	return out


func _draw_polygon_hatch(
	points: PackedVector2Array,
	stripe: Color = stripe_color,
	width: float = stripe_width,
) -> void:
	var min_v := points[0]
	var max_v := points[0]
	for p in points:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	var span := max_v - min_v
	var diag := span.length() + stripe_spacing * 4.0
	var steps := int(ceil((span.x + span.y) / stripe_spacing)) + 2
	for i in range(-2, steps + 2):
		var t := float(i) * stripe_spacing
		var start := min_v + Vector2(t - diag * 0.5, -diag * 0.5)
		var end := min_v + Vector2(t + diag * 0.5, diag * 0.5)
		draw_line(start, end, stripe, width, true)


func _draw_centroid_hatch(center: Vector2, stripe: Color = stripe_color, width: float = stripe_width) -> void:
	var half := 36.0
	for i in range(-2, 4):
		var offset := float(i) * stripe_spacing
		draw_line(
			center + Vector2(-half + offset, -half),
			center + Vector2(half + offset, half),
			stripe,
			width,
			true,
		)
