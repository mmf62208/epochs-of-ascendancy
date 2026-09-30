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
const VIERSEN := 710414
const OBERBERGISCHER := 710423
const NEUWIED := 710460
const HUNSRUECK := 710464
const PIDS: Array[int] = [VIERSEN, HUNSRUECK, OBERBERGISCHER, NEUWIED]
const CLUSTER_EXPECT_COUNT := 2
const CLUSTER_EXPECT_LEVEL := 4
const NEIGHBOR_PID := NEUWIED
const MID_ZOOM := 0.99
const OPS_ZOOM := 1.30
const CLOSE_ZOOM := 2.27
const OUT_ZOOM := 0.28
const OCCL_ZOOMS: Array[float] = [0.70, 0.99, 1.30, 1.35, 1.90, 2.30]
const CLUSTER_OCCL_ZOOMS: Array[float] = [0.70, 0.99, 1.30]
const OVERLAP_ZOOMS: Array[float] = [0.70, 0.99, 1.30, 1.90, 2.30]
const RX1_MID_ZOOM := 0.95
const RX1_MID_RIVER_MATCH := 0.02
const RX1_LOCAL_RIVER_WORLD := 120.0
const RX1_RIVER_NEIGHBOR := 5
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 48
const RSS_LIMIT_MB := 3000
const ANCHOR_MIN_HITS := 6
const SAMPLE_RADIUS := 28
const OCCLUSION_MAX := 0.05

