extends SceneTree

## BEGIN-1 FIX #3 (test-only): leftover Begin release must not pick the map.
## Product SHA f18a341a (frozen). Later commits are test / docs only.
##
## Real pipeline (T1 / leftover / follow-up click):
##   _title._input(ev)  AND  same-frame Input.parse_input_event + flush.
## Direct MapRenderer._input does not leftover-pick on main — it is not
## a behavior proof. Judge leftover / follow-up by pid / inspector / zoom
## only. Do not early-out on swallow flags.
##
##   T1  event-path 80 ms through the real pipeline. FAIL on main 425b4448
##       (Loir-et-Cher picked or inspector open). PASS on the tip.
##   T2  event Begin, drop leftover, real click 3 frames later must pick
##       (pid != -1, inspector). Catches M2 (no later-press clear).
##   T3  poll Begin, no press / no release, wait >=1000 ms + 3 frames,
##       first click must pick. Catches M1 (no expiry).
##   T4  T1 pipeline + OS.delay_msec(900) in the Begin frame, release in
##       frame N+2, must be swallowed. Catches M7 (clock not re-stamped).
##   T5  keep poll-path (b). M3: Begin hit outside the button rect so
##       button_down cannot re-arm. M9 (drop arm_frame+2 only) makes no
##       T1–T5 behavior difference.
##
##   timeout 1500 tools/run_godot.sh --headless --path . --import --quit
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessBegin1TitleReleaseFallthroughTest.gd
##   tools/eoa_begin1_guard.sh
##
## Headless / xvfb are NOT live Play.

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const PLAY_SIZE := Vector2i(1280, 740)
const LOIR := 710671
const HOLD_MS := 80
const EXPIRE_WAIT_MS := 1000
const ZOOM0 := 0.776
const CAM0 := Vector2(4200, 1000)
const MAP_PT := Vector2(640, 400)
const OUTSIDE_BEGIN_PT := Vector2(200, 580)
## M9: dropping `frames >= arm_frame + 2` from expiry (keep restamp + 750 ms)
## does not change T1–T5 leftover / follow-up pick behavior.

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _ui: CanvasLayer = null
var _info: Panel = null
var _title: CanvasLayer = null
var _container: Node2D = null
var _begin_pt: Vector2 = Vector2.ZERO
var _mm: Node = null
var _saved_pick_grid: Variant = null
var _loir_province: Object = null
var _loir_host: Node2D = null
var _event_seq: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	_restore_pick_grid()
	var ok := _failures == 0
	print("HeadlessBegin1TitleReleaseFallthroughTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessBegin1TitleReleaseFallthroughTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessBegin1TitleReleaseFallthroughTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessBegin1TitleReleaseFallthroughTest: ", msg)


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
	# Behavior cases first so fail-on-main is T1 leftover pick, not source text.
	await _test_t1_event_pipeline_80ms()
	await _test_t2_drop_leftover_later_click_picks()
	await _test_t3_poll_expire_then_first_click_picks()
	await _test_t4_same_frame_delay_release_n_plus_2()
	await _test_t5_poll_path_keeps_arm()
	await _test_t5_m3_outside_button_begin()
	await _test_keyboard_begin_then_map_click()
	_test_source_needles()


func _test_source_needles() -> void:
	# Light invariants that exist on main and the tip. Do not needle FIX #2
	# internals (clock_ready / arm_frame+2 / pending_press) — those are M7/M9
	# source-text only and are not a behavior proof.
	var title_src := _read(SRC_TITLE)
	var ren := _read(SRC_REN)
	if title_src.is_empty() or ren.is_empty():
		_fail("source files missing")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in title_src:
		_fail("Begin must stay ACTION_MODE_BUTTON_PRESS")
		return
	if "eoa_tip_dismiss_swallow_release" not in _slice_func(ren, "_arm_first_session_tip_dismiss_swallow"):
		_fail("TipDismiss swallow must stay")
		return
	_pass("source needles: ACTION_MODE_BUTTON_PRESS + TipDismiss kept (M9 is behavior-neutral)")


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt_a := src.find("\nfunc ", i + needle.length())
	var nxt_b := src.find("\nstatic func ", i + needle.length())
	var nxt := -1
	if nxt_a >= 0 and nxt_b >= 0:
		nxt = mini(nxt_a, nxt_b)
	elif nxt_a >= 0:
		nxt = nxt_a
	else:
		nxt = nxt_b
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _setup_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
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
	return true


