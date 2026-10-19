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
	await _assert_legend_height_and_minimap(PLAY_SIZE)
	await _assert_legend_height_and_minimap_at_war(PLAY_SIZE)
	_test_toolbar_highlight_tracks_mode()
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
	if "chrome_top" not in layout_leg:
		_fail("Supply legend must sit at chrome_top (below Map Mode)")
		return
	if "offset_top = chrome_top" not in layout_leg and "chrome_top, sz" not in layout_leg:
		_fail("Supply legend must pin offset_top to chrome_top (below Map Mode)")
		return
	if "200" not in layout_leg and "_supply_legend_content_size" not in layout_leg:
		_fail("Supply legend must cap height to content (~200)")
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
	if "Clean country colors (default) · Highways: Supply/Infra view" not in hints:
		_fail("Political mode tooltip must mention Highways: Supply/Infra view")
		return
	if "Toggle highways: L" not in hints:
		_fail("MODE_HINTS must mention Toggle highways: L")
		return
	if "Highways: Supply/Infra view" not in hints or '"terrain":' not in hints:
		_fail("Terrain mode tooltip must mention Highways: Supply/Infra view")
		return
	var ter_i: int = hints.find('"terrain":')
	var ter: String = hints.substr(ter_i, 280) if ter_i >= 0 else ""
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
	if legend.size.y > 200.0:
		_fail("legend height %.1f > 200 at %dx%d" % [legend.size.y, wh.x, wh.y])


func _minimap_rect() -> Rect2:
	var mm: Control = _mr.get("_map_minimap") as Control
	if mm == null or not mm.is_visible_in_tree():
		return Rect2()
	return mm.get_global_rect()


func _assert_legend_fits(wh: Vector2i, label: String) -> void:
	var legend: Rect2 = _legend_rect()
	if legend.size.x < 8.0 or legend.size.y < 8.0:
		_fail("%s legend rect is empty at %dx%d (%s)" % [label, wh.x, wh.y, str(legend)])
		return
	if legend.size.y > 200.0:
		_fail("%s legend height %.1f > 200 at %dx%d (%s)" % [label, legend.size.y, wh.x, wh.y, str(legend)])
		return
	var mm: Rect2 = _minimap_rect()
	if mm.size.x >= 8.0 and mm.size.y >= 8.0 and legend.intersects(mm):
		_fail("%s legend %s overlaps minimap %s at %dx%d" % [label, str(legend), str(mm), wh.x, wh.y])
		return
	_pass("%s legend %s height<=200 and misses minimap at %dx%d" % [label, str(legend), wh.x, wh.y])


func _assert_legend_height_and_minimap(wh: Vector2i) -> void:
	_set_window_size(wh)
	_mr.call("_layout_map_ui")
	await _flush()
	_assert_legend_fits(wh, "peace")


func _assert_legend_height_and_minimap_at_war(wh: Vector2i) -> void:
	_set_window_size(wh)
	var stub := Control.new()
	stub.name = "TopInfoBarWarStub"
	stub.add_to_group("top_info_bar")
	var gs := GDScript.new()
	gs.source_code = """
extends Control
func get_bar_height() -> float:
	return 72.0
"""
	if gs.reload() != OK:
		_fail("war TopInfoBar stub failed to parse")
		stub.queue_free()
		return
	stub.set_script(gs)
	stub.size = Vector2(1280, 72)
	root.add_child(stub)
	_mr.call("_layout_map_ui")
	await _flush()
	_assert_legend_fits(wh, "war")
	stub.queue_free()


func _test_toolbar_highlight_tracks_mode() -> void:
	var tb: Node = _mr.get("_map_mode_toolbar") as Node
	if tb == null or not tb.has_method("get_current_mode"):
		_fail("toolbar missing get_current_mode")
		return
	_mr.set("current_map_mode", "supply")
	_mr.set("supply_mode", true)
	_mr.call("_set_supply_legend_visible", true)
	_mr.call("_sync_mapmode_toolbar")
	if str(tb.call("get_current_mode")) != "supply":
		_fail("legend-open Supply must highlight Supply (got %s)" % str(tb.call("get_current_mode")))
		return
	_mr.set("current_map_mode", "infra")
	_mr.call("_sync_mapmode_toolbar")
	if str(tb.call("get_current_mode")) != "infra":
		_fail("legend-open Infra must highlight Infra (got %s)" % str(tb.call("get_current_mode")))
		return
	_mr.set("current_map_mode", "political")
	_mr.set("supply_mode", true)
	_mr.call("_sync_mapmode_toolbar")
	if str(tb.call("get_current_mode")) != "supply":
		_fail("L-on political must highlight Supply (got %s)" % str(tb.call("get_current_mode")))
		return
	var buttons = tb.get("_buttons")
	if buttons is Dictionary:
		var sup: Button = (buttons as Dictionary).get("supply") as Button
		var pol: Button = (buttons as Dictionary).get("political") as Button
		if sup == null or not sup.button_pressed:
			_fail("Supply chip must be pressed while legend is open from L")
			return
		if pol != null and pol.button_pressed:
			_fail("Political chip must not stay pressed while legend is open")
			return
	_pass("toolbar highlight tracks Supply/Infra while legend is open")


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
	if "Toggle highways: L" not in pol or "Toggle highways: L" not in ter:
		_fail("live MODE_HINTS political/terrain missing Toggle highways: L")
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
