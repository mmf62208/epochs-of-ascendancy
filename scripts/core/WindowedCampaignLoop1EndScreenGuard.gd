extends SceneTree

## Windowed CL1 evidence on a private Xvfb. Not live Play.
## Chrome shots (war HUD, declare button) always run.
## End-screen shots run when EOA_CL1_END_SHOTS=1 (CL1c).

var _failures := 0
var _map_picks := 0
var _boot: GDScript
var _war: GDScript
var _chrome: GDScript
var _cap: GDScript
var _end: GDScript
var _probe: Node


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] WindowedCampaignLoop1EndScreenGuard: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] WindowedCampaignLoop1EndScreenGuard: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_chrome = load("res://scripts/ui/CampaignWarChrome.gd") as GDScript
	if mm == null or _boot == null or _war == null or _chrome == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.boot(mm, sm, "GER"):
		_fail("boot failed")
		_finish()
		return
	var tm := get_root().get_node_or_null("TimeManager")
	if tm != null:
		tm.paused = true
	_war.reset_for_test()
	_war.clear_rule_overrides()
	var declared: Dictionary = _war.declare_war("GER", "FRA", "shot")
	if not bool(declared.get("ok", false)):
		_fail("declare GER-FRA failed %s" % str(declared))
	var line := str(_war.player_enemies_line())
	if line.find("At war:") < 0 or line.find("France") < 0:
		_fail("HUD line want At war: France got %s" % line)
	else:
		_pass("HUD line %s" % line)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		_fail("TopInfoBar scene missing")
	else:
		var bar: Node = packed.instantiate()
		bar.set("position", Vector2(0, 0))
		root.add_child(bar)
		if bar.has_method("refresh_campaign_war_readout"):
			bar.call("refresh_campaign_war_readout")
		var lbl := bar.find_child("CampaignWarReadout", true, false) as Label
		if lbl == null or str(lbl.text).find("At war:") < 0:
			_fail("CampaignWarReadout missing text=%s" % (str(lbl.text) if lbl != null else "null"))
		else:
			_pass("CampaignWarReadout visible text=%s" % lbl.text)
	var pol_to := _border_to(mm, "GER", "POL")
	var host := Panel.new()
	host.name = "InspectorChrome"
	host.position = Vector2(36, 160)
	host.size = Vector2(320, 160)
	host.custom_minimum_size = Vector2(320, 160)
	root.add_child(host)
	var title := Label.new()
	title.text = "Province inspector"
	title.position = Vector2(8, 8)
	host.add_child(title)
	var prov: Object = mm.call("get_province", pol_to) if pol_to > 0 else null
	_chrome.mount(host, prov)
	var btn := host.get_node_or_null("BtnDeclareWar") as Button
	if btn == null or not btn.visible or str(btn.text).find("war on") < 0:
		_fail("declare button missing text=%s" % (str(btn.text) if btn != null else "null"))
	else:
		_pass("declare button %s" % btn.text)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	_shot("war_hud")
	if host != null:
		host.position = Vector2(80, 80)
	await process_frame
	RenderingServer.force_draw()
	_shot("declare_button")
	await _peace_sheet(mm, sm)
	await _end_shots(mm, sm)
	_finish()


func _peace_sheet(mm: Node, sm: Node) -> void:
	var cap: GDScript = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	if cap == null or _war == null:
		_fail("peace sheet domains missing")
		return
	cap.apply_economy_factories_to_map()
	const LUX_PID := 710977
	var declared: Dictionary = _war.declare_war("GER", "LUX", "shot")
	if not bool(declared.get("ok", false)):
		_fail("declare GER-LUX failed %s" % str(declared))
		return
	if sm != null and sm.has_method("begin_control_batch"):
		sm.call("begin_control_batch")
	mm.call("update_province_owner", LUX_PID, "LUX", "GER", true, true)
	if sm != null and sm.has_method("end_control_batch"):
		sm.call("end_control_batch")
	cap.check_all(1)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var sheet := root.find_child("CampaignPeaceSheet", true, false)
	if sheet == null:
		_fail("peace sheet missing")
	else:
		var annex := sheet.find_child("BtnAnnexAll", true, false) as Button
		var keep := sheet.find_child("BtnKeepOccupied", true, false) as Button
		if annex == null or keep == null or not annex.visible or not keep.visible:
			_fail("peace buttons missing")
		else:
			_pass("peace sheet %s / %s" % [annex.text, keep.text])
	_shot("peace_sheet")


