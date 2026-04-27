# scripts/core/TestRunner.gd
extends Node

@onready var loader: ScenarioLoader = $ScenarioLoader
@onready var map_renderer: MapRenderer = $WorldMap

func _ready():
	print("=== Epochs of Ascendancy Test Starting ===")
	
	var success = loader.load_scenario("2026")   # Try "1936" or "1918" too
	
	if success:
		print("Scenario loaded. Rendering map...")
		map_renderer.render_provinces(loader)
	else:
		print("Failed to load scenario.")
