extends SceneTree

## Prove the LIVE day-tick path for RX-1 Build Bridge (same FIX3 calendar
## hook as IX-1): TimeManager.advance_real_time under stay-alive, NOT
## IDM.advance_daily_projects and NOT a drained F5 flush shortcut.
##
## Must FAIL on 1d092a14 (no RX-1 project / no calendar hook usage here)
## and PASS on the RX-1 tip: 0% → >0 within ~5 live days → COMPLETE.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRx1RhineLiveStayAliveTickTest.gd

const SRC_TM := "res://scripts/autoload/TimeManager.gd"
const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TR := "res://scripts/core/TestRunner.gd"
const HUB_ID := 710413
const OTHER_ID := 710412

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRx1RhineLiveStayAliveTickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRx1RhineLiveStayAliveTickTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


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


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessRx1RhineLiveStayAliveTickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRx1RhineLiveStayAliveTickTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_calendar_tick_not_flush()
	_test_source_live_press_and_guard()
	_test_stay_alive_advance_real_time_ticks_bridge()


func _test_source_calendar_tick_not_flush() -> void:
	var tm := _read(SRC_TM)
	var adv := _slice_func(tm, "advance_days")
	if "_tick_live_construction_on_calendar_day" not in adv:
		_fail("advance_days light path must call _tick_live_construction_on_calendar_day")
		return
	var tick := _slice_func(tm, "_tick_live_construction_on_calendar_day")
	if "advance_daily_projects" not in tick:
		_fail("calendar construction tick must call IDM.advance_daily_projects")
		return
	_pass("light-sim calendar ticks IDM even when stay-alive drops day_emit")


func _test_source_live_press_and_guard() -> void:
	var ren := _read(SRC_REN)
	var tr := _read(SRC_TR)
	if "deliver_rx1_bridge_button_mouse_press" not in ren:
		_fail("viewport mouse press helper missing")
		return
	if "try_start_rhine_bridge(" in _slice_func(ren, "deliver_rx1_bridge_button_mouse_press"):
		_fail("deliver_rx1_bridge_button_mouse_press must not call IDM directly")
		return
	if "EOA_SMOKE_RX1_LIVE_PROGRESS" not in tr:
		_fail("TestRunner live-progress guard missing")
		return
	var pump := _slice_func(tr, "_tick_smoke_rx1_live_progress")
	if "advance_real_time" not in pump:
		_fail("live-progress guard must drive advance_real_time")
		return
	if "advance_daily_projects" in pump:
		_fail("live-progress guard must not call IDM.advance_daily_projects")
		return
	if "_drain_living_f5_flush" in pump:
		_fail("live-progress guard must not drain the F5 flush shortcut")
		return
	var quit_fn := _slice_func(tr, "_quit_logged")
	if "rx1_live_progress" not in quit_fn:
		_fail("stay-alive must not swallow rx1_live_progress quit")
		return
	_pass("live press + guard stay on MapRenderer.button / advance_real_time")


func _test_stay_alive_advance_real_time_ticks_bridge() -> void:
	var tm: Node = _autoload("TimeManager")
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if tm == null or idm == null:
		_fail("TimeManager / IDM autoload missing")
		return
	if not idm.has_method("restore_project") or not tm.has_method("advance_real_time"):
		_fail("restore_project / advance_real_time missing")
		return
	Rx1RhineCrossing.ensure_loaded()
	Rx1RhineCrossing.reset_to_1936()
	if idm.has_method("initialize_with_time"):
		idm.call("initialize_with_time")
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-08")
	if idm.has_method("cancel_project") and bool(idm.call("has_active_project", HUB_ID)):
		idm.call("cancel_project", HUB_ID, "rx1_live_stay_alive_tick_reset")
	idm.call("restore_project", HUB_ID, {
		"province_id": HUB_ID,
		"axis": "infrastructure",
		"owner_tag": "GER",
		"starting_level": 4,
		"target_level": 4,
		"progress": 0.0,
		"work_per_day_base": 2.8,
		"days_remaining": 36,
		"status": "active",
		"build_rhine_bridge": true,
		"bridge_edge": [HUB_ID, OTHER_ID],
	})
	tm.set("_live_f5_equiv_clock", true)
	tm.set("_smoke_stay_alive", true)
	tm.set("_pending_sim_events", [])
	if tm.has_method("set_time_scale"):
		tm.call("set_time_scale", 4.0)
	if tm.has_method("set_paused"):
		tm.call("set_paused", false)
	var start_elapsed := int(tm.call("get_total_days_elapsed")) if tm.has_method("get_total_days_elapsed") else 0
	var start_prog := _bridge_progress(idm)
	var i := 0
	while i < 36:
		tm.call("advance_real_time", 1.0)
		i += 1
	var mid_elapsed := int(tm.call("get_total_days_elapsed")) if tm.has_method("get_total_days_elapsed") else 0
	var mid_prog := _bridge_progress(idm)
	var days5 := mid_elapsed - start_elapsed
	if days5 < 5:
		_fail("advance_real_time under stay-alive did not roll 5 calendar days (delta=%d)" % days5)
		_cleanup_stay_alive(tm, idm)
		return
	if mid_prog <= start_prog + 0.001:
		_fail(
			"GAP: stay-alive calendar +%dd but IDM Rhine bridge still %.1f%% (day_emit dropped, construction not on calendar roll)"
			% [days5, mid_prog]
		)
		_cleanup_stay_alive(tm, idm)
		return
	var last_prog := mid_prog
	while i < 260:
		tm.call("advance_real_time", 1.0)
		i += 1
		last_prog = _bridge_progress(idm)
		if not bool(idm.call("has_active_project", HUB_ID)):
			break
	var still_active := bool(idm.call("has_active_project", HUB_ID))
	var visual := ""
	if idm.has_method("get_rx1_bridge_visual_state"):
		visual = str(idm.call("get_rx1_bridge_visual_state"))
	var bridged := Rx1RhineCrossing.is_bridged(HUB_ID, OTHER_ID)
	if visual == "built" or bridged or not still_active:
		last_prog = 100.0
	_cleanup_stay_alive(tm, idm)
	if not bridged and visual != "built":
		_fail("Rhine bridge did not COMPLETE after live stay-alive clock (pct=%.1f state=%s active=%s bridged=%s)" % [last_prog, visual, str(still_active), str(bridged)])
		return
	_pass(
		"stay-alive advance_real_time +%dd %.1f%% → COMPLETE bridged=1 (NOT product Begin/Esc/clock PASS)"
		% [days5, start_prog]
	)


func _bridge_progress(idm: Node) -> float:
	if not idm.has_method("get_project_status"):
		return 0.0
	var st: Dictionary = idm.call("get_project_status", HUB_ID) as Dictionary
	return float(st.get("progress", 0.0))


func _cleanup_stay_alive(tm: Node, idm: Node) -> void:
	if tm.has_method("reset_smoke_stay_alive_for_tests"):
		tm.call("reset_smoke_stay_alive_for_tests")
	tm.set("_smoke_stay_alive", false)
	tm.set("_live_f5_equiv_clock", false)
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if idm.has_method("cancel_project") and bool(idm.call("has_active_project", HUB_ID)):
		idm.call("cancel_project", HUB_ID, "rx1_live_stay_alive_tick_done")
	Rx1RhineCrossing.reset_to_1936()
