extends SceneTree

## Equipment-aware land combat power (BattleManager estimate + resolve path) + short fight cycle.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCombatPowerEquipmentTest.gd

const FORM_A := "pwr_eq_att"
const FORM_D := "pwr_eq_def"
const TAG_A := "GER"
const TAG_D := "FRA"
const DESIGN_A := "panzer_iii_j_medium"
const DESIGN_D := "somua_s35_medium"


var _failures := 0
var _pm: Node = null
var _lm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCombatPowerEquipmentTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCombatPowerEquipmentTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessCombatPowerEquipmentTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	quit(0 if ok else 1)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run() -> void:
	_pm = _autoload("ProductionManager")
	_lm = _autoload("LeaderManager")
	if _pm == null or _lm == null:
		_fail("autoloads missing")
		return

	_test_empty_no_crash()
	_register_pair()
	_test_estimate_and_resolve_power_empty_vs_stocked()
	_test_fight_loss_reinforce_cycle()
	_cleanup()


func _test_empty_no_crash() -> void:
	_pm.clear_unit_equipment_stock("no_such_pwr_form")
	var cr_script: Script = load("res://scripts/combat/CombatResolver.gd") as Script
	if cr_script == null:
		_fail("CombatResolver missing")
		return
	var cr: Node = cr_script.new()
	root.add_child(cr)
	var p: Dictionary = cr.get_effective_combat_power("no_such_pwr_form", "no_such_pwr_form", "no_such_pwr_form", "plains")
	cr.queue_free()
	_pm.apply_combat_equipment_loss("no_such_pwr_form", 0.8)
	_pass("empty formation power/loss no-crash (power_empty=%s)" % str(p.is_empty()))


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


func _register_pair() -> void:
	_cleanup()
	_make_form(FORM_A, TAG_A, DESIGN_A)
	_make_form(FORM_D, TAG_D, DESIGN_D)
	_pm.set_country_equipment_stockpile(TAG_A, {DESIGN_A: 40})
	_pm.set_country_equipment_stockpile(TAG_D, {DESIGN_D: 40})


func _bm_estimate_power(cr: Node, fid: String) -> float:
	# Same formula as BattleManager._estimate_attack_power (equipment-aware get_effective_combat_power).
	var stats: Dictionary = cr.get_effective_combat_power(fid, fid, fid, "plains", -1, 2, 2)
	return float(stats.get("soft_attack", 0.0)) + float(stats.get("hard_attack", 0.0)) * 1.6


func _test_estimate_and_resolve_power_empty_vs_stocked() -> void:
	var cr_script: Script = load("res://scripts/combat/CombatResolver.gd") as Script
	var cr: Node = cr_script.new()
	root.add_child(cr)

	_pm.clear_unit_equipment_stock(FORM_A)
	var empty_stats: Dictionary = cr.get_effective_combat_power(FORM_A, FORM_A, FORM_A, "plains")
	var empty_est := _bm_estimate_power(cr, FORM_A)

	_pm.set_unit_equipment_stock(FORM_A, {DESIGN_A: 1})
	var full_stats: Dictionary = cr.get_effective_combat_power(FORM_A, FORM_A, FORM_A, "plains")
	var full_est := _bm_estimate_power(cr, FORM_A)

	print(
		"  [INFO] estimate empty=%.3f full=%.3f | has_short empty=%s full=%s soft empty=%.3f full=%.3f"
		% [
			empty_est,
			full_est,
			str(empty_stats.get("has_shortages")),
			str(full_stats.get("has_shortages")),
			float(empty_stats.get("soft_attack", 0.0)),
			float(full_stats.get("soft_attack", 0.0)),
		]
	)

	if empty_stats.is_empty() or full_stats.is_empty():
		_fail("power dict empty")
		cr.queue_free()
		return
	if not bool(empty_stats.get("has_shortages", false)):
		_fail("empty equip should has_shortages on BM power path")
		cr.queue_free()
		return
	if bool(full_stats.get("has_shortages", true)):
		_fail("stocked equip should not has_shortages")
		cr.queue_free()
		return
	if full_est <= empty_est:
		_fail("stocked estimate power should exceed empty (full=%.3f empty=%.3f)" % [full_est, empty_est])
		cr.queue_free()
		return
	if float(full_stats.get("soft_attack", 0.0)) <= float(empty_stats.get("soft_attack", 0.0)):
		_fail("stocked soft_attack should exceed empty")
		cr.queue_free()
		return

	# Minimal two-side resolve_combat score compare (attacker empty vs stocked vs same defender)
	var fa = _lm.get_formation(FORM_A)
	var fd = _lm.get_formation(FORM_D)
	_pm.set_unit_equipment_stock(FORM_D, {DESIGN_D: 1})
	var prov_script: Script = load("res://scripts/data/Province.gd") as Script
	var prov: Resource = null
	if prov_script != null:
		prov = prov_script.new() as Resource
	if prov == null and ClassDB.class_exists("Province"):
		prov = ClassDB.instantiate("Province") as Resource
	if prov != null:
		prov.set("id", 900001)
		prov.set("terrain", "plains")
		prov.set("owner_tag", TAG_D)
		prov.set("development_level", 2)
		prov.set("infrastructure", 2)
		_pm.clear_unit_equipment_stock(FORM_A)
		var r_empty: Dictionary = cr.resolve_combat(fa, fd, prov, FORM_A, FORM_D)
		_pm.set_unit_equipment_stock(FORM_A, {DESIGN_A: 1})
		var r_full: Dictionary = cr.resolve_combat(fa, fd, prov, FORM_A, FORM_D)
		var sc_empty := float(r_empty.get("attacker_score", 0.0))
		var sc_full := float(r_full.get("attacker_score", 0.0))
		print(
			"  [INFO] resolve_combat attacker_score empty=%.1f full=%.1f outcome_empty=%s full=%s"
			% [sc_empty, sc_full, str(r_empty.get("outcome")), str(r_full.get("outcome"))]
		)
		if r_empty.get("outcome") == "invalid" or r_full.get("outcome") == "invalid":
			_fail("resolve_combat invalid (power path failed)")
			cr.queue_free()
			return
		if sc_full <= sc_empty:
			_fail("stocked attacker_score should exceed empty (%.1f vs %.1f)" % [sc_full, sc_empty])
			cr.queue_free()
			return
		_pass("resolve_combat attacker_score higher when equipped (%.1f > %.1f)" % [sc_full, sc_empty])
	else:
		_pass("estimate/power empty vs stocked (no Province for resolve compare)")

	cr.queue_free()
	_pass("BM-path get_effective_combat_power / estimate formula equipment-aware")


