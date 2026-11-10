extends SceneTree

## SEARCH-HOTKEY-1 + NEXT-CHIP-LAYOUT.
## Item 1: a focused Search LineEdit (or any LineEdit) must not fire pause,
## speed, or map-mode hotkeys. Item 2: the NEXT war-goal box sits clear of
## Map Mode and the top bar; NEXT and Why are separate unclipped lines;
## an open inspector does not cover it.
##
## Fails on 5c1b541b (empty Search still toggles Space; digits 1–4 change
## speed; NEXT/Why share one box over Map Mode). Passes on this tip.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessSearchHotkey1Test.gd

const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 4

var _failures: int = 0
var _mr: Node = null
var _bar: Control = null
var _info: Panel = null


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.size = PLAY_SIZE
	await _case_search_hotkeys()
	await _case_next_chip_layout()
	var ok := _failures == 0
	print("HeadlessSearchHotkey1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSearchHotkey1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSearchHotkey1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSearchHotkey1Test: ", msg)


func _info_line(msg: String) -> void:
	print("  [INFO] HeadlessSearchHotkey1Test: ", msg)


func _frames(n: int) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1


func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	if a.size.x < 1.0 or a.size.y < 1.0 or b.size.x < 1.0 or b.size.y < 1.0:
		return false
	return a.grow(-0.5).intersects(b.grow(-0.5))


func _setup_map() -> bool:
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = scr.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	var map_ui := CanvasLayer.new()
	map_ui.name = "UI"
	_mr.add_child(map_ui)
	_info = Panel.new()
	_info.name = "InfoPanel"
	_info.visible = false
	_info.mouse_filter = Control.MOUSE_FILTER_STOP
	_info.size = Vector2(520, 360)
	_info.position = Vector2(12, 140)
	map_ui.add_child(_info)
	_mr.set("info_panel", _info)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.position = Vector2(400, 300)
	cam.enabled = true
	_mr.add_child(cam)
	root.add_child(_mr)
	cam.make_current()
	if not _mr.is_in_group("map_renderer"):
		_mr.add_to_group("map_renderer")
	return true


func _boot_top_bar() -> bool:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	layer.layer = 110
	root.add_child(layer)
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		_fail("TopInfoBar.tscn missing")
		return false
	var inst: Node = packed.instantiate()
	if inst == null or not (inst is Control):
		_fail("TopInfoBar instantiate failed")
		return false
	_bar = inst as Control
	_bar.name = "TopInfoBar"
	layer.add_child(_bar)
	await _frames(2)
	return true


func _search() -> Node:
	if _mr != null and _mr.has_method("ensure_live_search_chrome"):
		var hosted: Variant = _mr.call("ensure_live_search_chrome")
		if hosted is Node and is_instance_valid(hosted):
			return hosted as Node
	return root.find_child("MapProvinceSearch", true, false)


func _line() -> LineEdit:
	var search := _search()
	if search == null:
		return null
	return search.find_child("SearchLineEdit", true, false) as LineEdit


func _key(code: Key, pressed: bool) -> InputEventKey:
	var key := InputEventKey.new()
	key.device = 0
	key.keycode = code
	key.physical_keycode = code
	key.key_label = code
	key.pressed = pressed
	key.echo = false
	key.unicode = 0
	if pressed and code >= KEY_SPACE and code <= KEY_ASCIITILDE:
		key.unicode = code
	return key


func _dispatch_key(code: Key) -> void:
	var down := _key(code, true)
	var up := _key(code, false)
	if _bar != null:
		if _bar.has_method("_input"):
			_bar.call("_input", down)
		if _bar.has_method("_unhandled_input"):
			_bar.call("_unhandled_input", down)
	if _mr != null:
		if _mr.has_method("_input"):
			_mr.call("_input", down)
		if _mr.has_method("_unhandled_input"):
			_mr.call("_unhandled_input", down)
	root.push_input(down)
	root.push_input(up)


func _clock_snapshot() -> Dictionary:
	var paused := false
	var speed := 1
	if _bar != null:
		paused = bool(_bar.get("is_paused"))
		speed = int(_bar.get("current_speed"))
	var tm := root.get_node_or_null("TimeManager")
	if tm != null:
		if tm.has_method("is_paused"):
			paused = bool(tm.call("is_paused")) or paused
		if "paused" in tm:
			paused = bool(tm.get("paused")) or paused
		if "time_scale" in tm:
			speed = int(round(float(tm.get("time_scale"))))
	return {"paused": paused, "speed": speed}


func _set_clock(paused: bool, speed: int) -> void:
	if _bar != null:
		_bar.set("is_paused", paused)
		_bar.set("current_speed", speed)
	var tm := root.get_node_or_null("TimeManager")
	if tm != null:
		if tm.has_method("set_paused"):
			tm.call("set_paused", paused)
		elif "paused" in tm:
			tm.set("paused", paused)
		if tm.has_method("set_time_scale"):
			tm.call("set_time_scale", float(speed))
		elif "time_scale" in tm:
			tm.set("time_scale", float(speed))


