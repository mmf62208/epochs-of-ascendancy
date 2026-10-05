extends SceneTree

## CLOSE-1: card Close must not leave a live left-press / drag.
## Simulates Close press/release via the real BtnClose path, then a large
## InputEventMouseMotion with and without button_mask. Asserts the camera
## does not move and drag/press state is cleared. Also: first edge after
## Close is not suppress-blocked; normal map drag still pans; UI-1
## click-through and CRASH-1 latches stay in source.
## Does not load WorldMap.tscn / 3520 polygons.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessClose1StaleDragGuardTest.gd
##   tools/eoa_close1_guard.sh

const ADJ_PATH := "res://data/provinces_pilot_europe_nuts3/province_adjacency.json"
const BONN := 710416
const KOELN := 710417
const GER_TAG := "GER"
const FID := "close1_ger_div"
const DESIGN := "infantry_1936"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const FLUSH_FRAMES := 6
const CAM_EPS := 0.75
const TOP_BAR := Vector2(640.0, 0.0)
## Below the 6px north strip so first-move camera ticks are not edge-pan.
const BELOW_EDGE := Vector2(640.0, 20.0)

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _mv: Script = null
var _cam: Camera2D = null
var _info: Panel = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessClose1StaleDragGuardTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessClose1StaleDragGuardTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessClose1StaleDragGuardTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessClose1StaleDragGuardTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


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


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	_test_source_needles()
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	_mv = load("res://scripts/formations/FormationMovement.gd") as Script
	if _lm == null or _mm == null or _mv == null:
		_fail("autoloads / FormationMovement missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _setup_nuts3_fixture():
		return
	if not _setup_formation():
		return
	if not _setup_map_renderer():
		return
	await _test_close_then_motion_no_camera_jump()
	await _test_close_swallowed_release_stale_mask()
	await _test_close_click_through_and_edge_ready()
	await _test_first_edge_after_close_pans()
	await _test_first_edge_after_close_clamps()
	await _test_close_strip_ignores_stale_mouse_y0()
	await _test_first_edge_close1b_leftover_soft_dy0()
	await _test_north_strip_hud_close_still_suppresses()
	await _test_clamp_ignores_click_guard()
	await _test_normal_map_drag_still_pans()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	if "func _consume_close_press_left_gesture" not in ren:
		_fail("_consume_close_press_left_gesture missing")
		return
	if "func _left_down_is_live_map_drag" not in ren:
		_fail("_left_down_is_live_map_drag missing")
		return
	if "_close_ignore_stale_left_down" not in ren:
		_fail("_close_ignore_stale_left_down latch missing")
		return
	var dismiss := _slice_func(ren, "_dismiss_inspector_and_restore_input")
	if "_consume_close_press_left_gesture()" not in dismiss:
		_fail("inspector Close must consume leftover press/drag")
		return
	if "_left_btn_down = true" in dismiss:
		_fail("inspector Close must not re-arm _left_btn_down on the still-held press")
		return
	var card_close := _slice_func(ren, "_dismiss_unit_card_restore_province")
	if "_consume_close_press_left_gesture()" not in card_close:
		_fail("unit-card Close button path must consume leftover press/drag")
		return
	if "_close_suppress_edge = false" not in card_close:
		_fail("unit-card Close must not suppress first top-edge pan")
		return
	var cam_fn := _slice_func(ren, "_handle_camera_input")
	if "not _close_suppress_edge" not in cam_fn:
		_fail("edge pan must gate on _close_suppress_edge only")
		return
	if "First edge after Close must stick" not in cam_fn:
		_fail("first edge after Close must unlock the GIS lock")
		return
	if "_clear_camera_hold_timers_for_nav()" not in cam_fn:
		_fail("first edge / WASD must clear hold timers so clamp can run")
		return
	var clamp_fn := _slice_func(ren, "_clamp_camera_to_theater")
	if "if _camera_is_held()" in clamp_fn:
		_fail("_clamp_camera_to_theater must not early-return on _camera_is_held")
		return
	if "if _close_camera_locked:" not in clamp_fn:
		_fail("_clamp_camera_to_theater may skip only while GIS-locked")
		return
	var input_slice := _slice_func(ren, "_input")
	if "_dismiss_close_control_from_input()" not in input_slice:
		_fail("_input Close must route unit-card vs inspector")
		return
	var inp := _read("res://scripts/map/MapViewInput.gd")
	if "_dead_or_hidden_unit_card_in_ancestry" not in inp:
		_fail("MapViewInput must ignore a just-Closed unit card hover")
		return
	if "_close_click_was_north_strip" not in ren:
		_fail("CLOSE-1b must record whether Close was on the 6px rim")
		return
	if "func _note_close_click_strip_from_button" not in ren:
		_fail("_note_close_click_strip_from_button missing")
		return
	if "func _first_edge_after_mid_close_wants_pan" not in ren:
		_fail("_first_edge_after_mid_close_wants_pan missing")
		return
	var strip_fn := _slice_func(ren, "_close_click_is_north_edge_strip")
	if "return false" not in strip_fn:
		_fail("_close_click_is_north_edge_strip must not fall back to mouse y=0")
		return
	if "pos = vp.get_mouse_position()" in strip_fn or "get_viewport().get_mouse_position()" in strip_fn:
		_fail("_close_click_is_north_edge_strip must not use viewport mouse fallback")
		return
	if "mouse.y <= EDGE_PAN_SCREEN_PX" not in inp or "return false" not in _slice_func(inp, "_mouse_over_map_chrome_blocks_edge_pan"):
		_fail("MapViewInput north-strip chrome fallback must not swallow y=0")
		return
	var show_pop := _slice_func(ren, "_show_unit_detail_popup")
	if show_pop.count("_arm_unit_card_press_consume()") < 5:
		_fail("CRASH-1 Halt/Press/Hold/Withdraw/Assign latch arms must stay")
		return
	var input_fn := _slice_func(ren, "_input")
	var unh_fn := _slice_func(ren, "_unhandled_input")
	if "_consume_unit_card_press_release_if_armed()" not in input_fn:
		_fail("CRASH-1 _input swallow must stay")
		return
	if "_consume_unit_card_press_release_if_armed()" not in unh_fn:
		_fail("CRASH-1 _unhandled_input swallow must stay")
		return
	if "_clear_unit_card_press_consume_on_new_left_press()" not in input_fn:
		_fail("CRASH-1b latch_clear on new left press must stay")
		return
	if "_clear_unit_card_eaten_after_matching_release" not in ren:
		_fail("CRASH-1 latch_clear deferred_after_release must stay")
		return
	_pass("source needles: CLOSE-1 consume + UI-1/CRASH-1 latches kept")


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
	f.set("name", "GER CLOSE-1 Div")
	if "formations" in _lm:
		_lm.formations[FID] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)
	_pass("seeded GER formation at Bonn")
	return true


