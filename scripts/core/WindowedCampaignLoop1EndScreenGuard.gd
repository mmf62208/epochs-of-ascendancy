extends SceneTree

## Windowed CL1 evidence on a private Xvfb. Not live Play.
## Chrome shots (war HUD, declare button) always run.
## End-screen shots run when EOA_CL1_END_SHOTS=1 (CL1c).

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _chrome: GDScript


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


func _finish() -> void:
	var ok := _failures == 0
	print("WindowedCampaignLoop1EndScreenGuard: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("WindowedCampaignLoop1EndScreenGuard: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
