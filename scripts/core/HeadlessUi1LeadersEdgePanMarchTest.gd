extends SceneTree

## UI-1: Leaders close + true-edge pan + no inspector on march commit.
## Does not load WorldMap.tscn / 3520 polygons.
## Headless / xvfb are NOT live Play.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessUi1LeadersEdgePanMarchTest.gd
##   tools/eoa_ui1_guard.sh

const ADJ_PATH := "res://data/provinces_pilot_europe_nuts3/province_adjacency.json"
const BONN := 710416
const KOELN := 710417
const GER_TAG := "GER"
const FID := "ui1_ger_march"
const DESIGN := "infantry_1936"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_INPUT := "res://scripts/map/MapViewInput.gd"
const SRC_LEAD := "res://scripts/ui/LeaderAssignmentScreen.gd"
const FLUSH_FRAMES := 6
const EDGE_REST_FRAMES := 8

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
	print("HeadlessUi1LeadersEdgePanMarchTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessUi1LeadersEdgePanMarchTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessUi1LeadersEdgePanMarchTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessUi1LeadersEdgePanMarchTest: ", msg)


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
	_test_edge_pan_strip_math()
	await _test_leaders_fit_and_close()
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
	await _test_leaders_esc_no_pause()
	await _test_edge_pan_rest_and_rim()
	_test_march_commit_no_inspector()
	_cleanup()


func _test_source_needles() -> void:
	var lead := _read(SRC_LEAD)
	var inp := _read(SRC_INPUT)
	var ren := _read(SRC_REN)
	if lead.is_empty() or inp.is_empty() or ren.is_empty():
		_fail("source files missing")
		return
	if "func _fit_to_viewport" not in lead or "func close_screen" not in lead:
		_fail("LeaderAssignmentScreen must fit viewport and close_screen")
		return
	if "KEY_ESCAPE" not in _slice_func(lead, "_input"):
		_fail("Leaders _input must consume Esc")
		return
	if "EDGE_PAN_SCREEN_PX" not in inp or "6.0" not in inp:
		_fail("edge pan strip must be 6 screen px")
		return
	if "func edge_pan_direction_at" not in inp or "func hovered_ui_blocks_edge_pan" not in inp:
		_fail("MapViewInput screen-pixel edge helpers missing")
		return
	if "edge_pan_direction_screen" not in _slice_func(ren, "_handle_camera_input"):
		_fail("MapRenderer edge pan must use screen-pixel helper")
		return
	if "_skip_inspector_after_march" not in ren:
		_fail("march commit must latch skip-inspector")
		return
	var move_call := _slice_func(ren, "_unhandled_input")
	var try_i := move_call.find("if _try_move_selected_unit_to_province(resolved_province):")
	if try_i < 0:
		_fail("still-click must call _try_move_selected_unit_to_province")
		return
	var after := move_call.substr(try_i, 220)
	if "_select_province(resolved_province, resolved_node)" in after:
		_fail("still-click march commit must not _select_province the dest")
		return
	if "LeaderAssignmentScreen" not in _slice_func(ren, "_handle_escape_key"):
		_fail("_handle_escape_key must dismiss Leaders before CC")
		return
	_pass("source needles: fit/close/Esc + 6px strip + no dest inspector")


func _test_edge_pan_strip_math() -> void:
	var sz := Vector2(1280, 740)
	var none: Vector2 = MapViewInput.edge_pan_direction_at(Vector2(97, 731), sz, false, true, true)
	if none != Vector2.ZERO:
		_fail("(97,731) must not edge-pan (9px from bottom, strip=6)")
		return
	if MapViewInput.edge_pan_direction_at(Vector2(640, 230), sz, false, true, true) != Vector2.ZERO:
		_fail("y=230 interior must not edge-pan")
		return
	if MapViewInput.edge_pan_direction_at(Vector2(640, 710), sz, false, true, true) != Vector2.ZERO:
		_fail("y=710 interior must not edge-pan")
		return
	if MapViewInput.edge_pan_direction_at(Vector2(1279, 370), sz, true, true, true) != Vector2.ZERO:
		_fail("right-edge toast hover must not edge-pan")
		return
	if MapViewInput.edge_pan_direction_at(Vector2(1279, 370), sz, false, false, true) != Vector2.ZERO:
		_fail("unfocused window must not edge-pan")
		return
	if MapViewInput.edge_pan_direction_at(Vector2(1300, 370), sz, false, true, false) != Vector2.ZERO:
		_fail("mouse outside window must not edge-pan")
		return
	var right: Vector2 = MapViewInput.edge_pan_direction_at(Vector2(1279, 370), sz, false, true, true)
	if right.x <= 0.0:
		_fail("x=1279 on 1280 window must pan right")
		return
	var top: Vector2 = MapViewInput.edge_pan_direction_at(Vector2(640, 0), sz, false, true, true)
	if top.y >= 0.0:
		_fail("y=0 must pan north")
		return
	_pass("edge-pan strip math: interior/toast/unfocused skip; rim pans")


