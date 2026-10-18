extends SceneTree

## ATLAS-1 live Ruhr labels after Begin, with real unit/air counters on.
## Isolated CityLabelsLayer tests pan onto Essen and pass empty counter
## overrides — that is not the live Home zoom-in path. This boots TestScenario.
##
##   EOA_SMOKE_AUTO_BEGIN=1 tools/run_godot.sh --headless --path . \
##     --resolution 1280x800 -s res://scripts/core/HeadlessAtlas1LiveRuhrTest.gd

const ESSEN := 710403
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 30
const LIVE_ZOOMS: Array[float] = [1.217, 1.512, 2.904]
const VP := Vector2(1280, 800)
const ZOOM_SLACK := 0.14
const PLAY_WHEEL_SCREEN := Vector2(455, 455)
const ANCHOR_MAX_PX := 44.0
const RUHR_CORE := ["Essen", "Duisburg", "Düsseldorf", "Dortmund", "Köln"]

var _failures := 0
var _phase := 0
var _t0_msec := 0
var _last_wait_log := -1
var _settle_left := 0
var _zoom_i := 0
var _home_pos := Vector2.ZERO
var _lock_pos := Vector2.ZERO
var _lock_zoom := 0.0
var _focus_world := Vector2.ZERO
var _out_dir := ""


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAtlas1LiveRuhrTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAtlas1LiveRuhrTest: ", msg)


