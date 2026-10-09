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
const CAPTURE_FRAME_BUDGET_MS := 5.0
const DAYROLL_CAPTURE_BUDGET_MS := 200.0
const DAYROLL_OWN_SHARE_BUDGET_MS := 300.0
const DEFAULT_ROUTE_DEST_CAP_HINT := 24
const SLICE_ESTIMATE_MS := 25.0
const HUB_CAPACITY_DAY := 40
const CAPTURE_HUB_PID := 710160
const CAPTURE_DEPOT_PID := 710161
const REAL_DEPOT_PID := 710300
const DEPOT_ADD_PID := 710314
const RECAPTURE_PATH_PID := 710314
const SWI_PID := 710119
const REPEAT_DEPOT_ADDS := 4
const CONVERGE_FRAMES := 40
const FRAMES_PER_DAY_1X := 60
const FRAMES_PER_DAY_4X := 30
const MAX_PLANS_PER_FLUSH_SLICE := 8
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
	_test_depot_add_710314_converges(sm)
	_test_recapture_ger_converges(mm, sm)
	_test_multi_round_capture_round3_converges(mm, sm)
	_test_annex_and_depot_remove_zero_missing(gd, mm, sm)
	_test_keep_old_routes_until_swap(sm)
	_test_ten_capture_drains_one_day_1x_and_4x(mm, sm)
	_test_slice_caps_plans_per_frame(sm)
	_test_relations_access_clears_friendly_cache(sm)
	_test_recapture_710314_path_identity(mm, sm)
	_test_military_access_path_identity(mm, sm)
	_test_fifo_dequeue_matches_enqueue(sm)
	_test_slice_predictive_vs_reactive_seam(sm)
	_test_dayroll_with_capture_under_200ms(tm, mm, sm)
	_test_redrop_counter_increments_on_hostile_drop(mm, sm)
	_test_depot_add_replans_only_touched_dests(sm)
	_test_dayroll_event_own_share_under_300ms(tm, mm, gd, sm)
	_test_one_full_supply_day_per_game_day(tm, gd, sm)
	_test_production_cache_measured(gd)
	_test_owner_index_measured(mm)
	_test_multi_ai_decisions_stable(gd, tm)
	_test_live_day_ai_budget(tm, gd)
	_test_hub_capacity_on_infra_complete(mm, sm)
	_test_hub_capacity_matches_rebuild_at_day_40(tm, mm, sm)
	_test_gamedata_direct_infra_notifies_hub_stats(gd, mm, sm)


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
	if "ROUTE_REFRESH_MS_BUDGET: float = 40.0" not in sm_src:
		_fail("predictive slice is not 40 ms (FIX #5 refill-frame budget)")
	else:
		_pass("predictive slice budget is 40 ms")
	var refill := _slice_func(sm_src, "_refill_queued_dests")
	if refill.is_empty() or "_plan_route" not in refill:
		_fail("re-plan turned off (_refill_queued_dests stub)")
	else:
		_pass("re-plan still plans queued dests")
	if "used_ms + next_est" not in refill and "used_ms + next_est" not in sm_src:
		_fail("slice removed (predictive used+next check missing)")
	else:
		_pass("predictive slice stops before the next plan crosses the budget")
	if "route_refresh_plan_cost_estimate_ms" not in sm_src:
		_fail("slice plan-cost estimate seam missing (slice_reactive unguarded)")
	else:
		_pass("slice plan-cost estimate seam present")
	var flush := _slice_func(sm_src, "flush_pending_control_route_refresh")
	if flush.is_empty() or "_refill_queued_dests" not in flush:
		_fail("re-plan turned off (flush does not pop the dest queue)")
	else:
		_pass("flush pops the dest refill queue")
	if "_drop_routes_touching_pid(" in flush:
		_fail("re-drop restored (flush re-drops dirty pids — FIX #4 livelock)")
	else:
		_pass("flush never re-drops (deduped FIFO only)")
	if "_note_flush_redrop" not in sm_src or "network_route_redrop_count +=" not in sm_src:
		_fail("redrop counters never increment (redrop_restored tautology)")
	else:
		_pass("flush redrop counters increment on a planned-route drop")
	if "pop_front" not in refill:
		_fail("refill queue is not FIFO (pop_front missing)")
	else:
		_pass("refill dequeues from the front (FIFO)")
	if "_drop_all_default_routes" in flush or "_must_replan_all_defaults" in flush:
		_fail("flush still drop-alls remaining defaults")
	else:
		_pass("flush does not drop-all remaining defaults")
	if "_refill_queue" not in sm_src or "_refill_queued" not in sm_src:
		_fail("deduped FIFO refill queue missing")
	else:
		_pass("deduped FIFO refill queue present")
	var notify := _slice_func(sm_src, "notify_province_control_changed")
	if "_pid_blocks_player_supply" not in notify:
		_fail("no old-route keep (notify drops friendly-touching routes)")
	else:
		_pass("notify drops only hostile/impassable routes")
	if "_enqueue_all_current_dests" not in notify:
		_fail("friendly gain does not enqueue all dests (recapture pathdiff)")
	else:
		_pass("friendly gain enqueues all default dests")
	if "notify_hub_stats_changed" not in sm_src:
		_fail("notify_hub_stats_changed missing (5ca1d0b5 hub capacity stale)")
	else:
		_pass("notify_hub_stats_changed present")
	if "_on_relations_or_access_changed" not in sm_src:
		_fail("relations/access does not clear the pathfinder friendly cache")
	else:
		_pass("relations/access clears the pathfinder friendly cache")
	var rel_fn := _slice_func(sm_src, "_on_relations_or_access_changed")
	if "_enqueue_all_current_dests" not in rel_fn:
		_fail("relations/access clears cache but enqueues nothing (access pathdiff)")
	else:
		_pass("relations/access enqueues all default dests")
	if "_relations_change_involves_supply_owner" not in rel_fn and "player_tag" not in rel_fn:
		_fail("access/relations re-enqueues when the player is not a party")
	else:
		_pass("access/relations enqueues only when the player supply owner is a party")
	if (
		"_plan_route" in rel_fn
		or "flush_pending_control_route_refresh" in rel_fn
		or "_refill_queued_dests" in rel_fn
	):
		_fail("access/relations plans immediately (access not deferred)")
	else:
		_pass("access/relations only enqueues (same day-roll deferral)")
	var adv_defer := _slice_func(sm_src, "advance_supply_day")
	var flush_defer := _slice_func(sm_src, "flush_pending_control_route_refresh")
	var proc_fn := _slice_func(sm_src, "_process")
	if "_begin_day_roll_plan_deferral" not in adv_defer:
		_fail("advance_supply_day does not mark the day-roll plan frame")
	elif "_is_day_roll_plan_frame" not in flush_defer:
		_fail("flush still plans on the day-roll frame")
	elif "_is_day_roll_plan_frame" not in proc_fn:
		_fail("_process still plans on the day-roll frame")
	else:
		_pass("day-roll frame defers route plans to the next 40 ms slice")
	var patch := _slice_func(sm_src, "_patch_player_depot_hub")
	if "_enqueue_all_current_dests" in patch:
		_fail("depot add always re-plans all 24 dests")
	elif "_enqueue_missing_and_affected_dests" not in patch:
		_fail("depot add/remove does not enqueue only touched dests")
	else:
		_pass("depot add/remove enqueues only touched dests")
	var mm_src := _read("res://scripts/map/MapManager.gd")
	var infra_fn := _slice_func(mm_src, "update_province_infrastructure")
	var dev_fn := _slice_func(mm_src, "update_province_development")
	var changed_fn := _slice_func(mm_src, "notify_province_changed")
	if "notify_hub_stats_changed" not in infra_fn or "notify_hub_stats_changed" not in dev_fn:
		_fail("infra/dev complete does not notify hub stats (5ca1d0b5 stale from ~d28)")
	else:
		_pass("infra/dev complete notifies hub stats")
	if "notify_hub_stats_changed" not in changed_fn:
		_fail("notify_province_changed skips hub stats (GameData direct infra writes)")
	else:
		_pass("notify_province_changed notifies hub stats on infra/dev")
	var gd_src := _read(SRC_GD)
	if gd_src.find("notify_hub_stats_changed") < 0:
		_fail("GameData direct infra writes skip notify_hub_stats_changed")
	else:
		_pass("GameData direct infra writes call notify_hub_stats_changed")
	var rel_src := _read("res://scripts/national/RelationsManager.gd")
	var set_pol := _slice_func(rel_src, "set_policy")
	if "relations_changed.emit" not in set_pol:
		_fail("set_policy does not emit relations_changed (GER→SWI cache stale)")
	else:
		_pass("set_policy emits relations_changed")


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
	if sm.has_method("end_day_roll_plan_deferral"):
		sm.call("end_day_roll_plan_deferral")
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
	else:
		_pass("worst day_ai %.1fms < %.0f (behaviour, not a 200ms wall)" % [worst_ai, DAY_BUDGET_MS])
	var sm_live: Node = root.get_node_or_null("/root/SupplyManager")
	if sm_live != null and "last_supply_day_profile" in sm_live:
		var prof: Dictionary = sm_live.get("last_supply_day_profile")
		var gen_ms: float = float(prof.get("generate_ms", 0.0))
		var refill_ms: float = float(prof.get("refill_ms", prof.get("flush_ms", 0.0)))
		var total_ms: float = float(prof.get("total_ms", 0.0))
		var other_ms: float = maxf(0.0, total_ms - gen_ms - refill_ms)
		print(
			"HeadlessPerf4LiveMultiAiDayTest: day_frame_breakdown ai=%.1f generate=%.1f refill=%.1f other=%.1f supply_total=%.1f"
			% [worst_ai, gen_ms, refill_ms, other_ms, total_ms]
		)


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
	var plans0: int = int(sm.get("network_route_refill_count")) if "network_route_refill_count" in sm else 0
	var missing0: int = _missing_dests(sm)
	var t_ten := Time.get_ticks_usec()
	for pid in ten:
		mm.call("update_province_owner", pid, "FRA", "FRA")
	var ten_ms := float(Time.get_ticks_usec() - t_ten) / 1000.0
	var plans1: int = int(sm.get("network_route_refill_count")) if "network_route_refill_count" in sm else 0
	var missing1: int = _missing_dests(sm)
	var queued: int = _queue_n(sm)
	var dirty: int = _dirty_n(sm)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: capture_frame_ten n=%d %.1fms (informational) missing=%d→%d queue=%d dirty=%d plans=%d→%d pids=%s"
		% [ten.size(), ten_ms, missing0, missing1, queued, dirty, plans0, plans1, str(ten)]
	)
	var tagged := 0
	for pid2 in ten:
		if _hub_owner_tag(sm, pid2) == "FRA":
			tagged += 1
	if tagged != ten.size():
		_fail("ten-capture retagged %d/%d hubs" % [tagged, ten.size()])
	elif plans1 != plans0:
		_fail("ten-capture planned on the capture frame plans=%d→%d" % [plans0, plans1])
	elif missing1 <= 0 and queued <= 0:
		_fail("ten-capture enqueued nothing missing=%d queue=%d" % [missing1, queued])
	elif dirty != 0:
		_fail("ten-capture left dirty set n=%d" % dirty)
	else:
		_pass("ten-capture enqueue-once behaviour missing=%d queue=%d plans+=0 dirty=0 (%.1fms informational)" % [missing1, queued, ten_ms])
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
	print("HeadlessPerf4LiveMultiAiDayTest: ten_capture_live_day_frame=%.1fms (behaviour, not a 200ms wall)" % day_ms)
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


