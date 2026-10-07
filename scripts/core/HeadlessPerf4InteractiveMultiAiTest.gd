extends SceneTree

## PERF-4 FIX #1: interactive multi-AI is the live Play 1x hitch.
## Drives `_maybe_run_interactive_multi_ai` / `apply_interactive_multi_ai_day_live`
## with the live nation set (GER player, majors AI) and a live-weight supply
## network. FAILS on main 61a80433 and on tip 289268ed (rebuild every day).
## PASSES when the soft tick does not rebuild the network and still runs the
## full advance_supply_day steps (air / naval / shipping).
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessPerf4InteractiveMultiAiTest.gd

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const DEPOT_SCRIPT := "res://scripts/supply/ProvinceDepotState.gd"
const SRC_GD := "res://scripts/autoload/GameData.gd"
const SRC_TM := "res://scripts/autoload/TimeManager.gd"
const SRC_PM := "res://scripts/autoload/ProductionManager.gd"
const SRC_SM := "res://scripts/supply/SupplyManager.gd"
const SRC_MM := "res://scripts/map/MapManager.gd"
const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const EQUIV_DAYS := 7
const EQUIV_SEED := 193601
const FRAME_BUDGET_MS := 500.0
const LIVE_MAJORS: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"]

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf4InteractiveMultiAiTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf4InteractiveMultiAiTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessPerf4InteractiveMultiAiTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf4InteractiveMultiAiTest: RESULT=", "PASS" if ok else "FAIL")
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
	_test_source_gates_fail_on_old_tips()
	var mm: Node = root.get_node_or_null("/root/MapManager")
	var tm: Node = root.get_node_or_null("/root/TimeManager")
	var gd: Node = root.get_node_or_null("/root/GameData")
	var sm: Node = root.get_node_or_null("/root/SupplyManager")
	var pm: Node = root.get_node_or_null("/root/ProductionManager")
	var idm: Node = root.get_node_or_null("/root/InfrastructureDevelopmentManager")
	var lm: Node = root.get_node_or_null("/root/LeaderManager")
	var sp: Node = root.get_node_or_null("/root/SessionPlayers")
	if mm == null or tm == null or gd == null:
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
	_boot_live_nation_set(lm, sp)
	if idm != null and idm.has_method("initialize_with_time"):
		idm.call("initialize_with_time")
	var hubs := _boot_live_supply_network(mm, sm)
	if hubs < 2000:
		_fail("live-weight supply hubs too few (%d) — need land-hex depots" % hubs)
	else:
		_pass("live-weight supply hubs=%d" % hubs)
	_seed_major_oob_lines(pm)
	_test_interactive_multi_ai_entry(tm, gd, sm)
	_test_production_cache_measured(pm)
	_test_ai_infra_outcome_equivalence(idm, mm)
	_test_live_day_path_includes_multi_ai(tm, idm)


