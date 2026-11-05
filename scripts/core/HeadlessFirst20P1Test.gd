extends SceneTree

## FIRST20-P1 windowed layout checks (F1–F4). F1: neon frame keeps label glyphs
## at least 40 px inside the outer edge, and pause sliders stay inside the frame.
## F4: a 1936 diplomacy window has no placeholder copy, and one Esc closes only
## the front play window. The next Esc opens pause.
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
var _f2_done := false
var _f3_done := false
var _f4_done := false
var _f4_map: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for sz in SIZES:
		await _check_frame(sz)
	await _check_epoch_title(Vector2i(1024, 720))
	await _check_epoch_title(Vector2i(1280, 800))
	await _check_f2()
	await _check_f3()
	await _check_f4()
	_finish()


func _finish() -> void:
	if not _f2_done:
		_fail("F2 did not finish")
	if not _f3_done:
		_fail("F3 did not finish")
	if not _f4_done:
		_fail("F4 did not finish")
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


func _check_f2() -> void:
	# Runtime load: a parse-time PlayNextHook reference compiles before autoloads exist.
	var hook: GDScript = load("res://scripts/ui/PlayNextHook.gd") as GDScript
	var fmt: GDScript = load("res://scripts/map/MapPolishFormatters.gd") as GDScript
	if hook == null or fmt == null:
		_fail("F2 scripts missing")
		return
	hook.call("reset_goal_lock_for_test")
	var fra := _goal_rec("FRA", "France", 710739, 0.42)
	var first: Dictionary = hook.call("stick_chip_goal", fra, 0)
	if bool(first.get("changed", false)) or str((first.get("rec", {}) as Dictionary).get("target_tag", "")) != "FRA":
		_fail("F2 lock did not seed France")
		return
	var pol := _goal_rec("POL", "Poland", 710100, 1.0)
	var early: Dictionary = hook.call("stick_chip_goal", pol, 29)
	if bool(early.get("changed", false)) or str((early.get("rec", {}) as Dictionary).get("target_tag", "")) != "FRA":
		_fail("F2 target moved before 30 days: %s" % str(early))
		return
	var later: Dictionary = hook.call("stick_chip_goal", pol, 30)
	if not bool(later.get("changed", false)):
		_fail("F2 stronger goal did not switch at day 30")
		return
	var toast := "Goal changed: %s" % str(later.get("reason", ""))
	if not toast.begins_with("Goal changed:") or str(later.get("reason", "")).is_empty():
		_fail("F2 missing change reason")
		return
	hook.call("reset_goal_lock_for_test")
	hook.call("stick_chip_goal", _goal_rec("FRA", "France", 0, 0.42), 0)
	var invalid: Dictionary = hook.call("stick_chip_goal", pol, 1)
	if not bool(invalid.get("changed", false)):
		_fail("F2 invalid goal did not release the lock")
		return
	var jargon: Dictionary = fmt.call("execute_war_goal_step", "execute", 1)
	var queue_label := ""
	var queue: Array = jargon.get("apply_queue", [])
	if not queue.is_empty() and queue[0] is Dictionary:
		queue_label = str((queue[0] as Dictionary).get("label", ""))
	var visible := "%s\n%s\n%s" % [jargon.get("summary", ""), jargon.get("plain", ""), queue_label]
	if hook.call("player_may_show_war_goal_jargon") == true:
		_fail("F2 jargon predicate was true without a visible debug overlay")
		return
	for banned in ["Execute war-goal", "leaf", "score"]:
		if banned in visible:
			_fail("F2 release text contains %s: %s" % [banned, visible])
			return
	var why := str(hook.call("goal_why_line", "FRA", "France"))
	if not why.begins_with("Why:") or "Diplomacy" not in why or "Execute war-goal" in why or "leaf" in why:
		_fail("F2 why line %s" % why)
		return
	var tip: Dictionary = hook.call("goal_tooltip_copy", "France")
	if str(tip.get("title", "")) != "Justify war goal":
		_fail("F2 tooltip title %s" % str(tip.get("title", "")))
		return
	if not str(tip.get("click", "")).begins_with("Click · open Diplomacy on France"):
		_fail("F2 click line %s" % str(tip.get("click", "")))
		return
	await _check_f2_chip()


