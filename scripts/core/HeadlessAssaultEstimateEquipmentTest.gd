extends SceneTree

## Assault division ranking prefers stocked equipment (BattleManager estimate/pick path).
## Also re-checks post-fight equip loss → reinforce cycle.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAssaultEstimateEquipmentTest.gd

const FORM_EMPTY := "assault_est_empty"
const FORM_STOCKED := "assault_est_stocked"
const FORM_CYCLE := "assault_est_cycle_def"
const TAG := "GER"
const TAG_D := "FRA"
const DESIGN := "panzer_iii_j_medium"
const DESIGN_D := "somua_s35_medium"


var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _bm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAssaultEstimateEquipmentTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAssaultEstimateEquipmentTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessAssaultEstimateEquipmentTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	quit(0 if ok else 1)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run() -> void:
	_pm = _autoload("ProductionManager")
	_lm = _autoload("LeaderManager")
	if _pm == null or _lm == null:
		_fail("autoloads missing")
		return
	var bm_script: Script = load("res://scripts/combat/BattleManager.gd") as Script
	if bm_script == null:
		_fail("BattleManager.gd missing")
		return
	_bm = bm_script.new()
	root.add_child(_bm)
	if not _bm.has_method("_estimate_attack_power") or not _bm.has_method("_pick_strongest_division"):
		_fail("BattleManager estimate/pick helpers missing")
		return

	_test_empty_estimate_no_crash()
	_register_forms()
	_test_estimate_stocked_beats_empty()
	_test_pick_prefers_stocked_peer()
	_test_fight_cycle()
	_cleanup()
	if _bm:
		_bm.queue_free()


func _make_form(fid: String, tag: String, design: String) -> void:
	var scr: Script = load("res://scripts/formations/Formation.gd") as Script
	var f: Resource = scr.new() if scr != null else null
	if f == null and ClassDB.class_exists("Formation"):
		f = ClassDB.instantiate("Formation") as Resource
	if f == null:
		_fail("Formation create failed")
		return
	f.set("formation_id", fid)
	f.set("country_tag", tag)
	f.set("formation_type", "division")
	f.set("design_id", design)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	if "formations" in _lm:
		_lm.formations[fid] = f


func _register_forms() -> void:
	_cleanup()
	_make_form(FORM_EMPTY, TAG, DESIGN)
	_make_form(FORM_STOCKED, TAG, DESIGN)
	_make_form(FORM_CYCLE, TAG_D, DESIGN_D)
	_pm.clear_unit_equipment_stock(FORM_EMPTY)
	_pm.set_unit_equipment_stock(FORM_STOCKED, {DESIGN: 1})
	_pm.set_country_equipment_stockpile(TAG, {DESIGN: 40})
	_pm.set_country_equipment_stockpile(TAG_D, {DESIGN_D: 30})


func _test_empty_estimate_no_crash() -> void:
	_pm.clear_unit_equipment_stock("no_est_form")
	var p: float = float(_bm.call("_estimate_attack_power", "no_est_form", null, TAG))
	print("  [INFO] empty/missing form estimate=%.3f" % p)
	_pass("estimate no-crash for missing formation (power=%.3f)" % p)


func _test_estimate_stocked_beats_empty() -> void:
	var empty_p: float = float(_bm.call("_estimate_attack_power", FORM_EMPTY, null, TAG))
	var stock_p: float = float(_bm.call("_estimate_attack_power", FORM_STOCKED, null, TAG))
	print(
		"  [INFO] _estimate_attack_power empty=%.3f stocked=%.3f (same design %s)"
		% [empty_p, stock_p, DESIGN]
	)
	if stock_p <= empty_p:
		_fail("stocked estimate must be strictly greater (%.3f <= %.3f)" % [stock_p, empty_p])
		return
	_pass("assault estimate ranks stocked > empty (%.3f > %.3f)" % [stock_p, empty_p])


