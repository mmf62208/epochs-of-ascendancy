# scripts/map/CameraController.gd
## Attach to WorldMap/CameraInput. Drives target (ProvinceContainers) scale + position.
class_name CameraController
extends Node2D

@export var target: Node2D
@export var zoom_speed: float = 0.12
@export var min_zoom: float = 0.15
@export var max_zoom: float = MapCanvasConfig.MAX_CAMERA_ZOOM
@export var enable_zoom: bool = true
@export var enable_pan: bool = true
@export var enable_wasd: bool = true
@export var wasd_speed: float = 600.0
@export var enable_edge_pan: bool = true
@export var edge_pan_margin: float = 56.0
@export var edge_pan_speed: float = 980.0

@export var enable_wrap: bool = true

var _wrap_bounds: Rect2 = Rect2()
var _target_zoom := 1.0
var _is_panning := false

const _ZOOM_LERP_SPEED: float = 12.0


func _ready() -> void:
	if target == null:
		target = self
	_target_zoom = clampf(target.scale.x if target.scale.x > 0.01 else 1.0, min_zoom, max_zoom)
	# Do not force-scale target before MapRenderer can disable zoom for GIS boards.
	if enable_zoom:
		target.scale = Vector2.ONE * _target_zoom
	add_to_group("camera_controller")
	# ALWAYS so pan/zoom/edge work while TimeManager is paused (playtest look-around).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)


## Public helper for debug / test scenario loading to set an initial view cleanly.
func set_initial_view(target_position: Vector2, target_zoom_level: float, instant: bool = true):
	if target == null:
		return
	# When MapRenderer drives MapCamera for GIS world boards, never scale ProvinceContainers
	# (that produces dual map: small underlay + giant poly mesh).
	if not enable_zoom:
		return

	target.position = target_position

	var clamped := clampf(target_zoom_level, min_zoom, max_zoom)
	if instant:
		_target_zoom = clamped
		target.scale = Vector2.ONE * clamped
	else:
		_target_zoom = clamped
		# Let the normal _process lerp handle the animation


func _process(delta: float) -> void:
	if target == null:
		return

	# GIS / MapCamera boards: never leave a residual scale on ProvinceContainers
	# (causes dual map: underlay at one scale + polys at another).
	if not enable_zoom:
		if target.scale != Vector2.ONE:
			target.scale = Vector2.ONE
		# Still allow wasd/edge only when explicitly enabled (legacy boards).
		if enable_wasd:
			_apply_wasd(delta)
		if enable_edge_pan:
			_apply_edge_pan(delta)
		return

	# Map navigation must work while sim is paused (playtest look-around).
	if enable_wasd:
		_apply_wasd(delta)
	if enable_edge_pan:
		_apply_edge_pan(delta)

	var current := target.scale.x
	if absf(current - _target_zoom) <= 0.001:
		return

	var nav_delta := MapViewInput.motion_delta(delta)
	var new_scale := lerpf(current, _target_zoom, clampf(_ZOOM_LERP_SPEED * nav_delta, 0.0, 1.0))
	if absf(new_scale - _target_zoom) < 0.002:
		new_scale = _target_zoom
	_adjust_origin_for_uniform_zoom(current, new_scale)
	target.scale = Vector2(new_scale, new_scale)


func _apply_wasd(delta: float) -> void:
	# Command Center / modals: no WASD pan under overlay.
	if MapViewInput.modal_blocks_map_nav(get_viewport()):
		return
	var nav_delta := MapViewInput.motion_delta(delta)
	var move := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_action_pressed("move_left"):
		move.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_action_pressed("move_right"):
		move.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_action_pressed("move_up"):
		move.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_action_pressed("move_down"):
		move.y += 1.0
	if move.length_squared() > 0.0001:
		target.position += move.normalized() * wasd_speed * nav_delta
		_apply_wrap()


func _apply_wrap() -> void:
	if not enable_wrap or _wrap_bounds.size.x <= 0.0:
		return
	target.position = MapCanvasConfig.wrap_position(target.position, _wrap_bounds)


