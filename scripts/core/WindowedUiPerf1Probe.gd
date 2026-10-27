extends SceneTree

## UI-PERF-1 windowed probe. gamescope headless 1280x800, F5 GER 1936.
## Not live Play. Times boot/frames, map-mode chips and F-keys, Tech, Prod, L, A3.
##
##   tools/eoa_uiperf1_probe.sh ~/uiperf1/evidence/before_1.json

const PLAY := Vector2i(1280, 800)
const WAIT_MAP_SECS := 420
const FRAME_SAMPLES := 40
const SWITCH_FRAMES := 6
const MODE_BAR_MEDIAN_MS := 250.0
const MODE_BAR_WORST_MS := 500.0
const TECH_BAR_MS := 300.0
const PROD_BAR_MS := 300.0
const L_BAR_MS := 200.0
const PROD_CYCLES := 5
## Side-task main 477bdf00 median boot_chips_ms 34851 + 300.
## This probe's boot_ms stops at map-ready + 8 frames (boot_map), which sat
## ~650 ms under boot_chips on that sample. 3a5042e1 warms every mode on the
## boot frame and lands near 39 s, over this bar.
const BOOT_BAR_MS := 35151
const WARM_FRAME_BAR_MS := 100.0
const WARM_CACHE_MIN := 3000

const CHIP_LABELS := {
	"political": "Political",
	"strain": "Strain",
	"vitality": "Vitality",
	"development": "Development",
	"supply": "Supply",
	"resources": "Resources",
	"states": "States",
	"terrain": "Terrain",
	"infra": "Infra",
	"naval": "Naval",
}

var _t0_msec: int = 0
var _out_path: String = ""
var _log_path: String = ""
var _failures: int = 0
var _last_wait_log: int = -1
var _report: Dictionary = {}
var _lines: PackedStringArray = PackedStringArray()
var _last_click_t0: int = 0
var _last_click_warp_us: int = 0
var _last_click_press_us: int = 0
var _last_click_release_us: int = 0


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	call_deferred("_start")


func _start() -> void:
	_parse_out()
	_note("UI_PERF1 probe start")
	await _run()
	_finish()


func _parse_out() -> void:
	_out_path = OS.get_environment("HOME") + "/uiperf1/evidence/probe.json"
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if str(args[i]) == "--out" and i + 1 < args.size():
			_out_path = str(args[i + 1])
			i += 2
			continue
		i += 1
	_log_path = _out_path + ".log"
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())


func _run() -> void:
	var ds := DisplayServer.get_name()
	_note("DisplayServer=%s size_request=%s" % [ds, str(PLAY)])
	if ds == "headless":
		_fail("headless_display")
		return
	DisplayServer.window_set_size(PLAY)
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail("scene_load_%d" % err)
		return
	if not await _wait_map_ready():
		return
	_pause_clock()
	var boot_ms := Time.get_ticks_msec() - _t0_msec
	var nprov := _province_count()
	_note("UI_PERF1 boot_ms=%d provinces=%d" % [boot_ms, nprov])
	_report["boot_ms"] = boot_ms
	_report["provinces"] = nprov
	_report["a3"] = _a3_line(nprov)
	_note("UI_PERF1 A3 %s" % str(_report["a3"]))
	var mr_boot := _map_renderer()
	if mr_boot != null and mr_boot.has_method("hold_idle_fill_warm_for_probe"):
		_report["during_warm"] = await _measure_during_warm(mr_boot)
	else:
		_report["during_warm"] = {"skipped": true}
		_note("UI_PERF1 during_warm skipped (no idle fill warm)")
	_flush_report()
	var idle := await _sample_frames(FRAME_SAMPLES)
	_report["idle_frames_ms"] = idle
	_note("UI_PERF1 idle_frames n=%d median=%.1f worst=%.1f" % [idle.size(), _median(idle), _worst(idle)])
	_flush_report()
	var mr := _map_renderer()
	if mr == null:
		_fail("MapRenderer missing")
		return
	_report["switches"] = await _measure_switches(mr)
	_flush_report()
	_report["tech"] = await _measure_tech()
	_flush_report()
	_report["prod"] = await _measure_prod()
	_flush_report()
	_report["L"] = await _measure_l(mr)
	_flush_report()
	_grade()


