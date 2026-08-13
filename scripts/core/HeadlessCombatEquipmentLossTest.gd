extends SceneTree

## Combat losses consume unit equipment; reinforce rebuilds from country stockpile.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCombatEquipmentLossTest.gd

const ATT_ID := "combat_loss_test_att"
const DEF_ID := "combat_loss_test_def"
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
	print("  [FAIL] HeadlessCombatEquipmentLossTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCombatEquipmentLossTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessCombatEquipmentLossTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	quit(0 if ok else 1)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run() -> void:
	_pm = _autoload("ProductionManager")
	_lm = _autoload("LeaderManager")
	if _pm == null or _lm == null:
		_fail("ProductionManager/LeaderManager missing")
		return
	if not _pm.has_method("apply_combat_equipment_loss"):
		_fail("apply_combat_equipment_loss missing on ProductionManager")
		return

	_test_api_empty_no_crash()
	_register_formations()
	_test_apply_combat_outcome_reduces_equipment()
	_test_reinforce_after_loss()
	_cleanup()


func _test_api_empty_no_crash() -> void:
	_pm.clear_unit_equipment_stock("nonexistent_form_xyz")
	var r: Dictionary = _pm.apply_combat_equipment_loss("nonexistent_form_xyz", 0.8)
	if not r.is_empty():
		_fail("empty unit should remove nothing: %s" % str(r))
		return
	_pass("apply_combat_equipment_loss no-crash when no equipment")


func _make_formation(fid: String, tag: String, design: String, strength: float = 1.0) -> void:
	var fac_script: Script = load("res://scripts/formations/Formation.gd") as Script
	var f: Resource = fac_script.new() if fac_script != null else null
	if f == null and ClassDB.class_exists("Formation"):
		f = ClassDB.instantiate("Formation") as Resource
	if f == null:
		_fail("could not create Formation")
		return
	f.set("formation_id", fid)
	f.set("country_tag", tag)
	f.set("formation_type", "division")
	f.set("design_id", design)
	f.set("strength", strength)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	if "formations" in _lm:
		_lm.formations[fid] = f
	elif _lm.has_method("register_formation"):
		_lm.register_formation(f)


func _register_formations() -> void:
	_cleanup()
	_make_formation(ATT_ID, TAG_A, DESIGN_A, 1.0)
	_make_formation(DEF_ID, TAG_D, DESIGN_D, 1.0)
	_pm.set_unit_equipment_stock(ATT_ID, {DESIGN_A: 3})
	_pm.set_unit_equipment_stock(DEF_ID, {DESIGN_D: 2})
	_pm.set_country_equipment_stockpile(TAG_A, {DESIGN_A: 40})
	_pm.set_country_equipment_stockpile(TAG_D, {DESIGN_D: 40})


func _test_apply_combat_outcome_reduces_equipment() -> void:
	var before_att := int(_pm.get_unit_equipment_stock(ATT_ID).get(DESIGN_A, 0))
	var before_def := int(_pm.get_unit_equipment_stock(DEF_ID).get(DESIGN_D, 0))
	if before_att < 1 or before_def < 1:
		_fail("setup missing unit equipment att=%d def=%d" % [before_att, before_def])
		return

	# Direct API (core of outcome path)
	var removed_att: Dictionary = _pm.apply_combat_equipment_loss(ATT_ID, 0.5)
	var mid_att := int(_pm.get_unit_equipment_stock(ATT_ID).get(DESIGN_A, 0))
	if mid_att >= before_att or removed_att.is_empty():
		_fail("direct apply_combat_equipment_loss did not reduce (before=%d after=%d rem=%s)" % [before_att, mid_att, str(removed_att)])
		return
	_pass("apply_combat_equipment_loss reduced unit equipment %d→%d rem=%s" % [before_att, mid_att, str(removed_att)])

	# Restore equip then drive BattleManager.apply_combat_outcome (shipped post-battle path)
	_pm.set_unit_equipment_stock(ATT_ID, {DESIGN_A: 3})
	_pm.set_unit_equipment_stock(DEF_ID, {DESIGN_D: 2})
	var att_before_bm := int(_pm.get_unit_equipment_stock(ATT_ID).get(DESIGN_A, 0))
	var def_before_bm := int(_pm.get_unit_equipment_stock(DEF_ID).get(DESIGN_D, 0))

	var bm_script: Script = load("res://scripts/combat/BattleManager.gd") as Script
	if bm_script == null:
		_fail("BattleManager.gd load failed")
		return
	var bm: Node = bm_script.new()
	root.add_child(bm)
	var result := {
		"winner": "attacker",
		"defender_formation_id": DEF_ID,
		"attacker_tag": TAG_A,
		"target_province_id": -1,
		"outcome": "decisive_attacker",
	}
	if not bm.has_method("apply_combat_outcome"):
		_fail("apply_combat_outcome missing")
		bm.queue_free()
		return
	bm.apply_combat_outcome(result, ATT_ID, -1)
	var att_after_bm := int(_pm.get_unit_equipment_stock(ATT_ID).get(DESIGN_A, 0))
	var def_after_bm := int(_pm.get_unit_equipment_stock(DEF_ID).get(DESIGN_D, 0))
	bm.queue_free()

	print(
		"  [INFO] BM outcome equip ATT %d→%d DEF %d→%d (winner=attacker, def is loser)"
		% [att_before_bm, att_after_bm, def_before_bm, def_after_bm]
	)
	# Defender lost: equipment must drop. Attacker may light-wear or not if strength untouched as winner.
	if def_after_bm >= def_before_bm:
		_fail("defender (loser) unit equipment did not decrease after apply_combat_outcome")
		return
	_pass(
		"BattleManager.apply_combat_outcome reduced loser equipment DEF %d→%d"
		% [def_before_bm, def_after_bm]
	)


func _test_reinforce_after_loss() -> void:
	# Ensure unit is short after loss
	_pm.set_unit_equipment_stock(DEF_ID, {})
	var f = _lm.get_formation(DEF_ID) if _lm.has_method("get_formation") else null
	if f != null and "strength" in f:
		f.strength = 0.5
	_pm.set_country_equipment_stockpile(TAG_D, {DESIGN_D: 25})
	var stock_before := int(_pm.get_country_equipment_stockpile(TAG_D).get(DESIGN_D, 0))
	var unit_before := int(_pm.get_unit_equipment_stock(DEF_ID).get(DESIGN_D, 0))

	var report: Dictionary = _pm.daily_formation_reinforce_from_stockpile()
	var stock_after := int(_pm.get_country_equipment_stockpile(TAG_D).get(DESIGN_D, 0))
	var unit_after := int(_pm.get_unit_equipment_stock(DEF_ID).get(DESIGN_D, 0))
	var str_after := float(f.strength) if f != null and "strength" in f else -1.0

	print(
		"  [INFO] reinforce after loss stock %d→%d unit %d→%d strength=%.2f report=%s"
		% [stock_before, stock_after, unit_before, unit_after, str_after, str(report)]
	)
	if stock_after >= stock_before:
		_fail("country stockpile did not decrease on reinforce after combat loss")
		return
	if unit_after <= unit_before:
		_fail("unit equipment not restored after reinforce")
		return
	if str_after >= 0.0 and str_after < 0.5:
		_fail("strength should recover when re-equipped (str=%.2f)" % str_after)
		return
	_pass("reinforce after combat equipment loss restored equip/strength and drained stockpile")


func _cleanup() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_ID)
		_pm.clear_unit_equipment_stock(DEF_ID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_ID)
		_lm.formations.erase(DEF_ID)
