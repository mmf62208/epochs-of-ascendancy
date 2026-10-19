extends SceneTree

## HWY-3 FIX: supply toggle reuses the hub-route cache.
## (a) on/off/on does not re-run hub routing; highway keys stay identical.
## (b) a real infra / built-road change recomputes.
## (c) corridor styling still applies when supply is on.
## Source mutants (no EOA_* switches): ignore_infra → (b) FAIL;
## bypass_toggle → (a) FAIL; skip_styling → (c) FAIL.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3SupplyToggleCacheTest.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_LOADER := "res://scripts/core/ScenarioLoader.gd"
const OFF_FRAME2_LIMIT_MS := 350.0
const ON_WARM_LIMIT_MS := 300.0
## Cached L-toggle path (no ring walk / no chain rebuild). Main is ~15–35 ms.
const ON_WARM_CACHED_LIMIT_MS := 100.0

var _failures: int = 0
var _ol: Node2D = null
var _loader: Node = null
var _mr: Node = null
var _load_ms: float = 0.0


class MapRendererStub extends Node:
	var supply_mode: bool = false
	var current_map_mode: String = "political"


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessHwy3SupplyToggleCacheTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessHwy3SupplyToggleCacheTest: ", msg)


func _run_and_quit() -> void:
	await _run()
	var ok: bool = _failures == 0
	print("HeadlessHwy3SupplyToggleCacheTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessHwy3SupplyToggleCacheTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	_test_no_env_switches()
	if not await _boot_live_scenario():
		return
	_test_a_toggle_reuses_cache()
	_test_cached_path_skips_geom()
	_test_stub_report_lists_demoted()
	_test_live_lon_probe()
	_test_c_corridor_styling()
	_test_b_infra_change_recomputes()
	_test_mutant_ignore_infra()
	_test_mutant_bypass_toggle()
	_test_mutant_skip_styling()
	if _ol != null:
		_ol.queue_free()
	if _mr != null:
		_mr.queue_free()
	if _loader != null:
		_loader.queue_free()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt := src.find("\nfunc ", i + needle.length())
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _test_no_env_switches() -> void:
	var src: String = _read_text(SRC_OL)
	if "EOA_HWY3" in src or "hwy3_mutant_name" in src:
		_fail("overlay added an EOA_HWY3 / mutant env switch (forbidden)")
	else:
		_pass("no new EOA_HWY3 env switches in overlay")
	if "_hwy3_route_input_key" not in src or "HWY3_CACHE_KEY_INFRA" not in src:
		_fail("overlay missing HWY-3 supply-toggle cache key")
	if "var hwy3_cache_hit: bool = (" not in src:
		_fail("overlay missing hwy3_cache_hit needle")
	if "if supply_on and on_corridor:" not in src:
		_fail("overlay missing corridor styling needle")
	if "highway_network_component_info" not in src:
		_fail("overlay must compute highway connectivity once per rebuild")
	var apply_fn: String = _slice_func(src, "_apply_road_tier_cache")
	if apply_fn.is_empty() or "_road_stub_dropped.clear()" in apply_fn:
		_fail("_apply_road_tier_cache must not clear the demoted-stub list")
	var rebuild_fn: String = _slice_func(src, "_rebuild_road_layer_inner")
	var hit_i: int = rebuild_fn.find("if hwy3_cache_hit:")
	var ret_i: int = rebuild_fn.find("return", hit_i) if hit_i >= 0 else -1
	var hit_block: String = rebuild_fn.substr(hit_i, ret_i - hit_i) if hit_i >= 0 and ret_i > hit_i else ""
	if hit_block.is_empty() or "_apply_road_tier_cache" in hit_block:
		_fail("L-toggle cache hit must not re-apply road-tier chains")


func _boot_live_scenario() -> bool:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null:
		_fail("MapManager autoload missing")
		return false
	var LoaderScr: GDScript = load(SRC_LOADER) as GDScript
	if LoaderScr == null:
		_fail("could not load ScenarioLoader.gd")
		return false
	_loader = LoaderScr.new()
	if _loader == null:
		_fail("could not instantiate ScenarioLoader")
		return false
	_loader.name = "ScenarioLoader"
	root.add_child(_loader)
	if _loader.has_method("load_base_provinces"):
		_loader.call("load_base_provinces")
	if not _loader.has_method("load_scenario"):
		_fail("ScenarioLoader.load_scenario missing")
		return false
	var ok: bool = bool(await _loader.load_scenario("world_accurate"))
	if not ok:
		_fail("load_scenario(world_accurate) failed")
		return false
	if not _loader.has_method("get_map_data"):
		_fail("ScenarioLoader.get_map_data missing")
		return false
	var map_data: Variant = _loader.call("get_map_data")
	if map_data == null:
		_fail("ScenarioLoader.get_map_data returned null")
		return false
	if mm.has_method("initialize_from_map_data"):
		mm.call("initialize_from_map_data", map_data)
	if mm.has_method("rebuild_pick_grid"):
		mm.call("rebuild_pick_grid")
	_bind_map_renderer()
	_ol = _make_overlay(load(SRC_OL) as GDScript)
	if _ol == null:
		return false
	await process_frame
	var t0: int = Time.get_ticks_usec()
	if _ol.has_method("invalidate_hwy3_route_cache"):
		_ol.call("invalidate_hwy3_route_cache")
	_ol.call("_rebuild_road_layer_inner")
	_load_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	var dbg_v: Variant = RoadTierVisualScript.hwy3_debug()
	if typeof(dbg_v) == TYPE_DICTIONARY:
		var dbg: Dictionary = dbg_v
		print(
			"LIVE_LON_PROBE load_ms=%.2f route_ms=%.2f hubs_ms=%.2f adj_ms=%.2f"
			% [
				_load_ms,
				float(dbg.get("route_ms", 0.0)),
				float(dbg.get("hubs_ms", 0.0)),
				float(dbg.get("adj_ms", 0.0)),
			]
		)
	else:
		print("LIVE_LON_PROBE load_ms=%.2f" % _load_ms)
	if _cache().is_empty():
		_fail("live scenario trunk cache is empty")
		return false
	_ol.call("set_supply_corridor_path", [710417, 710416])
	return true


func _bind_map_renderer() -> void:
	var existing: Node = get_first_node_in_group("map_renderer")
	if existing != null:
		_mr = existing
		return
	_mr = MapRendererStub.new()
	_mr.name = "MapRendererStub"
	root.add_child(_mr)
	_mr.add_to_group("map_renderer")


func _make_overlay(gs: GDScript) -> Node2D:
	if gs == null:
		_fail("could not load overlay script")
		return null
	var ol: Node2D = gs.new() as Node2D
	if ol == null:
		_fail("could not instantiate overlay")
		return null
	root.add_child(ol)
	var mm: Node = root.get_node_or_null("/root/MapManager")
	ol.set("map_manager", mm)
	if ol.has_method("_ensure_sub_layers"):
		ol.call("_ensure_sub_layers")
	return ol


func _cache_of(ol: Node) -> Array:
	if ol != null and ol.has_method("get_road_tier_cache"):
		var cache_v: Variant = ol.call("get_road_tier_cache")
		if typeof(cache_v) == TYPE_ARRAY:
			return cache_v
	return []


func _cache() -> Array:
	return _cache_of(_ol)


func _compute_of(ol: Node) -> int:
	if ol != null and ol.has_method("get_hwy3_route_compute_count"):
		return int(ol.call("get_hwy3_route_compute_count"))
	return -1


func _compute() -> int:
	return _compute_of(_ol)


func _highway_keys(cache: Array) -> Dictionary:
	var keys: Dictionary = {}
	for row_v in cache:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) == RoadTierVisualScript.TIER_HIGHWAY:
			keys[RoadTierVisualScript.edge_key(int(row.get("p1", 0)), int(row.get("p2", 0)))] = true
	return keys


