extends SceneTree

## world_full post-capture defender displace: defender leaves captured province.
## Fixture: GER 9276 → FRA 9281; optional FRA retreat land 92990 adjacent.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureDefenderDisplaceTest.gd

const FROM_PID := 9276
const TO_PID := 9281
const RETREAT_PID := 92990  # synthetic FRA land for retreat (not in world_full; fixture-only)
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wf_disp_ger_div"
const DEF_FID := "wf_disp_fra_div"
const ATT_DESIGN := "panzer_iii_j_medium"
const DEF_DESIGN := "somua_s35_medium"


var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _mm: Node = null
var _bm: Node = null
var _with_retreat := true


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldFullPostCaptureDefenderDisplaceTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldFullPostCaptureDefenderDisplaceTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print(
		"HeadlessWorldFullPostCaptureDefenderDisplaceTest: ",
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
	var bm_script: Script = load("res://scripts/combat/BattleManager.gd") as Script
	if bm_script == null:
		_fail("BattleManager missing")
		return
	_bm = bm_script.new()
	root.add_child(_bm)

	_with_retreat = true
	if not _setup_map(_with_retreat):
		return
	if not _setup_forms():
		return
	_test_invalid_assault_no_crash()
	_test_displace_to_friendly_adjacent()
	_test_equip_reinforce_after()

	_with_retreat = false
	if not _setup_map(_with_retreat):
		return
	if not _setup_forms():
		return
	_test_displace_clears_when_no_friendly()

	_cleanup()
	if _bm:
		_bm.queue_free()


func _setup_map(include_retreat: bool) -> bool:
	var adj_path := "res://data/provinces_world_full/province_adjacency.json"
	if not FileAccess.file_exists(adj_path):
		_fail("world_full adjacency missing")
		return false
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	# Build adjacency dict: world edge + optional retreat land.
	var file := FileAccess.open(adj_path, FileAccess.READ)
	if file == null:
		_fail("cannot read adjacency")
		return false
	var root_json = JSON.parse_string(file.get_as_text())
	if typeof(root_json) != TYPE_DICTIONARY:
		_fail("adjacency JSON invalid")
		return false
	var adj: Dictionary = (root_json as Dictionary).get("adjacency", {}) as Dictionary
	var custom: Dictionary = {}
	# Seed from world for FROM/TO edges
	for k in [str(FROM_PID), str(TO_PID)]:
		if adj.has(k):
			custom[k] = (adj[k] as Array).duplicate()
	if not custom.has(str(FROM_PID)):
		custom[str(FROM_PID)] = [TO_PID]
	if not custom.has(str(TO_PID)):
		custom[str(TO_PID)] = [FROM_PID]
	# Ensure undirected FROM↔TO
	var from_n: Array = custom[str(FROM_PID)] as Array
	var to_n: Array = custom[str(TO_PID)] as Array
	if TO_PID not in from_n and TO_PID not in from_n.map(func(x): return int(x)):
		from_n.append(TO_PID)
	if FROM_PID not in to_n and FROM_PID not in to_n.map(func(x): return int(x)):
		to_n.append(FROM_PID)
	if include_retreat:
		# FRA retreat land adjacent only to TO (friendly rear)
		custom[str(RETREAT_PID)] = [TO_PID]
		if RETREAT_PID not in to_n and RETREAT_PID not in to_n.map(func(x): return int(x)):
			to_n.append(RETREAT_PID)
		custom[str(TO_PID)] = to_n
	else:
		custom[str(TO_PID)] = to_n
	custom[str(FROM_PID)] = from_n
	adj_sys.call("load_from_dict", custom)

	var from_p: Object = _new_obj("res://scripts/data/Province.gd")
	var to_p: Object = _new_obj("res://scripts/data/Province.gd")
	if from_p == null or to_p == null:
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

	adj_sys.call("register_province", from_p)
	adj_sys.call("register_province", to_p)

	var provs := {FROM_PID: from_p, TO_PID: to_p}
	if include_retreat:
		var ret_p: Object = _new_obj("res://scripts/data/Province.gd")
		if ret_p == null:
			_fail("retreat Province create failed")
			return false
		ret_p.set("id", RETREAT_PID)
		ret_p.set("owner_tag", DEF_TAG)
		ret_p.set("controller_tag", DEF_TAG)
		ret_p.set("terrain", "plains")
		ret_p.set("name", "FRA Rear")
		ret_p.set("is_sea", false)
		ret_p.set("development_level", 1)
		ret_p.set("infrastructure", 1)
		adj_sys.call("register_province", ret_p)
		provs[RETREAT_PID] = ret_p

	var countries := {
		ATT_TAG: {"tag": ATT_TAG, "name": "Germany"},
		DEF_TAG: {"tag": DEF_TAG, "name": "France"},
	}
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = mds.new(provs, {}, adj_sys, countries) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	_mm.call("initialize_from_map_data", map_data)
	if _mm.call("get_province", TO_PID) == null:
		_fail("MapManager missing target province")
		return false
	print(
		"  [INFO] displace fixture GER %d → FRA %d retreat=%s"
		% [FROM_PID, TO_PID, str(RETREAT_PID) if include_retreat else "none"]
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
	f.set("name", "%s DispDiv" % tag)
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


func _reset_state() -> void:
	_mm.call("update_province_owner", TO_PID, DEF_TAG, DEF_TAG, true)
	if _with_retreat:
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


func _test_displace_to_friendly_adjacent() -> void:
	_reset_state()
	var def_before := _station(DEF_FID)
	var att_before := _station(ATT_FID)
	if def_before != TO_PID:
		_fail("setup def station should be %d, got %d" % [TO_PID, def_before])
		return
	if att_before != FROM_PID:
		_fail("setup att station should be %d, got %d" % [FROM_PID, att_before])
		return

	# Prefer live execute; fallback to apply_combat_outcome on same capture path.
	var captured := false
	var def_after := def_before
	var att_after := att_before
	for attempt in 8:
		_reset_state()
		var wrap: Dictionary = _bm.execute_province_assault(ATT_TAG, TO_PID, FROM_PID, ATT_FID)
		var result: Dictionary = wrap
		if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
			result = wrap["result"] as Dictionary
		var winner := str(result.get("winner", ""))
		var pcc := bool(result.get("province_control_change", false))
		def_after = _station(DEF_FID)
		att_after = _station(ATT_FID)
		print(
			"  [INFO] execute attempt %d winner=%s pcc=%s att_st=%d def_st=%d owner=%s"
			% [attempt + 1, winner, str(pcc), att_after, def_after, _owner(TO_PID)]
		)
		if winner == "attacker" and pcc and _owner(TO_PID) == ATT_TAG:
			captured = true
			break

	if not captured:
		print("  [INFO] execute stochastic miss; forced apply_combat_outcome")
		_reset_state()
		_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
		def_after = _station(DEF_FID)
		att_after = _station(ATT_FID)
		captured = _owner(TO_PID) == ATT_TAG

	print(
		"  [INFO] friendly-retreat path att %d→%d def %d→%d owner=%s"
		% [att_before, att_after, def_before, def_after, _owner(TO_PID)]
	)
	if not captured:
		_fail("could not produce capture")
		return
	if _owner(TO_PID) != ATT_TAG:
		_fail("owner should be %s, got %s" % [ATT_TAG, _owner(TO_PID)])
		return
	if att_after != TO_PID:
		_fail("attacker station should be captured %d, got %d" % [TO_PID, att_after])
		return
	if def_after == TO_PID:
		_fail("defender station must leave captured province %d, still %d" % [TO_PID, def_after])
		return
	if def_after != RETREAT_PID:
		_fail("defender should retreat to friendly %d, got %d" % [RETREAT_PID, def_after])
		return
	_pass(
		"defender displaced %d→%d; attacker stationed on %d"
		% [def_before, def_after, att_after]
	)


func _test_displace_clears_when_no_friendly() -> void:
	_reset_state()
	var def_before := _station(DEF_FID)
	_bm.apply_combat_outcome(_forced_capture_result(), ATT_FID, FROM_PID)
	var def_after := _station(DEF_FID)
	var att_after := _station(ATT_FID)
	print(
		"  [INFO] no-friendly path def %d→%d att=%d owner=%s"
		% [def_before, def_after, att_after, _owner(TO_PID)]
	)
	if _owner(TO_PID) != ATT_TAG:
		_fail("no-friendly: owner should flip to %s" % ATT_TAG)
		return
	if att_after != TO_PID:
		_fail("no-friendly: attacker station should be %d, got %d" % [TO_PID, att_after])
		return
	if def_after == TO_PID:
		_fail("no-friendly: defender must leave %d, still %d" % [TO_PID, def_after])
		return
	# No remaining FRA land → clear to -1
	if def_after != -1:
		_fail("no-friendly: expected station clear (-1), got %d" % def_after)
		return
	_pass("no friendly land: defender station cleared off captured province")


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
	var def_st := _station(DEF_FID)
	print(
		"  [INFO] reinforce stock %d→%d def_equip=%d def_station=%d att_station=%d"
		% [stock_b, stock_a, equip_d, def_st, _station(ATT_FID)]
	)
	if stock_a >= stock_b or equip_d < 1:
		_fail("reinforce did not drain stockpile / fill equip")
		return
	if def_st == TO_PID:
		_fail("defender must not re-appear on captured province after reinforce")
		return
	if _station(ATT_FID) != TO_PID:
		_fail("attacker station must remain on captured province after reinforce")
		return
	_pass("post-capture reinforce works; stations preserved (def off target, att on target)")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_FID)
		_lm.formations.erase(DEF_FID)


func _cleanup() -> void:
	_cleanup_forms()
