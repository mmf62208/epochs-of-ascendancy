extends SceneTree

## INPUT-POLISH-1. Input-routing nits only.
## search_digits_no_leak must FAIL on 33c0722f (a focus drop between digits
## leaks KEY_3 into TopInfoBar speed and the box loses the tail) and PASS
## once a Search typing session keeps the digits and the clock.
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     --resolution 1280x800 -s res://scripts/core/HeadlessInputPolish1Test.gd

const PLAY_SIZE := Vector2i(1280, 800)
## Uelzen. Seeded under the click so the first post-prompt pick has a known pid.
const GER_PID := 710382
const PROMPT_HOVER := Vector2(40, 700)
const PROMPT_CLICK := Vector2(180, 620)

var _failures: int = 0
var _mr: Node = null
var _bar: Control = null
var _info: Panel = null
var _cam: Camera2D = null
var _saved_pick_grid: Variant = null
var _saved_centroids: Dictionary = {}
var _centroids_saved: bool = false


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
	await _case_search_digits_no_leak()
	await _case_load_confirm_quick_click()
	await _case_load_confirm_three_clicks()
	await _case_prompt_dismiss_first_click()
	await _case_prompt_dismiss_wheel_zoom()
	var ok := _failures == 0
	print("HeadlessInputPolish1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessInputPolish1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessInputPolish1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessInputPolish1Test: ", msg)


func _info_line(msg: String) -> void:
	print("  [INFO] HeadlessInputPolish1Test: ", msg)


func _frames(n: int) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1


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


## Real viewport path only. One push_input per edge: parse_input_event as well
## delivers the same key again and the box would read 950950.
## Do not call TopInfoBar._unhandled_input by hand — a handled Search key
## must never reach the speed hotkeys.
func _push_key(code: Key) -> void:
	var down := _key(code, true)
	var up := _key(code, false)
	if root != null:
		root.push_input(down)
		root.push_input(up)


func _clock_snapshot() -> Dictionary:
	var paused := true
	var speed := 1
	if _bar != null:
		paused = bool(_bar.get("is_paused"))
		speed = int(_bar.get("current_speed"))
	var tm := root.get_node_or_null("TimeManager")
	if tm != null:
		if "paused" in tm:
			paused = bool(tm.get("paused"))
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


func _mouse_at(pt: Vector2, pressed: bool) -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.device = 0
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pt
	mb.global_position = pt
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return mb


## Same Search click as HeadlessSearchHotkey1Test._click_search_box:
## chrome padding, not the LineEdit body, so focus_for_typing(true) runs.
func _click_search_box() -> LineEdit:
	var line := _line()
	var search := _search()
	if line == null or search == null or not (search is Control):
		_fail("Search chrome missing for click")
		return null
	var sr := search as Control
	var chrome_pt := sr.get_global_rect().position + Vector2(-4.0, maxf(8.0, sr.size.y * 0.5))
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(chrome_pt)
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = chrome_pt
	motion.global_position = chrome_pt
	motion.relative = Vector2(1, 1)
	root.push_input(motion)
	var down := _mouse_at(chrome_pt, true)
	var up := _mouse_at(chrome_pt, false)
	if _mr != null:
		if _mr.has_method("_input"):
			_mr.call("_input", down)
		if _mr.has_method("_focus_search_from_point"):
			_mr.call("_focus_search_from_point", chrome_pt)
	if search.has_method("_gui_input"):
		search.call("_gui_input", down)
	root.push_input(down)
	if _mr != null and _mr.has_method("_input"):
		_mr.call("_input", up)
	root.push_input(up)
	await process_frame
	return line


func _open_inspector() -> void:
	if _info != null:
		_info.visible = true
		_info.mouse_filter = Control.MOUSE_FILTER_STOP
		_info.z_index = 40
		_info.position = Vector2(12, 140)
		_info.size = Vector2(520, 360)
	if _mr != null and "selected_province_id" in _mr:
		_mr.set("selected_province_id", 710300)
	if _mr != null and _mr.has_method("_bring_info_panel_to_front"):
		_mr.call("_bring_info_panel_to_front")
	if _mr != null and _mr.has_method("_layout_map_ui"):
		_mr.call("_layout_map_ui")


