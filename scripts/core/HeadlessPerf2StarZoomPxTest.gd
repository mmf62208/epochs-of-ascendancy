extends SceneTree

## PERF-2 live star zoom: crisp 18–36 px stars, font never below the target.
## d3fc8c3d shrank font to 4 px at z=5.62 and scaled the Control up, so the
## live glyph was a 6–7 px blur. Font must stay at the on-screen size (18–36);
## the node is counter-scaled by 1/(camera zoom × glyph box) so the ★ is
## rasterised at its final size. On-screen ink is measured from a real
## viewport capture — never from a computed transform. Dummy --headless
## cannot grab GPU pixels: report RESULT=SKIP (render-only, needs xvfb).
## Full ink asserts run only under the xvfb wrapper.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x720 \
##     -s res://scripts/core/HeadlessPerf2StarZoomPxTest.gd   # SKIP
##   tools/eoa_perf2_star_zoom_px_guard.sh
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/run_godot.sh --path . \
##     --resolution 1280x720 -s res://scripts/core/HeadlessPerf2StarZoomPxTest.gd

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const PLAY_SIZE := Vector2i(1280, 720)
const OP_Z := 0.760
const TACTICAL_Z := 2.00
const DEEP_Z := 5.62
const BERLIN := 710300
const STAR_WORLD := Vector2(4000.0, 1600.0)
const META_STAR := &"_map_glyph_capital"
const FLUSH_FRAMES := 8
const SCREEN_MIN_PX := 18.0
const SCREEN_MAX_PX := 36.0
const FONT_MIN_PX := 14
const DEEP_INK_MIN_PX := 18.0

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null
var _star: Label = null
var _capture_ok: bool = false
var _capture_why: String = ""


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	if _is_dummy_renderer():
		_skip_dummy("render-only, needs xvfb")
		return
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf2StarZoomPxTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf2StarZoomPxTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _is_dummy_renderer() -> bool:
	var ds := str(DisplayServer.get_name()).to_lower()
	if ds.contains("headless") or ds.contains("dummy"):
		return true
	for arg in OS.get_cmdline_args():
		if str(arg) == "--headless":
			return true
	return false


func _skip_dummy(why: String) -> void:
	print("HeadlessPerf2StarZoomPxTest: SKIP (", why, ")")
	print("HeadlessPerf2StarZoomPxTest: RESULT=SKIP")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0)


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
	_assert_font_floor("operational", op)
	_assert_font_floor("tactical", tac)
	_assert_font_floor("deep", deep)
	_assert_ink_band("operational", op)
	_assert_ink_band("tactical", tac)
	_assert_ink_band("deep", deep)
	_assert_deep_ink(deep)
	_assert_monotone(op, tac, deep)
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
	if "/ denom" in px_fn or "screen / denom" in px_fn:
		_fail("_capital_star_font_px must not shrink font by zoom (d3fc8c3d 4 px smudge)")
		return
	if "CAPITAL_STAR_SCREEN_MAX" not in px_fn and "CAPITAL_STAR_SCREEN_MIN" not in px_fn:
		_fail("_capital_star_font_px must keep font at the 18–36 on-screen target")
		return
	var fit_fn := _slice_func(src, "_capital_star_apply_screen_fit")
	if fit_fn.is_empty():
		_fail("_capital_star_apply_screen_fit missing")
		return
	if "1.0 / maxf(z" not in fit_fn and "1.0 / maxf( z" not in fit_fn:
		_fail("_capital_star_apply_screen_fit must counter-scale by 1/(camera zoom × glyph box)")
		return
	var sync_fn := _slice_func(src, "_sync_capital_star_scales")
	if "_capital_star_font_px(_z)" not in sync_fn and "_capital_star_font_px( _z )" not in sync_fn:
		_fail("_sync_capital_star_scales must honor the wheel-measured zoom override")
		return
	_pass("source needles (font=target, counter-scale 1/(z×glyph))")


