# scripts/ui/LeaderReplacementPickerPopup.gd
class_name LeaderReplacementPickerPopup
extends Window

signal replacement_completed(request: Dictionary, new_leader_id: String, left_vacant: bool)

@export var request_id: String = ""

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var context_label: Label = $MarginContainer/VBoxContainer/ContextLabel
@onready var recommended_label: Label = $MarginContainer/VBoxContainer/RecommendedLabel
@onready var leader_list: ItemList = $MarginContainer/VBoxContainer/LeaderList
@onready var search_edit: LineEdit = $MarginContainer/VBoxContainer/SearchEdit
@onready var auto_button: Button = $MarginContainer/VBoxContainer/ActionRow/AutoButton
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ActionRow/ConfirmButton
@onready var vacant_button: Button = $MarginContainer/VBoxContainer/ActionRow/VacantButton
@onready var later_button: Button = $MarginContainer/VBoxContainer/ActionRow/LaterButton

var _request: Dictionary = {}
var _candidate_rows: Array[Dictionary] = []
var _selected_leader_id: String = ""


func _ready() -> void:
	if request_id.is_empty():
		queue_free()
		return

	_request = LeaderManager.get_leader_replacement_request(request_id)
	if _request.is_empty():
		queue_free()
		return

	visible = false
	close_requested.connect(_on_later_pressed)
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_body_label(context_label)
	RetrowaveTheme.style_body_label(recommended_label)
	RetrowaveTheme.style_search(search_edit)
	RetrowaveTheme.style_item_list(leader_list)
	RetrowaveTheme.style_primary_button(auto_button)
	RetrowaveTheme.style_primary_button(confirm_button)
	RetrowaveTheme.style_secondary_button(vacant_button)
	RetrowaveTheme.style_secondary_button(later_button)

	search_edit.placeholder_text = "Search candidates..."
	confirm_button.disabled = true
	auto_button.pressed.connect(_on_auto_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	vacant_button.pressed.connect(_on_vacant_pressed)
	later_button.pressed.connect(_on_later_pressed)
	leader_list.item_selected.connect(_on_leader_selected)
	search_edit.text_changed.connect(_on_search_changed)

	_build_header()
	_load_candidates()
	call_deferred("_present_popup")


func _present_popup() -> void:
	if not is_inside_tree():
		return
	popup_centered()
	visible = true


static func open_for_request(target_request_id: String) -> LeaderReplacementPickerPopup:
	var scene: PackedScene = load("res://scenes/ui/LeaderReplacementPickerPopup.tscn")
	if scene == null:
		push_warning("LeaderReplacementPickerPopup.tscn not found")
		return null
	var popup: LeaderReplacementPickerPopup = scene.instantiate() as LeaderReplacementPickerPopup
	if popup == null:
		return null
	popup.request_id = target_request_id
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		popup.queue_free()
		return null
	tree.root.add_child(popup)
	return popup


func _build_header() -> void:
	var departed := str(_request.get("departed_leader_name", "Commander"))
	var cause := str(_request.get("departure_cause", "departed")).replace("_", " ")
	var target := str(_request.get("target_label", "command"))
	title_label.text = "Choose Replacement"
	title = "Choose Replacement"
	context_label.text = "%s is no longer available (%s).\nVacancy: %s" % [departed, cause, target]

	var recommended_id := LeaderManager.pick_auto_replacement_leader(_request)
	if recommended_id.is_empty():
		recommended_label.text = "No automatic replacement available."
		auto_button.disabled = true
	else:
		var rec_leader := LeaderManager.get_leader(recommended_id)
		var rec_name := rec_leader.name if rec_leader != null else recommended_id
		recommended_label.text = "Recommended: %s" % rec_name
		recommended_label.modulate = Color(0.45, 0.95, 0.65)
		auto_button.text = "Assign %s" % rec_name
		auto_button.disabled = false


func _load_candidates() -> void:
	_candidate_rows = LeaderManager.get_replacement_candidates(_request)
	_selected_leader_id = ""
	confirm_button.disabled = true
	_populate_list("")


func _populate_list(search_text: String) -> void:
	var needle := search_text.strip_edges().to_lower()
	leader_list.clear()
	_selected_leader_id = ""
	confirm_button.disabled = true

	if _candidate_rows.is_empty():
		var empty_index := leader_list.add_item("No eligible replacements.")
		leader_list.set_item_metadata(empty_index, "")
		return

	for row in _candidate_rows:
		var leader_id := str(row.get("leader_id", ""))
		var leader_name := str(row.get("name", leader_id))
		if (
			not needle.is_empty()
			and needle not in leader_name.to_lower()
			and needle not in leader_id.to_lower()
		):
			continue

		var type_label := str(row.get("leader_type", "")).replace("_", " ").capitalize()
		var prefix := "★ " if bool(row.get("is_recommended", false)) else ""
		var item_text := "%s%s (%s) — Score %d" % [
			prefix,
			leader_name,
			type_label,
			int(row.get("score", 0)),
		]
		var item_index := leader_list.add_item(item_text)
		leader_list.set_item_metadata(item_index, leader_id)


func _on_search_changed(new_text: String) -> void:
	_populate_list(new_text)


func _on_leader_selected(index: int) -> void:
	_selected_leader_id = ""
	confirm_button.disabled = true
	if index < 0:
		return
	var metadata: Variant = leader_list.get_item_metadata(index)
	if metadata == null:
		return
	var leader_id := str(metadata)
	if leader_id.is_empty():
		return
	_selected_leader_id = leader_id
	confirm_button.disabled = false


func _on_auto_pressed() -> void:
	var recommended_id := LeaderManager.pick_auto_replacement_leader(_request)
	if recommended_id.is_empty():
		return
	if LeaderManager.resolve_leader_replacement(request_id, recommended_id, false):
		_finish(recommended_id, false)
	else:
		push_warning("Could not apply automatic replacement for %s" % request_id)


func _on_confirm_pressed() -> void:
	if _selected_leader_id.is_empty():
		return
	if LeaderManager.resolve_leader_replacement(request_id, _selected_leader_id, false):
		_finish(_selected_leader_id, false)


func _on_vacant_pressed() -> void:
	if LeaderManager.resolve_leader_replacement(request_id, "", true):
		_finish("", true)


func _on_later_pressed() -> void:
	replacement_completed.emit(_request.duplicate(), "", false)
	hide()
	call_deferred("queue_free")


func _finish(new_leader_id: String, left_vacant: bool) -> void:
	replacement_completed.emit(_request.duplicate(), new_leader_id, left_vacant)
	_refresh_leader_screen()
	hide()
	call_deferred("queue_free")


func _refresh_leader_screen() -> void:
	var main_screen: Node = get_tree().get_first_node_in_group("leader_screen")
	if main_screen != null and main_screen.has_method("refresh_screen"):
		main_screen.call("refresh_screen")
