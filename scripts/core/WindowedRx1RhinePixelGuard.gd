extends SceneTree

## WINDOWED (non-headless) RX-1 pixel + panel guard. Not the product Play path.
## Loads the live TestScenario (world_accurate, same F5 smoke scene), frames
## mid and close over Köln/Neuss, captures the viewport, and samples pixels
## along the Rhine polyline and the built Bonn–Köln–Leverkusen spine.
##
##   tools/eoa_rx1_pixel_guard.sh
##   xvfb-run -a tools/run_godot.sh -s res://scripts/core/WindowedRx1RhinePixelGuard.gd
##
## Scope-change FIX2: units stay on top (z=28). River/road sit below.
## (a) Units OFF — Rhine + gold spine must be visible at mid/close.
##     FAIL on 816cdc9 / PASS on tip. 816cdc9 has no U toggle: hide
##     DemoUnitIcon_*/StackBadge/PinFocusPulse/LandBattleBubbleLayer nodes
##     directly via _hide_unit_nodes_direct (documented in RX1_RHINE_CROSSING.md).
## (b) Units ON — sample a counter over the river; counter pixels must win.
## (c) U hides, U restores, sim fingerprint unchanged. Button stays in sync.
## Panel-state checks (Köln built / no re-offer / no leak) stay.
## Smoke harness is not the product. Artifacts are real viewport captures.

const KOELN := 710417
const BONN := 710416
const LEV := 710418
const NEUSS := 710413
const METTMANN := 710412
const MID_ZOOM := 0.95
const CLOSE_ZOOM := 2.10
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 48
const RIVER_MIN_HIT := 0.28
const ROAD_MIN_HIT := 0.15
const UNIT_MIN_HIT := 0.22
const SAMPLE_RADIUS := 5
const LOCAL_RIVER_WORLD := 120.0

enum Phase {
	WAIT_MAP,
	SETTLE,
	DO_MID,
	DO_CLOSE,
	DO_ROADS,
	DO_UNITS_ON,
	DO_TOGGLE,
	DO_PANEL_KOLN,
	DO_PANEL_NEUSS,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.DO_MID
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _mid_river_hit: float = 0.0
var _close_river_hit: float = 0.0
var _road_hit: float = 0.0
var _units_on_hit: float = 0.0
var _units_on_river_under: float = 0.0
var _toggle_ok: bool = false
var _used_direct_unit_hide: bool = false
var _koln_panel: Dictionary = {}
var _neuss_panel: Dictionary = {}
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _parked_unit: Node2D = null
var _parked_unit_pos: Vector2 = Vector2.ZERO


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedRx1RhinePixelGuard: DisplayServer=%s" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_out_dir = OS.get_environment("EOA_RX1_PIXEL_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-rx1-pixel"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/rx1-pixel")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_log("EOA_RX1_PIXEL_GUARD who=guard.boot out=%s (NOT product Begin/Esc/clock PASS)" % _out_dir)
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail_reasons.append("scene_load_%d" % err)
		_finish(false)
		return
	_phase = Phase.WAIT_MAP
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	if _phase != Phase.WAIT_MAP and _phase != Phase.DONE:
		_reassert_camera()
	match _phase:
		Phase.WAIT_MAP:
			_tick_wait_map()
		Phase.SETTLE:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.DO_MID:
			_do_mid()
		Phase.DO_CLOSE:
			_do_close()
		Phase.DO_ROADS:
			_do_roads()
		Phase.DO_UNITS_ON:
			_do_units_on()
		Phase.DO_TOGGLE:
			_do_toggle()
		Phase.DO_PANEL_KOLN:
			_do_panel_koln()
		Phase.DO_PANEL_NEUSS:
			_do_panel_neuss()
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
		_log("EOA_RX1_PIXEL_GUARD who=guard.wait_map elapsed=%d title=%s closed=%s n=%d" % [
			elapsed,
			str(_find_named("LivingTitleBoot") != null),
			str(_title_has_closed()),
			_province_count(),
		])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("rx1_ready_msec", 0)) == 0:
		root.set_meta("rx1_ready_msec", Time.get_ticks_msec())
		_log("EOA_RX1_PIXEL_GUARD who=guard.map_ready elapsed=%d n=%d (hold 2s then frame)" % [elapsed, _province_count()])
		return
	if Time.get_ticks_msec() - int(root.get_meta("rx1_ready_msec", 0)) < 2000:
		return
	_log("EOA_RX1_PIXEL_GUARD who=guard.frame_start elapsed=%d n=%d" % [elapsed, _province_count()])
	_freeze_boot_camera_fighters()
	_set_units_view(false)
	_frame_over_koln(MID_ZOOM, true)
	_go_settle(Phase.DO_MID)


