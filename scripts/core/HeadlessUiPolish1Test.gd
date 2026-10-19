extends SceneTree

## UI-POLISH-1: Agents Close in view, Space × first click, Trade signal guard,
## held Close swallow, Space Esc.
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
const SRC_PROD := "res://scripts/ui/ProductionAssignmentScreen.gd"
const SRC_LEAD := "res://scripts/ui/LeaderAssignmentScreen.gd"
const SRC_SWALLOW := "res://scripts/ui/CloseReleaseSwallow.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const PLAY_SIZE := Vector2i(1280, 800)
const VIEWPORT_RECT := Rect2(0.0, 0.0, 1280.0, 800.0)
const FLUSH_FRAMES := 8
const HELD_CLOSE_SEC := 0.075

var _failures: int = 0
var _event_seq: int = 0
var _ui: CanvasLayer = null
var _leftover: Node = null
var _agent_screen: Control = null
var _space_view: Window = null
var _trade_views: Array[Node] = []
var _probe_fired: int = 0
var _map_probe: Node = null
var _map_catcher: Node = null
var _cc_probe: Node = null


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
	_map_catcher = _MapReleaseCatcher.new()
	_map_catcher.name = "UiPolish1MapReleaseCatcher"
	root.add_child(_map_catcher)
	_cc_probe = _CcPathProbe.new()
	_cc_probe.name = "UiPolish1CcPathProbe"
	root.add_child(_cc_probe)
	await _flush()
	await _test_empty_map_click_counts_one_release()
	await _test_agents_close_inside_viewport()
	await _test_agents_title_vs_show_no_overlap()
	await _test_agents_close_held_not_covered()
	await _test_prod_close_held_no_map_up()
	await _test_mutant_prod_held_close_without_swallow()
	await _test_leaders_close_held_no_map_up()
	await _test_space_title_close_first_click()
	await _test_space_frame_x_then_unrelated_button()
	await _test_space_keyboard_close_then_click()
	await _test_space_close_then_map_select()
	await _test_space_esc_closes()
	await _test_idle_esc_reaches_command_center_path()
	await _test_trade_open_twice_no_already_connected()
	_cleanup()


func _test_source_needles() -> void:
	var agents_src := _read(SRC_AGENTS)
	var space_src := _read(SRC_SPACE)
	var trade_src := _read(SRC_TRADE)
	var prod_src := _read(SRC_PROD)
	var lead_src := _read(SRC_LEAD)
	var swallow_src := _read(SRC_SWALLOW)
	var ren_src := _read(SRC_REN)
	if agents_src.is_empty() or space_src.is_empty() or trade_src.is_empty():
		_fail("Agents / Space / Trade source missing")
		return
	if swallow_src.is_empty():
		_fail("CloseReleaseSwallow.gd missing")
		return
	if "PANEL_DESIGN_SIZE" not in agents_src:
		_fail("AgentAssignmentScreen must clamp design size to the viewport")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in space_src or "TitleCloseButton" not in space_src:
		_fail("Space × must ACTION_MODE_BUTTON_PRESS TitleCloseButton")
		return
	if "is_mouse_button_pressed(MOUSE_BUTTON_LEFT)" not in swallow_src:
		_fail("shared swallow must arm only while LMB is down")
		return
	if "250" not in swallow_src:
		_fail("shared swallow must expire after ~250 ms")
		return
	if "mb.pressed" not in swallow_src or "_disarm()" not in swallow_src:
		_fail("shared swallow must clear on a new left press")
		return
	if "arm_from" not in prod_src or "CloseReleaseSwallow" not in prod_src:
		_fail("Prod Close must use shared CloseReleaseSwallow")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in lead_src or "CloseReleaseSwallow" not in lead_src:
		_fail("Leaders Close must ACTION_MODE_BUTTON_PRESS with CloseReleaseSwallow")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in agents_src or "CloseReleaseSwallow" not in agents_src:
		_fail("Agents Close must ACTION_MODE_BUTTON_PRESS with CloseReleaseSwallow")
		return
	if "CloseReleaseSwallow" not in space_src or "_SpaceTitleCloseReleaseSwallow" in space_src:
		_fail("Space must use shared CloseReleaseSwallow (not the private class)")
		return
	if "_is_live_escape_event" not in space_src:
		_fail("Space must handle live Esc (keycode / physical / key_label / ui_cancel)")
		return
	if "_dismiss_space_layer_board_esc" not in ren_src or "SpaceLayerBoardView" not in ren_src:
		_fail("MapRenderer Esc chain must dismiss SpaceLayerBoardView")
		return
	if "_esc_open_command_center" not in ren_src:
		_fail("idle Esc must still open Command Center")
		return
	if "_raise_title_chrome" not in agents_src or "TITLE_BAR_HEIGHT" not in agents_src:
		_fail("Agents must raise TitleBar above content overflow")
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
	_pass("source needles: shared CloseReleaseSwallow + Agents chrome + Space Esc + Trade guard")


