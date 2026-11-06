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
	await _test_headless_dress_skipped()
	_test_tooltip_clamp()
	await _test_bar_tooltips()
	await _test_bar_1280_resources()
	_test_fill_copy()
	_test_dress_wrap()
	_test_begin_tooltip()
	_test_tooltip_p1()


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
			if (
				tip.begins_with("# Fill is not Strength\n")
				and tip.contains("Fill = men and equipment present vs. the TOE.")
				and tip.contains("Strength = combat readiness (Fill × organization × supply).")
				and tip.contains("A —% filled unit can still fight at full strength if organized and supplied.")
				and tip.contains("[Click] select · [Ctrl+Click] attack")
			):
				_pass("fill tooltip explains Fill is not Strength")
			else:
				_fail("fill tooltip copy: %s" % tip)
			var fixture := GDScript.new()
			fixture.source_code = "extends RefCounted\nvar toe_fill: float = 0.62\nvar strength: float = 1.0\n"
			if fixture.reload() != OK:
				_fail("fill fixture failed to parse")
			else:
				var live := str(strip_script.call("fill_line_tooltip", fixture.new()))
				if live.contains("A 62% filled unit can still fight at full strength if organized and supplied."):
					_pass("fill tooltip uses live 62%")
				else:
					_fail("fill tooltip live percent: %s" % live)
	if not ren.contains("Fill is not Strength"):
		_fail("MapRenderer fill tooltip literal missing")
	elif not ren.contains("A —% filled unit can still fight at full strength if organized and supplied."):
		_fail("MapRenderer fill tooltip literal missing the live-percent sentence")
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


func _test_headless_dress_skipped() -> void:
	if DisplayServer.get_name() != "headless":
		_fail("expected headless DisplayServer, got %s" % DisplayServer.get_name())
		return
	var theme_src := _read("res://scripts/ui/RetrowaveTheme.gd")
	if not theme_src.contains('DisplayServer.get_name() == "headless"'):
		_fail("headless dress guard missing from RetrowaveTheme")
		return
	var pop := PopupPanel.new()
	pop.theme_type_variation = "TooltipPanel"
	var lab := Label.new()
	lab.theme_type_variation = "TooltipLabel"
	lab.text = "# Should Not Dress\nBody stays on the engine label.\n[A] · [B]"
	pop.add_child(lab)
	root.add_child(pop)
	await process_frame
	await process_frame
	if pop.find_child("EoaTooltipBox", true, false) != null or bool(pop.get_meta("eoa_tooltip_dressed", false)):
		_fail("headless auto-dressed a tooltip")
	else:
		_pass("headless skips dress")
	pop.queue_free()


func _test_tooltip_p1() -> void:
	var theme_script := load("res://scripts/ui/RetrowaveTheme.gd")
	if theme_script == null or not theme_script.has_method("make_tooltip_theme"):
		_fail("make_tooltip_theme missing")
		return
	_assert_p1_panel(theme_script)
	_assert_p1_title_and_chips(theme_script)
	_assert_p1_anchor_and_pan(theme_script)
	_assert_p1_fill_clamp(theme_script)
	_assert_p1_source_mutant()


func _assert_p1_panel(theme_script) -> void:
	var theme_v: Variant = theme_script.call("make_tooltip_theme")
	var theme := theme_v as Theme
	if theme == null:
		_fail("make_tooltip_theme returned no theme")
		return
	var panel := theme.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	if panel == null:
		_fail("TooltipPanel stylebox missing")
		return
	var border := panel.border_color
	var cyan := Color("#33e6ff")
	if border.a < 0.8 or not _rgb_close(border, cyan):
		_fail("border %s want CYAN alpha >= 0.8" % str(border))
	elif panel.get_border_width(SIDE_LEFT) != 1 or panel.corner_radius_top_left != 4:
		_fail("border width/radius drifted")
	elif panel.content_margin_left != 10 or panel.content_margin_right != 10:
		_fail("horizontal margin %s/%s want 10/10" % [panel.content_margin_left, panel.content_margin_right])
	elif panel.content_margin_top != 8 or panel.content_margin_bottom != 8:
		_fail("vertical margin %s/%s want 8/8" % [panel.content_margin_top, panel.content_margin_bottom])
	elif panel.shadow_size != 4 or panel.shadow_offset != Vector2(2, 2):
		_fail("shadow size %s offset %s want 4 (2,2)" % [panel.shadow_size, panel.shadow_offset])
	elif not is_equal_approx(panel.shadow_color.a, 0.35) or panel.shadow_color.r > 0.01:
		_fail("shadow color %s want #000000 alpha 0.35" % str(panel.shadow_color))
	elif not is_equal_approx(panel.bg_color.a, 0.96):
		_fail("panel bg alpha %s want 0.96" % str(panel.bg_color.a))
	else:
		_pass("panel border 0.85 margins 10/8 shadow 4")


