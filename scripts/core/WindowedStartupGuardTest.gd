extends SceneTree

## STARTUP-GUARD windowed diagnostic. NOT a product fix. NOT live Play.
## Observes the real LivingTitleBoot.handle_live_begin path on TestScenario.
## DATA invariants are assertions. PRESENTATION is diagnostic only.
## Never claims live-startup PASS. Never labels a title-visible shot post_dismiss.
##
##   tools/eoa_startup_guard.sh

const VIEW_W := 1280
const VIEW_H := 800
const RESIZE_W := 860
const RESIZE_H := 550
const WAIT_WORLD_SECS := 420
const WAIT_DISMISS_SECS := 45
const SETTLE_FRAMES := 12
const GER_CAPITAL := 710300
const GER_TAG := "GER"
const EXPECT_YEAR := 1936
const EXPECT_PROVINCES_MIN := 3500
const EXPECT_PROVINCES := 3596
const EXPECT_GARRISONS := 575
const LIGHT_BLUE_R := 0.70
const LIGHT_BLUE_G := 0.82
const LIGHT_BLUE_B := 0.92
const LIGHT_BLUE_TOL := 0.18

enum Phase {
	WAIT_WORLD,
	SETTLE,
	PRE_BEGIN,
	INVOKE_BEGIN,
	WAIT_BOOT_CLOSED,
	WAIT_TREE_EXIT,
	POST_DISMISS,
	RESIZE,
	POST_RESIZE,
	FINISH,
	DONE,
}

var _phase: int = Phase.WAIT_WORLD
var _t0_usec: int = 0
var _last_wait_log: int = -1
var _settle_left: int = 0
var _after_settle: int = Phase.PRE_BEGIN
var _out_dir: String = ""
var _fixture_fail: PackedStringArray = PackedStringArray()
var _data_fail: PackedStringArray = PackedStringArray()
var _data_pass: PackedStringArray = PackedStringArray()
var _presentation_notes: PackedStringArray = PackedStringArray()
var _snapshots: Array[Dictionary] = []
var _timing: Dictionary = {}
var _pre_data: Dictionary = {}
var _post_data: Dictionary = {}
var _resize_data: Dictionary = {}
var _begin_out: Dictionary = {}
var _boot_closed_payload: Dictionary = {}
var _boot_closed_usec: int = 0
var _tree_exit_usec: int = 0
var _title_hooked: bool = false
var _begin_invoked: bool = false
var _live_blank: String = "INCOMPLETE"
var _ds_name: String = ""
var _engine_version: String = ""


func _init() -> void:
	_t0_usec = Time.get_ticks_usec()
	_timing["guard_start_usec"] = _t0_usec
	call_deferred("_start")


func _start() -> void:
	_ds_name = DisplayServer.get_name()
	var ver: Dictionary = Engine.get_version_info()
	_engine_version = "%s.%s.%s.%s" % [
		str(ver.get("major", "?")),
		str(ver.get("string", "")),
		str(ver.get("status", "")),
		str(ver.get("hash", "")),
	]
	_log(
		"WindowedStartupGuardTest: DisplayServer=%s engine=%s (NOT live Play / NOT live-startup PASS)"
		% [_ds_name, str(ver.get("string", ""))]
	)
	if _ds_name == "headless":
		_fixture_fail.append("headless_display")
		_live_blank = "INCOMPLETE"
		_finish()
		return
	_out_dir = OS.get_environment("EOA_STARTUP_GUARD_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-startup-guard"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/startup-guard")
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "0")
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "0")
	OS.set_environment("EOA_SKIP_TITLE", "0")
	_force_window(VIEW_W, VIEW_H, false)
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fixture_fail.append("scene_load_%d" % err)
		_finish()
		return
	_phase = Phase.WAIT_WORLD
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	match _phase:
		Phase.WAIT_WORLD:
			_tick_wait_world()
		Phase.SETTLE:
			_tick_settle()
		Phase.PRE_BEGIN:
			_do_pre_begin()
		Phase.INVOKE_BEGIN:
			_do_invoke_begin()
		Phase.WAIT_BOOT_CLOSED:
			_tick_wait_boot_closed()
		Phase.WAIT_TREE_EXIT:
			_tick_wait_tree_exit()
		Phase.POST_DISMISS:
			_do_post_dismiss()
		Phase.RESIZE:
			_do_resize()
		Phase.POST_RESIZE:
			_do_post_resize()
		Phase.FINISH:
			_finish()
		Phase.DONE:
			pass
		_:
			_unhandled_phase(_phase)


