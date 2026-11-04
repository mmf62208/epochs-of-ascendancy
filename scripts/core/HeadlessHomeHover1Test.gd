extends SceneTree

## FIRST20-FIX-1 Home and hover. Home puts the player capital (GER Berlin)
## within 40 px of the screen centre at the Europe start zoom. Hover uses the
## same pick as a click, including after the camera moves under a still cursor.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessHomeHover1Test.gd

const PLAY_SIZE := Vector2i(1280, 800)
const BERLIN := 710300
const PARIS := 710707
const ROME := 710963
const BONN := 710416
const BERN := 710500

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	if not _setup():
		_finish()
		return
	await _frames(2)
	_case_home_centers_berlin()
	await _case_hover_matches_click()
	await _case_still_cursor_follows_camera()
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessHomeHover1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessHomeHover1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] ", msg)


func _frames(n: int) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1


func _setup() -> bool:
	var lm := root.get_node_or_null("LeaderManager")
	var mm := root.get_node_or_null("MapManager")
	if lm == null or mm == null:
		_fail("LeaderManager or MapManager missing")
		return false
	if lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var rows: Array = [
		{"id": BERLIN, "tag": "GER", "name": "Berlin", "at": Vector2(4200, 1600)},
		{"id": PARIS, "tag": "FRA", "name": "Paris", "at": Vector2(2800, 2000)},
		{"id": ROME, "tag": "ITA", "name": "Rome", "at": Vector2(4000, 3200)},
		{"id": BONN, "tag": "GER", "name": "Bonn", "at": Vector2(5200, 1600)},
		{"id": BERN, "tag": "SWI", "name": "Bern", "at": Vector2(3600, 2600)},
	]
	if not _load_map(mm, rows):
		return false
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = scr.new() as Node
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.enabled = true
	_cam.position = Vector2(100, 100)
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	# MapRenderer._process clamps and edge-pans. Home's own clamp still runs;
	# a wide theater keeps the capital at the screen centre. Hover cases set
	# the camera themselves and must not be pulled back on the next frame.
	_mr.set_process(false)
	_mr.set("_current_theater_bounds", Rect2(-80000, -80000, 200000, 200000))
	for row in rows:
		var pid := int(row["id"])
		var gp: Object = mm.call("get_province", pid)
		if gp == null:
			_fail("province %d missing" % pid)
			return false
		_mr.provinces[pid] = gp
	_pass("home/hover fixture ready")
	return true


func _load_map(mm: Node, rows: Array) -> bool:
	var prov_scr: Script = load("res://scripts/data/Province.gd") as Script
	var adj_scr: Script = load("res://scripts/data/AdjacencySystem.gd") as Script
	var map_scr: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	if prov_scr == null or adj_scr == null or map_scr == null:
		_fail("map fixture scripts missing")
		return false
	var provs: Dictionary = {}
	var geometry: Dictionary = {}
	for row in rows:
		var p: Object = prov_scr.new()
		var pid := int(row["id"])
		p.set("id", pid)
		p.set("owner_tag", str(row["tag"]))
		p.set("controller_tag", str(row["tag"]))
		p.set("name", str(row["name"]))
		p.set("terrain", "plains")
		p.set("is_sea", false)
		p.set("coordinates", row["at"])
		provs[pid] = p
		geometry[pid] = {"points": _square(row["at"], 90.0)}
	var countries: Dictionary = {
		"GER": {"tag": "GER", "name": "Germany", "capital_province_id": 0},
		"FRA": {"tag": "FRA", "name": "France", "capital_province_id": 0},
		"ITA": {"tag": "ITA", "name": "Italy", "capital_province_id": 0},
		"SWI": {"tag": "SWI", "name": "Switzerland", "capital_province_id": 0},
	}
	var map_data: Object = map_scr.new(provs, geometry, adj_scr.new(), countries)
	if not mm.has_method("initialize_from_map_data"):
		_fail("initialize_from_map_data missing")
		return false
	mm.call("initialize_from_map_data", map_data)
	return true


func _square(center: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-half, -half),
		center + Vector2(half, -half),
		center + Vector2(half, half),
		center + Vector2(-half, half),
	])


func _screen_center() -> Vector2:
	var vp := _mr.get_viewport()
	if vp == null:
		return Vector2(PLAY_SIZE) * 0.5
	var sz := vp.get_visible_rect().size
	if sz.x < 10.0 or sz.y < 10.0:
		sz = Vector2(PLAY_SIZE)
	return sz * 0.5


func _screen_of_pid(pid: int) -> Vector2:
	var mm := root.get_node_or_null("MapManager")
	var c: Vector2 = mm.call("get_province_centroid", pid)
	_cam.force_update_transform()
	return _cam.get_canvas_transform() * c


