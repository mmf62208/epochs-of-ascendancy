extends SceneTree

## PERF-1b: hover hit-test reuses the draw-side facility marker cache.
## Headless — NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessFac1aHoverCacheTest.gd

const SRC_LAYER := "res://scripts/map/FacilityIconLayer.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const HOME_ZOOM := 0.776
const CLOSE_ZOOM := 2.30
const PLAY_SIZE := Vector2(1280.0, 740.0)
const NEAR_A := 710430
const NEAR_B := 710434
const FAR_C := 710451
const SITE_AIRFIELD := 1
const STATE_COMPLETED := 2
const FLUSH_FRAMES := 6
const HOVER_N := 12

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
	print("HeadlessFac1aHoverCacheTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFac1aHoverCacheTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFac1aHoverCacheTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFac1aHoverCacheTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessFac1aHoverCacheTest: ", msg)


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
	await _test_hover_reuses_cache()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()


func _test_source_needles() -> void:
	var layer := _read(SRC_LAYER)
	if layer.is_empty():
		_fail("FacilityIconLayer.gd missing")
		return
	var hit_rects := _slice_func(layer, "get_hit_rects_at_zoom")
	if "_markers_for_hit_test" not in hit_rects:
		_fail("get_hit_rects_at_zoom must reuse the draw-side marker cache")
	else:
		_pass("get_hit_rects_at_zoom uses _markers_for_hit_test")
	var helper := _slice_func(layer, "_markers_for_hit_test")
	if helper.is_empty():
		_fail("_markers_for_hit_test missing")
	elif "_last_markers" not in helper or "_markers_zoom" not in helper or "_markers_dirty" not in helper:
		_fail("_markers_for_hit_test must consult _last_markers / zoom / dirty")
	elif "0.008" not in helper:
		_fail("_markers_for_hit_test must use the same 0.008 zoom band as _draw")
	else:
		_pass("_markers_for_hit_test reuses clean cache at matching zoom")
	var compute := _slice_func(layer, "compute_markers_at_zoom")
	if compute.is_empty():
		_fail("compute_markers_at_zoom missing")
	elif "_last_markers" in compute or "_markers_for_hit_test" in compute:
		_fail("compute_markers_at_zoom must stay the explicit uncached path")
	elif "_build_markers()" not in compute:
		_fail("compute_markers_at_zoom must still call _build_markers")
	else:
		_pass("compute_markers_at_zoom stays explicit / uncached")
	var ren := _read(SRC_REN)
	var resolve := _slice_func(ren, "_resolve_map_pick_pid")
	var fac := _slice_func(ren, "_facility_icon_pid_at")
	if "_facility_icon_pid_at" not in resolve:
		_fail("_resolve_map_pick_pid must still call _facility_icon_pid_at")
	elif "hit_test_world" not in fac:
		_fail("_facility_icon_pid_at must still call hit_test_world")
	else:
		_pass("hover pick path still resolve → facility hit_test_world")


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
	p.name = "FAC1a hover %d" % pid
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


func _pair_worlds() -> Dictionary:
	## 30u apart: cluster at Home 0.776 (rects overlap) and split at 2.30
	## (rect gap ≥ SPLIT_GAP_PX). Isolated FAR is far off-axis.
	return {
		NEAR_A: Vector2.ZERO,
		NEAR_B: Vector2(30.0, 0.0),
		FAR_C: Vector2(400.0, 0.0),
	}


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
	_apply_pair_fixture(false)
	_pass("layer + Home z0.776 pair fixture")
	return true


