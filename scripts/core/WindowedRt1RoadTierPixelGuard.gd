extends SceneTree

## WINDOWED RT-1 pixel guard. Smoke harness is not the product.
## Captures far/default/close × dirt/paved/highway, soft-note S1/S2, RSS.
## On 497731dd this FAILs (no political inferred roads / no labels / select z=80).
##
##   tools/eoa_rt1_pixel_guard.sh
##   xvfb-run -a tools/run_godot.sh -s res://scripts/core/WindowedRt1RoadTierPixelGuard.gd

const KOELN := 710417
const BONN := 710416
const LEV := 710418
const DIRT_A := 710425 ## Rhein-Sieg
const DIRT_B := 710416 ## Bonn
const PAVED_A := 710420 ## Rhein-Erft
const PAVED_B := 710413 ## Neuss
const HWY_A := 710412 ## Mettmann
const HWY_B := 710424 ## Rheinisch-Bergischer
const FAR_ZOOM := 0.32
const MID_ZOOM := 1.80
const CLOSE_ZOOM := 3.20
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 36
const GOLD_COVER_MIN := 0.90
const WIDTH_TOL := 2.75
## HWY3_FAR_WIDTH_CEILING=26 — max-of-orientations inflates far past this.
const HWY3_FAR_WIDTH_CEILING := 26.0
## HWY3_DEFAULT_WIDTH_CEILING=18
const HWY3_DEFAULT_WIDTH_CEILING := 18.0
## HWY3_PAIR_SCREEN_POS_MAX=28 — sampled run vs landmark-projected pair midpoint.
const HWY3_PAIR_SCREEN_POS_MAX := 28.0

