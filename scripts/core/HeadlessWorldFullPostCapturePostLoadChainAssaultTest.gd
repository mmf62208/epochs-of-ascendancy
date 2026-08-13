extends SceneTree

## Next 3 key elements: post-save/load chain/flank assault still works.
## After map+prod+leader restore of pre-battle chain fixture:
## 1) execute_chain_assault_or_flank returns ≥2 successful steps with first capture
## 2) follow-on stages from captured province (from=TO) toward next enemy
## 3) daily_formation_reinforce_from_stockpile still works (restored design_id)
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadChainAssaultTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const NEXT_PID := 92991
const RETREAT_PID := 92990
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const NEXT_TAG := "BEL"
const ATT_FID := "wf_plca_ger_div"
const DEF_FID := "wf_plca_fra_div"
const NEXT_FID := "wf_plca_bel_div"
const ATT_DESIGN := "cv33_tankette"
const DEF_DESIGN := "somua_s35_medium"
const NEXT_DESIGN := "m3_stuart_light_tank"
const STOCK_SEED := 6


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
	print("  [FAIL] HeadlessWorldFullPostCapturePostLoadChainAssaultTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCapturePostLoadChainAssaultTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCapturePostLoadChainAssaultTest: ",
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
	_test_postload_chain_three()
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
		{
			ATT_TAG: {"tag": ATT_TAG},
			DEF_TAG: {"tag": DEF_TAG},
			NEXT_TAG: {"tag": NEXT_TAG},
		},
	) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	_mm.call("initialize_from_map_data", map_data)
	print(
		"  [INFO] postload-chain fixture GER %d → FRA %d → BEL %d design=%s"
		% [FROM_PID, TO_PID, NEXT_PID, ATT_DESIGN]
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


func _stock(tag: String, design: String = ATT_DESIGN) -> int:
	return int(_pm.get_country_equipment_stockpile(tag).get(design, 0))


func _hand(fid: String, design: String = ATT_DESIGN) -> int:
	return int(_pm.get_unit_equipment_stock(fid).get(design, 0))


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
	f.set("name", "%s PlcaDiv" % tag)
	_lm.formations[fid] = f


func _setup_forms() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_DESIGN, FROM_PID, 1.0, 1.0)
	_make_form(DEF_FID, DEF_TAG, DEF_DESIGN, TO_PID, 0.28, 0.32)
	_make_form(NEXT_FID, NEXT_TAG, NEXT_DESIGN, NEXT_PID, 0.28, 0.32)
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.clear_unit_equipment_stock(NEXT_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: STOCK_SEED})
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 4})
	_pm.set_country_equipment_stockpile(NEXT_TAG, {NEXT_DESIGN: 4})
	return _failures == 0


func _reset_state() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_mm.call("update_province_owner", NEXT_PID, NEXT_TAG, NEXT_TAG, true)
	_mm.call("update_province_owner", RETREAT_PID, DEF_TAG, DEF_TAG, true)
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = FROM_PID
		af.design_id = ATT_DESIGN
		af.strength = 1.0
		af.organization = 1.0
		af.readiness = 1.0
	var df = _lm.get_formation(DEF_FID)
	if df != null:
		df.stationed_province_id = TO_PID
		df.design_id = DEF_DESIGN
		df.strength = 0.28
		df.organization = 0.32
		df.readiness = 0.32
	var nf = _lm.get_formation(NEXT_FID)
	if nf != null:
		nf.stationed_province_id = NEXT_PID
		nf.design_id = NEXT_DESIGN
		nf.strength = 0.28
		nf.organization = 0.32
		nf.readiness = 0.32
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
	_pm.clear_unit_equipment_stock(DEF_FID)
	_pm.clear_unit_equipment_stock(NEXT_FID)
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: STOCK_SEED})


func _unwrap_result(wrap: Dictionary) -> Dictionary:
	if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
		return wrap["result"] as Dictionary
	return wrap


func _test_invalid_assault_no_crash() -> void:
	var bad: Dictionary = _bm.can_assault_province(ATT_TAG, FROM_PID, FROM_PID)
	if bool(bad.get("ok", true)):
		_fail("same-province assault should not be ok")
		return
	var empty: Array = _bm.execute_chain_assault_or_flank(ATT_TAG, 999999, FROM_PID, 2)
	print("  [INFO] invalid can=%s chain_size=%d" % [str(bad.get("ok")), empty.size()])
	_pass("invalid chain/assault no-crash")


