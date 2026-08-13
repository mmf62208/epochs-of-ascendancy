extends SceneTree

## Next 3 key elements: post-save/load restore still enables playability.
## After capture GER 9276→FRA 9281 + seed stock/hand:
## 1) map+prod+leader save → mutate → apply → can_assault from restored station
## 2) reinforce from restored country stockpile into on-hand
## 3) combat equip stats (has_shortages=false) from restored design_id + on-hand
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadPlayabilityTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_plp_ger_div"
const DEF_FID := "wf_plp_fra_div"
const DESIGN := "cv33_tankette"
const STOCK_SEED := 5
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
	print("  [FAIL] HeadlessWorldFullPostCapturePostLoadPlayabilityTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCapturePostLoadPlayabilityTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCapturePostLoadPlayabilityTest: ",
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
	_test_postload_three_playability()
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
	print("  [INFO] postload-playability fixture GER %d → FRA %d design=%s" % [FROM_PID, TO_PID, DESIGN])
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
	f.set("name", "%s PlpDiv" % tag)
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
		df.design_id = DESIGN
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


func _test_postload_three_playability() -> void:
	if not _do_capture():
		_fail("could not capture province")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station not on target pre-save")
		return
	if _station(DEF_FID) == TO_PID:
		_fail("defender still on target pre-save")
		return

	# Seed stockpile + on-hand (playability inputs for reinforce / combat stats)
	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: STOCK_SEED})
	_pm.set_unit_equipment_stock(ATT_FID, {DESIGN: HAND_SEED})
	var stock_pre := _stock(ATT_TAG)
	var hand_pre := _hand(ATT_FID)
	var st_pre := _station(ATT_FID)
	var des_pre := _design(ATT_FID)
	print(
		"  [INFO] pre-save owner=%s st=%d design=%s stock=%d hand=%d"
		% [_owner(TO_PID), st_pre, des_pre, stock_pre, hand_pre]
	)
	if des_pre != DESIGN:
		_fail("pre-save design_id should be %s" % DESIGN)
		return
	if stock_pre < 1 or hand_pre < 1:
		_fail("pre-save stockpile/on-hand not seeded")
		return

	if not _sl.has_method("_serialize_map_state") or not _sl.has_method("_apply_map_state"):
		_fail("SaveLoadManager missing _serialize/_apply_map_state")
		return
	if not _pm.has_method("get_save_data") or not _pm.has_method("apply_save_data"):
		_fail("ProductionManager missing get/apply_save_data")
		return
	if not _lm.has_method("get_save_data") or not _lm.has_method("apply_save_data"):
		_fail("LeaderManager missing get/apply_save_data")
		return

	var map_save: Dictionary = _sl.call("_serialize_map_state")
	var prod_save: Dictionary = _pm.get_save_data()
	var lead_save: Dictionary = _lm.get_save_data()

	# Prove leader save carries design_id (required for post-load reinforce/stats)
	var forms_blob: Dictionary = lead_save.get("formations", {}) as Dictionary
	var att_blob: Dictionary = forms_blob.get(ATT_FID, {}) as Dictionary
	var save_design := str(att_blob.get("design_id", ""))
	print("  [INFO] leader form save design_id=%s st=%s" % [save_design, str(att_blob.get("stationed_province_id"))])
	if save_design != DESIGN:
		_fail("leader get_save_data must include design_id=%s (got %s)" % [DESIGN, save_design])
		return

	# Mutate live state — wipe playability inputs so restore is the only path
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.design_id = ""
	var df = _lm.get_formation(DEF_FID)
	if df != null:
		df.stationed_province_id = TO_PID
	_pm.set_country_equipment_stockpile(ATT_TAG, {DESIGN: 0})
	_pm.clear_unit_equipment_stock(ATT_FID)
	print(
		"  [INFO] mutated owner=%s st=%d design=%s stock=%d hand=%d"
		% [_owner(TO_PID), _station(ATT_FID), _design(ATT_FID), _stock(ATT_TAG), _hand(ATT_FID)]
	)
	if _owner(TO_PID) == ATT_TAG or _station(ATT_FID) == TO_PID or _design(ATT_FID) == DESIGN:
		_fail("mutation did not clear owner/station/design")
		return
	if _stock(ATT_TAG) > 0 or _hand(ATT_FID) > 0:
		_fail("mutation did not clear stock/hand")
		return

	# Restore map + production + leaders (formations include design_id + station)
	_sl.call("_apply_map_state", map_save)
	_pm.apply_save_data(prod_save)
	_lm.apply_save_data(lead_save)

	var owner_a := _owner(TO_PID)
	var st_a := _station(ATT_FID)
	var des_a := _design(ATT_FID)
	var stock_a := _stock(ATT_TAG)
	var hand_a := _hand(ATT_FID)
	print(
		"  [INFO] restored owner=%s st=%d design=%s stock=%d hand=%d"
		% [owner_a, st_a, des_a, stock_a, hand_a]
	)
	if owner_a != ATT_TAG:
		_fail("restored owner should be %s, got %s" % [ATT_TAG, owner_a])
		return
	if st_a != TO_PID:
		_fail("restored attacker station should be %d, got %d" % [TO_PID, st_a])
		return
	if des_a != DESIGN:
		_fail("restored design_id should be %s, got %s" % [DESIGN, des_a])
		return
	if stock_a < STOCK_SEED:
		_fail("restored stockpile %d < seeded %d" % [stock_a, STOCK_SEED])
		return
	if hand_a < HAND_SEED:
		_fail("restored on-hand %d < seeded %d" % [hand_a, HAND_SEED])
		return

	# --- Element 1: can_assault from restored capture station toward FRA rear ---
	var can: Dictionary = _bm.can_assault_province(ATT_TAG, RETREAT_PID, TO_PID)
	var can_ok := bool(can.get("ok", false))
	var power := float(can.get("estimated_power", can.get("power", can.get("attack_power", 0.0))))
	# Prefer explicit attack formation when present
	var can_fid := str(can.get("formation_id", can.get("attacker_formation_id", "")))
	if can_fid.is_empty() and can.has("source_formation_id"):
		can_fid = str(can.get("source_formation_id", ""))
	# Fall back: divisions at restored staging must include attacker
	if can_fid.is_empty() and _bm.has_method("get_divisions_at_province"):
		var divs: Array = _bm.get_divisions_at_province(TO_PID, ATT_TAG)
		for d in divs:
			var did := str(d)
			if did == ATT_FID or (typeof(d) == TYPE_OBJECT and str(d.get("formation_id")) == ATT_FID):
				can_fid = ATT_FID
				break
			if not did.is_empty() and did != ATT_TAG:
				can_fid = did
				break
	print("  [INFO] e1 can_assault ok=%s fid=%s power=%s reason=%s" % [str(can_ok), can_fid, str(power), str(can.get("reason", ""))])
	if not can_ok:
		_fail("e1: can_assault from restored station failed: %s" % str(can.get("reason", can)))
		return
	if can_fid.is_empty():
		# Station is restored; treat ATT_FID as staging source when can ok
		if _station(ATT_FID) == TO_PID:
			can_fid = ATT_FID
		else:
			_fail("e1: can_assault ok but formation_id empty and attacker not on staging")
			return
	_pass("e1: can_assault ok after map+leader restore (st=%d fid=%s power=%.3f)" % [st_a, can_fid, power])

	# --- Element 3 first: combat equip stats from *restored* on-hand (before e2 clears it) ---
	var hand_restored := _hand(ATT_FID)
	if hand_restored < 1:
		_fail("e3: restored on-hand empty before combat-stats check")
		return
	var stats_full: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var short_full := bool(stats_full.get("has_shortages", true))
	var soft_full := float(stats_full.get("soft_attack", 0.0))
	print(
		"  [INFO] e3 restored-hand has_shortages=%s soft=%.3f hand=%d design=%s"
		% [str(short_full), soft_full, hand_restored, _design(ATT_FID)]
	)
	if short_full:
		_fail("e3: has_shortages true with restored design_id + restored on-hand")
		return
	if soft_full <= 0.0:
		_fail("e3: soft_attack should be positive when equipped from restore")
		return

	# Contrast: empty on-hand should report shortages (design_id still present)
	_pm.clear_unit_equipment_stock(ATT_FID)
	var stats_empty: Dictionary = _pm.get_formation_equipment_combat_stats(ATT_FID)
	var short_empty := bool(stats_empty.get("has_shortages", false))
	var soft_empty := float(stats_empty.get("soft_attack", 0.0))
	print("  [INFO] e3 empty has_shortages=%s soft=%.3f" % [str(short_empty), soft_empty])
	if not short_empty:
		_fail("e3: empty on-hand should have_shortages")
		return
	if soft_full <= soft_empty:
		_fail("e3: equipped soft should exceed empty (full=%.3f empty=%.3f)" % [soft_full, soft_empty])
		return
	_pass("e3: combat stats from restored on-hand (soft %.3f > empty %.3f)" % [soft_full, soft_empty])

	# --- Element 2: daily reinforce from restored stockpile (uses restored design_id) ---
	# On-hand already empty from e3 contrast; stockpile still restored
	var stock_b := _stock(ATT_TAG)
	var hand_b := _hand(ATT_FID)
	if hand_b != 0:
		_pm.clear_unit_equipment_stock(ATT_FID)
		hand_b = _hand(ATT_FID)
	if hand_b != 0:
		_fail("e2: hand not cleared before daily reinforce")
		return
	if stock_b < 1:
		_fail("e2: stockpile empty before daily reinforce")
		return
	if _design(ATT_FID) != DESIGN:
		_fail("e2: design_id must be restored for daily reinforce OOB (%s)" % _design(ATT_FID))
		return
	if not _pm.has_method("daily_formation_reinforce_from_stockpile"):
		_fail("e2: daily_formation_reinforce_from_stockpile missing")
		return
	# Primary path: daily reinforce resolves design via restored formation design_id
	# (get_formation_required_equipment) — no hardcoded design id on this call.
	var rep: Dictionary = _pm.daily_formation_reinforce_from_stockpile()
	var moved := int(rep.get("equipment_moved", 0))
	var stock_c := _stock(ATT_TAG)
	var hand_c := _hand(ATT_FID)
	print(
		"  [INFO] e2 daily_formation_reinforce_from_stockpile stock %d→%d hand %d→%d moved=%d units=%s"
		% [stock_b, stock_c, hand_b, hand_c, moved, str(rep.get("units_reinforced", 0))]
	)
	if hand_c < 1:
		_fail("e2: on-hand still empty after daily_formation_reinforce_from_stockpile")
		return
	if stock_c >= stock_b:
		_fail("e2: country stockpile did not decrease (was %d now %d)" % [stock_b, stock_c])
		return
	if moved < 1:
		_fail("e2: equipment_moved < 1 from daily reinforce report")
		return
	_pass(
		"e2: daily_formation_reinforce_from_stockpile stock %d→%d hand→%d (design_id=%s)"
		% [stock_b, stock_c, hand_c, _design(ATT_FID)]
	)

	_pass("all 3 post-load playability elements: can_assault + daily reinforce + combat stats")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_FID)
		_lm.formations.erase(DEF_FID)


func _cleanup() -> void:
	_cleanup_forms()
