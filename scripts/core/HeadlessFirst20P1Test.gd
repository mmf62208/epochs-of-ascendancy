extends SceneTree

## FIRST20-P1 windowed layout checks (F1–F4). F1: neon frame keeps label glyphs
## at least 40 px inside the outer edge, and pause sliders stay inside the frame.
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     --resolution 1280x800 -s res://scripts/core/HeadlessFirst20P1Test.gd

const _LoadingScreen := preload("res://scripts/ui/LoadingScreen.gd")
const SIZES: Array[Vector2i] = [Vector2i(1280, 800), Vector2i(1280, 720)]
const INSET := 40.0
const TEXTURE_MARGIN := 48.0
const SLIDER_CLEARANCE := 12.0
const MUST_SEE: PackedStringArray = [
	"The world", "SCENARIO DATE", "LOAD GAME", "GAME", "SETTINGS", "UI",
]

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for sz in SIZES:
		await _check_frame(sz)
	await _check_epoch_title(Vector2i(1024, 720))
	await _check_epoch_title(Vector2i(1280, 800))
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("RESULT=PASS")
		quit(0)
	else:
		print("RESULT=FAIL failures=%d" % _failures)
		quit(1)


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL %s" % msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _set_size(sz: Vector2i) -> void:
	DisplayServer.window_set_size(sz)
	if root != null:
		root.size = sz
	await _frames(2)


func _check_frame(sz: Vector2i) -> void:
	await _set_size(sz)
	# Load after autoloads exist. A parse-time LivingTitleBoot reference compiles
	# before SaveLoadManager is registered and the title checks never run.
	var boot_script: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if boot_script == null:
		_fail("%s title script missing" % str(sz))
		return
	var title := boot_script.new() as Node
	if title == null:
		_fail("%s title did not construct" % str(sz))
		return
	title.name = "F1Title"
	root.add_child(title)
	await _frames(3)
	var panel := title.find_child("LivingTitlePanel", true, false) as PanelContainer
	if panel == null:
		_fail("%s title panel missing" % str(sz))
	else:
		_check_menu_style(panel, "title %s" % str(sz))
		if not is_equal_approx(panel.offset_left, 28.0) or not is_equal_approx(panel.offset_top, -340.0):
			_fail("%s title offsets L/T %s %s" % [str(sz), panel.offset_left, panel.offset_top])
		if not is_equal_approx(panel.offset_right, 508.0) or not is_equal_approx(panel.offset_bottom, 340.0):
			_fail("%s title offsets R/B %s %s" % [str(sz), panel.offset_right, panel.offset_bottom])
		if panel.size.x < 479.0 or panel.size.y < 679.0:
			_fail("%s title size %s" % [str(sz), panel.size])
		var margin := panel.get_child(0) as MarginContainer
		if margin == null:
			_fail("%s title margin missing" % str(sz))
		else:
			for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
				if int(margin.get_theme_constant(edge)) != 0:
					_fail("%s title %s=%s" % [str(sz), edge, margin.get_theme_constant(edge)])
		var sub := _label_starting(panel, "The world")
		if sub == null:
			_fail("%s subtitle missing" % str(sz))
		elif sub.custom_minimum_size.x < 399.0:
			_fail("%s body wrap width %s" % [str(sz), sub.custom_minimum_size.x])
		_check_label_glyphs(panel, panel.get_global_rect(), "title %s" % str(sz))
		_check_phrase(panel, panel.get_global_rect(), "The world", "title %s" % str(sz), true)
		_check_phrase(panel, panel.get_global_rect(), "SCENARIO DATE", "title %s" % str(sz), true)
		_check_phrase(panel, panel.get_global_rect(), "LOAD GAME", "title %s" % str(sz), true)
		_check_header_pad(panel, "SCENARIO DATE", "title %s" % str(sz))
	title.queue_free()
	await _frames(1)

	var packed := load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		_fail("MainMenu scene missing")
		return
	var menu := packed.instantiate()
	menu.name = "F1Pause"
	root.add_child(menu)
	await _frames(3)
	var pause := menu.find_child("MenuPanel", true, false) as PanelContainer
	if pause == null:
		_fail("%s pause panel missing" % str(sz))
	else:
		_check_menu_style(pause, "pause %s" % str(sz))
		var frame := pause.get_global_rect()
		_check_label_glyphs(pause, frame, "pause %s" % str(sz))
		_check_phrase(pause, frame, "GAME", "pause %s" % str(sz), true)
		_check_phrase(pause, frame, "SETTINGS", "pause %s" % str(sz), true)
		_check_phrase(pause, frame, "UI", "pause %s" % str(sz), true)
		_check_header_pad(pause, "SETTINGS", "pause %s" % str(sz))
		_check_settings_pin(menu, frame, "pause %s" % str(sz))
	menu.queue_free()
	await _frames(1)

	var loading := _LoadingScreen.new()
	loading.name = "F1Loading"
	root.add_child(loading)
	loading.show_loading("cycle", "Loading the epoch")
	loading.update_progress(0.30, "Agents")
	await _frames(3)
	var load_frame := Rect2(Vector2.ZERO, Vector2(sz))
	_check_label_glyphs(loading, load_frame, "loading %s" % str(sz))
	var chapter := loading.title_label
	if chapter == null or chapter.text != "THE AGENT'S EPOCH":
		_fail("%s loading title %s" % [str(sz), chapter.text if chapter != null else "null"])
	else:
		_check_epoch_label(chapter, load_frame, "loading %s" % str(sz))
	loading.queue_free()
	await _frames(1)