func _missing_dests(sm: Node) -> int:
	if sm != null and sm.has_method("count_missing_default_dests"):
		return int(sm.call("count_missing_default_dests"))
	return -1


func _queue_n(sm: Node) -> int:
	if sm != null and sm.has_method("count_refill_queue"):
		return int(sm.call("count_refill_queue"))
	return -1


func _dirty_n(sm: Node) -> int:
	if sm != null and sm.has_method("count_control_dirty"):
		return int(sm.call("count_control_dirty"))
	if sm != null and "get_network_topology_snapshot" in sm:
		var snap: Dictionary = sm.call("get_network_topology_snapshot")
		return int(snap.get("dirty_n", -1))
	return -1


func _redrop_n(sm: Node) -> int:
	if sm != null and "network_route_redrop_count" in sm:
		return int(sm.get("network_route_redrop_count"))
	return -1


func _flush_until_drained(sm: Node, max_frames: int) -> Dictionary:
	if sm != null and sm.has_method("end_day_roll_plan_deferral"):
		sm.call("end_day_roll_plan_deferral")
	var frames: int = 0
	var plans_total: int = 0
	var plans_max: int = 0
	var redrops: int = 0
	while frames < max_frames:
		if _queue_n(sm) <= 0 and _missing_dests(sm) <= 0:
			break
		var got: int = int(sm.call("flush_pending_control_route_refresh"))
		var one: int = int(sm.get("last_flush_plan_count")) if "last_flush_plan_count" in sm else got
		plans_total += maxi(got, 0)
		if one > plans_max:
			plans_max = one
		if "last_flush_redrop_count" in sm:
			redrops += int(sm.get("last_flush_redrop_count"))
		frames += 1
		if got <= 0 and _queue_n(sm) <= 0:
			break
	return {
		"frames": frames,
		"plans_total": plans_total,
		"plans_max": plans_max,
		"redrops": redrops,
		"missing": _missing_dests(sm),
		"queue": _queue_n(sm),
		"dirty": _dirty_n(sm),
	}


