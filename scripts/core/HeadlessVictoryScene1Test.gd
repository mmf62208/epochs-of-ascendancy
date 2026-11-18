extends SceneTree

## VICTORY-SCENE-1. Mapper, Ink stages, killswitch, and the CL1 host.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessVictoryScene1Test.gd

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessVictoryScene1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessVictoryScene1Test: ", msg)


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if root != null:
		root.size = Vector2i(1280, 800)
	OS.set_environment("EOA_VICTORY_SCENE", "")
	OS.set_environment("EOA_VICTORY_SCENE_CPU", "")
	OS.set_environment("EOA_VICTORY_SCENE_MISS_SKY", "")
	if not await _case_mapper():
		_finish()
		return
	if not await _case_wins():
		_finish()
		return
	if not await _case_fallbacks():
		_finish()
		return
	if not await _case_defeat():
		_finish()
		return
	if not await _case_skip():
		_finish()
		return
	if not await _case_clock():
		_finish()
		return
	if not await _case_audio():
		_finish()
		return
	if not await _case_no_writes():
		_finish()
		return
	if not await _case_rng():
		_finish()
		return
	if not await _case_provinces():
		_finish()
		return
	if not await _case_killswitch():
		_finish()
		return
	# Case 12 (CL1 host) lands with VS-1c.
	_finish()


