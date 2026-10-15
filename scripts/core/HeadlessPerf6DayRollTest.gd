extends SceneTree

## PERF-6: the AI soft-supply full day is queued on the roll and sliced on
## later frames. Production harvest and reinforce no longer share a 1x day.
## FIX #1: atomic phases yield unless remaining budget >= last cost + 2 ms;
## generate/ship items also keep a 5 ms reserve so a last step + GC stays
## under the 25 ms cap. The cap itself is unchanged.
## FIX #2: the first phase/item of a frame always runs (progress guarantee);
## phase estimates EMA-blend on run and decay toward the floor when deferred.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessPerf6DayRollTest.gd
##
## FAILS on simulated M3 (sync supply day inside day_ai). PASSES on the tip.
## Headless only. Live Play A/B is not this harness.

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const DEPOT_SCRIPT := "res://scripts/supply/ProvinceDepotState.gd"
const DAYS := 12
const DAY_AI_P95_MS := 40.0
const DAY_AI_MAX_MS := 60.0
const SLICE_MAX_MS := 25.0
const LISTENER_MAX_MS := 30.0
const DEPOT_TOL := 0.000001
const GAPS_BETWEEN_TICKS := 2

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf6DayRollTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf6DayRollTest: ", msg)


func _run_and_quit() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf6DayRollTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf6DayRollTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _run() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	var tm: Node = root.get_node_or_null("/root/TimeManager")
	var sm: Node = root.get_node_or_null("/root/SupplyManager")
	var pm: Node = root.get_node_or_null("/root/ProductionManager")
	var lm: Node = root.get_node_or_null("/root/LeaderManager")
	var sp: Node = root.get_node_or_null("/root/SessionPlayers")
	if mm == null or tm == null or sm == null or pm == null:
		_fail("autoloads missing")
		return
	if not _load_accurate_board(mm):
		_fail("board load failed")
		return
	var n_prov := int(mm.call("get_province_count")) if mm.has_method("get_province_count") else 0
	if n_prov < 3000:
		_fail("too_few_provinces=%d" % n_prov)
		return
	_pass("loaded_provinces=%d" % n_prov)
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "GER")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var depots := _boot_live_supply_network(mm, sm)
	if depots < 2000:
		_fail("live-weight depots too few (%d)" % depots)
		return
	_pass("live-weight depots=%d" % depots)
	var has_queue := sm.has_method("queue_full_supply_day") and sm.has_method("supply_day_queue_depth")
	if not has_queue:
		_fail("queue_full_supply_day missing (sync roll-frame supply day)")
	else:
		_test_depot_equality(sm)
		_test_atomic_phase_defer(sm)
		_test_generate_step_bound(sm)
		_test_production_totals(pm, tm)
	await _test_clock(tm, sm, pm, 1.0, true)
	await _test_clock(tm, sm, pm, 4.0, false)
	if has_queue:
		await _test_catch_up(tm, sm)


func _test_depot_equality(sm: Node) -> void:
	var base := _snap_depots(sm)
	seed(193601)
	sm.call("queue_full_supply_day", 1.0)
	var guard := 0
	while int(sm.call("supply_day_queue_depth")) > 0 and guard < 80:
		sm.call("_drain_queued_supply_day_slice")
		guard += 1
	var queued_left := int(sm.call("supply_day_queue_depth"))
	var queued_snap := _snap_depots(sm)
	_restore_depots(sm, base)
	seed(193601)
	sm.call("advance_supply_day", 1.0)
	var sync_snap := _snap_depots(sm)
	var diff := _depot_diff(queued_snap, sync_snap)
	print(
		"HeadlessPerf6DayRollTest: depot_equality drains=%d queued_left=%d diff=%s"
		% [guard, queued_left, diff if not diff.is_empty() else "none"]
	)
	if queued_left != 0:
		_fail("direct drain left %d supply days" % queued_left)
	elif not diff.is_empty():
		_fail("queued slices != sync supply day (%s)" % diff)
	else:
		_pass("queued slices match sync supply day within 1e-6")
	_restore_depots(sm, base)
	sm.set("full_supply_day_count", 0)
	sm.set("_supply_day_queue", [])


