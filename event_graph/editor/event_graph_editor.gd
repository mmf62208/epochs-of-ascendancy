@tool
class_name EventGraphEditor
extends Control

## Main editor panel hosted in the Godot bottom dock.
## Implements the spec requirements:
## - Inspector integration via EditorInterface.edit_resource()
## - Type-safe connection validation
## - Context menu at mouse cursor position
## - Trigger: output allows max 1 connection
## - Variable: input allows max 1 connection, output allows multiple
## - Type mismatch connections are rejected

const EventGraphNodeScript := preload("res://event_graph/editor/event_graph_node.gd")
const PaletteScript := preload("res://event_graph/editor/node_palette.gd")

var _graph_edit: GraphEdit
var _palette: EventNodePalette
var _toolbar: HBoxContainer
var _status_bar: Label

var _current_graph: EventGraphResource = null
var _node_map: Dictionary = {}  # node_id -> EventGraphNode
var _processor: EventGraphProcessor = null

## Track the last right-click position for context menu node placement
var _last_right_click_pos: Vector2 = Vector2.ZERO

var _clipboard_nodes: Array[Dictionary] = []
var _clipboard_connections: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "EventGraph"

	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_hbox)

	_palette = PaletteScript.new()
	_palette.node_type_selected.connect(_on_palette_selection)
	root_hbox.add_child(_palette)

	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_hbox.add_child(centre)

	_build_toolbar(centre)

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	_graph_edit.right_disconnects = true
	_graph_edit.gui_input.connect(_on_graph_gui_input)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph_edit.node_selected.connect(_on_node_selected)
	_graph_edit.copy_nodes_request.connect(_on_copy_nodes_request)
	_graph_edit.paste_nodes_request.connect(_on_paste_nodes_request)
	_graph_edit.duplicate_nodes_request.connect(_on_duplicate_nodes_request)
	centre.add_child(_graph_edit)

	_status_bar = Label.new()
	_status_bar.text = "No graph loaded. Create or open a EventGraphResource."
	_status_bar.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	centre.add_child(_status_bar)


func _build_toolbar(parent: VBoxContainer) -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 6)
	parent.add_child(_toolbar)

	_add_tb_btn("New", _on_new_graph)
	_add_tb_btn("Open", _on_open_graph)
	_add_tb_btn("Save", _on_save_graph)
	_toolbar.add_child(VSeparator.new())
	_add_tb_btn("Run", _on_run_flow)
	_add_tb_btn("Stop", _on_stop_flow)
	_toolbar.add_child(VSeparator.new())
	_add_tb_btn("Center", _on_center_graph)


func _add_tb_btn(lbl: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = lbl
	btn.flat = false
	btn.pressed.connect(cb)
	_toolbar.add_child(btn)


# ── Load / Rebuild ────────────────────────────────────────────────────────────

func load_graph(res: EventGraphResource) -> void:
	if res == null:
		return
	_current_graph = res
	_current_graph.restore_after_load()
	_rebuild_canvas()
	_set_status("Loaded: " + res.graph_name)


func _rebuild_canvas() -> void:
	_graph_edit.clear_connections()

	for child in _graph_edit.get_children():
		if child is GraphNode:
			_graph_edit.remove_child(child)
			child.queue_free()
	_node_map.clear()

	if _current_graph == null:
		return

	# 1. Spawn visual nodes from the nodes array
	for data in _current_graph.nodes:
		var node_res := data as EventNodeResource
		if node_res:
			_spawn_visual_node(node_res)

	# 2. Restore connections using the name-based connection data
	for conn in _current_graph.connections:
		var from_id: String = conn.get("from_node_id", "")
		var to_id: String = conn.get("to_node_id", "")
		var from_port_name: String = conn.get("from_port", "")
		var to_port_name: String = conn.get("to_port", "")

		var from_vis: EventGraphNode = _node_map.get(from_id)
		var to_vis: EventGraphNode = _node_map.get(to_id)
		if from_vis and to_vis:
			var from_slot := _find_slot_by_name(from_vis, from_port_name, true)
			var to_slot := _find_slot_by_name(to_vis, to_port_name, false)
			if from_slot >= 0 and to_slot >= 0:
				_graph_edit.connect_node(from_vis.name, from_slot, to_vis.name, to_slot)


func _spawn_visual_node(node_res: EventNodeResource) -> EventGraphNode:
	var gn := EventGraphNodeScript.new()
	gn.name = node_res.node_id
	_graph_edit.add_child(gn)
	gn.setup(node_res)
	gn.data_changed.connect(_on_node_data_changed)
	gn.delete_requested.connect(_on_delete_node)
	gn.rebuild_requested.connect(_rebuild_canvas)
	_node_map[node_res.node_id] = gn
	return gn


## Find the slot index for a given port name.
func _find_slot_by_name(gn: EventGraphNode, port_name: String, is_output: bool) -> int:
	for i in gn._slot_map.size():
		var side_key := "right" if is_output else "left"
		var info: Dictionary = gn._slot_map[i].get(side_key, {})
		if info.get("name", "") == port_name:
			return i
	return -1


# ── New / Open / Save ─────────────────────────────────────────────────────────

func _on_new_graph() -> void:
	_current_graph = EventGraphResource.new()
	_current_graph.graph_name = "NewEventGraph"

	var start := EventNodeStart.new()
	start.graph_pos = Vector2(100, 150)
	_current_graph.add_node(start)

	_rebuild_canvas()
	_set_status("New graph created.")


func _on_open_graph() -> void:
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.tres", "EventGraph Resource")
	dialog.file_selected.connect(_on_open_file_selected)
	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.65)


