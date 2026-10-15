extends SceneTree

## WINDOWED RENDER-1 live-boot cold L-on. xvfb is NOT product Play.
## Real TestScenario. KEY_L via Input.parse_input_event; t0 is stamped in
## MapRenderer._input. Stop at frame_post_draw of the first mesh_calls>0
## frame; also report frame2 and a same-run L-off frame2.
##
##   tools/eoa_render1_live_cold_guard.sh

const KOELN := 710417
const CLOSE_Z := 3.2
const WAIT_MAP_SECS := 420
const PREBUILD_WAIT_FRAMES := 480
const MAX_DELTA_MS := 250.0
const MAX_BA_RATIO := 0.75
const HUE_TOL := 0.10
const A_FRAME2_DEFAULT_MS := 611.0
const A_TEAL := Vector2(37000.0, 45000.0)
const A_OLIVE := Vector2(7000.0, 9000.0)
const A_ORANGE := Vector2(4000.0, 7000.0)

var _failures: int = 0
var _t0_msec: int = 0
var _out_dir: String = ""
var _post_draw_n: int = 0
var _armed: bool = false
var _got_frame1: bool = false
var _got_frame2: bool = false
var _frame1_ms: float = -1.0
var _frame2_ms: float = -1.0
var _loff_frame2_ms: float = -1.0
var _t0_usec: int = 0
var _last_wait_log: int = -1


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("WindowedRender1LiveColdGuard: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("WindowedRender1LiveColdGuard: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] WindowedRender1LiveColdGuard: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] WindowedRender1LiveColdGuard: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] WindowedRender1LiveColdGuard: ", msg)


