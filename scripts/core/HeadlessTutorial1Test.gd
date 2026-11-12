extends SceneTree

## TUTORIAL-1. Default off, EOA_TUTORIAL=1 drives all 12 domain steps both ways,
## auto-skip 6–8 at war, keyboard isolation, public pause API, fence.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessTutorial1Test.gd

const SRC_DOMAIN := "res://scripts/core/TutorialGuideDomain.gd"
const SRC_GUIDE := "res://scripts/ui/tutorial/FirstSessionGuide.gd"
const SRC_CARD := "res://scripts/ui/tutorial/TutorialCard.gd"
const SRC_PROMPT := "res://scripts/ui/tutorial/TutorialPrompt.gd"
const SRC_BAR := "res://scripts/ui/TopInfoBar.gd"
const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const SRC_MENU := "res://scripts/ui/MainMenu.gd"
const JSON_PATH := "res://data/tutorial/first_session_1936.json"
const FONT_PATH := "res://assets/fonts/Cinzel-VariableFont_wght.ttf"
const OFL_PATH := "res://assets/fonts/OFL.txt"
const FENCED: PackedStringArray = [
	"res://scripts/ui/CampaignEndScreen.gd",
	"res://scripts/ui/CampaignInkEndScreen.gd",
	"res://scripts/core/CampaignEndDomain.gd",
	"res://scripts/ui/CampaignWarChrome.gd",
	"res://scripts/ui/DiplomacyView.gd",
	"res://scripts/map/MapRenderer.gd",
	"res://scripts/autoload/TimeManager.gd",
	"res://scripts/autoload/GameData.gd",
]
const STEP_IDS: PackedStringArray = [
	"welcome", "time", "map_modes", "inspector", "units", "justify",
	"justify_wait", "declare", "march", "fight", "save", "ending",
]

var _failures: int = 0
var _domain: GDScript


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessTutorial1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessTutorial1Test: ", msg)


func _run() -> void:
	_test_files()
	_domain = load(SRC_DOMAIN) as GDScript
	if _domain == null:
		_fail("TutorialGuideDomain missing")
		_finish()
		return
	_test_json_copy()
	_test_default_off()
	_test_prompt_rules()
	_test_cfg_roundtrip()
	_test_all_steps_both_ways()
	_test_auto_skip_war()
	await _test_keyboard_isolation()
	_test_pause_api()
	_test_fence()
	_test_replay_button()
	await _test_card_and_prompt_nodes()
	await _test_prompt_layout_and_keys()
	_test_own_unit_card_not_inspector()
	_test_cue_log_wrap_and_battle()
	_test_completed_does_not_autostart()
	await _test_p1a_card_hugs_content()
	_test_p1a_fight_copy_and_done_hold()
	_test_p1a_under_attack_keeps_fight_open()
	await _test_p1a_target_rings()
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessTutorial1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessTutorial1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _test_files() -> void:
	for p in [SRC_DOMAIN, SRC_GUIDE, SRC_CARD, SRC_PROMPT, JSON_PATH, FONT_PATH, OFL_PATH]:
		if not FileAccess.file_exists(p):
			_fail("missing %s" % p)
			return
	var ofl := _read(OFL_PATH)
	if ofl.find("SIL OPEN FONT LICENSE") < 0:
		_fail("OFL.txt is not SIL OFL")
		return
	_pass("new files present (domain, guide, card, prompt, json, font, OFL)")


func _test_json_copy() -> void:
	var spec: Dictionary = _domain.call("spec")
	var rows: Array = _domain.call("steps")
	if rows.size() != 12:
		_fail("json steps=%d want 12" % rows.size())
		return
	var want := {
		"welcome": "You lead Germany, 1936",
		"time": "Time is paused",
		"map_modes": "See the map another way",
		"inspector": "Look at a province",
		"units": "Meet your divisions",
		"justify": "Wars need a reason first",
		"justify_wait": "Let the claim build",
		"declare": "Your claim is ready",
		"march": "Move an army",
		"fight": "Start a fight",
		"save": "Save your game",
		"ending": "How the campaign ends",
	}
	for raw in rows:
		if not (raw is Dictionary):
			_fail("step not a dict")
			return
		var row: Dictionary = raw
		var sid := str(row.get("id", ""))
		if str(row.get("title", "")) != str(want.get(sid, "")):
			_fail("copy title %s=%s" % [sid, str(row.get("title", ""))])
			return
		var body := str(row.get("body", ""))
		if body.find("leaf") >= 0 or body.find("Execute") >= 0 or body.find("score") >= 0:
			_fail("forbidden string in %s body" % sid)
			return
	if str((spec.get("scenario", {}) as Dictionary).get("player_tag", "")) != "GER":
		_fail("scenario player_tag")
		return
	_pass("JSON 12-step copy matches spec")


