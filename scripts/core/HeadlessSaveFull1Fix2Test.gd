extends SceneTree

## SAVE-FULL-1 FIX part 2. Fails on d4a50cf8, passes after the fleet/land split,
## the Begin GER seat, and the FIN/NOR national designs.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessSaveFull1Fix2Test.gd

const MAGINOT := 710173
const BAS_RHIN := 710739
const NORTH_SEA := 950000
const ROME := 710963
const FID_LAND := "GER_formation_0"
const FID_FLEET := "GER_formation_2"
const WORLD_MAGINOT := Vector2(4283.279411, 1010.266854)
const WORLD_BAS := Vector2(4269.73, 1004.85)
const WORLD_NORTH_SEA := Vector2(4164.266667, 773.688889)
const WORLD_ROME := Vector2(4383.92, 1213.06)
const CAM_HOME := Vector2(4200.0, 900.0)

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _cam: Camera2D = null


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveFull1Fix2Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveFull1Fix2Test: ", msg)


func _run() -> void:
	_lm = root.get_node_or_null("LeaderManager")
	_mm = root.get_node_or_null("MapManager")
	_test_designs()
	_test_begin_ger()
	await _test_fleet_vs_land()
	if _failures > 0:
		print("HeadlessSaveFull1Fix2Test: RESULT=FAIL failures=%d" % _failures)
	else:
		print("HeadlessSaveFull1Fix2Test: RESULT=PASS")
	quit(1 if _failures > 0 else 0)


func _test_designs() -> void:
	var sp_script: Script = load("res://scripts/formations/FormationSpawner.gd") as Script
	if sp_script == null:
		_fail("C: spawner script missing")
		return
	var want := {
		"FIN": "fin_armor_1936",
		"NOR": "nor_armor_1936",
		"BEL": "m3_stuart_light_tank",
		"DNK": "m3_stuart_light_tank",
		"CZE": "lt_vz_35_light",
		"SWE": "swe_armor_1936",
	}
	var bad := PackedStringArray()
	for tag in ["FIN", "NOR", "BEL", "DNK", "CZE", "SWE"]:
		var got := str(sp_script.call("minor_land_design_id", tag))
		print("  [INFO] C minor_land_design_id %s=%s" % [tag, got])
		if got != str(want[tag]):
			bad.append("%s=%s" % [tag, got])
	if _lm != null and _lm.has_method("clear_all_formations"):
		_lm.call("clear_all_formations")
	var sp: Node = sp_script.new() as Node
	root.add_child(sp)
	for tag in ["FIN", "NOR", "BEL", "GER"]:
		var capital := 710300 if tag == "GER" else 1
		sp.call("spawn_test_formations_for_country", tag, 1, capital, [capital])
	var spawned := {"FIN": "", "NOR": "", "BEL": "", "GER": ""}
	if _lm != null and _lm.has_method("get_formations_for_country"):
		for tag2 in ["FIN", "NOR", "BEL", "GER"]:
			for f in _lm.call("get_formations_for_country", tag2):
				if f == null:
					continue
				if str(f.formation_type) != "division":
					continue
				spawned[tag2] = str(f.design_id)
				break
	print(
		"  [INFO] C spawned FIN=%s NOR=%s BEL=%s GER=%s"
		% [spawned["FIN"], spawned["NOR"], spawned["BEL"], spawned["GER"]]
	)
	if str(spawned["FIN"]) != "fin_armor_1936":
		bad.append("spawn FIN=%s" % spawned["FIN"])
	if str(spawned["NOR"]) != "nor_armor_1936":
		bad.append("spawn NOR=%s" % spawned["NOR"])
	if str(spawned["BEL"]) != "m3_stuart_light_tank":
		bad.append("spawn BEL=%s" % spawned["BEL"])
	if str(spawned["GER"]) != "panzer_iii_j_medium":
		bad.append("spawn GER=%s" % spawned["GER"])
	if _lm != null and _lm.has_method("clear_all_formations"):
		_lm.call("clear_all_formations")
	sp.free()
	if not bad.is_empty():
		_fail("C: designs %s" % ", ".join(bad))
		return
	_pass("C: FIN fin_armor_1936, NOR nor_armor_1936, BEL stays Stuart, GER stays panzer")


