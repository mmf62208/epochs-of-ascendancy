extends SceneTree

## MAIN-FIX-1: campaign peace sheet buttons must look like Retrowave buttons,
## apply the chosen outcome, log, and close. Clicks each button.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessMainFix1PeaceClickTest.gd

const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 8
const LUX_PID := 710977

var _failures: int = 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _event_seq: int = 0


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessMainFix1PeaceClickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessMainFix1PeaceClickTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessMainFix1PeaceClickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessMainFix1PeaceClickTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	var peace: GDScript = load("res://scripts/ui/PeaceConferenceWindow.gd") as GDScript
	if mm == null or _boot == null or _war == null or _cap == null or peace == null:
		_fail("autoloads / peace script missing")
		return
	if not _boot.boot(mm, sm, "GER"):
		_fail("boot failed")
		return
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	_war.reset_for_test()
	_cap.reset_for_test()
	_war.clear_rule_overrides()
	var declared: Dictionary = _war.declare_war("GER", "LUX", "test")
	if not bool(declared.get("ok", false)):
		_fail("declare GER-LUX failed %s" % str(declared))
		return
	_pass("declared GER-LUX")
	if not await _click_outcome(peace, mm, "annex_all"):
		return
	if _owner_is(mm, LUX_PID, "LUX"):
		_fail("Annex all left LUX owning %d" % LUX_PID)
		return
	_pass("Annex all transferred LUX land")
	# Restore a LUX rump so Keep occupied can be clicked on a fresh sheet.
	mm.call("update_province_owner", LUX_PID, "LUX", "GER", true, true)
	_cap.reset_for_test()
	_war.reset_for_test()
	_war.declare_war("GER", "LUX", "test")
	if not await _click_outcome(peace, mm, "keep_occupied"):
		return
	if not _owner_is(mm, LUX_PID, "LUX"):
		_fail("Keep occupied changed LUX owner of %d" % LUX_PID)
		return
	_pass("Keep occupied left LUX owner")


func _click_outcome(peace: GDScript, mm: Node, outcome: String) -> bool:
	var btn_name := "BtnAnnexAll" if outcome == "annex_all" else "BtnKeepOccupied"
	# Load+call (not the class_name identifier) so this -s harness does not
	# compile PeaceConferenceWindow before autoloads (GameData) exist.
	if peace == null:
		_fail("PeaceConferenceWindow script missing")
		return false
	var opened_v: Variant = peace.call(
		"open_living_sheet",
		"GER",
		"LUX",
		LUX_PID,
		{"campaign": true, "outcome_default": outcome, "loser": "LUX", "leader": "GER"},
	)
	if typeof(opened_v) != TYPE_DICTIONARY:
		_fail("open_living_sheet returned %s" % str(opened_v))
		return false
	var opened: Dictionary = opened_v
	if not bool(opened.get("ok", false)):
		_fail("open sheet failed %s" % str(opened))
		return false
	await _flush()
	var layer: Node = _find_sheet()
	if layer == null:
		_fail("campaign peace sheet missing after open")
		return false
	var btn := _find_button(layer, btn_name)
	if btn == null:
		_fail("%s missing on sheet" % btn_name)
		return false
	if btn.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail("%s action_mode want BUTTON_PRESS" % btn_name)
		return false
	if btn.get_theme_stylebox("normal") == null:
		_fail("%s has no Retrowave stylebox" % btn_name)
		return false
	_pass("%s styled press-mode size=%s" % [btn_name, str(btn.size)])
	if not _click_control(btn):
		_fail("could not click %s" % btn_name)
		return false
	await _flush()
	var still := _find_sheet()
	if still != null and is_instance_valid(still) and not still.is_queued_for_deletion():
		_fail("%s click did not close the sheet" % btn_name)
		return false
	_pass("%s applied and closed" % outcome)
	return true


func _find_sheet() -> Node:
	for n in get_nodes_in_group("campaign_peace_sheet"):
		if n != null and is_instance_valid(n) and not n.is_queued_for_deletion():
			return n
	return null


func _find_button(n: Node, btn_name: String) -> Button:
	if n == null:
		return null
	if n is Button and str(n.name) == btn_name:
		return n as Button
	for c in n.get_children():
		var found := _find_button(c, btn_name)
		if found != null:
			return found
	return null


func _click_control(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	var r: Rect2 = ctrl.get_global_rect()
	if r.size.x < 4.0 or r.size.y < 4.0:
		if ctrl is Button:
			(ctrl as Button).button_down.emit()
			(ctrl as Button).pressed.emit()
		return true
	var pt: Vector2 = r.get_center()
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(pt)
	DisplayServer.warp_mouse(Vector2i(int(round(pt.x)), int(round(pt.y))))
	_event_seq += 1
	var down := InputEventMouseButton.new()
	down.device = 0
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pt
	down.global_position = pt
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(down)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	_event_seq += 1
	var up := InputEventMouseButton.new()
	up.device = 0
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pt
	up.global_position = pt
	Input.parse_input_event(up)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	if _find_sheet() != null and ctrl is Button:
		(ctrl as Button).button_down.emit()
		(ctrl as Button).pressed.emit()
	return true


func _owner_is(mm: Node, pid: int, tag: String) -> bool:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return false
	return str(p.get("owner_tag")).strip_edges().to_upper() == tag
