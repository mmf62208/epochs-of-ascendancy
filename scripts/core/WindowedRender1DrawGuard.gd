extends SceneTree

## WINDOWED RENDER-1 draw + cold-L gate. xvfb is NOT live Play.
## Engine draw counters must rise on L-on (392 on the tip). A 0 count is FAIL.
## counter_lie is a source edit in this test (draw_mesh removed, counters kept).
## No product flag. No grep fallback.
##
##   tools/eoa_render1_draw_guard.sh

const LAND_N := 3196
const POLY_SIDES := 48
const HOME_Z := 0.318
const MAX_COLD_MS := 250.0
const PREBUILD_WAIT_FRAMES := 240
const LAYER_PATH := "res://scripts/map/SupplyOutlineBatchLayer.gd"
const DRAW_MESH_CALL := "draw_mesh(mesh, null, Transform2D(), mesh_modulate)"
const ROLES: Array[String] = [
	"active", "preview", "route", "infra_sabotage", "infra_repair",
	"infra_repair_engineers", "engineers_stationed", "engineers_needed",
	"engineers_recommended", "engineers_insufficient", "infra_duel_even",
	"depot_sabotage", "supply_pressure", "trade_transit", "hub",
]

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("WindowedRender1DrawGuard: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("WindowedRender1DrawGuard: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] WindowedRender1DrawGuard: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] WindowedRender1DrawGuard: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] WindowedRender1DrawGuard: ", msg)


func _loadavg_line() -> String:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	if f == null:
		return "?"
	var line := f.get_line().strip_edges()
	f.close()
	return line


func _run() -> void:
	var ds := DisplayServer.get_name()
	_info("DisplayServer=%s" % ds)
	if ds == "headless":
		_fail("headless_display: engine counters stay 0; run via tools/eoa_render1_draw_guard.sh")
		return
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)

	var items := _make_items(LAND_N)
	await _check_counter_lie_source_edit(items)
	await _check_product_draws(items)
	await _check_present_drain(items)
	await _check_never_drain_mutant(items)
	await _measure_cold_lon()


func _load_layer_script(src: String) -> Script:
	if src.is_empty():
		return load(LAYER_PATH) as Script
	var gs := GDScript.new()
	gs.source_code = src
	if gs.reload() != OK:
		return null
	return gs


func _counter_lie_mutant_source() -> String:
	var src := FileAccess.get_file_as_string(LAYER_PATH)
	if src.find(DRAW_MESH_CALL) < 0:
		return ""
	return src.replace(DRAW_MESH_CALL, "pass # counter_lie mutant: draw_mesh removed")


func _spawn_layer(scr: Script, items: Array[Dictionary]) -> Node2D:
	var layer: Node2D = scr.new() as Node2D
	if layer == null:
		return null
	root.add_child(layer)
	layer.visible = true
	layer.call("set_view", HOME_Z, Rect2(-2000, -2000, 8000, 4000))
	layer.call("set_items", items)
	return layer


func _check_counter_lie_source_edit(items: Array[Dictionary]) -> void:
	var mutant_src := _counter_lie_mutant_source()
	if mutant_src.is_empty():
		_fail("counter_lie source edit: product has no live draw_mesh call to strip")
		return
	var scr := _load_layer_script(mutant_src)
	if scr == null:
		_fail("counter_lie source edit: mutant script failed to reload")
		return
	var layer := _spawn_layer(scr, items)
	if layer == null:
		_fail("counter_lie source edit: could not instance mutant layer")
		return
	await _flush(4)
	layer.queue_redraw()
	await process_frame
	await process_frame
	var mesh_calls := 0
	if layer.has_method("get_last_draw_stats"):
		var st: Dictionary = layer.call("get_last_draw_stats") as Dictionary
		mesh_calls = int(st.get("mesh_calls", 0))
	var probe_delta := await _measure_engine_delta(layer)
	_info("counter_lie source-edit probe mesh_calls=%d delta=%d (must be 0)" % [mesh_calls, probe_delta])
	if probe_delta > 0:
		_fail("counter_lie source-edit survived: draw_mesh stripped but engine delta=%d" % probe_delta)
	else:
		_pass("counter_lie source-edit: draw_mesh removed, counters=%d, engine delta=0 (FAIL path)" % mesh_calls)
	layer.queue_free()


