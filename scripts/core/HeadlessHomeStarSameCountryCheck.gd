extends SceneTree

## Home capital snap on the live world_accurate country table.
## Boots TestScenario (not the light pick harness, which never loads LUX).
## Frames Europe with player_path_europe_home, then calls the shipped
## world-position query and the shipped hover/click resolve.
## Köln 710417 must stay Köln under Luxembourg's star. Wandsworth 711417
## must still snap to London 711414. Never EOA_SKIP_TITLE.
##
##   EOA_SMOKE_AUTO_BEGIN=1 tools/run_godot.sh --headless --path . \
##     --resolution 1280x740 -s res://scripts/core/HeadlessHomeStarSameCountryCheck.gd

const KOELN := 710417
const LUX := 710977
const LONDON := 711414
const WANDSWORTH := 711417
const VIEW := Vector2i(1280, 740)
const WAIT_MAP_MSEC := 420000

var _failures: PackedStringArray = PackedStringArray()
var _t0_msec: int = 0
var _last_wait_log: int = -1


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	if OS.get_environment("EOA_SKIP_TITLE").strip_edges() == "1":
		_fail("EOA_SKIP_TITLE")
		_finish()
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_force_view()
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail("scene_load_%d" % err)
		_finish()
		return
	if not await _wait_until_map():
		_finish()
		return
	_pause_clock()
	_force_view()
	var mr := _map_renderer()
	var mm := _map_manager()
	if mr == null or mm == null:
		_fail("missing_map")
		_finish()
		return
	if mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	else:
		_fail("no_player_path_europe_home")
		_finish()
		return
	await _pump(36)
	# Home fit can defer once while capital centroids land. Call the shipped path again.
	mr.call("player_path_europe_home")
	await _pump(24)
	_check_live_snap(mm, mr)
	_finish()


func _check_live_snap(mm: Node, mr: Node) -> void:
	var zoom := 1.0
	if mr.has_method("_get_camera_zoom"):
		zoom = float(mr.call("_get_camera_zoom"))
	var snap2 := 0.0
	if mm.has_method("_capital_star_snap_radius_sq"):
		snap2 = float(mm.call("_capital_star_snap_radius_sq"))
	var radius := sqrt(maxf(snap2, 0.0))
	var lux_cap := _country_capital(mm, "LUX")
	var koln_pt: Vector2 = mm.call("get_province_centroid", KOELN)
	var lux_pt: Vector2 = mm.call("get_province_centroid", LUX)
	var lon_pt: Vector2 = mm.call("get_province_centroid", LONDON)
	var wan_pt: Vector2 = mm.call("get_province_centroid", WANDSWORTH)
	var koln_dist := koln_pt.distance_to(lux_pt)
	var wan_dist := wan_pt.distance_to(lon_pt)
	var koln_inside := _point_in_province(mm, koln_pt, KOELN)
	var koln_in_lux := _point_in_province(mm, koln_pt, LUX)
	var wan_inside := _point_in_province(mm, wan_pt, WANDSWORTH)
	var wan_in_london := _point_in_province(mm, wan_pt, LONDON)
	var koln_world := int(mm.call("get_province_at_world_pos", koln_pt, true))
	var koln_pick := int(mr.call("_resolve_map_pick_pid", koln_pt))
	var wan_world := int(mm.call("get_province_at_world_pos", wan_pt, true))
	var wan_pick := int(mr.call("_resolve_map_pick_pid", wan_pt))
	var view_sz := Vector2.ZERO
	if mr.get_viewport() != null:
		view_sz = mr.get_viewport().get_visible_rect().size
	print("EOA_STAR viewport=%.0fx%.0f" % [view_sz.x, view_sz.y])
	print("EOA_STAR home_zoom=%.3f" % zoom)
	print("EOA_STAR star_radius=%.2f" % radius)
	print("EOA_STAR lux_capital=%d" % lux_cap)
	print(
		"EOA_STAR koln_point=%.1f,%.1f inside_koln=%s inside_lux_poly=%s dist_lux=%.2f radius_gt_dist=%s owner=%s"
		% [
			koln_pt.x, koln_pt.y,
			str(koln_inside), str(koln_in_lux), koln_dist,
			str(radius > koln_dist),
			str(mm.call("get_province_owner", KOELN)),
		]
	)
	print("EOA_STAR koln_world=%d koln_pick=%d" % [koln_world, koln_pick])
	print(
		"EOA_STAR wandsworth_point=%.1f,%.1f inside_wan=%s outside_london=%s inside_disk=%s owner=%s london_owner=%s"
		% [
			wan_pt.x, wan_pt.y,
			str(wan_inside), str(not wan_in_london), str(wan_dist <= radius),
			str(mm.call("get_province_owner", WANDSWORTH)),
			str(mm.call("get_province_owner", LONDON)),
		]
	)
	print("EOA_STAR wan_world=%d wan_pick=%d" % [wan_world, wan_pick])
	if zoom <= 0.05 or zoom > 1.15:
		_fail("home_zoom_%.3f" % zoom)
	if lux_cap != LUX:
		_fail("lux_capital_%d" % lux_cap)
	if not koln_inside or koln_in_lux:
		_fail("koln_polygon")
	if radius <= koln_dist:
		_fail("radius_%.2f_le_dist_%.2f" % [radius, koln_dist])
	if koln_world != KOELN or koln_pick != KOELN:
		_fail("koln_resolve_world_%d_pick_%d" % [koln_world, koln_pick])
	if not wan_inside or wan_in_london:
		_fail("wandsworth_polygon")
	if wan_dist > radius:
		_fail("wandsworth_outside_disk_%.2f" % wan_dist)
	if wan_world != LONDON or wan_pick != LONDON:
		_fail("wan_resolve_world_%d_pick_%d" % [wan_world, wan_pick])


