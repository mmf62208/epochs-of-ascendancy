extends SceneTree

## PERF-6 FIX #2: a 19 ms atomic-phase estimate (or a high generate-item
## estimate) must not starve the queued supply day when there is no
## deadline-0 catch-up. First work of a frame always runs; estimates EMA
## on run and decay toward the floor when deferred.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessPerf6StarveTest.gd
##
## FAILS on d31e3223 (FIX #1 clamp-to-20, no progress guarantee, no decay).
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
const PHASE_PIN_MS := 19.0
const ITEM_PIN_MS := 20.0
const MAX_FRAMES := 160
const DECAY := 0.8
const EMA_OLD := 0.75
const EMA_NEW := 0.25

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf6StarveTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf6StarveTest: ", msg)


func _run_and_quit() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf6StarveTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf6StarveTest: RESULT=", "PASS" if ok else "FAIL")
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
	if not sm.has_method("queue_full_supply_day") or not sm.has_method("_run_supply_day_job"):
		_fail("supply-day job path missing")
		return
	_test_progress_forces_first_phase(sm)
	_test_defer_decays_estimate(sm)
	_test_run_emas_estimate(sm)
	await _test_queued_day(tm, sm, "phase", 1.0)
	await _test_queued_day(tm, sm, "phase", 4.0)
	await _test_queued_day(tm, sm, "item", 1.0)
	await _test_queued_day(tm, sm, "item", 4.0)


func _test_progress_forces_first_phase(sm: Node) -> void:
	_reset_overrides(sm)
	if "_supply_slice_did_work" in sm:
		sm.set("_supply_slice_did_work", false)
	var job: Dictionary = sm.call("_make_supply_day_job", 1.0)
	job["phase"] = 2
	job["naval_last_ms"] = PHASE_PIN_MS
	var now := Time.get_ticks_usec()
	var tight: int = now + 3000
	var done := bool(sm.call("_run_supply_day_job", job, tight))
	var phase := int(job.get("phase", -1))
	var naval_ms := float(job.get("naval_ms", 0.0))
	print(
		"HeadlessPerf6StarveTest: progress_first tight_done=%s phase=%d naval_ms=%.3f"
		% [str(done), phase, naval_ms]
	)
	if phase < 3 or naval_ms <= 0.0:
		_fail(
			"first work of frame did not run naval at 19ms estimate (done=%s phase=%d naval_ms=%.3f)"
			% [str(done), phase, naval_ms]
		)
	else:
		_pass("first work of frame ran naval despite 19ms estimate (3ms remaining)")
	_reset_overrides(sm)


func _test_defer_decays_estimate(sm: Node) -> void:
	_reset_overrides(sm)
	if "_supply_slice_did_work" in sm:
		sm.set("_supply_slice_did_work", true)
	var job: Dictionary = sm.call("_make_supply_day_job", 1.0)
	job["phase"] = 2
	job["naval_last_ms"] = PHASE_PIN_MS
	if "_supply_slice_phase_ms" in sm:
		var phases: Dictionary = sm.get("_supply_slice_phase_ms")
		phases["naval"] = PHASE_PIN_MS
		sm.set("_supply_slice_phase_ms", phases)
	var now := Time.get_ticks_usec()
	var budget: int = now + 20000
	var done := bool(sm.call("_run_supply_day_job", job, budget))
	var phase := int(job.get("phase", -1))
	var last_ms := float(job.get("naval_last_ms", -1.0))
	var want: float = 0.05 + (PHASE_PIN_MS - 0.05) * DECAY
	print(
		"HeadlessPerf6StarveTest: defer_decay done=%s phase=%d last_ms=%.3f want=%.3f"
		% [str(done), phase, last_ms, want]
	)
	if done or phase != 2 or float(job.get("naval_ms", 0.0)) > 0.0:
		_fail("defer-after-work still ran naval (done=%s phase=%d)" % [str(done), phase])
	elif last_ms > want + 0.05 or last_ms >= PHASE_PIN_MS:
		_fail("deferred naval estimate stayed pinned at %.3f (want ~%.3f)" % [last_ms, want])
	else:
		_pass("deferred naval estimate decayed %.3f → %.3f" % [PHASE_PIN_MS, last_ms])
	_reset_overrides(sm)


func _test_run_emas_estimate(sm: Node) -> void:
	_reset_overrides(sm)
	if "_supply_slice_did_work" in sm:
		sm.set("_supply_slice_did_work", false)
	var job: Dictionary = sm.call("_make_supply_day_job", 1.0)
	job["phase"] = 2
	job["naval_last_ms"] = PHASE_PIN_MS
	if "_supply_slice_phase_ms" in sm:
		var phases: Dictionary = sm.get("_supply_slice_phase_ms")
		phases["naval"] = PHASE_PIN_MS
		sm.set("_supply_slice_phase_ms", phases)
	var now := Time.get_ticks_usec()
	var wide: int = now + 50000
	var done := bool(sm.call("_run_supply_day_job", job, wide))
	var actual := float(job.get("naval_ms", 0.0))
	var last_ms := float(job.get("naval_last_ms", -1.0))
	var blended: float = PHASE_PIN_MS * EMA_OLD + actual * EMA_NEW
	var want: float = clampf(blended, 0.05, 20.0)
	print(
		"HeadlessPerf6StarveTest: run_ema done=%s actual=%.3f last_ms=%.3f want=%.3f"
		% [str(done), actual, last_ms, want]
	)
	if actual <= 0.0:
		_fail("EMA case did not run naval")
	elif absf(last_ms - want) > 0.15:
		_fail("naval estimate not EMA-blended (last=%.3f want=%.3f actual=%.3f)" % [last_ms, want, actual])
	elif last_ms <= actual + 0.05 and actual < 10.0:
		_fail("naval estimate overwritten with measured %.3f (no EMA)" % actual)
	else:
		_pass("naval estimate EMA-blended to %.3f (actual %.3f)" % [last_ms, actual])
	_reset_overrides(sm)


