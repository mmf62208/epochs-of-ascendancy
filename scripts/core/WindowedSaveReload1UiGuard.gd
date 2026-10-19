extends SceneTree

## SR1 test E. Private display only (wrapper starts Xvfb or gamescope headless).
## Every dialog click runs plain, then again with the leftover release swallow.
const _Hash = preload("res://scripts/core/SaveStateHash.gd")
const _Format = preload("res://scripts/core/SaveFormat.gd")
const _Io = preload("res://scripts/core/SaveReload1Io.gd")
const PLAY := Vector2i(1280, 800)

var _failures := 0
var _event_seq := 0
var _bar: Node
var _mr: Node
var _leftover: Node
var _pick_pid := -1
var _created: Array[String] = []
var _menu_item_y: Dictionary = {}


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] WindowedSaveReload1UiGuard: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] WindowedSaveReload1UiGuard: ", msg)


func _run() -> void:
	DisplayServer.window_set_size(PLAY)
	root.size = PLAY
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if mm == null or boot == null or not boot.boot(mm, sm, "GER"):
		_fail("campaign boot failed")
		_finish()
		return
	# Production hosts the bar on UILayer 110, above map chrome. A root Control
	# sits under MapRenderer's UI canvas and never receives Menu clicks.
	var hud := CanvasLayer.new()
	hud.name = "UILayer"
	hud.layer = 110
	root.add_child(hud)
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		_fail("TopInfoBar scene missing")
		_finish()
		return
	_bar = packed.instantiate()
	hud.add_child(_bar)
	_setup_map(mm)
	_leftover = _LeftoverReleaseSwallow.new()
	_leftover.name = "LeftoverReleaseSwallow"
	root.add_child(_leftover)
	var toast := get_root().get_node_or_null("LeaderEventUI")
	if toast != null:
		toast.set("force_toast_ui", true)
	await process_frame
	await process_frame
	await _pass_flow(false, "sr1test_ui_plain", true)
	if _failures == 0:
		await _pass_flow(true, "sr1test_ui_swallow", false)
	_cleanup()
	_finish()


