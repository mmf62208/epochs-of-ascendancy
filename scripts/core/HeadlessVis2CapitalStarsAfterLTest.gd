extends SceneTree

## VIS-2: capital stars keep their idle draw layer after an L supply cycle.
## After L on then L off at operational zoom, stars must still be drawable
## (z_index / z_as_relative / modulate), not merely visible-in-tree.
## Main `425b4448` leaves them at Z_MAP_GLYPH+2 (10, absolute) so they sit
## under Europe land / later canvas layers until a map-mode switch.
## Does not load WorldMap.tscn / 3520. Headless is NOT live Play.
## Never set EOA_SKIP_TITLE.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x720 \
##     -s res://scripts/core/HeadlessVis2CapitalStarsAfterLTest.gd

const ProvinceMapVisualsScript = preload("res://scripts/map/ProvinceMapVisuals.gd")

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const PLAY_SIZE := Vector2i(1280, 720)
const OP_Z := 0.760
const CAPITAL_STAR_Z := 40
const EUROPE_LAND_Z := 4
const BERLIN := 710300
const PARIS := 710707
const ROME := 710963
const LONDON := 711414
const CAPITAL_PIDS: Array[int] = [710300, 710707, 710963, 711414]
const META_STAR := &"_map_glyph_capital"
const FLUSH_FRAMES := 4

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessVis2CapitalStarsAfterLTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessVis2CapitalStarsAfterLTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessVis2CapitalStarsAfterLTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessVis2CapitalStarsAfterLTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessVis2CapitalStarsAfterLTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	root.size = PLAY_SIZE
	if not _setup_map_renderer():
		return
	_seed_capitals()
	await _flush()
	_set_operational_zoom()
	if _mr.has_method("_sync_capital_star_scales"):
		_mr.call("_sync_capital_star_scales", OP_Z)
	await _flush()
	var before: Dictionary = _star_draw_snapshot()
	_info(
		"before L z=%.3f stars=%d drawable=%d buried_z10=%d"
		% [OP_Z, int(before.get("n", 0)), int(before.get("drawable", 0)), int(before.get("buried", 0))]
	)
	if int(before.get("n", 0)) < CAPITAL_PIDS.size():
		_fail("fixture must stamp %d capital stars (got %d)" % [CAPITAL_PIDS.size(), int(before.get("n", 0))])
		_cleanup()
		return
	if int(before.get("drawable", 0)) < CAPITAL_PIDS.size():
		_fail("before L only %d/%d stars are on the idle draw layer" % [int(before.get("drawable", 0)), CAPITAL_PIDS.size()])
		_cleanup()
		return
	_pass("before L all %d stars are drawable at z>=%d" % [CAPITAL_PIDS.size(), CAPITAL_STAR_Z])
	if not await _drive_l_cycle():
		_cleanup()
		return
	# Re-apply the L-off glyph pass at the same camera (what _toggle ends with).
	if _mr.has_method("_sync_map_label_glyph_stack"):
		_mr.call("_sync_map_label_glyph_stack", OP_Z)
	await _flush()
	var after: Dictionary = _star_draw_snapshot()
	_info(
		"after L cycle z=%.3f stars=%d visible=%d drawable=%d buried_z10=%d min_eff_z=%d"
		% [
			OP_Z,
			int(after.get("n", 0)),
			int(after.get("visible", 0)),
			int(after.get("drawable", 0)),
			int(after.get("buried", 0)),
			int(after.get("min_eff_z", -1)),
		]
	)
	if int(after.get("n", 0)) < CAPITAL_PIDS.size():
		_fail("L cycle dropped stars from the tree (n=%d)" % int(after.get("n", 0)))
	else:
		_pass("L cycle kept %d star glyphs in the tree" % int(after.get("n", 0)))
	if int(after.get("visible", 0)) < CAPITAL_PIDS.size():
		_fail("after L cycle only %d/%d stars visible=true" % [int(after.get("visible", 0)), CAPITAL_PIDS.size()])
	else:
		_pass("after L cycle all stars still visible=true")
	var glyph_z := ProvinceMapVisualsScript.Z_MAP_GLYPH + 2
	if int(after.get("buried", 0)) > 0:
		_fail(
			"after L cycle %d star(s) left at glyph-stack z=%d (want idle z>=%d, not just visible-in-tree)"
			% [int(after.get("buried", 0)), glyph_z, CAPITAL_STAR_Z]
		)
	else:
		_pass("after L cycle no star remains at glyph-stack z=%d" % glyph_z)
	if int(after.get("drawable", 0)) < CAPITAL_PIDS.size():
		_fail(
			"after L cycle only %d/%d stars have effective draw z>=%d (min_eff_z=%d)"
			% [
				int(after.get("drawable", 0)),
				CAPITAL_PIDS.size(),
				CAPITAL_STAR_Z,
				int(after.get("min_eff_z", -1)),
			]
		)
	else:
		_pass("after L cycle all stars keep idle draw layer z>=%d" % CAPITAL_STAR_Z)
	_cleanup()


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
	_cam.zoom = Vector2(OP_Z, OP_Z)
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


