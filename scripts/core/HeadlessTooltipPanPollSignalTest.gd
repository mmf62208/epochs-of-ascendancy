extends SceneTree

## TOOLTIP-P1 FIX #2 — real process_frame invocation, not a helper-only tick.
##
## FIX #1 connected `_poll_tooltip_pan.bind(pop)` to SceneTree.process_frame.
## If that bound PopupPanel dies without a successful disconnect (engine
## tooltip memdelete / tree_exiting hook dropped / stop sees an invalid
## Object), every later frame logs:
##   Error calling from signal 'process_frame' to callable:
##   'GDScript::_poll_tooltip_pan': Cannot convert argument 1 from Object to Object.
## HeadlessTooltipPanPollTest still PASSed on that tip because it only
## drove `_start` while the node stayed valid. This test reproduces the
## leftover-bind invocation, then requires the product poll to survive it.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessTooltipPanPollSignalTest.gd
##
## The gate wrapper must also fail on engine ERROR / SCRIPT ERROR. Headless
## is NOT live Play.

const THEME_SRC := "res://scripts/ui/RetrowaveTheme.gd"
const PAN_POLL_FRAMES := 300
const PAN_POLL_SLACK := 8
const PAN_POLL_MIN := PAN_POLL_FRAMES - PAN_POLL_SLACK
const PAN_POLL_MAX := PAN_POLL_FRAMES + PAN_POLL_SLACK
const LIVE_TIP := "# Fill is not Strength\nFill 0% — Fill is not Strength.\n[1] · [2] · [3] · [4] · [Del] · [Ctrl+Click]"
const MAP_TIP := "# Rhineland\nSteel 12 · coal 4\n[Click] select"
const UNIT_TIP := "# GER Division\nFill 0% · men 7200\n[Click] select · [Ctrl+Click] attack"

