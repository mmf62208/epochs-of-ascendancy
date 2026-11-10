extends SceneTree

## SEARCH-HOTKEY-1 + NEXT-CHIP-LAYOUT (r2: click-focus + RtT AAR clear).
## Item 1: a focused Search LineEdit (or any LineEdit) must not fire pause,
## speed, or map-mode hotkeys. A left click on the Search box must actually
## focus the LineEdit before the next key. Item 2: the NEXT war-goal box sits
## clear of Map Mode and the top bar; a leftover land AAR must not survive
## Return to Title into a fresh Begin.
##
## Fails on 5c1b541b (empty Search still toggles Space; digits 1–4 change
## speed; NEXT/Why share one box over Map Mode). r2 click-focus / Bytomski
## leftover fails on e1f1f813 and passes on this tip.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessSearchHotkey1Test.gd

const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 4
const KINGSTON := 903045
const BYTOMSKI_PID := 711082

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
	await _case_search_click_focus()
	await _case_next_chip_layout()
	await _case_next_chip_rtt_aar()
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


func _inspector_pid() -> int:
	if _mr == null:
		return -1
	if "selected_province_id" in _mr:
		return int(_mr.get("selected_province_id"))
	return -1


func _inspector_open() -> bool:
	if _info != null and _info.visible:
		return true
	if _mr == null:
		return false
	var ip: Variant = _mr.get("info_panel")
	return ip is CanvasItem and (ip as CanvasItem).visible


func _cc_up() -> bool:
	var mm := root.get_node_or_null("MainMenu")
	if mm == null or not is_instance_valid(mm) or mm.is_queued_for_deletion():
		return false
	if str(mm.name) != "MainMenu":
		return false
	if bool(mm.get("_closing")):
		return false
	return true


func _close_cc() -> void:
	var mm := root.get_node_or_null("MainMenu")
	if mm != null and is_instance_valid(mm) and mm.has_method("_force_close") and not bool(mm.get("_closing")):
		mm.call("_force_close")


func _hide_inspector() -> void:
	if _info != null:
		_info.visible = false
	if _mr == null:
		return
	var ip: Variant = _mr.get("info_panel")
	if ip is CanvasItem and is_instance_valid(ip):
		(ip as CanvasItem).visible = false
	if "selected_province_id" in _mr:
		_mr.set("selected_province_id", -1)


func _mouse_at(pt: Vector2, pressed: bool) -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.device = 0
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pt
	mb.global_position = pt
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return mb


