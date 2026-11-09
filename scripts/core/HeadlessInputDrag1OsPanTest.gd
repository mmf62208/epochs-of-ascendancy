extends SceneTree

## INPUT-DRAG-1: OS-like coarse left/middle drags must pan from the events
## themselves (not `_process` polling get_mouse_position). Release after a
## pan must not open a unit/division panel. Left still-click still opens the
## land chip. Middle still-click opens nothing.
##
## Injects InputEventMouseButton press + coarse InputEventMouseMotion steps
## (4×60px) and the fine 20×5px recipe. Does not load WorldMap.tscn / 3520.
## Must FAIL on main 02b77a78 (coarse left/middle do not pan; coarse left
## release on a chip opens UnitDetailPopup) and PASS on the tip.
## Headless is NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessInputDrag1OsPanTest.gd

const ADJ_PATH := "res://data/provinces_pilot_europe_nuts3/province_adjacency.json"
const BONN := 710416
const KOELN := 710417
const GER_TAG := "GER"
const FID := "input_drag1_ger_div"
const DESIGN := "infantry_1936"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const PLAY_SIZE := Vector2i(1280, 740)
const CAM_START := Vector2(4000.0, 1200.0)
const START_Z := 0.80
const CHIP_PT := Vector2(720.0, 420.0)
const EMPTY_PT := Vector2(480.0, 360.0)
const CAM_EPS := 8.0
const FLUSH_FRAMES := 4
const COARSE_STEP_PX := 60.0
const COARSE_STEPS := 4
const FINE_STEP_PX := 5.0
const FINE_STEPS := 20

var _failures: int = 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _cam: Camera2D = null
var _info: Panel = null
var _event_seq: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessInputDrag1OsPanTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessInputDrag1OsPanTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessInputDrag1OsPanTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessInputDrag1OsPanTest: ", msg)


func _info_line(msg: String) -> void:
	print("  [INFO] HeadlessInputDrag1OsPanTest: ", msg)


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


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	_test_source_needles()
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	if _lm == null or _mm == null:
		_fail("LeaderManager / MapManager missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _setup_nuts3_fixture():
		return
	if not _setup_formation():
		return
	if not _setup_map_renderer():
		return
	_pause_sim()
	await _flush()
	_test_coarse_left_drag_pans_no_panel()
	_test_coarse_left_release_on_chip_no_panel()
	_test_fine_left_20x5_pans_no_panel()
	_test_coarse_middle_drag_pans_no_panel()
	_test_left_still_click_opens_chip()
	_test_middle_still_click_opens_nothing()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	if "LEFT_PAN_SLOP_PX" not in ren or "8.0" not in ren:
		_fail("left pan slop must stay 8px")
		return
	if "_is_middle_dragging" not in ren:
		_fail("_is_middle_dragging missing")
		return
	var input_fn := _slice_func(ren, "_input")
	if "MOUSE_BUTTON_MIDDLE" not in input_fn or "MOUSE_BUTTON_RIGHT" not in input_fn:
		_fail("_input must keep middle/right pan")
		return
	if "STARTUP_BLANK_MOVE_PX" not in ren:
		_fail("#167 startup-blank swallow must stay")
		return
	if "_apply_pointer_drag_pan" not in ren:
		_fail("mutant poll_only_pan: MapRenderer must apply pan from pointer events")
		return
	var motion_fn := _slice_func(ren, "_handle_pointer_motion_pan")
	if motion_fn.is_empty() or "mm.relative" not in motion_fn:
		_fail("mutant ignore_event_relative: motion pan must read event.relative")
		return
	if "_handle_pointer_motion_pan" not in input_fn:
		_fail("_input must route MouseMotion through _handle_pointer_motion_pan")
		return
	var mid_btn := _slice_func(ren, "_handle_middle_or_right_pointer")
	if mid_btn.is_empty():
		_fail("_handle_middle_or_right_pointer missing")
		return
	if "set_input_as_handled" not in mid_btn:
		_fail("middle/right must mark the event handled (press and release)")
		return
	var chip_fn := _slice_func(ren, "_try_open_land_chip_from_input")
	if "_is_middle_dragging" not in chip_fn and "MOUSE_BUTTON_MIDDLE" not in chip_fn:
		_fail("_try_open_land_chip_from_input must refuse middle/right")
		return
	_pass("source needles: event pan + middle never-pick + #167 swallow kept")


func _setup_nuts3_fixture() -> bool:
	if not FileAccess.file_exists(ADJ_PATH):
		_fail("nuts3 adjacency missing")
		return false
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	if adj_sys.has_method("load_adjacency"):
		adj_sys.call("load_adjacency", ADJ_PATH)
	var rows: Array = [
		{"id": BONN, "tag": GER_TAG, "name": "Bonn"},
		{"id": KOELN, "tag": GER_TAG, "name": "Köln"},
	]
	var provs: Dictionary = {}
	var countries: Dictionary = {GER_TAG: {"tag": GER_TAG, "name": "Germany"}}
	for row in rows:
		var pid := int(row["id"])
		var p: Object = _new_obj("res://scripts/data/Province.gd")
		if p == null:
			_fail("Province create failed")
			return false
		p.set("id", pid)
		p.set("owner_tag", GER_TAG)
		p.set("controller_tag", GER_TAG)
		p.set("terrain", "plains")
		p.set("name", str(row["name"]))
		p.set("is_sea", false)
		p.set("infrastructure", 4)
		p.set("development_level", 3)
		p.set("core_for", [GER_TAG])
		provs[pid] = p
		if adj_sys.has_method("register_province"):
			adj_sys.call("register_province", p)
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = mds.new(provs, {}, adj_sys, countries) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	if _mm.has_method("initialize_from_map_data"):
		_mm.call("initialize_from_map_data", map_data)
	else:
		_fail("initialize_from_map_data missing")
		return false
	_pass("nuts3 fixture Bonn/Köln")
	return true


func _setup_formation() -> bool:
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("Formation create failed")
		return false
	f.set("formation_id", FID)
	f.set("country_tag", GER_TAG)
	f.set("formation_type", "division")
	f.set("design_id", DESIGN)
	f.set("stationed_province_id", BONN)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set("name", "GER Division")
	if "formations" in _lm:
		_lm.formations[FID] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)
	_pass("seeded GER Division at Bonn")
	return true


