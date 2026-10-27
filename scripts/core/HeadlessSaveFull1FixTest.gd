extends SceneTree

## SAVE-FULL-1 FIX probes. Each case fails on b31b625a behavior and passes
## after the fix: player tag on the save, title clicks vs Command Center,
## minor land designs, debug declare-war, open-fight display name.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessSaveFull1FixTest.gd

const SLOT := "sf1fix_click"
const MARK := 4242

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveFull1FixTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveFull1FixTest: ", msg)


func _run() -> void:
	_test_player_tag()
	_test_minor_land_design()
	_test_open_fight_name()
	_test_one_select_toast()
	_test_ctrl_l_quickload()
	_test_title_release_passthrough()
	await _test_title_clicks()
	_test_debug_declare_war()
	if _failures > 0:
		print("HeadlessSaveFull1FixTest: RESULT=FAIL failures=%d" % _failures)
	else:
		print("HeadlessSaveFull1FixTest: RESULT=PASS")
	quit(1 if _failures > 0 else 0)


func _test_player_tag() -> void:
	var lm := get_root().get_node_or_null("LeaderManager")
	var sl := get_root().get_node_or_null("SaveLoadManager")
	if lm == null or sl == null:
		_fail("A: LeaderManager or SaveLoadManager missing")
		return
	if not lm.has_method("set_player_country_tag") or not sl.has_method("_gather_save_data"):
		_fail("A: player tag or gather API missing")
		return
	lm.call("set_player_country_tag", "GER")
	var data: Dictionary = sl.call("_gather_save_data")
	var meta: Dictionary = data.get("metadata", {}) as Dictionary
	var tag := str(meta.get("player_tag", "")).strip_edges().to_upper()
	if tag != "GER":
		_fail("A: metadata.player_tag=%s while playing GER" % tag)
		return
	var row: Dictionary = sl.call("_format_slot_ui_row", "quicksave", true, meta)
	var label := str(row.get("label", ""))
	if label.find("GER") < 0 or label.find("USA") >= 0:
		_fail("A: load label '%s' does not name GER" % label)
		return
	_pass("A: save metadata and load label record GER")


func _test_minor_land_design() -> void:
	var lm := get_root().get_node_or_null("LeaderManager")
	if lm == null or not lm.has_method("clear_all_formations"):
		_fail("C: LeaderManager missing")
		return
	lm.call("clear_all_formations")
	# load() the spawner. A class_name Formation reference in this -s script
	# makes Formation.new() inside the spawner resolve to a bare GDScript.
	var sp_script: Script = load("res://scripts/formations/FormationSpawner.gd") as Script
	if sp_script == null:
		_fail("C: FormationSpawner script missing")
		return
	var sp: Node = sp_script.new()
	get_root().add_child(sp)
	var cze_land: Array = [710146, 710148, 710149, 710150]
	sp.call("spawn_test_formations_for_country", "CZE", 2, 710146, cze_land)
	var swe_land: Array = [711213, 711224, 711226, 711227]
	sp.call("spawn_test_formations_for_country", "SWE", 2, 711213, swe_land)
	sp.call("spawn_test_formations_for_country", "GER", 1, 710300, [710300])
	var cze_ids: PackedStringArray = PackedStringArray()
	var swe_ids: PackedStringArray = PackedStringArray()
	var ger_ok := false
	for f in lm.call("get_formations_for_country", "CZE"):
		if f == null or str(f.formation_type) != "division":
			continue
		cze_ids.append(str(f.design_id))
	for f2 in lm.call("get_formations_for_country", "SWE"):
		if f2 == null or str(f2.formation_type) != "division":
			continue
		swe_ids.append(str(f2.design_id))
	for f3 in lm.call("get_formations_for_country", "GER"):
		if f3 == null:
			continue
		if str(f3.formation_type) == "division" and str(f3.design_id) == "panzer_iii_j_medium":
			ger_ok = true
	lm.call("clear_all_formations")
	sp.free()
	var cze_ok := cze_ids.size() > 0
	var swe_ok := swe_ids.size() > 0
	for cid in cze_ids:
		if cid != "lt_vz_35_light":
			cze_ok = false
	for sid in swe_ids:
		if sid != "swe_armor_1936":
			swe_ok = false
	if not cze_ok or not swe_ok or not ger_ok:
		_fail("C: land designs CZE=[%s] SWE=[%s] GER_panzer=%s" % [",".join(cze_ids), ",".join(swe_ids), ger_ok])
		return
	_pass("C: CZE uses lt_vz_35_light, SWE uses swe_armor_1936, GER stays panzer")