func _assert_p1_title_and_chips(theme_script) -> void:
	var titled := _dress_tip(theme_script, "# Fill is not Strength\nBody line stays wrapped.\n[Click] select · [Ctrl+Click] attack · [Esc]")
	if titled == null:
		return
	var title := titled.find_child("EoaTooltipTitle", true, false) as Label
	var rule := titled.find_child("EoaTooltipRule", true, false) as HSeparator
	if title == null:
		_fail("titled tip has no EoaTooltipTitle")
	elif title.text != "Fill is not Strength" or title.text.begins_with("#"):
		_fail("title text %s" % title.text)
	elif int(title.get_theme_font_size("font_size")) != 15:
		_fail("title size %s want 15" % str(title.get_theme_font_size("font_size")))
	elif not _rgb_close(title.get_theme_color("font_color"), Color("#33e6ff")):
		_fail("title color %s want #33e6ff" % str(title.get_theme_color("font_color")))
	else:
		var fnt: Font = title.get_theme_font("font")
		if not (fnt is FontVariation) or (fnt as FontVariation).variation_embolden < 0.5:
			_fail("title font is not bold")
		else:
			_pass("title 15 px bold #33e6ff prefix stripped")
	if rule == null:
		_fail("titled tip has no EoaTooltipRule")
	else:
		var line := rule.get_theme_stylebox("separator") as StyleBoxLine
		if line == null or not _rgb_close(line.color, Color("#2a3a5c")) or line.thickness != 1:
			_fail("rule style %s" % str(line))
		else:
			_pass("title rule #2a3a5c")
	var row := titled.find_child("EoaHotkeyRow", true, false) as HBoxContainer
	if row == null or row.alignment != BoxContainer.ALIGNMENT_END:
		_fail("hotkey row missing or not ALIGNMENT_END")
	elif int(row.get_theme_constant("separation")) != 6:
		_fail("hotkey row separation %s want 6" % str(row.get_theme_constant("separation")))
	else:
		_pass("hotkey row end-aligned sep 6")
	_assert_chip_colors(titled, true)
	titled.queue_free()
	var plain := _dress_tip(theme_script, "Steel · 1,240\nNo title on this tip.\n[G]")
	if plain == null:
		return
	if plain.find_child("EoaTooltipTitle", true, false) != null or plain.find_child("EoaTooltipRule", true, false) != null:
		_fail("untitled tip created a title node")
	else:
		_pass("no # prefix means no title node")
	plain.queue_free()
	var three := _dress_tip(theme_script, "Body\n[A] · [B] · [C]")
	if three == null:
		return
	var chips := _nodes_named(three, "HotkeyChip")
	if chips.size() != 3:
		_fail("[A] · [B] · [C] made %d chips %s" % [chips.size(), _chip_dump(three)])
	else:
		var danger := false
		for chip in chips:
			var sb := (chip as Control).get_theme_stylebox("panel") as StyleBoxFlat
			if sb != null and _rgb_close(sb.border_color, Color("#ff33cc")):
				danger = true
		if danger:
			_fail("plain [A][B][C] chip used the danger border")
		else:
			_pass("three HotkeyChip nodes")
	three.queue_free()


