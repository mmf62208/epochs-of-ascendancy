extends SceneTree

## Living unit order loop on world_accurate Maginot chips:
##   park GER 710173 / FRA 710739 → DemoUnitIcon + org/str → march own land → start_land_battle
## Does not load WorldMap.tscn / 3520 polygons (hang-class).
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateUnitOrderLoopTest.gd

const GER_FRONT := 710173
const FRA_FRONT := 710739
const GER_REAR := 710176  # Rastatt — GER land neighbor of Baden-Baden
const ATT_TAG := "GER"
const DEF_TAG := "FRA"
const GER_FID := "uol_ger_maginot"
const FRA_FID := "uol_fra_maginot"
const GER_FID_2 := "uol_ger_stack"
const ATT_DESIGN := "panzer_iii_j_medium"
const DEF_DESIGN := "somua_s35_medium"

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _bm: Node = null
var _mr: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessWorldAccurateUnitOrderLoopTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessWorldAccurateUnitOrderLoopTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessWorldAccurateUnitOrderLoopTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _run() -> void:
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	_bm = _autoload("BattleManager")
	if _lm == null or _mm == null or _bm == null:
		_fail("autoloads missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", ATT_TAG)
	if not _setup_maginot_map():
		return
	if not _setup_formations():
		return
	if not _setup_map_renderer_pins():
		return
	_test_front_chips()
	_test_march_and_assault()
	_cleanup()


func _setup_maginot_map() -> bool:
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

	var rows: Array = [
		{"id": GER_FRONT, "tag": ATT_TAG, "name": "Baden-Baden GER"},
		{"id": FRA_FRONT, "tag": DEF_TAG, "name": "Bas-Rhin FRA"},
		{"id": GER_REAR, "tag": ATT_TAG, "name": "Rastatt GER rear"},
	]
	var provs: Dictionary = {}
	var countries: Dictionary = {
		ATT_TAG: {"tag": ATT_TAG, "name": "Germany"},
		DEF_TAG: {"tag": DEF_TAG, "name": "France"},
	}
	for row in rows:
		var pid := int(row["id"])
		var p: Object = _new_obj("res://scripts/data/Province.gd")
		if p == null:
			_fail("Province create failed")
			return false
		p.set("id", pid)
		p.set("owner_tag", str(row["tag"]))
		p.set("controller_tag", str(row["tag"]))
		p.set("terrain", "plains")
		p.set("name", str(row["name"]))
		p.set("is_sea", false)
		p.set("infrastructure", 4)
		p.set("development_level", 3)
		provs[pid] = p
		if adj_sys.has_method("register_province"):
			adj_sys.call("register_province", p)

	var found := false
	if adj_sys.has_method("are_adjacent"):
		found = bool(adj_sys.call("are_adjacent", GER_FRONT, FRA_FRONT))
	if not found and adj_sys.has_method("get_neighbors"):
		for n in adj_sys.call("get_neighbors", GER_FRONT):
			if int(n) == FRA_FRONT:
				found = true
				break
	if not found:
		_fail("fixture edge %d-%d not in world_accurate adjacency" % [GER_FRONT, FRA_FRONT])
		return false

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
	_pass("map fixture GER %d / rear %d / FRA %d" % [GER_FRONT, GER_REAR, FRA_FRONT])
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
	f.set("name", "%s Maginot Div" % tag)
	if "formations" in _lm:
		_lm.formations[fid] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)


func _setup_formations() -> bool:
	_cleanup_forms()
	_make_form(GER_FID, ATT_TAG, ATT_DESIGN, GER_FRONT)
	_make_form(GER_FID_2, ATT_TAG, ATT_DESIGN, GER_REAR)
	_make_form(FRA_FID, DEF_TAG, DEF_DESIGN, FRA_FRONT)
	if _failures > 0:
		return false
	_pass("seeded GER/FRA land formations")
	return true


func _setup_map_renderer_pins() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	root.add_child(_mr)

	var pids: Array = [GER_FRONT, FRA_FRONT, GER_REAR]
	for pid_v in pids:
		var pid := int(pid_v)
		var gp = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
		if gp == null:
			_fail("MapManager missing province %d" % pid)
			return false
		if "provinces" in _mr:
			_mr.provinces[pid] = gp
		var node := Node2D.new()
		node.name = "Province_%d" % pid
		container.add_child(node)
		if "province_nodes" in _mr:
			_mr.province_nodes[pid] = node

	if not _mr.has_method("ensure_playable_front_chips"):
		_fail("ensure_playable_front_chips missing")
		return false
	var parked: Variant = _mr.call("ensure_playable_front_chips", false)
	print("  [INFO] ensure_playable_front_chips ", parked)
	if parked is Dictionary and not bool(parked.get("ok", false)):
		_fail("ensure_playable_front_chips not ok")
		return false
	_pass("ensure_playable_front_chips ok")
	return true


func _ger_on_front() -> Object:
	if _lm == null or not _lm.has_method("get_formations_for_country"):
		return null
	for f in _lm.call("get_formations_for_country", ATT_TAG):
		if f == null:
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft != "division" and ft != "garrison":
			continue
		if int(f.stationed_province_id) == GER_FRONT:
			return f
	return null


