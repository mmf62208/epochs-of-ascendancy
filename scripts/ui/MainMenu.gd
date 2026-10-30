# scripts/ui/MainMenu.gd
## In-game command center (CanvasLayer overlay — not a native OS window).
## Left: actions · Right: save browser with real slots · ESC / Close works always.
class_name MainMenu
extends CanvasLayer

const MENU_WIDTH := 960.0
const MENU_HEIGHT := 680.0
## Above living title (120) and UILayer HUD (110) so Esc→CC is not buried under the bar.
const COMMAND_CENTER_LAYER := 130
const LIVING_CC_NATIONS := ["GER", "ENG", "FRA", "JAP", "USA", "SOV", "ITA", "POL"]
const LIVING_CC_ERAS := [1918, 1936, 2026]

signal menu_closed


## Facts for the Command Center living campaign pick. Unknown tag/year → GER 1936.
static func living_campaign_pick_facts(tag: String = "GER", year: int = 1936) -> Dictionary:
	var t := tag.strip_edges().to_upper()
	var defaulted := false
	if t.is_empty() or not LIVING_CC_NATIONS.has(t):
		t = "GER"
		defaulted = true
	var y := int(year)
	if y != 1918 and y != 1936 and y != 2026:
		y = 1936
		defaulted = true
	return {
		"ok": true,
		"player_tag": t,
		"year": y,
		"era": y,
		"nations": LIVING_CC_NATIONS.duplicate(),
		"eras": LIVING_CC_ERAS.duplicate(),
		"default_ger": t == "GER",
		"default_1936": y == 1936,
		"defaulted": defaulted,
		"live": true,
	}


## Apply a Command Center nation/era pick. Headless-safe (no Window). Env boot in TestRunner stays.
static func apply_living_campaign_pick(tag: String = "GER", year: int = 1936) -> Dictionary:
	var facts: Dictionary = living_campaign_pick_facts(tag, year)
	var t := str(facts.get("player_tag", "GER"))
	var y := int(facts.get("year", 1936))
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("boot_living_player"):
		var nation: Dictionary = LeaderManager.boot_living_player(t)
		facts["nation"] = nation
		facts["player_tag"] = str(nation.get("player_tag", t))
	elif typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("set_player_country_tag"):
		LeaderManager.set_player_country_tag(t)
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("boot_living_era"):
		var era: Dictionary = TimeManager.boot_living_era(y)
		facts["era_boot"] = era
		facts["year"] = int(era.get("year", y))
		facts["era"] = int(era.get("era", y))
	var resolved := str(facts.get("player_tag", t)).strip_edges().to_upper()
	if resolved.is_empty():
		resolved = t
	if typeof(SessionPlayers) != TYPE_NIL and SessionPlayers.has_method("adopt_living_human"):
		SessionPlayers.adopt_living_human(resolved)
	facts["ok"] = true
	facts["applied"] = true
	return facts

var _closing := false
var _root: Control
var _panel: PanelContainer
var _options_vbox: VBoxContainer
var _save_list_vbox: VBoxContainer
var _status_label: Label
var _blocker: ColorRect

var _delete_confirm: ConfirmationDialog
var _pending_delete_slot := ""
var _confirm_layer: Control = null
var _rename_dialog: AcceptDialog
var _rename_field: LineEdit
var _pending_rename_slot := ""
var _save_as_dialog: AcceptDialog
var _save_as_field: LineEdit
var _nation_btns: Dictionary = {}
var _era_btns: Dictionary = {}
## Edge-trigger for `_process` pointer poll (computerUse leftover on CloseX).
var _close_ptr_poll_held: bool = false
var _clock_lock_held: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = COMMAND_CENTER_LAYER
	_build_ui()
	_ensure_dialogs()
	_acquire_clock_lock()
	_set_status("Paused · Save / Load slots on the right · ESC or Close to resume")
	_refresh_save_list()
	set_process_input(true)
	set_process_unhandled_input(true)


func _node_is_open_living_title(n: Node) -> bool:
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		return false
	if not str(n.name).begins_with("LivingTitleBoot"):
		return false
	if bool(n.get("_closed")):
		return false
	return true


func _any_open_living_title(n: Node) -> bool:
	if _node_is_open_living_title(n):
		return true
	for child in n.get_children():
		if _any_open_living_title(child):
			return true
	return false


func _living_title_is_up() -> bool:
	# Walk the tree (do not use find_child — queued leftovers lie title_up=false).
	# Do not reference LivingTitleBoot class_name (-s harness parse).
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	if tree.root != null and _any_open_living_title(tree.root):
		return true
	if tree.current_scene != null and _any_open_living_title(tree.current_scene):
		return true
	return false


func _find_open_living_title(n: Node) -> Node:
	if _node_is_open_living_title(n):
		return n
	for child in n.get_children():
		var found := _find_open_living_title(child)
		if found != null:
			return found
	return null


