extends SceneTree

## Next 3 key elements for acquired foreign design combat loop:
## 1) daily_formation_reinforce_from_stockpile fills on-hand from country stockpile
## 2) combat stats / can_assault attack_power better when equipped vs empty
## 3) apply_combat_equipment_loss / combat outcome writes off on-hand equip
## GER 9276→FRA 9281 capture grants somua_s35_medium; then reinforce/power/loss.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990  # remains FRA for follow-on can_assault power compare
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_fdcl_ger_div"
const DEF_FID := "wf_fdcl_fra_div"
const ATT_HOME := "panzer_iii_j_medium"
const FOREIGN := "somua_s35_medium"
const FACTORY_ID := 928101


var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _mm: Node = null
var _fm: Node = null
var _dm: Node = null
var _bm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest: ",
		"PASS" if ok else "FAIL",
		" (failures=", _failures, ")"
	)
	quit(0 if ok else 1)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _run() -> void:
	_pm = _autoload("ProductionManager")
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	_fm = _autoload("FactoryManager")
	_dm = _autoload("DesignManager")
	if _pm == null or _lm == null or _mm == null or _fm == null or _dm == null:
		_fail("autoloads missing")
		return
	if not _setup_map():
		return
	if not _setup_forms():
		return
	if not _setup_factory():
		return
	var bm_script: Script = load("res://scripts/combat/BattleManager.gd") as Script
	if bm_script == null:
		_fail("BattleManager missing")
		return
	_bm = bm_script.new()
	root.add_child(_bm)

	_test_invalid_assault_no_crash()
	_test_three_combat_loop_elements()
	_cleanup()
	if _bm:
		_bm.queue_free()


func _setup_map() -> bool:
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	adj_sys.call(
		"load_from_dict",
		{
			str(FROM_PID): [TO_PID],
			str(TO_PID): [FROM_PID, RETREAT_PID],
			str(RETREAT_PID): [TO_PID],
		}
	)
	var from_p: Object = _new_obj("res://scripts/data/Province.gd")
	var to_p: Object = _new_obj("res://scripts/data/Province.gd")
	var ret_p: Object = _new_obj("res://scripts/data/Province.gd")
	if from_p == null or to_p == null or ret_p == null:
		_fail("Province create failed")
		return false
	_fill_prov(from_p, FROM_PID, ATT_TAG, "GER Border", 2)
	_fill_prov(to_p, TO_PID, DEF_TAG, "FRA Target", 1)
	_fill_prov(ret_p, RETREAT_PID, DEF_TAG, "FRA Rear", 1)
	adj_sys.call("register_province", from_p)
	adj_sys.call("register_province", to_p)
	adj_sys.call("register_province", ret_p)
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = mds.new(
		{FROM_PID: from_p, TO_PID: to_p, RETREAT_PID: ret_p},
		{},
		adj_sys,
		{ATT_TAG: {"tag": ATT_TAG}, DEF_TAG: {"tag": DEF_TAG}},
	) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	_mm.call("initialize_from_map_data", map_data)
	print(
		"  [INFO] foreign-design combat-loop fixture GER %d → FRA %d design=%s"
		% [FROM_PID, TO_PID, FOREIGN]
	)
	return true


func _fill_prov(p: Object, pid: int, tag: String, pname: String, dev: int) -> void:
	p.set("id", pid)
	p.set("owner_tag", tag)
	p.set("controller_tag", tag)
	p.set("terrain", "plains")
	p.set("name", pname)
	p.set("is_sea", false)
	p.set("development_level", dev)
	p.set("infrastructure", dev)


func _owner(pid: int) -> String:
	if _mm.has_method("get_province_owner"):
		return str(_mm.call("get_province_owner", pid)).to_upper()
	var p = _mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.owner_tag).strip_edges().to_upper()


func _station(fid: String) -> int:
	var f = _lm.get_formation(fid)
	if f == null or not ("stationed_province_id" in f):
		return -999
	return int(f.stationed_province_id)


func _fac_owner() -> String:
	var f = _fm.get_factory(FACTORY_ID)
	if f == null:
		return ""
	return str(f.owner_tag).strip_edges().to_upper()


