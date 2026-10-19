extends SceneTree

## ATLAS-1 live Ruhr labels after Begin, with real unit/air counters on.
## Isolated CityLabelsLayer tests pan onto Essen and pass empty counter
## overrides — that is not the live Home zoom-in path. This boots TestScenario.
##
##   EOA_SMOKE_AUTO_BEGIN=1 tools/run_godot.sh --headless --path . \
##     --resolution 1280x800 -s res://scripts/core/HeadlessAtlas1LiveRuhrTest.gd

const ESSEN := 710403
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 30
## Play 59c85d54 cameras (RESULT_6702). Wheel-notch stand-ins for 1.264/1.572/3.019.
const LIVE_ZOOMS: Array[float] = [1.270, 1.578, 3.031]
const PLAY_Z_LABEL := 1.022
const PLAY_CAM_LABEL := Vector2(7557.27, 1546.63)
const PLAY_CAMS: Array[Vector2] = [
	Vector2(7521.68, 1557.15),
	Vector2(7493.04, 1565.78),
	Vector2(7432.08, 1582.48),
]
const VP := Vector2(1280, 800)
const ZOOM_SLACK := 0.14
## Play parked the mouse off-map so no tooltip; wheel is not re-aimed at Essen.
const PLAY_WHEEL_SCREEN := Vector2(500, 85)
## Play lbl.py: |label-centre − dot|. About 15 px after compact sit.
const ANCHOR_MAX_PX := 16.0
const ORDER_SLACK_PX := 8.0
const STABLE_SLACK_PX := 3.0
const RUHR_CORE := ["Essen", "Duisburg", "Düsseldorf", "Dortmund", "Köln"]
var _wheel_screen := PLAY_WHEEL_SCREEN
var _home_zoom := 0.0
var _in_offsets: Dictionary = {}
var _phase_out := false
var _did_z1 := false

var _failures := 0
var _phase := 0
var _t0_msec := 0
var _last_wait_log := -1
var _settle_left := 0
var _zoom_i := 0
var _home_pos := Vector2.ZERO
var _lock_pos := Vector2.ZERO
var _lock_zoom := 0.0
var _focus_world := Vector2.ZERO
var _out_dir := ""


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAtlas1LiveRuhrTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAtlas1LiveRuhrTest: ", msg)