func _test_atomic_phase_defer(sm: Node) -> void:
	# Deadline logic, not wall-clock speed: a 12 ms naval phase must not start
	# with 3 ms remaining, and deadline 0 (sync / catch-up) must still run.
	if not sm.has_method("_supply_slice_cannot_afford_phase"):
		_fail("atomic phase afford helper missing")
		return
	if not sm.has_method("_make_supply_day_job") or not sm.has_method("_run_supply_day_job"):
		_fail("supply-day job runner missing")
		return
	var now := Time.get_ticks_usec()
	var tight: int = now + 3000
	var wide: int = now + 50000
	var cannot_tight := bool(sm.call("_supply_slice_cannot_afford_phase", tight, 12.0))
	var cannot_sync := bool(sm.call("_supply_slice_cannot_afford_phase", 0, 12.0))
	var cannot_wide := bool(sm.call("_supply_slice_cannot_afford_phase", wide, 12.0))
	var job: Dictionary = sm.call("_make_supply_day_job", 1.0)
	job["phase"] = 2
	job["naval_last_ms"] = 12.0
	# After some work this frame, FIX #1 still defers. The first unit of
	# work in a frame is forced (progress guarantee; see StarveTest).
	if "_supply_slice_did_work" in sm:
		sm.set("_supply_slice_did_work", true)
	var done_tight := bool(sm.call("_run_supply_day_job", job, tight))
	var phase_tight := int(job.get("phase", -1))
	var naval_tight := float(job.get("naval_ms", -1.0))
	print(
		"HeadlessPerf6DayRollTest: atomic_defer helper tight=%s sync=%s wide=%s job_done=%s phase=%d naval_ms=%.3f"
		% [str(cannot_tight), str(cannot_sync), str(cannot_wide), str(done_tight), phase_tight, naval_tight]
	)
	if not cannot_tight:
		_fail("atomic afford helper started a 12ms phase with 3ms remaining")
	elif cannot_sync:
		_fail("atomic afford helper deferred deadline 0 (sync/catch-up must run)")
	elif cannot_wide:
		_fail("atomic afford helper deferred a 12ms phase with 50ms remaining")
	elif done_tight or phase_tight != 2 or naval_tight > 0.0:
		_fail(
			"naval phase ran with 3ms remaining (done=%s phase=%d naval_ms=%.3f)"
			% [str(done_tight), phase_tight, naval_tight]
		)
	else:
		_pass("atomic naval phase deferred when remaining budget < last cost + 2ms")


func _test_generate_step_bound(sm: Node) -> void:
	# 6 ms remaining vs last generate step 8 ms: do not start another depot.
	# Old slicer only checked `now >= deadline` and would process at least one.
	if not sm.has_method("_supply_slice_cannot_afford_item"):
		_fail("generate item afford helper missing")
		return
	if not ("depot_states" in sm) or not sm.has_method("_run_supply_day_job"):
		_fail("generate bound setup missing")
		return
	var states: Dictionary = sm.depot_states
	if states.is_empty():
		_fail("generate bound needs depot keys")
		return
	var item_saved: float = float(sm.get("_supply_slice_last_item_ms")) if "_supply_slice_last_item_ms" in sm else 0.25
	var base := _snap_depots(sm)
	sm.set("_supply_slice_last_item_ms", 8.0)
	if "_supply_slice_did_work" in sm:
		sm.set("_supply_slice_did_work", true)
	var now := Time.get_ticks_usec()
	var mid: int = now + 6000
	var cannot_mid := bool(sm.call("_supply_slice_cannot_afford_item", mid, 8.0))
	var cannot_sync := bool(sm.call("_supply_slice_cannot_afford_item", 0, 8.0))
	var job: Dictionary = sm.call("_make_supply_day_job", 1.0)
	job["phase"] = 1
	job["gen_ready"] = true
	job["keys"] = states.keys()
	job["index"] = 0
	var done := bool(sm.call("_run_supply_day_job", job, mid))
	var idx := int(job.get("index", -1))
	var phase := int(job.get("phase", -1))
	sm.set("_supply_slice_last_item_ms", item_saved)
	_restore_depots(sm, base)
	print(
		"HeadlessPerf6DayRollTest: gen_step_bound helper mid=%s sync=%s done=%s phase=%d index=%d"
		% [str(cannot_mid), str(cannot_sync), str(done), phase, idx]
	)
	if not cannot_mid:
		_fail("item afford helper started an 8ms step with 6ms remaining")
	elif cannot_sync:
		_fail("item afford helper deferred deadline 0")
	elif done or phase != 1 or idx != 0:
		_fail("generate stepped with 6ms remaining (done=%s phase=%d index=%d)" % [str(done), phase, idx])
	else:
		_pass("generate step deferred when remaining budget < last step + headroom")


