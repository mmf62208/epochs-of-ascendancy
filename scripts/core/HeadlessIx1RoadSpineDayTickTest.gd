extends SceneTree

## Prove the F5 day clock advances with an IX-1 Road Spine in progress
## past the live freeze (~day 7–9 / ~17–20%), and that a short automated
## path can complete the spine. Does not require the 3520 board.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1RoadSpineDayTickTest.gd

const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_SAVE := "res://scripts/autoload/SaveLoadManager.gd"
const SRC_TM := "res://scripts/autoload/TimeManager.gd"
const HUB_ID := 710417
const FREEZE_PROGRESS := 20.0
const LIVE_DAY_BUDGET_MS := 8000

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
	_test_source_live_f5_path_cannot_full_board_scan()
	_test_source_progress_does_not_renotify()
	_test_clock_advances_past_freeze()
	_test_spine_can_complete()
	_test_live_f5_equivalent_day_advance()
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
	if "is_live_f5_play_path" not in gate and "DisplayServer.get_name()" not in gate:
		_fail("full-board AI gate must also skip graphical editor/export Play, not only light_sim")
		return
	_pass("F5 light sim skips full-board AI invest; autosave deferred")


func _test_source_live_f5_path_cannot_full_board_scan() -> void:
	var idm := _read(SRC_IDM)
	var pick := _slice_func(idm, "_pick_ai_infra_province")
	if pick.is_empty():
		_fail("_pick_ai_infra_province missing")
		return
	if "get_all_provinces(" in pick or "get_provinces_by_owner(" in pick:
		_fail("live AI infra pick still walks get_all_provinces / get_provinces_by_owner")
		return
	if "AI_INFRA_PICK_CAP" not in pick:
		_fail("live AI infra pick must cap candidates")
		return
	var start := _slice_func(idm, "start_infrastructure_project")
	if "_should_quiet_ai_infra_start" not in start:
		_fail("AI infra start must quiet toast/notify on live F5")
		return
	var sim := _slice_func(idm, "simulate_live_f5_day_advance")
	if sim.is_empty() or "advance_live_f5_equivalent_days" not in sim:
		_fail("simulate_live_f5_day_advance must drive live-equiv days (not playtest clock)")
		return
	if "living_playtest_clock" in sim and "advance_living_playtest_days" in sim:
		_fail("live-equiv sim must not use advance_living_playtest_days")
		return
	var tm := _read(SRC_TM)
	var live := _slice_func(tm, "advance_live_f5_equivalent_days")
	if live.is_empty() or "_living_playtest_clock = true" in live:
		_fail("advance_live_f5_equivalent_days must not set _living_playtest_clock")
		return
	if "_live_f5_equiv_clock = true" not in live:
		_fail("advance_live_f5_equivalent_days must set _live_f5_equiv_clock")
		return
	var rings := _slice_func(_read(SRC_REN), "_refresh_feature_progress_rings")
	if "is_interactive_light_sim" not in rings:
		_fail("feature-ring day walk must early-out on F5 light sim")
		return
	_pass("live F5 path cannot full-board AI scan; toast quiet; ring walk gated")


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
	# Continue the same Köln project (already past 20%) on the cheap daily tick.
	# A second F5 flush of 30d OOMs air/day listeners; complete does not need that path.
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = idm.call("simulate_ix1_spine_days", 30, false)
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


func _test_live_f5_equivalent_day_advance() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("simulate_live_f5_day_advance"):
		_fail("simulate_live_f5_day_advance missing")
		return
	if idm.has_method("initialize_with_time"):
		idm.call("initialize_with_time")
	var tm: Node = _autoload("TimeManager")
	if tm != null and tm.has_method("is_live_f5_play_path"):
		# Before the run, headless without the equiv flag is not Play.
		pass
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = idm.call("simulate_live_f5_day_advance", 5)
	var ms := Time.get_ticks_msec() - t0
	var elapsed := int(result.get("elapsed_delta", 0))
	var consider := int(result.get("full_board_ai_invest_calls", -1))
	var gate_on := bool(result.get("full_board_ai_invest", true))
	var considered := int(result.get("provinces_considered", 9999))
	if not bool(result.get("ok", false)):
		_fail("live-F5-equiv day advance not ok: %s" % str(result))
		return
	if elapsed < 5:
		_fail("live-F5-equiv clock did not advance 5 days (elapsed_delta=%d) %s" % [elapsed, str(result)])
		return
	if not bool(result.get("past_plus2", false)):
		_fail("live-F5-equiv did not prove past day +2: %s" % str(result))
		return
	if consider != 0:
		_fail("full-board ai_consider_daily_invests ran %d times on live-equiv path" % consider)
		return
	if gate_on:
		_fail("live-equiv still enables _should_run_full_board_ai_invest")
		return
	if considered > 16:
		_fail("live AI infra pick considered %d provinces (cap 16)" % considered)
		return
	if ms > LIVE_DAY_BUDGET_MS:
		_fail("live-F5-equiv 5d took %dms (wedged)" % ms)
		return
	if bool(result.get("living_playtest_clock", true)):
		_fail("live-equiv result must not claim living_playtest_clock")
		return
	_pass(
		"live-F5-equiv +%dd past+2 consider=%d pick=%d (%dms)"
		% [elapsed, consider, considered, ms]
	)


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
