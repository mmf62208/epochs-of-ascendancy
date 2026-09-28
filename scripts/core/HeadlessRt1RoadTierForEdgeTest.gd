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
	_test_lod_cull()
	_test_display_rank()


func _test_lod_cull() -> void:
	# Europe Home: rare display highways (top few %) + explicit. Not paved/dirt.
	if RoadTierVisualScript.tier_visible_at_zoom(0, false, 1, 0.40):
		_fail("europe zoom must hide remapped paved")
	else:
		_pass("europe zoom hides remapped paved")
	if not RoadTierVisualScript.tier_visible_at_zoom(0, false, 2, 0.40):
		_fail("europe zoom must keep rare display highway")
	else:
		_pass("europe zoom keeps rare display highway")
	if not RoadTierVisualScript.tier_visible_at_zoom(2, false, 2, 0.40):
		_fail("europe zoom must keep formula+display highway")
	else:
		_pass("europe zoom keeps formula+display highway")
	if not RoadTierVisualScript.tier_visible_at_zoom(0, true, 2, 0.40):
		_fail("europe zoom must keep explicit highway")
	else:
		_pass("europe zoom keeps explicit highway")
	if RoadTierVisualScript.tier_visible_at_zoom(0, false, 0, 1.80):
		_fail("mid zoom must hide dirt")
	else:
		_pass("mid zoom hides dirt")
	if not RoadTierVisualScript.tier_visible_at_zoom(0, false, 1, 1.80):
		_fail("mid zoom must show paved")
	else:
		_pass("mid zoom shows paved")
	if not RoadTierVisualScript.tier_visible_at_zoom(0, false, 0, 2.80):
		_fail("close zoom must show dirt")
	else:
		_pass("close zoom shows dirt")
	if not RoadTierVisualScript.dirt_hidden_at_zoom(0.55):
		_fail("dirt must hide at Europe/Home zoom 0.55")
	else:
		_pass("dirt hidden at Europe/Home")


func _test_display_rank() -> void:
	if RoadTierVisualScript.display_tier_from_rank(0.10, false) != 0:
		_fail("rank 0.10 should be dirt")
	else:
		_pass("rank 0.10 → dirt")
	if RoadTierVisualScript.display_tier_from_rank(0.55, false) != 1:
		_fail("rank 0.55 should be paved")
	else:
		_pass("rank 0.55 → paved")
	if RoadTierVisualScript.display_tier_from_rank(0.80, false) != 1:
		_fail("rank 0.80 should be paved (highways are top few % only)")
	else:
		_pass("rank 0.80 → paved")
	if RoadTierVisualScript.display_tier_from_rank(0.97, false) != 2:
		_fail("rank 0.97 should be rare highway")
	else:
		_pass("rank 0.97 → highway")
	if RoadTierVisualScript.display_tier_from_rank(0.0, true) != 2:
		_fail("explicit rank 0 should be highway")
	else:
		_pass("explicit → highway")
	_test_trunk_sparsifier()


