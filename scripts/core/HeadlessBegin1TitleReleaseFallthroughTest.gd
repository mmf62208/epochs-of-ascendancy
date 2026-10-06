extends SceneTree

## BEGIN-1: a normal ~80 ms Begin click must not leftover-pick the map.
## FIX #2: clock starts after the Begin frame (restamp on first later _process).
## Poll-path arms set begin_press_pending so the click's own N+1 press keeps
## the arm. Event-path keeps the same-frame rule. button_down arms only while
## left is held (Enter/Space must not arm).
## Drive real InputEventMouseButton through title _input then MapRenderer
## _input (same frame). No manual arm. Follow-up / later clicks must select
## via the real pick path (pid != -1, no _select_province fallback).
## Does not load WorldMap.tscn / 3520. Headless / xvfb are NOT live Play.
##
##   timeout 1500 tools/run_godot.sh --headless --path . --import --quit
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessBegin1TitleReleaseFallthroughTest.gd
##   tools/eoa_begin1_guard.sh

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const PLAY_SIZE := Vector2i(1280, 740)
const LOIR := 710671
const HOLD_MS := 80
const EXPIRE_WAIT_MS := 800
const ZOOM0 := 0.776
const CAM0 := Vector2(4200, 1000)
const MAP_PT := Vector2(640, 400)

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


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	root.size = PLAY_SIZE
	_test_source_needles()
	if not _setup_renderer():
		return
	await _test_80ms_begin_does_not_pick()
	await _test_next_map_click_still_selects()
	await _test_keyboard_begin_then_map_click()
	await _test_swallow_expires_and_new_press_clears()
	await _test_same_frame_delay_does_not_expire()
	await _test_poll_path_late_press_keeps_arm()


