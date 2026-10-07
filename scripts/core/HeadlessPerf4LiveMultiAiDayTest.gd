extends SceneTree

## PERF-4 FIX #1: live-equivalent interactive multi-AI day cost.
## The stripped HeadlessPerf4DailySimTickTest never built the F5 supply
## network, so `_maybe_run_interactive_multi_ai` looked cheap (~20ms) while
## Play after Begin GER 1936 spent ~1.5s in apply_supply → set_player_depot
## → SupplyManager.build_network every game day.
##
## This harness boots the same per-day path: world_accurate board, GER player,
## live city-layer supply network, then TimeManager day_ai including
## apply_interactive_multi_ai_day_live. FAILS on tip 289268ed / main (worst
## day_ai in the 1.5s class). PASSES when the soft tick no longer rebuilds
## the network and live Play still runs the full advance_supply_day steps.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const SRC_SM := "res://scripts/supply/SupplyManager.gd"
const SRC_GD := "res://scripts/autoload/GameData.gd"
const EQUIV_DAYS := 5
const EQUIV_SEED := 193601
const PLAYER_TAG := "GER"
const DAY_BUDGET_MS := 500.0
const QUIET_DAY_BUDGET_MS := 200.0
const CAPTURE_FRAME_BUDGET_MS := 5.0
const RECOVERY_DAY_BUDGET_MS := 200.0
const HUB_CAPACITY_DAY := 40
const CAPTURE_HUB_PID := 710160
const CAPTURE_DEPOT_PID := 710161
const REAL_DEPOT_PID := 710300
const REPEAT_DEPOT_ADDS := 4
const CAPITALS := {
	"GER": 710300,
	"FRA": 710707,
	"ENG": 711414,
	"USA": 800792,
	"SOV": 903534,
	"ITA": 710963,
	"JAP": 903995,
	"POL": 711054,
}

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf4LiveMultiAiDayTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf4LiveMultiAiDayTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessPerf4LiveMultiAiDayTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf4LiveMultiAiDayTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


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
	var needle := "func %s(" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var rest := src.substr(i)
	var lines := rest.split("\n")
	var out := PackedStringArray()
	out.append(lines[0])
	for li in range(1, lines.size()):
		var line := lines[li]
		if line.begins_with("func ") or line.begins_with("static func "):
			break
		out.append(line)
	return "\n".join(out)


func _run() -> void:
	_test_source_gates_fail_on_pre_fix()
	var mm: Node = root.get_node_or_null("/root/MapManager")
	var tm: Node = root.get_node_or_null("/root/TimeManager")
	var gd: Node = root.get_node_or_null("/root/GameData")
	var sm: Node = root.get_node_or_null("/root/SupplyManager")
	var lm: Node = root.get_node_or_null("/root/LeaderManager")
	if mm == null or tm == null or gd == null or sm == null:
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
	if lm != null and lm.has_method("boot_living_player"):
		lm.call("boot_living_player", PLAYER_TAG)
	elif lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", PLAYER_TAG)
	if not _boot_live_supply_network(mm, sm):
		_fail("supply network boot failed")
		return
	_test_step_costs(gd, sm, tm)
	_test_repeated_real_depot_guard(sm)
	_test_capture_frame_budgets(mm, sm)
	_test_peace_annexation_updates_supply(gd, mm, sm)
	_test_ten_capture_path_identity_within_one_day(mm, sm)
	_test_annex_path_identity(gd, mm, sm)
	_test_capture_matches_full_rebuild(mm, sm)
	_test_one_full_supply_day_per_game_day(tm, gd, sm)
	_test_production_cache_measured(gd)
	_test_owner_index_measured(mm)
	_test_multi_ai_decisions_stable(gd, tm)
	_test_live_day_ai_budget(tm, gd)
	_test_hub_capacity_on_infra_complete(mm, sm)
	_test_hub_capacity_matches_rebuild_at_day_40(tm, mm, sm)


func _test_source_gates_fail_on_pre_fix() -> void:
	var sm_src := _read(SRC_SM)
	var depot := _slice_func(sm_src, "set_player_depot")
	if depot.is_empty() or "changed" not in depot:
		_fail("set_player_depot still rebuilds every call (pre-fix / main FAIL class)")
	else:
		_pass("set_player_depot rebuilds only on membership change")
	if "provinces.has" not in depot:
		_fail("set_player_depot still accepts dummy/missing pids (pre-fix FAIL class)")
	else:
		_pass("set_player_depot skips pids missing from the board")
	if "build_network" in depot:
		_fail("set_player_depot still full-rebuilds the network (2d930483 FAIL class)")
	else:
		_pass("set_player_depot patches one hub (no build_network)")
	var notify := _slice_func(sm_src, "notify_province_control_changed")
	if notify.is_empty() or "_rebuild_default_routes" in notify:
		_fail("notify_province_control_changed still rebuilds every route (2d930483 FAIL class)")
	else:
		_pass("notify_province_control_changed does not rebuild all routes")
	var day_fn := _slice_func(sm_src, "_on_game_day_advanced")
	if "_advance_supply_day_light" not in day_fn or "is_interactive_light_sim" not in day_fn:
		_fail("daily listener lost main's light/full split (2d930483 FAIL class)")
	else:
		_pass("daily listener restores main light path")
	if "full_supply_day_count" not in sm_src:
		_fail("full_supply_day_count missing")
	else:
		_pass("full_supply_day_count present")
	var adv := _slice_func(sm_src, "advance_supply_day")
	if "_process_air_missions" not in adv or "_process_naval_recon" not in adv:
		_fail("advance_supply_day dropped air/naval steps (gameplay change)")
	else:
		_pass("advance_supply_day keeps air/naval/shipping steps")
	if "is_live_f5_play_path" in adv or "is_interactive_light_sim" in adv:
		_fail("advance_supply_day still gates live Play onto the light path")
	else:
		_pass("advance_supply_day does not light-gate live Play")
	_test_replanned_off_must_fail(sm_src, adv)
	var gd_src := _read(SRC_GD)
	var mut := _slice_func(gd_src, "apply_supply_route_mutation")
	if "get_province" not in mut:
		_fail("apply_supply still set_player_depot on dummy pid 1 (pre-fix FAIL class)")
	else:
		_pass("apply_supply requires a real map province before set_player_depot")
	if "advance_supply_day_interactive_light" in mut:
		_fail("apply_supply still drops live Play onto the light path")
	elif "advance_supply_day" in mut:
		_pass("apply_supply uses full advance_supply_day")
	else:
		_fail("apply_supply lost advance_supply_day")
	var peace := _slice_func(gd_src, "apply_peace_conference_settlement_live")
	if "update_province_owner" not in peace and "notify_province_control_changed" not in peace:
		_fail("peace annexation writes ownership without notifying supply")
	else:
		_pass("peace annexation notifies supply")
	var live := _slice_func(gd_src, "apply_interactive_multi_ai_day_live")
	if "apply_production_for_tag" not in live or "apply_order_panel_action" not in live:
		_fail("interactive multi-AI live body lost production / apply_supply")
	else:
		_pass("interactive multi-AI still applies production + apply_supply")