func _apply_pair_fixture(include_far: bool) -> void:
	var worlds: Dictionary = _pair_worlds()
	var provs := {
		NEAR_A: _dummy_prov(NEAR_A, worlds[NEAR_A] as Vector2, 1),
		NEAR_B: _dummy_prov(NEAR_B, worlds[NEAR_B] as Vector2, 2),
	}
	var cents := {
		NEAR_A: worlds[NEAR_A] as Vector2,
		NEAR_B: worlds[NEAR_B] as Vector2,
	}
	var polys := {
		NEAR_A: _square_poly(worlds[NEAR_A] as Vector2),
		NEAR_B: _square_poly(worlds[NEAR_B] as Vector2),
	}
	if include_far:
		provs[FAR_C] = _dummy_prov(FAR_C, worlds[FAR_C] as Vector2, 4)
		cents[FAR_C] = worlds[FAR_C] as Vector2
		polys[FAR_C] = _square_poly(worlds[FAR_C] as Vector2)
	_layer.call("setup_for_test", provs, cents, 200, polys)
	_layer.call("set_test_map_mode", "political")
	_layer.call("set_show_facilities", true)
	_layer.call("set_test_zoom", HOME_ZOOM)


func _hover_pid(world: Vector2, zoom: float) -> int:
	return int(_layer.call("hit_test_at_zoom", world, zoom))