func _unhandled_phase(p: int) -> void:
	var _never: int = p
	_fixture_fail.append("unhandled_phase_%d" % p)
	_finish()


func _tick_wait_world() -> void:
	var elapsed := _elapsed_sec()
	if elapsed >= WAIT_WORLD_SECS:
		_fixture_fail.append("world_timeout_s=%d n=%d title=%s" % [
			elapsed, _province_count(), str(_title_state()["in_tree"])
		])
		_finish()
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		_log(
			"EOA_STARTUP_GUARD who=wait_world elapsed=%d n=%d title=%s loading=%s"
			% [elapsed, _province_count(), str(_title_state()["in_tree"]), str(_loading_up())]
		)
	_dismiss_loading_only()
	_force_window(VIEW_W, VIEW_H, false)
	_hook_title_if_needed()
	if not _world_ready_title_up():
		return
	_timing["world_ready_usec"] = Time.get_ticks_usec()
	_log(
		"EOA_STARTUP_GUARD who=world_ready elapsed=%d n=%d title_visible=1"
		% [elapsed, _province_count()]
	)
	_go_settle(Phase.PRE_BEGIN)


func _do_pre_begin() -> void:
	var title := _title_state()
	if not bool(title.get("visible", false)):
		_fixture_fail.append("pre_begin_title_not_visible")
		_finish()
		return
	_timing["pre_begin_usec"] = Time.get_ticks_usec()
	_pre_data = _collect_data_snapshot("pre_begin")
	var snap := _capture_observation("pre_begin", true)
	_snapshots.append(snap)
	_log("EOA_STARTUP_GUARD who=pre_begin title_visible=1 shot=%s" % str(snap.get("png", "")))
	_phase = Phase.INVOKE_BEGIN


func _do_invoke_begin() -> void:
	if _begin_invoked:
		return
	var boot := _title_node()
	if boot == null or not is_instance_valid(boot):
		_fixture_fail.append("begin_no_title")
		_finish()
		return
	if not boot.has_method("handle_live_begin"):
		_fixture_fail.append("begin_no_handle_live_begin")
		_finish()
		return
	_hook_title_if_needed()
	_timing["begin_usec"] = Time.get_ticks_usec()
	_begin_invoked = true
	_log("EOA_STARTUP_GUARD who=invoke_begin path=LivingTitleBoot.handle_live_begin")
	var out: Variant = boot.call("handle_live_begin")
	if out is Dictionary:
		_begin_out = out as Dictionary
	_log("EOA_STARTUP_GUARD who=begin_return %s" % str(_begin_out))
	_phase = Phase.WAIT_BOOT_CLOSED


func _tick_wait_boot_closed() -> void:
	var elapsed := int((Time.get_ticks_usec() - int(_timing.get("begin_usec", _t0_usec))) / 1000000.0)
	if _boot_closed_usec > 0 or _title_closed_flag():
		if _boot_closed_usec == 0:
			_boot_closed_usec = Time.get_ticks_usec()
			_timing["boot_closed_usec"] = _boot_closed_usec
		_log("EOA_STARTUP_GUARD who=boot_closed usec=%d" % _boot_closed_usec)
		_phase = Phase.WAIT_TREE_EXIT
		return
	if elapsed >= WAIT_DISMISS_SECS:
		_fixture_fail.append("boot_closed_timeout")
		_finish()


func _tick_wait_tree_exit() -> void:
	var elapsed := int((Time.get_ticks_usec() - int(_timing.get("begin_usec", _t0_usec))) / 1000000.0)
	var title := _title_state()
	if not bool(title.get("in_tree", false)):
		if _tree_exit_usec == 0:
			_tree_exit_usec = Time.get_ticks_usec()
			_timing["tree_exit_usec"] = _tree_exit_usec
		_timing["overlay_gone_usec"] = Time.get_ticks_usec()
		_log(
			"EOA_STARTUP_GUARD who=overlay_gone tree_exit_usec=%d visible=%s"
			% [_tree_exit_usec, str(title.get("visible", false))]
		)
		_go_settle(Phase.POST_DISMISS)
		return
	if elapsed >= WAIT_DISMISS_SECS:
		_fixture_fail.append("title_still_in_tree_after_begin")
		_presentation_notes.append("title_node_still_in_tree_after_timeout")
		_go_settle(Phase.POST_DISMISS)


