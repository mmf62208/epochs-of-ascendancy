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
