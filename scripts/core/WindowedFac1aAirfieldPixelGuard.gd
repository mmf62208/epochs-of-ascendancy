extends SceneTree

## WINDOWED FAC-1a airfield-icon pixel guard. xvfb / llvmpipe is NOT live Play.
## Frames Rhineland at operational zoom. Political must show 4 airfield icons
## (non-background pixels at Bonn/Köln/Leverkusen/Neuss). Zoomed-out and F9 hide.
##
##   tools/eoa_fac1a_pixel_guard.sh
##   xvfb-run -a -s "-screen 0 1600x900x24" tools/run_godot.sh \
##     -s res://scripts/core/WindowedFac1aAirfieldPixelGuard.gd

const ESSEN := 710403
const KOELN := 710417
const BONN := 710416
const LEV := 710418
const NEUSS := 710413
const PIDS: Array[int] = [BONN, LEV, KOELN, NEUSS]
const MID_ZOOM := 0.72
const CLOSE_ZOOM := 1.12
const OUT_ZOOM := 0.28
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 48
const RSS_LIMIT_MB := 3000
const ANCHOR_MIN_HITS := 6
## Icons sit a landward screen offset off the centroid corridor (FIX #1).
const SAMPLE_RADIUS := 40

enum Phase {
	WAIT_MAP,
	SETTLE,
	FRAME_MID,
	POLITICAL_MID,
	FRAME_CLOSE,
	POLITICAL_CLOSE,
	FRAME_OUT,
	ZOOMED_OUT,
	SWITCH_RESOURCES,
	RESOURCES,
	SWITCH_BACK,
	BACK,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.FRAME_MID
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _rss_start_kb: int = 0
var _rss_peak_kb: int = 0
var _cam_zoom: float = MID_ZOOM
var _mid_anchors: int = 0
var _close_anchors: int = 0
var _out_anchors: int = 0
var _res_anchors: int = 0
var _back_anchors: int = 0
var _layer_mid: int = -1
var _layer_out: int = -1
var _layer_res: int = -1
var _layer_back: int = -1


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedFac1aAirfieldPixelGuard: DisplayServer=%s (xvfb NOT live Play / NOT Vulkan product)" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_out_dir = OS.get_environment("EOA_FAC1A_PIXEL_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/opt/cursor/artifacts/fac1a"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/fac1a")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_rss_start_kb = _rss_kb()
	_rss_peak_kb = _rss_start_kb
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.boot out=%s rss_kb=%d (NOT live Play)" % [_out_dir, _rss_start_kb])
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
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.FRAME_MID:
			_do_frame(MID_ZOOM, Phase.POLITICAL_MID)
		Phase.POLITICAL_MID:
			_do_political_mid()
		Phase.FRAME_CLOSE:
			_do_frame(CLOSE_ZOOM, Phase.POLITICAL_CLOSE)
		Phase.POLITICAL_CLOSE:
			_do_political_close()
		Phase.FRAME_OUT:
			_do_frame(OUT_ZOOM, Phase.ZOOMED_OUT)
		Phase.ZOOMED_OUT:
			_do_zoomed_out()
		Phase.SWITCH_RESOURCES:
			_switch_resources()
		Phase.RESOURCES:
			_do_resources()
		Phase.SWITCH_BACK:
			_switch_back()
		Phase.BACK:
			_do_back()
		Phase.DONE:
			pass


