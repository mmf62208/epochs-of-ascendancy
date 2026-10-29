extends SceneTree

## INK-TOOLTIPS-P0: global tooltip theme, Fill ≠ Strength, resource copy,
## date box width. Fails on a4ebd959 (delay 0.5, empty resource tips, clipped date).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessInkTooltips0Test.gd
##
## Does not load the world map. Headless is NOT live Play.

const BAR_SCENE := "res://scenes/ui/TopInfoBar.tscn"
const STRIP_SRC := "res://scripts/ui/UnitCardCombatStrip.gd"
const MAP_SRC := "res://scripts/map/MapRenderer.gd"

var _failures: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessInkTooltips0Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessInkTooltips0Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessInkTooltips0Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessInkTooltips0Test: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _run() -> void:
	_test_delay_and_theme()
	_test_tooltip_clamp()
	await _test_bar_tooltips()
	await _test_bar_1280_resources()
	_test_fill_copy()
	_test_dress_wrap()
	_test_begin_tooltip()


func _test_delay_and_theme() -> void:
	var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	if is_equal_approx(delay, 0.45):
		_pass("tooltip_delay_sec=0.45")
	else:
		_fail("tooltip_delay_sec=%s want 0.45" % str(delay))
	var theme_script := load("res://scripts/ui/RetrowaveTheme.gd")
	if theme_script == null or not theme_script.has_method("install_tooltip_theme"):
		_fail("RetrowaveTheme.install_tooltip_theme missing")
		return
	theme_script.call("install_tooltip_theme", self)
	var theme := ThemeDB.get_default_theme()
	if theme == null:
		_fail("default theme missing")
		return
	var font_px := int(theme.get_font_size("font_size", "TooltipLabel"))
	if font_px >= 13 and font_px <= 14:
		_pass("TooltipLabel font_size=%d" % font_px)
	else:
		_fail("TooltipLabel font_size=%d want 13-14" % font_px)
	if theme.get_stylebox("panel", "TooltipPanel") != null:
		_pass("TooltipPanel stylebox set")
	else:
		_fail("TooltipPanel stylebox missing")
	var max_w := int(theme.get_constant("max_width", "TooltipLabel"))
	if max_w == 320:
		_pass("TooltipLabel max_width=320")
	else:
		_fail("TooltipLabel max_width=%d want 320" % max_w)


