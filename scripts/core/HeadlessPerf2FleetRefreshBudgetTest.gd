extends SceneTree

## PERF-2: shared-sea fleet offset cache + wheel/idle refresh budgets.
## (a) Channel / North Sea stack offsets are identical with and without cache.
## (b) Every-6th-frame detail refresh and one wheel-notch light refresh stay
##     under a generous usec budget (headroom for llvmpipe / CI jitter).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessPerf2FleetRefreshBudgetTest.gd
##
## Headless ≠ live Play. Does not touch FacilityIconLayer / MapZoomLOD / pick.

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const GER_TAG := "GER"
const ENG_TAG := "ENG"
const FRA_TAG := "FRA"
const ITA_TAG := "ITA"
const POL_TAG := "POL"
const USA_TAG := "USA"
const JAP_TAG := "JAP"
const SOV_TAG := "SOV"
const MAGINOT := 710173
const KOLN := 710417
const EAST_KENT := 711453
const NORTH_SEA := 950000
const CHANNEL := 950001
const DESIGN_LAND := "infantry_1936"
const DESIGN_FLEET := "king_george_v_class_bb"
const WORLD_MAGINOT := Vector2(4283.279410731325, 1010.2668539708038)
const WORLD_KOLN := Vector2(4254.322147319904, 944.0958606451493)
const WORLD_EAST_KENT := Vector2(4119.875714645911, 938.0282873606084)
const WORLD_NORTH_SEA := Vector2(4164.266666666666, 773.6888888888889)
const WORLD_CHANNEL := Vector2(4128.701206024651, 938.2179956383225)
const LIVE_RENDER_EAST_KENT := Vector2(7119.145, 1620.913)
const LIVE_RENDER_NORTH_SEA := Vector2(7195.9, 1336.9)
const LIVE_RENDER_CHANNEL := Vector2(7134.5, 1622.3)
const FLUSH_FRAMES := 3
## Cached idle refresh was ~54 ms on the software-GL play box; 80 ms leaves headroom.
const DETAIL_REFRESH_BUDGET_USEC := 80000
## One notch after px is stable; live was 500–1000 ms when doubled + star overrides.
const WHEEL_REFRESH_BUDGET_USEC := 100000
const OFFSET_CACHE_BUDGET_USEC := 8000
const OFFSET_EPS := 0.05

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _cam: Camera2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf2FleetRefreshBudgetTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf2FleetRefreshBudgetTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf2FleetRefreshBudgetTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf2FleetRefreshBudgetTest: ", msg)


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
	_force_play_zoom(1.0)
	_isolate_fixture_formations()
	_rebuild_icons()
	await _flush()
	_force_play_zoom(1.0)
	_sync_offsets(1.0)
	await _flush()
	_test_a_offsets_identical_with_and_without_cache()
	_test_a_plate_world_positions_match()
	_attach_fat_sea_rings()
	_plant_capital_stars(37)
	_test_b_detail_and_wheel_budgets()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	if "var _sea_fleet_offset_cache" not in ren:
		_fail("fleet offset cache member missing")
		return
	if "func _invalidate_sea_fleet_offset_cache" not in ren:
		_fail("fleet offset cache invalidate missing")
		return
	var off_fn := _slice_func(ren, "_sea_nation_fleet_stack_offsets")
	if "_sea_fleet_offset_cache" not in off_fn:
		_fail("_sea_nation_fleet_stack_offsets must consult the cache")
		return
	var rebuild := _slice_func(ren, "_rebuild_demo_unit_icons")
	if "_invalidate_sea_fleet_offset_cache" not in rebuild:
		_fail("rebuild must invalidate the fleet offset cache")
		return
	var clear_fn := _slice_func(ren, "_clear_sea_nation_layer_icons")
	if "_invalidate_sea_fleet_offset_cache" not in clear_fn:
		_fail("sea-disk clear must invalidate the fleet offset cache")
		return
	var sched := _slice_func(ren, "_schedule_light_terrain_zoom_refresh")
	if "_refresh_terrain_zoom_light()" in sched:
		_fail("_schedule_light_terrain_zoom_refresh must not refresh immediately (wheel already did)")
		return
	if "_pending_terrain_zoom_refresh" not in sched:
		_fail("_schedule_light_terrain_zoom_refresh must still queue the post-burst flush")
		return
	var stars := _slice_func(ren, "_sync_capital_star_scales")
	if "META_MAP_GLYPH_PX" not in stars:
		_fail("_sync_capital_star_scales must skip theme override when px is unchanged")
		return
	if "_capital_star_last_sync_px" not in stars:
		_fail("_sync_capital_star_scales must early-out when last px still matches")
		return
	var lab := _slice_func(ren, "_sea_nation_plate_label")
	if "_fleet2_plate_label_log" not in lab:
		_fail("plate_label must print only on change")
		return
	_pass("PERF-2 source needles (cache / schedule / stars / log-on-change)")


