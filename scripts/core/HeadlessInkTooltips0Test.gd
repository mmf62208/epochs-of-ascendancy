extends SceneTree

## INK-TOOLTIPS-P0: global tooltip theme, Fill ≠ Strength, resource copy,
## date box width, and five resource chips inside the viewport.
## Fails on a4ebd959 (delay 0.5, empty resource tips, clipped date).
## Fails on 93fd001b: at 1280×800 the war chip pushes Rubber out of the
## viewport, Energy has no chip, and Search runs past the right edge.
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
	_seed_resource_stockpile()
	if bar.has_method("_update_resources"):
		bar.call("_update_resources")
	var steel := bar.get("steel_label") as Label
	var aluminum := bar.get("aluminum_label") as Label
	var oil := bar.get("oil_label") as Label
	var rubber := bar.get("rubber_label") as Label
	var energy := bar.get("energy_label") as Label
	if energy == null:
		energy = bar.find_child("EnergyLabel", true, false) as Label
	var date_lbl := bar.get("date_time_label") as Label
	var pause_btn := bar.get("pause_button") as Button
	_expect_tip(steel, "Steel", "steel")
	_expect_tip(aluminum, "Aluminum", "aluminum")
	_expect_tip(rubber, "Rubber", "rubber")
	_expect_tip(energy, "Energy", "energy")
	if energy != null and not str(energy.tooltip_text).contains("Runs factories. Shortages cut output."):
		_fail("energy tooltip missing factory body: %s" % str(energy.tooltip_text))
	if oil == null or str(oil.tooltip_text).strip_edges().is_empty():
		_fail("fuel tooltip empty")
	elif not str(oil.tooltip_text).contains("Press G to check supply."):
		_fail("fuel tooltip missing G body: %s" % str(oil.tooltip_text))
	elif not str(oil.tooltip_text).contains("[G]"):
		_fail("fuel tooltip missing [G]: %s" % str(oil.tooltip_text))
	elif str(oil.tooltip_text).contains("Runs factories"):
		_fail("fuel tooltip includes the energy body: %s" % str(oil.tooltip_text))
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
	await _assert_resource_chips(1280, 800, false)
	await _assert_resource_chips(1280, 800, true)
	await _assert_resource_chips(1600, 900, false)
	await _assert_resource_chips(1920, 1080, false)


func _seed_resource_stockpile() -> void:
	var pm := root.get_node_or_null("ProductionManager")
	if pm != null and "national_stockpile" in pm:
		pm.national_stockpile = {
			"steel": 12400.0,
			"aluminum": 3400.0,
			"energy": 9000.0,
			"fuel": 12000.0,
			"rubber": 800.0,
		}


