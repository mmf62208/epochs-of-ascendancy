extends SceneTree

## STABILITY-JUSTICE-1. Flag default off. Player stability and a 30-day
## justification on the shipped apply_war_goal_justify / apply_war_goal_execute path.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessStabilityJustice1Test.gd

const OFF_SEED := "20fe9063de285f19d4f9b8a105abfd31"
const PID := 710739

var _failures: int = 0
var _sj: GDScript


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessStabilityJustice1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessStabilityJustice1Test: ", msg)


func _run() -> void:
	_sj = load("res://scripts/core/StabilityJusticeDomain.gd") as GDScript
	var gd := root.get_node_or_null("GameData")
	if gd == null or _sj == null:
		_fail("GameData or StabilityJusticeDomain missing")
		_finish()
		return
	_test_accessor(gd)
	_test_flag_off(gd)
	_test_flag_on(gd)
	_test_save_roundtrip(gd)
	_test_drift_clamp(gd)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessStabilityJustice1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessStabilityJustice1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _test_accessor(gd: Node) -> void:
	for bad in ["", "0", "true", "yes", "on", "TRUE"]:
		OS.set_environment("EOA_STABILITY_JUSTICE", bad)
		if bool(gd.call("stability_justice_enabled")):
			_fail("flag on for value '%s'" % bad)
			return
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	if not bool(gd.call("stability_justice_enabled")):
		_fail("flag stayed off for EOA_STABILITY_JUSTICE=1")
		return
	_pass("accessor is on only for EOA_STABILITY_JUSTICE=1")


func _test_flag_off(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "")
	_sj.call("clear_state")
	if bool(gd.call("stability_justice_enabled")):
		_fail("flag off check left the accessor on")
		return
	gd.call("apply_war_goal_justify", PID)
	gd.call("apply_war_goal_execute", PID)
	gd.call("stability_justice_tick_day")
	if bool(_sj.call("has_state")) or bool(gd.peace_state.has("stability_justice")):
		_fail("flag off created stability state")
		return
	var save: Dictionary = gd.call("get_save_data")
	if save.has("stability_justice"):
		_fail("flag off save gained stability_justice")
		return
	if str(gd.call("stability_justice_chip_line")) != "":
		_fail("flag off chip line is not empty")
		return
	if not is_equal_approx(float(gd.call("stability_justice_output_multiplier", "GER")), 1.0):
		_fail("flag off production multiplier is not 1")
		return
	var scale: Dictionary = gd.call("stability_justice_supply_scale")
	if bool(scale.get("apply", false)):
		_fail("flag off supply scale applied")
		return
	var seed_line := str(_sj.get("OFF_SEED_BASELINE"))
	print("HeadlessStabilityJustice1Test: seed_line=%s" % seed_line)
	if seed_line != OFF_SEED:
		_fail("seed line %s != OFF baseline %s" % [seed_line, OFF_SEED])
		return
	_pass("flag off: no stability state, seed line %s" % seed_line)