func _setup_fixture() -> bool:
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	var rows: Array = [
		{"id": MAGINOT, "tag": GER_TAG, "name": "Baden-Baden, Stadtkreis", "c": WORLD_MAGINOT, "sea": false, "domain": "land"},
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
		ITA_TAG: {"tag": ITA_TAG, "name": "Italy"},
		POL_TAG: {"tag": POL_TAG, "name": "Poland"},
		USA_TAG: {"tag": USA_TAG, "name": "United States"},
		JAP_TAG: {"tag": JAP_TAG, "name": "Japan"},
		SOV_TAG: {"tag": SOV_TAG, "name": "Soviet Union"},
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
	_inject_sea_geometry()
	_pass("fixture Maginot/Köln/East Kent/North Sea/Channel")
	return true


func _inject_sea_geometry() -> void:
	if _mm == null or not ("_geometry" in _mm):
		return
	var geo: Dictionary = _mm.get("_geometry")
	geo[NORTH_SEA] = {
		"points": PackedVector2Array([
			Vector2(4164.274325675988, 732.5307272414757), Vector2(4166.174301006074, 736.4131930852554),
			Vector2(4168.0742763361595, 740.2956589290352), Vector2(4172.128318089954, 745.8358452922807),
			Vector2(4175.963693706104, 752.1960435535552), Vector2(4178.243309691046, 754.7113853975154),
			Vector2(4180.5229256759885, 757.2267272414756), Vector2(4179.799841637543, 765.7169683029913),
			Vector2(4179.992155628316, 773.6906521075452), Vector2(4179.777676483066, 781.6756368137067),
			Vector2(4180.5229256759885, 790.1547272414757), Vector2(4178.231561462775, 792.658960245657),
			Vector2(4175.9401972495625, 795.1631932498385), Vector2(4172.0956657414545, 801.6379180829756),
			Vector2(4168.082002843649, 807.1851992204645), Vector2(4166.178164259819, 811.01796323097),
			Vector2(4164.274325675988, 814.8507272414756), Vector2(4162.3548929758845, 811.0002498281735),
			Vector2(4160.435460275781, 807.1497724148712), Vector2(4156.359980800274, 801.5185916414757),
			Vector2(4152.573385506481, 795.1383179240686), Vector2(4150.299555591235, 792.6465225827721),
			Vector2(4148.025725675988, 790.1547272414757), Vector2(4148.791404612467, 781.6756570393595),
			Vector2(4148.5128249258, 773.6906448413527), Vector2(4148.769384376283, 765.7159952190113),
			Vector2(4148.025725675988, 757.2267272414756), Vector2(4150.3088036522995, 754.707862920686),
			Vector2(4152.591881628611, 752.1889985998962), Vector2(4156.393754675988, 745.7430872414757),
			Vector2(4160.451815521844, 740.1735997399455), Vector2(4162.363070598915, 736.3521634907106),
		]),
		"label_anchor": WORLD_NORTH_SEA,
	}
	geo[CHANNEL] = {
		"points": PackedVector2Array([
			Vector2(4128.484210541551, 910.7763224551429), Vector2(4130.173619088177, 912.7202007272583),
			Vector2(4133.664048806636, 922.7231159229912), Vector2(4136.518408012873, 923.4433618054113),
			Vector2(4139.316610541551, 927.2403224551429), Vector2(4139.139687192327, 932.7282974104994),
			Vector2(4138.962763843103, 938.216272365856), Vector2(4139.139687192327, 943.7042974104995),
			Vector2(4139.316610541551, 949.1923224551429), Vector2(4136.5075238967065, 953.020052735643),
			Vector2(4133.698437251862, 956.847783016143), Vector2(4131.091323896706, 961.252052735643),
			Vector2(4128.484210541551, 965.656322455143), Vector2(4125.84609558298, 961.2122772551429),
			Vector2(4123.207980624408, 956.7682320551428), Vector2(4120.42989558298, 952.9802772551429),
			Vector2(4117.651810541551, 949.1923224551429), Vector2(4117.814176958154, 943.7042949884351),
			Vector2(4117.976543374758, 938.2162675217276), Vector2(4117.814176958154, 932.7282949884352),
			Vector2(4122.059172102304, 930.031663572581), Vector2(4122.444101436304, 920.1125363671852),
			Vector2(4123.230496541551, 919.5845624551428), Vector2(4125.857353541551, 915.1804424551428),
		]),
		"label_anchor": WORLD_CHANNEL,
	}
	_mm.set("_geometry", geo)
	if _mm.has_method("set_geometry_world_native"):
		_mm.call("set_geometry_world_native", true)
	if _mm.has_method("set_geometry_world_space"):
		_mm.call("set_geometry_world_space", true)


func _setup_formations() -> bool:
	var jobs: Array = [
		["perf2_ger_div6", GER_TAG, "division", DESIGN_LAND, MAGINOT, "GER Div 6"],
		["perf2_ger_ns", GER_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "GER Fleet 2"],
		["perf2_fra_ns", FRA_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "FRA Fleet 2"],
		["perf2_jap_ns", JAP_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "JAP Fleet 2"],
		["perf2_sov_ns", SOV_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "SOV Fleet 1"],
		["perf2_eng_ch", ENG_TAG, "fleet", DESIGN_FLEET, CHANNEL, "ENG Fleet 2"],
		["perf2_ita_ch", ITA_TAG, "fleet", DESIGN_FLEET, CHANNEL, "ITA Fleet 2"],
		["perf2_pol_ch", POL_TAG, "fleet", DESIGN_FLEET, CHANNEL, "POL Fleet 1"],
		["perf2_usa_ch", USA_TAG, "fleet", DESIGN_FLEET, CHANNEL, "USA Fleet 1"],
	]
	for job_v in jobs:
		var job: Array = job_v as Array
		if not _register_formation(str(job[0]), str(job[1]), str(job[2]), str(job[3]), int(job[4]), str(job[5])):
			return false
	_isolate_fixture_formations()
	_pass("seeded NS (GER/FRA/JAP/SOV) + Channel (ENG/ITA/POL/USA)")
	return true


func _isolate_fixture_formations() -> void:
	var keep: Dictionary = {
		"perf2_ger_div6": true,
		"perf2_ger_ns": true,
		"perf2_fra_ns": true,
		"perf2_jap_ns": true,
		"perf2_sov_ns": true,
		"perf2_eng_ch": true,
		"perf2_ita_ch": true,
		"perf2_pol_ch": true,
		"perf2_usa_ch": true,
	}
	var pids: Dictionary = {MAGINOT: true, KOLN: true, EAST_KENT: true, NORTH_SEA: true, CHANNEL: true}
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
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	var info := Panel.new()
	info.name = "InfoPanel"
	info.visible = false
	info.size = Vector2(280, 200)
	ui.add_child(info)
	_mr.set("info_panel", info)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(7160.0, 1480.0)
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
		EAST_KENT: LIVE_RENDER_EAST_KENT,
		NORTH_SEA: LIVE_RENDER_NORTH_SEA,
		CHANNEL: LIVE_RENDER_CHANNEL,
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
		node.position = Vector2.ZERO
		container.add_child(node)
		if "province_nodes" in _mr:
			_mr.province_nodes[pid] = node
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = placed[pid] as Vector2
	_force_centroids()
	_pass("MapRenderer + real centroids")
	return true


func _force_centroids() -> void:
	if _mm != null and "pick_grid" in _mm:
		_mm.pick_grid = null
	if _mm != null and "_centroids" in _mm:
		var cents: Dictionary = _mm.get("_centroids")
		cents[MAGINOT] = WORLD_MAGINOT
		cents[KOLN] = WORLD_KOLN
		cents[EAST_KENT] = LIVE_RENDER_EAST_KENT
		cents[NORTH_SEA] = LIVE_RENDER_NORTH_SEA
		cents[CHANNEL] = LIVE_RENDER_CHANNEL
		_mm.set("_centroids", cents)
	if _mr != null and "province_centroids" in _mr:
		_mr.province_centroids[MAGINOT] = WORLD_MAGINOT
		_mr.province_centroids[KOLN] = WORLD_KOLN
		_mr.province_centroids[EAST_KENT] = LIVE_RENDER_EAST_KENT
		_mr.province_centroids[NORTH_SEA] = LIVE_RENDER_NORTH_SEA
		_mr.province_centroids[CHANNEL] = LIVE_RENDER_CHANNEL


func _force_play_zoom(z: float) -> void:
	if _cam != null:
		_cam.zoom = Vector2(z, z)
		_cam.position = Vector2(7160.0, 1480.0)
		_cam.make_current()
	if "show_unit_counters" in _mr:
		_mr.show_unit_counters = true


func _rebuild_icons() -> void:
	if _mr != null and _mr.has_method("_update_unit_icons_for_test"):
		_mr.call("_update_unit_icons_for_test")
	elif _mr != null and _mr.has_method("_rebuild_demo_unit_icons"):
		_mr.call("_rebuild_demo_unit_icons", {})


func _sync_offsets(z: float) -> void:
	if _mr != null and _mr.has_method("_sync_sea_nation_fleet_offsets"):
		_mr.call("_sync_sea_nation_fleet_offsets", z)


func _fit_radius(pid: int, count: int) -> float:
	if _mr != null and _mr.has_method("_sea_nation_fit_radius"):
		return float(_mr.call("_sea_nation_fit_radius", pid, count, 14.5))
	return 14.5


func _offsets_equal(a: Array, b: Array, who: String) -> bool:
	if a.size() != b.size():
		_fail("%s offset count %d != %d" % [who, a.size(), b.size()])
		return false
	for i in a.size():
		var av: Vector2 = a[i] as Vector2
		var bv: Vector2 = b[i] as Vector2
		if av.distance_to(bv) > OFFSET_EPS:
			_fail("%s offset[%d] cache=%s raw=%s d=%.4f" % [who, i, str(av), str(bv), av.distance_to(bv)])
			return false
	return true


func _compute_offsets(pid: int, count: int, radius: float, use_cache: bool) -> Array:
	if "_sea_fleet_offset_cache_enabled" in _mr:
		_mr._sea_fleet_offset_cache_enabled = use_cache
	if _mr.has_method("_invalidate_sea_fleet_offset_cache"):
		_mr.call("_invalidate_sea_fleet_offset_cache")
	var offs: Array = _mr.call("_sea_nation_fleet_stack_offsets", count, radius, pid) as Array
	if "_sea_fleet_offset_cache_enabled" in _mr:
		_mr._sea_fleet_offset_cache_enabled = true
	return offs


func _collect_plate_world(pid: int) -> Dictionary:
	var out: Dictionary = {}
	if _mr == null or not _mr.has_method("_iter_demo_unit_icons_at_pid"):
		return out
	var icons: Array = _mr.call("_iter_demo_unit_icons_at_pid", pid) as Array
	for c in icons:
		if not (c is Node2D):
			continue
		var icon: Node2D = c as Node2D
		if not bool(icon.get_meta("sea_nation_disk", false)):
			continue
		var tag: String = str(icon.get_meta("sea_nation_tag", ""))
		var world: Vector2 = icon.position
		if _mr.has_method("_demo_unit_icon_world_pos"):
			world = _mr.call("_demo_unit_icon_world_pos", icon, pid) as Vector2
		out[tag] = world
	return out


func _test_a_offsets_identical_with_and_without_cache() -> void:
	var r_ch: float = _fit_radius(CHANNEL, 4)
	var r_ns: float = _fit_radius(NORTH_SEA, 4)
	var raw_ch: Array = _compute_offsets(CHANNEL, 4, r_ch, false)
	var raw_ns: Array = _compute_offsets(NORTH_SEA, 4, r_ns, false)
	var cached_ch: Array = _compute_offsets(CHANNEL, 4, r_ch, true)
	var cached_ns: Array = _compute_offsets(NORTH_SEA, 4, r_ns, true)
	if raw_ch.size() != 4 or raw_ns.size() != 4:
		_fail("(a) expected 4 offsets per shared sea (ch=%d ns=%d)" % [raw_ch.size(), raw_ns.size()])
		return
	if not _offsets_equal(cached_ch, raw_ch, "(a) Channel"):
		return
	if not _offsets_equal(cached_ns, raw_ns, "(a) North Sea"):
		return
	var cached_ch2: Array = _mr.call("_sea_nation_fleet_stack_offsets", 4, r_ch, CHANNEL) as Array
	var cached_ns2: Array = _mr.call("_sea_nation_fleet_stack_offsets", 4, r_ns, NORTH_SEA) as Array
	if not _offsets_equal(cached_ch2, raw_ch, "(a) Channel hit"):
		return
	if not _offsets_equal(cached_ns2, raw_ns, "(a) North Sea hit"):
		return
	print(
		"  [INFO] PERF-2 offsets ch=%s ns=%s r_ch=%.3f r_ns=%.3f"
		% [str(cached_ch), str(cached_ns), r_ch, r_ns]
	)
	_pass("(a) shared-sea offsets identical with and without cache")


func _test_a_plate_world_positions_match() -> void:
	if "_sea_fleet_offset_cache_enabled" in _mr:
		_mr._sea_fleet_offset_cache_enabled = false
	if _mr.has_method("_invalidate_sea_fleet_offset_cache"):
		_mr.call("_invalidate_sea_fleet_offset_cache")
	_sync_offsets(1.0)
	var raw_ch: Dictionary = _collect_plate_world(CHANNEL)
	var raw_ns: Dictionary = _collect_plate_world(NORTH_SEA)
	if "_sea_fleet_offset_cache_enabled" in _mr:
		_mr._sea_fleet_offset_cache_enabled = true
	if _mr.has_method("_invalidate_sea_fleet_offset_cache"):
		_mr.call("_invalidate_sea_fleet_offset_cache")
	_sync_offsets(1.0)
	var on_ch: Dictionary = _collect_plate_world(CHANNEL)
	var on_ns: Dictionary = _collect_plate_world(NORTH_SEA)
	for tag in ["ENG", "ITA", "POL", "USA"]:
		if not raw_ch.has(tag) or not on_ch.has(tag):
			_fail("(a) Channel plate %s missing raw=%s cached=%s" % [tag, str(raw_ch.has(tag)), str(on_ch.has(tag))])
			return
		var d: float = (raw_ch[tag] as Vector2).distance_to(on_ch[tag] as Vector2)
		if d > OFFSET_EPS:
			_fail("(a) Channel %s world moved with cache d=%.4f" % [tag, d])
			return
	for tag2 in ["GER", "FRA", "JAP", "SOV"]:
		if not raw_ns.has(tag2) or not on_ns.has(tag2):
			_fail("(a) North Sea plate %s missing raw=%s cached=%s" % [tag2, str(raw_ns.has(tag2)), str(on_ns.has(tag2))])
			return
		var d2: float = (raw_ns[tag2] as Vector2).distance_to(on_ns[tag2] as Vector2)
		if d2 > OFFSET_EPS:
			_fail("(a) North Sea %s world moved with cache d=%.4f" % [tag2, d2])
			return
	_pass("(a) live plate world positions identical with and without cache")


func _fat_ring(center: Vector2, radius: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var ang: float = TAU * float(i) / float(n)
		pts[i] = center + Vector2(cos(ang), sin(ang)) * radius
	return pts


func _attach_fat_sea_rings() -> void:
	if _mr == null or not ("province_nodes" in _mr):
		return
	var rings: Dictionary = {
		CHANNEL: LIVE_RENDER_CHANNEL,
		NORTH_SEA: LIVE_RENDER_NORTH_SEA,
	}
	for pid_v in rings.keys():
		var pid: int = int(pid_v)
		if not _mr.province_nodes.has(pid):
			continue
		var node: Node2D = _mr.province_nodes[pid] as Node2D
		if node == null:
			continue
		var doomed: Array = []
		for ch in node.get_children():
			if ch is Polygon2D:
				doomed.append(ch)
		for d_v in doomed:
			var d: Node = d_v as Node
			node.remove_child(d)
			d.free()
		var poly := Polygon2D.new()
		poly.name = "FatSeaRing"
		poly.polygon = _fat_ring(rings[pid] as Vector2, 48.0, 2200)
		node.add_child(poly)
	if _mr.has_method("_invalidate_sea_fleet_offset_cache"):
		_mr.call("_invalidate_sea_fleet_offset_cache")


func _plant_capital_stars(n: int) -> void:
	if _mr == null or not ("province_nodes" in _mr) or not ("container" in _mr):
		return
	var host: Node2D = _mr.container as Node2D
	if host == null:
		return
	var meta_px: StringName = &"_map_glyph_px"
	var meta_cap: StringName = &"_map_glyph_capital"
	for i in n:
		var pid: int = 880000 + i
		var node := Node2D.new()
		node.name = "Perf2StarHost_%d" % pid
		host.add_child(node)
		_mr.province_nodes[pid] = node
		var star := Label.new()
		star.text = "★"
		star.set_meta(meta_px, -1)
		star.set_meta(meta_cap, true)
		node.add_child(star)
	if _mr.has_method("_invalidate_capital_star_scale_cache"):
		_mr.call("_invalidate_capital_star_scale_cache")


func _usec_call(method_name: String) -> int:
	var t0: int = Time.get_ticks_usec()
	_mr.call(method_name)
	return Time.get_ticks_usec() - t0


func _test_b_detail_and_wheel_budgets() -> void:
	_force_play_zoom(0.90)
	if "_sea_fleet_offset_cache_enabled" in _mr:
		_mr._sea_fleet_offset_cache_enabled = false
	if _mr.has_method("_invalidate_sea_fleet_offset_cache"):
		_mr.call("_invalidate_sea_fleet_offset_cache")
	var r_ch: float = _fit_radius(CHANNEL, 4)
	var t_raw0: int = Time.get_ticks_usec()
	_mr.call("_sea_nation_fleet_stack_offsets", 4, r_ch, CHANNEL)
	var raw_usec: int = Time.get_ticks_usec() - t_raw0
	if "_sea_fleet_offset_cache_enabled" in _mr:
		_mr._sea_fleet_offset_cache_enabled = true
	if _mr.has_method("_invalidate_sea_fleet_offset_cache"):
		_mr.call("_invalidate_sea_fleet_offset_cache")
	_mr.call("_sea_nation_fleet_stack_offsets", 4, r_ch, CHANNEL)
	var t_hit0: int = Time.get_ticks_usec()
	_mr.call("_sea_nation_fleet_stack_offsets", 4, r_ch, CHANNEL)
	var hit_usec: int = Time.get_ticks_usec() - t_hit0
	print("  [INFO] PERF-2 offset_usec raw=%d cached_hit=%d budget=%d" % [raw_usec, hit_usec, OFFSET_CACHE_BUDGET_USEC])
	if hit_usec > OFFSET_CACHE_BUDGET_USEC:
		_fail("(b) cached _sea_nation_fleet_stack_offsets %d usec > %d" % [hit_usec, OFFSET_CACHE_BUDGET_USEC])
		return

	# Warm the every-6th-frame path, then time a cached call.
	if not _mr.has_method("_refresh_province_detail_visibility"):
		_fail("(b) _refresh_province_detail_visibility missing")
		return
	_mr.call("_refresh_province_detail_visibility")
	var detail_usec: int = _usec_call("_refresh_province_detail_visibility")
	print("  [INFO] PERF-2 detail_refresh_usec=%d budget=%d" % [detail_usec, DETAIL_REFRESH_BUDGET_USEC])
	if detail_usec > DETAIL_REFRESH_BUDGET_USEC:
		_fail("(b) _refresh_province_detail_visibility %d usec > %d" % [detail_usec, DETAIL_REFRESH_BUDGET_USEC])
		return

	# First light refresh applies star fonts; the wheel notch after that must skip.
	if not _mr.has_method("_refresh_terrain_zoom_light"):
		_fail("(b) _refresh_terrain_zoom_light missing")
		return
	_mr.call("_refresh_terrain_zoom_light")
	var t_w0: int = Time.get_ticks_usec()
	_mr.call("_refresh_terrain_zoom_light")
	if _mr.has_method("_schedule_light_terrain_zoom_refresh"):
		_mr.call("_schedule_light_terrain_zoom_refresh")
	var wheel_usec: int = Time.get_ticks_usec() - t_w0
	print("  [INFO] PERF-2 wheel_notch_usec=%d budget=%d" % [wheel_usec, WHEEL_REFRESH_BUDGET_USEC])
	if wheel_usec > WHEEL_REFRESH_BUDGET_USEC:
		_fail("(b) wheel-notch refresh work %d usec > %d" % [wheel_usec, WHEEL_REFRESH_BUDGET_USEC])
		return
	if "_pending_terrain_zoom_refresh" in _mr and not bool(_mr._pending_terrain_zoom_refresh):
		_fail("(b) wheel schedule must leave the post-burst refresh pending")
		return
	_pass(
		"(b) detail %d usec / wheel %d usec / cache-hit %d usec (raw %d)"
		% [detail_usec, wheel_usec, hit_usec, raw_usec]
	)


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	_mr = null