func _first_open_living_title() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	if tree.root != null:
		var from_root := _find_open_living_title(tree.root)
		if from_root != null:
			return from_root
	if tree.current_scene != null:
		return _find_open_living_title(tree.current_scene)
	return null


func _close_for_living_title_esc() -> void:
	# Title Esc closes. The press that opened this overlay must not also close it.
	var title_up_now := _living_title_is_up()
	var title := _first_open_living_title()
	if title != null and title.has_method("title_esc_opened_this_frame") and bool(title.call("title_esc_opened_this_frame")):
		print("EOA_LIVE_ESC who=MainMenu.keep_cc opened_this_frame=1")
		return
	print(
		"EOA_LIVE_ESC who=MainMenu.close_cc title_up=%s from_title_meta=%s"
		% [str(title_up_now), str(has_meta("eoa_opened_from_living_title"))]
	)
	if title != null and title.has_method("note_title_esc_closed"):
		title.call("note_title_esc_closed")
	_force_close()


func _is_live_escape_event(event: InputEvent) -> bool:
	if event is InputEventAction:
		var act: InputEventAction = event
		return bool(act.pressed) and str(act.action) == "ui_cancel"
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return false
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			return true
		if key.key_label == KEY_ESCAPE:
			return true
		if int(key.unicode) == 27:
			return true
	if event != null and event.is_action_pressed("ui_cancel"):
		return true
	return false


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if _confirm_blocks_event(event):
		get_viewport().set_input_as_handled()
		return
	if not _is_live_escape_event(event):
		return
	var title_up_now: bool = _living_title_is_up()
	print(
		"EOA_LIVE_ESC who=MainMenu._input process_mode=%s title_up=%s closing=%s tree=%s"
		% [str(process_mode), str(title_up_now), str(_closing), str(get_tree() != null)]
	)
	if _living_title_is_up() or has_meta("eoa_opened_from_living_title"):
		_close_for_living_title_esc()
		get_viewport().set_input_as_handled()
		return
	_route_escape_to_stack()
	get_viewport().set_input_as_handled()