func _clear_acq() -> void:
	if _dm.has_method("revoke_acquired_design"):
		_dm.revoke_acquired_design(ATT_TAG, FOREIGN)
	if "_acquired_designs" in _dm:
		var b = _dm._acquired_designs.get(ATT_TAG, {})
		if typeof(b) == TYPE_DICTIONARY:
			b.erase(FOREIGN)
	if "_acquired_foreign_designs" in _dm:
		var l = _dm._acquired_foreign_designs.get(ATT_TAG, {})
		if typeof(l) == TYPE_DICTIONARY:
			l.erase(FOREIGN)


func _stock(tag: String) -> int:
	return int(_pm.get_country_equipment_stockpile(tag).get(FOREIGN, 0))


func _hand(fid: String) -> int:
	return int(_pm.get_unit_equipment_stock(fid).get(FOREIGN, 0))


func _make_form(fid: String, tag: String, design: String, station: int, str_v: float, org_v: float) -> void:
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("Formation create failed")
		return
	f.set("formation_id", fid)
	f.set("country_tag", tag)
	f.set("formation_type", "division")
	f.set("design_id", design)
	f.set("stationed_province_id", station)
	f.set("strength", str_v)
	f.set("organization", org_v)
	f.set("readiness", org_v)
	f.set("name", "%s FdclDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_HOME, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, FOREIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_HOME: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_HOME: 40, FOREIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {FOREIGN: 40})
	return _failures == 0


func _setup_factory() -> bool:
	if "factories" in _fm and _fm.factories.has(FACTORY_ID):
		_fm.factories.erase(FACTORY_ID)
	if "province_to_factories" in _fm and _fm.province_to_factories.has(TO_PID):
		var ids: Array = _fm.province_to_factories[TO_PID]
		ids.erase(FACTORY_ID)
		if ids.is_empty():
			_fm.province_to_factories.erase(TO_PID)
	var fac: Object = _new_obj("res://scripts/map/Factory.gd")
	if fac == null:
		_fail("Factory create failed")
		return false
	fac.set("factory_id", FACTORY_ID)
	fac.set("province_id", TO_PID)
	fac.set("owner_tag", DEF_TAG)
	fac.set("is_seized", false)
	fac.set("current_production_design", FOREIGN)
	fac.set("previous_design", "")
	fac.set("factory_type", "standard")
	fac.set("max_production_lines", 2)
	fac.set("current_efficiency", 1.0)
	_fm.register_factory(fac)
	_clear_acq()
	print("  [INFO] factory design=%s has_acq_before=%s" % [FOREIGN, str(_dm.has_acquired_design(ATT_TAG, FOREIGN))])
	return true


func _reset_state() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_mm.call("update_province_owner", RETREAT_PID, DEF_TAG, DEF_TAG, true)
	var fac = _fm.get_factory(FACTORY_ID)
	if fac != null:
		fac.owner_tag = DEF_TAG
		fac.is_seized = false
		fac.current_production_design = FOREIGN
	_clear_acq()
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.design_id = ATT_HOME
		af.strength = 1.0
		af.organization = 1.0
		af.readiness = 1.0
	var df = _lm.get_formation(DEF_FID)
	if df != null:
		df.stationed_province_id = TO_PID
		df.strength = 0.35
		df.organization = 0.4
		df.readiness = 0.4
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_HOME: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_HOME: 40, FOREIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {FOREIGN: 40})


func _forced_capture_result() -> Dictionary:
	return {
		"winner": "attacker",
		"outcome": "major_victory",
		"province_control_change": true,
		"attacker_tag": ATT_TAG,
		"defender_tag": DEF_TAG,
		"target_province_id": TO_PID,
		"province_id": TO_PID,
		"attacker_formation_id": ATT_FID,
		"defender_formation_id": DEF_FID,
		"attacker_score": 10.0,
		"defender_score": 2.0,
	}