func _pass_flow(swallow: bool, slot: String, shots: bool) -> void:
	var tag := "plain" if not swallow else "swallow"
	_track(slot)
	_track("sr1test_ui_bad")
	_track("sr1test_ui_old")
	_track("sr1test_ui_qs")
	if not await _begin_ger(swallow):
		return
	var before := _save_bytes(slot)
	if not await _open_save_dialog(swallow):
		_fail("%s: Menu Save did not open the save dialog" % tag)
		return
	if _command_center_open():
		_fail("%s: Menu Save opened the Command Center" % tag)
		return
	if _save_bytes(slot) != before:
		_fail("%s: a file was written before Save" % tag)
		return
	_pass("%s: Menu Save opened the dialog and wrote nothing" % tag)
	if shots:
		await _shot("save_dialog")
	if not await _type_slot(slot):
		_fail("%s: could not type the slot name" % tag)
		return
	if not await _click_named("BtnSave", swallow):
		_fail("%s: Save button missing" % tag)
		return
	await process_frame
	await process_frame
	var path := _abs_save(slot)
	if not FileAccess.file_exists(path):
		_fail("%s: save file missing after Save" % tag)
		return
	var header: Dictionary = _Format.read_header(path)
	var fields: Dictionary = header.get("header", {}) if header.get("header") is Dictionary else {}
	if str(fields.get("player_tag", "")).strip_edges().to_upper() != "GER":
		_fail("%s: header player_tag=%s" % [tag, str(fields.get("player_tag", ""))])
		return
	var date := str(fields.get("game_date", ""))
	if date.is_empty():
		_fail("%s: header has no game_date" % tag)
		return
	if not _toast_has("Saved"):
		_fail("%s: no save toast" % tag)
		return
	_pass("%s: saved %s header GER %s" % [tag, slot, date])
	var md5_a := _md5_file(path)
	if not await _click_named("BtnSave", swallow):
		_fail("%s: second Save missing" % tag)
		return
	await process_frame
	var confirm := _dialog_node("ConfirmText")
	if confirm == null or str(confirm.text).find("Overwrite") < 0:
		_fail("%s: overwrite confirm missing text=%s" % [tag, str(confirm.text) if confirm != null else "null"])
		return
	_pass("%s: overwrite confirm shown" % tag)
	if shots:
		await _shot("overwrite_confirm")
	if not await _click_named("BtnConfirmCancel", swallow):
		_fail("%s: overwrite cancel missing" % tag)
		return
	await process_frame
	if _md5_file(path) != md5_a:
		_fail("%s: cancel changed the file" % tag)
		return
	_pass("%s: cancel left the file unchanged" % tag)
	if not await _click_named("BtnSave", swallow):
		return
	await process_frame
	# Wall time is second resolution. Wait so the overwrite file cannot match.
	await create_timer(1.1).timeout
	if not await _click_named("BtnConfirm", swallow):
		_fail("%s: overwrite button missing" % tag)
		return
	await process_frame
	await process_frame
	if _md5_file(path) == md5_a:
		_fail("%s: overwrite did not change the file" % tag)
		return
	_pass("%s: overwrite wrote a new file" % tag)
	_plant_bad_and_old()
	var saved_hash := _hash_now()
	var saved_date := _clock_text()
	if not await _open_load_dialog(swallow):
		_fail("%s: Menu Load did not open the load dialog" % tag)
		return
	var row := _dialog_node("Row_%s" % slot) as Button
	var bad := _dialog_node("Row_sr1test_ui_bad") as Button
	if row == null or str(row.text).find(date.substr(0, 10)) < 0 or str(row.text).find("GER") < 0 and str(row.text).find("Germany") < 0:
		_fail("%s: load row missing date/nation text=%s" % [tag, str(row.text) if row != null else "null"])
		return
	if not _row_before("sr1test_ui_old", slot):
		_fail("%s: newest save is not listed before the old fixture" % tag)
		return
	if bad == null or str(bad.text).find("damaged") < 0:
		_fail("%s: damaged row missing text=%s" % [tag, str(bad.text) if bad != null else "null"])
		return
	if bad.modulate.r > 0.7:
		_fail("%s: damaged row not greyed modulate=%s" % [tag, str(bad.modulate)])
		return
	_pass("%s: load list shows date, nation, and a damaged row" % tag)
	if shots:
		await _shot("load_list")
		if bad != null:
			var scroll := _dialog_node("SaveScroll") as ScrollContainer
			if scroll != null:
				scroll.ensure_control_visible(bad)
			await process_frame
		await _shot("load_damaged_row")
	var hash_before_bad := _hash_now()
	var toast_before_bad := _count_toast_labels("Save file is damaged and can't be loaded")
	_select_row(bad)
	await process_frame
	if not _toast_has("Save file is damaged and can't be loaded"):
		_fail("%s: selecting a damaged save did not show the damaged message" % tag)
		return
	var toast_after_bad := _count_toast_labels("Save file is damaged and can't be loaded")
	if toast_after_bad - toast_before_bad > 1:
		_fail("%s: selecting a damaged save showed %d Error toasts" % [tag, toast_after_bad - toast_before_bad])
		return
	if not await _click_named("BtnLoad", swallow):
		_fail("%s: load button missing" % tag)
		return
	await process_frame
	if _hash_now() != hash_before_bad:
		_fail("%s: damaged row loaded" % tag)
		return
	if not _toast_has("Save file is damaged and can't be loaded"):
		_fail("%s: Load on a damaged save said something else" % tag)
		return
	_pass("%s: damaged row cannot be loaded" % tag)
	_close_dialog()
	await process_frame
	var tm := get_root().get_node_or_null("TimeManager")
	if tm == null:
		_fail("TimeManager missing")
		return
	tm.paused = false
	var adv: Dictionary = tm.advance_live_f5_equivalent_days(3)
	if not bool(adv.get("ok", false)):
		_fail("%s: advance 3 failed %s" % [tag, str(adv)])
		return
	if not await _open_load_dialog(swallow):
		return
	var row_now := _dialog_node("Row_%s" % slot) as Button
	_select_row(row_now)
	if not await _click_named("BtnLoad", swallow):
		return
	await process_frame
	var load_confirm := _dialog_node("ConfirmText")
	if load_confirm == null or str(load_confirm.text).find("will be lost") < 0:
		_fail("%s: unsaved-progress confirm missing" % tag)
		return
	if load_confirm.autowrap_mode == TextServer.AUTOWRAP_OFF:
		_fail("%s: will-be-lost confirm does not wrap" % tag)
		return
	var confirm_panel := _dialog_node("ConfirmPanel") as Control
	if confirm_panel != null and load_confirm.get_minimum_size().y > confirm_panel.size.y - 40.0:
		_fail("%s: will-be-lost confirm overflows the frame" % tag)
		return
	var confirm_margin := _dialog_node("ConfirmMargin") as MarginContainer
	if confirm_margin == null or int(confirm_margin.get_theme_constant("margin_top")) < 24:
		_fail("%s: will-be-lost confirm has no top padding" % tag)
		return
	var sl_sess := get_root().get_node_or_null("SaveLoadManager")
	var sess := str(sl_sess.session_wall_time).strip_edges() if sl_sess != null else ""
	if sess.is_empty():
		if str(load_confirm.text).find("the start of this session") < 0:
			_fail("%s: empty session wall did not say start of this session" % tag)
			return
	else:
		var sess_local := sess
		if sl_sess != null and sl_sess.has_method("format_wall_time_local"):
			sess_local = str(sl_sess.format_wall_time_local(sess))
		if str(load_confirm.text).find(sess_local) < 0 and str(load_confirm.text).find(sess) < 0:
			_fail("%s: unsaved-progress used a file time, not this session (%s)" % [tag, str(load_confirm.text)])
			return
	if not await _click_named("BtnConfirm", swallow):
		return
	await process_frame
	await process_frame
	if _clock_text() != saved_date:
		_fail("%s: date after load %s want %s" % [tag, _clock_text(), saved_date])
		return
	if _hash_now() != saved_hash:
		_fail("%s: state hash changed across the dialog load" % tag)
		return
	_pass("%s: load restored the date and the state hash" % tag)
	await _quick_roundtrip(swallow, tag)
	await _close_paths(swallow, tag)
	if swallow:
		await _end_screen_load()


