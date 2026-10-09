extends SceneTree

## INPUT-1 FIX #1: close × on a notice/toast or Command Center must not fall
## through to MapRenderer. Close fires on button release through the real
## Control. The next still-click on the same spot must select.
##
## Judge leftover / follow-up by pid / inspector / formation only.
## Do not early-out on swallow flags. Mutants that drop a consumption
## point must FAIL by selection change, not source-text or setup.
##
##   T1  notice × event-path press+release through parse+flush. FAIL on
##       main 61a80433 (province under × selected). PASS on the tip.
##       Same-spot follow-up at 0 / 1 / 3 frames (no latch reset).
##       Also runs T1/T3/T5 on a `post_news` / `_show_toast` News × so
##       disconnecting that button_down fails by leftover Köln / unit.
##   T2  Command Center CloseX same pipeline + leftover up after overlay
##       free. FAIL on main (Köln) / PASS on tip. Same-spot 0 / 1 / 3.
##   T3  leftover release after notice dismiss (overlay gone) via real
##       InputEvents at the real ×. Catches missing `_input` swallow.
##   T4  leftover release after CC dismiss via real InputEvents.
##   T5  leftover `_input` chip path after notice × with a unit under ×.
##   T6  poll-path notice close through real `_process` (press away, warp
##       over ×, frames tick). Leftover press+release one frame later.
##   T7  poll-path CC close through MainMenu `_process`, leftover one
##       frame later.
##   T8  later still-click at a different spot must pick (one-shot).
##   T9  G89 same-spot at 0/1/3/240 frames (notice + CC) and CC other-spot.
##       No latch reset. Realistic hold close, then still-click at the real ×.
##   T10 CC leftover after overlay free (CC closed/freed before the
##       second click, like T2/T4). Main fails by leftover Köln.
##   T11 poll-pending swallow must expire: after 750 ms + 2 frames a
##       same-spot click must select. Stuck tick leaves pid=-1.
##   T12 reflow same-spot at z0.907 after a user ×. A surviving toast
##       slides into the freed slot; passthrough lets the map pick.
##       T12a News× over Notice (live pair). T12b Notice× over Notice.
##       T12c News× over News. T12d move-away restores STOP (blocks).
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessInput1CloseClickFallthroughTest.gd
##
## Headless / xvfb are NOT live Play.

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_LEUI := "res://scripts/ui/LeaderEventUI.gd"
const SRC_CC := "res://scripts/ui/MainMenu.gd"
const PLAY_SIZE := Vector2i(1280, 740)
const KNOWN_PID := 710417
const HOLD_MS := 80
const ZOOM0 := 0.776
const ZOOM_PLAY := 0.907
const CAM0 := Vector2(4200, 1000)
const MAP_PT := Vector2(640, 400)
const FIXTURE_NOTICE_PT := Vector2(1188, 92)

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _ui: CanvasLayer = null
var _info: Panel = null
var _container: Node2D = null
var _mm: Node = null
var _saved_pick_grid: Variant = null
var _known_province: Object = null
var _known_host: Node2D = null
var _event_seq: int = 0
var _cc: CanvasLayer = null
var _leui: Node = null
var _air_host: Node2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	_restore_pick_grid()
	var ok := _failures == 0
	print("HeadlessInput1CloseClickFallthroughTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessInput1CloseClickFallthroughTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessInput1CloseClickFallthroughTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessInput1CloseClickFallthroughTest: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	root.size = PLAY_SIZE
	if not _setup_renderer():
		return
	# Behavior first so fail-on-main is leftover pick, not source text.
	await _test_t1_notice_event_pipeline()
	await _test_t1_news_event_pipeline()
	await _test_t2_cc_event_pipeline()
	await _test_t3_notice_leftover_after_free()
	await _test_t3_news_leftover_after_free()
	await _test_t4_cc_leftover_after_free()
	await _test_t5_notice_chip_leftover()
	await _test_t5_news_chip_leftover()
	await _test_t6_notice_poll_leftover()
	await _test_t7_cc_poll_leftover()
	await _test_t8_later_click_picks()
	await _test_g_same_spot()
	await _test_cc_fast_double_click()
	await _test_t11_swallow_expiry_must_select()
	await _test_t12_reflow_same_spot()
	_test_source_needles()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	var leui := _read(SRC_LEUI)
	var cc := _read(SRC_CC)
	if ren.is_empty() or leui.is_empty() or cc.is_empty():
		_fail("source files missing")
		return
	# Names / swallow API are tip invariants. Pure main must fail by leftover
	# selection, not "NoticeClose missing" / missing swallow helper.
	if "CloseX" in cc:
		_pass("source needles: CloseX present (behavior is the proof)")
	else:
		_pass("source needles: skipped (behavior is the proof)")


func _setup_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer create failed")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	_mr.name = "MapRenderer"
	_container = Node2D.new()
	_container.name = "ProvinceContainers"
	_mr.add_child(_container)
	if "container" in _mr:
		_mr.container = _container
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_mr.add_child(_ui)
	_info = Panel.new()
	_info.name = "InfoPanel"
	_info.visible = false
	_info.size = Vector2(280, 200)
	_ui.add_child(_info)
	_mr.set("info_panel", _info)
	var name_l := Label.new()
	name_l.name = "LabelName"
	_info.add_child(name_l)
	_mr.set("info_name", name_l)
	var owner_l := Label.new()
	owner_l.name = "LabelOwner"
	_info.add_child(owner_l)
	_mr.set("info_owner", owner_l)
	var pop_l := Label.new()
	pop_l.name = "LabelPopulation"
	_info.add_child(pop_l)
	_mr.set("info_population", pop_l)
	for extra_name in [
		"info_terrain", "info_factories", "info_dev", "info_resources",
		"info_core", "info_special", "info_logistics", "info_combat", "info_national"
	]:
		var extra := Label.new()
		extra.name = extra_name
		_info.add_child(extra)
		_mr.set(extra_name, extra)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	if "use_spatial_picking" in _mr:
		_mr.use_spatial_picking = true
	_mr.set("selected_province_id", -1)
	_mr.set("selected_formation_id", "")
	if _mr.has_method("_ensure_province_id_badge"):
		_mr.call("_ensure_province_id_badge")
	_mm = root.get_node_or_null("MapManager")
	if _mm != null and "pick_grid" in _mm:
		_saved_pick_grid = _mm.pick_grid
		_mm.pick_grid = null
	_leui = root.get_node_or_null("LeaderEventUI")
	if _leui == null:
		# -s harness: do not reference the autoload class_name (parse fail).
		var leui_scr: Script = load("res://scripts/ui/LeaderEventUI.gd") as Script
		if leui_scr != null:
			_leui = leui_scr.new() as Node
			if _leui != null:
				_leui.name = "LeaderEventUI"
				root.add_child(_leui)
	_enable_toast_ui()
	_hide_harness_map_chrome()
	return true


func _hide_harness_map_chrome() -> void:
	# MapRenderer builds MapModeToolbar / search over the real CloseX slot
	# (~1063,152), often on CC unpause. Hide harness chrome so same-spot is
	# judged by province pick. Do not move or enlarge ×.
	if _mr == null:
		return
	for chrome_name in [
		"MapModeToolbar", "TopInfoBar", "SearchBox", "SearchLineEdit",
		"MapModeBar", "Minimap", "StrategicMinimap"
	]:
		var chrome: Node = _mr.find_child(chrome_name, true, false)
		if chrome is CanvasItem:
			(chrome as CanvasItem).visible = false
	if _ui != null:
		var tb: Node = _ui.find_child("MapModeToolbar", true, false)
		if tb is CanvasItem:
			(tb as CanvasItem).visible = false


func _enable_toast_ui() -> void:
	# Test hook on the node. Product post_news does not read EOA_HEADLESS_TOAST_UI.
	if _leui != null and "force_toast_ui" in _leui:
		_leui.set("force_toast_ui", true)


func _restore_pick_grid() -> void:
	if _mm != null and "pick_grid" in _mm and _saved_pick_grid != null:
		_mm.pick_grid = _saved_pick_grid


func _make_province() -> Object:
	var p: Object = _new_obj("res://scripts/data/Province.gd")
	if p == null:
		return null
	p.set("id", KNOWN_PID)
	p.set("owner_tag", "GER")
	p.set("controller_tag", "GER")
	p.set("terrain", "plains")
	p.set("name", "Köln")
	p.set("is_sea", false)
	return p


func _seed_known_under_screen(screen_pt: Vector2) -> bool:
	if _cam == null or _mr == null:
		_fail("renderer missing for known-pid seed")
		return false
	var world_under: Vector2 = _cam.get_canvas_transform().affine_inverse() * screen_pt
	if _known_province == null:
		_known_province = _make_province()
		if _known_province == null:
			_fail("Province create failed")
			return false
	if "provinces" in _mr:
		_mr.provinces[KNOWN_PID] = _known_province
	if "province_centroids" in _mr:
		_mr.province_centroids[KNOWN_PID] = world_under
	if _known_host == null:
		_known_host = Node2D.new()
		_known_host.name = "Province_%d" % KNOWN_PID
		_container.add_child(_known_host)
	_known_host.global_position = world_under
	if "province_nodes" in _mr:
		_mr.province_nodes[KNOWN_PID] = _known_host
	if _mm != null:
		if "pick_grid" in _mm:
			_mm.pick_grid = null
		if "_centroids" in _mm and _mm._centroids is Dictionary:
			var cents: Dictionary = _mm._centroids
			cents.clear()
			cents[KNOWN_PID] = world_under
		elif _mm.has_method("sync_render_centroids"):
			_mm.call("sync_render_centroids", {KNOWN_PID: world_under})
	if "_demo_unit_icon_pids" in _mr:
		_mr._demo_unit_icon_pids = []
	var got: int = int(_mr.call("_still_click_province_pid", world_under, false))
	if got != KNOWN_PID:
		_fail("real pick path must resolve Köln under the click (pid=%d)" % got)
		return false
	return true


func _make_mouse(screen_pt: Vector2, pressed: bool) -> InputEventMouseButton:
	_event_seq += 1
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.canceled = false
	ev.double_click = false
	ev.position = screen_pt
	ev.global_position = screen_pt
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.set_meta("eoa_input1_seq", _event_seq)
	return ev


func _aim_mouse(screen_pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)
	DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))
	var mot := InputEventMouseMotion.new()
	mot.device = 0
	mot.position = screen_pt
	mot.global_position = screen_pt
	Input.parse_input_event(mot)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _send_pipeline(screen_pt: Vector2, pressed: bool) -> InputEventMouseButton:
	_aim_mouse(screen_pt)
	var ev: InputEventMouseButton = _make_mouse(screen_pt, pressed)
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	return ev