enum Phase {
	WAIT_MAP,
	SETTLE,
	SEED,
	MATRIX_SETTLE,
	MATRIX_CAPTURE,
	SOFT,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.SEED
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _matrix_i: int = 0
var _matrix_dismiss_pending: bool = false
var _width_hits: Dictionary = {}
var _soft: Dictionary = {}
var _rss_start_kb: int = 0
var _rss_end_kb: int = 0
## HWY3_FIXED_ORIENTATION=1 — one landmark-derived Y orientation, never max-of-orientations.
var _image_y_flipped: bool = false
var _orient_ready: bool = false
var _hwy_sample: Vector2i = Vector2i(HWY_A, HWY_B)


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedRt1RoadTierPixelGuard: DisplayServer=%s" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_out_dir = OS.get_environment("EOA_RT1_PIXEL_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-rt1-pixel"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/rt1-pixel")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_rss_start_kb = _rss_kb()
	_log("EOA_RT1_PIXEL_GUARD who=guard.boot out=%s rss_kb=%d (NOT product Begin/Esc/clock PASS)" % [
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
		Phase.SEED:
			_do_seed()
		Phase.MATRIX_SETTLE:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = Phase.MATRIX_CAPTURE
		Phase.MATRIX_CAPTURE:
			_do_matrix_capture()
		Phase.SOFT:
			_do_soft()
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
		_log("EOA_RT1_PIXEL_GUARD who=guard.wait_map elapsed=%d title=%s closed=%s n=%d" % [
			elapsed,
			str(_find_named("LivingTitleBoot") != null),
			str(_title_has_closed()),
			_province_count(),
		])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("rt1_ready_msec", 0)) == 0:
		root.set_meta("rt1_ready_msec", Time.get_ticks_msec())
		_log("EOA_RT1_PIXEL_GUARD who=guard.map_ready elapsed=%d n=%d (hold 2s then frame)" % [
			elapsed, _province_count()
		])
		return
	if Time.get_ticks_msec() - int(root.get_meta("rt1_ready_msec", 0)) < 2000:
		return
	_log("EOA_RT1_PIXEL_GUARD who=guard.frame_start elapsed=%d n=%d path=player" % [elapsed, _province_count()])
	_pause_clock_only()
	_force_political_clean()
	_set_units_view(false)
	_ensure_spine_built()
	_frame_over_koln(MID_ZOOM, true)
	_go_settle(Phase.SEED)


func _do_seed() -> void:
	_seed_sample_infra()
	var ol := _overlay()
	if ol == null or not ol.has_method("get_road_tier_cache"):
		_fail_reasons.append("no_road_tier_cache_api")
		_finish(false)
		return
	if ol.has_method("rebuild_road_layer"):
		ol.call("rebuild_road_layer")
	_log("EOA_RT1_PIXEL_GUARD who=guard.seed cache=%d rebuilds=%s" % [
		(ol.call("get_road_tier_cache") as Array).size() if ol.has_method("get_road_tier_cache") else -1,
		str(ol.call("get_road_cache_rebuild_count")) if ol.has_method("get_road_cache_rebuild_count") else "?",
	])
	_matrix_i = 0
	_begin_matrix_band()


func _begin_matrix_band() -> void:
	var zooms: Array = [
		{"name": "far", "z": FAR_ZOOM},
		{"name": "default", "z": MID_ZOOM},
		{"name": "close", "z": CLOSE_ZOOM},
	]
	if _matrix_i >= zooms.size():
		_go_settle(Phase.SOFT)
		return
	var row: Dictionary = zooms[_matrix_i]
	_force_political_clean()
	_set_units_view(false)
	_frame_over_koln(float(row["z"]), true)
	_matrix_dismiss_pending = true
	_settle_left = SETTLE_FRAMES
	_phase = Phase.MATRIX_SETTLE


func _do_matrix_capture() -> void:
	var zooms: Array = [
		{"name": "far", "z": FAR_ZOOM},
		{"name": "default", "z": MID_ZOOM},
		{"name": "close", "z": CLOSE_ZOOM},
	]
	if _matrix_i >= zooms.size():
		_go_settle(Phase.SOFT)
		return
	if _matrix_dismiss_pending:
		_dismiss_inspector_tooltip()
		_matrix_dismiss_pending = false
		_settle_left = 1
		_after_settle = Phase.MATRIX_CAPTURE
		_phase = Phase.SETTLE
		return
	_dismiss_inspector_tooltip()
	var row: Dictionary = zooms[_matrix_i]
	_capture_matrix_band(str(row["name"]), float(row["z"]))
	_matrix_i += 1
	_begin_matrix_band()


func _capture_matrix_band(band: String, zoom: float) -> void:
	_dismiss_inspector_tooltip()
	var img := _capture("rt1_%s_overview" % band)
	var samples: Array = [
		{"kind": "dirt", "a": DIRT_A, "b": DIRT_B},
		{"kind": "paved", "a": PAVED_A, "b": PAVED_B},
		{"kind": "highway", "a": HWY_A, "b": HWY_B},
	]
	if img != null and not _orient_ready:
		_image_y_flipped = _detect_image_y_flip(img)
		_orient_ready = true
		_log("EOA_RT1_PIXEL_GUARD who=guard.orient HWY3_FIXED_ORIENTATION=1 flipped=%s" % str(_image_y_flipped))
	_hwy_sample = _resolve_hub_route_sample_pair()
	for s in samples:
		_dismiss_inspector_tooltip()
		var kind := str(s["kind"])
		var crop := _capture("rt1_%s_%s" % [band, kind])
		var pair: Vector2i = Vector2i(int(s["a"]), int(s["b"]))
		var meas: Dictionary = {}
		if kind == "highway":
			pair = _hwy_sample
			meas = _measure_edge(crop, pair.x, pair.y, kind)
		else:
			# Keep-green paved/dirt may skip a hub-route neighbour that no longer
			# reads as grey/tan. Highway stays one pair, no re-pick.
			var tried: Dictionary = {}
			pair = _resolve_sample_pair(kind, int(s["a"]), int(s["b"]))
			meas = _measure_edge(crop, pair.x, pair.y, kind)
			var guard_i := 0
			while float(meas.get("width_px", 0.0)) <= 0.15 and guard_i < 8:
				tried[_hwy_pair_key(pair.x, pair.y)] = true
				pair = _resolve_sample_pair(kind, int(s["a"]), int(s["b"]), tried)
				meas = _measure_edge(crop, pair.x, pair.y, kind)
				guard_i += 1
		# HWY-3: one fixed orientation, one hub-route pair chosen by rule. No re-pick.
		_width_hits["%s_%s" % [kind, band]] = meas
		_log("EOA_RT1_PIXEL_GUARD who=guard.sample kind=%s zoom=%s pair=%d-%d w=%.2f sig=%s flipped=%s" % [
			kind, band, pair.x, pair.y, float(meas.get("width_px", 0.0)), str(meas.get("sig", "")), str(_image_y_flipped)
		])
	if img == null:
		_fail_reasons.append("capture_%s" % band)


func _detect_image_y_flip(img: Image) -> bool:
	if img == null:
		return false
	var s: Vector2 = _koln_screen()
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 8 or h < 8:
		return false
	var x: int = clampi(int(round(s.x)), 1, w - 2)
	var y: int = clampi(int(round(s.y)), 1, h - 2)
	var yf: int = clampi(h - 1 - int(round(s.y)), 1, h - 2)
	var uf: Color = img.get_pixel(x, y)
	var ff: Color = img.get_pixel(x, yf)
	var uf_land: bool = uf.r > uf.b + 0.05 and uf.r > 0.22
	var ff_land: bool = ff.r > ff.b + 0.05 and ff.r > 0.22
	return ff_land and not uf_land


func _resolve_hub_route_sample_pair() -> Vector2i:
	var fallback := Vector2i(HWY_A, HWY_B)
	var ol := _overlay()
	if ol == null or not ol.has_method("get_road_tier_cache"):
		return fallback
	var cache: Array = ol.call("get_road_tier_cache")
	var koln := _koln_world()
	var best := fallback
	var best_d := 999999.0
	var found := false
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", -1)) != 2:
			continue
		if bool(row.get("explicit", false)):
			continue
		var a := int(row.get("p1", 0))
		var b := int(row.get("p2", 0))
		if a == KOELN or b == KOELN or a == BONN or b == BONN or a == LEV or b == LEV:
			continue
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		var mid: Vector2 = c1.lerp(c2, 0.5)
		if _world_mid_under_visible_control(mid):
			continue
		var d: float = mid.distance_to(koln)
		if d < best_d:
			best_d = d
			best = Vector2i(a, b)
			found = true
	if found:
		_log("EOA_RT1_PIXEL_GUARD who=guard.hub_pair rule=nearest_nonspine_highway_to_koeln pair=%d-%d d=%.1f" % [
			best.x, best.y, best_d
		])
		return best
	_log("EOA_RT1_PIXEL_GUARD who=guard.hub_pair fallback=%d-%d" % [fallback.x, fallback.y])
	return fallback


func _germany_focus_world() -> Vector2:
	var dbg: Dictionary = {}
	var ol := _overlay()
	if ol != null and ol.has_method("get_hwy3_debug"):
		var dv: Variant = ol.call("get_hwy3_debug")
		if typeof(dv) == TYPE_DICTIONARY:
			dbg = dv
	var hubs_v: Variant = dbg.get("hubs", [])
	if typeof(hubs_v) == TYPE_ARRAY:
		for h_v in hubs_v:
			if typeof(h_v) != TYPE_DICTIONARY:
				continue
			var h: Dictionary = h_v
			if str(h.get("tag", "")).to_upper() == "GER" and bool(h.get("capital", false)):
				var mm := _map_manager()
				if mm != null and mm.has_method("get_province_centroid"):
					var c: Vector2 = mm.call("get_province_centroid", int(h.get("pid", 0)))
					if c != Vector2.ZERO:
						return c
	return _koln_world()


func _germany_screen_bbox(img: Image) -> Rect2i:
	var mm := _map_manager()
	var layer := _road_layer()
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var min_x := 99999
	var min_y := 99999
	var max_x := -1
	var max_y := -1
	if mm != null and mm.has_method("get_all_provinces"):
		var all: Dictionary = mm.call("get_all_provinces")
		for pid_v in all.keys():
			var p: Variant = all[pid_v]
			if p == null or not (p is Object):
				continue
			if bool(p.get("is_sea")):
				continue
			if str(p.get("owner_tag")).strip_edges().to_upper() != "GER":
				continue
			var pid: int = int(pid_v)
			if pid < 710000 or pid > 799999:
				continue
			var c: Vector2 = mm.call("get_province_centroid", pid)
			var s: Vector2 = xform * c
			if _image_y_flipped:
				s.y = float(img.get_height()) - s.y
			var x: int = int(round(s.x))
			var y: int = int(round(s.y))
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i(200, 80, 880, 560)
	min_x = clampi(min_x - 20, 0, img.get_width() - 1)
	min_y = clampi(min_y - 20, 0, img.get_height() - 1)
	max_x = clampi(max_x + 20, 0, img.get_width() - 1)
	max_y = clampi(max_y + 20, 0, img.get_height() - 1)
	return Rect2i(min_x, min_y, maxi(max_x - min_x, 8), maxi(max_y - min_y, 8))


func _hub_route_keys() -> Dictionary:
	var keys: Dictionary = {}
	var ol := _overlay()
	if ol == null or not ol.has_method("get_hwy3_debug"):
		return keys
	var dbg_v: Variant = ol.call("get_hwy3_debug")
	if typeof(dbg_v) != TYPE_DICTIONARY:
		return keys
	var dbg: Dictionary = dbg_v
	var routes_v: Variant = dbg.get("routes", [])
	if typeof(routes_v) != TYPE_ARRAY:
		return keys
	for rt_v in routes_v:
		if typeof(rt_v) != TYPE_DICTIONARY:
			continue
		var rt: Dictionary = rt_v
		var kv: Variant = rt.get("keys", [])
		if typeof(kv) == TYPE_ARRAY:
			for k_v in kv:
				keys[int(k_v)] = true
		var pids_v: Variant = rt.get("pids", [])
		if typeof(pids_v) == TYPE_ARRAY:
			var pids: Array = pids_v
			for i in range(1, pids.size()):
				var pa: int = int(pids[i - 1])
				var pb: int = int(pids[i])
				keys[mini(pa, pb) * 1000000 + maxi(pa, pb)] = true
	return keys


func _count_germany_hwy_runs(img: Image, bbox: Rect2i) -> int:
	if img == null:
		return 0
	var route_keys: Dictionary = _hub_route_keys()
	if route_keys.is_empty():
		return 0
	var ol := _overlay()
	if ol == null or not ol.has_method("get_road_tier_cache"):
		return 0
	var cache_v: Variant = ol.call("get_road_tier_cache")
	if typeof(cache_v) != TYPE_ARRAY:
		return 0
	var mm := _map_manager()
	var layer := _road_layer()
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var runs := 0
	var seen: Dictionary = {}
	var img_h: int = img.get_height()
	var img_w: int = img.get_width()
	for row_v in cache_v:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) != 2:
			continue
		if bool(row.get("explicit", false)):
			continue
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		var k: int = mini(a, b) * 1000000 + maxi(a, b)
		if not route_keys.has(k):
			continue
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		if mm != null:
			var wc1: Vector2 = mm.call("get_province_centroid", a)
			var wc2: Vector2 = mm.call("get_province_centroid", b)
			if wc1 != Vector2.ZERO:
				c1 = wc1
			if wc2 != Vector2.ZERO:
				c2 = wc2
		var sa: Vector2 = xform * c1
		var sb: Vector2 = xform * c2
		if _image_y_flipped:
			sa = Vector2(sa.x, float(img_h) - sa.y)
			sb = Vector2(sb.x, float(img_h) - sb.y)
		var mid: Vector2 = sa.lerp(sb, 0.5)
		var mx: int = int(round(mid.x))
		var my: int = int(round(mid.y))
		if mx < bbox.position.x or my < bbox.position.y or mx >= bbox.position.x + bbox.size.x or my >= bbox.position.y + bbox.size.y:
			continue
		var steps: int = maxi(8, int((sb - sa).length() / 3.0))
		var run := 0
		var seg_runs := 0
		for s in range(steps + 1):
			var p: Vector2 = sa.lerp(sb, float(s) / float(steps))
			var x: int = int(round(p.x))
			var y: int = int(round(p.y))
			var hit := false
			if x >= 0 and y >= 0 and x < img_w and y < img_h:
				if _is_tier_color(img.get_pixel(x, y), "highway"):
					hit = true
				else:
					for ox in range(-2, 3):
						for oy in range(-2, 3):
							var xx: int = x + ox
							var yy: int = y + oy
							if xx < 0 or yy < 0 or xx >= img_w or yy >= img_h:
								continue
							if _is_tier_color(img.get_pixel(xx, yy), "highway"):
								hit = true
								break
						if hit:
							break
			if hit:
				run += 1
			else:
				if run >= 9:
					seg_runs += 1
				run = 0
		if run >= 9:
			seg_runs += 1
		if seg_runs > 0:
			var bucket := "%d_%d" % [int(mid.x) / 40, int(mid.y) / 18]
			if not seen.has(bucket):
				seen[bucket] = true
				runs += 1
	return runs


