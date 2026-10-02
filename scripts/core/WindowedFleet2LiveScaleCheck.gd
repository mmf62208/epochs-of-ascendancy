extends SceneTree

## FLEET-2 FIX #2 live-scale check on the real world_accurate board.
## xvfb 1280x740 · GER · Europe Home · zoom ~1.5 Channel + North Sea.
## Logs renderer-world cluster centres vs Play centroids and East Kent pick.
## xvfb is NOT live Play. Never EOA_SKIP_TITLE.
##
##   tools/eoa_fleet2_live_scale_check.sh

const CHANNEL := 950001
const NORTH_SEA := 950000
const EAST_KENT := 711453
const LIVE_RENDER_CHANNEL := Vector2(7134.5, 1622.3)
const LIVE_RENDER_NORTH_SEA := Vector2(7195.9, 1336.9)
const LIVE_RENDER_EAST_KENT := Vector2(7119.145, 1620.913)
const LIVE_OLD_ENG_CHIP := Vector2(7134.5, 1610.3)
const TARGET_ZOOM := 1.5
const WAIT_MAP_SECS := 420
const GER_TAG := "GER"

enum Phase { WAIT_MAP, HOME, CHANNEL, NORTH_SEA, EAST_KENT, DONE }

var _phase: int = Phase.WAIT_MAP
var _t0_msec: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _ch_cluster: Vector2 = Vector2.ZERO
var _ns_cluster: Vector2 = Vector2.ZERO
var _ch_plates: Dictionary = {}
var _ns_plates: Dictionary = {}
var _kent_pick: String = ""
var _kent_ok: bool = false


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedFleet2LiveScaleCheck: DisplayServer=%s" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1280, 740))
	var win := DisplayServer.window_get_size()
	_log("EOA_FLEET2_LIVE who=guard.window size=%dx%d (xvfb≠Play)" % [win.x, win.y])
	_out_dir = OS.get_environment("EOA_FLEET2_LIVE_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-fleet2-live"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/fleet2-fix2")
	DirAccess.make_dir_recursive_absolute("res://".replace("res://", ""))
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_log("EOA_FLEET2_LIVE who=guard.boot out=%s (NOT product Play)" % _out_dir)
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
		Phase.CHANNEL:
			_do_channel()
		Phase.NORTH_SEA:
			_do_north_sea()
		Phase.EAST_KENT:
			_do_east_kent()
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
		_log("EOA_FLEET2_LIVE who=guard.wait_map elapsed=%d n=%d" % [elapsed, _province_count()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("fleet2_live_ready_msec", 0)) == 0:
		root.set_meta("fleet2_live_ready_msec", Time.get_ticks_msec())
		return
	if Time.get_ticks_msec() - int(root.get_meta("fleet2_live_ready_msec", 0)) < 1500:
		return
	_log("EOA_FLEET2_LIVE who=guard.frame_start elapsed=%d n=%d" % [elapsed, _province_count()])
	_phase = Phase.HOME


func _do_home() -> void:
	_force_player_ger()
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	elif mr != null and mr.has_method("center_europe_in_world_view"):
		mr.call("center_europe_in_world_view")
	_pause_clock()
	_log("EOA_FLEET2_LIVE who=guard.europe_home ger=%s" % _player_tag())
	_phase = Phase.CHANNEL


func _do_channel() -> void:
	_frame_sea(LIVE_RENDER_CHANNEL, "channel")
	_ch_plates = _collect_sea_plates(CHANNEL)
	_ch_cluster = _cluster_of(_ch_plates)
	_log_plates("Channel 950001", _ch_plates, _ch_cluster, LIVE_RENDER_CHANNEL)
	if _ch_plates.size() < 4:
		_fail_reasons.append("channel_plates_%d" % _ch_plates.size())
	if _ch_cluster.distance_to(LIVE_RENDER_CHANNEL) > 80.0:
		_fail_reasons.append("channel_cluster_off_%.1f" % _ch_cluster.distance_to(LIVE_RENDER_CHANNEL))
	if _ch_cluster.distance_to(Vector2(4128.7, 938.2)) < 80.0:
		_fail_reasons.append("channel_still_unscaled_canada")
	_capture("fleet2_channel_z15")
	_phase = Phase.NORTH_SEA


func _do_north_sea() -> void:
	_frame_sea(LIVE_RENDER_NORTH_SEA, "north_sea")
	_ns_plates = _collect_sea_plates(NORTH_SEA)
	_ns_cluster = _cluster_of(_ns_plates)
	_log_plates("North Sea 950000", _ns_plates, _ns_cluster, LIVE_RENDER_NORTH_SEA)
	if _ns_plates.size() < 4:
		_fail_reasons.append("north_sea_plates_%d" % _ns_plates.size())
	if _ns_cluster.distance_to(LIVE_RENDER_NORTH_SEA) > 80.0:
		_fail_reasons.append("north_sea_cluster_off_%.1f" % _ns_cluster.distance_to(LIVE_RENDER_NORTH_SEA))
	if _ns_cluster.distance_to(Vector2(4164.3, 773.7)) < 80.0:
		_fail_reasons.append("north_sea_still_unscaled_canada")
	_capture("fleet2_north_sea_z15")
	_phase = Phase.EAST_KENT


func _do_east_kent() -> void:
	var mr := _map_renderer()
	if mr == null or not mr.has_method("_pick_unit_formation_at_world"):
		_fail_reasons.append("no_pick")
		_finish(_fail_reasons.is_empty())
		return
	var samples: Array = [
		{"name": "live_east_kent", "pos": LIVE_RENDER_EAST_KENT},
		{"name": "live_old_eng_chip", "pos": LIVE_OLD_ENG_CHIP},
		{"name": "live_channel_centroid", "pos": LIVE_RENDER_CHANNEL},
	]
	var all_ok := true
	for s_v in samples:
		var s: Dictionary = s_v as Dictionary
		var pos: Vector2 = s["pos"] as Vector2
		var fo: Object = mr.call("_pick_unit_formation_at_world", pos)
		var fid := str(fo.formation_id) if fo != null and "formation_id" in fo else "null"
		var tag := str(fo.country_tag).strip_edges().to_upper() if fo != null and "country_tag" in fo else "?"
		var ftype := str(fo.formation_type) if fo != null and "formation_type" in fo else "?"
		_log("EOA_FLEET2_LIVE who=east_kent.pick name=%s world=%.1f,%.1f fid=%s tag=%s type=%s" % [
			str(s["name"]), pos.x, pos.y, fid, tag, ftype
		])
		var ok := fo != null and ftype == "fleet" and tag in ["ENG", "ITA", "POL", "USA"]
		if str(s["name"]) == "live_old_eng_chip":
			_kent_pick = "%s/%s/%s" % [fid, tag, ftype]
			_kent_ok = ok
		if not ok:
			all_ok = false
			_fail_reasons.append("east_kent_%s_got_%s_%s" % [str(s["name"]), tag, ftype])
	if not all_ok:
		_log("EOA_FLEET2_LIVE who=east_kent RESULT=FAIL pick=%s" % _kent_pick)
	else:
		_log("EOA_FLEET2_LIVE who=east_kent RESULT=PASS pick=%s (Channel fleet, not GER Div 6)" % _kent_pick)
	_finish(_fail_reasons.is_empty())


func _frame_sea(world: Vector2, who: String) -> void:
	var mr := _map_renderer()
	var cam := _camera()
	if cam != null:
		cam.global_position = world
	if mr != null and mr.has_method("player_path_wheel_toward_world"):
		var z: float = float(mr.call("player_path_wheel_toward_world", world, TARGET_ZOOM))
		_log("EOA_FLEET2_LIVE who=guard.frame_%s zoom=%.3f cam=%s" % [who, z, str(world)])
	elif cam != null:
		cam.zoom = Vector2(TARGET_ZOOM, TARGET_ZOOM)
		_log("EOA_FLEET2_LIVE who=guard.frame_%s zoom=%.3f (direct)" % [who, TARGET_ZOOM])
	if mr != null and mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint", TARGET_ZOOM)
	if mr != null and mr.has_method("_sync_sea_nation_fleet_offsets"):
		mr.call("_sync_sea_nation_fleet_offsets", TARGET_ZOOM)


func _collect_sea_plates(pid: int) -> Dictionary:
	var out: Dictionary = {}
	var mr := _map_renderer()
	if mr == null:
		return out
	var host: Node2D = null
	if "province_nodes" in mr and mr.province_nodes.has(pid):
		host = mr.province_nodes[pid] as Node2D
	if host == null:
		return out
	for c in host.get_children():
		if not (c is Node2D):
			continue
		if not str(c.name).begins_with("DemoUnitIcon_"):
			continue
		if not bool((c as Node2D).get_meta("sea_nation_disk", false)):
			continue
		var tag := str((c as Node2D).get_meta("sea_nation_tag", ""))
		var pos: Vector2 = (c as Node2D).global_position
		if pos == Vector2.ZERO:
			pos = (c as Node2D).position
		var lab := ""
		var desig: Node = (c as Node2D).get_node_or_null("Designation")
		if desig != null:
			lab = str(desig.get("text"))
		var r: float = 0.0
		if (c as Node2D).has_meta("sea_nation_radius"):
			r = float((c as Node2D).get_meta("sea_nation_radius"))
		out[tag] = {"pos": pos, "label": lab, "r": r, "name": str(c.name)}
	return out


func _cluster_of(plates: Dictionary) -> Vector2:
	if plates.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for k in plates.keys():
		var rec: Dictionary = plates[k] as Dictionary
		acc += rec.get("pos", Vector2.ZERO) as Vector2
	return acc / float(plates.size())


func _log_plates(who: String, plates: Dictionary, cluster: Vector2, live_c: Vector2) -> void:
	_log("EOA_FLEET2_LIVE who=plates sea=%s n=%d cluster=%.1f,%.1f live_centroid=%.1f,%.1f d=%.1f" % [
		who, plates.size(), cluster.x, cluster.y, live_c.x, live_c.y, cluster.distance_to(live_c)
	])
	for k in plates.keys():
		var rec: Dictionary = plates[k] as Dictionary
		var p: Vector2 = rec.get("pos", Vector2.ZERO) as Vector2
		_log("EOA_FLEET2_LIVE who=plate sea=%s tag=%s world=%.1f,%.1f r=%.2f label='%s' name=%s" % [
			who, str(k), p.x, p.y, float(rec.get("r", 0.0)), str(rec.get("label", "")), str(rec.get("name", ""))
		])


func _capture(name: String) -> void:
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		_fail_reasons.append("no_viewport")
		return
	var tex := vp.get_texture()
	if tex == null:
		_fail_reasons.append("no_tex")
		return
	var img := tex.get_image()
	if img == null:
		_fail_reasons.append("no_image")
		return
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	_captures.append(path)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/fleet2-fix2"):
		img.save_png("/opt/cursor/artifacts/fleet2-fix2/%s.png" % name)
	var repo_dir := "docs/evidence/fleet2_fix2"
	DirAccess.make_dir_recursive_absolute(repo_dir)
	img.save_png("%s/%s.png" % [repo_dir, name])
	var cam := _camera()
	var z := 0.0
	var cp := Vector2.ZERO
	if cam != null:
		z = maxf(cam.zoom.x, cam.zoom.y)
		cp = cam.global_position
	_log("EOA_FLEET2_LIVE who=guard.capture file=%s %dx%d zoom=%.3f cam=%.1f,%.1f" % [
		path, img.get_width(), img.get_height(), z, cp.x, cp.y
	])


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


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	if not ok and _fail_reasons.is_empty():
		_fail_reasons.append("unknown")
	var verdict := "PASS" if ok else "FAIL"
	_log("WindowedFleet2LiveScaleCheck: CH cluster %s vs live %s | NS cluster %s vs live %s | East Kent pick=%s" % [
		str(_ch_cluster), str(LIVE_RENDER_CHANNEL), str(_ns_cluster), str(LIVE_RENDER_NORTH_SEA), _kent_pick
	])
	_log("WindowedFleet2LiveScaleCheck: RESULT=%s reasons=%s captures=%d" % [
		verdict, str(_fail_reasons), _captures.size()
	])
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