func _test_source_gates_fail_on_old_tips() -> void:
	var gd_src := _read(SRC_GD)
	var supply_fn := _slice_func(gd_src, "apply_supply_route_mutation")
	if "advance_supply_day_interactive_light" in supply_fn:
		_fail("apply_supply still drops live Play onto the light path")
	elif "advance_supply_day" in supply_fn:
		_pass("apply_supply uses full advance_supply_day")
	else:
		_fail("apply_supply lost advance_supply_day")
	var live_fn := _slice_func(gd_src, "apply_interactive_multi_ai_day_live")
	if "country_profile" not in live_fn or "begin_interactive_multi_ai_day_cache" not in live_fn:
		_fail("apply_interactive_multi_ai_day_live missing per-country profile/cache (289268ed FAIL class)")
	else:
		_pass("per-country multi-AI profile + day cache")
	if "get_last_interactive_multi_ai_profile" not in gd_src:
		_fail("get_last_interactive_multi_ai_profile missing")
	var pm_src := _read(SRC_PM)
	if "func begin_interactive_multi_ai_day_cache" not in pm_src:
		_fail("ProductionManager missing per-day line-owner cache (289268ed FAIL class)")
	else:
		_pass("production day cache present")
	var adv_fn := _slice_func(pm_src, "advance_days_for_country")
	if "_interactive_ai_line_ids_by_owner" not in adv_fn:
		_fail("advance_days_for_country still walks all lines per AI country")
	else:
		_pass("advance_days_for_country uses owner line index")
	var sm_src := _read(SRC_SM)
	if "func advance_supply_day_interactive_light" not in sm_src:
		_fail("SupplyManager missing interactive light entry (289268ed FAIL class)")
	else:
		_pass("advance_supply_day_interactive_light present")
	var day_fn := _slice_func(sm_src, "_on_game_day_advanced")
	if "_advance_supply_day_light" not in day_fn or "is_interactive_light_sim" not in day_fn:
		_fail("daily listener lost main's light/full split")
	else:
		_pass("daily listener uses light path on interactive sim")
	var mm_src := _read(SRC_MM)
	var full_fn := _slice_func(mm_src, "get_fully_controlled_strategic_regions")
	if "_owned_or_controlled_pid_set" not in full_fn:
		_fail("regional control still walks ScenarioLoader provinces per AI country")
	else:
		_pass("regional control uses owner-index set")
	var bonus_fn := _slice_func(mm_src, "get_active_regional_control_bonuses")
	if "loader.provinces.has" in bonus_fn:
		_fail("get_active_regional_control_bonuses still re-walks loader provinces")
	else:
		_pass("regional bonus reuses fully-controlled helper")
	var tm_src := _read(SRC_TM)
	var prof := _slice_func(tm_src, "_profile_day_ai_steps")
	if "multi_ai_profile" not in prof:
		_fail("day_ai profile missing multi_ai country breakdown")
	else:
		_pass("day_ai records multi_ai_profile")


func _boot_live_nation_set(lm: Node, sp: Node) -> void:
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "GER")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	_pass("live nation set player=GER majors=AI")


func _boot_live_supply_network(mm: Node, sm: Node) -> int:
	if sm == null:
		return 0
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
	var hubs := 0
	if "hubs" in sm:
		hubs = int((sm.hubs as Dictionary).size())
	var depots := 0
	if "depot_states" in sm:
		depots = int((sm.depot_states as Dictionary).size())
	# Live Play generate walks every depot. If kinds-filter left holes, seed land depots.
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
	print(
		"HeadlessPerf4InteractiveMultiAiTest: supply land=%d hubs=%d depots=%d"
		% [land_n, hubs, depots]
	)
	return depots


func _seed_major_oob_lines(pm: Node) -> void:
	if pm == null or not pm.has_method("create_line"):
		return
	var n := 0
	for tag_v in LIVE_MAJORS:
		var tag := str(tag_v)
		if tag == "GER":
			continue
		for i in range(8):
			var lid := "oob_%s_infantry_%d" % [tag, i]
			pm.call("create_line", lid)
			n += 1
	_pass("seeded oob lines=%d" % n)