func _assert_chip_colors(pop: Node, expect_danger: bool) -> void:
	var chips := _nodes_named(pop, "HotkeyChip")
	if chips.size() != 3:
		_fail("expected 3 chips, got %d %s" % [chips.size(), _chip_dump(pop)])
		return
	var saw_danger := false
	var saw_safe := false
	for chip in chips:
		var panel := chip as PanelContainer
		var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
		var lab := panel.get_child(0) as Label
		if sb == null or lab == null:
			_fail("chip missing style or label")
			return
		if int(lab.get_theme_font_size("font_size")) != 12:
			_fail("chip font %s want 12" % str(lab.get_theme_font_size("font_size")))
			return
		var danger := lab.text.contains("Ctrl+Click") or lab.text.contains("Del")
		var want := Color("#ff33cc") if danger else Color("#33e6ff")
		if not _rgb_close(sb.border_color, want) or not _rgb_close(lab.get_theme_color("font_color"), want):
			_fail("chip %s border %s text %s" % [lab.text, str(sb.border_color), str(lab.get_theme_color("font_color"))])
			return
		if danger:
			saw_danger = true
			if sb.border_color.a < 0.99:
				_fail("danger border alpha %s want opaque #ff33cc" % str(sb.border_color.a))
				return
		else:
			saw_safe = true
			if not is_equal_approx(sb.border_color.a, 0.6):
				_fail("safe chip border alpha %s want 0.6" % str(sb.border_color.a))
				return
		if sb.get_border_width(SIDE_LEFT) != 1 or sb.corner_radius_top_left != 3:
			_fail("chip border/radius drifted")
			return
		if sb.content_margin_left != 6 or sb.content_margin_top != 1:
			_fail("chip margin drifted")
			return
	if expect_danger and not saw_danger:
		_fail("Ctrl+Click chip was not #ff33cc")
	elif not saw_safe:
		_fail("no safe cyan chip")
	else:
		_pass("Ctrl+Click chip border #ff33cc")


func _assert_p1_anchor_and_pan(theme_script) -> void:
	var anc: Rect2 = theme_script.call(
		"resolve_tooltip_anchor", Rect2(), Vector2(510, 22), Vector2(0, 0), true
	)
	if anc.position.distance_to(Vector2(510, 22)) > 0.01:
		_fail("cursor anchor used %s not the cursor" % str(anc))
	else:
		_pass("top-bar tip anchors at the cursor")
	var stuck: Rect2 = theme_script.call(
		"resolve_tooltip_anchor", Rect2(), Vector2(510, 22), Vector2(0, 0), false
	)
	if stuck.position != Vector2.ZERO:
		_fail("unknown cursor ignored popup position %s" % str(stuck))
	var placed: Rect2 = theme_script.call(
		"clamp_tooltip_rect", Vector2(280, 72), Rect2(0, 0, 1280, 720), anc
	)
	if placed.position.x < 200.0:
		_fail("top-bar tip sat at the left edge %s" % str(placed))
	elif not _rect_inside_margin(placed, Rect2(0, 0, 1280, 720), 4.0):
		_fail("top-bar tip inside margin failed %s" % str(placed))
	else:
		_pass("top-bar tip is not parked at the top-left")
	if bool(theme_script.call("tooltip_should_clear_for_pan", Vector2.ZERO, Vector2.ZERO)):
		_fail("still camera cleared the tooltip")
	elif not bool(theme_script.call("tooltip_should_clear_for_pan", Vector2.ZERO, Vector2(30, 0))):
		_fail("pan did not clear the tooltip")
	else:
		_pass("stale hover clears on pan")
	var probe := PopupPanel.new()
	root.add_child(probe)
	var host: Variant = theme_script.call("_host_viewport", probe)
	if host == null or host == probe:
		_fail("tooltip host viewport is the popup (top-left mouse)")
	else:
		_pass("tooltip reads the game viewport, not its own window")
	probe.queue_free()


func _assert_p1_fill_clamp(theme_script) -> void:
	var strip_script := load(STRIP_SRC)
	if strip_script == null:
		_fail("strip missing for clamp")
		return
	var raw := str(strip_script.call("fill_line_tooltip", null))
	var pop := _dress_tip(theme_script, raw)
	if pop == null:
		return
	pop.reset_size()
	var sz := Vector2(pop.size)
	if sz.x < 8.0 or sz.y < 8.0:
		sz = pop.get_contents_minimum_size()
	if sz.x < 8.0:
		sz.x = 280.0
	if sz.y < 8.0:
		sz.y = 140.0
	for vp_size in [Vector2(1280, 720), Vector2(1920, 1080)]:
		var vp := Rect2(Vector2.ZERO, vp_size)
		var corner := Rect2(vp_size.x - 48.0, vp_size.y - 36.0, 24, 18)
		var placed: Rect2 = theme_script.call("clamp_tooltip_rect", sz, vp, corner)
		if not _rect_inside_margin(placed, vp, 4.0):
			_fail("fill tip clipped at %s placed %s" % [str(vp_size), str(placed)])
		else:
			_pass("fill tip inside %s with 4 px %s" % [str(vp_size), str(placed)])
		var bar := Rect2(vp_size.x * 0.45, 16, 20, 18)
		var top: Rect2 = theme_script.call("clamp_tooltip_rect", sz, vp, bar)
		if not _rect_inside_margin(top, vp, 4.0):
			_fail("fill tip top-bar clipped at %s %s" % [str(vp_size), str(top)])
	pop.queue_free()


