# scripts/ui/MainMenu.gd
## Reusable Main Menu scene — pause/resume, save manager, extensible options.
class_name MainMenu
extends Window

const MENU_WIDTH := 780
const MENU_HEIGHT := 540
const FADE_IN_SEC := 0.14
const FADE_OUT_SEC := 0.1

## id, label, style: primary | secondary | danger | muted
const MENU_OPTIONS: Array[Dictionary] = [
	{"id": "save", "label": "Save Game", "style": "primary"},
	{"id": "load", "label": "Load Game", "style": "secondary"},
	{"id": "trade_market", "label": "Trade Market", "style": "primary"},
	{"id": "save_as", "label": "Save As…", "style": "secondary"},
	{"id": "settings", "label": "Settings", "style": "muted"},
	{"id": "help", "label": "Help / About", "style": "muted"},
	{"id": "return_to_main", "label": "Return to Title", "style": "secondary"},
	{"id": "exit", "label": "Exit to Desktop", "style": "danger"},
]

signal menu_closed

var _previous_pause_state := false
var _previous_speed := 1
var _save_list_vbox: VBoxContainer
var _closing := false

var _delete_confirm: ConfirmationDialog
var _pending_delete_slot := ""
var _rename_dialog: AcceptDialog
var _rename_field: LineEdit
var _pending_rename_slot := ""
var _save_as_dialog: AcceptDialog
var _save_as_field: LineEdit

@onready var main_vbox: VBoxContainer = $MarginContainer/VBoxContainer
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/SubtitleLabel
@onready var content_hbox: HBoxContainer = $MarginContainer/VBoxContainer/ContentHBox
@onready var options_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ContentHBox/OptionsVBox
@onready var save_manager_panel: PanelContainer = $MarginContainer/VBoxContainer/ContentHBox/SaveManagerPanel
@onready var save_manager_container: VBoxContainer = $MarginContainer/VBoxContainer/ContentHBox/SaveManagerPanel/SaveManagerContainer
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton


func _ready() -> void:
	title = "Main Menu"
	unresizable = true
	close_requested.connect(_on_close_requested)
	_clamp_to_viewport()
	_apply_theme()
	_build_menu_options()
	_build_save_manager_view()
	_ensure_dialogs()
	_style_static_controls()
	_pause_game(true)
	_set_status("Game paused — choose an option or manage saves.")
	_play_open_fade()
	grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_close_requested()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_close_requested()
		get_viewport().set_input_as_handled()


func _clamp_to_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	size = Vector2i(mini(MENU_WIDTH, int(vp.x * 0.92)), mini(MENU_HEIGHT, int(vp.y * 0.88)))
	position = Vector2i((vp - Vector2(size)) / 2)


func _apply_theme() -> void:
	if typeof(RetrowaveTheme) == TYPE_NIL:
		return
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_body_label(subtitle_label)
	RetrowaveTheme.style_detail_panel(save_manager_panel)


func _style_static_controls() -> void:
	if typeof(RetrowaveTheme) == TYPE_NIL:
		return
	RetrowaveTheme.style_secondary_button(close_button)
	RetrowaveTheme.style_body_label(status_label)
	status_label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)


func _play_open_fade() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_IN_SEC)


func _build_menu_options() -> void:
	var section := Label.new()
	section.text = "GAME"
	section.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	options_vbox.add_child(section)
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_column_header(section)

	for opt in MENU_OPTIONS:
		var id := str(opt.get("id", ""))
		var label := str(opt.get("label", id))
		var style := str(opt.get("style", "secondary"))
		options_vbox.add_child(_make_menu_button(label, id, style))

	close_button.pressed.connect(_on_close_requested)


