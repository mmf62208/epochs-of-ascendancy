extends SceneTree

## FLEET-2 FIX #6 live-scale check on the real world_accurate board.
## xvfb exactly 1280x740 · GER · Europe Home · Channel + North Sea at Home zoom
## and ~1.5. Pixel-assert each plate centre. Click all 8 plates at 0.318 / 0.40
## / 0.8 / 1.5 plus East Kent, old ENG chip, and a GER-nearest gap.
## Also click Play-listed land/air counters at 0.318 / 0.40, coasts 710374 /
## 710380 (topmost PAINTED chip or own GER/province — never NLD through an
## empty label box), Emden NLD east +20, DNK AW3 bars +44 / ±4 / ±8 / ends /
## 2 px sweep, own AW3 bars +46 / corner, Emden painted-rect grid, own GER
## bodies, and bare-land points east of the NLD label. xvfb is NOT live Play.
## Never EOA_SKIP_TITLE.
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
const REPO_DIR := "docs/evidence/fleet2b"
const COAST_A := 710374
const COAST_B := 710380

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
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/fleet2b")
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
	_assert_zoom_reorder_ms()
	var zooms: Array = [0.318, 0.40, 0.80, 1.50]
	var zoom_env := OS.get_environment("EOA_FLEET2_LIVE_ZOOMS").strip_edges()
	if not zoom_env.is_empty():
		zooms = []
		for part in zoom_env.split(","):
			var bit := part.strip_edges()
			if bit.is_empty():
				continue
			zooms.append(float(bit))
	for z_v in zooms:
		var z: float = float(z_v)
		_frame_sea_direct(_ch_cluster if _ch_cluster != Vector2.ZERO else LIVE_RENDER_CHANNEL, z, "click_z%.3f" % z)
		var ch: Dictionary = _collect_sea_plates(CHANNEL)
		var ns: Dictionary = _collect_sea_plates(NORTH_SEA)
		if ch.size() >= 4:
			_ch_plates = ch
		if ns.size() >= 4:
			_ns_plates = ns
		for k in _ch_plates.keys():
			var rec: Dictionary = _ch_plates[k] as Dictionary
			_click_one({
				"who": "z%.3f_CH_%s" % [z, str(k)],
				"pos": rec.get("pos", Vector2.ZERO) as Vector2,
				"own": false,
				"kind": "fleet",
				"want_tags": ["ENG", "ITA", "POL", "USA"],
			})
		for k2 in _ns_plates.keys():
			var rec2: Dictionary = _ns_plates[k2] as Dictionary
			var tag := str(k2)
			_click_one({
				"who": "z%.3f_NS_%s" % [z, tag],
				"pos": rec2.get("pos", Vector2.ZERO) as Vector2,
				"own": tag == GER_TAG,
				"kind": "fleet",
				"want_tags": ["GER", "FRA", "JAP", "SOV"],
			})
		_click_one({
			"who": "z%.3f_east_kent_711453" % z,
			"pos": LIVE_RENDER_EAST_KENT,
			"own": false,
			"kind": "fleet",
			"want_tags": ["ENG", "ITA", "POL", "USA"],
		})
		_click_one({
			"who": "z%.3f_old_eng_chip" % z,
			"pos": LIVE_OLD_ENG_CHIP,
			"own": false,
			"kind": "fleet",
			"want_tags": ["ENG", "ITA", "POL", "USA"],
		})
		var ger_p: Vector2 = Vector2.ZERO
		var fra_p: Vector2 = Vector2.ZERO
		if _ns_plates.has("GER"):
			ger_p = (_ns_plates["GER"] as Dictionary).get("pos", Vector2.ZERO) as Vector2
		if _ns_plates.has("FRA"):
			fra_p = (_ns_plates["FRA"] as Dictionary).get("pos", Vector2.ZERO) as Vector2
		if ger_p != Vector2.ZERO and fra_p != Vector2.ZERO:
			_click_one({
				"who": "z%.3f_GER_nearest_gap" % z,
				"pos": ger_p.lerp(fra_p, 0.38),
				"own": true,
				"kind": "fleet",
				"want_tags": ["GER"],
			})
		if z == 0.318 or z == 0.40:
			_click_land_air_guard(z)
			_click_own_ger_bodies(z)
			if is_equal_approx(z, 0.318):
				_click_home_measured_points()
	_click_ger_face_pixels()
	_click_airfield_l4()
	_write_clicks_md()
	_finish(_fail_reasons.is_empty())


func _click_one(row: Dictionary) -> void:
	var mr := _map_renderer()
	var who := str(row.get("who", "?"))
	var pos: Vector2 = row.get("pos", Vector2.ZERO) as Vector2
	var own: bool = bool(row.get("own", false))
	var want: Array = row.get("want_tags", []) as Array
	var kind := str(row.get("kind", "fleet"))
	var want_type := str(row.get("want_type", ""))
	var want_fid := str(row.get("want_fid", ""))
	if mr == null:
		_fail_reasons.append("click_%s_no_mr" % who)
		return
	_reset_card()
	var opened := false
	if mr.has_method("_try_open_unit_at_world"):
		opened = bool(mr.call("_try_open_unit_at_world", pos))
	if not opened and mr.has_method("_try_open_land_unit_at_world"):
		opened = bool(mr.call("_try_open_land_unit_at_world", pos, false, false))
	var fo: Object = null
	if mr.has_method("_pick_unit_formation_at_world"):
		fo = mr.call("_pick_unit_formation_at_world", pos)
	var fid := str(fo.formation_id) if fo != null and "formation_id" in fo else "null"
	var tag := str(fo.country_tag).strip_edges().to_upper() if fo != null and "country_tag" in fo else "?"
	var ftype := str(fo.formation_type) if fo != null and "formation_type" in fo else "?"
	var card := _popup_state()
	var ok := false
	if kind == "fleet":
		ok = fo != null and ftype == "fleet" and tag in want and opened
		if who.ends_with("east_kent_711453") or who.ends_with("old_eng_chip"):
			ok = ok and tag != GER_TAG and fid.find("Div") < 0 and fid.find("Garrison") < 0
		if who.find("GER_nearest_gap") >= 0:
			ok = ok and tag == GER_TAG and ftype == "fleet"
	elif kind == "hex_own_or_province":
		# German land: own GER (not fleet) or no unit. Never a foreign chip.
		if fo == null:
			ok = true
		else:
			ok = tag == GER_TAG and ftype != "fleet"
	elif kind == "not_fid":
		# Airfield cluster: fail only when this click opens the forbidden formation.
		ok = not (opened and fid == want_fid)
	else:
		ok = fo != null and opened and tag in want and ftype != "fleet"
		if not want_type.is_empty():
			ok = ok and ftype == want_type
		if not want_fid.is_empty():
			ok = ok and fid == want_fid
	if kind != "hex_own_or_province" and kind != "not_fid":
		if own:
			ok = ok and card["open_fight"] and card["assign"]
		else:
			ok = ok and not card["open_fight"] and not card["assign"]
	elif kind == "hex_own_or_province" and fo != null and tag == GER_TAG:
		ok = ok and card["open_fight"] and card["assign"]
	var screen := _world_to_screen(pos)
	var line := (
		"EOA_FLEET2_LIVE who=click name=%s world=%.1f,%.1f screen=%.0f,%.0f fid=%s tag=%s type=%s opened=%s own_card=%s fight=%s assign=%s ok=%s"
		% [who, pos.x, pos.y, screen.x, screen.y, fid, tag, ftype, str(opened), str(own), str(card["open_fight"]), str(card["assign"]), str(ok)]
	)
	_log(line)
	_click_log.append(line)
	if who.ends_with("old_eng_chip") or who.ends_with("east_kent_711453"):
		_kent_pick = "%s/%s/%s" % [fid, tag, ftype]
	if not ok:
		_fail_reasons.append("click_%s_got_%s_%s" % [who, tag, ftype])


