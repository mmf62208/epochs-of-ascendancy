extends SceneTree

## PERF-5 FIX #3: L-on batch rings must be a handful of canvas draw commands,
## not one polished ring (2 polylines) per province.
## Counts via SupplyOutlineBatchLayer.last_draw_command_count() — a counter
## incremented next to each draw_multiline / draw_* — not by grepping source.
##
## FAILS on 2c68a67c (no counter, or per-province draw_polished_ring ≈ 2×N).
## PASSES when ≥3000 L-on items issue ≤64 batch-layer commands, or a ≥20×
## cut versus ea251004's 2 commands/item.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessPerf5SupplyOutlineBatchDrawTest.gd

const LAND_N := 3200
const POLY_SIDES := 16
const HOME_Z := 0.318
const FLUSH_FRAMES := 3
const MAX_DRAW_COMMANDS := 64
const MIN_REDUCTION := 20.0
## ea251004 / 2c68a67c: draw_polished_ring = glow polyline + stroke polyline.
const EA251004_COMMANDS_PER_ITEM := 2
## Direct 3200-item style-buffer rebuild. OverlayFresh B4 still owns the
## <1 ms reconcile bar on the small grid / #88 drain.
const MAX_DIRECT_PATCH_MS := 50.0

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
	print("HeadlessPerf5SupplyOutlineBatchDrawTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf5SupplyOutlineBatchDrawTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf5SupplyOutlineBatchDrawTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf5SupplyOutlineBatchDrawTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessPerf5SupplyOutlineBatchDrawTest: ", msg)


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


func _draw_commands(batch: Node) -> int:
	if batch == null:
		return -1
	if not batch.has_method("last_draw_command_count"):
		return -1
	return int(batch.call("last_draw_command_count"))


