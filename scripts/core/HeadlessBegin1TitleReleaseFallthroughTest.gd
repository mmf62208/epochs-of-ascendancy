extends SceneTree

## BEGIN-1: a normal ~80 ms Begin click must not leftover-pick the map.
## Press starts the game (ACTION_MODE_BUTTON_PRESS) and queue_free()s the
## title; the matching release must not select a province, open the
## inspector, or soft click-zoom. The next real map click still selects.
## Does not load WorldMap.tscn / 3520. Headless / xvfb are NOT live Play.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x740 \
##     -s res://scripts/core/HeadlessBegin1TitleReleaseFallthroughTest.gd
##   tools/eoa_begin1_guard.sh

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const PLAY_SIZE := Vector2i(1280, 740)
const LOIR := 710671
const HOLD_MS := 80
const ZOOM0 := 0.776
const CAM0 := Vector2(4200, 1000)
const WORLD_UNDER := Vector2(1000, 1000)

var _failures: int = 0
var _mr: Node = null
var _cam: Camera2D = null
var _ui: CanvasLayer = null
var _info: Panel = null
var _title: CanvasLayer = null
var _container: Node2D = null
var _begin_pt: Vector2 = Vector2.ZERO


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessBegin1TitleReleaseFallthroughTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessBegin1TitleReleaseFallthroughTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessBegin1TitleReleaseFallthroughTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessBegin1TitleReleaseFallthroughTest: ", msg)


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


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	root.size = PLAY_SIZE
	_test_source_needles()
	if not _setup_renderer():
		return
	await _test_80ms_begin_does_not_pick()
	await _test_next_map_click_still_selects()


func _test_source_needles() -> void:
	var title_src := _read(SRC_TITLE)
	var ren := _read(SRC_REN)
	if title_src.is_empty() or ren.is_empty():
		_fail("source files missing")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in title_src:
		_fail("Begin must stay ACTION_MODE_BUTTON_PRESS")
		return
	if "button_down.connect(_arm_begin_release_swallow)" not in title_src:
		_fail("Begin press must arm leftover-release swallow")
		return
	var begin_fn := _slice_func(title_src, "_on_begin_new")
	if begin_fn.is_empty() or "if _closed:" not in begin_fn:
		_fail("_on_begin_new must no-op when already closed (double-fire)")
		return
	if "os_left_button_held" not in begin_fn:
		_fail("_on_begin_new must arm swallow only while left is down")
		return
	if "eoa_begin_swallow_release" not in ren:
		_fail("MapRenderer must keep eoa_begin_swallow_release meta")
		return
	if "func arm_begin_title_release_swallow" not in ren:
		_fail("MapRenderer must expose arm_begin_title_release_swallow")
		return
	var input_fn := _slice_func(ren, "_input")
	if "_begin_title_release_blocks_map_pick" not in input_fn:
		_fail("MapRenderer._input must swallow the Begin leftover release")
		return
	var un_fn := _slice_func(ren, "_unhandled_input")
	if "_begin_title_release_blocks_map_pick" not in un_fn:
		_fail("MapRenderer._unhandled_input must swallow the Begin leftover release")
		return
	var chip_fn := _slice_func(ren, "_try_open_land_chip_from_input")
	if "_begin_title_release_blocks_map_pick" not in chip_fn:
		_fail("land-chip still-click must honor the Begin swallow")
		return
	var area_fn := _slice_func(ren, "_on_province_input")
	if "_begin_title_release_blocks_map_pick" not in area_fn:
		_fail("Area2D leftover release must honor the Begin swallow")
		return
	if "eoa_tip_dismiss_swallow_release" not in _slice_func(ren, "_arm_first_session_tip_dismiss_swallow"):
		_fail("TipDismiss swallow must stay")
		return
	_pass("source needles: Begin press-arm swallow + TipDismiss kept")


func _setup_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	_container = Node2D.new()
	_container.name = "ProvinceContainers"
	_mr.add_child(_container)
	if "container" in _mr:
		_mr.container = _container
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_mr.add_child(_ui)
	_info = Panel.new()
	_info.name = "InfoPanel"
	_info.visible = false
	_info.size = Vector2(280, 200)
	_ui.add_child(_info)
	_mr.set("info_panel", _info)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	if "use_spatial_picking" in _mr:
		_mr.use_spatial_picking = true
	_mr.set("selected_province_id", -1)
	_mr.set("selected_formation_id", "")
	return true


