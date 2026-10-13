extends SceneTree

## PERF-5 FIX #4: L-on batch rings must not emit antialiased lines, and the
## visible-rect vertex/segment totals must stay bounded. Counts come from
## SupplyOutlineBatchLayer counters incremented next to each draw_multiline —
## not by grepping source, and not by draw-command count (FIX #3 owns that).
##
## FAILS on 8accbb69: no AA/segment counters, or AA multiline over the full
## 3200-ring set (glow+stroke, no camera cull).
## PASSES when a Home-sized rect draws 0 AA commands and far fewer segments
## than the unculled 2×N ring set.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessPerf5SupplyOutlineFrameCostTest.gd

const LAND_N := 3200
const POLY_SIDES := 16
const HOME_Z := 0.776
const FLUSH_FRAMES := 3
## Unculled 8accbb69: 3200 rings × 16 segs × glow+stroke = 102400.
const UNCULL_SEGMENTS := LAND_N * POLY_SIDES * 2
const MAX_VISIBLE_SEGMENTS := 28000
const MAX_VISIBLE_VERTICES := 56000
const MAX_DRAWN_ITEMS := 2200
const VIEW_RECT := Rect2(-40.0, -40.0, 520.0, 400.0)
const FAR_RECT := Rect2(100000.0, 100000.0, 200.0, 200.0)

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null
var _batch: Node2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf5SupplyOutlineFrameCostTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf5SupplyOutlineFrameCostTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf5SupplyOutlineFrameCostTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf5SupplyOutlineFrameCostTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessPerf5SupplyOutlineFrameCostTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _make_ring(radius: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sides)
	var i := 0
	while i < sides:
		var a: float = TAU * float(i) / float(sides)
		pts[i] = Vector2(cos(a), sin(a)) * radius
		i += 1
	return pts


func _style_for(role: String) -> Dictionary:
	return ProvinceMapVisuals.get_supply_outline_style(role)


func _make_item(pid: int, origin: Vector2, role: String) -> Dictionary:
	var style: Dictionary = _style_for(role)
	var local: PackedVector2Array = _make_ring(18.0, POLY_SIDES)
	var pts := PackedVector2Array()
	pts.resize(local.size())
	var i := 0
	while i < local.size():
		pts[i] = local[i] + origin
		i += 1
	return {
		"pid": pid,
		"points": pts,
		"color": style["color"],
		"glow": style["glow"],
		"width": style["width"],
		"glow_extra": style["glow_extra"],
		"z_index": style["z_index"],
		"role": role,
	}


func _counter(batch: Node, method: String) -> int:
	if batch == null:
		return -1
	if not batch.has_method(method):
		return -1
	return int(batch.call(method))


func _assert_frame_cost(label: String, batch: Node, item_n: int, expect_draw: bool) -> void:
	if batch == null:
		_fail("%s batch missing" % label)
		return
	if not batch.has_method("last_aa_line_command_count"):
		_fail("%s no last_aa_line_command_count (8accbb69 AA multiline has no counter)" % label)
		return
	if not batch.has_method("last_drawn_segment_count"):
		_fail("%s no last_drawn_segment_count (8accbb69 draws the full ring set)" % label)
		return
	if not batch.has_method("last_drawn_vertex_count"):
		_fail("%s no last_drawn_vertex_count" % label)
		return
	if not batch.has_method("last_drawn_item_count"):
		_fail("%s no last_drawn_item_count" % label)
		return
	var aa: int = _counter(batch, "last_aa_line_command_count")
	var segs: int = _counter(batch, "last_drawn_segment_count")
	var verts: int = _counter(batch, "last_drawn_vertex_count")
	var drawn: int = _counter(batch, "last_drawn_item_count")
	_info("%s items=%d aa=%d segs=%d verts=%d drawn_items=%d unculled=%d" % [
		label, item_n, aa, segs, verts, drawn, UNCULL_SEGMENTS,
	])
	if aa != 0:
		_fail("%s aa_line_commands=%d want 0 (antialiased multiline is the Home hitch)" % [label, aa])
	else:
		_pass("%s aa_line_commands=0" % label)
	if expect_draw:
		if segs <= 0:
			_fail("%s segments=%d (visible rect issued nothing)" % [label, segs])
		elif segs > MAX_VISIBLE_SEGMENTS:
			_fail("%s segments=%d > %d (8accbb69 unculled is %d)" % [
				label, segs, MAX_VISIBLE_SEGMENTS, UNCULL_SEGMENTS,
			])
		else:
			_pass("%s segments=%d <= %d (unculled %d)" % [label, segs, MAX_VISIBLE_SEGMENTS, UNCULL_SEGMENTS])
		if verts > MAX_VISIBLE_VERTICES:
			_fail("%s vertices=%d > %d" % [label, verts, MAX_VISIBLE_VERTICES])
		else:
			_pass("%s vertices=%d <= %d" % [label, verts, MAX_VISIBLE_VERTICES])
		if drawn <= 0:
			_fail("%s drawn_items=%d (visible rect culled the rings in view)" % [label, drawn])
		elif drawn > MAX_DRAWN_ITEMS:
			_fail("%s drawn_items=%d > %d (want camera-rect cull, not all %d)" % [
				label, drawn, MAX_DRAWN_ITEMS, item_n,
			])
		elif item_n > MAX_DRAWN_ITEMS and drawn >= item_n:
			_fail("%s drawn_items=%d >= item_n=%d (no spatial cull)" % [label, drawn, item_n])
		else:
			_pass("%s drawn_items=%d of %d (culled)" % [label, drawn, item_n])
	else:
		if segs != 0 or drawn != 0:
			_fail("%s far rect still drew segs=%d items=%d (no camera-rect cull)" % [label, segs, drawn])
		else:
			_pass("%s far rect segs=0 drawn_items=0" % label)
		if aa != 0:
			_fail("%s far rect aa=%d" % [label, aa])


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)
	await _direct_batch_layer()
	await _l_on_map_renderer()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()


