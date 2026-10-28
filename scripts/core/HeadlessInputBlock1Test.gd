extends SceneTree

## INPUT-BLOCK-1: Command Center overlays must consume the click and the Esc
## that belongs to them.
##
##   A. Quicksave Load over the living title must not also Begin (1 Jan 1936).
##   B. A click on the open Command Center must not arm a map gesture (#134).
##   C. Begin must close the Command Center (CC-HANG-1), three runs.
##   D. Esc closes one layer each: search, inspector, Command Center.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessInputBlock1Test.gd

const PLAY_SIZE := Vector2i(1280, 800)
const SAVE_DATE := "1936-06-15"
const PRE_DATE := "1918-01-01"
const SENTINEL_PID := 424242

var _failures: int = 0
var _mr: Node = null
var _ui: CanvasLayer = null
var _bar: Control = null
var _info: Panel = null
var _cam: Camera2D = null
var _title: CanvasLayer = null
var _event_seq: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessInputBlock1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessInputBlock1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessInputBlock1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessInputBlock1Test: ", msg)


func _flush(n: int = 6) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1


func _clock() -> Node:
	return root.get_node_or_null("TimeManager")


func _saves() -> Node:
	return root.get_node_or_null("SaveLoadManager")


func _date_text() -> String:
	var tm := _clock()
	if tm == null:
		return "no-clock"
	return "%04d-%02d-%02d" % [
		int(tm.get("current_year")),
		int(tm.get("current_month")),
		int(tm.get("current_day")),
	]


func _set_date(y: int, m: int, d: int) -> void:
	var tm := _clock()
	if tm == null:
		return
	tm.set("current_year", y)
	tm.set("current_month", m)
	tm.set("current_day", d)


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	_write_quicksave()
	if not _setup_map_renderer():
		return
	if not await _boot_top_bar():
		return
	await _flush(4)
	await _test_load_does_not_begin()
	await _test_cc_click_does_not_arm_map()
	await _test_begin_closes_cc_three_times()
	await _test_esc_one_layer_each()
	await _test_real_chrome_clicks()
	await _test_real_title_load()
	await _test_real_cc_load()
	await _test_real_esc_clears_then_begin()
	await _test_real_search_esc()
	_cleanup()


func _write_quicksave() -> void:
	var slm := _saves()
	if slm == null or not slm.has_method("get_save_path"):
		_fail("SaveLoadManager missing")
		return
	if slm.has_method("_ensure_save_dir"):
		slm.call("_ensure_save_dir")
	var path := str(slm.call("get_save_path", "quicksave"))
	var body := """{
  "save_version": 2,
  "metadata": {"slot": "quicksave", "player_tag": "GER", "scenario_id": ""},
  "time": {
    "current_date": {"year": 1936, "month": 6, "day": 15, "hour": 8},
    "scenario_start_date": "1936-01-01",
    "paused": true,
    "time_scale": 1.0,
    "total_days_elapsed": 166,
    "current_hour": 8
  },
  "land_war": {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}}
}
"""
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write quicksave at %s" % path)
		return
	f.store_string(body)
	f.close()
	print("INPUT_BLOCK1 quicksave=", path, " exists=", FileAccess.file_exists(path))


func _setup_map_renderer() -> bool:
	var mr_script: Script = _map_pick_hook_script()
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	var map_ui := CanvasLayer.new()
	map_ui.name = "UI"
	_mr.add_child(map_ui)
	_info = Panel.new()
	_info.name = "InfoPanel"
	_info.visible = false
	_info.mouse_filter = Control.MOUSE_FILTER_STOP
	_info.size = Vector2(280, 200)
	map_ui.add_child(_info)
	_mr.set("info_panel", _info)
	_wire_info_labels()
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(400, 300)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_pass("MapRenderer fixture ready")
	return true


func _boot_top_bar() -> bool:
	_ui = CanvasLayer.new()
	_ui.name = "UILayer"
	_ui.layer = 110
	root.add_child(_ui)
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		_fail("TopInfoBar.tscn missing")
		return false
	var inst: Node = packed.instantiate()
	if inst == null or not (inst is Control):
		_fail("TopInfoBar instantiate failed")
		return false
	_bar = inst as Control
	_bar.name = "TopInfoBar"
	if "player_country_tag" in _bar:
		_bar.set("player_country_tag", "GER")
	_ui.add_child(_bar)
	await _flush(2)
	_pass("TopInfoBar live")
	return true


func _spawn_title() -> bool:
	_drop_title_now()
	var title_scr: GDScript = load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot missing")
		return false
	_title = title_scr.new() as CanvasLayer
	if _title == null:
		_fail("LivingTitleBoot create failed")
		return false
	_title.name = "LivingTitleBoot"
	_title.visible = true
	root.add_child(_title)
	await _flush(4)
	return true