func _test_begin_ger() -> void:
	var session := root.get_node_or_null("SessionPlayers")
	var sl := root.get_node_or_null("SaveLoadManager")
	var sm := root.get_node_or_null("SupplyManager")
	if _lm == null or session == null or _mm == null:
		_fail("B: autoloads missing")
		return
	var boot_s: Script = load("res://scripts/core/CampaignLoopTestBoot.gd") as Script
	if boot_s == null or not bool(boot_s.call("boot", _mm, sm, "GER")):
		_fail("B: world_accurate boot failed")
		return
	if session.has_method("setup_solo_play"):
		session.call("setup_solo_play", "USA")
	var title_s: Script = load("res://scripts/ui/LivingTitleBoot.gd") as Script
	if title_s == null:
		_fail("B: title boot script missing")
		return
	var picked: Dictionary = title_s.call("apply_living_title_boot", "GER", 1936, "")
	_print_war_probe("before_sync", picked)
	if session.has_method("_sync_leader_player_tag"):
		session.call("_sync_leader_player_tag")
	var probe := _print_war_probe("after_sync", {})
	var tag := str(probe.get("leader", ""))
	var slot := str(probe.get("slot", ""))
	var label := str(probe.get("label", ""))
	var meta_tag := ""
	if sl != null and sl.has_method("_gather_save_data"):
		var data: Dictionary = sl.call("_gather_save_data")
		var meta: Dictionary = data.get("metadata", {}) as Dictionary
		meta_tag = str(meta.get("player_tag", "")).strip_edges().to_upper()
		print("  [INFO] B metadata.player_tag=%s" % meta_tag)
	var names_ger := label.find("France") >= 0 or label.find("Poland") >= 0
	var names_japan := label.find("Japan") >= 0
	if tag != "GER" or slot != "GER" or not names_ger or names_japan or meta_tag != "GER":
		_fail(
			"B: after Begin GER tag=%s slot=%s meta=%s label='%s'"
			% [tag, slot, meta_tag, label]
		)
	else:
		_pass("B: Begin GER keeps GER through sync; NEXT names %s" % label)
	if session.has_method("setup_solo_play"):
		session.call("setup_solo_play", "USA")
	title_s.call("apply_living_title_boot", "USA", 1936, "")
	if session.has_method("_sync_leader_player_tag"):
		session.call("_sync_leader_player_tag")
	var usa := _print_war_probe("usa", {})
	var usa_tag := str(usa.get("leader", ""))
	var usa_label := str(usa.get("label", ""))
	var usa_sug := str(usa.get("suggest", ""))
	if usa_tag != "USA":
		_fail("B: USA session tag=%s" % usa_tag)
		return
	if usa_sug == "JAP" and usa_label.find("Japan") < 0:
		_fail("B: USA suggest JAP but label '%s'" % usa_label)
		return
	_pass("B: USA session stays USA (suggest %s, label '%s')" % [usa_sug, usa_label])


func _print_war_probe(when: String, picked: Dictionary) -> Dictionary:
	var session := root.get_node_or_null("SessionPlayers")
	var leader := ""
	if _lm != null and _lm.has_method("get_player_country_tag"):
		leader = str(_lm.call("get_player_country_tag"))
	var supply := ""
	var sm := root.get_node_or_null("SupplyManager")
	if sm != null and "player_tag" in sm:
		supply = str(sm.player_tag)
	var slot := ""
	if session != null and session.has_method("get_active_tag"):
		slot = str(session.call("get_active_tag"))
	var label := ""
	var hook_s: Script = load("res://scripts/ui/PlayNextHook.gd") as Script
	if hook_s != null:
		var rec: Dictionary = hook_s.call("recommend", "")
		label = str(rec.get("label", ""))
	var suggest := ""
	var neigh := ""
	var war_s: Script = load("res://scripts/core/WarStateDomain.gd") as Script
	if war_s != null:
		var sug: Dictionary = war_s.call("suggest_player_target")
		suggest = str(sug.get("tag", ""))
		var keys: Array = war_s.call("land_neighbours", "GER")
		neigh = ",".join(keys)
	print(
		"  [INFO] B %s leader=%s supply=%s slot=%s suggest=%s label='%s' picked=%s GER_neighbours=%s"
		% [when, leader, supply, slot, suggest, label, str(picked.get("player_tag", "")), neigh]
	)
	return {"leader": leader, "supply": supply, "slot": slot, "suggest": suggest, "label": label}


