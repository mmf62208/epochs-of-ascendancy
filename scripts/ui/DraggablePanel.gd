# scripts/ui/DraggablePanel.gd
class_name DraggablePanel
extends Control

## Drag a panel by its root or by an optional handle (e.g. title bar).
## Clicking any part of the panel raises it above other open screens.

@export var drag_handle: Control = null

var _dragging := false
var _drag_offset := Vector2.ZERO

## Shared stacking so each bring-to-front lands above the last.
static var _stack_z: int = 100


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if z_index < 80:
		z_index = 80
	var handle := drag_handle if drag_handle != null else self
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	if not handle.gui_input.is_connected(_on_drag_input):
		handle.gui_input.connect(_on_drag_input)
	# Raise when clicking anywhere on the panel body (not only the title bar).
	if handle != self and not gui_input.is_connected(_on_panel_raise_input):
		gui_input.connect(_on_panel_raise_input)
	# Background should not steal clicks outside the chrome.
	var bg := get_node_or_null("Background") as Control
	if bg != null:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(true)


func bring_to_front() -> void:
	_stack_z = maxi(_stack_z + 1, 100)
	z_index = _stack_z
	var p := get_parent()
	if p != null:
		p.move_child(self, p.get_child_count() - 1)


func _on_panel_raise_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			bring_to_front()


func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				bring_to_front()
				_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				accept_event()
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		# Keep fully on-screen when possible.
		var vp := get_viewport()
		if vp != null:
			var r := vp.get_visible_rect()
			var s := size
			if s.x < 8.0:
				s = custom_minimum_size
			global_position.x = clampf(global_position.x, r.position.x + 4.0, r.end.x - maxf(s.x, 80.0) - 4.0)
			global_position.y = clampf(global_position.y, r.position.y + 48.0, r.end.y - maxf(s.y, 80.0) - 4.0)
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	# Esc closes the topmost focused overlay of this type when this panel is frontmost.
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if _is_frontmost_draggable():
				queue_free()
				get_viewport().set_input_as_handled()


func _is_frontmost_draggable() -> bool:
	var p := get_parent()
	if p == null:
		return true
	var best_z := z_index
	var best: Node = self
	for c in p.get_children():
		if c is DraggablePanel and is_instance_valid(c) and (c as Control).visible:
			var d := c as DraggablePanel
			if d.z_index >= best_z:
				best_z = d.z_index
				best = d
	return best == self
