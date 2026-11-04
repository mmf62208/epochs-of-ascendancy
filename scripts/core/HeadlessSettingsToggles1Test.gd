extends SceneTree

## SETTINGS-TOGGLES-1. Registry, env-over-save-over-default, campaign save,
## a pre-DS-6 save, and each toggle off (no tick, readout, or save key) or on.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessSettingsToggles1Test.gd

const PID := 710739

var _failures: int = 0
var _toggles: GDScript
var _sj: GDScript
var _vp: GDScript


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	_finish()


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSettingsToggles1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSettingsToggles1Test: ", msg)


func _run() -> void:
	var gd := root.get_node_or_null("GameData")
	_toggles = load("res://scripts/core/SystemTogglesDomain.gd") as GDScript
	_sj = load("res://scripts/core/StabilityJusticeDomain.gd") as GDScript
	_vp = load("res://scripts/core/VictoryPathsDomain.gd") as GDScript
	if gd == null or _toggles == null or _sj == null or _vp == null:
		_fail("GameData or toggle domains missing")
		return
	_quiet()
	_test_registry()
	_test_modder_entry()
	_quiet()
	_test_precedence(gd)
	_quiet()
	_test_save_roundtrip(gd)
	_quiet()
	_test_pre_ds6(gd)
	_quiet()
	_test_each_off(gd)
	_quiet()
	_test_each_on(gd)
	_quiet()
	_test_setup_ui()
	_quiet()
	await _test_setup_input(gd)


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessSettingsToggles1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSettingsToggles1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _quiet() -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "")
	OS.set_environment("EOA_VICTORY_PATHS", "")
	OS.set_environment("EOA_SETTINGS_TOGGLES_PROBE", "")
	if _toggles != null:
		_toggles.call("reset_for_test")
	if _sj != null:
		_sj.call("clear_state")
	if _vp != null:
		_vp.call("reset_for_test")


func _entry(id: String) -> Dictionary:
	for raw in _toggles.call("entries"):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == id:
			return raw
	return {}


func _test_registry() -> void:
	var rows: Array = _toggles.call("entries")
	if rows.size() < 2:
		_fail("registry loaded %d toggles" % rows.size())
		return
	var stab := _entry("stability_justice")
	var paths := _entry("victory_paths")
	if stab.is_empty() or paths.is_empty():
		_fail("registry missing stability_justice or victory_paths")
		return
	if bool(stab.get("default", true)) or bool(paths.get("default", true)):
		_fail("registry default is not off")
		return
	if str(stab.get("env", "")) != "EOA_STABILITY_JUSTICE":
		_fail("stability env is %s" % str(stab.get("env", "")))
		return
	if str(paths.get("env", "")) != "EOA_VICTORY_PATHS":
		_fail("victory env is %s" % str(paths.get("env", "")))
		return
	if str(stab.get("label", "")).is_empty() or str(paths.get("label", "")).is_empty():
		_fail("registry label missing")
		return
	if bool(_toggles.call("is_enabled", "stability_justice")) or bool(_toggles.call("is_enabled", "victory_paths")):
		_fail("fresh registry is not off")
		return
	if bool(_toggles.call("is_enabled", "not_a_toggle")):
		_fail("unknown id enabled")
		return
	_pass("registry loads stability_justice and victory_paths, both default off")


func _test_modder_entry() -> void:
	_toggles.call("set_registry_for_test", [{
		"id": "mod_probe",
		"label": "Mod Probe",
		"default": false,
		"env": "EOA_SETTINGS_TOGGLES_PROBE",
	}])
	if bool(_toggles.call("is_enabled", "mod_probe")):
		_fail("mod entry defaulted on")
		return
	_toggles.call("apply_setup", {"mod_probe": true})
	if not bool(_toggles.call("is_enabled", "mod_probe")):
		_fail("mod entry setup did not enable")
		return
	OS.set_environment("EOA_SETTINGS_TOGGLES_PROBE", "0")
	if bool(_toggles.call("is_enabled", "mod_probe")):
		_fail("mod entry ignored env 0")
		return
	var blob: Dictionary = _toggles.call("export_save_blob")
	if not bool(blob.get("mod_probe", false)):
		_fail("mod entry was not saved")
		return
	_toggles.call("reset_for_test")
	if not _entry("mod_probe").is_empty() or _entry("stability_justice").is_empty():
		_fail("reset did not restore the file registry")
		return
	_pass("a registry entry enables, saves, and yields to its env without domain edits")


