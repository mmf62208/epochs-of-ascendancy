extends SceneTree

## world_full post-capture follow-on assault **execute** from captured province.
## Capture GER 9276→FRA 9281; then execute_province_assault from 9281 → BEL 92991.
## Gate: execute success + combat result (winner), not blocked by missing formation.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureFollowOnExecuteTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const NEXT_PID := 92991
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const NEXT_TAG := "BEL"
const ATT_FID := "wf_foexec_ger_div"
const DEF_FID := "wf_foexec_fra_div"
const NEXT_FID := "wf_foexec_bel_div"
const ATT_DESIGN := "panzer_iii_j_medium"
const DEF_DESIGN := "somua_s35_medium"
const NEXT_DESIGN := "m3_stuart_light_tank"


var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _mm: Node = null
var _bm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldFullPostCaptureFollowOnExecuteTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureFollowOnExecuteTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureFollowOnExecuteTest: ",
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
	if _pm == null or _lm == null or _mm == null:
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
	_test_capture_then_follow_on_execute()
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

	var provs := {FROM_PID: from_p, TO_PID: to_p, NEXT_PID: next_p, RETREAT_PID: ret_p}
	var countries := {
		ATT_TAG: {"tag": ATT_TAG, "name": "Germany"},
		DEF_TAG: {"tag": DEF_TAG, "name": "France"},
		NEXT_TAG: {"tag": NEXT_TAG, "name": "Belgium"},
	}
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = mds.new(provs, {}, adj_sys, countries) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	_mm.call("initialize_from_map_data", map_data)
	if _mm.call("get_province", NEXT_PID) == null:
		_fail("MapManager missing next enemy province")
		return false
	print(
		"  [INFO] follow-on execute fixture GER %d → FRA %d → BEL %d"
		% [FROM_PID, TO_PID, NEXT_PID]
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
	f.set("name", "%s FoExecDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, DEF_DESIGN, TO_PID, 0.35, 0.4)
	_make_form(NEXT_FID, NEXT_TAG, NEXT_DESIGN, NEXT_PID, 0.4, 0.5)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.clear_unit_equipment_stock(NEXT_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: 40})
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 40})
	_pm.set_country_equipment_stockpile(NEXT_TAG, {NEXT_DESIGN: 40})
	return _failures == 0


func _reset_state() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_mm.call("update_province_owner", NEXT_PID, NEXT_TAG, NEXT_TAG, true)
	_mm.call("update_province_owner", RETREAT_PID, DEF_TAG, DEF_TAG, true)
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
	var nf = _lm.get_formation(NEXT_FID)
	if nf != null:
		nf.stationed_province_id = NEXT_PID
		nf.strength = 0.4
		nf.organization = 0.5
		nf.readiness = 0.5
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.clear_unit_equipment_stock(NEXT_FID)


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


func _do_first_capture() -> bool:
	for attempt in 8:
		_reset_state()
		var wrap: Dictionary = _bm.execute_province_assault(ATT_TAG, TO_PID, FROM_PID, ATT_FID)
		var result: Dictionary = wrap
		if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
			result = wrap["result"] as Dictionary
		var winner := str(result.get("winner", ""))
		var pcc := bool(result.get("province_control_change", false))
		print(
			"  [INFO] first capture attempt %d winner=%s pcc=%s att_st=%d def_st=%d owner=%s"
			% [attempt + 1, winner, str(pcc), _station(ATT_FID), _station(DEF_FID), _owner(TO_PID)]
		)
		if winner == "attacker" and pcc and _owner(TO_PID) == ATT_TAG:
			return true
	print("  [INFO] first capture stochastic miss; forced apply_combat_outcome")
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG


