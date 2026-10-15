extends SceneTree

## RENDER-1: L-on supply rings as pre-built ArrayMesh + Home-zoom LOD.
## FAILS on 5df8e7fc (polyline/AA _draw). PASSES on the tip.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessRender1SupplyRingMeshTest.gd

const LAND_N := 3196
const POLY_SIDES := 48
const HOME_Z := 0.318
const CLOSE_Z := 0.90
const FLUSH_FRAMES := 3
const PATCH_SAMPLES := 21
const IDLE_FRAMES := 60
const MAX_PATCH_P50_MS := 1.0
const MAX_PATCH_WORST_MS := 50.0
const MAX_WARM_FRAME_MS := 100.0
const MAX_COLD_MS := 250.0
const HOME_VERT_RATIO := 0.25
const LAYER_PATH := "res://scripts/map/SupplyOutlineBatchLayer.gd"
const ROLES: PackedStringArray = PackedStringArray([
	"active", "preview", "route", "infra_sabotage", "infra_repair",
	"infra_repair_engineers", "engineers_stationed", "engineers_needed",
	"engineers_recommended", "engineers_insufficient", "infra_duel_even",
	"depot_sabotage", "supply_pressure", "trade_transit", "hub",
])

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null
var _sink_mesh_n: int = 0
var _sink_verts: int = 0
var _sink_idx: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessRender1SupplyRingMeshTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRender1SupplyRingMeshTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRender1SupplyRingMeshTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRender1SupplyRingMeshTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessRender1SupplyRingMeshTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func note_draw_mesh(_mesh: Variant, v_n: int, i_n: int) -> void:
	_sink_mesh_n += 1
	_sink_verts += v_n
	_sink_idx += i_n


func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx := int(round((p / 100.0) * float(sorted.size() - 1)))
	idx = clampi(idx, 0, sorted.size() - 1)
	return float(sorted[idx])


func _make_ring(origin: Vector2, radius: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sides)
	var i := 0
	while i < sides:
		var a := TAU * float(i) / float(sides)
		pts[i] = origin + Vector2(cos(a), sin(a)) * radius
		i += 1
	return pts


func _style_for(role: String) -> Dictionary:
	return ProvinceMapVisuals.get_supply_outline_style(role)


func _make_items(n: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var i := 0
	while i < n:
		var pid := 710000 + i
		var origin := Vector2(float(i % 80) * 40.0, float(i / 80) * 40.0)
		var role := str(ROLES[i % ROLES.size()]) if i < ROLES.size() else "route"
		if i >= ROLES.size() and i % 97 == 0:
			role = str(ROLES[i % ROLES.size()])
		var style: Dictionary = _style_for(role)
		items.append({
			"pid": pid,
			"points": _make_ring(origin, 24.0, POLY_SIDES),
			"color": style["color"],
			"glow": style["glow"],
			"width": style["width"],
			"glow_extra": style["glow_extra"],
			"z_index": style["z_index"],
			"role": role,
		})
		i += 1
	return items


func _scan_layer_source() -> Dictionary:
	var txt := FileAccess.get_file_as_string(LAYER_PATH)
	var line_hits := 0
	var aa_hits := 0
	var polished_hits := 0
	for raw in txt.split("\n"):
		var line := str(raw)
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		if line.find("draw_polyline") >= 0 or line.find("draw_multiline") >= 0:
			line_hits += 1
		if line.find("canvas_item_add_polyline") >= 0 or line.find("canvas_item_add_multiline") >= 0:
			line_hits += 1
		if line.find("antialiased") >= 0:
			aa_hits += 1
		if line.find("draw_polished_ring") >= 0:
			polished_hits += 1
	return {
		"line_hits": line_hits,
		"aa_hits": aa_hits,
		"polished_hits": polished_hits,
		"ok": line_hits == 0 and aa_hits == 0 and polished_hits == 0,
	}


func _reset_sink() -> void:
	_sink_mesh_n = 0
	_sink_verts = 0
	_sink_idx = 0


func _draw_layer(layer: Node) -> Dictionary:
	_reset_sink()
	layer.set("draw_sink", self)
	if not bool(layer.visible):
		layer.visible = true
	if layer is CanvasItem:
		(layer as CanvasItem).queue_redraw()
	await process_frame
	var stats: Dictionary = {}
	if layer.has_method("get_last_draw_stats"):
		stats = layer.call("get_last_draw_stats") as Dictionary
		if int(stats.get("mesh_calls", 0)) <= 0 and layer.has_method("_draw"):
			_reset_sink()
			layer.call("_draw")
			stats = {}
	if layer.has_method("get_last_draw_stats"):
		stats = layer.call("get_last_draw_stats") as Dictionary
	else:
		stats = {
			"mesh_calls": 0,
			"line_calls": -1,
			"aa_calls": -1,
			"drawn_vertices": 0,
			"drawn_indices": 0,
			"drawn_mesh_n": 0,
			"culled_chunks": 0,
			"built_vertices": 0,
			"built_indices": 0,
			"rebuilds": -1,
			"chunk_n": 0,
		}
	stats["sink_mesh_n"] = _sink_mesh_n
	stats["sink_verts"] = _sink_verts
	stats["sink_idx"] = _sink_idx
	return stats


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)
	var items := _make_items(LAND_N)
	if items.size() < 3000:
		_fail("seeded items=%d want >=3000" % items.size())
		return
	await _test_layer_bars(items)
	await _test_maprenderer_toggle()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()