func _test_production_totals(pm: Node, tm: Node) -> void:
	if not pm.has_method("get_save_data") or not pm.has_method("apply_save_data"):
		_fail("production save snapshot missing")
		return
	if not pm.has_method("_on_game_day_advanced"):
		_fail("production day listener missing")
		return
	tm.set("_live_f5_equiv_clock", true)
	tm.set("paused", false)
	var saved: Dictionary = pm.call("get_save_data")
	_run_light_listener_days(pm, tm, 10)
	var staggered: Dictionary = _production_amounts(pm)
	var h10 := int(pm.get_meta("perf6_light_harvest_n")) if pm.has_meta("perf6_light_harvest_n") else -1
	var r10 := int(pm.get_meta("perf6_light_reinforce_n")) if pm.has_meta("perf6_light_reinforce_n") else -1
	pm.call("apply_save_data", saved)
	_run_m3_light_days(pm, 10)
	var reference: Dictionary = _production_amounts(pm)
	var amount_diff := _amount_diff(staggered, reference)
	print(
		"HeadlessPerf6DayRollTest: production_10d harvests=%d reinforces=%d diff=%s"
		% [h10, r10, amount_diff if not amount_diff.is_empty() else "none"]
	)
	if h10 != 2 or r10 != 2:
		_fail("10-day cadence harvests=%d reinforces=%d (want 2 and 2)" % [h10, r10])
	elif not amount_diff.is_empty():
		_fail("10-day production totals != same-count reference (%s)" % amount_diff)
	else:
		_pass("10-day production totals match two harvests and two reinforces")
	pm.call("apply_save_data", saved)
	_run_light_listener_days(pm, tm, 12)
	var h12 := int(pm.get_meta("perf6_light_harvest_n")) if pm.has_meta("perf6_light_harvest_n") else -1
	var r12 := int(pm.get_meta("perf6_light_reinforce_n")) if pm.has_meta("perf6_light_reinforce_n") else -1
	var both := bool(pm.get_meta("perf6_light_both")) if pm.has_meta("perf6_light_both") else false
	print("HeadlessPerf6DayRollTest: production_12d harvests=%d reinforces=%d both=%s" % [h12, r12, str(both)])
	if h12 != 2 or r12 != 3 or both:
		_fail("day-12 checkpoint harvests=%d reinforces=%d both=%s (want 2, 3, false)" % [h12, r12, str(both)])
	else:
		_pass("day-12 checkpoint reinforce shifted to day %% 5 == 2 (3 calls, harvest still 2)")
	pm.call("apply_save_data", saved)


func _run_light_listener_days(pm: Node, tm: Node, days: int) -> void:
	pm.set_meta("perf6_light_harvest_n", 0)
	pm.set_meta("perf6_light_reinforce_n", 0)
	pm.set_meta("perf6_light_both", false)
	for day_n in range(1, days + 1):
		tm.set("total_days_elapsed", day_n)
		pm.call("_on_game_day_advanced", 1936, 1, day_n)
		var harvest := bool(pm.get_meta("perf6_light_harvest")) if pm.has_meta("perf6_light_harvest") else false
		var reinforce := bool(pm.get_meta("perf6_light_reinforce")) if pm.has_meta("perf6_light_reinforce") else false
		if harvest:
			pm.set_meta("perf6_light_harvest_n", int(pm.get_meta("perf6_light_harvest_n")) + 1)
		if reinforce:
			pm.set_meta("perf6_light_reinforce_n", int(pm.get_meta("perf6_light_reinforce_n")) + 1)
		if harvest and reinforce:
			pm.set_meta("perf6_light_both", true)
		if harvest != (day_n % 5 == 0) or reinforce != (day_n % 5 == 2):
			pm.set_meta("perf6_light_both", true)


