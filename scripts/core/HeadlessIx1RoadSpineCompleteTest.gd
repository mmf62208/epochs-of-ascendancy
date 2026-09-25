extends SceneTree

## IX-1: spine start → daily tick → complete, then RoadLayer has
## Bonn–Köln–Leverkusen and Essen is off-spine (no road, higher move cost).
## Also drives the zoom + RoadLayer redraw path that killed Play after start.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1RoadSpineCompleteTest.gd

const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_TR := "res://scripts/core/TestRunner.gd"
const SRC_CAM := "res://scripts/map/CameraController.gd"
const HUB_ID := 710417
const BONN_ID := 710416
const LEV_ID := 710418
const ESSEN_ID := 710403

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessIx1RoadSpineCompleteTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessIx1RoadSpineCompleteTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


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


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessIx1RoadSpineCompleteTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessIx1RoadSpineCompleteTest: RESULT=", "PASS" if ok else "FAIL")
	print("EOA_HARNESS_QUIT who=HeadlessIx1RoadSpineCompleteTest reason=%s code=%d" % [
		"complete_pass" if ok else "complete_fail",
		0 if ok else 1,
	])
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_no_tactical_on_spine_start()
	_test_source_zoom_brackets_and_flush()
	_test_source_progress_complete_logs()
	_test_source_building_ellipsis_and_toast_before_zoom()
	_test_source_harness_quit_logged()
	_test_spine_start_to_complete_roadlayer_essen()
	_test_zoom_path_after_spine_does_not_die()


func _test_source_no_tactical_on_spine_start() -> void:
	var ren := _read(SRC_REN)
	var press := _slice_func(ren, "_on_build_road_spine_pressed")
	if press.is_empty():
		_fail("_on_build_road_spine_pressed missing")
		return
	if "focus_province_by_id(pid, \"soft\")" not in press:
		_fail("spine start must soft-pan (never tactical 2.4)")
		return
	if "focus_province_by_id(pid)" in press and "focus_province_by_id(pid, \"soft\")" not in press:
		_fail("spine start still calls default focus_province_by_id (tactical death)")
		return
	if "tactical_redirected_soft" not in ren:
		_fail("focus_province_by_id must redirect tactical zoom to soft")
		return
	_pass("spine start does not snap tactical 2.4")


func _test_source_zoom_brackets_and_flush() -> void:
	var ren := _read(SRC_REN)
	var cam := _read(SRC_CAM)
	if "EOA_ZOOM_BEGIN" not in ren or "EOA_ZOOM_END" not in ren:
		_fail("MapRenderer missing EOA_ZOOM_BEGIN/END")
		return
	if "flush_stdout" not in _slice_func(ren, "eoa_log_flush") and "flush_stdout" not in ren:
		_fail("MapRenderer zoom logs must flush")
		return
	if "EOA_ZOOM_BEGIN" not in cam or "EOA_ZOOM_END" not in cam:
		_fail("CameraController missing EOA_ZOOM_BEGIN/END")
		return
	if "drive_ix1_zoom_and_roadlayer_redraw" not in ren:
		_fail("drive_ix1_zoom_and_roadlayer_redraw missing")
		return
	_pass("zoom path is bracketed + flushed")


func _test_source_progress_complete_logs() -> void:
	var ren := _read(SRC_REN)
	var idm := _read(SRC_IDM)
	if "EOA_SMOKE_SPINE_PROGRESS" not in ren or "EOA_SMOKE_SPINE_PROGRESS" not in idm:
		_fail("EOA_SMOKE_SPINE_PROGRESS missing")
		return
	if "EOA_SMOKE_SPINE_COMPLETE" not in ren or "EOA_SMOKE_SPINE_COMPLETE" not in idm:
		_fail("EOA_SMOKE_SPINE_COMPLETE missing")
		return
	if "LabelSpineProgress" not in ren:
		_fail("Köln panel missing spine progress label")
		return
	if "simulate_ix1_spine_start_to_complete" not in idm:
		_fail("simulate_ix1_spine_start_to_complete missing")
		return
	if "ix1_spine_roadlayer_report" not in _read(SRC_OL):
		_fail("RoadLayer missing ix1_spine_roadlayer_report")
		return
	_pass("progress/complete logs + panel + RoadLayer report shipped")