func _make_menu_button(text: String, option: String, style: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(func(): _on_menu_button_pressed(option))
	if typeof(RetrowaveTheme) != TYPE_NIL:
		match style:
			"primary":
				RetrowaveTheme.style_primary_button(btn)
			"danger":
				RetrowaveTheme.style_danger_button(btn)
			"muted":
				RetrowaveTheme.style_secondary_button(btn)
				btn.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
			_:
				RetrowaveTheme.style_secondary_button(btn)
	return btn


func _on_menu_button_pressed(option: String) -> void:
	var top_bar := get_tree().root.get_node_or_null("TopInfoBar")
	if top_bar != null and top_bar.has_signal("menu_option_selected"):
		top_bar.menu_option_selected.emit(option)
	_handle_menu_option(option)


func _build_save_manager_view() -> void:
	for c in save_manager_container.get_children():
		c.queue_free()

	var header := Label.new()
	header.text = "SAVES"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	save_manager_container.add_child(header)
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_column_header(header)

	var hint := Label.new()
	hint.text = "Most recent first · Load replaces current session"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_manager_container.add_child(hint)
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_body_label(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	save_manager_container.add_child(scroll)

	_save_list_vbox = VBoxContainer.new()
	_save_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_save_list_vbox)

	_refresh_save_list()


func _refresh_save_list() -> void:
	if _save_list_vbox == null or not is_instance_valid(_save_list_vbox):
		_build_save_manager_view()
		return
	for c in _save_list_vbox.get_children():
		c.queue_free()
	_populate_save_list(_save_list_vbox)


func _populate_save_list(parent: VBoxContainer) -> void:
	if typeof(SaveLoadManager) == TYPE_NIL:
		var err := Label.new()
		err.text = "Save system unavailable."
		parent.add_child(err)
		return

	var saves := SaveLoadManager.list_saves()
	if saves.is_empty():
		var empty := Label.new()
		empty.text = "No saves yet.\nUse Save Game or Save As to create your first slot."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(empty)
		if typeof(RetrowaveTheme) != TYPE_NIL:
			RetrowaveTheme.style_body_label(empty)
		return

	for save_info in saves:
		parent.add_child(_make_save_row(save_info))


func _make_save_row(save_info: Dictionary) -> Control:
	var slot := str(save_info.get("slot", ""))
	var meta: Dictionary = save_info.get("metadata", {}) as Dictionary

	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_detail_panel(row_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	row_panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	outer.add_child(title_row)

	var slot_label := Label.new()
	slot_label.text = slot if not slot.is_empty() else "?"
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_column_header(slot_label)
	title_row.add_child(slot_label)

	var nation := str(meta.get("player_tag", "")).strip_edges()
	if not nation.is_empty():
		var tag_label := Label.new()
		tag_label.text = nation
		tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if typeof(RetrowaveTheme) != TYPE_NIL:
			RetrowaveTheme.style_body_label(tag_label)
			tag_label.add_theme_color_override("font_color", RetrowaveTheme.MAGENTA)
		title_row.add_child(tag_label)

	var detail := Label.new()
	detail.text = _format_save_detail_line(meta)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_body_label(detail)
	outer.add_child(detail)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	outer.add_child(actions)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.custom_minimum_size = Vector2(72, 30)
	load_btn.pressed.connect(_on_load_slot_pressed.bind(slot))
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_primary_button(load_btn)
	actions.add_child(load_btn)

	var rename_btn := Button.new()
	rename_btn.text = "Rename"
	rename_btn.custom_minimum_size = Vector2(72, 30)
	rename_btn.pressed.connect(_open_rename_dialog.bind(slot))
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_secondary_button(rename_btn)
	actions.add_child(rename_btn)

	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size = Vector2(72, 30)
	del_btn.pressed.connect(_open_delete_confirm.bind(slot))
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_danger_button(del_btn)
	actions.add_child(del_btn)

	return row_panel


func _format_save_detail_line(meta: Dictionary) -> String:
	var scenario := _format_scenario_label(str(meta.get("scenario_id", "")))
	var when := _format_timestamp(str(meta.get("last_played", meta.get("timestamp", ""))))
	var play := _format_play_time(int(meta.get("play_time_seconds", 0)))
	var version := str(meta.get("game_version", "")).strip_edges()
	var parts: PackedStringArray = []
	if not scenario.is_empty():
		parts.append(scenario)
	if not when.is_empty():
		parts.append(when)
	if play != "—":
		parts.append(play)
	if not version.is_empty():
		parts.append("v%s" % version)
	return " · ".join(parts) if parts.size() > 0 else "No metadata"


func _format_scenario_label(scenario_id: String) -> String:
	if scenario_id.is_empty():
		return "Unknown scenario"
	return scenario_id.replace("_", " ")


func _format_timestamp(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	if s.contains("T"):
		var date_part := s.split("T", false, 1)[0]
		var time_part := s.split("T", false, 1)[1] if s.split("T").size() > 1 else ""
		var date_readable := GameDateDisplay.format_iso_date_readable(date_part) if date_part.contains("-") else date_part
		var clock := time_part.substr(0, 5) if time_part.length() >= 5 else ""
		return "%s %s" % [date_readable, clock].strip_edges()
	if s.contains("-"):
		return GameDateDisplay.format_iso_date_readable(s.substr(0, 10))
	return s.substr(0, 16)


func _format_play_time(seconds: int) -> String:
	if seconds <= 0:
		return "—"
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % m


func _handle_menu_option(option: String) -> void:
	match option:
		"save":
			_do_quicksave()
		"load":
			_set_status("Select a save on the right, then press Load.")
		"trade_market":
			_open_trade_market()
		"save_as":
			_open_save_as_dialog()
		"settings":
			_set_status("Settings panel coming soon — use in-game options for now.")
			_toast("Settings will open here in a future update.", 2.5)
		"return_to_main":
			_set_status("Return to title screen — not implemented yet.")
			_toast("Title screen return is not wired yet.", 2.5)
		"exit":
			_closing = true
			_pause_game(false)
			menu_closed.emit()
			get_tree().quit()
		"help":
			_show_help_dialog()
		_:
			_set_status("Option: %s" % option)


func _do_quicksave() -> void:
	if typeof(SaveLoadManager) == TYPE_NIL:
		_toast("Save system unavailable.", 3.0, true)
		return
	var result := SaveLoadManager.save_game_detailed(SaveLoadManager.DEFAULT_SLOT)
	if result.get("ok", false):
		_set_status("Saved to %s." % SaveLoadManager.DEFAULT_SLOT)
		_toast("Game saved (%s)" % SaveLoadManager.DEFAULT_SLOT, 2.0)
		_refresh_save_list()
	else:
		var err := str(result.get("error", "Save failed"))
		_set_status(err)
		_toast(err, 3.0, true)

func _open_trade_market() -> void:
	var packed := load("res://scenes/ui/TradeMarketView.tscn")
	if packed == null:
		_toast("Trade Market is not available yet.", 2.5, true)
		return

	var view = packed.instantiate()
	get_tree().root.add_child(view)
	if view.has_method("show_market"):
		view.show_market("PUBLIC")
	else:
		view.popup_centered(Vector2i(1100, 700))

	# Close this menu cleanly so pause state is restored
	_closing = true
	await _close_with_fade()


func _on_load_slot_pressed(slot: String) -> void:
	if typeof(SaveLoadManager) == TYPE_NIL:
		_toast("Save system unavailable.", 3.0, true)
		return
	if SaveLoadManager.has_method("check_scenario_compatibility"):
		var compat: Dictionary = SaveLoadManager.check_scenario_compatibility(slot)
		if not compat.get("compatible", true):
			var saved_s := str(compat.get("saved_scenario", "?"))
			var cur_s := str(compat.get("current_scenario", "?"))
			var msg := "Scenario mismatch: save is %s, current is %s." % [saved_s, cur_s]
			_toast(msg, 3.5, true)
			_set_status(msg)
			return

	var result := SaveLoadManager.load_game_detailed(slot)
	if result.get("ok", false):
		_sync_hud_after_load()
		_toast("Loaded: %s" % slot, 2.5)
		await _close_with_fade()
	else:
		var err := str(result.get("error", "Load failed"))
		_set_status(err)
		_toast(err, 3.0, true)


func _sync_hud_after_load() -> void:
	var top_bar := get_tree().root.get_node_or_null("TopInfoBar")
	if top_bar != null:
		if top_bar.has_method("_update_date_time"):
			top_bar._update_date_time()
		if top_bar.has_method("_update_resources"):
			top_bar._update_resources()


func _ensure_dialogs() -> void:
	_delete_confirm = ConfirmationDialog.new()
	_delete_confirm.title = "Delete Save"
	_delete_confirm.ok_button_text = "Delete"
	_delete_confirm.cancel_button_text = "Cancel"
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_confirm)

	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Rename Save"
	_rename_dialog.ok_button_text = "Rename"
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	var rename_box := VBoxContainer.new()
	rename_box.add_theme_constant_override("separation", 8)
	_rename_field = LineEdit.new()
	_rename_field.placeholder_text = "New slot name"
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_search(_rename_field)
		_rename_field.placeholder_text = "New slot name (letters, numbers, underscore)"
	rename_box.add_child(_rename_field)
	_rename_dialog.add_child(rename_box)
	add_child(_rename_dialog)

	_save_as_dialog = AcceptDialog.new()
	_save_as_dialog.title = "Save As"
	_save_as_dialog.ok_button_text = "Save"
	_save_as_dialog.confirmed.connect(_on_save_as_confirmed)
	var save_as_box := VBoxContainer.new()
	_save_as_field = LineEdit.new()
	_save_as_field.placeholder_text = "Slot name (e.g. campaign_01)"
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_search(_save_as_field)
	save_as_box.add_child(_save_as_field)
	_save_as_dialog.add_child(save_as_box)
	add_child(_save_as_dialog)


func _open_delete_confirm(slot: String) -> void:
	_pending_delete_slot = slot
	_delete_confirm.dialog_text = "Delete save \"%s\"?\nThis cannot be undone." % slot
	_delete_confirm.popup_centered(Vector2i(420, 140))


func _on_delete_confirmed() -> void:
	var slot := _pending_delete_slot
	_pending_delete_slot = ""
	if slot.is_empty() or typeof(SaveLoadManager) == TYPE_NIL:
		return
	if not SaveLoadManager.delete_save(slot):
		_set_status("Could not delete \"%s\"." % slot)
		_toast("Delete failed: %s" % slot, 3.0, true)
		return
	_set_status("Deleted save \"%s\"." % slot)
	_toast("Deleted: %s" % slot, 2.0, true)
	_refresh_save_list()


func _open_rename_dialog(slot: String) -> void:
	_pending_rename_slot = slot
	_rename_field.text = slot
	_rename_dialog.popup_centered(Vector2i(400, 160))
	_rename_field.grab_focus()


func _on_rename_confirmed() -> void:
	var old_slot := _pending_rename_slot
	var new_slot := _sanitize_slot_name(_rename_field.text)
	_pending_rename_slot = ""
	if old_slot.is_empty() or new_slot.is_empty():
		_toast("Enter a valid slot name.", 2.5, true)
		return
	if new_slot == old_slot:
		return
	if typeof(SaveLoadManager) == TYPE_NIL:
		return
	if not SaveLoadManager.rename_save(old_slot, new_slot):
		_set_status("Rename failed (name taken or missing file).")
		_toast("Could not rename to \"%s\"." % new_slot, 3.0, true)
		return
	_set_status("Renamed \"%s\" → \"%s\"." % [old_slot, new_slot])
	_toast("Renamed to %s" % new_slot, 2.0)
	_refresh_save_list()


func _open_save_as_dialog() -> void:
	_save_as_field.text = ""
	_save_as_dialog.popup_centered(Vector2i(400, 160))
	_save_as_field.grab_focus()


func _on_save_as_confirmed() -> void:
	var slot := _sanitize_slot_name(_save_as_field.text)
	if slot.is_empty():
		_toast("Enter a slot name.", 2.5, true)
		return
	if typeof(SaveLoadManager) == TYPE_NIL:
		return
	var result := SaveLoadManager.save_game_detailed(slot)
	if result.get("ok", false):
		_set_status("Saved as \"%s\"." % slot)
		_toast("Saved as %s" % slot, 2.0)
		_refresh_save_list()
	else:
		var err := str(result.get("error", "Save failed"))
		_set_status(err)
		_toast(err, 3.0, true)


func _sanitize_slot_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	s = s.replace(" ", "_")
	var cleaned := ""
	for i in s.length():
		var ch := s[i]
		if ch.is_valid_identifier() or ch == "_" or ch.is_valid_int():
			cleaned += ch
	return cleaned


func _show_help_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Epochs of Ascendancy"
	dlg.dialog_text = (
		"Grand strategy in a neon-soaked age.\n\n"
		+ "• Save Game — quicksave slot\n"
		+ "• Save As — named slot on disk\n"
		+ "• ESC or Close — resume previous speed\n\n"
		+ "F5 quicksave · F9 quickload · Menu button toggles this panel."
	)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(480, 220))


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func _toast(message: String, duration: float = 2.5, is_error: bool = false) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(message, duration, is_error)


func _on_close_requested() -> void:
	if _closing:
		return
	_closing = true
	await _close_with_fade()


func _close_with_fade() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC)
	await tw.finished
	_pause_game(false)
	menu_closed.emit()
	queue_free()