func _assert_converged(sm: Node, label: String, drain: Dictionary) -> void:
	print(
		"HeadlessPerf4LiveMultiAiDayTest: %s frames=%d plans=%d max_plans=%d redrops=%d missing=%d queue=%d dirty=%d"
		% [
			label,
			int(drain.get("frames", -1)),
			int(drain.get("plans_total", -1)),
			int(drain.get("plans_max", -1)),
			int(drain.get("redrops", -1)),
			int(drain.get("missing", -1)),
			int(drain.get("queue", -1)),
			int(drain.get("dirty", -1)),
		]
	)
	if int(drain.get("missing", -1)) != 0:
		_fail("%s still missing dests n=%d (FIX #4 livelock class)" % [label, int(drain.get("missing", -1))])
	elif int(drain.get("dirty", -1)) != 0:
		_fail("%s dirty set did not drain n=%d" % [label, int(drain.get("dirty", -1))])
	elif int(drain.get("queue", -1)) != 0:
		_fail("%s refill queue did not drain n=%d" % [label, int(drain.get("queue", -1))])
	elif int(drain.get("redrops", -1)) != 0:
		_fail("%s re-dropped routes n=%d (re-drop restored)" % [label, int(drain.get("redrops", -1))])
	elif int(drain.get("plans_total", 0)) > 48:
		_fail("%s planned %d times (livelock re-planning the same dests)" % [label, int(drain.get("plans_total", 0))])
	else:
		_pass("%s converged missing=0 dirty=0 queue=0 redrops=0" % label)


func _test_depot_add_710314_converges(sm: Node) -> void:
	if sm == null or not sm.has_method("set_player_depot"):
		_fail("depot add 710314 helpers missing")
		return
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", DEPOT_ADD_PID, false)
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	var missing0: int = _missing_dests(sm)
	sm.call("set_player_depot", DEPOT_ADD_PID, true)
	if _dirty_n(sm) != 0:
		_fail("depot add 710314 left dirty set n=%d (pid must leave dirty immediately)" % _dirty_n(sm))
	else:
		_pass("depot add 710314 cleared dirty immediately")
	var drain: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
	_assert_converged(sm, "depot_add_710314", drain)
	if missing0 < 0:
		_fail("depot add 710314 missing helper missing")
	sm.call("set_player_depot", DEPOT_ADD_PID, false)
	var rm: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
	_assert_converged(sm, "depot_remove_710314", rm)


func _test_recapture_ger_converges(mm: Node, sm: Node) -> void:
	if mm == null or sm == null:
		_fail("recapture helpers missing")
		return
	_restore_owner(mm, CAPTURE_HUB_PID, "GER")
	_restore_owner(mm, CAPTURE_DEPOT_PID, "GER")
	if not _boot_live_supply_network(mm, sm):
		_fail("recapture boot failed")
		return
	if _hub_owner_tag(sm, CAPTURE_HUB_PID) != "GER":
		_fail("recapture needs GER hub %d" % CAPTURE_HUB_PID)
		return
	mm.call("update_province_owner", CAPTURE_HUB_PID, "FRA", "FRA")
	_flush_until_drained(sm, CONVERGE_FRAMES)
	mm.call("update_province_owner", CAPTURE_HUB_PID, "GER", "GER")
	if _dirty_n(sm) != 0:
		_fail("recapture left dirty set n=%d" % _dirty_n(sm))
	var drain: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
	_assert_converged(sm, "recapture_ger", drain)


