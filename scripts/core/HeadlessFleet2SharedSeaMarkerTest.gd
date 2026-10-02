extends SceneTree

## FLEET-2: one clickable marker per nation when several fleets share a
## sea province. Hit disks match the drawn plates and must not overlap.
## Single-nation sea (ENG Channel) and FLEET-1 / MV-1b rules stay as today.
## Headless / xvfb are NOT live Play.
##
## Real world_accurate label_anchor centroids (provinces_geometry.json):
##   710173 Maginot GER land               (4283.279411, 1010.266854)
##   710417 Köln (GER land; MV-1b FRA)     (4254.322147,  944.095861)
##   950000 North Sea Zone (GER+FRA fleets)(4164.266667,  773.688889)
##   950001 English Channel (ENG only)     (4128.701206,  938.217996)
## Stacked North Sea disks are offset from the chip base
##   centroid + (0, -12)  →  (4164.266667, 761.688889)
## by `_sea_nation_fleet_stack_offsets` (player-first, then alpha).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFleet2SharedSeaMarkerTest.gd
##   tools/eoa_fleet2_guard.sh

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const GER_TAG := "GER"
const ENG_TAG := "ENG"
const FRA_TAG := "FRA"
const MAGINOT := 710173
const KOLN := 710417
const NORTH_SEA := 950000
const CHANNEL := 950001
const FID_GER_LAND := "fleet2_ger_maginot"
const FID_GER_FLEET := "fleet2_ger_north_sea"
const FID_FRA_FLEET_SEA := "fleet2_fra_north_sea"
const FID_ENG_FLEET := "fleet2_eng_channel"
const FID_FRA_FLEET_KOLN := "fleet2_fra_koln"
const DESIGN_LAND := "infantry_1936"
const DESIGN_FLEET := "king_george_v_class_bb"
const WORLD_MAGINOT := Vector2(4283.279410731325, 1010.2668539708038)
const WORLD_KOLN := Vector2(4254.322147319904, 944.0958606451493)
const WORLD_NORTH_SEA := Vector2(4164.266666666666, 773.6888888888889)
const WORLD_CHANNEL := Vector2(4128.701206024651, 938.2179956383225)
const FLUSH_FRAMES := 4


var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _cam: Camera2D = null
var _info: Panel = null
var _ger_ns: Vector2 = Vector2.ZERO
var _fra_ns: Vector2 = Vector2.ZERO
var _eng_ch: Vector2 = Vector2.ZERO
var _ger_r: float = 0.0
var _fra_r: float = 0.0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessFleet2SharedSeaMarkerTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFleet2SharedSeaMarkerTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFleet2SharedSeaMarkerTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFleet2SharedSeaMarkerTest: ", msg)


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
	if not _setup_fixture():
		return
	if not _setup_formations():
		return
	if not _setup_map_renderer():
		return
	_force_play_zoom()
	_isolate_fixture_formations()
	_rebuild_icons()
	await _flush()
	_force_play_zoom()
	_sync_offsets()
	await _flush()
	if not _resolve_marker_coords():
		return
	_test_a_own_north_sea()
	_test_b_foreign_north_sea()
	_test_c_disks_do_not_overlap()
	_test_d_single_nation_channel()
	_test_e_koln_fra_land_fleet()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	if "func _iter_demo_unit_icons_at_pid" not in ren:
		_fail("must iterate every DemoUnitIcon_* on a province")
		return
	if "func _sea_nation_fleet_stack_offsets" not in ren:
		_fail("stacked sea-nation offset helper missing")
		return
	if "func _sea_nation_fleet_disk_radius_world" not in ren:
		_fail("stacked sea-nation disk radius helper missing")
		return
	if "func _place_sea_nation_fleet_counter" not in ren:
		_fail("per-nation sea fleet placer missing")
		return
	if "sea_nation_disk" not in ren:
		_fail("stacked sea markers must tag sea_nation_disk")
		return
	if "_sea_nations" not in ren:
		_fail("icon index must collect per-nation sea fleets")
		return
	var pick_fn := _slice_func(ren, "_pick_unit_formation_at_world")
	if "_iter_demo_unit_icons_at_pid" not in pick_fn:
		_fail("pick must walk every DemoUnitIcon_* (not only DemoUnitIcon_{pid})")
		return
	if "_demo_unit_icon_hit_radius_world" not in pick_fn:
		_fail("pick hit radius must match the drawn disk")
		return
	var land_fn := _slice_func(ren, "_try_open_land_unit_at_world")
	if "fo_any == null" not in land_fn:
		_fail("FLEET-1 spill must still require no direct counter hit")
		return
	if "_hex_pick_is_land_province(world_pos)" not in land_fn:
		_fail("FLEET-1 spill must still require a land hex")
		return
	if "_formation_is_stationed_on_sea(fo_any)" not in land_fn:
		_fail("FLEET-1 foreign-fleet inspect must still key on the fleet location pid")
		return
	if "not _hex_pick_is_land_province(world_pos)" in land_fn:
		_fail("foreign-fleet inspect must not use GIS-under-cursor as the sea gate")
		return
	var open_unit := _slice_func(ren, "_try_open_unit_at_world")
	if "player_only" not in open_unit or "_formation_is_player_tag" not in open_unit:
		_fail("_try_open_unit_at_world must stay player-tag (MV-1b)")
		return
	var rebuild := _slice_func(ren, "_rebuild_demo_unit_icons")
	if "_demo_icon_jobs_for_province" not in rebuild:
		_fail("rebuild must emit per-nation jobs for shared sea fleets")
		return
	if "func _province_id_is_sea" not in ren:
		_fail("_province_id_is_sea helper missing")
		return
	_pass("FLEET-2 source needles (FLEET-1 / MV-1b unedited)")


