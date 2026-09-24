extends SceneTree

## Prove live Search/Go resolves Köln / Cologne / Koln / Koeln → 710417
## and the shipped inspector path force-opens without tactical zoom.
## Does not require the 3520 board.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1SearchGoInspectorTest.gd

const SRC_SEARCH := "res://scripts/ui/map/MapProvinceSearch.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
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
	_pass("Search/Go + Alt/infra source path force-opens inspector (soft pan, no queue_free)")


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
	node.queue_free()
