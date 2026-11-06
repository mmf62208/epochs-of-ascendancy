extends SceneTree

## TOOLTIP-P1 pan poll must stay bounded.
##
## Assertion (documented):
## 1. Synthetic detector: the bodies of `_poll_tooltip_pan` and
##    `_arm_tooltip_pan_clear` must not contain `call_deferred`. On tip
##    c9639f2b both functions re-queue `_poll_tooltip_pan.call_deferred(pop)`
##    with no per-frame cap (MessageQueue OOM / SIGSEGV). That detector
##    fails the run before the live poll is armed, so the old self-loop
##    cannot hang the process.
## 2. Runtime bound: drive `_start_tooltip_pan_poll` directly (headless
##    `_arm_tooltip_pan_clear` still returns early). Over 300 `process_frame`
##    awaits with a visible tip and a live Camera2D, meta
##    `eoa_tooltip_pan_poll_ticks` must land in [292, 308] and the per-frame
##    delta must be <= 1. That is at most one poll per frame, plus 8 frames
##    of slack.
## 3. `hide()` clears meta `eoa_tooltip_pan_poll` and the tick count does
##    not move across 30 further frames. A null camera stops the same way.
##    A pan that `tooltip_should_clear_for_pan` accepts hides the tip and
##    stops. Freeing the tip drops the tracked callback.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessTooltipPanPollTest.gd
##
## Does not load the world map. Headless is NOT live Play.

const THEME_SRC := "res://scripts/ui/RetrowaveTheme.gd"
const PAN_POLL_FRAMES := 300
const PAN_POLL_SLACK := 8
const PAN_POLL_MIN := PAN_POLL_FRAMES - PAN_POLL_SLACK
const PAN_POLL_MAX := PAN_POLL_FRAMES + PAN_POLL_SLACK

var _failures: int = 0
var _cam: Camera2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessTooltipPanPollTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessTooltipPanPollTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessTooltipPanPollTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessTooltipPanPollTest: ", msg)


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


func _run() -> void:
	print(
		"HeadlessTooltipPanPollTest: ASSERTION ticks in [%d, %d] over %d frames, per-frame delta <= 1; no call_deferred in _poll_tooltip_pan / _arm_tooltip_pan_clear"
		% [PAN_POLL_MIN, PAN_POLL_MAX, PAN_POLL_FRAMES]
	)
	if not _test_no_self_defer_loop():
		return
	var theme := load(THEME_SRC)
	if theme == null:
		_fail("RetrowaveTheme missing")
		return
	theme.call("install_tooltip_theme", self)
	_cam = Camera2D.new()
	_cam.name = "PanPollCam"
	root.add_child(_cam)
	_cam.global_position = Vector2.ZERO
	_cam.make_current()
	await _test_bounded_then_hide(theme)
	await _test_null_camera_stops(theme)
	await _test_pan_hides_and_stops(theme)
	await _test_free_drops_poll(theme)


func _test_no_self_defer_loop() -> bool:
	var src := _read(THEME_SRC)
	if src.is_empty():
		_fail("RetrowaveTheme source missing")
		return false
	var poll := _func_body(src, "_poll_tooltip_pan")
	var arm := _func_body(src, "_arm_tooltip_pan_clear")
	if poll.is_empty():
		_fail("_poll_tooltip_pan missing")
		return false
	if arm.is_empty():
		_fail("_arm_tooltip_pan_clear missing")
		return false
	var poll_hits := poll.count("call_deferred")
	var arm_hits := arm.count("call_deferred")
	if poll_hits > 0 or arm_hits > 0:
		_fail(
			"unbounded call_deferred self-loop: _poll_tooltip_pan=%d _arm_tooltip_pan_clear=%d. A visible tip re-queues the poll on every idle with no per-frame cap (MessageQueue OOM). Stopped before arming the live poll."
			% [poll_hits, arm_hits]
		)
		return false
	var starter := _func_body(src, "_start_tooltip_pan_poll")
	if starter.is_empty() or ("process_frame" not in starter and "Timer" not in starter):
		_fail("pan poll is not frame-driven (no process_frame connection and no Timer)")
		return false
	_pass("no call_deferred self-loop in _poll_tooltip_pan or _arm_tooltip_pan_clear")
	return true


func _make_tip(theme) -> PopupPanel:
	var pop := PopupPanel.new()
	pop.theme_type_variation = "TooltipPanel"
	var lab := Label.new()
	lab.theme_type_variation = "TooltipLabel"
	lab.text = "# Date\n1 Jan 1936\n[Click] select"
	pop.add_child(lab)
	root.add_child(pop)
	theme.call("dress_tooltip_popup", pop)
	pop.popup(Rect2i(24, 24, 220, 72))
	if not pop.visible:
		pop.visible = true
	return pop


func _ticks(pop: PopupPanel) -> int:
	if pop == null or not is_instance_valid(pop):
		return -1
	return int(pop.get_meta("eoa_tooltip_pan_poll_ticks", 0))