func _test_source_needles() -> void:
	var title_src := _read(SRC_TITLE)
	var ren := _read(SRC_REN)
	if title_src.is_empty() or ren.is_empty():
		_fail("source files missing")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in title_src:
		_fail("Begin must stay ACTION_MODE_BUTTON_PRESS")
		return
	if "button_down.connect(_arm_begin_release_swallow)" not in title_src:
		_fail("Begin press must arm leftover-release swallow")
		return
	var arm_title_fn := _slice_func(title_src, "_arm_begin_release_swallow")
	if arm_title_fn.is_empty() or "os_left_button_held" not in arm_title_fn:
		_fail("button_down arm must require os_left_button_held (keyboard Begin must not arm)")
		return
	var begin_fn := _slice_func(title_src, "_on_begin_new")
	if begin_fn.is_empty() or "if _closed:" not in begin_fn:
		_fail("_on_begin_new must no-op when already closed (double-fire)")
		return
	if "os_left_button_held" not in begin_fn:
		_fail("_on_begin_new must arm swallow only while left is down")
		return
	if "eoa_begin_swallow_release" not in ren:
		_fail("MapRenderer must keep eoa_begin_swallow_release meta")
		return
	if "func arm_begin_title_release_swallow" not in ren:
		_fail("MapRenderer must expose arm_begin_title_release_swallow")
		return
	var arm_fn := _slice_func(ren, "arm_begin_title_release_swallow")
	if "get_ticks_msec" not in arm_fn or "get_process_frames" not in arm_fn:
		_fail("arm_begin_title_release_swallow must store arm time and arm frame")
		return
	if "pending_press" not in arm_fn or "eoa_begin_swallow_press_pending" not in arm_fn:
		_fail("arm_begin_title_release_swallow must take pending_press and set begin_press_pending")
		return
	if "BEGIN_TITLE_SWALLOW_EXPIRE_MS" not in ren and "750" not in _slice_func(ren, "_begin_title_release_blocks_map_pick"):
		_fail("Begin swallow must expire after ~750 ms")
		return
	var tick_fn := _slice_func(ren, "_tick_begin_title_release_swallow")
	if "eoa_begin_swallow_clock_ready" not in tick_fn or "get_ticks_msec" not in tick_fn:
		_fail("_tick_begin_title_release_swallow must restamp the clock after the Begin frame")
		return
	var exp_fn := _slice_func(ren, "_begin_title_release_swallow_expired")
	if "eoa_begin_swallow_clock_ready" not in exp_fn or "arm_frame + 2" not in exp_fn:
		_fail("expiry must require restamp and frames >= arm_frame + 2")
		return
	if "func _clear_begin_title_release_swallow_on_new_left_press" not in ren:
		_fail("Begin swallow must clear on a new left press")
		return
	var clear_press_fn := _slice_func(ren, "_clear_begin_title_release_swallow_on_new_left_press")
	if "eoa_begin_swallow_arm_frame" not in clear_press_fn:
		_fail("new left press must clear only in a later frame than the arming")
		return
	if "eoa_begin_swallow_press_pending" not in clear_press_fn:
		_fail("new left press must keep the arm when begin_press_pending (poll-path late press)")
		return
	var apply_fn := _slice_func(title_src, "_apply_pointer_hit")
	if "pending_press" not in apply_fn or "_on_begin_new(pending_press" not in apply_fn:
		_fail("_apply_pointer_hit must pass event-vs-poll pending_press into _on_begin_new")
		return
	var begin_new_fn := _slice_func(title_src, "_on_begin_new")
	if "pending_press" not in begin_new_fn or "from_pointer" not in begin_new_fn:
		_fail("_on_begin_new must take pending_press / from_pointer from the pointer path")
		return
	var input_fn := _slice_func(ren, "_input")
	if "_begin_title_release_blocks_map_pick" not in input_fn:
		_fail("MapRenderer._input must swallow the Begin leftover release")
		return
	if "_clear_begin_title_release_swallow_on_new_left_press" not in input_fn:
		_fail("MapRenderer._input must drop the swallow on a new left press")
		return
	var un_fn := _slice_func(ren, "_unhandled_input")
	if "_begin_title_release_blocks_map_pick" not in un_fn:
		_fail("MapRenderer._unhandled_input must swallow the Begin leftover release")
		return
	if "_clear_begin_title_release_swallow_on_new_left_press" not in un_fn:
		_fail("MapRenderer._unhandled_input must drop the swallow on a new left press")
		return
	var chip_fn := _slice_func(ren, "_try_open_land_chip_from_input")
	if "_begin_title_release_blocks_map_pick" not in chip_fn:
		_fail("land-chip still-click must honor the Begin swallow")
		return
	var area_fn := _slice_func(ren, "_on_province_input")
	if "_begin_title_release_blocks_map_pick" not in area_fn:
		_fail("Area2D leftover release must honor the Begin swallow")
		return
	if "_clear_begin_title_release_swallow_on_new_left_press" not in area_fn:
		_fail("Area2D new press must drop the Begin swallow")
		return
	if "eoa_tip_dismiss_swallow_release" not in _slice_func(ren, "_arm_first_session_tip_dismiss_swallow"):
		_fail("TipDismiss swallow must stay")
		return
	_pass("source needles: restamp clock + poll pending_press + later-frame clear + TipDismiss kept")


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
	# First show_info_panel creates ProvinceIdBadge and currently also
	# _clear_selection(). Prime the badge so the follow-up pick keeps pid.
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
		# Isolate nearest-centroid fallback: only Loir sits under this click.
		# Typed Dictionary[int, Vector2] cannot be replaced by an untyped dict.
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


func _release_at(screen_pt: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = screen_pt
	ev.global_position = screen_pt
	return ev


func _press_at(screen_pt: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = screen_pt
	ev.global_position = screen_pt
	return ev


func _warp_mouse(screen_pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)
	DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))


func _send_mouse(screen_pt: Vector2, pressed: bool) -> InputEventMouseButton:
	_warp_mouse(screen_pt)
	var ev: InputEventMouseButton = _press_at(screen_pt) if pressed else _release_at(screen_pt)
	if _mr != null:
		_mr._input(ev)
		_mr._unhandled_input(ev)
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
		begin.position = Vector2(80, 420)
		begin.size = Vector2(360, 72)
		if begin.has_method("reset_size"):
			begin.reset_size()
		await _flush(3)
	var rect: Rect2 = begin.get_global_rect()
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		rect = Rect2(Vector2(80, 420), Vector2(360, 72))
		begin.position = rect.position
		begin.size = rect.size
	_begin_pt = rect.get_center()
	if not bool(_mr.call("_living_title_boot_is_up")):
		_fail("LivingTitleBoot must be visible to MapRenderer before Begin press")
		return false
	return true


