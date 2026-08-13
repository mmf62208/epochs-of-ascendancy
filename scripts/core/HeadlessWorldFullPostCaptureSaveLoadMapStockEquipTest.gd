extends SceneTree

## Next 3 key elements: map ownership, country stockpile, unit equip survive save/load.
## After capture GER 9276→FRA 9281:
## 1) SaveLoadManager _serialize/_apply_map_state restores owner/controller
## 2) ProductionManager get/apply_save_data restores country stockpile
## 3) ProductionManager restores unit on-hand equip (+ combat no shortage)
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_mse_ger_div"
const DEF_FID := "wf_mse_fra_div"
const DESIGN := "cv33_tankette"
const STOCK_SEED := 7
const HAND_SEED := 2


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
	print("  [FAIL] HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest: ",
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
	print("  [INFO] map-stock-equip saveload fixture GER %d → FRA %d design=%s" % [FROM_PID, TO_PID, DESIGN])
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


func _controller(pid: int) -> String:
	if _mm.has_method("get_province_controller"):
		return str(_mm.call("get_province_controller", pid)).to_upper()
	var p = _mm.call("get_province", pid)
	if p == null:
		return ""
	var c := str(p.controller_tag).strip_edges().to_upper()
	return c if not c.is_empty() else str(p.owner_tag).strip_edges().to_upper()


func _station(fid: String) -> int:
	var f = _lm.get_formation(fid)
	if f == null or not ("stationed_province_id" in f):
		return -999
	return int(f.stationed_province_id)


func _stock(tag: String) -> int:
	return int(_pm.get_country_equipment_stockpile(tag).get(DESIGN, 0))


func _hand(fid: String) -> int:
	return int(_pm.get_unit_equipment_stock(fid).get(DESIGN, 0))


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
	f.set("name", "%s MseDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, DESIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {DESIGN: 0})
	return _failures == 0


func _reset_state() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
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
		df.strength = 0.35
		df.organization = 0.4
		df.readiness = 0.4
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: 0})
	_pm.set_country_equipment_stockpile(DEF_TAG, {DESIGN: 0})


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
				and _owner(TO_PID) == ATT_TAG:
			print(
				"  [INFO] capture attempt %d ok owner=%s att_st=%d def_st=%d"
				% [attempt + 1, _owner(TO_PID), _station(ATT_FID), _station(DEF_FID)]
			)
			return true
	print("  [INFO] forced apply_combat_outcome for capture")
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG


func _test_saveload_three_elements() -> void:
	if not _do_capture():
		_fail("could not capture province")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station not on target")
		return
	if _station(DEF_FID) == TO_PID:
		_fail("defender still on target")
		return

	# Seed stockpile + on-hand via shipped setters (post-capture state)
	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: STOCK_SEED})
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: HAND_SEED})
	var stock_pre := _stock(ATT_TAG)
	var hand_pre := _hand(ATT_FID)
	var owner_pre := _owner(TO_PID)
	var ctrl_pre := _controller(TO_PID)
	print(
		"  [INFO] pre-save owner=%s ctrl=%s stock=%d hand=%d"
		% [owner_pre, ctrl_pre, stock_pre, hand_pre]
	)
	if owner_pre != ATT_TAG or ctrl_pre != ATT_TAG:
		_fail("pre-save owner/controller should be %s" % ATT_TAG)
		return
	if stock_pre < 1 or hand_pre < 1:
		_fail("pre-save stockpile/on-hand not seeded")
		return

	# Snapshot shipped map + production
	if not _sl.has_method("_serialize_map_state") or not _sl.has_method("_apply_map_state"):
		_fail("SaveLoadManager missing _serialize/_apply_map_state")
		return
	if not _pm.has_method("get_save_data") or not _pm.has_method("apply_save_data"):
		_fail("ProductionManager missing get/apply_save_data")
		return

	var map_save: Dictionary = _sl.call("_serialize_map_state")
	var prod_save: Dictionary = _pm.get_save_data()
	# Validate map payload structure via shipped audit when available
	if _sl.has_method("validate_map_save_payload"):
		var val: Dictionary = _sl.call("validate_map_save_payload", map_save)
		print("  [INFO] map payload validate ok=%s provinces=%s" % [str(val.get("ok")), str(val.get("province_count"))])
		if not bool(val.get("ok", false)):
			_fail("map save payload validation failed: %s" % str(val.get("missing")))
			return
	if not prod_save.has("country_equipment_stockpiles") or not prod_save.has("unit_equipment_stock"):
		_fail("production save missing stockpile/unit equip keys")
		return

	# Mutate live state
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: 0})
	_pm.clear_unit_equipment_stock(ATT_FID)
	print(
		"  [INFO] mutated owner=%s stock=%d hand=%d"
		% [_owner(TO_PID), _stock(ATT_TAG), _hand(ATT_FID)]
	)
	if _owner(TO_PID) == ATT_TAG or _stock(ATT_TAG) > 0 or _hand(ATT_FID) > 0:
		_fail("mutation did not clear owner/stock/hand")
		return

	# Restore
	_sl.call("_apply_map_state", map_save)
	_pm.apply_save_data(prod_save)

	# Element 1: map ownership
	var owner_a := _owner(TO_PID)
	var ctrl_a := _controller(TO_PID)
	print("  [INFO] e1 restored owner=%s ctrl=%s" % [owner_a, ctrl_a])
	if owner_a != ATT_TAG:
		_fail("e1: owner should be %s after map apply, got %s" % [ATT_TAG, owner_a])
		return
	if ctrl_a != ATT_TAG:
		_fail("e1: controller should be %s after map apply, got %s" % [ATT_TAG, ctrl_a])
		return
	_pass("e1: captured province owner/controller survived map save/load")

	# Element 2: country stockpile
	var stock_a := _stock(ATT_TAG)
	var def_stock := _stock(DEF_TAG)
	print("  [INFO] e2 restored att_stock=%d (want ≥%d) def_stock=%d" % [stock_a, stock_pre, def_stock])
	if stock_a < stock_pre:
		_fail("e2: attacker stockpile %d < pre-save %d after production apply" % [stock_a, stock_pre])
		return
	if stock_a < 1:
		_fail("e2: attacker stockpile zero after restore")
		return
	_pass("e2: attacker country stockpile survived production save/load (%d)" % stock_a)

	# Element 3: unit on-hand
	var hand_a := _hand(ATT_FID)
	print("  [INFO] e3 restored hand=%d (want ≥1)" % hand_a)
	if hand_a < 1:
		_fail("e3: unit on-hand empty after production apply")
		return
	if hand_a < HAND_SEED:
		_fail("e3: on-hand %d < seeded %d" % [hand_a, HAND_SEED])
		return
	var stats: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var short := bool(stats.get("has_shortages", true))
	print("  [INFO] e3 combat has_shortages=%s soft=%.3f" % [str(short), float(stats.get("soft_attack", 0.0))])
	if short:
		_fail("e3: combat stats still has_shortages after equip restore")
		return
	# Stations still sane (not part of map/prod save but capture fixture)
	if _station(ATT_FID) != TO_PID:
		_fail("e3: attacker station drifted off target")
		return
	_pass("e3: unit on-hand equip survived production save/load (hand=%d, no shortages)" % hand_a)

	_pass("all 3 saveload elements: map owner + country stockpile + unit equip")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_FID)
		_lm.formations.erase(DEF_FID)


func _cleanup() -> void:
	_cleanup_forms()