func _test_bar_tooltips() -> void:
	var packed := load(BAR_SCENE) as PackedScene
	if packed == null:
		_fail("TopInfoBar scene missing")
		return
	var bar := packed.instantiate() as Control
	if bar == null:
		_fail("TopInfoBar instantiate failed")
		return
	root.add_child(bar)
	await process_frame
	await process_frame
	var steel := bar.get("steel_label") as Label
	var aluminum := bar.get("aluminum_label") as Label
	var oil := bar.get("oil_label") as Label
	var rubber := bar.get("rubber_label") as Label
	var date_lbl := bar.get("date_time_label") as Label
	var pause_btn := bar.get("pause_button") as Button
	_expect_tip(steel, "Steel", "steel")
	_expect_tip(aluminum, "Aluminum", "aluminum")
	_expect_tip(rubber, "Rubber", "rubber")
	if oil == null or str(oil.tooltip_text).strip_edges().is_empty():
		_fail("fuel tooltip empty")
	elif not ("G" in str(oil.tooltip_text)):
		_fail("fuel tooltip missing G: %s" % str(oil.tooltip_text))
	else:
		_pass("fuel tooltip mentions G")
	if date_lbl == null:
		_fail("date label missing")
	else:
		if not str(date_lbl.text).contains("(+"):
			date_lbl.text = str(date_lbl.text) + " (+4d)"
		if bar.has_method("_fit_date_label"):
			bar.call("_fit_date_label")
		var font := date_lbl.get_theme_font("font")
		var fsize := date_lbl.get_theme_font_size("font_size")
		if fsize <= 0:
			fsize = 13
		var need := 0.0
		if font != null:
			need = font.get_string_size(date_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		else:
			need = float(date_lbl.text.length()) * 8.0
		if date_lbl.custom_minimum_size.x + 0.5 < need:
			_fail("date min %.1f < text width %.1f (%s)" % [date_lbl.custom_minimum_size.x, need, date_lbl.text])
		elif date_lbl.clip_text:
			_fail("date clip_text still true")
		else:
			_pass("date min %.1f >= text %.1f" % [date_lbl.custom_minimum_size.x, need])
		var date_tip := str(date_lbl.tooltip_text)
		if date_tip.contains("UI stays live") or date_tip.contains("The UI stays live"):
			_fail("date tooltip duplicates pause body")
		elif not (date_tip.contains("Each day") or date_tip.contains("Running at")):
			_fail("date tooltip missing day body: %s" % date_tip)
		else:
			_pass("date tooltip is the calendar body")
		if pause_btn == null:
			_fail("pause button missing")
		else:
			var pause_tip := str(pause_btn.tooltip_text)
			if pause_tip == date_tip or pause_tip.contains(date_tip):
				_fail("pause tooltip duplicates date")
			elif pause_tip.contains("Each day"):
				_fail("pause tooltip contains date body")
			elif not pause_tip.contains("UI stays live"):
				_fail("pause tooltip missing live-UI body: %s" % pause_tip)
			else:
				_pass("pause tooltip distinct from date")
	var speed := bar.find_child("SpeedOverflowMenu", true, false) as MenuButton
	var speed_tip := ""
	if speed != null:
		speed_tip = str(speed.tooltip_text)
	elif bar.has_method("_speed_tooltip"):
		speed_tip = str(bar.call("_speed_tooltip"))
	if speed_tip.is_empty():
		_fail("speed tooltip missing")
	elif not (speed_tip.contains("[1]") and speed_tip.contains("[4]")):
		_fail("speed tooltip missing 1-4: %s" % speed_tip)
	elif speed_tip.contains("[+]") or speed_tip.contains("[-]"):
		_fail("speed tooltip has unbound +/-: %s" % speed_tip)
	else:
		_pass("speed tooltip is 1-4 only")
	bar.queue_free()


func _expect_tip(lbl: Label, phrase: String, name: String) -> void:
	if lbl == null or str(lbl.tooltip_text).strip_edges().is_empty():
		_fail("%s tooltip empty" % name)
	elif not (phrase in str(lbl.tooltip_text)):
		_fail("%s tooltip missing %s" % [name, phrase])
	else:
		_pass("%s tooltip set" % name)


func _test_fill_copy() -> void:
	var strip := _read(STRIP_SRC)
	var ren := _read(MAP_SRC)
	if not strip.contains("func fill_line_tooltip"):
		_fail("fill_line_tooltip missing")
	else:
		var strip_script := load(STRIP_SRC)
		if strip_script == null or not strip_script.has_method("fill_line_tooltip"):
			_fail("fill_line_tooltip missing")
		else:
			var tip := str(strip_script.call("fill_line_tooltip", null))
			if tip.contains("Fill") and tip.contains("Strength 1.00"):
				_pass("fill tooltip names Fill and Strength 1.00")
			else:
				_fail("fill tooltip missing Strength value: %s" % tip)
	if not ren.contains("Fill ≠ Strength"):
		_fail("MapRenderer fill tooltip literal missing")
	else:
		_pass("MapRenderer fill tooltip literal")
	if not (ren.contains("fill_ratio < 0.5") and ren.contains("RetrowaveTheme.WARNING")):
		_fail("Fill WARNING below 50% wiring missing")
	else:
		_pass("Fill WARNING below 50%")
	# 320-wide stack: fill label and bar keep their minimums (no clip).
	var host := PanelContainer.new()
	host.clip_contents = false
	host.custom_minimum_size = Vector2(320, 220)
	var box := VBoxContainer.new()
	box.clip_contents = false
	host.add_child(box)
	var fill := Label.new()
	fill.text = "Fill 42%"
	fill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fill.clip_text = false
	fill.custom_minimum_size = Vector2(290, 22)
	fill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(fill)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 4)
	bar.clip_contents = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)
	root.add_child(host)
	host.reset_size()
	if host.custom_minimum_size.y < 220.0 or fill.custom_minimum_size.y < 22.0 or bar.custom_minimum_size.y < 4.0:
		_fail("fill stack min size collapsed")
	elif fill.clip_text or host.clip_contents:
		_fail("fill stack clips")
	else:
		_pass("fill line+bar min size on 320x220")
	host.queue_free()


