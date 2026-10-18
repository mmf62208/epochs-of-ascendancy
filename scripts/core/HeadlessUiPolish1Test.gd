extends SceneTree

## UI-POLISH-1: Agents Close in view, Space × first click, Trade signal guard.
##
## Does not load WorldMap / 3520 polygons.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessUiPolish1Test.gd
##
## Headless is NOT live Play.

const SRC_AGENTS := "res://scripts/ui/AgentAssignmentScreen.gd"
const SRC_SPACE := "res://scripts/ui/SpaceLayerBoardView.gd"
const SRC_TRADE := "res://scripts/ui/TradeMarketView.gd"
const PLAY_SIZE := Vector2i(1280, 800)
const VIEWPORT_RECT := Rect2(0.0, 0.0, 1280.0, 800.0)
const FLUSH_FRAMES := 8

var _failures: int = 0
var _event_seq: int = 0
var _ui: CanvasLayer = null
var _leftover: Node = null
var _agent_screen: Control = null
var _space_view: Window = null
var _trade_views: Array[Node] = []


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessUiPolish1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessUiPolish1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessUiPolish1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessUiPolish1Test: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


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
		if root is Window:
			(root as Window).gui_embed_subwindows = true
	_leftover = _LeftoverReleaseSwallow.new()
	_leftover.name = "UiPolish1LeftoverReleaseSwallow"
	root.add_child(_leftover)
	_ui = CanvasLayer.new()
	_ui.name = "UILayer"
	_ui.layer = 110
	root.add_child(_ui)
	await _flush()
	await _test_agents_close_inside_viewport()
	await _test_space_title_close_first_click()
	await _test_trade_open_twice_no_already_connected()
	_cleanup()


func _test_source_needles() -> void:
	var agents_src := _read(SRC_AGENTS)
	var space_src := _read(SRC_SPACE)
	var trade_src := _read(SRC_TRADE)
	if agents_src.is_empty() or space_src.is_empty() or trade_src.is_empty():
		_fail("Agents / Space / Trade source missing")
		return
	if "PANEL_DESIGN_SIZE" not in agents_src:
		_fail("AgentAssignmentScreen must clamp design size to the viewport")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in space_src or "TitleCloseButton" not in space_src:
		_fail("Space × must ACTION_MODE_BUTTON_PRESS TitleCloseButton")
		return
	var idx := 0
	var guarded := 0
	while true:
		var i := trade_src.find("deal_rejected.connect", idx)
		if i < 0:
			break
		var before := trade_src.substr(maxi(0, i - 160), 160)
		if "is_connected" not in before and "CONNECT_" not in before:
			_fail("TradeMarketView unguarded deal_rejected.connect at offset %d" % i)
			return
		guarded += 1
		idx = i + 1
	if guarded < 1:
		_fail("TradeMarketView must connect deal_rejected behind is_connected")
		return
	_pass("source needles: Agents clamp + Space press-on-down × + Trade deal_rejected guard")


func _test_agents_close_inside_viewport() -> void:
	var packed: PackedScene = load("res://scenes/ui/AgentAssignmentScreen.tscn") as PackedScene
	if packed == null:
		_fail("AgentAssignmentScreen.tscn missing")
		return
	var inst: Node = packed.instantiate()
	if inst == null or not (inst is Control):
		_fail("AgentAssignmentScreen instantiate failed")
		return
	_agent_screen = inst as Control
	_agent_screen.name = "AgentAssignmentScreen"
	if "country_tag" in _agent_screen:
		_agent_screen.set("country_tag", "GER")
	_ui.add_child(_agent_screen)
	await _flush()
	if _agent_screen.has_method("_center_on_viewport"):
		_agent_screen.call("_center_on_viewport")
	await _flush()
	var close_btn: Button = _agent_screen.get_node_or_null("TitleBar/CloseButton") as Button
	if close_btn == null:
		_fail("Agents CloseButton missing")
		return
	var r: Rect2 = close_btn.get_global_rect()
	if r.size.x < 4.0 or r.size.y < 4.0:
		_fail("Agents CloseButton rect too small %s" % str(r))
		return
	if not VIEWPORT_RECT.encloses(r):
		_fail("Agents CloseButton rect %s not inside 1280x800 viewport" % str(r))
		return
	var panel_r: Rect2 = _agent_screen.get_global_rect()
	if not VIEWPORT_RECT.encloses(panel_r):
		_fail("Agents screen rect %s not inside 1280x800 viewport" % str(panel_r))
		return
	_pass("Agents Close inside 1280x800 at %s (panel %s)" % [str(r), str(panel_r)])


func _title_close_button(win: Window) -> Button:
	if win == null:
		return null
	var n: Node = win.find_child("TitleCloseButton", true, false)
	if n is Button:
		return n as Button
	return null