enum Phase {
	WAIT_MAP,
	SETTLE,
	FRAME_MID,
	POLITICAL_MID,
	FRAME_OPS,
	POLITICAL_OPS,
	FRAME_CLOSE,
	POLITICAL_CLOSE,
	FRAME_OUT,
	ZOOMED_OUT,
	SWITCH_RESOURCES,
	RESOURCES,
	SWITCH_BACK,
	BACK,
	OCCLUSION,
	RX1_CROSSCHECK,
	OVERLAP,
	OWNERSHIP,
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
var _cam_pos: Vector2 = Vector2.ZERO
var _mid_anchors: int = 0
var _close_anchors: int = 0
var _out_anchors: int = 0
var _res_anchors: int = 0
var _back_anchors: int = 0
var _layer_mid: int = -1
var _layer_out: int = -1
var _layer_res: int = -1
var _layer_back: int = -1
var _fix2_dir: String = ""
var _fix2b_dir: String = ""
var _fix2c_dir: String = ""
var _occl_max: float = 0.0
var _rx1_mid_on: float = -1.0
var _rx1_mid_off: float = -1.0
var _counter_drawn_ok: bool = false
var _overlap_fail: int = 0
var _own_fail: int = 0
var _cluster_mid_ok: bool = false
var _split_close_ok: bool = false
var _counter_clear_ok: bool = false
var _badge_px: float = 0.0
var _occl_i: int = 0
var _overlap_i: int = 0


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
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/fac1a_fix2")
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/fac1a_fix2b")
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/fac1a_fix2c")
	_fix2_dir = "/opt/cursor/artifacts/fac1a_fix2"
	_fix2b_dir = "/opt/cursor/artifacts/fac1a_fix2b"
	_fix2c_dir = "/opt/cursor/artifacts/fac1a_fix2c"
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
	_reassert_camera()
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
		Phase.FRAME_OPS:
			_do_frame(OPS_ZOOM, Phase.POLITICAL_OPS)
		Phase.POLITICAL_OPS:
			_do_political_ops()
		Phase.FRAME_CLOSE:
			_park_unit_on_koeln()
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
		Phase.OCCLUSION:
			_do_occlusion()
		Phase.RX1_CROSSCHECK:
			_do_rx1_crosscheck()
		Phase.OVERLAP:
			_do_overlap()
		Phase.OWNERSHIP:
			_do_ownership()
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
	var ol_boot := _facility_layer()
	if ol_boot != null and ol_boot.has_method("rebuild_icon_list"):
		ol_boot.call("rebuild_icon_list")
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
	_badge_px = _badge_px_now()
	if _badge_px + 0.01 < 16.0:
		_fail_reasons.append("badge_px_%.1f" % _badge_px)
	_capture("fac1a_political_mid_NOT_live_play")
	_capture_fix2("02_mid_z0.99_badges_or_cluster_NOT_live_play")
	_capture_fix2b("02_mid_z0.99_cluster_NOT_live_play")
	_capture_fix2c("02_mid_z0.99_cluster_NOT_live_play")
	_cluster_mid_ok = _assert_cluster_at_zoom(MID_ZOOM)
	_log_pair_worlds()
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.mid anchors=%d layer=%d zoom=%.3f badge=%.1f cluster=%s (NOT live Play)" % [_mid_anchors, _layer_mid, _cam_zoom, _badge_px, str(_cluster_mid_ok)])
	if not _cluster_mid_ok:
		_fail_reasons.append("mid_cluster_missing")
	_go_settle(Phase.FRAME_OPS)


func _do_political_ops() -> void:
	_set_mode("political")
	_hide_unit_noise()
	_redraw_layer()
	var hits := _sample_anchor_hits()
	_capture("fac1a_political_ops_NOT_live_play")
	_capture_fix2("01_operational_z1.30_all4_airfields_NOT_live_play")
	_capture_fix2b("01_operational_z1.30_rhineland_NOT_live_play")
	_capture_fix2c("01_operational_z1.30_rhineland_NOT_live_play")
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.ops anchors=%d zoom=%.3f (NOT live Play)" % [hits, _cam_zoom])
	if hits < 1:
		_fail_reasons.append("ops_missing_icons")
	_go_settle(Phase.FRAME_CLOSE)


func _do_political_close() -> void:
	_set_mode("political")
	_hide_unit_noise()
	_redraw_layer()
	_close_anchors = _sample_anchor_hits()
	_show_units()
	_redraw_layer()
	_counter_drawn_ok = _koeln_counter_rect(CLOSE_ZOOM).size.x > 1.0
	_capture("fac1a_political_close_NOT_live_play")
	_capture_fix2("03_close_koln_z2.27_counters_NOT_live_play")
	_capture_fix2b("03_close_koln_bonn_z2.27_counter_NOT_live_play")
	_capture_fix2c("03_close_koln_bonn_z2.27_counter_NOT_live_play")
	_split_close_ok = _assert_split_at_zoom(CLOSE_ZOOM)
	_counter_clear_ok = _assert_neighbor_clears_counter()
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.close anchors=%d zoom=%.3f split=%s counter_clear=%s counter_drawn=%s (NOT live Play)" % [_close_anchors, _cam_zoom, str(_split_close_ok), str(_counter_clear_ok), str(_counter_drawn_ok)])
	if _close_anchors < 1:
		_fail_reasons.append("close_missing_icons")
	if not _split_close_ok:
		_fail_reasons.append("close_cluster_not_split")
	if not _counter_drawn_ok:
		_fail_reasons.append("close_counter_not_drawn")
	if not _counter_clear_ok:
		_fail_reasons.append("close_counter_overlap")
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
	if not _assert_cluster_at_zoom(MID_ZOOM):
		_fail_reasons.append("back_cluster_missing")
	_occl_i = 0
	_go_settle(Phase.OCCLUSION)


func _do_occlusion() -> void:
	if _occl_i >= OCCL_ZOOMS.size():
		_go_settle(Phase.RX1_CROSSCHECK)
		return
	var z: float = OCCL_ZOOMS[_occl_i]
	_frame_over_rhineland(z)
	_hide_unit_noise()
	_set_mode("political")
	var ol := _facility_layer()
	if ol != null and ol.has_method("set_show_facilities"):
		ol.call("set_show_facilities", true)
	_redraw_layer()
	var on_img := _grab()
	if ol != null and ol.has_method("set_show_facilities"):
		ol.call("set_show_facilities", false)
	_redraw_layer()
	var off_img := _grab()
	if ol != null and ol.has_method("set_show_facilities"):
		ol.call("set_show_facilities", true)
	var frac := _occlusion_frac(on_img, off_img, z)
	_occl_max = maxf(_occl_max, frac)
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.occlusion z=%.2f frac=%.3f need<=0.05 (NOT live Play)" % [z, frac])
	if frac > OCCLUSION_MAX + 0.0001:
		_fail_reasons.append("occlusion_z%.2f_%.3f" % [z, frac])
	_occl_i += 1
	_go_settle(Phase.OCCLUSION)


func _do_rx1_crosscheck() -> void:
	## Same pose as WindowedRx1RhinePixelGuard mid (Köln, 0.95). Icons ON vs
	## OFF mid_river must match within 0.02 so a cluster-on-Rhine cannot
	## hide behind FAC-1a individual-icon occlusion.
	_hide_unit_noise()
	_set_mode("political")
	var kc := _mm_centroid(KOELN)
	if kc == Vector2.ZERO:
		kc = _centroid(KOELN)
	_apply_camera(kc, RX1_MID_ZOOM)
	_sync_close_layers(RX1_MID_ZOOM)
	var ol := _facility_layer()
	if ol != null and ol.has_method("set_show_facilities"):
		ol.call("set_show_facilities", true)
	_redraw_layer()
	var on_img := _grab()
	if ol != null and ol.has_method("set_show_facilities"):
		ol.call("set_show_facilities", false)
	_redraw_layer()
	var off_img := _grab()
	if ol != null and ol.has_method("set_show_facilities"):
		ol.call("set_show_facilities", true)
	_rx1_mid_on = _sample_rx1_mid_river(on_img)
	_rx1_mid_off = _sample_rx1_mid_river(off_img)
	var d := absf(_rx1_mid_on - _rx1_mid_off)
	_log(
		"EOA_FAC1A_PIXEL_GUARD who=guard.rx1_mid_river on=%.3f off=%.3f d=%.3f need<=%.2f (NOT live Play)"
		% [_rx1_mid_on, _rx1_mid_off, d, RX1_MID_RIVER_MATCH]
	)
	if d > RX1_MID_RIVER_MATCH + 0.0001:
		_fail_reasons.append("rx1_mid_river_d_%.3f" % d)
	_overlap_i = 0
	_go_settle(Phase.OVERLAP)


func _sync_close_layers(zoom: float) -> void:
	var labels: Node = _find_named("PoliticalLabelsLayer")
	if labels != null and labels.has_method("sync_camera_zoom"):
		labels.call("sync_camera_zoom", zoom)
	var rhine: Node = _find_named("Rx1RhineLayer")
	if rhine != null and rhine.has_method("refresh"):
		rhine.call("refresh")
	var iol := _find_named("InfrastructureOverlayLayer")
	if iol != null and iol.has_method("refresh_ix1_gold_spine"):
		iol.call("refresh_ix1_gold_spine", true)
	var gold: Node = _find_named("Ix1GoldSpine")
	if gold != null and gold.has_method("redraw_gold_spine"):
		gold.call("redraw_gold_spine")


func _sample_rx1_mid_river(img: Image) -> float:
	if img == null:
		return 0.0
	var pts := _rx1_local_course_pts()
	var layer := _find_named("Rx1RhineLayer") as CanvasItem
	if pts.size() < 2:
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
			if _rx1_river_neighborhood(img, ix, iy):
				hits += 1
	if total <= 0:
		return 0.0
	return float(hits) / float(total)


func _rx1_local_course_pts() -> PackedVector2Array:
	var raw := PackedVector2Array()
	var scr: Script = load("res://scripts/map/Rx1RhineCrossing.gd") as Script
	if scr != null and scr.has_method("course_points"):
		raw = scr.call("course_points") as PackedVector2Array
	var scaled := PackedVector2Array()
	for p in raw:
		scaled.append(p * 1.728)
	var k := _mm_centroid(KOELN)
	if k == Vector2.ZERO:
		return scaled
	var out := PackedVector2Array()
	for p in scaled:
		if p.distance_to(k) <= RX1_LOCAL_RIVER_WORLD:
			out.append(p)
	if out.size() >= 2:
		return out
	return scaled


func _rx1_river_neighborhood(img: Image, x: int, y: int) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var rad := RX1_RIVER_NEIGHBOR
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var xx := x + dx
			var yy := y + dy
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			if _is_rx1_river_color(img.get_pixel(xx, yy)):
				return true
	return false


func _is_rx1_river_color(c: Color) -> bool:
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


func _do_overlap() -> void:
	if _overlap_i >= OVERLAP_ZOOMS.size():
		_go_settle(Phase.OWNERSHIP)
		return
	var z: float = OVERLAP_ZOOMS[_overlap_i]
	_frame_over_rhineland(z)
	_park_unit_on_koeln()
	_show_units()
	_set_mode("political")
	_redraw_layer()
	var ol := _facility_layer()
	var markers: Array = []
	if ol != null and ol.has_method("compute_markers_at_zoom"):
		markers = ol.call("compute_markers_at_zoom", z)
	elif ol != null and ol.has_method("get_last_markers"):
		markers = ol.call("get_last_markers")
	var hit := false
	for i in range(markers.size()):
		var a: Rect2 = (markers[i] as Dictionary).get("rect", Rect2()) as Rect2
		for j in range(i + 1, markers.size()):
			var b: Rect2 = (markers[j] as Dictionary).get("rect", Rect2()) as Rect2
			if a.intersects(b):
				hit = true
		if z + 0.001 >= 2.20:
			var counter := _koeln_counter_rect(z)
			if counter.size.x > 1.0 and a.intersects(counter):
				hit = true
				_fail_reasons.append("overlap_counter_z%.2f" % z)
	if hit:
		_overlap_fail += 1
		_fail_reasons.append("overlap_z%.2f" % z)
	if z + 0.001 >= 1.90 and not _assert_split_at_zoom(z):
		hit = true
		_fail_reasons.append("split_z%.2f" % z)
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.overlap z=%.2f markers=%d hit=%s (NOT live Play)" % [z, markers.size(), str(hit)])
	_overlap_i += 1
	_go_settle(Phase.OVERLAP)


func _do_ownership() -> void:
	var mm := root.get_node_or_null("MapManager")
	var ol := _facility_layer()
	if mm == null or ol == null:
		_fail_reasons.append("ownership_no_mm")
		_finish(_fail_reasons.is_empty())
		return
	for z in OVERLAP_ZOOMS:
		_frame_over_rhineland(z)
		_redraw_layer()
		for pid in PIDS:
			var world: Vector2 = ol.call("get_draw_world", pid)
			var hit := -1
			if mm.has_method("get_province_at_world_pos"):
				hit = int(mm.call("get_province_at_world_pos", world, true))
			if hit != pid:
				_own_fail += 1
				_fail_reasons.append("own_z%.2f_pid%d_hit%d" % [z, pid, hit])
				_log("EOA_FAC1A_PIXEL_GUARD who=guard.own FAIL z=%.2f pid=%d hit=%d" % [z, pid, hit])
			else:
				_log("EOA_FAC1A_PIXEL_GUARD who=guard.own z=%.2f pid=%d hit=%d" % [z, pid, hit])
	_finish(_fail_reasons.is_empty())


func _badge_px_now() -> float:
	var ol := _facility_layer()
	if ol != null and ol.has_method("get_badge_screen_px"):
		return float(ol.call("get_badge_screen_px", _cam_zoom))
	return 0.0


func _capture_fix2(name: String) -> void:
	if _fix2_dir.is_empty():
		return
	var prev := _out_dir
	_out_dir = _fix2_dir
	_capture(name)
	_out_dir = prev


func _capture_fix2b(name: String) -> void:
	if _fix2b_dir.is_empty():
		return
	var prev := _out_dir
	_out_dir = _fix2b_dir
	_capture(name)
	_out_dir = prev


func _capture_fix2c(name: String) -> void:
	if _fix2c_dir.is_empty():
		return
	var prev := _out_dir
	_out_dir = _fix2c_dir
	_capture(name)
	_out_dir = prev


func _markers_at(zoom: float) -> Array:
	var ol := _facility_layer()
	if ol == null:
		return []
	if ol.has_method("compute_markers_at_zoom"):
		return ol.call("compute_markers_at_zoom", zoom)
	if ol.has_method("get_last_markers"):
		return ol.call("get_last_markers")
	return []


func _log_pair_worlds() -> void:
	var ol := _facility_layer()
	if ol == null or not ol.has_method("get_draw_world"):
		return
	for i in range(PIDS.size()):
		var a: int = PIDS[i]
		var wa: Vector2 = ol.call("get_draw_world", a)
		for j in range(i + 1, PIDS.size()):
			var b: int = PIDS[j]
			var wb: Vector2 = ol.call("get_draw_world", b)
			_log(
				"EOA_FAC1A_PIXEL_GUARD who=guard.pair a=%d b=%d world=%.2f (NOT live Play)"
				% [a, b, wa.distance_to(wb)]
			)


func _assert_cluster_at_zoom(zoom: float) -> bool:
	var markers := _markers_at(zoom)
	for rec_v in markers:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if bool(rec.get("cluster", false)) and int(rec.get("count", 0)) >= CLUSTER_EXPECT_COUNT and int(rec.get("level", 0)) == CLUSTER_EXPECT_LEVEL:
			_log("EOA_FAC1A_PIXEL_GUARD who=guard.cluster z=%.2f count=%d level=%d (NOT live Play)" % [zoom, int(rec.get("count", 0)), int(rec.get("level", 0))])
			return true
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.cluster MISS z=%.2f markers=%d (NOT live Play)" % [zoom, markers.size()])
	return false


func _assert_split_at_zoom(zoom: float) -> bool:
	var markers := _markers_at(zoom)
	if markers.size() < 4:
		_log("EOA_FAC1A_PIXEL_GUARD who=guard.split FAIL z=%.2f markers=%d (NOT live Play)" % [zoom, markers.size()])
		return false
	for rec_v in markers:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		if bool((rec_v as Dictionary).get("cluster", false)):
			_log("EOA_FAC1A_PIXEL_GUARD who=guard.split FAIL still_clustered z=%.2f (NOT live Play)" % zoom)
			return false
	for i in range(markers.size()):
		var a: Rect2 = (markers[i] as Dictionary).get("rect", Rect2()) as Rect2
		for j in range(i + 1, markers.size()):
			var b: Rect2 = (markers[j] as Dictionary).get("rect", Rect2()) as Rect2
			if a.intersects(b):
				_log("EOA_FAC1A_PIXEL_GUARD who=guard.split FAIL overlap z=%.2f (NOT live Play)" % zoom)
				return false
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.split z=%.2f markers=%d (NOT live Play)" % [zoom, markers.size()])
	return true


func _assert_neighbor_clears_counter() -> bool:
	var markers := _markers_at(CLOSE_ZOOM)
	var counter := _koeln_counter_rect(CLOSE_ZOOM)
	if counter.size.x <= 1.0:
		_log("EOA_FAC1A_PIXEL_GUARD who=guard.counter no_chip (NOT live Play)")
		return false
	for rec_v in markers:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if int(rec.get("pid", -1)) != NEIGHBOR_PID:
			continue
		var r: Rect2 = rec.get("rect", Rect2()) as Rect2
		if r.intersects(counter):
			_log("EOA_FAC1A_PIXEL_GUARD who=guard.counter INTERSECT neighbor=%d (NOT live Play)" % NEIGHBOR_PID)
			return false
		_log("EOA_FAC1A_PIXEL_GUARD who=guard.counter clear neighbor=%d (NOT live Play)" % NEIGHBOR_PID)
		return true
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.counter missing_neighbor=%d (NOT live Play)" % NEIGHBOR_PID)
	return false


func _grab() -> Image:
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()


func _is_gold_or_river(c: Color) -> bool:
	if c.a < 0.35:
		return false
	var gold := c.r > 0.62 and c.g > 0.48 and c.b < 0.42 and c.s > 0.28
	var river := c.b > 0.38 and c.b > c.r + 0.08 and c.b > c.g * 0.85 and c.s > 0.18
	return gold or river


func _occlusion_frac(on_img: Image, off_img: Image, zoom: float = -1.0) -> float:
	if on_img == null or off_img == null:
		return 0.0
	var cam := _camera()
	if cam == null:
		return 0.0
	var w := mini(on_img.get_width(), off_img.get_width())
	var h := mini(on_img.get_height(), off_img.get_height())
	var acc: Array[int] = [0, 0]
	## Neighborhood around each airfield draw-world (where icons actually sit).
	for pid in PIDS:
		_acc_cover(acc, on_img, off_img, cam, _centroid(pid), 40, w, h)
	## Cluster markers are larger and were unsampled — mid_river 0.749→0.631
	## false-passed while individual interiors stayed off the Rhine.
	if zoom >= 0.0:
		for rec_v in _markers_at(zoom):
			if typeof(rec_v) != TYPE_DICTIONARY:
				continue
			var rec: Dictionary = rec_v
			if not bool(rec.get("cluster", false)):
				continue
			var cw: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
			if cw != Vector2.ZERO:
				_acc_cover(acc, on_img, off_img, cam, cw, 52, w, h)
				_log("EOA_FAC1A_PIXEL_GUARD who=guard.occl_cluster z=%.2f world=%.1f,%.1f count=%d (NOT live Play)" % [zoom, cw.x, cw.y, int(rec.get("count", 0))])
	## In-game gold spine + Rhine walk (Bonn–Köln–Lev + Neuss + Düsseldorf–Duisburg).
	## FIX #1 s1_gold_cover false-passed because S1 never sampled Neuss / the
	## Leverkusen cap — only Bonn/Köln/Lev centroids. Walk those centroids PLUS
	## Neuss and the segments between them so close-zoom spine pixels count.
	var spine_pids: Array[int] = [710416, 710417, 710418, 710413, 710401, 710402]
	var spine_pts: Array[Vector2] = []
	for sp in spine_pids:
		var c := _mm_centroid(sp)
		if c != Vector2.ZERO:
			spine_pts.append(c)
			_acc_cover(acc, on_img, off_img, cam, c, 22, w, h)
	for i in range(maxi(spine_pts.size() - 1, 0)):
		var a: Vector2 = spine_pts[i]
		var b: Vector2 = spine_pts[i + 1]
		for t in range(1, 6):
			var p: Vector2 = a.lerp(b, float(t) / 6.0)
			_acc_cover(acc, on_img, off_img, cam, p, 14, w, h)
	if acc[0] <= 0:
		return 0.0
	return float(acc[1]) / float(acc[0])


func _acc_cover(acc: Array[int], on_img: Image, off_img: Image, cam: Camera2D, world: Vector2, rad: int, w: int, h: int) -> void:
	var screen: Vector2 = cam.get_canvas_transform() * world
	var cx := int(round(screen.x))
	var cy := int(round(screen.y))
	for y in range(cy - rad, cy + rad + 1, 2):
		for x in range(cx - rad, cx + rad + 1, 2):
			if x < 2 or y < 2 or x >= w - 2 or y >= h - 2:
				continue
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) > rad * rad:
				continue
			if not _is_gold_or_river(off_img.get_pixel(x, y)):
				continue
			acc[0] += 1
			if not _is_gold_or_river(on_img.get_pixel(x, y)):
				acc[1] += 1