func _keys_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
	return true


func _set_supply(on: bool) -> void:
	if _mr == null:
		return
	_mr.set("supply_mode", on)
	_mr.set("current_map_mode", "supply" if on else "political")


func _toggle_like_l(on: bool) -> float:
	_set_supply(on)
	var t0: int = Time.get_ticks_usec()
	if _ol.has_method("set_show_roads"):
		_ol.call("set_show_roads", false)
	else:
		_ol.call("_rebuild_road_layer_inner")
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _test_a_toggle_reuses_cache() -> void:
	var before: int = _compute()
	if before < 1:
		_fail("(a) route-compute counter was %d after boot (want >= 1)" % before)
		return
	var keys0: Dictionary = _highway_keys(_cache())
	if keys0.is_empty():
		_fail("(a) no highway keys after boot")
		return
	_toggle_like_l(true)
	var after_on: int = _compute()
	var keys_on: Dictionary = _highway_keys(_cache())
	_toggle_like_l(false)
	var after_off: int = _compute()
	var keys_off: Dictionary = _highway_keys(_cache())
	_toggle_like_l(true)
	var after_on2: int = _compute()
	var keys_on2: Dictionary = _highway_keys(_cache())
	print(
		"HWY3_SUPPLY_TOGGLE compute boot=%d on=%d off=%d on2=%d hwy=%d"
		% [before, after_on, after_off, after_on2, keys0.size()]
	)
	if after_on != before or after_off != before or after_on2 != before:
		_fail("(a) route-compute counter moved on toggle %d → %d/%d/%d" % [before, after_on, after_off, after_on2])
	else:
		_pass("(a) toggle on/off/on left route-compute at %d" % before)
	if not _keys_equal(keys0, keys_on) or not _keys_equal(keys0, keys_off) or not _keys_equal(keys0, keys_on2):
		_fail("(a) highway key set drifted across supply toggles")
	else:
		_pass("(a) highway key set identical across on/off/on (%d)" % keys0.size())