func _catcher_ups() -> int:
	if _map_catcher != null and _map_catcher.has_method("left_ups"):
		return int(_map_catcher.call("left_ups"))
	return -1


func _reset_catcher() -> void:
	if _map_catcher != null and _map_catcher.has_method("reset"):
		_map_catcher.call("reset")


func _cc_opens() -> int:
	if _cc_probe != null and _cc_probe.has_method("opens"):
		return int(_cc_probe.call("opens"))
	return -1


func _reset_cc() -> void:
	if _cc_probe != null and _cc_probe.has_method("reset"):
		_cc_probe.call("reset")


func _drop_swallow_nodes() -> void:
	if root == null:
		return
	var sw: Node = root.get_node_or_null("CloseReleaseSwallow")
	if sw != null:
		sw.queue_free()
	var old: Node = root.get_node_or_null("SpaceTitleCloseReleaseSwallow")
	if old != null:
		old.queue_free()


func _test_empty_map_click_counts_one_release() -> void:
	_ensure_mouse_up()
	_reset_catcher()
	var map_pt := Vector2(640.0, 400.0)
	await _held_click_at(map_pt, false, 0)
	await _flush()
	if _catcher_ups() != 1:
		_fail("empty-map held click must count 1 unhandled mouse-up (got %d)" % _catcher_ups())
		return
	_pass("empty-map held click counted 1 unhandled mouse-up")


func _open_agents() -> bool:
	if _agent_screen != null and is_instance_valid(_agent_screen):
		_agent_screen.hide()
		_agent_screen.queue_free()
		_agent_screen = null
		await _flush()
	var packed: PackedScene = load("res://scenes/ui/AgentAssignmentScreen.tscn") as PackedScene
	if packed == null:
		_fail("AgentAssignmentScreen.tscn missing")
		return false
	var inst: Node = packed.instantiate()
	if inst == null or not (inst is Control):
		_fail("AgentAssignmentScreen instantiate failed")
		return false
	_agent_screen = inst as Control
	_agent_screen.name = "AgentAssignmentScreen"
	if "country_tag" in _agent_screen:
		_agent_screen.set("country_tag", "GER")
	_ui.add_child(_agent_screen)
	await _flush()
	if _agent_screen.has_method("_center_on_viewport"):
		_agent_screen.call("_center_on_viewport")
	await _flush()
	return true


func _test_agents_close_inside_viewport() -> void:
	if not await _open_agents():
		return
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
	if close_btn.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("Agents Close action_mode=%s want BUTTON_PRESS" % str(close_btn.action_mode))
		return
	_pass("Agents Close inside 1280x800 at %s (panel %s)" % [str(r), str(panel_r)])


func _test_agents_title_vs_show_no_overlap() -> void:
	if _agent_screen == null or not is_instance_valid(_agent_screen):
		if not await _open_agents():
			return
	var title: Control = _agent_screen.get_node_or_null("TitleBar/TitleLabel") as Control
	var filter_row: Control = _agent_screen.get_node_or_null(
		"MarginContainer/VBoxContainer/MainArea/ListsColumn/AgentsColumn/RosterFilterRow"
	) as Control
	if title == null or filter_row == null:
		_fail("Agents TitleLabel / RosterFilterRow missing")
		return
	var tr: Rect2 = title.get_global_rect()
	var fr: Rect2 = filter_row.get_global_rect()
	if tr.intersects(fr):
		_fail("Agents title %s overlaps Show: filter %s" % [str(tr), str(fr)])
		return
	_pass("Agents title vs Show: filter rects do not intersect")


