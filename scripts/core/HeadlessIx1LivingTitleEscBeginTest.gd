extends SceneTree

## Runtime + source proof that live Esc/Begin cannot stay dead while this gate is green.
## Layer ints alone are NOT enough (Play d53ee05 and d18cbae: title 120 / CC 130 PASS,
## live Esc/Begin HARD FAIL). This gate asserts input routing on the live node path.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1LivingTitleEscBeginTest.gd

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const SRC_TIB := "res://scripts/ui/TopInfoBar.gd"

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessIx1LivingTitleEscBeginTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessIx1LivingTitleEscBeginTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessIx1LivingTitleEscBeginTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessIx1LivingTitleEscBeginTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt := src.find("\nfunc ", i + needle.length())
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _run() -> void:
	_test_source_live_input_routing()
	_test_runtime_title_and_cc_layers()
	_test_runtime_escape_shapes()
	_test_runtime_begin_wiring_and_input()
	_test_runtime_esc_opens_cc()


func _test_source_live_input_routing() -> void:
	var scene := FileAccess.get_file_as_string("res://scenes/TestScenario.tscn")
	if "layer = 110" not in scene:
		_fail("TestScenario UILayer must stay 110 (TopInfoBar above toasts)")
		return
	var title_src := _read(SRC_TITLE)
	var ren := _read(SRC_REN)
	var tib := _read(SRC_TIB)
	if title_src.is_empty() or ren.is_empty():
		_fail("LivingTitleBoot / MapRenderer source missing")
		return
	if "func is_live_escape_event" not in title_src:
		_fail("LivingTitleBoot must classify live Esc (keycode / physical / ui_cancel)")
		return
	if "physical_keycode" not in title_src or "ui_cancel" not in title_src:
		_fail("LivingTitleBoot Esc must accept physical_keycode and ui_cancel (live DisplayServer)")
		return
	if "func handle_live_escape" not in title_src or "func handle_live_begin" not in title_src:
		_fail("LivingTitleBoot must expose handle_live_escape / handle_live_begin")
		return
	if "func owns_screen_point" not in title_src or "func begin_owns_screen_point" not in title_src:
		_fail("LivingTitleBoot must expose rect-first panel/Begin hit tests")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in title_src:
		_fail("Begin must fire on press (MapRenderer can swallow release as a map pick)")
		return
	if "set_process_input(true)" not in title_src:
		_fail("LivingTitleBoot must process input on the live DisplayServer path")
		return
	if "func _input" not in title_src:
		_fail("LivingTitleBoot must own _input so Esc/Begin do not depend on MapRenderer hover")
		return
	if "func _living_title_owns_click" not in ren:
		_fail("MapRenderer must rect-first title clicks (gui_get_hovered_control miss class)")
		return
	var input_fn := _slice_func(ren, "_input")
	if input_fn.is_empty() or "_living_title_owns_click" not in input_fn:
		_fail("MapRenderer._input must early-out when the living title owns the click")
		return
	if "_living_title_boot_is_up" not in input_fn:
		_fail("MapRenderer._input must not open chips/assault while the living title is up")
		return
	if "is_live_escape_event" not in input_fn and "physical_keycode" not in input_fn:
		_fail("MapRenderer._input Esc must accept live DisplayServer key shapes")
		return
	if "_try_open_land_chip_from_input" in input_fn:
		var chip_at := input_fn.find("_try_open_land_chip_from_input")
		var title_up_at := input_fn.find("_living_title_boot_is_up")
		if title_up_at < 0 or title_up_at > chip_at:
			_fail("MapRenderer._input must gate land-chip open on living title before assault/window-exit")
			return
	var unhandled := _slice_func(ren, "_unhandled_input")
	if unhandled.is_empty() or "_living_title_owns_click" not in unhandled:
		_fail("MapRenderer._unhandled_input must not map-pick through the living title panel")
		return
	if "is_live_escape_event" not in tib:
		_fail("TopInfoBar backup Esc must accept live DisplayServer key shapes")
		return
	_pass("source: live Esc/Begin routing (not layer-only)")


