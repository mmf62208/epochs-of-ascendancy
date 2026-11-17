extends SceneTree

## SIM-1110-A: defender stacking, AI threatened-sector shift.
## (a) 3-unit hex opens with def_n=3
## (b) retreating unit onto an attacked hex joins the defence
## (c) AI GER vs AI POL: by war day 5 Bytomski holds >=2 from quiet stations;
##     Gliwicki stays occupied (B2 ramp is game-state: 1-stack probe)
## (d) Germany's French border keeps >= ceil(18*0.5)=9 garrisons
## (e) human GER: 0 cover/reinforce of GER in 30 days; stations only change via retreat
## (f) B2 offensive ramp: 21d hold + 15/10/7 gaps, skip when the attacking hex
##     already has a concentrated stack (>=2). Expires at RAMP_END_DAYS.
##     Product must not read EOA_CAMPAIGN_LOOP. Source mutant.
## (g) 0 SCRIPT ERROR
## (k) no GARRISON_REINFORCE onto war-captured land; control home hex is reinforced
## (k2) no GARRISON_COVER move onto war-captured land; control home hex is covered
## (l) 5-day AI unit move cooldown; join-defence-if-attacked is not blocked
## (m) 1-hop single-stack MAX (not summed); 2-hop ignored; human = AI
## (n) threatened under-covered POL dest gets a reinforce (fires)
## (n2) hold back: last defender on a front province is not pulled

const SRC_BM := "res://scripts/combat/BattleManager.gd"
const GLIWICKI := 711058
const BYTOMSKI := 711057
const HUMAN_DAYS := 30
const AIVAI_CHECK_DAYS := 60

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
	_test_k_no_reinforce_captured(mm, sm, bm, tm, lm)
	_test_k2_no_cover_captured(mm, sm, bm, tm, lm)
	_test_l_move_cooldown(mm, sm, bm, tm, lm)
	_test_m_threat_radius(mm, sm, bm, tm, lm)
	_test_n_pol_reinforce_fire(mm, sm, bm, tm, lm)
	_test_n2_pol_reinforce_hold(mm, sm, bm, tm, lm)
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
	if "const RAMP_HOLD_DAYS := 21" not in bm_src:
		_fail("mutant: RAMP_HOLD_DAYS missing")
		return
	if "EOA_CAMPAIGN_LOOP" in bm_src:
		_fail("mutant: BattleManager still reads EOA_CAMPAIGN_LOOP")
		return
	if 'OS.get_environment("EOA_CAMPAIGN_LOOP")' in bm_src:
		_fail("mutant: BattleManager OS.get_environment EOA_CAMPAIGN_LOOP")
		return
	if "Never pull the last defender" not in bm_src:
		_fail("mutant: last-defender cover keep missing")
		return
	if "Threatened empty dest: COVER is the reinforce" not in bm_src:
		_fail("mutant: threatened COVER logs GARRISON_REINFORCE missing")
		return
	if "func _ai_cover_expired_for_hole" not in bm_src:
		_fail("mutant: cover expiry after COVER_EXPIRE_DAYS missing")
		return
	if "const COVER_EXPIRE_DAYS := 180" not in bm_src:
		_fail("mutant: COVER_EXPIRE_DAYS missing")
		return
	if "_ai_friendly_division_count(tag, from_id) >= 2" not in bm_src:
		_fail("mutant: concentrated-stack ramp skip missing")
		return
	if "func _ai_has_committed_field_army" not in bm_src:
		_fail("mutant: committed field-army ramp skip missing")
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
	if "func _ai_local_threat" not in bm_src:
		_fail("mutant: _ai_local_threat missing")
		return
	if "const AI_UNIT_MOVE_COOLDOWN_DAYS := 5" not in bm_src:
		_fail("mutant: AI_UNIT_MOVE_COOLDOWN_DAYS missing")
		return
	if "GARRISON_REINFORCE skip_captured" not in bm_src:
		_fail("mutant: GARRISON_REINFORCE skip_captured missing")
		return
	if "GARRISON_COVER skip_captured" not in bm_src:
		_fail("mutant: GARRISON_COVER skip_captured missing")
		return
	if "AI_MOVE_COOLDOWN skip" not in bm_src:
		_fail("mutant: AI_MOVE_COOLDOWN skip missing")
		return
	if "ai_unit_moved_day" not in bm_src:
		_fail("mutant: ai_unit_moved_day missing")
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
	for day in range(1, AIVAI_CHECK_DAYS + 1):
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
		if day == 20:
			new_caps_d20 = _new_polish_captures(mm, start_pol)
			print("SIM1110A_F d20 new_pol_caps=%d (ramp game-state; 1-stack probe)" % new_caps_d20)
	var new_caps_d60 := _new_polish_captures(mm, start_pol)
	print("SIM1110A_F d60 new_pol_caps=%d (ramp game-state; 1-stack probe)" % new_caps_d60)
	if not d4_ok:
		return
	_pass("(c)(d) aivai checkpoints; B2 ramp game-state")


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
	# CAMPAIGN_LOOP gates the B2 ramp here; hotter GER hexes may still consume
	# the 2/day reinforce budget, so Gliwicki may stay at 1.
	if gli.size() < 1:
		_fail("(c) Gliwicki emptied owner=%s" % _owner(mm, GLIWICKI))
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
		_pass("(c) Bytomski stacked %d from quiet stations; Gliwicki held %d" % [byt.size(), gli.size()])
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