func _test_agents_close_held_not_covered() -> void:
	if _agent_screen == null or not is_instance_valid(_agent_screen):
		if not await _open_agents():
			return
	var close_btn: Button = _agent_screen.get_node_or_null("TitleBar/CloseButton") as Button
	if close_btn == null:
		_fail("Agents CloseButton missing for held click")
		return
	var pt: Vector2 = close_btn.get_global_rect().get_center()
	_warp_mouse(pt)
	var motion := InputEventMouseMotion.new()
	motion.position = pt
	motion.global_position = pt
	Input.parse_input_event(motion)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	await _flush()
	var vp: Viewport = root.get_viewport()
	var hovered: Control = vp.gui_get_hovered_control() if vp != null else null
	var covered := true
	var walk: Node = hovered
	while walk != null:
		if walk == close_btn:
			covered = false
			break
		walk = walk.get_parent()
	if covered:
		_fail(
			"Agents Close covered by %s at %s (want CloseButton hover)"
			% [str(hovered), str(pt)]
		)
		return
	_ensure_mouse_up()
	_reset_catcher()
	await _held_click_control(close_btn, false)
	await _flush()
	var still_up := (
		_agent_screen != null
		and is_instance_valid(_agent_screen)
		and not _agent_screen.is_queued_for_deletion()
		and _agent_screen.visible
	)
	if still_up:
		_fail("Agents held Close did not close the screen")
		return
	if _catcher_ups() != 0:
		_fail("Agents held Close leaked %d map mouse-up(s)" % _catcher_ups())
		return
	_pass("Agents Close fully hoverable and held-click closed with 0 map mouse-ups")
	_agent_screen = null
	_drop_swallow_nodes()
	await _flush()


func _instantiate_named_screen(scene_path: String, node_name: String) -> Control:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		_fail("%s missing" % scene_path)
		return null
	var inst: Node = packed.instantiate()
	if inst == null or not (inst is Control):
		_fail("%s instantiate failed" % scene_path)
		return null
	var screen := inst as Control
	screen.name = node_name
	_ui.add_child(screen)
	return screen


func _test_prod_close_held_no_map_up() -> void:
	_ensure_mouse_up()
	_drop_swallow_nodes()
	var screen: Control = _instantiate_named_screen(
		"res://scenes/ui/ProductionAssignmentScreen.tscn", "ProductionAssignmentScreen"
	)
	if screen == null:
		return
	await _flush()
	var close_btn: Button = screen.get_node_or_null("TitleBar/CloseButton") as Button
	if close_btn == null:
		_fail("Prod CloseButton missing")
		screen.queue_free()
		return
	if close_btn.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("Prod Close action_mode=%s want BUTTON_PRESS" % str(close_btn.action_mode))
		screen.queue_free()
		return
	_reset_catcher()
	await _held_click_control(close_btn, false)
	await _flush()
	var still_up := (
		is_instance_valid(screen)
		and not screen.is_queued_for_deletion()
		and screen.visible
	)
	if still_up:
		_fail("Prod held Close did not close the screen")
		screen.queue_free()
		return
	if _catcher_ups() != 0:
		_fail("Prod held Close leaked %d map mouse-up(s)" % _catcher_ups())
		return
	_pass("Prod held Close closed with 0 map mouse-ups")
	_drop_swallow_nodes()
	await _flush()


func _test_mutant_prod_held_close_without_swallow() -> void:
	## Removing the shared swallow must make the Prod held-close case FAIL:
	## the matching mouse-up reaches the map catcher.
	_ensure_mouse_up()
	_drop_swallow_nodes()
	var screen: Control = _instantiate_named_screen(
		"res://scenes/ui/ProductionAssignmentScreen.tscn", "ProductionAssignmentScreen"
	)
	if screen == null:
		return
	await _flush()
	var close_btn: Button = screen.get_node_or_null("TitleBar/CloseButton") as Button
	if close_btn == null:
		_fail("Prod CloseButton missing for mutant")
		screen.queue_free()
		return
	for c in close_btn.pressed.get_connections():
		var cb: Callable = c.get("callable", Callable())
		if cb.is_valid() and close_btn.pressed.is_connected(cb):
			close_btn.pressed.disconnect(cb)
	close_btn.pressed.connect(screen.queue_free)
	_reset_catcher()
	await _held_click_control(close_btn, false)
	await _flush()
	if _catcher_ups() != 1:
		_fail(
			"mutant: Prod held-close without swallow must leak 1 map mouse-up (got %d)"
			% _catcher_ups()
		)
		if is_instance_valid(screen):
			screen.queue_free()
		return
	_pass("mutant: removing CloseReleaseSwallow makes Prod held-close leak 1 map mouse-up")
	if is_instance_valid(screen) and not screen.is_queued_for_deletion():
		screen.queue_free()
	_drop_swallow_nodes()
	await _flush()