func _case_search_digits_no_leak() -> void:
	print("INPUT_POLISH_1 case=search_digits_no_leak")
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
	_set_clock(true, 1)
	var supply_before := bool(_mr.get("supply_mode"))
	var line := await _click_search_box()
	if line == null:
		return
	await _frames(1)
	var fo: Control = root.get_viewport().gui_get_focus_owner() if root.get_viewport() != null else null
	if not line.has_focus() and fo != line:
		_fail("search_digits_no_leak: Search click did not focus the line (focus=%s owner=%s)" % [str(line.has_focus()), str(fo)])
		return
	line.text = ""
	# Click-focus sticks for this frame and the next. Type the head while it holds.
	for ch in ["9", "5", "0"]:
		_push_key(ch.unicode_at(0) as Key)
	await _frames(3)
	_info_line("after head text='%s' focus=%s" % [line.text, str(line.has_focus())])
	if line.text != "950":
		_fail("search_digits_no_leak: head digits did not land before the drop (text='%s')" % line.text)
		return
	# Play drop: deferred map release, TopInfoBar rehost, inspector layout.
	_mr.call_deferred("_release_search_focus")
	if _bar != null and _bar.has_method("host_map_search_chrome"):
		var search := _search()
		if search is Control:
			_bar.call("host_map_search_chrome", search)
	_open_inspector()
	await _frames(2)
	fo = root.get_viewport().gui_get_focus_owner() if root.get_viewport() != null else null
	_info_line("after forced drop text='%s' focus=%s owner=%s" % [line.text, str(line.has_focus()), str(fo)])
	# Stolen caret (reparent / release). The session must put the tail back.
	var vp_drop: Viewport = root.get_viewport()
	if vp_drop != null:
		vp_drop.gui_release_focus()
	line.release_focus()
	await _frames(1)
	var before := _clock_snapshot()
	for ch2 in ["3", "3", "7"]:
		_push_key(ch2.unicode_at(0) as Key)
		await _frames(1)
	await _frames(2)
	var after := _clock_snapshot()
	var supply_after := bool(_mr.get("supply_mode"))
	_info_line("tail text='%s' paused %s→%s speed %s→%s supply %s→%s" % [
		line.text,
		str(before.get("paused")), str(after.get("paused")),
		str(before.get("speed")), str(after.get("speed")),
		str(supply_before), str(supply_after),
	])
	if line.text != "950337":
		_fail("search_digits_no_leak: box text '%s' != 950337" % line.text)
		return
	if bool(after.get("paused")) != true or int(after.get("speed")) != int(before.get("speed")):
		_fail("search_digits_no_leak: clock leaked paused=%s speed=%s→%s" % [
			str(after.get("paused")), str(before.get("speed")), str(after.get("speed"))
		])
		return
	if supply_after != supply_before:
		_fail("search_digits_no_leak: supply mode toggled %s→%s" % [str(supply_before), str(supply_after)])
		return
	_pass("search_digits_no_leak: 950337 landed, clock stayed paused, supply unchanged")


func _load_count() -> int:
	var slm := root.get_node_or_null("SaveLoadManager")
	if slm == null:
		return -1
	return int(slm.get("eoa_load_apply_count"))


