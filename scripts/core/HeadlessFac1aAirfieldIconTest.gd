extends SceneTree

## FAC-1a: airfield seeds + FacilityIconLayer (headless — NOT live Play).
## Duck-typed stubs only. This file never names Province / SpecialSite /
## ScenarioLoader as parse-time identifiers (those scripts fail to compile
## as -s dependencies when they mention autoloads).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFac1aAirfieldIconTest.gd

const SRC_LAYER := "res://scripts/map/FacilityIconLayer.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_LOADER := "res://scripts/core/ScenarioLoader.gd"
const SRC_ZOOM := "res://scripts/map/MapZoomLOD.gd"

const BONN := 710416
const KOELN := 710417
const LEV := 710418
const NEUSS := 710413

const SITE_AIRFIELD := 1
const STATE_COMPLETED := 2
const STATE_DAMAGED := 3
const STATE_DESTROYED := 4

const BOARDS: Array[String] = [
	"provinces_world_accurate",
	"provinces_pilot_europe_nuts3",
]


class DummyProv extends RefCounted:
	var id: int = 0
	var name: String = ""
	var is_sea: bool = false
	var owner_tag: String = "GER"
	var special_sites: Array = []
	var coordinates: Vector2 = Vector2.ZERO


class DummySite extends RefCounted:
	var id: String = ""
	var site_type: int = 1
	var tier: int = 1
	var province_id: int = 0
	var owner_tag: String = "GER"
	var construction_state: int = 2
	var damage_level: int = 0


var _failures := 0
var _layer: Node2D = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFac1aAirfieldIconTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFac1aAirfieldIconTest: ", msg)


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
	var nxt := src.find("\nfunc ", i + needle.length())
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessFac1aAirfieldIconTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFac1aAirfieldIconTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_needles()
	_test_tier4_def()
	_test_board_seeds_and_layer()
	_test_damaged_mapping()


func _test_source_needles() -> void:
	var layer := _read(SRC_LAYER)
	var ren := _read(SRC_REN)
	var ol := _read(SRC_OL)
	var loader := _read(SRC_LOADER)
	var zoom := _read(SRC_ZOOM)
	if "class_name FacilityIconLayer" not in layer:
		_fail("FacilityIconLayer class_name missing")
	else:
		_pass("FacilityIconLayer class_name")
	if "draw_texture_rect" not in layer:
		_fail("layer must use draw_texture_rect")
	else:
		_pass("draw_texture_rect present")
	if "Line2D.new" in layer or "add_child" in _slice_func(layer, "_draw"):
		_fail("layer _draw must not spawn Line2D / children")
	else:
		_pass("no Line2D children in _draw")
	if "rebuild_icon_list" not in _slice_func(layer, "_process"):
		_pass("_process does not rebuild list")
	else:
		_fail("_process must not rebuild the icon list")
	if "func set_show_facilities" not in layer:
		_fail("set_show_facilities missing")
	else:
		_pass("set_show_facilities present")
	if "var show_facilities: bool = true" not in layer:
		_fail("show_facilities must default true")
	else:
		_pass("show_facilities default true")
	if "KEY_P" not in layer:
		_fail("KEY_P toggle missing on layer")
	else:
		_pass("KEY_P on layer (MapRenderer input untouched)")
	if "_setup_facility_icon_layer" not in ren:
		_fail("MapRenderer missing _setup_facility_icon_layer")
	else:
		_pass("MapRenderer creates FacilityIconLayer")
	if 'ol_res.call("set_map_mode_for_glyphs", m)' not in ren:
		_fail("RH-1 set_map_mode glyph hook was edited away")
	else:
		_pass("RH-1 set_map_mode glyph hook intact")
	if "func rebuild_sites_layer" not in ol:
		_fail("rebuild_sites_layer missing (must stay)")
	else:
		_pass("InfrastructureOverlayLayer.rebuild_sites_layer untouched")
	if "apply_seeded_special_sites_to_provinces" not in loader:
		_fail("loader missing apply_seeded_special_sites_to_provinces")
	else:
		_pass("loader seeds AIRFIELD via project_sites")
	if "func site_marker_min_zoom_for_board" not in zoom:
		_fail("MapZoomLOD site threshold missing")
	else:
		_pass("MapZoomLOD thresholds not required to change")
	var set_mode := _slice_func(ren, "set_map_mode")
	if "FacilityIconLayer" in set_mode:
		_fail("set_map_mode must not mention FacilityIconLayer (RH-1 lines stay)")
	else:
		_pass("set_map_mode body has no FacilityIconLayer hook")