func _test_layer_bars(items: Array[Dictionary]) -> void:
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
	await _flush()

	if not layer.has_method("set_view") or not layer.has_method("get_last_draw_stats"):
		_fail("(a-g) mesh/LOD API missing on layer (base polyline path)")
		layer.queue_free()
		return

	var src := _scan_layer_source()
	var full_rect := Rect2(-2000, -2000, 8000, 4000)
	layer.call("set_view", HOME_Z, full_rect)
	layer.call("set_items", items)
	await _flush()
	if int(layer.call("item_count")) < 3000:
		_fail("item_count=%d want >=3000" % int(layer.call("item_count")))
	else:
		_pass("live-weight items=%d" % int(layer.call("item_count")))

	var home_stats := await _draw_layer(layer)
	_check_a(src, home_stats)
	_check_g(layer, items)
	var home_built := int(layer.call("get_built_vertex_count")) if layer.has_method("get_built_vertex_count") else 0
	var home_idx := int(layer.call("get_built_index_count")) if layer.has_method("get_built_index_count") else 0
	_info("Home built verts=%d idx=%d mesh_calls=%d chunks=%d" % [
		home_built, home_idx, int(home_stats.get("mesh_calls", 0)), int(home_stats.get("chunk_n", 0)),
	])

	layer.call("set_view", CLOSE_Z, full_rect)
	await _flush()
	var full_stats := await _draw_layer(layer)
	var full_built := int(layer.call("get_built_vertex_count")) if layer.has_method("get_built_vertex_count") else 0
	await _check_b(home_built, full_built, layer, full_rect)
	_check_counter_lie(full_stats)

	layer.call("set_view", HOME_Z, full_rect)
	await _flush()
	await _draw_layer(layer)
	await _check_c(layer)
	await _check_d(layer, items)
	await _check_f(layer)
	await _check_skip(layer)

	_info(
		"tip Home verts=%d Full verts=%d ratio=%.3f mesh_calls_home=%d"
		% [
			home_built, full_built,
			(float(home_built) / float(full_built)) if full_built > 0 else -1.0,
			int(home_stats.get("mesh_calls", 0)),
		]
	)
	layer.queue_free()


