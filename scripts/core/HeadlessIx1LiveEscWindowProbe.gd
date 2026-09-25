extends SceneTree

## Lean windowed DisplayServer Esc probe — no 3520 board (avoids F5 OOM 137).
##   DISPLAY=:1 tools/run_godot.sh --path . -s res://scripts/core/HeadlessIx1LiveEscWindowProbe.gd
## Not a substitute for Play computerUse on TestScenario. Proves windowed Esc
## reaches title + two Esc keep Command Center (the 3d00182 live hole).

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessIx1LiveEscWindowProbe: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessIx1LiveEscWindowProbe: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessIx1LiveEscWindowProbe: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessIx1LiveEscWindowProbe: RESULT=", "PASS" if ok else "FAIL")
	print("HeadlessIx1LiveEscWindowProbe: displayserver=", DisplayServer.get_name())
	quit(0 if ok else 1)


func _make_escape() -> InputEventKey:
	var key := InputEventKey.new()
	key.pressed = true
	key.echo = false
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.key_label = KEY_ESCAPE
	return key


func _run() -> void:
	var ds := DisplayServer.get_name()
	print("HeadlessIx1LiveEscWindowProbe: DisplayServer=", ds)
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot missing")
		return
	var title: CanvasLayer = title_scr.new() as CanvasLayer
	title.name = "LivingTitleBoot"
	root.add_child(title)
	if not bool(title.call("handle_live_escape")):
		_fail("first Esc must open Command Center")
		return
	var cc: Node = root.get_node_or_null("MainMenu")
	if cc == null:
		if title.has_method("_instance_command_center_now"):
			title.call("_instance_command_center_now")
		cc = root.get_node_or_null("MainMenu")
	if cc == null:
		_fail("Command Center missing after first Esc")
		return
	var esc2: InputEvent = _make_escape()
	if title.has_method("_input"):
		title.call("_input", esc2)
	if cc.has_method("_input"):
		cc.call("_input", esc2)
	if bool(cc.get("_closing")) or cc.is_queued_for_deletion() or root.get_node_or_null("MainMenu") == null:
		_fail("second Esc closed Command Center on windowed DisplayServer")
		return
	# Input-singleton poll (computerUse / focus miss class).
	Input.parse_input_event(_make_escape())
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	if title.has_method("_process"):
		title.call("_process", 0.016)
	if root.get_node_or_null("MainMenu") == null or bool(cc.get("_closing")):
		_fail("process-poll Esc closed Command Center")
		return
	_pass("windowed DisplayServer=%s two Esc keep CC; poll stay" % ds)
	# Mouse CC + Begin-without-Esc (Play 2a4ed6b: Esc never entered Godot).
	var leftover2: Node = root.get_node_or_null("MainMenu")
	if leftover2 != null:
		leftover2.free()
	var title_m: CanvasLayer = title_scr.new() as CanvasLayer
	title_m.name = "LivingTitleBootMouse"
	root.add_child(title_m)
	var cc_btn: Button = title_m.find_child("LivingTitleCommandCenter", true, false) as Button
	var chip: Button = title_m.find_child("LivingTitleEscChip", true, false) as Button
	if cc_btn == null or chip == null:
		_fail("mouse Command Center · Esc / Esc · Menu chip missing")
		return
	if not bool(title_m.call("handle_live_command_center_click")) and not bool(title_m.get("_esc_routed_to_cc")):
		_fail("mouse Command Center click must open CC")
		return
	if title_m.has_method("_instance_command_center_now"):
		title_m.call("_instance_command_center_now")
	if root.get_node_or_null("MainMenu") == null:
		_fail("mouse Command Center click must instance MainMenu")
		return
	var title_b: CanvasLayer = title_scr.new() as CanvasLayer
	root.add_child(title_b)
	var bout: Dictionary = title_b.call("handle_live_begin")
	if not bool(bout.get("closed", false)) and not bool(title_b.get("_closed")):
		_fail("Begin must dismiss title without Esc first")
		return
	if title_m.has_method("handle_live_pointer"):
		var title_p: CanvasLayer = title_scr.new() as CanvasLayer
		root.add_child(title_p)
		var begin_p: Button = title_p.get("_begin_btn") as Button
		if begin_p != null:
			begin_p.position = Vector2(40, 400)
			begin_p.size = Vector2(360, 52)
			begin_p.global_position = Vector2(40, 400)
		var mb_p := InputEventMouseButton.new()
		mb_p.button_index = MOUSE_BUTTON_LEFT
		mb_p.pressed = true
		mb_p.position = Vector2(60, 420)
		mb_p.global_position = Vector2(60, 420)
		var pact: String = str(title_p.call("handle_live_pointer", mb_p))
		if pact != "begin" and not bool(title_p.get("_closed")):
			print("HeadlessIx1LiveEscWindowProbe: NOTE handle_live_pointer headless rect miss — source path required")
		if is_instance_valid(title_p):
			title_p.queue_free()
	_pass("mouse CC + Begin-without-Esc on DisplayServer=%s" % ds)
	if ds == "headless":
		print("HeadlessIx1LiveEscWindowProbe: NOTE headless — not a live F5/computerUse proof")
		print("HeadlessIx1LiveEscWindowProbe: Play path if zero EOA_LIVE_ESC: click Esc · Menu or Begin, then continue softpipe")
	if is_instance_valid(title_b):
		title_b.queue_free()
	if is_instance_valid(title_m):
		title_m.queue_free()
	if is_instance_valid(title):
		title.queue_free()
	if is_instance_valid(cc):
		cc.queue_free()
	var mm2: Node = root.get_node_or_null("MainMenu")
	if mm2 != null and is_instance_valid(mm2):
		mm2.queue_free()
