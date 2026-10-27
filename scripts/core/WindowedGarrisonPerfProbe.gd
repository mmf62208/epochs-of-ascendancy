extends SceneTree

## Windowed F5 chip probe (gamescope). Not Play.
## Boot until the board is up and the chip count is stable, then sample
## idle frames at strategic / mid / close over Berlin, a pan, a wheel zoom,
## one live day tick, L, and a map-mode switch.
##
##   tools/eoa_garrison_perf_probe.sh

const BERLIN := 710300
const Z_STRATEGIC := 0.14
const Z_MID := 0.80
const Z_CLOSE := 1.60
const WAIT_MAP_SECS := 420
const WAIT_CHIPS_SECS := 180
const WARMUP := 8
const SAMPLE_N := 20

var _t0_msec: int = 0
var _failures: int = 0
var _out_dir: String = ""
var _last_wait_log: int = -1


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("WindowedGarrisonPerfProbe: RESULT=%s" % ("PASS" if ok else "FAIL"))
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] WindowedGarrisonPerfProbe: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] WindowedGarrisonPerfProbe: ", msg)


func _opt_int(node: Object, key: String, fallback: int) -> int:
	if node == null or not (key in node):
		return fallback
	return int(node.get(key))


func _dump_boot_counters(tag: String) -> void:
	var lm := get_root().get_node_or_null("LeaderManager")
	var mr := get_first_node_in_group("map_renderer")
	var forms := 0
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		forms = (lm.formations as Dictionary).size()
	print(
		"EOA_BOOT counters tag=%s forms=%d scan_n=%d scan_ms=%.1f rebuild_n=%d rebuild_ms=%.1f index_n=%d index_ms=%.1f flush_n=%d hold_n=%d render_ms=%.1f finish_ms=%.1f bootpol_ms=%.1f center_ms=%.1f t=%d"
		% [
			tag,
			forms,
			_opt_int(lm, "eoa_boot_scan_n", -1),
			float(_opt_int(lm, "eoa_boot_scan_us", 0)) / 1000.0,
			_opt_int(mr, "eoa_boot_rebuild_n", -1),
			float(_opt_int(mr, "eoa_boot_rebuild_us", 0)) / 1000.0,
			_opt_int(mr, "eoa_boot_index_n", -1),
			float(_opt_int(mr, "eoa_boot_index_us", 0)) / 1000.0,
			_opt_int(mr, "eoa_boot_flush_n", -1),
			_opt_int(mr, "eoa_boot_hold_n", -1),
			float(_opt_int(mr, "eoa_boot_render_us", 0)) / 1000.0,
			float(_opt_int(mr, "eoa_boot_finish_us", 0)) / 1000.0,
			float(_opt_int(mr, "eoa_boot_bootpol_us", 0)) / 1000.0,
			float(_opt_int(mr, "eoa_boot_center_us", 0)) / 1000.0,
			Time.get_ticks_msec(),
		]
	)


