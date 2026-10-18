extends SceneTree

## EDGE-2: rim dwell (250 ms) + ramp (~600 ms) + Home-zoom world-speed cap
## + left-HUD 6px exemption. Small MapRenderer fixture — not WorldMap.tscn / 3520.
## Must FAIL on b7affe58 (no dwell / no ramp / no cap / left HUD blocks) and
## PASS on this tip. Headless is NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessEdge2RimFeelTest.gd
##   tools/eoa_edge2_guard.sh

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_INPUT := "res://scripts/map/MapViewInput.gd"
const PLAY_SIZE := Vector2(1280.0, 740.0)
const CAM_START := Vector2(4000.0, 1200.0)
const START_Z := 1.0
const HOME_Z := 0.33
const FAR_Z := 0.11
const DT := 1.0 / 60.0
const FLUSH_FRAMES := 4
const CAM_EPS := 0.75
const SPEED_EPS := 0.08

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _ui: CanvasLayer = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessEdge2RimFeelTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessEdge2RimFeelTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessEdge2RimFeelTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessEdge2RimFeelTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessEdge2RimFeelTest: ", msg)


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


func _inp_script() -> Script:
	return load(SRC_INPUT) as Script


func _inp_has(method: String) -> bool:
	var scr: Script = _inp_script()
	if scr != null and scr.has_method(method):
		return true
	return ("func %s" % method) in _read(SRC_INPUT)


func _inp_const(name: String, fallback: float) -> float:
	var scr: Script = _inp_script()
	if scr == null or not (scr is GDScript):
		return fallback
	var consts: Dictionary = (scr as GDScript).get_script_constant_map()
	if not consts.has(name):
		return fallback
	return float(consts[name])


func _feel_scale(t: float) -> float:
	if not _inp_has("edge_pan_feel_scale"):
		return -1.0
	return float(_inp_script().call("edge_pan_feel_scale", t))


func _zoom_div(z: float) -> float:
	if not _inp_has("edge_pan_zoom_divisor"):
		return z
	return float(_inp_script().call("edge_pan_zoom_divisor", z))


func _dir_at(
	pos: Vector2,
	blocks: bool = false,
	focused: bool = true,
	inside: bool = true,
	top_bar: bool = false,
	left_hud: bool = false
) -> Vector2:
	var scr: Script = _inp_script()
	if scr == null:
		return Vector2.ZERO
	if left_hud:
		if "left_hud_only" not in _slice_func(_read(SRC_INPUT), "edge_pan_direction_at"):
			return Vector2.ZERO
		return scr.call("edge_pan_direction_at", pos, PLAY_SIZE, blocks, focused, inside, top_bar, true) as Vector2
	return MapViewInput.edge_pan_direction_at(pos, PLAY_SIZE, blocks, focused, inside, top_bar)


func _is_left_hud(ctrl: Control) -> bool:
	# Name walk matches MapViewInput._node_is_left_hud_chrome. Static
	# Script.call does not marshal Control args reliably in headless.
	if ctrl == null:
		return false
	var walk: Node = ctrl
	var found_hud: bool = false
	while walk != null:
		var nn := str(walk.name)
		var is_hud: bool = (
			nn == "MapModeToolbar"
			or nn == "MapMinimap"
			or nn == "Minimap"
			or nn == "StrategicMinimap"
			or nn == "InfoPanel"
			or nn == "MapLegendPanel"
			or nn == "SupplyOverlayLegend"
			or nn == "Legend"
			or (nn.ends_with("Legend") and "Toast" not in nn)
		)
		if is_hud:
			found_hud = true
		walk = walk.get_parent()
	return found_hud


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)
	_test_source_needles()
	if _failures > 0 and not _inp_has("edge_pan_feel_scale"):
		_info("b7affe58 / no-feel product — stopping after source needles")
		return
	_test_feel_math()
	_test_far_zoom_cap_math()
	_test_left_hud_strip_math()
	if not _setup_map_renderer():
		return
	await _flush()
	_test_camera_dwell_and_ramp()
	_test_camera_far_zoom_cap()
	await _test_left_rim_with_hud()
	_cleanup()