func _test_invalid_assault_no_crash() -> void:
	var bad: Dictionary = _bm.can_assault_province(ATT_TAG, FROM_PID, FROM_PID)
	if bool(bad.get("ok", true)):
		_fail("same-province assault should not be ok")
		return
	var bad2: Dictionary = _bm.execute_province_assault(ATT_TAG, 999999, FROM_PID, ATT_FID)
	print("  [INFO] invalid can=%s exec_success=%s" % [str(bad.get("ok")), str(bad2.get("success", bad2))])
	_pass("invalid assault no-crash")


func _do_capture() -> bool:
	for attempt in 8:
		_reset_state()
		var wrap: Dictionary = _bm.execute_province_assault(ATT_TAG, TO_PID, FROM_PID, ATT_FID)
		var result: Dictionary = wrap
		if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
			result = wrap["result"] as Dictionary
		if str(result.get("winner", "")) == "attacker" and bool(result.get("province_control_change", false)) \
				and _owner(TO_PID) == ATT_TAG and bool(_dm.has_acquired_design(ATT_TAG, FOREIGN)):
			print(
				"  [INFO] capture attempt %d ok owner=%s fac=%s has_acq=true att_st=%d"
				% [attempt + 1, _owner(TO_PID), _fac_owner(), _station(ATT_FID)]
			)
			return true
	print("  [INFO] forced apply_combat_outcome for capture grant")
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG and bool(_dm.has_acquired_design(ATT_TAG, FOREIGN))