func _run() -> void:
	var ds := DisplayServer.get_name()
	_info("DisplayServer=%s" % ds)
	if ds == "headless":
		_fail("headless_display: run via tools/eoa_render1_live_cold_guard.sh")
		return
	DisplayServer.window_set_size(Vector2i(1280, 740))
	_out_dir = OS.get_environment("EOA_RENDER1_LIVE_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-render1-live"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail("scene_load_%d" % err)
		return
	if not await _wait_map_ready():
		return
	_pause_clock()
	_freeze_boot_camera_fighters()
	_frame_over_koln(CLOSE_Z)
	var mr := _map_renderer()
	if mr == null:
		_fail("MapRenderer missing")
		return
	if not await _wait_prebuild(mr):
		return
	# TestRunner smoke +6d / deferred_grand_visuals can steal the camera
	# (Play MIXED captured Japan). Re-pin Köln at close zoom before KEY_L.
	_freeze_map_renderer_process()
	_frame_over_koln(CLOSE_Z)
	if not _camera_is_on_koln(CLOSE_Z):
		_fail("camera not on Köln after prebuild")
		return
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	await _measure_lon(mr)
	_check_roles(mr)
	_frame_over_koln(CLOSE_Z)
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	await _check_hue()
	await _measure_loff(mr)
	_check_bars()
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func _wait_map_ready() -> bool:
	while true:
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed >= WAIT_MAP_SECS:
			_fail("map_timeout")
			return false
		if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
			_last_wait_log = elapsed
			_info("wait_map elapsed=%d n=%d" % [elapsed, _province_count()])
		_dismiss_title()
		if _map_is_ready():
			_info("map_ready elapsed=%d n=%d" % [elapsed, _province_count()])
			var i := 0
			while i < 12:
				await process_frame
				i += 1
			return true
		await process_frame
	return false


func _wait_prebuild(mr: Node) -> bool:
	var i := 0
	while i < PREBUILD_WAIT_FRAMES:
		if mr.has_method("is_supply_ring_prebuild_ready") and bool(mr.call("is_supply_ring_prebuild_ready")):
			var st: Dictionary = {}
			if mr.has_method("get_supply_ring_prebuild_stats"):
				st = mr.call("get_supply_ring_prebuild_stats") as Dictionary
			_info(
				"idle_prebuild done items=%d max_step=%.3f"
				% [int(st.get("item_count", -1)), float(st.get("max_step_ms", -1.0))]
			)
			if float(st.get("max_step_ms", 0.0)) > 8.0:
				_fail("idle prebuild max_step=%.3f > 8.0" % float(st.get("max_step_ms", 0.0)))
			return true
		await process_frame
		i += 1
	_fail("idle prebuild did not finish")
	return false


func _on_frame_post_draw() -> void:
	_post_draw_n += 1
	if not _armed:
		return
	var mr := _map_renderer()
	if mr == null:
		return
	var mesh_n := _mesh_calls(mr)
	var now := Time.get_ticks_usec()
	if _t0_usec <= 0 and mr.has_method("get_supply_lon_input_t0_usec"):
		_t0_usec = int(mr.call("get_supply_lon_input_t0_usec"))
	if _t0_usec <= 0:
		return
	var ms := float(now - _t0_usec) / 1000.0
	if not _got_frame1 and mesh_n > 0:
		_got_frame1 = true
		_frame1_ms = ms
		return
	if _got_frame1 and not _got_frame2:
		_got_frame2 = true
		_frame2_ms = ms
		_armed = false


func _mesh_calls(mr: Node) -> int:
	if mr.has_method("get_supply_batch_draw_stats"):
		var st: Dictionary = mr.call("get_supply_batch_draw_stats") as Dictionary
		return int(st.get("mesh_calls", 0))
	return 0


func _press_l() -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_L
	ev.physical_keycode = KEY_L
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	var ev_up := InputEventKey.new()
	ev_up.pressed = false
	ev_up.echo = false
	ev_up.keycode = KEY_L
	ev_up.physical_keycode = KEY_L
	Input.parse_input_event(ev_up)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _measure_lon(mr: Node) -> void:
	_got_frame1 = false
	_got_frame2 = false
	_frame1_ms = -1.0
	_frame2_ms = -1.0
	_t0_usec = 0
	_armed = true
	_press_l()
	if mr.has_method("get_supply_lon_input_t0_usec"):
		_t0_usec = int(mr.call("get_supply_lon_input_t0_usec"))
	if _t0_usec <= 0:
		_fail("KEY_L t0 missing (MapRenderer._input did not stamp)")
		_armed = false
		return
	var guard := 0
	while (not _got_frame2) and guard < 90:
		await process_frame
		guard += 1
	_armed = false
	_info("live L-on frame1=%.3f frame2=%.3f mesh=%d" % [_frame1_ms, _frame2_ms, _mesh_calls(mr)])
	if _frame1_ms < 0.0 or _frame2_ms < 0.0:
		_fail("live L-on did not present rings frame1=%.3f frame2=%.3f" % [_frame1_ms, _frame2_ms])


func _measure_loff(mr: Node) -> void:
	_got_frame1 = false
	_got_frame2 = false
	var t0 := Time.get_ticks_usec()
	_t0_usec = t0
	_press_l()
	var draws := 0
	var first_ms := -1.0
	var second_ms := -1.0
	var guard := 0
	while draws < 2 and guard < 60:
		await RenderingServer.frame_post_draw
		draws += 1
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if draws == 1:
			first_ms = ms
		else:
			second_ms = ms
		guard += 1
	_loff_frame2_ms = second_ms
	_info("live L-off frame1=%.3f frame2=%.3f mesh=%d" % [first_ms, _loff_frame2_ms, _mesh_calls(mr)])
	if _loff_frame2_ms < 0.0:
		_fail("live L-off frame2 missing")


func _a_frame2() -> float:
	var env := OS.get_environment("EOA_RENDER1_A_FRAME2_MS").strip_edges()
	if not env.is_empty() and env.is_valid_float():
		return float(env)
	return A_FRAME2_DEFAULT_MS


func _check_bars() -> void:
	var delta := _frame2_ms - _loff_frame2_ms
	var a_ms := _a_frame2()
	var ba := 0.0
	if a_ms > 0.0:
		ba = _frame2_ms / a_ms
	print(
		"live_boot L-on_frame1=%.3f L-on_frame2=%.3f L-off_frame2=%.3f delta=%.3f B/A=%.3f A_frame2=%.3f"
		% [_frame1_ms, _frame2_ms, _loff_frame2_ms, delta, ba, a_ms]
	)
	if delta > MAX_DELTA_MS:
		_fail("Δ(L-on − L-off frame2)=%.1f ms > %.0f" % [delta, MAX_DELTA_MS])
	else:
		_pass("Δ(L-on − L-off frame2)=%.1f ms (bar %.0f)" % [delta, MAX_DELTA_MS])
	if ba > MAX_BA_RATIO or ba <= 0.0:
		_fail("frame2 B/A=%.3f want <= %.2f (A=%.1f B=%.1f)" % [ba, MAX_BA_RATIO, a_ms, _frame2_ms])
	else:
		_pass("frame2 B/A=%.3f (A=%.1f B=%.1f)" % [ba, a_ms, _frame2_ms])


func _check_roles(mr: Node) -> void:
	if not mr.has_method("supply_roles_match_fresh_lon"):
		_fail("live roles: supply_roles_match_fresh_lon missing")
		return
	var hist: Dictionary = {}
	if mr.has_method("get_supply_roles_histogram"):
		hist = mr.call("get_supply_roles_histogram") as Dictionary
	_info("live L-on role histogram=%s" % str(hist))
	print("role_histogram %s" % str(hist))
	if not bool(mr.call("supply_roles_match_fresh_lon")):
		_fail("live L-on roles != fresh _supply_highlight_roles() hist=%s" % str(hist))
	else:
		_pass("live L-on roles == fresh compute %s" % str(hist))


func _check_hue() -> void:
	var i := 0
	while i < 4:
		_frame_over_koln(CLOSE_Z)
		await process_frame
		i += 1
	if not _camera_is_on_koln(CLOSE_Z):
		_fail("hue: camera not on Köln close-zoom")
		return
	RenderingServer.force_draw()
	_frame_over_koln(CLOSE_Z)
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		_fail("hue: no viewport")
		return
	var tex := vp.get_texture()
	if tex == null:
		_fail("hue: no viewport texture")
		return
	var img := tex.get_image()
	if img == null:
		_fail("hue: capture failed")
		return
	var path := "%s/close_lon.png" % _out_dir
	img.save_png(path)
	var buckets := _hue_buckets(img)
	var teal := int(buckets.get("teal", 0))
	var olive := int(buckets.get("olive", 0))
	var orange := int(buckets.get("orange", 0))
	print(
		"hue_buckets teal=%d olive=%d orange=%d vs A teal=37-45k olive=7-9k orange=4-7k (edge teal, no neon political orange)"
		% [teal, olive, orange]
	)
	# Teal: mesh stroke is thicker than 5df8e7fc polylines; require at least
	# A's floor−10% so we are not B's 2.0–2.5k, and cap at A's ceiling+10%
	# on *edge* pixels so fill interiors cannot inflate the count.
	if teal < A_TEAL.x * (1.0 - HUE_TOL) or teal > A_TEAL.y * (1.0 + HUE_TOL):
		_fail("hue teal=%d not within ±10%% of 5df8e7fc 37-45k" % teal)
	else:
		_pass("hue teal=%d within ±10%% of 5df8e7fc" % teal)
	# Olive: engineer_recommended is the regression. Extra olive fails;
	# fewer than A is OK (A's leftover terrain olive is not required).
	if olive > A_OLIVE.y * (1.0 + HUE_TOL):
		_fail("hue olive=%d above ±10%% of 5df8e7fc 7-9k" % olive)
	else:
		_pass("hue olive=%d <= 5df8e7fc 9k+10%%" % olive)
	if not _within_a(orange, A_ORANGE):
		_fail("hue orange=%d not within ±10%% of 5df8e7fc 4-7k" % orange)
	else:
		_pass("hue orange=%d within ±10%% of 5df8e7fc" % orange)


func _within_a(n: int, band: Vector2) -> bool:
	var lo := band.x * (1.0 - HUE_TOL)
	var hi := band.y * (1.0 + HUE_TOL)
	return float(n) >= lo and float(n) <= hi


func _classify_hue(c: Color) -> String:
	if c.s <= 0.4 or c.v <= 0.5:
		return ""
	if c.h >= 0.38 and c.h < 0.56:
		return "teal"
	if c.h >= 0.14 and c.h < 0.32:
		return "olive"
	# Exclude neon political fills (GER/ITA sat≈0.98) so orange measures
	# ring/glow colour the way 5df8e7fc's 4–7k band did, not country fill.
	if c.h >= 0.03 and c.h < 0.14 and c.s <= 0.80 and c.v <= 0.88:
		return "orange"
	return ""


func _hue_buckets(img: Image) -> Dictionary:
	var teal := 0
	var olive := 0
	var orange := 0
	var w := img.get_width()
	var h := img.get_height()
	# Map area only. Teal is edge pixels so mesh interiors cannot 3× the
	# 5df8e7fc polyline stroke count.
	var y := 40
	while y < h - 1:
		var x := 1
		while x < w - 1:
			var c := img.get_pixel(x, y)
			var kind := _classify_hue(c)
			if kind == "olive":
				olive += 1
			elif kind == "orange":
				orange += 1
			elif kind == "teal":
				var edge := (
					_classify_hue(img.get_pixel(x - 1, y)) != "teal"
					or _classify_hue(img.get_pixel(x + 1, y)) != "teal"
					or _classify_hue(img.get_pixel(x, y - 1)) != "teal"
					or _classify_hue(img.get_pixel(x, y + 1)) != "teal"
				)
				if edge:
					teal += 1
			x += 1
		y += 1
	return {"teal": teal, "olive": olive, "orange": orange}


func _map_is_ready() -> bool:
	if not _title_closed():
		return false
	if _province_count() < 3000:
		return false
	return _map_renderer() != null and _camera() != null


func _title_closed() -> bool:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("living_title_has_closed") and bool(tm.call("living_title_has_closed")):
		return true
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	if boot == null and _province_count() >= 3000:
		return int((Time.get_ticks_msec() - _t0_msec) / 1000.0) >= 8
	return false


func _dismiss_title() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if bool(boot.get("_closed")):
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	elif boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")


func _province_count() -> int:
	var mm: Node = root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _pause_clock() -> void:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)


