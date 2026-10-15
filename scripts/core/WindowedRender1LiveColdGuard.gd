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
const DEFAULT_A_FILE := "res://docs/evidence/render1/a_live_5df8e7fc.json"

var _failures: int = 0
var _t0_msec: int = 0
var _out_dir: String = ""
var _post_draw_n: int = 0
var _armed: bool = false
var _got_frame1: bool = false
var _got_frame2: bool = false
var _frame1_ms: float = -1.0
var _frame2_ms: float = -1.0
var _loff_frame1_ms: float = -1.0
var _loff_frame2_ms: float = -1.0
var _t0_usec: int = 0
var _t0_before_press: int = 0
var _last_wait_log: int = -1
var _phase: String = ""
var _a_metrics: Dictionary = {}
var _measure_a: bool = false
var _last_hue: Dictionary = {}


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
	_measure_a = OS.get_environment("EOA_RENDER1_MEASURE_A").strip_edges() == "1"
	if not _measure_a:
		_a_metrics = _load_a_metrics()
		if _a_metrics.is_empty():
			_fail("A frame2 missing: set EOA_RENDER1_A_FRAME2_MS, EOA_RENDER1_A_FRAME2_FILE, or run MEASURE_A on 5df8e7fc (A_FRAME2_DEFAULT_MS deleted)")
			return
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
	_feed_batch_view()
	if not _camera_is_on_koln(CLOSE_Z):
		_fail("camera not on Köln after prebuild")
		return
	if _loading_screen_up():
		_fail("LoadingScreen still up after map_ready")
		return
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	await _measure_lon(mr)
	if not _measure_a:
		_check_roles(mr)
	_frame_over_koln(CLOSE_Z)
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	await _check_hue()
	var quiet := 0
	while quiet < 8:
		await process_frame
		quiet += 1
	await _measure_loff(mr)
	_check_bars()
	_write_run_json()
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
		if _province_count() >= 3500:
			_dismiss_loading()
		if _map_is_ready():
			_info("map_ready elapsed=%d n=%d loading=%s" % [
				elapsed, _province_count(), str(_loading_screen_up()),
			])
			var i := 0
			while i < 12:
				await process_frame
				i += 1
			return true
		await process_frame
	return false


func _wait_prebuild(mr: Node) -> bool:
	if not mr.has_method("is_supply_ring_prebuild_ready"):
		_info("A path: no idle prebuild API (5df8e7fc polyline)")
		var settle := 0
		while settle < 24:
			await process_frame
			settle += 1
		return true
	var i := 0
	while i < PREBUILD_WAIT_FRAMES:
		if bool(mr.call("is_supply_ring_prebuild_ready")):
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
	var stamped := _read_lon_t0(mr)
	if stamped > _t0_before_press:
		_t0_usec = stamped
	if _t0_usec <= _t0_before_press:
		return
	var now := Time.get_ticks_usec()
	var ms := float(now - _t0_usec) / 1000.0
	var presented := _overlay_presented(mr)
	if _phase == "lon":
		if not _got_frame1 and presented:
			_got_frame1 = true
			_frame1_ms = ms
			return
		if _got_frame1 and not _got_frame2:
			_got_frame2 = true
			_frame2_ms = ms
			_armed = false
		return
	if _phase == "loff":
		# Wait until the overlay is actually hidden, then the next two
		# post_draw frames. Do not reuse L-on's t0 (parse_input_event is deferred).
		if presented:
			return
		if not _got_frame1:
			_got_frame1 = true
			_loff_frame1_ms = ms
			return
		if not _got_frame2:
			_got_frame2 = true
			_loff_frame2_ms = ms
			_armed = false


func _mesh_calls(mr: Node) -> int:
	if mr.has_method("get_supply_batch_draw_stats"):
		var st: Dictionary = mr.call("get_supply_batch_draw_stats") as Dictionary
		return int(st.get("mesh_calls", 0))
	return 0


func _overlay_presented(mr: Node) -> bool:
	# Hide is supply_mode false. Stale mesh_calls from idle-warm / last L-on
	# _draw must not count as presented (that was the 10–43 ms lie).
	if not bool(mr.get("supply_mode")):
		return false
	var draw_usec := _batch_last_draw_usec(mr)
	if draw_usec > 0:
		return draw_usec > _t0_usec and _mesh_calls(mr) > 0
	if mr.has_method("get_supply_overlay_outline_visible_count"):
		if int(mr.call("get_supply_overlay_outline_visible_count")) > 0:
			return true
	return _count_visible_supply_outlines(mr) > 0


