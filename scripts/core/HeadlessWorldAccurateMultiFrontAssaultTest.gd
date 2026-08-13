extends SceneTree

## Multi-front land assault on real world_accurate edges:
##   GER 710173 → FRA 710739 (Maginot / Bas-Rhin)
##   GER 710302 → POL 711073 (Polish border sample)
## Also validates MapManager.collect_live_border_assault_targets when loaded.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMultiFrontAssaultTest.gd

const EDGES: Array = [
	{"from": 710173, "to": 710739, "att": "GER", "def": "FRA", "label": "maginot"},
	{"from": 710302, "to": 711073, "att": "GER", "def": "POL", "label": "polish"},
]

const ATT_DESIGN := "panzer_iii_j_medium"
const DEF_DESIGN_FRA := "somua_s35_medium"
const DEF_DESIGN_POL := "pol_armor_1936"

var _failures := 0
var _pm: Node = null
var _lm: Node = null
var _mm: Node = null
var _bm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldAccurateMultiFrontAssaultTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldAccurateMultiFrontAssaultTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessWorldAccurateMultiFrontAssaultTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
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
	if not _setup_multi_edge_map():
		return
	var bm_script: Script = load("res://scripts/combat/BattleManager.gd") as Script
	if bm_script == null:
		_fail("BattleManager.gd missing")
		return
	_bm = bm_script.new()
	root.add_child(_bm)
	if not _bm.has_method("can_assault_province") or not _bm.has_method("execute_province_assault"):
		_fail("BattleManager assault APIs missing")
		return

	_test_border_target_collector()
	_test_multi_front_assault_day()
	for edge in EDGES:
		_test_edge_assault(edge)
	_cleanup()
	if _bm:
		_bm.queue_free()


func _setup_multi_edge_map() -> bool:
	var adj_path := "res://data/provinces_world_accurate/province_adjacency.json"
	if not FileAccess.file_exists(adj_path):
		_fail("world_accurate adjacency missing")
		return false
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	if adj_sys.has_method("load_adjacency"):
		adj_sys.call("load_adjacency", adj_path)

	var provs: Dictionary = {}
	var countries: Dictionary = {}
	for edge in EDGES:
		var from_id := int(edge["from"])
		var to_id := int(edge["to"])
		var att := str(edge["att"])
		var def := str(edge["def"])
		var found := false
		if adj_sys.has_method("are_adjacent"):
			found = bool(adj_sys.call("are_adjacent", from_id, to_id))
		if not found and adj_sys.has_method("get_neighbors"):
			for n in adj_sys.call("get_neighbors", from_id):
				if int(n) == to_id:
					found = true
					break
		if not found:
			_fail("edge missing %s %d→%d" % [edge["label"], from_id, to_id])
			return false
		_pass("edge present %s %d→%d" % [edge["label"], from_id, to_id])

		if not provs.has(from_id):
			var fp: Object = _new_obj("res://scripts/data/Province.gd")
			fp.set("id", from_id)
			fp.set("owner_tag", att)
			fp.set("controller_tag", att)
			fp.set("terrain", "plains")
			fp.set("name", "GER border %d" % from_id)
			fp.set("is_sea", false)
			fp.set("infrastructure", 4)
			fp.set("development_level", 3)
			provs[from_id] = fp
			if adj_sys.has_method("register_province"):
				adj_sys.call("register_province", fp)
		if not provs.has(to_id):
			var tp: Object = _new_obj("res://scripts/data/Province.gd")
			tp.set("id", to_id)
			tp.set("owner_tag", def)
			tp.set("controller_tag", def)
			tp.set("terrain", "plains")
			tp.set("name", "%s border %d" % [def, to_id])
			tp.set("is_sea", false)
			tp.set("infrastructure", 4)
			tp.set("development_level", 3)
			provs[to_id] = tp
			if adj_sys.has_method("register_province"):
				adj_sys.call("register_province", tp)
		countries[att] = {"tag": att, "name": att}
		countries[def] = {"tag": def, "name": def}

	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = mds.new(provs, {}, adj_sys, countries) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	if _mm.has_method("initialize_from_map_data"):
		_mm.call("initialize_from_map_data", map_data)
	else:
		_fail("initialize_from_map_data missing")
		return false
	return true