func _begin_via_real_mouse_press() -> bool:
	if not await _spawn_title():
		return false
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	_clear_inspector()
	if not _seed_loir_under_screen(_begin_pt):
		return false
	_warp_mouse(_begin_pt)
	var ev: InputEventMouseButton = _press_at(_begin_pt)
	# Title _input first, then MapRenderer _input in the same frame (c).
	# A mutant that also clears on the same-frame press (M3) drops the arm.
	_title._input(ev)
	if not bool(_title.get("_closed")):
		_fail("Begin mouse press did not close the living title via title _input")
		return false
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("title _input Begin did not arm leftover-release swallow")
		return false
	_mr._input(ev)
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("same-frame MapRenderer _input press cleared the Begin swallow")
		return false
	_pass("Begin mouse press closed the title via title _input then MapRenderer _input")
	_pass("Begin leftover-release swallow armed through same-frame title+map press")
	return true


func _test_80ms_begin_does_not_pick() -> void:
	if not await _begin_via_real_mouse_press():
		return
	await _wait_hold_ms(HOLD_MS)
	await _flush(3)
	if _title != null and is_instance_valid(_title) and not _title.is_queued_for_deletion():
		if not bool(_title.get("_closed")):
			_fail("title still open after 80 ms")
			return
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	if not _seed_loir_under_screen(_begin_pt):
		return
	_clear_inspector()
	var z0: float = _zoom_x()
	var pid0: int = int(_mr.get("selected_province_id"))
	_send_mouse(_begin_pt, false)
	await _flush(2)
	var got_pid: int = int(_mr.get("selected_province_id"))
	if got_pid != pid0 and got_pid == LOIR:
		_fail("Begin leftover release selected Loir-et-Cher via real pick (pid=%d)" % got_pid)
		return
	if got_pid != pid0 and got_pid > 0:
		_fail("Begin leftover release selected pid=%d" % got_pid)
		return
	if _inspector_up():
		_fail("Begin leftover release opened the inspector")
		return
	if absf(_zoom_x() - z0) > 0.002:
		_fail("Begin leftover release changed zoom %.3f -> %.3f" % [z0, _zoom_x()])
		return
	_pass("80 ms Begin leftover release did not pick / inspect / zoom")
	await _flush(3)
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("Begin swallow stayed armed after the leftover release")
		return
	_pass("Begin swallow cleared after one leftover release")


func _assert_real_map_click_selects(screen_pt: Vector2, why: String) -> bool:
	_reset_map_click_latches()
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	if not _seed_loir_under_screen(screen_pt):
		return false
	_clear_inspector()
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("%s: swallow still armed; would eat a real map click" % why)
		return false
	_warp_mouse(screen_pt)
	_send_mouse(screen_pt, true)
	_send_mouse(screen_pt, false)
	await _flush(2)
	var got_pid: int = int(_mr.get("selected_province_id"))
	if got_pid != LOIR:
		_fail("%s: real pick path must select Loir-et-Cher (pid=%d)" % [why, got_pid])
		return false
	if not _inspector_up():
		_fail("%s: real pick path must open the inspector" % why)
		return false
	_pass("%s: real map click selected pid=%d and opened inspector" % [why, got_pid])
	return true


func _test_next_map_click_still_selects() -> void:
	if _mr == null or _cam == null:
		_fail("renderer missing for follow-up click")
		return
	await _assert_real_map_click_selects(MAP_PT, "follow-up after leftover Begin")


func _send_begin_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.echo = false
	if _title != null and is_instance_valid(_title):
		_title._input(ev)
	if _title != null and is_instance_valid(_title) and not bool(_title.get("_closed")):
		if _mr != null:
			_mr._input(ev)
	if _title != null and is_instance_valid(_title) and not bool(_title.get("_closed")):
		if _title.has_method("handle_live_begin"):
			_title.call("handle_live_begin")


func _test_keyboard_begin_then_map_click() -> void:
	for keycode in [KEY_ENTER, KEY_SPACE]:
		var key_name: String = "Enter" if keycode == KEY_ENTER else "Space"
		if not await _spawn_title():
			return
		_clear_inspector()
		_send_begin_key(keycode)
		if not bool(_title.get("_closed")):
			_fail("keyboard Begin (%s) did not close the living title" % key_name)
			return
		if bool(_mr.call("_begin_title_release_blocks_map_pick")):
			_fail("keyboard Begin (%s) armed leftover-release swallow" % key_name)
			return
		_pass("keyboard Begin (%s) closed the title and did not arm swallow" % key_name)
		if not await _assert_real_map_click_selects(MAP_PT, "map click after keyboard Begin (%s)" % key_name):
			return