func _test_leaders_close_held_no_map_up() -> void:
	_ensure_mouse_up()
	_drop_swallow_nodes()
	var screen: Control = _instantiate_named_screen(
		"res://scenes/ui/LeaderAssignmentScreen.tscn", "LeaderAssignmentScreen"
	)
	if screen == null:
		return
	await _flush()
	if screen.has_method("_fit_to_viewport"):
		screen.call("_fit_to_viewport")
	await _flush()
	var close_btn: Button = screen.get_node_or_null("CloseButton") as Button
	if close_btn == null:
		_fail("Leaders CloseButton missing")
		screen.queue_free()
		return
	if close_btn.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("Leaders Close action_mode=%s want BUTTON_PRESS" % str(close_btn.action_mode))
		screen.queue_free()
		return
	_reset_catcher()
	await _held_click_control(close_btn, false)
	await _flush()
	var still_up := (
		is_instance_valid(screen)
		and not screen.is_queued_for_deletion()
		and screen.visible
	)
	if still_up:
		_fail("Leaders held Close did not close the screen")
		screen.queue_free()
		return
	if _catcher_ups() != 0:
		_fail("Leaders held Close leaked %d map mouse-up(s)" % _catcher_ups())
		return
	_pass("Leaders held Close closed with 0 map mouse-ups")
	_drop_swallow_nodes()
	await _flush()


func _title_close_button(win: Window) -> Button:
	if win == null:
		return null
	var n: Node = win.find_child("TitleCloseButton", true, false)
	if n is Button:
		return n as Button
	return null


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
	if _space_view.size.x < 64 or _space_view.size.y < 64:
		_fail("Space board size too small %s" % str(_space_view.size))
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
	_reset_catcher()
	_click_window_at(_space_view, x_btn, true)
	await _flush()
	if _space_view.visible:
		_fail("Space × did not close on the first click (leftover release swallowed)")
		return
	_pass("Space × closed on first click via parse_input_event (leftover swallow)")


func _close_button(win: Window) -> Button:
	if win == null:
		return null
	var n: Node = win.find_child("CloseButton", true, false)
	if n is Button:
		return n as Button
	return null


func _free_space_view() -> void:
	if _space_view != null and is_instance_valid(_space_view):
		_space_view.hide()
		_space_view.queue_free()
	_space_view = null
	_drop_swallow_nodes()


func _open_space_board() -> bool:
	_free_space_view()
	var script: Resource = load("res://scripts/ui/SpaceLayerBoardView.gd")
	if script == null:
		_fail("SpaceLayerBoardView.gd missing")
		return false
	var view: Object = script.new()
	if view == null or not (view is Window):
		_fail("SpaceLayerBoardView instantiate failed")
		return false
	_space_view = view as Window
	_space_view.name = "SpaceLayerBoardView"
	root.add_child(_space_view)
	if _space_view.has_method("show_board"):
		_space_view.call("show_board", "GER")
	else:
		_space_view.popup_centered()
	return true


func _ensure_mouse_up() -> void:
	if _leftover != null and _leftover.has_method("disarm"):
		_leftover.call("disarm")
	var up: InputEventMouseButton = _make_mouse(Vector2(8.0, 8.0), false)
	Input.parse_input_event(up)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	_drop_swallow_nodes()


func _make_probe_button() -> Button:
	var btn := Button.new()
	btn.name = "UiPolish1ProbeButton"
	btn.text = "Probe"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	btn.position = Vector2(24.0, 720.0)
	btn.custom_minimum_size = Vector2(96.0, 32.0)
	btn.size = Vector2(96.0, 32.0)
	_probe_fired = 0
	if not btn.pressed.is_connected(_on_probe_pressed):
		btn.pressed.connect(_on_probe_pressed)
	_ui.add_child(btn)
	return btn


func _on_probe_pressed() -> void:
	_probe_fired += 1