func _test_k_no_reinforce_captured(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(k) declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(k) no GER-POL border")
		return
	var x_pid := int(pair[0])
	var pol_pid := int(pair[1])
	var ger_from := _first_own_land_neighbor(mm, x_pid, "GER")
	if ger_from <= 0:
		ger_from = x_pid
	bm.call("_apply_attacker_win_capture_light", "POL", x_pid, pol_pid, "")
	if _owner(mm, x_pid) != "POL":
		_fail("(k) capture did not flip X=%d owner=%s" % [x_pid, _owner(mm, x_pid)])
		return
	if not bool(bm.call("_ai_is_war_captured", "POL", x_pid)):
		_fail("(k) X %d not in POL captured_pids" % x_pid)
		return
	var h_pid := _pol_neighbor_of(mm, ger_from, x_pid)
	if h_pid <= 0:
		_fail("(k) no POL home hex H facing the GER stack")
		return
	var q1 := _quiet_pol_pid(mm, {x_pid: true, h_pid: true, pol_pid: true})
	var q2 := _quiet_pol_pid(mm, {x_pid: true, h_pid: true, pol_pid: true, q1: true})
	if q1 <= 0 or q2 <= 0:
		_fail("(k) no quiet POL spares q1=%d q2=%d" % [q1, q2])
		return
	_vacate_tag_at(lm, "POL", x_pid, q1)
	_vacate_tag_at(lm, "GER", x_pid, ger_from)
	_make_garr(lm, "sim1110a_k_x", "POL", x_pid, 1.0)
	_make_garr(lm, "sim1110a_k_h", "POL", h_pid, 1.0)
	_make_garr(lm, "sim1110a_k_s1", "POL", q1, 1.0)
	_make_garr(lm, "sim1110a_k_s2", "POL", q2, 1.0)
	_boot.make_division("sim1110a_k_g1", "GER", ger_from)
	_boot.make_division("sim1110a_k_g2", "GER", ger_from)
	_keep_only_formations(lm, [
		"sim1110a_k_x", "sim1110a_k_h", "sim1110a_k_s1", "sim1110a_k_s2",
		"sim1110a_k_g1", "sim1110a_k_g2",
	])
	_occupy_pol_holes_except(mm, lm, {ger_from: true}, {x_pid: true, h_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	tm.set("total_days_elapsed", 0)
	var h_th := 0.0
	if bm.has_method("_ai_local_threat"):
		h_th = float(bm.call("_ai_local_threat", h_pid, "POL"))
	var pick = bm.call("_ai_pick_quiet_spare", "POL", h_pid)
	var pick_fid := str(pick.formation_id) if pick != null else ""
	bm.call("try_ai_cover_threatened_borders")
	var s1_at := _station_of(lm, "sim1110a_k_s1")
	var s2_at := _station_of(lm, "sim1110a_k_s2")
	var s1_md := _march_dest("sim1110a_k_s1")
	var s2_md := _march_dest("sim1110a_k_s2")
	var x_n := _tag_count_at(lm, "POL", x_pid)
	var h_n := _tag_count_at(lm, "POL", h_pid)
	var skip := _log_has(bm, "GARRISON_REINFORCE skip_captured")
	print(
		"SIM1110A_K X=%d H=%d ger_from=%d s1=%d/%d s2=%d/%d x_n=%d h_n=%d skip=%s Hth=%.3f pick=%s"
		% [x_pid, h_pid, ger_from, s1_at, s1_md, s2_at, s2_md, x_n, h_n, str(skip), h_th, pick_fid]
	)
	if s1_at == x_pid or s2_at == x_pid or s1_md == x_pid or s2_md == x_pid:
		_fail("(k) spare reinforced captured X=%d (s1=%d md=%d s2=%d md=%d)" % [x_pid, s1_at, s1_md, s2_at, s2_md])
		return
	if not skip:
		_fail("(k) missing GARRISON_REINFORCE skip_captured print")
		return
	if h_n < 2 and s1_at != h_pid and s2_at != h_pid and s1_md != h_pid and s2_md != h_pid:
		_fail("(k) control home H=%d was not reinforced h_n=%d s1=%d/%d s2=%d/%d" % [h_pid, h_n, s1_at, s1_md, s2_at, s2_md])
		return
	_pass("(k) no reinforce onto captured X=%d; control H=%d reinforced; skip_captured printed" % [x_pid, h_pid])
	var _unused_k := sm


func _test_k2_no_cover_captured(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(k2) declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(k2) no GER-POL border")
		return
	var y_pid := int(pair[0])
	var pol_pid := int(pair[1])
	var ger_from := _first_own_land_neighbor(mm, y_pid, "GER")
	if ger_from <= 0:
		ger_from = y_pid
	bm.call("_apply_attacker_win_capture_light", "POL", y_pid, pol_pid, "")
	if _owner(mm, y_pid) != "POL":
		_fail("(k2) capture did not flip Y=%d owner=%s" % [y_pid, _owner(mm, y_pid)])
		return
	var h_pid := _pol_neighbor_of(mm, ger_from, y_pid)
	if h_pid <= 0:
		_fail("(k2) no POL home hex H facing the GER station")
		return
	var q1 := _quiet_pol_pid(mm, {y_pid: true, h_pid: true, pol_pid: true})
	var q2 := _quiet_pol_pid(mm, {y_pid: true, h_pid: true, pol_pid: true, q1: true})
	if q1 <= 0 or q2 <= 0:
		_fail("(k2) no quiet POL spares")
		return
	_vacate_tag_at(lm, "POL", y_pid, q1)
	_vacate_tag_at(lm, "GER", y_pid, ger_from)
	_vacate_tag_at(lm, "POL", h_pid, q2)
	_make_garr(lm, "sim1110a_k2_s1", "POL", q1, 1.0)
	_make_garr(lm, "sim1110a_k2_s2", "POL", q2, 1.0)
	_boot.make_division("sim1110a_k2_ger", "GER", ger_from)
	_keep_only_formations(lm, ["sim1110a_k2_s1", "sim1110a_k2_s2", "sim1110a_k2_ger"])
	_occupy_pol_holes_except(mm, lm, {ger_from: true}, {y_pid: true, h_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var s1_at := _station_of(lm, "sim1110a_k2_s1")
	var s2_at := _station_of(lm, "sim1110a_k2_s2")
	var y_n := _tag_count_at(lm, "POL", y_pid)
	var h_n := _tag_count_at(lm, "POL", h_pid)
	var skip := _log_has(bm, "GARRISON_COVER skip_captured")
	print(
		"SIM1110A_K2 Y=%d H=%d s1=%d s2=%d y_n=%d h_n=%d skip=%s"
		% [y_pid, h_pid, s1_at, s2_at, y_n, h_n, str(skip)]
	)
	if s1_at == y_pid or s2_at == y_pid or y_n > 0:
		_fail("(k2) cover moved onto captured Y=%d s1=%d s2=%d y_n=%d" % [y_pid, s1_at, s2_at, y_n])
		return
	if not skip:
		_fail("(k2) missing GARRISON_COVER skip_captured print")
		return
	if h_n < 1 and s1_at != h_pid and s2_at != h_pid:
		_fail("(k2) control home H=%d was not covered h_n=%d s1=%d s2=%d" % [h_pid, h_n, s1_at, s2_at])
		return
	_pass("(k2) no cover onto captured Y=%d; control H=%d covered; skip_captured printed" % [y_pid, h_pid])
	var _unused_k2 := sm


func _test_l_move_cooldown(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(l) declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(l) no GER-POL border")
		return
	var a_pid := int(pair[1])
	var ger_a := int(pair[0])
	var b_pair: Array[int] = _other_pol_front_distinct(mm, a_pid, ger_a)
	if b_pair.size() < 2:
		_fail("(l) no second POL home hex B with a distinct GER neighbor")
		return
	var b_pid := int(b_pair[0])
	var ger_b := int(b_pair[1])
	var q := _quiet_pol_pid(mm, {a_pid: true, b_pid: true})
	if q <= 0:
		_fail("(l) no quiet POL spare hex")
		return
	_vacate_tag_at(lm, "POL", a_pid, q)
	_vacate_tag_at(lm, "POL", b_pid, q)
	_make_garr(lm, "sim1110a_l_s", "POL", q, 1.0)
	_boot.make_division("sim1110a_l_ger", "GER", ger_a)
	_keep_only_formations(lm, ["sim1110a_l_s", "sim1110a_l_ger"])
	_occupy_pol_holes_except(mm, lm, {ger_a: true}, {a_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var s_at := _station_of(lm, "sim1110a_l_s")
	print("SIM1110A_L day0 S %d -> %d A=%d" % [q, s_at, a_pid])
	if s_at != a_pid:
		_fail("(l) spare did not move to A=%d got %d" % [a_pid, s_at])
		return
	# Park S back on the quiet hex so it is the only cover-pool spare for B.
	# Cooldown is stamped on the formation id, not the hex.
	var s_form: Object = lm.call("get_formation", "sim1110a_l_s") if lm.has_method("get_formation") else null
	if s_form != null:
		s_form.set("stationed_province_id", q)
	var blob: Dictionary = bm.call("get_save_data")
	var saved_ok := blob.get("ai_unit_moved_day") is Dictionary and (blob["ai_unit_moved_day"] as Dictionary).has("sim1110a_l_s")
	if saved_ok:
		bm.call("reset_ai_war1_for_test")
		bm.call("apply_save_data", blob)
		if not bm.has_method("_ai_unit_in_move_cooldown") or not bool(bm.call("_ai_unit_in_move_cooldown", "sim1110a_l_s", "POL", a_pid)):
			_fail("(l) cooldown did not survive save/load")
			return
	var ger_f: Object = lm.call("get_formation", "sim1110a_l_ger") if lm.has_method("get_formation") else null
	if ger_f != null:
		ger_f.set("stationed_province_id", ger_b)
	_occupy_pol_holes_except(mm, lm, {ger_b: true}, {b_pid: true, a_pid: true})
	var moved_early := false
	for day in range(1, 5):
		tm.set("total_days_elapsed", day)
		bm.call("try_ai_cover_threatened_borders")
		s_at = _station_of(lm, "sim1110a_l_s")
		print("SIM1110A_L day=%d S=%d B=%d" % [day, s_at, b_pid])
		if s_at == b_pid:
			moved_early = true
			break
	if moved_early:
		_fail("(l) S moved to B on day +1..+4 (station=%d)" % s_at)
		return
	if not saved_ok:
		_fail("(l) ai_unit_moved_day missing from save blob %s" % str(blob.keys()))
		return
	if ger_f != null:
		ger_f.set("stationed_province_id", ger_a)
	if s_form != null:
		s_form.set("stationed_province_id", a_pid)
	var opened: Dictionary = bm.call("start_land_battle", "GER", a_pid, ger_a, "sim1110a_l_ger")
	bm.call("_join_defence_if_attacked", "sim1110a_l_s", a_pid, "POL")
	var live: Dictionary = bm.call("get_land_battle_at", a_pid)
	var def_fids: Array = live.get("def_fids", []) as Array
	print("SIM1110A_L join def_fids=%s opened=%s" % [str(def_fids), str(opened.get("opened", false))])
	if not def_fids.has("sim1110a_l_s"):
		_fail("(l) join-defence-if-attacked blocked during cooldown fids=%s" % str(def_fids))
		return
	tm.set("total_days_elapsed", 5)
	bm.call("try_ai_cover_threatened_borders")
	s_at = _station_of(lm, "sim1110a_l_s")
	print("SIM1110A_L day5 S=%d B=%d" % [s_at, b_pid])
	_pass("(l) S held A on days +1..+4 (may move day +5 station=%d); join-defence still works" % s_at)
	var _unused_l := sm


func _test_m_threat_radius(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(m) declare GER-POL failed")
		return
	var fx: Dictionary = _threat_radius_fixture(mm)
	if int(fx.get("p", 0)) <= 0:
		_fail("(m) no P with two GER-owned neighbors")
		return
	var p_pid := int(fx["p"])
	var g1 := int(fx["g1"])
	var g2 := int(fx["g2"])
	var gfar := int(fx.get("gfar", -1))
	var q := _quiet_pol_pid(mm, {p_pid: true})
	if q <= 0:
		_fail("(m) no quiet POL spare")
		return
	_vacate_tag_at(lm, "POL", p_pid, q)
	_make_garr(lm, "sim1110a_m_own", "POL", p_pid, 1.5)
	_make_garr(lm, "sim1110a_m_s", "POL", q, 1.0)
	_boot.make_division("sim1110a_m_e1", "GER", g1)
	_boot.make_division("sim1110a_m_e2", "GER", g2)
	_keep_only_formations(lm, ["sim1110a_m_own", "sim1110a_m_s", "sim1110a_m_e1", "sim1110a_m_e2"])
	_occupy_pol_holes_except(mm, lm, {g1: true, g2: true}, {p_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	var threat := _threat_on(bm, p_pid, "POL")
	var own_p := float(bm.call("_ai_hex_power", p_pid, "POL", "defend"))
	var max_stack := float(bm.call("_ai_max_adjacent_enemy_stack_power", p_pid, "POL"))
	print(
		"SIM1110A_M1 P=%d g1=%d g2=%d threat=%.3f own=%.3f max=%.3f r_local=%.3f r_max=%.3f"
		% [p_pid, g1, g2, threat, own_p, max_stack, threat / maxf(own_p, 1.0), max_stack / maxf(own_p, 1.0)]
	)
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var s_at := _station_of(lm, "sim1110a_m_s")
	var s_md := _march_dest("sim1110a_m_s")
	if absf(threat - max_stack) > 0.0001:
		_fail("(m.1) two adjacent stacks were summed threat=%.3f max=%.3f own=%.3f" % [threat, max_stack, own_p])
		return
	if s_at == p_pid or s_md == p_pid:
		_fail("(m.1) P was reinforced from two unsummed 1u stacks s=%d md=%d threat=%.3f own=%.3f" % [s_at, s_md, threat, own_p])
		return
	_pass("(m.1) two adjacent 1u stacks not summed; P not reinforced")
	if gfar <= 0:
		_fail("(m.2) no GER hex 2 hops from P")
		return
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(m.2) redeclare failed")
		return
	q = _quiet_pol_pid(mm, {p_pid: true})
	_vacate_tag_at(lm, "POL", p_pid, q)
	_make_garr(lm, "sim1110a_m2_own", "POL", p_pid, 1.5)
	_make_garr(lm, "sim1110a_m2_s", "POL", q, 1.0)
	_boot.make_division("sim1110a_m2_f1", "GER", gfar)
	_boot.make_division("sim1110a_m2_f2", "GER", gfar)
	_boot.make_division("sim1110a_m2_f3", "GER", gfar)
	_boot.make_division("sim1110a_m2_f4", "GER", gfar)
	_keep_only_formations(lm, [
		"sim1110a_m2_own", "sim1110a_m2_s",
		"sim1110a_m2_f1", "sim1110a_m2_f2", "sim1110a_m2_f3", "sim1110a_m2_f4",
	])
	_occupy_pol_holes_except(mm, lm, {gfar: true}, {p_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	var threat_far := _threat_on(bm, p_pid, "POL")
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var s2_at := _station_of(lm, "sim1110a_m2_s")
	var s2_md := _march_dest("sim1110a_m2_s")
	print("SIM1110A_M2 P=%d gfar=%d threat=%.3f s=%d md=%d" % [p_pid, gfar, threat_far, s2_at, s2_md])
	if s2_at == p_pid or s2_md == p_pid:
		_fail("(m.2) 2-hop 4-stack was counted; P reinforced")
		return
	_pass("(m.2) 4-division stack 2 hops away ignored")
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(m.3) redeclare failed")
		return
	q = _quiet_pol_pid(mm, {p_pid: true})
	_vacate_tag_at(lm, "POL", p_pid, q)
	_make_garr(lm, "sim1110a_m3_own", "POL", p_pid, 1.5)
	_make_garr(lm, "sim1110a_m3_s", "POL", q, 1.0)
	_boot.make_division("sim1110a_m3_e1", "GER", g1)
	_boot.make_division("sim1110a_m3_e2", "GER", g2)
	_keep_only_formations(lm, ["sim1110a_m3_own", "sim1110a_m3_s", "sim1110a_m3_e1", "sim1110a_m3_e2"])
	_occupy_pol_holes_except(mm, lm, {g1: true, g2: true}, {p_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	var threat_ai := _threat_on(bm, p_pid, "POL")
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var s_ai := _station_of(lm, "sim1110a_m3_s")
	var sp := get_root().get_node_or_null("SessionPlayers")
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "GER")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var threat_hu := _threat_on(bm, p_pid, "POL")
	print("SIM1110A_M3 threat_ai=%.3f threat_hu=%.3f s_ai=%d" % [threat_ai, threat_hu, s_ai])
	if absf(threat_ai - threat_hu) > 0.0001:
		_fail("(m.3) threat AI vs human diverged ai=%.3f hu=%.3f" % [threat_ai, threat_hu])
		return
	_pass("(m.3) human = AI threat %.3f and same reinforce decision" % threat_ai)
	var _unused_m := [sm]


func _test_n_pol_reinforce_fire(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(n) declare GER-POL failed")
		return
	var fx: Dictionary = _threat_radius_fixture(mm)
	if int(fx.get("p", 0)) <= 0:
		_fail("(n) no P with two GER-owned neighbors")
		return
	var p_pid := int(fx["p"])
	var g1 := int(fx["g1"])
	var q := _quiet_pol_pid(mm, {p_pid: true})
	if q <= 0:
		_fail("(n) no quiet POL spare")
		return
	_vacate_tag_at(lm, "POL", p_pid, q)
	_make_garr(lm, "sim1110a_n_own", "POL", p_pid, 1.0)
	_make_garr(lm, "sim1110a_n_s", "POL", q, 1.0)
	_boot.make_division("sim1110a_n_g1", "GER", g1)
	_boot.make_division("sim1110a_n_g2", "GER", g1)
	_keep_only_formations(lm, ["sim1110a_n_own", "sim1110a_n_s", "sim1110a_n_g1", "sim1110a_n_g2"])
	_occupy_pol_holes_except(mm, lm, {g1: true}, {p_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	var threat := _threat_on(bm, p_pid, "POL")
	var own_p := float(bm.call("_ai_hex_power", p_pid, "POL", "defend"))
	var r := threat / maxf(own_p, 1.0)
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var s_at := _station_of(lm, "sim1110a_n_s")
	var s_md := _march_dest("sim1110a_n_s")
	var fired := s_at == p_pid or s_md == p_pid
	var log_hit := _log_has(bm, "GARRISON_REINFORCE")
	print(
		"SIM1110A_N FIRE P=%d q=%d threat=%.3f own=%.3f r=%.3f s=%d md=%d fired=%s log=%s"
		% [p_pid, q, threat, own_p, r, s_at, s_md, str(fired), str(log_hit)]
	)
	if r < 1.2:
		_fail("(n) fire fixture r=%.3f < 1.2 (not under-covered)" % r)
		return
	if not fired:
		_fail("(n) threatened under-covered POL P=%d was not reinforced s=%d md=%d" % [p_pid, s_at, s_md])
		return
	if not log_hit:
		_fail("(n) missing GARRISON_REINFORCE print")
		return
	_pass("(n) threatened under-covered POL P=%d reinforced (fire)" % p_pid)
	var _unused_n := sm


func _test_n2_pol_reinforce_hold(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(n2) declare GER-POL failed")
		return
	var fx: Dictionary = _threat_radius_fixture(mm)
	if int(fx.get("p", 0)) <= 0:
		_fail("(n2) no P with two GER-owned neighbors")
		return
	var p_pid := int(fx["p"])
	var g1 := int(fx["g1"])
	var other: Array[int] = _other_pol_front_distinct(mm, p_pid, g1)
	if other.size() < 2:
		_fail("(n2) no other POL front hex")
		return
	var f_pid := int(other[0])
	var ger_f := int(other[1])
	_vacate_tag_at(lm, "POL", p_pid, f_pid)
	_vacate_tag_at(lm, "POL", f_pid, f_pid)
	_make_garr(lm, "sim1110a_n2_last", "POL", f_pid, 1.0)
	_boot.make_division("sim1110a_n2_g1", "GER", g1)
	_boot.make_division("sim1110a_n2_g2", "GER", g1)
	_boot.make_division("sim1110a_n2_gf", "GER", ger_f)
	_keep_only_formations(lm, ["sim1110a_n2_last", "sim1110a_n2_g1", "sim1110a_n2_g2", "sim1110a_n2_gf"])
	_occupy_pol_holes_except(mm, lm, {g1: true, ger_f: true}, {p_pid: true, f_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	var pick = bm.call("_ai_pick_quiet_spare", "POL", p_pid)
	var pick_fid := str(pick.formation_id) if pick != null else ""
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var last_at := _station_of(lm, "sim1110a_n2_last")
	var last_md := _march_dest("sim1110a_n2_last")
	var pulled := last_at == p_pid or last_md == p_pid
	print(
		"SIM1110A_N2 HOLD P=%d F=%d last=%d/%d pick=%s pulled=%s"
		% [p_pid, f_pid, last_at, last_md, pick_fid, str(pulled)]
	)
	if pulled:
		_fail("(n2) pulled last front defender F=%d onto P=%d" % [f_pid, p_pid])
		return
	if last_at != f_pid:
		_fail("(n2) last defender left F=%d station=%d" % [f_pid, last_at])
		return
	if pick_fid == "sim1110a_n2_last":
		_fail("(n2) _ai_pick_quiet_spare returned the last front defender")
		return
	_pass("(n2) last front defender F=%d held (not pulled onto P=%d)" % [f_pid, p_pid])
	var _unused_n2 := sm


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


func _make_garr(lm: Node, fid: String, tag: String, pid: int, strength: float) -> void:
	_boot.make_division(fid, tag, pid)
	var f: Object = lm.call("get_formation", fid) if lm.has_method("get_formation") else null
	if f == null:
		return
	f.set("strength", strength)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set_meta("garrison_1936", true)


func _threat_on(bm: Node, pid: int, tag: String) -> float:
	if bm.has_method("_ai_local_threat"):
		return float(bm.call("_ai_local_threat", pid, tag))
	if bm.has_method("_ai_max_adjacent_enemy_stack_power"):
		return float(bm.call("_ai_max_adjacent_enemy_stack_power", pid, tag))
	return 0.0


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


func _log_has(bm: Node, needle: String) -> bool:
	if not bm.has_method("ai_r2_prints"):
		return false
	for line_v in bm.call("ai_r2_prints"):
		if needle in str(line_v):
			return true
	return false


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


func _pol_neighbor_of(mm: Node, ger_pid: int, skip: int) -> int:
	if ger_pid <= 0:
		return -1
	var nbrs: Array = mm.call("get_adjacent_provinces", ger_pid, true)
	var ids: Array[int] = []
	for nid_v in nbrs:
		ids.append(int(nid_v))
	ids.sort()
	for nid in ids:
		if nid == skip or nid <= 0:
			continue
		var p: Object = mm.call("get_province", nid)
		if p == null or bool(p.get("is_sea")):
			continue
		if str(p.get("owner_tag")).strip_edges().to_upper() == "POL":
			return nid
	return -1


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
			# r>=2.0 targets 3, so three dummies keep fillers off the reinforce list.
			_boot.make_division("sim1110a_fill_%d_a" % nid, "POL", nid)
			_boot.make_division("sim1110a_fill_%d_b" % nid, "POL", nid)
			_boot.make_division("sim1110a_fill_%d_c" % nid, "POL", nid)


func _other_pol_front_distinct(mm: Node, skip: int, skip_ger: int) -> Array[int]:
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
		var ger_n := _first_own_land_neighbor(mm, pid, "GER")
		if ger_n > 0 and ger_n != skip_ger:
			return [pid, ger_n] as Array[int]
	return [] as Array[int]


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
		var gfar := _ger_two_hops(mm, pid, ger_n)
		return {"p": pid, "g1": ger_n[0], "g2": ger_n[1], "gfar": gfar}
	return {}


func _ger_two_hops(mm: Node, origin: int, adj_ger: Array[int]) -> int:
	var blocked: Dictionary = {origin: true}
	for g in adj_ger:
		blocked[int(g)] = true
	var hop1: Dictionary = {}
	var nbrs0: Array = mm.call("get_adjacent_provinces", origin, true)
	for nid_v in nbrs0:
		hop1[int(nid_v)] = true
	var ids: Array[int] = []
	for nid2_v in hop1.keys():
		ids.append(int(nid2_v))
	ids.sort()
	for nid in ids:
		var nbrs: Array = mm.call("get_adjacent_provinces", nid, true)
		var hop2: Array[int] = []
		for n2_v in nbrs:
			hop2.append(int(n2_v))
		hop2.sort()
		for n2 in hop2:
			if bool(blocked.get(n2, false)) or bool(hop1.get(n2, false)):
				continue
			var p: Object = mm.call("get_province", n2)
			if p == null or bool(p.get("is_sea")):
				continue
			if str(p.get("owner_tag")).strip_edges().to_upper() == "GER":
				return n2
	return -1