func _click_land_air_guard(z: float) -> void:
	var counters: Array = _collect_land_air_counters()
	var rows: Array = [
		{"who": "ENG_Div_0", "tag": "ENG", "type": "division", "ord": 0},
		{"who": "ENG_Div_1", "tag": "ENG", "type": "division", "ord": 1},
		{"who": "BEL_Div_0", "tag": "BEL", "type": "division", "ord": 0},
		{"who": "BEL_Div_1", "tag": "BEL", "type": "division", "ord": 1},
		{"who": "BEL_Div_2", "tag": "BEL", "type": "division", "ord": 2},
		{"who": "NLD_Div_0", "tag": "NLD", "type": "division", "ord": 0},
		{"who": "NLD_Div_2", "tag": "NLD", "type": "division", "ord": 2},
		{"who": "NLD_AW3", "tag": "NLD", "type": "air_wing", "ord": 3},
		{"who": "FRA_Garrison_4", "tag": "FRA", "type": "garrison", "ord": 4},
		{"who": "Emden_NLD", "tag": "NLD", "type": "division", "ord": 1},
		{"who": "BEL_AW3", "tag": "BEL", "type": "air_wing", "ord": 3},
		{"who": "DNK_AW3", "tag": "DNK", "type": "air_wing", "ord": 3},
	]
	for rec_v in rows:
		var rec: Dictionary = rec_v as Dictionary
		var hit: Dictionary = _match_land_air(counters, str(rec["tag"]), str(rec["type"]), int(rec["ord"]))
		if hit.is_empty():
			_fail_reasons.append("missing_%s_z%.3f" % [str(rec["who"]), z])
			_log("EOA_FLEET2_LIVE who=missing name=%s z=%.3f" % [str(rec["who"]), z])
			continue
		var want_fid := str(hit.get("fid", ""))
		var icon: Node2D = hit.get("icon", null) as Node2D
		var pos: Vector2 = _point_where_chip_is_drawn(icon, want_fid)
		if pos.x > 1.0e8:
			var cover := ""
			var origin := Vector2.ZERO
			if icon != null and is_instance_valid(icon):
				origin = icon.global_position
				cover = _painted_piece_winner_fid(origin)
				var xf_b: Transform2D = icon.get_global_transform()
				var bits: PackedStringArray = PackedStringArray()
				for off_v in [Vector2(0, -18), Vector2(0, 27), Vector2(24, 10), Vector2(-24, 10), Vector2(36, 8)]:
					var off: Vector2 = off_v as Vector2
					bits.append("%s=%s" % [str(off), _painted_piece_winner_fid(xf_b * off)])
				_log("EOA_FLEET2_LIVE who=buried_samples name=%s origin=%.1f,%.1f scale=%.2f %s" % [
					str(rec["who"]), origin.x, origin.y, icon.scale.x, " ".join(bits)
				])
			_fail_reasons.append("no_top_pixel_%s_z%.3f" % [str(rec["who"]), z])
			_log("EOA_FLEET2_LIVE who=no_top_pixel name=%s z=%.3f fid=%s cover_at_origin=%s" % [
				str(rec["who"]), z, want_fid, cover
			])
			continue
		_click_one({
			"who": "z%.3f_%s" % [z, str(rec["who"])],
			"pos": pos,
			"own": false,
			"kind": "land",
			"want_tags": [str(rec["tag"])],
			"want_type": str(rec["type"]),
			"want_fid": want_fid,
		})
	_click_coast_hex(z, COAST_A)
	_click_coast_hex(z, COAST_B)
	_click_own_aw3_painted(z)
	_click_emden_east(z)
	_click_dnk_aw3_bars(z)
	_click_dnk_aw3_bar_strip(z)
	_click_nld_label_east_bare(z)
	_click_emden_grid(z)
	if is_equal_approx(z, 0.40):
		_click_heidekreis_painted_or_own(z)


func _click_home_measured_points() -> void:
	# Europe Home at z0.318. NLD Div 1 is the Channel bar corner
	# (screen 742,386 on the Channel camera — local 21.2, 33.8).
	# GER AW3 is a pixel that chip is drawn on, not a fixed Home screen point.
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	var cam := _camera()
	if cam != null:
		cam.zoom = Vector2(0.318, 0.318)
		cam.make_current()
	if mr != null and mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint", 0.318)
	var cam_pos := Vector2.ZERO
	if cam != null:
		cam_pos = cam.global_position
	_log("EOA_FLEET2_LIVE who=home_frame zoom=0.318 cam=%.1f,%.1f" % [cam_pos.x, cam_pos.y])
	var counters: Array = _collect_land_air_counters()
	var nld: Dictionary = _match_land_air(counters, "NLD", "division", 1)
	var ger: Dictionary = _match_land_air(counters, "GER", "air_wing", 3)
	if nld.is_empty():
		_fail_reasons.append("missing_Emden_NLD_home")
	else:
		var nld_icon: Node2D = nld.get("icon", null) as Node2D
		var nld_fid := str(nld.get("fid", ""))
		# The old local (21.2, 33.8) rim is under a player symbol once
		# those sprites paint above foreign bars. Click a pixel this
		# chip still owns.
		var nld_pos: Vector2 = _point_where_chip_is_drawn(nld_icon, nld_fid)
		if nld_pos.x > 1.0e8:
			_fail_reasons.append("no_top_pixel_Emden_NLD_home")
			_log("EOA_FLEET2_LIVE who=no_top_pixel name=Emden_NLD_home fid=%s" % nld_fid)
		else:
			_click_one({
				"who": "home_Emden_NLD_rim",
				"pos": nld_pos,
				"own": false,
				"kind": "land",
				"want_tags": ["NLD"],
				"want_type": "division",
				"want_fid": nld_fid,
			})
	if ger.is_empty():
		_fail_reasons.append("missing_GER_AW3_home_bars")
	else:
		var ger_icon: Node2D = ger.get("icon", null) as Node2D
		var ger_fid := str(ger.get("fid", ""))
		var ger_pos: Vector2 = _point_where_chip_is_drawn(ger_icon, ger_fid)
		if ger_pos.x > 1.0e8:
			ger_pos = ger.get("pos", Vector2.ZERO) as Vector2
		_click_one({
			"who": "home_GER_AW3_bars",
			"pos": ger_pos,
			"own": true,
			"kind": "land",
			"want_tags": ["GER"],
			"want_type": "air_wing",
			"want_fid": ger_fid,
		})


func _click_own_ger_bodies(z: float) -> void:
	var counters: Array = _collect_land_air_counters()
	var rows: Array = [
		{"who": "GER_Div_6", "tag": "GER", "type": "division", "ord": 6},
		{"who": "GER_Div_7", "tag": "GER", "type": "division", "ord": 7},
		{"who": "GER_Garrison_4", "tag": "GER", "type": "garrison", "ord": 4},
		{"who": "GER_AW3", "tag": "GER", "type": "air_wing", "ord": 3},
	]
	for rec_v in rows:
		var rec: Dictionary = rec_v as Dictionary
		var hit: Dictionary = _match_land_air(counters, str(rec["tag"]), str(rec["type"]), int(rec["ord"]))
		if hit.is_empty():
			_fail_reasons.append("missing_%s_z%.3f" % [str(rec["who"]), z])
			continue
		var want_fid := str(hit.get("fid", ""))
		var icon: Node2D = hit.get("icon", null) as Node2D
		var pos: Vector2 = _point_where_chip_is_drawn(icon, want_fid)
		if pos.x > 1.0e8:
			var cover := ""
			if icon != null and is_instance_valid(icon):
				cover = _painted_piece_winner_fid(icon.global_position)
			_fail_reasons.append("no_top_pixel_%s_z%.3f" % [str(rec["who"]), z])
			_log("EOA_FLEET2_LIVE who=no_top_pixel name=%s z=%.3f fid=%s cover_at_origin=%s" % [
				str(rec["who"]), z, want_fid, cover
			])
			continue
		_click_one({
			"who": "z%.3f_%s_body" % [z, str(rec["who"])],
			"pos": pos,
			"own": true,
			"kind": "land",
			"want_tags": ["GER"],
			"want_type": str(rec["type"]),
			"want_fid": want_fid,
		})


