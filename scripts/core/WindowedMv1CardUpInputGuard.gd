extends SceneTree

## WINDOWED MV-1 card-up real-input guard. xvfb / llvmpipe is NOT live Play.
## Selects the unit by InputEventMouseButton press+release at the counter
## screen position (normal `_input` / `_unhandled_input`). Never assigns
## `selected_formation_id`. Asserts: card visible; Bonn→Leverkusen hover
## shows preview line + chip; still-click release is not dragged; commit
## via `_try_move_selected_unit_to_province` / enqueue; preview==commit;
## a real drag still pans and does not commit.
##
##   tools/eoa_mv1_card_up_input_guard.sh

const KOELN := 710417
const BONN := 710416
const LEV := 710418
const NEUSS := 710413
const MID_ZOOM := 2.80
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 24
const LEFTOVER_FRAMES := 22
const RSS_LIMIT_MB := 3000
const DRAG_PX := 24.0
const NAME_A := "GER MV-1 A"
const NAME_B := "GER MV-1 B"

enum Phase {
	WAIT_MAP,
	SETTLE,
	PARK,
	INSPECTOR,
	WAIT_INSPECTOR,
	CLOSE_INSPECTOR,
	WAIT_CLOSE_INSPECTOR,
	SELECT,
	WAIT_SELECT,
	HOVER,
	WAIT_HOVER,
	OPENFIGHT,
	WAIT_OPENFIGHT,
	CLOSE_FIGHT,
	WAIT_CLOSE_FIGHT,
	RESELECT,
	WAIT_RESELECT,
	SWITCH_B,
	WAIT_SWITCH,
	RESELECT_A,
	WAIT_RESELECT_A,
	CHIP_DISK,
	WAIT_CHIP_DISK,
	COMMIT,
	WAIT_COMMIT,
	UNLOCK_DRAG,
	DRAG_PRESS,
	DRAG_MOVE,
	DRAG_RELEASE,
	WAIT_DRAG,
	DRAG2_PRESS,
	DRAG2_OUT,
	DRAG2_BACK,
	DRAG2_RELEASE,
	WAIT_DRAG2,
	STILL_CLICK,
	WAIT_STILL,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.PARK
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _rss_start_kb: int = 0
var _rss_peak_kb: int = 0
var _fid: String = ""
var _fid_b: String = ""
var _chip_text: String = ""
var _hover_ok: bool = false
var _commit_ok: bool = false
var _drag_ok: bool = false
var _switch_ok: bool = false
var _inspector_ok: bool = false
var _openfight_ok: bool = false
var _chip_disk_ok: bool = false
var _drag2_ok: bool = false
var _stills_ok: bool = false
var _preview_path: Array = []
var _preview_days: int = -1
var _still_left: int = 0
var _still_pass: int = 0
var _march_dest_before_drag2: int = -1
var _inspector_before_drag2: bool = false
var _cam_pos: Vector2 = Vector2.ZERO
var _cam_zoom: float = MID_ZOOM
var _cam_before_drag: Vector2 = Vector2.ZERO
var _last_mouse: Vector2 = Vector2.ZERO
var _mv_scr: Script = null
var _camera_unlocked: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_dest: Vector2 = Vector2.ZERO


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedMv1CardUpInputGuard: DisplayServer=%s (xvfb NOT live Play / NOT Vulkan product)" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_out_dir = OS.get_environment("EOA_MV1_CARD_UP_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-mv1-card-up"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/mv1-preview")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_rss_start_kb = _rss_kb()
	_rss_peak_kb = _rss_start_kb
	_mv_scr = load("res://scripts/formations/FormationMovement.gd") as Script
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.boot out=%s rss_kb=%d (NOT live Play)" % [_out_dir, _rss_start_kb])
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail_reasons.append("scene_load_%d" % err)
		_finish(false)
		return
	_phase = Phase.WAIT_MAP
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	_note_rss()
	match _phase:
		Phase.WAIT_MAP:
			_tick_wait_map()
		Phase.SETTLE:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.PARK:
			_do_park()
		Phase.INSPECTOR:
			_do_inspector()
		Phase.WAIT_INSPECTOR:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_check_inspector()
		Phase.CLOSE_INSPECTOR:
			_do_close_panel("inspector")
		Phase.WAIT_CLOSE_INSPECTOR:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_check_close_then_select()
		Phase.SELECT:
			_do_select()
		Phase.WAIT_SELECT:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_check_select_then_hover()
		Phase.HOVER:
			_do_hover()
		Phase.WAIT_HOVER:
			_settle_left -= 1
			if _settle_left <= 0:
				_check_hover_then_openfight()
		Phase.OPENFIGHT:
			_do_openfight()
		Phase.WAIT_OPENFIGHT:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_check_openfight()
		Phase.CLOSE_FIGHT:
			_do_close_panel("open_fight")
		Phase.WAIT_CLOSE_FIGHT:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_check_close_fight_then_reselect()
		Phase.RESELECT:
			_do_select()
		Phase.WAIT_RESELECT:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_check_reselect_then_switch()
		Phase.SWITCH_B:
			_do_switch_b()
		Phase.WAIT_SWITCH:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_check_switch_then_reselect_a()
		Phase.RESELECT_A:
			_do_reselect_a()
		Phase.WAIT_RESELECT_A:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_check_reselect_a_then_chip()
		Phase.CHIP_DISK:
			_do_chip_disk()
		Phase.WAIT_CHIP_DISK:
			_settle_left -= 1
			if _settle_left <= 0:
				_check_chip_disk_then_commit()
		Phase.COMMIT:
			_do_commit()
		Phase.WAIT_COMMIT:
			_settle_left -= 1
			if _settle_left <= 0:
				_check_commit_then_drag()
		Phase.UNLOCK_DRAG:
			_do_unlock_drag()
		Phase.DRAG_PRESS:
			if _settle_left > 0:
				_settle_left -= 1
			else:
				_do_drag_press()
		Phase.DRAG_MOVE:
			_settle_left -= 1
			if _settle_left <= 0:
				_do_drag_move()
		Phase.DRAG_RELEASE:
			_settle_left -= 1
			if _settle_left <= 0:
				_do_drag_release()
		Phase.WAIT_DRAG:
			_settle_left -= 1
			if _settle_left <= 0:
				_check_drag_and_finish()
		Phase.DRAG2_PRESS:
			if _settle_left > 0:
				_settle_left -= 1
			else:
				_do_drag2_press()
		Phase.DRAG2_OUT:
			_settle_left -= 1
			if _settle_left <= 0:
				_do_drag2_out()
		Phase.DRAG2_BACK:
			_settle_left -= 1
			if _settle_left <= 0:
				_do_drag2_back()
		Phase.DRAG2_RELEASE:
			_settle_left -= 1
			if _settle_left <= 0:
				_do_drag2_release()
		Phase.WAIT_DRAG2:
			_settle_left -= 1
			if _settle_left <= 0:
				_check_drag2_then_stills()
		Phase.STILL_CLICK:
			_do_still_repeat()
		Phase.WAIT_STILL:
			_settle_left -= 1
			if _settle_left <= 0:
				_check_still_repeat()
		Phase.DONE:
			pass


