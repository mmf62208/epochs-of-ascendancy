extends SceneTree

## GAP-NLD-1 FIX r1. Standalone map-select identity + relative timing.
## Not wired into --quick.
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessGapNld1PerfTest.gd

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const MIN_POINTS := 2000
const REL_SLACK := 1.10
const NLD_PIDS: PackedInt32Array = [902785, 902883, 900317]
const SIA_PIDS: PackedInt32Array = [904506, 904507, 904508]
const EU_PIDS: PackedInt32Array = [710300, 710173, 711414, 710707]

var _failures: int = 0
var _mm: Node = null
var _mr: Node = null


func _init() -> void:
	call_deferred("_start")


func _flush() -> void:
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessGapNld1PerfTest: ", msg)
	_flush()


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessGapNld1PerfTest: ", msg)
	_flush()


func _log(msg: String) -> void:
	print("  HeadlessGapNld1PerfTest: ", msg)
	_flush()


func _start() -> void:
	await _run()
	var ok: bool = _failures == 0
	print("HeadlessGapNld1PerfTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessGapNld1PerfTest: RESULT=", "PASS" if ok else "FAIL")
	_flush()
	quit(0 if ok else 1)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	return data if data is Dictionary else {}


func _run() -> void:
	_mm = root.get_node_or_null("MapManager")
	if _mm == null:
		_fail("MapManager missing")
		return
	if not _load_board():
		return
	if not _setup_renderer():
		return
	var t_build: int = Time.get_ticks_usec()
	var n_poly: int = int(_mr.call("gap_nld1_rebuild_pick_index"))
	var build_ms: float = float(Time.get_ticks_usec() - t_build) / 1000.0
	_log("PROFILE rebuild_pick_index_ms=%.2f polys=%d ready=%s" % [
		build_ms, n_poly, str(_mr.call("gap_nld1_pick_index_ready"))
	])
	if n_poly < 3000:
		_fail("pick cache too small n=%d" % n_poly)
		return
	_pass("pick cache n=%d" % n_poly)
	var pts: Array[Vector2] = _build_points()
	if pts.size() < MIN_POINTS:
		_fail("need >=%d points got %d" % [MIN_POINTS, pts.size()])
		return
	_pass("points=%d" % pts.size())
	_run_identity_and_timing(pts)


func _load_board() -> bool:
	var base: Dictionary = _load_json(BASE_PATH)
	var geo: Dictionary = _load_json(GEO_PATH)
	var own_doc: Dictionary = _load_json(OWN_PATH)
	if base.is_empty() or geo.is_empty():
		_fail("data_load_failed")
		return false
	var ProvScript: GDScript = load(PROV_SCRIPT) as GDScript
	var MapDataScript: GDScript = load(MAP_DATA_SCRIPT) as GDScript
	if ProvScript == null or MapDataScript == null:
		_fail("script_load_failed")
		return false
	var owners: Dictionary = own_doc.get("owners", {}) as Dictionary
	var provs: Dictionary = {}
	for row_v in base.get("provinces", []):
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var pid: int = int(row.get("id", 0))
		if pid <= 0:
			continue
		var p: Object = ProvScript.new()
		p.set("id", pid)
		p.set("name", str(row.get("name", "Province %d" % pid)))
		p.set("terrain", str(row.get("terrain", "plains")))
		p.set("domain", str(row.get("domain", "land")))
		var terr_l: String = str(p.get("terrain")).strip_edges().to_lower()
		var dom_l: String = str(p.get("domain")).strip_edges().to_lower()
		p.set("is_sea", terr_l in ["sea", "ocean", "water", "lake"] or dom_l in ["sea", "ocean", "naval"])
		var ot: String = str(owners.get(str(pid), "")).strip_edges().to_upper()
		if not ot.is_empty():
			p.set("owner_tag", ot)
			p.set("controller_tag", ot)
		provs[pid] = p
	var geometry: Dictionary = {}
	for row_v2 in geo.get("provinces", []):
		if typeof(row_v2) != TYPE_DICTIONARY:
			continue
		var row2: Dictionary = row_v2
		var pid2: int = int(row2.get("id", 0))
		if pid2 <= 0:
			continue
		var pts: Array = row2.get("points", [])
		var packed := PackedVector2Array()
		for pt in pts:
			if pt is Array and (pt as Array).size() >= 2:
				var arr: Array = pt
				packed.append(Vector2(float(arr[0]), float(arr[1])))
		geometry[pid2] = {
			"points": packed,
			"label_anchor": row2.get("label_anchor", []),
			"meta": row2.get("meta", {}),
		}
	var adj: Object = null
	if FileAccess.file_exists(ADJ_PATH):
		var AdjScr: GDScript = load("res://scripts/data/AdjacencySystem.gd") as GDScript
		if AdjScr != null:
			adj = AdjScr.new()
			if adj.has_method("load_adjacency"):
				adj.call("load_adjacency", ADJ_PATH)
	var map_data: Object = MapDataScript.new(provs, geometry, adj, {})
	_mm.call("initialize_from_map_data", map_data)
	if _mm.has_method("set_geometry_world_native"):
		_mm.call("set_geometry_world_native", true)
	if _mm.has_method("set_geometry_world_space"):
		_mm.call("set_geometry_world_space", true)
	if _mm.has_method("rebuild_pick_grid"):
		_mm.call("rebuild_pick_grid")
	var n_prov: int = int(_mm.call("get_province_count"))
	if n_prov < 3000:
		_fail("too_few_provinces=%d" % n_prov)
		return false
	_pass("loaded_provinces=%d" % n_prov)
	return true


