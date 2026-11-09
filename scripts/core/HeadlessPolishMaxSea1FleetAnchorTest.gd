extends SceneTree

## POLISH-MAX-SEA-1 B: STACK fleet_anchor must not leave SeaNationDisk rects.
## North Sea 950000 (GER/FRA/SOV/JAP) in the z<0.6 STACK band shows fleet
## diamonds only. Mid and full bands keep the nation disk.
##
## Must FAIL on main e451b53f (SeaNationDisk stays visible at z=0.55) and
## PASS on the tip. Headless is NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessPolishMaxSea1FleetAnchorTest.gd

const LOD := preload("res://scripts/map/MapZoomLOD.gd")
const NORTH_SEA := 950000
const STACK_Z := 0.55
const STACK_TOP_Z := 0.59
const MID_Z := 0.80
const FULL_Z := 1.30
const HOME_Z := 0.787
const TAGS: Array[String] = ["GER", "FRA", "SOV", "JAP"]
const TAG_COLORS := {
	"GER": Color(0.35, 0.38, 0.42),
	"FRA": Color(0.22, 0.35, 0.72),
	"SOV": Color(0.72, 0.18, 0.18),
	"JAP": Color(0.78, 0.22, 0.28),
}

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _icons: Array[Node2D] = []


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	var ok := _failures == 0
	print("HeadlessPolishMaxSea1FleetAnchorTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPolishMaxSea1FleetAnchorTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPolishMaxSea1FleetAnchorTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPolishMaxSea1FleetAnchorTest: ", msg)


