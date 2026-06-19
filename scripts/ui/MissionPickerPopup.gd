# scripts/ui/MissionPickerPopup.gd
class_name MissionPickerPopup
extends Window

signal mission_assigned(agent_id: String, mission_id: String, target_tag: String)

@export var country_tag: String = "USA"
@export var agent_id: String = ""
@export var target_tag: String = ""
@export var dialog_title: String = "Select Mission"
@export var category_filter: String = ""

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var context_label: Label = $MarginContainer/VBoxContainer/ContextLabel
@onready var search_edit: LineEdit = $MarginContainer/VBoxContainer/SearchEdit
@onready var category_filter_option: OptionButton = (
	$MarginContainer/VBoxContainer/CategoryFilterRow/CategoryFilter
)
@onready var mission_list: ItemList = $MarginContainer/VBoxContainer/MissionList
@onready var detail_label: Label = $MarginContainer/VBoxContainer/DetailLabel
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/CancelButton

var _mission_rows: Array[Dictionary] = []
var _filtered_rows: Array[Dictionary] = []
var selected_mission_id: String = ""


func _ready() -> void:
	if agent_id.is_empty() or target_tag.is_empty():
		queue_free()
		return

	visible = false
	close_requested.connect(_on_cancel_pressed)
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.MAGENTA)
	RetrowaveTheme.style_body_label(context_label)
	RetrowaveTheme.style_body_label(detail_label)
	RetrowaveTheme.style_search(search_edit)
	RetrowaveTheme.style_filter_option(category_filter_option)
	RetrowaveTheme.style_item_list(mission_list)
	RetrowaveTheme.style_primary_button(confirm_button)
	RetrowaveTheme.style_secondary_button(cancel_button)

	search_edit.placeholder_text = "Search missions..."
	confirm_button.disabled = true
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	search_edit.text_changed.connect(_on_search_changed)
	mission_list.item_selected.connect(_on_mission_selected)
	category_filter_option.item_selected.connect(_on_category_filter_changed)

	_setup_category_filter()
	_update_title()
	_load_missions()
	call_deferred("_present_popup")


func _update_title() -> void:
	if not dialog_title.is_empty():
		title_label.text = dialog_title
		title = dialog_title
	else:
		title_label.text = "Select Mission"
		title = "Select Mission"

	var agent_summary := AgentManager.get_agent_summary(agent_id)
	var agent_name := str(agent_summary.get("name", agent_id))
	context_label.text = "%s operating against %s" % [agent_name, target_tag]


func _present_popup() -> void:
	if not is_inside_tree():
		return
	popup_centered()
	visible = true


static func open_picker(configure: Callable) -> MissionPickerPopup:
	var scene: PackedScene = load("res://scenes/ui/MissionPickerPopup.tscn")
	if scene == null:
		push_warning("MissionPickerPopup.tscn not found")
		return null

	var picker: MissionPickerPopup = scene.instantiate() as MissionPickerPopup
	if picker == null:
		return null

	configure.call(picker)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		picker.queue_free()
		return null
	tree.root.add_child(picker)
	return picker


func _setup_category_filter() -> void:
	category_filter_option.clear()
	category_filter_option.add_item("All Categories")
	for cat in AgentManager.get_mission_categories():
		category_filter_option.add_item(cat.capitalize())

	var pick := 0
	var needle := category_filter.strip_edges().to_lower()
	if not needle.is_empty():
		for i in range(category_filter_option.item_count):
			if category_filter_option.get_item_text(i).to_lower() == needle:
				pick = i
				break
			if category_filter_option.get_item_text(i).to_lower() == needle.capitalize():
				pick = i
				break
	category_filter_option.select(pick)


func _active_category_filter() -> String:
	if category_filter_option.selected <= 0:
		return ""
	return category_filter_option.get_item_text(category_filter_option.selected).to_lower()


func _load_missions() -> void:
	_mission_rows = AgentManager.get_eligible_missions_for_agent(agent_id, _active_category_filter())
	_filtered_rows = _mission_rows.duplicate()
	selected_mission_id = ""
	_populate_list(search_edit.text)


func _on_category_filter_changed(_index: int) -> void:
	_load_missions()


func _populate_list(search_text: String) -> void:
	var needle := search_text.strip_edges().to_lower()
	mission_list.clear()
	selected_mission_id = ""
	confirm_button.disabled = true
	detail_label.text = "Select a mission for details."

	if _filtered_rows.is_empty():
		var idx := mission_list.add_item("No eligible missions for this agent.")
		mission_list.set_item_metadata(idx, "")
		return

	for row in _filtered_rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mission_row := row as Dictionary
		var mission_id := str(mission_row.get("mission_id", ""))
		var name := str(mission_row.get("name", mission_id))
		if (
			not needle.is_empty()
			and needle not in name.to_lower()
			and needle not in mission_id.to_lower()
			and needle not in str(mission_row.get("category", "")).to_lower()
		):
			continue

		var chance_pct := int(float(mission_row.get("success_chance", 0.0)) * 100.0)
		var item_text := "%s (%s) — %d%%" % [
			name,
			mission_row.get("category", ""),
			chance_pct,
		]
		var item_index := mission_list.add_item(item_text)
		mission_list.set_item_metadata(item_index, mission_id)