func _do_mid() -> void:
	_reassert_camera()
	var img := _capture("rx1_pixel_mid_koeln_units_off")
	var layer := _rhine_layer()
	_mid_river_hit = _sample_polyline(img, _local_course_pts(), layer, "river")
	_log("EOA_RX1_PIXEL_GUARD who=guard.mid_river units=off hit=%.3f need>=%.2f direct_hide=%s" % [
		_mid_river_hit, RIVER_MIN_HIT, str(_used_direct_unit_hide)
	])
	if _mid_river_hit < RIVER_MIN_HIT:
		_fail_reasons.append("mid_river_hit")
	_frame_over_koln(CLOSE_ZOOM, true)
	_go_settle(Phase.DO_CLOSE)


func _do_close() -> void:
	_reassert_camera()
	var img := _capture("rx1_pixel_close_koeln_units_off")
	var layer := _rhine_layer()
	_close_river_hit = _sample_polyline(img, _local_course_pts(), layer, "river")
	_log("EOA_RX1_PIXEL_GUARD who=guard.close_river units=off hit=%.3f need>=%.2f" % [_close_river_hit, RIVER_MIN_HIT])
	if _close_river_hit < RIVER_MIN_HIT:
		_fail_reasons.append("close_river_hit")
	_ensure_spine_built()
	_frame_over_koln(CLOSE_ZOOM, true)
	_go_settle(Phase.DO_ROADS)


func _do_roads() -> void:
	_reassert_camera()
	var layer := _ensure_gold_spine_layer()
	var img := _capture("rx1_pixel_road_spine_units_off")
	if layer == null:
		layer = _rhine_layer()
	var line_hit := _sample_polyline(img, _spine_pts(), layer, "road")
	var box_hit := _sample_spine_bbox(img, _spine_pts(), layer)
	_road_hit = maxf(line_hit, box_hit)
	_log(
		"EOA_RX1_PIXEL_GUARD who=guard.road_spine units=off line=%.3f box=%.3f hit=%.3f need>=%.2f gold_matcher=1"
		% [line_hit, box_hit, _road_hit, ROAD_MIN_HIT]
	)
	if _road_hit < ROAD_MIN_HIT:
		_fail_reasons.append("road_hit")
	_set_units_view(true)
	_park_unit_over_river()
	_frame_over_koln(CLOSE_ZOOM, true)
	_go_settle(Phase.DO_UNITS_ON)


func _do_units_on() -> void:
	_reassert_camera()
	var img := _capture("rx1_pixel_close_koeln_units_on")
	var sample := _sample_parked_unit(img)
	_units_on_hit = float(sample.get("chip", 0.0))
	_units_on_river_under = float(sample.get("river", 0.0))
	_log(
		"EOA_RX1_PIXEL_GUARD who=guard.units_on chip=%.3f river=%.3f need_chip>=%.2f and chip>river"
		% [_units_on_hit, _units_on_river_under, UNIT_MIN_HIT]
	)
	if _units_on_hit < UNIT_MIN_HIT or _units_on_hit <= _units_on_river_under:
		_fail_reasons.append("units_do_not_win")
	_restore_parked_unit()
	_set_units_view(true)
	_go_settle(Phase.DO_TOGGLE)


func _do_toggle() -> void:
	_reassert_camera()
	var before := _sim_fingerprint()
	var mr := _map_renderer()
	var default_on := true
	if mr != null and "show_unit_counters" in mr:
		default_on = bool(mr.get("show_unit_counters"))
	if not default_on:
		_fail_reasons.append("units_default_hidden")
	_set_units_view(true)
	var vis0 := _visible_icon_count()
	_log("EOA_RX1_PIXEL_GUARD who=guard.toggle default_on=%s vis0=%d" % [str(default_on), vis0])
	_press_units_hotkey()
	var hidden := _units_are_hidden()
	var after_hide := _sim_fingerprint()
	if not hidden:
		_fail_reasons.append("u_did_not_hide")
	if after_hide != before:
		_fail_reasons.append("toggle_hide_mutated_sim")
	_press_units_hotkey()
	var restored := not _units_are_hidden()
	var after_restore := _sim_fingerprint()
	if not restored:
		_fail_reasons.append("u_did_not_restore")
	if after_restore != before:
		_fail_reasons.append("toggle_restore_mutated_sim")
	_toggle_ok = hidden and restored and after_hide == before and after_restore == before
	if mr != null and mr.has_method("units_view_report"):
		var rep: Dictionary = mr.call("units_view_report") as Dictionary
		if not bool(rep.get("button_matches", false)):
			_fail_reasons.append("button_desync")
			_toggle_ok = false
		_log("EOA_RX1_PIXEL_GUARD who=guard.toggle report=%s" % str(rep))
	_capture("rx1_pixel_units_restored")
	_log("EOA_RX1_PIXEL_GUARD who=guard.toggle ok=%s hide=%s restore=%s" % [str(_toggle_ok), str(hidden), str(restored)])
	var mr2 := _map_renderer()
	if mr2 != null and mr2.has_method("set_rx1_bridge_preview"):
		mr2.call("set_rx1_bridge_preview", "built", NEUSS, 100.0)
	_open_inspector(KOELN)
	_go_settle(Phase.DO_PANEL_KOLN)