func set_wrap_bounds(bounds: Rect2) -> void:
	_wrap_bounds = bounds


func _apply_edge_pan(delta: float) -> void:
	var vp := get_viewport()
	if MapViewInput.edge_pan_blocked_by_gui(vp):
		return
	var nav_delta := MapViewInput.motion_delta(delta)
	var m := vp.get_mouse_position()
	var sz: Vector2 = vp.get_visible_rect().size
	var dir := Vector2.ZERO
	if m.x <= edge_pan_margin:
		dir.x -= 1.0
	elif m.x >= sz.x - edge_pan_margin:
		dir.x += 1.0
	if m.y >= sz.y - edge_pan_margin:
		dir.y += 1.0
	else:
		# Pan north under the HUD strip (not raw screen top — avoids thrash over TopInfoBar).
		var top_safe := 90.0
		if get_tree() and typeof(TopInfoBar) != TYPE_NIL:
			var tib = TopInfoBar.find_in_tree(get_tree())
			if tib != null and tib.has_method("get_bar_height"):
				top_safe = maxf(top_safe, float(tib.call("get_bar_height")) + 60.0)
		if m.y >= top_safe and m.y < top_safe + edge_pan_margin:
			dir.y -= 1.0
	if dir.length_squared() < 0.0001:
		return
	target.position += dir.normalized() * edge_pan_speed * nav_delta
	_apply_wrap()


func _input(event: InputEvent) -> void:
	if target == null or not enable_pan:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Middle-drag OR right-drag pan (laptops often lack middle button).
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			# Do not start pan when clicking UI chrome.
			if mb.pressed and MapViewInput.edge_pan_blocked_by_gui(get_viewport()):
				# Skip pan start over HUD/modals (TopInfoBar blocks edge pan on purpose).
				var hov := get_viewport().gui_get_hovered_control()
				if hov != null and not _is_under_top_info_bar(hov):
					return
			_is_panning = mb.pressed
			if mb.pressed:
				get_viewport().set_input_as_handled()

	if _is_panning and event is InputEventMouseMotion:
		target.position += (event as InputEventMouseMotion).relative
		_apply_wrap()
		get_viewport().set_input_as_handled()


func _is_under_top_info_bar(node: Node) -> bool:
	var n := node
	while n != null:
		if str(n.name) == "TopInfoBar":
			return true
		n = n.get_parent()
	return false


func _unhandled_input(event: InputEvent) -> void:
	if target == null or not enable_zoom:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		# Fallback wheel when MapRenderer did not handle (unhandled path).
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_toward_mouse(1.0 + zoom_speed * 1.35)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_toward_mouse(1.0 - zoom_speed * 1.35)
			get_viewport().set_input_as_handled()


func _zoom_toward_mouse(factor: float) -> void:
	var cur := clampf(_target_zoom, min_zoom, max_zoom)
	var next := clampf(cur * factor, min_zoom, max_zoom)
	if is_equal_approx(next, cur):
		return
	_target_zoom = next


func _adjust_origin_for_uniform_zoom(old_s: float, new_s: float) -> void:
	var mp := target.get_global_mouse_position()
	var local_mouse := target.get_global_transform().affine_inverse() * mp
	target.position += Vector2(local_mouse.x * (old_s - new_s), local_mouse.y * (old_s - new_s))

## Center (and optionally zoom) the map view on a world position. Used for auto-centering after map tool changes
## (settlement, infra invest, combat outcomes, etc.) so the player immediately sees the visual effect on the raster + polys.
func center_on_position(world_pos: Vector2, zoom_level: float = -1.0, instant: bool = true) -> void:
	if target == null:
		return
	target.position = world_pos
	if zoom_level > 0.0:
		var clamped := clampf(zoom_level, min_zoom, max_zoom)
		_target_zoom = clamped
		if instant:
			target.scale = Vector2.ONE * clamped
		# non-instant: _process lerp will handle toward _target_zoom