func _test_flag_on(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	_sj.call("clear_state")
	var started: Dictionary = gd.call("apply_war_goal_justify", PID)
	if int(started.get("justify_days_done", -1)) != 1 or bool(started.get("justify_complete", true)):
		_fail("justify start days=%s complete=%s" % [str(started.get("justify_days_done")), str(started.get("justify_complete"))])
		return
	if "1/30" not in str(started.get("summary", "")):
		_fail("justify summary missing progress: %s" % str(started.get("summary", "")))
		return
	for _i in range(29):
		gd.call("stability_justice_tick_day")
	var just: Dictionary = _sj.call("justify_status")
	if int(just.get("days_done", -1)) != 30 or not bool(just.get("complete", false)):
		_fail("justify did not complete: %s" % str(just))
		return
	var before := float(_sj.call("stability"))
	var declared: Dictionary = gd.call("apply_war_goal_execute", PID)
	var after := float(_sj.call("stability"))
	if not is_equal_approx(after, before) or bool(declared.get("stability_penalized", true)):
		_fail("justified declare changed stability %s -> %s penalized=%s" % [before, after, str(declared.get("stability_penalized"))])
		return
	_pass("justify completes in 30 days and a justified declare is free")

	_sj.call("clear_state")
	var unjust: Dictionary = gd.call("apply_war_goal_execute", PID)
	var dropped := float(_sj.call("stability"))
	if not is_equal_approx(dropped, 0.85) or not bool(unjust.get("stability_penalized", false)):
		_fail("unjustified declare stability=%s penalized=%s" % [dropped, str(unjust.get("stability_penalized"))])
		return
	_pass("unjustified declare costs 0.15 stability")

	_sj.call("import_save_blob", {"stability": 0.0, "justify": {"active": false}})
	var player := str(_sj.call("player_tag"))
	if not is_equal_approx(float(gd.call("stability_justice_output_multiplier", player)), 0.75):
		_fail("stability 0 multiplier %s" % str(gd.call("stability_justice_output_multiplier", player)))
		return
	if not is_equal_approx(float(gd.call("stability_justice_output_multiplier", "FRA")), 1.0):
		_fail("non-player multiplier changed")
		return
	_sj.call("import_save_blob", {"stability": 0.5, "justify": {"active": false}})
	if not is_equal_approx(float(_sj.call("output_multiplier_for_tag", player)), 1.0):
		_fail("stability 0.5 should not slow production")
		return
	_sj.call("import_save_blob", {"stability": 0.25, "justify": {"active": false}})
	if not is_equal_approx(float(_sj.call("output_multiplier_for_tag", player)), 0.875):
		_fail("stability 0.25 multiplier %s" % str(_sj.call("output_multiplier_for_tag", player)))
		return
	var low: Dictionary = gd.call("stability_justice_supply_scale")
	if not bool(low.get("apply", false)) or not is_equal_approx(float(low.get("multiplier", 0.0)), 0.875):
		_fail("supply scale at 0.25: %s" % str(low))
		return
	var chip := str(gd.call("stability_justice_chip_line"))
	if not chip.begins_with("Stability "):
		_fail("chip line missing: %s" % chip)
		return
	_pass("low-stability multiplier and chip line")


func _test_save_roundtrip(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	_sj.call("clear_state")
	gd.peace_state["occupation_province"] = {
		"1": {"resistance_level": 1.0},
	}
	gd.call("apply_war_goal_justify", PID)
	for _i in range(9):
		gd.call("stability_justice_tick_day")
	var expect_stab := float(_sj.call("stability"))
	var expect_days := int((_sj.call("justify_status") as Dictionary).get("days_done", -1))
	if expect_days != 10:
		_fail("roundtrip setup days=%d" % expect_days)
		return
	if expect_stab >= 1.0:
		_fail("occupation drift did not lower stability (%s)" % expect_stab)
		return
	var save: Dictionary = gd.call("get_save_data")
	if not (save.get("stability_justice") is Dictionary):
		_fail("flag on save missing stability_justice")
		return
	_sj.call("clear_state")
	if bool(_sj.call("has_state")):
		_fail("clear_state left stability state")
		return
	gd.call("apply_save_data", save)
	var loaded := float(_sj.call("stability"))
	var days := int((_sj.call("justify_status") as Dictionary).get("days_done", -1))
	if not is_equal_approx(loaded, expect_stab) or days != expect_days:
		_fail("roundtrip stability %s vs %s days %d vs %d" % [loaded, expect_stab, days, expect_days])
		return
	_pass("flag on save/load roundtrip stability=%.4f justify=%d/30" % [loaded, days])

	_sj.call("import_save_blob", {"stability": 0.2, "justify": {"active": true, "province_id": PID, "days_done": 4, "complete": false}})
	gd.call("apply_save_data", {"version": 1})
	if bool(_sj.call("has_state")) or not is_equal_approx(float(_sj.call("stability")), 1.0):
		_fail("pre-flag load stability=%s state=%s" % [str(_sj.call("stability")), str(_sj.call("has_state"))])
		return
	var just: Dictionary = _sj.call("justify_status")
	if bool(just.get("active", true)) or int(just.get("days_done", -1)) != 0:
		_fail("pre-flag load kept a justification %s" % str(just))
		return
	var partial := {"stability": 0.4}
	_sj.call("import_save_blob", partial)
	if not is_equal_approx(float(_sj.call("stability")), 0.4):
		_fail("missing justify subkey did not default")
		return
	var partial_just: Dictionary = _sj.call("justify_status")
	if bool(partial_just.get("active", true)):
		_fail("missing justify subkey started a justification")
		return
	_pass("pre-flag save loads at stability 1.0 with no justification")


func _test_drift_clamp(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	_sj.call("clear_state")
	var player := str(_sj.call("player_tag"))
	gd.peace_state["campaign_wars"] = {
		"wars": {"AAA|%s" % player: {"a": "AAA", "b": player}},
		"truces": {},
		"log": [],
		"justifies": {},
		"booted": true,
	}
	gd.peace_state["occupation_province"] = {
		"9": {"resistance_level": 1.0},
	}
	gd.call("apply_war_goal_execute", 1)
	var guard := 0
	while float(_sj.call("stability")) > 0.0 and guard < 800:
		gd.call("stability_justice_tick_day")
		guard += 1
	if not is_equal_approx(float(_sj.call("stability")), 0.0):
		_fail("drift did not clamp at 0 after %d ticks (stability=%s)" % [guard, str(_sj.call("stability"))])
		return
	gd.call("stability_justice_tick_day")
	if float(_sj.call("stability")) < 0.0:
		_fail("stability went below 0")
		return
	gd.peace_state["campaign_wars"] = {
		"wars": {},
		"truces": {},
		"log": [],
		"justifies": {},
		"booted": true,
	}
	gd.peace_state["occupation_province"] = {}
	guard = 0
	while float(_sj.call("stability")) < 1.0 and guard < 2000:
		gd.call("stability_justice_tick_day")
		guard += 1
	if not is_equal_approx(float(_sj.call("stability")), 1.0):
		_fail("recovery did not clamp at 1 after %d ticks (stability=%s)" % [guard, str(_sj.call("stability"))])
		return
	gd.call("stability_justice_tick_day")
	if float(_sj.call("stability")) > 1.0:
		_fail("stability went above 1")
		return
	_pass("drift stays clamped to 0..1")
