extends SceneTree

## WINDOWED RH-1 resource-glyph pixel guard. xvfb / llvmpipe is NOT live Play.
## Frames Ruhr / Essen NUTS3 at zoom >= 0.5. Political must have no coal/resource
## glyph pixels; F9 resources must show current HudIconLibrary glyphs.
##
##   tools/eoa_rh1_pixel_guard.sh
##   xvfb-run -a -s "-screen 0 1600x900x24" tools/run_godot.sh \
##     -s res://scripts/core/WindowedRh1ResourceGlyphPixelGuard.gd

const ESSEN := 710403
const DUISBURG := 710402
const KOELN := 710417
const BONN := 710416
const LEV := 710418
const FRAME_ZOOM := 0.55
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 48
const RSS_LIMIT_MB := 3000
const GLYPH_MIN_DELTA := 180

enum Phase {
	WAIT_MAP,
	SETTLE,
	ZOOM,
	POLITICAL,
	SWITCH_RESOURCES,
	RESOURCES,
	SWITCH_BACK,
	BACK,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.POLITICAL
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _rss_start_kb: int = 0
var _rss_peak_kb: int = 0
var _cam_pos: Vector2 = Vector2.ZERO
var _cam_zoom: float = FRAME_ZOOM
var _political_hits: int = -1
var _resources_hits: int = -1
var _back_hits: int = -1
var _icons_political: bool = true
var _icons_resources: bool = false
var _icons_back: bool = true


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedRh1ResourceGlyphPixelGuard: DisplayServer=%s (xvfb NOT live Play / NOT Vulkan product)" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_out_dir = OS.get_environment("EOA_RH1_PIXEL_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-rh1-pixel"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/rh1-glyphs")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_rss_start_kb = _rss_kb()
	_rss_peak_kb = _rss_start_kb
	_log("EOA_RH1_PIXEL_GUARD who=guard.boot out=%s rss_kb=%d (NOT live Play)" % [_out_dir, _rss_start_kb])
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
		Phase.ZOOM:
			_do_zoom()
		Phase.POLITICAL:
			_do_political()
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
		_log("EOA_RH1_PIXEL_GUARD who=guard.wait_map elapsed=%d closed=%s n=%d (NOT live Play)" % [elapsed, str(_title_has_closed()), _province_count()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("rh1_ready_msec", 0)) == 0:
		root.set_meta("rh1_ready_msec", Time.get_ticks_msec())
		_log("EOA_RH1_PIXEL_GUARD who=guard.map_ready elapsed=%d n=%d" % [elapsed, _province_count()])
		return
	if Time.get_ticks_msec() - int(root.get_meta("rh1_ready_msec", 0)) < 2000:
		return
	_log("EOA_RH1_PIXEL_GUARD who=guard.frame_start elapsed=%d (NOT live Play)" % elapsed)
	_hide_title_overlay()
	_pause_clock_only()
	_unlock_player_camera()
	_frame_over_ruhr(FRAME_ZOOM)
	_hide_unit_noise()
	_go_settle(Phase.ZOOM)


func _do_zoom() -> void:
	_wheel_to_min_zoom(0.52)
	_hide_unit_noise()
	_go_settle(Phase.POLITICAL)


func _do_political() -> void:
	_hide_unit_noise()
	var ol := _overlay()
	_icons_political = bool(ol.get("show_resource_icons")) if ol != null else true
	if _icons_political:
		_fail_reasons.append("political_show_resource_icons_true")
	_political_hits = _sample_glyph_hits()
	_capture("rh1_political_no_coal_icons_NOT_live_play")
	_log("EOA_RH1_PIXEL_GUARD who=guard.political hits=%d icons=%s (NOT live Play)" % [_political_hits, str(_icons_political)])
	_go_settle(Phase.SWITCH_RESOURCES)


func _switch_resources() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	if mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "resources")
	_log("EOA_RH1_PIXEL_GUARD who=guard.switch resources (NOT live Play)")
	_go_settle(Phase.RESOURCES)


