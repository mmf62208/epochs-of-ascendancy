# scripts/ui/MainMenu.gd
## In-game command center (CanvasLayer overlay — not a native OS window).
## Left: actions · Right: save browser with real slots · ESC / Close works always.
class_name MainMenu
extends CanvasLayer

const MENU_WIDTH := 960.0
const MENU_HEIGHT := 620.0

signal menu_closed

var _closing := false
var _root: Control
var _panel: PanelContainer
var _options_vbox: VBoxContainer
var _save_list_vbox: VBoxContainer
var _status_label: Label
var _blocker: ColorRect

var _delete_confirm: ConfirmationDialog
var _pending_delete_slot := ""
var _rename_dialog: AcceptDialog
var _rename_field: LineEdit
var _pending_rename_slot := ""
var _save_as_dialog: AcceptDialog
var _save_as_field: LineEdit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_ui()
	_ensure_dialogs()
	_pause_game(true)
	_set_status("Paused · Save / Load slots on the right · ESC or Close to resume")
	_refresh_save_list()
	set_process_input(true)
	set_process_unhandled_input(true)


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_force_close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_force_close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	# Single full-rect root (STOP) so hit-testing reaches panel + buttons.
	# Previous layout put Blocker as a sibling under CanvasLayer while Root was
	# MOUSE_FILTER_IGNORE — clicks fell through to the dimmer and never hit Save/Load.
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	_blocker = ColorRect.new()
	_blocker.name = "Blocker"
	_blocker.color = Color(0.02, 0.03, 0.06, 0.72)
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.process_mode = Node.PROCESS_MODE_ALWAYS
	# Click dimmer outside the panel → return to game.
	_blocker.gui_input.connect(_on_blocker_gui_input)
	_root.add_child(_blocker)

	_panel = PanelContainer.new()
	_panel.name = "MenuPanel"
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = Vector2(MENU_WIDTH, MENU_HEIGHT)
	_root.add_child(_panel)
	RetrowaveTheme.style_menu_panel(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	# Branding wordmark above Command Center title (512 fallback if main missing).
	var wordmark_tex: Texture2D = null
	if ResourceLoader.exists("res://assets/graphics/branding/epochs_wordmark.png"):
		wordmark_tex = load("res://assets/graphics/branding/epochs_wordmark.png") as Texture2D
	elif ResourceLoader.exists("res://assets/graphics/branding/epochs_wordmark_512.png"):
		wordmark_tex = load("res://assets/graphics/branding/epochs_wordmark_512.png") as Texture2D
	if wordmark_tex != null:
		var wordmark := TextureRect.new()
		wordmark.name = "Wordmark"
		wordmark.texture = wordmark_tex
		wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var wm_h := 48.0
		var wm_aspect := float(wordmark_tex.get_width()) / maxf(1.0, float(wordmark_tex.get_height()))
		wordmark.custom_minimum_size = Vector2(wm_h * wm_aspect, wm_h)
		wordmark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(wordmark)

	# Title bar: title + upper-right ✕ to return to game.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	outer.add_child(title_row)

	var title := Label.new()
	title.text = "Command Center"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	RetrowaveTheme.style_title(title, RetrowaveTheme.CYAN)
	title_row.add_child(title)

	var close_x := Button.new()
	close_x.name = "CloseX"
	close_x.text = "✕"
	close_x.tooltip_text = "Return to game (ESC)"
	close_x.custom_minimum_size = Vector2(44, 40)
	close_x.focus_mode = Control.FOCUS_ALL
	close_x.mouse_filter = Control.MOUSE_FILTER_STOP
	close_x.process_mode = Node.PROCESS_MODE_ALWAYS
	close_x.pressed.connect(_force_close)
	RetrowaveTheme.style_secondary_button(close_x)
	# Slightly stronger “window chrome” read for the X.
	close_x.add_theme_font_size_override("font_size", 20)
	title_row.add_child(close_x)

	var sub := Label.new()
	sub.text = "Save · Load · Campaign tools  ·  ✕ or ESC returns to map"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetrowaveTheme.style_body_label(sub)
	outer.add_child(sub)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	outer.add_child(content)

	# --- Left: actions ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	content.add_child(left)

	var left_hdr := Label.new()
	left_hdr.text = "GAME"
	RetrowaveTheme.style_column_header(left_hdr)
	left.add_child(left_hdr)

	_options_vbox = left
	_add_action_button(left, "Save Game (quicksave)", "save", true)
	_add_action_button(left, "Save As…", "save_as", false)
	_add_action_button(left, "Refresh save list", "refresh", false)
	_add_action_button(left, "Trade Market", "trade_market", true)
	_add_action_button(left, "Help / About", "help", false)
	_add_action_button(left, "Return to Title", "return_to_main", false)
	_add_action_button(left, "Exit to Desktop", "exit", false, true)

	if OS.is_debug_build():
		var dbg_hdr := Label.new()
		dbg_hdr.text = "DEBUG"
		RetrowaveTheme.style_column_header(dbg_hdr)
		left.add_child(dbg_hdr)
		_add_action_button(left, "Open Debug Overlay (F10)", "debug", false)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)

	# --- Right: save browser ---
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(right)
	RetrowaveTheme.style_detail_panel_flat(right)

	var right_m := MarginContainer.new()
	right_m.add_theme_constant_override("margin_left", 12)
	right_m.add_theme_constant_override("margin_right", 12)
	right_m.add_theme_constant_override("margin_top", 10)
	right_m.add_theme_constant_override("margin_bottom", 10)
	right.add_child(right_m)

	var right_v := VBoxContainer.new()
	right_v.add_theme_constant_override("separation", 8)
	right_m.add_child(right_v)

	var sav_hdr := Label.new()
	sav_hdr.text = "SAVES"
	RetrowaveTheme.style_column_header(sav_hdr)
	right_v.add_child(sav_hdr)

	var sav_hint := Label.new()
	sav_hint.text = "Click Save on a slot to write · Load to restore · Save Game uses quicksave"
	sav_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(sav_hint)
	right_v.add_child(sav_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_v.add_child(scroll)

	_save_list_vbox = VBoxContainer.new()
	_save_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_list_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_save_list_vbox)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 36)
	RetrowaveTheme.style_body_label(_status_label)
	_status_label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	outer.add_child(_status_label)

	var close_btn := Button.new()
	close_btn.text = "Return to Game (ESC)"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(_force_close)
	RetrowaveTheme.style_primary_button(close_btn)
	outer.add_child(close_btn)

	_center_panel()
	if get_viewport():
		get_viewport().size_changed.connect(_center_panel)