func _assert_resource_chips(vp_w: int, vp_h: int, at_war: bool) -> void:
	DisplayServer.window_set_size(Vector2i(vp_w, vp_h))
	root.size = Vector2i(vp_w, vp_h)
	var ui := CanvasLayer.new()
	ui.name = "InkChipUI"
	ui.layer = 110
	root.add_child(ui)
	var packed := load(BAR_SCENE) as PackedScene
	if packed == null:
		_fail("TopInfoBar scene missing for %d layout" % vp_w)
		ui.queue_free()
		return
	var bar := packed.instantiate() as Control
	if bar == null:
		_fail("TopInfoBar instantiate failed for %d layout" % vp_w)
		ui.queue_free()
		return
	if "player_country_tag" in bar:
		bar.set("player_country_tag", "GER")
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 0.0
	bar.offset_top = 0.0
	bar.offset_right = 0.0
	bar.offset_bottom = 52.0
	ui.add_child(bar)
	_seed_resource_stockpile()
	var search_script := load("res://scripts/ui/map/MapProvinceSearch.gd")
	var search: Control = null
	if search_script != null:
		search = search_script.new() as Control
	if search != null:
		search.name = "MapProvinceSearch"
		if bar.has_method("host_map_search_chrome"):
			bar.call("host_map_search_chrome", search)
	if at_war:
		_arm_one_war()
	else:
		_clear_war()
	if bar.has_method("refresh_campaign_war_readout"):
		bar.call("refresh_campaign_war_readout")
	if bar.has_method("_update_resources"):
		bar.call("_update_resources")
	if bar.has_method("_apply_responsive_layout"):
		bar.call("_apply_responsive_layout")
	_play_search_layout(search)
	for _i in 4:
		await process_frame
	var vp := Rect2(0, 0, float(vp_w), float(vp_h))
	var tag := "%dx%d war=%s" % [vp_w, vp_h, "1" if at_war else "0"]
	var specs: Array[Dictionary] = [
		{"key": "Steel", "nodes": ["SteelChip", "SteelLabel"], "body": "Rifles, artillery, tanks and ships. Stockpile refills division TOE daily."},
		{"key": "Aluminum", "nodes": ["AluminumChip", "AluminumLabel"], "body": "Aircraft and light vehicles."},
		{"key": "Energy", "nodes": ["EnergyChip", "EnergyLabel"], "body": "Runs factories. Shortages cut output."},
		{"key": "Rubber", "nodes": ["RubberChip", "RubberLabel"], "body": "Trucks and tires. Needed to fill motorized TOE."},
		{"key": "Fuel", "nodes": ["FuelChip", "OilLabel"], "body": "Press G to check supply."},
	]
	var chips: Array[Control] = []
	var tip_keys: Array[Dictionary] = []
	for spec in specs:
		var chip := _find_named(bar, spec["nodes"] as Array)
		var key := str(spec["key"])
		if chip == null:
			_fail("%s %s chip missing" % [tag, key])
			print("CHIP_RECT %s %s MISSING" % [tag, key])
			continue
		chips.append(chip)
		var r := chip.get_global_rect()
		var tip := str(chip.tooltip_text).strip_edges()
		tip_keys.append({"key": key, "tip": tip})
		var inside := _rect_inside(r, vp, 0.5)
		var clip_msg := _clip_ancestor_problem(chip)
		print("CHIP_RECT %s %s rect=%s vis=%s size=%s inside=%s clip=%s tip_len=%d" % [
			tag, key, str(r), str(chip.is_visible_in_tree()), str(chip.size), str(inside),
			clip_msg if not clip_msg.is_empty() else "ok", tip.length(),
		])
		if not chip.is_visible_in_tree():
			_fail("%s %s not visible in tree" % [tag, key])
		elif chip.size.x <= 0.0 or chip.size.y <= 0.0:
			_fail("%s %s size is zero %s" % [tag, key, str(chip.size)])
		elif not inside:
			_fail("%s %s rect not inside viewport %s" % [tag, key, str(r)])
		elif not clip_msg.is_empty():
			_fail("%s %s %s" % [tag, key, clip_msg])
		elif tip.is_empty():
			_fail("%s %s tooltip empty" % [tag, key])
		elif not tip.contains(str(spec["body"])):
			_fail("%s %s tooltip missing body: %s" % [tag, key, tip])
		elif key == "Fuel" and not tip.contains("[G]"):
			_fail("%s Fuel tooltip missing [G]: %s" % [tag, tip])
		elif key == "Fuel" and tip.contains("Runs factories"):
			_fail("%s Fuel tooltip includes energy body" % tag)
		elif key != "Fuel" and tip.contains("Press G to check supply."):
			_fail("%s %s tooltip includes the fuel body" % [tag, key])
		else:
			_pass("%s %s chip %s" % [tag, key, str(r)])
	var seen: Dictionary = {}
	for pair in tip_keys:
		var tip_s := str(pair["tip"])
		if tip_s.is_empty():
			continue
		if seen.has(tip_s):
			_fail("%s tooltip duplicated %s and %s" % [tag, str(seen[tip_s]), str(pair["key"])])
		else:
			seen[tip_s] = str(pair["key"])
	if seen.size() == specs.size():
		_pass("%s five tooltips distinct" % tag)
	var hosted: Control = search
	if hosted == null or not is_instance_valid(hosted):
		hosted = bar.find_child("MapProvinceSearch", true, false) as Control
	var blockers: Array[Control] = []
	if hosted != null:
		blockers.append(hosted)
		var sr := hosted.get_global_rect()
		print("CHIP_RECT %s Search rect=%s vis=%s size=%s inside=%s" % [
			tag, str(sr), str(hosted.is_visible_in_tree()), str(hosted.size), str(_rect_inside(sr, vp, 0.5)),
		])
		if not hosted.is_visible_in_tree() or hosted.size.x <= 0.0 or hosted.size.y <= 0.0:
			_fail("%s search missing" % tag)
		elif not _rect_inside(sr, vp, 0.5):
			_fail("%s search not inside viewport %s" % [tag, str(sr)])
		else:
			_pass("%s search inside %s" % [tag, str(sr)])
	for nm in ["PauseButton", "Speed1Button", "Speed2Button", "Speed3Button", "Speed4Button", "DateTimeLabel"]:
		var clock := bar.find_child(nm, true, false) as Control
		if clock == null or not clock.is_visible_in_tree():
			_fail("%s %s missing" % [tag, nm])
			continue
		blockers.append(clock)
		var cr := clock.get_global_rect()
		print("CHIP_RECT %s %s rect=%s" % [tag, nm, str(cr)])
		if not _rect_inside(cr, vp, 0.5):
			_fail("%s %s not inside viewport %s" % [tag, nm, str(cr)])
	for i in chips.size():
		for j in range(i + 1, chips.size()):
			if _rects_overlap(chips[i].get_global_rect(), chips[j].get_global_rect()):
				_fail("%s chips overlap %s" % [tag, str(chips[i].get_global_rect())])
		for b in blockers:
			if _rects_overlap(chips[i].get_global_rect(), b.get_global_rect()):
				_fail("%s %s overlaps %s %s vs %s" % [
					tag, chips[i].name, b.name, str(chips[i].get_global_rect()), str(b.get_global_rect()),
				])
	bar.queue_free()
	ui.queue_free()
	await process_frame


