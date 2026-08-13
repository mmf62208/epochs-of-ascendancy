extends SceneTree

## Next 3 key elements: full slot save_game_detailed / load_game_detailed round-trip.
## After capture GER 9276→FRA 9281 + seed stock/hand/design:
## 1) save_game_detailed(slot) ok → file exists
## 2) mutate live owner/station/design/stock/hand
## 3) load_game_detailed restores map owner, prod stock/hand, leader station+design
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_plsl_ger_div"
const DEF_FID := "wf_plsl_fra_div"
const DESIGN := "cv33_tankette"
const STOCK_SEED := 7
const HAND_SEED := 3
const SLOT := "eoa_test_postload_slot_wf"


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
	print("  [FAIL] HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest: ",
		"PASS" if ok else "FAIL",
		" (failures=", _failures, ")"
	)
	# Best-effort cleanup of test slot
	if _sl != null and _sl.has_method("delete_save"):
		_sl.delete_save(SLOT)
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
	_test_slot_saveload_three()
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
	print("  [INFO] postload-slot-saveload fixture GER %d → FRA %d slot=%s" % [FROM_PID, TO_PID, SLOT])
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


func _design(fid: String) -> String:
	var f = _lm.get_formation(fid)
	if f == null or not ("design_id" in f):
		return ""
	return str(f.design_id)


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
	f.set("name", "%s PlslDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, DESIGN, TO_PID, 0.35, 0.4)
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: 0})
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


func _forced_capture() -> Dictionary:
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
			return true
	_reset_state()
	_bm.apply_combat_outcome(_forced_capture(), ATT_FID, FROM_PID)
	return _owner(TO_PID) == ATT_TAG


func _test_slot_saveload_three() -> void:
	if not _do_capture():
		_fail("capture failed")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station not on target")
		return

	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: STOCK_SEED})
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: HAND_SEED})
	var owner_pre := _owner(TO_PID)
	var ctrl_pre := _controller(TO_PID)
	var st_pre := _station(ATT_FID)
	var des_pre := _design(ATT_FID)
	var stock_pre := _stock(ATT_TAG)
	var hand_pre := _hand(ATT_FID)
	print(
		"  [INFO] pre-slot-save owner=%s st=%d design=%s stock=%d hand=%d"
		% [owner_pre, st_pre, des_pre, stock_pre, hand_pre]
	)

	if not _sl.has_method("save_game_detailed") or not _sl.has_method("load_game_detailed"):
		_fail("save/load_game_detailed missing")
		return
	if not _sl.has_method("get_save_path"):
		_fail("get_save_path missing")
		return

	# Clean prior test slot
	if _sl.has_method("delete_save"):
		_sl.delete_save(SLOT)

	# --- Element 1: save_game_detailed writes slot ---
	var save_res: Dictionary = _sl.save_game_detailed(SLOT)
	print("  [INFO] e1 save ok=%s path=%s bytes=%s" % [str(save_res.get("ok")), str(save_res.get("path")), str(save_res.get("bytes"))])
	if not bool(save_res.get("ok", false)):
		_fail("e1: save_game_detailed failed: %s" % str(save_res.get("error", save_res)))
		return
	var path := str(save_res.get("path", _sl.get_save_path(SLOT)))
	if path.is_empty() or not FileAccess.file_exists(path):
		_fail("e1: save file missing at %s" % path)
		return
	if int(save_res.get("bytes", 0)) < 100:
		_fail("e1: save payload too small")
		return
	# Payload must include map + production + leaders keys
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("e1: save JSON not object")
		return
	var data: Dictionary = parsed
	if not data.has("map") or not data.has("production") or not data.has("leaders"):
		_fail("e1: save missing map/production/leaders sections")
		return
	_pass("e1: save_game_detailed slot ok path=%s bytes=%s" % [path, str(save_res.get("bytes"))])

	# --- Element 2: mutate live so load is the only recovery path ---
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.design_id = ""
	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: 0})
	_pm.clear_unit_equipment_stock(ATT_FID)
	print(
		"  [INFO] e2 mutated owner=%s st=%d design=%s stock=%d hand=%d"
		% [_owner(TO_PID), _station(ATT_FID), _design(ATT_FID), _stock(ATT_TAG), _hand(ATT_FID)]
	)
	if _owner(TO_PID) == ATT_TAG or _station(ATT_FID) == TO_PID or _design(ATT_FID) == DESIGN:
		_fail("e2: mutation incomplete")
		return
	if _stock(ATT_TAG) > 0 or _hand(ATT_FID) > 0:
		_fail("e2: stock/hand not cleared")
		return
	_pass("e2: live state mutated (owner/station/design/stock/hand cleared)")

	# --- Element 3: load_game_detailed restores conquest playability state ---
	var load_res: Dictionary = _sl.load_game_detailed(SLOT)
	print("  [INFO] e3 load ok=%s path=%s" % [str(load_res.get("ok")), str(load_res.get("path"))])
	if not bool(load_res.get("ok", false)):
		_fail("e3: load_game_detailed failed: %s" % str(load_res.get("error", load_res)))
		return
	var owner_a := _owner(TO_PID)
	var ctrl_a := _controller(TO_PID)
	var st_a := _station(ATT_FID)
	var des_a := _design(ATT_FID)
	var stock_a := _stock(ATT_TAG)
	var hand_a := _hand(ATT_FID)
	print(
		"  [INFO] e3 restored owner=%s ctrl=%s st=%d design=%s stock=%d hand=%d"
		% [owner_a, ctrl_a, st_a, des_a, stock_a, hand_a]
	)
	if owner_a != ATT_TAG:
		_fail("e3: map owner should be %s, got %s" % [ATT_TAG, owner_a])
		return
	if ctrl_a != ATT_TAG:
		_fail("e3: map controller should be %s, got %s" % [ATT_TAG, ctrl_a])
		return
	if st_a != TO_PID:
		_fail("e3: station should be %d, got %d" % [TO_PID, st_a])
		return
	if des_a != DESIGN:
		_fail("e3: design_id should be %s, got %s" % [DESIGN, des_a])
		return
	if stock_a < STOCK_SEED:
		_fail("e3: stockpile %d < seeded %d" % [stock_a, STOCK_SEED])
		return
	if hand_a < HAND_SEED:
		_fail("e3: on-hand %d < seeded %d" % [hand_a, HAND_SEED])
		return
	# Playability smoke: can_assault from restored station
	var can: Dictionary = _bm.can_assault_province(ATT_TAG, RETREAT_PID, TO_PID)
	if not bool(can.get("ok", false)):
		_fail("e3: can_assault after slot load failed: %s" % str(can.get("reason", can)))
		return
	_pass(
		"e3: load_game_detailed restored owner/station/design/stock/hand; can_assault ok"
	)

	_pass("all 3 slot saveload elements: save + mutate + load restore")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_FID)
		_lm.formations.erase(DEF_FID)


func _cleanup() -> void:
	_cleanup_forms()
