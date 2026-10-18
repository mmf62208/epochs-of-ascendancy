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
const DUISBURG := 710402
const DUESSELDORF := 710401
const DORTMUND := 710443
const HAMM := 710445
const MUENSTER := 710429
const METTMANN := 710412
const VIENNA := 710022
const VIENNA_N := 710020
const VIENNA_S := 710021
const MUENCHEN := 710205
const MUENCHEN_LAND := 710220
const MANCHESTER := 711344
const MANCHESTER_SW := 711345
const HOME_CAM := Vector2(7449.6456, 1795.9165)
const ANCHOR_MAX_PX := 32.0

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
	var script: Variant = load(LAYER_PATH)
	if script == null:
		_fail("CityLabelsLayer.gd failed to load")
		_finish()
		return
	var layer: Node = (script as GDScript).new()
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
	_test_anchor_distance(layer)
	_test_close_no_overlap(layer)
	_test_no_duplicate_names(layer)
	_test_essen_at_mid_z15(layer)
	_test_home_cam_ruhr_mid(layer)
	_test_ruhr_priority_over_hamm(layer)
	_test_label_set_stable(layer)
	_test_counter_avoidance(layer)
	_test_no_doubled_draws(layer)
	_test_ruhr_centered_live_zooms(layer)
	_test_air_wing_cover_essen(layer)
	_test_mid_scenario_capitals(layer)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAtlas1CityLabelsTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAtlas1CityLabelsTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _names(placed: Array) -> Dictionary:
	var out: Dictionary = {}
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
	if not names.has("Essen"):
		_fail("mid Ruhr missing Essen")
	else:
		_pass("mid Ruhr has Essen")
	if not names.has("Köln") and not names.has("Cologne"):
		_fail("mid Ruhr missing Köln")
	else:
		_pass("mid Ruhr has Köln")
	if _placed_overlap(placed):
		_fail("Ruhr labels overlap at mid")
	else:
		_pass("Ruhr labels have no pairwise overlap")
	var screen_n := int(layer.call("screen_count"))
	print("ATLAS1 city ruhr_screen=%d" % screen_n)
	if screen_n > 60:
		_fail("mid screen count %d > 60" % screen_n)
	else:
		_pass("mid screen count %d <= 60" % screen_n)
	var essen_row: Dictionary = names.get("Essen", {})
	if not essen_row.is_empty():
		var dist := _anchor_dist_px(essen_row, essen, zoom, essen, vp)
		if dist > ANCHOR_MAX_PX:
			_fail("Essen label drifted %.1f px from its dot" % dist)
		else:
			_pass("Essen label stays on its Ruhr dot (%.1f px)" % dist)


func _test_nation_rect(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1920, 1080)
	var cover := Rect2(Vector2.ZERO, vp)
	layer.call("set_view", 1.55, essen, vp, [cover])
	var placed: Array = layer.call("placed")
	var leftover_towns := 0
	for p in placed:
		if bool(p.get("capital", false)):
			continue
		leftover_towns += 1
	if leftover_towns > 0:
		_fail("nation rect covering the view still left %d non-capital city labels" % leftover_towns)
	else:
		_pass("nation rect hides non-capital city labels")


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
		# Hubs enter at home-band zoom so they are fully on by mid (z1.02).
		if alpha < 0.05:
			_fail("Essen alpha %.3f missing at z1.02" % alpha)
		else:
			_pass("Essen visible at z1.02 (alpha %.3f)" % alpha)
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


func _name_list(placed: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		out.append(str(p.get("name", "")))
	out.sort()
	return out


func _name_key(placed: Array) -> String:
	return ",".join(_name_list(placed))


func _anchor_dist_px(item: Dictionary, world: Vector2, zoom: float, cam: Vector2, vp: Vector2) -> float:
	var anchor := (world - cam) * zoom + vp * 0.5
	var off: Vector2 = item.get("screen_offset", Vector2.ZERO)
	return off.length() if off != Vector2.ZERO else item.get("screen_rect", Rect2()).position.distance_to(anchor)


func _placed_overlap(placed: Array) -> bool:
	var rects: Array = []
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		rects.append(p.get("screen_rect", Rect2()))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i]
			var b: Rect2 = rects[j]
			if a.intersects(b):
				return true
	return false