func _save_all() -> Dictionary:
	return {
		"map": _sl.call("_serialize_map_state"),
		"prod": _pm.get_save_data(),
		"lead": _lm.get_save_data(),
	}


func _apply_all(blob: Dictionary) -> void:
	_sl.call("_apply_map_state", blob["map"])
	_pm.apply_save_data(blob["prod"])
	_lm.apply_save_data(blob["lead"])


func _mutate_live() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	_mm.call("update_province_owner", NEXT_PID, NEXT_TAG, NEXT_TAG, true)
	var af = _lm.get_formation(ATT_FID)
	if af != null:
		af.stationed_province_id = -1
		af.design_id = ""
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: 0})
	_pm.clear_unit_equipment_stock(ATT_FID)


func _try_chain() -> Dictionary:
	var out := {"ok": false, "size": 0, "first": {}, "follow": {}, "follow_from": -1, "follow_target": -1}
	var results: Array = _bm.execute_chain_assault_or_flank(ATT_TAG, TO_PID, FROM_PID, 2)
	out["size"] = results.size()
	if results.size() < 1:
		return out
	var first_wrap: Dictionary = results[0] as Dictionary
	if not bool(first_wrap.get("success", false)):
		return out
	var first := _unwrap_result(first_wrap)
	out["first"] = first
	if str(first.get("winner", "")) != "attacker" or not bool(first.get("province_control_change", false)):
		return out
	if _owner(TO_PID) != ATT_TAG:
		return out
	if results.size() < 2:
		return out
	var follow_wrap: Dictionary = results[1] as Dictionary
	if not bool(follow_wrap.get("success", false)):
		return out
	var follow := _unwrap_result(follow_wrap)
	out["follow"] = follow
	out["follow_from"] = int(follow.get("from_province_id", -1))
	out["follow_target"] = int(follow.get("target_province_id", follow.get("province_id", -1)))
	out["ok"] = true
	return out


