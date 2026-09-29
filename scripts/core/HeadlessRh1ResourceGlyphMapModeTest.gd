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
	_test_renderer_set_map_mode_hook()


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


func _test_renderer_set_map_mode_hook() -> void:
	var ren_scr: Script = load(SRC_REN) as Script
	var ol_scr: Script = load(SRC_OL) as Script
	if ren_scr == null or ol_scr == null:
		_fail("could not load MapRenderer or overlay script")
		return
	var mr: Node = ren_scr.new()
	var ol: Node = ol_scr.new()
	if mr == null or ol == null:
		_fail("could not instantiate MapRenderer/overlay")
		if mr != null:
			mr.free()
		if ol != null:
			ol.free()
		return
	var host := Node2D.new()
	host.name = "OverlayHost"
	mr.add_child(host)
	mr.set("container", host)
	# Skip deferred fill/mesh apply — this is a glyph-flag hook test only.
	if "_map_mode_apply_scheduled" in mr:
		mr.set("_map_mode_apply_scheduled", true)
	ol.name = "InfrastructureOverlayLayer"
	host.add_child(ol)
	if bool(ol.get("show_resource_icons")):
		_fail("renderer-attached overlay must start hidden")
	else:
		_pass("renderer-attached overlay starts hidden")
	if not mr.has_method("set_map_mode"):
		_fail("MapRenderer.set_map_mode missing")
		mr.free()
		return
	mr.call("set_map_mode", "states")
	_expect_icons(ol, false, "renderer.states")
	mr.call("set_map_mode", "diplomacy")
	_expect_icons(ol, false, "renderer.diplomacy")
	mr.call("set_map_mode", "terrain")
	_expect_icons(ol, false, "renderer.terrain")
	mr.call("set_map_mode", "resources")
	_expect_icons(ol, false if str(mr.get("current_map_mode")) != "resources" else true, "renderer.resources")
	if str(mr.get("current_map_mode")) != "resources":
		_fail("set_map_mode(resources) current_map_mode=%s" % str(mr.get("current_map_mode")))
	elif not bool(ol.get("show_resource_icons")):
		_fail("set_map_mode(resources) left glyphs hidden")
	else:
		_pass("set_map_mode(resources) shows glyphs")
	mr.call("set_map_mode", "political")
	_expect_icons(ol, false, "renderer.back_to_political")
	mr.call("set_map_mode", "resources")
	_expect_icons(ol, true, "renderer.resources_again")
	mr.call("set_map_mode", "diplomacy")
	_expect_icons(ol, false, "renderer.resources_to_diplomacy")
	mr.free()
