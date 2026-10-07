extends SceneTree

## PERF-4: daily sim-tick hitch. Times the live-F5 day-advance path
## (day_emit / day_ai / day_battles) on world_accurate. FAILS on main
## (get_peace_state still deep-copies; no per-listener timers / owner index).
## PASSES on this branch: worst phase < 500ms + same AI infra decisions.
## Does NOT boot the F5 supply network — see HeadlessPerf4LiveMultiAiDayTest
## for the live Begin-GER interactive multi-AI cost.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessPerf4DailySimTickTest.gd

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const SRC_GD := "res://scripts/autoload/GameData.gd"
const SRC_TM := "res://scripts/autoload/TimeManager.gd"
const SRC_MM := "res://scripts/map/MapManager.gd"
const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const EQUIV_DAYS := 7
const EQUIV_SEED := 193601
const PEACE_COPY_LOOPS := 24

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf4DailySimTickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf4DailySimTickTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessPerf4DailySimTickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf4DailySimTickTest: RESULT=", "PASS" if ok else "FAIL")
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
	_test_source_gates_fail_on_main()
	var mm: Node = root.get_node_or_null("/root/MapManager")
	var tm: Node = root.get_node_or_null("/root/TimeManager")
	var gd: Node = root.get_node_or_null("/root/GameData")
	var idm: Node = root.get_node_or_null("/root/InfrastructureDevelopmentManager")
	if mm == null or tm == null:
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
	if idm != null and idm.has_method("initialize_with_time"):
		idm.call("initialize_with_time")
	_test_peace_state_read_is_cheap(gd)
	_test_owner_index_is_cached(mm)
	_test_live_day_path_budget(tm, idm)
	_test_ai_infra_outcome_equivalence(idm)


func _test_source_gates_fail_on_main() -> void:
	var gd_src := _read(SRC_GD)
	var get_ps := _slice_func(gd_src, "get_peace_state")
	var peek := _slice_func(gd_src, "peek_peace_state")
	if peek.is_empty() or "duplicate(" in peek:
		_fail("peek_peace_state missing or still copies (main FAIL class)")
	else:
		_pass("peek_peace_state live ref")
	if "duplicate(true)" in get_ps:
		_fail("get_peace_state still deep-copies (main FAIL class)")
	else:
		_pass("get_peace_state no deepcopy")
	var tm_src := _read(SRC_TM)
	if "_emit_game_day_advanced_profiled" not in tm_src:
		_fail("TimeManager missing per-listener timers (main FAIL class)")
	else:
		_pass("per-listener day-tick timers")
	if "DAY_TICK_FRAME_BUDGET_MS" not in tm_src:
		_fail("DAY_TICK_FRAME_BUDGET_MS missing")
	var mm_src := _read(SRC_MM)
	if "_ensure_owner_index" not in mm_src:
		_fail("MapManager missing owner index (main FAIL class)")
	else:
		_pass("owner index present")
	var idm_src := _read(SRC_IDM)
	var try_fn := _slice_func(idm_src, "try_start_infrastructure_investment")
	if "peek_peace_state" not in try_fn:
		_fail("try_start still deep-copies peace_state (main FAIL class)")
	else:
		_pass("AI infra start peeks peace_state")


func _test_peace_state_read_is_cheap(gd: Node) -> void:
	if gd == null or not gd.has_method("get_peace_state"):
		_fail("GameData.get_peace_state missing")
		return
	# Warm init.
	gd.call("get_peace_state")
	var t0 := Time.get_ticks_usec()
	for _i in PEACE_COPY_LOOPS:
		gd.call("get_peace_state")
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("HeadlessPerf4DailySimTickTest: get_peace_state x%d = %.2fms" % [PEACE_COPY_LOOPS, ms])
	# Main's duplicate(true) × 24 of the live blob is the 1.7s class. Peek is << 50ms.
	if ms >= 500.0:
		_fail("get_peace_state x%d took %.1fms (still copying?)" % [PEACE_COPY_LOOPS, ms])
	else:
		_pass("get_peace_state x%d = %.2fms" % [PEACE_COPY_LOOPS, ms])