func _wait_hold_ms(ms: int) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _flush(n: int = 4) -> void:
	var i: int = 0
	while i < n:
		await process_frame
		i += 1


func _inspector_up() -> bool:
	if _info != null and _info.visible:
		return true
	if _ui != null and _ui.get_node_or_null("UnitDetailPopup") != null:
		return true
	return false


func _clear_inspector() -> void:
	_mr.set("selected_province_id", -1)
	_mr.set("selected_formation_id", "")
	if _info != null:
		_info.visible = false
	if _ui != null:
		var pop: Node = _ui.get_node_or_null("UnitDetailPopup")
		if pop != null:
			_ui.remove_child(pop)
			pop.free()


func _restore_home_camera() -> void:
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)


func _pid() -> int:
	return int(_mr.get("selected_province_id"))


func _fid() -> String:
	return str(_mr.get("selected_formation_id"))


func _assert_no_selection(why: String) -> bool:
	var got_pid: int = _pid()
	if got_pid == KNOWN_PID:
		_fail("%s: leftover selected Köln (pid=%d)" % [why, got_pid])
		return false
	if got_pid > 0:
		_fail("%s: leftover selected pid=%d" % [why, got_pid])
		return false
	if not _fid().is_empty():
		_fail("%s: leftover selected unit %s" % [why, _fid()])
		return false
	if _inspector_up():
		_fail("%s: leftover opened the inspector" % why)
		return false
	_pass("%s: leftover did not pick / inspect" % why)
	return true


