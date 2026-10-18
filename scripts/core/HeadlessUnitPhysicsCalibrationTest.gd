extends SceneTree

## P1 air-physics calibration: 12 presets in band, variant pairs ±5%, GD == golden.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessUnitPhysicsCalibrationTest.gd

const CalcScript = preload("res://scripts/units/DesignCalculator.gd")
const PhysScript = preload("res://scripts/units/UnitPhysics.gd")

var _failures: int = 0
var _compared: int = 0
var _max_rel: float = 0.0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessUnitPhysicsCalibrationTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessUnitPhysicsCalibrationTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessUnitPhysicsCalibrationTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessUnitPhysicsCalibrationTest: RESULT=", "PASS" if ok else "FAIL")
	print("HeadlessUnitPhysicsCalibrationTest: compared=", _compared, " max_rel=", _max_rel)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	var calc: RefCounted = CalcScript.new()
	if not bool(calc.call("load_presets")):
		_fail("presets failed to load: %s" % str(calc.call("errors")))
		return
	_pass("presets loaded")
	var golden: Dictionary = calc.call("load_golden") as Dictionary
	if golden.is_empty():
		_fail("p1_golden.json missing or empty")
		return
	var g_presets: Dictionary = golden.get("presets", {}) as Dictionary
	var ids: PackedStringArray = calc.call("preset_ids") as PackedStringArray
	if ids.size() != 12:
		_fail("expected 12 presets, got %d" % ids.size())
	for pid in ids:
		var block: Dictionary = calc.call("get_preset", pid) as Dictionary
		var row: Dictionary = calc.call("calibration_row", block) as Dictionary
		var ratio: float = float(row.get("ratio", 0.0))
		var result: float = float(row.get("result_km", 0.0))
		var sourced: float = float(row.get("sourced_km", 0.0))
		if ratio < UnitPhysics.CAL_BAND_LO or ratio > UnitPhysics.CAL_BAND_HI:
			_fail("%s ratio %.6f outside [1.010, 1.020]" % [pid, ratio])
		elif result + 1e-9 < sourced:
			_fail("%s result %.6f below sourced %.6f" % [pid, result, sourced])
		else:
			_pass("%s ratio=%.4f result=%.3f k=%.5f" % [pid, ratio, result, float(row.get("k_preset", 0.0))])
		if pid == "me262_a1a" and absf(result - 1071.0) > 1e-6:
			_fail("Me 262 must be exactly 1071 km, got %.9f" % result)
		if g_presets.has(pid):
			_cmp_num("cal.%s.result_km" % pid, result, float((g_presets[pid] as Dictionary).get("result_km", 0.0)))
			_cmp_num("cal.%s.ratio" % pid, ratio, float((g_presets[pid] as Dictionary).get("ratio", 0.0)))
			_cmp_num("cal.%s.k_preset" % pid, float(row.get("k_preset", 0.0)), float((g_presets[pid] as Dictionary).get("k_preset", 0.0)))
			_cmp_int("cal.%s.hexes" % pid, int(row.get("hexes", 0)), int((g_presets[pid] as Dictionary).get("hexes", 0)))
	var pairs: Dictionary = {
		"p51_tank": UnitPhysics.p51_tank_pair(),
		"p51_bc_to_d": UnitPhysics.p51_bc_to_d_pair(),
		"typhoon_tanks": UnitPhysics.typhoon_tank_pair(),
	}
	var g_pairs: Dictionary = golden.get("variant_pairs", {}) as Dictionary
	for name in ["p51_tank", "p51_bc_to_d", "typhoon_tanks"]:
		var p: Dictionary = pairs[name] as Dictionary
		var err: float = float(p.get("error", 99.0))
		if absf(err) > 0.05:
			_fail("%s |error|=%.4f > 5%%" % [name, absf(err)])
		else:
			_pass("%s error=%.2f%%" % [name, float(p.get("error_pct", 0.0))])
		if g_pairs.has(name):
			var gp: Dictionary = g_pairs[name] as Dictionary
			_cmp_num("pair.%s.model_delta" % name, float(p.get("model_delta", 0.0)), float(gp.get("model_delta", 0.0)))
			_cmp_num("pair.%s.error" % name, err, float(gp.get("error", 0.0)))
	var cases: Dictionary = calc.call("me262_cases") as Dictionary
	var g_cases: Dictionary = golden.get("me262_cases", {}) as Dictionary
	for cname in ["clean", "sc500", "kg1000_full", "kg1000_fuel_cut"]:
		if not cases.has(cname) or not g_cases.has(cname):
			_fail("missing me262 case %s" % cname)
			continue
		_cmp_eval("me262.%s" % cname, cases[cname] as Dictionary, g_cases[cname] as Dictionary)
	var rato: Dictionary = UnitPhysics.rato_overload_check()
	if bool(rato.get("allowed", true)) != false:
		_fail("RATO stub must stay allowed=false")
	else:
		_pass("RATO stub allowed=false")
	if absf(UnitPhysics.STORE_CLASS_EXPONENT - 1.0) > 1e-12:
		_fail("STORE_CLASS_EXPONENT must be 1.0")
	else:
		_pass("STORE_CLASS_EXPONENT=1.0")


func _cmp_eval(prefix: String, ev: Dictionary, g: Dictionary) -> void:
	var keys: Array = g.keys()
	keys.sort()
	for k in keys:
		var gv: Variant = g[k]
		if gv == null:
			continue
		if typeof(gv) == TYPE_BOOL:
			_compared += 1
			if bool(ev.get(k, not bool(gv))) != bool(gv):
				_fail("%s.%s bool %s vs %s" % [prefix, str(k), str(ev.get(k)), str(gv)])
			continue
		if typeof(gv) == TYPE_INT or (typeof(gv) == TYPE_FLOAT and float(gv) == floor(float(gv)) and str(k).ends_with("hexes")):
			_cmp_int("%s.%s" % [prefix, str(k)], int(ev.get(k, -999)), int(gv))
			continue
		if typeof(gv) == TYPE_FLOAT or typeof(gv) == TYPE_INT:
			_cmp_num("%s.%s" % [prefix, str(k)], float(ev.get(k, 0.0)), float(gv))


func _cmp_num(label: String, got: float, want: float) -> void:
	_compared += 1
	var e: float = UnitPhysics.rel_err(got, want)
	if e > _max_rel:
		_max_rel = e
	if e > 1e-9:
		_fail("%s got=%.12f want=%.12f rel=%g" % [label, got, want, e])


func _cmp_int(label: String, got: int, want: int) -> void:
	_compared += 1
	if got != want:
		_fail("%s got=%d want=%d" % [label, got, want])