func _info_line(msg: String) -> void:
	print("  [INFO] HeadlessPolishMaxSea1FleetAnchorTest: ", msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if root != null:
		root.size = Vector2i(1280, 800)
	_test_policy()
	if not await _boot_sea_stack():
		return
	_test_direct_apply_stack()
	_test_direct_apply_mid_full()
	await _test_live_zoom_stack_hides_disk()
	await _test_live_zoom_mid_full_keep_disk()


func _test_policy() -> void:
	if LOD.unit_lod_band_name(STACK_Z) != "stack" or LOD.unit_lod_band_name(STACK_TOP_Z) != "stack":
		_fail("z=0.55/0.59 must be stack")
		return
	if LOD.unit_lod_band_name(MID_Z) != "mid":
		_fail("z=0.80 must be mid")
		return
	if LOD.unit_lod_band_name(FULL_Z) != "full":
		_fail("z=1.30 must be full")
		return
	var fleet_stack: Dictionary = LOD.unit_lod_policy(STACK_Z, false, true)
	if not bool(fleet_stack.get("fleet_anchor", false)):
		_fail("fleet at z=0.55 must request fleet_anchor")
		return
	if bool(fleet_stack.get("stack_chip", true)):
		_fail("fleet at z=0.55 must not use land stack_chip")
		return
	var fleet_mid: Dictionary = LOD.unit_lod_policy(MID_Z, false, true)
	if bool(fleet_mid.get("fleet_anchor", false)):
		_fail("fleet mid must not request fleet_anchor")
		return
	var fleet_full: Dictionary = LOD.unit_lod_policy(FULL_Z, false, true)
	if bool(fleet_full.get("fleet_anchor", false)):
		_fail("fleet full must not request fleet_anchor")
		return
	_pass("LOD policy: stack fleet_anchor; mid/full unchanged")


func _boot_sea_stack() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer missing")
		return false
	_mr = mr_script.new()
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(7196, 1337)
	_cam.zoom = Vector2(HOME_Z, HOME_Z)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_mr.set_process(false)
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	await _frames(2)
	if not _mr.has_method("_ensure_sea_nation_layer"):
		_fail("_ensure_sea_nation_layer missing")
		return false
	if not _mr.has_method("_attach_sea_nation_fleet_disk"):
		_fail("_attach_sea_nation_fleet_disk missing")
		return false
	var layer: Node2D = _mr.call("_ensure_sea_nation_layer") as Node2D
	if layer == null:
		_fail("SeaNationFleetLayer missing")
		return false
	_icons.clear()
	for i in TAGS.size():
		var tag: String = TAGS[i]
		var col: Color = TAG_COLORS[tag] as Color
		var icon := Node2D.new()
		icon.name = "DemoUnitIcon_%d_%s" % [NORTH_SEA, tag]
		icon.set_meta("sea_nation_disk", true)
		icon.set_meta("sea_nation_tag", tag)
		icon.set_meta("province_id", NORTH_SEA)
		icon.set_meta("eoa_stack_n", 1)
		icon.position = Vector2(float(i % 2) * 48.0 - 24.0, float(i / 2) * 44.0 - 22.0)
		layer.add_child(icon)
		_mr.call("_attach_unit_counter_chrome", icon, null, col)
		_mr.call("_attach_sea_nation_fleet_disk", icon, 14.5, col)
		_icons.append(icon)
	if _icons.size() != 4:
		_fail("need 4 North Sea nation markers, got %d" % _icons.size())
		return false
	for icon in _icons:
		var disk: Node = icon.get_node_or_null("SeaNationDisk")
		if disk == null:
			_fail("%s missing SeaNationDisk after attach" % icon.name)
			return false
		if disk is Polygon2D:
			var poly: PackedVector2Array = (disk as Polygon2D).polygon
			if poly.size() != 4:
				_fail("%s SeaNationDisk is not a rect (n=%d)" % [icon.name, poly.size()])
				return false
	_pass("North Sea fixture: 4 nation rects (GER/FRA/SOV/JAP)")
	return true


func _disk_visible(icon: Node2D) -> bool:
	var disk := icon.get_node_or_null("SeaNationDisk") as CanvasItem
	return disk != null and disk.visible


func _anchor_visible(icon: Node2D) -> bool:
	var anchor := icon.get_node_or_null("FleetAnchor") as CanvasItem
	return anchor != null and anchor.visible


func _count_visible_disks() -> int:
	var n := 0
	for icon in _icons:
		if _disk_visible(icon):
			n += 1
	return n


func _count_visible_anchors() -> int:
	var n := 0
	for icon in _icons:
		if _anchor_visible(icon):
			n += 1
	return n


func _apply_all(z: float) -> void:
	for icon in _icons:
		_mr.call("_apply_unit_lod_to_icon", icon, z, false, true)


func _test_direct_apply_stack() -> void:
	_apply_all(STACK_Z)
	var disks := _count_visible_disks()
	var anchors := _count_visible_anchors()
	_info_line("direct z=0.55 disks_vis=%d anchors_vis=%d" % [disks, anchors])
	if disks != 0:
		_fail("z=0.55 SeaNationDisk still visible on %d/4 North Sea markers" % disks)
	else:
		_pass("z=0.55 SeaNationDisk hidden on all 4 markers")
	if anchors != 4:
		_fail("z=0.55 FleetAnchor visible on %d/4 (want 4)" % anchors)
	else:
		_pass("z=0.55 FleetAnchor visible on all 4 markers")
	_apply_all(STACK_TOP_Z)
	disks = _count_visible_disks()
	if disks != 0:
		_fail("z=0.59 (stack top) SeaNationDisk still visible on %d/4" % disks)
	else:
		_pass("z=0.59 SeaNationDisk hidden")


func _test_direct_apply_mid_full() -> void:
	_apply_all(MID_Z)
	var disks := _count_visible_disks()
	var anchors := _count_visible_anchors()
	_info_line("direct z=0.80 disks_vis=%d anchors_vis=%d" % [disks, anchors])
	if disks != 4:
		_fail("mid z=0.80 SeaNationDisk visible on %d/4 (want 4; mid unchanged)" % disks)
	else:
		_pass("mid z=0.80 SeaNationDisk visible (unchanged)")
	if anchors != 0:
		_fail("mid z=0.80 FleetAnchor still visible on %d/4" % anchors)
	else:
		_pass("mid z=0.80 FleetAnchor hidden")
	_apply_all(FULL_Z)
	disks = _count_visible_disks()
	anchors = _count_visible_anchors()
	_info_line("direct z=1.30 disks_vis=%d anchors_vis=%d" % [disks, anchors])
	if disks != 4:
		_fail("full z=1.30 SeaNationDisk visible on %d/4 (want 4; full unchanged)" % disks)
	else:
		_pass("full z=1.30 SeaNationDisk visible (unchanged)")
	if anchors != 0:
		_fail("full z=1.30 FleetAnchor still visible on %d/4" % anchors)
	else:
		_pass("full z=1.30 FleetAnchor hidden")


func _live_zoom_to(z: float) -> void:
	_cam.zoom = Vector2(z, z)
	_cam.make_current()
	if _mr.has_method("_refresh_terrain_zoom_light"):
		_mr.call("_refresh_terrain_zoom_light")


func _test_live_zoom_stack_hides_disk() -> void:
	_apply_all(MID_Z)
	await _frames(1)
	_live_zoom_to(STACK_Z)
	await _frames(1)
	var disks := _count_visible_disks()
	var anchors := _count_visible_anchors()
	_info_line("live zoom z=0.55 disks_vis=%d anchors_vis=%d" % [disks, anchors])
	if disks != 0:
		_fail("live zoom z=0.55 SeaNationDisk still visible on %d/4" % disks)
	else:
		_pass("live zoom z=0.55 SeaNationDisk hidden")
	if anchors != 4:
		_fail("live zoom z=0.55 FleetAnchor visible on %d/4 (want 4)" % anchors)
	else:
		_pass("live zoom z=0.55 FleetAnchor visible")


func _test_live_zoom_mid_full_keep_disk() -> void:
	_live_zoom_to(MID_Z)
	await _frames(1)
	var disks := _count_visible_disks()
	if disks != 4:
		_fail("live zoom mid SeaNationDisk visible on %d/4 (want 4)" % disks)
	else:
		_pass("live zoom mid SeaNationDisk kept")
	_live_zoom_to(FULL_Z)
	await _frames(1)
	disks = _count_visible_disks()
	if disks != 4:
		_fail("live zoom full SeaNationDisk visible on %d/4 (want 4)" % disks)
	else:
		_pass("live zoom full SeaNationDisk kept")
