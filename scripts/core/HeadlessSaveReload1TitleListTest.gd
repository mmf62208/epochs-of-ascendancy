extends SceneTree

## SR1 FIX #2: 12 title-screen saves stay inside 1280×800, Begin stays on-screen,
## and a row click loads. Damaged rows are greyed and refuse the load.
const _Io = preload("res://scripts/core/SaveReload1Io.gd")

const PLAY := Vector2i(1280, 800)
const SLOT_PREFIX := "sr1fix2_"
const DAMAGED_SLOT := "sr1fix2_bad"

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
	_plant_damaged()
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
	_assert_panel_fits(title)
	await _assert_damaged_row(title)
	var loaded_ok := await _assert_click_loads(title)
	if is_instance_valid(title):
		_cleanup(title)
	else:
		_cleanup(null)
	if not loaded_ok:
		_finish()
		return
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
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = bad.get_global_rect().get_center()
	ev.global_position = ev.position
	if title.has_method("handle_live_pointer"):
		title.call("handle_live_pointer", ev)
	if not bool(title.get("_closed")):
		bad.pressed.emit()
	await process_frame
	if title.is_queued_for_deletion() or bool(title.get("_closed")):
		_fail("clicking the damaged title row dismissed the title")
		return
	var msg := ""
	var status: Variant = title.get("_status")
	if status is Label:
		msg = str((status as Label).text)
	if msg.find("Save file is damaged and can't be loaded") < 0:
		_fail("damaged title row did not show the damaged message (status=%s)" % msg)
		return
	_pass("damaged title row is greyed and refuses the load")


func _assert_click_loads(title: Node) -> bool:
	var slot := "sr1fix2_03"
	var row := title.find_child("LivingTitleSaveRow_%s" % slot, true, false) as Button
	if row == null:
		_fail("loadable title row %s missing" % slot)
		return false
	if _tm != null:
		_tm.paused = false
		_tm.advance_live_f5_equivalent_days(2)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = row.get_global_rect().get_center()
	ev.global_position = ev.position
	if title.has_method("handle_live_pointer"):
		title.call("handle_live_pointer", ev)
	else:
		row.pressed.emit()
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


func _cleanup(title: Node) -> void:
	if title != null and is_instance_valid(title):
		title.queue_free()
	if _sl != null and _sl.has_method("delete_save"):
		for slot in _created:
			_sl.call("delete_save", slot)


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessSaveReload1TitleListTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSaveReload1TitleListTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
