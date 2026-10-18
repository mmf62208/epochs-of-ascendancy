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

var _failures := 0
var _phase := 0
var _t0_msec := 0
var _last_wait_log := -1
var _settle_left := 0
var _zoom_i := 0
var _home_pos := Vector2.ZERO
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
			_reassert_camera(LIVE_ZOOMS[_zoom_i])
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
	_zoom_i = 0
	_begin_zoom()


func _begin_zoom() -> void:
	if _zoom_i >= LIVE_ZOOMS.size():
		_finish()
		return
	var z: float = LIVE_ZOOMS[_zoom_i]
	var pos := _home_pos
	if z > 2.0:
		pos = _essen_world()
		if pos == Vector2.ZERO:
			pos = _home_pos
	_apply_camera(pos, z)
	var layer := _city_layer()
	if layer != null and layer.has_method("set_live_view"):
		layer.call("set_live_view", z, pos, VP)
	_settle_left = SETTLE_FRAMES
	_phase = 2
	print("ATLAS1 live frame z=%.3f cam=%.1f,%.1f" % [z, pos.x, pos.y])


func _check_zoom() -> void:
	var z: float = LIVE_ZOOMS[_zoom_i]
	_reassert_camera(z)
	var layer := _city_layer()
	if layer == null:
		_fail("CityLabelsLayer missing at z%.3f" % z)
		_zoom_i += 1
		_begin_zoom()
		return
	if layer.has_method("set_live_view"):
		var cam := _camera()
		var pos := cam.global_position if cam != null else _home_pos
		layer.call("set_live_view", z, pos, VP)
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
			_fail("Essen missing at live Home-cam z%.3f" % z)
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
	var mr := _map_renderer()
	if mr != null and mr.has_method("lock_pixel_guard_camera"):
		mr.call("lock_pixel_guard_camera", pos, zoom)
		return
	var cam := _camera()
	if cam != null:
		cam.position_smoothing_enabled = false
		cam.zoom = Vector2(zoom, zoom)
		cam.global_position = pos
		cam.reset_smoothing()
		cam.enabled = true
		cam.make_current()


func _reassert_camera(zoom: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	var pos := cam.global_position
	if zoom > 2.0:
		var essen := _essen_world()
		if essen != Vector2.ZERO:
			pos = essen
	else:
		pos = _home_pos
	_apply_camera(pos, zoom)


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
		_reassert_camera(LIVE_ZOOMS[_zoom_i])
	RenderingServer.force_draw()
	if _zoom_i < LIVE_ZOOMS.size():
		_reassert_camera(LIVE_ZOOMS[_zoom_i])
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
