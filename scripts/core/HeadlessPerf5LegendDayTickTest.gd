extends SceneTree

## PERF-5 (a): L-on legend day tick must be cheap (op-count hard gate).
## FAILS on main: StyleBox.changed and CompareHintLabel.theme_changed fire every day.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessPerf5LegendDayTickTest.gd

const LAND_N := 3196
const POLY_SIDES := 8
const CONTESTED_N := 48
const DAY_TICKS := 20
const EXPIRY_N := 5
const LISTENER_P95_MS := 60.0
const LISTENER_WORST_MS := 100.0
const HOME_Z := 0.318
const FLUSH_FRAMES := 3

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _container: Node2D = null
var _stylebox_changed: int = 0
var _panel_theme_changed: int = 0
var _hint_theme_changed: int = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessPerf5LegendDayTickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessPerf5LegendDayTickTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessPerf5LegendDayTickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessPerf5LegendDayTickTest: ", msg)


func _info(msg: String) -> void:
	print("  [INFO] HeadlessPerf5LegendDayTickTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _walks() -> int:
	if _mr != null and _mr.has_method("get_legend_board_walks"):
		return int(_mr.call("get_legend_board_walks"))
	return -1


func _text_writes() -> int:
	if _mr != null and _mr.has_method("get_legend_text_writes"):
		return int(_mr.call("get_legend_text_writes"))
	return -1


func _pulse_modulate() -> Color:
	if _mr != null and _mr.has_method("get_supply_legend_pulse_modulate"):
		return _mr.call("get_supply_legend_pulse_modulate") as Color
	return Color(0, 0, 0, 0)


func _legend_text() -> String:
	var rtl: RichTextLabel = _mr.get("_supply_overlay_legend") as RichTextLabel
	if rtl == null:
		return ""
	return str(rtl.text)


func _run() -> void:
	OS.set_environment("EOA_LIVE_F5_EQUIV", "1")
	DisplayServer.window_set_size(Vector2i(1280, 740))
	if root != null:
		root.size = Vector2i(1280, 740)
	if typeof(TimeManager) != TYPE_NIL and "_live_f5_equiv_clock" in TimeManager:
		TimeManager._live_f5_equiv_clock = true
	if not _setup_renderer():
		return
	await _flush()
	if not bool(_mr.get("supply_mode")):
		_mr.call("_toggle_supply_overlay")
		await _flush()
	if not bool(_mr.get("supply_mode")):
		_fail("L-on did not set supply_mode")
		return
	if _mr.get("_supply_legend_panel") == null:
		_mr.call("_update_supply_overlay_legend")
		await _flush()
	_connect_theme_counters()
	if _stylebox_changed < 0:
		_fail("legend StyleBox not observable")
		return
	await _measure_day_ticks()
	await _measure_expiries()
	await _measure_contested_flip()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()


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
	_cam.position = Vector2(4200, 1000)
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
	var i := 0
	while i < LAND_N:
		var pid := 710000 + i
		var host := Node2D.new()
		host.name = "Prov_%d" % pid
		host.position = Vector2(float(i % 80) * 40.0, float(i / 80) * 40.0)
		var poly := Polygon2D.new()
		poly.polygon = _make_ring(24.0, POLY_SIDES)
		host.add_child(poly)
		_container.add_child(host)
		_mr.province_nodes[pid] = host
		if pscr != null:
			var p: Object = pscr.new()
			p.set("id", pid)
			p.set("name", "Land %d" % pid)
			p.set("owner_tag", "GER")
			p.set("controller_tag", "FRA" if i < CONTESTED_N else "GER")
			p.set("infrastructure", 50)
			p.set("is_sea", false)
			_mr.provinces[pid] = p
			if mm != null and "_provinces" in mm:
				mm._provinces[pid] = p
		if depot_scr != null and "depot_states" in sm:
			sm.depot_states[pid] = depot_scr.new(pid, 100.0)
		i += 1
	if int(_mr.province_nodes.size()) < LAND_N:
		_fail("province_nodes seeded %d want %d" % [int(_mr.province_nodes.size()), LAND_N])
		return false
	_seed_boot_supply_layer()
	if "overlay_visible" in sm:
		sm.overlay_visible = false
	_mr.supply_mode = false
	if mm != null and _mr.has_method("_connect_map_manager_signals"):
		_mr.call("_connect_map_manager_signals")
	if _mr.has_method("_connect_time_manager_signals"):
		_mr.call("_connect_time_manager_signals")
	_info("seeded land=%d contested=%d" % [LAND_N, CONTESTED_N])
	return true


func _seed_boot_supply_layer() -> void:
	var layer_scr: Script = load("res://scripts/supply/SupplyMapLayer.gd") as Script
	if layer_scr == null or _container == null:
		return
	var layer: Node2D = layer_scr.new() as Node2D
	if layer == null:
		return
	layer.name = "SupplyMapLayer"
	layer.visible = false
	_container.add_child(layer)
	_mr.supply_map_layer = layer


func _make_ring(radius: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sides)
	var i := 0
	while i < sides:
		var a := TAU * float(i) / float(sides)
		pts[i] = Vector2(cos(a), sin(a)) * radius
		i += 1
	return pts


func _connect_theme_counters() -> void:
	_stylebox_changed = 0
	_panel_theme_changed = 0
	_hint_theme_changed = 0
	var panel: PanelContainer = _mr.get("_supply_legend_panel") as PanelContainer
	if panel == null:
		_stylebox_changed = -1
		return
	var style := panel.get_theme_stylebox("panel")
	if style != null and style.has_signal("changed"):
		style.changed.connect(func() -> void: _stylebox_changed += 1)
	if panel.has_signal("theme_changed"):
		panel.theme_changed.connect(func() -> void: _panel_theme_changed += 1)
	var hint: Label = _mr.get("_compare_hint_label") as Label
	if hint != null and hint.has_signal("theme_changed"):
		hint.theme_changed.connect(func() -> void: _hint_theme_changed += 1)


func _emit_day(year: int, month: int, day: int) -> float:
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.current_year = year
		TimeManager.current_month = month
		TimeManager.current_day = day
	var t0 := Time.get_ticks_usec()
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_signal("game_day_advanced"):
		TimeManager.game_day_advanced.emit(year, month, day)
	else:
		_mr.call("_on_game_day_advanced_legend", year, month, day)
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _percentile(sorted_ms: Array, p: float) -> float:
	if sorted_ms.is_empty():
		return 0.0
	var idx := int(floor(p * float(sorted_ms.size() - 1)))
	return float(sorted_ms[idx])


func _measure_day_ticks() -> void:
	var ms_list: Array = []
	var walks0 := _walks()
	var texts0 := _text_writes()
	var style0 := _stylebox_changed
	var panel0 := _panel_theme_changed
	var hint0 := _hint_theme_changed
	var day := 2
	var i := 0
	while i < DAY_TICKS:
		var ms := _emit_day(1936, 1, day)
		ms_list.append(ms)
		day += 1
		i += 1
	ms_list.sort()
	var p50 := _percentile(ms_list, 0.50)
	var p95 := _percentile(ms_list, 0.95)
	var worst := float(ms_list[ms_list.size() - 1])
	_info("listener p50=%.2f p95=%.2f worst=%.2f n=%d" % [p50, p95, worst, ms_list.size()])
	if p95 > LISTENER_P95_MS:
		_fail("listener p95 %.2f ms > %.1f" % [p95, LISTENER_P95_MS])
	else:
		_pass("listener p95 %.2f ms" % p95)
	if worst > LISTENER_WORST_MS:
		_fail("listener worst %.2f ms > %.1f" % [worst, LISTENER_WORST_MS])
	else:
		_pass("listener worst %.2f ms" % worst)
	var style_d := _stylebox_changed - style0
	var panel_d := _panel_theme_changed - panel0
	var hint_d := _hint_theme_changed - hint0
	_info("ops stylebox_changed=%d panel_theme=%d hint_theme=%d walks=%d→%d texts=%d→%d" % [
		style_d, panel_d, hint_d, walks0, _walks(), texts0, _text_writes(),
	])
	if style_d != 0:
		_fail("legend StyleBox changed=%d want 0" % style_d)
	else:
		_pass("legend StyleBox changed=0")
	if panel_d != 0:
		_fail("legend PanelContainer.theme_changed=%d want 0" % panel_d)
	else:
		_pass("legend PanelContainer.theme_changed=0")
	if hint_d != 0:
		_fail("CompareHintLabel.theme_changed=%d want 0 (colour unchanged)" % hint_d)
	else:
		_pass("CompareHintLabel.theme_changed=0")
	var walks := _walks()
	if walks >= 0:
		var walks_d := walks - walks0
		if walks_d > DAY_TICKS:
			_fail("board walks %d over %d days (want ≤1/day)" % [walks_d, DAY_TICKS])
		else:
			_pass("board walks %d over %d days (≤1/day)" % [walks_d, DAY_TICKS])
	var texts := _text_writes()
	if texts >= 0:
		var texts_d := texts - texts0
		if texts_d > DAY_TICKS:
			_fail("legend text writes %d over %d days (want ≤1/tick)" % [texts_d, DAY_TICKS])
		else:
			_pass("legend text writes %d over %d days" % [texts_d, DAY_TICKS])


func _measure_expiries() -> void:
	var pulse_on := _pulse_modulate()
	_emit_day(1936, 1, 28)
	pulse_on = _pulse_modulate()
	var walks0 := _walks()
	var i := 0
	while i < EXPIRY_N:
		_mr.set("_map_time_pulse_until_msec", Time.get_ticks_msec() - 10)
		_mr.call("_expire_map_time_pulse_if_needed")
		i += 1
	var walks := _walks()
	var pulse_off := _pulse_modulate()
	if walks >= 0 and walks > walks0:
		_fail("expiry walked the board %d→%d (want 0)" % [walks0, walks])
	else:
		_pass("expiry board walks=0")
	if pulse_on == pulse_off:
		_fail("pulse modulate unchanged active=%s expired=%s" % [str(pulse_on), str(pulse_off)])
	else:
		_pass("pulse modulate differs active vs expired")


func _measure_contested_flip() -> void:
	var mm: Node = root.get_node_or_null("MapManager")
	if mm == null or not mm.has_method("update_province_owner"):
		_fail("MapManager.update_province_owner missing")
		return
	var before := _legend_text()
	var flip_pid := 710200
	mm.call("update_province_owner", flip_pid, "GER", "FRA", true, false)
	_emit_day(1936, 1, 30)
	await process_frame
	var after := _legend_text()
	if after.find("49") < 0 and after.find(str(CONTESTED_N + 1)) < 0:
		_fail("legend text did not show new contested count after controller flip (before_len=%d after_len=%d)" % [before.length(), after.length()])
	else:
		_pass("legend text updated contested count after controller flip")
