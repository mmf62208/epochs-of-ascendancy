extends SceneTree

## BEGIN-1: a normal ~80 ms Begin click must not leftover-pick the map.
## FIX #1: swallow clears on a new left press and expires (400 ms / 24 frames).
## Drive real InputEventMouseButton press/release through MapRenderer _input /
## _unhandled_input. Follow-up and no-release clicks must select via the real
## pick path (pid != -1, no _select_province fallback).
## Does not load WorldMap.tscn / 3520. Headless / xvfb are NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessBegin1TitleReleaseFallthroughTest.gd
##   tools/eoa_begin1_guard.sh

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const PLAY_SIZE := Vector2i(1280, 740)
const LOIR := 710671
const HOLD_MS := 80
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
	if "BEGIN_SWALLOW_CAP_MSEC" not in ren or "BEGIN_SWALLOW_CAP_FRAMES" not in ren:
		_fail("Begin swallow must expire on a short msec/frame cap")
		return
	if "func _clear_begin_title_release_swallow_on_new_left_press" not in ren:
		_fail("Begin swallow must clear on a new left press")
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
	_pass("source needles: Begin press-arm + expiry + clear-on-press + TipDismiss kept")


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
		if "_centroids" in _mm:
			_mm._centroids = {LOIR: world_under}
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


func _send_mouse(screen_pt: Vector2, pressed: bool) -> InputEventMouseButton:
	if DisplayServer.get_name() != "headless":
		DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))
	var ev: InputEventMouseButton = _press_at(screen_pt) if pressed else _release_at(screen_pt)
	if _mr != null:
		_mr._input(ev)
		_mr._unhandled_input(ev)
	return ev


func _reset_map_click_latches() -> void:
	if _mr == null:
		return
	if _mr.has_method("_clear_left_slop_after_still_click"):
		_mr.call("_clear_left_slop_after_still_click")
	_mr.set("_left_skip_next_pick", false)
	_mr.set("_left_gesture_dragged", false)
	_mr.set("_left_btn_down", false)
	_mr.set("_left_button_was_up", true)
	_mr.set("_left_ready_for_still_click", true)
	_mr.set("_unit_card_consumed_press", false)
	_mr.set("_unit_card_release_eaten", false)
	_mr.set("_skip_inspector_after_march", false)
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
	var ev: InputEventMouseButton = _press_at(_begin_pt)
	_mr._input(ev)
	if not bool(_title.get("_closed")):
		_title._input(ev)
	if not bool(_title.get("_closed")):
		_fail("Begin mouse press did not close the living title via _input")
		return false
	_pass("Begin mouse press closed the title via real InputEventMouseButton")
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("Begin mouse press did not arm leftover-release swallow")
		return false
	_pass("Begin leftover-release swallow armed")
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
	_send_mouse(screen_pt, true)
	await _flush(2)
	_send_mouse(screen_pt, false)
	await _flush(3)
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


func _test_keyboard_begin_then_map_click() -> void:
	if not await _spawn_title():
		return
	_clear_inspector()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	_title._input(enter)
	if not bool(_title.get("_closed")):
		_fail("keyboard Enter did not close the living title via _input")
		return
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("keyboard Begin must not arm leftover-release swallow")
		return
	_pass("keyboard Begin closed the title and did not arm swallow")
	await _assert_real_map_click_selects(MAP_PT, "map click after keyboard Begin")


func _test_swallow_expires_and_new_press_clears() -> void:
	if _mr == null:
		_fail("renderer missing for swallow expiry")
		return
	_mr.call("arm_begin_title_release_swallow")
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("arm_begin_title_release_swallow did not arm")
		return
	var t0: int = Time.get_ticks_msec()
	var f0: int = Engine.get_process_frames()
	while (
		Time.get_ticks_msec() - t0 < 450
		and Engine.get_process_frames() - f0 < 30
	):
		await process_frame
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("Begin swallow still armed after 400 ms / 24 frames")
		return
	_pass("Begin swallow expired on its own (400 ms / 24 frames)")
	_mr.call("arm_begin_title_release_swallow")
	if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("re-arm before new-press clear failed")
		return
	_send_mouse(MAP_PT, true)
	if bool(_mr.call("_begin_title_release_blocks_map_pick")):
		_fail("new left press did not clear the Begin swallow")
		return
	_pass("new left press cleared the Begin swallow")
	_send_mouse(MAP_PT, false)
	await _flush(2)
	_clear_inspector()
	await _assert_real_map_click_selects(MAP_PT, "map click after armed-no-release")