func _route_escape_to_stack() -> void:
	# One owner: MapRenderer walks search → inspector → Command Center.
	# Closing here as well made the first Esc skip the layers underneath.
	var tree := get_tree()
	var mr: Node = tree.get_first_node_in_group("map_renderer") if tree != null else null
	if mr != null and mr.has_method("_handle_escape_key"):
		mr.call("_handle_escape_key")
		return
	_force_close()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if _confirm_blocks_event(event):
		get_viewport().set_input_as_handled()
		return
	if not _is_live_escape_event(event):
		return
	print(
		"EOA_LIVE_ESC who=MainMenu._unhandled_input process_mode=%s title_up=%s"
		% [str(process_mode), str(_living_title_is_up())]
	)
	if _living_title_is_up() or has_meta("eoa_opened_from_living_title"):
		_close_for_living_title_esc()
		get_viewport().set_input_as_handled()
		return
	_route_escape_to_stack()
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
	_panel.clip_contents = true
	_root.add_child(_panel)
	RetrowaveTheme.style_menu_panel(_panel)

	# Child minimum sizes (autowrap labels, the save list) must not grow the
	# panel past the viewport. This slot reports a small minimum and fits
	# its child to the panel rect, so Settings stay inside 1280×800.
	var slot := _PanelSlot.new()
	slot.name = "PanelSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(slot)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	slot.add_child(margin)

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
	title_row.name = "CommandCenterHeader"
	title_row.mouse_filter = Control.MOUSE_FILTER_STOP
	title_row.add_theme_constant_override("separation", 8)
	outer.add_child(title_row)

	var title := Label.new()
	title.name = "CommandCenterTitle"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	var pause_menu := not _living_title_is_up() and not has_meta("eoa_opened_from_living_title")
	title.text = "Paused" if pause_menu else "Command Center"
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
	# Press closes even when the title overlay eats the matching release.
	close_x.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	close_x.add_to_group("eoa_ui_close_x")
	# Press arms leftover-release swallow before MapRenderer `_input` sees the up.
	close_x.button_down.connect(_on_close_x_button_down)
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

	# --- Left: actions scroll, settings pinned so Mute stays on screen ---
	var left := VBoxContainer.new()
	left.name = "GameActions"
	# Wide enough for Master slider + Mute on one row at 1280×800.
	left.custom_minimum_size = Vector2(340, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	content.add_child(left)

	var left_scroll := ScrollContainer.new()
	left_scroll.name = "GameActionsScroll"
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	left.add_child(left_scroll)

	var left_inner := VBoxContainer.new()
	left_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_inner.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left_inner)

	var left_hdr := Label.new()
	left_hdr.text = "GAME"
	RetrowaveTheme.style_column_header(left_hdr)
	left_inner.add_child(left_hdr)

	_options_vbox = left_inner
	if pause_menu:
		var resume := Button.new()
		resume.name = "BtnResume"
		resume.text = "Resume"
		resume.custom_minimum_size = Vector2(0, 38)
		resume.focus_mode = Control.FOCUS_ALL
		resume.process_mode = Node.PROCESS_MODE_ALWAYS
		resume.mouse_filter = Control.MOUSE_FILTER_STOP
		resume.pressed.connect(_force_close)
		RetrowaveTheme.style_primary_button(resume)
		left_inner.add_child(resume)
	_add_action_button(left_inner, "Save Game (quicksave)", "save", not pause_menu)
	_add_action_button(left_inner, "Save As…", "save_as", false)
	_add_action_button(left_inner, "Refresh save list", "refresh", false)
	_add_action_button(left_inner, "Trade Market", "trade_market", true)
	_add_action_button(left_inner, "Help / About", "help", false)
	_add_action_button(left_inner, "Return to Title", "return_to_main", false)
	_add_action_button(left_inner, "Exit to Desktop", "exit", false, true)

	var new_game := VBoxContainer.new()
	new_game.name = "NewGameBlock"
	new_game.add_to_group("eoa_cc_new_game")
	new_game.add_theme_constant_override("separation", 8)
	new_game.visible = not pause_menu
	left_inner.add_child(new_game)
	var camp_hdr := Label.new()
	camp_hdr.text = "CAMPAIGN"
	RetrowaveTheme.style_column_header(camp_hdr)
	new_game.add_child(camp_hdr)
	var camp_hint := Label.new()
	camp_hint.text = "GER Maginot is the F5 default. Pick a nation and era."
	camp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	camp_hint.custom_minimum_size = Vector2(300, 0)
	RetrowaveTheme.style_body_label(camp_hint)
	new_game.add_child(camp_hint)
	var nation_row_a := HBoxContainer.new()
	nation_row_a.add_theme_constant_override("separation", 4)
	new_game.add_child(nation_row_a)
	var nation_row_b := HBoxContainer.new()
	nation_row_b.add_theme_constant_override("separation", 4)
	new_game.add_child(nation_row_b)
	var ni := 0
	for tag in LIVING_CC_NATIONS:
		var nbtn := Button.new()
		nbtn.text = str(tag)
		nbtn.custom_minimum_size = Vector2(52, 32)
		nbtn.focus_mode = Control.FOCUS_ALL
		nbtn.process_mode = Node.PROCESS_MODE_ALWAYS
		nbtn.pressed.connect(_on_living_nation_pressed.bind(str(tag)))
		if ni < 4:
			nation_row_a.add_child(nbtn)
		else:
			nation_row_b.add_child(nbtn)
		_nation_btns[str(tag)] = nbtn
		ni += 1
	var era_row := HBoxContainer.new()
	era_row.add_theme_constant_override("separation", 4)
	new_game.add_child(era_row)
	for yr in LIVING_CC_ERAS:
		var ebtn := Button.new()
		ebtn.text = str(int(yr))
		ebtn.custom_minimum_size = Vector2(68, 32)
		ebtn.focus_mode = Control.FOCUS_ALL
		ebtn.process_mode = Node.PROCESS_MODE_ALWAYS
		ebtn.pressed.connect(_on_living_era_pressed.bind(int(yr)))
		era_row.add_child(ebtn)
		_era_btns[int(yr)] = ebtn
	_refresh_living_campaign_buttons()

	if OS.is_debug_build():
		var dbg_hdr := Label.new()
		dbg_hdr.text = "DEBUG"
		RetrowaveTheme.style_column_header(dbg_hdr)
		left_inner.add_child(dbg_hdr)
		_add_action_button(left_inner, "Open Debug Overlay (F10)", "debug", false)

	# Pinned under the scroll so Mute is inside the panel at 1280×800.
	_add_audio_settings(left)

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
	sav_hint.name = "SaveListHint"
	sav_hint.text = "Click Save on a slot to write · Load to restore · Save Game uses quicksave · Ctrl+Shift+S opens this list"
	sav_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sav_hint.custom_minimum_size = Vector2(280, 0)
	sav_hint.tooltip_text = "Save / load slots. Ctrl+Shift+S opens this list. F6 is the loyalty mapmode."
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
	close_btn.name = "ReturnToGame"
	close_btn.text = "Return to Game (ESC)"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.add_to_group("eoa_ui_close_x")
	close_btn.button_down.connect(_on_close_x_button_down)
	close_btn.pressed.connect(_force_close)
	RetrowaveTheme.style_primary_button(close_btn)
	outer.add_child(close_btn)

	_center_panel()
	if get_viewport():
		get_viewport().size_changed.connect(_center_panel)