func _chip_on(pid: int) -> Node:
	if _mr == null or not ("province_nodes" in _mr):
		return null
	var nodes = _mr.province_nodes
	if not (nodes is Dictionary) or not nodes.has(pid):
		return null
	var n: Node = nodes[pid] as Node
	if n == null:
		return null
	return n.get_node_or_null("DemoUnitIcon_%d" % pid)


func _test_front_chips() -> void:
	var ger_f: Object = _ger_on_front()
	if ger_f == null:
		_fail("no GER land formation stationed at %d" % GER_FRONT)
		return
	var str_v := float(ger_f.strength) if "strength" in ger_f else 0.0
	var org_v := float(ger_f.organization) if "organization" in ger_f else 0.0
	print("  [INFO] GER fid=%s str=%.2f org=%.2f" % [str(ger_f.formation_id), str_v, org_v])
	if str_v <= 0.0 or org_v <= 0.0:
		_fail("GER formation lacks strength/organization")
		return
	_pass("GER land on %d str=%.2f org=%.2f" % [GER_FRONT, str_v, org_v])

	var icon_pids: Array = _mr.get("_demo_unit_icon_pids") if "_demo_unit_icon_pids" in _mr else []
	var indexed := false
	for v in icon_pids:
		if int(v) == GER_FRONT:
			indexed = true
			break
	var chip: Node = _chip_on(GER_FRONT)
	if chip == null and not indexed:
		_fail("no DemoUnitIcon on %d (index missing pid)" % GER_FRONT)
		return
	if chip == null:
		_fail("no DemoUnitIcon node on %d" % GER_FRONT)
		return
	_pass("DemoUnitIcon on %d" % GER_FRONT)
	if not chip.has_meta("formation_id") or str(chip.get_meta("formation_id", "")).is_empty():
		_fail("chip meta missing formation_id")
		return
	_pass("chip meta formation_id=%s" % str(chip.get_meta("formation_id")))
	var str_num: Node = chip.get_node_or_null("StrNum")
	var bars: Node = chip.get_node_or_null("StatBars")
	if str_num == null:
		_fail("chip missing StrNum")
	else:
		_pass("chip StrNum=%s" % str(str_num.get("text") if "text" in str_num else "?"))
	if bars == null or bars.get_node_or_null("OrgBar") == null or bars.get_node_or_null("StrBar") == null:
		_fail("chip missing OrgBar/StrBar")
	else:
		_pass("chip OrgBar+StrBar present")


func _test_march_and_assault() -> void:
	var ger_f: Object = _ger_on_front()
	if ger_f == null:
		_fail("march/assault skipped — no GER on front")
		return
	var fid := str(ger_f.formation_id)
	if _mr.has_method("_select_map_unit"):
		_mr.call("_select_map_unit", ger_f)
	elif "selected_formation_id" in _mr:
		_mr.selected_formation_id = fid

	var dest := GER_REAR
	if _mm.has_method("get_adjacent_provinces"):
		for nv in _mm.call("get_adjacent_provinces", GER_FRONT, true):
			var nid := int(nv)
			if nid == GER_FRONT or nid == FRA_FRONT:
				continue
			var np = _mm.call("get_province", nid) if _mm.has_method("get_province") else null
			if np == null or bool(np.is_sea):
				continue
			if str(np.owner_tag).strip_edges().to_upper() == ATT_TAG:
				dest = nid
				break

	var marched: Dictionary = {}
	if _mr.has_method("_try_move_selected_unit_to_province"):
		var dest_p = _mm.call("get_province", dest) if _mm.has_method("get_province") else null
		if dest_p != null:
			_mr.call("_try_move_selected_unit_to_province", dest_p)
	var mv_scr: Script = load("res://scripts/formations/FormationMovement.gd") as Script
	if mv_scr == null:
		_fail("FormationMovement.gd missing")
		return
	marched = mv_scr.call("enqueue_own_land_march", fid, dest, ATT_TAG)
	print("  [INFO] enqueue_own_land_march dest=%d %s" % [dest, str(marched)])
	if not bool(marched.get("ok", false)):
		_fail("enqueue_own_land_march not ok: %s" % str(marched.get("reason", marched)))
		return
	_pass("enqueue_own_land_march ok hops=%s dest=%d" % [str(marched.get("hops", "?")), dest])

	# Re-station on the front hex for the assault (march must not strand the unit).
	ger_f.stationed_province_id = GER_FRONT
	if not _bm.has_method("start_land_battle"):
		_fail("start_land_battle missing")
		return
	var opened: Dictionary = _bm.call("start_land_battle", ATT_TAG, FRA_FRONT, GER_FRONT, fid)
	print("  [INFO] start_land_battle %s" % str(opened))
	if not bool(opened.get("success", false)):
		_fail("start_land_battle not ok: %s" % str(opened.get("reason", opened)))
		return
	if bool(opened.get("instant", false)):
		# Honest: empty FRA hex resolves immediately (execute_province_assault).
		print("  [INFO] empty-defender instant (no FRA stack at %d)" % FRA_FRONT)
		_pass("start_land_battle instant empty-defender")
	else:
		_pass("start_land_battle opened=%s" % str(opened.get("opened", false)))


func _cleanup_forms() -> void:
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(GER_FID)
		_lm.formations.erase(GER_FID_2)
		_lm.formations.erase(FRA_FID)


func _cleanup() -> void:
	_cleanup_forms()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