func _click_coast_hex(z: float, pid: int) -> void:
	var pos: Vector2 = _province_world(pid)
	if pos == Vector2.ZERO:
		_fail_reasons.append("coast_%d_no_centroid" % pid)
		return
	# Halo probe: if the centroid sits on a painted foreign plate (Emden
	# NLD covers all of Cuxhaven at Home scale), walk to a point that still
	# GIS-resolves to this hex but misses every painted body.
	var halo: Vector2 = _halo_point_in_province(pid, pos, z)
	if halo.distance_to(pos) > 0.5:
		_log("EOA_FLEET2_LIVE who=coast_halo pid=%d centroid=%.1f,%.1f halo=%.1f,%.1f z=%.3f" % [
			pid, pos.x, pos.y, halo.x, halo.y, z
		])
		_click_one({
			"who": "z%.3f_coast_%d" % [z, pid],
			"pos": halo,
			"own": false,
			"kind": "hex_own_or_province",
			"want_tags": ["GER"],
		})
		return
	if _any_painted_at(pos):
		# Whole hex sits under a painted body (Cuxhaven inside Emden plate).
		# Painted-body rule applies; do not demand GER spill.
		var top := _name_topmost_painted(pos)
		_log("EOA_FLEET2_LIVE who=coast_covered_by_paint pid=%d world=%.1f,%.1f topmost=%s z=%.3f" % [
			pid, pos.x, pos.y, top, z
		])
		_click_log.append("coast %d covered_by_paint topmost=%s" % [pid, top])
		return
	_click_one({
		"who": "z%.3f_coast_%d" % [z, pid],
		"pos": pos,
		"own": false,
		"kind": "hex_own_or_province",
		"want_tags": ["GER"],
	})


func _click_emden_east(z: float) -> void:
	var counters: Array = _collect_land_air_counters()
	var hit: Dictionary = _match_land_air(counters, "NLD", "division", 1)
	if hit.is_empty():
		_fail_reasons.append("missing_Emden_NLD_east_z%.3f" % z)
		return
	var base: Vector2 = hit.get("pos", Vector2.ZERO) as Vector2
	var want_fid := str(hit.get("fid", ""))
	var east: Vector2 = base + Vector2(20.0 / maxf(z, 0.05), 0.0)
	var icon: Node2D = hit.get("icon", null) as Node2D
	if _painted_piece_winner_fid(east) != want_fid:
		var found: Vector2 = _nld_div1_east_pixel(icon, want_fid)
		if found.x > 1.0e8:
			_fail_reasons.append("no_top_pixel_Emden_NLD_east_z%.3f" % z)
			_log("EOA_FLEET2_LIVE who=no_top_pixel name=Emden_NLD_east z=%.3f fid=%s" % [z, want_fid])
			return
		east = found
	_click_one({
		"who": "z%.3f_Emden_NLD_east20" % z,
		"pos": east,
		"own": false,
		"kind": "land",
		"want_tags": ["NLD"],
		"want_type": "division",
		"want_fid": want_fid,
	})


func _click_dnk_aw3_bars(z: float) -> void:
	var counters: Array = _collect_land_air_counters()
	var hit: Dictionary = _match_land_air(counters, "DNK", "air_wing", 3)
	if hit.is_empty():
		_fail_reasons.append("missing_DNK_AW3_bars_z%.3f" % z)
		return
	var icon: Node2D = hit.get("icon", null) as Node2D
	var base: Vector2 = hit.get("pos", Vector2.ZERO) as Vector2
	var want_fid: String = str(hit.get("fid", ""))
	var bars: Vector2 = base + Vector2(0.0, 44.0 / maxf(z, 0.05))
	if icon != null and is_instance_valid(icon):
		var xf: Transform2D = icon.get_global_transform()
		var local_bars: Vector2 = xf * Vector2(0.0, 27.0)
		if not _world_in_icon_stat_bars_or_local(icon, bars):
			if _world_in_icon_painted(icon, bars):
				pass
			else:
				bars = local_bars
		# +44 at Home sits on the Emden NLD plate (nearer). Walk the
		# painted bar strip for a pixel that already picks DNK — first a
		# bars-only pixel (off every other plate), then any bar pixel
		# whose current pick is DNK.
		var picked: Vector2 = _dnk_bars_pick_point(icon, bars, want_fid, z)
		if picked != bars:
			bars = picked
	_click_one({
		"who": "z%.3f_DNK_AW3_bars44" % z,
		"pos": bars,
		"own": false,
		"kind": "land",
		"want_tags": ["DNK"],
		"want_type": "air_wing",
		"want_fid": want_fid,
	})


func _dnk_bars_pick_point(icon: Node2D, start: Vector2, want_fid: String, z: float) -> Vector2:
	var xf: Transform2D = icon.get_global_transform()
	var cands: Array = [start, xf * Vector2(0.0, 27.0)]
	var lxs: Array = [6, 8, 10, 12, 14, 16, 18, 20, -6, -8, -10, 4, -4, 22, -12, -14, -16, -18, -20]
	var lys: Array = [27, 24, 30, 22, 32]
	for lx_v in lxs:
		for ly_v in lys:
			cands.append(xf * Vector2(float(lx_v), float(ly_v)))
	var mr := _map_renderer()
	var off_plate: Vector2 = Vector2.ZERO
	var have_off: bool = false
	for cand_v in cands:
		var cand: Vector2 = cand_v as Vector2
		if not _world_in_icon_stat_bars_or_local(icon, cand):
			continue
		if not _other_plate_owns(cand, icon):
			if not have_off:
				off_plate = cand
				have_off = true
			if _pick_fid_at(mr, cand) == want_fid:
				_log("EOA_FLEET2_LIVE who=dnk_bars_walk z=%.3f world=%.1f,%.1f off_plate=1 fid=%s" % [
					z, cand.x, cand.y, want_fid
				])
				return cand
	if have_off:
		_log("EOA_FLEET2_LIVE who=dnk_bars_walk z=%.3f world=%.1f,%.1f off_plate=1 fid=search" % [
			z, off_plate.x, off_plate.y
		])
		return off_plate
	for cand_v2 in cands:
		var cand2: Vector2 = cand_v2 as Vector2
		if not _world_in_icon_stat_bars_or_local(icon, cand2):
			continue
		if _pick_fid_at(mr, cand2) == want_fid:
			_log("EOA_FLEET2_LIVE who=dnk_bars_walk z=%.3f world=%.1f,%.1f off_plate=0 fid=%s" % [
				z, cand2.x, cand2.y, want_fid
			])
			return cand2
	_log("EOA_FLEET2_LIVE who=dnk_bars_walk z=%.3f world=%.1f,%.1f off_plate=0 fid=none" % [
		z, start.x, start.y
	])
	return start