func _do_panel_koln() -> void:
	_koln_panel = _read_panel(KOELN)
	_capture("rx1_pixel_koln_panel")
	var offers := bool(_koln_panel.get("offers_build_road_spine", true))
	var built := bool(_koln_panel.get("shows_spine_built", false))
	var leak := bool(_koln_panel.get("leaks_bridge_on_spine_pid", true))
	_log(
		"EOA_RX1_PIXEL_GUARD who=guard.koln_panel offer=%s built=%s bridge_leak=%s"
		% [str(offers), str(built), str(leak)]
	)
	if offers:
		_fail_reasons.append("koln_reoffers_build")
	if not built:
		_fail_reasons.append("koln_missing_built")
	if leak:
		_fail_reasons.append("koln_bridge_status_leak")
	_open_inspector(NEUSS)
	_go_settle(Phase.DO_PANEL_NEUSS)


func _do_panel_neuss() -> void:
	_neuss_panel = _read_panel(NEUSS)
	_capture("rx1_pixel_neuss_panel")
	var leak := bool(_neuss_panel.get("leaks_spine_on_bridge_pid", true))
	_log("EOA_RX1_PIXEL_GUARD who=guard.neuss_panel spine_leak=%s" % str(leak))
	if leak:
		_fail_reasons.append("neuss_spine_status_leak")
	_finish(_fail_reasons.is_empty())


func _map_manager() -> Node:
	if root == null:
		return null
	return root.get_node_or_null("MapManager")


func _map_is_ready() -> bool:
	# First 816cdc9 run captured the living-title load screen (pillars +
	# "Rendering provinces") because MapManager/MapRenderer exist under the
	# CanvasLayer. Wait until Begin has closed the title.
	if not _title_has_closed():
		return false
	if _find_named("LivingTitleBoot") != null:
		return false
	if _province_count() < 3000:
		return false
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province"):
		return false
	if mm.call("get_province", KOELN) == null:
		return false
	if _map_renderer() == null:
		return false
	if _camera() == null:
		return false
	return true


func _title_has_closed() -> bool:
	var tr := _test_runner()
	if tr != null and bool(tr.get_meta("eoa_living_title_closed", false)):
		return true
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	return false


func _test_runner() -> Node:
	var n := _find_named("TestRunner")
	if n != null:
		return n
	var scene := current_scene
	if scene != null and scene.get_script() != null:
		return scene
	return current_scene


func _province_count() -> int:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _dismiss_title_if_needed() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	elif boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _frame_over_koln(zoom: float, hide_inspector: bool) -> void:
	var pos := _koln_world()
	_apply_camera(pos, zoom)
	var mr := _map_renderer()
	if hide_inspector and mr != null:
		if "info_panel" in mr:
			var ip: Variant = mr.get("info_panel")
			if ip is Control:
				(ip as Control).visible = false
	var labels: Node = _find_named("PoliticalLabelsLayer")
	if labels != null and labels.has_method("sync_camera_zoom"):
		labels.call("sync_camera_zoom", zoom)
	var rhine: Node = _find_named("Rx1RhineLayer")
	if rhine != null and rhine.has_method("refresh"):
		rhine.call("refresh")
	var ol := _find_named("InfrastructureOverlayLayer")
	if ol != null and ol.has_method("_apply_screen_space_road_widths"):
		ol.call("_apply_screen_space_road_widths")
	_log("EOA_RX1_PIXEL_GUARD who=guard.frame zoom=%.2f pos=%.1f,%.1f" % [zoom, pos.x, pos.y])


