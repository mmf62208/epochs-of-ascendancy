extends SceneTree

## SR1 FIX #2/#3: 12 title-screen saves stay inside 1280×800, Begin stays on-screen,
## a row pointer click loads, local time applies zone bias, and CC never steals
## a visible save-row centre. Damaged rows are greyed and refuse the load.
const _Io = preload("res://scripts/core/SaveReload1Io.gd")

const PLAY := Vector2i(1280, 800)
const SLOT_PREFIX := "sr1fix2_"
const DAMAGED_SLOT := "sr1fix2_bad"
const UTC_FIXED := "1936-06-15T08:00:00"
const DAMAGED_MSG := "Save file is damaged and can't be loaded"

var _failures := 0
var _created: Array[String] = []
var _sl
var _tm


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	OS.set_environment("EOA_SKIP_TITLE", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveReload1TitleListTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveReload1TitleListTest: ", msg)


func _run() -> void:
	DisplayServer.window_set_size(PLAY)
	root.size = PLAY
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_sl = get_root().get_node_or_null("SaveLoadManager")
	_tm = get_root().get_node_or_null("TimeManager")
	if mm == null or boot == null or _sl == null or _tm == null:
		_fail("autoloads missing")
		_finish()
		return
	if not boot.boot(mm, sm, "GER"):
		_fail("boot failed")
		_finish()
		return
	_wipe_prefix(SLOT_PREFIX)
	if not _write_twelve_saves():
		_finish()
		return
	_assert_v2_does_not_log_v1_migrate()
	await _assert_confirm_top_pad()
	await _assert_session_wall_confirm()
	await _assert_camera_restore()
	_plant_damaged()
	var toast := get_root().get_node_or_null("LeaderEventUI")
	if toast != null:
		toast.set("force_toast_ui", true)
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot missing")
		_finish()
		return
	var title: Node = title_scr.new()
	title.name = "LivingTitleBoot"
	root.add_child(title)
	await process_frame
	await process_frame
	await process_frame
	if title.has_method("_fit_panel_to_viewport"):
		title.call("_fit_panel_to_viewport")
	await process_frame
	_assert_local_time_bias()
	_assert_panel_fits(title)
	await _assert_damaged_row(title)
	await _assert_visible_row_centres_never_cc(title)
	var loaded_ok := await _assert_click_loads(title)
	if is_instance_valid(title):
		_cleanup(title)
	else:
		_cleanup(null)
	_finish()


func _write_twelve_saves() -> bool:
	var first := "sr1fix2_00"
	var written: Dictionary = _sl.save_game_detailed(first)
	_track(first)
	if not bool(written.get("ok", false)):
		_fail("first save failed: %s" % str(written.get("error", "")))
		return false
	var src := str(written.get("absolute_path", written.get("path", "")))
	if src.begins_with("user://"):
		src = ProjectSettings.globalize_path(src)
	if src.is_empty() or not FileAccess.file_exists(src):
		_fail("first save path missing")
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src)
	for i in range(1, 12):
		var slot := "%s%02d" % [SLOT_PREFIX, i]
		_track(slot)
		var dest := ProjectSettings.globalize_path("user://saves/%s.eoasave" % slot)
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			_fail("could not copy save %s" % slot)
			return false
		f.store_buffer(bytes)
		f.close()
	_pass("wrote 12 title-list saves")
	return true


func _plant_damaged() -> void:
	_track(DAMAGED_SLOT)
	var dest := ProjectSettings.globalize_path("user://saves/%s.eoasave" % DAMAGED_SLOT)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer("NOTASAVE".to_utf8_buffer())
	f.close()


func _assert_panel_fits(title: Node) -> void:
	var panel := title.find_child("LivingTitlePanel", true, false) as Control
	var begin := title.find_child("LivingTitleBegin", true, false) as Control
	var scroll := title.find_child("LivingTitleSaveScroll", true, false) as ScrollContainer
	if panel == null or begin == null or scroll == null:
		_fail("title panel / Begin / save scroll missing")
		return
	var pr: Rect2 = panel.get_global_rect()
	if pr.size.y > 800.0 + 0.5:
		_fail("title panel height %.1f exceeds 800" % pr.size.y)
	else:
		_pass("title panel height %.1f fits in 800" % pr.size.y)
	if pr.end.y > 800.0 + 0.5 or pr.position.y < -0.5:
		_fail("title panel rect %s is not inside 800 px" % str(pr))
	else:
		_pass("title panel rect stays on 1280x800")
	var br: Rect2 = begin.get_global_rect()
	if br.position.x < -0.5 or br.position.y < -0.5 or br.end.x > 1280.5 or br.end.y > 800.5:
		_fail("Begin rect %s is off-screen at 1280x800" % str(br))
	else:
		_pass("Begin rect %s is on-screen" % str(br))
	if scroll.custom_minimum_size.y > 168.5:
		_fail("save scroll min height %.1f is not capped" % scroll.custom_minimum_size.y)
	else:
		_pass("save list is in a capped ScrollContainer (%.1f)" % scroll.custom_minimum_size.y)
	var listed := 0
	for i in range(12):
		var slot := "%s%02d" % [SLOT_PREFIX, i]
		if title.find_child("LivingTitleSaveRow_%s" % slot, true, false) != null:
			listed += 1
	if listed < 12:
		_fail("title listed %d/12 of the written saves" % listed)
	else:
		_pass("title listed all 12 written saves")