func _test_swallow_expires_and_new_press_clears() -> void:
	# Lost leftover up after a real Begin press: expire, then first click picks.
	if not await _begin_via_real_mouse_press():
		return
	await _wait_hold_ms(EXPIRE_WAIT_MS)
	await _flush(2)
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("lost-release swallow stayed armed after %d ms expiry" % EXPIRE_WAIT_MS)
		return
	_pass("lost-release swallow expired after ~750 ms")
	if not await _assert_real_map_click_selects(MAP_PT, "first click after lost-release expiry"):
		return
	# Separately: lost leftover up, then a later-frame fresh press clears.
	if not await _begin_via_real_mouse_press():
		return
	await _flush(3)
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("swallow dropped before the later-frame press (cannot prove clear-on-press)")
		return
	_send_mouse(MAP_PT, true)
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("later-frame left press did not clear the Begin swallow")
		return
	_pass("later-frame left press cleared the Begin swallow")
	_send_mouse(MAP_PT, false)
	await _flush(2)
	_clear_inspector()
	if not await _assert_real_map_click_selects(MAP_PT, "first click after lost-release + fresh press"):
		return


func _assert_leftover_release_did_not_pick(screen_pt: Vector2, why: String) -> bool:
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	if not _seed_loir_under_screen(screen_pt):
		return false
	_clear_inspector()
	var z0: float = _zoom_x()
	var pid0: int = int(_mr.get("selected_province_id"))
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("%s: swallow not armed before leftover release" % why)
		return false
	_send_mouse(screen_pt, false)
	await _flush(2)
	var got_pid: int = int(_mr.get("selected_province_id"))
	if got_pid != pid0 and got_pid == LOIR:
		_fail("%s: leftover release selected Loir-et-Cher via real pick (pid=%d)" % [why, got_pid])
		return false
	if got_pid != pid0 and got_pid > 0:
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


func _test_same_frame_delay_does_not_expire() -> void:
	# (a) Real Begin press, then 900 ms wall-clock in the same frame.
	# Clock must not start until the first later _process restamp.
	if not await _begin_via_real_mouse_press():
		return
	OS.delay_msec(900)
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("same-frame 900 ms delay expired the swallow before leftover release")
		return
	await process_frame
	if not await _assert_leftover_release_did_not_pick(_begin_pt, "same-frame 900 ms Begin then next-frame release"):
		return
	await _flush(2)
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("Begin swallow stayed armed after the delayed leftover release")
		return
	_pass("same-frame 900 ms stall did not expire the Begin swallow")


func _test_poll_path_late_press_keeps_arm() -> void:
	# (b) Poll-path arm in frame N (handle_live_pointer(null)), press in N+1,
	# then leftover release: no pick. A later click still picks.
	if not await _spawn_title():
		return
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	_clear_inspector()
	if not _seed_loir_under_screen(_begin_pt):
		return
	_warp_mouse(_begin_pt)
	var polled: String = str(_title.call("handle_live_pointer", null))
	if polled != "begin":
		_fail("poll-path handle_live_pointer(null) did not Begin (got %s)" % polled)
		return
	if not bool(_title.get("_closed")):
		_fail("poll-path Begin did not close the living title")
		return
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("poll-path Begin did not arm leftover-release swallow")
		return
	_pass("poll-path handle_live_pointer(null) closed the title and armed swallow")
	await process_frame
	_reset_map_click_latches()
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	if not _seed_loir_under_screen(_begin_pt):
		return
	_clear_inspector()
	_send_mouse(_begin_pt, true)
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("poll-path N+1 press cleared the Begin swallow")
		return
	_pass("poll-path N+1 press kept the Begin swallow")
	if not await _assert_leftover_release_did_not_pick(_begin_pt, "poll-path N+1 press then leftover release"):
		return
	await _flush(2)
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("poll-path leftover release left the swallow armed")
		return
	if not await _assert_real_map_click_selects(MAP_PT, "later click after poll-path leftover"):
		return
