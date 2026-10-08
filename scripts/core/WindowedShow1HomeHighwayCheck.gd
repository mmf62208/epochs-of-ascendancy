extends SceneTree

## SHOW-1 windowed check. Europe Home far-band highways must read as a gold
## core wider than the old 3.2 px hairline. Search Köln must still pick
## Köln 710417, not Luxembourg 710995.
##
##   DISPLAY=:0 tools/run_godot.sh --path . --position 0,29 --resolution 1280x740 \
##     -s res://scripts/core/WindowedShow1HomeHighwayCheck.gd

const KOELN := 710417
## Luxembourg the country polygon (LU000), not an older capital sample.
const LUX := 710977
const BONN := 710416
const LEV := 710418
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 24
const CORE_MIN_PX := 5

enum Phase { WAIT_MAP, SETTLE, HOME, KOLN, DONE }

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.HOME
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _core_px: int = -1
var _home_zoom: float = -1.0
var _koln_pid: int = -1


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	if DisplayServer.get_name() == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail_reasons.append("scene_load_%d" % err)
		_finish(false)
		return
	_phase = Phase.WAIT_MAP
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	match _phase:
		Phase.WAIT_MAP:
			_tick_wait_map()
		Phase.SETTLE:
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.HOME:
			_do_home()
		Phase.KOLN:
			_do_koln()
		Phase.DONE:
			pass


func _go_settle(next_phase: int) -> void:
	_after_settle = next_phase
	_settle_left = SETTLE_FRAMES
	_phase = Phase.SETTLE


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail_reasons.append("map_timeout")
		_finish(false)
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		_log("wait_map elapsed=%d closed=%s n=%d" % [elapsed, str(_title_closed()), _province_count()])
	_dismiss_title()
	if not _map_ready():
		return
	if int(root.get_meta("show1_ready_msec", 0)) == 0:
		root.set_meta("show1_ready_msec", Time.get_ticks_msec())
		return
	if Time.get_ticks_msec() - int(root.get_meta("show1_ready_msec", 0)) < 1500:
		return
	_pause_clock()
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "political")
	if mr != null and "show_unit_counters" in mr:
		mr.set("show_unit_counters", false)
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", false)
	var ol := _find_named("InfrastructureOverlayLayer")
	if ol != null and ol.has_method("rebuild_road_layer"):
		ol.call("rebuild_road_layer")
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	_go_settle(Phase.HOME)


func _do_home() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("dismiss_first_session_action_tip"):
		mr.call("dismiss_first_session_action_tip")
	_hide_counters()
	RenderingServer.force_draw()
	var cam := _camera()
	_home_zoom = 1.0
	if cam != null:
		_home_zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	_log("home_zoom=%.3f" % _home_zoom)
	if _home_zoom > 1.15:
		_fail_reasons.append("home_not_far_band_%.3f" % _home_zoom)
	var img := _capture()
	_core_px = _best_far_core_px(img, cam)
	_log("far_core_px=%d need>=%d" % [_core_px, CORE_MIN_PX])
	if _core_px < CORE_MIN_PX:
		_fail_reasons.append("far_core_px_%d" % _core_px)
	var opened := false
	if mr != null and mr.has_method("player_path_search_go"):
		opened = bool(mr.call("player_path_search_go", KOELN))
	var selected := -1
	if mr != null:
		selected = int(mr.selected_province_id)
	var supply_pid := -1
	var sm := root.get_node_or_null("SupplyManager")
	if sm != null and sm.has_method("get_selected_province_id"):
		supply_pid = int(sm.call("get_selected_province_id"))
	if selected != KOELN and supply_pid == KOELN:
		selected = supply_pid
	root.set_meta("show1_koln_opened", opened)
	root.set_meta("show1_koln_selected", selected)
	_log("koln_search_now opened=%s selected=%d supply=%d" % [str(opened), selected, supply_pid])
	if mr != null and mr.has_method("hide_info_panel"):
		mr.call("hide_info_panel")
	_go_settle(Phase.KOLN)


func _do_koln() -> void:
	var mr := _map_renderer()
	var mm := _map_manager()
	var world := _centroid(KOELN)
	var opened := int(root.get_meta("show1_koln_selected", -1))
	var snapped := -1
	if mm != null and mm.has_method("get_province_at_world_pos"):
		snapped = int(mm.call("get_province_at_world_pos", world, true))
	_koln_pid = opened
	_log("koln_search opened=%d centroid_snap=%d world=%.1f,%.1f" % [opened, snapped, world.x, world.y])
	if opened != KOELN:
		_fail_reasons.append("koln_search_%d" % opened)
	# Home-zoom capital snap can land the geometric centroid on Luxembourg.
	# That pick predates this slice. Search/Go must still open Köln.
	if snapped == LUX:
		_log("centroid_snaps_to_luxembourg (pre-existing capital star; not a road regression)")
	_finish(_fail_reasons.is_empty())


