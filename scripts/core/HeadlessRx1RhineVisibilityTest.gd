extends SceneTree

## FIX2 scope change: units stay on top (z=28). Rhine/road sit above
## nation labels (18) and below counters. View-only U + HUD Units button.
## Spine chrome only on Bonn/Köln/Leverkusen. Launch path imports class cache.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRx1RhineVisibilityTest.gd

const SRC_LAYER := "res://scripts/map/Rx1RhineLayer.gd"
const SRC_INFRA := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_RUN := "res://tools/run_godot.sh"
const SRC_GD := "res://scripts/autoload/GameData.gd"
const NEUSS_ID := 710413
const KOELN_ID := 710417
const BONN_ID := 710416
const LEVERKUSEN_ID := 710418

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRx1RhineVisibilityTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRx1RhineVisibilityTest: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _const_int(src: String, name: String) -> int:
	var needle := "const %s := " % name
	var i := src.find(needle)
	if i < 0:
		return -1
	var rest := src.substr(i + needle.length(), 8)
	var digits := ""
	for ch in rest:
		if ch < "0" or ch > "9":
			break
		digits += ch
	return int(digits) if digits != "" else -1


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessRx1RhineVisibilityTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRx1RhineVisibilityTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_z_order()
	_test_spine_chrome_scope()
	_test_fresh_checkout_launch()
	_test_units_view_toggle()


func _test_z_order() -> void:
	var layer := _read(SRC_LAYER)
	var infra := _read(SRC_INFRA)
	var ren := _read(SRC_REN)
	var rhine_z := _const_int(layer, "MAP_BELOW_UNITS_Z")
	var unit_z := _const_int(layer, "UNIT_COUNTER_Z")
	var label_z := _const_int(layer, "NATION_LABEL_Z")
	var road_z := _const_int(infra, "ROAD_BELOW_UNITS_Z")
	if unit_z != 28:
		_fail("UNIT_COUNTER_Z must stay 28 (DemoUnitIcon)")
		return
	if label_z != 18:
		_fail("NATION_LABEL_Z must stay 18 (labels must not bury river/road)")
		return
	if rhine_z >= unit_z:
		_fail("Rhine MAP_BELOW_UNITS_Z=%d must sit below unit %d" % [rhine_z, unit_z])
		return
	if rhine_z <= label_z:
		_fail("Rhine z=%d must sit above nation Labels z=%d" % [rhine_z, label_z])
		return
	if road_z >= 28:
		_fail("RoadLayer ROAD_BELOW_UNITS_Z=%d must sit below units 28" % road_z)
		return
	if road_z <= 18:
		_fail("RoadLayer z=%d must sit above nation Labels 18" % road_z)
		return
	if "add_overlay_layer(\"Rx1RhineLayer\"" in ren and ", 22)" not in ren:
		_fail("MapRenderer must spawn Rx1RhineLayer at z=22 (below units)")
		return
	if "ABOVE_UNIT_COUNTERS_Z" in layer or "ROAD_ABOVE_UNIT_COUNTERS_Z" in infra:
		_fail("FIX1 raise-above-units constants must be gone")
		return
	if "RIVER_SCREEN_PX" not in layer:
		_fail("Rx1RhineLayer missing screen-space river width")
		return
	if "scale_points" not in layer and "THEATER_SCALE" not in layer:
		_fail("Rx1RhineLayer must scale course points onto the live theater canvas")
		return
	if "ROAD_EXPLICIT_SCREEN_PX" not in infra:
		_fail("InfrastructureOverlayLayer missing screen-space road width")
		return
	if "ROAD_EXPLICIT_COLOR" not in infra:
		_fail("InfrastructureOverlayLayer missing gold ROAD_EXPLICIT_COLOR")
		return
	if "class Ix1GoldSpineDraw" not in infra or "func refresh_ix1_gold_spine" not in infra:
		_fail("InfrastructureOverlayLayer missing joined Ix1GoldSpineDraw")
		return
	var gold_z := _const_int(infra, "GOLD_SPINE_Z")
	if gold_z >= 28 or gold_z <= 18:
		_fail("GOLD_SPINE_Z=%d must sit above labels 18 and below units 28" % gold_z)
		return
	var guard := _read("res://scripts/core/WindowedRx1RhinePixelGuard.gd")
	if "_sample_spine_continuity" not in guard:
		_fail("pixel guard must sample spine continuity along Bonn–Köln–Leverkusen")
		return
	_pass("Rhine z=%d Road z=%d gold z=%d sit above labels 18 and below units 28" % [rhine_z, road_z, gold_z])