func _drop_title_now() -> void:
	if _title != null and is_instance_valid(_title):
		_title.set("_closed", true)
		if not _title.is_queued_for_deletion():
			_title.queue_free()
	_title = null
	var stray := root.get_node_or_null("LivingTitleBoot")
	if stray != null and is_instance_valid(stray) and not stray.is_queued_for_deletion():
		stray.set("_closed", true)
		stray.queue_free()


func _cc_node() -> Node:
	var mm := root.get_node_or_null("MainMenu")
	if mm == null or not is_instance_valid(mm) or mm.is_queued_for_deletion():
		return null
	if str(mm.name) != "MainMenu":
		return null
	return mm


func _cc_capturing() -> bool:
	var mm := _cc_node()
	if mm == null:
		return false
	if bool(mm.get("_closing")):
		return false
	if mm is CanvasLayer and not (mm as CanvasLayer).visible:
		return false
	return true


func _close_cc() -> void:
	var mm := _cc_node()
	if mm != null and mm.has_method("_force_close") and not bool(mm.get("_closing")):
		mm.call("_force_close")


func _open_cc(from_title: bool) -> bool:
	var existing := _cc_node()
	if existing != null:
		_close_cc()
		await _flush(2)
	if _bar != null and _bar.has_method("open_command_center_stay"):
		_bar.call("open_command_center_stay")
	await _flush(6)
	var mm := _cc_node()
	if mm == null:
		_fail("Command Center did not open")
		return false
	if not from_title and mm.has_meta("eoa_opened_from_living_title"):
		mm.remove_meta("eoa_opened_from_living_title")
	if mm.has_method("_refresh_save_list"):
		mm.call("_refresh_save_list")
	await _flush(3)
	return _cc_capturing()


func _make_mouse(screen_pt: Vector2, pressed: bool) -> InputEventMouseButton:
	_event_seq += 1
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.canceled = false
	ev.double_click = false
	ev.position = screen_pt
	ev.global_position = screen_pt
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.set_meta("eoa_inputblock1_seq", _event_seq)
	return ev


func _warp_mouse(screen_pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)
	DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))


func _send_pipeline(screen_pt: Vector2, pressed: bool, through_title: bool) -> void:
	_warp_mouse(screen_pt)
	var ev := _make_mouse(screen_pt, pressed)
	if through_title and _title != null and is_instance_valid(_title) and not _title.is_queued_for_deletion():
		if not bool(_title.get("_closed")):
			_title._input(ev)
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _release_mouse(screen_pt: Vector2) -> void:
	_send_pipeline(screen_pt, false, false)
	await _flush(2)


func _find_quicksave_load() -> Button:
	var mm := _cc_node()
	if mm == null:
		return null
	for n in mm.find_children("*", "Button", true, false):
		if not (n is Button):
			continue
		var b := n as Button
		if b.text != "Load":
			continue
		if str(b.get_meta("eoa_load_slot", "")) != "quicksave":
			continue
		if b.disabled:
			continue
		return b
	return null


func _title_closed() -> bool:
	if _title == null or not is_instance_valid(_title):
		return true
	if _title.is_queued_for_deletion():
		return true
	return bool(_title.get("_closed"))


func _test_load_does_not_begin() -> void:
	print("INPUT_BLOCK1 case=load")
	if not await _spawn_title():
		return
	if not await _open_cc(true):
		_fail("Load case: Command Center not up over the title")
		return
	var load_b := _find_quicksave_load()
	if load_b == null:
		_fail("Load case: quicksave Load button missing or disabled")
		return
	var rect := load_b.get_global_rect()
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		_fail("Load case: Load button has no rect %s" % str(rect))
		return
	var pt := rect.get_center()
	_set_date(1918, 1, 1)
	print("INPUT_BLOCK1 load_pt=", pt, " pre_date=", _date_text(), " cc=", _cc_capturing())
	_send_pipeline(pt, true, true)
	await _flush(4)
	var date_after := _date_text()
	var title_closed := _title_closed()
	print(
		"INPUT_BLOCK1 load_result date=", date_after,
		" title_closed=", title_closed,
		" cc=", _cc_capturing(),
		" held=", Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	)
	await _release_mouse(pt)
	if date_after == "1936-01-01" or title_closed:
		_fail("Load click also fired Begin (date=%s title_closed=%s)" % [date_after, str(title_closed)])
		return
	if date_after != SAVE_DATE:
		_fail("Load did not apply %s (date=%s)" % [SAVE_DATE, date_after])
		return
	_pass("Load applied %s and did not Begin" % SAVE_DATE)