func _setup_map_renderer() -> bool:
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("MapRenderer.gd failed to load")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer.new() failed")
		return false
	_mr.name = "MapRenderer"
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_mr.add_child(_ui)
	_info = Panel.new()
	_info.name = "InfoPanel"
	_info.visible = false
	_info.size = Vector2(280, 200)
	_ui.add_child(_info)
	_mr.set("info_panel", _info)
	var stub_keys: PackedStringArray = PackedStringArray([
		"info_name", "info_owner", "info_population", "info_terrain", "info_factories", "info_dev",
	])
	var stub_names: PackedStringArray = PackedStringArray([
		"LabelName", "LabelOwner", "LabelPopulation", "LabelTerrain", "LabelFactories", "LabelDev",
	])
	var si := 0
	while si < stub_keys.size():
		var lbl := Label.new()
		lbl.name = stub_names[si]
		_info.add_child(lbl)
		_mr.set(stub_keys[si], lbl)
		si += 1
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_mr.set_process(false)
	_mr.set_process_input(true)
	_mr.set_process_unhandled_input(true)
	if "_close_camera_locked" in _mr:
		_mr.set("_close_camera_locked", false)
	if "_close_suppress_edge" in _mr:
		_mr.set("_close_suppress_edge", false)
	if "_close_click_guard" in _mr:
		_mr.set("_close_click_guard", false)
	if "_startup_blank_armed" in _mr:
		_mr.set("_startup_blank_armed", false)
	if "enable_map_wrap" in _mr:
		_mr.set("enable_map_wrap", false)
	if "use_spatial_picking" in _mr:
		_mr.set("use_spatial_picking", true)
	if "show_unit_counters" in _mr:
		_mr.set("show_unit_counters", true)
	if "_current_theater_bounds" in _mr:
		_mr.set("_current_theater_bounds", Rect2(-40000.0, -40000.0, 120000.0, 120000.0))
	for pid_v in [BONN, KOELN]:
		var pid := int(pid_v)
		var gp: Variant = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
		if gp == null:
			_fail("MapManager missing province %d" % pid)
			return false
		if "provinces" in _mr:
			_mr.provinces[pid] = gp
		var node := Node2D.new()
		node.name = "Province_%d" % pid
		container.add_child(node)
		if "province_nodes" in _mr:
			_mr.province_nodes[pid] = node
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = Vector2(float(pid % 100) * 8.0, 40.0)
	_place_chip_at_screen(CHIP_PT)
	_pass("MapRenderer fixture ready @ 1280x740 z=0.80")
	return true


func _pause_sim() -> void:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _place_chip_at_screen(screen: Vector2) -> void:
	if _mr == null or _cam == null:
		return
	var fo: Object = _formation()
	if fo == null:
		return
	var host: Node2D = null
	if "province_nodes" in _mr and _mr.province_nodes.has(BONN):
		host = _mr.province_nodes[BONN] as Node2D
	if host == null:
		return
	var old: Node = host.get_node_or_null("DemoUnitIcon_%d" % BONN)
	if old != null:
		old.free()
	var world: Vector2 = _cam.get_canvas_transform().affine_inverse() * screen
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_%d" % BONN
	icon.visible = true
	host.add_child(icon)
	icon.global_position = world
	icon.set_meta("formation", fo)
	icon.set_meta("formation_id", FID)
	icon.set_meta("province_id", BONN)
	if "_demo_unit_icon_pids" in _mr:
		var pids: Array = _mr._demo_unit_icon_pids
		if not pids.has(BONN):
			pids.append(BONN)
			_mr._demo_unit_icon_pids = pids