func _test_spine_chrome_scope() -> void:
	var ren := _read(SRC_REN)
	if "func inspector_should_show_spine_status" not in ren:
		_fail("MapRenderer missing inspector_should_show_spine_status")
		return
	if "func _hide_ix1_spine_inspector_chrome" not in ren:
		_fail("MapRenderer missing _hide_ix1_spine_inspector_chrome")
		return
	if "710413" not in ren or "never Neuss" not in ren:
		_fail("spine chrome must name Neuss 710413 as out of scope")
		return
	var mr: Node = root.get_node_or_null("MapRenderer")
	if mr == null:
		var nodes: Array = get_nodes_in_group("map_renderer")
		if nodes.size() > 0:
			mr = nodes[0] as Node
	if mr != null and mr.has_method("inspector_should_show_spine_status"):
		if bool(mr.call("inspector_should_show_spine_status", NEUSS_ID)):
			_fail("inspector_should_show_spine_status(710413) must be false")
			return
		if not bool(mr.call("inspector_should_show_spine_status", KOELN_ID)):
			_fail("inspector_should_show_spine_status(710417) must be true")
			return
		if not bool(mr.call("inspector_should_show_spine_status", BONN_ID)):
			_fail("inspector_should_show_spine_status(710416) must be true")
			return
		if not bool(mr.call("inspector_should_show_spine_status", LEVERKUSEN_ID)):
			_fail("inspector_should_show_spine_status(710418) must be true")
			return
		_pass("spine status absent on Neuss 710413, present on Bonn/Köln/Leverkusen")
		return
	_pass("spine chrome helpers present (MapRenderer not instanced on -s; source gate)")


func _test_fresh_checkout_launch() -> void:
	var run := _read(SRC_RUN)
	var gd := _read(SRC_GD)
	if "--headless --import" not in run or "class cache missing" not in run:
		_fail("run_godot.sh must one-time --import when class cache lacks Rx1RhineCrossing")
		return
	if 'preload("res://scripts/map/Rx1RhineCrossing.gd")' not in gd:
		_fail("GameData must preload Rx1RhineCrossing.gd (no class_name at autoload parse)")
		return
	_pass("fresh-checkout launch: import-if-needed + GameData preload")


func _test_units_view_toggle() -> void:
	var ren := _read(SRC_REN)
	var bar := _read("res://scripts/ui/TopInfoBar.gd")
	var guard := _read("res://scripts/core/WindowedRx1RhinePixelGuard.gd")
	if "func set_unit_counters_visible" not in ren:
		_fail("MapRenderer missing set_unit_counters_visible")
		return
	if "func units_view_report" not in ren:
		_fail("MapRenderer missing units_view_report")
		return
	if "func _sync_unit_overlay_visibility" not in ren:
		_fail("MapRenderer missing overlay hide for stack/rings/bubbles")
		return
	if "toggle_unit_counters()" not in ren:
		_fail("MapRenderer must bind plain U to toggle_unit_counters")
		return
	# Plain U (not shift) must toggle units; Shift+U is supply flow.
	if "Supply/sealane flow %s (Shift+U)" not in ren:
		_fail("Shift+U must be supply/sealane flow (U is units)")
		return
	if "_gui_text_field_has_focus()" not in ren:
		_fail("U must not fire while Search has focus")
		return
	if "BtnUnitsView" not in bar:
		_fail("TopInfoBar missing BtnUnitsView HUD button")
		return
	if "func sync_units_view_button" not in bar:
		_fail("TopInfoBar missing sync_units_view_button")
		return
	if "_hide_unit_nodes_direct" not in guard:
		_fail("pixel guard must document 816cdc9 direct node hide")
		return
	_pass("view-only Units toggle: U + BtnUnitsView + Search-focus guard")