func _test_replanned_off_must_fail(sm_src: String, adv: String) -> void:
	# 5ca1d0b5: budget=2 and turning refill off still passed the whole gate.
	if "ROUTE_REFRESH_BUDGET_PER_FLUSH: int = 2" in sm_src:
		_fail("re-plan budget still 2/day (5ca1d0b5 FAIL class — dests stay dark)")
	elif "ROUTE_REFRESH_BUDGET_PER_FLUSH: int = DEFAULT_ROUTE_DEST_CAP" not in sm_src:
		_fail("re-plan budget is not the dest cap (turning re-plan off must FAIL)")
	else:
		_pass("re-plan budget equals DEFAULT_ROUTE_DEST_CAP (24 dests / 1 day)")
	if "DEFAULT_ROUTE_DEST_CAP: int = 24" not in sm_src:
		_fail("DEFAULT_ROUTE_DEST_CAP missing (cap N undocumented)")
	else:
		_pass("DEFAULT_ROUTE_DEST_CAP=24 documented as full-rebuild dest cap")
	if "flush_pending_control_route_refresh" not in adv:
		_fail("advance_supply_day no longer flushes dropped dests")
	else:
		_pass("advance_supply_day flushes dropped dests on the full day")
	if "ROUTE_REFRESH_MS_BUDGET" not in sm_src or "drain_pending_route_refresh" not in sm_src:
		_fail("same-day dest drain missing (recovery would hitch one frame)")
	else:
		_pass("same-day dest drain + per-frame plan budget present")
	var refill := _slice_func(sm_src, "_refill_missing_default_routes")
	if refill.is_empty() or "_plan_route" not in refill:
		_fail("re-plan turned off (_refill_missing_default_routes stub)")
	else:
		_pass("re-plan still plans missing dests")
	var flush := _slice_func(sm_src, "flush_pending_control_route_refresh")
	if flush.is_empty() or "_refill_missing_default_routes" not in flush:
		_fail("re-plan turned off (flush does not refill)")
	else:
		_pass("flush calls _refill_missing_default_routes")
	if "notify_hub_stats_changed" not in sm_src:
		_fail("notify_hub_stats_changed missing (5ca1d0b5 hub capacity stale)")
	else:
		_pass("notify_hub_stats_changed present")
	var mm_src := _read("res://scripts/map/MapManager.gd")
	var infra_fn := _slice_func(mm_src, "update_province_infrastructure")
	var dev_fn := _slice_func(mm_src, "update_province_development")
	if "notify_hub_stats_changed" not in infra_fn or "notify_hub_stats_changed" not in dev_fn:
		_fail("infra/dev complete does not notify hub stats (5ca1d0b5 stale from ~d28)")
	else:
		_pass("infra/dev complete notifies hub stats")


func _boot_live_supply_network(mm: Node, sm: Node) -> bool:
	if not sm.has_method("build_network"):
		return false
	var city := _load_city_layer()
	var provs: Dictionary = mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else {}
	var adj: Variant = mm.call("get_adjacency_system") if mm.has_method("get_adjacency_system") else null
	var countries: Dictionary = {}
	for tag_v in CAPITALS.keys():
		var tag := str(tag_v)
		countries[tag] = {
			"tag": tag,
			"name": tag,
			"capital_province_id": int(CAPITALS[tag]),
		}
	var t0 := Time.get_ticks_usec()
	sm.call("build_network", provs, countries, city, adj, PLAYER_TAG)
	var boot_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var hubs_n := 0
	if "hubs" in sm and sm.hubs is Dictionary:
		hubs_n = (sm.hubs as Dictionary).size()
	print("HeadlessPerf4LiveMultiAiDayTest: supply_boot=%.1fms hubs=%d city=%d" % [boot_ms, hubs_n, city.size()])
	if hubs_n < 20:
		_fail("supply boot too thin hubs=%d (need live-like city/factory hubs)" % hubs_n)
		return false
	_pass("supply network booted hubs=%d" % hubs_n)
	return true


func _reset_clock(tm: Node, elapsed: int) -> void:
	tm.set("paused", false)
	if "current_year" in tm:
		tm.set("current_year", 1936)
		tm.set("current_month", 1)
		tm.set("current_day", 1)
		tm.set("current_hour", 0)
		tm.set("total_days_elapsed", elapsed)
		tm.set("_accumulated_game_days", 0.0)
		tm.set("_accumulated_game_hours", 0.0)
	if tm.has_method("clear_day_tick_history"):
		tm.call("clear_day_tick_history")


func _test_step_costs(gd: Node, sm: Node, tm: Node) -> void:
	_reset_clock(tm, 0)
	if "_live_f5_equiv_clock" in tm:
		tm.set("_live_f5_equiv_clock", true)
	var t0 := Time.get_ticks_usec()
	var prod: Dictionary = gd.call("apply_production_for_tag", "JAP")
	var prod_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var supply: Dictionary = gd.call("apply_order_panel_action", "apply_supply", 1)
	var supply_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	# Dummy pid 1 is the live soft-tick argument. First enable must skip
	# missing pids; a second call must stay a membership no-op. Do not treat
	# a first-time add of a *real* depot as the daily hitch.
	t0 = Time.get_ticks_usec()
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", 1, true)
	var depot_first_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", 1, true)
	var depot_second_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var live: Dictionary = gd.call("apply_interactive_multi_ai_day_live", 1)
	var live_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if "_live_f5_equiv_clock" in tm:
		tm.set("_live_f5_equiv_clock", false)
	var supply_detail := ""
	if "peace_state" in gd:
		var ps: Dictionary = gd.peace_state
		var raw_last: Variant = ps.get("supply_last_live_apply", {})
		if raw_last is Dictionary:
			supply_detail = str((raw_last as Dictionary).get("detail", ""))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: steps prod=%.1fms supply=%.1fms detail=%s depot_first=%.1fms depot_second=%.1fms multi_ai=%.1fms prod_ok=%s supply_ok=%s live_ok=%s tags=%s"
		% [
			prod_ms,
			supply_ms,
			supply_detail,
			depot_first_ms,
			depot_second_ms,
			live_ms,
			str(bool(prod.get("ok", false))),
			str(bool(supply.get("ok", false))),
			str(bool(live.get("ok", false))),
			str(live.get("prod_tags", [])),
		]
	)
	if supply_detail != "advance_supply_day":
		_fail("apply_supply detail=%s (live Play must use full advance_supply_day)" % supply_detail)
	else:
		_pass("apply_supply full-day detail=%s %.1fms" % [supply_detail, supply_ms])
	if supply_ms >= DAY_BUDGET_MS:
		_fail("apply_supply %.1fms >= %.0f (live daily hitch class)" % [supply_ms, DAY_BUDGET_MS])
	else:
		_pass("apply_supply %.1fms < %.0f" % [supply_ms, DAY_BUDGET_MS])
	if live_ms >= DAY_BUDGET_MS:
		_fail("apply_interactive_multi_ai_day_live %.1fms >= %.0f (still rebuilding?)" % [live_ms, DAY_BUDGET_MS])
	else:
		_pass("apply_interactive_multi_ai_day_live %.1fms < %.0f" % [live_ms, DAY_BUDGET_MS])
	if depot_first_ms >= DAY_BUDGET_MS:
		_fail("set_player_depot(1) first %.1fms >= %.0f (dummy pid still rebuilds)" % [depot_first_ms, DAY_BUDGET_MS])
	else:
		_pass("set_player_depot(1) first skip/cheap %.1fms" % depot_first_ms)
	if depot_second_ms >= DAY_BUDGET_MS:
		_fail("set_player_depot(1) second %.1fms >= %.0f (membership no-op missed)" % [depot_second_ms, DAY_BUDGET_MS])
	else:
		_pass("set_player_depot(1) second no-op %.1fms" % depot_second_ms)