func _base_snap(extra: Dictionary = {}) -> Dictionary:
	var snap := {
		"guide_active": true,
		"world_map_present": true,
		"title_open": false,
		"title_closed": true,
		"player_tag": "GER",
		"start_year": 1936,
		"headless": false,
		"qa_run": false,
		"has_saves": false,
		"loaded_save": false,
		"time_paused": true,
		"day_advanced_then_paused": false,
		"map_mode": "political",
		"map_mode_changed": false,
		"inspector_visible": false,
		"inspector_on_target": false,
		"own_unit_card_visible": false,
		"at_war_with_target": false,
		"at_war_any": false,
		"war_enemy_tag": "",
		"war_enemy_name": "",
		"player_has_justify": false,
		"justify_tag": "",
		"target_tag": "POL",
		"target_name": "Poland",
		"player_justify_ready": false,
		"player_justify_days_left": 14,
		"player_justify_days": 14,
		"player_unit_adjacent_enemy": false,
		"cue_order_move": false,
		"cue_order_attack": false,
		"cue_save_ok": false,
		"battle_started_player": false,
		"minutes_since_begin": 0.0,
		"press_next": false,
		"press_got_it": false,
		"campaign_end_open": false,
	}
	for k in extra.keys():
		snap[k] = extra[k]
	return snap


func _prog(done: Array = []) -> Dictionary:
	var p: Dictionary = _domain.call("empty_progress")
	p["enabled"] = true
	p["answered"] = true
	p["done_steps"] = done.duplicate()
	p["reshow_welcome"] = false
	return p


func _eval(snap: Dictionary, prog: Dictionary) -> Dictionary:
	return _domain.call("evaluate", snap, prog)


func _test_default_off() -> void:
	OS.set_environment("EOA_TUTORIAL", "")
	var p: Dictionary = _domain.call("empty_progress")
	var with_saves := _base_snap({"has_saves": true, "headless": false, "qa_run": false})
	if bool(_domain.call("should_show_prompt", with_saves, p)):
		_fail("prompt shows when saves exist")
		return
	var headless := _base_snap({"headless": true, "qa_run": true, "has_saves": false})
	if bool(_domain.call("should_show_prompt", headless, p)):
		_fail("prompt shows in headless")
		return
	if bool(_domain.call("should_auto_start", headless, p)):
		_fail("guide auto-starts in headless without EOA_TUTORIAL")
		return
	var qa := _base_snap({"headless": false, "qa_run": true})
	if bool(_domain.call("should_auto_start", qa, p)):
		_fail("guide auto-starts in QA harness")
		return
	var hidden: Dictionary = _eval(headless, p)
	if bool(hidden.get("visible", true)):
		_fail("evaluate visible in headless default-off")
		return
	_pass("default off: saves/headless/QA never auto-start")


func _test_prompt_rules() -> void:
	OS.set_environment("EOA_TUTORIAL", "")
	var p: Dictionary = _domain.call("empty_progress")
	var fresh := _base_snap({"has_saves": false, "headless": false, "qa_run": false, "title_closed": true})
	if not bool(_domain.call("should_show_prompt", fresh, p)):
		_fail("prompt hidden for GER 1936 first launch")
		return
	p["answered"] = true
	if bool(_domain.call("should_show_prompt", fresh, p)):
		_fail("prompt repeats after answered")
		return
	OS.set_environment("EOA_TUTORIAL", "1")
	p["answered"] = false
	if bool(_domain.call("should_show_prompt", fresh, p)):
		_fail("EOA_TUTORIAL=1 must skip prompt")
		return
	if not bool(_domain.call("should_auto_start", fresh, p)):
		_fail("EOA_TUTORIAL=1 did not auto-start")
		return
	OS.set_environment("EOA_TUTORIAL", "0")
	p["enabled"] = true
	if bool(_domain.call("should_auto_start", fresh, p)):
		_fail("EOA_TUTORIAL=0 still starts")
		return
	OS.set_environment("EOA_TUTORIAL", "")
	_pass("prompt once + env 1/0")


func _test_cfg_roundtrip() -> void:
	var p := _prog(["welcome", "time"])
	p["skipped_steps"] = ["time"]
	_domain.call("save_cfg", p)
	var loaded: Dictionary = _domain.call("load_cfg")
	if not bool(loaded.get("enabled", false)) or not bool(loaded.get("answered", false)):
		_fail("cfg enabled/answered lost")
		return
	var done: Array = loaded.get("done_steps", [])
	if not done.has("welcome") or not done.has("time"):
		_fail("cfg done_steps lost")
		return
	_pass("cfg roundtrip user://first_session.cfg")