func _click_dnk_aw3_bar_strip(z: float) -> void:
	# FLEET-2b: full visible StatBars width — ±4, ±8, ends, every 2 px.
	var counters: Array = _collect_land_air_counters()
	var hit: Dictionary = _match_land_air(counters, "DNK", "air_wing", 3)
	if hit.is_empty():
		_fail_reasons.append("missing_DNK_AW3_strip_z%.3f" % z)
		return
	var icon: Node2D = hit.get("icon", null) as Node2D
	var want_fid: String = str(hit.get("fid", ""))
	if icon == null or not is_instance_valid(icon):
		_fail_reasons.append("missing_DNK_AW3_strip_icon_z%.3f" % z)
		return
	var xf: Transform2D = icon.get_global_transform()
	var mid: Vector2 = xf * Vector2(0.0, 27.0)
	var zz: float = maxf(z, 0.05)
	var named: Array = [
		{"who": "DNK_AW3_bars_m4", "pos": mid + Vector2(-4.0 / zz, 0.0)},
		{"who": "DNK_AW3_bars_p4", "pos": mid + Vector2(4.0 / zz, 0.0)},
		{"who": "DNK_AW3_bars_m8", "pos": mid + Vector2(-8.0 / zz, 0.0)},
		{"who": "DNK_AW3_bars_p8", "pos": mid + Vector2(8.0 / zz, 0.0)},
		{"who": "DNK_AW3_bars_end_m", "pos": xf * Vector2(-20.0, 27.0)},
		{"who": "DNK_AW3_bars_end_p", "pos": xf * Vector2(20.0, 27.0)},
	]
	for rec_v in named:
		var rec: Dictionary = rec_v as Dictionary
		var pos: Vector2 = rec["pos"] as Vector2
		var who := str(rec["who"])
		if not _world_in_icon_stat_bars_or_local(icon, pos):
			_fail_reasons.append("dnk_strip_%s_off_bars_z%.3f" % [who, z])
			continue
		var got := _pick_fid_at(_map_renderer(), pos)
		var winner := _painted_piece_winner_fid(pos)
		_log("EOA_FLEET2_LIVE who=dnk_strip name=%s z=%.3f fid=%s winner=%s" % [who, z, got, winner])
		_click_log.append("dnk_strip %s fid=%s winner=%s" % [who, got, winner])
		if got != winner or winner.is_empty():
			_fail_reasons.append("dnk_strip_%s_z%.3f_got_%s_winner_%s" % [who, z, got, winner])
			continue
		if got == want_fid:
			_click_one({
				"who": "z%.3f_%s" % [z, who],
				"pos": pos,
				"own": false,
				"kind": "land",
				"want_tags": ["DNK"],
				"want_type": "air_wing",
				"want_fid": want_fid,
			})
	var sweep_ok: int = 0
	var sweep_n: int = 0
	var own_n: int = 0
	var other_n: int = 0
	var dx: int = -20
	while dx <= 20:
		var spos: Vector2 = xf * Vector2(float(dx), 27.0)
		sweep_n += 1
		var got_s := _pick_fid_at(_map_renderer(), spos)
		var winner_s := _painted_piece_winner_fid(spos)
		if _world_in_icon_stat_bars_or_local(icon, spos) and not winner_s.is_empty() and got_s == winner_s:
			sweep_ok += 1
			if got_s == want_fid:
				own_n += 1
			else:
				other_n += 1
		else:
			_fail_reasons.append("dnk_sweep_z%.3f_lx%d_got_%s_winner_%s" % [z, dx, got_s, winner_s])
			_log("EOA_FLEET2_LIVE who=dnk_sweep_fail z=%.3f lx=%d fid=%s winner=%s" % [z, dx, got_s, winner_s])
		dx += 2
	if own_n == 0:
		_fail_reasons.append("dnk_strip_no_own_bars_z%.3f" % z)
	# Home pile: some of this strip is another chip's ink. That pixel must
	# be the drawn piece, not NLD Div 1's plate just because the point
	# sits in that plate.
	if is_equal_approx(z, 0.318) and other_n == 0:
		_fail_reasons.append("dnk_strip_no_overlap_z%.3f" % z)
	_log("EOA_FLEET2_LIVE who=dnk_sweep_sum z=%.3f ok=%d n=%d own=%d other=%d" % [z, sweep_ok, sweep_n, own_n, other_n])
	_click_log.append("dnk_sweep z=%.3f ok=%d/%d own=%d other=%d" % [z, sweep_ok, sweep_n, own_n, other_n])


func _click_nld_label_east_bare(z: float) -> void:
	# Bare land east of the Emden NLD label — must not open NLD_1.
	var counters: Array = _collect_land_air_counters()
	var hit: Dictionary = _match_land_air(counters, "NLD", "division", 1)
	if hit.is_empty():
		_fail_reasons.append("missing_NLD_label_east_z%.3f" % z)
		return
	var icon: Node2D = hit.get("icon", null) as Node2D
	var base: Vector2 = hit.get("pos", Vector2.ZERO) as Vector2
	var nld_fid := str(hit.get("fid", ""))
	if icon == null or not is_instance_valid(icon):
		_fail_reasons.append("missing_NLD_label_east_icon_z%.3f" % z)
		return
	var xf: Transform2D = icon.get_global_transform()
	var pts: Array = [
		{"who": "NLD_label_east_local28", "pos": xf * Vector2(28.0, 12.0)},
		{"who": "NLD_label_east_local32", "pos": xf * Vector2(32.0, 10.0)},
		{"who": "NLD_label_east_40px", "pos": base + Vector2(40.0 / maxf(z, 0.05), 0.0)},
	]
	for rec_v in pts:
		var rec: Dictionary = rec_v as Dictionary
		var pos: Vector2 = rec["pos"] as Vector2
		var who := str(rec["who"])
		var nld_paint: bool = _world_in_icon_painted(icon, pos)
		var any_paint: bool = _any_painted_at(pos)
		var fid := _pick_fid_at(_map_renderer(), pos)
		_log(
			"EOA_FLEET2_LIVE who=nld_label_east name=%s z=%.3f world=%.1f,%.1f nld_paint=%s any_paint=%s fid=%s"
			% [who, z, pos.x, pos.y, str(nld_paint), str(any_paint), fid]
		)
		_click_log.append("label_east %s nld_paint=%s any_paint=%s fid=%s" % [who, str(nld_paint), str(any_paint), fid])
		if nld_paint:
			continue
		if fid == nld_fid:
			_fail_reasons.append("label_east_%s_z%.3f_nld_empty_box" % [who, z])
			continue
		if any_paint:
			_click_log.append("label_east %s covered_by_paint topmost=%s" % [who, _name_topmost_painted(pos)])
			continue
		_click_one({
			"who": "z%.3f_%s" % [z, who],
			"pos": pos,
			"own": false,
			"kind": "hex_own_or_province",
			"want_tags": ["GER"],
		})


func _click_heidekreis_painted_or_own(z: float) -> void:
	# z0.40 Heidekreis: topmost PAINTED chip or own GER/province — never
	# NLD_1 through an empty label box.
	var pos: Vector2 = _province_world(COAST_B)
	if pos == Vector2.ZERO:
		_fail_reasons.append("heidekreis_no_centroid")
		return
	var nld_hit: Dictionary = _match_land_air(_collect_land_air_counters(), "NLD", "division", 1)
	var nld_fid := str(nld_hit.get("fid", "NLD_formation_1"))
	var nld_icon: Node2D = nld_hit.get("icon", null) as Node2D
	var painted: bool = _any_painted_at(pos)
	var in_nld_paint: bool = nld_icon != null and _world_in_icon_painted(nld_icon, pos)
	var fid := _pick_fid_at(_map_renderer(), pos)
	_log(
		"EOA_FLEET2_LIVE who=heidekreis_z40 world=%.1f,%.1f painted=%s in_nld_paint=%s fid=%s"
		% [pos.x, pos.y, str(painted), str(in_nld_paint), fid]
	)
	_click_log.append("heidekreis z=%.3f painted=%s in_nld_paint=%s fid=%s" % [z, str(painted), str(in_nld_paint), fid])
	if fid == nld_fid and not in_nld_paint:
		_fail_reasons.append("heidekreis_z%.3f_nld_empty_label" % z)
		return
	if painted:
		var top := _name_topmost_painted(pos)
		if top == nld_fid and not in_nld_paint:
			_fail_reasons.append("heidekreis_z%.3f_topmost_nld_empty_label" % z)
		_click_log.append("heidekreis covered_by_paint topmost=%s" % top)
		return
	_click_one({
		"who": "z%.3f_Heidekreis_halo" % z,
		"pos": pos,
		"own": false,
		"kind": "hex_own_or_province",
		"want_tags": ["GER"],
	})