func _a3_line(nprov: int) -> Dictionary:
	return {
		"city_min_zoom": MapZoomLOD.city_marker_min_zoom_for_board(nprov),
		"site_min_zoom": MapZoomLOD.site_marker_min_zoom_for_board(nprov),
		"cull_threshold": MapZoomLOD.ACCURATE_BOARD_CULL_THRESHOLD,
	}


func _measure_switches(mr: Node) -> Array:
	var out: Array = []
	var cycle := 0
	while cycle < 3:
		cycle += 1
		for mode in ["terrain", "political", "supply", "resources", "states", "infra"]:
			out.append(await _switch_chip(mr, mode, cycle))
		out.append(await _switch_key(mr, "political", KEY_F1, false, false, cycle))
		out.append(await _switch_key(mr, "strain", KEY_F2, false, false, cycle))
		out.append(await _switch_key(mr, "resources", KEY_F9, false, false, cycle))
		out.append(await _switch_key(mr, "terrain", KEY_F9, true, false, cycle))
		out.append(await _switch_key(mr, "states", KEY_F9, false, true, cycle))
		out.append(await _switch_key(mr, "supply", KEY_F5, false, false, cycle))
		_flush_report()
	return out


func _switch_chip(mr: Node, mode: String, cycle: int) -> Dictionary:
	var btn := _mode_button(mode)
	var gen0 := int(mr.get("map_mode_apply_gen"))
	var skips0 := int(mr.get("ui_perf_toolbar_skips"))
	var owns0 := int(mr.get("ui_perf_owns_us"))
	var leg0 := int(mr.get("ui_perf_legend_us"))
	var clicked := false
	var t0 := Time.get_ticks_usec()
	if btn != null:
		clicked = _click_control(btn)
		t0 = _last_click_t0
	else:
		_note("UI_PERF1 chip missing mode=%s" % mode)
	var row := await _collect_switch(mr, t0, gen0, "chip", mode, cycle)
	row["clicked"] = clicked
	row["warp_us"] = _last_click_warp_us
	row["press_us"] = _last_click_press_us
	row["release_us"] = _last_click_release_us
	row["skips"] = int(mr.get("ui_perf_toolbar_skips")) - skips0
	row["owns_us"] = int(mr.get("ui_perf_owns_us")) - owns0
	row["legend_us"] = int(mr.get("ui_perf_legend_us")) - leg0
	_note(_switch_line(row))
	return row


func _switch_key(mr: Node, mode: String, keycode: Key, ctrl: bool, shift: bool, cycle: int) -> Dictionary:
	_release_focus()
	var gen0 := int(mr.get("map_mode_apply_gen"))
	var leg0 := int(mr.get("ui_perf_legend_us"))
	var t0 := Time.get_ticks_usec()
	_tap_key(keycode, ctrl, shift)
	var row := await _collect_switch(mr, t0, gen0, "key", mode, cycle)
	row["legend_us"] = int(mr.get("ui_perf_legend_us")) - leg0
	_note(_switch_line(row))
	return row


