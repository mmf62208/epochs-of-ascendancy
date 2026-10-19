extends SceneTree

## ROADS-1 UI: Supply legend must sit below Map Mode chips at 1280x800
## (and wider). Political / terrain hints must mention highways live
## only in Supply/Infra.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessRoads1SupplyLegendLayoutTest.gd

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TB := "res://scripts/ui/map/MapModeToolbar.gd"
const PLAY_SIZE := Vector2i(1280, 800)
const WIDE_SIZE := Vector2i(1600, 900)
const FLUSH_FRAMES := 4

var _failures: int = 0
var _mr: Node = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok: bool = _failures == 0
	print("HeadlessRoads1SupplyLegendLayoutTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRoads1SupplyLegendLayoutTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRoads1SupplyLegendLayoutTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRoads1SupplyLegendLayoutTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessRoads1SupplyLegendLayoutTest: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt := src.find("\nfunc ", i + needle.length())
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	_test_source_layout_and_hints()
	if not await _boot_renderer():
		return
	await _assert_no_overlap_at(PLAY_SIZE)
	await _assert_no_overlap_at(WIDE_SIZE)
	_test_highway_hint_live()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()


func _test_source_layout_and_hints() -> void:
	var ren: String = _read(SRC_REN)
	var tb: String = _read(SRC_TB)
	if ren.is_empty() or tb.is_empty():
		_fail("MapRenderer / MapModeToolbar source missing")
		return
	var layout_ui: String = _slice_func(ren, "_layout_map_ui")
	var layout_leg: String = _slice_func(ren, "_layout_supply_legend")
	var update_leg: String = _slice_func(ren, "_update_supply_overlay_legend")
	if "func _layout_supply_legend" not in ren:
		_fail("MapRenderer must layout the Supply legend off the mode chips")
		return
	if "_layout_supply_legend()" not in layout_ui:
		_fail("_layout_map_ui must call _layout_supply_legend")
		return
	if "_layout_supply_legend()" not in update_leg:
		_fail("_update_supply_overlay_legend must call _layout_supply_legend")
		return
	if "chrome_top" not in layout_leg or "offset_top = chrome_top" not in layout_leg:
		_fail("Supply legend must sit at chrome_top (below Map Mode)")
		return
	if "offset_top = 56" in update_leg or "offset_top = 56.0" in update_leg:
		_fail("Supply legend must not pin at y=56 over the mode chips")
		return
	if "Highways: Supply/Infra view" not in tb:
		_fail("MapModeToolbar must hint that highways live in Supply/Infra view")
		return
	var hints: String = _slice_const_block(tb, "MODE_HINTS")
	if hints.is_empty():
		_fail("MODE_HINTS block missing")
		return
	if '"political": "Clean country colors (default) · Highways: Supply/Infra view"' not in hints:
		_fail("Political mode tooltip must mention Highways: Supply/Infra view")
		return
	if "Highways: Supply/Infra view" not in hints or '"terrain":' not in hints:
		_fail("Terrain mode tooltip must mention Highways: Supply/Infra view")
		return
	var ter_i: int = hints.find('"terrain":')
	var ter: String = hints.substr(ter_i, 220) if ter_i >= 0 else ""
	if "Highways: Supply/Infra view" not in ter:
		_fail("Terrain mode tooltip must mention Highways: Supply/Infra view")
		return
	_pass("source: legend under chrome_top + highway hint on political/terrain")


func _slice_const_block(src: String, name: String) -> String:
	var needle := "const %s" % name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt := src.find("\nconst ", i + needle.length())
	if nxt < 0:
		nxt = src.find("\nvar ", i + needle.length())
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _set_window_size(wh: Vector2i) -> void:
	DisplayServer.window_set_size(wh)
	if root != null:
		root.size = wh
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.size = wh


func _boot_renderer() -> bool:
	_set_window_size(PLAY_SIZE)
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	_mr.add_child(cam)
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	_mr.container = container
	root.add_child(_mr)
	cam.make_current()
	await _flush()
	if _mr.get("_map_mode_toolbar") == null:
		_mr.call("_setup_player_map_ux")
		await _flush()
	if _mr.get("_map_mode_toolbar") == null:
		_fail("MapModeToolbar was not created")
		return false
	_mr.call("_update_supply_overlay_legend")
	_mr.call("_set_supply_legend_visible", true)
	_mr.call("_layout_map_ui")
	await _flush()
	if _mr.get("_supply_legend_panel") == null:
		_fail("SupplyOverlayLegend was not created")
		return false
	_pass("booted MapRenderer + toolbar + Supply legend")
	return true


func _legend_rect() -> Rect2:
	var panel: Control = _mr.get("_supply_legend_panel") as Control
	if panel == null or not panel.is_visible_in_tree():
		return Rect2()
	return panel.get_global_rect()


func _mode_buttons() -> Array:
	var out: Array = []
	var tb: Node = _mr.get("_map_mode_toolbar") as Node
	if tb == null:
		return out
	var buttons = tb.get("_buttons")
	if buttons is Dictionary:
		for mode_v in (buttons as Dictionary).keys():
			var btn: Button = (buttons as Dictionary).get(mode_v) as Button
			if btn != null:
				out.append(btn)
	return out


func _assert_no_overlap_at(wh: Vector2i) -> void:
	_set_window_size(wh)
	_mr.call("_layout_map_ui")
	await _flush()
	var legend: Rect2 = _legend_rect()
	if legend.size.x < 8.0 or legend.size.y < 8.0:
		_fail("Supply legend rect is empty at %dx%d (%s)" % [wh.x, wh.y, str(legend)])
		return
	var buttons: Array = _mode_buttons()
	if buttons.is_empty():
		_fail("no Map Mode buttons found at %dx%d" % [wh.x, wh.y])
		return
	var overlaps: int = 0
	for btn_v in buttons:
		var btn: Button = btn_v as Button
		if btn == null or not btn.is_visible_in_tree():
			continue
		var br: Rect2 = btn.get_global_rect()
		if br.size.x < 1.0 or br.size.y < 1.0:
			continue
		if legend.intersects(br):
			overlaps += 1
			_fail(
				"legend %s overlaps mode '%s' %s at %dx%d"
				% [str(legend), btn.text, str(br), wh.x, wh.y]
			)
	if overlaps == 0:
		_pass(
			"legend %s misses %d mode buttons at %dx%d"
			% [str(legend), buttons.size(), wh.x, wh.y]
		)


func _test_highway_hint_live() -> void:
	var tb: Node = _mr.get("_map_mode_toolbar") as Node
	if tb == null:
		_fail("toolbar missing for highway hint")
		return
	var hints = tb.get("MODE_HINTS")
	if not (hints is Dictionary):
		_fail("MODE_HINTS missing")
		return
	var pol: String = str((hints as Dictionary).get("political", ""))
	var ter: String = str((hints as Dictionary).get("terrain", ""))
	if "Highways: Supply/Infra view" not in pol or "Highways: Supply/Infra view" not in ter:
		_fail("live MODE_HINTS political/terrain missing highway note")
		return
	var buttons = tb.get("_buttons")
	if buttons is Dictionary:
		var pol_btn: Button = (buttons as Dictionary).get("political") as Button
		var ter_btn: Button = (buttons as Dictionary).get("terrain") as Button
		if pol_btn == null or "Highways: Supply/Infra view" not in pol_btn.tooltip_text:
			_fail("Political chip tooltip must mention Highways: Supply/Infra view")
			return
		if ter_btn == null or "Highways: Supply/Infra view" not in ter_btn.tooltip_text:
			_fail("Terrain chip tooltip must mention Highways: Supply/Infra view")
			return
	var legend: Label = tb.get("_legend") as Label
	if legend != null and "Highways: Supply/Infra view" not in legend.text:
		_fail("Map Mode one-line note must mention Highways: Supply/Infra view")
		return
	_pass("political/terrain tooltips + one-line note mention highways")
