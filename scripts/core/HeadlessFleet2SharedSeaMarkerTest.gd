extends SceneTree

## FLEET-2: one clickable marker per nation when several fleets share a
## sea province. Hit disks match the drawn plates and must not overlap.
## Production stationing (same as `_station_world_major_fleet_chips`):
##   950000 North Sea  GER, FRA, SOV, JAP
##   950001 Channel    ENG, ITA, POL, USA
## FIX #1: 3+ plates use a 2x2 / column clamped to the sea polygon so the
## Channel cannot fan across East Kent. Cluster pad picks the nearest plate
## and never nearest-own-land spill. FLEET-1 / MV-1b stay as today.
## Headless / xvfb are NOT live Play.
##
## Raw MapManager / provinces_geometry.json centroids (UNSCALED):
##   710173 Maginot GER land / GER Div 6    (4283.279411, 1010.266854)
##   710417 Köln (GER land; MV-1b FRA)      (4254.322147,  944.095861)
##   711453 East Kent (ENG coastal land)    (4119.875715,  938.028287)
##   950000 North Sea Zone                  (4164.266667,  773.688889)
##   950001 English Channel                 (4128.701206,  938.217996)
##
## Live world_accurate renderer centroids (Play RESULT_7387, ×THEATER_SCALE):
##   950001 Channel  (7134.5, 1622.3)
##   950000 North Sea (7195.9, 1336.9)
## Injected geo stays UNSCALED so a missing transform cannot hide again.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFleet2SharedSeaMarkerTest.gd
##   tools/eoa_fleet2_guard.sh

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
const FID_GER_LAND := "fleet2_ger_div6"
const FID_GER_FLEET := "fleet2_ger_north_sea"
const FID_FRA_FLEET_SEA := "fleet2_fra_north_sea"
const FID_JAP_FLEET := "fleet2_jap_north_sea"
const FID_SOV_FLEET := "fleet2_sov_north_sea"
const FID_ENG_FLEET := "fleet2_eng_channel"
const FID_ITA_FLEET := "fleet2_ita_channel"
const FID_POL_FLEET := "fleet2_pol_channel"
const FID_USA_FLEET := "fleet2_usa_channel"
const FID_FRA_FLEET_KOLN := "fleet2_fra_koln"
const DESIGN_LAND := "infantry_1936"
const DESIGN_FLEET := "king_george_v_class_bb"
const WORLD_MAGINOT := Vector2(4283.279410731325, 1010.2668539708038)
const WORLD_KOLN := Vector2(4254.322147319904, 944.0958606451493)
const WORLD_EAST_KENT := Vector2(4119.875714645911, 938.0282873606084)
const WORLD_NORTH_SEA := Vector2(4164.266666666666, 773.6888888888889)
const WORLD_CHANNEL := Vector2(4128.701206024651, 938.2179956383225)
const LIVE_RENDER_CHANNEL := Vector2(7134.5, 1622.3)
const LIVE_RENDER_NORTH_SEA := Vector2(7195.9, 1336.9)
const LIVE_RENDER_EAST_KENT := Vector2(7119.145, 1620.913)
const LIVE_OLD_ENG_CHIP := Vector2(7134.5, 1610.3)
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
var _jap_ns: Vector2 = Vector2.ZERO
var _sov_ns: Vector2 = Vector2.ZERO
var _eng_ch: Vector2 = Vector2.ZERO
var _ita_ch: Vector2 = Vector2.ZERO
var _pol_ch: Vector2 = Vector2.ZERO
var _usa_ch: Vector2 = Vector2.ZERO
var _ger_r: float = 0.0
var _fra_r: float = 0.0
var _ch_r: float = 0.0
const WORLD_OLD_ENG_CHIP := Vector2(4128.701, 926.218)
const MAX_CLUSTER_SPACINGS := 3.0


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
	_test_d_channel_production()
	_test_e_koln_fra_land_fleet()
	_test_f_channel_four_plates()
	_test_g_east_kent_picks_channel()
	_test_h_cluster_pad_nearest()
	_test_i_labels_have_nation_tag()
	_test_j_renderer_space_anchor()
	_test_k_spread_band_live_clicks()
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
	if "func _sea_nation_choose_clamped_offsets" not in ren:
		_fail("compact/clamp sea-nation layout helper missing")
		return
	if "func _sea_nation_fit_radius" not in ren:
		_fail("narrow-sea packed radius helper missing")
		return
	if "func _pick_nearest_sea_nation_in_cluster_pad" not in ren:
		_fail("cluster no-spill pad helper missing")
		return
	if "func _sea_nation_plate_label" not in ren:
		_fail("nation-tag plate label helper missing")
		return
	var poly_fn := _slice_func(ren, "_sea_province_poly_world")
	if "transform_province_points" not in poly_fn:
		_fail("_sea_province_poly_world must transform MapManager geo into renderer space")
		return
	if "func _sea_align_poly_to_renderer_centroid" not in ren:
		_fail("sea poly must align to province_centroids (renderer world)")
		return
	if "func _sea_nation_maybe_fallback_chip_base" not in ren:
		_fail("chip-base 2x2 fallback missing — Canada drift must not pass")
		return
	if "func _sea_nation_counter_scale" not in ren:
		_fail("sea-nation chip must shrink to the hit disk")
		return
	if "func _pick_sea_nation_plate_drawn_at_world" not in ren:
		_fail("FIX #3 drawn sea-plate pick missing")
		return
	if "func _nation_fleet_rank" not in ren:
		_fail("FIX #3 per-nation fleet ordinal missing")
		return
	if "func _sea_nation_formation_dist_sq" not in ren:
		_fail("FIX #3 cluster-pad must beat a farther Home-band land hit")
		return
	if "maxi(index, 0) + 1" in ren:
		_fail("plate label must not use sea-stack index+1")
		return
	var land3 := _slice_func(ren, "_try_open_land_unit_at_world")
	if "_pick_sea_nation_plate_drawn_at_world" not in land3:
		_fail("land open must bind a drawn sea plate before the own-land disk")
		return
	if "_pick_nearest_sea_nation_in_cluster_pad" not in land3:
		_fail("land open must bind own-GER cluster-pad (not sea-zone inspector)")
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
	_pass("fixture Maginot/Köln/East Kent/North Sea/Channel (real centroids+polys)")
	return true