func _do_post_dismiss() -> void:
	var title := _title_state()
	var title_vis := bool(title.get("visible", false)) or bool(title.get("in_tree", false))
	_timing["post_dismiss_usec"] = Time.get_ticks_usec()
	_post_data = _collect_data_snapshot("post_dismiss")
	_compare_data(_pre_data, _post_data, "pre_begin→post_dismiss")
	var label := "post_dismiss"
	if title_vis:
		label = "after_begin_title_still_visible"
		_fixture_fail.append("refused_post_dismiss_label_title_still_visible")
		_presentation_notes.append("shot_after_begin_kept_title_visible_label")
	var snap := _capture_observation(label, title_vis)
	_snapshots.append(snap)
	_log(
		"EOA_STARTUP_GUARD who=%s title_visible=%s shot=%s"
		% [label, str(title_vis), str(snap.get("png", ""))]
	)
	_phase = Phase.RESIZE


func _do_resize() -> void:
	_timing["resize_usec"] = Time.get_ticks_usec()
	_force_window(RESIZE_W, RESIZE_H, false)
	_log("EOA_STARTUP_GUARD who=controlled_resize %dx%d (product Begin does not set_size)" % [RESIZE_W, RESIZE_H])
	_go_settle(Phase.POST_RESIZE)


func _do_post_resize() -> void:
	var title := _title_state()
	var title_vis := bool(title.get("visible", false)) or bool(title.get("in_tree", false))
	_timing["post_resize_usec"] = Time.get_ticks_usec()
	_resize_data = _collect_data_snapshot("post_resize")
	_compare_data(_post_data, _resize_data, "post_dismiss→post_resize")
	var label := "post_resize"
	if title_vis:
		label = "post_resize_title_still_visible"
		_presentation_notes.append("resize_shot_title_still_visible")
	var snap := _capture_observation(label, title_vis)
	_snapshots.append(snap)
	_log("EOA_STARTUP_GUARD who=%s shot=%s" % [label, str(snap.get("png", ""))])
	_phase = Phase.FINISH


func _go_settle(next_phase: int) -> void:
	_after_settle = next_phase
	_settle_left = SETTLE_FRAMES
	_phase = Phase.SETTLE


func _tick_settle() -> void:
	_settle_left -= 1
	if _settle_left > 0:
		return
	_phase = _after_settle


func _hook_title_if_needed() -> void:
	if _title_hooked:
		return
	var boot := _title_node()
	if boot == null:
		return
	if boot.has_signal("boot_closed") and not boot.is_connected("boot_closed", _on_boot_closed):
		boot.connect("boot_closed", _on_boot_closed)
	if not boot.tree_exited.is_connected(_on_title_tree_exited):
		boot.tree_exited.connect(_on_title_tree_exited)
	_title_hooked = true
	_log("EOA_STARTUP_GUARD who=hook_title boot_closed+tree_exited")


func _on_boot_closed(result: Dictionary) -> void:
	_boot_closed_payload = result
	_boot_closed_usec = Time.get_ticks_usec()
	_timing["boot_closed_usec"] = _boot_closed_usec
	_log("EOA_STARTUP_GUARD who=signal.boot_closed %s" % str(result))


func _on_title_tree_exited() -> void:
	_tree_exit_usec = Time.get_ticks_usec()
	_timing["tree_exit_usec"] = _tree_exit_usec
	_log("EOA_STARTUP_GUARD who=signal.tree_exited usec=%d" % _tree_exit_usec)


func _world_ready_title_up() -> bool:
	if _province_count() < EXPECT_PROVINCES_MIN:
		return false
	if _map_renderer() == null or _camera() == null:
		return false
	if _loading_up():
		return false
	var title := _title_state()
	if not bool(title.get("in_tree", false)):
		return false
	if bool(title.get("closed", false)):
		return false
	if not bool(title.get("visible", false)):
		return false
	return true


func _title_closed_flag() -> bool:
	var tm := _time_manager()
	if tm != null and tm.has_method("living_title_has_closed") and bool(tm.call("living_title_has_closed")):
		return true
	var scene := current_scene
	if scene != null and bool(scene.get_meta("eoa_living_title_closed", false)):
		return true
	var boot := _title_node()
	if boot != null and bool(boot.get("_closed")):
		return true
	return false