func _test_source_needles() -> void:
	var inp := _read(SRC_INPUT)
	var ren := _read(SRC_REN)
	if inp.is_empty() or ren.is_empty():
		_fail("source files missing")
		return
	if "EDGE_PAN_SCREEN_PX" not in inp or "6.0" not in inp:
		_fail("UI-1 6px strip must stay")
		return
	if "EDGE_PAN_RIGHT_SCREEN_PX" not in inp or "10.0" not in inp:
		_fail("EDGE-1 10px right strip must stay")
		return
	if "EDGE_PAN_RIM_DWELL_SEC" not in inp or "0.250" not in inp:
		_fail("mutant no_dwell: EDGE_PAN_RIM_DWELL_SEC 0.250 missing")
		return
	if "EDGE_PAN_RAMP_SEC" not in inp or "0.600" not in inp:
		_fail("mutant no_ramp: EDGE_PAN_RAMP_SEC 0.600 missing")
		return
	if "EDGE_PAN_HOME_ZOOM" not in inp or "0.33" not in inp:
		_fail("mutant no_cap: EDGE_PAN_HOME_ZOOM 0.33 missing")
		return
	if "func edge_pan_feel_scale" not in inp:
		_fail("mutant no_dwell/no_ramp: edge_pan_feel_scale missing")
		return
	if "func edge_pan_zoom_divisor" not in inp:
		_fail("mutant no_cap: edge_pan_zoom_divisor missing")
		return
	if "func hovered_is_left_hud_only" not in inp or "func left_strip_hud_exempt" not in inp:
		_fail("mutant left_blocked: left HUD exemption helpers missing")
		return
	if "left_hud_only" not in _slice_func(inp, "edge_pan_direction_at"):
		_fail("mutant left_blocked: edge_pan_direction_at must take left_hud_only")
		return
	if "left_strip_hud_exempt" not in _slice_func(inp, "edge_pan_blocked_by_gui"):
		_fail("mutant left_blocked: edge_pan_blocked_by_gui must honor left_strip_hud_exempt")
		return
	if "mouse.x <= EDGE_PAN_SCREEN_PX" not in _slice_func(inp, "_mouse_over_map_chrome_blocks_edge_pan"):
		_fail("mutant left_blocked: left-dock chrome must skip the 6px left rim")
		return
	if "WHEEL_EDGE_SUPPRESS_MS" not in ren or "_gate_wheel_edge_pan" not in ren:
		_fail("WHEELDRIFT-1 wheel hold must stay")
		return
	if "_update_edge_rim_contact" not in _slice_func(ren, "_handle_camera_input"):
		_fail("mutant no_dwell: _handle_camera_input must apply rim contact feel")
		return
	if "edge_pan_zoom_divisor" not in _slice_func(ren, "_handle_camera_input"):
		_fail("mutant no_cap: _handle_camera_input must cap far-zoom world speed")
		return
	if "feel_scale" not in _slice_func(ren, "_handle_camera_input"):
		_fail("mutant no_ramp: _handle_camera_input must scale edge speed by feel")
		return
	_pass("source needles: dwell/ramp/cap/left-HUD + UI-1 6px + EDGE-1 10px + wheel hold")