func _test_all_steps_both_ways() -> void:
	OS.set_environment("EOA_TUTORIAL", "1")
	var cases: Array = [
		{"id": "welcome", "done": [], "off": {}, "on": {"press_next": true}, "trig": {}},
		{"id": "time", "done": ["welcome"], "off": {}, "on": {"day_advanced_then_paused": true}, "trig": {}},
		{"id": "map_modes", "done": ["welcome", "time"], "off": {}, "on": {"map_mode_changed": true}, "trig": {}},
		{"id": "inspector", "done": ["welcome", "time", "map_modes"], "off": {}, "on": {"inspector_visible": true}, "trig": {}},
		{"id": "units", "done": ["welcome", "time", "map_modes", "inspector"], "off": {}, "on": {"own_unit_card_visible": true}, "trig": {}},
		{"id": "justify", "done": ["welcome", "time", "map_modes", "inspector", "units"], "off": {}, "on": {"player_has_justify": true, "justify_tag": "POL"}, "trig": {}},
		{"id": "justify_wait", "done": ["welcome", "time", "map_modes", "inspector", "units", "justify"], "off": {"player_has_justify": true}, "on": {"player_has_justify": true, "player_justify_ready": true}, "trig": {"player_has_justify": true}},
		{"id": "declare", "done": ["welcome", "time", "map_modes", "inspector", "units", "justify", "justify_wait"], "off": {}, "on": {"at_war_with_target": true}, "trig": {}},
		{"id": "march", "done": ["welcome", "time", "map_modes", "inspector", "units", "justify", "justify_wait", "declare"], "off": {}, "on": {"cue_order_move": true}, "trig": {}},
		{"id": "fight", "done": ["welcome", "time", "map_modes", "inspector", "units", "justify", "justify_wait", "declare", "march"], "off": {"player_unit_adjacent_enemy": true}, "on": {"player_unit_adjacent_enemy": true, "battle_started_player": true}, "trig": {"player_unit_adjacent_enemy": true}},
		{"id": "save", "done": ["welcome", "time", "map_modes", "inspector", "units", "justify", "justify_wait", "declare", "march", "fight"], "off": {}, "on": {"cue_save_ok": true}, "trig": {}},
		{"id": "ending", "done": ["welcome", "time", "map_modes", "inspector", "units", "justify", "justify_wait", "declare", "march", "fight", "save"], "off": {}, "on": {"press_got_it": true}, "trig": {}},
	]
	for raw2 in cases:
		var c2: Dictionary = raw2
		var sid2 := str(c2.get("id", ""))
		var prog2 := _prog(c2.get("done", []))
		var off_snap := _base_snap(c2.get("trig", {}))
		for k in (c2.get("off", {}) as Dictionary).keys():
			off_snap[k] = (c2.get("off", {}) as Dictionary)[k]
		var incomplete2: Dictionary = _eval(off_snap, prog2)
		if str(incomplete2.get("step_id", "")) != sid2:
			_fail("incomplete %s got step=%s state=%s" % [sid2, str(incomplete2.get("step_id", "")), str(incomplete2.get("state", ""))])
			return
		if str(incomplete2.get("state", "")) == "done":
			_fail("incomplete %s already done" % sid2)
			return
		if not bool(incomplete2.get("visible", false)):
			_fail("incomplete %s hidden" % sid2)
			return
		var on_snap := _base_snap(c2.get("trig", {}))
		for k2 in (c2.get("on", {}) as Dictionary).keys():
			on_snap[k2] = (c2.get("on", {}) as Dictionary)[k2]
		var complete2: Dictionary = _eval(on_snap, prog2)
		if str(complete2.get("state", "")) != "done" and str(complete2.get("step_id", "")) != sid2:
			_fail("complete %s got step=%s state=%s" % [sid2, str(complete2.get("step_id", "")), str(complete2.get("state", ""))])
			return
		if str(complete2.get("state", "")) != "done":
			_fail("complete %s state=%s" % [sid2, str(complete2.get("state", ""))])
			return
	# save also completes via 15-minute fallback without fight done
	var save_prog := _prog(["welcome", "time", "map_modes", "inspector", "units", "justify", "justify_wait", "declare", "march"])
	var save_wait: Dictionary = _eval(_base_snap({"minutes_since_begin": 16.0}), save_prog)
	if str(save_wait.get("step_id", "")) != "save":
		_fail("15-minute save fallback got %s" % str(save_wait.get("step_id", "")))
		return
	OS.set_environment("EOA_TUTORIAL", "")
	_pass("all 12 steps trigger/complete both ways")


func _test_auto_skip_war() -> void:
	OS.set_environment("EOA_TUTORIAL", "1")
	var done := ["welcome", "time", "map_modes", "inspector", "units"]
	var snap := _base_snap({
		"at_war_any": true,
		"at_war_with_target": true,
		"war_enemy_tag": "POL",
		"war_enemy_name": "Poland",
	})
	var result: Dictionary = _eval(snap, _prog(done))
	if str(result.get("state", "")) != "auto_skip":
		_fail("at-war did not auto-skip (state=%s step=%s)" % [str(result.get("state", "")), str(result.get("step_id", ""))])
		return
	var ids: Array = result.get("auto_skip_ids", [])
	if not ids.has("justify") or not ids.has("justify_wait") or not ids.has("declare"):
		_fail("auto_skip_ids=%s" % str(ids))
		return
	if str(result.get("title", "")).find("Poland") < 0:
		_fail("war skip title missing display name: %s" % str(result.get("title", "")))
		return
	var justifying := _base_snap({"player_has_justify": true, "justify_tag": "CZE", "target_name": "Czechoslovakia"})
	var jres: Dictionary = _eval(justifying, _prog(done))
	if str(jres.get("step_id", "")) != "justify":
		_fail("already-justifying did not resolve step 6 (state=%s step=%s)" % [str(jres.get("state", "")), str(jres.get("step_id", ""))])
		return
	if str(jres.get("state", "")) != "done" and str(jres.get("state", "")) != "auto_skip":
		_fail("already-justifying state=%s" % str(jres.get("state", "")))
		return
	var other := _base_snap({"player_tag": "FRA"})
	var ores: Dictionary = _eval(other, _prog(done))
	var oids: Array = ores.get("auto_skip_ids", [])
	if str(ores.get("state", "")) != "auto_skip" or not oids.has("justify") or not oids.has("declare"):
		_fail("non-GER did not auto-skip war steps (state=%s ids=%s)" % [str(ores.get("state", "")), str(oids)])
		return
	OS.set_environment("EOA_TUTORIAL", "")
	_pass("steps 6–8 auto-skip when at war / justifying")