class _PanelSlot extends Container:
	func _get_minimum_size() -> Vector2:
		return Vector2(320, 160)

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN:
			return
		for c in get_children():
			var child := c as Control
			if child == null:
				continue
			fit_child_in_rect(child, Rect2(Vector2.ZERO, size))


func _on_blocker_gui_input(event: InputEvent) -> void:
	# Click outside panel (on dimmed map) closes menu — same as ✕ / ESC.
	# Press and release both stop here so the map never sees them.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if _panel != null and is_instance_valid(_panel):
			var local := _panel.get_global_rect()
			if local.has_point(mb.global_position):
				return
		if mb.pressed:
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


func _audio_node() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("AudioManager")


func _add_audio_settings(parent: VBoxContainer) -> void:
	var block := VBoxContainer.new()
	block.name = "AudioSettings"
	block.add_theme_constant_override("separation", 4)
	parent.add_child(block)
	var hdr := Label.new()
	hdr.text = "SETTINGS"
	RetrowaveTheme.style_column_header(hdr)
	block.add_child(hdr)
	var audio := _audio_node()
	var master_row := _audio_slider("Master", "MasterVolume", _audio_db(audio, "get_master_db", 0.0), "set_master_db")
	var mute := CheckButton.new()
	mute.name = "MuteAudio"
	mute.text = "Mute"
	mute.focus_mode = Control.FOCUS_ALL
	mute.size_flags_horizontal = Control.SIZE_SHRINK_END
	mute.button_pressed = bool(audio.call("is_muted")) if audio != null and audio.has_method("is_muted") else false
	mute.toggled.connect(_on_audio_mute_toggled)
	master_row.add_child(mute)
	block.add_child(master_row)
	block.add_child(_audio_slider("UI", "UiVolume", _audio_db(audio, "get_ui_db", -12.0), "set_ui_db"))
	block.add_child(_audio_slider("SFX", "SfxVolume", _audio_db(audio, "get_sfx_db", 0.0), "set_sfx_db"))


func _audio_db(audio: Node, getter: String, fallback: float) -> float:
	if audio != null and audio.has_method(getter):
		return float(audio.call(getter))
	return fallback


