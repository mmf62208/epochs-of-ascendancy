extends SceneTree

## RT-1: road_tier_for_edge across infra × eras × explicit.
## Must FAIL on 497731dd (RoadTierVisual.gd / wrapper missing) and PASS on tip.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadTierForEdgeTest.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRt1RoadTierForEdgeTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRt1RoadTierForEdgeTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessRt1RoadTierForEdgeTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRt1RoadTierForEdgeTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _era(year: int) -> Dictionary:
	if year <= 1924:
		return {"road_infra_min": 5.0, "label": "sparse_1918"}
	if year >= 2000:
		return {"road_infra_min": 2.0, "label": "dense_2026"}
	return {"road_infra_min": 3.0, "label": "standard_1936"}


func _run() -> void:
	var ol_src := ""
	if FileAccess.file_exists("res://scripts/map/InfrastructureOverlayLayer.gd"):
		var f := FileAccess.open("res://scripts/map/InfrastructureOverlayLayer.gd", FileAccess.READ)
		if f != null:
			ol_src = f.get_as_text()
			f.close()
	if "static func road_tier_for_edge" not in ol_src:
		_fail("InfrastructureOverlayLayer.road_tier_for_edge wrapper missing")
	else:
		_pass("overlay wrapper present")
	var cases: Array = [
		{"year": 1936, "infra": 2.9, "explicit": false, "want": 0},
		{"year": 1936, "infra": 3.0, "explicit": false, "want": 1},
		{"year": 1936, "infra": 6.0, "explicit": false, "want": 1},
		{"year": 1936, "infra": 8.9, "explicit": false, "want": 1},
		{"year": 1936, "infra": 9.0, "explicit": false, "want": 2},
		{"year": 1936, "infra": 0.0, "explicit": true, "want": 2},
		{"year": 1918, "infra": 4.9, "explicit": false, "want": 0},
		{"year": 1918, "infra": 5.0, "explicit": false, "want": 1},
		{"year": 1918, "infra": 8.0, "explicit": false, "want": 1},
		{"year": 1918, "infra": 11.0, "explicit": false, "want": 2},
		{"year": 1918, "infra": 1.0, "explicit": true, "want": 2},
		{"year": 2026, "infra": 1.9, "explicit": false, "want": 0},
		{"year": 2026, "infra": 2.0, "explicit": false, "want": 1},
		{"year": 2026, "infra": 5.0, "explicit": false, "want": 1},
		{"year": 2026, "infra": 8.0, "explicit": false, "want": 2},
		{"year": 2026, "infra": 0.5, "explicit": true, "want": 2},
	]
	for row in cases:
		var year: int = int(row["year"])
		var era: Dictionary = _era(year)
		var got: int = RoadTierVisualScript.road_tier_for_edge(
			float(row["infra"]), era, bool(row["explicit"])
		)
		var wrap: int = RoadTierVisualScript.road_tier_for_edge(
			float(row["infra"]), era, bool(row["explicit"])
		)
		var want: int = int(row["want"])
		if got != want or wrap != want:
			_fail("year=%d infra=%.1f explicit=%s got=%d wrap=%d want=%d" % [
				year, float(row["infra"]), str(row["explicit"]), got, wrap, want
			])
		else:
			_pass("year=%d infra=%.1f explicit=%s → %d" % [
				year, float(row["infra"]), str(row["explicit"]), got
			])
