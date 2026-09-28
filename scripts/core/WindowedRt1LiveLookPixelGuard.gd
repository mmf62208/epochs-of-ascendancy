extends SceneTree

## WINDOWED RT-1 live-look + Europe mesh-density guard.
## Does NOT seed infrastructure. Smoke harness is not the product.
##
## (a) mid/close: pixels for dirt tan + dash, paved grey, highway casing+stripe.
## (b) Europe/Home: grey road-mesh density near main 497731dd (no mesh).
## Gold spine width ~9 px. S2 labels are control-sized, not world-scaled.
##
## Must FAIL on 22c3392 (mesh + no distinct looks). Density PASSes on 497731dd.
## Must PASS on the live-look tip.
##
##   tools/eoa_rt1_live_look_guard.sh

const KOELN := 710417
const BONN := 710416
const LEV := 710418
const EUROPE_ZOOM := 0.42
const MID_ZOOM := 1.80
const CLOSE_ZOOM := 3.20
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 40
const GOLD_WIDTH_MIN := 7.0
const GOLD_WIDTH_MAX := 13.0
## After units-off, 497731dd Europe is low. 22c3392 dirt carpet is far above this.
const MESH_MAX_FRAC := 0.018
const TIER_MIN_PX := 6
const DASH_MIN_GAPS := 1
const LABEL_MAX_H_PX := 36.0

enum Phase {
	WAIT_MAP,
	SETTLE,
	EUROPE,
	MID,
	CLOSE,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.EUROPE
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _rss_start_kb: int = 0
var _rss_end_kb: int = 0
var _cam_pos: Vector2 = Vector2.ZERO
var _cam_zoom: float = EUROPE_ZOOM
var _mesh_frac: float = -1.0
var _gold_w_close: float = 0.0


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedRt1LiveLookPixelGuard: DisplayServer=%s" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_out_dir = OS.get_environment("EOA_RT1_LIVE_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-rt1-live-look"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/rt1-live-look")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_rss_start_kb = _rss_kb()
	_log("EOA_RT1_LIVE_LOOK who=guard.boot out=%s rss_kb=%d (NOT product Play)" % [
		_out_dir, _rss_start_kb
	])
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
		Phase.SETTLE:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.EUROPE:
			_do_europe()
		Phase.MID:
			_do_mid()
		Phase.CLOSE:
			_do_close()
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
		_log("EOA_RT1_LIVE_LOOK who=guard.wait_map elapsed=%d closed=%s n=%d" % [
			elapsed, str(_title_has_closed()), _province_count()
		])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("rt1_live_ready_msec", 0)) == 0:
		root.set_meta("rt1_live_ready_msec", Time.get_ticks_msec())
		return
	if Time.get_ticks_msec() - int(root.get_meta("rt1_live_ready_msec", 0)) < 2000:
		return
	_log("EOA_RT1_LIVE_LOOK who=guard.frame_start elapsed=%d n=%d" % [elapsed, _province_count()])
	_force_political_clean()
	_set_units_view(false)
	_ensure_spine_built()
	_frame_europe_home()
	_freeze_boot_camera_fighters()
	_go_settle(Phase.EUROPE)


func _do_europe() -> void:
	_force_political_clean()
	_set_units_view(false)
	_reassert_camera()
	RenderingServer.force_draw()
	var img := _capture("rt1_live_europe")
	_mesh_frac = _mesh_density_frac(img)
	_log("EOA_RT1_LIVE_LOOK who=guard.europe mesh_frac=%.5f max=%.4f (497731dd baseline ~0)" % [
		_mesh_frac, MESH_MAX_FRAC
	])
	if _mesh_frac > MESH_MAX_FRAC:
		_fail_reasons.append("europe_mesh_frac_%.5f" % _mesh_frac)
	_force_political_clean()
	_set_units_view(false)
	_frame_over_koln(MID_ZOOM, true)
	_go_settle(Phase.MID)


