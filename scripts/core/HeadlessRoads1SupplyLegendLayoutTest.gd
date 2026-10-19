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
var _top_bar: Control = null
var _war: GDScript = null


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
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
	if not await _boot_top_bar():
		return
	_fill_live_legend_text()
	await _flush()
	await _assert_no_overlap_at(PLAY_SIZE)
	await _assert_no_overlap_at(WIDE_SIZE)
	await _assert_legend_height_and_minimap(PLAY_SIZE)
	await _assert_legend_height_and_minimap_at_war(PLAY_SIZE)
	_test_toolbar_highlight_tracks_mode()
	_test_mode_chip_toggled_while_legend_open()
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
	if "200" not in layout_leg and "_supply_legend_host_size" not in layout_leg and "SUPPLY_LEGEND_HOST_SIZE" not in layout_leg:
		_fail("Supply legend must use a fixed ~200 px host")
		return
	if "get_content_height" in layout_leg or "get_combined_minimum_size" in layout_leg:
		_fail("Supply legend host size must not come from content")
		return
	var host_sz: String = _slice_func(ren, "_supply_legend_host_size")
	if "get_content_height" in host_sz or "get_combined_minimum_size" in host_sz:
		_fail("_supply_legend_host_size must return a fixed size, not content height")
		return
	var frame_fn: String = _slice_func(ren, "_apply_supply_legend_fixed_frame")
	if "fit_content = false" not in frame_fn or "scroll_active = true" not in frame_fn:
		_fail("legend RTL must scroll inside a fixed height (fit_content off, scroll_active on)")
		return
	if "clip_contents = true" not in frame_fn:
		_fail("legend panel/host must clip_contents so the visible rect stays 200 px")
		return
	if "fit_content = true" in update_leg and "fit_content = false" not in update_leg:
		_fail("Supply overlay legend must not enable fit_content")
		return
	if "offset_top = 56" in update_leg or "offset_top = 56.0" in update_leg:
		_fail("Supply legend must not pin at y=56 over the mode chips")
		return
	var set_fn: String = _slice_func(tb, "set_mode")
	if "not notify_renderer" in set_fn and 'm = "supply"' in set_fn:
		_fail("set_mode must not remap a chip click back to Supply while L is on")
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
	_mr.set("supply_mode", true)
	_mr.call("_set_supply_legend_visible", true)
	_fill_live_legend_text()
	_mr.call("_layout_map_ui")
	await _flush()
	if _mr.get("_supply_legend_panel") == null:
		_fail("SupplyOverlayLegend was not created")
		return false
	_pass("booted MapRenderer + toolbar + Supply legend")
	return true


func _boot_top_bar() -> bool:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null:
		tm.set("scenario_start_year", 1936)
		tm.set("current_year", 1936)
		tm.set("current_month", 1)
		tm.set("current_day", 1)
		tm.set("paused", true)
	var lm: Node = root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	if _war == null:
		_fail("WarStateDomain missing")
		return false
	_war.reset_for_test()
	if _war.has_method("clear_rule_overrides"):
		_war.clear_rule_overrides()
	if not bool(_war.loop_enabled()):
		_fail("campaign loop inactive — cannot declare a real war")
		return false
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		_fail("TopInfoBar.tscn missing")
		return false
	var inst: Node = packed.instantiate()
	if inst == null or not (inst is Control):
		_fail("TopInfoBar instantiate failed")
		return false
	_top_bar = inst as Control
	_top_bar.name = "TopInfoBar"
	if "player_country_tag" in _top_bar:
		_top_bar.set("player_country_tag", "GER")
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_left = 0.0
	_top_bar.offset_top = 0.0
	_top_bar.offset_right = 0.0
	_top_bar.offset_bottom = 52.0
	root.add_child(_top_bar)
	await _flush()
	var bar_h: float = 0.0
	if _top_bar.has_method("get_bar_height"):
		bar_h = float(_top_bar.call("get_bar_height"))
	if bar_h > 60.0:
		_fail("peace TopInfoBar height %.1f (live bar stays ~52)" % bar_h)
		return false
	_pass("TopInfoBar booted height=%.1f (live ~52)" % bar_h)
	return true