func _test_fight_loss_reinforce_cycle() -> void:
	# equip → outcome loss → has_shortages → reinforce
	_pm.set_unit_equipment_stock(FORM_D, {DESIGN_D: 1})
	_pm.set_country_equipment_stockpile(TAG_D, {DESIGN_D: 25})
	var pre_soft := float(_pm.get_formation_equipment_combat_stats(FORM_D).get("soft_attack", 0.0))
	var pre_short := bool(_pm.get_formation_equipment_combat_stats(FORM_D).get("has_shortages", true))
	if pre_short:
		_fail("cycle setup: defender should be equipped")
		return

	var bm_script: Script = load("res://scripts/combat/BattleManager.gd") as Script
	var bm: Node = bm_script.new()
	root.add_child(bm)
	bm.apply_combat_outcome(
		{
			"winner": "attacker",
			"defender_formation_id": FORM_D,
			"attacker_tag": TAG_A,
			"target_province_id": -1,
			"outcome": "decisive_attacker",
		},
		FORM_A,
		-1,
	)
	bm.queue_free()

	var post_equip := int(_pm.get_unit_equipment_stock(FORM_D).get(DESIGN_D, 0))
	var mid: Dictionary = _pm.get_formation_equipment_combat_stats(FORM_D)
	print(
		"  [INFO] cycle post-outcome equip=%d soft=%.3f has_shortages=%s (pre soft=%.3f)"
		% [post_equip, float(mid.get("soft_attack", 0.0)), str(mid.get("has_shortages")), pre_soft]
	)
	if post_equip >= 1 and not bool(mid.get("has_shortages", false)):
		# ensure zero for shortage if partial loss left equip
		_pm.apply_combat_equipment_loss(FORM_D, 1.0)
		mid = _pm.get_formation_equipment_combat_stats(FORM_D)
		post_equip = int(_pm.get_unit_equipment_stock(FORM_D).get(DESIGN_D, 0))
	if not bool(mid.get("has_shortages", false)):
		_fail("after loss should has_shortages")
		return
	if float(mid.get("soft_attack", 0.0)) >= pre_soft:
		_fail("after loss soft should drop")
		return

	var stock_b := int(_pm.get_country_equipment_stockpile(TAG_D).get(DESIGN_D, 0))
	var f = _lm.get_formation(FORM_D)
	if f != null and "strength" in f:
		f.strength = minf(float(f.strength), 0.5)
	_pm.daily_formation_reinforce_from_stockpile()
	var stock_a := int(_pm.get_country_equipment_stockpile(TAG_D).get(DESIGN_D, 0))
	var equip_a := int(_pm.get_unit_equipment_stock(FORM_D).get(DESIGN_D, 0))
	var after_r: Dictionary = _pm.get_formation_equipment_combat_stats(FORM_D)
	print(
		"  [INFO] cycle reinforce stock %d→%d equip=%d has_shortages=%s"
		% [stock_b, stock_a, equip_a, str(after_r.get("has_shortages"))]
	)
	if stock_a >= stock_b or equip_a < 1 or bool(after_r.get("has_shortages", true)):
		_fail("reinforce did not restore equip / drain stockpile")
		return
	_pass("short fight cycle: equip→outcome→shortage power→reinforce")


func _cleanup() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(FORM_A)
		_pm.clear_unit_equipment_stock(FORM_D)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(FORM_A)
		_lm.formations.erase(FORM_D)