var _cam_pos: Vector2 = Vector2.ZERO
var _cam_zoom: float = MID_ZOOM


func _freeze_boot_camera_fighters() -> void:
	# Play MIXED 816cdc9 pixel run framed Europe Home: TestRunner deferred
	# center_europe_in_world_view / LivingTitle _center_on_player won the camera.
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_close_camera_locked", true)
		mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 120000)
		if mr.has_method("set_process"):
			# Keep MapRenderer alive for inspector chrome; lock pose instead of disabling.
			pass
	var tr := _test_runner()
	if tr != null and tr.has_method("set_process"):
		# Title already closed. Stop TestRunner from re-queuing Europe Home.
		tr.set_process(false)
	var cc := _find_named("CameraController")
	if cc != null:
		if "enable_pan" in cc:
			cc.set("enable_pan", false)
		if "enable_zoom" in cc:
			cc.set("enable_zoom", false)
		cc.set_process(false)
	if mr != null and mr.has_method("set_process"):
		# Stop _handle_camera_input / theater auto-fit from fighting the frame.
		mr.set_process(false)
	_log("EOA_RX1_PIXEL_GUARD who=guard.lock_camera (NOT product Home/Close)")


func _reassert_camera() -> void:
	if _cam_pos == Vector2.ZERO:
		return
	_apply_camera(_cam_pos, _cam_zoom)
	if root != null and not bool(root.get_meta("rx1_cam_deferred", false)):
		root.set_meta("rx1_cam_deferred", true)
		call_deferred("_apply_camera_deferred")


func _apply_camera_deferred() -> void:
	if root != null:
		root.set_meta("rx1_cam_deferred", false)
	if _cam_pos != Vector2.ZERO:
		_apply_camera(_cam_pos, _cam_zoom)


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
	if cam != null:
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
	# GIS boards lock ProvinceContainers at identity. Do not scale it.


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
		_log(
			"EOA_RX1_PIXEL_GUARD who=guard.cam pos=%.1f,%.1f zoom=%.3f koln_dist=%.1f"
			% [cam.global_position.x, cam.global_position.y, cam.zoom.x, d]
		)
		if name.begins_with("rx1_pixel_mid") or name.begins_with("rx1_pixel_close") or name.begins_with("rx1_pixel_road") or name.begins_with("rx1_pixel_units"):
			if d > 520.0:
				_fail_reasons.append("camera_not_on_koln")
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
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/rx1-pixel"):
		img.save_png("/opt/cursor/artifacts/rx1-pixel/%s.png" % name)
	_log(
		"EOA_RX1_PIXEL_GUARD who=guard.capture file=%s %dx%d (real viewport; NOT a mock)"
		% [path, img.get_width(), img.get_height()]
	)
	return img


func _sample_polyline(img: Image, pts: PackedVector2Array, layer: CanvasItem, kind: String) -> float:
	if img == null or pts.size() < 2:
		return 0.0
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var hits := 0
	var total := 0
	var w := img.get_width()
	var h := img.get_height()
	for i in range(1, pts.size()):
		var a: Vector2 = xform * pts[i - 1]
		var b: Vector2 = xform * pts[i]
		var step_px := 2.0 if kind == "road" else 3.0
		var steps := maxi(6 if kind == "road" else 4, int(a.distance_to(b) / step_px))
		for s in range(steps + 1):
			var t := float(s) / float(maxi(steps, 1))
			var p := a.lerp(b, t)
			var ix := int(round(p.x))
			var iy := int(round(p.y))
			if ix < 0 or iy < 0 or ix >= w or iy >= h:
				continue
			total += 1
			if _neighborhood_hit(img, ix, iy, kind):
				hits += 1
	if total <= 0:
		_log("EOA_RX1_PIXEL_GUARD who=guard.sample kind=%s hits=0 total=0 (off-screen or no layer)" % kind)
		return 0.0
	_log("EOA_RX1_PIXEL_GUARD who=guard.sample kind=%s hits=%d total=%d" % [kind, hits, total])
	return float(hits) / float(total)


