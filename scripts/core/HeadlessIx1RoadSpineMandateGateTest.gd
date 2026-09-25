extends SceneTree

## Prove IX-1 Build Road Spine Mandate gate passes at GER 1936 day-0 (Mandate 0).
## Does not require the 3520 board. Live try_start is extra if Köln is loaded.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1RoadSpineMandateGateTest.gd

const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const HUB_ID := 710417

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessIx1RoadSpineMandateGateTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessIx1RoadSpineMandateGateTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessIx1RoadSpineMandateGateTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_uses_starter_cost()
	_test_day0_mandate_gate()
	_test_try_start_if_koln_loaded()


func _test_source_uses_starter_cost() -> void:
	if not FileAccess.file_exists(SRC_IDM):
		_fail("InfrastructureDevelopmentManager.gd missing")
		return
	var f := FileAccess.open(SRC_IDM, FileAccess.READ)
	if f == null:
		_fail("cannot read InfrastructureDevelopmentManager.gd")
		return
	var text := f.get_as_text()
	f.close()
	if "get_ix1_road_spine_mandate_cost" not in text:
		_fail("IDM missing get_ix1_road_spine_mandate_cost")
		return
	if "ix1_day0_mandate_can_start" not in text:
		_fail("IDM missing ix1_day0_mandate_can_start")
		return
	if "IX1_FIRST_SESSION_MANDATE_COST" not in text:
		_fail("IDM missing IX1_FIRST_SESSION_MANDATE_COST")
		return
	if "start_road_spine_project" not in text:
		_fail("IDM missing start_road_spine_project (Invest-gated start is a live no-op)")
		return
	var spine_fn := text.find("func try_start_road_spine")
	if spine_fn < 0:
		_fail("try_start_road_spine missing")
		return
	var next_fn := text.find("\nfunc ", spine_fn + 10)
	var body := text.substr(spine_fn, next_fn - spine_fn if next_fn > spine_fn else text.length() - spine_fn)
	if "can_start_project(" in body:
		_fail("try_start_road_spine still uses generic Invest can_start_project")
		return
	if "preview.get(\"cost_pp\"" in body:
		_fail("try_start_road_spine still spends generic Invest cost_pp")
		return
	if "start_road_spine_project" not in body:
		_fail("try_start_road_spine does not call start_road_spine_project")
		return
	_pass("IDM IX-1 Mandate cost uses first-session starter API")


func _test_day0_mandate_gate() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("ix1_day0_mandate_can_start"):
		_fail("ix1_day0_mandate_can_start missing")
		return
	if not idm.has_method("get_ix1_road_spine_mandate_cost"):
		_fail("get_ix1_road_spine_mandate_cost missing")
		return
	var cost := int(idm.call("get_ix1_road_spine_mandate_cost"))
	var gate: Dictionary = idm.call("ix1_day0_mandate_can_start", "GER")
	if cost != 0:
		_fail("IX-1 first-session cost is %d, expected 0" % cost)
		return
	if not bool(gate.get("ok", false)):
		_fail("GER 1936 day-0 Mandate gate failed: %s" % str(gate))
		return
	if int(gate.get("mandate", -1)) < int(gate.get("cost", 999)):
		_fail("Mandate %s < cost %s" % [str(gate.get("mandate")), str(gate.get("cost"))])
		return
	_pass("GER 1936 day-0 Mandate gate ok mandate=%s cost=%s" % [str(gate.get("mandate")), str(gate.get("cost"))])


func _test_try_start_if_koln_loaded() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	var mm: Node = _autoload("MapManager")
	if idm == null or mm == null or not mm.has_method("get_province"):
		_pass("Köln not loaded — Mandate gate already asserted")
		return
	var p: Variant = mm.call("get_province", HUB_ID)
	if p == null:
		_pass("Köln 710417 not on board — Mandate gate already asserted")
		return
	if not idm.has_method("try_start_road_spine"):
		_fail("try_start_road_spine missing")
		return
	var result: Dictionary = idm.call("try_start_road_spine", HUB_ID, "GER")
	var reason := str(result.get("reason", ""))
	if reason.begins_with("Insufficient Mandate"):
		_fail("try_start_road_spine still Mandate-blocked: %s" % reason)
		return
	if bool(result.get("success", false)):
		_pass("try_start_road_spine started on Köln at day-0 Mandate")
		return
	# Ownership / era / missing map are not this FIX; Mandate must not be the reason.
	_pass("try_start_road_spine not Mandate-blocked (reason=%s)" % reason)
