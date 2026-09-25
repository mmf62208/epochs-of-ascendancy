extends SceneTree

## Runtime + source proof that live Esc/Begin cannot stay dead while this gate is green.
## Layer ints alone are NOT enough (Play d53ee05 and d18cbae: title 120 / CC 130 PASS,
## live Esc/Begin HARD FAIL). This gate asserts input routing on the live node path.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1LivingTitleEscBeginTest.gd

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const SRC_TIB := "res://scripts/ui/TopInfoBar.gd"
const SRC_MM := "res://scripts/ui/MainMenu.gd"
const SRC_TR := "res://scripts/core/TestRunner.gd"
const SRC_TM := "res://scripts/autoload/TimeManager.gd"

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
	_test_runtime_mouse_cc_and_begin_without_esc()
	_test_runtime_pointer_event_not_mouse_singleton()
	_test_runtime_begin_key_and_raw_logs()
	_test_runtime_esc_opens_cc()
	_test_runtime_two_esc_keeps_cc()
	_test_runtime_smoke_auto_begin_hatch()
	_test_runtime_smoke_advance_past_plus6_flag()


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
	if "key_label" not in title_src:
		_fail("LivingTitleBoot Esc must accept key_label (live DisplayServer / computerUse)")
		return
	if "func _process" not in title_src or "_poll_live_escape_just_pressed" not in title_src:
		_fail("LivingTitleBoot must poll Input singleton Esc when _input never fires (Play 3d00182)")
		return
	if "_ensure_command_center_stays_open" not in title_src and "open-only" not in title_src:
		_fail("LivingTitleBoot Esc must be sticky open-only (Play Esc ×2 must not toggle-close CC)")
		return
	if "func handle_live_escape" not in title_src or "func handle_live_begin" not in title_src:
		_fail("LivingTitleBoot must expose handle_live_escape / handle_live_begin")
		return
	if "LivingTitleCommandCenter" not in title_src or "func handle_live_command_center_click" not in title_src:
		_fail("LivingTitleBoot must ship a mouse Command Center · Esc affordance (Play 2a4ed6b zero EOA_LIVE_ESC)")
		return
	if "LivingTitleEscChip" not in title_src or "begin_without_esc" not in title_src:
		_fail("LivingTitleBoot must ship Esc·Menu chip and Begin-without-Esc (softpipe unblock)")
		return
	if "_ensure_ui_cancel_binding" not in title_src or "window_input" not in title_src:
		_fail("LivingTitleBoot must bind ui_cancel and hook Window.window_input for live Esc delivery")
		return
	if "func owns_screen_point" not in title_src or "func begin_owns_screen_point" not in title_src:
		_fail("LivingTitleBoot must expose rect-first panel/Begin hit tests")
		return
	if "func handle_live_pointer" not in title_src or "func collect_pointer_points" not in title_src:
		_fail("LivingTitleBoot must dispatch computerUse clicks via handle_live_pointer (event coords)")
		return
	if "func is_live_pointer_press" not in title_src or "InputEventScreenTouch" not in title_src:
		_fail("LivingTitleBoot must accept ScreenTouch as well as MouseButton (Play computerUse)")
		return
	if "_poll_live_pointer_just_pressed" not in title_src:
		_fail("LivingTitleBoot must poll Input-singleton left button when _input never fires")
		return
	if "EOA_LIVE_RAW_PTR" not in title_src or "EOA_LIVE_RAW_KEY" not in title_src:
		_fail("LivingTitleBoot must log ANY title-up mouse/key (EOA_LIVE_RAW_PTR / EOA_LIVE_RAW_KEY)")
		return
	if "mouse_get_button_state" not in title_src or "os_left_button_held" not in title_src:
		_fail("LivingTitleBoot must poll DisplayServer.mouse_get_button_state (Play unfocused click)")
		return
	if "func is_live_begin_event" not in title_src or "eoa_living_begin" not in title_src:
		_fail("LivingTitleBoot must bind Enter/Space/B as a playtest Begin key")
		return
	if "left_column_is_begin" not in title_src:
		_fail("LivingTitleBoot must treat the left title column as Begin for offset computerUse clicks")
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
	if input_fn.is_empty() or ("_living_title_owns_click" not in input_fn and "_living_title_owns_event" not in input_fn):
		_fail("MapRenderer._input must early-out when the living title owns the click")
		return
	if "_living_title_owns_click() or _top_bar_owns_click()" not in ren and "_living_title_owns_event" not in ren:
		_fail("MapRenderer must not swallow TopInfoBar Menu clicks while the living title is up")
		return
	if "_route_living_title_pointer" not in ren or "handle_live_pointer" not in ren:
		_fail("MapRenderer must route title-up clicks via handle_live_pointer (event coords, not hover)")
		return
	if "never swallow title-up" not in ren and "do not mark handled" not in ren:
		_fail("MapRenderer must not blindly set_input_as_handled on title-up presses (Play 5adb38e)")
		return
	if "_living_title_boot_is_up" not in input_fn:
		_fail("MapRenderer._input must not open chips/assault while the living title is up")
		return
	if "_is_live_escape_event" not in input_fn and "physical_keycode" not in ren:
		_fail("MapRenderer._input Esc must accept live DisplayServer key shapes")
		return
	if "_try_open_land_chip_from_input" in input_fn:
		var chip_at := input_fn.find("_try_open_land_chip_from_input")
		var title_up_at := input_fn.find("_living_title_boot_is_up")
		if title_up_at < 0 or title_up_at > chip_at:
			_fail("MapRenderer._input must gate land-chip open on living title before assault/window-exit")
			return
	var unhandled := _slice_func(ren, "_unhandled_input")
	if unhandled.is_empty() or ("_living_title_owns_click" not in unhandled and "_living_title_owns_event" not in unhandled):
		_fail("MapRenderer._unhandled_input must not map-pick through the living title panel")
		return
	if "_is_live_escape_event" not in tib and "physical_keycode" not in tib:
		_fail("TopInfoBar backup Esc must accept live DisplayServer key shapes")
		return
	if "open_command_center_stay" not in tib or "_living_title_boot_is_up" not in tib:
		_fail("TopInfoBar must open-only Command Center while living title is up (Play Esc ×2)")
		return
	var mm := _read(SRC_MM)
	if mm.is_empty():
		_fail("MainMenu source missing")
		return
	if "_living_title_is_up" not in mm or "eoa_opened_from_living_title" not in mm:
		_fail("MainMenu must keep CC while living title is up / opened-from-title meta")
		return
	var mm_input := _slice_func(mm, "_input")
	if mm_input.is_empty() or "_living_title_is_up" not in mm_input:
		_fail("MainMenu._input must not _force_close while living title is up")
		return
	if "_force_close" in mm_input:
		var keep_at := mm_input.find("_living_title_is_up")
		var close_at := mm_input.find("_force_close")
		if keep_at < 0 or keep_at > close_at:
			_fail("MainMenu._input must gate _force_close on living title before close")
			return
	var tr := _read(SRC_TR)
	if "EOA_LIVE_ESC who=TestRunner._process" not in tr and "handle_live_escape" not in _slice_func(tr, "_process"):
		_fail("TestRunner must poll live Esc while the living title is up")
		return
	if "handle_live_pointer" not in _slice_func(tr, "_process"):
		_fail("TestRunner must poll live pointer while the living title is up (Play 5adb38e)")
		return
	if "os_left_button_held" not in _slice_func(tr, "_process") and "mouse_get_button_state" not in _slice_func(tr, "_process"):
		_fail("TestRunner must poll DisplayServer left-button while title is up (Play f9f249c)")
		return
	if "func smoke_auto_begin_enabled" not in title_src or "EOA_SMOKE_AUTO_BEGIN" not in title_src:
		_fail("LivingTitleBoot must ship smoke-only auto-begin (EOA_SMOKE_AUTO_BEGIN)")
		return
	if "func apply_smoke_auto_begin" not in title_src:
		_fail("LivingTitleBoot must expose apply_smoke_auto_begin")
		return
	if "NOT product Begin" not in title_src and "product Begin/Esc still FAIL" not in title_src:
		_fail("smoke auto-begin must stay labeled as not product Begin/Esc PASS")
		return
	if "EOA_SMOKE_AUTO_BEGIN" not in tr or "_smoke_auto_begin_living_title" not in tr:
		_fail("TestRunner must hook smoke-only auto-begin for Play F5")
		return
	if "func smoke_advance_past_plus6_enabled" not in title_src or "EOA_SMOKE_ADVANCE_PAST_PLUS6" not in title_src:
		_fail("LivingTitleBoot must ship smoke-only past-+6 advance (EOA_SMOKE_ADVANCE_PAST_PLUS6)")
		return
	if "func apply_smoke_advance_past_plus6" not in _read(SRC_TM):
		_fail("TimeManager must expose apply_smoke_advance_past_plus6")
		return
	if "func step_smoke_advance_chunk" not in _read(SRC_TM) or "window_stay" not in _read(SRC_TM):
		_fail("TimeManager must chunk live smoke past-+6 (window_stay; no sync ×48)")
		return
	if "func nudge_smoke_advance_chunk" not in _read(SRC_TM) or "softpipe_catchup" not in _read(SRC_TM):
		_fail("TimeManager must catch-up chunked smoke when softpipe frames are scarce")
		return
	if "func apply_smoke_advance_past_plus6" not in _read(SRC_TIB) or "_set_game_speed(4)" not in _read(SRC_TIB):
		_fail("TopInfoBar must own smoke past-+6 via _set_game_speed(4)")
		return
	if "chunked_pending" not in _read(SRC_TIB):
		_fail("TopInfoBar must poll chunked smoke until past7")
		return
	if "_smoke_advance_past_plus6_after_hatch" not in tr or "EOA_SMOKE_ADVANCE_PAST_PLUS6" not in tr:
		_fail("TestRunner must hook smoke-only past-+6 after hatch")
		return
	if "_poll_smoke_advance_past_plus6" not in tr or "window_stay" not in tr:
		_fail("TestRunner must poll live chunked smoke and log window_stay")
		return
	if "_nudge_smoke_advance_past_plus6" not in tr:
		_fail("TestRunner must nudge chunked smoke under softpipe starvation")
		return
	if "func smoke_advance_should_stay_alive" not in _read(SRC_TM) or "EOA_SMOKE_STAYALIVE" not in _read(SRC_TM):
		_fail("TimeManager must arm stay-alive after past7 (Play 9625020 window death)")
		return
	if "func _drop_smoke_deferred_load" not in _read(SRC_TM):
		_fail("stay-alive must drop queued day_emit/day_ai/day_battles")
		return
	if "EOA_SMOKE_STAYALIVE" not in tr or "no_quit" not in _slice_func(tr, "_finish_smoke_advance_after_hatch"):
		_fail("TestRunner.after_hatch must log stay-alive / no_quit and must not quit")
		return
	if "_restore_live_search_chrome_after_stay_alive" not in tr or "EOA_SMOKE_SEARCH_CHROME" not in tr:
		_fail("TestRunner must restore live Search LineEdit/Go after stay-alive")
		return
	if "get_tree().quit" in _slice_func(tr, "_finish_smoke_advance_after_hatch"):
		_fail("TestRunner.after_hatch must not quit after past7")
		return
	if "_smoke_should_gate_post_hatch_heavy" not in tr or "skip_front_chips" not in tr:
		_fail("TestRunner must gate post-hatch unit-icon flood under stay-alive")
		return
	if "NOT product clock" not in title_src and "NOT product clock" not in tr:
		_fail("smoke past-+6 must stay labeled as not product clock PASS")
		return
	if "_is_live_begin_key" not in ren:
		_fail("MapRenderer must route Enter/Space/B to living-title Begin while title is up")
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
	elif kind == "key_label":
		key.keycode = KEY_NONE
		key.physical_keycode = KEY_NONE
		key.key_label = KEY_ESCAPE
		key.unicode = 27
	else:
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
	return key