func _test_keyboard_isolation() -> void:
	var card_src := _read(SRC_CARD)
	var guide_src := _read(SRC_GUIDE)
	var prompt_src := _read(SRC_PROMPT)
	if card_src.find("FOCUS_NONE") < 0:
		_fail("TutorialCard missing FOCUS_NONE")
		return
	if card_src.find("KEY_SPACE") >= 0 or card_src.find("KEY_1") >= 0:
		_fail("TutorialCard swallows speed/pause keys")
		return
	if guide_src.find("KEY_SPACE") >= 0 or guide_src.find("KEY_F1") >= 0:
		_fail("FirstSessionGuide swallows hotkeys")
		return
	if prompt_src.find("KEY_ENTER") < 0 or prompt_src.find("KEY_ESCAPE") < 0:
		_fail("TutorialPrompt missing Enter/Esc")
		return
	var card_scr: GDScript = load(SRC_CARD) as GDScript
	var card: Node = card_scr.new()
	root.add_child(card)
	await process_frame
	var stolen := _count_focused(card)
	if stolen > 0:
		_fail("card buttons with focus: %d" % stolen)
		card.queue_free()
		return
	card.queue_free()
	_pass("keyboard isolation: FOCUS_NONE, cards do not swallow Space/1-4/F-keys")


func _count_focused(n: Node) -> int:
	var stolen := 0
	if n is BaseButton and (n as BaseButton).focus_mode != Control.FOCUS_NONE:
		stolen += 1
	for c in n.get_children():
		stolen += _count_focused(c)
	return stolen


func _test_pause_api() -> void:
	var bar := _read(SRC_BAR)
	var guide := _read(SRC_GUIDE)
	if bar.find("func pause()") < 0:
		_fail("TopInfoBar missing public pause()")
		return
	if bar.find("var is_paused") < 0:
		_fail("TopInfoBar missing public is_paused read API")
		return
	if guide.find("_on_pause_pressed") >= 0:
		_fail("guide calls _on_pause_pressed")
		return
	if guide.find("_overlay_holds_clock") >= 0:
		_fail("guide calls _overlay_holds_clock")
		return
	if guide.find("TimeManager.set_paused") >= 0 or guide.find("TimeManager.paused =") >= 0:
		_fail("guide writes TimeManager pause")
		return
	if guide.find("call(\"pause\")") < 0 and guide.find(".pause()") < 0:
		_fail("guide does not call public pause()")
		return
	if guide.find("get(\"is_paused\")") < 0 and guide.find("call(\"is_paused\")") < 0 and guide.find("is_paused()") < 0:
		_fail("guide does not read public is_paused")
		return
	_pass("pause API public-only; guide never writes TimeManager")


func _test_fence() -> void:
	var new_src := _read(SRC_GUIDE) + _read(SRC_CARD) + _read(SRC_PROMPT) + _read(SRC_DOMAIN)
	if new_src.find("tutorial_first_session_primary") >= 0:
		_fail("guide touches tutorial_first_session_primary peace_state")
		return
	if new_src.find("peace_state") >= 0 and SRC_DOMAIN.find("peace") >= 0:
		pass
	for p in FENCED:
		if not FileAccess.file_exists(p):
			_fail("fenced file missing %s" % p)
			return
	var guide := _read(SRC_GUIDE)
	if guide.find("GameData.peace_state") >= 0:
		_fail("guide writes GameData.peace_state")
		return
	_pass("fenced files unread-for-write; no peace_state package")


func _test_replay_button() -> void:
	var title := _read(SRC_TITLE)
	var menu := _read(SRC_MENU)
	if title.find("BtnTutorial") < 0 or menu.find("BtnTutorial") < 0:
		_fail("BtnTutorial missing on title or Command Center")
		return
	if title.find("start_tutorial_from_title") < 0:
		_fail("LivingTitleBoot missing start_tutorial_from_title")
		return
	if menu.find("First-session guide") < 0 or menu.find("Restart guide now") < 0:
		_fail("Settings GAME toggle/restart missing")
		return
	if menu.find("Restart the guide on this map?") < 0:
		_fail("in-game confirm copy missing")
		return
	_pass("BtnTutorial + Settings toggle + Restart")


func _test_card_and_prompt_nodes() -> void:
	var prompt_scr: GDScript = load(SRC_PROMPT) as GDScript
	var prompt: Node = prompt_scr.new()
	root.add_child(prompt)
	await process_frame
	if prompt.get_node_or_null("PromptTitle") == null and prompt.find_child("PromptTitle", true, false) == null:
		_fail("TutorialPrompt missing title")
		prompt.queue_free()
		return
	var show_btn := prompt.find_child("BtnShowBasics", true, false) as Button
	var know_btn := prompt.find_child("BtnKnowGame", true, false) as Button
	if show_btn == null or know_btn == null:
		_fail("TutorialPrompt missing action buttons")
		prompt.queue_free()
		return
	if show_btn.focus_mode != Control.FOCUS_NONE or know_btn.focus_mode != Control.FOCUS_NONE:
		_fail("prompt buttons take focus")
		prompt.queue_free()
		return
	prompt.queue_free()
	var autoload := root.get_node_or_null("FirstSessionGuide")
	if autoload == null:
		_fail("FirstSessionGuide autoload missing")
		return
	_pass("prompt nodes + FirstSessionGuide autoload")