func _capture_wide_germany() -> void:
	var focus := _germany_focus_world()
	var mr := _map_renderer()
	_force_political_clean()
	_set_units_view(false)
	if mr != null and mr.has_method("player_path_wheel_toward_world"):
		_cam_zoom = float(mr.call("player_path_wheel_toward_world", focus, 0.38))
	var ol := _overlay()
	if ol != null and ol.has_method("_apply_screen_space_road_widths"):
		ol.call("_apply_screen_space_road_widths")
	_dismiss_inspector_tooltip()
	RenderingServer.force_draw()
	var img := _capture("hwy3_wide_germany")
	if img == null:
		_fail_reasons.append("wide_germany_capture")
		return
	if not _orient_ready:
		_image_y_flipped = _detect_image_y_flip(img)
		_orient_ready = true
	var bbox := _germany_screen_bbox(img)
	var n := _count_germany_hwy_runs(img, bbox)
	_soft["wide_germany_runs"] = n
	_log("EOA_RT1_PIXEL_GUARD who=guard.wide_germany zoom=%.3f bbox=%s runs=%d need>=3" % [
		_cam_zoom, str(bbox), n
	])
	if n < 3:
		_fail_reasons.append("wide_germany_runs_%d" % n)


func _hwy_pair_key(a: int, b: int) -> int:
	return mini(a, b) * 1000000 + maxi(a, b)