func _audio_slider(label_text: String, node_name: String, value: float, setter: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(64, 0)
	RetrowaveTheme.style_body_label(lab)
	row.add_child(lab)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = -40.0
	slider.max_value = 0.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(80, 20)
	slider.value = value
	slider.value_changed.connect(_on_audio_slider.bind(setter))
	row.add_child(slider)
	return row


func _on_audio_slider(value: float, setter: String) -> void:
	var audio := _audio_node()
	if audio != null and audio.has_method(setter):
		audio.call(setter, value)


func _control_has_point(node: Control, screen: Vector2) -> bool:
	if node == null or not is_instance_valid(node) or not node.visible:
		return false
	return node.get_global_rect().has_point(screen)


func _find_action_button(action_id: String) -> Button:
	var want := action_id.strip_edges()
	for n in find_children("*", "Button", true, false):
		if not (n is Button):
			continue
		var b := n as Button
		if str(b.get_meta("eoa_cc_action", "")) == want and not b.disabled and b.visible:
			return b
	return null


## "refresh", "close", "header", or "" for a screen point. Geometry only.
func live_pointer_target(screen: Vector2) -> String:
	var refresh := _find_action_button("refresh")
	if refresh != null and _control_has_point(refresh, screen):
		return "refresh"
	var close_b := close_x_button()
	if close_b != null and _control_has_point(close_b, screen):
		return "close"
	var header := find_child("CommandCenterHeader", true, false) as Control
	if _control_has_point(header, screen):
		return "header"
	return ""


## One click for a live-pointer hit. Refresh also emits pressed once per frame.
func activate_live_pointer(screen: Vector2) -> String:
	var kind := live_pointer_target(screen)
	if kind == "refresh":
		var am := _audio_node()
		var btn := _find_action_button("refresh")
		if am != null and am.has_method("activate_button"):
			am.call("activate_button", btn)
		elif btn != null:
			btn.pressed.emit()
		return "refresh"
	if kind == "close":
		_play_live_click(close_x_button())
		return "close"
	if kind == "header":
		_play_live_click(find_child("CommandCenterHeader", true, false))
		return "header"
	return ""


func _play_live_click(source: Object) -> void:
	var am := _audio_node()
	if am != null and am.has_method("play_ui_click"):
		am.call("play_ui_click", source)


func _on_audio_mute_toggled(on: bool) -> void:
	var audio := _audio_node()
	if audio != null and audio.has_method("set_muted"):
		audio.call("set_muted", on)


func _add_action_button(parent: VBoxContainer, text: String, id: String, primary: bool, danger: bool = false) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.set_meta("eoa_cc_action", id)
	if id == "refresh":
		btn.name = "RefreshSaveList"
	# Bind by string id (stable); avoid async signal sinks that drop without await.
	btn.pressed.connect(_on_action.bind(id))
	if danger:
		RetrowaveTheme.style_danger_button(btn)
	elif primary:
		RetrowaveTheme.style_primary_button(btn)
	else:
		RetrowaveTheme.style_secondary_button(btn)
	parent.add_child(btn)


func _on_living_nation_pressed(tag: String) -> void:
	var year := 1936
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
		year = int(TimeManager.get_current_year())
	var out: Dictionary = apply_living_campaign_pick(tag, year)
	_refresh_living_campaign_buttons()
	_set_status("Playing %s · %d" % [str(out.get("player_tag", tag)), int(out.get("year", year))])
	_toast("Campaign · %s %d" % [str(out.get("player_tag", tag)), int(out.get("year", year))], 2.5)


func _on_living_era_pressed(year: int) -> void:
	var tag := "GER"
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		tag = str(LeaderManager.get_player_country_tag())
	var out: Dictionary = apply_living_campaign_pick(tag, year)
	_refresh_living_campaign_buttons()
	_set_status("Playing %s · %d" % [str(out.get("player_tag", tag)), int(out.get("year", year))])
	_toast("Era · %d" % int(out.get("year", year)), 2.5)


func _refresh_living_campaign_buttons() -> void:
	var tag := "GER"
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		tag = str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	var year := 1936
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
		year = int(TimeManager.get_current_year())
	for k in _nation_btns.keys():
		var btn: Button = _nation_btns[k]
		if btn == null or not is_instance_valid(btn):
			continue
		if str(k) == tag:
			RetrowaveTheme.style_primary_button(btn)
		else:
			RetrowaveTheme.style_secondary_button(btn)
	for yk in _era_btns.keys():
		var ebtn: Button = _era_btns[yk]
		if ebtn == null or not is_instance_valid(ebtn):
			continue
		if int(yk) == year:
			RetrowaveTheme.style_primary_button(ebtn)
		else:
			RetrowaveTheme.style_secondary_button(ebtn)


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
	var kind := "manual"
	if slm.has_method("slot_kind"):
		kind = str(slm.call("slot_kind", slot))
	if kind == "auto":
		_set_status("Autosave is written by the game. Choose a manual slot.")
		_toast("Autosave is written by the game.", 2.5, true)
		return
	var occupied := false
	if slm.has_method("slot_is_occupied"):
		occupied = bool(slm.call("slot_is_occupied", slot))
	# Quicksave overwrites without a dialog. Occupied manual slots confirm.
	if occupied and kind != "quick":
		_open_overwrite_confirm(slot)
		return
	_write_slot(slot)


func _write_slot(slot: String) -> void:
	var slm := _slm()
	if slm == null or not slm.has_method("save_game_detailed"):
		_set_status("SAVE FAILED: SaveLoadManager missing")
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
	# Free immediately so a rewritten autosave does not leave a stale card
	# (queue_free keeps the old SlotCard_* in the tree until the frame ends).
	while _save_list_vbox.get_child_count() > 0:
		var stale: Node = _save_list_vbox.get_child(0)
		_save_list_vbox.remove_child(stale)
		stale.free()

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
	row.custom_minimum_size = Vector2(0, 112)
	row.name = "SlotCard_%s" % slot
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_detail_panel_flat(row)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	row.add_child(outer)

	var title_row := HBoxContainer.new()
	outer.add_child(title_row)

	var badge := str(info.get("kind_badge", ""))
	var nation_line := str(info.get("nation_line", ""))
	var when_line := str(info.get("when_line", ""))
	var name_l := Label.new()
	name_l.name = "SlotTitle"
	if badge.is_empty():
		name_l.text = label if not label.is_empty() else slot
	else:
		name_l.text = "%s   %s" % [slot, badge]
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 14)
	RetrowaveTheme.style_column_header(name_l)
	title_row.add_child(name_l)

	var st := Label.new()
	st.name = "SlotStatus"
	st.text = "occupied" if occupied else "empty"
	RetrowaveTheme.style_body_label(st)
	if occupied:
		st.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	title_row.add_child(st)

	var detail := Label.new()
	detail.name = "SlotDetail"
	var unreadable := bool(info.get("unreadable", false)) or nation_line.find("unreadable") >= 0
	if unreadable:
		detail.text = "%s\n%s" % [
			nation_line if not nation_line.is_empty() else "Save unreadable",
			when_line if not when_line.is_empty() else "Save unreadable",
		]
		st.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
		st.text = "unreadable"
	elif occupied and not nation_line.is_empty():
		detail.text = "%s\n%s" % [nation_line, when_line]
	elif occupied:
		detail.text = _format_detail(meta)
	else:
		detail.text = "Empty slot — press Save to write here"
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
	load_b.set_meta("eoa_load_slot", slot)
	load_b.pressed.connect(_on_load_slot.bind(slot))
	RetrowaveTheme.style_primary_button(load_b)
	actions.add_child(load_b)

	var save_b := Button.new()
	save_b.text = "Save"
	save_b.custom_minimum_size = Vector2(80, 32)
	var can_save := bool(info.get("can_save", true))
	save_b.disabled = not can_save
	save_b.tooltip_text = "Autosave is written by the game." if not can_save else "Write current game into this slot"
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
	# The same press is delivered by window_input and again by the viewport.
	if _closing:
		print("EOA_LOAD_APPLY skip duplicate slot=%s via=cc" % slot)
		return
	var slm := _slm()
	if slm != null and slm.has_method("load_confirm_required") and bool(slm.call("load_confirm_required", slot)):
		_open_load_confirm(slot)
		return
	_load_slot_now(slot)