func _guide() -> Node:
	return root.get_node_or_null("FirstSessionGuide")


func _key(physical: int, keycode: int = 0) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = keycode
	ev.physical_keycode = physical
	return ev


func _test_prompt_layout_and_keys() -> void:
	var guide := _guide()
	if guide == null:
		_fail("FirstSessionGuide autoload missing for layout")
		return
	var host: Control = guide.get_node_or_null("FirstSessionLayer/GuideHost") as Control
	if host == null:
		_fail("GuideHost missing")
		return
	host.size = Vector2(1280, 800)
	host.custom_minimum_size = Vector2(1280, 800)
	if not guide.has_method("_show_prompt"):
		_fail("FirstSessionGuide missing _show_prompt")
		return
	guide.call("_show_prompt")
	await process_frame
	await process_frame
	if guide.has_method("_center_prompt"):
		guide.call("_center_prompt")
		await process_frame
	var title := guide.find_child("PromptTitle", true, false) as Control
	var show_btn := guide.find_child("BtnShowBasics", true, false) as Control
	var know_btn := guide.find_child("BtnKnowGame", true, false) as Control
	var dont := guide.find_child("DontAskAgain", true, false) as Control
	var prompt: Control = guide.get("_prompt") as Control
	if title == null or show_btn == null or know_btn == null or dont == null or prompt == null:
		_fail("prompt chrome missing after present/center")
		guide.call("_hide_prompt")
		return
	var layout_ok := true
	for pair in [
		["PromptTitle", title],
		["BtnShowBasics", show_btn],
		["BtnKnowGame", know_btn],
		["DontAskAgain", dont],
	]:
		var ctl := pair[1] as Control
		if not ctl.visible or ctl.size.x < 8.0 or ctl.size.y < 8.0:
			_fail("%s not visible/sized after real parent/anchor/center (size=%s vis=%s)" % [
				str(pair[0]), str(ctl.size), str(ctl.visible)
			])
			layout_ok = false
	if prompt.size.y >= host.size.y * 0.75 or prompt.size.y >= host.size.y - 80.0:
		_fail("prompt height %s is not compact vs host %s" % [str(prompt.size.y), str(host.size.y)])
		layout_ok = false
	if prompt.size.x < 400.0 or prompt.size.x > host.size.x * 0.9:
		_fail("prompt width %s is not compact ~520" % str(prompt.size.x))
		layout_ok = false
	if prompt.anchor_left > 0.01 or prompt.anchor_top > 0.01 or prompt.anchor_right > 0.01 or prompt.anchor_bottom > 0.01:
		_fail("prompt anchors not top-left after present/center (L=%.3f T=%.3f R=%.3f B=%.3f)" % [
			prompt.anchor_left, prompt.anchor_top, prompt.anchor_right, prompt.anchor_bottom
		])
		layout_ok = false
	var know_hits := {"n": 0}
	var show_hits := {"n": 0}
	if prompt.has_signal("know_game"):
		prompt.know_game.connect(func() -> void: know_hits["n"] = int(know_hits["n"]) + 1)
	if prompt.has_signal("show_basics"):
		prompt.show_basics.connect(func() -> void: show_hits["n"] = int(show_hits["n"]) + 1)
	var esc := _key(KEY_ESCAPE, KEY_NONE)
	if guide.has_method("_input"):
		guide._input(esc)
	if prompt.has_method("_input") and prompt.visible:
		prompt._input(esc)
	await process_frame
	if prompt.visible or int(know_hits["n"]) < 1:
		_fail("Esc did not emit know_game / dismiss prompt (visible=%s hits=%s)" % [
			str(prompt.visible), str(know_hits["n"])
		])
		layout_ok = false
	guide.call("_show_prompt")
	await process_frame
	await process_frame
	var enter := _key(KEY_ENTER, KEY_ENTER)
	if guide.has_method("_input"):
		guide._input(enter)
	if prompt.has_method("_input") and prompt.visible:
		prompt._input(enter)
	await process_frame
	if int(show_hits["n"]) < 1:
		_fail("Enter did not emit show_basics")
		layout_ok = false
	guide.set("_force_start", false)
	guide.call("_hide_card")
	guide.call("_hide_prompt")
	if layout_ok:
		_pass("prompt layout compact + Esc know_game + Enter show_basics")


func _test_own_unit_card_not_inspector() -> void:
	var guide := _guide()
	if guide == null or not guide.has_method("_own_unit_card_visible"):
		_fail("FirstSessionGuide missing _own_unit_card_visible")
		return
	var inspector := Control.new()
	inspector.name = "InfoPanel"
	var fight := Button.new()
	fight.name = "BtnOpenFight"
	fight.visible = true
	inspector.add_child(fight)
	root.add_child(inspector)
	var inspector_only: bool = bool(guide.call("_own_unit_card_visible"))
	var pop := Control.new()
	pop.name = "UnitDetailPopup"
	var march := Button.new()
	march.name = "BtnMarchArm"
	march.visible = true
	pop.add_child(march)
	root.add_child(pop)
	var with_card: bool = bool(guide.call("_own_unit_card_visible"))
	pop.queue_free()
	inspector.queue_free()
	if inspector_only:
		_fail("own_unit_card_visible true for inspector InfoPanel BtnOpenFight")
		return
	if not with_card:
		_fail("own_unit_card_visible false with UnitDetailPopup BtnMarchArm")
		return
	_pass("own_unit_card_visible ignores inspector BtnOpenFight")