func _camera_pos() -> Vector2:
	if _cam != null and is_instance_valid(_cam):
		return _cam.global_position
	return Vector2.ZERO


func _unit_panel_up() -> bool:
	if _ui == null:
		return false
	var pop: Node = _ui.get_node_or_null("UnitDetailPopup")
	if pop != null and is_instance_valid(pop) and pop is CanvasItem:
		return (pop as CanvasItem).visible
	return pop != null


func _hide_unit_panel() -> void:
	if _mr != null and _mr.has_method("_hide_unit_card_keep_map_focus"):
		_mr.call("_hide_unit_card_keep_map_focus")
	if _ui != null:
		var pop: Node = _ui.get_node_or_null("UnitDetailPopup")
		if pop != null:
			pop.queue_free()
	if _mr != null and "selected_formation_id" in _mr:
		_mr.selected_formation_id = ""
	if _info != null:
		_info.visible = false


func _reset_gesture() -> void:
	if _mr == null:
		return
	if _mr.has_method("_reset_left_gesture_state"):
		_mr.call("_reset_left_gesture_state", EMPTY_PT)
	_mr.set("_is_middle_dragging", false)
	_mr.set("_left_btn_down", false)
	_mr.set("_left_pan_active", false)
	_mr.set("_left_pan_armed", false)
	_mr.set("_close_click_guard", false)
	_mr.set("_close_camera_locked", false)
	_mr.set("_startup_blank_armed", false)
	if "selected_province_id" in _mr:
		_mr.selected_province_id = -1
	_hide_unit_panel()
	_cam.global_position = CAM_START
	_cam.zoom = Vector2(START_Z, START_Z)
	_place_chip_at_screen(CHIP_PT)


func _make_button(screen_pt: Vector2, pressed: bool, button: int) -> InputEventMouseButton:
	_event_seq += 1
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = pressed
	ev.canceled = false
	ev.double_click = false
	ev.position = screen_pt
	ev.global_position = screen_pt
	var mask := 0
	if pressed:
		if button == MOUSE_BUTTON_LEFT:
			mask = MOUSE_BUTTON_MASK_LEFT
		elif button == MOUSE_BUTTON_MIDDLE:
			mask = MOUSE_BUTTON_MASK_MIDDLE
		elif button == MOUSE_BUTTON_RIGHT:
			mask = MOUSE_BUTTON_MASK_RIGHT
	ev.button_mask = mask
	ev.set_meta("eoa_input_drag1_seq", _event_seq)
	return ev


func _make_motion(screen_pt: Vector2, relative: Vector2, mask: int) -> InputEventMouseMotion:
	_event_seq += 1
	var ev := InputEventMouseMotion.new()
	ev.device = 0
	ev.position = screen_pt
	ev.global_position = screen_pt
	ev.relative = relative
	ev.velocity = relative * 60.0
	ev.button_mask = mask
	ev.set_meta("eoa_input_drag1_seq", _event_seq)
	return ev


func _feed(ev: InputEvent, also_unhandled: bool = true) -> void:
	if _mr == null:
		return
	_mr._input(ev)
	if also_unhandled and _mr.has_method("_unhandled_input"):
		_mr._unhandled_input(ev)


func _inject_drag(start: Vector2, step: Vector2, steps: int, button: int, tick_camera: bool) -> void:
	var mask := MOUSE_BUTTON_MASK_LEFT
	if button == MOUSE_BUTTON_MIDDLE:
		mask = MOUSE_BUTTON_MASK_MIDDLE
	elif button == MOUSE_BUTTON_RIGHT:
		mask = MOUSE_BUTTON_MASK_RIGHT
	_feed(_make_button(start, true, button))
	var pt: Vector2 = start
	var i := 0
	while i < steps:
		pt += step
		_feed(_make_motion(pt, step, mask), false)
		if tick_camera and _mr.has_method("_handle_camera_input"):
			_mr.call("_handle_camera_input", 1.0 / 60.0)
		i += 1
	_feed(_make_button(pt, false, button))


func _drag_pan_ok(label: String, before: Vector2, after: Vector2) -> bool:
	var d: Vector2 = after - before
	var dcam: float = d.length()
	_info_line("%s dcam=%.2f d=(%.2f,%.2f) panel=%s fid=%s" % [
		label, dcam, d.x, d.y, str(_unit_panel_up()), str(_mr.get("selected_formation_id")),
	])
	if dcam < CAM_EPS:
		_fail("%s did not pan (dcam=%.2f before=%s after=%s)" % [label, dcam, str(before), str(after)])
		return false
	# Rightward drag → camera west. Reject leftover (0,0) edge-pan (NW diagonal).
	if d.x >= -1.0:
		_fail("%s pan was not westward for a right drag d=%s" % [label, str(d)])
		return false
	if absf(d.y) > absf(d.x) * 0.75:
		_fail("%s pan was not drag-axis (edge-pan?) d=%s" % [label, str(d)])
		return false
	return true