func _go_settle(next_phase: int) -> void:
	_after_settle = next_phase
	_settle_left = SETTLE_FRAMES
	_phase = Phase.SETTLE


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail_reasons.append("map_timeout")
		_finish(false)
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		_log("EOA_FAC1A_PIXEL_GUARD who=guard.wait_map elapsed=%d closed=%s n=%d (NOT live Play)" % [elapsed, str(_title_has_closed()), _province_count()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("fac1a_ready_msec", 0)) == 0:
		root.set_meta("fac1a_ready_msec", Time.get_ticks_msec())
		_log("EOA_FAC1A_PIXEL_GUARD who=guard.map_ready elapsed=%d n=%d" % [elapsed, _province_count()])
		return
	if Time.get_ticks_msec() - int(root.get_meta("fac1a_ready_msec", 0)) < 2000:
		return
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.frame_start elapsed=%d (NOT live Play)" % elapsed)
	_hide_title_overlay()
	_pause_clock_only()
	_unlock_player_camera()
	_hide_unit_noise()
	_go_settle(Phase.FRAME_MID)


func _do_frame(zoom: float, next_phase: int) -> void:
	_frame_over_rhineland(zoom)
	_hide_unit_noise()
	_redraw_layer()
	_go_settle(next_phase)


func _do_political_mid() -> void:
	_set_mode("political")
	_hide_unit_noise()
	_redraw_layer()
	_layer_mid = _layer_would_draw()
	if _layer_mid != 4:
		_fail_reasons.append("mid_layer_count_%d" % _layer_mid)
	_mid_anchors = _sample_anchor_hits()
	_capture("fac1a_political_mid_NOT_live_play")
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.mid anchors=%d layer=%d zoom=%.3f (NOT live Play)" % [_mid_anchors, _layer_mid, _cam_zoom])
	if _mid_anchors < 4:
		_fail_reasons.append("mid_missing_icons")
	_go_settle(Phase.FRAME_CLOSE)


func _do_political_close() -> void:
	_set_mode("political")
	_hide_unit_noise()
	_redraw_layer()
	_close_anchors = _sample_anchor_hits()
	_capture("fac1a_political_close_NOT_live_play")
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.close anchors=%d zoom=%.3f (NOT live Play)" % [_close_anchors, _cam_zoom])
	if _close_anchors < 4:
		_fail_reasons.append("close_missing_icons")
	_go_settle(Phase.FRAME_OUT)


func _do_zoomed_out() -> void:
	_set_mode("political")
	_hide_unit_noise()
	_redraw_layer()
	_layer_out = _layer_would_draw()
	_out_anchors = _sample_anchor_hits()
	_capture("fac1a_zoomed_out_NOT_live_play")
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.out anchors=%d layer=%d zoom=%.3f (NOT live Play)" % [_out_anchors, _layer_out, _cam_zoom])
	if _layer_out != 0:
		_fail_reasons.append("zoomed_out_layer_%d" % _layer_out)
	_go_settle(Phase.SWITCH_RESOURCES)


func _switch_resources() -> void:
	_frame_over_rhineland(MID_ZOOM)
	_set_mode("resources")
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.switch resources (NOT live Play)")
	_go_settle(Phase.RESOURCES)


func _do_resources() -> void:
	_hide_unit_noise()
	_redraw_layer()
	_layer_res = _layer_would_draw()
	_res_anchors = _sample_anchor_hits()
	_capture("fac1a_resources_F9_NOT_live_play")
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.resources anchors=%d layer=%d (NOT live Play)" % [_res_anchors, _layer_res])
	if _layer_res != 0:
		_fail_reasons.append("resources_layer_%d" % _layer_res)
	_go_settle(Phase.SWITCH_BACK)


func _switch_back() -> void:
	_set_mode("political")
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.switch political (NOT live Play)")
	_go_settle(Phase.BACK)


func _do_back() -> void:
	_frame_over_rhineland(MID_ZOOM)
	_hide_unit_noise()
	_redraw_layer()
	_layer_back = _layer_would_draw()
	_back_anchors = _sample_anchor_hits()
	_capture("fac1a_political_back_NOT_live_play")
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.back anchors=%d layer=%d (NOT live Play)" % [_back_anchors, _layer_back])
	if _layer_back != 4:
		_fail_reasons.append("back_layer_%d" % _layer_back)
	if _back_anchors < 4:
		_fail_reasons.append("back_missing_icons")
	_finish(_fail_reasons.is_empty())


func _facility_layer() -> Node:
	var mr := _map_renderer()
	if mr != null and mr.has_method("get_overlay_layer"):
		var ol: Variant = mr.call("get_overlay_layer", "FacilityIconLayer")
		if ol is Node:
			return ol as Node
	return _find_named("FacilityIconLayer")


func _redraw_layer() -> void:
	var ol := _facility_layer()
	if ol != null and ol.has_method("queue_redraw"):
		ol.call("queue_redraw")
	if ol != null and ol.has_method("notify_sites_changed"):
		## Do not rebuild on zoom; this is only used after mode/frame if list is empty.
		var n: int = int(ol.call("get_icon_list").size()) if ol.has_method("get_icon_list") else 0
		if n == 0:
			ol.call("notify_sites_changed")
	RenderingServer.force_draw()
	RenderingServer.force_draw()


func _layer_would_draw() -> int:
	var ol := _facility_layer()
	if ol == null:
		return -1
	if ol.has_method("count_icons_that_would_draw"):
		return int(ol.call("count_icons_that_would_draw"))
	return -1


func _set_mode(mode: String) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_map_mode"):
		mr.call("set_map_mode", mode)


func _sample_anchor_hits() -> int:
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		return 0
	var tex := vp.get_texture()
	if tex == null:
		return 0
	var img := tex.get_image()
	if img == null:
		return 0
	var cam := _camera()
	if cam == null:
		return 0
	var w := img.get_width()
	var h := img.get_height()
	var found := 0
	for pid in PIDS:
		var world := _centroid(pid)
		var screen: Vector2 = cam.get_canvas_transform() * world
		var hits := _sample_disk(img, int(round(screen.x)), int(round(screen.y)), SAMPLE_RADIUS, w, h)
		if hits >= ANCHOR_MIN_HITS:
			found += 1
		_log("EOA_FAC1A_PIXEL_GUARD who=guard.anchor pid=%d screen=%.0f,%.0f hits=%d (NOT live Play)" % [pid, screen.x, screen.y, hits])
	return found


func _sample_disk(img: Image, cx: int, cy: int, radius: int, w: int, h: int) -> int:
	var hits := 0
	for y in range(cy - radius, cy + radius + 1, 1):
		for x in range(cx - radius, cx + radius + 1, 1):
			if x < 4 or y < 4 or x >= w - 4 or y >= h - 4:
				continue
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) > radius * radius:
				continue
			if _is_icon_pixel(img.get_pixel(x, y)):
				hits += 1
	return hits


