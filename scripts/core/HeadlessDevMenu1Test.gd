extends SceneTree

## FIRST20-FIX-1 debug menu. Player Menu and F10 stay closed unless this is a
## debug build AND ProjectSettings eoa/dev_menu is on. A release build
## (debug_build=false) cannot open MAP TOOLS, including from a toast-close click.
## The overlay stamp uses local time.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessDevMenu1Test.gd

const PLAY_SIZE := Vector2i(1280, 800)
const DEBUG_ITEM := "Debug (F10)"
const CC_DEBUG := "Open Debug Overlay (F10)"

var _failures: int = 0
var _bar: Control = null
var _world: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	ProjectSettings.set_setting("eoa/dev_menu", false)
	if not await _boot_bar():
		_finish()
		return
	await _frames(3)
	await _case_off_menu_and_f10()
	await _case_toast_close_cannot_open()
	_case_release_predicate_and_stamp()
	await _case_command_center(false)
	ProjectSettings.set_setting("eoa/dev_menu", true)
	if _bar != null and _bar.has_method("_setup_compact_menu"):
		_bar.call("_setup_compact_menu")
	await _frames(2)
	await _case_on_menu_and_f10()
	await _case_command_center(true)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessDevMenu1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessDevMenu1Test: RESULT=", "PASS" if ok else "FAIL")
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


func _boot_bar() -> bool:
	_world = Node.new()
	_world.name = "DevMenuWorld"
	root.add_child(_world)
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	layer.layer = 110
	_world.add_child(layer)
	current_scene = _world
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
	_pass("TopInfoBar live with eoa/dev_menu off")
	return true


func _popup() -> PopupMenu:
	if _bar == null:
		return null
	var mb: MenuButton = _bar.get("menu_button") as MenuButton
	if mb == null:
		return null
	return mb.get_popup()


func _menu_has(text: String) -> bool:
	var popup := _popup()
	if popup == null:
		return false
	var i := 0
	while i < popup.item_count:
		if popup.get_item_text(i) == text:
			return true
		i += 1
	return false


func _menu_texts() -> String:
	var popup := _popup()
	if popup == null:
		return ""
	var parts: PackedStringArray = []
	var i := 0
	while i < popup.item_count:
		var label := popup.get_item_text(i)
		if not label.is_empty():
			parts.append(label)
		i += 1
	return ", ".join(parts)


func _dbg() -> GDScript:
	# load() at runtime, after autoloads exist. A class_name reference here
	# compiles the overlay before TimeManager is registered.
	return load("res://scripts/ui/DebugOverlay.gd") as GDScript


func _map_tools_open() -> bool:
	var found := root.find_child("DebugOverlay", true, false)
	return found is CanvasItem and (found as CanvasItem).visible


func _map_tools_title() -> String:
	var host: Node = root.find_child("DebugOverlay", true, false)
	if host == null:
		return ""
	var labels: Array[Node] = host.find_children("*", "Label", true, false)
	for node in labels:
		var lbl := node as Label
		if lbl != null and "MAP TOOLS" in lbl.text:
			return lbl.text
	return ""


func _push_key(code: Key, pressed: bool, ctrl: bool = false, shift: bool = false) -> void:
	var key := InputEventKey.new()
	key.device = 0
	key.keycode = code
	key.physical_keycode = code
	key.key_label = code
	key.pressed = pressed
	key.echo = false
	key.ctrl_pressed = ctrl
	key.shift_pressed = shift
	root.push_input(key)


func _tap_key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	_push_key(code, true, ctrl, shift)
	await process_frame
	_push_key(code, false, ctrl, shift)
	await process_frame


func _case_off_menu_and_f10() -> void:
	print("DEV_MENU case=off texts=%s" % _menu_texts())
	if _menu_has(DEBUG_ITEM):
		_fail("player menu lists Debug (F10) while eoa/dev_menu is off")
		return
	if not _menu_has("Settings"):
		_fail("player menu lost Settings")
		return
	await _tap_key(KEY_F10)
	await _frames(4)
	if _map_tools_open():
		_fail("F10 opened MAP TOOLS while eoa/dev_menu is off")
		return
	await _tap_key(KEY_R, true, true)
	await _frames(3)
	if _map_tools_open():
		_fail("Ctrl+Shift+R opened MAP TOOLS while eoa/dev_menu is off")
		return
	var dbg := _dbg()
	if dbg != null:
		dbg.call("toggle")
		dbg.call("show_overlay")
	await _frames(2)
	if _map_tools_open():
		_fail("toggle/show_overlay opened MAP TOOLS while eoa/dev_menu is off")
		return
	var popup := _popup()
	if popup != null:
		popup.id_pressed.emit(4)
		await _frames(3)
	if _map_tools_open():
		_fail("menu id 4 opened MAP TOOLS while eoa/dev_menu is off")
		return
	_pass("off: no Debug item, F10 and a menu id do nothing")