func _click_at(pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(pt)
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = pt
	motion.global_position = pt
	motion.relative = Vector2(1, 1)
	root.push_input(motion)
	var down := _mouse_at(pt, true)
	var up := _mouse_at(pt, false)
	if _mr != null:
		if _mr.has_method("_input"):
			_mr.call("_input", down)
		if _mr.has_method("_focus_search_from_point"):
			_mr.call("_focus_search_from_point", pt)
	var search := _search()
	if search != null and search.has_method("_gui_input"):
		search.call("_gui_input", down)
	root.push_input(down)
	if _mr != null and _mr.has_method("_input"):
		_mr.call("_input", up)
	root.push_input(up)


## Left click on the Search chrome (LineEdit or padding), not Go / results.
func _click_search_box() -> LineEdit:
	var line := _line()
	var search := _search()
	if line == null or search == null or not (search is Control):
		_fail("Search chrome missing for click")
		return null
	var sr := search as Control
	# Chrome padding / grow-hit, not the LineEdit body, so a leftover
	# `_suppress_line_grab_frame` cannot be rescued by native LineEdit grab.
	var chrome_pt := sr.get_global_rect().position + Vector2(-4.0, maxf(8.0, sr.size.y * 0.5))
	_click_at(chrome_pt)
	await process_frame
	return line


func _assert_click_owns_keys(label: String) -> void:
	_close_cc()
	_hide_inspector()
	_set_clock(true, 1)
	var grabber := _search()
	if grabber != null and grabber.has_method("_release_line_focus"):
		grabber.call("_release_line_focus")
	var line := await _click_search_box()
	if line == null:
		return
	var fo: Control = root.get_viewport().gui_get_focus_owner() if root.get_viewport() != null else null
	if not line.has_focus() and fo != line:
		_fail("%s: Search click did not focus SearchLineEdit (focus=%s owner=%s)" % [label, str(line.has_focus()), str(fo)])
		return
	var before := _clock_snapshot()
	var pid_before := _inspector_pid()
	var insp_before := _inspector_open()
	for code in [KEY_1, KEY_2]:
		_dispatch_key(code as Key)
	await _frames(2)
	var after := _clock_snapshot()
	if int(after.get("speed")) != int(before.get("speed")) or bool(after.get("paused")) != bool(before.get("paused")):
		_fail("%s: digits after Search click changed clock pause=%s→%s speed=%s→%s" % [
			label, str(before.get("paused")), str(after.get("paused")),
			str(before.get("speed")), str(after.get("speed"))
		])
		return
	if (not insp_before) and _inspector_open():
		_fail("%s: digits after Search click opened the inspector pid=%s" % [label, str(_inspector_pid())])
		return
	if _inspector_pid() != pid_before and _inspector_pid() > 0 and pid_before > 0:
		_fail("%s: digits after Search click changed inspector %s → %s" % [label, str(pid_before), str(_inspector_pid())])
		return
	_pass("%s: Search click focused the line; digits did not change speed or open inspector" % label)


func _kingston_search() -> void:
	var search := _search()
	var line := _line()
	if search == null or line == null:
		return
	line.text = "kingston"
	if search.has_method("submit_from_live_ui"):
		search.call("submit_from_live_ui", "kingston")
	elif search.has_method("_on_submit"):
		search.call("_on_submit", "kingston")


func _begin_as(tag: String) -> bool:
	_free_title(_find_title())
	var title := _make_title()
	await process_frame
	await process_frame
	await process_frame
	var btns: Variant = title.get("_nation_btns")
	if btns is Dictionary:
		var nbtn: Button = (btns as Dictionary).get(tag) as Button
		if nbtn != null:
			nbtn.pressed.emit()
			await process_frame
	var begin: Button = title.get("_begin_btn") as Button
	if begin == null:
		_free_title(title)
		return false
	begin.pressed.emit()
	for _i in 12:
		await process_frame
		if title == null or not is_instance_valid(title) or bool(title.get("_closed")):
			return true
	return bool(title.get("_closed")) if is_instance_valid(title) else true


func _return_to_title() -> bool:
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	_free_menu()
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return false
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	await process_frame
	await process_frame
	await process_frame
	var ret: Button = null
	for n in menu.find_children("*", "Button", true, false):
		if n is Button and str((n as Button).get_meta("eoa_cc_action", "")) == "return_to_main":
			ret = n as Button
			break
	if ret == null:
		_free_menu()
		return false
	ret.pressed.emit()
	var closed := not is_instance_valid(menu) or menu.is_queued_for_deletion()
	await process_frame
	await process_frame
	return closed or not is_instance_valid(menu)


func _make_title() -> Node:
	_free_title(_find_title())
	var scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	var title: Node = scr.new() as Node
	title.name = "LivingTitleBoot"
	root.add_child(title)
	return title


func _find_title() -> Node:
	return root.find_child("LivingTitleBoot", true, false)


func _free_title(title: Node) -> void:
	if title == null or not is_instance_valid(title):
		return
	if title.get_parent() != null:
		title.get_parent().remove_child(title)
	title.free()


func _free_menu() -> void:
	var menu := root.get_node_or_null("MainMenu")
	if menu == null or not is_instance_valid(menu):
		return
	if menu.has_method("_release_clock_lock"):
		menu.call("_release_clock_lock")
	var parent := menu.get_parent()
	if parent != null:
		parent.remove_child(menu)
	menu.free()


func _dummy_title_scene() -> PackedScene:
	var title := Node.new()
	title.name = "TitleIdle"
	var packed := PackedScene.new()
	packed.pack(title)
	title.free()
	return packed


func _inject_bytomski_aar() -> bool:
	var bm := root.get_node_or_null("BattleManager")
	if bm == null:
		_fail("BattleManager missing")
		return false
	bm.set("_last_land_aar", {
		"winner": "attacker",
		"place": "Gdański",
		"next_pid": BYTOMSKI_PID,
		"next_place": "Bytomski",
		"line": "Battle ended at Gdański",
		"fid": "search_hotkey1_aar",
		"from_id": KINGSTON,
		"tag": "GER",
	})
	return true


func _chip_text() -> String:
	var chip := _next_chip()
	if chip == null:
		return ""
	return str(chip.text)


func _case_search_click_focus() -> void:
	print("SEARCH_HOTKEY_1 case=search_click_focus")
	if _mr == null:
		if not _setup_map():
			return
		if not await _boot_top_bar():
			return
	if _mr.has_method("ensure_live_search_chrome"):
		_mr.call("ensure_live_search_chrome")
	await _frames(2)
	var title := root.find_child("LivingTitleBoot", true, false)
	if title != null and is_instance_valid(title):
		title.set("_closed", true)
	# Same-frame leftover after Go / result pick (Play ENG-after-Kingston).
	var search := _search()
	if search != null and search.has_method("_release_line_focus"):
		search.call("_release_line_focus")
	await _assert_click_owns_keys("after_release")
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm != null and boot != null:
		boot.call("boot", mm, sm, "GER")
	if not await _begin_as("SOV"):
		_fail("SOV Begin failed")
		return
	if _mr.has_method("ensure_live_search_chrome"):
		_mr.call("ensure_live_search_chrome")
	await _assert_click_owns_keys("sov_begin")
	if not await _begin_as("ENG"):
		_fail("ENG Begin failed")
		return
	if _mr.has_method("ensure_live_search_chrome"):
		_mr.call("ensure_live_search_chrome")
	_kingston_search()
	await _assert_click_owns_keys("eng_after_kingston")
	_close_cc()
	_hide_inspector()
	_set_clock(true, 1)
	await _frames(1)
	var line := await _click_search_box()
	if line == null:
		return
	line.text = ""
	var paused_before := bool(_clock_snapshot().get("paused"))
	_dispatch_key(KEY_ESCAPE)
	await _frames(2)
	var fo: Control = root.get_viewport().gui_get_focus_owner() if root.get_viewport() != null else null
	if line.has_focus() or fo == line:
		_fail("Esc after Search click left SearchLineEdit focused")
		return
	if _cc_up():
		_fail("the Esc that unfocused Search also opened Paused")
		return
	if bool(_clock_snapshot().get("paused")) != paused_before:
		_fail("Esc after Search click changed pause")
		return
	_pass("one Esc after Search click released focus and did not open Paused")
	_dispatch_key(KEY_ESCAPE)
	await _frames(4)
	if not _cc_up():
		_fail("Esc with Search unfocused did not open Paused")
		return
	_pass("later Esc with Search unfocused opened Paused")
	_close_cc()


func _case_next_chip_rtt_aar() -> void:
	print("SEARCH_HOTKEY_1 case=next_chip_rtt_aar")
	if _mr == null:
		_fail("MapRenderer missing for AAR RtT")
		return
	var hook: GDScript = load("res://scripts/ui/PlayNextHook.gd") as GDScript
	if hook == null:
		_fail("PlayNextHook missing")
		return
	if not _inject_bytomski_aar():
		return
	var rec: Dictionary = hook.call("recommend", "GER")
	var rec_label := str(rec.get("label", ""))
	if rec_label.find("Bytomski") < 0:
		_fail("injected AAR did not rank as Press Bytomski next (got '%s')" % rec_label)
		return
	_pass("injected AAR ranks as '%s'" % rec_label)
	if _mr.has_method("refresh_next_hook_after_living_begin"):
		_mr.call("refresh_next_hook_after_living_begin")
	elif _mr.has_method("_refresh_next_hook_chip"):
		_mr.call("_refresh_next_hook_chip")
	await _frames(2)
	var wants: Array[Dictionary] = [
		{"tag": "USA", "needle": "Japan"},
		{"tag": "SOV", "needle": "Poland"},
		{"tag": "ENG", "needle": "English Channel"},
	]
	for row in wants:
		var tag := str(row.get("tag"))
		var needle := str(row.get("needle"))
		if not _inject_bytomski_aar():
			return
		if not await _return_to_title():
			_fail("Return to Title before Begin %s did not fire" % tag)
			return
		if not await _begin_as(tag):
			_fail("Begin %s after RtT failed" % tag)
			return
		await _frames(3)
		if _mr.has_method("refresh_next_hook_after_living_begin"):
			_mr.call("refresh_next_hook_after_living_begin")
		await _frames(2)
		var shown := _chip_text()
		if shown.find("Bytomski") >= 0 or shown.find("Press Bytomski") >= 0:
			_fail("Begin %s after GER AAR RtT kept leftover '%s'" % [tag, shown])
			return
		if shown.find(needle) < 0:
			_fail("Begin %s after RtT want '%s' in '%s'" % [tag, needle, shown])
			return
		_pass("after RtT Begin %s: %s" % [tag, shown])