func _on_open_file_selected(path: String) -> void:
	var raw_res = ResourceLoader.load(path)
	
	print("--- Load Debug ---")
	print("Path: ", path)
	print("Raw Resource: ", raw_res)
	
	#if raw_res and raw_res.get_script():
		#print("Loaded Script Path: ", raw_res.get_script().resource_path)
		#print("Expected Script Path: res://addons/event_graph/core/event_graph_resource.gd")
		#if raw_res.get_script().resource_path != "res://addons/event_graph/core/event_graph_resource.gd":
			#printerr("Error: The loaded file is not a EventGraphResource! It uses script: ", raw_res.get_script().resource_path)
			#_set_status("Error: File is not EventGraphResource. It is an older format.")
			#return
	
	var res = raw_res as EventGraphResource
	if res:
		load_graph(res)
	else:
		printerr("Cast failed even though script path matches. This might be a Godot cyclic dependency bug.")
		# Workaround for Godot cast bug: use duck typing if it has the required method
		if raw_res.has_method("restore_after_load"):
			print("Applying duck typing workaround...")
			_current_graph = raw_res
			_current_graph.restore_after_load()
			_rebuild_canvas()
			_set_status("Loaded (Workaround): " + raw_res.graph_name)
		else:
			_set_status("Error: could not load " + path)


func _on_save_graph() -> void:
	if _current_graph == null:
		_set_status("Nothing to save.")
		return

	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.tres", "EventGraph Resource")
	dialog.current_file = _current_graph.graph_name + ".tres"
	dialog.file_selected.connect(_on_save_file_selected)
	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.65)


func _on_save_file_selected(path: String) -> void:
	_current_graph.prepare_for_save()
	var err := ResourceSaver.save(_current_graph, path)
	if err == OK:
		_set_status("Saved: " + path)
	else:
		_set_status("Save failed (error %d)" % err)


func _on_center_graph() -> void:
	_graph_edit.scroll_offset = Vector2.ZERO


# ── Connection Handling (Type-Safe) ───────────────────────────────────────────

