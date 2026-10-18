extends SceneTree

## STAIR-1. Axis share, fidelity, and raw course_points(). Distance is local.
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessStair1RhineSmoothTest.gd

const COURSE_PATH := "res://data/map/rx1_rhine_crossings.json"
const LAYER_PATH := "res://scripts/map/Rx1RhineLayer.gd"

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessStair1RhineSmoothTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessStair1RhineSmoothTest: ", msg)


func _run_and_quit() -> void:
	if not ResourceLoader.exists(LAYER_PATH):
		_fail("Rx1RhineLayer missing")
		_finish()
		return
	var raw_json := _load_course()
	if raw_json.size() < 2:
		_fail("course json unreadable")
		_finish()
		return
	var Rx1 = load("res://scripts/map/Rx1RhineCrossing.gd")
	Rx1.ensure_loaded()
	var raw: PackedVector2Array = Rx1.course_points()
	if not _same_course(raw, raw_json):
		_fail("course_points() does not match the raw json course (%d vs %d)" % [raw.size(), raw_json.size()])
	else:
		_pass("course_points() is the raw course (%d)" % raw.size())
	var layer: Node2D = load(LAYER_PATH).new()
	root.add_child(layer)
	var display: PackedVector2Array = layer.call("display_points")
	var share := _axis_share(display, 0.02)
	var dev := _max_dev(display, raw_json)
	var ends := display.size() >= 2 and display[0].distance_to(raw_json[0]) < 0.001 and display[display.size() - 1].distance_to(raw_json[raw_json.size() - 1]) < 0.001
	print("ATLAS1 rhine axis=%.4f max_dev=%.3f display=%d raw=%d ends=%s" % [
		share, dev, display.size(), raw_json.size(), str(ends),
	])
	if share >= 0.10:
		_fail("axis-aligned segment share %.3f >= 0.10" % share)
	else:
		_pass("axis share %.3f < 0.10" % share)
	if dev > 1.5:
		_fail("display vertex %.3f wu off the raw course" % dev)
	else:
		_pass("fidelity %.3f wu <= 1.5" % dev)
	if not ends:
		_fail("endpoints moved")
	else:
		_pass("endpoints match the raw course")
	if display.size() <= raw_json.size():
		_fail("display polyline was not smoothed (%d <= raw %d)" % [display.size(), raw_json.size()])
	else:
		_pass("smoothed display has %d vertices" % display.size())
	# course_points must still be the json after the layer built its cache.
	var again: PackedVector2Array = Rx1.course_points()
	if not _same_course(again, raw_json):
		_fail("course_points() changed after the display cache was built")
	else:
		_pass("course_points() unchanged after display cache")
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessStair1RhineSmoothTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessStair1RhineSmoothTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _load_course() -> PackedVector2Array:
	var out := PackedVector2Array()
	var text := FileAccess.get_file_as_string(COURSE_PATH)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return out
	var course: Variant = (data as Dictionary).get("course", {})
	if typeof(course) != TYPE_DICTIONARY:
		return out
	var pts: Variant = (course as Dictionary).get("points", [])
	if not (pts is Array):
		return out
	for pair in pts:
		if pair is Array and (pair as Array).size() >= 2:
			out.append(Vector2(float(pair[0]), float(pair[1])))
	return out


func _same_course(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.001:
			return false
	return true


func _axis_share(pts: PackedVector2Array, tol: float) -> float:
	var n := 0
	var ax := 0
	for i in range(pts.size() - 1):
		var dx := pts[i + 1].x - pts[i].x
		var dy := pts[i + 1].y - pts[i].y
		if dx * dx + dy * dy < 1e-8:
			continue
		n += 1
		if absf(dx) <= tol or absf(dy) <= tol:
			ax += 1
	if n == 0:
		return 1.0
	return float(ax) / float(n)


func _max_dev(pts: PackedVector2Array, raw: PackedVector2Array) -> float:
	var worst := 0.0
	for p in pts:
		var d := _dist_to_polyline(p, raw)
		if d > worst:
			worst = d
	return worst


func _dist_to_polyline(p: Vector2, line: PackedVector2Array) -> float:
	if line.size() < 2:
		return 1.0e9
	var best := 1.0e18
	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		var vx := b.x - a.x
		var vy := b.y - a.y
		var l2 := vx * vx + vy * vy
		var t := 0.0
		if l2 > 1e-12:
			t = clampf(((p.x - a.x) * vx + (p.y - a.y) * vy) / l2, 0.0, 1.0)
		var dx := p.x - (a.x + t * vx)
		var dy := p.y - (a.y + t * vy)
		var d := dx * dx + dy * dy
		if d < best:
			best = d
	return sqrt(best)