func _load_slot_now(slot: String) -> void:
	if _closing:
		print("EOA_LOAD_APPLY skip duplicate slot=%s via=cc" % slot)
		return
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
	if bool(result.get("duplicate", false)):
		print("EOA_LOAD_APPLY skip duplicate slot=%s via=cc" % slot)
		return
	if bool(result.get("ok", false)):
		_set_status("Loaded \"%s\"" % slot)
		_toast("Loaded %s" % slot, 2.0)
		print("MainMenu: load ok → %s" % slot)
		_sync_hud_after_load()
		# Closing the menu must not put the pre-menu clock back over the save.
		set_meta("eoa_loaded_clock", true)
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


func _confirm_visible() -> bool:
	return _confirm_layer != null and is_instance_valid(_confirm_layer) and _confirm_layer.visible


func _dismiss_confirm() -> void:
	if _confirm_layer != null and is_instance_valid(_confirm_layer):
		_confirm_layer.queue_free()
	_confirm_layer = null


func _confirm_blocks_event(event: InputEvent) -> bool:
	if not _confirm_visible() or event == null:
		return false
	if _is_live_escape_event(event):
		_dismiss_confirm()
		_pending_delete_slot = ""
		return true
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	var accept := key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.physical_keycode == KEY_ENTER
	if not accept and key.is_action_pressed("ui_accept"):
		accept = true
	if not accept:
		return false
	# Delete: Enter does nothing. Other confirms: Enter confirms.
	if _confirm_layer != null and str(_confirm_layer.name) == "DeleteSaveConfirm":
		return true
	_activate_confirm()
	return true


func _activate_confirm() -> void:
	if _confirm_layer == null or not is_instance_valid(_confirm_layer):
		return
	var btn: Node = _confirm_layer.find_child("BtnLoad", true, false)
	if btn == null:
		btn = _confirm_layer.find_child("BtnDanger", true, false)
	if btn is BaseButton:
		(btn as BaseButton).pressed.emit()


func _open_text_confirm(node_name: String, title: String, body: String, action_label: String, on_action: Callable, save_first_slot: String = "") -> void:
	_dismiss_confirm()
	if _root == null or not is_instance_valid(_root):
		return
	var host := Control.new()
	host.name = node_name
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	host.z_index = 40
	_root.add_child(host)
	_confirm_layer = host
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)
	var panel := Panel.new()
	panel.name = "ConfirmPanel"
	panel.custom_minimum_size = Vector2(420, 180)
	panel.size = Vector2(420, 180)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = RetrowaveTheme.BG_PANEL
	style.border_color = RetrowaveTheme.WARNING
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	var vp := Vector2(960, 680)
	if get_viewport() != null:
		vp = get_viewport().get_visible_rect().size
	panel.position = Vector2(maxf(8.0, (vp.x - 420.0) * 0.5), maxf(8.0, (vp.y - 180.0) * 0.5))
	host.add_child(panel)
	var title_l := Label.new()
	title_l.name = "ConfirmTitle"
	title_l.text = title
	title_l.position = Vector2(16, 14)
	title_l.size = Vector2(388, 28)
	title_l.add_theme_font_size_override("font_size", 16)
	title_l.add_theme_color_override("font_color", RetrowaveTheme.TEXT_PRIMARY)
	panel.add_child(title_l)
	var body_l := Label.new()
	body_l.name = "ConfirmBody"
	body_l.text = body
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_l.position = Vector2(16, 48)
	body_l.size = Vector2(388, 68)
	body_l.add_theme_font_size_override("font_size", 14)
	body_l.add_theme_color_override("font_color", RetrowaveTheme.TEXT_PRIMARY)
	panel.add_child(body_l)
	var cancel := Button.new()
	cancel.name = "BtnCancel"
	cancel.text = "Cancel"
	cancel.position = Vector2(300, 128)
	cancel.custom_minimum_size = Vector2(104, 36)
	cancel.focus_mode = Control.FOCUS_ALL
	cancel.process_mode = Node.PROCESS_MODE_ALWAYS
	cancel.pressed.connect(func() -> void:
		_pending_delete_slot = ""
		_dismiss_confirm()
	)
	RetrowaveTheme.style_secondary_button(cancel)
	panel.add_child(cancel)
	if not save_first_slot.is_empty():
		var save_first := Button.new()
		save_first.name = "BtnSaveFirst"
		save_first.text = "Save first"
		save_first.position = Vector2(150, 128)
		save_first.custom_minimum_size = Vector2(140, 36)
		var load_slot := save_first_slot
		save_first.pressed.connect(func() -> void:
			_dismiss_confirm()
			_write_slot("quicksave")
			_load_slot_now(load_slot)
		)
		RetrowaveTheme.style_secondary_button(save_first)
		panel.add_child(save_first)
		var load_b := Button.new()
		load_b.name = "BtnLoad"
		load_b.text = action_label
		load_b.position = Vector2(16, 128)
		load_b.custom_minimum_size = Vector2(120, 36)
		load_b.pressed.connect(func() -> void:
			_dismiss_confirm()
			on_action.call()
		)
		RetrowaveTheme.style_primary_button(load_b)
		panel.add_child(load_b)
	else:
		var danger := Button.new()
		danger.name = "BtnDanger"
		danger.text = action_label
		danger.position = Vector2(16, 128)
		danger.custom_minimum_size = Vector2(140, 36)
		danger.pressed.connect(func() -> void:
			_dismiss_confirm()
			on_action.call()
		)
		RetrowaveTheme.style_danger_button(danger)
		panel.add_child(danger)
	cancel.call_deferred("grab_focus")