func _goal_rec(tag: String, name: String, pid: int, score: float) -> Dictionary:
	return {
		"ok": true,
		"action": "justify",
		"source": "war_goal",
		"label": "Justify war on %s" % name,
		"target_tag": tag,
		"goal_name": name,
		"to_id": pid,
		"goal_score": score,
	}


func _check_f2_chip() -> void:
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		_fail("F2 MapRenderer missing")
		return
	var mr := scr.new() as Node
	if mr == null:
		_fail("F2 MapRenderer did not construct")
		return
	mr.name = "F2Map"
	var ui := CanvasLayer.new()
	ui.name = "UI"
	mr.add_child(ui)
	root.add_child(mr)
	var boot_script: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if boot_script == null:
		_fail("F2 title script missing")
		mr.queue_free()
		return
	var boot := boot_script.new() as Node
	boot.name = "LivingTitleBoot"
	root.add_child(boot)
	await _frames(1)
	mr.call("_refresh_next_hook_chip")
	var chip := ui.get_node_or_null("PlayNextHookChip") as Button
	if chip == null:
		_fail("F2 chip missing")
		mr.queue_free()
		boot.queue_free()
		return
	if chip.visible:
		_fail("F2 chip visible on the title")
		mr.queue_free()
		boot.queue_free()
		return
	boot.queue_free()
	await _frames(2)
	mr.call("_refresh_next_hook_chip")
	if not chip.visible:
		_fail("F2 chip stayed hidden after the title closed")
		mr.queue_free()
		return
	var shown := {
		"source": "war_goal",
		"action": "justify",
		"target_tag": "FRA",
		"goal_name": "France",
		"to_id": 710739,
		"label": "Justify war on France",
		"goal_score": 1.0,
	}
	mr.call("_paint_goal_chip_detail", shown, true)
	if chip.custom_minimum_size.x > 336.5 or chip.custom_minimum_size.y < 43.0:
		_fail("F2 chip size %s" % chip.custom_minimum_size)
		mr.queue_free()
		return
	var why := chip.get_node_or_null("GoalWhy") as Label
	if why == null or not why.text.begins_with("Why:") or int(why.get_theme_font_size("font_size")) != 12:
		_fail("F2 why label %s" % (why.text if why != null else "missing"))
		mr.queue_free()
		return
	var title := ui.find_child("GoalTooltipTitle", true, false) as Label
	if title == null or title.text != "Justify war goal" or int(title.get_theme_font_size("font_size")) != 14:
		_fail("F2 tooltip title label")
		mr.queue_free()
		return
	if title.get_theme_color("font_color") != RetrowaveTheme.CYAN:
		_fail("F2 tooltip title color %s" % title.get_theme_color("font_color"))
		mr.queue_free()
		return
	chip.set_meta("play_next_rec", shown)
	chip.pressed.emit()
	await _frames(2)
	var dip := root.find_child("DiplomacyView", true, false)
	if dip == null:
		_fail("F2 click did not open Diplomacy")
		mr.queue_free()
		return
	var selected := str(dip.get("_selected_country"))
	if selected != "FRA":
		_fail("F2 Diplomacy selected %s" % selected)
		mr.queue_free()
		dip.queue_free()
		return
	dip.queue_free()
	mr.queue_free()
	await _frames(1)
	_f2_done = true


func _check_f3() -> void:
	await _set_size(Vector2i(1280, 800))
	var cases: Array[Dictionary] = [
		{"name": "Berlin", "id": 710300, "spine": false},
		{"name": "Köln", "id": 710417, "spine": true},
		{"name": "Hamburg", "id": 710321, "spine": false},
	]
	for item in cases:
		if not await _check_f3_case(item):
			return
	if not await _check_f3_close_click():
		return
	_f3_done = true