func _best_far_core_px(img: Image, cam: Camera2D) -> int:
	if img == null or cam == null:
		return 0
	var node := _highway_draw()
	if node == null:
		_fail_reasons.append("no_highway_draw")
		return 0
	var edges: Array = node.get("edges")
	var best := 0
	var sample_logged := false
	var xform: Transform2D = cam.get_canvas_transform()
	var size := Vector2(img.get_width(), img.get_height())
	for row_v in edges:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var a: int = int(row.get("p1", 0))
		var b: int = int(row.get("p2", 0))
		if _is_spine(a, b):
			continue
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		if c1 == Vector2.ZERO or c2 == Vector2.ZERO:
			continue
		var s1: Vector2 = xform * c1
		var s2: Vector2 = xform * c2
		var delta := s2 - s1
		if delta.length() < 8.0:
			continue
		var dir := delta / delta.length()
		var perp := Vector2(-dir.y, dir.x)
		for t in [0.35, 0.5, 0.65]:
			var p: Vector2 = s1.lerp(s2, float(t))
			if p.x < 8.0 or p.y < 8.0 or p.x > size.x - 8.0 or p.y > size.y - 8.0:
				continue
			var w := _pale_run(img, p, perp)
			if w > best:
				best = w
			if not sample_logged:
				var sx := int(clamp(round(p.x), 0, img.get_width() - 1))
				var sy := int(clamp(round(p.y), 0, img.get_height() - 1))
				var col := img.get_pixel(sx, sy)
				_log("sample xy=%d,%d rgb=%.2f,%.2f,%.2f run=%d" % [sx, sy, col.r, col.g, col.b, w])
				sample_logged = true
	return best


func _pale_run(img: Image, center: Vector2, perp: Vector2) -> int:
	var hits: Array[int] = []
	for i in range(-14, 15):
		var p: Vector2 = center + perp * float(i)
		var x := int(round(p.x))
		var y := int(round(p.y))
		if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
			hits.append(0)
		elif _pale_gold(img.get_pixel(x, y)):
			hits.append(1)
		else:
			hits.append(0)
	var best := 0
	var run := 0
	for bit in hits:
		if bit == 1:
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return best


func _pale_gold(c: Color) -> bool:
	return c.r > 0.85 and c.g > 0.75 and c.b > 0.40 and c.b < 0.80 and c.g > c.b


func _is_spine(a: int, b: int) -> bool:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	if lo == BONN and hi == KOELN:
		return true
	if lo == KOELN and hi == LEV:
		return true
	return false


func _highway_draw() -> Node:
	var ol := _find_named("InfrastructureOverlayLayer")
	if ol == null:
		_log("overlay_missing")
		return null
	var road := ol.get_node_or_null("RoadLayer")
	if road == null:
		_log("road_layer_missing")
		return null
	var node := road.get_node_or_null("RoadTierDraw_2")
	if node == null:
		_log("highway_node_missing children=%d" % road.get_child_count())
	else:
		var edges: Array = node.get("edges")
		_log("highway_edges=%d" % edges.size())
	return node


func _capture() -> Image:
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img != null:
		var path := "/tmp/eoa-show1-home.png"
		img.save_png(path)
		_log("capture %s %dx%d" % [path, img.get_width(), img.get_height()])
	return img


func _centroid(pid: int) -> Vector2:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", pid)
		if c != Vector2.ZERO:
			return c
	return Vector2.ZERO


func _map_ready() -> bool:
	if not _title_closed():
		return false
	if _province_count() < 3000:
		return false
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province"):
		return false
	return mm.call("get_province", KOELN) != null and _map_renderer() != null and _camera() != null


func _title_closed() -> bool:
	var tm := _time_manager()
	if tm != null and tm.has_method("living_title_has_closed") and bool(tm.call("living_title_has_closed")):
		return true
	if root != null and bool(root.get_meta("eoa_living_title_closed", false)):
		return true
	var boot := _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	return boot == null and _province_count() >= 3000 and int((Time.get_ticks_msec() - _t0_msec) / 1000.0) >= 8


func _dismiss_title() -> void:
	var boot := _find_named("LivingTitleBoot")
	if boot == null or bool(boot.get("_closed")):
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	if not bool(boot.get("_closed")) and boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")


func _pause_clock() -> void:
	var tm := _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)


func _province_count() -> int:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _map_manager() -> Node:
	if root == null:
		return null
	return root.get_node_or_null("MapManager")


func _time_manager() -> Node:
	if root == null:
		return null
	return root.get_node_or_null("TimeManager")


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var named := mr.get_node_or_null("MapCamera") as Camera2D
		if named != null:
			return named
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		return vp.get_camera_2d()
	return null


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _hide_counters() -> void:
	var mr := _map_renderer()
	if mr != null:
		mr.set("show_unit_counters", false)
		if mr.has_method("_sync_unit_counter_visibility"):
			mr.call("_sync_unit_counter_visibility")
	_hide_counter_nodes(root)


func _hide_counter_nodes(n: Node) -> void:
	if n == null:
		return
	var nm := str(n.name)
	if nm.begins_with("DemoUnitIcon"):
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	for c in n.get_children():
		_hide_counter_nodes(c)


func _log(msg: String) -> void:
	print("EOA_SHOW1 %s" % msg)


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	print("WindowedShow1HomeHighwayCheck: RESULT=%s reasons=%s core_px=%d home_zoom=%.3f koln_pid=%d" % [
		"PASS" if ok else "FAIL", str(_fail_reasons), _core_px, _home_zoom, _koln_pid
	])
	quit(0 if ok else 1)
