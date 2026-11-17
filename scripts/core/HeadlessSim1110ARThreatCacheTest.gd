extends SceneTree

## SIM-1110-A-R: single-stack front threat + per-tag cache.
## T1 two adjacent 1u stacks are NOT summed (P not reinforced).
## T2 a single 2-div stack still triggers reinforce.
## T3 passive-human GER border: no POL forward stacking; same decision with GER AI.
## T4 cache on/off same ctrl_md5 over 60d aivai; 0 rebuilds on a quiet day;
##    rebuild after capture/move.
## T5 threat path never calls get_formations_for_country (source + F5 probe).
## Each of T1–T5 must FAIL on main 330644ef (missing API / no reinforce trigger)
## and PASS on this tip. T1/T3 "not reinforced" asserts include a positive
## paired reinforce so they cannot pass trivially on a no-reinforce main.

const SRC_BM := "res://scripts/combat/BattleManager.gd"
const DAYS_T3 := 10
const DAYS_T4 := 60

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_AI_REJECT_LOG", "")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSim1110ARThreatCacheTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSim1110ARThreatCacheTest: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if mm == null or bm == null or tm == null or lm == null or _boot == null or _war == null:
		_fail("autoloads missing")
		_finish()
		return
	_test_t1_not_summed(mm, sm, bm, tm, lm)
	_test_t2_single_stack_triggers(mm, sm, bm, tm, lm)
	_test_t3_passive_human_border(mm, sm, bm, tm, lm)
	_test_t4_cache(mm, sm, bm, tm, lm)
	_test_t5_no_nation_scan(mm, sm, bm, tm, lm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessSim1110ARThreatCacheTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSim1110ARThreatCacheTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _api_ok(bm: Node) -> bool:
	if not bm.has_method("_ai_local_threat"):
		_fail("threat API missing: _ai_local_threat")
		return false
	if not bm.has_method("_ai_compute_foe_p"):
		_fail("threat API missing: _ai_compute_foe_p")
		return false
	if not bm.has_method("set_ai_threat_cache_enabled") or not bm.has_method("ai_threat_cache_counts"):
		_fail("cache API missing: set_ai_threat_cache_enabled / ai_threat_cache_counts")
		return false
	if not bm.has_method("bump_ai_station_gen"):
		_fail("cache API missing: bump_ai_station_gen")
		return false
	return true


func _test_t1_not_summed(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _api_ok(bm):
		return
	# Paired positive: a 2-div stack MUST reinforce, or "not reinforced" is trivial.
	var pos := _run_stack_fixture(mm, sm, bm, tm, lm, true, false)
	if not bool(pos.get("ok", false)):
		return
	if not bool(pos.get("reinforced", false)):
		_fail(
			"T1 precondition: 2-div stack did not reinforce P=%d s=%d md=%d threat=%.3f own=%.3f (main has no reinforce)"
			% [int(pos.get("p", 0)), int(pos.get("s_at", -1)), int(pos.get("s_md", -1)), float(pos.get("threat", 0.0)), float(pos.get("own", 0.0))]
		)
		return
	var two := _run_stack_fixture(mm, sm, bm, tm, lm, false, false)
	if not bool(two.get("ok", false)):
		return
	var threat := float(two.get("threat", 0.0))
	var max_stack := float(two.get("max_stack", 0.0))
	var own_p := float(two.get("own", 0.0))
	print(
		"SIM1110AR_T1 P=%d threat=%.3f max=%.3f own=%.3f r=%.3f s=%d md=%d"
		% [int(two.get("p", 0)), threat, max_stack, own_p, threat / maxf(own_p, 1.0), int(two.get("s_at", -1)), int(two.get("s_md", -1))]
	)
	if absf(threat - max_stack) > 0.0001:
		_fail("T1 two adjacent stacks were summed threat=%.3f max=%.3f" % [threat, max_stack])
		return
	if threat / maxf(own_p, 1.0) >= 1.2:
		_fail("T1 ratio %.3f >= 1.2 with unsummed stacks" % (threat / maxf(own_p, 1.0)))
		return
	if bool(two.get("reinforced", false)):
		_fail("T1 P was reinforced from two 1u stacks")
		return
	_pass("T1 single-stack not summed; P not reinforced (paired 2-div did reinforce)")


func _test_t2_single_stack_triggers(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _api_ok(bm):
		return
	var pos := _run_stack_fixture(mm, sm, bm, tm, lm, true, false)
	if not bool(pos.get("ok", false)):
		return
	print(
		"SIM1110AR_T2 P=%d threat=%.3f own=%.3f r=%.3f s=%d md=%d"
		% [int(pos.get("p", 0)), float(pos.get("threat", 0.0)), float(pos.get("own", 0.0)), float(pos.get("threat", 0.0)) / maxf(float(pos.get("own", 1.0)), 1.0), int(pos.get("s_at", -1)), int(pos.get("s_md", -1))]
	)
	if not bool(pos.get("reinforced", false)):
		_fail("T2 2-div stack did not reinforce P")
		return
	_pass("T2 single 2-div stack triggers reinforce")


func _test_t3_passive_human_border(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _api_ok(bm):
		return
	var pos := _run_stack_fixture(mm, sm, bm, tm, lm, true, false)
	if not bool(pos.get("ok", false)):
		return
	if not bool(pos.get("reinforced", false)):
		_fail("T3 precondition: 2-div stack did not reinforce (main has no reinforce)")
		return
	var human_row := _run_t3_border(mm, sm, bm, tm, lm, true)
	if not bool(human_row.get("ok", false)):
		return
	var ai_row := _run_t3_border(mm, sm, bm, tm, lm, false)
	if not bool(ai_row.get("ok", false)):
		return
	print(
		"SIM1110AR_T3 human n=%d max=%d threat=%.3f ai n=%d max=%d threat=%.3f"
		% [
			int(human_row.get("end_n", -1)), int(human_row.get("max_n", -1)), float(human_row.get("threat", 0.0)),
			int(ai_row.get("end_n", -1)), int(ai_row.get("max_n", -1)), float(ai_row.get("threat", 0.0)),
		]
	)
	if int(human_row.get("max_n", 99)) > int(human_row.get("start_n", 0)):
		_fail("T3 POL stacked forward vs human GER max_n=%d start=%d" % [int(human_row.get("max_n")), int(human_row.get("start_n"))])
		return
	if bool(human_row.get("reinforced", false)):
		_fail("T3 POL reinforced vs passive human GER")
		return
	if absf(float(human_row.get("threat", 0.0)) - float(ai_row.get("threat", 0.0))) > 0.0001:
		_fail("T3 threat human vs AI diverged")
		return
	if bool(ai_row.get("reinforced", false)) != bool(human_row.get("reinforced", false)):
		_fail("T3 reinforce decision human vs AI diverged")
		return
	_pass("T3 no forward stacking vs passive human; same decision with GER AI")


func _test_t4_cache(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _api_ok(bm):
		return
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("T4 seed missing")
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("T4 declare failed")
		return
	bm.call("set_ai_threat_cache_enabled", true)
	var pair_warm := _border_pair(mm, "GER", "POL")
	var warm_pid := int(pair_warm[1]) if pair_warm.size() >= 2 else 711058
	bm.call("_ai_local_threat", warm_pid, "POL")
	bm.call("reset_ai_threat_cache_counts")
	bm.call("_ai_local_threat", warm_pid, "POL")
	var quiet: Dictionary = bm.call("ai_threat_cache_counts")
	print("SIM1110AR_T4 quiet rebuilds=%s" % str(quiet.get("rebuilds", -1)))
	if int(quiet.get("rebuilds", -1)) != 0:
		_fail("T4 quiet day threat-cache rebuilds=%s want 0" % str(quiet.get("rebuilds")))
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("T4 no GER-POL border")
		return
	var x_pid := int(pair[0])
	var pol_pid := int(pair[1])
	bm.call("reset_ai_threat_cache_counts")
	bm.call("_apply_attacker_win_capture_light", "POL", x_pid, pol_pid, "")
	bm.call("try_ai_cover_threatened_borders")
	var after_cap: Dictionary = bm.call("ai_threat_cache_counts")
	print("SIM1110AR_T4 after_capture rebuilds=%s" % str(after_cap.get("rebuilds", -1)))
	if int(after_cap.get("rebuilds", 0)) <= 0:
		_fail("T4 no threat-cache rebuild after capture")
		return
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("T4 redeclare for move failed")
		return
	var fx: Dictionary = _threat_radius_fixture(mm)
	if int(fx.get("p", 0)) <= 0:
		_fail("T4 no P fixture for move rebuild")
		return
	var p_pid := int(fx["p"])
	var g1 := int(fx["g1"])
	var q := _quiet_pol_pid(mm, {p_pid: true})
	_vacate_tag_at(lm, "POL", p_pid, q)
	_make_garr(lm, "sim1110ar_t4_own", "POL", p_pid, 1.0)
	_boot.make_division("sim1110ar_t4_e", "GER", g1)
	_keep_only_formations(lm, ["sim1110ar_t4_own", "sim1110ar_t4_e"])
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	bm.call("set_ai_threat_cache_enabled", true)
	bm.call("_ai_local_threat", p_pid, "POL")
	bm.call("reset_ai_threat_cache_counts")
	var ger_f: Object = lm.call("get_formation", "sim1110ar_t4_e") if lm.has_method("get_formation") else null
	var g2 := int(fx.get("g2", g1))
	if ger_f != null:
		ger_f.set("stationed_province_id", g2)
	bm.call("bump_ai_station_gen", "GER")
	bm.call("_ai_local_threat", p_pid, "POL")
	var after_move: Dictionary = bm.call("ai_threat_cache_counts")
	print("SIM1110AR_T4 after_move rebuilds=%s" % str(after_move.get("rebuilds", -1)))
	if int(after_move.get("rebuilds", 0)) <= 0:
		_fail("T4 no threat-cache rebuild after move")
		return
	var md5_on := _run_aivai_ctrl_md5(mm, sm, bm, tm, lm, true)
	if md5_on.is_empty():
		return
	var md5_off := _run_aivai_ctrl_md5(mm, sm, bm, tm, lm, false)
	if md5_off.is_empty():
		return
	print("SIM1110AR_T4 ctrl_md5 on=%s off=%s" % [md5_on, md5_off])
	if md5_on != md5_off:
		_fail("T4 cache on/off ctrl_md5 diverged on=%s off=%s" % [md5_on, md5_off])
		return
	bm.call("set_ai_threat_cache_enabled", true)
	_pass("T4 cache on/off same ctrl_md5; 0 quiet rebuilds; rebuild after capture/move")


func _test_t5_no_nation_scan(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _api_ok(bm):
		return
	var src := FileAccess.get_file_as_string(SRC_BM)
	if src.is_empty():
		_fail("T5 could not read BattleManager.gd")
		return
	for fname in ["_ai_local_threat", "_ai_compute_foe_p", "_ai_max_adjacent_enemy_stack_power", "_ai_hex_power", "_ai_ensure_threat_cache"]:
		var body := _func_body(src, fname)
		if body.is_empty():
			_fail("T5 %s missing" % fname)
			return
		if "get_formations_for_country" in body:
			_fail("T5 %s calls get_formations_for_country" % fname)
			return
	var hex_body := _func_body(src, "_ai_hex_power")
	if "get_divisions_at_province" not in hex_body:
		_fail("T5 _ai_hex_power does not use get_divisions_at_province")
		return
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("T5 declare failed")
		return
	if lm.has_method("seed_1936_start_garrisons"):
		lm.call("seed_1936_start_garrisons", true)
	bm.call("reset_ai_threat_cache_counts")
	if tm.has_method("advance_live_f5_equivalent_days"):
		tm.call("advance_live_f5_equivalent_days", 1)
	else:
		bm.call("try_ai_start_land_battles", 0)
	var gffc := 0
	if bm.has_method("ai_threat_gffc_calls"):
		gffc = int(bm.call("ai_threat_gffc_calls"))
	print("SIM1110AR_T5 gffc_calls=%d" % gffc)
	if gffc != 0:
		_fail("T5 threat path get_formations_for_country calls=%d during F5" % gffc)
		return
	_pass("T5 threat path has no get_formations_for_country; F5 gffc=0")
	var _unused_t5 := sm


func _run_aivai_ctrl_md5(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, cache_on: bool) -> String:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return ""
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("T4 seed missing for cache %s" % str(cache_on))
		return ""
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("T4 declare failed for cache %s" % str(cache_on))
		return ""
	bm.call("set_ai_threat_cache_enabled", cache_on)
	for _d in range(DAYS_T4):
		if tm.has_method("advance_live_f5_equivalent_days"):
			tm.call("advance_live_f5_equivalent_days", 1)
		else:
			bm.call("try_ai_start_land_battles", _d)
	return _ctrl_md5(mm)


func _run_t3_border(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, ger_human: bool) -> Dictionary:
	var player := "GER" if ger_human else "USA"
	if not _boot_as(mm, sm, bm, lm, player, not ger_human):
		return {"ok": false}
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("T3 declare failed human=%s" % str(ger_human))
		return {"ok": false}
	var fx: Dictionary = _three_ger_fixture(mm)
	if int(fx.get("p", 0)) <= 0:
		fx = _threat_radius_fixture(mm)
		if int(fx.get("p", 0)) <= 0:
			_fail("T3 no POL hex facing 2+ GER neighbors")
			return {"ok": false}
	var p_pid := int(fx["p"])
	var gids: Array[int] = []
	for k in ["g1", "g2", "g3"]:
		if int(fx.get(k, 0)) > 0:
			gids.append(int(fx[k]))
	if gids.size() < 2:
		_fail("T3 fixture GER neighbors < 2")
		return {"ok": false}
	var q := _quiet_pol_pid(mm, {p_pid: true})
	if q <= 0:
		_fail("T3 no quiet POL spare")
		return {"ok": false}
	_vacate_tag_at(lm, "POL", p_pid, q)
	_make_garr(lm, "sim1110ar_t3_own", "POL", p_pid, 1.0)
	_make_garr(lm, "sim1110ar_t3_s", "POL", q, 1.0)
	var keep: Array = ["sim1110ar_t3_own", "sim1110ar_t3_s"]
	var ger_set: Dictionary = {}
	for i in range(gids.size()):
		var fid := "sim1110ar_t3_g%d" % i
		_boot.make_division(fid, "GER", gids[i])
		keep.append(fid)
		ger_set[gids[i]] = true
	_keep_only_formations(lm, keep)
	_occupy_pol_holes_except(mm, lm, ger_set, {p_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	var start_n := _tag_count_at(lm, "POL", p_pid)
	var max_n := start_n
	var reinforced := false
	var threat := float(bm.call("_ai_local_threat", p_pid, "POL"))
	for d in range(DAYS_T3):
		tm.set("total_days_elapsed", d)
		bm.call("try_ai_cover_threatened_borders")
		var n := _tag_count_at(lm, "POL", p_pid)
		if n > max_n:
			max_n = n
		var s_at := _station_of(lm, "sim1110ar_t3_s")
		var s_md := _march_dest("sim1110ar_t3_s")
		if s_at == p_pid or s_md == p_pid or n > start_n:
			reinforced = true
	var _unused_t3 := sm
	return {
		"ok": true,
		"start_n": start_n,
		"end_n": _tag_count_at(lm, "POL", p_pid),
		"max_n": max_n,
		"reinforced": reinforced,
		"threat": threat,
	}


func _run_stack_fixture(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, two_on_one: bool, _unused: bool) -> Dictionary:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return {"ok": false}
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("stack fixture declare failed")
		return {"ok": false}
	var fx: Dictionary = _threat_radius_fixture(mm)
	if int(fx.get("p", 0)) <= 0:
		_fail("no P with two GER-owned neighbors")
		return {"ok": false}
	var p_pid := int(fx["p"])
	var g1 := int(fx["g1"])
	var g2 := int(fx["g2"])
	var q := _quiet_pol_pid(mm, {p_pid: true})
	if q <= 0:
		_fail("no quiet POL spare")
		return {"ok": false}
	_vacate_tag_at(lm, "POL", p_pid, q)
	_make_garr(lm, "sim1110ar_own", "POL", p_pid, 1.5)
	_make_garr(lm, "sim1110ar_s", "POL", q, 1.0)
	var keep: Array = ["sim1110ar_own", "sim1110ar_s", "sim1110ar_e1", "sim1110ar_e2"]
	if two_on_one:
		_boot.make_division("sim1110ar_e1", "GER", g1)
		_boot.make_division("sim1110ar_e2", "GER", g1)
		_occupy_pol_holes_except(mm, lm, {g1: true}, {p_pid: true})
	else:
		_boot.make_division("sim1110ar_e1", "GER", g1)
		_boot.make_division("sim1110ar_e2", "GER", g2)
		_occupy_pol_holes_except(mm, lm, {g1: true, g2: true}, {p_pid: true})
	_keep_only_formations(lm, keep)
	if two_on_one:
		_occupy_pol_holes_except(mm, lm, {g1: true}, {p_pid: true})
	else:
		_occupy_pol_holes_except(mm, lm, {g1: true, g2: true}, {p_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	var threat := float(bm.call("_ai_local_threat", p_pid, "POL"))
	var own_p := float(bm.call("_ai_hex_power", p_pid, "POL", "defend"))
	var max_stack := float(bm.call("_ai_max_adjacent_enemy_stack_power", p_pid, "POL"))
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var s_at := _station_of(lm, "sim1110ar_s")
	var s_md := _march_dest("sim1110ar_s")
	var _unused_sm := sm
	return {
		"ok": true,
		"p": p_pid,
		"threat": threat,
		"own": own_p,
		"max_stack": max_stack,
		"s_at": s_at,
		"s_md": s_md,
		"reinforced": s_at == p_pid or s_md == p_pid,
	}


func _boot_as(mm: Node, sm: Node, bm: Node, lm: Node, player: String, observer: bool = false) -> bool:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	if lm != null and "_garrisons_1936_seeded" in lm:
		lm._garrisons_1936_seeded = false
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
		if "_empty_hex_siege" in bm:
			bm._empty_hex_siege = {}
		if bm.has_method("reset_ai_war1_for_test"):
			bm.reset_ai_war1_for_test()
	if not _boot.boot(mm, sm, player):
		_fail("boot %s failed" % player)
		return false
	if _cap != null:
		_cap.apply_economy_factories_to_map()
		_cap.reset_for_test()
	_war.reset_for_test()
	_war.clear_rule_overrides()
	if _end != null:
		_end.call("reset_for_test")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", player)
	var sp := get_root().get_node_or_null("SessionPlayers")
	if sp != null:
		if observer and sp.has_method("setup_observer_play"):
			sp.call("setup_observer_play", player)
		elif sp.has_method("setup_solo_play"):
			sp.call("setup_solo_play", player)
	return true


func _ctrl_md5(mm: Node) -> String:
	var ids: Array[int] = []
	var provs: Variant = mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else {}
	if provs is Dictionary:
		for pid_v in (provs as Dictionary).keys():
			ids.append(int(pid_v))
	ids.sort()
	var parts: PackedStringArray = PackedStringArray()
	for pid in ids:
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		var o := str(p.get("owner_tag")).strip_edges().to_upper()
		var c := str(p.get("controller_tag")).strip_edges().to_upper()
		parts.append("%d:%s:%s" % [pid, o, c])
	return ",".join(parts).md5_text()


func _func_body(src: String, name: String) -> String:
	var needle := "func %s" % name
	var i := src.find(needle)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 1)
	if j < 0:
		j = src.length()
	return src.substr(i, j - i)


func _owner(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _first_own_land_neighbor(mm: Node, pid: int, tag: String) -> int:
	if pid <= 0:
		return -1
	var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
	for nid_v in nbrs:
		var nid := int(nid_v)
		if nid == pid or nid <= 0:
			continue
		var p: Object = mm.call("get_province", nid)
		if p == null or bool(p.get("is_sea")):
			continue
		var ot := str(p.get("controller_tag")).strip_edges().to_upper()
		if ot.is_empty():
			ot = str(p.get("owner_tag")).strip_edges().to_upper()
		if ot == tag:
			return nid
	return -1


func _border_pair(mm: Node, ger: String, pol: String) -> Array[int]:
	var owned: Array = mm.call("get_provinces_by_owner", ger)
	var ids: Array[int] = []
	for pid_v in owned:
		ids.append(int(pid_v))
	ids.sort()
	for pid in ids:
		var p0: Object = mm.call("get_province", pid)
		if p0 == null or bool(p0.get("is_sea")):
			continue
		var pol_n := _first_own_land_neighbor(mm, pid, pol)
		if pol_n > 0:
			return [pid, pol_n] as Array[int]
	return [] as Array[int]


func _vacate_tag_at(lm: Node, tag: String, pid: int, dest: int) -> void:
	if dest <= 0 or dest == pid:
		return
	for f in lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		if int(f.stationed_province_id) != pid:
			continue
		f.stationed_province_id = dest


func _make_garr(lm: Node, fid: String, tag: String, pid: int, strength: float) -> void:
	_boot.make_division(fid, tag, pid)
	var f: Object = lm.call("get_formation", fid) if lm.has_method("get_formation") else null
	if f == null:
		return
	f.set("strength", strength)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set_meta("garrison_1936", true)


func _formation_movement_script() -> GDScript:
	return load("res://scripts/formations/FormationMovement.gd") as GDScript


func _march_dest(fid: String) -> int:
	var gds := _formation_movement_script()
	if gds == null:
		return -1
	var row_v: Variant = gds.call("get_march", fid)
	if typeof(row_v) != TYPE_DICTIONARY:
		return -1
	var row: Dictionary = row_v
	if row.is_empty():
		return -1
	return int(row.get("dest_id", -1))


func _station_of(lm: Node, fid: String) -> int:
	var f: Object = lm.call("get_formation", fid) if lm.has_method("get_formation") else null
	if f == null:
		return -1
	return int(f.get("stationed_province_id"))


func _tag_count_at(lm: Node, tag: String, pid: int) -> int:
	var n := 0
	for f in lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		if int(f.get("stationed_province_id")) == pid:
			n += 1
	return n


func _touches_foreign(mm: Node, pid: int, tag: String) -> bool:
	var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
	for nid_v in nbrs:
		var np: Object = mm.call("get_province", int(nid_v))
		if np == null or bool(np.get("is_sea")):
			continue
		var ot := str(np.get("controller_tag")).strip_edges().to_upper()
		if ot.is_empty():
			ot = str(np.get("owner_tag")).strip_edges().to_upper()
		if not ot.is_empty() and ot != tag:
			return true
	return false


func _quiet_pol_pid(mm: Node, skip: Dictionary) -> int:
	var owned: Array = mm.call("get_provinces_by_owner", "POL")
	var ids: Array[int] = []
	for pid_v in owned:
		ids.append(int(pid_v))
	ids.sort()
	for pid in ids:
		if bool(skip.get(pid, false)):
			continue
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		if _touches_foreign(mm, pid, "POL"):
			continue
		return pid
	return -1


func _keep_only_formations(lm: Node, fids: Array) -> void:
	if lm == null or not ("formations" in lm) or not (lm.formations is Dictionary):
		return
	var keep: Dictionary = {}
	for fid_v in fids:
		keep[str(fid_v)] = true
	var drop: Array[String] = []
	for fid_v2 in (lm.formations as Dictionary).keys():
		var fid := str(fid_v2)
		if not keep.has(fid):
			drop.append(fid)
	for fid2 in drop:
		(lm.formations as Dictionary).erase(fid2)
	_clear_marches()


func _clear_marches() -> void:
	var gds := _formation_movement_script()
	if gds == null:
		return
	var rows_v: Variant = gds.call("list_marches")
	if typeof(rows_v) != TYPE_ARRAY:
		return
	for row_v in rows_v as Array:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var fid := str((row_v as Dictionary).get("formation_id", ""))
		if fid.is_empty():
			continue
		gds.call("clear_march", fid)


func _occupy_pol_holes_except(mm: Node, lm: Node, ger_stations: Dictionary, keep: Dictionary) -> void:
	var seen: Dictionary = {}
	for epid_v in ger_stations.keys():
		var epid := int(epid_v)
		var nbrs: Array = mm.call("get_adjacent_provinces", epid, true)
		for nid_v in nbrs:
			var nid := int(nid_v)
			if nid <= 0 or seen.has(nid) or bool(keep.get(nid, false)):
				continue
			var p: Object = mm.call("get_province", nid)
			if p == null or bool(p.get("is_sea")):
				continue
			if str(p.get("owner_tag")).strip_edges().to_upper() != "POL":
				continue
			seen[nid] = true
			if _tag_count_at(lm, "POL", nid) > 0:
				continue
			_boot.make_division("sim1110ar_fill_%d_a" % nid, "POL", nid)
			_boot.make_division("sim1110ar_fill_%d_b" % nid, "POL", nid)
			_boot.make_division("sim1110ar_fill_%d_c" % nid, "POL", nid)


func _threat_radius_fixture(mm: Node) -> Dictionary:
	var owned: Array = mm.call("get_provinces_by_owner", "POL")
	var ids: Array[int] = []
	for pid_v in owned:
		ids.append(int(pid_v))
	ids.sort()
	for pid in ids:
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		var ger_n: Array[int] = []
		var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
		for nid_v in nbrs:
			var nid := int(nid_v)
			var np: Object = mm.call("get_province", nid)
			if np == null or bool(np.get("is_sea")):
				continue
			if str(np.get("owner_tag")).strip_edges().to_upper() == "GER":
				ger_n.append(nid)
		if ger_n.size() < 2:
			continue
		ger_n.sort()
		var g3 := -1
		if ger_n.size() > 2:
			g3 = ger_n[2]
		return {"p": pid, "g1": ger_n[0], "g2": ger_n[1], "g3": g3}
	return {}


func _three_ger_fixture(mm: Node) -> Dictionary:
	var owned: Array = mm.call("get_provinces_by_owner", "POL")
	var ids: Array[int] = []
	for pid_v in owned:
		ids.append(int(pid_v))
	ids.sort()
	for pid in ids:
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		var ger_n: Array[int] = []
		var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
		for nid_v in nbrs:
			var nid := int(nid_v)
			var np: Object = mm.call("get_province", nid)
			if np == null or bool(np.get("is_sea")):
				continue
			if str(np.get("owner_tag")).strip_edges().to_upper() == "GER":
				ger_n.append(nid)
		if ger_n.size() < 3:
			continue
		ger_n.sort()
		return {"p": pid, "g1": ger_n[0], "g2": ger_n[1], "g3": ger_n[2]}
	return {}