func _direct_batch_layer() -> void:
	var scr: Script = load("res://scripts/map/SupplyOutlineBatchLayer.gd") as Script
	if scr == null:
		_fail("SupplyOutlineBatchLayer.gd missing")
		return
	_batch = scr.new() as Node2D
	if _batch == null:
		_fail("could not construct SupplyOutlineBatchLayer")
		return
	root.add_child(_batch)
	_batch.visible = true
	var items: Array[Dictionary] = []
	var i := 0
	while i < LAND_N:
		var role: String = "hub"
		if i < 80:
			role = "route"
		elif i < 160:
			role = "engineers_recommended"
		var origin := Vector2(float(i % 80) * 40.0, float(i / 80) * 40.0)
		items.append(_make_item(710000 + i, origin, role))
		i += 1
	_batch.call("set_items", items)
	if not _batch.has_method("set_view_rect") or not _batch.has_method("set_view_zoom"):
		_fail("direct set_view_rect/set_view_zoom missing (8accbb69 draws every ring)")
		return
	_batch.call("set_view_zoom", HOME_Z)
	_batch.call("set_view_rect", VIEW_RECT)
	await _flush()
	var n: int = 0
	if _batch.has_method("item_count"):
		n = int(_batch.call("item_count"))
	if n < 3000:
		_fail("direct items=%d want >=3000" % n)
	else:
		_pass("direct items=%d" % n)
	_assert_frame_cost("direct Home rect", _batch, n, true)

	var hub_seen: bool = false
	var route_seen: bool = false
	var eng_seen: bool = false
	var raw_items: Variant = _batch.get("_items")
	if typeof(raw_items) == TYPE_ARRAY:
		for item_var in raw_items:
			if typeof(item_var) != TYPE_DICTIONARY:
				continue
			var role2: String = str((item_var as Dictionary).get("role", ""))
			if role2 == "hub":
				hub_seen = true
			elif role2 == "route":
				route_seen = true
			elif role2 == "engineers_recommended":
				eng_seen = true
	if hub_seen and route_seen and eng_seen:
		_pass("direct hub/route/engineers rings still present")
	else:
		_fail("direct missing hub=%s route=%s engineers=%s" % [
			str(hub_seen), str(route_seen), str(eng_seen),
		])

	_batch.call("set_view_rect", FAR_RECT)
	await _flush()
	_assert_frame_cost("direct far rect", _batch, n, false)

	_batch.call("set_view_rect", VIEW_RECT)
	await _flush()
	var segs_before: int = _counter(_batch, "last_drawn_segment_count")
	var rebuilds_before: int = _counter(_batch, "last_style_rebuilds")
	if _batch.has_method("set_pulse_phase"):
		_batch.call("set_pulse_phase", 1.25)
	await _flush()
	var segs_after: int = _counter(_batch, "last_drawn_segment_count")
	if segs_after != segs_before:
		_fail("pulse changed segments %d→%d (must stay modulate-only)" % [segs_before, segs_after])
	else:
		_pass("pulse modulate-only (segs=%d)" % segs_after)
	if _batch.has_method("last_style_rebuilds"):
		var pulse_rebuilds: int = int(_batch.call("last_style_rebuilds"))
		if pulse_rebuilds != rebuilds_before:
			_fail("pulse rebuilt styles %d→%d" % [rebuilds_before, pulse_rebuilds])
		else:
			_pass("pulse rebuilt 0 extra styles")


func _l_on_map_renderer() -> void:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return
	_mr = mr_script.new()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(180, 140)
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
		return
	var depot_scr: Script = load("res://scripts/supply/ProvinceDepotState.gd") as Script
	var i := 0
	while i < 3196:
		var pid: int = 710000 + i
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
	var layer_scr: Script = load("res://scripts/supply/SupplyMapLayer.gd") as Script
	if layer_scr != null:
		var layer: Node2D = layer_scr.new() as Node2D
		if layer != null:
			layer.name = "SupplyMapLayer"
			layer.visible = false
			_container.add_child(layer)
			_mr.supply_map_layer = layer
	if "overlay_visible" in sm:
		sm.overlay_visible = false
	_mr.supply_mode = false
	await _flush()
	_mr.call("_toggle_supply_overlay")
	await _flush()
	if _mr.has_method("_pulse_supply_outlines"):
		_mr.call("_pulse_supply_outlines")
	await _flush()
	var batch: Node = _mr.get("_supply_outline_batch") as Node
	if batch == null:
		_fail("L-on batch missing")
		return
	var item_n: int = 0
	if batch.has_method("item_count"):
		item_n = int(batch.call("item_count"))
	if item_n < 3000:
		_fail("L-on items=%d want >=3000" % item_n)
	else:
		_pass("L-on items=%d" % item_n)
	_assert_frame_cost("L-on MapRenderer Home", batch, item_n, true)
	if _mr.has_method("get_supply_outline_aa_line_commands"):
		var via_mr: int = int(_mr.call("get_supply_outline_aa_line_commands"))
		var via_batch: int = _counter(batch, "last_aa_line_command_count")
		if via_mr != via_batch:
			_fail("L-on MapRenderer AA getter %d != batch %d" % [via_mr, via_batch])
		else:
			_pass("L-on MapRenderer AA getter=%d" % via_mr)
	if _mr.has_method("get_supply_outline_drawn_segments"):
		var segs_mr: int = int(_mr.call("get_supply_outline_drawn_segments"))
		_pass("L-on MapRenderer segments getter=%d" % segs_mr)