func _restore_pick_grid() -> void:
	if _mm != null and "pick_grid" in _mm and _saved_pick_grid != null:
		_mm.pick_grid = _saved_pick_grid


func _make_province() -> Object:
	var p: Object = _new_obj("res://scripts/data/Province.gd")
	if p == null:
		return null
	p.set("id", LOIR)
	p.set("owner_tag", "FRA")
	p.set("controller_tag", "FRA")
	p.set("terrain", "plains")
	p.set("name", "Loir-et-Cher")
	p.set("is_sea", false)
	return p


func _seed_loir_under_screen(screen_pt: Vector2) -> bool:
	if _cam == null or _mr == null:
		_fail("renderer missing for Loir seed")
		return false
	var world_under: Vector2 = _cam.get_canvas_transform().affine_inverse() * screen_pt
	if _loir_province == null:
		_loir_province = _make_province()
		if _loir_province == null:
			_fail("Province create failed")
			return false
	if "provinces" in _mr:
		_mr.provinces[LOIR] = _loir_province
	if "province_centroids" in _mr:
		_mr.province_centroids[LOIR] = world_under
	if _loir_host == null:
		_loir_host = Node2D.new()
		_loir_host.name = "Province_%d" % LOIR
		_container.add_child(_loir_host)
	_loir_host.global_position = world_under
	if "province_nodes" in _mr:
		_mr.province_nodes[LOIR] = _loir_host
	if _mm != null:
		if "pick_grid" in _mm:
			_mm.pick_grid = null
		if "_centroids" in _mm and _mm._centroids is Dictionary:
			var cents: Dictionary = _mm._centroids
			cents.clear()
			cents[LOIR] = world_under
		elif _mm.has_method("sync_render_centroids"):
			_mm.call("sync_render_centroids", {LOIR: world_under})
	if "_demo_unit_icon_pids" in _mr:
		_mr._demo_unit_icon_pids = []
	var got: int = int(_mr.call("_still_click_province_pid", world_under, false))
	if got != LOIR:
		_fail("real pick path must resolve Loir-et-Cher under the click (pid=%d)" % got)
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
	# Unique so parse_input_event cannot drop a replayed instance.
	ev.set_meta("eoa_begin1_seq", _event_seq)
	return ev


func _warp_mouse(screen_pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)
	DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))


func _send_pipeline(screen_pt: Vector2, pressed: bool, through_title: bool) -> InputEventMouseButton:
	# Real leftover-pick pipeline: title._input plus same-frame parse+flush.
	_warp_mouse(screen_pt)
	var ev: InputEventMouseButton = _make_mouse(screen_pt, pressed)
	if through_title and _title != null and is_instance_valid(_title):
		_title._input(ev)
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	return ev


func _reset_map_click_latches() -> void:
	if _mr == null:
		return
	if _mr.has_method("_reset_left_gesture_state"):
		_mr.call("_reset_left_gesture_state", MAP_PT)
	elif _mr.has_method("_clear_left_slop_after_still_click"):
		_mr.call("_clear_left_slop_after_still_click")
	_mr.set("_left_skip_next_pick", false)
	_mr.set("_left_gesture_dragged", false)
	_mr.set("_left_btn_down", false)
	_mr.set("_left_button_was_up", true)
	_mr.set("_left_ready_for_still_click", true)
	_mr.set("_left_cam_moved_this_down", false)
	_mr.set("_left_pan_active", false)
	_mr.set("_left_pan_armed", false)
	_mr.set("_left_slop_latched", false)
	_mr.set("_left_release_frame", -1)
	_mr.set("_close_click_guard", false)
	_mr.set("_map_pick_block_until_msec", 0)
	_mr.set("_unit_card_consumed_press", false)
	_mr.set("_unit_card_release_eaten", false)
	_mr.set("_skip_inspector_after_march", false)
	_mr.set("_mv1_last_release_was_drag", false)
	_mr.set("selected_formation_id", "")