func _click(pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(pt)
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = pt
	motion.global_position = pt
	motion.relative = Vector2(1, 1)
	root.push_input(motion)
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


func _case_toast_close_cannot_open() -> void:
	print("DEV_MENU case=toast_close")
	var leui: Node = root.get_node_or_null("LeaderEventUI")
	if leui == null or not leui.has_method("show_toast"):
		_fail("LeaderEventUI.show_toast missing")
		return
	leui.set("force_toast_ui", true)
	leui.call("show_toast", "DEV-MENU toast close must not open MAP TOOLS", 30.0)
	await _frames(4)
	var btn: Button = leui.find_child("NoticeClose", true, false) as Button
	if btn == null or not is_instance_valid(btn):
		_fail("toast did not build NoticeClose")
		return
	var pt := btn.get_global_rect().get_center()
	print("DEV_MENU toast_close rect=%s pt=%s" % [str(btn.get_global_rect()), str(pt)])
	if btn.get_global_rect().size == Vector2.ZERO:
		_fail("NoticeClose has no screen rect")
		return
	await _click(pt)
	await _frames(3)
	if _map_tools_open():
		_fail("toast-close click opened MAP TOOLS")
		return
	if is_instance_valid(btn) and btn.is_inside_tree():
		_fail("toast-close click did not dismiss the notice")
		return
	_pass("toast-close click dismissed the notice and left MAP TOOLS closed")


func _case_release_predicate_and_stamp() -> void:
	print("DEV_MENU case=predicate_stamp")
	var dbg := _dbg()
	if dbg == null:
		_fail("DebugOverlay.gd missing")
		return
	if bool(dbg.call("dev_menu_allowed_for", false, true)):
		_fail("a release build with the setting on would show Debug")
	elif bool(dbg.call("dev_menu_allowed_for", true, false)):
		_fail("a debug build with eoa/dev_menu off would show Debug")
	elif not bool(dbg.call("dev_menu_allowed_for", true, true)):
		_fail("the dev path would hide Debug")
	else:
		_pass("release build cannot open Debug; dev path can")
	var stamp := str(dbg.call("local_refresh_stamp"))
	var expect := Time.get_datetime_string_from_system(false, true)
	if stamp.length() < 16 or stamp.substr(0, 16) != expect.substr(0, 16):
		_fail("local stamp %s != %s" % [stamp, expect])
	else:
		var ov: Node = dbg.new()
		var lbl := Label.new()
		ov.set("_status_label", lbl)
		ov.call("_update_status")
		if not (stamp.substr(0, 16) in lbl.text):
			_fail("status label did not use the local stamp (%s)" % lbl.text)
		else:
			_pass("overlay stamp is local time (%s)" % stamp.substr(0, 16))
		ov.free()


func _tree_has_text(node: Node, text: String) -> bool:
	if node is Button and (node as Button).text == text:
		return true
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false


func _case_command_center(dev_on: bool) -> void:
	print("DEV_MENU case=command_center on=%s" % str(dev_on))
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		_fail("MainMenu.tscn missing")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await _frames(2)
	var has := _tree_has_text(menu, CC_DEBUG)
	if dev_on and not has:
		_fail("Command Center hid Open Debug Overlay while eoa/dev_menu is on")
	elif not dev_on and has:
		_fail("Command Center shows Open Debug Overlay while eoa/dev_menu is off")
	else:
		_pass("Command Center debug entry matches eoa/dev_menu=%s" % str(dev_on))
	menu.queue_free()
	await _frames(2)


func _case_on_menu_and_f10() -> void:
	print("DEV_MENU case=on texts=%s" % _menu_texts())
	var dbg := _dbg()
	if dbg == null or not bool(dbg.call("dev_menu_allowed")):
		_fail("dev path is closed while eoa/dev_menu is on in a debug build")
		return
	if not _menu_has(DEBUG_ITEM):
		_fail("dev menu did not list Debug (F10)")
		return
	await _tap_key(KEY_F10)
	await _frames(6)
	if not _map_tools_open():
		_fail("F10 did not open MAP TOOLS on the dev path")
		return
	var title := _map_tools_title()
	print("DEV_MENU map_tools title=%s" % title)
	if not ("MAP TOOLS" in title):
		_fail("open overlay title is not MAP TOOLS (%s)" % title)
		return
	_pass("on: Debug item present and F10 opens MAP TOOLS")
