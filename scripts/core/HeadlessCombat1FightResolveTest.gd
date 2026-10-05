extends SceneTree

## COMBAT-1: Open fight prefers a defended neighbor, Start opens a real
## fight, and the existing land-battle tick paints Took/Held on toast + card.
## Does not load WorldMap.tscn / 3520 polygons.
## Does not touch TipDismiss, ORDERS card layout, or chip draw-order / hit rank.
##
## Live Play recipe: docs/evidence/combat1/CLICKS.md (same 1280×740 @(0,29)
## coords as ORDERS-1). xvfb / headless ≠ live Play.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCombat1FightResolveTest.gd
##   tools/eoa_combat1_guard.sh

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_BM := "res://scripts/combat/BattleManager.gd"
const BONN := 710416
const HAUT_RHIN := 710740
const BAS_RHIN := 710739
const GER_TAG := "GER"
const FRA_TAG := "FRA"
const FID := "combat1_ger_div"
const FID_DEF := "combat1_fra_def"
const DESIGN := "infantry_1936"
const FLUSH_FRAMES := 10

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _bm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _cam: Camera2D = null
var _info: Panel = null
var _chip: Node2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessCombat1FightResolveTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCombat1FightResolveTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCombat1FightResolveTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCombat1FightResolveTest: ", msg)