func _collect_switch(mr: Node, t0: int, gen0: int, via: String, mode: String, cycle: int) -> Dictionary:
	var frames: Array[float] = []
	var i := 0
	var gen := gen0
	while i < SWITCH_FRAMES:
		var a := Time.get_ticks_usec()
		await process_frame
		frames.append(float(Time.get_ticks_usec() - a) / 1000.0)
		i += 1
		gen = int(mr.get("map_mode_apply_gen"))
		# Stop on the frame that applied the mode. A later idle frame is the
		# normal cadence (~50 ms), not the hitch.
		if gen != gen0:
			break
	var wall := float(Time.get_ticks_usec() - t0) / 1000.0
	var prof: Dictionary = {}
	if "map_mode_switch_profile" in mr:
		prof = (mr.get("map_mode_switch_profile") as Dictionary).duplicate()
	return {
		"cycle": cycle,
		"via": via,
		"mode": mode,
		"live_mode": str(mr.get("current_map_mode")),
		"wall_ms": wall,
		"frame_worst_ms": _worst(frames),
		"frames_ms": frames,
		"applied": gen != gen0,
		"profile": prof,
	}


func _switch_line(row: Dictionary) -> String:
	var prof: Dictionary = row.get("profile", {}) as Dictionary
	return (
		"UI_PERF1 mode=%s via=%s cycle=%d wall_ms=%.1f frame_worst_ms=%.1f applied=%s live=%s fill_us=%s color_us=%s assign_us=%s restore_us=%s stars_us=%s sync_us=%s chip_us=%s supply_ms=%s warp_us=%s press_us=%s release_us=%s skips=%s owns_us=%s legend_us=%s cache_n=%s"
		% [
			str(row.get("mode", "")),
			str(row.get("via", "")),
			int(row.get("cycle", 0)),
			float(row.get("wall_ms", -1.0)),
			float(row.get("frame_worst_ms", -1.0)),
			str(bool(row.get("applied", false))),
			str(row.get("live_mode", "")),
			str(prof.get("fill_us", "")),
			str(prof.get("fill_color_us", "")),
			str(prof.get("fill_assign_us", "")),
			str(prof.get("restore_us", "")),
			str(prof.get("stars_us", "")),
			str(prof.get("sync_us", "")),
			str(prof.get("chip_us", "")),
			str(prof.get("supply_highlight_ms", "")),
			str(row.get("warp_us", "")),
			str(row.get("press_us", "")),
			str(row.get("release_us", "")),
			str(row.get("skips", "")),
			str(row.get("owns_us", "")),
			str(row.get("legend_us", "")),
			str(prof.get("cache_n", "")),
		]
	)


func _measure_tech() -> Dictionary:
	_close_named("TechnologyScreen")
	await process_frame
	var btn := _bar_button("TechnologyButton")
	var t0 := Time.get_ticks_usec()
	var clicked := _click_control(btn)
	var visible_ms := -1.0
	var frames: Array[float] = []
	var footer := ""
	var rows := -1
	var i := 0
	while i < 12:
		var a := Time.get_ticks_usec()
		await process_frame
		frames.append(float(Time.get_ticks_usec() - a) / 1000.0)
		i += 1
		var screen := _live_named("TechnologyScreen")
		if screen != null and _control_visible(screen):
			if visible_ms < 0.0:
				visible_ms = float(Time.get_ticks_usec() - t0) / 1000.0
			footer = _label_text(screen, "FooterLabel")
			var list := screen.find_child("ResearchList", true, false)
			rows = list.get_child_count() if list != null else -1
			if rows >= 10:
				break
	if visible_ms < 0.0:
		visible_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	var raw := footer.find("[color=") >= 0
	var row := {
		"clicked": clicked,
		"visible_ms": visible_ms,
		"frame_worst_ms": _worst(frames),
		"frames_ms": frames,
		"footer": footer,
		"raw_bbcode": raw,
		"rows": rows,
	}
	_note(
		"UI_PERF1 tech clicked=%s visible_ms=%.1f frame_worst_ms=%.1f rows=%d raw_bbcode=%s footer=%s"
		% [str(clicked), visible_ms, float(row["frame_worst_ms"]), rows, str(raw), footer.substr(0, 180)]
	)
	_close_named("TechnologyScreen")
	await process_frame
	return row