func _test_open_fight_name() -> void:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null or not mr_script.has_method("open_fight_attacker_label"):
		_fail("G: open_fight_attacker_label missing")
		return
	var form_script: Script = load("res://scripts/formations/Formation.gd") as Script
	if form_script == null:
		_fail("G: Formation script missing")
		return
	var f: Object = form_script.new()
	f.formation_id = "garr1936_GER_711072"
	f.name = "GER 1st Garrison Division"
	f.country_tag = "GER"
	f.set_meta("garrison_1936", true)
	var label := str(mr_script.call("open_fight_attacker_label", f, f.formation_id))
	if label.find("garr1936_") >= 0 or label != f.name:
		_fail("G: sheet label '%s' is not the card name" % label)
		return
	f.name = "garr1936_GER_711072"
	f.set_meta("garrison_1936_ordinal", 1)
	var fallback := str(mr_script.call("open_fight_attacker_label", f, f.formation_id))
	var want := ""
	var lm := get_root().get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("garrison_1936_display_name"):
		want = str(lm.call("garrison_1936_display_name", "GER", 1))
	if fallback.find("garr1936_") >= 0 or (not want.is_empty() and fallback != want):
		_fail("G: raw-id fallback '%s' want '%s'" % [fallback, want])
		return
	_pass("G: open fight uses the card name, not the raw formation id")


func _test_one_select_toast() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/map/MapRenderer.gd")
	var body := _func_slice(src, "_select_map_unit")
	if body.count("_show_inspector_toast") != 1 or body.count("toast_map_debug") != 0:
		_fail("H: _select_map_unit toast count inspector=%d debug=%d" % [
			body.count("_show_inspector_toast"), body.count("toast_map_debug")
		])
		return
	_pass("H: one Unit selected toast kept")


func _test_ctrl_l_quickload() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/TopInfoBar.gd")
	var body := _func_slice(src, "_unhandled_input")
	if body.find("KEY_L") < 0 or body.find("quickload") < 0:
		_fail("B: Ctrl+L quickload missing from TopInfoBar")
		return
	_pass("B: Ctrl+L still calls quickload")


func _test_title_release_passthrough() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/map/MapRenderer.gd")
	var body := _func_slice(src, "_input")
	if body.find("command center release passthrough") < 0:
		_fail("B: title-up release still eats Command Center ×")
		return
	_pass("B: title-up release leaves Command Center × to the button")