func _do_mid() -> void:
	_set_units_view(false)
	_reassert_camera()
	_judge_looks(_capture("rt1_live_mid"), "mid", false)
	_judge_labels("mid")
	_frame_over_koln(CLOSE_ZOOM, true)
	_go_settle(Phase.CLOSE)


func _do_close() -> void:
	_set_units_view(false)
	_reassert_camera()
	var img := _capture("rt1_live_close")
	_judge_looks(img, "close", true)
	_judge_labels("close")
	_gold_w_close = _measure_gold_width(img)
	_log("EOA_RT1_LIVE_LOOK who=guard.gold_width_close px=%.2f need %.1f-%.1f" % [
		_gold_w_close, GOLD_WIDTH_MIN, GOLD_WIDTH_MAX
	])
	if _gold_w_close < GOLD_WIDTH_MIN or _gold_w_close > GOLD_WIDTH_MAX:
		_fail_reasons.append("gold_width_close_%.2f" % _gold_w_close)
	_rss_end_kb = _rss_kb()
	_log("EOA_RT1_LIVE_LOOK who=guard.rss start_kb=%d end_kb=%d mb=%.1f" % [
		_rss_start_kb, _rss_end_kb, float(_rss_end_kb) / 1024.0
	])
	_finish(_fail_reasons.is_empty())


func _judge_looks(img: Image, band: String, need_dirt: bool) -> void:
	if img == null:
		_fail_reasons.append("capture_%s" % band)
		return
	var dirt_n := _count_kind_on_edges(img, 0, "dirt")
	var paved_n := _count_kind_on_edges(img, 1, "paved")
	var case_n := _count_kind_on_edges(img, 2, "casing")
	var stripe_n := _count_kind_on_edges(img, 2, "stripe")
	var dash_gaps := _dirt_dash_gaps(img)
	_log("EOA_RT1_LIVE_LOOK who=guard.looks band=%s dirt=%d paved=%d casing=%d stripe=%d dash_gaps=%d" % [
		band, dirt_n, paved_n, case_n, stripe_n, dash_gaps
	])
	if need_dirt:
		if dirt_n < TIER_MIN_PX:
			_fail_reasons.append("%s_dirt_px_%d" % [band, dirt_n])
		if dash_gaps < DASH_MIN_GAPS:
			_fail_reasons.append("%s_dirt_dash_%d" % [band, dash_gaps])
	if paved_n < TIER_MIN_PX:
		_fail_reasons.append("%s_paved_px_%d" % [band, paved_n])
	if case_n < TIER_MIN_PX:
		_fail_reasons.append("%s_highway_casing_%d" % [band, case_n])
	if stripe_n < 4:
		_fail_reasons.append("%s_highway_stripe_%d" % [band, stripe_n])


func _judge_labels(band: String) -> void:
	var gold := _gold_layer()
	if gold == null:
		_fail_reasons.append("%s_no_gold_layer" % band)
		return
	var visible_n := 0
	var overlap := false
	var last_rect := Rect2()
	var huge := false
	for ch in gold.get_children():
		if not (ch is Label):
			continue
		var lbl := ch as Label
		if not lbl.visible:
			continue
		visible_n += 1
		var fs := 0
		if lbl.has_theme_font_size_override("font_size"):
			fs = int(lbl.get_theme_font_size("font_size"))
		# 14 px + outline 4 is ~24–32 px tall (same family as political labels).
		# World-scaled draw_string leftovers were 40+ px / font > 20.
		if fs > 20 or lbl.size.y > LABEL_MAX_H_PX:
			huge = true
		var r := Rect2(lbl.position, lbl.size)
		if visible_n > 1 and last_rect.intersects(r):
			overlap = true
		last_rect = r
	_log("EOA_RT1_LIVE_LOOK who=guard.labels band=%s visible=%d huge=%s overlap=%s" % [
		band, visible_n, str(huge), str(overlap)
	])
	# S2 labels are close-only (zoom >= 2.60). Mid 1.80 must not require them.
	if band == "close":
		if visible_n < 2:
			_fail_reasons.append("%s_labels_%d" % [band, visible_n])
		if huge:
			_fail_reasons.append("%s_labels_huge" % band)
		if overlap:
			_fail_reasons.append("%s_labels_overlap" % band)