func _test_three_combat_loop_elements() -> void:
	if not _do_capture():
		_fail("could not capture + grant foreign design")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station should be captured province")
		return
	if _station(DEF_FID) == TO_PID:
		_fail("defender should leave captured province")
		return
	if _fac_owner() != ATT_TAG:
		_fail("factory should belong to attacker")
		return

	var af = _lm.get_formation(ATT_FID)
	if af == null:
		_fail("attacker formation missing")
		return

	# --- Element 1: daily reinforce foreign design ---
	af.design_id = FOREIGN
	_pm.clear_unit_equipment_stock(ATT_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {FOREIGN: 5})
	var stock_b := _stock(ATT_TAG)
	var hand_b := _hand(ATT_FID)
	var reinf: Dictionary = _pm.daily_formation_reinforce_from_stockpile()
	var stock_a := _stock(ATT_TAG)
	var hand_a := _hand(ATT_FID)
	print(
		"  [INFO] e1 reinforce stock %d→%d hand %d→%d moved=%s units=%s"
		% [
			stock_b,
			stock_a,
			hand_b,
			hand_a,
			str(reinf.get("equipment_moved", 0)),
			str(reinf.get("units_reinforced", 0)),
		]
	)
	if hand_a < 1:
		_fail("e1: on-hand foreign design still empty after reinforce")
		return
	if stock_a >= stock_b:
		_fail("e1: country stockpile did not decrease after reinforce")
		return
	if stock_b - stock_a < 1:
		_fail("e1: stockpile delta too small")
		return
	_pass("e1: daily reinforce filled foreign design on-hand (%d→%d stock %d→%d)" % [hand_b, hand_a, stock_b, stock_a])

	# --- Element 2: combat stats + assault power empty vs equipped ---
	_pm.clear_unit_equipment_stock(ATT_FID)
	var stats_empty: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var soft_empty := float(stats_empty.get("soft_attack", 0.0))
	var short_empty := bool(stats_empty.get("has_shortages", false))
	var can_empty: Dictionary = _bm.can_assault_province(ATT_TAG, RETREAT_PID, TO_PID)
	var power_empty := float(can_empty.get("attack_power", 0.0))

	_pm.set_unit_equipment_stock(ATT_FID, {FOREIGN: 2})
	var stats_full: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var soft_full := float(stats_full.get("soft_attack", 0.0))
	var short_full := bool(stats_full.get("has_shortages", true))
	var can_full: Dictionary = _bm.can_assault_province(ATT_TAG, RETREAT_PID, TO_PID)
	var power_full := float(can_full.get("attack_power", 0.0))
	print(
		"  [INFO] e2 empty short=%s soft=%.3f power=%.3f | full short=%s soft=%.3f power=%.3f"
		% [str(short_empty), soft_empty, power_empty, str(short_full), soft_full, power_full]
	)
	if not short_empty:
		_fail("e2: expected has_shortages when on-hand empty")
		return
	if short_full:
		_fail("e2: expected no shortages when on-hand filled")
		return
	if soft_full <= soft_empty:
		_fail("e2: soft_attack should rise when equipped (%.3f vs %.3f)" % [soft_full, soft_empty])
		return
	if not bool(can_empty.get("ok", false)) or not bool(can_full.get("ok", false)):
		_fail("e2: can_assault should be ok for both empty and full equip")
		return
	if power_full <= power_empty:
		_fail("e2: attack_power should be higher when equipped (%.3f vs %.3f)" % [power_full, power_empty])
		return
	_pass(
		"e2: combat/assault power up when equipped (soft %.3f→%.3f power %.3f→%.3f)"
		% [soft_empty, soft_full, power_empty, power_full]
	)

	# --- Element 3: combat equip write-off ---
	_pm.set_unit_equipment_stock(ATT_FID, {FOREIGN: 3})
	var hand_pre := _hand(ATT_FID)
	var removed: Dictionary = _pm.apply_combat_equipment_loss(ATT_FID, 0.5)
	var hand_mid := _hand(ATT_FID)
	print("  [INFO] e3 apply_combat_equipment_loss hand %d→%d removed=%s" % [hand_pre, hand_mid, str(removed)])
	if removed.is_empty() or int(removed.get(FOREIGN, 0)) < 1:
		_fail("e3: apply_combat_equipment_loss did not consume foreign design")
		return
	if hand_mid >= hand_pre:
		_fail("e3: on-hand did not decrease after equip loss API")
		return

	# Also via outcome path (loser severity)
	_pm.set_unit_equipment_stock(ATT_FID, {FOREIGN: 2})
	af.strength = 1.0
	af.organization = 1.0
	af.readiness = 1.0
	var hand_pre2 := _hand(ATT_FID)
	var forced_loss := {
		"winner": "defender",
		"outcome": "defeat",
		"province_control_change": false,
		"attacker_tag": ATT_TAG,
		"defender_tag": DEF_TAG,
		"target_province_id": RETREAT_PID,
		"province_id": RETREAT_PID,
		"attacker_formation_id": ATT_FID,
		"defender_formation_id": DEF_FID,
		"attacker_score": 1.0,
		"defender_score": 10.0,
	}
	_bm.apply_combat_outcome(forced_loss, ATT_FID, TO_PID)
	var hand_post2 := _hand(ATT_FID)
	print(
		"  [INFO] e3 apply_combat_outcome hand %d→%d str=%.2f"
		% [hand_pre2, hand_post2, float(af.strength)]
	)
	if hand_post2 >= hand_pre2:
		_fail("e3: on-hand did not decrease after combat outcome equip write-off")
		return

	# Optional re-reinforce restores
	_pm.set_country_equipment_stockpile(ATT_TAG, {FOREIGN: 4})
	_pm.clear_unit_equipment_stock(ATT_FID)
	_pm.daily_formation_reinforce_from_stockpile()
	var hand_restore := _hand(ATT_FID)
	print("  [INFO] e3 re-reinforce on-hand=%d" % hand_restore)
	if hand_restore < 1:
		_fail("e3: re-reinforce failed to restore foreign equip after loss")
		return

	_pass(
		"e3: combat write-off consumed foreign equip (%d→%d API, %d→%d outcome); re-reinforce ok"
		% [hand_pre, hand_mid, hand_pre2, hand_post2]
	)

	_pass("all 3 combat-loop elements: reinforce + power + equip-loss for foreign design")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_FID)
		_lm.formations.erase(DEF_FID)


func _cleanup() -> void:
	_cleanup_forms()
	if _fm != null:
		if "factories" in _fm:
			_fm.factories.erase(FACTORY_ID)
		if "province_to_factories" in _fm and _fm.province_to_factories.has(TO_PID):
			var ids: Array = _fm.province_to_factories[TO_PID]
			ids.erase(FACTORY_ID)
			if ids.is_empty():
				_fm.province_to_factories.erase(TO_PID)
