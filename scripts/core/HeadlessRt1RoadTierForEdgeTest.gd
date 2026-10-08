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
	if not RoadTierVisualScript.tier_visible_at_zoom(0, false, 2, 1.80):
		_fail("mid zoom must show highway")
	else:
		_pass("mid zoom shows highway")
	if not RoadTierVisualScript.end_labels_visible_at_zoom(1.80):
		_fail("mid zoom must show Bonn/Köln/Leverkusen labels")
	else:
		_pass("mid zoom shows city labels")
	if RoadTierVisualScript.end_labels_visible_at_zoom(0.40):
		_fail("Europe Home must hide city labels")
	else:
		_pass("Europe Home hides city labels")
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
		_fail("close/far gold spine must stay 16 px")
	else:
		_pass("close/far gold spine 16 px")
	if "GOLD_SPINE_HALO_SCREEN_PX := 20.0" not in ol_src:
		_fail("close/far gold halo must stay 20 px")
	else:
		_pass("close/far gold halo 20 px")
	if "GOLD_SPINE_MID_SCREEN_PX := 28.0" not in ol_src or "GOLD_SPINE_MID_HALO_SCREEN_PX := 34.0" not in ol_src:
		_fail("mid-zoom gold must be 28 px on 34 px halo")
	else:
		_pass("mid-zoom gold 28/34")
	var vis_src := ""
	if FileAccess.file_exists("res://scripts/map/RoadTierVisual.gd"):
		var vf := FileAccess.open("res://scripts/map/RoadTierVisual.gd", FileAccess.READ)
		if vf != null:
			vis_src = vf.get_as_text()
			vf.close()
	if "HIGHWAY_CASING_SCREEN_PX := 12.0" not in vis_src:
		_fail("highway casing must be 12 px (wider than paved, thinner than gold)")
	else:
		_pass("highway casing 12 px")
	if "HIGHWAY_FAR_CASING_SCREEN_PX := 9.0" not in vis_src:
		_fail("Europe Home highway casing must be 9 px")
	else:
		_pass("far highway casing 9 px")
	if "HIGHWAY_FAR_CORE_SCREEN_PX := 5.5" not in vis_src:
		_fail("Europe Home highway core must be 5.5 px")
	else:
		_pass("far highway core 5.5 px")
	if not is_equal_approx(RoadTierVisualScript.screen_width_for_tier(RoadTierVisualScript.TIER_HIGHWAY, 0), 9.0):
		_fail("far screen width got %.2f" % RoadTierVisualScript.screen_width_for_tier(RoadTierVisualScript.TIER_HIGHWAY, 0))
	else:
		_pass("lod 0 highway width 9")
	if not is_equal_approx(RoadTierVisualScript.screen_width_for_tier(RoadTierVisualScript.TIER_HIGHWAY, 1), 12.0):
		_fail("mid screen width got %.2f" % RoadTierVisualScript.screen_width_for_tier(RoadTierVisualScript.TIER_HIGHWAY, 1))
	else:
		_pass("lod 1 highway width 12")
	if RoadTierVisualScript.highway_core_color(true) != RoadTierVisualScript.HIGHWAY_STRIPE_COLOR:
		_fail("far core must use the gold stripe color")
	else:
		_pass("far core is gold stripe")
	if RoadTierVisualScript.highway_core_color(false) != RoadTierVisualScript.HIGHWAY_CORE_COLOR:
		_fail("mid/close core must stay dark")
	else:
		_pass("mid/close core stays dark")
	if "highway_core_color(far)" not in ol_src:
		_fail("overlay far/mid core must call highway_core_color(far)")
	else:
		_pass("overlay uses highway_core_color(far)")
	if "var core := RoadTierVisualScript.HIGHWAY_CORE_COLOR" in ol_src:
		_fail("overlay must not paint the dark core on the far band")
	else:
		_pass("dark core is not unconditional")
	if "_draw_road_quad" not in ol_src:
		_fail("highways must use non-AA filled quads")
	else:
		_pass("highway non-AA quads")
	if "_make_end_label(\"Köln\")" not in ol_src:
		_fail("S2 must include a Köln city label")
	else:
		_pass("Köln city label")
	_test_spine_pairs()
	if "draw_line(pts[i - 1], pts[i], ROAD_EXPLICIT_COLOR, gold_w, true)" in ol_src:
		_fail("gold spine must not use antialiased draw_line")
	else:
		_pass("gold spine non-AA")


