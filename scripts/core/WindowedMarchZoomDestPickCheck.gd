extends SceneTree

## Windowed 1280×740 march dest pick at z 0.32 / 0.80 / 1.50.
## Fresh Heidekreis interior screen → dest 710380. Also logs stale z=1.50
## screen reused at lower zooms on the Europe Home camera.
## xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
##
##   tools/eoa_march_zoom_pick_windowed_check.sh

const VIEW_W := 1280
const VIEW_H := 740
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 24
const GER_TAG := "GER"
const HEIDE := 710380
const BORDE := 710515
const HARZ := 710517
const ZOOMS: Array[float] = [0.32, 0.80, 1.50]
const REPO_DIR := "docs/evidence/march_zoom_pick"

enum Phase {
	WAIT_MAP,
	HOME,
	SETTLE,
	PICKS,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _t0_msec: int = 0
var _settle_left: int = 0
var _after_settle: int = Phase.HOME
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _last_wait_log: int = -1
var _home_zoom: float = 0.4
var _home_cam: Vector2 = Vector2.ZERO
var _fid: String = ""
var _rows: PackedStringArray = PackedStringArray()
var _fresh_ok: int = 0
var _fresh_n: int = 0


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedMarchZoomDestPickCheck: DisplayServer=%s" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	_force_viewport()
	_out_dir = OS.get_environment("EOA_MARCH_ZOOM_LIVE_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-march-zoom-live"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/march_zoom_pick")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_log("EOA_MARCH_ZOOM_LIVE who=guard.boot out=%s view=%dx%d (NOT product Play)" % [_out_dir, VIEW_W, VIEW_H])
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
		Phase.HOME:
			_do_home()
		Phase.SETTLE:
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.PICKS:
			_do_picks()
		Phase.DONE:
			pass


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail_reasons.append("map_timeout")
		_finish(false)
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		_log("EOA_MARCH_ZOOM_LIVE who=guard.wait_map elapsed=%d n=%d" % [elapsed, _province_count()])
	_dismiss_title_if_needed()
	_force_viewport()
	if not _map_is_ready():
		return
	if int(root.get_meta("march_zoom_live_ready_msec", 0)) == 0:
		root.set_meta("march_zoom_live_ready_msec", Time.get_ticks_msec())
		return
	if Time.get_ticks_msec() - int(root.get_meta("march_zoom_live_ready_msec", 0)) < 1500:
		return
	_log("EOA_MARCH_ZOOM_LIVE who=guard.frame_start elapsed=%d n=%d" % [elapsed, _province_count()])
	_phase = Phase.HOME


func _do_home() -> void:
	_force_viewport()
	_force_player_ger()
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	elif mr != null and mr.has_method("center_europe_in_world_view"):
		mr.call("center_europe_in_world_view")
	_pause_clock()
	var cam := _camera()
	if cam != null:
		_home_zoom = maxf(cam.zoom.x, cam.zoom.y)
		_home_cam = cam.global_position
	_fid = _pick_ger_land_fid()
	_log(
		"EOA_MARCH_ZOOM_LIVE who=guard.europe_home ger=%s zoom=%.3f cam=%.1f,%.1f fid=%s"
		% [_player_tag(), _home_zoom, _home_cam.x, _home_cam.y, _fid]
	)
	if _fid.is_empty():
		_fail_reasons.append("no_ger_land_formation")
		_finish(false)
		return
	_go_settle(Phase.PICKS)


func _do_picks() -> void:
	var mr := _map_renderer()
	if mr == null or not mr.has_method("_screen_to_world") or not mr.has_method("_mv1_event_province_pid"):
		_fail_reasons.append("map_renderer_pick_api")
		_finish(false)
		return
	var heide_w: Vector2 = _interior_world(HEIDE)
	if heide_w == Vector2.ZERO:
		_fail_reasons.append("heidekreis_centroid_missing")
		_finish(false)
		return
	var gis_hit := _gis(heide_w)
	_log("EOA_MARCH_ZOOM_LIVE who=gis interior=%.2f,%.2f hit=%d %s" % [heide_w.x, heide_w.y, gis_hit, _pname(gis_hit)])
	if gis_hit != HEIDE:
		_fail_reasons.append("gis_interior_hit_%d" % gis_hit)
	_select_unit()
	for z in ZOOMS:
		_set_zoom_on(heide_w, z)
		var screen: Vector2 = _world_to_screen(heide_w)
		var back: Vector2 = mr.call("_screen_to_world", screen) as Vector2
		var dest: int = int(mr.call("_mv1_event_province_pid", back))
		_fresh_n += 1
		var ok := dest == HEIDE and _screen_in_view(screen)
		if ok:
			_fresh_ok += 1
			_commit_if_possible(dest)
		else:
			_fail_reasons.append("fresh_z%.2f_dest_%d_%s" % [z, dest, _pname(dest)])
		var row := (
			"| fresh | z=%.2f | screen=%.1f,%.1f | world=%.2f,%.2f | dest=%d %s | %s |"
			% [z, screen.x, screen.y, back.x, back.y, dest, _pname(dest), "PASS" if ok else "FAIL"]
		)
		_rows.append(row)
		_log("EOA_MARCH_ZOOM_LIVE who=fresh %s" % row)
	_log_stale_home(heide_w)
	_write_clicks()
	if _fresh_ok != _fresh_n or _fresh_n < ZOOMS.size():
		_fail_reasons.append("fresh %d/%d" % [_fresh_ok, _fresh_n])
	_finish(_fail_reasons.is_empty())


func _log_stale_home(heide_w: Vector2) -> void:
	var cam := _camera()
	if cam == null:
		return
	cam.global_position = _home_cam
	cam.zoom = Vector2(1.50, 1.50)
	var stale_screen: Vector2 = _world_to_screen(heide_w)
	var dest_15 := _pick_screen(stale_screen)
	_rows.append(
		"| stale_src | z=1.50 cam=Home | screen=%.1f,%.1f | dest=%d %s |"
		% [stale_screen.x, stale_screen.y, dest_15, _pname(dest_15)]
	)
	_log(
		"EOA_MARCH_ZOOM_LIVE who=stale_src z=1.50 screen=%.1f,%.1f dest=%d %s"
		% [stale_screen.x, stale_screen.y, dest_15, _pname(dest_15)]
	)
	for z in [0.80, 0.32]:
		cam.global_position = _home_cam
		cam.zoom = Vector2(z, z)
		var stale_dest := _pick_screen(stale_screen)
		var fresh_screen: Vector2 = _world_to_screen(heide_w)
		var fresh_dest := _pick_screen(fresh_screen)
		_rows.append(
			"| stale_reuse | z=%.2f cam=Home | stale_dest=%d %s | fresh_dest=%d %s |"
			% [z, stale_dest, _pname(stale_dest), fresh_dest, _pname(fresh_dest)]
		)
		_log(
			"EOA_MARCH_ZOOM_LIVE who=stale_reuse z=%.2f stale=%d %s fresh=%d %s Harz=%d Börde=%d"
			% [z, stale_dest, _pname(stale_dest), fresh_dest, _pname(fresh_dest), HARZ, BORDE]
		)
		if fresh_dest != HEIDE and _screen_in_view(fresh_screen):
			_fail_reasons.append("home_fresh_z%.2f_dest_%d" % [z, fresh_dest])


func _commit_if_possible(dest: int) -> void:
	if _fid.is_empty():
		return
	var mv: Script = load("res://scripts/formations/FormationMovement.gd") as Script
	if mv == null:
		return
	var inst: Object = mv.new()
	if inst == null:
		return
	if inst.has_method("clear_march"):
		inst.call("clear_march", _fid)
	var commit: Dictionary = inst.call("enqueue_own_land_march", _fid, dest, GER_TAG)
	_log(
		"EOA_MARCH_ZOOM_LIVE who=move_commit fid=%s dest=%d %s ok=%s hops=%s days=%s"
		% [
			_fid, dest, _pname(dest), str(bool(commit.get("ok", false))),
			str(commit.get("hops", "?")), str(commit.get("calendar_days", "?")),
		]
	)


func _select_unit() -> void:
	var mr := _map_renderer()
	var lm := _leader_manager()
	if mr == null or lm == null or _fid.is_empty():
		return
	var fo: Object = null
	if lm.has_method("get_formation"):
		fo = lm.call("get_formation", _fid)
	if fo == null and "formations" in lm:
		fo = lm.formations.get(_fid)
	if fo == null:
		return
	if mr.has_method("_select_map_unit"):
		mr.call("_select_map_unit", fo)
	elif "selected_formation_id" in mr:
		mr.selected_formation_id = _fid


func _pick_screen(screen: Vector2) -> int:
	var mr := _map_renderer()
	if mr == null:
		return -1
	var world: Vector2 = mr.call("_screen_to_world", screen) as Vector2
	return int(mr.call("_mv1_event_province_pid", world))


func _set_zoom_on(world: Vector2, z: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	cam.global_position = world
	cam.zoom = Vector2(z, z)
	var mr := _map_renderer()
	if mr != null and mr.has_method("_sync_unit_counter_visibility"):
		mr.call("_sync_unit_counter_visibility", z)


func _world_to_screen(world: Vector2) -> Vector2:
	var cam := _camera()
	if cam != null:
		return cam.get_canvas_transform() * world
	return world


func _screen_in_view(screen: Vector2) -> bool:
	return screen.x >= 8.0 and screen.y >= 8.0 and screen.x <= float(VIEW_W) - 8.0 and screen.y <= float(VIEW_H) - 8.0


func _interior_world(pid: int) -> Vector2:
	var mr := _map_renderer()
	if mr != null and "province_centroids" in mr:
		var cents: Dictionary = mr.province_centroids
		if cents.has(pid):
			var c: Vector2 = cents[pid] as Vector2
			if c != Vector2.ZERO:
				return c
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_centroid"):
		return mm.call("get_province_centroid", pid) as Vector2
	return Vector2.ZERO


func _gis(world: Vector2) -> int:
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province_at_world_pos"):
		return -1
	var hit := int(mm.call("get_province_at_world_pos", world, true))
	if mm.has_method("resolve_pick_province_id"):
		hit = int(mm.call("resolve_pick_province_id", hit))
	return hit


func _pname(pid: int) -> String:
	var mm := _map_manager()
	if pid <= 0 or mm == null or not mm.has_method("get_province"):
		return "?"
	var p: Variant = mm.call("get_province", pid)
	if p == null:
		return str(pid)
	return str(p.get("name"))


func _pick_ger_land_fid() -> String:
	var lm := _leader_manager()
	if lm == null:
		return ""
	if lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", GER_TAG)
	var garrison := ""
	var any_land := ""
	if "formations" in lm:
		for fid_v in lm.formations.keys():
			var f: Object = lm.formations[fid_v]
			if f == null:
				continue
			var tag := str(f.get("country_tag")).strip_edges().to_upper()
			var ft := str(f.get("formation_type")) if "formation_type" in f else ""
			if tag != GER_TAG:
				continue
			if ft != "" and ft != "division":
				continue
			var name_s := str(f.get("name")) if "name" in f else ""
			var fid_s := str(fid_v)
			if any_land.is_empty():
				any_land = fid_s
			if "garrison 4" in name_s.to_lower() or fid_s.ends_with("_formation_4"):
				garrison = fid_s
	if not garrison.is_empty():
		return garrison
	return any_land


func _write_clicks() -> void:
	var md := "# March zoom dest pick windowed xvfb 1280x740\n\n"
	md += "GER · world_accurate. NOT live Play.\n\n"
	md += "fresh %d/%d (Heidekreis 710380 at z 0.32 / 0.80 / 1.50)\n\n" % [_fresh_ok, _fresh_n]
	md += "| kind | zoom | detail |\n"
	md += "|---|---|---|\n"
	for row in _rows:
		md += "%s\n" % row
	var path := "%s/CLICKS.md" % _out_dir
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	DirAccess.make_dir_recursive_absolute(REPO_DIR)
	var ev := FileAccess.open("%s/CLICKS.md" % REPO_DIR, FileAccess.WRITE)
	if ev != null:
		ev.store_string(md)
		ev.close()
	_log("EOA_MARCH_ZOOM_LIVE who=clicks fresh=%d/%d" % [_fresh_ok, _fresh_n])


func _go_settle(next_phase: int) -> void:
	_after_settle = next_phase
	_settle_left = SETTLE_FRAMES
	_phase = Phase.SETTLE


func _force_viewport() -> void:
	var want := Vector2i(VIEW_W, VIEW_H)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(want)
	if root is Window:
		var w: Window = root as Window
		w.size = want
		w.min_size = want
		w.max_size = want
		w.content_scale_size = want
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.size = want


func _force_player_ger() -> void:
	var lm := _leader_manager()
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", GER_TAG)


func _player_tag() -> String:
	var lm := _leader_manager()
	if lm != null and lm.has_method("get_player_country_tag"):
		return str(lm.call("get_player_country_tag"))
	return "?"


func _pause_clock() -> void:
	var tm := _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	elif tm != null and "paused" in tm:
		tm.set("paused", true)


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _province_count() < 3000:
		return false
	return _map_renderer() != null and _camera() != null


func _title_has_closed() -> bool:
	var tm := _time_manager()
	if tm != null and tm.has_method("living_title_has_closed"):
		if bool(tm.call("living_title_has_closed")):
			return true
	var scene := current_scene
	if scene != null and bool(scene.get_meta("eoa_living_title_closed", false)):
		return true
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	if boot == null and _province_count() >= 3000:
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed >= 8:
			return true
	return false


func _dismiss_title_if_needed() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if bool(boot.get("_closed")):
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	if not bool(boot.get("_closed")) and boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")
	var tm: Node = _time_manager()
	if tm != null and tm.has_method("mark_living_title_closed") and bool(boot.get("_closed")):
		tm.call("mark_living_title_closed")


func _province_count() -> int:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam: Node = mr.get_node_or_null("MapCamera")
		if cam is Camera2D:
			return cam as Camera2D
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		return vp.get_camera_2d()
	return null


func _map_manager() -> Node:
	if root != null:
		var n: Node = root.get_node_or_null("MapManager")
		if n != null:
			return n
	return _find_named("MapManager")


func _leader_manager() -> Node:
	if root != null:
		var n: Node = root.get_node_or_null("LeaderManager")
		if n != null:
			return n
	return _find_named("LeaderManager")


func _time_manager() -> Node:
	if root != null:
		var n: Node = root.get_node_or_null("TimeManager")
		if n != null:
			return n
	return _find_named("TimeManager")


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	if not ok:
		for r in _fail_reasons:
			print("  [FAIL] WindowedMarchZoomDestPickCheck: ", r)
	print("WindowedMarchZoomDestPickCheck: fresh=%d/%d" % [_fresh_ok, _fresh_n])
	print("WindowedMarchZoomDestPickCheck: ", "PASS" if ok else "FAIL", " (failures=", _fail_reasons.size(), ")")
	print("WindowedMarchZoomDestPickCheck: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