func _mm_centroid(pid: int) -> Vector2:
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", pid)
		if c != Vector2.ZERO:
			return c
	return Vector2.ZERO


func _park_unit_on_koeln() -> void:
	var parked := false
	var lm := root.get_node_or_null("LeaderManager")
	if lm == null:
		lm = _find_named("LeaderManager")
	var list: Array = []
	if lm != null and lm.has_method("get_formations_for_country"):
		var raw: Variant = lm.call("get_formations_for_country", "GER")
		if raw is Array:
			list = raw as Array
	elif lm != null and "formations" in lm:
		var fd: Variant = lm.get("formations")
		if fd is Dictionary:
			list = (fd as Dictionary).values()
		elif fd is Array:
			list = fd as Array
	for f_v in list:
		if typeof(f_v) != TYPE_OBJECT:
			continue
		var f: Object = f_v as Object
		var tag := str(f.get("owner_tag") if "owner_tag" in f else "").to_upper()
		if tag != "" and tag != "GER":
			continue
		var ftype := str(f.get("formation_type") if "formation_type" in f else "").to_lower()
		if ftype != "" and ftype.find("fleet") >= 0:
			continue
		if ftype != "" and ftype.find("air") >= 0:
			continue
		if "stationed_province_id" in f:
			f.set("stationed_province_id", KOELN)
			parked = true
			_log("EOA_FAC1A_PIXEL_GUARD who=guard.park_koeln fid=%s" % str(f.get("id")))
			break
	var mr := _map_renderer()
	if mr != null and mr.has_method("mv1_rebuild_unit_icons"):
		mr.call("mv1_rebuild_unit_icons")
	elif mr != null and mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint")
	if not parked:
		_log("EOA_FAC1A_PIXEL_GUARD who=guard.park_koeln none")
	var kc := _mm_centroid(KOELN)
	if kc != Vector2.ZERO:
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if str(n.name).begins_with("DemoUnitIcon") and n is Node2D:
				if (n as Node2D).global_position.distance_to(kc) < 80.0:
					(n as Node2D).global_position = kc
					break
			for ch in n.get_children():
				stack.append(ch)


