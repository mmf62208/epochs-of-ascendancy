extends SceneTree

## PERF-6 FIX #3: lag on a 4× day must not dump the remainder in one
## unbounded midnight catch-up. Pause skips 10 drain frames (existing
## pause seam), then the catch-up window drains at ≤22 ms/frame. The day
## still finishes before the roll, every frame ≤25 ms, no deadline-0 sync.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessPerf6PaceTest.gd
##
## FAILS on 5f7d4cc7 (≤80 ms unbounded catch-up / no paced 22 ms budget).
## PASSES on the tip. Headless only.

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const DEPOT_SCRIPT := "res://scripts/supply/ProvinceDepotState.gd"
const SLICE_MAX_MS := 25.0
const SKIP_FRAMES := 10
const FRAME_MS := 16.0
const UNTIL_MS := 50
const MAX_DRAIN_FRAMES := 16

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf6PaceTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf6PaceTest: ", msg)


func _run_and_quit() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf6PaceTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf6PaceTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _run() -> void:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	var tm: Node = root.get_node_or_null("/root/TimeManager")
	var sm: Node = root.get_node_or_null("/root/SupplyManager")
	if mm == null or tm == null or sm == null:
		_fail("autoloads missing")
		return
	if not _load_accurate_board(mm):
		_fail("board load failed")
		return
	var depots := _boot_live_supply_network(mm, sm)
	if depots < 2000:
		_fail("live-weight depots too few (%d)" % depots)
		return
	_pass("live-weight depots=%d" % depots)
	if not sm.has_method("queue_full_supply_day") or not sm.has_method("_drain_queued_supply_day_slice"):
		_fail("supply-day job path missing")
		return
	_test_pace_budget_raises(tm, sm)
	await _test_lag_completes_without_sync(tm, sm)


func _test_pace_budget_raises(tm: Node, sm: Node) -> void:
	_reset_slice_state(sm)
	_arm_catchup_clock(tm, sm, 4.0)
	if not sm.has_method("_supply_slice_paced_budget_ms"):
		_fail("paced budget helper missing (fixed 20 ms / no FIX #3)")
		return
	if not sm.has_method("_should_sync_finish_supply_day"):
		_fail("sync-finish helper missing (unbounded ≤80 ms catch-up still in place)")
		return
	if not sm.has_method("_supply_slice_remaining_work_ms"):
		_fail("remaining-work helper missing")
		return
	if "supply_slice_frame_ms_override" in sm:
		sm.set("supply_slice_frame_ms_override", FRAME_MS)
	sm.call("queue_full_supply_day", 1.0)
	tm.set("current_hour", 20)
	tm.set("_accumulated_game_hours", 0.0)
	tm.set("_last_advance_real_msec", Time.get_ticks_msec() - (1000 - UNTIL_MS))
	var remaining: float = float(sm.call("_supply_slice_remaining_work_ms"))
	var budget: float = float(sm.call("_supply_slice_paced_budget_ms"))
	var in_window := bool(sm.call("_should_catch_up_supply_day"))
	var sync_now := bool(sm.call("_should_sync_finish_supply_day"))
	print(
		"HeadlessPerf6PaceTest: pace_budget remaining=%.1f budget=%.2f catch_up=%s sync=%s"
		% [remaining, budget, str(in_window), str(sync_now)]
	)
	if remaining < 40.0:
		_fail("queued day remaining work %.1fms too small to exercise pacing" % remaining)
	elif not in_window:
		_fail("until=%dms was not in the bounded catch-up window" % UNTIL_MS)
	elif sync_now:
		_fail("until=%dms used last-resort sync finish (want bounded 22 ms)" % UNTIL_MS)
	elif budget < 21.5:
		_fail("paced budget %.2fms stayed at 20 ms with remaining %.1fms / 4 frames" % [budget, remaining])
	else:
		_pass("paced budget %.2fms with remaining %.1fms (catch-up window, no sync)" % [budget, remaining])
	_reset_slice_state(sm)


