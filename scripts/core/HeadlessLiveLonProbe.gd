extends SceneTree

## Live L-on / L-off overlay hitch probe (HWY-3 supply-toggle cache).
## Measures the overlay work L hits (set_show_roads → rebuild_road_layer)
## on the live ScenarioLoader board. ×2 runs.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessLiveLonProbe.gd

const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_LOADER := "res://scripts/core/ScenarioLoader.gd"
const OFF_FRAME2_LIMIT_MS := 350.0
const ON_WARM_LIMIT_MS := 300.0

var _failures: int = 0
var _ol: Node2D = null
var _loader: Node = null
var _mr: Node = null


class MapRendererStub extends Node:
	var supply_mode: bool = false
	var current_map_mode: String = "political"


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessLiveLonProbe: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessLiveLonProbe: ", msg)


func _run_and_quit() -> void:
	await _run()
	var ok: bool = _failures == 0
	print("HeadlessLiveLonProbe: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessLiveLonProbe: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	if not await _boot():
		return
	var load_ms: float = 0.0
	var t_load: int = Time.get_ticks_usec()
	_ol.call("_rebuild_road_layer_inner")
	load_ms = float(Time.get_ticks_usec() - t_load) / 1000.0
	print("LIVE_LON_PROBE load_ms=%.2f" % load_ms)
	_ol.call("set_supply_corridor_path", [710417, 710416])
	_toggle(true)
	for run_i in range(2):
		var off_ms: float = _toggle(false)
		var on_ms: float = _toggle(true)
		print(
			"LIVE_LON_PROBE run=%d off_frame2=%.2f on_warm=%.2f load_ms=%.2f"
			% [run_i + 1, off_ms, on_ms, load_ms]
		)
		if off_ms > OFF_FRAME2_LIMIT_MS:
			_fail("run %d off frame2 %.2f ms > %.0f" % [run_i + 1, off_ms, OFF_FRAME2_LIMIT_MS])
		else:
			_pass("run %d off frame2 %.2f ms" % [run_i + 1, off_ms])
		if on_ms > ON_WARM_LIMIT_MS:
			_fail("run %d on_warm %.2f ms > %.0f" % [run_i + 1, on_ms, ON_WARM_LIMIT_MS])
		else:
			_pass("run %d on_warm %.2f ms" % [run_i + 1, on_ms])
	if _ol != null:
		_ol.queue_free()
	if _mr != null:
		_mr.queue_free()
	if _loader != null:
		_loader.queue_free()


func _boot() -> bool:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail("MapManager autoload missing")
		return false
	var LoaderScr: GDScript = load(SRC_LOADER) as GDScript
	if LoaderScr == null:
		_fail("could not load ScenarioLoader.gd")
		return false
	_loader = LoaderScr.new()
	_loader.name = "ScenarioLoader"
	root.add_child(_loader)
	if _loader.has_method("load_base_provinces"):
		_loader.call("load_base_provinces")
	var ok: bool = bool(await _loader.load_scenario("world_accurate"))
	if not ok:
		_fail("load_scenario(world_accurate) failed")
		return false
	var map_data: Variant = _loader.call("get_map_data")
	if mm.has_method("initialize_from_map_data"):
		mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	_mr = MapRendererStub.new()
	_mr.name = "MapRendererStub"
	root.add_child(_mr)
	var ol_script: GDScript = load(SRC_OL) as GDScript
	_ol = ol_script.new() as Node2D
	root.add_child(_ol)
	_ol.set("map_manager", mm)
	if _ol.has_method("_ensure_sub_layers"):
		_ol.call("_ensure_sub_layers")
	return true


func _toggle(on: bool) -> float:
	_mr.set("supply_mode", on)
	_mr.set("current_map_mode", "supply" if on else "political")
	var t0: int = Time.get_ticks_usec()
	_ol.call("set_show_roads", false)
	return float(Time.get_ticks_usec() - t0) / 1000.0
