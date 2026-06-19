@tool
class_name EventNodePalette
extends PanelContainer

## Left-side panel listing all available node types grouped by category.
## Uses EventNodeRegistry for auto-discovered + built-in node types.
## Double-click or "Add" button inserts a node into the graph.

signal node_type_selected(name_key: String)

const CATEGORY_COLORS := {
	"Flow":   Color(0.20, 0.55, 0.90),
	"Logic":  Color(0.90, 0.65, 0.10),
	"Action": Color(0.20, 0.75, 0.45),
	"Event":  Color(0.80, 0.25, 0.25),
}

var _tree: Tree
var _search: LineEdit
var is_popup: bool = false


func _ready() -> void:
	if not is_popup:
		custom_minimum_size = Vector2(180, 0)
	else:
		custom_minimum_size = Vector2(250, 350)

	var vbox := VBoxContainer.new()
	add_child(vbox)

	if not is_popup:
		# Header label
		var header := Label.new()
		header.text = "Node Palette"
		header.add_theme_font_size_override("font_size", 14)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(header)
		vbox.add_child(HSeparator.new())

	# Search field
	_search = LineEdit.new()
	_search.placeholder_text = "Search…"
	_search.text_changed.connect(_on_search_changed)
	_search.gui_input.connect(_on_search_gui_input)
	vbox.add_child(_search)

	# Tree
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root           = true
	_tree.columns             = 1
	_tree.item_activated.connect(_on_item_activated)
	vbox.add_child(_tree)

	if not is_popup:
		# Add button
		var add_btn := Button.new()
		add_btn.text = "+ Add to Graph"
		add_btn.pressed.connect(_on_add_pressed)
		vbox.add_child(add_btn)

		# Refresh button
		var refresh_btn := Button.new()
		refresh_btn.text = "↻ Refresh"
		refresh_btn.tooltip_text = "Rescan custom_nodes/ directory"
		refresh_btn.pressed.connect(_on_refresh_pressed)
		vbox.add_child(refresh_btn)

	_populate("")
	
	if is_popup:
		_search.grab_focus()


func _on_search_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_DOWN:
			_tree.grab_focus()
			if _tree.get_root() and _tree.get_root().get_first_child():
				_tree.get_root().get_first_child().select(0)
		elif event.keycode == KEY_ENTER:
			_on_item_activated()


func _populate(filter: String) -> void:
	_tree.clear()
	var root := _tree.create_item()

	var registry := EventNodeRegistry.get_registry()

	# Group by category
	var categories: Dictionary = {}
	for key in registry:
		var info: Dictionary = registry[key]
		if filter != "" and not info["label"].to_lower().contains(filter.to_lower()):
			continue
		var cat: String = info["category"]
		if not categories.has(cat):
			categories[cat] = []
		categories[cat].append(key)

	for cat in ["Flow", "Logic", "Action", "Event","Utility","Data"]:
		if not categories.has(cat):
			continue
		var cat_item := _tree.create_item(root)
		cat_item.set_text(0, cat)
		cat_item.set_selectable(0, false)
		var col: Color = CATEGORY_COLORS.get(cat, Color.WHITE)
		cat_item.set_custom_color(0, col)

		for key in categories[cat]:
			var child := _tree.create_item(cat_item)
			child.set_text(0, "  " + registry[key]["label"])
			child.set_metadata(0, key)
			child.set_tooltip_text(0, registry[key].get("description", ""))


func _on_search_changed(text: String) -> void:
	_populate(text)


func _on_item_activated() -> void:
	_emit_selected()


func _on_add_pressed() -> void:
	_emit_selected()


func _on_refresh_pressed() -> void:
	EventNodeRegistry.rebuild()
	_populate(_search.text if _search else "")


func _emit_selected() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var key = item.get_metadata(0)
	if key != null:
		node_type_selected.emit(str(key))
