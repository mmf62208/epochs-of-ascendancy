# scripts/formations/FormationSpawner.gd
class_name FormationSpawner
extends Node

const TEST_FORMATION_TYPES: Array[String] = [
	Formation.TYPE_DIVISION,
	Formation.TYPE_DIVISION,
	Formation.TYPE_FLEET,
	Formation.TYPE_AIR_WING,
	Formation.TYPE_GARRISON,
	Formation.TYPE_TASK_FORCE,
]

## Land-capable formation types (station must be owned land for playable OOB).
const LAND_FORMATION_TYPES: Array[String] = [
	Formation.TYPE_DIVISION,
	Formation.TYPE_GARRISON,
]


## Pure station resolver (mirrors tools/map_generation/lib/formation_station_resolver.py).
## Prefer capital when it is in owned_land_ids; else first sorted owned land; else -1.
## Rejects non-positive ids. Callers must only pass land (non-sea) owned ids.
static func resolve_station_province_id(capital_id: int, owned_land_ids: Array) -> int:
	var owned: Array[int] = []
	var seen: Dictionary = {}
	for raw in owned_land_ids:
		var pid := int(raw)
		if pid <= 0 or seen.has(pid):
			continue
		seen[pid] = true
		owned.append(pid)
	owned.sort()
	if capital_id > 0 and seen.has(capital_id):
		return capital_id
	if not owned.is_empty():
		return owned[0]
	return -1


## Deterministic station list for `count` formations (capital-first spread across owned land).
static func resolve_stations_for_count(count: int, capital_id: int, owned_land_ids: Array) -> Array[int]:
	return resolve_stations_hoi_deploy(count, capital_id, owned_land_ids, [], [])


## HOI-style deploy: front_reserve → capital → key hubs → border → remaining owned land.
## Mirrors tools/map_generation/lib/formation_station_resolver.resolve_stations_hoi_deploy.
## When formation_types is non-empty, land slots (division|garrison) fill from ordered;
## naval/air use capital / first non-reserved so they do not consume front_reserve pids.
static func resolve_stations_hoi_deploy(
	count: int,
	capital_id: int,
	owned_land_ids: Array,
	key_provinces: Array = [],
	border_provinces: Array = [],
	front_reserve: Array = [],
	formation_types: Array = [],
) -> Array[int]:
	var out: Array[int] = []
	if count <= 0:
		return out
	var owned: Array[int] = []
	var owned_seen: Dictionary = {}
	for raw in owned_land_ids:
		var pid := int(raw)
		if pid <= 0 or owned_seen.has(pid):
			continue
		owned_seen[pid] = true
		owned.append(pid)
	if owned.is_empty():
		for _i in count:
			out.append(-1)
		return out
	var ordered: Array[int] = []
	var used: Dictionary = {}
	var reserved: Dictionary = {}
	for raw in front_reserve:
		var rpid := int(raw)
		if rpid > 0 and owned_seen.has(rpid) and not used.has(rpid):
			ordered.append(rpid)
			used[rpid] = true
			reserved[rpid] = true
	if capital_id > 0 and owned_seen.has(capital_id) and not used.has(capital_id):
		ordered.append(capital_id)
		used[capital_id] = true
	for raw in key_provinces:
		var kpid := int(raw)
		if kpid > 0 and owned_seen.has(kpid) and not used.has(kpid):
			ordered.append(kpid)
			used[kpid] = true
	for raw in border_provinces:
		var bpid := int(raw)
		if bpid > 0 and owned_seen.has(bpid) and not used.has(bpid):
			ordered.append(bpid)
			used[bpid] = true
	var rest: Array[int] = []
	for pid in owned:
		if not used.has(pid):
			rest.append(pid)
	rest.sort()
	for pid in rest:
		if not used.has(pid):
			ordered.append(pid)
			used[pid] = true
	if ordered.is_empty():
		for _i in count:
			out.append(-1)
		return out
	var non_land := -1
	if capital_id > 0 and owned_seen.has(capital_id):
		non_land = capital_id
	else:
		for pid in ordered:
			if not reserved.has(pid):
				non_land = pid
				break
		if non_land <= 0:
			non_land = ordered[0]
	if not formation_types.is_empty():
		var land_cursor := 0
		var n_types := formation_types.size()
		for i in count:
			var ftype := str(formation_types[i % n_types]).strip_edges().to_lower()
			var is_land := false
			for lt in LAND_FORMATION_TYPES:
				if ftype == str(lt).strip_edges().to_lower():
					is_land = true
					break
			if is_land:
				out.append(ordered[land_cursor % ordered.size()])
				land_cursor += 1
			else:
				out.append(non_land)
		return out
	for i in count:
		out.append(ordered[i % ordered.size()])
	return out


