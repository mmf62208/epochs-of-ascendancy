extends SceneTree

## Prove live Search/Go resolves Köln / Cologne / Koln / Koeln → 710417
## and the shipped inspector path force-opens without tactical zoom.
## Does not require the 3520 board.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1SearchGoInspectorTest.gd

const SRC_SEARCH := "res://scripts/ui/map/MapProvinceSearch.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TR := "res://scripts/core/TestRunner.gd"
const HUB_ID := 710417

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessIx1SearchGoInspectorTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessIx1SearchGoInspectorTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessIx1SearchGoInspectorTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessIx1SearchGoInspectorTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


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
	var nxt := src.find("\nfunc ", i + needle.length())
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _run() -> void:
	_test_source_live_inspector_path()
	_test_resolve_aliases()
	_test_go_enter_signal_wiring()
	_test_source_spine_visible_after_search()
	_test_idm_should_show_spine_on_koln()
	_test_spine_start_after_press_wiring()


func _test_source_live_inspector_path() -> void:
	var search := _read(SRC_SEARCH)
	var ren := _read(SRC_REN)
	if search.is_empty() or ren.is_empty():
		_fail("search/renderer source missing")
		return
	if "open_province_inspector_from_search" not in search:
		_fail("MapProvinceSearch does not call open_province_inspector_from_search")
		return
	if "fold_search_key" not in search or "city_name" not in search or "cologne" not in search:
		_fail("Search missing fold / city_name / cologne alias")
		return
	if "SearchGoButton" not in search or "text_submitted.connect(_on_submit)" not in search:
		_fail("Search LineEdit/Go signals are not wired")
		return
	if "button_down.connect(_on_go_pressed)" not in search:
		_fail("Go button_down is not wired (live click can miss pressed-on-up)")
		return
	if "_search_ui_owns_click" not in ren or "rebind_map_search" not in ren:
		_fail("MapRenderer missing search rect / rebind after living title")
		return
	if "ensure_live_search_chrome" not in ren or "search_chrome_is_live" not in ren:
		_fail("MapRenderer missing ensure_live_search_chrome after stay-alive")
		return
	if "search_chrome_pixel_report" not in ren:
		_fail("MapRenderer missing search_chrome_pixel_report (log live=1 is not enough)")
		return
	var ensure_fn := _slice_func(ren, "ensure_live_search_chrome")
	if ensure_fn.is_empty() or "UILayer" not in ensure_fn:
		_fail("ensure_live_search_chrome must host Search on UILayer 110 (not WorldMap UI 20)")
		return
	if "TopInfoBar" not in ensure_fn and "TopInfoBar" not in _slice_func(ren, "_search_hud_control_host"):
		_fail("Search must parent to TopInfoBar (Control with size), not a 0-size CanvasLayer")
		return
	var layout_fn := _slice_func(ren, "_layout_map_search_chrome")
	if layout_fn.is_empty() or ("TopInfoBar" not in layout_fn and "PRESET_TOP_RIGHT" not in layout_fn):
		_fail("Search layout must pin TOP_RIGHT of the TopInfoBar strip")
		return
	if "PRESET_TOP_RIGHT" in _slice_func(ren, "_layout_map_ui"):
		_fail("Search must not use PRESET_TOP_RIGHT on a CanvasLayer parent")
		return
	var pixel_fn := _slice_func(ren, "search_chrome_pixel_report")
	if pixel_fn.is_empty() or "on_screen" not in pixel_fn or "overlap" not in pixel_fn:
		_fail("pixel report must include on_screen / overlap (fail live when pixels absent)")
		return
	if "live" not in pixel_fn:
		_fail("pixel report must set live=0 when drawn rect is missing")
		return
	if "ensure_chrome_visible" not in search or "custom_minimum_size = Vector2(180, 28)" not in search:
		_fail("Search LineEdit must keep a 28px min height so stay-alive chrome is visible")
		return
	if "_force_child_geometry" not in search:
		_fail("Search must force LineEdit/Go actual size (min size alone can paint 0px)")
		return
	var tr := _read(SRC_TR)
	if "_restore_live_search_chrome_after_stay_alive" not in tr or "EOA_SMOKE_SEARCH_CHROME" not in tr:
		_fail("TestRunner must restore live Search chrome after stay-alive (not a headless-only path)")
		return
	if "EOA_SMOKE_SEARCH_CHROME_PIXEL" not in tr:
		_fail("TestRunner must log EOA_SMOKE_SEARCH_CHROME_PIXEL (rect/overlap/on_screen)")
		return
	if "ensure_live_search_chrome" not in _slice_func(tr, "_restore_live_search_chrome_after_stay_alive"):
		_fail("stay-alive restore must call ensure_live_search_chrome")
		return
	if "search_chrome_pixel_report" not in _slice_func(tr, "_restore_live_search_chrome_after_stay_alive"):
		_fail("stay-alive restore must use search_chrome_pixel_report (not flag-only live)")
		return
	if "layout_settle" not in tr or "_smoke_search_chrome_sticky_after_reflow" not in tr:
		_fail("TestRunner must PIXEL-check Search after TopInfoBar layout settle (not first-paint only)")
		return
	if "in_bar" not in pixel_fn:
		_fail("pixel report must require Search in the TopInfoBar strip (in_bar)")
		return
	var tib_src := _read("res://scripts/ui/TopInfoBar.gd")
	if "_keep_search_chrome_sticky" not in tib_src:
		_fail("TopInfoBar must re-apply Search after More+/Steel/Al reflow")
		return
	if "RightContainer" not in _slice_func(tib_src, "host_map_search_chrome"):
		_fail("host_map_search_chrome must place Search in RightContainer (not overlay-only TOP_RIGHT)")
		return
	var live := _slice_func(ren, "open_province_inspector_from_search")
	if live.is_empty():
		_fail("open_province_inspector_from_search missing")
		return
	if "show_info_panel(province, true, true)" not in live:
		_fail("Search inspector is not force-open + keep_camera")
		return
	if "_soft_pan_camera_to_province" not in live:
		_fail("Search still uses a hard camera snap")
		return
	if "2.4" in live:
		_fail("Search live path still mentions tactical 2.4 zoom")
		return
	var hide := _slice_func(ren, "_hide_unit_card_keep_map_focus")
	if "queue_free()" in hide:
		_fail("hide unit card still queue_free mid Search")
		return
	var hex := _slice_func(ren, "_open_hex_province_inspector")
	if "show_info_panel(province, true, true)" not in hex:
		_fail("Alt/infra hex backup does not force-open inspector")
		return
	if "_reveal_ix1_road_spine_on_inspector" not in live:
		_fail("Search live path does not reveal Build Road Spine")
		return
	_pass("Search/Go + Alt/infra source path force-opens inspector (soft pan, no queue_free)")