func _wait_hold_ms(ms: int) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _flush(n: int = 4) -> void:
	var i: int = 0
	while i < n:
		await process_frame
		i += 1


func _zoom_x() -> float:
	if _cam == null:
		return 0.0
	return absf(_cam.zoom.x)


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


func _spawn_title() -> bool:
	if _title != null and is_instance_valid(_title):
		if not _title.is_queued_for_deletion():
			_title.free()
		_title = null
	var title_scr: GDScript = load(SRC_TITLE) as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot missing")
		return false
	_title = title_scr.new() as CanvasLayer
	if _title == null:
		_fail("LivingTitleBoot create failed")
		return false
	_title.name = "LivingTitleBoot"
	_title.visible = true
	root.add_child(_title)
	await _flush(6)
	var begin: Button = _title.find_child("LivingTitleBegin", true, false) as Button
	if begin == null:
		_fail("LivingTitleBegin missing")
		return false
	begin.visible = true
	if begin.get_global_rect().size.x < 8.0 or begin.get_global_rect().size.y < 8.0:
		begin.position = Vector2(80, 180)
		begin.size = Vector2(360, 72)
		if begin.has_method("reset_size"):
			begin.reset_size()
		await _flush(3)
	var rect: Rect2 = begin.get_global_rect()
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		rect = Rect2(Vector2(80, 180), Vector2(360, 72))
		begin.position = rect.position
		begin.size = rect.size
	_begin_pt = rect.get_center()
	if _mr.has_method("_living_title_boot_is_up") and not bool(_mr.call("_living_title_boot_is_up")):
		_fail("LivingTitleBoot must be visible to MapRenderer before Begin press")
		return false
	return true


func _place_begin_button(pos: Vector2, size: Vector2) -> Button:
	var begin: Button = _title.find_child("LivingTitleBegin", true, false) as Button
	if begin == null:
		return null
	var cc_btn: Button = _title.find_child("LivingTitleCommandCenter", true, false) as Button
	if cc_btn != null:
		cc_btn.global_position = Vector2(900, 20)
		cc_btn.size = Vector2(160, 36)
	begin.global_position = pos
	begin.size = size
	return begin


func _poll_mouse() -> Vector2:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		return vp.get_mouse_position()
	return Vector2.ZERO


func _prepare_poll_begin_hit() -> bool:
	# Headless warp often leaves get_mouse_position() at the last leftover /
	# follow-up point. Cover (0,0) and the live poll point so
	# handle_live_pointer(null) is a real Begin, not panel/map.
	var poll_pt: Vector2 = _poll_mouse()
	var cover := Vector2(
		maxf(700.0, maxf(poll_pt.x, 40.0) + 80.0),
		maxf(740.0, maxf(poll_pt.y, 80.0) + 80.0)
	)
	var begin_btn: Button = _place_begin_button(Vector2(0, 0), cover)
	if begin_btn == null:
		_fail("poll-path LivingTitleBegin missing")
		return false
	await _flush(2)
	_begin_pt = begin_btn.get_global_rect().get_center()
	var owns_hit := true
	if _title.has_method("begin_owns_screen_point"):
		owns_hit = (
			bool(_title.call("begin_owns_screen_point", Vector2(0, 0)))
			or bool(_title.call("begin_owns_screen_point", poll_pt))
			or bool(_title.call("begin_owns_screen_point", Vector2(40, 80)))
		)
	if not owns_hit:
		_fail("poll-path Begin hit rect must own (0,0) or the live poll point %s" % str(poll_pt))
		return false
	_warp_mouse(Vector2(40, 80))
	return true


func _begin_closed() -> bool:
	if _title == null or not is_instance_valid(_title):
		return true
	return bool(_title.get("_closed"))


func _prepare_begin_home(screen_pt: Vector2) -> bool:
	_restore_home_camera()
	_clear_inspector()
	if not _seed_loir_under_screen(screen_pt):
		return false
	return true