func _case_search_hotkeys() -> void:
	print("SEARCH_HOTKEY_1 case=search_hotkeys")
	if not _setup_map():
		return
	if not await _boot_top_bar():
		return
	await _frames(2)
	var title := root.find_child("LivingTitleBoot", true, false)
	if title != null and is_instance_valid(title):
		title.set("_closed", true)
		title.name = "LivingTitleBootGone"
		title.free()
	if _mr.has_method("ensure_live_search_chrome"):
		_mr.call("ensure_live_search_chrome")
	await _frames(2)
	var line := _line()
	if line == null:
		_fail("SearchLineEdit missing")
		return
	line.focus_mode = Control.FOCUS_ALL
	line.editable = true
	line.grab_focus()
	await _frames(2)
	var fo: Control = root.get_viewport().gui_get_focus_owner() if root.get_viewport() != null else null
	if not line.has_focus() and fo != line:
		_fail("could not focus SearchLineEdit")
		return
	_set_clock(true, 1)
	await _frames(1)
	var before := _clock_snapshot()
	var mode_before := str(_mr.get("current_map_mode"))
	_info_line("focused search before paused=%s speed=%s mode=%s" % [str(before.get("paused")), str(before.get("speed")), mode_before])
	var query := "berlin"
	var i := 0
	while i < query.length():
		_dispatch_key(query.unicode_at(i) as Key)
		i += 1
	for code in [KEY_SPACE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_EQUAL, KEY_MINUS, KEY_U, KEY_L, KEY_F2, KEY_PERIOD]:
		_dispatch_key(code as Key)
	await _frames(2)
	var after := _clock_snapshot()
	var mode_after := str(_mr.get("current_map_mode"))
	_info_line("after keys paused=%s speed=%s mode=%s text=%s focus=%s" % [
		str(after.get("paused")), str(after.get("speed")), mode_after, line.text, str(line.has_focus())
	])
	if bool(after.get("paused")) != bool(before.get("paused")):
		_fail("search focus changed pause (%s -> %s)" % [str(before.get("paused")), str(after.get("paused"))])
	elif int(after.get("speed")) != int(before.get("speed")):
		_fail("search focus changed speed (%s -> %s)" % [str(before.get("speed")), str(after.get("speed"))])
	elif mode_after != mode_before:
		_fail("search focus changed map mode (%s -> %s)" % [mode_before, mode_after])
	else:
		_pass("focused search: pause/speed/map-mode unchanged after query+Space+digits")
	var paused_before_esc := bool(_clock_snapshot().get("paused"))
	_dispatch_key(KEY_ESCAPE)
	await _frames(2)
	if bool(_clock_snapshot().get("paused")) != paused_before_esc:
		_fail("Esc while search focused changed pause")
	else:
		_pass("Esc while search focused did not unpause")


func _toolbar() -> Control:
	if _mr == null:
		return null
	var tb: Variant = _mr.get("_map_mode_toolbar")
	return tb as Control


func _next_chip() -> Button:
	if _mr == null:
		return null
	var ui := _mr.get_node_or_null("UI")
	if ui == null:
		return null
	return ui.get_node_or_null("PlayNextHookChip") as Button