func _begin_ger(swallow: bool) -> bool:
	var existing := _find_title()
	if existing != null:
		existing.queue_free()
		await process_frame
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot missing")
		return false
	var title := title_scr.new() as Node
	title.name = "LivingTitleBoot"
	root.add_child(title)
	await create_timer(0.3).timeout
	var begin := title.find_child("LivingTitleBegin", true, false) as Button
	if begin == null or not _click_control(begin, swallow):
		_fail("LivingTitleBegin click failed")
		return false
	await process_frame
	await process_frame
	var tag := ""
	var lm := get_root().get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("get_player_country_tag"):
		tag = str(lm.call("get_player_country_tag")).strip_edges().to_upper()
	if tag != "GER":
		_fail("Begin did not set GER (got %s)" % tag)
		return false
	_pass("Begin GER")
	return true


func _open_save_dialog(swallow: bool) -> bool:
	_close_dialog()
	if not await _click_menu_item(0, swallow):
		return false
	await process_frame
	await process_frame
	var dlg := _dialog()
	if dlg == null:
		return false
	return _dialog_node("BtnSave") != null and _dialog_node("SlotName") != null


func _open_load_dialog(swallow: bool) -> bool:
	_close_dialog()
	if not await _click_menu_item(1, swallow):
		return false
	await process_frame
	await process_frame
	return _dialog() != null and _dialog_node("BtnLoad") != null


