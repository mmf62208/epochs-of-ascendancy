# scripts/ui/map/MapMinimap.gd
## Corner minimap: click-to-pan, LOD tier hint, strategic political dots (Vic3-style).
extends PanelContainer

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")

var _map_renderer: Node = null
var _camera: Camera2D = null
var _draw_area: Control = null
var _world_bounds: Rect2 = MapCanvasConfig.WORLD_CANONICAL_BOUNDS
var _viewport_rect: Rect2 = Rect2()
var _lod_tier: int = MapZoomLODScript.Tier.STRATEGIC
var _political_dots: Array = []  # [{pos: Vector2, color: Color}]
var _dots_built: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(180, 100)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_area = Control.new()
	_draw_area.custom_minimum_size = Vector2(180, 100)
	_draw_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_area.gui_input.connect(_on_minimap_input)
	_draw_area.draw.connect(_on_draw_minimap)
	add_child(_draw_area)


func bind(map_renderer: Node, camera: Camera2D) -> void:
	_map_renderer = map_renderer
	_camera = camera
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_world_bounds"):
		var wb: Rect2 = MapManager.get_world_bounds()
		if wb.size.x > 10.0 and wb.size.y > 0.0:
			_world_bounds = wb
	invalidate_political_cache()
	_draw_area.queue_redraw()


func set_lod_tier(tier: int) -> void:
	if tier == _lod_tier:
		return
	_lod_tier = tier
	if _draw_area != null:
		_draw_area.queue_redraw()


func invalidate_political_cache() -> void:
	_political_dots.clear()
	_dots_built = false


func _ensure_political_dots() -> void:
	if _dots_built:
		return
	_dots_built = true
	if typeof(MapManager) == TYPE_NIL:
		return
	var centroids: Dictionary = {}
	if MapManager.has_method("get_all_centroids"):
		centroids = MapManager.get_all_centroids()
	elif MapManager.has_method("get_province_centroid"):
		if "provinces" in MapManager:
			for pid_var in MapManager.provinces.keys():
				centroids[int(pid_var)] = MapManager.get_province_centroid(int(pid_var))
	if centroids.is_empty():
		return

	for pid_var in centroids.keys():
		var pid := int(pid_var)
		var pos: Vector2 = centroids[pid_var] as Vector2
		if pos == Vector2.ZERO:
			continue
		var prov: Province = null
		if MapManager.has_method("get_province"):
			prov = MapManager.get_province(pid) as Province
		if prov != null and prov.is_sea:
			continue
		var tag := ""
		if prov != null:
			tag = prov.owner_tag.strip_edges().to_upper()
		var col := Color(0.45, 0.48, 0.55, 0.85)
		if not tag.is_empty() and MapManager.has_method("get_country_color"):
			col = MapManager.get_country_color(tag)
			col.a = 0.88
		_political_dots.append({"pos": pos, "color": col})


func _minimap_transform(r: Rect2) -> Dictionary:
	var scale_x := r.size.x / _world_bounds.size.x
	var scale_y := r.size.y / _world_bounds.size.y
	var s := minf(scale_x, scale_y) * 0.95
	var ox := r.position.x + (r.size.x - _world_bounds.size.x * s) * 0.5
	var oy := r.position.y + (r.size.y - _world_bounds.size.y * s) * 0.5
	return {"s": s, "ox": ox, "oy": oy}


func _world_to_minimap(p: Vector2, xf: Dictionary) -> Vector2:
	return Vector2(xf["ox"] + p.x * xf["s"], xf["oy"] + p.y * xf["s"])


func _on_draw_minimap() -> void:
	if _draw_area == null:
		return
	var r := _draw_area.get_rect()
	_draw_area.draw_rect(r, Color(0.08, 0.1, 0.14, 0.92))
	_draw_area.draw_rect(r, Color(0.25, 0.55, 0.85, 0.35), false, 1.0)

	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province_count"):
		return

	var xf := _minimap_transform(r)

	if MapZoomLODScript.show_minimap_political_dots(_lod_tier):
		_ensure_political_dots()
		var dot_r := 1.6 if _lod_tier == MapZoomLODScript.Tier.STRATEGIC else 1.2
		for entry: Dictionary in _political_dots:
			var mp := _world_to_minimap(entry["pos"] as Vector2, xf)
			if not r.has_point(mp):
				continue
			_draw_area.draw_circle(mp, dot_r, entry["color"] as Color)
	else:
		# Europe cluster hint when not showing full political dots
		var europe := Rect2(
			_world_bounds.position.x,
			_world_bounds.position.y,
			_world_bounds.size.x * 0.45,
			_world_bounds.size.y * 0.45
		)
		_draw_area.draw_rect(
			Rect2(
				xf["ox"] + europe.position.x * xf["s"],
				xf["oy"] + europe.position.y * xf["s"],
				europe.size.x * xf["s"],
				europe.size.y * xf["s"]
			),
			Color(0.2, 0.75, 0.55, 0.25)
		)

	if _camera != null:
		var vp := get_viewport().get_visible_rect().size
		var zoom := absf(_camera.zoom.x)
		var half := vp * 0.5 / maxf(zoom, 0.01)
		var cam_center := _camera.global_position
		var view := Rect2(cam_center - half, half * 2.0)
		_viewport_rect = Rect2(
			xf["ox"] + view.position.x * xf["s"],
			xf["oy"] + view.position.y * xf["s"],
			view.size.x * xf["s"],
			view.size.y * xf["s"]
		)
		_draw_area.draw_rect(_viewport_rect, Color(1.0, 0.35, 0.55, 0.55), false, 2.0)

	var tier_name := MapZoomLODScript.tier_name(_lod_tier)
	var tier_col := Color(0.55, 0.82, 0.98, 0.92)
	if _lod_tier == MapZoomLODScript.Tier.OPERATIONAL:
		tier_col = Color(0.78, 0.88, 0.55, 0.92)
	elif _lod_tier == MapZoomLODScript.Tier.TACTICAL:
		tier_col = Color(0.98, 0.72, 0.45, 0.92)
	_draw_area.draw_string(
		ThemeDB.fallback_font,
		r.position + Vector2(6, 14),
		tier_name.capitalize(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		tier_col
	)


func _on_minimap_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = _draw_area.get_local_mouse_position()
		var r := _draw_area.get_rect()
		var xf := _minimap_transform(r)
		var wx: float = (local.x - float(xf["ox"])) / float(xf["s"])
		var wy: float = (local.y - float(xf["oy"])) / float(xf["s"])
		_camera.global_position = Vector2(wx, wy)
		_draw_area.queue_redraw()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_on_minimap_input(InputEventMouseButton.new())


func _process(_delta: float) -> void:
	if _draw_area != null and _camera != null:
		_draw_area.queue_redraw()