func _on_connection_request(from_node_name: StringName, from_port: int,
		to_node_name: StringName, to_port: int) -> void:
	if _current_graph == null:
		return

	var from_vis: EventGraphNode = _node_map.get(str(from_node_name))
	var to_vis: EventGraphNode = _node_map.get(str(to_node_name))
	if from_vis == null or to_vis == null:
		return

	var from_kind := from_vis.get_port_kind(from_port, true)
	var to_kind := to_vis.get_port_kind(to_port, false)

	# ── Rule: Cannot connect trigger to variable or vice versa ────────
	if from_kind != to_kind:
		_set_status("Cannot connect: trigger ↁEvariable mismatch.")
		return

	# ── Type check for variable ports ─────────────────────────────────
	if from_kind == "variable":
		var from_type := from_vis.get_port_type_id(from_port, true)
		var to_type := to_vis.get_port_type_id(to_port, false)
		if from_type != to_type and from_type != TYPE_NIL and to_type != TYPE_NIL:
			_set_status("Type mismatch: cannot connect %s to %s." % [
				_type_name(from_type), _type_name(to_type)])
			return

	# ── Enforce connection rules ──────────────────────────────────────
	var from_port_name := from_vis.get_port_name(from_port, true)
	var to_port_name := to_vis.get_port_name(to_port, false)
	var from_node_id := str(from_node_name)
	var to_node_id := str(to_node_name)

	if from_kind == "trigger":
		# Trigger output: max 1 connection. Remove existing.
		_remove_existing_connections_from(from_node_id, from_port_name, from_node_name, from_port)
	else:
		# Variable input: max 1 connection. Remove existing on the input side.
		_remove_existing_connections_to(to_node_id, to_port_name, to_node_name, to_port)

	# Make the connection
	_graph_edit.connect_node(from_node_name, from_port, to_node_name, to_port)
	_current_graph.add_connection(from_node_id, from_port_name, to_node_id, to_port_name)


func _remove_existing_connections_from(node_id: String, port_name: String,
		vis_name: StringName, slot_idx: int) -> void:
	var list := _graph_edit.get_connection_list()
	for edge in list:
		if str(edge["from_node"]) == str(vis_name) and edge["from_port"] == slot_idx:
			_graph_edit.disconnect_node(edge["from_node"], edge["from_port"],
					edge["to_node"], edge["to_port"])
			# Find the target port name
			var target_vis: EventGraphNode = _node_map.get(str(edge["to_node"]))
			if target_vis:
				var target_port_name := target_vis.get_port_name(edge["to_port"], false)
				_current_graph.remove_connection(node_id, port_name,
						str(edge["to_node"]), target_port_name)


func _remove_existing_connections_to(node_id: String, port_name: String,
		vis_name: StringName, slot_idx: int) -> void:
	var list := _graph_edit.get_connection_list()
	for edge in list:
		if str(edge["to_node"]) == str(vis_name) and edge["to_port"] == slot_idx:
			_graph_edit.disconnect_node(edge["from_node"], edge["from_port"],
					edge["to_node"], edge["to_port"])
			var source_vis: EventGraphNode = _node_map.get(str(edge["from_node"]))
			if source_vis:
				var source_port_name := source_vis.get_port_name(edge["from_port"], true)
				_current_graph.remove_connection(str(edge["from_node"]), source_port_name,
						node_id, port_name)


func _on_disconnection_request(from_node_name: StringName, from_port: int,
		to_node_name: StringName, to_port: int) -> void:
	if _current_graph == null:
		return

	var from_vis: EventGraphNode = _node_map.get(str(from_node_name))
	var to_vis: EventGraphNode = _node_map.get(str(to_node_name))
	if from_vis == null or to_vis == null:
		return

	var from_port_name := from_vis.get_port_name(from_port, true)
	var to_port_name := to_vis.get_port_name(to_port, false)

	_graph_edit.disconnect_node(from_node_name, from_port, to_node_name, to_port)
	_current_graph.remove_connection(str(from_node_name), from_port_name,
			str(to_node_name), to_port_name)


func _type_name(t: int) -> String:
	match t:
		TYPE_BOOL: return "Bool"
		TYPE_INT: return "Int"
		TYPE_FLOAT: return "Float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_NIL: return "Any"
		_: return "Unknown"


# ── Inspector Integration ────────────────────────────────────────────────────

func _on_node_selected(node: Node) -> void:
	if node is EventGraphNode:
		var gn := node as EventGraphNode
		if gn.node_res and Engine.is_editor_hint():
			# Show the EventNodeResource in Godot's Inspector
			if EditorInterface:
				EditorInterface.edit_resource(gn.node_res)


# ── Context Menu ─────────────────────────────────────────────────────────────

func _on_graph_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_last_right_click_pos = event.position
			_show_context_menu(event.global_position)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			if _graph_edit.has_method("get_closest_connection_at_point"):
				var conn: Dictionary = _graph_edit.get_closest_connection_at_point(event.position)
				if not conn.is_empty():
					_on_disconnection_request(conn.get("from_node", ""), conn.get("from_port", 0), 
							conn.get("to_node", ""), conn.get("to_port", 0))
					_graph_edit.accept_event()