func _start() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_out_dir = OS.get_environment("EOA_ATLAS1_EVIDENCE").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-atlas1-live-ruhr"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail("scene_load_%d" % err)
		_finish()
		return
	_phase = 1
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	if _phase == 1:
		_tick_wait_map()
	elif _phase == 2:
		if _zoom_i < LIVE_ZOOMS.size():
			_reassert_locked_zoom(LIVE_ZOOMS[_zoom_i])
		_settle_left -= 1
		if _settle_left <= 0:
			_check_zoom()
	elif _phase == 3:
		pass


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail("map_timeout after %ds (%s)" % [elapsed, _ready_blocker()])
		_finish()
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		print("ATLAS1 live wait elapsed=%d %s" % [elapsed, _ready_blocker()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	_frame_europe_home()
	var cam := _camera()
	if cam != null:
		_home_pos = cam.global_position
	_ensure_units_on()
	_quiet_boot_fighters()
	# Play: 1280x800, Home, then wheel at (455,455). No Essen pre-pan.
	var essen_w := _essen_world()
	_focus_world = _world_under_screen(PLAY_WHEEL_SCREEN)
	print("ATLAS1 live map_ready home=%.1f,%.1f home_z=%.3f wheel=%s under=%.1f,%.1f essen=%.1f,%.1f dist=%.1f units=%d layers=%d" % [
		_home_pos.x, _home_pos.y, _camera_zoom(), str(PLAY_WHEEL_SCREEN),
		_focus_world.x, _focus_world.y, essen_w.x, essen_w.y,
		_focus_world.distance_to(essen_w),
		_visible_unit_count(), _city_layer_count(),
	])
	if _city_layer_count() != 1:
		_fail("CityLabelsLayer count %d want 1 (doubled draw path)" % _city_layer_count())
	if _visible_unit_count() < 1:
		_fail("no live unit/air counters after Begin")
	if _focus_world == Vector2.ZERO:
		_fail("world under playtester wheel (455,455) is zero")
	_zoom_i = 0
	_begin_zoom()


func _begin_zoom() -> void:
	if _zoom_i >= LIVE_ZOOMS.size():
		_finish()
		return
	var z: float = LIVE_ZOOMS[_zoom_i]
	# Playtester: Home, then wheel at screen (455,455). Main zoom path only.
	_wheel_to(z)
	var cam := _camera()
	var pos := cam.global_position if cam != null else _home_pos
	_lock_pos = pos
	_lock_zoom = _camera_zoom()
	_sync_live_counters(_lock_zoom)
	_sync_layer_from_camera()
	_settle_left = SETTLE_FRAMES
	_phase = 2
	print("ATLAS1 live frame want_z=%.3f cam_z=%.3f cam=%.1f,%.1f" % [z, _lock_zoom, pos.x, pos.y])


func _check_zoom() -> void:
	var z: float = LIVE_ZOOMS[_zoom_i]
	_reassert_locked_zoom(z)
	var layer := _city_layer()
	if layer == null:
		_fail("CityLabelsLayer missing at z%.3f" % z)
		_zoom_i += 1
		_begin_zoom()
		return
	var live_z := _camera_zoom()
	if not _camera_zoom_stuck(z):
		_fail("MapCamera zoom %.3f want %.3f (layout must follow live camera)" % [live_z, z])
	var layout_z := float(layer.call("last_layout_zoom")) if layer.has_method("last_layout_zoom") else -1.0
	if absf(layout_z - live_z) > ZOOM_SLACK:
		_fail("CityLabelsLayer last_layout_zoom %.3f != camera %.3f" % [layout_z, live_z])
	var placed: Array = layer.call("placed")
	var names := PackedStringArray()
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		names.append(str(p.get("name", "")))
	names.sort()
	var essen_s := Vector2.ZERO
	if layer.has_method("screen_of"):
		essen_s = layer.call("screen_of", ESSEN)
	print("ATLAS1 live z%.3f n=%d counters=%d counters_rect=%d essen_s=%.1f,%.1f names=%s" % [
		z, names.size(), _visible_unit_count(),
		int(layer.call("last_counter_rect_count")) if layer.has_method("last_counter_rect_count") else 0,
		essen_s.x, essen_s.y, ",".join(names),
	])
	if not _has_name(placed, "Essen"):
		_fail("Essen missing at live wheel z%.3f" % z)
	else:
		_pass("Essen labelled at live wheel z%.3f" % z)
	if not _essen_on_screen():
		_fail("Essen world not on screen at live wheel z%.3f" % z)
	else:
		_pass("Essen on screen at live wheel z%.3f" % z)
	for core in RUHR_CORE:
		if core == "Köln":
			if not _has_name(placed, "Köln") and not _has_name(placed, "Cologne"):
				_fail("Köln missing at live wheel z%.3f" % z)
		elif not _has_name(placed, core):
			_fail("%s missing at live wheel z%.3f" % [core, z])
	if z >= 2.3:
		_check_ruhr_north_south(placed, z)
	if _has_name(placed, "Hamm") and not _has_name(placed, "Essen"):
		_fail("Hamm kept over Essen at live wheel z%.3f" % z)
	if _has_name(placed, "Münster") and not _has_name(placed, "Essen"):
		_fail("Münster kept over Essen at live wheel z%.3f" % z)
	_check_anchor_and_chrome(layer, placed, z)
	if bool(layer.call("has_visual_overlap")):
		_fail("live label overlap at z%.3f" % z)
	else:
		_pass("no live label overlap at z%.3f" % z)
	var dups: PackedStringArray = layer.call("duplicate_drawn_names")
	if not dups.is_empty():
		_fail("doubled draws at z%.3f: %s" % [z, ", ".join(dups)])
	else:
		_pass("no doubled names at z%.3f" % z)
	var hwy3 := _hwy3_visible_names()
	if not hwy3.is_empty():
		_fail("HWY-3 hub Labels still visible at z%.3f: %s" % [z, ", ".join(hwy3)])
	else:
		_pass("HWY-3 hub Labels hidden at z%.3f" % z)
	if _city_layer_count() != 1:
		_fail("CityLabelsLayer count %d at z%.3f" % [_city_layer_count(), z])
	var legacy := _legacy_province_name_count()
	if legacy > 0:
		_fail("legacy province-name Labels still visible at z%.3f n=%d (second draw)" % [z, legacy])
	else:
		_pass("no legacy province-name draw at z%.3f" % z)
	var hits: PackedStringArray = layer.call("labels_hit_counters")
	var ruhr_hits := PackedStringArray()
	var covered := PackedStringArray()
	for h in hits:
		var nm := str(h)
		if nm in ["Essen", "Hamm", "Münster", "Dortmund", "Duisburg", "Düsseldorf", "Herne", "Gelsenkirchen", "Köln", "Cologne", "Krefeld", "Mönchengladbach", "Remscheid"]:
			ruhr_hits.append(nm)
		if nm in RUHR_CORE or nm == "Cologne":
			covered.append(nm)
		elif nm in ["Hamm", "Münster", "Herne", "Gelsenkirchen", "Krefeld", "Mönchengladbach", "Remscheid"]:
			covered.append(nm)
	if not covered.is_empty():
		_fail("Ruhr labels under live counters at z%.3f: %s" % [z, ", ".join(covered)])
	elif not ruhr_hits.is_empty():
		_pass("Ruhr cores by dots over chips at z%.3f (%s)" % [z, ", ".join(ruhr_hits)])
	else:
		_pass("Ruhr labels clear of live counters at z%.3f" % z)
	_maybe_shot("live_ruhr_z%s" % str(z).replace(".", ""))
	_zoom_i += 1
	_begin_zoom()


func _names_of(placed: Array) -> PackedStringArray:
	var names := PackedStringArray()
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		names.append(str(p.get("name", "")))
	names.sort()
	return names


func _has_name(placed: Array, want: String) -> bool:
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		if str(p.get("name", "")) == want:
			return true
	return false


func _frame_europe_home() -> void:
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", false)
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	elif mr != null and mr.has_method("center_europe_in_world_view"):
		mr.call("center_europe_in_world_view")


func _quiet_boot_fighters() -> void:
	# Stop TestRunner / CameraController fighting the view, but do NOT pin
	# lock_pixel_guard_camera yet — the play path is wheel-toward-mouse.
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", false)
	var tr := _find_named("TestRunner")
	if tr != null:
		tr.set_process(false)
		tr.set_physics_process(false)
		tr.process_mode = Node.PROCESS_MODE_DISABLED
	var cc := _find_named("CameraController")
	if cc != null:
		if "enable_pan" in cc:
			cc.set("enable_pan", false)
		if "enable_zoom" in cc:
			cc.set("enable_zoom", false)
		cc.set_process(false)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_hold_camera_until_msec", 0)
		if mr.has_method("_unlock_close_camera"):
			mr.call("_unlock_close_camera")


func _ensure_units_on() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", true)
	if mr != null and mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint")


func _wheel_to(target_zoom: float) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_wheel_toward_screen"):
		mr.call("player_path_wheel_toward_screen", PLAY_WHEEL_SCREEN, target_zoom)
	elif mr != null and mr.has_method("player_path_wheel_toward_world") and _focus_world != Vector2.ZERO:
		mr.call("player_path_wheel_toward_world", _focus_world, target_zoom)
	else:
		var cam := _camera()
		if cam != null:
			cam.zoom = Vector2(target_zoom, target_zoom)


func _world_under_screen(screen: Vector2) -> Vector2:
	var cam := _camera()
	if cam == null:
		return Vector2.ZERO
	var z := maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	if z < 0.04:
		return Vector2.ZERO
	return cam.global_position + (screen - VP * 0.5) / z


func _essen_on_screen() -> bool:
	var layer := _city_layer()
	if layer == null or not layer.has_method("screen_of"):
		return false
	var s: Vector2 = layer.call("screen_of", ESSEN)
	return s.x >= 8.0 and s.y >= 8.0 and s.x <= VP.x - 8.0 and s.y <= VP.y - 8.0


func _check_anchor_and_chrome(layer: Node, placed: Array, z: float) -> void:
	var required: Dictionary = {"Essen": true, "Cologne": true}
	for core in RUHR_CORE:
		required[core] = true
	var chrome: Array = []
	if layer.has_method("chrome_screen_rects"):
		chrome = layer.call("chrome_screen_rects")
	var hits: PackedStringArray = PackedStringArray()
	if layer.has_method("labels_hit_chrome"):
		hits = layer.call("labels_hit_chrome", chrome)
	for h in hits:
		var nm := str(h)
		if required.has(nm):
			_fail("%s hidden under UI/tooltip at live wheel z%.3f" % [nm, z])
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var nm2 := str(p.get("name", ""))
		if not required.has(nm2):
			continue
		var dist := 0.0
		if layer.has_method("anchor_distance_px"):
			dist = float(layer.call("anchor_distance_px", p))
		else:
			var off: Vector2 = p.get("screen_offset", Vector2.ZERO)
			dist = off.length()
		if dist > ANCHOR_MAX_PX:
			_fail("%s is %.1f px from its dot at live wheel z%.3f" % [nm2, dist, z])


func _check_ruhr_north_south(placed: Array, z: float) -> void:
	var rows: Array = []
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var nm := str(p.get("name", ""))
		if nm == "Cologne":
			nm = "Köln"
		if not (nm in RUHR_CORE):
			continue
		var world: Vector2 = p.get("world", Vector2.ZERO)
		var rect: Rect2 = p.get("screen_rect", Rect2())
		# Marks (dots) define N/S. Labels may sit ±30 px beside their own
		# mark; Essen vs Duisburg are ~9 px apart at z 2.9 so label-centers
		# can invert by a few pixels without the cities swapping.
		rows.append({"name": nm, "world_y": world.y, "screen_y": rect.get_center().y})
	if rows.size() < 5:
		return
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("world_y", 0.0)) < float(b.get("world_y", 0.0))
	)
	for i in range(rows.size() - 1):
		var a: Dictionary = rows[i]
		var b: Dictionary = rows[i + 1]
		if float(a.get("screen_y", 0.0)) > float(b.get("screen_y", 0.0)) + ANCHOR_MAX_PX:
			_fail(
				"%s drawn south of %s at live wheel z%.3f (world N→S broken)"
				% [str(a.get("name", "")), str(b.get("name", "")), z]
			)
			return
	_pass("Ruhr N/S order at live wheel z%.3f" % z)


