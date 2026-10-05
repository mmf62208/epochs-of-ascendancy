extends SceneTree

## CLOSE-1 windowed xvfb check. 1280×740 · GER · Europe Home · world_accurate.
## Open a unit card, press Close at its real BtnClose position, then warp/move
## straight to the top bar (≥20 times; zooms 0.32–1.5; vary speed). Assert
## camera delta 0 on the first move, then top-edge pan on the first try.
## xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
##
##   tools/eoa_close1_windowed_check.sh

const VIEW_W := 1280
const VIEW_H := 740
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 24
const GER_TAG := "GER"
const CAM_EPS := 1.5
const EDGE_FRAMES := 18
const ZOOMS: Array[float] = [0.32, 0.50, 0.80, 1.20, 1.50]
const TRIALS_PER_ZOOM := 4
const TOP_BAR := Vector2(640.0, 0.0)
const TOP_BAR_ALT := Vector2(10.0, 1.0)
## First-move dest stays below the 6px rim so edge-pan is not scored as a stale drag.
const FIRST_MOVE := Vector2(640.0, 20.0)
const FIRST_MOVE_ALT := Vector2(10.0, 20.0)

enum Phase {
	WAIT_MAP,
	HOME,
	SETTLE,
	OPEN_CARD,
	WAIT_CARD,
	RUN_TRIAL,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _t0_msec: int = 0
var _settle_left: int = 0
var _after_settle: int = Phase.HOME
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _last_wait_log: int = -1
var _home_zoom: float = 0.4
var _fid: String = ""
var _rows: PackedStringArray = PackedStringArray()
var _first_move_ok: int = 0
var _first_move_n: int = 0
var _edge_ok: int = 0
var _edge_n: int = 0
var _trial_i: int = 0
var _last_mouse: Vector2 = Vector2.ZERO


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedClose1CardCloseDragCheck: DisplayServer=%s" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	_force_viewport()
	_out_dir = OS.get_environment("EOA_CLOSE1_LIVE_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-close1-live"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/close1")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_log("EOA_CLOSE1_LIVE who=guard.boot out=%s view=%dx%d (NOT product Play)" % [_out_dir, VIEW_W, VIEW_H])
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail_reasons.append("scene_load_%d" % err)
		_finish(false)
		return
	_phase = Phase.WAIT_MAP
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	match _phase:
		Phase.WAIT_MAP:
			_tick_wait_map()
		Phase.HOME:
			_do_home()
		Phase.SETTLE:
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.OPEN_CARD:
			_do_open_card()
		Phase.WAIT_CARD:
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = Phase.RUN_TRIAL
		Phase.RUN_TRIAL:
			_do_one_trial()
		Phase.DONE:
			pass


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail_reasons.append("map_timeout")
		_finish(false)
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		_log("EOA_CLOSE1_LIVE who=guard.wait_map elapsed=%d n=%d" % [elapsed, _province_count()])
	_dismiss_title_if_needed()
	_force_viewport()
	if not _map_is_ready():
		return
	if int(root.get_meta("close1_live_ready_msec", 0)) == 0:
		root.set_meta("close1_live_ready_msec", Time.get_ticks_msec())
		return
	if Time.get_ticks_msec() - int(root.get_meta("close1_live_ready_msec", 0)) < 1500:
		return
	_log("EOA_CLOSE1_LIVE who=guard.frame_start elapsed=%d n=%d" % [elapsed, _province_count()])
	_phase = Phase.HOME


func _do_home() -> void:
	_force_viewport()
	_force_player_ger()
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	elif mr != null and mr.has_method("center_europe_in_world_view"):
		mr.call("center_europe_in_world_view")
	_pause_clock()
	var cam := _camera()
	if cam != null:
		_home_zoom = maxf(cam.zoom.x, cam.zoom.y)
	_fid = _pick_ger_land_fid()
	_log("EOA_CLOSE1_LIVE who=guard.europe_home ger=%s zoom=%.3f fid=%s" % [_player_tag(), _home_zoom, _fid])
	if _fid.is_empty():
		_fail_reasons.append("no_ger_land_formation")
		_finish(false)
		return
	_go_settle(Phase.OPEN_CARD)


func _do_open_card() -> void:
	var total: int = ZOOMS.size() * TRIALS_PER_ZOOM
	if _trial_i >= total:
		_write_clicks()
		if _first_move_ok != _first_move_n or _first_move_n < 20:
			_fail_reasons.append("first_move %d/%d" % [_first_move_ok, _first_move_n])
		if _edge_ok != _edge_n or _edge_n < 20:
			_fail_reasons.append("first_edge %d/%d" % [_edge_ok, _edge_n])
		_finish(_fail_reasons.is_empty())
		return
	var z: float = ZOOMS[int(_trial_i / TRIALS_PER_ZOOM)]
	_set_zoom(z)
	if not _open_card():
		_fail_reasons.append("card_open_z%.2f_t%d" % [z, _trial_i % TRIALS_PER_ZOOM])
		_trial_i += 1
		_phase = Phase.OPEN_CARD
		return
	_settle_left = 4
	_phase = Phase.WAIT_CARD


func _do_one_trial() -> void:
	var mr := _map_renderer()
	var cam := _camera()
	if mr == null or cam == null:
		_fail_reasons.append("no_map_or_cam")
		_finish(false)
		return
	var z: float = ZOOMS[int(_trial_i / TRIALS_PER_ZOOM)]
	var local_i: int = _trial_i % TRIALS_PER_ZOOM
	var close_pos: Vector2 = _card_close_pos()
	if close_pos == Vector2.ZERO:
		_fail_reasons.append("close_pos_z%.2f_t%d" % [z, local_i])
		_trial_i += 1
		_phase = Phase.OPEN_CARD
		return
	var dest: Vector2 = FIRST_MOVE if (local_i % 2) == 0 else FIRST_MOVE_ALT
	var edge_pos: Vector2 = TOP_BAR if (local_i % 2) == 0 else TOP_BAR_ALT
	var steps: int = 1
	if local_i == 1:
		steps = 4
	elif local_i == 3:
		steps = 8
	_press_close_real(close_pos)
	var before: Vector2 = cam.global_position
	_move_to(close_pos, dest, steps, local_i >= 2)
	var after_move: Vector2 = cam.global_position
	var move_d: float = after_move.distance_to(before)
	_first_move_n += 1
	var live: bool = bool(mr.get("_left_btn_down")) or bool(mr.get("_left_pan_active"))
	var drag_should: bool = false
	if mr.has_method("_left_drag_should_pan"):
		drag_should = bool(mr.call("_left_drag_should_pan"))
	var move_ok: bool = move_d <= CAM_EPS and not live and not drag_should
	if move_ok:
		_first_move_ok += 1
	else:
		_fail_reasons.append("stale_drag_z%.2f_t%d_d=%.1f live=%s" % [z, local_i, move_d, str(live)])
	var edge_before: Vector2 = cam.global_position
	_hold_top_edge(edge_pos)
	var edge_after: Vector2 = cam.global_position
	var edge_d: Vector2 = edge_after - edge_before
	_edge_n += 1
	var edge_ok: bool = edge_d.y < -4.0
	if edge_ok:
		_edge_ok += 1
	else:
		_fail_reasons.append("edge0_z%.2f_t%d_dy=%.1f" % [z, local_i, edge_d.y])
	_rows.append(
		"| %d | %.2f | %.0f,%.0f | %d | %.2f | %s | %.1f | %s |" % [
			_trial_i + 1,
			z,
			close_pos.x,
			close_pos.y,
			steps,
			move_d,
			"PASS" if move_ok else "FAIL",
			edge_d.y,
			"PASS" if edge_ok else "FAIL",
		]
	)
	_log(
		"EOA_CLOSE1_LIVE who=trial i=%d z=%.2f close=%.0f,%.0f steps=%d move_d=%.2f edge_dy=%.1f live=%s" % [
			_trial_i + 1, z, close_pos.x, close_pos.y, steps, move_d, edge_d.y, str(live)
		]
	)
	_recenter_home(z)
	_trial_i += 1
	_phase = Phase.OPEN_CARD


func _open_card() -> bool:
	var mr := _map_renderer()
	var lm := _leader_manager()
	if mr == null or lm == null or _fid.is_empty():
		return false
	var fo: Object = null
	if lm.has_method("get_formation"):
		fo = lm.call("get_formation", _fid)
	elif "formations" in lm:
		fo = lm.formations.get(_fid)
	if fo == null:
		return false
	if "selected_formation_id" in mr:
		mr.selected_formation_id = _fid
	mr.call("_show_unit_detail_popup", fo)
	var ui: Node = mr.get_node_or_null("UI")
	if ui == null:
		return false
	var pop: Node = ui.get_node_or_null("UnitDetailPopup")
	return pop != null and (pop is CanvasItem) and (pop as CanvasItem).visible


func _card_close_pos() -> Vector2:
	var mr := _map_renderer()
	if mr == null:
		return Vector2.ZERO
	var ui: Node = mr.get_node_or_null("UI")
	if ui == null:
		return Vector2.ZERO
	var pop: Node = ui.get_node_or_null("UnitDetailPopup")
	if pop == null:
		return Vector2.ZERO
	var btn: Button = pop.find_child("BtnClose", true, false) as Button
	if btn == null or not btn.visible:
		return Vector2.ZERO
	return btn.get_global_rect().get_center()


func _press_close_real(pos: Vector2) -> void:
	var mr := _map_renderer()
	_warp(pos)
	_press(pos)
	var ui: Node = mr.get_node_or_null("UI") if mr != null else null
	var pop: Node = ui.get_node_or_null("UnitDetailPopup") if ui != null else null
	var btn: Button = pop.find_child("BtnClose", true, false) as Button if pop != null else null
	if btn != null and is_instance_valid(btn):
		btn.pressed.emit()
	_release(pos)


func _move_to(from_pos: Vector2, dest: Vector2, steps: int, with_mask: bool) -> void:
	var n: int = maxi(1, steps)
	var i := 1
	while i <= n:
		var t: float = float(i) / float(n)
		var p: Vector2 = from_pos.lerp(dest, t)
		var mask: int = int(MOUSE_BUTTON_MASK_LEFT) if with_mask else 0
		_motion(p, mask)
		var mr := _map_renderer()
		if mr != null and mr.has_method("_handle_camera_input"):
			mr.call("_handle_camera_input", 0.016)
		i += 1


func _hold_top_edge(pos: Vector2) -> void:
	var i := 0
	while i < EDGE_FRAMES:
		_warp(pos)
		var mot := InputEventMouseMotion.new()
		mot.position = pos
		mot.global_position = pos
		mot.relative = Vector2.ZERO
		var vp := root.get_viewport() if root != null else null
		if vp != null:
			vp.push_input(mot, true)
		var mr := _map_renderer()
		if mr != null and mr.has_method("_handle_camera_input"):
			mr.call("_handle_camera_input", 0.016)
		i += 1


func _recenter_home(z: float) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	_set_zoom(z)
	if mr != null:
		mr.set("_close_camera_locked", false)
		mr.set("_close_click_guard", false)
		mr.set("_close_suppress_edge", false)
		mr.set("_hold_camera_until_msec", 0)
		mr.set("_map_pick_block_until_msec", 0)
		if mr.has_method("_reset_left_gesture_state"):
			mr.call("_reset_left_gesture_state", Vector2(400, 400))
		mr.set("_close_ignore_stale_left_down", false)


func _set_zoom(z: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	cam.zoom = Vector2(z, z)
	var mr := _map_renderer()
	if mr != null and mr.has_method("_sync_unit_counter_visibility"):
		mr.call("_sync_unit_counter_visibility", z)


func _pick_ger_land_fid() -> String:
	var lm := _leader_manager()
	if lm == null:
		return ""
	if lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", GER_TAG)
	if "formations" in lm:
		for fid_v in lm.formations.keys():
			var f: Object = lm.formations[fid_v]
			if f == null:
				continue
			var tag := str(f.get("country_tag")).strip_edges().to_upper()
			var ft := str(f.get("formation_type")) if "formation_type" in f else ""
			if tag != GER_TAG:
				continue
			if ft != "" and ft != "division":
				continue
			return str(fid_v)
	return ""


func _press(pos: Vector2) -> void:
	_warp(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.push_input(ev, true)
	else:
		Input.parse_input_event(ev)
	_last_mouse = pos


func _release(pos: Vector2) -> void:
	_warp(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	ev.global_position = pos
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.push_input(ev, true)
	else:
		Input.parse_input_event(ev)
	_last_mouse = pos


func _motion(pos: Vector2, mask: int) -> void:
	_warp(pos)
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = pos - _last_mouse
	ev.button_mask = mask
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.push_input(ev, true)
	else:
		Input.parse_input_event(ev)
	_last_mouse = pos


func _warp(pos: Vector2) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.warp_mouse(Vector2i(int(round(pos.x)), int(round(pos.y))))
	var win: Window = root if root is Window else null
	if win != null:
		win.warp_mouse(pos)


func _write_clicks() -> void:
	var md := "# CLOSE-1 windowed xvfb 1280x740\n\n"
	md += "GER · Europe Home · world_accurate. NOT live Play.\n\n"
	md += "first_move %d/%d · first_edge %d/%d\n\n" % [_first_move_ok, _first_move_n, _edge_ok, _edge_n]
	md += "| # | zoom | close | steps | move_d | first_move | edge_dy | first_edge |\n"
	md += "|---|---|---|---|---|---|---|---|\n"
	for row in _rows:
		md += "%s\n" % row
	var path := "%s/CLICKS.md" % _out_dir
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	var ev_dir := "docs/evidence/close1"
	DirAccess.make_dir_recursive_absolute(ev_dir)
	var ev := FileAccess.open("%s/CLICKS.md" % ev_dir, FileAccess.WRITE)
	if ev != null:
		ev.store_string(md)
		ev.close()
	_log("EOA_CLOSE1_LIVE who=clicks first_move=%d/%d first_edge=%d/%d" % [_first_move_ok, _first_move_n, _edge_ok, _edge_n])


func _go_settle(next_phase: int) -> void:
	_after_settle = next_phase
	_settle_left = SETTLE_FRAMES
	_phase = Phase.SETTLE


func _force_viewport() -> void:
	var want := Vector2i(VIEW_W, VIEW_H)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(want)
	if root is Window:
		var w: Window = root as Window
		w.size = want
		w.min_size = want
		w.max_size = want
		w.content_scale_size = want
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.size = want


func _force_player_ger() -> void:
	var lm := _leader_manager()
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", GER_TAG)


func _player_tag() -> String:
	var lm := _leader_manager()
	if lm != null and lm.has_method("get_player_country_tag"):
		return str(lm.call("get_player_country_tag"))
	return "?"


func _pause_clock() -> void:
	var tm := _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	elif tm != null and "paused" in tm:
		tm.set("paused", true)


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _province_count() < 3000:
		return false
	return _map_renderer() != null and _camera() != null


func _title_has_closed() -> bool:
	var tm := _time_manager()
	if tm != null and tm.has_method("living_title_has_closed"):
		if bool(tm.call("living_title_has_closed")):
			return true
	var scene := current_scene
	if scene != null and bool(scene.get_meta("eoa_living_title_closed", false)):
		return true
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	if boot == null and _province_count() >= 3000:
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed >= 8:
			return true
	return false


func _dismiss_title_if_needed() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if bool(boot.get("_closed")):
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	if not bool(boot.get("_closed")) and boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")
	var tm: Node = _time_manager()
	if tm != null and tm.has_method("mark_living_title_closed") and bool(boot.get("_closed")):
		tm.call("mark_living_title_closed")


func _province_count() -> int:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam: Node = mr.get_node_or_null("MapCamera")
		if cam is Camera2D:
			return cam as Camera2D
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		return vp.get_camera_2d()
	return null


func _map_manager() -> Node:
	if root != null:
		var n: Node = root.get_node_or_null("MapManager")
		if n != null:
			return n
	return _find_named("MapManager")


func _leader_manager() -> Node:
	if root != null:
		var n: Node = root.get_node_or_null("LeaderManager")
		if n != null:
			return n
	return _find_named("LeaderManager")


func _time_manager() -> Node:
	if root != null:
		var n: Node = root.get_node_or_null("TimeManager")
		if n != null:
			return n
	return _find_named("TimeManager")


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	if not ok:
		for r in _fail_reasons:
			print("  [FAIL] WindowedClose1CardCloseDragCheck: ", r)
	print(
		"WindowedClose1CardCloseDragCheck: first_move=%d/%d first_edge=%d/%d" % [
			_first_move_ok, _first_move_n, _edge_ok, _edge_n
		]
	)
	print("WindowedClose1CardCloseDragCheck: ", "PASS" if ok else "FAIL", " (failures=", _fail_reasons.size(), ")")
	print("WindowedClose1CardCloseDragCheck: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