func _reset_gesture() -> void:
	if _mr == null:
		return
	_mr.set("_left_btn_down", false)
	_mr.set("_left_pan_armed", false)
	_mr.set("_left_pan_active", false)
	_mr.set("_left_gesture_dragged", false)
	_mr.set("_left_button_was_up", true)
	_mr.set("_left_origin_valid", false)
	_mr.set("_left_gesture_origin", Vector2(-9, -9))
	_mr.set("_left_origin_screen", Vector2(-9, -9))
	_mr.set("_left_max_slop_sq", 0.0)
	_mr.set("_left_skip_next_pick", false)
	_mr.set("_cc_map_press_latch", false)
	# A prior inspector Esc leaves this set. It hides a later held click from
	# `_process`. Each case starts from an idle map.
	_mr.set("_close_ignore_stale_left_down", false)
	if "_chrome_hold_swallowed" in _mr:
		_mr.set("_chrome_hold_swallowed", false)
	_mr.set("_left_sticky_valid", false)
	_mr.set("_left_sticky_slop_sq", 0.0)
	_mr.set("selected_province_id", SENTINEL_PID)
	_mr.set("selected_formation_id", "")
	if _cam != null:
		_cam.position = Vector2(400, 300)


func _test_cc_click_does_not_arm_map() -> void:
	print("INPUT_BLOCK1 case=clickthrough")
	_drop_title_now()
	await _flush(2)
	if not await _open_cc(false):
		_fail("click-through: Command Center not up")
		return
	var mm := _cc_node()
	var panel := mm.get_node_or_null("Root/MenuPanel") as Control
	if panel == null:
		_fail("click-through: MenuPanel missing")
		return
	var prect := panel.get_global_rect()
	# Interior of the panel header, not a button.
	var panel_pt := prect.position + Vector2(36, 28)
	_reset_gesture()
	_send_pipeline(panel_pt, true, false)
	await _flush(1)
	var armed := bool(_mr.get("_left_btn_down"))
	var pid_after_press := int(_mr.get("selected_province_id"))
	print("INPUT_BLOCK1 panel_press armed=", armed, " pid=", pid_after_press, " pt=", panel_pt)
	await _release_mouse(panel_pt)
	var pid_after_release := int(_mr.get("selected_province_id"))
	if armed:
		_fail("Command Center panel click armed map gesture _left_btn_down (#134)")
	elif pid_after_press != SENTINEL_PID or pid_after_release != SENTINEL_PID:
		_fail("Command Center panel click changed selected_province_id to %s/%s" % [pid_after_press, pid_after_release])
	else:
		_pass("Command Center panel click did not arm the map")
	# Dimmer press closes the overlay. The matching release must not pick.
	if not await _open_cc(false):
		_fail("click-through: Command Center did not reopen for dimmer")
		return
	var dim_pt := Vector2(12, 12)
	_reset_gesture()
	_send_pipeline(dim_pt, true, false)
	await _flush(1)
	var dim_armed := bool(_mr.get("_left_btn_down"))
	await _release_mouse(dim_pt)
	var dim_pid := int(_mr.get("selected_province_id"))
	print("INPUT_BLOCK1 dimmer_press armed=", dim_armed, " pid=", dim_pid, " cc_after=", _cc_capturing())
	if dim_armed or dim_pid != SENTINEL_PID:
		_fail("Command Center dimmer click reached the map (armed=%s pid=%s)" % [dim_armed, dim_pid])
	else:
		_pass("Command Center dimmer click did not reach the map")


func _test_begin_closes_cc_three_times() -> void:
	print("INPUT_BLOCK1 case=hang")
	var hung := 0
	var i := 0
	while i < 3:
		if not await _spawn_title():
			return
		if not await _open_cc(true):
			_fail("CC-HANG run %d: Command Center not up" % (i + 1))
			return
		if _title.has_method("handle_live_begin"):
			_title.call("handle_live_begin")
		await _flush(3)
		var capturing := _cc_capturing()
		print("INPUT_BLOCK1 begin_run=", i + 1, " cc_capturing=", capturing, " title_closed=", _title_closed())
		if capturing:
			hung += 1
		_drop_title_now()
		_close_cc()
		await _flush(2)
		i += 1
	if hung > 0:
		_fail("Begin left the Command Center capturing input on %d/3 runs" % hung)
		return
	_pass("Begin closed the Command Center on 3/3 runs")


func _search_node() -> Node:
	if _mr != null and _mr.has_method("ensure_live_search_chrome"):
		var hosted: Variant = _mr.call("ensure_live_search_chrome")
		if hosted is Node and is_instance_valid(hosted):
			return hosted as Node
	if _bar != null:
		var found := _bar.find_child("MapProvinceSearch", true, false)
		if found != null:
			return found
	return root.find_child("MapProvinceSearch", true, false)


func _search_open() -> bool:
	var search := _search_node()
	if search == null:
		return false
	var line := search.find_child("SearchLineEdit", true, false) as LineEdit
	if line != null and is_instance_valid(line) and line.has_focus() and not line.text.strip_edges().is_empty():
		return true
	var results := search.get_node_or_null("SearchResults") as CanvasItem
	if results != null and is_instance_valid(results) and results.visible:
		return true
	return false