func _test_precedence(gd: Node) -> void:
	if bool(gd.call("stability_justice_enabled")) or bool(gd.call("victory_paths_enabled")):
		_fail("default left a system on")
		return
	_toggles.call("apply_setup", {"stability_justice": true, "victory_paths": false})
	if not bool(gd.call("stability_justice_enabled")) or bool(gd.call("victory_paths_enabled")):
		_fail("campaign choice did not beat the default")
		return
	OS.set_environment("EOA_STABILITY_JUSTICE", "0")
	if bool(gd.call("stability_justice_enabled")):
		_fail("env 0 did not beat a campaign on")
		return
	OS.set_environment("EOA_STABILITY_JUSTICE", "")
	OS.set_environment("EOA_VICTORY_PATHS", "1")
	if not bool(gd.call("victory_paths_enabled")):
		_fail("env 1 did not beat a campaign off")
		return
	if not bool(gd.call("stability_justice_enabled")):
		_fail("clearing env dropped the campaign on")
		return
	for bad in ["", "true", "yes", "on", "TRUE"]:
		OS.set_environment("EOA_VICTORY_PATHS", bad)
		_toggles.call("apply_setup", {"victory_paths": false})
		if bool(gd.call("victory_paths_enabled")):
			_fail("non 0/1 env '%s' turned victory on" % bad)
			return
	OS.set_environment("EOA_VICTORY_PATHS", "yes")
	_toggles.call("apply_setup", {"victory_paths": true})
	if not bool(gd.call("victory_paths_enabled")):
		_fail("non 0/1 env blocked the campaign choice")
		return
	_pass("env 1 or 0 wins, then the campaign choice, then the default")


func _test_save_roundtrip(gd: Node) -> void:
	_toggles.call("apply_setup", {"stability_justice": true, "victory_paths": true})
	var save: Dictionary = gd.call("get_save_data")
	var blob: Dictionary = save.get("system_toggles", {})
	if not bool(blob.get("stability_justice", false)) or not bool(blob.get("victory_paths", false)):
		_fail("save missed a non-default toggle: %s" % str(blob))
		return
	if save.has("stability_justice") or save.has("victory_paths"):
		_fail("toggle-only save wrote a system blob")
		return
	_toggles.call("load_missing_save")
	if bool(gd.call("stability_justice_enabled")) or bool(gd.call("victory_paths_enabled")):
		_fail("clear did not drop the campaign choice")
		return
	gd.call("apply_save_data", save)
	if not bool(gd.call("stability_justice_enabled")) or not bool(gd.call("victory_paths_enabled")):
		_fail("load did not restore both toggles")
		return
	var again: Dictionary = gd.call("get_save_data")
	var again_blob: Dictionary = again.get("system_toggles", {})
	if not bool(again_blob.get("stability_justice", false)) or not bool(again_blob.get("victory_paths", false)):
		_fail("second save dropped a toggle")
		return
	_toggles.call("apply_setup", {})
	var off_save: Dictionary = gd.call("get_save_data")
	if off_save.has("system_toggles"):
		_fail("all-default save wrote system_toggles")
		return
	_pass("save/load restores non-default toggles and omits the key when all are off")


func _test_pre_ds6(gd: Node) -> void:
	_toggles.call("apply_setup", {"stability_justice": true, "victory_paths": true})
	_sj.call("import_save_blob", {"stability": 0.4, "justify": {"active": false}})
	_vp.call("import_save_blob", {"arsenal_streak": {"GER": 2}, "last_elapsed": 4})
	gd.call("apply_save_data", {"version": 1})
	if bool(gd.call("stability_justice_enabled")) or bool(gd.call("victory_paths_enabled")):
		_fail("pre-DS-6 load kept a toggle on")
		return
	if bool(_sj.call("has_state")) or bool(_vp.call("has_state")):
		_fail("pre-DS-6 load kept system state")
		return
	var save: Dictionary = gd.call("get_save_data")
	if save.has("system_toggles") or save.has("stability_justice") or save.has("victory_paths"):
		_fail("pre-DS-6 load wrote a toggle or system key")
		return
	_pass("pre-DS-6 save loads with defaults and no system keys")


