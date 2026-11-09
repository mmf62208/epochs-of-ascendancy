extends SceneTree

## FIRST20-FIX-1. Return to Title must not touch a freed clock bar.
## Start, advance, first-press Return to Title, idle the title, load, advance.
## Real InputEventMouseButton through the viewport. 0 SCRIPT ERRORs.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessReturnToTitle1Test.gd

const SLOT := "rtt1"
const PLAY := Vector2i(1280, 800)
const TITLE_IDLE_FRAMES := 45
const TOPBAR_SCENE := "res://scenes/ui/TopInfoBar.tscn"
const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const REAL_SAVES := "/.local/share/godot/app_userdata/Epochs-of-Ascendancy"

var _failures: int = 0
var _log = null


func _init() -> void:
	var log_scr := load("res://scripts/core/ReturnToTitleScriptErrorLog.gd") as GDScript
	_log = log_scr.new()
	OS.add_logger(_log)
	# Existing campaign-loop switches. Not a new EOA_* flag.
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessReturnToTitle1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessReturnToTitle1Test: ", msg)


func _run() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var tm := root.get_node_or_null("TimeManager")
	var sl := root.get_node_or_null("SaveLoadManager")
	if mm == null or sm == null or tm == null or sl == null:
		_fail("autoloads missing")
		_finish()
		return
	DisplayServer.window_set_size(PLAY)
	root.size = PLAY
	var boot_scr := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if boot_scr == null or not bool(boot_scr.call("boot", mm, sm, "GER")):
		_fail("board boot failed")
		_finish()
		return
	_pass("board booted")
	if not _begin_return_begin_modifiers():
		_finish()
		return
	if tm.has_method("set_paused"):
		tm.call("set_paused", false)
	var bar := _spawn_clock_bar()
	if bar == null:
		_fail("clock bar missing")
		_finish()
		return
	if not await _wait_until_cached(sm, bar):
		_fail("SupplyManager did not cache the live clock bar")
		_finish()
		return
	_pass("clock bar cached")
	if not _exit_hooked(bar):
		_fail("clock bar tree_exiting was not connected")
		_finish()
		return
	_pass("tree_exiting disconnect hooked")
	if tm.has_method("set_paused"):
		tm.call("set_paused", false)
	for _i in 3:
		tm.call("advance_one_day")
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	var advanced_day := int(tm.get("current_day"))
	var advanced_elapsed := int(tm.get("total_days_elapsed")) if "total_days_elapsed" in tm else -1
	if advanced_elapsed < 3 and advanced_day == 1:
		_fail("clock did not advance before the save day=%d elapsed=%d" % [advanced_day, advanced_elapsed])
		_finish()
		return
	var saved: Dictionary = sl.call("save_game_detailed", SLOT)
	if not bool(saved.get("ok", false)):
		_fail("save failed %s" % str(saved.get("error", "")))
		_finish()
		return
	var abs_path := str(saved.get("absolute_path", ""))
	if abs_path.find(REAL_SAVES) >= 0 and abs_path.find("/tmp/") < 0 and abs_path.find(OS.get_environment("XDG_DATA_HOME")) < 0:
		_fail("save wrote outside the isolated user dir %s" % abs_path)
		_finish()
		return
	_pass("saved %s day=%d" % [abs_path, advanced_day])
	var packed := _title_scene()
	root.set_meta("eoa_return_title_scene", packed)
	var menu := _spawn_menu()
	if menu == null:
		_fail("command center missing")
		_finish()
		return
	await process_frame
	await process_frame
	await process_frame
	var btn := _return_button(menu)
	if btn == null:
		_fail("Return to Title button missing")
		_finish()
		return
	if btn.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("Return to Title is not press-mode")
		_finish()
		return
	var scroll := menu.find_child("GameActionsScroll", true, false) as ScrollContainer
	if scroll != null and scroll.has_method("ensure_control_visible"):
		scroll.call("ensure_control_visible", btn)
	await process_frame
	var rect := btn.get_global_rect()
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		_fail("Return to Title rect %s" % rect)
		_finish()
		return
	var center := rect.get_center()
	# Down only. A release-mode button inside the scroll does nothing yet.
	root.push_input(_mouse(center, true))
	var first_press := menu.is_queued_for_deletion()
	var cache_cleared := sm.get("_clock_bar") == null
	if not first_press:
		_fail("first Return to Title press did nothing rect=%s" % rect)
	elif not cache_cleared:
		_fail("first press did not clear the clock bar")
	else:
		_pass("first press returned to title and cleared the clock bar")
	root.push_input(_mouse(center + Vector2(3, 2), false))
	for _f in TITLE_IDLE_FRAMES:
		await process_frame
	var scene := current_scene
	var scene_name := str(scene.name) if scene != null else ""
	if scene_name != "TitleIdle":
		_fail("title scene is '%s'" % scene_name)
	elif is_instance_valid(bar):
		_fail("old clock bar still valid on the title")
	else:
		_pass("title idle %d frames after the bar was freed" % TITLE_IDLE_FRAMES)
	var loaded: Dictionary = sl.call("load_game_detailed", SLOT)
	if not bool(loaded.get("ok", false)):
		_fail("load failed %s" % str(loaded.get("error", "")))
	elif int(tm.get("current_day")) != advanced_day:
		_fail("load day=%s want %d" % [str(tm.get("current_day")), advanced_day])
	else:
		_pass("loaded save on the title")
	if tm.has_method("set_paused"):
		tm.call("set_paused", false)
	for _j in 2:
		tm.call("advance_one_day")
	for _g in 20:
		await process_frame
	var played_day := int(tm.get("current_day"))
	if played_day == advanced_day:
		_fail("clock did not advance after load day=%d" % played_day)
	else:
		_pass("advanced again after load day=%d" % played_day)
	_probe_freed_cache(sm)
	for _h in 8:
		await process_frame
	if _log.script_errors != 0:
		_fail("script_errors=%d %s" % [_log.script_errors, " | ".join(_log.samples)])
	else:
		_pass("script_errors=0 across start, title idle, load, and play")
	_finish()