func _test_queued_day(tm: Node, sm: Node, kind: String, scale: float) -> void:
	_reset_overrides(sm)
	_arm_no_catchup(tm, sm, scale)
	var before := int(sm.get("full_supply_day_count")) if "full_supply_day_count" in sm else 0
	sm.call("queue_full_supply_day", 1.0)
	var q: Array = sm.get("_supply_day_queue") if "_supply_day_queue" in sm else []
	if q.is_empty():
		_fail("%s %.0fx queue_full_supply_day did not enqueue" % [kind, scale])
		_reset_overrides(sm)
		return
	var job: Dictionary = q[0]
	if kind == "phase":
		sm.set("supply_slice_phase_cost_estimate_ms", PHASE_PIN_MS)
	elif kind == "item":
		sm.set("_supply_slice_last_item_ms", ITEM_PIN_MS)
		job["phase"] = 1
		job["gen_ready"] = false
		job["index"] = 0
	var slice_max := 0.0
	var slice_over := 0
	var catch_up := 0
	var frames := 0
	while frames < MAX_FRAMES:
		if int(sm.get("full_supply_day_count")) >= before + 1:
			break
		if sm.has_method("_should_catch_up_supply_day") and bool(sm.call("_should_catch_up_supply_day")):
			catch_up += 1
		await process_frame
		frames += 1
		if "last_supply_slice_ms" in sm:
			var sms := float(sm.get("last_supply_slice_ms"))
			if sms > slice_max:
				slice_max = sms
			if sms > SLICE_MAX_MS:
				slice_over += 1
	var after := int(sm.get("full_supply_day_count")) if "full_supply_day_count" in sm else -1
	var left := 0
	if sm.has_method("supply_day_queue_depth"):
		left = int(sm.call("supply_day_queue_depth"))
	print(
		"HeadlessPerf6StarveTest: queued %s clock %.0fx frames=%d full %d→%d left=%d slice_max=%.2f slice_over=%d catch_up=%d"
		% [kind, scale, frames, before, after, left, slice_max, slice_over, catch_up]
	)
	if catch_up > 0:
		_fail("%s %.0fx catch-up/deadline-0 ran %d times" % [kind, scale, catch_up])
	elif after != before + 1 or left != 0:
		_fail(
			"%s %.0fx supply day starved (full %d→%d left=%d frames=%d)"
			% [kind, scale, before, after, left, frames]
		)
	elif slice_over > 0 or slice_max > SLICE_MAX_MS:
		_fail("%s %.0fx slice max %.2fms over %d (cap %.0f)" % [kind, scale, slice_max, slice_over, SLICE_MAX_MS])
	else:
		_pass("%s %.0fx completed in %d frames slice_max=%.2f" % [kind, scale, frames, slice_max])
	_reset_overrides(sm)


func _arm_no_catchup(tm: Node, sm: Node, scale: float) -> void:
	tm.set("paused", false)
	tm.set("time_scale", scale)
	tm.set("_live_f5_equiv_clock", true)
	tm.set("_force_windowed_backup_clock", false)
	tm.set("_living_playtest_clock", false)
	tm.set("current_year", 1936)
	tm.set("current_month", 1)
	tm.set("current_day", 1)
	tm.set("current_hour", 0)
	tm.set("total_days_elapsed", 0)
	tm.set("_accumulated_game_hours", 0.0)
	tm.set("_last_advance_real_msec", Time.get_ticks_msec())
	sm.set("full_supply_day_count", 0)
	if "_supply_day_queue" in sm:
		sm.set("_supply_day_queue", [])


func _reset_overrides(sm: Node) -> void:
	if "supply_slice_phase_cost_estimate_ms" in sm:
		sm.set("supply_slice_phase_cost_estimate_ms", -1.0)
	if "supply_slice_item_cost_estimate_ms" in sm:
		sm.set("supply_slice_item_cost_estimate_ms", -1.0)
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
	if "supply_slice_frame_ms_override" in sm:
		sm.set("supply_slice_frame_ms_override", -1.0)
	if "supply_catch_up_sync_count" in sm:
		sm.set("supply_catch_up_sync_count", 0)
	if "supply_catch_up_sync_ms" in sm:
		sm.set("supply_catch_up_sync_ms", 0.0)


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
	print("HeadlessPerf6StarveTest: supply land=%d depots=%d" % [land_n, depots])
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
