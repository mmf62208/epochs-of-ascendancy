extends SceneTree

## SIM-1110-A: defender stacking, AI threatened-sector shift, offensive ramp.
## (a) 3-unit hex opens with def_n=3
## (b) retreating unit onto an attacked hex joins the defence
## (c) AI GER vs AI POL: by war day 5 Gliwicki and Bytomski each hold >=2
##     garrisons sourced from non-enemy-touching stations (see checkpoint comment)
## (d) Germany's French border keeps >= ceil(18*0.5)=9 garrisons
## (e) human GER: 0 cover/reinforce of GER in 30 days; stations only change via retreat
## (f) AI GER: 0 new Polish-land captures before war day 21, <=3 by day 60
## (g) 0 SCRIPT ERROR

const SRC_BM := "res://scripts/combat/BattleManager.gd"
const GLIWICKI := 711058
const BYTOMSKI := 711057
const HUMAN_DAYS := 30
const RAMP_HOLD_CHECK_DAY := 20
const RAMP_D60 := 60

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
	print("  [FAIL] HeadlessSim1110aDefenceTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSim1110aDefenceTest: ", msg)


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
	_assert_source()
	_test_a_defender_stack(mm, sm, bm, lm)
	_test_b_retreat_join(mm, sm, bm, lm)
	_test_cdf_aivai(mm, sm, bm, tm, lm)
	_test_e_human_ger(mm, sm, bm, tm, lm)
	_test_h_captured_no_raise(mm, sm, bm, tm, lm)
	_test_i_raise_cap(mm, sm, bm, tm, lm)
	_test_j_hop_cache(mm, sm, bm, tm, lm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessSim1110aDefenceTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSim1110aDefenceTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _assert_source() -> void:
	var bm_src := FileAccess.get_file_as_string(SRC_BM)
	if "const DEF_STACK_MAX := 3" not in bm_src:
		_fail("mutant: DEF_STACK_MAX missing")
		return
	if "func _join_defence_if_attacked" not in bm_src:
		_fail("mutant: _join_defence_if_attacked missing")
		return
	if "func _ai_reinforce_threatened_sectors" not in bm_src:
		_fail("mutant: _ai_reinforce_threatened_sectors missing")
		return
	if "func _ai_offensive_ramp_ok" not in bm_src:
		_fail("mutant: _ai_offensive_ramp_ok missing")
		return
	if "GARRISON_REINFORCE" not in bm_src:
		_fail("mutant: GARRISON_REINFORCE print missing")
		return
	if "last_new_capture_day" not in bm_src:
		_fail("mutant: last_new_capture_day missing")
		return
	if "_is_player_or_human_nation(tag):" not in bm_src:
		_fail("mutant: B0 human skip missing")
		return
	if "func _ai_is_war_captured" not in bm_src:
		_fail("mutant: _ai_is_war_captured missing")
		return
	if "const RAISE_WAR_BUDGET_FRAC := 0.10" not in bm_src:
		_fail("mutant: RAISE_WAR_BUDGET_FRAC missing")
		return
	if "const RAISE_MIN_GAP_DAYS := 7" not in bm_src:
		_fail("mutant: RAISE_MIN_GAP_DAYS missing")
		return
	if "AI_HOP_CACHE day=" not in bm_src:
		_fail("mutant: AI_HOP_CACHE print missing")
		return
	if "captured_pids" not in bm_src:
		_fail("mutant: captured_pids missing")
		return
	_pass("source mutants killed")


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


func _test_a_defender_stack(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(a) declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(a) no GER-POL border")
		return
	var ger_pid := int(pair[0])
	var pol_pid := int(pair[1])
	_boot.make_division("sim1110a_def1", "GER", ger_pid)
	_boot.make_division("sim1110a_def2", "GER", ger_pid)
	_boot.make_division("sim1110a_def3", "GER", ger_pid)
	_boot.make_division("sim1110a_att", "POL", pol_pid)
	var opened: Dictionary = bm.call("start_land_battle", "POL", ger_pid, pol_pid, "sim1110a_att")
	if not bool(opened.get("opened", false)):
		_fail("(a) battle did not open %s" % str(opened))
		return
	var battle: Dictionary = opened.get("battle", {}) as Dictionary
	var def_n := int(battle.get("def_n", 0))
	var def_fids: Array = battle.get("def_fids", []) as Array
	print("SIM1110A_A def_n=%d def_fids=%s" % [def_n, str(def_fids)])
	if def_n != 3:
		_fail("(a) def_n want 3 got %d battle=%s" % [def_n, str(battle.keys())])
		return
	if def_fids.size() != 3:
		_fail("(a) def_fids size want 3 got %d" % def_fids.size())
		return
	_pass("(a) 3-unit hex opened with def_n=3")


func _test_b_retreat_join(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(b) declare GER-POL failed")
		return
	var fx: Array[int] = _retreat_join_fixture(mm)
	if fx.size() < 3:
		_fail("(b) no A/B/C fixture (captured/battle/staging)")
		return
	var pid_a := fx[0]
	var pid_b := fx[1]
	var pid_c := fx[2]
	_boot.make_division("sim1110a_ret", "GER", pid_a)
	_boot.make_division("sim1110a_hold", "GER", pid_b)
	_boot.make_division("sim1110a_polb", "POL", pid_c)
	var opened: Dictionary = bm.call("start_land_battle", "POL", pid_b, pid_c, "sim1110a_polb")
	if not bool(opened.get("opened", false)):
		_fail("(b) battle on B did not open %s A=%d B=%d C=%d" % [str(opened), pid_a, pid_b, pid_c])
		return
	var before_n := int((opened.get("battle", {}) as Dictionary).get("def_n", 0))
	bm.call("_apply_attacker_win_capture_light", "POL", pid_a, pid_c, "")
	var live: Dictionary = bm.call("get_land_battle_at", pid_b)
	var after_n := int(live.get("def_n", 0))
	var def_fids: Array = live.get("def_fids", []) as Array
	var ret_f: Object = lm.call("get_formation", "sim1110a_ret") if lm.has_method("get_formation") else null
	var ret_station := int(ret_f.get("stationed_province_id")) if ret_f != null else -1
	print(
		"SIM1110A_B A=%d B=%d C=%d before_n=%d after_n=%d ret_station=%d fids=%s"
		% [pid_a, pid_b, pid_c, before_n, after_n, ret_station, str(def_fids)]
	)
	if ret_station != pid_b:
		_fail("(b) retreat did not land on attacked hex (station=%d want %d)" % [ret_station, pid_b])
		return
	if not def_fids.has("sim1110a_ret"):
		_fail("(b) retreated fid not in def_fids %s" % str(def_fids))
		return
	if after_n < 2:
		_fail("(b) def_n after retreat want >=2 got %d" % after_n)
		return
	_pass("(b) retreating unit joined defence def_n=%d" % after_n)


func _test_cdf_aivai(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("seed_1936_start_garrisons missing")
		return
	var seeded: Dictionary = lm.call("seed_1936_start_garrisons", true)
	print("SIM1110A_SEED placed=%s" % str(seeded.get("placed", -1)))
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(c) declare GER-POL failed")
		return
	var start_pol: Dictionary = _owned_set(mm, "POL")
	var start_ger: Dictionary = _owned_set(mm, "GER")
	var start_stations: Dictionary = _ger_stations(lm)
	var enemy_touch: Dictionary = {}
	for fid in start_stations.keys():
		var sid := int(start_stations[fid])
		if bool(bm.call("_station_touches_enemy", sid, "GER")):
			enemy_touch[fid] = sid
	var d4_ok := false
	var new_caps_d20 := -1
	for day in range(1, RAMP_D60 + 1):
		tm.call("advance_live_f5_equivalent_days", 1)
		# Case (c) asserts on war day 5, not day 4: THREAT_RATIO 1.2 means a 1v1
		# border is not a threat. Gliwicki only reaches ratio 2.0 after Poland
		# masses on Opolski. Observed: d4 gliwicki=1 bytomski=2, d5 both 2.
		if day == 4:
			print(
				"SIM1110A_C day4 gliwicki=%d bytomski=%d"
				% [_garrison_fids_at(lm, "GER", GLIWICKI).size(), _garrison_fids_at(lm, "GER", BYTOMSKI).size()]
			)
		if day == 5:
			d4_ok = _assert_c_d(mm, bm, lm, start_stations, enemy_touch)
		if day == 14 or day == 21 or day == 30 or day == 60:
			var ger_lost := 0
			for pid_v in start_ger.keys():
				if _owner(mm, int(pid_v)) != "GER":
					ger_lost += 1
			print(
				"SIM1110A_AB d%d ger_net_lost=%d pol_divs=%d pol_garr=%d"
				% [day, ger_lost, _div_n(lm, "POL"), _garrison_n(lm, "POL")]
			)
		if day == RAMP_HOLD_CHECK_DAY:
			new_caps_d20 = _new_polish_captures(mm, start_pol)
			print("SIM1110A_F d20 new_pol_caps=%d" % new_caps_d20)
	var new_caps_d60 := _new_polish_captures(mm, start_pol)
	print("SIM1110A_F d60 new_pol_caps=%d" % new_caps_d60)
	if not d4_ok:
		return
	if new_caps_d20 < 0:
		_fail("(f) missed d20 checkpoint")
		return
	if new_caps_d20 != 0:
		_fail("(f) AI GER new Polish captures before war day 21: %d" % new_caps_d20)
		return
	if new_caps_d60 > 3:
		_fail("(f) AI GER new Polish captures by d60 want <=3 got %d" % new_caps_d60)
		return
	_pass("(f) B2: 0 new POL-land captures by d20, %d by d60" % new_caps_d60)


func _assert_c_d(
	mm: Node,
	bm: Node,
	lm: Node,
	start_stations: Dictionary,
	enemy_touch: Dictionary,
) -> bool:
	var gli := _garrison_fids_at(lm, "GER", GLIWICKI)
	var byt := _garrison_fids_at(lm, "GER", BYTOMSKI)
	print("SIM1110A_C day5 gliwicki=%d bytomski=%d gli=%s byt=%s" % [gli.size(), byt.size(), str(gli), str(byt)])
	var c_ok := true
	if gli.size() < 2:
		_fail("(c) Gliwicki garrisons want >=2 got %d owner=%s" % [gli.size(), _owner(mm, GLIWICKI)])
		c_ok = false
	if byt.size() < 2:
		_fail("(c) Bytomski garrisons want >=2 got %d owner=%s" % [byt.size(), _owner(mm, BYTOMSKI)])
		c_ok = false
	if c_ok:
		for fid in gli:
			if start_stations.has(fid) and int(start_stations[fid]) == GLIWICKI:
				continue
			var origin := int(start_stations.get(fid, -1))
			if origin > 0 and enemy_touch.has(fid):
				_fail("(c) Gliwicki extra %s came from enemy-touching %d" % [fid, origin])
				c_ok = false
				break
		for fid2 in byt:
			if start_stations.has(fid2) and int(start_stations[fid2]) == BYTOMSKI:
				continue
			var origin2 := int(start_stations.get(fid2, -1))
			if origin2 > 0 and enemy_touch.has(fid2):
				_fail("(c) Bytomski extra %s came from enemy-touching %d" % [fid2, origin2])
				c_ok = false
				break
	if c_ok:
		_pass("(c) Gliwicki and Bytomski each hold >=2 from quiet stations")
	var fra_hexes: Array[int] = _hexes_facing(mm, "GER", "FRA")
	var fra_garr := _garrison_count_on(lm, "GER", fra_hexes)
	var keep := int(ceil(18.0 * 0.5))
	print("SIM1110A_D fra_hexes=%d fra_garrisons=%d keep=%d" % [fra_hexes.size(), fra_garr, keep])
	var d_ok := true
	if fra_garr < keep:
		_fail("(d) French border garrisons want >=%d got %d on %d hexes" % [keep, fra_garr, fra_hexes.size()])
		d_ok = false
	else:
		_pass("(d) French border kept %d garrisons (>=%d)" % [fra_garr, keep])
	var _unused := bm
	return c_ok and d_ok


func _test_e_human_ger(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "GER", false):
		return
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("(e) seed missing")
		return
	lm.call("seed_1936_start_garrisons", true)
	print("SIM1110A_E_START")
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(e) declare GER-POL failed")
		return
	var prev_stations: Dictionary = _all_ger_stations(lm)
	var start_fids: Dictionary = prev_stations.duplicate()
	var moved_illegal := 0
	var raised := 0
	var seen_raised: Dictionary = {}
	for day in range(1, HUMAN_DAYS + 1):
		tm.call("advance_live_f5_equivalent_days", 1)
		var now_stations: Dictionary = _all_ger_stations(lm)
		for fid_v in now_stations.keys():
			var fid := str(fid_v)
			if not start_fids.has(fid):
				if seen_raised.has(fid):
					continue
				seen_raised[fid] = true
				var nf = lm.call("get_formation", fid) if lm.has_method("get_formation") else null
				if nf != null and (bool(nf.get_meta("garrison_1936", false)) or fid.begins_with("garr1936_GER") or fid.begins_with("capdef_GER")):
					raised += 1
					print("SIM1110A_E raised %s @ %s day=%d" % [fid, str(now_stations[fid]), day])
				continue
			if not prev_stations.has(fid):
				continue
			var old_sid := int(prev_stations[fid])
			var sid := int(now_stations[fid])
			if old_sid == sid:
				continue
			# Capture retreat: origin is no longer GER-controlled after this day.
			if _ctrl(mm, old_sid) != "GER":
				continue
			moved_illegal += 1
			print("SIM1110A_E illegal_move %s %d -> %d day=%d" % [fid, old_sid, sid, day])
		prev_stations = now_stations
	print("SIM1110A_E illegal_moves=%d raised=%d" % [moved_illegal, raised])
	print("SIM1110A_E_END")
	if moved_illegal > 0 or raised > 0:
		_fail("(e) human GER station changes besides capture retreat (moved=%d raised=%d)" % [moved_illegal, raised])
		return
	_pass("(e) human GER: no cover/reinforce/raise in %d days" % HUMAN_DAYS)
	var _unused_bm := bm


func _test_h_captured_no_raise(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bm.has_method("_ai_is_war_captured"):
		_fail("(h) _ai_is_war_captured missing")
		return
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("(h) seed missing")
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(h) declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(h) no GER-POL border")
		return
	var ger_pid := int(pair[0])
	var pol_pid := int(pair[1])
	var ger_from := _first_own_land_neighbor(mm, ger_pid, "GER")
	if ger_from <= 0:
		ger_from = ger_pid
	var before_fids: Dictionary = _garrison_fid_set(lm, "POL")
	bm.call("_apply_attacker_win_capture_light", "POL", ger_pid, pol_pid, "")
	if _owner(mm, ger_pid) != "POL":
		_fail("(h) capture did not flip owner pid=%d owner=%s" % [ger_pid, _owner(mm, ger_pid)])
		return
	_vacate_tag_at(lm, "POL", ger_pid, pol_pid)
	if not bool(bm.call("_ai_is_war_captured", "POL", ger_pid)):
		_fail("(h) captured pid %d not in POL captured_pids" % ger_pid)
		return
	var caps := _captured_pids_for("POL", "GER")
	if not caps.has(ger_pid):
		_fail("(h) war row captured_pids missing %d got %s" % [ger_pid, str(caps.keys())])
		return
	var gd := get_root().get_node_or_null("GameData")
	if gd == null:
		_fail("(h) GameData missing")
		return
	var saved: Dictionary = gd.call("get_save_data")
	var saved_cw_v: Variant = saved.get("campaign_wars", {})
	if not (saved_cw_v is Dictionary):
		_fail("(h) get_save_data missing campaign_wars")
		return
	var saved_cw: Dictionary = (saved_cw_v as Dictionary).duplicate(true)
	var wars_live: Dictionary = ((gd.peace_state.get("campaign_wars", {}) as Dictionary).get("wars", {}) as Dictionary)
	var key := "GER|POL"
	if wars_live.has(key):
		var row_wipe: Dictionary = wars_live[key] as Dictionary
		row_wipe["captured_pids"] = {}
		wars_live[key] = row_wipe
	gd.call("apply_save_data", {"campaign_wars": saved_cw})
	if not bool(bm.call("_ai_is_war_captured", "POL", ger_pid)):
		_fail("(h) captured list did not survive save/load")
		return
	_pass("(h) captured list survived save/load pid=%d" % ger_pid)
	bm.call("try_ai_cover_threatened_borders")
	var after_fids: Dictionary = _garrison_fid_set(lm, "POL")
	var raised_on_cap := 0
	for fid_v in after_fids.keys():
		if before_fids.has(fid_v):
			continue
		var f: Object = lm.call("get_formation", str(fid_v)) if lm.has_method("get_formation") else null
		if f == null:
			continue
		if int(f.get("stationed_province_id")) == ger_pid:
			raised_on_cap += 1
	print("SIM1110A_H pid=%d raised_on_captured=%d pol_garr=%d" % [ger_pid, raised_on_cap, after_fids.size()])
	if raised_on_cap > 0:
		_fail("(h) raised %d new garrisons on captured pid %d" % [raised_on_cap, ger_pid])
		return
	bm.call("_apply_attacker_win_capture_light", "GER", ger_pid, ger_from, "")
	if bool(bm.call("_ai_is_war_captured", "POL", ger_pid)):
		_fail("(h) captured pid %d still listed after GER retake" % ger_pid)
		return
	_pass("(h) retake cleared captured pid")
	bm.call("_apply_attacker_win_capture_light", "POL", ger_pid, pol_pid, "")
	if not bool(bm.call("_ai_is_war_captured", "POL", ger_pid)):
		_fail("(h) recapture did not re-list pid")
		return
	_war.make_peace("GER", "POL", "test")
	if bool(bm.call("_ai_is_war_captured", "POL", ger_pid)):
		_fail("(h) captured list survived peace")
		return
	_pass("(h) 0 raises on war-captured land; list clears on retake and peace")
	var _unused_h := [sm, tm]


func _test_i_raise_cap(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bm.has_method("_ai_raise_budget"):
		_fail("(i) _ai_raise_budget missing")
		return
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("(i) seed missing")
		return
	lm.call("seed_1936_start_garrisons", true)
	var seed_n := int(bm.call("_ai_garrison_seed_n", "POL"))
	var budget := int(bm.call("_ai_raise_budget", "POL"))
	var want := mini(10, maxi(1, int(ceil(float(seed_n) * 0.10))))
	print("SIM1110A_I seed_n=%d budget=%d want=%d" % [seed_n, budget, want])
	if budget != want:
		_fail("(i) budget %d != clampi(ceil(seed_n*0.10),1,10)=%d seed_n=%d" % [budget, want, seed_n])
		return
	if seed_n == 33 and budget != 4:
		_fail("(i) POL 33 seed should budget 4 got %d" % budget)
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(i) declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(i) no GER-POL border")
		return
	var ger_pid := int(pair[0])
	var pol_pid := int(pair[1])
	var dest := _ger_facing_pol_pid(mm, pol_pid)
	if dest <= 0:
		_fail("(i) no POL dest to park vacated units")
		return
	_boot.make_division("sim1110a_i_ger", "GER", ger_pid)
	var kept := false
	for f in lm.call("get_formations_for_country", "POL"):
		if f == null or not bool(f.get_meta("garrison_1936", false)):
			continue
		if not kept:
			f.stationed_province_id = dest
			kept = true
			continue
		f.set_meta("garrison_1936", false)
	if not kept:
		_fail("(i) POL had no garrison_1936 to keep cover active")
		return
	_keep_one_pol_garrison_1936(lm, dest)
	_vacate_tag_at(lm, "POL", pol_pid, dest)
	var start_n := _garrison_n(lm, "POL")
	var raise_days: Array[int] = []
	for day in range(0, 30):
		tm.set("total_days_elapsed", day)
		_vacate_tag_at(lm, "POL", pol_pid, dest)
		_keep_one_pol_garrison_1936(lm, dest)
		var n_before := _garrison_n(lm, "POL")
		var cov: Dictionary = bm.call("try_ai_cover_threatened_borders")
		var now_n := _garrison_n(lm, "POL")
		if day < 3 or int(cov.get("raised", 0)) > 0:
			print(
				"SIM1110A_I day=%d raised=%s moved=%s pol_n=%d owner=%s"
				% [day, str(cov.get("raised", -1)), str(cov.get("moved", -1)), now_n, _owner(mm, pol_pid)]
			)
		if now_n > n_before:
			raise_days.append(day)
	var row: Dictionary = bm.call("_ai_war_row", "POL", "GER")
	var raises_map: Dictionary = row.get("raises_by_tag", {}) as Dictionary
	var charged := int(raises_map.get("POL", 0))
	print("SIM1110A_I raises_days=%s charged=%d start_n=%d now=%d" % [str(raise_days), charged, start_n, _garrison_n(lm, "POL")])
	if charged < 1 and raise_days.is_empty():
		_fail("(i) no POL raises observed; cap test did not bite")
		return
	if charged > budget:
		_fail("(i) POL raises %d > budget %d" % [charged, budget])
		return
	if raise_days.size() > budget:
		_fail("(i) observed %d POL raises > budget %d" % [raise_days.size(), budget])
		return
	for i in range(1, raise_days.size()):
		if int(raise_days[i]) - int(raise_days[i - 1]) < 7:
			_fail("(i) raise gap %d days < 7 (%s)" % [int(raise_days[i]) - int(raise_days[i - 1]), str(raise_days)])
			return
	_pass("(i) POL raises <= %d with >=7 day gap (charged=%d days=%s)" % [budget, charged, str(raise_days)])
	var _unused_i := sm


func _test_j_hop_cache(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bm.has_method("ai_hop_cache_counts") or not bm.has_method("reset_ai_hop_cache_counts"):
		_fail("(j) hop cache counters missing")
		return
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("(j) seed missing")
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(j) declare GER-POL failed")
		return
	bm.call("_ai_hops_from", "GER", GLIWICKI)
	bm.call("_ai_hexes_facing_tag", "GER", "FRA")
	bm.call("reset_ai_hop_cache_counts")
	bm.call("_ai_hops_from", "GER", GLIWICKI)
	bm.call("_ai_hexes_facing_tag", "GER", "FRA")
	var quiet: Dictionary = bm.call("ai_hop_cache_counts")
	print("SIM1110A_J quiet adj=%s hops=%s facing=%s" % [str(quiet.get("adj", -1)), str(quiet.get("hops", -1)), str(quiet.get("facing", -1))])
	if int(quiet.get("adj", -1)) != 0 or int(quiet.get("hops", -1)) != 0 or int(quiet.get("facing", -1)) != 0:
		_fail("(j) rebuilds on a no-event day adj=%s hops=%s facing=%s" % [str(quiet.get("adj")), str(quiet.get("hops")), str(quiet.get("facing"))])
		return
	bm.call("bump_ai_board_epoch")
	bm.call("_ai_hops_from", "GER", GLIWICKI)
	bm.call("_ai_hexes_facing_tag", "GER", "FRA")
	var after: Dictionary = bm.call("ai_hop_cache_counts")
	print("SIM1110A_J after_epoch adj=%s hops=%s facing=%s" % [str(after.get("adj", -1)), str(after.get("hops", -1)), str(after.get("facing", -1))])
	if int(after.get("adj", 0)) + int(after.get("hops", 0)) + int(after.get("facing", 0)) <= 0:
		_fail("(j) no rebuild after epoch bump")
		return
	_pass("(j) hop cache quiet on no-event day; rebuilds after epoch")
	var _unused_j := [sm, tm]


func _retreat_join_fixture(mm: Node) -> Array[int]:
	var owned: Array = mm.call("get_provinces_by_owner", "GER")
	var ids: Array[int] = []
	for pid_v in owned:
		ids.append(int(pid_v))
	ids.sort()
	for pid in ids:
		var b := _first_own_land_neighbor(mm, pid, "GER")
		if b <= 0:
			continue
		var c := _first_own_land_neighbor(mm, b, "POL")
		if c <= 0:
			continue
		return [pid, b, c] as Array[int]
	return [] as Array[int]


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


func _owned_set(mm: Node, tag: String) -> Dictionary:
	var out: Dictionary = {}
	for pid_v in mm.call("get_provinces_by_owner", tag):
		out[int(pid_v)] = true
	return out


func _new_polish_captures(mm: Node, start_pol: Dictionary) -> int:
	var n := 0
	for pid_v in start_pol.keys():
		var pid := int(pid_v)
		if _owner(mm, pid) == "GER":
			n += 1
	return n


func _ger_stations(lm: Node) -> Dictionary:
	var out: Dictionary = {}
	for f in lm.call("get_formations_for_country", "GER"):
		if f == null or not bool(f.get_meta("garrison_1936", false)):
			continue
		out[str(f.formation_id)] = int(f.stationed_province_id)
	return out


func _all_ger_stations(lm: Node) -> Dictionary:
	var out: Dictionary = {}
	for f in lm.call("get_formations_for_country", "GER"):
		if f == null:
			continue
		out[str(f.formation_id)] = int(f.stationed_province_id) if "stationed_province_id" in f else -1
	return out


func _garrison_fids_at(lm: Node, tag: String, pid: int) -> Array[String]:
	var out: Array[String] = []
	for f in lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		if not bool(f.get_meta("garrison_1936", false)):
			continue
		if int(f.stationed_province_id) != pid:
			continue
		out.append(str(f.formation_id))
	out.sort()
	return out


func _hexes_facing(mm: Node, tag: String, other: String) -> Array[int]:
	var out: Array[int] = []
	for pid_v in mm.call("get_provinces_by_owner", tag):
		var pid := int(pid_v)
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		if _first_own_land_neighbor(mm, pid, other) > 0:
			out.append(pid)
	out.sort()
	return out


func _garrison_count_on(lm: Node, tag: String, pids: Array[int]) -> int:
	var want: Dictionary = {}
	for pid in pids:
		want[pid] = true
	var n := 0
	for f in lm.call("get_formations_for_country", tag):
		if f == null or not bool(f.get_meta("garrison_1936", false)):
			continue
		if want.has(int(f.stationed_province_id)):
			n += 1
	return n


func _owner(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _ctrl(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	var c := str(p.get("controller_tag")).strip_edges().to_upper()
	if c.is_empty():
		c = str(p.get("owner_tag")).strip_edges().to_upper()
	return c


func _garrison_fid_set(lm: Node, tag: String) -> Dictionary:
	var out: Dictionary = {}
	for f in lm.call("get_formations_for_country", tag):
		if f == null or not bool(f.get_meta("garrison_1936", false)):
			continue
		out[str(f.formation_id)] = int(f.stationed_province_id)
	return out


func _garrison_n(lm: Node, tag: String) -> int:
	return _garrison_fid_set(lm, tag).size()


func _div_n(lm: Node, tag: String) -> int:
	var n := 0
	for f in lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft == "division" or ft == "garrison":
			n += 1
	return n


func _keep_one_pol_garrison_1936(lm: Node, dest: int) -> void:
	var kept := false
	for f in lm.call("get_formations_for_country", "POL"):
		if f == null or not bool(f.get_meta("garrison_1936", false)):
			continue
		if not kept:
			if dest > 0:
				f.stationed_province_id = dest
			kept = true
			continue
		f.set_meta("garrison_1936", false)


func _vacate_tag_at(lm: Node, tag: String, pid: int, dest: int) -> void:
	if dest <= 0 or dest == pid:
		return
	for f in lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		if int(f.stationed_province_id) != pid:
			continue
		f.stationed_province_id = dest


func _captured_pids_for(tag: String, other: String) -> Dictionary:
	var out: Dictionary = {}
	var gd := get_root().get_node_or_null("GameData")
	if gd == null:
		return out
	var raw: Variant = gd.peace_state.get("campaign_wars", {})
	if not (raw is Dictionary):
		return out
	var wars_v: Variant = (raw as Dictionary).get("wars", {})
	if not (wars_v is Dictionary):
		return out
	var key := "GER|POL"
	if tag > other:
		key = "%s|%s" % [other, tag]
	else:
		key = "%s|%s" % [tag, other]
	var row_v: Variant = (wars_v as Dictionary).get(key, {})
	if not (row_v is Dictionary):
		return out
	var caps_v: Variant = (row_v as Dictionary).get("captured_pids", {})
	if not (caps_v is Dictionary):
		return out
	var arr_v: Variant = (caps_v as Dictionary).get(tag, [])
	if not (arr_v is Array):
		return out
	for pid_v in arr_v:
		out[int(pid_v)] = true
	return out


func _ger_facing_pol_pid(mm: Node, skip: int) -> int:
	var owned: Array = mm.call("get_provinces_by_owner", "POL")
	var ids: Array[int] = []
	for pid_v in owned:
		ids.append(int(pid_v))
	ids.sort()
	for pid in ids:
		if pid == skip:
			continue
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		if _first_own_land_neighbor(mm, pid, "GER") > 0:
			return pid
	return _other_pol_pid(mm, skip)


func _other_pol_pid(mm: Node, skip: int) -> int:
	var owned: Array = mm.call("get_provinces_by_owner", "POL")
	var ids: Array[int] = []
	for pid_v in owned:
		ids.append(int(pid_v))
	ids.sort()
	for pid in ids:
		if pid == skip:
			continue
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		if _first_own_land_neighbor(mm, pid, "GER") > 0:
			continue
		return pid
	for pid2 in ids:
		if pid2 != skip:
			return pid2
	return -1
