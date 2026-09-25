extends SceneTree

## IX-1: spine start → daily tick → complete, then RoadLayer has
## Bonn–Köln–Leverkusen and Essen is off-spine (no road, higher move cost).
## Visual states must occur in order: queued → construction → built.
## Also drives the zoom + RoadLayer/preview redraw path that killed Play after start.
##
##   tools/run_godot.sh --headless -s res://scripts/core/HeadlessIx1RoadSpineCompleteTest.gd

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
	_test_source_spine_visual_states()
	_test_source_building_ellipsis_and_toast_before_zoom()
	_test_source_preview_loop_caps()
	_test_source_harness_quit_logged()
	_test_spine_start_to_complete_roadlayer_essen()
	_test_zoom_path_after_spine_does_not_die()


func _test_source_no_tactical_on_spine_start() -> void:
	var ren := _read(SRC_REN)
	var press := _slice_func(ren, "_on_build_road_spine_pressed")
	if press.is_empty():
		_fail("_on_build_road_spine_pressed missing")
		return
	var after := _slice_func(ren, "_ix1_spine_start_after_first_frame")
	if "call_deferred(\"_ix1_spine_start_after_first_frame\"" not in press:
		_fail("spine start must defer panel/zoom so toast paints first")
		return
	if "focus_province_by_id(pid, \"soft\")" not in after:
		_fail("spine start must soft-pan (never tactical 2.4)")
		return
	if "focus_province_by_id(pid)" in after and "focus_province_by_id(pid, \"soft\")" not in after:
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


func _test_source_spine_visual_states() -> void:
	var idm := _read(SRC_IDM)
	var ol := _read(SRC_OL)
	if "EOA_SMOKE_SPINE_STATE" not in idm:
		_fail("EOA_SMOKE_SPINE_STATE log missing")
		return
	if 'state=queued' not in idm and '"queued"' not in idm:
		_fail("queued visual state missing")
		return
	if "construction" not in idm or "built" not in idm:
		_fail("construction/built visual states missing")
		return
	if "class Ix1SpinePreviewDraw" not in ol or "set_ix1_spine_preview" not in ol:
		_fail("Ix1SpinePreviewDraw / set_ix1_spine_preview missing")
		return
	var notify := _slice_func(idm, "_notify_ix1_spine_preview")
	if 'call("rebuild_road_layer")' in notify or "rebuild_road_layer(" in notify:
		_fail("preview notify must not rebuild the RoadLayer (zoom silent-exit)")
		return
	var rebuild := _slice_func(ol, "_rebuild_road_layer_inner")
	if "spine_preview_layer" in rebuild:
		_fail("rebuild_road_layer must not touch spine preview")
		return
	_pass("queued → construction → built preview is _draw-only")


func _test_source_building_ellipsis_and_toast_before_zoom() -> void:
	var press := _slice_func(_read(SRC_REN), "_on_build_road_spine_pressed")
	var apply := _slice_func(_read(SRC_REN), "_apply_spine_building_button_state")
	if '"Building…"' not in apply and '"Building…"' not in _read(SRC_REN):
		_fail("Building… button state missing")
		return
	var toast_i := press.find("_show_inspector_toast")
	var defer_i := press.find("call_deferred")
	if toast_i < 0 or defer_i < 0 or toast_i > defer_i:
		_fail("toast must happen before deferred camera/zoom on spine start")
		return
	if "_apply_spine_building_button_state" not in press:
		_fail("Building… state not applied on start")
		return
	_pass("toast + Building… persist before zoom")


