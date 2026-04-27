class_name ScenarioLoader
extends Node

const Province = preload("res://scripts/core/Province.gd")

var base_provinces: Dictionary = {}
var provinces: Dictionary = {}
var countries: Dictionary = {}

signal scenario_loaded()

func _ready():
	load_base_provinces()

func load_base_provinces():
	var file_path = "res://data/provinces/provinces_base.json"
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var data = json.data
	base_provinces.clear()
	for p_data in data["provinces"]:
		var p = Province.new()
		p.id = int(p_data.get("id", 0))          # force int
		p.name = p_data.get("name", "Unnamed")
		p.resources = p_data.get("natural_resources", {})
		p.terrain = p_data.get("terrain", "plains")
		p.core_for_tags = p_data.get("core_for_tags", [])
		p.population = p_data.get("population_base", 1000000)
		p.special_features = p_data.get("special_features", [])
		p.special_levels = p_data.get("special_levels", {})
		base_provinces[p.id] = p
	print("✅ Base provinces loaded: ", base_provinces.size(), " provinces")

func load_scenario(scenario_name: String) -> bool:
	var file_path = "res://data/scenarios/" + scenario_name + ".json"
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var data = json.data
	
	provinces.clear()
	countries.clear()

	# Copy base
	for id in base_provinces:
		var base_p = base_provinces[id]
		var p = Province.new()
		p.id = base_p.id
		p.name = base_p.name
		p.resources = base_p.resources.duplicate()
		p.terrain = base_p.terrain
		p.core_for_tags = base_p.core_for_tags.duplicate()
		p.population = base_p.population
		p.special_features = base_p.special_features.duplicate()
		p.special_levels = base_p.special_levels.duplicate()
		provinces[id] = p

	# Apply overrides with heavy debug
	print("=== APPLYING SCENARIO OVERRIDES ===")
	if data.has("provinces"):
		for p_data in data["provinces"]:
			var raw_id = p_data.get("id", 0)
			var id = int(raw_id)                     # ← THIS IS THE FIX
			if provinces.has(id):
				var p = provinces[id]
				p.owner_tag = p_data.get("owner_tag", p.owner_tag)
				p.factories = p_data.get("factories", p.factories)
				p.development_level = p_data.get("development_level", p.development_level)
				p.special_features = p_data.get("special_features", p.special_features)
				p.special_levels = p_data.get("special_levels", p.special_levels)
				
				if id <= 6:   # Debug the first few provinces
					print("  id ", id, " | owner=", p.owner_tag, " | specials=", p.special_features)
			else:
				print("  WARNING: id ", id, " not found in provinces!")

	# Load countries
	if data.has("countries"):
		for c_data in data["countries"]:
			var c = Country.new()
			c.tag = c_data.get("tag", "")
			c.name = c_data.get("name", "")
			c.color = Color(c_data.get("color", "#FFFFFF"))
			c.capital_province_id = c_data.get("capital_province_id", 0)
			countries[c.tag] = c
	
	print("✅ Scenario loaded | Provinces: ", provinces.size(), " | Countries: ", countries.size())
	scenario_loaded.emit()
	return true

func get_country(tag: String):
	return countries.get(tag)