func _test_trunk_sparsifier() -> void:
	# Square cycle A-B-C-D-A. Full mesh has 2 triangles if we add both diagonals;
	# four sides have 0 triangles but 1 cycle. Add a chord to make 1 triangle.
	var a := Vector2(0, 0)
	var b := Vector2(10, 0)
	var c := Vector2(10, 10)
	var d := Vector2(0, 10)
	var cands: Array = [
		{"p1": 1, "p2": 2, "c1": a, "c2": b, "avg_infra": 2.0, "weight": 1.0, "w1": 1.0, "w2": 1.0, "explicit": false, "tier": 0},
		{"p1": 2, "p2": 3, "c1": b, "c2": c, "avg_infra": 2.0, "weight": 1.0, "w1": 1.0, "w2": 1.0, "explicit": false, "tier": 0},
		{"p1": 3, "p2": 4, "c1": c, "c2": d, "avg_infra": 2.0, "weight": 1.0, "w1": 1.0, "w2": 1.0, "explicit": false, "tier": 0},
		{"p1": 4, "p2": 1, "c1": d, "c2": a, "avg_infra": 2.0, "weight": 1.0, "w1": 1.0, "w2": 1.0, "explicit": false, "tier": 0},
		{"p1": 1, "p2": 3, "c1": a, "c2": c, "avg_infra": 1.0, "weight": 1.0, "w1": 1.0, "w2": 1.0, "explicit": false, "tier": 0},
	]
	if RoadTierVisualScript.count_undirected_triangles(cands) < 1:
		_fail("square+diagonal must have a triangle before trunk")
	else:
		_pass("pre-trunk triangle present")
	var trunk: Array = RoadTierVisualScript.select_trunk_edges(cands)
	var tri: int = RoadTierVisualScript.count_undirected_triangles(trunk)
	if tri != 0:
		_fail("trunk must drop triangles got=%d edges=%d" % [tri, trunk.size()])
	else:
		_pass("trunk has 0 triangles edges=%d" % trunk.size())
	if trunk.size() >= cands.size():
		_fail("trunk must drop cyclic extras got=%d from=%d" % [trunk.size(), cands.size()])
	else:
		_pass("trunk dropped cyclic extras %d→%d" % [cands.size(), trunk.size()])
	var deg: Dictionary = RoadTierVisualScript.degree_stats(trunk)
	if int(deg.get("max", 99)) > RoadTierVisualScript.TRUNK_HUB_DEGREE_CAP:
		_fail("trunk max degree %d exceeds hub cap" % int(deg.get("max", 99)))
	else:
		_pass("trunk max degree=%d" % int(deg.get("max", 0)))
	# Must-draw Bonn–Köln survives even among junk.
	var must_cands: Array = cands.duplicate()
	must_cands.append({
		"p1": RoadTierVisualScript.BONN_ID,
		"p2": RoadTierVisualScript.KOELN_ID,
		"c1": Vector2(100, 100),
		"c2": Vector2(104, 100),
		"avg_infra": 1.0,
		"weight": 1.0,
		"explicit": false,
		"tier": 0,
	})
	var must_trunk: Array = RoadTierVisualScript.select_trunk_edges(must_cands)
	var kept := false
	var want := RoadTierVisualScript.edge_key(
		RoadTierVisualScript.BONN_ID, RoadTierVisualScript.KOELN_ID
	)
	for row_v in must_trunk:
		var row: Dictionary = row_v
		if RoadTierVisualScript.edge_key(int(row.get("p1", 0)), int(row.get("p2", 0))) == want:
			kept = true
			break
	if not kept:
		_fail("must-draw Bonn–Köln missing from trunk")
	else:
		_pass("must-draw Bonn–Köln kept")
	# Overlay must call the sparsifier (not terciles).
	var ol_src := ""
	if FileAccess.file_exists("res://scripts/map/InfrastructureOverlayLayer.gd"):
		var f := FileAccess.open("res://scripts/map/InfrastructureOverlayLayer.gd", FileAccess.READ)
		if f != null:
			ol_src = f.get_as_text()
			f.close()
	if "select_trunk_edges" not in ol_src or "assign_rare_display_tiers" not in ol_src:
		_fail("overlay must call select_trunk_edges + assign_rare_display_tiers")
	else:
		_pass("overlay uses trunk + rare highways")
	if "GOLD_SPINE_SCREEN_PX := 16.0" not in ol_src:
		_fail("gold spine must be 16 px (thicker than 8.5 casing)")
	else:
		_pass("gold spine 16 px")
	if "draw_line(pts[i - 1], pts[i], ROAD_EXPLICIT_COLOR, gold_w, true)" in ol_src:
		_fail("gold spine must not use antialiased draw_line")
	else:
		_pass("gold spine non-AA")
