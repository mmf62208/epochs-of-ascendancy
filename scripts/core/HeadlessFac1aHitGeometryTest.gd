extends SceneTree

## FAC-1a FIX #8: L2 oval trim, halo/gap/margin do not own clicks, and a
## zero-gap still-click commits to event.position. Behaviour only.
## Must FAIL on main 61a80433 and PASS on the FIX #8 tip. NOT live Play.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFac1aHitGeometryTest.gd

const SRC_LAYER := "res://scripts/map/FacilityIconLayer.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const ZOOMS: Array[float] = [0.93, 0.97, 1.3, 2.25]
const STALE := 710368
const PAD_PX := 2.0

var _failures := 0
var _layer: Node2D = null
var _mr: Node = null
var _cam: Camera2D = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFac1aHitGeometryTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFac1aHitGeometryTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessFac1aHitGeometryTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFac1aHitGeometryTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _run() -> void:
	if not _boot():
		return
	_test_edges()
	_test_stale_commit_miss()
	_test_event_position_not_mouse()


func _boot() -> bool:
	var layer_script: Script = load(SRC_LAYER) as Script
	var ren_script: Script = load(SRC_REN) as Script
	if layer_script == null or ren_script == null:
		_fail("FacilityIconLayer or MapRenderer missing")
		return false
	_layer = layer_script.new() as Node2D
	_mr = ren_script.new() as Node
	if _layer == null or _mr == null:
		_fail("could not instantiate layer or renderer")
		return false
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	_layer.name = "FacilityIconLayer"
	container.add_child(_layer)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(260, 180)
	_cam.zoom = Vector2.ONE
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_layer.call("set_show_facilities", true)
	_layer.call("set_test_map_mode", "political")
	_layer.set("_test_board_n", 3520)
	_pass("layer + MapRenderer booted")
	return true


func _install_markers(zoom: float) -> void:
	var markers: Array[Dictionary] = [
		{
			"pid": 710434,
			"world": Vector2(8000, 8000),
			"cluster": true,
			"level": 2,
			"count": 2,
			"tex_key": "airfield_l2_intact",
		},
		{
			"pid": 710451,
			"world": Vector2(9200, 8000),
			"cluster": true,
			"level": 4,
			"count": 2,
			"tex_key": "airfield_l4_intact",
		},
		{
			"pid": 710430,
			"world": Vector2(8000, 9200),
			"cluster": false,
			"level": 1,
			"count": 1,
			"tex_key": "airfield_l1_intact",
		},
		{
			"pid": 710423,
			"world": Vector2(9200, 9200),
			"cluster": false,
			"level": 3,
			"count": 1,
			"tex_key": "airfield_l3_intact",
		},
	]
	_layer.call("set_test_zoom", zoom)
	_layer.set("_last_markers", markers)
	_layer.set("_markers_zoom", zoom)
	_layer.set("_markers_dirty", false)
	_mr.set("_march_preview_cache_dest", STALE)


func _pad(zoom: float) -> float:
	return float(_layer.call("_world_size_at", PAD_PX, zoom))


func _in_ellipse(r: Rect2, p: Vector2) -> bool:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return false
	var c := r.get_center()
	var rx := r.size.x * 0.5
	var ry := r.size.y * 0.5
	var dx := (p.x - c.x) / rx
	var dy := (p.y - c.y) / ry
	return dx * dx + dy * dy <= 1.002


func _hex_pid(world: Vector2) -> int:
	if _mr != null and _mr.has_method("_resolve_hex_pick_pid"):
		return int(_mr.call("_resolve_hex_pick_pid", world))
	return -1


func _outside_cardinals(art: Rect2, pad: float) -> Array[Vector2]:
	var c := art.get_center()
	var rx := art.size.x * 0.5
	var ry := art.size.y * 0.5
	return [
		c + Vector2(0.0, -(ry + pad)),
		c + Vector2(0.0, ry + pad),
		c + Vector2(rx + pad, 0.0),
		c + Vector2(-(rx + pad), 0.0),
	]


func _inside_cardinals(art: Rect2, pad: float) -> Array[Vector2]:
	var c := art.get_center()
	var rx := art.size.x * 0.5 - pad
	var ry := art.size.y * 0.5 - pad
	if rx <= 1.0 or ry <= 1.0:
		return [c]
	return [
		c,
		c + Vector2(0.0, -ry),
		c + Vector2(0.0, ry),
		c + Vector2(rx, 0.0),
		c + Vector2(-rx, 0.0),
	]


func _clear_of_chrome(p: Vector2, art: Rect2, badge: Rect2, tag: Rect2) -> bool:
	if _in_ellipse(art, p):
		return false
	if _in_ellipse(badge, p):
		return false
	if _in_ellipse(tag, p):
		return false
	return true