func _test_interactive_multi_ai_entry(tm: Node, gd: Node, sm: Node) -> void:
	if not gd.has_method("apply_interactive_multi_ai_day_live"):
		_fail("apply_interactive_multi_ai_day_live missing")
		return
	if not tm.has_method("_maybe_run_interactive_multi_ai"):
		_fail("_maybe_run_interactive_multi_ai missing")
		return
	tm.set("_live_f5_equiv_clock", true)
	tm.set("paused", false)
	if "total_days_elapsed" in tm:
		tm.set("total_days_elapsed", 0)
	var t0 := Time.get_ticks_usec()
	var live: Dictionary = gd.call("apply_interactive_multi_ai_day_live", 1)
	var apply_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var prof: Dictionary = {}
	if gd.has_method("get_last_interactive_multi_ai_profile"):
		prof = gd.call("get_last_interactive_multi_ai_profile")
	_print_country_profile("apply_live", prof, apply_ms)
	if bool(live.get("skipped", false)):
		_fail("interactive multi-AI skipped on live nation set: %s" % str(live.get("reason", "")))
	var prod_tags: Array = live.get("prod_tags", []) as Array
	if "GER" in prod_tags:
		_fail("GER player leaked into prod_tags %s" % str(prod_tags))
	elif prod_tags.size() < 1:
		_fail("no production tags applied")
	else:
		_pass("prod_tags=%s soft=%s" % [str(prod_tags), str(live.get("soft_tag", ""))])
	if apply_ms >= FRAME_BUDGET_MS:
		_fail("apply_interactive_multi_ai_day_live %.1fms >= %.0f (289268ed class)" % [apply_ms, FRAME_BUDGET_MS])
	else:
		_pass("apply_interactive_multi_ai_day_live %.1fms < %.0f" % [apply_ms, FRAME_BUDGET_MS])
	t0 = Time.get_ticks_usec()
	tm.call("_maybe_run_interactive_multi_ai")
	var maybe_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("HeadlessPerf4InteractiveMultiAiTest: _maybe_run_interactive_multi_ai=%.1fms" % maybe_ms)
	if maybe_ms >= FRAME_BUDGET_MS:
		_fail("_maybe_run_interactive_multi_ai %.1fms >= %.0f" % [maybe_ms, FRAME_BUDGET_MS])
	else:
		_pass("_maybe_run_interactive_multi_ai %.1fms < %.0f" % [maybe_ms, FRAME_BUDGET_MS])
	# Behaviour mutant: live Play must keep the full supply day.
	var supply_last: Dictionary = {}
	if "peace_state" in gd:
		var ps: Dictionary = gd.peace_state
		var raw: Variant = ps.get("supply_last_live_apply", {})
		if raw is Dictionary:
			supply_last = raw as Dictionary
	var detail := str(supply_last.get("detail", ""))
	if detail != "advance_supply_day":
		_fail("soft supply skipped full day (detail=%s)" % detail)
	else:
		_pass("soft supply full-day detail=%s" % detail)
	var depots := 0
	if sm != null and "depot_states" in sm:
		depots = int((sm.depot_states as Dictionary).size())
	if depots < 2000:
		_fail("depots dropped after multi-AI (%d)" % depots)
	tm.set("_live_f5_equiv_clock", false)


func _print_country_profile(label: String, prof: Dictionary, wall_ms: float) -> void:
	print(
		"HeadlessPerf4InteractiveMultiAiTest: %s wall=%.1fms profile_total=%.1fms player=%s day=%s"
		% [
			label,
			wall_ms,
			float(prof.get("total_ms", 0.0)),
			str(prof.get("player_tag", "")),
			str(prof.get("day_index", "")),
		]
	)
	var rows: Array = prof.get("countries", []) as Array
	for raw in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		print(
			"HeadlessPerf4InteractiveMultiAiTest:   %s %s=%.2fms ok=%s lines=%s delta=%s"
			% [
				str(row.get("tag", "?")),
				str(row.get("step", "?")),
				float(row.get("ms", 0.0)),
				str(row.get("ok", false)),
				str(row.get("lines_touched", 0)),
				str(row.get("stock_delta", 0)),
			]
		)


