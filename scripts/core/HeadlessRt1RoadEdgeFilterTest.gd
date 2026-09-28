extends SceneTree

## RT-1: must-draw Bonn–Köln / Köln–Leverkusen; must-NOT Köln–Essen / Köln–Düren.
## Uses NUTS3 centroids + shared-border / Rhineland centroid-gap fallback.
## Must FAIL on 497731dd (filter missing) and PASS on tip.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRt1RoadEdgeFilterTest.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")

const KOELN := 710417
const BONN := 710416
const LEV := 710418
const ESSEN := 710403
const DUREN := 710419

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRt1RoadEdgeFilterTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRt1RoadEdgeFilterTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessRt1RoadEdgeFilterTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRt1RoadEdgeFilterTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _centroid_of(pts: Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	var n := 0
	for pt in pts:
		if typeof(pt) == TYPE_ARRAY and pt.size() >= 2:
			acc += Vector2(float(pt[0]), float(pt[1]))
			n += 1
	if n <= 0:
		return Vector2.ZERO
	return acc / float(n)


func _run() -> void:
	_test_pure_thresholds()
	_test_nuts3_pairs()


func _test_pure_thresholds() -> void:
	# Distances measured on the Rhineland theater (same cents on nuts3 + world_accurate).
	var pairs: Array = [
		{"a": BONN, "b": KOELN, "d": 7.858, "must": true},
		{"a": KOELN, "b": LEV, "d": 3.151, "must": true},
		{"a": KOELN, "b": ESSEN, "d": 14.619, "must": false},
		{"a": KOELN, "b": DUREN, "d": 12.781, "must": false},
	]
	for row in pairs:
		var ok: bool = RoadTierVisualScript.road_edge_passes_sanity(
			float(row["d"]), false, false, RoadTierVisualScript.RHINE_CENTROID_GAP_CAP
		)
		var wrap: bool = InfrastructureOverlayLayer.road_edge_passes_sanity(
			float(row["d"]), false, false, RoadTierVisualScript.RHINE_CENTROID_GAP_CAP
		)
		var want: bool = bool(row["must"])
		if ok != want or wrap != want:
			_fail("centroid-cap %d-%d d=%.3f got=%s want=%s" % [
				int(row["a"]), int(row["b"]), float(row["d"]), str(ok), str(want)
			])
		else:
			_pass("centroid-cap %d-%d d=%.3f → %s" % [
				int(row["a"]), int(row["b"]), float(row["d"]), "draw" if ok else "drop"
			])
	if RoadTierVisualScript.road_edge_passes_sanity(9.0, true, false, 99.0):
		_fail("known non-border must drop even when under cap")
	else:
		_pass("known non-border drops regardless of distance")
	if not RoadTierVisualScript.road_edge_passes_sanity(40.0, true, true, 1.0):
		_fail("known shared border must draw even over cap")
	else:
		_pass("known shared border draws regardless of distance")


func _test_nuts3_pairs() -> void:
	var geom := _load_json("res://data/provinces_pilot_europe_nuts3/provinces_geometry.json")
	var adj := _load_json("res://data/provinces_pilot_europe_nuts3/province_adjacency.json")
	if geom.is_empty() or adj.is_empty():
		_fail("could not load NUTS3 geometry/adjacency")
		return
	var cents: Dictionary = {}
	var rings: Dictionary = {}
	for g in geom.get("provinces", []):
		if typeof(g) != TYPE_DICTIONARY:
			continue
		var pid: int = int(g.get("id", -1))
		var pts: Array = g.get("points", [])
		cents[pid] = _centroid_of(pts)
		var ring := PackedVector2Array()
		for pt in pts:
			if typeof(pt) == TYPE_ARRAY and pt.size() >= 2:
				ring.append(Vector2(float(pt[0]), float(pt[1])))
		if ring.size() >= 3:
			rings[pid] = ring
	var shared: Dictionary = RoadTierVisualScript.shared_border_keys_from_rings(rings, 4.0)
	var have_shared: bool = not shared.is_empty()
	if not have_shared:
		_pass("NUTS3 rings produced no shared-edge set; using Rhineland centroid cap")
	else:
		_pass("NUTS3 shared-edge keys=%d" % shared.size())
	var adj_map: Dictionary = adj.get("adjacency", {})
	var knn_has_essen := false
	var knn_has_duren := false
	var knn_raw: Variant = adj_map.get(str(KOELN), [])
	if typeof(knn_raw) == TYPE_ARRAY:
		for nid in knn_raw:
			if int(nid) == ESSEN:
				knn_has_essen = true
			if int(nid) == DUREN:
				knn_has_duren = true
	if knn_has_essen:
		_pass("NUTS3 kNN still lists Köln–Essen (filter must drop it)")
	if knn_has_duren:
		_pass("NUTS3 kNN still lists Köln–Düren (filter must drop it)")
	var checks: Array = [
		{"a": BONN, "b": KOELN, "must": true, "name": "Bonn-Köln"},
		{"a": KOELN, "b": LEV, "must": true, "name": "Köln-Leverkusen"},
		{"a": KOELN, "b": ESSEN, "must": false, "name": "Köln-Essen"},
		{"a": KOELN, "b": DUREN, "must": false, "name": "Köln-Düren"},
	]
	for row in checks:
		var a: int = int(row["a"])
		var b: int = int(row["b"])
		var c1: Vector2 = cents.get(a, Vector2.ZERO)
		var c2: Vector2 = cents.get(b, Vector2.ZERO)
		if c1 == Vector2.ZERO or c2 == Vector2.ZERO:
			_fail("missing centroid for %s" % str(row["name"]))
			continue
		var key := RoadTierVisualScript.edge_key(a, b)
		var share := shared.has(key)
		var ok: bool = RoadTierVisualScript.road_edge_passes_sanity(
			c1.distance_to(c2), have_shared, share, RoadTierVisualScript.RHINE_CENTROID_GAP_CAP
		)
		var want: bool = bool(row["must"])
		if ok != want:
			_fail("%s share=%s d=%.3f got=%s want=%s" % [
				str(row["name"]), str(share), c1.distance_to(c2), str(ok), str(want)
			])
		else:
			_pass("%s share=%s d=%.3f → %s" % [
				str(row["name"]), str(share), c1.distance_to(c2), "draw" if ok else "drop"
			])