func _setup_renderer() -> bool:
	var scr: Script = load(SRC_REN) as Script
	if scr == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = scr.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	_mr.set_meta("full_world_underlay_active", true)
	if "provinces" in _mr:
		_mr.provinces = _mm.call("get_all_provinces")
	var geo_copy: Dictionary = {}
	for pid_v in _mr.provinces.keys():
		var pid: int = int(pid_v)
		if _mm.has_method("get_province_geometry"):
			geo_copy[pid] = _mm.call("get_province_geometry", pid)
	if "geometry" in _mr:
		_mr.geometry = geo_copy
	# Do not add_child: MapRenderer._ready expects a full scene (camera, BtnClose).
	return true


func _centroid(pid: int) -> Vector2:
	if _mm != null and _mm.has_method("get_province_centroid"):
		return _mm.call("get_province_centroid", pid)
	return Vector2.ZERO


func _add_grid(into: Array[Vector2], origin: Vector2, size: Vector2, nx: int, ny: int) -> void:
	if nx <= 0 or ny <= 0:
		return
	for iy in ny:
		for ix in nx:
			var fx: float = (float(ix) + 0.5) / float(nx)
			var fy: float = (float(iy) + 0.5) / float(ny)
			into.append(origin + Vector2(size.x * fx, size.y * fy))


