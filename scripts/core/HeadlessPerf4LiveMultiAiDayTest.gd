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
## the network and stays on the F5 light supply path.
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
	_test_multi_ai_decisions_stable(gd, tm)
	_test_live_day_ai_budget(tm, gd)


func _test_source_gates_fail_on_pre_fix() -> void:
	var sm_src := _read(SRC_SM)
	var depot := _slice_func(sm_src, "set_player_depot")
	if depot.is_empty() or "changed" not in depot:
		_fail("set_player_depot still rebuilds every call (pre-fix / main FAIL class)")
	else:
		_pass("set_player_depot rebuilds only on membership change")
	var adv := _slice_func(sm_src, "advance_supply_day")
	if "_should_use_interactive_light_supply" not in adv and "_advance_supply_day_light" not in adv:
		_fail("advance_supply_day missing F5 light gate (pre-fix FAIL class)")
	else:
		_pass("advance_supply_day uses F5 light path")
	var gd_src := _read(SRC_GD)
	var mut := _slice_func(gd_src, "apply_supply_route_mutation")
	if "get_province" not in mut:
		_fail("apply_supply still set_player_depot on dummy pid 1 (pre-fix FAIL class)")
	else:
		_pass("apply_supply requires a real map province before set_player_depot")
	var live := _slice_func(gd_src, "apply_interactive_multi_ai_day_live")
	if "apply_production_for_tag" not in live or "apply_order_panel_action" not in live:
		_fail("interactive multi-AI live body lost production / apply_supply")
	else:
		_pass("interactive multi-AI still applies production + apply_supply")


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
	t0 = Time.get_ticks_usec()
	if sm.has_method("set_player_depot"):
		sm.call("set_player_depot", 1, true)
	var depot_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var live: Dictionary = gd.call("apply_interactive_multi_ai_day_live", 1)
	var live_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if "_live_f5_equiv_clock" in tm:
		tm.set("_live_f5_equiv_clock", false)
	print(
		"HeadlessPerf4LiveMultiAiDayTest: steps prod=%.1fms supply=%.1fms depot=%.1fms multi_ai=%.1fms prod_ok=%s supply_ok=%s live_ok=%s tags=%s"
		% [
			prod_ms,
			supply_ms,
			depot_ms,
			live_ms,
			str(bool(prod.get("ok", false))),
			str(bool(supply.get("ok", false))),
			str(bool(live.get("ok", false))),
			str(live.get("prod_tags", [])),
		]
	)
	if live_ms >= DAY_BUDGET_MS:
		_fail("apply_interactive_multi_ai_day_live %.1fms >= %.0f (still rebuilding?)" % [live_ms, DAY_BUDGET_MS])
	else:
		_pass("apply_interactive_multi_ai_day_live %.1fms < %.0f" % [live_ms, DAY_BUDGET_MS])
	if depot_ms >= DAY_BUDGET_MS:
		_fail("set_player_depot(1) %.1fms >= %.0f (dummy pid still rebuilds)" % [depot_ms, DAY_BUDGET_MS])
	else:
		_pass("set_player_depot(1) no-op/cheap %.1fms" % depot_ms)


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
		_pass("worst day_ai %.1fms < %.0f" % [worst_ai, DAY_BUDGET_MS])


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