func _prepare_leftover_home(screen_pt: Vector2) -> bool:
	# Restore Home under the leftover without wiping the Begin press gesture.
	_restore_home_camera()
	if not _seed_loir_under_screen(screen_pt):
		return false
	_clear_inspector()
	return true


func _assert_leftover_swallowed(screen_pt: Vector2, why: String) -> bool:
	if not _prepare_leftover_home(screen_pt):
		return false
	var z0: float = _zoom_x()
	_send_pipeline(screen_pt, false, true)
	await _flush(2)
	var got_pid: int = int(_mr.get("selected_province_id"))
	if got_pid == LOIR:
		_fail("%s: leftover release selected Loir-et-Cher (pid=%d)" % [why, got_pid])
		return false
	if got_pid > 0:
		_fail("%s: leftover release selected pid=%d" % [why, got_pid])
		return false
	if _inspector_up():
		_fail("%s: leftover release opened the inspector" % why)
		return false
	if absf(_zoom_x() - z0) > 0.002:
		_fail("%s: leftover release changed zoom %.3f -> %.3f" % [why, z0, _zoom_x()])
		return false
	_pass("%s: leftover release did not pick / inspect / zoom" % why)
	return true


func _assert_real_click_picks(screen_pt: Vector2, why: String) -> bool:
	# Do not skip when swallow is still armed — that hid M1 / M2.
	_reset_map_click_latches()
	_restore_home_camera()
	if not _seed_loir_under_screen(screen_pt):
		return false
	_clear_inspector()
	_send_pipeline(screen_pt, true, false)
	_send_pipeline(screen_pt, false, false)
	await _flush(2)
	var got_pid: int = int(_mr.get("selected_province_id"))
	if got_pid == -1:
		_fail("%s: real click must pick (pid=-1)" % why)
		return false
	if not _inspector_up():
		_fail("%s: real click must open the inspector (pid=%d)" % [why, got_pid])
		return false
	_pass("%s: real click picked pid=%d and opened inspector" % [why, got_pid])
	return true


func _test_t1_event_pipeline_80ms() -> void:
	if not await _spawn_title():
		return
	if not _prepare_begin_home(_begin_pt):
		return
	_send_pipeline(_begin_pt, true, true)
	if not _begin_closed():
		_fail("T1: Begin press via title._input + parse/flush did not close the living title")
		return
	_pass("T1: Begin press closed the title through the real pipeline")
	await _wait_hold_ms(HOLD_MS)
	await _flush(3)
	if not await _assert_leftover_swallowed(_begin_pt, "T1 event-path 80 ms leftover"):
		return
	if not await _assert_real_click_picks(MAP_PT, "T1 follow-up after leftover"):
		return


func _test_t2_drop_leftover_later_click_picks() -> void:
	if not await _spawn_title():
		return
	if not _prepare_begin_home(_begin_pt):
		return
	_send_pipeline(_begin_pt, true, true)
	if not _begin_closed():
		_fail("T2: event Begin did not close the living title")
		return
	# Drop the leftover release. Three frames later a real click must pick
	# (M2: no later-press clear keeps the arm and eats that click).
	await _flush(3)
	if not await _assert_real_click_picks(MAP_PT, "T2 click 3 frames after dropped leftover"):
		return


func _test_t3_poll_expire_then_first_click_picks() -> void:
	if not await _spawn_title():
		return
	if not await _prepare_poll_begin_hit():
		return
	_restore_home_camera()
	_clear_inspector()
	var polled: String = str(_title.call("handle_live_pointer", null))
	if polled != "begin":
		_fail("T3: poll-path handle_live_pointer(null) did not Begin (got %s)" % polled)
		return
	if not _begin_closed():
		_fail("T3: poll-path Begin did not close the living title")
		return
	_pass("T3: poll-path Begin closed the title (no press / no release)")
	# No leftover press or release. Expiry must drop the arm (M1: first click eaten).
	await _wait_hold_ms(EXPIRE_WAIT_MS)
	await _flush(3)
	if not await _assert_real_click_picks(MAP_PT, "T3 first click after 1000 ms + 3 frames"):
		return


