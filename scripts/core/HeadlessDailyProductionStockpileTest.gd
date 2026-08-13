extends SceneTree

## Drive shipped **daily** production path (TimeManager tick entry) → country stockpile.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessDailyProductionStockpileTest.gd
##
## Gates:
## 1) empty/unassigned line: daily_production_tick does not crash
## 2) factory-assigned bootstrap line: N× daily_production_tick increases country stockpile

const TAG := "GER"
const DESIGN := "cv33_tankette"
const LINE_ID := "daily_tick_test_oob_ger_cv33"
const EMPTY_LINE_ID := "daily_tick_test_empty_unassigned"
const PROVINCE_ID := 887767
const DAILY_TICKS := 100


var _failures := 0
var _pm: Node = null
var _fm: Node = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessDailyProductionStockpileTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessDailyProductionStockpileTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessDailyProductionStockpileTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
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
	if not _pm.has_method("daily_production_tick"):
		_fail("daily_production_tick missing (TimeManager day path entry)")
		return
	var tpl = gd.design_data.get_template(DESIGN)
	if tpl == null:
		_fail("design template missing: " + DESIGN)
		return

	_test_empty_line_daily_tick_no_crash()
	_test_daily_tick_fills_stockpile()
	_test_time_manager_day_path_wired()


func _test_empty_line_daily_tick_no_crash() -> void:
	if _pm.has_method("remove_line"):
		_pm.remove_line(EMPTY_LINE_ID)
	var line = _pm.create_line(EMPTY_LINE_ID)
	if line == null:
		_fail("create_line empty failed")
		return
	for _i in 5:
		_pm.daily_production_tick()
	_pm.remove_line(EMPTY_LINE_ID)
	_pass("empty/unassigned line daily_production_tick no-crash")


func _test_daily_tick_fills_stockpile() -> void:
	if _pm.has_method("remove_line"):
		_pm.remove_line(LINE_ID)
	var factory_id := PROVINCE_ID * 100 + 1
	_cleanup_factory(factory_id)

	var factory: Resource = null
	if ClassDB.class_exists("Factory"):
		factory = ClassDB.instantiate("Factory") as Resource
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
		_fail("bootstrap_line_on_factory missing")
		_cleanup_factory(factory_id)
		return
	if not bool(_pm.bootstrap_line_on_factory(LINE_ID, DESIGN, factory_id)):
		_fail("bootstrap_line_on_factory returned false")
		_cleanup_all(factory_id)
		return

	var before: Dictionary = _pm.get_country_equipment_stockpile(TAG)
	var before_amt := int(before.get(DESIGN, 0))

	for _i in DAILY_TICKS:
		_pm.daily_production_tick()

	var after: Dictionary = _pm.get_country_equipment_stockpile(TAG)
	var after_amt := int(after.get(DESIGN, 0))
	var delta := after_amt - before_amt

	print(
		"  [INFO] daily_production_tick ×%d design=%s before=%d after=%d delta=%d"
		% [DAILY_TICKS, DESIGN, before_amt, after_amt, delta]
	)

	if delta < 1:
		_fail("daily_production_tick did not grow country stockpile (delta=%d)" % delta)
		_cleanup_all(factory_id)
		return

	_pass("daily_production_tick filled stockpile design=%s delta=%+d" % [DESIGN, delta])
	_cleanup_all(factory_id)


func _test_time_manager_day_path_wired() -> void:
	## Structural: ProductionManager must connect game_day_advanced → daily_production_tick.
	var src := FileAccess.get_file_as_string("res://scripts/autoload/ProductionManager.gd")
	if src.is_empty():
		_fail("could not read ProductionManager.gd")
		return
	if "daily_production_tick" not in src:
		_fail("daily_production_tick missing in ProductionManager source")
		return
	if "_on_game_day_advanced" not in src:
		_fail("_on_game_day_advanced missing")
		return
	if "game_day_advanced.connect" not in src and "game_day_advanced.is_connected" not in src:
		_fail("TimeManager.game_day_advanced not wired")
		return
	# Daily tick must call day-based advance (stockpile path), not only PP advance_production alone
	if "func daily_production_tick" not in src:
		_fail("daily_production_tick definition missing")
		return
	# Ensure body uses advance_days (proven stockpile) — read function slice
	var idx := src.find("func daily_production_tick")
	var slice := src.substr(idx, 200) if idx >= 0 else ""
	if "advance_days" not in slice:
		_fail("daily_production_tick does not call advance_days (stockpile path)")
		return
	_pass("TimeManager game_day_advanced → daily_production_tick → advance_days wired")


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