func _collect_data_snapshot(phase: String) -> Dictionary:
	var lm := _leader_manager()
	var tm := _time_manager()
	var mm := _map_manager()
	var pm := _production_manager()
	var date := {}
	if tm != null and tm.has_method("get_current_date"):
		date = tm.call("get_current_date") as Dictionary
	var tag := ""
	if lm != null and lm.has_method("get_player_country_tag"):
		tag = str(lm.call("get_player_country_tag"))
	var forms := _formation_inventory(lm)
	var stock := _stockpile_snapshot(pm)
	var owner_berlin := ""
	if mm != null and mm.has_method("get_province_owner"):
		owner_berlin = str(mm.call("get_province_owner", GER_CAPITAL))
	return {
		"phase": phase,
		"kind": "DATA",
		"player_tag": tag,
		"date": date,
		"province_n": _province_count(),
		"berlin_owner": owner_berlin,
		"formations": forms,
		"stockpile": stock,
		"unit_icon_nodes": _count_named_prefix("DemoUnitIcon_"),
	}


func _compare_data(before: Dictionary, after: Dictionary, label: String) -> void:
	if before.is_empty() or after.is_empty():
		_data_fail.append("%s missing_snapshot" % label)
		return
	_assert_eq(label, "player_tag", str(before.get("player_tag", "")), str(after.get("player_tag", "")))
	var bd: Dictionary = before.get("date", {}) as Dictionary
	var ad: Dictionary = after.get("date", {}) as Dictionary
	_assert_eq(label, "year", str(bd.get("year", "")), str(ad.get("year", "")))
	_assert_eq(label, "month", str(bd.get("month", "")), str(ad.get("month", "")))
	_assert_eq(label, "day", str(bd.get("day", "")), str(ad.get("day", "")))
	_assert_eq(label, "province_n", str(before.get("province_n", -1)), str(after.get("province_n", -1)))
	_assert_eq(label, "berlin_owner", str(before.get("berlin_owner", "")), str(after.get("berlin_owner", "")))
	var bf: Dictionary = before.get("formations", {}) as Dictionary
	var af: Dictionary = after.get("formations", {}) as Dictionary
	_assert_eq(label, "formation_n", str(bf.get("total", -1)), str(af.get("total", -1)))
	_assert_eq(label, "garrison_n", str(bf.get("garrison_1936", -1)), str(af.get("garrison_1936", -1)))
	_assert_eq(label, "identity_fp", str(bf.get("identity_fp", "")), str(af.get("identity_fp", "")))
	var bs: Dictionary = before.get("stockpile", {}) as Dictionary
	var as_: Dictionary = after.get("stockpile", {}) as Dictionary
	_assert_eq(label, "stockpile_fp", str(bs.get("fp", "")), str(as_.get("fp", "")))
	_assert_eq(
		label,
		"unit_icon_nodes",
		str(before.get("unit_icon_nodes", -1)),
		str(after.get("unit_icon_nodes", -1))
	)


func _assert_eq(label: String, field: String, a: String, b: String) -> void:
	if a == b:
		_data_pass.append("%s %s=%s" % [label, field, a])
	else:
		_data_fail.append("%s %s %s→%s" % [label, field, a, b])


func _formation_inventory(lm: Node) -> Dictionary:
	var total := 0
	var garr := 0
	var by_tag: Dictionary = {}
	var ids: PackedStringArray = PackedStringArray()
	if lm == null:
		return {"total": 0, "garrison_1936": 0, "by_tag": {}, "identity_fp": "no_lm"}
	var raw: Variant = lm.get("formations")
	if raw is Dictionary:
		var forms: Dictionary = raw
		for fid_v in forms.keys():
			var f: Object = forms[fid_v] as Object
			if f == null:
				continue
			total += 1
			var tag := str(f.get("country_tag"))
			var pid := int(f.get("stationed_province_id")) if "stationed_province_id" in f else -1
			var fid := str(f.get("formation_id"))
			ids.append("%s:%s:%d" % [tag, fid, pid])
			by_tag[tag] = int(by_tag.get(tag, 0)) + 1
			if bool(f.get_meta("garrison_1936", false)):
				garr += 1
	ids.sort()
	return {
		"total": total,
		"garrison_1936": garr,
		"by_tag": by_tag,
		"identity_fp": str(ids.size()) + ":" + str(hash(ids)),
	}


func _stockpile_snapshot(pm: Node) -> Dictionary:
	var stock: Dictionary = {}
	if pm != null:
		var raw: Variant = pm.get("national_stockpile")
		if raw is Dictionary:
			stock = (raw as Dictionary).duplicate(true)
	var keys: Array = stock.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [str(k), str(stock[k])])
	return {
		"n": stock.size(),
		"keys": keys,
		"values": stock,
		"fp": str(hash(parts)),
	}


