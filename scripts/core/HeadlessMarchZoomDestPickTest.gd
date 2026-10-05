extends SceneTree

## March dest pick at z 0.32 / 0.80 / 1.5.
## Fresh GIS-interior screen → expected dest id via MapRenderer._screen_to_world
## + _mv1_event_province_pid (same path as march commit).
## Also logs stale-screen-from-other-zoom dests (live-smoke harness hypothesis).
## Does not edit MapRenderer pick / chip / spill / title / Fill%.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessMarchZoomDestPickTest.gd
##   tools/eoa_march_zoom_pick_guard.sh

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const ADJ_PATH := "res://data/provinces_world_accurate/province_adjacency.json"
const PROV_SCRIPT := "res://scripts/data/Province.gd"
const MAP_DATA_SCRIPT := "res://scripts/data/MapScenarioData.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const HEIDE := 710380
const BORDE := 710515
const HARZ := 710517
const KOELN := 710417
const BONN := 710416
const GER_TAG := "GER"
const FID := "march_zoom_ger_garrison"
const DESIGN := "infantry_1936"
const VIEW_W := 1280
const VIEW_H := 740
const ZOOMS: Array[float] = [0.32, 0.80, 1.50]
const FLUSH_FRAMES := 4
const REPO_DIR := "docs/evidence/march_zoom_pick"

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _mv: Script = null
var _cam: Camera2D = null
var _rows: PackedStringArray = PackedStringArray()
var _stale_rows: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessMarchZoomDestPickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessMarchZoomDestPickTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessMarchZoomDestPickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessMarchZoomDestPickTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt_a := src.find("\nfunc ", i + needle.length())
	var nxt_b := src.find("\nstatic func ", i + needle.length())
	var nxt := -1
	if nxt_a >= 0 and nxt_b >= 0:
		nxt = mini(nxt_a, nxt_b)
	elif nxt_a >= 0:
		nxt = nxt_a
	else:
		nxt = nxt_b
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _run() -> void:
	_force_viewport()
	_test_source_needles()
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	_mv = load("res://scripts/formations/FormationMovement.gd") as Script
	if _mm == null:
		_fail("MapManager missing")
		return
	if _mv == null:
		_fail("FormationMovement.gd missing")
		return
	if _lm != null and _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _load_accurate_board():
		return
	if not _setup_map_renderer():
		return
	if not _setup_formation():
		return
	await _flush()
	if not _assert_adjacency_gap():
		return
	if not _assert_gis_interiors():
		return
	await _test_fresh_interior_picks()
	await _test_stale_screen_hypothesis()
	_write_evidence()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var screen_fn := _slice_func(ren, "_map_pick_screen_pos")
	if "event as InputEventMouse" not in screen_fn and "event.position" not in screen_fn:
		_fail("_map_pick_screen_pos must use event.position")
		return
	var stw := _slice_func(ren, "_screen_to_world")
	if "get_canvas_transform" not in stw or "affine_inverse" not in stw:
		_fail("_screen_to_world must invert the camera canvas transform")
		return
	var ev_fn := _slice_func(ren, "_mv1_event_province_pid")
	if "_resolve_hex_pick_pid" not in ev_fn:
		_fail("_mv1_event_province_pid must re-resolve GIS")
		return
	var re_fn := _slice_func(ren, "_mv1_re_resolve_commit_pid")
	if "_resolve_hex_pick_pid" not in re_fn:
		_fail("_mv1_re_resolve_commit_pid must override stale cache dest")
		return
	_pass("needles: event.position + canvas inverse + GIS re-resolve")


func _load_accurate_board() -> bool:
	var base := _load_json(BASE_PATH)
	var geo := _load_json(GEO_PATH)
	var own_doc := _load_json(OWN_PATH)
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
		var pid := int(row.get("id", 0))
		if pid <= 0:
			continue
		var p: Object = ProvScript.new()
		p.set("id", pid)
		p.set("name", str(row.get("name", "Province %d" % pid)))
		p.set("terrain", str(row.get("terrain", "plains")))
		p.set("domain", str(row.get("domain", "land")))
		var terr_l := str(p.get("terrain")).strip_edges().to_lower()
		var dom_l := str(p.get("domain")).strip_edges().to_lower()
		p.set("is_sea", terr_l in ["sea", "ocean", "water", "lake"] or dom_l in ["sea", "ocean", "naval"])
		var ot := str(owners.get(str(pid), "")).strip_edges().to_upper()
		if not ot.is_empty():
			p.set("owner_tag", ot)
			p.set("controller_tag", ot)
		provs[pid] = p
	var geometry: Dictionary = {}
	for row_v2 in geo.get("provinces", []):
		if typeof(row_v2) != TYPE_DICTIONARY:
			continue
		var row2: Dictionary = row_v2
		var pid2 := int(row2.get("id", 0))
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
		_mm.call("set_geometry_world_native", false)
	if _mm.has_method("set_geometry_world_space"):
		_mm.call("set_geometry_world_space", false)
	if _mm.has_method("rebuild_pick_grid"):
		_mm.call("rebuild_pick_grid")
	var n_prov := int(_mm.call("get_province_count")) if _mm.has_method("get_province_count") else 0
	if n_prov < 3000:
		_fail("too_few_provinces=%d" % n_prov)
		return false
	_pass("loaded_provinces=%d" % n_prov)
	return true