func _run_m3_light_days(pm: Node, days: int) -> void:
	for day_n in range(1, days + 1):
		pm.call("advance_days", 1.0)
		if day_n % 5 == 0:
			pm.call("daily_resource_harvest_tick", 5.0)
			pm.call("daily_formation_reinforce_from_stockpile")


func _production_amounts(pm: Node) -> Dictionary:
	var out := {"resources": {}, "equipment": {}}
	if "national_stockpile" in pm and pm.national_stockpile is Dictionary:
		out["resources"] = (pm.national_stockpile as Dictionary).duplicate(true)
	if "national_equipment_stockpile" in pm and pm.national_equipment_stockpile is Dictionary:
		out["equipment"] = (pm.national_equipment_stockpile as Dictionary).duplicate(true)
	return out


func _amount_diff(a: Dictionary, b: Dictionary) -> String:
	var res_a: Dictionary = a.get("resources", {})
	var res_b: Dictionary = b.get("resources", {})
	var keys: Dictionary = {}
	for k in res_a.keys():
		keys[str(k)] = true
	for k2 in res_b.keys():
		keys[str(k2)] = true
	var bad := 0
	var sample := ""
	for k3 in keys.keys():
		var da := float(res_a.get(k3, 0.0))
		var db := float(res_b.get(k3, 0.0))
		if absf(da - db) > DEPOT_TOL:
			bad += 1
			if sample.is_empty():
				sample = "%s %.6f vs %.6f" % [str(k3), da, db]
	var eq_a: Dictionary = a.get("equipment", {})
	var eq_b: Dictionary = b.get("equipment", {})
	var ekeys: Dictionary = {}
	for ek in eq_a.keys():
		ekeys[str(ek)] = true
	for ek2 in eq_b.keys():
		ekeys[str(ek2)] = true
	for ek3 in ekeys.keys():
		var ea := int(eq_a.get(ek3, 0))
		var eb := int(eq_b.get(ek3, 0))
		if ea != eb:
			bad += 1
			if sample.is_empty():
				sample = "eq %s %d vs %d" % [str(ek3), ea, eb]
	if bad == 0:
		return ""
	return "%d keys %s" % [bad, sample]