func _show_context_menu(at_screen_pos: Vector2) -> void:
	var popup := PopupPanel.new()
	
	var palette := PaletteScript.new()
	palette.is_popup = true
	popup.add_child(palette)
	
	palette.node_type_selected.connect(func(key: String) -> void:
		_add_node_at_mouse(key)
		popup.hide()
		popup.queue_free()
	)
	
	# Close on click-away is handled by PopupPanel naturally in many cases,
	# but we ensure it's removed from the tree when hidden.
	popup.popup_hide.connect(popup.queue_free)
	
	get_tree().root.add_child(popup)
	popup.popup(Rect2i(at_screen_pos, Vector2i.ZERO))


func _on_palette_selection(name_key: String) -> void:
	_add_node_at_center(name_key)


## Add node at the position where the user right-clicked.
func _add_node_at_mouse(name_key: String) -> void:
	if _current_graph == null:
		_on_new_graph()

	var node_res: EventNodeResource = EventNodeRegistry.create_node(name_key)
	if node_res == null:
		return
	node_res.ensure_node_id()

	# Convert the click position to graph coordinates
	node_res.graph_pos = (_last_right_click_pos + _graph_edit.scroll_offset) / _graph_edit.zoom

	_current_graph.add_node(node_res)
	_spawn_visual_node(node_res)
	_set_status("Added: " + node_res.title)


func _add_node_at_center(name_key: String) -> void:
	if _current_graph == null:
		_on_new_graph()

	var node_res: EventNodeResource = EventNodeRegistry.create_node(name_key)
	if node_res == null:
		return
	node_res.ensure_node_id()

	node_res.graph_pos = _graph_edit.scroll_offset + _graph_edit.size * 0.5 - Vector2(80, 60)

	_current_graph.add_node(node_res)
	_spawn_visual_node(node_res)
	_set_status("Added: " + node_res.title)


# ── Node Changes / Deletion ──────────────────────────────────────────────────

func _on_node_data_changed(_data: EventNodeResource) -> void:
	if _current_graph:
		_current_graph.emit_changed()


func _on_delete_nodes_request(node_names: Array[StringName]) -> void:
	for n_name in node_names:
		_on_delete_node(str(n_name))


func _on_delete_node(node_id: String) -> void:
	if _current_graph == null:
		return

	var gn := _node_map.get(node_id) as GraphNode
	if gn:
		var list := _graph_edit.get_connection_list()
		for edge in list:
			if str(edge["from_node"]) == node_id or str(edge["to_node"]) == node_id:
				_graph_edit.disconnect_node(edge["from_node"], edge["from_port"],
						edge["to_node"], edge["to_port"])

		if gn.get_parent() == _graph_edit:
			_graph_edit.remove_child(gn)
		gn.queue_free()
		_node_map.erase(node_id)

	_current_graph.remove_node(node_id)
	_current_graph.sanitize()
	_set_status("Deleted node.")


# ── Copy / Paste / Duplicate ─────────────────────────────────────────────────

func _on_copy_nodes_request() -> void:
	if _current_graph == null:
		return
	_clipboard_nodes.clear()
	_clipboard_connections.clear()
	
	var selected_ids := {}
	for child in _graph_edit.get_children():
		if child is GraphNode and child.selected:
			var gn := child as EventGraphNode
			if gn and gn.node_res:
				_clipboard_nodes.append(_current_graph._node_to_record(gn.node_res))
				selected_ids[gn.node_res.node_id] = true
				
	for conn in _current_graph.connections:
		if selected_ids.has(conn.get("from_node_id", "")) and selected_ids.has(conn.get("to_node_id", "")):
			_clipboard_connections.append(conn.duplicate(true))
			
	_set_status("Copied %d nodes." % _clipboard_nodes.size())