func _sample_spine_bbox(img: Image, pts: PackedVector2Array, layer: CanvasItem) -> float:
	if img == null or pts.size() < 2:
		return 0.0
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var min_x := 1.0e9
	var min_y := 1.0e9
	var max_x := -1.0e9
	var max_y := -1.0e9
	var any := false
	for p in pts:
		var c: Vector2 = xform * p
		if not c.is_finite():
			continue
		any = true
		min_x = minf(min_x, c.x)
		min_y = minf(min_y, c.y)
		max_x = maxf(max_x, c.x)
		max_y = maxf(max_y, c.y)
	if not any:
		return 0.0
	var pad := 14.0
	var x0 := maxi(0, int(min_x - pad))
	var y0 := maxi(0, int(min_y - pad))
	var x1 := mini(img.get_width() - 1, int(max_x + pad))
	var y1 := mini(img.get_height() - 1, int(max_y + pad))
	if x1 <= x0 or y1 <= y0:
		_log("EOA_RX1_PIXEL_GUARD who=guard.sample_bbox off-screen")
		return 0.0
	# If Bonn/Leverkusen pull the box across the whole theater view, keep a
	# local window around Köln so tan land cannot dominate the ratio.
	if (x1 - x0) * (y1 - y0) > 220 * 220:
		var k := _koln_world()
		var kc: Vector2 = xform * k
		x0 = maxi(0, int(kc.x) - 90)
		y0 = maxi(0, int(kc.y) - 90)
		x1 = mini(img.get_width() - 1, int(kc.x) + 90)
		y1 = mini(img.get_height() - 1, int(kc.y) + 90)
	var hits := 0
	var total := 0
	for yy in range(y0, y1 + 1, 2):
		for xx in range(x0, x1 + 1, 2):
			total += 1
			if _is_road_color(img.get_pixel(xx, yy)):
				hits += 1
	if total <= 0:
		return 0.0
	_log("EOA_RX1_PIXEL_GUARD who=guard.sample_bbox gold=%d total=%d box=%d,%d-%d,%d" % [hits, total, x0, y0, x1, y1])
	return float(hits) / float(total)


func _neighborhood_hit(img: Image, x: int, y: int, kind: String) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var rad := 8 if kind == "road" else SAMPLE_RADIUS
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var xx := x + dx
			var yy := y + dy
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var c := img.get_pixel(xx, yy)
			if kind == "river" and _is_river_color(c):
				return true
			if kind == "road" and _is_road_color(c):
				return true
			if kind == "unit" and _is_unit_chip_color(c):
				return true
	return false


func _is_river_color(c: Color) -> bool:
	# Stroke is Color(0.22, 0.58, 0.92). Do not count North Sea, Mediterranean,
	# or unit-chip cyan bars — those false-passed 816cdc9 at Home/theater zoom.
	var r := c.r * 255.0
	var g := c.g * 255.0
	var b := c.b * 255.0
	if r + g + b < 80.0:
		return false
	if g > 200.0 and b > 200.0 and r < 80.0:
		return false
	var river_d := absf(r - 56.0) + absf(g - 148.0) + absf(b - 235.0)
	if river_d < 110.0:
		return true
	if b > 170.0 and b > g + 35.0 and b > r + 70.0 and r < 110.0 and g > 70.0 and g < 190.0:
		return true
	return false


func _is_road_color(c: Color) -> bool:
	# Gold ROAD_EXPLICIT_COLOR Color(0.92, 0.62, 0.08) ≈ (235, 158, 20).
	# Over GER red the stroke composites to ~ (245, 103, 9). Must not match
	# tan land (~200,170,120) or old tan road (128, 92, 36) so 816cdc9 fails.
	var r := c.r * 255.0
	var g := c.g * 255.0
	var b := c.b * 255.0
	var gold_d := absf(r - 235.0) + absf(g - 158.0) + absf(b - 20.0)
	if gold_d < 110.0:
		return true
	var over_red_d := absf(r - 245.0) + absf(g - 103.0) + absf(b - 9.0)
	if over_red_d < 80.0:
		return true
	if r > 185.0 and g > 65.0 and g < 210.0 and b < 70.0 and r > g + 30.0 and r > b + 90.0:
		return true
	return false


func _is_unit_chip_color(c: Color) -> bool:
	if _is_river_color(c):
		return false
	if _is_road_color(c):
		return false
	var r := c.r * 255.0
	var g := c.g * 255.0
	var b := c.b * 255.0
	# Parchment / tan land
	if r > 160.0 and g > 130.0 and b > 80.0 and b < 170.0 and absf(r - g) < 55.0:
		return false
	# Open sea
	if b > 180.0 and g > 160.0 and r < 120.0:
		return false
	var chroma := maxf(r, maxf(g, b)) - minf(r, minf(g, b))
	var lum := (r + g + b) / 3.0
	if chroma > 35.0 and lum < 210.0:
		return true
	if lum > 20.0 and lum < 150.0 and chroma > 12.0:
		return true
	return false