func _go_settle(next_phase: int, frames: int = SETTLE_FRAMES) -> void:
	_after_settle = next_phase
	_settle_left = frames
	_phase = Phase.SETTLE


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail_reasons.append("map_timeout")
		_finish(false)
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.wait_map elapsed=%d closed=%s n=%d (NOT live Play)" % [elapsed, str(_title_has_closed()), _province_count()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("mv1_card_ready_msec", 0)) == 0:
		root.set_meta("mv1_card_ready_msec", Time.get_ticks_msec())
		_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.map_ready elapsed=%d n=%d" % [elapsed, _province_count()])
		return
	if Time.get_ticks_msec() - int(root.get_meta("mv1_card_ready_msec", 0)) < 2000:
		return
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.frame_start elapsed=%d (NOT live Play)" % elapsed)
	_hide_title_overlay()
	_pause_clock_only()
	_lock_camera_keep_process()
	_frame_over_koln(MID_ZOOM)
	_go_settle(Phase.PARK)


func _do_park() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	_fid = _park_ger_at(BONN, NAME_A)
	_fid_b = _park_ger_at(NEUSS, NAME_B, _fid)
	if _fid.is_empty() or _fid_b.is_empty():
		_fail_reasons.append("no_ger_formation")
		_finish(false)
		return
	if "show_unit_counters" in mr:
		mr.set("show_unit_counters", true)
	if mr.has_method("mv1_rebuild_unit_icons"):
		mr.call("mv1_rebuild_unit_icons")
	elif mr.has_method("_update_unit_icons_for_test"):
		mr.call("_update_unit_icons_for_test")
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.park fid_a=%s fid_b=%s (NOT live Play)" % [_fid, _fid_b])
	_go_settle(Phase.INSPECTOR, 18)


func _do_select() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	# Must NOT assign selected_formation_id — click the painted counter.
	var from_reselect: bool = _phase == Phase.RESELECT
	var already := ""
	if "selected_formation_id" in mr:
		already = str(mr.get("selected_formation_id"))
	if not already.is_empty() and not from_reselect:
		_fail_reasons.append("selected_already_set_before_click")
		_finish(false)
		return
	var pos: Vector2 = mr.call("mv1_formation_screen_pos", _fid) as Vector2
	if pos == Vector2.ZERO:
		_fail_reasons.append("unit_counter_screen_pos_missing")
		_finish(false)
		return
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.select_click pos=%.1f,%.1f fid=%s (NOT live Play)" % [pos.x, pos.y, _fid])
	_click_still(pos)
	_phase = Phase.WAIT_RESELECT if from_reselect else Phase.WAIT_SELECT
	_settle_left = LEFTOVER_FRAMES