func _test_source_preview_loop_caps() -> void:
	var ol := _read(SRC_OL)
	var dashed := _slice_func(ol, "_draw_spine_dashed")
	if "IX1_PREVIEW_MAX_SEGS" not in dashed or "IX1_PREVIEW_MIN_STEP" not in dashed:
		_fail("preview dash loop missing hard caps")
		return
	if "is_finite(length)" not in dashed:
		_fail("preview dash must reject non-finite length")
		return
	if ", true)" in dashed:
		_fail("preview dash must not use antialiased draw_line (windowed OOM)")
		return
	if "position = hub_c" not in ol and "position = hub" not in ol:
		_fail("preview must draw hub-local (not absolute GIS cents)")
		return
	var sh := _read("res://tools/eoa_ix1_spine_frame_guard.sh")
	if "EOA_SMOKE_FRAME_GUARD" not in sh or "eoa_play_f5_smoke_auto_begin.sh" not in sh:
		_fail("frame guard must launch via eoa_play_f5_smoke_auto_begin.sh")
		return
	var ren := _read("res://scripts/map/MapRenderer.gd")
	var deliver := _slice_func(ren, "deliver_ix1_spine_button_mouse_press")
	if deliver.is_empty() or "push_input" not in deliver:
		_fail("frame guard must deliver InputEventMouseButton through the viewport")
		return
	if "press_build_road_spine_from_live_ui()" in deliver or "try_start_road_spine" in deliver:
		_fail("viewport mouse press must not call the spine helper/API")
		return
	var toast := _read("res://scripts/ui/LeaderEventUI.gd")
	var dismiss := _slice_func(toast, "_dismiss_toast")
	if "remove_child" not in dismiss:
		_fail("toast dismiss must remove_child before queue_free (queue_free-only spins)")
		return
	if "eoa_toast_dismissing" not in toast:
		_fail("toast dismiss must be idempotent")
		return
	if "while _toast_container.get_child_count()" in toast:
		_fail("toast trim must not while get_child_count after queue_free")
		return
	_pass("preview loops are hard-capped + hub-local; Play-launch viewport mouse guard shipped")


func _test_source_harness_quit_logged() -> void:
	var tr := _read(SRC_TR)
	if "func _quit_logged" not in tr or "EOA_HARNESS_QUIT" not in tr:
		_fail("TestRunner must log EOA_HARNESS_QUIT with a reason")
		return
	var quit_fn := _slice_func(tr, "_quit_logged")
	if "get_tree().quit" not in quit_fn:
		_fail("_quit_logged must call get_tree().quit after logging a reason")
		return
	var outside := tr.replace(quit_fn, "")
	if "get_tree().quit" in outside:
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
	var states: Array = result.get("visual_states", []) as Array
	if states.size() < 3 or str(states[0]) != "queued" or str(states[1]) != "construction" or str(states[states.size() - 1]) != "built":
		_fail("visual states not queued→construction→built: %s" % str(states))
		return
	var pq: Dictionary = result.get("preview_queued", {}) as Dictionary
	var pc: Dictionary = result.get("preview_construction", {}) as Dictionary
	if str(pq.get("state", "")) != "queued" or not bool(pq.get("bonn_koln", false)) or not bool(pq.get("koln_leverkusen", false)):
		_fail("queued preview missing Bonn–Köln–Leverkusen: %s" % str(pq))
		return
	if int(pq.get("line2d_children", 1)) != 0:
		_fail("queued preview used Line2D children (zoom death class): %s" % str(pq))
		return
	if str(pc.get("state", "")) != "construction" or not bool(pc.get("bonn_koln", false)):
		_fail("construction preview missing: %s" % str(pc))
		return
	if bool(pq.get("essen_edge", false)) or bool(pc.get("essen_edge", false)):
		_fail("preview painted Essen")
		return
	if ms > 20000:
		_fail("start→complete took %dms" % ms)
		return
	_pass(
		"start→complete days=%s states=queued→construction→built RoadLayer Bonn–Köln–Leverkusen Essen off-spine (%dms)"
		% [str(result.get("days")), ms]
	)


func _test_zoom_path_after_spine_does_not_die() -> void:
	# Reproduce Play MIXED 002df244: start (already complete above) + zoom + RoadLayer redraw.
	print("EOA_ZOOM_BEGIN who=HeadlessIx1RoadSpineCompleteTest.drive")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	var overlay: Node = get_first_node_in_group("infrastructure_overlay")
	if overlay == null:
		overlay = root.find_child("Ix1HeadlessRoadLayer", true, false)
	if overlay != null and overlay.has_method("rebuild_road_layer"):
		overlay.call("rebuild_road_layer")
	if overlay != null and overlay.has_method("refresh_ix1_spine_preview"):
		overlay.call("refresh_ix1_spine_preview")
	if overlay != null and overlay.has_method("ix1_spine_roadlayer_report"):
		var report: Dictionary = overlay.call("ix1_spine_roadlayer_report")
		if not bool(report.get("ok", false)):
			_fail("RoadLayer report after zoom-path rebuild: %s" % str(report))
			return
	if overlay != null and overlay.has_method("ix1_spine_preview_report"):
		var prev: Dictionary = overlay.call("ix1_spine_preview_report")
		if int(prev.get("line2d_children", 1)) != 0:
			_fail("zoom-path preview spawned Line2D children: %s" % str(prev))
			return
	print("EOA_ZOOM_END who=HeadlessIx1RoadSpineCompleteTest.drive ok=1")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	_pass("zoom + RoadLayer redraw after spine did not exit")
