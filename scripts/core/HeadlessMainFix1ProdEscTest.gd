extends SceneTree

## MAIN-FIX-1: Esc with Production open must close Prod only.
## Idle Esc (nothing open) still opens Command Center via TopInfoBar.
##
## Play MIXED on main d00dc8ed: Leaders / Agents / Space consumed Esc;
## ProductionAssignmentScreen only handled Esc in `_unhandled_input`, so
## MapRenderer `_input` opened Command Center on top of Prod.
##
## Does not load WorldMap / 3520 polygons.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessMainFix1ProdEscTest.gd
##
## Headless is NOT live Play.

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_PROD := "res://scripts/ui/ProductionAssignmentScreen.gd"
const SRC_BM := "res://scripts/combat/BattleManager.gd"
const SRC_PEACE := "res://scripts/ui/PeaceConferenceWindow.gd"
const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 8

var _failures: int = 0
var _mr: Node = null
var _ui: CanvasLayer = null
var _bar: Control = null
var _info: Panel = null
var _cam: Camera2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessMainFix1ProdEscTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessMainFix1ProdEscTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessMainFix1ProdEscTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessMainFix1ProdEscTest: ", msg)


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


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	_test_source_needles()
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	if not _setup_map_renderer():
		return
	if not await _boot_top_bar():
		return
	await _test_prod_esc_closes_without_command_center()
	await _test_idle_esc_opens_command_center()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	var prod := _read(SRC_PROD)
	var bm := _read(SRC_BM)
	var peace := _read(SRC_PEACE)
	if ren.is_empty() or prod.is_empty() or bm.is_empty():
		_fail("MapRenderer / ProductionAssignmentScreen / BattleManager source missing")
		return
	var esc := _slice_func(ren, "_handle_escape_key")
	if "ProductionAssignmentScreen" not in esc:
		_fail("_handle_escape_key must dismiss ProductionAssignmentScreen before CC")
		return
	var prod_idx := esc.find("ProductionAssignmentScreen")
	var cc_idx := esc.find("_esc_open_command_center")
	if prod_idx < 0 or cc_idx < 0 or prod_idx > cc_idx:
		_fail("Prod dismiss must run before _esc_open_command_center")
		return
	if "_esc_open_command_center" not in ren:
		_fail("idle Esc must still open Command Center")
		return
	if "func close_screen" not in prod:
		_fail("ProductionAssignmentScreen must expose close_screen for Esc")
		return
	if "ProductionAssignmentScreen_dying" not in prod:
		_fail("Prod close_screen must rename the dying node")
		return
	var overlays := _slice_func(ren, "_dismiss_map_overlays_esc")
	if "ProductionAssignmentScreen" not in overlays:
		_fail("_dismiss_map_overlays_esc must include ProductionAssignmentScreen")
		return
	var news := _slice_func(bm, "_post_battle_news")
	if "owner_now != attacker" not in news and "previous_owner == attacker" not in news:
		_fail("_post_battle_news must skip capture toast unless owner actually flipped")
		return
	if "previous_owner_tag" not in _slice_func(bm, "_apply_attacker_win_capture_light"):
		_fail("light capture must record previous_owner_tag")
		return
	if not peace.is_empty():
		var sheet := _slice_func(peace, "_open_campaign_peace_sheet")
		if "panel.size" not in sheet and "size = Vector2(480, 220)" not in sheet:
			_fail("campaign peace sheet must set an explicit panel size")
			return
		if "add_theme_stylebox_override" not in sheet:
			_fail("campaign peace sheet must paint an opaque StyleBox")
			return
	_pass("source needles: Prod Esc before CC + capture owner-flip + peace sheet size")


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
	var map_ui := CanvasLayer.new()
	map_ui.name = "UI"
	_mr.add_child(map_ui)
	_info = Panel.new()
	_info.name = "InfoPanel"
	_info.visible = false
	_info.size = Vector2(280, 200)
	map_ui.add_child(_info)
	_mr.set("info_panel", _info)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(400, 300)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	_pass("MapRenderer fixture ready")
	return true