func _check_select_then_hover() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var selected := ""
	if "selected_formation_id" in mr:
		selected = str(mr.get("selected_formation_id"))
	var card_up := false
	if mr.has_method("mv1_unit_card_is_visible"):
		card_up = bool(mr.call("mv1_unit_card_is_visible"))
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	var ui_names := ""
	var ui_node: Node = mr.get_node_or_null("UI")
	if ui_node != null:
		var bits: PackedStringArray = PackedStringArray()
		for c in ui_node.get_children():
			var vis := false
			if c is CanvasItem:
				vis = (c as CanvasItem).visible
			bits.append("%s vis=%s" % [str(c.name), str(vis)])
		ui_names = ",".join(bits)
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.select_result selected=%s card=%s rel=%s ui=%s (NOT live Play)"
		% [selected, str(card_up), str(rel), ui_names]
	)
	if selected.is_empty():
		_fail_reasons.append("select_did_not_arm_formation")
	if selected != _fid and not selected.is_empty():
		_fail_reasons.append("select_armed_wrong_fid")
	if not card_up:
		_fail_reasons.append("unit_card_not_visible")
	if bool(rel.get("dragged", false)):
		_fail_reasons.append("select_click_classified_dragged")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_phase = Phase.HOVER


func _do_hover() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var lev: Vector2 = _march_dest_screen(mr)
	if lev == Vector2.ZERO:
		_fail_reasons.append("lev_screen_pos_missing")
		_finish(false)
		return
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.hover_move lev=%.1f,%.1f (NOT live Play)" % [lev.x, lev.y])
	_move_mouse(lev)
	_phase = Phase.WAIT_HOVER
	_settle_left = 20


func _check_hover_then_openfight() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	if not mr.has_method("mv1_preview_report"):
		_fail_reasons.append("no_mv1_preview_report")
		_finish(false)
		return
	var report: Dictionary = mr.call("mv1_preview_report") as Dictionary
	_chip_text = str(report.get("chip_text", ""))
	_hover_ok = bool(report.get("line_visible", false)) and int(report.get("point_n", 0)) >= 2
	_preview_days = int(report.get("calendar_days", -1))
	if report.has("cache_dest"):
		pass
	_preview_path = _preview_path_from_cache(mr)
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.hover report=%s (NOT live Play)" % str(report))
	if not _hover_ok:
		_fail_reasons.append("preview_line_missing_on_card_up_hover")
	if not bool(report.get("chip_visible", false)):
		_fail_reasons.append("preview_chip_missing_on_card_up_hover")
	if "2 hops" not in _chip_text or "arrives in 3 days" not in _chip_text or "Leverkusen" not in _chip_text:
		_fail_reasons.append("chip_text_unexpected")
	if not mr.has_method("mv1_unit_card_is_visible") or not bool(mr.call("mv1_unit_card_is_visible")):
		_fail_reasons.append("unit_card_lost_on_hover")
	_capture("mv1_card_up_hover_chip_NOT_live_play")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_phase = Phase.OPENFIGHT


func _preview_path_from_cache(mr: Node) -> Array:
	if mr == null:
		return []
	if "_march_preview_cache" in mr:
		var cache: Variant = mr.get("_march_preview_cache")
		if cache is Dictionary:
			return (cache as Dictionary).get("path", []) as Array
	return []


func _do_commit() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var lev: Vector2 = _march_dest_screen(mr)
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.commit_click lev=%.1f,%.1f (NOT live Play)" % [lev.x, lev.y])
	_click_still(lev)
	_phase = Phase.WAIT_COMMIT
	_settle_left = LEFTOVER_FRAMES


func _check_commit_then_drag() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	var dragged := bool(rel.get("dragged", true))
	if mr.has_method("mv1_last_left_release_was_drag"):
		dragged = bool(mr.call("mv1_last_left_release_was_drag"))
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.commit_release rel=%s (NOT live Play)" % str(rel))
	if dragged:
		_fail_reasons.append("commit_click_classified_dragged")
	if _mv_scr == null:
		_fail_reasons.append("formation_movement_script_missing")
		_finish(false)
		return
	var has: bool = bool(_mv_scr.call("has_march", _fid))
	var order: Dictionary = _mv_scr.call("get_march", _fid) as Dictionary
	var dest := int(order.get("dest_id", -1))
	var days := int(order.get("calendar_days", -1))
	if days <= 0 and not order.is_empty() and _mv_scr != null:
		var eta: float = float(_mv_scr.call("remaining_eta_days", order))
		days = int(_mv_scr.call("calendar_days", eta))
	var path: Array = order.get("path", []) as Array
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.commit has=%s dest=%d days=%d path=%s preview_days=%d (NOT live Play)"
		% [str(has), dest, days, str(path), _preview_days]
	)
	if not has:
		_fail_reasons.append("has_march_false_after_commit")
	if dest != LEV:
		_fail_reasons.append("commit_dest_not_leverkusen")
	if _preview_days > 0 and days > 0 and days != _preview_days:
		_fail_reasons.append("commit_days_ne_preview")
	if not _preview_path.is_empty() and not path.is_empty() and str(path) != str(_preview_path):
		_fail_reasons.append("commit_path_ne_preview")
	_commit_ok = has and dest == LEV and not dragged
	_capture("mv1_card_up_commit_NOT_live_play")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_phase = Phase.UNLOCK_DRAG