func _layout_centers(zoom: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var layouts: Array = _layer.call("get_hit_rects_at_zoom", zoom)
	for lay_v in layouts:
		if typeof(lay_v) != TYPE_DICTIONARY:
			continue
		var lay: Dictionary = lay_v
		var world: Vector2 = lay.get("world", Vector2.ZERO) as Vector2
		out.append({
			"pid": int(lay.get("pid", -1)),
			"world": world,
			"cluster": bool(lay.get("cluster", false)),
		})
	return out


func _hover_many(pts: Array[Vector2], zoom: float, n: int) -> void:
	var i := 0
	while i < n:
		for w in pts:
			_hover_pid(w, zoom)
		i += 1


func _test_hover_reuses_cache() -> void:
	if _layer == null or _cam == null:
		_fail("fixture missing for hover-cache")
		return
	await _flush()
	var worlds: Dictionary = _pair_worlds()
	var a_w: Vector2 = worlds[NEAR_A] as Vector2
	var b_w: Vector2 = worlds[NEAR_B] as Vector2
	var c_w: Vector2 = worlds[FAR_C] as Vector2
	var miss_w := Vector2(-80.0, 80.0)
	var icons: Array = _layer.call("get_icon_list")
	if icons.size() != 2:
		_fail("pair fixture icons=%d want 2" % icons.size())
		return
	var home_layouts: Array[Dictionary] = _layout_centers(HOME_ZOOM)
	if home_layouts.is_empty():
		_fail("Home get_hit_rects_at_zoom returned 0 layouts")
		return
	var clustered := false
	var host_w := Vector2.ZERO
	var host_pid := -1
	for rec in home_layouts:
		if bool(rec.get("cluster", false)):
			clustered = true
			host_w = rec.get("world", Vector2.ZERO) as Vector2
			host_pid = int(rec.get("pid", -1))
	if not clustered or host_pid <= 0:
		_fail("Home z0.776 pair should produce a cluster layout")
		return
	var pid_host0: int = _hover_pid(host_w, HOME_ZOOM)
	var pid_b0: int = _hover_pid(b_w, HOME_ZOOM)
	var pid_miss0: int = _hover_pid(miss_w, HOME_ZOOM)
	if pid_host0 != host_pid:
		_fail("Home hover at cluster centre pid=%d want %d" % [pid_host0, host_pid])
		return
	if pid_b0 != host_pid:
		_fail("Home hover at NEAR_B (L2 host) pid=%d want %d" % [pid_b0, host_pid])
		return
	if pid_miss0 > 0:
		_fail("empty hover point owned pid=%d" % pid_miss0)
		return
	_pass("Home hover cluster host pid=%d at world %s" % [host_pid, str(host_w)])
	var hover_pts: Array[Vector2] = [host_w, b_w, miss_w]
	var builds0: int = int(_layer.call("get_build_markers_count"))
	if builds0 <= 0:
		_fail("first Home hover/draw never called _build_markers")
		return
	_hover_many(hover_pts, HOME_ZOOM, HOVER_N)
	var builds1: int = int(_layer.call("get_build_markers_count"))
	if builds1 != builds0:
		_fail("fixed-zoom hover rebuilt markers %d → %d" % [builds0, builds1])
		return
	_pass("fixed-zoom %d hovers caused 0 extra builds (%d)" % [HOVER_N, builds1])
	if _hover_pid(host_w, HOME_ZOOM) != pid_host0 or _hover_pid(b_w, HOME_ZOOM) != pid_b0:
		_fail("Home hover pid changed after cached hovers")
		return
	if _hover_pid(miss_w, HOME_ZOOM) != pid_miss0:
		_fail("empty hover point changed after cached hovers")
		return
	_pass("same pids at same worlds after cached Home hovers")
	_cam.zoom = Vector2(CLOSE_ZOOM, CLOSE_ZOOM)
	_cam.force_update_scroll()
	_layer.call("set_test_zoom", CLOSE_ZOOM)
	await _flush()
	var pid_a_close: int = _hover_pid(a_w, CLOSE_ZOOM)
	var pid_b_close: int = _hover_pid(b_w, CLOSE_ZOOM)
	if pid_a_close != NEAR_A:
		_fail("close zoom A should be own pid %d got %d" % [NEAR_A, pid_a_close])
		return
	if pid_b_close != NEAR_B:
		_fail("close zoom B should be own pid %d got %d" % [NEAR_B, pid_b_close])
		return
	_pass("zoom change split cluster: A=%d B=%d" % [pid_a_close, pid_b_close])
	var builds2: int = int(_layer.call("get_build_markers_count"))
	if builds2 <= builds1:
		_fail("zoom change must rebuild clusters (%d → %d)" % [builds1, builds2])
		return
	_hover_many([a_w, b_w, miss_w], CLOSE_ZOOM, HOVER_N)
	var builds3: int = int(_layer.call("get_build_markers_count"))
	if builds3 != builds2:
		_fail("close-zoom hover rebuilt markers %d → %d" % [builds2, builds3])
		return
	_pass("close-zoom %d hovers caused 0 extra builds (%d)" % [HOVER_N, builds3])
	if _hover_pid(a_w, CLOSE_ZOOM) != pid_a_close or _hover_pid(b_w, CLOSE_ZOOM) != pid_b_close:
		_fail("close hover pid changed after cached hovers")
		return
	_pass("same close-zoom pids after cached hovers")
	_cam.zoom = Vector2(HOME_ZOOM, HOME_ZOOM)
	_cam.force_update_scroll()
	_apply_pair_fixture(true)
	await _flush()
	var pid_c: int = _hover_pid(c_w, HOME_ZOOM)
	if pid_c != FAR_C:
		_fail("data-change hover at FAR_C expected %d got %d" % [FAR_C, pid_c])
		return
	_pass("data change: FAR_C pid=%d now hittable" % pid_c)
	var builds4: int = int(_layer.call("get_build_markers_count"))
	if builds4 <= builds3:
		_fail("data change must rebuild clusters (%d → %d)" % [builds3, builds4])
		return
	_hover_many([host_w, b_w, c_w, miss_w], HOME_ZOOM, HOVER_N)
	var builds5: int = int(_layer.call("get_build_markers_count"))
	if builds5 != builds4:
		_fail("post-data hover rebuilt markers %d → %d" % [builds4, builds5])
		return
	_pass("post-data %d hovers caused 0 extra builds (%d)" % [HOVER_N, builds5])
	if _hover_pid(c_w, HOME_ZOOM) != FAR_C:
		_fail("FAR_C pid drifted after cached post-data hovers")
		return
	var explicit: Array = _layer.call("compute_markers_at_zoom", CLOSE_ZOOM)
	if explicit.size() < 3:
		_fail("explicit compute_markers_at_zoom(2.30) should split (n=%d)" % explicit.size())
		return
	_pass("explicit compute_markers_at_zoom still rebuilds at test zoom")
	_info("home_z=%.3f close_z=%.3f builds=%d→%d→%d→%d→%d" % [
		HOME_ZOOM, CLOSE_ZOOM, builds0, builds1, builds2, builds3, builds5
	])