func _collect_multi_ai_days(gd: Node, tm: Node, days: int) -> Array:
	var out: Array = []
	for day_i in range(days):
		if "total_days_elapsed" in tm:
			tm.set("total_days_elapsed", day_i)
		var live: Dictionary = gd.call("apply_interactive_multi_ai_day_live", 1)
		out.append({
			"day": day_i,
			"prod_tags": (live.get("prod_tags", []) as Array).duplicate(),
			"soft_tag": str(live.get("soft_tag", "")),
			"production_n": int(live.get("production_n", 0)),
			"soft_n": int(live.get("soft_n", 0)),
			"player_tag": str(live.get("player_tag", "")),
		})
	return out


func _test_multi_ai_decisions_stable(gd: Node, tm: Node) -> void:
	seed(EQUIV_SEED)
	var a: Array = _collect_multi_ai_days(gd, tm, EQUIV_DAYS)
	seed(EQUIV_SEED)
	var b: Array = _collect_multi_ai_days(gd, tm, EQUIV_DAYS)
	if a.size() != EQUIV_DAYS or b.size() != EQUIV_DAYS:
		_fail("multi-AI decision length a=%d b=%d" % [a.size(), b.size()])
		return
	var same := true
	for i in a.size():
		if str(a[i]) != str(b[i]):
			same = false
			_fail("multi-AI day %s mismatch %s vs %s" % [str(a[i].get("day")), str(a[i]), str(b[i])])
			break
		var tags: Array = a[i].get("prod_tags", []) as Array
		if PLAYER_TAG in tags:
			same = false
			_fail("player tag %s in prod_tags %s" % [PLAYER_TAG, str(tags)])
			break
	if same:
		_pass("multi-AI decisions identical over %d days seed=%d player=%s" % [EQUIV_DAYS, EQUIV_SEED, PLAYER_TAG])
		print("HeadlessPerf4LiveMultiAiDayTest: multi_ai_decisions=%s" % str(a))


func _test_live_day_ai_budget(tm: Node, gd: Node) -> void:
	if not tm.has_method("advance_live_f5_equivalent_days"):
		_fail("advance_live_f5_equivalent_days missing")
		return
	_reset_clock(tm, 0)
	if gd.has_method("apply_interactive_multi_ai_day_live"):
		# Warm one apply so first timed day is not the only allocation spike.
		gd.call("apply_interactive_multi_ai_day_live", 1)
	var t0 := Time.get_ticks_usec()
	var clock: Dictionary = tm.call("advance_live_f5_equivalent_days", EQUIV_DAYS)
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("HeadlessPerf4LiveMultiAiDayTest: live_f5_equiv clock=%s wall=%.1fms" % [str(clock), wall_ms])
	var history: Array = []
	if tm.has_method("get_day_tick_history"):
		history = tm.call("get_day_tick_history")
	var worst := 0.0
	var worst_kind := ""
	var worst_ai := 0.0
	for raw in history:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var ms := float(row.get("worst_phase_ms", 0.0))
		if ms >= worst:
			worst = ms
			worst_kind = str(row.get("worst_phase", ""))
		var ai_ms := float(row.get("day_ai_ms", 0.0))
		if ai_ms >= worst_ai:
			worst_ai = ai_ms
		var steps: Array = row.get("day_ai_steps", []) as Array
		var step_parts: PackedStringArray = PackedStringArray()
		for sv in steps:
			if typeof(sv) != TYPE_DICTIONARY:
				continue
			var sd: Dictionary = sv
			step_parts.append("%s=%.1f" % [str(sd.get("name", "?")), float(sd.get("ms", 0.0))])
		print(
			"HeadlessPerf4LiveMultiAiDayTest: day profile emit=%.1f ai=%.1f battles=%.1f steps=[%s]"
			% [
				float(row.get("day_emit_ms", 0.0)),
				ai_ms,
				float(row.get("day_battles_ms", 0.0)),
				", ".join(step_parts),
			]
		)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: worst_phase=%s %.1fms worst_day_ai=%.1fms budget=%.0f"
		% [worst_kind, worst, worst_ai, DAY_BUDGET_MS]
	)
	if history.is_empty():
		_fail("no day-tick profile history (instrumentation not wired)")
		return
	if worst_ai < 0.01:
		_fail("day_ai never ran (interactive multi-AI skipped?)")
		return
	if worst >= DAY_BUDGET_MS:
		_fail("worst daily-tick phase %.1fms >= %.0f (%s)" % [worst, DAY_BUDGET_MS, worst_kind])
	else:
		_pass("worst daily-tick phase %.1fms < %.0f (%s)" % [worst, DAY_BUDGET_MS, worst_kind])
	if worst_ai >= DAY_BUDGET_MS:
		_fail("worst day_ai %.1fms >= %.0f (live hitch class)" % [worst_ai, DAY_BUDGET_MS])
	elif worst_ai >= QUIET_DAY_BUDGET_MS:
		_fail("worst quiet day_ai %.1fms >= %.0f (FIX #4 live-day bar)" % [worst_ai, QUIET_DAY_BUDGET_MS])
	else:
		_pass("worst day_ai %.1fms < %.0f quiet-bar" % [worst_ai, QUIET_DAY_BUDGET_MS])


