extends SceneTree

## LABEL-1: country names stay proportionate and crisp at Europe / mid / close.
## Asserts effective font_px * zoom / viewport_h is in-band and is not a
## magnified Label.scale / low-res raster. City-label LOD (Köln/Bonn/Leverkusen)
## must still show at mid/close. Does not load WorldMap.tscn / 3520.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x720 \
##     -s res://scripts/core/HeadlessLabel1NationZoomTest.gd

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")
const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")

const PLAY_SIZE := Vector2i(1280, 720)
const EUROPE_Z := 0.40
const MID_Z := 0.776
const CLOSE_Z := 1.80
const EUROPE_RATIO_LO := 0.018
const EUROPE_RATIO_HI := 0.045
const MID_RATIO_LO := 0.016
const MID_RATIO_HI := 0.038
const CLOSE_RATIO_HI := 0.012

var _failures: int = 0
var _layer: Node = null
var _cam: Camera2D = null
var _shot_dir: String = "user://label1"
var _ger_label: Label = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessLabel1NationZoomTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessLabel1NationZoomTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessLabel1NationZoomTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessLabel1NationZoomTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessLabel1NationZoomTest: ", msg)


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	root.size = PLAY_SIZE
	_shot_dir = _resolve_shot_dir()
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_add_backdrop()
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(4200, 1600)
	_cam.zoom = Vector2(EUROPE_Z, EUROPE_Z)
	root.add_child(_cam)
	_cam.make_current()
	await process_frame
	var booted: bool = await _boot_label_layer()
	if not booted:
		return
	_assert_policy_tables()
	_assert_city_label_lod()
	await _measure_and_snapshot("europe", EUROPE_Z, EUROPE_RATIO_LO, EUROPE_RATIO_HI, false)
	await _measure_and_snapshot("mid", MID_Z, MID_RATIO_LO, MID_RATIO_HI, false)
	await _measure_and_snapshot("close", CLOSE_Z, 0.0, CLOSE_RATIO_HI, true)
	_assert_no_node_scale()
	_assert_layer_fences()


func _boot_label_layer() -> bool:
	var scr: Script = load("res://scripts/map/MapPoliticalLabelsLayer.gd") as Script
	if scr == null:
		_fail("MapPoliticalLabelsLayer.gd failed to load")
		return false
	var inst: Object = scr.new()
	if inst == null or not (inst is Node2D):
		_fail("MapPoliticalLabelsLayer.new() failed (autoload parse?)")
		return false
	_layer = inst as Node2D
	_layer.name = "PoliticalLabelsLayer"
	root.add_child(_layer)
	await process_frame
	if _layer.has_method("seed_debug_nation_label"):
		_ger_label = _layer.call("seed_debug_nation_label", "GER", "Germany", Vector2(4200, 1580), 28) as Label
		_layer.call("seed_debug_nation_label", "FRA", "France", Vector2(4000, 1720), 24)
		_layer.call("seed_debug_nation_label", "NLD", "Netherlands", Vector2(4280, 1500), 17)
	else:
		_fail("seed_debug_nation_label missing")
		return false
	if _ger_label == null or not is_instance_valid(_ger_label):
		_fail("GER nation label was not created")
		return false
	_pass("seeded GER/FRA/NLD nation labels")
	return true


func _add_backdrop() -> void:
	var ger := Polygon2D.new()
	ger.name = "GERFill"
	ger.polygon = PackedVector2Array([
		Vector2(3600, 1300), Vector2(4600, 1300), Vector2(4600, 1900), Vector2(3600, 1900)
	])
	ger.color = Color(0.62, 0.22, 0.22, 1.0)
	ger.z_as_relative = false
	ger.z_index = 1
	root.add_child(ger)
	var fra := Polygon2D.new()
	fra.name = "FRAFill"
	fra.polygon = PackedVector2Array([
		Vector2(3000, 1650), Vector2(4000, 1650), Vector2(4000, 2150), Vector2(3000, 2150)
	])
	fra.color = Color(0.22, 0.32, 0.58, 1.0)
	fra.z_as_relative = false
	fra.z_index = 1
	root.add_child(fra)


