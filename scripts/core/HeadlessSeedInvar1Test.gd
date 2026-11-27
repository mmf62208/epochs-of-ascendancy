extends SceneTree
## SEED-INVAR-1 measurement. PASS means the runs finished and printed the table.
## It does not require seeds to differ. SEED_INVAR_1_ASSERT=differs (commit 2)
## requires seeds 1/2/3 to differ and the seed-1 repeat to match.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessSeedInvar1Test.gd
##   SEED_INVAR_1_DAYS=30   window (default 30)
##   SEED_INVAR_1_ONLY=1    one seed, for a fresh-process check

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
	print("  [FAIL] HeadlessSeedInvar1Test: ", msg)


func _run() -> void:
	var days := 30
	var env_days := OS.get_environment("SEED_INVAR_1_DAYS").strip_edges()
	if not env_days.is_empty() and env_days.is_valid_int():
		days = maxi(int(env_days), 1)
	var only := OS.get_environment("SEED_INVAR_1_ONLY").strip_edges()
	var seeds: Array[int] = [1, 2, 3, 1]
	if not only.is_empty() and only.is_valid_int():
		seeds = [int(only)]
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	var rng_match := _rng_api_matches()
	print(
		"HeadlessSeedInvar1Test: rng_api_match=%s days=%d pre_rng=1 boot_run_seed=0"
		% [str(rng_match).to_lower(), days]
	)
	var rows: Array = []
	_capture_stock(get_root().get_node_or_null("ProductionManager"))
	for seed_v in seeds:
		rows.append(await _run_seed(int(seed_v), days))
	if seeds.size() >= 3:
		var varied := false
		var first := str((rows[0] as Dictionary).get("ctrl_md5", ""))
		for i in range(1, 3):
			if str((rows[i] as Dictionary).get("ctrl_md5", "")) != first:
				varied = true
		print("HeadlessSeedInvar1Test: SEED_VARIANCE=%s" % ("differs" if varied else "identical"))
		if seeds.size() >= 4:
			var again := str((rows[3] as Dictionary).get("ctrl_md5", ""))
			var same := again == first and not first.is_empty()
			var str_same := str((rows[3] as Dictionary).get("str_md5", "")) == str((rows[0] as Dictionary).get("str_md5", ""))
			print(
				"HeadlessSeedInvar1Test: REPEAT seed=1 ctrl=%s str=%s"
				% [("identical" if same else "differs"), ("identical" if str_same else "differs")]
			)
			if OS.get_environment("SEED_INVAR_1_ASSERT").strip_edges() == "differs":
				if not varied:
					_fail("SEED_VARIANCE identical, want differs")
				if not same:
					_fail("seed 1 repeat moved")
	var ok := _failures == 0
	print("HeadlessSeedInvar1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSeedInvar1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _rng_api_matches() -> bool:
	var probe := RandomNumberGenerator.new()
	seed(424242)
	var global_draw := randf()
	probe.seed = 424242
	return probe.randf() == global_draw


func _run_seed(seed_v: int, days: int) -> Dictionary:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var pm := get_root().get_node_or_null("ProductionManager")
	var fm := get_root().get_node_or_null("FactoryManager")
	var empty := {
		"seed": seed_v, "ctrl_md5": "", "battles": 0, "cas_total": 0,
		"org_sum": 0.0, "str_sum": 0.0, "changes": 0, "rng_draws": -1, "str_md5": "",
		"lines": 0,
	}
	if mm == null or tm == null or lm == null or _boot == null or _war == null or _cap == null:
		_fail("seed %d autoloads missing" % seed_v)
		return empty
	# Let a previous seed's deferred capture or organize hit the old map.
	for _drain in 4:
		await process_frame
	# Boot must match a fresh process: run_seed 0, and the same global RNG.
	seed(1)
	tm.run_seed = 0
	_restore_stock(pm)
	_wipe_sim_state(bm, pm, fm, lm, tm)
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
	if not _boot.boot(mm, sm, "USA"):
		_fail("seed %d boot failed" % seed_v)
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
	# Do not wipe production lines or factories after boot_ai_production.
	_clear_battle_residue(bm, tm)
	if lm.has_method("seed_1936_start_garrisons"):
		lm.call("seed_1936_start_garrisons", true)
	tm.run_seed = seed_v
	_cap.ensure_snapshot()
	var dec: Dictionary = _war.declare_war("GER", "POL", "seed_invar_1")
	if not bool(dec.get("ok", false)):
		_fail("seed %d declare %s" % [seed_v, JSON.stringify(dec)])
		return empty
	var start_ctrl := _controller_map(mm)
	var start_sums := _formation_sums(lm)
	var seen: Dictionary = {}
	var cas_seen: Dictionary = {}
	var changes := 0
	var prev := start_ctrl.duplicate()
	var rng_draws := 0
	var rng_bad := false
	var rng_hit_days := 0
	for _d in range(days):
		tm.call("advance_live_f5_equivalent_days", 1)
		await process_frame
		await process_frame
		if int(tm.run_seed) != 0:
			var n := _draws_since_reseed(int(tm.run_seed), int(tm.total_days_elapsed))
			if n < 0:
				rng_bad = true
			else:
				rng_draws += n
				if n > 0:
					rng_hit_days += 1
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
	var row := {
		"seed": seed_v,
		"ctrl_md5": _ctrl_md5(prev),
		"battles": seen.size(),
		"cas_total": cas_total,
		"org_sum": float(sums.get("org", 0.0)),
		"str_sum": float(sums.get("str", 0.0)),
		"str_md5": str(sums.get("md5", "")),
		"changes": changes,
		"rng_draws": -1 if rng_bad else rng_draws,
		"rng_hit_days": rng_hit_days,
		"lines": lines_n,
		"start_str_md5": str(start_sums.get("md5", "")),
		"start_n": int(start_sums.get("n", 0)),
	}
	print(
		"HeadlessSeedInvar1Test: seed=%d ctrl_md5=%s battles=%d cas_total=%d org_sum=%.6f str_sum=%.6f str_md5=%s changes=%d rng_draws=%d rng_hit_days=%d lines=%d start_n=%d start_str_md5=%s"
		% [
			seed_v,
			str(row["ctrl_md5"]),
			int(row["battles"]),
			int(row["cas_total"]),
			float(row["org_sum"]),
			float(row["str_sum"]),
			str(row["str_md5"]),
			int(row["changes"]),
			int(row["rng_draws"]),
			int(row["rng_hit_days"]),
			lines_n,
			int(row["start_n"]),
			str(row["start_str_md5"]),
		]
	)
	return row


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


## Battles and queued captures only. Production lines stay.
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
		return {"org": org, "str": strength, "md5": ""}
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


## Draws since TimeManager._reseed_sim_day(day_index), using only the global RNG.
## RandomNumberGenerator does not match @GlobalScope on this Godot, so it is not used.
## Consumes one global randf, then reseeds. The next advance_days reseeds again.
func _draws_since_reseed(run_seed: int, day_index: int) -> int:
	var h := int(hash([run_seed, int(day_index)]))
	var actual := randf()
	seed(h)
	for k in range(4000):
		if randf() == actual:
			return k
	return -1


func _script_has(scr: GDScript, method_name: String) -> bool:
	for m in scr.get_script_method_list():
		if typeof(m) == TYPE_DICTIONARY and str((m as Dictionary).get("name", "")) == method_name:
			return true
	return false