func _start() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_out_dir = OS.get_environment("EOA_ATLAS1_EVIDENCE").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-atlas1-live-ruhr"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail("scene_load_%d" % err)
		_finish()
		return
	_phase = 1
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	if _phase == 1:
		_tick_wait_map()
	elif _phase == 2:
		if _zoom_i >= 0 and _zoom_i < LIVE_ZOOMS.size():
			_reassert_locked_zoom(LIVE_ZOOMS[_zoom_i])
		_settle_left -= 1
		if _settle_left <= 0:
			_check_zoom()
	elif _phase == 4:
		_reassert_locked_zoom(PLAY_Z_LABEL)
		_settle_left -= 1
		if _settle_left <= 0:
			_check_z1()
	elif _phase == 3:
		pass


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail("map_timeout after %ds (%s)" % [elapsed, _ready_blocker()])
		_finish()
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		print("ATLAS1 live wait elapsed=%d %s" % [elapsed, _ready_blocker()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	_frame_europe_home()
	var cam := _camera()
	if cam != null:
		_home_pos = cam.global_position
		_home_zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	_ensure_units_on()
	_quiet_boot_fighters()
	# Play RESULT_6702: Home z0.344, mouse parked at (500,85) off-map, then
	# wheel toward the Ruhr. Do NOT re-aim at Essen each notch (that was
	# the old test — cam ~7345,1664 vs Play 7521,1557 at z1.270).
	var essen_w := _essen_world()
	_wheel_screen = PLAY_WHEEL_SCREEN
	_focus_world = essen_w
	var under_mouse := _world_under_screen(PLAY_WHEEL_SCREEN)
	print("ATLAS1 live map_ready home=%.1f,%.1f home_z=%.3f wheel=%s under_mouse=%.1f,%.1f essen=%.1f,%.1f dist_mouse=%.1f units=%d layers=%d" % [
		_home_pos.x, _home_pos.y, _camera_zoom(), str(_wheel_screen),
		under_mouse.x, under_mouse.y, essen_w.x, essen_w.y,
		under_mouse.distance_to(essen_w),
		_visible_unit_count(), _city_layer_count(),
	])
	if _city_layer_count() != 1:
		_fail("CityLabelsLayer count %d want 1 (doubled draw path)" % _city_layer_count())
	if _visible_unit_count() < 1:
		_fail("no live unit/air counters after Begin")
	if _focus_world == Vector2.ZERO:
		_fail("Essen world is zero at Home")
	_zoom_i = 0
	_begin_z1_check()


func _begin_z1_check() -> void:
	_restore_home()
	_park_mouse()
	_apply_camera(PLAY_CAM_LABEL, PLAY_Z_LABEL)
	_park_mouse()
	_lock_pos = PLAY_CAM_LABEL
	_lock_zoom = PLAY_Z_LABEL
	_settle_left = SETTLE_FRAMES
	_phase = 4
	print("ATLAS1 live frame want_z=%.3f cam_z=%.3f cam=%.1f,%.1f (Düsseldorf at z1.0)" % [
		PLAY_Z_LABEL, _camera_zoom(), PLAY_CAM_LABEL.x, PLAY_CAM_LABEL.y,
	])


func _begin_zoom() -> void:
	if _zoom_i >= LIVE_ZOOMS.size():
		if not _phase_out:
			_phase_out = true
			_zoom_i = LIVE_ZOOMS.size() - 2
			if _zoom_i < 0:
				_finish()
				return
			_begin_zoom_out()
			return
		_finish()
		return
	var z: float = LIVE_ZOOMS[_zoom_i]
	_restore_home()
	_park_mouse()
	# zstep from Home toward Play's camera, mouse then parked off-map.
	_wheel_from_home_to_play(_zoom_i)
	_apply_camera(PLAY_CAMS[_zoom_i], z)
	_park_mouse()
	var cam := _camera()
	var pos := cam.global_position if cam != null else PLAY_CAMS[_zoom_i]
	_lock_pos = pos
	_lock_zoom = _camera_zoom()
	_sync_live_counters(_lock_zoom)
	_sync_layer_from_camera()
	_settle_left = SETTLE_FRAMES
	_phase = 2
	print("ATLAS1 live frame want_z=%.3f cam_z=%.3f cam=%.1f,%.1f out=%s" % [
		z, _lock_zoom, pos.x, pos.y, str(_phase_out),
	])


func _begin_zoom_out() -> void:
	var z: float = LIVE_ZOOMS[_zoom_i]
	_park_mouse()
	_apply_camera(PLAY_CAMS[_zoom_i], z)
	_park_mouse()
	_lock_pos = PLAY_CAMS[_zoom_i]
	_lock_zoom = z
	_sync_live_counters(z)
	_sync_layer_from_camera()
	_settle_left = SETTLE_FRAMES
	_phase = 2
	print("ATLAS1 live frame want_z=%.3f cam_z=%.3f cam=%.1f,%.1f out=true" % [
		z, _camera_zoom(), _lock_pos.x, _lock_pos.y,
	])


func _check_zoom() -> void:
	var z: float = LIVE_ZOOMS[_zoom_i]
	_reassert_locked_zoom(z)
	var layer := _city_layer()
	if layer == null:
		_fail("CityLabelsLayer missing at z%.3f" % z)
		_zoom_i += 1
		_begin_zoom()
		return
	var live_z := _camera_zoom()
	if not _camera_zoom_stuck(z):
		_fail("MapCamera zoom %.3f want %.3f (layout must follow live camera)" % [live_z, z])
	var layout_z := float(layer.call("last_layout_zoom")) if layer.has_method("last_layout_zoom") else -1.0
	if absf(layout_z - live_z) > ZOOM_SLACK:
		_fail("CityLabelsLayer last_layout_zoom %.3f != camera %.3f" % [layout_z, live_z])
	var placed: Array = layer.call("placed")
	var names := PackedStringArray()
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		names.append(str(p.get("name", "")))
	names.sort()
	var essen_s := Vector2.ZERO
	if layer.has_method("screen_of"):
		essen_s = layer.call("screen_of", ESSEN)
	print("ATLAS1 live z%.3f n=%d counters=%d counters_rect=%d essen_s=%.1f,%.1f names=%s" % [
		z, names.size(), _visible_unit_count(),
		int(layer.call("last_counter_rect_count")) if layer.has_method("last_counter_rect_count") else 0,
		essen_s.x, essen_s.y, ",".join(names),
	])
	if not _has_name(placed, "Essen"):
		_fail("Essen missing at live wheel z%.3f" % z)
	else:
		_pass("Essen labelled at live wheel z%.3f" % z)
	if not _essen_on_screen():
		_fail("Essen world not on screen at live wheel z%.3f" % z)
	else:
		_pass("Essen on screen at live wheel z%.3f" % z)
	for core in RUHR_CORE:
		if core == "Köln":
			if not _has_name(placed, "Köln") and not _has_name(placed, "Cologne"):
				_fail("Köln missing at live wheel z%.3f" % z)
		elif not _has_name(placed, core):
			_fail("%s missing at live wheel z%.3f" % [core, z])
	_check_ruhr_north_south(placed, z)
	if _has_name(placed, "Hamm") and not _has_name(placed, "Essen"):
		_fail("Hamm kept over Essen at live wheel z%.3f" % z)
	if _has_name(placed, "Münster") and not _has_name(placed, "Essen"):
		_fail("Münster kept over Essen at live wheel z%.3f" % z)
	_check_anchor_and_chrome(layer, placed, z)
	if bool(layer.call("has_visual_overlap")):
		_fail("live label overlap at z%.3f: %s" % [z, _overlap_pairs(placed)])
	else:
		_pass("no live label overlap at z%.3f" % z)
	var dups: PackedStringArray = layer.call("duplicate_drawn_names")
	if not dups.is_empty():
		_fail("doubled draws at z%.3f: %s" % [z, ", ".join(dups)])
	else:
		_pass("no doubled names at z%.3f" % z)
	var hwy3 := _hwy3_visible_names()
	if not hwy3.is_empty():
		_fail("HWY-3 hub Labels still visible at z%.3f: %s" % [z, ", ".join(hwy3)])
	else:
		_pass("HWY-3 hub Labels hidden at z%.3f" % z)
	if _city_layer_count() != 1:
		_fail("CityLabelsLayer count %d at z%.3f" % [_city_layer_count(), z])
	var legacy := _legacy_province_name_count()
	if legacy > 0:
		_fail("legacy province-name Labels still visible at z%.3f n=%d (second draw)" % [z, legacy])
	else:
		_pass("no legacy province-name draw at z%.3f" % z)
	var hits: PackedStringArray = layer.call("labels_hit_counters")
	var ruhr_hits := PackedStringArray()
	var covered := PackedStringArray()
	for h in hits:
		var nm := str(h)
		if nm in ["Essen", "Hamm", "Münster", "Dortmund", "Duisburg", "Düsseldorf", "Herne", "Gelsenkirchen", "Köln", "Cologne", "Krefeld", "Mönchengladbach", "Remscheid"]:
			ruhr_hits.append(nm)
		if nm in RUHR_CORE or nm == "Cologne":
			covered.append(nm)
		elif nm in ["Hamm", "Münster", "Herne", "Gelsenkirchen", "Krefeld", "Mönchengladbach", "Remscheid"]:
			covered.append(nm)
	if not covered.is_empty():
		# z 30 draws above chips. A name on its own mark is still the right city.
		var drifted := PackedStringArray()
		for nm3 in covered:
			for p3 in placed:
				if str(p3.get("name", "")) != str(nm3) and not (str(nm3) == "Köln" and str(p3.get("name", "")) == "Cologne"):
					continue
				var d3 := _play_dist(layer, p3)
				if d3 > ANCHOR_MAX_PX:
					drifted.append("%s@%.0fpx" % [str(nm3), d3])
				break
		if not drifted.is_empty():
			_fail("Ruhr labels under live counters at z%.3f: %s" % [z, ", ".join(drifted)])
		else:
			_pass("Ruhr cores by dots over chips at z%.3f (%s)" % [z, ", ".join(covered)])
	elif not ruhr_hits.is_empty():
		_pass("Ruhr cores by dots over chips at z%.3f (%s)" % [z, ", ".join(ruhr_hits)])
	else:
		_pass("Ruhr labels clear of live counters at z%.3f" % z)
	_maybe_shot("live_ruhr_z%s" % str(z).replace(".", ""))
	_record_or_check_stable(layer, placed, z)
	if _phase_out:
		_zoom_i -= 1
		if _zoom_i < 0:
			_finish()
			return
		_begin_zoom_out()
		return
	_zoom_i += 1
	_begin_zoom()


func _names_of(placed: Array) -> PackedStringArray:
	var names := PackedStringArray()
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		names.append(str(p.get("name", "")))
	names.sort()
	return names


func _overlap_pairs(placed: Array) -> String:
	var bits: PackedStringArray = PackedStringArray()
	for i in placed.size():
		var a: Dictionary = placed[i]
		if float(a.get("alpha", 0.0)) < 0.04:
			continue
		var ar: Rect2 = a.get("screen_rect", Rect2())
		var ad: Rect2 = a.get("dot_rect", Rect2())
		for j in range(i + 1, placed.size()):
			var b: Dictionary = placed[j]
			if float(b.get("alpha", 0.0)) < 0.04:
				continue
			var br: Rect2 = b.get("screen_rect", Rect2())
			var bd: Rect2 = b.get("dot_rect", Rect2())
			var hit := ar.grow(4.0).intersects(br.grow(4.0))
			hit = hit or (ad.size.x > 0.5 and br.intersects(ad))
			hit = hit or (bd.size.x > 0.5 and ar.intersects(bd))
			if hit:
				bits.append(
					"%s@%.0f,%.0f,%.0fx%.0f/%s@%.0f,%.0f,%.0fx%.0f"
					% [
						str(a.get("name", "")), ar.position.x, ar.position.y, ar.size.x, ar.size.y,
						str(b.get("name", "")), br.position.x, br.position.y, br.size.x, br.size.y,
					]
				)
	return ", ".join(bits)


func _has_name(placed: Array, want: String) -> bool:
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		if str(p.get("name", "")) == want:
			return true
	return false


func _frame_europe_home() -> void:
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", false)
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_europe_home"):
		mr.call("player_path_europe_home")
	elif mr != null and mr.has_method("center_europe_in_world_view"):
		mr.call("center_europe_in_world_view")


func _quiet_boot_fighters() -> void:
	# Stop TestRunner / CameraController fighting the view, but do NOT pin
	# lock_pixel_guard_camera yet — the play path is wheel-toward-mouse.
	if root != null:
		root.set_meta("eoa_rx1_pixel_lock_camera", false)
	var tr := _find_named("TestRunner")
	if tr != null:
		tr.set_process(false)
		tr.set_physics_process(false)
		tr.process_mode = Node.PROCESS_MODE_DISABLED
	var cc := _find_named("CameraController")
	if cc != null:
		if "enable_pan" in cc:
			cc.set("enable_pan", false)
		if "enable_zoom" in cc:
			cc.set("enable_zoom", false)
		cc.set_process(false)
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_hold_camera_until_msec", 0)
		if mr.has_method("_unlock_close_camera"):
			mr.call("_unlock_close_camera")


func _ensure_units_on() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", true)
	if mr != null and mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint")


func _wheel_to(target_zoom: float) -> void:
	# Fixed off-map mouse. Never re-aim at Essen (that packed a different cam).
	_wheel_to_screen(_wheel_screen, target_zoom)


func _wheel_to_screen(screen: Vector2, target_zoom: float) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_wheel_toward_screen"):
		mr.call("player_path_wheel_toward_screen", screen, target_zoom)
		return
	var cam := _camera()
	if cam != null:
		cam.zoom = Vector2(target_zoom, target_zoom)


func _restore_home() -> void:
	_frame_europe_home()
	var cam := _camera()
	if cam != null and _home_pos != Vector2.ZERO and _home_zoom > 0.04:
		cam.position_smoothing_enabled = false
		cam.zoom = Vector2(_home_zoom, _home_zoom)
		cam.global_position = _home_pos
		cam.reset_smoothing()


func _park_mouse() -> void:
	_wheel_screen = PLAY_WHEEL_SCREEN
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.warp_mouse(Vector2i(int(PLAY_WHEEL_SCREEN.x), int(PLAY_WHEEL_SCREEN.y)))


func _wheel_from_home_to_play(idx: int) -> void:
	if idx < 0 or idx >= PLAY_CAMS.size():
		return
	var target_z: float = LIVE_ZOOMS[idx]
	var target_pos: Vector2 = PLAY_CAMS[idx]
	var z0 := _camera_zoom()
	if z0 < 0.04:
		z0 = _home_zoom
	var c0 := _home_pos
	var vp_c := VP * 0.5
	var denom := (1.0 / maxf(z0, 0.04)) - (1.0 / maxf(target_z, 0.04))
	var mouse := PLAY_WHEEL_SCREEN
	if absf(denom) > 0.0001:
		mouse = vp_c + (target_pos - c0) / denom
	_wheel_to_screen(mouse, target_z)


func _play_dist(layer: Node, p: Dictionary) -> float:
	if layer.has_method("play_label_distance_px"):
		return float(layer.call("play_label_distance_px", p))
	if layer.has_method("anchor_distance_px"):
		return float(layer.call("anchor_distance_px", p))
	return (p.get("screen_offset", Vector2.ZERO) as Vector2).length()


func _compass(off: Vector2) -> String:
	if off.length() < 2.0:
		return "on"
	if absf(off.x) >= absf(off.y) * 1.4:
		return "W" if off.x < 0.0 else "E"
	if absf(off.y) >= absf(off.x) * 1.4:
		return "N" if off.y < 0.0 else "S"
	var ew := "W" if off.x < 0.0 else "E"
	var ns := "N" if off.y < 0.0 else "S"
	return ns + ew


func _check_z1() -> void:
	_reassert_locked_zoom(PLAY_Z_LABEL)
	var layer := _city_layer()
	if layer == null:
		_fail("CityLabelsLayer missing at z%.3f" % PLAY_Z_LABEL)
		_begin_zoom()
		return
	var placed: Array = layer.call("placed")
	if not _has_name(placed, "Düsseldorf"):
		_fail("Düsseldorf missing at live wheel z%.3f (must label at z1.0)" % PLAY_Z_LABEL)
	else:
		_pass("Düsseldorf labelled at live wheel z%.3f" % PLAY_Z_LABEL)
	_maybe_shot("live_ruhr_z1022")
	_did_z1 = true
	_begin_zoom()


func _record_or_check_stable(layer: Node, placed: Array, z: float) -> void:
	var key_z := "%.3f" % z
	var now: Dictionary = {}
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var nm := str(p.get("name", ""))
		if nm != "Köln" and nm != "Cologne" and nm != "Herne" and not (nm in RUHR_CORE):
			continue
		var off := Vector2.ZERO
		if layer.has_method("play_label_offset_px"):
			off = layer.call("play_label_offset_px", p) as Vector2
		else:
			off = p.get("screen_offset", Vector2.ZERO) as Vector2
		now[nm] = off
	if not _phase_out:
		_in_offsets[key_z] = now
		return
	if not _in_offsets.has(key_z):
		return
	var prev: Dictionary = _in_offsets[key_z]
	for nm2 in now.keys():
		if not prev.has(nm2):
			continue
		var a: Vector2 = prev[nm2]
		var b: Vector2 = now[nm2]
		var d := a.distance_to(b)
		if d > STABLE_SLACK_PX:
			_fail("%s zoom-in vs zoom-out at z%s offset delta %.1f px (in %.1f,%.1f out %.1f,%.1f)" % [
				str(nm2), key_z, d, a.x, a.y, b.x, b.y,
			])
		else:
			_pass("%s stable in/out at z%s (delta %.1f)" % [str(nm2), key_z, d])


func _world_to_screen(world: Vector2) -> Vector2:
	var cam := _camera()
	if cam == null or world == Vector2.ZERO:
		return Vector2.ZERO
	return cam.get_canvas_transform() * world


func _world_under_screen(screen: Vector2) -> Vector2:
	var cam := _camera()
	if cam == null:
		return Vector2.ZERO
	var z := maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	if z < 0.04:
		return Vector2.ZERO
	return cam.global_position + (screen - VP * 0.5) / z


func _essen_on_screen() -> bool:
	var layer := _city_layer()
	if layer == null or not layer.has_method("screen_of"):
		return false
	var s: Vector2 = layer.call("screen_of", ESSEN)
	return s.x >= 8.0 and s.y >= 8.0 and s.x <= VP.x - 8.0 and s.y <= VP.y - 8.0


func _check_anchor_and_chrome(layer: Node, placed: Array, z: float) -> void:
	var required: Dictionary = {"Essen": true, "Cologne": true}
	for core in RUHR_CORE:
		required[core] = true
	var chrome: Array = []
	if layer.has_method("chrome_screen_rects"):
		chrome = layer.call("chrome_screen_rects")
	var hits: PackedStringArray = PackedStringArray()
	if layer.has_method("labels_hit_chrome"):
		hits = layer.call("labels_hit_chrome", chrome)
	for h in hits:
		var nm := str(h)
		if required.has(nm):
			_fail("%s hidden under UI/tooltip at live wheel z%.3f" % [nm, z])
	var worst := 0.0
	var worst_nm := ""
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var nm2 := str(p.get("name", ""))
		if not required.has(nm2):
			continue
		var dist := _play_dist(layer, p)
		var edge := 0.0
		var off := Vector2.ZERO
		if layer.has_method("play_label_offset_px"):
			off = layer.call("play_label_offset_px", p) as Vector2
		if layer.has_method("drawn_nearest_edge_px"):
			edge = float(layer.call("drawn_nearest_edge_px", p))
		var pack := 0.0
		if layer.has_method("anchor_distance_px"):
			pack = float(layer.call("anchor_distance_px", p))
		print("ATLAS1 live play %s z%.3f center=%.1f edge=%.1f pack_edge=%.1f offset=%.1f,%.1f %s" % [
			nm2, z, dist, edge, pack, off.x, off.y, _compass(off),
		])
		if nm2 == "Düsseldorf" and off.x < -20.0:
			_fail("Düsseldorf %.0f W at z%.3f — flush-left into NL" % [absf(off.x), z])
		if dist > worst:
			worst = dist
			worst_nm = nm2
		if dist > ANCHOR_MAX_PX:
			_fail("%s is %.1f px from its dot at live wheel z%.3f (Play centre)" % [nm2, dist, z])
	if worst <= ANCHOR_MAX_PX and not worst_nm.is_empty():
		_pass("Ruhr cores within %.0f px of their dots at z%.3f (worst %s %.1f)" % [ANCHOR_MAX_PX, z, worst_nm, worst])


func _check_ruhr_north_south(placed: Array, z: float) -> void:
	# Label centres. Düsseldorf jumping ~60 px north of its mark reads as a
	# city north of Essen/Duisburg; slack is only a few pixels of beside-dot sit.
	var ok := true
	ok = _require_north_of(placed, "Duisburg", "Düsseldorf", z) and ok
	ok = _require_north_of(placed, "Essen", "Düsseldorf", z) and ok
	ok = _require_north_of(placed, "Düsseldorf", "Köln", z) and ok
	if ok:
		_pass("Ruhr N/S order at live wheel z%.3f" % z)


func _core_label_center_y(placed: Array, want: String) -> float:
	var also := ""
	if want == "Köln":
		also = "Cologne"
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var nm := str(p.get("name", ""))
		if nm != want and nm != also:
			continue
		var rect: Rect2 = p.get("screen_rect", Rect2())
		return rect.get_center().y
	return -1.0e9


func _require_north_of(placed: Array, north_name: String, south_name: String, z: float) -> bool:
	var ny := _core_label_center_y(placed, north_name)
	var sy := _core_label_center_y(placed, south_name)
	if ny < -1.0e8 or sy < -1.0e8:
		return true
	if ny > sy + ORDER_SLACK_PX:
		_fail(
			"%s drawn south of %s at live wheel z%.3f (label centres %.1f vs %.1f)"
			% [north_name, south_name, z, ny, sy]
		)
		return false
	return true


func _hwy3_visible_names() -> PackedStringArray:
	# Only the HWY-3 CanvasLayer Labels. get_hub_city_label_names now proxies
	# ATLAS-1 placed names while CityLabelsLayer owns the map.
	var out := PackedStringArray()
	var mr := _map_renderer()
	if mr == null:
		return out
	var ol: Node = null
	if mr.has_method("get_overlay_layer"):
		ol = mr.call("get_overlay_layer", "InfrastructureOverlayLayer")
	if ol == null:
		return out
	var layer: Node = ol.get_node_or_null("Hwy3HubCityLabels")
	if layer == null or not (layer is CanvasItem) or not (layer as CanvasItem).visible:
		return out
	for ch in layer.get_children():
		if ch is Label and is_instance_valid(ch) and (ch as Label).visible:
			var nm := str((ch as Label).text).strip_edges()
			if not nm.is_empty():
				out.append(nm)
	return out


func _apply_camera(pos: Vector2, zoom: float) -> void:
	_lock_pos = pos
	_lock_zoom = zoom
	var cam := _camera()
	if cam != null:
		cam.position_smoothing_enabled = false
		cam.zoom = Vector2(zoom, zoom)
		cam.global_position = pos
		cam.reset_smoothing()
		cam.enabled = true
		cam.make_current()
	_sync_live_counters(zoom)
	_sync_layer_from_camera()


func _reassert_locked_zoom(zoom: float) -> void:
	var pos := _lock_pos
	if pos == Vector2.ZERO:
		pos = _home_pos
	var z := _lock_zoom if _lock_zoom > 0.04 else zoom
	_apply_camera(pos, z)


func _sync_live_counters(zoom: float) -> void:
	var mr := _map_renderer()
	if mr == null:
		return
	if mr.has_method("_sync_unit_counter_paint"):
		mr.call("_sync_unit_counter_paint", zoom)
	if mr.has_method("_refresh_province_detail_visibility"):
		mr.call("_refresh_province_detail_visibility")
	if mr.has_method("_hide_legacy_province_name_labels"):
		mr.call("_hide_legacy_province_name_labels")


func _sync_layer_from_camera() -> void:
	var layer := _city_layer()
	var cam := _camera()
	if layer == null or cam == null or not layer.has_method("sync_view"):
		return
	var z := maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	var vp := VP
	if root != null and root.get_viewport() != null:
		vp = root.get_viewport().get_visible_rect().size
	layer.call("sync_view", z, cam.global_position, vp, true)


func _camera_zoom() -> float:
	var cam := _camera()
	if cam == null:
		return 0.0
	return maxf(absf(cam.zoom.x), absf(cam.zoom.y))


func _camera_zoom_stuck(want: float) -> bool:
	return absf(_camera_zoom() - want) <= ZOOM_SLACK


func _legacy_province_name_count() -> int:
	var mr := _map_renderer()
	if mr != null and mr.has_method("count_visible_province_name_labels"):
		return int(mr.call("count_visible_province_name_labels"))
	return 0


func _essen_world() -> Vector2:
	var layer := _city_layer()
	if layer != null and layer.has_method("world_of"):
		var w: Vector2 = layer.call("world_of", ESSEN)
		if w != Vector2.ZERO:
			return w
	return Vector2.ZERO


func _maybe_shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _lock_zoom > 0.04:
		_reassert_locked_zoom(_lock_zoom)
	RenderingServer.force_draw()
	if _lock_zoom > 0.04:
		_reassert_locked_zoom(_lock_zoom)
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("ATLAS1 live shot %s %dx%d" % [path, img.get_width(), img.get_height()])


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _find_named("LivingTitleBoot") != null:
		return false
	if _province_count() < 3000:
		return false
	if _map_renderer() == null or _camera() == null:
		return false
	if _city_layer() == null:
		return false
	return true


func _ready_blocker() -> String:
	if not _title_has_closed():
		return "title_open"
	if _find_named("LivingTitleBoot") != null:
		return "title_node"
	if _province_count() < 3000:
		return "provinces"
	if _map_renderer() == null:
		return "renderer"
	if _camera() == null:
		return "camera"
	if _city_layer() == null:
		return "city_layer"
	return "ready"


func _title_has_closed() -> bool:
	var tr := _find_named("TestRunner")
	if tr == null:
		tr = current_scene
	if tr != null and bool(tr.get_meta("eoa_living_title_closed", false)):
		return true
	if current_scene != null and bool(current_scene.get_meta("eoa_living_title_closed", false)):
		return true
	var boot := _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	return false


func _dismiss_title_if_needed() -> void:
	var boot := _find_named("LivingTitleBoot")
	if boot == null:
		return
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	elif boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")


func _province_count() -> int:
	var mm := root.get_node_or_null("MapManager") if root != null else null
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _map_renderer() -> Node:
	var nodes := get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0]
	return _find_named("WorldMap")


func _city_layer() -> Node:
	return _find_named("CityLabelsLayer")


func _city_layer_count() -> int:
	if root == null:
		return 0
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == null:
			continue
		if str(node.name) == "CityLabelsLayer":
			n += 1
		for ch in node.get_children():
			stack.append(ch)
	return n


func _visible_unit_count() -> int:
	var mr := _map_renderer()
	if mr != null and mr.has_method("_count_visible_unit_icons"):
		return int(mr.call("_count_visible_unit_icons"))
	return 0


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam := mr.get_node_or_null("MapCamera") as Camera2D
		if cam != null:
			return cam
	if root != null and root.get_viewport() != null:
		return root.get_viewport().get_camera_2d()
	return null


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _finish() -> void:
	_phase = 3
	var ok := _failures == 0
	print("HeadlessAtlas1LiveRuhrTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAtlas1LiveRuhrTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
