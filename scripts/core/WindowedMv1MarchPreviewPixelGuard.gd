extends SceneTree

## WINDOWED MV-1 march-preview pixel guard. xvfb / llvmpipe is NOT live Play.
## Last slice xvfb OpenGL missed a live Vulkan regression — label evidence
## honestly. Gameplay UI only: MarchPreviewLine present on hover, gone after
## unhover. Does not touch roads / borders / labels / InfrastructureOverlay.
##
##   tools/eoa_mv1_pixel_guard.sh
##   xvfb-run -a -s "-screen 0 1600x900x24" tools/run_godot.sh \
##     -s res://scripts/core/WindowedMv1MarchPreviewPixelGuard.gd

const KOELN := 710417
const BONN := 710416
const LEV := 710418
const FRA_FRONT := 710739
const MID_ZOOM := 1.15
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 36
const RSS_LIMIT_MB := 3000

enum Phase {
	WAIT_MAP,
	SETTLE,
	SELECT,
	HOVER,
	UNHOVER,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.SELECT
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _rss_start_kb: int = 0
var _rss_peak_kb: int = 0
var _fid: String = ""
var _hover_ok: bool = false
var _unhover_ok: bool = false
var _chip_text: String = ""


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedMv1MarchPreviewPixelGuard: DisplayServer=%s (xvfb NOT live Play / NOT Vulkan product)" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_out_dir = OS.get_environment("EOA_MV1_PIXEL_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-mv1-pixel"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/mv1-preview")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	_rss_start_kb = _rss_kb()
	_rss_peak_kb = _rss_start_kb
	_log("EOA_MV1_PIXEL_GUARD who=guard.boot out=%s rss_kb=%d (NOT live Play)" % [_out_dir, _rss_start_kb])
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail_reasons.append("scene_load_%d" % err)
		_finish(false)
		return
	_phase = Phase.WAIT_MAP
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	_note_rss()
	match _phase:
		Phase.WAIT_MAP:
			_tick_wait_map()
		Phase.SETTLE:
			_reassert_camera()
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.SELECT:
			_do_select()
		Phase.HOVER:
			_do_hover()
		Phase.UNHOVER:
			_do_unhover()
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
		_log("EOA_MV1_PIXEL_GUARD who=guard.wait_map elapsed=%d closed=%s n=%d (NOT live Play)" % [elapsed, str(_title_has_closed()), _province_count()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("mv1_ready_msec", 0)) == 0:
		root.set_meta("mv1_ready_msec", Time.get_ticks_msec())
		_log("EOA_MV1_PIXEL_GUARD who=guard.map_ready elapsed=%d n=%d" % [elapsed, _province_count()])
		return
	if Time.get_ticks_msec() - int(root.get_meta("mv1_ready_msec", 0)) < 2000:
		return
	_log("EOA_MV1_PIXEL_GUARD who=guard.frame_start elapsed=%d (NOT live Play)" % elapsed)
	_hide_title_overlay()
	_pause_clock_only()
	_lock_camera_fighters()
	_frame_over_koln(MID_ZOOM)
	_go_settle(Phase.SELECT)


func _do_select() -> void:
	var mr := _map_renderer()
	if mr == null:
		_fail_reasons.append("no_map_renderer")
		_finish(false)
		return
	_fid = _park_ger_at_bonn()
	if _fid.is_empty():
		_fail_reasons.append("no_ger_formation")
		_finish(false)
		return
	if "selected_formation_id" in mr:
		mr.set("selected_formation_id", _fid)
	_log("EOA_MV1_PIXEL_GUARD who=guard.select fid=%s (NOT live Play)" % _fid)
	_go_settle(Phase.HOVER)


func _do_hover() -> void:
	var mr := _map_renderer()
	if mr == null or not mr.has_method("mv1_apply_hover_preview"):
		_fail_reasons.append("no_mv1_apply_hover_preview")
		_finish(false)
		return
	var report: Dictionary = mr.call("mv1_apply_hover_preview", LEV) as Dictionary
	_chip_text = str(report.get("chip_text", ""))
	_hover_ok = bool(report.get("line_visible", false)) and int(report.get("point_n", 0)) >= 2
	_log("EOA_MV1_PIXEL_GUARD who=guard.hover report=%s (NOT live Play)" % str(report))
	if not _hover_ok:
		_fail_reasons.append("preview_line_missing_on_hover")
	if not bool(report.get("chip_visible", false)):
		_fail_reasons.append("preview_chip_missing_on_hover")
	if "hops" not in _chip_text and "Can't march" not in _chip_text:
		_fail_reasons.append("chip_text_unexpected")
	_capture("mv1_hover_preview_line_NOT_live_play")
	if mr.has_method("mv1_apply_hover_preview"):
		var cant: Dictionary = mr.call("mv1_apply_hover_preview", FRA_FRONT) as Dictionary
		_log("EOA_MV1_PIXEL_GUARD who=guard.hover_enemy report=%s" % str(cant))
		if bool(cant.get("line_visible", false)):
			_fail_reasons.append("enemy_preview_line")
		if "Can't march" not in str(cant.get("chip_text", "")):
			_fail_reasons.append("enemy_chip_not_cant")
		mr.call("mv1_apply_hover_preview", LEV)
	_go_settle(Phase.UNHOVER)


func _do_unhover() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("mv1_clear_hover_preview"):
		mr.call("mv1_clear_hover_preview")
	if mr != null and mr.has_method("mv1_preview_report"):
		var report: Dictionary = mr.call("mv1_preview_report") as Dictionary
		_unhover_ok = not bool(report.get("line_visible", true)) and int(report.get("point_n", 1)) == 0
		_log("EOA_MV1_PIXEL_GUARD who=guard.unhover report=%s (NOT live Play)" % str(report))
		if not _unhover_ok:
			_fail_reasons.append("preview_line_still_visible")
		if bool(report.get("chip_visible", false)):
			_fail_reasons.append("preview_chip_still_visible")
	else:
		_fail_reasons.append("no_mv1_clear")
	_capture("mv1_unhover_preview_gone_NOT_live_play")
	_finish(_fail_reasons.is_empty())


func _park_ger_at_bonn() -> String:
	var lm := root.get_node_or_null("LeaderManager")
	if lm == null:
		return ""
	if lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var picked := ""
	if "formations" in lm:
		for fid_v in lm.formations.keys():
			var f: Object = lm.formations[fid_v]
			if f == null:
				continue
			var tag := str(f.get("country_tag")).strip_edges().to_upper()
			var ft := str(f.get("formation_type")) if "formation_type" in f else ""
			if tag != "GER":
				continue
			if ft != "" and ft != "division":
				continue
			f.set("stationed_province_id", BONN)
			picked = str(fid_v)
			break
	if picked.is_empty():
		var scr: Script = load("res://scripts/formations/Formation.gd") as Script
		if scr == null:
			return ""
		var f2: Object = scr.new()
		if f2 == null:
			return ""
		picked = "mv1_pixel_ger"
		f2.set("formation_id", picked)
		f2.set("country_tag", "GER")
		f2.set("formation_type", "division")
		f2.set("design_id", "infantry_1936")
		f2.set("stationed_province_id", BONN)
		f2.set("name", "GER MV-1 pixel")
		if "formations" in lm:
			lm.formations[picked] = f2
	return picked


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _province_count() < 3000:
		return false
	if _map_renderer() == null:
		return false
	if _camera() == null:
		return false
	return true


func _title_has_closed() -> bool:
	var tm := _time_manager()
	if tm != null and tm.has_method("living_title_has_closed"):
		if bool(tm.call("living_title_has_closed")):
			return true
	var tr := _find_named("TestRunner")
	if tr != null and bool(tr.get_meta("eoa_living_title_closed", false)):
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


func _province_count() -> int:
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _dismiss_title_if_needed() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if bool(boot.get("_closed")):
		_mark_title_closed()
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	if not bool(boot.get("_closed")) and boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")
	if bool(boot.get("_closed")):
		_mark_title_closed()


func _hide_title_overlay() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if "visible" in boot:
		boot.set("visible", false)
	if boot is CanvasItem:
		(boot as CanvasItem).visible = false
	if boot is CanvasLayer:
		(boot as CanvasLayer).visible = false
	if "_closed" in boot:
		boot.set("_closed", true)
	_mark_title_closed()


func _mark_title_closed() -> void:
	var tm := _time_manager()
	if tm != null and tm.has_method("mark_living_title_closed"):
		tm.call("mark_living_title_closed")
	var tr := _find_named("TestRunner")
	if tr != null:
		tr.set_meta("eoa_living_title_closed", true)
	if current_scene != null:
		current_scene.set_meta("eoa_living_title_closed", true)


func _time_manager() -> Node:
	if root != null:
		var tm: Node = root.get_node_or_null("TimeManager")
		if tm != null:
			return tm
	return _find_named("TimeManager")


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _pause_clock_only() -> void:
	var tm := root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)
	elif tm != null and "paused" in tm:
		tm.set("paused", true)


