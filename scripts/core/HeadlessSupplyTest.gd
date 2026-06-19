extends SceneTree


func _init() -> void:
	var loader = load("res://scripts/core/ScenarioLoader.gd").new()
	loader.load_base_provinces()
	await loader.load_scenario("2026")
	var test_script: GDScript = load("res://scripts/core/SupplyLineTest.gd")
	var passed: bool = test_script.call("run_all", loader)
	print("Supply line tests: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
