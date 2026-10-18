extends SceneTree

## Windowed ATLAS-1 pixel guard. One orientation. Real viewport captures.
## Home / mid / close over the Ruhr and over Paris, plus the Danube at Vienna.
##   tools/eoa_atlas1_pixel_guard.sh

const ESSEN := 710403
const PARIS := 710707
const BERLIN := 710300
const VIENNA_8192 := Vector2(4467.7, 1021.1)
const THEATER := 1.728
const HOME_CAM := Vector2(7449.6456, 1795.9165)
const HOME_ZOOM := 0.40
const MID_ZOOM := 1.35
const CLOSE_ZOOM := 2.40
const LIVE_Z1217 := 1.217
const LIVE_Z1512 := 1.512
const LIVE_Z2904 := 2.904
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 24

var _phase := 0
var _shot := 0
var _settle_left := 0
var _t0_msec := 0
var _last_wait_log := -1
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir := ""
var _cam_pos := Vector2.ZERO
var _cam_zoom := 1.0
var _shots: Array = []
var _home_pos := Vector2.ZERO


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedAtlas1PixelGuard: DisplayServer=%s" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_out_dir = OS.get_environment("EOA_ATLAS1_PIXEL_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-atlas1-pixel"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_shots = [
		{"name": "europe_wide", "zoom": 0.32, "at": "berlin", "probe": ""},
		{"name": "germany_mid", "zoom": 0.90, "at": "berlin", "probe": ""},
		{"name": "home_ruhr", "zoom": HOME_ZOOM, "at": "essen", "probe": ""},
		{"name": "mid_ruhr", "zoom": MID_ZOOM, "at": "essen", "probe": "essen"},
		{"name": "close_ruhr", "zoom": CLOSE_ZOOM, "at": "essen", "probe": "essen"},
		{"name": "home_paris", "zoom": HOME_ZOOM, "at": "paris", "probe": ""},
		{"name": "mid_paris", "zoom": MID_ZOOM, "at": "paris", "probe": "paris"},
		{"name": "close_paris", "zoom": CLOSE_ZOOM, "at": "paris", "probe": "paris"},
		{"name": "mid_danube", "zoom": MID_ZOOM, "at": "vienna", "probe": "danube"},
		{"name": "beauty_rhine", "zoom": 1.15, "at": "koln", "probe": ""},
		{"name": "live_ruhr_z1217", "zoom": LIVE_Z1217, "at": "home", "probe": "essen", "units": true},
		{"name": "live_ruhr_z1512", "zoom": LIVE_Z1512, "at": "home", "probe": "essen", "units": true},
		{"name": "live_ruhr_z2904", "zoom": LIVE_Z2904, "at": "essen", "probe": "essen", "units": true},
	]
	_log("EOA_ATLAS1_PIXEL_GUARD who=guard.boot out=%s" % _out_dir)
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail_reasons.append("scene_load_%d" % err)
		_finish(false)
		return
	_phase = 1
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	if _phase == 1:
		_tick_wait_map()
	elif _phase == 2:
		_reassert_camera()
		_settle_left -= 1
		if _settle_left <= 0:
			_take_shot()
	elif _phase == 3:
		pass


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail_reasons.append("map_timeout")
		_finish(false)
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		_log("EOA_ATLAS1_PIXEL_GUARD who=guard.wait elapsed=%d n=%d %s" % [elapsed, _province_count(), _ready_blocker()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	_freeze_boot_camera_fighters()
	var cam := _camera()
	if cam != null:
		_home_pos = cam.global_position
	if _home_pos == Vector2.ZERO:
		_home_pos = HOME_CAM
	_hide_units()
	_log("EOA_ATLAS1_PIXEL_GUARD who=guard.map_ready n=%d home=%.1f,%.1f" % [
		_province_count(), _home_pos.x, _home_pos.y,
	])
	_begin_shot()


func _begin_shot() -> void:
	if _shot >= _shots.size():
		_finish(_fail_reasons.is_empty())
		return
	var spec: Dictionary = _shots[_shot]
	_set_units_visible(bool(spec.get("units", false)))
	var pos := _world_for(str(spec.get("at", "essen")))
	_apply_camera(pos, float(spec.get("zoom", 1.0)))
	_settle_left = SETTLE_FRAMES
	_phase = 2
	_log("EOA_ATLAS1_PIXEL_GUARD who=guard.frame shot=%s zoom=%.2f" % [str(spec.get("name", "")), _cam_zoom])


func _take_shot() -> void:
	var spec: Dictionary = _shots[_shot]
	var img := _capture(str(spec.get("name", "shot")))
	var probe := str(spec.get("probe", ""))
	if img != null and probe == "essen":
		_assert_label(img, _world_for("essen"), "Essen")
	elif img != null and probe == "paris":
		_assert_label(img, _world_for("paris"), "Paris")
	elif img != null and probe == "danube":
		_assert_danube(img, _world_for("vienna"))
	_shot += 1
	_begin_shot()


func _assert_label(img: Image, world: Vector2, label: String) -> void:
	var screen := _project(world)
	var run := _warm_run(img, screen, 12)
	_log("EOA_ATLAS1_PIXEL_GUARD who=guard.label %s screen=%.1f,%.1f run=%d" % [label, screen.x, screen.y, run])
	if run < 3:
		_fail_reasons.append("%s_label_run_%d" % [label.to_lower(), run])


func _assert_danube(img: Image, world: Vector2) -> void:
	var screen := _project(world)
	var run := _river_run(img, int(screen.x), 8)
	_log("EOA_ATLAS1_PIXEL_GUARD who=guard.danube screen=%.1f,%.1f run=%d" % [screen.x, screen.y, run])
	if run < 3:
		_fail_reasons.append("danube_run_%d" % run)


func _project(world: Vector2) -> Vector2:
	var vp := root.get_viewport()
	if vp != null:
		var xf := vp.get_canvas_transform()
		return xf * world
	return world


func _warm_run(img: Image, center: Vector2, radius: int) -> int:
	var best := 0
	var x0 := int(center.x) - radius
	var x1 := int(center.x) + radius
	var y0 := int(center.y) - radius
	var y1 := int(center.y) + radius
	for y in range(y0, y1 + 1):
		var run := 0
		for x in range(x0, x1 + 1):
			if _is_outline(img, x, y):
				run += 1
				if run > best:
					best = run
			else:
				run = 0
	return best


func _is_outline(img: Image, x: int, y: int) -> bool:
	if img == null or x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return false
	var c := img.get_pixel(x, y)
	return c.r > 0.82 and c.g > 0.75 and c.b > 0.62 and c.b < 0.97 and c.r + 0.02 > c.b


func _river_run(img: Image, col: int, pad: int) -> int:
	if img == null:
		return 0
	var best := 0
	for dx in range(-pad, pad + 1):
		var run := 0
		var x := col + dx
		for y in img.get_height():
			if _is_river(img, x, y):
				run += 1
				if run > best:
					best = run
			else:
				run = 0
	return best


func _is_river(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return false
	var c := img.get_pixel(x, y)
	return c.b > 0.42 and c.b > c.r + 0.18 and c.g > 0.28 and c.r < 0.55


func _world_for(key: String) -> Vector2:
	if key == "home":
		if _home_pos != Vector2.ZERO:
			return _home_pos
		return HOME_CAM
	var cities := _find_named("CityLabelsLayer")
	var pid := 0
	if key == "essen":
		pid = ESSEN
	elif key == "paris":
		pid = PARIS
	elif key == "berlin":
		pid = BERLIN
	if pid != 0 and cities != null and cities.has_method("world_of"):
		var w: Vector2 = cities.call("world_of", pid)
		if w != Vector2.ZERO:
			return w
	if key == "vienna":
		return VIENNA_8192 * THEATER
	if key == "koln":
		return Vector2(4254.322, 944.096) * THEATER
	if key == "berlin":
		return Vector2(4408.0, 910.0) * THEATER
	if key == "paris":
		return Vector2(4148.787, 1005.818) * THEATER
	return Vector2(4255.099, 929.498) * THEATER


func _capture(shot_name: String) -> Image:
	_reassert_camera()
	RenderingServer.force_draw()
	_reassert_camera()
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	var path := "%s/%s.png" % [_out_dir, shot_name]
	img.save_png(path)
	var evidence := OS.get_environment("EOA_ATLAS1_EVIDENCE").strip_edges()
	if not evidence.is_empty():
		DirAccess.make_dir_recursive_absolute(evidence)
		img.save_png("%s/tip_%s.png" % [evidence, shot_name])
	_log("EOA_ATLAS1_PIXEL_GUARD who=guard.capture file=%s %dx%d" % [path, img.get_width(), img.get_height()])
	return img


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _find_named("LivingTitleBoot") != null:
		return false
	if _province_count() < 3000:
		return false
	if _map_renderer() == null or _camera() == null:
		return false
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province"):
		return false
	if mm.call("get_province", ESSEN) == null:
		return false
	return true


func _title_has_closed() -> bool:
	var tr := _find_named("TestRunner")
	if tr == null:
		tr = current_scene
	if tr != null and bool(tr.get_meta("eoa_living_title_closed", false)):
		return true
	if current_scene != null and bool(current_scene.get_meta("eoa_living_title_closed", false)):
		return true
	var boot := _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	return false


func _ready_blocker() -> String:
	if not _title_has_closed():
		return "title_open"
	if _find_named("LivingTitleBoot") != null:
		return "title_node"
	if _province_count() < 3000:
		return "provinces"
	if _map_renderer() == null:
		return "renderer"
	if _camera() == null:
		return "camera"
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province"):
		return "map_manager"
	if mm.call("get_province", ESSEN) == null:
		return "essen"
	return "ready"


func _dismiss_title_if_needed() -> void:
	var boot := _find_named("LivingTitleBoot")
	if boot == null:
		return
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	elif boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")


func _province_count() -> int:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _map_manager() -> Node:
	if root == null:
		return null
	return root.get_node_or_null("MapManager")


func _map_renderer() -> Node:
	var nodes := get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0]
	return _find_named("WorldMap")


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam := mr.get_node_or_null("MapCamera") as Camera2D
		if cam != null:
			return cam
	if root != null and root.get_viewport() != null:
		return root.get_viewport().get_camera_2d()
	return null


func _freeze_boot_camera_fighters() -> void:
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_close_camera_locked", true)
		mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 180000)
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
	if mr != null and mr.has_method("set_process"):
		mr.set_process(false)


func _hide_units() -> void:
	_set_units_visible(false)
	var mr := _map_renderer()
	if mr != null and "info_panel" in mr:
		var ip: Variant = mr.get("info_panel")
		if ip is Control:
			(ip as Control).visible = false


func _set_units_visible(on: bool) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", on)


func _apply_camera(pos: Vector2, zoom: float) -> void:
	_cam_pos = pos
	_cam_zoom = zoom
	var mr := _map_renderer()
	if mr != null and mr.has_method("lock_pixel_guard_camera"):
		mr.call("lock_pixel_guard_camera", pos, zoom)
		return
	var cam := _camera()
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)
		cam.global_position = pos
		cam.reset_smoothing()
		cam.enabled = true
		cam.make_current()


func _reassert_camera() -> void:
	if _cam_pos == Vector2.ZERO:
		return
	_apply_camera(_cam_pos, _cam_zoom)


func _finish(ok: bool) -> void:
	_phase = 3
	var verdict := "PASS" if ok else "FAIL"
	_log("EOA_ATLAS1_PIXEL_GUARD reasons=%s" % str(_fail_reasons))
	_log("WindowedAtlas1PixelGuard: RESULT=%s" % verdict)
	quit(0 if ok else 1)


func _log(msg: String) -> void:
	print(msg)