func _test_owner_index_is_cached(mm: Node) -> void:
	if not mm.has_method("get_provinces_by_owner"):
		_fail("get_provinces_by_owner missing")
		return
	var tags: Array = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"]
	var t0 := Time.get_ticks_usec()
	var n0 := 0
	for tag_v in tags:
		var owned: Array = mm.call("get_provinces_by_owner", str(tag_v))
		n0 += owned.size()
	var first_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var n1 := 0
	for tag_v2 in tags:
		var owned2: Array = mm.call("get_provinces_by_owner", str(tag_v2))
		n1 += owned2.size()
	var second_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print(
		"HeadlessPerf4DailySimTickTest: owner_index first=%.2fms second=%.2fms n=%d/%d"
		% [first_ms, second_ms, n0, n1]
	)
	if n0 < 100 or n0 != n1:
		_fail("owner_index membership mismatch n0=%d n1=%d" % [n0, n1])
	elif second_ms > 50.0:
		_fail("owner_index cache miss? second=%.1fms" % second_ms)
	else:
		_pass("owner_index cached second=%.2fms n=%d" % [second_ms, n1])


func _collect_infra_decisions(idm: Node, days: int, seed: int) -> Array:
	var out: Array = []
	if idm == null or not idm.has_method("try_ai_start_infra_project"):
		return out
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


func _test_ai_infra_outcome_equivalence(idm: Node) -> void:
	if idm == null:
		_fail("IDM missing for equivalence")
		return
	var a: Array = _collect_infra_decisions(idm, EQUIV_DAYS, EQUIV_SEED)
	var b: Array = _collect_infra_decisions(idm, EQUIV_DAYS, EQUIV_SEED)
	if a.size() != EQUIV_DAYS or b.size() != EQUIV_DAYS:
		_fail("equivalence run length a=%d b=%d" % [a.size(), b.size()])
		return
	var same := true
	for i in a.size():
		var da: Dictionary = a[i]
		var db: Dictionary = b[i]
		if str(da) != str(db):
			same = false
			_fail("infra decision day %s mismatch %s vs %s" % [str(da.get("day")), str(da), str(db)])
			break
	if same:
		_pass("AI infra decisions identical over %d days seed=%d" % [EQUIV_DAYS, EQUIV_SEED])
		print("HeadlessPerf4DailySimTickTest: infra_decisions=%s" % str(a))


func _test_live_day_path_budget(tm: Node, idm: Node) -> void:
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
	if idm != null and "active_projects" in idm:
		# Leave any seeded projects; live path must stay cheap with projects too.
		pass
	var t0 := Time.get_ticks_usec()
	var clock: Dictionary = tm.call("advance_live_f5_equivalent_days", EQUIV_DAYS)
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("HeadlessPerf4DailySimTickTest: live_f5_equiv clock=%s wall=%.1fms" % [str(clock), wall_ms])
	var budget := 500
	if tm.has_method("get_day_tick_frame_budget_ms"):
		budget = int(tm.call("get_day_tick_frame_budget_ms"))
	var history: Array = []
	if tm.has_method("get_day_tick_history"):
		history = tm.call("get_day_tick_history")
	var worst := 0.0
	var worst_kind := ""
	var worst_listener := ""
	var worst_listener_ms := 0.0
	for raw in history:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var ms := float(row.get("worst_phase_ms", 0.0))
		if ms >= worst:
			worst = ms
			worst_kind = str(row.get("worst_phase", ""))
			worst_listener = str(row.get("worst_listener", ""))
			worst_listener_ms = float(row.get("worst_listener_ms", 0.0))
		var listeners: Array = row.get("listeners", []) as Array
		var parts: PackedStringArray = PackedStringArray()
		for lv in listeners:
			if typeof(lv) != TYPE_DICTIONARY:
				continue
			var ld: Dictionary = lv
			parts.append("%s=%.1f" % [str(ld.get("name", "?")), float(ld.get("ms", 0.0))])
		print(
			"HeadlessPerf4DailySimTickTest: day profile emit=%.1f ai=%.1f battles=%.1f listeners=[%s]"
			% [
				float(row.get("day_emit_ms", 0.0)),
				float(row.get("day_ai_ms", 0.0)),
				float(row.get("day_battles_ms", 0.0)),
				", ".join(parts),
			]
		)
	print(
		"HeadlessPerf4DailySimTickTest: worst_phase=%s %.1fms worst_listener=%s %.1fms budget=%d"
		% [worst_kind, worst, worst_listener, worst_listener_ms, budget]
	)
	if history.is_empty():
		_fail("no day-tick profile history (instrumentation not wired)")
		return
	if worst >= float(budget):
		_fail("worst daily-tick phase %.1fms >= %d (%s)" % [worst, budget, worst_kind])
	else:
		_pass("worst daily-tick phase %.1fms < %d (%s)" % [worst, budget, worst_kind])
	if worst_listener_ms >= float(budget):
		_fail("worst listener %s %.1fms >= %d" % [worst_listener, worst_listener_ms, budget])


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
