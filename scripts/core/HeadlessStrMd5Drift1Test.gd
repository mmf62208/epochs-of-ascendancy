extends SceneTree
## STRMD5-DRIFT-1 measurement. Same-process seed 1 ×2 at d30.
## RESULT=PASS means both runs finished and the per-unit / id diff was printed.
## Does not assert that str_md5 matches (and does not fail when it happens to).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessStrMd5Drift1Test.gd
##   STRMD5_DRIFT_1_DAYS=30   window (default 30)
##
## Boot/wipe copied from HeadlessSeedInvar1Test. That file is not edited.

const FORM_TAGS: Array[String] = ["GER", "FRA", "ENG", "SOV", "ITA", "JAP", "POL", "USA"]

const _STOCK_PROPS: Array[String] = [
	"national_stockpile",
	"national_equipment_stockpile",
	"country_equipment_stockpiles",
	"country_civilian_goods",
	"_unit_equipment_stock",
	"_family_units_produced",
	"_equipment_flows",
	"priority_reinforcement_units",
	"last_daily_harvest_report",
	"equipment_production_reliability",
	"province_resource_dev",
	"country_training_policy",
]

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _stock_snap: Dictionary = {}


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessStrMd5Drift1Test: ", msg)


func _run() -> void:
	var days := 30
	var env_days := OS.get_environment("STRMD5_DRIFT_1_DAYS").strip_edges()
	if not env_days.is_empty() and env_days.is_valid_int():
		days = maxi(int(env_days), 1)
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	print("HeadlessStrMd5Drift1Test: days=%d seed=1 in-process repeat=2" % days)
	_capture_stock(get_root().get_node_or_null("ProductionManager"))
	var run1: Dictionary = await _run_seed(1, days, 1)
	var run2: Dictionary = await _run_seed(1, days, 2)
	_print_diff(run1, run2)
	var ok := _failures == 0
	print("HeadlessStrMd5Drift1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessStrMd5Drift1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _run_seed(seed_v: int, days: int, pass_n: int) -> Dictionary:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var pm := get_root().get_node_or_null("ProductionManager")
	var fm := get_root().get_node_or_null("FactoryManager")
	var empty := {
		"pass": pass_n,
		"seed": seed_v,
		"ctrl_md5": "",
		"battles": 0,
		"cas_total": 0,
		"org_sum": 0.0,
		"str_sum": 0.0,
		"changes": 0,
		"str_md5": "",
		"start_str_md5": "",
		"start_n": 0,
		"lines": 0,
		"units": {},
		"alloc_start": {},
		"alloc_end": {},
		"stock_end": {},
	}
	if mm == null or tm == null or lm == null or _boot == null or _war == null or _cap == null:
		_fail("pass %d autoloads missing" % pass_n)
		return empty
	for _drain in 4:
		await process_frame
	seed(1)
	tm.run_seed = 0
	_restore_stock(pm)
	_wipe_sim_state(bm, pm, fm, lm, tm)
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
	if not _boot.boot(mm, sm, "USA"):
		_fail("pass %d boot failed" % pass_n)
		return empty
	_cap.apply_economy_factories_to_map()
	if _script_has(_boot, "boot_ai_production"):
		_boot.call("boot_ai_production", "USA")
	_war.reset_for_test()
	_cap.reset_for_test()
	if _end != null:
		_end.call("reset_for_test")
	if _war.has_method("clear_rule_overrides"):
		_war.call("clear_rule_overrides")
	if bm != null and bm.has_method("reset_ai_war1_for_test"):
		bm.call("reset_ai_war1_for_test")
	_clear_battle_residue(bm, tm)
	if lm.has_method("seed_1936_start_garrisons"):
		lm.call("seed_1936_start_garrisons", true)
	tm.run_seed = seed_v
	_cap.ensure_snapshot()
	var dec: Dictionary = _war.declare_war("GER", "POL", "strmd5_drift_1")
	if not bool(dec.get("ok", false)):
		_fail("pass %d declare %s" % [pass_n, JSON.stringify(dec)])
		return empty
	var start_sums := _formation_sums(lm)
	var start_ctrl := _controller_map(mm)
	var alloc_start := _read_allocators(lm, pm, bm, tm)
	print(
		"HeadlessStrMd5Drift1Test: pass=%d run_seed=%d hash1=%d hash2=%d start_ctrl_md5=%s"
		% [
			pass_n,
			int(tm.run_seed),
			int(hash([1, 1])),
			int(hash([2, 1])),
			_ctrl_md5(start_ctrl),
		]
	)
	print(
		"HeadlessStrMd5Drift1Test: pass=%d ALLOC_START %s"
		% [pass_n, _fmt_alloc(alloc_start)]
	)
	var seen: Dictionary = {}
	var cas_seen: Dictionary = {}
	var changes := 0
	var prev := start_ctrl.duplicate()
	for _d in range(days):
		tm.call("advance_live_f5_equivalent_days", 1)
		await process_frame
		await process_frame
		if _d == 0 or _d == days - 1:
			print(
				"HeadlessStrMd5Drift1Test: pass=%d day=%d run_seed=%d elapsed=%d reseed_calls=%d"
				% [
					pass_n,
					_d + 1,
					int(tm.run_seed),
					int(tm.total_days_elapsed) if "total_days_elapsed" in tm else -1,
					int(tm._reseed_calls) if "_reseed_calls" in tm else -1,
				]
			)
		var now := _controller_map(mm)
		for pid in now.keys():
			if str(prev.get(pid, "")) != str(now[pid]):
				changes += 1
		prev = now
		if bm != null and bm.has_method("get_open_land_battles"):
			for raw in bm.call("get_open_land_battles"):
				if typeof(raw) != TYPE_DICTIONARY:
					continue
				var battle: Dictionary = raw
				var bid := _battle_key(battle)
				seen[bid] = true
				var cas := 0
				if battle.has("attacker_casualties"):
					cas += int(battle.get("attacker_casualties", 0))
				if battle.has("defender_casualties"):
					cas += int(battle.get("defender_casualties", 0))
				cas_seen[bid] = maxi(int(cas_seen.get(bid, 0)), cas)
	var cas_total := 0
	for bid2 in cas_seen.keys():
		cas_total += int(cas_seen[bid2])
	var sums := _formation_sums(lm)
	var lines_n := 0
	if pm != null and pm.has_method("get_line_ids"):
		lines_n = pm.get_line_ids().size()
	var units := _unit_table(lm)
	var alloc_end := _read_allocators(lm, pm, bm, tm)
	var stock_end := _stock_keys(pm)
	var row := {
		"pass": pass_n,
		"seed": seed_v,
		"ctrl_md5": _ctrl_md5(prev),
		"battles": seen.size(),
		"cas_total": cas_total,
		"org_sum": float(sums.get("org", 0.0)),
		"str_sum": float(sums.get("str", 0.0)),
		"str_md5": str(sums.get("md5", "")),
		"changes": changes,
		"lines": lines_n,
		"start_str_md5": str(start_sums.get("md5", "")),
		"start_ctrl_md5": _ctrl_md5(start_ctrl),
		"start_n": int(start_sums.get("n", 0)),
		"run_seed": int(tm.run_seed),
		"units": units,
		"alloc_start": alloc_start,
		"alloc_end": alloc_end,
		"stock_end": stock_end,
	}
	print(
		"HeadlessStrMd5Drift1Test: pass=%d seed=%d ctrl_md5=%s battles=%d cas_total=%d org_sum=%.6f str_sum=%.6f str_md5=%s changes=%d lines=%d start_n=%d start_str_md5=%s units=%d"
		% [
			pass_n,
			seed_v,
			str(row["ctrl_md5"]),
			int(row["battles"]),
			int(row["cas_total"]),
			float(row["org_sum"]),
			float(row["str_sum"]),
			str(row["str_md5"]),
			int(row["changes"]),
			lines_n,
			int(row["start_n"]),
			str(row["start_str_md5"]),
			units.size(),
		]
	)
	print(
		"HeadlessStrMd5Drift1Test: pass=%d ALLOC_END %s"
		% [pass_n, _fmt_alloc(alloc_end)]
	)
	print(
		"HeadlessStrMd5Drift1Test: pass=%d STOCK_END n=%d md5=%s"
		% [pass_n, int(stock_end.get("n", 0)), str(stock_end.get("md5", ""))]
	)
	_print_unit_prefix_counts(pass_n, units)
	return row


func _print_diff(run1: Dictionary, run2: Dictionary) -> void:
	print("HeadlessStrMd5Drift1Test: DIFF start_str_md5 r1=%s r2=%s match=%s" % [
		str(run1.get("start_str_md5", "")),
		str(run2.get("start_str_md5", "")),
		str(str(run1.get("start_str_md5", "")) == str(run2.get("start_str_md5", ""))).to_lower(),
	])
	print("HeadlessStrMd5Drift1Test: DIFF start_ctrl_md5 r1=%s r2=%s match=%s" % [
		str(run1.get("start_ctrl_md5", "")),
		str(run2.get("start_ctrl_md5", "")),
		str(str(run1.get("start_ctrl_md5", "")) == str(run2.get("start_ctrl_md5", ""))).to_lower(),
	])
	print("HeadlessStrMd5Drift1Test: DIFF run_seed r1=%d r2=%d" % [
		int(run1.get("run_seed", -1)),
		int(run2.get("run_seed", -1)),
	])
	print("HeadlessStrMd5Drift1Test: DIFF ctrl_md5 r1=%s r2=%s match=%s" % [
		str(run1.get("ctrl_md5", "")),
		str(run2.get("ctrl_md5", "")),
		str(str(run1.get("ctrl_md5", "")) == str(run2.get("ctrl_md5", ""))).to_lower(),
	])
	print("HeadlessStrMd5Drift1Test: DIFF battles r1=%d r2=%d" % [int(run1.get("battles", 0)), int(run2.get("battles", 0))])
	print("HeadlessStrMd5Drift1Test: DIFF changes r1=%d r2=%d" % [int(run1.get("changes", 0)), int(run2.get("changes", 0))])
	print("HeadlessStrMd5Drift1Test: DIFF org_sum r1=%.6f r2=%.6f d=%.6f" % [
		float(run1.get("org_sum", 0.0)),
		float(run2.get("org_sum", 0.0)),
		float(run2.get("org_sum", 0.0)) - float(run1.get("org_sum", 0.0)),
	])
	print("HeadlessStrMd5Drift1Test: DIFF str_sum r1=%.6f r2=%.6f d=%.6f" % [
		float(run1.get("str_sum", 0.0)),
		float(run2.get("str_sum", 0.0)),
		float(run2.get("str_sum", 0.0)) - float(run1.get("str_sum", 0.0)),
	])
	print("HeadlessStrMd5Drift1Test: DIFF str_md5 r1=%s r2=%s match=%s" % [
		str(run1.get("str_md5", "")),
		str(run2.get("str_md5", "")),
		str(str(run1.get("str_md5", "")) == str(run2.get("str_md5", ""))).to_lower(),
	])
	var a1: Dictionary = run1.get("alloc_start", {}) as Dictionary
	var a2: Dictionary = run2.get("alloc_start", {}) as Dictionary
	var e1: Dictionary = run1.get("alloc_end", {}) as Dictionary
	var e2: Dictionary = run2.get("alloc_end", {}) as Dictionary
	print("HeadlessStrMd5Drift1Test: DIFF ALLOC_START r1 %s" % _fmt_alloc(a1))
	print("HeadlessStrMd5Drift1Test: DIFF ALLOC_START r2 %s" % _fmt_alloc(a2))
	print("HeadlessStrMd5Drift1Test: DIFF ALLOC_END r1 %s" % _fmt_alloc(e1))
	print("HeadlessStrMd5Drift1Test: DIFF ALLOC_END r2 %s" % _fmt_alloc(e2))
	for key in ["fielded_seq", "leader_id_seq", "replacement_seq", "equipment_flow_seq", "next_land_battle_seq", "elapsed", "reseed_calls", "leader_pool_n", "pending_repl_n"]:
		var s1 := int(a1.get(key, -1))
		var s2 := int(a2.get(key, -1))
		var x1 := int(e1.get(key, -1))
		var x2 := int(e2.get(key, -1))
		if s1 != s2 or x1 != x2:
			print(
				"HeadlessStrMd5Drift1Test: DIFF ALLOC %s start r1=%d r2=%d end r1=%d r2=%d"
				% [key, s1, s2, x1, x2]
			)
	var u1: Dictionary = run1.get("units", {}) as Dictionary
	var u2: Dictionary = run2.get("units", {}) as Dictionary
	var only1: Array[String] = []
	var only2: Array[String] = []
	var changed: Array[String] = []
	var str_delta := 0.0
	var org_delta := 0.0
	var only1_str := 0.0
	var only1_org := 0.0
	var only2_str := 0.0
	var only2_org := 0.0
	for fid_v in u1.keys():
		var fid := str(fid_v)
		if not u2.has(fid):
			only1.append(fid)
			only1_str += float((u1[fid] as Dictionary).get("str", 0.0))
			only1_org += float((u1[fid] as Dictionary).get("org", 0.0))
			continue
		var r := u1[fid] as Dictionary
		var s := u2[fid] as Dictionary
		var ds := float(s.get("str", 0.0)) - float(r.get("str", 0.0))
		var dog := float(s.get("org", 0.0)) - float(r.get("org", 0.0))
		if absf(ds) > 0.000001 or absf(dog) > 0.000001:
			changed.append(fid)
			str_delta += ds
			org_delta += dog
	for fid_v2 in u2.keys():
		var fid2 := str(fid_v2)
		if not u1.has(fid2):
			only2.append(fid2)
			only2_str += float((u2[fid2] as Dictionary).get("str", 0.0))
			only2_org += float((u2[fid2] as Dictionary).get("org", 0.0))
	only1.sort()
	only2.sort()
	changed.sort()
	print(
		"HeadlessStrMd5Drift1Test: DIFF units n1=%d n2=%d only1=%d only2=%d changed=%d"
		% [u1.size(), u2.size(), only1.size(), only2.size(), changed.size()]
	)
	print(
		"HeadlessStrMd5Drift1Test: DIFF cancel only1_str=%.6f only2_str=%.6f d_str=%.6f only1_org=%.6f only2_org=%.6f d_org=%.6f changed_str_sum=%.6f changed_org_sum=%.6f"
		% [only1_str, only2_str, only2_str - only1_str, only1_org, only2_org, only2_org - only1_org, str_delta, org_delta]
	)
	var cap := 80
	_print_id_list("ONLY1", only1, u1, cap)
	_print_id_list("ONLY2", only2, u2, cap)
	var shown := 0
	for fid3 in changed:
		if shown >= cap:
			print("HeadlessStrMd5Drift1Test: DIFF CHANGED ... %d more" % (changed.size() - shown))
			break
		var ra: Dictionary = u1[fid3]
		var rb: Dictionary = u2[fid3]
		print(
			"HeadlessStrMd5Drift1Test: DIFF CHANGED fid=%s tag=%s pid=%d design=%s str %.5f->%.5f org %.5f->%.5f"
			% [
				fid3,
				str(ra.get("tag", "")),
				int(ra.get("pid", -1)),
				str(ra.get("design", "")),
				float(ra.get("str", 0.0)),
				float(rb.get("str", 0.0)),
				float(ra.get("org", 0.0)),
				float(rb.get("org", 0.0)),
			]
		)
		shown += 1
	_print_stock_diff(run1.get("stock_end", {}) as Dictionary, run2.get("stock_end", {}) as Dictionary)
	_print_station_join(only1, u1, only2, u2)


func _print_id_list(label: String, ids: Array[String], units: Dictionary, cap: int) -> void:
	if ids.is_empty():
		print("HeadlessStrMd5Drift1Test: DIFF %s (none)" % label)
		return
	var n := 0
	for fid in ids:
		if n >= cap:
			print("HeadlessStrMd5Drift1Test: DIFF %s ... %d more" % [label, ids.size() - n])
			break
		var row: Dictionary = units.get(fid, {})
		print(
			"HeadlessStrMd5Drift1Test: DIFF %s fid=%s tag=%s pid=%d design=%s str=%.5f org=%.5f"
			% [
				label,
				fid,
				str(row.get("tag", "")),
				int(row.get("pid", -1)),
				str(row.get("design", "")),
				float(row.get("str", 0.0)),
				float(row.get("org", 0.0)),
			]
		)
		n += 1


func _print_station_join(only1: Array[String], u1: Dictionary, only2: Array[String], u2: Dictionary) -> void:
	## Pair only-in-run ids that share tag+station+design: same unit, different allocator id.
	if only1.is_empty() and only2.is_empty():
		return
	var by_key2: Dictionary = {}
	for fid in only2:
		var row: Dictionary = u2.get(fid, {})
		var key := "%s|%d|%s" % [str(row.get("tag", "")), int(row.get("pid", -1)), str(row.get("design", ""))]
		if not by_key2.has(key):
			by_key2[key] = []
		(by_key2[key] as Array).append(fid)
	var paired := 0
	var unpaired1 := 0
	for fid1 in only1:
		var r1: Dictionary = u1.get(fid1, {})
		var key1 := "%s|%d|%s" % [str(r1.get("tag", "")), int(r1.get("pid", -1)), str(r1.get("design", ""))]
		var pool: Array = by_key2.get(key1, [])
		if pool.is_empty():
			unpaired1 += 1
			continue
		var fid2 := str(pool.pop_front())
		paired += 1
		if paired <= 40:
			var r2: Dictionary = u2.get(fid2, {})
			print(
				"HeadlessStrMd5Drift1Test: DIFF PAIR r1=%s r2=%s tag=%s pid=%d design=%s str %.5f/%.5f org %.5f/%.5f"
				% [
					fid1,
					fid2,
					str(r1.get("tag", "")),
					int(r1.get("pid", -1)),
					str(r1.get("design", "")),
					float(r1.get("str", 0.0)),
					float(r2.get("str", 0.0)),
					float(r1.get("org", 0.0)),
					float(r2.get("org", 0.0)),
				]
			)
	print(
		"HeadlessStrMd5Drift1Test: DIFF PAIR paired=%d unpaired_only1=%d leftover_only2=%d"
		% [paired, unpaired1, only2.size() - paired]
	)


func _print_stock_diff(s1: Dictionary, s2: Dictionary) -> void:
	print(
		"HeadlessStrMd5Drift1Test: DIFF STOCK n1=%d n2=%d md5_match=%s"
		% [
			int(s1.get("n", 0)),
			int(s2.get("n", 0)),
			str(str(s1.get("md5", "")) == str(s2.get("md5", ""))).to_lower(),
		]
	)
	var k1: Dictionary = s1.get("keys", {}) as Dictionary
	var k2: Dictionary = s2.get("keys", {}) as Dictionary
	var only1: Array[String] = []
	var only2: Array[String] = []
	var changed := 0
	for fid_v in k1.keys():
		var fid := str(fid_v)
		if not k2.has(fid):
			only1.append(fid)
		elif str(k1[fid]) != str(k2[fid]):
			changed += 1
	for fid_v2 in k2.keys():
		if not k1.has(str(fid_v2)):
			only2.append(str(fid_v2))
	only1.sort()
	only2.sort()
	print(
		"HeadlessStrMd5Drift1Test: DIFF STOCK only1=%d only2=%d changed=%d"
		% [only1.size(), only2.size(), changed]
	)
	var cap := 20
	for i in range(mini(cap, only1.size())):
		print("HeadlessStrMd5Drift1Test: DIFF STOCK_ONLY1 %s" % only1[i])
	for i2 in range(mini(cap, only2.size())):
		print("HeadlessStrMd5Drift1Test: DIFF STOCK_ONLY2 %s" % only2[i2])


func _print_unit_prefix_counts(pass_n: int, units: Dictionary) -> void:
	var counts: Dictionary = {}
	for fid_v in units.keys():
		var fid := str(fid_v)
		var pref := fid
		var cut := fid.find("_")
		if cut > 0:
			pref = fid.substr(0, cut)
		counts[pref] = int(counts.get(pref, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%d" % [str(k), int(counts[k])])
	print("HeadlessStrMd5Drift1Test: pass=%d ID_PREFIX %s" % [pass_n, " ".join(parts)])


func _unit_table(lm: Node) -> Dictionary:
	var out := {}
	if lm == null or not ("formations" in lm) or not (lm.formations is Dictionary):
		return out
	var forms: Dictionary = lm.formations
	for fid_v in forms.keys():
		var f: Object = forms[fid_v]
		if f == null:
			continue
		var tag := str(f.get("country_tag")).strip_edges().to_upper()
		if tag not in FORM_TAGS:
			continue
		var fid := str(fid_v)
		out[fid] = {
			"tag": tag,
			"str": float(f.get("strength")) if "strength" in f else 0.0,
			"org": float(f.get("organization")) if "organization" in f else 0.0,
			"pid": int(f.get("stationed_province_id")) if "stationed_province_id" in f else -1,
			"design": str(f.get("design_id")) if "design_id" in f else "",
		}
	return out


func _read_allocators(lm: Node, pm: Node, bm: Node, tm: Node) -> Dictionary:
	var out := {
		"fielded_seq": -1,
		"leader_id_seq": -1,
		"replacement_seq": -1,
		"garrisons_1936_seeded": -1,
		"equipment_flow_seq": -1,
		"unit_stock_n": -1,
		"next_land_battle_seq": -1,
		"elapsed": -1,
		"formations_n": -1,
		"reseed_calls": -1,
		"leader_pool_n": -1,
		"pending_repl_n": -1,
	}
	if lm != null:
		if "_fielded_seq" in lm:
			out["fielded_seq"] = int(lm._fielded_seq)
		if "_leader_id_seq" in lm:
			out["leader_id_seq"] = int(lm._leader_id_seq)
		if "_replacement_seq" in lm:
			out["replacement_seq"] = int(lm._replacement_seq)
		if "_garrisons_1936_seeded" in lm:
			out["garrisons_1936_seeded"] = 1 if bool(lm._garrisons_1936_seeded) else 0
		if "formations" in lm and lm.formations is Dictionary:
			out["formations_n"] = (lm.formations as Dictionary).size()
		if "leader_pool" in lm and lm.leader_pool is Dictionary:
			out["leader_pool_n"] = (lm.leader_pool as Dictionary).size()
		if "pending_leader_replacements" in lm and lm.pending_leader_replacements is Array:
			out["pending_repl_n"] = (lm.pending_leader_replacements as Array).size()
	if pm != null:
		if "_equipment_flow_seq" in pm:
			out["equipment_flow_seq"] = int(pm._equipment_flow_seq)
		if "_unit_equipment_stock" in pm and pm._unit_equipment_stock is Dictionary:
			out["unit_stock_n"] = (pm._unit_equipment_stock as Dictionary).size()
	if bm != null and "_next_land_battle_seq" in bm:
		out["next_land_battle_seq"] = int(bm._next_land_battle_seq)
	if tm != null:
		if "total_days_elapsed" in tm:
			out["elapsed"] = int(tm.total_days_elapsed)
		if "_reseed_calls" in tm:
			out["reseed_calls"] = int(tm._reseed_calls)
	return out


func _fmt_alloc(a: Dictionary) -> String:
	return (
		"fielded_seq=%d leader_id_seq=%d replacement_seq=%d garrisons_seeded=%d equipment_flow_seq=%d unit_stock_n=%d next_land_battle_seq=%d elapsed=%d formations_n=%d reseed_calls=%d leader_pool_n=%d pending_repl_n=%d"
		% [
			int(a.get("fielded_seq", -1)),
			int(a.get("leader_id_seq", -1)),
			int(a.get("replacement_seq", -1)),
			int(a.get("garrisons_1936_seeded", -1)),
			int(a.get("equipment_flow_seq", -1)),
			int(a.get("unit_stock_n", -1)),
			int(a.get("next_land_battle_seq", -1)),
			int(a.get("elapsed", -1)),
			int(a.get("formations_n", -1)),
			int(a.get("reseed_calls", -1)),
			int(a.get("leader_pool_n", -1)),
			int(a.get("pending_repl_n", -1)),
		]
	)


func _stock_keys(pm: Node) -> Dictionary:
	var keys := {}
	if pm == null or not ("_unit_equipment_stock" in pm) or not (pm._unit_equipment_stock is Dictionary):
		return {"n": 0, "md5": "", "keys": keys}
	var stock: Dictionary = pm._unit_equipment_stock
	var parts := PackedStringArray()
	for fid_v in stock.keys():
		var fid := str(fid_v)
		var blob: Variant = stock[fid_v]
		var total := 0
		if blob is Dictionary:
			for k in (blob as Dictionary).keys():
				total += int((blob as Dictionary).get(k, 0))
		keys[fid] = total
		parts.append("%s=%d" % [fid, total])
	parts.sort()
	return {"n": keys.size(), "md5": "\n".join(parts).md5_text(), "keys": keys}


func _wipe_sim_state(bm: Node, pm: Node, fm: Node, lm: Node, tm: Node) -> void:
	if pm != null and pm.has_method("get_line_ids") and pm.has_method("remove_line"):
		for lid_v in pm.get_line_ids():
			pm.remove_line(str(lid_v))
	if fm != null:
		if "factories" in fm and fm.factories is Dictionary:
			(fm.factories as Dictionary).clear()
		if "province_to_factories" in fm and fm.province_to_factories is Dictionary:
			(fm.province_to_factories as Dictionary).clear()
	if lm != null:
		if lm.has_method("clear_all_formations"):
			lm.call("clear_all_formations")
		elif "formations" in lm and lm.formations is Dictionary:
			(lm.formations as Dictionary).clear()
		if "_garrisons_1936_seeded" in lm:
			lm._garrisons_1936_seeded = false
	if bm != null:
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
		if "_pending_light_captures" in bm:
			bm._pending_light_captures = []
		if "_empty_hex_siege" in bm and bm._empty_hex_siege is Dictionary:
			(bm._empty_hex_siege as Dictionary).clear()
		if bm.has_method("reset_ai_war1_for_test"):
			bm.call("reset_ai_war1_for_test")
	if tm != null:
		if "_pending_sim_events" in tm:
			tm._pending_sim_events.clear()
		tm._live_f5_equiv_clock = false
		tm.paused = false
	var idm := get_root().get_node_or_null("InfrastructureDevelopmentManager")
	if idm != null and "active_projects" in idm and idm.active_projects is Dictionary:
		(idm.active_projects as Dictionary).clear()


func _clear_battle_residue(bm: Node, tm: Node) -> void:
	if bm != null:
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
		if "_next_land_battle_seq" in bm:
			bm._next_land_battle_seq = 1
		if "_last_land_aar" in bm and bm._last_land_aar is Dictionary:
			(bm._last_land_aar as Dictionary).clear()
		if "_capture_flush_armed" in bm:
			bm._capture_flush_armed = false
		if "_pending_light_captures" in bm:
			bm._pending_light_captures = []
		if "_empty_hex_siege" in bm and bm._empty_hex_siege is Dictionary:
			(bm._empty_hex_siege as Dictionary).clear()
	if tm != null:
		if "_pending_sim_events" in tm:
			tm._pending_sim_events.clear()
		tm._live_f5_equiv_clock = false
		tm.paused = false


func _controller_map(mm: Node) -> Dictionary:
	var ctrl := {}
	var provs: Dictionary = mm.call("get_all_provinces")
	for k in provs.keys():
		var p: Object = provs[k]
		if p == null or bool(p.get("is_sea")):
			continue
		ctrl[int(k)] = str(p.get("controller_tag")).strip_edges().to_upper()
	return ctrl


func _ctrl_md5(ctrl: Dictionary) -> String:
	var keys: Array = ctrl.keys()
	keys.sort()
	var parts := PackedStringArray()
	for pid in keys:
		parts.append("%d=%s" % [int(pid), str(ctrl[pid])])
	return "\n".join(parts).md5_text()


func _battle_key(battle: Dictionary) -> String:
	var bid := str(battle.get("id", "")).strip_edges()
	if not bid.is_empty():
		return bid
	return "%s|%d|%d|%s" % [
		str(battle.get("att_tag", "")),
		int(battle.get("from_id", -1)),
		int(battle.get("to_id", -1)),
		str(battle.get("att_fid", "")),
	]


func _formation_sums(lm: Node) -> Dictionary:
	var org := 0.0
	var strength := 0.0
	var parts := PackedStringArray()
	if lm == null or not ("formations" in lm) or not (lm.formations is Dictionary):
		return {"org": org, "str": strength, "md5": "", "n": 0}
	var forms: Dictionary = lm.formations
	for fid in forms.keys():
		var f: Object = forms[fid]
		if f == null:
			continue
		var tag := str(f.get("country_tag")).strip_edges().to_upper()
		if tag not in FORM_TAGS:
			continue
		var st := float(f.get("strength")) if "strength" in f else 0.0
		var og := float(f.get("organization")) if "organization" in f else 0.0
		strength += st
		org += og
		parts.append("%s:%.5f:%.5f" % [str(fid), st, og])
	parts.sort()
	return {"org": org, "str": strength, "md5": "\n".join(parts).md5_text(), "n": parts.size()}


func _capture_stock(pm: Node) -> void:
	_stock_snap.clear()
	if pm == null:
		return
	for prop in _STOCK_PROPS:
		if prop in pm and pm.get(prop) is Dictionary:
			_stock_snap[prop] = (pm.get(prop) as Dictionary).duplicate(true)
	if "_resource_plants_seeded" in pm:
		_stock_snap["_resource_plants_seeded"] = bool(pm._resource_plants_seeded)
	if "_equipment_flow_seq" in pm:
		_stock_snap["_equipment_flow_seq"] = int(pm._equipment_flow_seq)


func _restore_stock(pm: Node) -> void:
	if pm == null:
		return
	for prop_v in _stock_snap.keys():
		var prop := str(prop_v)
		if prop == "_resource_plants_seeded":
			pm._resource_plants_seeded = bool(_stock_snap[prop])
			continue
		if prop == "_equipment_flow_seq":
			pm._equipment_flow_seq = int(_stock_snap[prop])
			continue
		if prop in pm and _stock_snap[prop] is Dictionary:
			pm.set(prop, (_stock_snap[prop] as Dictionary).duplicate(true))


func _script_has(scr: GDScript, method_name: String) -> bool:
	for m in scr.get_script_method_list():
		if typeof(m) == TYPE_DICTIONARY and str((m as Dictionary).get("name", "")) == method_name:
			return true
	return false