func _count_name(placed: Array, options: Array) -> int:
	var n := 0
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var nm := str(p.get("name", ""))
		for opt in options:
			if nm == str(opt):
				n += 1
				break
	return n


func _test_anchor_distance(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1280, 800)
	var zooms: Array[float] = [0.80, 1.20, 1.50, 2.40, 2.90]
	var worst := 0.0
	for z_v in zooms:
		var z: float = z_v
		layer.call("set_view", z, essen, vp, [])
		var placed: Array = layer.call("placed")
		for p in placed:
			if float(p.get("alpha", 0.0)) < 0.04:
				continue
			var world: Vector2 = p.get("world", Vector2.ZERO) as Vector2
			var dist := _anchor_dist_px(p, world, z, essen, vp)
			if dist > worst:
				worst = dist
			if dist > ANCHOR_MAX_PX:
				_fail("label %s at z%.2f is %.1f px from its dot" % [str(p.get("name", "")), z, dist])
				return
	print("ATLAS1 city max_anchor_px=%.1f" % worst)
	_pass("label anchors stay within %.0f px at mid/close zooms (worst %.1f)" % [ANCHOR_MAX_PX, worst])


func _test_close_no_overlap(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1280, 800)
	var zooms: Array[float] = [2.30, 2.60, 2.90, 2.904]
	for z_v in zooms:
		var z: float = z_v
		layer.call("set_view", z, essen, vp, [])
		var placed: Array = layer.call("placed")
		if _placed_overlap(placed) or bool(layer.call("has_visual_overlap")):
			_fail("drawn label rects overlap at z%.2f Ruhr view" % z)
			return
		print("ATLAS1 city close_z%.2f n=%d" % [z, int(layer.call("screen_count"))])
	_pass("no overlapping label rects at z2.3-2.9 Ruhr")


func _test_no_duplicate_names(layer: Node) -> void:
	if str(layer.call("display_name_of", VIENNA_N)) != "":
		_fail("Vienna satellite %d still in the label set" % VIENNA_N)
	else:
		_pass("Vienna Umland Nord dropped")
	if str(layer.call("display_name_of", VIENNA_S)) != "":
		_fail("Vienna satellite %d still in the label set" % VIENNA_S)
	else:
		_pass("Vienna Umland Süd dropped")
	var wien := str(layer.call("display_name_of", VIENNA))
	if wien != "Wien" and wien != "Vienna":
		_fail("Wien canonical name is '%s'" % wien)
	else:
		_pass("Wien canonical is %s" % wien)
	if str(layer.call("display_name_of", MUENCHEN_LAND)) != "":
		_fail("München Landkreis still in the label set")
	else:
		_pass("München Landkreis dropped")
	var muc := str(layer.call("display_name_of", MUENCHEN))
	if muc != "München" and muc != "Munich":
		_fail("München canonical name is '%s'" % muc)
	else:
		_pass("München canonical is %s" % muc)
	if str(layer.call("display_name_of", MANCHESTER_SW)) != "":
		_fail("Greater Manchester satellite still in the label set")
	else:
		_pass("Manchester satellites dropped")
	if str(layer.call("display_name_of", MANCHESTER)) != "Manchester":
		_fail("Manchester hub missing")
	else:
		_pass("Manchester hub kept")
	var vienna_w: Vector2 = layer.call("world_of", VIENNA)
	layer.call("set_view", 1.35, vienna_w, Vector2(1280, 800), [])
	var vn := _count_name(layer.call("placed"), ["Wien", "Vienna"])
	if vn != 1:
		_fail("Vienna labelled %d times at z1.35" % vn)
	else:
		_pass("one Vienna/Wien label at z1.35")
	var man_w: Vector2 = layer.call("world_of", MANCHESTER)
	layer.call("set_view", 2.40, man_w, Vector2(1280, 800), [])
	var mn := _count_name(layer.call("placed"), ["Manchester"])
	if mn != 1:
		_fail("Manchester labelled %d times at z2.4" % mn)
	else:
		_pass("one Manchester label at z2.4")
	var muc_w: Vector2 = layer.call("world_of", MUENCHEN)
	layer.call("set_view", 1.55, muc_w, Vector2(1280, 800), [])
	var mcn := _count_name(layer.call("placed"), ["München", "Munich"])
	if mcn != 1:
		_fail("München labelled %d times at z1.55" % mcn)
	else:
		_pass("one München label at z1.55")