func _test_t4_same_frame_delay_release_n_plus_2() -> void:
	if not await _spawn_title():
		return
	if not _prepare_begin_home(_begin_pt):
		return
	_send_pipeline(_begin_pt, true, true)
	if not _begin_closed():
		_fail("T4: Begin press did not close the living title")
		return
	# Clock must restamp on the first later _process. 900 ms in this frame
	# must not expire the leftover (M7: no restamp → leftover picks).
	OS.delay_msec(900)
	await process_frame
	await process_frame
	if not await _assert_leftover_swallowed(_begin_pt, "T4 same-frame 900 ms then release N+2"):
		return


func _test_t5_poll_path_keeps_arm() -> void:
	# (b) Poll-path arm in frame N, press in N+1, leftover release: no pick.
	if not await _spawn_title():
		return
	if not await _prepare_poll_begin_hit():
		return
	_restore_home_camera()
	_clear_inspector()
	if not _seed_loir_under_screen(MAP_PT):
		return
	var polled: String = str(_title.call("handle_live_pointer", null))
	if polled != "begin":
		_fail("T5(b): poll-path handle_live_pointer(null) did not Begin (got %s)" % polled)
		return
	if not _begin_closed():
		_fail("T5(b): poll-path Begin did not close the living title")
		return
	_pass("T5(b): poll-path handle_live_pointer(null) closed the title")
	await process_frame
	if not _prepare_leftover_home(MAP_PT):
		return
	_send_pipeline(MAP_PT, true, false)
	if not await _assert_leftover_swallowed(MAP_PT, "T5(b) poll N+1 press then leftover"):
		return
	if not await _assert_real_click_picks(MAP_PT, "T5(b) later click after poll leftover"):
		return


func _test_t5_m3_outside_button_begin() -> void:
	# M3 (clear on same-frame press) is masked if the hit is on LivingTitleBegin
	# (button_down re-arms). Hit left-column / slab, not the button rect.
	if not await _spawn_title():
		return
	var begin_btn: Button = _place_begin_button(Vector2(80, 160), Vector2(360, 72))
	if begin_btn == null:
		_fail("T5 M3: LivingTitleBegin missing")
		return
	await _flush(2)
	var btn_rect: Rect2 = begin_btn.get_global_rect()
	var hit: Vector2 = OUTSIDE_BEGIN_PT
	if btn_rect.has_point(hit):
		hit = Vector2(btn_rect.position.x + 8.0, btn_rect.end.y + 80.0)
	if btn_rect.has_point(hit):
		_fail("T5 M3: outside-button hit still inside LivingTitleBegin")
		return
	if _title.has_method("left_column_is_begin") and not bool(_title.call("left_column_is_begin", hit)):
		_fail("T5 M3: hit must be a left-column Begin (not the button)")
		return
	if not _prepare_begin_home(hit):
		return
	_send_pipeline(hit, true, true)
	if not _begin_closed():
		_fail("T5 M3: outside-button Begin did not close the living title")
		return
	_pass("T5 M3: outside-button Begin closed the title (button_down cannot re-arm)")
	await _wait_hold_ms(HOLD_MS)
	await _flush(2)
	if not await _assert_leftover_swallowed(hit, "T5 M3 outside-button leftover"):
		return


func _send_begin_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.echo = false
	if _title != null and is_instance_valid(_title):
		_title._input(ev)
	if _title != null and is_instance_valid(_title) and not _begin_closed():
		if _mr != null:
			_mr._input(ev)
	if _title != null and is_instance_valid(_title) and not _begin_closed():
		if _title.has_method("handle_live_begin"):
			_title.call("handle_live_begin")


func _test_keyboard_begin_then_map_click() -> void:
	for keycode in [KEY_ENTER, KEY_SPACE]:
		var key_name: String = "Enter" if keycode == KEY_ENTER else "Space"
		if not await _spawn_title():
			return
		_clear_inspector()
		_send_begin_key(keycode)
		if not _begin_closed():
			_fail("keyboard Begin (%s) did not close the living title" % key_name)
			return
		_pass("keyboard Begin (%s) closed the title" % key_name)
		if not await _assert_real_click_picks(MAP_PT, "map click after keyboard Begin (%s)" % key_name):
			return