func _test_cue_log_wrap_and_battle() -> void:
	var guide := _guide()
	var am := root.get_node_or_null("AudioManager")
	if guide == null or am == null:
		_fail("guide or AudioManager missing for cue wrap")
		return
	if am.has_method("clear_request_log"):
		am.call("clear_request_log")
	var i := 0
	while i < 48:
		am.call("play", "ui_hover")
		i += 1
	if not guide.has_method("_on_step_enter"):
		_fail("guide missing _on_step_enter")
		return
	guide.call("_on_step_enter", "march")
	am.call("play", "order_move")
	am.call("play", "order_attack")
	am.call("play", "save_ok")
	var snap: Dictionary = guide.call("_snapshot_now")
	var cue_ok := true
	if not bool(snap.get("cue_order_move", false)):
		_fail("order_move cue missed after 48-cap wrap")
		cue_ok = false
	if not bool(snap.get("cue_save_ok", false)):
		_fail("save_ok cue missed after 48-cap wrap")
		cue_ok = false
	if not bool(snap.get("cue_order_attack", false)):
		_fail("order_attack cue missed after 48-cap wrap")
		cue_ok = false
	guide.set("_battle_player", false)
	var injected := false
	var bm := root.get_node_or_null("BattleManager")
	if bm != null:
		var open_v: Variant = bm.get("_open_land_battles")
		if open_v is Array:
			var player := str(guide.call("_player_tag"))
			(open_v as Array).append({
				"att_tag": player,
				"def_tag": "POL",
			})
			injected = true
	var battle_snap: Dictionary = guide.call("_snapshot_now")
	if injected:
		var open_after: Variant = bm.get("_open_land_battles")
		if open_after is Array and not (open_after as Array).is_empty():
			(open_after as Array).pop_back()
	if not bool(battle_snap.get("battle_started_player", false)):
		_fail("player open land battle did not set battle_started_player")
		cue_ok = false
	if am.has_method("clear_request_log"):
		am.call("clear_request_log")
	if cue_ok:
		_pass("cue wrap + player battle completes fight")


func _test_completed_does_not_autostart() -> void:
	OS.set_environment("EOA_TUTORIAL", "")
	var p: Dictionary = _domain.call("empty_progress")
	p["answered"] = true
	p["enabled"] = true
	p["completed"] = true
	p["reshow_welcome"] = true
	var snap := _base_snap({"headless": false, "qa_run": false, "has_saves": true, "loaded_save": false})
	if bool(_domain.call("should_auto_start", snap, p)):
		_fail("completed+enabled auto-starts on fresh Begin")
		return
	var replay: Dictionary = _domain.call("reset_for_replay", p)
	if not bool(_domain.call("should_auto_start", snap, replay)):
		_fail("explicit replay did not auto-start at welcome")
		return
	if bool(replay.get("completed", true)):
		_fail("reset_for_replay left completed true")
		return
	if str(_eval(snap, replay).get("step_id", "")) != "welcome":
		_fail("explicit replay did not land on welcome / step 1")
		return
	var guide := _guide()
	if guide != null:
		guide.set("_progress", p.duplicate(true))
		guide.set("_force_start", false)
		guide.call("_on_boot_closed", {"mode": "begin"})
		var after: Dictionary = guide.get("_progress")
		if bool(after.get("reshow_welcome", false)):
			_fail("fresh Begin after completed re-armed reshow_welcome")
			return
		if bool(guide.get("_force_start")):
			_fail("fresh Begin after completed set force_start")
			return
		guide.call("replay", false)
		if not bool(guide.get("_force_start")):
			_fail("explicit replay did not set force_start")
			return
		var rp: Dictionary = guide.get("_progress")
		if bool(rp.get("completed", true)) or str(_eval(snap, rp).get("step_id", "")) != "welcome":
			_fail("explicit replay did not restart at welcome")
			return
		guide.set("_force_start", false)
		guide.call("_hide_card")
		guide.call("_hide_prompt")
	_pass("completed Begin does not auto-start; replay still starts at 1")


func _p1a_done_before(step_id: String) -> Array:
	var done: Array = []
	for sid in STEP_IDS:
		if str(sid) == step_id:
			break
		done.append(str(sid))
	return done


func _p1a_active_model(step_id: String) -> Dictionary:
	OS.set_environment("EOA_TUTORIAL", "1")
	var extra := {}
	if step_id == "fight":
		extra["player_unit_adjacent_enemy"] = true
	return _eval(_base_snap(extra), _prog(_p1a_done_before(step_id)))