func _setup_map_renderer() -> bool:
	var mr_script: Script = load(SRC_REN) as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.enabled = true
	_cam.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	if "use_spatial_picking" in _mr:
		_mr.use_spatial_picking = true
	for pid in [HEIDE, KOELN, BONN, HARZ, BORDE]:
		var gp: Variant = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
		if gp == null:
			_fail("MapManager missing province %d" % pid)
			return false
		if "provinces" in _mr:
			_mr.provinces[pid] = gp
		var node := Node2D.new()
		node.name = "Province_%d" % pid
		container.add_child(node)
		if "province_nodes" in _mr:
			_mr.province_nodes[pid] = node
		var c: Vector2 = _centroid(pid)
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = c
	_pass("MapRenderer + camera 1280x740")
	return true


func _setup_formation() -> bool:
	if _mv != null:
		var inst: Object = _mv.new()
		if inst != null and inst.has_method("clear_march"):
			inst.call("clear_march", FID)
	if _lm == null:
		_fail("LeaderManager missing")
		return false
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("Formation create failed")
		return false
	f.set("formation_id", FID)
	f.set("country_tag", GER_TAG)
	f.set("formation_type", "division")
	f.set("design_id", DESIGN)
	f.set("stationed_province_id", BONN)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set("name", "GER Garrison 4")
	if "formations" in _lm:
		_lm.formations[FID] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	_pass("seeded GER Garrison 4 at Bonn")
	return true


func _assert_adjacency_gap() -> bool:
	var neigh: Array = []
	if _mm.has_method("get_adjacent_provinces"):
		neigh = _mm.call("get_adjacent_provinces", HEIDE, true)
	var ids: Array[int] = []
	for n in neigh:
		ids.append(int(n))
	if HARZ in ids or BORDE in ids:
		_fail("Heidekreis unexpectedly adjacent to Harz/Börde — geometry changed")
		return false
	var d_harz := _centroid(HEIDE).distance_to(_centroid(HARZ))
	var d_borde := _centroid(HEIDE).distance_to(_centroid(BORDE))
	print(
		"  [INFO] Heidekreis neighbors=%s d_Harz=%.1f d_Börde=%.1f (not adjacent)"
		% [str(ids), d_harz, d_borde]
	)
	if d_harz < 20.0 or d_borde < 20.0:
		_fail("Harz/Börde unexpectedly close to Heidekreis")
		return false
	_pass("Harz/Börde are not Heidekreis neighbors (large miss ≠ 1-hex offset)")
	return true


func _assert_gis_interiors() -> bool:
	for pid in [HEIDE, KOELN]:
		var world: Vector2 = _interior(pid)
		var hit := _gis(world)
		if hit != pid:
			_fail("GIS interior pid=%d hit=%d %s at %s" % [pid, hit, _pname(hit), str(world)])
			return false
		print("  [INFO] GIS interior %s %d world=%.3f,%.3f" % [_pname(pid), pid, world.x, world.y])
	_pass("GIS interiors Heidekreis + Köln")
	return true