func _check_product_draws(items: Array[Dictionary]) -> void:
	var scr: Script = load(LAYER_PATH) as Script
	if scr == null:
		_fail("SupplyOutlineBatchLayer.gd missing")
		return
	var layer := _spawn_layer(scr, items)
	if layer == null:
		_fail("could not instance product SupplyOutlineBatchLayer")
		return
	await _flush(4)
	layer.queue_redraw()
	await process_frame
	await process_frame
	if layer.has_method("in_view_present_complete"):
		var drain_i := 0
		while drain_i < 3 and not bool(layer.call("in_view_present_complete")):
			layer.queue_redraw()
			await process_frame
			drain_i += 1
	var mesh_calls := 0
	if layer.has_method("get_last_draw_stats"):
		var st: Dictionary = layer.call("get_last_draw_stats") as Dictionary
		mesh_calls = int(st.get("mesh_calls", 0))
	if mesh_calls < 300:
		_fail("mesh_calls=%d want >=300 (Home LOD batch)" % mesh_calls)
		layer.queue_free()
		return
	_info("mesh_calls=%d items=%d" % [mesh_calls, items.size()])
	var live_delta := await _measure_engine_delta(layer)
	_info("independent_draw_info engine delta=%d mesh_calls=%d" % [live_delta, mesh_calls])
	if live_delta <= 0:
		_fail("independent_draw_info: engine delta=0 (mutant_counter_lie; no grep fallback)")
	elif live_delta < mesh_calls:
		_fail("independent_draw_info: engine delta=%d < mesh_calls=%d" % [live_delta, mesh_calls])
	else:
		_pass("independent_draw_info killed mutant_counter_lie: engine delta=%d >= mesh_calls=%d" % [
			live_delta, mesh_calls,
		])
	layer.queue_free()


