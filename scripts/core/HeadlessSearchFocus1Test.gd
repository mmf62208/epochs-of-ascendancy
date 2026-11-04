extends SceneTree

## FIRST20-FIX-1 search focus. Real InputEventKey / InputEventMouseButton only.
## Type in Search, Esc releases focus and closes the layer, the next Esc opens
## pause. Enter, a result-row click, and a map click also release focus.
## Hotkeys stay blocked while the line is focused and work after release.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessSearchFocus1Test.gd

const PLAY_SIZE := Vector2i(1280, 800)

var _failures: int = 0
var _mr: Node = null
var _bar: Control = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	if not _setup_map():
		_finish()
		return
	if not await _boot_top_bar():
		_finish()
		return
	await _frames(4)
	_drop_title()
	if _mr.has_method("ensure_live_search_chrome"):
		_mr.call("ensure_live_search_chrome")
	await _frames(2)
	await _case_esc_then_pause()
	await _case_enter_releases()
	await _case_map_click_and_hotkey()
	await _case_result_pick_releases()
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessSearchFocus1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSearchFocus1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] ", msg)


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
	var info := Panel.new()
	info.name = "InfoPanel"
	info.visible = false
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size = Vector2(280, 160)
	map_ui.add_child(info)
	_mr.set("info_panel", info)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.position = Vector2(400, 300)
	cam.enabled = true
	_mr.add_child(cam)
	root.add_child(_mr)
	cam.make_current()
	_pass("MapRenderer fixture ready")
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
	_pass("TopInfoBar live")
	return true


func _drop_title() -> void:
	var title := root.find_child("LivingTitleBoot", true, false)
	if title != null and is_instance_valid(title):
		title.set("_closed", true)
		title.name = "LivingTitleBootGone"
		title.free()


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


func _results_visible() -> bool:
	var search := _search()
	if search == null:
		return false
	var results := search.get_node_or_null("SearchResults") as CanvasItem
	return results != null and is_instance_valid(results) and results.visible


func _cc_up() -> bool:
	var mm := root.get_node_or_null("MainMenu")
	if mm == null or not is_instance_valid(mm) or mm.is_queued_for_deletion():
		return false
	if str(mm.name) != "MainMenu":
		return false
	if bool(mm.get("_closing")):
		return false
	if mm is CanvasLayer and not (mm as CanvasLayer).visible:
		return false
	return true


func _close_cc() -> void:
	var mm := root.get_node_or_null("MainMenu")
	if mm != null and is_instance_valid(mm) and mm.has_method("_force_close") and not bool(mm.get("_closing")):
		mm.call("_force_close")


func _hide_inspector() -> void:
	if _mr == null:
		return
	var info: Variant = _mr.get("info_panel")
	if info is CanvasItem and is_instance_valid(info):
		(info as CanvasItem).visible = false


func _push_key(code: Key, pressed: bool) -> void:
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
	root.push_input(key)


func _tap_key(code: Key) -> void:
	_push_key(code, true)
	await process_frame
	_push_key(code, false)
	await process_frame


func _type_ascii(text: String) -> void:
	var i := 0
	while i < text.length():
		var code: Key = text.unicode_at(i) as Key
		await _tap_key(code)
		i += 1


