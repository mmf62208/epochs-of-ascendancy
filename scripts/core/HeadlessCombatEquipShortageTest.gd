extends SceneTree

## Drive shipped combat equipment shortage + reinforce-from-stockpile APIs.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCombatEquipShortageTest.gd

const FORM_ID := "combat_eq_test_ger_div"
const TAG := "GER"
const DESIGN := "panzer_iii_j_medium"


var _failures := 0
var _pm: Node = null
var _lm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCombatEquipShortageTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCombatEquipShortageTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessCombatEquipShortageTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	quit(0 if ok else 1)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run() -> void:
	_pm = _autoload("ProductionManager")
	_lm = _autoload("LeaderManager")
	if _pm == null:
		_fail("ProductionManager missing")
		return
	if _lm == null:
		_fail("LeaderManager missing")
		return
	if not _pm.has_method("get_formation_equipment_combat_stats"):
		_fail("get_formation_equipment_combat_stats missing")
		return
	if not _pm.has_method("auto_reinforce_unit_from_stockpile"):
		_fail("auto_reinforce_unit_from_stockpile missing")
		return
	if not _pm.has_method("daily_formation_reinforce_from_stockpile"):
		_fail("daily_formation_reinforce_from_stockpile missing")
		return

	_register_test_formation()
	_test_empty_vs_equipped_combat_stats()
	_test_reinforce_drains_country_stockpile()
	_test_daily_reinforce_path()
	_cleanup()


func _register_test_formation() -> void:
	_cleanup()
	var fac_script: Script = load("res://scripts/formations/Formation.gd") as Script
	var f: Resource = fac_script.new() if fac_script != null else null
	if f == null and ClassDB.class_exists("Formation"):
		f = ClassDB.instantiate("Formation") as Resource
	if f == null:
		_fail("could not instantiate Formation")
		return
	f.set("formation_id", FORM_ID)
	f.set("country_tag", TAG)
	f.set("formation_type", "division")
	f.set("design_id", DESIGN)
	f.set("strength", 0.55)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	if _lm.has_method("register_formation"):
		_lm.register_formation(f)
	elif "formations" in _lm:
		_lm.formations[FORM_ID] = f
	_pm.clear_unit_equipment_stock(FORM_ID)
	_pm.set_country_equipment_stockpile(TAG, {DESIGN: 50})


func _test_empty_vs_equipped_combat_stats() -> void:
	_pm.clear_unit_equipment_stock(FORM_ID)
	var empty_stats: Dictionary = _pm.get_formation_equipment_combat_stats(FORM_ID)
	if empty_stats.is_empty():
		_fail("empty stats returned empty dict")
		return
	if not bool(empty_stats.get("has_shortages", false)):
		_fail("empty unit equipment should has_shortages=true: %s" % str(empty_stats))
		return
	var empty_soft := float(empty_stats.get("soft_attack", 0.0))
	var empty_rdy := float(empty_stats.get("readiness", 0.0))

	_pm.set_unit_equipment_stock(FORM_ID, {DESIGN: 1})
	var full_stats: Dictionary = _pm.get_formation_equipment_combat_stats(FORM_ID)
	if bool(full_stats.get("has_shortages", true)):
		_fail("stocked unit should not have shortages: %s" % str(full_stats))
		return
	var full_soft := float(full_stats.get("soft_attack", 0.0))
	var full_rdy := float(full_stats.get("readiness", 0.0))

	print(
		"  [INFO] empty soft=%.3f rdy=%.3f | equipped soft=%.3f rdy=%.3f shortages empty=%s full=%s"
		% [empty_soft, empty_rdy, full_soft, full_rdy, str(empty_stats.get("has_shortages")), str(full_stats.get("has_shortages"))]
	)
	if full_soft <= empty_soft:
		_fail("equipped soft_attack should exceed shorted (full=%.3f empty=%.3f)" % [full_soft, empty_soft])
		return
	if full_rdy <= empty_rdy:
		_fail("equipped readiness should exceed shorted")
		return

	# CombatResolver path (same helpers combat uses)
	var resolver_script: Script = load("res://scripts/combat/CombatResolver.gd") as Script
	if resolver_script != null:
		var cr: Node = resolver_script.new()
		root.add_child(cr)
		_pm.clear_unit_equipment_stock(FORM_ID)
		var p_empty: Dictionary = cr.get_effective_combat_power(FORM_ID, FORM_ID, FORM_ID, "plains")
		_pm.set_unit_equipment_stock(FORM_ID, {DESIGN: 1})
		var p_full: Dictionary = cr.get_effective_combat_power(FORM_ID, FORM_ID, FORM_ID, "plains")
		cr.queue_free()
		if p_empty.is_empty() or p_full.is_empty():
			_fail("CombatResolver returned empty power empty=%s full=%s" % [str(p_empty.is_empty()), str(p_full.is_empty())])
			return
		if not bool(p_empty.get("has_shortages", false)):
			_fail("CombatResolver empty power missing has_shortages")
			return
		if bool(p_full.get("has_shortages", true)):
			_fail("CombatResolver full power should not has_shortages")
			return
		if float(p_full.get("soft_attack", 0.0)) <= float(p_empty.get("soft_attack", 0.0)):
			_fail("CombatResolver equipped soft should beat shorted")
			return
		_pass("CombatResolver power: shorted vs equipped (has_shortages + soft_attack)")
	else:
		_pass("formation stats shorted vs equipped (no CombatResolver class load)")