func _count_of(ol: Node, method_name: String) -> int:
	if ol != null and ol.has_method(method_name):
		return int(ol.call(method_name))
	return -1


func _test_cached_path_skips_geom() -> void:
	var geom0: int = _count_of(_ol, "get_road_geom_apply_count")
	var comp0: int = _count_of(_ol, "get_road_component_info_count")
	if geom0 < 1 or comp0 < 1:
		_fail("cached-path counters missing after boot geom=%d info=%d" % [geom0, comp0])
		return
	_toggle_like_l(true)
	_toggle_like_l(false)
	_toggle_like_l(true)
	var geom1: int = _count_of(_ol, "get_road_geom_apply_count")
	var comp1: int = _count_of(_ol, "get_road_component_info_count")
	print("HWY3_CACHE_PATH geom=%d→%d info=%d→%d" % [geom0, geom1, comp0, comp1])
	if geom1 != geom0:
		_fail("L toggle re-applied road chains (%d → %d)" % [geom0, geom1])
	else:
		_pass("L toggle reused drawable/chains (geom apply stayed %d)" % geom0)
	if comp1 != comp0:
		_fail("L toggle rebuilt highway connectivity (%d → %d)" % [comp0, comp1])
	else:
		_pass("L toggle reused highway connectivity (info stayed %d)" % comp0)