func _measure_prod() -> Dictionary:
	var opens: Array = []
	var c := 0
	while c < PROD_CYCLES:
		c += 1
		_close_named("ProductionAssignmentScreen")
		await process_frame
		await process_frame
		var btn := _bar_button("ProductionButton")
		var t0 := Time.get_ticks_usec()
		var clicked := _click_control(btn)
		var open_ms := -1.0
		var frames: Array[float] = []
		var rows := -1
		var i := 0
		while i < 8:
			var a := Time.get_ticks_usec()
			await process_frame
			var dt := float(Time.get_ticks_usec() - a) / 1000.0
			frames.append(dt)
			i += 1
			var screen := _live_named("ProductionAssignmentScreen")
			if screen != null and _control_visible(screen):
				open_ms = float(Time.get_ticks_usec() - t0) / 1000.0
				var list := screen.find_child("FactoryListContent", true, false)
				rows = list.get_child_count() if list != null else -1
				break
		if open_ms < 0.0:
			open_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		var one := {
			"i": c,
			"clicked": clicked,
			"open_ms": open_ms,
			"frame_worst_ms": _worst(frames),
			"rows": rows,
		}
		opens.append(one)
		_note("UI_PERF1 prod i=%d clicked=%s open_ms=%.1f frame_worst_ms=%.1f rows=%d" % [
			c, str(clicked), open_ms, float(one["frame_worst_ms"]), rows,
		])
		var screen_c := _live_named("ProductionAssignmentScreen")
		var close_btn: Button = null
		if screen_c != null:
			close_btn = screen_c.get_node_or_null("TitleBar/CloseButton") as Button
		if close_btn != null:
			_click_control(close_btn)
		else:
			_close_named("ProductionAssignmentScreen")
		await process_frame
		_flush_report()
	# Same-frame Close then Prod. The spaced 5x above did not reproduce a multi-minute hang.
	var live := _live_named("ProductionAssignmentScreen")
	if live == null:
		var open_btn := _bar_button("ProductionButton")
		_click_control(open_btn)
		var w := 0
		while w < 8 and _live_named("ProductionAssignmentScreen") == null:
			await process_frame
			w += 1
		live = _live_named("ProductionAssignmentScreen")
	var close_btn: Button = null
	if live != null:
		close_btn = live.get_node_or_null("TitleBar/CloseButton") as Button
	var t_same := Time.get_ticks_usec()
	if close_btn != null:
		_click_control(close_btn)
	var reopen := _bar_button("ProductionButton")
	var clicked_same := _click_control(reopen)
	var open_ms := -1.0
	var frames: Array[float] = []
	var rows := -1
	var seen_sz := Vector2.ZERO
	var j := 0
	while j < 12:
		var a := Time.get_ticks_usec()
		await process_frame
		frames.append(float(Time.get_ticks_usec() - a) / 1000.0)
		j += 1
		var screen := _live_named("ProductionAssignmentScreen")
		if screen != null:
			seen_sz = screen.size
			if _control_visible(screen):
				open_ms = float(Time.get_ticks_usec() - t_same) / 1000.0
				var list := screen.find_child("FactoryListContent", true, false)
				rows = list.get_child_count() if list != null else -1
				if rows >= 1 or j >= 4:
					break
	if open_ms < 0.0:
		open_ms = float(Time.get_ticks_usec() - t_same) / 1000.0
	var same := {
		"i": 6,
		"clicked": clicked_same,
		"open_ms": open_ms,
		"frame_worst_ms": _worst(frames),
		"rows": rows,
		"same_frame": true,
		"size": [seen_sz.x, seen_sz.y],
	}
	opens.append(same)
	_note("UI_PERF1 prod i=6 same_frame clicked=%s open_ms=%.1f frame_worst_ms=%.1f rows=%d size=%s" % [
		str(clicked_same), open_ms, float(same["frame_worst_ms"]), rows, str(seen_sz),
	])
	_flush_report()
	return {"opens": opens}


