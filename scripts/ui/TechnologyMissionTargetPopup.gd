# scripts/ui/TechnologyMissionTargetPopup.gd
class_name TechnologyMissionTargetPopup
extends Window

signal target_selected(tech_id: String)

@export var actor_country: String = "USA"
@export var victim_country: String = "GER"
@export var agent_id: String = ""
@export var mission_id: String = "steal_research"

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var context_label: Label = $MarginContainer/VBoxContainer/ContextLabel
@onready var target_list: ItemList = $MarginContainer/VBoxContainer/TargetList
@onready var detail_label: Label = $MarginContainer/VBoxContainer/DetailLabel
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/CancelButton

var _targets: Array[Dictionary] = []
var _selected_tech_id: String = ""


func _ready() -> void:
	close_requested.connect(_on_cancel_pressed)
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_body_label(context_label)
	RetrowaveTheme.style_body_label(detail_label)
	RetrowaveTheme.style_item_list(target_list)
	RetrowaveTheme.style_primary_button(confirm_button)
	RetrowaveTheme.style_secondary_button(cancel_button)

	title_label.text = "Select Technology Target"
	context_label.text = "Steal research progress from %s into %s" % [victim_country, actor_country]
	confirm_button.disabled = true
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	target_list.item_selected.connect(_on_target_selected)
	_load_targets()
	call_deferred("_present_popup")


static func open_picker(configure: Callable) -> TechnologyMissionTargetPopup:
	var scene: PackedScene = load("res://scenes/ui/TechnologyMissionTargetPopup.tscn")
	if scene == null:
		return null
	var picker: TechnologyMissionTargetPopup = scene.instantiate() as TechnologyMissionTargetPopup
	if picker == null:
		return null
	configure.call(picker)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		picker.queue_free()
		return null
	tree.root.add_child(picker)
	return picker


func _present_popup() -> void:
	if is_inside_tree():
		popup_centered()
		visible = true


func _load_targets() -> void:
	target_list.clear()
	_targets.clear()
	_selected_tech_id = ""

	if typeof(TechnologyManager) == TYPE_NIL:
		target_list.add_item("(Technology system unavailable)")
		return

	_targets = TechnologyManager.get_stealable_tech_targets(actor_country, victim_country)
	if _targets.is_empty():
		target_list.add_item("(No stealable research targets — victim has no exposed tech)")
		detail_label.text = "Complete or start research on theft-target nodes first."
		return

	for entry in _targets:
		var tech_id := str(entry.get("tech_id", ""))
		var label := "%s — victim: %s" % [
			entry.get("name", tech_id),
			str(entry.get("victim_status", "")).capitalize(),
		]
		var idx := target_list.add_item(label)
		target_list.set_item_metadata(idx, tech_id)


func _on_target_selected(index: int) -> void:
	_selected_tech_id = ""
	confirm_button.disabled = true
	if index < 0:
		return
	var meta: Variant = target_list.get_item_metadata(index)
	if meta == null:
		return
	_selected_tech_id = str(meta)
	if _selected_tech_id.is_empty():
		return
	confirm_button.disabled = false
	for entry in _targets:
		if str(entry.get("tech_id", "")) == _selected_tech_id:
			detail_label.text = (
				"Steal progress on %s.\nVictim: %s · Your tree: %s"
				% [
					entry.get("name", ""),
					entry.get("victim_status", ""),
					entry.get("actor_status", ""),
				]
			)
			break


func _on_confirm_pressed() -> void:
	if _selected_tech_id.is_empty():
		return
	target_selected.emit(_selected_tech_id)
	hide()
	call_deferred("queue_free")


func _on_cancel_pressed() -> void:
	hide()
	call_deferred("queue_free")
