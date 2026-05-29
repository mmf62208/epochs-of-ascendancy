# scripts/core/TestRunner.gd
extends Node

@onready var loader: ScenarioLoader = $ScenarioLoader
@onready var map_renderer: MapRenderer = $WorldMap
@onready var camera_controller: CameraController = $WorldMap/CameraInput

var player_tag: String = "USA"


func _ready() -> void:
	print("=== Epochs of Ascendancy Test Starting ===")
	_run_production_line_tests()

	var success := loader.load_scenario("2026")

	if not success:
		print("Failed to load scenario.")
		return

	_wire_factory_province_lookup()

	print("Scenario loaded. Initializing map renderer...")
	var map_data := loader.get_map_data()
	map_renderer.initialize(
		map_data.provinces,
		map_data.geometry,
		map_data.adjacency_system,
		map_data.countries,
	)

	# Also feed MapManager so it is authoritative even in test runner flows
	var mm := get_node_or_null("/root/MapManager")
	if mm != null and mm.has_method("initialize_from_map_data"):
		mm.initialize_from_map_data(map_data)
	elif mm != null and mm.has_method("force_initialize"):
		mm.force_initialize(map_data.provinces, map_data.geometry, map_data.adjacency_system, map_data.countries)

	if camera_controller and map_renderer.container:
		camera_controller.target = map_renderer.container

	player_tag = _resolve_player_tag()

	if map_renderer and loader:
		map_renderer.build_supply_network(loader.get_city_layer(), player_tag)
		var sm := get_node_or_null("/root/SupplyManager")
		if sm:
			sm.record_attrition("us_infantry_div_ww2", 120, {"m4_sherman_medium": 2.0})
			sm.advance_supply_day(1.0)
		print("Supply network ready (toggle overlay with L)")

	if mm != null and mm.has_method("has_province_data") and mm.has_province_data():
		print("✅ MapManager ready with %d provinces (ProvinceEffects now centralized)" % mm.get_province_count())

	_configure_top_info_bar(player_tag)
	if typeof(LeaderManager) != TYPE_NIL:
		LeaderManager.set_player_country_tag(player_tag)


func _resolve_player_tag() -> String:
	var tag := player_tag
	if loader == null:
		return tag
	if loader.get_country(tag) != null:
		return tag
	for c in loader.countries.values():
		if c is Country:
			return (c as Country).tag
	return tag


func _configure_top_info_bar(player_tag: String) -> void:
	var top_bar: TopInfoBar = get_node_or_null("UILayer/TopInfoBar") as TopInfoBar
	if top_bar != null:
		top_bar.player_country_tag = player_tag


func _wire_factory_province_lookup() -> void:
	var fm := get_node_or_null("/root/FactoryManager")
	if fm == null or loader == null:
		return
	fm.set_province_lookup(func(province_id: int) -> Province:
		return loader.provinces.get(province_id) as Province
	)


func _run_production_line_tests() -> void:
	print("=== Production Line Tests ===")
	var passed := ProductionLineTest.run_all(GameData.design_data)
	print("✅ Production line tests passed" if passed else "❌ Production line tests failed")
