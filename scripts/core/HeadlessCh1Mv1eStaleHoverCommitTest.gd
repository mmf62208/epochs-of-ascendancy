extends SceneTree

## CH-1 / MV-1e: stale hover must not steal a non-icon still-click at 4x.
## Same-frame motion over province X, press+release over province Y (own land,
## no facility icon). Commit dest must be Y 15/15. Live pair was Bad Kreuznach
## vs Hildesheim; this fixture uses Köln (X) vs Leverkusen (Y).
## MV-1 / MV-1b gates stay unedited.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCh1Mv1eStaleHoverCommitTest.gd
##   tools/eoa_ch1_mv1e_stale_hover_guard.sh

const ADJ_PATH := "res://data/provinces_pilot_europe_nuts3/province_adjacency.json"
const BONN := 710416
const KOELN := 710417
const LEV := 710418
const GER_TAG := "GER"
const FID := "ch1_mv1e_ger"
const DESIGN := "infantry_1936"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const ITERS := 15
const WORLD_X := Vector2(100.0, 100.0)
const WORLD_Y := Vector2(420.0, 100.0)
const WORLD_HOME := Vector2(100.0, 380.0)

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _tm: Node = null
var _mr: Node = null
var _mv: Script = null
var _cam: Camera2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessCh1Mv1eStaleHoverCommitTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCh1Mv1eStaleHoverCommitTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCh1Mv1eStaleHoverCommitTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCh1Mv1eStaleHoverCommitTest: ", msg)


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
	_test_source_needles()
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	_tm = _autoload("TimeManager")
	_mv = load("res://scripts/formations/FormationMovement.gd") as Script
	if _lm == null or _mm == null:
		_fail("autoloads missing")
		return
	if _mv == null:
		_fail("FormationMovement.gd missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _setup_nuts3_fixture():
		return
	if not _setup_formation():
		return
	if not _setup_map_renderer():
		return
	await _test_stale_hover_commit_15x()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var dest_fn := _slice_func(ren, "_mv1_preview_dest_matches_world")
	if dest_fn.is_empty():
		_fail("_mv1_preview_dest_matches_world missing")
		return
	var fac_i := dest_fn.find("_facility_icon_pid_at")
	var hover_i := dest_fn.find("_hover_province")
	if fac_i < 0 or hover_i < 0 or fac_i > hover_i:
		_fail("dest_matches must keep facility before hover (FAC-1a)")
		return
	if "_resolve_hex_pick_pid" not in dest_fn:
		_fail("dest_matches must re-resolve GIS at the event world")
		return
	if "func _mv1_event_province_pid" not in ren:
		_fail("_mv1_event_province_pid helper missing")
		return
	if "func _mv1_re_resolve_commit_pid" not in ren:
		_fail("_mv1_re_resolve_commit_pid helper missing")
		return
	var un_fn := _slice_func(ren, "_unhandled_input")
	if "_map_pick_world_from_event(event)" not in un_fn:
		_fail("_unhandled_input must pick via _map_pick_world_from_event")
		return
	if "_mv1_re_resolve_commit_pid" not in un_fn:
		_fail("_unhandled_input cached-dest path must re-resolve event province")
		return
	_pass("MV-1e event-position re-resolve needles (MV-1/MV-1b unedited)")


func _setup_nuts3_fixture() -> bool:
	if not FileAccess.file_exists(ADJ_PATH):
		_fail("nuts3 adjacency missing")
		return false
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	if adj_sys.has_method("load_adjacency"):
		adj_sys.call("load_adjacency", ADJ_PATH)
	var rows: Array = [
		{"id": BONN, "tag": GER_TAG, "name": "Bonn", "c": WORLD_HOME},
		{"id": KOELN, "tag": GER_TAG, "name": "Köln", "c": WORLD_X},
		{"id": LEV, "tag": GER_TAG, "name": "Leverkusen", "c": WORLD_Y},
	]
	var provs: Dictionary = {}
	var countries: Dictionary = {GER_TAG: {"tag": GER_TAG, "name": "Germany"}}
	for row in rows:
		var pid := int(row["id"])
		var p: Object = _new_obj("res://scripts/data/Province.gd")
		if p == null:
			_fail("Province create failed")
			return false
		p.set("id", pid)
		p.set("owner_tag", GER_TAG)
		p.set("controller_tag", GER_TAG)
		p.set("terrain", "plains")
		p.set("name", str(row["name"]))
		p.set("is_sea", false)
		p.set("infrastructure", 4)
		p.set("development_level", 3)
		p.set("core_for", [GER_TAG])
		provs[pid] = p
		if adj_sys.has_method("register_province"):
			adj_sys.call("register_province", p)
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = mds.new(provs, {}, adj_sys, countries) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	if _mm.has_method("initialize_from_map_data"):
		_mm.call("initialize_from_map_data", map_data)
	else:
		_fail("initialize_from_map_data missing")
		return false
	if not _edge(BONN, KOELN) or not _edge(KOELN, LEV):
		_fail("fixture missing Bonn–Köln / Köln–Leverkusen")
		return false
	if "_centroids" in _mm:
		var cents: Dictionary = _mm.get("_centroids")
		cents[BONN] = WORLD_HOME
		cents[KOELN] = WORLD_X
		cents[LEV] = WORLD_Y
		_mm.set("_centroids", cents)
	_pass("nuts3 fixture Bonn/Köln/Leverkusen (X=Köln Y=Leverkusen)")
	return true


func _edge(a: int, b: int) -> bool:
	if _mm == null or not _mm.has_method("get_adjacent_provinces"):
		return false
	for n in _mm.call("get_adjacent_provinces", a, true):
		if int(n) == b:
			return true
	return false


func _fm(method: String, a: Variant = null, b: Variant = null, c: Variant = null) -> Variant:
	if _mv == null:
		return null
	var inst: Object = _mv.new() as Object
	if inst == null:
		return null
	if c != null:
		return inst.call(method, a, b, c)
	if b != null:
		return inst.call(method, a, b)
	if a != null:
		return inst.call(method, a)
	return inst.call(method)


func _setup_formation() -> bool:
	_fm("clear_march", FID)
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
	f.set("name", "GER CH-1 MV-1e Div")
	if "formations" in _lm:
		_lm.formations[FID] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)
	_pass("seeded lone GER formation at Bonn")
	return true


