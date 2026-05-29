# scripts/map/SpecialSiteManager.gd
## Central loader and factory for SpecialSite definitions (data-driven).
##
## Loads all JSON definitions from res://data/map/special_sites/
## Provides creation of SpecialSite instances for provinces.

extends Node

var site_definitions: Dictionary = {}   # site_id -> raw JSON dict
var _loaded: bool = false

signal special_site_created(site: SpecialSite, province_id: int)


func _ready() -> void:
	load_all_definitions()


func load_all_definitions() -> void:
	site_definitions.clear()

	var dir := DirAccess.open("res://data/map/special_sites/")
	if dir == null:
		push_warning("SpecialSiteManager: Could not open data/map/special_sites/ directory")
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var path := "res://data/map/special_sites/" + file_name
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var json_text := file.get_as_text()
				var parser := JSON.new()
				if parser.parse(json_text) == OK:
					var data: Dictionary = parser.data
					if data.has("id"):
						site_definitions[data["id"]] = data
						print("SpecialSiteManager: Loaded definition '%s'" % data["id"])
					else:
						push_warning("SpecialSiteManager: JSON missing 'id' field: " + path)
				else:
					push_warning("SpecialSiteManager: Failed to parse JSON: " + path)
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()

	_loaded = true
	print("SpecialSiteManager: Loaded %d special site definitions" % site_definitions.size())


func is_loaded() -> bool:
	return _loaded


func get_site_definition(site_id: String) -> Dictionary:
	return site_definitions.get(site_id, {})


func get_all_site_ids() -> Array[String]:
	return site_definitions.keys()


## Creates a fully populated SpecialSite instance from a definition.
## Applies construction state, effects, and visual metadata.
func create_special_site(site_id: String, province_id: int, owner_tag: String) -> SpecialSite:
	var def := get_site_definition(site_id)
	if def.is_empty():
		push_error("SpecialSiteManager: Unknown site_id '%s'" % site_id)
		return null

	var site := SpecialSite.new()
	site.id = site_id
	site.province_id = province_id
	site.owner_tag = owner_tag

	# Site type
	if def.has("site_type"):
		var st := str(def["site_type"]).to_upper()
		match st:
			"PORT": site.site_type = SpecialSite.SiteType.PORT
			"AIRFIELD": site.site_type = SpecialSite.SiteType.AIRFIELD
			"NAVAL_SHIPYARD": site.site_type = SpecialSite.SiteType.NAVAL_SHIPYARD
			"FACTORY": site.site_type = SpecialSite.SiteType.FACTORY
			"OIL_REFINERY": site.site_type = SpecialSite.SiteType.OIL_REFINERY
			"ENERGY_PLANT": site.site_type = SpecialSite.SiteType.ENERGY_PLANT
			"ICBM_SITE": site.site_type = SpecialSite.SiteType.ICBM_SITE
			"RADAR_STATION": site.site_type = SpecialSite.SiteType.RADAR_STATION
			"FLAK_BATTERY": site.site_type = SpecialSite.SiteType.FLAK_BATTERY
			"MISSILE_DEFENSE": site.site_type = SpecialSite.SiteType.MISSILE_DEFENSE
			"SPECIAL_PROJECT": site.site_type = SpecialSite.SiteType.SPECIAL_PROJECT
			"FORTIFICATION": site.site_type = SpecialSite.SiteType.FORTIFICATION
			"BRIDGE": site.site_type = SpecialSite.SiteType.BRIDGE
			_: site.site_type = SpecialSite.SiteType.PORT

	# Tier
	site.tier = int(def.get("tier", 1))

	# Effects
	var effects := def.get("effects", {}) as Dictionary
	site.supply_bonus = float(effects.get("supply_throughput_bonus", 0))
	site.trade_capacity = float(effects.get("trade_capacity", 0))

	# Construction requirements (stored for reference / UI)
	if def.has("construction"):
		var cons := def["construction"] as Dictionary
		site.required_infra_level = int(cons.get("required_infra_level", 1))

	# Damage info
	if def.has("damage"):
		var dmg := def["damage"] as Dictionary
		site.max_damage_level = int(dmg.get("max_damage_level", 3))

	# Upgrade path (future: define in JSON)
	if def.has("upgrade_to"):
		site.upgrade_target_id = str(def["upgrade_to"])

	# Start as completed (when created via project completion)
	site.complete_construction()

	special_site_created.emit(site, province_id)
	return site


## Helper for debug / direct creation (starts under construction)
func create_special_site_under_construction(site_id: String, province_id: int, owner_tag: String) -> SpecialSite:
	var site := create_special_site(site_id, province_id, owner_tag)
	if site:
		site.start_construction()
	return site


## Returns list of site_ids that can currently be constructed in this province.
## Checks required_infra_level from the definition's "construction" section.
func get_constructible_sites_for_province(province: Province) -> Array[String]:
	if province == null:
		return []

	var available: Array[String] = []
	var current_infra := province.infrastructure

	for site_id in site_definitions.keys():
		var def := site_definitions[site_id] as Dictionary
		var cons := def.get("construction", {}) as Dictionary
		var req_infra := int(cons.get("required_infra_level", 1))

		if current_infra >= req_infra:
			# Basic terrain / feature requirements (extend as needed)
			var site_type_str := str(def.get("site_type", "")).to_lower()
			var can_build := true

			if site_type_str in ["port", "naval_shipyard"]:
				if not province.has_port and not province.has_feature("port") and not province.has_feature("harbor"):
					can_build = false

			if site_type_str == "airfield" and province.terrain in ["mountains", "jungle", "swamp"]:
				can_build = false

			if can_build:
				available.append(site_id)

	return available