func _check_a(src: Dictionary, stats: Dictionary) -> void:
	var line_hits := int(src.get("line_hits", 1))
	var aa_hits := int(src.get("aa_hits", 1))
	var polished := int(src.get("polished_hits", 1))
	var mesh_calls := int(stats.get("mesh_calls", 0))
	var line_calls := int(stats.get("line_calls", -1))
	var aa_calls := int(stats.get("aa_calls", -1))
	if line_hits != 0 or polished != 0:
		_fail("(a) steady path source still has line/polished hits line=%d polished=%d" % [line_hits, polished])
	elif mesh_calls <= 0:
		_fail("(a) steady _draw emitted 0 draw_mesh calls")
	elif line_calls != 0 or aa_calls != 0:
		_fail("(a) line_calls=%d aa_calls=%d want 0" % [line_calls, aa_calls])
	else:
		_pass("(a) 0 line/AA calls, mesh_calls=%d" % mesh_calls)
	if aa_hits != 0:
		_fail("mutant_aa_on: source antialiased hits=%d" % aa_hits)
	else:
		_pass("mutant_aa_on killed by (a) source+runtime aa_calls=0")
	if line_hits != 0 or polished != 0 or mesh_calls <= 0:
		_fail("mutant_polyline_loop survived")
	else:
		_pass("mutant_polyline_loop killed by (a) 0 line calls / mesh path")


func _check_b(home_built: int, full_built: int, layer: Node, full_rect: Rect2) -> void:
	if full_built <= 0 or home_built <= 0:
		_fail("(b) missing mesh array totals home=%d full=%d" % [home_built, full_built])
		return
	var ratio := float(home_built) / float(full_built)
	if ratio > HOME_VERT_RATIO:
		_fail("(b) Home verts %d / full %d = %.3f want <=%.2f (lod_off mutant)" % [
			home_built, full_built, ratio, HOME_VERT_RATIO,
		])
	else:
		_pass("(b) Home verts %d / full %d = %.3f" % [home_built, full_built, ratio])
		_pass("mutant_lod_off killed by (b) Home/full=%.3f" % ratio)
	var tiny := Rect2(0, 0, 80, 80)
	layer.call("set_view", CLOSE_Z, tiny)
	var culled_stats := await _draw_layer(layer)
	var drawn := int(culled_stats.get("drawn_vertices", 0))
	var culled := int(culled_stats.get("culled_chunks", 0))
	var built := int(layer.call("get_built_vertex_count")) if layer.has_method("get_built_vertex_count") else 0
	if culled <= 0 or drawn >= built:
		_fail("(b) view-rect cull failed culled=%d drawn=%d built=%d (cull_off mutant)" % [culled, drawn, built])
	else:
		_pass("(b) cull holds above threshold culled=%d drawn=%d built=%d" % [culled, drawn, built])
		_pass("mutant_cull_off killed by (b) culled_chunks=%d drawn<built" % culled)
	layer.call("set_view", CLOSE_Z, full_rect)


func _check_counter_lie(stats: Dictionary) -> void:
	var mesh_calls := int(stats.get("mesh_calls", 0))
	var sink_n := int(stats.get("sink_mesh_n", 0))
	var drawn_v := int(stats.get("drawn_vertices", 0))
	var sink_v := int(stats.get("sink_verts", 0))
	var drawn_n := int(stats.get("drawn_mesh_n", 0))
	if mesh_calls <= 0 or sink_n != mesh_calls or drawn_n != mesh_calls:
		_fail("mutant_counter_lie: mesh_calls=%d sink=%d drawn_mesh_n=%d" % [mesh_calls, sink_n, drawn_n])
	elif drawn_v != sink_v or drawn_v <= 0:
		_fail("mutant_counter_lie: drawn_verts=%d sink_verts=%d" % [drawn_v, sink_v])
	else:
		_pass("mutant_counter_lie killed: counters match real draw_mesh arrays verts=%d calls=%d" % [drawn_v, mesh_calls])


func _check_c(layer: Node) -> void:
	if not layer.has_method("get_mesh_rebuild_count"):
		_fail("(c) rebuild counter missing")
		return
	var before := int(layer.call("get_mesh_rebuild_count"))
	var i := 0
	while i < IDLE_FRAMES:
		await _draw_layer(layer)
		i += 1
	var after := int(layer.call("get_mesh_rebuild_count"))
	if after != before:
		_fail("(c) rebuilds %d→%d across %d idle frames (rebuild_in_draw mutant)" % [before, after, IDLE_FRAMES])
	else:
		_pass("(c) 0 rebuilds across %d idle frames (count=%d)" % [IDLE_FRAMES, after])
		_pass("mutant_rebuild_in_draw killed by (c)")