func _test_dress_wrap() -> void:
	var theme_script := load("res://scripts/ui/RetrowaveTheme.gd")
	if theme_script == null or not theme_script.has_method("dress_tooltip_popup"):
		_fail("dress_tooltip_popup missing")
		return
	var pop := PopupPanel.new()
	pop.theme_type_variation = "TooltipPanel"
	var lab := Label.new()
	lab.theme_type_variation = "TooltipLabel"
	lab.text = "Steel · 1,240\nRifles, artillery, tanks and ships. Stockpile refills division TOE daily. This sentence is long enough to wrap inside three hundred twenty pixels.\n[G]"
	pop.add_child(lab)
	root.add_child(pop)
	theme_script.call("dress_tooltip_popup", pop)
	var dressed: Label = lab
	if lab.get_parent() != pop:
		dressed = lab
	if dressed.autowrap_mode == TextServer.AUTOWRAP_OFF:
		_fail("dressed tooltip autowrap off")
	elif not is_equal_approx(dressed.custom_maximum_size.x, 320.0):
		_fail("dressed max width %s want 320" % str(dressed.custom_maximum_size))
	else:
		_pass("dressed tooltip wraps at 320")
	var min_s := dressed.get_combined_minimum_size()
	if min_s.x < 200.0 or min_s.x > 340.0:
		_fail("dressed width collapsed %s" % str(min_s))
	elif min_s.y < 28.0:
		_fail("dressed height collapsed %s" % str(min_s))
	else:
		_pass("dressed tooltip keeps a readable width %s" % str(min_s))
	var chip := pop.find_child("HotkeyChip", true, false)
	if chip == null:
		_fail("hotkey chip missing")
	else:
		_pass("hotkey chip present")
	if theme_script.has_method("place_tooltip_popup"):
		var vp_r := Rect2(0, 0, 1280, 800)
		var anc := Rect2(200, 760, 80, 24)
		var placed: Rect2 = theme_script.call("place_tooltip_popup", pop, vp_r, anc)
		if not _rect_inside_viewport(placed, vp_r):
			_fail("placed dress popup left viewport %s" % str(placed))
		else:
			_pass("placed dress popup inside viewport %s" % str(placed))
	pop.queue_free()


func _rect_inside_viewport(r: Rect2, vp: Rect2) -> bool:
	if r.size.x < 1.0 or r.size.y < 1.0:
		return false
	return (
		r.position.x + 0.01 >= vp.position.x
		and r.position.y + 0.01 >= vp.position.y
		and r.position.x + r.size.x <= vp.position.x + vp.size.x + 0.01
		and r.position.y + r.size.y <= vp.position.y + vp.size.y + 0.01
	)


func _test_tooltip_clamp() -> void:
	var theme_script := load("res://scripts/ui/RetrowaveTheme.gd")
	if theme_script == null or not theme_script.has_method("clamp_tooltip_rect"):
		_fail("clamp_tooltip_rect missing")
		return
	var vp := Rect2(0, 0, 1280, 800)
	var tip := Vector2(280, 96)
	var bottom: Rect2 = theme_script.call("clamp_tooltip_rect", tip, vp, Rect2(400, 760, 80, 24))
	if not _rect_inside_viewport(bottom, vp):
		_fail("bottom tooltip not inside viewport %s" % str(bottom))
	elif bottom.position.y + bottom.size.y > 760.0 + 0.5:
		_fail("bottom tooltip did not flip above anchor %s" % str(bottom))
	else:
		_pass("bottom tooltip flipped above %s" % str(bottom))
	var right: Rect2 = theme_script.call("clamp_tooltip_rect", tip, vp, Rect2(1200, 200, 70, 24))
	if not _rect_inside_viewport(right, vp):
		_fail("right tooltip not inside viewport %s" % str(right))
	elif right.position.x + right.size.x > 1280.0 + 0.5:
		_fail("right tooltip overflowed %s" % str(right))
	else:
		_pass("right tooltip flipped left %s" % str(right))
	var left: Rect2 = theme_script.call("clamp_tooltip_rect", tip, vp, Rect2(4, 200, 40, 24))
	if not _rect_inside_viewport(left, vp):
		_fail("left tooltip not inside viewport %s" % str(left))
	else:
		_pass("left tooltip clamped %s" % str(left))
	var top: Rect2 = theme_script.call("clamp_tooltip_rect", tip, vp, Rect2(400, 4, 80, 24))
	if not _rect_inside_viewport(top, vp):
		_fail("top tooltip not inside viewport %s" % str(top))
	else:
		_pass("top tooltip stays inside %s" % str(top))
	var corner: Rect2 = theme_script.call("clamp_tooltip_rect", tip, vp, Rect2(1210, 770, 60, 24))
	if not _rect_inside_viewport(corner, vp):
		_fail("corner tooltip not inside viewport %s" % str(corner))
	else:
		_pass("corner tooltip flipped+clamped %s" % str(corner))
	var pop := PopupPanel.new()
	pop.theme_type_variation = "TooltipPanel"
	var lab := Label.new()
	lab.theme_type_variation = "TooltipLabel"
	lab.text = "FRA Garrison 4\nOrg 80 · Strength 1.00 · Fill 0%\nLast line must stay inside the viewport."
	pop.add_child(lab)
	root.add_child(pop)
	theme_script.call("dress_tooltip_popup", pop)
	var placed: Rect2 = theme_script.call(
		"place_tooltip_popup", pop, vp, Rect2(520, 770, 90, 28)
	)
	if not _rect_inside_viewport(placed, vp):
		_fail("popup place left viewport %s" % str(placed))
	elif placed.position.y + placed.size.y > 770.0 + 0.5:
		_fail("popup place did not flip above %s" % str(placed))
	else:
		_pass("popup place flipped above at 1280x800 %s" % str(placed))
	pop.queue_free()