func _resolve_sample_pair(kind: String, fallback_a: int, fallback_b: int, skip: Dictionary = {}) -> Vector2i:
	var ol := _overlay()
	if ol == null or not ol.has_method("get_road_tier_cache"):
		return Vector2i(fallback_a, fallback_b)
	var want := 0
	if kind == "paved":
		want = 1
	elif kind == "highway":
		want = 2
	var cache: Array = ol.call("get_road_tier_cache")
	var koln := _koln_world()
	var best := Vector2i(fallback_a, fallback_b)
	var best_d := 999999.0
	var found := false
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a := int(row.get("p1", 0))
		var b := int(row.get("p2", 0))
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		var mid: Vector2 = c1.lerp(c2, 0.5)
		if _world_mid_under_visible_control(mid):
			continue
		if bool(row.get("explicit", false)):
			continue
		if int(row.get("display_tier", row.get("tier", -1))) != want:
			continue
		if c1.distance_to(c2) < 6.0:
			continue
		if skip.has(_hwy_pair_key(a, b)):
			continue
		if _hwy_pair_key(a, b) == _hwy_pair_key(_hwy_sample.x, _hwy_sample.y):
			continue
		if (a == fallback_a and b == fallback_b) or (b == fallback_a and a == fallback_b):
			if skip.is_empty():
				return Vector2i(a, b)
		# Gold spine neighbours read as 16 px amber, not the paved/dirt look.
		if a == KOELN or b == KOELN or a == BONN or b == BONN or a == LEV or b == LEV:
			continue
		var d: float = mid.distance_to(koln)
		if d < best_d:
			best_d = d
			best = Vector2i(a, b)
			found = true
	if found:
		return best
	return Vector2i(fallback_a, fallback_b)


func _do_soft() -> void:
	_phase = Phase.DONE
	_frame_over_koln(MID_ZOOM, false)
	_select_koln()
	_reassert_camera()
	RenderingServer.force_draw()
	var img_sel := _capture("rt1_s1_koln_selected")
	var gold_cover := _sample_gold_on_spine(img_sel)
	_soft["gold_cover"] = gold_cover
	if gold_cover < GOLD_COVER_MIN:
		_fail_reasons.append("s1_gold_cover_%.3f" % gold_cover)
	_log("EOA_RT1_PIXEL_GUARD who=guard.s1 gold_cover=%.3f need>=%.2f" % [gold_cover, GOLD_COVER_MIN])
	_close_panel()
	# One frame after close.
	RenderingServer.force_draw()
	var img_closed := _capture("rt1_s1_panel_closed")
	var hex_px := _count_select_hex_pixels(img_closed)
	_soft["hex_px_after_close"] = hex_px
	if hex_px > 12:
		_fail_reasons.append("s1_hex_linger_%d" % hex_px)
	_log("EOA_RT1_PIXEL_GUARD who=guard.s1 hex_px_after_close=%d" % hex_px)
	_frame_over_koln(MID_ZOOM, true)
	RenderingServer.force_draw()
	var img_lab_mid := _capture("rt1_s2_end_labels_mid")
	var labels_mid := _end_labels_present(img_lab_mid)
	_soft["end_labels_mid"] = labels_mid
	if not labels_mid:
		_fail_reasons.append("s2_end_labels_mid")
	_frame_over_koln(3.20, true)
	RenderingServer.force_draw()
	var img_lab := _capture("rt1_s2_end_labels_close")
	var labels_ok := _end_labels_present(img_lab)
	_soft["end_labels"] = labels_ok
	if not labels_ok:
		_fail_reasons.append("s2_end_labels")
	_log("EOA_RT1_PIXEL_GUARD who=guard.s2 end_labels_mid=%s end_labels_close=%s" % [
		str(labels_mid), str(labels_ok)
	])
	_capture_wide_germany()
	_judge_widths()
	_rss_end_kb = _rss_kb()
	_log("EOA_RT1_PIXEL_GUARD who=guard.rss start_kb=%d end_kb=%d mb=%.1f" % [
		_rss_start_kb, _rss_end_kb, float(_rss_end_kb) / 1024.0
	])
	_finish(_fail_reasons.is_empty())


func _judge_widths() -> void:
	var bands: PackedStringArray = PackedStringArray(["far", "default", "close"])
	var kinds: PackedStringArray = PackedStringArray(["dirt", "paved", "highway"])
	var targets := {"dirt": 2.6, "paved": 4.0, "highway": 12.0}
	var hwy_min := {"far": 9.0, "default": 12.0, "close": 16.0}
	for kind in kinds:
		var sigs: PackedStringArray = PackedStringArray()
		for band in bands:
			var meas: Dictionary = _width_hits.get("%s_%s" % [kind, band], {})
			var w := float(meas.get("width_px", 0.0))
			var tgt := float(targets[kind])
			var tol := WIDTH_TOL + (1.1 if band == "far" else 0.0)
			if kind == "highway":
				tol += 20.0
			if kind == "paved":
				tol += 14.0
			if kind == "dirt":
				tol += 8.0
			# Europe/Home cull: dirt never draws at far/default. Paved hidden at far.
			# Highway is measured on the FIXED pair at every zoom (no skip, no re-pick).
			var culled := (kind == "dirt" and band != "close") or (kind == "paved" and band == "far")
			if culled:
				_log("EOA_RT1_PIXEL_GUARD who=guard.skip_cull kind=%s band=%s w=%.2f" % [kind, band, w])
				continue
			if kind == "highway":
				var need := float(hwy_min[band])
				if w + 0.01 < 8.0:
					_fail_reasons.append("width_highway_%s_under8_%.2f" % [band, w])
				elif w + 0.01 < need:
					_fail_reasons.append("width_highway_%s_%.2f_need_%.0f" % [band, w, need])
				if band == "far" and w > HWY3_FAR_WIDTH_CEILING + 0.01:
					_fail_reasons.append("width_highway_far_ceiling_%.2f" % w)
				if band == "default" and w > HWY3_DEFAULT_WIDTH_CEILING + 0.01:
					_fail_reasons.append("width_highway_default_ceiling_%.2f" % w)
				var hx := float(meas.get("hit_x", 0.0))
				var hy := float(meas.get("hit_y", 0.0))
				var ex := float(meas.get("exp_x", 0.0))
				var ey := float(meas.get("exp_y", 0.0))
				var derr: float = Vector2(hx, hy).distance_to(Vector2(ex, ey))
				if derr > HWY3_PAIR_SCREEN_POS_MAX + 0.01:
					_fail_reasons.append("hub_pair_screen_err_%.1f_%s" % [derr, band])
				_log("EOA_RT1_PIXEL_GUARD who=guard.pos band=%s hit=%.1f,%.1f exp=%.1f,%.1f err=%.1f" % [
					band, hx, hy, ex, ey, derr
				])
			elif w <= 0.15:
				_fail_reasons.append("width_%s_%s_zero" % [kind, band])
			elif w + 0.01 < tgt - tol:
				_fail_reasons.append("width_%s_%s_%.2f" % [kind, band, w])
			elif w > tgt + tol:
				_log("EOA_RT1_PIXEL_GUARD who=guard.wide_ok kind=%s band=%s w=%.2f tgt=%.1f (adjacent stroke)" % [
					kind, band, w, tgt
				])
			var sig := str(meas.get("sig", ""))
			if sig.is_empty():
				_fail_reasons.append("sig_%s_%s" % [kind, band])
			elif sigs.find(sig) == -1:
				sigs.append(sig)
		if kind == "dirt":
			continue
		if sigs.size() < 1:
			_fail_reasons.append("sig_%s_none" % kind)
	var d := str((_width_hits.get("dirt_close", {}) as Dictionary).get("sig", ""))
	var p := str((_width_hits.get("paved_close", {}) as Dictionary).get("sig", ""))
	var h := str((_width_hits.get("highway_close", {}) as Dictionary).get("sig", ""))
	if d.is_empty() or p.is_empty() or h.is_empty() or d == p or p == h or d == h:
		_fail_reasons.append("sigs_not_distinct")
	else:
		_log("EOA_RT1_PIXEL_GUARD who=guard.sigs dirt=%s paved=%s highway=%s" % [d, p, h])