func _finish() -> void:
	var logged: int = _log.script_errors if _log != null else 0
	var ok: bool = _failures == 0 and logged == 0
	print("HeadlessReturnToTitle1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, " script_errors=", _log.script_errors if _log != null else -1, ")")
	print("HeadlessReturnToTitle1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _spawn_clock_bar() -> Node:
	var packed := load(TOPBAR_SCENE) as PackedScene
	if packed == null:
		return null
	var host := Node.new()
	host.name = "PlayHost"
	var bar := packed.instantiate()
	host.add_child(bar)
	root.add_child(host)
	current_scene = host
	return bar


func _wait_until_cached(sm: Node, bar: Node) -> bool:
	for _i in 8:
		await process_frame
		var cached: Variant = sm.get("_clock_bar")
		if cached == bar and is_instance_valid(cached):
			return true
	return false


func _exit_hooked(bar: Node) -> bool:
	if bar == null or not is_instance_valid(bar):
		return false
	for conn in bar.tree_exiting.get_connections():
		var callable: Callable = conn.get("callable", Callable())
		if callable.is_valid() and str(callable.get_method()) == "_on_clock_bar_tree_exiting":
			return true
	return false


func _spawn_menu() -> Node:
	var packed := load(MENU_SCENE) as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	return menu


func _return_button(menu: Node) -> Button:
	for n in menu.find_children("*", "Button", true, false):
		if not (n is Button):
			continue
		var b := n as Button
		if str(b.get_meta("eoa_cc_action", "")) == "return_to_main":
			return b
	return null


func _begin_return_begin_modifiers() -> bool:
	# Play #172 FAIL B: second Begin after Return to Title SCRIPT ERRORed at
	# NationalModifierManager.apply_national_effect (untyped Array leftover).
	var menu_src := FileAccess.get_file_as_string("res://scripts/ui/MainMenu.gd")
	if menu_src.find("func _return_to_title") < 0 or menu_src.find("clear_all_modifiers") < 0:
		_fail("Begin/Return/Begin: Return to Title must reset NationalModifierManager")
		return false
	var nmm := root.get_node_or_null("NationalModifierManager")
	if nmm == null or not nmm.has_method("apply_national_effect"):
		_fail("Begin/Return/Begin: NationalModifierManager missing")
		return false
	var payload := {
		"source": "test_agent_boost",
		"source_detail": "boost_production mission test",
		"modifiers": {"output_multiplier": 0.12, "resource_output_multiplier": 0.08},
		"duration_months": 3,
		"remaining_months": 3,
	}
	if not bool(nmm.call("apply_national_effect", "GER", payload)):
		_fail("Begin/Return/Begin: first Begin apply failed")
		return false
	_pass("Begin/Return/Begin: first Begin applied")
	# First game leftover as Dictionary/JSON untyped Array (a75f3d53).
	var leftover: Array = []
	var stored: Variant = nmm.get("country_modifiers").get("GER", [])
	if stored is Array:
		leftover.append_array(stored)
	if leftover.is_empty():
		leftover.append({"effect_id": "stale", "modifiers": {}, "remaining_months": 1})
	nmm.country_modifiers["GER"] = leftover
	if nmm.has_method("clear_all_modifiers"):
		nmm.call("clear_all_modifiers")
	# Plant leftover again: save/load and a75f3d53 Return leave an untyped Array.
	nmm.country_modifiers["GER"] = leftover
	var errors_before: int = _log.script_errors if _log != null else 0
	var second: bool = bool(nmm.call("apply_national_effect", "GER", payload))
	var errors_after: int = _log.script_errors if _log != null else 0
	if errors_after > errors_before:
		_fail(
			"Begin/Return/Begin: second Begin SCRIPT ERROR (%d) %s"
			% [errors_after - errors_before, " | ".join(_log.samples)]
		)
		return false
	if not second:
		_fail("Begin/Return/Begin: second Begin apply failed")
		return false
	_pass("Begin/Return/Begin: second Begin applied with 0 script errors")
	return true


func _title_scene() -> PackedScene:
	var title := Node.new()
	title.name = "TitleIdle"
	var packed := PackedScene.new()
	packed.pack(title)
	title.free()
	return packed


func _mouse(pt: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pt
	ev.global_position = pt
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


## Assign a bar the bind path never saw, then free it. The next _process
## must not pass that freed object into a typed Node argument.
func _probe_freed_cache(sm: Node) -> void:
	var decoy: Variant = Node.new()
	sm.set("_clock_bar", decoy)
	(decoy as Node).free()
	decoy = null
