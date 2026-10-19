extends SceneTree

## CL1 FIX #2: at 1280×800 the top-bar Pause + speed buttons must stay
## inside the viewport, with no overlap, in peace and at war.
## Live Play on 2a7da052: "At war: Poland" shifted the row left and Pause
## went off-screen. Fail that layout; keep date readable.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessCampaignLoop1TopBarFitTest.gd

const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 8
const CLOCK_NAMES: Array[String] = [
	"PauseButton",
	"Speed1Button",
	"Speed2Button",
	"Speed3Button",
	"Speed4Button",
]

var _failures := 0
var _war: GDScript
var _bar: Control
var _ui: CanvasLayer


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessCampaignLoop1TopBarFitTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCampaignLoop1TopBarFitTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCampaignLoop1TopBarFitTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCampaignLoop1TopBarFitTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	var lm := get_root().get_node_or_null("LeaderManager")
	var tm := get_root().get_node_or_null("TimeManager")
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	if _war == null:
		_fail("WarStateDomain missing")
		return
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	if tm != null:
		tm.scenario_start_year = 1936
		tm.current_year = 1936
		tm.current_month = 1
		tm.current_day = 1
		tm.paused = true
	_war.reset_for_test()
	_war.clear_rule_overrides()
	if not _war.loop_enabled():
		_fail("campaign loop inactive")
		return
	if not await _boot_bar():
		return
	await _assert_case("peace", 0)
	_war.reset_for_test()
	var one: Dictionary = _war.declare_war("GER", "POL", "call_to_arms")
	if not bool(one.get("ok", false)):
		_fail("declare POL failed %s" % str(one))
		return
	await _assert_case("war1", 1)
	var two: Dictionary = _war.declare_war("GER", "FRA", "call_to_arms")
	var three: Dictionary = _war.declare_war("GER", "CZE", "call_to_arms")
	if not bool(two.get("ok", false)) or not bool(three.get("ok", false)):
		_fail("declare FRA/CZE failed %s %s" % [str(two), str(three)])
		return
	await _assert_case("war3", 3)
	_cleanup()


func _boot_bar() -> bool:
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
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_left = 0.0
	_bar.offset_top = 0.0
	_bar.offset_right = 0.0
	_bar.offset_bottom = 52.0
	_ui.add_child(_bar)
	_host_search_stub()
	await _flush()
	if _bar.has_method("_apply_responsive_layout"):
		_bar.call("_apply_responsive_layout")
	await _flush()
	var pause := _named_button("PauseButton")
	if pause == null or not pause.visible:
		_fail("PauseButton missing after boot")
		return false
	_pass("TopInfoBar booted at %dx%d pause=%s" % [PLAY_SIZE.x, PLAY_SIZE.y, str(pause.get_global_rect())])
	return true


func _host_search_stub() -> void:
	## Live Play hosts MapProvinceSearch at 308px on the right. Without it
	## this harness would not reproduce the 1280 overflow.
	var search := HBoxContainer.new()
	search.name = "MapProvinceSearch"
	search.custom_minimum_size = Vector2(308, 32)
	search.size_flags_horizontal = Control.SIZE_SHRINK_END
	var line := LineEdit.new()
	line.name = "SearchLineEdit"
	line.custom_minimum_size = Vector2(240, 28)
	line.placeholder_text = "Search"
	var go := Button.new()
	go.name = "SearchGoButton"
	go.text = "Go"
	go.custom_minimum_size = Vector2(44, 28)
	search.add_child(line)
	search.add_child(go)
	if _bar.has_method("host_map_search_chrome"):
		_bar.call("host_map_search_chrome", search)
	else:
		var right := _bar.get_node_or_null("ContentRow/RightContainer")
		if right != null:
			right.add_child(search)