func _measure_l(mr: Node) -> Dictionary:
	var samples: Array = []
	var n := 0
	while n < 3:
		n += 1
		_release_focus()
		var t0 := Time.get_ticks_usec()
		_tap_key(KEY_L, false, false)
		var frames: Array[float] = []
		var i := 0
		while i < 3:
			var a := Time.get_ticks_usec()
			await process_frame
			frames.append(float(Time.get_ticks_usec() - a) / 1000.0)
			i += 1
		var wall := float(Time.get_ticks_usec() - t0) / 1000.0
		var one := {"i": n, "wall_ms": wall, "frame_worst_ms": _worst(frames), "frames_ms": frames}
		samples.append(one)
		_note("UI_PERF1 L i=%d wall_ms=%.1f frame_worst_ms=%.1f supply=%s" % [
			n, wall, float(one["frame_worst_ms"]), str(mr.get("supply_mode")),
		])
	return {"samples": samples}


func _measure_during_warm(mr: Node) -> Dictionary:
	mr.call("hold_idle_fill_warm_for_probe")
	var pending_terrain := bool(mr.get("fill_cache_warm_pending"))
	_note("UI_PERF1 during_warm hold pending=%s" % str(pending_terrain))
	var terrain: Dictionary = await _switch_chip(mr, "terrain", 0)
	mr.call("release_idle_fill_warm_for_probe")
	var over := 0
	var frame_max := 0.0
	var supply: Dictionary = {}
	var pending_supply := false
	var supply_clicked := false
	var guard := 0
	while guard < 4000:
		guard += 1
		var frame_ms := await _one_frame_ms()
		var slice_us := int(mr.get("fill_warm_last_frame_us"))
		if slice_us > 0:
			frame_max = maxf(frame_max, frame_ms)
			if frame_ms > WARM_FRAME_BAR_MS:
				over += 1
				_note("UI_PERF1 during_warm frame_ms=%.1f slice_us=%d OVER" % [frame_ms, slice_us])
		var pending := bool(mr.get("fill_cache_warm_pending"))
		if not supply_clicked and int(mr.get("fill_warm_slices")) >= 1 and pending:
			pending_supply = true
			supply = await _switch_chip(mr, "supply", 0)
			supply_clicked = true
			continue
		if supply_clicked and not pending:
			break
		if not pending and not supply_clicked and guard > 60:
			break
	var out := {
		"skipped": false,
		"pending_before_terrain": pending_terrain,
		"terrain": terrain,
		"pending_before_supply": pending_supply,
		"supply": supply,
		"warm_frames_over_100": over,
		"warm_frame_max_ms": frame_max,
		"warm_finished": not bool(mr.get("fill_cache_warm_pending")),
		"slices": int(mr.get("fill_warm_slices")),
		"warm_work_max_us": int(mr.get("fill_warm_frame_max_us")),
	}
	if bool(out["warm_finished"]):
		var back: Dictionary = await _switch_chip(mr, "political", 0)
		out["back_political"] = back
	_note(
		"UI_PERF1 during_warm terrain_cache=%s supply_cache=%s frames_over=%d frame_max=%.1f slices=%d finished=%s"
		% [
			str(_cache_n(terrain)),
			str(_cache_n(supply)),
			over,
			frame_max,
			int(out["slices"]),
			str(bool(out["warm_finished"])),
		]
	)
	return out


func _one_frame_ms() -> float:
	var a := Time.get_ticks_usec()
	await process_frame
	return float(Time.get_ticks_usec() - a) / 1000.0


func _cache_n(row: Dictionary) -> int:
	var prof: Dictionary = row.get("profile", {}) as Dictionary
	return int(prof.get("cache_n", -1))


