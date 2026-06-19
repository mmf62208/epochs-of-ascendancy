# scripts/ui/RetoolingWarningPopup.gd
class_name RetoolingWarningPopup
extends Window

@export var factory_id: int = 0
@export var new_design: String = ""

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var warning_label: RichTextLabel = $MarginContainer/VBoxContainer/WarningLabel
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/CancelButton


func _ready() -> void:
	title = "Retooling Warning"
	close_requested.connect(_on_cancel_pressed)

	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.WARNING)
	RetrowaveTheme.style_rich_text(warning_label)
	RetrowaveTheme.style_danger_button(confirm_button)
	RetrowaveTheme.style_secondary_button(cancel_button)

	title_label.text = "RETOOLING WARNING"
	_update_warning_text()
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _update_warning_text() -> void:
	if FactoryManager == null:
		warning_label.text = "[color=#ff6666]FactoryManager unavailable.[/color]"
		return

	var factory := FactoryManager.get_factory(factory_id)
	if factory == null:
		warning_label.text = "[color=#ff6666]Error: Factory not found.[/color]"
		return

	var old_design := factory.current_production_design
	if old_design.is_empty():
		old_design = "(idle)"

	var old_group := RetoolingSimilarityTable.category_group_for_design(factory.current_production_design)
	var new_group := RetoolingSimilarityTable.category_group_for_design(new_design)
	var params := ProductionManager.get_retooling_params(old_group, new_group)

	var retool_days := float(params.get("retool_days", 45.0))
	var recovery_days := float(params.get("recovery_days", 45.0))
	var retained_eff := float(params.get("retained_efficiency", 0.5))

	var text := "[color=#33e6ff][b]You are about to change production[/b][/color]\n\n"
	text += "Current:  [b]%s[/b]\n" % old_design
	text += "New:      [color=#ff33cc][b]%s[/b][/color]\n\n" % new_design
	text += (
		"This will put the factory into [b]retooling[/b] for approximately "
		+ "[b]%.0f days[/b] (recovery ~%.0f days).\n"
		% [retool_days, recovery_days]
	)
	text += "Efficiency will drop to roughly [b]%.0f%%[/b] during this period.\n\n" % (
		retained_eff * 100.0
	)
	text += "[color=#ff6666][b]Current production progress will be lost.[/b][/color]\n\n"
	text += "[color=#9aa8c7]Proceed with retooling?[/color]"

	warning_label.text = text
	warning_label.fit_content = true


func _on_confirm_pressed() -> void:
	var ok := ProductionManager.reassign_factory(factory_id, new_design)
	if not ok:
		push_warning("Failed to reassign factory %d to %s" % [factory_id, new_design])
	else:
		var main_screen := get_tree().get_first_node_in_group("production_screen")
		if main_screen != null and main_screen.has_method("refresh_screen"):
			main_screen.refresh_screen()
	hide()
	call_deferred("queue_free")


func _on_cancel_pressed() -> void:
	hide()
	call_deferred("queue_free")