func _resolve_shot_dir() -> String:
	var env_dir := str(OS.get_environment("EOA_LABEL1_OUT")).strip_edges()
	if not env_dir.is_empty():
		return env_dir
	var art := "/opt/cursor/artifacts/label1"
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		return art
	return ProjectSettings.globalize_path("user://label1")


func _assert_policy_tables() -> void:
	var vh := 720.0
	var eu_px: int = MapZoomLODScript.nation_label_font_px_for_camera(EUROPE_Z, vh)
	var mid_px: int = MapZoomLODScript.nation_label_font_px_for_camera(MID_Z, vh)
	var close_px: int = MapZoomLODScript.nation_label_font_px_for_camera(CLOSE_Z, vh)
	if eu_px <= 0 or mid_px <= 0:
		_fail("policy font europe=%d mid=%d" % [eu_px, mid_px])
	else:
		_pass("policy font europe=%d mid=%d" % [eu_px, mid_px])
	if close_px != 0:
		_fail("close policy font=%d want 0" % close_px)
	else:
		_pass("close policy hides nation font")
	if MapZoomLODScript.nation_label_is_texture_magnified(mid_px, MID_Z, 1.0):
		_fail("policy mid marked magnified at scale=1")
	else:
		_pass("policy mid scale=1 is not magnified")
	if not MapZoomLODScript.nation_label_is_texture_magnified(20, MID_Z, 2.5):
		_fail("policy missed scale=2.5 magnification")
	else:
		_pass("policy flags node.scale magnification")
	var mid_eff: float = MapZoomLODScript.nation_label_effective_screen_px(mid_px, MID_Z, 1.0)
	if mid_eff > float(mid_px) + 0.75:
		_fail("mid effective %.1f > font %d" % [mid_eff, mid_px])
	else:
		_pass("mid effective %.1fpx from font %d (not a blown-up texture)" % [mid_eff, mid_px])


func _assert_city_label_lod() -> void:
	if not RoadTierVisualScript.end_labels_visible_at_zoom(1.80):
		_fail("city labels hidden at close/mid 1.80")
	else:
		_pass("city labels visible at 1.80 (Köln/Bonn/Leverkusen)")
	if not RoadTierVisualScript.end_labels_visible_at_zoom(1.50):
		_fail("city labels must show at zoom 1.50")
	else:
		_pass("city labels show at 1.50")
	if RoadTierVisualScript.end_labels_visible_at_zoom(EUROPE_Z):
		_fail("city labels must stay off at Europe Home")
	else:
		_pass("city labels hidden at Europe Home")
	if RoadTierVisualScript.END_LABEL_ZOOM_MIN < 1.49:
		_fail("END_LABEL_ZOOM_MIN=%.2f" % RoadTierVisualScript.END_LABEL_ZOOM_MIN)
	else:
		_pass("city label floor 1.50 kept")


func _metrics_for(z: float) -> Dictionary:
	if _layer != null and _layer.has_method("nation_label_debug_metrics"):
		var live: Dictionary = _layer.call("nation_label_debug_metrics", "GER") as Dictionary
		if not live.is_empty():
			return live
	var font_px: int = 0
	var node_scale := 1.0
	var visible := false
	if _ger_label != null and is_instance_valid(_ger_label):
		visible = _ger_label.visible
		node_scale = maxf(_ger_label.scale.x, _ger_label.scale.y)
		if visible:
			font_px = int(_ger_label.get_theme_font_size("font_size"))
	var vh := 720.0
	return {
		"zoom": z,
		"viewport_h": vh,
		"font_px": font_px,
		"node_scale": node_scale,
		"effective_screen_px": MapZoomLODScript.nation_label_effective_screen_px(font_px, z, node_scale),
		"height_ratio": MapZoomLODScript.nation_label_height_ratio(font_px, z, node_scale, vh),
		"texture_magnified": MapZoomLODScript.nation_label_is_texture_magnified(font_px, z, node_scale),
		"visible": visible,
	}


