extends SceneTree

## RENDER-1: idle prebuild role map vs fresh `_compute_supply_highlight_roles()`
## at L-on, per pid (not the histogram).
##
## Tip (no mutant env): PASS — prebuild roles == L-on compute, and prebuild
## never passed `allow_without_overlay`.
## Mutant `EOA_RENDER1_PREBUILD_MUTANT=lon_semantics_off` (MapRenderer ~l.30254
## `_supply_role_lon_semantics=false`): FAIL — infra<45 pids missing.
## Mutant `EOA_RENDER1_PREBUILD_MUTANT=allow_without_overlay`: FAIL — prebuild
## recorded the third-arg true path.
##
##   tools/eoa_render1_prebuild_role.sh
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessRender1PrebuildRoleTest.gd

const LAND_N := 240
const HUB_N := 48
const HIGH_INFRA_N := 32
const POLY_SIDES := 24
const HOME_Z := 0.318
const FLUSH_FRAMES := 3
const PREBUILD_WAIT_FRAMES := 360

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null
var _hub_pids: Array[int] = []
var _low_infra_pids: Array[int] = []
var _high_infra_pids: Array[int] = []
var _mutant: String = ""


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessRender1PrebuildRoleTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRender1PrebuildRoleTest: RESULT=", "PASS" if ok else "FAIL")
	print("HeadlessRender1PrebuildRoleTest: mutant=%s" % _mutant)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRender1PrebuildRoleTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRender1PrebuildRoleTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessRender1PrebuildRoleTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
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


func _histogram(roles: Dictionary) -> Dictionary:
	var hist: Dictionary = {}
	for pid_var in roles.keys():
		var role := str(roles[pid_var])
		if role.is_empty():
			continue
		hist[role] = int(hist.get(role, 0)) + 1
	return hist


func _run() -> void:
	_mutant = OS.get_environment("EOA_RENDER1_PREBUILD_MUTANT").strip_edges()
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)
	if not _setup_renderer():
		return
	await _flush()
	var pre_stats: Dictionary = await _wait_idle_prebuild()
	_info(
		"idle_prebuild done=%s items=%d max_step=%.3f mutant=%s"
		% [
			str(pre_stats.get("done", false)),
			int(pre_stats.get("item_count", -1)),
			float(pre_stats.get("max_step_ms", -1.0)),
			_mutant,
		]
	)
	if not bool(pre_stats.get("done", false)):
		_fail("idle prebuild did not finish")
		return
	if not _mr.has_method("get_supply_prebuild_roles_copy"):
		_fail("get_supply_prebuild_roles_copy missing")
		return
	# Snapshot BEFORE L-on.
	var pre_roles: Dictionary = _mr.call("get_supply_prebuild_roles_copy") as Dictionary
	_info("prebuild roles n=%d hist=%s (before L-on)" % [pre_roles.size(), str(_histogram(pre_roles))])
	if pre_roles.is_empty():
		_fail("prebuild role map empty before L-on")
		return
	var used_allow := false
	if _mr.has_method("prebuild_used_allow_without_overlay"):
		used_allow = bool(_mr.call("prebuild_used_allow_without_overlay"))
	if used_allow:
		_fail("prebuild used allow_without_overlay (must be L-on semantics, not third-arg true)")
	else:
		_pass("prebuild did not pass allow_without_overlay")
	# L-on, then a fresh compute — not the histogram, not the cache.
	if "supply_mode" in _mr:
		_mr.supply_mode = false
	var sm: Node = root.get_node_or_null("SupplyManager")
	if sm != null and "overlay_visible" in sm:
		sm.overlay_visible = false
	_mr.call("_toggle_supply_overlay")
	await process_frame
	if not _mr.has_method("_compute_supply_highlight_roles"):
		_fail("_compute_supply_highlight_roles missing")
		return
	var fresh: Dictionary = _mr.call("_compute_supply_highlight_roles") as Dictionary
	_info("fresh L-on compute n=%d hist=%s" % [fresh.size(), str(_histogram(fresh))])
	_compare_per_pid(pre_roles, fresh)
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()