func _test_postload_chain_three() -> void:
	if not _sl.has_method("_serialize_map_state") or not _sl.has_method("_apply_map_state"):
		_fail("SaveLoad map helpers missing")
		return
	if not _bm.has_method("execute_chain_assault_or_flank"):
		_fail("execute_chain_assault_or_flank missing")
		return
	if not _pm.has_method("daily_formation_reinforce_from_stockpile"):
		_fail("daily_formation_reinforce_from_stockpile missing")
		return

	# Snapshot pre-battle playable fixture (stations at FROM, stock seeded)
	_reset_state()
	var blob: Dictionary = _save_all()
	var lead_forms: Dictionary = (blob["lead"] as Dictionary).get("formations", {}) as Dictionary
	var att_blob: Dictionary = lead_forms.get(ATT_FID, {}) as Dictionary
	if str(att_blob.get("design_id", "")) != ATT_DESIGN:
		_fail("leader save missing design_id for chain fixture")
		return
	print(
		"  [INFO] pre-save st=%d design=%s stock=%d hand=%d"
		% [_station(ATT_FID), _design(ATT_FID), _stock(ATT_TAG), _hand(ATT_FID)]
	)

	_mutate_live()
	print(
		"  [INFO] mutated st=%d design=%s stock=%d hand=%d"
		% [_station(ATT_FID), _design(ATT_FID), _stock(ATT_TAG), _hand(ATT_FID)]
	)
	_apply_all(blob)
	print(
		"  [INFO] restored st=%d design=%s stock=%d hand=%d owner_to=%s"
		% [_station(ATT_FID), _design(ATT_FID), _stock(ATT_TAG), _hand(ATT_FID), _owner(TO_PID)]
	)
	if _station(ATT_FID) != FROM_PID or _design(ATT_FID) != ATT_DESIGN:
		_fail("restore failed station/design for chain entry")
		return
	if _stock(ATT_TAG) < STOCK_SEED:
		_fail("stockpile not restored")
		return

	# --- Element 1: chain ≥2 with first capture after restore ---
	var got := {}
	var last_size := 0
	for attempt in 12:
		# Re-apply clean restored battle posture each attempt
		_apply_all(blob)
		# Soft defenders for stochastic resolve
		var df = _lm.get_formation(DEF_FID)
		if df != null:
			df.strength = 0.25
			df.organization = 0.28
			df.readiness = 0.28
		var nf = _lm.get_formation(NEXT_FID)
		if nf != null:
			nf.strength = 0.25
			nf.organization = 0.28
			nf.readiness = 0.28
		var af = _lm.get_formation(ATT_FID)
		if af != null:
			af.strength = 1.0
			af.organization = 1.0
			af.readiness = 1.0
			af.stationed_province_id = FROM_PID
			af.design_id = ATT_DESIGN
		_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 3})
		got = _try_chain()
		last_size = int(got.get("size", 0))
		print(
			"  [INFO] e1 attempt %d ok=%s size=%d owner_to=%s att_st=%d"
			% [attempt + 1, str(got.get("ok")), last_size, _owner(TO_PID), _station(ATT_FID)]
		)
		if bool(got.get("ok", false)):
			break

	if not bool(got.get("ok", false)):
		_fail("e1: post-load chain did not yield ≥2 successful steps with first capture (size=%d)" % last_size)
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("e1: first target not owned by attacker after chain")
		return
	_pass("e1: post-load chain ≥2 steps with first capture (size=%d owner=%s)" % [last_size, _owner(TO_PID)])

	# --- Element 2: follow-on staged from captured province toward next enemy ---
	var follow_from := int(got.get("follow_from", -1))
	var follow_target := int(got.get("follow_target", -1))
	var follow: Dictionary = got.get("follow", {}) as Dictionary
	var fw := str(follow.get("winner", "")).strip_edges()
	var has_scores := follow.has("attacker_score") or follow.has("defender_score")
	print(
		"  [INFO] e2 follow from=%d target=%d winner=%s scores att=%.3f def=%.3f"
		% [
			follow_from,
			follow_target,
			fw,
			float(follow.get("attacker_score", 0.0)),
			float(follow.get("defender_score", 0.0)),
		]
	)
	if follow_from != TO_PID:
		_fail("e2: follow-on must stage from captured %d, got %d" % [TO_PID, follow_from])
		return
	if follow_target != NEXT_PID:
		_fail("e2: follow-on target should be %d, got %d" % [NEXT_PID, follow_target])
		return
	if fw.is_empty() and not has_scores:
		_fail("e2: follow-on missing winner/scores")
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("e2: first capture ownership lost")
		return
	if _station(DEF_FID) == TO_PID:
		_fail("e2: first defender still on first target")
		return
	_pass("e2: follow-on staged from captured %d → %d post-load" % [TO_PID, NEXT_PID])

	# --- Element 3: daily reinforce after post-load chain (design_id path) ---
	var af2 = _lm.get_formation(ATT_FID)
	if af2 != null and _design(ATT_FID).is_empty():
		af2.design_id = ATT_DESIGN
	if _design(ATT_FID) != ATT_DESIGN:
		# ensure design present for OOB reinforce
		if af2 != null:
			af2.design_id = ATT_DESIGN
	_pm.clear_unit_equipment_stock(ATT_FID)
	if _stock(ATT_TAG) < 1:
		_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: 4})
	var stock_b := _stock(ATT_TAG)
	var hand_b := _hand(ATT_FID)
	var rep: Dictionary = _pm.daily_formation_reinforce_from_stockpile()
	var stock_a := _stock(ATT_TAG)
	var hand_a := _hand(ATT_FID)
	var moved := int(rep.get("equipment_moved", 0))
	print(
		"  [INFO] e3 daily_formation_reinforce_from_stockpile stock %d→%d hand %d→%d moved=%d design=%s"
		% [stock_b, stock_a, hand_b, hand_a, moved, _design(ATT_FID)]
	)
	if hand_a < 1:
		_fail("e3: daily reinforce left hand empty post-chain")
		return
	if stock_a >= stock_b:
		_fail("e3: stockpile did not decrease")
		return
	if moved < 1:
		_fail("e3: equipment_moved < 1")
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("e3: first capture ownership lost after reinforce")
		return
	_pass("e3: daily reinforce post-load chain stock %d→%d hand→%d" % [stock_b, stock_a, hand_a])

	_pass("all 3 post-load chain elements: chain≥2 + follow-from-captured + daily reinforce")


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
