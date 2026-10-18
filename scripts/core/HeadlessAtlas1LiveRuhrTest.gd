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
const ZOOM_SLACK := 0.05

var _failures := 0
var _phase := 0
var _t0_msec := 0
var _last_wait_log := -1
var _settle_left := 0
var _zoom_i := 0
var _home_pos := Vector2.ZERO
var _lock_pos := Vector2.ZERO
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
	_freeze_boot_fighters()
	print("ATLAS1 live map_ready home=%.1f,%.1f units=%d layers=%d" % [
		_home_pos.x, _home_pos.y, _visible_unit_count(), _city_layer_count(),
	])
	if _city_layer_count() != 1:
		_fail("CityLabelsLayer count %d want 1 (doubled draw path)" % _city_layer_count())
	if _visible_unit_count() < 1:
		_fail("no live unit/air counters after Begin")
	_check_home_cam_mid()
	_zoom_i = 0
	_begin_zoom()


func _begin_zoom() -> void:
	if _zoom_i >= LIVE_ZOOMS.size():
		_finish()
		return
	var z: float = LIVE_ZOOMS[_zoom_i]
	# Playtester wheeled in over the Ruhr (mouse ~455,455 on 1280x800), not
	# Europe-Home centre. Isolated tests used to inject set_live_view so the
	# layout could pass while MapCamera stayed at Home zoom.
	var pos := _essen_world()
	if pos == Vector2.ZERO:
		pos = _home_pos
	_apply_camera(pos, z)
	_settle_left = SETTLE_FRAMES
	_phase = 2
	print("ATLAS1 live frame z=%.3f cam=%.1f,%.1f" % [z, pos.x, pos.y])


func _check_home_cam_mid() -> void:
	_apply_camera(_home_pos, 1.217)
	var layer := _city_layer()
	if layer == null:
		_fail("CityLabelsLayer missing at Home-cam z1.217")
		return
	if not _camera_zoom_stuck(1.217):
		_fail("MapCamera zoom %.3f want 1.217 at Home-cam (tests were injecting layout zoom)" % _camera_zoom())
	var placed: Array = layer.call("placed")
	if not _has_name(placed, "Essen"):
		_fail("Essen missing at live Home-cam z1.217")
	else:
		_pass("Essen labelled at live Home-cam z1.217")


func _check_zoom() -> void:
	var z: float = LIVE_ZOOMS[_zoom_i]
	_reassert_locked_zoom(z)
	var layer := _city_layer()
	if layer == null:
		_fail("CityLabelsLayer missing at z%.3f" % z)
		_zoom_i += 1
		_begin_zoom()
		return
	if not _camera_zoom_stuck(z):
		_fail("MapCamera zoom %.3f want %.3f (layout must follow live camera)" % [_camera_zoom(), z])
	var layout_z := float(layer.call("last_layout_zoom")) if layer.has_method("last_layout_zoom") else -1.0
	if absf(layout_z - z) > ZOOM_SLACK:
		_fail("CityLabelsLayer last_layout_zoom %.3f != camera %.3f" % [layout_z, z])
	var placed: Array = layer.call("placed")
	var names := PackedStringArray()
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		names.append(str(p.get("name", "")))
	names.sort()
	print("ATLAS1 live z%.3f n=%d counters=%d names=%s" % [
		z, names.size(), _visible_unit_count(), ",".join(names),
	])
	if z < 2.0:
		if not _has_name(placed, "Essen"):
			_fail("Essen missing at live Ruhr-cam z%.3f" % z)
		else:
			_pass("Essen labelled at live z%.3f" % z)
		if not _has_name(placed, "Köln") and not _has_name(placed, "Cologne"):
			_fail("Köln missing at live z%.3f" % z)
		if _has_name(placed, "Hamm") and not _has_name(placed, "Essen"):
			_fail("Hamm kept over Essen at live z%.3f" % z)
		if _has_name(placed, "Münster") and not _has_name(placed, "Essen"):
			_fail("Münster kept over Essen at live z%.3f" % z)
	if bool(layer.call("has_visual_overlap")):
		_fail("live label overlap at z%.3f" % z)
	else:
		_pass("no live label overlap at z%.3f" % z)
	var dups: PackedStringArray = layer.call("duplicate_drawn_names")
	if not dups.is_empty():
		_fail("doubled draws at z%.3f: %s" % [z, ", ".join(dups)])
	else:
		_pass("no doubled names at z%.3f" % z)
	if _city_layer_count() != 1:
		_fail("CityLabelsLayer count %d at z%.3f" % [_city_layer_count(), z])
	var legacy := _legacy_province_name_count()
	if legacy > 0:
		_fail("legacy province-name Labels still visible at z%.3f n=%d (second draw)" % [z, legacy])
	else:
		_pass("no legacy province-name draw at z%.3f" % z)
	var hits: PackedStringArray = layer.call("labels_hit_counters")
	var ruhr_hits := PackedStringArray()
	for h in hits:
		var nm := str(h)
		if nm in ["Essen", "Hamm", "Münster", "Dortmund", "Duisburg", "Düsseldorf", "Herne", "Gelsenkirchen", "Köln", "Cologne", "Krefeld", "Mönchengladbach", "Remscheid"]:
			ruhr_hits.append(nm)
	if not ruhr_hits.is_empty():
		_fail("Ruhr labels under live counters at z%.3f: %s" % [z, ", ".join(ruhr_hits)])
	else:
		_pass("Ruhr labels clear of live counters at z%.3f" % z)
	_maybe_shot("live_ruhr_z%s" % str(z).replace(".", ""))
	_zoom_i += 1
	_begin_zoom()


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


func _freeze_boot_fighters() -> void:
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
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
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_process"):
		mr.set_process(false)


func _ensure_units_on() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", true)
	if mr != null and mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint")


func _apply_camera(pos: Vector2, zoom: float) -> void:
	_lock_pos = pos
	var mr := _map_renderer()
	if mr != null and mr.has_method("lock_pixel_guard_camera"):
		mr.call("lock_pixel_guard_camera", pos, zoom)
	else:
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
		pos = _essen_world()
	if pos == Vector2.ZERO:
		pos = _home_pos
	_apply_camera(pos, zoom)


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