func _click_menu_item(id: int, swallow: bool) -> bool:
	# Press opens the popup (MenuButton is BUTTON_PRESS). A release on that
	# same click hits Save, because the popup grabs the held button. Focus the
	# wanted row and accept it through the popup's own input, then release.
	var wanted := "load" if id == 1 else "save"
	_dismiss_unexpected()
	await process_frame
	if _bar == null:
		return false
	var mb := _bar.find_child("MenuButton", true, false) as MenuButton
	if mb == null:
		_fail("Menu button missing")
		return false
	var popup := mb.get_popup()
	if popup != null and popup.visible:
		popup.hide()
		await process_frame
	var point := await _control_hit_point(mb)
	var hover := root.get_viewport().gui_get_hovered_control()
	print("MENU_HIT point=%s hover=%s" % [str(point), _node_name(hover)])
	_press_only(point, swallow)
	if popup == null:
		_release_only(point)
		return false
	for _wait in range(8):
		if popup.visible:
			break
		await process_frame
	print("MENU_OPEN visible=%s size=%s" % [str(popup.visible), str(popup.size)])
	if not popup.visible:
		_release_only(point)
		_fail("Menu popup did not open hover=%s" % _node_name(hover))
		return false
	var index := -1
	for i in popup.item_count:
		if popup.get_item_id(i) == id:
			index = i
			break
	if index < 0:
		_release_only(point)
		_fail("Menu item %d missing" % id)
		return false
	popup.set_focused_item(index)
	_popup_accept(popup)
	await process_frame
	_release_only(point)
	await process_frame
	if _dialog_is(wanted):
		print("MENU_ITEM id=%d index=%d title=%s" % [id, index, _dialog_title()])
		return true
	print("MENU_ITEM_MISS id=%d title=%s" % [id, _dialog_title()])
	_fail("Menu item %d did not open the %s dialog" % [id, wanted])
	return false


func _popup_accept(popup: PopupMenu) -> void:
	var down := InputEventKey.new()
	down.pressed = true
	down.echo = false
	down.keycode = KEY_ENTER
	down.physical_keycode = KEY_ENTER
	popup.push_input(down)
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	var up := InputEventKey.new()
	up.pressed = false
	up.echo = false
	up.keycode = KEY_ENTER
	up.physical_keycode = KEY_ENTER
	popup.push_input(up)
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _press_only(screen_pt: Vector2, swallow: bool) -> void:
	if swallow:
		_arm_swallow()
	elif _leftover != null and _leftover.has_method("disarm"):
		_leftover.call("disarm")
	_aim_mouse(screen_pt)
	Input.parse_input_event(_make_mouse(screen_pt, true))
	Input.flush_buffered_events()


func _release_only(screen_pt: Vector2) -> void:
	Input.parse_input_event(_make_mouse(screen_pt, false))
	Input.flush_buffered_events()


func _dialog_is(mode: String) -> bool:
	var dlg := _dialog()
	if dlg == null or not is_instance_valid(dlg) or dlg.is_queued_for_deletion():
		return false
	if mode == "load":
		return _dialog_node("BtnLoad") != null
	return _dialog_node("BtnSave") != null


func _dialog_title() -> String:
	var title := _dialog_node("Title")
	if title is Label:
		return str((title as Label).text)
	return ""


func _dismiss_unexpected() -> void:
	_close_dialog()
	var menu := get_root().get_node_or_null("MainMenu")
	if menu != null and is_instance_valid(menu) and not menu.is_queued_for_deletion():
		menu.queue_free()


func _type_slot(slot: String) -> bool:
	var edit := _dialog_node("SlotName") as LineEdit
	if edit == null or not _click_control(edit, false):
		return false
	edit.grab_focus()
	edit.text = ""
	edit.caret_column = 0
	for i in slot.length():
		var ch := slot.substr(i, 1)
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.echo = false
		ev.unicode = ch.unicode_at(0)
		ev.keycode = ch.unicode_at(0)
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		var up := InputEventKey.new()
		up.pressed = false
		up.echo = false
		up.unicode = ev.unicode
		up.keycode = ev.keycode
		Input.parse_input_event(up)
		Input.flush_buffered_events()
	await process_frame
	var got := str(edit.text).strip_edges()
	if got.find(slot) < 0:
		edit.text = slot
		edit.caret_column = slot.length()
	return str(edit.text).find(slot) >= 0