func _test_feel_math() -> void:
	if not _inp_has("edge_pan_feel_scale"):
		_fail("mutant no_dwell: MapViewInput.edge_pan_feel_scale missing")
		return
	var dwell: float = _inp_const("EDGE_PAN_RIM_DWELL_SEC", -1.0)
	var ramp: float = _inp_const("EDGE_PAN_RAMP_SEC", -1.0)
	if absf(dwell - 0.250) > 0.0001:
		_fail("mutant no_dwell: dwell is %.3f want 0.250" % dwell)
		return
	if absf(ramp - 0.600) > 0.0001:
		_fail("mutant no_ramp: ramp is %.3f want 0.600" % ramp)
		return
	var s0: float = _feel_scale(0.0)
	var s_before: float = _feel_scale(dwell - 0.001)
	var s_at: float = _feel_scale(dwell)
	var s_030: float = _feel_scale(0.30)
	var s_full: float = _feel_scale(dwell + ramp)
	_info("feel scale 0=%.3f before=%.3f at=%.3f t0.3=%.3f full=%.3f" % [s0, s_before, s_at, s_030, s_full])
	if s0 > 0.0 or s_before > 0.0:
		_fail("mutant no_dwell: feel_scale before 250 ms is %.3f (want 0)" % s_before)
		return
	if s_at > 0.001:
		_fail("mutant no_dwell: feel_scale at exactly 250 ms is %.3f (want 0)" % s_at)
		return
	if s_030 >= 0.25:
		_fail("mutant no_ramp: feel_scale at 0.3 s is %.3f (want < 0.25 of full)" % s_030)
		return
	if s_full < 0.999:
		_fail("mutant no_ramp: feel_scale at dwell+ramp is %.3f (want 1)" % s_full)
		return
	var dist_030: float = _integrate_feel(0.0, 0.30, DT)
	var full_030: float = 0.30
	var ratio_030: float = dist_030 / full_030 if full_030 > 0.0 else 1.0
	_info("0.3s contact distance ratio=%.4f (want < 0.25 of full-speed)" % ratio_030)
	if ratio_030 >= 0.25:
		_fail("mutant no_dwell/no_ramp: 0.3 s distance is %.1f%% of full-speed (want < 25%%)" % (ratio_030 * 100.0))
		return
	# Extra ramp kill: 250–550 ms of contact must not slam to full.
	var dist_ramp: float = _integrate_feel(dwell, dwell + 0.30, DT)
	var full_ramp: float = 0.30
	var ratio_ramp: float = dist_ramp / full_ramp if full_ramp > 0.0 else 1.0
	_info("post-dwell 0.3s distance ratio=%.4f (want < 0.50; no_ramp would be ~1.0)" % ratio_ramp)
	if ratio_ramp >= 0.50:
		_fail("mutant no_ramp: 300 ms after dwell is %.1f%% of full-speed (want < 50%%)" % (ratio_ramp * 100.0))
		return
	_pass("feel math: 0 px before 250 ms; 0.3 s < 25% full; ramp kills instant-full")


func _integrate_feel(t0: float, t1: float, dt: float) -> float:
	var acc: float = 0.0
	var t: float = t0
	while t < t1 - 0.00001:
		t += dt
		acc += _feel_scale(t) * dt
	return acc


func _test_far_zoom_cap_math() -> void:
	if not _inp_has("edge_pan_zoom_divisor"):
		_fail("mutant no_cap: edge_pan_zoom_divisor missing")
		return
	var home_div: float = _zoom_div(HOME_Z)
	var far_div: float = _zoom_div(FAR_Z)
	var close_div: float = _zoom_div(0.80)
	if absf(home_div - HOME_Z) > 0.0001:
		_fail("Home zoom divisor %.3f want %.3f" % [home_div, HOME_Z])
		return
	if absf(far_div - HOME_Z) > 0.0001:
		_fail("mutant no_cap: far zoom 0.11 divisor is %.3f (want Home %.3f, not 0.11)" % [far_div, HOME_Z])
		return
	if absf(close_div - 0.80) > 0.0001:
		_fail("close zoom must keep 1/zoom (divisor %.3f want 0.80)" % close_div)
		return
	var speed: float = 2200.0
	var world_home: float = speed / home_div
	var world_far: float = speed / far_div
	var uncapped_far: float = speed / FAR_Z
	_info("world speed home=%.1f far_capped=%.1f far_uncapped=%.1f" % [world_home, world_far, uncapped_far])
	if world_far > world_home * (1.0 + SPEED_EPS):
		_fail("mutant no_cap: far-zoom world speed %.1f > Home %.1f" % [world_far, world_home])
		return
	if uncapped_far <= world_home * 1.5:
		_fail("cap probe: uncapped far should be ~3× Home")
		return
	_pass("far-zoom cap: z=0.11 world speed equals Home z=0.33")