func _do_unlock_drag() -> void:
	var mr := _map_renderer()
	if mr != null:
		if mr.has_method("_unlock_close_camera"):
			mr.call("_unlock_close_camera")
		mr.set("_close_camera_locked", false)
		mr.set("_hold_camera_until_msec", 0)
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", false)
	_camera_unlocked = true
	var cam := _camera()
	if cam != null:
		_cam_before_drag = cam.global_position
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.unlock_drag cam=%.1f,%.1f (NOT live Play)" % [_cam_before_drag.x, _cam_before_drag.y])
	_phase = Phase.DRAG_PRESS
	_settle_left = 8


func _do_drag_press() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	_drag_start = mr.call("mv1_province_screen_pos", KOELN) as Vector2
	if _drag_start == Vector2.ZERO:
		_drag_start = Vector2(900, 400)
	_drag_dest = _drag_start + Vector2(-DRAG_PX, -DRAG_PX)
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.drag_press start=%.1f,%.1f dest=%.1f,%.1f (NOT live Play)"
		% [_drag_start.x, _drag_start.y, _drag_dest.x, _drag_dest.y]
	)
	_press_at(_drag_start)
	_phase = Phase.DRAG_MOVE
	_settle_left = 3


func _do_drag_move() -> void:
	_move_mouse(_drag_dest)
	_phase = Phase.DRAG_RELEASE
	_settle_left = 4


func _do_drag_release() -> void:
	_release_at(_drag_dest)
	_phase = Phase.WAIT_DRAG
	_settle_left = LEFTOVER_FRAMES


func _check_drag_and_finish() -> void:
	var mr := _map_renderer()
	var cam := _camera()
	var cam_after := Vector2.ZERO
	if cam != null:
		cam_after = cam.global_position
	var moved := cam_after.distance_to(_cam_before_drag)
	var rel: Dictionary = {}
	if mr != null and mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	var dragged := true
	if mr != null and mr.has_method("mv1_last_left_release_was_drag"):
		dragged = bool(mr.call("mv1_last_left_release_was_drag"))
	var dest := -1
	if _mv_scr != null:
		var order: Dictionary = _mv_scr.call("get_march", _fid) as Dictionary
		dest = int(order.get("dest_id", -1))
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.drag_result moved=%.1f dragged=%s dest=%d rel=%s (NOT live Play)"
		% [moved, str(dragged), dest, str(rel)]
	)
	if moved < 2.0:
		_fail_reasons.append("drag_did_not_pan")
	if not dragged:
		_fail_reasons.append("drag_not_classified_dragged")
	if dest != LEV:
		_fail_reasons.append("drag_changed_march_dest")
	_drag_ok = moved >= 2.0 and dragged and dest == LEV
	_capture("mv1_card_up_drag_pan_NOT_live_play")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_phase = Phase.DRAG2_PRESS
	_settle_left = 8


func _march_dest_screen(mr: Node) -> Vector2:
	if mr != null and mr.has_method("mv1_screen_pos_for_march_dest"):
		var picked: Vector2 = mr.call("mv1_screen_pos_for_march_dest", LEV) as Vector2
		if picked != Vector2.ZERO:
			return picked
	if mr != null and mr.has_method("mv1_province_screen_pos"):
		return mr.call("mv1_province_screen_pos", LEV) as Vector2
	return Vector2.ZERO


func _click_still(pos: Vector2, ctrl: bool = false, alt: bool = false) -> void:
	_press_at(pos, ctrl, alt)
	# Same-position release after a couple of idle frames (still click).
	var hold := pos
	call_deferred("_click_still_release", hold, ctrl, alt)


func _click_still_release(pos: Vector2, ctrl: bool = false, alt: bool = false) -> void:
	_release_at(pos, ctrl, alt)