func _local_course_pts() -> PackedVector2Array:
	var all := _course_pts()
	var k := _koln_world()
	var out := PackedVector2Array()
	for p in all:
		if p.distance_to(k) <= LOCAL_RIVER_WORLD:
			out.append(p)
	if out.size() >= 2:
		return out
	return all


func _course_pts() -> PackedVector2Array:
	var raw := PackedVector2Array()
	var scr: Script = load("res://scripts/map/Rx1RhineCrossing.gd") as Script
	if scr != null and scr.has_method("course_points"):
		raw = scr.call("course_points") as PackedVector2Array
	var canvas_scr: Script = load("res://scripts/map/MapCanvasConfig.gd") as Script
	if canvas_scr != null and canvas_scr.has_method("scale_points"):
		return canvas_scr.call("scale_points", raw) as PackedVector2Array
	var out := PackedVector2Array()
	for p in raw:
		out.append(p * 1.728)
	return out


func _rhine_layer() -> CanvasItem:
	return _find_named("Rx1RhineLayer") as CanvasItem


func _road_layer() -> CanvasItem:
	var n := _find_named("RoadLayer")
	if n is CanvasItem:
		return n as CanvasItem
	var ol := _find_named("InfrastructureOverlayLayer")
	if ol != null:
		var ch := ol.get_node_or_null("RoadLayer")
		if ch is CanvasItem:
			return ch as CanvasItem
	return null


func _spine_pts() -> PackedVector2Array:
	var out := PackedVector2Array()
	var rl := _road_layer()
	if rl != null:
		for c in rl.get_children():
			if not (c is Line2D):
				continue
			var line := c as Line2D
			var explicit := bool(line.get_meta("explicit", false)) or bool(line.get_meta("rx1_gold_spine", false))
			if not explicit:
				continue
			for p in line.points:
				out.append(p)
		if out.size() >= 2:
			return out
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_centroid"):
		var b: Vector2 = mm.call("get_province_centroid", BONN)
		var k: Vector2 = mm.call("get_province_centroid", KOELN)
		var l: Vector2 = mm.call("get_province_centroid", LEV)
		if b != Vector2.ZERO and k != Vector2.ZERO and l != Vector2.ZERO:
			out.append(b)
			out.append(k)
			out.append(l)
			return out
	out.append(Vector2(4257.18 * 1.728, 951.42 * 1.728))
	out.append(Vector2(4254.32 * 1.728, 944.10 * 1.728))
	out.append(Vector2(4254.88 * 1.728, 940.99 * 1.728))
	return out


func _ensure_spine_built() -> void:
	var idm: Node = root.get_node_or_null("InfrastructureDevelopmentManager")
	if idm == null:
		idm = _find_named("InfrastructureDevelopmentManager")
	if idm != null and idm.has_method("link_ix1_road_spine_edges"):
		idm.call("link_ix1_road_spine_edges", KOELN, [BONN, LEV])
	var ol := _find_named("InfrastructureOverlayLayer")
	if ol != null and ol.has_method("rebuild_road_layer"):
		ol.call("rebuild_road_layer")
	_ensure_gold_spine_layer()


func _ensure_gold_spine_layer() -> CanvasItem:
	var ol := _find_named("InfrastructureOverlayLayer")
	if ol != null and ol.has_method("force_paint_ix1_gold_spine"):
		var n: int = int(ol.call("force_paint_ix1_gold_spine"))
		_log("EOA_RX1_PIXEL_GUARD who=guard.gold_spine painted=%d (tip API)" % n)
	var rl := _road_layer()
	if rl != null:
		rl.visible = true
		_log("EOA_RX1_PIXEL_GUARD who=guard.road_layer vis=%s children=%d" % [str(rl.visible), rl.get_child_count()])
	return rl


func _open_inspector(pid: int) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("open_province_inspector_from_search"):
		mr.call("open_province_inspector_from_search", pid)
	elif mr != null and mr.has_method("focus_province_by_id"):
		mr.call("focus_province_by_id", pid, "keep")


func _read_panel(pid: int) -> Dictionary:
	var mr := _map_renderer()
	if mr != null and mr.has_method("rx1_panel_state_report"):
		return mr.call("rx1_panel_state_report", pid) as Dictionary
	return _inspect_panel_nodes(pid)


