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
const FRAME_ZOOM := 1.15
const ICON_WORLD_OFFSET := Vector2(12, 12)
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 40
const RSS_LIMIT_MB := 3000
const SAMPLE_RADIUS := 10
const GLYPH_MIN_HITS := 8

enum Phase {
	WAIT_MAP,
	SETTLE,
	POLITICAL,
	RESOURCES,
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
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.POLITICAL:
			_do_political()
		Phase.RESOURCES:
			_do_resources()
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
	_lock_camera_fighters()
	_hide_unit_noise()
	_frame_over_ruhr(FRAME_ZOOM)
	_go_settle(Phase.POLITICAL)


func _do_political() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	if mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "political")
	_frame_over_ruhr(FRAME_ZOOM)
	var ol := _overlay()
	_icons_political = bool(ol.get("show_resource_icons")) if ol != null else true
	if _icons_political:
		_fail_reasons.append("political_show_resource_icons_true")
	_political_hits = _sample_glyph_hits()
	_capture("rh1_political_no_coal_icons_NOT_live_play")
	_log("EOA_RH1_PIXEL_GUARD who=guard.political hits=%d icons=%s (NOT live Play)" % [_political_hits, str(_icons_political)])
	if _political_hits > 0:
		_fail_reasons.append("political_glyph_pixels")
	_go_settle(Phase.RESOURCES)


func _do_resources() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	if mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "resources")
	_frame_over_ruhr(FRAME_ZOOM)
	var ol := _overlay()
	_icons_resources = bool(ol.get("show_resource_icons")) if ol != null else false
	if not _icons_resources:
		_fail_reasons.append("resources_show_resource_icons_false")
	if ol != null and ol.has_method("queue_redraw"):
		ol.call("queue_redraw")
	_resources_hits = _sample_glyph_hits()
	_capture("rh1_resources_coal_icons_NOT_live_play")
	_log("EOA_RH1_PIXEL_GUARD who=guard.resources hits=%d icons=%s (NOT live Play)" % [_resources_hits, str(_icons_resources)])
	if _resources_hits < GLYPH_MIN_HITS:
		_fail_reasons.append("resources_glyphs_missing")
	_go_settle(Phase.BACK)


func _do_back() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "political")
	_frame_over_ruhr(FRAME_ZOOM)
	var ol := _overlay()
	_icons_back = bool(ol.get("show_resource_icons")) if ol != null else true
	if _icons_back:
		_fail_reasons.append("back_show_resource_icons_true")
	_back_hits = _sample_glyph_hits()
	_capture("rh1_political_again_no_icons_NOT_live_play")
	_log("EOA_RH1_PIXEL_GUARD who=guard.back hits=%d icons=%s (NOT live Play)" % [_back_hits, str(_icons_back)])
	if _back_hits > 0:
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
	_reassert_camera()
	RenderingServer.force_draw()
	_reassert_camera()
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
	var layer := _overlay() as CanvasItem
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var hits := 0
	for pid in [KOELN, ESSEN, DUISBURG, BONN, LEV]:
		var world := _centroid(int(pid)) + ICON_WORLD_OFFSET
		var screen: Vector2 = xform * world
		hits += _neighborhood_glyph(img, int(round(screen.x)), int(round(screen.y)), SAMPLE_RADIUS)
	_log("EOA_RH1_PIXEL_GUARD who=guard.sample hits=%d (NOT live Play)" % hits)
	return hits


func _neighborhood_glyph(img: Image, cx: int, cy: int, radius: int) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var hits := 0
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if x < 24 or y < 90 or x >= w - 8 or y >= h - 8:
				continue
			if _is_glyph_pixel(img.get_pixel(x, y)):
				hits += 1
	return hits


func _is_glyph_pixel(c: Color) -> bool:
	# Current coal HudIconLibrary glyph is a saturated cyan/teal hex, not GER
	# political fill and not coal-tint land (0.22, 0.20, 0.18).
	if c.a < 0.35:
		return false
	if c.s < 0.30 or c.v < 0.38:
		return false
	if c.g > c.r + 0.10 and c.b > c.r + 0.06:
		return true
	return false


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


func _lock_camera_fighters() -> void:
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
	var cc := _find_named("CameraController")
	if cc != null:
		if "enable_pan" in cc:
			cc.set("enable_pan", false)
		if "enable_zoom" in cc:
			cc.set("enable_zoom", false)
		cc.set_process(false)
	if mr != null and mr.has_method("set_process"):
		mr.set_process(false)
	_log("EOA_RH1_PIXEL_GUARD who=guard.lock_camera (NOT live Play)")


func _ensure_not_live_banner() -> void:
	var existing: Node = _find_named("Rh1NotLivePlayBanner")
	if existing != null:
		if existing is CanvasItem:
			(existing as CanvasItem).visible = true
		return
	var banner := Label.new()
	banner.name = "Rh1NotLivePlayBanner"
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


func _frame_over_ruhr(zoom: float) -> void:
	var pos := _centroid(ESSEN)
	if pos == Vector2.ZERO:
		pos = _centroid(KOELN)
	_apply_camera(pos, zoom)
	_ensure_not_live_banner()
	var mr := _map_renderer()
	if mr != null and "info_panel" in mr:
		var ip: Variant = mr.get("info_panel")
		if ip is Control:
			(ip as Control).visible = false
	var ol := _overlay()
	if ol != null and ol.has_method("queue_redraw"):
		ol.call("queue_redraw")
	_log("EOA_RH1_PIXEL_GUARD who=guard.frame zoom=%.2f pos=%.1f,%.1f (NOT live Play)" % [zoom, pos.x, pos.y])


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
	if _cam_pos == Vector2.ZERO:
		_apply_camera(_centroid(ESSEN), FRAME_ZOOM)
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


func _capture(name: String) -> void:
	_reassert_camera()
	_ensure_not_live_banner()
	RenderingServer.force_draw()
	_reassert_camera()
	RenderingServer.force_draw()
	var cam := _camera()
	if cam != null:
		var d := cam.global_position.distance_to(_centroid(ESSEN))
		_log(
			"EOA_RH1_PIXEL_GUARD who=guard.cam pos=%.1f,%.1f zoom=%.3f essen_dist=%.1f (NOT live Play)"
			% [cam.global_position.x, cam.global_position.y, cam.zoom.x, d]
		)
		if d > 1600.0:
			_fail_reasons.append("camera_not_on_ruhr")
		if cam.zoom.x < 0.50:
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