func _test_fleet_vs_land() -> void:
	if _lm == null or _mm == null:
		_fail("A: autoloads missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", "GER")
	if _lm.has_method("clear_all_formations"):
		_lm.call("clear_all_formations")
	if not await _setup_fleet_fixture():
		return
	# Land Open fight with nothing selected still reaches Bas-Rhin.
	_mr.call("_open_fight_from_formation_id", "")
	var empty_txt := _sheet_text()
	print("  [INFO] A empty-fid sheet='%s'" % empty_txt.replace("\n", " | "))
	if empty_txt.find("Bas-Rhin") < 0:
		_fail("A: land fallback sheet missing Bas-Rhin ('%s')" % empty_txt.replace("\n", " | "))
	else:
		_pass("A: empty land Open fight still names Bas-Rhin")
	_free_sheet()
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = ""
	_park_camera()
	var home := _cam.position
	var ev := _event_at_world(WORLD_NORTH_SEA)
	var opened := false
	if _mr.has_method("_try_open_land_chip_from_input"):
		opened = bool(_mr.call("_try_open_land_chip_from_input", false, ev))
	if not opened and _mr.has_method("_try_open_unit_at_world"):
		opened = bool(_mr.call("_try_open_unit_at_world", WORLD_NORTH_SEA))
	if not opened and _mr.has_method("_try_open_land_unit_at_world"):
		opened = bool(_mr.call("_try_open_land_unit_at_world", WORLD_NORTH_SEA, false, false))
	var sel := str(_mr.selected_formation_id) if "selected_formation_id" in _mr else ""
	var fleet_station := _station(FID_FLEET)
	print(
		"  [INFO] A select opened=%s sel=%s station=%d cam=%s sheet='%s'"
		% [opened, sel, fleet_station, str(_cam.position), _sheet_text().replace("\n", " | ")]
	)
	if not opened or sel != FID_FLEET or not _popup_up():
		_fail("A: fleet click sel=%s opened=%s card=%s" % [sel, opened, _popup_up()])
	elif _sheet_text().find("Bas-Rhin") >= 0 or _camera_left_home(home) or fleet_station != NORTH_SEA:
		_fail(
			"A: fleet select opened Maginot or moved camera station=%d cam=%s"
			% [fleet_station, str(_cam.position)]
		)
	else:
		_pass("A: fleet click opens the fleet card, no Bas-Rhin sheet, camera stays off Italy")
	var pop := _popup()
	var fight_btn: Button = null
	if pop != null:
		fight_btn = pop.find_child("BtnOpenFight", true, false) as Button
	if fight_btn == null:
		_fail("A: fleet card has no Open fight button")
	else:
		_park_camera()
		home = _cam.position
		fight_btn.pressed.emit()
		var after := _sheet_text()
		fleet_station = _station(FID_FLEET)
		print(
			"  [INFO] A fleet Open fight sheet='%s' station=%d cam=%s"
			% [after.replace("\n", " | "), fleet_station, str(_cam.position)]
		)
		if after.find("Bas-Rhin") >= 0 or after.find(FID_LAND) >= 0 or fleet_station != NORTH_SEA or _camera_left_home(home):
			_fail(
				"A: fleet Open fight became land sheet station=%d cam=%s body='%s'"
				% [fleet_station, str(_cam.position), after.replace("\n", " | ")]
			)
		else:
			_pass("A: fleet Open fight stays on the fleet card and off Italy")
	_free_sheet()
	_park_camera()
	home = _cam.position
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID_FLEET
	_mr.call("_open_fight_from_formation_id", "")
	var stolen := _sheet_text()
	fleet_station = _station(FID_FLEET)
	print(
		"  [INFO] A empty-fid while fleet selected sheet='%s' station=%d cam=%s"
		% [stolen.replace("\n", " | "), fleet_station, str(_cam.position)]
	)
	if stolen.find("Bas-Rhin") >= 0 or stolen.find(FID_LAND) >= 0 or fleet_station != NORTH_SEA or _camera_left_home(home):
		_fail("A: empty Open fight stole the Maginot division while the fleet was selected")
	else:
		_pass("A: empty Open fight does not steal Bas-Rhin while a fleet is selected")
	_free_sheet()
	_mr.call("_open_fight_from_formation_id", FID_LAND)
	var land_txt := _sheet_text()
	print("  [INFO] A land Open fight sheet='%s' cam=%s" % [land_txt.replace("\n", " | "), str(_cam.position)])
	if land_txt.find("Bas-Rhin") < 0 or land_txt.find("FRA") < 0:
		_fail("A: Maginot Open fight missing Bas-Rhin ('%s')" % land_txt.replace("\n", " | "))
	else:
		_pass("A: Maginot division Open fight still opens Bas-Rhin %d" % BAS_RHIN)
	if _mr != null:
		_mr.set_process(false)
		_mr.queue_free()