func _test_repeated_real_depot_guard(sm: Node) -> void:
	if sm == null or not sm.has_method("set_player_depot"):
		_fail("set_player_depot missing")
		return
	var before := int(sm.get("network_build_count")) if "network_build_count" in sm else -1
	var patch0 := int(sm.get("network_hub_patch_count")) if "network_hub_patch_count" in sm else -1
	if before < 0 or patch0 < 0:
		_fail("depot counts missing (hub-patch mutant unguarded)")
		return
	var t_first := Time.get_ticks_usec()
	sm.call("set_player_depot", REAL_DEPOT_PID, true)
	var first_ms := float(Time.get_ticks_usec() - t_first) / 1000.0
	var after_first := int(sm.get("network_build_count"))
	var patch1 := int(sm.get("network_hub_patch_count"))
	if after_first != before:
		_fail("first real depot add builds=%d→%d (expected one-hub patch, not build_network)" % [before, after_first])
	elif patch1 != patch0 + 1:
		_fail("first real depot add patches=%d→%d (expected +1 hub patch)" % [patch0, patch1])
	elif first_ms >= DAY_BUDGET_MS:
		_fail("first real depot add %.1fms >= %.0f (2d930483 full-rebuild class)" % [first_ms, DAY_BUDGET_MS])
	else:
		_pass("first real depot add one-hub patch %.1fms" % first_ms)
	var t_rep := Time.get_ticks_usec()
	for _i in REPEAT_DEPOT_ADDS:
		sm.call("set_player_depot", REAL_DEPOT_PID, true)
	var repeat_ms := float(Time.get_ticks_usec() - t_rep) / 1000.0
	var after_rep := int(sm.get("network_build_count"))
	var patch_rep := int(sm.get("network_hub_patch_count"))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: real_depot pid=%d first=%.1fms repeat_%dx=%.1fms builds=%d→%d→%d patches=%d→%d→%d"
		% [REAL_DEPOT_PID, first_ms, REPEAT_DEPOT_ADDS, repeat_ms, before, after_first, after_rep, patch0, patch1, patch_rep]
	)
	if after_rep != after_first or patch_rep != patch1:
		_fail(
			"repeated real depot add extra work builds %d→%d patches %d→%d"
			% [after_first, after_rep, patch1, patch_rep]
		)
	else:
		_pass("repeated real depot add no extra rebuilds count=%d" % after_rep)
	if repeat_ms >= DAY_BUDGET_MS:
		_fail("repeated real depot add %.1fms >= %.0f (membership guard missed)" % [repeat_ms, DAY_BUDGET_MS])
	else:
		_pass("repeated real depot add %.1fms < %.0f" % [repeat_ms, DAY_BUDGET_MS])
	var t_rm := Time.get_ticks_usec()
	sm.call("set_player_depot", REAL_DEPOT_PID, false)
	var remove_ms := float(Time.get_ticks_usec() - t_rm) / 1000.0
	var after_rm := int(sm.get("network_build_count"))
	var patch_rm := int(sm.get("network_hub_patch_count"))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: real_depot_remove pid=%d %.1fms builds=%d→%d patches=%d→%d"
		% [REAL_DEPOT_PID, remove_ms, after_rep, after_rm, patch_rep, patch_rm]
	)
	if after_rm != after_rep:
		_fail("depot remove used build_network builds=%d→%d" % [after_rep, after_rm])
	elif patch_rm != patch_rep + 1:
		_fail("depot remove patches=%d→%d (expected +1 hub patch)" % [patch_rep, patch_rm])
	elif remove_ms >= DAY_BUDGET_MS:
		_fail("depot remove %.1fms >= %.0f (2d930483 full-rebuild class)" % [remove_ms, DAY_BUDGET_MS])
	else:
		_pass("depot remove one-hub patch %.1fms" % remove_ms)


func _test_capture_matches_full_rebuild(mm: Node, sm: Node) -> void:
	if sm == null or not sm.has_method("get_network_topology_snapshot"):
		_fail("get_network_topology_snapshot missing")
		return
	if not mm.has_method("update_province_owner"):
		_fail("update_province_owner missing")
		return
	var hubs: Dictionary = sm.hubs if "hubs" in sm else {}
	if not hubs.has(CAPTURE_HUB_PID) or not hubs.has(CAPTURE_DEPOT_PID):
		_fail("capture pids not hubs hub=%s depot=%s" % [str(hubs.has(CAPTURE_HUB_PID)), str(hubs.has(CAPTURE_DEPOT_PID))])
		return
	var hub0: Variant = hubs[CAPTURE_HUB_PID]
	var dep0: Variant = hubs[CAPTURE_DEPOT_PID]
	var hub_tag0 := str(hub0.owner_tag).to_upper() if hub0 != null else ""
	var dep_tag0 := str(dep0.owner_tag).to_upper() if dep0 != null else ""
	if hub_tag0 != "GER" or dep_tag0 != "GER":
		_fail("pre-capture hub owners hub=%s depot=%s (need GER)" % [hub_tag0, dep_tag0])
		return
	var builds_before := int(sm.get("network_build_count"))
	mm.call("update_province_owner", CAPTURE_HUB_PID, "FRA", "FRA")
	mm.call("update_province_owner", CAPTURE_DEPOT_PID, "FRA", "FRA")
	if sm.has_method("advance_supply_day"):
		sm.call("advance_supply_day", 1.0)
	var after_cap: Dictionary = sm.call("get_network_topology_snapshot")
	var owners_cap: Dictionary = after_cap.get("hub_owners", {}) as Dictionary
	var hub_tag := str(owners_cap.get(CAPTURE_HUB_PID, owners_cap.get(str(CAPTURE_HUB_PID), "")))
	var dep_tag := str(owners_cap.get(CAPTURE_DEPOT_PID, owners_cap.get(str(CAPTURE_DEPOT_PID), "")))
	# Dictionary int keys may stringify through Variant get — also check typed hub.
	if hub_tag != "FRA":
		var live_hub: Variant = (sm.hubs as Dictionary).get(CAPTURE_HUB_PID)
		if live_hub != null:
			hub_tag = str(live_hub.owner_tag).to_upper()
	if dep_tag != "FRA":
		var live_dep: Variant = (sm.hubs as Dictionary).get(CAPTURE_DEPOT_PID)
		if live_dep != null:
			dep_tag = str(live_dep.owner_tag).to_upper()
	print(
		"HeadlessPerf4LiveMultiAiDayTest: capture hub=%d %s→%s depot=%d %s→%s refresh=%s builds=%d→%d"
		% [
			CAPTURE_HUB_PID,
			hub_tag0,
			hub_tag,
			CAPTURE_DEPOT_PID,
			dep_tag0,
			dep_tag,
			str(after_cap.get("ownership_refresh_count", 0)),
			builds_before,
			int(sm.get("network_build_count")),
		]
	)
	if hub_tag != "FRA" or dep_tag != "FRA":
		_fail("after capture+day hub=%s depot=%s (stale GER network)" % [hub_tag, dep_tag])
		return
	_pass("capture retagged hub %d and depot %d to FRA" % [CAPTURE_HUB_PID, CAPTURE_DEPOT_PID])
	if int(sm.get("network_build_count")) != builds_before:
		_fail("capture used full build_network (expected incremental route patch)")
	else:
		_pass("capture patched routes without a full build_network")
	var cap_routes: Array = after_cap.get("routes", []) as Array
	if _routes_use_pid_as_dest(cap_routes, CAPTURE_HUB_PID) or _routes_use_pid_as_dest(cap_routes, CAPTURE_DEPOT_PID):
		_fail("captured pids still GER route dests")
	else:
		_pass("captured pids dropped as GER route dests n=%d" % cap_routes.size())
	if not _boot_live_supply_network(mm, sm):
		_fail("forced rebuild after capture failed")
		return
	var after_full: Dictionary = sm.call("get_network_topology_snapshot")
	var owners_full: Dictionary = after_full.get("hub_owners", {}) as Dictionary
	var hub_full := str(owners_full.get(CAPTURE_HUB_PID, ""))
	var dep_full := str(owners_full.get(CAPTURE_DEPOT_PID, ""))
	if hub_full != "FRA":
		var fh: Variant = (sm.hubs as Dictionary).get(CAPTURE_HUB_PID)
		if fh != null:
			hub_full = str(fh.owner_tag).to_upper()
	if dep_full != "FRA":
		var fd: Variant = (sm.hubs as Dictionary).get(CAPTURE_DEPOT_PID)
		if fd != null:
			dep_full = str(fd.owner_tag).to_upper()
	if hub_full != "FRA" or dep_full != "FRA":
		_fail("forced rebuild owners hub=%s depot=%s" % [hub_full, dep_full])
		return
	_pass("capture hub owners match forced rebuild")