func _info_line(msg: String) -> void:
	print("  [INFO] HeadlessCombat1FightResolveTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


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
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	_bm = _autoload("BattleManager")
	if _lm == null or _mm == null or _bm == null:
		_fail("autoloads missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _setup_fixture():
		return
	if not _setup_formations():
		return
	if not _setup_map_renderer():
		return
	_test_prefer_defended_neighbor()
	await _test_open_fight_start_and_resolve()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	var bm := _read(SRC_BM)
	if ren.is_empty() or bm.is_empty():
		_fail("MapRenderer / BattleManager missing")
		return
	var adj_fn := _slice_func(ren, "_adjacent_enemy_province_id")
	if adj_fn.is_empty() or "_province_has_defending_units" not in adj_fn:
		_fail("_adjacent_enemy_province_id must prefer a defended neighbor")
		return
	var def_fn := _slice_func(ren, "_province_has_defending_units")
	if def_fn.is_empty() or "get_divisions_at_province" not in def_fn:
		_fail("_province_has_defending_units must call get_divisions_at_province")
		return
	if "refresh_after_land_battle_day" not in ren or "_surface_last_land_aar_toast" not in ren:
		_fail("COMBAT-1 must surface AAR after the land-battle tick")
		return
	var day_fn := _slice_func(ren, "_on_game_day_advanced_legend")
	if day_fn.find("_surface_last_land_aar_toast") < 0:
		_fail("day emit must still surface leftover AAR when open_n is 0")
		return
	var open_n_block := ""
	var open_i := day_fn.find("if open_n > 0:")
	if open_i >= 0:
		open_n_block = day_fn.substr(open_i, 700)
	if "peek_last_land_aar" in open_n_block and "_surface_last_land_aar_toast" not in day_fn:
		_fail("AAR toast must not be gated on remaining open fights only")
		return
	if "_notify_land_battle_day_surface" not in bm:
		_fail("BattleManager must notify map after tick_open_land_battles")
		return
	var tick_fn := _slice_func(bm, "tick_open_land_battles")
	if "_notify_land_battle_day_surface" not in tick_fn:
		_fail("tick_open_land_battles must notify the fight-day surface")
		return
	var popup := _slice_func(ren, "_show_unit_detail_popup")
	if "stance_row.add_child(wd_btn)" not in popup or "UNIT_CARD_DOCK_RESERVE" not in ren:
		_fail("ORDERS card layout must stay (Hold/Withdraw dock)")
		return
	if "TipDismiss" in _slice_func(ren, "refresh_after_land_battle_day"):
		_fail("COMBAT-1 must not edit TipDismiss")
		return
	if "func show_first_session_action_tip" in _slice_func(ren, "_surface_last_land_aar_toast"):
		_fail("COMBAT-1 must not own the first-session tip")
		return
	_pass("source needles: defended neighbor + AAR after tick; ORDERS/TipDismiss fenced")


func _setup_fixture() -> bool:
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	# Empty Haut-Rhin is first so a first-enemy pick would instant-capture.
	if adj_sys.has_method("load_from_dict"):
		adj_sys.call("load_from_dict", {
			"adjacency": {
				str(BONN): [HAUT_RHIN, BAS_RHIN],
				str(HAUT_RHIN): [BONN],
				str(BAS_RHIN): [BONN],
			}
		})
	var rows: Array = [
		{"id": BONN, "tag": GER_TAG, "name": "Bonn"},
		{"id": HAUT_RHIN, "tag": FRA_TAG, "name": "Haut-Rhin"},
		{"id": BAS_RHIN, "tag": FRA_TAG, "name": "Bas-Rhin"},
	]
	var provs: Dictionary = {}
	var countries: Dictionary = {
		GER_TAG: {"tag": GER_TAG, "name": "Germany"},
		FRA_TAG: {"tag": FRA_TAG, "name": "France"},
	}
	for row in rows:
		var pid := int(row["id"])
		var p: Object = _new_obj("res://scripts/data/Province.gd")
		if p == null:
			_fail("Province create failed")
			return false
		var tag := str(row["tag"])
		p.set("id", pid)
		p.set("owner_tag", tag)
		p.set("controller_tag", tag)
		p.set("terrain", "plains")
		p.set("name", str(row["name"]))
		p.set("is_sea", false)
		p.set("infrastructure", 4)
		p.set("development_level", 3)
		p.set("core_for", [tag])
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
	var first_adj := -1
	if _mm.has_method("get_adjacent_provinces"):
		var adj: Array = _mm.call("get_adjacent_provinces", BONN, true)
		if not adj.is_empty():
			first_adj = int(adj[0])
	if first_adj != HAUT_RHIN:
		_fail("fixture first adjacent must be empty Haut-Rhin %d got %d" % [HAUT_RHIN, first_adj])
		return false
	_pass("fixture Bonn + empty Haut-Rhin first + defended Bas-Rhin")
	return true


func _setup_formations() -> bool:
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
	f.set("is_in_combat", false)
	f.set("name", "GER COMBAT-1 Div")
	if "formations" in _lm:
		_lm.formations[FID] = f
	var d: Object = _new_obj("res://scripts/formations/Formation.gd")
	if d == null:
		_fail("defender Formation create failed")
		return false
	d.set("formation_id", FID_DEF)
	d.set("country_tag", FRA_TAG)
	d.set("formation_type", "division")
	d.set("design_id", DESIGN)
	d.set("stationed_province_id", BAS_RHIN)
	d.set("strength", 1.0)
	d.set("organization", 1.0)
	d.set("readiness", 1.0)
	d.set("is_in_combat", false)
	d.set("name", "FRA COMBAT-1 Def")
	if "formations" in _lm:
		_lm.formations[FID_DEF] = d
	_pass("seeded GER at Bonn + FRA defender at Bas-Rhin only")
	return true


func _setup_map_renderer() -> bool:
	var win: Window = root as Window
	if win != null:
		win.size = Vector2i(1280, 740)
	DisplayServer.window_set_size(Vector2i(1280, 740))
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
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_mr.add_child(_ui)
	_info = Panel.new()
	_info.name = "InfoPanel"
	_info.visible = false
	_info.size = Vector2(280, 200)
	_ui.add_child(_info)
	_mr.set("info_panel", _info)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(400, 300)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	var pids: Array = [BONN, HAUT_RHIN, BAS_RHIN]
	for pid_v in pids:
		var pid := int(pid_v)
		var gp: Variant = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
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
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = Vector2(float(pid % 100) * 8.0, 40.0)
	_place_chip()
	_pass("MapRenderer + UI canvas + GER chip")
	return true


func _place_chip() -> void:
	if _mr == null or not ("province_nodes" in _mr):
		return
	var host: Node2D = _mr.province_nodes.get(BONN) as Node2D
	if host == null:
		return
	var old: Node = host.get_node_or_null("DemoUnitIcon_%d" % BONN)
	if old != null:
		old.free()
	_chip = Node2D.new()
	_chip.name = "DemoUnitIcon_%d" % BONN
	_chip.visible = true
	host.add_child(_chip)
	_chip.position = Vector2.ZERO
	var fo: Object = _formation()
	_chip.set_meta("formation", fo)
	_chip.set_meta("formation_id", FID)
	_chip.set_meta("province_id", BONN)
	if "show_unit_counters" in _mr:
		_mr.show_unit_counters = true
	if "_demo_unit_icon_pids" in _mr:
		var pids: Array = _mr._demo_unit_icon_pids
		if not pids.has(BONN):
			pids.append(BONN)
			_mr._demo_unit_icon_pids = pids
	if fo != null and _mr.has_method("_attach_unit_counter_chrome"):
		_mr.call("_attach_unit_counter_chrome", _chip, fo, Color(0.2, 0.35, 0.22, 1.0))
	if _mr.has_method("_refresh_selected_unit_chip"):
		_mr.call("_refresh_selected_unit_chip")


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _defender() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID_DEF)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID_DEF)
	return null