## Collect owned land province ids for a country from MapManager (skips sea).
static func collect_owned_land_ids(country_tag: String) -> Array[int]:
	var out: Array[int] = []
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() or typeof(MapManager) == TYPE_NIL:
		return out
	if MapManager.has_method("get_provinces_by_owner"):
		for pidv in MapManager.get_provinces_by_owner(tag):
			var pid := int(pidv)
			var pp: Province = MapManager.get_province(pid) if MapManager.has_method("get_province") else null
			if pp == null:
				continue
			if bool(pp.is_sea):
				continue
			out.append(pid)
		out.sort()
		return out
	if MapManager.has_method("get_all_provinces"):
		var aps = MapManager.get_all_provinces()
		if typeof(aps) == TYPE_DICTIONARY:
			for pidv in aps.keys():
				var pp: Province = aps[pidv]
				if pp == null:
					continue
				if str(pp.owner_tag).strip_edges().to_upper() != tag:
					continue
				if bool(pp.is_sea):
					continue
				out.append(int(pp.id))
		out.sort()
	return out


func spawn_test_formations_for_country(
	country_tag: String,
	count: int = 6,
	capital_province_id: int = -1,
	owned_land_override: Array = [],
	key_provinces: Array = [],
	border_provinces: Array = [],
	front_reserve: Array = [],
) -> void:
	if country_tag.is_empty() or count <= 0:
		return

	var tag := country_tag.strip_edges().to_upper()
	# Prefer explicit owned land from ScenarioLoader (MapManager may not be initialized yet).
	var owned_land: Array[int] = []
	if not owned_land_override.is_empty():
		for raw in owned_land_override:
			var pid := int(raw)
			if pid > 0:
				owned_land.append(pid)
		owned_land.sort()
	else:
		owned_land = collect_owned_land_ids(tag)
	# HOI deploy: front_reserve first, then capital + hubs + borders; land slots from type cycle.
	var stations: Array[int] = resolve_stations_hoi_deploy(
		count,
		capital_province_id,
		owned_land,
		key_provinces,
		border_provinces,
		front_reserve,
		TEST_FORMATION_TYPES
	)
	var land_stationed := 0
	var invalid_stations := 0

	for i in count:
		var formation := Formation.new()
		formation.formation_id = "%s_formation_%d" % [tag, i]
		formation.country_tag = tag
		formation.formation_type = TEST_FORMATION_TYPES[i % TEST_FORMATION_TYPES.size()]
		formation.organization = 1.0
		formation.readiness = 1.0
		formation.strength = 1.0

		match formation.formation_type:
			Formation.TYPE_DIVISION:
				formation.name = "Division %d" % i
				var land_missions = [Formation.LAND_MISSION_ASSAULT, Formation.LAND_MISSION_DEFEND, Formation.LAND_MISSION_PATROL, Formation.LAND_MISSION_ARTILLERY_PREP]
				formation.current_land_mission = land_missions[i % land_missions.size()]
				formation.mission_intensity = 0.8 + (i % 3) * 0.3
				if tag == "GER":
					formation.design_id = "panzer_iii_j_medium" if i % 2 == 0 else "tiger_i_heavy_tank"
				elif tag == "ENG" or tag == "USA":
					formation.design_id = "m4_sherman_medium_tank" if i % 2 == 0 else "m4a3e8_sherman_medium"
				elif tag == "FRA":
					formation.design_id = "somua_s35_medium" if i % 2 == 0 else "tiger_i_heavy_tank"
				elif tag == "SOV":
					formation.design_id = "t34_medium_tank" if i % 2 == 0 else "sov_armor_1936"
				elif tag == "ITA":
					formation.design_id = "cv33_tankette" if i % 2 == 0 else "ita_armor_1936"
				elif tag == "JAP":
					formation.design_id = "jap_armor_1936" if i % 2 == 0 else "m3_stuart_light_tank"
				elif tag == "POL":
					formation.design_id = "pol_armor_1936" if i % 2 == 0 else "m3_stuart_light_tank"
				else:
					formation.design_id = "m3_stuart_light_tank"
			Formation.TYPE_FLEET:
				formation.name = "Fleet %d" % i
				formation.current_naval_order = Formation.NAVAL_ORDER_SEARCH_PATROL if i % 2 == 0 else Formation.NAVAL_ORDER_SEARCH_AND_DESTROY
				if tag == "GER":
					formation.naval_design_id = "type_viic_uboat"
				elif tag == "ENG":
					formation.naval_design_id = "king_george_v_class_bb"
				elif tag == "USA":
					formation.naval_design_id = "fletcher_class_destroyer"
				elif tag == "SOV":
					formation.naval_design_id = "kirov_class_1936"
				elif tag == "ITA":
					formation.naval_design_id = "ita_frigate_1936"
				elif tag == "JAP":
					formation.naval_design_id = "yamato_battleship" if i % 2 == 0 else "akagi_carrier_1936"
				elif tag == "POL":
					formation.naval_design_id = "pol_frigate_1936"
				else:
					formation.naval_design_id = "v_class_destroyer"
			Formation.TYPE_AIR_WING:
				formation.name = "Air Wing %d" % i
				var air_missions = [Formation.AIR_MISSION_RECON, Formation.AIR_MISSION_CLOSE_AIR_SUPPORT, Formation.AIR_MISSION_INTERDICTION, Formation.AIR_MISSION_STRATEGIC_BOMBING, Formation.AIR_MISSION_AIR_SUPERIORITY, Formation.AIR_MISSION_NAVAL_STRIKE]
				formation.current_air_mission = air_missions[i % air_missions.size()]
				formation.mission_intensity = 0.7 + (i % 4) * 0.35
				if tag == "GER":
					formation.air_design_id = "bf109g_fighter" if i % 2 == 0 else "b17g_fortress"
				elif tag == "USA":
					formation.air_design_id = "p51d_mustang" if i % 2 == 0 else "b17g_fortress"
				elif tag == "ENG":
					formation.air_design_id = "spitfire_mk9_fighter"
				elif tag == "SOV":
					formation.air_design_id = "sov_fighter_1936"
				elif tag == "ITA":
					formation.air_design_id = "ita_fighter_1936"
				elif tag == "JAP":
					formation.air_design_id = "a6m_zero_fighter"
				elif tag == "POL":
					formation.air_design_id = "pol_fighter_1936"
				else:
					formation.air_design_id = "bf109_fighter"
			Formation.TYPE_GARRISON:
				formation.name = "Garrison %d" % i
				formation.current_land_mission = Formation.LAND_MISSION_GARRISON
				formation.design_id = "infantry_m1_garand"
			Formation.TYPE_TASK_FORCE:
				formation.name = "Naval Task Force %d" % i
				var orders = [Formation.NAVAL_ORDER_CONVOY_DUTY, Formation.NAVAL_ORDER_AMBUSH, Formation.NAVAL_ORDER_MINELAY, Formation.NAVAL_ORDER_ASW]
				formation.current_naval_order = orders[i % orders.size()]
				if tag == "GER":
					formation.naval_design_id = "type_viic_uboat"
				elif tag == "JAP":
					formation.naval_design_id = "yamato_battleship"
				elif tag in ["SOV", "ITA", "POL", "ENG", "USA", "FRA"]:
					formation.naval_design_id = "fletcher_class_destroyer"
				else:
					formation.naval_design_id = "v_class_destroyer"
			_:
				formation.name = "Formation %d" % i

		# Owned-land station (capital preferred). No obsolete demo pids (GER→2 etc.).
		var station_id := stations[i] if i < stations.size() else resolve_station_province_id(capital_province_id, owned_land)
		if station_id > 0:
			formation.stationed_province_id = station_id
			if formation.formation_type in LAND_FORMATION_TYPES:
				land_stationed += 1
		else:
			formation.stationed_province_id = -1
			invalid_stations += 1

		LeaderManager.register_formation(formation)

	print(
		"Spawned %d test formations for %s (owned_land=%d capital=%d land_stationed=%d invalid=%d primary_station=%d)"
		% [
			count,
			tag,
			owned_land.size(),
			capital_province_id,
			land_stationed,
			invalid_stations,
			stations[0] if not stations.is_empty() else -1,
		]
	)