func _check_f3_case(item: Dictionary) -> bool:
	var built: Dictionary = _f3_build(str(item["name"]), int(item["id"]), bool(item["spine"]))
	if built.is_empty():
		_fail("F3 %s harness missing" % str(item["name"]))
		return false
	var panel: Control = built["panel"]
	var mr: Node = built["mr"]
	mr.call("_layout_info_panel_inner")
	await _frames(2)
	mr.call("_layout_info_panel_inner")
	await _frames(2)
	var ok := _f3_assert_layout(str(item["name"]), panel, mr, bool(item["spine"]))
	_f3_free(built)
	await _frames(1)
	return ok


func _f3_build(prov_name: String, pid: int, spine: bool) -> Dictionary:
	var script: GDScript = load("res://scripts/map/MapRenderer.gd") as GDScript
	if script == null:
		return {}
	var mr: Node = script.new()
	if mr == null:
		return {}
	var panel := Panel.new()
	panel.name = "InfoPanel"
	panel.visible = true
	panel.clip_contents = true
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(365, 82)
	panel.offset_left = 365.0
	panel.offset_top = 82.0
	panel.offset_right = 925.0
	panel.offset_bottom = 638.0
	panel.size = Vector2(560, 556)
	panel.custom_minimum_size = Vector2(560, 556)
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "InfoScroll"
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.name = "InfoContentMargin"
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.name = "InfoContent"
	margin.add_child(content)
	var name_l := Label.new()
	name_l.name = "LabelName"
	name_l.text = prov_name
	content.add_child(name_l)
	var badge := Label.new()
	badge.name = "ProvinceIdBadge"
	badge.text = "#%d" % pid
	panel.add_child(badge)
	var spirits := _f3_button("BtnNationalSpirits", "National Spirits", "National spirits")
	var settle_text := "🏠 Settle %s (+0.35, now 1.25)" % prov_name
	var settle := _f3_button("BtnSettleProvince", settle_text, "Settle the province")
	var deploy := _f3_button("BtnStationEngineers", "Deploy Infanterie-Division", "Deploy the division")
	var fight := _f3_button("BtnOpenFight", "Open fight", "Open a fight")
	var attack := _f3_button("BtnAttackProvince", "Attack from Brandenburg", "Attack")
	var close := _f3_button("BtnClose", "Close", "Close province inspector")
	for btn in [spirits, settle, deploy, fight, attack, close]:
		panel.add_child(btn)
	var spine_btn: Button = null
	if spine:
		spine_btn = _f3_button("BtnBuildRoadSpine", "Build Road Spine", "Build the road spine")
		spine_btn.visible = true
		panel.add_child(spine_btn)
	mr.set("info_panel", panel)
	mr.set("info_name", name_l)
	mr.set("btn_close", close)
	mr.set("btn_national_spirits", spirits)
	mr.set("_btn_settle", settle)
	mr.set("_btn_station_engineers", deploy)
	mr.set("_btn_open_fight", fight)
	mr.set("_btn_attack", attack)
	mr.set("_province_id_badge", badge)
	if spine_btn != null:
		mr.set("_btn_build_road_spine", spine_btn)
	return {"panel": panel, "mr": mr, "close": close}


func _f3_button(node_name: String, text: String, tip: String) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.tooltip_text = tip
	btn.visible = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn


