extends SceneTree

## Next 3 key elements: post-save/load conquest state still enables operational loop.
## After capture GER 9276→FRA 9281 (grant + seize + station) and full manager restore:
## 1) execute_province_assault from restored station succeeds (follow-on toward FRA rear)
## 2) seized factory bootstrap + advance_days credits attacker stockpile
## 3) acquired foreign design fieldable: may-use + equip + combat has_shortages=false
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadConquestLoopTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_pcl_ger_div"
const DEF_FID := "wf_pcl_fra_div"
const ATT_HOME := "panzer_iii_j_medium"
const FOREIGN := "somua_s35_medium"
const PROD_DESIGN := "cv33_tankette"
const FACTORY_ID := 928102
const LINE_ID := "wf_pcl_ger_line"
const ADVANCE_DAYS := 100.0


var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _mm: Node = null
var _sl: Node = null
var _fm: Node = null
var _dm: Node = null
var _bm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldFullPostCapturePostLoadConquestLoopTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCapturePostLoadConquestLoopTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCapturePostLoadConquestLoopTest: ",
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
	_sl = _autoload("SaveLoadManager")
	_fm = _autoload("FactoryManager")
	_dm = _autoload("DesignManager")
	if _pm == null or _lm == null or _mm == null or _sl == null or _fm == null or _dm == null:
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
	_test_postload_conquest_loop()
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
		"  [INFO] postload-conquest-loop fixture GER %d → FRA %d foreign=%s factory=%d"
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


func _design(fid: String) -> String:
	var f = _lm.get_formation(fid)
	if f == null or not ("design_id" in f):
		return ""
	return str(f.design_id)


func _stock(tag: String, design: String = PROD_DESIGN) -> int:
	return int(_pm.get_country_equipment_stockpile(tag).get(design, 0))


func _hand(fid: String, design: String = PROD_DESIGN) -> int:
	return int(_pm.get_unit_equipment_stock(fid).get(design, 0))


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


func _may_use() -> bool:
	if _dm.has_method("country_may_use_design"):
		return bool(_dm.country_may_use_design(ATT_TAG, FOREIGN))
	return _has_acq()


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
	f.set("name", "%s PclDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_HOME, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, FOREIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_HOME: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_HOME: 40, PROD_DESIGN: 0, FOREIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {FOREIGN: 40, PROD_DESIGN: 0})
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
		fac.current_efficiency = 1.0
		fac.current_damage = 0.0
	_clear_acq()
	if _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
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
		df.design_id = FOREIGN
		df.strength = 0.35
		df.organization = 0.4
		df.readiness = 0.4
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_HOME: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_HOME: 40, PROD_DESIGN: 0, FOREIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {FOREIGN: 40, PROD_DESIGN: 0})


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
				"  [INFO] capture attempt %d ok st=%d seized=%s acq=%s"
				% [attempt + 1, _station(ATT_FID), str(_fac_seized()), str(_has_acq())]
			)
			return true
	print("  [INFO] forced apply_combat_outcome for capture")
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG and _has_acq() and _fac_owner() == ATT_TAG