func _inspector_open() -> bool:
	return _info != null and is_instance_valid(_info) and _info.visible


func _layer_state() -> String:
	return "search=%s inspector=%s cc=%s" % [
		str(_search_open()), str(_inspector_open()), str(_cc_capturing())
	]


func _send_esc() -> void:
	_event_seq += 1
	var key := InputEventKey.new()
	key.device = 0
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.key_label = KEY_ESCAPE
	key.pressed = true
	key.echo = false
	key.unicode = 27
	key.set_meta("eoa_inputblock1_seq", _event_seq)
	Input.parse_input_event(key)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	await process_frame
	var up := InputEventKey.new()
	up.device = 0
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.key_label = KEY_ESCAPE
	up.pressed = false
	up.echo = false
	Input.parse_input_event(up)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	await process_frame


func _arm_search_layer() -> bool:
	var search := _search_node()
	if search == null:
		_fail("Esc case: MapProvinceSearch missing")
		return false
	var line := search.find_child("SearchLineEdit", true, false) as LineEdit
	if line == null:
		_fail("Esc case: SearchLineEdit missing")
		return false
	line.text = "berlin"
	line.grab_focus()
	var results := search.get_node_or_null("SearchResults") as Control
	if results == null:
		results = ColorRect.new()
		results.name = "SearchResults"
		results.color = Color(0.05, 0.08, 0.12, 0.95)
		results.custom_minimum_size = Vector2(180, 72)
		results.mouse_filter = Control.MOUSE_FILTER_STOP
		search.add_child(results)
	results.visible = true
	await _flush(1)
	return _search_open()


func _test_esc_one_layer_each() -> void:
	print("INPUT_BLOCK1 case=esc")
	_drop_title_now()
	await _flush(2)
	_close_cc()
	await _flush(2)
	if _info != null:
		_info.visible = true
	if not await _arm_search_layer():
		_fail("Esc case: search layer did not arm")
		return
	if not await _open_cc(false):
		_fail("Esc case: Command Center not up")
		return
	if not _inspector_open():
		_fail("Esc case: inspector not open")
		return
	if not _search_open():
		_fail("Esc case: search closed while opening Command Center")
		return
	print("INPUT_BLOCK1 esc_before ", _layer_state())
	var order: PackedStringArray = []
	var presses := 0
	var dead := 0
	var doubles := 0
	while presses < 6 and (_search_open() or _inspector_open() or _cc_capturing()):
		var before_s := _search_open()
		var before_i := _inspector_open()
		var before_c := _cc_capturing()
		await _send_esc()
		presses += 1
		var after_s := _search_open()
		var after_i := _inspector_open()
		var after_c := _cc_capturing()
		var changed: PackedStringArray = []
		if before_s != after_s:
			changed.append("search")
		if before_i != after_i:
			changed.append("inspector")
		if before_c != after_c:
			changed.append("cc")
		var tag := "dead" if changed.is_empty() else "+".join(changed)
		if changed.is_empty():
			dead += 1
		if changed.size() > 1:
			doubles += 1
		order.append(tag)
		print("INPUT_BLOCK1 esc_press=", presses, " changed=", tag, " ", _layer_state())
	var order_s := ",".join(order)
	print("INPUT_BLOCK1 esc_presses=", presses, " order=", order_s, " dead=", dead, " doubles=", doubles)
	var expect := "search,inspector,cc"
	if order_s != expect or presses != 3 or dead != 0 or doubles != 0:
		_fail("Esc stack presses=%d order=%s (want %s, one layer each)" % [presses, order_s, expect])
		return
	if _search_open() or _inspector_open() or _cc_capturing():
		_fail("Esc stack still open after 3 presses (%s)" % _layer_state())
		return
	_pass("Esc closed search, inspector, then Command Center in 3 presses")


func _map_pick_hook_script() -> Script:
	var hook := GDScript.new()
	hook.source_code = """extends \"res://scripts/map/MapRenderer.gd\"
func _resolve_map_pick_pid(world_pos: Vector2) -> int:
	if bool(get_meta(\"eoa_test_force_pick\", false)):
		return 711414
	return super._resolve_map_pick_pid(world_pos)

func _resolve_hex_pick_pid(world_pos: Vector2) -> int:
	if bool(get_meta(\"eoa_test_force_pick\", false)):
		return 711414
	return super._resolve_hex_pick_pid(world_pos)
"""
	if hook.reload() != OK:
		return load("res://scripts/map/MapRenderer.gd") as Script
	return hook


func _add_info_label(node_name: String) -> Label:
	var lab := Label.new()
	lab.name = node_name
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(lab)
	return lab


