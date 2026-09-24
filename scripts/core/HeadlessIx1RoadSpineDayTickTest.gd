extends SceneTree

## Prove the F5 day clock advances with an IX-1 Road Spine in progress
## past the live freeze (~day 7–9 / ~17–20%), and that a short automated
## path can complete the spine. Does not require the 3520 board.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1RoadSpineDayTickTest.gd

const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_SAVE := "res://scripts/autoload/SaveLoadManager.gd"
const HUB_ID := 710417
const FREEZE_PROGRESS := 20.0

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessIx1RoadSpineDayTickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessIx1RoadSpineDayTickTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessIx1RoadSpineDayTickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessIx1RoadSpineDayTickTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_gates_full_board_ai_invest()
	_test_source_progress_does_not_renotify()
	_test_clock_advances_past_freeze()
	_test_spine_can_complete()
	_test_mandate_cost_still_zero()


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


func _test_source_gates_full_board_ai_invest() -> void:
	var idm := _read(SRC_IDM)
	if idm.is_empty():
		_fail("InfrastructureDevelopmentManager.gd missing")
		return
	var gate := _slice_func(idm, "_should_run_full_board_ai_invest")
	var adv := _slice_func(idm, "advance_daily_projects")
	if "is_interactive_light_sim" not in gate:
		_fail("_should_run_full_board_ai_invest must gate on F5 light sim")
		return
	if "_should_run_full_board_ai_invest" not in adv:
		_fail("advance_daily_projects must consult the light-sim AI-invest gate")
		return
	if "ai_consider_daily_invests" not in adv:
		_fail("advance_daily_projects lost ai_consider_daily_invests (harness path)")
		return
	var save := _read(SRC_SAVE)
	if "_deferred_calendar_autosave" not in save:
		_fail("calendar autosave must be deferred off day_emit")
		return
	_pass("F5 light sim skips full-board AI invest; autosave deferred")


func _test_source_progress_does_not_renotify() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var prog := _slice_func(ren, "_on_infra_progress_for_inspector")
	if prog.is_empty():
		_fail("_on_infra_progress_for_inspector missing")
		return
	if "notify_province_changed(" in prog:
		_fail("progress handler still notify_province_changed (inspector rebuild loop)")
		return
	var changed := _slice_func(ren, "_on_map_province_data_changed")
	if "selected_province_id" not in changed or "infrastructure_project" not in changed:
		_fail("province_data_changed must light-refresh only the selected spine hex")
		return
	_pass("spine progress no longer re-enters show_info_panel via notify")


func _test_clock_advances_past_freeze() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("simulate_ix1_spine_days"):
		_fail("simulate_ix1_spine_days missing")
		return
	if idm.has_method("initialize_with_time"):
		idm.call("initialize_with_time")
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = idm.call("simulate_ix1_spine_days", 12)
	var ms := Time.get_ticks_msec() - t0
	var elapsed := int(result.get("elapsed_delta", 0))
	var after := float(result.get("progress_after", 0.0))
	var before := float(result.get("progress_before", 0.0))
	if elapsed < 12:
		_fail("clock did not advance 12 days with spine active (elapsed_delta=%d) %s" % [elapsed, str(result)])
		return
	if after <= before and not bool(result.get("completed", false)):
		_fail("spine progress did not increase: %.1f → %.1f" % [before, after])
		return
	if after <= FREEZE_PROGRESS and not bool(result.get("past_freeze", false)):
		_fail("spine still at freeze point (%.1f%%)" % after)
		return
	if ms > 20000:
		_fail("12-day spine tick took %dms (still wedged)" % ms)
		return
	_pass(
		"clock +12d spine %.1f%% → %.1f%% past_freeze=%s (%dms)"
		% [before, after, str(result.get("past_freeze")), ms]
	)


func _test_spine_can_complete() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	# Continue the same Köln project (already past 20%) until days_remaining hits 0.
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = idm.call("simulate_ix1_spine_days", 30)
	var ms := Time.get_ticks_msec() - t0
	var completed := bool(result.get("completed", false))
	var after := float(result.get("progress_after", 0.0))
	if not completed and after < 99.0:
		_fail("spine did not complete on short path: %s" % str(result))
		return
	if ms > 45000:
		_fail("complete path took %dms" % ms)
		return
	_pass("spine complete=%s progress=%.1f elapsed_delta=%s (%dms)" % [
		str(completed or after >= 99.0), after, str(result.get("elapsed_delta")), ms
	])


func _test_mandate_cost_still_zero() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("get_ix1_road_spine_mandate_cost"):
		_fail("get_ix1_road_spine_mandate_cost missing")
		return
	var cost := int(idm.call("get_ix1_road_spine_mandate_cost"))
	if cost != 0:
		_fail("Mandate front door regress: cost=%d" % cost)
		return
	var gate: Dictionary = idm.call("ix1_day0_mandate_can_start", "GER")
	if not bool(gate.get("ok", false)):
		_fail("GER 1936 day-0 Mandate gate failed after day-tick FIX: %s" % str(gate))
		return
	_pass("Mandate front door still 0 / day-0 gate ok")