func _on_paste_nodes_request() -> void:
	if _current_graph == null or _clipboard_nodes.is_empty():
		return
		
	for child in _graph_edit.get_children():
		if child is GraphNode:
			child.selected = false
			
	var old_to_new_ids := {}
	var center := Vector2.ZERO
	for rec in _clipboard_nodes:
		center += rec.get("graph_pos", Vector2.ZERO)
	if _clipboard_nodes.size() > 0:
		center /= _clipboard_nodes.size()
	
	var mouse_pos = (_graph_edit.scroll_offset + _graph_edit.get_local_mouse_position()) / _graph_edit.zoom
	
	var new_nodes := []
	for rec in _clipboard_nodes:
		var new_res = _current_graph._node_from_record(rec)
		if new_res:
			var old_id = new_res.node_id
			new_res.node_id = EventNodeResource.generate_node_id()
			new_res.graph_pos = mouse_pos + (new_res.graph_pos - center)
			old_to_new_ids[old_id] = new_res.node_id
			_current_graph.add_node(new_res)
			new_nodes.append(new_res)
			
	for conn in _clipboard_connections:
		var from_id = conn.get("from_node_id", "")
		var to_id = conn.get("to_node_id", "")
		if old_to_new_ids.has(from_id) and old_to_new_ids.has(to_id):
			_current_graph.add_connection(
				old_to_new_ids[from_id], conn.get("from_port", ""),
				old_to_new_ids[to_id], conn.get("to_port", "")
			)
			
	_rebuild_canvas()
	for child in _graph_edit.get_children():
		if child is EventGraphNode and child.node_res in new_nodes:
			child.selected = true
			
	_set_status("Pasted %d nodes." % new_nodes.size())


func _on_duplicate_nodes_request() -> void:
	if _current_graph == null:
		return
	
	var selected_ids := {}
	var nodes_to_dup := []
	for child in _graph_edit.get_children():
		if child is GraphNode and child.selected:
			var gn := child as EventGraphNode
			if gn and gn.node_res:
				nodes_to_dup.append(_current_graph._node_to_record(gn.node_res))
				selected_ids[gn.node_res.node_id] = true
				child.selected = false
				
	if nodes_to_dup.is_empty():
		return
		
	var old_to_new_ids := {}
	var new_nodes := []
	for rec in nodes_to_dup:
		var new_res = _current_graph._node_from_record(rec)
		if new_res:
			var old_id = new_res.node_id
			new_res.node_id = EventNodeResource.generate_node_id()
			new_res.graph_pos += Vector2(40, 40)
			old_to_new_ids[old_id] = new_res.node_id
			_current_graph.add_node(new_res)
			new_nodes.append(new_res)
			
	for conn in _current_graph.connections:
		if selected_ids.has(conn.get("from_node_id", "")) and selected_ids.has(conn.get("to_node_id", "")):
			_current_graph.add_connection(
				old_to_new_ids[conn.get("from_node_id", "")], conn.get("from_port", ""),
				old_to_new_ids[conn.get("to_node_id", "")], conn.get("to_port", "")
			)
			
	_rebuild_canvas()
	for child in _graph_edit.get_children():
		if child is EventGraphNode and child.node_res in new_nodes:
			child.selected = true
			
	_set_status("Duplicated %d nodes." % new_nodes.size())

# ── Run / Stop ────────────────────────────────────────────────────────────────

func _on_run_flow() -> void:
	if _current_graph == null:
		_set_status("No graph loaded.")
		return
	if _processor and _processor.is_running():
		_set_status("Already running.")
		return

	_processor = EventGraphProcessor.new(_current_graph, null)
	add_child(_processor)

	_processor.node_executed.connect(_on_exec_node)
	_processor.flow_started.connect(func() -> void: _set_status("Running..."))
	_processor.flow_finished.connect(_on_exec_finished)
	_processor.flow_error.connect(func(msg: String) -> void: _set_status("Error: " + msg))

	_processor.execute()


func _on_stop_flow() -> void:
	if _processor:
		_processor.stop()
		_set_status("Stopped.")


func _on_exec_node(node_id: String) -> void:
	for id in _node_map:
		_node_map[id].set_executing(id == node_id)


func _on_exec_finished() -> void:
	_set_status("Flow finished.")
	for id in _node_map:
		_node_map[id].set_executing(false)
	if _processor:
		_processor.queue_free()
		_processor = null


func _set_status(msg: String) -> void:
	if _status_bar:
		_status_bar.text = msg