func _test_edges() -> void:
	var saw_l2 := false
	var saw_l4 := false
	for z in ZOOMS:
		_install_markers(z)
		var layouts: Array = _layer.call("get_hit_rects_at_zoom", z)
		if layouts.is_empty():
			_fail("no layouts at z=%.2f" % z)
			continue
		var pad := _pad(z)
		for lay_v in layouts:
			if typeof(lay_v) != TYPE_DICTIONARY:
				continue
			var lay: Dictionary = lay_v
			var want: int = int(lay.get("pid", -1))
			var art: Rect2 = lay.get("art_rect", Rect2()) as Rect2
			var icon: Rect2 = lay.get("icon_rect", Rect2()) as Rect2
			var badge: Rect2 = lay.get("badge_rect", Rect2()) as Rect2
			var tag: Rect2 = lay.get("tag_rect", Rect2()) as Rect2
			var is_round := bool(lay.get("round_art", false))
			var is_l2 := bool(lay.get("cluster", false)) and int(lay.get("level", 0)) == 2
			if is_l2:
				saw_l2 = true
			if is_round and bool(lay.get("cluster", false)):
				saw_l4 = true
			for p in _inside_cardinals(art, pad):
				var hit_in: int = int(_layer.call("hit_test_world", p))
				if hit_in != want:
					_fail("inside art z=%.2f pid=%d hit=%d round=%s" % [z, want, hit_in, str(is_round)])
				var click_in: int = int(_mr.call("_still_click_province_pid", p, true))
				if click_in != want:
					_fail("still_click inside z=%.2f pid=%d got=%d" % [z, want, click_in])
			var outs := _outside_cardinals(art, pad)
			var checked_out := 0
			for p2 in outs:
				if not _clear_of_chrome(p2, art, badge, tag):
					continue
				checked_out += 1
				var hit_out: int = int(_layer.call("hit_test_world", p2))
				if hit_out > 0:
					_fail("2px outside art still facility z=%.2f pid=%d hit=%d round=%s" % [z, want, hit_out, str(is_round)])
				var click_out: int = int(_mr.call("_still_click_province_pid", p2, true))
				var hex: int = _hex_pid(p2)
				if click_out == STALE or click_out != hex:
					_fail("still_click outside z=%.2f got=%d hex=%d stale=%d" % [z, click_out, hex, STALE])
			if checked_out < 4:
				_fail("z=%.2f pid=%d only %d clear outside cardinals" % [z, want, checked_out])
			## 1px outside the drawn art sits in HALO_PX when zoom >= 1.
			var halo_p := art.get_center() + Vector2(0.0, -(art.size.y * 0.5 + pad * 0.5))
			if _clear_of_chrome(halo_p, art, badge, tag):
				var halo_hit: int = int(_layer.call("hit_test_world", halo_p))
				if halo_hit > 0:
					_fail("halo owns click z=%.2f pid=%d hit=%d" % [z, want, halo_hit])
			if is_l2:
				## Top of the 34px square is inside the old circle and outside the oval.
				var over := Vector2(icon.get_center().x, icon.position.y + pad)
				if _clear_of_chrome(over, art, badge, tag):
					var over_hit: int = int(_layer.call("hit_test_world", over))
					if over_hit > 0:
						_fail("L2 circle overshoot z=%.2f hit=%d" % [z, over_hit])
					else:
						_pass("L2 oval rejects circle overshoot z=%.2f" % z)
				else:
					_fail("L2 overshoot sample landed on chrome z=%.2f" % z)
				var gap_p := Vector2(
					(badge.get_center().x + tag.get_center().x) * 0.5,
					art.get_center().y
				)
				if badge.size.x > 0.0 and tag.size.x > 0.0 and _clear_of_chrome(gap_p, art, badge, tag):
					var gap_hit: int = int(_layer.call("hit_test_world", gap_p))
					if gap_hit > 0:
						_fail("chrome gap owns click z=%.2f hit=%d" % [z, gap_hit])
		_pass("edge samples z=%.2f" % z)
	if not saw_l2:
		_fail("no L2 cluster across zooms")
	else:
		_pass("L2 cluster present")
	if not saw_l4:
		_fail("no L4 round cluster across zooms")
	else:
		_pass("L4 round cluster present")


func _test_stale_commit_miss() -> void:
	_install_markers(0.97)
	var nowhere := Vector2(-1.0e6, -1.0e6)
	_mr.set("_march_preview_cache_dest", STALE)
	var click: int = int(_mr.call("_still_click_province_pid", nowhere, true))
	var resolved: int = int(_mr.call("_mv1_re_resolve_commit_pid", nowhere, STALE, true))
	if click == STALE:
		_fail("still_click GIS miss kept stale %d" % STALE)
	else:
		_pass("still_click GIS miss does not keep stale")
	if resolved == STALE:
		_fail("re_resolve kept stale dest %d" % STALE)
	else:
		_pass("re_resolve does not keep stale dest")
	var y := Vector2(8000, 8000)
	var y_pid: int = int(_mr.call("_mv1_re_resolve_commit_pid", y, STALE, true))
	if y_pid != 710434:
		_fail("re_resolve on L2 centre want 710434 got %d" % y_pid)
	else:
		_pass("re_resolve on L2 centre is the icon, not stale")


func _test_event_position_not_mouse() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(640, 360)
	ev.global_position = Vector2(640, 360)
	var picked: Vector2 = _mr.call("_map_pick_world_from_event", ev) as Vector2
	var from_event: Vector2 = _mr.call("_screen_to_world", ev.position) as Vector2
	var mouse := Vector2.ZERO
	var vp := _mr.get_viewport()
	if vp != null:
		mouse = vp.get_mouse_position()
	var from_mouse: Vector2 = _mr.call("_screen_to_world", mouse) as Vector2
	if from_event.distance_to(from_mouse) < 1.0:
		_fail("event and mouse worlds are the same; mutant would not show")
		return
	if picked.distance_to(from_event) > 0.01:
		_fail("pick followed mouse/other world %s want event %s" % [str(picked), str(from_event)])
	else:
		_pass("pick uses event.position not mouse")