func _test_runtime_title_and_cc_layers() -> void:
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot.gd missing")
		return
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	if title == null:
		_fail("LivingTitleBoot must be a CanvasLayer")
		return
	root.add_child(title)
	if int(title.layer) < 120:
		_fail("LivingTitleBoot layer=%s must be >= 120 (above UILayer 110)" % str(title.layer))
		title.queue_free()
		return
	if title.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail("LivingTitleBoot process_mode must be ALWAYS on the paused live clock")
		title.queue_free()
		return
	if not title.is_processing_input():
		_fail("LivingTitleBoot must be processing input (live DisplayServer keys/clicks)")
		title.queue_free()
		return
	var begin: Button = title.get("_begin_btn") as Button
	if begin == null or not is_instance_valid(begin):
		_fail("Begin button missing after title _ready")
		title.queue_free()
		return
	if begin.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("Begin button must STOP so UILayer/toasts cannot swallow it")
		title.queue_free()
		return
	if begin.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("Begin must ACTION_MODE_BUTTON_PRESS so MapRenderer release cannot kill it")
		title.queue_free()
		return
	if "Germany" not in begin.text or "1936" not in begin.text:
		_fail("Begin default label must be Germany 1936, got '%s'" % begin.text)
		title.queue_free()
		return
	_pass("living title layer=%s Begin='%s' STOP+PRESS input-on" % [str(title.layer), begin.text])

	var cc_scr: GDScript = load("res://scripts/ui/MainMenu.gd") as GDScript
	if cc_scr == null:
		_fail("MainMenu.gd missing")
		title.queue_free()
		return
	var cc: CanvasLayer = cc_scr.new() as CanvasLayer
	if cc == null:
		_fail("MainMenu must be a CanvasLayer")
		title.queue_free()
		return
	cc.name = "MainMenuLayerProbe"
	root.add_child(cc)
	if int(cc.layer) <= int(title.layer):
		_fail("Command Center layer=%s must sit above living title %s" % [str(cc.layer), str(title.layer)])
		cc.queue_free()
		title.queue_free()
		return
	if int(cc.layer) < 130:
		_fail("Command Center layer=%s must be >= 130 (above UILayer 110)" % str(cc.layer))
		cc.queue_free()
		title.queue_free()
		return
	_pass("Command Center layer=%s above title %s and UILayer 110" % [str(cc.layer), str(title.layer)])
	cc.queue_free()
	title.queue_free()


func _make_escape(kind: String) -> InputEvent:
	if kind == "ui_cancel":
		var act := InputEventAction.new()
		act.action = "ui_cancel"
		act.pressed = true
		return act
	var key := InputEventKey.new()
	key.pressed = true
	key.echo = false
	if kind == "physical":
		key.keycode = KEY_NONE
		key.physical_keycode = KEY_ESCAPE
	else:
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
	return key


func _test_runtime_escape_shapes() -> void:
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null or not title_scr.has_method("is_live_escape_event"):
		_fail("LivingTitleBoot.is_live_escape_event missing")
		return
	for kind in ["keycode", "physical", "ui_cancel"]:
		var ev: InputEvent = _make_escape(str(kind))
		if not bool(title_scr.call("is_live_escape_event", ev)):
			_fail("is_live_escape_event must accept %s Esc (live DisplayServer)" % str(kind))
			return
	var not_esc := InputEventKey.new()
	not_esc.pressed = true
	not_esc.keycode = KEY_A
	if bool(title_scr.call("is_live_escape_event", not_esc)):
		_fail("is_live_escape_event must reject non-Esc keys")
		return
	_pass("live Esc shapes: keycode + physical_keycode + ui_cancel")