var _failures: int = 0
var _cam: Camera2D = null
var _theme = null
var _awaited_frames: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessTooltipPanPollSignalTest: awaited_frames=", _awaited_frames)
	print("HeadlessTooltipPanPollSignalTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessTooltipPanPollSignalTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessTooltipPanPollSignalTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessTooltipPanPollSignalTest: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _func_body(src: String, func_name: String) -> String:
	var lines := src.split("\n")
	var prefix := "static func %s(" % func_name
	var start := -1
	for i in lines.size():
		if lines[i].begins_with(prefix):
			start = i
			break
	if start < 0:
		return ""
	var body := ""
	for j in range(start, lines.size()):
		if j > start:
			var line: String = lines[j]
			if line.begins_with("static func ") or line.begins_with("func "):
				break
		body += lines[j] + "\n"
	return body


func _await_frames(n: int) -> void:
	for _i in n:
		await process_frame
		_awaited_frames += 1


func _ticks(pop: PopupPanel) -> int:
	if pop == null or not is_instance_valid(pop):
		return -1
	return int(pop.get_meta("eoa_tooltip_pan_poll_ticks", 0))


func _drop_tree_exiting(pop: PopupPanel) -> int:
	var n := 0
	if pop == null or not is_instance_valid(pop):
		return 0
	var conns: Array = pop.tree_exiting.get_connections()
	for c in conns:
		var cb: Callable = c.get("callable", Callable())
		if pop.tree_exiting.is_connected(cb):
			pop.tree_exiting.disconnect(cb)
			n += 1
	return n


func _make_tip(text: String) -> PopupPanel:
	var pop := PopupPanel.new()
	pop.theme_type_variation = "TooltipPanel"
	var lab := Label.new()
	lab.theme_type_variation = "TooltipLabel"
	lab.text = text
	pop.add_child(lab)
	root.add_child(pop)
	_theme.call("dress_tooltip_popup", pop)
	pop.popup(Rect2i(24, 24, 260, 96))
	if not pop.visible:
		pop.visible = true
	return pop


func _dressed_ok(pop: PopupPanel, want_title: String, want_del: bool) -> bool:
	if pop == null or not is_instance_valid(pop):
		return false
	if not bool(pop.get_meta("eoa_tooltip_dressed", false)):
		return false
	var title := pop.find_child("EoaTooltipTitle", true, false) as Label
	if title == null or title.text != want_title:
		return false
	if pop.find_child("EoaTooltipRule", true, false) == null:
		return false
	if pop.find_child("EoaHotkeyRow", true, false) == null:
		return false
	var row := pop.find_child("EoaHotkeyRow", true, false)
	if row == null:
		return false
	if not want_del:
		return true
	var found_del := false
	var found_ctrl := false
	for chip in row.get_children():
		for child in chip.get_children():
			if child is Label:
				var t := (child as Label).text
				if t.contains("Del"):
					found_del = true
				if t.contains("Ctrl+Click"):
					found_ctrl = true
	return found_del and found_ctrl


func _run() -> void:
	print(
		"HeadlessTooltipPanPollSignalTest: ASSERTION real process_frame, dressed tips, leftover-bind death, ticks in [%d, %d] over %d frames"
		% [PAN_POLL_MIN, PAN_POLL_MAX, PAN_POLL_FRAMES]
	)
	if not _test_source_guards():
		return
	_theme = load(THEME_SRC)
	if _theme == null:
		_fail("RetrowaveTheme missing")
		return
	_theme.call("install_tooltip_theme", self)
	_cam = Camera2D.new()
	_cam.name = "SignalPanCam"
	root.add_child(_cam)
	_cam.global_position = Vector2.ZERO
	_cam.make_current()
	await _test_leftover_bind_death()
	await _test_dressed_300_and_cycle()
	await _test_two_tips_hide_reopen()
	await _test_pan_null_cam_free()
	_test_no_leftover_binds()


func _test_source_guards() -> bool:
	var src := _read(THEME_SRC)
	if src.is_empty():
		_fail("RetrowaveTheme source missing")
		return false
	var poll := _func_body(src, "_poll_tooltip_pan")
	var starter := _func_body(src, "_start_tooltip_pan_poll")
	var arm := _func_body(src, "_arm_tooltip_pan_clear")
	if poll.is_empty() or starter.is_empty() or arm.is_empty():
		_fail("pan poll helpers missing")
		return false
	if poll.count("call_deferred") > 0 or arm.count("call_deferred") > 0:
		_fail("call_deferred reintroduced in _poll_tooltip_pan / _arm_tooltip_pan_clear")
		return false
	if "process_frame" not in starter:
		_fail("_start_tooltip_pan_poll is not process_frame-driven")
		return false
	if "_poll_tooltip_pan.bind" in starter:
		_fail("FIX #1 leftover: _start binds _poll_tooltip_pan(PopupPanel) onto process_frame")
		return false
	var first := ""
	for line in poll.split("\n"):
		if line.begins_with("static func _poll_tooltip_pan("):
			first = line
			break
	if "PopupPanel" in first or "Object" in first:
		_fail("_poll_tooltip_pan still takes a typed Object first arg: %s" % first)
		return false
	_pass("zero-arg process_frame poll; no PopupPanel bind; no call_deferred loop")
	return true


func _test_leftover_bind_death() -> void:
	var pop := _make_tip(LIVE_TIP)
	if not _dressed_ok(pop, "Fill is not Strength", true):
		_fail("live-style tip missing title/rule/Del/Ctrl+Click chrome")
		pop.free()
		return
	_theme.call("_arm_tooltip_pan_clear", pop)
	if bool(_theme.call("tooltip_pan_poll_active", pop)):
		_fail("headless _arm_tooltip_pan_clear armed the pan poll")
		_theme.call("_stop_tooltip_pan_poll", pop)
		pop.free()
		return
	_theme.call("_start_tooltip_pan_poll", pop)
	if not bool(_theme.call("tooltip_pan_poll_active", pop)):
		_fail("product _start did not arm the real process_frame poll")
		pop.free()
		return
	if int(_theme.call("tooltip_pan_poll_bound_object_count", self)) != 0:
		_fail("product process_frame poll still binds an Object")
		pop.free()
		return
	await _await_frames(1)
	var dropped := _drop_tree_exiting(pop)
	if dropped < 1:
		_fail("product _start did not hook tree_exiting (cannot simulate memdelete)")
		pop.free()
		return
	var id := pop.get_instance_id()
	pop.free()
	await _await_frames(20)
	if bool(_theme.call("tooltip_pan_poll_tracked", id)):
		_fail("freed tip left a tracked poll after 20 process_frames (FIX #1 leftover bind)")
	elif bool(_theme.call("tooltip_pan_poll_process_frame_connected", self)):
		_fail("process_frame poll still connected after the last tip was freed")
	elif int(_theme.call("tooltip_pan_poll_bound_object_count", self)) != 0:
		_fail("bound Object leftover on process_frame after free")
	else:
		_pass("leftover-bind death: 20 process_frames after freed tip, no tracked poll / no bound Object")


func _test_dressed_300_and_cycle() -> void:
	var pop := _make_tip(LIVE_TIP)
	if not _dressed_ok(pop, "Fill is not Strength", true):
		_fail("300-frame tip lost Fill/Del chrome")
		pop.free()
		return
	_theme.call("_start_tooltip_pan_poll", pop)
	var max_delta := 0
	var prev := _ticks(pop)
	for _i in PAN_POLL_FRAMES:
		await _await_frames(1)
		var now := _ticks(pop)
		max_delta = maxi(max_delta, now - prev)
		prev = now
	if not bool(_theme.call("tooltip_pan_poll_active", pop)):
		_fail("poll stopped during the 300-frame dressed soak ticks=%d" % prev)
	elif max_delta > 1:
		_fail("poll ran %d times in one frame (cap is 1); ticks=%d" % [max_delta, prev])
	elif prev < PAN_POLL_MIN or prev > PAN_POLL_MAX:
		_fail("ticks=%d over %d frames want [%d, %d]" % [prev, PAN_POLL_FRAMES, PAN_POLL_MIN, PAN_POLL_MAX])
	else:
		_pass("dressed soak ticks=%d max_per_frame=%d over %d process_frames" % [prev, max_delta, PAN_POLL_FRAMES])
	pop.hide()
	await _await_frames(1)
	var after_hide := _ticks(pop)
	if bool(_theme.call("tooltip_pan_poll_active", pop)) or bool(pop.get_meta("eoa_tooltip_pan_poll", false)):
		_fail("hide left the process_frame poll connected")
	else:
		var grew := false
		for _j in 20:
			await _await_frames(1)
			if _ticks(pop) != after_hide:
				grew = true
				break
		if grew:
			_fail("poll kept ticking after hide")
		else:
			_pass("hide stopped the real process_frame poll at %d" % after_hide)
	pop.visible = true
	_theme.call("_start_tooltip_pan_poll", pop)
	await _await_frames(3)
	if not bool(_theme.call("tooltip_pan_poll_active", pop)):
		_fail("reopen did not re-arm process_frame")
	elif _ticks(pop) < 1:
		_fail("reopen armed but process_frame did not tick")
	else:
		_pass("hide then reopen re-armed process_frame ticks=%d" % _ticks(pop))
	_theme.call("_stop_tooltip_pan_poll", pop)
	pop.free()


func _test_two_tips_hide_reopen() -> void:
	var a := _make_tip(MAP_TIP)
	var b := _make_tip(UNIT_TIP)
	if not _dressed_ok(a, "Rhineland", false) or not bool(b.get_meta("eoa_tooltip_dressed", false)):
		_fail("map/unit tips did not dress")
		a.free()
		b.free()
		return
	_theme.call("_start_tooltip_pan_poll", a)
	_theme.call("_start_tooltip_pan_poll", b)
	await _await_frames(4)
	var ta := _ticks(a)
	var tb := _ticks(b)
	if ta < 3 or tb < 3:
		_fail("two open tips did not both receive process_frame ticks a=%d b=%d" % [ta, tb])
	elif int(_theme.call("tooltip_pan_poll_bound_object_count", self)) != 0:
		_fail("two-tip poll bound an Object")
	else:
		_pass("two dressed tips ticked on one process_frame callback a=%d b=%d" % [ta, tb])
	a.hide()
	await _await_frames(2)
	var tb2 := _ticks(b)
	if bool(_theme.call("tooltip_pan_poll_active", a)):
		_fail("hiding tip A left it armed")
	elif not bool(_theme.call("tooltip_pan_poll_active", b)):
		_fail("hiding tip A dropped tip B's poll")
	elif _ticks(b) <= tb:
		_fail("tip B stopped ticking after A hid")
	else:
		_pass("one of two tips hidden; B still ticks=%d" % tb2)
	_theme.call("_stop_tooltip_pan_poll", b)
	a.free()
	b.free()
	await _await_frames(2)
	if bool(_theme.call("tooltip_pan_poll_process_frame_connected", self)):
		_fail("process_frame still connected after both tips were freed")


func _test_pan_null_cam_free() -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera2D.new()
		root.add_child(_cam)
		_cam.make_current()
	_cam.global_position = Vector2.ZERO
	var pop := _make_tip(MAP_TIP)
	_theme.call("_start_tooltip_pan_poll", pop)
	await _await_frames(1)
	if not pop.has_meta("eoa_tooltip_cam_pose"):
		_fail("first real process_frame did not record camera pose")
		pop.free()
		return
	var pose: Vector2 = pop.get_meta("eoa_tooltip_cam_pose")
	_cam.global_position = pose + Vector2(40, 0)
	await _await_frames(1)
	var frozen := _ticks(pop)
	if pop.visible:
		_fail("pan left the dressed tip visible")
	elif bool(_theme.call("tooltip_pan_poll_process_frame_connected", self)):
		_fail("pan-clear left process_frame connected")
	else:
		_pass("pan cleared the dressed tip and disconnected process_frame ticks=%d" % frozen)
	if is_instance_valid(pop):
		pop.free()
	_cam.global_position = Vector2.ZERO
	var pop2 := _make_tip(UNIT_TIP)
	_theme.call("_start_tooltip_pan_poll", pop2)
	await _await_frames(1)
	_cam.free()
	_cam = null
	await _await_frames(2)
	if bool(_theme.call("tooltip_pan_poll_active", pop2)) or bool(pop2.get_meta("eoa_tooltip_pan_poll", false)):
		_fail("freed camera left the process_frame poll running")
	else:
		_pass("freed/null camera stopped the process_frame poll")
	var id := pop2.get_instance_id()
	pop2.free()
	await _await_frames(4)
	if bool(_theme.call("tooltip_pan_poll_tracked", id)) or bool(_theme.call("tooltip_pan_poll_process_frame_connected", self)):
		_fail("normal free left a process_frame poll")
	else:
		_pass("normal free dropped the process_frame poll")
	_cam = Camera2D.new()
	root.add_child(_cam)
	_cam.global_position = Vector2.ZERO
	_cam.make_current()


func _test_no_leftover_binds() -> void:
	if int(_theme.call("tooltip_pan_poll_bound_object_count", self)) != 0:
		_fail("process_frame still has bound Objects on _poll_tooltip_pan")
	elif bool(_theme.call("tooltip_pan_poll_process_frame_connected", self)):
		_fail("process_frame poll still connected after the suite")
	else:
		_pass("no process_frame binds or leftover poll connections")