func _f3_assert_layout(prov_name: String, panel: Control, mr: Node, spine: bool) -> bool:
	var header := panel.get_node_or_null("InspectorHeader") as Control
	if header == null:
		_fail("F3 %s header missing" % prov_name)
		return false
	var title := header.find_child("InspectorTitle", true, false) as Label
	var badge := header.find_child("ProvinceIdBadge", true, false) as Label
	var close := header.find_child("BtnClose", true, false) as Button
	if title == null or title.text != prov_name or int(title.get_theme_font_size("font_size")) != 18:
		_fail("F3 %s title" % prov_name)
		return false
	if title.get_theme_color("font_color") != RetrowaveTheme.CYAN:
		_fail("F3 %s title color" % prov_name)
		return false
	if badge == null or not badge.text.begins_with("#") or int(badge.get_theme_font_size("font_size")) != 12:
		_fail("F3 %s id" % prov_name)
		return false
	if badge.get_theme_color("font_color") != RetrowaveTheme.TEXT_DIM:
		_fail("F3 %s id color" % prov_name)
		return false
	if close == null or close.text != "Close":
		_fail("F3 %s close missing" % prov_name)
		return false
	if close.get_theme_color("font_color") != RetrowaveTheme.WARNING:
		_fail("F3 %s close color" % prov_name)
		return false
	if absf(close.size.x - 72.0) > 2.0 or absf(close.size.y - 28.0) > 2.0:
		_fail("F3 %s close size %s" % [prov_name, str(close.size)])
		return false
	var controls: Array[Control] = []
	for node in header.find_children("*", "Control", true, false):
		var ctrl := node as Control
		if ctrl == null or not ctrl.visible:
			continue
		if ctrl is Container or str(ctrl.name) == "InspectorHeaderSpacer":
			continue
		if ctrl.get_global_rect().size.x < 1.0 or ctrl.get_global_rect().size.y < 1.0:
			continue
		controls.append(ctrl)
	if controls.size() < 5:
		_fail("F3 %s header controls %d" % [prov_name, controls.size()])
		return false
	for i in controls.size():
		for j in range(i + 1, controls.size()):
			var a: Rect2 = (controls[i] as Control).get_global_rect()
			var b: Rect2 = (controls[j] as Control).get_global_rect()
			if a.intersects(b):
				_fail("F3 %s overlap %s %s vs %s %s" % [prov_name, str(controls[i].name), str(a), str(controls[j].name), str(b)])
				return false
	if not _f3_glyphs_clear(title, close) or not _f3_glyphs_clear(badge, close):
		_fail("F3 %s glyphs overlap close or miss the label" % prov_name)
		return false
	var settle := header.find_child("BtnSettleProvince", true, false) as Button
	if settle == null:
		_fail("F3 %s settle missing" % prov_name)
		return false
	if settle.text_overrun_behavior != TextServer.OVERRUN_TRIM_WORD_ELLIPSIS:
		_fail("F3 %s settle overrun %s" % [prov_name, str(settle.text_overrun_behavior)])
		return false
	if settle.custom_minimum_size.x > 180.01:
		_fail("F3 %s settle width %s" % [prov_name, str(settle.custom_minimum_size.x)])
		return false
	if not (settle.text in settle.tooltip_text):
		_fail("F3 %s settle tooltip missing full text" % prov_name)
		return false
	var fight := header.find_child("BtnOpenFight", true, false) as Button
	var spirits := header.find_child("BtnNationalSpirits", true, false) as Button
	if fight == null or spirits == null:
		_fail("F3 %s actions missing" % prov_name)
		return false
	var fight_border := _f3_border(fight)
	var spirit_border := _f3_border(spirits)
	if fight_border != RetrowaveTheme.CYAN:
		_fail("F3 %s primary border %s" % [prov_name, str(fight_border)])
		return false
	var dim := RetrowaveTheme.TEXT_DIM
	dim.a = 0.5
	if spirit_border != dim:
		_fail("F3 %s secondary border %s" % [prov_name, str(spirit_border)])
		return false
	var flow := header.get_node_or_null("InspectorActions") as HFlowContainer
	if flow == null:
		_fail("F3 %s flow missing" % prov_name)
		return false
	var order: PackedStringArray = PackedStringArray([
		"BtnNationalSpirits", "BtnSettleProvince", "BtnStationEngineers", "BtnOpenFight", "BtnAttackProvince",
	])
	var seen := 0
	for child in flow.get_children():
		if str(child.name) == order[seen]:
			seen += 1
			if seen >= order.size():
				break
	if seen != order.size():
		_fail("F3 %s action order" % prov_name)
		return false
	var hh := float(mr.get("_inspector_header_h"))
	var measured := header.get_combined_minimum_size().y + 8.0
	if absf(hh - measured) > 1.5 and absf(hh - (header.size.y + 8.0)) > 1.5:
		_fail("F3 %s header_h %s measured %s" % [prov_name, str(hh), str(measured)])
		return false
	var scroll := panel.get_node_or_null("InfoScroll") as Control
	if scroll == null or scroll.position.y + 0.5 < header.position.y + header.size.y:
		_fail("F3 %s scroll overlaps header" % prov_name)
		return false
	if spine:
		var spine_btn := panel.find_child("BtnBuildRoadSpine", true, false) as Button
		if spine_btn == null or not spine_btn.visible:
			_fail("F3 %s spine missing" % prov_name)
			return false
		var spine_rect := spine_btn.get_global_rect()
		for ctrl in controls:
			if spine_rect.intersects((ctrl as Control).get_global_rect()):
				_fail("F3 %s spine overlaps %s" % [prov_name, str(ctrl.name)])
				return false
		if scroll.position.y + 0.5 < spine_btn.position.y + spine_btn.size.y:
			_fail("F3 %s scroll overlaps spine" % prov_name)
			return false
	return true