func _assert_zoom_reorder_ms() -> void:
	# The deleted per-zoom raise spent 30–70 s below z0.65. This step is
	# one scale sync from 0.40 to 0.318 after a warmup sync.
	var mr := _map_renderer()
	if mr == null or not mr.has_method("_sync_unit_counter_paint"):
		_fail_reasons.append("zoom_step_no_sync")
		return
	var n := 0
	if "_demo_unit_icon_pids" in mr:
		n = (mr._demo_unit_icon_pids as Array).size()
	if n < 10:
		_fail_reasons.append("zoom_step_few_icons_%d" % n)
		return
	mr.call("_sync_unit_counter_paint", 0.40)
	mr.call("_sync_unit_counter_paint", 0.40)
	mr.set_meta("eoa_trace_counter_sync", true)
	var t0 := Time.get_ticks_usec()
	mr.call("_sync_unit_counter_paint", 0.318)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_log("EOA_FLEET2_LIVE who=zoom_step from=0.400 to=0.318 ms=%.2f icons=%d" % [ms, n])
	if ms > 50.0:
		_fail_reasons.append("zoom_step_ms_%.1f" % ms)


func _click_ger_face_pixels() -> void:
	# Province 710977 at z0.318. Each face pixel is chosen where this
	# chip's sprite is the top painted piece, then the live open must
	# be that formation. A miss is no_top_pixel, not a substitute point.
	var z := 0.318
	var pid := 710977
	var anchor := _province_world(pid)
	if anchor == Vector2.ZERO:
		_fail_reasons.append("ger_face_no_centroid")
		return
	_frame_sea_direct(anchor, z, "ger_faces_710977")
	var counters: Array = _collect_land_air_counters()
	var rows: Array = [
		{"who": "GER_Div_6", "type": "division", "ord": 6},
		{"who": "GER_Garrison_4", "type": "garrison", "ord": 4},
		{"who": "GER_Div_7", "type": "division", "ord": 7},
	]
	for rec_v in rows:
		var rec: Dictionary = rec_v as Dictionary
		var who := str(rec["who"])
		var hit: Dictionary = _match_land_air(counters, "GER", str(rec["type"]), int(rec["ord"]))
		if hit.is_empty():
			_fail_reasons.append("missing_%s_face" % who)
			_log("EOA_FLEET2_LIVE who=missing_face name=%s frame_pid=%d" % [who, pid])
			_log_ger_face_candidates(counters)
			continue
		_log("EOA_FLEET2_LIVE who=ger_face_unit name=%s fid=%s stationed=%d frame=%d" % [
			who, str(hit.get("fid", "")), int(hit.get("pid", -1)), pid
		])
		var want_fid := str(hit.get("fid", ""))
		var icon: Node2D = hit.get("icon", null) as Node2D
		var pos: Vector2 = _ger_face_world(icon, want_fid)
		if pos.x > 1.0e8:
			_fail_reasons.append("no_top_pixel_%s_z%.3f" % [who, z])
			_log("EOA_FLEET2_LIVE who=no_top_pixel name=%s z=%.3f fid=%s" % [who, z, want_fid])
			continue
		_click_one({
			"who": "z%.3f_%s_face" % [z, who],
			"pos": pos,
			"own": true,
			"kind": "land",
			"want_tags": ["GER"],
			"want_type": str(rec["type"]),
			"want_fid": want_fid,
		})


func _log_ger_face_candidates(counters: Array) -> void:
	var n := 0
	for c_v in counters:
		var c: Dictionary = c_v as Dictionary
		if str(c.get("tag", "")) != "GER":
			continue
		var ord := int(c.get("ord", -99))
		if ord != 4 and ord != 6 and ord != 7:
			continue
		_log("EOA_FLEET2_LIVE who=ger_face_candidate type=%s ord=%d pid=%d fid=%s" % [
			str(c.get("type", "")), ord, int(c.get("pid", -1)), str(c.get("fid", ""))
		])
		n += 1
		if n >= 12:
			return


func _match_land_air_at(counters: Array, tag: String, ftype: String, ord: int, pid: int) -> Dictionary:
	for c_v in counters:
		var c: Dictionary = c_v as Dictionary
		if str(c.get("tag", "")) != tag:
			continue
		if str(c.get("type", "")) != ftype:
			continue
		if int(c.get("ord", -99)) != ord:
			continue
		if int(c.get("pid", -1)) != pid:
			continue
		return c
	return {}


func _ger_face_world(icon: Node2D, want_fid: String) -> Vector2:
	if icon == null or not is_instance_valid(icon) or want_fid.is_empty():
		return Vector2(INF, INF)
	var spr: Sprite2D = null
	for c_v in icon.get_children():
		if c_v is Sprite2D and (c_v as Sprite2D).visible and (c_v as Sprite2D).texture != null:
			spr = c_v as Sprite2D
			break
	if spr == null:
		return Vector2(INF, INF)
	var mr := _map_renderer()
	if mr == null or not mr.has_method("_sprite_pixel_opaque") or not mr.has_method("_unit_counter_top_drawn_piece"):
		return Vector2(INF, INF)
	var sz: Vector2 = spr.texture.get_size()
	if spr.region_enabled:
		sz = spr.region_rect.size
	var locals: Array = [Vector2.ZERO]
	var step := 2.0
	var y := -sz.y * 0.5 + 1.0
	while y < sz.y * 0.5:
		var x := -sz.x * 0.5 + 1.0
		while x < sz.x * 0.5:
			locals.append(Vector2(x, y))
			x += step
		y += step
	var opaque_n := 0
	var sprite_top_n := 0
	var center_piece := "null"
	var center_fid := ""
	var center_opaque := false
	for local_v in locals:
		var local: Vector2 = local_v as Vector2
		var world: Vector2 = spr.to_global(local)
		var opaque := bool(mr.call("_sprite_pixel_opaque", spr, world))
		if local == Vector2.ZERO:
			center_opaque = opaque
			var piece0: Variant = mr.call("_unit_counter_top_drawn_piece", world, icon)
			if piece0 is Node:
				center_piece = str((piece0 as Node).name)
			center_fid = _painted_piece_winner_fid(world)
		if not opaque:
			continue
		opaque_n += 1
		var piece: Variant = mr.call("_unit_counter_top_drawn_piece", world, icon)
		if not (piece is Sprite2D):
			continue
		sprite_top_n += 1
		if _painted_piece_winner_fid(world) == want_fid:
			_log("EOA_FLEET2_LIVE who=ger_face_hit fid=%s opaque=%d sprite_top=%d tex=%.0fx%.0f" % [
				want_fid, opaque_n, sprite_top_n, sz.x, sz.y
			])
			return world
	var spr_z := -999
	var spr_eff := -999
	if mr.has_method("_canvas_item_effective_z"):
		spr_z = spr.z_index
		spr_eff = int(mr.call("_canvas_item_effective_z", spr))
	_log(
		"EOA_FLEET2_LIVE who=ger_face_miss fid=%s opaque=%d sprite_top=%d samples=%d tex=%.0fx%.0f center_opaque=%s center_piece=%s center_fid=%s spr_z=%d spr_eff=%d"
		% [want_fid, opaque_n, sprite_top_n, locals.size(), sz.x, sz.y, str(center_opaque), center_piece, center_fid, spr_z, spr_eff]
	)
	return Vector2(INF, INF)


func _click_airfield_l4() -> void:
	# L4 cluster on Neuwied. The nearest-own spill must not open GER_formation_4.
	var z := 0.760
	var pid := 710451
	var anchor := _province_world(pid)
	if anchor == Vector2.ZERO:
		_fail_reasons.append("airfield_710451_no_centroid")
		return
	_frame_sea_direct(anchor, z, "airfield_710451")
	var mr := _map_renderer()
	var ol: Node = null
	if mr != null and mr.has_method("get_overlay_layer"):
		ol = mr.call("get_overlay_layer", "FacilityIconLayer") as Node
	if ol == null or not ol.has_method("get_hit_rects_at_zoom"):
		_fail_reasons.append("airfield_no_layer")
		return
	var layouts: Array = ol.call("get_hit_rects_at_zoom", z) as Array
	var hit := Vector2(INF, INF)
	for layout_v in layouts:
		if typeof(layout_v) != TYPE_DICTIONARY:
			continue
		var layout: Dictionary = layout_v as Dictionary
		if int(layout.get("pid", -1)) != pid or not bool(layout.get("cluster", false)):
			continue
		var rect: Rect2 = layout.get("hit_icon", Rect2()) as Rect2
		if rect.size.x <= 0.0:
			continue
		var center: Vector2 = rect.get_center()
		var fac := -1
		if mr.has_method("_facility_icon_pid_at"):
			fac = int(mr.call("_facility_icon_pid_at", center))
		if fac == pid:
			hit = center
			break
	if hit.x > 1.0e8:
		_fail_reasons.append("airfield_710451_no_hit")
		_log("EOA_FLEET2_LIVE who=airfield_miss pid=%d z=%.3f" % [pid, z])
		return
	_click_one({
		"who": "z%.3f_L4_%d" % [z, pid],
		"pos": hit,
		"own": false,
		"kind": "not_fid",
		"want_fid": "GER_formation_4",
	})