func _test_prefer_defended_neighbor() -> void:
	if _mr == null or not _mr.has_method("_adjacent_enemy_province_id"):
		_fail("_adjacent_enemy_province_id missing")
		return
	var picked := int(_mr.call("_adjacent_enemy_province_id", BONN, GER_TAG))
	if picked != BAS_RHIN:
		_fail("Open fight pick want defended Bas-Rhin %d got %d (empty Haut-Rhin is first adj)" % [BAS_RHIN, picked])
		return
	_pass("prefer defended Bas-Rhin over empty Haut-Rhin")
	var def_f: Object = _defender()
	if def_f != null:
		def_f.set("stationed_province_id", -1)
	var empty_pick := int(_mr.call("_adjacent_enemy_province_id", BONN, GER_TAG))
	if def_f != null:
		def_f.set("stationed_province_id", BAS_RHIN)
	if empty_pick != HAUT_RHIN:
		_fail("empty-only fallback want Haut-Rhin %d got %d" % [HAUT_RHIN, empty_pick])
		return
	_pass("empty Haut-Rhin fallback when no defender exists")


func _popup() -> Node:
	if _ui == null:
		return null
	return _ui.get_node_or_null("UnitDetailPopup")


func _sheet() -> Node:
	if _ui == null:
		return null
	return _ui.get_node_or_null("OpenFightSheet")


func _find_btn(root_n: Node, node_name: String, text_prefix: String) -> Button:
	if root_n == null:
		return null
	var named: Button = root_n.find_child(node_name, true, false) as Button
	if named != null:
		return named
	for n in root_n.find_children("*", "Button", true, false):
		if n is Button and str((n as Button).text).begins_with(text_prefix):
			return n as Button
	return null


func _card_text() -> String:
	var pop: Node = _popup()
	if pop == null:
		return ""
	var bits: PackedStringArray = PackedStringArray()
	for n in pop.find_children("*", "Label", true, false):
		if n is Label:
			var t := str((n as Label).text).strip_edges()
			if not t.is_empty():
				bits.append(t)
	return " | ".join(bits)


