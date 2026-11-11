extends SceneTree

## INPUT-POLISH-1. Input-routing nits only.
## search_digits_no_leak must FAIL on 33c0722f (a focus drop between digits
## leaks KEY_3 into TopInfoBar speed and the box loses the tail) and PASS
## once a Search typing session keeps the digits and the clock.
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     --resolution 1280x800 -s res://scripts/core/HeadlessInputPolish1Test.gd

const PLAY_SIZE := Vector2i(1280, 800)

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
	await _case_search_digits_no_leak()
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