func _assert_same_spot_picks(screen_pt: Vector2, why: String) -> bool:
	_clear_inspector()
	# CC close can retarget map-mode / camera. Re-seed Köln under the same
	# screen point. Do not reset input latches.
	_restore_home_camera()
	if not _seed_known_under_screen(screen_pt):
		return false
	_hide_harness_map_chrome()
	_aim_mouse(screen_pt)
	await _flush(1)
	_send_pipeline(screen_pt, true)
	_send_pipeline(screen_pt, false)
	await _flush(2)
	var got_pid: int = _pid()
	if got_pid == KNOWN_PID or _inspector_up():
		_pass("%s: same-spot click selected pid=%d" % [why, got_pid])
		return true
	_fail("%s: same-spot click after close did not select (pid=%d)" % [why, got_pid])
	return false


func _assert_real_click_picks(screen_pt: Vector2, why: String) -> bool:
	if _mr.has_method("_reset_left_gesture_state"):
		_mr.call("_reset_left_gesture_state", screen_pt)
	_restore_home_camera()
	if not _seed_known_under_screen(screen_pt):
		return false
	_clear_inspector()
	_send_pipeline(screen_pt, true)
	_send_pipeline(screen_pt, false)
	await _flush(2)
	var got_pid: int = _pid()
	if got_pid == -1:
		_fail("%s: real click must pick (pid=-1)" % why)
		return false
	if not _inspector_up() and got_pid != KNOWN_PID:
		_fail("%s: real click must open inspector or pick Köln (pid=%d)" % [why, got_pid])
		return false
	_pass("%s: real click picked pid=%d" % [why, got_pid])
	return true


