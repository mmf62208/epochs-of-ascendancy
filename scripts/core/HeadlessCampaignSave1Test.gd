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
		if is_instance_valid(n) and not n.is_queued_for_deletion():
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