func _warp(pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(pt)
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = pt
	motion.global_position = pt
	motion.relative = Vector2(1, 1)
	root.push_input(motion)


func _click(pt: Vector2) -> void:
	_warp(pt)
	await process_frame
	var down := InputEventMouseButton.new()
	down.device = 0
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pt
	down.global_position = pt
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.device = 0
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pt
	up.global_position = pt
	up.button_mask = 0
	root.push_input(up)
	await process_frame


func _focus_line_by_click() -> LineEdit:
	var line := _line()
	if line == null:
		_fail("SearchLineEdit missing")
		return null
	await _click(line.get_global_rect().get_center())
	await _frames(2)
	if not line.has_focus():
		_fail("click did not focus SearchLineEdit")
		return null
	return line


func _case_esc_then_pause() -> void:
	print("SEARCH_FOCUS case=esc_then_pause")
	_close_cc()
	_hide_inspector()
	await _frames(2)
	var line := await _focus_line_by_click()
	if line == null:
		return
	await _type_ascii("berlin")
	await _frames(2)
	print("SEARCH_FOCUS typed text=%s focus=%s results=%s" % [line.text, str(line.has_focus()), str(_results_visible())])
	if line.text != "berlin" or not line.has_focus():
		_fail("typing did not land in the search line (text=%s focus=%s)" % [line.text, str(line.has_focus())])
		return
	var mode_before := str(_mr.get("current_map_mode"))
	await _tap_key(KEY_F2)
	await _frames(1)
	if str(_mr.get("current_map_mode")) != mode_before:
		_fail("F2 changed map mode while the search line was focused")
		return
	await _tap_key(KEY_ESCAPE)
	await _frames(2)
	var fo: Control = root.get_viewport().gui_get_focus_owner() if root.get_viewport() != null else null
	print("SEARCH_FOCUS after_esc focus=%s text=%s results=%s cc=%s" % [str(line.has_focus()), line.text, str(_results_visible()), str(_cc_up())])
	if line.has_focus() or (fo != null and fo == line):
		_fail("Esc left the search line focused")
		return
	if _results_visible() or not line.text.strip_edges().is_empty():
		_fail("Esc did not close the search layer")
		return
	if _cc_up():
		_fail("the Esc that closed search also opened pause")
		return
	await _tap_key(KEY_ESCAPE)
	await _frames(4)
	print("SEARCH_FOCUS next_esc cc=%s" % str(_cc_up()))
	if not _cc_up():
		_fail("the next Esc did not open the pause menu")
		return
	_pass("Esc released search focus; the next Esc opened pause")


func _case_enter_releases() -> void:
	print("SEARCH_FOCUS case=enter")
	_close_cc()
	_hide_inspector()
	await _frames(2)
	var line := await _focus_line_by_click()
	if line == null:
		return
	await _type_ascii("paris")
	await _frames(1)
	await _tap_key(KEY_ENTER)
	await _frames(3)
	print("SEARCH_FOCUS after_enter focus=%s text=%s" % [str(line.has_focus()), line.text])
	if line.has_focus():
		_fail("Enter left the search line focused")
		return
	_pass("Enter released search focus")


func _case_map_click_and_hotkey() -> void:
	print("SEARCH_FOCUS case=map_click")
	_close_cc()
	_hide_inspector()
	await _frames(2)
	var line := await _focus_line_by_click()
	if line == null:
		return
	await _type_ascii("rome")
	await _frames(2)
	if not line.has_focus():
		_fail("search line lost focus before the map click")
		return
	var map_pt := Vector2(640, 560)
	var bar_rect := _bar.get_global_rect() if _bar != null else Rect2()
	if bar_rect.has_point(map_pt):
		map_pt = Vector2(640, bar_rect.end.y + 80.0)
	var search := _search() as Control
	var srect := search.get_global_rect() if search != null else Rect2()
	print("SEARCH_FOCUS map_pt=%s search_rect=%s line_rect=%s text=%s" % [str(map_pt), str(srect), str(line.get_global_rect()), line.text])
	await _click(map_pt)
	await _frames(2)
	print("SEARCH_FOCUS after_map focus=%s results=%s text=%s pt=%s" % [str(line.has_focus()), str(_results_visible()), line.text, str(map_pt)])
	if line.has_focus():
		_fail("map click left the search line focused")
		return
	if _results_visible():
		_fail("map click left the search results open")
		return
	await _tap_key(KEY_F2)
	await _frames(2)
	var mode := str(_mr.get("current_map_mode"))
	print("SEARCH_FOCUS hotkey_after_map mode=%s" % mode)
	if mode != "strain":
		_fail("F2 did not run after the map click released focus (mode=%s)" % mode)
		return
	_pass("map click released focus and F2 worked")


func _case_result_pick_releases() -> void:
	print("SEARCH_FOCUS case=result_pick")
	_close_cc()
	_hide_inspector()
	await _frames(2)
	var line := await _focus_line_by_click()
	if line == null:
		return
	await _type_ascii("berlin")
	await _frames(2)
	var search := _search()
	var row := search.find_child("SearchResultRow", true, false) as Button if search != null else null
	if row == null or not row.visible:
		_fail("result row did not open for berlin text=%s focus=%s" % [line.text, str(line.has_focus())])
		return
	await _click(row.get_global_rect().get_center())
	await _frames(3)
	var fo: Control = root.get_viewport().gui_get_focus_owner() if root.get_viewport() != null else null
	var stuck := line.has_focus() or (fo != null and (fo == line or fo == row))
	print("SEARCH_FOCUS after_pick focus_line=%s owner=%s" % [str(line.has_focus()), str(fo.name) if fo != null else "none"])
	if stuck:
		_fail("picking a search result left focus in the search chrome")
		return
	await _tap_key(KEY_F3)
	await _frames(2)
	var mode := str(_mr.get("current_map_mode"))
	print("SEARCH_FOCUS hotkey_after_pick mode=%s" % mode)
	if mode != "vitality":
		_fail("F3 did not run after the result pick released focus (mode=%s)" % mode)
		return
	_pass("result pick released focus and F3 worked")