func _press_at(pos: Vector2, ctrl: bool = false, alt: bool = false) -> void:
	_warp(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	Input.parse_input_event(ev)
	var vp := root.get_viewport()
	if vp != null:
		vp.push_input(ev, true)
	_last_mouse = pos


func _release_at(pos: Vector2, ctrl: bool = false, alt: bool = false) -> void:
	_warp(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	ev.global_position = pos
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	Input.parse_input_event(ev)
	var vp := root.get_viewport()
	if vp != null:
		vp.push_input(ev, true)
	_last_mouse = pos


func _move_mouse(pos: Vector2) -> void:
	_warp(pos)
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = pos - _last_mouse
	Input.parse_input_event(ev)
	var vp := root.get_viewport()
	if vp != null:
		vp.push_input(ev, true)
	_last_mouse = pos


func _warp(pos: Vector2) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.warp_mouse(Vector2i(int(round(pos.x)), int(round(pos.y))))


func _do_inspector() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var pos: Vector2 = _march_dest_screen(mr)
	if pos == Vector2.ZERO:
		pos = mr.call("mv1_province_screen_pos", LEV) as Vector2
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.inspector_click pos=%.1f,%.1f (NOT live Play)" % [pos.x, pos.y])
	# Alt prefers hex inspector over the nearest-land fallback (first-select).
	_click_still(pos, false, true)
	_phase = Phase.WAIT_INSPECTOR
	_settle_left = LEFTOVER_FRAMES


func _check_inspector() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var vis := false
	if mr.has_method("mv1_inspector_is_visible"):
		vis = bool(mr.call("mv1_inspector_is_visible"))
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.inspector vis=%s rel=%s (NOT live Play)" % [str(vis), str(rel)])
	if not vis:
		_fail_reasons.append("inspector_not_visible")
		_finish(false)
		return
	if bool(rel.get("dragged", false)):
		_fail_reasons.append("inspector_click_classified_dragged")
		_finish(false)
		return
	_inspector_ok = true
	_phase = Phase.CLOSE_INSPECTOR


func _do_close_panel(kind: String) -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var pos := Vector2.ZERO
	if mr.has_method("mv1_close_button_screen_pos"):
		pos = mr.call("mv1_close_button_screen_pos") as Vector2
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.close_%s pos=%.1f,%.1f (NOT live Play)" % [kind, pos.x, pos.y])
	if pos == Vector2.ZERO:
		_fail_reasons.append("close_button_missing_%s" % kind)
		_finish(false)
		return
	_click_still(pos)
	if kind == "inspector":
		_phase = Phase.WAIT_CLOSE_INSPECTOR
	else:
		_phase = Phase.WAIT_CLOSE_FIGHT
	_settle_left = LEFTOVER_FRAMES


func _check_close_then_select() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var vis := true
	if mr.has_method("mv1_inspector_is_visible"):
		vis = bool(mr.call("mv1_inspector_is_visible"))
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.close_inspector vis=%s rel=%s (NOT live Play)" % [str(vis), str(rel)])
	if vis:
		_fail_reasons.append("inspector_still_visible_after_close")
	if bool(rel.get("dragged", false)):
		_fail_reasons.append("inspector_close_classified_dragged")
	if bool(rel.get("ready", true)) == false:
		_fail_reasons.append("ready_false_after_inspector_close")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_phase = Phase.SELECT


func _do_openfight() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var pos: Vector2 = mr.call("mv1_province_screen_pos", KOELN) as Vector2
	if pos == Vector2.ZERO:
		pos = Vector2(820, 380)
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.openfight_ctrl_click pos=%.1f,%.1f (NOT live Play)" % [pos.x, pos.y])
	_click_still(pos, true, false)
	_phase = Phase.WAIT_OPENFIGHT
	_settle_left = LEFTOVER_FRAMES


func _check_openfight() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var vis := false
	if mr.has_method("mv1_open_fight_is_visible"):
		vis = bool(mr.call("mv1_open_fight_is_visible"))
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.openfight vis=%s rel=%s (NOT live Play)" % [str(vis), str(rel)])
	if not vis:
		_fail_reasons.append("open_fight_not_visible")
		_finish(false)
		return
	_openfight_ok = true
	_phase = Phase.CLOSE_FIGHT


func _check_close_fight_then_reselect() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var vis := true
	if mr.has_method("mv1_open_fight_is_visible"):
		vis = bool(mr.call("mv1_open_fight_is_visible"))
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.close_fight vis=%s rel=%s (NOT live Play)" % [str(vis), str(rel)])
	if vis:
		_fail_reasons.append("open_fight_still_visible_after_close")
	if bool(rel.get("dragged", false)):
		_fail_reasons.append("open_fight_close_classified_dragged")
	if bool(rel.get("ready", true)) == false:
		_fail_reasons.append("ready_false_after_open_fight_close")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_phase = Phase.RESELECT


func _check_reselect_then_switch() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var selected := ""
	if "selected_formation_id" in mr:
		selected = str(mr.get("selected_formation_id"))
	var card_up := false
	if mr.has_method("mv1_unit_card_is_visible"):
		card_up = bool(mr.call("mv1_unit_card_is_visible"))
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.reselect selected=%s card=%s rel=%s (NOT live Play)"
		% [selected, str(card_up), str(rel)]
	)
	if selected != _fid:
		_fail_reasons.append("reselect_after_open_fight_failed")
	if not card_up:
		_fail_reasons.append("card_not_visible_after_reselect")
	if bool(rel.get("dragged", false)):
		_fail_reasons.append("reselect_classified_dragged")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_phase = Phase.SWITCH_B


func _do_switch_b() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var pos: Vector2 = mr.call("mv1_formation_screen_pos", _fid_b) as Vector2
	if pos == Vector2.ZERO:
		_fail_reasons.append("unit_b_screen_pos_missing")
		_finish(false)
		return
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.switch_b pos=%.1f,%.1f fid_b=%s (NOT live Play)" % [pos.x, pos.y, _fid_b])
	_click_still(pos)
	_phase = Phase.WAIT_SWITCH
	_settle_left = LEFTOVER_FRAMES


func _check_switch_then_reselect_a() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var selected := ""
	if "selected_formation_id" in mr:
		selected = str(mr.get("selected_formation_id"))
	var title := ""
	if mr.has_method("mv1_unit_card_title_text"):
		title = str(mr.call("mv1_unit_card_title_text"))
	var has_a := false
	if _mv_scr != null:
		has_a = bool(_mv_scr.call("has_march", _fid))
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.switch_result selected=%s title=%s has_a=%s rel=%s (NOT live Play)"
		% [selected, title, str(has_a), str(rel)]
	)
	if selected != _fid_b:
		_fail_reasons.append("plain_click_did_not_switch_to_b")
	if NAME_B not in title:
		_fail_reasons.append("card_title_not_unit_b")
	if has_a:
		_fail_reasons.append("switch_queued_march_for_a")
	if bool(rel.get("dragged", false)):
		_fail_reasons.append("switch_click_classified_dragged")
	_capture("mv1_card_switched_to_unit_b_NOT_live_play")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_switch_ok = true
	_phase = Phase.RESELECT_A


