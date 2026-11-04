extends SceneTree

## FIRST20-FIX-1 Open fight. The Berlin inspector must not offer a unit at
## Baden-Baden. When the battle is blocked, Start battle is disabled, the
## reason is on the sheet before the click, and the click raises no Error toast.
##
##   tools/run_godot.sh --headless --path . --resolution 1280x800 \
##     -s res://scripts/core/HeadlessOpenFight1Test.gd

const BERLIN := 710300
const POTSDAM := 710304
const BADEN := 710173
const BAS_RHIN := 710739

var _failures: int = 0
var _mr: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _setup():
		_finish()
		return
	await _frames(2)
	_case_berlin_skips_baden()
	await _frames(2)
	await _case_blocked_start_is_disabled()
	await _frames(2)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessOpenFight1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessOpenFight1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] ", msg)


func _frames(n: int) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1


func _setup() -> bool:
	var lm := root.get_node_or_null("LeaderManager")
	var mm := root.get_node_or_null("MapManager")
	if lm == null or mm == null:
		_fail("LeaderManager or MapManager missing")
		return false
	if lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	elif "player_country_tag" in lm:
		lm.set("player_country_tag", "GER")
	if not _load_fixture(mm):
		return false
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = scr.new() as Node
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_mr.add_child(ui)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.enabled = true
	_mr.add_child(cam)
	root.add_child(_mr)
	cam.make_current()
	for pid in [BERLIN, POTSDAM, BADEN, BAS_RHIN]:
		var gp: Object = mm.call("get_province", pid)
		if gp == null:
			_fail("fixture province %d missing after load" % pid)
			return false
		_mr.provinces[pid] = gp
	_register(lm, "f20_baden", "F20 Division Zero", BADEN)
	_register(lm, "f20_berlin", "F20 Berlin Guard", BERLIN)
	_register(lm, "f20_edge", "F20 Edge Unit", POTSDAM)
	_register(lm, "f20_front", "F20 Frontier", BADEN)
	var leui := root.get_node_or_null("LeaderEventUI")
	if leui != null and "force_toast_ui" in leui:
		leui.set("force_toast_ui", true)
	_pass("open-fight fixture ready")
	return true


func _load_fixture(mm: Node) -> bool:
	var adj_scr: Script = load("res://scripts/data/AdjacencySystem.gd") as Script
	var prov_scr: Script = load("res://scripts/data/Province.gd") as Script
	var map_scr: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	if adj_scr == null or prov_scr == null or map_scr == null:
		_fail("map fixture scripts missing")
		return false
	var adj_sys: Object = adj_scr.new()
	if adj_sys.has_method("load_from_dict"):
		adj_sys.call("load_from_dict", {
			"adjacency": {
				str(BERLIN): [POTSDAM],
				str(POTSDAM): [BERLIN],
				str(BADEN): [BAS_RHIN],
				str(BAS_RHIN): [BADEN],
			}
		})
	var rows: Array = [
		{"id": BERLIN, "tag": "GER", "name": "Berlin", "at": Vector2(0, 0)},
		{"id": POTSDAM, "tag": "GER", "name": "Potsdam", "at": Vector2(100, 0)},
		{"id": BADEN, "tag": "GER", "name": "Baden-Baden, Stadtkreis", "at": Vector2(5000, 0)},
		{"id": BAS_RHIN, "tag": "FRA", "name": "Bas-Rhin", "at": Vector2(5100, 0)},
	]
	var provs: Dictionary = {}
	for row in rows:
		var p: Object = prov_scr.new()
		p.set("id", int(row["id"]))
		p.set("owner_tag", str(row["tag"]))
		p.set("controller_tag", str(row["tag"]))
		p.set("name", str(row["name"]))
		p.set("terrain", "plains")
		p.set("is_sea", false)
		p.set("coordinates", row["at"])
		provs[int(row["id"])] = p
		if adj_sys.has_method("register_province"):
			adj_sys.call("register_province", p)
	var countries: Dictionary = {
		"GER": {"tag": "GER", "name": "Germany"},
		"FRA": {"tag": "FRA", "name": "France"},
	}
	var map_data: Object = map_scr.new(provs, {}, adj_sys, countries)
	if not mm.has_method("initialize_from_map_data"):
		_fail("initialize_from_map_data missing")
		return false
	mm.call("initialize_from_map_data", map_data)
	return true


func _register(lm: Node, fid: String, unit_name: String, pid: int) -> void:
	var form_scr: GDScript = load("res://scripts/formations/Formation.gd") as GDScript
	var fo: Object = form_scr.new()
	fo.set("formation_id", fid)
	fo.set("name", unit_name)
	fo.set("country_tag", "GER")
	fo.set("formation_type", "division")
	fo.set("stationed_province_id", pid)
	fo.set("strength", 1.0)
	if lm.has_method("register_formation"):
		lm.call("register_formation", fo)


func _sheet() -> Node:
	var ui := _mr.get_node_or_null("UI")
	if ui == null:
		return null
	return ui.get_node_or_null("OpenFightSheet")


