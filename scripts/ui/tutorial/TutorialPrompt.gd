# scripts/ui/tutorial/TutorialPrompt.gd
## First-launch "New to EOA?" modal (T02). Holds the clock while open.
class_name TutorialPrompt
extends PanelContainer

signal show_basics
signal know_game
signal dont_ask_changed(on: bool)

const _CloseReleaseSwallow := preload("res://scripts/ui/CloseReleaseSwallow.gd")

var _dont: CheckBox
var _clock_lock_held: bool = false
var _subtitle: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(520, 0)
	_build()
	set_process_input(true)
	visible = false


func present(nation_line: String) -> void:
	if _subtitle != null:
		_subtitle.text = nation_line
	visible = true
	reset_size()
	_acquire_clock_lock()


func dismiss() -> void:
	visible = false
	_release_clock_lock()


func dont_ask() -> bool:
	return _dont != null and _dont.button_pressed


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_wheel(event):
		accept_event()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func _build() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = RetrowaveTheme.BG_PANEL
	sb.border_color = RetrowaveTheme.CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	var title := Label.new()
	title.name = "PromptTitle"
	title.text = "New to Epochs of Ascendancy?"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", RetrowaveTheme.TEXT_PRIMARY)
	col.add_child(title)
	_subtitle = Label.new()
	_subtitle.name = "PromptSubtitle"
	_subtitle.text = "Germany · 1 January 1936"
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", RetrowaveTheme.MAGENTA)
	col.add_child(_subtitle)
	var body := Label.new()
	body.name = "PromptBody"
	body.text = "A short guide walks you through your first 20 minutes: time, map modes, the inspector, going to war, moving an army, a battle, saving, and how the game ends."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", RetrowaveTheme.TEXT_PRIMARY)
	col.add_child(body)
	var meta := Label.new()
	meta.text = "12 short steps · skip any time · the clock stays paused while you decide"
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	col.add_child(meta)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var show_btn := _make_btn("Show me the basics", true)
	show_btn.name = "BtnShowBasics"
	show_btn.pressed.connect(_on_show)
	row.add_child(show_btn)
	var know_btn := _make_btn("I know the game", false)
	know_btn.name = "BtnKnowGame"
	know_btn.pressed.connect(_on_know)
	row.add_child(know_btn)
	var extra := HBoxContainer.new()
	extra.add_theme_constant_override("separation", 12)
	col.add_child(extra)
	_dont = CheckBox.new()
	_dont.name = "DontAskAgain"
	_dont.text = "Don't ask again"
	_dont.focus_mode = Control.FOCUS_NONE
	_dont.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	_dont.toggled.connect(func(on: bool) -> void: dont_ask_changed.emit(on))
	extra.add_child(_dont)
	var hint := Label.new()
	hint.text = "Menu → Settings → First-session guide"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	extra.add_child(hint)


func _make_btn(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.custom_minimum_size = Vector2(0, 40)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.button_down.connect(func() -> void: _CloseReleaseSwallow.arm_from(self))
	if primary:
		RetrowaveTheme.style_primary_button(btn)
	else:
		RetrowaveTheme.style_secondary_button(btn)
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_wheel(event):
		_mark_handled()
		return
	if _is_enter(event):
		_on_show()
		_mark_handled()
	elif _is_escape(event):
		_on_know()
		_mark_handled()


func _is_enter(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		return true
	if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
		return true
	return false


func _is_escape(event: InputEvent) -> bool:
	if event is InputEventAction:
		var act := event as InputEventAction
		return bool(act.pressed) and str(act.action) == "ui_cancel"
	if event is InputEventKey:
		var key := event as InputEventKey
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


func _is_wheel(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	return mb.pressed and (
		mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
	)


func _mark_handled() -> void:
	accept_event()
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _on_show() -> void:
	show_basics.emit()


func _on_know() -> void:
	know_game.emit()


func _acquire_clock_lock() -> void:
	if _clock_lock_held:
		return
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("acquire_overlay_clock_lock"):
		TimeManager.acquire_overlay_clock_lock()
		_clock_lock_held = true


func _release_clock_lock() -> void:
	if not _clock_lock_held:
		return
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("release_overlay_clock_lock"):
		TimeManager.release_overlay_clock_lock()
	_clock_lock_held = false


func _exit_tree() -> void:
	_release_clock_lock()