func _pause_game(pause: bool) -> void:
	var resume_speed := _get_resume_speed()
	if typeof(TimeManager) == TYPE_NIL:
		Engine.time_scale = 0.0 if pause else float(resume_speed)
		return

	if pause:
		if not has_meta("was_paused_before_menu"):
			set_meta("was_paused_before_menu", TimeManager.is_paused())
			set_meta("speed_before_menu", resume_speed)
		TimeManager.set_paused(true)
		TimeManager.set_time_scale(0.0)
		Engine.time_scale = 0.0
	else:
		var was_paused: bool = get_meta("was_paused_before_menu", false)
		var prev_speed: int = int(get_meta("speed_before_menu", resume_speed))
		TimeManager.set_paused(was_paused)
		var scale := 0.0 if was_paused else float(prev_speed)
		TimeManager.set_time_scale(scale)
		Engine.time_scale = scale
		_sync_top_bar_after_menu_close(was_paused, prev_speed)
		if has_meta("was_paused_before_menu"):
			remove_meta("was_paused_before_menu")
		if has_meta("speed_before_menu"):
			remove_meta("speed_before_menu")


func _get_resume_speed() -> int:
	var top_bar := get_tree().root.get_node_or_null("TopInfoBar")
	if top_bar != null and "current_speed" in top_bar:
		return maxi(1, int(top_bar.current_speed))
	return maxi(1, _previous_speed)


func _sync_top_bar_after_menu_close(was_paused: bool, speed: int) -> void:
	var top_bar := get_tree().root.get_node_or_null("TopInfoBar")
	if top_bar == null:
		return
	if "is_paused" in top_bar:
		top_bar.is_paused = was_paused
	if "current_speed" in top_bar:
		top_bar.current_speed = speed
	if top_bar.has_method("_sync_time_manager_controls"):
		top_bar._sync_time_manager_controls()
	if top_bar.has_method("_update_speed_buttons"):
		top_bar._update_speed_buttons()
