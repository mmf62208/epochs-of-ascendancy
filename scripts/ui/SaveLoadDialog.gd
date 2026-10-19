# scripts/ui/SaveLoadDialog.gd
## Modal save / load list. Layer 128: above the end screen (125) and the HUD (110),
## below the Command Center (130). Never shown headless.
class_name SaveLoadDialog
extends CanvasLayer

const LAYER := 128
const PROTECTED: PackedStringArray = ["quicksave", "autosave", "autosave_1", "autosave_2", "autosave_3"]

var _mode := "save"
var _rows: Array[Dictionary] = []
var _selected := -1
var _list: VBoxContainer
var _name_field: LineEdit
var _confirm_panel: Panel
var _confirm_label: Label
var _confirm_ok: Button
var _confirm_kind := ""
var _pending_slot := ""


static func open(mode: String) -> Node:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	for n in tree.get_nodes_in_group("save_load_dialog"):
		if is_instance_valid(n):
			n.queue_free()
	var layer := SaveLoadDialog.new()
	layer._mode = "load" if mode == "load" else "save"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	tree.root.move_child(layer, tree.root.get_child_count() - 1)
	return layer


func _ready() -> void:
	name = "SaveLoadPopup"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("save_load_dialog")
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("raise_toasts_above_dialogs"):
		LeaderEventUI.raise_toasts_above_dialogs()
	set_process_input(true)
	var blocker := ColorRect.new()
	blocker.name = "Blocker"
	blocker.color = Color(0.02, 0.03, 0.06, 0.78)
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	var panel := Panel.new()
	panel.name = "DialogPanel"
	panel.custom_minimum_size = Vector2(760, 520)
	panel.size = Vector2(760, 520)
	panel.position = Vector2(260, 120)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	RetrowaveTheme.style_menu_panel(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(18, 14)
	box.custom_minimum_size = Vector2(724, 490)
	box.size = Vector2(724, 490)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.text = "Save game" if _mode == "save" else "Load game"
	RetrowaveTheme.style_title(title)
	box.add_child(title)
	if _mode == "save":
		_name_field = LineEdit.new()
		_name_field.name = "SlotName"
		_name_field.text = _default_name()
		_name_field.custom_minimum_size = Vector2(700, 32)
		_name_field.add_theme_color_override("font_color", Color(0.93, 0.95, 0.98))
		_name_field.add_theme_font_size_override("font_size", 16)
		box.add_child(_name_field)
	var scroll := ScrollContainer.new()
	scroll.name = "SaveScroll"
	scroll.custom_minimum_size = Vector2(700, 340)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "SaveList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	if _mode == "save":
		var save_b := _button("Save", _on_save_pressed)
		save_b.name = "BtnSave"
		RetrowaveTheme.style_primary_button(save_b)
		actions.add_child(save_b)
	else:
		var load_b := _button("Load", _on_load_pressed)
		load_b.name = "BtnLoad"
		RetrowaveTheme.style_primary_button(load_b)
		actions.add_child(load_b)
		var del_b := _button("Delete", _on_delete_pressed)
		del_b.name = "BtnDelete"
		RetrowaveTheme.style_danger_button(del_b)
		actions.add_child(del_b)
	var cancel_b := _button("Cancel", _close)
	cancel_b.name = "BtnCancel"
	RetrowaveTheme.style_secondary_button(cancel_b)
	actions.add_child(cancel_b)
	var close_b := _button("×", _close)
	close_b.name = "BtnClose"
	RetrowaveTheme.style_secondary_button(close_b)
	actions.add_child(close_b)
	_build_confirm(panel)
	_refresh()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.custom_minimum_size = Vector2(96, 34)
	b.pressed.connect(cb)
	return b


func _build_confirm(panel: Panel) -> void:
	_confirm_panel = Panel.new()
	_confirm_panel.name = "ConfirmPanel"
	_confirm_panel.visible = false
	_confirm_panel.position = Vector2(80, 140)
	_confirm_panel.custom_minimum_size = Vector2(600, 220)
	_confirm_panel.size = Vector2(600, 220)
	_confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	RetrowaveTheme.style_menu_panel(_confirm_panel)
	panel.add_child(_confirm_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(548, 172)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	var margin := MarginContainer.new()
	margin.name = "ConfirmMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 16)
	_confirm_panel.add_child(margin)
	margin.add_child(box)
	_confirm_label = Label.new()
	_confirm_label.name = "ConfirmText"
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirm_label.custom_minimum_size = Vector2(540, 80)
	RetrowaveTheme.style_body_label(_confirm_label)
	box.add_child(_confirm_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_confirm_ok = _button("Overwrite", _on_confirm_ok)
	_confirm_ok.name = "BtnConfirm"
	RetrowaveTheme.style_danger_button(_confirm_ok)
	row.add_child(_confirm_ok)
	var no := _button("Cancel", _hide_confirm)
	no.name = "BtnConfirmCancel"
	RetrowaveTheme.style_secondary_button(no)
	row.add_child(no)


func _default_name() -> String:
	var tag := "GER"
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var live := str(LeaderManager.get_player_country_tag()).strip_edges()
		if not live.is_empty():
			tag = live
	var y := 1936
	var m := 1
	var d := 1
	if typeof(TimeManager) != TYPE_NIL:
		y = int(TimeManager.current_year)
		m = int(TimeManager.current_month)
		d = int(TimeManager.current_day)
	var raw := "%s %04d-%02d-%02d" % [tag, y, m, d]
	if typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("_sanitize_slot"):
		return str(SaveLoadManager._sanitize_slot(raw))
	return raw.to_lower().replace(" ", "_")


func _refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	_selected = -1
	if typeof(SaveLoadManager) == TYPE_NIL or not SaveLoadManager.has_method("list_saves"):
		return
	var listed: Array = SaveLoadManager.list_saves()
	for entry in listed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_rows.append(entry)
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "No saves yet"
		RetrowaveTheme.style_body_label(empty)
		_list.add_child(empty)
		return
	for i in _rows.size():
		_list.add_child(_make_row(i))


func _make_row(index: int) -> Control:
	var info: Dictionary = _rows[index]
	var meta: Dictionary = info.get("metadata", {}) if info.get("metadata") is Dictionary else {}
	var damaged := bool(info.get("damaged", false))
	var old := bool(info.get("old_format", false))
	var slot := str(info.get("slot", ""))
	var btn := Button.new()
	btn.name = "Row_%s" % slot
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(680, 36)
	var tag := str(meta.get("player_tag", "")).strip_edges().to_upper()
	var nation := str(meta.get("nation_name", tag))
	var when := str(meta.get("game_date", ""))
	var status := str(meta.get("campaign_status", ""))
	var wall := str(meta.get("wall_time", meta.get("timestamp", "")))
	if typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("format_wall_time_local"):
		wall = str(SaveLoadManager.format_wall_time_local(wall))
	var flags := ""
	if old:
		flags += "  old format"
	if damaged:
		flags += "  damaged"
	btn.text = "%s   %s   %s   %s   %s%s" % [slot, when, nation, status, wall, flags]
	if damaged:
		btn.modulate = Color(0.55, 0.55, 0.55, 1)
	btn.pressed.connect(_select_row.bind(index))
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.color = _flag_color(tag if not tag.is_empty() else slot)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(swatch)
	RetrowaveTheme.style_secondary_button(btn)
	return btn


func _flag_color(tag: String) -> Color:
	var h := absi(int(hash(tag)))
	return Color.from_hsv(float(h % 360) / 360.0, 0.62, 0.92)


func _select_row(index: int) -> void:
	_selected = index
	if index < 0 or index >= _rows.size():
		return
	if _mode == "save" and _name_field != null:
		_name_field.text = str(_rows[index].get("slot", ""))
	if bool(_rows[index].get("damaged", false)):
		_toast(SaveLoadManager.DAMAGED_SAVE_MESSAGE, true)


func _on_save_pressed() -> void:
	var slot := _typed_slot()
	if slot.is_empty():
		_toast("Enter a save name.", true)
		return
	if slot in PROTECTED:
		_toast("That slot is reserved.", true)
		return
	var status: Dictionary = SaveLoadManager.slot_status(slot)
	if not bool(status.get("missing", true)):
		var meta: Dictionary = status.get("metadata", {}) if status.get("metadata") is Dictionary else {}
		var when := str(meta.get("game_date", ""))
		var nation := str(meta.get("nation_name", meta.get("player_tag", "")))
		_show_confirm("overwrite", slot, "Overwrite %s (%s, %s)?" % [slot, when, nation], "Overwrite")
		return
	_write(slot)


func _on_load_pressed() -> void:
	var info := _selected_info()
	if info.is_empty():
		_toast("Select a save.", true)
		return
	if bool(info.get("damaged", false)):
		_toast(SaveLoadManager.DAMAGED_SAVE_MESSAGE, true)
		return
	var slot := str(info.get("slot", ""))
	var running := false
	if typeof(TimeManager) != TYPE_NIL:
		running = int(TimeManager.get_total_days_elapsed()) > 0
	if running:
		var since := ""
		if typeof(SaveLoadManager) != TYPE_NIL:
			since = str(SaveLoadManager.session_wall_time).strip_edges()
		if since.is_empty():
			since = "the start of this session"
		elif typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("format_wall_time_local"):
			since = str(SaveLoadManager.format_wall_time_local(since))
		_show_confirm("load", slot, "Unsaved progress since %s will be lost. Load?" % since, "Load")
		return
	_read(slot)


func _on_delete_pressed() -> void:
	var info := _selected_info()
	if info.is_empty() or bool(info.get("damaged", false)) and str(info.get("slot", "")).is_empty():
		_toast("Select a save.", true)
		return
	var slot := str(info.get("slot", ""))
	if slot.is_empty():
		_toast("Select a save.", true)
		return
	_show_confirm("delete", slot, "Delete save \"%s\"?" % slot, "Delete")


func _show_confirm(kind: String, slot: String, text: String, ok_label: String) -> void:
	_confirm_kind = kind
	_pending_slot = slot
	_confirm_label.text = text
	_confirm_ok.text = ok_label
	var text_h := maxf(80.0, _confirm_label.get_minimum_size().y)
	var panel_h := maxf(220.0, text_h + 120.0)
	_confirm_label.custom_minimum_size = Vector2(540, text_h)
	_confirm_panel.custom_minimum_size = Vector2(600, panel_h)
	_confirm_panel.size = Vector2(600, panel_h)
	_confirm_panel.visible = true


func _hide_confirm() -> void:
	_confirm_kind = ""
	_pending_slot = ""
	if _confirm_panel != null:
		_confirm_panel.visible = false


func _on_confirm_ok() -> void:
	var kind := _confirm_kind
	var slot := _pending_slot
	_hide_confirm()
	if slot.is_empty():
		return
	if kind == "overwrite" or kind == "save":
		_write(slot)
	elif kind == "load":
		_read(slot)
	elif kind == "delete":
		if SaveLoadManager.delete_save(slot):
			_toast("Deleted %s" % slot, false)
			_refresh()
		else:
			_toast("Could not delete %s" % slot, true)


func _write(slot: String) -> void:
	var result: Dictionary = SaveLoadManager.save_game_detailed(slot)
	if bool(result.get("ok", false)):
		_refresh()
	# save_game_detailed already toasts.


func _read(slot: String) -> void:
	var result: Dictionary = SaveLoadManager.load_game_detailed(slot)
	if bool(result.get("ok", false)):
		var bar := get_tree().get_first_node_in_group("top_info_bar") if get_tree() != null else null
		if bar != null and bar.has_method("_update_date_time"):
			bar.call("_update_date_time")
		_close()
	# Success and failure toasts come from load_game_detailed.


func _typed_slot() -> String:
	if _name_field == null:
		return ""
	return str(SaveLoadManager._sanitize_slot(_name_field.text))


func _selected_info() -> Dictionary:
	if _selected < 0 or _selected >= _rows.size():
		return {}
	return _rows[_selected]


func _newest_wall_time() -> String:
	var best := ""
	for info in _rows:
		var meta: Dictionary = info.get("metadata", {}) if info.get("metadata") is Dictionary else {}
		var wall := str(meta.get("wall_time", meta.get("timestamp", "")))
		if wall > best:
			best = wall
	return best


func _toast(message: String, is_error: bool) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("raise_toasts_above_dialogs"):
		LeaderEventUI.raise_toasts_above_dialogs()
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(message, 3.0, is_error)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and ((event as InputEventKey).keycode == KEY_ESCAPE or (event as InputEventKey).physical_keycode == KEY_ESCAPE)):
		get_viewport().set_input_as_handled()
		if _confirm_panel != null and _confirm_panel.visible:
			_hide_confirm()
		else:
			_close()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			# The full-rect blocker owns the click. Do not mark it handled here:
			# Button ACTION_MODE_BUTTON_PRESS must still see the press. Map pick
			# is blocked because this layer is a visible *Popup modal.
			pass


func _close() -> void:
	var tree := get_tree()
	if tree != null:
		var mr := tree.get_first_node_in_group("map_renderer")
		if mr != null and mr.has_method("arm_ui_close_release_swallow"):
			mr.call("arm_ui_close_release_swallow")
	queue_free()