func _batch_last_draw_usec(mr: Node) -> int:
	if mr.has_method("get_supply_batch_draw_stats"):
		var st: Dictionary = mr.call("get_supply_batch_draw_stats") as Dictionary
		var u := int(st.get("draw_usec", 0))
		if u > 0:
			return u
	var layer: Node = null
	if "container" in mr:
		var c: Node = mr.get("container") as Node
		if c != null:
			layer = c.get_node_or_null("SupplyOutlineBatch")
	if layer != null and layer.has_method("get_last_draw_usec"):
		return int(layer.call("get_last_draw_usec"))
	return 0


func _read_lon_t0(mr: Node) -> int:
	if mr != null and mr.has_method("get_supply_lon_input_t0_usec"):
		return int(mr.call("get_supply_lon_input_t0_usec"))
	return 0


func _count_visible_supply_outlines(mr: Node) -> int:
	var nodes: Dictionary = {}
	if "province_nodes" in mr:
		nodes = mr.get("province_nodes") as Dictionary
	var n := 0
	for pid_var in nodes.keys():
		var node: Node = nodes[pid_var] as Node
		if node == null:
			continue
		var line := node.get_node_or_null("SupplyOutline") as Line2D
		if line != null and line.visible:
			n += 1
	return n


func _press_l() -> void:
	# Down only. MapRenderer already ignores key-up (`event.pressed`), but a
	# release would still overwrite t0 if a handler stamps every KEY_L event.
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_L
	ev.physical_keycode = KEY_L
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _measure_lon(mr: Node) -> void:
	_got_frame1 = false
	_got_frame2 = false
	_frame1_ms = -1.0
	_frame2_ms = -1.0
	_t0_before_press = _read_lon_t0(mr)
	_t0_usec = 0
	_phase = "lon"
	_armed = true
	_press_l()
	var guard := 0
	while (not _got_frame2) and guard < 90:
		if _t0_usec <= 0:
			var stamped := _read_lon_t0(mr)
			if stamped > _t0_before_press:
				_t0_usec = stamped
			elif _measure_a and guard >= 1 and stamped <= 0:
				_t0_usec = Time.get_ticks_usec()
				_info("A path: t0 stamped after parse_input_event (no get_supply_lon_input_t0_usec)")
		await process_frame
		guard += 1
	_armed = false
	if not _measure_a and _t0_usec <= _t0_before_press:
		_fail("KEY_L t0 missing (MapRenderer._input did not stamp a new t0)")
	_info(
		"live L-on frame1=%.3f frame2=%.3f presented=%s mesh=%d vis=%d"
		% [
			_frame1_ms, _frame2_ms, str(_overlay_presented(mr)), _mesh_calls(mr),
			_count_visible_supply_outlines(mr),
		]
	)
	if _frame1_ms < 0.0 or _frame2_ms < 0.0:
		_fail("live L-on did not present rings frame1=%.3f frame2=%.3f" % [_frame1_ms, _frame2_ms])


func _measure_loff(mr: Node) -> void:
	_got_frame1 = false
	_got_frame2 = false
	_loff_frame1_ms = -1.0
	_loff_frame2_ms = -1.0
	_t0_before_press = _read_lon_t0(mr)
	_t0_usec = 0
	_phase = "loff"
	_armed = true
	_press_l()
	var guard := 0
	while (not _got_frame2) and guard < 90:
		if _t0_usec <= 0:
			var stamped := _read_lon_t0(mr)
			if stamped > _t0_before_press:
				_t0_usec = stamped
			elif guard >= 1 and stamped <= _t0_before_press:
				_t0_usec = Time.get_ticks_usec()
		await process_frame
		guard += 1
	_armed = false
	_info(
		"live L-off frame1=%.3f frame2=%.3f presented=%s mesh=%d vis=%d"
		% [
			_loff_frame1_ms, _loff_frame2_ms, str(_overlay_presented(mr)),
			_mesh_calls(mr), _count_visible_supply_outlines(mr),
		]
	)
	if _loff_frame2_ms < 0.0:
		_fail("live L-off frame2 missing")


func _a_frame2() -> float:
	var env := OS.get_environment("EOA_RENDER1_A_FRAME2_MS").strip_edges()
	if not env.is_empty() and env.is_valid_float():
		return float(env)
	return float(_a_metrics.get("lon_frame2_ms", 0.0))