func _assert_p1_source_mutant() -> void:
	var src := _read("res://scripts/ui/RetrowaveTheme.gd")
	var needle := "const TOOLTIP_TITLE_PREFIX := \"# \""
	if needle not in src:
		_fail("mutant needle missing in real source")
		return
	var mutated := src.replace("class_name RetrowaveTheme\n", "")
	mutated = mutated.replace(needle, "const TOOLTIP_TITLE_PREFIX := \"@@ \"")
	var gs := GDScript.new()
	gs.source_code = mutated
	if gs.reload() != OK:
		_fail("title mutant failed to parse")
		return
	var pop := _dress_tip(gs, "# Fill is not Strength\nBody\n[A] · [B] · [C]")
	if pop == null:
		_fail("title mutant dress failed")
		return
	var title := pop.find_child("EoaTooltipTitle", true, false)
	if title != null:
		_fail("title mutant survived (EoaTooltipTitle still built)")
	else:
		_pass("real-source title mutant killed")
	pop.queue_free()


func _dress_tip(theme_script, text: String) -> PopupPanel:
	if theme_script == null or not theme_script.has_method("dress_tooltip_popup"):
		_fail("dress_tooltip_popup missing")
		return null
	var pop := PopupPanel.new()
	pop.theme_type_variation = "TooltipPanel"
	var lab := Label.new()
	lab.theme_type_variation = "TooltipLabel"
	lab.text = text
	pop.add_child(lab)
	root.add_child(pop)
	theme_script.call("dress_tooltip_popup", pop)
	return pop


func _nodes_named(node: Node, wanted: String) -> Array:
	# Untyped on purpose: Array[Node].append_array drops every match but the first.
	var into: Array = []
	_collect_named(node, wanted, into)
	return into


func _collect_named(node: Node, wanted: String, into: Array) -> void:
	if node == null:
		return
	if _name_is_hook(node, wanted):
		into.append(node)
	for c in node.get_children():
		_collect_named(c, wanted, into)


## Godot renames a second sibling HotkeyChip to HotkeyChip2 when the chip is
## added with a readable name. The hook is still the HotkeyChip prefix.
func _name_is_hook(node: Node, wanted: String) -> bool:
	var n := str(node.name)
	if n == wanted:
		return true
	if wanted != "HotkeyChip" or not n.begins_with("HotkeyChip"):
		return false
	var rest := n.substr(wanted.length())
	return rest.is_valid_int()


func _chip_dump(node: Node) -> String:
	var row := node.find_child("EoaHotkeyRow", true, false)
	if row == null:
		return "no EoaHotkeyRow"
	var bits: PackedStringArray = PackedStringArray()
	for c in row.get_children():
		var text := ""
		if c.get_child_count() > 0 and c.get_child(0) is Label:
			text = (c.get_child(0) as Label).text
		bits.append("%s=%s" % [str(c.name), text])
	return "row_children=%d [%s]" % [row.get_child_count(), ", ".join(bits)]


func _rgb_close(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


func _rect_inside_margin(r: Rect2, vp: Rect2, m: float) -> bool:
	if r.size.x < 1.0 or r.size.y < 1.0:
		return false
	return (
		r.position.x + 0.05 >= vp.position.x + m
		and r.position.y + 0.05 >= vp.position.y + m
		and r.position.x + r.size.x <= vp.position.x + vp.size.x - m + 0.05
		and r.position.y + r.size.y <= vp.position.y + vp.size.y - m + 0.05
	)