func _compare_per_pid(pre_roles: Dictionary, fresh: Dictionary) -> void:
	var mismatch := 0
	var only_pre := 0
	var only_fresh := 0
	var samples: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for pid_var in fresh.keys():
		var pid := int(pid_var)
		seen[pid] = true
		var want := str(fresh[pid_var])
		var got := str(pre_roles.get(pid, ""))
		if got != want:
			mismatch += 1
			if samples.size() < 8:
				samples.append("pid=%d pre=%s fresh=%s" % [pid, got, want])
			if got.is_empty():
				only_fresh += 1
	for pid_var in pre_roles.keys():
		var pid := int(pid_var)
		if seen.has(pid):
			continue
		only_pre += 1
		mismatch += 1
		if samples.size() < 8:
			samples.append("pid=%d pre=%s fresh=" % [pid, str(pre_roles[pid_var])])
	print(
		"prebuild_vs_fresh mismatch=%d only_pre=%d only_fresh=%d pre_n=%d fresh_n=%d samples=%s"
		% [mismatch, only_pre, only_fresh, pre_roles.size(), fresh.size(), ", ".join(samples)]
	)
	if mismatch != 0:
		_fail(
			"prebuild role map != fresh _compute_supply_highlight_roles() at L-on mismatch=%d only_pre=%d only_fresh=%d"
			% [mismatch, only_pre, only_fresh]
		)
	else:
		_pass("prebuild role map == fresh L-on compute per pid n=%d" % fresh.size())
	# Fixture must actually distinguish lon_semantics=false (engineers present).
	var fresh_eng := 0
	var pre_eng := 0
	for pid_var in fresh.keys():
		if str(fresh[pid_var]) == "engineers_recommended":
			fresh_eng += 1
	for pid_var in pre_roles.keys():
		if str(pre_roles[pid_var]) == "engineers_recommended":
			pre_eng += 1
	_info("engineers_recommended pre=%d fresh=%d low_infra_seeded=%d" % [
		pre_eng, fresh_eng, _low_infra_pids.size(),
	])
	if fresh_eng < 8:
		_fail("fixture too hub-heavy: fresh engineers_recommended=%d (lon_semantics_off mutant would be invisible)" % fresh_eng)


func _wait_idle_prebuild() -> Dictionary:
	var stats: Dictionary = {}
	var i := 0
	while i < PREBUILD_WAIT_FRAMES:
		if _mr.has_method("get_supply_ring_prebuild_stats"):
			stats = _mr.call("get_supply_ring_prebuild_stats") as Dictionary
			if bool(stats.get("done", false)):
				return stats
		await process_frame
		i += 1
	if _mr.has_method("get_supply_ring_prebuild_stats"):
		stats = _mr.call("get_supply_ring_prebuild_stats") as Dictionary
	return stats


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
	if sm == null:
		_fail("SupplyManager autoload missing")
		return false
	var depot_scr: Script = load("res://scripts/supply/ProvinceDepotState.gd") as Script
	if "depot_states" in sm:
		(sm.depot_states as Dictionary).clear()
	if "player_depot_province_ids" in sm:
		(sm.player_depot_province_ids as Array).clear()
	var i := 0
	while i < LAND_N:
		var pid := 710000 + i
		var host := Node2D.new()
		host.name = "Prov_%d" % pid
		host.position = Vector2.ZERO
		var poly := Polygon2D.new()
		poly.polygon = _make_ring(Vector2(float(i % 24) * 40.0, float(i / 24) * 40.0), 18.0, POLY_SIDES)
		host.add_child(poly)
		_container.add_child(host)
		_mr.province_nodes[pid] = host
		var is_hub := i < HUB_N
		var is_high := (not is_hub) and i >= (LAND_N - HIGH_INFRA_N)
		var infra := 1
		if is_high:
			infra = 80
		if pscr != null:
			var p: Object = pscr.new()
			p.set("id", pid)
			p.set("name", "Land %d" % pid)
			p.set("owner_tag", "GER")
			p.set("controller_tag", "GER")
			p.set("infrastructure", infra)
			p.set("is_sea", false)
			_mr.provinces[pid] = p
			if mm != null and "_provinces" in mm:
				mm._provinces[pid] = p
		if is_hub:
			_hub_pids.append(pid)
			if depot_scr != null and "depot_states" in sm:
				sm.depot_states[pid] = depot_scr.new(pid, 100.0)
			if "player_depot_province_ids" in sm:
				(sm.player_depot_province_ids as Array).append(pid)
		elif is_high:
			_high_infra_pids.append(pid)
		else:
			_low_infra_pids.append(pid)
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
	_info(
		"seeded land=%d hubs=%d low_infra=%d high_infra=%d (mixed so lon_semantics_off is visible)"
		% [LAND_N, _hub_pids.size(), _low_infra_pids.size(), _high_infra_pids.size()]
	)
	return true