func _quick_roundtrip(swallow: bool, tag: String) -> void:
	var sl := get_root().get_node_or_null("SaveLoadManager")
	if sl == null:
		_fail("SaveLoadManager missing")
		return
	sl.set("quicksave_slot_override", "sr1test_ui_qs")
	sl.set("quickload_slot_override", "sr1test_ui_qs")
	var vp := root.get_viewport()
	if vp != null:
		vp.gui_release_focus()
	_key_ctrl(KEY_S, swallow)
	await process_frame
	await process_frame
	if not FileAccess.file_exists(_abs_save("sr1test_ui_qs")):
		_fail("%s: Ctrl+S did not write the test quick slot" % tag)
		return
	if _toast_has("Quicksave OK"):
		_fail("%s: Ctrl+S showed a second Quicksave OK toast" % tag)
		return
	if not _toast_has("Saved"):
		_fail("%s: Ctrl+S toast missing" % tag)
		return
	var qs_date := _clock_text()
	var qs_hash := _hash_now()
	var tm := get_root().get_node_or_null("TimeManager")
	tm.paused = false
	tm.advance_live_f5_equivalent_days(2)
	sl.set("quickload_slot_override", "sr1test_ui_qs")
	_key_ctrl(KEY_L, swallow)
	await process_frame
	await process_frame
	if _clock_text() != qs_date or _hash_now() != qs_hash:
		_fail("%s: Ctrl+L did not restore %s/%s" % [tag, _clock_text(), qs_date])
		return
	if not _toast_has("Loaded"):
		_fail("%s: Ctrl+L toast missing" % tag)
		return
	_pass("%s: Ctrl+S / Ctrl+L round-trip" % tag)


func _close_paths(swallow: bool, tag: String) -> void:
	for which in ["BtnClose", "BtnCancel", "esc"]:
		if not await _open_save_dialog(swallow):
			_fail("%s: could not reopen save dialog for %s" % [tag, which])
			return
		var pid_before := int(_mr.get("selected_province_id"))
		var info: CanvasItem = _mr.get("info_panel") as CanvasItem
		var info_before := info != null and info.visible
		_click_at(Vector2(40, 760), swallow)
		await process_frame
		if int(_mr.get("selected_province_id")) != pid_before or (info != null and info.visible and not info_before):
			_fail("%s: a click through the dialog picked a province" % tag)
			return
		if which == "esc":
			_key_esc()
		else:
			if not await _click_named(which, swallow):
				_fail("%s: %s missing" % [tag, which])
				return
		await create_timer(0.4).timeout
		if _dialog() != null:
			_fail("%s: dialog stayed open after %s" % [tag, which])
			return
		var aim_screen := await _open_map_point()
		if not _seed_pick_under(aim_screen):
			_fail("%s: no province under the map click at %s" % [tag, str(aim_screen)])
			return
		_mr.set("selected_province_id", -1)
		_click_at(aim_screen, false)
		await process_frame
		await process_frame
		var picked := int(_mr.get("selected_province_id"))
		if picked <= 0:
			var hov := root.get_viewport().gui_get_hovered_control()
			_fail("%s: map click after %s did not select (pid=%s aim=%s screen=%s mouse=%s hover=%s)" % [tag, which, str(picked), str(_pick_pid), str(aim_screen), str(root.get_viewport().get_mouse_position()), _node_name(hov)])
			return
		_pass("%s: close via %s, next map click selected %d" % [tag, which, picked])


func _end_screen_load() -> void:
	var gd := get_root().get_node_or_null("GameData")
	var cap: GDScript = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	var end: GDScript = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if gd == null or cap == null or end == null:
		_fail("end-screen domains missing")
		return
	var st: Dictionary = gd.peace_state.get("campaign_capitulation", {}) if gd.peace_state.get("campaign_capitulation") is Dictionary else {}
	var caps: Dictionary = st.get("capitulated", {}) if st.get("capitulated") is Dictionary else {}
	caps["GER"] = true
	st["capitulated"] = caps
	gd.peace_state["campaign_capitulation"] = st
	var tm := get_root().get_node_or_null("TimeManager")
	var day := int(tm.get_total_days_elapsed()) if tm != null else 0
	var latched: Dictionary = end.latch_defeat("GER", day)
	if str(latched.get("outcome", "")) != "defeat":
		_fail("defeat did not latch %s" % str(latched))
		return
	await process_frame
	# get_first_node_in_group is on SceneTree. The root Window does not have it.
	var screen: Node = get_first_node_in_group("campaign_end_screen")
	if screen == null:
		_fail("end screen missing after latch_defeat")
		return
	var load_b := screen.find_child("BtnLoad", true, false) as Button
	if load_b == null or not _click_control(load_b, false):
		_fail("end screen Load click failed")
		return
	await process_frame
	await process_frame
	var dlg := _dialog()
	if dlg == null or int(dlg.layer) <= int(screen.layer):
		_fail("load dialog is not above the end screen")
		return
	_pass("end screen Load opened the dialog above the end screen (layer %s > %s)" % [str(dlg.layer), str(screen.layer)])
	_close_dialog()
	await process_frame
	if not _click_control(load_b, true):
		_fail("end screen Load under swallow failed")
		return
	await process_frame
	if _dialog() == null:
		_fail("swallow pass did not open the load dialog from the end screen")
		return
	_pass("end screen Load still opens under the leftover swallow")


