extends SceneTree

## Next 3 key elements: post-save/load second-province ownership flip.
## After first capture GER 9276→FRA 9281 + map/prod/leader restore:
## 1) execute follow-on assault toward next enemy succeeds
## 2) second province owner flips to attacker (pcc or forced outcome)
## 3) attacker station advances to second province; first ownership held
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const NEXT_PID := 92991
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const NEXT_TAG := "BEL"
const ATT_FID := "wf_plsf_ger_div"
const DEF_FID := "wf_plsf_fra_div"
const NEXT_FID := "wf_plsf_bel_div"
const DESIGN := "cv33_tankette"


var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _mm: Node = null
var _sl: Node = null
var _bm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest: ",
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
	if _pm == null or _lm == null or _mm == null or _sl == null:
		_fail("autoloads missing")
		return
	if not _setup_map():
		return
	if not _setup_forms():
		return
	var bm_script: Script = load("res://scripts/combat/BattleManager.gd") as Script
	if bm_script == null:
		_fail("BattleManager missing")
		return
	_bm = bm_script.new()
	root.add_child(_bm)
	_test_invalid_assault_no_crash()
	_test_postload_second_flip()
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
			str(TO_PID): [FROM_PID, NEXT_PID, RETREAT_PID],
			str(NEXT_PID): [TO_PID],
			str(RETREAT_PID): [TO_PID],
		}
	)
	var from_p: Object = _new_obj("res://scripts/data/Province.gd")
	var to_p: Object = _new_obj("res://scripts/data/Province.gd")
	var next_p: Object = _new_obj("res://scripts/data/Province.gd")
	var ret_p: Object = _new_obj("res://scripts/data/Province.gd")
	if from_p == null or to_p == null or next_p == null or ret_p == null:
		_fail("Province create failed")
		return false
	_fill_prov(from_p, FROM_PID, ATT_TAG, "GER Border", 2)
	_fill_prov(to_p, TO_PID, DEF_TAG, "FRA Target", 1)
	_fill_prov(next_p, NEXT_PID, NEXT_TAG, "BEL Next", 1)
	_fill_prov(ret_p, RETREAT_PID, DEF_TAG, "FRA Rear", 1)
	adj_sys.call("register_province", from_p)
	adj_sys.call("register_province", to_p)
	adj_sys.call("register_province", next_p)
	adj_sys.call("register_province", ret_p)
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = mds.new(
		{FROM_PID: from_p, TO_PID: to_p, NEXT_PID: next_p, RETREAT_PID: ret_p},
		{},
		adj_sys,
		{ATT_TAG: {"tag": ATT_TAG}, DEF_TAG: {"tag": DEF_TAG}, NEXT_TAG: {"tag": NEXT_TAG}},
	) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	_mm.call("initialize_from_map_data", map_data)
	print("  [INFO] postload-second-flip GER %d → FRA %d → BEL %d" % [FROM_PID, TO_PID, NEXT_PID])
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
	f.set("name", "%s PlsfDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, DESIGN, TO_PID, 0.3, 0.35)
	_make_form(NEXT_FID, NEXT_TAG, DESIGN, NEXT_PID, 0.28, 0.3)
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.clear_unit_equipment_stock(NEXT_FID)
	return _failures == 0


func _reset_pre_first() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_mm.call("update_province_owner", NEXT_PID, NEXT_TAG, NEXT_TAG, true)
	_mm.call("update_province_owner", RETREAT_PID, DEF_TAG, DEF_TAG, true)
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.design_id = DESIGN
		af.strength = 1.0
		af.organization = 1.0
		af.readiness = 1.0
	var df = _lm.get_formation(DEF_FID)
	if df != null:
		df.stationed_province_id = TO_PID
		df.strength = 0.3
		df.organization = 0.35
		df.readiness = 0.35
	var nf = _lm.get_formation(NEXT_FID)
	if nf != null:
		nf.stationed_province_id = NEXT_PID
		nf.strength = 0.28
		nf.organization = 0.3
		nf.readiness = 0.3
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: 3})


func _forced_first_capture() -> Dictionary:
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


func _forced_second_capture() -> Dictionary:
	return {
		"winner": "attacker",
		"outcome": "major_victory",
		"province_control_change": true,
		"attacker_tag": ATT_TAG,
		"defender_tag": NEXT_TAG,
		"target_province_id": NEXT_PID,
		"province_id": NEXT_PID,
		"attacker_formation_id": ATT_FID,
		"defender_formation_id": NEXT_FID,
		"attacker_score": 10.0,
		"defender_score": 2.0,
		"from_province_id": TO_PID,
	}


func _test_invalid_assault_no_crash() -> void:
	var bad: Dictionary = _bm.can_assault_province(ATT_TAG, FROM_PID, FROM_PID)
	if bool(bad.get("ok", true)):
		_fail("same-province assault should not be ok")
		return
	_pass("invalid assault no-crash")


