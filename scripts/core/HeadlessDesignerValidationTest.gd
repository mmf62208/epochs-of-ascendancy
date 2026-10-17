extends SceneTree

## P1 designer validation: Me 262 §5 cases, warnings, RATO stub, panel builds,
## read-only (custom_designs + template count unchanged).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessDesignerValidationTest.gd

const CalcScript = preload("res://scripts/units/DesignCalculator.gd")
const PanelScript = preload("res://scripts/ui/AirPhysicsReadoutPanel.gd")
const PopupScript = preload("res://scripts/ui/DomainDesignPopup.gd")

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
	var pop: Window = PopupScript.new() as Window
	root.add_child(pop)
	await process_frame
	if pop.has_method("set_domain"):
		pop.call("set_domain", "air")
	await process_frame
	var btn: Button = _find_named(pop, "PhysicsReadoutP1Btn") as Button
	if btn == null:
		_fail("Physics readout (P1) button missing")
	else:
		if not btn.visible:
			_fail("button hidden on air domain")
		else:
			_pass("button visible on air")
		if pop.has_method("set_domain"):
			pop.call("set_domain", "land")
		await process_frame
		if btn.visible:
			_fail("button visible on land")
		else:
			_pass("button hidden on land")
		OS.set_environment("EOA_AIR_PHYSICS_P1", "0")
		if pop.has_method("set_domain"):
			pop.call("set_domain", "air")
		await process_frame
		if btn.visible:
			_fail("killswitch EOA_AIR_PHYSICS_P1=0 did not hide button")
		else:
			_pass("killswitch hides button")
		OS.set_environment("EOA_AIR_PHYSICS_P1", "")
	pop.queue_free()
	await process_frame
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