func _setup_map_renderer() -> bool:
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("MapRenderer.gd failed to load")
		return false
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0.55, 0.04, 0.08, 1.0)
	bg.size = Vector2(PLAY_SIZE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
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
	root.add_child(_mr)
	_cam.make_current()
	_mr.set_process_input(false)
	_mr.set_process(false)
	_pass("MapRenderer + root viewport fixture ready")
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
	poly.color = Color(0.62, 0.05, 0.08, 1.0)
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
	if _mr.has_method("_invalidate_capital_star_scale_cache"):
		_mr.call("_invalidate_capital_star_scale_cache")
	if _mr.has_method("_refresh_terrain_zoom_light"):
		_mr.call("_refresh_terrain_zoom_light")
	elif _mr.has_method("_sync_capital_star_scales"):
		_mr.call("_sync_capital_star_scales", z)
	await _flush()
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var font_px: int = _star_font_px()
	var ink: Dictionary = _capture_ink_bbox()
	var ink_px := float(ink.get("span", -1.0))
	var formula_px: int = -1
	if _mr != null and _mr.has_method("_capital_star_font_px"):
		if _mr.get_method_argument_count("_capital_star_font_px") >= 1:
			formula_px = int(_mr.call("_capital_star_font_px", z))
		else:
			formula_px = int(_mr.call("_capital_star_font_px"))
	_info(
		"%s z=%.3f font=%d formula=%d ink=%.1f ink_n=%d capture=%s"
		% [
			name_s,
			z,
			font_px,
			formula_px,
			ink_px,
			int(ink.get("n", 0)),
			"ok" if _capture_ok else _capture_why,
		]
	)
	return {
		"name": name_s,
		"z": z,
		"font_px": font_px,
		"formula_px": formula_px,
		"ink_px": ink_px,
		"ink_n": int(ink.get("n", 0)),
		"capture_ok": _capture_ok,
	}


func _assert_font_floor(name_s: String, m: Dictionary) -> void:
	var font_px := int(m.get("font_px", -1))
	if font_px < FONT_MIN_PX:
		_fail(
			"%s font_px=%d < %d (d3fc8c3d dropped font to 4 and scaled the smudge)"
			% [name_s, font_px, FONT_MIN_PX]
		)
	else:
		_pass("%s font_px=%d >= %d" % [name_s, font_px, FONT_MIN_PX])


func _assert_ink_band(name_s: String, m: Dictionary) -> void:
	if not bool(m.get("capture_ok", false)):
		_fail(
			"%s no rendered capture (%s) — will not substitute a transform"
			% [name_s, _capture_why]
		)
		return
	var ink_px := float(m.get("ink_px", -1.0))
	if ink_px < 4.0:
		_fail("%s ink bbox=%.1f (star not in the captured image)" % [name_s, ink_px])
		return
	# Operational 20 px font has an ~11 px bright core (play 0.79). The 18–36
	# cap is the high-zoom on-screen target; require it from tactical up.
	if name_s == "operational":
		if ink_px < 8.0:
			_fail("%s ink bbox=%.1f (expected a visible 20 px star core)" % [name_s, ink_px])
		else:
			_pass("%s ink bbox=%.1f (20 px font core)" % [name_s, ink_px])
		return
	if ink_px + 0.05 < SCREEN_MIN_PX or ink_px > SCREEN_MAX_PX + 2.0:
		_fail("%s ink bbox=%.1f outside 18–36" % [name_s, ink_px])
	else:
		_pass("%s ink bbox=%.1f in 18–36" % [name_s, ink_px])


func _assert_deep_ink(deep: Dictionary) -> void:
	if not bool(deep.get("capture_ok", false)):
		return
	var ink_px := float(deep.get("ink_px", -1.0))
	if ink_px + 0.05 < DEEP_INK_MIN_PX:
		_fail("deep ink bbox=%.1f < %.0f (d3fc8c3d 4 px font is a 6–7 px smudge)" % [ink_px, DEEP_INK_MIN_PX])
	else:
		_pass("deep ink bbox=%.1f >= %.0f" % [ink_px, DEEP_INK_MIN_PX])


func _assert_monotone(op: Dictionary, tac: Dictionary, deep: Dictionary) -> void:
	if not (
		bool(op.get("capture_ok", false))
		and bool(tac.get("capture_ok", false))
		and bool(deep.get("capture_ok", false))
	):
		_fail("monotone skipped — no rendered capture")
		return
	var a := float(op.get("ink_px", -1.0))
	var b := float(tac.get("ink_px", -1.0))
	var c := float(deep.get("ink_px", -1.0))
	if a < 4.0 or b < 4.0 or c < 4.0:
		_fail("monotone check missing ink op=%.1f tac=%.1f deep=%.1f" % [a, b, c])
		return
	# 1 px slop: same 36 px font + 1/z counter-scale can quantize 26 vs 25.
	if b + 1.05 < a:
		_fail("tactical ink=%.1f shrank vs operational %.1f" % [b, a])
	else:
		_pass("tactical ink=%.1f >= operational %.1f" % [b, a])
	if c + 1.05 < b:
		_fail("deep ink=%.1f shrank vs tactical %.1f" % [c, b])
	else:
		_pass("deep ink=%.1f >= tactical %.1f" % [c, b])
	if c + 1.05 < a:
		_fail("deep ink=%.1f < operational %.1f" % [c, a])
	else:
		_pass("deep ink=%.1f >= operational %.1f" % [c, a])


func _star_font_px() -> int:
	if _star == null or not is_instance_valid(_star):
		return -1
	if _star.has_theme_font_size_override("font_size"):
		return int(_star.get_theme_font_size("font_size"))
	return -1


func _grab_viewport_image() -> Image:
	_capture_ok = false
	_capture_why = ""
	var ds := str(DisplayServer.get_name())
	if ds.to_lower().contains("headless"):
		_capture_why = "DisplayServer=%s dummy (need xvfb, no --headless)" % ds
		return null
	var vp := root.get_viewport()
	if vp == null:
		_capture_why = "root viewport missing"
		return null
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		_capture_why = "viewport texture null"
		return null
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 8:
		_capture_why = "get_image() null or tiny (dummy GPU)"
		return null
	_capture_ok = true
	_capture_why = "ok %dx%d ds=%s" % [img.get_width(), img.get_height(), ds]
	return img


func _capture_ink_bbox() -> Dictionary:
	var img: Image = _grab_viewport_image()
	if img == null:
		_info("capture skipped: " + _capture_why)
		return {"span": -1.0, "n": 0}
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var search := mini(mini(w, h) / 2, 80)
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
	var gold := c.r > 0.62 and c.g > 0.45 and c.b < 0.48 and (c.r - c.b) > 0.22
	var halo := c.r > 0.48 and c.g > 0.32 and c.b < 0.42 and (c.r + c.g) > c.b * 2.8
	return gold or halo


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
	_mr = null
	_cam = null
	_container = null
	_star = null
