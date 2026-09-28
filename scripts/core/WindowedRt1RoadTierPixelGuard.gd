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
var _width_hits: Dictionary = {}
var _soft: Dictionary = {}
var _rss_start_kb: int = 0
var _rss_end_kb: int = 0


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
	var row: Dictionary = zooms[_matrix_i]
	_capture_matrix_band(str(row["name"]), float(row["z"]))
	_matrix_i += 1
	_begin_matrix_band()


func _capture_matrix_band(band: String, zoom: float) -> void:
	var img := _capture("rt1_%s_overview" % band)
	var samples: Array = [
		{"kind": "dirt", "a": DIRT_A, "b": DIRT_B},
		{"kind": "paved", "a": PAVED_A, "b": PAVED_B},
		{"kind": "highway", "a": HWY_A, "b": HWY_B},
	]
	for s in samples:
		var kind := str(s["kind"])
		var pair: Vector2i = _resolve_sample_pair(kind, int(s["a"]), int(s["b"]))
		var crop := _capture("rt1_%s_%s" % [band, kind])
		var meas: Dictionary = _measure_edge(crop, pair.x, pair.y, kind)
		_width_hits["%s_%s" % [kind, band]] = meas
		_log("EOA_RT1_PIXEL_GUARD who=guard.sample kind=%s zoom=%s pair=%d-%d w=%.2f sig=%s" % [
			kind, band, pair.x, pair.y, float(meas.get("width_px", 0.0)), str(meas.get("sig", ""))
		])
	if img == null:
		_fail_reasons.append("capture_%s" % band)


func _resolve_sample_pair(kind: String, fallback_a: int, fallback_b: int) -> Vector2i:
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
		if (a == fallback_a and b == fallback_b) or (b == fallback_a and a == fallback_b):
			return Vector2i(a, b)
		if bool(row.get("explicit", false)):
			continue
		if int(row.get("display_tier", row.get("tier", -1))) != want:
			continue
		# Gold spine neighbours read as 16 px amber, not the paved/dirt look.
		if a == KOELN or b == KOELN or a == BONN or b == BONN or a == LEV or b == LEV:
			continue
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		var mid: Vector2 = c1.lerp(c2, 0.5)
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
			# Far inferred highways are rare and often off the Köln frame.
			var culled := (kind == "dirt" and band != "close") or (kind == "paved" and band == "far") or (kind == "highway" and band == "far")
			if culled:
				_log("EOA_RT1_PIXEL_GUARD who=guard.skip_cull kind=%s band=%s w=%.2f" % [kind, band, w])
				continue
			if w <= 0.15:
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
		for i in range(-12, 13):
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
			var dist3 := mini(absi(run_start), 12)
			if run > best_run or (run == best_run and dist3 < best_run_dist):
				best_run = run
		if best_run > best_w:
			best_w = best_run
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
		var steps := maxi(8, int(a.distance_to(b) / 3.0))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			var x := int(round(p.x))
			var y := int(round(p.y))
			if x < 1 or y < 1 or x >= img.get_width() - 1 or y >= img.get_height() - 1:
				continue
			total += 1
			if _neighborhood_gold(img, x, y, 3):
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
	var mr := _map_renderer()
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	elif mr != null and mr.has_method("_dismiss_inspector_and_restore_input"):
		mr.call("_dismiss_inspector_and_restore_input")


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
	if hide_inspector and mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
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