func _setup_map(mm: Node) -> void:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	_mr = mr_script.new()
	_mr.name = "MapRenderer"
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	var info := Panel.new()
	info.name = "InfoPanel"
	info.visible = false
	info.size = Vector2(280, 200)
	info.position = Vector2(20, 80)
	ui.add_child(info)
	# show_info_panel writes these with no null check. A missing label is a
	# SCRIPT ERROR that aborts the still-click before the selection sticks.
	for prop in [
		"info_name", "info_owner", "info_population", "info_terrain",
		"info_factories", "info_dev", "info_resources", "info_core", "info_special",
	]:
		var lab := Label.new()
		lab.name = prop
		info.add_child(lab)
		_mr.set(prop, lab)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.enabled = true
	_mr.add_child(cam)
	root.add_child(_mr)
	cam.make_current()
	_mr.set("info_panel", info)
	# The first show_info_panel builds the id badge, and that builder clears
	# selected_province_id. Warm it now so a later still-click keeps the pick.
	if _mr.has_method("_ensure_province_id_badge"):
		_mr.call("_ensure_province_id_badge")
	_aim_camera(mm, cam)


func _aim_camera(mm: Node, cam: Camera2D) -> void:
	# Leave the camera where MapRenderer._ready framed Europe. The campaign
	# boot does not load polygon points, so centroids are (0, 0) and moving
	# the camera there makes every still-click miss.
	var n := 0
	if mm.has_method("get_all_provinces"):
		var provs: Variant = mm.call("get_all_provinces")
		if provs is Dictionary:
			n = (provs as Dictionary).size()
	print("WindowedSaveReload1UiGuard: camera at %s zoom %s provinces=%d" % [str(cam.position), str(cam.zoom), n])


func _seed_pick_under(screen_pt: Vector2) -> bool:
	var vp := root.get_viewport()
	var cam := vp.get_camera_2d() if vp != null else null
	var mm := get_root().get_node_or_null("MapManager")
	if cam == null or _mr == null or mm == null:
		return false
	var world: Vector2 = cam.get_canvas_transform().affine_inverse() * screen_pt
	var pid := 710417
	var prov: Object = mm.call("get_province", pid) if mm.has_method("get_province") else null
	if prov == null and mm.has_method("get_provinces_by_owner"):
		var ids: Array = mm.call("get_provinces_by_owner", "GER")
		if not ids.is_empty():
			pid = int(ids[0])
			prov = mm.call("get_province", pid)
	if prov == null:
		return false
	pid = int(prov.get("id"))
	if "pick_grid" in mm:
		mm.set("pick_grid", null)
	var cents: Dictionary = mm.get("_centroids") if "_centroids" in mm else {}
	cents[pid] = world
	var got := _resolve_still_click(world)
	if got != pid:
		cents.clear()
		cents[pid] = world
		got = _resolve_still_click(world)
	var bag: Dictionary = _mr.get("provinces")
	bag[pid] = prov
	_mr.set("provinces", bag)
	_pick_pid = pid
	print("WindowedSaveReload1UiGuard: seed pid=%d world=%s resolved=%d" % [pid, str(world), got])
	return got == pid


func _resolve_still_click(world: Vector2) -> int:
	if _mr != null and _mr.has_method("_still_click_province_pid"):
		return int(_mr.call("_still_click_province_pid", world, false))
	return -1


func _open_map_point() -> Vector2:
	var candidates: Array[Vector2] = [Vector2(640, 480), Vector2(520, 420), Vector2(780, 540), Vector2(400, 360)]
	for pt in candidates:
		_aim_mouse(pt)
		await process_frame
		var hov := root.get_viewport().gui_get_hovered_control()
		if hov == null or hov.mouse_filter != Control.MOUSE_FILTER_STOP:
			return pt
	return candidates[0]