func _pick_fid_at(_mr: Node, world: Vector2) -> String:
	# Point choice is the painted-piece walk. The live pick is only the
	# click result, so a search cannot lock onto its own answer.
	return _painted_piece_winner_fid(world)


func _click_emden_grid(z: float) -> void:
	var counters: Array = _collect_land_air_counters()
	var hit: Dictionary = _match_land_air(counters, "NLD", "division", 1)
	if hit.is_empty():
		_fail_reasons.append("missing_Emden_NLD_grid_z%.3f" % z)
		return
	var icon: Node2D = hit.get("icon", null) as Node2D
	var base: Vector2 = hit.get("pos", Vector2.ZERO) as Vector2
	var want_fid := str(hit.get("fid", ""))
	var dxs: Array = [-30, -20, -10, 0, 10, 20, 30]
	var dys: Array = [-24, 0, 24, 46]
	if z >= 0.36:
		dxs = [-30, -15, 0, 15, 30]
		dys = [-20, 5, 35]
	var nld1_n: int = 0
	var other_n: int = 0
	var outside_n: int = 0
	var zz: float = maxf(z, 0.05)
	for dx_v in dxs:
		for dy_v in dys:
			var dx: float = float(dx_v)
			var dy: float = float(dy_v)
			var world: Vector2 = base + Vector2(dx / zz, dy / zz)
			var in_nld: bool = _world_in_icon_painted(icon, world)
			var fo: Object = null
			var mr := _map_renderer()
			if mr != null and mr.has_method("_pick_unit_formation_at_world"):
				fo = mr.call("_pick_unit_formation_at_world", world)
			var fid := str(fo.formation_id) if fo != null and "formation_id" in fo else "null"
			var tag := str(fo.country_tag).strip_edges().to_upper() if fo != null and "country_tag" in fo else "?"
			var top_name := _name_topmost_painted(world)
			if in_nld:
				if fid == want_fid:
					nld1_n += 1
				else:
					other_n += 1
					# Inside NLD paint: only OK when a different counter is
					# drawn on top of this cell.
					if top_name.is_empty() or top_name == want_fid or top_name == "null":
						_fail_reasons.append(
							"emden_grid_z%.3f_%d_%d_got_%s_no_topmost" % [z, int(dx), int(dy), fid]
						)
			else:
				outside_n += 1
			_log(
				"EOA_FLEET2_LIVE who=emden_grid z=%.3f dx=%d dy=%d world=%.1f,%.1f in_nld=%s fid=%s tag=%s topmost=%s"
				% [z, int(dx), int(dy), world.x, world.y, str(in_nld), fid, tag, top_name]
			)
			_click_log.append(
				"grid z=%.3f dx=%d dy=%d in_nld=%s fid=%s topmost=%s" % [
					z, int(dx), int(dy), str(in_nld), fid, top_name
				]
			)
	_log(
		"EOA_FLEET2_LIVE who=emden_grid_sum z=%.3f nld1=%d other=%d outside=%d cells=%d"
		% [z, nld1_n, other_n, outside_n, nld1_n + other_n + outside_n]
	)


func _halo_point_in_province(pid: int, start: Vector2, z: float) -> Vector2:
	# FLEET-2b: walk off actually painted pixels only. An empty label box
	# is already a halo (Heidekreis).
	if not _any_painted_at(start):
		return start
	var mr := _map_renderer()
	var zz: float = maxf(z, 0.05)
	var radii: Array = [8, 10, 12, 14, 16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 80, 100, 128, 160, 200]
	for r_v in radii:
		var r: float = float(r_v) / zz
		for i in 24:
			var p: Vector2 = start + Vector2(r, 0.0).rotated(TAU * float(i) / 24.0)
			var hid: int = -1
			if mr != null and mr.has_method("_resolve_hex_pick_pid"):
				hid = int(mr.call("_resolve_hex_pick_pid", p))
			if hid == pid and not _any_painted_at(p):
				return p
	return start


func _any_painted_at(world: Vector2) -> bool:
	# FLEET-2b painted pixels only (plate + bars + glyph ink). An empty
	# designation AABB is not painted — Heidekreis 710380 at z0.40 must
	# not count as covered_by_paint just because the label box reaches it.
	var mr := _map_renderer()
	if mr == null or not ("_demo_unit_icon_pids" in mr):
		return false
	for id_v in mr._demo_unit_icon_pids:
		var id: int = int(id_v)
		if not mr.has_method("_iter_demo_unit_icons_at_pid"):
			continue
		for c_v in mr.call("_iter_demo_unit_icons_at_pid", id) as Array:
			var icon: Node2D = c_v as Node2D
			if icon == null or not is_instance_valid(icon) or not icon.visible:
				continue
			if bool(icon.get_meta("sea_nation_disk", false)):
				if mr.has_method("_unit_counter_top_drawn_piece"):
					var sea_piece: Variant = mr.call("_unit_counter_top_drawn_piece", world, icon)
					if sea_piece != null:
						return true
				continue
			if _world_in_icon_painted(icon, world):
				return true
	return false


func _name_topmost_painted(world: Vector2) -> String:
	var mr := _map_renderer()
	if mr == null or not ("_demo_unit_icon_pids" in mr):
		return ""
	var best: Node2D = null
	var best_fid := ""
	var best_d: float = INF
	for id_v in mr._demo_unit_icon_pids:
		var id: int = int(id_v)
		if not mr.has_method("_iter_demo_unit_icons_at_pid"):
			continue
		for c_v in mr.call("_iter_demo_unit_icons_at_pid", id) as Array:
			var icon: Node2D = c_v as Node2D
			if icon == null or not is_instance_valid(icon) or not icon.visible:
				continue
			var painted: bool = false
			var chip_pos: Vector2 = icon.global_position
			if mr.has_method("_demo_unit_icon_world_pos"):
				chip_pos = mr.call("_demo_unit_icon_world_pos", icon, id) as Vector2
			if bool(icon.get_meta("sea_nation_disk", false)):
				painted = false
				if mr.has_method("_unit_counter_top_drawn_piece"):
					painted = mr.call("_unit_counter_top_drawn_piece", world, icon) != null
			else:
				painted = _world_in_icon_painted(icon, world)
			if not painted:
				continue
			var fo: Object = null
			if mr.has_method("_formation_from_demo_icon"):
				fo = mr.call("_formation_from_demo_icon", icon)
			var fid := str(fo.formation_id) if fo != null and "formation_id" in fo else str(icon.get_meta("formation_id", ""))
			var d: float = world.distance_to(chip_pos)
			if best == null:
				best = icon
				best_fid = fid
				best_d = d
				continue
			var wins: bool = false
			if mr.has_method("_unit_counter_painted_wins"):
				wins = bool(mr.call("_unit_counter_painted_wins", icon, best, world, d, best_d))
			elif d < best_d:
				wins = true
			if wins:
				best = icon
				best_fid = fid
				best_d = d
	return best_fid