func _test_fresh_interior_picks() -> void:
	for pid in [HEIDE, KOELN]:
		var world: Vector2 = _interior(pid)
		for z in ZOOMS:
			_set_cam(world, z)
			await _flush()
			var screen: Vector2 = _world_to_screen(world)
			var back: Vector2 = _mr.call("_screen_to_world", screen) as Vector2
			var dest: int = int(_mr.call("_mv1_event_province_pid", back))
			var mm_screen: int = -1
			if _mm.has_method("get_province_at_screen_pos"):
				mm_screen = int(_mm.call("get_province_at_screen_pos", screen, true))
			var row := (
				"| fresh | z=%.2f | %s %d | screen=%.1f,%.1f | world=%.2f,%.2f | dest=%d %s | mm_screen=%d |"
				% [z, _pname(pid), pid, screen.x, screen.y, back.x, back.y, dest, _pname(dest), mm_screen]
			)
			_rows.append(row)
			print("  [INFO] HeadlessMarchZoomDestPickTest: %s" % row)
			if dest != pid:
				_fail("fresh z=%.2f %s want dest=%d got %d %s" % [z, _pname(pid), pid, dest, _pname(dest)])
				continue
			if mm_screen > 0 and mm_screen != pid:
				_fail("fresh z=%.2f get_province_at_screen_pos want %d got %d" % [z, pid, mm_screen])
				continue
			if not _screen_in_view(screen):
				_fail("fresh z=%.2f %s screen off-viewport %s" % [z, _pname(pid), str(screen)])
				continue
			_pass("fresh z=%.2f %s dest=%d screen=%.1f,%.1f" % [z, _pname(pid), dest, screen.x, screen.y])


func _test_stale_screen_hypothesis() -> void:
	# Europe-Home-ish camera south of Heidekreis (Köln). Reuse the z=1.50
	# interior screen at lower zooms — the live-smoke miss class.
	var heide_w: Vector2 = _interior(HEIDE)
	var home_w: Vector2 = _centroid(KOELN)
	_set_cam(home_w, 1.50)
	await _flush()
	var stale_screen: Vector2 = _world_to_screen(heide_w)
	var fresh_15: int = _pick_screen(stale_screen)
	var s15 := (
		"| stale_src | z=1.50 cam=Köln | Heidekreis screen=%.1f,%.1f | dest=%d %s |"
		% [stale_screen.x, stale_screen.y, fresh_15, _pname(fresh_15)]
	)
	_stale_rows.append(s15)
	print("  [INFO] HeadlessMarchZoomDestPickTest: %s" % s15)
	for z in [0.80, 0.32]:
		_set_cam(home_w, z)
		await _flush()
		var stale_dest: int = _pick_screen(stale_screen)
		var fresh_screen: Vector2 = _world_to_screen(heide_w)
		var fresh_dest: int = _pick_screen(fresh_screen)
		var row := (
			"| stale_reuse | z=%.2f cam=Köln | stale_screen=%.1f,%.1f dest=%d %s | fresh_screen=%.1f,%.1f dest=%d %s |"
			% [
				z, stale_screen.x, stale_screen.y, stale_dest, _pname(stale_dest),
				fresh_screen.x, fresh_screen.y, fresh_dest, _pname(fresh_dest),
			]
		)
		_stale_rows.append(row)
		print("  [INFO] HeadlessMarchZoomDestPickTest: %s" % row)
		if fresh_dest != HEIDE:
			_fail("stale-experiment fresh recompute z=%.2f want Heidekreis got %d %s" % [z, fresh_dest, _pname(fresh_dest)])
		if stale_dest == HEIDE:
			print("  [INFO] stale z=1.50 screen @ z=%.2f still Heidekreis" % z)
		else:
			print(
				"  [INFO] STALE_HARNESS z=1.50 screen @ z=%.2f dest=%d %s (Harz=%d Börde=%d)"
				% [z, stale_dest, _pname(stale_dest), HARZ, BORDE]
			)
	# Home-fit screen reused at mid zoom: world slides toward the camera
	# (south of Heidekreis → Harz / Börde class).
	_set_cam(home_w, 0.32)
	await _flush()
	var home_screen: Vector2 = _world_to_screen(heide_w)
	var home_fresh: int = _pick_screen(home_screen)
	_stale_rows.append(
		"| stale_src | z=0.32 cam=Köln | Heidekreis screen=%.1f,%.1f | dest=%d %s |"
		% [home_screen.x, home_screen.y, home_fresh, _pname(home_fresh)]
	)
	for z2 in [0.80, 1.50]:
		_set_cam(home_w, z2)
		await _flush()
		var stale2: int = _pick_screen(home_screen)
		var fresh2_screen: Vector2 = _world_to_screen(heide_w)
		var fresh2: int = _pick_screen(fresh2_screen)
		_stale_rows.append(
			"| stale_reuse | z=0.32 screen @ z=%.2f | stale_dest=%d %s | fresh_dest=%d %s |"
			% [z2, stale2, _pname(stale2), fresh2, _pname(fresh2)]
		)
		print(
			"  [INFO] STALE_HARNESS z=0.32 screen @ z=%.2f dest=%d %s fresh=%d %s (Harz=%d Börde=%d)"
			% [z2, stale2, _pname(stale2), fresh2, _pname(fresh2), HARZ, BORDE]
		)
		if fresh2 != HEIDE:
			_fail("stale-experiment fresh recompute z=%.2f want Heidekreis got %d %s" % [z2, fresh2, _pname(fresh2)])


