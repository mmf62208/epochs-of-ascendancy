extends SceneTree

## P1 designer validation: Me 262 §5 cases, warnings, RATO stub, panel builds,
## read-only (custom_designs + template count unchanged).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessDesignerValidationTest.gd

const CalcScript = preload("res://scripts/units/DesignCalculator.gd")
const PanelScript = preload("res://scripts/ui/AirPhysicsReadoutPanel.gd")

const PLAY_SIZE := Vector2i(1280, 800)

var _failures: int = 0


func _init() -> void:
	call_deferred("_start")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessDesignerValidationTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessDesignerValidationTest: ", msg)


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessDesignerValidationTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessDesignerValidationTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _count_templates() -> int:
	var n: int = 0
	var d: DirAccess = DirAccess.open("res://data/unit_templates")
	if d == null:
		return 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".json"):
			n += 1
		name = d.get_next()
	d.list_dir_end()
	return n


func _find_named(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for c in n.get_children():
		var hit: Node = _find_named(c, want)
		if hit != null:
			return hit
	return null


func _force_viewport() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root is Window:
		(root as Window).size = PLAY_SIZE
	var vp := root.get_viewport()
	if vp != null:
		vp.size = PLAY_SIZE


func _rect_inside(inner: Rect2, outer: Rect2, slack: float = 1.5) -> bool:
	return (
		inner.position.x >= outer.position.x - slack
		and inner.position.y >= outer.position.y - slack
		and inner.end.x <= outer.end.x + slack
		and inner.end.y <= outer.end.y + slack
	)


func _assert_ctrl_reachable(ctrl: Control, win: Window, vp_rect: Rect2, label: String) -> void:
	if ctrl == null:
		_fail("%s missing" % label)
		return
	var local: Rect2 = ctrl.get_global_rect()
	var win_vis := Rect2(Vector2.ZERO, Vector2(win.size))
	if not _rect_inside(local, win_vis):
		_fail("%s not inside window visible rect %s vs %s" % [label, str(local), str(win_vis)])
		return
	var screen := Rect2(Vector2(win.position) + local.position, local.size)
	if not _rect_inside(screen, vp_rect):
		_fail("%s not inside viewport %s vs %s" % [label, str(screen), str(vp_rect)])
		return
	_pass("%s reachable mouse rect=%s screen=%s" % [label, str(local), str(screen)])


func _assert_popup_hook() -> void:
	if not FileAccess.file_exists("res://scripts/ui/DomainDesignPopup.gd"):
		_fail("DomainDesignPopup.gd missing")
		return
	var f: FileAccess = FileAccess.open("res://scripts/ui/DomainDesignPopup.gd", FileAccess.READ)
	if f == null:
		_fail("DomainDesignPopup.gd unreadable")
		return
	var txt: String = f.get_as_text()
	f.close()
	if txt.find("PhysicsReadoutP1Btn") < 0 or txt.find("Physics readout (P1)") < 0:
		_fail("popup missing Physics readout (P1) button")
	else:
		_pass("popup source has Physics readout (P1) button")
	if txt.find("EOA_AIR_PHYSICS_P1") < 0:
		_fail("popup missing EOA_AIR_PHYSICS_P1 killswitch")
	else:
		_pass("popup source has killswitch")
	if txt.find("res://scripts/ui/AirPhysicsReadoutPanel.gd") < 0:
		_fail("popup does not load() AirPhysicsReadoutPanel")
	else:
		_pass("popup load()s AirPhysicsReadoutPanel")
	if txt.find("p1_readout_visible") < 0:
		_fail("popup does not call DesignCalculator.p1_readout_visible")
	else:
		_pass("popup uses p1_readout_visible helper")


func _has_warning(ev: Dictionary, wid: String) -> bool:
	for w in ev.get("warnings", []) as Array:
		if w is Dictionary and str((w as Dictionary).get("id", "")) == wid:
			return true
	return false


func _design_manager() -> Node:
	return root.get_node_or_null("/root/DesignManager")


func _run() -> void:
	var before_custom: Dictionary = {}
	var dm: Node = _design_manager()
	if dm != null and dm.has_method("get_save_data"):
		before_custom = (dm.call("get_save_data") as Dictionary).duplicate(true)
	var before_templates: int = _count_templates()
	var calc: RefCounted = CalcScript.new()
	if not bool(calc.call("load_presets")):
		_fail("presets failed to load")
		return
	var cases: Dictionary = calc.call("me262_cases") as Dictionary
	_check_clean(cases.get("clean", {}) as Dictionary)
	_check_sc500(cases.get("sc500", {}) as Dictionary)
	_check_1000(cases.get("kg1000_full", {}) as Dictionary)
	_check_cut(cases.get("kg1000_fuel_cut", {}) as Dictionary)
	var rato: Dictionary = UnitPhysics.rato_overload_check(7533.0, 7130.0)
	if bool(rato.get("allowed", true)):
		_fail("RATO stub allowed=true (must stay false in P1)")
	else:
		_pass("RATO stub allowed=false deferred=P2")
	var p51: Dictionary = calc.call("evaluate_ids", "p51d", "aft85", "escort") as Dictionary
	if not _has_warning(p51, "cg_aft"):
		_fail("P-51D aft tank missing CG warning")
	else:
		_pass("P-51D CG warning present")
	var panel: Window = PanelScript.new() as Window
	root.add_child(panel)
	await process_frame
	if panel == null:
		_fail("panel failed to build")
	else:
		_pass("AirPhysicsReadoutPanel built headless")
		if panel.has_method("set_preset"):
			panel.call("set_preset", "me262_a1a")
			panel.call("set_loadout", "sc500_racks")
			await process_frame
			var ev: Dictionary = panel.call("current_evaluation") as Dictionary
			if absf(float(ev.get("range_loaded_km", 0.0)) - 731.0) > 1.0:
				_fail("panel Me 262 SC500 range %.3f" % float(ev.get("range_loaded_km", 0.0)))
			else:
				_pass("panel Me 262 SC500 range ok")
		panel.queue_free()
		await process_frame
	_force_viewport()
	await process_frame
	var pop_scr: GDScript = load("res://scripts/ui/DomainDesignPopup.gd") as GDScript
	if pop_scr == null:
		_fail("DomainDesignPopup.gd failed to load")
		return
	var pop: Window = pop_scr.new() as Window
	root.add_child(pop)
	await process_frame
	pop.size = Vector2i(560, 720)
	if pop.has_method("_clamp_to_viewport"):
		pop.call("_clamp_to_viewport")
	if pop.has_method("set_domain"):
		pop.call("set_domain", "air")
	pop.visible = true
	if pop.has_method("popup_centered"):
		pop.popup_centered()
	await process_frame
	await process_frame
	if pop.size.x < 200 or pop.size.y < 200:
		pop.size = Vector2i(560, 720)
		await process_frame
	var vp_rect := Rect2(Vector2.ZERO, Vector2(PLAY_SIZE))
	var vp_now := root.get_viewport()
	if vp_now != null:
		var vr := vp_now.get_visible_rect()
		if vr.size.x >= 1.0 and vr.size.y >= 1.0:
			vp_rect = Rect2(Vector2.ZERO, vr.size)
	var btn: Button = _find_named(pop, "PhysicsReadoutP1Btn") as Button
	if btn == null:
		_fail("Physics readout (P1) button missing on Air popup")
	elif not btn.visible:
		_fail("Physics readout (P1) button hidden on Air")
	else:
		_pass("Physics readout (P1) button visible on Air")
		_assert_ctrl_reachable(btn, pop, vp_rect, "Physics readout (P1)")
	if pop.has_method("_on_physics_readout_pressed"):
		pop.call("_on_physics_readout_pressed")
	await process_frame
	await process_frame
	var panel_win: Window = null
	for c in root.get_children():
		if c is Window and c != pop and str((c as Window).title).begins_with("Air physics"):
			panel_win = c as Window
			break
	if panel_win == null:
		_fail("AirPhysicsReadoutPanel did not open from the button")
	else:
		if panel_win.has_method("_clamp_to_viewport"):
			panel_win.call("_clamp_to_viewport")
		if panel_win.size.x < 200 or panel_win.size.y < 200:
			panel_win.size = Vector2i(600, 480)
		if panel_win.has_method("popup_centered"):
			panel_win.popup_centered()
		await process_frame
		var close_btn: Button = null
		if panel_win.has_method("close_button"):
			close_btn = panel_win.call("close_button") as Button
		if close_btn == null:
			close_btn = _find_named(panel_win, "CloseBtn") as Button
		_assert_ctrl_reachable(close_btn, panel_win, vp_rect, "readout Close")
		panel_win.queue_free()
		await process_frame
	pop.queue_free()
	await process_frame
	if not bool(CalcScript.p1_readout_visible("air", "")):
		_fail("helper hides button on air")
	else:
		_pass("helper shows button on air")
	if bool(CalcScript.p1_readout_visible("land", "")):
		_fail("helper shows button on land")
	else:
		_pass("helper hides button on land")
	if bool(CalcScript.p1_readout_visible("naval", "")) or bool(CalcScript.p1_readout_visible("space", "")):
		_fail("helper shows button on naval/space")
	else:
		_pass("helper hides button on naval/space")
	if bool(CalcScript.p1_readout_visible("air", "0")):
		_fail("killswitch EOA_AIR_PHYSICS_P1=0 did not hide button")
	else:
		_pass("killswitch hides button")
	_assert_popup_hook()
	var after_templates: int = _count_templates()
	if after_templates != before_templates:
		_fail("template count changed %d → %d" % [before_templates, after_templates])
	else:
		_pass("template count unchanged (%d)" % after_templates)
	dm = _design_manager()
	if dm != null and dm.has_method("get_save_data"):
		var after_custom: Dictionary = dm.call("get_save_data") as Dictionary
		var b: String = JSON.stringify(before_custom.get("custom_designs", {}))
		var a: String = JSON.stringify(after_custom.get("custom_designs", {}))
		if a != b:
			_fail("DesignManager.custom_designs mutated")
		else:
			_pass("custom_designs unchanged")
	else:
		_pass("DesignManager not on tree; template-count snapshot is the read-only proof")


func _check_clean(ev: Dictionary) -> void:
	_near("clean.w_i", float(ev.get("w_i_kg", 0.0)), 6473.0, 0.0)
	_near("clean.mtow_delta", float(ev.get("mtow_delta_kg", 0.0)), 657.0, 0.0)
	_near("clean.range", float(ev.get("range_loaded_km", 0.0)), 1071.0, 1.0)
	_eqi("clean.hexes", int(ev.get("range_loaded_hexes", 0)), 44)
	_eqi("clean.radius", int(ev.get("radius_hexes", 0)), 17)
	_near("clean.speed", float(ev.get("v_max_loaded_kmh", 0.0)), 870.0, 1.0)
	_near("clean.agility", float(ev.get("agility", 0.0)), 1.0, 0.005)
	_near("clean.to_lo", float(ev.get("takeoff_lo_m", 0.0)), 914.0, 5.0)
	_near("clean.to_hi", float(ev.get("takeoff_hi_m", 0.0)), 1189.0, 5.0)


func _check_sc500(ev: Dictionary) -> void:
	_near("sc500.w_i", float(ev.get("w_i_kg", 0.0)), 7033.0, 0.0)
	_near("sc500.delta", float(ev.get("mtow_delta_kg", 0.0)), 97.0, 0.0)
	_near("sc500.range", float(ev.get("range_loaded_km", 0.0)), 731.0, 1.0)
	_eqi("sc500.hexes", int(ev.get("range_loaded_hexes", 0)), 30)
	_eqi("sc500.radius", int(ev.get("radius_hexes", 0)), 13)
	_eqi("sc500.two_leg", int(ev.get("two_leg_radius_hexes", 0)), 16)
	_near("sc500.speed", float(ev.get("v_max_loaded_kmh", 0.0)), 753.0, 1.0)
	_near("sc500.agility", float(ev.get("agility", 0.0)), 0.690, 0.005)
	_near("sc500.to_lo", float(ev.get("takeoff_lo_m", 0.0)), 1079.0, 5.0)
	_near("sc500.to_hi", float(ev.get("takeoff_hi_m", 0.0)), 1404.0, 5.0)
	if not _has_warning(ev, "near_mtow"):
		_fail("sc500 missing near-MTOW warning")
	else:
		_pass("sc500 near-MTOW warning")


func _check_1000(ev: Dictionary) -> void:
	_near("1000.w_i", float(ev.get("w_i_kg", 0.0)), 7533.0, 0.0)
	_near("1000.delta", float(ev.get("mtow_delta_kg", 0.0)), -403.0, 0.0)
	if not bool(ev.get("over_mtow", false)):
		_fail("1000 kg full fuel must be OVER MTOW")
	_near("1000.range", float(ev.get("range_loaded_km", 0.0)), 451.0, 1.0)
	_eqi("1000.hexes", int(ev.get("range_loaded_hexes", 0)), 19)
	_eqi("1000.radius", int(ev.get("radius_hexes", 0)), 6)
	_near("1000.speed", float(ev.get("v_max_loaded_kmh", 0.0)), 615.0, 1.0)
	_near("1000.agility", float(ev.get("agility", 0.0)), 0.430, 0.005)
	_near("1000.to_lo", float(ev.get("takeoff_lo_m", 0.0)), 1238.0, 5.0)
	_near("1000.to_hi", float(ev.get("takeoff_hi_m", 0.0)), 1610.0, 5.0)
	_near("1000.cut_L", float(ev.get("fuel_cut_L", 0.0)), 1514.0, 2.0)
	_eqi("1000.cut_radius", int(ev.get("fuel_cut_radius_hexes", 0)), 4)
	if not _has_warning(ev, "overweight"):
		_fail("1000 kg missing OVERWEIGHT warning")
	else:
		_pass("1000 kg OVERWEIGHT + three fixes")
	if not _has_warning(ev, "cg_heavy_store"):
		_fail("1000 kg missing fighter-frame CG warning")
	var fixes_ok := false
	for w in ev.get("warnings", []) as Array:
		if w is Dictionary and str((w as Dictionary).get("id", "")) == "overweight":
			var fx: Array = (w as Dictionary).get("fixes", []) as Array
			if fx.size() >= 3:
				fixes_ok = true
	if not fixes_ok:
		_fail("OVERWEIGHT must offer three fixes (fuel cut / RATO / bomber)")
	else:
		_pass("OVERWEIGHT offers three fixes")


func _check_cut(ev: Dictionary) -> void:
	_near("cut.w_i", float(ev.get("w_i_kg", 0.0)), 7130.0, 0.0)
	_near("cut.range", float(ev.get("range_loaded_km", 0.0)), 339.0, 1.0)
	_eqi("cut.hexes", int(ev.get("range_loaded_hexes", 0)), 14)
	_eqi("cut.radius", int(ev.get("radius_hexes", 0)), 4)
	_near("cut.speed", float(ev.get("v_max_loaded_kmh", 0.0)), 615.0, 1.0)
	_near("cut.agility", float(ev.get("agility", 0.0)), 0.454, 0.005)
	_near("cut.to_lo", float(ev.get("takeoff_lo_m", 0.0)), 1109.0, 5.0)
	_near("cut.to_hi", float(ev.get("takeoff_hi_m", 0.0)), 1443.0, 5.0)
	_near("cut.fuel", float(ev.get("w_fuel_kg", 0.0)), 1257.0, 0.5)


func _near(label: String, got: float, want: float, tol: float) -> void:
	if absf(got - want) > tol + 1e-9:
		_fail("%s got=%.6f want=%.6f tol=%.3f" % [label, got, want, tol])
	else:
		_pass("%s=%.4f" % [label, got])


func _eqi(label: String, got: int, want: int) -> void:
	if got != want:
		_fail("%s got=%d want=%d" % [label, got, want])
	else:
		_pass("%s=%d" % [label, got])