func _check_bars() -> void:
	var delta := _frame2_ms - _loff_frame2_ms
	var a_ms := _a_frame2()
	var ba := 0.0
	if a_ms > 0.0:
		ba = _frame2_ms / a_ms
	print(
		"live_boot L-on_frame1=%.3f L-on_frame2=%.3f L-off_frame1=%.3f L-off_frame2=%.3f delta=%.3f B/A=%.3f A_frame2=%.3f"
		% [_frame1_ms, _frame2_ms, _loff_frame1_ms, _loff_frame2_ms, delta, ba, a_ms]
	)
	if _measure_a:
		_pass("MEASURE_A recorded L-on_frame2=%.3f L-off_frame2=%.3f Δ=%.3f (no B/A bar)" % [
			_frame2_ms, _loff_frame2_ms, delta,
		])
		return
	if delta > MAX_DELTA_MS:
		_fail("Δ(L-on − L-off frame2)=%.1f ms > %.0f" % [delta, MAX_DELTA_MS])
	else:
		_pass("Δ(L-on − L-off frame2)=%.1f ms (bar %.0f; Ship ~155 not 10–43)" % [delta, MAX_DELTA_MS])
	if ba > MAX_BA_RATIO or ba <= 0.0:
		_fail("frame2 B/A=%.3f want <= %.2f (A=%.1f B=%.1f)" % [ba, MAX_BA_RATIO, a_ms, _frame2_ms])
	else:
		_pass("frame2 B/A=%.3f (A=%.1f B=%.1f; A from measured 5df8e7fc file)" % [ba, a_ms, _frame2_ms])


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
		_feed_batch_view()
		await process_frame
		i += 1
	if _loading_screen_up():
		_fail("hue: LoadingScreen still covering the map")
		return
	if not _camera_is_on_koln(CLOSE_Z):
		_fail("hue: camera not on Köln close-zoom")
		return
	var mr := _map_renderer()
	if mr != null and not _overlay_presented(mr) and not bool(mr.get("supply_mode")):
		_fail("hue: overlay not on (rings must be visible for ring-edge share)")
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
	_last_hue = buckets
	var teal := int(buckets.get("teal", 0))
	var olive := int(buckets.get("olive", 0))
	var orange := int(buckets.get("orange", 0))
	var edge_n := teal + olive + orange
	var share := 0.0
	if edge_n > 0:
		share = float(teal) / float(edge_n)
	var fill_teal := int(buckets.get("teal_fill", 0))
	var width_proxy := 0.0
	if teal > 0:
		width_proxy = float(fill_teal) / float(teal)
	print(
		"hue_buckets ring_edge teal=%d olive=%d orange=%d share=%.4f fill_teal=%d width_proxy=%.3f (mesh stroke reads thinner than Line2D AA; width_scale option)"
		% [teal, olive, orange, share, fill_teal, width_proxy]
	)
	if teal < 80:
		_fail("hue ring-edge teal=%d too low (LoadingScreen / missed Köln?)" % teal)
		return
	if _measure_a:
		_pass("MEASURE_A hue ring-edge teal=%d share=%.4f width_proxy=%.3f" % [teal, share, width_proxy])
		return
	var a_share := float(_a_metrics.get("hue_teal_share", 0.0))
	var a_teal := int(_a_metrics.get("hue_teal_edge", 0))
	var a_width := float(_a_metrics.get("width_proxy", 0.0))
	if a_share <= 0.0:
		_fail("A ring-edge teal share missing from measured 5df8e7fc file")
		return
	var share_lo := a_share * (1.0 - HUE_TOL)
	var share_hi := a_share * (1.0 + HUE_TOL)
	if share < share_lo or share > share_hi:
		_fail(
			"hue teal share=%.4f not within ±10%% of 5df8e7fc share=%.4f (edge teal=%d vs A %d)"
			% [share, a_share, teal, a_teal]
		)
	else:
		_pass(
			"hue teal share=%.4f within ±10%% of 5df8e7fc %.4f (edge teal=%d A=%d; B width_proxy=%.3f A=%.3f thinner Line2D-AA vs mesh)"
			% [share, a_share, teal, a_teal, width_proxy, a_width]
		)
	# Olive: engineer_recommended is the regression. Extra olive fails the
	# teal share; also cap absolute olive vs A's measured edge count +10%.
	var a_olive := int(_a_metrics.get("hue_olive_edge", 0))
	if a_olive > 0 and olive > int(ceil(float(a_olive) * (1.0 + HUE_TOL))):
		_fail("hue olive edge=%d above ±10%% of 5df8e7fc %d" % [olive, a_olive])
	else:
		_pass("hue olive edge=%d <= 5df8e7fc %d+10%%" % [olive, a_olive])


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
	var teal_fill := 0
	var w := img.get_width()
	var h := img.get_height()
	# Map area only. All three buckets are ring-edge pixels so a thinner
	# mesh stroke cannot cheat the teal share vs 5df8e7fc Line2D AA.
	var y := 40
	while y < h - 1:
		var x := 1
		while x < w - 1:
			var kind := _classify_hue(img.get_pixel(x, y))
			if kind.is_empty():
				x += 1
				continue
			if kind == "teal":
				teal_fill += 1
			var edge := (
				_classify_hue(img.get_pixel(x - 1, y)) != kind
				or _classify_hue(img.get_pixel(x + 1, y)) != kind
				or _classify_hue(img.get_pixel(x, y - 1)) != kind
				or _classify_hue(img.get_pixel(x, y + 1)) != kind
			)
			if edge:
				if kind == "teal":
					teal += 1
				elif kind == "olive":
					olive += 1
				elif kind == "orange":
					orange += 1
			x += 1
		y += 1
	return {"teal": teal, "olive": olive, "orange": orange, "teal_fill": teal_fill}


