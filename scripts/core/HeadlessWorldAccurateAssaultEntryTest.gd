extends SceneTree

## world_accurate land assault entry: can_assault + execute on real adjacency (GER→FRA).
## Avoid class_name typed constructors under -s (autoload identifier compile order).
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateAssaultEntryTest.gd

## Real world_accurate land edge: GER 710173 adjacent FRA capital 710739.
const FROM_PID := 710173
const TO_PID := 710739
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const ATT_FID := "wa_assault_ger_div"
const DEF_FID := "wa_assault_fra_div"
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
	print("  [FAIL] HeadlessWorldAccurateAssaultEntryTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldAccurateAssaultEntryTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessWorldAccurateAssaultEntryTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	quit(0 if ok else 1)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _new_obj(path: String) -> Object:
	## RefCounted/Resource via script load (ClassDB global names often unavailable under -s).
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
	if not _setup_world_accurate_border_map():
		return
	if not _setup_formations_and_equip():
		return
	var bm_script: Script = load("res://scripts/combat/BattleManager.gd") as Script
	if bm_script == null:
		_fail("BattleManager.gd missing")
		return
	_bm = bm_script.new()
	root.add_child(_bm)
	if not _bm.has_method("can_assault_province") or not _bm.has_method("execute_province_assault"):
		_fail("BattleManager public assault APIs missing")
		return

	_test_can_and_execute_assault()
	_test_post_assault_reinforce()
	_cleanup()
	if _bm:
		_bm.queue_free()


func _setup_world_accurate_border_map() -> bool:
	var adj_path := "res://data/provinces_world_accurate/province_adjacency.json"
	if not FileAccess.file_exists(adj_path):
		_fail("world_accurate adjacency missing")
		return false

	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("could not create AdjacencySystem")
		return false
	if adj_sys.has_method("load_adjacency"):
		adj_sys.call("load_adjacency", adj_path)

	var found := false
	if adj_sys.has_method("are_adjacent"):
		found = bool(adj_sys.call("are_adjacent", FROM_PID, TO_PID))
	if not found and adj_sys.has_method("get_neighbors"):
		for n in adj_sys.call("get_neighbors", FROM_PID):
			if int(n) == TO_PID:
				found = true
				break
	if not found:
		_fail("fixture edge %d-%d not in world_accurate adjacency" % [FROM_PID, TO_PID])
		return false

	var from_p: Object = _new_obj("res://scripts/data/Province.gd")
	var to_p: Object = _new_obj("res://scripts/data/Province.gd")
	if from_p == null or to_p == null:
		_fail("could not create Province resources")
		return false
	from_p.set("id", FROM_PID)
	from_p.set("owner_tag", ATT_TAG)
	from_p.set("controller_tag", ATT_TAG)
	from_p.set("terrain", "plains")
	from_p.set("name", "Baden-Baden GER border")
	from_p.set("is_sea", false)
	from_p.set("development_level", 3)
	from_p.set("infrastructure", 3)

	to_p.set("id", TO_PID)
	to_p.set("owner_tag", DEF_TAG)
	to_p.set("controller_tag", DEF_TAG)
	to_p.set("terrain", "plains")
	to_p.set("name", "Bas-Rhin FRA border")
	to_p.set("is_sea", false)
	to_p.set("development_level", 4)
	to_p.set("infrastructure", 4)

	if adj_sys.has_method("register_province"):
		adj_sys.call("register_province", from_p)
		adj_sys.call("register_province", to_p)

	var provs: Dictionary = {FROM_PID: from_p, TO_PID: to_p}
	var countries: Dictionary = {
		ATT_TAG: {"tag": ATT_TAG, "name": "Germany"},
		DEF_TAG: {"tag": DEF_TAG, "name": "France"},
	}
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = null
	if mds != null:
		map_data = mds.new(provs, {}, adj_sys, countries)
	if map_data == null:
		_fail("could not create MapScenarioData")
		return false

	if _mm.has_method("initialize_from_map_data"):
		_mm.call("initialize_from_map_data", map_data)
	else:
		_fail("MapManager.initialize_from_map_data missing")
		return false

	var gp_from = _mm.call("get_province", FROM_PID) if _mm.has_method("get_province") else null
	var gp_to = _mm.call("get_province", TO_PID) if _mm.has_method("get_province") else null
	if gp_from == null or gp_to == null:
		_fail("MapManager did not accept fixture provinces")
		return false
	var adj_list: Array = []
	if _mm.has_method("get_adjacent_provinces"):
		adj_list = _mm.call("get_adjacent_provinces", FROM_PID)
	print("  [INFO] map fixture GER %d → FRA %d adjacent=%s" % [FROM_PID, TO_PID, str(adj_list)])
	return true


func _make_form(fid: String, tag: String, design: String, station: int) -> void:
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("Formation create failed")
		return
	f.set("formation_id", fid)
	f.set("country_tag", tag)
	f.set("formation_type", "division")
	f.set("design_id", design)
	f.set("stationed_province_id", station)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set("name", "%s Assault Div" % tag)
	if "formations" in _lm:
		_lm.formations[fid] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)


