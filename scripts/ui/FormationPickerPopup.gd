# scripts/ui/FormationPickerPopup.gd
class_name FormationPickerPopup
extends Window

signal formation_assigned(formation_id: String)

@export var leader_id: String = ""
@export var country_tag: String = "GER"
@export var leader_name: String = ""

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var search_edit: LineEdit = $MarginContainer/VBoxContainer/SearchEdit
@onready var formation_list: ItemList = $MarginContainer/VBoxContainer/FormationList
@onready var assign_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/AssignButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/CancelButton

var available_formations: Array[Dictionary] = []
var filtered_formations: Array[Dictionary] = []
var selected_formation_id: String = ""


func _ready() -> void:
	visible = false
	close_requested.connect(_on_cancel_pressed)
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_search(search_edit)
	search_edit.placeholder_text = "Search formations..."
	RetrowaveTheme.style_item_list(formation_list)
	RetrowaveTheme.style_primary_button(assign_button)
	RetrowaveTheme.style_secondary_button(cancel_button)

	assign_button.disabled = true
	assign_button.pressed.connect(_on_assign_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	search_edit.text_changed.connect(_on_search_changed)
	formation_list.item_selected.connect(_on_formation_selected)

	_update_title()
	_load_available_formations()
	call_deferred("_present_popup")


func _present_popup() -> void:
	if not is_inside_tree():
		return
	popup_centered()
	visible = true


func _update_title() -> void:
	if leader_name.is_empty():
		title_label.text = "Assign Leader to Formation"
		title = "Assign to Formation"
	else:
		title_label.text = "Assign %s to Formation" % leader_name
		title = "Assign %s" % leader_name


func _load_available_formations() -> void:
	available_formations = LeaderManager.get_available_formations(country_tag)
	filtered_formations = available_formations.duplicate()
	selected_formation_id = ""
	assign_button.disabled = true
	_refresh_list()


func _refresh_list() -> void:
	formation_list.clear()

	if filtered_formations.is_empty():
		formation_list.add_item("(No available formations)")
		return

	for formation in filtered_formations:
		var display_name: String = str(formation.get("name", formation.get("formation_id", "")))
		var formation_type: String = str(formation.get("type", "division"))
		var category: String = str(formation.get("category", ""))
		var suffix := " [%s]" % category if not category.is_empty() else ""
		formation_list.add_item("%s (%s)%s" % [display_name, formation_type, suffix])


func _on_search_changed(new_text: String) -> void:
	var needle := new_text.strip_edges().to_lower()
	filtered_formations.clear()

	for formation in available_formations:
		var display_name: String = str(formation.get("name", "")).to_lower()
		var formation_id: String = str(formation.get("formation_id", "")).to_lower()
		var formation_type: String = str(formation.get("type", "")).to_lower()
		if (
			needle.is_empty()
			or needle in display_name
			or needle in formation_id
			or needle in formation_type
		):
			filtered_formations.append(formation)

	selected_formation_id = ""
	assign_button.disabled = true
	_refresh_list()


func _on_formation_selected(index: int) -> void:
	if index < 0 or index >= filtered_formations.size():
		selected_formation_id = ""
		assign_button.disabled = true
		return
	selected_formation_id = str(filtered_formations[index].get("formation_id", ""))
	assign_button.disabled = selected_formation_id.is_empty()


func _on_assign_pressed() -> void:
	if leader_id.is_empty() or selected_formation_id.is_empty():
		return

	var success: bool = LeaderManager.assign_leader_to_formation(leader_id, selected_formation_id)
	if success:
		formation_assigned.emit(selected_formation_id)
		var main_screen: Node = get_tree().get_first_node_in_group("leader_screen")
		if main_screen != null and main_screen.has_method("refresh_screen"):
			main_screen.call("refresh_screen")

	hide()
	call_deferred("queue_free")


func _on_cancel_pressed() -> void:
	hide()
	call_deferred("queue_free")