func _seed_capitals() -> void:
	var cents: Dictionary = {}
	if "province_centroids" in _mr:
		cents = _mr.get("province_centroids") as Dictionary
	var seed_pos: Dictionary = {
		BERLIN: Vector2(4200.0, 1600.0),
		PARIS: Vector2(2800.0, 2000.0),
		ROME: Vector2(4000.0, 3200.0),
		LONDON: Vector2(3600.0, 1500.0),
	}
	for pid in seed_pos.keys():
		var p: int = int(pid)
		var pos: Vector2 = seed_pos[p] as Vector2
		cents[p] = pos
		var host := Node2D.new()
		host.name = "Prov_%d" % p
		host.position = Vector2.ZERO
		host.z_index = EUROPE_LAND_Z
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
		poly.z_index = 0
		host.add_child(poly)
		if "province_nodes" in _mr:
			_mr.province_nodes[p] = host
		if _mr.has_method("_add_capital_star_to_node"):
			_mr.call("_add_capital_star_to_node", host, p)
		else:
			_fail("_add_capital_star_to_node missing")
	if "province_centroids" in _mr:
		_mr.province_centroids = cents
	if "selected_province_id" in _mr:
		_mr.selected_province_id = BERLIN
	_info("seeded %d product capital stars" % CAPITAL_PIDS.size())


func _set_operational_zoom() -> void:
	_cam.zoom = Vector2(OP_Z, OP_Z)
	_cam.position = Vector2(4200.0, 1800.0)


func _star_effective_z(star: CanvasItem, host: Node2D) -> int:
	if star.z_as_relative:
		return int(host.z_index) + int(star.z_index)
	return int(star.z_index)


func _star_draw_snapshot() -> Dictionary:
	var n := 0
	var visible_n := 0
	var drawable := 0
	var buried := 0
	var min_eff := 999
	var glyph_z := ProvinceMapVisualsScript.Z_MAP_GLYPH + 2
	if _mr == null or not ("province_nodes" in _mr):
		return {"n": 0, "visible": 0, "drawable": 0, "buried": 0, "min_eff_z": -1}
	var nodes: Dictionary = _mr.province_nodes
	for pid_v in nodes.keys():
		var node: Node2D = nodes[pid_v] as Node2D
		if node == null:
			continue
		for child in node.get_children():
			if not (child is Label) or not (child as Label).has_meta(META_STAR):
				continue
			var star := child as Label
			n += 1
			if star.visible:
				visible_n += 1
			var eff := _star_effective_z(star, node)
			if eff < min_eff:
				min_eff = eff
			var a := star.modulate.a
			# Drawable = idle capital layer (z>=40, absolute, opaque), not the
			# supply glyph stack leftover (absolute z=10) that sits under land.
			if (
				star.visible
				and (not star.z_as_relative)
				and eff >= CAPITAL_STAR_Z
				and a >= 0.99
			):
				drawable += 1
			if star.z_index == glyph_z or (not star.z_as_relative and eff == glyph_z):
				buried += 1
	if n == 0:
		min_eff = -1
	return {
		"n": n,
		"visible": visible_n,
		"drawable": drawable,
		"buried": buried,
		"min_eff_z": min_eff,
	}


func _make_key(key: Key, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = pressed
	ev.echo = false
	ev.keycode = key
	ev.physical_keycode = key
	return ev


func _press_l() -> void:
	Input.parse_input_event(_make_key(KEY_L, true))
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	Input.parse_input_event(_make_key(KEY_L, false))
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _drive_l_cycle() -> bool:
	var sm: Node = root.get_node_or_null("SupplyManager")
	if sm == null:
		_fail("SupplyManager autoload missing — cannot drive real L")
		return false
	if bool(_mr.get("supply_mode")):
		_mr.call("_toggle_supply_overlay")
		await _flush()
	_set_operational_zoom()
	var t_on := Time.get_ticks_usec()
	_press_l()
	await _flush()
	var l_on_ms := float(Time.get_ticks_usec() - t_on) / 1000.0
	if not bool(_mr.get("supply_mode")):
		# Viewport may not deliver L in this fixture; the product path is the same.
		if _mr.has_method("_toggle_supply_overlay"):
			_mr.call("_toggle_supply_overlay")
			await _flush()
	if not bool(_mr.get("supply_mode")):
		_fail("L on did not set supply_mode")
		return false
	_pass("L on supply_mode=true (%.2fms)" % l_on_ms)
	_set_operational_zoom()
	var t_off := Time.get_ticks_usec()
	_press_l()
	await _flush()
	var l_off_ms := float(Time.get_ticks_usec() - t_off) / 1000.0
	if bool(_mr.get("supply_mode")):
		if _mr.has_method("_toggle_supply_overlay"):
			_mr.call("_toggle_supply_overlay")
			await _flush()
	if bool(_mr.get("supply_mode")):
		_fail("L off left supply_mode true")
		return false
	_pass("L off supply_mode=false (%.2fms)" % l_off_ms)
	_set_operational_zoom()
	return true


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
	_mr = null
	_cam = null
	_container = null