func _click_own_aw3_painted(z: float) -> void:
	var counters: Array = _collect_land_air_counters()
	var hit: Dictionary = _match_land_air(counters, "GER", "air_wing", 3)
	if hit.is_empty():
		_fail_reasons.append("missing_GER_AW3_painted_z%.3f" % z)
		return
	var icon: Node2D = hit.get("icon", null) as Node2D
	var base: Vector2 = hit.get("pos", Vector2.ZERO) as Vector2
	var want_fid := str(hit.get("fid", ""))
	var bars := Vector2(INF, INF)
	var corner := Vector2(INF, INF)
	if icon != null and is_instance_valid(icon):
		var xf: Transform2D = icon.get_global_transform()
		var bar_pts: Array = []
		var bars_px: Vector2 = base + Vector2(0.0, 46.0 / maxf(z, 0.05))
		if _world_in_icon_stat_bars(icon, bars_px):
			bar_pts.append(bars_px)
		bar_pts.append(xf * Vector2(0.0, 27.0))
		var bx := -20
		while bx <= 20:
			bar_pts.append(xf * Vector2(float(bx), 27.0))
			bar_pts.append(xf * Vector2(float(bx), 22.0))
			bar_pts.append(xf * Vector2(float(bx), 32.0))
			bx += 2
		bars = _first_owned_point(bar_pts, want_fid)
		var corner_pts: Array = [
			xf * Vector2(21.0, 20.0),
			xf * Vector2(18.0, 16.0),
			xf * Vector2(21.0, 12.0),
			xf * Vector2(16.0, 20.0),
			xf * Vector2(21.0, 8.0),
			xf * Vector2(12.0, 18.0),
		]
		var cx := 10
		while cx <= 22:
			var cy := 8
			while cy <= 22:
				corner_pts.append(xf * Vector2(float(cx), float(cy)))
				cy += 2
			cx += 2
		corner = _first_owned_point(corner_pts, want_fid)
	if bars.x > 1.0e8:
		_fail_reasons.append("no_top_pixel_GER_AW3_bars_z%.3f" % z)
		_log("EOA_FLEET2_LIVE who=no_top_pixel name=GER_AW3_bars z=%.3f fid=%s" % [z, want_fid])
	else:
		_click_one({
			"who": "z%.3f_GER_AW3_bars" % z,
			"pos": bars,
			"own": true,
			"kind": "land",
			"want_tags": ["GER"],
			"want_type": "air_wing",
			"want_fid": want_fid,
		})
	if corner.x > 1.0e8:
		_fail_reasons.append("no_top_pixel_GER_AW3_corner_z%.3f" % z)
		_log("EOA_FLEET2_LIVE who=no_top_pixel name=GER_AW3_corner z=%.3f fid=%s" % [z, want_fid])
	else:
		_click_one({
			"who": "z%.3f_GER_AW3_corner" % z,
			"pos": corner,
			"own": true,
			"kind": "land",
			"want_tags": ["GER"],
			"want_type": "air_wing",
			"want_fid": want_fid,
		})


func _world_in_icon_painted(icon: Node2D, world: Vector2) -> bool:
	var mr := _map_renderer()
	if mr != null and mr.has_method("_world_in_unit_painted_rect"):
		return bool(mr.call("_world_in_unit_painted_rect", world, icon))
	return true


func _world_in_icon_stat_bars(icon: Node2D, world: Vector2) -> bool:
	var mr := _map_renderer()
	if mr != null and mr.has_method("_world_in_unit_stat_bars"):
		return bool(mr.call("_world_in_unit_stat_bars", world, icon))
	return false


func _painted_piece_winner_fid(world: Vector2) -> String:
	# Same gate as the live pick, without calling it. Land must sit in
	# the painted rect. Sea needs a drawn piece. Cluster-blocked land
	# is not a candidate. Rank is piece z, then tree order.
	var mr := _map_renderer()
	if mr == null or not ("_demo_unit_icon_pids" in mr):
		return ""
	if not mr.has_method("_canvas_item_effective_z") or not mr.has_method("_unit_counter_top_drawn_piece"):
		return ""
	var best_piece: CanvasItem = null
	var best_fid := ""
	for id_v in mr._demo_unit_icon_pids:
		var id: int = int(id_v)
		if not mr.has_method("_iter_demo_unit_icons_at_pid"):
			continue
		for c_v in mr.call("_iter_demo_unit_icons_at_pid", id) as Array:
			var icon: Node2D = c_v as Node2D
			if icon == null or not is_instance_valid(icon) or not icon.visible:
				continue
			var fo: Object = null
			if mr.has_method("_formation_from_demo_icon"):
				fo = mr.call("_formation_from_demo_icon", icon)
			if fo == null:
				continue
			var sea: bool = bool(icon.get_meta("sea_nation_disk", false))
			if not sea:
				if mr.has_method("_world_in_unit_painted_rect") and not bool(mr.call("_world_in_unit_painted_rect", world, icon)):
					continue
				if mr.has_method("_land_air_body_blocked_by_cluster_hole") and bool(mr.call("_land_air_body_blocked_by_cluster_hole", world, fo, -1.0)):
					continue
			var piece: CanvasItem = mr.call("_unit_counter_top_drawn_piece", world, icon) as CanvasItem
			if piece == null:
				continue
			if best_piece != null and not _piece_is_drawn_above(mr, piece, best_piece):
				continue
			best_piece = piece
			best_fid = str(fo.formation_id) if "formation_id" in fo else ""
	return best_fid


func _piece_is_drawn_above(mr: Node, a: CanvasItem, b: CanvasItem) -> bool:
	if a == null:
		return false
	if b == null:
		return true
	var za: int = int(mr.call("_canvas_item_effective_z", a))
	var zb: int = int(mr.call("_canvas_item_effective_z", b))
	if za != zb:
		return za > zb
	return a.is_greater_than(b)


func _point_where_chip_is_drawn(icon: Node2D, want_fid: String) -> Vector2:
	# A pixel whose real pick is this formation. Plate, bars, and the
	# designation glyph (including the right rim). No skip when none exists.
	if icon == null or not is_instance_valid(icon) or want_fid.is_empty():
		return Vector2(INF, INF)
	var xf: Transform2D = icon.get_global_transform()
	var worlds: Array = []
	var desig: Node = icon.get_node_or_null("Designation")
	if desig is Node2D:
		var d_xf: Transform2D = (desig as Node2D).get_global_transform()
		worlds.append((desig as Node2D).global_position)
		var mr := _map_renderer()
		if mr != null and mr.has_method("_chip_text_glyph_local_rect"):
			var grect: Rect2 = mr.call("_chip_text_glyph_local_rect", desig) as Rect2
			if grect.size.x > 0.0 and grect.size.y > 0.0:
				var mid := grect.position + grect.size * 0.5
				var right := Vector2(grect.position.x + grect.size.x - 0.6, grect.position.y + grect.size.y * 0.5)
				worlds.append(d_xf * mid)
				worlds.append(d_xf * right)
				worlds.append(d_xf * Vector2(grect.position.x + grect.size.x * 0.85, mid.y))
	worlds.append(xf * Vector2(0.0, 0.0))
	worlds.append(xf * Vector2(20.0, -20.0))
	worlds.append(xf * Vector2(-20.0, -20.0))
	worlds.append(xf * Vector2(24.0, 0.0))
	worlds.append(xf * Vector2(21.2, 33.8))
	var step := 4
	while step >= 1:
		# Plate is 44×40 at (−22,−20); ink grows two local px past that.
		# y=-22 is a real GER corner. Do not start the scan below it.
		var ly: int = -22
		while ly <= 34:
			var lx: int = -24
			while lx <= 26:
				worlds.append(xf * Vector2(float(lx), float(ly)))
				lx += step
			ly += step
		var bx: int = -22
		while bx <= 22:
			worlds.append(xf * Vector2(float(bx), 27.0))
			bx += step
		for world_v in worlds:
			var world: Vector2 = world_v as Vector2
			if _pick_fid_at(_map_renderer(), world) == want_fid:
				return world
		if step == 1:
			break
		step = int(step / 2)
		worlds.clear()
	return Vector2(INF, INF)