func _collect_presentation(phase: String, title_visible: bool) -> Dictionary:
	var cam := _camera()
	var mr := _map_renderer()
	var vp := root.get_viewport() if root != null else null
	var vp_size := Vector2.ZERO
	if vp != null:
		vp_size = vp.get_visible_rect().size
	var win := _window_state()
	var centroid := Vector2.ZERO
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_centroid"):
		centroid = mm.call("get_province_centroid", GER_CAPITAL) as Vector2
	if centroid == Vector2.ZERO and mr != null:
		var cents: Variant = mr.get("province_centroids")
		if cents is Dictionary:
			centroid = (cents as Dictionary).get(GER_CAPITAL, Vector2.ZERO) as Vector2
	var cam_pos := Vector2.ZERO
	var cam_zoom := 0.0
	var vis_rect := Rect2()
	var capital_in_view := false
	if cam != null:
		cam_pos = cam.global_position
		cam_zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
		vis_rect = _visible_world_rect(cam, vp_size)
		capital_in_view = vis_rect.has_point(centroid)
	var mesh := _mesh_visibility(mr, vis_rect)
	var icons := _icon_visibility(mr, vis_rect)
	var chips := _chip_state()
	var underlay := _underlay_state(mr)
	return {
		"phase": phase,
		"kind": "PRESENTATION_DIAGNOSTIC",
		"not_pixel_oracle": true,
		"title_visible": title_visible,
		"window": win,
		"viewport_size": [vp_size.x, vp_size.y],
		"camera_pos": [cam_pos.x, cam_pos.y],
		"camera_zoom": cam_zoom,
		"visible_world_rect": [vis_rect.position.x, vis_rect.position.y, vis_rect.size.x, vis_rect.size.y],
		"ger_capital_pid": GER_CAPITAL,
		"ger_centroid": [centroid.x, centroid.y],
		"capital_in_visible_rect": capital_in_view,
		"mesh": mesh,
		"icons": icons,
		"underlay": underlay,
		"chips": chips,
		"always_on_top": bool(win.get("always_on_top", false)),
	}


func _visible_world_rect(cam: Camera2D, vp_size: Vector2) -> Rect2:
	var z := maxf(absf(cam.zoom.x), 0.01)
	var world := vp_size / z
	var origin := cam.get_screen_center_position() - world * 0.5
	return Rect2(origin, world)


func _mesh_visibility(mr: Node, vis: Rect2) -> Dictionary:
	var total := 0
	var vis_n := 0
	var in_view := 0
	if mr == null:
		return {"nodes": 0, "visible": 0, "in_view": 0, "note": "no_map"}
	var raw: Variant = mr.get("province_nodes")
	var cents: Variant = mr.get("province_centroids")
	var cmap: Dictionary = cents as Dictionary if cents is Dictionary else {}
	if raw is Dictionary:
		for pid_v in (raw as Dictionary).keys():
			var node: Node = (raw as Dictionary)[pid_v] as Node
			if node == null:
				continue
			total += 1
			var shown := true
			if node is CanvasItem:
				shown = (node as CanvasItem).visible
			if shown:
				vis_n += 1
			var c: Vector2 = cmap.get(int(pid_v), Vector2.INF) as Vector2
			if c != Vector2.INF and vis.has_point(c):
				in_view += 1
	return {
		"nodes": total,
		"visible": vis_n,
		"in_view": in_view,
		"note": "counts_are_not_pixels_on_screen",
	}


func _icon_visibility(mr: Node, vis: Rect2) -> Dictionary:
	var total := 0
	var vis_n := 0
	var in_view := 0
	if mr == null:
		return {"nodes": 0, "visible": 0, "in_view": 0}
	for n in mr.find_children("DemoUnitIcon_*", "", true, false):
		if not (n is Node2D):
			continue
		total += 1
		var item := n as Node2D
		if item.visible:
			vis_n += 1
		if vis.has_point(item.global_position):
			in_view += 1
	return {
		"nodes": total,
		"visible": vis_n,
		"in_view": in_view,
		"note": "node_visibility_not_pixel_proof",
	}


func _underlay_state(mr: Node) -> Dictionary:
	if mr == null:
		return {"present": false}
	var bg: Node = null
	if mr.has_node("WorldBackground"):
		bg = mr.get_node("WorldBackground")
	var shown := false
	if bg is CanvasItem:
		shown = (bg as CanvasItem).visible
	return {
		"present": bg != null,
		"visible": shown,
		"full_world_underlay_active": bool(mr.get_meta("full_world_underlay_active", false)),
	}


