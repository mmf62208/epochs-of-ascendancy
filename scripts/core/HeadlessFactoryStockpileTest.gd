extends SceneTree

## Drive shipped factory→line→stockpile APIs (not a reimplementation).
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFactoryStockpileTest.gd
##
## Gates:
## 1) empty/unassigned line: advance_days does not crash, 0 units
## 2) factory-assigned bootstrap line: advance_days increases country stockpile for design

const TAG := "GER"
const DESIGN := "cv33_tankette"  # 35 base days — finishes inside 100d with bootstrap tooling
const LINE_ID := "stockpile_test_oob_ger_cv33"
const EMPTY_LINE_ID := "stockpile_test_empty_unassigned"
const PROVINCE_ID := 887766
const ADVANCE_DAYS := 100.0


var _failures := 0
var _pm: Node = null
var _fm: Node = null


func _init() -> void:
	# Autoloads register with --path; resolve via tree (not bare autoload identifiers —
	# those can fail compile when the entry script is loaded as -s SceneTree).
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFactoryStockpileTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFactoryStockpileTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessFactoryStockpileTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	quit(0 if ok else 1)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run() -> void:
	_pm = _autoload("ProductionManager")
	_fm = _autoload("FactoryManager")
	var gd: Node = _autoload("GameData")
	if _pm == null:
		_fail("ProductionManager autoload missing")
		return
	if _fm == null:
		_fail("FactoryManager autoload missing")
		return
	if gd == null or not ("design_data" in gd) or gd.design_data == null:
		_fail("GameData.design_data missing")
		return
	var tpl = gd.design_data.get_template(DESIGN)
	if tpl == null:
		_fail("design template missing: " + DESIGN)
		return

	_test_empty_unassigned_line_no_crash()
	_test_factory_line_stockpile_grows()


func _test_empty_unassigned_line_no_crash() -> void:
	if _pm.has_method("remove_line"):
		_pm.remove_line(EMPTY_LINE_ID)
	var line = _pm.create_line(EMPTY_LINE_ID)
	if line == null:
		_fail("create_line empty failed")
		return
	# No factory, no template — must not crash.
	var report: Dictionary = _pm.advance_days(10.0)
	if typeof(report) != TYPE_DICTIONARY:
		_fail("advance_days empty returned non-dict")
		_pm.remove_line(EMPTY_LINE_ID)
		return
	var line_rep: Dictionary = {}
	if typeof(report.get("lines")) == TYPE_DICTIONARY:
		line_rep = report["lines"].get(EMPTY_LINE_ID, {})
	var done := int(line_rep.get("units_completed", 0))
	if done != 0:
		_fail("empty unassigned line completed units: %d" % done)
		_pm.remove_line(EMPTY_LINE_ID)
		return
	_pm.remove_line(EMPTY_LINE_ID)
	_pass("empty/unassigned line advance_days no-crash units=0")


func _make_factory_id(province_id: int, slot: int) -> int:
	# Factory.make_id(province, slot) == province * 100 + slot
	return province_id * 100 + slot


func _test_factory_line_stockpile_grows() -> void:
	if _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
	var factory_id := _make_factory_id(PROVINCE_ID, 1)
	_cleanup_factory(factory_id)

	# Use Factory class_name if available; fall back to Resource script load.
	var factory: Resource = null
	if ClassDB.class_exists("Factory") or true:
		# Prefer global class Factory (project class_name)
		factory = ClassDB.instantiate("Factory") if ClassDB.class_exists("Factory") else null
	if factory == null:
		var fac_script: Script = load("res://scripts/map/Factory.gd") as Script
		if fac_script != null:
			factory = fac_script.new() as Resource
	if factory == null:
		_fail("could not instantiate Factory")
		return

	factory.set("factory_id", factory_id)
	factory.set("province_id", PROVINCE_ID)
	factory.set("owner_tag", TAG)
	factory.set("factory_type", "standard")
	factory.set("max_production_lines", 2)
	factory.set("current_efficiency", 1.0)
	_fm.register_factory(factory)

	if not _pm.has_method("bootstrap_line_on_factory"):
		_fail("bootstrap_line_on_factory missing on ProductionManager")
		_cleanup_factory(factory_id)
		return

	var boot_ok: bool = bool(_pm.bootstrap_line_on_factory(LINE_ID, DESIGN, factory_id))
	if not boot_ok:
		_fail("bootstrap_line_on_factory returned false")
		_cleanup_all(factory_id)
		return

	var line = _pm.get_line(LINE_ID)
	if line == null:
		_fail("line missing after bootstrap")
		_cleanup_all(factory_id)
		return
	if int(line.factory_id) != factory_id:
		_fail("line.factory_id=%d expected %d" % [int(line.factory_id), factory_id])
		_cleanup_all(factory_id)
		return
	var tmpl := str(line.current_template_id) if "current_template_id" in line else ""
	var des := str(line.design_id) if "design_id" in line else ""
	if tmpl.is_empty() and des.is_empty():
		_fail("bootstrap left template/design empty")
		_cleanup_all(factory_id)
		return

	var before: Dictionary = _pm.get_country_equipment_stockpile(TAG)
	var before_amt := int(before.get(DESIGN, 0))

	var report: Dictionary = _pm.advance_days(ADVANCE_DAYS)
	var total_done := int(report.get("total_units_completed", 0))
	var line_rep: Dictionary = {}
	if typeof(report.get("lines")) == TYPE_DICTIONARY:
		line_rep = report["lines"].get(LINE_ID, {})
	var line_done := int(line_rep.get("units_completed", 0))

	var after: Dictionary = _pm.get_country_equipment_stockpile(TAG)
	var after_amt := int(after.get(DESIGN, 0))
	var delta := after_amt - before_amt

	print(
		"  [INFO] stockpile advance %.0fd design=%s before=%d after=%d delta=%d line_done=%d total_done=%d"
		% [ADVANCE_DAYS, DESIGN, before_amt, after_amt, delta, line_done, total_done]
	)

	if line_done < 1 and delta < 1:
		_fail(
			"no production/stockpile growth after advance_days (line_done=%d delta=%d total=%d)"
			% [line_done, delta, total_done]
		)
		_cleanup_all(factory_id)
		return
	if delta < 1:
		_fail("units completed but country stockpile did not grow (line_done=%d delta=%d)" % [line_done, delta])
		_cleanup_all(factory_id)
		return

	_pass(
		"factory line stockpile grew design=%s delta=%+d line_done=%d (shipped advance_days)"
		% [DESIGN, delta, line_done]
	)
	_cleanup_all(factory_id)


func _cleanup_all(factory_id: int) -> void:
	if _pm != null and _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
	_cleanup_factory(factory_id)


func _cleanup_factory(factory_id: int) -> void:
	if _fm == null:
		return
	if "factories" in _fm and typeof(_fm.factories) == TYPE_DICTIONARY:
		_fm.factories.erase(factory_id)
	var pid := int(float(factory_id) / 100.0)
	if "province_to_factories" in _fm and typeof(_fm.province_to_factories) == TYPE_DICTIONARY:
		if _fm.province_to_factories.has(pid):
			var ids: Array = _fm.province_to_factories[pid]
			ids.erase(factory_id)
			if ids.is_empty():
				_fm.province_to_factories.erase(pid)