func _text_uncipped(ctrl: Control, text: String, fallback_px: int) -> bool:
	if ctrl == null:
		return false
	if ctrl is Label:
		var lab := ctrl as Label
		if lab.clip_text:
			return false
		if lab.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
			return false
	if ctrl is Button:
		var btn := ctrl as Button
		if btn.clip_text:
			return false
		if btn.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
			return false
	var font: Font = ctrl.get_theme_font("font")
	var fs := ctrl.get_theme_font_size("font_size")
	if fs <= 0:
		fs = fallback_px
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		return true
	if ctrl is Label and (ctrl as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
		return true
	if ctrl is Button and (ctrl as Button).autowrap_mode != TextServer.AUTOWRAP_OFF:
		return true
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return tw + 8.0 <= ctrl.size.x + 2.0


func _paint_war_goal(player: String, foe: String, foe_name: String, pid: int) -> void:
	var lm := root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", player)
	var hook: GDScript = load("res://scripts/ui/PlayNextHook.gd") as GDScript
	if hook != null and hook.has_method("reset_goal_lock_for_test"):
		hook.call("reset_goal_lock_for_test")
	var rec := {
		"ok": true,
		"action": "justify",
		"label": "Justify war on %s" % foe_name,
		"hint": "Justify a claim before declaring war",
		"source": "war_goal",
		"target_tag": foe,
		"goal_name": foe_name,
		"to_id": pid,
		"goal_score": 1.0,
	}
	if hook != null and hook.has_method("stick_chip_goal"):
		hook.call("stick_chip_goal", rec, 0)
	if _mr.has_method("refresh_next_hook_after_living_begin"):
		_mr.call("refresh_next_hook_after_living_begin")
	else:
		_mr.call("_refresh_next_hook_chip")
	var chip := _next_chip()
	if chip != null:
		chip.set_meta("play_next_rec", rec.duplicate(true))
		chip.text = "NEXT · %s" % str(rec.get("label"))
	_mr.call("_paint_goal_chip_detail", rec, true)
	if _mr.has_method("_layout_map_ui"):
		_mr.call("_layout_map_ui")
	if _mr.has_method("_fit_next_hook_chip"):
		_mr.call("_fit_next_hook_chip")


func _assert_chip_layout(player: String, foe_name: String, inspector_open: bool) -> void:
	var chip := _next_chip()
	if chip == null or not chip.visible:
		_fail("%s NEXT chip missing/hidden" % player)
		return
	var next_lbl := chip.get_node_or_null("GoalNext") as Label
	var why := chip.get_node_or_null("GoalWhy") as Label
	if next_lbl == null:
		_fail("%s GoalNext label missing — NEXT and Why share one box" % player)
		return
	if why == null or not why.visible:
		_fail("%s GoalWhy label missing" % player)
		return
	await _frames(2)
	var chip_r := chip.get_global_rect()
	var next_r := next_lbl.get_global_rect()
	var why_r := why.get_global_rect()
	var bar_r := _bar.get_global_rect() if _bar != null else Rect2()
	var tb := _toolbar()
	var tb_r := Rect2()
	if tb != null:
		if tb.has_method("get_live_panel_rect"):
			var live: Variant = tb.call("get_live_panel_rect")
			if live is Rect2:
				tb_r = live as Rect2
			else:
				tb_r = tb.get_global_rect()
		else:
			tb_r = tb.get_global_rect()
	_info_line("%s inspector=%s chip=%s next=%s why=%s toolbar=%s bar=%s text='%s' why_text='%s'" % [
		player, str(inspector_open), str(chip_r), str(next_r), str(why_r), str(tb_r), str(bar_r), chip.text, why.text
	])
	var blob := "%s %s %s" % [chip.text, next_lbl.text, why.text]
	if blob.find(foe_name) < 0:
		_fail("%s NEXT text missing target '%s' (got '%s')" % [player, foe_name, blob])
		return
	if _rects_overlap(chip_r, bar_r):
		_fail("%s NEXT box %s intersects top bar %s" % [player, str(chip_r), str(bar_r)])
		return
	if _rects_overlap(chip_r, tb_r):
		_fail("%s NEXT box %s intersects Map Mode %s" % [player, str(chip_r), str(tb_r)])
		return
	if _rects_overlap(next_r, why_r):
		_fail("%s NEXT label %s intersects Why %s" % [player, str(next_r), str(why_r)])
		return
	if not _text_uncipped(next_lbl, str(next_lbl.text), 15) or not _text_uncipped(why, str(why.text), 12):
		_fail("%s NEXT/Why text is clipped" % player)
		return
	if inspector_open and _info != null and _info.visible:
		var ip_r := _info.get_global_rect()
		if _rects_overlap(chip_r, ip_r) and chip.z_index <= _info.z_index:
			_fail("%s NEXT box %s covered by inspector %s" % [player, str(chip_r), str(ip_r)])
			return
	_pass("%s NEXT layout clear of Map Mode/top bar; Why separate; target='%s'" % [player, foe_name])


func _case_next_chip_layout() -> void:
	print("SEARCH_HOTKEY_1 case=next_chip_layout")
	if _mr == null:
		if not _setup_map():
			return
		if not await _boot_top_bar():
			return
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm != null and boot != null:
		if not bool(boot.call("boot", mm, sm, "GER")):
			_fail("campaign boot failed")
			return
	var war: GDScript = load("res://scripts/core/WarStateDomain.gd") as GDScript
	if war != null:
		war.call("reset_for_test")
		if war.has_method("clear_rule_overrides"):
			war.clear_rule_overrides()
	if _mr.get("_map_mode_toolbar") == null and _mr.has_method("_setup_player_map_ux"):
		_mr.call("_setup_player_map_ux")
	await _frames(FLUSH_FRAMES)
	if _toolbar() == null:
		_fail("MapModeToolbar missing")
		return
	var chrome: GDScript = load("res://scripts/ui/CampaignWarChrome.gd") as GDScript
	var cases: Array[Dictionary] = [
		{"player": "USA", "foe": "JAP", "pid": 902598},
		{"player": "SOV", "foe": "POL", "pid": 711054},
		{"player": "ENG", "foe": "GER", "pid": 710300},
		{"player": "GER", "foe": "FRA", "pid": 710739},
	]
	for row in cases:
		var player := str(row.get("player"))
		var foe := str(row.get("foe"))
		var name := foe
		if chrome != null and chrome.has_method("display_name_for_tag"):
			var shown := str(chrome.call("display_name_for_tag", foe)).strip_edges()
			if not shown.is_empty():
				name = shown
		_info.visible = false
		_paint_war_goal(player, foe, name, int(row.get("pid")))
		await _frames(2)
		await _assert_chip_layout(player, name, false)
		_info.visible = true
		_info.z_index = 40
		if _mr.has_method("_layout_map_ui"):
			_mr.call("_layout_map_ui")
		if _mr.has_method("_fit_next_hook_chip"):
			_mr.call("_fit_next_hook_chip")
		await _frames(2)
		await _assert_chip_layout(player, name, true)
		_info.visible = false