func _chip_state() -> Dictionary:
	var bar := _top_info_bar()
	var vp_w := 0.0
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp_w = vp.get_visible_rect().size.x
	var stock: Dictionary = {}
	var pm := _production_manager()
	if pm != null:
		var raw: Variant = pm.get("national_stockpile")
		if raw is Dictionary:
			stock = raw
	var chips: Dictionary = {}
	if bar != null:
		var rc: Node = bar.get("_resources_container") as Node
		chips["resources_container_visible"] = rc != null and rc is CanvasItem and (rc as CanvasItem).visible
		for pair in [["steel", "steel_label"], ["aluminum", "aluminum_label"], ["energy", "energy_label"], ["rubber", "rubber_label"], ["fuel", "oil_label"]]:
			var key := str(pair[0])
			var lab_n := str(pair[1])
			var lab: Node = bar.get(lab_n) as Node
			var vis := lab != null and lab is CanvasItem and (lab as CanvasItem).visible
			var txt := str(lab.get("text")) if lab != null else ""
			chips[key] = {
				"visible": vis,
				"text": txt,
				"stockpile": float(stock.get(key, stock.get("oil", 0.0) if key == "fuel" else 0.0)),
			}
	chips["vp_w"] = vp_w
	chips["layout_hides_below_1280"] = vp_w < 1280.0
	chips["note"] = "hidden_chip_is_not_stockpile_zero"
	return chips


func _window_state() -> Dictionary:
	var sz := DisplayServer.window_get_size()
	var mode := DisplayServer.window_get_mode()
	var aot := false
	if DisplayServer.get_window_list().size() > 0:
		var wid: int = int(DisplayServer.get_window_list()[0])
		aot = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, wid)
	return {
		"size": [sz.x, sz.y],
		"mode": _window_mode_name(mode),
		"mode_i": mode,
		"always_on_top": aot,
		"display": _ds_name,
	}


func _window_mode_name(mode: int) -> String:
	match mode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			return "windowed"
		DisplayServer.WINDOW_MODE_MINIMIZED:
			return "minimized"
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return "maximized"
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return "fullscreen"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return "exclusive_fullscreen"
		_:
			return "unknown_%d" % mode


func _capture_observation(label: String, title_visible: bool) -> Dictionary:
	var pres := _collect_presentation(label, title_visible)
	var png := ""
	var img_obs := {}
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		RenderingServer.force_draw()
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null:
				png = "%s/%s.png" % [_out_dir, label]
				img.save_png(png)
				if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/startup-guard"):
					img.save_png("/opt/cursor/artifacts/startup-guard/%s.png" % label)
				img_obs = _describe_image(img, title_visible)
	pres["png"] = png
	pres["image"] = img_obs
	pres["monotonic_usec"] = Time.get_ticks_usec()
	pres["elapsed_usec"] = Time.get_ticks_usec() - _t0_usec
	_write_json("%s/%s.json" % [_out_dir, label], pres)
	return pres


func _describe_image(img: Image, title_visible: bool) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return {"ok": false, "note": "empty_image"}
	var step_x := maxi(1, w / 80)
	var step_y := maxi(1, h / 50)
	var n := 0
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var near_light := 0
	var dark := 0
	var sat := 0
	var x := 0
	while x < w:
		var y := 0
		while y < h:
			var c := img.get_pixel(x, y)
			sr += c.r
			sg += c.g
			sb += c.b
			n += 1
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			if mx - mn > 0.12:
				sat += 1
			if (
				absf(c.r - LIGHT_BLUE_R) <= LIGHT_BLUE_TOL + 0.15
				and absf(c.g - LIGHT_BLUE_G) <= LIGHT_BLUE_TOL
				and absf(c.b - LIGHT_BLUE_B) <= LIGHT_BLUE_TOL
			) or (c.r > 0.55 and c.g > 0.65 and c.b > 0.75):
				near_light += 1
			if (c.r + c.g + c.b) / 3.0 < 0.18:
				dark += 1
			y += step_y
		x += step_x
	var mean := Vector3(sr / maxf(float(n), 1.0), sg / maxf(float(n), 1.0), sb / maxf(float(n), 1.0))
	var light_frac := float(near_light) / maxf(float(n), 1.0)
	var sat_frac := float(sat) / maxf(float(n), 1.0)
	var dark_frac := float(dark) / maxf(float(n), 1.0)
	var looks_uniform_light := light_frac >= 0.55 and sat_frac <= 0.22
	var looks_varied := sat_frac >= 0.20
	var note := "sampled_mean_not_pixel_oracle"
	if title_visible:
		note += ";title_visible_so_not_post_dismiss"
	return {
		"ok": true,
		"w": w,
		"h": h,
		"sample_n": n,
		"mean_rgb": [mean.x, mean.y, mean.z],
		"near_light_frac": light_frac,
		"saturated_frac": sat_frac,
		"dark_frac": dark_frac,
		"looks_uniform_light": looks_uniform_light,
		"looks_varied_color": looks_varied,
		"note": note,
	}