func _test_clock(tm: Node, sm: Node, pm: Node, scale: float, do_pause: bool) -> void:
	_arm_clock(tm, sm, scale)
	var slice_max := 0.0
	var slice_over := 0
	var unfinished := 0
	var pause_checked := not do_pause
	var pause_ok := true
	var frames := 0
	var gap_i := 0
	# 1x is 24 hour-ticks/day and each tick keeps GAPS non-tick frames.
	var max_frames := DAYS * 24 * (GAPS_BETWEEN_TICKS + 1) + 160
	var sched := {}
	while frames < max_frames:
		var elapsed := int(tm.get("total_days_elapsed"))
		var depth := _queue_depth(sm)
		if elapsed >= DAYS and depth == 0:
			break
		if do_pause and not pause_checked and depth > 0 and gap_i > 0 and _slice_has_started(sm):
			pause_ok = await _pause_mid_slice(tm, sm)
			pause_checked = true
		var now_ms := Time.get_ticks_msec()
		var tick := elapsed < DAYS and gap_i >= GAPS_BETWEEN_TICKS
		if tick:
			if _tick_would_roll(tm) and depth > 0:
				unfinished += 1
			tm.set("_last_advance_real_msec", now_ms - 1000)
			gap_i = 0
		else:
			tm.set("_last_advance_real_msec", now_ms)
			gap_i += 1
		await process_frame
		frames += 1
		if "last_supply_slice_ms" in sm:
			var sms := float(sm.get("last_supply_slice_ms"))
			if sms > slice_max:
				slice_max = sms
			if sms > SLICE_MAX_MS:
				slice_over += 1
		if pm.has_meta("perf6_light_day_n"):
			var dn := int(pm.get_meta("perf6_light_day_n"))
			if dn > 0 and not sched.has(dn):
				sched[dn] = {
					"h": bool(pm.get_meta("perf6_light_harvest")),
					"r": bool(pm.get_meta("perf6_light_reinforce")),
				}
	var full_n := int(sm.get("full_supply_day_count")) if "full_supply_day_count" in sm else -1
	var history: Array = tm.call("get_day_tick_history") if tm.has_method("get_day_tick_history") else []
	var ai := _day_ai_stats(history)
	var listener := _listener_stats(history)
	print(
		"HeadlessPerf6DayRollTest: clock %.0fx frames=%d full=%d unfinished_rolls=%d slice_max=%.2f slice_over=%d day_ai_n=%d p95=%.1f max=%.1f listener_n=%d listener_max=%.1f"
		% [
			scale, frames, full_n, unfinished, slice_max, slice_over,
			int(ai.get("n", 0)), float(ai.get("p95", -1.0)), float(ai.get("max", -1.0)),
			int(listener.get("n", 0)), float(listener.get("max", -1.0)),
		]
	)
	var label := "%.0fx" % scale
	if full_n != DAYS:
		_fail("%s full_supply_day_count=%d for %d days" % [label, full_n, DAYS])
	else:
		_pass("%s one full supply day per game day (%d)" % [label, full_n])
	if unfinished > 0:
		_fail("%s %d rolls started with a supply day still queued" % [label, unfinished])
	else:
		_pass("%s each supply day finished before the next roll" % label)
	if not ("last_supply_slice_ms" in sm):
		_fail("%s supply slice meter missing" % label)
	elif slice_over > 0 or slice_max > SLICE_MAX_MS:
		_fail("%s slice max %.2fms over %d frames (cap %.0f)" % [label, slice_max, slice_over, SLICE_MAX_MS])
	else:
		_pass("%s slice max %.2fms <= %.0f" % [label, slice_max, SLICE_MAX_MS])
	if int(ai.get("n", 0)) < DAYS:
		_fail("%s day_ai samples=%d (want %d)" % [label, int(ai.get("n", 0)), DAYS])
	elif float(ai.get("p95", 999.0)) > DAY_AI_P95_MS or float(ai.get("max", 999.0)) > DAY_AI_MAX_MS:
		_fail("%s day_ai p95=%.1f max=%.1f (cap p95 %.0f max %.0f)" % [label, float(ai.get("p95", 0.0)), float(ai.get("max", 0.0)), DAY_AI_P95_MS, DAY_AI_MAX_MS])
	else:
		_pass("%s day_ai p95=%.1f max=%.1f" % [label, float(ai.get("p95", 0.0)), float(ai.get("max", 0.0))])
	if int(listener.get("n", 0)) < DAYS:
		_fail("%s production listener samples=%d" % [label, int(listener.get("n", 0))])
	elif float(listener.get("max", 999.0)) > LISTENER_MAX_MS:
		_fail("%s production listener max %.1fms > %.0f" % [label, float(listener.get("max", 0.0)), LISTENER_MAX_MS])
	else:
		_pass("%s production listener max %.1fms <= %.0f" % [label, float(listener.get("max", 0.0)), LISTENER_MAX_MS])
	var sched_bad := _schedule_problems(sched)
	if not sched_bad.is_empty():
		_fail("%s production stagger %s" % [label, sched_bad])
	elif sched.size() < DAYS:
		_fail("%s production stagger saw %d days" % [label, sched.size()])
	else:
		_pass("%s harvest on day%%5==0, reinforce on day%%5==2" % label)
	if do_pause and not pause_ok:
		_fail("pause mid-slice still advanced the supply cursor")
	elif do_pause:
		_pass("pause mid-slice did no supply work")


func _pause_mid_slice(tm: Node, sm: Node) -> bool:
	var q: Array = sm.get("_supply_day_queue")
	if q.is_empty():
		return false
	var job: Dictionary = q[0]
	var idx0 := int(job.get("index", -1))
	var phase0 := int(job.get("phase", -1))
	tm.set("paused", true)
	var ok := true
	for _i in 4:
		tm.set("_last_advance_real_msec", Time.get_ticks_msec())
		await process_frame
		if "last_supply_slice_ms" in sm and float(sm.get("last_supply_slice_ms")) > 0.0:
			ok = false
		var q2: Array = sm.get("_supply_day_queue")
		if q2.is_empty():
			ok = false
			break
		var job2: Dictionary = q2[0]
		if int(job2.get("index", -2)) != idx0 or int(job2.get("phase", -2)) != phase0:
			ok = false
	tm.set("paused", false)
	print("HeadlessPerf6DayRollTest: pause_mid_slice phase=%d index=%d ok=%s" % [phase0, idx0, str(ok)])
	return ok


