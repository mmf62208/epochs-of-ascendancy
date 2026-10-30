# scripts/ui/CampaignInkEndScreen.gd
## Ink end screen. 760×520 BG_PANEL. Shown headless so tests can see it.
## Layer 125, under Command Center (130). Esc does nothing.
class_name CampaignInkEndScreen
extends CanvasLayer

const PANEL_SIZE := Vector2(760, 520)

static var present_log: Array = []

var _outcome: String = "loss"
var _tag: String = ""
var _reason: String = ""
var _clock_lock_held: bool = false


static func clear_log() -> void:
	present_log.clear()


static func log_entries() -> Array:
	return present_log.duplicate()


static func present_loss(tag: String, reason: String) -> Node:
	present_log.append("end_screen")
	return _open("loss", tag, reason)


static func present_win(tag: String, reason: String) -> Node:
	present_log.append("end_screen")
	return _open("win", tag, reason)


static func _open(outcome: String, tag: String, reason: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	for n in tree.get_nodes_in_group("campaign_ink_end_screen"):
		if is_instance_valid(n):
			n.queue_free()
	var layer := CampaignInkEndScreen.new()
	layer._outcome = outcome
	layer._tag = tag.strip_edges().to_upper()
	layer._reason = reason
	layer.layer = 125
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	return layer


func _ready() -> void:
	add_to_group("campaign_ink_end_screen")
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_acquire_clock_lock()
	var dim := ColorRect.new()
	dim.name = "Dimmer"
	dim.color = Color(RetrowaveTheme.BG_DEEP.r, RetrowaveTheme.BG_DEEP.g, RetrowaveTheme.BG_DEEP.b, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_swallow_input)
	add_child(dim)

	var panel := Panel.new()
	panel.name = "InkEndPanel"
	panel.custom_minimum_size = PANEL_SIZE
	panel.size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var win := _outcome == "win"
	var border := RetrowaveTheme.SUCCESS if win else RetrowaveTheme.WARNING
	var style := StyleBoxFlat.new()
	style.bg_color = RetrowaveTheme.BG_PANEL
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_place_panel(panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 28
	box.offset_top = 24
	box.offset_right = -28
	box.offset_bottom = -20
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.name = "OutcomeTitle"
	title.text = "VICTORY" if win else "DEFEAT"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", border)
	box.add_child(title)

	var sub := Label.new()
	sub.name = "OutcomeSubtitle"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if win:
		sub.text = "Your strategy prevailed.\nKeep playing to shape the decades ahead."
	else:
		sub.text = "Your government has fallen.\nHistory isn't finished. Continue as another nation, or load a save."
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", RetrowaveTheme.TEXT_PRIMARY)
	box.add_child(sub)

	var when := Label.new()
	when.name = "OutcomeWhen"
	when.text = _when_line()
	when.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(when)
	box.add_child(when)

	if not _reason.strip_edges().is_empty():
		var why := Label.new()
		why.name = "OutcomeReason"
		why.text = _reason
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(why)
		box.add_child(why)

	var stats := Label.new()
	stats.name = "OutcomeStats"
	stats.text = _stats_line()
	RetrowaveTheme.style_body_label(stats)
	box.add_child(stats)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	if win:
		row.add_child(_make_button("BtnKeepPlaying", "Keep playing", true, _on_keep))
		row.add_child(_make_button("BtnSave", "Save", false, _on_save))
		row.add_child(_make_button("BtnMainMenu", "Main menu", false, _on_main_menu))
	else:
		var cont := _make_button("BtnContinueAs", "Continue as…", true, _on_continue)
		cont.tooltip_text = "Pick a successor nation and keep this world going."
		row.add_child(cont)
		row.add_child(_make_button("BtnLoadSave", "Load save", false, _on_load))
		row.add_child(_make_button("BtnMainMenu", "Main menu", false, _on_main_menu))


func _place_panel(panel: Control) -> void:
	var vp := Vector2(1280, 800)
	var tree := get_tree()
	if tree != null and tree.root != null and tree.root.get_viewport() != null:
		vp = tree.root.get_viewport().get_visible_rect().size
	panel.position = Vector2(maxf(16.0, (vp.x - PANEL_SIZE.x) * 0.5), maxf(16.0, (vp.y - PANEL_SIZE.y) * 0.5))


func _make_button(node_name: String, label: String, primary: bool, cb: Callable) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = label
	btn.custom_minimum_size = Vector2(180, 44)
	btn.focus_mode = Control.FOCUS_ALL
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(cb)
	if primary:
		RetrowaveTheme.style_primary_button(btn)
	else:
		RetrowaveTheme.style_secondary_button(btn)
	return btn


func _nation_line() -> String:
	var tag := _tag
	var tree := get_tree()
	if tree != null and tree.root != null:
		var slm := tree.root.get_node_or_null("SaveLoadManager")
		if slm != null and slm.has_method("nation_card_line"):
			return str(slm.call("nation_card_line", tag))
	return tag


func _format_iso(iso: String) -> String:
	var tree := get_tree()
	if tree != null and tree.root != null:
		var slm := tree.root.get_node_or_null("SaveLoadManager")
		if slm != null and slm.has_method("format_game_date_display"):
			return str(slm.call("format_game_date_display", iso))
	return iso


func _when_line() -> String:
	var start := ""
	var today := ""
	if typeof(TimeManager) != TYPE_NIL:
		start = str(TimeManager.scenario_start_date).strip_edges()
		today = "%04d-%02d-%02d" % [
			int(TimeManager.current_year),
			int(TimeManager.current_month),
			int(TimeManager.current_day),
		]
	var a := _format_iso(start) if start.length() >= 10 else start
	var b := _format_iso(today)
	if a == "—":
		a = start
	return "%s · %s – %s" % [_nation_line(), a, b]


func _stats_line() -> String:
	var days := 0
	if typeof(TimeManager) != TYPE_NIL:
		days = int(TimeManager.total_days_elapsed)
	var held := 0
	var vp := 0
	var tag := _tag
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces") and not tag.is_empty():
		var provinces: Dictionary = MapManager.get_all_provinces()
		for pid in provinces.keys():
			var prov: Variant = provinces[pid]
			if prov == null:
				continue
			var ctrl := str(prov.controller_tag).strip_edges().to_upper() if "controller_tag" in prov else ""
			if ctrl != tag:
				continue
			held += 1
			vp += int(prov.victory_points) if "victory_points" in prov else 0
	return "Day %d · %d victory points · %d provinces held" % [days, vp, held]


func _input(event: InputEvent) -> void:
	if _is_escape(event):
		get_viewport().set_input_as_handled()


func _swallow_input(event: InputEvent) -> void:
	if _is_escape(event):
		get_viewport().set_input_as_handled()


func _is_escape(event: InputEvent) -> bool:
	if event == null:
		return false
	if event.is_action_pressed("ui_cancel"):
		return true
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE)
	return false


func _on_continue() -> void:
	var scr: Script = load("res://scripts/ui/PeaceConferenceWindow.gd") as Script
	if scr != null and scr.has_method("open_continuation_picker"):
		scr.call("open_continuation_picker")
	present_log.append("picker")


func _on_keep() -> void:
	var dom: Script = load("res://scripts/core/CampaignInkEndDomain.gd") as Script
	if dom != null and dom.has_method("note_keep_playing"):
		dom.call("note_keep_playing")
	_dismiss_end_screen()


func _acquire_clock_lock() -> void:
	if _clock_lock_held:
		return
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("acquire_overlay_clock_lock"):
		TimeManager.acquire_overlay_clock_lock()
		_clock_lock_held = true
	elif typeof(TimeManager) != TYPE_NIL:
		TimeManager.set_paused(true)


func _release_clock_lock() -> void:
	if not _clock_lock_held:
		return
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("release_overlay_clock_lock"):
		TimeManager.release_overlay_clock_lock()
	_clock_lock_held = false


func _dismiss_end_screen() -> void:
	remove_from_group("campaign_ink_end_screen")
	name = "CampaignInkEndScreen_dying"
	_release_clock_lock()
	queue_free()


func _exit_tree() -> void:
	_release_clock_lock()


func _on_save() -> void:
	if typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("save_game_detailed"):
		SaveLoadManager.save_game_detailed("quicksave")
	_open_command_center()


func _on_load() -> void:
	_open_command_center()


func _on_main_menu() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.change_scene_to_file("res://scenes/TestScenario.tscn")


func _open_command_center() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var bar := tree.get_first_node_in_group("top_info_bar")
	if bar != null and bar.has_method("_open_command_center"):
		bar.call("_open_command_center", true)
		return
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	tree.root.add_child(menu)