func _test_each_off(gd: Node) -> void:
	var forced := {
		"date": "1936-02-02",
		"elapsed": 3,
		"player_tag": "GER",
		"world_factories": 100,
		"tags": {
			"GER": {
				"controlled_targets": 0,
				"target_total": 8,
				"factories": 50,
				"atomic_ready": false,
				"major_enemies": [],
				"capitulated_enemies": [],
			},
		},
	}
	_vp.call("set_snapshot_override", forced)
	var sj_tick: Dictionary = gd.call("stability_justice_tick_day")
	var vp_tick: Dictionary = gd.call("victory_paths_tick_day")
	if not bool(sj_tick.get("skipped", false)) or not bool(vp_tick.get("skipped", false)):
		_fail("off tick was not skipped sj=%s vp=%s" % [str(sj_tick), str(vp_tick)])
		return
	gd.call("apply_war_goal_justify", PID)
	gd.call("apply_war_goal_execute", PID)
	if bool(_sj.call("has_state")) or bool(_vp.call("has_state")):
		_fail("off path created system state")
		return
	if bool(gd.peace_state.has("stability_justice")) or bool(gd.peace_state.has("victory_paths")):
		_fail("off path wrote peace_state keys")
		return
	if str(gd.call("stability_justice_chip_line")) != "" or str(gd.call("victory_paths_progress_text")) != "":
		_fail("off readout was not empty")
		return
	var save: Dictionary = gd.call("get_save_data")
	if save.has("system_toggles") or save.has("stability_justice") or save.has("victory_paths"):
		_fail("off save gained a key")
		return
	var menu := _make_menu()
	if menu == null:
		_fail("off Command Center failed to build")
		return
	if menu.find_child("VictoryPathsReadout", true, false) != null:
		_fail("off Command Center created VictoryPathsReadout")
		menu.free()
		return
	menu.free()
	_pass("each toggle off: no tick, readout, or save key")


func _test_each_on(gd: Node) -> void:
	_toggles.call("apply_setup", {"stability_justice": true})
	if not bool(gd.call("stability_justice_enabled")) or bool(gd.call("victory_paths_enabled")):
		_fail("stability campaign toggle did not enable only that system")
		return
	var started: Dictionary = gd.call("apply_war_goal_justify", PID)
	if int(started.get("justify_days_done", -1)) != 1:
		_fail("stability on did not start justify: %s" % str(started))
		return
	var chip := str(gd.call("stability_justice_chip_line"))
	if not chip.begins_with("Stability "):
		_fail("stability on chip line missing: %s" % chip)
		return
	var sj_save: Dictionary = gd.call("get_save_data")
	if not (sj_save.get("stability_justice") is Dictionary):
		_fail("stability on save missing stability_justice")
		return
	var sj_toggles: Dictionary = sj_save.get("system_toggles", {})
	if not bool(sj_toggles.get("stability_justice", false)) or bool(sj_toggles.get("victory_paths", false)):
		_fail("stability on toggle blob: %s" % str(sj_toggles))
		return
	if sj_save.has("victory_paths"):
		_fail("stability on wrote victory_paths")
		return
	_pass("stability_justice on from the campaign toggle")

	_sj.call("clear_state")
	_toggles.call("apply_setup", {"victory_paths": true})
	if bool(gd.call("stability_justice_enabled")) or not bool(gd.call("victory_paths_enabled")):
		_fail("victory campaign toggle did not enable only that system")
		return
	_vp.call("reset_for_test")
	_vp.call("set_snapshot_override", {
		"date": "1936-02-02",
		"elapsed": 3,
		"player_tag": "GER",
		"world_factories": 100,
		"tags": {
			"GER": {
				"controlled_targets": 0,
				"target_total": 8,
				"factories": 50,
				"atomic_ready": false,
				"major_enemies": [],
				"capitulated_enemies": [],
			},
		},
	})
	var tick: Dictionary = gd.call("victory_paths_tick_day")
	if bool(tick.get("skipped", false)) or not bool(_vp.call("has_state")):
		_fail("victory on tick did not store progress: %s" % str(tick))
		return
	var text := str(gd.call("victory_paths_progress_text"))
	if text.is_empty():
		_fail("victory on progress text is empty")
		return
	var vp_save: Dictionary = gd.call("get_save_data")
	if not (vp_save.get("victory_paths") is Dictionary):
		_fail("victory on save missing victory_paths")
		return
	var vp_toggles: Dictionary = vp_save.get("system_toggles", {})
	if not bool(vp_toggles.get("victory_paths", false)) or bool(vp_toggles.get("stability_justice", false)):
		_fail("victory on toggle blob: %s" % str(vp_toggles))
		return
	if vp_save.has("stability_justice"):
		_fail("victory on wrote stability_justice")
		return
	var menu := _make_menu()
	if menu == null:
		_fail("on Command Center failed to build")
		return
	if menu.find_child("VictoryPathsReadout", true, false) == null:
		_fail("victory on Command Center has no readout")
		menu.free()
		return
	menu.free()
	_pass("victory_paths on from the campaign toggle")