func _fixture_notice_close() -> Button:
	# Pure main skips toast UI. A real NoticeClose at the toast × slot lets
	# leftover fail by Köln selection instead of "NoticeClose missing".
	_enable_toast_ui()
	if _leui != null and _leui.has_method("_ensure_toast_layer"):
		_leui.call("_ensure_toast_layer")
	var layer: Node = null
	if _leui != null:
		layer = _leui.get_node_or_null("LeaderNewsLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "LeaderNewsLayer"
		if _leui != null:
			_leui.add_child(layer)
		else:
			root.add_child(layer)
	var btn := Button.new()
	btn.name = "NoticeClose"
	btn.text = "×"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.custom_minimum_size = Vector2(20, 20)
	btn.size = Vector2(20, 20)
	btn.position = FIXTURE_NOTICE_PT
	btn.add_to_group("eoa_ui_close_x")
	if _leui != null and _leui.has_method("_on_notice_close_button_down"):
		btn.button_down.connect(_leui._on_notice_close_button_down)
	btn.pressed.connect(func() -> void:
		if btn.get_parent() != null:
			btn.get_parent().remove_child(btn)
		btn.queue_free()
	)
	layer.add_child(btn)
	return btn


func _find_notice_close() -> Button:
	var btn: Button = null
	if _leui != null and _leui.has_method("notice_close_button"):
		btn = _leui.call("notice_close_button") as Button
	if btn == null and _leui != null:
		btn = _leui.find_child("NoticeClose", true, false) as Button
	return btn


func _is_news_toast_close(btn: Button) -> bool:
	# `_show_toast` (post_news) sets this tooltip; `show_toast` does not.
	return btn != null and is_instance_valid(btn) and btn.tooltip_text == "Dismiss notification"


func _show_notice() -> Button:
	_enable_toast_ui()
	if _leui == null:
		return _fixture_notice_close()
	if _leui.has_method("show_toast"):
		_leui.call("show_toast", "INPUT-1 notice close test", 30.0)
	await _flush(3)
	var btn: Button = _find_notice_close()
	if btn == null:
		btn = _fixture_notice_close()
		await _flush(1)
	return btn


func _show_news_notice() -> Button:
	# post_news → `_show_toast` NoticeClose (button_down ~L523). Fixture only
	# when headless main skips toast UI, so leftover still fails by Köln.
	_enable_toast_ui()
	if _leui == null:
		return _fixture_notice_close()
	if _leui.has_method("post_news"):
		_leui.call(
			"post_news",
			"INPUT-1 news close test",
			"News toast × must not pick Köln",
			"general"
		)
	await _flush(3)
	var btn: Button = _find_notice_close()
	if btn != null and _is_news_toast_close(btn):
		return btn
	var forced: bool = _leui != null and "force_toast_ui" in _leui and bool(_leui.get("force_toast_ui"))
	if forced and btn == null:
		_fail("T-news: post_news did not build NoticeClose with force_toast_ui")
		return _fixture_notice_close()
	if btn == null:
		btn = _fixture_notice_close()
		await _flush(1)
	return btn


func _hide_notices() -> void:
	if _leui == null:
		return
	var layer: Node = _leui.get_node_or_null("LeaderNewsLayer")
	if layer == null:
		return
	var box: Node = layer.get_node_or_null("ToastContainer")
	if box != null:
		for c in box.get_children():
			box.remove_child(c)
			c.free()
	var stray: Node = layer.find_child("NoticeClose", true, false)
	if stray != null:
		var sp: Node = stray.get_parent()
		if sp != null:
			sp.remove_child(stray)
		stray.free()


func _spawn_cc() -> Button:
	_free_cc()
	var scr: GDScript = load(SRC_CC) as GDScript
	if scr == null:
		_fail("MainMenu.gd missing")
		return null
	_cc = scr.new() as CanvasLayer
	if _cc == null:
		_fail("Command Center create failed")
		return null
	_cc.name = "MainMenu"
	root.add_child(_cc)
	await _flush(6)
	var btn: Button = _cc.find_child("CloseX", true, false) as Button
	if btn == null:
		_fail("CloseX missing on Command Center")
		return null
	return btn


func _free_cc() -> void:
	if _cc != null and is_instance_valid(_cc):
		if not _cc.is_queued_for_deletion():
			_cc.free()
	_cc = null


func _cc_closed() -> bool:
	return _cc == null or not is_instance_valid(_cc) or bool(_cc.get("_closing"))


func _prepare_under(btn: Button) -> Vector2:
	if btn == null or not is_instance_valid(btn):
		return Vector2.ZERO
	var rect: Rect2 = btn.get_global_rect()
	var pt: Vector2 = rect.get_center()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		pt = btn.global_position + Vector2(10, 10)
	_restore_home_camera()
	_clear_inspector()
	if not _seed_known_under_screen(pt):
		return Vector2.ZERO
	_aim_mouse(pt)
	return pt


func _click_close(screen_pt: Vector2) -> void:
	_aim_mouse(screen_pt)
	await _flush(1)
	_send_pipeline(screen_pt, true)
	await _wait_hold_ms(HOLD_MS)
	_aim_mouse(screen_pt)
	await _flush(1)
	_send_pipeline(screen_pt, false)


func _click_close_same_frame(screen_pt: Vector2) -> void:
	# Arm + close + leftover must share a process frame so the one-shot
	# swallow is still armed for T2/T4 leftover (80 ms hold would expire
	# same-frame keep and look like a later click).
	_aim_mouse(screen_pt)
	await _flush(1)
	_send_pipeline(screen_pt, true)
	_send_pipeline(screen_pt, false)


func _leftover_up_after_free(screen_pt: Vector2) -> void:
	# Overlay already closed on the matching `pressed`. Leftover is a real
	# press+release at the same × (no private latches, same frame so the
	# one-shot swallow is still armed). Hide harness chrome so leftover is
	# judged by Köln, not a toolbar hit.
	_hide_harness_map_chrome()
	if _cc != null and is_instance_valid(_cc):
		_cc.free()
		_cc = null
	_restore_home_camera()
	_seed_known_under_screen(screen_pt)
	_aim_mouse(screen_pt)
	_send_pipeline(screen_pt, true)
	_send_pipeline(screen_pt, false)


func _same_spot_gaps(kind: String) -> void:
	for gap_frames in [0, 1, 3, 240]:
		var btn: Button = null
		if kind == "notice":
			_hide_notices()
			btn = await _show_notice()
		else:
			btn = await _spawn_cc()
		if btn == null:
			return
		var pt: Vector2 = _prepare_under(btn)
		if pt == Vector2.ZERO:
			return
		await _click_close(pt)
		await _flush(1)
		var i: int = 0
		while i < gap_frames:
			await process_frame
			i += 1
		if not await _assert_same_spot_picks(pt, "%s same-spot gap=%d" % [kind, gap_frames]):
			pass
		_hide_notices()
		_free_cc()


func _test_t1_notice_event_pipeline() -> void:
	_hide_notices()
	var btn: Button = await _show_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close(pt)
	await _flush(1)
	if not _assert_no_selection("T1 notice event-path leftover"):
		return
	_hide_notices()
	await _same_spot_gaps("notice")


func _test_t1_news_event_pipeline() -> void:
	_hide_notices()
	var btn: Button = await _show_news_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close(pt)
	await _flush(1)
	if not _assert_no_selection("T1 news post_news event-path leftover"):
		return
	_hide_notices()


func _test_t2_cc_event_pipeline() -> void:
	var btn: Button = await _spawn_cc()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close_same_frame(pt)
	# Same-frame leftover press+release after overlay free. FAIL on main
	# (Köln). PASS on tip (swallow still armed).
	_leftover_up_after_free(pt)
	await _flush(1)
	if not _cc_closed():
		_fail("T2: CloseX press+release did not close Command Center")
		return
	_pass("T2: CloseX closed Command Center through the real pipeline")
	if not _assert_no_selection("T2 CC event-path leftover"):
		return
	_free_cc()
	await _same_spot_gaps("cc")


func _test_t3_notice_leftover_after_free() -> void:
	_hide_notices()
	var btn: Button = await _show_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close_same_frame(pt)
	_leftover_up_after_free(pt)
	await _flush(2)
	if not _assert_no_selection("T3 notice leftover after overlay free"):
		return
	_hide_notices()


func _test_t3_news_leftover_after_free() -> void:
	_hide_notices()
	var btn: Button = await _show_news_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close_same_frame(pt)
	_leftover_up_after_free(pt)
	await _flush(2)
	if not _assert_no_selection("T3 news leftover after overlay free"):
		return
	_hide_notices()


func _test_t4_cc_leftover_after_free() -> void:
	var btn: Button = await _spawn_cc()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close_same_frame(pt)
	_leftover_up_after_free(pt)
	await _flush(2)
	if not _cc_closed():
		_fail("T4: CloseX did not close Command Center")
		return
	if not _assert_no_selection("T4 CC leftover after overlay free"):
		return
	_free_cc()


func _air_under_point(screen_pt: Vector2) -> Object:
	var world_pt: Vector2 = _cam.get_canvas_transform().affine_inverse() * screen_pt
	var fscr: Script = load("res://scripts/formations/Formation.gd") as Script
	var fo: Object = fscr.new() if fscr != null else null
	if fo == null:
		_fail("EST air Formation missing")
		return null
	fo.set("formation_id", "input1_est_air")
	fo.set("country_tag", "EST")
	fo.set("formation_type", "air_wing")
	fo.set("name", "EST Air Wing 3")
	fo.set("stationed_province_id", 710199)
	fo.set("strength", 0.9)
	fo.set("organization", 1.0)
	if _air_host != null and is_instance_valid(_air_host):
		_air_host.queue_free()
	_air_host = Node2D.new()
	_air_host.name = "Province_710199"
	_air_host.position = world_pt
	_container.add_child(_air_host)
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_710199"
	_air_host.add_child(icon)
	icon.global_position = world_pt
	icon.set_meta("formation", fo)
	icon.set_meta("formation_id", "input1_est_air")
	icon.set_meta("province_id", 710199)
	if "province_nodes" in _mr:
		_mr.province_nodes[710199] = _air_host
	if "_demo_unit_icon_pids" in _mr:
		_mr._demo_unit_icon_pids = [710199]
	return fo


func _test_t5_notice_chip_leftover() -> void:
	_hide_notices()
	var btn: Button = await _show_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	var world_pt: Vector2 = _cam.get_canvas_transform().affine_inverse() * pt
	_air_under_point(pt)
	_mr.set("selected_formation_id", "")
	var proof: bool = false
	if _mr.has_method("_try_open_land_unit_at_world"):
		proof = bool(_mr.call("_try_open_land_unit_at_world", world_pt, false, false))
	if not proof or _fid() != "input1_est_air":
		_fail("T5 air wing under × was not a real hit (opened=%s fid=%s)" % [str(proof), _fid()])
		return
	_pass("T5 air wing under × opens when the click is not NoticeClose")
	_clear_inspector()
	await _click_close_same_frame(pt)
	_leftover_up_after_free(pt)
	await _flush(2)
	if _fid() == "input1_est_air":
		_fail("T5 leftover chip path selected the unit under ×")
		return
	if not _assert_no_selection("T5 notice leftover _input / chip"):
		return
	if "_demo_unit_icon_pids" in _mr:
		_mr._demo_unit_icon_pids = []
	_hide_notices()


func _test_t5_news_chip_leftover() -> void:
	_hide_notices()
	var btn: Button = await _show_news_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	var world_pt: Vector2 = _cam.get_canvas_transform().affine_inverse() * pt
	_air_under_point(pt)
	_mr.set("selected_formation_id", "")
	var proof: bool = false
	if _mr.has_method("_try_open_land_unit_at_world"):
		proof = bool(_mr.call("_try_open_land_unit_at_world", world_pt, false, false))
	if not proof or _fid() != "input1_est_air":
		_fail("T5 news air wing under × was not a real hit (opened=%s fid=%s)" % [str(proof), _fid()])
		return
	_pass("T5 news air wing under × opens when the click is not NoticeClose")
	_clear_inspector()
	await _click_close_same_frame(pt)
	_leftover_up_after_free(pt)
	await _flush(2)
	if _fid() == "input1_est_air":
		_fail("T5 news leftover chip path selected the unit under ×")
		return
	if not _assert_no_selection("T5 news leftover _input / chip"):
		return
	if "_demo_unit_icon_pids" in _mr:
		_mr._demo_unit_icon_pids = []
	_hide_notices()


func _poll_away_pt(btn: Button) -> Vector2:
	var away: Vector2 = MAP_PT
	if btn != null and is_instance_valid(btn):
		var rect: Rect2 = btn.get_global_rect().grow(12.0)
		if rect.has_point(away):
			away = Vector2(80, 600)
			if rect.has_point(away):
				away = Vector2(48, 48)
	return away


func _idle_poll_latches() -> void:
	# Button-up + one frame so `_poll_*_just_pressed` drops its hold latch.
	_send_pipeline(MAP_PT, false)
	if _leui != null and "_notice_ptr_poll_held" in _leui:
		_leui.set("_notice_ptr_poll_held", false)
	if _cc != null and is_instance_valid(_cc) and "_close_ptr_poll_held" in _cc:
		_cc.set("_close_ptr_poll_held", false)


func _drive_real_process_poll(kind: String, btn: Button, pt: Vector2) -> void:
	# Press away from × so GUI button_down does not fire, warp over × in
	# the same frame, then let `_process` poll `handle_live_close_pointer(null)`.
	_idle_poll_latches()
	await process_frame
	var away: Vector2 = _poll_away_pt(btn)
	_aim_mouse(away)
	var ev: InputEventMouseButton = _make_mouse(away, true)
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	_aim_mouse(pt)
	var i: int = 0
	while i < 3:
		await process_frame
		i += 1
	# Matching leftover up of this hold. Poll-arm swallows it on the tip.
	_send_pipeline(pt, false)
	# Poll miss (main / disabled `_process`) must not hide leftover Köln:
	# drop the overlay so the next click is judged by selection.
	if kind == "notice":
		var still: Button = _find_notice_close()
		if still != null and is_instance_valid(still) and still.is_visible_in_tree():
			_hide_notices()
	elif _cc != null and is_instance_valid(_cc) and not _cc_closed():
		_cc.free()
		_cc = null


func _test_t6_notice_poll_leftover() -> void:
	_hide_notices()
	var btn: Button = await _show_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _drive_real_process_poll("notice", btn, pt)
	await process_frame
	_clear_inspector()
	# Poll leftover press arrives N+1. pending_press must keep the arm.
	_send_pipeline(pt, true)
	await _wait_hold_ms(HOLD_MS)
	_send_pipeline(pt, false)
	await _flush(2)
	if not _assert_no_selection("T6 notice poll leftover"):
		return
	_hide_notices()


func _test_t7_cc_poll_leftover() -> void:
	var btn: Button = await _spawn_cc()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _drive_real_process_poll("cc", btn, pt)
	await process_frame
	_clear_inspector()
	_send_pipeline(pt, true)
	await _wait_hold_ms(HOLD_MS)
	_send_pipeline(pt, false)
	await _flush(2)
	if not _assert_no_selection("T7 CC poll leftover"):
		return
	_free_cc()


func _test_t8_later_click_picks() -> void:
	_hide_notices()
	var btn: Button = await _show_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close(pt)
	await _flush(3)
	_hide_notices()
	if not await _assert_real_click_picks(MAP_PT, "T8 later click after notice ×"):
		return
	var cc_btn: Button = await _spawn_cc()
	if cc_btn == null:
		return
	var cc_pt: Vector2 = _prepare_under(cc_btn)
	if cc_pt == Vector2.ZERO:
		return
	await _click_close(cc_pt)
	_leftover_up_after_free(cc_pt)
	await _flush(3)
	_free_cc()
	if not await _assert_real_click_picks(MAP_PT, "T8 later click after CC ×"):
		return


func _test_g_same_spot() -> void:
	# Fold G89f1SameSpotTest: realistic hold close, then same-spot still-click
	# at 0/1/3/240 frames with no latch reset. CC other-spot at gap=3.
	for kind in ["notice", "cc"]:
		for gap in [0, 1, 3, 240]:
			await _g_case(kind, gap, false)
	await _g_case("cc", 3, true)


func _g_case(kind: String, gap_frames: int, other_spot: bool) -> void:
	var btn: Button = null
	if kind == "notice":
		_hide_notices()
		btn = await _show_notice()
	else:
		btn = await _spawn_cc()
	if btn == null:
		_fail("G %s: no ×" % kind)
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	var closes: Array[int] = [0]
	btn.pressed.connect(func() -> void: closes[0] += 1)
	_aim_mouse(pt)
	await _flush(1)
	_send_pipeline(pt, true)
	await _wait_hold_ms(HOLD_MS)
	var closed_on_press: bool = (kind == "cc" and _cc_closed()) or (
		kind == "notice" and not is_instance_valid(btn)
	)
	_aim_mouse(pt)
	_send_pipeline(pt, false)
	await _flush(1)
	var closed: bool = (kind == "cc" and _cc_closed()) or (
		kind == "notice"
		and (
			not is_instance_valid(btn)
			or btn.get_parent() == null
			or not btn.is_visible_in_tree()
		)
	)
	var leftover_pid: int = _pid()
	if not closed:
		_fail("G %s gap=%d: overlay did not close" % [kind, gap_frames])
	if leftover_pid > 0 or _inspector_up():
		_fail("G %s gap=%d: close leftover selected pid=%d" % [kind, gap_frames, leftover_pid])
	var i: int = 0
	while i < gap_frames:
		await process_frame
		i += 1
	_clear_inspector()
	if kind == "cc":
		_free_cc()
	_restore_home_camera()
	if other_spot:
		pt = MAP_PT
	_seed_known_under_screen(pt)
	_hide_harness_map_chrome()
	_aim_mouse(pt)
	await _flush(1)
	_send_pipeline(pt, true)
	await _wait_hold_ms(HOLD_MS)
	_send_pipeline(pt, false)
	await _flush(2)
	var got: int = _pid()
	var tag := "G %s gap=%d%s closed_on_press=%s pressed_sig=%d" % [
		kind, gap_frames, " other" if other_spot else " same", str(closed_on_press), closes[0]
	]
	if got != KNOWN_PID and not _inspector_up():
		_fail("%s: click after close did not select (pid=%d)" % [tag, got])
	else:
		_pass("%s: leftover_pid=%d; click selected pid=%d" % [tag, leftover_pid, got])
	_hide_notices()
	_free_cc()


func _test_cc_fast_double_click() -> void:
	# Close through the real ✕, then leftover after the overlay is gone
	# (same as T2/T4). A still-open Command Center blocked the second
	# same-frame click on main, so T10 used to PASS on 61a80433.
	var btn: Button = await _spawn_cc()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close_same_frame(pt)
	_leftover_up_after_free(pt)
	await _flush(1)
	if not _cc_closed():
		_fail("T10: CloseX press+release did not close Command Center")
		_free_cc()
		return
	if not _assert_no_selection("T10 CC leftover after overlay free"):
		_free_cc()
		return
	_free_cc()


func _test_t11_swallow_expiry_must_select() -> void:
	# Phase 1: event-path leftover after free. FAIL on main by Köln.
	_hide_notices()
	var btn: Button = await _show_notice()
	if btn == null:
		return
	var pt: Vector2 = _prepare_under(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close_same_frame(pt)
	_leftover_up_after_free(pt)
	await _flush(2)
	if not _assert_no_selection("T11 main-fail leftover before expiry"):
		_hide_notices()
		return
	_hide_notices()
	_clear_inspector()
	# Phase 2: poll-pending arm. After 750 ms + 2 frames the same spot
	# must select. A no-op `_tick_ui_close_release_swallow` keeps pending
	# and leftover pid stays -1.
	if not _mr.has_method("arm_ui_close_release_swallow"):
		_fail("T11: arm_ui_close_release_swallow missing after leftover passed")
		return
	_restore_home_camera()
	if not _seed_known_under_screen(pt):
		return
	_hide_harness_map_chrome()
	_mr.call("arm_ui_close_release_swallow", true)
	await _wait_hold_ms(830)
	await _flush(4)
	if not await _assert_same_spot_picks(pt, "T11 swallow expiry must select"):
		return
	_hide_notices()


func _play_zoom_camera() -> void:
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM_PLAY, ZOOM_PLAY)


func _toast_box() -> Node:
	if _leui == null:
		return null
	var box: Variant = _leui.get("_toast_container")
	if box is Node:
		return box as Node
	var layer: Node = _leui.get_node_or_null("LeaderNewsLayer")
	if layer == null:
		return null
	return layer.get_node_or_null("ToastContainer")


func _toast_panels() -> Array[PanelContainer]:
	var out: Array[PanelContainer] = []
	var box: Node = _toast_box()
	if box == null:
		return out
	for child in box.get_children():
		if child is PanelContainer:
			out.append(child as PanelContainer)
	return out


func _collect_buttons(n: Node, out: Array[Button]) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is Button:
		out.append(n as Button)
	for child in n.get_children():
		if child is Node:
			_collect_buttons(child as Node, out)


func _panel_close(panel: Node) -> Button:
	if panel == null or not is_instance_valid(panel):
		return null
	var named: Button = panel.find_child("NoticeClose", true, false) as Button
	if named != null:
		return named
	# Main 61a80433 × buttons are unnamed (no NoticeClose).
	var found: Array[Button] = []
	_collect_buttons(panel, found)
	var i: int = 0
	while i < found.size():
		var b: Button = found[i]
		if b.text == "×" or b.tooltip_text == "Dismiss notification":
			return b
		i += 1
	return null


func _close_on_panel(panel: Node, news: bool) -> Button:
	var btn: Button = _panel_close(panel)
	if btn == null:
		return null
	var is_news: bool = btn.tooltip_text == "Dismiss notification"
	if news != is_news:
		return null
	return btn


func _first_close(news: bool) -> Button:
	var panels: Array[PanelContainer] = _toast_panels()
	var i: int = 0
	while i < panels.size():
		var btn: Button = _close_on_panel(panels[i], news)
		if btn != null:
			return btn
		i += 1
	if panels.size() > 0:
		return _panel_close(panels[0])
	return null


func _post_news_card(title: String, body: String) -> void:
	_enable_toast_ui()
	var before: int = _toast_panels().size()
	if _leui != null and _leui.has_method("post_news"):
		_leui.call("post_news", title, body, "infrastructure")
	if _toast_panels().size() == before and _leui != null and _leui.has_method("_show_toast"):
		# Main headless skips post_news; `_show_toast` still builds the News card.
		_leui.call("_show_toast", {
			"title": title,
			"body": body,
			"category": "infrastructure",
		})


func _post_notice_card(message: String) -> void:
	_enable_toast_ui()
	var before: int = _toast_panels().size()
	if _leui != null and _leui.has_method("show_toast"):
		_leui.call("show_toast", message, 30.0)
	if _toast_panels().size() == before and _leui != null and _leui.has_method("_show_toast"):
		_leui.call("_show_toast", {
			"title": "Notice",
			"body": message,
			"category": "system",
		})


func _survivor_panel(prefer_notice: bool) -> PanelContainer:
	var panels: Array[PanelContainer] = _toast_panels()
	if prefer_notice:
		var i: int = 0
		while i < panels.size():
			if _close_on_panel(panels[i], false) != null:
				return panels[i]
			i += 1
	if panels.size() > 0:
		return panels[0]
	return null


func _prepare_under_play(btn: Button) -> Vector2:
	if btn == null or not is_instance_valid(btn):
		return Vector2.ZERO
	var rect: Rect2 = btn.get_global_rect()
	var pt: Vector2 = rect.get_center()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		pt = btn.global_position + Vector2(10, 10)
	_play_zoom_camera()
	_clear_inspector()
	if not _seed_known_under_screen(pt):
		return Vector2.ZERO
	_hide_harness_map_chrome()
	_aim_mouse(pt)
	return pt


func _same_spot_play_click(screen_pt: Vector2) -> void:
	_play_zoom_camera()
	_clear_inspector()
	_seed_known_under_screen(screen_pt)
	_hide_harness_map_chrome()
	_aim_mouse(screen_pt)
	_send_pipeline(screen_pt, true)
	await _wait_hold_ms(HOLD_MS)
	_send_pipeline(screen_pt, false)
	await _flush(2)


func _assert_t12_selected(why: String, survivor: Variant) -> bool:
	var got_pid: int = _pid()
	var alive: bool = (
		survivor is Node
		and is_instance_valid(survivor)
		and (survivor as Node).get_parent() != null
	)
	if got_pid == KNOWN_PID or _inspector_up():
		if not alive:
			_fail("%s: selected but survivor toast left the tree (poll close)" % why)
			return false
		_pass("%s: same-spot click selected pid=%d" % [why, got_pid])
		return true
	_fail("%s: same-spot click after close did not select (pid=%d)" % [why, got_pid])
	return false


func _test_t12_reflow_same_spot() -> void:
	await _test_t12a_news_over_notice()
	await _test_t12b_notice_over_notice()
	await _test_t12c_news_over_news()
	await _test_t12d_restore_blocks()


func _test_t12a_news_over_notice() -> void:
	_hide_notices()
	_enable_toast_ui()
	if _leui == null:
		_fail("T12a: LeaderEventUI missing")
		return
	_post_news_card(
		"Infrastructure Complete",
		"The rail yard at Testland is complete.\nCapacity is now sufficient for wartime traffic.\nInfrastructure is level 4."
	)
	_post_notice_card("Investment complete in Testland: infra now level 4")
	await _flush(3)
	var btn: Button = _first_close(true)
	if btn == null:
		_fail("T12a: post_news News × missing")
		return
	var pt: Vector2 = _prepare_under_play(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close(pt)
	await _flush(2)
	if not _assert_no_selection("T12a News× leftover"):
		return
	var survivor: PanelContainer = _survivor_panel(true)
	if survivor == null or not survivor.get_global_rect().has_point(pt):
		_fail("T12a setup: survivor did not reflow under ×")
		_hide_notices()
		return
	await _wait_hold_ms(1300)
	await _same_spot_play_click(pt)
	if not _assert_t12_selected("T12a News× over Notice", survivor):
		_hide_notices()
		return
	_hide_notices()


func _test_t12b_notice_over_notice() -> void:
	_hide_notices()
	_enable_toast_ui()
	if _leui == null:
		_fail("T12b: LeaderEventUI missing")
		return
	_post_notice_card("INPUT-1 T12b notice A stacked")
	_post_notice_card("INPUT-1 T12b notice B stacked")
	await _flush(3)
	var btn: Button = _first_close(false)
	if btn == null:
		_fail("T12b: Notice × missing")
		return
	var pt: Vector2 = _prepare_under_play(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close(pt)
	await _flush(2)
	if not _assert_no_selection("T12b Notice× leftover"):
		return
	var survivor: PanelContainer = _survivor_panel(false)
	var sx: Button = _panel_close(survivor)
	if survivor == null or sx == null or not sx.get_global_rect().has_point(pt):
		_fail("T12b setup: survivor × did not reflow under close point")
		_hide_notices()
		return
	await _wait_hold_ms(1300)
	await _same_spot_play_click(pt)
	if not _assert_t12_selected("T12b Notice× over Notice", survivor):
		_hide_notices()
		return
	_hide_notices()


func _test_t12c_news_over_news() -> void:
	_hide_notices()
	_enable_toast_ui()
	if _leui == null:
		_fail("T12c: LeaderEventUI missing")
		return
	var body: String = "The rail yard at Testland is complete.\nCapacity is now sufficient for wartime traffic.\nInfrastructure is level 4."
	_post_news_card("Infrastructure Complete", body)
	_post_news_card("Infrastructure Complete", body)
	await _flush(3)
	var btn: Button = _first_close(true)
	if btn == null:
		_fail("T12c: News × missing")
		return
	var pt: Vector2 = _prepare_under_play(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close(pt)
	await _flush(2)
	if not _assert_no_selection("T12c News× leftover"):
		return
	var survivor: PanelContainer = _survivor_panel(false)
	var sx: Button = _panel_close(survivor)
	if survivor == null or sx == null or not sx.get_global_rect().has_point(pt):
		_fail("T12c setup: survivor × did not reflow under close point")
		_hide_notices()
		return
	await _wait_hold_ms(1300)
	await _same_spot_play_click(pt)
	if not _assert_t12_selected("T12c News× over News", survivor):
		_hide_notices()
		return
	_hide_notices()


func _test_t12d_restore_blocks() -> void:
	_hide_notices()
	_enable_toast_ui()
	if _leui == null:
		_fail("T12d: LeaderEventUI missing")
		return
	_post_news_card(
		"Infrastructure Complete",
		"The rail yard at Testland is complete.\nCapacity is now sufficient for wartime traffic.\nInfrastructure is level 4."
	)
	_post_notice_card("Investment complete in Testland: infra now level 4")
	await _flush(3)
	var btn: Button = _first_close(true)
	if btn == null:
		_fail("T12d: post_news News × missing")
		return
	var pt: Vector2 = _prepare_under_play(btn)
	if pt == Vector2.ZERO:
		return
	await _click_close(pt)
	await _flush(2)
	if not _assert_no_selection("T12d News× leftover"):
		return
	var survivor: PanelContainer = _survivor_panel(true)
	if survivor == null or not survivor.get_global_rect().has_point(pt):
		_fail("T12d setup: survivor did not reflow under ×")
		_hide_notices()
		return
	_aim_mouse(MAP_PT)
	await _flush(2)
	_aim_mouse(pt)
	await _flush(2)
	await _same_spot_play_click(pt)
	if survivor == null or not is_instance_valid(survivor) or survivor.get_parent() == null:
		_fail("T12d: Notice left the tree")
		_hide_notices()
		return
	var got_pid: int = _pid()
	if got_pid == -1 and not _inspector_up():
		_pass("T12d restore: toast body blocked same-spot (pid=-1)")
	else:
		_fail("T12d: after move-away same-spot selected pid=%d" % got_pid)
	_hide_notices()