func _route_topology_matches(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var keys_a: PackedStringArray = PackedStringArray()
	var keys_b: PackedStringArray = PackedStringArray()
	for raw in a:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		keys_a.append("%s:%s:%s" % [str(row.get("key", "")), str(row.get("src", "")), str(row.get("dst", ""))])
	for raw_b in b:
		if typeof(raw_b) != TYPE_DICTIONARY:
			continue
		var row_b: Dictionary = raw_b
		keys_b.append("%s:%s:%s" % [str(row_b.get("key", "")), str(row_b.get("src", "")), str(row_b.get("dst", ""))])
	keys_a.sort()
	keys_b.sort()
	return "\n".join(keys_a) == "\n".join(keys_b)


func _routes_use_pid_as_dest(routes: Array, pid: int) -> bool:
	for raw in routes:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if int(row.get("dst", -1)) == pid:
			return true
	return false


func _hub_owner_tag(sm: Node, pid: int) -> String:
	if sm == null or not ("hubs" in sm):
		return ""
	var hub: Variant = (sm.hubs as Dictionary).get(pid)
	if hub == null:
		return ""
	return str(hub.owner_tag).strip_edges().to_upper()


func _restore_owner(mm: Node, pid: int, tag: String) -> void:
	if mm != null and mm.has_method("update_province_owner"):
		mm.call("update_province_owner", pid, tag, tag)


func _collect_ger_hub_pids(sm: Node, limit: int, exclude: Array) -> Array[int]:
	var out: Array[int] = []
	if sm == null or not ("hubs" in sm):
		return out
	var hubs: Dictionary = sm.hubs as Dictionary
	var keys: Array = hubs.keys()
	keys.sort()
	for pid_v in keys:
		var pid := int(pid_v)
		if pid == int(CAPITALS.get("GER", 0)):
			continue
		if pid in exclude:
			continue
		var hub: Variant = hubs.get(pid_v)
		if hub == null:
			continue
		if str(hub.owner_tag).to_upper() != "GER":
			continue
		out.append(pid)
		if out.size() >= limit:
			break
	return out


func _test_capture_frame_budgets(mm: Node, sm: Node) -> void:
	if mm == null or sm == null or not mm.has_method("update_province_owner"):
		_fail("capture-frame budget helpers missing")
		return
	if _hub_owner_tag(sm, CAPTURE_HUB_PID) != "GER":
		_fail("single-capture budget needs GER hub %d" % CAPTURE_HUB_PID)
		return
	var t_one := Time.get_ticks_usec()
	mm.call("update_province_owner", CAPTURE_HUB_PID, "FRA", "FRA")
	var one_ms := float(Time.get_ticks_usec() - t_one) / 1000.0
	print("HeadlessPerf4LiveMultiAiDayTest: capture_frame_single pid=%d %.1fms" % [CAPTURE_HUB_PID, one_ms])
	if _hub_owner_tag(sm, CAPTURE_HUB_PID) != "FRA":
		_fail("single capture left hub owner %s" % _hub_owner_tag(sm, CAPTURE_HUB_PID))
	elif one_ms >= CAPTURE_FRAME_BUDGET_MS:
		_fail("single capture %.1fms >= %.0f (FIX #4 capture-frame bar)" % [one_ms, CAPTURE_FRAME_BUDGET_MS])
	else:
		_pass("single capture frame %.1fms < %.0f" % [one_ms, CAPTURE_FRAME_BUDGET_MS])
	_restore_owner(mm, CAPTURE_HUB_PID, "GER")
	var ten: Array[int] = _collect_ger_hub_pids(sm, 10, [])
	if ten.size() < 10:
		_fail("ten-capture budget needs 10 GER hubs got=%d" % ten.size())
		return
	var t_ten := Time.get_ticks_usec()
	for pid in ten:
		mm.call("update_province_owner", pid, "FRA", "FRA")
	var ten_ms := float(Time.get_ticks_usec() - t_ten) / 1000.0
	print("HeadlessPerf4LiveMultiAiDayTest: capture_frame_ten n=%d %.1fms pids=%s" % [ten.size(), ten_ms, str(ten)])
	var tagged := 0
	for pid2 in ten:
		if _hub_owner_tag(sm, pid2) == "FRA":
			tagged += 1
	if tagged != ten.size():
		_fail("ten-capture retagged %d/%d hubs" % [tagged, ten.size()])
	elif ten_ms >= CAPTURE_FRAME_BUDGET_MS:
		_fail("ten captures %.1fms >= %.0f (FIX #4 capture-frame bar)" % [ten_ms, CAPTURE_FRAME_BUDGET_MS])
	else:
		_pass("ten-capture tick %.1fms < %.0f" % [ten_ms, CAPTURE_FRAME_BUDGET_MS])
	for pid3 in ten:
		_restore_owner(mm, pid3, "GER")


func _test_peace_annexation_updates_supply(gd: Node, mm: Node, sm: Node) -> void:
	if gd == null or not gd.has_method("apply_peace_conference_settlement_live"):
		_fail("apply_peace_conference_settlement_live missing")
		return
	var pids: Array[int] = _collect_ger_hub_pids(sm, 1, [CAPTURE_HUB_PID, CAPTURE_DEPOT_PID, int(CAPITALS.get("GER", 0))])
	if pids.is_empty():
		_fail("peace annexation needs a GER hub")
		return
	var pid := pids[0]
	if _hub_owner_tag(sm, pid) != "GER":
		_fail("peace annexation pre-owner %s" % _hub_owner_tag(sm, pid))
		return
	var refresh0 := int(sm.get("network_ownership_refresh_count"))
	var res: Dictionary = gd.call("apply_peace_conference_settlement_live", "FRA", "GER", pid, true, false, 0.0, false)
	var after_tag := _hub_owner_tag(sm, pid)
	var refresh1 := int(sm.get("network_ownership_refresh_count"))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: peace_annex pid=%d hub=%s refresh=%d→%d ok=%s"
		% [pid, after_tag, refresh0, refresh1, str(bool(res.get("ok", false)))]
	)
	if after_tag != "FRA":
		_fail("peace annexation left supply hub %s (direct owner write?)" % after_tag)
	elif refresh1 <= refresh0:
		_fail("peace annexation did not notify supply refresh=%d→%d" % [refresh0, refresh1])
	else:
		_pass("peace annexation retagged hub %d and notified supply" % pid)
	_restore_owner(mm, pid, "GER")


func _route_paths_identical(a: Array, b: Array) -> bool:
	var paths_a: Dictionary = {}
	var paths_b: Dictionary = {}
	for raw in a:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		paths_a[str(row.get("key", ""))] = str(row.get("path", []))
	for raw_b in b:
		if typeof(raw_b) != TYPE_DICTIONARY:
			continue
		var row_b: Dictionary = raw_b
		paths_b[str(row_b.get("key", ""))] = str(row_b.get("path", []))
	if paths_a.size() != paths_b.size():
		return false
	for key_v in paths_a.keys():
		if not paths_b.has(key_v):
			return false
		if str(paths_a[key_v]) != str(paths_b[key_v]):
			return false
	return true