func _count_kind_on_edges(img: Image, display_tier: int, kind: String) -> int:
	if img == null:
		return 0
	var edges: Array = _live_edges_of_display(display_tier)
	if edges.is_empty():
		return 0
	var layer := _road_layer()
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var n := 0
	for entry in edges:
		var a: Vector2 = xform * entry.get("c1", Vector2.ZERO)
		var b: Vector2 = xform * entry.get("c2", Vector2.ZERO)
		if a == Vector2.ZERO or b == Vector2.ZERO:
			continue
		var steps := mini(24, maxi(6, int(a.distance_to(b) / 3.0)))
		for i in range(steps + 1):
			var p: Vector2 = a.lerp(b, float(i) / float(maxi(steps, 1)))
			var x := int(round(p.x))
			var y := int(round(p.y))
			if x < 1 or y < 1 or x >= img.get_width() - 1 or y >= img.get_height() - 1:
				continue
			if _neighborhood_kind(img, x, y, 2, kind):
				n += 1
	return n


func _dirt_dash_gaps(img: Image) -> int:
	if img == null:
		return 0
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province_centroid"):
		return 0
	var edges: Array = _live_edges_of_display(0)
	if edges.is_empty():
		edges = [{"c1": mm.call("get_province_centroid", 710425), "c2": mm.call("get_province_centroid", BONN)}]
	var layer := _road_layer()
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var best := 0
	for entry in edges:
		var a: Vector2 = xform * entry.get("c1", Vector2.ZERO)
		var b: Vector2 = xform * entry.get("c2", Vector2.ZERO)
		if a == Vector2.ZERO or b == Vector2.ZERO:
			continue
		var delta: Vector2 = b - a
		var length := delta.length()
		if length < 8.0:
			continue
		var dir: Vector2 = delta / length
		var hits := 0
		var gaps := 0
		var prev := false
		var steps := mini(48, int(length / 2.0))
		for i in range(steps + 1):
			var p: Vector2 = a + dir * (length * float(i) / float(maxi(steps, 1)))
			var x := int(round(p.x))
			var y := int(round(p.y))
			if x < 1 or y < 1 or x >= img.get_width() - 1 or y >= img.get_height() - 1:
				continue
			var hit := _neighborhood_kind(img, x, y, 2, "dirt")
			if hit:
				if not prev:
					hits += 1
				prev = true
			else:
				if prev:
					gaps += 1
				prev = false
		best = maxi(best, gaps)
		if hits >= 2 and gaps >= 1:
			return maxi(gaps, 1)
	return best


func _live_edges_of_display(display_tier: int) -> Array:
	var ol := _overlay()
	if ol == null or not ol.has_method("get_road_tier_cache"):
		return []
	var cache: Array = ol.call("get_road_tier_cache")
	var out: Array = []
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var dt := int(row.get("display_tier", row.get("tier", -1)))
		if dt != display_tier:
			continue
		if bool(row.get("explicit", false)):
			continue
		out.append(row)
		if out.size() >= 12:
			break
	return out


func _neighborhood_kind(img: Image, x: int, y: int, rad: int, kind: String) -> bool:
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			if _is_kind(img.get_pixel(x + dx, y + dy), kind):
				return true
	return false


func _mesh_density_frac(img: Image) -> float:
	if img == null:
		return 1.0
	var mesh := 0
	var total := 0
	var step := 3
	var y0 := 100
	var y1 := img.get_height() - 80
	var x0 := 20
	var x1 := img.get_width() - 20
	for y in range(y0, y1, step):
		for x in range(x0, x1, step):
			total += 1
			if _is_stroke_on_fill(img, x, y):
				mesh += 1
	if total <= 0:
		return 1.0
	return float(mesh) / float(total)


