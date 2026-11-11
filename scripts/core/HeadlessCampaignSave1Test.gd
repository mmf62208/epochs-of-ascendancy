extends SceneTree

## CAMPAIGN-SAVE-1. Fails on 05bf7fb1: the speed bar is not resynced, slot cards
## omit the nation line, province resources do not round-trip, loss opens the
## peace window immediately, and there is no data-driven win check.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCampaignSave1Test.gd

const SLOT := "slot1"
const RULES_PATH := "res://data/campaign/victory_conditions.json"

var _failures: int = 0


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCampaignSave1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCampaignSave1Test: ", msg)


func _run() -> void:
	_test_win_rules()
	_test_round_trip_and_speed()
	_test_load_warning_and_confirms()
	_test_command_center_pause_menu()
	_test_save_browser_opens_command_center()
	_test_live_win_then_loss()
	_test_option_a_end_strings()
	_test_clock_stays_paused_under_overlays()
	_test_continue_as_closes_in_order()
	_test_defeat_load_closes_end_screen()
	_test_save_hint_and_f6_loyalty()
	_test_save_list_polish()
	_test_victory_render()
	await _test_1949_latch_one_overlay()
	await _test_near_capitulation_real_tick()
	await _test_return_begin_clears_war()
	await _test_keep_playing_esc_opens_pause()
	await _test_cc_polish_and_first_return()
	var ok := _failures == 0
	print("HeadlessCampaignSave1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCampaignSave1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _test_win_rules() -> void:
	var rules := _read_rules()
	if rules.is_empty():
		_fail("win: victory_conditions.json missing or empty")
		return
	if str(rules.get("end_date", "")) != "1949-01-01":
		_fail("win: end_date=%s" % str(rules.get("end_date", "")))
		return
	if int(rules.get("victory_points", {}).get("threshold", 0)) != 500:
		_fail("win: vp threshold is not the data file value")
		return
	if bool(rules.get("victory_points", {}).get("enabled", true)):
		_fail("win: default victory_points.enabled must stay false")
		return
	var dom: Script = load("res://scripts/core/CampaignInkEndDomain.gd") as Script
	if dom == null:
		_fail("win: domain script missing")
		return
	var early: Dictionary = dom.call("evaluate_rules", {
		"date": "1936-01-14",
		"player_tag": "GER",
		"enemies": [],
		"enemy_capital_controllers": {},
		"victory_points": 9999,
	}, rules)
	if bool(early.get("win", true)):
		_fail("win: 1936 with no enemies and disabled VP still won")
		return
	var by_date: Dictionary = dom.call("evaluate_rules", {
		"date": str(rules.get("end_date", "")),
		"player_tag": "GER",
		"enemies": [],
		"victory_points": 0,
	}, rules)
	var date_reasons: Array = by_date.get("reasons", [])
	if not bool(by_date.get("win", false)) or not date_reasons.has("end_date"):
		_fail("win: end date in the data file did not fire")
		return
	var by_caps: Dictionary = dom.call("evaluate_rules", {
		"date": "1936-06-01",
		"player_tag": "GER",
		"enemies": ["FRA"],
		"enemy_capital_controllers": {"FRA": "GER"},
		"victory_points": 0,
	}, rules)
	var cap_reasons: Array = by_caps.get("reasons", [])
	if not bool(by_caps.get("win", false)) or not cap_reasons.has("enemy_capitals"):
		_fail("win: held enemy capital did not fire")
		return
	var tuned := rules.duplicate(true)
	tuned["win_if_end_date_reached"] = false
	tuned["win_if_all_enemy_capitals_controlled"] = false
	var vp: Dictionary = tuned.get("victory_points", {}).duplicate(true)
	vp["enabled"] = true
	vp["threshold"] = 10
	tuned["victory_points"] = vp
	var below: Dictionary = dom.call("evaluate_rules", {
		"date": "1936-06-01", "player_tag": "GER", "enemies": [], "victory_points": 9,
	}, tuned)
	var at: Dictionary = dom.call("evaluate_rules", {
		"date": "1936-06-01", "player_tag": "GER", "enemies": [], "victory_points": 10,
	}, tuned)
	if bool(below.get("win", true)) or not bool(at.get("win", false)):
		_fail("win: VP threshold 10 did not follow the rules dict (below=%s at=%s)" % [str(below), str(at)])
		return
	_pass("win: end date, capitals, and VP threshold come from the rules")


func _test_round_trip_and_speed() -> void:
	var lm := root.get_node_or_null("LeaderManager")
	var sl := root.get_node_or_null("SaveLoadManager")
	var tm := root.get_node_or_null("TimeManager")
	var mm := root.get_node_or_null("MapManager")
	var pm := root.get_node_or_null("ProductionManager")
	if lm == null or sl == null or tm == null or mm == null or pm == null:
		_fail("round-trip: autoload missing")
		return
	lm.call("set_player_country_tag", "GER")
	tm.current_year = 1936
	tm.current_month = 3
	tm.current_day = 14
	tm.total_days_elapsed = 14
	tm.set_paused(false)
	tm.set_time_scale(4.0)
	pm.national_stockpile["cs1_oil"] = 42
	var unit_script: Script = load("res://scripts/formations/Formation.gd") as Script
	if unit_script == null:
		_fail("round-trip: unit script missing")
		return
	var unit: Object = unit_script.new()
	unit.set("formation_id", "cs1_probe")
	unit.set("name", "CS1 Probe")
	unit.set("formation_type", "division")
	unit.set("country_tag", "GER")
	unit.set("organization", 77.0)
	unit.set("strength", 0.64)
	var formations := _formations(lm)
	formations["cs1_probe"] = unit
	var provs: Dictionary = mm.call("get_all_provinces")
	if provs.is_empty():
		mm.call("add_editor_province_from_fields", 1990001, "GER", "FRA", {"oil": 7})
		provs = mm.call("get_all_provinces")
	if provs.is_empty():
		_fail("round-trip: map has no provinces")
		return
	var pid := int(provs.keys()[0])
	var prov: Object = provs[pid]
	prov.set("resources", {"oil": 7})
	var owner_before := str(prov.owner_tag)
	var ctrl_before := str(prov.controller_tag)
	var owner_counts := _tag_counts(provs, "owner_tag")
	var ctrl_counts := _tag_counts(provs, "controller_tag")
	var unit_n := formations.size()
	var bar := _make_bar()
	if bar == null:
		_fail("speed: top bar scene missing")
		return
	bar.set("current_speed", 4)
	bar.set("is_paused", false)
	var saved: Dictionary = sl.call("save_game_detailed", SLOT)
	if not bool(saved.get("ok", false)):
		_fail("round-trip: save failed %s" % str(saved.get("error", "")))
		return
	var row := _slot_row(sl, SLOT)
	var nation := str(row.get("nation_line", ""))
	var badge := str(row.get("kind_badge", ""))
	var when := str(row.get("when_line", ""))
	var meta: Dictionary = row.get("metadata", {})
	if nation != "Germany (GER)":
		_fail("card: nation_line='%s' want Germany (GER)" % nation)
		return
	if badge != "MANUAL":
		_fail("card: badge='%s' want MANUAL" % badge)
		return
	if when.find("14 Mar 1936") < 0 or when.find("Saved") < 0:
		_fail("card: when_line='%s'" % when)
		return
	if str(meta.get("player_tag", "")) != "GER":
		_fail("card: player_tag=%s" % str(meta.get("player_tag", "")))
		return
	if str(meta.get("scenario_id", "")) == "1936":
		_fail("card: scenario_id fell back to 1936")
		return
	var blob := nation + "\n" + when + "\n" + str(row.get("label", ""))
	if blob.find("Played") >= 0 or blob.find("play_time") >= 0 or blob.find("USA") >= 0:
		_fail("card: playtime or USA leaked into '%s'" % blob)
		return
	_pass("card: Germany (GER), MANUAL, 14 Mar 1936, playtime hidden")
	bar.set("current_speed", 1)
	bar.set("is_paused", false)
	tm.set_time_scale(1.0)
	tm.set_paused(false)
	tm.current_year = 1937
	tm.current_month = 1
	tm.current_day = 2
	tm.total_days_elapsed = 400
	lm.call("set_player_country_tag", "FRA")
	pm.national_stockpile["cs1_oil"] = 0
	prov.set("resources", {"oil": 0})
	prov.set("owner_tag", "ZZZ")
	prov.set("controller_tag", "ZZZ")
	_formations(lm).erase("cs1_probe")
	var loaded: Dictionary = sl.call("load_game_detailed", SLOT)
	if not bool(loaded.get("ok", false)):
		_fail("round-trip: load failed %s" % str(loaded.get("error", "")))
		return
	if int(bar.get("current_speed")) != 4 or bool(bar.get("is_paused")):
		_fail("speed: bar speed=%s paused=%s after load" % [str(bar.get("current_speed")), str(bar.get("is_paused"))])
		return
	if not is_equal_approx(float(tm.time_scale), 4.0) or bool(tm.call("is_paused")):
		_fail("speed: TimeManager scale=%s paused=%s" % [str(tm.time_scale), str(tm.call("is_paused"))])
		return
	var speed4: Variant = bar.get("speed4_button")
	if speed4 is CanvasItem and (speed4 as CanvasItem).modulate.r < 0.95:
		_fail("speed: 4x button is not the active state")
		return
	if int(tm.current_year) != 1936 or int(tm.current_month) != 3 or int(tm.current_day) != 14:
		_fail("round-trip: date %d-%d-%d" % [int(tm.current_year), int(tm.current_month), int(tm.current_day)])
		return
	if int(tm.total_days_elapsed) != 14:
		_fail("round-trip: elapsed %s" % str(tm.total_days_elapsed))
		return
	if str(lm.player_country_tag).strip_edges().to_upper() != "GER":
		_fail("round-trip: player %s" % str(lm.player_country_tag))
		return
	if int(pm.national_stockpile.get("cs1_oil", 0)) != 42:
		_fail("round-trip: stockpile %s" % str(pm.national_stockpile.get("cs1_oil", 0)))
		return
	var restored: Object = mm.call("get_province", pid)
	if restored == null or int(restored.resources.get("oil", 0)) != 7:
		_fail("round-trip: province oil did not return")
		return
	if str(restored.owner_tag) != owner_before or str(restored.controller_tag) != ctrl_before:
		_fail("round-trip: owner/controller %s/%s" % [str(restored.owner_tag), str(restored.controller_tag)])
		return
	var provs2: Dictionary = mm.call("get_all_provinces")
	if _tag_counts(provs2, "owner_tag") != owner_counts or _tag_counts(provs2, "controller_tag") != ctrl_counts:
		_fail("round-trip: ownership counts changed")
		return
	var restored_units := _formations(lm)
	var back: Object = restored_units.get("cs1_probe", null)
	if back == null or int(round(float(back.get("organization")))) != 77 or restored_units.size() != unit_n:
		_fail("round-trip: units size=%d probe=%s" % [lm.formations.size(), str(back)])
		return
	_pass("round-trip: date, GER, owners, unit, stockpile, oil, 4x bar")


func _test_load_warning_and_confirms() -> void:
	var sl := root.get_node_or_null("SaveLoadManager")
	var tm := root.get_node_or_null("TimeManager")
	if sl == null or tm == null:
		_fail("confirm: autoload missing")
		return
	if bool(sl.call("load_confirm_required", SLOT)):
		_fail("confirm: warned on the same day as the save")
		return
	tm.total_days_elapsed = int(tm.total_days_elapsed) + 1
	if not bool(sl.call("load_confirm_required", SLOT)):
		_fail("confirm: one unsaved day did not warn")
		return
	if bool(sl.call("load_confirm_required", "autosave")):
		_fail("confirm: autosave load warned")
		return
	_pass("confirm: load warning after 1 day, not for autosave")
	var menu := _make_menu()
	if menu == null:
		_fail("confirm: menu missing")
		return
	var elapsed_now := int(tm.total_days_elapsed)
	menu.call("_on_load_slot", SLOT)
	var load_dlg := menu.find_child("LoadUnsavedConfirm", true, false)
	if load_dlg == null or not load_dlg.visible:
		_fail("confirm: LoadUnsavedConfirm did not open")
		return
	if int(tm.total_days_elapsed) != elapsed_now:
		_fail("confirm: load applied before confirm")
		return
	var body := load_dlg.find_child("ConfirmBody", true, false)
	if body == null or str(body.text).find("Progress since your last save will be lost.") < 0:
		_fail("confirm: load copy missing")
		return
	menu.call("_dismiss_confirm")
	var before := FileAccess.get_file_as_string(sl.call("get_save_path", SLOT))
	var card := menu.find_child("SlotCard_%s" % SLOT, true, false)
	if card == null:
		_fail("confirm: slot card missing")
		return
	var save_btn := _button_named(card, "Save")
	if save_btn == null:
		_fail("confirm: Save button missing")
		return
	save_btn.pressed.emit()
	var over := menu.find_child("OverwriteSaveConfirm", true, false)
	if over == null:
		_fail("confirm: OverwriteSaveConfirm missing")
		return
	var after_open := FileAccess.get_file_as_string(sl.call("get_save_path", SLOT))
	if after_open != before:
		_fail("confirm: overwrite rewrote the file before confirm")
		return
	var over_body := over.find_child("ConfirmBody", true, false)
	if over_body == null or str(over_body.text).find("will be replaced") < 0:
		_fail("confirm: overwrite copy missing")
		return
	var danger := over.find_child("BtnDanger", true, false)
	if not (danger is BaseButton):
		_fail("confirm: overwrite button missing")
		return
	(danger as BaseButton).pressed.emit()
	var del_btn := _button_named(card, "Delete")
	if del_btn == null:
		_fail("confirm: Delete button missing")
		return
	# The list may have been rebuilt. Find the card again.
	card = menu.find_child("SlotCard_%s" % SLOT, true, false)
	del_btn = _button_named(card, "Delete") if card != null else null
	if del_btn == null:
		_fail("confirm: Delete button missing after overwrite")
		return
	del_btn.pressed.emit()
	var delete_dlg := menu.find_child("DeleteSaveConfirm", true, false)
	if delete_dlg == null:
		_fail("confirm: DeleteSaveConfirm missing")
		return
	var cancel := delete_dlg.find_child("BtnCancel", true, false)
	if cancel == null or not (cancel is Control) or (cancel as Control).get_viewport() == null:
		_fail("confirm: delete Cancel missing")
		return
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_ENTER
	ev.echo = false
	menu.call("_input", ev)
	if not FileAccess.file_exists(sl.call("get_save_path", SLOT)):
		_fail("confirm: Enter deleted the save")
		return
	var del_go := delete_dlg.find_child("BtnDanger", true, false)
	if not (del_go is BaseButton):
		_fail("confirm: delete action missing")
		return
	(del_go as BaseButton).pressed.emit()
	if FileAccess.file_exists(sl.call("get_save_path", SLOT)):
		_fail("confirm: confirmed delete left the file")
		return
	_pass("confirm: load, overwrite, and delete (Enter does not delete)")
	if menu.has_method("_force_close"):
		menu.call("_force_close")


func _test_command_center_pause_menu() -> void:
	var menu := _make_menu()
	if menu == null:
		_fail("cc: menu missing")
		return
	var title := menu.find_child("CommandCenterTitle", true, false)
	if title == null or str(title.text) != "Paused":
		_fail("cc: in-game title '%s'" % (str(title.text) if title != null else "missing"))
		return
	var actions := menu.find_child("GameActions", true, false)
	var first := _first_button(actions)
	if first == null or str(first.text) != "Resume" or str(first.name) != "BtnResume":
		_fail("cc: first action is not Resume")
		return
	var block := menu.find_child("NewGameBlock", true, false)
	if block == null or block.visible:
		_fail("cc: new-game block still visible in game")
		return
	if _visible_button_text(menu, "Begin"):
		_fail("cc: Begin is visible in game")
		return
	_pass("cc: in-game title Paused, Resume first, no new game")
	if menu.has_method("_force_close"):
		menu.call("_force_close")
	var boot_script: Script = load("res://scripts/ui/LivingTitleBoot.gd") as Script
	if boot_script == null:
		_fail("cc: title script missing")
		return
	var title_boot: Node = boot_script.new()
	title_boot.name = "LivingTitleBoot"
	root.add_child(title_boot)
	var start := _make_menu()
	if start == null:
		_fail("cc: start menu missing")
		return
	var start_title := start.find_child("CommandCenterTitle", true, false)
	var start_block := start.find_child("NewGameBlock", true, false)
	if start_title == null or str(start_title.text) != "Command Center":
		_fail("cc: start title '%s'" % (str(start_title.text) if start_title != null else "missing"))
		return
	if start_block == null or not start_block.visible:
		_fail("cc: start new-game block hidden")
		return
	if start.find_child("BtnResume", true, false) != null:
		_fail("cc: start screen has Resume")
		return
	_pass("cc: start screen stays Command Center")
	if start.has_method("_force_close"):
		start.call("_force_close")
	title_boot.queue_free()


func _test_save_browser_opens_command_center() -> void:
	var bar := _make_bar()
	if bar == null or not bar.has_method("_show_save_manager_popup"):
		_fail("f6: top bar missing")
		return
	bar.call("_show_save_manager_popup")
	if root.get_node_or_null("SaveManagerPopup") != null:
		_fail("f6: SaveManagerPopup still opened")
		return
	var menu := root.get_node_or_null("MainMenu")
	if menu == null:
		_fail("f6: Command Center did not open")
		return
	_pass("f6: save browser opens the Command Center list")
	if menu.has_method("_force_close"):
		menu.call("_force_close")


func _test_live_win_then_loss() -> void:
	var tm := root.get_node_or_null("TimeManager")
	var lm := root.get_node_or_null("LeaderManager")
	var gd := root.get_node_or_null("GameData")
	if tm == null or lm == null or gd == null:
		_fail("end: autoload missing")
		return
	var rules := _read_rules()
	var dom: Script = load("res://scripts/core/CampaignInkEndDomain.gd") as Script
	var screen: Script = load("res://scripts/ui/CampaignInkEndScreen.gd") as Script
	if dom == null or screen == null:
		_fail("end: scripts missing")
		return
	dom.call("reset_for_test")
	screen.call("clear_log")
	lm.call("set_player_country_tag", "GER")
	var end := str(rules.get("end_date", "1949-01-01"))
	tm.current_year = int(end.substr(0, 4))
	tm.current_month = int(end.substr(5, 2))
	tm.current_day = int(end.substr(8, 2))
	tm.set_paused(false)
	var result: Dictionary = dom.call("evaluate_day")
	if not bool(result.get("win", false)):
		_fail("win: evaluate_day did not fire on the data end date")
		return
	var win_screen := _ink_screen()
	if win_screen == null:
		_fail("win: end screen missing")
		return
	var win_title := win_screen.find_child("OutcomeTitle", true, false)
	if win_title == null or str(win_title.text) != "VICTORY":
		_fail("win: title is not VICTORY")
		return
	var win_sub := win_screen.find_child("OutcomeSubtitle", true, false)
	if win_sub == null or str(win_sub.text).find("1 January 1949") < 0 or str(win_sub.text).find("prevailed") >= 0:
		_fail("win: 1949 timeout subtitle is '%s'" % (str(win_sub.text) if win_sub != null else "missing"))
		return
	var win_why := win_screen.find_child("OutcomeReason", true, false)
	if win_why == null or str(win_why.text).find("1 January 1949") < 0 or str(win_why.text).find("end_date") >= 0:
		_fail("win: 1949 timeout reason is '%s'" % (str(win_why.text) if win_why != null else "missing"))
		return
	if win_screen.find_child("PathTitle", true, false) != null:
		_fail("win: PathTitle shown with Victory Paths off")
		return
	if win_screen.find_child("BtnKeepPlaying", true, false) == null:
		_fail("win: Keep playing missing")
		return
	if not tm.is_paused():
		_fail("win: clock still running")
		return
	var keep := win_screen.find_child("BtnKeepPlaying", true, false)
	if keep is BaseButton:
		(keep as BaseButton).pressed.emit()
	_pass("win: data end date paused and showed VICTORY")
	screen.call("clear_log")
	tm.set_paused(false)
	gd.call("trigger_national_defeat_or_continuation", "GER", "Headless defeat test")
	if not tm.is_paused():
		_fail("loss: clock was not paused")
		return
	var loss := _ink_screen()
	if loss == null:
		_fail("loss: end screen missing")
		return
	var loss_title := loss.find_child("OutcomeTitle", true, false)
	if loss_title == null or str(loss_title.text) != "DEFEAT":
		_fail("loss: title is not DEFEAT")
		return
	var loss_sub := loss.find_child("OutcomeSubtitle", true, false)
	if loss_sub == null or str(loss_sub.text).find("Continue as another nation") < 0:
		_fail("loss: subtitle is '%s'" % (str(loss_sub.text) if loss_sub != null else "missing"))
		return
	if get_nodes_in_group("continuation_picker").size() != 0:
		_fail("loss: picker opened before Continue as…")
		return
	var log: Array = screen.call("log_entries")
	if log.find("end_screen") < 0 or log.find("picker") >= 0:
		_fail("loss: log before continue = %s" % str(log))
		return
	var cont := loss.find_child("BtnContinueAs", true, false)
	if cont == null:
		_fail("loss: Continue as… missing")
		return
	if cont is BaseButton:
		(cont as BaseButton).pressed.emit()
	log = screen.call("log_entries")
	if log.find("end_screen") < 0 or log.find("picker") < 0 or log.find("end_screen") > log.find("picker"):
		_fail("loss: screen was not before the picker (%s)" % str(log))
		return
	if get_nodes_in_group("continuation_picker").is_empty():
		_fail("loss: Continue as… did not open the picker")
		return
	_pass("loss: end screen before the continuation picker, clock paused")


func _test_option_a_end_strings() -> void:
	var screen: Script = load("res://scripts/ui/CampaignInkEndScreen.gd") as Script
	if screen == null:
		_fail("option-a: CampaignInkEndScreen missing")
		return
	var timeout_sub := str(screen.call("player_subtitle", "win", "end_date"))
	var timeout_why := str(screen.call("player_reason_text", "end_date"))
	var win_sub := str(screen.call("player_subtitle", "win", "enemy_capitals"))
	var win_why := str(screen.call("player_reason_text", "enemy_capitals"))
	var both_why := str(screen.call("player_reason_text", "end_date, enemy_capitals"))
	var loss_sub := str(screen.call("player_subtitle", "loss", "capitulated"))
	if timeout_why.find("1 January 1949") < 0 or timeout_why.find("end_date") >= 0:
		_fail("option-a: timeout reason '%s'" % timeout_why)
		return
	if timeout_sub.find("1 January 1949") < 0 or timeout_sub.find("prevailed") >= 0:
		_fail("option-a: timeout subtitle '%s'" % timeout_sub)
		return
	if win_sub.find("prevailed") < 0 or win_why.find("enemy capital") < 0:
		_fail("option-a: win copy sub='%s' why='%s'" % [win_sub, win_why])
		return
	if both_why.find("1 January 1949") < 0 or both_why.find("enemy capital") < 0:
		_fail("option-a: combined reason '%s'" % both_why)
		return
	if both_why.find("end_date") >= 0 or both_why.find("enemy_capitals") >= 0:
		_fail("option-a: combined reason still jargon '%s'" % both_why)
		return
	if loss_sub.find("Continue as another nation") < 0:
		_fail("option-a: loss subtitle '%s'" % loss_sub)
		return
	for bad in ["Atomic", "Arsenal of the World", "Victory Paths", "Satellite"]:
		if timeout_sub.find(bad) >= 0 or timeout_why.find(bad) >= 0 or win_sub.find(bad) >= 0 or loss_sub.find(bad) >= 0:
			_fail("option-a: default copy mentions %s" % bad)
			return
	_free_group("campaign_ink_end_screen")
	_free_group("continuation_picker")
	screen.call("clear_log")
	screen.call("present_win", "GER", "end_date")
	var win := _ink_screen()
	if win == null:
		_fail("option-a: timeout screen missing")
		return
	var shown_sub := win.find_child("OutcomeSubtitle", true, false)
	var shown_why := win.find_child("OutcomeReason", true, false)
	if shown_sub == null or str(shown_sub.text) != timeout_sub:
		_fail("option-a: rendered timeout subtitle '%s'" % (str(shown_sub.text) if shown_sub != null else "missing"))
		return
	if shown_why == null or str(shown_why.text) != timeout_why:
		_fail("option-a: rendered timeout reason '%s'" % (str(shown_why.text) if shown_why != null else "missing"))
		return
	if win.find_child("PathTitle", true, false) != null:
		_fail("option-a: PathTitle on default timeout")
		return
	_free_group("campaign_ink_end_screen")
	var gd := root.get_node_or_null("GameData")
	var lm := root.get_node_or_null("LeaderManager")
	if gd == null or lm == null:
		_fail("option-a: autoload missing")
		return
	lm.call("set_player_country_tag", "GER")
	gd.call("trigger_national_defeat_or_continuation", "GER", "option-a loss")
	var loss := _ink_screen()
	if loss == null:
		_fail("option-a: DEFEAT missing")
		return
	var cont := loss.find_child("BtnContinueAs", true, false)
	if not (cont is BaseButton):
		_fail("option-a: Continue as… missing")
		return
	(cont as BaseButton).pressed.emit()
	var picker := _picker()
	if picker == null:
		_fail("option-a: picker missing")
		return
	var header := _picker_header(picker)
	if header.find("Choose nation to continue playing as") < 0:
		_fail("option-a: picker header '%s'" % header)
		return
	_pass("option-a: 1949 timeout, win/loss, and Continue as… copy")
	_free_group("continuation_picker")
	_free_group("campaign_ink_end_screen")


func _test_clock_stays_paused_under_overlays() -> void:
	_free_menu()
	_free_group("campaign_ink_end_screen")
	_free_group("continuation_picker")
	var tm := root.get_node_or_null("TimeManager")
	var bar := _make_bar()
	if tm == null or bar == null:
		_fail("clock: autoload or bar missing")
		return
	tm.set_paused(false)
	tm.set_time_scale(2.0)
	bar.set("current_speed", 2)
	bar.set("is_paused", false)
	bar.set_meta("player_owns_clock", true)
	var elapsed0 := int(tm.total_days_elapsed)
	var menu := _make_menu()
	if menu == null:
		_fail("clock: CC missing")
		return
	if not bool(tm.call("is_paused")):
		_fail("clock: CC did not pause TimeManager")
		return
	bar.call("_set_game_speed", 4)
	if not bool(tm.call("is_paused")) or not is_equal_approx(float(tm.time_scale), 2.0):
		_fail("clock: speed key moved TimeManager under CC (paused=%s scale=%s)" % [str(tm.call("is_paused")), str(tm.time_scale)])
		return
	bar.call("_on_pause_pressed")
	if bar.has_method("_step_live_clock"):
		bar.call("_step_live_clock")
	if not bool(tm.call("is_paused")):
		_fail("clock: pause/space still moved TimeManager under CC")
		return
	if not is_equal_approx(float(tm.time_scale), 2.0):
		_fail("clock: speed under CC changed scale to %s" % str(tm.time_scale))
		return
	if int(tm.total_days_elapsed) != elapsed0:
		_fail("clock: days advanced under CC")
		return
	if menu.has_method("_force_close"):
		menu.call("_force_close")
	if bool(tm.call("is_paused")):
		_fail("clock: Resume did not restore the earlier running state")
		return
	if not is_equal_approx(float(tm.time_scale), 2.0):
		_fail("clock: Resume lost 2x (scale=%s)" % str(tm.time_scale))
		return
	_pass("clock: CC blocks speed keys and Resume restores 2x")
	tm.set_paused(false)
	tm.set_time_scale(3.0)
	bar.set("current_speed", 3)
	bar.set("is_paused", false)
	var screen: Script = load("res://scripts/ui/CampaignInkEndScreen.gd") as Script
	if screen == null:
		_fail("clock: end screen script missing")
		return
	screen.call("present_win", "GER", "end_date")
	if not bool(tm.call("is_paused")):
		_fail("clock: VICTORY did not pause")
		return
	bar.call("_set_game_speed", 4)
	if not bool(tm.call("is_paused")) or not is_equal_approx(float(tm.time_scale), 3.0):
		_fail("clock: speed key moved the clock under VICTORY")
		return
	var win := _ink_screen()
	var keep := win.find_child("BtnKeepPlaying", true, false) if win != null else null
	if keep is BaseButton:
		(keep as BaseButton).pressed.emit()
	if bool(tm.call("is_paused")):
		_fail("clock: Keep playing did not restore the earlier running state")
		return
	if not is_equal_approx(float(tm.time_scale), 3.0):
		_fail("clock: Keep playing lost 3x (scale=%s)" % str(tm.time_scale))
		return
	_pass("clock: VICTORY blocks speed keys and Keep playing restores 3x")


func _test_continue_as_closes_in_order() -> void:
	_free_menu()
	_free_group("campaign_ink_end_screen")
	_free_group("continuation_picker")
	var tm := root.get_node_or_null("TimeManager")
	var lm := root.get_node_or_null("LeaderManager")
	var gd := root.get_node_or_null("GameData")
	var screen: Script = load("res://scripts/ui/CampaignInkEndScreen.gd") as Script
	if tm == null or lm == null or gd == null or screen == null:
		_fail("continue: autoload missing")
		return
	_free_group("campaign_ink_end_screen")
	_free_group("continuation_picker")
	screen.call("clear_log")
	lm.call("set_player_country_tag", "GER")
	tm.set_paused(false)
	tm.set_time_scale(2.0)
	gd.call("trigger_national_defeat_or_continuation", "GER", "continue-order")
	var loss := _ink_screen()
	if loss == null:
		_fail("continue: DEFEAT missing")
		return
	var cont := loss.find_child("BtnContinueAs", true, false)
	if not (cont is BaseButton):
		_fail("continue: Continue as… missing")
		return
	(cont as BaseButton).pressed.emit()
	var picker := _picker()
	if picker == null:
		_fail("continue: picker missing")
		return
	if _ink_screen() == null:
		_fail("continue: DEFEAT vanished when the picker opened")
		return
	var cancel := picker.find_child("BtnCancelPicker", true, false)
	if not (cancel is BaseButton):
		_fail("continue: Cancel missing on picker")
		return
	(cancel as BaseButton).pressed.emit()
	if _picker() != null:
		_fail("continue: Cancel left the picker in the tree")
		return
	if _ink_screen() == null:
		_fail("continue: Cancel did not return to DEFEAT")
		return
	if str(lm.player_country_tag).strip_edges().to_upper() != "GER":
		_fail("continue: Cancel switched the player")
		return
	cont = _ink_screen().find_child("BtnContinueAs", true, false)
	if cont is BaseButton:
		(cont as BaseButton).pressed.emit()
	picker = _picker()
	if picker == null:
		_fail("continue: picker did not reopen")
		return
	var usa := picker.find_child("BtnPick_USA", true, false)
	if not (usa is BaseButton):
		_fail("continue: USA pick button missing")
		return
	(usa as BaseButton).pressed.emit()
	if str(lm.player_country_tag).strip_edges().to_upper() != "GER":
		_fail("continue: pick switched before Confirm")
		return
	var confirm := picker.find_child("BtnConfirmContinue", true, false)
	if not (confirm is BaseButton):
		_fail("continue: Confirm missing")
		return
	(confirm as BaseButton).pressed.emit()
	if _picker() != null:
		_fail("continue: picker still in the tree after Confirm")
		return
	if _ink_screen() != null:
		_fail("continue: DEFEAT still in the tree after Confirm")
		return
	if str(lm.player_country_tag).strip_edges().to_upper() != "USA":
		_fail("continue: player is %s after Confirm" % str(lm.player_country_tag))
		return
	if _orphaned_end_nodes():
		_fail("continue: leftover picker or end screen in the tree")
		return
	_pass("continue: Cancel returns to DEFEAT; Confirm closes both and switches")


## A successful load from DEFEAT must dismiss the end screen and any continuation
## picker, then restore the clock the save carried. A missing slot must leave both up.
func _test_defeat_load_closes_end_screen() -> void:
	_free_menu()
	_free_group("campaign_ink_end_screen")
	_free_group("continuation_picker")
	var tm := root.get_node_or_null("TimeManager")
	var sl := root.get_node_or_null("SaveLoadManager")
	var lm := root.get_node_or_null("LeaderManager")
	var gd := root.get_node_or_null("GameData")
	if tm == null or sl == null or lm == null or gd == null:
		_fail("defeat-load: autoload missing")
		return
	var bar := _make_bar()
	if bar == null:
		_fail("defeat-load: top bar missing")
		return
	lm.call("set_player_country_tag", "GER")
	tm.set_paused(false)
	tm.set_time_scale(3.0)
	bar.set("current_speed", 3)
	bar.set("is_paused", false)
	var saved: Dictionary = sl.call("save_game_detailed", "quicksave")
	if not bool(saved.get("ok", false)):
		_fail("defeat-load: quicksave failed %s" % str(saved.get("error", "")))
		return
	gd.call("trigger_national_defeat_or_continuation", "GER", "defeat-load")
	var loss := _ink_screen()
	if loss == null:
		_fail("defeat-load: DEFEAT missing")
		return
	var cont := loss.find_child("BtnContinueAs", true, false)
	if cont is BaseButton:
		(cont as BaseButton).pressed.emit()
	if _picker() == null or _ink_screen() == null:
		_fail("defeat-load: DEFEAT or picker missing before load")
		return
	var missing: Dictionary = sl.call("load_game_detailed", "qr1_missing_slot")
	if bool(missing.get("ok", false)):
		_fail("defeat-load: missing slot loaded")
		return
	if _ink_screen() == null or _picker() == null:
		_fail("defeat-load: failed load dismissed DEFEAT or the picker")
		return
	if not bool(tm.call("overlay_holds_clock")) or not bool(tm.call("is_paused")):
		_fail("defeat-load: failed load released the clock")
		return
	if not bool(sl.call("quickload")):
		_fail("defeat-load: quickload failed")
		return
	if _ink_screen() != null or _picker() != null or _orphaned_end_nodes():
		_fail("defeat-load: quickload left DEFEAT, picker, or an orphan")
		return
	if bool(tm.call("overlay_holds_clock")):
		_fail("defeat-load: clock lock still held after quickload")
		return
	if bool(tm.call("is_paused")) or not is_equal_approx(float(tm.time_scale), 3.0):
		_fail("defeat-load: quickload clock paused=%s scale=%s" % [str(tm.call("is_paused")), str(tm.time_scale)])
		return
	if int(bar.get("current_speed")) != 3 or bool(bar.get("is_paused")):
		_fail("defeat-load: bar speed=%s paused=%s after quickload" % [str(bar.get("current_speed")), str(bar.get("is_paused"))])
		return
	_pass("defeat-load: failed load keeps DEFEAT; Ctrl+L closes it and restores 3x")
	tm.set_paused(false)
	tm.set_time_scale(2.0)
	bar.set("current_speed", 2)
	bar.set("is_paused", false)
	saved = sl.call("save_game_detailed", "quicksave")
	if not bool(saved.get("ok", false)):
		_fail("defeat-load: 2x quicksave failed")
		return
	_free_menu()
	gd.call("trigger_national_defeat_or_continuation", "GER", "defeat-load-cc")
	loss = _ink_screen()
	if loss == null:
		_fail("defeat-load: second DEFEAT missing")
		return
	cont = loss.find_child("BtnContinueAs", true, false)
	if cont is BaseButton:
		(cont as BaseButton).pressed.emit()
	if _picker() == null:
		_fail("defeat-load: second picker missing")
		return
	var load_btn := loss.find_child("BtnLoadSave", true, false)
	if not (load_btn is BaseButton):
		_fail("defeat-load: Load save button missing")
		return
	(load_btn as BaseButton).pressed.emit()
	var menu := root.get_node_or_null("MainMenu")
	if menu == null or not is_instance_valid(menu) or menu.is_queued_for_deletion():
		_fail("defeat-load: Load save did not open Command Center")
		return
	if not menu.has_method("_load_slot_now"):
		_fail("defeat-load: Command Center has no _load_slot_now")
		return
	menu.call("_load_slot_now", "quicksave")
	if _ink_screen() != null or _picker() != null or _orphaned_end_nodes():
		_fail("defeat-load: slot load left DEFEAT, picker, or an orphan")
		return
	menu = root.get_node_or_null("MainMenu")
	if menu != null and is_instance_valid(menu) and not menu.is_queued_for_deletion():
		_fail("defeat-load: Command Center stayed open after slot load")
		return
	if bool(tm.call("overlay_holds_clock")):
		_fail("defeat-load: clock lock still held after slot load")
		return
	if bool(tm.call("is_paused")) or not is_equal_approx(float(tm.time_scale), 2.0):
		_fail("defeat-load: slot load clock paused=%s scale=%s" % [str(tm.call("is_paused")), str(tm.time_scale)])
		return
	if int(bar.get("current_speed")) != 2 or bool(bar.get("is_paused")):
		_fail("defeat-load: bar speed=%s paused=%s after slot load" % [str(bar.get("current_speed")), str(bar.get("is_paused"))])
		return
	_pass("defeat-load: Load save then slot load closes DEFEAT, picker, and Command Center at 2x")
	_free_menu()
	_free_group("campaign_ink_end_screen")
	_free_group("continuation_picker")


func _test_save_hint_and_f6_loyalty() -> void:
	var bar := _make_bar()
	if bar == null:
		_fail("hint: top bar missing")
		return
	var save_tip := ""
	var save_btn: Variant = bar.get("save_button")
	if save_btn is Control:
		save_tip = str((save_btn as Control).tooltip_text)
	var menu_tip := ""
	var menu_btn: Variant = bar.get("menu_button")
	if menu_btn is Control:
		menu_tip = str((menu_btn as Control).tooltip_text)
	if save_tip.find("Ctrl+Shift+S") < 0 and menu_tip.find("Ctrl+Shift+S") < 0:
		_fail("hint: top bar save control tooltip missing Ctrl+Shift+S (save='%s' menu='%s')" % [save_tip, menu_tip])
		return
	var menu := _make_menu()
	if menu == null:
		_fail("hint: CC missing")
		return
	var hint := menu.find_child("SaveListHint", true, false)
	if hint == null or str(hint.text).find("Ctrl+Shift+S") < 0:
		_fail("hint: CC save/load section missing Ctrl+Shift+S")
		return
	if not (hint is Control) or (hint as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE:
		_fail("hint: SaveListHint mouse_filter IGNORE hides the tooltip")
		return
	var tip := str((hint as Control).tooltip_text)
	if tip.find("Ctrl+Shift+S") < 0:
		_fail("hint: SaveListHint tooltip missing Ctrl+Shift+S ('%s')" % tip)
		return
	var mr_src := FileAccess.get_file_as_string("res://scripts/map/MapRenderer.gd")
	var f6 := mr_src.find("keycode == KEY_F6")
	if f6 < 0:
		_fail("f6: KEY_F6 missing on MapRenderer")
		return
	var slice := mr_src.substr(f6, 180)
	if slice.find("loyalty") < 0:
		_fail("f6: KEY_F6 is no longer the loyalty mapmode")
		return
	if slice.find("save") >= 0 or slice.find("Save") >= 0:
		_fail("f6: KEY_F6 was rebound toward save")
		return
	_pass("hint: Ctrl+Shift+S on save list; F6 stays loyalty")
	if menu.has_method("_force_close"):
		menu.call("_force_close")


func _test_save_list_polish() -> void:
	_free_menu()
	var sl := root.get_node_or_null("SaveLoadManager")
	var tm := root.get_node_or_null("TimeManager")
	var lm := root.get_node_or_null("LeaderManager")
	if sl == null or tm == null or lm == null:
		_fail("polish: autoload missing")
		return
	var sl_src := FileAccess.get_file_as_string("res://scripts/autoload/SaveLoadManager.gd")
	if sl_src.find("const SAVE_VERSION := 2") < 0:
		_fail("polish: SAVE_VERSION is not 2")
		return
	lm.call("set_player_country_tag", "GER")
	tm.current_year = 1936
	tm.current_month = 3
	tm.current_day = 14
	tm.total_days_elapsed = 14
	var saved: Dictionary = sl.call("save_game_detailed", SLOT)
	if not bool(saved.get("ok", false)):
		_fail("polish: save failed")
		return
	var row := _slot_row(sl, SLOT)
	var when := str(row.get("when_line", ""))
	var saved_at := when
	var idx := when.find("Saved ")
	if idx >= 0:
		saved_at = when.substr(idx)
	if saved_at.find("T") >= 0:
		_fail("polish: save time is still ISO/UTC with T ('%s')" % when)
	if saved_at.find("Saved ") < 0:
		_fail("polish: when_line missing Saved ('%s')" % when)
	tm.current_year = 1936
	tm.current_month = 3
	tm.current_day = 14
	var auto1: Dictionary = sl.call("save_game_detailed", "autosave")
	if not bool(auto1.get("ok", false)):
		_fail("polish: first autosave failed")
		return
	var auto_slot := str(auto1.get("slot", "autosave_1"))
	var menu := _make_menu()
	if menu == null:
		_fail("polish: CC missing")
		return
	var card := menu.find_child("SlotCard_%s" % auto_slot, true, false)
	var detail := card.find_child("SlotDetail", true, false) if card != null else null
	if detail == null or str(detail.text).find("14 Mar 1936") < 0:
		_fail("polish: autosave card missing 14 Mar 1936 ('%s')" % (str(detail.text) if detail != null else "missing"))
		return
	tm.current_year = 1936
	tm.current_month = 4
	tm.current_day = 20
	tm.total_days_elapsed = 51
	var auto2: Dictionary = sl.call("save_game_detailed", "autosave")
	if not bool(auto2.get("ok", false)):
		_fail("polish: rewritten autosave failed")
		return
	if menu.has_method("_refresh_save_list"):
		menu.call("_refresh_save_list")
	var auto_slot2 := str(auto2.get("slot", auto_slot))
	card = menu.find_child("SlotCard_%s" % auto_slot2, true, false)
	detail = card.find_child("SlotDetail", true, false) if card != null else null
	var detail_txt := str(detail.text) if detail != null else ""
	if detail_txt.find("20 Apr 1936") < 0:
		_fail("polish: autosave card did not refresh in-game date ('%s')" % detail_txt)
		return
	if auto_slot2 == auto_slot and detail_txt.find("14 Mar 1936") >= 0:
		_fail("polish: stale autosave date still on the card ('%s')" % detail_txt)
		return
	var bad_path := str(sl.call("get_save_path", "slot2"))
	var bf := FileAccess.open(bad_path, FileAccess.WRITE)
	if bf == null:
		_fail("polish: could not write corrupt slot2")
		return
	bf.store_string("{not json")
	bf.close()
	var bad_row := _slot_row(sl, "slot2")
	var blob := str(bad_row.get("nation_line", "")) + "\n" + str(bad_row.get("when_line", "")) + "\n" + str(bad_row.get("game_date_label", ""))
	if blob.find("unreadable") < 0 and blob.find("Unreadable") < 0:
		_fail("polish: corrupt card is a bare dash ('%s')" % blob)
		return
	var tag_before := str(lm.player_country_tag)
	var loaded: Dictionary = sl.call("load_game_detailed", "slot2")
	if bool(loaded.get("ok", false)):
		_fail("polish: corrupt slot2 loaded")
		return
	if str(loaded.get("error", "")).find("unreadable") < 0:
		_fail("polish: corrupt load error '%s'" % str(loaded.get("error", "")))
		return
	if str(lm.player_country_tag) != tag_before:
		_fail("polish: corrupt load mutated player tag")
		return
	_pass("polish: local save time, autosave date refresh, corrupt slot unreadable")
	if menu.has_method("_force_close"):
		menu.call("_force_close")


func _test_victory_render() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if root is Window:
		(root as Window).size = Vector2i(1280, 800)
	_free_group("campaign_ink_end_screen")
	var screen: Script = load("res://scripts/ui/CampaignInkEndScreen.gd") as Script
	if screen == null:
		_fail("victory: script missing")
		return
	var why := "end_date, enemy_capitals"
	screen.call("present_win", "GER", why)
	var win := _ink_screen()
	if win == null:
		_fail("victory: screen missing")
		return
	var title := win.find_child("OutcomeTitle", true, false)
	if title == null or str(title.text) != "VICTORY":
		_fail("victory: title is not VICTORY")
		return
	var reason := win.find_child("OutcomeReason", true, false)
	if reason == null or str(reason.text).find("1 January 1949") < 0:
		_fail("victory: 1949 timeout wording missing")
		return
	if str(reason.text).find("end_date") >= 0 or str(reason.text).find("enemy_capitals") >= 0:
		_fail("victory: still shows jargon '%s'" % str(reason.text))
		return
	var vp := Rect2(0, 0, 1280, 800)
	for nm in ["OutcomeTitle", "OutcomeReason", "BtnKeepPlaying", "BtnSave", "BtnMainMenu"]:
		var n := win.find_child(nm, true, false)
		if not (n is Control):
			_fail("victory: %s missing" % nm)
			return
		var r: Rect2 = (n as Control).get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > vp.size.x + 1.0 or r.end.y > vp.size.y + 1.0:
			_fail("victory: %s outside 1280×800 at %s" % [nm, str(r)])
			return
	_pass("victory: VICTORY reasons and buttons inside 1280×800")
	if win.has_method("_dismiss_end_screen"):
		win.call("_dismiss_end_screen")
	else:
		win.queue_free()


func _test_1949_latch_one_overlay() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var tm := root.get_node_or_null("TimeManager")
	var sl := root.get_node_or_null("SaveLoadManager")
	var lm := root.get_node_or_null("LeaderManager")
	var ev := root.get_node_or_null("LeaderEventUI")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var war: GDScript = load("res://scripts/core/WarStateDomain.gd") as GDScript
	var cap: GDScript = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	var end: GDScript = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	var ink: GDScript = load("res://scripts/core/CampaignInkEndDomain.gd") as GDScript
	var ink_screen: GDScript = load("res://scripts/ui/CampaignInkEndScreen.gd") as GDScript
	if mm == null or tm == null or sl == null or lm == null or boot == null or war == null or cap == null or end == null or ink == null:
		_fail("1949: autoload or domain missing")
		return
	_free_group("campaign_ink_end_screen")
	_free_group("campaign_end_screen")
	_free_group("continuation_picker")
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("1949: board boot failed")
		return
	cap.call("apply_economy_factories_to_map")
	war.call("reset_for_test")
	cap.call("reset_for_test")
	end.call("reset_for_test")
	ink.call("reset_for_test")
	if ink_screen != null and ink_screen.has_method("clear_log"):
		ink_screen.call("clear_log")
	lm.call("set_player_country_tag", "GER")
	tm.current_year = 1949
	tm.current_month = 1
	tm.current_day = 1
	tm.current_hour = 0
	tm.total_days_elapsed = 13 * 365
	if tm.has_method("set_paused"):
		tm.call("set_paused", false)
	else:
		tm.paused = false
	if not bool(war.call("loop_enabled")):
		_fail("1949: campaign loop is off")
		_cleanup_1949(end, ev, tm)
		return
	tm.call("_campaign_after_battles")
	await process_frame
	await process_frame
	if not bool(end.call("latched")):
		_fail("1949: campaign_end did not latch")
		_cleanup_1949(end, ev, tm)
		return
	var model: Dictionary = end.call("view_model")
	var ranked: Array = end.call("factory_rank")
	var rank := 1
	for i in range(ranked.size()):
		if str(ranked[i]) == "GER":
			rank = i + 1
			break
	var want_title := "Victory: Ascendant" if rank == 1 else "Defeat: Eclipsed (rank %d)" % rank
	if str(model.get("kind", "")) != "time":
		_fail("1949: kind=%s want time" % str(model.get("kind", "")))
		_cleanup_1949(end, ev, tm)
		return
	if str(model.get("title", "")) != want_title:
		_fail("1949: model title '%s' want '%s'" % [str(model.get("title", "")), want_title])
		_cleanup_1949(end, ev, tm)
		return
	var cl1 := _cl1_screen()
	var ink_n := _ink_screen()
	var cl1_n := 0
	for n in get_nodes_in_group("campaign_end_screen"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and not str(n.name).ends_with("_dying"):
			cl1_n += 1
	var ink_count := 0
	for n2 in get_nodes_in_group("campaign_ink_end_screen"):
		if is_instance_valid(n2) and not n2.is_queued_for_deletion() and not str(n2.name).ends_with("_dying"):
			ink_count += 1
	if cl1 == null or cl1_n != 1:
		_fail("1949: want exactly one CL1 panel got %d" % cl1_n)
		_cleanup_1949(end, ev, tm)
		return
	if ink_n != null or ink_count != 0:
		_fail("1949: Ink 1949 panel still showing (count=%d)" % ink_count)
		_cleanup_1949(end, ev, tm)
		return
	var title := cl1.find_child("Title", true, false)
	if title == null or str(title.text) != want_title:
		_fail("1949: panel title '%s' want '%s'" % [str(title.text) if title != null else "missing", want_title])
		_cleanup_1949(end, ev, tm)
		return
	var reason_l := cl1.find_child("Reason", true, false)
	var reason_txt := str(reason_l.text) if reason_l != null else ""
	if reason_l != null and reason_l.visible and (reason_txt == want_title or reason_txt == want_title + "."):
		_fail("1949: verdict line duplicated title+reason '%s'" % reason_txt)
		_cleanup_1949(end, ev, tm)
		return
	var keep_btn := cl1.find_child("BtnKeepPlaying", true, false) as Button
	var want_keep := "Continue as Germany"
	if end.has_method("keep_playing_label"):
		want_keep = str(end.call("keep_playing_label", "GER"))
	if keep_btn == null or str(keep_btn.text) != want_keep:
		_fail("1949: Keep playing label '%s' want '%s'" % [str(keep_btn.text) if keep_btn != null else "missing", want_keep])
		_cleanup_1949(end, ev, tm)
		return
	if rank != 1 and str(title.text).find("VICTORY") >= 0:
		_fail("1949: VICTORY label on Eclipsed/Defeat")
		_cleanup_1949(end, ev, tm)
		return
	var date_l := cl1.find_child("Date", true, false)
	if date_l == null or str(date_l.text).find("1 January 1949") < 0 or str(date_l.text).find("1949-01-01") >= 0:
		_fail("1949: date '%s' is not 1 January 1949" % (str(date_l.text) if date_l != null else "missing"))
		_cleanup_1949(end, ev, tm)
		return
	var stats_l := cl1.find_child("Stats", true, false)
	if stats_l != null and str(stats_l.text).find("Provinces (controlled) 0 →") >= 0:
		_fail("1949: provinces baseline still 0 (%s)" % str(stats_l.text))
		_cleanup_1949(end, ev, tm)
		return
	if not bool(tm.paused) and not (tm.has_method("is_paused") and bool(tm.call("is_paused"))):
		_fail("1949: clock not paused after latch")
		_cleanup_1949(end, ev, tm)
		return
	if not bool(end.call("clock_locked")):
		_fail("1949: clock_locked is false")
		_cleanup_1949(end, ev, tm)
		return
	if ev != null and ev.has_method("hold_for_campaign_end"):
		if ev.has_method("events_held_for_campaign_end") and not bool(ev.call("events_held_for_campaign_end")):
			_fail("1949: LeaderEventUI hold not set")
			_cleanup_1949(end, ev, tm)
			return
	if lm.has_signal("leader_retirement_offered"):
		lm.emit_signal("leader_retirement_offered", "cs1_1949_fake_leader")
	await process_frame
	await process_frame
	if _leadership_popup_visible():
		_fail("1949: Leadership Transition popped after latch")
		_cleanup_1949(end, ev, tm)
		return
	var year0 := int(tm.current_year)
	var day0 := int(tm.current_day)
	if tm.has_method("set_paused"):
		tm.call("set_paused", false)
	else:
		tm.paused = false
	if tm.has_method("advance_one_day"):
		tm.call("advance_one_day")
	if int(tm.current_year) != year0 or int(tm.current_day) != day0:
		_fail("1949: clock moved after latch to %04d-%02d-%02d" % [int(tm.current_year), int(tm.current_month), int(tm.current_day)])
		_cleanup_1949(end, ev, tm)
		return
	var saved: Dictionary = sl.call("save_game_detailed", "cs1_1949_latch")
	if not bool(saved.get("ok", false)):
		_fail("1949: save failed %s" % str(saved.get("error", "")))
		_cleanup_1949(end, ev, tm)
		return
	var loaded: Dictionary = sl.call("load_game_detailed", "cs1_1949_latch")
	if not bool(loaded.get("ok", false)):
		_fail("1949: load failed %s" % str(loaded.get("error", "")))
		_cleanup_1949(end, ev, tm)
		return
	_pass("1949: save/load after latch")
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	_free_menu()
	var menu := _make_menu()
	if menu == null:
		_fail("1949: Command Center missing for Return to Title")
		_cleanup_1949(end, ev, tm)
		return
	await process_frame
	await process_frame
	await process_frame
	var ret := _return_to_title_button(menu)
	if ret == null:
		_fail("1949: Return to Title missing")
		_cleanup_1949(end, ev, tm)
		return
	ret.pressed.emit()
	await process_frame
	if is_instance_valid(menu) and not menu.is_queued_for_deletion():
		_fail("1949: Return to Title did not close Command Center")
		_cleanup_1949(end, ev, tm)
		return
	_pass("1949: one overlay, rank title, formatted date, paused, no event, save/load, Return to Title")
	_cleanup_1949(end, ev, tm)


func _test_near_capitulation_real_tick() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var tm := root.get_node_or_null("TimeManager")
	var sl := root.get_node_or_null("SaveLoadManager")
	var lm := root.get_node_or_null("LeaderManager")
	var ev := root.get_node_or_null("LeaderEventUI")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var war: GDScript = load("res://scripts/core/WarStateDomain.gd") as GDScript
	var cap: GDScript = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	var end: GDScript = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if mm == null or tm == null or sl == null or lm == null or boot == null or war == null or cap == null or end == null:
		_fail("near-cap: autoload or domain missing")
		return
	_free_group("campaign_end_screen")
	_free_group("campaign_ink_end_screen")
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("near-cap: board boot failed")
		return
	if not _install_near_capitulation_slot(sl):
		return
	war.call("reset_for_test")
	cap.call("reset_for_test")
	end.call("reset_for_test")
	var loaded: Dictionary = sl.call("load_game_detailed", "near_capitulation")
	if not bool(loaded.get("ok", false)):
		_fail("near-cap: load failed %s" % str(loaded.get("error", "")))
		return
	lm.call("set_player_country_tag", "GER")
	if not bool(war.call("any_war")):
		_fail("near-cap: fixture did not restore GER-FRA war")
		return
	var prog := float(cap.call("progress", "GER"))
	var thresh := float(cap.call("threshold", "GER"))
	if prog + 0.0000001 < thresh:
		_fail("near-cap: after load progress %.4f < threshold %.4f (JSON by_pid keys?)" % [prog, thresh])
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	if bool(end.call("latched")):
		_fail("near-cap: already latched on load (must fire through the tick path)")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	if tm.has_method("set_paused"):
		tm.call("set_paused", false)
	else:
		tm.paused = false
	var n := 0
	const MAX_N := 15
	while n < MAX_N:
		if tm.has_method("advance_live_f5_equivalent_days"):
			tm.call("advance_live_f5_equivalent_days", 1)
		elif tm.has_method("advance_one_day"):
			tm.call("advance_one_day")
		else:
			_fail("near-cap: no real tick path")
			_cleanup_near_cap(end, ev, tm, war, cap)
			return
		n += 1
		if bool(end.call("latched")) or bool(cap.call("is_capitulated", "GER")):
			break
	if not bool(end.call("latched")):
		_fail("near-cap: no capitulation latch after %d real ticks (progress=%.4f thresh=%.4f)" % [n, float(cap.call("progress", "GER")), thresh])
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	var model: Dictionary = end.call("view_model")
	if str(model.get("kind", "")) != "defeat" and str(model.get("outcome", "")) != "defeat":
		_fail("near-cap: latched kind=%s outcome=%s want defeat" % [str(model.get("kind", "")), str(model.get("outcome", ""))])
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	var panel := _cl1_screen()
	if panel == null:
		_fail("near-cap: Defeat panel missing after %d ticks" % n)
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	print("NEAR_CAPITULATION_N_DAYS=%d" % n)
	_pass("near-cap: real tick path latched defeat in %d day(s)" % n)
	_cleanup_near_cap(end, ev, tm, war, cap)


func _test_return_begin_clears_war() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var tm := root.get_node_or_null("TimeManager")
	var sl := root.get_node_or_null("SaveLoadManager")
	var lm := root.get_node_or_null("LeaderManager")
	var ev := root.get_node_or_null("LeaderEventUI")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var war: GDScript = load("res://scripts/core/WarStateDomain.gd") as GDScript
	var cap: GDScript = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	var end: GDScript = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	var title_boot: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if mm == null or sl == null or lm == null or boot == null or war == null or end == null or title_boot == null:
		_fail("rtt-begin: autoload or domain missing")
		return
	_free_group("campaign_end_screen")
	_free_group("campaign_ink_end_screen")
	_free_menu()
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("rtt-begin: board boot failed")
		return
	if not _install_near_capitulation_slot(sl):
		return
	# Same slot as the prior real-tick test. SaveLoadManager skips a second
	# apply on the same process frame (`EOA_LOAD_APPLY skip duplicate`).
	await process_frame
	await process_frame
	var loaded: Dictionary = sl.call("load_game_detailed", "near_capitulation")
	if not bool(loaded.get("ok", false)):
		_fail("rtt-begin: load failed %s" % str(loaded.get("error", "")))
		return
	if not bool(war.call("any_war")):
		_fail("rtt-begin: fixture is not at war")
		return
	if ev != null and ev.has_method("hold_for_campaign_end"):
		ev.call("hold_for_campaign_end")
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	var menu := _make_menu()
	if menu == null:
		_fail("rtt-begin: Command Center missing")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	await process_frame
	var ret := _return_to_title_button(menu)
	if ret == null:
		_fail("rtt-begin: Return to Title missing")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	ret.pressed.emit()
	await process_frame
	await process_frame
	var begun: Dictionary = title_boot.call("apply_living_title_boot", "GER", 1936, "")
	if not bool(begun.get("ok", false)) and not bool(begun.get("applied", false)):
		_fail("rtt-begin: Begin apply failed %s" % str(begun))
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	if bool(war.call("any_war")):
		_fail("rtt-begin: Begin still at war (%s)" % str(war.call("player_enemies_line")))
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	if bool(end.call("latched")):
		_fail("rtt-begin: campaign_end still latched")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	if ev != null and ev.has_method("events_held_for_campaign_end") and bool(ev.call("events_held_for_campaign_end")):
		_fail("rtt-begin: LeaderEventUI hold still on")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	_pass("rtt-begin: Return to Title then Begin has 0 wars, no latch, no hold")
	_cleanup_near_cap(end, ev, tm, war, cap)


func _test_keep_playing_esc_opens_pause() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var tm := root.get_node_or_null("TimeManager")
	var ev := root.get_node_or_null("LeaderEventUI")
	var lm := root.get_node_or_null("LeaderManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var end: GDScript = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	var war: GDScript = load("res://scripts/core/WarStateDomain.gd") as GDScript
	var cap: GDScript = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	if tm == null or end == null or boot == null or mm == null:
		_fail("keep-esc: autoload missing")
		return
	_free_group("campaign_end_screen")
	_free_group("campaign_ink_end_screen")
	_free_menu()
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("keep-esc: board boot failed")
		return
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var bar := _make_bar()
	if bar == null:
		_fail("keep-esc: TopInfoBar missing")
		return
	tm.current_year = 1949
	tm.current_month = 1
	tm.current_day = 1
	tm.total_days_elapsed = 13 * 365
	if tm.has_method("set_paused"):
		tm.call("set_paused", false)
	if war != null and war.has_method("reset_for_test"):
		war.call("reset_for_test")
	if cap != null and cap.has_method("reset_for_test"):
		cap.call("reset_for_test")
	end.call("reset_for_test")
	tm.call("_campaign_after_battles")
	await process_frame
	await process_frame
	var cl1 := _cl1_screen()
	if cl1 == null:
		_fail("keep-esc: end overlay missing")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	var keep := cl1.find_child("BtnKeepPlaying", true, false) as Button
	if keep == null or not keep.visible:
		_fail("keep-esc: Continue as <nation> missing")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	keep.pressed.emit()
	await process_frame
	await process_frame
	if _cl1_screen() != null:
		_fail("keep-esc: overlay still up after Continue as")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.echo = false
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	if bar.has_method("_unhandled_input"):
		bar.call("_unhandled_input", esc)
	else:
		Input.parse_input_event(esc)
	await process_frame
	await process_frame
	var menu := root.get_node_or_null("MainMenu")
	if menu == null or not is_instance_valid(menu) or menu.is_queued_for_deletion():
		_fail("keep-esc: Esc did not open pause / Command Center")
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	var title := menu.find_child("CommandCenterTitle", true, false)
	if title == null or str(title.text) != "Paused":
		_fail("keep-esc: Command Center title '%s'" % (str(title.text) if title != null else "missing"))
		_cleanup_near_cap(end, ev, tm, war, cap)
		return
	_pass("keep-esc: Esc after Continue as opens pause menu")
	_cleanup_near_cap(end, ev, tm, war, cap)


func _install_near_capitulation_slot(sl: Node) -> bool:
	var src := ProjectSettings.globalize_path("res://tests/fixtures/campaign_save_1/near_capitulation.json")
	if not FileAccess.file_exists(src):
		_fail("near-cap: fixture missing %s" % src)
		return false
	var dest := ""
	if sl != null and sl.has_method("get_save_path_global"):
		dest = str(sl.call("get_save_path_global", "near_capitulation"))
	if dest.is_empty():
		dest = ProjectSettings.globalize_path("user://saves/near_capitulation.json")
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var err := DirAccess.copy_absolute(src, dest)
	if err != OK:
		var text := FileAccess.get_file_as_string(src)
		var out := FileAccess.open(dest, FileAccess.WRITE)
		if out == null:
			_fail("near-cap: could not install slot dest=%s err=%s" % [dest, str(err)])
			return false
		out.store_string(text)
		out.close()
	return true


func _cleanup_near_cap(end: GDScript, ev: Node, tm: Node, war: GDScript, cap: GDScript) -> void:
	_free_group("campaign_end_screen")
	_free_group("campaign_ink_end_screen")
	_free_group("continuation_picker")
	_free_menu()
	if end != null and end.has_method("reset_for_test"):
		end.call("reset_for_test")
	if war != null and war.has_method("reset_for_test"):
		war.call("reset_for_test")
	if cap != null and cap.has_method("reset_for_test"):
		cap.call("reset_for_test")
	if ev != null and ev.has_method("restore_after_campaign_end"):
		ev.call("restore_after_campaign_end")
	if tm != null:
		tm.current_year = 1936
		tm.current_month = 1
		tm.current_day = 1
		tm.total_days_elapsed = 0
		if tm.has_method("set_paused"):
			tm.call("set_paused", true)
		if tm.has_method("clear_overlay_clock_locks"):
			tm.call("clear_overlay_clock_locks")
	if root.has_meta("eoa_return_title_scene"):
		root.remove_meta("eoa_return_title_scene")


func _cleanup_1949(end: GDScript, ev: Node, tm: Node) -> void:
	_free_group("campaign_end_screen")
	_free_group("campaign_ink_end_screen")
	_free_group("continuation_picker")
	_free_menu()
	if end != null and end.has_method("reset_for_test"):
		end.call("reset_for_test")
	if ev != null and ev.has_method("restore_after_campaign_end"):
		ev.call("restore_after_campaign_end")
	if tm != null:
		tm.current_year = 1936
		tm.current_month = 1
		tm.current_day = 1
		tm.total_days_elapsed = 0
		if tm.has_method("set_paused"):
			tm.call("set_paused", true)
	if root.has_meta("eoa_return_title_scene"):
		root.remove_meta("eoa_return_title_scene")


func _leadership_popup_visible() -> bool:
	for n in root.get_children():
		if n == null or not is_instance_valid(n):
			continue
		if n is Window and str((n as Window).title).find("Leadership Transition") >= 0:
			return true
		var scr: Script = n.get_script()
		if scr != null and str(scr.resource_path).find("RetirementOfferPopup") >= 0:
			return true
	return false


func _test_cc_polish_and_first_return() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if root is Window:
		(root as Window).size = Vector2i(1280, 800)
	_free_menu()
	var bar := _make_bar()
	var menu := _make_menu()
	if bar == null or menu == null:
		_fail("polish2: bar or CC missing")
		return
	await process_frame
	await process_frame
	await process_frame
	var hint := menu.find_child("SaveListHint", true, false) as Control
	if hint == null or hint.mouse_filter == Control.MOUSE_FILTER_IGNORE or str(hint.tooltip_text).find("Ctrl+Shift+S") < 0:
		_fail("polish2: save-list tooltip is not on a visible control")
		return
	var resume := menu.find_child("BtnResume", true, false) as Button
	if resume == null or resume.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("polish2: Resume is not press-mode")
		return
	var ret := _return_to_title_button(menu)
	if ret == null:
		_fail("polish2: Return to Title missing")
		return
	if ret.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("polish2: Return to Title is not press-mode")
		return
	var scroll := menu.find_child("GameActionsScroll", true, false) as ScrollContainer
	if scroll != null and scroll.is_ancestor_of(ret):
		_fail("polish2: Return to Title is still inside the actions scroll")
		return
	var ret_rect := ret.get_global_rect()
	var view := Rect2(Vector2.ZERO, Vector2(1280, 800))
	if ret_rect.size.x < 8.0 or ret_rect.size.y < 8.0 or not view.encloses(ret_rect):
		_fail("polish2: Return to Title rect %s not fully on 1280×800" % str(ret_rect))
		return
	var bar_rect := (bar as Control).get_global_rect()
	var hud_pt := Vector2(640.0, clampf(bar_rect.get_center().y, 8.0, 48.0))
	root.push_input(_mouse_button(hud_pt, true))
	root.push_input(_mouse_button(hud_pt, false))
	await process_frame
	if menu == null or not is_instance_valid(menu) or menu.is_queued_for_deletion():
		_fail("polish2: top-bar click dismissed Command Center")
		return
	var title := menu.find_child("CommandCenterTitle", true, false)
	if title == null or str(title.text) != "Paused":
		_fail("polish2: CC title after top-bar click '%s'" % (str(title.text) if title != null else "missing"))
		return
	_pass("polish2: tooltip visible; top-bar click does not dismiss Paused")
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	var center := ret_rect.get_center()
	root.push_input(_mouse_button(center, true))
	var first := menu.is_queued_for_deletion()
	root.push_input(_mouse_button(center + Vector2(2, 1), false))
	if not first:
		_fail("polish2: first Return to Title press did nothing rect=%s" % str(ret_rect))
		return
	_pass("polish2: first Return to Title press returned")
	_free_menu()
	await _test_pause_first_enter()
	await _test_living_title_first_enter()


func _test_pause_first_enter() -> void:
	_free_menu()
	var menu := _make_menu()
	if menu == null:
		_fail("enter: pause CC missing")
		return
	await process_frame
	await process_frame
	var resume := menu.find_child("BtnResume", true, false) as Button
	if resume == null:
		_fail("enter: Resume missing")
		return
	if not resume.has_focus():
		resume.grab_focus()
	await process_frame
	root.push_input(_key(KEY_ENTER, true))
	var closed := menu.is_queued_for_deletion()
	root.push_input(_key(KEY_ENTER, false))
	if not closed:
		_fail("enter: first Return on Paused did not Resume")
		return
	_pass("enter: first Return on Paused Resumes")
	_free_menu()


func _test_living_title_first_enter() -> void:
	var boot_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if boot_scr == null:
		_fail("title-enter: LivingTitleBoot missing")
		return
	var title: CanvasLayer = boot_scr.new() as CanvasLayer
	title.name = "LivingTitleBoot"
	root.add_child(title)
	await process_frame
	await process_frame
	var begin := title.find_child("LivingTitleBegin", true, false) as Button
	if begin == null:
		_fail("title-enter: Begin missing")
		title.queue_free()
		return
	var vp := title.get_viewport()
	if vp != null:
		vp.gui_release_focus()
	await process_frame
	if title.has_method("_restore_begin_focus_if_idle"):
		title.call("_restore_begin_focus_if_idle")
	if not begin.has_focus():
		_fail("title-enter: idle focus restore did not grab Begin")
		title.queue_free()
		return
	var ev := _key(KEY_ENTER, true)
	if title.has_method("_input"):
		title._input(ev)
	var closed := bool(title.get("_closed")) or title.is_queued_for_deletion()
	if not closed:
		Input.parse_input_event(ev)
		await process_frame
		closed = bool(title.get("_closed")) or title.is_queued_for_deletion()
	if not closed:
		_fail("title-enter: first Return did not Begin")
		title.queue_free()
		return
	_pass("title-enter: first Return Begins")
	if is_instance_valid(title) and not title.is_queued_for_deletion():
		title.queue_free()
	await process_frame


func _dummy_title_scene() -> PackedScene:
	var title := Node.new()
	title.name = "TitleIdle"
	var packed := PackedScene.new()
	packed.pack(title)
	title.free()
	return packed


func _return_to_title_button(menu: Node) -> Button:
	for n in menu.find_children("*", "Button", true, false):
		if not (n is Button):
			continue
		var b := n as Button
		if str(b.get_meta("eoa_cc_action", "")) == "return_to_main":
			return b
	return null


func _mouse_button(pt: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pt
	ev.global_position = pt
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


func _key(keycode: int, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = pressed
	ev.echo = false
	ev.keycode = keycode
	ev.physical_keycode = keycode
	if keycode == KEY_ENTER:
		ev.unicode = 13
	return ev


func _picker() -> Node:
	for n in get_nodes_in_group("continuation_picker"):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			if str(n.name).ends_with("_dying"):
				continue
			return n
	return null


func _picker_header(picker: Node) -> String:
	if picker == null:
		return ""
	for n in picker.find_children("*", "Label", true, false):
		if n is Label and str((n as Label).text).find("Choose nation") >= 0:
			return str((n as Label).text)
	return ""


func _free_group(group: String) -> void:
	for n in get_nodes_in_group(group):
		if n == null or not is_instance_valid(n):
			continue
		if n.has_method("_release_clock_lock"):
			n.call("_release_clock_lock")
		if n.is_in_group(group):
			n.remove_from_group(group)
		n.name = str(n.name) + "_dying"
		var parent := n.get_parent()
		if parent != null:
			parent.remove_child(n)
		n.free()


func _free_menu() -> void:
	var menu := root.get_node_or_null("MainMenu")
	if menu == null or not is_instance_valid(menu):
		return
	if menu.has_method("_release_clock_lock"):
		menu.call("_release_clock_lock")
	var parent := menu.get_parent()
	if parent != null:
		parent.remove_child(menu)
	menu.free()


func _orphaned_end_nodes() -> bool:
	for n in get_nodes_in_group("continuation_picker"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and not str(n.name).ends_with("_dying"):
			return true
	for n2 in get_nodes_in_group("campaign_ink_end_screen"):
		if is_instance_valid(n2) and not n2.is_queued_for_deletion() and not str(n2.name).ends_with("_dying"):
			return true
	return false


func _formations(lm: Node) -> Dictionary:
	var raw: Variant = lm.get("formations")
	if raw is Dictionary:
		return raw
	return {}


func _read_rules() -> Dictionary:
	if not FileAccess.file_exists(RULES_PATH):
		return {}
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


func _tag_counts(provs: Dictionary, field: String) -> Dictionary:
	var counts := {}
	for pid in provs.keys():
		var prov: Object = provs[pid]
		if prov == null:
			continue
		var tag := str(prov.get(field))
		counts[tag] = int(counts.get(tag, 0)) + 1
	return counts


func _slot_row(sl: Node, slot: String) -> Dictionary:
	var rows: Array = sl.call("list_slots_for_ui")
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("slot", "")) == slot:
			return row
	return {}


func _make_bar() -> Node:
	var existing := root.find_child("TopInfoBar", true, false)
	if existing is Control:
		return existing
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		return null
	var bar: Node = packed.instantiate()
	root.add_child(bar)
	return bar as Control


func _make_menu() -> Node:
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	return menu


func _ink_screen() -> Node:
	var nodes := get_nodes_in_group("campaign_ink_end_screen")
	for n in nodes:
		if is_instance_valid(n) and not n.is_queued_for_deletion() and not str(n.name).ends_with("_dying"):
			return n
	return null


func _cl1_screen() -> Node:
	for n in get_nodes_in_group("campaign_end_screen"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and not str(n.name).ends_with("_dying"):
			return n
	return null


func _first_button(n: Node) -> Button:
	if n == null:
		return null
	for c in n.get_children():
		if c is Button:
			return c
		var nested := _first_button(c)
		if nested != null:
			return nested
	return null


func _button_named(n: Node, label: String) -> Button:
	if n == null:
		return null
	if n is Button and str((n as Button).text) == label:
		return n
	for c in n.get_children():
		var found := _button_named(c, label)
		if found != null:
			return found
	return null


func _visible_button_text(n: Node, label: String) -> bool:
	var btn := _button_named(n, label)
	return btn != null and btn.visible