func _on_search_changed(new_text: String) -> void:
	var needle := new_text.strip_edges().to_lower()
	_filtered_rows.clear()
	for row in _mission_rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mission_row := row as Dictionary
		var haystack := (
			"%s %s %s"
			% [
				str(mission_row.get("name", "")),
				str(mission_row.get("mission_id", "")),
				str(mission_row.get("category", "")),
			]
		).to_lower()
		if needle.is_empty() or needle in haystack:
			_filtered_rows.append(mission_row)
	_populate_list(new_text)


func _on_mission_selected(index: int) -> void:
	selected_mission_id = ""
	confirm_button.disabled = true
	if index < 0:
		return

	var metadata: Variant = mission_list.get_item_metadata(index)
	if metadata == null:
		return
	var mission_id := str(metadata)
	if mission_id.is_empty():
		return

	selected_mission_id = mission_id
	confirm_button.disabled = false
	_update_detail_for_mission(mission_id)


func _update_detail_for_mission(mission_id: String) -> void:
	var mission := AgentManager.get_mission_definition(mission_id)
	if mission.is_empty():
		detail_label.text = "Mission not found."
		return

	var chance_pct := 0
	for row in _mission_rows:
		if str(row.get("mission_id", "")) == mission_id:
			chance_pct = int(float(row.get("success_chance", 0.0)) * 100.0)
			break

	var preview: Dictionary = AgentMissionImpact.get_impact_preview(mission)
	var impact_block := (
		"\n\n— If successful —\n%s\n\n— Partial —\n%s\n\n— Failure —\n%s"
		% [
			preview.get("success", "—"),
			preview.get("partial", "—"),
			preview.get("failure", "—"),
		]
	)

	detail_label.text = (
		"%s\n\n%s\n\nCategory: %s\nDuration: %d months\nSuccess: ~%d%%\nDetection risk: ~%.0f%%\nRequires %s %d+%s"
		% [
			mission.get("name", mission_id),
			mission.get("description", ""),
			mission.get("category", ""),
			int(mission.get("duration_months", 0)),
			chance_pct,
			float(mission.get("detection_risk", 0.3)) * 100.0,
			mission.get("skill_requirement", "intelligence"),
			int(mission.get("min_skill_level", 1)),
			impact_block,
		]
	)


func _on_confirm_pressed() -> void:
	if selected_mission_id.is_empty():
		return

	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.mission_requires_tech_target(
		selected_mission_id
	):
		var actor_tag := country_tag
		var agent := AgentManager.get_agent(agent_id)
		if agent != null:
			actor_tag = agent.country_tag
		TechnologyMissionTargetPopup.open_picker(
			func(picker: TechnologyMissionTargetPopup) -> void:
				picker.actor_country = actor_tag
				picker.victim_country = target_tag
				picker.agent_id = agent_id
				picker.mission_id = selected_mission_id
				picker.target_selected.connect(
					_on_tech_target_picked.bind(selected_mission_id),
					CONNECT_ONE_SHOT,
				),
		)
		return

	_finalize_mission_assignment(selected_mission_id, "")


func _on_tech_target_picked(tech_id: String, mission_id: String) -> void:
	_finalize_mission_assignment(mission_id, tech_id)


func _finalize_mission_assignment(mission_id: String, tech_id: String) -> void:
	if not AgentManager.assign_agent_to_mission(agent_id, mission_id, target_tag, tech_id):
		push_warning("Could not assign mission %s" % mission_id)
		return

	mission_assigned.emit(agent_id, mission_id, target_tag)
	_refresh_agent_screen()

	if typeof(LeaderEventUI) != TYPE_NIL:
		var mission := AgentManager.get_mission_definition(mission_id)
		var agent_name := str(AgentManager.get_agent_summary(agent_id).get("name", agent_id))
		var extra := ""
		if not tech_id.is_empty() and typeof(TechnologyManager) != TYPE_NIL:
			extra = " targeting %s." % TechnologyManager.get_tech_display_name(tech_id)
		else:
			extra = "."
		LeaderEventUI.post_news(
			"Mission Assigned",
			"%s began %s in %s%s" % [
				agent_name,
				mission.get("name", mission_id),
				target_tag,
				extra,
			],
			"espionage",
		)
	hide()
	call_deferred("queue_free")


func _refresh_agent_screen() -> void:
	var main_screen: Node = get_tree().get_first_node_in_group("agent_screen")
	if main_screen != null and main_screen.has_method("refresh_screen"):
		main_screen.call("refresh_screen")


func _on_cancel_pressed() -> void:
	hide()
	call_deferred("queue_free")