func _sheet_text() -> String:
	var sheet := _sheet()
	if sheet == null:
		return ""
	var bits: PackedStringArray = PackedStringArray()
	for node in sheet.find_children("*", "Label", true, false):
		if node is Label:
			var t := str((node as Label).text).strip_edges()
			if not t.is_empty():
				bits.append(t)
	return "\n".join(bits)


func _case_berlin_skips_baden() -> void:
	print("OPEN_FIGHT case=berlin")
	_mr.set("selected_province_id", BERLIN)
	_mr.set("selected_formation_id", "f20_baden")
	_mr.set("_last_inspector_toast", "")
	_mr.call("_open_fight_from_inspector")
	var text := _sheet_text()
	print("OPEN_FIGHT berlin sheet:\n%s" % text)
	if _sheet() == null:
		_fail("Berlin Open fight did not open a sheet")
		return
	if "Baden-Baden" in text or "F20 Division Zero" in text:
		_fail("Berlin Open fight listed the Baden-Baden unit")
		return
	if "F20 Berlin Guard" not in text:
		_fail("Berlin Open fight did not list the unit in Berlin")
		return
	var units_line := ""
	for line in text.split("\n"):
		if line.begins_with("Units ·"):
			units_line = line
			break
	var guard_at := units_line.find("F20 Berlin Guard")
	var edge_at := units_line.find("F20 Edge Unit")
	if guard_at < 0 or edge_at < 0 or guard_at > edge_at:
		_fail("units are not sorted with Berlin before Potsdam (%s)" % units_line)
		return
	_pass("Berlin Open fight uses a unit in Berlin and skips Baden-Baden")


func _case_blocked_start_is_disabled() -> void:
	print("OPEN_FIGHT case=blocked")
	_mr.set("selected_province_id", BADEN)
	_mr.set("selected_formation_id", "f20_berlin")
	_mr.set("_last_inspector_toast", "")
	_mr.call("_open_fight_from_inspector")
	var sheet := _sheet()
	var text := _sheet_text()
	print("OPEN_FIGHT blocked sheet:\n%s" % text)
	if sheet == null:
		_fail("border Open fight did not open a sheet")
		return
	if "F20 Berlin Guard" in text:
		_fail("border Open fight listed the Berlin unit")
		return
	var btn: Button = sheet.find_child("BtnStartBattle", true, false) as Button
	var warn: Label = sheet.find_child("OpenFightBlock", true, false) as Label
	if btn == null or warn == null:
		_fail("blocked sheet missing Start battle or the warning line")
		return
	if not btn.disabled:
		_fail("Start battle stays enabled while the fight is blocked")
		return
	if warn.text.is_empty() or not ("Not at war" in warn.text):
		_fail("warning line does not say why (%s)" % warn.text)
		return
	if warn.get_theme_font_size("font_size") != 13:
		_fail("warning line is not 13px")
		return
	var warn_col := warn.get_theme_color("font_color")
	if not warn_col.is_equal_approx(Color("#ff6666")):
		_fail("warning line is not #ff6666 (%s)" % str(warn_col))
		return
	if not ("Not at war" in btn.tooltip_text) or not ("justify a war goal first" in btn.tooltip_text):
		_fail("Start battle tooltip missing the block reason (%s)" % btn.tooltip_text)
		return
	if not ("Not at war" in text):
		_fail("block reason is not visible on the sheet before the click")
		return
	var style := btn.get_theme_stylebox("disabled") as StyleBoxFlat
	if style == null or style.get_border_width(SIDE_LEFT) != 1:
		_fail("blocked Start battle border is not 1px")
		return
	if not is_equal_approx(style.border_color.a, 0.4):
		_fail("blocked Start battle border alpha is not 0.4")
		return
	var dim := Color("#9aa8c7")
	var border_rgb := Color(style.border_color.r, style.border_color.g, style.border_color.b, 1.0)
	if not border_rgb.is_equal_approx(dim):
		_fail("blocked Start battle border is not TEXT_DIM")
		return
	var font_col := btn.get_theme_color("font_disabled_color")
	if not font_col.is_equal_approx(dim):
		_fail("blocked Start battle text is not TEXT_DIM (%s)" % str(font_col))
		return
	var pt := btn.get_global_rect().get_center()
	await _click(pt)
	await _frames(2)
	var toast := str(_mr.get("_last_inspector_toast"))
	if toast.begins_with("Start battle") or _error_toast_up():
		_fail("blocked Start battle raised an Error toast (%s)" % toast)
		return
	_pass("blocked Start battle is disabled, reason visible, no Error toast")


func _error_toast_up() -> bool:
	var leui := root.get_node_or_null("LeaderEventUI")
	if leui == null:
		return false
	for node in leui.find_children("*", "Label", true, false):
		if node is Label and str((node as Label).text).strip_edges() == "Error":
			return true
	return false


func _click(pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(pt)
	var motion := InputEventMouseMotion.new()
	motion.position = pt
	motion.global_position = pt
	root.push_input(motion)
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pt
	down.global_position = pt
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pt
	up.global_position = pt
	root.push_input(up)
	await process_frame
