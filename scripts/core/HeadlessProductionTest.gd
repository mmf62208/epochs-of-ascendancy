extends SceneTree

## Standalone production-line test entry (no main scene). Run after editor import once:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessProductionTest.gd
##
## Deferred load: ProductionLineTest pulls ProductionLine / CombatResolver / Formation,
## which mention autoload identifiers (DesignManager, GameData, …). Those names exist
## only after the project autoloads register, same as other Headless* SceneTree tests.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var design_data: DesignDataLoader = DesignDataLoader.new()
	design_data.load_all()
	var test_script: GDScript = load("res://scripts/core/ProductionLineTest.gd") as GDScript
	if test_script == null or not test_script.has_method("run_all"):
		print("Production line tests: FAIL")
		quit(1)
		return
	var passed: bool = test_script.run_all(design_data)
	print("Production line tests: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