func _setup_map_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
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
	_cam.position = Vector2(260, 180)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	if "use_spatial_picking" in _mr:
		_mr.use_spatial_picking = true
	var placed: Dictionary = {BONN: WORLD_HOME, KOELN: WORLD_X, LEV: WORLD_Y}
	for pid_v in placed.keys():
		var pid := int(pid_v)
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
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = placed[pid] as Vector2
	_pass("MapRenderer + centroids X=Köln Y=Leverkusen")
	return true


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _world_to_screen(world: Vector2) -> Vector2:
	if _cam == null:
		return world
	return _cam.get_canvas_transform() * world


func _seed_stale_preview_x() -> void:
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	var x_p: Object = _mm.call("get_province", KOELN) if _mm.has_method("get_province") else null
	_mr.set("_hover_province", x_p)
	_mr.set("_march_preview_cache_dest", KOELN)
	_mr.set("_march_preview_cache_fid", FID)
	_mr.set("_march_preview_cache", {
		"ok": true,
		"hops": 2,
		"calendar_days": 3,
		"dest_id": KOELN,
		"path": [BONN, KOELN],
	})
	if _mr.has_method("_set_march_preview_chip_text"):
		_mr.call("_set_march_preview_chip_text", "2 hops · arrives in 3 days · Köln")


func _test_stale_hover_commit_15x() -> void:
	_seed_stale_preview_x()
	if bool(_mr.call("_mv1_preview_dest_matches_world", WORLD_X)) != true:
		_fail("dest_matches(X) must stay true for the preview dest")
		return
	if bool(_mr.call("_mv1_preview_dest_matches_world", WORLD_Y)):
		_fail("dest_matches(Y) must not trust stale hover/cache dest X")
		return
	var resolved_y: int = int(_mr.call("_mv1_re_resolve_commit_pid", WORLD_Y, KOELN, true))
	if resolved_y != LEV:
		_fail("re_resolve commit pid on Y with cache X want %d got %d" % [LEV, resolved_y])
		return
	_pass("dest_matches re-resolves event world; stale X does not match Y")
	if _tm != null and _tm.has_method("set_time_scale"):
		_tm.call("set_time_scale", 4.0)
	var fail := 0
	var i := 0
	while i < ITERS:
		_fm("clear_march", FID)
		var fo: Object = _formation()
		if fo != null:
			fo.set("stationed_province_id", BONN)
		_seed_stale_preview_x()
		var screen_x: Vector2 = _world_to_screen(WORLD_X)
		var screen_y: Vector2 = _world_to_screen(WORLD_Y)
		var mot := InputEventMouseMotion.new()
		mot.position = screen_x
		mot.global_position = screen_x
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = screen_y
		press.global_position = screen_y
		var rel := InputEventMouseButton.new()
		rel.button_index = MOUSE_BUTTON_LEFT
		rel.pressed = false
		rel.position = screen_y
		rel.global_position = screen_y
		## Same-frame: motion to X, press/release over Y (no facility icon).
		_mr.call("_input", mot)
		var world: Vector2 = _mr.call("_map_pick_world_from_event", rel) as Vector2
		var matches: bool = bool(_mr.call("_mv1_preview_dest_matches_world", world))
		var ready: bool = bool(_mr.call("_mv1_selected_own_land_ready_to_commit", world))
		var pid: int = int(_mr.call("_still_click_province_pid", world, ready))
		pid = int(_mr.call("_mv1_re_resolve_commit_pid", world, pid, ready))
		if matches and pid == KOELN:
			fail += 1
			_fail("iter %d dest_matches trusted stale hover X=%d (want Y=%d)" % [i, KOELN, LEV])
			i += 1
			continue
		if pid != LEV:
			fail += 1
			_fail("iter %d commit pid=%d want Y=%d matches=%s world=%s" % [i, pid, LEV, str(matches), str(world)])
			i += 1
			continue
		var dest_p: Object = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
		if dest_p == null or not bool(_mr.call("_try_move_selected_unit_to_province", dest_p)):
			fail += 1
			_fail("iter %d move to Y failed" % i)
			i += 1
			continue
		var order: Dictionary = _fm("get_march", FID)
		if int(order.get("dest_id", -1)) != LEV:
			fail += 1
			_fail("iter %d march dest=%s want Y=%d" % [i, str(order.get("dest_id")), LEV])
			i += 1
			continue
		i += 1
	if _tm != null and _tm.has_method("set_time_scale"):
		_tm.call("set_time_scale", 1.0)
	if fail != 0:
		_fail("MV-1e stale hover 4x: %d/%d failed (NOT live Play)" % [fail, ITERS])
		return
	_pass("MV-1e stale hover 4x: %d/%d commit Y=Leverkusen (lone unit, 0 fails, NOT live Play)" % [ITERS, ITERS])


func _cleanup() -> void:
	_fm("clear_march", FID)
	if _lm != null and "formations" in _lm and _lm.formations is Dictionary:
		_lm.formations.erase(FID)
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