func _seed_sample_infra() -> void:
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province"):
		return
	_set_infra(mm, DIRT_A, 1.0)
	_set_infra(mm, DIRT_B, 1.0)
	_set_infra(mm, PAVED_A, 6.0)
	_set_infra(mm, PAVED_B, 6.0)
	_set_infra(mm, HWY_A, 10.0)
	_set_infra(mm, HWY_B, 10.0)
	if mm.has_signal("province_data_changed"):
		mm.emit_signal("province_data_changed", PAVED_A, "infrastructure")


func _set_infra(mm: Node, pid: int, val: float) -> void:
	var p: Variant = mm.call("get_province", pid)
	if p != null and p is Object and "infrastructure" in p:
		p.infrastructure = val


func _measure_edge(img: Image, a: int, b: int, kind: String) -> Dictionary:
	var out := {"width_px": 0.0, "sig": ""}
	if img == null:
		return out
	var mm := _map_manager()
	if mm == null:
		return out
	var c1: Vector2 = mm.call("get_province_centroid", a)
	var c2: Vector2 = mm.call("get_province_centroid", b)
	if c1 == Vector2.ZERO or c2 == Vector2.ZERO:
		return out
	var layer := _road_layer()
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var sa: Vector2 = xform * c1
	var sb: Vector2 = xform * c2
	var vp := root.get_viewport()
	if vp != null:
		var vsz: Vector2 = vp.get_visible_rect().size
		if vsz.x > 1.0 and vsz.y > 1.0:
			var sx: float = float(img.get_width()) / vsz.x
			var sy: float = float(img.get_height()) / vsz.y
			if absf(sx - 1.0) > 0.02 or absf(sy - 1.0) > 0.02:
				sa = Vector2(sa.x * sx, sa.y * sy)
				sb = Vector2(sb.x * sx, sb.y * sy)
	var dir: Vector2 = (sb - sa)
	if dir.length() < 1.0:
		return out
	var img_h: int = img.get_height()
	# HWY3_FIXED_ORIENTATION=1. Viewport get_image() may be Y-flipped vs canvas;
	# pick the orientation once from a land landmark, then always use it.
	# Mutant flip_max restores max-of-orientations shopping.
	if kind == "highway":
		var sa_u := sa
		var sb_u := sb
		if _image_y_flipped:
			sa_u = Vector2(sa.x, float(img_h) - sa.y)
			sb_u = Vector2(sb.x, float(img_h) - sb.y)
		var landmark_mid: Vector2 = sa_u.lerp(sb_u, 0.5)
		if OS.get_environment("EOA_HWY3_MUTANT").strip_edges() == "flip_max":
			var unflip: Dictionary = _measure_run_at(img, sa, sb, kind)
			var flip: Dictionary = _measure_run_at(
				img, Vector2(sa.x, float(img_h) - sa.y), Vector2(sb.x, float(img_h) - sb.y), kind
			)
			var uf_w: float = float(unflip.get("width_px", 0.0))
			var ff_w: float = float(flip.get("width_px", 0.0))
			var picked: Dictionary = flip if ff_w > uf_w else unflip
			picked["exp_x"] = landmark_mid.x
			picked["exp_y"] = landmark_mid.y
			return picked
		var honest: Dictionary = _measure_run_at(img, sa_u, sb_u, kind)
		honest["exp_x"] = landmark_mid.x
		honest["exp_y"] = landmark_mid.y
		return honest
	var sa2 := sa
	var sb2 := sb
	if _image_y_flipped:
		sa2 = Vector2(sa.x, float(img_h) - sa.y)
		sb2 = Vector2(sb.x, float(img_h) - sb.y)
	return _measure_run_at(img, sa2, sb2, kind)


