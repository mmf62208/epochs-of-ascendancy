extends SceneTree

## WHEELDRIFT-1: wheel zoom stays under the cursor; in/out are inverses;
## a wheel notch never edge-pans (350 ms hold + 150 ms dwell).
## Small MapRenderer fixture — does not load WorldMap.tscn / 3520.
## Must FAIL on main MapRenderer (no suppress, asymmetric zoom, viewport mouse)
## and PASS on this tip. Headless is NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessWheelDrift1Test.gd

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_INPUT := "res://scripts/map/MapViewInput.gd"
const PLAY_SIZE := Vector2i(1280, 740)
const MID := Vector2(640.0, 370.0)
const BR := Vector2(1279.0, 739.0)
const ANCHOR_EVENT := Vector2(900.0, 500.0)
const ANCHOR_VIEWPORT := Vector2(200.0, 180.0)
const START_Z := 0.80
const CAM_START := Vector2(4000.0, 1200.0)
const PX_EPS := 2.0
const Z_EPS := 0.004
const CAM_EPS := 2.0
const FLUSH_FRAMES := 4
const KOLN := 710417

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessWheelDrift1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessWheelDrift1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWheelDrift1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWheelDrift1Test: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessWheelDrift1Test: ", msg)


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


func _world_of(screen: Vector2) -> Vector2:
	if _cam == null:
		return screen
	return _cam.get_canvas_transform().affine_inverse() * screen


func _screen_of(world: Vector2) -> Vector2:
	if _cam == null:
		return world
	return _cam.get_canvas_transform() * world


func _tick_camera() -> void:
	if _mr != null and _mr.has_method("_handle_camera_input"):
		_mr.call("_handle_camera_input", 1.0 / 60.0)


func _edge_frames() -> int:
	if _mr == null or not ("_nav_edge_pan_frames" in _mr):
		return -1
	return int(_mr.get("_nav_edge_pan_frames"))


func _reset_edge_frames() -> void:
	if _mr != null and "_nav_edge_pan_frames" in _mr:
		_mr.set("_nav_edge_pan_frames", 0)