func _assert_case(label: String, enemy_n: int) -> void:
	if _bar.has_method("refresh_campaign_war_readout"):
		_bar.call("refresh_campaign_war_readout")
	if _bar.has_method("_apply_responsive_layout"):
		_bar.call("_apply_responsive_layout")
	await _flush()
	var hud := _bar.find_child("CampaignWarReadout", true, false) as Label
	if enemy_n <= 0:
		if hud != null and hud.visible and not str(hud.text).strip_edges().is_empty():
			_fail("%s war chip should be hidden got %s" % [label, hud.text])
			return
		_pass("%s no war chip" % label)
	else:
		if hud == null or not hud.visible:
			_fail("%s CampaignWarReadout missing" % label)
			return
		if str(hud.text).find("At war") < 0:
			_fail("%s war chip want At war got %s" % [label, hud.text])
			return
		_pass("%s war chip %s" % [label, hud.text])
	var date := _bar.find_child("DateTimeLabel", true, false) as Label
	if date == null or not date.visible:
		_fail("%s DateTimeLabel missing" % label)
		return
	if str(date.text).find("1936") < 0:
		_fail("%s date not readable got %s" % [label, date.text])
		return
	var date_r: Rect2 = date.get_global_rect()
	if not _rect_in_viewport(date_r):
		_fail("%s date off-screen %s" % [label, str(date_r)])
		return
	_pass("%s date %s at %s" % [label, date.text, str(date_r)])
	var seen: Dictionary = {}
	for nm in CLOCK_NAMES:
		var btn := _named_button(nm)
		if btn == null or not btn.visible:
			_fail("%s %s missing/hidden" % [label, nm])
			return
		var r: Rect2 = btn.get_global_rect()
		if r.size.x < 8.0 or r.size.y < 8.0:
			_fail("%s %s rect too small %s" % [label, nm, str(r)])
			return
		if not _rect_in_viewport(r):
			_fail("%s %s off-screen %s" % [label, nm, str(r)])
			return
		seen[nm] = r
		_pass("%s %s %s" % [label, nm, str(r)])
	var buttons: Array = _visible_bar_buttons()
	if buttons.size() < CLOCK_NAMES.size():
		_fail("%s too few visible buttons %d" % [label, buttons.size()])
		return
	for i in range(buttons.size()):
		var a: Control = buttons[i]
		var ra: Rect2 = a.get_global_rect()
		if not _rect_in_viewport(ra):
			_fail("%s button %s off-screen %s" % [label, a.name, str(ra)])
			return
		for j in range(i + 1, buttons.size()):
			var b: Control = buttons[j]
			var rb: Rect2 = b.get_global_rect()
			if _rects_overlap(ra, rb):
				_fail("%s overlap %s %s vs %s %s" % [label, a.name, str(ra), b.name, str(rb)])
				return
	_pass("%s %d buttons inside 1280x800, no overlap" % [label, buttons.size()])


func _named_button(nm: String) -> BaseButton:
	if _bar == null:
		return null
	return _bar.find_child(nm, true, false) as BaseButton


func _visible_bar_buttons() -> Array:
	var out: Array = []
	if _bar == null:
		return out
	_collect_buttons(_bar, out)
	return out


func _collect_buttons(n: Node, out: Array) -> void:
	if n is BaseButton:
		var btn := n as BaseButton
		if btn.visible and btn.get_global_rect().size.x >= 4.0 and btn.get_global_rect().size.y >= 4.0:
			out.append(btn)
	for child in n.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		_collect_buttons(child, out)


func _rect_in_viewport(r: Rect2) -> bool:
	var vp := Rect2(Vector2.ZERO, Vector2(float(PLAY_SIZE.x), float(PLAY_SIZE.y)))
	return r.position.x >= 0.0 and r.position.y >= 0.0 \
		and r.end.x <= vp.end.x + 0.5 and r.end.y <= vp.end.y + 0.5


func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	var aa := a.grow(-0.5)
	var bb := b.grow(-0.5)
	return aa.intersects(bb)


func _cleanup() -> void:
	if _bar != null and is_instance_valid(_bar):
		_bar.queue_free()
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