func _test_essen_at_mid_z15(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1280, 800)
	layer.call("set_view", 1.02, HOME_CAM, vp, [])
	var base_rc := int(layer.get("rebuild_count"))
	layer.call("sync_view", 1.50, essen, vp, false)
	var after_rc := int(layer.get("rebuild_count"))
	print("ATLAS1 city zoom_rebuild delta=%d" % (after_rc - base_rc))
	if after_rc < base_rc + 1:
		_fail("in-band zoom 1.02→1.50 did not rebuild layout")
	else:
		_pass("in-band zoom rebuilds layout")
	var placed: Array = layer.call("placed")
	var names := _names(placed)
	if not names.has("Essen"):
		_fail("Essen not labelled at z1.5 Ruhr view")
	else:
		_pass("Essen labelled at z1.5 Ruhr view")
	layer.call("set_view", 1.50, essen, vp, [])
	placed = layer.call("placed")
	names = _names(placed)
	if not names.has("Essen"):
		_fail("Essen missing at forced z1.5")
	elif _placed_overlap(placed):
		_fail("z1.5 Ruhr labels overlap")
	else:
		_pass("forced z1.5 Ruhr has Essen and no overlap")


func _test_home_cam_ruhr_mid(layer: Node) -> void:
	## Live Play zooms Home in place. Centering the camera on Essen hid the miss.
	var vp := Vector2(1280, 800)
	var zooms: Array[float] = [1.217, 1.512]
	for z_v in zooms:
		var z: float = z_v
		layer.call("set_view", z, HOME_CAM, vp, [])
		var placed: Array = layer.call("placed")
		var names := _names(placed)
		var shown := ",".join(_name_list(placed))
		print("ATLAS1 city home_cam z%.3f n=%d names=%s" % [z, int(layer.call("screen_count")), shown])
		if not names.has("Essen"):
			_fail("Essen missing at Home-cam z%.3f (live zoom-in path)" % z)
		else:
			_pass("Essen labelled at Home-cam z%.3f" % z)
		if not names.has("Köln") and not names.has("Cologne"):
			_fail("Köln missing at Home-cam z%.3f" % z)
		if bool(layer.call("has_visual_overlap")):
			_fail("Home-cam z%.3f label rects overlap" % z)


func _test_ruhr_priority_over_hamm(layer: Node) -> void:
	var essen := float(layer.call("score_of", ESSEN))
	var duis := float(layer.call("score_of", DUISBURG))
	var duss := float(layer.call("score_of", DUESSELDORF))
	var dort := float(layer.call("score_of", DORTMUND))
	var hamm := float(layer.call("score_of", HAMM))
	var muen := float(layer.call("score_of", MUENSTER))
	print("ATLAS1 city score_ruhr essen=%.1f duis=%.1f duss=%.1f dort=%.1f hamm=%.1f muenster=%.1f" % [
		essen, duis, duss, dort, hamm, muen,
	])
	if essen <= hamm or essen <= muen:
		_fail("Essen score %.1f must beat Hamm %.1f and Münster %.1f" % [essen, hamm, muen])
	elif duis <= hamm or duss <= hamm or dort <= hamm:
		_fail("Ruhr cores must beat Hamm score %.1f" % hamm)
	else:
		_pass("Ruhr cores beat Hamm/Münster on score")
	var vp := Vector2(1280, 800)
	layer.call("set_view", 1.217, HOME_CAM, vp, [])
	var names := _names(layer.call("placed"))
	if names.has("Hamm") and not names.has("Essen"):
		_fail("Hamm labelled at Home-cam z1.217 while Essen is missing")
	elif names.has("Münster") and not names.has("Essen"):
		_fail("Münster labelled at Home-cam z1.217 while Essen is missing")
	else:
		_pass("Home-cam mid does not prefer Hamm/Münster over Essen")