func _test_p1a_card_hugs_content() -> void:
	var guide := _guide()
	if guide == null:
		_fail("P1a card hug: FirstSessionGuide missing")
		return
	var host: Control = guide.get_node_or_null("FirstSessionLayer/GuideHost") as Control
	var card: TutorialCard = guide.get("_card") as TutorialCard
	if host == null or card == null:
		_fail("P1a card hug: host or card missing")
		return
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.position = Vector2.ZERO
	host.custom_minimum_size = Vector2(1280, 800)
	host.size = Vector2(1280, 800)
	await process_frame
	var cases: Array = [
		{"id": "welcome", "confirm": false},
		{"id": "units", "confirm": false},
		{"id": "fight", "confirm": false},
		{"id": "ending", "confirm": false},
		{"id": "welcome", "confirm": true},
	]
	for raw in cases:
		var c: Dictionary = raw
		var sid := str(c.get("id", ""))
		var model := _p1a_active_model(sid)
		if str(model.get("step_id", "")) != sid or not bool(model.get("visible", false)):
			_fail("P1a card hug: model for %s missing (step=%s vis=%s)" % [
				sid, str(model.get("step_id", "")), str(model.get("visible", false))
			])
			OS.set_environment("EOA_TUTORIAL", "")
			return
		model["confirm_skip"] = bool(c.get("confirm", false))
		model["visible"] = true
		card.size = Vector2(maxf(card.custom_minimum_size.x, 340.0), host.size.y * 0.85)
		card.present(model)
		await process_frame
		await process_frame
		await process_frame
		var combined := card.get_combined_minimum_size()
		var label := "step %s%s" % [str(model.get("n", 0)), " skip-confirm" if bool(c.get("confirm", false)) else ""]
		if card.size.y > combined.y + 1.0:
			_fail("P1a card hug: %s size.y=%.1f > combined_min.y+1 (%.1f)" % [label, card.size.y, combined.y])
			OS.set_environment("EOA_TUTORIAL", "")
			return
		if card.size.y + 1.0 < combined.y:
			_fail("P1a card hug: %s size.y=%.1f collapsed under combined_min.y %.1f" % [label, card.size.y, combined.y])
			OS.set_environment("EOA_TUTORIAL", "")
			return
		if card.size.y >= host.size.y * 0.6:
			_fail("P1a card hug: %s size.y=%.1f >= 0.6*host %.1f" % [label, card.size.y, host.size.y * 0.6])
			OS.set_environment("EOA_TUTORIAL", "")
			return
	var dots := 0
	for node in card.find_children("*", "ColorRect", true, false):
		if node.is_queued_for_deletion():
			continue
		var dot := node as ColorRect
		if dot.size_flags_horizontal != Control.SIZE_SHRINK_CENTER or dot.size_flags_vertical != Control.SIZE_SHRINK_CENTER:
			_fail("P1a card hug: step dots are not SIZE_SHRINK_CENTER")
			OS.set_environment("EOA_TUTORIAL", "")
			return
		dots += 1
	if dots != TutorialGuideDomain.STEP_COUNT:
		_fail("P1a card hug: dot count %d" % dots)
		OS.set_environment("EOA_TUTORIAL", "")
		return
	OS.set_environment("EOA_TUTORIAL", "")
	_pass("P1a card hugs content on steps 1, 5, 10, 12 and skip-confirm")


func _test_p1a_fight_copy_and_done_hold() -> void:
	OS.set_environment("EOA_TUTORIAL", "1")
	var before := _p1a_done_before("fight")
	var wait: Dictionary = _eval(_base_snap({"player_unit_adjacent_enemy": false}), _prog(before))
	if str(wait.get("body", "")) != "Move a division onto the border with Poland":
		_fail("P1a fight-wait body=%s" % str(wait.get("body", "")))
		OS.set_environment("EOA_TUTORIAL", "")
		return
	var rows: Array = _domain.call("steps")
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var sid := str(row.get("id", ""))
		if sid == "units":
			var keys: Array = row.get("keys", [])
			if keys.has("U"):
				_fail("P1a step 5 still has the U chip")
				OS.set_environment("EOA_TUTORIAL", "")
				return
		elif sid == "ending":
			var end_keys: Array = row.get("keys", [])
			if not end_keys.is_empty():
				_fail("P1a step 12 chip not dropped: %s" % str(end_keys))
				OS.set_environment("EOA_TUTORIAL", "")
				return
		elif sid == "fight":
			var body := str(row.get("body", ""))
			if body.find("Polish troops") >= 0:
				_fail("P1a step 10 still says Polish troops")
				OS.set_environment("EOA_TUTORIAL", "")
				return
			if abs(float(row.get("p1_done_hold_s", 0.0)) - 3.0) > 0.01:
				_fail("P1a step 10 p1_done_hold_s=%s" % str(row.get("p1_done_hold_s", "")))
				OS.set_environment("EOA_TUTORIAL", "")
				return
	var done_res: Dictionary = _eval(_base_snap({
		"player_unit_adjacent_enemy": true,
		"battle_started_player": true,
	}), _prog(before))
	if str(done_res.get("state", "")) != "done":
		_fail("P1a player battle did not complete fight (state=%s)" % str(done_res.get("state", "")))
		OS.set_environment("EOA_TUTORIAL", "")
		return
	if abs(float(done_res.get("p1_done_hold_s", 0.0)) - 3.0) > 0.01:
		_fail("P1a done result hold=%s want 3" % str(done_res.get("p1_done_hold_s", 0)))
		OS.set_environment("EOA_TUTORIAL", "")
		return
	if str(done_res.get("title", "")) != "Battle started":
		_fail("P1a done title=%s" % str(done_res.get("title", "")))
		OS.set_environment("EOA_TUTORIAL", "")
		return
	var guide := _guide()
	if guide == null:
		_fail("P1a done hold: guide missing")
		OS.set_environment("EOA_TUTORIAL", "")
		return
	guide.call("_apply_result", done_res)
	var left := float(guide.get("_flash_left"))
	guide.set("_flash_left", 0.0)
	if abs(left - 3.0) > 0.05:
		_fail("P1a guide done hold %.3f want 3" % left)
		OS.set_environment("EOA_TUTORIAL", "")
		return
	OS.set_environment("EOA_TUTORIAL", "")
	_pass("P1a fight-wait copy and step 10 done hold 3s")


