extends SceneTree

## RH-1: resource glyphs only on F9 resources mapmode.
## Default/political/diplomacy/other modes keep show_resource_icons false.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRh1ResourceGlyphMapModeTest.gd

const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRh1ResourceGlyphMapModeTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRh1ResourceGlyphMapModeTest: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessRh1ResourceGlyphMapModeTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRh1ResourceGlyphMapModeTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_needles()
	_test_overlay_mapmode_gate()


func _test_source_needles() -> void:
	var ol := _read(SRC_OL)
	var ren := _read(SRC_REN)
	if "var show_resource_icons: bool = false" not in ol:
		_fail("overlay default show_resource_icons must be false")
	else:
		_pass("overlay default show_resource_icons=false")
	if 'var _glyph_map_mode: String = "political"' not in ol:
		_fail("overlay _glyph_map_mode default must be political")
	else:
		_pass("overlay _glyph_map_mode defaults political")
	if "func set_map_mode_for_glyphs" not in ol:
		_fail("set_map_mode_for_glyphs missing")
	else:
		_pass("set_map_mode_for_glyphs present")
	if 'ol_res.call("set_map_mode_for_glyphs", m)' not in ren:
		_fail("MapRenderer set_map_mode must hook set_map_mode_for_glyphs")
	else:
		_pass("MapRenderer set_map_mode hooks glyphs")
	if 'ol_glyphs.call("set_map_mode_for_glyphs", current_map_mode)' not in ren:
		_fail("MapRenderer init must seed glyphs from current_map_mode")
	else:
		_pass("MapRenderer init seeds glyphs hidden")


func _expect_icons(ol: Node, want: bool, label: String) -> void:
	var got := bool(ol.get("show_resource_icons"))
	if got != want:
		_fail("%s show_resource_icons=%s want=%s mode=%s" % [
			label, str(got), str(want), str(ol.get("_glyph_map_mode"))
		])
	else:
		_pass("%s show_resource_icons=%s" % [label, str(got)])


func _test_overlay_mapmode_gate() -> void:
	var scr: Script = load(SRC_OL) as Script
	if scr == null:
		_fail("could not load InfrastructureOverlayLayer.gd")
		return
	var ol: Node = scr.new()
	if ol == null:
		_fail("could not instantiate InfrastructureOverlayLayer")
		return
	_expect_icons(ol, false, "default")
	if str(ol.get("_glyph_map_mode")) != "political":
		_fail("default _glyph_map_mode=%s" % str(ol.get("_glyph_map_mode")))
	else:
		_pass("default _glyph_map_mode=political")
	if not ol.has_method("set_map_mode_for_glyphs"):
		_fail("instance missing set_map_mode_for_glyphs")
		ol.free()
		return
	ol.call("set_map_mode_for_glyphs", "political")
	_expect_icons(ol, false, "political")
	ol.call("set_map_mode_for_glyphs", "diplomacy")
	_expect_icons(ol, false, "diplomacy")
	for mode in ["states", "terrain", "infra", "supply", "strain", "weather"]:
		ol.call("set_map_mode_for_glyphs", str(mode))
		_expect_icons(ol, false, str(mode))
	ol.call("set_map_mode_for_glyphs", "resources")
	_expect_icons(ol, true, "resources")
	ol.call("set_map_mode_for_glyphs", "political")
	_expect_icons(ol, false, "back_to_political")
	ol.call("set_map_mode_for_glyphs", "RESOURCES")
	_expect_icons(ol, true, "RESOURCES_upper")
	ol.call("set_map_mode_for_glyphs", "diplomacy")
	_expect_icons(ol, false, "resources_to_diplomacy")
	ol.free()