func _camera_left_home(home: Vector2) -> bool:
	if _cam == null:
		return true
	if _cam.position.distance_to(WORLD_ROME) < 200.0:
		return true
	return _cam.position.distance_to(home) > 40.0


func _station(fid: String) -> int:
	if _lm == null or not _lm.has_method("get_formation"):
		return -1
	var fo: Object = _lm.call("get_formation", fid)
	if fo == null or not ("stationed_province_id" in fo):
		return -1
	return int(fo.stationed_province_id)


func _setup_fleet_fixture() -> bool:
	var adj: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj == null or not adj.has_method("load_from_dict"):
		_fail("A: adjacency missing")
		return false
	adj.call("load_from_dict", {
		str(MAGINOT): [BAS_RHIN],
		str(BAS_RHIN): [MAGINOT],
	})
	var rows: Array = [
		{"id": MAGINOT, "tag": "GER", "name": "Baden-Baden, Stadtkreis", "c": WORLD_MAGINOT, "sea": false},
		{"id": BAS_RHIN, "tag": "FRA", "name": "Bas-Rhin", "c": WORLD_BAS, "sea": false},
		{"id": NORTH_SEA, "tag": "", "name": "North Sea Zone", "c": WORLD_NORTH_SEA, "sea": true},
		{"id": ROME, "tag": "ITA", "name": "Roma", "c": WORLD_ROME, "sea": false},
	]
	var provs: Dictionary = {}
	var countries := {
		"GER": {"tag": "GER", "name": "Germany", "capital_province_id": MAGINOT},
		"FRA": {"tag": "FRA", "name": "France", "capital_province_id": BAS_RHIN},
		"ITA": {"tag": "ITA", "name": "Italy", "capital_province_id": ROME},
	}
	for row in rows:
		var pid := int(row["id"])
		var p: Object = _new_obj("res://scripts/data/Province.gd")
		if p == null:
			_fail("A: province create failed")
			return false
		p.set("id", pid)
		p.set("owner_tag", str(row["tag"]))
		p.set("controller_tag", str(row["tag"]))
		p.set("name", str(row["name"]))
		p.set("terrain", "sea" if bool(row["sea"]) else "plains")
		p.set("is_sea", bool(row["sea"]))
		p.set("domain", "sea" if bool(row["sea"]) else "land")
		provs[pid] = p
		if adj.has_method("register_province"):
			adj.call("register_province", p)
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	if mds == null:
		_fail("A: MapScenarioData missing")
		return false
	var map_data: Object = mds.new(provs, {}, adj, countries)
	if not _mm.has_method("initialize_from_map_data"):
		_fail("A: initialize_from_map_data missing")
		return false
	_mm.call("initialize_from_map_data", map_data)
	_force_centroids()
	if not _register(FID_LAND, "GER", "division", "panzer_iii_j_medium", MAGINOT, "Division 0"):
		return false
	if not _register(FID_FLEET, "GER", "fleet", "type_viic_uboat", NORTH_SEA, "GER North Sea Fleet"):
		return false
	if not _register("FRA_bas", "FRA", "division", "infantry_1936", BAS_RHIN, "FRA Bas-Rhin Div"):
		return false
	return await _setup_renderer()