func _test_capture_then_follow_on_execute() -> void:
	if not _do_first_capture():
		_fail("could not produce first capture")
		return

	var att_st_after_cap := _station(ATT_FID)
	var def_st_after_cap := _station(DEF_FID)
	var owner_to := _owner(TO_PID)
	print(
		"  [INFO] post-first-capture att_st=%d def_st=%d owner=%s"
		% [att_st_after_cap, def_st_after_cap, owner_to]
	)
	if owner_to != ATT_TAG:
		_fail("first target owner should be %s, got %s" % [ATT_TAG, owner_to])
		return
	if att_st_after_cap != TO_PID:
		_fail("attacker station should be first target %d, got %d" % [TO_PID, att_st_after_cap])
		return
	if def_st_after_cap == TO_PID:
		_fail("first defender must leave captured %d" % TO_PID)
		return

	# Restore attacker combat readiness for follow-on (damage from first fight is realistic,
	# but execute must not be blocked — top up lightly so resolve path is exercised).
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.organization = maxf(float(af.organization), 0.85)
		af.readiness = maxf(float(af.readiness), 0.85)
		af.strength = maxf(float(af.strength), 0.9)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})

	var can: Dictionary = _bm.can_assault_province(ATT_TAG, NEXT_PID, TO_PID)
	print("  [INFO] pre-execute can_assault: %s" % str(can))
	if not bool(can.get("ok", false)):
		_fail("can_assault before follow-on execute failed: %s" % str(can.get("reason", can)))
		return

	var wrap2: Dictionary = _bm.execute_province_assault(ATT_TAG, NEXT_PID, TO_PID, ATT_FID)
	print("  [INFO] follow-on execute wrap: success=%s keys=%s" % [str(wrap2.get("success", wrap2)), str(wrap2.keys())])
	if not bool(wrap2.get("success", false)):
		_fail(
			"execute_province_assault follow-on blocked: %s"
			% str(wrap2.get("reason", wrap2))
		)
		return

	var result2: Dictionary = wrap2
	if wrap2.has("result") and typeof(wrap2.get("result")) == TYPE_DICTIONARY:
		result2 = wrap2["result"] as Dictionary
	var winner2 := str(result2.get("winner", "")).strip_edges()
	var has_scores := result2.has("attacker_score") or result2.has("defender_score")
	print(
		"  [INFO] follow-on result winner=%s scores att=%.3f def=%.3f pcc=%s owner_next=%s att_st=%d owner_first=%s"
		% [
			winner2,
			float(result2.get("attacker_score", 0.0)),
			float(result2.get("defender_score", 0.0)),
			str(result2.get("province_control_change", false)),
			_owner(NEXT_PID),
			_station(ATT_FID),
			_owner(TO_PID),
		]
	)
	if winner2.is_empty() and not has_scores:
		_fail("follow-on result missing winner and scores")
		return
	if winner2.is_empty():
		_fail("follow-on result must include winner field")
		return

	# First target still owned by attacker after follow-on attempt.
	if _owner(TO_PID) != ATT_TAG:
		_fail("first captured province owner must remain %s, got %s" % [ATT_TAG, _owner(TO_PID)])
		return
	# First-target defender still not on first target.
	if _station(DEF_FID) == TO_PID:
		_fail("first defender re-appeared on first target after follow-on")
		return
	# Attacker either still on first target, or advanced if second capture happened.
	var att_st_now := _station(ATT_FID)
	if att_st_now != TO_PID and att_st_now != NEXT_PID:
		_fail("attacker station unexpected %d (want first %d or next %d if captured)" % [att_st_now, TO_PID, NEXT_PID])
		return
	if bool(result2.get("province_control_change", false)) and winner2 == "attacker":
		if att_st_now != NEXT_PID:
			_fail("second capture should advance attacker station to %d, got %d" % [NEXT_PID, att_st_now])
			return
	elif att_st_now != TO_PID and not (winner2 == "attacker" and bool(result2.get("province_control_change", false))):
		# Non-capture follow-on: stay on first target
		if att_st_now != TO_PID:
			_fail("without second capture attacker should remain on first target %d, got %d" % [TO_PID, att_st_now])
			return

	_pass(
		"follow-on execute success=true winner=%s from_captured=%d → next=%d att_st=%d"
		% [winner2, TO_PID, NEXT_PID, att_st_now]
	)


func _test_equip_reinforce_after() -> void:
	_pm.set_unit_equipment_stock(DEF_FID, {})
	var f = _lm.get_formation(DEF_FID)
	if f != null and "strength" in f:
		f.strength = 0.45
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 12})
	var stock_b := int(_pm.get_country_equipment_stockpile(DEF_TAG).get(DEF_DESIGN, 0))
	_pm.daily_formation_reinforce_from_stockpile()
	var stock_a := int(_pm.get_country_equipment_stockpile(DEF_TAG).get(DEF_DESIGN, 0))
	var equip_d := int(_pm.get_unit_equipment_stock(DEF_FID).get(DEF_DESIGN, 0))
	print(
		"  [INFO] reinforce stock %d→%d def_equip=%d first_owner=%s att_st=%d"
		% [stock_b, stock_a, equip_d, _owner(TO_PID), _station(ATT_FID)]
	)
	if stock_a >= stock_b or equip_d < 1:
		_fail("reinforce did not drain stockpile / fill equip")
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("first capture ownership lost after reinforce")
		return
	if _station(DEF_FID) == TO_PID:
		_fail("first defender on captured province after reinforce")
		return
	_pass("post follow-on reinforce works; first capture ownership + stations sane")


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
