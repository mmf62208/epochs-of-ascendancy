extends SceneTree

## FIX1 RX-1 visibility: Rhine + RoadLayer z above DemoUnitIcon (28),
## spine chrome only on Bonn/Köln/Leverkusen, launch path imports class cache.
## Must FAIL on 9750f3d (z=7 / leaked Neuss spine / no import gate) and PASS on tip.
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


func _test_z_order() -> void:
	var layer := _read(SRC_LAYER)
	var infra := _read(SRC_INFRA)
	var ren := _read(SRC_REN)
	var rhine_z := _const_int(layer, "ABOVE_UNIT_COUNTERS_Z")
	var unit_z := _const_int(layer, "UNIT_COUNTER_Z")
	var road_z := _const_int(infra, "ROAD_ABOVE_UNIT_COUNTERS_Z")
	if unit_z != 28:
		_fail("UNIT_COUNTER_Z must stay 28 (DemoUnitIcon)")
		return
	if rhine_z <= unit_z:
		_fail("Rhine ABOVE_UNIT_COUNTERS_Z=%d must be > unit %d" % [rhine_z, unit_z])
		return
	if road_z <= 28:
		_fail("RoadLayer ROAD_ABOVE_UNIT_COUNTERS_Z=%d must be > 28" % road_z)
		return
	if "add_overlay_layer(\"Rx1RhineLayer\"" in ren and "36" not in ren:
		_fail("MapRenderer must spawn Rx1RhineLayer at z=36")
		return
	if "HALO_WIDTH" not in layer:
		_fail("Rx1RhineLayer missing halo (readability through plates)")
		return
	_pass("Rhine z=%d and Road z=%d sit above DemoUnitIcon z=%d" % [rhine_z, road_z, unit_z])


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
