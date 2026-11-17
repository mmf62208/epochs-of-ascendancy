extends SceneTree

## VP-READOUT-1. Command Center Victory Paths heading, day-1 0-state lines,
## and no horizontal clip at 1280×720 / 1280×800. Flag-off tree unchanged.
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     --resolution 1280x800 -s res://scripts/core/HeadlessVpReadout1Test.gd
##
## Does not load the world map. Headless is NOT live Play.

const PLAY_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1280, 800)]
const ENABLED_TITLES: PackedStringArray = [
	"Conquest",
	"Atomic",
	"Arsenal of the World",
	"Score",
]
const FLUSH_FRAMES := 8

var _failures: int = 0
var _vp: GDScript
var _toggles: GDScript


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessVpReadout1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessVpReadout1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessVpReadout1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessVpReadout1Test: ", msg)


func _run() -> void:
	_vp = load("res://scripts/core/VictoryPathsDomain.gd") as GDScript
	_toggles = load("res://scripts/core/SystemTogglesDomain.gd") as GDScript
	if _vp == null:
		_fail("VictoryPathsDomain missing")
		return
	_boot_ger_1936(0)
	await _test_flag_off()
	_on()
	await _test_day("day 0", 0)
	await _test_day("day 7", 7)
	_off()


func _on() -> void:
	OS.set_environment("EOA_VICTORY_PATHS", "1")
	_reset_domains()


func _off() -> void:
	OS.set_environment("EOA_VICTORY_PATHS", "0")
	_reset_domains()


func _reset_domains() -> void:
	if _toggles != null and _toggles.has_method("reset_for_test"):
		_toggles.call("reset_for_test")
	if _vp != null and _vp.has_method("reset_for_test"):
		_vp.call("reset_for_test")


