# scripts/ui/TechnologyGraphView.gd
class_name TechnologyGraphView
extends Control

## Pan/zoom research graph: nodes laid out by column/row from technology data.

signal node_selected(tech_id: String)

const NODE_WIDTH := 148.0
const NODE_HEIGHT := 64.0
const COL_GAP := 44.0
const ROW_GAP := 30.0
const CANVAS_PAD := 28.0
const MIN_ZOOM := 0.45
const MAX_ZOOM := 1.8

var _graph_nodes: Array[Dictionary] = []
var _graph_edges: Array[Dictionary] = []
var _selected_id: String = ""
var _zoom: float = 1.0
var _pan_offset: Vector2 = Vector2.ZERO
var _panning: bool = false
var _pan_anchor: Vector2 = Vector2.ZERO
var _node_panels: Dictionary = {}

@onready var _viewport: Control = $GraphViewport
@onready var _content: Control = $GraphViewport/GraphContent
@onready var _edges: Control = $GraphViewport/GraphContent/EdgeLayer
@onready var _nodes_root: Control = $GraphViewport/GraphContent/NodesRoot


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _edges:
		_edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edges.set_script(load("res://scripts/ui/TechnologyGraphEdgeLayer.gd"))
	if _viewport:
		_viewport.mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_zoom(_zoom * 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_zoom(_zoom / 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_pan_anchor = mb.position - _pan_offset
			accept_event()
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		_pan_offset = mm.position - _pan_anchor
		_apply_transform()
		accept_event()


func set_graph_data(
	nodes: Array,
	edges: Array,
	selected_tech_id: String = "",
) -> void:
	_graph_nodes.clear()
	_graph_edges.clear()
	for raw in nodes:
		if typeof(raw) == TYPE_DICTIONARY:
			_graph_nodes.append((raw as Dictionary).duplicate())
	for raw in edges:
		if typeof(raw) == TYPE_DICTIONARY:
			_graph_edges.append((raw as Dictionary).duplicate())
	_selected_id = selected_tech_id
	_rebuild_nodes()
	_center_on_graph()


func reset_view() -> void:
	_zoom = 1.0
	_pan_offset = Vector2.ZERO
	_apply_transform()


func _apply_zoom(new_zoom: float, focal: Vector2) -> void:
	var clamped := clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(clamped, _zoom):
		return
	var before := (focal - _pan_offset) / _zoom
	_zoom = clamped
	var after := before * _zoom
	_pan_offset = focal - after
	_apply_transform()


func _apply_transform() -> void:
	if _content == null:
		return
	_content.scale = Vector2(_zoom, _zoom)
	_content.position = _pan_offset
	if _edges:
		_edges.queue_redraw()


func _node_position(entry: Dictionary) -> Vector2:
	var col := int(entry.get("column", 0))
	var row := int(entry.get("row", 0))
	return Vector2(
		CANVAS_PAD + col * (NODE_WIDTH + COL_GAP),
		CANVAS_PAD + row * (NODE_HEIGHT + ROW_GAP),
	)


func _graph_canvas_size() -> Vector2:
	var max_x := CANVAS_PAD + NODE_WIDTH
	var max_y := CANVAS_PAD + NODE_HEIGHT
	for entry in _graph_nodes:
		var pos := _node_position(entry)
		max_x = maxf(max_x, pos.x + NODE_WIDTH + CANVAS_PAD)
		max_y = maxf(max_y, pos.y + NODE_HEIGHT + CANVAS_PAD)
	return Vector2(max_x, max_y)


func _center_on_graph() -> void:
	if _content == null or _viewport == null:
		return
	var canvas := _graph_canvas_size()
	_content.custom_minimum_size = canvas
	_content.size = canvas
	var view_size := _viewport.size
	if view_size.x < 1.0 or view_size.y < 1.0:
		return
	_zoom = 1.0
	_pan_offset = (view_size - canvas) * 0.5
	_pan_offset.y = maxf(_pan_offset.y, 8.0)
	_apply_transform()


func _rebuild_nodes() -> void:
	if _nodes_root == null:
		return
	for child in _nodes_root.get_children():
		child.queue_free()
	_node_panels.clear()

	for entry in _graph_nodes:
		var tech_id := str(entry.get("tech_id", ""))
		var panel := _create_node_panel(entry)
		var pos := _node_position(entry)
		panel.position = pos
		panel.custom_minimum_size = Vector2(NODE_WIDTH, NODE_HEIGHT)
		panel.size = Vector2(NODE_WIDTH, NODE_HEIGHT)
		_nodes_root.add_child(panel)
		_node_panels[tech_id] = panel

	if _edges:
		_edges.custom_minimum_size = _graph_canvas_size()
		_edges.size = _edges.custom_minimum_size
		_edges.queue_redraw()


func _create_node_panel(entry: Dictionary) -> PanelContainer:
	var tech_id := str(entry.get("tech_id", ""))
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel_flat(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_node_gui_input.bind(tech_id))

	var status := str(entry.get("status", "locked"))
	var selected := tech_id == _selected_id
	_apply_node_style(panel, status, selected)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	var title := Label.new()
	title.text = str(entry.get("name", tech_id))
	title.clip_text = true
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetrowaveTheme.style_body_label(title)
	title.add_theme_font_size_override("font_size", 12)
	box.add_child(title)

	var sub := Label.new()
	sub.text = status.replace("_", " ").capitalize()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetrowaveTheme.style_body_label(sub)
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	box.add_child(sub)

	if status == "in_progress":
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = float(entry.get("progress_pct", 0.0))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		box.add_child(bar)

	return panel


func _apply_node_style(panel: PanelContainer, status: String, selected: bool) -> void:
	if selected:
		panel.modulate = Color(1.0, 0.95, 0.75)
	elif status == "available":
		panel.modulate = Color(0.85, 1.0, 0.9)
	elif status == "in_progress":
		panel.modulate = Color(0.75, 0.9, 1.0)
	elif status == "completed":
		panel.modulate = Color(0.7, 0.85, 0.7)
	elif status == "compromised":
		panel.modulate = Color(1.0, 0.55, 0.55)
	else:
		panel.modulate = Color(0.55, 0.55, 0.62)


func _on_node_gui_input(event: InputEvent, tech_id: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_selected_id = tech_id
			node_selected.emit(tech_id)
			_rebuild_nodes()


func paint_edges(canvas: Control) -> void:
	if canvas == null:
		return
	var centers: Dictionary = {}
	for entry in _graph_nodes:
		var tid := str(entry.get("tech_id", ""))
		var pos := _node_position(entry)
		centers[tid] = pos + Vector2(NODE_WIDTH * 0.5, NODE_HEIGHT * 0.5)

	for edge in _graph_edges:
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if not centers.has(from_id) or not centers.has(to_id):
			continue
		var a: Vector2 = centers[from_id]
		var b: Vector2 = centers[to_id]
		var done := bool(edge.get("satisfied", false))
		var color := Color(0.35, 0.75, 0.95, 0.85) if done else Color(0.45, 0.45, 0.55, 0.7)
		canvas.draw_line(a, b, color, 2.0, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_center_on_graph")