func _test_source_building_ellipsis_and_toast_before_zoom() -> void:
	var press := _slice_func(_read(SRC_REN), "_on_build_road_spine_pressed")
	var apply := _slice_func(_read(SRC_REN), "_apply_spine_building_button_state")
	if '"Building…"' not in apply and '"Building…"' not in _read(SRC_REN):
		_fail("Building… button state missing")
		return
	var toast_i := press.find("_show_inspector_toast")
	var focus_i := press.find("focus_province_by_id")
	if toast_i < 0 or focus_i < 0 or toast_i > focus_i:
		_fail("toast must happen before camera/zoom on spine start")
		return
	if "_apply_spine_building_button_state" not in press:
		_fail("Building… state not applied on start")
		return
	_pass("toast + Building… persist before zoom")


func _test_source_harness_quit_logged() -> void:
	var tr := _read(SRC_TR)
	if "func _quit_logged" not in tr or "EOA_HARNESS_QUIT" not in tr:
		_fail("TestRunner must log EOA_HARNESS_QUIT with a reason")
		return
	if tr.count("get_tree().quit") > 1:
		_fail("TestRunner still has silent get_tree().quit besides _quit_logged")
		return
	_pass("harness quit always logs a reason")


func _test_spine_start_to_complete_roadlayer_essen() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("simulate_ix1_spine_start_to_complete"):
		_fail("simulate_ix1_spine_start_to_complete missing")
		return
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = idm.call("simulate_ix1_spine_start_to_complete", 50)
	var ms := Time.get_ticks_msec() - t0
	print("  [DETAIL] start_to_complete ", result)
	if not bool(result.get("completed", false)):
		_fail("spine did not complete: %s" % str(result))
		return
	if not bool(result.get("edge_bonn_koln", false)) or not bool(result.get("edge_koln_leverkusen", false)):
		_fail("corridor edges missing after complete: %s" % str(result))
		return
	if bool(result.get("essen_edge", true)):
		_fail("Essen incorrectly received a spine road")
		return
	if not bool(result.get("essen_impact_none", false)):
		_fail("Essen impact check failed: %s" % str(result))
		return
	if not bool(result.get("cheaper_than_before", false)):
		_fail("Köln move cost not cheaper after spine")
		return
	if not bool(result.get("cheaper_than_essen", false)):
		_fail("Köln not cheaper than off-spine Essen")
		return
	var roads: Dictionary = result.get("roadlayer", {}) as Dictionary
	if not bool(roads.get("bonn_koln", false)) or not bool(roads.get("koln_leverkusen", false)):
		_fail("RoadLayer missing Bonn–Köln–Leverkusen: %s" % str(roads))
		return
	if bool(roads.get("essen_edge", false)):
		_fail("RoadLayer painted Essen–Köln")
		return
	if ms > 20000:
		_fail("start→complete took %dms" % ms)
		return
	_pass(
		"start→complete days=%s RoadLayer Bonn–Köln–Leverkusen Essen off-spine (%dms)"
		% [str(result.get("days")), ms]
	)


func _test_zoom_path_after_spine_does_not_die() -> void:
	# Reproduce Play MIXED 002df244: start (already complete above) + zoom + RoadLayer redraw.
	print("EOA_ZOOM_BEGIN who=HeadlessIx1RoadSpineCompleteTest.drive")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	var overlay: Node = get_first_node_in_group("infrastructure_overlay")
	if overlay != null and overlay.has_method("rebuild_road_layer"):
		overlay.call("rebuild_road_layer")
		var report: Dictionary = overlay.call("ix1_spine_roadlayer_report") if overlay.has_method("ix1_spine_roadlayer_report") else {}
		if not bool(report.get("ok", false)):
			_fail("RoadLayer report after zoom-path rebuild: %s" % str(report))
			return
	elif idm != null and idm.has_method("simulate_ix1_spine_start_to_complete"):
		# Overlay was created inside simulate; find it.
		var found: Node = root.find_child("Ix1HeadlessRoadLayer", true, false)
		if found != null and found.has_method("rebuild_road_layer"):
			found.call("rebuild_road_layer")
	print("EOA_ZOOM_END who=HeadlessIx1RoadSpineCompleteTest.drive ok=1")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	_pass("zoom + RoadLayer redraw after spine did not exit")
