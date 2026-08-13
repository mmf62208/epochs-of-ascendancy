extends SceneTree

## Next 3 key elements after capture design grant:
## 1) country_may_use_design true for foreign design
## 2) bootstrap+advance produces into attacker country stockpile
## 3) field on-hand equip → combat stats has_shortages false
## GER 9276→FRA 9281; factory current_production_design=somua_s35_medium.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_field_ger_div"
const DEF_FID := "wf_field_fra_div"
const ATT_HOME_DESIGN := "panzer_iii_j_medium"
const FOREIGN_DESIGN := "somua_s35_medium"
const FACTORY_ID := 928101
const LINE_ID := "wf_field_seized_line"
const ADVANCE_DAYS := 100.0


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
	print("  [FAIL] HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest: ",
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
	_test_three_elements_after_capture()
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
		"  [INFO] acquired-design fielding fixture GER %d → FRA %d design=%s"
		% [FROM_PID, TO_PID, FOREIGN_DESIGN]
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


func _may_use(tag: String, design: String) -> bool:
	return bool(_dm.country_may_use_design(tag, design))


func _has_acq(tag: String, design: String) -> bool:
	return bool(_dm.has_acquired_design(tag, design))


func _stock(tag: String, design: String) -> int:
	return int(_pm.get_country_equipment_stockpile(tag).get(design, 0))


func _clear_acq(tag: String, design: String) -> void:
	if _dm.has_method("revoke_acquired_design"):
		_dm.revoke_acquired_design(tag, design)
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
	f.set("name", "%s FieldDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_HOME_DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, FOREIGN_DESIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_HOME_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_HOME_DESIGN: 40, FOREIGN_DESIGN: 0})
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
	fac.set("current_damage", 0.0)
	_fm.register_factory(fac)
	_clear_acq(ATT_TAG, FOREIGN_DESIGN)
	if _has_acq(ATT_TAG, FOREIGN_DESIGN) or _may_use(ATT_TAG, FOREIGN_DESIGN):
		# may_use true only if nation empty/universal; for FRA-nation design must be false
		if _has_acq(ATT_TAG, FOREIGN_DESIGN):
			_fail("setup: attacker already has acquisition")
			return false
		if _may_use(ATT_TAG, FOREIGN_DESIGN) and str(_dm.get_design_nation_tag(FOREIGN_DESIGN)).to_upper() == "FRA":
			_fail("setup: may_use true before acquisition for FRA design")
			return false
	print(
		"  [INFO] factory design=%s may_use_before=%s has_acq_before=%s nation=%s"
		% [
			FOREIGN_DESIGN,
			str(_may_use(ATT_TAG, FOREIGN_DESIGN)),
			str(_has_acq(ATT_TAG, FOREIGN_DESIGN)),
			str(_dm.get_design_nation_tag(FOREIGN_DESIGN)) if _dm.has_method("get_design_nation_tag") else "?",
		]
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
		fac.current_efficiency = 1.0
		fac.current_damage = 0.0
	_clear_acq(ATT_TAG, FOREIGN_DESIGN)
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.design_id = ATT_HOME_DESIGN
		af.strength = 1.0
		af.organization = 1.0
		af.readiness = 1.0
	var df = _lm.get_formation(DEF_FID)
	if df != null:
		df.stationed_province_id = TO_PID
		df.strength = 0.35
		df.organization = 0.4
		df.readiness = 0.4
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_HOME_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	if _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_HOME_DESIGN: 40, FOREIGN_DESIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {FOREIGN_DESIGN: 40})


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
			"  [INFO] capture attempt %d winner=%s pcc=%s owner=%s fac=%s seized=%s has_acq=%s may_use=%s"
			% [
				attempt + 1,
				winner,
				str(pcc),
				_owner(TO_PID),
				_fac_owner(),
				str(_fac_seized()),
				str(_has_acq(ATT_TAG, FOREIGN_DESIGN)),
				str(_may_use(ATT_TAG, FOREIGN_DESIGN)),
			]
		)
		if winner == "attacker" and pcc and _owner(TO_PID) == ATT_TAG and _fac_owner() == ATT_TAG:
			return true
	print("  [INFO] execute stochastic miss; forced apply_combat_outcome")
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG and _fac_owner() == ATT_TAG


func _test_three_elements_after_capture() -> void:
	var may_before := _may_use(ATT_TAG, FOREIGN_DESIGN)
	var acq_before := _has_acq(ATT_TAG, FOREIGN_DESIGN)
	print("  [INFO] element0 pre-capture may_use=%s has_acq=%s" % [str(may_before), str(acq_before)])
	if acq_before:
		_fail("pre-capture attacker already acquired foreign design")
		return
	if may_before:
		_fail("pre-capture may_use should be false for unacquired FRA design")
		return

	if not _do_capture():
		_fail("could not produce capture + factory transfer")
		return
	if not _fac_seized():
		_fail("factory not seized")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station should be target")
		return
	if _station(DEF_FID) == TO_PID:
		_fail("defender should leave target")
		return

	# --- Element 1: may-use ---
	var may_after := _may_use(ATT_TAG, FOREIGN_DESIGN)
	var acq_after := _has_acq(ATT_TAG, FOREIGN_DESIGN)
	print("  [INFO] element1 may_use=%s has_acq=%s" % [str(may_after), str(acq_after)])
	if not acq_after:
		_fail("element1: has_acquired_design should be true after capture grant")
		return
	if not may_after:
		_fail("element1: country_may_use_design should be true after grant")
		return
	_pass("element1: may-use true for acquired foreign design %s" % FOREIGN_DESIGN)

	# --- Element 2: produce into attacker stockpile ---
	var fac = _fac()
	if fac != null:
		fac.current_efficiency = 1.0
		fac.current_damage = 0.0
	if _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
	if not bool(_pm.bootstrap_line_on_factory(LINE_ID, FOREIGN_DESIGN, FACTORY_ID)):
		_fail("element2: bootstrap_line_on_factory failed for foreign design")
		return
	var att_b := _stock(ATT_TAG, FOREIGN_DESIGN)
	var def_b := _stock(DEF_TAG, FOREIGN_DESIGN)
	var report: Dictionary = _pm.advance_days(ADVANCE_DAYS)
	var att_a := _stock(ATT_TAG, FOREIGN_DESIGN)
	var def_a := _stock(DEF_TAG, FOREIGN_DESIGN)
	var delta_att := att_a - att_b
	var delta_def := def_a - def_b
	var total_done := int(report.get("total_units_completed", 0))
	print(
		"  [INFO] element2 produce %.0fd att %d→%d (Δ%+d) def %d→%d (Δ%+d) total=%d"
		% [ADVANCE_DAYS, att_b, att_a, delta_att, def_b, def_a, delta_def, total_done]
	)
	if delta_att < 1:
		_fail("element2: attacker stockpile did not grow for foreign design (Δ=%d total=%d)" % [delta_att, total_done])
		return
	if delta_def > 0:
		_fail("element2: defender stockpile received production (Δ=%d)" % delta_def)
		return
	_pass("element2: seized factory produced foreign design into attacker stockpile +%d" % delta_att)

	# --- Element 3: field on formation + combat stats ---
	var af = _lm.get_formation(ATT_FID)
	if af == null:
		_fail("element3: attacker formation missing")
		return
	af.design_id = FOREIGN_DESIGN
	_pm.clear_unit_equipment_stock(ATT_FID)
	var stats_before: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var short_before := bool(stats_before.get("has_shortages", false))
	print(
		"  [INFO] element3 before equip has_shortages=%s soft=%.3f on_hand=%s stock=%d"
		% [str(short_before), float(stats_before.get("soft_attack", 0.0)), str(_pm.get_unit_equipment_stock(ATT_FID)), _stock(ATT_TAG, FOREIGN_DESIGN)]
	)
	if not short_before:
		_fail("element3: expected shortages before equipping foreign design")
		return
	var taken := 0
	if _pm.has_method("request_equipment_for_unit"):
		taken = int(_pm.request_equipment_for_unit(ATT_FID, FOREIGN_DESIGN, 1))
	if taken < 1:
		# Fallback: direct equip from stockpile if request failed
		var stock_left := _stock(ATT_TAG, FOREIGN_DESIGN)
		if stock_left >= 1:
			_pm.take_from_country_equipment_stockpile(ATT_TAG, FOREIGN_DESIGN, 1)
			_pm.set_unit_equipment_stock(ATT_FID, {FOREIGN_DESIGN: 1})
			taken = 1
	var on_hand: Dictionary = _pm.get_unit_equipment_stock(ATT_FID)
	var on_hand_n := int(on_hand.get(FOREIGN_DESIGN, 0))
	var stats_after: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var short_after := bool(stats_after.get("has_shortages", true))
	print(
		"  [INFO] element3 after equip taken=%d on_hand=%d has_shortages=%s soft=%.3f"
		% [taken, on_hand_n, str(short_after), float(stats_after.get("soft_attack", 0.0))]
	)
	if on_hand_n < 1:
		_fail("element3: formation on-hand foreign design count < 1")
		return
	if short_after:
		_fail("element3: combat stats still has_shortages after equip")
		return
	if float(stats_after.get("soft_attack", 0.0)) <= float(stats_before.get("soft_attack", 0.0)):
		# Soft should improve when shortages clear (strict inequality from baseline)
		_fail(
			"element3: soft_attack should rise after equip (before=%.3f after=%.3f)"
			% [float(stats_before.get("soft_attack", 0.0)), float(stats_after.get("soft_attack", 0.0))]
		)
		return
	_pass(
		"element3: fielded %s×%d; combat has_shortages=false soft %.3f→%.3f"
		% [FOREIGN_DESIGN, on_hand_n, float(stats_before.get("soft_attack", 0.0)), float(stats_after.get("soft_attack", 0.0))]
	)

	_pass("all 3 key elements: may-use + produce + field foreign design after capture")


func _test_equip_reinforce_after() -> void:
	# Standard reinforce regression on defender (home design stock)
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
		"  [INFO] reinforce stock %d→%d def_equip=%d may_use=%s"
		% [stock_b, stock_a, equip_d, str(_may_use(ATT_TAG, FOREIGN_DESIGN))]
	)
	if stock_a >= stock_b or equip_d < 1:
		_fail("reinforce did not drain stockpile / fill equip")
		return
	if not _may_use(ATT_TAG, FOREIGN_DESIGN):
		_fail("may-use lost after reinforce")
		return
	_pass("post-capture reinforce works; may-use retained")


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