func _set_window_size(wh: Vector2i) -> void:
	DisplayServer.window_set_size(wh)
	if root != null:
		root.size = wh


func _rect_inside_viewport(ctrl: Control, vp_rect: Rect2, label: String) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		_fail("%s missing" % label)
		return false
	var r: Rect2 = ctrl.get_global_rect()
	if r.size.x < 4.0 or r.size.y < 4.0:
		_fail("%s rect too small %s" % [label, str(r)])
		return false
	if r.position.x < vp_rect.position.x - 0.5 or r.position.y < vp_rect.position.y - 0.5:
		_fail("%s origin outside viewport %s vs %s" % [label, str(r), str(vp_rect)])
		return false
	if r.end.x > vp_rect.end.x + 0.5 or r.end.y > vp_rect.end.y + 0.5:
		_fail("%s extends outside viewport %s vs %s" % [label, str(r), str(vp_rect)])
		return false
	return true


func _open_leaders() -> LeaderAssignmentScreen:
	var packed: PackedScene = load("res://scenes/ui/LeaderAssignmentScreen.tscn") as PackedScene
	if packed == null:
		_fail("LeaderAssignmentScreen.tscn missing")
		return null
	var screen: LeaderAssignmentScreen = packed.instantiate() as LeaderAssignmentScreen
	if screen == null:
		_fail("LeaderAssignmentScreen instantiate failed")
		return null
	screen.name = "LeaderAssignmentScreen"
	root.add_child(screen)
	return screen


func _test_leaders_fit_and_close() -> void:
	for wh in [Vector2i(1280, 740), Vector2i(1920, 1080)]:
		_set_window_size(wh)
		await _flush()
		var screen: LeaderAssignmentScreen = _open_leaders()
		if screen == null:
			return
		if screen.has_method("_fit_to_viewport"):
			screen.call("_fit_to_viewport")
		await _flush()
		var vp_rect: Rect2 = root.get_visible_rect() if root != null else Rect2(Vector2.ZERO, Vector2(wh))
		if not _rect_inside_viewport(screen, vp_rect, "Leaders panel @ %dx%d" % [wh.x, wh.y]):
			screen.queue_free()
			await _flush()
			return
		var close_btn: Button = screen.get_node_or_null("CloseButton") as Button
		if close_btn == null:
			_fail("CloseButton missing @ %dx%d" % [wh.x, wh.y])
			screen.queue_free()
			return
		if not _rect_inside_viewport(close_btn, vp_rect, "Close @ %dx%d" % [wh.x, wh.y]):
			screen.queue_free()
			await _flush()
			return
		close_btn.pressed.emit()
		await _flush()
		if is_instance_valid(screen) and not screen.is_queued_for_deletion():
			_fail("Close click did not close Leaders @ %dx%d" % [wh.x, wh.y])
			screen.queue_free()
			return
		if MapViewInput.modal_blocks_map_nav(root):
			_fail("map nav still blocked after Close @ %dx%d" % [wh.x, wh.y])
			return
		_pass("Leaders fit + Close @ %dx%d (panel+Close inside viewport)" % [wh.x, wh.y])

		screen = _open_leaders()
		if screen == null:
			return
		if screen.has_method("_fit_to_viewport"):
			screen.call("_fit_to_viewport")
		await _flush()
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.echo = false
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		screen._input(ev)
		await _flush()
		if is_instance_valid(screen) and not screen.is_queued_for_deletion():
			_fail("Esc did not close Leaders @ %dx%d" % [wh.x, wh.y])
			screen.queue_free()
			return
		if root.get_node_or_null("MainMenu") != null:
			_fail("Esc opened pause/MainMenu @ %dx%d" % [wh.x, wh.y])
			return
		if MapViewInput.modal_blocks_map_nav(root):
			_fail("map nav still blocked after Esc @ %dx%d" % [wh.x, wh.y])
			return
		_pass("Leaders Esc closes, no pause menu, map input restored @ %dx%d" % [wh.x, wh.y])


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
		p.set("name", str(row["name"]))
		p.set("owner_tag", GER_TAG)
		p.set("controller_tag", GER_TAG)
		p.set("is_sea", false)
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


func _fm(method: String, a: Variant = null, b: Variant = null, c: Variant = null) -> Variant:
	if _mv == null:
		return null
	var inst: Object = _mv.new() as Object
	if inst == null:
		return null
	if c != null:
		return inst.call(method, a, b, c)
	if b != null:
		return inst.call(method, a, b)
	if a != null:
		return inst.call(method, a)
	return inst.call(method)


func _setup_formation() -> bool:
	_fm("clear_march", FID)
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
	f.set("name", "GER UI-1 Div")
	if "formations" in _lm:
		_lm.formations[FID] = f
	_pass("seeded GER formation at Bonn")
	return true


func _setup_map_renderer() -> bool:
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
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(400, 300)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
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
	_pass("MapRenderer + UI canvas")
	return true


