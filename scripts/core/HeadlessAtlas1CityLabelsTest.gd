extends SceneTree

## ATLAS-1 city labels. Fails on a tree with no CityLabelsLayer.
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd

const LAYER_PATH := "res://scripts/map/CityLabelsLayer.gd"
const TIER4 := [
	710300, 710707, 710963, 711112, 711414, 800792, 903995, 903534,
]
const TIER4_NAMES := [
	"Berlin", "Paris", "Rome", "Warsaw", "London", "Washington", "Tokyo", "Moscow",
]
const RUHR := {
	710403: "Essen",
	710401: "Düsseldorf",
	710402: "Duisburg",
	710443: "Dortmund",
	710417: "Köln",
}
const ESSEN := 710403
const METTMANN := 710412

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAtlas1CityLabelsTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAtlas1CityLabelsTest: ", msg)


func _build_bar_ms() -> float:
	var raw: String = OS.get_environment("EOA_ATLAS1_BUILD_BAR_MS").strip_edges()
	if raw.is_empty() or not raw.is_valid_float():
		return 150.0
	return raw.to_float()


func _run_and_quit() -> void:
	if not ResourceLoader.exists(LAYER_PATH):
		_fail("CityLabelsLayer.gd missing")
		_finish()
		return
	var layer: Node = load(LAYER_PATH).new()
	root.add_child(layer)
	_test_bands(layer)
	_test_home(layer)
	_test_ruhr(layer)
	_test_nation_rect(layer)
	_test_cap(layer)
	_test_rebuild(layer)
	_test_fade(layer)
	_test_capital_priority(layer)
	_test_score(layer)
	_test_states(layer)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAtlas1CityLabelsTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAtlas1CityLabelsTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _names(placed: Array) -> Dictionary:
	var out := {}
	for p in placed:
		out[str(p.get("name", ""))] = p
	return out


func _test_bands(layer: Node) -> void:
	var home := int(layer.call("eligible_count", "home"))
	var strategic := int(layer.call("eligible_count", "strategic"))
	var mid := int(layer.call("eligible_count", "mid"))
	var close := int(layer.call("eligible_count", "close"))
	var total := int(layer.call("candidate_count"))
	print("ATLAS1 city candidates=%d home=%d strategic=%d mid=%d close=%d build_ms=%.1f" % [
		total, home, strategic, mid, close, float(layer.call("build_ms")),
	])
	if total < 2000:
		_fail("candidate count %d < 2000" % total)
	else:
		_pass("candidates %d" % total)
	if home != 8:
		_fail("home eligible %d != 8 tier-4 capitals" % home)
	else:
		_pass("home eligible 8")
	if strategic < home + 20:
		_fail("strategic eligible %d should add tier-3" % strategic)
	else:
		_pass("strategic eligible %d" % strategic)
	if mid <= strategic:
		_fail("mid eligible %d should exceed strategic %d" % [mid, strategic])
	else:
		_pass("mid eligible %d" % mid)
	if close < total:
		_fail("close eligible %d < candidates %d" % [close, total])
	else:
		_pass("close eligible %d" % close)
	var bar_ms: float = _build_bar_ms()
	var build_ms := float(layer.call("build_ms"))
	if build_ms > bar_ms:
		_fail("city build %.1f ms > %.0f" % [build_ms, bar_ms])
	else:
		_pass("city build %.1f ms" % build_ms)
	if layer.call("is_eligible", METTMANN, "mid"):
		_fail("Mettmann (no Kreisfreie score) must stay out of mid")
	else:
		_pass("Mettmann excluded at mid")
	if not layer.call("is_eligible", ESSEN, "mid"):
		_fail("Essen score must clear the mid tier-2 floor")
	else:
		_pass("Essen eligible at mid")
	if layer.call("is_eligible", METTMANN, "home") or layer.call("is_eligible", ESSEN, "home"):
		_fail("tier-2 leaked into home")
	else:
		_pass("home stays tier-4")


func _test_home(layer: Node) -> void:
	var min_v := Vector2(1.0e12, 1.0e12)
	var max_v := Vector2(-1.0e12, -1.0e12)
	for pid in TIER4:
		var w: Vector2 = layer.call("world_of", pid)
		if w == Vector2.ZERO:
			_fail("missing world for tier-4 %d" % pid)
			return
		min_v = min_v.min(w)
		max_v = max_v.max(w)
	var zoom := 0.40
	var cam := (min_v + max_v) * 0.5
	var span := (max_v - min_v) * zoom
	var vp := span + Vector2(800, 500)
	layer.call("set_view", zoom, cam, vp, [])
	var placed: Array = layer.call("placed")
	var names := _names(placed)
	var missing := 0
	for n in TIER4_NAMES:
		if not names.has(n):
			missing += 1
			_fail("home missing %s" % n)
	if missing == 0:
		_pass("home shows all 8 tier-4 names")
	if int(layer.call("screen_count")) > 60:
		_fail("home screen count %d > 60" % int(layer.call("screen_count")))
	else:
		_pass("home screen count %d" % int(layer.call("screen_count")))