func _panel_closed(label: String) -> bool:
	if _unit_panel_up() or str(_mr.get("selected_formation_id")) == FID:
		_fail("%s opened a unit/division panel" % label)
		return false
	return true


func _test_coarse_left_drag_pans_no_panel() -> void:
	_reset_gesture()
	var before: Vector2 = _camera_pos()
	_inject_drag(EMPTY_PT, Vector2(COARSE_STEP_PX, 0.0), COARSE_STEPS, MOUSE_BUTTON_LEFT, false)
	var after: Vector2 = _camera_pos()
	var pan_ok: bool = _drag_pan_ok("coarse left 4x60 empty", before, after)
	var panel_ok: bool = _panel_closed("coarse left 4x60 empty")
	if pan_ok and panel_ok:
		_pass("coarse left-drag pans (dcam=%.2f) and opens no panel" % after.distance_to(before))


func _test_coarse_left_release_on_chip_no_panel() -> void:
	_reset_gesture()
	var start := CHIP_PT - Vector2(COARSE_STEP_PX * float(COARSE_STEPS), 0.0)
	var before: Vector2 = _camera_pos()
	_inject_drag(start, Vector2(COARSE_STEP_PX, 0.0), COARSE_STEPS, MOUSE_BUTTON_LEFT, false)
	var after: Vector2 = _camera_pos()
	var pan_ok: bool = _drag_pan_ok("coarse left onto chip", before, after)
	var panel_ok: bool = _panel_closed("coarse left-drag release on chip")
	if pan_ok and panel_ok:
		_pass("coarse left-drag onto chip pans and does not pick")


func _test_fine_left_20x5_pans_no_panel() -> void:
	_reset_gesture()
	var before: Vector2 = _camera_pos()
	_inject_drag(EMPTY_PT, Vector2(FINE_STEP_PX, 0.0), FINE_STEPS, MOUSE_BUTTON_LEFT, true)
	var after: Vector2 = _camera_pos()
	var pan_ok: bool = _drag_pan_ok("fine left 20x5", before, after)
	var panel_ok: bool = _panel_closed("fine left 20x5")
	if pan_ok and panel_ok:
		_pass("fine 20x5 left-drag pans (dcam=%.2f) and opens no panel" % after.distance_to(before))


func _test_coarse_middle_drag_pans_no_panel() -> void:
	_reset_gesture()
	var before: Vector2 = _camera_pos()
	_inject_drag(CHIP_PT, Vector2(COARSE_STEP_PX, 0.0), COARSE_STEPS, MOUSE_BUTTON_MIDDLE, false)
	var after: Vector2 = _camera_pos()
	var pan_ok: bool = _drag_pan_ok("coarse middle over chip", before, after)
	var panel_ok: bool = _panel_closed("middle-drag")
	if pan_ok and panel_ok:
		_pass("coarse middle-drag pans (dcam=%.2f) and never opens a panel" % after.distance_to(before))


func _test_left_still_click_opens_chip() -> void:
	_reset_gesture()
	var before: Vector2 = _camera_pos()
	_feed(_make_button(CHIP_PT, true, MOUSE_BUTTON_LEFT))
	_feed(_make_button(CHIP_PT, false, MOUSE_BUTTON_LEFT))
	var after: Vector2 = _camera_pos()
	if after.distance_to(before) > CAM_EPS:
		_fail("left still-click panned the camera (dcam=%.2f)" % after.distance_to(before))
		return
	if not _unit_panel_up() and str(_mr.get("selected_formation_id")) != FID:
		_fail("left still-click did not open the land chip (fid=%s panel=%s)" % [
			str(_mr.get("selected_formation_id")), str(_unit_panel_up()),
		])
		return
	_pass("left still-click opens the land chip")


func _test_middle_still_click_opens_nothing() -> void:
	_reset_gesture()
	_feed(_make_button(CHIP_PT, true, MOUSE_BUTTON_MIDDLE))
	_feed(_make_button(CHIP_PT, false, MOUSE_BUTTON_MIDDLE))
	if _unit_panel_up() or str(_mr.get("selected_formation_id")) == FID:
		_fail("middle still-click opened a unit/division panel")
		return
	if _info != null and _info.visible:
		_fail("middle still-click opened the inspector")
		return
	_pass("middle still-click opens nothing")


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	_mr = null
	_ui = null
	_cam = null
	_info = null