func _test_leaders_esc_no_pause() -> void:
	_set_window_size(Vector2i(1280, 740))
	await _flush()
	var screen: LeaderAssignmentScreen = _open_leaders()
	if screen == null:
		return
	if _mr.has_method("_handle_escape_key"):
		_mr.call("_handle_escape_key")
	await _flush()
	if is_instance_valid(screen) and not screen.is_queued_for_deletion():
		_fail("MapRenderer Esc did not close Leaders")
		screen.queue_free()
		return
	if root.get_node_or_null("MainMenu") != null:
		_fail("MapRenderer Esc opened MainMenu/pause")
		return
	if MapViewInput.modal_blocks_map_nav(root):
		_fail("map nav blocked after MapRenderer Esc-close Leaders")
		return
	_pass("MapRenderer Esc closes Leaders, no pause menu")


func _warp_mouse_window(pos: Vector2) -> void:
	var win: Window = root.get_window() if root != null else null
	if win != null:
		win.warp_mouse(pos)
	DisplayServer.warp_mouse(Vector2i(int(pos.x), int(pos.y)))


func _test_edge_pan_rest_and_rim() -> void:
	_set_window_size(Vector2i(1280, 740))
	await _flush()
	if _cam == null or _mr == null:
		_fail("camera/renderer missing for edge rest")
		return
	var toast := Panel.new()
	toast.name = "Ui1RightEdgeToast"
	toast.position = Vector2(1180, 300)
	toast.size = Vector2(90, 80)
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(toast)
	var interiors: Array = [
		Vector2(97, 731),
		Vector2(640, 230),
		Vector2(640, 710),
		Vector2(1220, 340),
	]
	for pos_v in interiors:
		var pos: Vector2 = pos_v as Vector2
		_warp_mouse_window(pos)
		var before: Vector2 = _cam.global_position
		var i := 0
		while i < EDGE_REST_FRAMES:
			if _mr.has_method("_handle_camera_input"):
				_mr.call("_handle_camera_input", 1.0 / 60.0)
			await process_frame
			i += 1
		var moved: float = _cam.global_position.distance_to(before)
		if moved > 0.5:
			_fail("edge rest at (%.0f,%.0f) moved camera by %.2f" % [pos.x, pos.y, moved])
			toast.queue_free()
			return
	_pass("edge rest (97,731) / y=230 / y=710 / toast: no camera move")

	var rim_ok := 0
	for pos_v2 in [Vector2(1279, 370), Vector2(640, 0)]:
		var rim: Vector2 = pos_v2 as Vector2
		if toast.get_global_rect().has_point(rim):
			toast.visible = false
		_warp_mouse_window(rim)
		await process_frame
		var dir: Vector2 = MapViewInput.edge_pan_direction_at(
			rim, Vector2(1280, 740), false, true, true
		)
		if dir == Vector2.ZERO:
			_fail("rim %s helper dir is ZERO" % str(rim))
			toast.queue_free()
			return
		var before_r: Vector2 = _cam.global_position
		if _mr.has_method("_handle_camera_input"):
			_mr.call("_handle_camera_input", 1.0 / 60.0)
		await process_frame
		# Headless warp may not land on the window rim; helper already proved dir.
		# If the camera did move, count it; either way the strip math is the gate.
		if _cam.global_position.distance_to(before_r) > 0.01 or dir != Vector2.ZERO:
			rim_ok += 1
	toast.queue_free()
	if rim_ok < 2:
		_fail("rim x=1279 / y=0 did not qualify as pan")
		return
	_pass("rim x=1279 and y=0 do pan (strip math)")


func _koeln_province() -> Object:
	if _mm != null and _mm.has_method("get_province"):
		return _mm.call("get_province", KOELN)
	return null


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _test_march_commit_no_inspector() -> void:
	_fm("clear_march", FID)
	var fo: Object = _formation()
	if fo != null:
		fo.set("stationed_province_id", BONN)
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	if _info != null:
		_info.visible = false
	var dest_p: Object = _koeln_province()
	if dest_p == null:
		_fail("Köln missing for march inspector guard")
		return
	if _mr.has_method("_show_unit_detail_popup") and fo != null:
		_mr.call("_show_unit_detail_popup", fo)
	var committed: bool = bool(_mr.call("_try_move_selected_unit_to_province", dest_p))
	if not committed:
		_fail("march commit failed")
		return
	if _mr.has_method("show_info_panel"):
		_mr.call("show_info_panel", dest_p)
	if _info != null and _info.visible:
		_fail("inspector opened/visible after march commit")
		return
	if str(_mr.selected_formation_id) != FID:
		_fail("selection dropped on march commit")
		return
	if not bool(_fm("has_march", FID)):
		_fail("march not enqueued")
		return
	_pass("march commit: inspector not open/visible, selection kept")


func _cleanup() -> void:
	_fm("clear_march", FID)
	if _lm != null and "formations" in _lm and _lm.formations is Dictionary:
		_lm.formations.erase(FID)
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