func _show_units() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", true)
	if mr != null and mr.has_method("mv1_rebuild_unit_icons"):
		mr.call("mv1_rebuild_unit_icons")
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if str(n.name).begins_with("DemoUnitIcon") and n is CanvasItem:
			(n as CanvasItem).visible = true
		for ch in n.get_children():
			stack.append(ch)


func _koeln_counter_rect(zoom: float = -1.0) -> Rect2:
	var cam := _camera()
	if cam == null:
		return Rect2()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if str(n.name).begins_with("DemoUnitIcon") and n is CanvasItem and (n as CanvasItem).visible:
			var world := (n as Node2D).global_position if n is Node2D else Vector2.ZERO
			## compute_markers_at_zoom rects are world*zoom (translation cancels).
			var scr: Vector2 = world * zoom if zoom >= 0.0 else cam.get_canvas_transform() * world
			var half := Vector2(28, 20)
			var r := Rect2(scr - half, half * 2.0)
			var mm := root.get_node_or_null("MapManager")
			if mm != null and mm.has_method("get_province_centroid"):
				var kc: Vector2 = mm.call("get_province_centroid", KOELN)
				if world.distance_to(kc) < 48.0:
					return r
		for ch in n.get_children():
			stack.append(ch)
	## No synthetic Köln box — a fallback 80×56 at the centroid false-overlapped
	## nearby icons at mid zoom when no chip was actually there.
	return Rect2()


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
	## Ink airfield only — do not count political country fill (GER red matched dirt).
	var brass := c.r > 0.62 and c.g > 0.42 and c.g < 0.82 and c.b < 0.38 and c.s > 0.38
	var dirt := c.r > 0.58 and c.g > 0.30 and c.g < 0.58 and c.b < 0.28 and c.s > 0.40
	var asphalt := c.s < 0.12 and c.v > 0.28 and c.v < 0.48 and absf(c.r - c.g) < 0.05 and absf(c.g - c.b) < 0.05
	return brass or dirt or asphalt


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