func _control_hit_point(ctrl: Control) -> Vector2:
	var rect := ctrl.get_global_rect()
	var samples: Array[Vector2] = [rect.get_center()]
	samples.append(rect.position + Vector2(rect.size.x * 0.25, rect.size.y * 0.5))
	samples.append(rect.position + Vector2(rect.size.x * 0.75, rect.size.y * 0.5))
	samples.append(rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.3))
	for pt in samples:
		_aim_mouse(pt)
		await process_frame
		var hov := root.get_viewport().gui_get_hovered_control()
		if hov == ctrl or (hov != null and (ctrl.is_ancestor_of(hov) or hov.is_ancestor_of(ctrl))):
			return pt
	return rect.get_center()


func _node_name(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "null"
	return str(n.name)


func _aim_mouse(screen_pt: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pt
	motion.global_position = screen_pt
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var vp := root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)


func _aim_screen() -> Vector2:
	var vp := root.get_viewport()
	var cam := vp.get_camera_2d() if vp != null else null
	if cam == null:
		return Vector2(640, 450)
	var screen: Vector2 = cam.get_canvas_transform() * Vector2(cam.position)
	return Vector2(clampf(screen.x, 80.0, 1200.0), clampf(screen.y, 120.0, 720.0))


func _click_named(node_name: String, swallow: bool) -> bool:
	var node := _dialog_node(node_name) as Control
	if node == null:
		return false
	return _click_control(node, swallow)


func _click_control(ctrl: Control, swallow: bool) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	var rect := ctrl.get_global_rect()
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return false
	_click_at(rect.get_center(), swallow)
	return true


func _click_at(screen_pt: Vector2, swallow: bool) -> void:
	if swallow:
		_arm_swallow()
	elif _leftover != null and _leftover.has_method("disarm"):
		_leftover.call("disarm")
	# MapRenderer decides bar-vs-map from Viewport.get_mouse_position(), which a
	# bare button event does not update. A motion flush first, or the map eats
	# the Menu click and a later still-click looks like a drag from (0, 0).
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pt
	motion.global_position = screen_pt
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var vp := root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)
	DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))
	Input.parse_input_event(_make_mouse(screen_pt, true))
	Input.flush_buffered_events()
	Input.parse_input_event(_make_mouse(screen_pt, false))
	Input.flush_buffered_events()


func _arm_swallow() -> void:
	if _mr != null and _mr.has_method("arm_ui_close_release_swallow"):
		_mr.call("arm_ui_close_release_swallow")
	if _leftover != null and _leftover.has_method("arm"):
		_leftover.call("arm")


func _make_mouse(screen_pt: Vector2, pressed: bool) -> InputEventMouseButton:
	_event_seq += 1
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = screen_pt
	ev.global_position = screen_pt
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


func _key_ctrl(code: Key, swallow: bool) -> void:
	if swallow:
		_arm_swallow()
	var down := InputEventKey.new()
	down.pressed = true
	down.echo = false
	down.keycode = code
	down.physical_keycode = code
	down.ctrl_pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	var up := InputEventKey.new()
	up.pressed = false
	up.echo = false
	up.keycode = code
	up.physical_keycode = code
	up.ctrl_pressed = true
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _key_esc() -> void:
	var down := InputEventKey.new()
	down.pressed = true
	down.echo = false
	down.keycode = KEY_ESCAPE
	down.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(down)
	Input.flush_buffered_events()


func _dialog() -> CanvasLayer:
	var n := get_root().get_node_or_null("SaveLoadPopup")
	return n as CanvasLayer


func _dialog_node(node_name: String) -> Node:
	var dlg := _dialog()
	if dlg == null:
		return null
	return dlg.find_child(node_name, true, false)


func _select_row(row: Button) -> void:
	if row == null:
		return
	row.pressed.emit()


func _row_before(older: String, newer: String) -> bool:
	var list := _dialog_node("SaveList")
	if list == null:
		return false
	var oi := -1
	var ni := -1
	var i := 0
	for child in list.get_children():
		if str(child.name) == "Row_%s" % older:
			oi = i
		if str(child.name) == "Row_%s" % newer:
			ni = i
		i += 1
	return ni >= 0 and oi >= 0 and ni < oi


