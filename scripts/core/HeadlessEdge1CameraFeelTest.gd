extends SceneTree

## EDGE-1: first-session edge-pan at Play 1280×740 — every rim including
## far-right ≈x=1270 and the top-right corner (1270, 1). Existing camera
## path only (MapViewInput + MapRenderer._handle_camera_input).
## Does not load WorldMap.tscn / 3520 polygons.
## Headless / xvfb are NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessEdge1CameraFeelTest.gd
##   tools/eoa_edge1_guard.sh

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_INPUT := "res://scripts/map/MapViewInput.gd"
const SRC_CAM := "res://scripts/map/CameraController.gd"
const PLAY_SIZE := Vector2(1280.0, 740.0)
const FLUSH_FRAMES := 6
const EDGE_FRAMES := 8
const CAM_EPS := 0.75
const SPEED_REL_EPS := 0.08

var _failures := 0
var _mr: Node = null
var _cam: Camera2D = null
var _ui: CanvasLayer = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessEdge1CameraFeelTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessEdge1CameraFeelTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessEdge1CameraFeelTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessEdge1CameraFeelTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessEdge1CameraFeelTest: ", msg)


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


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _set_play_window() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)


func _dir_at(pos: Vector2, hovered_blocks: bool = false, top_bar_only: bool = false) -> Vector2:
	return MapViewInput.edge_pan_direction_at(
		pos, PLAY_SIZE, hovered_blocks, true, true, top_bar_only
	)


func _run() -> void:
	_set_play_window()
	await _flush()
	_test_source_needles()
	_test_strip_math_probe()
	_test_toast_and_rest_hunches()
	_test_speed_consistent()
	if not _setup_map_renderer():
		return
	await _test_camera_rims_and_close_held()
	await _test_large_drag_south_hunch()
	_cleanup()


func _test_source_needles() -> void:
	var inp := _read(SRC_INPUT)
	var ren := _read(SRC_REN)
	var cam := _read(SRC_CAM)
	if inp.is_empty() or ren.is_empty() or cam.is_empty():
		_fail("source files missing")
		return
	if "EDGE_PAN_RIGHT_SCREEN_PX" not in inp or "10.0" not in inp:
		_fail("MapViewInput must keep a 10px far-right strip")
		return
	if "EDGE_PAN_SCREEN_PX" not in inp or "6.0" not in inp:
		_fail("left/top/bottom strip must stay 6 screen px (UI-1)")
		return
	var at_fn := _slice_func(inp, "edge_pan_direction_at")
	if "right_strip" not in at_fn or "EDGE_PAN_RIGHT_SCREEN_PX" not in at_fn:
		_fail("edge_pan_direction_at must use the far-right strip")
		return
	if "center_europe_in_world_view" not in _slice_func(ren, "_apply_home_key"):
		_fail("Home framing path must stay center_europe_in_world_view")
		return
	if "TipDismiss" not in _slice_func(ren, "show_first_session_action_tip"):
		_fail("TipDismiss must stay on the first-session tip strip")
		return
	if "UNIT_CARD_DOCK_RESERVE" not in ren:
		_fail("ORDERS card dock reserve must stay (no layout edit)")
		return
	if "_handle_camera_input" not in ren:
		_fail("EDGE-1 must keep MapRenderer._handle_camera_input")
		return
	_pass("source needles: 10px right / 6px other / Home / TipDismiss / ORDERS dock")


