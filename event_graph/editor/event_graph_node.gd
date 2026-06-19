@tool
class_name EventGraphNode
extends GraphNode

## Editor visual representation of a EventNodeResource.
## Dynamically builds ports (trigger + variable) and inline property controls.
## Acts as a proxy  Eall data lives in the EventNodeResource.

signal data_changed(node_res: EventNodeResource)
signal delete_requested(node_id: String)
signal rebuild_requested()

var CATEGORY_COLORS := {
	"Flow":   Color(0.20, 0.55, 0.90),
	"Logic":  Color(0.90, 0.65, 0.10),
	"Action": Color(0.20, 0.75, 0.45),
	"Event":  Color(0.80, 0.25, 0.25),
	"Data": Color(0.23, 0.23, 0.23, 1.0),
	"Utility":Color()
}

## All ports use the same GraphEdit type so connection_request always fires.
## We do our own validation in EventGraphEditor._on_connection_request().
const UNIFIED_PORT_TYPE := 0

## Visual colors by kind / Variant.Type
var TRIGGER_COLOR := Color(1.0, 1.0, 1.0)

var VAR_TYPE_COLORS := {
	TYPE_BOOL:    Color(0.80, 0.20, 0.20),
	TYPE_INT:     Color(0.20, 0.60, 0.80),
	TYPE_FLOAT:   Color(0.30, 0.80, 0.30),
	TYPE_STRING:  Color(0.80, 0.70, 0.20),
	TYPE_VECTOR2: Color(0.60, 0.40, 0.80),
	TYPE_VECTOR3: Color(0.80, 0.40, 0.60),
	TYPE_NIL:     Color(0.60, 0.60, 0.60),
}

var node_res: EventNodeResource = null
var _prop_controls: Dictionary = {}

## Port mapping: slot_index -> { "left": {...}, "right": {...} }
## Each side dict: { "kind": "trigger"/"variable", "name": String, "type": int }
var _slot_map: Array[Dictionary] = []


func setup(data: EventNodeResource) -> void:
	node_res = data
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_prop_controls.clear()
	_slot_map.clear()

	title = node_res.title
	position_offset = node_res.graph_pos

	# Title bar color
	var cat_color: Color = CATEGORY_COLORS.get(node_res.category, Color(0.45, 0.45, 0.45))
	var sb := StyleBoxFlat.new()
	sb.bg_color = cat_color
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	add_theme_stylebox_override("titlebar", sb)

	# ── Build port rows ──────────────────────────────────────────────────
	var left_ports: Array[Dictionary] = []
	var right_ports: Array[Dictionary] = []

	# Trigger inputs (left side)
	for tname in node_res.get_trigger_inputs():
		left_ports.append({"kind": "trigger", "name": tname, "type": TYPE_NIL})

	# Variable inputs (left side)
	for vdef in node_res.get_variable_inputs():
		left_ports.append({"kind": "variable", "name": vdef.get("name", ""), "type": vdef.get("type", TYPE_NIL)})

	# Trigger outputs (right side)
	for tname in node_res.get_trigger_outputs():
		right_ports.append({"kind": "trigger", "name": tname, "type": TYPE_NIL})

	# Variable outputs (right side)
	for vdef in node_res.get_variable_outputs():
		right_ports.append({"kind": "variable", "name": vdef.get("name", ""), "type": vdef.get("type", TYPE_NIL)})

	var max_rows := maxi(left_ports.size(), right_ports.size())
	if max_rows == 0:
		max_rows = 1

	for i in max_rows:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var has_left := i < left_ports.size()
		var has_right := i < right_ports.size()

		# Left label
		var lbl_left := Label.new()
		lbl_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if has_left:
			var prefix := "▶ " if left_ports[i]["kind"] == "trigger" else ""
			lbl_left.text = prefix + str(left_ports[i]["name"])
		row.add_child(lbl_left)

		# Right label
		var lbl_right := Label.new()
		lbl_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if has_right:
			var suffix := " ▶" if right_ports[i]["kind"] == "trigger" else ""
			lbl_right.text = str(right_ports[i]["name"]) + suffix
		row.add_child(lbl_right)

		add_child(row)

		# Determine colors (visual only  Etype check is in editor callback)
		var left_color := Color.WHITE
		var right_color := Color.WHITE

		if has_left:
			if left_ports[i]["kind"] == "trigger":
				left_color = TRIGGER_COLOR
			else:
				left_color = VAR_TYPE_COLORS.get(left_ports[i]["type"], Color(0.6, 0.6, 0.6))

		if has_right:
			if right_ports[i]["kind"] == "trigger":
				right_color = TRIGGER_COLOR
			else:
				right_color = VAR_TYPE_COLORS.get(right_ports[i]["type"], Color(0.6, 0.6, 0.6))

		# Use UNIFIED_PORT_TYPE for all ports so connection_request always fires
		set_slot(i, has_left, UNIFIED_PORT_TYPE, left_color,
				has_right, UNIFIED_PORT_TYPE, right_color)

		# Store slot mapping
		_slot_map.append({
			"left": left_ports[i] if has_left else {},
			"right": right_ports[i] if has_right else {},
		})

	# ── Inline property controls ─────────────────────────────────────────
	if not node_res.properties.is_empty():
		var has_visible_props := false
		for key in node_res.properties.keys():
			if not key.begins_with("_"):
				has_visible_props = true
				break
				
		if has_visible_props:
			add_child(HSeparator.new())
			for key in node_res.properties.keys():
				if key.begins_with("_"):
					continue
				var val = node_res.properties[key]
				var row2 := HBoxContainer.new()
				row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL

				var lbl := Label.new()
				lbl.text = key.capitalize()
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lbl.custom_minimum_size.x = 80
				row2.add_child(lbl)

				var ctrl: Control = _make_control(key, val)
				row2.add_child(ctrl)
				_prop_controls[key] = ctrl
				add_child(row2)

	# ── Custom Actions ───────────────────────────────────────────────────
	if node_res.has_method("get_custom_actions"):
		var actions: Array = node_res.get_custom_actions()
		if actions.size() > 0:
			add_child(HSeparator.new())
			for action in actions:
				var action_btn := Button.new()
				action_btn.text = action.get("label", "Action")
				action_btn.pressed.connect(func() -> void:
					node_res.call(action.get("method", ""))
					node_res.emit_changed()
					data_changed.emit(node_res)
					rebuild_requested.emit()
				)
				add_child(action_btn)

	# ── Delete button ────────────────────────────────────────────────────
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.tooltip_text = "Delete node"
	del_btn.flat = true
	del_btn.pressed.connect(_on_delete_pressed)
	add_child(del_btn)

	position_offset_changed.connect(_on_position_changed)