func _test_lag_completes_without_sync(tm: Node, sm: Node) -> void:
	_reset_slice_state(sm)
	_arm_catchup_clock(tm, sm, 4.0)
	if "supply_slice_frame_ms_override" in sm:
		sm.set("supply_slice_frame_ms_override", FRAME_MS)
	var before := int(sm.get("full_supply_day_count")) if "full_supply_day_count" in sm else 0
	var sync_before := int(sm.get("supply_catch_up_sync_count")) if "supply_catch_up_sync_count" in sm else 0
	sm.call("queue_full_supply_day", 1.0)
	if int(sm.call("supply_day_queue_depth")) <= 0:
		_fail("lag case queue_full_supply_day did not enqueue")
		_reset_slice_state(sm)
		return
	tm.set("current_hour", 20)
	tm.set("_accumulated_game_hours", 0.0)
	tm.set("paused", true)
	var skip_i := 0
	while skip_i < SKIP_FRAMES:
		tm.set("_last_advance_real_msec", Time.get_ticks_msec())
		await process_frame
		skip_i += 1
		if "last_supply_slice_ms" in sm and float(sm.get("last_supply_slice_ms")) > 0.0:
			_fail("paused skip frame still drained %.2fms" % float(sm.get("last_supply_slice_ms")))
			_reset_slice_state(sm)
			return
	tm.set("paused", false)
	var slice_max := 0.0
	var slice_over := 0
	var frames := 0
	var after := before
	var left := int(sm.call("supply_day_queue_depth"))
	while frames < MAX_DRAIN_FRAMES and (after == before or left > 0):
		tm.set("_last_advance_real_msec", Time.get_ticks_msec() - (1000 - UNTIL_MS))
		await process_frame
		frames += 1
		if "last_supply_slice_ms" in sm:
			var sms := float(sm.get("last_supply_slice_ms"))
			if sms > slice_max:
				slice_max = sms
			if sms > SLICE_MAX_MS:
				slice_over += 1
		after = int(sm.get("full_supply_day_count")) if "full_supply_day_count" in sm else -1
		left = int(sm.call("supply_day_queue_depth")) if sm.has_method("supply_day_queue_depth") else -1
		if after >= before + 1 and left == 0:
			break
	var sync_after := int(sm.get("supply_catch_up_sync_count")) if "supply_catch_up_sync_count" in sm else -1
	print(
		"HeadlessPerf6PaceTest: lag_4x skipped=%d drain_frames=%d full %d→%d left=%d slice_max=%.2f slice_over=%d sync %d→%d"
		% [SKIP_FRAMES, frames, before, after, left, slice_max, slice_over, sync_before, sync_after]
	)
	if after != before + 1 or left != 0:
		_fail(
			"lag 4x day did not finish before roll (full %d→%d left=%d frames=%d)"
			% [before, after, left, frames]
		)
	elif slice_over > 0 or slice_max > SLICE_MAX_MS:
		_fail("lag 4x slice max %.2fms over %d (cap %.0f)" % [slice_max, slice_over, SLICE_MAX_MS])
	elif sync_after != sync_before:
		_fail("lag 4x used unbounded sync finish (sync %d→%d slice_max=%.2f)" % [sync_before, sync_after, slice_max])
	else:
		_pass("lag 4x completed in %d frames slice_max=%.2f sync=0" % [frames, slice_max])
	var count_at_roll := int(sm.get("full_supply_day_count"))
	tm.set("_last_advance_real_msec", Time.get_ticks_msec() - 1000)
	await process_frame
	var roll_ms := float(sm.get("last_supply_slice_ms")) if "last_supply_slice_ms" in sm else -1.0
	print(
		"HeadlessPerf6PaceTest: roll_frame slice_ms=%.2f count=%d"
		% [roll_ms, int(sm.get("full_supply_day_count"))]
	)
	if roll_ms > 0.0:
		_fail("roll frame still sliced supply work (%.2fms)" % roll_ms)
	elif int(sm.get("full_supply_day_count")) != count_at_roll:
		_fail("roll frame completed a supply day")
	else:
		_pass("roll frame did no slice work")
	_reset_slice_state(sm)


func _arm_catchup_clock(tm: Node, sm: Node, scale: float) -> void:
	tm.set("paused", false)
	tm.set("time_scale", scale)
	tm.set("_live_f5_equiv_clock", true)
	tm.set("_force_windowed_backup_clock", true)
	tm.set("_living_playtest_clock", false)
	tm.set("current_year", 1936)
	tm.set("current_month", 1)
	tm.set("current_day", 1)
	tm.set("current_hour", 20)
	tm.set("total_days_elapsed", 0)
	tm.set("_accumulated_game_hours", 0.0)
	tm.set("_last_advance_real_msec", Time.get_ticks_msec())
	sm.set("full_supply_day_count", 0)
	if "_supply_day_queue" in sm:
		sm.set("_supply_day_queue", [])
	if "supply_catch_up_sync_count" in sm:
		sm.set("supply_catch_up_sync_count", 0)
	if "supply_catch_up_sync_ms" in sm:
		sm.set("supply_catch_up_sync_ms", 0.0)


func _reset_slice_state(sm: Node) -> void:
	if "supply_slice_phase_cost_estimate_ms" in sm:
		sm.set("supply_slice_phase_cost_estimate_ms", -1.0)
	if "supply_slice_item_cost_estimate_ms" in sm:
		sm.set("supply_slice_item_cost_estimate_ms", -1.0)
	if "supply_slice_frame_ms_override" in sm:
		sm.set("supply_slice_frame_ms_override", -1.0)
	if "_supply_slice_last_item_ms" in sm:
		sm.set("_supply_slice_last_item_ms", 0.25)
	if "_supply_slice_did_work" in sm:
		sm.set("_supply_slice_did_work", false)
	if "_supply_slice_phase_ms" in sm:
		sm.set("_supply_slice_phase_ms", {
			"flush": 1.0,
			"naval": 6.0,
			"fuel": 4.5,
			"air": 1.0,
		})
	if "_supply_day_queue" in sm:
		sm.set("_supply_day_queue", [])
	if "supply_catch_up_sync_count" in sm:
		sm.set("supply_catch_up_sync_count", 0)
	if "supply_catch_up_sync_ms" in sm:
		sm.set("supply_catch_up_sync_ms", 0.0)
	if "last_supply_slice_catch_up" in sm:
		sm.set("last_supply_slice_catch_up", false)


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
	print("HeadlessPerf6PaceTest: supply land=%d depots=%d" % [land_n, depots])
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