func _hwy3_visible_names() -> PackedStringArray:
	var out := PackedStringArray()
	var mr := _map_renderer()
	if mr == null:
		return out
	var ol: Node = null
	if mr.has_method("get_overlay_layer"):
		ol = mr.call("get_overlay_layer", "InfrastructureOverlayLayer")
	if ol != null and ol.has_method("get_hub_city_label_names"):
		var raw: Variant = ol.call("get_hub_city_label_names")
		if raw is Array:
			for n in raw:
				out.append(str(n))
	return out


func _apply_camera(pos: Vector2, zoom: float) -> void:
	_lock_pos = pos
	_lock_zoom = zoom
	var cam := _camera()
	if cam != null:
		cam.position_smoothing_enabled = false
		cam.zoom = Vector2(zoom, zoom)
		cam.global_position = pos
		cam.reset_smoothing()
		cam.enabled = true
		cam.make_current()
	_sync_live_counters(zoom)
	_sync_layer_from_camera()


func _reassert_locked_zoom(zoom: float) -> void:
	var pos := _lock_pos
	if pos == Vector2.ZERO:
		pos = _home_pos
	var z := _lock_zoom if _lock_zoom > 0.04 else zoom
	_apply_camera(pos, z)


func _sync_live_counters(zoom: float) -> void:
	var mr := _map_renderer()
	if mr == null:
		return
	if mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint", zoom)
	if mr.has_method("_refresh_province_detail_visibility"):
		mr.call("_refresh_province_detail_visibility")
	if mr.has_method("_hide_legacy_province_name_labels"):
		mr.call("_hide_legacy_province_name_labels")