func _wire_info_labels() -> void:
	_mr.set("info_name", _add_info_label("LabelName"))
	_mr.set("info_owner", _add_info_label("LabelOwner"))
	_mr.set("info_population", _add_info_label("LabelPopulation"))
	_mr.set("info_terrain", _add_info_label("LabelTerrain"))
	_mr.set("info_factories", _add_info_label("LabelFactories"))
	_mr.set("info_dev", _add_info_label("LabelDev"))
	_mr.set("info_resources", _add_info_label("LabelResources"))
	_mr.set("info_core", _add_info_label("LabelCore"))
	_mr.set("info_special", _add_info_label("LabelSpecial"))
	_mr.set("info_logistics", _add_info_label("LabelLogistics"))
	_mr.set("info_combat", _add_info_label("LabelCombat"))
	_mr.set("info_national", _add_info_label("LabelNational"))
	var mods := RichTextLabel.new()
	mods.name = "InfoModifiers"
	mods.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(mods)
	_mr.set("info_modifiers", mods)


func _seed_province(pid: int, tag: String, pname: String) -> void:
	# Load at runtime. Naming the province class here makes the -s entry
	# script compile Province.gd before the GameData autoload exists.
	var script: Script = load("res://scripts/data/Province.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("INPUT_BLOCK1 province script unavailable")
		return
	var p: Object = script.new()
	p.set("id", pid)
	p.set("name", pname)
	p.set("owner_tag", tag)
	p.set("controller_tag", tag)
	p.set("terrain", "urban")
	p.set("population", 1000000)
	if _mr != null and _mr.get("provinces") is Dictionary:
		(_mr.get("provinces") as Dictionary)[pid] = p
	var mm := root.get_node_or_null("MapManager")
	if mm == null:
		return
	var bag: Variant = mm.get("_provinces")
	if bag is Dictionary:
		bag[pid] = p


func _send_real(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		_warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _click_down(pt: Vector2) -> void:
	_send_real(_make_mouse(pt, true))


func _click_up(pt: Vector2) -> void:
	_send_real(_make_mouse(pt, false))


func _move_to(pt: Vector2) -> void:
	var mot := InputEventMouseMotion.new()
	mot.device = 0
	mot.position = pt
	mot.global_position = pt
	var from := root.get_mouse_position() if root != null else pt
	mot.relative = pt - from
	if mot.relative.length_squared() < 1.0:
		mot.relative = Vector2(4, 4)
	mot.velocity = mot.relative * 40.0
	mot.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
	_send_real(mot)


func _gesture_line(tag: String) -> String:
	return "INPUT_BLOCK1 %s btn=%s origin_valid=%s drag=%s latch=%s pid=%s" % [
		tag,
		str(bool(_mr.get("_left_btn_down"))),
		str(bool(_mr.get("_left_origin_valid"))),
		str(bool(_mr.get("_left_gesture_dragged"))),
		str(bool(_mr.get("_cc_map_press_latch"))),
		str(int(_mr.get("selected_province_id"))),
	]


func _gesture_dirty() -> bool:
	if bool(_mr.get("_left_btn_down")):
		return true
	if bool(_mr.get("_left_origin_valid")):
		return true
	if bool(_mr.get("_left_gesture_dragged")):
		return true
	if bool(_mr.get("_cc_map_press_latch")):
		return true
	return int(_mr.get("selected_province_id")) != SENTINEL_PID


func _title_tag() -> String:
	if _title == null or not is_instance_valid(_title):
		return ""
	return str(_title.get("_tag"))


func _header_point() -> Vector2:
	var mm := _cc_node()
	if mm == null:
		return Vector2.ZERO
	var header := mm.find_child("CommandCenterHeader", true, false) as Control
	if header != null:
		return header.get_global_rect().get_center()
	for n in mm.find_children("*", "Label", true, false):
		if n is Label and (n as Label).text == "Command Center":
			return (n as Control).get_global_rect().get_center()
	return Vector2.ZERO


func _close_point() -> Vector2:
	var mm := _cc_node()
	if mm == null:
		return Vector2.ZERO
	var btn := mm.find_child("CloseX", true, false) as Control
	if btn == null:
		return Vector2.ZERO
	return btn.get_global_rect().get_center()


func _title_load_point() -> Vector2:
	if _title == null or not is_instance_valid(_title):
		return Vector2.ZERO
	for n in _title.find_children("*", "Button", true, false):
		if n is Button and (n as Button).has_meta("eoa_load_slot"):
			return (n as Control).get_global_rect().get_center()
	return Vector2.ZERO


func _begin_point() -> Vector2:
	if _title == null or not is_instance_valid(_title):
		return Vector2.ZERO
	var btn := _title.find_child("LivingTitleBegin", true, false) as Control
	if btn == null:
		return Vector2.ZERO
	return btn.get_global_rect().get_center()


func _press_drag_release(case_name: String, pt: Vector2, drag: bool) -> bool:
	_move_to(pt)
	await process_frame
	_click_down(pt)
	await process_frame
	var dirty := false
	var line := _gesture_line("%s phase=press" % case_name)
	print(line)
	dirty = dirty or _gesture_dirty()
	var up_at := pt
	if drag:
		up_at = pt + Vector2(36, 22)
		_move_to(up_at)
		await process_frame
		print(_gesture_line("%s phase=drag" % case_name))
		dirty = dirty or _gesture_dirty()
	_click_up(up_at)
	await process_frame
	print(_gesture_line("%s phase=release" % case_name))
	dirty = dirty or _gesture_dirty()
	await process_frame
	print(_gesture_line("%s phase=frame" % case_name))
	dirty = dirty or _gesture_dirty()
	return dirty


func _test_real_chrome_clicks() -> void:
	print("INPUT_BLOCK1 case=real_chrome")
	var specs: Array[Dictionary] = [
		{"name": "real_game_dim", "title": false, "kind": "dim", "drag": true, "cc_stays": false},
		{"name": "real_game_header", "title": false, "kind": "header", "drag": true, "cc_stays": true},
		{"name": "real_game_x", "title": false, "kind": "x", "drag": true, "cc_stays": false},
		{"name": "real_title_dim", "title": true, "kind": "dim", "drag": true, "cc_stays": false},
		{"name": "real_title_header", "title": true, "kind": "header", "drag": true, "cc_stays": true},
		{"name": "real_title_x", "title": true, "kind": "x", "drag": true, "cc_stays": false},
	]
	for spec in specs:
		var case_name := str(spec["name"])
		if bool(spec["title"]):
			if not await _spawn_title():
				return
		else:
			_drop_title_now()
			await _flush(2)
		if not await _open_cc(bool(spec["title"])):
			_fail("%s: Command Center not up" % case_name)
			return
		_reset_gesture()
		_mr.set("selected_province_id", SENTINEL_PID)
		var pt := Vector2(40, 400)
		if str(spec["kind"]) == "header":
			pt = _header_point()
		elif str(spec["kind"]) == "x":
			pt = _close_point()
		if pt == Vector2.ZERO:
			_fail("%s: control centre missing" % case_name)
			return
		print("INPUT_BLOCK1 %s pt=%s" % [case_name, str(pt)])
		var dirty := await _press_drag_release(case_name, pt, bool(spec["drag"]))
		var cc_up := _cc_capturing()
		print("INPUT_BLOCK1 %s cc_up=%s" % [case_name, str(cc_up)])
		if dirty:
			_fail("%s: click reached the map" % case_name)
		elif cc_up != bool(spec["cc_stays"]):
			_fail("%s: Command Center up=%s" % [case_name, str(cc_up)])
		else:
			_pass("%s consumed press, release, and the next frame" % case_name)
		_drop_title_now()
		_close_cc()
		await _flush(2)


func _arm_force_pick() -> void:
	_seed_province(711414, "ENG", "London")
	if _mr != null:
		_mr.set_meta("eoa_test_force_pick", true)


func _test_real_title_load() -> void:
	print("INPUT_BLOCK1 case=real_title_load")
	if not await _spawn_title():
		return
	_close_cc()
	await _flush(2)
	_arm_force_pick()
	_reset_gesture()
	_set_date(1918, 1, 1)
	var pt := _title_load_point()
	if pt == Vector2.ZERO:
		_fail("real_title_load: title Load button missing")
		return
	var tag0 := _title_tag()
	print("INPUT_BLOCK1 real_title_load pt=%s tag=%s" % [str(pt), tag0])
	var dirty := await _press_drag_release("real_title_load", pt, false)
	var tag1 := _title_tag()
	print(
		"INPUT_BLOCK1 real_title_load date=%s title_closed=%s tag=%s"
		% [_date_text(), str(_title_closed()), tag1]
	)
	if dirty or tag1 == "ENG" or int(_mr.get("selected_province_id")) == 711414:
		_fail("real_title_load: Load selected the nation or province under the button")
	elif not _title_closed():
		_fail("real_title_load: title Load did not enter the save")
	elif _date_text() != SAVE_DATE:
		_fail("real_title_load: date=%s" % _date_text())
	else:
		_pass("real_title_load did not select the province under Load")
	if _mr != null:
		_mr.set_meta("eoa_test_force_pick", false)


func _test_real_cc_load() -> void:
	print("INPUT_BLOCK1 case=real_cc_load")
	if not await _spawn_title():
		return
	if not await _open_cc(true):
		_fail("real_cc_load: Command Center not up")
		return
	_arm_force_pick()
	_reset_gesture()
	_set_date(1918, 1, 1)
	var load_b := _find_quicksave_load()
	if load_b == null:
		_fail("real_cc_load: quicksave Load missing")
		return
	var pt := load_b.get_global_rect().get_center()
	print("INPUT_BLOCK1 real_cc_load pt=%s tag=%s" % [str(pt), _title_tag()])
	# Hold and drag after Load closes the Command Center. The release and the
	# next frame must not select the nation under that gesture.
	var dirty := await _press_drag_release("real_cc_load", pt, true)
	print(
		"INPUT_BLOCK1 real_cc_load date=%s title_closed=%s tag=%s cc=%s"
		% [_date_text(), str(_title_closed()), _title_tag(), str(_cc_capturing())]
	)
	if dirty or _title_tag() == "ENG" or int(_mr.get("selected_province_id")) == 711414:
		_fail("real_cc_load: Load selected the nation or province under the button")
	elif _title_closed():
		_fail("real_cc_load: Load closed the title")
	elif _date_text() != SAVE_DATE:
		_fail("real_cc_load: date=%s" % _date_text())
	else:
		_pass("real_cc_load did not select the province under Load")
	if _mr != null:
		_mr.set_meta("eoa_test_force_pick", false)


func _type_ascii(text: String) -> void:
	for i in text.length():
		var code := text.unicode_at(i)
		var key := InputEventKey.new()
		key.device = 0
		key.pressed = true
		key.echo = false
		key.unicode = code
		key.keycode = code as Key
		key.physical_keycode = key.keycode
		_send_real(key)
		await process_frame
		var up := key.duplicate() as InputEventKey
		up.pressed = false
		up.unicode = 0
		_send_real(up)
		await process_frame


func _test_real_esc_clears_then_begin() -> void:
	print("INPUT_BLOCK1 case=real_esc_clear_begin")
	_drop_title_now()
	await _flush(2)
	_close_cc()
	await _flush(2)
	_reset_gesture()
	var pt := Vector2(900, 500)
	_move_to(pt)
	await process_frame
	_click_down(pt)
	await process_frame
	_move_to(pt + Vector2(40, 24))
	await process_frame
	var armed_line := _gesture_line("real_esc_clear_begin phase=armed")
	print(armed_line)
	if not bool(_mr.get("_left_btn_down")):
		_fail("real_esc_clear_begin: map press did not arm")
		_click_up(pt + Vector2(40, 24))
		return
	await _send_esc()
	await _flush(3)
	print("INPUT_BLOCK1 real_esc_clear_begin phase=opened cc=%s" % str(_cc_capturing()))
	if not _cc_capturing():
		_fail("real_esc_clear_begin: Esc did not open Command Center")
		_click_up(pt + Vector2(40, 24))
		return
	await _send_esc()
	await _flush(2)
	var closed_line := _gesture_line("real_esc_clear_begin phase=closed")
	print(closed_line)
	var dirty := _gesture_dirty()
	_click_up(pt + Vector2(40, 24))
	await _flush(2)
	print(_gesture_line("real_esc_clear_begin phase=released"))
	dirty = dirty or _gesture_dirty()
	if not await _spawn_title():
		return
	_set_date(1918, 1, 1)
	var begin_pt := _begin_point()
	if begin_pt == Vector2.ZERO:
		_fail("real_esc_clear_begin: Begin button missing")
		return
	_click_down(begin_pt)
	await process_frame
	_click_up(begin_pt)
	await _flush(4)
	var began := _title_closed() and _date_text() == "1936-01-01"
	print(
		"INPUT_BLOCK1 real_esc_clear_begin phase=begin title_closed=%s date=%s"
		% [str(_title_closed()), _date_text()]
	)
	if dirty:
		_fail("real_esc_clear_begin: Esc close left a pending map press")
	elif not began:
		_fail("real_esc_clear_begin: first Begin after Esc did not start")
	else:
		_pass("real_esc_clear_begin cleared the press and Begin worked once")


func _search_line() -> LineEdit:
	var search := _search_node()
	if search == null:
		return null
	return search.find_child("SearchLineEdit", true, false) as LineEdit


func _open_cc_from_menu() -> bool:
	var root_win := root as Window
	if root_win != null:
		root_win.gui_embed_subwindows = true
	var mb: MenuButton = _bar.get("menu_button") as MenuButton
	if mb == null or not mb.visible:
		_fail("real_search_esc: Menu button missing")
		return false
	var menu_pt := mb.get_global_rect().get_center()
	_click_down(menu_pt)
	await process_frame
	_click_up(menu_pt)
	await _flush(3)
	var popup := mb.get_popup()
	if popup == null or not popup.visible:
		_fail("real_search_esc: Menu popup did not open")
		return false
	var idx := -1
	for i in popup.item_count:
		if popup.get_item_text(i) == "Settings":
			idx = i
			break
	if idx < 0:
		_fail("real_search_esc: Settings item missing")
		return false
	# The Menu click opened an embedded popup. Its items are drawn, not
	# child buttons, and a release in the first 400 ms is ignored. Move
	# across the popup through the root viewport (that forwards into the
	# focused window) until Settings is the focused row, then click it.
	popup.grab_focus()
	await process_frame
	var hit := _scan_popup_row(popup, idx)
	print(
		"INPUT_BLOCK1 real_search_esc menu embedded=%s focus=%s size=%s pos=%s hit=%s row=%s"
		% [
			str(popup.is_embedded()),
			str(popup.has_focus()),
			str(popup.size),
			str(popup.position),
			str(hit),
			str(popup.get_focused_item()),
		]
	)
	if hit.x < 0.0:
		_fail("real_search_esc: Settings row was not under the pointer")
		return false
	OS.delay_msec(450)
	_root_click(hit, true)
	_root_click(hit, false)
	await _flush(2)
	if not _cc_capturing():
		_root_click(hit, true)
		_root_click(hit, false)
		await _flush(4)
	return _cc_capturing()


func _scan_popup_row(popup: PopupMenu, idx: int) -> Vector2:
	var origin := Vector2(popup.position)
	var best := Vector2(-1, -1)
	var y := 4
	while y < int(popup.size.y) - 2:
		var pt := origin + Vector2(maxf(popup.size.x, 40.0) * 0.5, float(y))
		var mot := InputEventMouseMotion.new()
		mot.device = 0
		mot.position = pt
		mot.global_position = pt
		mot.relative = Vector2(0, 4)
		mot.velocity = Vector2(0, 40)
		root.push_input(mot)
		if popup.get_focused_item() == idx:
			best = pt
			break
		y += 4
	return best


func _root_click(pt: Vector2, pressed: bool) -> void:
	var ev := _make_mouse(pt, pressed)
	root.push_input(ev)


func _test_real_search_esc() -> void:
	print("INPUT_BLOCK1 case=real_search_esc")
	_drop_title_now()
	await _flush(2)
	_close_cc()
	await _flush(2)
	if _info != null:
		_info.visible = false
	_seed_province(710300, "GER", "Berlin")
	_reset_gesture()
	var line := _search_line()
	if line == null:
		_fail("real_search_esc: search line missing")
		return
	# The direct Esc case leaves a query and a results node. Start this
	# case from an empty line so the typed keys are what open the row.
	var search_reset := _search_node()
	if search_reset != null:
		var leftover := search_reset.get_node_or_null("SearchResults")
		if leftover != null and is_instance_valid(leftover):
			leftover.free()
	line.text = ""
	line.release_focus()
	var line_pt := line.get_global_rect().get_center()
	_click_down(line_pt)
	await process_frame
	_click_up(line_pt)
	await _flush(2)
	if not line.has_focus():
		_fail("real_search_esc: search line did not focus")
		return
	await _type_ascii("berlin")
	await _flush(2)
	var search := _search_node()
	var row := search.find_child("SearchResultRow", true, false) as Button if search != null else null
	if row == null or not row.visible:
		_fail("real_search_esc: result row did not open for berlin text=%s" % line.text)
		return
	var row_pt := row.get_global_rect().get_center()
	print("INPUT_BLOCK1 real_search_esc row=%s text=%s" % [str(row_pt), line.text])
	_click_down(row_pt)
	await process_frame
	_click_up(row_pt)
	await _flush(4)
	if not _search_open() or not _inspector_open():
		_fail("real_search_esc: after pick %s" % _layer_state())
		return
	if not await _open_cc_from_menu():
		_fail("real_search_esc: Menu did not open Command Center (%s)" % _layer_state())
		return
	if not (_search_open() and _inspector_open() and _cc_capturing()):
		_fail("real_search_esc: stack not armed %s" % _layer_state())
		return
	print("INPUT_BLOCK1 real_search_esc before ", _layer_state())
	var order: PackedStringArray = []
	var presses := 0
	while presses < 4 and (_search_open() or _inspector_open() or _cc_capturing()):
		var before_s := _search_open()
		var before_i := _inspector_open()
		var before_c := _cc_capturing()
		await _send_esc()
		presses += 1
		var changed: PackedStringArray = []
		if before_s != _search_open():
			changed.append("search")
		if before_i != _inspector_open():
			changed.append("inspector")
		if before_c != _cc_capturing():
			changed.append("cc")
		var tag := "dead" if changed.is_empty() else "+".join(changed)
		order.append(tag)
		print("INPUT_BLOCK1 real_search_esc press=%d changed=%s %s" % [presses, tag, _layer_state()])
	var order_s := ",".join(order)
	print("INPUT_BLOCK1 real_search_esc presses=%d order=%s" % [presses, order_s])
	if order_s != "search,inspector,cc" or presses != 3:
		_fail("real_search_esc: presses=%d order=%s" % [presses, order_s])
		return
	_pass("real_search_esc closed search, inspector, then Command Center")


func _cleanup() -> void:
	_drop_title_now()
	_close_cc()