func _test_setup_ui() -> void:
	var boot_script := load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if boot_script == null:
		_fail("LivingTitleBoot missing")
		return
	var boot: Node = boot_script.new()
	boot.call("_build_ui")
	var panel := boot.find_child("LivingTitlePanel", true, false) as Control
	if panel == null:
		_fail("setup panel missing")
		boot.free()
		return
	var width := panel.offset_right - panel.offset_left
	if width > 480.0 or panel.offset_right >= 1280.0 or panel.offset_left < 0.0:
		_fail("setup panel does not fit 1280 width (left=%s right=%s)" % [panel.offset_left, panel.offset_right])
		boot.free()
		return
	var header := boot.find_child("SystemTogglesHeader", true, false) as Label
	if header == null or header.text != "SYSTEMS":
		_fail("SYSTEMS header missing")
		boot.free()
		return
	for id in ["stability_justice", "victory_paths"]:
		var box := boot.find_child("SystemToggle_%s" % id, true, false) as CheckBox
		var entry := _entry(id)
		if box == null:
			_fail("checkbox missing for %s" % id)
			boot.free()
			return
		if box.text != str(entry.get("label", "")):
			_fail("checkbox label %s want %s" % [box.text, str(entry.get("label", ""))])
			boot.free()
			return
		if box.button_pressed:
			_fail("checkbox %s starts checked" % id)
			boot.free()
			return
		if box.custom_minimum_size.x > width - 32.0 or box.custom_minimum_size.y < 24.0:
			_fail("checkbox %s size %s does not fit the panel" % [id, str(box.custom_minimum_size)])
			boot.free()
			return
		if int(box.get_theme_font_size("font_size")) < 14:
			_fail("checkbox %s font is under 14" % id)
			boot.free()
			return
	var stab_box := boot.find_child("SystemToggle_stability_justice", true, false) as CheckBox
	stab_box.button_pressed = true
	var chosen: Dictionary = boot.call("commit_setup_toggles")
	if not bool(chosen.get("stability_justice", false)) or bool(chosen.get("victory_paths", false)):
		_fail("Begin stored %s" % str(chosen))
		boot.free()
		return
	if not bool(_toggles.call("is_enabled", "stability_justice")) or bool(_toggles.call("is_enabled", "victory_paths")):
		_fail("Begin did not apply the checked system")
		boot.free()
		return
	boot.free()
	_pass("setup screen has one ink checkbox per toggle inside a 1280-wide panel")