func _test_no_doubled_draws(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1280, 800)
	var zooms: Array[float] = [1.217, 1.512, 2.904]
	for z_v in zooms:
		var z: float = z_v
		var cam := HOME_CAM if z < 2.0 else essen
		layer.call("set_view", z, cam, vp, [])
		var dups: PackedStringArray = layer.call("duplicate_drawn_names")
		if not dups.is_empty():
			_fail("doubled names at z%.3f: %s" % [z, ", ".join(dups)])
			return
		var pids: Dictionary = {}
		for p in layer.call("placed"):
			if float(p.get("alpha", 0.0)) < 0.04:
				continue
			var pid := int(p.get("pid", 0))
			if pids.has(pid):
				_fail("pid %d drawn twice at z%.3f" % [pid, z])
				return
			pids[pid] = true
	_pass("no doubled city names or pids at live zooms")


func _test_ruhr_centered_live_zooms(layer: Node) -> void:
	## Playtester wheeled in over the Ruhr (Essen under the cursor), 1280x800.
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1280, 800)
	var zooms: Array[float] = [1.217, 1.512, 2.904]
	var ok := true
	for z_v in zooms:
		var z: float = z_v
		layer.call("set_view", z, essen, vp, [])
		var placed: Array = layer.call("placed")
		var names := _names(placed)
		print("ATLAS1 city ruhr_cam z%.3f n=%d names=%s" % [
			z, int(layer.call("screen_count")), ",".join(_name_list(placed)),
		])
		if not names.has("Essen"):
			_fail("Essen missing at Ruhr-cam z%.3f" % z)
			ok = false
		if z < 2.0 and not names.has("Köln") and not names.has("Cologne"):
			_fail("Köln missing at Ruhr-cam z%.3f" % z)
			ok = false
		if names.has("Hamm") and not names.has("Essen"):
			_fail("Hamm kept over Essen at Ruhr-cam z%.3f" % z)
			ok = false
		if bool(layer.call("has_visual_overlap")):
			_fail("Ruhr-cam z%.3f label/dot overlap" % z)
			ok = false
	if ok:
		_pass("Ruhr-cam live zooms keep Essen and do not overlap")


func _test_air_wing_cover_essen(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1280, 800)
	var zoom := 1.09
	var cover := Rect2(vp * 0.5 + Vector2(-44.0, -50.0), Vector2(88.0, 100.0))
	layer.call("set_view", zoom, essen, vp, [], [cover])
	var placed: Array = layer.call("placed")
	var names := _names(placed)
	if not names.has("Essen"):
		_fail("Essen missing under air-wing counter at z1.09")
		return
	var rect: Rect2 = (names["Essen"] as Dictionary).get("screen_rect", Rect2())
	if rect.intersects(cover):
		_fail("Essen still under air-wing AABB at z1.09")
	else:
		_pass("Essen nudged off air-wing counter at z1.09")
	layer.call("set_view", 1.35, essen, vp, [], [cover])
	placed = layer.call("placed")
	names = _names(placed)
	if not names.has("Essen"):
		_fail("Essen missing under air-wing counter at z1.35")
		return
	rect = (names["Essen"] as Dictionary).get("screen_rect", Rect2())
	if rect.intersects(cover):
		_fail("Essen still under air-wing AABB at z1.35")
	elif bool(layer.call("has_visual_overlap")):
		_fail("air-wing cover at z1.35 caused label/dot overlap")
	else:
		_pass("Essen clear of air-wing counter at z1.35")


