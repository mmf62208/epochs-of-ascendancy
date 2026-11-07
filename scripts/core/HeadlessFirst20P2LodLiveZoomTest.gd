extends SceneTree

## FIRST20-P2 F6 live LOD band switch.
## Card type at z=0.583 (stack) vs z=1.391 (full) after a live zoom change
## through `_refresh_terrain_zoom_light` (Play wheel path), not a first apply.
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     --resolution 1280x800 -s res://scripts/core/HeadlessFirst20P2LodLiveZoomTest.gd
##
## Must FAIL on 495ee5ee (both zooms stay chip+letter) and PASS after the
## light-path LOD fix.

const PID := 710173
const HOME_Z := 0.787
const STACK_Z := 0.583
const FULL_Z := 1.391
const LOD := preload("res://scripts/map/MapZoomLOD.gd")

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _icon: Node2D = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_live_zoom_card_type()
	_finish()


func _finish() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	if _failures == 0:
		print("HeadlessFirst20P2LodLiveZoomTest: RESULT=PASS")
		quit(0)
	else:
		print("HeadlessFirst20P2LodLiveZoomTest: RESULT=FAIL failures=%d" % _failures)
		quit(1)


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL %s" % msg)


func _pass(msg: String) -> void:
	print("PASS %s" % msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _card_kind(icon: Node2D) -> String:
	if icon == null:
		return "missing"
	var bars := icon.get_node_or_null("StatBars") as Node2D
	var letter := icon.get_node_or_null("TypeLetter") as Node2D
	var count := icon.get_node_or_null("LodCount") as Node2D
	var bars_on := bars != null and bars.visible
	var letter_on := letter != null and letter.visible
	var count_on := count != null and count.visible
	if count_on and not letter_on and not bars_on:
		return "stack"
	if letter_on and bars_on:
		var org := bars.get_node_or_null("OrgBar") if bars != null else null
		var strb := bars.get_node_or_null("StrBar") if bars != null else null
		if org != null and strb != null:
			return "full"
		return "full_incomplete"
	if letter_on and not bars_on:
		return "mid"
	return "other letter=%s bars=%s count=%s" % [str(letter_on), str(bars_on), str(count_on)]


func _live_zoom_to(z: float) -> String:
	if _cam == null or _mr == null:
		return "missing"
	_cam.zoom = Vector2(z, z)
	_cam.make_current()
	await _frames(1)
	# Play wheel path: camera already at z, then light LOD (not _apply_unit_lod_to_icon).
	if _mr.has_method("_refresh_terrain_zoom_light"):
		_mr.call("_refresh_terrain_zoom_light")
	await _frames(1)
	var kind := _card_kind(_icon)
	var cam_z := maxf(_cam.zoom.x, _cam.zoom.y)
	print(
		"LIVE_LOD z=%.3f cam=%.3f band=%s kind=%s"
		% [z, cam_z, LOD.unit_lod_band_name(cam_z), kind]
	)
	return kind


func _boot() -> bool:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if root != null:
		root.size = Vector2i(1280, 800)
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
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(4200, 1000)
	_cam.zoom = Vector2(HOME_Z, HOME_Z)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	# Play F5 is paused: `_process` skips `_refresh_province_detail_visibility`,
	# so wheel zoom only hits `_refresh_terrain_zoom_light`. Isolate that path.
	_mr.set_process(false)
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	await _frames(2)
	var host := Node2D.new()
	host.name = "Province_%d" % PID
	container.add_child(host)
	_icon = Node2D.new()
	_icon.name = "DemoUnitIcon_%d" % PID
	_icon.set_meta("eoa_stack_n", 4)
	_icon.set_meta("province_id", PID)
	host.add_child(_icon)
	if "province_nodes" in _mr:
		_mr.province_nodes[PID] = host
	if "_demo_unit_icon_pids" in _mr:
		_mr._demo_unit_icon_pids = [PID]
	_mr.call("_attach_unit_counter_chrome", _icon, null, Color(0.35, 0.38, 0.42))
	# Simulate Home placement (Play 1280x800 Home is z=0.787 → mid chip+letter).
	_mr.call("_apply_unit_lod_to_icon", _icon, HOME_Z, false, false)
	await _frames(1)
	var home_kind := _card_kind(_icon)
	print("LIVE_LOD home z=%.3f kind=%s" % [HOME_Z, home_kind])
	if home_kind != "mid":
		_fail("home placement should be mid chip+letter, got %s" % home_kind)
		return false
	_pass("home placement mid chip+letter")
	return true


func _test_live_zoom_card_type() -> void:
	if not await _boot():
		return
	var want_stack := LOD.unit_lod_band_name(STACK_Z)
	var want_full := LOD.unit_lod_band_name(FULL_Z)
	if want_stack != "stack" or want_full != "full":
		_fail("policy z=0.583=%s z=1.391=%s" % [want_stack, want_full])
		return
	var at_stack: String = await _live_zoom_to(STACK_Z)
	var at_full: String = await _live_zoom_to(FULL_Z)
	if at_stack == at_full:
		_fail(
			"live zoom kept the same card kind %s at z=0.583 and z=1.391 (want stack vs full)"
			% at_stack
		)
		return
	if at_stack != "stack":
		_fail("z=0.583 after live zoom kind=%s want stack (22x16 count-only)" % at_stack)
	else:
		_pass("z=0.583 live → stack count-only")
	if at_full != "full":
		_fail("z=1.391 after live zoom kind=%s want full (OrgBar+StrBar)" % at_full)
	else:
		_pass("z=1.391 live → full OrgBar+StrBar")
	# Cross the bands the other way too (full → stack), still via the live path.
	var back: String = await _live_zoom_to(STACK_Z)
	if back != "stack":
		_fail("live zoom back to 0.583 kind=%s want stack" % back)
	else:
		_pass("live zoom full→stack")
