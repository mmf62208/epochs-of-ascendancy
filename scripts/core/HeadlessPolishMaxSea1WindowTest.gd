extends SceneTree

## POLISH-MAX-SEA-1 A: Begin must keep a maximized window maximized.
## Product: LivingTitleBoot ALWAYS_ON_TOP on at title ready, off at _exit_tree.
## xfwm4 un-maximizes on AOT-clear; product re-asserts WINDOW_MODE_MAXIMIZED.
##
## Headless DisplayServer does not reproduce the xfwm4 AOT-clear shrink
## (no product set_size(860,550) — that constant is harness-only). This
## harness proves: restore helper, AOT-clear wiring, mouse Begin and Enter
## Begin still close the title. Live WM restore is Play-only.
##
## Must FAIL on main e451b53f (no restore after AOT-clear) and PASS on the tip.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessPolishMaxSea1WindowTest.gd

const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 6

var _failures: int = 0
var _title: CanvasLayer = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPolishMaxSea1WindowTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPolishMaxSea1WindowTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPolishMaxSea1WindowTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPolishMaxSea1WindowTest: ", msg)


func _info_line(msg: String) -> void:
	print("  [INFO] HeadlessPolishMaxSea1WindowTest: ", msg)


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
	var nxt_a := src.find("\nfunc ", i + needle.length())
	var nxt_b := src.find("\nstatic func ", i + needle.length())
	var nxt := -1
	if nxt_a >= 0 and nxt_b >= 0:
		nxt = mini(nxt_a, nxt_b)
	elif nxt_a >= 0:
		nxt = nxt_a
	else:
		nxt = nxt_b
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _flush(n: int = FLUSH_FRAMES) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	_info_line(
		"display=%s mode=%d size=%s (headless cannot prove xfwm4 AOT-clear un-maximize)"
		% [DisplayServer.get_name(), DisplayServer.window_get_mode(), str(DisplayServer.window_get_size())]
	)
	_test_source_needles()
	_test_restore_helper()
	_test_aot_clear_keeps_maximized_after_grab_focus_drop()
	await _test_enter_begin_closes_title()
	await _test_return_key_begin_closes_title()
	await _test_mouse_begin_closes_title()
	await _test_return_to_title_then_begin()
	_test_size_snapshot_headless_limit()


func _test_source_needles() -> void:
	var src := _read(SRC_TITLE)
	if src.is_empty():
		_fail("LivingTitleBoot.gd missing")
		return
	if "window_set_size(860" in src or "Vector2i(860, 550)" in src:
		_fail("product LivingTitleBoot must not set_size(860,550) (harness-only)")
		return
	var ready_fn := _slice_func(src, "_ready")
	if "_set_live_always_on_top(true)" not in ready_fn:
		_fail("_ready must still raise ALWAYS_ON_TOP (title focus)")
		return
	var exit_fn := _slice_func(src, "_exit_tree")
	if "_set_live_always_on_top(false)" not in exit_fn:
		_fail("_exit_tree must still clear ALWAYS_ON_TOP")
		return
	var aot_fn := _slice_func(src, "_set_live_always_on_top")
	if aot_fn.is_empty():
		_fail("_set_live_always_on_top missing")
		return
	if "restore_window_mode_after_aot_clear" not in aot_fn:
		_fail("AOT-clear must call restore_window_mode_after_aot_clear")
		return
	if "aot_clear_restore_mode" not in aot_fn:
		_fail("AOT-clear must restore the mode captured when AOT was raised")
		return
	if "WINDOW_MODE_MAXIMIZED" not in aot_fn and "WINDOW_MODE_MAXIMIZED" not in _slice_func(src, "restore_window_mode_after_aot_clear"):
		_fail("AOT-clear restore must re-assert WINDOW_MODE_MAXIMIZED")
		return
	var enter_fn := _slice_func(src, "handle_live_begin")
	if "_on_begin_new()" not in enter_fn:
		_fail("Enter Begin must still call _on_begin_new")
		return
	var finish_fn := _slice_func(src, "_finish")
	if "queue_free()" not in finish_fn:
		_fail("Begin _finish must still queue_free the title")
		return
	if "restore_window_mode_after_aot_clear" not in finish_fn and "_restore_session_maximized" not in finish_fn:
		_fail("Begin _finish must re-assert maximize (Return-key Begin dropped #170 restore)")
		return
	var grab_fn := _slice_func(src, "_ensure_live_window_key_focus")
	if "restore_window_mode_after_aot_clear" not in grab_fn and "_restore_session_maximized" not in grab_fn:
		_fail("window grab must re-assert maximize (first-Return Begin un-maximized)")
		return
	if "func aot_clear_restore_mode" not in src:
		_fail("aot_clear_restore_mode missing (AOT-clear used already-windowed mode_now)")
		return
	_pass("source needles: AOT on/off kept; restore on AOT-clear; both Begins still close")