func _is_stroke_on_fill(img: Image, x: int, y: int) -> bool:
	var c := img.get_pixel(x, y)
	if not _is_mesh_like(c):
		return false
	# Thin road stroke sits on a saturated political fill. Unit plates are
	# large grey blocks and must not count as mesh.
	var fill_near := false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var n := img.get_pixel(x + dx, y + dy)
			var sat := maxf(n.r, maxf(n.g, n.b)) - minf(n.r, minf(n.g, n.b))
			if sat > 0.28:
				fill_near = true
				break
		if fill_near:
			break
	return fill_near


func _is_mesh_like(c: Color) -> bool:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var sat := mx - mn
	var lum := (c.r + c.g + c.b) / 3.0
	if lum < 0.22 or lum > 0.62:
		return false
	if sat > 0.14:
		return false
	return true


func _is_kind(c: Color, kind: String) -> bool:
	if kind == "dirt":
		return _near_rgb(c, Color(0.84, 0.56, 0.18), 0.16) or _near_rgb(c, Color(0.72, 0.48, 0.16), 0.14)
	if kind == "paved":
		return _near_rgb(c, Color(0.34, 0.36, 0.40), 0.11) or _near_rgb(c, Color(0.16, 0.17, 0.20), 0.10)
	if kind == "casing":
		return _near_rgb(c, Color(0.05, 0.05, 0.07), 0.10) or _near_rgb(c, Color(0.22, 0.24, 0.28), 0.10)
	if kind == "stripe":
		return _near_rgb(c, Color(0.98, 0.94, 0.62), 0.14)
	return false


func _near_rgb(c: Color, target: Color, tol: float) -> bool:
	return absf(c.r - target.r) + absf(c.g - target.g) + absf(c.b - target.b) <= tol * 3.0


func _measure_gold_width(img: Image) -> float:
	if img == null:
		return 0.0
	var mm := _map_manager()
	if mm == null:
		return 0.0
	var c1: Vector2 = mm.call("get_province_centroid", BONN)
	var c2: Vector2 = mm.call("get_province_centroid", KOELN)
	var layer := _overlay() as CanvasItem
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var a: Vector2 = xform * c1
	var b: Vector2 = xform * c2
	var dir: Vector2 = b - a
	if dir.length() < 2.0:
		return 0.0
	var perp := Vector2(-dir.y, dir.x).normalized()
	var mid: Vector2 = a.lerp(b, 0.45)
	var best := 0
	for t_i in range(3, 8):
		var p0: Vector2 = a.lerp(b, float(t_i) / 10.0)
		var run := 0
		var best_run := 0
		var in_run := false
		for i in range(-16, 17):
			var p: Vector2 = p0 + perp * float(i)
			var x := int(round(p.x))
			var y := int(round(p.y))
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				if in_run:
					best_run = maxi(best_run, run)
					in_run = false
					run = 0
				continue
			if _is_gold(img.get_pixel(x, y)):
				if not in_run:
					in_run = true
					run = 0
				run += 1
			elif in_run:
				best_run = maxi(best_run, run)
				in_run = false
				run = 0
		if in_run:
			best_run = maxi(best_run, run)
		best = maxi(best, best_run)
	if best <= 0:
		var x0 := int(round(mid.x))
		var y0 := int(round(mid.y))
		for i in range(-14, 15):
			var x := x0 + int(round(perp.x * float(i)))
			var y := y0 + int(round(perp.y * float(i)))
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if _is_gold(img.get_pixel(x, y)):
				best += 1
	return float(best)


func _is_gold(c: Color) -> bool:
	var r := c.r * 255.0
	var g := c.g * 255.0
	var b := c.b * 255.0
	var gold_d := absf(r - 235.0) + absf(g - 158.0) + absf(b - 20.0)
	if gold_d < 110.0:
		return true
	if r > 185.0 and g > 65.0 and g < 210.0 and b < 70.0 and r > g + 30.0 and r > b + 90.0:
		return true
	return false