func _inject_sea_geometry() -> void:
	if _mm == null or not ("_geometry" in _mm):
		return
	var geo: Dictionary = _mm.get("_geometry")
	geo[EAST_KENT] = {
		"points": PackedVector2Array([
			Vector2(4114.9487104, 944.9813493100348), Vector2(4113.4305644080705, 942.7185933665803),
			Vector2(4116.124218215877, 940.9319106924808), Vector2(4118.332788739935, 939.4669805646026),
			Vector2(4117.989403408163, 937.1441333096208), Vector2(4117.64601807639, 934.8212860546389),
			Vector2(4117.122924502648, 932.5480340664365), Vector2(4118.877130552647, 932.156054185142),
			Vector2(4120.631336602646, 931.7640743038475), Vector2(4122.406928312705, 931.8778916986766),
			Vector2(4124.182520022764, 931.9917090935057), Vector2(4127.733703442882, 932.2193438831639),
			Vector2(4127.130110564115, 935.3231052665808), Vector2(4126.526517685348, 938.4268666499976),
			Vector2(4123.578927143997, 939.566869693379), Vector2(4120.631336602646, 940.7068727367603),
			Vector2(4119.149901307549, 941.2720870561492), Vector2(4117.707925722648, 942.7185933665803),
			Vector2(4117.239108991306, 944.9597355170483), Vector2(4116.124218215877, 944.9702563969404),
		]),
		"label_anchor": WORLD_EAST_KENT,
	}
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
	if not _register_formation(FID_GER_LAND, GER_TAG, "division", DESIGN_LAND, MAGINOT, "GER Div 6"):
		return false
	if not _register_formation(FID_GER_FLEET, GER_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "GER Fleet 2"):
		return false
	if not _register_formation(FID_FRA_FLEET_SEA, FRA_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "FRA Fleet 2"):
		return false
	if not _register_formation(FID_JAP_FLEET, JAP_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "JAP Fleet 2"):
		return false
	if not _register_formation(FID_SOV_FLEET, SOV_TAG, "fleet", DESIGN_FLEET, NORTH_SEA, "SOV king_george_v_class_bb"):
		return false
	if not _register_formation(FID_ENG_FLEET, ENG_TAG, "fleet", DESIGN_FLEET, CHANNEL, "ENG Fleet 2"):
		return false
	if not _register_formation(FID_ITA_FLEET, ITA_TAG, "fleet", DESIGN_FLEET, CHANNEL, "ITA Fleet 2"):
		return false
	if not _register_formation(FID_POL_FLEET, POL_TAG, "fleet", DESIGN_FLEET, CHANNEL, "POL king_george_v_class_bb"):
		return false
	if not _register_formation(FID_USA_FLEET, USA_TAG, "fleet", DESIGN_FLEET, CHANNEL, "USA king_george_v_class_bb"):
		return false
	if not _register_formation(FID_FRA_FLEET_KOLN, FRA_TAG, "fleet", DESIGN_FLEET, KOLN, "FRA Köln Fleet"):
		return false
	_isolate_fixture_formations()
	_pass("seeded production NS (GER/FRA/JAP/SOV) + Channel (ENG/ITA/POL/USA)")
	return true