func _open_overwrite_confirm(slot: String) -> void:
	var blurb := "'%s' will be replaced. This can't be undone." % slot
	var slm := _slm()
	if slm != null and slm.has_method("slot_replace_blurb"):
		blurb = str(slm.call("slot_replace_blurb", slot))
	_open_text_confirm("OverwriteSaveConfirm", "Overwrite save?", blurb, "Overwrite", _write_slot.bind(slot))


func _open_load_confirm(slot: String) -> void:
	_open_text_confirm(
		"LoadUnsavedConfirm",
		"Load '%s'?" % slot,
		"Progress since your last save will be lost.",
		"Load",
		_load_slot_now.bind(slot),
		slot
	)


func open_delete_confirm(slot: String) -> void:
	_open_delete(slot)


func _open_delete(slot: String) -> void:
	_pending_delete_slot = slot
	_open_text_confirm(
		"DeleteSaveConfirm",
		"Delete save?",
		"'%s' will be permanently deleted." % slot,
		"Delete",
		_on_delete_confirmed
	)


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
		+ "Command Center: Save / Load slots · pick GER/ENG/FRA/JAP · 1918/1936/2026 · ESC resumes map\n"
		+ "Title: pick scenario date, country, or load a save (map stays live underneath)\n\n"
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
		+ "Default F5 play as GER 1936 (Europe Maginot theater). Env EOA_PLAYER_TAG / EOA_START_YEAR still override boot."
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


func _map_renderer_for_close() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var mr: Node = tree.get_first_node_in_group("map_renderer")
	if mr != null:
		return mr
	if tree.root != null:
		return tree.root.find_child("MapRenderer", true, false)
	return null


func arm_cc_close_release_swallow(pending_press: bool = false) -> void:
	var mr: Node = _map_renderer_for_close()
	if mr != null and mr.has_method("arm_ui_close_release_swallow"):
		mr.call("arm_ui_close_release_swallow", pending_press)


func _on_close_x_button_down() -> void:
	# Real press reached CloseX — do not also poll-close on this hold.
	_close_ptr_poll_held = true
	arm_cc_close_release_swallow()


func close_x_button() -> Button:
	return find_child("CloseX", true, false) as Button


func handle_live_close_pointer(event: InputEvent = null) -> String:
	# Poll / event backup when computerUse never delivers button_down on ✕.
	var btn: Button = close_x_button()
	if btn == null or not is_instance_valid(btn):
		return "none"
	var pts: Array[Vector2] = []
	if event is InputEventMouse:
		var em: InputEventMouse = event as InputEventMouse
		pts.append(em.position)
		pts.append(em.global_position)
	var vp: Viewport = get_viewport()
	if vp != null:
		pts.append(vp.get_mouse_position())
	var ds_mouse: Vector2i = DisplayServer.mouse_get_position()
	pts.append(Vector2(float(ds_mouse.x), float(ds_mouse.y)))
	var rect: Rect2 = btn.get_global_rect()
	var over: bool = false
	for p in pts:
		if rect.has_point(p):
			over = true
			break
	if not over:
		return "miss"
	arm_cc_close_release_swallow(event == null)
	_force_close()
	return "close"


