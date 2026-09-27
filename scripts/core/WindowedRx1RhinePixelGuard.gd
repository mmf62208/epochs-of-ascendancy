extends SceneTree

## WINDOWED (non-headless) RX-1 pixel + panel guard. Not the product Play path.
## Loads the live TestScenario (world_accurate, same F5 smoke scene), frames
## mid and close over Köln/Neuss, captures the viewport, and samples pixels
## along the Rhine polyline and the built Bonn–Köln–Leverkusen spine.
##
##   tools/eoa_rx1_pixel_guard.sh
##   xvfb-run -a tools/run_godot.sh -s res://scripts/core/WindowedRx1RhinePixelGuard.gd
##
## Must FAIL on 816cdc9 (world-width stroke under nation Labels; Köln re-offer;
## Neuss bridge row leaked onto Köln) and PASS on the FIX2 tip.
## Smoke harness is not the product. Artifacts are real viewport captures.

const KOELN := 710417
const BONN := 710416
const LEV := 710418
const NEUSS := 710413
const METTMANN := 710412
const MID_ZOOM := 0.48
const CLOSE_ZOOM := 1.20
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 10
const RIVER_MIN_HIT := 0.18
const ROAD_MIN_HIT := 0.14
const SAMPLE_RADIUS := 3

enum Phase {
	WAIT_MAP,
	SETTLE,
	DO_MID,
	DO_CLOSE,
	DO_ROADS,
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
var _koln_panel: Dictionary = {}
var _neuss_panel: Dictionary = {}
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1


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
	match _phase:
		Phase.WAIT_MAP:
			_tick_wait_map()
		Phase.SETTLE:
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.DO_MID:
			_do_mid()
		Phase.DO_CLOSE:
			_do_close()
		Phase.DO_ROADS:
			_do_roads()
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
		_log("EOA_RX1_PIXEL_GUARD who=guard.wait_map elapsed=%d" % elapsed)
	if not _map_is_ready():
		return
	_log("EOA_RX1_PIXEL_GUARD who=guard.map_ready elapsed=%d" % elapsed)
	_dismiss_title_if_needed()
	_frame_over_koln(MID_ZOOM, true)
	_go_settle(Phase.DO_MID)


func _do_mid() -> void:
	var img := _capture("rx1_pixel_mid_koeln")
	var layer := _rhine_layer()
	_mid_river_hit = _sample_polyline(img, _course_pts(), layer, "river")
	_log("EOA_RX1_PIXEL_GUARD who=guard.mid_river hit=%.3f need>=%.2f" % [_mid_river_hit, RIVER_MIN_HIT])
	if _mid_river_hit < RIVER_MIN_HIT:
		_fail_reasons.append("mid_river_hit")
	_frame_over_koln(CLOSE_ZOOM, true)
	_go_settle(Phase.DO_CLOSE)


func _do_close() -> void:
	var img := _capture("rx1_pixel_close_koeln")
	var layer := _rhine_layer()
	_close_river_hit = _sample_polyline(img, _course_pts(), layer, "river")
	_log("EOA_RX1_PIXEL_GUARD who=guard.close_river hit=%.3f need>=%.2f" % [_close_river_hit, RIVER_MIN_HIT])
	if _close_river_hit < RIVER_MIN_HIT:
		_fail_reasons.append("close_river_hit")
	_ensure_spine_built()
	_frame_over_koln(CLOSE_ZOOM, true)
	_go_settle(Phase.DO_ROADS)


func _do_roads() -> void:
	var img := _capture("rx1_pixel_road_spine")
	var layer := _road_layer()
	if layer == null:
		layer = _rhine_layer()
	_road_hit = _sample_polyline(img, _spine_pts(), layer, "road")
	_log("EOA_RX1_PIXEL_GUARD who=guard.road_spine hit=%.3f need>=%.2f" % [_road_hit, ROAD_MIN_HIT])
	if _road_hit < ROAD_MIN_HIT:
		_fail_reasons.append("road_hit")
	# Reproduce Play MIXED 816cdc9: leftover Neuss bridge chrome must not stick on Köln.
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_rx1_bridge_preview"):
		mr.call("set_rx1_bridge_preview", "built", NEUSS, 100.0)
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
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province"):
		return false
	if mm.call("get_province", KOELN) == null:
		return false
	if _map_renderer() == null:
		return false
	if _title_blocking():
		return false
	return true


func _title_blocking() -> bool:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return false
	if boot is CanvasLayer:
		return (boot as CanvasLayer).visible
	return bool(boot.get("visible"))


func _dismiss_title_if_needed() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null and boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")


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
	var cam := _camera()
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)
		cam.global_position = pos
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
	return Vector2(4254.32, 944.10)


func _capture(name: String) -> Image:
	RenderingServer.force_draw()
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
		var steps := maxi(4, int(a.distance_to(b) / 3.0))
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
		return 0.0
	return float(hits) / float(total)


func _neighborhood_hit(img: Image, x: int, y: int, kind: String) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	for dy in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for dx in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			var xx := x + dx
			var yy := y + dy
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var c := img.get_pixel(xx, yy)
			if kind == "river" and _is_river_color(c):
				return true
			if kind == "road" and _is_road_color(c):
				return true
	return false


func _is_river_color(c: Color) -> bool:
	var r := c.r * 255.0
	var g := c.g * 255.0
	var b := c.b * 255.0
	var river_d := absf(r - 56.0) + absf(g - 148.0) + absf(b - 235.0)
	var halo_d := absf(r - 10.0) + absf(g - 26.0) + absf(b - 51.0)
	if river_d < 140.0:
		return true
	if halo_d < 90.0 and b > r + 8.0:
		return true
	if b > 150.0 and b > r + 40.0 and b > g + 10.0:
		return true
	if b > 90.0 and g > 70.0 and b > r + 25.0 and r < 120.0:
		return true
	return false


func _is_road_color(c: Color) -> bool:
	var r := c.r * 255.0
	var g := c.g * 255.0
	var b := c.b * 255.0
	var d := absf(r - 128.0) + absf(g - 92.0) + absf(b - 36.0)
	if d < 120.0:
		return true
	if r > 90.0 and r < 190.0 and g > 50.0 and g < 150.0 and b < 90.0 and r > g and g > b + 8.0:
		return true
	return false


func _course_pts() -> PackedVector2Array:
	var scr: Script = load("res://scripts/map/Rx1RhineCrossing.gd") as Script
	if scr != null and scr.has_method("course_points"):
		return scr.call("course_points") as PackedVector2Array
	return PackedVector2Array()


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
	out.append(Vector2(4257.18, 951.42))
	out.append(Vector2(4254.32, 944.10))
	out.append(Vector2(4254.88, 940.99))
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
		"EOA_RX1_PIXEL_GUARD mid_river=%.3f close_river=%.3f road=%.3f koln_offer=%s koln_built=%s koln_bridge_leak=%s neuss_spine_leak=%s %s"
		% [
			_mid_river_hit,
			_close_river_hit,
			_road_hit,
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