func _pick_screen(screen: Vector2) -> int:
	var world: Vector2 = _mr.call("_screen_to_world", screen) as Vector2
	return int(_mr.call("_mv1_event_province_pid", world))


func _set_cam(world: Vector2, z: float) -> void:
	if _cam == null:
		return
	_cam.global_position = world
	_cam.zoom = Vector2(z, z)
	_cam.make_current()


func _world_to_screen(world: Vector2) -> Vector2:
	if _cam == null:
		return world
	return _cam.get_canvas_transform() * world


func _screen_in_view(screen: Vector2) -> bool:
	return screen.x >= 0.0 and screen.y >= 0.0 and screen.x <= float(VIEW_W) and screen.y <= float(VIEW_H)


func _centroid(pid: int) -> Vector2:
	if _mm != null and _mm.has_method("get_province_centroid"):
		return _mm.call("get_province_centroid", pid) as Vector2
	return Vector2.ZERO


func _interior(pid: int) -> Vector2:
	var c: Vector2 = _centroid(pid)
	if _gis(c) == pid:
		return c
	var pts := _poly(pid)
	if pts.size() >= 3:
		var acc := Vector2.ZERO
		for p in pts:
			acc += p
		var mean: Vector2 = acc / float(pts.size())
		if _gis(mean) == pid:
			return mean
		for p2 in pts:
			var mid: Vector2 = (c + p2) * 0.5
			if _gis(mid) == pid:
				return mid
	return c


func _poly(pid: int) -> PackedVector2Array:
	if _mm == null or not _mm.has_method("get_province_geometry"):
		return PackedVector2Array()
	var geo: Dictionary = _mm.call("get_province_geometry", pid)
	var raw: Variant = geo.get("points", PackedVector2Array())
	var pts := PackedVector2Array()
	if raw is PackedVector2Array:
		pts = raw
	elif raw is Array:
		for pt in raw as Array:
			if pt is Vector2:
				pts.append(pt)
			elif pt is Array and (pt as Array).size() >= 2:
				var arr: Array = pt
				pts.append(Vector2(float(arr[0]), float(arr[1])))
	if pts.size() >= 3:
		return MapCanvasConfig.transform_province_points(pts, false, true, false)
	return pts


func _gis(world: Vector2) -> int:
	if _mm == null or not _mm.has_method("get_province_at_world_pos"):
		return -1
	var hit := int(_mm.call("get_province_at_world_pos", world, true))
	if _mm.has_method("resolve_pick_province_id"):
		hit = int(_mm.call("resolve_pick_province_id", hit))
	return hit


func _pname(pid: int) -> String:
	if pid <= 0 or _mm == null or not _mm.has_method("get_province"):
		return "?"
	var p: Variant = _mm.call("get_province", pid)
	if p == null:
		return str(pid)
	return str(p.get("name"))


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _write_evidence() -> void:
	var md := "# March zoom dest pick (headless)\n\n"
	md += "NOT live Play. Fresh GIS-interior screen → dest at z 0.32 / 0.80 / 1.50.\n"
	md += "Harz `710517` / Börde `710515` are **not** adjacent to Heidekreis `710380`.\n\n"
	md += "## Fresh picks\n\n"
	md += "| kind | zoom | target | screen | world | dest | mm_screen |\n"
	md += "|---|---|---|---|---|---|---|\n"
	for row in _rows:
		md += "%s\n" % row
	md += "\n## Stale-screen hypothesis (Köln camera, reuse z=1.50 Heidekreis screen)\n\n"
	for row2 in _stale_rows:
		md += "%s\n" % row2
	DirAccess.make_dir_recursive_absolute(REPO_DIR)
	var ev := FileAccess.open("%s/HEADLESS.md" % REPO_DIR, FileAccess.WRITE)
	if ev != null:
		ev.store_string(md)
		ev.close()


func _force_viewport() -> void:
	var want := Vector2i(VIEW_W, VIEW_H)
	if root is Window:
		var w: Window = root as Window
		w.size = want
		w.min_size = want
		w.content_scale_size = want
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var vp := root.get_viewport() if root != null else null
	if vp != null:
		vp.size = want


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	return data if data is Dictionary else {}


func _cleanup() -> void:
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