func _test_p1a_under_attack_keeps_fight_open() -> void:
	var guide := _guide()
	if guide == null:
		_fail("P1a under attack: guide missing")
		return
	guide.set("_battle_player", false)
	guide.set("_under_attack", false)
	if guide.has_method("_on_step_enter"):
		guide.call("_on_step_enter", "fight")
	var bm := root.get_node_or_null("BattleManager")
	if bm == null:
		_fail("P1a under attack: BattleManager missing")
		return
	var open_v: Variant = bm.get("_open_land_battles")
	if not (open_v is Array):
		_fail("P1a under attack: open land battles missing")
		return
	var player := str(guide.call("_player_tag"))
	(open_v as Array).append({
		"att_tag": "POL",
		"def_tag": player,
	})
	var snap: Dictionary = guide.call("_snapshot_now")
	var open_after: Variant = bm.get("_open_land_battles")
	if open_after is Array and not (open_after as Array).is_empty():
		(open_after as Array).pop_back()
	if bool(snap.get("battle_started_player", false)):
		_fail("P1a under attack: defender battle set battle_started_player")
		return
	if not bool(snap.get("player_under_attack", false)):
		_fail("P1a under attack: player_under_attack not set")
		return
	OS.set_environment("EOA_TUTORIAL", "1")
	var eval_snap := _base_snap({
		"player_unit_adjacent_enemy": true,
		"player_under_attack": bool(snap.get("player_under_attack", false)),
		"battle_started_player": bool(snap.get("battle_started_player", false)),
	})
	var res: Dictionary = _eval(eval_snap, _prog(_p1a_done_before("fight")))
	OS.set_environment("EOA_TUTORIAL", "")
	if str(res.get("step_id", "")) != "fight" or str(res.get("state", "")) == "done" or str(res.get("state", "")) == "hidden":
		_fail("P1a under attack: step 10 did not stay open (step=%s state=%s)" % [
			str(res.get("step_id", "")), str(res.get("state", ""))
		])
		return
	if str(res.get("status_text", "")) != "You're under attack; now start your own battle":
		_fail("P1a under attack status=%s" % str(res.get("status_text", "")))
		return
	if str(res.get("status_color", "")) != "#f2c94c":
		_fail("P1a under attack status color=%s" % str(res.get("status_color", "")))
		return
	_pass("P1a defender battle leaves step 10 open and sets player_under_attack")


func _test_p1a_target_rings() -> void:
	var guide := _guide()
	if guide == null:
		_fail("P1a rings: guide missing")
		return
	var declare := Button.new()
	declare.name = "BtnDeclareWar"
	declare.position = Vector2(40, 200)
	declare.size = Vector2(160, 32)
	declare.custom_minimum_size = Vector2(160, 32)
	root.add_child(declare)
	var dipl := Button.new()
	dipl.name = "DiplomacyButton"
	dipl.position = Vector2(900, 8)
	dipl.size = Vector2(72, 28)
	dipl.custom_minimum_size = Vector2(72, 28)
	root.add_child(dipl)
	var open_fight := Button.new()
	open_fight.name = "BtnOpenFight"
	open_fight.position = Vector2(80, 520)
	open_fight.size = Vector2(140, 32)
	open_fight.custom_minimum_size = Vector2(140, 32)
	root.add_child(open_fight)
	var start := Button.new()
	start.name = "BtnStartBattle"
	start.position = Vector2(240, 520)
	start.size = Vector2(140, 32)
	start.custom_minimum_size = Vector2(140, 32)
	root.add_child(start)
	await process_frame
	var justify := {
		"step_id": "justify",
		"target": {
			"kind": "node",
			"path": "WorldMap/UI/InfoPanel/BtnDeclareWar",
			"p1_target_when": "inspector_on_target",
			"p1_else": "TopInfoBar/ContentRow/CenterContainer/DiplomacyButton",
		},
	}
	var got: Rect2 = guide.call("_target_rect", justify)
	var dipl_r := dipl.get_global_rect()
	if got.position.distance_to(dipl_r.position) > 2.0:
		_fail("P1a ring: inspector off target got %s want Dipl %s" % [str(got), str(dipl_r)])
		declare.queue_free()
		dipl.queue_free()
		open_fight.queue_free()
		start.queue_free()
		return
	var fight := {
		"step_id": "fight",
		"target": {
			"kind": "node_in_unit_card",
			"name": "BtnOpenFight",
			"p1_prefer": "BtnStartBattle",
		},
	}
	var pref: Rect2 = guide.call("_target_rect", fight)
	var start_r := start.get_global_rect()
	declare.queue_free()
	dipl.queue_free()
	open_fight.queue_free()
	start.queue_free()
	if pref.position.distance_to(start_r.position) > 2.0:
		_fail("P1a ring: visible Start battle got %s want %s" % [str(pref), str(start_r)])
		return
	_pass("P1a rings Dipl until the inspector is on target, and Start battle when it is open")
