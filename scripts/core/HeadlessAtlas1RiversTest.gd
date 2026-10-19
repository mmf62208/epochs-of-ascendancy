extends SceneTree

## ATLAS-1 major rivers. Distance checks use this file's own point-to-polyline
## function. Fails when MajorRiversLayer is absent.
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd

const LAYER_PATH := "res://scripts/map/MajorRiversLayer.gd"
const NEED := [
	"Danube", "Donau", "Elbe", "Oder", "Vistula", "Seine", "Loire", "Rhône", "Po", "Thames",
]
const VIENNA := Vector2(4467.7, 1021.1)

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAtlas1RiversTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAtlas1RiversTest: ", msg)


func _build_bar_ms() -> float:
	var raw: String = OS.get_environment("EOA_ATLAS1_BUILD_BAR_MS").strip_edges()
	if raw.is_empty() or not raw.is_valid_float():
		return 150.0
	return raw.to_float()


func _run_and_quit() -> void:
	if not ResourceLoader.exists(LAYER_PATH):
		_fail("MajorRiversLayer.gd missing")
		_finish()
		return
	var t0 := Time.get_ticks_usec()
	var layer: Node = load(LAYER_PATH).new()
	root.add_child(layer)
	layer.call("refresh")
	var build_ms := float(layer.call("build_ms"))
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("ATLAS1 rivers build_ms=%.1f wall_ms=%.1f verts=%d" % [build_ms, wall_ms, int(layer.call("vertex_count"))])
	_test_names(layer)
	_test_budget(layer, build_ms)
	_test_fidelity(layer)
	_test_no_rhine(layer)
	_test_vienna(layer)
	_test_labels(layer)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAtlas1RiversTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAtlas1RiversTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _test_names(layer: Node) -> void:
	var names: PackedStringArray = layer.call("selected_names")
	var have := {}
	for n in names:
		have[n] = true
	var missing := PackedStringArray()
	for n in NEED:
		if not have.has(n):
			missing.append(n)
	if not have.has("Dnipro") and not have.has("Dnieper"):
		missing.append("Dnipro")
	if not have.has("Volga"):
		missing.append("Volga")
	if missing.is_empty():
		_pass("selected names include the atlas rivers (%d names)" % names.size())
	else:
		_fail("missing river names %s" % str(missing))


func _test_budget(layer: Node, build_ms: float) -> void:
	var verts := int(layer.call("vertex_count"))
	if verts > 20000:
		_fail("vertex count %d > 20000" % verts)
	elif verts < 1000:
		_fail("vertex count %d looks empty" % verts)
	else:
		_pass("vertices %d <= 20000" % verts)
	var bar_ms: float = _build_bar_ms()
	if build_ms > bar_ms:
		_fail("river build %.1f ms > %.0f" % [build_ms, bar_ms])
	else:
		_pass("river build %.1f ms" % build_ms)


func _test_fidelity(layer: Node) -> void:
	var raws: Array = layer.call("raw_polylines")
	var smooths: Array = layer.call("smoothed_polylines")
	if raws.size() != smooths.size() or raws.is_empty():
		_fail("raw/smooth polyline mismatch %d/%d" % [raws.size(), smooths.size()])
		return
	var worst := 0.0
	var raw_n := 0
	var smooth_n := 0
	for i in raws.size():
		var raw: PackedVector2Array = raws[i]
		var smooth: PackedVector2Array = smooths[i]
		raw_n += raw.size()
		smooth_n += smooth.size()
		for p in smooth:
			var d := _dist_to_polyline(p, raw)
			if d > worst:
				worst = d
	print("ATLAS1 rivers max_dev=%.3f raw_verts=%d smooth_verts=%d" % [worst, raw_n, smooth_n])
	if worst > 1.5:
		_fail("smoothed vertex %.3f wu from its raw line" % worst)
	else:
		_pass("smoothed vertices within %.3f wu of the raw line" % worst)
	if smooth_n <= raw_n:
		_fail("smoothing did not add vertices (%d <= %d)" % [smooth_n, raw_n])
	else:
		_pass("chaikin added vertices %d -> %d" % [raw_n, smooth_n])


func _test_no_rhine(layer: Node) -> void:
	if layer.call("draws_rhine_stroke"):
		_fail("MajorRiversLayer strokes Rhein/Rhine (double draw)")
	else:
		_pass("Rhine stroke stays on Rx1RhineLayer")
	var records: Array = layer.call("river_records")
	for rec in records:
		var n := str(rec.get("name", ""))
		if n == "Rhein" or n == "Rhine" or n == "Rhin":
			_fail("stroked part named %s" % n)
			return


func _test_vienna(layer: Node) -> void:
	var records: Array = layer.call("river_records")
	var best := 1.0e9
	for rec in records:
		var canon := str(rec.get("canonical", ""))
		if canon != "Danube":
			continue
		var raw: PackedVector2Array = rec.get("raw", PackedVector2Array())
		for p in raw:
			var d := p.distance_to(VIENNA)
			if d < best:
				best = d
	print("ATLAS1 rivers danube_vienna_wu=%.2f" % best)
	if best > 6.0:
		_fail("Danube is %.1f wu from Vienna — mercator reprojection missed" % best)
	else:
		_pass("Danube passes %.2f wu from Vienna" % best)


func _test_labels(layer: Node) -> void:
	var vienna_world := VIENNA * 1.728
	layer.call("set_view", 1.4, vienna_world, Vector2(1920, 1080))
	var labels: PackedStringArray = layer.call("label_names_for_view")
	var have := {}
	for n in labels:
		have[n] = int(have.get(n, 0)) + 1
	if not have.has("Danube"):
		_fail("mid view over Vienna has no Danube label (%s)" % str(labels))
	else:
		_pass("Danube label at mid")
	var dup := false
	for n in have.keys():
		if int(have[n]) > 1:
			dup = true
			_fail("river %s labelled %d times on one screen" % [n, int(have[n])])
	if not dup:
		_pass("at most one label per river")


func _dist_to_polyline(p: Vector2, line: PackedVector2Array) -> float:
	if line.is_empty():
		return 1.0e9
	if line.size() == 1:
		return p.distance_to(line[0])
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