func _test_source_spine_visible_after_search() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer source missing for spine-visible gate")
		return
	var live := _slice_func(ren, "open_province_inspector_from_search")
	if "_reveal_ix1_road_spine_on_inspector" not in live:
		_fail("open_province_inspector_from_search does not reveal Build Road Spine")
		return
	var hex := _slice_func(ren, "_open_hex_province_inspector")
	if "_reveal_ix1_road_spine_on_inspector" not in hex:
		_fail("Alt/infra hex backup does not reveal Build Road Spine")
		return
	var show := _slice_func(ren, "show_info_panel")
	if "_reveal_ix1_road_spine_on_inspector" not in show:
		_fail("show_info_panel does not keep Build Road Spine on the live inspector")
		return
	var pin := _slice_func(ren, "_pin_road_spine_button_to_inspector_chrome")
	if pin.is_empty() or "add_child" not in pin:
		_fail("Build Road Spine is not pinned to InfoPanel chrome")
		return
	var reveal := _slice_func(ren, "_reveal_ix1_road_spine_on_inspector")
	if "scroll_vertical" not in reveal:
		_fail("Search reveal does not reset inspector scroll")
		return
	if "Ix1SpineBuildRow" not in ren or "BtnBuildRoadSpineInList" not in ren:
		_fail("Build Road Spine is not pinned into the live facility Build list")
		return
	if "_prepend_ix1_spine_build_row" not in _slice_func(ren, "_update_special_sites_ui"):
		_fail("special-sites Build list does not prepend Build Road Spine")
		return
	var layout := _slice_func(ren, "_layout_road_spine_chrome_button")
	if "230" not in layout:
		_fail("Build Road Spine chrome is not next to Settle")
		return
	_pass("Search+Go live path pins Build Road Spine on chrome + facility Build list")