func _test_multi_round_capture_round3_converges(mm: Node, sm: Node) -> void:
	if mm == null or sm == null:
		_fail("multi-round capture helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("multi-round capture boot failed")
		return
	var batch: Array[int] = _collect_ger_hub_pids(sm, 3, [])
	if batch.size() < 3:
		_fail("multi-round capture needs 3 GER hubs got=%d" % batch.size())
		return
	for round_i in range(1, 4):
		for pid in batch:
			mm.call("update_province_owner", pid, "FRA", "FRA")
		var cap: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
		_assert_converged(sm, "multi_round_capture_r%d" % round_i, cap)
		for pid2 in batch:
			mm.call("update_province_owner", pid2, "GER", "GER")
		var rec: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
		_assert_converged(sm, "multi_round_restore_r%d" % round_i, rec)
	if _missing_dests(sm) != 0:
		_fail("multi-round capture round 3 ended missing=%d" % _missing_dests(sm))
	else:
		_pass("multi-round capture round 3 ended missing=0")


func _test_annex_and_depot_remove_zero_missing(gd: Node, mm: Node, sm: Node) -> void:
	if gd == null or mm == null or sm == null:
		_fail("annex/depot-remove converge helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("annex/depot-remove boot failed")
		return
	var pids: Array[int] = _collect_ger_hub_pids(sm, 1, [CAPTURE_HUB_PID, CAPTURE_DEPOT_PID, int(CAPITALS.get("GER", 0))])
	if pids.is_empty():
		_fail("annex converge needs a GER hub")
		return
	var pid: int = pids[0]
	gd.call("apply_peace_conference_settlement_live", "FRA", "GER", pid, true, false, 0.0, false)
	var annex: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
	_assert_converged(sm, "annex_zero_missing", annex)
	_restore_owner(mm, pid, "GER")
	_flush_until_drained(sm, CONVERGE_FRAMES)
	sm.call("set_player_depot", DEPOT_ADD_PID, true)
	_flush_until_drained(sm, CONVERGE_FRAMES)
	sm.call("set_player_depot", DEPOT_ADD_PID, false)
	var rm: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
	_assert_converged(sm, "depot_remove_zero_missing", rm)


func _test_keep_old_routes_until_swap(sm: Node) -> void:
	if sm == null or not sm.has_method("get_network_topology_snapshot"):
		_fail("old-route keep helpers missing")
		return
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	var before: Dictionary = sm.call("get_network_topology_snapshot")
	var routes0: int = int(before.get("route_n", 0))
	var missing0: int = _missing_dests(sm)
	sm.call("set_player_depot", DEPOT_ADD_PID, true)
	var missing1: int = _missing_dests(sm)
	var after: Dictionary = sm.call("get_network_topology_snapshot")
	var routes1: int = int(after.get("route_n", 0))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: keep_old_routes before_n=%d after_n=%d missing=%d→%d"
		% [routes0, routes1, missing0, missing1]
	)
	# No-keep mutant drops friendly-touching routes on the depot add.
	if missing1 > 1:
		_fail("no old-route keep: depot add dropped dests missing=%d (want ≤1 new dest)" % missing1)
	elif routes1 + 1 < routes0:
		_fail("no old-route keep: routes %d→%d after friendly depot add" % [routes0, routes1])
	else:
		_pass("old routes kept serving after depot add missing=%d" % missing1)
	_flush_until_drained(sm, CONVERGE_FRAMES)
	sm.call("set_player_depot", DEPOT_ADD_PID, false)
	_flush_until_drained(sm, CONVERGE_FRAMES)


func _test_ten_capture_drains_one_day_1x_and_4x(mm: Node, sm: Node) -> void:
	if mm == null or sm == null:
		_fail("1x/4x drain helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("1x/4x drain boot failed")
		return
	var ten: Array[int] = _collect_ger_hub_pids(sm, 10, [])
	if ten.size() < 10:
		_fail("1x/4x drain needs 10 GER hubs got=%d" % ten.size())
		return
	for pid in ten:
		mm.call("update_province_owner", pid, "FRA", "FRA")
	var d1: Dictionary = _flush_until_drained(sm, FRAMES_PER_DAY_1X)
	_assert_converged(sm, "ten_capture_1x_day", d1)
	for pid_r in ten:
		_restore_owner(mm, pid_r, "GER")
	if not _boot_live_supply_network(mm, sm):
		_fail("4x drain boot failed")
		return
	for pid2 in ten:
		mm.call("update_province_owner", pid2, "FRA", "FRA")
	var d4: Dictionary = _flush_until_drained(sm, FRAMES_PER_DAY_4X)
	_assert_converged(sm, "ten_capture_4x_day", d4)
	for pid3 in ten:
		_restore_owner(mm, pid3, "GER")
	_boot_live_supply_network(mm, sm)


func _test_slice_caps_plans_per_frame(sm: Node) -> void:
	if sm == null or not sm.has_method("enqueue_player_dests_for_refresh"):
		_fail("slice plan-cap helpers missing")
		return
	var queued: int = int(sm.call("enqueue_player_dests_for_refresh"))
	var qn: int = _queue_n(sm)
	sm.call("flush_pending_control_route_refresh")
	var planned: int = int(sm.get("last_flush_plan_count")) if "last_flush_plan_count" in sm else -1
	print(
		"HeadlessPerf4LiveMultiAiDayTest: slice_plan_cap queued=%d queue=%d planned=%d"
		% [queued, qn, planned]
	)
	if qn < 8:
		_fail("slice plan-cap could not enqueue dests queue=%d" % qn)
	elif planned <= 0:
		_fail("slice plan-cap planned 0 (flush did not pop the queue)")
	elif planned >= qn and qn >= 8:
		_fail("slice removed: one flush planned all %d dests" % planned)
	elif planned > MAX_PLANS_PER_FLUSH_SLICE:
		_fail("slice plan-cap planned %d > %d" % [planned, MAX_PLANS_PER_FLUSH_SLICE])
	else:
		_pass("slice capped plans/frame=%d queue_left=%d" % [planned, _queue_n(sm)])
	_flush_until_drained(sm, CONVERGE_FRAMES)


func _test_relations_access_clears_friendly_cache(sm: Node) -> void:
	var rm: Node = root.get_node_or_null("/root/RelationsManager")
	if rm == null or sm == null:
		_fail("relations cache helpers missing")
		return
	if not sm.has_method("is_player_friendly_province"):
		_fail("is_player_friendly_province missing")
		return
	var before: bool = bool(sm.call("is_player_friendly_province", SWI_PID))
	if sm.has_method("clear_refill_queue"):
		sm.call("clear_refill_queue")
	if rm.has_method("set_policy"):
		rm.call("set_policy", "JAP", "CHI", {"military_access": true})
	var foreign_q: int = _queue_n(sm)
	if foreign_q > 0:
		_fail("JAP–CHI access enqueued GER dests n=%d (player not a party)" % foreign_q)
	else:
		_pass("JAP–CHI access did not enqueue GER dests")
	if rm.has_method("set_policy"):
		rm.call("set_policy", PLAYER_TAG, "SWI", {"military_access": true})
	var after: bool = bool(sm.call("is_player_friendly_province", SWI_PID))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: ger_swi_access before=%s after=%s"
		% [str(before), str(after)]
	)
	if before:
		_fail("GER→SWI already friendly before access (cache test unarmed)")
	elif not after:
		_fail("GER→SWI still blocked after military_access (friendly cache stale)")
	else:
		_pass("GER→SWI became friendly after access (cache cleared)")
	if rm.has_method("set_policy"):
		rm.call("set_policy", PLAYER_TAG, "SWI", {"military_access": false})
		rm.call("set_policy", "JAP", "CHI", {"military_access": false})


func _live_vs_rebuild_pathdiff(mm: Node, sm: Node) -> Dictionary:
	var live: Dictionary = sm.call("get_network_topology_snapshot")
	if not _boot_live_supply_network(mm, sm):
		return {"ok": false, "pathdiff": -1, "live_n": 0, "full_n": 0}
	var full: Dictionary = sm.call("get_network_topology_snapshot")
	var live_routes: Array = live.get("routes", []) as Array
	var full_routes: Array = full.get("routes", []) as Array
	return {
		"ok": true,
		"pathdiff": _path_mismatch_count(live_routes, full_routes),
		"live_n": live_routes.size(),
		"full_n": full_routes.size(),
		"identical": _route_paths_identical(live_routes, full_routes),
	}


func _hub_capdiff(live_caps: Dictionary, full_caps: Dictionary) -> Array:
	var diffs: Array = []
	var keys: Dictionary = {}
	for k in live_caps.keys():
		keys[int(k)] = true
	for k2 in full_caps.keys():
		keys[int(k2)] = true
	for pid_v in keys.keys():
		var pid: int = int(pid_v)
		var live_c: float = float(live_caps.get(pid, live_caps.get(str(pid), 0.0)))
		var full_c: float = float(full_caps.get(pid, full_caps.get(str(pid), 0.0)))
		if not is_equal_approx(live_c, full_c):
			diffs.append({"pid": pid, "live": live_c, "full": full_c})
	return diffs


func _test_recapture_710314_path_identity(mm: Node, sm: Node) -> void:
	if mm == null or sm == null or not sm.has_method("get_network_topology_snapshot"):
		_fail("recapture 710314 path identity helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("recapture 710314 boot failed")
		return
	var pid: int = RECAPTURE_PATH_PID
	mm.call("update_province_owner", pid, "FRA", "FRA")
	_flush_until_drained(sm, CONVERGE_FRAMES)
	mm.call("update_province_owner", pid, "GER", "GER")
	var drain: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
	_assert_converged(sm, "ll_recap_710314", drain)
	var cmp: Dictionary = _live_vs_rebuild_pathdiff(mm, sm)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: recapture_710314 pathdiff=%s live_n=%s full_n=%s"
		% [str(cmp.get("pathdiff", -1)), str(cmp.get("live_n", -1)), str(cmp.get("full_n", -1))]
	)
	if not bool(cmp.get("ok", false)):
		_fail("recapture 710314 rebuild failed")
	elif int(cmp.get("pathdiff", -1)) != 0:
		_fail("recapture 710314 pathdiff=%d (enqueue-touching-only keeps detour)" % int(cmp.get("pathdiff", -1)))
	else:
		_pass("recapture 710314 paths match full rebuild pathdiff=0")
	_restore_owner(mm, pid, "GER")
	_boot_live_supply_network(mm, sm)


func _test_military_access_path_identity(mm: Node, sm: Node) -> void:
	var rm: Node = root.get_node_or_null("/root/RelationsManager")
	if rm == null or sm == null or not rm.has_method("set_policy"):
		_fail("military access path identity helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("military access path identity boot failed")
		return
	rm.call("set_policy", PLAYER_TAG, "SWI", {"military_access": true})
	var grant_q: int = _queue_n(sm)
	var grant_drain: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
	_assert_converged(sm, "access_grant", grant_drain)
	var grant: Dictionary = _live_vs_rebuild_pathdiff(mm, sm)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: access_grant queue=%d pathdiff=%s"
		% [grant_q, str(grant.get("pathdiff", -1))]
	)
	if grant_q <= 0:
		_fail("military access grant enqueued nothing (relations clear cache only)")
	elif int(grant.get("pathdiff", -1)) != 0:
		_fail("military access grant pathdiff=%d" % int(grant.get("pathdiff", -1)))
	else:
		_pass("military access grant paths match rebuild pathdiff=0")
	if not _boot_live_supply_network(mm, sm):
		_fail("military access revoke boot failed")
		rm.call("set_policy", PLAYER_TAG, "SWI", {"military_access": false})
		return
	rm.call("set_policy", PLAYER_TAG, "SWI", {"military_access": false})
	var rev_q: int = _queue_n(sm)
	var rev_drain: Dictionary = _flush_until_drained(sm, CONVERGE_FRAMES)
	_assert_converged(sm, "access_revoked", rev_drain)
	var rev: Dictionary = _live_vs_rebuild_pathdiff(mm, sm)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: access_revoked queue=%d pathdiff=%s"
		% [rev_q, str(rev.get("pathdiff", -1))]
	)
	if rev_q <= 0:
		_fail("military access revoke enqueued nothing")
	elif int(rev.get("pathdiff", -1)) != 0:
		_fail("military access revoke pathdiff=%d" % int(rev.get("pathdiff", -1)))
	else:
		_pass("military access revoke paths match rebuild pathdiff=0")
	_boot_live_supply_network(mm, sm)


