extends SceneTree

## SR1 FIX #4: Command Center opened from the title must swallow title clicks
## and close on Esc / × / Return to Title. Private display only (wrapper).
const PLAY := Vector2i(1280, 800)
const SLOT := "sr1fix4_cc"

var _failures := 0
var _sl
var _created: Array[String] = []


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] WindowedSaveReload1TitleCcTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] WindowedSaveReload1TitleCcTest: ", msg)


func _run() -> void:
	DisplayServer.window_set_size(PLAY)
	root.size = PLAY
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_sl = get_root().get_node_or_null("SaveLoadManager")
	if mm == null or boot == null or _sl == null:
		_fail("autoloads missing")
		_finish()
		return
	if not boot.boot(mm, sm, "GER"):
		_fail("boot failed")
		_finish()
		return
	if _sl.has_method("delete_save"):
		_sl.call("delete_save", SLOT)
	_created.append(SLOT)
	var written: Dictionary = _sl.save_game_detailed(SLOT)
	if not bool(written.get("ok", false)):
		_fail("could not write title save %s" % str(written.get("error", "")))
		_finish()
		return
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
	if title.has_method("_fit_panel_to_viewport"):
		title.call("_fit_panel_to_viewport")
	await process_frame
	var row := title.find_child("LivingTitleSaveRow_%s" % SLOT, true, false) as Control
	var begin := title.find_child("LivingTitleBegin", true, false) as Control
	if row == null or begin == null:
		_fail("title save row / Begin missing")
		_cleanup(title)
		_finish()
		return
	if not bool(title.call("handle_live_command_center_click")):
		_fail("title CC button must open Command Center")
		_cleanup(title)
		_finish()
		return
	if title.has_method("_instance_command_center_now"):
		title.call("_instance_command_center_now")
	var cc: Node = root.get_node_or_null("MainMenu")
	if cc == null or bool(cc.get("_closing")):
		_fail("Command Center missing after title CC click")
		_cleanup(title)
		_finish()
		return
	cc.set_meta("eoa_sr1_block_quit", true)
	_pass("title CC button opened Command Center")
	_sl.last_load_result = {}
	title.set("last_save_pointer", {})
	var save_pt: Vector2 = row.get_global_rect().get_center()
	var begin_pt: Vector2 = begin.get_global_rect().get_center()
	var exit_btn := cc.find_child("Exit to Desktop", true, false) as Control
	if exit_btn == null:
		for child in _buttons(cc):
			if str(child.text).find("Exit") >= 0:
				exit_btn = child
				break
	var exit_pt: Vector2 = exit_btn.get_global_rect().get_center() if exit_btn != null else Vector2(180, 640)
	var save_act := _pointer(title, save_pt)
	var begin_act := _pointer(title, begin_pt)
	var exit_act := _pointer(title, exit_pt)
	if save_act != "cc_block" or begin_act != "cc_block" or exit_act != "cc_block":
		_fail("title pointer while CC is up must be cc_block (save=%s begin=%s exit=%s)" % [save_act, begin_act, exit_act])
	var ptr_raw: Variant = title.get("last_save_pointer")
	var ptr: Dictionary = ptr_raw if typeof(ptr_raw) == TYPE_DICTIONARY else {}
	if str(ptr.get("kind", "")) == "load" or bool(_sl.last_load_result.get("ok", false)):
		_fail("click on the save-row position loaded a save through Command Center")
	if bool(title.get("_closed")):
		_fail("click on Begin under Command Center dismissed the title")
	if bool(cc.get_meta("eoa_sr1_exit_fired", false)):
		_fail("click on the Exit position quit while Command Center was swallowing")
	if _failures == 0:
		_pass("CC swallows save-row / Begin / Exit-underneath clicks")
	if title.has_method("_process"):
		title.call("_process", 0.016)
	await process_frame
	if not bool(title.call("handle_live_escape")):
		_fail("Esc must close Command Center opened from the title")
	elif is_instance_valid(cc) and not bool(cc.get("_closing")) and not cc.is_queued_for_deletion():
		_fail("Esc left Command Center open")
	else:
		_pass("Esc closes title-opened Command Center")
	await process_frame
	if is_instance_valid(cc):
		cc.queue_free()
		await process_frame
	if not bool(title.call("handle_live_command_center_click")):
		_fail("could not reopen Command Center for ×")
		_cleanup(title)
		_finish()
		return
	if title.has_method("_instance_command_center_now"):
		title.call("_instance_command_center_now")
	cc = root.get_node_or_null("MainMenu")
	if cc == null:
		_fail("reopen for × failed")
		_cleanup(title)
		_finish()
		return
	cc.set_meta("eoa_sr1_block_quit", true)
	await process_frame
	var close_x := cc.find_child("CloseX", true, false) as Button
	if close_x == null:
		_fail("CloseX missing")
	else:
		close_x.pressed.emit()
		await process_frame
		if is_instance_valid(cc) and not bool(cc.get("_closing")) and not cc.is_queued_for_deletion():
			_fail("× did not close Command Center")
		else:
			_pass("× closes title-opened Command Center")
	if is_instance_valid(cc):
		cc.queue_free()
		await process_frame
	if not bool(title.call("handle_live_command_center_click")):
		_fail("could not reopen Command Center for Return to Title")
		_cleanup(title)
		_finish()
		return
	if title.has_method("_instance_command_center_now"):
		title.call("_instance_command_center_now")
	cc = root.get_node_or_null("MainMenu")
	if cc == null:
		_fail("reopen for Return to Title failed")
		_cleanup(title)
		_finish()
		return
	if cc.has_method("_return_to_title"):
		cc.call("_return_to_title")
	await process_frame
	if is_instance_valid(cc) and not bool(cc.get("_closing")) and not cc.is_queued_for_deletion():
		_fail("Return to Title did not close Command Center")
	elif not is_instance_valid(title) or bool(title.get("_closed")):
		_fail("Return to Title dismissed the living title")
	else:
		_pass("Return to Title closes CC and leaves the title up")
	_cleanup(title)
	_finish()


func _pointer(title: Node, pos: Vector2) -> String:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	if title.has_method("handle_live_pointer"):
		return str(title.call("handle_live_pointer", ev))
	return ""


func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button:
		out.append(n as Button)
	for child in n.get_children():
		out.append_array(_buttons(child))
	return out


func _cleanup(title: Variant) -> void:
	if title is Node and is_instance_valid(title):
		(title as Node).queue_free()
	var leftover: Node = root.get_node_or_null("MainMenu")
	if leftover != null and is_instance_valid(leftover):
		leftover.queue_free()
	if _sl != null and _sl.has_method("delete_save"):
		for slot in _created:
			_sl.call("delete_save", slot)


func _finish() -> void:
	var ok := _failures == 0
	print("WindowedSaveReload1TitleCcTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("WindowedSaveReload1TitleCcTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