func _test_stub_report_lists_demoted() -> void:
	if _ol == null or not _ol.has_method("get_highway_stub_report"):
		_fail("get_highway_stub_report missing")
		return
	var report_v: Variant = _ol.call("get_highway_stub_report")
	if typeof(report_v) != TYPE_DICTIONARY:
		_fail("stub report is not a Dictionary")
		return
	var report: Dictionary = report_v
	var n: int = int(report.get("dropped_n", -1))
	var keys_v: Variant = report.get("dropped", [])
	var keys: Array = keys_v if typeof(keys_v) == TYPE_ARRAY else []
	var edges_v: Variant = report.get("edges", [])
	var edges: Array = edges_v if typeof(edges_v) == TYPE_ARRAY else []
	var want_a: String = RoadTierVisualScript.edge_key(903534, 905809)
	var want_b: String = RoadTierVisualScript.edge_key(905807, 905809)
	var have_a: bool = keys.has(want_a)
	var have_b: bool = keys.has(want_b)
	var named: int = 0
	for ev in edges:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = ev
		if str(e.get("n1", "")).is_empty() or str(e.get("n2", "")).is_empty():
			continue
		named += 1
	print(
		"HWY3_STUB_REPORT n=%d keys=%s named=%d"
		% [n, str(keys), named]
	)
	if n < 2 or not have_a or not have_b:
		_fail("stub report must list demoted 903534–905809 and 905807–905809 (n=%d)" % n)
	elif named < 2:
		_fail("stub report edges must include province names")
	else:
		_pass("stub report lists demoted Moscow stub by pid + name")


func _test_live_lon_probe() -> void:
	for run_i in range(2):
		var off_ms: float = _toggle_like_l(false)
		var on_ms: float = _toggle_like_l(true)
		print(
			"LIVE_LON_PROBE run=%d off_frame2=%.2f on_warm=%.2f load_ms=%.2f"
			% [run_i + 1, off_ms, on_ms, _load_ms]
		)
		if off_ms > OFF_FRAME2_LIMIT_MS:
			_fail("LiveLonProbe run %d off frame2 %.2f ms > %.0f" % [run_i + 1, off_ms, OFF_FRAME2_LIMIT_MS])
		else:
			_pass("LiveLonProbe run %d off frame2 %.2f ms" % [run_i + 1, off_ms])
		if on_ms > ON_WARM_LIMIT_MS:
			_fail("LiveLonProbe run %d on_warm %.2f ms > %.0f" % [run_i + 1, on_ms, ON_WARM_LIMIT_MS])
		elif on_ms > ON_WARM_CACHED_LIMIT_MS:
			_fail("LiveLonProbe run %d on_warm %.2f ms > cached-path %.0f" % [run_i + 1, on_ms, ON_WARM_CACHED_LIMIT_MS])
		else:
			_pass("LiveLonProbe run %d on_warm %.2f ms" % [run_i + 1, on_ms])


func _test_c_corridor_styling() -> void:
	_ol.call("set_supply_corridor_path", [710417, 710416])
	_set_supply(true)
	_ol.call("_rebuild_road_layer_inner")
	var n: int = 0
	if _ol.has_method("get_supply_corridor_line_count"):
		n = int(_ol.call("get_supply_corridor_line_count"))
	var on_edge: bool = false
	for row_v in _cache():
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if (a == 710417 and b == 710416) or (a == 710416 and b == 710417):
			on_edge = bool(row.get("corridor", false))
			break
	print("HWY3_SUPPLY_STYLE glow=%d corridor_flag=%s" % [n, str(on_edge)])
	if n <= 0:
		_fail("(c) supply on left no corridor glow lines")
	else:
		_pass("(c) supply on applied corridor styling (glow=%d)" % n)
	if not on_edge:
		_fail("(c) 710417–710416 corridor flag not set while supply on")


func _koeln() -> Object:
	var mm: Node = root.get_node_or_null("/root/MapManager")
	if mm == null or not mm.has_method("get_province"):
		return null
	return mm.call("get_province", 710417)


func _test_b_infra_change_recomputes() -> void:
	var p: Object = _koeln()
	if p == null:
		_fail("(b) Köln 710417 missing")
		return
	var before: int = _compute()
	var old_infra: int = int(p.get("infrastructure"))
	p.set("infrastructure", old_infra + 3)
	_ol.call("_rebuild_road_layer_inner")
	var after: int = _compute()
	p.set("infrastructure", old_infra)
	print("HWY3_SUPPLY_INFRA compute %d → %d (infra %d→%d)" % [before, after, old_infra, old_infra + 3])
	if after != before + 1:
		_fail("(b) infra change did not recompute (count %d → %d)" % [before, after])
	else:
		_pass("(b) infra change recomputed hub routes")