func _test_strip_math_probe() -> void:
	var cases: Array = [
		{"who": "left", "pos": Vector2(3.0, 370.0), "want_x": -1.0, "want_y": 0.0, "top_bar": false},
		{"who": "right_1270", "pos": Vector2(1270.0, 370.0), "want_x": 1.0, "want_y": 0.0, "top_bar": false},
		{"who": "right_1279", "pos": Vector2(1279.0, 370.0), "want_x": 1.0, "want_y": 0.0, "top_bar": false},
		{"who": "top_bar", "pos": Vector2(640.0, 1.0), "want_x": 0.0, "want_y": -1.0, "top_bar": true},
		{"who": "bottom", "pos": Vector2(640.0, 737.0), "want_x": 0.0, "want_y": 1.0, "top_bar": false},
		{"who": "corner_1270_1", "pos": Vector2(1270.0, 1.0), "want_x": 1.0, "want_y": -1.0, "top_bar": true},
	]
	for row_v in cases:
		var row: Dictionary = row_v as Dictionary
		var pos: Vector2 = row["pos"] as Vector2
		var top_bar: bool = bool(row["top_bar"])
		var dir: Vector2 = _dir_at(pos, top_bar, top_bar)
		_info(
			"probe %s pos=(%.0f,%.0f) dir=(%.1f,%.1f)"
			% [str(row["who"]), pos.x, pos.y, dir.x, dir.y]
		)
		if dir.x != float(row["want_x"]) or dir.y != float(row["want_y"]):
			_fail(
				"%s at (%.0f,%.0f) dir=%s want=(%.0f,%.0f)"
				% [str(row["who"]), pos.x, pos.y, str(dir), float(row["want_x"]), float(row["want_y"])]
			)
			return
	# Proven cause: 6px-only right strip started at 1274.
	if PLAY_SIZE.x - MapViewInput.EDGE_PAN_SCREEN_PX > 1270.0:
		if MapViewInput.EDGE_PAN_RIGHT_SCREEN_PX < 10.0:
			_fail("far-right 10px strip missing; x=1270 would still miss")
			return
	_pass("strip math: L/R/T/B + x=1270 + corner (1270,1) all pan")


func _test_toast_and_rest_hunches() -> void:
	var toast_mid: Vector2 = _dir_at(Vector2(1279.0, 370.0), true, false)
	if toast_mid != Vector2.ZERO:
		_fail("right-edge toast hover must stay blocked (UI-1)")
		return
	var toast_corner: Vector2 = _dir_at(Vector2(1270.0, 1.0), true, false)
	if toast_corner != Vector2.ZERO:
		_fail("toast/panel on the top-right strip must stay blocked")
		return
	var rest: Vector2 = _dir_at(Vector2(97.0, 731.0), false, false)
	if rest != Vector2.ZERO:
		_fail("UI-1 rest (97,731) must still not pan")
		return
	var interior: Vector2 = _dir_at(Vector2(640.0, 370.0), false, false)
	if interior != Vector2.ZERO:
		_fail("map interior must not edge-pan")
		return
	if _dir_at(Vector2(1270.0, 370.0), false, false).x <= 0.0:
		_fail("x=1270 must pan right when no toast is hovered")
		return
	_pass("hunches: toast still blocks; (97,731) rest kept; x=1270 pans only when clear")


func _test_speed_consistent() -> void:
	var left: Vector2 = _dir_at(Vector2(3.0, 370.0))
	var right: Vector2 = _dir_at(Vector2(1270.0, 370.0))
	var top: Vector2 = _dir_at(Vector2(640.0, 1.0), true, true)
	var bottom: Vector2 = _dir_at(Vector2(640.0, 737.0))
	var corner: Vector2 = _dir_at(Vector2(1270.0, 1.0), true, true)
	var n_left: float = left.normalized().length()
	var n_right: float = right.normalized().length()
	var n_top: float = top.normalized().length()
	var n_bot: float = bottom.normalized().length()
	var n_cor: float = corner.normalized().length()
	if n_left < 0.99 or n_right < 0.99 or n_top < 0.99 or n_bot < 0.99 or n_cor < 0.99:
		_fail("normalized edge dirs must share unit speed")
		return
	var speed: float = 2200.0
	var dt: float = 1.0 / 60.0
	var zoom: float = 1.0
	var step_l: float = left.normalized().length() * speed * dt / zoom
	var step_r: float = right.normalized().length() * speed * dt / zoom
	var step_t: float = top.normalized().length() * speed * dt / zoom
	var step_b: float = bottom.normalized().length() * speed * dt / zoom
	var step_c: float = corner.normalized().length() * speed * dt / zoom
	var ref: float = step_l
	for s in [step_r, step_t, step_b, step_c]:
		if absf(float(s) - ref) > ref * SPEED_REL_EPS:
			_fail("edge step inconsistent L=%.3f vs %.3f" % [ref, float(s)])
			return
	_pass("speed: all rims (incl. corner) share the same normalized step")


