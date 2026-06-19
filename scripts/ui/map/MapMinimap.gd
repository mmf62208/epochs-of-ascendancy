# scripts/ui/map/MapMinimap.gd
## Corner minimap: click-to-pan over world bounds.
extends PanelContainer

var _map_renderer: Node = null
var _camera: Camera2D = null
var _draw_area: Control = null
var _world_bounds: Rect2 = MapCanvasConfig.WORLD_CANONICAL_BOUNDS
var _viewport_rect: Rect2 = Rect2()


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
		if wb.size.x > 10.0 and wb.size.y > 10.0:
			_world_bounds = wb
	_draw_area.queue_redraw()


func _on_draw_minimap() -> void:
	if _draw_area == null:
		return
	var r := _draw_area.get_rect()
	_draw_area.draw_rect(r, Color(0.08, 0.1, 0.14, 0.92))
	_draw_area.draw_rect(r, Color(0.25, 0.55, 0.85, 0.35), false, 1.0)

	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province_count"):
		return

	var scale_x := r.size.x / _world_bounds.size.x
	var scale_y := r.size.y / _world_bounds.size.y
	var s := minf(scale_x, scale_y) * 0.95
	var ox := r.position.x + (r.size.x - _world_bounds.size.x * s) * 0.5
	var oy := r.position.y + (r.size.y - _world_bounds.size.y * s) * 0.5

	# Europe cluster hint (NW of world canvas)
	var europe := Rect2(_world_bounds.position.x, _world_bounds.position.y, _world_bounds.size.x * 0.45, _world_bounds.size.y * 0.45)
	_draw_area.draw_rect(
		Rect2(ox + europe.position.x * s, oy + europe.position.y * s, europe.size.x * s, europe.size.y * s),
		Color(0.2, 0.75, 0.55, 0.25)
	)

	if _camera != null:
		var vp := get_viewport().get_visible_rect().size
		var zoom := absf(_camera.zoom.x)
		var half := vp * 0.5 / maxf(zoom, 0.01)
		var cam_center := _camera.global_position
		var view := Rect2(cam_center - half, half * 2.0)
		_viewport_rect = Rect2(
			ox + view.position.x * s,
			oy + view.position.y * s,
			view.size.x * s,
			view.size.y * s
		)
		_draw_area.draw_rect(_viewport_rect, Color(1.0, 0.35, 0.55, 0.55), false, 2.0)


func _on_minimap_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = _draw_area.get_local_mouse_position()
		var r := _draw_area.get_rect()
		var scale_x := r.size.x / _world_bounds.size.x
		var scale_y := r.size.y / _world_bounds.size.y
		var s := minf(scale_x, scale_y) * 0.95
		var ox := r.position.x + (r.size.x - _world_bounds.size.x * s) * 0.5
		var oy := r.position.y + (r.size.y - _world_bounds.size.y * s) * 0.5
		var wx := (local.x - ox) / s
		var wy := (local.y - oy) / s
		_camera.global_position = Vector2(wx, wy)
		_draw_area.queue_redraw()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_on_minimap_input(InputEventMouseButton.new())


func _process(_delta: float) -> void:
	if _draw_area != null and _camera != null:
		_draw_area.queue_redraw()