func _os_left_button_held() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return false
	return (int(DisplayServer.mouse_get_button_state()) & int(MOUSE_BUTTON_MASK_LEFT)) != 0


func _poll_close_x_just_pressed() -> bool:
	var held: bool = _os_left_button_held()
	if held:
		if _close_ptr_poll_held:
			return false
		_close_ptr_poll_held = true
		return true
	_close_ptr_poll_held = false
	return false


func _process(_delta: float) -> void:
	if _closing:
		return
	if _poll_close_x_just_pressed():
		handle_live_close_pointer(null)


func _clear_title_pending_pointer() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var stack: Array[Node] = []
	if tree.root != null:
		stack.append(tree.root)
	if tree.current_scene != null:
		stack.append(tree.current_scene)
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n != null and is_instance_valid(n) and str(n.name).begins_with("LivingTitleBoot"):
			if n.has_method("clear_pending_pointer"):
				n.call("clear_pending_pointer")
		if n == null:
			continue
		for c in n.get_children():
			stack.append(c)


func _force_close() -> void:
	# Swallow is armed on CloseX button_down / poll handle, not here.
	# `_force_close` re-arm cleared poll `pending_press` (same-spot stayed dead).
	# Esc, X, and the backdrop all land here. Drop the title latch so the next
	# Begin click is not a leftover passthrough, and drop any map press.
	_clear_title_pending_pointer()
	var mr_close := _map_renderer_for_close()
	if mr_close != null and mr_close.has_method("clear_overlay_close_map_gesture"):
		mr_close.call("clear_overlay_close_map_gesture")
	if _closing:
		_release_clock_lock()
		menu_closed.emit()
		queue_free()
		return
	_closing = true
	_release_clock_lock()
	menu_closed.emit()
	queue_free()


func _acquire_clock_lock() -> void:
	if _clock_lock_held:
		return
	if typeof(TimeManager) == TYPE_NIL:
		return
	if TimeManager.has_method("acquire_overlay_clock_lock"):
		TimeManager.acquire_overlay_clock_lock()
		_clock_lock_held = true
		return
	_pause_game(true)


func _release_clock_lock() -> void:
	if not _clock_lock_held:
		return
	if Engine.time_scale < 0.001:
		Engine.time_scale = 1.0
	if typeof(TimeManager) != TYPE_NIL:
		if has_meta("eoa_loaded_clock"):
			remove_meta("eoa_loaded_clock")
			if TimeManager.has_method("note_overlay_clock_from_current"):
				TimeManager.note_overlay_clock_from_current()
		if TimeManager.has_method("release_overlay_clock_lock"):
			TimeManager.release_overlay_clock_lock()
	_clock_lock_held = false


func _exit_tree() -> void:
	_release_clock_lock()


func _pause_game(pause: bool) -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	if pause:
		if not has_meta("was_paused_before_menu"):
			set_meta("was_paused_before_menu", TimeManager.is_paused())
		if TimeManager.has_method("acquire_overlay_clock_lock") and not _clock_lock_held:
			TimeManager.acquire_overlay_clock_lock()
			_clock_lock_held = true
		else:
			TimeManager.set_paused(true)
		if Engine.time_scale < 0.001:
			Engine.time_scale = 1.0
	else:
		var top_bar: Node = TopInfoBar.find_in_tree(get_tree()) if get_tree() != null else null
		if has_meta("eoa_loaded_clock"):
			remove_meta("eoa_loaded_clock")
			if has_meta("was_paused_before_menu"):
				remove_meta("was_paused_before_menu")
			if _clock_lock_held and TimeManager.has_method("note_overlay_clock_from_current"):
				TimeManager.note_overlay_clock_from_current()
			if _clock_lock_held and TimeManager.has_method("release_overlay_clock_lock"):
				TimeManager.release_overlay_clock_lock()
				_clock_lock_held = false
			Engine.time_scale = 1.0
			if top_bar != null and top_bar.has_method("resync_speed_from_time_manager"):
				top_bar.call("resync_speed_from_time_manager")
			return
		if _clock_lock_held and TimeManager.has_method("release_overlay_clock_lock"):
			TimeManager.release_overlay_clock_lock()
			_clock_lock_held = false
		else:
			var was_paused: bool = get_meta("was_paused_before_menu", true)
			TimeManager.set_paused(was_paused)
		Engine.time_scale = 1.0
		if has_meta("was_paused_before_menu"):
			remove_meta("was_paused_before_menu")
		if top_bar != null:
			if top_bar.has_method("resync_speed_from_time_manager"):
				top_bar.call("resync_speed_from_time_manager")
			elif top_bar.has_method("_sync_pause_from_time_manager"):
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
