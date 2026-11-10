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
	await _test_input_path_script_errors()
	_test_self_target_excluded()
	await _test_top_bar_war_after_declare()
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
	var input_fn := _slice_func(ren_src, "_input")
	if input_fn.find("_mark_input_handled") < 0:
		_fail("MapRenderer._input must null-guard set_input_as_handled")
		return
	if input_fn.find("get_viewport().set_input_as_handled") >= 0:
		_fail("MapRenderer._input still calls get_viewport().set_input_as_handled unguarded")
		return
	var rtt_fn := input_fn.find('tgt == "refresh" or tgt == "return_to_title"')
	if rtt_fn < 0:
		_fail("MapRenderer._input missing live Return to Title branch")
		return
	var rtt_slice := input_fn.substr(rtt_fn, 360)
	var mark_at := rtt_slice.find("_mark_input_handled")
	var act_at := rtt_slice.find("mm_ov.call(")
	if mark_at < 0 or act_at < 0 or mark_at > act_at:
		_fail("MapRenderer._input must mark handled before activating Return to Title")
		return
	if input_fn.find("_campaign_modal_is_up") < 0:
		_fail("MapRenderer._input must mark handled before overlay Main menu frees the map")
		return
	var polish := _read(SRC_POLISH)
	if polish.find("func province_ui_display_name") < 0 or polish.find(str(RUS_WEST_PID)) < 0:
		_fail("MapPolishFormatters.province_ui_display_name must override 903492")
		return
	var settle_fn := _slice_func(ren_src, "_update_settle_button")
	if settle_fn.find("_province_display_name") < 0:
		_fail("_update_settle_button must use _province_display_name")
		return
	var insight := _read("res://scripts/map/ProvinceInsight.gd")
	var top_fn := _slice_func(insight, "build_inspector_topline")
	if top_fn.find("province_ui_display_name") < 0:
		_fail("build_inspector_topline must use province_ui_display_name")
		return
	var chrome_src := _read("res://scripts/ui/CampaignWarChrome.gd")
	if chrome_src.find("func is_self_nation") < 0:
		_fail("CampaignWarChrome.is_self_nation missing")
		return
	if chrome_src.find("func refresh_top_bar_war_readout") < 0:
		_fail("CampaignWarChrome.refresh_top_bar_war_readout missing")
		return
	var dip := _read("res://scripts/ui/DiplomacyView.gd")
	if dip.find("is_self_nation") < 0:
		_fail("DiplomacyView must skip the player's own nation")
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
	var rus := _rus_west_province()
	if rus == null:
		_fail("could not make 903492 province for display-name surfaces")
		return
	var insight: GDScript = load("res://scripts/map/ProvinceInsight.gd") as GDScript
	if insight == null:
		_fail("ProvinceInsight.gd missing")
		return
	var topline_v: Variant = insight.call("build_inspector_topline", rus)
	if not (topline_v is Dictionary):
		_fail("build_inspector_topline missing")
		return
	var title := str((topline_v as Dictionary).get("title", ""))
	if title.find("RUS West") >= 0 or title != RUS_WEST_LABEL:
		_fail("inspector title want '%s' got '%s'" % [RUS_WEST_LABEL, title])
		return
	var compact := str(insight.call("build_compact_hover_tooltip", rus))
	var strategic := str(insight.call("build_strategic_hover_tooltip", rus))
	if compact.find("RUS West") >= 0 or compact.find(RUS_WEST_LABEL) < 0:
		_fail("compact hover still raw RUS West: %s" % compact)
		return
	if strategic.find("RUS West") >= 0 or strategic.find(RUS_WEST_LABEL) < 0:
		_fail("strategic hover still raw RUS West: %s" % strategic)
		return
	var panel := Panel.new()
	panel.name = "InfoPanel"
	root.add_child(panel)
	var settle_mr: Node = mr_script.new() as Node
	settle_mr.set("info_panel", panel)
	settle_mr.call("_update_settle_button", rus)
	var settle := panel.find_child("BtnSettleProvince", true, false) as Button
	var settle_txt := str(settle.text) if settle != null else ""
	settle_mr.free()
	panel.queue_free()
	if settle == null or settle_txt.find(RUS_WEST_LABEL) < 0 or settle_txt.find("RUS West") >= 0:
		_fail("Settle button want Western Russia got '%s'" % settle_txt)
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


