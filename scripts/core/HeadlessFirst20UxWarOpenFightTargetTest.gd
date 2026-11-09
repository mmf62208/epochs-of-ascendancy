extends SceneTree

## FIRST20-UX-WAR (b): Open fight prefers an at-war neighbour and never
## defaults to a neutral while a war is on.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessFirst20UxWarOpenFightTargetTest.gd

const GER_FRONT := 101
const POL_HEX := 201
const CZE_HEX := 301
const GER_CZE_ONLY := 102
const GER_TAG := "GER"
const POL_TAG := "POL"
const CZE_TAG := "CZE"
const FID := "f20_ux_war_ger"
const SRC_REN := "res://scripts/map/MapRenderer.gd"

var _failures: int = 0
var _mr: Node = null
var _lm: Node = null
var _mm: Node = null
var _war: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _run() -> void:
	_test_source_needles()
	if not _setup():
		_finish()
		return
	_case_war_prefers_pol_not_cze()
	_case_no_at_war_neighbour_never_neutral()
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessFirst20UxWarOpenFightTargetTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFirst20UxWarOpenFightTargetTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt_a := src.find("\nfunc ", i + needle.length())
	var nxt_b := src.find("\nstatic func ", i + needle.length())
	var nxt := -1
	if nxt_a >= 0 and nxt_b >= 0:
		nxt = mini(nxt_a, nxt_b)
	elif nxt_a >= 0:
		nxt = nxt_a
	else:
		nxt = nxt_b
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	var adj_fn := _slice_func(ren, "_adjacent_enemy_province_id")
	if adj_fn.is_empty() or "_open_fight_owner_is_at_war" not in adj_fn:
		_fail("_adjacent_enemy_province_id must consult is_at_war via _open_fight_owner_is_at_war")
		return
	if "_province_has_defending_units" not in adj_fn:
		_fail("_adjacent_enemy_province_id must still prefer a defended neighbor")
		return
	var war_fn := _slice_func(ren, "_open_fight_owner_is_at_war")
	if war_fn.is_empty() or "is_at_war" not in war_fn:
		_fail("_open_fight_owner_is_at_war must call WarStateDomain.is_at_war")
		return
	_pass("source needles: at-war preference layered on COMBAT-1 defended pick")


func _setup() -> bool:
	_lm = root.get_node_or_null("LeaderManager")
	_mm = root.get_node_or_null("MapManager")
	var tm := root.get_node_or_null("TimeManager")
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	if _lm == null or _mm == null or tm == null or _war == null:
		_fail("autoloads missing")
		return false
	if "scenario_start_year" in tm:
		tm.set("scenario_start_year", 1936)
	if "total_days_elapsed" in tm:
		tm.set("total_days_elapsed", 0)
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _load_fixture():
		return false
	_war.reset_for_test()
	_war.clear_rule_overrides()
	var declared: Dictionary = _war.declare_war(GER_TAG, POL_TAG, "player")
	if not bool(declared.get("ok", false)):
		_fail("declare GER–POL failed %s" % str(declared))
		return false
	if not bool(_war.is_at_war(GER_TAG, POL_TAG)):
		_fail("GER–POL not at war after declare")
		return false
	if bool(_war.is_at_war(GER_TAG, CZE_TAG)):
		_fail("GER–CZE must stay neutral")
		return false
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = scr.new() as Node
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.enabled = true
	_mr.add_child(cam)
	root.add_child(_mr)
	cam.make_current()
	for pid in [GER_FRONT, POL_HEX, CZE_HEX, GER_CZE_ONLY]:
		var gp: Object = _mm.call("get_province", pid)
		if gp == null:
			_fail("fixture province %d missing" % pid)
			return false
		_mr.provinces[pid] = gp
	_register(FID, "F20 UX War GER", GER_FRONT)
	_register("f20_ux_war_cze", "F20 CZE Garrison", CZE_HEX, CZE_TAG)
	_pass("open-fight war fixture ready")
	return true