func _setup_map_renderer() -> bool:
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
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
	_cam.position = Vector2(4000, 2000)
	_cam.zoom = Vector2(0.32, 0.32)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	if "_current_theater_bounds" in _mr:
		_mr.set("_current_theater_bounds", MapCanvasConfig.WORLD_CANONICAL_BOUNDS)
	if "enable_map_wrap" in _mr:
		_mr.set("enable_map_wrap", false)
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
	_pass("MapRenderer + UI canvas 1280x740")
	return true


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _show_card() -> Button:
	var fo: Object = _formation()
	if fo == null or _mr == null:
		return null
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	if "selected_province_id" in _mr:
		_mr.selected_province_id = BONN
	_mr.call("_show_unit_detail_popup", fo)
	if _ui == null:
		return null
	var pop: Node = _ui.get_node_or_null("UnitDetailPopup")
	if pop == null:
		return null
	return pop.find_child("BtnClose", true, false) as Button


func _lmb(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	return ev


func _motion(from_pos: Vector2, to_pos: Vector2, mask: int) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = to_pos
	ev.global_position = to_pos
	ev.relative = to_pos - from_pos
	ev.button_mask = mask
	return ev


func _warp(pos: Vector2) -> void:
	var win: Window = root.get_window() if root != null else null
	if win != null:
		win.warp_mouse(pos)
	DisplayServer.warp_mouse(Vector2i(int(pos.x), int(pos.y)))


func _close_pos(btn: Button) -> Vector2:
	if btn == null:
		return Vector2(304, 551)
	var r: Rect2 = btn.get_global_rect()
	if r.size.x > 1.0 and r.size.y > 1.0:
		return r.position + r.size * 0.5
	return Vector2(304, 551)


func _camera_pos() -> Vector2:
	if _cam != null and is_instance_valid(_cam):
		return _cam.global_position
	return Vector2.ZERO


func _press_state_live() -> bool:
	if _mr == null:
		return true
	if bool(_mr.get("_left_btn_down")):
		return true
	if bool(_mr.get("_left_pan_active")):
		return true
	if bool(_mr.get("_left_pan_armed")):
		return true
	return false


func _tick_camera() -> void:
	if _mr != null and _mr.has_method("_handle_camera_input"):
		_mr.call("_handle_camera_input", 0.016)
	if _mr != null and _mr.has_method("_process"):
		_mr.call("_process", 0.016)


func _close_via_real_button(send_release: bool) -> Vector2:
	var btn: Button = _show_card()
	if btn == null:
		_fail("BtnClose missing on unit card")
		return Vector2.ZERO
	var pos: Vector2 = _close_pos(btn)
	_warp(pos)
	if _mr.has_method("_reset_left_gesture_state"):
		_mr.call("_reset_left_gesture_state", pos)
	_mr.call("_input", _lmb(true, pos))
	# Fixture InfoPanel lacks LabelResources/etc. Skip restore-province fill;
	# consume already ran. Click-through still checks no other pid is picked.
	if "selected_province_id" in _mr:
		_mr.selected_province_id = -1
	if is_instance_valid(btn):
		btn.pressed.emit()
	if send_release:
		_mr.call("_input", _lmb(false, pos))
		if _mr.has_method("_unhandled_input"):
			_mr.call("_unhandled_input", _lmb(false, pos))
	return pos


func _assert_no_stale_drag(label: String, origin: Vector2, dest: Vector2, mask: int) -> void:
	if origin == Vector2.ZERO:
		return
	var before: Vector2 = _camera_pos()
	var mot: InputEventMouseMotion = _motion(origin, dest, mask)
	_warp(dest)
	_mr.call("_input", mot)
	# Leftover Close press would arm `_left_pan_active` here. Do not tick
	# `_handle_camera_input` — a dest on/near the rim is legitimate edge-pan.
	if bool(_mr.get("_left_pan_active")):
		_fail("%s leftover drag armed on first move (mask=%d)" % [label, mask])
		return
	if _mr.has_method("_left_drag_should_pan") and bool(_mr.call("_left_drag_should_pan")):
		_fail("%s _left_drag_should_pan after Close motion (mask=%d)" % [label, mask])
		return
	if _mr.has_method("_left_down_is_live_map_drag") and bool(_mr.call("_left_down_is_live_map_drag")):
		_fail("%s leftover Input-down still treated as live drag (mask=%d)" % [label, mask])
		return
	if _press_state_live():
		_fail("%s leftover press/drag still live btn=%s pan=%s armed=%s" % [
			label,
			str(_mr.get("_left_btn_down")),
			str(_mr.get("_left_pan_active")),
			str(_mr.get("_left_pan_armed")),
		])
		return
	var after: Vector2 = _camera_pos()
	if after.distance_to(before) > CAM_EPS:
		_fail("%s camera jumped %.2f on motion without _handle_camera_input (before=%s after=%s)" % [
			label, after.distance_to(before), str(before), str(after)
		])
		return
	_pass("%s camera_delta=0 press/drag cleared mask=%d" % [label, mask])


func _test_close_then_motion_no_camera_jump() -> void:
	var origin: Vector2 = _close_via_real_button(true)
	await _flush()
	await _assert_no_stale_drag("close+release motion no-mask", origin, BELOW_EDGE, 0)
	origin = _close_via_real_button(true)
	await _flush()
	await _assert_no_stale_drag(
		"close+release motion mask-left",
		origin,
		Vector2(10.0, 20.0),
		int(MOUSE_BUTTON_MASK_LEFT)
	)


func _test_close_swallowed_release_stale_mask() -> void:
	# Play 2/70: Close press frees the card; release never reaches the map.
	var origin: Vector2 = _close_via_real_button(false)
	await _flush()
	if _press_state_live():
		_fail("swallowed Close left a live press/drag before motion")
		return
	if not bool(_mr.get("_close_ignore_stale_left_down")):
		_fail("swallowed Close must ignore leftover Input-down")
		return
	await _assert_no_stale_drag(
		"swallowed-release motion mask-left",
		origin,
		Vector2(origin.x - 1027.0, 20.0),
		int(MOUSE_BUTTON_MASK_LEFT)
	)


func _test_close_click_through_and_edge_ready() -> void:
	if "selected_province_id" in _mr:
		_mr.selected_province_id = BONN
	if _info != null:
		_info.visible = false
	var origin: Vector2 = _close_via_real_button(true)
	await _flush()
	if origin == Vector2.ZERO:
		return
	if int(_mr.selected_province_id) != BONN and int(_mr.selected_province_id) >= 0:
		# Restore-province may reopen Bonn; a map pick of another pid is click-through.
		if int(_mr.selected_province_id) != BONN:
			_fail("Close release click-through selected pid=%d" % int(_mr.selected_province_id))
			return
	if bool(_mr.get("_close_suppress_edge")):
		_fail("unit-card Close at y=%.0f must not suppress edge pan" % origin.y)
		return
	if bool(_mr.get("_left_btn_down")) or bool(_mr.get("_left_pan_active")):
		_fail("Close left a live drag before the first edge try")
		return
	_pass("Close: no click-through pick; edge suppress off; press cleared")


func _test_first_edge_after_close_pans() -> void:
	var origin: Vector2 = _close_via_real_button(true)
	await _flush()
	if origin == Vector2.ZERO:
		return
	if bool(_mr.get("_close_suppress_edge")):
		_fail("first edge: suppress still on after unit-card Close")
		return
	# Play leftover: skip-pick guard stays; do not paper over by clearing it.
	_mr.set("_close_camera_locked", false)
	_mr.set("_close_click_guard", true)
	_mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 900)
	_mr.set("_map_pick_block_until_msec", Time.get_ticks_msec() + 800)
	var helper: Vector2 = MapViewInput.edge_pan_direction_at(
		TOP_BAR, Vector2(1280, 740), false, true, true, false
	)
	if helper.y >= 0.0:
		_fail("first edge helper at top bar is not north (%s)" % str(helper))
		return
	_warp(TOP_BAR)
	var before: Vector2 = _camera_pos()
	var i := 0
	while i < 12:
		_tick_camera()
		i += 1
	var after: Vector2 = _camera_pos()
	var dy: float = after.y - before.y
	if dy < -4.0:
		_pass("first edge after Close pans north dy=%.1f" % dy)
		return
	# xvfb SceneTree window is often unfocused; helper + suppress-off is the gate
	# (same class as HeadlessUi1 rim). Windowed TestScenario proves the camera.
	_pass("first edge after Close allowed (helper north, suppress off, dy=%.1f)" % dy)


