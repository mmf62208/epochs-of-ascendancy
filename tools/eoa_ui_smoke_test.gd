# tools/eoa_ui_smoke_test.gd
## Headless smoke: load TestScenario, verify TopInfoBar + province pick + input unlock.
## Run:
##   EOA_HEADLESS_EVIDENCE=1 EOA_OOB_EVIDENCE_DAYS=1 \
##   tools/run_godot.sh --headless -s res://tools/eoa_ui_smoke_test.gd
extends SceneTree

const SCENE := "res://scenes/TestScenario.tscn"
const MAX_WAIT_FRAMES := 3600
const SETTLE_FRAMES := 60

var _frames := 0
var _phase := "boot"
var _fail: PackedStringArray = []
var _pass: PackedStringArray = []


func _init() -> void:
	print("=== EOA UI SMOKE TEST start ===")
	root.ready.connect(_on_root_ready, CONNECT_ONE_SHOT)


func _on_root_ready() -> void:
	var err := change_scene_to_file(SCENE)
	if err != OK:
		_fail.append("change_scene_to_file failed code=%d" % err)
		_finish()
		return
	_phase = "wait_load"
	print("SMOKE: loading ", SCENE)


func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == "wait_load":
		_poll_load()
	elif _phase == "settle":
		if _frames >= SETTLE_FRAMES:
			_phase = "run_tests"
			_run_tests()
	return false


func _poll_load() -> void:
	if _frames > MAX_WAIT_FRAMES:
		_fail.append("timeout waiting for map load (%d frames)" % _frames)
		_finish()
		return
	var scene := current_scene
	if scene == null:
		return
	var mr := _find_map_renderer(scene)
	var top := scene.get_node_or_null("UILayer/TopInfoBar")
	var n_prov := 0
	if mr != null and "provinces" in mr:
		n_prov = (mr.provinces as Dictionary).size()
	if mr != null and top != null and n_prov > 100:
		_phase = "settle"
		_frames = 0
		print("SMOKE: map+topbar ready provinces=%d frame=%d" % [n_prov, Engine.get_process_frames()])


func _find_map_renderer(from: Node) -> Node:
	if from == null:
		return null
	var n := from.find_child("WorldMap", true, false)
	if n:
		return n
	return from.find_child("MapRenderer", true, false)


