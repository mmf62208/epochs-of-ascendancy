extends SceneTree

## FIRST20-P2 F6 start-zoom LOD + F7 mapmode toggle/strip.
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     --resolution 1280x800 -s res://scripts/core/HeadlessFirst20P2Test.gd

const SIZES: Array[Vector2i] = [Vector2i(1024, 720), Vector2i(1280, 800), Vector2i(1920, 1080)]
const RIGHT_INSET := 8.0
const LOD := preload("res://scripts/map/MapZoomLOD.gd")
const SHOT_DIR := "res://docs/evidence/first20_p2"

var _failures: int = 0
var _mr: Node = null
var _tb: Control = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_lod_thresholds()
	await _test_lod_apply()
	await _test_f7_toggle_and_strip()
	await _shots()
	_finish()


func _finish() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	if _failures == 0:
		print("HeadlessFirst20P2Test: RESULT=PASS")
		quit(0)
	else:
		print("HeadlessFirst20P2Test: RESULT=FAIL failures=%d" % _failures)
		quit(1)


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL %s" % msg)


func _pass(msg: String) -> void:
	print("PASS %s" % msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _test_lod_thresholds() -> void:
	if LOD.unit_lod_band_name(0.39) != "stack" or LOD.unit_lod_band_name(0.59) != "stack":
		_fail("F6 z<0.6 must be stack")
		return
	if LOD.unit_lod_band_name(0.6) != "mid" or LOD.unit_lod_band_name(1.19) != "mid":
		_fail("F6 mid band")
		return
	if LOD.unit_lod_band_name(1.2) != "full":
		_fail("F6 z>=1.2 full")
		return
	var start_pol: Dictionary = LOD.unit_lod_policy(0.4)
	if str(start_pol.get("band", "")) != "stack" or bool(start_pol.get("show_bars", true)):
		_fail("F6 start policy %s" % str(start_pol))
		return
	if int(start_pol.get("chip_z", 28)) >= int(start_pol.get("label_z", 18)):
		_fail("F6 chips must sit under nation labels at start zoom")
		return
	var sel: Dictionary = LOD.unit_lod_policy(0.4, true, false)
	if str(sel.get("band", "")) != "full":
		_fail("F6 selected own must force full")
		return
	var fleet: Dictionary = LOD.unit_lod_policy(0.35, false, true)
	if not bool(fleet.get("fleet_anchor", false)):
		_fail("F6 fleet anchor at start zoom")
		return
	if not LOD.hide_default_unit_name(0.8, "Division 0"):
		_fail("F6 must hide Division 0 below 1.2")
		return
	if LOD.hide_default_unit_name(1.2, "Division 0"):
		_fail("F6 Division 0 may show at full")
		return
	if LOD.unit_lod_mid_letter("H") != "A" or LOD.unit_lod_mid_letter("G") != "I":
		_fail("F6 mid letter I/A/L")
		return
	_pass("F6 LOD thresholds")


func _test_lod_apply() -> void:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer missing")
		return
	_mr = mr_script.new()
	root.add_child(_mr)
	await _frames(2)
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_test"
	icon.set_meta("eoa_stack_n", 12)
	root.add_child(icon)
	_mr.call("_attach_unit_counter_chrome", icon, null, Color(0.35, 0.38, 0.42))
	_mr.call("_apply_unit_lod_to_icon", icon, 0.4, false, false)
	await _frames(1)
	var bars := icon.get_node_or_null("StatBars") as Node2D
	if bars != null and bars.visible:
		_fail("F6 start zoom still shows stat bars")
	var letter := icon.get_node_or_null("TypeLetter") as Node2D
	if letter != null and letter.visible:
		_fail("F6 start zoom still shows type letter")
	var count := icon.get_node_or_null("LodCount") as Node2D
	if count == null or not count.visible or str(count.get("text")) != "12":
		_fail("F6 start zoom missing stack count 12")
	else:
		_pass("F6 start zoom stack count 12")
	var plate := icon.get_node_or_null("NationPlate") as Polygon2D
	if plate == null or plate.polygon.size() < 4:
		_fail("F6 stack plate missing")
	else:
		var bb := plate.polygon[2] - plate.polygon[0]
		if absf(bb.x) < 20.0 or absf(bb.y) < 14.0:
			_fail("F6 stack plate size %s" % str(bb))
	_mr.call("_apply_unit_lod_to_icon", icon, 0.8, false, false)
	await _frames(1)
	letter = icon.get_node_or_null("TypeLetter") as Node2D
	if letter == null or not letter.visible:
		_fail("F6 mid band missing type letter")
	bars = icon.get_node_or_null("StatBars") as Node2D
	if bars != null and bars.visible:
		_fail("F6 mid band still shows bars")
	else:
		_pass("F6 mid letter / no bars")
	_mr.call("_apply_unit_lod_to_icon", icon, 1.3, false, false)
	await _frames(1)
	bars = icon.get_node_or_null("StatBars") as Node2D
	if bars == null or not bars.visible:
		_fail("F6 full band missing bars")
	var rdy: CanvasItem = null
	if bars != null:
		rdy = bars.get_node_or_null("RdyBar") as CanvasItem
	if rdy != null and rdy.visible:
		_fail("F6 full band still shows readiness bar")
	else:
		_pass("F6 full two-bar cap")
	icon.queue_free()


func _boot_toolbar() -> bool:
	if _mr == null or not is_instance_valid(_mr):
		var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
		_mr = mr_script.new()
		root.add_child(_mr)
		await _frames(2)
	if _mr.get_node_or_null("UI") == null:
		var ui := CanvasLayer.new()
		ui.name = "UI"
		_mr.add_child(ui)
		await _frames(1)
	if _mr.get("_map_mode_toolbar") == null and _mr.has_method("_setup_player_map_ux"):
		_mr.call("_setup_player_map_ux")
		await _frames(2)
	_tb = _mr.get("_map_mode_toolbar") as Control
	if _tb == null:
		_fail("MapModeToolbar missing")
		return false
	return true


func _set_size(sz: Vector2i) -> void:
	DisplayServer.window_set_size(sz)
	if root != null:
		root.size = sz
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.size = sz
	await _frames(2)


func _test_f7_toggle_and_strip() -> void:
	if not await _boot_toolbar():
		return
	_mr.set("current_map_mode", "political")
	_mr.set("_map_mode_hotkey_prior", "political")
	_mr.call("_toggle_map_mode_hotkey", "strain")
	if str(_mr.get("current_map_mode")) != "strain":
		_fail("F7 F2 did not enter strain (now %s)" % str(_mr.get("current_map_mode")))
	else:
		_pass("F7 F2 enters strain")
	_mr.call("_toggle_map_mode_hotkey", "strain")
	if str(_mr.get("current_map_mode")) != "political":
		_fail("F7 F2 did not return to political (now %s)" % str(_mr.get("current_map_mode")))
	else:
		_pass("F7 F2 returns to political")
	_mr.call("_toggle_map_mode_hotkey", "vitality")
	_mr.call("_toggle_map_mode_hotkey", "vitality")
	if str(_mr.get("current_map_mode")) != "political":
		_fail("F7 F3 toggle prior (now %s)" % str(_mr.get("current_map_mode")))
	else:
		_pass("F7 F3 toggles prior")
	if _tb.find_child("MoreOverflow", true, false) == null:
		# More may be absent if every chip fit; still require the pack helper.
		var src := FileAccess.get_file_as_string("res://scripts/ui/map/MapModeToolbar.gd")
		if "More ▾" not in src:
			_fail("F7 More menu missing from toolbar source")
	var ix := _find_label_text(_tb, "Intensity")
	if ix == null:
		_mr.call("set_map_mode", "strain")
		await _frames(2)
		ix = _find_label_text(_tb, "Intensity")
	if ix == null:
		_fail("F7 Intensity caption missing on strain")
	else:
		_pass("F7 Intensity caption")
	for lab in ["Low", "Med", "High", "Max"]:
		if _find_button_text(_tb, lab) == null:
			_fail("F7 intensity button %s missing" % lab)
	if _find_button_text(_tb, "Low") != null:
		_pass("F7 Low/Med/High/Max")
	for sz in SIZES:
		await _set_size(sz)
		if _mr.has_method("_layout_map_ui"):
			_mr.call("_layout_map_ui")
		if _tb.has_method("relayout_overflow"):
			_tb.call("relayout_overflow")
		await _frames(3)
		var limit := float(sz.x) - RIGHT_INSET
		var right := 0.0
		if _tb.has_method("get_strip_right_edge"):
			right = float(_tb.call("get_strip_right_edge"))
		else:
			right = _tb.get_global_rect().end.x
		if right > limit + 0.5:
			_fail("F7 strip right edge %.1f > %.1f at %s" % [right, limit, str(sz)])
		else:
			_pass("F7 strip right %.1f <= %.1f at %s" % [right, limit, str(sz)])
	_mr.call("set_map_mode", "strain")
	await _frames(1)
	var buttons2: Dictionary = _tb.get("_buttons")
	var sb: Button = buttons2.get("strain") as Button if buttons2 != null else null
	if sb != null:
		var fill := sb.get_theme_stylebox("normal") as StyleBoxFlat
		if fill == null or not fill.bg_color.is_equal_approx(RetrowaveTheme.CYAN):
			_fail("F7 active chip is not CYAN fill")
		else:
			_pass("F7 active CYAN fill")
	else:
		_fail("F7 strain chip missing")


func _find_label_text(n: Node, text: String) -> Label:
	if n is Label and (n as Label).text == text:
		return n as Label
	for c in n.get_children():
		var hit := _find_label_text(c, text)
		if hit != null:
			return hit
	return null


func _find_button_text(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n as Button
	for c in n.get_children():
		var hit := _find_button_text(c, text)
		if hit != null:
			return hit
	return null


func _shots() -> void:
	# Best-effort grab. Do not await frame_post_draw — headless can hang there.
	# Committed evidence is the PIL stills under docs/evidence/first20_p2/.
	await _frames(2)
	var dir := ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var vp := root.get_viewport()
	if vp == null:
		print("INFO no viewport for shots")
		return
	var tex := vp.get_texture()
	if tex == null:
		print("INFO no texture for shots")
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		print("INFO empty shot")
		return
	img.save_png(dir.path_join("after_toolbar_live.png"))
	print("INFO shot %s/after_toolbar_live.png" % dir)