func _test_fifo_dequeue_matches_enqueue(sm: Node) -> void:
	if sm == null or not sm.has_method("enqueue_refill_dests") or not sm.has_method("peek_refill_queue"):
		_fail("FIFO enqueue/dequeue helpers missing")
		return
	if sm.has_method("clear_refill_queue"):
		sm.call("clear_refill_queue")
	var snap: Dictionary = sm.call("get_network_topology_snapshot") if sm.has_method("get_network_topology_snapshot") else {}
	var dests: Array[int] = []
	for raw in snap.get("routes", []) as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var dst: int = int((raw as Dictionary).get("dst", -1))
		if dst > 0 and dst not in dests:
			dests.append(dst)
	dests.sort()
	if dests.size() < 4:
		_fail("FIFO test needs 4 default dests got=%d" % dests.size())
		return
	# Two capture-like batches. Order is not sorted (high ids first).
	var batch1: Array = [dests[dests.size() - 1], dests[dests.size() - 2]]
	var batch2: Array = [dests[0], dests[1]]
	var want: Array[int] = [int(batch1[0]), int(batch1[1]), int(batch2[0]), int(batch2[1])]
	sm.call("enqueue_refill_dests", batch1)
	sm.call("enqueue_refill_dests", batch2)
	var queued: Array = sm.call("peek_refill_queue")
	var got: Array[int] = []
	for _i in range(want.size()):
		sm.call("flush_pending_control_route_refresh", 1)
		var planned: Array = sm.get("last_flush_planned_dests") if "last_flush_planned_dests" in sm else []
		for d_v in planned:
			got.append(int(d_v))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: fifo_order want=%s queued=%s got=%s"
		% [str(want), str(queued), str(got)]
	)
	if str(queued) != str(want):
		_fail("FIFO enqueue order %s != %s (sorted/LIFO mutant)" % [str(queued), str(want)])
	elif str(got) != str(want):
		_fail("FIFO dequeue order %s != enqueue %s (sorted/LIFO mutant)" % [str(got), str(want)])
	else:
		_pass("FIFO dequeue == enqueue across two batches %s" % str(got))
	_flush_until_drained(sm, CONVERGE_FRAMES)


