extends SceneTree

## AI-WAR-1: stalemate peace, stall massing, garrison, retake cooldown,
## observer Simulation ended, reject counters, democracy guard.

const SRC_WAR := "res://scripts/core/WarStateDomain.gd"
const SRC_BM := "res://scripts/combat/BattleManager.gd"
const SRC_AI := "res://scripts/combat/LandBattleAi.gd"
const SRC_END := "res://scripts/core/CampaignEndDomain.gd"
const SRC_TM := "res://scripts/autoload/TimeManager.gd"

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _ai: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_LIVE_F5_EQUIV", "1")
	OS.set_environment("EOA_AI_REJECT_LOG", "")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAiWar1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAiWar1Test: ", msg)


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
	_ai = load("res://scripts/combat/LandBattleAi.gd") as GDScript
	if mm == null or bm == null or tm == null or lm == null or _boot == null or _war == null:
		_fail("autoloads missing")
		_finish()
		return
	_assert_source()
	_test_stalemate(mm, sm, bm, tm, lm)
	_test_stall_mass(mm, sm, bm, tm, lm)
	_test_garrison(mm, sm, bm, tm, lm)
	_test_retake_cooldown(mm, sm, bm, tm, lm)
	_test_observer(mm, sm, bm, tm, lm)
	_test_reject_counters(mm, sm, bm, tm, lm)
	_test_democracy_guard(mm, sm, bm, tm, lm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAiWar1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAiWar1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _assert_source() -> void:
	var war_src := FileAccess.get_file_as_string(SRC_WAR)
	var bm_src := FileAccess.get_file_as_string(SRC_BM)
	var ai_src := FileAccess.get_file_as_string(SRC_AI)
	var end_src := FileAccess.get_file_as_string(SRC_END)
	var tm_src := FileAccess.get_file_as_string(SRC_TM)
	if "func try_ai_stalemate_peace" not in war_src:
		_fail("mutant: try_ai_stalemate_peace missing")
		return
	if "try_ai_stalemate_peace" not in tm_src:
		_fail("mutant: TimeManager missing stalemate hook")
		return
	if "Simulation ended" not in end_src:
		_fail("mutant: observer Simulation ended missing")
		return
	if "MIN_AGGRESSION_TO_START := 0.45" not in ai_src:
		_fail("mutant: MIN_AGGRESSION_TO_START not 0.45")
		return
	if "retake_cooldown" not in bm_src or "follow_on_blocked_garrison" not in bm_src:
		_fail("mutant: garrison/cooldown/reject missing from BattleManager")
		return
	if "EOA_AI_REJECT_LOG" not in war_src or "EOA_AI_REJECT_LOG" not in bm_src:
		_fail("mutant: reject log flag missing")
		return
	if "print(" in war_src:
		var reject_print := war_src.find("EOA_AI_REJECT")
		if reject_print < 0:
			_fail("WarStateDomain has prints but no reject-log marker")
			return
	_pass("source mutants killed")


func _boot_as(mm: Node, sm: Node, bm: Node, lm: Node, player: String) -> bool:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
		if "_empty_hex_siege" in bm:
			bm._empty_hex_siege = {}
		if bm.has_method("reset_ai_war1_for_test"):
			bm.reset_ai_war1_for_test()
		if bm.has_method("ai_reject_counters"):
			bm.ai_reject_counters(true)
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
	var sp := get_root().get_node_or_null("SessionPlayers")
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", player)
	return true


func _test_stalemate(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	var product_n := int(_war.rules().get("stalemate_white_peace_days", 0))
	if product_n != 180:
		_fail("product stalemate_white_peace_days want 180 got %d" % product_n)
		return
	_war.set_rule_overrides({"stalemate_white_peace_days": 10})
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("stalemate declare GER-POL failed")
		return
	var pair := _first_border(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("stalemate no GER-POL border")
		return
	var pol_pid := int(pair[1])
	var owner_before := str(mm.call("get_province", pol_pid).get("owner_tag"))
	tm.total_days_elapsed = 10
	var peaced: Array = _war.try_ai_stalemate_peace(10)
	if peaced.is_empty():
		_fail("AI-AI war did not stalemate-peace after N=10")
		return
	if _war.is_at_war("GER", "POL"):
		_fail("GER-POL still at war after stalemate")
		return
	if not _war.in_truce("GER", "POL"):
		_fail("stalemate did not write truce")
		return
	if not (bm.get_open_land_battles() as Array).is_empty():
		_fail("stalemate left open fights")
		return
	var owner_after := str(mm.call("get_province", pol_pid).get("owner_tag"))
	if owner_after != owner_before:
		_fail("stalemate changed owners %s -> %s" % [owner_before, owner_after])
		return
	var just: Dictionary = _justifies()
	if just.has("GER>POL") or just.has("POL>GER"):
		_fail("stalemate left pair justifies %s" % str(just.keys()))
		return
	var log_ok := false
	for row_v in _war_log():
		if row_v is Dictionary and str((row_v as Dictionary).get("reason", "")) == "stalemate":
			log_ok = true
			break
	if not log_ok:
		_fail("stalemate reason missing from war log")
		return
	_pass("stalemate AI-AI peace reason=stalemate owners held")

	if not _boot_as(mm, sm, bm, lm, "GER"):
		return
	_war.set_rule_overrides({"stalemate_white_peace_days": 10})
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("player-war declare failed")
		return
	tm.total_days_elapsed = 10
	var player_peace: Array = _war.try_ai_stalemate_peace(10)
	if not player_peace.is_empty() or not _war.is_at_war("GER", "POL"):
		_fail("player war auto-peaced")
		return
	_pass("player war does not stalemate-peace")

	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	_war.set_rule_overrides({"stalemate_white_peace_days": 10})
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("mid-fight declare failed")
		return
	var border := _first_border(mm, "GER", "POL")
	if border.size() < 2:
		_fail("mid-fight no border")
		return
	_boot.make_division("aiw1_ger", "GER", int(border[0]))
	_boot.make_division("aiw1_pol", "POL", int(border[1]))
	var opened: Dictionary = bm.call("start_land_battle", "GER", int(border[1]), int(border[0]), "aiw1_ger")
	if not bool(opened.get("opened", false)):
		_fail("mid-fight did not open %s" % str(opened))
		return
	tm.total_days_elapsed = 10
	var mid: Array = _war.try_ai_stalemate_peace(10)
	if not mid.is_empty() or not _war.is_at_war("GER", "POL"):
		_fail("mid-fight war auto-peaced")
		return
	_pass("open fight blocks stalemate peace")


func _test_stall_mass(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	_war.set_rule_overrides({"ai_attack_stall_days": 2})
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("stall declare failed")
		return
	var pair := _first_border(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("stall no border")
		return
	var from_id := int(pair[0])
	var to_id := int(pair[1])
	_boot.make_division("aiw1_stall_ger", "GER", from_id)
	_boot.make_division("aiw1_stall_pol", "POL", to_id)
	_garrison_neighbors(mm, from_id, "POL")
	var spare := _adjacent_own(mm, from_id, "GER")
	if spare > 0:
		_boot.make_division("aiw1_stall_spare", "GER", spare)
	tm.total_days_elapsed = 0
	var ratio0 := float(bm.call("_ai_min_attack_ratio", "GER"))
	if absf(ratio0 - 1.5) > 0.0001:
		_fail("ratio before stall want 1.5 got %s" % str(ratio0))
		return
	tm.total_days_elapsed = 2
	var ratio2 := float(bm.call("_ai_min_attack_ratio", "GER"))
	if absf(ratio2 - 1.2) > 0.0001:
		_fail("ratio after 2-day stall want 1.2 got %s" % str(ratio2))
		return
	var under: Array = [{
		"tag": "GER",
		"from_id": from_id,
		"to_id": to_id,
		"defender_tag": "POL",
		"formation_id": "aiw1_stall_ger",
		"has_formation": true,
		"empty_hex": false,
		"attacker_power": 80.0,
		"defender_power": 80.0,
		"min_ratio": 1.2,
	}]
	bm.call("_ai_refresh_massing_commits", under, 2)
	var stall_row: Dictionary = {}
	if "_ai_stall" in bm and (bm._ai_stall as Dictionary).has("GER"):
		stall_row = (bm._ai_stall as Dictionary)["GER"]
	var commit := int(stall_row.get("commit_to_id", -1))
	if commit != to_id:
		_fail("stalled GER did not commit to one hex want %d got %s" % [to_id, str(stall_row)])
		return
	var blob: Dictionary = bm.call("get_save_data")
	if not (blob.get("ai_stall") is Dictionary) or not (blob["ai_stall"] as Dictionary).has("GER"):
		_fail("ai_stall missing from BattleManager save blob")
		return
	bm.call("reset_ai_war1_for_test")
	bm.call("apply_save_data", blob)
	var restored: Dictionary = {}
	if "_ai_stall" in bm and (bm._ai_stall as Dictionary).has("GER"):
		restored = (bm._ai_stall as Dictionary)["GER"]
	if int(restored.get("commit_to_id", -1)) != commit:
		_fail("stall commit did not round-trip save/load saved=%s restored=%s" % [str(blob.get("ai_stall")), str(restored)])
		return
	tm.total_days_elapsed = 2 + 30
	var ratio3 := float(bm.call("_ai_min_attack_ratio", "GER"))
	if absf(ratio3 - 1.0) > 0.0001:
		_fail("ratio after extra 30 stall days want 1.0 got %s stall=%s" % [str(ratio3), str(restored)])
		return
	tm.total_days_elapsed = 2
	var day2: Dictionary = bm.call("try_ai_start_land_battles", 2)
	var dests: Dictionary = {}
	for raw in day2.get("marched", []):
		if raw is Dictionary:
			dests[int((raw as Dictionary).get("dest_id", -1))] = true
	if dests.size() > 1:
		_fail("massing sprayed dests %s" % str(dests.keys()))
		return
	_pass("stall relax 1.2 then 1.0, one-hex commit saved")


func _test_garrison(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("garrison declare failed")
		return
	var pair := _first_border(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("garrison no border")
		return
	var from_id := int(pair[0])
	var to_id := int(pair[1])
	_boot.make_division("aiw1_garr_ger", "GER", from_id)
	bm.call("_apply_attacker_win_capture_light", "GER", to_id, from_id, "aiw1_garr_ger")
	var f: Object = lm.call("get_formation", "aiw1_garr_ger") if lm.has_method("get_formation") else null
	if f == null or int(f.get("stationed_province_id")) != to_id:
		_fail("winner did not stay on captured hex")
		return
	var on_hex := (bm.call("get_divisions_at_province", to_id, "GER") as Array).size()
	if on_hex < 1:
		_fail("captured hex empty after win")
		return
	bm._last_land_aar = {
		"winner": "attacker",
		"tag": "GER",
		"fid": "aiw1_garr_ger",
		"from_id": to_id,
		"next_pid": from_id,
		"att_tag": "GER",
	}
	var follow: Dictionary = bm.call("try_ai_follow_on_after_win", "USA")
	if int(follow.get("started_n", 1)) != 0:
		_fail("follow-on started without a garrison buddy %s" % str(follow))
		return
	var counters: Dictionary = bm.call("ai_reject_counters")
	if int(counters.get("follow_on_blocked_garrison", 0)) <= 0:
		_fail("follow_on_blocked_garrison counter not incremented")
		return
	_boot.make_division("aiw1_garr_buddy", "GER", to_id)
	var follow2: Dictionary = bm.call("try_ai_follow_on_after_win", "USA")
	# Buddy present: follow-on may start or fail for other reasons (from_id is GER land).
	# The garrison rule must not block when a second division holds the hex.
	if str(follow2.get("reason", "")) == "garrison":
		_fail("follow-on still garrison-blocked with a buddy on the hex")
		return
	_pass("garrison: winner stays, follow-on blocked without buddy")


func _test_retake_cooldown(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	_war.set_rule_overrides({"ai_retake_cooldown_days": 7})
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("cooldown declare GER-POL failed")
		return
	if not bool(_war.declare_war("SOV", "GER", "test").get("ok", false)):
		# max_wars=1 may block SOV-GER; override for the third-party check
		_war.set_rule_overrides({"ai_retake_cooldown_days": 7, "ai_max_wars": 2})
		_war.declare_war("SOV", "GER", "test")
	var pair := _first_border(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("cooldown no border")
		return
	var from_id := int(pair[0])
	var to_id := int(pair[1])
	_boot.make_division("aiw1_cd_ger", "GER", from_id)
	tm.total_days_elapsed = 1
	bm.call("_apply_attacker_win_capture_light", "GER", to_id, from_id, "aiw1_cd_ger")
	if not bool(bm.call("_retake_blocked_for", "POL", to_id)):
		_fail("previous owner POL not on retake cooldown")
		return
	if bool(bm.call("_retake_blocked_for", "SOV", to_id)):
		_fail("third party SOV blocked by retake cooldown")
		return
	_boot.make_division("aiw1_cd_pol", "POL", from_id)
	var day7: Dictionary = bm.call("can_assault_province", "POL", to_id, from_id)
	tm.total_days_elapsed = 7
	var still: Dictionary = bm.call("can_assault_province", "POL", to_id, from_id)
	if bool(still.get("ok", true)) and str(still.get("reason", "")).find("cooldown") < 0:
		# POL may fail for other reasons, but cooldown must still apply on day 7.
		if not bool(bm.call("_retake_blocked_for", "POL", to_id)):
			_fail("cooldown expired before day 8 (day=7)")
			return
	tm.total_days_elapsed = 8
	if bool(bm.call("_retake_blocked_for", "POL", to_id)):
		_fail("cooldown still blocking POL on day 8")
		return
	var blob: Dictionary = bm.call("get_save_data")
	if not (blob.get("retake_cooldown") is Dictionary):
		_fail("retake_cooldown missing from save blob")
		return
	_pass("retake cooldown 7 days, day 8 allowed, third party free")
	var _unused := day7


func _test_observer(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "GER"):
		return
	_war.set_rule_overrides({"end_date": "1936-01-31"})
	tm.current_year = 1936
	tm.current_month = 1
	tm.current_day = 31
	tm.total_days_elapsed = 30
	_end.call("evaluate_and_latch", 30)
	var human: Dictionary = _end.call("view_model")
	var h_title := str(human.get("title", ""))
	if str(human.get("kind", "")) != "time":
		_fail("human time-limit kind=%s model=%s" % [str(human.get("kind")), str(human)])
		return
	if h_title != "Victory: Ascendant" and not h_title.begins_with("Defeat: Eclipsed"):
		_fail("human GER time-limit title %s" % h_title)
		return
	_pass("human GER time limit %s" % h_title)

	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	_boot.set_observer("USA")
	_war.set_rule_overrides({"end_date": "1936-01-31"})
	tm.current_year = 1936
	tm.current_month = 1
	tm.current_day = 31
	tm.total_days_elapsed = 30
	_end.call("evaluate_and_latch", 30)
	var obs: Dictionary = _end.call("view_model")
	if str(obs.get("kind", "")) != "time" or str(obs.get("outcome", "")) != "neutral":
		_fail("observer latch %s" % str(obs))
		return
	if str(obs.get("title", "")) != "Simulation ended":
		_fail("observer title %s" % str(obs.get("title")))
		return
	if not bool(tm.paused):
		_fail("observer time limit did not lock the clock")
		return
	_pass("observer time limit Simulation ended")


func _test_reject_counters(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	if OS.get_environment("EOA_AI_REJECT_LOG").strip_edges() == "1":
		_fail("EOA_AI_REJECT_LOG must be off for this case")
		return
	_war.ai_reject_counters(true)
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_max_wars": 0,
		"ai_declare_min_aggression": 0.99,
		"ai_declare_min_ratio": 99.0,
		"ai_declare_checks_per_day": 8,
	})
	_war.try_ai_declare_wars(0)
	var dec: Dictionary = _war.ai_reject_counters()
	if int(dec.get("max_wars", 0)) <= 0:
		_fail("declare max_wars counter stayed 0 %s" % str(dec))
		return
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_max_wars": 1,
		"ai_declare_min_aggression": 0.99,
		"ai_declare_min_ratio": 99.0,
		"ai_declare_checks_per_day": 8,
	})
	_war.ai_reject_counters(true)
	_war.try_ai_declare_wars(0)
	dec = _war.ai_reject_counters()
	if int(dec.get("aggression", 0)) <= 0:
		_fail("declare aggression counter stayed 0 %s" % str(dec))
		return
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_max_wars": 1,
		"ai_declare_min_aggression": 0.0,
		"ai_declare_min_ratio": 99.0,
		"ai_declare_checks_per_day": 8,
	})
	_war.ai_reject_counters(true)
	_war.try_ai_declare_wars(0)
	dec = _war.ai_reject_counters()
	if int(dec.get("ratio", 0)) <= 0 and int(dec.get("no_target", 0)) <= 0:
		_fail("declare ratio/no_target counters stayed 0 %s" % str(dec))
		return
	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("reject attack declare failed")
		return
	var pair := _first_border(mm, "GER", "POL")
	if pair.size() < 2:
		_fail("reject attack no border")
		return
	_boot.make_division("aiw1_rej_ger", "GER", int(pair[0]))
	_boot.make_division("aiw1_rej_pol", "POL", int(pair[1]))
	bm.call("ai_reject_counters", true)
	bm.call("try_ai_start_land_battles", 0)
	var att: Dictionary = bm.call("ai_reject_counters")
	if int(att.get("ratio", 0)) <= 0:
		_fail("attack ratio counter stayed 0 %s" % str(att))
		return
	tm.total_days_elapsed = 1
	bm.call("_apply_attacker_win_capture_light", "GER", int(pair[1]), int(pair[0]), "aiw1_rej_ger")
	bm.call("ai_reject_counters", true)
	var assault: Dictionary = bm.call("can_assault_province", "POL", int(pair[1]), int(pair[0]))
	att = bm.call("ai_reject_counters")
	if int(att.get("retake_cooldown", 0)) <= 0:
		_fail("attack retake_cooldown counter stayed 0 assault=%s blocked=%s" % [
			str(assault),
			str(bm.call("_retake_blocked_for", "POL", int(pair[1]))),
		])
		return
	_pass("reject counters readable, flag off")


func _test_democracy_guard(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_as(mm, sm, bm, lm, "GER"):
		return
	tm.current_year = 1936
	if bool(_war.democracy_guard_allows("FRA", "POL")):
		_fail("FRA allowed unprovoked POL")
		return
	if bool(_war.democracy_guard_allows("ENG", "CHI")):
		_fail("ENG allowed unprovoked CHI")
		return
	if bool(_war.democracy_guard_allows("USA", "GER")):
		_fail("USA allowed first-war declare on GER in 1936")
		return
	if not bool(_war.democracy_guard_allows("GER", "POL")):
		_fail("GER blocked from POL")
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("democracy setup declare failed")
		return
	if not bool(_war.democracy_guard_allows("FRA", "GER")):
		_fail("FRA blocked from GER who is already at war")
		return
	if bool(_war.democracy_guard_allows("FRA", "POL")):
		_fail("FRA allowed POL even after GER-POL started")
		return
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_declare_min_ratio": 0.0,
		"ai_declare_min_aggression": 0.0,
		"ai_declare_checks_per_day": 8,
		"ai_max_wars": 1,
	})
	_war.reset_for_test()
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_declare_min_ratio": 0.0,
		"ai_declare_min_aggression": 0.0,
		"ai_declare_checks_per_day": 8,
		"ai_max_wars": 1,
	})
	tm.current_year = 1936
	tm.total_days_elapsed = 0
	var events: Array = _war.try_ai_declare_wars(0)
	for ev in events:
		if not (ev is Dictionary):
			continue
		var row: Dictionary = ev
		var att := str(row.get("attacker", ""))
		var defn := str(row.get("defender", ""))
		if att in ["FRA", "ENG", "USA"]:
			_fail("democracy %s started a 1936 justify on %s with no wars" % [att, defn])
			return
	_war.declare_war("GER", "POL", "test")
	events = _war.try_ai_declare_wars(1)
	for ev2 in events:
		if not (ev2 is Dictionary):
			continue
		var row2: Dictionary = ev2
		var att2 := str(row2.get("attacker", ""))
		var def2 := str(row2.get("defender", ""))
		if att2 in ["FRA", "ENG", "USA"] and def2 in ["POL", "CHI"]:
			_fail("democracy %s justified on %s" % [att2, def2])
			return
	_pass("democracies cannot open 1936-38 wars or unprovoked POL/CHI")


func _first_border(mm: Node, att: String, defender: String) -> Array:
	var owned: Array = mm.call("get_provinces_by_owner", att)
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		for nid_v in mm.call("get_adjacent_provinces", pid, true):
			var nid := int(nid_v)
			var p: Object = mm.call("get_province", nid)
			if p == null or bool(p.get("is_sea")):
				continue
			if str(p.get("owner_tag")).strip_edges().to_upper() != defender:
				continue
			return [pid, nid]
	return []


func _garrison_neighbors(mm: Node, pid: int, tag: String) -> void:
	var n := 0
	for nid_v in mm.call("get_adjacent_provinces", pid, true):
		var nid := int(nid_v)
		var p: Object = mm.call("get_province", nid)
		if p == null or bool(p.get("is_sea")):
			continue
		if str(p.get("owner_tag")).strip_edges().to_upper() != tag:
			continue
		n += 1
		_boot.make_division("aiw1_fill_%s_%d" % [tag, nid], tag, nid)


func _adjacent_own(mm: Node, pid: int, tag: String) -> int:
	for nid_v in mm.call("get_adjacent_provinces", pid, true):
		var nid := int(nid_v)
		if nid == pid:
			continue
		var p: Object = mm.call("get_province", nid)
		if p == null or bool(p.get("is_sea")):
			continue
		if str(p.get("owner_tag")).strip_edges().to_upper() == tag:
			return nid
	return -1


func _justifies() -> Dictionary:
	var gd := get_root().get_node_or_null("GameData")
	if gd == null:
		return {}
	var st: Dictionary = gd.peace_state.get("campaign_wars", {})
	var raw: Variant = st.get("justifies", {})
	return raw if raw is Dictionary else {}


func _war_log() -> Array:
	var gd := get_root().get_node_or_null("GameData")
	if gd == null:
		return []
	var st: Dictionary = gd.peace_state.get("campaign_wars", {})
	var raw: Variant = st.get("log", [])
	return raw if raw is Array else []