func _shot(name: String) -> void:
	var vp := root.get_viewport()
	if vp == null:
		_fail("no viewport")
		return
	var tex := vp.get_texture()
	if tex == null:
		_fail("no viewport texture")
		return
	var img := tex.get_image()
	if img == null:
		_fail("no image")
		return
	var path := OS.get_environment("HOME") + "/campaign1_evidence/%s.png" % name
	var err := img.save_png(path)
	if err != OK:
		_fail("save %s err=%d" % [path, err])
	else:
		_pass("shot %s %dx%d" % [path, img.get_width(), img.get_height()])


func _end_shots(mm: Node, sm: Node) -> void:
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if _cap == null or _end == null:
		_fail("end domains missing")
		return
	_dismiss_modals()
	var hud := CanvasLayer.new()
	hud.name = "HudStandIn"
	hud.layer = 110
	root.add_child(hud)
	var sentinel := Button.new()
	sentinel.name = "MapPickSentinel"
	sentinel.text = "map pick"
	sentinel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sentinel.mouse_filter = Control.MOUSE_FILTER_STOP
	sentinel.pressed.connect(_on_map_pick)
	root.add_child(sentinel)
	_probe = MapClickProbe.new()
	_probe.name = "MapClickProbe"
	root.add_child(_probe)
	root.move_child(_probe, 0)
	await _latch_shot(mm, sm, "defeat", "POL")
	await _click_main_menu()
	await _latch_shot(mm, sm, "victory", "GER")
	await _latch_shot(mm, sm, "time", "GER")


func _on_map_pick() -> void:
	_map_picks += 1


