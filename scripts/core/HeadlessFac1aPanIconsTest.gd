extends SceneTree

## PERF-1 FIX #1: facility icons stay visible after a Home-zoom pan without
## reclustering. Headless — NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessFac1aPanIconsTest.gd

const SRC_LAYER := "res://scripts/map/FacilityIconLayer.gd"
const HOME_ZOOM := 0.33
const PLAY_SIZE := Vector2(1280.0, 740.0)
const NEAR_PID := 710430
const FAR_PID := 710451
const SITE_AIRFIELD := 1
const STATE_COMPLETED := 2
const FLUSH_FRAMES := 6

var _failures := 0
var _layer: Node2D = null
var _cam: Camera2D = null


class DummyProv extends RefCounted:
	var id: int = 0
	var name: String = ""
	var is_sea: bool = false
	var owner_tag: String = "GER"
	var special_sites: Array = []
	var coordinates: Vector2 = Vector2.ZERO


class DummySite extends RefCounted:
	var id: String = ""
	var site_type: int = 1
	var tier: int = 1
	var province_id: int = 0
	var owner_tag: String = "GER"
	var construction_state: int = 2
	var damage_level: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessFac1aPanIconsTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFac1aPanIconsTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFac1aPanIconsTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFac1aPanIconsTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessFac1aPanIconsTest: ", msg)


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
	var nxt := src.find("\nfunc ", i + needle.length())
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


func _run() -> void:
	_set_play_window()
	await _flush()
	_test_source_needles()
	if not _setup_layer():
		return
	await _test_pan_reuses_markers()
	_test_hover_reuses_markers()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()


func _test_source_needles() -> void:
	var src := _read(SRC_LAYER)
	if src.is_empty():
		_fail("FacilityIconLayer.gd missing")
		return
	var proc := _slice_func(src, "_process")
	if "pan_changed" not in proc or "8.0" not in proc:
		_fail("_process must restore ≥8px pan_changed queue_redraw")
	else:
		_pass("_process restores ≥8px pan redraw")
	if "queue_redraw" not in proc:
		_fail("_process missing queue_redraw")
	else:
		_pass("_process still queue_redraws")
	if "_mark_markers_dirty" not in proc:
		_fail("zoom change must mark the marker cache dirty")
	else:
		_pass("zoom change dirties marker cache")
	if "rebuild_icon_list" in proc:
		_fail("_process must not rebuild the icon list")
	else:
		_pass("_process does not rebuild icon list")
	var draw_i := src.find("func _draw() -> void:")
	var draw_fn := ""
	if draw_i >= 0:
		var nxt := src.find("\nfunc ", draw_i + 10)
		draw_fn = src.substr(draw_i, nxt - draw_i) if nxt >= 0 else src.substr(draw_i)
	if draw_fn.is_empty():
		_fail("_draw function missing")
	elif "_last_markers.clear()" in draw_fn:
		_fail("_draw must not clear the marker cache")
	else:
		_pass("_draw keeps the marker cache")
	if "_markers_zoom" not in draw_fn or "_markers_dirty" not in draw_fn:
		_fail("_draw must rebuild only when cache is dirty/empty or zoom drifted")
	else:
		_pass("_draw uses _markers_zoom + dirty flag")
	if "absf(z - _last_zoom)" in draw_fn:
		_fail("_draw must not compare zoom against _last_zoom (_process overwrites it)")
	else:
		_pass("_draw does not use _last_zoom for cache")
	if "func get_build_markers_count" not in src:
		_fail("get_build_markers_count missing")
	else:
		_pass("get_build_markers_count present")
	if "func compute_markers_at_zoom" not in src:
		_fail("compute_markers_at_zoom must stay")
	else:
		_pass("compute_markers_at_zoom unchanged")
	var hit_rects := _slice_func(src, "get_hit_rects_at_zoom")
	if "_markers_for_hit_test" not in hit_rects:
		_fail("get_hit_rects_at_zoom must reuse the draw-side marker cache")
	else:
		_pass("get_hit_rects_at_zoom uses hover cache helper")
	var compute := _slice_func(src, "compute_markers_at_zoom")
	if "_last_markers" in compute or "_markers_for_hit_test" in compute:
		_fail("compute_markers_at_zoom must stay the explicit uncached path")
	else:
		_pass("compute_markers_at_zoom does not read the draw cache")


func _dummy_site(pid: int, tier: int) -> DummySite:
	var site := DummySite.new()
	site.id = "airfield_tier_%d" % tier
	site.site_type = SITE_AIRFIELD
	site.tier = tier
	site.province_id = pid
	site.owner_tag = "GER"
	site.construction_state = STATE_COMPLETED
	site.damage_level = 0
	return site


func _dummy_prov(pid: int, world: Vector2, tier: int) -> DummyProv:
	var p := DummyProv.new()
	p.id = pid
	p.name = "FAC1a pan %d" % pid
	p.is_sea = false
	p.owner_tag = "GER"
	p.coordinates = world
	p.special_sites = [_dummy_site(pid, tier)]
	return p


func _square_poly(c: Vector2, half: float = 24.0) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(-half, -half),
		c + Vector2(half, -half),
		c + Vector2(half, half),
		c + Vector2(-half, half),
	])