func _path_mismatch_count(a: Array, b: Array) -> int:
	var paths_a: Dictionary = {}
	var paths_b: Dictionary = {}
	for raw in a:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		paths_a[str(row.get("key", ""))] = str(row.get("path", []))
	for raw_b in b:
		if typeof(raw_b) != TYPE_DICTIONARY:
			continue
		var row_b: Dictionary = raw_b
		paths_b[str(row_b.get("key", ""))] = str(row_b.get("path", []))
	var n: int = 0
	var keys: Dictionary = {}
	for k in paths_a.keys():
		keys[k] = true
	for k2 in paths_b.keys():
		keys[k2] = true
	for key_v in keys.keys():
		if str(paths_a.get(key_v, "")) != str(paths_b.get(key_v, "")):
			n += 1
	return n


func _test_ten_capture_path_identity_within_one_day(mm: Node, sm: Node) -> void:
	if sm == null or not sm.has_method("get_network_topology_snapshot"):
		_fail("ten-capture path identity helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("ten-capture identity boot failed")
		return
	var ten: Array[int] = _collect_ger_hub_pids(sm, 10, [])
	if ten.size() < 10:
		_fail("ten-capture identity needs 10 GER hubs got=%d" % ten.size())
		return
	var refill0: int = int(sm.get("network_route_refill_count"))
	var missing0: int = int(sm.call("count_missing_default_dests")) if sm.has_method("count_missing_default_dests") else -1
	for pid in ten:
		mm.call("update_province_owner", pid, "FRA", "FRA")
	var missing_cap: int = int(sm.call("count_missing_default_dests")) if sm.has_method("count_missing_default_dests") else -1
	print(
		"HeadlessPerf4LiveMultiAiDayTest: ten_capture_drop missing=%d→%d pids=%s"
		% [missing0, missing_cap, str(ten)]
	)
	if missing_cap <= 0:
		_fail("ten captures dropped no dests (re-plan-off mutant unguarded)")
		for pid_r in ten:
			_restore_owner(mm, pid_r, "GER")
		return
	var t_day: int = Time.get_ticks_usec()
	sm.call("advance_supply_day", 1.0)
	var day_ms: float = float(Time.get_ticks_usec() - t_day) / 1000.0
	var t_drain: int = Time.get_ticks_usec()
	var drained: int = int(sm.call("drain_pending_route_refresh")) if sm.has_method("drain_pending_route_refresh") else 0
	var drain_ms: float = float(Time.get_ticks_usec() - t_drain) / 1000.0
	var missing1: int = int(sm.call("count_missing_default_dests"))
	var refill1: int = int(sm.get("network_route_refill_count"))
	var prof: Dictionary = sm.get("last_supply_day_profile") if "last_supply_day_profile" in sm else {}
	print(
		"HeadlessPerf4LiveMultiAiDayTest: ten_capture_recovery day=%.1fms drain=%.1fms drained=%d missing=%d refill=%d→%d profile=%s"
		% [day_ms, drain_ms, drained, missing1, refill0, refill1, str(prof)]
	)
	if missing1 != 0:
		_fail("ten-capture dests still missing after 1 day n=%d (5ca1d0b5 budget=2 class)" % missing1)
	elif refill1 <= refill0:
		_fail("ten-capture 1-day refill_count unchanged %d→%d (re-plan turned off)" % [refill0, refill1])
	else:
		_pass("ten-capture recovered all dests in 1 day missing=0 refill+%d" % (refill1 - refill0))
	if day_ms >= RECOVERY_DAY_BUDGET_MS:
		_fail("ten-capture live day frame %.1fms >= %.0f" % [day_ms, RECOVERY_DAY_BUDGET_MS])
	else:
		_pass("ten-capture live day frame %.1fms < %.0f" % [day_ms, RECOVERY_DAY_BUDGET_MS])
	var live: Dictionary = sm.call("get_network_topology_snapshot")
	if not _boot_live_supply_network(mm, sm):
		_fail("ten-capture forced rebuild failed")
		for pid_r2 in ten:
			_restore_owner(mm, pid_r2, "GER")
		return
	var full: Dictionary = sm.call("get_network_topology_snapshot")
	var live_routes: Array = live.get("routes", []) as Array
	var full_routes: Array = full.get("routes", []) as Array
	var mismatch: int = _path_mismatch_count(live_routes, full_routes)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: ten_capture_paths live_n=%d full_n=%d mismatch=%d"
		% [live_routes.size(), full_routes.size(), mismatch]
	)
	if not _route_paths_identical(live_routes, full_routes):
		_fail("ten-capture paths != forced rebuild mismatch=%d (5ca1d0b5 equal-length drift)" % mismatch)
	else:
		_pass("ten-capture paths match forced rebuild n=%d" % live_routes.size())
	for pid_r3 in ten:
		_restore_owner(mm, pid_r3, "GER")
	_boot_live_supply_network(mm, sm)


func _test_annex_path_identity(gd: Node, mm: Node, sm: Node) -> void:
	if gd == null or not gd.has_method("apply_peace_conference_settlement_live"):
		_fail("annex path identity helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("annex path identity boot failed")
		return
	var pids: Array[int] = _collect_ger_hub_pids(sm, 1, [CAPTURE_HUB_PID, CAPTURE_DEPOT_PID, int(CAPITALS.get("GER", 0))])
	if pids.is_empty():
		_fail("annex path identity needs a GER hub")
		return
	var pid: int = pids[0]
	var res: Dictionary = gd.call("apply_peace_conference_settlement_live", "FRA", "GER", pid, true, false, 0.0, false)
	if not bool(res.get("ok", false)) and _hub_owner_tag(sm, pid) != "FRA":
		_fail("annex path identity settlement failed pid=%d" % pid)
		return
	sm.call("advance_supply_day", 1.0)
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	var missing: int = int(sm.call("count_missing_default_dests")) if sm.has_method("count_missing_default_dests") else -1
	if missing != 0:
		_fail("annex dests still missing after 1 day n=%d" % missing)
	else:
		_pass("annex recovered dests in 1 day")
	var live: Dictionary = sm.call("get_network_topology_snapshot")
	if not _boot_live_supply_network(mm, sm):
		_fail("annex forced rebuild failed")
		_restore_owner(mm, pid, "GER")
		return
	var full: Dictionary = sm.call("get_network_topology_snapshot")
	var live_routes: Array = live.get("routes", []) as Array
	var full_routes: Array = full.get("routes", []) as Array
	var mismatch: int = _path_mismatch_count(live_routes, full_routes)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: annex_paths pid=%d live_n=%d full_n=%d mismatch=%d"
		% [pid, live_routes.size(), full_routes.size(), mismatch]
	)
	if not _route_paths_identical(live_routes, full_routes):
		_fail("annex paths != forced rebuild mismatch=%d (5ca1d0b5 equal-length drift)" % mismatch)
	else:
		_pass("annex paths match forced rebuild n=%d" % live_routes.size())
	_restore_owner(mm, pid, "GER")
	_boot_live_supply_network(mm, sm)


