extends SceneTree

## FLEET-2 FIX #2b live-scale check on the real world_accurate board.
## xvfb exactly 1280x740 · GER · Europe Home · Channel + North Sea at Home zoom
## and ~1.5. Pixel-assert each plate centre. Click all 8 plates + East Kent.
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
const VIEW_W := 1280
const VIEW_H := 740
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 36
const GER_TAG := "GER"
const REPO_DIR := "docs/evidence/fleet2_fix2b"

enum Phase {
	WAIT_MAP,
	HOME,
	SETTLE,
	CHANNEL_HOME,
	CHANNEL_Z15,
	NORTH_HOME,
	NORTH_Z15,
	CLICKS,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _t0_msec: int = 0
var _settle_left: int = 0
var _after_settle: int = Phase.HOME
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _home_zoom: float = 0.4
var _ch_cluster: Vector2 = Vector2.ZERO
var _ns_cluster: Vector2 = Vector2.ZERO
var _ch_plates: Dictionary = {}
var _ns_plates: Dictionary = {}
var _kent_pick: String = ""
var _click_log: PackedStringArray = PackedStringArray()


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
	_force_viewport()
	_out_dir = OS.get_environment("EOA_FLEET2_LIVE_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-fleet2-live"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/fleet2-fix2b")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_log("EOA_FLEET2_LIVE who=guard.boot out=%s view=%dx%d (NOT product Play)" % [_out_dir, VIEW_W, VIEW_H])
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
		Phase.CHANNEL_HOME:
			_do_sea_frame(CHANNEL, LIVE_RENDER_CHANNEL, _home_zoom, "channel", "home", true)
		Phase.CHANNEL_Z15:
			_do_sea_frame(CHANNEL, LIVE_RENDER_CHANNEL, TARGET_ZOOM, "channel", "z15", false)
		Phase.NORTH_HOME:
			_do_sea_frame(NORTH_SEA, LIVE_RENDER_NORTH_SEA, _home_zoom, "north_sea", "home", true)
		Phase.NORTH_Z15:
			_do_sea_frame(NORTH_SEA, LIVE_RENDER_NORTH_SEA, TARGET_ZOOM, "north_sea", "z15", false)
		Phase.CLICKS:
			_do_clicks()
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
	_force_viewport()
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
	_force_viewport()
	_force_player_ger()
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	elif mr != null and mr.has_method("center_europe_in_world_view"):
		mr.call("center_europe_in_world_view")
	_pause_clock()
	_ensure_fleet_icons(-1.0)
	var cam := _camera()
	if cam != null:
		_home_zoom = maxf(cam.zoom.x, cam.zoom.y)
	_log("EOA_FLEET2_LIVE who=guard.europe_home ger=%s zoom=%.3f" % [_player_tag(), _home_zoom])
	if _home_zoom < 0.18 or _home_zoom > 1.2:
		_fail_reasons.append("home_zoom_%.3f" % _home_zoom)
	_go_settle(Phase.CHANNEL_HOME)


func _do_sea_frame(pid: int, live_c: Vector2, zoom: float, sea_key: String, band: String, first: bool) -> void:
	_force_viewport()
	var settle_key := "fleet2_%s_%s_settle" % [sea_key, band]
	var settled: bool = int(root.get_meta(settle_key, 0)) == 1
	# Rebuild only on the first visit. A same-frame rebuild+capture paints empty
	# water (nodes exist for pick/log, canvas items have not drawn yet).
	if not settled:
		_ensure_fleet_icons(zoom)
	else:
		_paint_fleet_icons(zoom)
	var plates: Dictionary = _collect_sea_plates(pid)
	var cluster: Vector2 = _cluster_of(plates)
	if cluster == Vector2.ZERO:
		cluster = live_c
	_frame_sea_direct(cluster, zoom, "%s_%s" % [sea_key, band])
	if not settled:
		root.set_meta(settle_key, 1)
		_go_settle(_phase)
		return
	plates = _collect_sea_plates(pid)
	cluster = _cluster_of(plates)
	if pid == CHANNEL:
		_ch_plates = plates
		_ch_cluster = cluster
	else:
		_ns_plates = plates
		_ns_cluster = cluster
	_log_plates("%s %d %s" % [sea_key, pid, band], plates, cluster, live_c)
	if plates.size() < 4:
		_fail_reasons.append("%s_%s_plates_%d" % [sea_key, band, plates.size()])
	if cluster.distance_to(live_c) > 80.0:
		_fail_reasons.append("%s_%s_cluster_off_%.1f" % [sea_key, band, cluster.distance_to(live_c)])
	if cluster.distance_to(Vector2(4128.7, 938.2)) < 80.0 or cluster.distance_to(Vector2(4164.3, 773.7)) < 80.0:
		_fail_reasons.append("%s_%s_still_unscaled_canada" % [sea_key, band])
	var cap_name := "fleet2_%s_%s" % [sea_key, band]
	if not _capture(cap_name, zoom, cluster):
		_fail_reasons.append("%s_capture" % cap_name)
	else:
		_pixel_assert_plates(cap_name, plates, zoom)
	if first:
		if sea_key == "channel":
			_phase = Phase.CHANNEL_Z15
		else:
			_phase = Phase.NORTH_Z15
	elif sea_key == "channel":
		_phase = Phase.NORTH_HOME
	else:
		_phase = Phase.CLICKS


func _do_clicks() -> void:
	var rows: Array = []
	for k in _ch_plates.keys():
		var rec: Dictionary = _ch_plates[k] as Dictionary
		rows.append({
			"who": "CH_%s" % str(k),
			"pos": rec.get("pos", Vector2.ZERO) as Vector2,
			"own": false,
			"want_tags": ["ENG", "ITA", "POL", "USA"],
		})
	for k2 in _ns_plates.keys():
		var rec2: Dictionary = _ns_plates[k2] as Dictionary
		var tag := str(k2)
		rows.append({
			"who": "NS_%s" % tag,
			"pos": rec2.get("pos", Vector2.ZERO) as Vector2,
			"own": tag == GER_TAG,
			"want_tags": ["GER", "FRA", "JAP", "SOV"],
		})
	rows.append({
		"who": "east_kent_711453",
		"pos": LIVE_RENDER_EAST_KENT,
		"own": false,
		"want_tags": ["ENG", "ITA", "POL", "USA"],
	})
	rows.append({
		"who": "old_eng_chip",
		"pos": LIVE_OLD_ENG_CHIP,
		"own": false,
		"want_tags": ["ENG", "ITA", "POL", "USA"],
	})
	for row_v in rows:
		var row: Dictionary = row_v as Dictionary
		_click_one(row)
	_finish(_fail_reasons.is_empty())


func _click_one(row: Dictionary) -> void:
	var mr := _map_renderer()
	var who := str(row.get("who", "?"))
	var pos: Vector2 = row.get("pos", Vector2.ZERO) as Vector2
	var own: bool = bool(row.get("own", false))
	var want: Array = row.get("want_tags", []) as Array
	if mr == null:
		_fail_reasons.append("click_%s_no_mr" % who)
		return
	_reset_card()
	var fo: Object = null
	if mr.has_method("_pick_unit_formation_at_world"):
		fo = mr.call("_pick_unit_formation_at_world", pos)
	var fid := str(fo.formation_id) if fo != null and "formation_id" in fo else "null"
	var tag := str(fo.country_tag).strip_edges().to_upper() if fo != null and "country_tag" in fo else "?"
	var ftype := str(fo.formation_type) if fo != null and "formation_type" in fo else "?"
	var opened := false
	if mr.has_method("_try_open_unit_at_world"):
		opened = bool(mr.call("_try_open_unit_at_world", pos))
	if not opened and mr.has_method("_try_open_land_unit_at_world"):
		opened = bool(mr.call("_try_open_land_unit_at_world", pos, false, false))
	var card := _popup_state()
	var ok := fo != null and ftype == "fleet" and tag in want
	if who == "east_kent_711453" or who == "old_eng_chip":
		ok = ok and tag != GER_TAG and fid.find("Div") < 0
	if own:
		ok = ok and card["open_fight"] and card["assign"]
	else:
		ok = ok and opened and not card["open_fight"] and not card["assign"]
	var line := (
		"EOA_FLEET2_LIVE who=click name=%s world=%.1f,%.1f fid=%s tag=%s type=%s opened=%s own_card=%s fight=%s assign=%s ok=%s"
		% [who, pos.x, pos.y, fid, tag, ftype, str(opened), str(own), str(card["open_fight"]), str(card["assign"]), str(ok)]
	)
	_log(line)
	_click_log.append(line)
	if who == "old_eng_chip":
		_kent_pick = "%s/%s/%s" % [fid, tag, ftype]
	if not ok:
		_fail_reasons.append("click_%s_got_%s_%s" % [who, tag, ftype])


func _go_settle(next_phase: int) -> void:
	_after_settle = next_phase
	_settle_left = SETTLE_FRAMES
	_phase = Phase.SETTLE


func _paint_fleet_icons(z: float) -> void:
	var mr := _map_renderer()
	if mr == null:
		return
	if "show_unit_counters" in mr:
		mr.show_unit_counters = true
	var zz: float = z
	if zz < 0.0:
		var cam := _camera()
		zz = maxf(cam.zoom.x, cam.zoom.y) if cam != null else 1.0
	if mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint", zz)
	if mr.has_method("_sync_sea_nation_fleet_offsets"):
		mr.call("_sync_sea_nation_fleet_offsets", zz)


func _ensure_fleet_icons(z: float) -> void:
	var mr := _map_renderer()
	if mr == null:
		return
	if "show_unit_counters" in mr:
		mr.show_unit_counters = true
	if mr.has_method("ensure_playable_front_chips"):
		mr.call("ensure_playable_front_chips", false)
	if mr.has_method("_update_unit_icons_for_test"):
		mr.call("_update_unit_icons_for_test")
	elif mr.has_method("_rebuild_demo_unit_icons"):
		mr.call("_rebuild_demo_unit_icons", {})
	_paint_fleet_icons(z)
	var n := 0
	if "_demo_unit_icon_pids" in mr:
		n = (mr._demo_unit_icon_pids as Array).size()
	_log("EOA_FLEET2_LIVE who=guard.icons pids=%d z=%.3f" % [n, z])


func _frame_sea_direct(world: Vector2, zoom: float, who: String) -> void:
	# Direct cam set — wheel-toward-mouse drifted the Channel frame onto England.
	_force_viewport()
	var cam := _camera()
	if cam != null:
		cam.global_position = world
		cam.zoom = Vector2(zoom, zoom)
		cam.make_current()
	var mr := _map_renderer()
	if mr != null and mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint", zoom)
	if mr != null and mr.has_method("_sync_sea_nation_fleet_offsets"):
		mr.call("_sync_sea_nation_fleet_offsets", zoom)
	_log("EOA_FLEET2_LIVE who=guard.frame_%s zoom=%.3f cam=%.1f,%.1f (direct)" % [who, zoom, world.x, world.y])


func _collect_sea_plates(pid: int) -> Dictionary:
	var out: Dictionary = {}
	var mr := _map_renderer()
	if mr != null and mr.has_method("_iter_demo_unit_icons_at_pid"):
		var icons: Array = mr.call("_iter_demo_unit_icons_at_pid", pid) as Array
		for ic_v in icons:
			var icon: Node2D = ic_v as Node2D
			if icon == null:
				continue
			_record_plate(icon, pid, out)
		if not out.is_empty():
			return out
	var prefix := "DemoUnitIcon_%d_" % pid
	if mr != null:
		_collect_sea_plates_walk(mr, prefix, pid, out)
	if out.is_empty() and root != null:
		_collect_sea_plates_walk(root, prefix, pid, out)
	return out


func _record_plate(icon: Node2D, pid: int, out: Dictionary) -> void:
	var tag := str(icon.get_meta("sea_nation_tag", ""))
	if tag.is_empty():
		var bits: PackedStringArray = str(icon.name).split("_")
		if bits.size() >= 3:
			tag = str(bits[bits.size() - 1])
	if tag.is_empty():
		return
	var pos: Vector2 = icon.global_position
	if pos == Vector2.ZERO:
		pos = icon.position
	var mr := _map_renderer()
	if mr != null and mr.has_method("_demo_unit_icon_world_pos"):
		pos = mr.call("_demo_unit_icon_world_pos", icon, pid) as Vector2
	var lab := ""
	var desig: Node = icon.get_node_or_null("Designation")
	if desig != null:
		lab = str(desig.get("text")).replace("\n", " ")
	var r: float = 0.0
	if icon.has_meta("sea_nation_radius"):
		r = float(icon.get_meta("sea_nation_radius"))
	var hit: float = r
	if mr != null and mr.has_method("_demo_unit_icon_hit_radius_world"):
		hit = float(mr.call("_demo_unit_icon_hit_radius_world", 1.0, icon))
	out[tag] = {
		"pos": pos,
		"label": lab,
		"r": r,
		"hit": hit,
		"scale": maxf(icon.scale.x, icon.scale.y),
		"visible": icon.visible,
		"parent": str(icon.get_parent().name) if icon.get_parent() != null else "?",
		"name": str(icon.name),
	}


func _collect_sea_plates_walk(n: Node, prefix: String, pid: int, out: Dictionary) -> void:
	if n == null:
		return
	if n is Node2D and str(n.name).begins_with(prefix):
		_record_plate(n as Node2D, pid, out)
	for c in n.get_children():
		_collect_sea_plates_walk(c, prefix, pid, out)


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
		_log(
			"EOA_FLEET2_LIVE who=plate sea=%s tag=%s world=%.1f,%.1f r=%.2f hit=%.2f scale=%.3f vis=%s parent=%s label='%s' name=%s"
			% [
				who, str(k), p.x, p.y, float(rec.get("r", 0.0)), float(rec.get("hit", 0.0)),
				float(rec.get("scale", 0.0)), str(rec.get("visible", false)),
				str(rec.get("parent", "")), str(rec.get("label", "")), str(rec.get("name", "")),
			]
		)


func _world_to_screen(world: Vector2) -> Vector2:
	var cam := _camera()
	if cam != null:
		return cam.get_canvas_transform() * world
	return world


func _capture(name: String, zoom: float, cam_world: Vector2) -> bool:
	_force_viewport()
	var cam := _camera()
	if cam != null:
		cam.global_position = cam_world
		cam.zoom = Vector2(zoom, zoom)
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		_fail_reasons.append("no_viewport")
		return false
	var tex := vp.get_texture()
	if tex == null:
		_fail_reasons.append("no_tex")
		return false
	var img := tex.get_image()
	if img == null:
		_fail_reasons.append("no_image")
		return false
	if img.get_width() != VIEW_W or img.get_height() != VIEW_H:
		_fail_reasons.append("%s_size_%dx%d_want_%dx%d" % [name, img.get_width(), img.get_height(), VIEW_W, VIEW_H])
		_log("EOA_FLEET2_LIVE who=guard.capture_size_fail file=%s %dx%d" % [name, img.get_width(), img.get_height()])
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	_captures.append(path)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/fleet2-fix2b"):
		img.save_png("/opt/cursor/artifacts/fleet2-fix2b/%s.png" % name)
	DirAccess.make_dir_recursive_absolute(REPO_DIR)
	img.save_png("%s/%s.png" % [REPO_DIR, name])
	var z := 0.0
	var cp := Vector2.ZERO
	if cam != null:
		z = maxf(cam.zoom.x, cam.zoom.y)
		cp = cam.global_position
	_log("EOA_FLEET2_LIVE who=guard.capture file=%s %dx%d zoom=%.3f cam=%.1f,%.1f" % [
		path, img.get_width(), img.get_height(), z, cp.x, cp.y
	])
	root.set_meta("fleet2_last_img_path", path)
	return img.get_width() == VIEW_W and img.get_height() == VIEW_H


func _pixel_assert_plates(cap_name: String, plates: Dictionary, zoom: float) -> void:
	var path := str(root.get_meta("fleet2_last_img_path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		_fail_reasons.append("%s_pixel_no_img" % cap_name)
		return
	var img := Image.new()
	if img.load(path) != OK:
		_fail_reasons.append("%s_pixel_load" % cap_name)
		return
	for k in plates.keys():
		var rec: Dictionary = plates[k] as Dictionary
		var world: Vector2 = rec.get("pos", Vector2.ZERO) as Vector2
		var screen: Vector2 = _world_to_screen(world)
		var sx := int(round(screen.x))
		var sy := int(round(screen.y))
		_log("EOA_FLEET2_LIVE who=screen sea=%s tag=%s world=%.1f,%.1f screen=%d,%d zoom=%.3f" % [
			cap_name, str(k), world.x, world.y, sx, sy, zoom
		])
		if sx < 8 or sy < 8 or sx >= img.get_width() - 8 or sy >= img.get_height() - 8:
			_fail_reasons.append("%s_%s_screen_oob_%d_%d" % [cap_name, str(k), sx, sy])
			continue
		var nation: Color = _nation_color(str(k))
		var hit := _sample_plate_pixels(img, sx, sy, nation)
		_log(
			"EOA_FLEET2_LIVE who=pixel sea=%s tag=%s screen=%d,%d nation=%.2f,%.2f,%.2f hits=%d sea=%d choke=%d centre_rgb=%.2f,%.2f,%.2f ok=%s"
			% [
				cap_name, str(k), sx, sy, nation.r, nation.g, nation.b, hit["hits"],
				int(hit["sea"]), int(hit["choke"]), hit["cr"], hit["cg"], hit["cb"], str(hit["ok"]),
			]
		)
		if not bool(hit["ok"]):
			_fail_reasons.append("%s_%s_pixel_miss" % [cap_name, str(k)])


func _sample_plate_pixels(img: Image, cx: int, cy: int, nation: Color) -> Dictionary:
	var hits := 0
	var sea_hits := 0
	var choke_hits := 0
	var cr := 0.0
	var cg := 0.0
	var cb := 0.0
	var rad := 7
	var n := 0
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c: Color = img.get_pixel(x, y)
			if dx == 0 and dy == 0:
				cr = c.r
				cg = c.g
				cb = c.b
			n += 1
			if _is_choke_color(c):
				choke_hits += 1
				continue
			if _is_sea_color(c):
				sea_hits += 1
				continue
			if _is_nation_or_label(c, nation):
				hits += 1
	# Centre of a painted plate is nation / NATO / label, not sea or choke diamond.
	var ok: bool = hits >= 8 and hits > choke_hits
	return {"hits": hits, "ok": ok, "cr": cr, "cg": cg, "cb": cb, "n": n, "sea": sea_hits, "choke": choke_hits}


func _is_sea_color(c: Color) -> bool:
	# Political sea: mid/dark blue. Neutral dark (NATO/outline) is not sea.
	if c.b > c.r + 0.06 and c.b > c.g + 0.02 and c.r < 0.40:
		return true
	return false


func _is_choke_color(c: Color) -> bool:
	# Orange / cyan diamonds only — not pale label glyphs.
	if c.r > 0.85 and c.g > 0.35 and c.g < 0.75 and c.b < 0.35:
		return true
	if c.g > 0.70 and c.b > 0.70 and c.r < 0.45:
		return true
	return false


func _is_nation_or_label(c: Color, nation: Color) -> bool:
	var dr: float = c.r - nation.r
	var dg: float = c.g - nation.g
	var db: float = c.b - nation.b
	if dr * dr + dg * dg + db * db < 0.22:
		return true
	var lifted := Color(
		clampf(nation.r * 0.70 + 0.18, 0.0, 1.0),
		clampf(nation.g * 0.70 + 0.18, 0.0, 1.0),
		clampf(nation.b * 0.70 + 0.18, 0.0, 1.0),
		1.0
	)
	dr = c.r - lifted.r
	dg = c.g - lifted.g
	db = c.b - lifted.b
	if dr * dr + dg * dg + db * db < 0.20:
		return true
	var luma: float = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
	# Pale label / NATO glyph, or dark plate outline (not blue sea).
	if luma > 0.55:
		return true
	if luma < 0.28 and absf(c.r - c.b) < 0.08:
		return true
	return false


func _nation_color(tag: String) -> Color:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_country_color"):
		return mm.call("get_country_color", tag) as Color
	match tag:
		"GER":
			return Color(0.35, 0.36, 0.38)
		"ENG":
			return Color(0.75, 0.18, 0.18)
		"FRA":
			return Color(0.22, 0.35, 0.72)
		"ITA":
			return Color(0.22, 0.55, 0.28)
		"POL":
			return Color(0.72, 0.20, 0.28)
		"USA":
			return Color(0.20, 0.32, 0.62)
		"JAP":
			return Color(0.85, 0.85, 0.88)
		"SOV":
			return Color(0.70, 0.16, 0.16)
		_:
			return Color(0.5, 0.5, 0.6)


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


func _reset_card() -> void:
	var mr := _map_renderer()
	if mr != null:
		if "selected_formation_id" in mr:
			mr.selected_formation_id = ""
		if "selected_province_id" in mr:
			mr.selected_province_id = -1
	var ui := _find_named("UI")
	if ui != null:
		var old: Node = ui.get_node_or_null("UnitDetailPopup")
		if old != null:
			ui.remove_child(old)
			old.free()


func _popup_state() -> Dictionary:
	var out := {"up": false, "open_fight": false, "assign": false}
	var ui := _find_named("UI")
	if ui == null:
		return out
	var pop: Node = ui.get_node_or_null("UnitDetailPopup")
	if pop == null or not is_instance_valid(pop):
		return out
	out["up"] = true
	out["open_fight"] = pop.find_child("BtnOpenFight", true, false) != null
	out["assign"] = pop.find_child("BtnAssignLeader", true, false) != null
	return out


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
	_log("WindowedFleet2LiveScaleCheck: RESULT=%s reasons=%s captures=%d home_zoom=%.3f" % [
		verdict, str(_fail_reasons), _captures.size(), _home_zoom
	])
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