func _classify_live_blank() -> String:
	if _ds_name == "headless":
		return "INCOMPLETE"
	var post: Dictionary = {}
	for s in _snapshots:
		if str(s.get("phase", "")) == "post_dismiss":
			post = s
			break
	if post.is_empty():
		_presentation_notes.append("no_trusted_post_dismiss_shot")
		return "INCOMPLETE"
	if bool(post.get("title_visible", true)):
		_presentation_notes.append("post_dismiss_label_blocked_title_visible")
		return "INCOMPLETE"
	var img: Dictionary = post.get("image", {}) as Dictionary
	if not bool(img.get("ok", false)):
		_presentation_notes.append("post_dismiss_image_missing")
		return "INCOMPLETE"
	var pre: Dictionary = {}
	for s2 in _snapshots:
		if str(s2.get("phase", "")) == "pre_begin":
			pre = s2
			break
	var pre_img: Dictionary = pre.get("image", {}) as Dictionary
	var post_light := bool(img.get("looks_uniform_light", false))
	var pre_varied := bool(pre_img.get("looks_varied_color", false))
	if post_light and pre_varied:
		_presentation_notes.append("post_field_uniform_light_after_varied_setup")
		return "REPRODUCED"
	if post_light:
		_presentation_notes.append("post_field_uniform_light")
		return "REPRODUCED"
	if bool(img.get("looks_varied_color", false)):
		_presentation_notes.append("post_field_still_varied_color")
		return "NOT_REPRODUCED"
	_presentation_notes.append("post_field_inconclusive")
	return "NOT_REPRODUCED"


func _check_absolute_data() -> void:
	var src := _post_data if not _post_data.is_empty() else _pre_data
	if src.is_empty():
		_data_fail.append("no_data_snapshot")
		return
	if str(src.get("player_tag", "")) != GER_TAG:
		_data_fail.append("player_tag=%s want GER" % str(src.get("player_tag", "")))
	else:
		_data_pass.append("player_tag=GER")
	var date: Dictionary = src.get("date", {}) as Dictionary
	if int(date.get("year", 0)) != EXPECT_YEAR:
		_data_fail.append("year=%s want %d" % [str(date.get("year", "")), EXPECT_YEAR])
	else:
		_data_pass.append("year=%d" % EXPECT_YEAR)
	var n := int(src.get("province_n", 0))
	if n < EXPECT_PROVINCES_MIN:
		_data_fail.append("province_n=%d < %d" % [n, EXPECT_PROVINCES_MIN])
	else:
		_data_pass.append("province_n=%d (shipped expect %d)" % [n, EXPECT_PROVINCES])
	if str(src.get("berlin_owner", "")) != GER_TAG:
		_data_fail.append("berlin_owner=%s want GER" % str(src.get("berlin_owner", "")))
	else:
		_data_pass.append("berlin_710300_owner=GER")
	var forms: Dictionary = src.get("formations", {}) as Dictionary
	var garr := int(forms.get("garrison_1936", -1))
	if garr == EXPECT_GARRISONS:
		_data_pass.append("garrison_1936=%d" % garr)
	elif garr < 0:
		_data_fail.append("garrison_1936_unreadable")
	else:
		_presentation_notes.append(
			"garrison_1936_observed=%d shipped_expect=%d (reported, not invented)" % [garr, EXPECT_GARRISONS]
		)
		if garr == 0:
			_data_fail.append("garrison_1936=0")
		else:
			_data_pass.append("garrison_1936_nonzero=%d" % garr)