func _grade() -> void:
	var boot_ms := int(_report.get("boot_ms", 999999))
	var boot_ok := boot_ms <= BOOT_BAR_MS
	if not boot_ok:
		_failures += 1
		_note("UI_PERF1 FAIL boot_ms=%d bar=%d" % [boot_ms, BOOT_BAR_MS])
	var warm_ok := _grade_during_warm()
	var switches: Array = _report.get("switches", []) as Array
	var walls: Array[float] = []
	var frame_over := 0
	var missed := 0
	for row_v in switches:
		var row: Dictionary = row_v
		if not bool(row.get("applied", false)):
			missed += 1
			continue
		var wall := float(row.get("wall_ms", 99999.0))
		walls.append(wall)
		if float(row.get("frame_worst_ms", 99999.0)) > MODE_BAR_WORST_MS or wall > MODE_BAR_WORST_MS:
			frame_over += 1
	var med := _median(walls)
	var worst := _worst(walls)
	var map_ok := missed == 0 and walls.size() > 0 and med <= MODE_BAR_MEDIAN_MS and worst <= MODE_BAR_WORST_MS and frame_over == 0
	if not map_ok:
		_failures += 1
	var tech: Dictionary = _report.get("tech", {}) as Dictionary
	var tech_ok := (
		bool(tech.get("clicked", false))
		and float(tech.get("visible_ms", 99999.0)) <= TECH_BAR_MS
		and not bool(tech.get("raw_bbcode", true))
	)
	if not tech_ok:
		_failures += 1
	var prod_ok := true
	var prod: Dictionary = _report.get("prod", {}) as Dictionary
	for one_v in prod.get("opens", []) as Array:
		var one: Dictionary = one_v
		var open_ms := float(one.get("open_ms", 99999.0))
		if not bool(one.get("clicked", false)):
			prod_ok = false
			continue
		# Spaced Close→Prod is the 300 ms bar. The same-frame cycle is the
		# multi-minute #109 guard: it must finish, and it must not hang.
		if bool(one.get("same_frame", false)):
			if open_ms > 3000.0:
				prod_ok = false
		elif open_ms > PROD_BAR_MS:
			prod_ok = false
	if not prod_ok:
		_failures += 1
	var l_walls: Array[float] = []
	var linfo: Dictionary = _report.get("L", {}) as Dictionary
	for s_v in linfo.get("samples", []) as Array:
		l_walls.append(float((s_v as Dictionary).get("wall_ms", 99999.0)))
	var l_med := _median(l_walls)
	var l_ok := l_walls.size() > 0 and l_med <= L_BAR_MS and _worst(l_walls) <= L_BAR_MS
	var idle_med := _median(_report.get("idle_frames_ms", []) as Array)
	_report["grade"] = {
		"boot_ms": boot_ms,
		"boot_bar_ms": BOOT_BAR_MS,
		"boot": "PASS" if boot_ok else "FAIL",
		"during_warm": "PASS" if warm_ok else "FAIL",
		"map_median_ms": med,
		"map_worst_ms": worst,
		"map_missed": missed,
		"map_over_frame": frame_over,
		"map": "PASS" if map_ok else "FAIL",
		"tech": "PASS" if tech_ok else "FAIL",
		"prod": "PASS" if prod_ok else "FAIL",
		"L": "PASS" if l_ok else "REPORT",
		"idle_median_ms": idle_med,
		"failures": _failures,
	}
	_note(
		"UI_PERF1 grade boot=%s boot_ms=%d during_warm=%s map=%s median=%.1f worst=%.1f missed=%d tech=%s prod=%s L=%s l_median=%.1f idle_median=%.1f"
		% [
			"PASS" if boot_ok else "FAIL", boot_ms,
			"PASS" if warm_ok else "FAIL",
			"PASS" if map_ok else "FAIL", med, worst, missed,
			"PASS" if tech_ok else "FAIL",
			"PASS" if prod_ok else "FAIL",
			"PASS" if l_ok else "REPORT",
			l_med,
			idle_med,
		]
	)


