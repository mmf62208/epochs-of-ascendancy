extends SceneTree

## VIS-1: first-session map readability — paused Home / Shift+Home hide capital
## stars; L on then L off leaves no supply-outline residue.
## Drives real keys through the viewport (not _input / _unhandled_input).
## Does not load WorldMap.tscn / 3520. Headless is NOT live Play.
## Never set EOA_SKIP_TITLE.
## EOA_VIS1_BEHAVIOR_ONLY=1 skips source-text needles (mutation table).
##
##   tools/run_godot.sh --headless --path . --resolution 1280x720 \
##     -s res://scripts/core/HeadlessVis1MapReadabilityTest.gd

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")
const ProvinceMapVisualsScript = preload("res://scripts/map/ProvinceMapVisuals.gd")

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const PLAY_SIZE := Vector2i(1280, 720)
const CLOSE_Z := 0.945
const HOME_STRATEGIC_MAX := 0.55
const BERLIN := 710300
const PARIS := 710707
const ROME := 710963
const ROUTE_PID := 710173
const CAPITAL_PIDS: Array[int] = [710300, 710707, 710963, 711414, 710416, 710417, 710418, 710451]
const META_STAR := &"_map_glyph_capital"
const FLUSH_FRAMES := 4

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null
var _home_ms: float = 0.0
var _shift_home_ms: float = 0.0
var _l_on_ms: float = 0.0
var _l_off_ms: float = 0.0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessVis1MapReadabilityTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessVis1MapReadabilityTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessVis1MapReadabilityTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessVis1MapReadabilityTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessVis1MapReadabilityTest: ", msg)


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


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	root.size = PLAY_SIZE
	if OS.get_environment("EOA_VIS1_BEHAVIOR_ONLY") != "1":
		_assert_source_needles()
	else:
		_info("EOA_VIS1_BEHAVIOR_ONLY=1 — source-text needles skipped")
	if not _setup_map_renderer():
		return
	_pause_sim()
	_seed_capitals_and_polys()
	await _flush()
	await _assert_paused_home_hides_stars()
	await _assert_paused_shift_home_hides_stars()
	await _assert_l_toggle_clears_outlines()
	_info(
		"home_ms=%.2f shift_home_ms=%.2f l_on_ms=%.2f l_off_ms=%.2f (fixture, not 3520 GL)"
		% [_home_ms, _shift_home_ms, _l_on_ms, _l_off_ms]
	)
	_cleanup()


func _assert_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var home_fn := _slice_func(ren, "center_europe_in_world_view")
	if "_sync_capital_star_scales" not in home_fn:
		_fail("center_europe_in_world_view must resync capital stars after the Home camera jump")
	else:
		_pass("Home Europe path resyncs capital stars")
	var shift_fn := _slice_func(ren, "_apply_home_key")
	if "_sync_capital_star_scales" not in shift_fn:
		_fail("_apply_home_key Shift+Home must resync capital stars")
	else:
		_pass("Shift+Home resyncs capital stars")
	var sup_fn := _slice_func(ren, "_refresh_supply_highlights")
	if "prev_pids" not in sup_fn or "hide_polished_outline" not in sup_fn:
		_fail("_refresh_supply_highlights must hide leftover SupplyOutline on L off")
	else:
		_pass("L-off refresh hides leftover supply outlines")
	if "center_europe_in_world_view" not in shift_fn:
		_fail("Home framing path must stay center_europe_in_world_view")
	else:
		_pass("Home framing still center_europe_in_world_view")


func _setup_map_renderer() -> bool:
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("MapRenderer.gd failed to load")
		return false
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
	_cam.position = Vector2(4200.0, 1800.0)
	_cam.zoom = Vector2(CLOSE_Z, CLOSE_Z)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_mr.set_process_input(true)
	_mr.set_process_unhandled_input(true)
	if "_close_camera_locked" in _mr:
		_mr.set("_close_camera_locked", false)
	_pass("MapRenderer fixture ready")
	return true


func _pause_sim() -> void:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if tm == null or not bool(tm.call("is_paused")):
		_fail("TimeManager must be paused for the Home path")
		return
	_pass("sim paused (TimeManager.is_paused)")