func _do_first_capture() -> bool:
	for attempt in 8:
		_reset_pre_first()
		var wrap: Dictionary = _bm.execute_province_assault(ATT_TAG, TO_PID, FROM_PID, ATT_FID)
		var result: Dictionary = wrap
		if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
			result = wrap["result"] as Dictionary
		if str(result.get("winner", "")) == "attacker" and bool(result.get("province_control_change", false)) \
				and _owner(TO_PID) == ATT_TAG:
			print("  [INFO] first capture attempt %d ok st=%d" % [attempt + 1, _station(ATT_FID)])
			return true
	print("  [INFO] forced first capture")
	_reset_pre_first()
	_bm.apply_combat_outcome(_forced_first_capture(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG


func _test_postload_second_flip() -> void:
	if not _do_first_capture():
		_fail("first capture failed")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker not on first target after capture")
		return

	# Snapshot post-first-capture state
	var map_save: Dictionary = _sl.call("_serialize_map_state")
	var prod_save: Dictionary = _pm.get_save_data()
	var lead_save: Dictionary = _lm.get_save_data()

	# Mutate
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.design_id = ""
	_pm.clear_unit_equipment_stock(ATT_FID)

	# Restore
	_sl.call("_apply_map_state", map_save)
	_pm.apply_save_data(prod_save)
	_lm.apply_save_data(lead_save)
	print(
		"  [INFO] restored owner_to=%s st=%d design=%s owner_next=%s"
		% [_owner(TO_PID), _station(ATT_FID), _design(ATT_FID), _owner(NEXT_PID)]
	)
	if _owner(TO_PID) != ATT_TAG or _station(ATT_FID) != TO_PID:
		_fail("restore failed first capture posture")
		return
	if _design(ATT_FID) != DESIGN:
		_fail("design_id not restored")
		return

	# Top up for follow-on
	af = _lm.get_formation(ATT_FID)
	if af != null:
		af.organization = 1.0
		af.readiness = 1.0
		af.strength = 1.0
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: 3})
	var nf = _lm.get_formation(NEXT_FID)
	if nf != null:
		nf.stationed_province_id = NEXT_PID
		nf.strength = 0.25
		nf.organization = 0.28
		nf.readiness = 0.28

	# --- Element 1: execute follow-on succeeds ---
	var can: Dictionary = _bm.can_assault_province(ATT_TAG, NEXT_PID, TO_PID)
	if not bool(can.get("ok", false)):
		_fail("e1: can_assault next failed: %s" % str(can.get("reason", can)))
		return
	var wrap2: Dictionary = {}
	var result2: Dictionary = {}
	var exec_ok := false
	for attempt in 8:
		af = _lm.get_formation(ATT_FID)
		if af != null:
			af.stationed_province_id = TO_PID
			af.organization = 1.0
			af.readiness = 1.0
			af.strength = 1.0
		nf = _lm.get_formation(NEXT_FID)
		if nf != null:
			nf.stationed_province_id = NEXT_PID
			nf.strength = 0.22
			nf.organization = 0.25
		_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: 3})
		# Keep first ownership if a prior attempt flipped next without station fix
		if _owner(TO_PID) != ATT_TAG:
			_mm.call("update_province_owner", TO_PID, ATT_TAG, ATT_TAG, true)
		if _owner(NEXT_PID) == ATT_TAG:
			_mm.call("update_province_owner", NEXT_PID, NEXT_TAG, NEXT_TAG, true)
		wrap2 = _bm.execute_province_assault(ATT_TAG, NEXT_PID, TO_PID, ATT_FID)
		if not bool(wrap2.get("success", false)):
			print("  [INFO] e1 attempt %d execute not success: %s" % [attempt + 1, str(wrap2.get("reason", wrap2))])
			continue
		result2 = wrap2
		if wrap2.has("result") and typeof(wrap2.get("result")) == TYPE_DICTIONARY:
			result2 = wrap2["result"] as Dictionary
		exec_ok = true
		print(
			"  [INFO] e1 attempt %d success winner=%s pcc=%s owner_next=%s st=%d"
			% [
				attempt + 1,
				str(result2.get("winner", "")),
				str(result2.get("province_control_change", false)),
				_owner(NEXT_PID),
				_station(ATT_FID),
			]
		)
		if str(result2.get("winner", "")) == "attacker" and bool(result2.get("province_control_change", false)) \
				and _owner(NEXT_PID) == ATT_TAG:
			break
	if not exec_ok:
		_fail("e1: execute follow-on never succeeded post-load")
		return
	_pass("e1: execute follow-on assault post-load success=true")

	# --- Element 2: second province ownership flip ---
	if _owner(NEXT_PID) != ATT_TAG:
		print("  [INFO] e2 stochastic miss; forced second capture outcome")
		# Ensure staging posture for station advance
		af = _lm.get_formation(ATT_FID)
		if af != null:
			af.stationed_province_id = TO_PID
		_bm.apply_combat_outcome(_forced_second_capture(), ATT_FID, TO_PID)
	print("  [INFO] e2 owner_next=%s owner_first=%s" % [_owner(NEXT_PID), _owner(TO_PID)])
	if _owner(NEXT_PID) != ATT_TAG:
		_fail("e2: second province owner should be %s, got %s" % [ATT_TAG, _owner(NEXT_PID)])
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("e2: first province ownership lost during second flip")
		return
	_pass("e2: second province ownership flipped to %s (first held)" % ATT_TAG)

	# --- Element 3: station advances; first held ---
	var att_st := _station(ATT_FID)
	print("  [INFO] e3 att_st=%d want next=%d first_owner=%s" % [att_st, NEXT_PID, _owner(TO_PID)])
	if att_st != NEXT_PID:
		_fail("e3: attacker station should advance to %d, got %d" % [NEXT_PID, att_st])
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("e3: first province owner drifted")
		return
	if _station(NEXT_FID) == NEXT_PID and _owner(NEXT_PID) == ATT_TAG:
		# defender may have been displaced — OK either way
		pass
	_pass("e3: attacker station advanced to second province %d; first ownership held" % NEXT_PID)

	_pass("all 3 post-load second-province flip elements")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
		_pm.clear_unit_equipment_stock(NEXT_FID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_FID)
		_lm.formations.erase(DEF_FID)
		_lm.formations.erase(NEXT_FID)


func _cleanup() -> void:
	_cleanup_forms()