func _f3_glyphs_clear(lab: Label, close: Button) -> bool:
	var count := lab.get_total_character_count()
	if count <= 0:
		return false
	var xf := lab.get_global_transform()
	var close_rect := close.get_global_rect()
	var seen := 0
	for i in count:
		var local := lab.get_character_bounds(i)
		if local.size.x <= 0.0 or local.size.y <= 0.0:
			continue
		var gr := Rect2(xf * local.position, local.size)
		seen += 1
		if close_rect.intersects(gr):
			return false
		if not lab.get_global_rect().encloses(gr):
			return false
	return seen > 0


func _f3_border(btn: Button) -> Color:
	var st := btn.get_theme_stylebox("normal") as StyleBoxFlat
	if st == null:
		return Color(0, 0, 0, 0)
	return st.border_color


func _check_f3_close_click() -> bool:
	var built: Dictionary = _f3_build("Berlin", 710300, false)
	if built.is_empty():
		_fail("F3 close harness missing")
		return false
	var panel: Control = built["panel"]
	var mr: Node = built["mr"]
	var close: Button = built["close"]
	mr.call("_layout_info_panel_inner")
	await _frames(2)
	var center: Vector2 = close.get_global_rect().get_center()
	var hit := InputEventMouseButton.new()
	hit.button_index = MOUSE_BUTTON_LEFT
	hit.pressed = true
	hit.position = center
	hit.global_position = center
	if mr.call("_press_hits_inspector_close", hit) != true:
		_fail("F3 close ignored event at %s" % str(center))
		_f3_free(built)
		return false
	var miss := InputEventMouseButton.new()
	miss.button_index = MOUSE_BUTTON_LEFT
	miss.pressed = true
	miss.position = Vector2(-20, -20)
	miss.global_position = miss.position
	if mr.call("_press_hits_inspector_close", miss) == true:
		_fail("F3 close hit a point outside the button")
		_f3_free(built)
		return false
	var cover_script: GDScript = load("res://scripts/ui/DraggablePanel.gd") as GDScript
	var cover: Control = cover_script.new() as Control
	cover.name = "LeaderAssignmentScreen"
	cover.visible = true
	cover.position = close.get_global_rect().position - Vector2(10, 10)
	cover.size = close.get_global_rect().size + Vector2(20, 20)
	cover.custom_minimum_size = cover.size
	root.add_child(cover)
	await _frames(1)
	if mr.call("_press_hits_inspector_close", hit) == true:
		_fail("F3 close stole a click covered by another screen")
		cover.queue_free()
		_f3_free(built)
		return false
	cover.visible = false
	await _frames(1)
	if mr.call("_try_inspector_close_from_event", hit) != true or panel.visible:
		_fail("F3 close event did not hide the inspector")
		cover.queue_free()
		_f3_free(built)
		return false
	cover.queue_free()
	_f3_free(built)
	await _frames(1)
	return true


func _f3_free(built: Dictionary) -> void:
	var panel: Node = built.get("panel")
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	var mr: Node = built.get("mr")
	if mr != null and is_instance_valid(mr):
		mr.queue_free()


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


