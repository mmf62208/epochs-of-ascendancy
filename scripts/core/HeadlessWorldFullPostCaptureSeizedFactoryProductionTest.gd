extends SceneTree

## world_full: after capture, seized factory production credits **attacker** country stockpile.
## GER 9276→FRA 9281; factory on 9281 transfers; bootstrap line; advance_days → GER stock +1.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureSeizedFactoryProductionTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_sfp_ger_div"
const DEF_FID := "wf_sfp_fra_div"
const ATT_DESIGN := "panzer_iii_j_medium"
const DEF_DESIGN := "somua_s35_medium"
const FACTORY_ID := 928101
const LINE_ID := "wf_seized_ger_line"
const PROD_DESIGN := "cv33_tankette"  # finishes inside 100d with bootstrap tooling
const ADVANCE_DAYS := 100.0


var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _mm: Node = null
var _fm: Node = null
var _bm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldFullPostCaptureSeizedFactoryProductionTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureSeizedFactoryProductionTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureSeizedFactoryProductionTest: ",
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
	if _pm == null or _lm == null or _mm == null or _fm == null:
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
	_test_capture_then_seized_factory_produces_for_attacker()
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
	print("  [INFO] seized-factory production fixture GER %d → FRA %d factory=%d design=%s" % [FROM_PID, TO_PID, FACTORY_ID, PROD_DESIGN])
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


func _stock(tag: String, design: String) -> int:
	return int(_pm.get_country_equipment_stockpile(tag).get(design, 0))


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
	f.set("name", "%s SfpDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, DEF_DESIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: 40, PROD_DESIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 40, PROD_DESIGN: 0})
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
	fac.set("factory_type", "standard")
	fac.set("max_production_lines", 2)
	fac.set("current_efficiency", 1.0)
	fac.set("current_damage", 0.0)
	_fm.register_factory(fac)
	if _fac_owner() != DEF_TAG:
		_fail("setup factory owner should be FRA")
		return false
	print("  [INFO] factory id=%d owner=%s seized=%s" % [FACTORY_ID, _fac_owner(), str(_fac_seized())])
	return true


func _reset_state() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_mm.call("update_province_owner", RETREAT_PID, DEF_TAG, DEF_TAG, true)
	var fac = _fac()
	if fac != null:
		fac.owner_tag = DEF_TAG
		fac.is_seized = false
		fac.current_efficiency = 1.0
		fac.current_damage = 0.0
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
	if _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: 40, PROD_DESIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 40, PROD_DESIGN: 0})


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
		var winner := str(result.get("winner", ""))
		var pcc := bool(result.get("province_control_change", false))
		print(
			"  [INFO] capture attempt %d winner=%s pcc=%s owner=%s fac=%s seized=%s"
			% [attempt + 1, winner, str(pcc), _owner(TO_PID), _fac_owner(), str(_fac_seized())]
		)
		if winner == "attacker" and pcc and _owner(TO_PID) == ATT_TAG and _fac_owner() == ATT_TAG:
			return true
	print("  [INFO] execute stochastic miss; forced apply_combat_outcome")
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG and _fac_owner() == ATT_TAG


func _test_capture_then_seized_factory_produces_for_attacker() -> void:
	if not _do_capture():
		_fail("could not produce capture with factory transfer")
		return
	if not _fac_seized():
		_fail("factory should be seized after capture")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station should be %d" % TO_PID)
		return
	if _station(DEF_FID) == TO_PID:
		_fail("defender should leave captured province")
		return

	# Restore factory efficiency after capture repair side-effects.
	var fac = _fac()
	if fac != null:
		fac.current_efficiency = 1.0
		fac.current_damage = 0.0

	if not _pm.has_method("bootstrap_line_on_factory"):
		_fail("bootstrap_line_on_factory missing")
		return
	if _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
	var boot: bool = bool(_pm.bootstrap_line_on_factory(LINE_ID, PROD_DESIGN, FACTORY_ID))
	if not boot:
		_fail("bootstrap_line_on_factory returned false on seized factory")
		return
	var line = _pm.get_line(LINE_ID)
	if line == null or int(line.factory_id) != FACTORY_ID:
		_fail("line not bound to seized factory")
		return
	print(
		"  [INFO] bootstrap line=%s factory=%d fac_owner=%s design=%s"
		% [LINE_ID, FACTORY_ID, _fac_owner(), PROD_DESIGN]
	)

	var att_before := _stock(ATT_TAG, PROD_DESIGN)
	var def_before := _stock(DEF_TAG, PROD_DESIGN)
	var report: Dictionary = _pm.advance_days(ADVANCE_DAYS)
	var att_after := _stock(ATT_TAG, PROD_DESIGN)
	var def_after := _stock(DEF_TAG, PROD_DESIGN)
	var delta_att := att_after - att_before
	var delta_def := def_after - def_before
	var total_done := int(report.get("total_units_completed", 0))
	var line_rep: Dictionary = {}
	if typeof(report.get("lines")) == TYPE_DICTIONARY:
		line_rep = report["lines"].get(LINE_ID, {})
	var line_done := int(line_rep.get("units_completed", 0))
	print(
		"  [INFO] advance %.0fd att %d→%d (Δ%+d) def %d→%d (Δ%+d) line_done=%d total=%d"
		% [ADVANCE_DAYS, att_before, att_after, delta_att, def_before, def_after, delta_def, line_done, total_done]
	)

	if delta_att < 1 and line_done < 1:
		_fail("seized factory produced nothing for attacker after advance_days")
		return
	if delta_att < 1:
		_fail("units completed but attacker stockpile did not grow (line_done=%d Δatt=%d)" % [line_done, delta_att])
		return
	if delta_def > 0:
		_fail("defender stockpile must not receive completion (Δdef=%d)" % delta_def)
		return
	if _fac_owner() != ATT_TAG:
		_fail("factory owner drifted after production")
		return

	_pass(
		"seized factory production: attacker stockpile +%d design=%s; defender Δ=0"
		% [delta_att, PROD_DESIGN]
	)


func _test_equip_reinforce_after() -> void:
	_pm.set_unit_equipment_stock(DEF_FID, {})
	var f = _lm.get_formation(DEF_FID)
	if f != null and "strength" in f:
		f.strength = 0.45
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 12, PROD_DESIGN: _stock(DEF_TAG, PROD_DESIGN)})
	var stock_b := int(_pm.get_country_equipment_stockpile(DEF_TAG).get(DEF_DESIGN, 0))
	_pm.daily_formation_reinforce_from_stockpile()
	var stock_a := int(_pm.get_country_equipment_stockpile(DEF_TAG).get(DEF_DESIGN, 0))
	var equip_d := int(_pm.get_unit_equipment_stock(DEF_FID).get(DEF_DESIGN, 0))
	print(
		"  [INFO] reinforce stock %d→%d def_equip=%d fac_owner=%s att_stock_prod=%d"
		% [stock_b, stock_a, equip_d, _fac_owner(), _stock(ATT_TAG, PROD_DESIGN)]
	)
	if stock_a >= stock_b or equip_d < 1:
		_fail("reinforce did not drain stockpile / fill equip")
		return
	if _fac_owner() != ATT_TAG:
		_fail("factory ownership lost after reinforce")
		return
	_pass("post-capture reinforce works; seized factory remains attacker-owned")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
		if _pm.has_method("remove_line"):
			_pm.remove_line(LINE_ID)
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