func _write_min_quicksave() -> bool:
	var slm := root.get_node_or_null("SaveLoadManager")
	if slm == null or not slm.has_method("get_save_path"):
		_fail("SaveLoadManager missing")
		return false
	var path := str(slm.call("get_save_path", "quicksave"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write quicksave at %s" % path)
		return false
	f.store_string("{\"save_version\":2,\"metadata\":{\"slot\":\"quicksave\",\"player_tag\":\"GER\"}}\n")
	f.close()
	return true


func _open_paused_load_confirm() -> Button:
	if _bar == null or not _bar.has_method("open_command_center_stay"):
		_fail("TopInfoBar missing for Paused")
		return null
	# Stay, do not toggle. A failed Load leaves Paused up; a second
	# _on_menu_pressed would close it.
	_bar.call("open_command_center_stay")
	await _frames(3)
	var menu := root.get_node_or_null("MainMenu")
	if menu == null or not menu.has_method("_open_load_confirm"):
		_fail("Paused MainMenu did not open")
		return null
	menu.call("_open_load_confirm", "quicksave")
	await _frames(2)
	var load_b := menu.find_child("BtnLoad", true, false) as Button
	if load_b == null:
		_fail("BtnLoad missing")
		return null
	var rect := load_b.get_global_rect()
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		_fail("BtnLoad has no rect %s" % str(rect))
		return null
	var consumes := false
	if _mr != null and _mr.has_method("_cc_chrome_consumes_point"):
		consumes = bool(_mr.call("_cc_chrome_consumes_point", rect.get_center()))
	_info_line("BtnLoad center=%s rect=%s action_mode=%s chrome_consumes=%s" % [
		str(rect.get_center()), str(rect), str(load_b.action_mode), str(consumes)
	])
	return load_b


## Press and release in the same call, no frame between them. A release-mode
## button whose release MapRenderer eats never emits pressed.
func _click_same_frame(pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(pt)
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = pt
	motion.global_position = pt
	motion.relative = Vector2(1, 0)
	root.push_input(motion)
	var down := _mouse_at(pt, true)
	var up := _mouse_at(pt, false)
	root.push_input(down)
	root.push_input(up)


func _confirm_open() -> bool:
	var menu := root.get_node_or_null("MainMenu")
	if menu == null or not is_instance_valid(menu):
		return false
	if menu.has_method("_confirm_visible"):
		return bool(menu.call("_confirm_visible"))
	return menu.find_child("LoadUnsavedConfirm", true, false) != null


func _case_load_confirm_quick_click() -> void:
	print("INPUT_POLISH_1 case=load_confirm_quick_click")
	if _mr == null and not _setup_map():
		return
	if _bar == null and not await _boot_top_bar():
		return
	if not _write_min_quicksave():
		return
	var before := _load_count()
	var load_b := await _open_paused_load_confirm()
	if load_b == null:
		return
	_click_same_frame(load_b.get_global_rect().get_center())
	await _frames(3)
	var after := _load_count()
	var open := _confirm_open()
	_info_line("quick click loads %s→%s confirm_open=%s" % [str(before), str(after), str(open)])
	if after != before + 1:
		_fail("load_confirm_quick_click: expected one load apply, got %s→%s" % [str(before), str(after)])
		return
	if open:
		_fail("load_confirm_quick_click: confirm stayed open after Load")
		return
	_pass("load_confirm_quick_click: one load apply and confirm closed")


func _case_load_confirm_three_clicks() -> void:
	print("INPUT_POLISH_1 case=load_confirm_three_clicks")
	if not _write_min_quicksave():
		return
	var before := _load_count()
	var load_b := await _open_paused_load_confirm()
	if load_b == null:
		return
	var pt := load_b.get_global_rect().get_center()
	# Three quick clicks before the frame ends, so a queued second press can
	# still see the button (queue_free has not run).
	_click_same_frame(pt)
	_click_same_frame(pt)
	_click_same_frame(pt)
	await _frames(3)
	var after := _load_count()
	_info_line("three clicks loads %s→%s confirm_open=%s" % [str(before), str(after), str(_confirm_open())])
	if after != before + 1:
		_fail("load_confirm_three_clicks: expected exactly one load, got %s→%s" % [str(before), str(after)])
		return
	_pass("load_confirm_three_clicks: three quick clicks applied one load")


func _close_command_center() -> void:
	var menu := root.get_node_or_null("MainMenu")
	if menu != null and is_instance_valid(menu) and menu.has_method("_force_close"):
		menu.call("_force_close")
	await _frames(2)
	if _mr != null:
		_mr.set("_cc_map_press_latch", false)
		_mr.set("_chrome_hold_swallowed", false)


func _wire_inspector_labels() -> void:
	if _info == null or _mr == null:
		return
	for extra_name in [
		"info_name", "info_owner", "info_population", "info_terrain", "info_factories",
		"info_dev", "info_resources", "info_core", "info_special", "info_logistics",
		"info_combat", "info_national",
	]:
		if _mr.get(extra_name) != null:
			continue
		var extra := Label.new()
		extra.name = extra_name
		_info.add_child(extra)
		_mr.set(extra_name, extra)


func _seed_uelzen(screen_pt: Vector2) -> bool:
	if _mr == null:
		_fail("MapRenderer missing for Uelzen seed")
		return false
	_cam = _mr.get_node_or_null("MapCamera") as Camera2D
	if _cam == null:
		_fail("MapCamera missing")
		return false
	_cam.make_current()
	_cam.force_update_transform()
	var world_under: Vector2 = _cam.get_canvas_transform().affine_inverse() * screen_pt
	# load() so this -s script does not compile-depend on Province (GameData).
	var prov_scr: Script = load("res://scripts/data/Province.gd") as Script
	if prov_scr == null:
		_fail("Province.gd missing")
		return false
	var prov: Object = prov_scr.new()
	if prov == null:
		_fail("Province create failed")
		return false
	prov.set("id", GER_PID)
	prov.set("name", "Uelzen")
	prov.set("owner_tag", "GER")
	prov.set("controller_tag", "GER")
	prov.set("terrain", "plains")
	prov.set("is_sea", false)
	prov.set("domain", "land")
	if "provinces" in _mr:
		_mr.provinces[GER_PID] = prov
	if "province_centroids" in _mr:
		_mr.province_centroids[GER_PID] = world_under
	var mm := root.get_node_or_null("MapManager")
	if mm != null:
		if "pick_grid" in mm and _saved_pick_grid == null:
			_saved_pick_grid = mm.pick_grid
			mm.pick_grid = null
		if "_centroids" in mm and mm._centroids is Dictionary:
			var cents: Dictionary = mm._centroids
			if not _centroids_saved:
				_saved_centroids = cents.duplicate()
				_centroids_saved = true
			cents.clear()
			cents[GER_PID] = world_under
	if _mr.has_method("_still_click_province_pid"):
		var got := int(_mr.call("_still_click_province_pid", world_under, false))
		if got != GER_PID:
			_fail("Uelzen seed did not resolve (pid=%s)" % str(got))
			return false
	return true


func _restore_pick_grid() -> void:
	var mm := root.get_node_or_null("MapManager")
	if mm == null:
		return
	if "pick_grid" in mm and _saved_pick_grid != null:
		mm.pick_grid = _saved_pick_grid
		_saved_pick_grid = null
	if _centroids_saved and "_centroids" in mm and mm._centroids is Dictionary:
		var cents: Dictionary = mm._centroids
		cents.clear()
		for k in _saved_centroids.keys():
			cents[k] = _saved_centroids[k]
		_centroids_saved = false
		_saved_centroids = {}


func _guide() -> Node:
	return root.get_node_or_null("FirstSessionGuide")


func _hover_name() -> String:
	var vp := root.get_viewport()
	if vp == null:
		return ""
	var hov := vp.gui_get_hovered_control()
	if hov == null:
		return ""
	return str(hov.name)


func _push_motion(pt: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = pt
	motion.global_position = pt
	motion.relative = Vector2(1, 0)
	root.push_input(motion)


func _push_left_at(pt: Vector2, pressed: bool) -> void:
	root.push_input(_mouse_at(pt, pressed))


func _push_wheel_up(pt: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.device = 0
	mb.button_index = MOUSE_BUTTON_WHEEL_UP
	mb.pressed = true
	mb.position = pt
	mb.global_position = pt
	root.push_input(mb)


func _zoom_x() -> float:
	if _cam == null and _mr != null:
		_cam = _mr.get_node_or_null("MapCamera") as Camera2D
	if _cam == null:
		return 0.0
	return absf(_cam.zoom.x)


func _soft_clear_inspector() -> void:
	if _mr != null:
		_mr.set("selected_province_id", -1)
		_mr.set("selected_formation_id", "")
	if _info != null:
		_info.visible = false


func _prepare_prompt_map() -> bool:
	if _mr == null and not _setup_map():
		return false
	await _close_command_center()
	# Headless leaves the OS cursor at (0, 0). The top bar owns that point, and
	# _gui_blocks_map_pick follows the cursor, not the click's event.position.
	if _bar != null:
		_bar.visible = false
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wire_inspector_labels()
	if not _seed_uelzen(PROMPT_CLICK):
		return false
	_soft_clear_inspector()
	return true


## A press the map sees, then the prompt gates input so the matching release
## is missed. A motion while the blocker is up leaves the stale Popup hover.
func _raise_prompt_with_stale_press() -> bool:
	var guide := _guide()
	if guide == null or not guide.has_method("_show_prompt"):
		_fail("FirstSessionGuide missing")
		return false
	_soft_clear_inspector()
	if _mr != null:
		_mr.set_process_input(true)
		_mr.set_process_unhandled_input(true)
	_push_left_at(PROMPT_HOVER, true)
	guide.call("_show_prompt")
	await _frames(2)
	if _mr != null and _mr.is_processing_input():
		_fail("prompt did not gate MapRenderer input")
		return false
	_push_left_at(PROMPT_HOVER, false)
	_push_motion(PROMPT_HOVER)
	await _frames(1)
	_info_line("prompt up hover=%s map_input=%s" % [
		_hover_name(), str(_mr.is_processing_input() if _mr != null else false)
	])
	return true


func _dismiss_prompt(how: String) -> bool:
	var guide := _guide()
	if guide == null:
		_fail("FirstSessionGuide missing on dismiss")
		return false
	if how == "know":
		if guide.has_method("_center_prompt"):
			guide.call("_center_prompt")
		await _frames(1)
		var know := guide.find_child("BtnKnowGame", true, false) as Button
		if know == null:
			_fail("BtnKnowGame missing")
			return false
		var rect := know.get_global_rect()
		if rect.size.x < 4.0:
			_fail("BtnKnowGame has no rect %s" % str(rect))
			return false
		_click_same_frame(rect.get_center())
	else:
		_push_key(KEY_ESCAPE)
	await _frames(3)
	var prompt := guide.get("_prompt") as CanvasItem
	if prompt != null and prompt.visible:
		_fail("prompt still visible after %s" % how)
		return false
	return _assert_prompt_released(how)


## Hidden blocker must not keep a STOP filter, and the map gesture must be
## button-up and ready. Headless 4.7.1 clears hover when the blocker hides,
## so the click itself can already land; live xdotool does not refresh hover.
func _assert_prompt_released(how: String) -> bool:
	var guide := _guide()
	var blocker := guide.get("_blocker") as Control if guide != null else null
	var filter := int(blocker.mouse_filter) if blocker != null else -1
	var ready := bool(_mr.get("_left_ready_for_still_click")) if _mr != null else false
	var down := bool(_mr.get("_left_btn_down")) if _mr != null else true
	var processing := _mr != null and _mr.is_processing_input()
	_info_line("dismiss=%s hover=%s filter=%s map_input=%s left_down=%s ready=%s" % [
		how, _hover_name(), str(filter), str(processing), str(down), str(ready)
	])
	if blocker == null or blocker.visible or filter != int(Control.MOUSE_FILTER_IGNORE):
		_fail("prompt dismiss (%s): blocker still takes the pointer (visible=%s filter=%s)" % [
			how, str(blocker.visible if blocker != null else true), str(filter)
		])
		return false
	if not processing or down or not ready:
		_fail("prompt dismiss (%s): map input=%s left_down=%s ready=%s" % [
			how, str(processing), str(down), str(ready)
		])
		return false
	return true


func _hide_top_bar_for_map_click() -> void:
	# Inspector layout can show the bar again. (0, 0) is the stuck headless cursor.
	if _bar != null:
		_bar.visible = false
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _case_prompt_dismiss_first_click() -> void:
	print("INPUT_POLISH_1 case=prompt_dismiss_first_click")
	if not await _prepare_prompt_map():
		return
	for how in ["esc", "know"]:
		if not await _raise_prompt_with_stale_press():
			return
		if not await _dismiss_prompt(how):
			return
		_hide_top_bar_for_map_click()
		_push_left_at(PROMPT_CLICK, true)
		_push_left_at(PROMPT_CLICK, false)
		await _frames(3)
		var pid := int(_mr.get("selected_province_id")) if _mr != null else -1
		var up := _info != null and _info.visible
		_info_line("first click how=%s pid=%s inspector=%s" % [how, str(pid), str(up)])
		if pid != GER_PID or not up:
			_fail("prompt_dismiss_first_click (%s): first click pid=%s inspector=%s want %s" % [
				how, str(pid), str(up), str(GER_PID)
			])
			return
		_soft_clear_inspector()
	if not await _assert_hidden_host_ungates():
		return
	_pass("prompt_dismiss_first_click: Esc and I know the game, inspector on first click")


func _assert_hidden_host_ungates() -> bool:
	if not await _raise_prompt_with_stale_press():
		return false
	var guide := _guide()
	var host := guide.get("_host") as CanvasItem if guide != null else null
	if host == null:
		_fail("GuideHost missing")
		return false
	host.visible = false
	await _frames(3)
	var processing := _mr != null and _mr.is_processing_input()
	_info_line("hidden host map_input=%s prompt_visible=%s" % [
		str(processing),
		str(bool(guide.get("_prompt").visible) if guide.get("_prompt") != null else false),
	])
	host.visible = true
	if guide.has_method("_hide_prompt"):
		guide.call("_hide_prompt")
	await _frames(1)
	if not processing:
		_fail("prompt.visible under a hidden host kept MapRenderer input off")
		return false
	return true


func _case_prompt_dismiss_wheel_zoom() -> void:
	print("INPUT_POLISH_1 case=prompt_dismiss_wheel_zoom")
	if _mr == null and not await _prepare_prompt_map():
		return
	if not _centroids_saved and not _seed_uelzen(PROMPT_CLICK):
		return
	for how in ["esc", "know"]:
		if not await _raise_prompt_with_stale_press():
			return
		if not await _dismiss_prompt(how):
			return
		var z0 := _zoom_x()
		var fid0 := str(_mr.get("selected_formation_id")) if _mr != null else ""
		_push_wheel_up(PROMPT_CLICK)
		await _frames(2)
		var z1 := _zoom_x()
		var fid1 := str(_mr.get("selected_formation_id")) if _mr != null else ""
		_info_line("wheel how=%s zoom %.4f→%.4f unit '%s'→'%s'" % [how, z0, z1, fid0, fid1])
		if absf(z1 - z0) < 0.001:
			_fail("prompt_dismiss_wheel_zoom (%s): wheel-up did not zoom (%.4f)" % [how, z1])
			return
		if fid1 != fid0 or not fid1.is_empty():
			_fail("prompt_dismiss_wheel_zoom (%s): wheel selected unit '%s'" % [how, fid1])
			return
	_pass("prompt_dismiss_wheel_zoom: wheel-up zooms and selects no unit")
	_restore_pick_grid()