func _case_home_centers_berlin() -> void:
	print("HOME_HOVER case=home")
	_mr.set("_current_theater_bounds", Rect2(-80000, -80000, 200000, 200000))
	_mr.call("_apply_home_key", false)
	_cam.force_update_transform()
	var screen := _screen_of_pid(BERLIN)
	var center := _screen_center()
	var dist := screen.distance_to(center)
	var cam_at: Vector2 = _cam.global_position
	var mm := root.get_node_or_null("MapManager")
	var berlin: Vector2 = mm.call("get_province_centroid", BERLIN)
	print("HOME_HOVER berlin_screen=%s center=%s dist=%.1f cam=%s berlin_world=%s" % [str(screen), str(center), dist, str(cam_at), str(berlin)])
	if dist > 40.0:
		_fail("Home left Berlin %.1f px from screen centre (want <= 40)" % dist)
		return
	var center_pid := int(_mr.call("province_id_at_screen", center))
	var center_name := _province_name(center_pid)
	print("HOME_HOVER center_pick=%d %s" % [center_pid, center_name])
	if center_pid != BERLIN and _owner(center_pid) != "GER":
		_fail("camera centre is not on the player's land (%s)" % center_name)
		return
	_pass("Home puts Berlin within 40 px of screen centre")


func _province_name(pid: int) -> String:
	if not _mr.provinces.has(pid):
		return ""
	return str(_mr.provinces[pid].name)


func _owner(pid: int) -> String:
	if not _mr.provinces.has(pid):
		return ""
	return str(_mr.provinces[pid].owner_tag).strip_edges().to_upper()


func _hover_name() -> String:
	var hov: Object = _mr.get("_hover_province")
	if hov == null:
		return ""
	return str(hov.get("name"))


## Headless DisplayServer::mouse_get_position stays (0, 0) and warp_mouse does
## not write Input's cursor. The root viewport reads that cursor through the
## screen transform. parse + flush is what sets it.
func _set_mouse(pt: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pt
	motion.global_position = pt
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func _mouse() -> Vector2:
	var vp := _mr.get_viewport()
	if vp == null:
		return Vector2.ZERO
	return vp.get_mouse_position()


func _warp(pt: Vector2) -> void:
	_set_mouse(pt)
	var got := _mouse()
	if got.distance_to(pt) <= 1.5:
		return
	# Screen transform scaled the cursor. One probe inverts a uniform scale.
	_set_mouse(Vector2(200, 100))
	var probe := _mouse()
	var sx := 200.0 / probe.x if absf(probe.x) > 0.5 else 1.0
	var sy := 100.0 / probe.y if absf(probe.y) > 0.5 else 1.0
	_set_mouse(Vector2(pt.x * sx, pt.y * sy))


func _case_hover_matches_click() -> void:
	print("HOME_HOVER case=five")
	var pids: Array = [BERLIN, PARIS, ROME, BONN, BERN]
	for pid_v in pids:
		var pid := int(pid_v)
		var want := _province_name(pid)
		_cam.global_position = root.get_node("MapManager").call("get_province_centroid", pid)
		_cam.force_update_transform()
		var screen := _screen_of_pid(pid)
		_warp(screen)
		await _frames(1)
		_mr.call("_update_spatial_hover")
		var hover_pid := int(_mr.call("province_id_at_screen", screen))
		var click_pid := int(_mr.call("_still_click_province_pid", _mr.call("_screen_to_world", screen), false))
		var hover_name := _hover_name()
		print("HOME_HOVER pid=%d want=%s hover=%s hover_pid=%d click_pid=%d screen=%s mouse=%s" % [pid, want, hover_name, hover_pid, click_pid, str(screen), str(_mouse())])
		if hover_name != want:
			_fail("hover at %s read %s (mouse %s)" % [want, hover_name, str(_mouse())])
			return
		if hover_pid != pid or click_pid != pid:
			_fail("hover/click disagree at %s (hover %d click %d)" % [want, hover_pid, click_pid])
			return
	_pass("hover matches click on 5 provinces")


func _case_still_cursor_follows_camera() -> void:
	print("HOME_HOVER case=still_cursor")
	var mm := root.get_node("MapManager")
	_cam.zoom = Vector2(1, 1)
	_cam.global_position = mm.call("get_province_centroid", BERLIN)
	_cam.force_update_transform()
	var screen := _screen_of_pid(BERLIN)
	_warp(screen)
	await _frames(1)
	_mr.set("_last_hover_mouse", Vector2(-99999, -99999))
	_mr.call("_update_spatial_hover")
	if _hover_name() != "Berlin":
		_fail("still-cursor setup did not hover Berlin (%s)" % _hover_name())
		return
	_cam.global_position = mm.call("get_province_centroid", BERN)
	_cam.force_update_transform()
	# Cursor stays at the same screen point. The land under it is now Bern.
	_mr.call("_update_spatial_hover")
	var hover_name := _hover_name()
	var picked := int(_mr.call("province_id_at_screen", _mr.get_viewport().get_mouse_position()))
	print("HOME_HOVER still hover=%s pick=%d %s" % [hover_name, picked, _province_name(picked)])
	if hover_name == "Berlin" or hover_name != "Bern":
		_fail("camera move under a still cursor left hover on %s" % hover_name)
		return
	if _province_name(picked) != hover_name:
		_fail("still-cursor hover %s != pick %s" % [hover_name, _province_name(picked)])
		return
	_pass("hover follows the camera when the cursor stays still")