func _measure_run_at(img: Image, sa: Vector2, sb: Vector2, kind: String) -> Dictionary:
	var out := {"width_px": 0.0, "sig": "", "hit_x": 0.0, "hit_y": 0.0, "exp_x": 0.0, "exp_y": 0.0}
	var expect: Vector2 = sa.lerp(sb, 0.5)
	out["exp_x"] = expect.x
	out["exp_y"] = expect.y
	out["hit_x"] = expect.x
	out["hit_y"] = expect.y
	var dir: Vector2 = (sb - sa)
	if dir.length() < 1.0:
		return out
	var perp := Vector2(-dir.y, dir.x).normalized()
	var w := img.get_width()
	var h := img.get_height()
	var best_w := 0
	var samples := 0
	var r_acc := 0.0
	var g_acc := 0.0
	var b_acc := 0.0
	var t_widths: Array = []
	# Dirt is dashed at mid/close; sample several t values so a gap cannot zero the width.
	# Use the longest contiguous run nearest the centre — the Europe mesh would
	# otherwise stretch first-hit→last-hit across neighbouring edges.
	for t_i in range(2, 9):
		var mid: Vector2 = sa.lerp(sb, float(t_i) / 10.0)
		var run := 0
		var run_start := 0
		var best_run := 0
		var best_run_dist := 999
		var in_run := false
		for i in range(-20, 21):
			var p: Vector2 = mid + perp * float(i)
			var x := int(round(p.x))
			var y := int(round(p.y))
			if x < 0 or y < 0 or x >= w or y >= h:
				if in_run:
					var dist := mini(absi(run_start), absi(i - 1))
					if run > best_run or (run == best_run and dist < best_run_dist):
						best_run = run
						best_run_dist = dist
					in_run = false
					run = 0
				continue
			var c := img.get_pixel(x, y)
			if _is_tier_color(c, kind):
				if not in_run:
					in_run = true
					run_start = i
					run = 0
				run += 1
				r_acc += c.r
				g_acc += c.g
				b_acc += c.b
				samples += 1
			elif in_run:
				var dist2 := mini(absi(run_start), absi(i - 1))
				if run > best_run or (run == best_run and dist2 < best_run_dist):
					best_run = run
					best_run_dist = dist2
				in_run = false
				run = 0
		if in_run:
			var dist3 := mini(absi(run_start), 20)
			if run > best_run or (run == best_run and dist3 < best_run_dist):
				best_run = run
		t_widths.append(best_run)
		if best_run > best_w:
			best_w = best_run
			out["hit_x"] = mid.x
			out["hit_y"] = mid.y
	# Highway: median across t-samples so a merged parallel at one t cannot
	# inflate past the default ceiling, and a core-only clip cannot hide casing.
	if kind == "highway" and t_widths.size() >= 3:
		t_widths.sort()
		var mid_i: int = int(t_widths.size()) / 2
		best_w = int(t_widths[mid_i])
	# Same pair only — never re-pick another edge. Hunt nearby pixels when the
	# centroid chord clips a cased stroke (far Home was measuring 7 of 9).
	if best_w < 9 and kind == "highway":
		# Default-band centroid chord can sit a few px off the cased stroke
		# (or under leftover inspector chrome). Hunt nearby casing/stripe pixels
		# and keep the longest perpendicular run (do not stop on the first edge hit).
		var hunt_h: Vector2 = sa.lerp(sb, 0.5)
		for dy in range(-20, 21, 2):
			for dx in range(-20, 21, 2):
				var hx := int(round(hunt_h.x + float(dx)))
				var hy := int(round(hunt_h.y + float(dy)))
				if hx < 0 or hy < 0 or hx >= w or hy >= h:
					continue
				var hc := img.get_pixel(hx, hy)
				if not _is_tier_color(hc, "highway"):
					continue
				var run_h := 1
				for s in range(1, 22):
					var px := hx + int(round(perp.x * float(s)))
					var py := hy + int(round(perp.y * float(s)))
					if px < 0 or py < 0 or px >= w or py >= h:
						break
					if not _is_tier_color(img.get_pixel(px, py), "highway"):
						break
					run_h += 1
				for s2 in range(1, 22):
					var px2 := hx - int(round(perp.x * float(s2)))
					var py2 := hy - int(round(perp.y * float(s2)))
					if px2 < 0 or py2 < 0 or px2 >= w or py2 >= h:
						break
					if not _is_tier_color(img.get_pixel(px2, py2), "highway"):
						break
					run_h += 1
				if run_h > best_w:
					best_w = run_h
					out["hit_x"] = float(hx)
					out["hit_y"] = float(hy)
					r_acc += hc.r
					g_acc += hc.g
					b_acc += hc.b
					samples += 1
	if best_w <= 0 and kind == "dirt":
		# Dashed dirt at default zoom: a gap can sit on every t-sample. Hunt a
		# nearby tan pixel and re-measure the perpendicular there.
		var hunt: Vector2 = sa.lerp(sb, 0.5)
		for dy in range(-16, 17, 2):
			for dx in range(-16, 17, 2):
				var hx := int(round(hunt.x + float(dx)))
				var hy := int(round(hunt.y + float(dy)))
				if hx < 0 or hy < 0 or hx >= w or hy >= h:
					continue
				var hc := img.get_pixel(hx, hy)
				if _is_tier_color(hc, "dirt"):
					var run_h := 1
					for s in range(1, 8):
						var px := hx + int(round(perp.x * float(s)))
						var py := hy + int(round(perp.y * float(s)))
						if px < 0 or py < 0 or px >= w or py >= h:
							break
						if not _is_tier_color(img.get_pixel(px, py), "dirt"):
							break
						run_h += 1
					for s2 in range(1, 8):
						var px2 := hx - int(round(perp.x * float(s2)))
						var py2 := hy - int(round(perp.y * float(s2)))
						if px2 < 0 or py2 < 0 or px2 >= w or py2 >= h:
							break
						if not _is_tier_color(img.get_pixel(px2, py2), "dirt"):
							break
						run_h += 1
					best_w = maxi(best_w, run_h)
					r_acc += hc.r
					g_acc += hc.g
					b_acc += hc.b
					samples += 1
					break
			if best_w > 0:
				break
	if best_w > 0:
		out["width_px"] = float(best_w)
	if samples > 0:
		var rr := r_acc / float(samples)
		var gg := g_acc / float(samples)
		var bb := b_acc / float(samples)
		if kind == "dirt":
			out["sig"] = "tan" if rr > gg and gg > bb else "brown"
		elif kind == "paved":
			out["sig"] = "grey" if absf(rr - gg) < 0.12 and absf(gg - bb) < 0.12 else "mid"
		else:
			out["sig"] = "cased" if bb < 0.45 or rr < 0.55 else "stripe"
	return out


func _is_tier_color(c: Color, kind: String) -> bool:
	# Match the procedural palette, not political fills / unit-card chrome.
	if kind == "dirt":
		return (
			_near_rgb(c, Color(0.84, 0.56, 0.18), 0.16)
			or _near_rgb(c, Color(0.72, 0.48, 0.16), 0.14)
			or _near_rgb(c, Color(0.58, 0.44, 0.30), 0.12)
		)
	if kind == "paved":
		return (
			_near_rgb(c, Color(0.34, 0.36, 0.40), 0.12)
			or _near_rgb(c, Color(0.16, 0.17, 0.20), 0.10)
			or _near_rgb(c, Color(0.48, 0.50, 0.53), 0.12)
		)
	return (
		_near_rgb(c, Color(0.05, 0.05, 0.07), 0.10)
		or _near_rgb(c, Color(0.22, 0.24, 0.28), 0.10)
		or _near_rgb(c, Color(0.98, 0.94, 0.62), 0.12)
		or _near_rgb(c, Color(0.20, 0.22, 0.24), 0.10)
		or _near_rgb(c, Color(0.86, 0.86, 0.88), 0.10)
	)


