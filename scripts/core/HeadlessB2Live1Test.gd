extends SceneTree

## B2-LIVE-1: field-army skip is per-war and front-based so the 1936 start OOB
## does not disable the offensive ramp. Must FAIL on 95003ad3 and PASS on tip.
## Not wired into the gates runner.

const SRC_BM := "res://scripts/combat/BattleManager.gd"
const SCENARIO_PATH := "res://data/scenarios/world_accurate.json"
const GER_FRONT := 710173
const FRA_FRONT := 710739
const GER_CAPITAL := 710300
const MAJOR_COUNT_TAGS: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]
const CHIP_MAJORS: Array = [
	{"tag": "ENG", "pid": 711414, "design": "m4_sherman_medium_tank"},
	{"tag": "USA", "pid": 800792, "design": "m4_sherman_medium_tank"},
	{"tag": "SOV", "pid": 903534, "design": "t34_medium_tank"},
	{"tag": "ITA", "pid": 710963, "design": "cv33_tankette"},
	{"tag": "JAP", "pid": 903981, "design": "jap_armor_1936"},
	{"tag": "POL", "pid": 711112, "design": "pol_armor_1936"},
]
const BUDGET_TAGS: Array[String] = ["GER", "FRA", "ENG", "SOV", "ITA", "JAP", "USA", "POL", "CZE"]

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _gd: Node
var _live_fingerprint := ""
var _live_approx := false
var _budget_table: Dictionary = {}


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_AI_REJECT_LOG", "")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessB2Live1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessB2Live1Test: ", msg)


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
	_test_a1_live_oob_and_arm(mm, sm, bm, tm, lm)
	_test_a2_capital_raise(mm, sm, bm, lm)
	_test_a2b_capdef_on_front(mm, sm, bm, lm)
	_test_a3_cl1_style(mm, sm, bm, lm)
	_test_a4_garrison_only(mm, sm, bm, lm)
	_test_a5_real_front_army(mm, sm, bm, lm)
	_test_a6_per_pair(mm, sm, bm, lm)
	_test_b_save(mm, sm, bm, lm)
	_test_c1_epoch(mm, sm, bm, lm)
	_test_c2_threat_rebuild(mm, sm, bm, lm)
	_test_d1_phases(bm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessB2Live1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessB2Live1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _boot_as(mm: Node, sm: Node, bm: Node, lm: Node, player: String, observer: bool = false) -> bool:
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
	if observer:
		_war.set_campaign_observer(true)
	return true


func _test_a1_live_oob_and_arm(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	var spawned: Dictionary = _spawn_live_oob(mm, lm)
	var seeded: Dictionary = lm.call("seed_1936_start_garrisons", true)
	var placed := int(seeded.get("placed", -1))
	var skipped := int(seeded.get("skipped_occupied", -1))
	var targets := int(seeded.get("targets", -1))
	_live_fingerprint = "garrisons placed=%d skipped_occupied=%d targets=%d" % [placed, skipped, targets]
	_live_approx = not (placed == 536 and skipped == 40 and targets == 576)
	var arm := "LIVE" if not _live_approx else "LIVE-APPROX"
	print("B2LIVE1_SEED %s" % _live_fingerprint)
	print(
		"B2LIVE1_OOB mode=%s gerfield=%d polfield=%d garr=%d/%d/%d ger_land=%d chips_ger=%d chips_fra=%d"
		% [
			arm,
			_land_n(lm, "GER"),
			_land_n(lm, "POL"),
			placed,
			skipped,
			targets,
			int(spawned.get("ger_land", 0)),
			int(spawned.get("ger_chips", 0)),
			int(spawned.get("fra_chips", 0)),
		]
	)
	var ger_pol_n := _count_field_on_front(mm, lm, "GER", "POL")
	var ger_fra_n := _count_field_on_front(mm, lm, "GER", "FRA")
	print(
		"B2LIVE1_FRONT_ARMY ger_pol=%d ger_fra=%d FIELD_ARMY_FRONT_MIN=%d"
		% [ger_pol_n, ger_fra_n, _front_min(bm)]
	)
	if placed < 1 or targets != 576:
		_fail("A1 seed did not run placed=%d targets=%d" % [placed, targets])
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("A1 declare GER-POL failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("A1 no GER-POL border")
		return
	var from_id := int(pair[0])
	var to_id := int(pair[1])
	from_id = _single_stack_from(mm, lm, "GER", "POL", from_id)
	var fielded := _call_fielded(bm, "GER", "POL")
	print("B2LIVE1_A1 d0 fielded=%s from=%d to=%d" % [str(fielded), from_id, to_id])
	if fielded:
		_fail("A1 GER-vs-POL fielded at d0 on live OOB (B2 skipped)")
		return
	var ramp0: bool = bool(bm.call("_ai_offensive_ramp_ok", "GER", "POL", to_id, from_id))
	if ramp0:
		_fail("A1 ramp_ok true at war day < 21")
		return
	if bm.has_method("ai_reject_counters"):
		bm.call("ai_reject_counters", true)
	var cap_raised := false
	for day in range(1, 91):
		tm.call("advance_live_f5_equivalent_days", 1)
		if day == 21 or day == 30 or day == 60 or day == 90:
			_log_ramp(bm, lm, day, "GER", "POL")
			_log_ramp(bm, lm, day, "POL", "GER")
		if day == 21:
			var raised: bool = bool(bm.call("_raise_capital_garrison_at", "GER", GER_CAPITAL))
			print("B2LIVE1_CR d21 raise=%s" % str(raised))
			cap_raised = raised
			if _call_fielded(bm, "GER", "POL"):
				_fail("A1/LIVE-OOB GER-vs-POL SKIP_FIELDED after capdef raise at d21")
				return
			_log_ramp(bm, lm, 21, "GER", "POL")
		if day == 30:
			var rej: Dictionary = bm.call("ai_reject_counters", false) if bm.has_method("ai_reject_counters") else {}
			var ramp_n := int(rej.get("offensive_ramp", 0))
			print("B2LIVE1_A1 d30 offensive_ramp=%d" % ramp_n)
			if ramp_n <= 0:
				_fail("A1 live OOB 30d aivai offensive_ramp=%d (B2 did not fire)" % ramp_n)
				return
	if not cap_raised:
		_fail("LIVE-OOB capital raise at d21 did not field capdef_GER_710300")
		return
	_pass("A1 live OOB not fielded; B2 fires d21-90; capdef raise does not skip")


func _test_a2_capital_raise(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("A2 declare failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("A2 no border")
		return
	if not bool(bm.call("_raise_capital_garrison_at", "GER", GER_CAPITAL)):
		_fail("A2 raise capdef_GER_710300 failed")
		return
	if _call_fielded(bm, "GER", "POL"):
		_fail("A2 capdef capital raise counted as field army")
		return
	var from_id := _single_stack_from(mm, lm, "GER", "POL", int(pair[0]))
	var ramp_ok: bool = bool(bm.call("_ai_offensive_ramp_ok", "GER", "POL", int(pair[1]), from_id))
	if ramp_ok:
		_fail("A2 ramp_ok true after capdef raise during hold")
		return
	_pass("A2 capdef capital raise does not skip B2")
	var _u := sm


func _test_a2b_capdef_on_front(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("A2b declare failed")
		return
	var front := _hexes_facing(mm, "GER", "POL")
	if front.size() < 3:
		_fail("A2b GER-POL front size %d" % front.size())
		return
	var n := 0
	for pid in front:
		if n >= 4:
			break
		if not _field_capdef_at(lm, "GER", int(pid), n):
			_fail("A2b could not station capdef on %d" % int(pid))
			return
		n += 1
	if n < 3:
		_fail("A2b stationed %d capdef on front want >=3" % n)
		return
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "GER")
	if _call_fielded(bm, "GER", "POL"):
		_fail("A2b %d capdef_* on GER-POL front counted as field army" % n)
		return
	_pass("A2b capdef_* never counts toward FIELD_ARMY_FRONT_MIN even with %d on front" % n)
	var _u2 := sm


func _test_a3_cl1_style(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("A3 declare failed")
		return
	var front := _hexes_facing(mm, "GER", "POL")
	if front.is_empty():
		_fail("A3 no GER-POL front")
		return
	_boot.make_division("cl1_GER_%d" % int(front[0]), "GER", int(front[0]))
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "GER")
	if _call_fielded(bm, "GER", "POL"):
		_fail("A3 a single cl1_* hex counted as committed (FIELD_ARMY_FRONT_MIN bypassed)")
		return
	var n := 0
	for pid in front:
		_boot.make_division("cl1_GER_%d" % int(pid), "GER", int(pid))
		n += 1
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "GER")
	if not _call_fielded(bm, "GER", "POL"):
		_fail("A3 CL1-style every-border-hex not fielded n=%d" % n)
		return
	var pair := _border_pair(mm, "GER", "POL")
	var ramp_ok: bool = bool(bm.call("_ai_offensive_ramp_ok", "GER", "POL", int(pair[1]), int(pair[0])))
	if not ramp_ok:
		_fail("A3 ramp_ok false at war day 5-equivalent with CL1 field army")
		return
	_pass("A3 CL1-style border divisions still count as committed n=%d" % n)
	var _u3 := sm


func _test_a4_garrison_only(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("A4 declare failed")
		return
	if _call_fielded(bm, "GER", "POL"):
		_fail("A4 garrison-only counted as fielded")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("A4 no border")
		return
	var tm: Node = get_root().get_node_or_null("TimeManager")
	if tm != null:
		tm.call("advance_live_f5_equivalent_days", 10)
	var from_id := _single_stack_from(mm, lm, "GER", "POL", int(pair[0]))
	var ramp_ok: bool = bool(bm.call("_ai_offensive_ramp_ok", "GER", "POL", int(pair[1]), from_id))
	if ramp_ok:
		_fail("A4 ramp_ok true at war day 10 (hold should apply)")
		return
	_pass("A4 garrison-only not fielded; ramp holds at day 10")
	var _u4 := sm


func _test_a5_real_front_army(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("A5 declare failed")
		return
	var front := _hexes_facing(mm, "GER", "POL")
	var min_n := _front_min(bm)
	if front.size() < min_n:
		_fail("A5 front size %d < FIELD_ARMY_FRONT_MIN %d" % [front.size(), min_n])
		return
	for i in range(min_n - 1):
		_boot.make_division("field_GER_%d" % i, "GER", int(front[i]))
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "GER")
	if _call_fielded(bm, "GER", "POL"):
		_fail("A5 %d front divisions counted as fielded (min=%d)" % [min_n - 1, min_n])
		return
	_boot.make_division("field_GER_%d" % (min_n - 1), "GER", int(front[min_n - 1]))
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "GER")
	if not _call_fielded(bm, "GER", "POL"):
		_fail("A5 %d non-garrison front divisions not fielded" % min_n)
		return
	_pass("A5 FIELD_ARMY_FRONT_MIN=%d real front army is fielded" % min_n)
	var _u5 := sm


func _test_a6_per_pair(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("A6 declare POL failed")
		return
	if not bool(_war.declare_war("GER", "FRA", "test").get("ok", false)):
		_fail("A6 declare FRA failed")
		return
	_boot.make_division("maginot_GER_a", "GER", GER_FRONT)
	_boot.make_division("maginot_GER_b", "GER", GER_FRONT)
	var ger_nbr := -1
	for nv in mm.call("get_adjacent_provinces", GER_FRONT, true):
		var nid := int(nv)
		var np: Object = mm.call("get_province", nid)
		if np == null or bool(np.get("is_sea")):
			continue
		if str(np.get("owner_tag")).strip_edges().to_upper() == "GER":
			ger_nbr = nid
			break
	if ger_nbr > 0:
		_boot.make_division("maginot_GER_c", "GER", ger_nbr)
	if bm.has_method("bump_ai_station_gen"):
		bm.call("bump_ai_station_gen", "GER")
	if _call_fielded(bm, "GER", "POL"):
		_fail("A6 Maginot chips made GER-vs-POL fielded")
		return
	_pass("A6 GER Maginot chips do not field GER-vs-POL")
	var _u6 := sm


func _test_b_save(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	var fresh: Dictionary = {}
	for tag in BUDGET_TAGS:
		fresh[tag] = int(bm.call("_ai_raise_budget", tag))
	_budget_table = fresh.duplicate()
	print("B2LIVE1_B1_FRESH_BUDGET %s" % str(fresh))
	var seed_before: Dictionary = _seed_n_copy()
	var form_n := _formation_count(lm)
	for i in range(3):
		if not bool(bm.call("_raise_garrison_at", "CZE", 710146)):
			_fail("B1 CZE raise %d failed" % i)
			return
	var gd_blob: Dictionary = _gd.call("get_save_data")
	var lm_blob: Dictionary = lm.call("get_save_data")
	gd_blob.erase("garrison_seed_n")
	lm_blob.erase("garrisons_1936_seeded")
	var form_n_raised := _formation_count(lm)
	_gd.call("clear_for_load")
	if lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	if "_garrisons_1936_seeded" in lm:
		lm._garrisons_1936_seeded = false
	_gd.call("apply_save_data", gd_blob)
	lm.call("apply_save_data", lm_blob)
	var ps_after: Variant = _gd.get("peace_state")
	var after_seed: Variant = (ps_after as Dictionary).get("garrison_seed_n", {}) if ps_after is Dictionary else {}
	if after_seed is Dictionary and not (after_seed as Dictionary).is_empty():
		var back := after_seed as Dictionary
		if int(back.get("CZE", 0)) != int(seed_before.get("CZE", -1)):
			_fail("B1 peace_state garrison_seed_n back-filled from units CZE=%s want %s" % [str(back.get("CZE")), str(seed_before.get("CZE"))])
			return
	var old_budget := int(bm.call("_ai_raise_budget", "CZE"))
	var want := int(fresh.get("CZE", -1))
	print("B2LIVE1_B1 CZE budget old-save=%d fresh=%d seed_n=%s" % [old_budget, want, str(after_seed)])
	if old_budget != want:
		_fail("B1 CZE budget %d != fresh %d (old save counted raises)" % [old_budget, want])
	else:
		print("B2LIVE1_B1_BUDGET_TABLE %s" % str(fresh))
		_pass("B1 old-format save budget matches fresh; not back-filled")
	var again: Dictionary = lm.call("seed_1936_start_garrisons", false)
	if not bool(again.get("already", false)):
		_fail("B2 Continue seed_1936_start_garrisons(false) already=%s" % str(again.get("already")))
	var seed_after: Dictionary = _seed_n_copy()
	if after_seed is Dictionary:
		if seed_after.hash() != _seed_n_copy_from(after_seed as Dictionary).hash():
			_fail("B2 garrison_seed_n changed on Continue seed")
	var form_after := _formation_count(lm)
	if form_after != form_n_raised:
		_fail("B2 formation count %d != %d after Continue seed" % [form_after, form_n_raised])
	if bool(again.get("already", false)) and form_after == form_n_raised:
		_pass("B2 Continue seed already=true; seed_n and formation count unchanged")
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	var gd2: Dictionary = _gd.call("get_save_data")
	var lm2: Dictionary = lm.call("get_save_data")
	if not gd2.has("garrison_seed_n"):
		_fail("B3 new-format GameData missing garrison_seed_n")
		return
	if not lm2.has("garrisons_1936_seeded"):
		_fail("B3 new-format LeaderManager missing garrisons_1936_seeded")
		return
	_gd.call("clear_for_load")
	if lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	_gd.call("apply_save_data", gd2)
	lm.call("apply_save_data", lm2)
	var gd3: Dictionary = _gd.call("get_save_data")
	var lm3: Dictionary = lm.call("get_save_data")
	if not gd3.has("garrison_seed_n") or not lm3.has("garrisons_1936_seeded"):
		_fail("B3 keys dropped on round-trip")
		return
	if not bool(lm3.get("garrisons_1936_seeded", false)):
		_fail("B3 garrisons_1936_seeded not preserved true")
		return
	_pass("B3 new-format both keys preserved")
	var _u7 := [sm, form_n]


func _test_c1_epoch(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("C1 declare failed")
		return
	var pair := _border_pair(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("C1 no border")
		return
	var e0 := int(bm.get("_ai_board_epoch"))
	bm.call("_apply_attacker_win_capture_light", "GER", int(pair[1]), int(pair[0]), "")
	var e1 := int(bm.get("_ai_board_epoch"))
	var delta := e1 - e0
	print("B2LIVE1_C1 epoch %d -> %d delta=%d" % [e0, e1, delta])
	if delta != 1:
		_fail("C1 light capture epoch delta=%d want 1 (double bump on base)" % delta)
		return
	_pass("C1 light capture bumps _ai_board_epoch exactly 1")
	var _u8 := sm


func _test_c2_threat_rebuild(mm: Node, sm: Node, bm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA", true):
		return
	lm.call("seed_1936_start_garrisons", true)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("C2 declare failed")
		return
	if not bm.has_method("ai_threat_cache_counts"):
		_fail("C2 ai_threat_cache_counts missing")
		return
	var before_map := _station_map(lm, "GER")
	if bm.has_method("reset_ai_threat_cache_counts"):
		bm.call("reset_ai_threat_cache_counts")
	if bm.has_method("set_ai_threat_cache_enabled"):
		bm.call("set_ai_threat_cache_enabled", true)
	var cover: Dictionary = bm.call("try_ai_cover_threatened_borders")
	var pair := _border_pair(mm, "GER", "POL")
	var pid := int(pair[0]) if pair.size() >= 1 else 711058
	bm.call("_ai_local_threat", pid, "GER")
	var counts: Dictionary = bm.call("ai_threat_cache_counts")
	var rebuilds := int(counts.get("rebuilds", -1))
	var scanned := int(counts.get("scanned", -1))
	var own_n := _own_land_n(mm, "GER")
	var after_map := _station_map(lm, "GER")
	print(
		"B2LIVE1_C2 rebuilds=%d scanned=%d own_land=%d moved=%s raised=%s stations_equal=%s"
		% [rebuilds, scanned, own_n, str(cover.get("moved", -1)), str(cover.get("raised", -1)), str(before_map.hash() == after_map.hash())]
	)
	if scanned < 0:
		_fail("C2 scanned-hex count missing (full per-tag rescan on base)")
		return
	if own_n > 0 and scanned >= own_n:
		_fail("C2 scanned=%d >= own_land=%d (did not limit to front)" % [scanned, own_n])
		return
	if rebuilds > 8:
		_fail("C2 rebuilds=%d too high (COVER invalidated every hole fill)" % rebuilds)
		return
	_pass("C2 threat rebuild limited to front scanned=%d own=%d rebuilds=%d" % [scanned, own_n, rebuilds])
	var _u9 := sm


func _test_d1_phases(bm: Node) -> void:
	var end_d := int(bm.get("RAMP_END_DAYS"))
	if end_d != 90:
		_fail("D1 RAMP_END_DAYS=%d want 90" % end_d)
		return
	var phases_v: Variant = bm.get("RAMP_PHASES")
	if not (phases_v is Array):
		_fail("D1 RAMP_PHASES missing")
		return
	for raw in phases_v:
		if not (raw is Array) or (raw as Array).size() < 2:
			continue
		var start_d := int((raw as Array)[0])
		if start_d >= end_d:
			_fail("D1 unreachable phase start %d >= RAMP_END_DAYS %d" % [start_d, end_d])
			return
	_pass("D1 no phase start >= RAMP_END_DAYS 90")


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
		_fail("A1 FormationSpawner missing")
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
	var ger_land := _land_n(lm, "GER")
	print("B2LIVE1_SPAWN tags=%d ger_land=%d chips=%s" % [tags.size(), ger_land, str(chips)])
	return {
		"ger_land": ger_land,
		"ger_chips": int(chips.get("ger", 0)),
		"fra_chips": int(chips.get("fra", 0)),
		"tags": tags.size(),
	}


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


func _apply_maginot_chips(lm: Node, mm: Node) -> void:
	var ger_land: Array = _land_forms(lm, "GER")
	var ger_nbr := -1
	for nv in mm.call("get_adjacent_provinces", GER_FRONT, true):
		var nid := int(nv)
		var np: Object = mm.call("get_province", nid)
		if np == null or bool(np.get("is_sea")):
			continue
		if str(np.get("owner_tag")).strip_edges().to_upper() == "GER":
			ger_nbr = nid
			break
	if ger_land.size() >= 1:
		ger_land[0].stationed_province_id = GER_FRONT
	if ger_land.size() >= 2:
		ger_land[1].stationed_province_id = GER_FRONT
	if ger_land.size() >= 3 and ger_nbr > 0:
		ger_land[2].stationed_province_id = ger_nbr


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


func _land_n(lm: Node, tag: String) -> int:
	return _land_forms(lm, tag).size()


func _count_field_on_front(mm: Node, lm: Node, tag: String, foe: String) -> int:
	var front: Dictionary = {}
	for pid in _hexes_facing(mm, tag, foe):
		front[int(pid)] = true
	var n := 0
	for f in _land_forms(lm, tag):
		if f == null:
			continue
		var fid := str(f.formation_id)
		if fid.begins_with("capdef_"):
			continue
		var sid := int(f.stationed_province_id) if "stationed_province_id" in f else -1
		if front.has(sid):
			n += 1
	return n


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


func _call_fielded(bm: Node, tag: String, def_tag: String) -> bool:
	if not bm.has_method("_ai_has_committed_field_army"):
		return false
	var src := FileAccess.get_file_as_string(SRC_BM)
	if "func _ai_has_committed_field_army(tag: String, def_tag: String)" in src:
		return bool(bm.call("_ai_has_committed_field_army", tag, def_tag))
	return bool(bm.call("_ai_has_committed_field_army", tag))


func _front_min(bm: Node) -> int:
	var v: Variant = bm.get("FIELD_ARMY_FRONT_MIN")
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return 3


func _log_ramp(bm: Node, lm: Node, day: int, tag: String, foe: String) -> void:
	var fielded := _call_fielded(bm, tag, foe)
	var fielded_by := _first_fielded_by(lm, tag, foe, fielded)
	var wd := int(bm.call("_ai_war_day", tag, foe)) if bm.has_method("_ai_war_day") else -1
	var sr := 0.0
	if typeof(_war) != TYPE_NIL:
		sr = float(_war.military_strength(tag)) / maxf(float(_war.military_strength(foe)), 1.0)
	var gap := int(bm.call("_ai_ramp_gap", wd)) if bm.has_method("_ai_ramp_gap") else -1
	var last_cap := int(bm.call("_ai_last_new_capture_day", tag, foe)) if bm.has_method("_ai_last_new_capture_day") else 0
	var day_now := int(bm.call("_ai_day")) if bm.has_method("_ai_day") else day
	var ready := day_now - last_cap >= gap
	var phase := _ramp_phase(tag, fielded, sr, wd)
	var rej := 0
	if bm.has_method("ai_reject_counters"):
		rej = int(bm.call("ai_reject_counters", false).get("offensive_ramp", 0))
	print(
		"B2LIVE1_RAMP day=%d tag=%s foe=%s fielded=%s fielded_by=%s wd=%d sr=%.3f phase=%s gap=%d last_cap=%d ready=%s rej_ramp=%d"
		% [day, tag, foe, str(fielded), fielded_by, wd, sr, phase, gap, last_cap, str(ready), rej]
	)


func _ramp_phase(tag: String, fielded: bool, sr: float, wd: int) -> String:
	if typeof(_war) != TYPE_NIL and _war._is_player_or_human_nation(tag):
		return "PLAYER"
	if fielded:
		return "SKIP_FIELDED"
	if sr < 1.0:
		return "OPEN_SR<1"
	if wd >= 90:
		return "EXPIRED"
	if wd < 21:
		return "HOLD"
	return "GAP"


func _first_fielded_by(lm: Node, tag: String, foe: String, fielded: bool) -> String:
	if not fielded:
		return "-"
	for f in lm.call("get_formations_for_country", tag):
		if f == null or bool(f.get_meta("garrison_1936", false)):
			continue
		var fid := str(f.formation_id)
		if fid.begins_with("capdef_"):
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft != "division" and ft != "garrison":
			continue
		var sid := int(f.stationed_province_id) if "stationed_province_id" in f else -1
		if sid <= 0:
			continue
		return "%s:%s@%d" % [fid, ft, sid]
	for f2 in lm.call("get_formations_for_country", tag):
		if f2 == null or bool(f2.get_meta("garrison_1936", false)):
			continue
		var sid2 := int(f2.stationed_province_id) if "stationed_province_id" in f2 else -1
		if sid2 > 0:
			return "%s:%s@%d" % [str(f2.formation_id), str(f2.formation_type), sid2]
	var _u := foe
	return "-"


func _field_capdef_at(lm: Node, tag: String, pid: int, n: int) -> bool:
	if not lm.has_method("field_designed_unit"):
		return false
	var fid := "capdef_%s_%d" % [tag, pid] if n == 0 else "capdef_%s_%d_%d" % [tag, pid, n + 1]
	var fielded: Dictionary = lm.call("field_designed_unit", tag, "infantry_1936", pid, "land", {
		"formation_id": fid,
		"skip_leader": true,
		"quiet": true,
		"force_new": true,
	})
	return bool(fielded.get("ok", false))


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


func _first_own_land_neighbor(mm: Node, pid: int, tag: String) -> int:
	var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
	var ids: Array[int] = []
	for nid_v in nbrs:
		ids.append(int(nid_v))
	ids.sort()
	for nid in ids:
		var np: Object = mm.call("get_province", nid)
		if np == null or bool(np.get("is_sea")):
			continue
		if str(np.get("owner_tag")).strip_edges().to_upper() == tag:
			return nid
	return -1


func _single_stack_from(mm: Node, lm: Node, tag: String, foe: String, fallback: int) -> int:
	var front := _hexes_facing(mm, tag, foe)
	for pid in front:
		var n := 0
		for f in lm.call("get_formations_for_country", tag):
			if f == null:
				continue
			if int(f.stationed_province_id) == int(pid):
				n += 1
		if n == 1:
			return int(pid)
	return fallback


func _seed_n_copy() -> Dictionary:
	if _gd == null:
		return {}
	var ps: Variant = _gd.get("peace_state")
	if not (ps is Dictionary):
		return {}
	var v: Variant = (ps as Dictionary).get("garrison_seed_n", {})
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	return {}


func _seed_n_copy_from(v: Dictionary) -> Dictionary:
	return v.duplicate(true)


func _formation_count(lm: Node) -> int:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		return (lm.formations as Dictionary).size()
	return 0


func _station_map(lm: Node, tag: String) -> Dictionary:
	var out: Dictionary = {}
	for f in lm.call("get_formations_for_country", tag):
		if f == null:
			continue
		out[str(f.formation_id)] = int(f.stationed_province_id)
	return out


func _own_land_n(mm: Node, tag: String) -> int:
	var n := 0
	for pid_v in mm.call("get_provinces_by_owner", tag):
		var p: Object = mm.call("get_province", int(pid_v))
		if p == null or bool(p.get("is_sea")):
			continue
		n += 1
	return n


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