func _seed_capitals_and_polys() -> void:
	var cents: Dictionary = {}
	if "province_centroids" in _mr:
		cents = _mr.get("province_centroids") as Dictionary
	# Wide Europe trio so Home fit lands below STRATEGIC_MAX_ZOOM 0.55.
	var seed_pos: Dictionary = {
		BERLIN: Vector2(4200.0, 1600.0),
		PARIS: Vector2(2800.0, 2000.0),
		ROME: Vector2(4000.0, 3200.0),
		711414: Vector2(3600.0, 1500.0),
		710416: Vector2(4100.0, 1750.0),
		710417: Vector2(4120.0, 1780.0),
		710418: Vector2(4140.0, 1810.0),
		710451: Vector2(4050.0, 1900.0),
		ROUTE_PID: Vector2(3900.0, 2100.0),
	}
	for pid in seed_pos.keys():
		var p: int = int(pid)
		var pos: Vector2 = seed_pos[p] as Vector2
		cents[p] = pos
		var host := Node2D.new()
		host.name = "Prov_%d" % p
		host.position = Vector2.ZERO
		_container.add_child(host)
		var poly := Polygon2D.new()
		poly.name = "Fill"
		poly.polygon = PackedVector2Array([
			pos + Vector2(-40, -30),
			pos + Vector2(40, -30),
			pos + Vector2(40, 30),
			pos + Vector2(-40, 30),
		])
		poly.color = Color(0.35, 0.42, 0.38, 0.96)
		host.add_child(poly)
		if "province_nodes" in _mr:
			_mr.province_nodes[p] = host
		if CAPITAL_PIDS.has(p):
			_stamp_star(host, pos)
	if "province_centroids" in _mr:
		_mr.province_centroids = cents
	if "selected_province_id" in _mr:
		_mr.selected_province_id = BERLIN
	_info("seeded %d capitals + route pid %d" % [CAPITAL_PIDS.size(), ROUTE_PID])


func _stamp_star(host: Node2D, center: Vector2) -> void:
	var star := Label.new()
	star.text = "★"
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.add_theme_font_size_override("font_size", 18)
	star.set_meta(META_STAR, true)
	star.visible = true
	star.reset_size()
	var sms := star.get_minimum_size()
	star.position = center - sms * 0.5
	host.add_child(star)


func _visible_star_count() -> int:
	var n := 0
	if _mr == null or not ("province_nodes" in _mr):
		return 0
	var nodes: Dictionary = _mr.province_nodes
	for pid_v in nodes.keys():
		var node: Node2D = nodes[pid_v] as Node2D
		if node == null:
			continue
		for child in node.get_children():
			if child is Label and (child as Label).has_meta(META_STAR) and (child as Label).visible:
				n += 1
	return n


func _visible_supply_outline_count() -> int:
	var n := 0
	if _mr == null or not ("province_nodes" in _mr):
		return 0
	var nodes: Dictionary = _mr.province_nodes
	for pid_v in nodes.keys():
		var node: Node2D = nodes[pid_v] as Node2D
		if node == null:
			continue
		for child in node.get_children():
			if not (child is Line2D):
				continue
			var ln := child as Line2D
			var nm := str(ln.name)
			if (nm == "SupplyOutline" or nm == "SupplyOutlineGlow") and ln.visible:
				n += 1
	return n