func _setup_fixture() -> bool:
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	var rows: Array = [
		{"id": MAGINOT, "tag": GER_TAG, "name": "Baden-Baden, Stadtkreis", "c": WORLD_MAGINOT, "sea": false, "domain": "land"},
		{"id": KOLN, "tag": GER_TAG, "name": "Köln, Kreisfreie Stadt", "c": WORLD_KOLN, "sea": false, "domain": "land"},
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
	_pass("fixture Maginot/Köln/North Sea/Channel (real centroids)")
	return true


func _setup_formations() -> bool:
	if not _register_formation(FID_GER_LAND, GER_TAG, "division", DESIGN_LAND, MAGINOT, "GER Maginot Div"):
		return false
	if not _register_formation(FID_GER_FLEET, GER_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "GER North Sea Fleet"):
		return false
	if not _register_formation(FID_FRA_FLEET_SEA, FRA_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "FRA North Sea Fleet"):
		return false
	if not _register_formation(FID_ENG_FLEET, ENG_TAG, "fleet", DESIGN_FLEET, CHANNEL, "ENG Channel Fleet"):
		return false
	if not _register_formation(FID_FRA_FLEET_KOLN, FRA_TAG, "fleet", DESIGN_FLEET, KOLN, "FRA Köln Fleet"):
		return false
	_isolate_fixture_formations()
	_pass("seeded GER+FRA North Sea fleets, ENG Channel, Köln FRA land fleet")
	return true


func _isolate_fixture_formations() -> void:
	# Live 1936 OOB also stations GER land on Köln / Maginot. First-wins would
	# hide the FRA land-fleet disk that MV-1b / (e) must still hit-and-refuse.
	var keep: Dictionary = {
		FID_GER_LAND: true,
		FID_GER_FLEET: true,
		FID_FRA_FLEET_SEA: true,
		FID_ENG_FLEET: true,
		FID_FRA_FLEET_KOLN: true,
	}
	var pids: Dictionary = {MAGINOT: true, KOLN: true, NORTH_SEA: true, CHANNEL: true}
	if _lm == null or not ("formations" in _lm) or not (_lm.formations is Dictionary):
		return
	for fid_v in _lm.formations.keys():
		var fid := str(fid_v)
		if keep.has(fid):
			continue
		var fo: Object = _lm.formations[fid_v]
		if fo == null or not ("stationed_province_id" in fo):
			continue
		var sid := int(fo.stationed_province_id)
		if pids.has(sid):
			fo.stationed_province_id = -1


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
		KOLN: WORLD_KOLN,
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
		# Production: province nodes sit at origin; chips use centroid.
		node.position = Vector2.ZERO
		container.add_child(node)
		if "province_nodes" in _mr:
			_mr.province_nodes[pid] = node
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = placed[pid] as Vector2
	_force_centroids()
	_pass("MapRenderer + real centroids (nodes at origin)")
	return true


func _force_centroids() -> void:
	if _mm != null and "pick_grid" in _mm:
		_mm.pick_grid = null
	if _mm != null and "_centroids" in _mm:
		var cents: Dictionary = _mm.get("_centroids")
		cents[MAGINOT] = WORLD_MAGINOT
		cents[KOLN] = WORLD_KOLN
		cents[NORTH_SEA] = WORLD_NORTH_SEA
		cents[CHANNEL] = WORLD_CHANNEL
		_mm.set("_centroids", cents)
	if _mr != null and "province_centroids" in _mr:
		_mr.province_centroids[MAGINOT] = WORLD_MAGINOT
		_mr.province_centroids[KOLN] = WORLD_KOLN
		_mr.province_centroids[NORTH_SEA] = WORLD_NORTH_SEA
		_mr.province_centroids[CHANNEL] = WORLD_CHANNEL


func _force_play_zoom() -> void:
	if _cam != null:
		_cam.zoom = Vector2(1.0, 1.0)
		_cam.position = Vector2(4200.0, 900.0)
		_cam.make_current()
	if "show_unit_counters" in _mr:
		_mr.show_unit_counters = true


func _rebuild_icons() -> void:
	if _mr != null and _mr.has_method("_update_unit_icons_for_test"):
		_mr.call("_update_unit_icons_for_test")
	elif _mr != null and _mr.has_method("_rebuild_demo_unit_icons"):
		_mr.call("_rebuild_demo_unit_icons", {})


func _sync_offsets() -> void:
	if _mr != null and _mr.has_method("_sync_unit_counter_scales"):
		_mr.call("_sync_unit_counter_scales", 1.0)
	if _mr != null and _mr.has_method("_sync_sea_nation_fleet_offsets"):
		_mr.call("_sync_sea_nation_fleet_offsets", 1.0)


func _icon_for_fid(pid: int, fid: String) -> Node2D:
	var host: Node2D = null
	if "province_nodes" in _mr and _mr.province_nodes.has(pid):
		host = _mr.province_nodes[pid] as Node2D
	if host == null:
		return null
	for c in host.get_children():
		if not (c is Node2D):
			continue
		if not str(c.name).begins_with("DemoUnitIcon_"):
			continue
		if str(c.get_meta("formation_id", "")) == fid:
			return c as Node2D
	return null


func _icon_world(icon: Node2D, pid: int) -> Vector2:
	if icon == null:
		return Vector2.ZERO
	if _mr != null and _mr.has_method("_demo_unit_icon_world_pos"):
		return _mr.call("_demo_unit_icon_world_pos", icon, pid) as Vector2
	return icon.global_position


func _icon_hit_r(icon: Node2D) -> float:
	if _mr == null:
		return 20.0
	if _mr.has_method("_demo_unit_icon_hit_radius_world"):
		return float(_mr.call("_demo_unit_icon_hit_radius_world", 1.0, icon))
	return float(_mr.call("_unit_counter_hit_radius_world", 1.0, icon))


func _resolve_marker_coords() -> bool:
	var ger_icon: Node2D = _icon_for_fid(NORTH_SEA, FID_GER_FLEET)
	var fra_icon: Node2D = _icon_for_fid(NORTH_SEA, FID_FRA_FLEET_SEA)
	var eng_icon: Node2D = _icon_for_fid(CHANNEL, FID_ENG_FLEET)
	if ger_icon == null or fra_icon == null:
		_fail("North Sea must draw one DemoUnitIcon per nation (GER + FRA)")
		return false
	if eng_icon == null:
		_fail("Channel ENG single-nation marker missing")
		return false
	if not bool(ger_icon.get_meta("sea_nation_disk", false)) or not bool(fra_icon.get_meta("sea_nation_disk", false)):
		_fail("shared-sea markers must set sea_nation_disk")
		return false
	if bool(eng_icon.get_meta("sea_nation_disk", false)):
		_fail("single-nation Channel marker must stay a normal DemoUnitIcon_{pid}")
		return false
	if eng_icon.name != "DemoUnitIcon_%d" % CHANNEL:
		_fail("Channel icon name=%s want DemoUnitIcon_%d" % [eng_icon.name, CHANNEL])
		return false
	_ger_ns = _icon_world(ger_icon, NORTH_SEA)
	_fra_ns = _icon_world(fra_icon, NORTH_SEA)
	_eng_ch = _icon_world(eng_icon, CHANNEL)
	_ger_r = _icon_hit_r(ger_icon)
	_fra_r = _icon_hit_r(fra_icon)
	var base: Vector2 = WORLD_NORTH_SEA + Vector2(0, -12)
	var ch_base: Vector2 = WORLD_CHANNEL + Vector2(0, -12)
	print(
		"  [INFO] HeadlessFleet2SharedSeaMarkerTest: GER disk %s r=%.1f FRA disk %s r=%.1f Channel %s (base NS %s CH %s)"
		% [str(_ger_ns), _ger_r, str(_fra_ns), _fra_r, str(_eng_ch), str(base), str(ch_base)]
	)
	if _ger_ns.distance_to(_fra_ns) < 1.0:
		_fail("GER and FRA North Sea markers must be offset (same centre)")
		return false
	if _eng_ch.distance_to(ch_base) > 2.0:
		_fail("single-nation Channel chip moved: %s want %s" % [str(_eng_ch), str(ch_base)])
		return false
	_pass(
		"coords GER %s r=%.1f FRA %s r=%.1f Channel %s"
		% [str(_ger_ns), _ger_r, str(_fra_ns), _fra_r, str(_eng_ch)]
	)
	return true


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


func _assert_no_command_buttons(who: String) -> bool:
	if _popup_has_btn("BtnOpenFight"):
		_fail("%s foreign card must hide Open fight" % who)
		return false
	if _popup_has_btn("BtnAssignLeader"):
		_fail("%s foreign card must hide Assign leader" % who)
		return false
	return true


func _click_chip_path(world: Vector2) -> bool:
	var ev: InputEventMouseButton = _event_at_world(world)
	var resolved: Vector2 = _mr.call("_map_pick_world_from_event", ev) as Vector2
	if resolved.distance_to(world) > 2.0:
		_fail("event.position world %s != seed %s" % [str(resolved), str(world)])
		return false
	if bool(_mr.call("_try_open_land_chip_from_input", false, ev)):
		return true
	if _selected_fid().is_empty() and bool(_mr.call("_try_open_unit_at_world", resolved)):
		return true
	return bool(_mr.call("_try_open_land_unit_at_world", resolved, false, false))


func _test_a_own_north_sea() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", _ger_ns))
	if hex != NORTH_SEA:
		_fail("(a) GIS at GER disk want North Sea %d got %d" % [NORTH_SEA, hex])
		return
	var ev: InputEventMouseButton = _event_at_world(_ger_ns)
	var world: Vector2 = _mr.call("_map_pick_world_from_event", ev) as Vector2
	var own: bool = bool(_mr.call("_try_open_unit_at_world", world))
	if not own:
		_fail("(a) own GER North Sea disk must select via _try_open_unit_at_world")
		return
	if _selected_fid() != FID_GER_FLEET:
		_fail("(a) selected=%s want GER fleet %s" % [_selected_fid(), FID_GER_FLEET])
		return
	if not _popup_up():
		_fail("(a) GER fleet own card missing")
		return
	if not _popup_has_btn("BtnOpenFight"):
		_fail("(a) own GER fleet card must show Open fight")
		return
	if not _popup_has_btn("BtnAssignLeader"):
		_fail("(a) own GER fleet card must show Assign leader")
		return
	_reset_pick()
	var chip: bool = _click_chip_path(_ger_ns)
	if not chip or _selected_fid() != FID_GER_FLEET:
		_fail("(a) land-chip path must select own GER fleet (selected=%s)" % _selected_fid())
		return
	_pass("(a) GER North Sea disk %s selected fleet %s with own card" % [str(_ger_ns), FID_GER_FLEET])


func _test_b_foreign_north_sea() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", _fra_ns))
	if hex != NORTH_SEA:
		_fail("(b) GIS at FRA disk want North Sea %d got %d" % [NORTH_SEA, hex])
		return
	var disk: Object = _mr.call("_pick_unit_formation_at_world", _fra_ns)
	if disk == null or str(disk.formation_id) != FID_FRA_FLEET_SEA:
		var got := str(disk.formation_id) if disk != null and "formation_id" in disk else "?"
		_fail("(b) FRA disk centre must pick FRA fleet (got %s)" % got)
		return
	var opened: bool = _click_chip_path(_fra_ns)
	if not opened:
		_fail("(b) FRA North Sea disk must inspect the foreign fleet")
		return
	if _selected_fid() != FID_FRA_FLEET_SEA:
		_fail("(b) selected=%s want FRA fleet %s" % [_selected_fid(), FID_FRA_FLEET_SEA])
		return
	if not _popup_up():
		_fail("(b) FRA fleet inspect popup missing")
		return
	if not _assert_no_command_buttons("(b) FRA North Sea"):
		return
	_pass("(b) FRA North Sea disk %s selected fleet %s with read-only card" % [str(_fra_ns), FID_FRA_FLEET_SEA])


func _test_c_disks_do_not_overlap() -> void:
	var dist: float = _ger_ns.distance_to(_fra_ns)
	var need: float = _ger_r + _fra_r
	if dist <= need:
		_fail("(c) GER/FRA hit disks overlap (dist=%.1f r_sum=%.1f)" % [dist, need])
		return
	var ger_hit: Object = _mr.call("_pick_unit_formation_at_world", _ger_ns)
	var fra_hit: Object = _mr.call("_pick_unit_formation_at_world", _fra_ns)
	if ger_hit == null or str(ger_hit.formation_id) != FID_GER_FLEET:
		_fail("(c) GER disk centre must pick GER fleet")
		return
	if fra_hit == null or str(fra_hit.formation_id) != FID_FRA_FLEET_SEA:
		_fail("(c) FRA disk centre must pick FRA fleet")
		return
	var ger_r2: float = _ger_r * _ger_r
	var fra_r2: float = _fra_r * _fra_r
	if _ger_ns.distance_squared_to(_fra_ns) <= ger_r2:
		_fail("(c) FRA centre sits inside the GER hit disk")
		return
	if _fra_ns.distance_squared_to(_ger_ns) <= fra_r2:
		_fail("(c) GER centre sits inside the FRA hit disk")
		return
	_pass("(c) disks do not overlap (dist=%.1f > r_sum=%.1f); each centre picks its fleet" % [dist, need])


func _test_d_single_nation_channel() -> void:
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", WORLD_CHANNEL))
	if hex != CHANNEL:
		_fail("(d) GIS at Channel centroid want %d got %d" % [CHANNEL, hex])
		return
	var opened: bool = _click_chip_path(WORLD_CHANNEL)
	if not opened:
		_fail("(d) Channel centroid must still select the ENG fleet")
		return
	if _selected_fid() != FID_ENG_FLEET:
		_fail("(d) selected=%s want ENG Channel fleet %s" % [_selected_fid(), FID_ENG_FLEET])
		return
	if not _popup_up():
		_fail("(d) ENG Channel inspect popup missing")
		return
	if not _assert_no_command_buttons("(d) ENG Channel"):
		return
	_reset_pick()
	var mid: bool = _click_chip_path(_eng_ch)
	if not mid or _selected_fid() != FID_ENG_FLEET:
		_fail("(d) Channel chip centre %s must still select ENG" % str(_eng_ch))
		return
	_pass("(d) single-nation Channel ENG at %s behaves as before" % str(_eng_ch))


func _place_land_chip_at(pid: int, fid: String, world: Vector2) -> Node2D:
	# FLEET-1 style: bare DemoUnitIcon_{pid} at the seed so the 48-world floor
	# hits the centroid. Rebuild chrome on Maginot would otherwise steal Köln
	# via player-tag preference (AABB > 60).
	var host: Node2D = null
	if "province_nodes" in _mr and _mr.province_nodes.has(pid):
		host = _mr.province_nodes[pid] as Node2D
	if host == null:
		return null
	for c in host.get_children():
		if c is Node2D and str(c.name).begins_with("DemoUnitIcon_"):
			host.remove_child(c)
			c.free()
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
	icon.set_meta("sea_nation_disk", false)
	if "_demo_unit_icon_pids" in _mr:
		var pids: Array = _mr._demo_unit_icon_pids
		if not pids.has(pid):
			pids.append(pid)
			_mr._demo_unit_icon_pids = pids
	return icon


func _test_e_koln_fra_land_fleet() -> void:
	_reset_pick()
	# Hide Maginot chrome so its Home-band AABB cannot player-prefer steal Köln.
	if "province_nodes" in _mr and _mr.province_nodes.has(MAGINOT):
		var mag_host: Node2D = _mr.province_nodes[MAGINOT] as Node2D
		if mag_host != null:
			for c in mag_host.get_children():
				if c is Node2D and str(c.name).begins_with("DemoUnitIcon_"):
					(c as Node2D).visible = false
	var koln_icon: Node2D = _place_land_chip_at(KOLN, FID_FRA_FLEET_KOLN, WORLD_KOLN)
	if koln_icon == null:
		_fail("(e) Köln FRA land-fleet DemoUnitIcon missing")
		return
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", WORLD_KOLN))
	if hex != KOLN:
		_fail("(e) GIS at Köln want %d got %d" % [KOLN, hex])
		return
	if not bool(_mr.call("_hex_pick_is_land_province", WORLD_KOLN)):
		_fail("(e) Köln must count as land")
		return
	var fra: Object = _formation(FID_FRA_FLEET_KOLN)
	if bool(_mr.call("_formation_is_stationed_on_sea", fra)):
		_fail("(e) Köln FRA fleet must stay land-stationed (MV-1b)")
		return
	if bool(koln_icon.get_meta("sea_nation_disk", false)):
		_fail("(e) Köln land-fleet must not be a sea_nation_disk")
		return
	var disk: Object = _mr.call("_pick_unit_formation_at_world", WORLD_KOLN)
	if disk == null or str(disk.formation_id) != FID_FRA_FLEET_KOLN:
		var got := str(disk.formation_id) if disk != null and "formation_id" in disk else "?"
		_fail("(e) Köln click must still hit the FRA land-province fleet disk (got %s)" % got)
		return
	var opened: bool = _click_chip_path(WORLD_KOLN)
	if opened and _selected_fid() == FID_FRA_FLEET_KOLN:
		_fail("(e) Köln FRA land-province fleet must stay unselectable")
		return
	if _selected_fid() == FID_FRA_FLEET_KOLN:
		_fail("(e) selected FRA Köln fleet — MV-1b leaked")
		return
	_pass("(e) Köln FRA land-province fleet at %s still not selected" % str(WORLD_KOLN))


func _cleanup() -> void:
	if _lm != null and "formations" in _lm and _lm.formations is Dictionary:
		_lm.formations.erase(FID_GER_LAND)
		_lm.formations.erase(FID_GER_FLEET)
		_lm.formations.erase(FID_FRA_FLEET_SEA)
		_lm.formations.erase(FID_ENG_FLEET)
		_lm.formations.erase(FID_FRA_FLEET_KOLN)
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