func _test_idm_should_show_spine_on_koln() -> void:
	var idm: Node = root.get_node_or_null("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("should_show_road_spine_button"):
		_fail("should_show_road_spine_button missing")
		return
	if not idm.has_method("is_ix1_road_spine_province"):
		_fail("is_ix1_road_spine_province missing")
		return
	if not bool(idm.call("is_ix1_road_spine_province", HUB_ID)):
		_fail("710417 is not an IX-1 corridor province")
		return
	if not bool(idm.call("should_show_road_spine_button", HUB_ID, "GER")):
		_fail("should_show_road_spine_button(710417, GER) is false on day-0 Köln")
		return
	if bool(idm.call("should_show_road_spine_button", 710403, "GER")):
		_fail("should_show_road_spine_button showed on off-spine Essen")
		return
	if not idm.has_method("get_ix1_road_spine_mandate_cost"):
		_fail("get_ix1_road_spine_mandate_cost missing")
		return
	if int(idm.call("get_ix1_road_spine_mandate_cost")) != 0:
		_fail("IX-1 Mandate cost is not 0")
		return
	_pass("IDM shows startable Build Road Spine on GER 1936 day-0 Köln (Mandate 0)")


func _test_spine_start_after_press_wiring() -> void:
	# Play MIXED d0b1587d: chrome visible, live press never armed.
	var ren := _read(SRC_REN)
	var idm := _read("res://scripts/map/InfrastructureDevelopmentManager.gd")
	if ren.is_empty() or idm.is_empty():
		_fail("renderer/IDM source missing for spine start-after-press")
		return
	if "_road_spine_btn_owns_click" not in ren:
		_fail("Build Road Spine click is not owned (leftover map pan can swallow press)")
		return
	if "_road_spine_btn_owns_click" not in _slice_func(ren, "_input"):
		_fail("MapRenderer._input does not yield to Build Road Spine")
		return
	var wire := _slice_func(ren, "_wire_road_spine_live_button")
	if wire.is_empty() or "ACTION_MODE_BUTTON_PRESS" not in wire:
		_fail("Build Road Spine is not press-on-down")
		return
	if "button_down.connect(_on_build_road_spine_pressed)" not in ren:
		_fail("Build Road Spine button_down is not wired")
		return
	if "press_build_road_spine_from_live_ui" not in ren:
		_fail("press_build_road_spine_from_live_ui missing")
		return
	if "EOA_SMOKE_SPINE_START" not in ren:
		_fail("EOA_SMOKE_SPINE_START live start gate missing")
		return
	if "EOA_ZOOM_BEGIN" not in ren or "EOA_ZOOM_END" not in ren:
		_fail("EOA_ZOOM_BEGIN/END missing (silent-exit capture)")
		return
	var press := _slice_func(ren, "_on_build_road_spine_pressed")
	var after := _slice_func(ren, "_ix1_spine_start_after_first_frame")
	if 'focus_province_by_id(pid, "soft")' not in after:
		_fail("spine press still tactical-zooms (softpipe silent exit)")
		return
	if 'call_deferred("_ix1_spine_start_after_first_frame"' not in press:
		_fail("spine start must defer panel/zoom so toast paints first")
		return
	if "_ix1_spine_target_province_id" not in press:
		_fail("spine press does not resolve inspector pid")
		return
	if "open Köln first" not in press:
		_fail("spine press can silent-return with no toast")
		return
	var start := _slice_func(idm, "try_start_road_spine")
	if "can_start_project(" in start:
		_fail("try_start_road_spine still uses generic Invest can_start_project")
		return
	if "start_road_spine_project" not in start:
		_fail("try_start_road_spine does not create via start_road_spine_project")
		return
	_pass("Build Road Spine live press arms start (owns-click + press-on-down + no Invest gate)")


func _test_resolve_aliases() -> void:
	var script: Script = load(SRC_SEARCH) as Script
	if script == null:
		_fail("cannot load MapProvinceSearch.gd")
		return
	var node := HBoxContainer.new()
	node.set_script(script)
	root.add_child(node)
	if not node.has_method("resolve_search_query"):
		_fail("resolve_search_query missing")
		node.queue_free()
		return
	if not node.has_method("fold_search_key"):
		_fail("fold_search_key missing")
		node.queue_free()
		return
	var folded: String = str(node.call("fold_search_key", "Köln"))
	if folded != "koln":
		_fail("fold_search_key(Köln) expected koln got %s" % folded)
		node.queue_free()
		return
	var queries: PackedStringArray = PackedStringArray(["Köln", "koln", "koeln", "Cologne", "cologne", "710417"])
	for q in queries:
		var pid: int = int(node.call("resolve_search_query", q))
		if pid != HUB_ID:
			_fail("resolve_search_query(%s)=%d expected %d" % [q, pid, HUB_ID])
			node.queue_free()
			return
	_pass("Search resolves Köln/Cologne/Koln/Koeln/710417 → 710417")
	node.queue_free()


func _make_inspector_stub() -> Node:
	var stub_script := GDScript.new()
	stub_script.source_code = """extends Node
var last_pid: int = -1
var calls: int = 0
func open_province_inspector_from_search(province_id: int) -> bool:
	last_pid = province_id
	calls += 1
	return true
"""
	var err: Error = stub_script.reload()
	if err != OK:
		return null
	var stub := Node.new()
	stub.set_script(stub_script)
	return stub


func _test_go_enter_signal_wiring() -> void:
	## Live-facing: emit Button.pressed / LineEdit.text_submitted and require
	## the same resolve + open_province_inspector_from_search path.
	var script: Script = load(SRC_SEARCH) as Script
	if script == null:
		_fail("cannot load MapProvinceSearch.gd for signal gate")
		return
	var node := HBoxContainer.new()
	node.set_script(script)
	root.add_child(node)
	if node.has_method("_ensure_live_controls"):
		node.call("_ensure_live_controls")
	var line: LineEdit = node.get_node_or_null("SearchLineEdit") as LineEdit
	var btn: Button = node.get_node_or_null("SearchGoButton") as Button
	if line == null or btn == null:
		_fail("SearchLineEdit / SearchGoButton missing after _ready")
		node.queue_free()
		return
	if node.has_method("ensure_chrome_visible"):
		node.call("ensure_chrome_visible")
	if not line.visible or not btn.visible or line.focus_mode == Control.FOCUS_NONE:
		_fail("Search LineEdit/Go not visible/focusable after ensure_chrome_visible")
		node.queue_free()
		return
	if line.custom_minimum_size.y < 24.0:
		_fail("Search LineEdit min height is 0 — live chrome vanishes after stay-alive")
		node.queue_free()
		return
	# Pixel prove: parent to a sized Control (TopInfoBar class) so layout is real.
	var bar := Control.new()
	bar.name = "TopInfoBar"
	bar.size = Vector2(1280, 52)
	bar.custom_minimum_size = Vector2(1280, 52)
	bar.clip_contents = false
	root.add_child(bar)
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	bar.add_child(node)
	node.set_anchors_preset(Control.PRESET_TOP_RIGHT, false)
	node.offset_left = -316.0
	node.offset_right = -8.0
	node.offset_top = 10.0
	node.offset_bottom = 42.0
	if node.has_method("ensure_chrome_visible"):
		node.call("ensure_chrome_visible")
	var line_r: Rect2 = line.get_global_rect()
	var go_r: Rect2 = btn.get_global_rect()
	if line_r.size.x < 80.0 or line_r.size.y < 16.0 or go_r.size.x < 24.0 or go_r.size.y < 16.0:
		_fail("Search LineEdit/Go drawn rect is zero/off-parent after TopInfoBar host")
		bar.queue_free()
		return
	if line_r.position.x < 0.0 or line_r.end.x > 1280.0 or line_r.position.y < 0.0:
		_fail("Search LineEdit is off-screen on TopInfoBar host (x=%s y=%s)" % [str(line_r.position.x), str(line_r.position.y)])
		bar.queue_free()
		return
	# Play 48e4fe20: overlay TOP_RIGHT vanished after Steel/Al reflow. In-flow
	# RightContainer must keep LineEdit/Go sized and focusable.
	var right: HBoxContainer = HBoxContainer.new()
	right.name = "RightContainer"
	right.custom_minimum_size = Vector2(800, 40)
	right.size = Vector2(800, 40)
	bar.add_child(right)
	var steel_l: Label = Label.new()
	steel_l.name = "SteelLabel"
	steel_l.text = "Steel: 12000"
	steel_l.visible = true
	right.add_child(steel_l)
	var al_l: Label = Label.new()
	al_l.name = "AluminumLabel"
	al_l.text = "Aluminum: 8000"
	al_l.visible = true
	right.add_child(al_l)
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	right.add_child(node)
	node.size_flags_horizontal = Control.SIZE_SHRINK_END
	node.custom_minimum_size = Vector2(308, 32)
	if node.has_method("ensure_chrome_visible"):
		node.call("ensure_chrome_visible")
	if line.custom_minimum_size.x < 160.0 or line.custom_minimum_size.y < 24.0 or btn.custom_minimum_size.x < 40.0:
		_fail("Search LineEdit/Go lost min size after Steel/Al reflow")
		bar.queue_free()
		return
	if not line.visible or not btn.visible or line.focus_mode == Control.FOCUS_NONE or not line.editable:
		_fail("Search LineEdit/Go not focusable after Steel/Al reflow")
		bar.queue_free()
		return
	var pressed_wired: bool = false
	for c in btn.get_signal_connection_list("pressed"):
		if str(c.get("callable", "")).find("_on_go_pressed") >= 0:
			pressed_wired = true
	var submitted_wired: bool = false
	for c2 in line.get_signal_connection_list("text_submitted"):
		if str(c2.get("callable", "")).find("_on_submit") >= 0:
			submitted_wired = true
	if not pressed_wired:
		_fail("Go Button.pressed is not connected to _on_go_pressed")
		node.queue_free()
		return
	if not submitted_wired:
		_fail("LineEdit.text_submitted is not connected to _on_submit")
		node.queue_free()
		return
	var stub: Node = _make_inspector_stub()
	if stub == null:
		_fail("cannot build inspector stub")
		node.queue_free()
		return
	root.add_child(stub)
	if node.has_method("bind"):
		node.call("bind", stub, null)
	line.text = "Cologne"
	node.set("_submit_guard_msec", 0)
	btn.emit_signal("pressed")
	var go_pid: int = int(stub.get("last_pid"))
	var go_calls: int = int(stub.get("calls"))
	if go_pid != HUB_ID or go_calls < 1:
		_fail("Go pressed did not open inspector for Cologne (pid=%d calls=%d)" % [go_pid, go_calls])
		stub.queue_free()
		node.queue_free()
		return
	stub.set("last_pid", -1)
	stub.set("calls", 0)
	node.set("_submit_guard_msec", 0)
	line.emit_signal("text_submitted", "710417")
	var enter_open: int = int(stub.get("last_pid"))
	if enter_open != HUB_ID:
		_fail("text_submitted did not open inspector for 710417 (pid=%d)" % enter_open)
		stub.queue_free()
		node.queue_free()
		return
	if node.has_method("submit_from_live_ui"):
		var enter_pid: int = int(node.call("submit_from_live_ui", "Köln"))
		if enter_pid != HUB_ID:
			_fail("submit_from_live_ui(Köln)=%d expected %d" % [enter_pid, HUB_ID])
			stub.queue_free()
			node.queue_free()
			return
	_pass("Go pressed + Enter text_submitted call open_province_inspector_from_search(710417)")
	stub.queue_free()
	if is_instance_valid(bar):
		bar.queue_free()
	elif is_instance_valid(node):
		node.queue_free()