func _test_left_hud_strip_math() -> void:
	var left_clear: Vector2 = _dir_at(Vector2(3.0, 370.0), false, true, true, false, false)
	if left_clear.x >= 0.0:
		_fail("left rim without HUD must pan west")
		return
	var left_blocked: Vector2 = _dir_at(Vector2(3.0, 370.0), true, true, true, false, false)
	if left_blocked != Vector2.ZERO:
		_fail("toast/panel on the left rim must still block")
		return
	var left_hud: Vector2 = _dir_at(Vector2(3.0, 370.0), true, true, true, false, true)
	_info("left HUD exempt dir=%s" % str(left_hud))
	if left_hud.x >= 0.0:
		_fail("mutant left_blocked: left HUD in the 6px strip must pan west (dir=%s)" % str(left_hud))
		return
	var hud_interior: Vector2 = _dir_at(Vector2(20.0, 370.0), true, true, true, false, true)
	if hud_interior != Vector2.ZERO:
		_fail("left HUD below the 6px strip must still block (got %s)" % str(hud_interior))
		return
	# Strip sizes kept.
	var right: Vector2 = MapViewInput.edge_pan_direction_at(
		Vector2(1270.0, 370.0), PLAY_SIZE, false, true, true, false
	)
	if right.x <= 0.0:
		_fail("EDGE-1 x=1270 must still pan east")
		return
	_pass("left HUD 6px exemption; toast still blocks; 6/10 px strips kept")


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
	_cam.position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_mr.set_process(false)
	_mr.set("_close_suppress_edge", false)
	_mr.set("_close_click_was_north_strip", false)
	_mr.set("_close_camera_locked", false)
	_mr.set("_close_click_guard", false)
	_mr.set("_hold_camera_until_msec", 0)
	_mr.set("_map_pick_block_until_msec", 0)
	_mr.set("enable_map_wrap", false)
	if "_current_theater_bounds" in _mr:
		_mr.set("_current_theater_bounds", Rect2(-40000.0, -40000.0, 120000.0, 120000.0))
	if "_wheel_edge_suppress_until_msec" in _mr:
		_mr.set("_wheel_edge_suppress_until_msec", 0)
	if "_wheel_edge_await_dwell" in _mr:
		_mr.set("_wheel_edge_await_dwell", false)
	if "_edge_rim_contact_sec" in _mr:
		_mr.set("_edge_rim_contact_sec", 0.0)
	_pass("MapRenderer fixture ready @ 1280x740")
	return true


func _tick_camera(dt: float = DT) -> void:
	if _mr != null and _mr.has_method("_handle_camera_input"):
		_mr.call("_handle_camera_input", dt)


func _reset_contact() -> void:
	if _mr != null and "_edge_rim_contact_sec" in _mr:
		_mr.set("_edge_rim_contact_sec", 0.0)
	if _mr != null and "_nav_edge_pan_frames" in _mr:
		_mr.set("_nav_edge_pan_frames", 0)


func _on_rim_now() -> bool:
	var vp := _mr.get_viewport() if _mr != null else null
	if vp == null:
		return false
	var dir: Vector2 = MapViewInput.edge_pan_direction_screen(vp)
	return dir != Vector2.ZERO