## Get the port name for a given slot index and side.
func get_port_name(slot_idx: int, is_output: bool) -> String:
	if slot_idx < 0 or slot_idx >= _slot_map.size():
		return ""
	var side_key := "right" if is_output else "left"
	var info: Dictionary = _slot_map[slot_idx].get(side_key, {})
	return str(info.get("name", ""))


## Get the port kind ("trigger" or "variable") for a given slot.
func get_port_kind(slot_idx: int, is_output: bool) -> String:
	if slot_idx < 0 or slot_idx >= _slot_map.size():
		return ""
	var side_key := "right" if is_output else "left"
	var info: Dictionary = _slot_map[slot_idx].get(side_key, {})
	return str(info.get("kind", ""))


## Get the port Variant.Type for a given slot.
func get_port_type_id(slot_idx: int, is_output: bool) -> int:
	if slot_idx < 0 or slot_idx >= _slot_map.size():
		return TYPE_NIL
	var side_key := "right" if is_output else "left"
	var info: Dictionary = _slot_map[slot_idx].get(side_key, {})
	return int(info.get("type", TYPE_NIL))


func _make_control(key: String, val: Variant) -> Control:
	match typeof(val):
		TYPE_FLOAT, TYPE_INT:
			var spin := SpinBox.new()
			spin.value = float(val)
			spin.step = 0.01 if typeof(val) == TYPE_FLOAT else 1.0
			spin.min_value = -9999.0
			spin.max_value = 9999.0
			spin.allow_greater = true
			spin.custom_minimum_size.x = 100
			spin.value_changed.connect(func(v: float) -> void:
				node_res.properties[key] = v if typeof(val) == TYPE_FLOAT else int(v)
				node_res.emit_changed()
				data_changed.emit(node_res)
			)
			return spin

		TYPE_BOOL:
			var chk := CheckBox.new()
			chk.button_pressed = bool(val)
			chk.toggled.connect(func(v: bool) -> void:
				node_res.properties[key] = v
				node_res.emit_changed()
				data_changed.emit(node_res)
			)
			return chk

		TYPE_DICTIONARY:
			if val.has("options") and val.has("selected"):
				var opt := OptionButton.new()
				var options: Array = val["options"]
				for i in options.size():
					opt.add_item(str(options[i]), i)
				opt.select(int(val["selected"]))
				opt.item_selected.connect(func(idx: int) -> void:
					var new_dict = val.duplicate()
					new_dict["selected"] = idx
					node_res.properties[key] = new_dict
					node_res.emit_changed()
					data_changed.emit(node_res)
					rebuild_requested.emit()
				)
				return opt
			var le := LineEdit.new()
			le.text = str(val)
			le.editable = false
			return le

		_:
			var le := LineEdit.new()
			le.text = str(val)
			le.custom_minimum_size.x = 100
			le.text_submitted.connect(func(v: String) -> void:
				node_res.properties[key] = v
				node_res.emit_changed()
				data_changed.emit(node_res)
			)
			return le


func _on_position_changed() -> void:
	if node_res != null:
		node_res.graph_pos = position_offset


func _on_delete_pressed() -> void:
	delete_requested.emit(node_res.node_id)


func set_executing(active: bool) -> void:
	var sb := StyleBoxFlat.new()
	var cat_color: Color = CATEGORY_COLORS.get(node_res.category, Color(0.45, 0.45, 0.45))
	sb.bg_color = cat_color.lightened(0.3) if active else cat_color
	sb.border_width_top = 3 if active else 0
	sb.border_color = Color.YELLOW if active else Color.TRANSPARENT
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	add_theme_stylebox_override("titlebar", sb)