func _test_slice_predictive_vs_reactive_seam(sm: Node) -> void:
	if sm == null or not sm.has_method("enqueue_player_dests_for_refresh"):
		_fail("slice estimate-seam helpers missing")
		return
	if not ("route_refresh_plan_cost_estimate_ms" in sm):
		_fail("route_refresh_plan_cost_estimate_ms seam missing")
		return
	if sm.has_method("clear_refill_queue"):
		sm.call("clear_refill_queue")
	sm.set("route_refresh_plan_cost_estimate_ms", SLICE_ESTIMATE_MS)
	sm.set("last_plan_ms", SLICE_ESTIMATE_MS)
	var queued: int = int(sm.call("enqueue_player_dests_for_refresh"))
	sm.call("flush_pending_control_route_refresh")
	var planned: int = int(sm.get("last_flush_plan_count")) if "last_flush_plan_count" in sm else -1
	print(
		"HeadlessPerf4LiveMultiAiDayTest: slice_reactive_seam estimate=%.0f queued=%d planned=%d"
		% [SLICE_ESTIMATE_MS, queued, planned]
	)
	sm.set("route_refresh_plan_cost_estimate_ms", -1.0)
	if queued < 4:
		_fail("slice seam could not enqueue dests queued=%d" % queued)
	elif planned != 1:
		_fail("slice_reactive survived: estimate %.0f planned %d (want predictive 1, reactive 2)" % [SLICE_ESTIMATE_MS, planned])
	else:
		_pass("predictive slice plans 1/frame at %.0fms estimate (reactive would plan 2)" % SLICE_ESTIMATE_MS)
	_flush_until_drained(sm, CONVERGE_FRAMES)


func _test_gamedata_direct_infra_notifies_hub_stats(gd: Node, mm: Node, sm: Node) -> void:
	if gd == null or mm == null or sm == null:
		_fail("GameData infra notify helpers missing")
		return
	if not gd.has_method("apply_ascendancy_initiative_player_province_choice"):
		_fail("apply_ascendancy_initiative_player_province_choice missing")
		return
	var ger_cap: int = int(CAPITALS.get("GER", 0))
	var p: Variant = mm.call("get_province", ger_cap)
	if p == null:
		_fail("GameData infra notify needs GER capital")
		return
	var hubs: Dictionary = sm.hubs if "hubs" in sm else {}
	if not hubs.has(ger_cap):
		_fail("GER capital is not a hub")
		return
	var cap0: float = float(hubs[ger_cap].storage_capacity)
	var stats0: int = int(sm.get("network_hub_stats_refresh_count"))
	var infra0: int = int(p.infrastructure)
	# Real settlement-improve path. Coastal feature makes the function write infra.
	if "special_features" in p and p.special_features is Dictionary:
		(p.special_features as Dictionary)["coastal"] = 1
	gd.call("apply_ascendancy_initiative_player_province_choice", PLAYER_TAG, "perf4", "improve_capital", ger_cap)
	if int(p.infrastructure) <= infra0 and gd.has_method("apply_encourage_relocation"):
		gd.call("apply_encourage_relocation", PLAYER_TAG, "perf4_cap", 0.4)
	var live1: Dictionary = sm.call("get_hub_capacity_snapshot") if sm.has_method("get_hub_capacity_snapshot") else {}
	var cap1: float = float((sm.hubs as Dictionary)[ger_cap].storage_capacity)
	var stats1: int = int(sm.get("network_hub_stats_refresh_count"))
	if not _boot_live_supply_network(mm, sm):
		_fail("GameData infra rebuild failed")
		return
	var full: Dictionary = sm.call("get_hub_capacity_snapshot") if sm.has_method("get_hub_capacity_snapshot") else {}
	var capdiff: Array = _hub_capdiff(live1, full)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: gamedata_infra_choice pid=%d infra=%d→%d cap=%.0f→%.0f stats=%d→%d capdiff=%s"
		% [ger_cap, infra0, int(p.infrastructure), cap0, cap1, stats0, stats1, str(capdiff)]
	)
	if stats1 <= stats0:
		_fail("GameData settlement-improve did not notify hub stats")
	elif cap1 <= cap0:
		_fail("GameData settlement-improve left hub capacity %.0f" % cap1)
	elif not capdiff.is_empty():
		_fail("GameData settlement-improve capdiff=%s (infra_no_notify)" % str(capdiff))
	else:
		_pass("GameData settlement-improve hub capacity == rebuild capdiff=[]")