func _finish() -> void:
	OS.set_environment("EOA_VICTORY_SCENE", "")
	OS.set_environment("EOA_VICTORY_SCENE_CPU", "")
	OS.set_environment("EOA_VICTORY_SCENE_MISS_SKY", "")
	_clear_screens()
	var ok := _failures == 0
	print("HeadlessVictoryScene1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessVictoryScene1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _case_mapper() -> bool:
	var rows: Array = [
		["vp", "win", "", {"path_id": "conquest"}, "WIN", "", "conquest", false],
		["vp", "win", "", {"path_id": "atomic"}, "WIN", "", "atomic", false],
		["vp", "win", "", {"path_id": "arsenal"}, "WIN", "", "arsenal", false],
		["vp", "win", "", {"path_id": "score"}, "WIN", "", "score", false],
		["vp", "win", "", {"path_id": "satellite"}, "WIN", "", "score", false],
		["vp", "loss", "", {"path_id": "conquest"}, "DEFEAT", "burning", "rival_path", false],
		["ink", "win", "enemy_capitals,end_date", {}, "WIN", "", "enemy_capitals", false],
		["ink", "win", "end_date", {}, "WIN", "", "endured", true],
		["ink", "win", "Manual victory test", {}, "WIN", "", "score", false],
		["gamedata", "loss", "fallen", {}, "DEFEAT", "burning", "capitulation", false],
		["cl1", "victory", "decisive", {"kind": "decisive"}, "WIN", "", "conquest", false],
		["cl1", "victory", "time", {"kind": "time", "rank": 1}, "WIN", "", "ascendant", false],
		["cl1", "defeat", "time", {"kind": "time", "rank": 3}, "DEFEAT", "eclipsed", "eclipsed", false],
		["cl1", "defeat", "defeat", {"kind": "defeat"}, "DEFEAT", "burning", "capitulation", false],
		["cl1", "neutral", "time", {"kind": "time"}, "SHEET", "", "", false],
	]
	for row in rows:
		var info: Dictionary = VictorySceneModel.template_key(str(row[0]), str(row[1]), str(row[2]), row[3])
		if str(info.get("template", "")) != str(row[4]) or str(info.get("mode", "")) != str(row[5]) or str(info.get("headline_key", "")) != str(row[6]) or bool(info.get("restrained", false)) != bool(row[7]):
			_fail("mapper %s/%s/%s got %s" % [str(row[0]), str(row[1]), str(row[2]), str(info)])
			return false
		if str(row[6]) == "enemy_capitals" and str(info.get("fallback", "")) != "conquest":
			_fail("enemy_capitals fallback %s" % str(info))
			return false
		if str(row[6]) == "ascendant" and str(info.get("fallback", "")) != "score":
			_fail("ascendant fallback %s" % str(info))
			return false
	_pass("mapper table")
	return true


func _case_wins() -> bool:
	var ink := _ink()
	if ink == null:
		_fail("CampaignInkEndScreen missing")
		return false
	var plain: Node = ink.call("present_win", "GER", "kept playing")
	await process_frame
	if _text(plain, "OutcomeTitle") != "VICTORY" or plain.find_child("PathTitle", true, false) != null:
		_fail("two-arg victory lost VICTORY or gained PathTitle")
		return false
	if not _text(plain, "OutcomeStats").begins_with("Day "):
		_fail("two-arg victory stats '%s'" % _text(plain, "OutcomeStats"))
		return false
	var cases: Array = [
		["GER", "enemy_capitals", {}],
		["GER", "end_date", {}],
		["GER", "conquest", {"path_id": "conquest", "path_title": "Conquest", "winner": "GER", "stats": "Capitals 3/5"}],
		["GER", "atomic", {"path_id": "atomic", "path_title": "Atomic", "winner": "GER", "stats": "Hold 30"}],
		["GER", "arsenal", {"path_id": "arsenal", "path_title": "Arsenal", "winner": "GER", "stats": "Share 40"}],
		["GER", "score", {"path_id": "score", "path_title": "Score", "winner": "GER", "stats": "Score 9"}],
	]
	for row in cases:
		var detail: Dictionary = row[2]
		var reason := str(row[1])
		if detail.has("path_id"):
			reason = str(detail.get("path_title", reason))
		var screen: Node = ink.call("present_win", str(row[0]), reason, detail)
		await process_frame
		if screen == null or int(screen.layer) != 125 or not screen.is_in_group("campaign_ink_end_screen"):
			_fail("win host layer/group for %s" % reason)
			return false
		var stage := screen.find_child("VictorySceneStage", true, false) as Control
		if stage == null:
			_fail("VictorySceneStage missing for %s" % reason)
			return false
		var vp := stage.get_viewport().get_visible_rect().size
		var rect := stage.get_global_rect()
		if not is_equal_approx(rect.size.x, vp.x) or not is_equal_approx(rect.size.y, vp.y):
			_fail("stage rect %s viewport %s" % [str(rect.size), str(vp)])
			return false
		var built: Dictionary = VictorySceneModel.build(
			"vp" if detail.has("path_id") else "ink",
			"win",
			"GER",
			str(row[1]) if not detail.has("path_id") else reason,
			detail
		)
		var head := _text(stage, "SceneHeadline").replace("\n", " / ")
		if head != str(built.get("headline", "")):
			_fail("headline '%s' want '%s'" % [head, str(built.get("headline", ""))])
			return false
		if _text(screen, "OutcomeTitle") != "VICTORY":
			_fail("legacy title for %s" % reason)
			return false
		if detail.has("stats") and _text(screen, "OutcomeStats") != str(detail.get("stats", "")):
			_fail("legacy stats '%s'" % _text(screen, "OutcomeStats"))
			return false
		if detail.has("path_title") and _text(screen, "PathTitle") != str(detail.get("path_title", "")):
			_fail("PathTitle for %s" % reason)
			return false
		for nm in ["BtnKeepPlaying", "BtnSave", "BtnLoadSave", "BtnMainMenu"]:
			if screen.find_child(nm, true, false) == null:
				_fail("missing %s on %s" % [nm, reason])
				return false
		if _text(screen, "BtnLoadSave") != "Load":
			_fail("BtnLoadSave text '%s'" % _text(screen, "BtnLoadSave"))
			return false
	_pass("win stages")
	return true


func _case_fallbacks() -> bool:
	var ink := _ink()
	var pol: Node = ink.call("present_win", "POL", "enemy_capitals")
	await process_frame
	if not _tint_ok(pol, "POL", true):
		return false
	var zzz: Node = ink.call("present_win", "ZZZ", "enemy_capitals")
	await process_frame
	if not _tint_ok(zzz, "ZZZ", false):
		return false
	var table: Dictionary = VictorySceneModel.load_table().duplicate(true)
	var headlines: Dictionary = table.get("headlines", {})
	var win: Dictionary = headlines.get("win", {})
	win["GER"] = {"conquest": {"headline": "GERMANY / OVERRIDE", "eyebrow": "OVERRIDE", "sub": "override sub"}}
	headlines["win"] = win
	table["headlines"] = headlines
	var over: Dictionary = VictorySceneModel.lookup_headline(table, "win", "GER", "conquest")
	if str(over.get("headline", "")) != "GERMANY / OVERRIDE":
		_fail("GER override '%s'" % str(over.get("headline", "")))
		return false
	var fra: Dictionary = VictorySceneModel.lookup_headline(table, "win", "FRA", "conquest")
	if str(fra.get("headline", "")) != "{NAME} / TRIUMPHANT":
		_fail("default headline changed '%s'" % str(fra.get("headline", "")))
		return false
	if VictorySceneModel.backdrop_kind("res://assets/graphics/victory_scene/missing.png") != "procedural":
		_fail("missing skyline was not procedural")
		return false
	OS.set_environment("EOA_VICTORY_SCENE_MISS_SKY", "1")
	var miss: Node = ink.call("present_win", "GER", "enemy_capitals")
	await process_frame
	OS.set_environment("EOA_VICTORY_SCENE_MISS_SKY", "")
	if miss.find_child("ProceduralBackdrop", true, false) == null:
		_fail("forced missing sky did not build ProceduralBackdrop")
		return false
	_pass("fallbacks")
	return true


func _tint_ok(screen: Node, tag: String, allow_real: bool) -> bool:
	var cloth := screen.find_child("FlagCloth", true, false)
	if cloth == null or not (cloth.material is ShaderMaterial):
		_fail("%s flag material missing" % tag)
		return false
	var mat := cloth.material as ShaderMaterial
	var tint := float(mat.get_shader_parameter("tint_mix"))
	var apply := float(mat.get_shader_parameter("apply_tint"))
	if not is_equal_approx(tint, 0.35):
		_fail("%s tint_mix %s" % [tag, str(tint)])
		return false
	if not allow_real and not is_equal_approx(apply, 0.0):
		_fail("%s apply_tint %s want 0" % [tag, str(apply)])
		return false
	var head := _text(screen, "SceneHeadline").replace("\n", " / ")
	var built: Dictionary = VictorySceneModel.build("ink", "win", tag, "enemy_capitals", {})
	if head != str(built.get("headline", "")):
		_fail("%s headline '%s' want '%s'" % [tag, head, str(built.get("headline", ""))])
		return false
	return true


func _case_defeat() -> bool:
	var ink := _ink()
	var loss: Node = ink.call("present_loss", "GER", "fallen")
	await process_frame
	if not await _burn_ok(loss, "gamedata"):
		return false
	var rival: Node = ink.call("present_loss", "GER", "FRA won", {"path_id": "conquest", "path_title": "Conquest", "winner": "FRA", "stats": "Rival"})
	await process_frame
	if not await _burn_ok(rival, "vp"):
		return false
	if _text(rival, "OutcomeTitle") != "DEFEAT" or _text(rival, "OutcomeStats") != "Rival":
		_fail("rival legacy text")
		return false
	_pass("defeat burning")
	return true


func _burn_ok(screen: Node, label: String) -> bool:
	var stage := screen.find_child("DefeatSceneStage", true, false)
	if stage == null:
		_fail("%s DefeatSceneStage missing" % label)
		return false
	var layers := stage.find_child("VictorySceneLayers", true, false)
	if layers == null or str(layers.mode) != "burning":
		_fail("%s mode %s" % [label, str(layers.mode) if layers != null else "none"])
		return false
	var cloth := stage.find_child("FlagCloth", true, false)
	if cloth == null or not (cloth.material is ShaderMaterial):
		_fail("%s burn material missing" % label)
		return false
	var mat := cloth.material as ShaderMaterial
	var burn := 0.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 2500:
		await process_frame
		burn = float(mat.get_shader_parameter("burn"))
		if burn > 0.0:
			break
	if burn <= 0.0 or burn > 0.5:
		_fail("%s burn %s" % [label, str(burn)])
		return false
	var fx := stage.find_child("FxParticles", true, false)
	if fx == null or fx.get_child_count() <= 0:
		_fail("%s particles missing" % label)
		return false
	for nm in ["BtnContinueAs", "BtnLoadSave", "BtnMainMenu"]:
		if screen.find_child(nm, true, false) == null:
			_fail("%s missing %s" % [label, nm])
			return false
	if _text(screen, "BtnLoadSave") != "Load save":
		_fail("%s load label '%s'" % [label, _text(screen, "BtnLoadSave")])
		return false
	return true


func _case_skip() -> bool:
	var am := root.get_node_or_null("AudioManager")
	if am != null and am.has_method("clear_request_log"):
		am.call("clear_request_log")
	var screen: Node = _ink().call("present_loss", "GER", "skip")
	await process_frame
	var before := _sting_count(am, "end_defeat_sting")
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = Vector2(12, 12)
	screen._input(ev)
	await process_frame
	var cloth := screen.find_child("FlagCloth", true, false)
	var burn := float((cloth.material as ShaderMaterial).get_shader_parameter("burn"))
	if not is_equal_approx(burn, 0.5):
		_fail("skip burn %s" % str(burn))
		return false
	var primary := screen.find_child("BtnContinueAs", true, false) as Button
	if primary == null or not primary.visible or primary.modulate.a < 0.99:
		_fail("skip did not show the primary button")
		return false
	var focus := screen.get_viewport().gui_get_focus_owner()
	if focus != primary:
		_fail("skip focus %s" % str(focus))
		return false
	if _sting_count(am, "end_defeat_sting") != before or before != 1:
		_fail("skip changed sting count %s -> %s" % [str(before), str(_sting_count(am, "end_defeat_sting"))])
		return false
	_pass("skip")
	return true


func _case_clock() -> bool:
	var tm := root.get_node_or_null("TimeManager")
	if tm == null or not tm.has_method("overlay_holds_clock"):
		_fail("TimeManager clock lock missing")
		return false
	var ink := _ink()
	var screen: Node = ink.call("present_win", "GER", "end_date")
	await process_frame
	if not bool(tm.call("overlay_holds_clock")):
		_fail("clock not held")
		return false
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	screen._input(esc)
	await process_frame
	if not is_instance_valid(screen) or screen.is_queued_for_deletion() or not screen.is_in_group("campaign_ink_end_screen"):
		_fail("escape dismissed the screen")
		return false
	if screen.has_method("_on_keep"):
		screen.call("_on_keep")
	await process_frame
	if bool(tm.call("overlay_holds_clock")):
		_fail("clock still held after keep")
		return false
	screen = ink.call("present_loss", "GER", "clock")
	await process_frame
	ink.call("_on_any_load_completed", "victory-scene")
	await process_frame
	if _live_ink() != null:
		_fail("load_completed left the screen open")
		return false
	if bool(tm.call("overlay_holds_clock")):
		_fail("clock still held after load_completed")
		return false
	_pass("clock")
	return true


func _case_audio() -> bool:
	var am := root.get_node_or_null("AudioManager")
	if am == null:
		_fail("AudioManager missing")
		return false
	am.call("clear_request_log")
	var win: Node = _ink().call("present_win", "GER", "audio")
	await process_frame
	if _sting_count(am, "end_victory_sting") != 1 or _sting_count(am, "end_defeat_sting") != 0:
		_fail("victory sting %s" % str(am.call("request_log")))
		return false
	if win.has_method("_dismiss_end_screen"):
		win.call("_dismiss_end_screen")
	am.call("clear_request_log")
	var loss: Node = _ink().call("present_loss", "GER", "audio")
	await process_frame
	if _sting_count(am, "end_defeat_sting") != 1 or _sting_count(am, "end_victory_sting") != 0:
		_fail("defeat sting %s" % str(am.call("request_log")))
		return false
	if loss.has_method("_dismiss_end_screen"):
		loss.call("_dismiss_end_screen")
	_pass("audio")
	return true


func _case_no_writes() -> bool:
	var gd := root.get_node_or_null("GameData")
	var mm := root.get_node_or_null("MapManager")
	if gd == null or mm == null:
		_fail("GameData or MapManager missing")
		return false
	var builds := int(mm.owner_index_build_count)
	var wars := JSON.stringify(gd.peace_state.get("campaign_wars", null))
	var caps := JSON.stringify(gd.peace_state.get("campaign_capitulation", null))
	var vp_before := JSON.stringify(gd.peace_state.get("victory_paths", null))
	var screen: Node = _ink().call("present_win", "GER", "conquest", {"path_id": "conquest", "path_title": "Conquest", "winner": "GER", "stats": "same"})
	await _frames(8)
	if int(mm.owner_index_build_count) != builds:
		_fail("owner index %s -> %s" % [str(builds), str(mm.owner_index_build_count)])
		return false
	if JSON.stringify(gd.peace_state.get("campaign_wars", null)) != wars:
		_fail("campaign_wars changed")
		return false
	if JSON.stringify(gd.peace_state.get("campaign_capitulation", null)) != caps:
		_fail("campaign_capitulation changed")
		return false
	if JSON.stringify(gd.peace_state.get("victory_paths", null)) != vp_before:
		_fail("victory path blob changed")
		return false
	if screen.find_child("VictorySceneStage", true, false) == null:
		_fail("conquest stage missing during write check")
		return false
	_pass("no state writes")
	return true


func _case_rng() -> bool:
	seed(12345)
	var a := randi()
	seed(12345)
	OS.set_environment("EOA_VICTORY_SCENE_CPU", "1")
	var screen: Node = _ink().call("present_loss", "GER", "rng")
	for _i in 120:
		await process_frame
	var b := randi()
	OS.set_environment("EOA_VICTORY_SCENE_CPU", "")
	if screen.find_child("FxParticles", true, false) == null:
		_fail("cpu-tier defeat built no particles")
		return false
	if a != b:
		_fail("rng moved %s -> %s" % [str(a), str(b)])
		return false
	_pass("rng isolation")
	return true


func _case_provinces() -> bool:
	var gd := root.get_node_or_null("GameData")
	var open: Dictionary = VictorySceneModel.provinces_at_start("GER")
	if str(open.get("source", "")) != "scenario" or int(open.get("count", -1)) != 421:
		_fail("GER start %s" % str(open))
		return false
	var saved: Variant = gd.peace_state.get("campaign_capitulation", null)
	var snap := {"snapshotted": true, "start_owned": {"GER": [1, 2, 3, 4]}}
	gd.peace_state["campaign_capitulation"] = snap
	var got: Dictionary = VictorySceneModel.provinces_at_start("GER")
	if saved == null:
		gd.peace_state.erase("campaign_capitulation")
	else:
		gd.peace_state["campaign_capitulation"] = saved
	if str(got.get("source", "")) != "snapshot" or int(got.get("count", -1)) != 4:
		_fail("snapshot start %s" % str(got))
		return false
	_pass("provinces at start")
	return true


func _case_killswitch() -> bool:
	OS.set_environment("EOA_VICTORY_SCENE", "0")
	var ink := _ink()
	var win: Node = ink.call("present_win", "GER", "end_date")
	await process_frame
	if win.find_child("VictorySceneStage", true, false) != null or win.find_child("DefeatSceneStage", true, false) != null:
		_fail("killswitch still built a stage")
		return false
	var panel := win.find_child("InkEndPanel", true, false) as Control
	if panel == null or not is_equal_approx(panel.size.x, 760.0) or not is_equal_approx(panel.size.y, 520.0):
		_fail("killswitch panel %s" % (str(panel.size) if panel != null else "missing"))
		return false
	if win.find_child("BtnLoadSave", true, false) != null:
		_fail("killswitch win gained BtnLoadSave")
		return false
	var loss: Node = ink.call("present_loss", "GER", "fallen")
	await process_frame
	if loss.find_child("DefeatSceneStage", true, false) != null or loss.find_child("InkEndPanel", true, false) == null:
		_fail("killswitch loss is not today's panel")
		return false
	var end := load("res://scripts/ui/CampaignEndScreen.gd") as GDScript
	var model := _cl1_model("victory", "decisive", "Victory", 1)
	var cl1: Node = end.call("present", model)
	await process_frame
	if cl1.find_child("VictorySceneStage", true, false) != null or cl1.find_child("EndPanel", true, false) == null:
		_fail("killswitch CL1 changed the sheet")
		return false
	OS.set_environment("EOA_VICTORY_SCENE", "")
	_pass("killswitch")
	return true


func _case_cl1() -> bool:
	var end := load("res://scripts/ui/CampaignEndScreen.gd") as GDScript
	if end == null:
		_fail("CampaignEndScreen missing")
		return false
	var decisive := _cl1_model("victory", "decisive", "Victory", 1)
	var screen: Node = end.call("present", decisive)
	await process_frame
	if screen.find_child("VictorySceneStage", true, false) == null:
		_fail("decisive did not host the winner stage")
		return false
	if not _pointer_hits(screen):
		return false
	var got: Dictionary = screen.call("get_end_model")
	if JSON.stringify(got) != JSON.stringify(decisive):
		_fail("get_end_model %s" % str(got))
		return false
	_clear_screens()
	await process_frame
	var fallen := _cl1_model("defeat", "defeat", "Defeat", 0)
	screen = end.call("present", fallen)
	await process_frame
	var burn_stage := screen.find_child("DefeatSceneStage", true, false)
	var burn_layers := burn_stage.find_child("VictorySceneLayers", true, false) if burn_stage != null else null
	if burn_layers == null or str(burn_layers.mode) != "burning" or burn_stage.find_child("FxParticles", true, false) == null:
		_fail("CL1 defeat is not burning")
		return false
	_clear_screens()
	await process_frame
	var asc := _cl1_model("victory", "time", "Victory: Ascendant", 1)
	screen = end.call("present", asc)
	await process_frame
	if screen.find_child("VictorySceneStage", true, false) == null:
		_fail("ascendant stage missing")
		return false
	if _text(screen, "SceneHeadline").replace("\n", " / ").find("ASCENDANT") < 0:
		_fail("ascendant headline '%s'" % _text(screen, "SceneHeadline"))
		return false
	if _text(screen, "Title") != "Victory: Ascendant":
		_fail("ascendant title '%s'" % _text(screen, "Title"))
		return false
	_clear_screens()
	await process_frame
	var ecl := _cl1_model("defeat", "time", "Defeat: Eclipsed (rank 3)", 3)
	screen = end.call("present", ecl)
	await process_frame
	var ecl_stage := screen.find_child("DefeatSceneStage", true, false)
	var ecl_layers := ecl_stage.find_child("VictorySceneLayers", true, false) if ecl_stage != null else null
	if ecl_layers == null or str(ecl_layers.mode) != "eclipsed":
		_fail("eclipsed mode missing")
		return false
	if ecl_stage.find_child("FxParticles", true, false) != null:
		_fail("eclipsed built particles")
		return false
	if _text(screen, "Title").find("VICTORY") >= 0:
		_fail("eclipsed title contains VICTORY")
		return false
	_clear_screens()
	await process_frame
	var obs := _cl1_model("neutral", "time", "Simulation ended", 2)
	screen = end.call("present", obs)
	await process_frame
	if screen.find_child("VictorySceneStage", true, false) != null or screen.find_child("DefeatSceneStage", true, false) != null:
		_fail("observer built a stage")
		return false
	var panel := screen.find_child("EndPanel", true, false) as CanvasItem
	if panel == null or not panel.visible or _text(screen, "Title") != "Simulation ended":
		_fail("observer sheet changed")
		return false
	_pass("CL1 host")
	return true


func _pointer_hits(screen: Node) -> bool:
	var keep := screen.find_child("BtnKeepPlaying", true, false) as Button
	var load_b := screen.find_child("BtnLoad", true, false) as Button
	if keep == null or load_b == null:
		_fail("CL1 buttons missing")
		return false
	if keep.get_global_rect().size.x <= 1.0 or load_b.get_global_rect().size.x <= 1.0:
		_fail("CL1 button rects %s %s" % [str(keep.get_global_rect()), str(load_b.get_global_rect())])
		return false
	var stub: Node = null
	if get_first_node_in_group("top_info_bar") == null:
		stub = Node.new()
		stub.set_script(_load_stub_script())
		stub.name = "Vs1LoadStub"
		root.add_child(stub)
		stub.add_to_group("top_info_bar")
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = load_b.get_global_rect().get_center()
	var hit := str(screen.call("handle_pointer", ev))
	var stub_hit := stub == null or bool(stub.get_meta("hit", false))
	if stub != null:
		stub.queue_free()
	if hit != "load" or not stub_hit:
		_fail("handle_pointer load got %s" % hit)
		return false
	ev.position = keep.get_global_rect().get_center()
	hit = str(screen.call("handle_pointer", ev))
	if hit != "keep":
		_fail("handle_pointer keep got %s" % hit)
		return false
	return true


func _load_stub_script() -> GDScript:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nfunc _on_load_pressed() -> void:\n\tset_meta(\"hit\", true)\n"
	scr.reload()
	return scr


func _cl1_model(outcome: String, kind: String, title: String, rank: int) -> Dictionary:
	return {
		"outcome": outcome,
		"kind": kind,
		"player_tag": "GER",
		"title": title,
		"reason": "Factory share 12.0%." if kind == "time" else title,
		"date": "1949-01-01",
		"rank": rank,
		"allow_keep_playing": true,
		"allow_continuation": false,
		"keep_playing_reason": "",
		"stats": {
			"days": 10,
			"provinces_start": 421,
			"provinces_end": 400,
			"wars_fought": 1,
			"capitulated_by_side": 1,
			"capitulated_tags": ["FRA"],
			"factory_share": 0.12,
		},
	}


func _ink() -> GDScript:
	return load("res://scripts/ui/CampaignInkEndScreen.gd") as GDScript


func _text(node: Node, node_name: String) -> String:
	if node == null:
		return ""
	var found := node.find_child(node_name, true, false)
	if found == null or not ("text" in found):
		return ""
	return str(found.text)


func _sting_count(am: Node, key: String) -> int:
	if am == null or not am.has_method("request_log"):
		return 0
	var n := 0
	var log: Array = am.call("request_log")
	for item in log:
		if str(item) == key:
			n += 1
	return n


func _live_ink() -> Node:
	for n in get_nodes_in_group("campaign_ink_end_screen"):
		if n != null and is_instance_valid(n) and not n.is_queued_for_deletion() and not str(n.name).ends_with("_dying"):
			return n
	return null


func _clear_screens() -> void:
	for n in get_nodes_in_group("campaign_ink_end_screen"):
		if n != null and is_instance_valid(n) and n.has_method("_dismiss_end_screen"):
			n.call("_dismiss_end_screen")
	var end := load("res://scripts/ui/CampaignEndScreen.gd") as GDScript
	if end != null:
		end.call("dismiss_all")


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