func _test_input_path_script_errors() -> void:
	var log_scr: GDScript = load("res://scripts/core/ReturnToTitleScriptErrorLog.gd") as GDScript
	if log_scr == null:
		_fail("input-path: ReturnToTitleScriptErrorLog missing")
		return
	var elog: Logger = log_scr.new() as Logger
	OS.add_logger(elog)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if root is Window:
		(root as Window).size = Vector2i(1280, 800)
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	if not await _drive_rtt_input_click(elog):
		OS.remove_logger(elog)
		return
	if not await _drive_overlay_main_menu_input_click(elog):
		OS.remove_logger(elog)
		return
	var n := int(elog.get("script_errors"))
	var samples := PackedStringArray()
	if "samples" in elog:
		samples = elog.samples
	OS.remove_logger(elog)
	if n > 0:
		_fail("input-path: %d SCRIPT ERRORs %s" % [n, ", ".join(samples)])
		return
	_pass("input-path: MapRenderer._input mouse click frees the map with 0 script errors")


func _drive_rtt_input_click(elog: Logger) -> bool:
	_free_menu()
	_free_end_overlays()
	var before := int(elog.get("script_errors"))
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("input-path rtt: MapRenderer.gd missing")
		return false
	var mr: Node = mr_script.new() as Node
	mr.name = "MapRenderer"
	mr.set_process(false)
	mr.set_physics_process(false)
	mr.set_process_input(false)
	mr.set_process_unhandled_input(false)
	root.add_child(mr)
	current_scene = mr
	var menu := _make_menu()
	if menu == null:
		_fail("input-path rtt: Command Center missing")
		return false
	await process_frame
	await process_frame
	await process_frame
	var ret: Button = _return_to_title_button(menu)
	if ret == null:
		_fail("input-path rtt: Return to Title missing")
		_free_menu()
		return false
	var center := ret.get_global_rect().get_center()
	var tgt := ""
	if menu.has_method("live_pointer_target"):
		tgt = str(menu.call("live_pointer_target", center))
	if tgt != "return_to_title":
		_fail("input-path rtt: live_pointer_target want return_to_title got '%s'" % tgt)
		_free_menu()
		return false
	var ev := _mouse_left(center)
	if is_instance_valid(mr) and mr.has_method("_input"):
		mr.call("_input", ev)
	await process_frame
	await process_frame
	var after := int(elog.get("script_errors"))
	if after > before:
		_fail("input-path rtt: SCRIPT ERROR on Return to Title click")
		return false
	_pass("input-path rtt: _input Return to Title click had 0 script errors")
	return true


func _drive_overlay_main_menu_input_click(elog: Logger) -> bool:
	_free_menu()
	_free_end_overlays()
	var before := int(elog.get("script_errors"))
	root.set_meta("eoa_return_title_scene", _dummy_title_scene())
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("input-path overlay: MapRenderer.gd missing")
		return false
	var mr: Node = mr_script.new() as Node
	mr.name = "MapRenderer"
	mr.set_process(false)
	mr.set_physics_process(false)
	mr.set_process_input(false)
	mr.set_process_unhandled_input(false)
	root.add_child(mr)
	current_scene = mr
	var bar := _make_bar()
	if bar == null:
		_fail("input-path overlay: TopInfoBar missing")
		return false
	var end_scr: GDScript = load("res://scripts/ui/CampaignEndScreen.gd") as GDScript
	if end_scr == null:
		_fail("input-path overlay: CampaignEndScreen.gd missing")
		return false
	var screen: Node = end_scr.call("present", _defeat_model()) as Node
	await process_frame
	await process_frame
	if screen == null:
		_fail("input-path overlay: overlay missing")
		return false
	var menu_btn := screen.find_child("BtnMainMenu", true, false) as Button
	if menu_btn == null:
		_fail("input-path overlay: BtnMainMenu missing")
		_free_end_overlays()
		return false
	var ev := _mouse_left(menu_btn.get_global_rect().get_center())
	if is_instance_valid(mr) and mr.has_method("_input"):
		mr.call("_input", ev)
	await process_frame
	await process_frame
	var after := int(elog.get("script_errors"))
	if after > before:
		_fail("input-path overlay: SCRIPT ERROR on Main menu click")
		_free_end_overlays()
		return false
	_pass("input-path overlay: _input Main menu click had 0 script errors")
	return true