func _inspect_panel_nodes(pid: int) -> Dictionary:
	var spine_btn := _find_named("BtnBuildRoadSpine") as Button
	var spine_lab := _find_named("LabelSpineProgress") as Label
	var bridge_lab := _find_named("LabelRx1BridgeProgress") as Label
	var list_btn := _find_named("BtnBuildRoadSpineInList") as Button
	var spine_txt := spine_btn.text if spine_btn != null else ""
	var spine_vis := spine_btn != null and spine_btn.visible
	var list_vis := list_btn != null and list_btn.visible
	var offers := (spine_vis and "Build Road Spine" in spine_txt) or (
		list_vis and list_btn != null and "Build Road Spine" in list_btn.text
	)
	var prog := spine_lab.text if spine_lab != null else ""
	var prog_vis := spine_lab != null and spine_lab.visible
	var br := bridge_lab.text if bridge_lab != null else ""
	var br_vis := bridge_lab != null and bridge_lab.visible
	return {
		"pid": pid,
		"offers_build_road_spine": offers,
		"shows_spine_built": prog_vis and ("built" in prog.to_lower() or "complete" in prog.to_lower()),
		"leaks_bridge_on_spine_pid": (pid == KOELN or pid == BONN or pid == LEV) and br_vis and "bridge" in br.to_lower(),
		"leaks_spine_on_bridge_pid": (pid == NEUSS or pid == METTMANN) and (offers or (prog_vis and "spine" in prog.to_lower())),
		"spine_btn": spine_txt,
		"spine_progress": prog,
		"bridge_progress": br,
		"bridge_progress_visible": br_vis,
	}


func _set_units_view(on: bool) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", on)
		_used_direct_unit_hide = false
		return
	# 816cdc9 baseline: no view-only Units toggle. Hide painted nodes
	# directly so units-OFF river/road samples are not covered by chips.
	# Walks DemoUnitIcon_*, StackBadge, PinFocusPulse, LandBattleBubbleLayer,
	# SelectedFrame. Documented in docs/RX1_RHINE_CROSSING.md.
	_hide_unit_nodes_direct(not on)
	_used_direct_unit_hide = true


func _hide_unit_nodes_direct(hide: bool) -> void:
	if root == null:
		return
	_walk_hide_units(root, hide)


func _walk_hide_units(n: Node, hide: bool) -> void:
	if n == null:
		return
	var nm := str(n.name)
	if (
		nm.begins_with("DemoUnitIcon_")
		or nm == "StackBadge"
		or nm == "PinFocusPulse"
		or nm == "LandBattleBubbleLayer"
		or nm == "SelectedFrame"
	):
		if n is CanvasItem:
			(n as CanvasItem).visible = not hide
	for c in n.get_children():
		_walk_hide_units(c, hide)


func _visible_icon_count() -> int:
	var mr := _map_renderer()
	if mr != null and mr.has_method("units_view_report"):
		var rep: Dictionary = mr.call("units_view_report") as Dictionary
		return int(rep.get("visible_icon_count", 0))
	return _count_named_visible(root, "DemoUnitIcon_")


func _count_named_visible(n: Node, prefix: String) -> int:
	if n == null:
		return 0
	var ctn := 0
	if str(n.name).begins_with(prefix) and n is CanvasItem and (n as CanvasItem).visible:
		ctn += 1
	for c in n.get_children():
		ctn += _count_named_visible(c, prefix)
	return ctn


func _units_are_hidden() -> bool:
	var mr := _map_renderer()
	if mr != null and "show_unit_counters" in mr:
		if bool(mr.get("show_unit_counters")):
			return false
		return _visible_icon_count() <= 0
	return _visible_icon_count() <= 0


func _press_units_hotkey() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_hotkey_path")
		return
	var ev := InputEventKey.new()
	ev.keycode = KEY_U
	ev.physical_keycode = KEY_U
	ev.pressed = true
	ev.echo = false
	ev.shift_pressed = false
	ev.ctrl_pressed = false
	ev.alt_pressed = false
	if mr.has_method("_input"):
		mr.call("_input", ev)
	elif mr.has_method("_unhandled_input"):
		mr.call("_unhandled_input", ev)
	else:
		_fail_reasons.append("no_hotkey_path")


func _sim_fingerprint() -> Dictionary:
	var days := -1
	var owner := ""
	var sel_fid := ""
	var sel_pid := -1
	var tm: Node = root.get_node_or_null("TimeManager") if root != null else null
	if tm == null:
		tm = _find_named("TimeManager")
	if tm != null:
		if "total_days_elapsed" in tm:
			days = int(tm.get("total_days_elapsed"))
		elif tm.has_method("get_total_days_elapsed"):
			days = int(tm.call("get_total_days_elapsed"))
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_owner"):
		owner = str(mm.call("get_province_owner", KOELN))
	var mr := _map_renderer()
	if mr != null:
		if "selected_formation_id" in mr:
			sel_fid = str(mr.get("selected_formation_id"))
		if "selected_province_id" in mr:
			sel_pid = int(mr.get("selected_province_id"))
	return {
		"days": days,
		"koln_owner": owner,
		"selected_formation_id": sel_fid,
		"selected_province_id": sel_pid,
	}