func _check_d(layer: Node, items: Array[Dictionary]) -> void:
	var samples: Array = []
	var chunk_n := int(layer.call("get_chunk_count")) if layer.has_method("get_chunk_count") else 0
	var i := 0
	while i < PATCH_SAMPLES:
		var item: Dictionary = items[i * 17 % items.size()].duplicate()
		item["role"] = "hub"
		var style: Dictionary = _style_for("hub")
		item["color"] = style["color"]
		item["glow"] = style["glow"]
		item["width"] = style["width"]
		item["glow_extra"] = style["glow_extra"]
		var t0 := Time.get_ticks_usec()
		layer.call("patch_items", [item], [])
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		samples.append(ms)
		i += 1
	samples.sort()
	var p50 := _pct(samples, 50.0)
	var worst := float(samples[samples.size() - 1])
	var touched := int(layer.call("get_last_chunk_rebuild_count")) if layer.has_method("get_last_chunk_rebuild_count") else chunk_n
	if p50 > MAX_PATCH_P50_MS or worst >= MAX_PATCH_WORST_MS:
		_fail("(d) 1-depot patch p50=%.3f worst=%.3f (limits %.1f / <%d)" % [p50, worst, MAX_PATCH_P50_MS, int(MAX_PATCH_WORST_MS)])
	else:
		_pass("(d) 1-depot patch p50=%.3f worst=%.3f" % [p50, worst])
	if chunk_n > 1 and touched >= chunk_n:
		_fail("(d) patch rebuilt %d/%d chunks (patch_full_rebuild mutant)" % [touched, chunk_n])
	elif touched <= 0:
		_fail("(d) patch rebuilt 0 chunks")
	else:
		_pass("(d) touched chunks=%d / %d" % [touched, chunk_n])
		_pass("mutant_patch_full_rebuild killed by (d) touched=%d/%d" % [touched, chunk_n])


func _check_f(layer: Node) -> void:
	if not layer.has_method("get_mesh_rebuild_count"):
		_fail("(f) rebuild counter missing")
		return
	var before := int(layer.call("get_mesh_rebuild_count"))
	var p := 0
	while p < 8:
		layer.call("set_pulse_phase", float(p) * 0.4)
		p += 1
	await _draw_layer(layer)
	var after := int(layer.call("get_mesh_rebuild_count"))
	if after != before:
		_fail("(f) pulse rebuilt meshes %d→%d (pulse_rebuild mutant)" % [before, after])
	else:
		_pass("(f) pulse modulate-only (rebuilds=%d)" % after)
		_pass("mutant_pulse_rebuild killed by (f)")


func _check_skip(layer: Node) -> void:
	var before_vis := int(layer.call("visible_item_count"))
	var before_built := int(layer.call("get_built_vertex_count")) if layer.has_method("get_built_vertex_count") else 0
	var skip := {710000: true, 710001: true}
	layer.call("set_skip_pids", skip)
	await _draw_layer(layer)
	var after_vis := int(layer.call("visible_item_count"))
	var after_built := int(layer.call("get_built_vertex_count")) if layer.has_method("get_built_vertex_count") else 0
	if after_vis != before_vis - 2 or after_built >= before_built:
		_fail("mutant_skip_ignored: vis %d→%d built %d→%d" % [before_vis, after_vis, before_built, after_built])
	else:
		_pass("mutant_skip_ignored killed: vis %d→%d built %d→%d" % [before_vis, after_vis, before_built, after_built])
	layer.call("set_skip_pids", {})


