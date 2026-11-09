extends SceneTree

## FIRST20-UX-WAR (a): Justify on any foreign land province (not border-only),
## Diplomacy lists POL + land neighbours with the same Justify action, and
## disabled Attack names the next step.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessFirst20UxWarJustifyVisibilityTest.gd

const PLAY_SIZE := Vector2i(1280, 800)
const FLUSH_FRAMES := 6
const SRC_CHROME := "res://scripts/ui/CampaignWarChrome.gd"
const SRC_DIPLO := "res://scripts/ui/DiplomacyView.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _chrome: GDScript
var _ui: CanvasLayer
var _host_interior: Panel
var _host_border: Panel
var _pol_border := -1
var _pol_interior := -1
var _fra_border := -1


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessFirst20UxWarJustifyVisibilityTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFirst20UxWarJustifyVisibilityTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFirst20UxWarJustifyVisibilityTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFirst20UxWarJustifyVisibilityTest: ", msg)


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


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


func _run() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	if root != null:
		root.size = PLAY_SIZE
	_test_source_needles()
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	var sp := get_root().get_node_or_null("SessionPlayers")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_chrome = load("res://scripts/ui/CampaignWarChrome.gd") as GDScript
	if mm == null or _boot == null or _war == null or _chrome == null:
		_fail("autoloads missing")
		return
	if not _boot.boot(mm, sm, "GER"):
		_fail("boot failed")
		return
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "GER")
	_war.reset_for_test()
	_war.clear_rule_overrides()
	_pol_border = _border_to(mm, "GER", "POL")
	_fra_border = _border_to(mm, "GER", "FRA")
	_pol_interior = _interior_of(mm, "POL", "GER")
	if _pol_border <= 0 or _pol_interior <= 0 or _fra_border <= 0:
		_fail("missing POL border=%d interior=%d FRA=%d" % [_pol_border, _pol_interior, _fra_border])
		return
	if bool(_war.borders_tag(_pol_interior, "GER")):
		_fail("interior POL %d still borders GER" % _pol_interior)
		return
	_pass("POL border %d interior %d FRA %d" % [_pol_border, _pol_interior, _fra_border])
	if not _assert_inspector_justify(mm):
		_cleanup()
		return
	if not _assert_attack_hint(mm):
		_cleanup()
		return
	await _assert_diplomacy_justify()
	_cleanup()


func _test_source_needles() -> void:
	var chrome := _read(SRC_CHROME)
	var mount_fn := _slice_func(chrome, "mount")
	if mount_fn.is_empty():
		_fail("CampaignWarChrome.mount missing")
		return
	if "borders_tag" in mount_fn:
		_fail("inspector Justify must not gate visibility on borders_tag")
		return
	var dip := _read(SRC_DIPLO)
	if "POL" not in dip or "BtnJustifyWar" not in dip:
		_fail("Diplomacy must list POL and mount BtnJustifyWar")
		return
	var ren := _read(SRC_REN)
	if "_attack_not_at_war_hint" not in ren:
		_fail("Attack disabled path must use _attack_not_at_war_hint")
		return
	_pass("source needles: no border-only Justify gate; Diplomacy POL; Attack hint")


func _assert_inspector_justify(mm: Node) -> bool:
	_ui = CanvasLayer.new()
	_ui.name = "F20UxWarJustifyUI"
	_ui.layer = 110
	root.add_child(_ui)
	_host_interior = _make_host("InspectorPolInterior", Vector2(40, 80))
	_host_border = _make_host("InspectorPolBorder", Vector2(40, 280))
	_ui.add_child(_host_interior)
	_ui.add_child(_host_border)
	var interior_p: Object = mm.call("get_province", _pol_interior)
	var border_p: Object = mm.call("get_province", _pol_border)
	_chrome.mount(_host_interior, interior_p)
	_chrome.mount(_host_border, border_p)
	var interior_btn := _host_interior.get_node_or_null("BtnDeclareWar") as Button
	var border_btn := _host_border.get_node_or_null("BtnDeclareWar") as Button
	if interior_btn == null or not interior_btn.visible or interior_btn.disabled:
		_fail("interior POL Justify missing/disabled text=%s" % (str(interior_btn.text) if interior_btn != null else "null"))
		return false
	if str(interior_btn.text).find("Justify war on") < 0 or str(interior_btn.text).find("Poland") < 0:
		_fail("interior POL want Justify war on Poland got %s" % interior_btn.text)
		return false
	if str(interior_btn.tooltip_text).find("Border not required") < 0:
		_fail("interior POL tooltip missing border-not-required hint (%s)" % interior_btn.tooltip_text)
		return false
	if border_btn == null or not border_btn.visible:
		_fail("border POL Justify missing")
		return false
	_pass("inspector Justify on interior POL %d and border %d" % [_pol_interior, _pol_border])
	interior_btn.pressed.emit()
	if not bool(_war.player_has_justify("POL")):
		_fail("interior POL Justify press did not begin justify")
		return false
	_pass("interior POL Justify press began justification")
	return true


