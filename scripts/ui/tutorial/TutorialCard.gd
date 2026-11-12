# scripts/ui/tutorial/TutorialCard.gd
## First-session guide card (T01). Never takes keyboard focus. Clicks do not fall through.
class_name TutorialCard
extends PanelContainer

signal next_pressed
signal back_pressed
signal skip_step_pressed
signal skip_tutorial_pressed
signal skip_off_pressed
signal skip_keep_pressed
signal got_it_pressed
signal close_pressed
signal dont_show_again_toggled(on: bool)
signal reflow_requested

const CARD_WIDTH := 380.0
const CARD_WIDTH_WAR := 400.0
const CARD_WIDTH_NARROW := 340.0
const NARROW_VP := 1100.0
const BODY_WRAP := 348.0
const FONT_PATH := "res://assets/fonts/Cinzel-VariableFont_wght.ttf"

const _CloseReleaseSwallow := preload("res://scripts/ui/CloseReleaseSwallow.gd")

var _title: Label
var _body: Label
var _status: Label
var _category: Label
var _step_chip: Label
var _dots: HBoxContainer
var _keys_row: HBoxContainer
var _progress_bar: ProgressBar
var _progress_label: Label
var _progress_wrap: VBoxContainer
var _btn_next: Button
var _btn_back: Button
var _btn_skip_step: Button
var _btn_got_it: Button
var _btn_skip_tut: Button
var _btn_close: Button
var _btn_turn_off: Button
var _btn_keep: Button
var _dont: CheckBox
var _confirm_wrap: HBoxContainer
var _footer_right: HBoxContainer
var _cinzel: FontFile
var _current: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_load_font()
	_build()
	visible = false
	set_process(true)


func present(model: Dictionary) -> void:
	_current = model.duplicate(true)
	var accent := _accent_color(str(model.get("accent", "cyan")))
	_apply_frame(accent)
	var n := int(model.get("n", 0))
	_step_chip.text = "STEP %d / %d" % [n, TutorialGuideDomain.STEP_COUNT]
	_category.text = str(model.get("category", "")).to_upper()
	_title.text = str(model.get("title", ""))
	_body.text = str(model.get("body", ""))
	_status.text = str(model.get("status_text", ""))
	_status.visible = not _status.text.is_empty() and str(model.get("state", "")) != "done"
	var status_col := accent
	var status_hex := str(model.get("status_color", "")).strip_edges()
	if not status_hex.is_empty():
		status_col = Color(status_hex)
	_status.add_theme_color_override("font_color", status_col)
	_apply_status_weight(bool(model.get("status_bold", false)))
	_fill_dots(n, accent)
	_fill_keys(model.get("keys", []), accent)
	var prog: Variant = model.get("progress", {})
	if prog is Dictionary and not (prog as Dictionary).is_empty():
		_progress_wrap.visible = true
		var cur := float((prog as Dictionary).get("current", 0))
		var tot := maxf(1.0, float((prog as Dictionary).get("total", 14)))
		_progress_bar.max_value = tot
		_progress_bar.value = cur
		_progress_label.text = str((prog as Dictionary).get("label", ""))
	else:
		_progress_wrap.visible = false
	var kind := str(model.get("kind", "action"))
	var state := str(model.get("state", "active"))
	var confirm := bool(model.get("confirm_skip", false))
	_btn_next.visible = kind == "info" and not confirm and state != "done"
	_btn_back.visible = kind == "info" and n > 1 and not confirm and state != "done"
	_btn_skip_step.visible = bool(model.get("show_skip_step", false)) and not confirm and state != "done"
	_btn_got_it.visible = kind == "final" and not confirm
	_dont.visible = bool(model.get("show_dont_show_again", false)) and not confirm
	_confirm_wrap.visible = confirm
	_btn_skip_tut.visible = not confirm
	_btn_turn_off.visible = confirm
	_btn_keep.visible = confirm
	if confirm:
		_title.text = "Turn the guide off?"
		_body.text = "You can turn it back on in Settings."
		_status.visible = false
		_keys_row.visible = false
		_progress_wrap.visible = false
	visible = bool(model.get("visible", true))
	_fit_width(accent)
	_hug_content()
	call_deferred("_reflow")


func set_dont_show_again(on: bool) -> void:
	if _dont != null:
		_dont.set_pressed_no_signal(on)


func _load_font() -> void:
	if not FileAccess.file_exists(FONT_PATH):
		return
	var font := FontFile.new()
	var err := font.load_dynamic_font(FONT_PATH)
	if err == OK:
		_cinzel = font
		font.fixed_size = 17