func _iso_norm(s: String) -> String:
	return s.strip_edges().replace(" ", "T")


func _assert_local_time_bias() -> void:
	if _sl == null or not _sl.has_method("format_wall_time_local"):
		_fail("format_wall_time_local missing")
		return
	var west := _iso_norm(str(_sl.format_wall_time_local(UTC_FIXED, -240)))
	var east := _iso_norm(str(_sl.format_wall_time_local(UTC_FIXED, 240)))
	if west != "1936-06-15T04:00:00":
		_fail("UTC−4 bias did not shift 08:00 → 04:00 (got %s)" % west)
	else:
		_pass("injected bias −240 maps 08:00 UTC to 04:00 local")
	if east != "1936-06-15T12:00:00":
		_fail("UTC+4 bias did not shift 08:00 → 12:00 (got %s)" % east)
	else:
		_pass("injected bias +240 maps 08:00 UTC to 12:00 local")
	var tz: Dictionary = Time.get_time_zone_from_system()
	var sys_bias := int(tz.get("bias", 0))
	var via_system := _iso_norm(str(_sl.format_wall_time_local(UTC_FIXED)))
	var via_inject := _iso_norm(str(_sl.format_wall_time_local(UTC_FIXED, sys_bias)))
	if via_system != via_inject:
		_fail("system bias %d disagrees (system=%s inject=%s)" % [sys_bias, via_system, via_inject])
	else:
		_pass("system bias %d matches an injected call (%s)" % [sys_bias, via_system])


func _status_text(title: Node) -> String:
	var status: Variant = title.get("_status")
	if status is Label:
		return str((status as Label).text)
	return ""


func _pointer_press(title: Node, pos: Vector2) -> String:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	if not title.has_method("handle_live_pointer"):
		return ""
	return str(title.call("handle_live_pointer", ev))


func _scroll_row_into_view(title: Node, row: Control) -> void:
	var scroll := title.find_child("LivingTitleSaveScroll", true, false) as ScrollContainer
	if scroll != null and row != null:
		scroll.ensure_control_visible(row)


func _assert_damaged_row(title: Node) -> void:
	var bad := title.find_child("LivingTitleSaveRow_%s" % DAMAGED_SLOT, true, false) as Button
	if bad == null:
		_fail("title did not list the damaged save")
		return
	if str(bad.text).find("damaged") < 0:
		_fail("damaged title row text=%s" % bad.text)
		return
	if bad.modulate.r > 0.7:
		_fail("damaged title row not greyed")
		return
	_scroll_row_into_view(title, bad)
	await process_frame
	title.set("last_save_pointer", {})
	var action := _pointer_press(title, bad.get_global_rect().get_center())
	await process_frame
	if action == "cc":
		_fail("damaged row centre opened Command Center (action=cc)")
		return
	if not is_instance_valid(title) or bool(title.get("_closed")):
		_fail("clicking the damaged title row dismissed the title")
		return
	var msg := _status_text(title)
	if msg.find(DAMAGED_MSG) < 0:
		_fail("damaged title row pointer miss (action=%s status=%s)" % [action, msg])
		return
	var toast_n := _count_toast_labels(DAMAGED_MSG)
	if toast_n > 1:
		_fail("damaged title row showed %d identical Error toasts" % toast_n)
		return
	_pass("damaged title row is greyed and refuses the load")