func _grade_during_warm() -> bool:
	var info: Dictionary = _report.get("during_warm", {}) as Dictionary
	if bool(info.get("skipped", false)):
		return true
	var ok := true
	if not bool(info.get("pending_before_terrain", false)):
		ok = false
		_note("UI_PERF1 FAIL during_warm terrain click was not pending")
	if not bool(info.get("pending_before_supply", false)):
		ok = false
		_note("UI_PERF1 FAIL during_warm supply click was not mid-warm")
	if not _switch_cached(info.get("terrain", {}) as Dictionary, "terrain"):
		ok = false
	if not _switch_cached(info.get("supply", {}) as Dictionary, "supply"):
		ok = false
	if int(info.get("warm_frames_over_100", 1)) > 0:
		ok = false
		_note("UI_PERF1 FAIL during_warm frames_over_100=%s max=%.1f" % [
			str(info.get("warm_frames_over_100")), float(info.get("warm_frame_max_ms", -1)),
		])
	if not bool(info.get("warm_finished", false)):
		ok = false
		_note("UI_PERF1 FAIL during_warm did not finish")
	if not ok:
		_failures += 1
	return ok


func _switch_cached(row: Dictionary, mode: String) -> bool:
	var live := str(row.get("live_mode", ""))
	var n := _cache_n(row)
	var applied := bool(row.get("applied", false))
	if applied and live == mode and n >= WARM_CACHE_MIN:
		return true
	_note("UI_PERF1 FAIL during_warm mode=%s applied=%s live=%s cache_n=%d" % [mode, str(applied), live, n])
	return false


func _finish() -> void:
	var ok := _failures == 0
	_report["result"] = "PASS" if ok else "FAIL"
	_note("UI_PERF1 RESULT=%s failures=%d" % ["PASS" if ok else "FAIL", _failures])
	_flush_report()
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _sample_frames(n: int) -> Array[float]:
	var out: Array[float] = []
	var i := 0
	while i < n:
		var a := Time.get_ticks_usec()
		await process_frame
		out.append(float(Time.get_ticks_usec() - a) / 1000.0)
		i += 1
	return out


func _wait_map_ready() -> bool:
	while true:
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed >= WAIT_MAP_SECS:
			_fail("map_timeout provinces=%d" % _province_count())
			return false
		if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
			_last_wait_log = elapsed
			_note("wait_map elapsed=%d n=%d" % [elapsed, _province_count()])
		_dismiss_title()
		if _province_count() >= 3500:
			_dismiss_loading()
		if _map_is_ready():
			_note("map_ready elapsed=%d n=%d" % [elapsed, _province_count()])
			var i := 0
			while i < 8:
				await process_frame
				i += 1
			return true
		await process_frame
	return false


func _map_is_ready() -> bool:
	if not _title_closed():
		return false
	if _loading_screen_up():
		return false
	if _province_count() < 3500:
		return false
	return _map_renderer() != null


func _loading_screen_up() -> bool:
	var ls := _find_named("LoadingScreen")
	if ls == null:
		return false
	if "visible" in ls and not bool(ls.get("visible")):
		return false
	return true


func _dismiss_loading() -> void:
	var tr := _find_named("TestRunner")
	if tr != null and tr.has_method("_dismiss_loading_screen"):
		tr.call("_dismiss_loading_screen")
	var ls := _find_named("LoadingScreen")
	if ls == null:
		return
	if ls.has_method("hide_and_free"):
		ls.call("hide_and_free")
	elif "visible" in ls:
		ls.set("visible", false)


func _title_closed() -> bool:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("living_title_has_closed") and bool(tm.call("living_title_has_closed")):
		return true
	var boot := _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	return false


func _dismiss_title() -> void:
	var boot := _find_named("LivingTitleBoot")
	if boot == null or bool(boot.get("_closed")):
		return
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	elif boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")