func _latch_shot(mm: Node, sm: Node, kind: String, player: String) -> void:
	_dismiss_modals()
	if not _boot.boot(mm, sm, player):
		_fail("%s boot failed" % kind)
		return
	var tm := get_root().get_node_or_null("TimeManager")
	if tm != null:
		tm.paused = false
	_cap.apply_economy_factories_to_map()
	_war.reset_for_test()
	_cap.reset_for_test()
	_end.call("reset_for_test")
	_war.clear_rule_overrides()
	if kind == "time":
		_war.set_rule_overrides({"end_date": "1936-01-02"})
		_advance(tm)
	else:
		if not bool(_war.declare_war("GER", "POL", "shot").get("ok", false)):
			_fail("%s declare failed" % kind)
			return
		if kind == "victory":
			_war.set_rule_overrides({"victory_min_majors_defeated": 1, "victory_count_minors": true})
		_hold_until(mm, sm, "POL", "GER")
		_advance(tm)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var screen := _end_screen()
	if screen == null:
		_fail("%s end screen missing" % kind)
		return
	var title := screen.find_child("Title", true, false) as Label
	var reason := screen.find_child("Reason", true, false) as Label
	var date_l := screen.find_child("Date", true, false) as Label
	var keep := screen.find_child("BtnKeepPlaying", true, false) as Button
	var cont := screen.find_child("BtnContinue", true, false) as Button
	if title == null or reason == null or date_l == null:
		_fail("%s labels missing" % kind)
		return
	if int(screen.layer) != 125 or int(screen.layer) <= 110:
		_fail("%s layer %d" % [kind, int(screen.layer)])
		return
	if not screen.visible:
		_fail("%s panel hidden" % kind)
		return
	var want_title := ""
	if kind == "defeat":
		want_title = "Defeat"
	elif kind == "victory":
		want_title = "Victory"
	else:
		var ranked: Array = _end.call("factory_rank")
		want_title = "Victory: Ascendant" if not ranked.is_empty() and str(ranked[0]) == "GER" else "Defeat: Eclipsed (rank %d)" % _rank_of(ranked, "GER")
	if str(title.text) != want_title:
		_fail("%s title want %s got %s" % [kind, want_title, title.text])
		return
	if kind == "defeat" and str(reason.text).find("capitulated") < 0:
		_fail("%s reason %s" % [kind, reason.text])
		return
	if kind == "victory" and str(reason.text).find("Decisive") < 0:
		_fail("%s reason %s" % [kind, reason.text])
		return
	if str(date_l.text).is_empty():
		_fail("%s date empty" % kind)
		return
	if cont == null or cont.visible:
		_fail("%s Continue should stay hidden" % kind)
		return
	var stats_l := screen.find_child("Stats", true, false) as Label
	if stats_l == null or str(stats_l.text).find("controlled") < 0:
		_fail("%s stats missing controlled provinces %s" % [kind, str(stats_l.text) if stats_l != null else "null"])
		return
	var panel := screen.find_child("EndPanel", true, false) as Panel
	if panel == null:
		_fail("%s EndPanel missing" % kind)
		return
	var st: StyleBox = panel.get_theme_stylebox("panel")
	if not (st is StyleBoxFlat) or float((st as StyleBoxFlat).bg_color.a) < 0.99:
		_fail("%s EndPanel not opaque" % kind)
		return
	var sheet := root.find_child("CampaignPeaceSheet", true, false)
	if sheet != null and is_instance_valid(sheet) and bool(sheet.visible):
		_fail("%s peace sheet still visible behind end screen" % kind)
		return
	var toast_ui := root.get_node_or_null("LeaderEventUI")
	if toast_ui != null:
		var toast_layer := toast_ui.get_node_or_null("LeaderNewsLayer") as CanvasLayer
		if toast_layer != null and toast_layer.visible:
			_fail("%s capitulation toast layer still visible" % kind)
			return
	var bar: Node = get_first_node_in_group("top_info_bar")
	if bar != null:
		var hud := bar.find_child("CampaignWarReadout", true, false) as Label
		if hud != null and str(hud.text).find("At war:") >= 0:
			_fail("%s At war readout stale text=%s" % [kind, hud.text])
			return
	if kind == "defeat":
		if keep == null or keep.visible:
			_fail("%s Keep playing should be hidden at 0 provinces" % kind)
			return
		var keep_reason := screen.find_child("KeepPlayingReason", true, false) as Label
		if keep_reason == null or not keep_reason.visible or str(keep_reason.text).find("no remaining provinces") < 0:
			_fail("%s Keep playing reason missing" % kind)
			return
		if str(stats_l.text).find("→ 0") < 0 and str(stats_l.text).find("→0") < 0:
			_fail("%s defeat provinces_end not 0 got %s" % [kind, stats_l.text])
			return
	else:
		if keep == null or not keep.visible:
			_fail("%s Keep playing should stay visible" % kind)
			return
	if kind == "victory":
		if str(reason.text).find("1 nation capitulated") < 0:
			_fail("%s pluralization want 1 nation capitulated got %s" % [kind, reason.text])
			return
		if str(reason.text).find("1 nations") >= 0:
			_fail("%s leftover 1 nations %s" % [kind, reason.text])
			return
	_pass("%s screen %s" % [kind, title.text])
	_shot("end_%s" % kind)


