extends SceneTree

## world_full: combat capture of factory with current_production_design grants design to attacker.
## GER 9276→FRA 9281; factory on 9281 produces somua_s35_medium → GER has_acquired_design(captured).
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureDesignGrantTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_dgrant_ger_div"
const DEF_FID := "wf_dgrant_fra_div"
const ATT_DESIGN := "panzer_iii_j_medium"
const FOREIGN_DESIGN := "somua_s35_medium"
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
	print("  [FAIL] HeadlessWorldFullPostCaptureDesignGrantTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureDesignGrantTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureDesignGrantTest: ",
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
		_fail("autoloads missing (need DesignManager)")
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
	_test_capture_grants_foreign_design()
	_test_equip_reinforce_after()
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
		"  [INFO] design-grant fixture GER %d → FRA %d factory=%d design=%s"
		% [FROM_PID, TO_PID, FACTORY_ID, FOREIGN_DESIGN]
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


func _has_design(tag: String, design: String) -> bool:
	return bool(_dm.has_acquired_design(tag, design))


func _acq_kind(tag: String, design: String) -> String:
	if _dm.has_method("get_acquisition_kind"):
		return str(_dm.get_acquisition_kind(tag, design)).strip_edges().to_lower()
	return ""


func _clear_acq(tag: String, design: String) -> void:
	if _dm.has_method("revoke_acquired_design"):
		_dm.revoke_acquired_design(tag, design)
	# Belt-and-suspenders for private dicts if revoke missed
	if "_acquired_designs" in _dm:
		var bucket = _dm._acquired_designs.get(tag, {})
		if typeof(bucket) == TYPE_DICTIONARY:
			bucket.erase(design)
	if "_acquired_foreign_designs" in _dm:
		var leg = _dm._acquired_foreign_designs.get(tag, {})
		if typeof(leg) == TYPE_DICTIONARY:
			leg.erase(design)


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
	f.set("name", "%s DGrantDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, FOREIGN_DESIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: 40})
	_pm.set_country_equipment_stockpile(DEF_TAG, {FOREIGN_DESIGN: 40})
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
	fac.set("current_production_design", FOREIGN_DESIGN)
	fac.set("previous_design", "")
	fac.set("factory_type", "standard")
	fac.set("max_production_lines", 2)
	fac.set("current_efficiency", 1.0)
	_fm.register_factory(fac)
	_clear_acq(ATT_TAG, FOREIGN_DESIGN)
	if _has_design(ATT_TAG, FOREIGN_DESIGN):
		_fail("setup: attacker must not already have foreign design")
		return false
	var fcheck = _fac()
	if fcheck == null or str(fcheck.current_production_design) != FOREIGN_DESIGN:
		_fail("setup factory missing current_production_design")
		return false
	print(
		"  [INFO] factory id=%d owner=%s design=%s has_acq_before=%s"
		% [FACTORY_ID, _fac_owner(), FOREIGN_DESIGN, str(_has_design(ATT_TAG, FOREIGN_DESIGN))]
	)
	return true


func _reset_state() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_mm.call("update_province_owner", RETREAT_PID, DEF_TAG, DEF_TAG, true)
	var fac = _fac()
	if fac != null:
		fac.owner_tag = DEF_TAG
		fac.is_seized = false
		fac.current_production_design = FOREIGN_DESIGN
		fac.previous_design = ""
	_clear_acq(ATT_TAG, FOREIGN_DESIGN)
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.strength = 1.0
		af.organization = 1.0
		af.readiness = 1.0
	var df = _lm.get_formation(DEF_FID)
	if df != null:
		df.stationed_province_id = TO_PID
		df.strength = 0.35
		df.organization = 0.4
		df.readiness = 0.4
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
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
		if _has_design(ATT_TAG, FOREIGN_DESIGN):
			_fail("reset left design still acquired")
			return false
		var wrap: Dictionary = _bm.execute_province_assault(ATT_TAG, TO_PID, FROM_PID, ATT_FID)
		var result: Dictionary = wrap
		if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
			result = wrap["result"] as Dictionary
		var winner := str(result.get("winner", ""))
		var pcc := bool(result.get("province_control_change", false))
		print(
			"  [INFO] capture attempt %d winner=%s pcc=%s owner=%s fac=%s seized=%s has_acq=%s kind=%s"
			% [
				attempt + 1,
				winner,
				str(pcc),
				_owner(TO_PID),
				_fac_owner(),
				str(_fac_seized()),
				str(_has_design(ATT_TAG, FOREIGN_DESIGN)),
				_acq_kind(ATT_TAG, FOREIGN_DESIGN),
			]
		)
		if winner == "attacker" and pcc and _owner(TO_PID) == ATT_TAG:
			return true
	print("  [INFO] execute stochastic miss; forced apply_combat_outcome (non-skip factory path)")
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG


func _test_capture_grants_foreign_design() -> void:
	if _has_design(ATT_TAG, FOREIGN_DESIGN):
		_clear_acq(ATT_TAG, FOREIGN_DESIGN)
	if _has_design(ATT_TAG, FOREIGN_DESIGN):
		_fail("could not clear prior acquisition for setup")
		return

	if not _do_capture():
		_fail("could not produce capture")
		return

	var fac_owner := _fac_owner()
	var seized := _fac_seized()
	var has_acq := _has_design(ATT_TAG, FOREIGN_DESIGN)
	var kind := _acq_kind(ATT_TAG, FOREIGN_DESIGN)
	var att_st := _station(ATT_FID)
	var def_st := _station(DEF_FID)
	print(
		"  [INFO] post-capture owner=%s fac=%s seized=%s has_acq=%s kind=%s att_st=%d def_st=%d design=%s"
		% [_owner(TO_PID), fac_owner, str(seized), str(has_acq), kind, att_st, def_st, FOREIGN_DESIGN]
	)

	if _owner(TO_PID) != ATT_TAG:
		_fail("province owner should be %s" % ATT_TAG)
		return
	if fac_owner != ATT_TAG:
		_fail("factory owner should be %s, got %s" % [ATT_TAG, fac_owner])
		return
	if not seized:
		_fail("factory should be seized")
		return
	if not has_acq:
		_fail("attacker should have acquired design %s after factory capture" % FOREIGN_DESIGN)
		return
	if kind != "captured" and not kind.is_empty():
		# empty kind only if legacy store; prefer captured
		_fail("acquisition kind should be 'captured', got '%s'" % kind)
		return
	if kind.is_empty():
		# Modern store should have kind; warn but if has_acq true from modern path, get_acquisition_kind should work
		_fail("acquisition kind empty despite has_acquired")
		return
	if att_st != TO_PID:
		_fail("attacker station should be %d" % TO_PID)
		return
	if def_st == TO_PID:
		_fail("defender should leave captured province")
		return

	_pass(
		"design grant: %s → GER kind=%s; factory seized; stations ok"
		% [FOREIGN_DESIGN, kind]
	)


func _test_equip_reinforce_after() -> void:
	_pm.set_unit_equipment_stock(DEF_FID, {})
	var f = _lm.get_formation(DEF_FID)
	if f != null and "strength" in f:
		f.strength = 0.45
	_pm.set_country_equipment_stockpile(DEF_TAG, {FOREIGN_DESIGN: 12})
	var stock_b := int(_pm.get_country_equipment_stockpile(DEF_TAG).get(FOREIGN_DESIGN, 0))
	_pm.daily_formation_reinforce_from_stockpile()
	var stock_a := int(_pm.get_country_equipment_stockpile(DEF_TAG).get(FOREIGN_DESIGN, 0))
	var equip_d := int(_pm.get_unit_equipment_stock(DEF_FID).get(FOREIGN_DESIGN, 0))
	print(
		"  [INFO] reinforce stock %d→%d def_equip=%d has_acq=%s"
		% [stock_b, stock_a, equip_d, str(_has_design(ATT_TAG, FOREIGN_DESIGN))]
	)
	if stock_a >= stock_b or equip_d < 1:
		_fail("reinforce did not drain stockpile / fill equip")
		return
	if not _has_design(ATT_TAG, FOREIGN_DESIGN):
		_fail("design acquisition lost after reinforce")
		return
	_pass("post-capture reinforce works; design acquisition retained")


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