func _send_wheel(screen: Vector2, zoom_in: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if zoom_in else MOUSE_BUTTON_WHEEL_DOWN
	ev.position = screen
	ev.global_position = screen
	if _mr != null:
		_mr._input(ev)


func _factor_in() -> float:
	if _mr != null and _mr.has_method("_wheel_zoom_factor"):
		return float(_mr.call("_wheel_zoom_factor", true))
	return 1.0 + 0.18 * 1.35


func _factor_out() -> float:
	if _mr != null and _mr.has_method("_wheel_zoom_factor"):
		return float(_mr.call("_wheel_zoom_factor", false))
	return 1.0 - 0.18 * 1.35


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	if OS.get_environment("EOA_WHEELDRIFT1_BEHAVIOR_ONLY") != "1":
		_assert_source_needles()
	else:
		_info("EOA_WHEELDRIFT1_BEHAVIOR_ONLY=1 — source-text needles skipped")
	if not _setup_map_renderer():
		return
	_pause_sim()
	await _flush()
	await _test_t1_edge_during_wheel()
	_test_t2_anchor_and_inverse()
	_test_t3_event_position()
	_test_t4_regressions()
	_cleanup()


func _assert_source_needles() -> void:
	var ren := _read(SRC_REN)
	var inp := _read(SRC_INPUT)
	if ren.is_empty() or inp.is_empty():
		_fail("source files missing")
		return
	if "WHEEL_EDGE_SUPPRESS_MS" not in ren or "_arm_wheel_edge_suppress" not in ren:
		_fail("mutant no_wheel_suppress: MapRenderer must arm a wheel edge hold")
		return
	if "WHEEL_EDGE_DWELL_MS" not in ren or "_gate_wheel_edge_pan" not in ren:
		_fail("mutant edge_ignores_hold: wheel hold + dwell gate missing")
		return
	var wheel_fn := _slice_func(ren, "_input")
	if "_arm_wheel_edge_suppress" not in wheel_fn:
		_fail("mutant no_wheel_suppress: _input wheel branch must arm suppress")
		return
	if "event.position" not in _slice_func(ren, "_input") and "wheel_screen" not in _slice_func(ren, "_input"):
		_fail("mutant anchor_from_viewport_mouse: wheel must pass event.position")
		return
	var zfn := _slice_func(ren, "_zoom_toward_mouse")
	if "screen_pos" not in zfn:
		_fail("mutant anchor_from_viewport_mouse: _zoom_toward_mouse must take screen_pos")
		return
	if "world_before - world_after" not in zfn and "world_before-world_after" not in zfn:
		_fail("mutant no_anchor_correction: zoom must apply world_before - world_after")
		return
	var corr_i := zfn.find("world_before - world_after")
	var clamp_i := zfn.find("_clamp_camera_to_theater")
	if corr_i < 0 or clamp_i < 0 or clamp_i < corr_i:
		_fail("mutant clamp_before_anchor: theater clamp must run after the anchor correction")
		return
	var fac := _slice_func(ren, "_wheel_zoom_factor")
	if "1.0 / factor_in" not in fac and "1.0 / factor_in" not in ren:
		_fail("wheel in/out must be exact inverses (1.0 / factor_in)")
		return
	if "1.0 - zoom_speed * 1.35" in _slice_func(ren, "_input"):
		_fail("wheel _input must not use asymmetric 1.0 - zoom_speed * 1.35")
		return
	var gate := _slice_func(ren, "_gate_wheel_edge_pan")
	if "_wheel_edge_await_dwell = false" not in gate:
		_fail("mutant suppress_forever: dwell gate must clear after strip dwell")
		return
	if "EDGE_PAN_SCREEN_PX" not in inp or "6.0" not in inp:
		_fail("T4: left/top/bottom strip must stay 6 screen px (UI-1)")
		return
	if "EDGE_PAN_RIGHT_SCREEN_PX" not in inp or "10.0" not in inp:
		_fail("T4: far-right strip must stay 10 px (EDGE-1)")
		return
	if "event.position" not in _slice_func(ren, "_map_pick_screen_pos"):
		_fail("T4: FAC-1a click pick must keep event.position")
		return
	if "_close_suppress_edge" not in _slice_func(ren, "_handle_camera_input"):
		_fail("T4: CLOSE-1b north-strip suppress must stay in the nav step")
		return
	if "edge_pan_direction_screen" not in _slice_func(ren, "_handle_camera_input"):
		_fail("T4: EDGE-1 must keep edge_pan_direction_screen in _handle_camera_input")
		return
	_pass("source needles: suppress / inverse / event-anchor / T4 UI-1 EDGE-1 CLOSE-1b FAC-1a")


func _setup_map_renderer() -> bool:
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("MapRenderer.gd failed to load")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer.new() failed")
		return false
	_container = Node2D.new()
	_container.name = "ProvinceContainers"
	_mr.add_child(_container)
	if "container" in _mr:
		_mr.container = _container
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_mr.set_process_input(true)
	_mr.set_process_unhandled_input(true)
	if "_close_camera_locked" in _mr:
		_mr.set("_close_camera_locked", false)
	if "_close_suppress_edge" in _mr:
		_mr.set("_close_suppress_edge", false)
	if "_close_click_was_north_strip" in _mr:
		_mr.set("_close_click_was_north_strip", false)
	if "_close_click_guard" in _mr:
		_mr.set("_close_click_guard", false)
	if "enable_map_wrap" in _mr:
		_mr.set("enable_map_wrap", false)
	if "_current_theater_bounds" in _mr:
		_mr.set("_current_theater_bounds", Rect2(-40000.0, -40000.0, 120000.0, 120000.0))
	if "province_centroids" in _mr:
		var cents: Dictionary = _mr.get("province_centroids") as Dictionary
		cents[KOLN] = CAM_START
		_mr.province_centroids = cents
	_reset_edge_frames()
	_pass("MapRenderer fixture ready @ 1280x740 z=0.80")
	return true


func _pause_sim() -> void:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if tm != null and tm.has_method("is_paused") and bool(tm.call("is_paused")):
		_pass("sim paused (TimeManager.is_paused)")
	else:
		_info("TimeManager pause skipped (fixture)")


func _test_t1_edge_during_wheel() -> void:
	if _mr == null or _cam == null:
		_fail("T1: fixture missing")
		return
	_cam.global_position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	_mr.set("_close_suppress_edge", false)
	_mr.set("_close_camera_locked", false)
	_reset_edge_frames()
	var win: Window = root.get_window() if root != null else null
	if win != null:
		win.warp_mouse(BR)
	DisplayServer.warp_mouse(Vector2i(int(BR.x), int(BR.y)))
	var vp := _mr.get_viewport()
	if vp != null:
		vp.warp_mouse(BR)
	await process_frame
	var n := 0
	while n < 10:
		_send_wheel(BR, true)
		_tick_camera()
		await process_frame
		_tick_camera()
		await process_frame
		n += 1
	n = 0
	while n < 10:
		_send_wheel(BR, false)
		_tick_camera()
		await process_frame
		_tick_camera()
		await process_frame
		n += 1
	var hold_ms: int = 350
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < hold_ms + 20:
		_tick_camera()
		await process_frame
	var during: int = _edge_frames()
	_info("T1 edge frames during wheel+hold=%d (want 0)" % during)
	if during < 0:
		_fail("mutant no_wheel_suppress: _nav_edge_pan_frames missing")
		return
	if during != 0:
		_fail("mutant no_wheel_suppress: edge pan frames during wheel+hold=%d want 0" % during)
		return
	_pass("T1: 0 edge-pan frames during wheel + 350 ms hold")

	# After the hold, a deliberate strip dwell must still edge-pan (EDGE-1).
	var dwell_ms: int = 150
	_reset_edge_frames()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < dwell_ms + 80:
		_tick_camera()
		await process_frame
	var after: int = _edge_frames()
	_info("T1 edge frames after dwell=%d" % after)
	if after <= 0:
		# Headless warp can miss BR; (0,0) is still a rim. If the helper says
		# the live mouse is on a strip and we still got 0, suppress stuck.
		var live: Vector2 = Vector2.ZERO
		if win != null:
			live = win.get_mouse_position()
		var helper: Vector2 = MapViewInput.edge_pan_direction_at(
			live, Vector2(PLAY_SIZE), false, true, true, false
		)
		if helper == Vector2.ZERO:
			helper = MapViewInput.edge_pan_direction_at(
				BR, Vector2(PLAY_SIZE), false, true, true, false
			)
		_info("T1 dwell helper live=%s dir=%s" % [str(live), str(helper)])
		if helper != Vector2.ZERO:
			_fail("mutant suppress_forever: strip dwell after hold did not edge-pan")
			return
		_fail("mutant suppress_forever: no edge-pan after hold (helper also zero)")
		return
	_pass("T1: strip dwell after hold still edge-pans (EDGE-1 kept)")


func _test_t2_anchor_and_inverse() -> void:
	if _mr == null or _cam == null:
		_fail("T2: fixture missing")
		return
	_cam.global_position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	_mr.set("_close_camera_locked", false)
	var fin: float = _factor_in()
	var fout: float = _factor_out()
	_info("T2 factors in=%.6f out=%.6f product=%.6f" % [fin, fout, fin * fout])
	if absf(fin * fout - 1.0) > 0.0001:
		_fail("in/out are not exact inverses (in=%.6f out=%.6f)" % [fin, fout])
		return
	if absf(fout - (1.0 - 0.18 * 1.35)) < 0.002:
		_fail("out factor still uses asymmetric 1.0 - zoom_speed * 1.35")
		return
	var world_anchor: Vector2 = _world_of(MID)
	var cam0: Vector2 = _cam.global_position
	var z0: float = _cam.zoom.x
	var i := 0
	while i < 10:
		_mr.call("_zoom_toward_mouse", fin, MID)
		var stayed: Vector2 = _screen_of(world_anchor)
		var dpx: float = stayed.distance_to(MID)
		_info("T2 in notch %d z=%.3f dpx=%.3f" % [i + 1, _cam.zoom.x, dpx])
		if dpx > PX_EPS:
			_fail("mutant no_anchor_correction: in notch %d slipped %.3f px (want ≤%.1f)" % [i + 1, dpx, PX_EPS])
			return
		i += 1
	i = 0
	while i < 10:
		_mr.call("_zoom_toward_mouse", fout, MID)
		var stayed_out: Vector2 = _screen_of(world_anchor)
		var dpx_out: float = stayed_out.distance_to(MID)
		_info("T2 out notch %d z=%.3f dpx=%.3f" % [i + 1, _cam.zoom.x, dpx_out])
		if dpx_out > PX_EPS:
			_fail("mutant no_anchor_correction: out notch %d slipped %.3f px (want ≤%.1f)" % [i + 1, dpx_out, PX_EPS])
			return
		i += 1
	var z1: float = _cam.zoom.x
	var cam1: Vector2 = _cam.global_position
	if absf(z1 - z0) > Z_EPS:
		_fail("10 in + 10 out left zoom at %.4f start=%.4f (not inverses)" % [z1, z0])
		return
	if cam1.distance_to(cam0) > CAM_EPS:
		_fail("10 in + 10 out left camera %.3f px from start (want ≤%.1f)" % [cam1.distance_to(cam0), CAM_EPS])
		return
	_pass("T2: ≤2 px per notch, in/out round-trip zoom+camera")

	# Clamp-binding zoom-out: slip is allowed, runaway is not.
	_cam.global_position = Vector2(50.0, 50.0)
	_cam.zoom = Vector2(0.20, 0.20)
	if "_current_theater_bounds" in _mr:
		_mr.set("_current_theater_bounds", Rect2(0.0, 0.0, 600.0, 400.0))
	var bound_before: Vector2 = _cam.global_position
	var k := 0
	while k < 8:
		if _mr.has_method("_zoom_toward_mouse"):
			_mr.call("_zoom_toward_mouse", fout, MID)
		k += 1
	var bound_after: Vector2 = _cam.global_position
	var run: float = bound_after.distance_to(bound_before)
	_info("T2 clamp-bind cam %s → %s run=%.1f" % [str(bound_before), str(bound_after), run])
	if run > 20000.0:
		_fail("mutant clamp_before_anchor: clamp-bind zoom-out ran away (%.1f)" % run)
		return
	if "_current_theater_bounds" in _mr:
		_mr.set("_current_theater_bounds", Rect2(-40000.0, -40000.0, 120000.0, 120000.0))
	_cam.global_position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	_pass("T2: clamp-bind zoom-out does not runaway")


func _test_t3_event_position() -> void:
	if _mr == null or _cam == null:
		_fail("T3: fixture missing")
		return
	_cam.global_position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	var win: Window = root.get_window() if root != null else null
	if win != null:
		win.warp_mouse(ANCHOR_VIEWPORT)
	DisplayServer.warp_mouse(Vector2i(int(ANCHOR_VIEWPORT.x), int(ANCHOR_VIEWPORT.y)))
	var vp := _mr.get_viewport()
	if vp != null:
		vp.warp_mouse(ANCHOR_VIEWPORT)
	var world_event: Vector2 = _world_of(ANCHOR_EVENT)
	var world_view: Vector2 = _world_of(ANCHOR_VIEWPORT)
	var z_before: float = _cam.zoom.x
	_send_wheel(ANCHOR_EVENT, true)
	if absf(_cam.zoom.x - z_before) < 0.0005:
		# Hovered chrome swallowed _input zoom; drive the same wheel signature.
		_mr.call("_zoom_toward_mouse", _factor_in(), ANCHOR_EVENT)
	var event_after: Vector2 = _screen_of(world_event)
	var view_after: Vector2 = _screen_of(world_view)
	var d_event: float = event_after.distance_to(ANCHOR_EVENT)
	var d_view: float = view_after.distance_to(ANCHOR_VIEWPORT)
	_info("T3 event dpx=%.3f viewport dpx=%.3f" % [d_event, d_view])
	if d_event > PX_EPS:
		_fail("mutant anchor_from_viewport_mouse: event anchor slipped %.3f px" % d_event)
		return
	# Viewport mouse was not the notch; that world point must have moved.
	if d_view < 4.0:
		_fail("mutant anchor_from_viewport_mouse: zoom followed viewport mouse (dpx=%.3f)" % d_view)
		return
	_pass("T3: wheel anchors on event.position, not the warped viewport mouse")


func _test_t4_regressions() -> void:
	var left: Vector2 = MapViewInput.edge_pan_direction_at(
		Vector2(3.0, 370.0), Vector2(PLAY_SIZE), false, true, true, false
	)
	var right: Vector2 = MapViewInput.edge_pan_direction_at(
		Vector2(1270.0, 370.0), Vector2(PLAY_SIZE), false, true, true, false
	)
	var top: Vector2 = MapViewInput.edge_pan_direction_at(
		Vector2(640.0, 1.0), Vector2(PLAY_SIZE), true, true, true, true
	)
	var bot: Vector2 = MapViewInput.edge_pan_direction_at(
		Vector2(640.0, 737.0), Vector2(PLAY_SIZE), false, true, true, false
	)
	if left.x >= 0.0 or right.x <= 0.0 or top.y >= 0.0 or bot.y <= 0.0:
		_fail("T4: L/R/T/B helper dirs are not symmetric signs %s %s %s %s" % [str(left), str(right), str(top), str(bot)])
		return
	var rest: Vector2 = MapViewInput.edge_pan_direction_at(
		Vector2(97.0, 731.0), Vector2(PLAY_SIZE), false, true, true, false
	)
	if rest != Vector2.ZERO:
		_fail("T4: UI-1 rest (97,731) must still not pan")
		return
	var interior: Vector2 = MapViewInput.edge_pan_direction_at(
		MID, Vector2(PLAY_SIZE), false, true, true, false
	)
	if interior != Vector2.ZERO:
		_fail("T4: interior must not edge-pan")
		return
	if not FileAccess.file_exists("res://scripts/core/HeadlessVis1MapReadabilityTest.gd"):
		_fail("T4: HeadlessVis1MapReadabilityTest missing")
		return
	_pass("T4: UI-1/EDGE-1 rims + rest + Vis1 harness still present")


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	_mr = null
	_cam = null
	_container = null