func _test_tier4_def() -> void:
	if not FileAccess.file_exists("res://data/map/special_sites/airfield_tier_4.json"):
		_fail("airfield_tier_4.json missing")
		return
	var f := FileAccess.open("res://data/map/special_sites/airfield_tier_4.json", FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(txt) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_fail("airfield_tier_4.json parse")
		return
	var d: Dictionary = parser.data
	if str(d.get("id", "")) != "airfield_tier_4" or int(d.get("tier", 0)) != 4:
		_fail("airfield_tier_4 schema")
	else:
		_pass("airfield_tier_4.json tier=4")
	if str(d.get("site_type", "")).to_lower() != "airfield":
		_fail("airfield_tier_4 site_type")
	else:
		_pass("airfield_tier_4 site_type=airfield")


func _dummy_centroids() -> Dictionary:
	return {
		BONN: Vector2(100, 100),
		LEV: Vector2(140, 60),
		KOELN: Vector2(120, 80),
		NEUSS: Vector2(80, 70),
	}


func _state_from_record(rec: Dictionary) -> int:
	var st := str(rec.get("construction_state", "COMPLETED")).strip_edges().to_upper()
	if st == "DAMAGED":
		return STATE_DAMAGED
	if st == "DESTROYED":
		return STATE_DESTROYED
	if st == "NOT_BUILT":
		return 0
	return STATE_COMPLETED


func _seed_provinces_from_json(board: String) -> Dictionary:
	var dest: Dictionary = {}
	for pid in [BONN, LEV, KOELN, NEUSS]:
		var p := DummyProv.new()
		p.id = int(pid)
		p.name = "FAC1a %d" % int(pid)
		p.is_sea = false
		p.owner_tag = "GER"
		p.special_sites = []
		dest[int(pid)] = p
	var path := "res://data/%s/project_sites.json" % board
	if not FileAccess.file_exists(path):
		_fail("%s missing project_sites.json" % board)
		return dest
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(txt) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_fail("%s project_sites.json parse" % board)
		return dest
	var sites: Variant = (parser.data as Dictionary).get("sites", [])
	if typeof(sites) != TYPE_ARRAY:
		_fail("%s project_sites.sites not array" % board)
		return dest
	for rec_v in sites:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var pid := int(rec.get("province_id", 0))
		if not dest.has(pid):
			continue
		var p: DummyProv = dest[pid] as DummyProv
		if p == null:
			continue
		var site := DummySite.new()
		site.id = str(rec.get("site_id", "airfield_tier_%d" % int(rec.get("tier", 1))))
		site.province_id = pid
		site.owner_tag = "GER"
		site.site_type = SITE_AIRFIELD
		site.tier = clampi(int(rec.get("tier", 1)), 1, 4)
		site.construction_state = _state_from_record(rec)
		site.damage_level = int(rec.get("damage_level", 0))
		p.special_sites.append(site)
	return dest


func _airfield_count(provs: Dictionary) -> int:
	var n := 0
	for pid_v in provs.keys():
		var p: DummyProv = provs[pid_v] as DummyProv
		if p == null:
			continue
		for site_v in p.special_sites:
			var site: DummySite = site_v as DummySite
			if site != null and int(site.site_type) == SITE_AIRFIELD:
				n += 1
	return n


func _expect_tiers(provs: Dictionary, board: String) -> void:
	var want: Dictionary = {BONN: 1, LEV: 2, KOELN: 3, NEUSS: 4}
	for pid in want.keys():
		if not provs.has(pid):
			_fail("%s missing province %d" % [board, int(pid)])
			continue
		var p: DummyProv = provs[pid] as DummyProv
		if p == null:
			_fail("%s pid %d not a dummy province" % [board, int(pid)])
			continue
		var found := false
		for site_v in p.special_sites:
			var site: DummySite = site_v as DummySite
			if site == null or int(site.site_type) != SITE_AIRFIELD:
				continue
			found = true
			if int(site.tier) != int(want[pid]):
				_fail("%s pid %d tier=%d want=%d" % [board, int(pid), int(site.tier), int(want[pid])])
			else:
				_pass("%s pid %d AIRFIELD tier %d" % [board, int(pid), int(site.tier)])
		if not found:
			_fail("%s pid %d has no AIRFIELD site" % [board, int(pid)])


func _test_board_seeds_and_layer() -> void:
	var layer_script: Script = load(SRC_LAYER) as Script
	if layer_script == null:
		_fail("could not load FacilityIconLayer.gd")
		return
	if layer_script is GDScript and not (layer_script as GDScript).can_instantiate():
		_fail("FacilityIconLayer.gd cannot instantiate")
		return
	_layer = (layer_script as GDScript).new() as Node2D
	if _layer == null:
		_fail("could not instantiate FacilityIconLayer")
		return
	root.add_child(_layer)
	for board in BOARDS:
		var provs := _seed_provinces_from_json(board)
		var n := _airfield_count(provs)
		if n != 4:
			_fail("%s apply count=%d want 4" % [board, n])
		else:
			_pass("%s applied 4 airfield sites" % board)
		_expect_tiers(provs, board)
		var board_n := 3520 if board == "provinces_world_accurate" else 1514
		_layer.call("setup_for_test", provs, _dummy_centroids(), board_n)
		var icons: Array = _layer.call("get_icon_list")
		if icons.size() != 4:
			_fail("%s layer icons=%d want 4" % [board, icons.size()])
			continue
		_pass("%s layer built 4 entries" % board)
		var seen: Dictionary = {}
		for rec_v in icons:
			var rec: Dictionary = rec_v
			var lv: int = int(rec.get("level", 0))
			var key: String = str(rec.get("tex_key", ""))
			seen[lv] = key
			if not key.begins_with("airfield_l%d_intact" % lv):
				_fail("%s tex_key=%s for level %d" % [board, key, lv])
		for lv2 in [1, 2, 3, 4]:
			if not seen.has(lv2):
				_fail("%s missing level %d in icon list" % [board, lv2])
		if seen.size() == 4:
			_pass("%s levels 1-4 + intact tex keys" % board)
		var min_z: float = 0.62 if board_n >= 3000 else 0.38
		_layer.call("set_test_map_mode", "political")
		_layer.call("set_show_facilities", true)
		_layer.call("set_test_zoom", min_z - 0.10)
		var hidden_n: int = int(_layer.call("count_icons_that_would_draw"))
		if hidden_n != 0:
			_fail("%s below site zoom drew %d" % [board, hidden_n])
		else:
			_pass("%s hidden below site zoom %.2f" % [board, min_z])
		_layer.call("set_test_zoom", min_z + 0.08)
		var mid_n: int = int(_layer.call("count_icons_that_would_draw"))
		if mid_n != 4:
			_fail("%s political mid zoom drew %d" % [board, mid_n])
		else:
			_pass("%s visible at operational zoom" % board)
		_layer.call("set_test_map_mode", "diplomacy")
		if int(_layer.call("count_icons_that_would_draw")) != 4:
			_fail("%s diplomacy hid icons" % board)
		else:
			_pass("%s visible in diplomacy" % board)
		_layer.call("set_test_map_mode", "resources")
		if int(_layer.call("count_icons_that_would_draw")) != 0:
			_fail("%s resources mode still drawing" % board)
		else:
			_pass("%s hidden in resources (F9)" % board)
		_layer.call("set_test_map_mode", "political")
		_layer.call("set_show_facilities", false)
		if int(_layer.call("count_icons_that_would_draw")) != 0:
			_fail("%s toggle off still drawing" % board)
		else:
			_pass("%s toggle off → 0 drawn" % board)
		_layer.call("set_show_facilities", true)
		var before: int = int(_layer.call("get_rebuild_count"))
		for z in [0.20, 0.40, 0.70, 1.10, 1.55, 0.80]:
			_layer.call("set_test_zoom", z)
		var after: int = int(_layer.call("get_rebuild_count"))
		if after != before:
			_fail("%s zoom rebuilt list %d → %d" % [board, before, after])
		else:
			_pass("%s zoom did not rebuild icon list" % board)


func _test_damaged_mapping() -> void:
	if _layer == null or not is_instance_valid(_layer):
		_fail("no FacilityIconLayer instance for damaged mapping")
		return
	var site := DummySite.new()
	site.site_type = SITE_AIRFIELD
	site.tier = 2
	site.damage_level = 0
	site.construction_state = STATE_COMPLETED
	var intact := str(_layer.call("visual_state_for_site", site))
	if intact != "intact":
		_fail("completed undamaged mapped to %s" % intact)
	else:
		_pass("completed + damage_level=0 → intact")
	site.damage_level = 2
	var dmg := str(_layer.call("visual_state_for_site", site))
	if dmg != "damaged":
		_fail("damage_level>0 mapped to %s" % dmg)
	else:
		_pass("damage_level>0 → damaged")
	site.damage_level = 0
	site.construction_state = STATE_DAMAGED
	var st := str(_layer.call("visual_state_for_site", site))
	if st != "damaged":
		_fail("construction_state DAMAGED mapped to %s" % st)
	else:
		_pass("construction_state DAMAGED → damaged")
	var key := str(_layer.call("texture_key_for_level", 3, "damaged"))
	if key != "airfield_l3_damaged":
		_fail("texture key damaged=%s" % key)
	else:
		_pass("texture key maps damaged (art still intact at draw)")
	_layer.queue_free()
	_layer = null