func _pause_clock() -> void:
	var tm: Node = root.get_node_or_null("TimeManager")
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)


func _province_count() -> int:
	var mm: Node = root.get_node_or_null("MapManager")
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _map_renderer() -> Node:
	var nodes := get_nodes_in_group("map_renderer")
	if nodes.size() > 0:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _mode_button(mode: String) -> Button:
	var tb := _find_named("MapModeToolbar")
	if tb == null:
		return null
	var want := str(CHIP_LABELS.get(mode, mode))
	for c in tb.find_children("*", "Button", true, false):
		var btn := c as Button
		if btn != null and str(btn.text) == want:
			return btn
	return null


func _bar_button(node_name: String) -> Button:
	var bar := _find_named("TopInfoBar")
	if bar == null:
		return null
	return bar.find_child(node_name, true, false) as Button


func _click_control(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	var r := ctrl.get_global_rect()
	if r.size.x < 2.0 or r.size.y < 2.0:
		return false
	var p := r.get_center()
	p.x = clampf(p.x, 1.0, float(PLAY.x - 2))
	p.y = clampf(p.y, 1.0, float(PLAY.y - 2))
	if not r.has_point(p):
		p = Vector2(clampf(r.position.x + 2.0, 1.0, float(PLAY.x - 2)), clampf(r.position.y + r.size.y * 0.5, 1.0, float(PLAY.y - 2)))
	_release_focus()
	_warp_mouse(p)
	# Button action is mouse-up. Mouse-down does not change the mode; a real
	# click delivers it on an earlier frame. Time the release through the paint.
	var press_t := Time.get_ticks_usec()
	_parse_mouse(p, true)
	var release_t := Time.get_ticks_usec()
	_last_click_press_us = int(release_t - press_t)
	_last_click_warp_us = 0
	_last_click_t0 = release_t
	_parse_mouse(p, false)
	_last_click_release_us = int(Time.get_ticks_usec() - release_t)
	return true


func _parse_mouse(p: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = p
	ev.global_position = p
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _warp_mouse(p: Vector2) -> void:
	var vp := root.get_viewport()
	if vp != null:
		vp.warp_mouse(p)
	DisplayServer.warp_mouse(Vector2i(int(round(p.x)), int(round(p.y))))


func _tap_key(keycode: Key, ctrl: bool, shift: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.echo = false
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _release_focus() -> void:
	var vp := root.get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _live_named(nm: String) -> Control:
	var n := _find_named(nm)
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		return null
	if str(n.name).ends_with("_dying"):
		return null
	return n as Control


func _control_visible(n: Control) -> bool:
	if n == null or not n.visible:
		return false
	return n.size.x >= 80.0 and n.size.y >= 80.0


func _label_text(screen: Node, node_name: String) -> String:
	var lbl := screen.find_child(node_name, true, false) as Label
	if lbl == null:
		return ""
	return str(lbl.text)


func _close_named(nm: String) -> void:
	var n := _live_named(nm)
	if n == null:
		return
	if n.has_method("close_screen"):
		n.call("close_screen")
	else:
		n.queue_free()


func _median(vals: Array) -> float:
	if vals.is_empty():
		return -1.0
	var b: Array = vals.duplicate()
	b.sort()
	var n := b.size()
	if n % 2 == 1:
		return float(b[n / 2])
	return (float(b[n / 2 - 1]) + float(b[n / 2])) * 0.5


func _worst(vals: Array) -> float:
	var w := -1.0
	for v in vals:
		w = maxf(w, float(v))
	return w


func _note(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	_write_log()


func _fail(msg: String) -> void:
	_failures += 1
	_note("UI_PERF1 FAIL %s" % msg)


func _flush_report() -> void:
	_report["lines"] = _lines
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_report, "\t"))
	f.close()


func _write_log() -> void:
	var f := FileAccess.open(_log_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(_lines) + "\n")
	f.close()