func _test_dayroll_with_capture_under_200ms(tm: Node, mm: Node, sm: Node) -> void:
	if tm == null or mm == null or sm == null:
		_fail("dayroll+capture helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("dayroll+capture boot failed")
		return
	_restore_owner(mm, CAPTURE_HUB_PID, "GER")
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	_reset_clock(tm, 0)
	var t0: int = Time.get_ticks_usec()
	mm.call("update_province_owner", CAPTURE_HUB_PID, "FRA", "FRA")
	if tm.has_method("advance_live_f5_equivalent_days"):
		tm.call("advance_live_f5_equivalent_days", 1)
	elif sm.has_method("advance_supply_day"):
		sm.call("advance_supply_day", 1.0)
	var frame_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var prof: Dictionary = sm.get("last_supply_day_profile") if "last_supply_day_profile" in sm else {}
	var sim_ms: float = float(prof.get("total_ms", 0.0))
	print(
		"HeadlessPerf4LiveMultiAiDayTest: dayroll_capture_frame=%.1fms sim_supply=%.1fms generate=%.1f flush=%.1f (sim vs render: this is headless sim, not a live xvfb day-frame)"
		% [frame_ms, sim_ms, float(prof.get("generate_ms", 0.0)), float(prof.get("flush_ms", 0.0))]
	)
	if frame_ms >= DAYROLL_CAPTURE_BUDGET_MS:
		_fail("dayroll+capture frame %.1fms >= %.0f" % [frame_ms, DAYROLL_CAPTURE_BUDGET_MS])
	else:
		_pass("dayroll+capture frame %.1fms < %.0f (headless sim; live needs sim-vs-render split)" % [frame_ms, DAYROLL_CAPTURE_BUDGET_MS])
	_restore_owner(mm, CAPTURE_HUB_PID, "GER")
	_boot_live_supply_network(mm, sm)


func _emit_day_without_multi_ai(tm: Node) -> void:
	if tm != null and tm.has_method("_emit_game_day_advanced_profiled"):
		tm.call(
			"_emit_game_day_advanced_profiled",
			int(tm.get("current_year")) if "current_year" in tm else 1936,
			int(tm.get("current_month")) if "current_month" in tm else 1,
			int(tm.get("current_day")) if "current_day" in tm else 1
		)


func _dests_touching_pid(sm: Node, pid: int) -> Array[int]:
	var out: Array[int] = []
	if sm == null or not sm.has_method("get_network_topology_snapshot"):
		return out
	var snap: Dictionary = sm.call("get_network_topology_snapshot")
	var seen: Dictionary = {}
	for raw in snap.get("routes", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var dst: int = int(row.get("dst", 0))
		var hit := dst == pid or int(row.get("src", 0)) == pid
		if not hit:
			for step_v in row.get("path", []):
				if int(step_v) == pid:
					hit = true
					break
		if hit and dst > 0 and not seen.has(dst):
			seen[dst] = true
			out.append(dst)
	return out


func _test_redrop_counter_increments_on_hostile_drop(mm: Node, sm: Node) -> void:
	if mm == null or sm == null or not sm.has_method("get_network_topology_snapshot"):
		_fail("redrop behaviour helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("redrop behaviour boot failed")
		return
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	var n0: int = _redrop_n(sm)
	var victim: int = 0
	var snap: Dictionary = sm.call("get_network_topology_snapshot")
	var capital: int = int(CAPITALS.get("GER", 0))
	for raw in snap.get("routes", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		for step_v in row.get("path", []):
			var step: int = int(step_v)
			if step <= 0 or step == capital or step == int(row.get("dst", 0)):
				continue
			if sm.has_method("is_player_friendly_province") and not bool(sm.call("is_player_friendly_province", step)):
				continue
			victim = step
			break
		if victim > 0:
			break
	if victim <= 0:
		_fail("redrop behaviour found no friendly mid-path pid")
		return
	mm.call("update_province_owner", victim, "FRA", "FRA")
	var n1: int = _redrop_n(sm)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: redrop_behaviour pid=%d count=%d→%d"
		% [victim, n0, n1]
	)
	if n1 <= n0:
		_fail("redrop counter dead n=%d→%d (hostile drop of a planned route)" % [n0, n1])
	else:
		_pass("redrop counter incremented %d→%d on hostile drop of pid %d" % [n0, n1, victim])
	_restore_owner(mm, victim, "GER")
	_boot_live_supply_network(mm, sm)


func _test_depot_add_replans_only_touched_dests(sm: Node) -> void:
	if sm == null or not sm.has_method("set_player_depot") or not sm.has_method("peek_refill_queue"):
		_fail("depot subset helpers missing")
		return
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", DEPOT_ADD_PID, false)
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	if sm.has_method("clear_refill_queue"):
		sm.call("clear_refill_queue")
	var touching: Array[int] = _dests_touching_pid(sm, DEPOT_ADD_PID)
	var pid: int = DEPOT_ADD_PID
	if touching.size() <= 0 or touching.size() >= DEFAULT_ROUTE_DEST_CAP_HINT:
		var snap: Dictionary = sm.call("get_network_topology_snapshot") if sm.has_method("get_network_topology_snapshot") else {}
		for raw in snap.get("routes", []):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var dest: int = int((raw as Dictionary).get("dst", 0))
			if dest <= 0:
				continue
			var alt: Array[int] = _dests_touching_pid(sm, dest)
			if alt.size() > 0 and alt.size() < DEFAULT_ROUTE_DEST_CAP_HINT:
				pid = dest
				touching = alt
				break
	if touching.size() <= 0 or touching.size() >= DEFAULT_ROUTE_DEST_CAP_HINT:
		_fail("depot subset could not find a pid that touches fewer than 24 dests")
		return
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", pid, false)
		sm.call("set_player_depot", pid, true)
	var queued: Array = sm.call("peek_refill_queue") if sm.has_method("peek_refill_queue") else []
	var qn: int = queued.size()
	print(
		"HeadlessPerf4LiveMultiAiDayTest: depot_subset pid=%d touching=%d queued=%d queued_dests=%s"
		% [pid, touching.size(), qn, str(queued)]
	)
	if qn <= 0:
		_fail("depot add that touches dests enqueued nothing")
	elif qn >= 24:
		_fail("depot add re-planned all %d dests (want only the %d it touches)" % [qn, touching.size()])
	else:
		var extra: Array[int] = []
		for dest_v in queued:
			var dest: int = int(dest_v)
			if dest not in touching:
				extra.append(dest)
		if not extra.is_empty() and extra.size() > 1:
			_fail("depot add queued dests that do not touch pid extra=%s" % str(extra))
		else:
			_pass("depot add re-plans only touched dests queued=%d touching=%d" % [qn, touching.size()])
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", pid, false)
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")


func _assert_dayroll_event_own_share(label: String, tm: Node, sm: Node, event_cb: Callable) -> void:
	if sm.has_method("clear_refill_queue"):
		sm.call("clear_refill_queue")
	if sm.has_method("end_day_roll_plan_deferral"):
		sm.call("end_day_roll_plan_deferral")
	var refill0: int = int(sm.get("network_route_refill_count")) if "network_route_refill_count" in sm else 0
	var t0: int = Time.get_ticks_usec()
	_emit_day_without_multi_ai(tm)
	event_cb.call()
	var planned_emit: int = int(sm.get("last_flush_plan_count")) if "last_flush_plan_count" in sm else -1
	var flush_got: int = int(sm.call("flush_pending_control_route_refresh")) if sm.has_method("flush_pending_control_route_refresh") else -1
	var planned_flush: int = int(sm.get("last_flush_plan_count")) if "last_flush_plan_count" in sm else -1
	var share_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var refill1: int = int(sm.get("network_route_refill_count")) if "network_route_refill_count" in sm else refill0
	print(
		"HeadlessPerf4LiveMultiAiDayTest: dayroll_%s own_share=%.1fms plans_emit=%d plans_flush=%d refill=%d→%d (emit+event+plans, no multi_ai)"
		% [label, share_ms, planned_emit, planned_flush, refill0, refill1]
	)
	if planned_emit != 0 or flush_got != 0 or planned_flush != 0 or refill1 != refill0:
		_fail(
			"dayroll+%s planned on the roll frame emit=%d flush=%d refill=%d→%d"
			% [label, planned_emit, planned_flush, refill0, refill1]
		)
	elif share_ms >= DAYROLL_OWN_SHARE_BUDGET_MS:
		_fail("dayroll+%s own share %.1fms >= %.0f (emit+event+plans, no multi_ai)" % [label, share_ms, DAYROLL_OWN_SHARE_BUDGET_MS])
	else:
		_pass("dayroll+%s own share %.1fms < %.0f plans=0" % [label, share_ms, DAYROLL_OWN_SHARE_BUDGET_MS])
	if sm.has_method("end_day_roll_plan_deferral"):
		sm.call("end_day_roll_plan_deferral")
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")


func _test_dayroll_event_own_share_under_300ms(tm: Node, mm: Node, gd: Node, sm: Node) -> void:
	if tm == null or mm == null or sm == null:
		_fail("dayroll own-share helpers missing")
		return
	if not _boot_live_supply_network(mm, sm):
		_fail("dayroll own-share boot failed")
		return
	_reset_clock(tm, 0)
	var rm: Node = root.get_node_or_null("/root/RelationsManager")
	_assert_dayroll_event_own_share("access", tm, sm, func() -> void:
		if rm != null and rm.has_method("set_policy"):
			rm.call("set_policy", PLAYER_TAG, "SWI", {"military_access": true})
	)
	if rm != null and rm.has_method("set_policy"):
		rm.call("set_policy", PLAYER_TAG, "SWI", {"military_access": false})
	_restore_owner(mm, RECAPTURE_PATH_PID, "FRA")
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	_assert_dayroll_event_own_share("recapture", tm, sm, func() -> void:
		mm.call("update_province_owner", RECAPTURE_PATH_PID, "GER", "GER")
	)
	_restore_owner(mm, RECAPTURE_PATH_PID, "GER")
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", DEPOT_ADD_PID, false)
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	_assert_dayroll_event_own_share("depot_add", tm, sm, func() -> void:
		sm.call("set_player_depot", DEPOT_ADD_PID, true)
	)
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", DEPOT_ADD_PID, false)
	var annex_pids: Array[int] = _collect_ger_hub_pids(sm, 1, [CAPTURE_HUB_PID, CAPTURE_DEPOT_PID, int(CAPITALS.get("GER", 0))])
	var annex_pid: int = annex_pids[0] if not annex_pids.is_empty() else CAPTURE_HUB_PID
	_restore_owner(mm, annex_pid, "GER")
	if sm.has_method("drain_pending_route_refresh"):
		sm.call("drain_pending_route_refresh")
	_assert_dayroll_event_own_share("annex", tm, sm, func() -> void:
		if gd != null and gd.has_method("apply_peace_conference_settlement_live"):
			gd.call("apply_peace_conference_settlement_live", "FRA", "GER", annex_pid, true, false, 0.0, false)
		else:
			mm.call("update_province_owner", annex_pid, "FRA", "FRA")
	)
	_restore_owner(mm, annex_pid, "GER")
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
	# Capture must drop these pids from the GER owner index.
	if mm.has_method("update_province_owner"):
		mm.call("update_province_owner", CAPTURE_HUB_PID, "FRA", "FRA")
		mm.call("update_province_owner", CAPTURE_DEPOT_PID, "FRA", "FRA")
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