func _frame_europe_home() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("center_europe_in_world_view"):
		if mr.has_method("_pixel_guard_camera_locked"):
			mr.set("_close_camera_locked", false)
		mr.call("center_europe_in_world_view")
	var cam := _camera()
	var pos := Vector2.ZERO
	var z := EUROPE_ZOOM
	if cam != null:
		pos = cam.global_position
		z = maxf(cam.zoom.x, cam.zoom.y)
	if pos == Vector2.ZERO:
		pos = _koln_world()
		z = EUROPE_ZOOM
	if z > 0.88:
		z = EUROPE_ZOOM
	_apply_camera(pos, z)
	_set_units_view(false)
	_log("EOA_RT1_LIVE_LOOK who=guard.europe_frame zoom=%.3f pos=%.1f,%.1f" % [z, pos.x, pos.y])


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _province_count() < 3000:
		return false
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province"):
		return false
	if mm.call("get_province", KOELN) == null:
		return false
	return _map_renderer() != null and _camera() != null


func _title_has_closed() -> bool:
	var tm: Node = _time_manager()
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


func _time_manager() -> Node:
	if root != null:
		var tm: Node = root.get_node_or_null("TimeManager")
		if tm != null:
			return tm
	return _find_named("TimeManager")


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


func _freeze_boot_camera_fighters() -> void:
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_close_camera_locked", true)
		mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 120000)
	var tm: Node = _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	var tr := current_scene
	if tr != null and tr.has_method("set_process"):
		tr.set_process(false)
	var cc := _find_named("CameraController")
	if cc == null and mr != null:
		cc = mr.get_node_or_null("CameraInput")
	if cc != null:
		if "enable_pan" in cc:
			cc.set("enable_pan", false)
		if "enable_zoom" in cc:
			cc.set("enable_zoom", false)
		cc.set_process(false)
	if mr != null and mr.has_method("set_process"):
		mr.set_process(false)
	_log("EOA_RT1_LIVE_LOOK who=guard.lock_camera (NOT product Home/Close)")


func _frame_over_koln(zoom: float, hide_inspector: bool) -> void:
	_apply_camera(_koln_world(), zoom)
	var mr := _map_renderer()
	if hide_inspector and mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	var ol := _overlay()
	if ol != null and ol.has_method("_apply_screen_space_road_widths"):
		ol.call("_apply_screen_space_road_widths")
	if ol != null and ol.has_method("refresh_ix1_gold_spine"):
		ol.call("refresh_ix1_gold_spine", true)


func _reassert_camera() -> void:
	if _cam_pos == Vector2.ZERO:
		return
	_apply_camera(_cam_pos, _cam_zoom)


func _apply_camera(pos: Vector2, zoom: float) -> void:
	_cam_pos = pos
	_cam_zoom = zoom
	if root != null:
		root.set_meta("rt1_guard_zoom", zoom)
	var mr := _map_renderer()
	if mr != null and mr.has_method("lock_pixel_guard_camera"):
		mr.call("lock_pixel_guard_camera", pos, zoom)
		return
	if mr != null:
		mr.set("_close_camera_lock_pos", pos)
		mr.set("_close_camera_lock_zoom", Vector2(zoom, zoom))
		mr.set("_close_camera_locked", true)
		mr.set("_europe_focus_retry", 99)
	var cam := _camera()
	if cam == null:
		return
	cam.zoom = Vector2(zoom, zoom)
	var parent := cam.get_parent() as Node2D
	if parent != null:
		cam.position = parent.to_local(pos)
	cam.global_position = pos
	cam.reset_smoothing()
	if cam.has_method("force_update_scroll"):
		cam.call("force_update_scroll")
	cam.enabled = true
	cam.make_current()


func _koln_world() -> Vector2:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", KOELN)
		if c != Vector2.ZERO:
			return c
	return Vector2(4254.32 * 1.728, 944.10 * 1.728)