func _command_center_open() -> bool:
	var menu := get_root().get_node_or_null("MainMenu")
	return menu != null and is_instance_valid(menu) and not menu.is_queued_for_deletion() and not bool(menu.get("_closing"))


func _close_dialog() -> void:
	var dlg := _dialog()
	if dlg != null and is_instance_valid(dlg):
		dlg.queue_free()


func _toast_has(fragment: String) -> bool:
	return _label_has(get_root(), fragment)


func _count_toast_labels(fragment: String) -> int:
	return _count_labels(get_root(), fragment)


func _count_labels(n: Node, fragment: String) -> int:
	var c := 0
	if n is Label and str((n as Label).text).find(fragment) >= 0:
		c += 1
	for child in n.get_children():
		c += _count_labels(child, fragment)
	return c


func _label_has(n: Node, fragment: String) -> bool:
	if n is Label and str((n as Label).text).find(fragment) >= 0:
		return true
	for child in n.get_children():
		if _label_has(child, fragment):
			return true
	return false


func _clock_text() -> String:
	var tm := get_root().get_node_or_null("TimeManager")
	if tm == null:
		return ""
	return "%04d-%02d-%02d" % [int(tm.current_year), int(tm.current_month), int(tm.current_day)]


func _hash_now() -> String:
	var sl := get_root().get_node_or_null("SaveLoadManager")
	if sl == null or not sl.has_method("_gather_save_data"):
		return ""
	var data: Dictionary = sl.call("_gather_save_data")
	return str(_Hash.state_hash(data))


func _plant_bad_and_old() -> void:
	_write_bytes("sr1test_ui_bad.eoasave", "NOTASAVE".to_utf8_buffer())
	var old := "{\"save_version\":1,\"metadata\":{\"timestamp\":\"1999-01-01T00:00:00\",\"player_tag\":\"FRA\",\"scenario_id\":\"1936\",\"game_date\":\"1936-01-01 00:00\",\"nation_name\":\"France\"}}"
	_write_bytes("sr1test_ui_old.json", old.to_utf8_buffer())


func _write_bytes(file_name: String, bytes: PackedByteArray) -> void:
	var path := ProjectSettings.globalize_path("user://saves/" + file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()


func _abs_save(slot: String) -> String:
	return ProjectSettings.globalize_path("user://saves/%s.eoasave" % slot)


func _save_bytes(slot: String) -> int:
	var path := _abs_save(slot)
	if not FileAccess.file_exists(path):
		return -1
	return FileAccess.get_file_as_bytes(path).size()


func _md5_file(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


func _shot(shot_name: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	var tex := root.get_viewport().get_texture()
	if tex == null:
		_fail("screenshot %s has no viewport texture" % shot_name)
		return
	var img := tex.get_image()
	if img == null:
		_fail("screenshot %s image missing" % shot_name)
		return
	var path := _Io.evidence_file("%s.png" % shot_name)
	var err := img.save_png(path)
	if err != OK:
		_fail("screenshot %s save failed %s" % [shot_name, str(err)])
		return
	_pass("screenshot %s" % shot_name)


func _find_title() -> Node:
	return get_root().find_child("LivingTitleBoot", true, false)


func _track(slot: String) -> void:
	if slot not in _created:
		_created.append(slot)


func _cleanup() -> void:
	var sl := get_root().get_node_or_null("SaveLoadManager")
	if sl != null:
		sl.set("quicksave_slot_override", "")
		sl.set("quickload_slot_override", "")
		if sl.has_method("delete_save"):
			for slot in _created:
				sl.call("delete_save", slot)


func _finish() -> void:
	var ok := _failures == 0
	print("WindowedSaveReload1UiGuard: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("WindowedSaveReload1UiGuard: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


class _LeftoverReleaseSwallow extends Node:
	var _armed: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process_input(true)

	func arm() -> void:
		_armed = true

	func disarm() -> void:
		_armed = false

	func _input(event: InputEvent) -> void:
		if not _armed or not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
			return
		_armed = false
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
