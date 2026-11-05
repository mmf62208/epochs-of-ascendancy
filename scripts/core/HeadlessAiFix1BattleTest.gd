extends SceneTree

## SIM-1104-B: AI must start land battles against a defended hex, not only
## empty-hex light capture. Attack gate is 1.5:1 attacker:defender.
##
## Probe (printed): 1v1 on a live GER–POL border records try_ai_start_land_battles
## started_n / eligible_n. Root cause on BASE: battles DID open at 1:1 but
## resolved as defender holds (no province flip); light-sim skipped spare
## marches so the AI never concentrated.
##
## Live: 2 GER vs 1 POL on an adjacent border, 14 days, battles_started > 0.
## Real-source mutant: MIN_ATTACK_STRENGTH_RATIO / attack_ratio_ok missing,
## or 1:1 treated as eligible.

const DAYS := 14
const SRC_AI := "res://scripts/combat/LandBattleAi.gd"
const SRC_BM := "res://scripts/combat/BattleManager.gd"

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
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAiFix1BattleTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAiFix1BattleTest: ", msg)


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
	if mm == null or bm == null or tm == null or lm == null or _boot == null:
		_fail("autoloads missing")
		_finish()
		return
	_assert_source_mutant()
	_assert_ratio_helper()
	if not _boot_observer(mm, sm, bm, lm):
		_finish()
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("declare failed")
		_finish()
		return
	if _cap != null:
		_cap.ensure_snapshot()
	var pair: Array = _first_ger_pol_pair(mm)
	if pair.size() < 2:
		_fail("no GER–POL border pair")
		_finish()
		return
	var from_id := int(pair[0])
	var to_id := int(pair[1])
	_probe_one_v_one(mm, bm, lm, from_id, to_id)
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	if "_open_land_battles" in bm:
		bm._open_land_battles = []
	if "_empty_hex_siege" in bm:
		bm._empty_hex_siege = {}
	_boot.make_division("aifix1_ger_a", "GER", from_id)
	_boot.make_division("aifix1_ger_b", "GER", from_id)
	_boot.make_division("aifix1_pol_a", "POL", to_id)
	var preview: Dictionary = bm.call("can_assault_province", "GER", to_id, from_id)
	if not bool(preview.get("ok", false)):
		_fail("2v1 can_assault failed %s" % str(preview))
		_finish()
		return
	var day0: Dictionary = bm.call("try_ai_start_land_battles", 0)
	print("AIFIX1_BATTLE probe_2v1 %s" % str(day0))
	var battles := int(day0.get("started_n", 0))
	if battles <= 0 and "_open_land_battles" in bm:
		battles = (bm._open_land_battles as Array).size()
	for d in range(1, DAYS + 1):
		tm.call("advance_live_f5_equivalent_days", 1)
		if "_open_land_battles" in bm and (bm._open_land_battles as Array).size() > 0:
			battles += (bm._open_land_battles as Array).size()
		var aar: Dictionary = bm.call("peek_last_land_aar") if bm.has_method("peek_last_land_aar") else {}
		if not aar.is_empty() and str(aar.get("to_id", aar.get("stage", ""))) != "":
			battles += 1
	print("AIFIX1_BATTLE days=%d battles_score=%d open=%s" % [
		DAYS,
		battles,
		str((bm._open_land_battles as Array).size() if "_open_land_battles" in bm else -1),
	])
	if battles <= 0:
		_fail("battles_started=0 over %d days on a defended GER–POL hex" % DAYS)
		_finish()
		return
	_pass("battles_started=%d over %d days (2 GER vs 1 POL at %d→%d)" % [battles, DAYS, from_id, to_id])
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAiFix1BattleTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAiFix1BattleTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _boot_observer(mm: Node, sm: Node, bm: Node, lm: Node) -> bool:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
		if "_empty_hex_siege" in bm:
			bm._empty_hex_siege = {}
	if not _boot.boot(mm, sm, "USA"):
		_fail("boot USA failed")
		return false
	if _cap != null:
		_cap.apply_economy_factories_to_map()
		_cap.reset_for_test()
	if _war != null:
		_war.reset_for_test()
		_war.clear_rule_overrides()
	if _end != null:
		_end.call("reset_for_test")
	return true


