extends SceneTree

## FIX2 panel-state: Köln never re-offers Build Road Spine after built;
## bridge chrome only on Neuss 710413 / Mettmann 710412.
## Must FAIL on 816cdc9 (should_show still true after built; no bridge scope)
## and PASS on the tip.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRx1RhinePanelStateTest.gd

const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const KOELN_ID := 710417
const BONN_ID := 710416
const LEV_ID := 710418
const NEUSS_ID := 710413
const METTMANN_ID := 710412
const ESSEN_ID := 710403

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRx1RhinePanelStateTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRx1RhinePanelStateTest: ", msg)


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
	print("HeadlessRx1RhinePanelStateTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRx1RhinePanelStateTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_gates()
	_test_runtime_scope()


func _test_source_gates() -> void:
	var idm := _read(SRC_IDM)
	var ren := _read(SRC_REN)
	if "func is_ix1_road_spine_built" not in idm:
		_fail("IDM missing is_ix1_road_spine_built")
		return
	if "Never re-offer" not in idm:
		_fail("should_show_road_spine_button must refuse a built corridor")
		return
	if "func inspector_should_show_bridge_status" not in ren:
		_fail("MapRenderer missing inspector_should_show_bridge_status")
		return
	if "func _show_ix1_spine_built_state" not in ren:
		_fail("MapRenderer missing _show_ix1_spine_built_state")
		return
	if "710413" not in ren or "710412" not in ren:
		_fail("bridge status must name Neuss 710413 and Mettmann 710412")
		return
	if "Do not fall through after a false" not in ren:
		_fail("_ix1_should_show_spine_button must not fall through after should_show=false")
		return
	_pass("source: built helper + no re-offer + bridge scope")


func _test_runtime_scope() -> void:
	var idm: Node = root.get_node_or_null("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("is_ix1_road_spine_built"):
		_fail("is_ix1_road_spine_built missing at runtime")
		return
	if not idm.has_method("should_show_road_spine_button"):
		_fail("should_show_road_spine_button missing")
		return
	# Day-0 Köln still offers the button when the corridor is not built.
	var mm: Node = root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province"):
		var koln: Variant = mm.call("get_province", KOELN_ID)
		if koln != null and not bool(idm.call("is_ix1_road_spine_built", KOELN_ID)):
			if not bool(idm.call("should_show_road_spine_button", KOELN_ID, "GER")):
				_fail("day-0 Köln must still offer Build Road Spine")
				return
	if bool(idm.call("should_show_road_spine_button", ESSEN_ID, "GER")):
		_fail("Essen must not offer Build Road Spine")
		return
	if idm.has_method("link_ix1_road_spine_edges"):
		idm.call("link_ix1_road_spine_edges", KOELN_ID, [BONN_ID, LEV_ID])
	if mm != null and mm.has_method("get_province"):
		if mm.call("get_province", KOELN_ID) != null:
			if not bool(idm.call("is_ix1_road_spine_built", KOELN_ID)):
				_fail("is_ix1_road_spine_built(710417) false after link")
				return
			if bool(idm.call("should_show_road_spine_button", KOELN_ID, "GER")):
				_fail("should_show_road_spine_button still true after built")
				return
			if bool(idm.call("is_ix1_road_spine_built", NEUSS_ID)):
				_fail("is_ix1_road_spine_built(710413) must be false")
				return
	var mr_nodes: Array = get_nodes_in_group("map_renderer")
	var mr: Node = mr_nodes[0] as Node if mr_nodes.size() > 0 else null
	if mr != null and mr.has_method("inspector_should_show_bridge_status"):
		if bool(mr.call("inspector_should_show_bridge_status", KOELN_ID)):
			_fail("inspector_should_show_bridge_status(710417) must be false")
			return
		if not bool(mr.call("inspector_should_show_bridge_status", NEUSS_ID)):
			_fail("inspector_should_show_bridge_status(710413) must be true")
			return
		if not bool(mr.call("inspector_should_show_bridge_status", METTMANN_ID)):
			_fail("inspector_should_show_bridge_status(710412) must be true")
			return
		if bool(mr.call("inspector_should_show_spine_status", NEUSS_ID)):
			_fail("inspector_should_show_spine_status(710413) must be false")
			return
	_pass("runtime: Köln built hides button; bridge scoped to Neuss/Mettmann")