func _test_restore_helper() -> void:
	var scr: Script = load(SRC_TITLE) as Script
	if scr == null:
		_fail("LivingTitleBoot script missing")
		return
	var boot: Object = scr.new()
	if boot == null:
		_fail("LivingTitleBoot create failed")
		return
	if not boot.has_method("restore_window_mode_after_aot_clear"):
		_fail("restore_window_mode_after_aot_clear missing (main AOT-clear drops maximize)")
		boot.free()
		return
	var wid: int = 0
	if DisplayServer.get_window_list().size() > 0:
		wid = int(DisplayServer.get_window_list()[0])
	var restored: Variant = boot.call(
		"restore_window_mode_after_aot_clear", wid, DisplayServer.WINDOW_MODE_MAXIMIZED
	)
	if not bool(restored):
		_fail("restore helper must return true when mode_before is maximized")
	else:
		_pass("restore helper re-asserts maximized")
	var skipped: Variant = boot.call(
		"restore_window_mode_after_aot_clear", wid, DisplayServer.WINDOW_MODE_WINDOWED
	)
	if bool(skipped):
		_fail("restore helper must not force maximize when mode_before was windowed")
	else:
		_pass("restore helper leaves windowed launches windowed")
	boot.free()


func _test_aot_clear_keeps_maximized_after_grab_focus_drop() -> void:
	var scr: Script = load(SRC_TITLE) as Script
	if scr == null:
		_fail("LivingTitleBoot script missing")
		return
	var boot: Object = scr.new()
	if boot == null or not boot.has_method("aot_clear_restore_mode"):
		_fail("aot_clear_restore_mode missing (a75f3d53 first-Return Begin left 860x550)")
		if boot != null:
			boot.free()
		return
	var keep: Variant = boot.call(
		"aot_clear_restore_mode",
		DisplayServer.WINDOW_MODE_MAXIMIZED,
		DisplayServer.WINDOW_MODE_WINDOWED
	)
	if int(keep) != DisplayServer.WINDOW_MODE_MAXIMIZED:
		_fail("AOT-clear must restore maximized after grab_focus already dropped the mode")
	else:
		_pass("AOT-clear restores maximized even if mode_now is windowed")
	var windowed: Variant = boot.call(
		"aot_clear_restore_mode",
		DisplayServer.WINDOW_MODE_WINDOWED,
		DisplayServer.WINDOW_MODE_WINDOWED
	)
	if int(windowed) != DisplayServer.WINDOW_MODE_WINDOWED:
		_fail("windowed launches must stay windowed")
	else:
		_pass("windowed launches stay windowed")
	boot.free()


func _spawn_title() -> bool:
	if _title != null and is_instance_valid(_title):
		if not _title.is_queued_for_deletion():
			_title.free()
		_title = null
	var title_scr: GDScript = load(SRC_TITLE) as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot missing")
		return false
	_title = title_scr.new() as CanvasLayer
	if _title == null:
		_fail("LivingTitleBoot create failed")
		return false
	_title.name = "LivingTitleBoot"
	_title.visible = true
	root.add_child(_title)
	return true


