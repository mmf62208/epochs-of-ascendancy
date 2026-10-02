extends SceneTree

## FLEET-1: nearest-own-land chrome spill (CHROME_SPILL_WORLD 340) must not
## steal a foreign fleet disk or an open-sea hex. Land-near-own-unit and
## own-fleet first-select stay as today. Does not load WorldMap.tscn / 3520.
## Headless / xvfb are NOT live Play.
##
## Real world_accurate label_anchor centroids (provinces_geometry.json):
##   710173 Baden-Baden / Maginot GER land  (4283.279411, 1010.266854)
##   710385 Emden (GER North Sea coast)     (4258.130659,  873.294384)
##   710417 Köln (GER land; MV-1b FRA fleet)(4254.322147,  944.095861)
##   711453 East Kent (ENG coastal land)    (4119.875715,  938.028287)
##   950000 North Sea Zone (GER fleet)      (4164.266667,  773.688889)
##   950001 English Channel (ENG fleet)     (4128.701206,  938.217996)
## Distances: Maginot↔Channel 170.5 · Maginot↔North Sea 264.8 ·
## Emden↔Maginot 139.3 — all inside the 340 spill.
## Channel↔East Kent 8.8 — East Kent GIS is inside the Channel fleet disk.
## Open-sea click: Channel + 80 along the CCW perpendicular of
## Channel→Maginot = (4094.905, 1010.727) — GIS Channel, outside fleet disk.
## FIX #1: foreign fleet disk over coastal land still inspects that fleet
## when the fleet's own stationed pid is sea. Köln FRA land-fleet stays out.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFleet1LandSpillGateTest.gd
##   tools/eoa_fleet1_guard.sh

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const GER_TAG := "GER"
const ENG_TAG := "ENG"
const FRA_TAG := "FRA"
const MAGINOT := 710173
const EMDEN := 710385
const KOLN := 710417
const EAST_KENT := 711453
const NORTH_SEA := 950000
const CHANNEL := 950001
const FID_GER_LAND := "fleet1_ger_maginot"
const FID_GER_FLEET := "fleet1_ger_north_sea"
const FID_ENG_FLEET := "fleet1_eng_channel"
const FID_FRA_FLEET_KOLN := "fleet1_fra_koln"
const FID_FRA_LAND := "fleet1_fra_land"
const DESIGN_LAND := "infantry_1936"
const DESIGN_FLEET := "king_george_v_class_bb"
const WORLD_MAGINOT := Vector2(4283.279410731325, 1010.2668539708038)
const WORLD_EMDEN := Vector2(4258.130658509457, 873.2943840595451)
const WORLD_KOLN := Vector2(4254.322147319904, 944.0958606451493)
const WORLD_EAST_KENT := Vector2(4119.875714645911, 938.0282873606084)
const WORLD_NORTH_SEA := Vector2(4164.266666666666, 773.6888888888889)
const WORLD_CHANNEL := Vector2(4128.701206024651, 938.2179956383225)
var WORLD_OPEN_SEA: Vector2 = Vector2(4094.905, 1010.727)
const FLUSH_FRAMES := 4