func _space_click_point(btn: Control, win: Window) -> Vector2:
	var screen_origin: Vector2 = btn.get_screen_position() if btn.has_method("get_screen_position") else Vector2.ZERO
	if screen_origin.x > 1.0 or screen_origin.y > 1.0:
		return screen_origin + btn.size * 0.5
	var local_c: Vector2 = btn.get_global_rect().get_center()
	return Vector2(win.position) + local_c


func _test_space_title_close_first_click() -> void:
	var script: Resource = load("res://scripts/ui/SpaceLayerBoardView.gd")
	if script == null:
		_fail("SpaceLayerBoardView.gd missing")
		return
	var view: Object = script.new()
	if view == null or not (view is Window):
		_fail("SpaceLayerBoardView instantiate failed")
		return
	_space_view = view as Window
	_space_view.name = "SpaceLayerBoardView"
	root.add_child(_space_view)
	if _space_view.has_method("show_board"):
		_space_view.call("show_board", "GER")
	else:
		_space_view.popup_centered()
	await _flush()
	if not _space_view.visible:
		_fail("Space board not visible after show_board")
		return
	var x_btn: Button = _title_close_button(_space_view)
	if x_btn == null:
		_fail("Space TitleCloseButton (×) missing")
		return
	if x_btn.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("Space × action_mode=%s want BUTTON_PRESS" % str(x_btn.action_mode))
		return
	if x_btn.get_global_rect().size.x < 8.0:
		_fail("Space × rect too small %s" % str(x_btn.get_global_rect()))
		return
	var pt: Vector2 = _space_click_point(x_btn, _space_view)
	_click_at(pt, true)
	await _flush()
	if _space_view.visible:
		_fail("Space × did not close on the first click (leftover release swallowed)")
		return
	_pass("Space × closed on first click via parse_input_event (leftover swallow)")


func _count_deal_rejected_for(view: Object) -> int:
	if typeof(TradeManager) == TYPE_NIL:
		return 0
	var n := 0
	for c in TradeManager.deal_rejected.get_connections():
		var cb: Callable = c.get("callable", Callable())
		if cb.is_valid() and cb.get_object() == view:
			n += 1
	return n


func _test_trade_open_twice_no_already_connected() -> void:
	var packed: PackedScene = load("res://scenes/ui/TradeMarketView.tscn") as PackedScene
	if packed == null:
		_fail("TradeMarketView.tscn missing")
		return
	var first: Node = packed.instantiate()
	if first == null:
		_fail("TradeMarketView first instantiate failed")
		return
	first.name = "TradeMarketView"
	root.add_child(first)
	_trade_views.append(first)
	await _flush()
	var n1 := _count_deal_rejected_for(first)
	if n1 != 1:
		_fail("Trade first open deal_rejected connections=%d want 1" % n1)
		return
	first.hide()
	first.queue_free()
	await _flush()
	var second: Node = packed.instantiate()
	if second == null:
		_fail("TradeMarketView second instantiate failed")
		return
	second.name = "TradeMarketView"
	root.add_child(second)
	_trade_views.append(second)
	await _flush()
	var n2 := _count_deal_rejected_for(second)
	if n2 != 1:
		_fail("Trade second open deal_rejected connections=%d want 1" % n2)
		return
	_pass("Trade opened twice with deal_rejected connected once (no already-connected)")


func _make_mouse(screen_pt: Vector2, pressed: bool) -> InputEventMouseButton:
	_event_seq += 1
	var ev := InputEventMouseButton.new()
	ev.device = 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.canceled = false
	ev.double_click = false
	ev.position = screen_pt
	ev.global_position = screen_pt
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.set_meta("eoa_uipolish1_seq", _event_seq)
	return ev


func _warp_mouse(screen_pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)
	DisplayServer.warp_mouse(Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y))))


func _click_at(screen_pt: Vector2, swallow_release: bool) -> void:
	if _leftover != null and _leftover.has_method("arm"):
		if swallow_release:
			_leftover.call("arm")
		else:
			_leftover.call("disarm")
	_warp_mouse(screen_pt)
	var down: InputEventMouseButton = _make_mouse(screen_pt, true)
	Input.parse_input_event(down)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	var up: InputEventMouseButton = _make_mouse(screen_pt, false)
	Input.parse_input_event(up)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _cleanup() -> void:
	if _agent_screen != null and is_instance_valid(_agent_screen):
		_agent_screen.queue_free()
	if _space_view != null and is_instance_valid(_space_view):
		_space_view.queue_free()
	for v in _trade_views:
		if v != null and is_instance_valid(v):
			v.queue_free()
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	if _leftover != null and is_instance_valid(_leftover):
		_leftover.queue_free()


class _LeftoverReleaseSwallow extends Node:
	## Mimic MapRenderer leftover left-up swallow after Begin / pan skip-pick.
	var _armed: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process_input(true)

	func arm() -> void:
		_armed = true

	func disarm() -> void:
		_armed = false

	func _input(event: InputEvent) -> void:
		if not _armed:
			return
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			return
		_armed = false
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