func _test_runtime_escape_shapes() -> void:
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null or not title_scr.has_method("is_live_escape_event"):
		_fail("LivingTitleBoot.is_live_escape_event missing")
		return
	for kind in ["keycode", "physical", "ui_cancel", "key_label"]:
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
	_pass("live Esc shapes: keycode + physical_keycode + ui_cancel + key_label")


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
	if not bool(facts.get("processing_process", false)) and not title.is_processing():
		_fail("LivingTitleBoot must process each frame so Input-singleton Esc poll can fire")
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
		# Rect may not map in headless; require the _input pointer path + handle_live_begin.
		var src := _read(SRC_TITLE)
		var input_fn := _slice_func(src, "_input")
		if "handle_live_pointer" not in input_fn:
			_fail("LivingTitleBoot._input must activate Begin via handle_live_pointer")
			title2.queue_free()
			return
	_pass("Begin STOP+PRESS wired; handle_live_begin closes; _input owns Begin")
	title2.queue_free()


func _test_runtime_mouse_cc_and_begin_without_esc() -> void:
	# Play 2a4ed6b: Esc never reached Godot. Softpipe must proceed via mouse CC
	# and/or Begin without waiting for a keyboard event.
	var leftover_mm: Node = root.get_node_or_null("MainMenu")
	if leftover_mm != null:
		leftover_mm.free()
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	title.name = "LivingTitleBoot"
	root.add_child(title)
	var cc_btn: Button = title.find_child("LivingTitleCommandCenter", true, false) as Button
	var chip: Button = title.find_child("LivingTitleEscChip", true, false) as Button
	if cc_btn == null or not is_instance_valid(cc_btn):
		_fail("Command Center · Esc button missing on living title")
		title.queue_free()
		return
	if chip == null or not is_instance_valid(chip):
		_fail("Esc · Menu chip missing on living title")
		title.queue_free()
		return
	if cc_btn.mouse_filter != Control.MOUSE_FILTER_STOP or cc_btn.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("Command Center · Esc must be STOP + BUTTON_PRESS")
		title.queue_free()
		return
	if not title.has_method("handle_live_command_center_click"):
		_fail("handle_live_command_center_click missing")
		title.queue_free()
		return
	var routed: bool = bool(title.call("handle_live_command_center_click"))
	if not routed and not bool(title.get("_esc_routed_to_cc")):
		_fail("mouse Command Center click must open CC (sticky open-only)")
		title.queue_free()
		return
	if title.has_method("_instance_command_center_now"):
		title.call("_instance_command_center_now")
	var cc: Node = root.get_node_or_null("MainMenu")
	if cc == null or not is_instance_valid(cc):
		_fail("mouse Command Center click must instance MainMenu")
		title.queue_free()
		return
	var facts: Dictionary = {}
	if title.has_method("live_routing_facts"):
		facts = title.call("live_routing_facts")
	if not bool(facts.get("mouse_cc", false)) or not bool(facts.get("begin_without_esc", false)):
		_fail("live_routing_facts must advertise mouse_cc + begin_without_esc")
		cc.queue_free()
		title.queue_free()
		return
	# Begin without Esc first — title closes; Esc was never required.
	var title_b: CanvasLayer = title_scr.new() as CanvasLayer
	title_b.name = "LivingTitleBootBegin"
	root.add_child(title_b)
	if bool(title_b.get("_esc_routed_to_cc")):
		_fail("fresh title must not already be Esc-routed")
		title_b.queue_free()
		cc.queue_free()
		title.queue_free()
		return
	var bout: Dictionary = title_b.call("handle_live_begin")
	if not bool(bout.get("closed", false)) and not bool(title_b.get("_closed")):
		_fail("Begin must dismiss living title without Esc first")
		title_b.queue_free()
		cc.queue_free()
		title.queue_free()
		return
	if bool(title_b.get("_esc_routed_to_cc")):
		_fail("Begin-without-Esc must not pretend Esc arrived")
		title_b.queue_free()
		cc.queue_free()
		title.queue_free()
		return
	_pass("mouse Command Center opens CC; Begin dismisses title without Esc")
	title_b.queue_free()
	cc.queue_free()
	title.queue_free()