func _test_catch_up(tm: Node, sm: Node) -> void:
	_arm_clock(tm, sm, 4.0)
	tm.set("current_hour", 20)
	tm.set("_accumulated_game_hours", 0.0)
	sm.call("queue_full_supply_day", 1.0)
	sm.call("_drain_queued_supply_day_slice")
	var q: Array = sm.get("_supply_day_queue")
	if q.is_empty():
		_fail("catch-up setup finished the whole day in one slice")
		return
	var job: Dictionary = q[0]
	var keys: Array = job.get("keys", [])
	if keys.is_empty():
		_fail("catch-up setup did not snapshot depot keys")
		return
	job["phase"] = 1
	job["gen_ready"] = true
	job["index"] = maxi(0, keys.size() - 30)
	var before := int(sm.get("full_supply_day_count"))
	var now_ms := Time.get_ticks_msec()
	tm.set("_last_advance_real_msec", now_ms - 960)
	await process_frame
	var catch_ms := float(sm.get("last_supply_slice_ms")) if "last_supply_slice_ms" in sm else -1.0
	var after := int(sm.get("full_supply_day_count"))
	var left := _queue_depth(sm)
	print(
		"HeadlessPerf6DayRollTest: catch_up ms=%.2f count %d→%d left=%d"
		% [catch_ms, before, after, left]
	)
	if left != 0 or after != before + 1:
		_fail("catch-up did not finish the open supply day (left=%d count %d→%d)" % [left, before, after])
	elif catch_ms > SLICE_MAX_MS:
		_fail("catch-up slice %.2fms > %.0f" % [catch_ms, SLICE_MAX_MS])
	else:
		_pass("catch-up finished the remainder in %.2fms" % catch_ms)
	var count_at_roll := int(sm.get("full_supply_day_count"))
	now_ms = Time.get_ticks_msec()
	tm.set("_last_advance_real_msec", now_ms - 1000)
	await process_frame
	var roll_ms := float(sm.get("last_supply_slice_ms")) if "last_supply_slice_ms" in sm else -1.0
	var rolled_job_phase := -1
	var q3: Array = sm.get("_supply_day_queue")
	if not q3.is_empty():
		rolled_job_phase = int((q3[0] as Dictionary).get("phase", -1))
	print(
		"HeadlessPerf6DayRollTest: roll_frame slice_ms=%.2f new_phase=%d count=%d"
		% [roll_ms, rolled_job_phase, int(sm.get("full_supply_day_count"))]
	)
	if roll_ms > 0.0:
		_fail("roll frame still sliced supply work (%.2fms)" % roll_ms)
	elif int(sm.get("full_supply_day_count")) != count_at_roll:
		_fail("roll frame completed a supply day")
	else:
		_pass("roll frame did no slice work")


func _arm_clock(tm: Node, sm: Node, scale: float) -> void:
	tm.set("paused", false)
	tm.set("time_scale", scale)
	tm.set("_live_f5_equiv_clock", true)
	tm.set("_force_windowed_backup_clock", true)
	tm.set("current_year", 1936)
	tm.set("current_month", 1)
	tm.set("current_day", 1)
	tm.set("current_hour", 0)
	tm.set("total_days_elapsed", 0)
	tm.set("_accumulated_game_hours", 0.0)
	tm.set("_last_advance_real_msec", Time.get_ticks_msec())
	if tm.has_method("clear_day_tick_history"):
		tm.call("clear_day_tick_history")
	sm.set("full_supply_day_count", 0)
	if "_supply_day_queue" in sm:
		sm.set("_supply_day_queue", [])


func _tick_would_roll(tm: Node) -> bool:
	var scale := float(tm.get("time_scale"))
	var hours := maxf(scale, 0.1)
	if tm.has_method("is_interactive_light_sim") and bool(tm.call("is_interactive_light_sim")):
		hours = minf(hours, 6.0)
	var hour := int(tm.get("current_hour"))
	var acc := float(tm.get("_accumulated_game_hours"))
	return hour + int(acc + hours) >= 24


func _slice_has_started(sm: Node) -> bool:
	var q: Array = sm.get("_supply_day_queue")
	if q.is_empty():
		return false
	var job: Dictionary = q[0]
	return int(job.get("phase", 0)) > 0 or int(job.get("index", 0)) > 0


