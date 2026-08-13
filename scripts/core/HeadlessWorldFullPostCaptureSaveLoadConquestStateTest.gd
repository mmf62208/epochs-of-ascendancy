extends SceneTree

## Next 3 key elements: conquest state survives manager save/load after capture.
## 1) acquired foreign design (has_acquired_design kind=captured)
## 2) seized factory owner == attacker
## 3) attacker station on target; defender station ≠ target
## GER 9276→FRA 9281; DesignManager/FactoryManager/LeaderManager get/apply_save_data.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureSaveLoadConquestStateTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_slcs_ger_div"
const DEF_FID := "wf_slcs_fra_div"
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
	print("  [FAIL] HeadlessWorldFullPostCaptureSaveLoadConquestStateTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureSaveLoadConquestStateTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureSaveLoadConquestStateTest: ",
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
	_test_saveload_three_elements()
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
		"  [INFO] saveload conquest fixture GER %d → FRA %d design=%s factory=%d"
		% [FROM_PID, TO_PID, FOREIGN, FACTORY_ID]
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


func _fac() -> Object:
	return _fm.get_factory(FACTORY_ID)


func _fac_owner() -> String:
	var f = _fac()
	if f == null:
		return ""
	return str(f.owner_tag).strip_edges().to_upper()


func _fac_seized() -> bool:
	var f = _fac()
	return f != null and bool(f.is_seized)


func _has_acq() -> bool:
	return bool(_dm.has_acquired_design(ATT_TAG, FOREIGN))


func _acq_kind() -> String:
	if _dm.has_method("get_acquisition_kind"):
		return str(_dm.get_acquisition_kind(ATT_TAG, FOREIGN)).strip_edges().to_lower()
	return ""


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
	f.set("name", "%s SlcsDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_HOME, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, FOREIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_HOME: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
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
	print("  [INFO] factory design=%s has_acq_before=%s" % [FOREIGN, str(_has_acq())])
	return true


func _reset_state() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_mm.call("update_province_owner", RETREAT_PID, DEF_TAG, DEF_TAG, true)
	var fac = _fac()
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
				and _owner(TO_PID) == ATT_TAG and _has_acq() and _fac_owner() == ATT_TAG:
			print(
				"  [INFO] capture attempt %d ok att_st=%d def_st=%d seized=%s"
				% [attempt + 1, _station(ATT_FID), _station(DEF_FID), str(_fac_seized())]
			)
			return true
	print("  [INFO] forced apply_combat_outcome for capture")
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG and _has_acq() and _fac_owner() == ATT_TAG


func _test_saveload_three_elements() -> void:
	if not _do_capture():
		_fail("could not capture with grant + factory transfer")
		return
	if not _fac_seized():
		_fail("factory not seized after capture")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station not on target after capture")
		return
	if _station(DEF_FID) == TO_PID:
		_fail("defender still on target after capture")
		return

	# Snapshot via shipped manager APIs
	if not _dm.has_method("get_save_data") or not _dm.has_method("apply_save_data"):
		_fail("DesignManager missing get/apply_save_data")
		return
	if not _fm.has_method("get_save_data") or not _fm.has_method("apply_save_data"):
		_fail("FactoryManager missing get/apply_save_data")
		return
	if not _lm.has_method("get_save_data") or not _lm.has_method("apply_save_data"):
		_fail("LeaderManager missing get/apply_save_data")
		return

	var dsave: Dictionary = _dm.get_save_data()
	var fsave: Dictionary = _fm.get_save_data()
	var lsave: Dictionary = _lm.get_save_data()
	print(
		"  [INFO] saved design.acq=%s fac_keys=%s form_count=%d"
		% [
			str((dsave.get("acquired_designs", {}) as Dictionary).has(ATT_TAG)),
			str((fsave.get("factories", {}) as Dictionary).keys()),
			((lsave.get("formations", {}) as Dictionary).size() if lsave.has("formations") else 0),
		]
	)
	if not dsave.has("acquired_designs"):
		_fail("DesignManager save missing acquired_designs")
		return
	if not fsave.has("factories") or not fsave.has("province_to_factories"):
		_fail("FactoryManager save incomplete")
		return
	if not lsave.has("formations"):
		_fail("LeaderManager save missing formations")
		return

	# Mutate live state so restore must be real (not no-op)
	_clear_acq()
	var fac = _fac()
	if fac != null:
		fac.owner_tag = DEF_TAG
		fac.is_seized = false
	var af = _lm.get_formation(ATT_FID)
	var df = _lm.get_formation(DEF_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
	if df != null:
		df.stationed_province_id = TO_PID
	print(
		"  [INFO] mutated has_acq=%s fac=%s seized=%s att_st=%d def_st=%d"
		% [str(_has_acq()), _fac_owner(), str(_fac_seized()), _station(ATT_FID), _station(DEF_FID)]
	)
	if _has_acq() or _fac_owner() == ATT_TAG or _station(ATT_FID) == TO_PID:
		_fail("mutation did not clear conquest state before restore")
		return

	# Restore
	_dm.apply_save_data(dsave)
	_fm.apply_save_data(fsave)
	_lm.apply_save_data(lsave)

	# Element 1: design acquisition
	var has_acq := _has_acq()
	var kind := _acq_kind()
	print("  [INFO] e1 restored has_acq=%s kind=%s" % [str(has_acq), kind])
	if not has_acq:
		_fail("e1: has_acquired_design false after DesignManager apply_save_data")
		return
	if kind != "captured" and not kind.is_empty():
		_fail("e1: acquisition kind expected captured, got %s" % kind)
		return
	if kind.is_empty():
		_fail("e1: acquisition kind empty after restore")
		return
	_pass("e1: acquired design %s survived save/load (kind=%s)" % [FOREIGN, kind])

	# Element 2: factory owner + seized
	var fo := _fac_owner()
	var seized := _fac_seized()
	var fac_obj = _fac()
	print(
		"  [INFO] e2 restored fac_owner=%s seized=%s present=%s"
		% [fo, str(seized), str(fac_obj != null)]
	)
	if fac_obj == null:
		_fail("e2: factory missing after FactoryManager apply_save_data")
		return
	if fo != ATT_TAG:
		_fail("e2: factory owner should be %s after restore, got %s" % [ATT_TAG, fo])
		return
	if not seized:
		_fail("e2: factory is_seized should be true after restore")
		return
	if not _fm.province_to_factories.has(TO_PID):
		_fail("e2: province_to_factories missing target after restore")
		return
	_pass("e2: seized factory owner=%s survived save/load" % fo)

	# Element 3: stations
	var att_st := _station(ATT_FID)
	var def_st := _station(DEF_FID)
	print("  [INFO] e3 restored att_st=%d def_st=%d (want att=%d def!=%d)" % [att_st, def_st, TO_PID, TO_PID])
	if att_st != TO_PID:
		_fail("e3: attacker station should be %d after restore, got %d" % [TO_PID, att_st])
		return
	if def_st == TO_PID:
		_fail("e3: defender station should not be target after restore, still %d" % def_st)
		return
	# Province owner still attacker (map not in manager save — fixture still holds)
	if _owner(TO_PID) != ATT_TAG:
		_fail("e3: province owner drifted to %s" % _owner(TO_PID))
		return
	_pass("e3: stations survived save/load (att=%d def=%d)" % [att_st, def_st])

	_pass("all 3 saveload elements: design + seized factory + stations")


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