func _chunk_key_set(keys_var: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(keys_var) == TYPE_PACKED_STRING_ARRAY:
		for key in keys_var as PackedStringArray:
			out[str(key)] = true
	elif typeof(keys_var) == TYPE_ARRAY:
		for key_var in keys_var as Array:
			out[str(key_var)] = true
	return out


func _sets_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
	return true


func _check_present_drain(items: Array[Dictionary]) -> void:
	var scr: Script = load(LAYER_PATH) as Script
	if scr == null:
		_fail("present drain: SupplyOutlineBatchLayer.gd missing")
		return
	var layer := _spawn_layer(scr, items)
	if layer == null:
		_fail("present drain: could not instance layer")
		return
	layer.visible = false
	if layer.has_method("mark_hidden_for_split_present"):
		layer.call("mark_hidden_for_split_present")
	layer.visible = true
	layer.queue_redraw()
	var frames := 0
	var complete := false
	var drawn: Dictionary = {}
	var view: Dictionary = {}
	while frames < 3:
		if layer.has_method("_draw"):
			layer.call("_draw")
		await process_frame
		frames += 1
		if layer.has_method("get_last_drawn_chunk_keys"):
			drawn = _chunk_key_set(layer.call("get_last_drawn_chunk_keys"))
		if layer.has_method("get_in_view_chunk_keys"):
			view = _chunk_key_set(layer.call("get_in_view_chunk_keys"))
		if layer.has_method("in_view_present_complete"):
			complete = bool(layer.call("in_view_present_complete")) and _sets_equal(drawn, view)
		if complete:
			break
	if not complete or view.is_empty():
		_fail(
			"present drain: drawn mesh set != built chunk set in view after %d frames drawn=%d view=%d"
			% [frames, drawn.size(), view.size()]
		)
	else:
		_pass("present drain: drawn == in-view built set after %d frames n=%d" % [frames, view.size()])
	layer.queue_free()


func _check_never_drain_mutant(items: Array[Dictionary]) -> void:
	var src := FileAccess.get_file_as_string(LAYER_PATH)
	var seam := 'OS.get_environment("EOA_RENDER1_PRESENT_MUTANT").strip_edges() == "never_drain"'
	if src.find(seam) < 0:
		_fail("never_drain mutant: product has no PRESENT_MUTANT drain seam")
		return
	var mutant := src.replace(seam, "true")
	var gs := _load_layer_script(mutant)
	if gs == null:
		_fail("never_drain mutant: failed to reload")
		return
	var layer := _spawn_layer(gs, items)
	if layer == null:
		_fail("never_drain mutant: could not instance")
		return
	layer.visible = false
	if layer.has_method("mark_hidden_for_split_present"):
		layer.call("mark_hidden_for_split_present")
	layer.visible = true
	layer.queue_redraw()
	var frames := 0
	while frames < 3:
		await process_frame
		frames += 1
	var drawn: Dictionary = {}
	var view: Dictionary = {}
	if layer.has_method("get_last_drawn_chunk_keys"):
		drawn = _chunk_key_set(layer.call("get_last_drawn_chunk_keys"))
	if layer.has_method("get_in_view_chunk_keys"):
		view = _chunk_key_set(layer.call("get_in_view_chunk_keys"))
	var complete := false
	if layer.has_method("in_view_present_complete"):
		complete = bool(layer.call("in_view_present_complete"))
	if complete or _sets_equal(drawn, view):
		_fail(
			"never_drain mutant survived: complete=%s drawn=%d view=%d after 3 frames"
			% [str(complete), drawn.size(), view.size()]
		)
	else:
		_pass("never_drain mutant killed: drawn=%d < view=%d after 3 frames" % [drawn.size(), view.size()])
	layer.queue_free()


func _measure_cold_lon() -> void:
	if not _setup_renderer():
		return
	await _flush(3)
	var sm: Node = root.get_node_or_null("SupplyManager")
	if sm != null and "overlay_visible" in sm:
		sm.overlay_visible = false
	_mr.supply_mode = false
	var pre: Dictionary = await _wait_idle_prebuild()
	_info(
		"idle_prebuild done=%s items=%d max_step=%.3f"
		% [str(pre.get("done", false)), int(pre.get("item_count", -1)), float(pre.get("max_step_ms", -1.0))]
	)
	var t_toggle := Time.get_ticks_usec()
	_mr.call("_toggle_supply_overlay")
	var toggle_ms := float(Time.get_ticks_usec() - t_toggle) / 1000.0
	var t_frame := Time.get_ticks_usec()
	var complete_i := 0
	var guard := 0
	while guard < 8:
		if _mr != null and "container" in _mr:
			var c: Node = _mr.get("container") as Node
			if c != null:
				var batch: Node = c.get_node_or_null("SupplyOutlineBatch")
				if batch != null and batch.has_method("_draw") and bool(batch.visible):
					batch.call("_draw")
		await process_frame
		guard += 1
		if _mr.has_method("supply_in_view_present_complete") and bool(_mr.call("supply_in_view_present_complete")):
			complete_i = guard
			break
	var first_complete_ms := float(Time.get_ticks_usec() - t_frame) / 1000.0
	var cold_ms := toggle_ms + first_complete_ms
	var vis := 0
	if _mr.has_method("get_supply_overlay_outline_visible_count"):
		vis = int(_mr.call("get_supply_overlay_outline_visible_count"))
	print(
		"cold_raw display=%s ms=%.3f complete_frame=%d loadavg=%s"
		% [DisplayServer.get_name(), cold_ms, complete_i, _loadavg_line()]
	)
	_info("fixture L-on toggle=%.3f complete_frame=%.3f i=%d frame_total=%.3f vis=%d" % [
		toggle_ms, first_complete_ms, complete_i, cold_ms, vis,
	])
	if complete_i <= 0 or complete_i > 3:
		_fail("windowed fixture L-on rings did not complete within 3 frames i=%d" % complete_i)
	if vis < 3000:
		_fail("windowed fixture L-on visible=%d want >=3000" % vis)
	if cold_ms >= MAX_COLD_MS:
		_fail("windowed fixture L-on %.1f ms (bar %.0f)" % [cold_ms, MAX_COLD_MS])
	else:
		_pass("windowed fixture L-on %.1f ms (bar=%.0f)" % [cold_ms, MAX_COLD_MS])
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null


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
	_cam.position = Vector2(1600, 800)
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
	var depot_scr: Script = load("res://scripts/supply/ProvinceDepotState.gd") as Script
	var i := 0
	while i < LAND_N:
		var pid := 710000 + i
		var host := Node2D.new()
		host.name = "Prov_%d" % pid
		var poly := Polygon2D.new()
		poly.polygon = _make_ring(Vector2(float(i % 80) * 40.0, float(i / 80) * 40.0), 24.0, POLY_SIDES)
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
		if depot_scr != null and sm != null and "depot_states" in sm:
			sm.depot_states[pid] = depot_scr.new(pid, 100.0)
		i += 1
	var layer_scr: Script = load("res://scripts/supply/SupplyMapLayer.gd") as Script
	if layer_scr != null:
		var sl: Node2D = layer_scr.new() as Node2D
		sl.name = "SupplyMapLayer"
		sl.visible = false
		_container.add_child(sl)
		_mr.supply_map_layer = sl
	if sm != null and "overlay_visible" in sm:
		sm.overlay_visible = false
	_mr.supply_mode = false
	return true


func _wait_idle_prebuild() -> Dictionary:
	var stats: Dictionary = {}
	var i := 0
	while i < PREBUILD_WAIT_FRAMES:
		if _mr.has_method("get_supply_ring_prebuild_stats"):
			stats = _mr.call("get_supply_ring_prebuild_stats") as Dictionary
			if bool(stats.get("done", false)) and int(stats.get("item_count", 0)) >= 3000:
				return stats
		await process_frame
		i += 1
	if _mr.has_method("get_supply_ring_prebuild_stats"):
		stats = _mr.call("get_supply_ring_prebuild_stats") as Dictionary
	return stats


func _measure_engine_delta(layer: Node2D) -> int:
	layer.visible = false
	await process_frame
	await process_frame
	var off := _snapshot()
	layer.visible = true
	layer.queue_redraw()
	await process_frame
	await process_frame
	var on_s := _snapshot()
	var d_draws := int(on_s.get("draws", 0)) - int(off.get("draws", 0))
	var d_prims := int(on_s.get("prims", 0)) - int(off.get("prims", 0))
	var d_vis := int(on_s.get("vis_d", 0)) - int(off.get("vis_d", 0))
	var d_can := int(on_s.get("can_d", 0)) - int(off.get("can_d", 0))
	_info("engine off=%s on=%s d_draws=%d d_prims=%d d_vis=%d d_can=%d" % [
		str(off), str(on_s), d_draws, d_prims, d_vis, d_can,
	])
	return maxi(maxi(d_draws, d_prims), maxi(d_vis, d_can))


func _snapshot() -> Dictionary:
	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var vis_d := 0
	var can_d := 0
	if root != null:
		var vp := root.get_viewport()
		if vp != null:
			vis_d = int(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
			can_d = int(vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
	return {"draws": draws, "prims": prims, "vis_d": vis_d, "can_d": can_d}


func _flush(n: int) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1


func _make_ring(origin: Vector2, radius: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sides)
	var i := 0
	while i < sides:
		var a := TAU * float(i) / float(sides)
		pts[i] = origin + Vector2(cos(a), sin(a)) * radius
		i += 1
	return pts


func _make_items(n: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var i := 0
	while i < n:
		var role := str(ROLES[i % ROLES.size()]) if i < ROLES.size() else "route"
		if i >= ROLES.size() and i % 97 == 0:
			role = str(ROLES[i % ROLES.size()])
		var style: Dictionary = ProvinceMapVisuals.get_supply_outline_style(role)
		items.append({
			"pid": 710000 + i,
			"points": _make_ring(Vector2(float(i % 80) * 40.0, float(i / 80) * 40.0), 24.0, POLY_SIDES),
			"color": style["color"],
			"glow": style["glow"],
			"width": style["width"],
			"glow_extra": style["glow_extra"],
			"z_index": style["z_index"],
			"role": role,
		})
		i += 1
	return items