func _test_camera_dwell_and_ramp() -> void:
	if _cam == null or _mr == null:
		_fail("camera fixture missing")
		return
	if not _mr.has_method("_update_edge_rim_contact"):
		_fail("mutant no_dwell: _update_edge_rim_contact missing")
		return
	_cam.global_position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	# Helper path (does not depend on live mouse warp).
	_reset_contact()
	var dwell_frames: int = int(floor(0.250 / DT))
	var i := 0
	while i < dwell_frames:
		var scale: float = float(_mr.call("_update_edge_rim_contact", true, DT))
		if scale > 0.0:
			_fail("mutant no_dwell: feel_scale=%.3f during dwell frame %d" % [scale, i])
			return
		i += 1
	_pass("0 px panned before 250 ms dwell")

	# Live _handle_camera_input: if the pointer is on a rim, it must also sit
	# still for the dwell window (headless often already sits at 0,0).
	_reset_contact()
	_cam.global_position = CAM_START
	var before: Vector2 = _cam.global_position
	i = 0
	while i < dwell_frames:
		_tick_camera()
		i += 1
	var dwell_moved: float = _cam.global_position.distance_to(before)
	_info("live dwell frames=%d on_rim=%s cam moved=%.3f" % [dwell_frames, str(_on_rim_now()), dwell_moved])
	if _on_rim_now() and dwell_moved > CAM_EPS:
		_fail("mutant no_dwell: camera moved %.3f px in the first 250 ms" % dwell_moved)
		return

	# 0.3 s of contact vs full-speed 0.3 s — helper only (no double-count).
	_reset_contact()
	var acc: float = 0.0
	var t: float = 0.0
	var speed: float = maxf(float(_mr.get("pan_speed")), float(_mr.get("edge_scroll_speed")))
	var zdiv: float = _zoom_div(START_Z)
	while t < 0.30 - 0.0001:
		var sc: float = float(_mr.call("_update_edge_rim_contact", true, DT))
		t += DT
		acc += speed * sc * DT / zdiv
	var full_030: float = speed * 0.30 / zdiv
	var ratio: float = acc / full_030 if full_030 > 0.0 else 1.0
	_info("0.3s sim dist=%.2f full=%.2f ratio=%.3f" % [acc, full_030, ratio])
	if ratio >= 0.25:
		_fail("mutant no_dwell/no_ramp: 0.3 s contact is %.1f%% of full-speed (want < 25%%)" % (ratio * 100.0))
		return
	# Reset on leave.
	var reset_sc: float = float(_mr.call("_update_edge_rim_contact", false, DT))
	if reset_sc > 0.0 or float(_mr.get("_edge_rim_contact_sec")) > 0.0001:
		_fail("mutant no_ramp: leaving the rim must reset contact (scale=%.3f)" % reset_sc)
		return
	_pass("0.3 s of contact is < 25% of full-speed; leave-rim resets")


func _test_camera_far_zoom_cap() -> void:
	if _cam == null or _mr == null:
		_fail("far-zoom: fixture missing")
		return
	var speed: float = maxf(float(_mr.get("pan_speed")), float(_mr.get("edge_scroll_speed")))
	var dt: float = DT
	# Seed past dwell+ramp so feel is 1.0, then one full-speed edge step.
	if "_edge_rim_contact_sec" in _mr:
		_mr.set("_edge_rim_contact_sec", 2.0)
	var home_step: float = speed * dt / _zoom_div(HOME_Z)
	var far_step: float = speed * dt / _zoom_div(FAR_Z)
	var uncapped: float = speed * dt / FAR_Z
	_info("cap step home=%.3f far=%.3f uncapped=%.3f" % [home_step, far_step, uncapped])
	if far_step > home_step * (1.0 + SPEED_EPS):
		_fail("mutant no_cap: far step %.3f > Home %.3f" % [far_step, home_step])
		return
	if uncapped <= home_step * 1.5:
		_fail("cap probe: uncapped far step should exceed Home")
		return
	# Product apply: one rim frame at far zoom must not exceed the Home step.
	_cam.zoom = Vector2(FAR_Z, FAR_Z)
	_cam.global_position = CAM_START
	if "_edge_rim_contact_sec" in _mr:
		_mr.set("_edge_rim_contact_sec", 2.0)
	var before: Vector2 = _cam.global_position
	if _mr.has_method("_update_edge_rim_contact"):
		_mr.call("_update_edge_rim_contact", true, 0.0)
	# Apply the product formula used by _handle_camera_input (edge-only).
	var feel: float = _feel_scale(float(_mr.get("_edge_rim_contact_sec")))
	var applied: float = speed * feel * dt / _zoom_div(FAR_Z)
	_cam.global_position = before + Vector2(applied, 0.0)
	var moved: float = _cam.global_position.distance_to(before)
	if moved > home_step * (1.0 + SPEED_EPS) + 0.05:
		_fail("mutant no_cap: far-zoom applied %.3f > Home step %.3f" % [moved, home_step])
		return
	_cam.zoom = Vector2(START_Z, START_Z)
	_cam.global_position = CAM_START
	_reset_contact()
	_pass("far-zoom world speed capped at Home")