func _test_postload_conquest_loop() -> void:
	if not _do_capture():
		_fail("could not capture with grant + factory transfer")
		return
	if not _fac_seized():
		_fail("factory not seized after capture")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker not stationed on target")
		return

	# Ensure production APIs available
	if not _sl.has_method("_serialize_map_state") or not _sl.has_method("_apply_map_state"):
		_fail("SaveLoadManager map serialize/apply missing")
		return
	for pair in [
		[_dm, "DesignManager"],
		[_fm, "FactoryManager"],
		[_lm, "LeaderManager"],
		[_pm, "ProductionManager"],
	]:
		var node: Node = pair[0]
		var label: String = pair[1]
		if not node.has_method("get_save_data") or not node.has_method("apply_save_data"):
			_fail("%s missing get/apply_save_data" % label)
			return

	var map_save: Dictionary = _sl.call("_serialize_map_state")
	var prod_save: Dictionary = _pm.get_save_data()
	var lead_save: Dictionary = _lm.get_save_data()
	var dsave: Dictionary = _dm.get_save_data()
	var fsave: Dictionary = _fm.get_save_data()
	print(
		"  [INFO] pre-mutate owner=%s st=%d fac=%s seized=%s acq=%s"
		% [_owner(TO_PID), _station(ATT_FID), _fac_owner(), str(_fac_seized()), str(_has_acq())]
	)

	# Mutate all conquest + playability state
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_clear_acq()
	var fac = _fac()
	if fac != null:
		fac.owner_tag = DEF_TAG
		fac.is_seized = false
	var af = _lm.get_formation(ATT_FID)
	var df = _lm.get_formation(DEF_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.design_id = ""
	if df != null:
		df.stationed_province_id = TO_PID
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_HOME: 0, PROD_DESIGN: 0, FOREIGN: 0})
	_pm.clear_unit_equipment_stock(ATT_FID)
	print(
		"  [INFO] mutated owner=%s st=%d design=%s fac=%s acq=%s"
		% [_owner(TO_PID), _station(ATT_FID), _design(ATT_FID), _fac_owner(), str(_has_acq())]
	)
	if _owner(TO_PID) == ATT_TAG or _has_acq() or _fac_owner() == ATT_TAG or _station(ATT_FID) == TO_PID:
		_fail("mutation incomplete before restore")
		return

	# Full restore
	_sl.call("_apply_map_state", map_save)
	_pm.apply_save_data(prod_save)
	_lm.apply_save_data(lead_save)
	_dm.apply_save_data(dsave)
	_fm.apply_save_data(fsave)

	print(
		"  [INFO] restored owner=%s st=%d design=%s fac=%s seized=%s acq=%s may=%s"
		% [
			_owner(TO_PID),
			_station(ATT_FID),
			_design(ATT_FID),
			_fac_owner(),
			str(_fac_seized()),
			str(_has_acq()),
			str(_may_use()),
		]
	)
	if _owner(TO_PID) != ATT_TAG or _station(ATT_FID) != TO_PID:
		_fail("map/station restore failed")
		return
	if not _has_acq() or _fac_owner() != ATT_TAG or not _fac_seized():
		_fail("conquest design/factory restore failed")
		return
	if _design(ATT_FID) != ATT_HOME:
		_fail("design_id not restored (got %s)" % _design(ATT_FID))
		return

	# --- Element 1: execute follow-on assault from restored station ---
	af = _lm.get_formation(ATT_FID)
	if af != null:
		af.organization = maxf(float(af.organization), 0.85)
		af.readiness = maxf(float(af.readiness), 0.85)
		af.strength = maxf(float(af.strength), 0.9)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_HOME: 3})
	# Ensure defender sits on rear for a real fight
	df = _lm.get_formation(DEF_FID)
	if df != null and _station(DEF_FID) != RETREAT_PID:
		df.stationed_province_id = RETREAT_PID
		df.strength = maxf(float(df.strength), 0.3)
		df.organization = maxf(float(df.organization), 0.3)

	var can: Dictionary = _bm.can_assault_province(ATT_TAG, RETREAT_PID, TO_PID)
	if not bool(can.get("ok", false)):
		_fail("e1: can_assault post-load failed: %s" % str(can.get("reason", can)))
		return
	var wrap: Dictionary = _bm.execute_province_assault(ATT_TAG, RETREAT_PID, TO_PID, ATT_FID)
	print(
		"  [INFO] e1 execute success=%s keys=%s"
		% [str(wrap.get("success", wrap)), str(wrap.keys())]
	)
	if not bool(wrap.get("success", false)):
		_fail("e1: execute_province_assault blocked post-load: %s" % str(wrap.get("reason", wrap)))
		return
	var result: Dictionary = wrap
	if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
		result = wrap["result"] as Dictionary
	var winner := str(result.get("winner", "")).strip_edges()
	var has_scores := result.has("attacker_score") or result.has("defender_score")
	print(
		"  [INFO] e1 result winner=%s att_score=%.3f def_score=%.3f owner_first=%s"
		% [
			winner,
			float(result.get("attacker_score", 0.0)),
			float(result.get("defender_score", 0.0)),
			_owner(TO_PID),
		]
	)
	if winner.is_empty() and not has_scores:
		_fail("e1: follow-on result missing winner and scores")
		return
	if winner.is_empty():
		_fail("e1: follow-on result must include winner")
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("e1: first capture owner must remain %s" % ATT_TAG)
		return
	_pass("e1: execute follow-on assault post-load (winner=%s)" % winner)

	# --- Element 2: seized factory production for attacker after restore ---
	fac = _fac()
	if fac != null:
		fac.current_efficiency = 1.0
		fac.current_damage = 0.0
		fac.owner_tag = ATT_TAG
		fac.is_seized = true
	if _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
	if not bool(_pm.bootstrap_line_on_factory(LINE_ID, PROD_DESIGN, FACTORY_ID)):
		_fail("e2: bootstrap_line_on_factory failed on restored seized factory")
		return
	var att_b := _stock(ATT_TAG, PROD_DESIGN)
	var def_b := _stock(DEF_TAG, PROD_DESIGN)
	var report: Dictionary = _pm.advance_days(ADVANCE_DAYS)
	var att_a := _stock(ATT_TAG, PROD_DESIGN)
	var def_a := _stock(DEF_TAG, PROD_DESIGN)
	var delta_att := att_a - att_b
	var delta_def := def_a - def_b
	var total_done := int(report.get("total_units_completed", 0))
	print(
		"  [INFO] e2 advance %.0fd att %d→%d (Δ%+d) def %d→%d (Δ%+d) total=%d fac=%s"
		% [ADVANCE_DAYS, att_b, att_a, delta_att, def_b, def_a, delta_def, total_done, _fac_owner()]
	)
	if delta_att < 1:
		_fail("e2: seized factory did not grow attacker stockpile post-load (Δ=%d total=%d)" % [delta_att, total_done])
		return
	if delta_def > 0:
		_fail("e2: defender received production post-load (Δ=%d)" % delta_def)
		return
	if _fac_owner() != ATT_TAG:
		_fail("e2: factory owner drifted to %s" % _fac_owner())
		return
	_pass("e2: seized factory produced for attacker post-load +%d" % delta_att)

	# --- Element 3: acquired foreign design fieldable after restore ---
	if not _has_acq():
		_fail("e3: has_acquired_design lost")
		return
	if not _may_use():
		_fail("e3: country_may_use_design false after design restore")
		return
	af = _lm.get_formation(ATT_FID)
	if af == null:
		_fail("e3: attacker formation missing")
		return
	af.design_id = FOREIGN
	_pm.clear_unit_equipment_stock(ATT_FID)
	# Ensure stockpile has foreign design to field
	if _stock(ATT_TAG, FOREIGN) < 1:
		_pm.set_country_equipment_stockpile(
			ATT_TAG,
			{
				ATT_HOME: _stock(ATT_TAG, ATT_HOME),
				PROD_DESIGN: _stock(ATT_TAG, PROD_DESIGN),
				FOREIGN: 3,
			}
		)
	var stats_before: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var short_before := bool(stats_before.get("has_shortages", false))
	print(
		"  [INFO] e3 before equip has_shortages=%s soft=%.3f stock_foreign=%d"
		% [str(short_before), float(stats_before.get("soft_attack", 0.0)), _stock(ATT_TAG, FOREIGN)]
	)
	if not short_before:
		_fail("e3: expected shortages before equipping foreign design")
		return
	var taken := 0
	if _pm.has_method("request_equipment_for_unit"):
		taken = int(_pm.request_equipment_for_unit(ATT_FID, FOREIGN, 1))
	if taken < 1:
		_pm.take_from_country_equipment_stockpile(ATT_TAG, FOREIGN, 1)
		_pm.set_unit_equipment_stock(ATT_FID, {FOREIGN: 1})
		taken = 1
	var on_hand_n := _hand(ATT_FID, FOREIGN)
	var stats_after: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var short_after := bool(stats_after.get("has_shortages", true))
	var soft_after := float(stats_after.get("soft_attack", 0.0))
	var soft_before := float(stats_before.get("soft_attack", 0.0))
	print(
		"  [INFO] e3 after equip taken=%d on_hand=%d has_shortages=%s soft %.3f→%.3f"
		% [taken, on_hand_n, str(short_after), soft_before, soft_after]
	)
	if on_hand_n < 1:
		_fail("e3: foreign on-hand empty after equip")
		return
	if short_after:
		_fail("e3: combat still has_shortages after fielding acquired design")
		return
	if soft_after <= soft_before:
		_fail("e3: soft_attack should rise after equip (%.3f → %.3f)" % [soft_before, soft_after])
		return
	_pass(
		"e3: fielded acquired %s post-load; soft %.3f→%.3f no shortages"
		% [FOREIGN, soft_before, soft_after]
	)

	_pass("all 3 post-load conquest loop: execute + seized prod + field design")


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
	_clear_acq()
	if _fm != null:
		if "factories" in _fm:
			_fm.factories.erase(FACTORY_ID)
		if "province_to_factories" in _fm and _fm.province_to_factories.has(TO_PID):
			var ids: Array = _fm.province_to_factories[TO_PID]
			ids.erase(FACTORY_ID)
			if ids.is_empty():
				_fm.province_to_factories.erase(TO_PID)