func _check_f4() -> void:
	await _set_size(Vector2i(1280, 800))
	if not await _f4_boot_map():
		return
	if not await _f4_check_diplomacy_copy():
		return
	if not await _f4_esc_one("res://scenes/ui/DiplomacyView.tscn", "DiplomacyView", true):
		return
	if not await _f4_esc_one("res://scenes/ui/TechnologyScreen.tscn", "TechnologyScreen", false):
		return
	if not await _f4_esc_one("res://scenes/ui/LeaderAssignmentScreen.tscn", "LeaderAssignmentScreen", false):
		return
	if not await _f4_esc_top_only():
		return
	_f4_done = true


func _f4_boot_map() -> bool:
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		_fail("F4 MapRenderer missing")
		return false
	var mr := scr.new() as Node
	if mr == null:
		_fail("F4 MapRenderer did not construct")
		return false
	mr.name = "F4Map"
	var containers := Node2D.new()
	containers.name = "ProvinceContainers"
	mr.add_child(containers)
	if "container" in mr:
		mr.container = containers
	var map_ui := CanvasLayer.new()
	map_ui.name = "UI"
	mr.add_child(map_ui)
	var info := Panel.new()
	info.name = "InfoPanel"
	info.visible = false
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_ui.add_child(info)
	mr.set("info_panel", info)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.position = Vector2(400, 300)
	mr.add_child(cam)
	root.add_child(mr)
	_f4_map = mr
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	layer.layer = 110
	root.add_child(layer)
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		_fail("F4 TopInfoBar missing")
		return false
	var bar := packed.instantiate()
	bar.name = "TopInfoBar"
	layer.add_child(bar)
	await _frames(2)
	return true


func _f4_check_diplomacy_copy() -> bool:
	var dip := await _f4_open("res://scenes/ui/DiplomacyView.tscn", "DiplomacyView")
	if dip == null:
		return false
	await _frames(2)
	var banned := _f4_banned_copy(dip)
	if not banned.is_empty():
		_fail("F4 1936 diplomacy text %s" % banned)
		dip.queue_free()
		return false
	if dip.find_child("ArmisticeBlock", true, false) != null or dip.find_child("OpenPeaceConference", true, false) != null:
		_fail("F4 armistice block is present in 1936")
		dip.queue_free()
		return false
	var empty := dip.find_child("EmptyOffers", true, false) as Label
	var selected := str(dip.get("_selected_country")).strip_edges()
	if empty == null or empty.text != "No active offers with %s" % selected:
		_fail("F4 empty offers text %s" % (empty.text if empty != null else "missing"))
		dip.queue_free()
		return false
	if empty.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
		_fail("F4 empty offers are not centered")
		dip.queue_free()
		return false
	if int(empty.get_theme_font_size("font_size")) != 14 or empty.get_theme_color("font_color") != RetrowaveTheme.TEXT_DIM:
		_fail("F4 empty offers style")
		dip.queue_free()
		return false
	var propose := dip.find_child("ProposeTrade", true, false) as Button
	if propose == null or propose.text != "Propose trade" or propose.get_theme_color("font_color") != RetrowaveTheme.CYAN:
		_fail("F4 propose trade button")
		dip.queue_free()
		return false
	var offers := dip.find_child("OffersScroll", true, false) as ScrollContainer
	var lower := dip.find_child("LowerScroll", true, false) as ScrollContainer
	if offers == null or lower == null:
		_fail("F4 scroll nodes missing")
		dip.queue_free()
		return false
	if offers.custom_minimum_size.y != 0.0 or lower.custom_minimum_size.y != 0.0:
		_fail("F4 scroll min height %s / %s" % [offers.custom_minimum_size.y, lower.custom_minimum_size.y])
		dip.queue_free()
		return false
	if (offers.size_flags_vertical & Control.SIZE_EXPAND) != 0 or (lower.size_flags_vertical & Control.SIZE_EXPAND) != 0:
		_fail("F4 empty scroll still expands")
		dip.queue_free()
		return false
	await _frames(2)
	if offers.size.y >= 300.0:
		_fail("F4 offers scroll dead space %s" % offers.size)
		dip.queue_free()
		return false
	dip.queue_free()
	await _frames(1)
	return true