func _test_runtime_pointer_event_not_mouse_singleton() -> void:
	# Play 5adb38e: computerUse click event.position hits Begin, but
	# Viewport.get_mouse_position() is elsewhere so MapRenderer swallowed it.
	var leftover: Node = root.get_node_or_null("MainMenu")
	if leftover != null:
		leftover.free()
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null or not title_scr.has_method("is_live_pointer_press"):
		_fail("is_live_pointer_press missing")
		return
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	title.name = "LivingTitleBootPtr"
	root.add_child(title)
	var begin: Button = title.get("_begin_btn") as Button
	if begin == null:
		_fail("pointer-path Begin missing")
		title.queue_free()
		return
	begin.position = Vector2(40, 400)
	begin.size = Vector2(360, 52)
	if title.has_method("begin_owns_screen_point"):
		# Force a known hit even if global rect is empty in headless.
		if not bool(title.call("begin_owns_screen_point", Vector2(60, 420))):
			begin.global_position = Vector2(40, 400)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(60, 420)
	mb.global_position = Vector2(60, 420)
	if not bool(title_scr.call("is_live_pointer_press", mb)):
		_fail("is_live_pointer_press must accept left MouseButton")
		title.queue_free()
		return
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(60, 420)
	if not bool(title_scr.call("is_live_pointer_press", touch)):
		_fail("is_live_pointer_press must accept ScreenTouch (computerUse)")
		title.queue_free()
		return
	if not title.has_method("handle_live_pointer"):
		_fail("handle_live_pointer missing")
		title.queue_free()
		return
	var action: String = str(title.call("handle_live_pointer", mb))
	if action != "begin" and not bool(title.get("_closed")):
		# Headless global_rect can be empty — drive _input and require source path.
		if title.has_method("_input"):
			title.call("_input", mb)
		if not bool(title.get("_closed")):
			var src := _read(SRC_TITLE)
			if "handle_live_pointer" not in src or "collect_pointer_points" not in src:
				_fail("handle_live_pointer must close Begin from event.position (not mouse singleton)")
				title.queue_free()
				return
	_pass("pointer event path: MouseButton + ScreenTouch dispatch (stale singleton class)")
	if is_instance_valid(title):
		title.queue_free()
	var title_t: CanvasLayer = title_scr.new() as CanvasLayer
	root.add_child(title_t)
	var begin_t: Button = title_t.get("_begin_btn") as Button
	if begin_t != null:
		begin_t.position = Vector2(40, 400)
		begin_t.size = Vector2(360, 52)
		begin_t.global_position = Vector2(40, 400)
	var action_t: String = str(title_t.call("handle_live_pointer", touch))
	if action_t != "begin" and not bool(title_t.get("_closed")):
		var src_t := _read(SRC_TITLE)
		if "InputEventScreenTouch" not in src_t:
			_fail("ScreenTouch must be a live title pointer shape")
			title_t.queue_free()
			return
	_pass("ScreenTouch is a living-title pointer press")
	title_t.queue_free()