func _find_unit_icon() -> Node2D:
	if root == null:
		return null
	return _find_named_prefix(root, "DemoUnitIcon_") as Node2D


func _find_named_prefix(n: Node, prefix: String) -> Node:
	if n == null:
		return null
	if str(n.name).begins_with(prefix) and n is Node2D:
		return n
	for c in n.get_children():
		var hit := _find_named_prefix(c, prefix)
		if hit != null:
			return hit
	return null


func _park_unit_over_river() -> void:
	_restore_parked_unit()
	var icon := _find_unit_icon()
	if icon == null:
		_log("EOA_RX1_PIXEL_GUARD who=guard.park no DemoUnitIcon (units-on sample may fail)")
		return
	var pts := _local_course_pts()
	var dest := _koln_world()
	if pts.size() > 0:
		dest = pts[int(pts.size() / 2)]
	_parked_unit = icon
	_parked_unit_pos = icon.global_position
	icon.global_position = dest
	_log("EOA_RX1_PIXEL_GUARD who=guard.park unit=%s to=%.1f,%.1f (visual only)" % [str(icon.name), dest.x, dest.y])


func _restore_parked_unit() -> void:
	if _parked_unit != null and is_instance_valid(_parked_unit):
		_parked_unit.global_position = _parked_unit_pos
	_parked_unit = null
	_parked_unit_pos = Vector2.ZERO


func _sample_parked_unit(img: Image) -> Dictionary:
	if img == null:
		return {"chip": 0.0, "river": 0.0}
	var icon := _parked_unit
	if icon == null or not is_instance_valid(icon):
		icon = _find_unit_icon()
	if icon == null:
		_log("EOA_RX1_PIXEL_GUARD who=guard.sample_unit no icon")
		return {"chip": 0.0, "river": 0.0}
	var xform := icon.get_global_transform_with_canvas()
	var center: Vector2 = xform * Vector2.ZERO
	var w := img.get_width()
	var h := img.get_height()
	var chip := 0
	var river := 0
	var total := 0
	var rad := 10
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var xx := int(round(center.x)) + dx
			var yy := int(round(center.y)) + dy
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			total += 1
			var c := img.get_pixel(xx, yy)
			if _is_unit_chip_color(c):
				chip += 1
			if _is_river_color(c):
				river += 1
	if total <= 0:
		return {"chip": 0.0, "river": 0.0}
	_log("EOA_RX1_PIXEL_GUARD who=guard.sample_unit chip=%d river=%d total=%d at=%.1f,%.1f" % [
		chip, river, total, center.x, center.y
	])
	return {"chip": float(chip) / float(total), "river": float(river) / float(total)}


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	if process_frame.is_connected(_on_process):
		process_frame.disconnect(_on_process)
	var verdict := "PASS" if ok else "FAIL"
	_log(
		"EOA_RX1_PIXEL_GUARD mid_river=%.3f close_river=%.3f road=%.3f units_on_chip=%.3f units_on_river=%.3f toggle=%s direct_hide=%s koln_offer=%s koln_built=%s koln_bridge_leak=%s neuss_spine_leak=%s %s"
		% [
			_mid_river_hit,
			_close_river_hit,
			_road_hit,
			_units_on_hit,
			_units_on_river_under,
			str(_toggle_ok),
			str(_used_direct_unit_hide),
			str(_koln_panel.get("offers_build_road_spine", "?")),
			str(_koln_panel.get("shows_spine_built", "?")),
			str(_koln_panel.get("leaks_bridge_on_spine_pid", "?")),
			str(_neuss_panel.get("leaks_spine_on_bridge_pid", "?")),
			verdict,
		]
	)
	if not _fail_reasons.is_empty():
		_log("WindowedRx1RhinePixelGuard: fail_reasons=%s" % ",".join(_fail_reasons))
	_log("WindowedRx1RhinePixelGuard: captures=%s" % ",".join(_captures))
	_log("WindowedRx1RhinePixelGuard: RESULT=%s" % verdict)
	quit(0 if ok else 1)