func _test_pick_prefers_stocked_peer() -> void:
	# Same design, two land divisions — pick strongest must choose stocked formation_id.
	var divisions: Array[Dictionary] = [
		{"formation_id": FORM_EMPTY, "display_name": "Empty Div"},
		{"formation_id": FORM_STOCKED, "display_name": "Stocked Div"},
	]
	var best: Dictionary = _bm.call("_pick_strongest_division", divisions, null, TAG)
	var best_fid := str(best.get("formation_id", ""))
	var best_power := float(best.get("attack_power", 0.0))
	print(
		"  [INFO] _pick_strongest_division chose %s attack_power=%.3f"
		% [best_fid, best_power]
	)
	if best_fid != FORM_STOCKED:
		_fail("pick should prefer stocked formation, got %s" % best_fid)
		return
	if best_power <= 0.0:
		_fail("picked attack_power should be positive")
		return
	_pass("division pick prefers stocked land formation for assault")


func _test_fight_cycle() -> void:
	_pm.set_unit_equipment_stock(FORM_CYCLE, {DESIGN_D: 1})
	var pre: Dictionary = _pm.get_formation_equipment_combat_stats(FORM_CYCLE)
	var pre_soft := float(pre.get("soft_attack", 0.0))
	if bool(pre.get("has_shortages", true)):
		_fail("cycle setup needs equipped defender")
		return
	_bm.apply_combat_outcome(
		{
			"winner": "attacker",
			"defender_formation_id": FORM_CYCLE,
			"attacker_tag": TAG,
			"target_province_id": -1,
			"outcome": "decisive_attacker",
		},
		FORM_STOCKED,
		-1,
	)
	var post_equip := int(_pm.get_unit_equipment_stock(FORM_CYCLE).get(DESIGN_D, 0))
	var mid: Dictionary = _pm.get_formation_equipment_combat_stats(FORM_CYCLE)
	if post_equip >= 1 and not bool(mid.get("has_shortages", false)):
		_pm.apply_combat_equipment_loss(FORM_CYCLE, 1.0)
		mid = _pm.get_formation_equipment_combat_stats(FORM_CYCLE)
		post_equip = int(_pm.get_unit_equipment_stock(FORM_CYCLE).get(DESIGN_D, 0))
	print(
		"  [INFO] post-fight equip=%d soft=%.3f has_shortages=%s (pre soft=%.3f)"
		% [post_equip, float(mid.get("soft_attack", 0.0)), str(mid.get("has_shortages")), pre_soft]
	)
	if not bool(mid.get("has_shortages", false)):
		_fail("post-fight should has_shortages")
		return
	if float(mid.get("soft_attack", 0.0)) >= pre_soft:
		_fail("post-fight soft should drop")
		return

	var stock_b := int(_pm.get_country_equipment_stockpile(TAG_D).get(DESIGN_D, 0))
	var f = _lm.get_formation(FORM_CYCLE)
	if f != null and "strength" in f:
		f.strength = minf(float(f.strength), 0.5)
	_pm.daily_formation_reinforce_from_stockpile()
	var stock_a := int(_pm.get_country_equipment_stockpile(TAG_D).get(DESIGN_D, 0))
	var equip_a := int(_pm.get_unit_equipment_stock(FORM_CYCLE).get(DESIGN_D, 0))
	var after_r: Dictionary = _pm.get_formation_equipment_combat_stats(FORM_CYCLE)
	print(
		"  [INFO] reinforce stock %d→%d equip=%d has_shortages=%s"
		% [stock_b, stock_a, equip_a, str(after_r.get("has_shortages"))]
	)
	if stock_a >= stock_b or equip_a < 1 or bool(after_r.get("has_shortages", true)):
		_fail("reinforce did not restore equip / drain stockpile")
		return
	_pass("post-fight cycle: equip→outcome loss→shortage→reinforce")


func _cleanup() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(FORM_EMPTY)
		_pm.clear_unit_equipment_stock(FORM_STOCKED)
		_pm.clear_unit_equipment_stock(FORM_CYCLE)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(FORM_EMPTY)
		_lm.formations.erase(FORM_STOCKED)
		_lm.formations.erase(FORM_CYCLE)