func _sync_layer_from_camera() -> void:
	var layer := _city_layer()
	var cam := _camera()
	if layer == null or cam == null or not layer.has_method("sync_view"):
		return
	var z := maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	var vp := VP
	if root != null and root.get_viewport() != null:
		vp = root.get_viewport().get_visible_rect().size
	layer.call("sync_view", z, cam.global_position, vp, true)


func _camera_zoom() -> float:
	var cam := _camera()
	if cam == null:
		return 0.0
	return maxf(absf(cam.zoom.x), absf(cam.zoom.y))


func _camera_zoom_stuck(want: float) -> bool:
	return absf(_camera_zoom() - want) <= ZOOM_SLACK


func _legacy_province_name_count() -> int:
	var mr := _map_renderer()
	if mr != null and mr.has_method("count_visible_province_name_labels"):
		return int(mr.call("count_visible_province_name_labels"))
	return 0


func _essen_world() -> Vector2:
	var layer := _city_layer()
	if layer != null and layer.has_method("world_of"):
		var w: Vector2 = layer.call("world_of", ESSEN)
		if w != Vector2.ZERO:
			return w
	return Vector2.ZERO


func _maybe_shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _zoom_i < LIVE_ZOOMS.size():
		_reassert_locked_zoom(LIVE_ZOOMS[_zoom_i])
	RenderingServer.force_draw()
	if _zoom_i < LIVE_ZOOMS.size():
		_reassert_locked_zoom(LIVE_ZOOMS[_zoom_i])
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("ATLAS1 live shot %s %dx%d" % [path, img.get_width(), img.get_height()])


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _find_named("LivingTitleBoot") != null:
		return false
	if _province_count() < 3000:
		return false
	if _map_renderer() == null or _camera() == null:
		return false
	if _city_layer() == null:
		return false
	return true


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
	if _city_layer() == null:
		return "city_layer"
	return "ready"


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


func _dismiss_title_if_needed() -> void:
	var boot := _find_named("LivingTitleBoot")
	if boot == null:
		return
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	elif boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")


func _province_count() -> int:
	var mm := root.get_node_or_null("MapManager") if root != null else null
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _map_renderer() -> Node:
	var nodes := get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0]
	return _find_named("WorldMap")


func _city_layer() -> Node:
	return _find_named("CityLabelsLayer")


func _city_layer_count() -> int:
	if root == null:
		return 0
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == null:
			continue
		if str(node.name) == "CityLabelsLayer":
			n += 1
		for ch in node.get_children():
			stack.append(ch)
	return n


func _visible_unit_count() -> int:
	var mr := _map_renderer()
	if mr != null and mr.has_method("_count_visible_unit_icons"):
		return int(mr.call("_count_visible_unit_icons"))
	return 0


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam := mr.get_node_or_null("MapCamera") as Camera2D
		if cam != null:
			return cam
	if root != null and root.get_viewport() != null:
		return root.get_viewport().get_camera_2d()
	return null


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _finish() -> void:
	_phase = 3
	var ok := _failures == 0
	print("HeadlessAtlas1LiveRuhrTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAtlas1LiveRuhrTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