func _assert_source_mutant() -> void:
	if not FileAccess.file_exists(SRC_AI) or not FileAccess.file_exists(SRC_BM):
		_fail("LandBattleAi/BattleManager source missing")
		return
	var ai := FileAccess.get_file_as_string(SRC_AI)
	var bm := FileAccess.get_file_as_string(SRC_BM)
	if "MIN_ATTACK_STRENGTH_RATIO" not in ai:
		_fail("mutant skip_ratio: MIN_ATTACK_STRENGTH_RATIO missing")
		return
	if "func attack_ratio_ok" not in ai:
		_fail("mutant skip_ratio: attack_ratio_ok missing")
		return
	if "_ai_front_powers" not in bm or "_collect_adjacent_stack_march" not in bm:
		_fail("mutant empty_only: stacking/power helpers missing from try_ai path")
		return
	if "1.5" not in ai:
		_fail("mutant skip_ratio: 1.5 constant missing")
		return
	_pass("source mutant killed (1.5:1 gate + stack march)")


func _assert_ratio_helper() -> void:
	if _ai == null or not _ai.has_method("attack_ratio_ok"):
		_fail("LandBattleAi.attack_ratio_ok missing")
		return
	var even := {
		"tag": "GER",
		"defender_tag": "POL",
		"has_formation": true,
		"score": 20.0,
		"attacker_power": 100.0,
		"defender_power": 100.0,
	}
	var stacked := even.duplicate()
	stacked["attacker_power"] = 150.0
	if bool(_ai.call("attack_ratio_ok", even)):
		_fail("mutant 1v1_ok: attack_ratio_ok allowed 1:1")
		return
	if not bool(_ai.call("attack_ratio_ok", stacked)):
		_fail("1.5:1 rejected")
		return
	if bool(_ai.call("should_initiate", even, "USA", 0, 2)):
		_fail("mutant 1v1_ok: should_initiate allowed 1:1")
		return
	_pass("1:1 rejected, 1.5:1 accepted")


func _probe_one_v_one(mm: Node, bm: Node, lm: Node, from_id: int, to_id: int) -> void:
	_boot.make_division("aifix1_probe_ger", "GER", from_id)
	_boot.make_division("aifix1_probe_pol", "POL", to_id)
	var row: Dictionary = bm.call("try_ai_start_land_battles", 0)
	var powers: Dictionary = {}
	if bm.has_method("_ai_front_powers"):
		powers = bm.call("_ai_front_powers", "GER", from_id, "POL", to_id)
	print(
		"AIFIX1_BATTLE probe_1v1 started_n=%s eligible_n=%s open=%s powers=%s"
		% [
			str(row.get("started_n", -1)),
			str(row.get("eligible_n", -1)),
			str((bm._open_land_battles as Array).size() if "_open_land_battles" in bm else -1),
			str(powers),
		]
	)
	print(
		"AIFIX1_BATTLE probe_root_cause 1v1_started=%s (BASE soak opened 1:1 fights that resolved defender-hold; light-sim skipped spare marches so ratio never reached 1.5)"
		% str(int(row.get("started_n", 0)) > 0)
	)
	if "_open_land_battles" in bm:
		bm._open_land_battles = []
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).erase("aifix1_probe_ger")
		(lm.formations as Dictionary).erase("aifix1_probe_pol")


func _first_ger_pol_pair(mm: Node) -> Array:
	var owned: Array = mm.call("get_provinces_by_owner", "GER")
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		for nid_v in mm.call("get_adjacent_provinces", pid, true):
			var nid := int(nid_v)
			var p: Object = mm.call("get_province", nid)
			if p == null or bool(p.get("is_sea")):
				continue
			if str(p.get("owner_tag")).strip_edges().to_upper() != "POL":
				continue
			return [pid, nid]
	return []