func _run() -> void:
	var ds := DisplayServer.get_name()
	_info("DisplayServer=%s t0=%d" % [ds, _t0_msec])
	if ds == "headless":
		_fail("headless_display")
		return
	DisplayServer.window_set_size(Vector2i(1280, 800))
	_out_dir = OS.get_environment("EOA_GARRISON_PERF_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-garrison-perf"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail("scene_load_%d" % err)
		return
	if not await _wait_map_ready():
		return
	var boot_map_ms := Time.get_ticks_msec() - _t0_msec
	_info("boot_map_ms=%d" % boot_map_ms)
	_dump_boot_counters("boot_map")
	var boot_chips_ms := await _wait_chips_stable()
	_dump_boot_counters("boot_chips")
	if OS.get_environment("EOA_GARRISON_PERF_BOOT_ONLY").strip_edges() == "1":
		var chips_only := _chip_report()
		_write({
			"boot_map_ms": boot_map_ms,
			"boot_chips_ms": boot_chips_ms,
			"boot_ms": boot_chips_ms,
			"chips": chips_only.get("total", -1),
			"garrison": chips_only.get("garrison", -1),
			"boot_only": true,
			"display": ds,
		})
		print(
			"GARRISON_PERF boot_only boot_map_ms=%d boot_chips_ms=%d chips=%s garrison=%s"
			% [boot_map_ms, boot_chips_ms, str(chips_only.get("total", -1)), str(chips_only.get("garrison", -1))]
		)
		return
	_pause_clock()
	_freeze_camera_fighters()
	var anchor := _berlin_world()
	var strategic := await _sample_zoom("strategic", anchor, Z_STRATEGIC)
	var mid := await _sample_zoom("mid", anchor, Z_MID)
	var close := await _sample_zoom("close", anchor, Z_CLOSE)
	var pan := await _sample_pan(anchor, Z_MID)
	var wheel := await _sample_wheel(anchor)
	var ltoggle := await _sample_key_toggle()
	var mapmode := await _sample_mapmode()
	var day := _sample_day_tick()
	var chips := _chip_report()
	var cull_ok := int(strategic.get("visible", -1)) == 0
	if not cull_ok:
		_fail("strategic cull visible=%s" % str(strategic.get("visible", -1)))
	var row := {
		"boot_map_ms": boot_map_ms,
		"boot_chips_ms": boot_chips_ms,
		"boot_ms": boot_chips_ms,
		"strategic_med_ms": strategic.get("median_ms", -1.0),
		"strategic_p95_ms": strategic.get("p95_ms", -1.0),
		"strategic_visible": strategic.get("visible", -1),
		"strategic_zoom": strategic.get("zoom", -1.0),
		"mid_med_ms": mid.get("median_ms", -1.0),
		"mid_p95_ms": mid.get("p95_ms", -1.0),
		"mid_visible": mid.get("visible", -1),
		"mid_zoom": mid.get("zoom", -1.0),
		"close_med_ms": close.get("median_ms", -1.0),
		"close_p95_ms": close.get("p95_ms", -1.0),
		"close_visible": close.get("visible", -1),
		"close_zoom": close.get("zoom", -1.0),
		"pan_med_ms": pan.get("median_ms", -1.0),
		"pan_p95_ms": pan.get("p95_ms", -1.0),
		"pan_moved": pan.get("moved", 0),
		"wheel_med_ms": wheel.get("median_ms", -1.0),
		"wheel_p95_ms": wheel.get("p95_ms", -1.0),
		"wheel_end_zoom": wheel.get("end_zoom", -1.0),
		"day_tick_ms": day.get("ms", -1.0),
		"day_tick_worst_phase_ms": day.get("worst_phase_ms", -1.0),
		"day_tick_worst_phase": day.get("worst_phase", ""),
		"l_on_ms": ltoggle.get("on_ms", -1.0),
		"l_off_ms": ltoggle.get("off_ms", -1.0),
		"mapmode_ms": mapmode.get("ms", -1.0),
		"mapmode_back_ms": mapmode.get("back_ms", -1.0),
		"chips": chips.get("total", -1),
		"garrison": chips.get("garrison", -1),
		"cull_ok": cull_ok,
		"display": ds,
		"anchor": [anchor.x, anchor.y],
	}
	_write(row)
	_print_row(row)
	if float(strategic.get("median_ms", -1.0)) < 0.0:
		_fail("no strategic sample")
	if int(chips.get("total", 0)) < 1:
		_fail("no chips")


func _wait_map_ready() -> bool:
	while true:
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed >= WAIT_MAP_SECS:
			_fail("map_timeout n=%d" % _province_count())
			return false
		if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
			_last_wait_log = elapsed
			_info("wait_map elapsed=%d n=%d" % [elapsed, _province_count()])
		_dismiss_title()
		if _province_count() >= 3500:
			_dismiss_loading()
		if _map_is_ready():
			_info("map_ready elapsed=%d n=%d" % [elapsed, _province_count()])
			var i := 0
			while i < 8:
				await process_frame
				i += 1
			return true
		await process_frame
	return false


func _wait_chips_stable() -> int:
	var last := -1
	var stable := 0
	var hitch := 0.0
	while true:
		var elapsed_s := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed_s >= WAIT_MAP_SECS + WAIT_CHIPS_SECS:
			_info("chip wait timeout total=%d" % _chip_total())
			break
		var t0 := Time.get_ticks_usec()
		await process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if ms > hitch:
			hitch = ms
		var n := _chip_total()
		if n == last and n >= 0:
			stable += 1
		else:
			stable = 0
			last = n
		if stable >= 12 and n >= 1:
			break
	var boot_ms := Time.get_ticks_msec() - _t0_msec
	_info("boot_chips_ms=%d chips=%d hitch_ms=%.2f" % [boot_ms, _chip_total(), hitch])
	return boot_ms


func _sample_zoom(label: String, anchor: Vector2, zoom: float) -> Dictionary:
	_pin(anchor, zoom)
	if _map_renderer() != null and _map_renderer().has_method("_sync_unit_counter_paint"):
		_map_renderer().call("_sync_unit_counter_paint", zoom)
	await _warmup()
	var stats := await _sample_idle(SAMPLE_N)
	stats["visible"] = _visible_chips()
	stats["zoom"] = _camera_zoom()
	_info(
		"%s med=%.2f p95=%.2f vis=%d zoom=%.3f"
		% [label, float(stats["median_ms"]), float(stats["p95_ms"]), int(stats["visible"]), float(stats["zoom"])]
	)
	return stats


func _sample_pan(anchor: Vector2, zoom: float) -> Dictionary:
	_pin(anchor, zoom)
	_unlock_camera()
	await _warmup()
	var cam := _camera()
	var samples: Array[float] = []
	var moved := 0
	if cam == null:
		return {"median_ms": -1.0, "p95_ms": -1.0, "moved": 0}
	var step := 180.0
	for i in 12:
		var before := cam.global_position
		var t0 := Time.get_ticks_usec()
		cam.global_position = before + Vector2(step, step * 0.15)
		await process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		if cam.global_position.distance_to(before) > 20.0:
			moved += 1
	var stats := _stats(samples)
	stats["moved"] = moved
	_info("pan med=%.2f p95=%.2f moved=%d" % [float(stats["median_ms"]), float(stats["p95_ms"]), moved])
	return stats


func _sample_wheel(anchor: Vector2) -> Dictionary:
	_pin(anchor, Z_MID)
	_unlock_camera()
	await _warmup()
	var mr := _map_renderer()
	var samples: Array[float] = []
	if mr == null or not mr.has_method("_zoom_toward_mouse"):
		return {"median_ms": -1.0, "p95_ms": -1.0, "end_zoom": _camera_zoom()}
	var screen := Vector2(640, 400)
	for i in 8:
		var t0 := Time.get_ticks_usec()
		mr.call("_zoom_toward_mouse", 1.12, screen)
		if mr.has_method("_schedule_light_terrain_zoom_refresh"):
			mr.call("_schedule_light_terrain_zoom_refresh")
		await process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var stats := _stats(samples)
	stats["end_zoom"] = _camera_zoom()
	_info("wheel med=%.2f p95=%.2f end_zoom=%.3f" % [float(stats["median_ms"]), float(stats["p95_ms"]), float(stats["end_zoom"])])
	return stats


func _sample_key_toggle() -> Dictionary:
	var on_ms := await _key_frame(KEY_L, true)
	await process_frame
	var off_ms := await _key_frame(KEY_L, true)
	_info("L on=%.2f off=%.2f" % [on_ms, off_ms])
	return {"on_ms": on_ms, "off_ms": off_ms}


func _sample_mapmode() -> Dictionary:
	var mr := _map_renderer()
	if mr == null or not mr.has_method("set_map_mode"):
		return {"ms": -1.0, "back_ms": -1.0}
	var t0 := Time.get_ticks_usec()
	mr.call("set_map_mode", "terrain")
	await process_frame
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	mr.call("set_map_mode", "political")
	await process_frame
	var back := float(Time.get_ticks_usec() - t1) / 1000.0
	_info("mapmode terrain=%.2f political=%.2f" % [ms, back])
	return {"ms": ms, "back_ms": back}


func _sample_day_tick() -> Dictionary:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm == null or not tm.has_method("advance_live_f5_equivalent_days"):
		return {"ms": -1.0, "worst_phase_ms": -1.0, "worst_phase": ""}
	var t0 := Time.get_ticks_usec()
	var res: Dictionary = tm.call("advance_live_f5_equivalent_days", 1)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var prof: Dictionary = {}
	if tm.has_method("get_last_day_tick_profile"):
		prof = tm.call("get_last_day_tick_profile")
	_info(
		"day_tick ms=%.2f ok=%s worst=%s %.2f"
		% [ms, str(res.get("ok", false)), str(prof.get("worst_phase", "")), float(prof.get("worst_phase_ms", -1.0))]
	)
	return {
		"ms": ms,
		"worst_phase_ms": float(prof.get("worst_phase_ms", -1.0)),
		"worst_phase": str(prof.get("worst_phase", "")),
	}


func _key_frame(key: Key, pressed: bool) -> float:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = pressed
	ev.echo = false
	var t0 := Time.get_ticks_usec()
	Input.parse_input_event(ev)
	await process_frame
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _warmup() -> void:
	var i := 0
	while i < WARMUP:
		await process_frame
		i += 1


func _sample_idle(n: int) -> Dictionary:
	var samples: Array[float] = []
	for _i in n:
		var t0 := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	return _stats(samples)


func _stats(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"median_ms": -1.0, "p95_ms": -1.0, "mean_ms": -1.0, "max_ms": -1.0}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var sum := 0.0
	var mx := 0.0
	for v in samples:
		sum += v
		if v > mx:
			mx = v
	var mid := sorted[sorted.size() / 2]
	var p95_i := mini(sorted.size() - 1, int(ceil(float(sorted.size()) * 0.95)) - 1)
	if p95_i < 0:
		p95_i = sorted.size() - 1
	return {
		"median_ms": mid,
		"p95_ms": sorted[p95_i],
		"mean_ms": sum / float(samples.size()),
		"max_ms": mx,
	}


func _pin(anchor: Vector2, zoom: float) -> void:
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
	var mr := _map_renderer()
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	if mr != null and mr.has_method("lock_pixel_guard_camera"):
		mr.call("lock_pixel_guard_camera", anchor, zoom)
	else:
		var cam := _camera()
		if cam != null:
			cam.zoom = Vector2(zoom, zoom)
			cam.global_position = anchor
			cam.make_current()


func _unlock_camera() -> void:
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", false)
	var mr := _map_renderer()
	if mr != null and mr.has_method("_unlock_close_camera"):
		mr.call("_unlock_close_camera")


func _chip_report() -> Dictionary:
	var garrison := 0
	var lm: Node = root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("_garrison_1936_counts"):
		var counts: Dictionary = lm.call("_garrison_1936_counts")
		for k in counts.keys():
			garrison += int(counts[k])
	return {"total": _chip_total(), "garrison": garrison, "visible": _visible_chips()}


func _chip_total() -> int:
	var mr := _map_renderer()
	if mr == null:
		return 0
	var ids: Variant = mr.get("_demo_unit_icon_pids")
	if ids is Array:
		return (ids as Array).size()
	return 0


func _visible_chips() -> int:
	var mr := _map_renderer()
	if mr != null and mr.has_method("_count_visible_unit_icons"):
		return int(mr.call("_count_visible_unit_icons"))
	return -1


func _camera_zoom() -> float:
	var cam := _camera()
	if cam == null:
		return -1.0
	return maxf(absf(cam.zoom.x), absf(cam.zoom.y))


func _berlin_world() -> Vector2:
	var mm: Node = root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", BERLIN)
		if c != Vector2.ZERO:
			return c
	return Vector2(4400, 900)


func _pause_clock() -> void:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)


func _freeze_camera_fighters() -> void:
	var tr := _find_named("TestRunner")
	if tr != null and tr.has_method("set_process"):
		tr.set_process(false)
	var cc := _find_named("CameraController")
	if cc != null and cc.has_method("set_process"):
		cc.set_process(false)


func _map_is_ready() -> bool:
	if not _title_closed():
		return false
	if _loading_screen_up():
		return false
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


func _province_count() -> int:
	var mm: Node = root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


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
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		return vp.get_camera_2d()
	return null


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _print_row(row: Dictionary) -> void:
	var parts: PackedStringArray = PackedStringArray()
	for k in row.keys():
		parts.append("%s=%s" % [str(k), str(row[k])])
	print("GARRISON_PERF %s" % " ".join(parts))


func _write(row: Dictionary) -> void:
	var path := _out_dir.path_join("probe.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("write %s" % path)
		return
	f.store_string(JSON.stringify(row, "\t"))
	f.close()
	_info("wrote %s" % path)