func _load_fixture() -> bool:
	var adj_scr: Script = load("res://scripts/data/AdjacencySystem.gd") as Script
	var prov_scr: Script = load("res://scripts/data/Province.gd") as Script
	var map_scr: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	if adj_scr == null or prov_scr == null or map_scr == null:
		_fail("map fixture scripts missing")
		return false
	var adj_sys: Object = adj_scr.new()
	if adj_sys.has_method("load_from_dict"):
		adj_sys.call("load_from_dict", {
			"adjacency": {
				str(GER_FRONT): [CZE_HEX, POL_HEX],
				str(POL_HEX): [GER_FRONT],
				str(CZE_HEX): [GER_FRONT, GER_CZE_ONLY],
				str(GER_CZE_ONLY): [CZE_HEX],
			}
		})
	var rows: Array = [
		{"id": GER_FRONT, "tag": GER_TAG, "name": "GER Front"},
		{"id": POL_HEX, "tag": POL_TAG, "name": "POL Border"},
		{"id": CZE_HEX, "tag": CZE_TAG, "name": "CZE Neutral"},
		{"id": GER_CZE_ONLY, "tag": GER_TAG, "name": "GER CZE-only"},
	]
	var provs: Dictionary = {}
	for row in rows:
		var p: Object = prov_scr.new()
		p.set("id", int(row["id"]))
		p.set("owner_tag", str(row["tag"]))
		p.set("controller_tag", str(row["tag"]))
		p.set("name", str(row["name"]))
		p.set("terrain", "plains")
		p.set("is_sea", false)
		provs[int(row["id"])] = p
		if adj_sys.has_method("register_province"):
			adj_sys.call("register_province", p)
	var countries: Dictionary = {
		GER_TAG: {"tag": GER_TAG, "name": "Germany"},
		POL_TAG: {"tag": POL_TAG, "name": "Poland"},
		CZE_TAG: {"tag": CZE_TAG, "name": "Czechoslovakia"},
	}
	var map_data: Object = map_scr.new(provs, {}, adj_sys, countries)
	if not _mm.has_method("initialize_from_map_data"):
		_fail("initialize_from_map_data missing")
		return false
	_mm.call("initialize_from_map_data", map_data)
	return true


func _register(fid: String, unit_name: String, pid: int, tag: String = GER_TAG) -> void:
	var form_scr: GDScript = load("res://scripts/formations/Formation.gd") as GDScript
	var fo: Object = form_scr.new()
	fo.set("formation_id", fid)
	fo.set("name", unit_name)
	fo.set("country_tag", tag)
	fo.set("formation_type", "division")
	fo.set("stationed_province_id", pid)
	fo.set("strength", 1.0)
	if _lm.has_method("register_formation"):
		_lm.call("register_formation", fo)
	elif "formations" in _lm:
		_lm.formations[fid] = fo


func _owner_of(pid: int) -> String:
	if _mm == null or not _mm.has_method("get_province"):
		return ""
	var p: Object = _mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _case_war_prefers_pol_not_cze() -> void:
	if _mr == null or not _mr.has_method("_adjacent_enemy_province_id"):
		_fail("_adjacent_enemy_province_id missing")
		return
	var picked := int(_mr.call("_adjacent_enemy_province_id", GER_FRONT, GER_TAG))
	if picked != POL_HEX:
		_fail("GER–POL war: want POL %d got %d owner=%s (CZE %d is first adj)" % [
			POL_HEX, picked, _owner_of(picked), CZE_HEX
		])
		return
	if _owner_of(picked) != POL_TAG:
		_fail("Open fight target owner want POL got %s" % _owner_of(picked))
		return
	_mr.set("selected_formation_id", FID)
	_mr.call("_open_fight_from_formation_id", FID)
	var sheet := _sheet()
	var text := _sheet_text()
	if sheet == null:
		_fail("Open fight sheet missing after GER–POL war pick")
		return
	if "CZE Neutral" in text or "Czechoslovakia" in text:
		_fail("Open fight sheet defaulted to CZE:\n%s" % text)
		return
	if "POL Border" not in text and "Poland" not in text:
		_fail("Open fight sheet missing POL target:\n%s" % text)
		return
	_pass("GER–POL war Open fight target is POL, not CZE")


func _case_no_at_war_neighbour_never_neutral() -> void:
	var picked := int(_mr.call("_adjacent_enemy_province_id", GER_CZE_ONLY, GER_TAG))
	if picked > 0:
		_fail("no at-war neighbour: want no target, got %d owner=%s (must never be CZE)" % [
			picked, _owner_of(picked)
		])
		return
	if _owner_of(picked) == CZE_TAG:
		_fail("no at-war neighbour defaulted to CZE")
		return
	_register("f20_ux_war_cze_only", "F20 CZE-only", GER_CZE_ONLY)
	_mr.call("_open_fight_from_formation_id", "f20_ux_war_cze_only")
	var text := _sheet_text()
	if "CZE Neutral" in text:
		_fail("no at-war neighbour sheet named CZE:\n%s" % text)
		return
	if "No adjacent enemy" not in text:
		_fail("no at-war neighbour want 'No adjacent enemy' sheet got:\n%s" % text)
		return
	_pass("no at-war neighbour: never a neutral, No adjacent enemy sheet")


func _sheet() -> Node:
	var ui := _mr.get_node_or_null("UI") if _mr != null else null
	if ui == null:
		return null
	return ui.get_node_or_null("OpenFightSheet")


func _sheet_text() -> String:
	var sheet := _sheet()
	if sheet == null:
		return ""
	var bits: PackedStringArray = PackedStringArray()
	for node in sheet.find_children("*", "Label", true, false):
		if node is Label:
			var t := str((node as Label).text).strip_edges()
			if not t.is_empty():
				bits.append(t)
	return "\n".join(bits)