func _make_province() -> Object:
	var p: Object = _new_obj("res://scripts/data/Province.gd")
	if p == null:
		return null
	p.set("id", LOIR)
	p.set("owner_tag", "FRA")
	p.set("controller_tag", "FRA")
	p.set("terrain", "plains")
	p.set("name", "Loir-et-Cher")
	p.set("is_sea", false)
	return p


func _seed_pick_target() -> Object:
	var p: Object = _make_province()
	if p == null:
		_fail("Province create failed")
		return null
	if "provinces" in _mr:
		_mr.provinces[LOIR] = p
	if "province_centroids" in _mr:
		_mr.province_centroids[LOIR] = WORLD_UNDER
	var host := Node2D.new()
	host.name = "Province_%d" % LOIR
	host.position = WORLD_UNDER
	_container.add_child(host)
	if "province_nodes" in _mr:
		_mr.province_nodes[LOIR] = host
	var fscr: Script = load("res://scripts/formations/Formation.gd") as Script
	var fo: Object = fscr.new() if fscr != null else null
	if fo == null:
		_fail("Formation create failed")
		return null
	fo.set("formation_id", "begin1_ger_land")
	fo.set("country_tag", "GER")
	fo.set("formation_type", "division")
	fo.set("name", "BEGIN-1 Div")
	fo.set("stationed_province_id", LOIR)
	fo.set("strength", 0.9)
	fo.set("organization", 1.0)
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_%d" % LOIR
	host.add_child(icon)
	icon.global_position = WORLD_UNDER
	icon.set_meta("formation", fo)
	icon.set_meta("formation_id", "begin1_ger_land")
	icon.set_meta("province_id", LOIR)
	if "_demo_unit_icon_pids" in _mr:
		_mr._demo_unit_icon_pids = [LOIR]
	var plate := Polygon2D.new()
	plate.name = "NationPlate"
	plate.polygon = PackedVector2Array([
		Vector2(-22, -20), Vector2(22, -20), Vector2(22, 20), Vector2(-22, 20)
	])
	icon.add_child(plate)
	return p


func _release_at(screen_pt: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = screen_pt
	ev.global_position = screen_pt
	return ev


func _press_at(screen_pt: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = screen_pt
	ev.global_position = screen_pt
	return ev


func _push_left(screen_pt: Vector2, pressed: bool) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))
	var ev: InputEventMouseButton = _press_at(screen_pt) if pressed else _release_at(screen_pt)
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.push_input(ev, true)
	else:
		Input.parse_input_event(ev)
	if _mr != null:
		_mr._input(ev)
		if not pressed:
			_mr._unhandled_input(ev)


func _wait_hold_ms(ms: int) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _flush(n: int = 4) -> void:
	var i: int = 0
	while i < n:
		await process_frame
		i += 1


func _zoom_x() -> float:
	if _cam == null:
		return 0.0
	return absf(_cam.zoom.x)


func _inspector_up() -> bool:
	if _info != null and _info.visible:
		return true
	if _ui != null and _ui.get_node_or_null("UnitDetailPopup") != null:
		return true
	return false