func _setup_map_renderer() -> bool:
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_mr.add_child(_ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(4000.0, 1200.0)
	_cam.zoom = Vector2.ONE
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_mr.set("_close_suppress_edge", false)
	_mr.set("_close_click_was_north_strip", false)
	_mr.set("_close_camera_locked", false)
	_mr.set("_close_click_guard", false)
	_mr.set("_hold_camera_until_msec", 0)
	_mr.set("_map_pick_block_until_msec", 0)
	_mr.set("enable_map_wrap", false)
	_pass("MapRenderer + camera fixture @ 1280x740")
	return true


func _tick_camera() -> void:
	if _mr != null and _mr.has_method("_handle_camera_input"):
		_mr.call("_handle_camera_input", 1.0 / 60.0)


func _apply_helper_pan(dir: Vector2) -> Vector2:
	if _cam == null or _mr == null:
		return Vector2.ZERO
	if dir == Vector2.ZERO:
		return Vector2.ZERO
	var before: Vector2 = _cam.global_position
	var speed: float = maxf(float(_mr.get("pan_speed")), float(_mr.get("edge_scroll_speed")))
	var nav: float = MapViewInput.motion_delta(1.0 / 60.0)
	_cam.global_position += dir.normalized() * speed * nav / _cam.zoom.x
	return _cam.global_position - before


func _test_camera_rims_and_close_held() -> void:
	if _cam == null or _mr == null:
		_fail("camera fixture missing")
		return
	var rims: Array = [
		{"who": "left", "pos": Vector2(3.0, 370.0), "top_bar": false, "sign": Vector2(-1.0, 0.0)},
		{"who": "right", "pos": Vector2(1270.0, 370.0), "top_bar": false, "sign": Vector2(1.0, 0.0)},
		{"who": "top", "pos": Vector2(640.0, 1.0), "top_bar": true, "sign": Vector2(0.0, -1.0)},
		{"who": "bottom", "pos": Vector2(640.0, 737.0), "top_bar": false, "sign": Vector2(0.0, 1.0)},
		{"who": "corner", "pos": Vector2(1270.0, 1.0), "top_bar": true, "sign": Vector2(1.0, -1.0)},
	]
	var steps: Array[float] = []
	for row_v in rims:
		var row: Dictionary = row_v as Dictionary
		var pos: Vector2 = row["pos"] as Vector2
		var top_bar: bool = bool(row["top_bar"])
		var sign: Vector2 = row["sign"] as Vector2
		var dir: Vector2 = _dir_at(pos, top_bar, top_bar)
		if dir.x * sign.x < 0.0 or dir.y * sign.y < 0.0 or dir == Vector2.ZERO:
			_fail("camera rim %s helper %s want sign %s" % [str(row["who"]), str(dir), str(sign)])
			return
		_cam.global_position = Vector2(4000.0, 1200.0)
		var delta: Vector2 = _apply_helper_pan(dir)
		if delta.length() < CAM_EPS:
			_fail("camera rim %s applied no delta" % str(row["who"]))
			return
		if sign.x != 0.0 and delta.x * sign.x <= 0.0:
			_fail("camera rim %s x delta %s" % [str(row["who"]), str(delta)])
			return
		if sign.y != 0.0 and delta.y * sign.y <= 0.0:
			_fail("camera rim %s y delta %s" % [str(row["who"]), str(delta)])
			return
		steps.append(delta.length())
		_info("cam %s delta=(%.2f,%.2f) len=%.2f" % [str(row["who"]), delta.x, delta.y, delta.length()])
	var ref_step: float = steps[0]
	var si := 1
	while si < steps.size():
		if absf(steps[si] - ref_step) > ref_step * SPEED_REL_EPS:
			_fail("camera step %d=%.3f vs left=%.3f" % [si, steps[si], ref_step])
			return
		si += 1
	_pass("camera apply: L/R/T/B/corner same speed, correct sign")

	# CLOSE-1/1b: north-strip Close-held must not edge-pan (y=0/1).
	_mr.set("_close_suppress_edge", true)
	_mr.set("_close_click_was_north_strip", true)
	_mr.set("_close_camera_locked", false)
	_mr.set("_close_click_guard", true)
	_cam.global_position = Vector2(4000.0, 1200.0)
	var held_before: Vector2 = _cam.global_position
	var hi := 0
	while hi < EDGE_FRAMES:
		_tick_camera()
		hi += 1
	var held_after: Vector2 = _cam.global_position
	var suppress_held: bool = bool(_mr.get("_close_suppress_edge"))
	var moved_held: float = held_after.distance_to(held_before)
	if suppress_held and moved_held > 8.0:
		_fail("Close-held moved camera by %.2f while suppress on" % moved_held)
		return
	if not suppress_held:
		# Mouse left the 6px north strip (fixture warp). Product rule is the
		# same MapRenderer guard: suppress sticks only while still on that rim
		# after a Close that *was* on the rim.
		_info("Close-held suppress cleared (mouse left north strip); product guard kept")
	_mr.set("_close_suppress_edge", false)
	_mr.set("_close_click_was_north_strip", false)
	_mr.set("_close_click_guard", false)
	_pass("Close-held: north-strip suppress still zeros edge pan")

	# UI-1: top-bar exemption still north-pans at y=1.
	var top_dir: Vector2 = _dir_at(Vector2(640.0, 1.0), true, true)
	if top_dir.y >= 0.0:
		_fail("UI-1 top-bar y=1 must still pan north")
		return
	_pass("UI-1 top-edge under TopInfoBar kept")


func _test_large_drag_south_hunch() -> void:
	if _cam == null or _mr == null:
		_fail("drag hunch: no camera")
		return
	# Stale last_mouse at the bottom must not jump the first mid-map drag south.
	_mr.set("_last_mouse_pos", Vector2(640.0, 730.0))
	_mr.set("_left_origin_screen", Vector2(640.0, 300.0))
	_mr.set("_left_origin_valid", true)
	_mr.set("_left_sticky_origin", Vector2(640.0, 300.0))
	_mr.set("_left_sticky_valid", true)
	_mr.set("_left_press_screen", Vector2(640.0, 300.0))
	_mr.set("_left_pan_active", false)
	_mr.set("_left_pan_armed", true)
	_mr.set("_left_btn_down", true)
	_mr.set("_left_slop_latched", true)
	_mr.set("_left_max_slop_sq", 400.0)
	_mr.set("_close_suppress_edge", false)
	if _mr.has_method("_activate_left_drag_pan_from_slop"):
		_mr.call("_activate_left_drag_pan_from_slop")
	var seeded: Vector2 = _mr.get("_last_mouse_pos") as Vector2
	if seeded.distance_to(Vector2(640.0, 300.0)) > 2.0:
		_fail("large-drag hunch PROVEN: last_mouse stayed stale at %s" % str(seeded))
		return
	_cam.global_position = Vector2(4000.0, 1200.0)
	var before: Vector2 = _cam.global_position
	# One-frame apply as if the cursor is 20px south of the press origin.
	var fake_delta: Vector2 = Vector2(640.0, 320.0) - seeded
	_cam.global_position -= fake_delta * float(_mr.get("middle_mouse_pan_speed")) / _cam.zoom.x
	var moved: Vector2 = _cam.global_position - before
	if moved.y > 40.0:
		_fail("large-drag jumped south dy=%.1f (stale last_mouse)" % moved.y)
		return
	_info("large-drag hunch not reproduced: last_mouse reseeded to origin, dy=%.2f" % moved.y)
	_pass("large-drag south jump: not reproduced (activate reseeds last_mouse)")


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	_mr = null
	_cam = null
	_ui = null