func _measure_and_snapshot(name_s: String, z: float, lo: float, hi: float, must_hide: bool) -> void:
	_cam.zoom = Vector2(z, z)
	if _layer != null and _layer.has_method("sync_camera_zoom"):
		_layer.call("sync_camera_zoom", z)
	await process_frame
	await process_frame
	var m: Dictionary = _metrics_for(z)
	var font_px := int(m.get("font_px", -1))
	var node_scale := float(m.get("node_scale", 0.0))
	var ratio := float(m.get("height_ratio", -1.0))
	var magnified := bool(m.get("texture_magnified", true))
	var visible := bool(m.get("visible", false))
	var effective := float(m.get("effective_screen_px", -1.0))
	_info(
		"%s z=%.3f font=%d scale=%.3f screen=%.1f ratio=%.4f vis=%s mag=%s"
		% [name_s, z, font_px, node_scale, effective, ratio, str(visible), str(magnified)]
	)
	if absf(node_scale - 1.0) > 0.02:
		_fail("%s node_scale=%.3f (must be 1 — no texture magnify)" % [name_s, node_scale])
	else:
		_pass("%s node_scale=1" % name_s)
	if magnified:
		_fail("%s produced by magnifying a texture" % name_s)
	else:
		_pass("%s not texture-magnified" % name_s)
	if must_hide:
		if visible or font_px > 0:
			_fail("%s nation label still up font=%d vis=%s" % [name_s, font_px, str(visible)])
		elif ratio > hi:
			_fail("%s hidden ratio=%.4f" % [name_s, ratio])
		else:
			_pass("%s nation labels hidden (city names own this band)" % name_s)
	else:
		if (not visible) or font_px <= 0:
			_fail("%s nation label missing font=%d vis=%s" % [name_s, font_px, str(visible)])
		elif ratio < lo or ratio > hi:
			_fail("%s height_ratio=%.4f want %.3f..%.3f" % [name_s, ratio, lo, hi])
		else:
			_pass("%s height_ratio=%.4f in band" % [name_s, ratio])
		if effective > float(font_px) + 0.75:
			_fail("%s effective %.1f > font %d (magnified raster)" % [name_s, effective, font_px])
	_capture_shot(name_s, z)


func _capture_shot(name_s: String, z: float) -> void:
	if str(DisplayServer.get_name()).to_lower().contains("headless"):
		_info("shot skip (headless) %s z=%.3f" % [name_s, z])
		return
	var vp := root.get_viewport()
	if vp == null:
		return
	await process_frame
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		_info("shot skip (headless dummy viewport) %s" % name_s)
		return
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 8:
		_info("shot skip (no image) %s" % name_s)
		return
	var path := "%s/label1_%s_z%.3f.png" % [_shot_dir, name_s, z]
	var err := img.save_png(path)
	if err == OK:
		_info("shot %s" % path)
	else:
		_info("shot skip err=%d path=%s" % [err, path])


func _assert_no_node_scale() -> void:
	if _ger_label == null or not is_instance_valid(_ger_label):
		_fail("NationLabel_GER missing")
		return
	if _ger_label.scale != Vector2.ONE:
		_fail("GER scale=%s" % str(_ger_label.scale))
	else:
		_pass("GER Label.scale is identity")
	if _layer != null and _layer is Node2D and (_layer as Node2D).scale != Vector2.ONE:
		_fail("layer scale=%s" % str((_layer as Node2D).scale))
	else:
		_pass("PoliticalLabelsLayer scale is identity")


func _assert_layer_fences() -> void:
	var src := ""
	if FileAccess.file_exists("res://scripts/map/MapPoliticalLabelsLayer.gd"):
		var f := FileAccess.open("res://scripts/map/MapPoliticalLabelsLayer.gd", FileAccess.READ)
		if f != null:
			src = f.get_as_text()
			f.close()
	if "FacilityIconLayer" in src or "TipDismiss" in src or "_try_open_land" in src:
		_fail("label layer crossed pick/tip/facility fences")
	else:
		_pass("label layer fences intact")
	if "PROCESS_MODE_ALWAYS" not in src or "Vector2.ONE" not in src:
		_fail("live zoom / identity-scale wiring missing")
	else:
		_pass("paused-session zoom tracking + identity scale")