func _on_blocker_gui_input(event: InputEvent) -> void:
	# Click outside panel (on dimmed map) closes menu — same as ✕ / ESC.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# Only if click is not over the panel rect.
			if _panel != null and is_instance_valid(_panel):
				var local := _panel.get_global_rect()
				if local.has_point(mb.global_position):
					return
			_force_close()
			_root.accept_event()


func _center_panel() -> void:
	if _panel == null or get_viewport() == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w := minf(MENU_WIDTH, vp.x * 0.92)
	var h := minf(MENU_HEIGHT, vp.y * 0.88)
	_panel.custom_minimum_size = Vector2(w, h)
	_panel.size = Vector2(w, h)
	_panel.position = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)


func _add_action_button(parent: VBoxContainer, text: String, id: String, primary: bool, danger: bool = false) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# Bind by string id (stable); avoid async signal sinks that drop without await.
	btn.pressed.connect(_on_action.bind(id))
	if danger:
		RetrowaveTheme.style_danger_button(btn)
	elif primary:
		RetrowaveTheme.style_primary_button(btn)
	else:
		RetrowaveTheme.style_secondary_button(btn)
	parent.add_child(btn)


func _on_action(id: String) -> void:
	print("MainMenu: action=", id)
	match id:
		"save":
			_save_to_slot("quicksave")
		"save_as":
			_open_save_as_dialog()
		"refresh":
			_refresh_save_list()
			_set_status("Save list refreshed.")
		"trade_market":
			_open_trade_market()
		"help":
			_show_help()
		"return_to_main":
			_return_to_title()
		"exit":
			_closing = true
			_pause_game(false)
			menu_closed.emit()
			get_tree().quit()
		"debug":
			var dbg: Node = get_tree().root.get_node_or_null("DebugOverlay")
			if dbg != null and dbg.has_method("toggle"):
				dbg.call("toggle")
		_:
			_set_status("Option: %s" % id)


func _slm() -> Node:
	# Prefer autoload path (always present after boot).
	if get_tree() != null and get_tree().root != null:
		var n: Node = get_tree().root.get_node_or_null("/root/SaveLoadManager")
		if n != null:
			return n
	return null