func _queue_depth(sm: Node) -> int:
	if sm.has_method("supply_day_queue_depth"):
		return int(sm.call("supply_day_queue_depth"))
	return 0


func _schedule_problems(sched: Dictionary) -> String:
	for day_v in sched.keys():
		var day_n := int(day_v)
		var row: Dictionary = sched[day_v]
		var harvest := bool(row.get("h", false))
		var reinforce := bool(row.get("r", false))
		if harvest and reinforce:
			return "day %d ran harvest and reinforce" % day_n
		if harvest != (day_n % 5 == 0) or reinforce != (day_n % 5 == 2):
			return "day %d harvest=%s reinforce=%s" % [day_n, str(harvest), str(reinforce)]
	return ""


func _day_ai_stats(history: Array) -> Dictionary:
	var values: Array = []
	for raw in history:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if not row.has("day_ai_ms"):
			continue
		values.append(float(row.get("day_ai_ms", 0.0)))
	if values.is_empty():
		return {"n": 0, "p95": -1.0, "max": -1.0}
	values.sort()
	var mx := float(values[values.size() - 1])
	var rank := 0.95 * float(values.size() - 1)
	var lo := int(floor(rank))
	var hi := mini(lo + 1, values.size() - 1)
	var frac := rank - float(lo)
	var p95 := float(values[lo]) * (1.0 - frac) + float(values[hi]) * frac
	return {"n": values.size(), "p95": p95, "max": mx}


func _listener_stats(history: Array) -> Dictionary:
	var n := 0
	var mx := 0.0
	for raw in history:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var listeners: Array = row.get("listeners", []) as Array
		for item_v in listeners:
			if typeof(item_v) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = item_v
			var name := str(item.get("name", ""))
			if "ProductionManager" in name and "_on_game_day_advanced" in name:
				n += 1
				var ms := float(item.get("ms", 0.0))
				if ms > mx:
					mx = ms
	return {"n": n, "max": mx}


func _snap_depots(sm: Node) -> Dictionary:
	var out := {}
	if not ("depot_states" in sm):
		return out
	var states: Dictionary = sm.depot_states
	for pid_v in states.keys():
		var state = states[pid_v]
		if state == null:
			continue
		out[int(pid_v)] = {
			"stockpile": float(state.stockpile),
			"fuel": float(state.fuel_stockpile),
			"mun": float(state.munitions_stockpile),
			"sab": float(state.sabotage_level),
		}
	return out


func _restore_depots(sm: Node, snap: Dictionary) -> void:
	if not ("depot_states" in sm):
		return
	var states: Dictionary = sm.depot_states
	for pid_v in snap.keys():
		var state = states.get(pid_v, null)
		if state == null:
			continue
		var row: Dictionary = snap[pid_v]
		state.stockpile = float(row.get("stockpile", 0.0))
		state.fuel_stockpile = float(row.get("fuel", 0.0))
		state.munitions_stockpile = float(row.get("mun", 0.0))
		state.sabotage_level = float(row.get("sab", 0.0))


func _depot_diff(a: Dictionary, b: Dictionary) -> String:
	if a.size() != b.size():
		return "depot count %d vs %d" % [a.size(), b.size()]
	var bad := 0
	var sample := ""
	for pid_v in a.keys():
		if not b.has(pid_v):
			bad += 1
			continue
		var ra: Dictionary = a[pid_v]
		var rb: Dictionary = b[pid_v]
		for key in ["stockpile", "fuel", "mun", "sab"]:
			if absf(float(ra.get(key, 0.0)) - float(rb.get(key, 0.0))) > DEPOT_TOL:
				bad += 1
				if sample.is_empty():
					sample = "pid %s %s %.8f vs %.8f" % [str(pid_v), str(key), float(ra.get(key, 0.0)), float(rb.get(key, 0.0))]
				break
	if bad == 0:
		return ""
	return "%d depots %s" % [bad, sample]


