extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("GOAL_SMOKE_START")
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("NO_GAMEDATA")
		quit(1)
		return
	var r1: Dictionary = gd.call("apply_space_discovery_ui_primary_live", 1)
	print("DISCOVERY_UI_OK=", str(r1.get("ok", false)), " unresolved=", str(r1.get("unresolved_ok", false)), " choose=", str(r1.get("choose_ok", false)), " reresolve_blocked=", str(r1.get("reresolve_blocked", false)))
	var r2: Dictionary = gd.call("apply_matchmaking_lobby_primary_live", 1)
	print("MATCH_LOBBY_OK=", str(r2.get("ok", false)), " open=", str(r2.get("open_ok", false)), " path=", str(r2.get("path_ok", false)), " session=", str(r2.get("session_ok", false)))
	# Direct manager one-shot proof
	var slm: Node = root.get_node_or_null("/root/SpaceLayerManager")
	if slm:
		slm.call("reset_for_new_scenario")
		var s: Dictionary = slm.call("start_survey", "USA", "mars", {"months": 1, "force_success": true})
		var sid: String = str((s.get("survey", {}) as Dictionary).get("survey_id", ""))
		slm.call("force_complete_survey", sid, {"force_success": true, "seed": 42})
		slm.call("process_discovery_events", {"silent": true})
		var un: Array = slm.call("list_unresolved_discoveries", "USA")
		var did: String = str((un[0] as Dictionary).get("discovery_id", "")) if un.size() > 0 and un[0] is Dictionary else ""
		var listed: Dictionary = slm.call("list_discovery_choices", did)
		var cid: String = "claim_site"
		if listed.get("choices") is Array and (listed["choices"] as Array).size() > 0:
			cid = str(((listed["choices"] as Array)[0] as Dictionary).get("id", "claim_site"))
		var res1: Dictionary = slm.call("resolve_discovery_choice", did, cid, {"silent": true})
		var res2: Dictionary = slm.call("resolve_discovery_choice", did, cid, {"silent": true})
		print("DIRECT_RESOLVE_OK=", str(res1.get("ok", false)), " RERESOLVE_BLOCKED=", str(not bool(res2.get("ok", true))), " error=", str(res2.get("error", "")))
	print("GOAL_SMOKE_DONE")
	quit(0)
