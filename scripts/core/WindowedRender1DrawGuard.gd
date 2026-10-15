extends SceneTree

## WINDOWED RENDER-1 draw gate. xvfb is NOT live Play.
## Engine draw counters must rise on L-on (392 on the tip). A 0 count is FAIL.
## No grep fallback. skip_engine_draw (counter_lie) must produce delta 0.
##
##   tools/eoa_render1_draw_guard.sh

const LAND_N := 3196
const POLY_SIDES := 48
const HOME_Z := 0.318
const LAYER_PATH := "res://scripts/map/SupplyOutlineBatchLayer.gd"
const ROLES: Array[String] = [
	"active", "preview", "route", "infra_sabotage", "infra_repair",
	"infra_repair_engineers", "engineers_stationed", "engineers_needed",
	"engineers_recommended", "engineers_insufficient", "infra_duel_even",
	"depot_sabotage", "supply_pressure", "trade_transit", "hub",
]

var _failures: int = 0


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


func _run() -> void:
	var ds := DisplayServer.get_name()
	_info("DisplayServer=%s" % ds)
	if ds == "headless":
		_fail("headless_display: engine counters stay 0; run via tools/eoa_render1_draw_guard.sh")
		return
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)

	var scr: Script = load(LAYER_PATH) as Script
	if scr == null:
		_fail("SupplyOutlineBatchLayer.gd missing")
		return
	var layer: Node2D = scr.new() as Node2D
	if layer == null:
		_fail("could not instance SupplyOutlineBatchLayer")
		return
	root.add_child(layer)
	layer.visible = true
	var items := _make_items(LAND_N)
	layer.call("set_view", HOME_Z, Rect2(-2000, -2000, 8000, 4000))
	layer.call("set_items", items)
	await _flush(4)
	var mesh_calls := 0
	if layer.has_method("get_last_draw_stats"):
		layer.queue_redraw()
		await process_frame
		await process_frame
		var st: Dictionary = layer.call("get_last_draw_stats") as Dictionary
		mesh_calls = int(st.get("mesh_calls", 0))
	if mesh_calls < 300:
		_fail("mesh_calls=%d want >=300 (Home LOD batch)" % mesh_calls)
		layer.queue_free()
		return
	_info("mesh_calls=%d items=%d" % [mesh_calls, items.size()])

	layer.set("skip_engine_draw", true)
	var probe_delta := await _measure_engine_delta(layer)
	layer.set("skip_engine_draw", false)
	_info("counter_lie probe skip_engine_draw delta=%d (must be 0 / < mesh_calls)" % probe_delta)
	if probe_delta >= mesh_calls and probe_delta > 0:
		_fail("counter_lie probe survived: skip_engine_draw still reports delta=%d" % probe_delta)
	else:
		_pass("counter_lie probe: skip_engine_draw delta=%d would FAIL (0 count is FAIL)" % probe_delta)

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
