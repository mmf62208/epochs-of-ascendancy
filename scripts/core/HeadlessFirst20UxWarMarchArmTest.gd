extends SceneTree

## FIRST20-UX-WAR (c): March… arms the next own-land click onto the same
## enqueue_own_land_march path. Esc clears the arm without a march.
## Right-click stays pan (#169) — this test never binds it to move.
##
##   tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessFirst20UxWarMarchArmTest.gd

const ADJ_PATH := "res://data/provinces_pilot_europe_nuts3/province_adjacency.json"
const BONN := 710416
const KOELN := 710417
const GER_TAG := "GER"
const FID := "f20_ux_war_march"
const DESIGN := "infantry_1936"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const FLUSH_FRAMES := 4

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _mv: Script = null
var _ui: CanvasLayer = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessFirst20UxWarMarchArmTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFirst20UxWarMarchArmTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFirst20UxWarMarchArmTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFirst20UxWarMarchArmTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


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


func _run() -> void:
	_test_source_needles()
	_lm = root.get_node_or_null("LeaderManager")
	_mm = root.get_node_or_null("MapManager")
	_mv = load("res://scripts/formations/FormationMovement.gd") as Script
	if _lm == null or _mm == null or _mv == null:
		_fail("autoloads missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _setup_nuts3_fixture():
		return
	if not _setup_formation():
		return
	if not _setup_map_renderer():
		return
	await _test_arm_then_own_land_matches_existing()
	_test_esc_clears_arm_without_march()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if "BtnMarchArm" not in ren or "_arm_march_destination" not in ren:
		_fail("unit card must expose March… arm (BtnMarchArm / _arm_march_destination)")
		return
	if "MarchSelectHint" not in ren:
		_fail("persistent MarchSelectHint missing while a unit is selected")
		return
	var try_fn := _slice_func(ren, "_try_move_selected_unit_to_province")
	if try_fn.is_empty() or "enqueue_own_land_march" not in try_fn:
		_fail("march commit must stay on enqueue_own_land_march")
		return
	if "MOUSE_BUTTON_RIGHT" in try_fn:
		_fail("must not bind right-click to march")
		return
	_pass("source needles: March… arm + persistent hint; no right-click move")


func _setup_nuts3_fixture() -> bool:
	if not FileAccess.file_exists(ADJ_PATH):
		_fail("nuts3 adjacency missing")
		return false
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	if adj_sys.has_method("load_adjacency"):
		adj_sys.call("load_adjacency", ADJ_PATH)
	var rows: Array = [
		{"id": BONN, "tag": GER_TAG, "name": "Bonn"},
		{"id": KOELN, "tag": GER_TAG, "name": "Köln"},
	]
	var provs: Dictionary = {}
	var countries: Dictionary = {GER_TAG: {"tag": GER_TAG, "name": "Germany"}}
	for row in rows:
		var pid := int(row["id"])
		var p: Object = _new_obj("res://scripts/data/Province.gd")
		if p == null:
			_fail("Province create failed")
			return false
		p.set("id", pid)
		p.set("name", str(row["name"]))
		p.set("owner_tag", GER_TAG)
		p.set("controller_tag", GER_TAG)
		p.set("is_sea", false)
		p.set("core_for", [GER_TAG])
		provs[pid] = p
		if adj_sys.has_method("register_province"):
			adj_sys.call("register_province", p)
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
	_pass("nuts3 fixture Bonn/Köln")
	return true


func _setup_formation() -> bool:
	_mv.call("clear_march", FID)
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("Formation create failed")
		return false
	f.set("formation_id", FID)
	f.set("country_tag", GER_TAG)
	f.set("formation_type", "division")
	f.set("design_id", DESIGN)
	f.set("stationed_province_id", BONN)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set("name", "GER UX-WAR March")
	if "formations" in _lm:
		_lm.formations[FID] = f
	_pass("seeded GER formation at Bonn")
	return true


func _setup_map_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new() as Node
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_mr.add_child(_ui)
	var info := Panel.new()
	info.name = "InfoPanel"
	info.visible = false
	_ui.add_child(info)
	_mr.set("info_panel", info)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.enabled = true
	_mr.add_child(cam)
	root.add_child(_mr)
	cam.make_current()
	for pid_v in [BONN, KOELN]:
		var pid := int(pid_v)
		var gp: Variant = _mm.call("get_province", pid)
		if gp == null:
			_fail("MapManager missing province %d" % pid)
			return false
		_mr.provinces[pid] = gp
	_pass("MapRenderer + UI canvas")
	return true


func _koeln() -> Object:
	if _mm != null and _mm.has_method("get_province"):
		return _mm.call("get_province", KOELN)
	return null


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _march_dest() -> int:
	if _mv == null or not _mv.has_method("get_march"):
		return -1
	var march: Dictionary = _mv.call("get_march", FID)
	if march.is_empty():
		return -1
	return int(march.get("dest_id", -1))


func _test_arm_then_own_land_matches_existing() -> void:
	_mv.call("clear_march", FID)
	var fo: Object = _formation()
	if fo != null:
		fo.set("stationed_province_id", BONN)
	_mr.set("selected_formation_id", FID)
	_mr.call("_refresh_selected_unit_chip")
	await _flush()
	var hint := _ui.get_node_or_null("MarchSelectHint") as Label
	if hint == null or not hint.visible:
		_fail("persistent MarchSelectHint missing while unit selected")
		return
	if str(hint.text).find("click own land") < 0:
		_fail("MarchSelectHint copy got %s" % hint.text)
		return
	_mr.call("_show_unit_detail_popup", fo)
	await _flush()
	var pop := _ui.get_node_or_null("UnitDetailPopup")
	var march_btn: Button = pop.find_child("BtnMarchArm", true, false) as Button if pop != null else null
	if march_btn == null:
		_fail("unit card missing March… button")
		return
	var dest_p: Object = _koeln()
	if dest_p == null:
		_fail("Köln missing")
		return
	var unarmed: bool = bool(_mr.call("_try_move_selected_unit_to_province", dest_p))
	var unarmed_dest := _march_dest()
	if not unarmed or unarmed_dest != KOELN:
		_fail("existing path want Köln march got dest=%d ok=%s" % [unarmed_dest, str(unarmed)])
		return
	_mv.call("clear_march", FID)
	if fo != null:
		fo.set("stationed_province_id", BONN)
	_mr.set("selected_formation_id", FID)
	_mr.call("_show_unit_detail_popup", fo)
	await _flush()
	pop = _ui.get_node_or_null("UnitDetailPopup")
	march_btn = pop.find_child("BtnMarchArm", true, false) as Button if pop != null else null
	if march_btn == null:
		_fail("March… button missing on refresh")
		return
	_mr.call("_arm_march_destination")
	if not bool(_mr.get("_march_dest_armed")):
		_fail("March… did not arm")
		return
	var armed: bool = bool(_mr.call("_try_move_selected_unit_to_province", dest_p))
	var armed_dest := _march_dest()
	if not armed or armed_dest != unarmed_dest:
		_fail("armed march dest %d != existing %d" % [armed_dest, unarmed_dest])
		return
	if bool(_mr.get("_march_dest_armed")):
		_fail("arm should clear after commit")
		return
	_pass("armed March… click issues the same Köln order as the existing path")


func _test_esc_clears_arm_without_march() -> void:
	_mv.call("clear_march", FID)
	var fo: Object = _formation()
	if fo != null:
		fo.set("stationed_province_id", BONN)
	_mr.set("selected_formation_id", FID)
	_mr.call("_arm_march_destination")
	if not bool(_mr.get("_march_dest_armed")):
		_fail("arm missing before Esc")
		return
	_mr.call("_handle_escape_key")
	if bool(_mr.get("_march_dest_armed")):
		_fail("Esc did not clear March… arm")
		return
	if bool(_mv.call("has_march", FID)):
		_fail("Esc cleared arm but issued a march")
		return
	if str(_mr.selected_formation_id) != FID:
		_fail("Esc arm-cancel dropped unit selection")
		return
	_pass("Esc clears March… arm without a march")


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
