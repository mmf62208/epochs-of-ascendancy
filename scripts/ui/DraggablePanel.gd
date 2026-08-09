# scripts/ui/DraggablePanel.gd
class_name DraggablePanel
extends Control

## Drag a panel by its root or by an optional handle (e.g. title bar).

@export var drag_handle: Control = null

var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	var handle := drag_handle if drag_handle != null else self
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	if handle != self:
		handle.gui_input.connect(_on_drag_input)
	else:
		gui_input.connect(_on_drag_input)


func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		global_position = _clamp_to_viewport(get_global_mouse_position() - _drag_offset)


func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return pos
	var visible_rect := viewport.get_visible_rect()
	var panel_size := size
	if panel_size == Vector2.ZERO:
		panel_size = custom_minimum_size
	var max_pos := visible_rect.size - Vector2(64, 48)
	return Vector2(
		clampf(pos.x, -panel_size.x + 64.0, max_pos.x),
		clampf(pos.y, 0.0, max_pos.y)
	)