func _is_icon_pixel(c: Color) -> bool:
	if c.a < 0.45:
		return false
	## Ink airfield: dirt orange, asphalt grey, brass badge/pips, dark keyline.
	var brass := c.r > 0.55 and c.g > 0.40 and c.b < 0.50 and c.s > 0.22
	var dirt := c.r > 0.55 and c.g > 0.28 and c.g < 0.70 and c.b < 0.38 and c.s > 0.28
	var keyline := c.v < 0.20 and c.s < 0.25
	var asphalt := c.s < 0.18 and c.v > 0.22 and c.v < 0.55 and absf(c.r - c.g) < 0.08
	return brass or dirt or keyline or asphalt


func _centroid(pid: int) -> Vector2:
	var ol := _facility_layer()
	if ol != null and ol.has_method("get_draw_world"):
		var dw: Vector2 = ol.call("get_draw_world", pid)
		if dw != Vector2.ZERO and dw.is_finite():
			return dw
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", pid)
		if c != Vector2.ZERO:
			return c
	return Vector2(4254.32 * 1.728, 944.10 * 1.728)


func _hide_unit_noise() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", false)
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var nm := str(n.name)
		if nm.begins_with("DemoUnitIcon") or nm == "StackBadge" or nm == "PinFocusPulse" or nm == "LandBattleBubbleLayer" or nm == "SelectedFrame":
			if n is CanvasItem:
				(n as CanvasItem).visible = false
		for ch in n.get_children():
			stack.append(ch)


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


func _unlock_player_camera() -> void:
	var tm := _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_hold_camera_until_msec", 0)
		mr.set("_close_camera_locked", false)
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", false)
	var tr := _find_named("TestRunner")
	if tr != null and tr.has_method("set_process"):
		tr.set_process(false)