func _assert_attack_hint(mm: Node) -> bool:
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		_fail("MapRenderer.gd missing")
		return false
	var mr: Node = scr.new() as Node
	var panel := Panel.new()
	panel.name = "InfoPanel"
	panel.visible = true
	panel.size = Vector2(440, 80)
	mr.set("info_panel", panel)
	root.add_child(mr)
	root.add_child(panel)
	var pol_p: Object = mm.call("get_province", _pol_interior)
	if pol_p == null:
		_fail("interior POL province missing for Attack hint")
		return false
	mr.call("_update_attack_button", pol_p)
	var attack := panel.get_node_or_null("BtnAttackProvince") as Button
	if attack == null or not attack.visible:
		_fail("Attack button missing on foreign POL inspector")
		return false
	if not attack.disabled:
		_fail("Attack should be disabled while not at war")
		return false
	var tip := str(attack.tooltip_text) + " " + str(attack.text)
	if tip.find("justify") < 0 and tip.find("Justify") < 0:
		_fail("disabled Attack hint missing justify next-step (%s / %s)" % [attack.text, attack.tooltip_text])
		return false
	_pass("disabled Attack names Justify first (%s)" % attack.text)
	mr.queue_free()
	panel.queue_free()
	return true


func _assert_diplomacy_justify() -> void:
	if not ResourceLoader.exists("res://scenes/ui/DiplomacyView.tscn"):
		_fail("DiplomacyView.tscn missing")
		return
	var packed := load("res://scenes/ui/DiplomacyView.tscn") as PackedScene
	if packed == null:
		_fail("DiplomacyView.tscn load failed")
		return
	var view: Node = packed.instantiate()
	view.name = "DiplomacyView"
	if view.has_method("focus_country"):
		view.call("focus_country", "POL")
	root.add_child(view)
	await _flush()
	if not view.has_method("listed_country_tags"):
		_fail("Diplomacy listed_country_tags missing")
		view.queue_free()
		return
	var listed: Array = view.call("listed_country_tags")
	var listed_s := PackedStringArray()
	for tag_v in listed:
		listed_s.append(str(tag_v))
	if not listed_s.has("POL"):
		_fail("Diplomacy list missing POL %s" % str(listed))
		view.queue_free()
		return
	var neighbours: Array = _war.land_neighbours("GER")
	for n in neighbours:
		var nt := str(n)
		if nt == "GER":
			continue
		if not listed_s.has(nt):
			_fail("Diplomacy list missing neighbour %s" % nt)
			view.queue_free()
			return
	_pass("Diplomacy lists POL and GER land neighbours")
	var btn := view.find_child("BtnJustifyWar", true, false) as Button
	if btn == null or not btn.visible:
		_fail("Diplomacy BtnJustifyWar missing/hidden")
		view.queue_free()
		return
	if str(btn.text).find("Justify") < 0 and str(btn.text).find("Declare") < 0:
		_fail("Diplomacy Justify/Declare text got %s" % btn.text)
		view.queue_free()
		return
	_war.reset_for_test()
	view.call("_sync_justify_button")
	await _flush()
	if view.has_method("_on_justify_war_pressed"):
		view.call("_on_justify_war_pressed")
	if not bool(_war.player_has_justify("POL")):
		_fail("Diplomacy Justify press did not begin POL justify")
		view.queue_free()
		return
	_pass("Diplomacy Justify on POL uses the same domain call")
	view.queue_free()


func _make_host(host_name: String, pos: Vector2) -> Panel:
	var host := Panel.new()
	host.name = host_name
	host.position = pos
	host.size = Vector2(320, 160)
	host.custom_minimum_size = Vector2(320, 160)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	return host


func _interior_of(mm: Node, owner: String, not_border: String) -> int:
	if mm == null or not mm.has_method("get_provinces_by_owner"):
		return -1
	var owned: Array = mm.call("get_provinces_by_owner", owner)
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		var p: Object = mm.call("get_province", pid)
		if p == null or bool(p.get("is_sea")):
			continue
		if _war != null and bool(_war.borders_tag(pid, not_border)):
			continue
		return pid
	return -1


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


func _cleanup() -> void:
	if _host_interior != null and is_instance_valid(_host_interior):
		_host_interior.queue_free()
	if _host_border != null and is_instance_valid(_host_border):
		_host_border.queue_free()
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
