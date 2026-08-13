extends SceneTree

## world_full post-capture follow-on assault entry from captured province.
## Capture GER 9276→FRA 9281 (attacker stations on 9281); then can_assault from 9281
## toward synthetic enemy neighbor 92991.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureFollowOnAssaultTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const NEXT_PID := 92991
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const NEXT_TAG := "BEL"
const ATT_FID := "wf_follow_ger_div"
const DEF_FID := "wf_follow_fra_div"
const ATT_DESIGN := "panzer_iii_j_medium"
const DEF_DESIGN := "somua_s35_medium"


var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _mm: Node = null
var _bm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldFullPostCaptureFollowOnAssaultTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureFollowOnAssaultTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureFollowOnAssaultTest: ",
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
	_test_capture_then_follow_on_can_assault()
	_test_equip_reinforce_after()
	_cleanup()
	if _bm:
		_bm.queue_free()


func _setup_map() -> bool:
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	# Staging (GER) — capture target (FRA) — next enemy (BEL); FRA rear for defender displace.
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

	from_p.set("id", FROM_PID)
	from_p.set("owner_tag", ATT_TAG)
	from_p.set("controller_tag", ATT_TAG)
	from_p.set("terrain", "plains")
	from_p.set("name", "GER Border")
	from_p.set("is_sea", false)
	from_p.set("development_level", 2)
	from_p.set("infrastructure", 2)

	to_p.set("id", TO_PID)
	to_p.set("owner_tag", DEF_TAG)
	to_p.set("controller_tag", DEF_TAG)
	to_p.set("terrain", "plains")
	to_p.set("name", "FRA Target")
	to_p.set("is_sea", false)
	to_p.set("development_level", 1)
	to_p.set("infrastructure", 1)

	next_p.set("id", NEXT_PID)
	next_p.set("owner_tag", NEXT_TAG)
	next_p.set("controller_tag", NEXT_TAG)
	next_p.set("terrain", "plains")
	next_p.set("name", "BEL Next")
	next_p.set("is_sea", false)
	next_p.set("development_level", 1)
	next_p.set("infrastructure", 1)

	ret_p.set("id", RETREAT_PID)
	ret_p.set("owner_tag", DEF_TAG)
	ret_p.set("controller_tag", DEF_TAG)
	ret_p.set("terrain", "plains")
	ret_p.set("name", "FRA Rear")
	ret_p.set("is_sea", false)
	ret_p.set("development_level", 1)
	ret_p.set("infrastructure", 1)

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
		"  [INFO] follow-on fixture GER %d → FRA %d → BEL %d (rear FRA %d)"
		% [FROM_PID, TO_PID, NEXT_PID, RETREAT_PID]
	)
	return true


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
	f.set("name", "%s FollowDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, DEF_DESIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: 40})
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 40})
	return _failures == 0


func _reset_capture_state() -> void:
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
	_reset_capture_state()
	# Prefer live execute; fall back to shipped apply_combat_outcome.
	for attempt in 8:
		_reset_capture_state()
		var wrap: Dictionary = _bm.execute_province_assault(ATT_TAG, TO_PID, FROM_PID, ATT_FID)
		var result: Dictionary = wrap
		if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
			result = wrap["result"] as Dictionary
		var winner := str(result.get("winner", ""))
		var pcc := bool(result.get("province_control_change", false))
		print(
			"  [INFO] capture attempt %d winner=%s pcc=%s att_st=%d def_st=%d owner=%s"
			% [attempt + 1, winner, str(pcc), _station(ATT_FID), _station(DEF_FID), _owner(TO_PID)]
		)
		if winner == "attacker" and pcc and _owner(TO_PID) == ATT_TAG:
			return true
	print("  [INFO] execute stochastic miss; forced apply_combat_outcome")
	_reset_capture_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG


