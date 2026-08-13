# scripts/scenarios/ScenarioFactorySpawner.gd
class_name ScenarioFactorySpawner
extends Node

const DEFAULT_SCENARIO := "1936"
const TOP_INDUSTRIAL_TAGS: Array[String] = ["USA", "GER", "ENG", "SOV", "JAP"]
const TOP_NAVAL_SHIPYARD_TAGS: Array[String] = ["USA", "ENG", "JAP"]
const SECOND_TIER_NAVAL_TAGS: Array[String] = ["GER", "ITA", "FRA"]
const DEFAULT_NAVAL_POWER_TAGS: Array[String] = ["USA", "ENG", "JAP", "GER", "ITA", "FRA"]


func spawn_factories_for_scenario(
	scenario_name: String = DEFAULT_SCENARIO,
	scenario_loader: ScenarioLoader = null,
) -> void:
	var path := "res://data/scenarios/%s.json" % scenario_name
	if not ResourceLoader.exists(path):
		push_warning("ScenarioFactorySpawner: scenario file not found: " + path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ScenarioFactorySpawner: could not open: " + path)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ScenarioFactorySpawner: invalid JSON at " + path)
		return

	var data: Dictionary = parsed
	var factory_manager := _factory_manager()
	if factory_manager == null:
		push_warning("ScenarioFactorySpawner: FactoryManager autoload not available")
		return

	if scenario_loader != null:
		factory_manager.set_province_lookup(func(province_id: int) -> Province:
			return scenario_loader.provinces.get(province_id) as Province
		)

	if not data.has("countries"):
		push_warning("ScenarioFactorySpawner: no countries block in " + path)
		return

	var factories_created := 0
	var shipyards_created := 0
	var provinces_touched := 0
	var per_tag_summary: Dictionary = {}

	for country in _iter_countries(data):
		var country_tag := str(country.get("tag", "")).strip_edges().to_upper()
		if country_tag.is_empty():
			continue

		var is_major_power := bool(country.get("major_power", _default_major_power(country_tag)))
		var is_naval_power := bool(country.get("naval_power", _default_naval_power(country_tag)))
		var industrial_provinces := resolve_industrial_provinces(
			country, country_tag, scenario_loader
		)
		if industrial_provinces.is_empty():
			continue

		var base_factories := _base_factory_count(country, is_major_power, country_tag)
		var province_count := maxi(industrial_provinces.size(), 1)
		var factories_per_province: int = maxi(
			1, int(float(base_factories) / float(province_count)),
		)

		var tag_factories := 0
		var tag_shipyards := 0
		for province_id in industrial_provinces:
			var created: Array[Factory] = factory_manager.register_factories_for_province(
				province_id, country_tag, factories_per_province,
			)
			tag_factories += created.size()
			factories_created += created.size()
			provinces_touched += 1

		if is_naval_power:
			var shipyard_pids := resolve_shipyard_provinces(
				country_tag, industrial_provinces, scenario_loader
			)
			var shipyard_levels := _shipyard_levels_for_country(country_tag)
			for province_id in shipyard_pids:
				var shipyard: Factory = factory_manager.create_shipyard_for_province(
					province_id, country_tag, shipyard_levels,
				)
				if shipyard != null:
					tag_shipyards += 1
					shipyards_created += 1

		per_tag_summary[country_tag] = {
			"factories": tag_factories,
			"shipyards": tag_shipyards,
			"industrial_pids": industrial_provinces.duplicate(),
		}

	print(
		"ScenarioFactorySpawner: %s — %d factories, %d shipyards across %d province entries"
		% [scenario_name, factories_created, shipyards_created, provinces_touched]
	)
	# Evidence for majors (owned-board industrial bootstrap)
	var major_bits: PackedStringArray = []
	for mt in ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]:
		var s: Dictionary = per_tag_summary.get(mt, {})
		if s.is_empty():
			major_bits.append("%s fac=0 sy=0" % mt)
		else:
			major_bits.append(
				"%s fac=%d sy=%d pids=%s"
				% [mt, int(s.get("factories", 0)), int(s.get("shipyards", 0)), str(s.get("industrial_pids", []))]
			)
	print("ScenarioFactorySpawner: majors — %s" % ", ".join(major_bits))
	# Auto-seed resource/energy plants from province deposits (steel mills, coal plants, refineries…).
	var plant_report: Dictionary = _auto_seed_resource_plants(scenario_loader, factory_manager)
	if int(plant_report.get("seeded", 0)) > 0:
		print(
			"ScenarioFactorySpawner: resource plants seeded=%d (coal/steel/refinery/… by deposit)"
			% int(plant_report.get("seeded", 0))
		)


func _auto_seed_resource_plants(scenario_loader: ScenarioLoader, factory_manager: Node) -> Dictionary:
	if factory_manager == null or not factory_manager.has_method("auto_seed_resource_plants"):
		return {"seeded": 0}
	var payload: Array = []
	var unlocks_by_tag: Dictionary = {}
	if scenario_loader != null and "provinces" in scenario_loader:
		var provs: Variant = scenario_loader.provinces
		if provs is Dictionary:
			for pid_key in (provs as Dictionary):
				var p: Province = (provs as Dictionary)[pid_key] as Province
				if p == null:
					continue
				var tag := str(p.owner_tag).strip_edges().to_upper()
				var res: Dictionary = p.resources if p.resources is Dictionary else {}
				if tag.is_empty() or res.is_empty():
					continue
				payload.append({
					"province_id": int(p.id) if "id" in p else int(pid_key),
					"owner_tag": tag,
					"resources": res,
				})
				if not unlocks_by_tag.has(tag) and typeof(TechnologyManager) != TYPE_NIL:
					var st: Dictionary = TechnologyManager.get_country_state(tag) if TechnologyManager.has_method("get_country_state") else {}
					unlocks_by_tag[tag] = {
						"rule_flags": (st.get("rule_flags", []) as Array).duplicate() if st.get("rule_flags") is Array else [],
						"unlocked_resources": (st.get("unlocked_resources", []) as Array).duplicate() if st.get("unlocked_resources") is Array else [],
						"permanent_modifiers": (st.get("permanent_modifiers", {}) as Dictionary).duplicate(true) if st.get("permanent_modifiers") is Dictionary else {},
					}
	return factory_manager.auto_seed_resource_plants(payload, unlocks_by_tag, 16)