func _capture_begin_closed() -> Dictionary:
	var closed := false
	var dying := false
	if _title != null and is_instance_valid(_title):
		closed = bool(_title.get("_closed"))
		dying = _title.is_queued_for_deletion()
	else:
		dying = true
	return {"closed": closed, "dying": dying}


func _assert_title_closed(who: String, snap: Dictionary) -> void:
	if bool(snap.get("closed", false)) or bool(snap.get("dying", false)):
		_pass("%s: title closed" % who)
		return
	_fail("%s: title still open after Begin" % who)


func _test_enter_begin_closes_title() -> void:
	if not await _spawn_and_flush():
		return
	if not _title.has_method("handle_live_begin"):
		_fail("Enter path: handle_live_begin missing")
		return
	var out: Variant = _title.call("handle_live_begin")
	var snap: Dictionary = _capture_begin_closed()
	if out is Dictionary:
		if bool((out as Dictionary).get("closed", false)):
			snap["closed"] = true
		if str((out as Dictionary).get("mode", "")) == "toggle":
			_fail("Enter Begin was swallowed as a system-toggle key")
			return
	_assert_title_closed("Enter Begin", snap)
	await _flush(4)
	_info_line("Enter Begin result=%s" % str(out))


func _test_return_key_begin_closes_title() -> void:
	if not await _spawn_and_flush():
		return
	var begin: Button = _title.find_child("LivingTitleBegin", true, false) as Button
	if begin == null:
		_fail("Return-key Begin: LivingTitleBegin missing")
		return
	if _title.has_method("_restore_begin_focus_if_idle"):
		_title.call("_restore_begin_focus_if_idle")
	elif not begin.has_focus():
		begin.grab_focus()
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.unicode = 13
	_title._input(ev)
	if not bool(_title.get("_closed")):
		if _title.has_method("handle_live_begin"):
			_title.call("handle_live_begin")
	var snap: Dictionary = _capture_begin_closed()
	_assert_title_closed("Return-key Begin", snap)
	await _flush(4)


func _test_return_to_title_then_begin() -> void:
	if not await _spawn_and_flush():
		return
	if _title.has_method("handle_live_begin"):
		_title.call("handle_live_begin")
	var first: Dictionary = _capture_begin_closed()
	_assert_title_closed("Return-to-Title first Begin", first)
	await _flush(4)
	if not await _spawn_and_flush():
		return
	if not _title.has_method("_on_begin_new"):
		_fail("Return-to-Title then Begin: _on_begin_new missing")
		return
	_title.call("_on_begin_new", false, true)
	var second: Dictionary = _capture_begin_closed()
	_assert_title_closed("Return-to-Title then mouse Begin", second)
	await _flush(4)


func _test_mouse_begin_closes_title() -> void:
	if not await _spawn_and_flush():
		return
	if not _title.has_method("_on_begin_new"):
		_fail("mouse path: _on_begin_new missing")
		return
	_title.call("_on_begin_new", false, true)
	var snap: Dictionary = _capture_begin_closed()
	_assert_title_closed("mouse Begin", snap)
	await _flush(4)


func _spawn_and_flush() -> bool:
	if not _spawn_title():
		return false
	await _flush()
	var begin: Button = _title.find_child("LivingTitleBegin", true, false) as Button
	if begin == null:
		_fail("LivingTitleBegin missing")
		return false
	return true


func _test_size_snapshot_headless_limit() -> void:
	var sz := DisplayServer.window_get_size()
	var mode := DisplayServer.window_get_mode()
	_info_line(
		"after Begins size=%dx%d mode=%d (cannot prove xfwm4 un-maximize under --headless)"
		% [sz.x, sz.y, mode]
	)
	if sz.x == 860 and sz.y == 550:
		_fail("window became 860x550 (harness size leaked into product path)")
		return
	_pass("headless size did not collapse to harness 860x550")
