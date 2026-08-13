extends SceneTree

## world_full post-capture **chain/flank** assault via shipped execute_chain_assault_or_flank.
## First capture GER 9276→FRA 9281; follow-on from 9281 → BEL 92991 (synthetic).
## Assert: results.size() ≥ 2, first capture ownership, follow-on execute success.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureChainAssaultTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const NEXT_PID := 92991
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const NEXT_TAG := "BEL"
const ATT_FID := "wf_chain_ger_div"
const DEF_FID := "wf_chain_fra_div"
const NEXT_FID := "wf_chain_bel_div"
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
	print("  [FAIL] HeadlessWorldFullPostCaptureChainAssaultTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureChainAssaultTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureChainAssaultTest: ",
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
	_test_chain_after_capture()
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
	print("  [INFO] chain fixture GER %d → FRA %d → BEL %d" % [FROM_PID, TO_PID, NEXT_PID])
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
	f.set("name", "%s ChainDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, DEF_DESIGN, TO_PID, 0.35, 0.4)
	_make_form(NEXT_FID, NEXT_TAG, NEXT_DESIGN, NEXT_PID, 0.35, 0.4)
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
		nf.strength = 0.35
		nf.organization = 0.4
		nf.readiness = 0.4
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.clear_unit_equipment_stock(NEXT_FID)


func _unwrap_result(wrap: Dictionary) -> Dictionary:
	if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
		return wrap["result"] as Dictionary
	return wrap


func _test_invalid_assault_no_crash() -> void:
	var bad: Dictionary = _bm.can_assault_province(ATT_TAG, FROM_PID, FROM_PID)
	if bool(bad.get("ok", true)):
		_fail("same-province assault should not be ok")
		return
	var bad2: Dictionary = _bm.execute_province_assault(ATT_TAG, 999999, FROM_PID, ATT_FID)
	print("  [INFO] invalid can=%s exec_success=%s" % [str(bad.get("ok")), str(bad2.get("success", bad2))])
	_pass("invalid single assault no-crash")


func _test_chain_after_capture() -> void:
	var got_chain := false
	var last_size := 0
	var last_first: Dictionary = {}
	var last_follow: Dictionary = {}
	# Prefer real chain path; retry if first capture fails stochastically.
	for attempt in 10:
		_reset_state()
		var results: Array = _bm.execute_chain_assault_or_flank(ATT_TAG, TO_PID, FROM_PID, 2)
		last_size = results.size()
		print("  [INFO] chain attempt %d size=%d att_st=%d owner_to=%s owner_next=%s" % [
			attempt + 1, last_size, _station(ATT_FID), _owner(TO_PID), _owner(NEXT_PID)
		])
		if last_size < 1:
			continue
		var first_wrap: Dictionary = results[0] as Dictionary
		if not bool(first_wrap.get("success", false)):
			continue
		last_first = _unwrap_result(first_wrap)
		var pcc := bool(last_first.get("province_control_change", false))
		var winner := str(last_first.get("winner", ""))
		print(
			"  [INFO]   first winner=%s pcc=%s from=%s target=%s"
			% [winner, str(pcc), str(last_first.get("from_province_id", "")), str(last_first.get("target_province_id", ""))]
		)
		if winner != "attacker" or not pcc or _owner(TO_PID) != ATT_TAG:
			continue
		# After first capture, station should be on first target (unless follow-on already advanced).
		var att_st := _station(ATT_FID)
		if att_st != TO_PID and att_st != NEXT_PID:
			_fail("after first capture in chain, att station unexpected %d" % att_st)
			return
		if last_size < 2:
			print("  [INFO]   first capture ok but chain length 1 (no follow-on yet); retry")
			continue
		last_follow = results[1] as Dictionary
		if not bool(last_follow.get("success", false)):
			print("  [INFO]   follow-on wrap not success: %s" % str(last_follow))
			continue
		var follow_res := _unwrap_result(last_follow)
		var fw := str(follow_res.get("winner", "")).strip_edges()
		var has_scores := follow_res.has("attacker_score") or follow_res.has("defender_score")
		var follow_from := int(follow_res.get("from_province_id", -1))
		var follow_target := int(follow_res.get("target_province_id", follow_res.get("province_id", -1)))
		print(
			"  [INFO]   follow-on success winner=%s from=%d target=%d scores att=%.3f def=%.3f"
			% [
				fw,
				follow_from,
				follow_target,
				float(follow_res.get("attacker_score", 0.0)),
				float(follow_res.get("defender_score", 0.0)),
			]
		)
		if fw.is_empty() and not has_scores:
			_fail("follow-on result missing winner and scores")
			return
		if follow_from != TO_PID:
			_fail("follow-on must stage from captured %d, got from=%d" % [TO_PID, follow_from])
			return
		if follow_target != NEXT_PID:
			_fail("follow-on target should be next enemy %d, got %d" % [NEXT_PID, follow_target])
			return
		if _owner(TO_PID) != ATT_TAG:
			_fail("first target ownership lost during chain")
			return
		if _station(DEF_FID) == TO_PID:
			_fail("first defender still on first target after chain")
			return
		got_chain = true
		break

	if not got_chain:
		# Controlled first capture then re-invoke chain only works if we call chain from scratch.
		# Force attacker-favored state and call chain once more.
		print("  [INFO] stochastic miss; one more chain with refreshed attacker-favored forms")
		_reset_state()
		# Soften defenders further
		var df = _lm.get_formation(DEF_FID)
		if df != null:
			df.strength = 0.25
			df.organization = 0.3
			df.readiness = 0.3
		var nf = _lm.get_formation(NEXT_FID)
		if nf != null:
			nf.strength = 0.25
			nf.organization = 0.3
			nf.readiness = 0.3
		var results2: Array = _bm.execute_chain_assault_or_flank(ATT_TAG, TO_PID, FROM_PID, 2)
		last_size = results2.size()
		print("  [INFO] forced-favor chain size=%d" % last_size)
		if last_size >= 2 and bool((results2[0] as Dictionary).get("success", false)) \
				and bool((results2[1] as Dictionary).get("success", false)) \
				and _owner(TO_PID) == ATT_TAG:
			var fr := _unwrap_result(results2[1] as Dictionary)
			if int(fr.get("from_province_id", -1)) == TO_PID:
				got_chain = true
				last_follow = results2[1] as Dictionary
				last_first = _unwrap_result(results2[0] as Dictionary)

	if not got_chain:
		_fail(
			"chain API did not return ≥2 successful steps with first capture (last_size=%d owner_to=%s)"
			% [last_size, _owner(TO_PID)]
		)
		return

	print(
		"  [INFO] chain PASS size=%d first_owner=%s att_st=%d follow_success=%s"
		% [last_size, _owner(TO_PID), _station(ATT_FID), str(last_follow.get("success", false))]
	)
	_pass(
		"chain/flank ≥2 steps: first capture %d + follow-on execute from captured staging"
		% TO_PID
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
		"  [INFO] reinforce stock %d→%d def_equip=%d first_owner=%s"
		% [stock_b, stock_a, equip_d, _owner(TO_PID)]
	)
	if stock_a >= stock_b or equip_d < 1:
		_fail("reinforce did not drain stockpile / fill equip")
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("first capture ownership lost after reinforce")
		return
	_pass("post-chain reinforce works; first capture ownership held")


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