func _do_reselect_a() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var pos: Vector2 = mr.call("mv1_formation_screen_pos", _fid) as Vector2
	if pos == Vector2.ZERO:
		_fail_reasons.append("unit_a_screen_pos_missing")
		_finish(false)
		return
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.reselect_a pos=%.1f,%.1f (NOT live Play)" % [pos.x, pos.y])
	_click_still(pos)
	_phase = Phase.WAIT_RESELECT_A
	_settle_left = LEFTOVER_FRAMES


func _check_reselect_a_then_chip() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var selected := ""
	if "selected_formation_id" in mr:
		selected = str(mr.get("selected_formation_id"))
	if selected != _fid:
		_fail_reasons.append("reselect_a_failed")
		_finish(false)
		return
	_phase = Phase.CHIP_DISK


func _do_chip_disk() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var pos := Vector2.ZERO
	if mr.has_method("mv1_screen_pos_in_chip_over_province"):
		pos = mr.call("mv1_screen_pos_in_chip_over_province", _fid, KOELN) as Vector2
	if pos == Vector2.ZERO:
		_fail_reasons.append("chip_disk_point_missing")
		_finish(false)
		return
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.chip_disk pos=%.1f,%.1f (NOT live Play)" % [pos.x, pos.y])
	_click_still(pos)
	_phase = Phase.WAIT_CHIP_DISK
	_settle_left = LEFTOVER_FRAMES


func _check_chip_disk_then_commit() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	var selected := ""
	if "selected_formation_id" in mr:
		selected = str(mr.get("selected_formation_id"))
	var has := false
	var dest := -1
	if _mv_scr != null:
		has = bool(_mv_scr.call("has_march", _fid))
		var order: Dictionary = _mv_scr.call("get_march", _fid) as Dictionary
		dest = int(order.get("dest_id", -1))
	var rel: Dictionary = {}
	if mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.chip_disk_result selected=%s has=%s dest=%d rel=%s (NOT live Play)"
		% [selected, str(has), dest, str(rel)]
	)
	if selected != _fid:
		_fail_reasons.append("chip_disk_rearmed_or_switched")
	if not has or dest != KOELN:
		_fail_reasons.append("chip_disk_did_not_commit_a_to_koln")
	if bool(rel.get("dragged", false)):
		_fail_reasons.append("chip_disk_classified_dragged")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_chip_disk_ok = true
	_phase = Phase.COMMIT


func _do_drag2_press() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	if _mv_scr != null:
		var order: Dictionary = _mv_scr.call("get_march", _fid) as Dictionary
		_march_dest_before_drag2 = int(order.get("dest_id", -1))
	if mr.has_method("mv1_inspector_is_visible"):
		_inspector_before_drag2 = bool(mr.call("mv1_inspector_is_visible"))
	_drag_start = Vector2(900, 420)
	if mr.has_method("mv1_province_screen_pos"):
		var k: Vector2 = mr.call("mv1_province_screen_pos", KOELN) as Vector2
		if k != Vector2.ZERO:
			_drag_start = k + Vector2(80, -60)
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.drag2_press start=%.1f,%.1f (NOT live Play)" % [_drag_start.x, _drag_start.y])
	_press_at(_drag_start)
	_phase = Phase.DRAG2_OUT
	_settle_left = 3


func _do_drag2_out() -> void:
	_move_mouse(_drag_start + Vector2(DRAG_PX, DRAG_PX))
	_phase = Phase.DRAG2_BACK
	_settle_left = 4


func _do_drag2_back() -> void:
	_move_mouse(_drag_start)
	_phase = Phase.DRAG2_RELEASE
	_settle_left = 3


func _do_drag2_release() -> void:
	_release_at(_drag_start)
	_phase = Phase.WAIT_DRAG2
	_settle_left = LEFTOVER_FRAMES


func _check_drag2_then_stills() -> void:
	var mr := _map_renderer()
	var rel: Dictionary = {}
	if mr != null and mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
	var dragged := bool(rel.get("dragged", false))
	if mr != null and mr.has_method("mv1_last_left_release_was_drag"):
		dragged = bool(mr.call("mv1_last_left_release_was_drag"))
	var dest := -1
	if _mv_scr != null:
		var order: Dictionary = _mv_scr.call("get_march", _fid) as Dictionary
		dest = int(order.get("dest_id", -1))
	var inspector_now := false
	if mr != null and mr.has_method("mv1_inspector_is_visible"):
		inspector_now = bool(mr.call("mv1_inspector_is_visible"))
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.drag2_return rel=%s dest=%d inspector=%s (NOT live Play)"
		% [str(rel), dest, str(inspector_now)]
	)
	if not dragged:
		_fail_reasons.append("return_to_origin_drag_not_classified_dragged")
	if dest != _march_dest_before_drag2:
		_fail_reasons.append("return_to_origin_drag_committed_march")
	if inspector_now and not _inspector_before_drag2:
		_fail_reasons.append("return_to_origin_drag_opened_panel")
	if not _fail_reasons.is_empty():
		_finish(false)
		return
	_drag2_ok = true
	_still_left = 5
	_still_pass = 0
	_phase = Phase.STILL_CLICK