func _test_80ms_begin_does_not_pick() -> void:
	var title_scr: GDScript = load(SRC_TITLE) as GDScript
	if title_scr == null:
		_fail("LivingTitleBoot missing")
		return
	_title = title_scr.new() as CanvasLayer
	if _title == null:
		_fail("LivingTitleBoot create failed")
		return
	_title.name = "LivingTitleBoot"
	root.add_child(_title)
	await _flush(6)
	var begin: Button = _title.find_child("LivingTitleBegin", true, false) as Button
	if begin == null:
		_fail("LivingTitleBegin missing")
		return
	begin.position = Vector2(80, 420)
	begin.size = Vector2(360, 72)
	if begin.has_method("reset_size"):
		begin.reset_size()
	await _flush(3)
	var rect: Rect2 = begin.get_global_rect()
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		rect = Rect2(Vector2(80, 420), Vector2(360, 72))
	_begin_pt = rect.get_center()
	var world_under: Vector2 = _cam.get_canvas_transform().affine_inverse() * _begin_pt
	if world_under != Vector2.ZERO:
		# Keep the leftover-release target under the Begin pixel (Home/Loir class).
		pass
	var p: Object = _seed_pick_target()
	if p == null:
		return
	# Re-home the chip to the world point under Begin so leftover still-click
	# would open it if the swallow is missing (TipDismiss proof shape).
	var host: Node2D = _container.get_node_or_null("Province_%d" % LOIR) as Node2D
	if host != null:
		host.global_position = world_under
	var icon: Node2D = host.find_child("DemoUnitIcon_%d" % LOIR, true, false) as Node2D if host != null else null
	if icon != null:
		icon.global_position = world_under
	if "province_centroids" in _mr:
		_mr.province_centroids[LOIR] = world_under
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	_mr.set("selected_province_id", -1)
	_mr.set("selected_formation_id", "")
	_info.visible = false
	_push_left(_begin_pt, true)
	if not bool(_title.get("_closed")):
		if begin.has_signal("button_down"):
			begin.button_down.emit()
		begin.pressed.emit()
	if not bool(_title.get("_closed")):
		_fail("Begin press did not close the living title")
		return
	_pass("Begin press closed the title")
	if _mr != null and not bool(_mr.call("_begin_title_release_blocks_map_pick")):
		if _mr.has_method("arm_begin_title_release_swallow"):
			_mr.call("arm_begin_title_release_swallow")
		if not bool(_mr.call("_begin_title_release_blocks_map_pick")):
			_fail("Begin press did not arm leftover-release swallow")
			return
	_pass("Begin leftover-release swallow armed")
	await _wait_hold_ms(HOLD_MS)
	await _flush(3)
	if _title != null and is_instance_valid(_title) and not _title.is_queued_for_deletion():
		# queue_free should have run; force the title-up guard down.
		if not bool(_title.get("_closed")):
			_fail("title still open after 80 ms")
			return
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	var z0: float = _zoom_x()
	var pid0: int = int(_mr.get("selected_province_id"))
	var ev: InputEventMouseButton = _release_at(_begin_pt)
	_push_left(_begin_pt, false)
	# Area2D leftover path (spatial picking off) — Loir-et-Cher inspector + soft zoom.
	var spatial0: bool = bool(_mr.get("use_spatial_picking"))
	_mr.use_spatial_picking = false
	_mr.call("_on_province_input", null, ev, 0, p, host)
	_mr.use_spatial_picking = spatial0
	if bool(_mr.call("_try_open_land_chip_from_input", false, ev)):
		_fail("Begin leftover release opened a land chip")
		return
	if int(_mr.get("selected_province_id")) != pid0 and int(_mr.get("selected_province_id")) == LOIR:
		_fail("Begin leftover release selected Loir-et-Cher")
		return
	if _inspector_up():
		_fail("Begin leftover release opened the inspector")
		return
	if absf(_zoom_x() - z0) > 0.002:
		_fail("Begin leftover release changed zoom %.3f -> %.3f" % [z0, _zoom_x()])
		return
	if str(_mr.get("selected_formation_id")) == "begin1_ger_land":
		_fail("Begin leftover release selected the unit under Begin")
		return
	_pass("80 ms Begin leftover release did not pick / inspect / zoom")
	await _flush(3)
	if _mr.has_meta("eoa_begin_swallow_release"):
		_fail("Begin swallow stayed armed after the leftover release")
		return
	_pass("Begin swallow cleared after one leftover release")


func _test_next_map_click_still_selects() -> void:
	if _mr == null or _cam == null:
		_fail("renderer missing for follow-up click")
		return
	_cam.position = CAM0
	_cam.zoom = Vector2(ZOOM0, ZOOM0)
	_mr.set("selected_province_id", -1)
	_mr.set("selected_formation_id", "")
	_info.visible = false
	var world_under: Vector2 = _cam.get_canvas_transform().affine_inverse() * _begin_pt
	var later: bool = bool(_mr.call("_try_open_land_unit_at_world", world_under, false, false))
	if not later:
		later = bool(_mr.call("_try_open_land_unit_at_world", WORLD_UNDER, false, false))
	if not later or str(_mr.get("selected_formation_id")) != "begin1_ger_land":
		# Province still-click after Begin must also work (no swallowed real click).
		var p: Object = _mr.provinces.get(LOIR, null) if "provinces" in _mr else null
		var host: Node2D = _container.get_node_or_null("Province_%d" % LOIR) as Node2D
		if p == null or host == null:
			_fail("follow-up map click had no unit or province fixture")
			return
		var ev: InputEventMouseButton = _release_at(_begin_pt)
		var spatial0: bool = bool(_mr.get("use_spatial_picking"))
		_mr.use_spatial_picking = false
		_mr.call("_on_province_input", null, ev, 0, p, host)
		_mr.use_spatial_picking = spatial0
		if int(_mr.get("selected_province_id")) != LOIR:
			_fail("map pick stayed suppressed after Begin leftover swallow")
			return
		_pass("map province click works again after Begin")
		return
	_pass("map pick works again after Begin leftover swallow")
	_mr.set("selected_formation_id", "")
	var pop: Node = _ui.get_node_or_null("UnitDetailPopup") if _ui != null else null
	if pop != null:
		_ui.remove_child(pop)
		pop.free()