func _check_epoch_title(sz: Vector2i) -> void:
	await _set_size(sz)
	var loading := _LoadingScreen.new()
	loading.name = "F1Epoch"
	root.add_child(loading)
	loading.show_loading("cycle", "Loading")
	loading.update_progress(0.30, "Agents")
	await _frames(3)
	var chapter := loading.title_label
	var frame := Rect2(Vector2.ZERO, Vector2(sz))
	if chapter == null:
		_fail("%s epoch title missing" % str(sz))
	else:
		_check_epoch_label(chapter, frame, "epoch %s" % str(sz))
	loading.queue_free()
	await _frames(1)


func _check_epoch_label(chapter: Label, frame: Rect2, where: String) -> void:
	if chapter.text != "THE AGENT'S EPOCH":
		_fail("%s epoch text %s" % [where, chapter.text])
		return
	if chapter.clip_text:
		_fail("%s epoch clip_text" % where)
	if chapter.autowrap_mode != TextServer.AUTOWRAP_WORD_SMART:
		_fail("%s epoch autowrap %s" % [where, chapter.autowrap_mode])
	var fs := int(chapter.get_theme_font_size("font_size"))
	if fs > 20 or fs <= 0:
		_fail("%s epoch font %d" % [where, fs])
	var font := chapter.get_theme_font("font")
	if font == null:
		_fail("%s epoch font missing" % where)
		return
	var text_w := font.get_string_size(chapter.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var max_w := frame.size.x - 80.0
	if text_w > max_w + 0.5:
		_fail("%s epoch width %.1f > %.1f" % [where, text_w, max_w])
	if chapter.size.x > max_w + 1.0:
		_fail("%s epoch control width %.1f > %.1f" % [where, chapter.size.x, max_w])
	_glyph_block(chapter, frame, where, true)


func _check_menu_style(panel: PanelContainer, where: String) -> void:
	var box := panel.get_theme_stylebox("panel")
	if box == null:
		_fail("%s style missing" % where)
		return
	if box is StyleBoxTexture:
		var tex := box as StyleBoxTexture
		if not is_equal_approx(tex.texture_margin_left, TEXTURE_MARGIN):
			_fail("%s texture_margin %.1f" % [where, tex.texture_margin_left])
		if not is_equal_approx(tex.content_margin_left, 40.0) or not is_equal_approx(tex.content_margin_right, 40.0):
			_fail("%s content L/R %.1f %.1f" % [where, tex.content_margin_left, tex.content_margin_right])
		if not is_equal_approx(tex.content_margin_top, 44.0) or not is_equal_approx(tex.content_margin_bottom, 40.0):
			_fail("%s content T/B %.1f %.1f" % [where, tex.content_margin_top, tex.content_margin_bottom])
	else:
		_fail("%s panel style is %s" % [where, box.get_class()])


func _check_settings_pin(menu: Node, frame: Rect2, where: String) -> void:
	var scroll := menu.find_child("GameActionsScroll", true, false) as Control
	var pin := menu.find_child("SettingsPin", true, false) as VBoxContainer
	var sep := menu.find_child("SettingsSeparator", true, false) as HSeparator
	if scroll == null or pin == null or sep == null:
		_fail("%s settings pin missing" % where)
		return
	if scroll.get_parent() != pin.get_parent():
		_fail("%s scroll and pin are not siblings" % where)
	if scroll.get_index() > pin.get_index():
		_fail("%s settings are above the actions scroll" % where)
	if int(pin.get_theme_constant("separation")) != 8:
		_fail("%s pin gap %s" % [where, pin.get_theme_constant("separation")])
	var line := sep.get_theme_stylebox("separator") as StyleBoxLine
	if line == null or not is_equal_approx(line.thickness, 1.0):
		_fail("%s separator is not 1 px" % where)
	elif not is_equal_approx(line.color.a, 0.35) or line.color.r < 0.1:
		_fail("%s separator color %s" % [where, line.color])
	var mute := menu.find_child("MuteAudio", true, false) as CheckButton
	if mute == null or mute.get_parent() == null or str(mute.get_parent().name) != "MuteRow":
		_fail("%s Mute is not on its own row" % where)
	var master := menu.find_child("MasterVolume", true, false) as HSlider
	if master != null and mute != null and master.get_parent() == mute.get_parent():
		_fail("%s Mute shares the Master row" % where)
	var bottom := 0.0
	var saw_slider := false
	for node_name in ["MasterVolume", "UiVolume", "SfxVolume", "MusicVolume"]:
		var slider := menu.find_child(node_name, true, false) as HSlider
		if slider == null:
			_fail("%s slider %s missing" % [where, node_name])
			continue
		saw_slider = true
		var sr := slider.get_global_rect()
		if not frame.encloses(sr):
			_fail("%s slider %s outside frame %s vs %s" % [where, node_name, sr, frame])
		bottom = maxf(bottom, sr.end.y)
		var val := menu.find_child("%sValue" % node_name, true, false) as Label
		if val == null:
			_fail("%s value label %s missing" % [where, node_name])
			continue
		if val.custom_minimum_size.x < 55.0:
			_fail("%s value width %s" % [where, val.custom_minimum_size.x])
		if int(val.get_theme_font_size("font_size")) != 13:
			_fail("%s value font %s" % [where, val.get_theme_font_size("font_size")])
		var col: Color = val.get_theme_color("font_color")
		if col != RetrowaveTheme.TEXT_DIM:
			_fail("%s value color %s" % [where, col])
		var lab := slider.get_parent().get_child(0) as Label
		if lab == null or lab.custom_minimum_size.x < 63.0:
			_fail("%s row label width" % where)
		if (slider.size_flags_horizontal & Control.SIZE_EXPAND) == 0:
			_fail("%s slider %s does not expand" % [where, node_name])
	if mute != null and not frame.encloses(mute.get_global_rect()):
		_fail("%s Mute outside frame %s" % [where, mute.get_global_rect()])
	var inner_limit := frame.end.y - TEXTURE_MARGIN - SLIDER_CLEARANCE
	if saw_slider and bottom > inner_limit + 0.05:
		_fail("%s bottom slider %.1f is under inner edge+12 (limit %.1f)" % [where, bottom, inner_limit])


func _check_header_pad(root_node: Node, text: String, where: String) -> void:
	var lab := _label_exact(root_node, text)
	if lab == null:
		return
	if int(lab.get_theme_font_size("font_size")) != 13:
		_fail("%s %s font %s" % [where, text, lab.get_theme_font_size("font_size")])
	var col: Color = lab.get_theme_color("font_color")
	if col != RetrowaveTheme.CYAN:
		_fail("%s %s color %s" % [where, text, col])
	if lab.vertical_alignment != VERTICAL_ALIGNMENT_BOTTOM:
		_fail("%s %s valign" % [where, text])


func _check_phrase(root_node: Node, frame: Rect2, text: String, where: String, require_full: bool = false) -> void:
	var lab := _label_exact(root_node, text) if text != "The world" else _label_starting(root_node, text)
	if lab == null:
		_fail("%s missing %s" % [where, text])
		return
	_glyph_block(lab, frame, "%s [%s]" % [where, text], require_full)


func _check_label_glyphs(root_node: Node, frame: Rect2, where: String) -> void:
	var labels: Array = root_node.find_children("*", "Label", true, false)
	for node in labels:
		var lab := node as Label
		if lab == null or not lab.visible or lab.text.strip_edges().is_empty():
			continue
		_glyph_block(lab, frame, "%s label '%s'" % [where, lab.text.substr(0, 24)])


func _glyph_block(lab: Label, frame: Rect2, where: String, require_full: bool = false) -> void:
	var worst := 100000.0
	var counted := 0
	var xf := lab.get_global_transform()
	var clip := _clip_rect(lab, frame)
	for i in lab.text.length():
		var local := lab.get_character_bounds(i)
		if local.size.x <= 0.01 or local.size.y <= 0.01:
			continue
		var gp := xf * local.position
		var gr := Rect2(gp, local.size * xf.get_scale())
		if not clip.intersects(gr):
			if require_full:
				_fail("%s glyph %d off-screen %s" % [where, i, gr])
				return
			continue
		var visible := clip.intersection(gr)
		if require_full and not _contains_rect(clip, gr):
			_fail("%s glyph %d clipped %s clip %s" % [where, i, gr, clip])
			return
		counted += 1
		worst = minf(worst, _inset(visible, frame))
	if counted == 0:
		if not require_full and not clip.intersects(lab.get_global_rect()):
			return
		var fallback := _fallback_glyph_rect(lab)
		if fallback.size == Vector2.ZERO:
			_fail("%s no glyph bounds" % where)
			return
		if not clip.intersects(fallback):
			if require_full:
				_fail("%s fallback off-screen %s" % [where, fallback])
			return
		var visible_fb := clip.intersection(fallback)
		if require_full and not _contains_rect(clip, fallback):
			_fail("%s fallback clipped %s" % [where, fallback])
			return
		worst = _inset(visible_fb, frame)
		counted = 1
	if counted > 0 and worst < INSET - 0.05:
		_fail("%s glyph inset %.2f < 40 frame %s" % [where, worst, frame])


func _fallback_glyph_rect(lab: Label) -> Rect2:
	var font := lab.get_theme_font("font")
	if font == null:
		return Rect2()
	var fs := int(lab.get_theme_font_size("font_size"))
	var sz := font.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var origin := lab.get_global_rect().position
	if lab.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		origin.x += maxf(0.0, (lab.size.x - sz.x) * 0.5)
	return Rect2(origin, sz)


func _clip_rect(lab: Control, frame: Rect2) -> Rect2:
	var clip := frame
	var n: Node = lab
	while n != null:
		if n is Control and (n as Control).clip_contents:
			clip = clip.intersection((n as Control).get_global_rect())
		n = n.get_parent()
	return clip


func _inset(gr: Rect2, frame: Rect2) -> float:
	return minf(
		minf(gr.position.x - frame.position.x, frame.end.x - gr.end.x),
		minf(gr.position.y - frame.position.y, frame.end.y - gr.end.y)
	)


func _contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return outer.encloses(inner.grow(-0.05)) if inner.size.x > 0.2 else outer.encloses(inner)


func _label_exact(root_node: Node, text: String) -> Label:
	for node in root_node.find_children("*", "Label", true, false):
		var lab := node as Label
		if lab != null and lab.visible and lab.text == text:
			return lab
	return null


func _label_starting(root_node: Node, text: String) -> Label:
	for node in root_node.find_children("*", "Label", true, false):
		var lab := node as Label
		if lab != null and lab.visible and lab.text.begins_with(text):
			return lab
	return null