func _visible_row_centres(title: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scroll := title.find_child("LivingTitleSaveScroll", true, false) as ScrollContainer
	if scroll == null:
		return out
	var sr: Rect2 = scroll.get_global_rect()
	var rows: Variant = title.get("_save_rows")
	if typeof(rows) != TYPE_ARRAY:
		return out
	for raw in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var btn: Button = (raw as Dictionary).get("btn") as Button
		if btn == null or not is_instance_valid(btn):
			continue
		var centre: Vector2 = btn.get_global_rect().get_center()
		if not sr.has_point(centre):
			continue
		out.append({
			"btn": btn,
			"slot": str((raw as Dictionary).get("slot", "")),
			"damaged": bool((raw as Dictionary).get("damaged", false)),
			"centre": centre,
		})
	return out


func _assert_visible_row_centres_never_cc(title: Node) -> void:
	var scroll := title.find_child("LivingTitleSaveScroll", true, false) as ScrollContainer
	if scroll == null:
		_fail("save scroll missing for row-centre sweep")
		return
	title.set_meta("eoa_sr1_hit_probe", true)
	var bar: ScrollBar = scroll.get_v_scroll_bar()
	var max_scroll := 0
	if bar != null:
		max_scroll = maxi(0, int(round(float(bar.max_value) - float(bar.page))))
	var fracs: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
	var clicked := 0
	var cc_hits := 0
	for frac in fracs:
		scroll.scroll_vertical = int(round(float(max_scroll) * frac))
		await process_frame
		await process_frame
		var vis: Array[Dictionary] = _visible_row_centres(title)
		for hit in vis:
			var centre: Vector2 = hit["centre"] as Vector2
			title.set("last_save_pointer", {})
			var action := _pointer_press(title, centre)
			clicked += 1
			if action == "cc":
				cc_hits += 1
				_fail("visible row centre %s at scroll=%d opened CC" % [str(hit.get("slot", "")), scroll.scroll_vertical])
				continue
			if not is_instance_valid(title) or bool(title.get("_closed")):
				_fail("visible row centre %s closed the title during probe" % str(hit.get("slot", "")))
				return
			var ptr_raw: Variant = title.get("last_save_pointer")
			var ptr: Dictionary = ptr_raw if typeof(ptr_raw) == TYPE_DICTIONARY else {}
			var kind := str(ptr.get("kind", ""))
			var damaged := bool(hit.get("damaged", false))
			if action != "save":
				_fail("visible row centre %s action=%s (want save, never cc)" % [str(hit.get("slot", "")), action])
				continue
			if damaged:
				if kind != "damaged" or _status_text(title).find(DAMAGED_MSG) < 0:
					_fail("visible damaged centre %s did not show damaged message (kind=%s)" % [str(hit.get("slot", "")), kind])
					continue
			elif kind != "load":
				_fail("visible row centre %s did not classify as load (kind=%s)" % [str(hit.get("slot", "")), kind])
				continue
	if is_instance_valid(title) and title.has_meta("eoa_sr1_hit_probe"):
		title.remove_meta("eoa_sr1_hit_probe")
	if clicked < 8:
		_fail("row-centre sweep only clicked %d visible centres (need several scroll positions)" % clicked)
		return
	if cc_hits > 0:
		_fail("row-centre sweep opened CC %d time(s) across %d centres" % [cc_hits, clicked])
		return
	_pass("clicked %d visible row centres across 5 scroll positions; never CC" % clicked)


func _assert_click_loads(title: Node) -> bool:
	var slot := "sr1fix2_00"
	var row := title.find_child("LivingTitleSaveRow_%s" % slot, true, false) as Button
	if row == null:
		_fail("loadable title row %s missing" % slot)
		return false
	_scroll_row_into_view(title, row)
	await process_frame
	if _sl != null:
		_sl.last_load_result = {}
	if _tm != null:
		_tm.paused = false
		_tm.advance_live_f5_equivalent_days(2)
	var action := _pointer_press(title, row.get_global_rect().get_center())
	if action == "cc":
		_fail("loadable row centre opened Command Center (action=cc)")
		return false
	if action != "save":
		_fail("pointer click on %s missed the row (action=%s; no button fallback)" % [slot, action])
		return false
	await process_frame
	await process_frame
	var loaded: Dictionary = _sl.last_load_result if _sl != null else {}
	if not bool(loaded.get("ok", false)):
		_fail("clicking title row did not load (%s)" % str(loaded.get("error", "")))
		return false
	if is_instance_valid(title) and not bool(title.get("_closed")):
		_fail("title stayed up after a successful row load")
		return false
	_pass("clicking title row %s loaded it" % slot)
	return true


func _count_toast_labels(fragment: String) -> int:
	var lui := get_root().get_node_or_null("LeaderEventUI")
	if lui == null:
		return 0
	return _count_labels(lui, fragment)


func _count_labels(n: Node, fragment: String) -> int:
	var c := 0
	if n is Label and str((n as Label).text).find(fragment) >= 0:
		c += 1
	for child in n.get_children():
		c += _count_labels(child, fragment)
	return c


func _assert_v2_does_not_log_v1_migrate() -> void:
	if _sl == null:
		return
	if bool(_sl.get("last_migrate_was_v1")):
		_fail("fresh v2 save set last_migrate_was_v1")
		return
	if _sl.has_method("list_saves"):
		_sl.call("list_saves")
	if bool(_sl.get("last_migrate_was_v1")):
		_fail("listing v2 saves set last_migrate_was_v1")
		return
	_pass("fresh v2 save / list does not treat the file as v1")


func _assert_confirm_top_pad() -> void:
	var dlg_scr: GDScript = load("res://scripts/ui/SaveLoadDialog.gd") as GDScript
	if dlg_scr == null:
		_fail("SaveLoadDialog missing")
		return
	var dlg: Node = dlg_scr.new()
	root.add_child(dlg)
	await process_frame
	var margin := dlg.find_child("ConfirmMargin", true, false) as MarginContainer
	if margin == null:
		_fail("ConfirmMargin missing")
		dlg.queue_free()
		return
	var top := int(margin.get_theme_constant("margin_top"))
	if top < 24:
		_fail("confirm top margin %d is under the frame art" % top)
	else:
		_pass("confirm top margin %d clears the frame art" % top)
	dlg.queue_free()


func _assert_session_wall_confirm() -> void:
	if _sl == null:
		return
	_sl.session_wall_time = "1936-06-15T08:00:00"
	var dlg_scr: GDScript = load("res://scripts/ui/SaveLoadDialog.gd") as GDScript
	if dlg_scr == null:
		_fail("SaveLoadDialog missing for session wall")
		return
	var dlg: Node = dlg_scr.new()
	root.add_child(dlg)
	await process_frame
	dlg.set("_selected", 0)
	if dlg.has_method("_on_load_pressed"):
		if _tm != null:
			_tm.paused = false
			_tm.advance_live_f5_equivalent_days(1)
		dlg.call("_on_load_pressed")
	await process_frame
	var confirm := dlg.find_child("ConfirmText", true, false) as Label
	var text := str(confirm.text) if confirm != null else ""
	var want := "1936-06-15T08:00:00"
	if _sl.has_method("format_wall_time_local"):
		want = str(_sl.format_wall_time_local("1936-06-15T08:00:00"))
	if text.find("will be lost") < 0:
		_fail("session-wall confirm missing text=%s" % text)
	elif text.find(want) < 0 and text.find("the start of this session") < 0:
		_fail("unsaved-progress used the newest file time instead of the session (text=%s want=%s)" % [text, want])
	else:
		_pass("unsaved-progress uses this session's last save/load time")
	if _tm != null:
		_tm.paused = true
	dlg.queue_free()


func _assert_camera_restore() -> void:
	var mr_scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_scr == null:
		_fail("MapRenderer missing")
		return
	var mr: Node = mr_scr.new()
	mr.name = "MapRendererCam"
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.enabled = true
	cam.global_position = Vector2(1234.0, 567.0)
	cam.zoom = Vector2(1.25, 1.25)
	mr.add_child(cam)
	if not mr.has_method("get_save_data") or not mr.has_method("apply_save_data"):
		_fail("MapRenderer camera save hooks missing")
		mr.free()
		return
	var snap: Dictionary = mr.call("get_save_data")
	if not bool(snap.get("camera_saved", false)):
		_fail("get_save_data did not record the camera")
		mr.free()
		return
	cam.global_position = Vector2(8000.0, 4200.0)
	cam.zoom = Vector2(0.28, 0.28)
	mr.call("apply_save_data", snap)
	if mr.has_method("restore_view_after_load"):
		mr.call("restore_view_after_load")
	var back: Vector2 = cam.global_position
	if back.distance_to(Vector2(1234.0, 567.0)) > 8.0:
		_fail("restore_view_after_load left camera at %s (Brazil-class jump)" % str(back))
	elif absf(cam.zoom.x - 1.25) > 0.05:
		_fail("restore_view_after_load zoom=%s" % str(cam.zoom))
	else:
		_pass("saved camera restored after load (not a Brazil jump)")
	mr.free()


func _wipe_prefix(prefix: String) -> void:
	if _sl == null or not _sl.has_method("list_saves"):
		return
	for raw in _sl.list_saves():
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var slot := str(raw.get("slot", ""))
		if slot.begins_with(prefix) and _sl.has_method("delete_save"):
			_sl.call("delete_save", slot)


func _track(slot: String) -> void:
	if slot not in _created:
		_created.append(slot)


func _cleanup(title: Variant) -> void:
	if title is Node and is_instance_valid(title):
		(title as Node).queue_free()
	if _sl != null and _sl.has_method("delete_save"):
		for slot in _created:
			_sl.call("delete_save", slot)


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessSaveReload1TitleListTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSaveReload1TitleListTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