func _assert_draw_budget(label: String, batch: Node, item_n: int) -> void:
	if batch == null:
		_fail("%s batch missing" % label)
		return
	if not batch.has_method("last_draw_command_count"):
		_fail("%s no last_draw_command_count (2c68a67c per-province _draw has no counter)" % label)
		return
	var cmds: int = int(batch.call("last_draw_command_count"))
	var baseline: int = item_n * EA251004_COMMANDS_PER_ITEM
	var reduction: float = 0.0
	if cmds > 0:
		reduction = float(baseline) / float(cmds)
	_info("%s items=%d cmds=%d ea251004_baseline=%d reduction=%.1fx" % [
		label, item_n, cmds, baseline, reduction,
	])
	if cmds <= 0:
		_fail("%s draw commands=%d (nothing issued; counter or _draw is empty)" % [label, cmds])
		return
	var under_cap: bool = cmds <= MAX_DRAW_COMMANDS
	var reduced: bool = reduction >= MIN_REDUCTION
	if not under_cap and not reduced:
		_fail("%s cmds=%d want <=%d or >=%.0fx vs ea251004 (%d)" % [
			label, cmds, MAX_DRAW_COMMANDS, MIN_REDUCTION, baseline,
		])
	elif under_cap:
		_pass("%s cmds=%d <= %d (%.1fx vs ea251004 %d)" % [
			label, cmds, MAX_DRAW_COMMANDS, reduction, baseline,
		])
	else:
		_pass("%s cmds=%d (%.1fx vs ea251004 %d; cap is %d)" % [
			label, cmds, reduction, baseline, MAX_DRAW_COMMANDS,
		])


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
	await _flush()
	if _batch.has_method("item_count"):
		var n: int = int(_batch.call("item_count"))
		if n < 3000:
			_fail("direct items=%d want >=3000" % n)
		else:
			_pass("direct items=%d" % n)
		_assert_draw_budget("direct mixed roles", _batch, n)
	else:
		_fail("direct item_count missing")
		return
	if _batch.has_method("style_group_count"):
		var styles: int = int(_batch.call("style_group_count"))
		if styles < 2:
			_fail("direct style groups=%d want hub+route (and engineers)" % styles)
		else:
			_pass("direct style groups=%d (hub/route/engineers batched)" % styles)
	var hub_seen: bool = false
	var route_seen: bool = false
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
	if hub_seen and route_seen:
		_pass("direct hub and route rings still present")
	else:
		_fail("direct missing hub=%s route=%s" % [str(hub_seen), str(route_seen)])

	# Incremental patch: only the changed pids' geometry.
	if not _batch.has_method("patch_items"):
		_fail("direct patch_items missing")
		return
	var patch_pids: Array[int] = [710200, 710201, 710202]
	var upserts: Array = []
	for pid in patch_pids:
		var idx: int = pid - 710000
		var origin2 := Vector2(float(idx % 80) * 40.0, float(idx / 80) * 40.0)
		upserts.append(_make_item(pid, origin2, "route"))
	var t0: int = Time.get_ticks_usec()
	_batch.call("patch_items", upserts, [])
	var patch_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	await _flush()
	_assert_draw_budget("direct after patch", _batch, int(_batch.call("item_count")))
	if patch_ms >= MAX_DIRECT_PATCH_MS:
		_fail("direct patch_items %.3f ms >= %.1f" % [patch_ms, MAX_DIRECT_PATCH_MS])
	else:
		_pass("direct patch_items %.3f ms (3 pids; OverlayFresh B4 owns <1 ms)" % patch_ms)
	if _batch.has_method("last_geometry_touched_pids"):
		var touched: Array = _batch.call("last_geometry_touched_pids")
		var touched_set: Dictionary = {}
		for pid_var in touched:
			touched_set[int(pid_var)] = true
		var extra: int = 0
		for pid_var2 in touched_set.keys():
			if int(pid_var2) not in patch_pids:
				extra += 1
		var missing: int = 0
		for pid2 in patch_pids:
			if not touched_set.has(pid2):
				missing += 1
		if extra > 0 or missing > 0:
			_fail("direct patch touched extra=%d missing=%d (want only %s)" % [
				extra, missing, str(patch_pids),
			])
		else:
			_pass("direct patch_items touched only %d pids" % patch_pids.size())
	if _batch.has_method("last_style_rebuilds"):
		var rebuilt: int = int(_batch.call("last_style_rebuilds"))
		if rebuilt > 4:
			_fail("direct patch rebuilt %d styles (want only dirty hub/route)" % rebuilt)
		else:
			_pass("direct patch rebuilt %d dirty styles" % rebuilt)

	# Pulse is modulate-only: no geometry rebuild, same draw-command count.
	var cmds_before: int = _draw_commands(_batch)
	var rebuilds_before: int = 0
	if _batch.has_method("last_style_rebuilds"):
		rebuilds_before = int(_batch.call("last_style_rebuilds"))
	if _batch.has_method("set_pulse_phase"):
		_batch.call("set_pulse_phase", 1.25)
	await _flush()
	var cmds_after: int = _draw_commands(_batch)
	if cmds_after != cmds_before:
		_fail("pulse changed draw commands %d→%d (must stay modulate-only)" % [cmds_before, cmds_after])
	else:
		_pass("pulse modulate-only (cmds=%d)" % cmds_after)
	if _batch.has_method("last_style_rebuilds"):
		var pulse_rebuilds: int = int(_batch.call("last_style_rebuilds"))
		if pulse_rebuilds != rebuilds_before:
			_fail("pulse rebuilt styles %d→%d (must stay modulate-only)" % [rebuilds_before, pulse_rebuilds])
		else:
			_pass("pulse rebuilt 0 extra styles (still %d from last patch)" % pulse_rebuilds)


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
	var batch_view: Node = _mr.get("_supply_outline_batch") as Node
	# _ready recenters MapCamera on Europe; pin a rect over the synthetic
	# grid so FIX #3 still counts the batched L-on commands.
	if batch_view != null:
		if batch_view.has_method("set_view_zoom"):
			batch_view.call("set_view_zoom", 2.0)
		if batch_view.has_method("set_view_rect"):
			batch_view.call("set_view_rect", Rect2(-80.0, -80.0, 3360.0, 1760.0))
	await _flush()
	var visible_n: int = 0
	if _mr.has_method("get_supply_overlay_outline_visible_count"):
		visible_n = int(_mr.call("get_supply_overlay_outline_visible_count"))
	if visible_n < 3000:
		_fail("L-on visible items=%d want >=3000" % visible_n)
	else:
		_pass("L-on visible items=%d" % visible_n)
	var batch: Node = _mr.get("_supply_outline_batch") as Node
	if batch == null:
		_fail("L-on batch missing")
		return
	var item_n: int = 0
	if batch.has_method("item_count"):
		item_n = int(batch.call("item_count"))
	_assert_draw_budget("L-on MapRenderer", batch, item_n)
	if _mr.has_method("get_supply_outline_draw_commands"):
		var via_mr: int = int(_mr.call("get_supply_outline_draw_commands"))
		var via_batch: int = _draw_commands(batch)
		if via_mr != via_batch:
			_fail("L-on MapRenderer getter %d != batch %d" % [via_mr, via_batch])
		else:
			_pass("L-on MapRenderer getter cmds=%d" % via_mr)
	_info("L-on z=%.3f visible=%d batch_items=%d cmds=%d" % [
		HOME_Z, visible_n, item_n, _draw_commands(batch),
	])