func _capture(name: String) -> Image:
	_reassert_camera()
	RenderingServer.force_draw()
	_reassert_camera()
	RenderingServer.force_draw()
	var cam := _camera()
	if cam != null:
		var d := cam.global_position.distance_to(_koln_world())
		_log("EOA_RT1_LIVE_LOOK who=guard.cam pos=%.1f,%.1f zoom=%.3f want=%.2f koln_dist=%.1f" % [
			cam.global_position.x, cam.global_position.y, cam.zoom.x, _cam_zoom, d
		])
		if name.contains("mid") or name.contains("close"):
			if d > 520.0:
				_fail_reasons.append("camera_not_on_koln")
			if absf(cam.zoom.x - _cam_zoom) > 0.15:
				_fail_reasons.append("camera_zoom_%.2f" % cam.zoom.x)
	var vp := root.get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	_captures.append(path)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/rt1-live-look"):
		img.save_png("/opt/cursor/artifacts/rt1-live-look/%s.png" % name)
	_log("EOA_RT1_LIVE_LOOK who=guard.capture file=%s %dx%d" % [path, img.get_width(), img.get_height()])
	return img


func _overlay() -> Node:
	return _find_named("InfrastructureOverlayLayer")


func _gold_layer() -> Node:
	return _find_named("Ix1GoldSpine")


func _road_layer() -> CanvasItem:
	var ol := _overlay()
	if ol != null:
		var ch := ol.get_node_or_null("RoadLayer")
		if ch is CanvasItem:
			return ch as CanvasItem
	return _find_named("RoadLayer") as CanvasItem


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _map_manager() -> Node:
	return root.get_node_or_null("MapManager")


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var named_cam := mr.get_node_or_null("MapCamera") as Camera2D
		if named_cam != null:
			return named_cam
	var vp := root.get_viewport()
	if vp != null:
		return vp.get_camera_2d()
	return null


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _force_political_clean() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "political")


func _set_units_view(on: bool) -> void:
	var mr := _map_renderer()
	if mr != null:
		if "show_unit_counters" in mr:
			mr.set("show_unit_counters", on)
		if mr.has_method("set_unit_counters_visible"):
			mr.call("set_unit_counters_visible", on)
		if mr.has_method("_sync_unit_counter_paint") and not on:
			mr.call("_sync_unit_counter_paint")
	_walk_hide_units(root, not on)


func _walk_hide_units(n: Node, hide: bool) -> void:
	if n == null:
		return
	var nm := str(n.name)
	if (
		nm.begins_with("DemoUnitIcon")
		or nm.contains("UnitIcon")
		or nm.contains("NationPlate")
		or nm == "StackBadge"
		or nm == "PinFocusPulse"
		or nm == "LandBattleBubbleLayer"
		or nm == "SelectedFrame"
	):
		if n is CanvasItem:
			(n as CanvasItem).visible = not hide
	for c in n.get_children():
		_walk_hide_units(c, hide)


func _ensure_spine_built() -> void:
	var idm: Node = root.get_node_or_null("InfrastructureDevelopmentManager")
	if idm == null:
		idm = _find_named("InfrastructureDevelopmentManager")
	if idm != null and idm.has_method("link_ix1_road_spine_edges"):
		idm.call("link_ix1_road_spine_edges", KOELN, [BONN, LEV])
	var ol := _overlay()
	if ol != null and ol.has_method("rebuild_road_layer"):
		ol.call("rebuild_road_layer")
	if ol != null and ol.has_method("force_paint_ix1_gold_spine"):
		ol.call("force_paint_ix1_gold_spine")
	if ol != null and ol.has_method("refresh_ix1_gold_spine"):
		ol.call("refresh_ix1_gold_spine", true)


func _rss_kb() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return 0
	var text := f.get_as_text()
	f.close()
	for line in text.split("\n"):
		if line.begins_with("VmRSS:"):
			var parts := line.replace("\t", " ").split(" ", false)
			for p in parts:
				if p.is_valid_int():
					return int(p)
	return 0


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	if not ok and _fail_reasons.is_empty():
		_fail_reasons.append("unknown")
	_log("WindowedRt1LiveLookPixelGuard: mesh_frac=%.5f gold_w=%.2f RESULT=%s reasons=%s captures=%d" % [
		_mesh_frac, _gold_w_close, "PASS" if ok else "FAIL", ",".join(_fail_reasons), _captures.size()
	])
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