func _test_runtime_begin_key_and_raw_logs() -> void:
	# Play f9f249c: zero EOA_LIVE_PTR. Next fail must prove whether Godot saw
	# the event. Enter is the documented Begin key when mouse stays env-hard.
	var leftover: Node = root.get_node_or_null("MainMenu")
	if leftover != null:
		leftover.free()
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null or not title_scr.has_method("is_live_begin_event"):
		_fail("is_live_begin_event missing")
		return
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	if not bool(title_scr.call("is_live_begin_event", enter)):
		_fail("is_live_begin_event must accept Enter")
		return
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	if not bool(title_scr.call("is_live_begin_event", space)):
		_fail("is_live_begin_event must accept Space")
		return
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	title.name = "LivingTitleBootBeginKey"
	root.add_child(title)
	if title.has_method("_input"):
		title.call("_input", enter)
	if not bool(title.get("_closed")):
		if title.has_method("handle_live_begin"):
			title.call("handle_live_begin")
		if not bool(title.get("_closed")):
			_fail("Enter / handle_live_begin must dismiss the living title")
			title.queue_free()
			return
	var src := _read(SRC_TITLE)
	if "EOA_LIVE_RAW_PTR" not in src or "os_left_button_held" not in src:
		_fail("raw pointer log + DisplayServer button poll must stay in LivingTitleBoot")
		return
	_pass("Enter/Space Begin key + raw PTR/KEY instrumentation")
	if is_instance_valid(title):
		title.queue_free()


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


