extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("TEST_START")
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("NO_GAMEDATA")
		quit(1)
		return
	for api in [
		"apply_space_board_ui_primary_live",
		"apply_space_open_path_primary_live",
		"apply_space_rival_survey_primary_live",
		"apply_space_discovery_choice_primary_live",
		"apply_matchmaking_primary_live",
	]:
		print("CALL ", api)
		if gd.has_method(api):
			var r: Dictionary = gd.call(api, 1)
			print("RESULT ", api, " ok=", str(r.get("ok", false)))
		else:
			print("MISSING ", api)
	print("TEST_DONE")
	quit(0)