## Real title `_input` path. A panel catch-all must not swallow the checkbox,
## and Space/Enter on a focused box must not Begin.
func _test_setup_input(gd: Node) -> void:
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	await _assert_toggle_click()
	_quiet()
	await _assert_toggle_keys(gd)
	_quiet()
	await _assert_viewport_toggle_keys(gd)


func _assert_toggle_click() -> void:
	var boot := await _spawn_title()
	if boot == null:
		return
	var box := boot.find_child("SystemToggle_stability_justice", true, false) as CheckBox
	var other := boot.find_child("SystemToggle_victory_paths", true, false) as CheckBox
	if box == null or other == null:
		_fail("input click: system checkbox missing")
		_free_title(boot)
		return
	var rect := box.get_global_rect()
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		_fail("input click: checkbox has no rect %s" % str(rect))
		_free_title(boot)
		return
	if box.button_pressed or other.button_pressed:
		_fail("input click: checkbox starts checked")
		_free_title(boot)
		return
	var center := rect.get_center()
	boot._input(_mouse(center, true))
	boot._input(_mouse(center, false))
	if bool(boot.get("_closed")):
		_fail("input click: mouse press started the campaign")
		return
	if not box.button_pressed or other.button_pressed:
		_fail("input click: SystemToggle_stability_justice stayed unchecked after _input press/release at %s" % str(center))
		_free_title(boot)
		return
	_free_title(boot)
	_pass("input click: _input press/release checks the system box and does not Begin")


func _assert_toggle_keys(gd: Node) -> void:
	var boot := await _spawn_title()
	if boot == null:
		return
	var box := boot.find_child("SystemToggle_stability_justice", true, false) as CheckBox
	var other := boot.find_child("SystemToggle_victory_paths", true, false) as CheckBox
	if box == null or other == null:
		_fail("input key: system checkbox missing")
		_free_title(boot)
		return
	if not await _focus_box(boot, box):
		_free_title(boot)
		return
	boot._input(_key(KEY_SPACE))
	if bool(boot.get("_closed")) or not box.button_pressed or other.button_pressed:
		_fail("input key: focused Space did not check the box without Begin (pressed=%s closed=%s)" % [box.button_pressed, str(boot.get("_closed"))])
		_free_title(boot)
		return
	await process_frame
	if not await _focus_box(boot, box):
		_free_title(boot)
		return
	boot._input(_key(KEY_ENTER))
	if bool(boot.get("_closed")) or box.button_pressed:
		_fail("input key: focused Enter did not clear the box without Begin (pressed=%s closed=%s)" % [box.button_pressed, str(boot.get("_closed"))])
		_free_title(boot)
		return
	await process_frame
	if not await _focus_box(boot, box):
		_free_title(boot)
		return
	boot._input(_key(KEY_SPACE))
	if bool(boot.get("_closed")) or not box.button_pressed:
		_fail("input key: second focused Space did not check the box without Begin (pressed=%s closed=%s)" % [box.button_pressed, str(boot.get("_closed"))])
		_free_title(boot)
		return
	box.release_focus()
	var vp := boot.get_viewport()
	if vp != null:
		vp.gui_release_focus()
	await process_frame
	var owner := vp.gui_get_focus_owner() if vp != null else null
	if owner == box:
		_fail("input key: checkbox kept focus before Begin")
		_free_title(boot)
		return
	boot._input(_key(KEY_SPACE))
	if not bool(boot.get("_closed")):
		_fail("input key: Space with no system box focused did not Begin")
		_free_title(boot)
		return
	if not bool(gd.call("stability_justice_enabled")) or bool(gd.call("victory_paths_enabled")):
		_fail("input key: started game sj=%s vp=%s" % [str(gd.call("stability_justice_enabled")), str(gd.call("victory_paths_enabled"))])
		return
	_pass("input key: focused Space/Enter toggles the box; Begin with no box focused applies it")