func _pair_kept(trunk: Array, a: int, b: int) -> bool:
	var want := RoadTierVisualScript.edge_key(a, b)
	for row_v in trunk:
		var row: Dictionary = row_v
		if RoadTierVisualScript.edge_key(int(row.get("p1", 0)), int(row.get("p2", 0))) == want:
			return true
	return false


func _test_spine_pairs() -> void:
	var draw: Array = RoadTierVisualScript.must_draw_pairs()
	var draw_keys: Dictionary = {}
	for pair_v in draw:
		var pair: Array = pair_v
		draw_keys[RoadTierVisualScript.edge_key(int(pair[0]), int(pair[1]))] = true
	var bonn_koln := RoadTierVisualScript.edge_key(RoadTierVisualScript.BONN_ID, RoadTierVisualScript.KOELN_ID)
	var koln_lev := RoadTierVisualScript.edge_key(RoadTierVisualScript.KOELN_ID, RoadTierVisualScript.LEVERKUSEN_ID)
	if not draw_keys.has(bonn_koln) or not draw_keys.has(koln_lev):
		_fail("must-draw must keep Bonn–Köln and Köln–Leverkusen")
	else:
		_pass("must-draw Bonn–Köln and Köln–Leverkusen")
	for pair_v in RoadTierVisualScript.must_not_draw_pairs():
		var pair: Array = pair_v
		var key := RoadTierVisualScript.edge_key(int(pair[0]), int(pair[1]))
		if draw_keys.has(key):
			_fail("must-not pair %s is in must-draw" % key)
			return
	_pass("Köln–Essen and Köln–Düren stay out of must-draw")
	var cands: Array = [
		{
			"p1": RoadTierVisualScript.BONN_ID,
			"p2": RoadTierVisualScript.KOELN_ID,
			"c1": Vector2(0, 0),
			"c2": Vector2(4, 0),
			"avg_infra": 1.0,
			"weight": 1.0,
			"explicit": false,
			"tier": 0,
		},
		{
			"p1": RoadTierVisualScript.KOELN_ID,
			"p2": RoadTierVisualScript.LEVERKUSEN_ID,
			"c1": Vector2(4, 0),
			"c2": Vector2(7, 0),
			"avg_infra": 1.0,
			"weight": 1.0,
			"explicit": false,
			"tier": 0,
		},
	]
	var trunk: Array = RoadTierVisualScript.select_trunk_edges(cands)
	if not _pair_kept(trunk, RoadTierVisualScript.BONN_ID, RoadTierVisualScript.KOELN_ID):
		_fail("trunk dropped Bonn–Köln")
	elif not _pair_kept(trunk, RoadTierVisualScript.KOELN_ID, RoadTierVisualScript.LEVERKUSEN_ID):
		_fail("trunk dropped Köln–Leverkusen")
	else:
		_pass("trunk keeps Bonn–Köln and Köln–Leverkusen")
	# Real board drops these on the centroid-gap cap before the trunk sees them.
	if not RoadTierVisualScript.road_edge_passes_sanity(7.86, false, false):
		_fail("Bonn–Köln gap 7.86 must pass")
	elif not RoadTierVisualScript.road_edge_passes_sanity(3.15, false, false):
		_fail("Köln–Leverkusen gap 3.15 must pass")
	elif RoadTierVisualScript.road_edge_passes_sanity(12.78, false, false):
		_fail("Köln–Düren gap 12.78 must fail the centroid cap")
	elif RoadTierVisualScript.road_edge_passes_sanity(14.62, false, false):
		_fail("Köln–Essen gap 14.62 must fail the centroid cap")
	else:
		_pass("centroid cap keeps the spine and drops Düren and Essen")