func _sites_focus_world() -> Vector2:
	var acc := Vector2.ZERO
	var n := 0
	for pid in PIDS:
		var c := _centroid(pid)
		if c != Vector2.ZERO:
			acc += c
			n += 1
	if n <= 0:
		return _centroid(KOELN)
	return acc / float(n)


func _frame_over_rhineland(zoom: float) -> void:
	## Guard-only pose. Product Play still uses the player camera / wheel.
	## Home / Close / TestRunner were winning player_path_wheel (xvfb sat on
	## Europe Home). Pin the same way RX-1 does — lock_pixel_guard_camera.
	var pos := _sites_focus_world()
	if zoom + 0.001 >= 2.0:
		## Play Search+Go Köln at close: counter centered, Neuwied beside it.
		var kc := _mm_centroid(KOELN)
		if kc == Vector2.ZERO:
			kc = _centroid(KOELN)
		var nb := _centroid(NEIGHBOR_PID)
		if kc != Vector2.ZERO and nb != Vector2.ZERO:
			pos = kc.lerp(nb, 0.42)
		else:
			pos = kc
	_freeze_boot_camera_fighters()
	var mr := _map_renderer()
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	if mr != null and "info_panel" in mr:
		var ip: Variant = mr.get("info_panel")
		if ip is Control:
			(ip as Control).visible = false
	_apply_camera(pos, zoom)
	_sync_close_layers(zoom)
	_ensure_not_live_banner()
	var live_z := _cam_zoom
	var live_p := pos
	var cam_f := _camera()
	if cam_f != null:
		live_z = maxf(absf(cam_f.zoom.x), absf(cam_f.zoom.y))
		live_p = cam_f.global_position
	_log("EOA_FAC1A_PIXEL_GUARD who=guard.frame want=%.2f got=%.3f pos=%.1f,%.1f live=%.1f,%.1f (NOT live Play)" % [zoom, live_z, pos.x, pos.y, live_p.x, live_p.y])