func _lock_camera_fighters() -> void:
	var mr := _map_renderer()
	if mr != null:
		mr.set("_europe_focus_retry", 99)
		mr.set("_close_camera_locked", true)
	var tr := _find_named("TestRunner")
	if tr != null and tr.has_method("set_process"):
		tr.set_process(false)
	var cc := _find_named("CameraController")
	if cc != null:
		if "enable_pan" in cc:
			cc.set("enable_pan", false)
		if "enable_zoom" in cc:
			cc.set("enable_zoom", false)
		cc.set_process(false)


func _frame_over_koln(zoom: float) -> void:
	var pos := _koln_world()
	_apply_camera(pos, zoom)
	var mr := _map_renderer()
	if mr != null and "info_panel" in mr:
		var ip: Variant = mr.get("info_panel")
		if ip is Control:
			(ip as Control).visible = false


func _apply_camera(pos: Vector2, zoom: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	cam.zoom = Vector2(zoom, zoom)
	cam.global_position = pos
	cam.reset_smoothing()
	if cam.has_method("force_update_scroll"):
		cam.call("force_update_scroll")
	cam.enabled = true
	cam.make_current()


func _reassert_camera() -> void:
	_apply_camera(_koln_world(), MID_ZOOM)


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var cam := mr.get_node_or_null("MapCamera") as Camera2D
		if cam != null:
			return cam
	var vp := root.get_viewport()
	if vp != null:
		return vp.get_camera_2d()
	return null


func _koln_world() -> Vector2:
	var mm := root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", KOELN)
		if c != Vector2.ZERO:
			return c
	return Vector2(4254.32 * 1.728, 944.10 * 1.728)


func _capture(name: String) -> void:
	_reassert_camera()
	RenderingServer.force_draw()
	_reassert_camera()
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
	_captures.append(path)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/mv1-preview"):
		img.save_png("/opt/cursor/artifacts/mv1-preview/%s.png" % name)
	_log("EOA_MV1_PIXEL_GUARD who=guard.capture name=%s path=%s (xvfb NOT live Play)" % [name, path])


func _rss_kb() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return 0
	var text := f.get_as_text()
	f.close()
	for line in text.split("\n"):
		if line.begins_with("VmRSS:"):
			var bits: PackedStringArray = line.split(" ", false)
			if bits.size() >= 2:
				return int(bits[1])
	return 0


func _note_rss() -> void:
	var kb := _rss_kb()
	if kb > _rss_peak_kb:
		_rss_peak_kb = kb


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	_note_rss()
	var rss_mb := float(_rss_peak_kb) / 1024.0
	if rss_mb >= float(RSS_LIMIT_MB):
		_fail_reasons.append("rss_over_3gb")
		ok = false
	var result := "PASS" if ok else "FAIL"
	_log(
		"WindowedMv1MarchPreviewPixelGuard: RESULT=%s hover=%s unhover=%s chip=%s rss_mb=%.1f peak_kb=%d captures=%s reasons=%s (xvfb NOT live Play)"
		% [
			result,
			str(_hover_ok),
			str(_unhover_ok),
			_chip_text,
			rss_mb,
			_rss_peak_kb,
			str(_captures),
			str(_fail_reasons),
		]
	)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