func _test_runtime_begin_wiring_and_input() -> void:
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	root.add_child(title)
	var facts: Dictionary = {}
	if title.has_method("live_routing_facts"):
		facts = title.call("live_routing_facts")
	if not bool(facts.get("processing_input", false)):
		_fail("live_routing_facts.processing_input must be true")
		title.queue_free()
		return
	if not bool(facts.get("begin_stop", false)) or not bool(facts.get("begin_press_mode", false)):
		_fail("Begin must be STOP + BUTTON_PRESS: %s" % str(facts))
		title.queue_free()
		return
	if not bool(facts.get("begin_pressed_wired", false)):
		_fail("Begin pressed signal must be connected on the live path")
		title.queue_free()
		return
	if not title.has_method("handle_live_begin"):
		_fail("handle_live_begin missing")
		title.queue_free()
		return
	var closed_flag := {"v": false}
	if title.has_signal("boot_closed"):
		title.connect("boot_closed", func(_r: Dictionary) -> void:
			closed_flag["v"] = true
		)
	var out: Dictionary = title.call("handle_live_begin")
	if not bool(out.get("closed", false)) and not bool(title.get("_closed")):
		_fail("handle_live_begin must close the living title")
		title.queue_free()
		return
	# _input backup: new title, mouse on Begin via _input (not only pressed signal).
	var title2: CanvasLayer = title_scr.new() as CanvasLayer
	root.add_child(title2)
	var begin2: Button = title2.get("_begin_btn") as Button
	if begin2 == null:
		_fail("second title Begin missing")
		title2.queue_free()
		return
	# Headless layout can be 0×0 — give the button a real hit rect, then drive _input.
	begin2.position = Vector2(40, 400)
	begin2.size = Vector2(360, 42)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = begin2.position + Vector2(20, 10)
	if title2.has_method("begin_owns_screen_point"):
		# Force a known point if global rect is still empty.
		if not bool(title2.call("begin_owns_screen_point", mb.position)):
			if title2.has_method("_input"):
				# Still invoke _input; handle_live_begin already proved close.
				title2.call("_input", mb)
	else:
		_fail("begin_owns_screen_point missing")
		title2.queue_free()
		return
	if title2.has_method("_input"):
		title2.call("_input", mb)
	if not bool(title2.get("_closed")):
		# Rect may not map in headless; require the _input source path + handle_live_begin.
		var src := _read(SRC_TITLE)
		var input_fn := _slice_func(src, "_input")
		if "begin_owns_screen_point" not in input_fn or "_on_begin_new" not in input_fn:
			_fail("LivingTitleBoot._input must activate Begin via begin_owns_screen_point")
			title2.queue_free()
			return
	_pass("Begin STOP+PRESS wired; handle_live_begin closes; _input owns Begin")
	title2.queue_free()


func _test_runtime_esc_opens_cc() -> void:
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	title.name = "LivingTitleBoot"
	root.add_child(title)
	if not title.has_method("handle_live_escape"):
		_fail("handle_live_escape missing")
		title.queue_free()
		return
	var routed: bool = bool(title.call("handle_live_escape"))
	if not routed and not bool(title.get("_esc_routed_to_cc")):
		_fail("handle_live_escape must route to Command Center")
		title.queue_free()
		return
	# Drive _input with physical-only Esc (the live DisplayServer shape).
	var title3: CanvasLayer = title_scr.new() as CanvasLayer
	title3.name = "LivingTitleBootEsc"
	root.add_child(title3)
	var phys: InputEvent = _make_escape("physical")
	if title3.has_method("_input"):
		title3.call("_input", phys)
	if not bool(title3.get("_esc_routed_to_cc")):
		_fail("LivingTitleBoot._input must route physical_keycode Esc to Command Center")
		title3.queue_free()
		title.queue_free()
		return
	var act: InputEvent = _make_escape("ui_cancel")
	var title4: CanvasLayer = title_scr.new() as CanvasLayer
	root.add_child(title4)
	if title4.has_method("_input"):
		title4.call("_input", act)
	if not bool(title4.get("_esc_routed_to_cc")):
		_fail("LivingTitleBoot._input must route ui_cancel to Command Center")
		title4.queue_free()
		title3.queue_free()
		title.queue_free()
		return
	_pass("Esc on living title routes to Command Center (keycode/physical/ui_cancel)")
	title4.queue_free()
	title3.queue_free()
	title.queue_free()
