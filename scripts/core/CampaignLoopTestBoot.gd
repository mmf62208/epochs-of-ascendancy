# scripts/core/CampaignLoopTestBoot.gd
## Shared world_accurate boot for campaign-loop harnesses.
## Same files as HeadlessPerf4LiveMultiAiDayTest, without packing geometry
## points (assault, war, and ownership do not read them).
class_name CampaignLoopTestBoot
extends RefCounted

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


static func boot(mm: Node, sm: Node, player_tag: String = "GER") -> bool:
	if mm == null or not _load_board(mm, player_tag):
		return false
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("set_player_country_tag"):
		LeaderManager.set_player_country_tag(player_tag)
	if sm != null:
		_boot_supply(mm, sm, player_tag)
	_reset_clock()
	return int(mm.get("province_count") if "province_count" in mm else 0) > 0 or _province_count(mm) > 1000


static func _province_count(mm: Node) -> int:
	if mm.has_method("get_all_provinces"):
		var provs: Variant = mm.call("get_all_provinces")
		if provs is Dictionary:
			return (provs as Dictionary).size()
	if "_provinces" in mm and mm._provinces is Dictionary:
		return (mm._provinces as Dictionary).size()
	return 0


static func _load_board(mm: Node, player_tag: String) -> bool:
	var base := load_json(BASE_PATH)
	var own_doc := load_json(OWN_PATH)
	if base.is_empty():
		return false
	var ProvScript: GDScript = load(PROV_SCRIPT) as GDScript
	var MapDataScript: GDScript = load(MAP_DATA_SCRIPT) as GDScript
	if ProvScript == null or MapDataScript == null:
		return false
	var owners: Dictionary = own_doc.get("owners", {}) as Dictionary
	var city := load_json(CITY_PATH)
	var city_rows: Dictionary = city.get("provinces", city) if city.get("provinces", null) is Dictionary else {}
	var countries := {
		player_tag: {"tag": player_tag, "name": player_tag, "capital_province_id": 0},
	}
	var provs: Dictionary = {}
	for row in base.get("provinces", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid := int(row.get("id", 0))
		if pid <= 0:
			continue
		var p = ProvScript.new()
		p.id = pid
		p.name = str(row.get("name", "Province %d" % pid))
		p.terrain = str(row.get("terrain", "plains"))
		p.domain = str(row.get("domain", "land"))
		var terr_l := str(p.terrain).strip_edges().to_lower()
		p.is_sea = terr_l in ["sea", "ocean", "water", "lake"] or str(p.domain).strip_edges().to_lower() in ["sea", "ocean", "naval"]
		var ot := str(owners.get(str(pid), "")).strip_edges().to_upper()
		if not ot.is_empty():
			p.owner_tag = ot
			p.controller_tag = ot
			if not countries.has(ot):
				countries[ot] = {"tag": ot, "name": ot, "capital_province_id": 0}
		if "infrastructure" in p:
			p.infrastructure = 5
		if not bool(p.is_sea):
			p.factories = 1
			if city_rows.has(str(pid)) and city_rows[str(pid)] is Dictionary:
				if int((city_rows[str(pid)] as Dictionary).get("tier", 0)) >= 2:
					p.factories = 2
		provs[pid] = p
	var adj = null
	if FileAccess.file_exists(ADJ_PATH):
		var AdjScr: GDScript = load("res://scripts/data/AdjacencySystem.gd") as GDScript
		if AdjScr != null:
			adj = AdjScr.new()
			if adj.has_method("load_adjacency"):
				adj.call("load_adjacency", ADJ_PATH)
			if adj.has_method("begin_bulk_registration"):
				adj.call("begin_bulk_registration")
			for pid2 in provs.keys():
				if adj.has_method("register_province"):
					adj.call("register_province", provs[pid2])
			if adj.has_method("end_bulk_registration"):
				adj.call("end_bulk_registration")
	var map_data = MapDataScript.new(provs, {}, adj, countries)
	mm.call("initialize_from_map_data", map_data)
	return _province_count(mm) > 1000


static func _boot_supply(mm: Node, sm: Node, player_tag: String) -> void:
	if not sm.has_method("build_network"):
		return
	var city := load_json(CITY_PATH)
	var city_rows: Variant = city.get("provinces", city)
	var provs: Dictionary = mm.call("get_all_provinces") if mm.has_method("get_all_provinces") else {}
	var adj: Variant = mm.call("get_adjacency_system") if mm.has_method("get_adjacency_system") else null
	var countries: Dictionary = {}
	if "_countries" in mm and mm._countries is Dictionary:
		countries = mm._countries
	sm.call("build_network", provs, countries, city_rows if city_rows is Dictionary else {}, adj, player_tag)
	if sm.has_method("end_day_roll_plan_deferral"):
		sm.call("end_day_roll_plan_deferral")


static func _reset_clock() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	TimeManager.paused = false
	TimeManager.scenario_start_year = 1936
	TimeManager.current_year = 1936
	TimeManager.current_month = 1
	TimeManager.current_day = 1
	TimeManager.current_hour = 0
	TimeManager.total_days_elapsed = 0
	TimeManager._accumulated_game_days = 0.0


static func make_division(fid: String, tag: String, station: int) -> void:
	if typeof(LeaderManager) == TYPE_NIL:
		return
	var scr: GDScript = load("res://scripts/formations/Formation.gd") as GDScript
	if scr == null:
		return
	var f = scr.new()
	f.formation_id = fid
	f.country_tag = tag
	f.formation_type = "division"
	f.design_id = "infantry_division"
	f.stationed_province_id = station
	f.strength = 1.0
	f.organization = 1.0
	f.readiness = 1.0
	f.name = "%s %s" % [tag, fid]
	LeaderManager.formations[fid] = f