func _ensure_not_live_banner() -> void:
	var existing: Node = _find_named("Fac1aNotLivePlayBanner")
	if existing != null:
		if existing is CanvasItem:
			(existing as CanvasItem).visible = true
		return
	var layer := CanvasLayer.new()
	layer.name = "Fac1aNotLivePlayBanner"
	layer.layer = 120
	var banner := Label.new()
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
	banner.position = Vector2(16, 88)
	layer.add_child(banner)
	var host: Node = root
	if current_scene != null:
		host = current_scene
	host.add_child(layer)


func _frame_over_rhineland(zoom: float) -> void:
	var pos := _centroid(KOELN)
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_search_go"):
		mr.call("player_path_search_go", KOELN)
	elif mr != null and mr.has_method("open_province_inspector_from_search"):
		mr.call("open_province_inspector_from_search", KOELN)
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	if mr != null and "info_panel" in mr:
		var ip: Variant = mr.get("info_panel")
		if ip is Control:
			(ip as Control).visible = false
	if mr != null and mr.has_method("player_path_wheel_toward_world"):
		_cam_zoom = float(mr.call("player_path_wheel_toward_world", pos, zoom))
	var cam := _camera()
	if cam != null:
		if zoom + 0.001 < 0.45:
			_wheel_to_max_zoom(zoom)
		elif _cam_zoom + 0.001 < zoom:
			_wheel_to_min_zoom(zoom)
		_cam_zoom = maxf(cam.zoom.x, cam.zoom.y)
	_ensure_not_live_banner()
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.frame want=%.2f got=%.3f (NOT live Play)" % [zoom, _cam_zoom])


func _wheel_to_min_zoom(target_zoom: float) -> void:
	var mr := _map_renderer()
	var cam := _camera()
	if mr == null or cam == null or not mr.has_method("_zoom_toward_mouse"):
		return
	var world := _centroid(KOELN)
	var screen: Vector2 = cam.get_canvas_transform() * world
	if DisplayServer.get_name() != "headless":
		DisplayServer.warp_mouse(Vector2i(int(round(screen.x)), int(round(screen.y))))
	var guard: int = 0
	while guard < 16:
		var z: float = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
		if z + 0.001 >= target_zoom:
			break
		mr.call("_zoom_toward_mouse", 1.243)
		guard += 1
	_cam_zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))


func _wheel_to_max_zoom(target_zoom: float) -> void:
	var mr := _map_renderer()
	var cam := _camera()
	if mr == null or cam == null or not mr.has_method("_zoom_toward_mouse"):
		return
	var world := _centroid(KOELN)
	var screen: Vector2 = cam.get_canvas_transform() * world
	if DisplayServer.get_name() != "headless":
		DisplayServer.warp_mouse(Vector2i(int(round(screen.x)), int(round(screen.y))))
	var guard: int = 0
	while guard < 16:
		var z: float = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
		if z - 0.001 <= target_zoom:
			break
		mr.call("_zoom_toward_mouse", 0.80)
		guard += 1
	_cam_zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))


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


func _capture(name: String) -> void:
	_ensure_not_live_banner()
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var cam := _camera()
	if cam != null:
		_cam_zoom = maxf(cam.zoom.x, cam.zoom.y)
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
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.capture name=%s path=%s (xvfb NOT live Play)" % [name, path])


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
		"WindowedFac1aAirfieldPixelGuard: RESULT=%s mid=%d close=%d out=%d res=%d back=%d layer=%d/%d/%d/%d rss_mb=%.1f peak_kb=%d captures=%s reasons=%s (xvfb NOT live Play)"
		% [
			result,
			_mid_anchors,
			_close_anchors,
			_out_anchors,
			_res_anchors,
			_back_anchors,
			_layer_mid,
			_layer_out,
			_layer_res,
			_layer_back,
			rss_mb,
			_rss_peak_kb,
			str(_captures),
			str(_fail_reasons),
		]
	)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
