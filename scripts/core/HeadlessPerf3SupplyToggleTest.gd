extends SceneTree

## PERF-3: L supply-overlay toggle must not rebuild 3k Line2D rings.
## Measures the real MapRenderer._toggle_supply_overlay path with a 3196-land
## board (same outline count as world_accurate Play). FAILS on main (create
## SupplyOutline+Glow per province every L-on; L-off early-returns without hide).
## PASSES when rings are built once and shown/hidden.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessPerf3SupplyToggleTest.gd

const LAND_N := 3196
const POLY_SIDES := 48
const MAX_TOGGLE_MS := 1000.0
const HOME_Z := 0.318
const OPS_Z := 0.760
const FLUSH_FRAMES := 4

var _failures: int = 0
var _measured: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf3SupplyToggleTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf3SupplyToggleTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf3SupplyToggleTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf3SupplyToggleTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessPerf3SupplyToggleTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _count_line2d_outlines(visible_only: bool) -> int:
	if _mr == null:
		return 0
	var nodes: Dictionary = _mr.get("province_nodes") as Dictionary
	var n := 0
	for pid in nodes.keys():
		var node: Node = nodes[pid] as Node
		if node == null:
			continue
		var line := node.get_node_or_null("SupplyOutline") as Line2D
		if line == null:
			continue
		if visible_only and not line.visible:
			continue
		n += 1
	return n


func _visible_outline_count() -> int:
	if _mr != null and _mr.has_method("get_supply_overlay_outline_visible_count"):
		return int(_mr.call("get_supply_overlay_outline_visible_count"))
	return _count_line2d_outlines(true)


func _rebuild_count() -> int:
	if _mr != null and _mr.has_method("get_supply_outline_rebuild_count"):
		return int(_mr.call("get_supply_outline_rebuild_count"))
	return _count_line2d_outlines(false)


func _time_toggle() -> float:
	var t0 := Time.get_ticks_usec()
	_mr.call("_toggle_supply_overlay")
	await process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)
	if not _setup_renderer():
		return
	await _flush()
	await _measure_at_zoom("Home", HOME_Z)
	await _measure_at_zoom("z0.760", OPS_Z)
	if _measured < 2:
		_fail("did not measure both zooms (setup aborted)")
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()


func _setup_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(4200, 1000)
	_cam.zoom = Vector2(HOME_Z, HOME_Z)
	_mr.add_child(_cam)
	_container = Node2D.new()
	_container.name = "ProvinceContainers"
	_mr.add_child(_container)
	_mr.container = _container
	root.add_child(_mr)
	_cam.make_current()
	var pscr: Script = load("res://scripts/data/Province.gd") as Script
	var sm: Node = root.get_node_or_null("SupplyManager")
	var mm: Node = root.get_node_or_null("MapManager")
	if sm == null:
		_fail("SupplyManager autoload missing")
		return false
	var depot_scr: Script = load("res://scripts/supply/ProvinceDepotState.gd") as Script
	var i := 0
	while i < LAND_N:
		var pid := 710000 + i
		var host := Node2D.new()
		host.name = "Prov_%d" % pid
		host.position = Vector2(float(i % 80) * 40.0, float(i / 80) * 40.0)
		var poly := Polygon2D.new()
		poly.polygon = _make_ring(24.0, POLY_SIDES)
		host.add_child(poly)
		_container.add_child(host)
		_mr.province_nodes[pid] = host
		if pscr != null:
			var p: Object = pscr.new()
			p.set("id", pid)
			p.set("name", "Land %d" % pid)
			p.set("owner_tag", "GER")
			p.set("controller_tag", "GER")
			p.set("infrastructure", 1)
			p.set("is_sea", false)
			_mr.provinces[pid] = p
			if mm != null and "_provinces" in mm:
				mm._provinces[pid] = p
		if depot_scr != null and "depot_states" in sm:
			sm.depot_states[pid] = depot_scr.new(pid, 100.0)
		i += 1
	if int(_mr.province_nodes.size()) < LAND_N:
		_fail("province_nodes seeded %d want %d" % [int(_mr.province_nodes.size()), LAND_N])
		return false
	if "overlay_visible" in sm:
		sm.overlay_visible = false
	_mr.supply_mode = false
	var depot_n := 0
	if "depot_states" in sm:
		depot_n = int((sm.get("depot_states") as Dictionary).size())
	_info("seeded land=%d poly_sides=%d depots=%d" % [LAND_N, POLY_SIDES, depot_n])
	return true