## Pure-callable industrial province resolution (capital + key provinces that exist as land on board).
static func resolve_industrial_province_ids(
	capital_id: int,
	key_province_ids: Array,
	valid_land_ids: Array,
) -> Array[int]:
	var valid: Dictionary = {}
	for raw in valid_land_ids:
		var pid := int(raw)
		if pid > 0:
			valid[pid] = true
	var out: Array[int] = []
	var seen: Dictionary = {}
	if capital_id > 0 and (valid.is_empty() or valid.has(capital_id)):
		out.append(capital_id)
		seen[capital_id] = true
	for raw in key_province_ids:
		var pid := int(raw)
		if pid <= 0 or seen.has(pid):
			continue
		if not valid.is_empty() and not valid.has(pid):
			continue
		out.append(pid)
		seen[pid] = true
	return out


func resolve_industrial_provinces(
	country: Dictionary,
	country_tag: String,
	scenario_loader: ScenarioLoader,
) -> Array[int]:
	var capital := int(country.get("capital_province_id", 0))
	var keys: Array = []
	var key_raw: Variant = country.get("key_provinces", [])
	if typeof(key_raw) == TYPE_ARRAY:
		keys = key_raw as Array
	var valid_land: Array = []
	if scenario_loader != null:
		for pid in scenario_loader.provinces.keys():
			var p: Province = scenario_loader.provinces[pid]
			if p == null or p.is_sea:
				continue
			# Prefer provinces already owned by tag after ownership apply
			var ot := str(p.owner_tag).strip_edges().to_upper()
			if not ot.is_empty() and ot != country_tag:
				continue
			valid_land.append(int(p.id))
	var resolved := resolve_industrial_province_ids(capital, keys, valid_land)
	# If capital not owned yet (ordering edge), still use capital if it exists on board as land
	if resolved.is_empty() and scenario_loader != null and capital > 0:
		var cp: Province = scenario_loader.provinces.get(capital) as Province
		if cp != null and not cp.is_sea:
			resolved = [capital] as Array[int]
	return resolved


func resolve_shipyard_provinces(
	country_tag: String,
	industrial_provinces: Array[int],
	scenario_loader: ScenarioLoader,
) -> Array[int]:
	var out: Array[int] = []
	var seen: Dictionary = {}
	# Prefer industrial list that already has port access
	for province_id in industrial_provinces:
		if _province_has_port(province_id, {}, scenario_loader):
			if not seen.has(province_id):
				out.append(province_id)
				seen[province_id] = true
	if not out.is_empty():
		return out
	# Scan owned land for ports / coastal
	if scenario_loader == null:
		return out
	var coastal: Array[int] = []
	for pid in scenario_loader.provinces.keys():
		var p: Province = scenario_loader.provinces[pid]
		if p == null or p.is_sea:
			continue
		if str(p.owner_tag).strip_edges().to_upper() != country_tag:
			continue
		if p.resolve_has_port() or p.has_port:
			coastal.append(int(p.id))
	coastal.sort()
	# One primary shipyard site is enough for bootstrap
	if not coastal.is_empty():
		out.append(coastal[0])
	return out


func _iter_countries(data: Dictionary) -> Array:
	var out: Array = []
	var countries_block: Variant = data.get("countries", [])
	if typeof(countries_block) == TYPE_ARRAY:
		for country in countries_block:
			if typeof(country) == TYPE_DICTIONARY:
				out.append(country)
	elif typeof(countries_block) == TYPE_DICTIONARY:
		for tag in countries_block:
			var country: Variant = countries_block[tag]
			if typeof(country) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = country as Dictionary
			if not d.has("tag"):
				d["tag"] = str(tag)
			out.append(d)
	return out


func _base_factory_count(country: Dictionary, is_major_power: bool, country_tag: String) -> int:
	var industrial_weight := maxi(int(country.get("industrial_weight", 1)), 1)
	var base_factories := 2
	if is_major_power:
		base_factories = 6
	if country_tag in TOP_INDUSTRIAL_TAGS:
		base_factories += 3
	return base_factories * industrial_weight


func _shipyard_levels_for_country(country_tag: String) -> int:
	if country_tag in TOP_NAVAL_SHIPYARD_TAGS:
		return 5
	if country_tag in SECOND_TIER_NAVAL_TAGS:
		return 4
	return 3


func _default_major_power(country_tag: String) -> bool:
	return country_tag in TOP_INDUSTRIAL_TAGS


func _default_naval_power(country_tag: String) -> bool:
	return country_tag in DEFAULT_NAVAL_POWER_TAGS


func _province_has_port(
	province_id: int,
	_scenario_data: Dictionary,
	scenario_loader: ScenarioLoader,
) -> bool:
	if scenario_loader != null and scenario_loader.provinces.has(province_id):
		var province: Province = scenario_loader.provinces[province_id]
		return province != null and province.resolve_has_port()
	return false


func _factory_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/FactoryManager")