func _build() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)
	_step_chip = Label.new()
	_step_chip.name = "StepChip"
	_step_chip.focus_mode = Control.FOCUS_NONE
	_step_chip.add_theme_font_size_override("font_size", 11)
	_step_chip.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	header.add_child(_step_chip)
	_category = Label.new()
	_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category.add_theme_font_size_override("font_size", 11)
	_category.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	header.add_child(_category)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 3)
	header.add_child(_dots)
	_btn_close = _make_btn("×", "_on_close")
	_btn_close.name = "BtnClose"
	_btn_close.custom_minimum_size = Vector2(22, 22)
	header.add_child(_btn_close)

	_title = Label.new()
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", RetrowaveTheme.TEXT_PRIMARY)
	if _cinzel != null:
		_title.add_theme_font_override("font", _cinzel)
	col.add_child(_title)

	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(BODY_WRAP, 0)
	_body.add_theme_font_size_override("font_size", 14)
	_body.add_theme_color_override("font_color", RetrowaveTheme.TEXT_PRIMARY)
	_body.max_lines_visible = 4
	col.add_child(_body)

	_keys_row = HBoxContainer.new()
	_keys_row.name = "KeysRow"
	_keys_row.add_theme_constant_override("separation", 6)
	col.add_child(_keys_row)

	_progress_wrap = VBoxContainer.new()
	_progress_wrap.visible = false
	col.add_child(_progress_wrap)
	var prog_row := HBoxContainer.new()
	_progress_wrap.add_child(prog_row)
	_progress_bar = ProgressBar.new()
	_progress_bar.name = "WaitProgress"
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.custom_minimum_size = Vector2(0, 8)
	_progress_bar.show_percentage = false
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prog_row.add_child(_progress_bar)
	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 11)
	_progress_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	prog_row.add_child(_progress_label)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	col.add_child(_status)

	_dont = CheckBox.new()
	_dont.name = "DontShowAgain"
	_dont.text = "Don't show the guide again"
	_dont.focus_mode = Control.FOCUS_NONE
	_dont.mouse_filter = Control.MOUSE_FILTER_STOP
	_dont.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	_dont.toggled.connect(_on_dont)
	col.add_child(_dont)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	col.add_child(footer)
	_btn_skip_tut = _make_btn("Skip tutorial", "_on_skip_tutorial")
	_btn_skip_tut.name = "BtnSkipTutorial"
	_btn_skip_tut.flat = true
	_btn_skip_tut.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	footer.add_child(_btn_skip_tut)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)
	_footer_right = HBoxContainer.new()
	_footer_right.add_theme_constant_override("separation", 6)
	footer.add_child(_footer_right)
	_btn_back = _make_btn("Back", "_on_back")
	_btn_back.name = "BtnBack"
	_footer_right.add_child(_btn_back)
	_btn_next = _make_btn("Next", "_on_next")
	_btn_next.name = "BtnNext"
	RetrowaveTheme.style_primary_button(_btn_next)
	_style_focusless(_btn_next)
	_footer_right.add_child(_btn_next)
	_btn_skip_step = _make_btn("Skip step", "_on_skip_step")
	_btn_skip_step.name = "BtnSkipStep"
	_footer_right.add_child(_btn_skip_step)
	_btn_got_it = _make_btn("Got it", "_on_got_it")
	_btn_got_it.name = "BtnGotIt"
	RetrowaveTheme.style_primary_button(_btn_got_it)
	_style_focusless(_btn_got_it)
	_footer_right.add_child(_btn_got_it)

	_confirm_wrap = HBoxContainer.new()
	_confirm_wrap.visible = false
	_confirm_wrap.add_theme_constant_override("separation", 6)
	col.add_child(_confirm_wrap)
	_btn_turn_off = _make_btn("Turn off", "_on_turn_off")
	_btn_turn_off.name = "BtnTurnOff"
	_confirm_wrap.add_child(_btn_turn_off)
	_btn_keep = _make_btn("Keep going", "_on_keep")
	_btn_keep.name = "BtnKeepGoing"
	RetrowaveTheme.style_primary_button(_btn_keep)
	_style_focusless(_btn_keep)
	_confirm_wrap.add_child(_btn_keep)