func _test_capture_then_follow_on_can_assault() -> void:
	if not _do_capture():
		_fail("could not produce capture")
		return

	var att_st := _station(ATT_FID)
	var def_st := _station(DEF_FID)
	var owner_to := _owner(TO_PID)
	print(
		"  [INFO] post-capture att_st=%d def_st=%d owner=%s (want att=%d, def!=%d, owner=%s)"
		% [att_st, def_st, owner_to, TO_PID, TO_PID, ATT_TAG]
	)
	if owner_to != ATT_TAG:
		_fail("capture owner should be %s, got %s" % [ATT_TAG, owner_to])
		return
	if att_st != TO_PID:
		_fail("attacker station should be captured %d, got %d" % [TO_PID, att_st])
		return
	if def_st == TO_PID:
		_fail("defender station must leave captured %d, still %d" % [TO_PID, def_st])
		return

	# Presence at staging (captured province) via shipped lookup.
	var divs: Array = _bm.get_divisions_at_province(TO_PID, ATT_TAG)
	print("  [INFO] divisions at captured %d: %s" % [TO_PID, str(divs)])
	var found_fid := ""
	for d in divs:
		if typeof(d) == TYPE_DICTIONARY and str(d.get("formation_id", "")) == ATT_FID:
			found_fid = ATT_FID
			break
	if found_fid.is_empty():
		_fail("get_divisions_at_province(%d) must list attacker %s" % [TO_PID, ATT_FID])
		return

	# Follow-on entry: can_assault next enemy FROM captured province.
	var can: Dictionary = _bm.can_assault_province(ATT_TAG, NEXT_PID, TO_PID)
	print("  [INFO] follow-on can_assault: %s" % str(can))
	if not bool(can.get("ok", false)):
		_fail("can_assault from captured province failed: %s" % str(can.get("reason", can)))
		return
	var from_pid := int(can.get("from_province_id", -1))
	if from_pid != TO_PID:
		_fail("from_province_id should be captured %d, got %d" % [TO_PID, from_pid])
		return
	var can_fid := str(can.get("formation_id", "")).strip_edges()
	if can_fid.is_empty():
		_fail("can_assault must name a live formation at staging")
		return
	if can_fid != ATT_FID:
		_fail("expected formation %s at staging, got %s" % [ATT_FID, can_fid])
		return
	if str(can.get("defender_tag", "")).to_upper() != NEXT_TAG:
		_fail("defender_tag should be %s, got %s" % [NEXT_TAG, can.get("defender_tag")])
		return
	if int(can.get("target_province_id", -1)) != NEXT_PID:
		_fail("target_province_id should be %d" % NEXT_PID)
		return

	# Auto source lookup (no preferred from) should also find the captured staging.
	var can_auto: Dictionary = _bm.can_assault_province(ATT_TAG, NEXT_PID, -1)
	print("  [INFO] follow-on can_assault auto: %s" % str(can_auto))
	if not bool(can_auto.get("ok", false)):
		_fail("auto can_assault failed: %s" % str(can_auto.get("reason", can_auto)))
		return
	if int(can_auto.get("from_province_id", -1)) != TO_PID:
		_fail(
			"auto from_province_id should be captured %d, got %d"
			% [TO_PID, int(can_auto.get("from_province_id", -1))]
		)
		return

	_pass(
		"follow-on can_assault ok from captured %d → next %d formation=%s"
		% [TO_PID, NEXT_PID, can_fid]
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
		"  [INFO] reinforce stock %d→%d def_equip=%d att_st=%d def_st=%d"
		% [stock_b, stock_a, equip_d, _station(ATT_FID), _station(DEF_FID)]
	)
	if stock_a >= stock_b or equip_d < 1:
		_fail("reinforce did not drain stockpile / fill equip")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station must remain on captured province after reinforce")
		return
	# Follow-on still ok after reinforce.
	var can: Dictionary = _bm.can_assault_province(ATT_TAG, NEXT_PID, TO_PID)
	if not bool(can.get("ok", false)):
		_fail("follow-on can_assault broken after reinforce: %s" % str(can.get("reason", can)))
		return
	_pass("post-capture reinforce works; follow-on can_assault still ok")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_FID)
		_lm.formations.erase(DEF_FID)


func _cleanup() -> void:
	_cleanup_forms()