func _setup_layer() -> bool:
	var layer_script: Script = load(SRC_LAYER) as Script
	if layer_script == null or not (layer_script as GDScript).can_instantiate():
		_fail("could not load FacilityIconLayer.gd")
		return false
	_layer = (layer_script as GDScript).new() as Node2D
	if _layer == null:
		_fail("could not instantiate FacilityIconLayer")
		return false
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.enabled = true
	_cam.position = Vector2.ZERO
	_cam.zoom = Vector2(HOME_ZOOM, HOME_ZOOM)
	root.add_child(_cam)
	_cam.make_current()
	root.add_child(_layer)
	var screen_w_world := PLAY_SIZE.x / HOME_ZOOM
	var near_w := Vector2.ZERO
	var far_w := Vector2(screen_w_world + 400.0, 0.0)
	var provs := {
		NEAR_PID: _dummy_prov(NEAR_PID, near_w, 1),
		FAR_PID: _dummy_prov(FAR_PID, far_w, 4),
	}
	var cents := {NEAR_PID: near_w, FAR_PID: far_w}
	var polys := {NEAR_PID: _square_poly(near_w), FAR_PID: _square_poly(far_w)}
	## Small board so Home 0.33 is above site_min (0.32). Default 3520 hides below 0.62.
	_layer.call("setup_for_test", provs, cents, 200, polys)
	_layer.call("set_test_map_mode", "political")
	_layer.call("set_show_facilities", true)
	_layer.call("set_test_zoom", HOME_ZOOM)
	_pass("layer + Home-zoom camera fixture")
	return true


func _marker_has_pid(markers: Array, pid: int) -> bool:
	for rec_v in markers:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if int(rec.get("pid", -1)) == pid:
			return true
		var members: Variant = rec.get("pids", [])
		if members is Array and (members as Array).has(pid):
			return true
	return false


func _far_world() -> Vector2:
	return _layer.call("get_draw_world", FAR_PID) as Vector2


func _test_pan_reuses_markers() -> void:
	if _layer == null or _cam == null:
		_fail("fixture missing for pan-icons")
		return
	await _flush()
	var far_world := _far_world()
	if not far_world.is_finite() or far_world == Vector2.ZERO:
		_fail("FAR facility world missing")
		return
	var far_on_before: bool = bool(_layer.call("_in_viewport", far_world, 40.0))
	if far_on_before:
		_fail("FAR facility must start off-screen at Home")
		return
	_pass("FAR facility off-screen at Home before pan")
	var markers_before: Array = _layer.call("get_last_markers")
	if markers_before.is_empty():
		_fail("first Home draw left an empty marker cache")
		return
	if not _marker_has_pid(markers_before, FAR_PID):
		_fail("off-screen FAR facility was not cached at last Home draw")
		return
	_pass("off-screen FAR facility is in the zoom cache")
	var builds_before: int = int(_layer.call("get_build_markers_count"))
	if builds_before <= 0:
		_fail("first Home draw never called _build_markers")
		return
	_layer.set("_drawn_count", 0)
	var screen_w_world := PLAY_SIZE.x / HOME_ZOOM
	_cam.position = Vector2(screen_w_world, 0.0)
	_cam.force_update_scroll()
	if _layer.has_method("_process"):
		_layer.call("_process", 1.0 / 60.0)
	await _flush()
	var far_on_after: bool = bool(_layer.call("_in_viewport", far_world, 40.0))
	if not far_on_after:
		_fail("FAR facility still off-screen after ≥1 screen-width pan")
		return
	_pass("FAR facility on-screen after ≥1 screen-width pan")
	var drawn: int = int(_layer.call("get_last_drawn_count"))
	if drawn <= 0:
		_fail("drawn count=%d after pan — icons vanished (stale viewport cull)" % drawn)
		return
	_pass("drawn count=%d for facility now on-screen" % drawn)
	var builds_after: int = int(_layer.call("get_build_markers_count"))
	if builds_after != builds_before:
		_fail("_build_markers grew on pan %d → %d" % [builds_before, builds_after])
		return
	_pass("_build_markers call count unchanged on pan (%d)" % builds_after)
	_info("home_z=%.3f cam_delta=%.1f builds=%d drawn=%d" % [
		HOME_ZOOM, screen_w_world, builds_after, drawn
	])


func _test_hover_reuses_markers() -> void:
	if _layer == null:
		_fail("fixture missing for hover-cache")
		return
	var near_w: Vector2 = _layer.call("get_draw_world", NEAR_PID) as Vector2
	var far_w: Vector2 = _far_world()
	if not near_w.is_finite() or not far_w.is_finite() or far_w == Vector2.ZERO:
		_fail("hover-cache FAR world missing")
		return
	var pid_near0: int = int(_layer.call("hit_test_at_zoom", near_w, HOME_ZOOM))
	var pid_far0: int = int(_layer.call("hit_test_at_zoom", far_w, HOME_ZOOM))
	if pid_near0 != NEAR_PID:
		_fail("NEAR hover pid=%d want %d" % [pid_near0, NEAR_PID])
		return
	if pid_far0 != FAR_PID:
		_fail("FAR hover pid=%d want %d" % [pid_far0, FAR_PID])
		return
	var builds_before: int = int(_layer.call("get_build_markers_count"))
	var i := 0
	while i < 8:
		_layer.call("hit_test_at_zoom", near_w, HOME_ZOOM)
		_layer.call("hit_test_world", far_w)
		i += 1
	var builds_after: int = int(_layer.call("get_build_markers_count"))
	if builds_after != builds_before:
		_fail("fixed-zoom hover rebuilt markers %d → %d" % [builds_before, builds_after])
		return
	_pass("fixed-zoom hover caused 0 extra builds (%d)" % builds_after)
	if int(_layer.call("hit_test_at_zoom", near_w, HOME_ZOOM)) != pid_near0:
		_fail("NEAR hover pid changed after cached hovers")
		return
	if int(_layer.call("hit_test_at_zoom", far_w, HOME_ZOOM)) != pid_far0:
		_fail("FAR hover pid changed after cached hovers")
		return
	_pass("same facility pids after cached hovers")