func _setup_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("A: MapRenderer script missing")
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
	var close := Button.new()
	close.name = "BtnClose"
	info.add_child(close)
	_ui.add_child(info)
	_mr.set("info_panel", info)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = CAM_HOME
	_cam.zoom = Vector2.ONE
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	await process_frame
	await process_frame
	_mr.set_process(false)
	_cam.make_current()
	_park_camera()
	if "use_spatial_picking" in _mr:
		_mr.use_spatial_picking = true
	if "show_unit_counters" in _mr:
		_mr.show_unit_counters = true
	var placed := {
		MAGINOT: WORLD_MAGINOT,
		BAS_RHIN: WORLD_BAS,
		NORTH_SEA: WORLD_NORTH_SEA,
		ROME: WORLD_ROME,
	}
	for pid_v in placed.keys():
		var pid := int(pid_v)
		var gp: Variant = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
		if gp == null:
			_fail("A: missing province %d" % pid)
			return false
		if "provinces" in _mr:
			_mr.provinces[pid] = gp
		var node := Node2D.new()
		node.name = "Province_%d" % pid
		node.position = placed[pid]
		container.add_child(node)
		if "province_nodes" in _mr:
			_mr.province_nodes[pid] = node
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = placed[pid]
	_force_centroids()
	_place_chip(NORTH_SEA, FID_FLEET, WORLD_NORTH_SEA, true)
	_place_chip(MAGINOT, FID_LAND, WORLD_MAGINOT, false)
	_pass("A: fleet fixture North Sea vs Maginot / Bas-Rhin / Roma")
	return true


func _force_centroids() -> void:
	if _mm != null and "_centroids" in _mm:
		var cents: Dictionary = _mm.get("_centroids")
		cents[MAGINOT] = WORLD_MAGINOT
		cents[BAS_RHIN] = WORLD_BAS
		cents[NORTH_SEA] = WORLD_NORTH_SEA
		cents[ROME] = WORLD_ROME
		_mm.set("_centroids", cents)


func _place_chip(pid: int, fid: String, world: Vector2, sea_disk: bool) -> void:
	var host: Node2D = null
	if "province_nodes" in _mr and _mr.province_nodes.has(pid):
		host = _mr.province_nodes[pid] as Node2D
	if host == null:
		return
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_%d" % pid
	icon.visible = true
	host.add_child(icon)
	icon.global_position = world
	var fo: Object = _lm.call("get_formation", fid) if _lm.has_method("get_formation") else null
	if fo != null:
		icon.set_meta("formation", fo)
	icon.set_meta("formation_id", fid)
	icon.set_meta("province_id", pid)
	if sea_disk:
		icon.set_meta("sea_nation_disk", true)
		icon.set_meta("sea_nation_tag", "GER")
	if "_demo_unit_icon_pids" in _mr:
		var pids: Array = _mr._demo_unit_icon_pids
		if not pids.has(pid):
			pids.append(pid)
			_mr._demo_unit_icon_pids = pids


func _register(fid: String, tag: String, ftype: String, design: String, pid: int, pname: String) -> bool:
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("A: formation create failed %s" % fid)
		return false
	f.set("formation_id", fid)
	f.set("country_tag", tag)
	f.set("formation_type", ftype)
	f.set("design_id", design)
	f.set("naval_design_id", design if ftype == "fleet" else "")
	f.set("stationed_province_id", pid)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set("name", pname)
	if "formations" in _lm:
		_lm.formations[fid] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)
	return true


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _park_camera() -> void:
	if _cam == null:
		return
	_cam.position = CAM_HOME
	_cam.zoom = Vector2.ONE
	_cam.make_current()


func _event_at_world(world: Vector2) -> InputEventMouseButton:
	var screen := world
	if _cam != null:
		screen = _cam.get_canvas_transform() * world
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = screen
	ev.global_position = screen
	return ev


func _popup() -> Node:
	if _ui == null:
		return null
	return _ui.get_node_or_null("UnitDetailPopup")


func _popup_up() -> bool:
	var pop := _popup()
	return pop != null and is_instance_valid(pop) and not pop.is_queued_for_deletion()


func _free_sheet() -> void:
	if _ui == null:
		return
	var old := _ui.get_node_or_null("OpenFightSheet")
	if old != null:
		old.free()


func _sheet_text() -> String:
	if _ui == null:
		return ""
	var sheet := _ui.get_node_or_null("OpenFightSheet")
	if sheet == null or not is_instance_valid(sheet):
		return ""
	return _label_tree(sheet)


func _label_tree(n: Node) -> String:
	var parts := PackedStringArray()
	if n is Label:
		parts.append((n as Label).text)
	for c in n.get_children():
		var sub := _label_tree(c)
		if not sub.is_empty():
			parts.append(sub)
	return "\n".join(parts)