func _first_owned_point(points: Array, want_fid: String) -> Vector2:
	if want_fid.is_empty():
		return Vector2(INF, INF)
	for world_v in points:
		var world: Vector2 = world_v as Vector2
		if _pick_fid_at(_map_renderer(), world) == want_fid:
			return world
	return Vector2(INF, INF)


func _nld_div1_east_pixel(icon: Node2D, want_fid: String) -> Vector2:
	# East half of NLD Div 1. +20 world px is another wing on the live map.
	if icon == null or not is_instance_valid(icon):
		return Vector2(INF, INF)
	var xf: Transform2D = icon.get_global_transform()
	var ly := -8
	while ly <= 34:
		var lx := 12
		while lx <= 28:
			var world: Vector2 = xf * Vector2(float(lx), float(ly))
			if _pick_fid_at(_map_renderer(), world) == want_fid:
				return world
			lx += 2
		ly += 2
	return Vector2(INF, INF)


func _world_in_icon_stat_bars_or_local(icon: Node2D, world: Vector2) -> bool:
	if _world_in_icon_stat_bars(icon, world):
		return true
	if icon == null or not is_instance_valid(icon):
		return false
	var xf: Transform2D = icon.get_global_transform()
	var local: Vector2 = xf.affine_inverse() * world
	return local.x >= -22.5 and local.x <= 22.5 and local.y >= 19.5 and local.y <= 34.5


func _other_plate_owns(world: Vector2, self_icon: Node2D) -> bool:
	var mr := _map_renderer()
	if mr == null or not ("_demo_unit_icon_pids" in mr):
		return false
	for id_v in mr._demo_unit_icon_pids:
		var id: int = int(id_v)
		if not mr.has_method("_iter_demo_unit_icons_at_pid"):
			continue
		for c_v in mr.call("_iter_demo_unit_icons_at_pid", id) as Array:
			var icon: Node2D = c_v as Node2D
			if icon == null or icon == self_icon or not is_instance_valid(icon) or not icon.visible:
				continue
			if bool(icon.get_meta("sea_nation_disk", false)):
				continue
			if mr.has_method("_world_in_unit_plate_or_bars"):
				if bool(mr.call("_world_in_unit_plate_or_bars", world, icon)):
					return true
			elif _world_in_icon_painted(icon, world):
				return true
	return false


func _collect_land_air_counters() -> Array:
	var out: Array = []
	var mr := _map_renderer()
	if mr == null or not ("_demo_unit_icon_pids" in mr):
		return out
	for id_v in mr._demo_unit_icon_pids:
		var id: int = int(id_v)
		if not mr.has_method("_iter_demo_unit_icons_at_pid"):
			continue
		for c_v in mr.call("_iter_demo_unit_icons_at_pid", id) as Array:
			var icon: Node2D = c_v as Node2D
			if icon == null or not is_instance_valid(icon) or not icon.visible:
				continue
			if bool(icon.get_meta("sea_nation_disk", false)):
				continue
			var fo: Object = null
			if mr.has_method("_formation_from_demo_icon"):
				fo = mr.call("_formation_from_demo_icon", icon)
			if fo == null:
				continue
			var tag := str(fo.country_tag).strip_edges().to_upper() if "country_tag" in fo else ""
			var ftype := str(fo.formation_type) if "formation_type" in fo else ""
			if ftype == "fleet" or ftype == "task_force" or ftype == "ship":
				continue
			var fname := str(fo.name) if "name" in fo else ""
			var fid := str(fo.formation_id) if "formation_id" in fo else ""
			var pos: Vector2 = icon.global_position
			if mr.has_method("_demo_unit_icon_world_pos"):
				pos = mr.call("_demo_unit_icon_world_pos", icon, id) as Vector2
			out.append({
				"tag": tag,
				"type": ftype,
				"name": fname,
				"fid": fid,
				"pos": pos,
				"pid": int(fo.stationed_province_id) if "stationed_province_id" in fo else id,
				"ord": _counter_ordinal(fname, fid),
				"icon": icon,
			})
	return out


func _counter_ordinal(n: String, fid: String) -> int:
	var from_name: int = _trailing_int_token(n)
	if from_name >= 0:
		return from_name
	return _trailing_int_token(fid)


func _trailing_int_token(s: String) -> int:
	var n: String = s.strip_edges()
	if n.is_empty():
		return -1
	var i: int = n.length() - 1
	while i >= 0 and n.unicode_at(i) >= 48 and n.unicode_at(i) <= 57:
		i -= 1
	if i == n.length() - 1:
		return -1
	return int(n.substr(i + 1))


func _match_land_air(counters: Array, tag: String, ftype: String, ord: int) -> Dictionary:
	var best: Dictionary = {}
	for c_v in counters:
		var c: Dictionary = c_v as Dictionary
		if str(c.get("tag", "")) != tag:
			continue
		if str(c.get("type", "")) != ftype:
			continue
		if int(c.get("ord", -99)) != ord:
			continue
		best = c
		break
	return best


func _province_world(pid: int) -> Vector2:
	var mr := _map_renderer()
	if mr != null and "province_centroids" in mr and mr.province_centroids.has(pid):
		return mr.province_centroids[pid] as Vector2
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_centroid"):
		return mm.call("get_province_centroid", pid) as Vector2
	return Vector2.ZERO


func _write_clicks_md() -> void:
	DirAccess.make_dir_recursive_absolute(REPO_DIR)
	var path := "%s/CLICKS_DUMP.md" % REPO_DIR
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("# FLEET-2b live-scale clicks\n\n")
	f.store_string("xvfb 1280x740 · GER · Europe Home · world_accurate. NOT live Play.\n\n")
	f.store_string("Topmost painted *pixels*: plate, bars, or glyph ink (not a fat empty label AABB). Rank is the hit piece's CanvasItem z (child z included, so StatBars and text at z=3 beat any NationPlate at z=-1), then scene-tree order. Ownership block is halo-only (no painted pixels under the click).\n\n")
	f.store_string("| click | result |\n|---|---|\n")
	for line_v in _click_log:
		var line := str(line_v)
		f.store_string("| `%s` | logged |\n" % line.replace("|", "/"))
	f.close()
	_log("EOA_FLEET2_LIVE who=clicks_md path=%s n=%d" % [path, _click_log.size()])


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
	var fid := str(icon.get_meta("formation_id", ""))
	var fo: Variant = icon.get_meta("formation") if icon.has_meta("formation") else null
	if fo is Object and "formation_id" in fo:
		fid = str((fo as Object).formation_id)
	var r: float = 0.0
	if icon.has_meta("sea_nation_radius"):
		r = float(icon.get_meta("sea_nation_radius"))
	var hit: float = r
	if mr != null and mr.has_method("_demo_unit_icon_hit_radius_world"):
		hit = float(mr.call("_demo_unit_icon_hit_radius_world", 1.0, icon))
	out[tag] = {
		"pos": pos,
		"label": lab,
		"fid": fid,
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
			"EOA_FLEET2_LIVE who=plate sea=%s tag=%s fid=%s world=%.1f,%.1f r=%.2f hit=%.2f scale=%.3f vis=%s parent=%s label='%s' name=%s"
			% [
				who, str(k), str(rec.get("fid", "")), p.x, p.y, float(rec.get("r", 0.0)), float(rec.get("hit", 0.0)),
				float(rec.get("scale", 0.0)), str(rec.get("visible", false)),
				str(rec.get("parent", "")), str(rec.get("label", "")), str(rec.get("name", "")),
			]
		)


func _world_to_screen(world: Vector2) -> Vector2:
	var cam := _camera()
	if cam != null:
		return cam.get_canvas_transform() * world
	return world


func _screen_to_world(screen: Vector2) -> Vector2:
	var cam := _camera()
	if cam != null:
		return cam.get_canvas_transform().affine_inverse() * screen
	return screen


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
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/fleet2b"):
		img.save_png("/opt/cursor/artifacts/fleet2b/%s.png" % name)
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
	DisplayServer.window_set_position(Vector2i(0, 29))
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