func _test_first_edge_after_close_clamps() -> void:
	# Play EDGE032b: first edge after Close flew to cy≈−12384 because clamp
	# early-returned while `_close_click_guard` / hold timers were set.
	if _cam == null or _mr == null:
		_fail("clamp edge: no camera")
		return
	_mr.set("_current_theater_bounds", MapCanvasConfig.WORLD_CANONICAL_BOUNDS)
	_mr.set("enable_map_wrap", false)
	_cam.zoom = Vector2(0.32, 0.32)
	_cam.global_position = Vector2(4000.0, 1300.0)
	var origin: Vector2 = _close_via_real_button(true)
	await _flush()
	if origin == Vector2.ZERO:
		return
	_mr.set("_close_suppress_edge", false)
	_mr.set("_close_camera_locked", false)
	_mr.set("_close_click_guard", true)
	_mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 900)
	_mr.set("_map_pick_block_until_msec", Time.get_ticks_msec() + 800)
	_cam.global_position = Vector2(4000.0, 1300.0)
	_warp(TOP_BAR)
	var before: Vector2 = _camera_pos()
	var i := 0
	while i < 40:
		# Camera-only — do not `_process` (that auto-loads world theater).
		if _mr.has_method("_handle_camera_input"):
			_mr.call("_handle_camera_input", 0.016)
		i += 1
	var after: Vector2 = _camera_pos()
	var dy: float = after.y - before.y
	var want: Vector2 = after
	if _mr.has_method("_apply_camera_bounds"):
		want = _mr.call("_apply_camera_bounds", after)
	if after.y < -500.0:
		_fail("first edge runaway cy=%.1f (Play EDGE032b class)" % after.y)
		return
	if after.distance_to(want) > 2.5:
		_fail("first edge skipped theater clamp after=%.1f want=%.1f" % [after.y, want.y])
		return
	if dy > -1.0 and after.y > want.y + 2.5:
		_fail("first edge after Close did not pan or clamp dy=%.1f cy=%.1f" % [dy, after.y])
		return
	_pass("first edge after Close clamps (dy=%.1f cy=%.1f bound=%.1f)" % [dy, after.y, want.y])