func _do_still_repeat() -> void:
	var pos := Vector2(640, 200)
	var mr := _map_renderer()
	if mr != null and mr.has_method("mv1_province_screen_pos"):
		var k: Vector2 = mr.call("mv1_province_screen_pos", KOELN) as Vector2
		if k != Vector2.ZERO:
			pos = k + Vector2(-70, 50)
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.still_repeat n=%d pos=%.1f,%.1f (NOT live Play)" % [_still_pass + 1, pos.x, pos.y])
	_click_still(pos)
	_phase = Phase.WAIT_STILL
	_settle_left = LEFTOVER_FRAMES


func _check_still_repeat() -> void:
	var mr := _map_renderer()
	var dragged := true
	var rel: Dictionary = {}
	if mr != null and mr.has_method("mv1_left_release_report"):
		rel = mr.call("mv1_left_release_report") as Dictionary
		dragged = bool(rel.get("dragged", true))
	if mr != null and mr.has_method("mv1_last_left_release_was_drag"):
		dragged = bool(mr.call("mv1_last_left_release_was_drag"))
	_log(
		"EOA_MV1_CARD_UP_INPUT_GUARD who=guard.still_repeat_result n=%d dragged=%s rel=%s (NOT live Play)"
		% [_still_pass + 1, str(dragged), str(rel)]
	)
	if dragged:
		_fail_reasons.append("still_click_%d_after_drag_latched" % (_still_pass + 1))
		_finish(false)
		return
	_still_pass += 1
	_still_left -= 1
	if _still_left > 0:
		_phase = Phase.STILL_CLICK
		return
	_stills_ok = true
	_finish(_fail_reasons.is_empty())


func _park_ger_at(pid: int, unit_name: String, skip_fid: String = "") -> String:
	var lm := root.get_node_or_null("LeaderManager")
	if lm == null:
		return ""
	if lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var picked := ""
	if "formations" in lm:
		for fid_v in lm.formations.keys():
			var f: Object = lm.formations[fid_v]
			if f == null:
				continue
			var tag := str(f.get("country_tag")).strip_edges().to_upper()
			var ft := str(f.get("formation_type")) if "formation_type" in f else ""
			if tag != "GER":
				continue
			if ft != "" and ft != "division":
				continue
			var fid_s := str(fid_v)
			if fid_s == skip_fid:
				continue
			f.set("stationed_province_id", pid)
			f.set("name", unit_name)
			picked = fid_s
			break
	if picked.is_empty():
		var scr: Script = load("res://scripts/formations/Formation.gd") as Script
		if scr == null:
			return ""
		var f2: Object = scr.new()
		if f2 == null:
			return ""
		picked = "mv1_card_up_%s" % unit_name.replace(" ", "_")
		f2.set("formation_id", picked)
		f2.set("country_tag", "GER")
		f2.set("formation_type", "division")
		f2.set("design_id", "infantry_1936")
		f2.set("stationed_province_id", pid)
		f2.set("name", unit_name)
		if "formations" in lm:
			lm.formations[picked] = f2
	return picked


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _province_count() < 3000:
		return false
	if _map_renderer() == null:
		return false
	if _camera() == null:
		return false
	return true


func _title_has_closed() -> bool:
	var tm := _time_manager()
	if tm != null and tm.has_method("living_title_has_closed"):
		if bool(tm.call("living_title_has_closed")):
			return true
	var tr := _find_named("TestRunner")
	if tr != null and bool(tr.get_meta("eoa_living_title_closed", false)):
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


func _province_count() -> int:
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _dismiss_title_if_needed() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if bool(boot.get("_closed")):
		_mark_title_closed()
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	if not bool(boot.get("_closed")) and boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")
	if bool(boot.get("_closed")):
		_mark_title_closed()


func _hide_title_overlay() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if "visible" in boot:
		boot.set("visible", false)
	if boot is CanvasItem:
		(boot as CanvasItem).visible = false
	if boot is CanvasLayer:
		(boot as CanvasLayer).visible = false
	if "_closed" in boot:
		boot.set("_closed", true)
	_mark_title_closed()


func _mark_title_closed() -> void:
	var tm := _time_manager()
	if tm != null and tm.has_method("mark_living_title_closed"):
		tm.call("mark_living_title_closed")
	var tr := _find_named("TestRunner")
	if tr != null:
		tr.set_meta("eoa_living_title_closed", true)
	if current_scene != null:
		current_scene.set_meta("eoa_living_title_closed", true)


func _time_manager() -> Node:
	if root != null:
		var tm: Node = root.get_node_or_null("TimeManager")
		if tm != null:
			return tm
	return _find_named("TimeManager")


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _pause_clock_only() -> void:
	var tm := _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	elif tm != null and "paused" in tm:
		tm.set("paused", true)