func _make_ring(radius: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sides)
	var i := 0
	while i < sides:
		var a := TAU * float(i) / float(sides)
		pts[i] = Vector2(cos(a), sin(a)) * radius
		i += 1
	return pts


func _measure_at_zoom(label: String, zoom: float) -> void:
	if _mr == null:
		_fail("renderer missing for %s" % label)
		return
	_measured += 1
	if bool(_mr.get("supply_mode")):
		_mr.call("_toggle_supply_overlay")
		await process_frame
	_cam.zoom = Vector2(zoom, zoom)
	await process_frame
	var rebuilds_before := _rebuild_count()
	var on_ms := await _time_toggle()
	var on_n := _visible_outline_count()
	var line_on := _count_line2d_outlines(true)
	var rebuilds_on := _rebuild_count()
	if not bool(_mr.get("supply_mode")):
		_fail("%s L-on did not set supply_mode" % label)
	if on_n < 3000:
		_fail("%s L-on visible outlines=%d want >=3000" % [label, on_n])
	else:
		_pass("%s L-on visible outlines=%d" % [label, on_n])
	if on_ms >= MAX_TOGGLE_MS:
		_fail("%s L-on %.1f ms (limit %.0f; main rebuilds 6k Line2Ds)" % [label, on_ms, MAX_TOGGLE_MS])
	else:
		_pass("%s L-on %.1f ms" % [label, on_ms])
	var off_ms := await _time_toggle()
	var off_n := _visible_outline_count()
	var line_off := _count_line2d_outlines(true)
	var rebuilds_off := _rebuild_count()
	if bool(_mr.get("supply_mode")):
		_fail("%s L-off left supply_mode on" % label)
	if off_n != 0 or line_off != 0:
		_fail("%s L-off still shows outlines batch=%d line2d=%d" % [label, off_n, line_off])
	else:
		_pass("%s L-off hid outlines" % label)
	if off_ms >= MAX_TOGGLE_MS:
		_fail("%s L-off %.1f ms (limit %.0f)" % [label, off_ms, MAX_TOGGLE_MS])
	else:
		_pass("%s L-off %.1f ms" % [label, off_ms])
	var on2_ms := await _time_toggle()
	var on2_n := _visible_outline_count()
	var rebuilds_on2 := _rebuild_count()
	if on2_n < 3000:
		_fail("%s second L-on visible=%d" % [label, on2_n])
	if on2_ms >= MAX_TOGGLE_MS:
		_fail("%s second L-on %.1f ms" % [label, on2_ms])
	else:
		_pass("%s second L-on %.1f ms (show cached)" % [label, on2_ms])
	_mr.call("_toggle_supply_overlay")
	await process_frame
	_info(
		"%s z=%.3f on_ms=%.1f off_ms=%.1f on2_ms=%.1f visible_on=%d line2d_on=%d rebuilds %d→%d→%d→%d"
		% [label, zoom, on_ms, off_ms, on2_ms, on_n, line_on, rebuilds_before, rebuilds_on, rebuilds_off, rebuilds_on2]
	)
	if _mr.has_method("get_supply_outline_rebuild_count"):
		if rebuilds_on2 > rebuilds_on:
			_fail("%s second L-on rebuilt outlines %d→%d (must show/hide)" % [label, rebuilds_on, rebuilds_on2])
		else:
			_pass("%s second L-on rebuilds unchanged (%d)" % [label, rebuilds_on2])