func _make_btn(text: String, handler: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.custom_minimum_size = Vector2(0, 32)
	btn.button_down.connect(_arm_swallow)
	match handler:
		"_on_next":
			btn.pressed.connect(_on_next)
		"_on_back":
			btn.pressed.connect(_on_back)
		"_on_skip_step":
			btn.pressed.connect(_on_skip_step)
		"_on_skip_tutorial":
			btn.pressed.connect(_on_skip_tutorial)
		"_on_got_it":
			btn.pressed.connect(_on_got_it)
		"_on_close":
			btn.pressed.connect(_on_close)
		"_on_turn_off":
			btn.pressed.connect(_on_turn_off)
		"_on_keep":
			btn.pressed.connect(_on_keep)
		_:
			pass
	RetrowaveTheme.style_secondary_button(btn)
	_style_focusless(btn)
	return btn


func _style_focusless(btn: Button) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _arm_swallow() -> void:
	_CloseReleaseSwallow.arm_from(self)


func _fill_dots(n: int, accent: Color) -> void:
	for c in _dots.get_children():
		c.queue_free()
	for i in TutorialGuideDomain.STEP_COUNT:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(6, 6)
		d.size = Vector2(6, 6)
		d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i < n:
			d.color = accent
		else:
			d.color = Color(accent, 0.28)
		_dots.add_child(d)


func _fill_keys(keys: Variant, accent: Color) -> void:
	for c in _keys_row.get_children():
		c.queue_free()
	if not (keys is Array) or (keys as Array).is_empty():
		_keys_row.visible = false
		return
	_keys_row.visible = true
	var war := accent.is_equal_approx(RetrowaveTheme.MAGENTA)
	for k in keys:
		var chip := Label.new()
		chip.text = str(k)
		chip.add_theme_font_size_override("font_size", 12)
		chip.add_theme_color_override("font_color", RetrowaveTheme.MAGENTA if war else RetrowaveTheme.CYAN)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#0f1528")
		sb.border_color = RetrowaveTheme.MAGENTA if war else RetrowaveTheme.CYAN
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		chip.add_theme_stylebox_override("normal", sb)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_keys_row.add_child(chip)


func _apply_frame(accent: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = RetrowaveTheme.BG_PANEL
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.border_width_top = 6
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	add_theme_stylebox_override("panel", sb)
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.set_corner_radius_all(3)
	if _progress_bar != null:
		_progress_bar.add_theme_stylebox_override("fill", fill)


func _process(_delta: float) -> void:
	# present() hugs immediately, but a Label's wrapped minimum arrives a frame later.
	# Keep shrinking until the laid-out minimum is the card height.
	var before := size
	_hug_content()
	if not size.is_equal_approx(before):
		reflow_requested.emit()


func _hug_content() -> void:
	var w := custom_minimum_size.x
	if w < 8.0:
		w = CARD_WIDTH
	update_minimum_size()
	# Drop the stale height first so Godot recomputes the wrapped minimum.
	size = Vector2(w, 0)
	reset_size()
	var fitted := get_combined_minimum_size()
	var h := fitted.y
	var limit := _height_limit()
	if h > limit - 1.0:
		h = maxf(1.0, limit - 1.0)
	size = Vector2(maxf(w, fitted.x), h)


func _height_limit() -> float:
	# GuideHost is the full-screen parent, so 60% of the host is 60% of the viewport.
	var parent := get_parent() as Control
	var h := 0.0
	if parent != null:
		h = parent.size.y
	if h < 32.0:
		var vp := get_viewport()
		if vp != null:
			h = vp.get_visible_rect().size.y
	if h < 32.0:
		h = 800.0
	return h * 0.6


func _reflow() -> void:
	_hug_content()
	reflow_requested.emit()


func _apply_status_weight(bold: bool) -> void:
	if _status == null:
		return
	if not bold:
		_status.remove_theme_font_override("font")
		return
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_opentype = {"wght": 700}
	_status.add_theme_font_override("font", fv)


func _fit_width(_accent: Color) -> void:
	var vp := get_viewport()
	var w := CARD_WIDTH
	if vp != null and vp.get_visible_rect().size.x < NARROW_VP:
		w = CARD_WIDTH_NARROW
	elif str(_current.get("accent", "")) == "magenta":
		w = CARD_WIDTH_WAR
	custom_minimum_size.x = w
	_body.custom_minimum_size.x = maxf(200.0, w - 32.0)


func _accent_color(name: String) -> Color:
	match name:
		"magenta":
			return RetrowaveTheme.MAGENTA
		"success":
			return RetrowaveTheme.SUCCESS
		_:
			return RetrowaveTheme.CYAN


func _on_next() -> void:
	next_pressed.emit()


func _on_back() -> void:
	back_pressed.emit()


func _on_skip_step() -> void:
	skip_step_pressed.emit()


func _on_skip_tutorial() -> void:
	skip_tutorial_pressed.emit()


func _on_got_it() -> void:
	got_it_pressed.emit()


func _on_close() -> void:
	close_pressed.emit()


func _on_turn_off() -> void:
	skip_off_pressed.emit()


func _on_keep() -> void:
	skip_keep_pressed.emit()


func _on_dont(on: bool) -> void:
	dont_show_again_toggled.emit(on)