func _boot_top_bar() -> bool:
	_ui = CanvasLayer.new()
	_ui.name = "UILayer"
	_ui.layer = 110
	root.add_child(_ui)
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		_fail("TopInfoBar.tscn missing")
		return false
	var inst: Node = packed.instantiate()
	if inst == null or not (inst is Control):
		_fail("TopInfoBar instantiate failed")
		return false
	_bar = inst as Control
	_bar.name = "TopInfoBar"
	if "player_country_tag" in _bar:
		_bar.set("player_country_tag", "GER")
	_ui.add_child(_bar)
	await _flush()
	_pass("TopInfoBar live for idle Esc → Command Center")
	return true


func _find_live_prod() -> Control:
	var names: Array[String] = ["ProductionAssignmentScreen"]
	for nm in names:
		var n: Node = root.get_node_or_null(nm)
		if _is_live_prod(n):
			return n as Control
		if _ui != null:
			n = _ui.get_node_or_null(nm)
			if _is_live_prod(n):
				return n as Control
	var found: Node = root.find_child("ProductionAssignmentScreen", true, false)
	if _is_live_prod(found):
		return found as Control
	return null


func _is_live_prod(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n.is_queued_for_deletion():
		return false
	if str(n.name).ends_with("_dying"):
		return false
	return n is Control


func _prod_is_open() -> bool:
	var screen: Control = _find_live_prod()
	if screen == null:
		return false
	if not screen.visible:
		return false
	return true


func _main_menu_up() -> bool:
	var mm: Node = root.get_node_or_null("MainMenu")
	if mm == null or not is_instance_valid(mm) or mm.is_queued_for_deletion():
		return false
	if str(mm.name) == "MainMenuLeftover":
		return false
	if mm is CanvasItem:
		return (mm as CanvasItem).visible
	if mm is CanvasLayer:
		return (mm as CanvasLayer).visible
	return true


func _open_prod() -> Control:
	var packed: PackedScene = load("res://scenes/ui/ProductionAssignmentScreen.tscn") as PackedScene
	if packed == null:
		_fail("ProductionAssignmentScreen.tscn missing")
		return null
	var inst: Node = packed.instantiate()
	if inst == null or not (inst is Control):
		_fail("ProductionAssignmentScreen instantiate failed")
		return null
	var screen := inst as Control
	screen.name = "ProductionAssignmentScreen"
	root.add_child(screen)
	return screen


func _test_prod_esc_closes_without_command_center() -> void:
	var existing: Node = root.get_node_or_null("MainMenu")
	if existing != null:
		existing.queue_free()
		await _flush()
	var screen: Control = _open_prod()
	if screen == null:
		return
	await _flush()
	if not _prod_is_open():
		_fail("production screen not open before Esc")
		return
	if _mr.has_method("_handle_escape_key"):
		_mr.call("_handle_escape_key")
	await _flush()
	var still_up := (
		is_instance_valid(screen)
		and not screen.is_queued_for_deletion()
		and str(screen.name) != "ProductionAssignmentScreen_dying"
		and screen.visible
	)
	if still_up:
		_fail("Esc with Prod open did not close ProductionAssignmentScreen")
		screen.queue_free()
		return
	if _main_menu_up():
		_fail("Esc with Prod open also opened Command Center")
		return
	_pass("Esc closed Prod without opening Command Center")


func _test_idle_esc_opens_command_center() -> void:
	var leftover: Control = _find_live_prod()
	if leftover != null:
		leftover.queue_free()
		await _flush()
	var existing: Node = root.get_node_or_null("MainMenu")
	if existing != null:
		existing.queue_free()
		await _flush()
	if _prod_is_open():
		_fail("Prod still open before idle Esc")
		return
	if _main_menu_up():
		_fail("Command Center already open before idle Esc")
		return
	# `_esc_stack_frame` is per process frame — wait so this Esc is a new press.
	await process_frame
	if _mr.has_method("_handle_escape_key"):
		_mr.call("_handle_escape_key")
	await _flush()
	if _prod_is_open():
		_fail("idle Esc opened Production")
		return
	if not _main_menu_up():
		_fail("Esc with nothing open did not open Command Center")
		return
	_pass("Esc with nothing open opened Command Center")


func _cleanup() -> void:
	var screen: Control = _find_live_prod()
	if screen != null:
		screen.queue_free()
	var mm: Node = root.get_node_or_null("MainMenu")
	if mm != null and is_instance_valid(mm):
		mm.queue_free()
	if _bar != null and is_instance_valid(_bar):
		_bar.queue_free()
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