func _freeze_boot_camera_fighters() -> void:
	# Same pin as WindowedRx1RhinePixelGuard: TestRunner deferred Home /
	# +6d grand visuals must not steal the Köln close-zoom frame.
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_close_camera_locked", true)
		mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 120000)
	var tr := _find_named("TestRunner")
	if tr != null and tr.has_method("set_process"):
		tr.set_process(false)
	var cc := _find_named("CameraController")
	if cc != null:
		if "enable_pan" in cc:
			cc.set("enable_pan", false)
		if "enable_zoom" in cc:
			cc.set("enable_zoom", false)
		cc.set_process(false)
	_info("lock_camera (NOT product Home/Close)")


func _freeze_map_renderer_process() -> void:
	var mr := _map_renderer()
	# After idle prebuild. Stops theater auto-fit from undoing Köln close-zoom.
	if mr != null and mr.has_method("set_process"):
		mr.set_process(false)


func _camera_is_on_koln(zoom: float) -> bool:
	var cam := _camera()
	if cam == null:
		return false
	var dist := cam.global_position.distance_to(_koln_world())
	var z := maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	_info("cam pos=%.1f,%.1f zoom=%.3f koln_dist=%.1f" % [
		cam.global_position.x, cam.global_position.y, z, dist,
	])
	if dist > 520.0:
		return false
	if absf(z - zoom) > 0.35:
		return false
	return true


func _frame_over_koln(zoom: float) -> void:
	var pos := _koln_world()
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
	var mr := _map_renderer()
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	if mr != null and mr.has_method("lock_pixel_guard_camera"):
		mr.call("lock_pixel_guard_camera", pos, zoom)
	else:
		var cam := _camera()
		if cam != null:
			cam.zoom = Vector2(zoom, zoom)
			cam.global_position = pos
			cam.reset_smoothing()
			cam.enabled = true
			cam.make_current()
	_info("frame Köln zoom=%.2f pos=%.1f,%.1f" % [zoom, pos.x, pos.y])


func _koln_world() -> Vector2:
	var mm: Node = root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", KOELN)
		if c != Vector2.ZERO:
			return c
	return Vector2(4254.32 * 1.728, 944.10 * 1.728)


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam := mr.get_node_or_null("MapCamera") as Camera2D
		if cam != null:
			return cam
	var vp := root.get_viewport()
	if vp != null:
		return vp.get_camera_2d()
	return null


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)