func _find_named(bar: Node, names: Array) -> Control:
	for nm in names:
		var chip := bar.find_child(str(nm), true, false) as Control
		if chip != null:
			return chip
	return null


func _clear_war() -> void:
	var war := load("res://scripts/core/WarStateDomain.gd") as GDScript
	if war != null and war.has_method("reset_for_test"):
		war.call("reset_for_test")


func _arm_one_war() -> void:
	var lm := root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var tm := root.get_node_or_null("TimeManager")
	if tm != null:
		tm.scenario_start_year = 1936
		tm.current_year = 1936
		tm.current_month = 1
		tm.current_day = 1
	var war := load("res://scripts/core/WarStateDomain.gd") as GDScript
	if war == null:
		_fail("WarStateDomain missing")
		return
	if war.has_method("reset_for_test"):
		war.call("reset_for_test")
	if war.has_method("clear_rule_overrides"):
		war.call("clear_rule_overrides")
	if war.has_method("declare_war"):
		var one: Dictionary = war.call("declare_war", "GER", "POL", "call_to_arms")
		if not bool(one.get("ok", false)):
			_fail("declare POL failed %s" % str(one))


func _play_search_layout(search: Control) -> void:
	## Play calls MapRenderer._layout_map_search_chrome after the bar hosts Search.
	## On 93fd001b that forces a 308px Search and shoves the right side off 1280.
	if search == null or not is_instance_valid(search):
		return
	var mr_script := load("res://scripts/map/MapRenderer.gd")
	if mr_script == null:
		_fail("MapRenderer script missing for search layout")
		return
	var mr: Node = mr_script.new()
	mr.set("_map_search", search)
	if mr.has_method("_layout_map_search_chrome"):
		mr.call("_layout_map_search_chrome")
	mr.free()


func _rect_inside(r: Rect2, outer: Rect2, slop: float) -> bool:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return false
	return (
		r.position.x + slop >= outer.position.x
		and r.position.y + slop >= outer.position.y
		and r.end.x <= outer.end.x + slop
		and r.end.y <= outer.end.y + slop
	)


func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	var aa := a.grow(-0.5)
	var bb := b.grow(-0.5)
	if aa.size.x <= 0.0 or aa.size.y <= 0.0 or bb.size.x <= 0.0 or bb.size.y <= 0.0:
		return false
	return aa.intersects(bb)


func _clip_ancestor_problem(c: Control) -> String:
	var r := c.get_global_rect()
	var n: Node = c.get_parent()
	while n != null:
		if n is Control and (n as Control).clip_contents:
			var pr := (n as Control).get_global_rect()
			if not _rect_inside(r, pr, 0.5):
				return "clipped by %s rect=%s parent=%s" % [n.name, str(r), str(pr)]
		n = n.get_parent()
	return ""


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