func _click_main_menu() -> void:
	var screen := _end_screen()
	if screen == null or not screen.has_method("handle_pointer"):
		_fail("main menu click has no end screen")
		return
	var btn := screen.find_child("BtnMainMenu", true, false) as Button
	if btn == null:
		_fail("main menu button missing")
		return
	var rect := btn.get_global_rect()
	var pt := rect.position + rect.size * 0.5
	var vp := root.get_viewport()
	if vp != null:
		vp.warp_mouse(pt)
	var inspector := root.get_node_or_null("InspectorChrome")
	var inspector_children := inspector.get_child_count() if inspector != null else -1
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pt
	ev.global_position = pt
	Input.parse_input_event(ev)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	await process_frame
	await process_frame
	var probe := _probe as MapClickProbe
	if probe == null or not probe.consumed or probe.picks != 0 or _map_picks != 0:
		_fail("main menu click fell through consumed=%s picks=%d sentinel=%d" % [str(probe.consumed) if probe != null else "null", probe.picks if probe != null else -1, _map_picks])
		return
	var menu := root.get_node_or_null("MainMenu")
	if menu == null:
		_fail("main menu did not open")
		return
	if inspector != null and inspector.get_child_count() != inspector_children:
		_fail("inspector grew under the end screen")
		return
	_pass("main menu click consumed")


func _end_screen() -> CanvasLayer:
	for n in get_nodes_in_group("campaign_end_screen"):
		if n is CanvasLayer and is_instance_valid(n) and n.visible:
			return n
	return null


func _dismiss_modals() -> void:
	for group_name in ["campaign_peace_sheet", "campaign_end_screen"]:
		for n in get_nodes_in_group(group_name):
			if is_instance_valid(n):
				n.queue_free()
	var menu := root.get_node_or_null("MainMenu")
	if menu != null:
		menu.queue_free()


func _hold_until(mm: Node, sm: Node, tag: String, holder: String) -> void:
	var pids: Array = mm.call("get_provinces_by_owner", tag)
	pids.sort()
	if sm != null and sm.has_method("begin_control_batch"):
		sm.call("begin_control_batch")
	for pid_v in pids:
		var pid := int(pid_v)
		var p: Object = mm.call("get_province", pid)
		if p == null:
			continue
		var owner := str(p.get("owner_tag")).strip_edges().to_upper()
		var ctrl := str(p.get("controller_tag")).strip_edges().to_upper()
		if ctrl == holder:
			continue
		mm.call("update_province_owner", pid, owner, holder, true, true)
		if _cap != null and float(_cap.progress(tag)) + 0.0000001 >= float(_cap.threshold(tag)):
			break
	if sm != null and sm.has_method("end_control_batch"):
		sm.call("end_control_batch")


func _advance(tm: Node) -> void:
	if tm == null:
		return
	tm.paused = false
	tm.call("advance_live_f5_equivalent_days", 1)


func _rank_of(ranked: Array, tag: String) -> int:
	for i in range(ranked.size()):
		if str(ranked[i]) == tag:
			return i + 1
	return ranked.size()


func _border_to(mm: Node, att: String, defender: String) -> int:
	if not mm.has_method("get_provinces_by_owner"):
		return -1
	var owned: Array = mm.call("get_provinces_by_owner", att)
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
		nbrs.sort()
		for nid_v in nbrs:
			var n: Object = mm.call("get_province", int(nid_v))
			if n == null or bool(n.get("is_sea")):
				continue
			if str(n.get("owner_tag")).strip_edges().to_upper() == defender:
				return int(nid_v)
	return -1


class MapClickProbe extends Node:
	var picks := 0
	var consumed := false

	func _input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var tree := get_tree()
		if tree == null:
			return
		for n in tree.get_nodes_in_group("campaign_end_screen"):
			if n == null or not is_instance_valid(n) or not n.visible:
				continue
			if n.has_method("handle_pointer"):
				n.call("handle_pointer", mb)
			get_viewport().set_input_as_handled()
			consumed = true
			return
		picks += 1


func _finish() -> void:
	var ok := _failures == 0
	print("WindowedCampaignLoop1EndScreenGuard: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("WindowedCampaignLoop1EndScreenGuard: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