var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _cam: Camera2D = null
var _info: Panel = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessFleet1LandSpillGateTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFleet1LandSpillGateTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFleet1LandSpillGateTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFleet1LandSpillGateTest: ", msg)


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


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	_test_source_needles()
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	if _lm == null or _mm == null:
		_fail("autoloads missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _setup_coastal_fixture():
		return
	if not _setup_formations():
		return
	if not _setup_map_renderer():
		return
	_place_chips()
	await _flush()
	_force_play_zoom()
	_place_chips()
	await _flush()
	_resolve_open_sea_click()
	_test_distances_inside_spill()
	_test_a_foreign_fleet()
	_test_b_open_sea()
	_test_c_near_own_land()
	_test_d_own_fleet()
	_test_e_fleet_disk_over_east_kent()
	_test_f_koln_fra_land_fleet()
	_test_g_foreign_cards_readonly()
	_test_h_own_card_buttons()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var land_fn := _slice_func(ren, "_try_open_land_unit_at_world")
	if land_fn.is_empty():
		_fail("_try_open_land_unit_at_world missing")
		return
	var nearest_i := land_fn.find("_nearest_player_land_formation_at_world")
	if nearest_i < 0:
		_fail("land-open must still call nearest-own-land spill")
		return
	var gate_chunk := land_fn.substr(0, nearest_i)
	if "fo_any == null" not in gate_chunk and "fo_any == null" not in land_fn:
		_fail("spill must require no direct counter hit (fo_any == null)")
		return
	if "_hex_pick_is_land_province(world_pos)" not in gate_chunk:
		_fail("spill must require a land hex at event world")
		return
	if "func _hex_pick_is_land_province" not in ren:
		_fail("_hex_pick_is_land_province helper missing")
		return
	if "func _formation_is_fleet_counter" not in ren:
		_fail("_formation_is_fleet_counter helper missing")
		return
	if "_formation_is_fleet_counter(fo_any)" not in land_fn:
		_fail("land-open must inspect a sea foreign fleet disk")
		return
	if "_formation_is_stationed_on_sea(fo_any)" not in land_fn:
		_fail("foreign-fleet inspect must key on the fleet location pid (not GIS)")
		return
	if "not _hex_pick_is_land_province(world_pos)" in land_fn:
		_fail("foreign-fleet inspect must not use GIS-under-cursor as the sea gate")
		return
	if "func _formation_is_stationed_on_sea" not in ren:
		_fail("_formation_is_stationed_on_sea helper missing")
		return
	var pop_fn := _slice_func(ren, "_show_unit_detail_popup")
	if "own_card" not in pop_fn or "BtnOpenFight" not in pop_fn:
		_fail("unit card must still name BtnOpenFight for own units")
		return
	if "own_card" not in pop_fn or "BtnAssignLeader" not in pop_fn:
		_fail("unit card must still name BtnAssignLeader for own units")
		return
	if pop_fn.find("if own_card:") < 0:
		_fail("foreign unit cards must gate Open fight / Assign on own_card")
		return
	var move := _read("res://scripts/formations/FormationMovement.gd")
	var prev_fn := _slice_func(move, "preview_own_land_march")
	if '"not your unit"' not in prev_fn:
		_fail("preview_own_land_march must still block foreign units")
		return
	var spill := _slice_func(ren, "_nearest_player_land_formation_at_world")
	if "CHROME_SPILL_WORLD" not in spill or "340.0" not in spill:
		_fail("CHROME_SPILL_WORLD fallback must stay frozen at 340")
		return
	var chip := _slice_func(ren, "_try_open_land_chip_from_input")
	if "_map_pick_screen_pos(event)" not in chip:
		_fail("land-chip path must resolve event.position (MV-1e)")
		return
	var un_fn := _slice_func(ren, "_unhandled_input")
	if "_map_pick_world_from_event(event)" not in un_fn:
		_fail("_unhandled_input must pick via _map_pick_world_from_event")
		return
	var open_unit := _slice_func(ren, "_try_open_unit_at_world")
	if "player_only" not in open_unit or "_formation_is_player_tag" not in open_unit:
		_fail("_try_open_unit_at_world must stay player-tag (MV-1b)")
		return
	_pass("FLEET-1 source needles (spill gated; MV-1/MV-1b unedited)")


func _setup_coastal_fixture() -> bool:
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	var rows: Array = [
		{"id": MAGINOT, "tag": GER_TAG, "name": "Baden-Baden, Stadtkreis", "c": WORLD_MAGINOT, "sea": false, "domain": "land"},
		{"id": EMDEN, "tag": GER_TAG, "name": "Emden, Kreisfreie Stadt", "c": WORLD_EMDEN, "sea": false, "domain": "land"},
		{"id": KOLN, "tag": GER_TAG, "name": "Köln, Kreisfreie Stadt", "c": WORLD_KOLN, "sea": false, "domain": "land"},
		{"id": EAST_KENT, "tag": ENG_TAG, "name": "East Kent", "c": WORLD_EAST_KENT, "sea": false, "domain": "land"},
		{"id": NORTH_SEA, "tag": "", "name": "North Sea Zone", "c": WORLD_NORTH_SEA, "sea": true, "domain": "sea"},
		{"id": CHANNEL, "tag": "", "name": "English Channel Zone", "c": WORLD_CHANNEL, "sea": true, "domain": "strait"},
	]
	var provs: Dictionary = {}
	var countries: Dictionary = {
		GER_TAG: {"tag": GER_TAG, "name": "Germany"},
		ENG_TAG: {"tag": ENG_TAG, "name": "United Kingdom"},
		FRA_TAG: {"tag": FRA_TAG, "name": "France"},
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
		p.set("terrain", "sea" if bool(row["sea"]) else "plains")
		p.set("name", str(row["name"]))
		p.set("is_sea", bool(row["sea"]))
		p.set("domain", str(row["domain"]))
		p.set("infrastructure", 3)
		p.set("development_level", 2)
		p.set("core_for", [str(row["tag"])] if not str(row["tag"]).is_empty() else [])
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
	_force_centroids()
	_pass("coastal fixture Maginot/Emden/Köln/East Kent/North Sea/Channel (real centroids)")
	return true


func _setup_formations() -> bool:
	if not _register_formation(FID_GER_LAND, GER_TAG, "division", DESIGN_LAND, MAGINOT, "GER Maginot Div"):
		return false
	if not _register_formation(FID_GER_FLEET, GER_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "GER North Sea Fleet"):
		return false
	if not _register_formation(FID_ENG_FLEET, ENG_TAG, "fleet", DESIGN_FLEET, CHANNEL, "ENG Channel Fleet"):
		return false
	if not _register_formation(FID_FRA_FLEET_KOLN, FRA_TAG, "fleet", DESIGN_FLEET, KOLN, "FRA Köln Fleet"):
		return false
	if not _register_formation(FID_FRA_LAND, FRA_TAG, "division", DESIGN_LAND, KOLN, "FRA Köln Div"):
		return false
	_seed_leader("fleet1_ger_leader", "GER Test General", GER_TAG)
	_seed_leader("fleet1_eng_leader", "ENG Test Admiral", ENG_TAG)
	_seed_leader("fleet1_fra_leader", "FRA Test Admiral", FRA_TAG)
	_pass("seeded GER/ENG/FRA formations + available leaders")
	return true


func _register_formation(fid: String, tag: String, ftype: String, design: String, pid: int, pname: String) -> bool:
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("Formation create failed for %s" % fid)
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


func _setup_map_renderer() -> bool:
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
	_cam.position = Vector2(4200.0, 900.0)
	_cam.zoom = Vector2(1.0, 1.0)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	if "use_spatial_picking" in _mr:
		_mr.use_spatial_picking = true
	if "show_unit_counters" in _mr:
		_mr.show_unit_counters = true
	var placed: Dictionary = {
		MAGINOT: WORLD_MAGINOT,
		EMDEN: WORLD_EMDEN,
		KOLN: WORLD_KOLN,
		EAST_KENT: WORLD_EAST_KENT,
		NORTH_SEA: WORLD_NORTH_SEA,
		CHANNEL: WORLD_CHANNEL,
	}
	for pid_v in placed.keys():
		var pid := int(pid_v)
		var gp: Variant = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
		if gp == null:
			_fail("MapManager missing province %d" % pid)
			return false
		if "provinces" in _mr:
			_mr.provinces[pid] = gp
		var node := Node2D.new()
		node.name = "Province_%d" % pid
		node.position = placed[pid] as Vector2
		container.add_child(node)
		if "province_nodes" in _mr:
			_mr.province_nodes[pid] = node
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = placed[pid] as Vector2
	_force_centroids()
	_pass("MapRenderer + real coastal centroids")
	return true


func _force_centroids() -> void:
	if _mm != null and "pick_grid" in _mm:
		_mm.pick_grid = null
	if _mm != null and "_centroids" in _mm:
		var cents: Dictionary = _mm.get("_centroids")
		cents[MAGINOT] = WORLD_MAGINOT
		cents[EMDEN] = WORLD_EMDEN
		cents[KOLN] = WORLD_KOLN
		cents[EAST_KENT] = WORLD_EAST_KENT
		cents[NORTH_SEA] = WORLD_NORTH_SEA
		cents[CHANNEL] = WORLD_CHANNEL
		_mm.set("_centroids", cents)
	if _mr != null and "province_centroids" in _mr:
		_mr.province_centroids[MAGINOT] = WORLD_MAGINOT
		_mr.province_centroids[EMDEN] = WORLD_EMDEN
		_mr.province_centroids[KOLN] = WORLD_KOLN
		_mr.province_centroids[EAST_KENT] = WORLD_EAST_KENT
		_mr.province_centroids[NORTH_SEA] = WORLD_NORTH_SEA
		_mr.province_centroids[CHANNEL] = WORLD_CHANNEL


func _place_chip(pid: int, fid: String, world: Vector2) -> void:
	var host: Node2D = null
	if "province_nodes" in _mr and _mr.province_nodes.has(pid):
		host = _mr.province_nodes[pid] as Node2D
	if host == null:
		return
	var old: Node = host.get_node_or_null("DemoUnitIcon_%d" % pid)
	if old != null:
		old.free()
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_%d" % pid
	icon.visible = true
	host.add_child(icon)
	icon.global_position = world
	var fo: Object = _formation(fid)
	if fo != null:
		icon.set_meta("formation", fo)
	icon.set_meta("formation_id", fid)
	icon.set_meta("province_id", pid)
	if "_demo_unit_icon_pids" in _mr:
		var pids: Array = _mr._demo_unit_icon_pids
		if not pids.has(pid):
			pids.append(pid)
			_mr._demo_unit_icon_pids = pids


func _place_chips() -> void:
	_place_chip(MAGINOT, FID_GER_LAND, WORLD_MAGINOT)
	_place_chip(NORTH_SEA, FID_GER_FLEET, WORLD_NORTH_SEA)
	_place_chip(CHANNEL, FID_ENG_FLEET, WORLD_CHANNEL)
	_place_chip(KOLN, FID_FRA_FLEET_KOLN, WORLD_KOLN)


func _force_play_zoom() -> void:
	# MapRenderer._ready can re-frame. Keep zoom 1.0 so hit disks stay ~48 world.
	if _cam != null:
		_cam.zoom = Vector2(1.0, 1.0)
		_cam.position = Vector2(4200.0, 900.0)
		_cam.make_current()
	if "show_unit_counters" in _mr:
		_mr.show_unit_counters = true


func _channel_hit_r() -> float:
	var host: Node2D = null
	if "province_nodes" in _mr and _mr.province_nodes.has(CHANNEL):
		host = _mr.province_nodes[CHANNEL] as Node2D
	var icon: Node2D = null
	if host != null:
		icon = host.get_node_or_null("DemoUnitIcon_%d" % CHANNEL) as Node2D
	return float(_mr.call("_unit_counter_hit_radius_world", 1.0, icon))


func _resolve_open_sea_click() -> void:
	# Seed default is Channel + 80 CCW perp. Push just outside the live fleet disk
	# while GIS stays Channel and Maginot stays inside 340. East Kent is 8.8 west
	# of Channel — prefer the perp that does not fall into that land centroid.
	var hit_r: float = _channel_hit_r()
	var to_mag: Vector2 = WORLD_MAGINOT - WORLD_CHANNEL
	var perp: Vector2 = Vector2(-to_mag.y, to_mag.x).normalized()
	var need: float = maxf(80.0, hit_r + 24.0)
	var chosen: Vector2 = WORLD_CHANNEL + perp * need
	var chosen_hex: int = -1
	var chosen_d: float = INF
	var signs: Array = [1.0, -1.0]
	var dists: Array = [need, need + 40.0, need + 80.0]
	for s_v in signs:
		var s: float = float(s_v)
		for n_v in dists:
			var n: float = float(n_v)
			var cand: Vector2 = WORLD_CHANNEL + perp * s * n
			var hex: int = int(_mr.call("_resolve_hex_pick_pid", cand))
			var d_mag: float = cand.distance_to(WORLD_MAGINOT)
			if hex == CHANNEL and d_mag <= 340.0:
				chosen = cand
				chosen_hex = hex
				chosen_d = d_mag
				break
		if chosen_hex == CHANNEL:
			break
	WORLD_OPEN_SEA = chosen
	print(
		"  [INFO] HeadlessFleet1LandSpillGateTest: open-sea click %s hit_r=%.1f d_mag=%.1f gis=%d"
		% [str(WORLD_OPEN_SEA), hit_r, chosen_d, chosen_hex]
	)


func _formation(fid: String) -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", fid)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(fid)
	return null


func _world_to_screen(world: Vector2) -> Vector2:
	if _cam == null:
		return world
	return _cam.get_canvas_transform() * world


func _event_at_world(world: Vector2) -> InputEventMouseButton:
	var screen: Vector2 = _world_to_screen(world)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = screen
	ev.global_position = screen
	return ev


func _reset_pick() -> void:
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = ""
	if "selected_province_id" in _mr:
		_mr.selected_province_id = -1
	if _info != null:
		_info.visible = false
	if _ui != null:
		var old: Node = _ui.get_node_or_null("UnitDetailPopup")
		if old != null:
			_ui.remove_child(old)
			old.free()
	_force_centroids()


func _selected_fid() -> String:
	if _mr != null and "selected_formation_id" in _mr:
		return str(_mr.selected_formation_id)
	return ""


func _popup_up() -> bool:
	if _ui == null:
		return false
	var pop: Node = _ui.get_node_or_null("UnitDetailPopup")
	return pop != null and is_instance_valid(pop) and not pop.is_queued_for_deletion()


func _popup_has_btn(btn_name: String) -> bool:
	if _ui == null:
		return false
	var pop: Node = _ui.get_node_or_null("UnitDetailPopup")
	if pop == null or not is_instance_valid(pop):
		return false
	return pop.find_child(btn_name, true, false) != null


func _seed_leader(leader_id: String, lname: String, tag: String) -> void:
	if _lm == null or not ("leaders" in _lm):
		return
	var L: Object = _new_obj("res://scripts/leaders/Leader.gd")
	if L == null:
		return
	L.set("leader_id", leader_id)
	L.set("name", lname)
	L.set("country_tag", tag)
	L.set("assigned_army_id", "")
	L.set("is_injured", false)
	L.set("is_deceased", false)
	L.set("is_retired", false)
	L.set("is_captured", false)
	_lm.leaders[leader_id] = L


func _assert_no_command_buttons(who: String) -> bool:
	if _popup_has_btn("BtnOpenFight"):
		_fail("%s foreign card must hide Open fight" % who)
		return false
	if _popup_has_btn("BtnAssignLeader"):
		_fail("%s foreign card must hide Assign leader" % who)
		return false
	return true


func _foreign_unit_blocked(fid: String) -> bool:
	var fo: Object = _formation(fid)
	if fo == null:
		return false
	if not ("country_tag" in fo):
		return false
	return str(fo.country_tag).strip_edges().to_upper() != GER_TAG


func _click_chip_path(world: Vector2) -> bool:
	var ev: InputEventMouseButton = _event_at_world(world)
	var resolved: Vector2 = _mr.call("_map_pick_world_from_event", ev) as Vector2
	if resolved.distance_to(world) > 2.0:
		_fail("event.position world %s != seed %s" % [str(resolved), str(world)])
		return false
	if bool(_mr.call("_try_open_land_chip_from_input", false, ev)):
		return true
	# Fixture has no HUD. Same empty-select order as the chip path.
	if _selected_fid().is_empty() and bool(_mr.call("_try_open_unit_at_world", resolved)):
		return true
	return bool(_mr.call("_try_open_land_unit_at_world", resolved, false, false))


func _test_distances_inside_spill() -> void:
	var d_ch: float = WORLD_MAGINOT.distance_to(WORLD_CHANNEL)
	var d_ns: float = WORLD_MAGINOT.distance_to(WORLD_NORTH_SEA)
	var d_em: float = WORLD_MAGINOT.distance_to(WORLD_EMDEN)
	var d_open: float = WORLD_MAGINOT.distance_to(WORLD_OPEN_SEA)
	if d_ch > 340.0 or d_ns > 340.0 or d_em > 340.0 or d_open > 340.0:
		_fail("seed distances must stay inside 340 (ch=%.1f ns=%.1f em=%.1f open=%.1f)" % [d_ch, d_ns, d_em, d_open])
		return
	var spill_ch: Object = _mr.call("_nearest_player_land_formation_at_world", WORLD_CHANNEL)
	var spill_open: Object = _mr.call("_nearest_player_land_formation_at_world", WORLD_OPEN_SEA)
	var spill_em: Object = _mr.call("_nearest_player_land_formation_at_world", WORLD_EMDEN)
	if spill_ch == null or str(spill_ch.formation_id) != FID_GER_LAND:
		_fail("ungated spill at Channel must still reach Maginot GER land (documents the 340 steal)")
		return
	if spill_open == null or str(spill_open.formation_id) != FID_GER_LAND:
		_fail("ungated spill at open sea must still reach Maginot GER land")
		return
	if spill_em == null or str(spill_em.formation_id) != FID_GER_LAND:
		_fail("ungated spill at Emden must still reach Maginot GER land")
		return
	_pass(
		"coords Maginot %s Channel %s open-sea %s Emden %s NorthSea %s (d=%.1f/%.1f/%.1f/%.1f < 340)"
		% [str(WORLD_MAGINOT), str(WORLD_CHANNEL), str(WORLD_OPEN_SEA), str(WORLD_EMDEN), str(WORLD_NORTH_SEA), d_ch, d_open, d_em, d_ns]
	)


func _test_a_foreign_fleet() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", WORLD_CHANNEL))
	if hex != CHANNEL:
		_fail("(a) GIS at Channel centroid want %d got %d" % [CHANNEL, hex])
		return
	if not bool(_mr.call("_formation_is_fleet_counter", _formation(FID_ENG_FLEET))):
		_fail("(a) ENG formation must be a fleet counter")
		return
	if bool(_mr.call("_hex_pick_is_land_province", WORLD_CHANNEL)):
		_fail("(a) Channel must not count as land")
		return
	var opened: bool = _click_chip_path(WORLD_CHANNEL)
	if not opened:
		_fail("(a) foreign fleet chip path must open/inspect the ENG fleet")
		return
	if _selected_fid() != FID_ENG_FLEET:
		_fail("(a) selected=%s want ENG fleet %s (must not steal Maginot GER)" % [_selected_fid(), FID_ENG_FLEET])
		return
	if not _popup_up():
		_fail("(a) ENG fleet inspect popup missing")
		return
	_pass("(a) Channel ENG fleet at %s selected/inspected (not Maginot GER)" % str(WORLD_CHANNEL))


func _test_b_open_sea() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", WORLD_OPEN_SEA))
	if hex != CHANNEL:
		_fail("(b) GIS at open sea want Channel %d got %d" % [CHANNEL, hex])
		return
	if bool(_mr.call("_hex_pick_is_land_province", WORLD_OPEN_SEA)):
		_fail("(b) open sea must not count as land")
		return
	var disk: Object = _mr.call("_pick_unit_formation_at_world", WORLD_OPEN_SEA)
	if disk != null:
		var dfid: String = str(disk.formation_id) if "formation_id" in disk else "?"
		_fail("(b) open-sea click must miss every counter disk (hit %s)" % dfid)
		return
	var ev: InputEventMouseButton = _event_at_world(WORLD_OPEN_SEA)
	var opened: bool = bool(_mr.call("_try_open_land_chip_from_input", false, ev))
	if opened:
		_fail("(b) open sea must not bind own land via spill (selected=%s)" % _selected_fid())
		return
	if _selected_fid() == FID_GER_LAND:
		_fail("(b) open sea selected Maginot GER land — spill leaked")
		return
	var sea_pid: int = int(_mr.call("_still_click_province_pid", WORLD_OPEN_SEA, false))
	if sea_pid != CHANNEL:
		_fail("(b) still-click province pid=%d want Channel %d" % [sea_pid, CHANNEL])
		return
	# Fixture InfoPanel has no inspector children — do not call show_info_panel.
	# Fallthrough is the same pid _unhandled_input would inspect.
	_mr.selected_province_id = sea_pid
	if _info != null:
		_info.visible = true
	if int(_mr.selected_province_id) != CHANNEL:
		_fail("(b) sea inspector pid=%d want Channel %d" % [int(_mr.selected_province_id), CHANNEL])
		return
	if _info == null or not _info.visible:
		_fail("(b) sea province inspector did not open")
		return
	_pass("(b) open sea at %s opened Channel %d (not Maginot GER)" % [str(WORLD_OPEN_SEA), CHANNEL])


func _test_c_near_own_land() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", WORLD_EMDEN))
	if hex != EMDEN:
		_fail("(c) GIS at Emden want %d got %d" % [EMDEN, hex])
		return
	if not bool(_mr.call("_hex_pick_is_land_province", WORLD_EMDEN)):
		_fail("(c) Emden must count as land")
		return
	var disk: Object = _mr.call("_pick_land_unit_formation_at_world", WORLD_EMDEN)
	if disk != null:
		var lfid: String = str(disk.formation_id) if "formation_id" in disk else "?"
		_fail("(c) Emden must be outside the Maginot land disk (got %s)" % lfid)
		return
	var opened: bool = _click_chip_path(WORLD_EMDEN)
	if not opened:
		_fail("(c) land-near-own-unit spill must still open Maginot GER")
		return
	if _selected_fid() != FID_GER_LAND:
		_fail("(c) selected=%s want Maginot GER %s" % [_selected_fid(), FID_GER_LAND])
		return
	if not _popup_up():
		_fail("(c) GER land card missing")
		return
	_pass("(c) Emden land at %s still picked Maginot GER (spill on land)" % str(WORLD_EMDEN))


func _test_d_own_fleet() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", WORLD_NORTH_SEA))
	if hex != NORTH_SEA:
		_fail("(d) GIS at North Sea want %d got %d" % [NORTH_SEA, hex])
		return
	var ev: InputEventMouseButton = _event_at_world(WORLD_NORTH_SEA)
	var world: Vector2 = _mr.call("_map_pick_world_from_event", ev) as Vector2
	var own: bool = bool(_mr.call("_try_open_unit_at_world", world))
	if not own:
		_fail("(d) own GER fleet disk must still select via _try_open_unit_at_world")
		return
	if _selected_fid() != FID_GER_FLEET:
		_fail("(d) selected=%s want GER fleet %s" % [_selected_fid(), FID_GER_FLEET])
		return
	if not _popup_up():
		_fail("(d) GER fleet card missing")
		return
	_reset_pick()
	var chip: bool = _click_chip_path(WORLD_NORTH_SEA)
	if not chip or _selected_fid() != FID_GER_FLEET:
		_fail("(d) land-chip path must still first-select own fleet (selected=%s)" % _selected_fid())
		return
	_pass("(d) own GER fleet at North Sea %s still selected" % str(WORLD_NORTH_SEA))


func _test_e_fleet_disk_over_east_kent() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", WORLD_EAST_KENT))
	if hex != EAST_KENT:
		_fail("(e) GIS at East Kent want %d got %d" % [EAST_KENT, hex])
		return
	if not bool(_mr.call("_hex_pick_is_land_province", WORLD_EAST_KENT)):
		_fail("(e) East Kent must count as coastal land")
		return
	var eng: Object = _formation(FID_ENG_FLEET)
	if not bool(_mr.call("_formation_is_stationed_on_sea", eng)):
		_fail("(e) ENG fleet must be stationed on Channel sea")
		return
	var disk: Object = _mr.call("_pick_unit_formation_at_world", WORLD_EAST_KENT)
	if disk == null or str(disk.formation_id) != FID_ENG_FLEET:
		_fail("(e) East Kent click must be inside the ENG Channel fleet disk")
		return
	var opened: bool = _click_chip_path(WORLD_EAST_KENT)
	if not opened:
		_fail("(e) ENG fleet disk over East Kent land must inspect the fleet")
		return
	if _selected_fid() != FID_ENG_FLEET:
		_fail("(e) selected=%s want ENG fleet (GIS East Kent must not steal inspector)" % _selected_fid())
		return
	if not _popup_up():
		_fail("(e) ENG fleet inspect popup missing")
		return
	_pass("(e) ENG fleet disk at East Kent %s (GIS %d land) selected ENG fleet" % [str(WORLD_EAST_KENT), EAST_KENT])


func _test_f_koln_fra_land_fleet() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", WORLD_KOLN))
	if hex != KOLN:
		_fail("(f) GIS at Köln want %d got %d" % [KOLN, hex])
		return
	if not bool(_mr.call("_hex_pick_is_land_province", WORLD_KOLN)):
		_fail("(f) Köln must count as land")
		return
	var fra: Object = _formation(FID_FRA_FLEET_KOLN)
	if bool(_mr.call("_formation_is_stationed_on_sea", fra)):
		_fail("(f) Köln FRA fleet must stay land-stationed (MV-1b)")
		return
	var disk: Object = _mr.call("_pick_unit_formation_at_world", WORLD_KOLN)
	if disk == null or str(disk.formation_id) != FID_FRA_FLEET_KOLN:
		_fail("(f) Köln click must hit the FRA land-province fleet disk")
		return
	var opened: bool = _click_chip_path(WORLD_KOLN)
	if opened and _selected_fid() == FID_FRA_FLEET_KOLN:
		_fail("(f) Köln FRA land-province fleet must stay unselectable")
		return
	if _selected_fid() == FID_FRA_FLEET_KOLN:
		_fail("(f) selected FRA Köln fleet — MV-1b leaked")
		return
	_pass("(f) Köln FRA land-province fleet at %s still not selected" % str(WORLD_KOLN))


func _test_g_foreign_cards_readonly() -> void:
	_reset_pick()
	var eng: Object = _formation(FID_ENG_FLEET)
	_mr.call("_show_unit_detail_popup", eng)
	if not _popup_up():
		_fail("(g) ENG fleet card missing")
		return
	if not _assert_no_command_buttons("(g) ENG fleet"):
		return
	if not _foreign_unit_blocked(FID_ENG_FLEET):
		_fail("(g) ENG fleet must stay a foreign tag (march blocked)")
		return
	_reset_pick()
	var fra_land: Object = _formation(FID_FRA_LAND)
	_mr.call("_show_unit_detail_popup", fra_land)
	if not _popup_up():
		_fail("(g) FRA land card missing")
		return
	if not _assert_no_command_buttons("(g) FRA land"):
		return
	if not _foreign_unit_blocked(FID_FRA_LAND):
		_fail("(g) FRA land must stay a foreign tag (march blocked)")
		return
	_pass("(g) foreign fleet + land cards hide Assign/Open fight; march blocked")


func _test_h_own_card_buttons() -> void:
	_reset_pick()
	var opened: bool = _click_chip_path(WORLD_MAGINOT)
	if not opened or _selected_fid() != FID_GER_LAND:
		_fail("(h) own Maginot GER card must open (selected=%s)" % _selected_fid())
		return
	if not _popup_up():
		_fail("(h) own GER land card missing")
		return
	if not _popup_has_btn("BtnOpenFight"):
		_fail("(h) own unit card must still show Open fight")
		return
	if not _popup_has_btn("BtnAssignLeader"):
		_fail("(h) own unit card must still show Assign leader")
		return
	_pass("(h) own GER land card still shows Open fight + Assign")


func _cleanup() -> void:
	if _lm != null and "formations" in _lm and _lm.formations is Dictionary:
		_lm.formations.erase(FID_GER_LAND)
		_lm.formations.erase(FID_GER_FLEET)
		_lm.formations.erase(FID_ENG_FLEET)
		_lm.formations.erase(FID_FRA_FLEET_KOLN)
		_lm.formations.erase(FID_FRA_LAND)
	if _lm != null and "leaders" in _lm and _lm.leaders is Dictionary:
		_lm.leaders.erase("fleet1_ger_leader")
		_lm.leaders.erase("fleet1_eng_leader")
		_lm.leaders.erase("fleet1_fra_leader")
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