func _boot_ger_1936(elapsed: int) -> void:
	var lm := root.get_node_or_null("LeaderManager")
	var tm := root.get_node_or_null("TimeManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	if tm == null:
		return
	tm.scenario_start_year = 1936
	tm.current_year = 1936
	tm.current_month = 1
	var day := 1 + elapsed
	tm.current_day = day
	if "total_days_elapsed" in tm:
		tm.total_days_elapsed = elapsed
	if "paused" in tm:
		tm.paused = true


func _test_flag_off() -> void:
	_off()
	await _set_size(Vector2i(1280, 800))
	var menu := _make_menu()
	if menu == null:
		_fail("flag off Command Center failed to build")
		return
	await _flush()
	var heading := menu.find_child("VictoryPathsHeading", true, false)
	var readout := menu.find_child("VictoryPathsReadout", true, false)
	if heading != null:
		_fail("flag off: VictoryPathsHeading exists")
	elif readout != null:
		_fail("flag off: VictoryPathsReadout exists")
	else:
		_pass("flag off: neither heading nor readout exists")
	_free_menu(menu)


func _test_day(label: String, elapsed: int) -> void:
	_on()
	_boot_ger_1936(elapsed)
	for sz in PLAY_SIZES:
		await _assert_readout(label, elapsed, sz)


func _assert_readout(label: String, elapsed: int, sz: Vector2i) -> void:
	await _set_size(sz)
	var menu := _make_menu()
	if menu == null:
		_fail("%s %dx%d Command Center failed to build" % [label, sz.x, sz.y])
		return
	await _flush()
	if menu.has_method("_center_panel"):
		menu.call("_center_panel")
	await _flush()
	var heading := menu.find_child("VictoryPathsHeading", true, false) as Label
	if heading == null:
		_fail("%s: VictoryPathsHeading missing" % label)
	elif str(heading.text).strip_edges() != "Victory Paths":
		_fail("%s: VictoryPathsHeading text '%s' want 'Victory Paths'" % [label, heading.text])
	else:
		_pass("%s: VictoryPathsHeading='Victory Paths'" % label)
	var readout := menu.find_child("VictoryPathsReadout", true, false) as Label
	if readout == null:
		_fail("%s: VictoryPathsReadout missing" % label)
		_free_menu(menu)
		return
	var shown := str(readout.text)
	print("HeadlessVpReadout1Test: %s %dx%d text=%s" % [label, sz.x, sz.y, shown.replace("\n", " | ")])
	var lines := shown.split("\n")
	for title in ENABLED_TITLES:
		var hit := _line_for_title(lines, title)
		if hit.is_empty():
			_fail("%s: readout missing path '%s' in '%s'" % [label, title, shown.replace("\n", " | ")])
			continue
		if not _has_digit(hit):
			_fail("%s: path '%s' has no concrete value in '%s'" % [label, title, hit])
		else:
			_pass("%s: path '%s' = '%s'" % [label, title, hit])
	var column := _column_for(readout)
	if column == null:
		_fail("%s %dx%d: parent column missing" % [label, sz.x, sz.y])
	else:
		var panel := menu.find_child("MenuPanel", true, false) as Control
		_assert_fits(label, sz, readout, column, panel, shown)
	if sz.x == 1280 and sz.y == 800 and elapsed == 0:
		await _shot(menu, readout)
	_free_menu(menu)


func _line_for_title(lines: PackedStringArray, title: String) -> String:
	for raw in lines:
		var line := str(raw).strip_edges()
		if line.find(title) >= 0:
			return line
	return ""


func _has_digit(text: String) -> bool:
	for i in text.length():
		var ch := text.unicode_at(i)
		if ch >= 48 and ch <= 57:
			return true
	return false


func _column_for(readout: Control) -> Control:
	var n: Node = readout.get_parent()
	while n != null:
		if n is Control and str(n.name) == "GameActions":
			return n as Control
		n = n.get_parent()
	n = readout.get_parent()
	while n != null:
		if n is VBoxContainer:
			return n as Control
		n = n.get_parent()
	return readout.get_parent() as Control


func _assert_fits(label: String, sz: Vector2i, readout: Label, column: Control, panel: Control, shown: String) -> void:
	var col := column.get_global_rect()
	var lab := readout.get_global_rect()
	if lab.position.x + 0.05 < col.position.x:
		_fail(
			"%s %dx%d: readout x=%.1f < column x=%.1f"
			% [label, sz.x, sz.y, lab.position.x, col.position.x]
		)
	## menu_panel_frame_512 texture_margin is 48px. Content margin is 40, so a
	## left-aligned "Conquest" sits under the chrome and the C is clipped.
	const FRAME_INSET := 48.0
	if panel != null:
		var frame_inner := panel.get_global_rect().position.x + FRAME_INSET
		var glyph_x := lab.position.x
		var xf := readout.get_global_transform()
		if shown.length() > 0:
			var bounds := readout.get_character_bounds(0)
			if bounds.size.x > 0.01:
				glyph_x = (xf * bounds.position).x
		if glyph_x + 0.05 < frame_inner:
			_fail(
				"%s %dx%d: first glyph clipped under panel frame x=%.1f frame_inner=%.1f"
				% [label, sz.x, sz.y, glyph_x, frame_inner]
			)
	var font := readout.get_theme_font("font")
	var fsize := readout.get_theme_font_size("font_size")
	if fsize <= 0:
		fsize = 14
	var widest := 0.0
	var clip_fail := false
	for raw in shown.split("\n"):
		var line := str(raw).strip_edges()
		if line.is_empty():
			continue
		var tw := 0.0
		if font != null:
			tw = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		else:
			tw = float(line.length()) * 8.0
		widest = maxf(widest, tw)
		if tw > col.size.x + 0.5:
			clip_fail = true
			_fail(
				"%s %dx%d: line '%s' width %.1f > column width %.1f"
				% [label, sz.x, sz.y, line, tw, col.size.x]
			)
	if lab.size.x > col.size.x + 0.5:
		clip_fail = true
		_fail(
			"%s %dx%d: readout width %.1f > column width %.1f"
			% [label, sz.x, sz.y, lab.size.x, col.size.x]
		)
	if not clip_fail and lab.position.x + 0.05 >= col.position.x and widest <= col.size.x + 0.5:
		if panel == null or lab.position.x + 0.05 >= panel.get_global_rect().position.x + FRAME_INSET:
			_pass(
				"%s %dx%d: lines fit column x=%.1f w=%.1f widest=%.1f"
				% [label, sz.x, sz.y, col.position.x, col.size.x, widest]
			)


func _shot(menu: Node, readout: Control) -> void:
	var dir := OS.get_environment("EOA_VP_READOUT_SHOT").strip_edges()
	if dir.is_empty():
		return
	var scroll := menu.find_child("GameActionsScroll", true, false) as ScrollContainer
	var session := menu.find_child("SessionPin", true, false) as Control
	var settings := menu.find_child("SettingsPin", true, false) as Control
	if session != null:
		session.visible = false
	if settings != null:
		settings.visible = false
	if menu.has_method("_center_panel"):
		menu.call("_center_panel")
	await _flush()
	if scroll != null and readout != null:
		scroll.ensure_control_visible(readout)
	await _flush()
	var vp := root.get_viewport()
	if vp == null:
		print("  [INFO] HeadlessVpReadout1Test: no viewport for shot")
		return
	var tex := vp.get_texture()
	if tex == null:
		print("  [INFO] HeadlessVpReadout1Test: no texture for shot")
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		print("  [INFO] HeadlessVpReadout1Test: empty shot")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var full := dir.path_join("vp_readout_1280x800.png")
	var err := img.save_png(full)
	var heading_n := menu.find_child("VictoryPathsHeading", true, false) as Control
	var column := _column_for(readout)
	var r := readout.get_global_rect()
	if heading_n != null:
		r = heading_n.get_global_rect().merge(readout.get_global_rect())
	if column != null:
		var colr := column.get_global_rect()
		r.position.x = colr.position.x
		r.size.x = colr.size.x
	r = r.grow(16.0)
	var ri := Rect2i(int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y))
	ri = ri.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if ri.size.x > 0 and ri.size.y > 0:
		img.get_region(ri).save_png(dir.path_join("vp_readout_column_1280x800.png"))
	print("  [INFO] HeadlessVpReadout1Test: shot err=%s %s" % [err, full])


func _set_size(sz: Vector2i) -> void:
	DisplayServer.window_set_size(sz)
	if root is Window:
		(root as Window).size = sz
	var vp := root.get_viewport()
	if vp != null:
		vp.size = sz
	await process_frame
	await process_frame


func _flush() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _make_menu() -> Node:
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	menu.set_meta("eoa_opened_from_living_title", true)
	root.add_child(menu)
	return menu


func _free_menu(menu: Node) -> void:
	if menu == null:
		return
	if is_instance_valid(menu):
		menu.free()
