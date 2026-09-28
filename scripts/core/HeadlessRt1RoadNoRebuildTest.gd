extends SceneTree

## RT-1: zoom sweep + 300 pan frames must not rebuild the road cache or grow
## RoadLayer nodes. One province_data_changed("infrastructure") → exactly one rebuild.
## Must FAIL on 497731dd (rebuild-count API / RoadTierDraw missing) and PASS on tip.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadNoRebuildTest.gd

const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"

var _failures := 0
var _ol: Node2D = null
var _boot_frames: int = 0


func _init() -> void:
	call_deferred("_start")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRt1RoadNoRebuildTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRt1RoadNoRebuildTest: ", msg)


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


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessRt1RoadNoRebuildTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRt1RoadNoRebuildTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _start() -> void:
	_test_source_guards()
	if _failures > 0:
		_finish()
		return
	var ol_script: GDScript = load(SRC_OL) as GDScript
	if ol_script == null:
		_fail("could not load InfrastructureOverlayLayer.gd")
		_finish()
		return
	_ol = ol_script.new() as Node2D
	if _ol == null:
		_fail("could not instantiate overlay")
		_finish()
		return
	root.add_child(_ol)
	if not process_frame.is_connected(_on_boot_frame):
		process_frame.connect(_on_boot_frame)


func _on_boot_frame() -> void:
	_boot_frames += 1
	if _boot_frames < 3:
		return
	if process_frame.is_connected(_on_boot_frame):
		process_frame.disconnect(_on_boot_frame)
	_test_runtime_overlay()
	if _ol != null:
		_ol.queue_free()
	_finish()


func _test_source_guards() -> void:
	var ol := _read(SRC_OL)
	if "class RoadTierDraw" not in ol:
		_fail("RoadTierDraw missing (expected FAIL on 497731dd)")
		return
	if "func get_road_cache_rebuild_count" not in ol:
		_fail("get_road_cache_rebuild_count missing")
		return
	if "func _apply_road_tier_cache" not in ol:
		_fail("_apply_road_tier_cache missing")
		return
	var proc := _slice_func(ol, "_process")
	if "rebuild_road_layer" in proc or "_rebuild_road_layer_inner" in proc:
		_fail("_process must not rebuild the road cache")
		return
	var vis := _slice_func(ol, "_update_sub_layer_visibilities")
	if "rebuild_road_layer(" in vis or "_rebuild_road_layer_inner(" in vis:
		_fail("zoom visibility path must not rebuild the road cache")
		return
	_pass("source: RoadTierDraw + rebuild-count API; zoom/_process do not rebuild")


func _test_runtime_overlay() -> void:
	if _ol == null or not is_instance_valid(_ol):
		_fail("overlay lost during boot")
		return
	if not _ol.has_method("get_road_cache_rebuild_count"):
		_fail("runtime missing get_road_cache_rebuild_count")
		return
	if _ol.has_method("_ensure_road_tier_draw_nodes"):
		_ol.call("_ensure_road_tier_draw_nodes")
	# Pin era so _maybe_rebuild_for_era_change is a no-op during the sweep.
	if _ol.has_method("_get_era_band") and _ol.has_method("_get_map_year"):
		_ol.set("_last_era_band", int(_ol.call("_get_era_band", int(_ol.call("_get_map_year")))))
	var draw_n: int = int(_ol.call("get_road_tier_draw_node_count")) if _ol.has_method("get_road_tier_draw_node_count") else 0
	if draw_n != 3:
		_fail("expected 3 RoadTierDraw nodes, got %d" % draw_n)
	else:
		_pass("RoadTierDraw node count=3")
	var before: int = int(_ol.call("get_road_cache_rebuild_count"))
	var road_layer: Node = _ol.get("road_layer")
	var kids_before: int = (road_layer as Node).get_child_count() if road_layer is Node else 0
	for z in [0.20, 0.32, 0.55, 0.95, 1.55, 2.10, 0.95]:
		if _ol.has_method("_sync_road_tier_draw_zoom"):
			_ol.call("_sync_road_tier_draw_zoom", z)
		if _ol.has_method("_apply_screen_space_road_widths"):
			_ol.call("_apply_screen_space_road_widths")
		if _ol.has_method("_update_sub_layer_visibilities"):
			_ol.call("_update_sub_layer_visibilities")
	for _i in range(300):
		if _ol.has_method("_update_sub_layer_visibilities"):
			_ol.call("_update_sub_layer_visibilities")
		if _ol.has_method("_apply_screen_space_road_widths"):
			_ol.call("_apply_screen_space_road_widths")
	var after_zoom: int = int(_ol.call("get_road_cache_rebuild_count"))
	var kids_after: int = (road_layer as Node).get_child_count() if road_layer is Node else -1
	if after_zoom != before:
		_fail("zoom/pan rebuilt cache %d → %d (want zero rebuilds)" % [before, after_zoom])
	else:
		_pass("zoom sweep + 300 pan frames: rebuilds=0")
	if kids_after != kids_before:
		_fail("RoadLayer children grew %d → %d on zoom/pan" % [kids_before, kids_after])
	else:
		_pass("RoadLayer child count unchanged (%d) across zoom/pan" % kids_after)
	_ol.set("_last_infra_rebuild_msec", 0)
	_ol.set("_infra_rebuild_scheduled", false)
	_ol.set("_infra_light_rebuild_scheduled", false)
	if _ol.has_method("_on_province_data_changed"):
		_ol.call("_on_province_data_changed", 710417, "infrastructure")
	var after_infra: int = int(_ol.call("get_road_cache_rebuild_count"))
	if after_infra != before + 1:
		_fail("province_data_changed(infrastructure) rebuilds %d → %d (want +1)" % [before, after_infra])
	else:
		_pass("one infrastructure notify → exactly one rebuild")