func _finish() -> void:
	_phase = Phase.DONE
	if process_frame.is_connected(_on_process):
		process_frame.disconnect(_on_process)
	_check_absolute_data()
	_live_blank = _classify_live_blank()
	var data_ok := _data_fail.is_empty() and not _pre_data.is_empty()
	var fixture_ok := _fixture_fail.is_empty()
	var payload := {
		"guard": "WindowedStartupGuardTest",
		"kind": "TEST_ONLY_DIAGNOSTIC",
		"live_startup_pass_claimed": false,
		"base_sha_expected": "7d7a0b856efba61c04364f123b6a7f37c3e310c8",
		"engine_version": _engine_version,
		"display": _ds_name,
		"import_policy": "separate_headless_import_then_one_windowed_run",
		"begin_path": "LivingTitleBoot.handle_live_begin",
		"timing_usec": _timing,
		"timing_note": "monotonic Time.get_ticks_usec since engine start; not wall 4x30s waits",
		"begin_return": _begin_out,
		"boot_closed_payload": _boot_closed_payload,
		"data_pre": _pre_data,
		"data_post": _post_data,
		"data_resize": _resize_data,
		"snapshots": _snapshots,
		"data_pass": _data_pass,
		"data_fail": _data_fail,
		"fixture_fail": _fixture_fail,
		"presentation_notes": _presentation_notes,
		"labels": {
			"DATA_INVARIANT": "PASS" if data_ok else "FAIL",
			"PRESENTATION": "DIAGNOSTIC",
			"LIVE_BLANK": _live_blank,
			"FIXTURE": "PASS" if fixture_ok else "FAIL",
			"LIVE_STARTUP": "NOT_CLAIMED",
		},
		"coverage_gaps": [
			"xvfb_llvmpipe_not_live_desktop",
			"did_not_use_pair_maximized_launch",
			"one_run_only",
			"seed_20fe9063_not_recomputed_here",
		],
	}
	_write_json("%s/startup_guard.json" % _out_dir, payload)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/startup-guard"):
		_write_json("/opt/cursor/artifacts/startup-guard/startup_guard.json", payload)
	_log("EOA_STARTUP_GUARD DATA_INVARIANT=%s" % payload["labels"]["DATA_INVARIANT"])
	_log("EOA_STARTUP_GUARD PRESENTATION=DIAGNOSTIC LIVE_BLANK=%s" % _live_blank)
	_log("EOA_STARTUP_GUARD FIXTURE=%s LIVE_STARTUP=NOT_CLAIMED" % payload["labels"]["FIXTURE"])
	for r in _fixture_fail:
		_log("  [FIXTURE] %s" % r)
	for r in _data_fail:
		_log("  [DATA_FAIL] %s" % r)
	for r in _presentation_notes:
		_log("  [PRESENTATION] %s" % r)
	# Fixture completion is not live-startup PASS. Exit 0 only if the harness
	# finished and labeled shots honestly. DATA/blank stay in JSON.
	var harness_ok := fixture_ok
	print("WindowedStartupGuardTest: RESULT=", "COMPLETED" if harness_ok else "FIXTURE_FAIL")
	print("WindowedStartupGuardTest: LIVE_STARTUP=NOT_CLAIMED LIVE_BLANK=%s" % _live_blank)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if harness_ok else 1)


func _force_window(w: int, h: int, maximize: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if maximize:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(w, h))


func _dismiss_loading_only() -> void:
	var tr := _find_named("TestRunner")
	if tr != null and tr.has_method("_dismiss_loading_screen"):
		tr.call("_dismiss_loading_screen")
	var ls := _find_named("LoadingScreen")
	if ls == null:
		return
	if ls.has_method("hide_and_free"):
		ls.call("hide_and_free")
	elif "visible" in ls:
		ls.set("visible", false)


func _title_state() -> Dictionary:
	var boot := _title_node()
	var in_tree := boot != null and is_instance_valid(boot) and boot.is_inside_tree()
	var closed := false
	var vis := false
	if in_tree:
		closed = bool(boot.get("_closed"))
		vis = true
		if boot is CanvasItem:
			vis = (boot as CanvasItem).visible and not closed
		var panel := boot.find_child("LivingTitlePanel", true, false)
		if panel is CanvasItem:
			vis = vis and (panel as CanvasItem).visible
	return {
		"in_tree": in_tree,
		"closed": closed,
		"visible": vis and in_tree and not closed,
	}


func _title_node() -> Node:
	return _find_named("LivingTitleBoot")


func _loading_up() -> bool:
	var ls := _find_named("LoadingScreen")
	if ls == null:
		return false
	if "visible" in ls and not bool(ls.get("visible")):
		return false
	return true


func _count_named_prefix(prefix: String) -> int:
	var n := 0
	var host := _map_renderer()
	if host == null:
		return 0
	for c in host.find_children(prefix + "*", "", true, false):
		n += 1
	return n


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


func _production_manager() -> Node:
	if root != null:
		var n: Node = root.get_node_or_null("ProductionManager")
		if n != null:
			return n
	return _find_named("ProductionManager")


func _top_info_bar() -> Node:
	return _find_named("TopInfoBar")


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _elapsed_sec() -> int:
	return int((Time.get_ticks_usec() - _t0_usec) / 1000000.0)


func _write_json(path: String, payload: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_log("EOA_STARTUP_GUARD who=write_json_fail path=%s" % path)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
