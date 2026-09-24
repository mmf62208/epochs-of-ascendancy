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