func _lock_camera_keep_process() -> void:
	# Pin Köln so hover/commit stay on the Rhineland. Do NOT disable
	# MapRenderer process — `_update_spatial_hover` and left-drag pan need it.
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_close_camera_locked", true)
		mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 120000)
	var tr := _find_named("TestRunner")
	if tr != null and tr.has_method("set_process"):
		tr.set_process(false)
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.lock_camera_keep_process (NOT live Play)")


func _ensure_not_live_banner() -> void:
	var existing: Node = _find_named("Mv1NotLivePlayBanner")
	if existing != null:
		if existing is CanvasItem:
			(existing as CanvasItem).visible = true
		return
	var banner := Label.new()
	banner.name = "Mv1NotLivePlayBanner"
	banner.text = "xvfb / llvmpipe — NOT live Play (not Vulkan product)"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_font_size_override("font_size", 18)
	banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35, 1.0))
	banner.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	banner.add_theme_constant_override("shadow_offset_x", 1)
	banner.add_theme_constant_override("shadow_offset_y", 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.02, 0.82)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	banner.add_theme_stylebox_override("normal", sb)
	banner.position = Vector2(16, 56)
	banner.z_index = 80
	var host: Node = root
	if current_scene != null:
		host = current_scene
	host.add_child(banner)


func _frame_over_koln(zoom: float) -> void:
	var pos := _koln_world()
	_apply_camera(pos, zoom)
	_ensure_not_live_banner()
	var mr := _map_renderer()
	if mr != null and "info_panel" in mr:
		var ip: Variant = mr.get("info_panel")
		if ip is Control:
			(ip as Control).visible = false
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.frame zoom=%.2f pos=%.1f,%.1f (NOT live Play)" % [zoom, pos.x, pos.y])


func _apply_camera(pos: Vector2, zoom: float) -> void:
	_cam_pos = pos
	_cam_zoom = zoom
	var mr := _map_renderer()
	if mr != null and mr.has_method("lock_pixel_guard_camera"):
		mr.call("lock_pixel_guard_camera", pos, zoom)
		return
	if mr != null:
		mr.set("_close_camera_lock_pos", pos)
		mr.set("_close_camera_lock_zoom", Vector2(zoom, zoom))
		mr.set("_close_camera_locked", true)
	var cam := _camera()
	if cam == null:
		return
	cam.zoom = Vector2(zoom, zoom)
	var parent := cam.get_parent() as Node2D
	if parent != null:
		cam.position = parent.to_local(pos)
	else:
		cam.position = pos
	cam.global_position = pos
	cam.reset_smoothing()
	if cam.has_method("force_update_scroll"):
		cam.call("force_update_scroll")
	cam.enabled = true
	cam.make_current()


func _reassert_camera() -> void:
	if _camera_unlocked:
		return
	if _cam_pos == Vector2.ZERO:
		_apply_camera(_koln_world(), MID_ZOOM)
		return
	_apply_camera(_cam_pos, _cam_zoom)


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam := mr.get_node_or_null("MapCamera") as Camera2D
		if cam != null:
			return cam
	var vp := root.get_viewport()
	if vp != null:
		return vp.get_camera_2d()
	return null


func _koln_world() -> Vector2:
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", KOELN)
		if c != Vector2.ZERO:
			return c
	return Vector2(4254.32 * 1.728, 944.10 * 1.728)


func _capture(name: String) -> void:
	_ensure_not_live_banner()
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	_captures.append(path)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/mv1-preview"):
		img.save_png("/opt/cursor/artifacts/mv1-preview/%s.png" % name)
	_log("EOA_MV1_CARD_UP_INPUT_GUARD who=guard.capture name=%s path=%s (xvfb NOT live Play)" % [name, path])


func _rss_kb() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return 0
	var text := f.get_as_text()
	f.close()
	for line in text.split("\n"):
		if line.begins_with("VmRSS:"):
			var bits: PackedStringArray = line.split(" ", false)
			if bits.size() >= 2:
				return int(bits[1])
	return 0


func _note_rss() -> void:
	var kb := _rss_kb()
	if kb > _rss_peak_kb:
		_rss_peak_kb = kb


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	_note_rss()
	var rss_mb := float(_rss_peak_kb) / 1024.0
	if rss_mb >= float(RSS_LIMIT_MB):
		_fail_reasons.append("rss_over_3gb")
		ok = false
	var result := "PASS" if ok else "FAIL"
	_log(
		"WindowedMv1CardUpInputGuard: RESULT=%s hover=%s commit=%s drag=%s switch=%s inspector=%s fight=%s chip_disk=%s drag2=%s stills=%s chip=%s rss_mb=%.1f peak_kb=%d captures=%s reasons=%s (xvfb NOT live Play)"
		% [
			result,
			str(_hover_ok),
			str(_commit_ok),
			str(_drag_ok),
			str(_switch_ok),
			str(_inspector_ok),
			str(_openfight_ok),
			str(_chip_disk_ok),
			str(_drag2_ok),
			str(_stills_ok),
			_chip_text,
			rss_mb,
			_rss_peak_kb,
			str(_captures),
			str(_fail_reasons),
		]
	)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