func _f4_esc_one(scene_path: String, node_name: String, window_key: bool) -> bool:
	await _f4_drop_menu()
	var screen := await _f4_open(scene_path, node_name)
	if screen == null:
		return false
	await _frames(1)
	if not _f4_up(screen):
		_fail("F4 %s was not open" % node_name)
		return false
	var key := _f4_esc_key()
	if window_key and is_instance_valid(screen) and screen is Window:
		(screen as Window).push_input(key)
	else:
		root.push_input(key)
	await _frames(1)
	if is_instance_valid(screen) and _f4_up(screen):
		_fail("F4 Esc did not close %s" % node_name)
		screen.queue_free()
		return false
	if _f4_menu_up():
		_fail("F4 Esc that closed %s also opened pause" % node_name)
		return false
	await _frames(2)
	root.push_input(_f4_esc_key())
	await _frames(3)
	if not _f4_menu_up():
		_fail("F4 second Esc did not open pause after %s" % node_name)
		return false
	await _f4_drop_menu()
	return true


func _f4_esc_top_only() -> bool:
	await _f4_drop_menu()
	var tech := await _f4_open("res://scenes/ui/TechnologyScreen.tscn", "TechnologyScreen")
	var dip := await _f4_open("res://scenes/ui/DiplomacyView.tscn", "DiplomacyView")
	if tech == null or dip == null:
		return false
	await _frames(1)
	root.push_input(_f4_esc_key())
	await _frames(1)
	if is_instance_valid(dip) and _f4_up(dip):
		_fail("F4 Esc left Diplomacy open over Tech")
		dip.queue_free()
		if is_instance_valid(tech):
			tech.queue_free()
		return false
	if not is_instance_valid(tech) or not _f4_up(tech):
		_fail("F4 one Esc closed Tech along with Diplomacy")
		return false
	if _f4_menu_up():
		_fail("F4 Esc that closed Diplomacy also opened pause")
		tech.queue_free()
		return false
	tech.queue_free()
	await _frames(1)
	return true


func _f4_open(scene_path: String, node_name: String) -> Node:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		_fail("F4 missing %s" % scene_path)
		return null
	var inst := packed.instantiate()
	if inst == null:
		_fail("F4 %s did not instantiate" % node_name)
		return null
	inst.name = node_name
	root.add_child(inst)
	await _frames(2)
	return inst


func _f4_drop_menu() -> void:
	var mm := root.get_node_or_null("MainMenu")
	if mm != null and is_instance_valid(mm):
		mm.queue_free()
	await _frames(1)


func _f4_up(n: Node) -> bool:
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		return false
	if str(n.name).ends_with("_dying"):
		return false
	if n is Window:
		return (n as Window).visible
	if n is CanvasItem:
		return (n as CanvasItem).visible
	return true


func _f4_menu_up() -> bool:
	var mm := root.get_node_or_null("MainMenu")
	if mm == null or not is_instance_valid(mm) or mm.is_queued_for_deletion():
		return false
	if str(mm.name) != "MainMenu":
		return false
	if mm is CanvasItem:
		return (mm as CanvasItem).visible
	return true


func _f4_esc_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.device = 0
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.key_label = KEY_ESCAPE
	key.pressed = true
	key.echo = false
	return key


func _f4_banned_copy(n: Node) -> String:
	var hits: PackedStringArray = PackedStringArray()
	_f4_walk_copy(n, hits)
	return " | ".join(hits)


func _f4_walk_copy(n: Node, hits: PackedStringArray) -> void:
	if n == null or not is_instance_valid(n):
		return
	var text := ""
	if n is Label or n is Button or n is RichTextLabel or n is LinkButton:
		text = str(n.get("text"))
	for token in ["Future:", "1918", "F10"]:
		if token in text:
			hits.append("%s [%s]" % [str(n.name), text])
			break
	for child in n.get_children():
		_f4_walk_copy(child, hits)