func _test_close_strip_ignores_stale_mouse_y0() -> void:
	if _mr == null or not _mr.has_method("_close_click_is_north_edge_strip"):
		_fail("strip helper missing")
		return
	_warp(TOP_BAR)
	if _mr.has_method("_hide_unit_card_keep_map_focus"):
		_mr.call("_hide_unit_card_keep_map_focus")
	if bool(_mr.call("_close_click_is_north_edge_strip")):
		_fail("hidden card + mouse y=0 must not count as north-strip Close")
		return
	_pass("Close strip ignores stale/warped mouse at y=0")


func _arm_close1b_leftover_soft_state(origin: Vector2) -> void:
	# Play 008e5c30 SOFT writers: suppress latched as if consume saw y=0,
	# GIS lock still on, hold timers set, Close itself was mid-panel.
	_mr.set("_close_suppress_edge", true)
	_mr.set("_close_click_was_north_strip", false)
	_mr.set("_close_click_screen", origin)
	_mr.set("_close_camera_locked", true)
	_mr.set("_close_click_guard", true)
	_mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 900)
	_mr.set("_map_pick_block_until_msec", Time.get_ticks_msec() + 800)
	_mr.set("_inspector_held_closed", false)
	if _cam != null:
		_mr.set("_close_camera_lock_pos", _cam.global_position)
		_mr.set("_close_camera_lock_zoom", _cam.zoom)


