extends SceneTree

## First-session readability without WorldMap.tscn / 3520.
## Tip is pass-through and one-shot. Selected GER land shows Fill%/TOE.
## Empty land outside the hit disk does not count as on-chip.
## Tip dismiss and unit-card Close must not lock or jump the camera.
## Headless is NOT live Play. Never set EOA_SKIP_TITLE.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFirstSessionReadabilityTest.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessFirstSessionReadabilityTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessFirstSessionReadabilityTest: ", msg)


func _run() -> void:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		_finish()
		return
	var mr: Node = mr_script.new()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	mr.add_child(ui)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.position = Vector2(4200, 1000)
	cam.zoom = Vector2(0.78, 0.78)
	mr.add_child(cam)
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	mr.add_child(container)
	if "container" in mr:
		mr.container = container
	root.add_child(mr)
	cam.make_current()
	await process_frame
	cam.position = Vector2(4200, 1000)
	cam.zoom = Vector2(0.78, 0.78)
	var cam0: Vector2 = cam.position
	var locked0: bool = bool(mr.get("_close_camera_locked"))

	mr.call("show_first_session_action_tip")
	mr.call("show_first_session_action_tip")
	var strip: Node = ui.get_node_or_null("FirstSessionTipStrip")
	if strip == null or not (strip is Control):
		_fail("tip strip missing")
		_finish()
		return
	var strip_c: Control = strip as Control
	if strip_c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("tip strip mouse_filter=%d want IGNORE" % strip_c.mouse_filter)
	else:
		_pass("tip strip ignores mouse")
	var tip_lab: Label = strip.find_child("TipText", true, false) as Label
	if tip_lab == null or tip_lab.text != "Select a unit, then March or Open card.":
		_fail("tip text=%s" % (tip_lab.text if tip_lab != null else "missing"))
	elif tip_lab.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("tip label blocks mouse")
	else:
		_pass("tip text once")
	var dismiss: Button = strip.find_child("TipDismiss", true, false) as Button
	if dismiss == null or dismiss.text != "×" or dismiss.name.begins_with("Close") or dismiss.name == "BtnClose":
		_fail("dismiss control is not TipDismiss ×")
	else:
		_pass("dismiss is TipDismiss")
	if cam.position.distance_to(cam0) > 0.01 or bool(mr.get("_close_camera_locked")) != locked0:
		_fail("showing the tip moved the camera")
	mr.call("dismiss_first_session_action_tip")
	if ui.get_node_or_null("FirstSessionTipStrip") != null:
		_fail("tip still up after dismiss")
	elif cam.position.distance_to(cam0) > 0.01 or bool(mr.get("_close_camera_locked")):
		_fail("tip dismiss locked or jumped the camera")
	else:
		_pass("tip dismiss leaves the camera")

	var fscr: Script = load("res://scripts/formations/Formation.gd") as Script
	var fo: Object = fscr.new() if fscr != null else null
	if fo == null:
		_fail("Formation create failed")
		_finish()
		return
	fo.set("formation_id", "fs_ger_land")
	fo.set("country_tag", "GER")
	fo.set("formation_type", "division")
	fo.set("name", "Karlsruhe Garrison")
	fo.set("stationed_province_id", 710173)
	fo.set("strength", 0.86)
	fo.set("organization", 1.0)
	fo.set_meta("toe_fill", 0.72)
	var lm: Node = root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	if lm != null and "formations" in lm:
		lm.formations["fs_ger_land"] = fo
	mr.set("selected_formation_id", "fs_ger_land")
	var host := Node2D.new()
	host.name = "Province_710173"
	host.position = Vector2(1000, 1000)
	container.add_child(host)
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_710173"
	icon.position = Vector2(1000, 1000)
	host.add_child(icon)
	icon.global_position = Vector2(1000, 1000)
	if "province_nodes" in mr:
		mr.province_nodes[710173] = host
	icon.set_meta("formation", fo)
	icon.set_meta("formation_id", "fs_ger_land")
	icon.set_meta("province_id", 710173)
	var plate := Polygon2D.new()
	plate.name = "NationPlate"
	plate.polygon = PackedVector2Array([
		Vector2(-22, -20), Vector2(22, -20), Vector2(22, 20), Vector2(-22, 20)
	])
	icon.add_child(plate)
	if "_demo_unit_icon_pids" in mr:
		mr._demo_unit_icon_pids = [710173]
	var before: float = float(mr.call("_unit_counter_aabb_hit_screen", icon))
	mr.call("_refresh_selected_unit_chip")
	var readout: Node = icon.get_node_or_null("FillToeReadout")
	if readout == null:
		_fail("selected GER land has no FillToeReadout")
	else:
		var fs: int = int(readout.get("font_size"))
		var scale_z: float = float(mr.call("_unit_counter_scale_for_zoom", 0.78))
		if fs < 14:
			_fail("chip font_size=%d" % fs)
		elif fs * scale_z < 24.0:
			_fail("chip screen px %.1f at home zoom" % (fs * scale_z))
		else:
			_pass("chip Fill/TOE font %d × scale %.2f" % [fs, scale_z])
		if str(readout.get("text")).find("Fill") < 0 or str(readout.get("text")).find("TOE") < 0:
			_fail("chip text=%s" % str(readout.get("text")))
		else:
			_pass("chip text has Fill and TOE")
	var after: float = float(mr.call("_unit_counter_aabb_hit_screen", icon))
	if after > before + 1.0:
		_fail("FillToeReadout grew hit screen %.1f -> %.1f" % [before, after])
	else:
		_pass("FillToeReadout excluded from hit disk")

	mr.call("_show_unit_detail_popup", fo)
	await process_frame
	var card: Node = ui.get_node_or_null("UnitDetailPopup")
	if card == null:
		_fail("unit card missing")
		_finish()
		return
	var close_btn: Button = card.find_child("BtnClose", true, false) as Button
	var toe: Label = card.find_child("ToeLabel", true, false) as Label
	var fill: Label = null
	for ch in card.find_children("*", "Label", true, false):
		var lab: Label = ch as Label
		if lab != null and lab != toe and str(lab.text).begins_with("Fill"):
			fill = lab
			break
	if fill == null or toe == null or close_btn == null:
		_fail("card missing Fill, TOE, or Close")
	else:
		var fill_px: int = int(fill.get_theme_font_size("font_size"))
		var toe_px: int = int(toe.get_theme_font_size("font_size"))
		if fill_px < 16 or toe_px < 16:
			_fail("card fonts fill=%d toe=%d" % [fill_px, toe_px])
		elif not str(fill.text).begins_with("Fill") or not str(toe.text).begins_with("TOE"):
			_fail("card lines fill=%s toe=%s" % [fill.text, toe.text])
		elif fill.get_parent() == close_btn.get_parent():
			_fail("Fill shares the Close row")
		elif close_btn.custom_minimum_size.x < 76.0:
			_fail("Close min x=%.0f" % close_btn.custom_minimum_size.x)
		else:
			_pass("card Fill/TOE font %d/%d below Close" % [fill_px, toe_px])
	var cam1: Vector2 = cam.position
	mr.call("_dismiss_unit_card_restore_province")
	if cam.position.distance_to(cam1) > 0.01 or bool(mr.get("_close_camera_locked")):
		_fail("unit-card Close jumped or locked the camera")
	else:
		_pass("unit-card Close leaves the camera")

	cam.zoom = Vector2(0.78, 0.78)
	var near: bool = bool(mr.call("_empty_land_spill_is_on_chip", Vector2(1000, 1010), fo))
	var far: bool = bool(mr.call("_empty_land_spill_is_on_chip", Vector2(1000, 1400), fo))
	if not near:
		_fail("click 10u from the chip was treated as distant")
	elif far:
		_fail("click 400u from the chip still counts as on-chip")
	else:
		_pass("empty land outside the hit disk does not open")
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessFirstSessionReadabilityTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessFirstSessionReadabilityTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