func _save_to_slot(slot: String) -> void:
	## Synchronous save on pressed (deferred only for list refresh). No await —
	## async coroutines from Button.pressed were easy to lose / appear as "nothing happens".
	var slm := _slm()
	if slm == null or not slm.has_method("save_game_detailed"):
		_set_status("SAVE FAILED: SaveLoadManager missing")
		_toast("Save system unavailable.", 3.0, true)
		push_error("MainMenu: SaveLoadManager missing")
		return
	_set_status("Saving \"%s\"… (large boards take a few seconds)" % slot)
	print("MainMenu: saving slot=", slot)
	var result: Dictionary = slm.call("save_game_detailed", slot)
	if bool(result.get("ok", false)):
		var abs_p := str(result.get("absolute_path", result.get("path", "")))
		var kb := int(int(result.get("bytes", 0)) / 1024)
		_set_status("Saved \"%s\" · %d KB · %s" % [slot, kb, abs_p])
		_toast("Saved %s (%d KB)" % [slot, kb], 2.5)
		print("MainMenu: save ok → %s (%d bytes)" % [abs_p, int(result.get("bytes", 0))])
		call_deferred("_refresh_save_list")
	else:
		var err := str(result.get("error", "Save failed"))
		_set_status("SAVE FAILED: %s" % err)
		_toast(err, 4.0, true)
		push_error("MainMenu: %s" % err)


func _refresh_save_list() -> void:
	if _save_list_vbox == null or not is_instance_valid(_save_list_vbox):
		return
	for c in _save_list_vbox.get_children():
		c.queue_free()

	var slm := _slm()
	if slm == null:
		var err := Label.new()
		err.text = "Save system unavailable."
		_save_list_vbox.add_child(err)
		return

	var path_hint := Label.new()
	var glob := ""
	if slm.has_method("get_saves_dir_global"):
		glob = str(slm.call("get_saves_dir_global"))
	path_hint.text = "Folder: %s" % (glob if not glob.is_empty() else "user://saves/")
	path_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(path_hint)
	_save_list_vbox.add_child(path_hint)

	var rows: Array = []
	if slm.has_method("list_slots_for_ui"):
		rows = slm.call("list_slots_for_ui")
	elif slm.has_method("list_saves"):
		for s in slm.call("list_saves"):
			if typeof(s) == TYPE_DICTIONARY:
				var ent: Dictionary = s
				ent["occupied"] = true
				ent["can_load"] = true
				ent["label"] = str(ent.get("slot", "?"))
				rows.append(ent)

	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No slots — use Save Game or Save As…"
		_save_list_vbox.add_child(empty)
		return

	for info in rows:
		if typeof(info) != TYPE_DICTIONARY:
			continue
		_save_list_vbox.add_child(_make_save_row(info))


func _make_save_row(info: Dictionary) -> Control:
	var slot := str(info.get("slot", ""))
	var meta: Dictionary = info.get("metadata", {}) as Dictionary
	var occupied := bool(info.get("occupied", false))
	var label := str(info.get("label", slot))

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 88)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_detail_panel_flat(row)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	row.add_child(outer)

	var title_row := HBoxContainer.new()
	outer.add_child(title_row)

	var name_l := Label.new()
	name_l.text = label if not label.is_empty() else slot
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 14)
	RetrowaveTheme.style_column_header(name_l)
	title_row.add_child(name_l)

	var st := Label.new()
	st.text = "occupied" if occupied else "empty"
	RetrowaveTheme.style_body_label(st)
	if occupied:
		st.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	title_row.add_child(st)

	var detail := Label.new()
	detail.text = _format_detail(meta) if occupied else "Empty slot — press Save to write here"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(detail)
	outer.add_child(detail)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	outer.add_child(actions)

	var load_b := Button.new()
	load_b.text = "Load"
	load_b.custom_minimum_size = Vector2(80, 32)
	load_b.disabled = not occupied
	load_b.mouse_filter = Control.MOUSE_FILTER_STOP
	load_b.pressed.connect(_on_load_slot.bind(slot))
	RetrowaveTheme.style_primary_button(load_b)
	actions.add_child(load_b)

	var save_b := Button.new()
	save_b.text = "Save"
	save_b.custom_minimum_size = Vector2(80, 32)
	save_b.tooltip_text = "Write current game into this slot"
	save_b.mouse_filter = Control.MOUSE_FILTER_STOP
	save_b.pressed.connect(_save_to_slot.bind(slot))
	RetrowaveTheme.style_secondary_button(save_b)
	actions.add_child(save_b)

	var ren_b := Button.new()
	ren_b.text = "Rename"
	ren_b.custom_minimum_size = Vector2(80, 32)
	ren_b.disabled = not occupied
	ren_b.pressed.connect(_open_rename.bind(slot))
	RetrowaveTheme.style_secondary_button(ren_b)
	actions.add_child(ren_b)

	var del_b := Button.new()
	del_b.text = "Delete"
	del_b.custom_minimum_size = Vector2(80, 32)
	del_b.disabled = not occupied
	del_b.pressed.connect(_open_delete.bind(slot))
	RetrowaveTheme.style_danger_button(del_b)
	actions.add_child(del_b)

	return row