func _point_in_province(mm: Node, world_pos: Vector2, pid: int) -> bool:
	if not mm.has_method("_pick_geometry_provider"):
		_fail("no_pick_geometry")
		return false
	var poly: PackedVector2Array = mm.call("_pick_geometry_provider", pid)
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(world_pos, poly)


func _country_capital(mm: Node, tag: String) -> int:
	if not mm.has_method("get_country"):
		return -1
	var c: Variant = mm.call("get_country", tag)
	if c == null:
		return -1
	if c is Dictionary:
		return int((c as Dictionary).get("capital_province_id", -1))
	if c is Object and "capital_province_id" in c:
		return int(c.capital_province_id)
	return -1


func _wait_until_map() -> bool:
	var saw_ready := false
	var ready_at := 0
	while Time.get_ticks_msec() - _t0_msec < WAIT_MAP_MSEC:
		await process_frame
		_dismiss_title_if_needed()
		_force_view()
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed > 0 and elapsed % 20 == 0 and elapsed != _last_wait_log and not saw_ready:
			_last_wait_log = elapsed
			print("EOA_STAR wait_map elapsed=%d n=%d" % [elapsed, _province_count()])
		if not _map_is_ready():
			continue
		if not saw_ready:
			saw_ready = true
			ready_at = Time.get_ticks_msec()
			continue
		if Time.get_ticks_msec() - ready_at >= 1500:
			print("EOA_STAR map_ready n=%d elapsed=%d" % [_province_count(), elapsed])
			return true
	_fail("map_timeout n=%d" % _province_count())
	return false


func _pump(frames: int) -> void:
	var i := 0
	while i < frames:
		await process_frame
		i += 1


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _province_count() < 3000:
		return false
	return _map_renderer() != null and _camera() != null


func _title_has_closed() -> bool:
	# Headless never shows the living title (should_show_living_title). That is
	# the shipped boot, not EOA_SKIP_TITLE. Provinces plus a renderer are enough.
	if DisplayServer.get_name() == "headless" and _province_count() >= 3000 and _map_renderer() != null:
		return true
	var tm := _time_manager()
	if tm != null and tm.has_method("living_title_has_closed"):
		if bool(tm.call("living_title_has_closed")):
			return true
	var scene := current_scene
	if scene != null and bool(scene.get_meta("eoa_living_title_closed", false)):
		return true
	var boot := _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	if boot == null and _province_count() >= 3000:
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed >= 8:
			return true
	return false


func _dismiss_title_if_needed() -> void:
	var boot := _find_named("LivingTitleBoot")
	if boot == null or bool(boot.get("_closed")):
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	if not bool(boot.get("_closed")) and boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")
	var tm := _time_manager()
	if tm != null and tm.has_method("mark_living_title_closed") and bool(boot.get("_closed")):
		tm.call("mark_living_title_closed")


func _pause_clock() -> void:
	var tm := _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)


func _force_view() -> void:
	DisplayServer.window_set_size(VIEW)
	if root != null:
		root.size = VIEW


func _province_count() -> int:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _map_renderer() -> Node:
	var nodes := get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam := mr.get_node_or_null("MapCamera")
		if cam is Camera2D:
			return cam as Camera2D
		var mr_vp := mr.get_viewport()
		if mr_vp != null and mr_vp.get_camera_2d() != null:
			return mr_vp.get_camera_2d()
	if root != null and root.get_viewport() != null:
		return root.get_viewport().get_camera_2d()
	return null


func _map_manager() -> Node:
	if root != null:
		var n := root.get_node_or_null("MapManager")
		if n != null:
			return n
	return _find_named("MapManager")


func _time_manager() -> Node:
	if root != null:
		var n := root.get_node_or_null("TimeManager")
		if n != null:
			return n
	return _find_named("TimeManager")


func _find_named(node_name: String) -> Node:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == node_name:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("EOA_STAR FAIL %s" % msg)


func _finish() -> void:
	var ok := _failures.is_empty()
	print(
		"HeadlessHomeStarSameCountryCheck: RESULT=%s reasons=%s"
		% ["PASS" if ok else "FAIL", str(_failures)]
	)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