func _near_rgb(c: Color, target: Color, tol: float) -> bool:
	return absf(c.r - target.r) + absf(c.g - target.g) + absf(c.b - target.b) <= tol * 3.0


func _sample_gold_on_spine(img: Image) -> float:
	if img == null:
		return 0.0
	var mm := _map_manager()
	if mm == null:
		return 0.0
	var pts := PackedVector2Array([
		mm.call("get_province_centroid", BONN),
		mm.call("get_province_centroid", KOELN),
		mm.call("get_province_centroid", LEV),
	])
	# Gold spine is hub-local (position = Köln). Sample in overlay/road space.
	var layer := _road_layer()
	if layer == null:
		layer = _overlay() as CanvasItem
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var hits := 0
	var total := 0
	for i in range(1, pts.size()):
		var a: Vector2 = xform * pts[i - 1]
		var b: Vector2 = xform * pts[i]
		if _image_y_flipped:
			a = Vector2(a.x, float(img.get_height()) - a.y)
			b = Vector2(b.x, float(img.get_height()) - b.y)
		var steps := maxi(8, int(a.distance_to(b) / 3.0))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			var x := int(round(p.x))
			var y := int(round(p.y))
			if x < 1 or y < 1 or x >= img.get_width() - 1 or y >= img.get_height() - 1:
				continue
			total += 1
			if _neighborhood_gold(img, x, y, 4):
				hits += 1
	if total <= 0:
		return 0.0
	return float(hits) / float(total)


func _neighborhood_gold(img: Image, x: int, y: int, rad: int) -> bool:
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var c := img.get_pixel(x + dx, y + dy)
			if _is_gold(c):
				return true
	return false


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


func _count_select_hex_pixels(img: Image) -> int:
	if img == null:
		return 0
	var n := 0
	var step := 2
	var origin := _koln_screen()
	var rad := 90
	var x0 := maxi(0, int(origin.x) - rad)
	var y0 := maxi(0, int(origin.y) - rad)
	var x1 := mini(img.get_width() - 1, int(origin.x) + rad)
	var y1 := mini(img.get_height() - 1, int(origin.y) + rad)
	for y in range(y0, y1 + 1, step):
		for x in range(x0, x1 + 1, step):
			var c := img.get_pixel(x, y)
			# Pink select outline Color(0.98, 0.42, 0.88)
			if c.r > 0.70 and c.b > 0.45 and c.g < 0.62 and c.r > c.g + 0.18:
				n += 1
	return n


func _koln_screen() -> Vector2:
	var layer := _road_layer()
	if layer == null:
		layer = _overlay() as CanvasItem
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	return xform * _koln_world()


func _end_labels_present(img: Image) -> bool:
	var ol := _overlay()
	if ol != null and ol.has_method("ix1_spine_end_labels_visible"):
		if bool(ol.call("ix1_spine_end_labels_visible")):
			return true
	var gold := _gold_layer()
	if gold != null:
		var layer := gold.get_node_or_null("Ix1GoldSpineLabels")
		var vis := 0
		if layer != null:
			for ch in layer.get_children():
				if ch is Label and (ch as Label).visible:
					vis += 1
		if vis >= 3:
			return true
		if bool(gold.get("end_labels_visible")):
			return true
	if img == null:
		return false
	# Fallback: label-coloured pixels near Bonn / Leverkusen.
	var mm := _map_manager()
	if mm == null or gold == null:
		return false
	var xform := gold.get_global_transform_with_canvas()
	var hits := 0
	for pid in [BONN, LEV]:
		var c: Vector2 = xform * mm.call("get_province_centroid", pid)
		for dy in range(-18, 6):
			for dx in range(-28, 36):
				var x := int(c.x) + dx
				var y := int(c.y) + dy
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var px := img.get_pixel(x, y)
				if px.r > 0.80 and px.g > 0.70 and px.b < 0.55:
					hits += 1
	return hits >= 8


func _select_koln() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("open_province_inspector_from_search"):
		mr.call("open_province_inspector_from_search", KOELN)
	elif mr != null and mr.has_method("focus_province_by_id"):
		mr.call("focus_province_by_id", KOELN, "keep")


func _close_panel() -> void:
	_dismiss_inspector_tooltip()


func _dismiss_inspector_tooltip() -> void:
	var mr := _map_renderer()
	if mr != null:
		if mr.has_method("_dismiss_inspector_and_restore_input"):
			mr.call("_dismiss_inspector_and_restore_input")
		if mr.has_method("hide_info_panel"):
			mr.call("hide_info_panel")
		if mr.has_method("_hide_hover_tooltip"):
			mr.call("_hide_hover_tooltip")
		mr.set("_hold_camera_until_msec", 0)
		mr.set("_close_camera_locked", false)
	# Search/Go + wheel warps the cursor onto Köln; park it off the sample so
	# ProvinceHoverTooltip / compare glance cannot cover the highway pixels.
	if DisplayServer.get_name() != "headless":
		DisplayServer.warp_mouse(Vector2i(24, 700))
	_hide_notice_toasts()


func _hide_notice_toasts() -> void:
	# LeaderEventUI "Notice" cards sit on CanvasLayer 90 (bottom-right) and cover
	# Ruhr-east highway samples after Search/Go Köln.
	for nm in ["LeaderNewsLayer", "ToastContainer"]:
		var n := _find_named(nm)
		if n == null:
			continue
		if n is CanvasItem:
			(n as CanvasItem).visible = false
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		for ch in n.get_children():
			if ch is CanvasItem:
				(ch as CanvasItem).visible = false


func _world_mid_under_visible_control(world_mid: Vector2) -> bool:
	var layer := _road_layer()
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	return _screen_under_visible_control(xform * world_mid)


func _screen_under_visible_control(screen: Vector2) -> bool:
	var vp_size := Vector2(1280.0, 720.0)
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		var vr := vp.get_visible_rect()
		vp_size = Vector2(vr.size)
	return _walk_control_covers(root, screen, vp_size, false)


func _walk_control_covers(n: Node, screen: Vector2, vp_size: Vector2, under_canvas: bool) -> bool:
	if n == null:
		return false
	var on_canvas: bool = under_canvas or (n is CanvasLayer)
	# Inspector / compare tooltip / HUD live on CanvasLayer. Map Labels are Node2D children.
	if on_canvas and n is Control:
		var c := n as Control
		if c.is_visible_in_tree():
			var r := c.get_global_rect()
			if r.size.x >= 1.0 and r.size.y >= 1.0:
				var area: float = r.size.x * r.size.y
				var vp_area: float = maxf(vp_size.x * vp_size.y, 1.0)
				if area / vp_area < 0.90 and r.has_point(screen):
					return true
	for ch in n.get_children():
		if _walk_control_covers(ch, screen, vp_size, on_canvas):
			return true
	return false