func _test_label_set_stable(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1280, 800)
	layer.call("set_view", 1.50, essen, vp, [])
	var names0 := _name_key(layer.call("placed"))
	var rc0 := int(layer.get("rebuild_count"))
	for _i in 30:
		layer.call("sync_view", 1.50, essen, vp, false)
	var rc1 := int(layer.get("rebuild_count"))
	var names1 := _name_key(layer.call("placed"))
	print("ATLAS1 city stable_rebuild delta=%d names=%d" % [rc1 - rc0, _name_list(layer.call("placed")).size()])
	if rc1 != rc0:
		_fail("label rebuild_count moved with no camera move (%d -> %d)" % [rc0, rc1])
	elif names0 != names1:
		_fail("label set changed with no camera move")
	else:
		_pass("label set stable across frames with no camera move")
	layer.call("set_map_mode", "terrain")
	layer.call("set_map_mode", "political")
	var names2 := _name_key(layer.call("placed"))
	if names2 != names0:
		_fail("map-mode round trip changed the city label set")
	else:
		_pass("map-mode round trip keeps the city label set")


func _test_counter_avoidance(layer: Node) -> void:
	var essen: Vector2 = layer.call("world_of", ESSEN)
	var vp := Vector2(1280, 800)
	var zoom := 1.50
	var cover := Rect2(vp * 0.5 + Vector2(2.0, -18.0), Vector2(52.0, 30.0))
	layer.call("set_view", zoom, essen, vp, [], [cover])
	var placed: Array = layer.call("placed")
	var names := _names(placed)
	if not names.has("Essen"):
		_fail("Essen culled instead of nudging off the counter")
		return
	var rect: Rect2 = (names["Essen"] as Dictionary).get("screen_rect", Rect2())
	if rect.intersects(cover):
		_fail("Essen label still sits under the counter rect")
	else:
		_pass("Essen label avoids the counter rect")
	var dist := _anchor_dist_px(names["Essen"], essen, zoom, essen, vp)
	if dist > 120.0:
		_fail("counter nudge moved Essen %.1f px from its dot" % dist)
	else:
		_pass("counter nudge kept Essen within 120 px (%.1f)" % dist)


func _placed_has_pid(placed: Array, pid: int, want_name: String) -> bool:
	for p in placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		if int(p.get("pid", 0)) != pid:
			continue
		var nm := str(p.get("name", ""))
		if nm == want_name:
			return true
	return false


func _test_mid_scenario_capitals(layer: Node) -> void:
	var vp := Vector2(1280, 800)
	var zoom := 1.35
	var cover := Rect2(vp * 0.5 + Vector2(-90.0, -40.0), Vector2(220.0, 90.0))
	var missing: PackedStringArray = PackedStringArray()
	for i in TIER4.size():
		var pid: int = TIER4[i]
		var want := str(TIER4_NAMES[i])
		var world: Vector2 = layer.call("world_of", pid)
		if world == Vector2.ZERO:
			missing.append("%s pid %d dropped from candidates" % [want, pid])
			continue
		var shown := str(layer.call("display_name_of", pid))
		if shown != want:
			missing.append("%s display is '%s'" % [want, shown])
			continue
		layer.call("set_view", zoom, world, vp, [])
		var placed: Array = layer.call("placed")
		if not _placed_has_pid(placed, pid, want):
			missing.append("%s missing label at z1.35" % want)
			continue
		layer.call("set_view", zoom, world, vp, [cover], [cover])
		placed = layer.call("placed")
		if not _placed_has_pid(placed, pid, want):
			missing.append("%s culled by obstacles at z1.35" % want)
			continue
		print("ATLAS1 city mid_capital pid=%d name=%s" % [pid, want])
	if missing.is_empty():
		_pass("all 8 scenario capitals have a dot and label at z1.35")
	else:
		for msg in missing:
			_fail("mid capital: %s" % msg)