func _build_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var bounds: Rect2 = _mm.call("get_world_bounds") if _mm.has_method("get_world_bounds") else Rect2(0, 0, 14000, 7000)
	if bounds.size.x < 100.0 or bounds.size.y < 100.0:
		bounds = Rect2(0, 0, 14156, 7078)
	_add_grid(pts, bounds.position, bounds.size, 40, 36)
	var berlin: Vector2 = _centroid(710300)
	if berlin != Vector2.ZERO:
		_add_grid(pts, berlin - Vector2(180, 140), Vector2(360, 280), 16, 12)
	var nld_c: Vector2 = _centroid(902785)
	if nld_c != Vector2.ZERO:
		_add_grid(pts, nld_c - Vector2(220, 160), Vector2(440, 320), 18, 14)
	var sia_c: Vector2 = _centroid(904506)
	if sia_c != Vector2.ZERO:
		_add_grid(pts, sia_c - Vector2(160, 140), Vector2(320, 280), 14, 12)
	var sea_c: Vector2 = _centroid(950133)
	if sea_c == Vector2.ZERO:
		sea_c = bounds.position + Vector2(bounds.size.x * 0.22, bounds.size.y * 0.35)
	_add_grid(pts, sea_c - Vector2(200, 160), Vector2(400, 320), 12, 10)
	for pid in NLD_PIDS:
		var c: Vector2 = _centroid(int(pid))
		if c != Vector2.ZERO:
			pts.append(c)
			pts.append(c + Vector2(4, 0))
			pts.append(c + Vector2(0, 4))
			pts.append(c + Vector2(-3, 3))
	for pid2 in SIA_PIDS:
		var c2: Vector2 = _centroid(int(pid2))
		if c2 != Vector2.ZERO:
			pts.append(c2)
			pts.append(c2 + Vector2(3, -2))
	for pid3 in EU_PIDS:
		var c3: Vector2 = _centroid(int(pid3))
		if c3 != Vector2.ZERO:
			pts.append(c3)
			pts.append(c3 + Vector2(2, 2))
			pts.append(c3 + Vector2(-2, 1))
	# Sea / empty corners
	pts.append(bounds.position + Vector2(40, 40))
	pts.append(bounds.position + Vector2(bounds.size.x - 40, 40))
	pts.append(bounds.position + Vector2(40, bounds.size.y - 40))
	return pts


func _run_identity_and_timing(pts: Array[Vector2]) -> void:
	# Warm both paths on a handful of points so the timing pass is not cold-compile.
	for i in mini(8, pts.size()):
		_mr.call("gap_nld1_pick_at_world", pts[i], false)
		_mr.call("gap_nld1_pick_at_world", pts[i], true)
	var mismatches: int = 0
	var first_bad: String = ""
	var t_brute: int = Time.get_ticks_usec()
	var brute_ids: PackedInt32Array = PackedInt32Array()
	brute_ids.resize(pts.size())
	for i2 in pts.size():
		brute_ids[i2] = int(_mr.call("gap_nld1_pick_at_world", pts[i2], false))
	var brute_ms: float = float(Time.get_ticks_usec() - t_brute) / 1000.0
	var t_idx: int = Time.get_ticks_usec()
	var idx_ids: PackedInt32Array = PackedInt32Array()
	idx_ids.resize(pts.size())
	for i3 in pts.size():
		idx_ids[i3] = int(_mr.call("gap_nld1_pick_at_world", pts[i3], true))
	var idx_ms: float = float(Time.get_ticks_usec() - t_idx) / 1000.0
	for i4 in pts.size():
		if brute_ids[i4] != idx_ids[i4]:
			mismatches += 1
			if first_bad.is_empty():
				first_bad = "i=%d p=%s brute=%d idx=%d" % [i4, str(pts[i4]), brute_ids[i4], idx_ids[i4]]
	_log("PROFILE brute_ms=%.2f index_ms=%.2f per_brute=%.4f per_index=%.4f" % [
		brute_ms, idx_ms, brute_ms / float(pts.size()), idx_ms / float(pts.size())
	])
	_log("PROFILE mapmanager_compare start")
	var t_mm: int = Time.get_ticks_usec()
	var mm_hits: int = 0
	if _mm.has_method("get_province_at_world_pos"):
		for p in pts:
			if int(_mm.call("get_province_at_world_pos", p, true)) > 0:
				mm_hits += 1
	var mm_ms: float = float(Time.get_ticks_usec() - t_mm) / 1000.0
	_log("PROFILE mapmanager_pick_ms=%.2f hits=%d" % [mm_ms, mm_hits])
	if mismatches != 0:
		_fail("identical-pick mismatches=%d / %d first=%s" % [mismatches, pts.size(), first_bad])
	else:
		_pass("identical-pick points=%d mismatches=0" % pts.size())
	var cap: float = brute_ms * REL_SLACK
	if idx_ms > cap:
		_fail("relative timing index=%.2fms brute=%.2fms cap=%.2fms (brute+10%%)" % [idx_ms, brute_ms, cap])
	else:
		_pass("relative timing index=%.2fms brute=%.2fms cap=%.2fms" % [idx_ms, brute_ms, cap])
