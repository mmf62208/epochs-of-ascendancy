extends SceneTree

## POL-REINF-1: defensive COVER/REINFORCE garrisons are anchored; garrison_1936
## cannot launch from war-captured land. STANDALONE (not in --quick).
## Must FAIL on stack base 0b99f2a3 and PASS on tip.
##
## Command (fresh XDG_DATA_HOME, one Godot):
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessPolReinf1Test.gd

const SCENARIO_PATH := "res://data/scenarios/world_accurate.json"
const SRC_BM := "res://scripts/combat/BattleManager.gd"
const RUN_SEED := 0x20fe9063
const GER_FRONT := 710173
const FRA_FRONT := 710739
const GER_CAPITAL := 710300
const POL_CAPITAL := 711112
const MAJOR_COUNT_TAGS: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
const CHIP_MAJORS: Array = [
	{"tag": "ENG", "pid": 711414, "design": "m4_sherman_medium_tank"},
	{"tag": "USA", "pid": 800792, "design": "m4_sherman_medium_tank"},
	{"tag": "SOV", "pid": 903534, "design": "t34_medium_tank"},
	{"tag": "ITA", "pid": 710963, "design": "cv33_tankette"},
	{"tag": "JAP", "pid": 903981, "design": "jap_armor_1936"},
	{"tag": "POL", "pid": 711112, "design": "pol_armor_1936"},
]

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _gd: Node
var _live_approx := false
var _ctrl_md5_a := ""
var _ctrl_md5_b := ""


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_AI_REJECT_LOG", "")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPolReinf1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPolReinf1Test: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	_gd = get_root().get_node_or_null("GameData")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if mm == null or bm == null or tm == null or lm == null or _gd == null or _boot == null or _war == null:
		_fail("autoloads missing")
		_finish()
		return
	_assert_source(bm)
	if not _boot_as(mm, sm, bm, tm, lm, "GER", false):
		_finish()
		return
	_seed_live(mm, lm)
	_test_c_g1(mm, sm, bm, tm, lm)
	_test_d_g2(mm, sm, bm, tm, lm)
	_test_e_human_ai_cover_a7(mm, sm, bm, tm, lm)
	if OS.get_environment("EOA_POL_REINF1_QUICK").strip_edges() == "1":
		print("POLREINF1_QUICK skip (a)(b)(f) 180d/60d gerplayer")
	else:
		_test_abf_gerplayer(mm, sm, bm, tm, lm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessPolReinf1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPolReinf1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _assert_source(bm: Node) -> void:
	var bm_src := FileAccess.get_file_as_string(SRC_BM)
	if "const POL_REINF_ANCHOR_DAYS := 30" not in bm_src:
		_fail("(c) G1 missing POL_REINF_ANCHOR_DAYS := 30")
	if "const POL_REINF_ANCHOR_DAYS_MIN := 21" not in bm_src:
		_fail("(c) G1 missing POL_REINF_ANCHOR_DAYS_MIN := 21")
	if "const POL_REINF_ANCHOR_DAYS_MAX := 45" not in bm_src:
		_fail("(c) G1 missing POL_REINF_ANCHOR_DAYS_MAX := 45")
	if "func _ai_stamp_def_anchor" not in bm_src:
		_fail("(c) G1 missing _ai_stamp_def_anchor")
	if "func _ai_garrison_is_def_anchored" not in bm_src:
		_fail("(c) G1 missing _ai_garrison_is_def_anchored")
	if "func _ai_offensive_power_at" not in bm_src:
		_fail("(c) G1 missing _ai_offensive_power_at")
	if "AI_DEF_ANCHOR skip" not in bm_src:
		_fail("(c) G1 missing AI_DEF_ANCHOR skip print")
	if "garrison_captured_src" not in bm_src:
		_fail("(d) G2 missing garrison_captured_src reject")
	if "AI_GARRISON_CAPTURED_SRC skip" not in bm_src:
		_fail("(d) G2 missing AI_GARRISON_CAPTURED_SRC skip print")
	if "func _ai_resolve_offensive_fid" not in bm_src:
		_fail("(c)(d) missing _ai_resolve_offensive_fid")
	if '"ai_def_anchor_day"' in bm_src and "get_save_data" in bm_src:
		var save_fn := _func_body(bm_src, "get_save_data")
		if "ai_def_anchor_day" in save_fn:
			_fail("save-format change: ai_def_anchor_day in get_save_data")
	if not bm.has_method("_ai_garrison_is_def_anchored"):
		_fail("(c) G1 API _ai_garrison_is_def_anchored missing")
	if not bm.has_method("_ai_resolve_offensive_fid"):
		_fail("(d) G2 API _ai_resolve_offensive_fid missing")
	var days := int(bm.get("POL_REINF_ANCHOR_DAYS")) if "POL_REINF_ANCHOR_DAYS" in bm else -1
	var dmin := int(bm.get("POL_REINF_ANCHOR_DAYS_MIN")) if "POL_REINF_ANCHOR_DAYS_MIN" in bm else -1
	var dmax := int(bm.get("POL_REINF_ANCHOR_DAYS_MAX")) if "POL_REINF_ANCHOR_DAYS_MAX" in bm else -1
	if days < dmin or days > dmax or days != 30:
		_fail("(c) G1 POL_REINF_ANCHOR_DAYS=%d not 30 in [%d,%d]" % [days, dmin, dmax])
	else:
		_pass("source G1/G2 APIs POL_REINF_ANCHOR_DAYS=%d" % days)


func _boot_as(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, player: String, observer: bool = false) -> bool:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	if lm != null and "_garrisons_1936_seeded" in lm:
		lm._garrisons_1936_seeded = false
	if _gd != null:
		var ps: Variant = _gd.get("peace_state")
		if ps is Dictionary:
			(ps as Dictionary)["garrison_seed_n"] = {}
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
		if "_empty_hex_siege" in bm:
			bm._empty_hex_siege = {}
		if "_pending_light_captures" in bm:
			bm._pending_light_captures = []
		if bm.has_method("reset_ai_war1_for_test"):
			bm.reset_ai_war1_for_test()
	if mm != null and "_live_fronts_precompute" in mm:
		mm.set("_live_fronts_precompute", {})
	if not _boot.boot(mm, sm, player):
		_fail("boot %s failed" % player)
		return false
	if tm != null:
		tm.set("run_seed", RUN_SEED)
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
	if observer:
		_war.set_campaign_observer(true)
	return true


func _seed_live(mm: Node, lm: Node) -> Dictionary:
	_spawn_live_oob(mm, lm)
	var seeded: Dictionary = lm.call("seed_1936_start_garrisons", true)
	var placed := int(seeded.get("placed", -1))
	var skipped := int(seeded.get("skipped_occupied", -1))
	var targets := int(seeded.get("targets", -1))
	var fp := "garrisons placed=%d skipped_occupied=%d targets=%d" % [placed, skipped, targets]
	print("POLREINF1_SEED %s" % fp)
	_live_approx = not (placed == 536 and skipped == 40 and targets == 576)
	if _live_approx:
		_fail("LIVE-APPROX %s (want placed=536 skipped_occupied=40 targets=576)" % fp)
	else:
		_pass("LIVE fingerprint %s" % fp)
	return seeded


func _test_c_g1(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bm.has_method("_ai_garrison_is_def_anchored") or not bm.has_method("_ai_move_garrison_to"):
		_fail("(c) G1 APIs missing (expected on stack base)")
		return
	if not _boot_as(mm, sm, bm, tm, lm, "GER", false):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(c) declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(c) no GER-POL border")
		return
	var ger_to := int(pair[0])
	var pol_from := int(pair[1])
	var quiet := _quiet_pol_pid(mm, {pol_from: true, ger_to: true})
	if quiet <= 0:
		_fail("(c) no quiet POL spare hex")
		return
	_vacate_tag_at(lm, "POL", pol_from, quiet)
	_vacate_tag_at(lm, "GER", ger_to, ger_to)
	_make_garr(lm, "polreinf1_g1_s", "POL", quiet, 1.0)
	_boot.make_division("polreinf1_g1_ger", "GER", ger_to)
	_keep_only_formations(lm, ["polreinf1_g1_s", "polreinf1_g1_ger"])
	_occupy_pol_holes_except(mm, lm, {ger_to: true}, {pol_from: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	tm.set("total_days_elapsed", 2)
	var spare: Object = lm.call("get_formation", "polreinf1_g1_s")
	if spare == null:
		_fail("(c) spare missing")
		return
	bm.call("_ai_move_garrison_to", spare, pol_from, "POL")
	spare.set("stationed_province_id", pol_from)
	if bm.has_method("_note_garrison_station"):
		bm.call("_note_garrison_station", "polreinf1_g1_s", "POL", pol_from)
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "POL")
	_clear_marches()
	var anchored := bool(bm.call("_ai_garrison_is_def_anchored", "polreinf1_g1_s"))
	print("POLREINF1_G1 dest=%d from_quiet=%d anchored=%s" % [pol_from, quiet, str(anchored)])
	if not anchored:
		_fail("(c) G1 reinforce move did not anchor polreinf1_g1_s")
		return
	var raw_p := 0.0
	if bm.has_method("_ai_front_powers"):
		raw_p = float((bm.call("_ai_front_powers", "POL", pol_from, "GER", ger_to) as Dictionary).get("attacker_power", 0.0))
	var off_p := float(bm.call("_ai_offensive_power_at", pol_from, "POL", "GER", ger_to))
	print("POLREINF1_G1 raw_p=%.3f off_p=%.3f" % [raw_p, off_p])
	if off_p + 0.0001 >= raw_p and raw_p > 0.0:
		_fail("(c) G1 anchored unit still in offensive power raw=%.3f off=%.3f" % [raw_p, off_p])
		return
	if bm.has_method("ai_reject_counters"):
		bm.call("ai_reject_counters", true)
	var resolved := str(bm.call("_ai_resolve_offensive_fid", "POL", pol_from, "polreinf1_g1_s"))
	var rej: Dictionary = bm.call("ai_reject_counters", false) if bm.has_method("ai_reject_counters") else {}
	var da := int(rej.get("def_anchor", 0))
	print("POLREINF1_G1 resolve=%s def_anchor=%d" % [resolved, da])
	if not resolved.is_empty():
		_fail("(c) G1 resolve still picked anchored fid=%s" % resolved)
		return
	if da < 1:
		_fail("(c) G1 def_anchor reject not counted")
		return
	var s2 := _first_own_land_neighbor(mm, pol_from, "POL")
	if s2 > 0:
		var march_opps: Array = []
		bm.call("_collect_adjacent_stack_march", "POL", s2, ger_to, "GER", [], [], march_opps)
		for row_v in march_opps:
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			if str((row_v as Dictionary).get("formation_id", "")) == "polreinf1_g1_s":
				_fail("(c) G1 anchored fid in stack-march list onto %d" % s2)
				return
	var hold := int(bm.get("POL_REINF_ANCHOR_DAYS"))
	var ad: Dictionary = bm.get("_ai_def_anchor_day")
	ad["polreinf1_g1_s"] = int(bm.call("_ai_day")) - hold
	bm.set("_ai_def_anchor_day", ad)
	if bool(bm.call("_ai_garrison_is_def_anchored", "polreinf1_g1_s")):
		_fail("(c) G1 still anchored after POL_REINF_ANCHOR_DAYS")
		return
	_pass("(c) G1 anchor + power + preview + stack-march + expire")
	var _u := sm


func _test_d_g2(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bm.has_method("_ai_resolve_offensive_fid") or not bm.has_method("_ai_is_war_captured"):
		_fail("(d) G2 APIs missing (expected on stack base)")
		return
	if not _boot_as(mm, sm, bm, tm, lm, "GER", false):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(d) declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(d) no GER-POL border")
		return
	var x_pid := int(pair[0])
	var pol_pid := int(pair[1])
	var ger_from := _first_own_land_neighbor(mm, x_pid, "GER")
	if ger_from <= 0:
		ger_from = x_pid
	bm.call("_apply_attacker_win_capture_light", "POL", x_pid, pol_pid, "")
	if _owner(mm, x_pid) != "POL":
		_fail("(d) capture did not flip X=%d owner=%s" % [x_pid, _owner(mm, x_pid)])
		return
	if not bool(bm.call("_ai_is_war_captured", "POL", x_pid)):
		_fail("(d) X %d not in POL captured_pids" % x_pid)
		return
	var quiet := _quiet_pol_pid(mm, {x_pid: true, pol_pid: true, ger_from: true})
	_vacate_tag_at(lm, "POL", x_pid, quiet if quiet > 0 else pol_pid)
	_vacate_tag_at(lm, "GER", x_pid, ger_from)
	_make_garr(lm, "polreinf1_g2_g", "POL", x_pid, 1.0)
	_boot.make_division("polreinf1_g2_ger", "GER", ger_from)
	_keep_only_formations(lm, ["polreinf1_g2_g", "polreinf1_g2_ger"])
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	if bm.has_method("ai_reject_counters"):
		bm.call("ai_reject_counters", true)
	var resolved := str(bm.call("_ai_resolve_offensive_fid", "POL", x_pid, "polreinf1_g2_g"))
	var rej: Dictionary = bm.call("ai_reject_counters", false) if bm.has_method("ai_reject_counters") else {}
	var gcs := int(rej.get("garrison_captured_src", 0))
	print("POLREINF1_G2 X=%d resolve=%s garrison_captured_src=%d" % [x_pid, resolved, gcs])
	if not resolved.is_empty():
		_fail("(d) G2 garrison launched from captured X=%d fid=%s" % [x_pid, resolved])
		return
	if gcs < 1:
		_fail("(d) G2 garrison_captured_src reject not counted")
		return
	_boot.make_division("polreinf1_g2_field", "POL", x_pid)
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "POL")
	if bm.has_method("ai_reject_counters"):
		bm.call("ai_reject_counters", true)
	var resolved_f := str(bm.call("_ai_resolve_offensive_fid", "POL", x_pid, "polreinf1_g2_g"))
	var rej2: Dictionary = bm.call("ai_reject_counters", false) if bm.has_method("ai_reject_counters") else {}
	print("POLREINF1_G2 field resolve=%s gcs2=%d" % [resolved_f, int(rej2.get("garrison_captured_src", 0))])
	if resolved_f != "polreinf1_g2_field":
		_fail("(d) G2 field on captured hex should still launch got=%s" % resolved_f)
		return
	if int(rej2.get("garrison_captured_src", 0)) > 0:
		_fail("(d) G2 rejected mixed captured hex with field")
		return
	# Home-land garrison retaking own lost land: from-hex is not war-captured.
	var h_pid := pol_pid
	_vacate_tag_at(lm, "POL", h_pid, quiet if quiet > 0 else h_pid)
	_make_garr(lm, "polreinf1_g2_home", "POL", h_pid, 1.0)
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "POL")
	if bool(bm.call("_ai_is_war_captured", "POL", h_pid)):
		_fail("(d) POL home %d marked war-captured" % h_pid)
		return
	if bm.has_method("ai_reject_counters"):
		bm.call("ai_reject_counters", true)
	var resolved_h := str(bm.call("_ai_resolve_offensive_fid", "POL", h_pid, "polreinf1_g2_home"))
	var rej3: Dictionary = bm.call("ai_reject_counters", false) if bm.has_method("ai_reject_counters") else {}
	print("POLREINF1_G2 home H=%d resolve=%s gcs3=%d" % [h_pid, resolved_h, int(rej3.get("garrison_captured_src", 0))])
	if int(rej3.get("garrison_captured_src", 0)) > 0:
		_fail("(d) G2 blocked home-land retake from %d" % h_pid)
		return
	if resolved_h.is_empty():
		_fail("(d) G2 home garrison should still be able to retake")
		return
	_pass("(d) G2 no garrison launch from captured; field ok; home retake ok")
	var _u := sm


func _test_e_human_ai_cover_a7(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bm.has_method("_ai_garrison_is_def_anchored"):
		_fail("(e) G1 API missing")
		return
	# Same G1 stamp when the enemy is AI (USA observer).
	if not _boot_as(mm, sm, bm, tm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(e) observer declare failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("(e) no border")
		return
	var ger_to := int(pair[0])
	var pol_from := int(pair[1])
	var quiet := _quiet_pol_pid(mm, {pol_from: true, ger_to: true})
	_vacate_tag_at(lm, "POL", pol_from, quiet)
	_make_garr(lm, "polreinf1_e_s", "POL", quiet, 1.0)
	_keep_only_formations(lm, ["polreinf1_e_s"])
	_occupy_pol_holes_except(mm, lm, {ger_to: true}, {pol_from: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	tm.set("total_days_elapsed", 2)
	var spare: Object = lm.call("get_formation", "polreinf1_e_s")
	bm.call("_ai_move_garrison_to", spare, pol_from, "POL")
	spare.set("stationed_province_id", pol_from)
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "POL")
	if not bool(bm.call("_ai_garrison_is_def_anchored", "polreinf1_e_s")):
		_fail("(e) G1 did not hold when enemy is AI")
		return
	_pass("(e) G1 holds vs AI enemy")
	# COVER still fills an empty threatened home hole.
	if not _boot_as(mm, sm, bm, tm, lm, "GER", false):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("(e) cover declare failed")
		return
	pair = _border_pair(mm, "GER", "POL")
	var ger_pid := int(pair[0])
	var h_pid := int(pair[1])
	var q1 := _quiet_pol_pid(mm, {ger_pid: true, h_pid: true})
	var q2 := _quiet_pol_pid(mm, {ger_pid: true, h_pid: true, q1: true})
	_vacate_tag_at(lm, "POL", h_pid, q1 if q1 > 0 else h_pid)
	_vacate_tag_at(lm, "GER", ger_pid, ger_pid)
	_make_garr(lm, "polreinf1_e_s1", "POL", q1, 1.0)
	_make_garr(lm, "polreinf1_e_s2", "POL", q2, 1.0)
	_boot.make_division("polreinf1_e_ger", "GER", ger_pid)
	_keep_only_formations(lm, ["polreinf1_e_s1", "polreinf1_e_s2", "polreinf1_e_ger"])
	_occupy_pol_holes_except(mm, lm, {ger_pid: true}, {h_pid: true})
	if bm.has_method("bump_ai_board_epoch"):
		bm.call("bump_ai_board_epoch")
	tm.set("total_days_elapsed", 0)
	bm.call("try_ai_cover_threatened_borders")
	var h_n := _tag_count_at(lm, "POL", h_pid)
	var s1 := _station_of(lm, "polreinf1_e_s1")
	var s2 := _station_of(lm, "polreinf1_e_s2")
	print("POLREINF1_E cover H=%d ger=%d h_n=%d s1=%d s2=%d" % [h_pid, ger_pid, h_n, s1, s2])
	if h_n < 1 and s1 != h_pid and s2 != h_pid:
		_fail("(e) COVER did not fill threatened home hole H=%d" % h_pid)
		return
	_pass("(e) COVER fills threatened home hole")
	var _u := sm


func _test_abf_gerplayer(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	var first := _run_gerplayer(mm, sm, bm, tm, lm, 180, true)
	if first.is_empty():
		return
	_ctrl_md5_a = str(first.get("md5_d60", ""))
	var second := _run_gerplayer(mm, sm, bm, tm, lm, 60, false)
	if second.is_empty():
		return
	_ctrl_md5_b = str(second.get("md5_d60", ""))
	print("POLREINF1_F ctrl_md5 a=%s b=%s" % [_ctrl_md5_a, _ctrl_md5_b])
	if _ctrl_md5_a.is_empty() or _ctrl_md5_a != _ctrl_md5_b:
		_fail("(f) ctrl_md5 diverged a=%s b=%s" % [_ctrl_md5_a, _ctrl_md5_b])
		return
	_pass("(f) ctrl_md5 %s" % _ctrl_md5_a)


func _run_gerplayer(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, days: int, check_long: bool) -> Dictionary:
	if not _boot_as(mm, sm, bm, tm, lm, "GER", false):
		return {}
	_seed_live(mm, lm)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("gerplayer declare GER-POL failed")
		return {}
	var ger1936 := _owned_set(mm, "GER")
	var pol1936 := _owned_set(mm, "POL")
	var ger_start: Dictionary = _ger_stations(lm)
	var und := 0
	var net14 := -1
	var net21 := -1
	var net30 := -1
	var net60 := -1
	var net180 := -1
	var und60 := 0
	var md5_d60 := ""
	var illegal := 0
	var prev_owner: Dictionary = {}
	var prev_n: Dictionary = {}
	_fill_owner_div(mm, lm, prev_owner, prev_n)
	if bm.has_method("ai_reject_counters"):
		bm.call("ai_reject_counters", true)
	_log_pol_targets(mm, bm, lm)
	for day in range(1, days + 1):
		_advance_day(tm, bm)
		var now_owner: Dictionary = {}
		var now_n: Dictionary = {}
		_fill_owner_div(mm, lm, now_owner, now_n)
		for pid_v in now_owner.keys():
			var pid := int(pid_v)
			var o0 := str(prev_owner.get(pid, ""))
			var o1 := str(now_owner.get(pid, ""))
			if o0.is_empty() or o1 == o0:
				continue
			if int(prev_n.get(pid, 0)) < 1:
				und += 1
		prev_owner = now_owner
		prev_n = now_n
		illegal += _count_illegal_ger_moves(mm, lm, ger_start)
		ger_start = _ger_stations(lm)
		var net := _net(mm, ger1936, pol1936)
		if day == 14:
			net14 = net
			print("POLREINF1_A2 d14 net=%d und=%d" % [net, und])
		elif day == 21:
			net21 = net
			print("POLREINF1_A2 d21 net=%d und=%d" % [net, und])
		elif day == 30:
			net30 = net
			print("POLREINF1_A2 d30 net=%d und=%d" % [net, und])
		elif day == 60:
			net60 = net
			und60 = und
			md5_d60 = _ctrl_md5(mm)
			print("POLREINF1_A2 d60 net=%d und=%d" % [net, und])
		elif day == 180:
			net180 = net
			print("POLREINF1_A3 d180 net=%d und=%d" % [net, und])
	if md5_d60.is_empty():
		md5_d60 = _ctrl_md5(mm)
	var berlin := _owner(mm, GER_CAPITAL)
	var warsaw := _owner(mm, POL_CAPITAL)
	var rej: Dictionary = bm.call("ai_reject_counters", false) if bm.has_method("ai_reject_counters") else {}
	print(
		"POLREINF1_OUT days=%d d14/21/30/60/180=%d/%d/%d/%d/%d und60=%d und=%d berlin=%s warsaw=%s def_anchor=%d garrison_captured_src=%d illegal_ger=%d md5=%s"
		% [
			days, net14, net21, net30, net60, net180, und60, und, berlin, warsaw,
			int(rej.get("def_anchor", 0)), int(rej.get("garrison_captured_src", 0)), illegal, md5_d60,
		]
	)
	if net14 > 5:
		_fail("(a) GER net d14=%d want <=5" % net14)
	if net21 > 6:
		_fail("(a) GER net d21=%d want <=6" % net21)
	if net30 > 6:
		_fail("(a) GER net d30=%d want <=6" % net30)
	if net60 > 6:
		_fail("(a) GER net d60=%d want <=6" % net60)
	if und60 > 1:
		_fail("(a) undefended d60=%d want <=1" % und60)
	if illegal > 0:
		_fail("(e) A7 AI moved human GER units n=%d" % illegal)
	else:
		_pass("(e) A7 0 AI moves of human GER")
	if check_long:
		if net180 > 7:
			_fail("(b) GER net d180=%d want <=7" % net180)
		if und > 2:
			_fail("(b) undefended d180=%d want <=2" % und)
		if berlin != "GER":
			_fail("(b) Berlin flipped owner=%s" % berlin)
		if warsaw != "POL":
			_fail("(b) Warsaw flipped owner=%s" % warsaw)
		if net60 >= 0 and net180 > net60 + 1:
			_fail("(b) net grew after d60 %d -> %d" % [net60, net180])
		if net14 <= 5 and net21 <= 6 and net30 <= 6 and net60 <= 6 and und60 <= 1 and net180 <= 7 and und <= 2 and berlin == "GER" and warsaw == "POL":
			_pass("(a)(b) gerplayer d14/21/30/60/180=%d/%d/%d/%d/%d und=%d" % [net14, net21, net30, net60, net180, und])
	var _u := sm
	return {
		"net14": net14, "net21": net21, "net30": net30, "net60": net60, "net180": net180,
		"und60": und60, "und": und, "md5_d60": md5_d60, "illegal": illegal,
	}


func _advance_day(tm: Node, bm: Node) -> void:
	tm.call("advance_live_f5_equivalent_days", 1)
	# Live-F5-equiv queues attacker-win captures for BattleManager._process
	# (arm, then flush). This SceneTree script never idles, so apply now.
	if bm != null and bm.has_method("_flush_pending_light_captures"):
		bm.call("_flush_pending_light_captures")


func _log_pol_targets(mm: Node, bm: Node, lm: Node) -> void:
	if bm == null or not bm.has_method("_ai_border_targets"):
		return
	var rows: Array = bm.call("_ai_border_targets", "POL")
	var n := mini(rows.size(), 4)
	for i in range(n):
		if typeof(rows[i]) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = rows[i]
		var from_id := int(t.get("from_province_id", -1))
		var to_id := int(t.get("province_id", -1))
		var def_n := _tag_count_at(lm, "GER", to_id)
		var att_n := _tag_count_at(lm, "POL", from_id)
		print(
			"POLREINF1_TGT i=%d from=%d to=%d pol_n=%d ger_n=%d owner=%s"
			% [i, from_id, to_id, att_n, def_n, _owner(mm, to_id)]
		)


func _net(mm: Node, ger1936: Dictionary, pol1936: Dictionary) -> int:
	var ger_lost := 0
	var pol_lost := 0
	for pid_v in ger1936.keys():
		if _owner(mm, int(pid_v)) == "POL":
			ger_lost += 1
	for pid_v2 in pol1936.keys():
		if _owner(mm, int(pid_v2)) == "GER":
			pol_lost += 1
	return ger_lost - pol_lost


func _fill_owner_div(mm: Node, lm: Node, owners: Dictionary, counts: Dictionary) -> void:
	owners.clear()
	counts.clear()
	var provs: Variant = mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else {}
	if provs is Dictionary:
		for pid_v in (provs as Dictionary).keys():
			var pid := int(pid_v)
			var p: Object = mm.call("get_province", pid)
			if p == null or bool(p.get("is_sea")):
				continue
			owners[pid] = str(p.get("owner_tag")).strip_edges().to_upper()
			counts[pid] = 0
	for tag in ["GER", "POL"]:
		for f in lm.call("get_formations_for_country", tag):
			if f == null:
				continue
			var sid := int(f.stationed_province_id) if "stationed_province_id" in f else -1
			if counts.has(sid):
				counts[sid] = int(counts[sid]) + 1


func _count_illegal_ger_moves(mm: Node, lm: Node, prev: Dictionary) -> int:
	var n := 0
	var now := _ger_stations(lm)
	for fid_v in now.keys():
		var fid := str(fid_v)
		if not prev.has(fid):
			continue
		var old_sid := int(prev[fid])
		var sid := int(now[fid])
		if old_sid == sid:
			continue
		if _ctrl(mm, old_sid) != "GER":
			continue
		n += 1
	return n


func _ger_stations(lm: Node) -> Dictionary:
	var out: Dictionary = {}
	for f in lm.call("get_formations_for_country", "GER"):
		if f == null:
			continue
		out[str(f.formation_id)] = int(f.stationed_province_id)
	return out


func _owned_set(mm: Node, tag: String) -> Dictionary:
	var out: Dictionary = {}
	for pid_v in mm.call("get_provinces_by_owner", tag):
		var pid := int(pid_v)
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		out[pid] = true
	return out


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


func _spawn_live_oob(mm: Node, lm: Node) -> Dictionary:
	var scenario := _load_json(SCENARIO_PATH)
	var countries: Dictionary = {}
	var raw_c: Variant = scenario.get("countries", [])
	if raw_c is Array:
		for item in raw_c:
			if item is Dictionary:
				var tag := str((item as Dictionary).get("tag", "")).strip_edges().to_upper()
				if not tag.is_empty():
					countries[tag] = item
	var owners: Dictionary = {}
	for pid_v in mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else []:
		var p: Object = mm.call("get_province", int(pid_v)) if typeof(pid_v) != TYPE_OBJECT else pid_v
		if p == null:
			continue
		if bool(p.get("is_sea")):
			continue
		var ot := str(p.get("owner_tag")).strip_edges().to_upper()
		if ot.is_empty():
			continue
		var arr: Array = owners.get(ot, [])
		arr.append(int(p.get("id")))
		owners[ot] = arr
	if owners.is_empty() and mm.has_method("get_provinces_by_owner"):
		var seen: Dictionary = {}
		for pid2_v in mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else []:
			var p2: Object = mm.call("get_province", int(pid2_v))
			if p2 == null:
				continue
			var ot2 := str(p2.get("owner_tag")).strip_edges().to_upper()
			if ot2.is_empty() or seen.has(ot2):
				continue
			seen[ot2] = true
			var land: Array = []
			for pid3 in mm.call("get_provinces_by_owner", ot2):
				var p3: Object = mm.call("get_province", int(pid3))
				if p3 == null or bool(p3.get("is_sea")):
					continue
				land.append(int(pid3))
			owners[ot2] = land
	var tags: Array = owners.keys()
	tags.sort()
	var spawner_scr: GDScript = load("res://scripts/formations/FormationSpawner.gd") as GDScript
	var spawner = spawner_scr.new() if spawner_scr != null else null
	if spawner == null:
		_fail("FormationSpawner missing")
		return {}
	for tag_v in tags:
		var tag := str(tag_v)
		var owned_land: Array = owners.get(tag, [])
		if owned_land.is_empty():
			continue
		owned_land.sort()
		var count := 8 if tag in MAJOR_COUNT_TAGS else 4
		if countries.has(tag) and countries[tag] is Dictionary:
			if bool((countries[tag] as Dictionary).get("major_power", false)):
				count = 8
		var capital := -1
		var keys: Array = []
		if countries.has(tag) and countries[tag] is Dictionary:
			capital = int((countries[tag] as Dictionary).get("capital_province_id", -1))
			var kp: Variant = (countries[tag] as Dictionary).get("key_provinces", [])
			if kp is Array:
				keys = kp
		if capital <= 0 and lm.has_method("garrison_1936_capital_pids"):
			var caps: Array = lm.call("garrison_1936_capital_pids", tag)
			if not caps.is_empty():
				capital = int(caps[0])
		var border_ids := _collect_border_ids(mm, tag, owned_land)
		spawner.spawn_test_formations_for_country(tag, count, capital, owned_land, keys, border_ids)
	var chips := _apply_playable_chips(lm, mm)
	print("POLREINF1_SPAWN tags=%d chips=%s" % [tags.size(), str(chips)])
	return {"tags": tags.size(), "chips": chips}


func _apply_playable_chips(lm: Node, mm: Node) -> Dictionary:
	var ger_land: Array = _land_forms(lm, "GER")
	var fra_land: Array = _land_forms(lm, "FRA")
	var ger_nbr := -1
	if mm.has_method("get_adjacent_provinces"):
		for nv in mm.call("get_adjacent_provinces", GER_FRONT, true):
			var nid := int(nv)
			var np: Object = mm.call("get_province", nid)
			if np == null or bool(np.get("is_sea")):
				continue
			if str(np.get("owner_tag")).strip_edges().to_upper() == "GER":
				ger_nbr = nid
				break
	var ger_n := 0
	if ger_land.size() >= 1:
		ger_land[0].stationed_province_id = GER_FRONT
		ger_n += 1
	if ger_land.size() >= 2:
		ger_land[1].stationed_province_id = GER_FRONT
		ger_n += 1
	if ger_land.size() >= 3 and ger_nbr > 0:
		ger_land[2].stationed_province_id = ger_nbr
		ger_n += 1
	var fra_n := 0
	if fra_land.size() >= 1:
		fra_land[0].stationed_province_id = FRA_FRONT
		fra_n += 1
	if fra_land.size() >= 2:
		fra_land[1].stationed_province_id = FRA_FRONT
		fra_n += 1
	for row_v in CHIP_MAJORS:
		var row: Dictionary = row_v
		_station_major_chip(lm, str(row.get("tag", "")), int(row.get("pid", 0)), str(row.get("design", "")))
	return {"ger": ger_n, "fra": fra_n}


func _station_major_chip(lm: Node, tag: String, pid: int, design_id: String) -> void:
	if tag.is_empty() or pid <= 0:
		return
	var land: Array = _land_forms(lm, tag)
	var target: Object = null
	for f in land:
		if f != null and int(f.stationed_province_id) == pid:
			target = f
			break
	if target == null and not land.is_empty():
		target = land[land.size() - 1]
		if target != null:
			target.stationed_province_id = pid
	if target == null and lm.has_method("field_designed_unit"):
		lm.call("field_designed_unit", tag, design_id, pid, "land")


func _land_forms(lm: Node, tag: String) -> Array:
	var out: Array = []
	for f in lm.call("get_formations_for_country", tag):
		if f == null or bool(f.get_meta("garrison_1936", false)):
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft == "division" or ft == "garrison":
			out.append(f)
	return out


func _collect_border_ids(mm: Node, tag: String, owned_land: Array) -> Array:
	var owned_set: Dictionary = {}
	for raw in owned_land:
		owned_set[int(raw)] = true
	var out: Array = []
	var seen: Dictionary = {}
	for pidv in owned_land:
		var pid := int(pidv)
		if pid <= 0 or seen.has(pid):
			continue
		var is_border := false
		for nv in mm.call("get_adjacent_provinces", pid, true):
			var nid := int(nv)
			if owned_set.has(nid):
				continue
			var np: Object = mm.call("get_province", nid)
			if np == null or bool(np.get("is_sea")):
				continue
			var ot := str(np.get("owner_tag")).strip_edges().to_upper()
			if not ot.is_empty() and ot != tag:
				is_border = true
				break
		if is_border:
			seen[pid] = true
			out.append(pid)
	out.sort()
	return out


func _border_pair(mm: Node, ger: String, pol: String) -> Array[int]:
	var ids: Array[int] = []
	for pid_v in mm.call("get_provinces_by_owner", ger):
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


func _first_own_land_neighbor(mm: Node, pid: int, tag: String) -> int:
	var ids: Array[int] = []
	for nid_v in mm.call("get_adjacent_provinces", pid, true):
		ids.append(int(nid_v))
	ids.sort()
	for nid in ids:
		var np: Object = mm.call("get_province", nid)
		if np == null or bool(np.get("is_sea")):
			continue
		if str(np.get("owner_tag")).strip_edges().to_upper() == tag:
			return nid
	return -1


func _quiet_pol_pid(mm: Node, skip: Dictionary) -> int:
	var ids: Array[int] = []
	for pid_v in mm.call("get_provinces_by_owner", "POL"):
		ids.append(int(pid_v))
	ids.sort()
	for pid in ids:
		if bool(skip.get(pid, false)):
			continue
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		if _first_own_land_neighbor(mm, pid, "GER") > 0:
			continue
		return pid
	for pid2 in ids:
		if not bool(skip.get(pid2, false)):
			return pid2
	return -1


func _vacate_tag_at(lm: Node, tag: String, pid: int, dest: int) -> void:
	for f in lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		if int(f.stationed_province_id) == pid and dest > 0 and dest != pid:
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
	var gds: GDScript = load("res://scripts/formations/FormationMovement.gd") as GDScript
	if gds == null:
		return
	var rows_v: Variant = gds.call("list_marches")
	if typeof(rows_v) != TYPE_ARRAY:
		return
	for row_v in rows_v as Array:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var fid := str((row_v as Dictionary).get("formation_id", ""))
		if not fid.is_empty():
			gds.call("clear_march", fid)


func _occupy_pol_holes_except(mm: Node, lm: Node, ger_stations: Dictionary, keep: Dictionary) -> void:
	var seen: Dictionary = {}
	var n := 0
	for epid_v in ger_stations.keys():
		for nid_v in mm.call("get_adjacent_provinces", int(epid_v), true):
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
			n += 1
			_make_garr(lm, "polreinf1_hole_%d" % nid, "POL", nid, 1.0)
	var _u := n


func _tag_count_at(lm: Node, tag: String, pid: int) -> int:
	var n := 0
	for f in lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		if int(f.get("stationed_province_id")) == pid:
			n += 1
	return n


func _station_of(lm: Node, fid: String) -> int:
	var f: Object = lm.call("get_formation", fid) if lm.has_method("get_formation") else null
	if f == null:
		return -1
	return int(f.get("stationed_province_id"))


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


func _func_body(src: String, name: String) -> String:
	var needle := "func %s" % name
	var i := src.find(needle)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 1)
	if j < 0:
		j = src.length()
	return src.substr(i, j - i)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