## Live window path. Press then release through Input.parse_input_event, and
## keep the key down across process frames. A direct `_input` call hides the
## second flip.
func _assert_viewport_toggle_keys(gd: Node) -> void:
	var boot := await _spawn_title()
	if boot == null:
		return
	var box := boot.find_child("SystemToggle_stability_justice", true, false) as CheckBox
	var other := boot.find_child("SystemToggle_victory_paths", true, false) as CheckBox
	if box == null or other == null:
		_fail("viewport key: system checkbox missing")
		_free_title(boot)
		return
	if not await _focus_box(boot, box):
		_free_title(boot)
		return
	var flips := {"n": 0}
	box.toggled.connect(func(_on: bool) -> void:
		flips["n"] = int(flips["n"]) + 1
	)
	await _pump_key(KEY_SPACE)
	if bool(boot.get("_closed")) or not box.button_pressed or other.button_pressed or int(flips["n"]) != 1:
		_fail("viewport key: focused Space flips=%s pressed=%s other=%s closed=%s (want one flip, checked, campaign not started)" % [str(flips["n"]), str(box.button_pressed), str(other.button_pressed), str(boot.get("_closed"))])
		_free_title(boot)
		return
	if not await _focus_box(boot, box):
		_free_title(boot)
		return
	await _pump_key(KEY_ENTER)
	if bool(boot.get("_closed")) or box.button_pressed or other.button_pressed or int(flips["n"]) != 2:
		_fail("viewport key: focused Enter flips=%s pressed=%s closed=%s (want one more flip, unchecked, campaign not started)" % [str(flips["n"]), str(box.button_pressed), str(boot.get("_closed"))])
		_free_title(boot)
		return
	box.release_focus()
	var vp := boot.get_viewport()
	if vp != null:
		vp.gui_release_focus()
	await process_frame
	var owner := vp.gui_get_focus_owner() if vp != null else null
	if owner == box:
		_fail("viewport key: checkbox kept focus before Begin")
		_free_title(boot)
		return
	await _pump_key(KEY_ENTER)
	# Begin sets _closed and queue_frees the title. The hold frames free it
	# before this line runs.
	var began := false
	if not is_instance_valid(boot):
		began = true
	elif bool(boot.get("_closed")):
		began = true
	if not began:
		_fail("viewport key: Enter with no system box focused did not Begin")
		_free_title(boot)
		return
	if bool(gd.call("stability_justice_enabled")) or bool(gd.call("victory_paths_enabled")):
		_fail("viewport key: Begin applied a checked box sj=%s vp=%s" % [str(gd.call("stability_justice_enabled")), str(gd.call("victory_paths_enabled"))])
		return
	_pass("viewport key: focused Space/Enter each flip once via InputEvent; Enter with no box focused Begins")


func _pump_key(keycode: int) -> void:
	# One live key-down: the Input singleton stays down across frames, then release.
	Input.parse_input_event(_key_state(keycode, true))
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	for _i in 3:
		await process_frame
	Input.parse_input_event(_key_state(keycode, false))
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	for _j in 2:
		await process_frame


func _spawn_title() -> Node:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	var old := root.get_node_or_null("LivingTitleBoot")
	if old != null:
		old.free()
	var boot_script := load("res://scripts/ui/LivingTitleBoot.gd") as GDScript
	if boot_script == null:
		_fail("input: LivingTitleBoot missing")
		return null
	var boot: Node = boot_script.new()
	boot.name = "LivingTitleBoot"
	root.add_child(boot)
	await process_frame
	await process_frame
	return boot


func _focus_box(boot: Node, box: CheckBox) -> bool:
	box.grab_focus()
	await process_frame
	var vp := boot.get_viewport()
	var owner: Control = vp.gui_get_focus_owner() if vp != null else null
	if owner != box:
		_fail("input key: SystemToggle did not take focus (owner=%s)" % str(owner))
		return false
	return true


func _free_title(boot: Node) -> void:
	if boot != null and is_instance_valid(boot) and not bool(boot.get("_closed")):
		boot.free()


func _mouse(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	return ev


func _key(keycode: int) -> InputEventKey:
	return _key_state(keycode, true)


func _key_state(keycode: int, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = pressed
	ev.echo = false
	ev.keycode = keycode as Key
	ev.physical_keycode = keycode as Key
	return ev


func _make_menu() -> Node:
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	return menu