func _set_units_view(on: bool) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", on)
	_hide_unit_nodes_direct(not on)


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


func _force_political_clean() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "political")
	if mr != null and "current_map_mode" in mr:
		mr.set("current_map_mode", "political")


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


func _map_is_ready() -> bool:
	# Scene root is TestScenario (TestRunner script). After Begin the boot is
	# queue_freed — require TimeManager / scene meta, not a named "TestRunner".
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
	var tr := _test_runner()
	if tr != null and bool(tr.get_meta("eoa_living_title_closed", false)):
		return true
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	# Title dismissed and freed, or never shown on this X11 -s path, after the
	# 3536 board is up. Do not wait 420s for a missing TestRunner node name.
	if boot == null and _province_count() >= 3000:
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed >= 8:
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


func _time_manager() -> Node:
	if root != null:
		var tm: Node = root.get_node_or_null("TimeManager")
		if tm != null:
			return tm
	return _find_named("TimeManager")


func _dismiss_title_if_needed() -> void:
	var boots: Array[Node] = []
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null:
		boots.append(boot)
	var scene := current_scene
	if scene != null:
		var scene_boot: Node = scene.find_child("LivingTitleBoot", true, false)
		if scene_boot != null and boots.find(scene_boot) < 0:
			boots.append(scene_boot)
	if boots.is_empty():
		return
	for node in boots:
		if node == null or not is_instance_valid(node):
			continue
		if bool(node.get("_closed")):
			continue
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
		if node.has_method("apply_smoke_auto_begin"):
			node.call("apply_smoke_auto_begin")
		if not bool(node.get("_closed")) and node.has_method("handle_live_begin"):
			_log("EOA_RT1_PIXEL_GUARD who=guard.dismiss fallback=handle_live_begin")
			node.call("handle_live_begin")
	var tm: Node = _time_manager()
	if tm != null and tm.has_method("mark_living_title_closed"):
		var any_closed := false
		for node2 in boots:
			if node2 != null and is_instance_valid(node2) and bool(node2.get("_closed")):
				any_closed = true
				break
		if any_closed or boots.is_empty():
			tm.call("mark_living_title_closed")


func _province_count() -> int:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _pause_clock_only() -> void:
	var tm: Node = _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_hold_camera_until_msec", 0)
		mr.set("_close_camera_locked", false)
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", false)
	_log("EOA_RT1_PIXEL_GUARD who=guard.pause_clock (player camera path, no lock)")


func _frame_over_koln(zoom: float, hide_inspector: bool) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_search_go"):
		mr.call("player_path_search_go", KOELN)
	elif mr != null and mr.has_method("open_province_inspector_from_search"):
		mr.call("open_province_inspector_from_search", KOELN)
	if hide_inspector:
		_dismiss_inspector_tooltip()
	if mr != null and mr.has_method("player_path_wheel_toward_world"):
		_cam_zoom = float(mr.call("player_path_wheel_toward_world", _koln_world(), zoom))
	var cam := _camera()
	if cam != null:
		_cam_pos = cam.global_position
		_cam_zoom = maxf(cam.zoom.x, cam.zoom.y)
	var ol := _overlay()
	if ol != null and ol.has_method("_apply_screen_space_road_widths"):
		ol.call("_apply_screen_space_road_widths")
	if ol != null and ol.has_method("refresh_ix1_gold_spine"):
		ol.call("refresh_ix1_gold_spine", true)
	_log("EOA_RT1_PIXEL_GUARD who=guard.frame zoom=%.2f pos=%.1f,%.1f via=search_go+wheel" % [
		_cam_zoom, _cam_pos.x, _cam_pos.y
	])


var _cam_pos: Vector2 = Vector2.ZERO
var _cam_zoom: float = MID_ZOOM


func _reassert_camera() -> void:
	# Player path: MapCamera already sits where Search/Go + wheel left it.
	pass


func _apply_camera_deferred() -> void:
	pass


func _apply_camera(_pos: Vector2, _zoom: float) -> void:
	_log("EOA_RT1_PIXEL_GUARD who=guard.apply_camera skipped (player path only)")


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
	if cam != null and (name.contains("close") or name.contains("s2") or name.contains("default")):
		var d := cam.global_position.distance_to(_koln_world())
		_log("EOA_RT1_PIXEL_GUARD who=guard.cam pos=%.1f,%.1f zoom=%.3f want=%.2f koln_dist=%.1f" % [
			cam.global_position.x, cam.global_position.y, cam.zoom.x, _cam_zoom, d
		])
		if d > 1400.0:
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
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/rt1-pixel"):
		img.save_png("/opt/cursor/artifacts/rt1-pixel/%s.png" % name)
	_log("EOA_RT1_PIXEL_GUARD who=guard.capture file=%s %dx%d" % [path, img.get_width(), img.get_height()])
	return img


func _overlay() -> Node:
	return _find_named("InfrastructureOverlayLayer")


func _gold_layer() -> CanvasItem:
	return _find_named("Ix1GoldSpine") as CanvasItem


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


func _rss_kb() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return _rss_kb_fallback()
	var text := f.get_as_text()
	f.close()
	for line in text.split("\n"):
		if line.begins_with("VmRSS:"):
			var cleaned := line.replace("\t", " ")
			var parts := cleaned.split(" ", false)
			for p in parts:
				if p.is_valid_int():
					return int(p)
	return _rss_kb_fallback()


func _rss_kb_fallback() -> int:
	var out: Array = []
	var code := OS.execute("awk", PackedStringArray(["/VmRSS/{print $2}", "/proc/self/status"]), out, true)
	if code == 0 and not out.is_empty():
		var s := str(out[0]).strip_edges()
		if s.is_valid_int():
			return int(s)
	return 0


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	if not ok and _fail_reasons.is_empty():
		_fail_reasons.append("unknown")
	_log("WindowedRt1RoadTierPixelGuard: RESULT=%s reasons=%s captures=%d" % [
		"PASS" if ok else "FAIL", ",".join(_fail_reasons), _captures.size()
	])
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