func _boot_live_supply_network(mm: Node, sm: Node) -> int:
	if sm.has_method("supply_day_queue_depth"):
		sm.set("_supply_day_queue", [])
	var provs: Dictionary = mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else {}
	var land_n := 0
	for pid_v in provs.keys():
		var p = provs[pid_v]
		if p == null:
			continue
		if "is_sea" in p and bool(p.is_sea):
			continue
		if "factories" in p:
			p.factories = maxi(int(p.factories), 1)
		land_n += 1
	var city := _load_json(CITY_PATH)
	var city_layer: Dictionary = city.get("provinces", {}) as Dictionary
	var adj = mm.call("get_adjacency_system") if mm.has_method("get_adjacency_system") else null
	var countries: Dictionary = {}
	var raw_c: Variant = mm.get("_countries")
	if raw_c is Dictionary:
		countries = raw_c as Dictionary
	if sm.has_method("build_network"):
		sm.call("build_network", provs, countries, city_layer, adj, "GER")
	var depots := 0
	if "depot_states" in sm:
		depots = int((sm.depot_states as Dictionary).size())
	if depots < land_n:
		var DepotScr: GDScript = load(DEPOT_SCRIPT) as GDScript
		if DepotScr != null and "depot_states" in sm:
			var states: Dictionary = sm.depot_states
			for pid_v2 in provs.keys():
				var p2 = provs[pid_v2]
				if p2 == null or ("is_sea" in p2 and bool(p2.is_sea)):
					continue
				var pid := int(pid_v2)
				if states.has(pid):
					continue
				states[pid] = DepotScr.new(pid, 8000.0)
			sm.depot_states = states
			depots = int((sm.depot_states as Dictionary).size())
	print("HeadlessPerf6DayRollTest: supply land=%d depots=%d" % [land_n, depots])
	return depots


func _load_accurate_board(mm: Node) -> bool:
	var base := _load_json(BASE_PATH)
	var geo := _load_json(GEO_PATH)
	var own_doc := _load_json(OWN_PATH)
	if base.is_empty() or geo.is_empty():
		return false
	var ProvScript: GDScript = load(PROV_SCRIPT) as GDScript
	var MapDataScript: GDScript = load(MAP_DATA_SCRIPT) as GDScript
	if ProvScript == null or MapDataScript == null:
		return false
	var owners: Dictionary = own_doc.get("owners", {}) as Dictionary
	var provs: Dictionary = {}
	for row in base.get("provinces", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid := int(row.get("id", 0))
		if pid <= 0:
			continue
		var p = ProvScript.new()
		p.id = pid
		p.name = str(row.get("name", "Province %d" % pid))
		p.terrain = str(row.get("terrain", "plains"))
		p.domain = str(row.get("domain", "land"))
		var terr_l := str(p.terrain).strip_edges().to_lower()
		p.is_sea = terr_l in ["sea", "ocean", "water", "lake"] or str(p.domain).strip_edges().to_lower() in ["sea", "ocean", "naval"]
		var ot := str(owners.get(str(pid), "")).strip_edges().to_upper()
		if not ot.is_empty():
			p.owner_tag = ot
			p.controller_tag = ot
		if "infrastructure" in p:
			p.infrastructure = 5
		provs[pid] = p
	var geometry: Dictionary = {}
	for row2 in geo.get("provinces", []):
		if typeof(row2) != TYPE_DICTIONARY:
			continue
		var pid2 := int(row2.get("id", 0))
		if pid2 <= 0:
			continue
		var pts: Array = row2.get("points", [])
		var packed := PackedVector2Array()
		for pt in pts:
			if pt is Array and pt.size() >= 2:
				packed.append(Vector2(float(pt[0]), float(pt[1])))
		geometry[pid2] = {
			"points": packed,
			"label_anchor": row2.get("label_anchor", []),
			"meta": row2.get("meta", {}),
		}
	var adj = null
	if FileAccess.file_exists(ADJ_PATH):
		var AdjScr: GDScript = load("res://scripts/data/AdjacencySystem.gd") as GDScript
		if AdjScr != null:
			adj = AdjScr.new()
			if adj.has_method("load_adjacency"):
				adj.call("load_adjacency", ADJ_PATH)
			if adj.has_method("begin_bulk_registration"):
				adj.call("begin_bulk_registration")
			for _pid in provs.keys():
				if adj.has_method("register_province"):
					adj.call("register_province", provs[_pid])
			if adj.has_method("end_bulk_registration"):
				adj.call("end_bulk_registration")
	var map_data = MapDataScript.new(provs, geometry, adj, {})
	mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	return true


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	return data if data is Dictionary else {}