func _isolate_fixture_formations() -> void:
	# Live 1936 OOB also stations GER land on Köln / Maginot. First-wins would
	# hide the FRA land-fleet disk that MV-1b / (e) must still hit-and-refuse.
	var keep: Dictionary = {
		FID_GER_LAND: true,
		FID_GER_FLEET: true,
		FID_FRA_FLEET_SEA: true,
		FID_JAP_FLEET: true,
		FID_SOV_FLEET: true,
		FID_ENG_FLEET: true,
		FID_ITA_FLEET: true,
		FID_POL_FLEET: true,
		FID_USA_FLEET: true,
		FID_FRA_FLEET_KOLN: true,
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


func _force_play_zoom() -> void:
	if _cam != null:
		_cam.zoom = Vector2(1.0, 1.0)
		_cam.position = Vector2(7160.0, 1480.0)
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
	var icons: Array = []
	if _mr != null and _mr.has_method("_iter_demo_unit_icons_at_pid"):
		icons = _mr.call("_iter_demo_unit_icons_at_pid", pid) as Array
	else:
		var host: Node2D = null
		if "province_nodes" in _mr and _mr.province_nodes.has(pid):
			host = _mr.province_nodes[pid] as Node2D
		if host != null:
			for c0 in host.get_children():
				if c0 is Node2D and str(c0.name).begins_with("DemoUnitIcon_"):
					icons.append(c0)
	for c in icons:
		if not (c is Node2D):
			continue
		if str((c as Node2D).get_meta("formation_id", "")) == fid:
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
	var jap_icon: Node2D = _icon_for_fid(NORTH_SEA, FID_JAP_FLEET)
	var sov_icon: Node2D = _icon_for_fid(NORTH_SEA, FID_SOV_FLEET)
	var eng_icon: Node2D = _icon_for_fid(CHANNEL, FID_ENG_FLEET)
	var ita_icon: Node2D = _icon_for_fid(CHANNEL, FID_ITA_FLEET)
	var pol_icon: Node2D = _icon_for_fid(CHANNEL, FID_POL_FLEET)
	var usa_icon: Node2D = _icon_for_fid(CHANNEL, FID_USA_FLEET)
	if ger_icon == null or fra_icon == null or jap_icon == null or sov_icon == null:
		_fail("North Sea must draw one DemoUnitIcon per nation (GER/FRA/JAP/SOV)")
		return false
	if eng_icon == null or ita_icon == null or pol_icon == null or usa_icon == null:
		_fail("Channel must draw one DemoUnitIcon per production nation (ENG/ITA/POL/USA)")
		return false
	for ic in [ger_icon, fra_icon, jap_icon, sov_icon, eng_icon, ita_icon, pol_icon, usa_icon]:
		if not bool((ic as Node2D).get_meta("sea_nation_disk", false)):
			_fail("shared-sea markers must set sea_nation_disk (name=%s)" % (ic as Node2D).name)
			return false
	if not str(eng_icon.name).begins_with("DemoUnitIcon_%d_" % CHANNEL):
		_fail("Channel ENG name=%s want DemoUnitIcon_%d_ENG" % [eng_icon.name, CHANNEL])
		return false
	_ger_ns = _icon_world(ger_icon, NORTH_SEA)
	_fra_ns = _icon_world(fra_icon, NORTH_SEA)
	_jap_ns = _icon_world(jap_icon, NORTH_SEA)
	_sov_ns = _icon_world(sov_icon, NORTH_SEA)
	_eng_ch = _icon_world(eng_icon, CHANNEL)
	_ita_ch = _icon_world(ita_icon, CHANNEL)
	_pol_ch = _icon_world(pol_icon, CHANNEL)
	_usa_ch = _icon_world(usa_icon, CHANNEL)
	_ger_r = _icon_hit_r(ger_icon)
	_fra_r = _icon_hit_r(fra_icon)
	_ch_r = _icon_hit_r(eng_icon)
	var base: Vector2 = LIVE_RENDER_NORTH_SEA + Vector2(0, -12)
	var ch_base: Vector2 = LIVE_RENDER_CHANNEL + Vector2(0, -12)
	print(
		"  [INFO] HeadlessFleet2SharedSeaMarkerTest: NS GER %s r=%.1f FRA %s JAP %s SOV %s | CH ENG %s ITA %s POL %s USA %s r=%.1f (base NS %s CH %s)"
		% [
			str(_ger_ns), _ger_r, str(_fra_ns), str(_jap_ns), str(_sov_ns),
			str(_eng_ch), str(_ita_ch), str(_pol_ch), str(_usa_ch), _ch_r,
			str(base), str(ch_base),
		]
	)
	if _ger_ns.distance_to(_fra_ns) < 1.0:
		_fail("GER and FRA North Sea markers must be offset (same centre)")
		return false
	_pass(
		"coords NS GER %s r=%.1f FRA %s | CH ENG %s ITA %s POL %s USA %s r=%.1f"
		% [str(_ger_ns), _ger_r, str(_fra_ns), str(_eng_ch), str(_ita_ch), str(_pol_ch), str(_usa_ch), _ch_r]
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


func _is_channel_fid(fid: String) -> bool:
	return fid == FID_ENG_FLEET or fid == FID_ITA_FLEET or fid == FID_POL_FLEET or fid == FID_USA_FLEET


func _channel_plates() -> Array:
	return [
		{"fid": FID_ENG_FLEET, "pos": _eng_ch, "tag": ENG_TAG},
		{"fid": FID_ITA_FLEET, "pos": _ita_ch, "tag": ITA_TAG},
		{"fid": FID_POL_FLEET, "pos": _pol_ch, "tag": POL_TAG},
		{"fid": FID_USA_FLEET, "pos": _usa_ch, "tag": USA_TAG},
	]


func _assert_plate_picks_own(who: String, world: Vector2, want_fid: String, own_card: bool) -> bool:
	_reset_pick()
	var disk: Object = _mr.call("_pick_unit_formation_at_world", world)
	var got := str(disk.formation_id) if disk != null and "formation_id" in disk else "?"
	if disk == null or got != want_fid:
		_fail("%s disk centre must pick %s (got %s)" % [who, want_fid, got])
		return false
	var opened: bool = _click_chip_path(world)
	if not opened or _selected_fid() != want_fid:
		_fail("%s click selected=%s want %s" % [who, _selected_fid(), want_fid])
		return false
	if not _popup_up():
		_fail("%s card missing" % who)
		return false
	if own_card:
		if not _popup_has_btn("BtnOpenFight") or not _popup_has_btn("BtnAssignLeader"):
			_fail("%s own card must show Open fight / Assign" % who)
			return false
	elif not _assert_no_command_buttons(who):
		return false
	return true


func _plate_clamped_ok(world: Vector2, pid: int) -> bool:
	if _mr != null and _mr.has_method("_sea_nation_plate_clamped_ok"):
		return bool(_mr.call("_sea_nation_plate_clamped_ok", world, pid))
	if _mr != null and bool(_mr.call("_province_id_is_sea", int(_mr.call("_resolve_hex_pick_pid", world)))):
		return true
	return false


func _test_d_channel_production() -> void:
	# Production Channel holds ENG/ITA/POL/USA — not a single ENG pin.
	_reset_pick()
	var hex: int = int(_mr.call("_resolve_hex_pick_pid", LIVE_RENDER_CHANNEL))
	if hex != CHANNEL and hex != EAST_KENT:
		_fail("(d) GIS at live Channel centroid want Channel/East Kent got %d" % hex)
		return
	for rec_v in _channel_plates():
		var rec: Dictionary = rec_v as Dictionary
		var fid := str(rec["fid"])
		var pos: Vector2 = rec["pos"] as Vector2
		var tag := str(rec["tag"])
		if pos == Vector2.ZERO:
			_fail("(d) %s Channel plate centre missing" % tag)
			return
		if not _assert_plate_picks_own("(d) %s Channel" % tag, pos, fid, false):
			return
	_pass("(d) production Channel ENG/ITA/POL/USA each plate picks its fleet (read-only)")


func _test_f_channel_four_plates() -> void:
	var seen: Dictionary = {}
	for rec_v in _channel_plates():
		var rec: Dictionary = rec_v as Dictionary
		var fid := str(rec["fid"])
		var pos: Vector2 = rec["pos"] as Vector2
		var tag := str(rec["tag"])
		if not _assert_plate_picks_own("(f) %s" % tag, pos, fid, false):
			return
		if not _plate_clamped_ok(pos, CHANNEL):
			_fail("(f) %s plate centre %s is not over sea / clamp tolerance" % [tag, str(pos)])
			return
		seen[fid] = pos
	var pts: Array = [_eng_ch, _ita_ch, _pol_ch, _usa_ch]
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var a: Vector2 = pts[i] as Vector2
			var b: Vector2 = pts[j] as Vector2
			if a.distance_to(b) <= (_ch_r + _ch_r):
				_fail("(f) Channel disks overlap (%s vs %s dist=%.1f r_sum=%.1f)" % [str(a), str(b), a.distance_to(b), _ch_r * 2.0])
				return
	if seen.size() != 4:
		_fail("(f) want 4 distinct Channel fleets")
		return
	_pass("(f) Channel 4 plates: each centre picks its fleet and sits over sea/clamp")


func _test_g_east_kent_picks_channel() -> void:
	# Live renderer-world East Kent / old ENG chip (Play RESULT_7387).
	# Unscaled 4119/4128 is the Canada-space miss that hid FIX #1.
	var samples: Array = [
		{"name": "live East Kent 711453", "pos": LIVE_RENDER_EAST_KENT},
		{"name": "live old ENG chip", "pos": LIVE_OLD_ENG_CHIP},
		{"name": "live Channel centroid", "pos": LIVE_RENDER_CHANNEL},
	]
	for s_v in samples:
		var s: Dictionary = s_v as Dictionary
		var pos: Vector2 = s["pos"] as Vector2
		var name := str(s["name"])
		_reset_pick()
		var disk: Object = _mr.call("_pick_unit_formation_at_world", pos)
		var got := str(disk.formation_id) if disk != null and "formation_id" in disk else "?"
		if disk == null or not _is_channel_fid(got):
			_fail("(g) %s pick=%s want a Channel fleet (not GER Div 6)" % [name, got])
			return
		if got == FID_GER_LAND:
			_fail("(g) %s spilled to GER Div 6" % name)
			return
		var opened: bool = _click_chip_path(pos)
		if not opened:
			_fail("(g) %s click opened nothing (spill/land?)" % name)
			return
		if _selected_fid() == FID_GER_LAND:
			_fail("(g) %s selected GER Div 6 — land spill regression" % name)
			return
		if not _is_channel_fid(_selected_fid()):
			_fail("(g) %s selected=%s want a Channel fleet" % [name, _selected_fid()])
			return
		if not _popup_up():
			_fail("(g) %s Channel card missing" % name)
			return
		if not _assert_no_command_buttons("(g) %s" % name):
			return
	_pass("(g) East Kent / old ENG chip / label anchor pick a Channel fleet, not GER Div 6")


func _test_h_cluster_pad_nearest() -> void:
	# Mid-point between ENG and ITA (typical 2x2 gap) and the cluster centroid.
	var mid: Vector2 = (_eng_ch + _ita_ch + _pol_ch + _usa_ch) * 0.25
	var gap: Vector2 = (_eng_ch + _ita_ch) * 0.5
	for rec_v in [{"name": "cluster centroid", "pos": mid}, {"name": "ENG/ITA gap", "pos": gap}]:
		var rec: Dictionary = rec_v as Dictionary
		var pos: Vector2 = rec["pos"] as Vector2
		var name := str(rec["name"])
		_reset_pick()
		var disk: Object = _mr.call("_pick_unit_formation_at_world", pos)
		var got := str(disk.formation_id) if disk != null and "formation_id" in disk else "?"
		if disk == null or not _is_channel_fid(got):
			_fail("(h) %s pick=%s want nearest Channel plate (not land spill)" % [name, got])
			return
		var opened: bool = _click_chip_path(pos)
		if not opened or not _is_channel_fid(_selected_fid()):
			_fail("(h) %s selected=%s want a Channel fleet" % [name, _selected_fid()])
			return
		if _selected_fid() == FID_GER_LAND:
			_fail("(h) %s spilled to GER Div 6" % name)
			return
		if not _assert_no_command_buttons("(h) %s" % name):
			return
	_pass("(h) cluster-pad click picks the nearest Channel plate, not land spill")


func _icon_label(pid: int, fid: String) -> String:
	var icon: Node2D = _icon_for_fid(pid, fid)
	if icon == null:
		return ""
	var desig: Node = icon.get_node_or_null("Designation")
	if desig == null:
		return ""
	return str(desig.get("text"))


func _test_i_labels_have_nation_tag() -> void:
	var rows: Array = [
		{"pid": NORTH_SEA, "fid": FID_GER_FLEET, "tag": GER_TAG},
		{"pid": NORTH_SEA, "fid": FID_FRA_FLEET_SEA, "tag": FRA_TAG},
		{"pid": NORTH_SEA, "fid": FID_JAP_FLEET, "tag": JAP_TAG},
		{"pid": NORTH_SEA, "fid": FID_SOV_FLEET, "tag": SOV_TAG},
		{"pid": CHANNEL, "fid": FID_ENG_FLEET, "tag": ENG_TAG},
		{"pid": CHANNEL, "fid": FID_ITA_FLEET, "tag": ITA_TAG},
		{"pid": CHANNEL, "fid": FID_POL_FLEET, "tag": POL_TAG},
		{"pid": CHANNEL, "fid": FID_USA_FLEET, "tag": USA_TAG},
	]
	for rec_v in rows:
		var rec: Dictionary = rec_v as Dictionary
		var tag := str(rec["tag"])
		var label: String = _icon_label(int(rec["pid"]), str(rec["fid"]))
		if label.is_empty():
			_fail("(i) %s plate label missing" % tag)
			return
		if tag not in label:
			_fail("(i) %s label '%s' must include the nation tag" % [tag, label])
			return
		if "Fleet" not in label:
			_fail("(i) %s label '%s' must include Fleet" % [tag, label])
			return
		var has_digit := false
		for ci in label.length():
			var code: int = label.unicode_at(ci)
			if code >= 48 and code <= 57:
				has_digit = true
				break
		if not has_digit:
			_fail("(i) %s label '%s' must be 'TAG Fleet N' (POL/USA/SOV included)" % [tag, label])
			return
		if tag == SOV_TAG:
			var low: String = label.to_lower()
			if "king" in low or "class_bb" in low or label.ends_with(".") or "king_g" in low:
				_fail("(i) SOV label truncated/design-id: '%s'" % label)
				return
			if label.length() > 14:
				_fail("(i) SOV label still too long / truncated path: '%s'" % label)
				return
		# FIX #3 (c): POL/USA/SOV are each the nation's only fleet — not stack 3/4.
		if tag == POL_TAG or tag == USA_TAG or tag == SOV_TAG:
			if "Fleet 3" in label or "Fleet 4" in label:
				_fail("(i) %s label '%s' used sea-stack index, not per-nation ordinal" % [tag, label])
				return
			if "Fleet 1" not in label:
				_fail("(i) %s label '%s' want per-nation Fleet 1" % [tag, label])
				return
	_pass("(i) plate labels are 'TAG Fleet N'; POL/USA/SOV included; SOV not truncated")


func _cluster_mean(pts: Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p_v in pts:
		acc += p_v as Vector2
	return acc / float(pts.size())


func _assert_cluster_near_live(who: String, cluster: Vector2, live_c: Vector2, chip_base: Vector2, step: float) -> bool:
	var lim: float = MAX_CLUSTER_SPACINGS * maxf(step, 12.0)
	if cluster.distance_to(live_c) > lim:
		_fail("%s cluster %s is %.1f from live renderer centroid %s (lim=%.1f) — geo/renderer space mismatch" % [
			who, str(cluster), cluster.distance_to(live_c), str(live_c), lim
		])
		return false
	if cluster.distance_to(chip_base) > lim:
		_fail("%s cluster %s is %.1f from chip base %s (lim=%.1f)" % [
			who, str(cluster), cluster.distance_to(chip_base), str(chip_base), lim
		])
		return false
	# The FIX #1 Canada site: unscaled Channel/NS centroids.
	if cluster.distance_to(WORLD_CHANNEL) < 80.0 or cluster.distance_to(WORLD_NORTH_SEA) < 80.0:
		_fail("%s cluster %s sat on UNSCALED geo (Canada) not renderer world" % [who, str(cluster)])
		return false
	return true


func _test_j_renderer_space_anchor() -> void:
	var ch_pts: Array = [_eng_ch, _ita_ch, _pol_ch, _usa_ch]
	var ns_pts: Array = [_ger_ns, _fra_ns, _jap_ns, _sov_ns]
	var ch_c: Vector2 = _cluster_mean(ch_pts)
	var ns_c: Vector2 = _cluster_mean(ns_pts)
	var ch_base: Vector2 = LIVE_RENDER_CHANNEL + Vector2(0, -12)
	var ns_base: Vector2 = LIVE_RENDER_NORTH_SEA + Vector2(0, -12)
	var ch_step: float = maxf(_eng_ch.distance_to(_ita_ch), _eng_ch.distance_to(_pol_ch))
	var ns_step: float = maxf(_ger_ns.distance_to(_fra_ns), _ger_ns.distance_to(_jap_ns))
	if not _assert_cluster_near_live("(j) Channel", ch_c, LIVE_RENDER_CHANNEL, ch_base, ch_step):
		return
	if not _assert_cluster_near_live("(j) North Sea", ns_c, LIVE_RENDER_NORTH_SEA, ns_base, ns_step):
		return
	if _mr.has_method("_sea_province_poly_world") and _mr.has_method("_sea_poly_centroid"):
		var ch_poly: PackedVector2Array = _mr.call("_sea_province_poly_world", CHANNEL)
		var ns_poly: PackedVector2Array = _mr.call("_sea_province_poly_world", NORTH_SEA)
		if ch_poly.size() < 3 or ns_poly.size() < 3:
			_fail("(j) renderer-space sea poly missing")
			return
		var ch_pc: Vector2 = _mr.call("_sea_poly_centroid", ch_poly)
		var ns_pc: Vector2 = _mr.call("_sea_poly_centroid", ns_poly)
		if ch_pc.distance_to(LIVE_RENDER_CHANNEL) > 40.0:
			_fail("(j) Channel poly centroid %s not in renderer space (want %s)" % [str(ch_pc), str(LIVE_RENDER_CHANNEL)])
			return
		if ns_pc.distance_to(LIVE_RENDER_NORTH_SEA) > 40.0:
			_fail("(j) North Sea poly centroid %s not in renderer space (want %s)" % [str(ns_pc), str(LIVE_RENDER_NORTH_SEA)])
			return
		if ch_pc.distance_to(WORLD_CHANNEL) < 80.0:
			_fail("(j) Channel poly still in UNSCALED geo space %s" % str(ch_pc))
			return
	print(
		"  [INFO] HeadlessFleet2SharedSeaMarkerTest: live-space CH cluster %s vs renderer %s | NS cluster %s vs renderer %s"
		% [str(ch_c), str(LIVE_RENDER_CHANNEL), str(ns_c), str(LIVE_RENDER_NORTH_SEA)]
	)
	_pass("(j) cluster centres sit in renderer world (Channel %s / NS %s), not unscaled geo" % [str(ch_c), str(ns_c)])


func _apply_zoom(z: float) -> void:
	if _cam != null:
		_cam.zoom = Vector2(z, z)
		_cam.position = Vector2(7160.0, 1480.0)
		_cam.make_current()
	if _mr != null and _mr.has_method("_sync_unit_counter_scales"):
		_mr.call("_sync_unit_counter_scales", z)
	if _mr != null and _mr.has_method("_sync_sea_nation_fleet_offsets"):
		_mr.call("_sync_sea_nation_fleet_offsets", z)


func _test_k_spread_band_live_clicks() -> void:
	# Live renderer-world plates at the Play-fail zooms. A nearby GER land
	# chip reproduces the Home-band steal; drawn sea body must still win.
	var zooms: Array = [0.318, 0.40]
	for z_v in zooms:
		var z: float = float(z_v)
		_apply_zoom(z)
		if not _resolve_marker_coords():
			return
		var steal: Vector2 = _eng_ch + Vector2(36.0, 24.0)
		var land_icon: Node2D = _place_land_chip_at(MAGINOT, FID_GER_LAND, steal)
		if land_icon != null:
			land_icon.scale = Vector2(8.0, 8.0)
			land_icon.visible = true
		var rows: Array = [
			{"tag": ENG_TAG, "pos": _eng_ch, "fid": FID_ENG_FLEET, "own": false},
			{"tag": ITA_TAG, "pos": _ita_ch, "fid": FID_ITA_FLEET, "own": false},
			{"tag": POL_TAG, "pos": _pol_ch, "fid": FID_POL_FLEET, "own": false},
			{"tag": USA_TAG, "pos": _usa_ch, "fid": FID_USA_FLEET, "own": false},
			{"tag": GER_TAG, "pos": _ger_ns, "fid": FID_GER_FLEET, "own": true},
			{"tag": FRA_TAG, "pos": _fra_ns, "fid": FID_FRA_FLEET_SEA, "own": false},
			{"tag": JAP_TAG, "pos": _jap_ns, "fid": FID_JAP_FLEET, "own": false},
			{"tag": SOV_TAG, "pos": _sov_ns, "fid": FID_SOV_FLEET, "own": false},
		]
		for rec_v in rows:
			var rec: Dictionary = rec_v as Dictionary
			var tag: String = str(rec["tag"])
			var pos: Vector2 = rec["pos"] as Vector2
			var fid: String = str(rec["fid"])
			var own: bool = bool(rec["own"])
			if not _assert_plate_picks_own("(k) z=%.3f %s" % [z, tag], pos, fid, own):
				return
			if _selected_fid() == FID_GER_LAND:
				_fail("(k) z=%.3f %s opened GER land — Home-band steal" % [z, tag])
				return
		var gap: Vector2 = _ger_ns.lerp(_fra_ns, 0.38)
		if not _assert_plate_picks_own("(k) z=%.3f GER-nearest-gap" % z, gap, FID_GER_FLEET, true):
			return
		if _selected_fid() == "" or _info != null and _info.visible:
			_fail("(k) z=%.3f GER-nearest-gap opened the sea-zone inspector" % z)
			return
		if land_icon != null and is_instance_valid(land_icon):
			land_icon.visible = false
			if land_icon.get_parent() != null:
				land_icon.get_parent().remove_child(land_icon)
			land_icon.free()
			land_icon = null
		for extra_v in [
			{"name": "East Kent 711453", "pos": LIVE_RENDER_EAST_KENT},
			{"name": "old ENG chip", "pos": LIVE_OLD_ENG_CHIP},
		]:
			var extra: Dictionary = extra_v as Dictionary
			var epos: Vector2 = extra["pos"] as Vector2
			var ename := str(extra["name"])
			_reset_pick()
			var disk: Object = _mr.call("_pick_unit_formation_at_world", epos)
			var got := str(disk.formation_id) if disk != null and "formation_id" in disk else "?"
			var gtype := str(disk.formation_type) if disk != null and "formation_type" in disk else "?"
			if disk == null or not _is_channel_fid(got) or gtype != "fleet":
				_fail("(k) z=%.3f %s pick=%s/%s want a Channel fleet (not land)" % [z, ename, got, gtype])
				return
			if got == FID_GER_LAND or gtype == "division":
				_fail("(k) z=%.3f %s spilled to land %s" % [z, ename, got])
				return
	_apply_zoom(1.0)
	_pass("(k) all 8 plates at z0.318 and z0.40 open their fleet (GER own / others read-only); GER-nearest gap binds the fleet; East Kent / old ENG stay Channel")


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
		_lm.formations.erase(FID_JAP_FLEET)
		_lm.formations.erase(FID_SOV_FLEET)
		_lm.formations.erase(FID_ENG_FLEET)
		_lm.formations.erase(FID_ITA_FLEET)
		_lm.formations.erase(FID_POL_FLEET)
		_lm.formations.erase(FID_USA_FLEET)
		_lm.formations.erase(FID_FRA_FLEET_KOLN)
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