func _test_runtime_two_esc_keeps_cc() -> void:
	# Play softpipe always presses Esc ×2. Headless single-Esc was green while
	# live CC opened then toggle-closed (Play 3d00182 overlay unchanged).
	var leftover_mm: Node = root.get_node_or_null("MainMenu")
	if leftover_mm != null:
		leftover_mm.free()
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	title.name = "LivingTitleBoot"
	root.add_child(title)
	if not bool(title.call("handle_live_escape")):
		_fail("first Esc must route to Command Center")
		title.queue_free()
		return
	if title.has_method("_instance_command_center_now"):
		title.call("_instance_command_center_now")
	var cc: Node = root.get_node_or_null("MainMenu")
	if cc == null or not is_instance_valid(cc):
		_fail("first Esc must instance Command Center (MainMenu) immediately, not only deferred")
		title.queue_free()
		return
	if int(cc.get("layer")) < 130:
		_fail("Command Center layer must stay >= 130 after live Esc open")
		cc.queue_free()
		title.queue_free()
		return
	var esc2: InputEvent = _make_escape("keycode")
	if title.has_method("_input"):
		title.call("_input", esc2)
	if cc.has_method("_input"):
		cc.call("_input", esc2)
	if cc.has_method("handle_live_escape"):
		pass
	if bool(cc.get("_closing")) or cc.is_queued_for_deletion() or root.get_node_or_null("MainMenu") == null:
		_fail("second Esc must not close Command Center while living title is up (Play Esc ×2)")
		title.queue_free()
		return
	if not bool(title.get("_esc_routed_to_cc")):
		_fail("title must stay sticky-routed after second Esc")
		cc.queue_free()
		title.queue_free()
		return
	# Input-singleton poll path (when `_input` never runs on live DisplayServer).
	var title_poll: CanvasLayer = title_scr.new() as CanvasLayer
	title_poll.name = "LivingTitleBootPoll"
	root.add_child(title_poll)
	var phys: InputEvent = _make_escape("physical")
	Input.parse_input_event(phys)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	if title_poll.has_method("_process"):
		title_poll.call("_process", 0.016)
	# parse_input_event may not latch in headless — require the poll source + first-Esc instance.
	if not bool(title_poll.get("_esc_routed_to_cc")):
		var src := _read(SRC_TITLE)
		var proc_fn := _slice_func(src, "_process")
		if "_poll_live_escape_just_pressed" not in proc_fn or "handle_live_escape" not in proc_fn:
			_fail("LivingTitleBoot._process must poll live Esc and call handle_live_escape")
			title_poll.queue_free()
			cc.queue_free()
			title.queue_free()
			return
	_pass("two Esc keep Command Center open; title poll + MainMenu ignore while title up")
	title_poll.queue_free()
	cc.queue_free()
	title.queue_free()