func _test_ruhr(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var zoom := 1.55
	var vp := Vector2(1920, 1080)
	layer.call("set_view", zoom, essen, vp, [])
	var placed: Array = layer.call("placed")
	var names := _names(placed)
	var rects: Array = []
	for pname in RUHR.values():
		if not names.has(pname):
			_fail("mid Ruhr missing %s" % pname)
		else:
			rects.append((names[pname] as Dictionary).get("screen_rect", Rect2()))
	if rects.size() == RUHR.size():
		var overlap := false
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				var a: Rect2 = rects[i]
				var b: Rect2 = rects[j]
				if a.intersects(b):
					overlap = true
					_fail("Ruhr labels overlap %s / %s" % [str(a), str(b)])
		if not overlap:
			_pass("Ruhr five labelled with no pairwise overlap")
	var screen_n := int(layer.call("screen_count"))
	print("ATLAS1 city ruhr_screen=%d" % screen_n)
	if screen_n > 60:
		_fail("mid screen count %d > 60" % screen_n)
	else:
		_pass("mid screen count %d <= 60" % screen_n)
	var essen_row: Dictionary = names.get("Essen", {})
	if not essen_row.is_empty():
		var rect: Rect2 = essen_row.get("screen_rect", Rect2())
		var anchor := (essen - essen) * zoom + vp * 0.5
		anchor = vp * 0.5
		if rect.position.distance_to(anchor) > 80.0:
			_fail("Essen label drifted %.1f px from camera center" % rect.position.distance_to(anchor))
		else:
			_pass("Essen label stays on the Ruhr frame")


func _test_nation_rect(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1920, 1080)
	var cover := Rect2(Vector2.ZERO, vp)
	layer.call("set_view", 1.55, essen, vp, [cover])
	var placed: Array = layer.call("placed")
	if not placed.is_empty():
		_fail("nation rect covering the view still left %d city labels" % placed.size())
	else:
		_pass("nation rect hides city labels")


func _test_cap(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	layer.call("set_view", 1.55, essen, Vector2(1920, 1080), [])
	if int(layer.call("screen_count")) > 60:
		_fail("cap exceeded")
	else:
		_pass("cap held")


func _test_rebuild(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	layer.call("set_view", 0.40, essen, Vector2(1280, 720), [])
	var base := int(layer.get("rebuild_count"))
	for _i in 120:
		layer._process(0.016)
	var idle := int(layer.get("rebuild_count"))
	if idle != base:
		_fail("rebuild_count moved across 120 idle frames (%d -> %d)" % [base, idle])
	else:
		_pass("rebuild_count idle delta 0 (%d)" % idle)
	layer.call("set_view", 0.70, essen, Vector2(1280, 720), [])
	var after := int(layer.get("rebuild_count"))
	print("ATLAS1 city rebuild_idle=%d rebuild_after_band=%d" % [idle - base, after - idle])
	if after != idle + 1:
		_fail("band change rebuild delta %d != 1" % (after - idle))
	else:
		_pass("one rebuild per band change")


func _test_fade(layer: Node) -> void:
	var lod = load("res://scripts/map/MapZoomLOD.gd")
	var a := float(lod.city_label_fade_alpha(1.02, 1.0))
	var b := float(layer.call("fade_alpha", 1.02, 1.0))
	print("ATLAS1 city fade_1_02=%.3f layer=%.3f" % [a, b])
	if a < 0.05 or a > 0.70 or absf(a - b) > 0.001:
		_fail("fade at zoom 1.02 enter 1.0 is %.3f (want a ramp near 0.25)" % a)
	else:
		_pass("fade ramps (%.3f)" % a)
	var a0 := float(lod.city_label_fade_alpha(0.99, 1.0))
	if a0 > 0.001:
		_fail("fade before enter is %.3f" % a0)
	else:
		_pass("fade is 0 before the enter zoom")
	var essen: Vector2 = layer.call("world_of", ESSEN)
	layer.call("set_view", 1.02, essen, Vector2(1920, 1080), [])
	var placed: Array = layer.call("placed")
	var saw := false
	for p in placed:
		if str(p.get("name", "")) != "Essen":
			continue
		saw = true
		var alpha := float(p.get("alpha", 0.0))
		if alpha < 0.05 or alpha > 0.70:
			_fail("Essen alpha %.3f is not on the ramp" % alpha)
		else:
			_pass("Essen alpha %.3f follows the ramp" % alpha)
	if not saw:
		_fail("Essen missing at zoom 1.02")


func _test_capital_priority(layer: Node) -> void:
	var cam := Vector2(1000, 1000)
	var vp := Vector2(800, 600)
	var world := cam
	var cands := [
		{"pid": 1, "name": "Town", "tier": 2, "capital": false, "score": 9999.0, "world": world, "enter": 0.0},
		{"pid": 2, "name": "Cap", "tier": 1, "capital": true, "score": 10.0, "world": world, "enter": 0.0},
	]
	var placed: Array = layer.call("place_competing", cands, 3.0, cam, vp, [], 0.0)
	if placed.size() != 1:
		_fail("priority fixture placed %d labels (want the single capital)" % placed.size())
		return
	var name := str(placed[0].get("name", ""))
	if name != "Cap":
		_fail("non-capital beat the capital (%s)" % name)
	else:
		_pass("capital beats a higher score when only one slot fits")


func _test_score(layer: Node) -> void:
	var essen := float(layer.call("score_of", ESSEN))
	var mett := float(layer.call("score_of", METTMANN))
	print("ATLAS1 city score_essen=%.1f score_mettmann=%.1f" % [essen, mett])
	if essen <= mett:
		_fail("Essen score %.1f should beat Mettmann %.1f" % [essen, mett])
	else:
		_pass("Essen score %.1f > Mettmann %.1f" % [essen, mett])


func _test_states(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	layer.call("set_map_mode", "states")
	layer.call("set_view", 1.55, essen, Vector2(800, 600), [])
	var placed: Array = layer.call("placed")
	if not placed.is_empty():
		_fail("states map mode still shows %d city labels" % placed.size())
	else:
		_pass("states map mode hides city labels")
	layer.call("set_map_mode", "political")
