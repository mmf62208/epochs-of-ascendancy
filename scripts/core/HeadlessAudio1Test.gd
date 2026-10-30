extends SceneTree

## AUDIO-1. Manifest files, credits, one missing-key warning, saved mute,
## hover throttle, combat polyphony, end-screen stings. Dummy driver must
## stay free of SCRIPT ERROR.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAudio1Test.gd

const MANIFEST := "res://data/audio_manifest.json"
const CREDITS := "res://audio/CREDITS.md"
const LICENSES := "res://docs/THIRD_PARTY_LICENSES.md"
const LEGACY := ["select", "confirm", "achievement", "error", "map", "pin_focus"]
const REQUIRED := [
	"select", "confirm", "achievement", "error", "map", "pin_focus",
	"ui_click", "ui_hover", "day_tick", "combat_clash", "alert",
	"end_victory_sting", "end_defeat_sting",
]

var _failures: int = 0


func _init() -> void:
	call_deferred("_start")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAudio1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAudio1Test: ", msg)


func _start() -> void:
	await _run()
	_finish()


func _run() -> void:
	print("HeadlessAudio1Test: display=", DisplayServer.get_name())
	var am := _audio()
	if am == null:
		_fail("AudioManager autoload missing")
		return
	_test_manifest_and_credits()
	_test_buses(am)
	_test_missing_key(am)
	_test_hover(am)
	_test_combat(am)
	_test_day_speed(am)
	_test_pin_mute(am)
	_test_end_stings(am)
	_test_settings(am)
	await _test_live_clicks(am)
	await _test_mute_layout(am)
	_test_ready_war()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAudio1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAudio1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _audio() -> Node:
	return root.get_node_or_null("AudioManager")


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read(MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var keys: Variant = (parsed as Dictionary).get("keys", {})
	if typeof(keys) != TYPE_DICTIONARY:
		return {}
	return keys


func _test_manifest_and_credits() -> void:
	var keys := _manifest()
	if keys.is_empty():
		_fail("manifest missing keys")
		return
	var credits := _read(CREDITS)
	var licenses := _read(LICENSES)
	if credits.is_empty():
		_fail("CREDITS.md missing")
		return
	for name in REQUIRED:
		if not keys.has(name):
			_fail("manifest missing %s" % name)
			continue
		var entry: Dictionary = keys[name]
		var path := str(entry.get("path", ""))
		if not FileAccess.file_exists(path):
			_fail("missing file %s" % path)
			continue
		var row := ""
		for line in credits.split("\n"):
			if path in line:
				row = line
				break
		if row.is_empty():
			_fail("credits row missing %s" % path)
			continue
		var license_ok := "CC0" in row or "Original" in row
		var source_ok := "http" in row or "gen_audio1_sfx.py" in row
		if not license_ok or not source_ok:
			_fail("credits license/source %s" % path)
			continue
		if path not in licenses or not ("Original" in licenses or "CC0" in licenses):
			_fail("third-party mirror missing %s" % path)
			continue
		var peak := _wav_peak_db(path)
		if peak > -6.0 + 0.05:
			_fail("peak %.2f dBFS %s" % [peak, path])
			continue
	var clash: Dictionary = keys.get("combat_clash", {})
	if absf(float(clash.get("pitch_jitter", 0.0)) - 0.05) > 0.001:
		_fail("combat pitch_jitter")
		return
	if int(clash.get("max_polyphony", 0)) != 3:
		_fail("combat polyphony manifest")
		return
	for name in LEGACY:
		if not keys.has(name):
			_fail("legacy key %s" % name)
			return
	_pass("manifest, credits, peaks, legacy keys")


func _test_buses(am: Node) -> void:
	var ui := AudioServer.get_bus_index("UI")
	var sfx := AudioServer.get_bus_index("SFX")
	if ui < 0 or sfx < 0:
		_fail("UI/SFX buses missing")
		return
	if AudioServer.get_bus_send(ui) != "Master" or AudioServer.get_bus_send(sfx) != "Master":
		_fail("buses do not send to Master")
		return
	var ui_db := AudioServer.get_bus_volume_db(ui)
	if ui_db < -14.05 or ui_db > -9.95:
		_fail("UI bus %.2f dB outside -14..-10" % ui_db)
		return
	if absf(float(am.call("get_ui_db")) - ui_db) > 0.05:
		_fail("UI slider db does not match the bus")
		return
	_pass("Master → UI %.1f dB, SFX" % ui_db)


func _test_missing_key(am: Node) -> void:
	var key := "audio1_missing_key"
	am.call("play", key)
	am.call("play", key)
	if int(am.call("warning_count", key)) != 1:
		_fail("missing key warning count %s" % str(am.call("warning_count", key)))
		return
	_pass("missing key warns once")


func _test_hover(am: Node) -> void:
	var first := bool(am.call("play", "ui_hover"))
	var second := bool(am.call("play", "ui_hover"))
	if not first or second:
		_fail("hover throttle first=%s second=%s" % [str(first), str(second)])
		return
	OS.delay_msec(90)
	var third := bool(am.call("play", "ui_hover"))
	if not third:
		_fail("hover did not play after 90ms")
		return
	_pass("hover throttled to one per 80ms")


func _test_combat(am: Node) -> void:
	var accepted := 0
	for _i in 5:
		if bool(am.call("play", "combat_clash")):
			accepted += 1
	if accepted != 3:
		_fail("combat accepted %d voices" % accepted)
		return
	if int(am.call("active_voice_count", "combat_clash")) != 3:
		_fail("combat active %s" % str(am.call("active_voice_count", "combat_clash")))
		return
	var pitches: Array = am.call("voice_pitches", "combat_clash")
	if pitches.size() != 3:
		_fail("combat pitches %s" % str(pitches))
		return
	for p in pitches:
		var pitch := float(p)
		if pitch < 0.95 or pitch > 1.05:
			_fail("pitch %.4f outside ±5%%" % pitch)
			return
	_pass("combat polyphony 3 and pitch ±5%")


func _test_day_speed(am: Node) -> void:
	var tm := root.get_node_or_null("TimeManager")
	if tm == null:
		_fail("TimeManager missing")
		return
	var scale := float(tm.get("time_scale"))
	var paused := bool(tm.get("paused"))
	tm.set("paused", false)
	tm.set("time_scale", 1.0)
	if not bool(am.call("day_tick_allowed")):
		_fail("day tick silent at 1x")
		tm.set("time_scale", scale)
		tm.set("paused", paused)
		return
	tm.set("time_scale", 3.0)
	var at3 := bool(am.call("day_tick_allowed"))
	tm.set("time_scale", 4.0)
	var at4 := bool(am.call("day_tick_allowed"))
	tm.set("time_scale", 2.0)
	var at2 := bool(am.call("day_tick_allowed"))
	tm.set("time_scale", scale)
	tm.set("paused", paused)
	if at3 or at4 or at2:
		_fail("day tick audible at 2x/3x/4x")
		return
	_pass("day tick only at 1x")


func _test_pin_mute(am: Node) -> void:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nfunc get_pin_focus_sfx_enabled():\n\treturn false\n"
	if scr.reload() != OK:
		_fail("pin mute probe did not compile")
		return
	var probe := Node.new()
	probe.set_script(scr)
	probe.name = "Audio1PinProbe"
	root.add_child(probe)
	probe.add_to_group("map_renderer")
	var played := bool(am.call("play", "pin_focus"))
	probe.remove_from_group("map_renderer")
	probe.queue_free()
	if played:
		_fail("pin focus ignored prefs mute")
		return
	_pass("pin focus respects prefs mute")


func _test_end_stings(am: Node) -> void:
	var screen: Script = load("res://scripts/ui/CampaignInkEndScreen.gd") as Script
	if screen == null:
		_fail("end screen script missing")
		return
	am.call("clear_request_log")
	var win: Node = screen.call("present_win", "GER", "audio1")
	if win == null:
		_fail("victory screen did not open")
		return
	if _count_req(am, "end_victory_sting") != 1 or _count_req(am, "end_defeat_sting") != 0:
		_fail("victory sting log %s" % str(am.call("request_log")))
		return
	if win.has_method("_dismiss_end_screen"):
		win.call("_dismiss_end_screen")
	am.call("clear_request_log")
	var loss: Node = screen.call("present_loss", "GER", "audio1")
	if loss == null:
		_fail("defeat screen did not open")
		return
	if _count_req(am, "end_defeat_sting") != 1 or _count_req(am, "end_victory_sting") != 0:
		_fail("defeat sting log %s" % str(am.call("request_log")))
		return
	if loss.has_method("_dismiss_end_screen"):
		loss.call("_dismiss_end_screen")
	_pass("end screen requests victory and defeat stings")


func _count_req(am: Node, key: String) -> int:
	var n := 0
	var log: Array = am.call("request_log")
	for item in log:
		if str(item) == key:
			n += 1
	return n


func _test_settings(am: Node) -> void:
	var packed := load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		_fail("Command Center scene missing")
		return
	var menu := packed.instantiate()
	menu.name = "Audio1Menu"
	root.add_child(menu)
	var master := menu.find_child("MasterVolume", true, false) as HSlider
	var mute := menu.find_child("MuteAudio", true, false) as CheckButton
	if master == null or mute == null:
		_fail("CC settings controls missing")
		return
	master.value = -15.0
	mute.button_pressed = true
	if absf(float(am.call("get_master_db")) - (-15.0)) > 0.01 or not bool(am.call("is_muted")):
		_fail("slider did not write AudioManager")
		return
	var cfg_path := ProjectSettings.globalize_path("user://audio.cfg")
	if not FileAccess.file_exists("user://audio.cfg"):
		_fail("user://audio.cfg missing at %s" % cfg_path)
		return
	var snap := FileAccess.get_file_as_bytes("user://audio.cfg")
	am.call("set_master_db", 0.0)
	am.call("set_muted", false)
	var wf := FileAccess.open("user://audio.cfg", FileAccess.WRITE)
	if wf == null:
		_fail("could not restore audio.cfg")
		return
	wf.store_buffer(snap)
	wf.close()
	am.call("load_settings")
	if absf(float(am.call("get_master_db")) - (-15.0)) > 0.01 or not bool(am.call("is_muted")):
		_fail("round trip master=%s muted=%s" % [str(am.call("get_master_db")), str(am.call("is_muted"))])
		return
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx < 0 or not AudioServer.is_bus_mute(master_idx):
		_fail("Master bus not muted after reload")
		return
	if menu.has_method("_force_close"):
		menu.call("_force_close")
	_pass("volume and mute round-trip %s" % cfg_path)


const PLAY_SIZE := Vector2i(1280, 800)


func _set_play_size() -> void:
	DisplayServer.window_set_size(PLAY_SIZE)
	root.size = PLAY_SIZE
	await process_frame
	await process_frame


func _click_count(am: Node) -> int:
	return _count_req(am, "ui_click")


func _pointer(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	return ev


func _twice(am: Node, boot: Node, pos: Vector2) -> String:
	am.call("clear_request_log")
	var first := str(boot.call("handle_live_pointer", _pointer(pos)))
	var second := str(boot.call("handle_live_pointer", _pointer(pos)))
	if _click_count(am) != 1:
		_fail("ui_click count %d at %s (second=%s)" % [_click_count(am), str(pos), second])
	return first


func _button_center(btn: Control) -> Vector2:
	return btn.get_global_rect().get_center()


func _test_live_clicks(am: Node) -> void:
	await _set_play_size()
	var old := root.get_node_or_null("Audio1Menu")
	if old != null:
		old.queue_free()
		await process_frame
	var boot := _spawn_title()
	if boot == null:
		return
	await process_frame
	await process_frame
	var nations: Dictionary = boot.get("_nation_btns")
	var eras: Dictionary = boot.get("_era_btns")
	var fra: Button = nations.get("FRA") as Button
	var era: Button = eras.get(1918) as Button
	if fra == null or era == null:
		_fail("title nation/date buttons missing")
		boot.queue_free()
		return
	if fra.get_global_rect().size.y < 8.0 or era.get_global_rect().size.y < 8.0:
		_fail("title choice buttons have no rect fra=%s era=%s" % [fra.get_global_rect(), era.get_global_rect()])
		boot.queue_free()
		return
	var nation_act := _twice(am, boot, _button_center(fra))
	if nation_act != "choice" or str(boot.get("_tag")) != "FRA":
		_fail("nation click action=%s tag=%s" % [nation_act, str(boot.get("_tag"))])
	else:
		_pass("title nation click plays one ui_click")
	await process_frame
	var date_act := _twice(am, boot, _button_center(era))
	if date_act != "choice" or int(boot.get("_year")) != 1918:
		_fail("date click action=%s year=%s" % [date_act, str(boot.get("_year"))])
	else:
		_pass("title date click plays one ui_click")
	await process_frame
	await _assert_no_double_press(am)
	var title_load := _plant_load_button(boot.get_node("LivingTitleRoot"), Vector2(40, 40))
	await process_frame
	var load_act := _twice(am, boot, _button_center(title_load))
	if load_act != "load" or not bool(boot.get("_closed")):
		_fail("title load action=%s closed=%s" % [load_act, str(boot.get("_closed"))])
	else:
		_pass("title Load click plays one ui_click")
	boot.queue_free()
	await process_frame

	var boot_cc := _spawn_title()
	var menu := _spawn_menu(true)
	if boot_cc == null or menu == null:
		return
	await process_frame
	await process_frame
	var title := menu.find_child("CommandCenterTitle", true, false) as Label
	if title == null or title.text != "Command Center":
		_fail("living Command Center title is %s" % (title.text if title != null else "missing"))
	var header := menu.find_child("CommandCenterHeader", true, false) as Control
	var refresh := menu.find_child("RefreshSaveList", true, false) as Button
	if header == null or refresh == null:
		_fail("header or refresh missing")
	else:
		var header_pos := header.get_global_rect().position + Vector2(40, header.get_global_rect().size.y * 0.5)
		var header_act := _twice(am, boot_cc, header_pos)
		if header_act != "header":
			_fail("header click action=%s pos=%s rect=%s" % [header_act, header_pos, header.get_global_rect()])
		else:
			_pass("Command Center header plays one ui_click")
		await process_frame
		var presses := [0]
		refresh.pressed.connect(func() -> void: presses[0] += 1)
		var refresh_act := _twice(am, boot_cc, _button_center(refresh))
		if refresh_act != "refresh" or int(presses[0]) != 1:
			_fail("refresh action=%s emits=%s" % [refresh_act, str(presses[0])])
		else:
			_pass("Refresh plays one ui_click and emits pressed once")
	await process_frame
	var cc_load := _plant_load_button(menu, Vector2(8, 8))
	await process_frame
	var cc_act := _twice(am, boot_cc, _button_center(cc_load))
	if cc_act != "load":
		_fail("CC load action=%s rect=%s" % [cc_act, cc_load.get_global_rect()])
	elif bool(menu.get("_closing")):
		_fail("missing CC load closed the menu")
	else:
		_pass("Command Center Load plays one ui_click")
	boot_cc.queue_free()
	if is_instance_valid(menu):
		menu.queue_free()
	await process_frame


func _spawn_title() -> Node:
	var scr: Script = load("res://scripts/ui/LivingTitleBoot.gd") as Script
	if scr == null:
		_fail("LivingTitleBoot missing")
		return null
	var boot: Node = scr.new()
	boot.name = "LivingTitleBoot"
	root.add_child(boot)
	return boot


func _spawn_menu(from_title: bool) -> Node:
	var packed := load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		_fail("Command Center scene missing")
		return null
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	if from_title:
		menu.set_meta("eoa_opened_from_living_title", true)
	root.add_child(menu)
	return menu


func _plant_load_button(parent: Node, pos: Vector2) -> Button:
	var btn := Button.new()
	btn.text = "Load"
	btn.set_meta("eoa_load_slot", "audio1_missing_slot")
	btn.position = pos
	btn.size = Vector2(88, 28)
	btn.custom_minimum_size = Vector2(88, 28)
	parent.add_child(btn)
	return btn


func _assert_no_double_press(am: Node) -> void:
	var btn := Button.new()
	btn.name = "Audio1Double"
	btn.text = "Double"
	root.add_child(btn)
	am.call("clear_request_log")
	var first := bool(am.call("activate_button", btn))
	var second := bool(am.call("activate_button", btn))
	var pair := _click_count(am)
	await process_frame
	var emitted := [0]
	btn.pressed.connect(func() -> void: emitted[0] += 1)
	am.call("clear_request_log")
	am.call("play_ui_click", btn)
	btn.pressed.emit()
	var clicks := _click_count(am)
	btn.queue_free()
	if not first or second or pair != 1 or clicks != 1 or int(emitted[0]) != 1:
		_fail("double activate first=%s second=%s pair=%d clicks=%d emit=%d" % [first, second, pair, clicks, emitted[0]])
		return
	_pass("same-frame pressed does not play a second ui_click")


func _test_mute_layout(_am: Node) -> void:
	await _set_play_size()
	var tall := _spawn_menu(true)
	if tall == null:
		return
	await process_frame
	await process_frame
	_assert_mute_inside(tall, "command-center")
	await _shot_mute(tall, "command_center")
	tall.queue_free()
	await process_frame
	var pause := _spawn_menu(false)
	if pause == null:
		return
	await process_frame
	await process_frame
	var paused := pause.find_child("CommandCenterTitle", true, false) as Label
	if paused == null or paused.text != "Paused":
		_fail("pause title is %s" % (paused.text if paused != null else "missing"))
	_assert_mute_inside(pause, "pause")
	await _shot_mute(pause, "pause")
	pause.queue_free()
	await process_frame


func _assert_mute_inside(menu: Node, label: String) -> void:
	var mute := menu.find_child("MuteAudio", true, false) as CheckButton
	if mute == null:
		_fail("%s Mute missing" % label)
		return
	var rect := mute.get_global_rect()
	var view := Rect2(Vector2.ZERO, Vector2(PLAY_SIZE))
	var panel := menu.get_node_or_null("Root/MenuPanel") as Control
	var actions := menu.find_child("GameActions", true, false) as Control
	var scroll := menu.find_child("GameActionsScroll", true, false) as ScrollContainer
	var ok := true
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		_fail("%s Mute size %s" % [label, rect])
		ok = false
	if not view.encloses(rect):
		var vp := Vector2.ZERO
		if root.get_viewport() != null:
			vp = root.get_viewport().get_visible_rect().size
		_fail("%s Mute outside 1280x800 %s vp=%s panel=%s" % [label, rect, vp, panel.get_global_rect() if panel != null else "none"])
		ok = false
	if panel != null and not panel.get_global_rect().grow(1.0).encloses(rect):
		_fail("%s Mute outside panel %s panel=%s" % [label, rect, panel.get_global_rect()])
		ok = false
	if actions != null and not actions.get_global_rect().grow(1.0).encloses(rect):
		_fail("%s Mute outside settings column %s col=%s" % [label, rect, actions.get_global_rect()])
		ok = false
	if not mute.is_visible_in_tree() or mute.disabled:
		_fail("%s Mute not reachable visible=%s disabled=%s" % [label, mute.is_visible_in_tree(), mute.disabled])
		ok = false
	if scroll != null and scroll.scroll_vertical != 0:
		_fail("%s settings scrolled %d" % [label, scroll.scroll_vertical])
		ok = false
	if ok:
		_pass("%s Mute inside 1280x800 %s" % [label, rect])


func _shot_mute(menu: Node, tag: String) -> void:
	var dir := OS.get_environment("EOA_AUDIO1_MUTE_SHOT").strip_edges()
	if dir.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	if vp == null:
		print("  [INFO] HeadlessAudio1Test: no viewport for ", tag)
		return
	var tex := vp.get_texture()
	if tex == null:
		print("  [INFO] HeadlessAudio1Test: no texture for ", tag)
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		print("  [INFO] HeadlessAudio1Test: empty shot for ", tag)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var full := dir.path_join("mute_%s_1280x800.png" % tag)
	var err := img.save_png(full)
	var mute := menu.find_child("MuteAudio", true, false) as Control
	if mute != null:
		var r := mute.get_global_rect().grow(36.0)
		var ri := Rect2i(int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y))
		ri = ri.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if ri.size.x > 0 and ri.size.y > 0:
			img.get_region(ri).save_png(dir.path_join("mute_%s_crop.png" % tag))
	print("  [INFO] HeadlessAudio1Test: shot %s err=%s %s" % [tag, err, full])


func _script_has(scr: Script, method_name: String) -> bool:
	if scr == null:
		return false
	for m in scr.get_script_method_list():
		if str(m.get("name", "")) == method_name:
			return true
	return false


func _test_ready_war() -> void:
	# Load by path so this harness does not compile the domain before autoloads exist.
	var hooks: Script = load("res://scripts/core/Audio1PlayHooks.gd") as Script
	var domain: Script = load("res://scripts/core/WarStateDomain.gd") as Script
	if hooks == null or not _script_has(hooks, "maybe_run"):
		_fail("Audio1PlayHooks missing")
		return
	if domain == null or not _script_has(domain, "grant_ready_player_justify"):
		_fail("WarStateDomain did not compile")
		return
	OS.set_environment("EOA_AUDIO1_READY_WAR", "")
	var off: Dictionary = hooks.call("maybe_run")
	if bool(off.get("ran", true)) or str(off.get("reason", "")) != "off":
		_fail("hook ran while off %s" % str(off))
		return
	if bool(domain.call("player_has_justify", "FRA")):
		_fail("off hook wrote a FRA justify")
		return
	var tm := root.get_node_or_null("TimeManager")
	if tm == null:
		_fail("TimeManager missing")
		return
	var days := int(tm.get("total_days_elapsed"))
	OS.set_environment("EOA_AUDIO1_READY_WAR", "1")
	var on: Dictionary = hooks.call("maybe_run")
	OS.set_environment("EOA_AUDIO1_READY_WAR", "")
	if not bool(on.get("ran", false)):
		_fail("hook did not run when enabled %s" % str(on))
		domain.call("reset_for_test")
		return
	# -s harness has no board, so the default Maginot lookup has no owner.
	# The explicit defender is the same writer Play uses once the map is up.
	var granted: Dictionary = on
	if not bool(on.get("ok", false)):
		var raw: Variant = domain.call("grant_ready_player_justify", "FRA")
		if raw is Dictionary:
			granted = raw
	if not bool(granted.get("ok", false)):
		_fail("grant failed %s" % str(granted))
		domain.call("reset_for_test")
		return
	var defender := str(granted.get("defender", ""))
	if not bool(domain.call("player_justify_is_ready_for", defender)):
		_fail("justify not ready for %s" % defender)
	if int(tm.get("total_days_elapsed")) != days:
		_fail("hook moved the clock %d -> %d" % [days, int(tm.get("total_days_elapsed"))])
	domain.call("reset_for_test")
	if bool(domain.call("player_has_justify", defender)):
		_fail("reset left the justify")
		return
	_pass("ready-war hook stays off; grant does not move the clock")


func _wav_peak_db(path: String) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 99.0
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var data_at := -1
	for i in range(bytes.size() - 8):
		if bytes[i] == 0x64 and bytes[i + 1] == 0x61 and bytes[i + 2] == 0x74 and bytes[i + 3] == 0x61:
			data_at = i
			break
	if data_at < 0:
		return 99.0
	var size := int(bytes.decode_u32(data_at + 4))
	var start := data_at + 8
	var mx := 0
	var count := int(size / 2)
	for s in count:
		var sample := int(bytes.decode_s16(start + s * 2))
		var mag := absi(sample)
		if mag > mx:
			mx = mag
	if mx <= 0:
		return -120.0
	return 20.0 * log(float(mx) / 32767.0) / log(10.0)