func _fill_live_legend_text() -> void:
	if _mr == null:
		return
	_mr.set("supply_mode", true)
	_mr.call("_set_supply_legend_visible", true)
	var rtl: RichTextLabel = _mr.get("_supply_overlay_legend") as RichTextLabel
	## Load after autoloads. A class_name reference here compiles ProvinceInsight
	## before MapManager exists and strips the live builder.
	var insight: GDScript = load("res://scripts/map/ProvinceInsight.gd") as GDScript
	if insight == null or not insight.has_method("build_supply_legend_bbcode"):
		_fail("ProvinceInsight.build_supply_legend_bbcode unavailable")
		return
	var live: String = str(
		insight.call("build_supply_legend_bbcode", -1, 0, -1, "", 12, 4, "GER", 2, "", "")
	)
	if live.length() < 400:
		_fail("live Supply legend text is too short (%d chars) — need real bbcode" % live.length())
		return
	if rtl != null:
		rtl.fit_content = false
		rtl.scroll_active = true
		rtl.text = live
	_mr.call("_layout_supply_legend")
	_info("live legend text chars=%d" % live.length())


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
	if legend.size.x > 480.0 + 1.0:
		_fail("%s legend width %.1f > 480 at %dx%d (%s)" % [label, legend.size.x, wh.x, wh.y, str(legend)])
		return
	if legend.size.y > 200.0:
		_fail("%s legend height %.1f > 200 at %dx%d (%s)" % [label, legend.size.y, wh.x, wh.y, str(legend)])
		return
	var rtl: RichTextLabel = _mr.get("_supply_overlay_legend") as RichTextLabel
	var content_h: float = 0.0
	if rtl != null and rtl.has_method("get_content_height"):
		content_h = float(rtl.call("get_content_height"))
	if str(rtl.text if rtl != null else "").length() < 400:
		_fail("%s legend text is not the real live bbcode" % label)
		return
	if content_h <= 200.0:
		_fail("%s legend content height %.1f — real text must exceed the 200 px frame" % [label, content_h])
		return
	var mm: Rect2 = _minimap_rect()
	if mm.size.x >= 8.0 and mm.size.y >= 8.0 and legend.intersects(mm):
		_fail("%s legend %s overlaps minimap %s at %dx%d" % [label, str(legend), str(mm), wh.x, wh.y])
		return
	_info("MEASURE %s legend=%s" % [label, str(legend)])
	_pass("%s legend %s height<=200 and misses minimap at %dx%d" % [label, str(legend), wh.x, wh.y])


func _assert_legend_height_and_minimap(wh: Vector2i) -> void:
	_set_window_size(wh)
	_fill_live_legend_text()
	_mr.call("_layout_map_ui")
	await _flush()
	_assert_legend_fits(wh, "peace")


func _assert_legend_height_and_minimap_at_war(wh: Vector2i) -> void:
	_set_window_size(wh)
	if _war == null:
		_fail("WarStateDomain was not booted")
		return
	_war.reset_for_test()
	var declared: Dictionary = _war.declare_war("GER", "POL", "call_to_arms")
	if not bool(declared.get("ok", false)):
		_fail("declare_war GER-POL failed %s" % str(declared))
		return
	if _top_bar != null and _top_bar.has_method("refresh_campaign_war_readout"):
		_top_bar.call("refresh_campaign_war_readout")
	await _flush()
	var bar_h: float = 0.0
	if _top_bar != null and _top_bar.has_method("get_bar_height"):
		bar_h = float(_top_bar.call("get_bar_height"))
	if bar_h > 60.0:
		_fail("war TopInfoBar height %.1f (live bar stays ~52)" % bar_h)
		return
	_info("MEASURE war TopInfoBar height=%.1f" % bar_h)
	_fill_live_legend_text()
	_mr.call("_layout_map_ui")
	await _flush()
	_assert_legend_fits(wh, "war")
	_pass("real declare_war GER-POL; live top bar %.1f px" % bar_h)


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
	_mr.call("_apply_l_key_legend_toolbar_highlight")
	if str(tb.call("get_current_mode")) != "supply":
		_fail("L-key must highlight Supply (got %s)" % str(tb.call("get_current_mode")))
		return
	var buttons = tb.get("_buttons")
	if buttons is Dictionary:
		var sup: Button = (buttons as Dictionary).get("supply") as Button
		var pol: Button = (buttons as Dictionary).get("political") as Button
		if sup == null or not sup.button_pressed:
			_fail("Supply chip must be pressed after L-key highlight")
			return
		if pol != null and pol.button_pressed:
			_fail("Political chip must not stay pressed after L-key highlight")
			return
	_pass("toolbar highlight tracks Supply/Infra; L-key highlights Supply")


func _test_mode_chip_toggled_while_legend_open() -> void:
	var tb: Node = _mr.get("_map_mode_toolbar") as Node
	if tb == null or not tb.has_method("get_current_mode"):
		_fail("toolbar missing for toggled chip test")
		return
	_mr.set("current_map_mode", "political")
	_mr.set("supply_mode", true)
	_mr.call("_set_supply_legend_visible", true)
	_mr.call("_apply_l_key_legend_toolbar_highlight")
	if str(tb.call("get_current_mode")) != "supply":
		_fail("precondition: L-on should highlight Supply before chip click (got %s)" % str(tb.call("get_current_mode")))
		return
	var buttons = tb.get("_buttons")
	if not (buttons is Dictionary):
		_fail("toolbar _buttons missing")
		return
	var pol: Button = (buttons as Dictionary).get("political") as Button
	if pol == null:
		_fail("Political chip missing")
		return
	pol.emit_signal("toggled", true)
	if str(tb.call("get_current_mode")) != "political":
		_fail(
			"Political toggled while L-on must highlight Political (got %s)"
			% str(tb.call("get_current_mode"))
		)
		return
	if not pol.button_pressed:
		_fail("Political chip must stay pressed after toggled")
		return
	var sup: Button = (buttons as Dictionary).get("supply") as Button
	if sup != null and sup.button_pressed:
		_fail("Supply chip must not stay pressed after Political toggled")
		return
	_pass("Political toggled while L-on highlights Political")


func _test_highway_hint_live() -> void:
	var tb: Node = _mr.get("_map_mode_toolbar") as Node
	if tb == null:
		_fail("toolbar missing for highway hint")
		return
	_mr.set("current_map_mode", "political")
	_mr.set("supply_mode", false)
	_mr.call("_sync_mapmode_toolbar")
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