func _collect_infra_decisions(idm: Node, days: int, seed: int, mm: Node = null) -> Array:
	var out: Array = []
	if idm == null or not idm.has_method("try_ai_start_infra_project"):
		return out
	if mm != null and "_live_fronts_precompute" in mm:
		mm.set("_live_fronts_precompute", {})
	if "active_projects" in idm:
		(idm.active_projects as Dictionary).clear()
	if "_ai_infra_budget_day" in idm:
		idm.set("_ai_infra_budget_day", -1)
	if "_ai_infra_starts_today" in idm:
		idm.set("_ai_infra_starts_today", 0)
	seed(seed)
	for day_i in range(1, days + 1):
		if "_ai_infra_starts_today" in idm:
			idm.set("_ai_infra_starts_today", 0)
		if "_ai_infra_budget_day" in idm:
			idm.set("_ai_infra_budget_day", -1)
		var res: Dictionary = idm.call("try_ai_start_infra_project", "", day_i)
		out.append({
			"day": day_i,
			"tag": str(res.get("tag", "")),
			"pid": int(res.get("province_id", res.get("pid", 0))),
			"started": bool(res.get("started", false)),
			"reason": str(res.get("reason", "")),
		})
	return out


func _test_production_cache_measured(pm: Node) -> void:
	if pm == null or not pm.has_method("advance_days_for_country"):
		_fail("advance_days_for_country missing")
		return
	if not pm.has_method("begin_interactive_multi_ai_day_cache"):
		_fail("production day cache missing")
		return
	if pm.has_method("end_interactive_multi_ai_day_cache"):
		pm.call("end_interactive_multi_ai_day_cache")
	var scan0 := int(pm.get("interactive_ai_line_scan_count")) if "interactive_ai_line_scan_count" in pm else -1
	if scan0 < 0:
		_fail("interactive_ai_line_scan_count missing")
		return
	var t0 := Time.get_ticks_usec()
	for _i in 6:
		pm.call("advance_days_for_country", "JAP", 1.0)
		pm.call("advance_days_for_country", "FRA", 1.0)
		pm.call("advance_days_for_country", "ENG", 1.0)
	var uncached_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var scan_unc := int(pm.get("interactive_ai_line_scan_count")) - scan0
	pm.call("begin_interactive_multi_ai_day_cache")
	var scan1 := int(pm.get("interactive_ai_line_scan_count"))
	t0 = Time.get_ticks_usec()
	for _j in 6:
		pm.call("advance_days_for_country", "JAP", 1.0)
		pm.call("advance_days_for_country", "FRA", 1.0)
		pm.call("advance_days_for_country", "ENG", 1.0)
	var cached_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var scan_c := int(pm.get("interactive_ai_line_scan_count")) - scan1
	if pm.has_method("end_interactive_multi_ai_day_cache"):
		pm.call("end_interactive_multi_ai_day_cache")
	print(
		"HeadlessPerf4InteractiveMultiAiTest: prod_cache uncached=%.2fms scans=%d cached=%.2fms scans=%d"
		% [uncached_ms, scan_unc, cached_ms, scan_c]
	)
	if scan_c != 0:
		_fail("cached production still scanned lines scans=%d" % scan_c)
	elif scan_unc < 6:
		_fail("uncached production walks too few scans=%d" % scan_unc)
	elif cached_ms <= 0.0 or uncached_ms <= cached_ms:
		_fail("production cache no timing benefit cached=%.2fms uncached=%.2fms" % [cached_ms, uncached_ms])
	else:
		_pass("production cache cached=%.2fms < uncached=%.2fms scans %d→0" % [cached_ms, uncached_ms, scan_unc])


func _test_ai_infra_outcome_equivalence(idm: Node, mm: Node = null) -> void:
	if idm == null:
		_fail("IDM missing for equivalence")
		return
	# Live-weight hubs + seeded OOB lines change which majors have infra
	# candidates vs the stripped DailySimTick board. Seed 193601 must still
	# be deterministic on *this* board (two collects match). The main-vs-fix
	# sequence (JAP 903951 / FRA 710739 / …) is gated by
	# HeadlessPerf4DailySimTickTest.
	var a: Array = _collect_infra_decisions(idm, EQUIV_DAYS, EQUIV_SEED, mm)
	var b: Array = _collect_infra_decisions(idm, EQUIV_DAYS, EQUIV_SEED, mm)
	if a.size() != EQUIV_DAYS or b.size() != EQUIV_DAYS:
		_fail("infra run length a=%d b=%d" % [a.size(), b.size()])
		return
	var same := true
	for i in a.size():
		if str(a[i]) != str(b[i]):
			same = false
			_fail("infra day %s mismatch %s vs %s" % [str(a[i].get("day")), str(a[i]), str(b[i])])
			break
	if same:
		_pass("AI infra decisions identical over %d days seed=%d (live-weight board)" % [EQUIV_DAYS, EQUIV_SEED])
		print("HeadlessPerf4InteractiveMultiAiTest: infra_decisions=%s" % str(a))