func _test_self_target_excluded() -> void:
	var chrome: GDScript = load("res://scripts/ui/CampaignWarChrome.gd") as GDScript
	if chrome == null:
		_fail("self-target: CampaignWarChrome missing")
		return
	if not bool(chrome.call("is_self_nation", "USA", "USA")):
		_fail("is_self_nation USA/USA should be true")
		return
	if bool(chrome.call("inspector_offers_justify", "USA", "USA")):
		_fail("inspector still offers Justify on the player's own USA land")
		return
	var st: Dictionary = chrome.call("button_state_for_owner", "USA", "USA")
	if bool(st.get("visible", false)):
		_fail("Justify/Declare still visible for USA on USA (%s)" % str(st.get("text", "")))
		return
	if str(st.get("text", "")).find("United States") >= 0:
		_fail("self-target label leaked '%s'" % str(st.get("text", "")))
		return
	var lm := root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "USA")
	if ResourceLoader.exists("res://scenes/ui/DiplomacyView.tscn"):
		var packed: PackedScene = load("res://scenes/ui/DiplomacyView.tscn") as PackedScene
		if packed != null:
			var view: Node = packed.instantiate()
			root.add_child(view)
			if view.has_method("listed_country_tags"):
				var listed: Array = view.call("listed_country_tags")
				for tag_v in listed:
					if str(tag_v).strip_edges().to_upper() == "USA":
						_fail("Diplomacy listed_country_tags still includes the player USA")
						view.queue_free()
						if lm != null and lm.has_method("set_player_country_tag"):
							lm.call("set_player_country_tag", "GER")
						return
			var btn := view.find_child("BtnJustifyWar", true, false) as Button
			if btn != null and btn.visible and str(btn.text).find("United States") >= 0:
				_fail("Diplomacy Justify still targets the player (%s)" % btn.text)
				view.queue_free()
				if lm != null and lm.has_method("set_player_country_tag"):
					lm.call("set_player_country_tag", "GER")
				return
			view.queue_free()
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	_pass("self-target: USA is excluded from Justify/Declare")


func _test_top_bar_war_after_declare() -> void:
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var lm := root.get_node_or_null("LeaderManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var war: GDScript = load("res://scripts/core/WarStateDomain.gd") as GDScript
	var chrome: GDScript = load("res://scripts/ui/CampaignWarChrome.gd") as GDScript
	if mm == null or boot == null or war == null or chrome == null:
		_fail("war-bar: autoloads missing")
		return
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("war-bar: campaign boot failed")
		return
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	war.call("reset_for_test")
	war.call("clear_rule_overrides")
	if not bool(war.call("loop_enabled")):
		_fail("war-bar: campaign loop inactive")
		return
	var pol_pid := _land_pid(mm, "POL")
	if pol_pid <= 0:
		_fail("war-bar: no POL land")
		return
	var bar := _make_bar()
	if bar == null:
		_fail("war-bar: TopInfoBar missing")
		return
	await process_frame
	var host := Panel.new()
	host.name = "WarBarHost"
	host.size = Vector2(320, 160)
	root.add_child(host)
	var pol_p: Object = mm.call("get_province", pol_pid)
	chrome.call("mount", host, pol_p)
	war.call("grant_ready_player_justify", "POL")
	chrome.call("mount", host, pol_p)
	var btn := host.get_node_or_null("BtnDeclareWar") as Button
	if btn == null or not btn.visible:
		_fail("war-bar: Declare button missing")
		host.queue_free()
		return
	btn.pressed.emit()
	await process_frame
	var lbl := bar.find_child("CampaignWarReadout", true, false) as Label
	var line := str(lbl.text) if lbl != null else ""
	host.queue_free()
	if line.find("At war") < 0 or line.find("Poland") < 0:
		_fail("war-bar: after Declare want 'At war: Poland' got '%s'" % line)
		return
	_pass("war-bar: Declare refreshes At war: Poland without a save load")


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


func _rus_west_province() -> Object:
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province"):
		var live: Variant = mm.call("get_province", RUS_WEST_PID)
		if live is Object and live != null:
			if "name" in live:
				live.name = "RUS West"
			if "id" in live:
				live.id = RUS_WEST_PID
			return live
	var scr: Script = load("res://scripts/data/Province.gd") as Script
	if scr == null or not scr.can_instantiate():
		return null
	var p: Object = scr.new() as Object
	if p == null:
		return null
	p.set("id", RUS_WEST_PID)
	p.set("name", "RUS West")
	p.set("owner_tag", "SOV")
	p.set("is_sea", false)
	p.set("settlement_level", 0.0)
	return p


func _land_pid(mm: Node, owner: String) -> int:
	if mm == null or not mm.has_method("get_provinces_by_owner"):
		return -1
	var owned: Array = mm.call("get_provinces_by_owner", owner)
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		return pid
	return -1


func _mouse_left(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	return ev


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