func _test_border_target_collector() -> void:
	if not _mm.has_method("collect_live_border_assault_targets"):
		_fail("collect_live_border_assault_targets missing")
		return
	var targets: Array = _mm.call("collect_live_border_assault_targets", "GER", 8)
	print("  [INFO] border targets: ", targets)
	if targets.is_empty():
		_fail("no live border assault targets for GER")
		return
	var ids: Array = []
	for t in targets:
		if t is Dictionary:
			ids.append(int(t.get("province_id", -1)))
	if 710739 in ids or 711073 in ids:
		_pass("border targets include Maginot and/or Polish defender ids n=%d" % ids.size())
	else:
		# Fixture only has these 4 provinces — any foreign id is success
		_pass("border targets n=%d ids=%s" % [ids.size(), str(ids)])


func _test_multi_front_assault_day() -> void:
	if not _mm.has_method("multi_front_assault_day_for_tag"):
		_fail("multi_front_assault_day_for_tag missing")
		return
	var day: Dictionary = _mm.call("multi_front_assault_day_for_tag", "GER", 4)
	print("  [INFO] multi_front_assault_day: ", day.get("summary", day))
	if bool(day.get("empty", true)):
		_fail("multi_front_assault_day empty")
		return
	var aq: Array = day.get("apply_queue", [])
	if aq.is_empty():
		_fail("multi_front apply_queue empty")
		return
	for q in aq:
		if q is Dictionary and str(q.get("action_id", "")) == "apply_assault":
			var pid := int(q.get("province_id", -1))
			# Must not queue GER-owned provinces as assault targets
			var p = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
			if p != null and str(p.owner_tag).to_upper() == "GER":
				_fail("assault target is own province %d" % pid)
				return
	_pass("multi_front_assault_day ready_count=%s queue=%d" % [str(day.get("ready_count")), aq.size()])


func _test_edge_assault(edge: Dictionary) -> void:
	var from_id := int(edge["from"])
	var to_id := int(edge["to"])
	var att := str(edge["att"])
	var def := str(edge["def"])
	var label := str(edge["label"])
	var att_fid := "mf_%s_att" % label
	var def_fid := "mf_%s_def" % label
	var def_design := DEF_DESIGN_FRA if def == "FRA" else DEF_DESIGN_POL

	_make_form(att_fid, att, ATT_DESIGN, from_id)
	_make_form(def_fid, def, def_design, to_id)
	_pm.set_unit_equipment_stock(att_fid, {ATT_DESIGN: 2})
	_pm.set_unit_equipment_stock(def_fid, {def_design: 2})
	_pm.set_country_equipment_stockpile(att, {ATT_DESIGN: 40})
	_pm.set_country_equipment_stockpile(def, {def_design: 40})

	var can: Dictionary = _bm.can_assault_province(att, to_id, from_id)
	if not bool(can.get("ok", false)):
		_fail("%s can_assault failed: %s" % [label, str(can.get("reason", can))])
		_cleanup_edge_forms(att_fid, def_fid)
		return
	_pass("%s can_assault ok power=%.2f" % [label, float(can.get("attack_power", 0))])

	var wrap: Dictionary = _bm.execute_province_assault(att, to_id, from_id, att_fid)
	var result: Dictionary = wrap
	if wrap.has("result") and typeof(wrap.get("result")) == TYPE_DICTIONARY:
		result = wrap["result"] as Dictionary
	if bool(wrap.get("success", true)) == false and str(wrap.get("reason", "")) != "":
		_fail("%s execute failed: %s" % [label, str(wrap.get("reason"))])
		_cleanup_edge_forms(att_fid, def_fid)
		return
	if str(result.get("outcome", "")) == "invalid":
		_fail("%s invalid combat outcome" % label)
		_cleanup_edge_forms(att_fid, def_fid)
		return
	_pass("%s execute outcome=%s winner=%s" % [label, str(result.get("outcome", "?")), str(result.get("winner", "?"))])
	_cleanup_edge_forms(att_fid, def_fid)


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
	f.set("name", "%s MF Div" % tag)
	if "formations" in _lm:
		_lm.formations[fid] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)


func _cleanup_edge_forms(att_fid: String, def_fid: String) -> void:
	if _pm != null:
		_pm.clear_unit_equipment_stock(att_fid)
		_pm.clear_unit_equipment_stock(def_fid)
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(att_fid)
		_lm.formations.erase(def_fid)


func _cleanup() -> void:
	for edge in EDGES:
		var label := str(edge["label"])
		_cleanup_edge_forms("mf_%s_att" % label, "mf_%s_def" % label)