func _test_reinforce_drains_country_stockpile() -> void:
	_pm.clear_unit_equipment_stock(FORM_ID)
	_pm.set_country_equipment_stockpile(TAG, {DESIGN: 20})
	var before := int(_pm.get_country_equipment_stockpile(TAG).get(DESIGN, 0))
	var required: Dictionary = _pm.get_formation_required_equipment(FORM_ID)
	if required.is_empty() or not required.has(DESIGN):
		_fail("get_formation_required_equipment missing design: %s" % str(required))
		return
	var fulfilled: Dictionary = _pm.auto_reinforce_unit_from_stockpile(FORM_ID, required)
	var after := int(_pm.get_country_equipment_stockpile(TAG).get(DESIGN, 0))
	var unit_have := int(_pm.get_unit_equipment_stock(FORM_ID).get(DESIGN, 0))
	print(
		"  [INFO] reinforce before=%d after=%d unit=%d fulfilled=%s"
		% [before, after, unit_have, str(fulfilled)]
	)
	if after >= before:
		_fail("country stockpile did not decrease on reinforce (before=%d after=%d)" % [before, after])
		return
	if unit_have < 1:
		_fail("unit equipment not filled after reinforce")
		return
	_pass("auto_reinforce_unit_from_stockpile drained country stockpile and filled unit")


func _test_daily_reinforce_path() -> void:
	_pm.clear_unit_equipment_stock(FORM_ID)
	_pm.set_country_equipment_stockpile(TAG, {DESIGN: 15})
	var f = _lm.get_formation(FORM_ID) if _lm.has_method("get_formation") else null
	if f != null and "strength" in f:
		f.strength = 0.5
	var before := int(_pm.get_country_equipment_stockpile(TAG).get(DESIGN, 0))
	var report: Dictionary = _pm.daily_formation_reinforce_from_stockpile()
	var after := int(_pm.get_country_equipment_stockpile(TAG).get(DESIGN, 0))
	var unit_have := int(_pm.get_unit_equipment_stock(FORM_ID).get(DESIGN, 0))
	var str_after := float(f.strength) if f != null and "strength" in f else -1.0
	print(
		"  [INFO] daily reinforce report=%s before=%d after=%d unit=%d strength=%.2f"
		% [str(report), before, after, unit_have, str_after]
	)
	if after >= before and unit_have < 1:
		_fail("daily_formation_reinforce did not move equipment")
		return
	if unit_have < 1:
		_fail("unit still empty after daily reinforce")
		return
	if str_after >= 0.0 and str_after < 0.5:
		_fail("strength should recover when equipped (str=%.2f)" % str_after)
		return
	_pass("daily_formation_reinforce_from_stockpile recovered equipment/strength")


func _cleanup() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(FORM_ID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(FORM_ID)