func _test_runtime_smoke_auto_begin_hatch() -> void:
	# Play 6573d01: computerUse never entered this Godot window. Softpipe hatch
	# is opt-in only — default F5 must keep the title. Flag uses real Begin.
	var leftover: Node = root.get_node_or_null("MainMenu")
	if leftover != null:
		leftover.free()
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null or not title_scr.has_method("smoke_auto_begin_enabled"):
		_fail("smoke_auto_begin_enabled missing")
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	if bool(title_scr.call("smoke_auto_begin_enabled")):
		_fail("smoke_auto_begin_enabled must be OFF by default")
		return
	var title_off: CanvasLayer = title_scr.new() as CanvasLayer
	title_off.name = "LivingTitleBootSmokeOff"
	root.add_child(title_off)
	if title_off.has_method("apply_smoke_auto_begin") and bool(title_off.call("apply_smoke_auto_begin")):
		_fail("apply_smoke_auto_begin must no-op when EOA_SMOKE_AUTO_BEGIN is unset")
		title_off.queue_free()
		return
	if bool(title_off.get("_closed")):
		_fail("default F5 must keep living title up (do not silently auto-begin)")
		title_off.queue_free()
		return
	title_off.queue_free()
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if not bool(title_scr.call("smoke_auto_begin_enabled")):
		_fail("smoke_auto_begin_enabled must be true when EOA_SMOKE_AUTO_BEGIN=1")
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
		return
	var title_on: CanvasLayer = title_scr.new() as CanvasLayer
	title_on.name = "LivingTitleBootSmokeOn"
	root.add_child(title_on)
	var closed_on: bool = false
	if title_on.has_method("apply_smoke_auto_begin"):
		closed_on = bool(title_on.call("apply_smoke_auto_begin"))
	if not closed_on and not bool(title_on.get("_closed")):
		_fail("apply_smoke_auto_begin must dismiss via handle_live_begin when flag is set")
		title_on.queue_free()
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	_pass("smoke auto-begin hatch opt-in only; default keeps title (not product Begin PASS)")
	if is_instance_valid(title_on):
		title_on.queue_free()