func _apply_camera(pos: Vector2, zoom: float) -> void:
	if pos == Vector2.ZERO:
		return
	_cam_pos = pos
	_cam_zoom = zoom
	var mr := _map_renderer()
	if mr != null and mr.has_method("lock_pixel_guard_camera"):
		mr.call("lock_pixel_guard_camera", pos, zoom)
	elif mr != null:
		mr.set("_close_camera_lock_pos", pos)
		mr.set("_close_camera_lock_zoom", Vector2(zoom, zoom))
		mr.set("_close_camera_locked", true)
	var cam := _camera()
	if cam != null:
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
		_cam_zoom = zoom


func _reassert_camera() -> void:
	if _cam_pos == Vector2.ZERO:
		return
	_apply_camera(_cam_pos, _cam_zoom)


func _freeze_boot_camera_fighters() -> void:
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", true)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_close_camera_locked", true)
		mr.set("_hold_camera_until_msec", Time.get_ticks_msec() + 120000)
		## Home / theater auto-fit were resetting MapCamera after lock so
		## composites stayed on Europe. Guard-only; product Play untouched.
		if mr.has_method("set_process"):
			mr.set_process(false)
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


func _wheel_to_min_zoom(target_zoom: float) -> void:
	var mr := _map_renderer()
	var cam := _camera()
	if mr == null or cam == null or not mr.has_method("_zoom_toward_mouse"):
		return
	var world := _sites_focus_world()
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
	var world := _sites_focus_world()
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
	_frame_over_rhineland(_cam_zoom)
	_ensure_not_live_banner()
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var cam := _camera()
	if cam != null:
		_log(
			"EOA_FAC1A_PIXEL_GUARD who=guard.capture_cam want=%.3f got=%.3f pos=%.1f,%.1f (NOT live Play)"
			% [_cam_zoom, maxf(cam.zoom.x, cam.zoom.y), cam.global_position.x, cam.global_position.y]
		)
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
		"WindowedFac1aAirfieldPixelGuard: RESULT=%s mid=%d close=%d out=%d res=%d back=%d layer=%d/%d/%d/%d badge=%.1f occl_max=%.3f overlap_fail=%d own_fail=%d cluster_mid=%s split_close=%s counter_clear=%s counter_drawn=%s rx1_mid_on=%.3f rx1_mid_off=%.3f rss_mb=%.1f peak_kb=%d captures=%s reasons=%s (xvfb NOT live Play)"
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
			_badge_px,
			_occl_max,
			_overlap_fail,
			_own_fail,
			str(_cluster_mid_ok),
			str(_split_close_ok),
			str(_counter_clear_ok),
			str(_counter_drawn_ok),
			_rx1_mid_on,
			_rx1_mid_off,
			rss_mb,
			_rss_peak_kb,
			str(_captures),
			str(_fail_reasons),
		]
	)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
