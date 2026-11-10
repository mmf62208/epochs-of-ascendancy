extends SceneTree

## RTT-SMALLFIX-1. Esc after Continue, overlay buttons, Return to Title, display names, one quicksave toast.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessRttSmallfix1Test.gd

const SRC_END := "res://scripts/ui/CampaignEndScreen.gd"
const SRC_INK := "res://scripts/ui/CampaignInkEndScreen.gd"
const SRC_MENU := "res://scripts/ui/MainMenu.gd"
const SRC_BAR := "res://scripts/ui/TopInfoBar.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_FLAIR := "res://scripts/map/MapNextListHelpers.gd"
const SRC_POLISH := "res://scripts/map/MapPolishFormatters.gd"
const RUS_WEST_PID := 903492
const RUS_WEST_LABEL := "Western Russia"

var _failures: int = 0


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRttSmallfix1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRttSmallfix1Test: ", msg)


func _run() -> void:
	_test_source_needles()
	_test_display_names()
	await _test_capitulation_continue_button()
	await _test_esc_after_keep_opens_pause()
	await _test_return_to_title_live_pointer()
	await _test_overlay_main_menu_to_title()
	_document_item6_first_click()
	var ok := _failures == 0
	print("HeadlessRttSmallfix1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRttSmallfix1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _test_source_needles() -> void:
	var end_src := _read(SRC_END)
	var ink_src := _read(SRC_INK)
	var menu_src := _read(SRC_MENU)
	var bar_src := _read(SRC_BAR)
	var ren_src := _read(SRC_REN)
	if end_src.is_empty() or ink_src.is_empty() or menu_src.is_empty() or bar_src.is_empty() or ren_src.is_empty():
		_fail("source files missing")
		return
	var show_fn := _slice_func(end_src, "_show_continue_as")
	if show_fn.find("kind") >= 0 and show_fn.find("defeat") >= 0:
		_fail("_show_continue_as still auto-true for every defeat overlay")
		return
	if show_fn.find("allow_continuation") < 0:
		_fail("_show_continue_as must key off allow_continuation")
		return
	var menu_fn := _slice_func(end_src, "_on_main_menu")
	if menu_fn.find("open_command_center_stay") >= 0:
		_fail("CampaignEndScreen._on_main_menu still opens Command Center")
		return
	if menu_fn.find("reload_to_living_title") < 0:
		_fail("CampaignEndScreen._on_main_menu must reload the living title")
		return
	var ink_menu := _slice_func(ink_src, "_on_main_menu")
	if ink_menu.find("reload_to_living_title") < 0:
		_fail("CampaignInkEndScreen._on_main_menu must reload the living title")
		return
	if menu_src.find("func reload_to_living_title") < 0:
		_fail("MainMenu.reload_to_living_title missing")
		return
	var live_fn := _slice_func(menu_src, "live_pointer_target")
	if live_fn.find("return_to_title") < 0:
		_fail("live_pointer_target must include Return to Title")
		return
	var act_fn := _slice_func(menu_src, "activate_live_pointer")
	if act_fn.find("return_to_title") < 0:
		_fail("activate_live_pointer must honor Return to Title")
		return
	if ren_src.find('tgt == "refresh" or tgt == "return_to_title"') < 0:
		_fail("MapRenderer._input must activate live Return to Title")
		return
	var overlay_fn := _slice_func(ren_src, "_campaign_end_overlay_is_up")
	if overlay_fn.find("keep_playing") < 0:
		_fail("_campaign_end_overlay_is_up must ignore leftover overlays after Continue as")
		return
	var name_fn := _slice_func(ren_src, "_province_display_name")
	if name_fn.find(str(RUS_WEST_PID)) < 0 or name_fn.find(RUS_WEST_LABEL) < 0:
		_fail("_province_display_name must override 903492 to Western Russia")
		return
	var fight_fn := _slice_func(ren_src, "_show_open_fight_sheet")
	if fight_fn.find("display_name_for_tag") < 0:
		_fail("Open fight sheet must route tags through display_name_for_tag")
		return
	if fight_fn.find("[attacker_tag, att_name, from_name]") >= 0:
		_fail("Open fight sheet still interpolates raw attacker_tag")
		return
	var ctrl_s := _slice_func(bar_src, "_input")
	if ctrl_s.find("Quicksave OK") >= 0:
		_fail("TopInfoBar Ctrl+S still toasts Quicksave OK (duplicate)")
		return
	var save_fn := _slice_func(bar_src, "_on_save_pressed")
	if save_fn.find("Saved quicksave") >= 0:
		_fail("TopInfoBar Menu Save still toasts Saved quicksave (duplicate)")
		return
	_pass("source needles: overlay, title reload, display names, one toast")


func _test_display_names() -> void:
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("ensure_country_stub"):
		mm.call("ensure_country_stub", "SPA")
		mm.call("ensure_country_stub", "SOV")
		mm.call("ensure_country_stub", "GER")
		mm.call("ensure_country_stub", "POL")
	var helpers: GDScript = load(SRC_FLAIR) as GDScript
	if helpers == null:
		_fail("MapNextListHelpers missing")
		return
	var madrid: Dictionary = helpers.call("format_province_select_flair", "Madrid", "SPA", "", "plains")
	var madrid_toast := str(madrid.get("toast", ""))
	if madrid_toast.find("Spain") < 0 or madrid_toast.find("SPA") >= 0:
		_fail("Madrid select toast want Spain not SPA got '%s'" % madrid_toast)
		return
	var odessa: Dictionary = helpers.call("format_province_select_flair", "Odessa", "SOV", "", "plains")
	var odessa_toast := str(odessa.get("toast", ""))
	if odessa_toast.find("Soviet Union") < 0 or odessa_toast.find("SOV") >= 0:
		_fail("Odessa select toast want Soviet Union not SOV got '%s'" % odessa_toast)
		return
	var polish: GDScript = load(SRC_POLISH) as GDScript
	if polish == null:
		_fail("MapPolishFormatters missing")
		return
	var strip: Dictionary = polish.call("tooltip_sfx_flair_strip", "Madrid", "SPA", "Theater", false, "", true, false)
	var select_row: Dictionary = strip.get("select", {}) if strip.get("select") is Dictionary else {}
	var strip_toast := str(select_row.get("toast", strip.get("plain", "")))
	if strip_toast.find("Spain") < 0 or strip_toast.find("SPA") >= 0:
		_fail("tooltip_sfx_flair_strip want Spain not SPA got '%s'" % strip_toast)
		return
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return
	var mr: Node = mr_script.new() as Node
	if mr == null:
		_fail("MapRenderer create failed")
		return
	var shown := str(mr.call("_province_display_name", RUS_WEST_PID))
	mr.free()
	if shown == "RUS West" or shown.find("RUS West") >= 0:
		_fail("903492 display still 'RUS West'")
		return
	if shown != RUS_WEST_LABEL:
		_fail("903492 display want '%s' got '%s'" % [RUS_WEST_LABEL, shown])
		return
	var chrome: GDScript = load("res://scripts/ui/CampaignWarChrome.gd") as GDScript
	if chrome == null:
		_fail("CampaignWarChrome.gd missing")
		return
	var ger := str(chrome.call("display_name_for_tag", "GER"))
	var pol := str(chrome.call("display_name_for_tag", "POL"))
	if ger != "Germany" or pol != "Poland":
		_fail("display_name_for_tag GER/POL want Germany/Poland got %s/%s" % [ger, pol])
		return
	_pass("display names: Spain / Soviet Union / Germany / Poland / Western Russia")


func _test_capitulation_continue_button() -> void:
	_free_end_overlays()
	var model := _defeat_model()
	var end_scr: GDScript = load("res://scripts/ui/CampaignEndScreen.gd") as GDScript
	if end_scr == null:
		_fail("CampaignEndScreen.gd missing")
		return
	var screen: Node = end_scr.call("present", model) as Node
	await process_frame
	if screen == null:
		_fail("capitulation overlay missing")
		return
	var keep := screen.find_child("BtnKeepPlaying", true, false) as Button
	var cont := screen.find_child("BtnContinue", true, false) as Button
	if keep == null or not keep.visible:
		_fail("BtnKeepPlaying missing on capitulation overlay")
		_free_end_overlays()
		return
	if cont != null and cont.visible:
		_fail("BtnContinue still visible on capitulation overlay")
		_free_end_overlays()
		return
	_pass("capitulation overlay hides Continue as… and keeps Continue as Germany")
	_free_end_overlays()


func _test_esc_after_keep_opens_pause() -> void:
	_free_end_overlays()
	_free_menu()
	var gd := root.get_node_or_null("GameData")
	if gd == null:
		_fail("keep-esc: GameData missing")
		return
	var end: GDScript = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if end != null and end.has_method("reset_for_test"):
		end.call("reset_for_test")
	var model := _defeat_model()
	if "peace_state" in gd:
		var ps: Dictionary = gd.peace_state
		ps["campaign_end"] = model.duplicate(true)
		gd.peace_state = ps
	var bar := _make_bar()
	if bar == null:
		_fail("keep-esc: TopInfoBar missing")
		return
	var mr_script: Script = load(SRC_REN) as Script
	var mr: Node = mr_script.new() as Node
	mr.name = "MapRenderer"
	mr.set_process(false)
	mr.set_physics_process(false)
	root.add_child(mr)
	var end_scr: GDScript = load("res://scripts/ui/CampaignEndScreen.gd") as GDScript
	if end_scr == null:
		_fail("keep-esc: CampaignEndScreen.gd missing")
		_cleanup_keep_esc(mr, end)
		return
	var screen: Node = end_scr.call("present", model) as Node
	await process_frame
	if screen == null:
		_fail("keep-esc: overlay missing")
		_cleanup_keep_esc(mr, end)
		return
	var keep := screen.find_child("BtnKeepPlaying", true, false) as Button
	if keep == null:
		_fail("keep-esc: BtnKeepPlaying missing")
		_cleanup_keep_esc(mr, end)
		return
	keep.pressed.emit()
	await process_frame
	if end != null and end.has_method("view_model"):
		var vm: Dictionary = end.call("view_model")
		if not bool(vm.get("keep_playing", false)):
			_fail("keep-esc: keep_playing was not set")
			_cleanup_keep_esc(mr, end)
			return
	var ink_scr: GDScript = load("res://scripts/ui/CampaignInkEndScreen.gd") as GDScript
	var leftover: Node = null
	if ink_scr != null:
		leftover = ink_scr.call("present_loss", "GER", "capitulated") as Node
	await process_frame
	if leftover != null and leftover.has_method("_input"):
		leftover.call("_input", _esc())
	if bool(mr.call("_campaign_end_overlay_is_up")):
		_fail("keep-esc: leftover overlay still blocks Esc after Continue as")
		_cleanup_keep_esc(mr, end)
		return
	mr.call("_handle_escape_key")
	await process_frame
	await process_frame
	var menu := root.get_node_or_null("MainMenu")
	if menu == null or not is_instance_valid(menu) or menu.is_queued_for_deletion():
		_fail("keep-esc: Esc did not open Paused")
		_cleanup_keep_esc(mr, end)
		return
	var title := menu.find_child("CommandCenterTitle", true, false)
	if title == null or str(title.text) != "Paused":
		_fail("keep-esc: Command Center title '%s'" % (str(title.text) if title != null else "missing"))
		_cleanup_keep_esc(mr, end)
		return
	_pass("keep-esc: Esc after Continue as opens Paused")
	_cleanup_keep_esc(mr, end)


func _test_return_to_title_live_pointer() -> void:
	_free_menu()
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if root is Window:
		(root as Window).size = Vector2i(1280, 800)
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	var menu := _make_menu()
	if menu == null:
		_fail("rtt: Command Center missing")
		return
	await process_frame
	await process_frame
	await process_frame
	var ret: Button = _return_to_title_button(menu)
	if ret == null:
		_fail("rtt: Return to Title missing")
		_free_menu()
		return
	var center := ret.get_global_rect().get_center()
	var tgt := ""
	if menu.has_method("live_pointer_target"):
		tgt = str(menu.call("live_pointer_target", center))
	if tgt != "return_to_title":
		_fail("rtt: live_pointer_target want return_to_title got '%s'" % tgt)
		_free_menu()
		return
	if menu.has_method("activate_live_pointer"):
		menu.call("activate_live_pointer", center)
	var first := menu.is_queued_for_deletion()
	if not first:
		_fail("rtt: one live click on Return to Title did nothing")
		_free_menu()
		return
	await process_frame
	await process_frame
	var scene := current_scene
	var scene_name := str(scene.name) if scene != null else ""
	if scene_name != "TitleIdle":
		_fail("rtt: one click landed on '%s' not the title" % scene_name)
		return
	_pass("rtt: one live click on Return to Title reaches the title")


func _test_overlay_main_menu_to_title() -> void:
	_free_end_overlays()
	_free_menu()
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	var bar := _make_bar()
	if bar == null:
		_fail("main-menu: TopInfoBar missing")
		return
	var end_scr: GDScript = load("res://scripts/ui/CampaignEndScreen.gd") as GDScript
	if end_scr == null:
		_fail("main-menu: CampaignEndScreen.gd missing")
		return
	var screen: Node = end_scr.call("present", _defeat_model()) as Node
	await process_frame
	if screen == null or not screen.has_method("_on_main_menu"):
		_fail("main-menu: overlay missing")
		_free_end_overlays()
		return
	screen.call("_on_main_menu")
	await process_frame
	await process_frame
	var overlay := _cl1_screen()
	if overlay != null and is_instance_valid(overlay) and not overlay.is_queued_for_deletion() and str(overlay.name).find("_dying") < 0:
		if overlay is CanvasLayer and (overlay as CanvasLayer).visible:
			_fail("main-menu: overlay still visible")
			_free_end_overlays()
			return
	var cc := root.get_node_or_null("MainMenu")
	if cc != null and is_instance_valid(cc) and not cc.is_queued_for_deletion() and not bool(cc.get("_closing")):
		_fail("main-menu: landed on in-game Command Center")
		_free_end_overlays()
		return
	var scene := current_scene
	var scene_name := str(scene.name) if scene != null else ""
	if scene_name != "TitleIdle":
		_fail("main-menu: landed on '%s' not the living title" % scene_name)
		_free_end_overlays()
		return
	_pass("main-menu: overlay Main menu returns to the living title")
	_free_end_overlays()


func _document_item6_first_click() -> void:
	# Item 6 — documented, no product change.
	# DiplomacyButton already ACTION_MODE_BUTTON_PRESS via TopInfoBar._connect_once
	# (same class as Prod-1). arm_ui_close_release_swallow / _ui_close_release_blocks_map_pick
	# only skip map pick on leftover LEFT-UP (MapRenderer ~3599, ~4054), not button-down.
	# First map drag after Begin is the #167 leftover swallow
	# (arm_begin_title_release_swallow / LivingTitleBoot leftover) plus
	# _overlay_hold_blocks_map_gesture. Diplomacy first click can also no-op when
	# _toggle_root_popup finds a leftover DiplomacyView and hides it. Untangling
	# Begin click-through vs first-drag is not a small safe change.
	_pass("item6: first-click swallow documented; no product change")


func _defeat_model() -> Dictionary:
	return {
		"outcome": "defeat",
		"kind": "defeat",
		"day": 1,
		"date": "1936-06-01",
		"player_tag": "GER",
		"summary": "capitulated",
		"title": "Defeat",
		"reason": "Germany capitulated",
		"stats": {
			"days": 1,
			"provinces_start": 10,
			"provinces_end": 4,
			"wars_fought": 1,
			"capitulated_by_side": 1,
			"factory_share": 0.1,
		},
		"allow_continuation": false,
		"allow_keep_playing": true,
		"keep_playing_reason": "",
	}


func _cleanup_keep_esc(mr: Node, end: GDScript) -> void:
	_free_end_overlays()
	_free_menu()
	if mr != null and is_instance_valid(mr):
		var parent := mr.get_parent()
		if parent != null:
			parent.remove_child(mr)
		mr.free()
	if end != null and end.has_method("reset_for_test"):
		end.call("reset_for_test")


func _free_end_overlays() -> void:
	for group_name in ["campaign_end_screen", "campaign_ink_end_screen", "continuation_picker"]:
		for n in get_nodes_in_group(group_name):
			if n == null or not is_instance_valid(n):
				continue
			if n.has_method("_release_clock_lock"):
				n.call("_release_clock_lock")
			if n.is_in_group(group_name):
				n.remove_from_group(group_name)
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


func _make_bar() -> Node:
	var existing := root.find_child("TopInfoBar", true, false)
	if existing is Control:
		return existing
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		return null
	var bar: Node = packed.instantiate()
	root.add_child(bar)
	return bar


func _make_menu() -> Node:
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	return menu


func _cl1_screen() -> Node:
	for n in get_nodes_in_group("campaign_end_screen"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and not str(n.name).ends_with("_dying"):
			return n
	return null


func _return_to_title_button(menu: Node) -> Button:
	for n in menu.find_children("*", "Button", true, false):
		if not (n is Button):
			continue
		var b := n as Button
		if str(b.get_meta("eoa_cc_action", "")) == "return_to_main":
			return b
	return null


func _dummy_title_scene() -> PackedScene:
	var title := Node.new()
	title.name = "TitleIdle"
	var packed := PackedScene.new()
	packed.pack(title)
	title.free()
	return packed


func _esc() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	return ev


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, fn: String) -> String:
	var needle := "func %s" % fn
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt_a := src.find("\nfunc ", i + needle.length())
	var nxt_b := src.find("\nstatic func ", i + needle.length())
	var nxt := -1
	if nxt_a >= 0 and nxt_b >= 0:
		nxt = mini(nxt_a, nxt_b)
	elif nxt_a >= 0:
		nxt = nxt_a
	else:
		nxt = nxt_b
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)