func _format_detail(meta: Dictionary) -> String:
	if meta.is_empty():
		return "Occupied (no metadata)"
	var parts: PackedStringArray = []
	var sc := str(meta.get("scenario_id", "")).strip_edges()
	var tag := str(meta.get("player_tag", "")).strip_edges()
	var ts := str(meta.get("timestamp", meta.get("last_played", ""))).strip_edges()
	var ver := str(meta.get("game_version", "")).strip_edges()
	if not sc.is_empty():
		parts.append(sc.replace("_", " "))
	if not tag.is_empty():
		parts.append(tag)
	if not ts.is_empty():
		parts.append(ts.substr(0, mini(19, ts.length())))
	if not ver.is_empty():
		parts.append("v%s" % ver)
	return " · ".join(parts) if parts.size() > 0 else "Occupied"


func _on_load_slot(slot: String) -> void:
	print("MainMenu: load slot=", slot)
	var slm := _slm()
	if slm == null or not slm.has_method("load_game_detailed"):
		_set_status("LOAD FAILED: SaveLoadManager missing")
		_toast("Load system unavailable.", 3.0, true)
		return
	if slm.has_method("check_scenario_compatibility"):
		var compat: Dictionary = slm.call("check_scenario_compatibility", slot)
		if not compat.get("compatible", true):
			var msg := "Scenario mismatch: save is %s, current is %s." % [
				str(compat.get("saved_scenario", "?")),
				str(compat.get("current_scenario", "?")),
			]
			_set_status(msg)
			_toast(msg, 3.5, true)
			return
	_set_status("Loading \"%s\"…" % slot)
	var result: Dictionary = slm.call("load_game_detailed", slot)
	if bool(result.get("ok", false)):
		_set_status("Loaded \"%s\"" % slot)
		_toast("Loaded %s" % slot, 2.0)
		print("MainMenu: load ok → %s" % slot)
		_sync_hud_after_load()
		_force_close()
	else:
		var err := str(result.get("error", "Load failed"))
		_set_status("LOAD FAILED: %s" % err)
		_toast(err, 3.5, true)
		push_error("MainMenu: load failed %s" % err)


func _sync_hud_after_load() -> void:
	var top_bar: Node = null
	if get_tree() != null:
		top_bar = TopInfoBar.find_in_tree(get_tree())
	if top_bar != null:
		if top_bar.has_method("_update_date_time"):
			top_bar.call("_update_date_time")
		if top_bar.has_method("_update_resources"):
			top_bar.call("_update_resources")


func _ensure_dialogs() -> void:
	_delete_confirm = ConfirmationDialog.new()
	_delete_confirm.title = "Delete save"
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_confirm)

	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Rename save"
	_rename_dialog.ok_button_text = "Rename"
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	_rename_field = LineEdit.new()
	_rename_field.placeholder_text = "New slot name"
	_rename_dialog.add_child(_rename_field)
	add_child(_rename_dialog)

	_save_as_dialog = AcceptDialog.new()
	_save_as_dialog.title = "Save As"
	_save_as_dialog.ok_button_text = "Save"
	_save_as_dialog.confirmed.connect(_on_save_as_confirmed)
	_save_as_field = LineEdit.new()
	_save_as_field.placeholder_text = "Slot name (e.g. campaign_01)"
	_save_as_dialog.add_child(_save_as_field)
	add_child(_save_as_dialog)


func _open_save_as_dialog() -> void:
	_save_as_field.text = ""
	_save_as_dialog.popup_centered(Vector2i(420, 140))
	_save_as_field.grab_focus()


func _on_save_as_confirmed() -> void:
	var slot := _sanitize_slot_name(_save_as_field.text)
	if slot.is_empty():
		_toast("Enter letters, numbers, underscore.", 2.5, true)
		return
	_save_to_slot(slot)


func _open_delete(slot: String) -> void:
	_pending_delete_slot = slot
	_delete_confirm.dialog_text = "Delete save \"%s\"? This cannot be undone." % slot
	_delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	var slot := _pending_delete_slot
	_pending_delete_slot = ""
	var slm := _slm()
	if slot.is_empty() or slm == null:
		return
	if slm.has_method("delete_save") and slm.call("delete_save", slot):
		_set_status("Deleted \"%s\"" % slot)
		_refresh_save_list()
	else:
		_set_status("Could not delete \"%s\"" % slot)


func _open_rename(slot: String) -> void:
	_pending_rename_slot = slot
	_rename_field.text = slot
	_rename_dialog.popup_centered(Vector2i(400, 140))
	_rename_field.grab_focus()


