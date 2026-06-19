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


func spawn_test_formations_for_country(country_tag: String, count: int = 6) -> void:
	if country_tag.is_empty() or count <= 0:
		return

	for i in count:
		var formation := Formation.new()
		formation.formation_id = "%s_formation_%d" % [country_tag, i]
		formation.country_tag = country_tag
		formation.formation_type = TEST_FORMATION_TYPES[i % TEST_FORMATION_TYPES.size()]
		formation.organization = 1.0
		formation.readiness = 1.0
		formation.strength = 1.0

		match formation.formation_type:
			Formation.TYPE_DIVISION:
				formation.name = "Division %d" % i
				var land_missions = [Formation.LAND_MISSION_ASSAULT, Formation.LAND_MISSION_DEFEND, Formation.LAND_MISSION_PATROL, Formation.LAND_MISSION_ARTILLERY_PREP]
				formation.current_land_mission = land_missions[i % land_missions.size()]
				formation.mission_intensity = 0.8 + (i % 3) * 0.3  # vary aggressiveness
				# Assign real design for playtest (use verified existing from data/unit_templates/ for valid OOB, all 14 nations)
				if country_tag == "GER":
					formation.design_id = "panzer_iii_j_medium" if i % 2 == 0 else "tiger_i_heavy_tank"
				elif country_tag == "ENG" or country_tag == "USA":
					formation.design_id = "m4_sherman_medium_tank" if i % 2 == 0 else "m4a3e8_sherman_medium"
				elif country_tag == "FRA":
					formation.design_id = "somua_s35_medium" if i % 2 == 0 else "tiger_i_heavy_tank"
				elif country_tag == "SOV":
					formation.design_id = "t34_medium_tank" if i % 2 == 0 else "sov_armor_1936"
				elif country_tag == "ITA":
					formation.design_id = "cv33_tankette" if i % 2 == 0 else "ita_armor_1936"
				elif country_tag == "JAP":
					formation.design_id = "jap_armor_1936" if i % 2 == 0 else "m3_stuart_light_tank"
				elif country_tag == "POL":
					formation.design_id = "pol_armor_1936" if i % 2 == 0 else "m3_stuart_light_tank"
				else:
					formation.design_id = "m3_stuart_light_tank"  # fallback for FIN/NOR/SWE/DNK/NLD/BEL
			Formation.TYPE_FLEET:
				formation.name = "Fleet %d" % i
				formation.current_naval_order = Formation.NAVAL_ORDER_SEARCH_PATROL if i % 2 == 0 else Formation.NAVAL_ORDER_SEARCH_AND_DESTROY
				if country_tag == "GER":
					formation.naval_design_id = "type_viic_uboat"  # sub real
				elif country_tag == "ENG":
					formation.naval_design_id = "king_george_v_class_bb"  # bb real
				elif country_tag == "USA":
					formation.naval_design_id = "fletcher_class_destroyer"
				elif country_tag == "SOV":
					formation.naval_design_id = "kirov_class_1936"
				elif country_tag == "ITA":
					formation.naval_design_id = "ita_frigate_1936"
				elif country_tag == "JAP":
					formation.naval_design_id = "yamato_battleship" if i % 2 == 0 else "akagi_carrier_1936"
				elif country_tag == "POL":
					formation.naval_design_id = "pol_frigate_1936"
				else:
					formation.naval_design_id = "v_class_destroyer"  # small nations
			Formation.TYPE_AIR_WING:
				formation.name = "Air Wing %d" % i
				var air_missions = [Formation.AIR_MISSION_RECON, Formation.AIR_MISSION_CLOSE_AIR_SUPPORT, Formation.AIR_MISSION_INTERDICTION, Formation.AIR_MISSION_STRATEGIC_BOMBING, Formation.AIR_MISSION_AIR_SUPERIORITY, Formation.AIR_MISSION_NAVAL_STRIKE]
				formation.current_air_mission = air_missions[i % air_missions.size()]
				formation.mission_intensity = 0.7 + (i % 4) * 0.35  # intensity for round-the-clock etc.
				if country_tag == "GER":
					formation.air_design_id = "bf109g_fighter" if i % 2 == 0 else "b17g_fortress"
				elif country_tag == "USA":
					formation.air_design_id = "p51d_mustang" if i % 2 == 0 else "b17g_fortress"
				elif country_tag == "ENG":
					formation.air_design_id = "spitfire_mk9_fighter"
				elif country_tag == "SOV":
					formation.air_design_id = "sov_fighter_1936"
				elif country_tag == "ITA":
					formation.air_design_id = "ita_fighter_1936"
				elif country_tag == "JAP":
					formation.air_design_id = "a6m_zero_fighter"
				elif country_tag == "POL":
					formation.air_design_id = "pol_fighter_1936"
				else:
					formation.air_design_id = "bf109_fighter"  # minors fallback
			Formation.TYPE_GARRISON:
				formation.name = "Garrison %d" % i
				formation.current_land_mission = Formation.LAND_MISSION_GARRISON
				formation.design_id = "infantry_m1_garand"
			Formation.TYPE_TASK_FORCE:
				formation.name = "Naval Task Force %d" % i
				var orders = [Formation.NAVAL_ORDER_CONVOY_DUTY, Formation.NAVAL_ORDER_AMBUSH, Formation.NAVAL_ORDER_MINELAY, Formation.NAVAL_ORDER_ASW]
				formation.current_naval_order = orders[i % orders.size()]
				if country_tag == "GER":
					formation.naval_design_id = "type_viic_uboat"
				elif country_tag == "JAP":
					formation.naval_design_id = "yamato_battleship"
				elif country_tag in ["SOV", "ITA", "POL", "ENG", "USA", "FRA"]:
					formation.naval_design_id = "fletcher_class_destroyer"
				else:
					formation.naval_design_id = "v_class_destroyer"
			_:
				formation.name = "Formation %d" % i

		LeaderManager.register_formation(formation)

		# Set initial stationed province based on country for playtest (uses MapManager if available, falls to demo pids)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
			var aps = MapManager.get_all_provinces()
			for pidv in aps:
				var pp: Province = aps[pidv]
				if pp and pp.owner_tag == country_tag and not pp.is_sea:
					formation.stationed_province_id = pp.id
					break
		if formation.stationed_province_id <= 0:
			# demo fallback pids from history (e.g. GER around 2, ENG 5, etc)
			var demo_pids = {"GER": 2, "FRA": 4, "ENG": 5, "USA": 6, "ITA": 21, "SOV": 8, "JAP": 9, "POL":19, "FIN":40, "NOR":47, "SWE":63, "DNK":64, "NLD":48, "BEL":49}
			formation.stationed_province_id = demo_pids.get(country_tag, 1)

	print("Spawned %d test formations for %s (with designs and stationed provinces for playtest)" % [count, country_tag])
