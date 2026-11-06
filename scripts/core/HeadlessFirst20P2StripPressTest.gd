extends SceneTree

## FIRST20-P2 FIX ROUND 1: intensity / More / HFlow press must not free() the
## emitting chip. Strain secondary strip, real `pressed` (AudioManager wired).
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     --resolution 1024x720 -s res://scripts/core/HeadlessFirst20P2StripPressTest.gd

class StripPressLog extends Logger:
	var hits: PackedStringArray = PackedStringArray()

	func _log_message(message: String, error: bool) -> void:
		if error:
			_note(message)

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_note("%s:%d %s %s" % [file, line, code, rationale])

	func _note(text: String) -> void:
		var t := text
		if (
			t.find("freed or unreferenced") >= 0
			or t.find("Cannot convert argument") >= 0
			or t.find("previously freed") >= 0
			or t.find("freed instance") >= 0
		):
			if hits.size() < 12:
				hits.append(t)


var _failures: int = 0
var _log: StripPressLog = null
var _mr: Node = null
var _tb: Control = null
var _trail_ok: int = 0
var _trail_bad: int = 0


func _init() -> void:
	_log = StripPressLog.new()
	OS.add_logger(_log)
	call_deferred("_run")


func _run() -> void:
	await _test_strip_presses()
	_finish()


func _finish() -> void:
	_assert_log_clean()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	if _failures == 0:
		print("HeadlessFirst20P2StripPressTest: RESULT=PASS")
		quit(0)
	else:
		print("HeadlessFirst20P2StripPressTest: RESULT=FAIL failures=%d" % _failures)
		quit(1)


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL %s" % msg)


func _pass(msg: String) -> void:
	print("PASS %s" % msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _test_strip_presses() -> void:
	DisplayServer.window_set_size(Vector2i(1024, 720))
	if root != null:
		root.size = Vector2i(1024, 720)
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.size = Vector2i(1024, 720)
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer missing")
		return
	_mr = mr_script.new()
	root.add_child(_mr)
	await _frames(2)
	if _mr.get_node_or_null("UI") == null:
		var ui := CanvasLayer.new()
		ui.name = "UI"
		_mr.add_child(ui)
		await _frames(1)
	if _mr.get("_map_mode_toolbar") == null and _mr.has_method("_setup_player_map_ux"):
		_mr.call("_setup_player_map_ux")
		await _frames(2)
	_tb = _mr.get("_map_mode_toolbar") as Control
	if _tb == null:
		_fail("MapModeToolbar missing")
		return
	var am := root.get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("_wire_tree"):
		am.call("_wire_tree", _tb)
		_pass("AudioManager wired")
	else:
		print("INFO AudioManager missing; still emitting pressed")
	_mr.call("set_map_mode", "strain")
	await _frames(3)
	if str(_mr.get("current_map_mode")) != "strain":
		_fail("did not enter strain")
		return
	_pass("strain secondary strip")
	var seq: PackedStringArray = PackedStringArray(["Low", "Med", "High", "Max", "Low"])
	for lab in seq:
		if not await _press_named(lab):
			return
	_pass("intensity Low/Med/High/Max/Low")
	await _press_more_items()
	await _press_hflow_buttons()
	_assert_log_clean()
	if _trail_bad > 0:
		_fail("typed trail saw freed Object (%d)" % _trail_bad)
	elif _trail_ok > 0:
		_pass("typed trail hits=%d" % _trail_ok)


func _press_named(lab: String) -> bool:
	var btn := _find_button_text(_tb, lab)
	if btn == null:
		_fail("button %s missing before press" % lab)
		return false
	_emit_real_press(btn)
	if not is_instance_valid(btn):
		_fail("%s was free()'d during pressed" % lab)
		return false
	await _frames(3)
	_assert_log_clean()
	_pass("pressed %s still valid" % lab)
	return true


func _press_more_items() -> void:
	var more := _tb.find_child("MoreOverflow", true, false) as MenuButton
	if more == null:
		# Force overflow by relayout at a narrow width.
		if _tb.has_method("relayout_overflow"):
			_tb.call("relayout_overflow")
		await _frames(2)
		more = _tb.find_child("MoreOverflow", true, false) as MenuButton
	if more == null:
		print("INFO no MoreOverflow at 1024; skipping popup ids")
		return
	var popup := more.get_popup()
	if popup == null or popup.item_count < 1:
		_fail("More ▾ popup empty")
		return
	var n: int = popup.item_count
	for i in n:
		more = _tb.find_child("MoreOverflow", true, false) as MenuButton
		if more == null:
			_fail("MoreOverflow vanished after id %d" % i)
			return
		popup = more.get_popup()
		if popup == null or i >= popup.item_count:
			break
		popup.id_pressed.emit(i)
		await _frames(3)
		_assert_log_clean()
	_pass("More ▾ id_pressed x%d" % n)


func _press_hflow_buttons() -> void:
	var names: PackedStringArray = PackedStringArray()
	_collect_flow_labels(_tb, names)
	var seen: Dictionary = {}
	for lab in names:
		if seen.has(lab):
			continue
		seen[lab] = true
		var btn := _find_button_text(_tb, lab)
		if btn == null or not is_instance_valid(btn):
			continue
		_emit_real_press(btn)
		await _frames(2)
		_assert_log_clean()
	_pass("HFlow chip presses %d" % seen.size())


func _emit_real_press(btn: BaseButton) -> void:
	if btn == null or not is_instance_valid(btn):
		_fail("emit on invalid button")
		return
	var trail := Callable(self, "_on_typed_trail").bind(btn)
	if not btn.pressed.is_connected(trail):
		btn.pressed.connect(trail)
	var am := root.get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("activate_button"):
		am.call("activate_button", btn)
	else:
		btn.pressed.emit()


func _on_typed_trail(btn: BaseButton) -> void:
	if btn == null or not is_instance_valid(btn):
		_trail_bad += 1
		_fail("typed pressed trail got freed Object")
	else:
		_trail_ok += 1


func _assert_log_clean() -> void:
	if _log == null:
		return
	if _log.hits.is_empty():
		return
	_fail("engine error: %s" % _log.hits[0])
	_log.hits.clear()


func _collect_flow_labels(n: Node, out: PackedStringArray) -> void:
	if n is Button:
		var t := (n as Button).text.strip_edges()
		if not t.is_empty() and t != "More ▾" and t != "▾":
			out.append(t)
	for c in n.get_children():
		_collect_flow_labels(c, out)


func _find_button_text(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n as Button
	for c in n.get_children():
		var hit := _find_button_text(c, text)
		if hit != null:
			return hit
	return null
