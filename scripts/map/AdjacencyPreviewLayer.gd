# scripts/map/AdjacencyPreviewLayer.gd
## Highlights neighbors + movement cost when a province is selected.
extends Node2D

var _selected_pid: int = -1
var _neighbor_lines: Array[Line2D] = []
var _labels: Array[Label] = []


func set_selected_province(pid: int) -> void:
	if pid == _selected_pid:
		return
	_selected_pid = pid
	_rebuild()


func clear_selection() -> void:
	_selected_pid = -1
	_clear_drawn()


func _clear_drawn() -> void:
	for ln in _neighbor_lines:
		if is_instance_valid(ln):
			ln.queue_free()
	for lb in _labels:
		if is_instance_valid(lb):
			lb.queue_free()
	_neighbor_lines.clear()
	_labels.clear()


func _rebuild() -> void:
	_clear_drawn()
	if _selected_pid < 0 or typeof(MapManager) == TYPE_NIL:
		return
	if not MapManager.has_method("get_adjacent_provinces"):
		return

	var geo: Dictionary = MapManager.get_province_geometry(_selected_pid)
	var anchor: Array = geo.get("label_anchor", [])
	var from_pos := Vector2.ZERO
	if anchor.size() >= 2:
		from_pos = Vector2(float(anchor[0]), float(anchor[1]))
	elif MapManager.has_method("get_province_centroid"):
		from_pos = MapManager.get_province_centroid(_selected_pid)

	var neighbors: Array = MapManager.get_adjacent_provinces(_selected_pid)
	for n_var in neighbors:
		var nid := int(n_var)
		var ngeo: Dictionary = MapManager.get_province_geometry(nid)
		var nanchor: Array = ngeo.get("label_anchor", [])
		var to_pos := from_pos
		if nanchor.size() >= 2:
			to_pos = Vector2(float(nanchor[0]), float(nanchor[1]))
		elif MapManager.has_method("get_province_centroid"):
			to_pos = MapManager.get_province_centroid(nid)

		var ln := Line2D.new()
		ln.width = 2.5
		ln.default_color = Color(0.95, 0.75, 0.2, 0.85)
		ln.points = PackedVector2Array([from_pos, to_pos])
		ln.z_index = 75
		add_child(ln)
		_neighbor_lines.append(ln)

		var prov: Province = MapManager.get_province(_selected_pid)
		var move_cost := 1.0
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_terrain"):
			var terr: Dictionary = MapManager.get_province_terrain(nid)
			move_cost = float(terr.get("movement_cost", 1.0))
		elif prov != null and prov.has_method("get_movement_cost"):
			move_cost = prov.get_movement_cost()

		var mid := (from_pos + to_pos) * 0.5
		var lb := Label.new()
		lb.text = "%.1f" % move_cost
		lb.position = mid + Vector2(4, -8)
		lb.add_theme_font_size_override("font_size", 11)
		lb.modulate = Color(1.0, 0.95, 0.7)
		lb.z_index = 76
		add_child(lb)
		_labels.append(lb)