func _test_hub_capacity_on_infra_complete(mm: Node, sm: Node) -> void:
	if mm == null or sm == null or not mm.has_method("update_province_infrastructure"):
		_fail("hub capacity infra helpers missing")
		return
	if not sm.has_method("notify_hub_stats_changed") and not ("network_hub_stats_refresh_count" in sm):
		_fail("notify_hub_stats_changed missing (5ca1d0b5 FAIL class)")
		return
	var ger_cap: int = int(CAPITALS.get("GER", 0))
	var hubs: Dictionary = sm.hubs if "hubs" in sm else {}
	if not hubs.has(ger_cap):
		_fail("GER capital %d is not a hub" % ger_cap)
		return
	var hub0: Variant = hubs[ger_cap]
	var cap0: float = float(hub0.storage_capacity) if hub0 != null else 0.0
	var p: Variant = mm.call("get_province", ger_cap)
	if p == null:
		_fail("GER capital province missing")
		return
	var infra0: int = int(p.infrastructure)
	var stats0: int = int(sm.get("network_hub_stats_refresh_count"))
	mm.call("update_province_infrastructure", ger_cap, infra0 + 1)
	var hub1: Variant = (sm.hubs as Dictionary).get(ger_cap)
	var cap1: float = float(hub1.storage_capacity) if hub1 != null else 0.0
	var stats1: int = int(sm.get("network_hub_stats_refresh_count"))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: hub_infra_complete pid=%d infra=%d→%d cap=%.0f→%.0f stats=%d→%d"
		% [ger_cap, infra0, infra0 + 1, cap0, cap1, stats0, stats1]
	)
	if stats1 <= stats0:
		_fail("infra complete did not refresh hub stats (5ca1d0b5 stale capacity)")
	elif cap1 <= cap0:
		_fail("infra complete left hub capacity %.0f (expected increase)" % cap1)
	else:
		_pass("infra complete recalculated hub capacity %.0f→%.0f" % [cap0, cap1])
	if not _boot_live_supply_network(mm, sm):
		_fail("hub capacity rebuild after infra failed")
		return
	var hub_full: Variant = (sm.hubs as Dictionary).get(ger_cap)
	var cap_full: float = float(hub_full.storage_capacity) if hub_full != null else -1.0
	if not is_equal_approx(cap1, cap_full):
		_fail("infra hub capacity %.0f != rebuild %.0f" % [cap1, cap_full])
	else:
		_pass("infra hub capacity matches rebuild %.0f" % cap_full)


func _test_hub_capacity_matches_rebuild_at_day_40(tm: Node, mm: Node, sm: Node) -> void:
	if tm == null or sm == null or not tm.has_method("advance_live_f5_equivalent_days"):
		_fail("day-40 hub capacity helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("day-40 hub capacity boot failed")
		return
	_reset_clock(tm, 0)
	# advance_live_f5_equivalent_days clamps to 20; two clocks reach day 40.
	var clock: Dictionary = tm.call("advance_live_f5_equivalent_days", 20)
	var clock2: Dictionary = tm.call("advance_live_f5_equivalent_days", 20)
	clock["days"] = int(clock.get("days", 0)) + int(clock2.get("days", 0))
	clock["elapsed"] = clock2.get("elapsed", clock.get("elapsed", 0))
	clock["day"] = clock2.get("day", clock.get("day", 0))
	clock["second"] = clock2
	var live_caps: Dictionary = sm.call("get_hub_capacity_snapshot") if sm.has_method("get_hub_capacity_snapshot") else {}
	if live_caps.is_empty() and "hubs" in sm:
		for pid_v in (sm.hubs as Dictionary).keys():
			var h: Variant = (sm.hubs as Dictionary).get(pid_v)
			if h != null:
				live_caps[int(pid_v)] = float(h.storage_capacity)
	if not _boot_live_supply_network(mm, sm):
		_fail("day-40 forced rebuild failed")
		return
	var full_caps: Dictionary = sm.call("get_hub_capacity_snapshot") if sm.has_method("get_hub_capacity_snapshot") else {}
	var mismatch: int = 0
	var checked: int = 0
	var sample: PackedStringArray = PackedStringArray()
	for tag_v in CAPITALS.keys():
		var pid: int = int(CAPITALS[tag_v])
		if not live_caps.has(pid) and not live_caps.has(str(pid)):
			continue
		var live_c: float = float(live_caps.get(pid, live_caps.get(str(pid), 0.0)))
		var full_c: float = float(full_caps.get(pid, full_caps.get(str(pid), 0.0)))
		checked += 1
		if not is_equal_approx(live_c, full_c):
			mismatch += 1
			sample.append("%s %d live=%.0f full=%.0f" % [str(tag_v), pid, live_c, full_c])
	print(
		"HeadlessPerf4LiveMultiAiDayTest: hub_capacity_day40 clock=%s checked=%d mismatch=%d sample=%s"
		% [str(clock), checked, mismatch, ", ".join(sample)]
	)
	if checked == 0:
		_fail("day-40 hub capacity found no capital hubs")
	elif mismatch > 0:
		_fail("day-40 hub capacity != rebuild mismatch=%d %s (5ca1d0b5 stale from ~d28)" % [mismatch, ", ".join(sample)])
	else:
		_pass("day-40 hub capacity matches full rebuild capitals=%d" % checked)


func _test_one_full_supply_day_per_game_day(tm: Node, gd: Node, sm: Node) -> void:
	if tm == null or sm == null or not tm.has_method("advance_live_f5_equivalent_days"):
		_fail("one-full-day helpers missing")
		return
	if not ("full_supply_day_count" in sm):
		_fail("full_supply_day_count missing (2d930483 uncounted double day)")
		return
	_reset_clock(tm, 0)
	sm.set("full_supply_day_count", 0)
	var days := 3
	var clock: Dictionary = tm.call("advance_live_f5_equivalent_days", days)
	var full_n := int(sm.get("full_supply_day_count"))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: full_supply_days days=%d full=%d clock=%s"
		% [days, full_n, str(clock)]
	)
	if full_n != days:
		_fail("full supply days=%d for %d game days (want exactly one; 2d930483 ran two)" % [full_n, days])
	else:
		_pass("exactly one full supply day per game day (%d)" % full_n)