func _do_resources() -> void:
	_hide_unit_noise()
	var ol := _overlay()
	_icons_resources = bool(ol.get("show_resource_icons")) if ol != null else false
	if not _icons_resources:
		_fail_reasons.append("resources_show_resource_icons_false")
	if ol != null and ol.has_method("queue_redraw"):
		ol.call("queue_redraw")
	_resources_hits = _sample_glyph_hits()
	_capture("rh1_resources_coal_icons_NOT_live_play")
	_log("EOA_RH1_PIXEL_GUARD who=guard.resources hits=%d icons=%s (NOT live Play)" % [_resources_hits, str(_icons_resources)])
	if _resources_hits < _political_hits + GLYPH_MIN_DELTA:
		_fail_reasons.append("resources_glyphs_missing")
	_go_settle(Phase.SWITCH_BACK)


func _switch_back() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "political")
	_log("EOA_RH1_PIXEL_GUARD who=guard.switch political (NOT live Play)")
	_go_settle(Phase.BACK)


func _do_back() -> void:
	_hide_unit_noise()
	var ol := _overlay()
	_icons_back = bool(ol.get("show_resource_icons")) if ol != null else true
	if _icons_back:
		_fail_reasons.append("back_show_resource_icons_true")
	_back_hits = _sample_glyph_hits()
	_capture("rh1_political_again_no_icons_NOT_live_play")
	_log("EOA_RH1_PIXEL_GUARD who=guard.back hits=%d icons=%s (NOT live Play)" % [_back_hits, str(_icons_back)])
	if _back_hits > _political_hits + 80:
		_fail_reasons.append("political_glyphs_after_switch_back")
	_finish(_fail_reasons.is_empty())


func _overlay() -> Node:
	var mr := _map_renderer()
	if mr != null and mr.has_method("get_overlay_layer"):
		var ol: Variant = mr.call("get_overlay_layer", "InfrastructureOverlayLayer")
		if ol is Node:
			return ol as Node
	return _find_named("InfrastructureOverlayLayer")


func _sample_glyph_hits() -> int:
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
	var w := img.get_width()
	var h := img.get_height()
	var hits := 0
	# Map body only: skip HUD, minimap, toast stack.
	var x0 := 80
	var x1 := w - 280
	var y0 := 140
	var y1 := h - 90
	var step := 2
	for y in range(y0, y1, step):
		for x in range(x0, x1, step):
			if _is_glyph_on_land(img, x, y, w, h):
				hits += 1
	_log("EOA_RH1_PIXEL_GUARD who=guard.sample hits=%d size=%dx%d (NOT live Play)" % [hits, w, h])
	return hits


func _is_glyph_on_land(img: Image, x: int, y: int, w: int, h: int) -> bool:
	var c := img.get_pixel(x, y)
	if c.a < 0.50:
		return false
	# Current glyphs: dark ring / hex on land. Not void, not sea, not HUD cyan.
	if c.v > 0.22 or c.s > 0.35:
		return false
	if c.b > c.r + 0.08 and c.b > c.g + 0.06:
		return false
	var land_near := false
	for oy in [-6, 0, 6]:
		for ox in [-6, 0, 6]:
			var nx: int = x + int(ox)
			var ny: int = y + int(oy)
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var n: Color = img.get_pixel(nx, ny)
			if n.v > 0.28 and n.s > 0.12:
				land_near = true
	return land_near


func _centroid(pid: int) -> Vector2:
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", pid)
		if c != Vector2.ZERO:
			return c
	if pid == KOELN:
		return Vector2(4254.32 * 1.728, 944.10 * 1.728)
	if pid == BONN:
		return Vector2(4257.18 * 1.728, 951.42 * 1.728)
	if pid == LEV:
		return Vector2(4254.88 * 1.728, 940.99 * 1.728)
	return Vector2(4254.32 * 1.728, 944.10 * 1.728)