func _test_bounded_then_hide(theme) -> void:
	var pop := _make_tip(theme)
	if not pop.visible:
		_fail("dressed tip is not visible (visible=%s)" % str(pop.visible))
		pop.queue_free()
		return
	# Headless arm must still skip. The poll under test is started directly.
	theme.call("_arm_tooltip_pan_clear", pop)
	if bool(theme.call("tooltip_pan_poll_active", pop)):
		_fail("headless _arm_tooltip_pan_clear armed the pan poll")
		theme.call("_stop_tooltip_pan_poll", pop)
		pop.queue_free()
		return
	_pass("headless _arm_tooltip_pan_clear still skips")
	theme.call("_start_tooltip_pan_poll", pop)
	if not bool(theme.call("tooltip_pan_poll_active", pop)):
		_fail("direct _start_tooltip_pan_poll did not arm (visible=%s cam=%s)" % [str(pop.visible), str(root.get_camera_2d())])
		pop.queue_free()
		return
	var max_delta := 0
	var prev := _ticks(pop)
	for _i in PAN_POLL_FRAMES:
		await process_frame
		var now := _ticks(pop)
		max_delta = maxi(max_delta, now - prev)
		prev = now
	if not bool(theme.call("tooltip_pan_poll_active", pop)):
		_fail("poll stopped while the tip stayed visible with a camera (ticks=%d)" % prev)
	elif max_delta > 1:
		_fail("poll ran %d times in one frame (cap is 1); ticks=%d" % [max_delta, prev])
	elif prev < PAN_POLL_MIN or prev > PAN_POLL_MAX:
		_fail("ticks=%d over %d frames want [%d, %d] max_delta=%d" % [prev, PAN_POLL_FRAMES, PAN_POLL_MIN, PAN_POLL_MAX, max_delta])
	else:
		_pass("bounded poll ticks=%d max_per_frame=%d over %d frames (want [%d, %d])" % [prev, max_delta, PAN_POLL_FRAMES, PAN_POLL_MIN, PAN_POLL_MAX])
	pop.hide()
	await process_frame
	var after_hide := _ticks(pop)
	if pop.visible:
		_fail("hide() left the tip visible")
	elif bool(pop.get_meta("eoa_tooltip_pan_poll", false)):
		_fail("meta eoa_tooltip_pan_poll still set after hide")
	elif bool(theme.call("tooltip_pan_poll_active", pop)):
		_fail("process_frame poll still connected after hide")
	else:
		var grew := false
		for _j in 30:
			await process_frame
			if _ticks(pop) != after_hide:
				grew = true
				break
		if grew:
			_fail("poll kept ticking after hide (%d -> %d)" % [after_hide, _ticks(pop)])
		elif bool(pop.get_meta("eoa_tooltip_pan_poll", false)):
			_fail("meta eoa_tooltip_pan_poll returned after hide")
		else:
			_pass("hide cleared eoa_tooltip_pan_poll and stopped ticks at %d" % after_hide)
	pop.free()


func _test_null_camera_stops(theme) -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.free()
		_cam = null
	await process_frame
	var pop := _make_tip(theme)
	theme.call("_start_tooltip_pan_poll", pop)
	await process_frame
	await process_frame
	var ticks := _ticks(pop)
	if root.get_camera_2d() != null:
		_fail("null-camera case still has a current camera")
	elif bool(pop.get_meta("eoa_tooltip_pan_poll", false)) or bool(theme.call("tooltip_pan_poll_active", pop)):
		_fail("null camera kept polling ticks=%d" % ticks)
	elif ticks > 2:
		_fail("null camera polled %d times (want <= 2, then stop)" % ticks)
	else:
		var frozen := ticks
		for _i in 10:
			await process_frame
		if _ticks(pop) != frozen or bool(pop.get_meta("eoa_tooltip_pan_poll", false)):
			_fail("null camera resumed polling %d -> %d" % [frozen, _ticks(pop)])
		else:
			_pass("null camera stopped the poll ticks=%d meta cleared" % frozen)
	pop.free()
	_cam = Camera2D.new()
	_cam.name = "PanPollCam"
	root.add_child(_cam)
	_cam.global_position = Vector2.ZERO
	_cam.make_current()


func _test_pan_hides_and_stops(theme) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_fail("pan case lost the camera")
		return
	_cam.global_position = Vector2.ZERO
	_cam.make_current()
	var pop := _make_tip(theme)
	theme.call("_start_tooltip_pan_poll", pop)
	await process_frame
	if not pop.has_meta("eoa_tooltip_cam_pose"):
		_fail("first poll did not record the camera pose")
		pop.free()
		return
	var pose: Vector2 = pop.get_meta("eoa_tooltip_cam_pose")
	_cam.global_position = pose + Vector2(40, 0)
	await process_frame
	var frozen := _ticks(pop)
	if pop.visible:
		_fail("pan left the tip visible pose=%s cam=%s" % [str(pose), str(_cam.global_position)])
	elif bool(pop.get_meta("eoa_tooltip_pan_poll", false)):
		_fail("pan hid the tip but left eoa_tooltip_pan_poll set")
	else:
		for _i in 10:
			await process_frame
		if _ticks(pop) != frozen:
			_fail("poll ticked after pan-clear %d -> %d" % [frozen, _ticks(pop)])
		else:
			_pass("pan cleared the tip and stopped the poll ticks=%d" % frozen)
	if is_instance_valid(pop):
		pop.free()


func _test_free_drops_poll(theme) -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.global_position = Vector2.ZERO
		_cam.make_current()
	var pop := _make_tip(theme)
	theme.call("_start_tooltip_pan_poll", pop)
	await process_frame
	if not bool(theme.call("tooltip_pan_poll_active", pop)):
		_fail("free case did not arm")
		if is_instance_valid(pop):
			pop.free()
		return
	var id := pop.get_instance_id()
	pop.free()
	if bool(theme.call("tooltip_pan_poll_tracked", id)):
		_fail("freed tip left a tracked pan poll")
		return
	for _i in 10:
		await process_frame
	if bool(theme.call("tooltip_pan_poll_tracked", id)):
		_fail("freed tip regained a tracked pan poll")
	else:
		_pass("freeing the tip dropped the pan poll")
