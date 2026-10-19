extends SceneTree

## ROADS-1 FIX #5: wheel over the Supply legend scrolls its text.
## Wheel over open map still zooms. Uses real InputEventMouseButton wheels.
##
##   tools/run_godot.sh --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessRoads1SupplyLegendWheelTest.gd
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessRoads1SupplyLegendWheelTest.gd

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 6
const MAP_WHEEL_POS := Vector2(980.0, 520.0)

var _failures: int = 0
var _mr: Node = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok: bool = _failures == 0
	print("HeadlessRoads1SupplyLegendWheelTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRoads1SupplyLegendWheelTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRoads1SupplyLegendWheelTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRoads1SupplyLegendWheelTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessRoads1SupplyLegendWheelTest: ", msg)


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
	_test_source_yields_to_legend()
	if not await _boot_renderer():
		return
	await _test_wheel_over_legend_scrolls()
	await _test_wheel_over_map_zooms()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()


func _test_source_yields_to_legend() -> void:
	var ren: String = _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var wheel_fn: String = _slice_func(ren, "_wheel_should_zoom_map")
	if wheel_fn.is_empty():
		_fail("_wheel_should_zoom_map missing")
		return
	if "_pointer_over_supply_legend" not in wheel_fn:
		_fail("_wheel_should_zoom_map must yield when the pointer is over the Supply legend")
		return
	if "SupplyOverlayLegend" not in wheel_fn and "_supply_legend_panel" not in wheel_fn:
		_fail("_wheel_should_zoom_map must name the legend panel or SupplyOverlayLegend")
		return
	_pass("source: _wheel_should_zoom_map yields to the Supply legend")


func _boot_renderer() -> bool:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.size = PLAY_SIZE
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
	cam.zoom = Vector2(0.50, 0.50)
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
	_mr.call("_update_supply_overlay_legend")
	_mr.set("supply_mode", true)
	_mr.call("_set_supply_legend_visible", true)
	_fill_live_legend_text()
	_mr.call("_layout_map_ui")
	await _flush()
	if _mr.get("_supply_legend_panel") == null or _mr.get("_supply_overlay_legend") == null:
		_fail("Supply overlay legend was not created")
		return false
	_pass("booted MapRenderer + scrolling Supply legend")
	return true


func _fill_live_legend_text() -> void:
	var rtl: RichTextLabel = _mr.get("_supply_overlay_legend") as RichTextLabel
	var insight: GDScript = load("res://scripts/map/ProvinceInsight.gd") as GDScript
	if insight == null or not insight.has_method("build_supply_legend_bbcode"):
		_fail("ProvinceInsight.build_supply_legend_bbcode unavailable")
		return
	var live: String = str(
		insight.call("build_supply_legend_bbcode", -1, 0, -1, "", 12, 4, "GER", 2, "", "")
	)
	if live.length() < 400:
		_fail("live Supply legend text is too short (%d chars)" % live.length())
		return
	if rtl != null:
		rtl.fit_content = false
		rtl.scroll_active = true
		rtl.text = live
	_mr.call("_layout_supply_legend")
	_info("live legend text chars=%d" % live.length())


func _camera() -> Camera2D:
	if _mr == null:
		return null
	return _mr.get_node_or_null("MapCamera") as Camera2D


func _legend_scroll_value() -> float:
	var rtl: RichTextLabel = _mr.get("_supply_overlay_legend") as RichTextLabel
	if rtl == null:
		return -1.0
	var bar: VScrollBar = rtl.get_v_scroll_bar()
	if bar == null:
		return -1.0
	return float(bar.value)


func _legend_wheel_pos() -> Vector2:
	var rtl: RichTextLabel = _mr.get("_supply_overlay_legend") as RichTextLabel
	if rtl != null and rtl.is_visible_in_tree() and rtl.get_global_rect().size.y >= 8.0:
		return rtl.get_global_rect().get_center()
	var panel: Control = _mr.get("_supply_legend_panel") as Control
	if panel != null and panel.is_visible_in_tree():
		var r: Rect2 = panel.get_global_rect()
		return Vector2(r.position.x + r.size.x * 0.50, r.position.y + r.size.y * 0.72)
	return Vector2(250.0, 320.0)


func _warp_mouse(screen_pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport() if root != null else null
	if vp != null:
		vp.warp_mouse(screen_pt)
	DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pt
	motion.global_position = screen_pt
	Input.parse_input_event(motion)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _send_wheel(screen_pt: Vector2, zoom_in: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if zoom_in else MOUSE_BUTTON_WHEEL_DOWN
	ev.position = screen_pt
	ev.global_position = screen_pt
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _test_wheel_over_legend_scrolls() -> void:
	var cam: Camera2D = _camera()
	var rtl: RichTextLabel = _mr.get("_supply_overlay_legend") as RichTextLabel
	if cam == null or rtl == null:
		_fail("camera or legend RTL missing")
		return
	var pos: Vector2 = _legend_wheel_pos()
	_warp_mouse(pos)
	await _flush()
	if _mr.has_method("_wheel_should_zoom_map") and bool(_mr.call("_wheel_should_zoom_map")):
		_fail("over legend, _wheel_should_zoom_map must be false (pos=%s)" % str(pos))
		return
	var zoom0: float = cam.zoom.x
	var scroll0: float = _legend_scroll_value()
	var i := 0
	while i < 5:
		_send_wheel(pos, false)
		await process_frame
		i += 1
	await _flush()
	var zoom1: float = cam.zoom.x
	var scroll1: float = _legend_scroll_value()
	_info("legend wheel pos=%s zoom %.4f→%.4f scroll_value %.2f→%.2f" % [str(pos), zoom0, zoom1, scroll0, scroll1])
	if absf(zoom1 - zoom0) > 0.0005:
		_fail("wheel over legend zoomed the map (%.4f → %.4f)" % [zoom0, zoom1])
		return
	if scroll1 <= scroll0:
		_fail("wheel over legend did not increase scroll_value (%.2f → %.2f)" % [scroll0, scroll1])
		return
	_pass("wheel over legend: scroll_value %.2f→%.2f, zoom held %.4f" % [scroll0, scroll1, zoom1])


func _test_wheel_over_map_zooms() -> void:
	var cam: Camera2D = _camera()
	if cam == null:
		_fail("camera missing for map-wheel")
		return
	_warp_mouse(MAP_WHEEL_POS)
	await _flush()
	if _mr.has_method("_wheel_should_zoom_map") and not bool(_mr.call("_wheel_should_zoom_map")):
		_fail("over open map, _wheel_should_zoom_map must be true (pos=%s)" % str(MAP_WHEEL_POS))
		return
	var zoom0: float = cam.zoom.x
	var scroll0: float = _legend_scroll_value()
	_send_wheel(MAP_WHEEL_POS, false)
	await _flush()
	var zoom1: float = cam.zoom.x
	var scroll1: float = _legend_scroll_value()
	_info("map wheel pos=%s zoom %.4f→%.4f scroll_value %.2f→%.2f" % [str(MAP_WHEEL_POS), zoom0, zoom1, scroll0, scroll1])
	if absf(zoom1 - zoom0) <= 0.0005:
		_fail("wheel over open map did not change zoom (stayed %.4f)" % zoom0)
		return
	if absf(scroll1 - scroll0) > 0.05:
		_fail("wheel over open map moved legend scroll (%.2f → %.2f)" % [scroll0, scroll1])
		return
	_pass("wheel over open map: zoom %.4f→%.4f, legend scroll held" % [zoom0, zoom1])