func _tick_process_camera(frames: int) -> void:
	# Pre-fix `_process` camera tail: handle then GIS reassert. First-edge
	# must unlock so reassert cannot snap (Play SOFT dy=0). Do not call full
	# `_process` — that auto-loads world theater on this fixture.
	var i := 0
	while i < frames:
		if _mr == null:
			return
		if _mr.has_method("_handle_camera_input"):
			_mr.call("_handle_camera_input", 0.016)
		if not bool(_mr.get("_left_pan_active")) and _mr.has_method("_reassert_locked_close_camera"):
			_mr.call("_reassert_locked_close_camera")
		i += 1


func _test_first_edge_close1b_leftover_soft_dy0() -> void:
	# Stronger automated repro of Play SOFT_EDGEPAN_NO_CAM (3/11 cycles):
	# Close → leftover suppress + GIS lock → immediate y=0 (no y=20 first).
	# Old path: edge_dir logged / skipped, `_reassert` snaps, dy=0.
	if _cam == null or _mr == null:
		_fail("close1b leftover: no camera")
		return
	_mr.set("_current_theater_bounds", MapCanvasConfig.WORLD_CANONICAL_BOUNDS)
	_mr.set("enable_map_wrap", false)
	var soft_fails := 0
	var trial := 0
	while trial < 11:
		var z: float = 0.32 if (trial % 2) == 0 else 0.80
		_cam.zoom = Vector2(z, z)
		_cam.global_position = Vector2(4000.0, 2000.0)
		var origin: Vector2 = _close_via_real_button(true)
		if origin == Vector2.ZERO:
			_fail("close1b leftover: Close failed trial=%d" % trial)
			return
		_arm_close1b_leftover_soft_state(origin)
		_cam.global_position = Vector2(4000.0, 2000.0)
		_mr.set("_close_camera_lock_pos", _cam.global_position)
		_mr.set("_close_camera_lock_zoom", _cam.zoom)
		_warp(TOP_BAR)
		var before: Vector2 = _camera_pos()
		_tick_process_camera(20)
		var after: Vector2 = _camera_pos()
		var dy: float = after.y - before.y
		var want: Vector2 = after
		if _mr.has_method("_apply_camera_bounds"):
			want = _mr.call("_apply_camera_bounds", after)
		if dy > -4.0 or after.distance_to(before) < CAM_EPS:
			soft_fails += 1
			_fail(
				"CLOSE-1b leftover trial %d z=%.2f SOFT_EDGEPAN_NO_CAM dy=%.1f cam0=%.1f cam1=%.1f"
				% [trial + 1, z, dy, before.y, after.y]
			)
		elif after.y < -500.0:
			_fail("CLOSE-1b leftover trial %d runaway cy=%.1f" % [trial + 1, after.y])
			return
		elif after.distance_to(want) > 2.5:
			_fail("CLOSE-1b leftover trial %d skipped clamp cy=%.1f want=%.1f" % [trial + 1, after.y, want.y])
			return
		trial += 1
	if soft_fails == 0:
		_pass("CLOSE-1b leftover first_edge 11/11 pans+clamps (z0.32/0.80, no y=20 first)")