func _test_title_clicks() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var title: Node = load("res://scripts/ui/LivingTitleBoot.gd").new()
	title.name = "LivingTitleBoot"
	get_root().add_child(title)
	await process_frame
	var lm := get_root().get_node_or_null("LeaderManager")
	var sl := get_root().get_node_or_null("SaveLoadManager")
	if lm == null or sl == null or title.get("_cc_btn") == null:
		_fail("B: title or save autoload missing")
		if is_instance_valid(title):
			title.queue_free()
		return
	lm.call("set_player_country_tag", "GER")
	lm.set("_fielded_seq", MARK)
	if not bool(sl.call("save_game", SLOT)):
		_fail("B: could not write %s" % SLOT)
		title.queue_free()
		return
	lm.set("_fielded_seq", 1)
	var cc: Button = title.get("_cc_btn")
	_force_rect(cc, Vector2(100, 400), Vector2(220, 36))
	var root_c: Control = title.get_node_or_null("LivingTitleRoot") as Control
	var load_b := Button.new()
	load_b.text = "Load · quicksave"
	load_b.mouse_filter = Control.MOUSE_FILTER_STOP
	load_b.set_meta("eoa_load_slot", SLOT)
	if root_c != null:
		root_c.add_child(load_b)
	_force_rect(load_b, Vector2(100, 368), Vector2(220, 30))
	var load_hit := _press(title, load_b.get_global_rect().get_center())
	var seq_after := int(lm.get("_fielded_seq"))
	if load_hit != "load" or seq_after != MARK:
		_fail("B: title Load action=%s seq=%d (Load click eaten)" % [load_hit, seq_after])
	else:
		_pass("B: title Load loads the slot instead of opening Command Center")
	if is_instance_valid(title):
		title.queue_free()
		await process_frame
	title = load("res://scripts/ui/LivingTitleBoot.gd").new()
	title.name = "LivingTitleBoot"
	get_root().add_child(title)
	await process_frame
	var menu: Node = load("res://scripts/ui/MainMenu.gd").new()
	menu.name = "MainMenu"
	menu.set_meta("eoa_opened_from_living_title", true)
	get_root().add_child(menu)
	await process_frame
	await process_frame
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	if menu.has_method("_input"):
		menu.call("_input", esc)
	if not is_instance_valid(menu) or menu.is_queued_for_deletion():
		_fail("B: Esc closed Command Center while the title is up")
		if is_instance_valid(title):
			title.queue_free()
		return
	_pass("B: Esc still keeps Command Center open while the title is up")
	lm.set("_fielded_seq", 7)
	var close_b: Button = menu.call("close_x_button")
	var cc_load: Button = _find_cc_load(menu)
	if close_b == null or cc_load == null:
		_fail("B: Command Center CloseX or Load missing")
		menu.queue_free()
		title.queue_free()
		return
	cc_load.set_meta("eoa_load_slot", SLOT)
	_force_rect(close_b, Vector2(1000, 140), Vector2(44, 40))
	_force_rect(cc_load, Vector2(480, 420), Vector2(80, 32))
	var panel: Control = title.get("_panel") as Control
	if panel != null:
		_force_rect(panel, Vector2(20, 40), Vector2(1100, 700))
	var close_hit := _press(title, close_b.get_global_rect().get_center())
	var closed := (not is_instance_valid(menu)) or menu.is_queued_for_deletion() or bool(menu.get("_closing"))
	if close_hit != "close" or not closed:
		_fail("B: × action=%s closed=%s" % [close_hit, closed])
	else:
		_pass("B: × closes Command Center")
	# The closed menu stays named MainMenu until the frame ends. A second
	# MainMenu added in that window is renamed, so the title no longer sees it.
	if is_instance_valid(menu):
		menu.name = "MainMenuClosing"
		if not menu.is_queued_for_deletion():
			menu.queue_free()
	await process_frame
	if not is_instance_valid(title) or title.is_queued_for_deletion():
		title = load("res://scripts/ui/LivingTitleBoot.gd").new()
		title.name = "LivingTitleBoot"
		get_root().add_child(title)
		await process_frame
	menu = load("res://scripts/ui/MainMenu.gd").new()
	menu.name = "MainMenu"
	menu.set_meta("eoa_opened_from_living_title", true)
	get_root().add_child(menu)
	await process_frame
	lm.set("_fielded_seq", 7)
	cc_load = _find_cc_load(menu)
	if cc_load == null:
		_fail("B: second Command Center Load missing")
		if is_instance_valid(menu):
			menu.queue_free()
		if is_instance_valid(title):
			title.queue_free()
		return
	cc_load.set_meta("eoa_load_slot", SLOT)
	_force_rect(cc_load, Vector2(480, 420), Vector2(80, 32))
	panel = title.get("_panel") as Control
	if panel != null:
		_force_rect(panel, Vector2(20, 40), Vector2(1100, 700))
	var cc_hit := _press(title, cc_load.get_global_rect().get_center())
	var seq_cc := int(lm.get("_fielded_seq"))
	if cc_hit != "load" or seq_cc != MARK:
		_fail("B: Command Center Load action=%s seq=%d" % [cc_hit, seq_cc])
	else:
		_pass("B: Command Center Load loads the slot")
	if is_instance_valid(menu):
		menu.queue_free()
	if is_instance_valid(title):
		title.queue_free()


func _test_debug_declare_war() -> void:
	var war_script: Script = load("res://scripts/core/WarStateDomain.gd") as Script
	if war_script == null or not war_script.has_method("debug_console_declare"):
		_fail("D: debug_console_declare missing")
		return
	var lm := get_root().get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var ignored: Dictionary = war_script.call("debug_console_declare", "Berlin")
	if bool(ignored.get("handled", false)):
		_fail("D: province search was treated as a war command")
		return
	var declared: Dictionary = war_script.call("debug_console_declare", "declare war on POL")
	var at_war := bool(war_script.call("is_at_war", "GER", "POL"))
	if not bool(declared.get("ok", false)) or not at_war:
		_fail("D: declare war on POL failed %s at_war=%s" % [str(declared), at_war])
		return
	var src := FileAccess.get_file_as_string("res://scripts/ui/DiplomacyView.gd")
	if src.find("debug_console_declare") >= 0:
		_fail("D: declare hook landed on the Diplomacy panel")
		return
	_pass("D: debug console 'declare war on POL' opens GER–POL; Diplomacy panel untouched")


func _press(title: Node, at: Vector2) -> String:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	mb.global_position = at
	return str(title.call("handle_live_pointer", mb))


func _force_rect(ctrl: Control, origin: Vector2, sz: Vector2) -> void:
	if ctrl == null:
		return
	ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = origin.x
	ctrl.offset_top = origin.y
	ctrl.offset_right = origin.x + sz.x
	ctrl.offset_bottom = origin.y + sz.y
	ctrl.position = origin
	ctrl.size = sz
	ctrl.custom_minimum_size = sz


func _find_cc_load(menu: Node) -> Button:
	for n in menu.find_children("*", "Button", true, false):
		if n is Button and str((n as Button).text) == "Load" and not (n as Button).disabled:
			return n as Button
	return null


func _func_slice(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt := src.find("\nfunc ", i + needle.length())
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)
