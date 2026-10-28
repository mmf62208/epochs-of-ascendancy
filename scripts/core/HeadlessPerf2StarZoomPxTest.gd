extends SceneTree

## PERF-2 live star zoom: capital stars must grow on the real viewport.
## Play MIXED on b16b9b53: wheel/Home only call `_sync_capital_star_scales` →
## `_capital_star_font_px` capped at 20, so Budapest/Belgrade stayed ~20 px at
## camera zoom 5.62. The 18–36 clamp lived only on `_layout_zoomed_map_glyphs`
## (not the live wheel path). This guard drives that live light-refresh path
## at two+ zooms and measures on-screen star pixels. Must FAIL on b16b9b53
## and PASS on the tip. Does not load WorldMap.tscn / 3520.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x720 \
##     -s res://scripts/core/HeadlessPerf2StarZoomPxTest.gd

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const PLAY_SIZE := Vector2i(1280, 720)
const OP_Z := 0.760
const TACTICAL_Z := 2.00
const DEEP_Z := 5.62
const BERLIN := 710300
const STAR_WORLD := Vector2(4000.0, 1600.0)
const META_STAR := &"_map_glyph_capital"
const FLUSH_FRAMES := 6
const HIGH_MIN_FONT_PX := 28
const TACTICAL_MIN_SCREEN_PX := 70.0
const DEEP_MIN_SCREEN_PX := 150.0
const OP_MAX_SCREEN_PX := 26.0
const GROW_RATIO := 1.80

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null
var _star: Label = null
var _svp: SubViewport = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf2StarZoomPxTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf2StarZoomPxTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf2StarZoomPxTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf2StarZoomPxTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessPerf2StarZoomPxTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	root.size = PLAY_SIZE
	_test_source_needles()
	if not _setup_map_renderer():
		return
	_seed_capital()
	await _flush()
	var op: Dictionary = await _measure_at_zoom("operational", OP_Z)
	var tac: Dictionary = await _measure_at_zoom("tactical", TACTICAL_Z)
	var deep: Dictionary = await _measure_at_zoom("deep", DEEP_Z)
	_assert_band("operational", op, false)
	_assert_band("tactical", tac, true)
	_assert_band("deep", deep, true)
	_assert_grew(op, tac, "tactical")
	_assert_grew(op, deep, "deep")
	_cleanup()


func _test_source_needles() -> void:
	var src := _read(SRC_REN)
	if src.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var px_fn := _slice_func(src, "_capital_star_font_px")
	if px_fn.is_empty():
		_fail("_capital_star_font_px missing")
		return
	if "OPERATIONAL_MAX_ZOOM" not in px_fn:
		_fail("_capital_star_font_px must leave the idle 20 px cap above OPERATIONAL_MAX_ZOOM")
		return
	if "18, 36" not in px_fn and "18,36" not in px_fn:
		_fail("_capital_star_font_px must apply the 18–36 clamp on the live sync path")
		return
	var sync_fn := _slice_func(src, "_sync_capital_star_scales")
	if "_capital_star_font_px(_z)" not in sync_fn and "_capital_star_font_px( _z )" not in sync_fn:
		_fail("_sync_capital_star_scales must honor the wheel-measured zoom override")
		return
	_pass("source needles (live font px + sync uses _z)")