func _make_key(key: Key, pressed: bool, shift_pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = pressed
	ev.echo = false
	ev.keycode = key
	ev.physical_keycode = key
	ev.shift_pressed = shift_pressed
	return ev


func _deliver_key_event(ev: InputEventKey) -> void:
	# Viewport / Input pipeline. Do not call _input or _unhandled_input —
	# a direct call would hide a Shift+Home path that never receives real events.
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _press_key(key: Key, shift_pressed: bool = false) -> void:
	_deliver_key_event(_make_key(key, true, shift_pressed))
	_deliver_key_event(_make_key(key, false, shift_pressed))


func _cam_zoom() -> float:
	if _cam == null:
		return 0.0
	return maxf(absf(_cam.zoom.x), absf(_cam.zoom.y))


func _assert_paused_home_hides_stars() -> void:
	_cam.zoom = Vector2(CLOSE_Z, CLOSE_Z)
	_cam.position = Vector2(4200.0, 1800.0)
	if _mr.has_method("_refresh_terrain_zoom_light"):
		_mr.call("_refresh_terrain_zoom_light")
	await _flush()
	var n_close := _visible_star_count()
	_info("paused close z=%.3f visible_stars=%d" % [_cam_zoom(), n_close])
	if n_close < CAPITAL_PIDS.size():
		_fail("close zoom must show capital stars (got %d want %d)" % [n_close, CAPITAL_PIDS.size()])
	else:
		_pass("paused close zoom shows %d capital stars" % n_close)
	var t0 := Time.get_ticks_usec()
	_press_key(KEY_HOME, false)
	_home_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	await _flush()
	var z_home := _cam_zoom()
	var n_home := _visible_star_count()
	_info("paused Home z=%.3f visible_stars=%d home_ms=%.2f" % [z_home, n_home, _home_ms])
	if z_home > HOME_STRATEGIC_MAX:
		_fail("Home camera z=%.3f must be <= STRATEGIC_MAX_ZOOM %.2f" % [z_home, HOME_STRATEGIC_MAX])
	else:
		_pass("Home camera z=%.3f is strategic" % z_home)
	if n_home != 0:
		_fail("paused Home left %d capital stars visible (want 0, same as a wheel notch)" % n_home)
	else:
		_pass("paused Home hides capital stars")
	if _home_ms > 250.0:
		_fail("Home fixture frame %.2fms looks like a 3520 rebuild" % _home_ms)
	else:
		_pass("Home stay-cheap %.2fms" % _home_ms)


func _assert_paused_shift_home_hides_stars() -> void:
	# Close zoom + 8 visible stars, then a real Home with Shift held.
	# Must fail if _apply_home_key skips _sync_capital_star_scales (even when
	# the source-text needle is hidden).
	_cam.zoom = Vector2(CLOSE_Z, CLOSE_Z)
	_cam.position = Vector2(4200.0, 1800.0)
	if _mr.has_method("_refresh_terrain_zoom_light"):
		_mr.call("_refresh_terrain_zoom_light")
	await _flush()
	var n_close := _visible_star_count()
	_info("paused close-before-Shift+Home z=%.3f visible_stars=%d" % [_cam_zoom(), n_close])
	if n_close < CAPITAL_PIDS.size():
		_fail("close zoom before Shift+Home must show capital stars (got %d want %d)" % [n_close, CAPITAL_PIDS.size()])
	else:
		_pass("paused close zoom before Shift+Home shows %d capital stars" % n_close)
	var t0 := Time.get_ticks_usec()
	_press_key(KEY_HOME, true)
	_shift_home_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	await _flush()
	var z_shift := _cam_zoom()
	var n_shift := _visible_star_count()
	_info("paused Shift+Home z=%.3f visible_stars=%d shift_home_ms=%.2f" % [z_shift, n_shift, _shift_home_ms])
	if z_shift > HOME_STRATEGIC_MAX:
		_fail("Shift+Home camera z=%.3f must be <= STRATEGIC_MAX_ZOOM %.2f" % [z_shift, HOME_STRATEGIC_MAX])
	else:
		_pass("Shift+Home camera z=%.3f is strategic" % z_shift)
	if n_shift != 0:
		_fail("paused Shift+Home left %d capital stars visible (want 0)" % n_shift)
	else:
		_pass("paused Shift+Home hides capital stars")
	if _shift_home_ms > 250.0:
		_fail("Shift+Home fixture frame %.2fms looks like a 3520 rebuild" % _shift_home_ms)
	else:
		_pass("Shift+Home stay-cheap %.2fms" % _shift_home_ms)


func _assert_l_toggle_clears_outlines() -> void:
	var sm: Node = root.get_node_or_null("SupplyManager")
	if sm == null:
		_fail("SupplyManager autoload missing — cannot drive real L")
		return
	if bool(_mr.get("supply_mode")):
		_mr.call("_toggle_supply_overlay")
	var t_on := Time.get_ticks_usec()
	_press_key(KEY_L, false)
	_l_on_ms = float(Time.get_ticks_usec() - t_on) / 1000.0
	await _flush()
	if not bool(_mr.get("supply_mode")):
		_fail("L on did not set supply_mode")
		return
	# Real L-on paints the selected hex. Also stamp a yellow route ring — that
	# is the playtest residue color (OUTLINE_SUPPLY_ROUTE) that covered stars.
	_stamp_yellow_route_ring()
	var n_on := _visible_supply_outline_count()
	_info("L on outlines=%d l_on_ms=%.2f" % [n_on, _l_on_ms])
	if n_on <= 0:
		_fail("L on must draw at least one SupplyOutline")
		return
	_pass("L on drew %d supply outline nodes" % n_on)
	var t_off := Time.get_ticks_usec()
	_press_key(KEY_L, false)
	_l_off_ms = float(Time.get_ticks_usec() - t_off) / 1000.0
	await _flush()
	if bool(_mr.get("supply_mode")):
		_fail("L off left supply_mode true")
	else:
		_pass("L off cleared supply_mode")
	var n_off := _visible_supply_outline_count()
	var roles: Dictionary = _mr.get("_supply_role_by_province") as Dictionary
	_info("L off outlines=%d roles=%d l_off_ms=%.2f" % [n_off, roles.size(), _l_off_ms])
	if n_off != 0:
		_fail("L off left %d SupplyOutline/Glow nodes visible (yellow residue)" % n_off)
	else:
		_pass("L off hid all supply outlines")
	if not roles.is_empty():
		_fail("L off left _supply_role_by_province n=%d" % roles.size())
	else:
		_pass("L off cleared supply role dict")
	if _l_off_ms > 250.0:
		_fail("L-off fixture %.2fms walked too much" % _l_off_ms)
	else:
		_pass("L-off stay-cheap %.2fms" % _l_off_ms)


func _stamp_yellow_route_ring() -> void:
	var host: Node2D = _mr.province_nodes.get(ROUTE_PID) as Node2D
	if host == null:
		return
	var poly: PackedVector2Array = PackedVector2Array()
	for child in host.get_children():
		if child is Polygon2D:
			poly = (child as Polygon2D).polygon
			break
	if poly.size() < 3:
		return
	var style: Dictionary = ProvinceMapVisualsScript.get_supply_outline_style("route")
	ProvinceMapVisualsScript.ensure_polished_outline(
		host,
		poly,
		ProvinceMapVisualsScript.NODE_SUPPLY,
		style["color"],
		style["width"],
		style["glow"],
		style["glow_extra"],
		style["z_index"],
	)
	var roles: Dictionary = _mr.get("_supply_role_by_province") as Dictionary
	roles[ROUTE_PID] = "route"
	_mr.set("_supply_role_by_province", roles)


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	_mr = null
	_cam = null
	_container = null