func _flush_frames() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _test_open_fight_start_and_resolve() -> void:
	var fo: Object = _formation()
	if fo == null:
		_fail("attacker missing")
		return
	fo.set("stationed_province_id", BONN)
	fo.set("is_in_combat", false)
	fo.set("strength", 1.0)
	var def_f: Object = _defender()
	if def_f != null:
		def_f.set("stationed_province_id", BAS_RHIN)
		def_f.set("is_in_combat", false)
		def_f.set("strength", 1.0)
	if _bm.has_method("clear_last_land_aar"):
		_bm.call("clear_last_land_aar")
	if "_open_land_battles" in _bm:
		_bm._open_land_battles = []
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	_mr.call("_show_unit_detail_popup", fo)
	await _flush_frames()
	var open_btn: Button = _find_btn(_popup(), "BtnOpenFight", "Open fight")
	if open_btn == null:
		_fail("Open fight missing on card")
		return
	open_btn.pressed.emit()
	await _flush_frames()
	var sheet: Node = _sheet()
	if sheet == null:
		_fail("Open fight sheet missing")
		return
	var sheet_txt := ""
	for n in sheet.find_children("*", "Label", true, false):
		if n is Label:
			sheet_txt += str((n as Label).text) + "\n"
	if sheet_txt.findn("Haut-Rhin") >= 0 and sheet_txt.findn("Bas-Rhin") < 0:
		_fail("Open fight sheet picked empty Haut-Rhin: %s" % sheet_txt)
		return
	if sheet_txt.findn("Bas-Rhin") < 0:
		_fail("Open fight sheet missing Bas-Rhin defender: %s" % sheet_txt)
		return
	var start_btn: Button = _find_btn(sheet, "BtnStartBattle", "Start battle")
	if start_btn == null:
		_fail("Start battle missing")
		return
	start_btn.pressed.emit()
	await _flush_frames()
	var opened: Dictionary = {}
	if _bm.has_method("get_land_battle_for_formation"):
		opened = _bm.call("get_land_battle_for_formation", FID) as Dictionary
	if opened.is_empty() or int(opened.get("to_id", -1)) != BAS_RHIN:
		_fail("Start did not open a fight into Bas-Rhin: %s" % str(opened))
		return
	if bool(opened.get("instant", false)):
		_fail("Start was instant empty capture, not a fight")
		return
	_pass("Start battle opened GER→Bas-Rhin (not empty Haut-Rhin)")
	var str_before := float(fo.get("strength"))
	var fill_before := _card_text()
	if _bm.has_method("tick_open_land_battles"):
		_bm.call("tick_open_land_battles", 8.0)
	await _flush_frames()
	var aar: Dictionary = {}
	if _bm.has_method("peek_last_land_aar"):
		aar = _bm.call("peek_last_land_aar") as Dictionary
	var aar_line := str(aar.get("line", "")).strip_edges()
	var toast := ""
	if "_last_inspector_toast" in _mr:
		toast = str(_mr._last_inspector_toast)
	var visible := ("%s %s %s" % [aar_line, toast, str(aar.get("winner", ""))]).to_lower()
	if aar_line.is_empty():
		_fail("no AAR line after fight tick")
		return
	if (
		visible.find("took") < 0
		and visible.find("held") < 0
		and visible.find("battle ended") < 0
	):
		_fail("AAR/toast not readable Took/Held/ended: aar=%s toast=%s winner=%s" % [aar_line, toast, str(aar.get("winner", ""))])
		return
	if toast.find(aar_line) < 0 and toast.to_lower().find("took") < 0 and toast.to_lower().find("held") < 0:
		_fail("toast missing AAR line (playtester cannot see resolve): toast=%s aar=%s" % [toast, aar_line])
		return
	var str_after := float(fo.get("strength"))
	var fill_after := _card_text()
	var str_changed := str_after + 0.0001 < str_before
	var fill_changed := fill_after != fill_before and not fill_after.is_empty()
	var fill_mentions := fill_after.findn("Fill") >= 0 or fill_after.findn("Str") >= 0
	if not str_changed and not fill_changed:
		_fail(
			"no strength/Fill change on card after resolve str=%.3f→%.3f card_changed=%s"
			% [str_before, str_after, str(fill_changed)]
		)
		return
	if not fill_mentions and _popup() == null:
		_fail("fighting card missing after resolve")
		return
	_info_line(
		"resolve aar=%s toast=%s str=%.3f→%.3f card_fill=%s"
		% [aar_line, toast, str_before, str_after, fill_after.substr(0, 80)]
	)
	_pass("fight resolved: chips/card + readable Took/Held toast")


func _cleanup() -> void:
	if _lm != null and "formations" in _lm and _lm.formations is Dictionary:
		_lm.formations.erase(FID)
		_lm.formations.erase(FID_DEF)
	if _bm != null and "_open_land_battles" in _bm:
		_bm._open_land_battles = []
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