func _test_production_cache_measured(gd: Node) -> void:
	var pm: Node = root.get_node_or_null("/root/ProductionManager")
	if pm == null or not pm.has_method("advance_days_for_country"):
		_fail("ProductionManager.advance_days_for_country missing")
		return
	if not pm.has_method("begin_interactive_multi_ai_day_cache"):
		_fail("production day cache missing")
		return
	_seed_oob_lines(pm, 12)
	if pm.has_method("end_interactive_multi_ai_day_cache"):
		pm.call("end_interactive_multi_ai_day_cache")
	var scan0 := int(pm.get("interactive_ai_line_scan_count")) if "interactive_ai_line_scan_count" in pm else -1
	if scan0 < 0:
		_fail("interactive_ai_line_scan_count missing")
		return
	var t_unc := Time.get_ticks_usec()
	for _i in 8:
		pm.call("advance_days_for_country", "JAP", 1.0)
		pm.call("advance_days_for_country", "SOV", 1.0)
		pm.call("advance_days_for_country", "ITA", 1.0)
	var uncached_ms := float(Time.get_ticks_usec() - t_unc) / 1000.0
	var scan_unc := int(pm.get("interactive_ai_line_scan_count")) - scan0
	pm.call("begin_interactive_multi_ai_day_cache")
	var scan1 := int(pm.get("interactive_ai_line_scan_count"))
	var t_c := Time.get_ticks_usec()
	for _j in 8:
		pm.call("advance_days_for_country", "JAP", 1.0)
		pm.call("advance_days_for_country", "SOV", 1.0)
		pm.call("advance_days_for_country", "ITA", 1.0)
	var cached_ms := float(Time.get_ticks_usec() - t_c) / 1000.0
	var scan_c := int(pm.get("interactive_ai_line_scan_count")) - scan1
	if pm.has_method("end_interactive_multi_ai_day_cache"):
		pm.call("end_interactive_multi_ai_day_cache")
	print(
		"HeadlessPerf4LiveMultiAiDayTest: prod_cache uncached=%.2fms scans=%d cached=%.2fms scans=%d"
		% [uncached_ms, scan_unc, cached_ms, scan_c]
	)
	if scan_unc < 8:
		_fail("uncached production walks too few scans=%d" % scan_unc)
	else:
		_pass("uncached production full-line scans=%d" % scan_unc)
	if scan_c != 0:
		_fail("cached production still scanned lines scans=%d (cache reverted?)" % scan_c)
	else:
		_pass("cached production full-line scans=0")
	if cached_ms <= 0.0 or uncached_ms <= cached_ms:
		_fail("production cache no timing benefit cached=%.2fms uncached=%.2fms" % [cached_ms, uncached_ms])
	else:
		_pass("production cache timing cached=%.2fms < uncached=%.2fms" % [cached_ms, uncached_ms])


func _seed_oob_lines(pm: Node, per_tag: int) -> void:
	if pm == null or not pm.has_method("create_line"):
		return
	for tag_v in ["JAP", "SOV", "ITA", "FRA", "ENG", "USA", "POL"]:
		for i in per_tag:
			pm.call("create_line", "oob_%s_infantry_%d" % [str(tag_v), i])


func _test_owner_index_measured(mm: Node) -> void:
	if not mm.has_method("get_provinces_by_owner"):
		_fail("get_provinces_by_owner missing")
		return
	if not mm.has_method("_invalidate_owner_index"):
		_fail("owner index invalidate missing")
		return
	var all_p: Dictionary = mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else {}
	var brute: Dictionary = {}
	for pid_v in all_p.keys():
		var p = all_p[pid_v]
		if p == null:
			continue
		var ot := str(p.owner_tag).strip_edges().to_upper()
		if ot.is_empty():
			continue
		if not brute.has(ot):
			brute[ot] = []
		(brute[ot] as Array).append(int(pid_v))
	mm.call("_invalidate_owner_index")
	var builds0 := int(mm.get("owner_index_build_count")) if "owner_index_build_count" in mm else -1
	if builds0 < 0:
		_fail("owner_index_build_count missing")
		return
	var t_build := Time.get_ticks_usec()
	var ger_idx: Array = mm.call("get_provinces_by_owner", "GER")
	var build_ms := float(Time.get_ticks_usec() - t_build) / 1000.0
	var builds1 := int(mm.get("owner_index_build_count"))
	if builds1 != builds0 + 1:
		_fail("owner index dirty rebuild count %d→%d" % [builds0, builds1])
	var t_cached := Time.get_ticks_usec()
	for _i in 64:
		mm.call("get_provinces_by_owner", "GER")
		mm.call("get_provinces_by_owner", "FRA")
	var cached_ms := float(Time.get_ticks_usec() - t_cached) / 1000.0
	var builds2 := int(mm.get("owner_index_build_count"))
	var t_brute := Time.get_ticks_usec()
	for _j in 64:
		var _n := 0
		for pid_v2 in all_p.keys():
			var p2 = all_p[pid_v2]
			if p2 != null and str(p2.owner_tag).to_upper() == "GER":
				_n += 1
			if p2 != null and str(p2.owner_tag).to_upper() == "FRA":
				_n += 1
	var brute_ms := float(Time.get_ticks_usec() - t_brute) / 1000.0
	var ger_brute: Array = brute.get("GER", []) as Array
	ger_idx.sort()
	ger_brute.sort()
	print(
		"HeadlessPerf4LiveMultiAiDayTest: owner_index build=%.2fms cached64=%.2fms brute64=%.2fms builds=%d→%d→%d ger=%d"
		% [build_ms, cached_ms, brute_ms, builds0, builds1, builds2, ger_idx.size()]
	)
	if str(ger_idx) != str(ger_brute):
		_fail("owner index membership != brute walk idx=%d brute=%d" % [ger_idx.size(), ger_brute.size()])
	else:
		_pass("owner index membership matches brute walk n=%d" % ger_idx.size())
	if builds2 != builds1:
		_fail("cached owner lookups rebuilt index %d extra times" % (builds2 - builds1))
	else:
		_pass("cached owner lookups builds unchanged=%d" % builds2)
	if cached_ms <= 0.0 or brute_ms <= cached_ms:
		_fail("owner index no timing benefit cached=%.2fms brute=%.2fms" % [cached_ms, brute_ms])
	else:
		_pass("owner index timing cached64=%.2fms < brute64=%.2fms" % [cached_ms, brute_ms])
	# Capture already flipped 710160/710161 to FRA — index must not stay GER.
	var ger_after: Array = mm.call("get_provinces_by_owner", "GER")
	if CAPTURE_HUB_PID in ger_after or CAPTURE_DEPOT_PID in ger_after:
		_fail("owner index stale after capture still lists GER hub/depot")
	else:
		_pass("owner index dropped captured hub/depot from GER")


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
	var city := _load_city_layer()
	var countries: Dictionary = {}
	for tag_v in CAPITALS.keys():
		var tag := str(tag_v)
		countries[tag] = {
			"tag": tag,
			"name": tag,
			"capital_province_id": int(CAPITALS[tag]),
		}
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
		if "development_level" in p:
			p.development_level = 3
		if not bool(p.is_sea):
			p.factories = 1
		if city.has(str(pid)) and city[str(pid)] is Dictionary:
			var city_row: Dictionary = city[str(pid)]
			if int(city_row.get("tier", 0)) >= 2:
				p.factories = maxi(int(p.factories), 2)
		for cap_tag in CAPITALS.keys():
			if int(CAPITALS[cap_tag]) == pid:
				if "special_features" in p and p.special_features is Dictionary:
					(p.special_features as Dictionary)["capital"] = 1
		provs[pid] = p
	var geometry: Dictionary = {}
	for row in geo.get("provinces", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid2 := int(row.get("id", 0))
		if pid2 <= 0:
			continue
		var pts: Array = row.get("points", [])
		var packed := PackedVector2Array()
		for pt in pts:
			if pt is Array and pt.size() >= 2:
				packed.append(Vector2(float(pt[0]), float(pt[1])))
		geometry[pid2] = {
			"points": packed,
			"label_anchor": row.get("label_anchor", []),
			"meta": row.get("meta", {}),
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
	var map_data = MapDataScript.new(provs, geometry, adj, countries)
	mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	return true


func _load_city_layer() -> Dictionary:
	var doc := _load_json(CITY_PATH)
	var raw: Variant = doc.get("provinces", doc)
	return raw if raw is Dictionary else {}


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