func _test_bar_1280_resources() -> void:
	var packed := load(BAR_SCENE) as PackedScene
	if packed == null:
		_fail("TopInfoBar scene missing for 1280 layout")
		return
	var bar := packed.instantiate() as Control
	if bar == null:
		_fail("TopInfoBar instantiate failed for 1280 layout")
		return
	bar.set_meta("eoa_layout_vp_w", 1280.0)
	bar.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	bar.offset_left = 0.0
	bar.offset_top = 0.0
	bar.offset_right = 1280.0
	bar.offset_bottom = 52.0
	bar.custom_minimum_size = Vector2(1280, 52)
	bar.size = Vector2(1280, 52)
	root.add_child(bar)
	var search_script := load("res://scripts/ui/map/MapProvinceSearch.gd")
	var search: Control = null
	if search_script != null:
		search = search_script.new() as Control
	if search != null:
		search.name = "MapProvinceSearch"
		if bar.has_method("host_map_search_chrome"):
			bar.call("host_map_search_chrome", search)
	if bar.has_method("_apply_responsive_layout"):
		bar.call("_apply_responsive_layout")
	if bar.has_method("_update_resources"):
		bar.call("_update_resources")
	await process_frame
	await process_frame
	await process_frame
	var steel := bar.get("steel_label") as Label
	var aluminum := bar.get("aluminum_label") as Label
	var oil := bar.get("oil_label") as Label
	var rubber := bar.get("rubber_label") as Label
	var hosted: Control = search
	if hosted == null or not is_instance_valid(hosted):
		hosted = bar.find_child("MapProvinceSearch", true, false) as Control
	var labels: Array[Label] = [steel, aluminum, oil, rubber]
	var names: PackedStringArray = PackedStringArray(["steel", "aluminum", "fuel", "rubber"])
	var all_ok := true
	for i in labels.size():
		var lab: Label = labels[i]
		var nm := str(names[i])
		if lab == null or not lab.visible:
			_fail("%s counter hidden at 1280" % nm)
			all_ok = false
			continue
		if lab.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			_fail("%s counter ignores mouse at 1280" % nm)
			all_ok = false
		var r := lab.get_global_rect()
		if r.size.x < 4.0 or r.size.y < 4.0:
			_fail("%s counter has empty rect %s" % [nm, str(r)])
			all_ok = false
		elif r.position.x + r.size.x > 1280.5:
			_fail("%s counter clipped at right edge %s" % [nm, str(r)])
			all_ok = false
		elif hosted != null and hosted.visible and r.intersects(hosted.get_global_rect()):
			_fail("%s counter overlapped by search %s vs %s" % [nm, str(r), str(hosted.get_global_rect())])
			all_ok = false
		else:
			_pass("%s counter visible/hoverable at 1280 %s" % [nm, str(r)])
	if hosted == null or not hosted.visible:
		_fail("search chrome missing at 1280")
	elif hosted.get_global_rect().position.x + hosted.get_global_rect().size.x > 1280.5:
		_fail("search chrome past right edge %s" % str(hosted.get_global_rect()))
	else:
		_pass("search chrome beside resources %s" % str(hosted.get_global_rect()))
	if all_ok:
		_pass("resource counters not overlapped by search at 1280")
	bar.queue_free()


func _test_begin_tooltip() -> void:
	var boot := load("res://scripts/ui/LivingTitleBoot.gd")
	if boot == null or not boot.has_method("begin_campaign_tooltip"):
		_fail("begin_campaign_tooltip missing")
		return
	var tip := str(boot.call("begin_campaign_tooltip", "GER", 1936))
	if tip.contains("Begin") and tip.contains("[Enter]") and tip.contains("[Space]"):
		_pass("Begin tooltip set")
	else:
		_fail("Begin tooltip missing body: %s" % tip)