func _on_rename_confirmed() -> void:
	var old_s := _pending_rename_slot
	var new_s := _sanitize_slot_name(_rename_field.text)
	_pending_rename_slot = ""
	if old_s.is_empty() or new_s.is_empty() or new_s == old_s:
		return
	var slm := _slm()
	if slm and slm.has_method("rename_save") and slm.call("rename_save", old_s, new_s):
		_set_status("Renamed \"%s\" → \"%s\"" % [old_s, new_s])
		_refresh_save_list()
	else:
		_toast("Rename failed.", 2.5, true)


func _sanitize_slot_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower().replace(" ", "_")
	var cleaned := ""
	for i in s.length():
		var ch := s[i]
		var code := ch.unicode_at(0)
		var ok := (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or ch == "_" or ch == "-"
		if ok:
			cleaned += ch
	return cleaned


func _open_trade_market() -> void:
	var existing := get_tree().root.get_node_or_null("TradeMarketView")
	if existing != null:
		existing.queue_free()
		_toast("Trade market closed.", 1.5)
		return
	var packed := load("res://scenes/ui/TradeMarketView.tscn")
	if packed == null:
		_toast("Trade Market not available.", 2.5, true)
		return
	var view = packed.instantiate()
	view.name = "TradeMarketView"
	get_tree().root.add_child(view)
	if view.has_method("show_market"):
		view.show_market("PUBLIC")
	elif view.has_method("popup_centered"):
		view.popup_centered(Vector2i(1100, 700))
	_force_close()


func _show_help() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Epochs of Ascendancy — First Session"
	dlg.dialog_text = (
		"Epochs of Ascendancy — First Session\n\n"
		+ "Command Center: Save / Load slots · ESC resumes map\n\n"
		+ "— Session —\n"
		+ "Ctrl+S — Quicksave\n"
		+ "Ctrl+L — Quickload\n"
		+ "Ctrl+Shift+S — Save browser\n"
		+ "ESC — Dismiss overlays / Command Center\n\n"
		+ "— War path —\n"
		+ "B — Live border Fronts\n"
		+ "Shift+I — WarLoop first-session path\n"
		+ "I — EquipmentFlow glyphs\n"
		+ "G — Supply corridor hub → front\n"
		+ "Ctrl+click — Assault adjacent enemy\n\n"
		+ "— Mapmodes —\n"
		+ "F1–F4 political/strain/vitality/development\n"
		+ "F5 supply · F6 loyalty · F7 infra · F8 weather\n"
		+ "F9 resources · Shift+F9 states · Ctrl+F9 terrain\n\n"
		+ "— Navigation —\n"
		+ "Home Europe · Shift+Home world · End Asia · Shift+U unit counters\n\n"
		+ "Default play as GER (Europe Maginot theater)."
	)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(560, 420))


func _return_to_title() -> void:
	_closing = true
	_set_status("Reloading…")
	_pause_game(false)
	menu_closed.emit()
	queue_free()
	get_tree().change_scene_to_file("res://scenes/TestScenario.tscn")


func _force_close() -> void:
	if _closing:
		_pause_game(false)
		menu_closed.emit()
		queue_free()
		return
	_closing = true
	_pause_game(false)
	menu_closed.emit()
	queue_free()


func _pause_game(pause: bool) -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	if pause:
		if not has_meta("was_paused_before_menu"):
			set_meta("was_paused_before_menu", TimeManager.is_paused())
		TimeManager.set_paused(true)
		if Engine.time_scale < 0.001:
			Engine.time_scale = 1.0
	else:
		var was_paused: bool = get_meta("was_paused_before_menu", true)
		TimeManager.set_paused(was_paused)
		Engine.time_scale = 1.0
		if has_meta("was_paused_before_menu"):
			remove_meta("was_paused_before_menu")
		var top_bar: Node = TopInfoBar.find_in_tree(get_tree()) if get_tree() != null else null
		if top_bar != null:
			if top_bar.has_method("_sync_pause_from_time_manager"):
				top_bar.call("_sync_pause_from_time_manager")
			if top_bar.has_method("_update_speed_buttons"):
				top_bar.call("_update_speed_buttons")


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func _toast(message: String, duration: float = 2.5, is_error: bool = false) -> void:
	# Autoload node — call methods on the instance, never class_name.has_method (illegal in 4.7).
	var lui: Node = get_tree().root.get_node_or_null("/root/LeaderEventUI") if get_tree() else null
	if lui != null and lui.has_method("show_toast"):
		lui.call("show_toast", message, duration, is_error)