func _test_live_day_path_includes_multi_ai(tm: Node, idm: Node) -> void:
	if not tm.has_method("advance_live_f5_equivalent_days"):
		_fail("advance_live_f5_equivalent_days missing")
		return
	if tm.has_method("clear_day_tick_history"):
		tm.call("clear_day_tick_history")
	tm.set("paused", false)
	if "current_year" in tm:
		tm.set("current_year", 1936)
		tm.set("current_month", 1)
		tm.set("current_day", 1)
		tm.set("current_hour", 0)
		tm.set("total_days_elapsed", 0)
		tm.set("_accumulated_game_days", 0.0)
		tm.set("_accumulated_game_hours", 0.0)
	var t0 := Time.get_ticks_usec()
	var clock: Dictionary = tm.call("advance_live_f5_equivalent_days", EQUIV_DAYS)
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("HeadlessPerf4InteractiveMultiAiTest: live_f5_equiv clock=%s wall=%.1fms" % [str(clock), wall_ms])
	var history: Array = []
	if tm.has_method("get_day_tick_history"):
		history = tm.call("get_day_tick_history")
	var worst := 0.0
	var worst_kind := ""
	var worst_multi := 0.0
	var saw_multi := false
	for raw in history:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var ms := float(row.get("worst_phase_ms", 0.0))
		if ms >= worst:
			worst = ms
			worst_kind = str(row.get("worst_phase", ""))
		var steps: Array = row.get("day_ai_steps", []) as Array
		for sv in steps:
			if typeof(sv) != TYPE_DICTIONARY:
				continue
			var sd: Dictionary = sv
			if str(sd.get("name", "")) != "multi_ai":
				continue
			saw_multi = true
			var mms := float(sd.get("ms", 0.0))
			if mms > worst_multi:
				worst_multi = mms
			var countries: Array = sd.get("countries", []) as Array
			if countries.is_empty():
				var mp: Dictionary = row.get("multi_ai_profile", {}) as Dictionary
				countries = mp.get("countries", []) as Array
			print(
				"HeadlessPerf4InteractiveMultiAiTest: day_ai multi_ai=%.1fms countries=%s"
				% [mms, str(countries)]
			)
	print(
		"HeadlessPerf4InteractiveMultiAiTest: worst_phase=%s %.1fms worst_multi_ai=%.1fms budget=%.0f"
		% [worst_kind, worst, worst_multi, FRAME_BUDGET_MS]
	)
	if history.is_empty():
		_fail("no day-tick profile history")
		return
	if not saw_multi:
		_fail("advance_live_f5_equivalent_days never recorded multi_ai (old harness gap)")
	if worst >= FRAME_BUDGET_MS:
		_fail("worst daily-tick phase %.1fms >= %.0f (%s)" % [worst, FRAME_BUDGET_MS, worst_kind])
	else:
		_pass("worst daily-tick phase %.1fms < %.0f (%s)" % [worst, FRAME_BUDGET_MS, worst_kind])
	if worst_multi >= FRAME_BUDGET_MS:
		_fail("worst multi_ai step %.1fms >= %.0f" % [worst_multi, FRAME_BUDGET_MS])
	elif saw_multi:
		_pass("worst multi_ai step %.1fms < %.0f" % [worst_multi, FRAME_BUDGET_MS])


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