func _click_control_main(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	var r: Rect2 = ctrl.get_global_rect()
	if r.size.x < 4.0 or r.size.y < 4.0:
		return false
	_click_at_window(r.get_center(), false, 0)
	return true


func _test_space_frame_x_then_unrelated_button() -> void:
	## Native/embedded frame × emits close_requested after the mouse is already up.
	if not _open_space_board():
		return
	await _flush()
	_ensure_mouse_up()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_fail("LMB still down before frame × close_requested")
		return
	_space_view.close_requested.emit()
	await _flush()
	if _space_view != null and is_instance_valid(_space_view) and _space_view.visible:
		_fail("Space frame × close_requested did not hide the board")
		return
	var probe: Button = _make_probe_button()
	await _flush()
	if not _click_control_main(probe):
		_fail("could not click unrelated probe after frame ×")
		probe.queue_free()
		return
	await _flush()
	if _probe_fired != 1:
		_fail("unrelated button did not fire after frame × (swallow ate release, fired=%d)" % _probe_fired)
		probe.queue_free()
		return
	probe.queue_free()
	_pass("Space frame × then unrelated button fired")


func _test_space_keyboard_close_then_click() -> void:
	## Bottom Close from the keyboard: no mouse release at close time.
	if not _open_space_board():
		return
	await _flush()
	_ensure_mouse_up()
	var close_btn: Button = _close_button(_space_view)
	if close_btn == null:
		_fail("Space CloseButton missing")
		return
	close_btn.pressed.emit()
	await _flush()
	if _space_view != null and is_instance_valid(_space_view) and _space_view.visible:
		_fail("Space keyboard Close did not hide the board")
		return
	var probe: Button = _make_probe_button()
	await _flush()
	if not _click_control_main(probe):
		_fail("could not click after keyboard Close")
		probe.queue_free()
		return
	await _flush()
	if _probe_fired != 1:
		_fail("click after keyboard Close did not fire (swallow ate release, fired=%d)" % _probe_fired)
		probe.queue_free()
		return
	probe.queue_free()
	_pass("Space keyboard Close then click fired")


func _test_space_close_then_map_select() -> void:
	## After Space is gone, a map press-release must select (not a stuck leftover swallow).
	if _space_view != null and is_instance_valid(_space_view) and _space_view.visible:
		_ensure_mouse_up()
		_space_view.close_requested.emit()
		await _flush()
	_ensure_mouse_up()
	if _map_probe != null and is_instance_valid(_map_probe):
		_map_probe.queue_free()
	_map_probe = _MapPickProbe.new()
	_map_probe.name = "UiPolish1MapPickProbe"
	root.add_child(_map_probe)
	await _flush()
	var map_pt := Vector2(640.0, 400.0)
	_click_at_window(map_pt, false, 0)
	await _flush()
	var selected := false
	if _map_probe != null and _map_probe.has_method("was_selected"):
		selected = bool(_map_probe.call("was_selected"))
	if not selected:
		_fail("map press-release after Space close did not select")
		return
	_pass("map press-release after Space close selected")


func _make_esc() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.device = 0
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.key_label = KEY_ESCAPE
	ev.unicode = 27
	return ev


func _send_esc_to_space() -> void:
	if _space_view == null or not is_instance_valid(_space_view):
		return
	_space_view.grab_focus()
	var esc: InputEventKey = _make_esc()
	# Live Window keeps Esc in its own viewport (Play: MapRenderer never logged).
	if _space_view.has_method("push_input"):
		_space_view.push_input(esc, true)
	else:
		Input.parse_input_event(esc)
		if Input.has_method("flush_buffered_events"):
			Input.flush_buffered_events()


func _test_space_esc_closes() -> void:
	if not _open_space_board():
		return
	await _flush()
	_ensure_mouse_up()
	_reset_cc()
	if not _space_view.visible:
		_fail("Space board not visible before Esc")
		return
	_send_esc_to_space()
	await _flush()
	if _space_view != null and is_instance_valid(_space_view) and _space_view.visible:
		_fail("Esc with Space open did not close Space")
		return
	if _cc_opens() != 0:
		_fail("Esc with Space open also reached Command Center path (opens=%d)" % _cc_opens())
		return
	_pass("Esc closed Space without opening Command Center")


func _test_idle_esc_reaches_command_center_path() -> void:
	_free_space_view()
	await _flush()
	_ensure_mouse_up()
	_reset_cc()
	if root is Window:
		(root as Window).grab_focus()
	var esc: InputEventKey = _make_esc()
	Input.parse_input_event(esc)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	await _flush()
	if _cc_opens() != 1:
		_fail("Esc with nothing open did not reach Command Center path (opens=%d)" % _cc_opens())
		return
	_pass("Esc with nothing open reached Command Center path")


func _trade_manager() -> Object:
	if root == null:
		return null
	return root.get_node_or_null("TradeManager")


func _count_deal_rejected_for(view: Object) -> int:
	var tm: Object = _trade_manager()
	if tm == null or not tm.has_signal("deal_rejected"):
		return 0
	var n := 0
	for c in tm.get_signal_connection_list("deal_rejected"):
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


func _held_click_at(screen_pt: Vector2, leftover_swallow: bool, window_id: int) -> void:
	if _leftover != null and _leftover.has_method("arm"):
		if leftover_swallow:
			_leftover.call("arm")
		else:
			_leftover.call("disarm")
	_warp_mouse(screen_pt)
	var down: InputEventMouseButton = _make_mouse(screen_pt, true)
	down.window_id = window_id
	Input.parse_input_event(down)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	await process_frame
	await create_timer(HELD_CLOSE_SEC).timeout
	var up: InputEventMouseButton = _make_mouse(screen_pt, false)
	up.window_id = window_id
	Input.parse_input_event(up)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


func _held_click_control(ctrl: Control, leftover_swallow: bool) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	var r: Rect2 = ctrl.get_global_rect()
	await _held_click_at(r.get_center(), leftover_swallow, 0)


func _click_window_at(win: Window, btn: Control, swallow_release: bool) -> void:
	var local_pt: Vector2 = btn.get_global_rect().get_center()
	var embed_pt: Vector2 = Vector2(win.position) + local_pt
	win.grab_focus()
	# Embedded in the main window (id 0): click in parent coords over the ×.
	_click_at_window(embed_pt, swallow_release, 0)


func _click_at_window(screen_pt: Vector2, swallow_release: bool, window_id: int) -> void:
	if _leftover != null and _leftover.has_method("arm"):
		if swallow_release:
			_leftover.call("arm")
		else:
			_leftover.call("disarm")
	_warp_mouse(screen_pt)
	var down: InputEventMouseButton = _make_mouse(screen_pt, true)
	down.window_id = window_id
	Input.parse_input_event(down)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	var up: InputEventMouseButton = _make_mouse(screen_pt, false)
	up.window_id = window_id
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
	if _map_probe != null and is_instance_valid(_map_probe):
		_map_probe.queue_free()
	if _map_catcher != null and is_instance_valid(_map_catcher):
		_map_catcher.queue_free()
	if _cc_probe != null and is_instance_valid(_cc_probe):
		_cc_probe.queue_free()
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	if _leftover != null and is_instance_valid(_leftover):
		_leftover.queue_free()
	_drop_swallow_nodes()


class _MapReleaseCatcher extends Node:
	## Counts left button-ups that reach `_unhandled_input` (map stand-in).
	var _left_ups: int = 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process_unhandled_input(true)

	func reset() -> void:
		_left_ups = 0

	func left_ups() -> int:
		return _left_ups

	func _unhandled_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			return
		_left_ups += 1


class _CcPathProbe extends Node:
	## Idle Esc with nothing open must still reach this unhandled path (CC).
	var _opens: int = 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process_unhandled_input(true)

	func reset() -> void:
		_opens = 0

	func opens() -> int:
		return _opens

	func _unhandled_input(event: InputEvent) -> void:
		if not (event is InputEventKey):
			return
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if (
			key.keycode == KEY_ESCAPE
			or key.physical_keycode == KEY_ESCAPE
			or key.key_label == KEY_ESCAPE
			or int(key.unicode) == 27
		):
			_opens += 1


class _MapPickProbe extends Node:
	## Map pick-on-release (MapRenderer leftover class): an eaten up = missed select.
	var _down: bool = false
	var _selected: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process_unhandled_input(true)

	func was_selected() -> bool:
		return _selected

	func _unhandled_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_down = true
			return
		if _down:
			_down = false
			_selected = true


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