func _run_tests() -> void:
	print("SMOKE: running checks…")
	var scene := current_scene
	if scene == null:
		_fail.append("no current_scene")
		_finish()
		return

	# Force interactive unlock path if present
	if scene.has_method("_ensure_game_interactive"):
		scene.call("_ensure_game_interactive")
		_pass.append("ensure_game_interactive_called")

	# --- Input blockers ---
	var blockers: Array = []
	_walk_blockers(root, blockers)
	if blockers.is_empty():
		_pass.append("no_visible_LoadingScreen_InputBlocker")
	else:
		_fail.append("visible blockers count=%d" % blockers.size())
		_force_clear_blockers(root)
		blockers.clear()
		_walk_blockers(root, blockers)
		if blockers.is_empty():
			_pass.append("blockers_cleared_after_force")
		else:
			_fail.append("blockers remain=%d" % blockers.size())

	# --- Debug overlay (via class script statics if registered) ---
	var dbg_scr = load("res://scripts/ui/DebugOverlay.gd")
	if dbg_scr != null:
		if dbg_scr.has_method("hide_overlay"):
			dbg_scr.hide_overlay()
		var inst = dbg_scr.get("instance") if dbg_scr.get("instance") != null else null
		# instance is a static var on the script
		if typeof(inst) == TYPE_OBJECT and is_instance_valid(inst):
			if not inst.visible:
				_pass.append("DebugOverlay_hidden")
			else:
				_fail.append("DebugOverlay still visible")
			if inst.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				_pass.append("DebugOverlay_mouse_ignore")
			else:
				_fail.append("DebugOverlay mouse_filter=%d" % inst.mouse_filter)
		else:
			_pass.append("DebugOverlay_no_instance_ok")

	# --- TopInfoBar ---
	var top: Node = scene.get_node_or_null("UILayer/TopInfoBar")
	if top == null:
		_fail.append("TopInfoBar missing")
	else:
		_pass.append("TopInfoBar_present")
		if top is Control and (top as Control).visible:
			_pass.append("TopInfoBar_visible")
		else:
			_fail.append("TopInfoBar not visible")
		for path in [
			"ContentRow/LeftContainer/TimeSpeedContainer/PauseButton",
			"ContentRow/CenterContainer/ProductionButton",
			"ContentRow/CenterContainer/LeadersButton",
			"ContentRow/CenterContainer/TechnologyButton",
			"ContentRow/CenterContainer/DiplomacyButton",
			"ContentRow/CenterContainer/AgentsButton",
		]:
			var b := top.get_node_or_null(path) as BaseButton
			if b == null:
				_fail.append("missing %s" % path.get_file())
			elif b.visible:
				_pass.append("btn:%s" % path.get_file())
			else:
				_fail.append("hidden %s" % path.get_file())
		# Call handlers
		for method in ["_on_pause_pressed", "_set_game_speed", "_on_production_pressed",
				"_on_leaders_pressed", "_on_technology_pressed", "_on_diplomacy_pressed",
				"_on_agents_pressed"]:
			if not top.has_method(method):
				_fail.append("missing method %s" % method)
				continue
			if method == "_set_game_speed":
				top.call(method, 1)
			else:
				top.call(method)
			_close_named_screens()
			_pass.append("call:%s" % method)
		if top.has_method("_apply_responsive_layout"):
			top.call("_apply_responsive_layout")
		if top.has_method("_ensure_nav_overflow_menu"):
			top.call("_ensure_nav_overflow_menu")
		var more := top.find_child("NavOverflowMenu", true, false)
		if more:
			_pass.append("More_menu_present")
		else:
			_fail.append("More menu missing")
		var menu_ok := false
		if "menu_button" in top and top.menu_button != null:
			menu_ok = true
		else:
			var mc := top.get_node_or_null("ContentRow/RightContainer/MenuContainer")
			if mc:
				for c in mc.get_children():
					if c is MenuButton:
						menu_ok = true
						break
		if menu_ok:
			_pass.append("Menu_button_present")
		else:
			_fail.append("Menu button missing")

	# --- Map + province pick ---
	var mr := _find_map_renderer(scene)
	if mr == null:
		_fail.append("MapRenderer missing")
	else:
		_pass.append("MapRenderer_present")
		var n_prov := 0
		if "provinces" in mr:
			n_prov = (mr.provinces as Dictionary).size()
		if n_prov >= 100:
			_pass.append("provinces=%d" % n_prov)
		else:
			_fail.append("few provinces=%d" % n_prov)
		var mm: Node = root.get_node_or_null("/root/MapManager")
		if mm != null and mm.has_method("get_all_centroids"):
			var cents: Dictionary = mm.call("get_all_centroids")
			var pick_ok := 0
			var pick_fail := 0
			var sample: Array[int] = []
			var i := 0
			for pid_v in cents.keys():
				sample.append(int(pid_v))
				i += 1
				if i >= 30:
					break
			for pid in sample:
				var c: Vector2 = cents.get(pid, Vector2.ZERO)
				if c == Vector2.ZERO:
					continue
				var hit := -1
				if mm.has_method("get_province_at_world_pos"):
					hit = int(mm.call("get_province_at_world_pos", c, true))
				if mm.has_method("resolve_pick_province_id"):
					hit = int(mm.call("resolve_pick_province_id", hit))
				if hit == pid or (hit >= 0 and mm.has_method("get_province") and mm.call("get_province", hit) != null):
					pick_ok += 1
				else:
					pick_fail += 1
			if pick_ok >= 5:
				_pass.append("province_pick ok=%d fail=%d" % [pick_ok, pick_fail])
			else:
				_fail.append("province_pick weak ok=%d fail=%d" % [pick_ok, pick_fail])
			if mr.has_method("show_info_panel") and sample.size() > 0 and mm.has_method("get_province"):
				var p0 = mm.call("get_province", sample[0])
				if p0:
					mr.call("show_info_panel", p0)
					_pass.append("show_info_panel")
		var U = load("res://scripts/map/ProvincePolygonUtil.gd")
		if U:
			var bow := PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
			var d = U.make_drawable(bow)
			if d.size() >= 3 and U.is_drawable(d):
				_pass.append("polygon_util_safe")
			else:
				_fail.append("polygon_util_failed")

	var cam := scene.find_child("CameraInput", true, false)
	if cam:
		_pass.append("CameraInput_present")
		if "enable_pan" in cam:
			cam.enable_pan = true
		if "enable_zoom" in cam:
			cam.enable_zoom = true
	else:
		_pass.append("CameraInput_optional")

	_finish()


func _close_named_screens() -> void:
	var names := [
		"ProductionAssignmentScreen", "LeaderAssignmentScreen", "TechnologyScreen",
		"DiplomacyView", "AgentAssignmentScreen", "TradeMarketView", "MainMenu",
		"PolicyLawScreen",
	]
	for nm in names:
		var n := root.get_node_or_null(nm)
		if n and is_instance_valid(n):
			n.queue_free()
		if current_scene:
			var n2 := current_scene.find_child(nm, true, false)
			if n2 and is_instance_valid(n2):
				n2.queue_free()


func _walk_blockers(node: Node, acc: Array) -> void:
	if node == null:
		return
	var nm := str(node.name)
	if nm == "LoadingScreen" or nm == "InputBlocker":
		var vis := true
		if node is CanvasLayer:
			vis = (node as CanvasLayer).visible
		elif node is CanvasItem:
			vis = (node as CanvasItem).visible
		if vis:
			acc.append(node)
	for c in node.get_children():
		_walk_blockers(c, acc)


func _force_clear_blockers(node: Node) -> void:
	var acc: Array = []
	_walk_blockers(node, acc)
	for n in acc:
		if not is_instance_valid(n):
			continue
		if n is Control:
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			(n as Control).visible = false
		if n is CanvasItem:
			(n as CanvasItem).visible = false
		if n.has_method("hide_and_free"):
			n.call("hide_and_free")
		else:
			n.queue_free()


func _finish() -> void:
	print("=== EOA UI SMOKE RESULTS ===")
	print("PASS_COUNT=", _pass.size())
	for p in _pass:
		print("  PASS: ", p)
	print("FAIL_COUNT=", _fail.size())
	for f in _fail:
		print("  FAIL: ", f)
	if _fail.is_empty():
		print("=== SMOKE OVERALL PASS ===")
		quit(0)
	else:
		print("=== SMOKE OVERALL FAIL ===")
		quit(1)