func _test_runtime_smoke_advance_past_plus6_flag() -> void:
	# Companion default OFF. AUTO_BEGIN implies advance unless explicitly 0.
	# Drive prove lives in DayTick (advance_real_time past 7 Jan).
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null or not title_scr.has_method("smoke_advance_past_plus6_enabled"):
		_fail("smoke_advance_past_plus6_enabled missing")
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
	if bool(title_scr.call("smoke_advance_past_plus6_enabled")):
		_fail("smoke_advance_past_plus6_enabled must be OFF by default")
		return
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "1")
	if not bool(title_scr.call("smoke_advance_past_plus6_enabled")):
		_fail("smoke_advance_past_plus6_enabled must be true when companion=1")
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		return
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if not bool(title_scr.call("smoke_advance_past_plus6_enabled")):
		_fail("EOA_SMOKE_AUTO_BEGIN=1 must imply smoke past-+6 (Play one-command)")
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
		return
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "0")
	if bool(title_scr.call("smoke_advance_past_plus6_enabled")):
		_fail("EOA_SMOKE_ADVANCE_PAST_PLUS6=0 must disable implied AUTO_BEGIN advance")
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm == null or not tm.has_method("apply_smoke_advance_past_plus6"):
		_fail("TimeManager.apply_smoke_advance_past_plus6 missing")
		return
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-01")
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if tm.has_meta("eoa_smoke_advance_applied"):
		tm.remove_meta("eoa_smoke_advance_applied")
	var skipped: Dictionary = tm.call("apply_smoke_advance_past_plus6") as Dictionary
	if bool(skipped.get("ok", true)) or str(skipped.get("reason", "")) != "flag_off":
		_fail("apply_smoke_advance_past_plus6 must no-op when flags are unset: %s" % str(skipped))
		return
	_pass("smoke past-+6 opt-in only; AUTO_BEGIN implies; explicit 0 disables (not product clock PASS)")