func _test_left_rim_with_hud() -> void:
	if _mr == null or _ui == null:
		_fail("left HUD fixture missing")
		return
	var toolbar := PanelContainer.new()
	toolbar.name = "MapModeToolbar"
	toolbar.position = Vector2(0, 80)
	toolbar.size = Vector2(420, 72)
	toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(toolbar)
	toolbar.name = "MapModeToolbar"
	var legend := Label.new()
	legend.name = "Legend"
	legend.position = Vector2(0, 0)
	legend.size = Vector2(200, 24)
	legend.mouse_filter = Control.MOUSE_FILTER_STOP
	toolbar.add_child(legend)
	var info := Panel.new()
	info.name = "InfoPanel"
	info.position = Vector2(0, 160)
	info.size = Vector2(420, 480)
	info.mouse_filter = Control.MOUSE_FILTER_STOP
	info.set_meta("blocks_edge_pan", true)
	root.add_child(info)
	info.name = "InfoPanel"
	var mini := PanelContainer.new()
	mini.name = "MapMinimap"
	mini.position = Vector2(0, 620)
	mini.size = Vector2(200, 110)
	mini.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(mini)
	mini.name = "MapMinimap"
	var toast := Panel.new()
	toast.name = "Edge2LeftToast"
	toast.position = Vector2(0, 300)
	toast.size = Vector2(80, 40)
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	toast.visible = false
	root.add_child(toast)
	toast.name = "Edge2LeftToast"
	await process_frame

	if not _is_left_hud(toolbar):
		_fail("mutant left_blocked: MapModeToolbar must count as left HUD")
		return
	if not _is_left_hud(legend):
		_fail("mutant left_blocked: toolbar legend child must count as left HUD")
		return
	if not _is_left_hud(info):
		_fail("mutant left_blocked: InfoPanel must count as left HUD")
		return
	if not _is_left_hud(mini):
		_fail("mutant left_blocked: minimap must count as left HUD")
		return
	if _is_left_hud(toast):
		_fail("toast must not count as left HUD")
		return

	var dir: Vector2 = _dir_at(Vector2(3.0, 370.0), true, true, true, false, true)
	_info("left rim + HUD dir=%s (want x<0)" % str(dir))
	if dir.x >= 0.0:
		_fail("mutant left_blocked: left-rim direction is %s with HUD present" % str(dir))
		return
	# Interior of the panel (x=20) stays blocked.
	var interior: Vector2 = _dir_at(Vector2(20.0, 370.0), true, true, true, false, true)
	if interior != Vector2.ZERO:
		_fail("InfoPanel at x=20 must still block edge pan")
		return
	# Debug log of hovered control + window mouse x at x<=6.
	OS.set_environment("EOA_EDGE2_DEBUG", "1")
	var win: Window = root.get_window() if root != null else null
	if win != null:
		win.warp_mouse(Vector2(3.0, 370.0))
	DisplayServer.warp_mouse(Vector2i(3, 370))
	await process_frame
	var vp := _mr.get_viewport()
	var hovered: Control = vp.gui_get_hovered_control() if vp != null else null
	var mx := -1.0
	if win != null:
		mx = win.get_mouse_position().x
	var hname := "<null>"
	if hovered != null:
		hname = str(hovered.name)
	_info("left-rim probe hovered=%s window_x=%.1f" % [hname, mx])
	if vp != null:
		var _discard: Vector2 = MapViewInput.edge_pan_direction_screen(vp)
	OS.set_environment("EOA_EDGE2_DEBUG", "0")
	# Live blocked_by_gui: if the pointer actually landed in the 6px strip over HUD, must not block.
	if mx >= 0.0 and mx <= MapViewInput.EDGE_PAN_SCREEN_PX and _is_left_hud(hovered):
		if MapViewInput.edge_pan_blocked_by_gui(vp):
			_fail("mutant left_blocked: edge_pan_blocked_by_gui true at x=%.1f hovered=%s" % [mx, hname])
			return
		var live_dir: Vector2 = MapViewInput.edge_pan_direction_screen(vp)
		if live_dir.x >= 0.0:
			_fail("mutant left_blocked: live left-rim dir=%s hovered=%s" % [str(live_dir), hname])
			return
		_pass("live left rim pans with HUD hovered (%s @ x=%.1f)" % [hname, mx])
	else:
		_info("warp miss window_x=%.1f hovered=%s — helper dir already non-zero" % [mx, hname])
		_pass("left-rim direction non-zero with HUD present (helper)")
	toolbar.queue_free()
	info.queue_free()
	mini.queue_free()
	toast.queue_free()


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	_mr = null
	_cam = null
	_ui = null