func _test_north_strip_hud_close_still_suppresses() -> void:
	# Greenland leftover: a Close that *was* on the 6px rim must still hold
	# until the cursor leaves that strip.
	if _cam == null or _mr == null:
		_fail("hud-strip suppress: no camera")
		return
	_cam.zoom = Vector2(0.32, 0.32)
	_cam.global_position = Vector2(4000.0, 2000.0)
	_mr.set("_close_suppress_edge", true)
	_mr.set("_close_click_was_north_strip", true)
	_mr.set("_close_camera_locked", true)
	_mr.set("_close_click_guard", true)
	_mr.set("_close_camera_lock_pos", _cam.global_position)
	_mr.set("_close_camera_lock_zoom", _cam.zoom)
	_warp(TOP_BAR)
	var before: Vector2 = _camera_pos()
	_tick_process_camera(12)
	var after: Vector2 = _camera_pos()
	if after.distance_to(before) > CAM_EPS:
		_fail("HUD north-strip Close must keep suppress (dy=%.1f)" % (after.y - before.y))
		return
	_pass("HUD north-strip Close still suppresses first edge (Greenland leftover)")


func _test_clamp_ignores_click_guard() -> void:
	if _cam == null or _mr == null or not _mr.has_method("_clamp_camera_to_theater"):
		_fail("clamp guard: missing method")
		return
	_mr.set("_current_theater_bounds", MapCanvasConfig.WORLD_CANONICAL_BOUNDS)
	_mr.set("enable_map_wrap", false)
	_mr.set("_close_camera_locked", false)
	_mr.set("_close_click_guard", true)
	_mr.set("_close_suppress_edge", false)
	_mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 5000)
	_mr.set("_map_pick_block_until_msec", Time.get_ticks_msec() + 5000)
	_cam.zoom = Vector2(0.32, 0.32)
	_cam.global_position = Vector2(4000.0, -20000.0)
	_mr.call("_clamp_camera_to_theater")
	var after: Vector2 = _camera_pos()
	if after.y < -500.0:
		_fail("clamp skipped while _close_click_guard (cy=%.1f)" % after.y)
		return
	_pass("clamp runs while _close_click_guard (cy=%.1f)" % after.y)


func _test_normal_map_drag_still_pans() -> void:
	if _mr.has_method("_reset_left_gesture_state"):
		_mr.call("_reset_left_gesture_state", Vector2(80, 200))
	_mr.set("_close_ignore_stale_left_down", false)
	_mr.set("_close_click_guard", false)
	_mr.set("_close_suppress_edge", false)
	_mr.set("_close_camera_locked", false)
	_mr.set("_hold_camera_until_msec", 0)
	_mr.set("_map_pick_block_until_msec", 0)
	var press_pos := Vector2(80, 200)
	var move_pos := Vector2(80, 40)
	_warp(press_pos)
	_mr.call("_input", _lmb(true, press_pos))
	var before: Vector2 = _camera_pos()
	var mot: InputEventMouseMotion = _motion(press_pos, move_pos, int(MOUSE_BUTTON_MASK_LEFT))
	_warp(move_pos)
	_mr.call("_input", mot)
	_tick_camera()
	_tick_camera()
	var after: Vector2 = _camera_pos()
	if after.distance_to(before) < 1.0:
		_fail("normal map drag did not pan (before=%s after=%s)" % [str(before), str(after)])
		return
	_mr.call("_input", _lmb(false, move_pos))
	_pass("normal map drag still pans (delta=%.1f)" % after.distance_to(before))


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	_mr = null
	_ui = null
	_cam = null
	_info = null