func _setup_map_renderer() -> bool:
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("MapRenderer.gd failed to load")
		return false
	_svp = SubViewport.new()
	_svp.name = "Perf2StarViewport"
	_svp.size = PLAY_SIZE
	_svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_svp.transparent_bg = false
	_svp.handle_input_locally = false
	root.add_child(_svp)
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0.08, 0.10, 0.14, 1.0)
	bg.size = Vector2(PLAY_SIZE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_svp.add_child(bg)
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer.new() failed")
		return false
	_container = Node2D.new()
	_container.name = "ProvinceContainers"
	_mr.add_child(_container)
	if "container" in _mr:
		_mr.container = _container
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = STAR_WORLD
	_cam.zoom = Vector2(OP_Z, OP_Z)
	_cam.enabled = true
	_mr.add_child(_cam)
	_svp.add_child(_mr)
	_cam.make_current()
	_mr.set_process_input(false)
	_mr.set_process(false)
	_pass("MapRenderer + SubViewport fixture ready")
	return true


func _seed_capital() -> void:
	var cents: Dictionary = {}
	if "province_centroids" in _mr:
		cents = _mr.get("province_centroids") as Dictionary
	cents[BERLIN] = STAR_WORLD
	var host := Node2D.new()
	host.name = "Prov_%d" % BERLIN
	host.position = Vector2.ZERO
	host.z_index = 4
	_container.add_child(host)
	var poly := Polygon2D.new()
	poly.name = "Fill"
	poly.polygon = PackedVector2Array([
		STAR_WORLD + Vector2(-80, -60),
		STAR_WORLD + Vector2(80, -60),
		STAR_WORLD + Vector2(80, 60),
		STAR_WORLD + Vector2(-80, 60),
	])
	poly.color = Color(0.16, 0.22, 0.20, 1.0)
	poly.z_index = 0
	host.add_child(poly)
	if "province_nodes" in _mr:
		_mr.province_nodes[BERLIN] = host
	if "province_centroids" in _mr:
		_mr.province_centroids = cents
	if _mr.has_method("_add_capital_star_to_node"):
		_mr.call("_add_capital_star_to_node", host, BERLIN)
	else:
		_fail("_add_capital_star_to_node missing")
		return
	_star = _find_star(host)
	if _star == null:
		_fail("capital star Label was not stamped")
		return
	_info("seeded Berlin capital star at %s" % str(STAR_WORLD))


func _find_star(host: Node2D) -> Label:
	for child in host.get_children():
		if child is Label and (child as Label).has_meta(META_STAR):
			return child as Label
	return null


func _measure_at_zoom(name_s: String, z: float) -> Dictionary:
	_cam.zoom = Vector2(z, z)
	_cam.position = STAR_WORLD
	_cam.make_current()
	# Live wheel path — not `_layout_zoomed_map_glyphs_for_province_node`.
	if _mr.has_method("_invalidate_capital_star_scale_cache"):
		_mr.call("_invalidate_capital_star_scale_cache")
	if _mr.has_method("_refresh_terrain_zoom_light"):
		_mr.call("_refresh_terrain_zoom_light")
	elif _mr.has_method("_sync_capital_star_scales"):
		_mr.call("_sync_capital_star_scales", z)
	if _star != null:
		_star.reset_size()
	await _flush()
	if _svp != null:
		_svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var font_px: int = _star_font_px()
	var canvas_px := _star_canvas_span()
	var ink: Dictionary = _capture_ink_bbox()
	var ink_px := float(ink.get("span", -1.0))
	var screen_px := ink_px if ink_px >= 4.0 else canvas_px
	var formula_px: int = -1
	if _mr != null and _mr.has_method("_capital_star_font_px"):
		# b16b9b53 takes no zoom arg; extra args error there.
		if _mr.get_method_argument_count("_capital_star_font_px") >= 1:
			formula_px = int(_mr.call("_capital_star_font_px", z))
		else:
			formula_px = int(_mr.call("_capital_star_font_px"))
	_info(
		"%s z=%.3f font=%d formula=%d canvas=%.1f ink=%.1f screen=%.1f ink_n=%d"
		% [
			name_s,
			z,
			font_px,
			formula_px,
			canvas_px,
			ink_px,
			screen_px,
			int(ink.get("n", 0)),
		]
	)
	return {
		"name": name_s,
		"z": z,
		"font_px": font_px,
		"formula_px": formula_px,
		"canvas_px": canvas_px,
		"ink_px": ink_px,
		"screen_px": screen_px,
		"ink_n": int(ink.get("n", 0)),
	}


func _assert_band(name_s: String, m: Dictionary, high: bool) -> void:
	var screen_px := float(m.get("screen_px", -1.0))
	var font_px := int(m.get("font_px", -1))
	var formula_px := int(m.get("formula_px", -1))
	if screen_px < 4.0:
		_fail("%s star screen_px=%.1f (nothing drawn)" % [name_s, screen_px])
		return
	if high:
		var want_screen := TACTICAL_MIN_SCREEN_PX if name_s == "tactical" else DEEP_MIN_SCREEN_PX
		if font_px < HIGH_MIN_FONT_PX:
			_fail(
				"%s live font_px=%d < %d (wheel sync still idle-capped; formula=%d screen=%.1f)"
				% [name_s, font_px, HIGH_MIN_FONT_PX, formula_px, screen_px]
			)
		else:
			_pass("%s live font_px=%d" % [name_s, font_px])
		if formula_px < HIGH_MIN_FONT_PX:
			_fail("%s _capital_star_font_px=%d (want 18–36 clamp, 36 at z>=2)" % [name_s, formula_px])
		else:
			_pass("%s live formula_px=%d" % [name_s, formula_px])
		if screen_px + 0.05 < want_screen:
			_fail(
				"%s screen_px=%.1f < %.0f (b16b9b53 idle 11 px * camera cannot reach this)"
				% [name_s, screen_px, want_screen]
			)
		else:
			_pass("%s screen_px=%.1f (>= %.0f)" % [name_s, screen_px, want_screen])
	else:
		if screen_px > OP_MAX_SCREEN_PX:
			_fail("%s operational screen_px=%.1f > %.0f" % [name_s, screen_px, OP_MAX_SCREEN_PX])
		else:
			_pass("%s operational screen_px=%.1f" % [name_s, screen_px])


func _assert_grew(op: Dictionary, later: Dictionary, name_s: String) -> void:
	var a := float(op.get("screen_px", -1.0))
	var b := float(later.get("screen_px", -1.0))
	if a < 4.0 or b < 4.0:
		_fail("%s grow check missing sizes op=%.1f later=%.1f" % [name_s, a, b])
		return
	if b + 0.05 < a * GROW_RATIO:
		_fail("%s screen_px=%.1f did not grow vs operational %.1f (need ≥%.2f×)" % [name_s, b, a, GROW_RATIO])
	else:
		_pass("%s screen_px=%.1f > operational %.1f" % [name_s, b, a])


func _star_font_px() -> int:
	if _star == null or not is_instance_valid(_star):
		return -1
	if _star.has_theme_font_size_override("font_size"):
		return int(_star.get_theme_font_size("font_size"))
	return -1


func _star_canvas_span() -> float:
	if _star == null or not is_instance_valid(_star):
		return -1.0
	_star.reset_size()
	var xf: Transform2D = _star.get_global_transform_with_canvas()
	var r: Rect2 = _star.get_rect()
	var pts: Array[Vector2] = [
		xf * r.position,
		xf * Vector2(r.position.x + r.size.x, r.position.y),
		xf * Vector2(r.position.x, r.position.y + r.size.y),
		xf * (r.position + r.size),
	]
	var min_x := pts[0].x
	var max_x := pts[0].x
	var min_y := pts[0].y
	var max_y := pts[0].y
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return maxf(max_x - min_x, max_y - min_y)


func _capture_ink_bbox() -> Dictionary:
	# Dummy headless renderer has no GPU texture (`texture_2d_get` t=null).
	# Do not call get_image() there — that is a SCRIPT ERROR. Screen size is
	# still the Label's canvas-transform span on this same SubViewport.
	if str(DisplayServer.get_name()).to_lower().contains("headless"):
		return {"span": -1.0, "n": 0}
	if _svp == null or not is_instance_valid(_svp):
		return {"span": -1.0, "n": 0}
	var tex: ViewportTexture = _svp.get_texture()
	if tex == null:
		return {"span": -1.0, "n": 0}
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 8:
		return {"span": -1.0, "n": 0}
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var search := mini(mini(w, h) / 2, 180)
	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1
	var n := 0
	var y := maxi(cy - search, 0)
	var y1 := mini(cy + search, h - 1)
	while y <= y1:
		var x := maxi(cx - search, 0)
		var x1 := mini(cx + search, w - 1)
		while x <= x1:
			var c: Color = img.get_pixel(x, y)
			if _is_star_ink(c):
				n += 1
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y
			x += 1
		y += 1
	if n < 4 or max_x < min_x:
		return {"span": -1.0, "n": n}
	var span := float(maxi(max_x - min_x + 1, max_y - min_y + 1))
	return {"span": span, "n": n, "w": max_x - min_x + 1, "h": max_y - min_y + 1}


func _is_star_ink(c: Color) -> bool:
	return c.r > 0.55 and c.g > 0.38 and c.b < 0.48 and (c.r - c.b) > 0.22


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt_a := src.find("\nfunc ", i + needle.length())
	var nxt_b := src.find("\nstatic func ", i + needle.length())
	var nxt := -1
	if nxt_a >= 0 and nxt_b >= 0:
		nxt = mini(nxt_a, nxt_b)
	elif nxt_a >= 0:
		nxt = nxt_a
	else:
		nxt = nxt_b
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _cleanup() -> void:
	if _svp != null and is_instance_valid(_svp):
		_svp.queue_free()
	_svp = null
	_mr = null
	_cam = null
	_container = null
	_star = null