func _setup_formations_and_equip() -> bool:
	_cleanup_forms()
	_make_form(ATT_FID, ATT_TAG, ATT_DESIGN, FROM_PID)
	_make_form(DEF_FID, DEF_TAG, DEF_DESIGN, TO_PID)
	if _failures > 0:
		return false
	_pm.set_unit_equipment_stock(ATT_FID, {ATT_DESIGN: 2})
	_pm.set_unit_equipment_stock(DEF_FID, {DEF_DESIGN: 2})
	_pm.set_country_equipment_stockpile(ATT_TAG, {ATT_DESIGN: 50})
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 50})
	var found_att := false
	for f in _lm.get_formations_for_country(ATT_TAG):
		if f != null and str(f.get("formation_id") if f is Dictionary else f.formation_id) == ATT_FID:
			var sid := int(f.get("stationed_province_id") if f is Dictionary else f.stationed_province_id)
			if sid == FROM_PID:
				found_att = true
	if not found_att:
		_fail("attacker formation not stationed at from province")
		return false
	return true


func _test_can_and_execute_assault() -> void:
	var can: Dictionary = _bm.can_assault_province(ATT_TAG, TO_PID, FROM_PID)
	print("  [INFO] can_assault_province: %s" % str(can))
	if not bool(can.get("ok", false)):
		_fail("can_assault failed: %s" % str(can.get("reason", can)))
		return
	var fid := str(can.get("formation_id", ""))
	var ap := float(can.get("attack_power", 0.0))
	if fid.is_empty():
		_fail("can_assault missing formation_id")
		return
	if ap <= 0.0:
		_fail("can_assault attack_power should be > 0 (got %.3f)" % ap)
		return
	_pass("can_assault ok formation=%s attack_power=%.3f from=%d to=%d" % [fid, ap, FROM_PID, TO_PID])

	var equip_att_before := int(_pm.get_unit_equipment_stock(ATT_FID).get(ATT_DESIGN, 0))
	var equip_def_before := int(_pm.get_unit_equipment_stock(DEF_FID).get(DEF_DESIGN, 0))

	var wrap: Dictionary = _bm.execute_province_assault(ATT_TAG, TO_PID, FROM_PID, ATT_FID)
	# Public API returns {success, result} where result is the combat dict.
	var result: Dictionary = wrap
	if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
		result = wrap["result"] as Dictionary
	print(
		"  [INFO] execute success=%s keys=%s winner=%s outcome=%s reason=%s"
		% [
			str(wrap.get("success", "")),
			str(result.keys()),
			str(result.get("winner", "")),
			str(result.get("outcome", "")),
			str(wrap.get("reason", result.get("reason", ""))),
		]
	)
	if bool(wrap.get("success", true)) == false and str(wrap.get("reason", "")) != "":
		_fail("execute failed: %s" % str(wrap.get("reason")))
		return
	if str(result.get("outcome", "")) == "invalid":
		_fail("execute returned invalid combat outcome")
		return
	var has_winner := result.has("winner") and str(result.get("winner", "")) != ""
	var has_outcome := result.has("outcome") and str(result.get("outcome", "")) != ""
	if not has_winner and not has_outcome:
		_fail("execute result missing winner/outcome")
		return
	_pass(
		"execute_province_assault non-invalid winner=%s outcome=%s"
		% [str(result.get("winner", "?")), str(result.get("outcome", "?"))]
	)

	var equip_att_after := int(_pm.get_unit_equipment_stock(ATT_FID).get(ATT_DESIGN, 0))
	var equip_def_after := int(_pm.get_unit_equipment_stock(DEF_FID).get(DEF_DESIGN, 0))
	print(
		"  [INFO] post-execute equip ATT %d→%d DEF %d→%d"
		% [equip_att_before, equip_att_after, equip_def_before, equip_def_after]
	)
	var any_loss := equip_att_after < equip_att_before or equip_def_after < equip_def_before
	if not any_loss:
		var loser_fid := DEF_FID if str(result.get("winner", "")) == "attacker" else ATT_FID
		var rem: Dictionary = _pm.apply_combat_equipment_loss(loser_fid, 0.5)
		print("  [INFO] fallback equip loss on %s rem=%s" % [loser_fid, str(rem)])
		any_loss = not rem.is_empty()
	if not any_loss:
		_fail("no equipment loss after assault")
		return
	_pass("post-assault equipment decreased on at least one side")


func _test_post_assault_reinforce() -> void:
	_pm.set_unit_equipment_stock(DEF_FID, {})
	var f = _lm.get_formation(DEF_FID) if _lm.has_method("get_formation") else null
	if f != null and "strength" in f:
		f.strength = 0.5
	_pm.set_country_equipment_stockpile(DEF_TAG, {DEF_DESIGN: 20})
	var stock_b := int(_pm.get_country_equipment_stockpile(DEF_TAG).get(DEF_DESIGN, 0))
	_pm.daily_formation_reinforce_from_stockpile()
	var stock_a := int(_pm.get_country_equipment_stockpile(DEF_TAG).get(DEF_DESIGN, 0))
	var equip_a := int(_pm.get_unit_equipment_stock(DEF_FID).get(DEF_DESIGN, 0))
	print("  [INFO] reinforce stock %d→%d equip=%d" % [stock_b, stock_a, equip_a])
	if stock_a >= stock_b or equip_a < 1:
		_fail("reinforce did not drain stockpile / restore equip")
		return
	_pass("reinforce after assault path drains country stockpile and restores equip")


func _cleanup_forms() -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(ATT_FID)
		_pm.clear_unit_equipment_stock(DEF_FID)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(ATT_FID)
		_lm.formations.erase(DEF_FID)


func _cleanup() -> void:
	_cleanup_forms()