func _hide_unit_noise() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", false)
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
	_log("EOA_RH1_PIXEL_GUARD who=guard.player_camera (Search/Go+wheel, NOT live Play)")


func _ensure_not_live_banner() -> void:
	var existing: Node = _find_named("Rh1NotLivePlayBanner")
	if existing != null:
		if existing is CanvasItem:
			(existing as CanvasItem).visible = true
		return
	var layer := CanvasLayer.new()
	layer.name = "Rh1NotLivePlayBanner"
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


func _frame_over_ruhr(zoom: float) -> void:
	var pos := _centroid(ESSEN)
	if pos == Vector2.ZERO:
		pos = _centroid(KOELN)
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_search_go"):
		mr.call("player_path_search_go", ESSEN)
	elif mr != null and mr.has_method("open_province_inspector_from_search"):
		mr.call("open_province_inspector_from_search", ESSEN)
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
		_cam_pos = cam.global_position
		_cam_zoom = maxf(cam.zoom.x, cam.zoom.y)
	if _cam_zoom < 0.50:
		_wheel_to_min_zoom(0.52)
	_ensure_not_live_banner()
	var ol := _overlay()
	if ol != null and ol.has_method("queue_redraw"):
		ol.call("queue_redraw")
	_log("EOA_RH1_PIXEL_GUARD who=guard.frame want=%.2f got=%.3f pos=%.1f,%.1f (NOT live Play)" % [zoom, _cam_zoom, _cam_pos.x, _cam_pos.y])


func _wheel_to_min_zoom(target_zoom: float) -> void:
	var mr := _map_renderer()
	var cam := _camera()
	if mr == null or cam == null or not mr.has_method("_zoom_toward_mouse"):
		return
	var world := _centroid(ESSEN)
	var screen: Vector2 = cam.get_canvas_transform() * world
	if DisplayServer.get_name() != "headless":
		DisplayServer.warp_mouse(Vector2i(int(round(screen.x)), int(round(screen.y))))
	var factor_in: float = 1.243
	var guard: int = 0
	while guard < 12:
		var z: float = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
		if z + 0.001 >= target_zoom:
			break
		mr.call("_zoom_toward_mouse", factor_in)
		guard += 1
	_cam_zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	_cam_pos = cam.global_position
	_log("EOA_RH1_PIXEL_GUARD who=guard.wheel got=%.3f want=%.2f (NOT live Play)" % [_cam_zoom, target_zoom])


func _apply_camera(_pos: Vector2, _zoom: float) -> void:
	# Player path only — lock_pixel_guard_camera can report zoom while the
	# window still shows Europe Home.
	pass


func _reassert_camera() -> void:
	pass


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
		_cam_pos = cam.global_position
		var d := cam.global_position.distance_to(_centroid(ESSEN))
		_log(
			"EOA_RH1_PIXEL_GUARD who=guard.cam pos=%.1f,%.1f zoom=%.3f essen_dist=%.1f (NOT live Play)"
			% [cam.global_position.x, cam.global_position.y, _cam_zoom, d]
		)
		if _cam_zoom + 0.001 < 0.50:
			_fail_reasons.append("camera_zoom_below_0_5")
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
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/rh1-glyphs"):
		img.save_png("/opt/cursor/artifacts/rh1-glyphs/%s.png" % name)
	_log("EOA_RH1_PIXEL_GUARD who=guard.capture name=%s path=%s (xvfb NOT live Play)" % [name, path])


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
		"WindowedRh1ResourceGlyphPixelGuard: RESULT=%s political_hits=%d resources_hits=%d back_hits=%d icons=%s/%s/%s rss_mb=%.1f peak_kb=%d captures=%s reasons=%s (xvfb NOT live Play)"
		% [
			result,
			_political_hits,
			_resources_hits,
			_back_hits,
			str(_icons_political),
			str(_icons_resources),
			str(_icons_back),
			rss_mb,
			_rss_peak_kb,
			str(_captures),
			str(_fail_reasons),
		]
	)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
