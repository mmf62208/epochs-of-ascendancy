# scripts/ui/RetirementOfferPopup.gd
class_name RetirementOfferPopup
extends Window

## Emitted after the player chooses and LeaderManager.resolve_retirement runs.
## outcome: "honors" | "stayed" | "retired_anyway"
signal retirement_completed(leader_id: String, outcome: String)

@export var leader_id: String = ""

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var leader_info_label: Label = $MarginContainer/VBoxContainer/LeaderInfoLabel
@onready var description_label: Label = $MarginContainer/VBoxContainer/DescriptionLabel
@onready var retire_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/RetireButton
@onready var stay_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/StayButton
@onready var note_label: Label = $MarginContainer/VBoxContainer/NoteLabel

var leader: Leader


func _ready() -> void:
	if leader_id.is_empty():
		queue_free()
		return

	leader = LeaderManager.get_leader(leader_id)
	if leader == null:
		queue_free()
		return

	visible = false
	close_requested.connect(_on_close_blocked)
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.MAGENTA)
	RetrowaveTheme.style_column_header(leader_info_label)
	RetrowaveTheme.style_body_label(description_label)
	RetrowaveTheme.style_body_label(note_label)
	RetrowaveTheme.style_secondary_button(retire_button)
	RetrowaveTheme.style_primary_button(stay_button)

	_setup_ui()
	retire_button.pressed.connect(_on_retire_pressed)
	stay_button.pressed.connect(_on_stay_pressed)
	call_deferred("_present_popup")


func _on_close_blocked() -> void:
	pass


func _present_popup() -> void:
	if not is_inside_tree():
		return
	popup_centered()
	visible = true


func _setup_ui() -> void:
	title = "Leadership Transition"
	title_label.text = "A Respected Commander Considers Retirement"

	var age := LeaderManager.get_leader_age(leader)
	var role_name := leader.leader_type.replace("_", " ").capitalize()
	leader_info_label.text = "%s (%d) — %s" % [leader.name, age, role_name]

	description_label.text = (
		"%s has served with distinction. "
		% leader.name
		+ "They are considering stepping down to spend more time with family and reflect on their legacy."
	)

	note_label.text = (
		"Retiring with honors grants +%.0f prestige and +%.0f unity. "
		% [
			LeaderManager.RETIREMENT_HONORS_PRESTIGE,
			LeaderManager.RETIREMENT_HONORS_UNITY,
		]
		+ "Asking them to stay may succeed (~65%% chance) but increases strain next year. "
		+ "Their position will be freed if they leave."
	)


func _on_retire_pressed() -> void:
	LeaderManager.resolve_retirement(leader_id, true, false)
	retirement_completed.emit(leader_id, "honors")
	hide()
	call_deferred("queue_free")


func _on_stay_pressed() -> void:
	var stayed := LeaderManager.resolve_retirement(leader_id, false, true)
	if stayed:
		print("%s agreed to stay one more year." % leader.name)
		retirement_completed.emit(leader_id, "stayed")
	else:
		print("%s has decided to retire anyway." % leader.name)
		retirement_completed.emit(leader_id, "retired_anyway")
	hide()
	call_deferred("queue_free")


static func open_for_leader(target_leader_id: String) -> RetirementOfferPopup:
	var scene: PackedScene = load("res://scenes/ui/RetirementOfferPopup.tscn")
	if scene == null:
		push_warning("RetirementOfferPopup.tscn not found")
		return null

	var retirement_popup: RetirementOfferPopup = scene.instantiate() as RetirementOfferPopup
	if retirement_popup == null:
		return null

	retirement_popup.leader_id = target_leader_id
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		retirement_popup.queue_free()
		return null
	tree.root.add_child(retirement_popup)
	return retirement_popup