func _a_file_path() -> String:
	var env := OS.get_environment("EOA_RENDER1_A_FRAME2_FILE").strip_edges()
	if not env.is_empty():
		return env
	return ProjectSettings.globalize_path(DEFAULT_A_FILE)


func _load_a_metrics() -> Dictionary:
	var env_ms := OS.get_environment("EOA_RENDER1_A_FRAME2_MS").strip_edges()
	var path := _a_file_path()
	var out: Dictionary = {}
	if FileAccess.file_exists(path):
		var txt := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed as Dictionary
			_info("loaded A metrics from %s lon_frame2=%.3f teal_share=%.4f" % [
				path, float(out.get("lon_frame2_ms", -1.0)), float(out.get("hue_teal_share", -1.0)),
			])
	if not env_ms.is_empty() and env_ms.is_valid_float():
		out["lon_frame2_ms"] = float(env_ms)
		_info("A lon_frame2 overridden by EOA_RENDER1_A_FRAME2_MS=%.3f" % float(env_ms))
	if float(out.get("lon_frame2_ms", 0.0)) <= 0.0:
		return {}
	return out


func _write_run_json() -> void:
	var teal := int(_last_hue.get("teal", 0))
	var olive := int(_last_hue.get("olive", 0))
	var orange := int(_last_hue.get("orange", 0))
	var edge_n := teal + olive + orange
	var share := 0.0
	if edge_n > 0:
		share = float(teal) / float(edge_n)
	var fill_teal := int(_last_hue.get("teal_fill", 0))
	var width_proxy := 0.0
	if teal > 0:
		width_proxy = float(fill_teal) / float(teal)
	var payload := {
		"sha": "5df8e7fcc8c5dceb3b0429e14c87c83b116feee7" if _measure_a else "",
		"measure_a": _measure_a,
		"lon_frame1_ms": _frame1_ms,
		"lon_frame2_ms": _frame2_ms,
		"loff_frame1_ms": _loff_frame1_ms,
		"loff_frame2_ms": _loff_frame2_ms,
		"delta_ms": _frame2_ms - _loff_frame2_ms,
		"hue_teal_edge": teal,
		"hue_olive_edge": olive,
		"hue_orange_edge": orange,
		"hue_teal_share": share,
		"hue_teal_fill": fill_teal,
		"width_proxy": width_proxy,
		"display": DisplayServer.get_name(),
	}
	var out_path := "%s/live_boot.json" % _out_dir
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
		_info("wrote %s" % out_path)
	if _measure_a:
		var a_path := _a_file_path()
		DirAccess.make_dir_recursive_absolute(a_path.get_base_dir())
		var af := FileAccess.open(a_path, FileAccess.WRITE)
		if af != null:
			payload["sha"] = "5df8e7fcc8c5dceb3b0429e14c87c83b116feee7"
			af.store_string(JSON.stringify(payload, "\t"))
			af.close()
			_info("MEASURE_A wrote %s lon_frame2=%.3f share=%.4f" % [
				a_path, _frame2_ms, share,
			])
		else:
			_fail("MEASURE_A could not write %s" % a_path)


func _map_is_ready() -> bool:
	if not _title_closed():
		return false
	if _loading_screen_up():
		return false
	# Full world_accurate board, not mid-render 3280/3536 under LoadingScreen.
	if _province_count() < 3500:
		return false
	return _map_renderer() != null and _camera() != null


func _loading_screen_up() -> bool:
	var ls: Node = _find_named("LoadingScreen")
	if ls == null:
		return false
	if "visible" in ls and not bool(ls.get("visible")):
		return false
	return true


func _dismiss_loading() -> void:
	var tr := _find_named("TestRunner")
	if tr != null and tr.has_method("_dismiss_loading_screen"):
		tr.call("_dismiss_loading_screen")
	var ls: Node = _find_named("LoadingScreen")
	if ls == null:
		return
	if ls.has_method("hide_and_free"):
		ls.call("hide_and_free")
	elif "visible" in ls:
		ls.set("visible", false)


func _feed_batch_view() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("_feed_supply_outline_batch_view"):
		mr.call("_feed_supply_outline_batch_view")


func _title_closed() -> bool:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("living_title_has_closed") and bool(tm.call("living_title_has_closed")):
		return true
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
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
	_feed_batch_view()
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