func _mutated_overlay(kind: String) -> Node2D:
	var src: String = _read_text(SRC_OL)
	var mutated: String = src
	if kind == "ignore_infra":
		mutated = mutated.replace(
			'var infra_bit: String = str(board.get("infra", 0))',
			'var infra_bit: String = "0"'
		)
	elif kind == "bypass_toggle":
		mutated = mutated.replace(
			"var hwy3_cache_hit: bool = (",
			"var hwy3_cache_hit: bool = false and ("
		)
	elif kind == "skip_styling":
		mutated = mutated.replace(
			"if supply_on and on_corridor:",
			"if false and supply_on and on_corridor:"
		)
	else:
		_fail("unknown mutant %s" % kind)
		return null
	mutated = mutated.replace("class_name InfrastructureOverlayLayer\n", "")
	var inject_at: int = mutated.find("extends Node2D\n")
	if inject_at < 0:
		_fail("mutant %s: extends Node2D missing" % kind)
		return null
	inject_at += String("extends Node2D\n").length()
	mutated = (
		mutated.substr(0, inject_at)
		+ "func hwy3_supply_cache_mutant_token() -> String:\n    return \"%s\"\n" % kind
		+ mutated.substr(inject_at)
	)
	var gs := GDScript.new()
	gs.source_code = mutated
	if gs.reload() != OK:
		_fail("mutant %s: mutated script failed to parse" % kind)
		return null
	var ol: Node2D = _make_overlay(gs)
	if ol == null:
		return null
	if not ol.has_method("hwy3_supply_cache_mutant_token"):
		_fail("mutant %s: in-memory script is not the mutated source" % kind)
		ol.queue_free()
		return null
	if str(ol.call("hwy3_supply_cache_mutant_token")) != kind:
		_fail("mutant %s: token mismatch" % kind)
		ol.queue_free()
		return null
	ol.call("_rebuild_road_layer_inner")
	return ol


func _test_mutant_ignore_infra() -> void:
	var ol: Node2D = _mutated_overlay("ignore_infra")
	if ol == null:
		return
	var p: Object = _koeln()
	if p == null:
		_fail("mutant ignore_infra: Köln missing")
		ol.queue_free()
		return
	var before: int = _compute_of(ol)
	var old_infra: int = int(p.get("infrastructure"))
	p.set("infrastructure", old_infra + 5)
	ol.call("_rebuild_road_layer_inner")
	var after: int = _compute_of(ol)
	p.set("infrastructure", old_infra)
	print("HWY3_MUTANT ignore_infra compute %d → %d" % [before, after])
	if after != before:
		_fail("mutant ignore_infra survived (b) still recomputed")
	else:
		_pass("mutant ignore_infra killed (b)")
	ol.queue_free()


func _test_mutant_bypass_toggle() -> void:
	var ol: Node2D = _mutated_overlay("bypass_toggle")
	if ol == null:
		return
	var before: int = _compute_of(ol)
	_set_supply(true)
	ol.call("set_show_roads", false)
	_set_supply(false)
	ol.call("set_show_roads", false)
	var after: int = _compute_of(ol)
	print("HWY3_MUTANT bypass_toggle compute %d → %d" % [before, after])
	if after == before:
		_fail("mutant bypass_toggle survived (a) still reused cache")
	else:
		_pass("mutant bypass_toggle killed (a)")
	ol.queue_free()


func _test_mutant_skip_styling() -> void:
	var ol: Node2D = _mutated_overlay("skip_styling")
	if ol == null:
		return
	ol.call("set_supply_corridor_path", [710417, 710416])
	_set_supply(true)
	ol.call("_rebuild_road_layer_inner")
	var n: int = 0
	if ol.has_method("get_supply_corridor_line_count"):
		n = int(ol.call("get_supply_corridor_line_count"))
	print("HWY3_MUTANT skip_styling glow=%d" % n)
	if n > 0:
		_fail("mutant skip_styling survived (c) still drew glow")
	else:
		_pass("mutant skip_styling killed (c)")
	ol.queue_free()