func _check_g(layer: Node, items: Array[Dictionary]) -> void:
	if not layer.has_method("get_role_style_records") or not layer.has_method("get_roles_in_meshes"):
		_fail("(g) role/style records missing")
		return
	var recs: Array = layer.call("get_role_style_records")
	var in_mesh: Dictionary = layer.call("get_roles_in_meshes")
	var mismatch := 0
	var missing_role := 0
	for rec_var in recs:
		if typeof(rec_var) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_var
		var role := str(rec.get("role", ""))
		var expect: Dictionary = _style_for(role)
		var color := rec.get("color", Color.BLACK) as Color
		var glow := rec.get("glow", Color.BLACK) as Color
		var width := float(rec.get("width", -1.0))
		var glow_extra := float(rec.get("glow_extra", -1.0))
		var exp_c := expect["color"] as Color
		var exp_g := expect["glow"] as Color
		if not color.is_equal_approx(exp_c) or not glow.is_equal_approx(exp_g):
			mismatch += 1
		if absf(width - float(expect["width"])) > 0.001 or absf(glow_extra - float(expect["glow_extra"])) > 0.001:
			mismatch += 1
		if not in_mesh.has(role):
			missing_role += 1
	var seeded_roles: Dictionary = {}
	for item in items:
		seeded_roles[str(item.get("role", ""))] = true
	for role_var in seeded_roles.keys():
		if not in_mesh.has(role_var):
			missing_role += 1
	if mismatch > 0 or missing_role > 0 or recs.size() < ROLES.size():
		_fail("(g) colour/width mismatch=%d missing_roles=%d recs=%d" % [mismatch, missing_role, recs.size()])
	else:
		_pass("(g) colour/width parity for %d roles, all present in meshes" % recs.size())


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
		host.position = Vector2.ZERO
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


func _test_maprenderer_toggle() -> void:
	if not _setup_renderer():
		return
	await _flush()
	var sm: Node = root.get_node_or_null("SupplyManager")
	if sm != null and "overlay_visible" in sm:
		sm.overlay_visible = false
	_mr.supply_mode = false
	if "_supply_roles_cache" in _mr:
		_mr._supply_roles_cache = {}
	if "_supply_roles_cache_fingerprint" in _mr:
		_mr._supply_roles_cache_fingerprint = ""
	if "_supply_outline_batch" in _mr:
		var old_batch: Node = _mr.get("_supply_outline_batch") as Node
		if old_batch != null and is_instance_valid(old_batch):
			old_batch.queue_free()
		_mr._supply_outline_batch = null
	if "_supply_poly_cache" in _mr:
		_mr._supply_poly_cache = {}

	var t0 := Time.get_ticks_usec()
	_mr.call("_toggle_supply_overlay")
	await process_frame
	var cold_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var vis := 0
	if _mr.has_method("get_supply_overlay_outline_visible_count"):
		vis = int(_mr.call("get_supply_overlay_outline_visible_count"))
	var profile: Dictionary = {}
	if _mr.has_method("get_last_supply_toggle_profile"):
		profile = _mr.call("get_last_supply_toggle_profile") as Dictionary
	_info(
		"cold_first sm=%.3f refresh=%.3f batch=%.3f legend=%.3f sync=%.3f total=%.3f frame_total=%.3f vis=%d"
		% [
			float(profile.get("sm_toggle_ms", -1.0)),
			float(profile.get("refresh_highlights_ms", -1.0)),
			float(profile.get("batch_mesh_build_ms", -1.0)),
			float(profile.get("legend_ms", -1.0)),
			float(profile.get("sync_stack_ms", -1.0)),
			float(profile.get("total_ms", -1.0)),
			cold_ms, vis,
		]
	)
	if vis < 3000:
		_fail("(e′) cold L-on visible=%d want >=3000" % vis)
	if cold_ms >= MAX_COLD_MS:
		_fail("(e′) cold first L-on %.1f ms (limit %.0f; cold_full_build mutant)" % [cold_ms, MAX_COLD_MS])
	else:
		_pass("(e′) cold first L-on %.1f ms" % cold_ms)
		_pass("mutant_cold_full_build killed by (e′) %.1f ms" % cold_ms)

	_mr.call("_toggle_supply_overlay")
	await process_frame
	t0 = Time.get_ticks_usec()
	_mr.call("_toggle_supply_overlay")
	await process_frame
	var warm_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if warm_ms >= MAX_WARM_FRAME_MS:
		_fail("(e) warm L toggle first frame %.1f ms (limit %.0f)" % [warm_ms, MAX_WARM_FRAME_MS])
	else:
		_pass("(e) warm L toggle first frame %.1f ms" % warm_ms)
	_info("warm_toggle_frame_ms=%.3f" % warm_ms)
