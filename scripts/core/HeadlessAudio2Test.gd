extends SceneTree

## AUDIO-2. Music bus, CC0 manifest, new keys, crossfade, duck, persistence.
## Launch: tools/run_godot.sh --headless --audio-driver Dummy --path . -s res://scripts/core/HeadlessAudio2Test.gd

const JSON_MANIFEST := "res://data/audio_manifest.json"
const CSV_MANIFEST := "res://audio/AUDIO_MANIFEST.csv"
const CREDITS := "res://audio/CREDITS.md"
const LICENSES := "res://docs/THIRD_PARTY_LICENSES.md"
const NEW_KEYS := [
	"toast_info", "toast_warn", "save_ok", "load_ok",
	"order_move", "order_attack", "capture", "repulse",
	"end_victory_sting", "music_menu", "music_peace",
]
const ALT_KEYS := ["music_menu_alt", "music_menu_loop_alt"]

var _failures: int = 0


func _init() -> void:
	call_deferred("_start")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAudio2Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAudio2Test: ", msg)


func _start() -> void:
	await _run()
	_finish()


func _run() -> void:
	var driver := str(AudioServer.get_driver_name())
	print("HeadlessAudio2Test: driver=", driver, " display=", DisplayServer.get_name())
	if driver != "Dummy":
		_fail("audio driver %s" % driver)
	else:
		_pass("Dummy audio driver")
	var am := root.get_node_or_null("AudioManager")
	if am == null:
		_fail("AudioManager missing")
		return
	_test_bus_and_default(am)
	_test_manifest()
	_test_peaks_and_victory(am)
	_test_seams()
	await _test_crossfade(am)
	_test_duck(am)
	_test_persist_and_silent(am)
	_test_hooks(am)
	await _test_save_load(am)
	await _test_clicks(am)
	_test_missing_and_fallback(am)


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAudio2Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAudio2Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _count(am: Node, key: String) -> int:
	var n := 0
	for item in am.call("request_log"):
		if str(item) == key:
			n += 1
	return n


func _json() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JSON_MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var keys: Variant = (parsed as Dictionary).get("keys", {})
	if typeof(keys) != TYPE_DICTIONARY:
		return {}
	return keys


func _test_bus_and_default(am: Node) -> void:
	var idx := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	if idx < 0 or sfx < 0:
		_fail("Music or SFX bus missing")
		return
	if AudioServer.get_bus_send(idx) != "Master":
		_fail("Music bus send %s" % AudioServer.get_bus_send(idx))
		return
	var bus_db := AudioServer.get_bus_volume_db(idx)
	var sfx_db := AudioServer.get_bus_volume_db(sfx)
	var music_db := float(am.call("get_music_db"))
	var linear := float(am.call("get_music_linear"))
	var expect := db_to_linear(-6.0)
	if absf(bus_db - (-6.0)) > 0.05 or absf(music_db - (-6.0)) > 0.05:
		_fail("music default bus %.2f manager %.2f" % [bus_db, music_db])
		return
	if absf(linear - expect) > 0.001:
		_fail("music linear %.5f want %.5f" % [linear, expect])
		return
	if absf(sfx_db - 0.0) > 0.05:
		_fail("SFX bus moved to %.2f" % sfx_db)
		return
	if music_db - sfx_db > -5.9:
		_fail("music is not 6 dB under SFX (music %.2f sfx %.2f)" % [music_db, sfx_db])
		return
	_pass("Music bus default %.2f dB (linear %.3f), 6 dB under SFX" % [music_db, linear])


func _test_manifest() -> void:
	var rows := _csv_rows(FileAccess.get_file_as_string(CSV_MANIFEST))
	if rows.is_empty():
		_fail("AUDIO_MANIFEST.csv empty")
		return
	var listed := {}
	for row_v in rows:
		var row: Dictionary = row_v
		var rel := _norm(str(row.get("file", "")))
		var lic := str(row.get("license", "")).strip_edges()
		var src := str(row.get("source_file", "")).strip_edges()
		if rel.is_empty():
			_fail("manifest row missing file")
			return
		listed[rel] = true
		var res := "res://" + rel
		if not FileAccess.file_exists(res):
			_fail("manifest file missing %s" % rel)
			return
		if lic == "CC0 1.0":
			continue
		if lic == "original, project-owned":
			var gen := "res://" + src
			if src.is_empty() or not FileAccess.file_exists(gen):
				_fail("original row has no generator %s (%s)" % [rel, src])
				return
			continue
		_fail("license %s on %s" % [lic, rel])
		return
	var shipped := _audio_files("res://audio")
	for rel in shipped:
		if not listed.has(rel):
			_fail("shipped audio missing from manifest %s" % rel)
			return
	var keys := _json()
	for name in NEW_KEYS:
		if not keys.has(name):
			_fail("json missing %s" % name)
			return
		var path := str((keys[name] as Dictionary).get("path", ""))
		if not FileAccess.file_exists(path):
			_fail("json path missing %s %s" % [name, path])
			return
	for name in ALT_KEYS:
		if not keys.has(name):
			_fail("fallback key %s not registered" % name)
			return
		if str((keys[name] as Dictionary).get("bus", "")) != "Music":
			_fail("fallback %s not on Music" % name)
			return
	if str(keys["confirm"].get("path", "")) != "res://audio/sfx/ui/confirm.wav":
		_fail("confirm left the wav")
		return
	var credits := FileAccess.get_file_as_string(CREDITS)
	var licenses := FileAccess.get_file_as_string(LICENSES)
	if "res://audio/AUDIO_MANIFEST.csv" not in credits and "AUDIO_MANIFEST.csv" not in credits:
		_fail("CREDITS does not reference the manifest")
		return
	if "CC-BY" in credits.split("AUDIO-2")[-1] and "No CC-BY" not in credits:
		_fail("AUDIO-2 credits mention CC-BY")
		return
	for rel in shipped:
		if rel.ends_with(".ogg") and ("res://" + rel) not in licenses:
			_fail("third-party licenses missing %s" % rel)
			return
	_pass("manifest covers %d files, CC0 or original+generator" % shipped.size())


func _test_peaks_and_victory(am: Node) -> void:
	var keys := _json()
	var loudest_key := ""
	var loudest := -120.0
	var clash_eff := 0.0
	var click_eff := -99.0
	for name in ["ui_click", "combat_clash", "order_attack", "save_ok", "end_victory_sting", "music_menu", "music_peace", "music_menu_alt", "music_menu_loop_alt"]:
		var entry: Dictionary = keys.get(name, {})
		var path := str(entry.get("path", ""))
		var trim := float(entry.get("volume_db", 0.0))
		var raw := _ogg_peak_db(ProjectSettings.globalize_path(path))
		var eff := raw + trim
		print("  [PEAK] %s raw=%.2f trim=%.1f playback=%.2f" % [name, raw, trim, eff])
		if eff > -6.0 + 0.05:
			_fail("playback peak %.2f %s" % [eff, name])
			return
		if eff > loudest:
			loudest = eff
			loudest_key = name
		if name == "combat_clash":
			clash_eff = eff
		if name == "ui_click":
			click_eff = eff
	if loudest_key == "combat_clash" or clash_eff >= click_eff:
		_fail("clash still loudest clash=%.2f click=%.2f loudest=%s" % [clash_eff, click_eff, loudest_key])
		return
	var victory_path := str(keys["end_victory_sting"].get("path", ""))
	var stream := load(victory_path) as AudioStreamOggVorbis
	if stream == null:
		_fail("victory sting did not load")
		return
	var length := stream.get_length()
	var raw_v := _ogg_peak_db(ProjectSettings.globalize_path(victory_path))
	var loop_import := _import_flag(victory_path, "loop")
	print("  [VICTORY] length=%.3f peak=%.2f loop=%s import_loop=%s" % [length, raw_v, str(stream.loop), loop_import])
	if absf(length - 6.6) > 0.15:
		_fail("victory length %.3f" % length)
		return
	if raw_v > -6.0:
		_fail("victory file peak %.2f" % raw_v)
		return
	if stream.loop:
		_fail("victory loop flag is true")
		return
	if loop_import == "true":
		_fail("victory import loop=true")
		return
	_pass("peaks <= -6 dB playback, clash not loudest, victory %.3fs peak %.2f loop=false" % [length, raw_v])


func _test_seams() -> void:
	var keys := _json()
	for name in ["music_menu", "music_peace"]:
		var path := ProjectSettings.globalize_path(str(keys[name].get("path", "")))
		var seam := _seam(path)
		if seam.is_empty():
			_fail("seam measure failed %s" % name)
			return
		var gap := float(seam.get("lead", 99.0)) + float(seam.get("trail", 99.0))
		var audible := float(seam.get("audible", 99.0))
		print("  [SEAM] %s lead=%.3f trail=%.3f audible=%.5f" % [name, float(seam.get("lead", 0.0)), float(seam.get("trail", 0.0)), audible])
		if gap > 10.0:
			_fail("%s silence %.2fs" % [name, gap])
			return
		if audible > 0.05:
			_fail("%s loop click %.5f" % [name, audible])
			return
		var flag := _import_flag(str(keys[name].get("path", "")), "loop")
		if flag != "true":
			_fail("%s import loop=%s" % [name, flag])
			return
		var stream := load(str(keys[name].get("path", ""))) as AudioStreamOggVorbis
		if stream == null or not stream.loop:
			_fail("%s runtime loop false" % name)
			return
	var alt := _seam(ProjectSettings.globalize_path(str(keys["music_menu_loop_alt"].get("path", ""))))
	print("  [SEAM] music_menu_loop_alt fallback audible=%.5f (not the default loop)" % float(alt.get("audible", -1.0)))
	_pass("music_menu and music_peace loop with no click and <= 10s silence")


func _test_crossfade(am: Node) -> void:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar _closed := false\n"
	if scr.reload() != OK:
		_fail("title probe did not compile")
		return
	var title := Node.new()
	title.set_script(scr)
	title.name = "LivingTitleBoot"
	root.add_child(title)
	am.call("clear_request_log")
	am.call("_refresh_music_scene")
	if str(am.call("music_incoming_key")) != "music_menu":
		_fail("open title did not request music_menu (%s)" % str(am.call("music_incoming_key")))
		return
	if float(am.call("music_incoming_gain")) > 0.02:
		_fail("menu fade did not start at silence gain=%s" % str(am.call("music_incoming_gain")))
		return
	for _i in 22:
		am.call("service_music", 0.1)
	if absf(float(am.call("music_incoming_gain")) - 1.0) > 0.08:
		_fail("menu fade did not finish gain=%s" % str(am.call("music_incoming_gain")))
		return
	title.set("_closed", true)
	var world := Node2D.new()
	world.name = "WorldMap"
	root.add_child(world)
	am.call("_refresh_music_scene")
	if str(am.call("music_incoming_key")) != "music_peace" or str(am.call("music_outgoing_key")) != "music_menu":
		_fail("scene change keys in=%s out=%s" % [str(am.call("music_incoming_key")), str(am.call("music_outgoing_key"))])
		return
	if not bool(am.call("music_incoming_playing")) or not bool(am.call("music_outgoing_playing")):
		_fail("crossfade players in=%s out=%s" % [str(am.call("music_incoming_playing")), str(am.call("music_outgoing_playing"))])
		return
	if float(am.call("music_incoming_gain")) > 0.02 or float(am.call("music_outgoing_gain")) < 0.95:
		_fail("crossfade start in=%s out=%s" % [str(am.call("music_incoming_gain")), str(am.call("music_outgoing_gain"))])
		return
	var prev := float(am.call("music_incoming_gain"))
	var max_step := 0.0
	for _j in 130:
		am.call("service_music", 1.0 / 60.0)
		var g := float(am.call("music_incoming_gain"))
		max_step = maxf(max_step, absf(g - prev))
		prev = g
	if max_step > 0.02:
		_fail("crossfade step %.4f" % max_step)
		return
	if str(am.call("music_incoming_key")) != "music_peace" or bool(am.call("music_outgoing_playing")):
		_fail("peace did not remain after fade")
		return
	if _count(am, "music_menu") != 1 or _count(am, "music_peace") != 1:
		_fail("music log %s" % str(am.call("request_log")))
		return
	if str(am.call("music_incoming_key")) in ALT_KEYS:
		_fail("fallback music became the default")
		return
	title.queue_free()
	world.queue_free()
	_pass("menu to peace crossfade 2s max step %.4f" % max_step)


func _test_duck(am: Node) -> void:
	var base := float(am.call("get_music_db"))
	am.call("clear_request_log")
	if not bool(am.call("play", "end_victory_sting")):
		_fail("duck sting did not play")
		return
	var ducked := float(am.call("music_bus_db"))
	var span := int(am.call("music_duck_span_ms"))
	var stream := load("res://audio/sfx/end/end_victory_sting.ogg") as AudioStream
	var want := 0
	if stream != null:
		want = maxi(40, ceili(stream.get_length() * 1000.0))
	print("  [DUCK] bus %.2f -> %.2f span_ms=%d stream_ms=%d" % [base, ducked, span, want])
	if absf(float(am.call("music_duck_db")) - (-8.0)) > 0.01:
		_fail("duck db %s" % str(am.call("music_duck_db")))
		return
	if absf(ducked - (base - 8.0)) > 0.2:
		_fail("ducked bus %.2f base %.2f" % [ducked, base])
		return
	if abs(span - want) > 80:
		_fail("duck span %d vs %d" % [span, want])
		return
	am.call("_tick_music_duck", Time.get_ticks_msec() + span + 50)
	if absf(float(am.call("music_duck_db"))) > 0.01:
		_fail("duck did not release")
		return
	if absf(float(am.call("music_bus_db")) - base) > 0.2:
		_fail("bus did not restore %.2f" % float(am.call("music_bus_db")))
		return
	_pass("sting ducks Music by -8 dB for %d ms" % span)


func _test_persist_and_silent(am: Node) -> void:
	var slider_ok := _music_slider_defaults()
	if not slider_ok:
		return
	am.call("set_music_linear", 0.25)
	var cf := ConfigFile.new()
	if cf.load("user://audio.cfg") != OK:
		_fail("audio.cfg missing after music write")
		return
	if absf(float(cf.get_value("audio", "music_linear", -1.0)) - 0.25) > 0.001:
		_fail("cfg music_linear %s" % str(cf.get_value("audio", "music_linear", null)))
		return
	cf.set_value("audio", "music_linear", 0.4)
	cf.save("user://audio.cfg")
	am.call("load_settings")
	if absf(float(am.call("get_music_linear")) - 0.4) > 0.001:
		_fail("reload linear %s" % str(am.call("get_music_linear")))
		return
	var sfx_before := float(am.call("get_sfx_db"))
	am.call("set_music_linear", 0.0)
	if absf(float(am.call("get_music_linear"))) > 0.0001:
		_fail("linear did not hit 0")
		return
	if bool(am.call("music_incoming_playing")) or bool(am.call("music_outgoing_playing")):
		_fail("volume 0 left a music player running")
		return
	if float(am.call("music_bus_db")) > -70.0:
		_fail("volume 0 bus %.2f" % float(am.call("music_bus_db")))
		return
	am.call("clear_request_log")
	if not bool(am.call("play", "ui_click")):
		_fail("sfx silent when music is 0")
		return
	if absf(float(am.call("get_sfx_db")) - sfx_before) > 0.01:
		_fail("sfx db changed")
		return
	am.call("load_settings")
	_pass("music linear persists (0.25 write, 0.40 reload) and 0 stops playback")


func _music_slider_defaults() -> bool:
	var packed := load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		_fail("MainMenu scene missing")
		return false
	var menu := packed.instantiate()
	menu.name = "Audio2SliderProbe"
	root.add_child(menu)
	var slider := menu.find_child("MusicVolume", true, false) as HSlider
	var mute := menu.find_child("MuteAudio", true, false) as CheckButton
	if slider == null or mute == null:
		_fail("Music slider or Mute missing")
		menu.queue_free()
		return false
	if slider.min_value > 0.1 or slider.max_value < 99.0:
		_fail("Music slider range %s..%s" % [slider.min_value, slider.max_value])
		menu.queue_free()
		return false
	if slider.value < 49.0 or slider.value > 51.0:
		_fail("Music slider default %.1f" % slider.value)
		menu.queue_free()
		return false
	menu.queue_free()
	_pass("Music slider 0-100 default %.0f and Mute present" % slider.value)
	return true


func _test_hooks(am: Node) -> void:
	var map_src := FileAccess.get_file_as_string("res://scripts/map/MapRenderer.gd")
	var move := _fn_body(map_src, "_try_move_selected_unit_to_province")
	var assault := _fn_body(map_src, "_try_open_land_unit_at_world")
	var aar := _fn_body(map_src, "_surface_last_land_aar_toast")
	if move.count("call(\"notify_mv1_move_committed\")") != 1:
		_fail("move hook count %d" % move.count("call(\"notify_mv1_move_committed\")"))
		return
	if assault.count("call(\"notify_assault_ordered\")") != 1:
		_fail("assault hook count %d" % assault.count("call(\"notify_assault_ordered\")"))
		return
	if aar.count("call(\"notify_province_outcome\"") != 1:
		_fail("aar hook count %d" % aar.count("call(\"notify_province_outcome\""))
		return
	var title := FileAccess.get_file_as_string("res://scripts/ui/LivingTitleBoot.gd")
	var menu := FileAccess.get_file_as_string("res://scripts/ui/MainMenu.gd")
	if _fn_body(title, "_ready").count("_note_music(\"menu\")") < 1:
		_fail("title ready does not note menu music")
		return
	if _fn_body(title, "_finish").count("_note_music(\"game\")") < 1:
		_fail("title finish does not note game music")
		return
	if _fn_body(menu, "_ready").count("_note_music(\"menu\")") < 1:
		_fail("menu ready does not note menu music")
		return
	if _fn_body(menu, "_force_close").count("_note_music(") < 1:
		_fail("menu close does not note music")
		return
	if LandBattleSfx.key_for("capture") != "capture" or LandBattleSfx.key_for("repulse") != "repulse":
		_fail("LandBattleSfx capture/repulse keys")
		return
	if LandBattleSfx.key_for_unit("clash", "armor") != "achievement":
		_fail("armor flavor key changed")
		return
	var ui := root.get_node_or_null("LeaderEventUI")
	if ui == null:
		_fail("LeaderEventUI missing")
		return
	am.call("clear_request_log")
	ui.call("show_toast", "hello", 1.0, false)
	if _count(am, "toast_info") != 1 or _count(am, "toast_warn") != 0:
		_fail("toast_info log %s" % str(am.call("request_log")))
		return
	am.call("clear_request_log")
	ui.call("show_toast", "warning lights", 1.0, false)
	if _count(am, "toast_info") != 1 or _count(am, "toast_warn") != 0:
		_fail("warn-word toast log %s" % str(am.call("request_log")))
		return
	am.call("clear_request_log")
	ui.call("show_toast", "bad", 1.0, true)
	if _count(am, "toast_warn") != 1 or _count(am, "toast_info") != 0 or _count(am, "error") != 0:
		_fail("toast_warn log %s" % str(am.call("request_log")))
		return
	am.call("clear_request_log")
	am.call("notify_mv1_move_committed")
	am.call("notify_assault_ordered")
	am.call("notify_province_outcome", "attacker", "Province captured")
	if _count(am, "order_move") != 1 or _count(am, "order_attack") != 1 or _count(am, "capture") != 1:
		_fail("order/capture log %s" % str(am.call("request_log")))
		return
	am.call("clear_request_log")
	am.call("notify_province_outcome", "defender", "Attack repulsed")
	if _count(am, "repulse") != 1:
		_fail("repulse log %s" % str(am.call("request_log")))
		return
	_pass("hooks fire once: toast, move, assault, capture, repulse")


func _test_save_load(am: Node) -> void:
	var slm := root.get_node_or_null("SaveLoadManager")
	if slm == null:
		_fail("SaveLoadManager missing")
		return
	am.call("clear_request_log")
	var saved: Variant = slm.call("save_game_detailed", "audio2")
	if typeof(saved) != TYPE_DICTIONARY or not bool((saved as Dictionary).get("ok", false)):
		_fail("save failed %s" % str(saved))
		return
	if _count(am, "save_ok") != 1:
		_fail("save_ok count %d log %s" % [_count(am, "save_ok"), str(am.call("request_log"))])
		return
	am.call("clear_request_log")
	var loaded: Variant = slm.call("load_game_detailed", "audio2")
	var dup: Variant = slm.call("load_game_detailed", "audio2")
	if typeof(loaded) != TYPE_DICTIONARY or not bool((loaded as Dictionary).get("ok", false)):
		_fail("load failed %s" % str(loaded))
		return
	if typeof(dup) != TYPE_DICTIONARY or not bool((dup as Dictionary).get("duplicate", false)):
		_fail("duplicate load was not skipped %s" % str(dup))
		return
	for _i in 4:
		await process_frame
	if _count(am, "load_ok") != 1:
		_fail("load_ok count %d log %s" % [_count(am, "load_ok"), str(am.call("request_log"))])
		return
	_pass("save_ok once and load_ok once after the scene settles")


func _test_clicks(am: Node) -> void:
	var packed := load("res://scenes/ui/MainMenu.tscn") as PackedScene
	var menu := packed.instantiate()
	menu.name = "Audio2ClickMenu"
	root.add_child(menu)
	await process_frame
	var refresh := menu.find_child("RefreshSaveList", true, false) as Button
	if refresh == null:
		_fail("menu item missing")
		return
	am.call("clear_request_log")
	refresh.pressed.emit()
	if _count(am, "ui_click") != 1:
		_fail("menu item clicks %d" % _count(am, "ui_click"))
		return
	menu.call("_open_load_confirm", "audio2")
	var load_b := menu.find_child("BtnLoad", true, false) as Button
	if load_b == null:
		_fail("Load confirm button missing")
		return
	am.call("clear_request_log")
	load_b.pressed.emit()
	if _count(am, "ui_click") != 1:
		_fail("load confirm clicks %d" % _count(am, "ui_click"))
		return
	menu.queue_free()
	await process_frame
	var overlay_scr := load("res://scripts/ui/DebugOverlay.gd") as GDScript
	if overlay_scr == null or not overlay_scr.can_instantiate():
		_fail("Dev Harness script did not compile")
		return
	var overlay: Node = overlay_scr.new()
	root.add_child(overlay)
	await process_frame
	var harness := overlay.find_child("BtnToggleDevHarness", true, false) as Button
	if harness == null:
		_fail("Dev Harness button missing")
		overlay.queue_free()
		return
	am.call("clear_request_log")
	harness.pressed.emit()
	if _count(am, "ui_click") != 1:
		_fail("dev harness clicks %d" % _count(am, "ui_click"))
		overlay.queue_free()
		return
	overlay.queue_free()
	overlay_scr.set("instance", null)
	_pass("one ui_click on menu item, Load confirm, and Dev Harness")


func _test_missing_and_fallback(am: Node) -> void:
	var key := "audio2_missing_key"
	am.call("play", key)
	am.call("play", key)
	if int(am.call("warning_count", key)) != 1:
		_fail("missing warning %s" % str(am.call("warning_count", key)))
		return
	var abs_path := ProjectSettings.globalize_path("res://audio/sfx/ui/ui_click.ogg")
	var bak := abs_path + ".audio2bak"
	var renamed := DirAccess.rename_absolute(abs_path, bak)
	if renamed != OK:
		_fail("could not hide ui_click.ogg (%d)" % renamed)
		return
	am.call("forget_cached_stream", "ui_click")
	var played := bool(am.call("play", "ui_click"))
	var warns := int(am.call("warning_count", "ui_click"))
	DirAccess.rename_absolute(bak, abs_path)
	am.call("forget_cached_stream", "ui_click")
	am.call("play", "ui_click")
	if not played or warns != 1:
		_fail("wav fallback played=%s warnings=%d" % [str(played), warns])
		return
	if int(am.call("warning_count", "ui_click")) != 1:
		_fail("fallback warned again")
		return
	_pass("missing key warns once; ogg miss falls back to wav with one warning")


func _fn_body(src: String, name: String) -> String:
	var token := "func %s" % name
	var at := src.find(token)
	if at < 0:
		return ""
	var nxt := src.find("\nfunc ", at + token.length())
	if nxt < 0:
		return src.substr(at)
	return src.substr(at, nxt - at)


func _audio_files(root_path: String) -> Array:
	var out: Array = []
	_walk_audio(root_path, out)
	return out


func _walk_audio(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var child := path.path_join(name)
			if dir.current_is_dir():
				_walk_audio(child, out)
			elif name.ends_with(".ogg") or name.ends_with(".wav"):
				out.append(_norm(child))
		name = dir.get_next()
	dir.list_dir_end()


func _norm(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p.begins_with("res://"):
		p = p.substr(6)
	return p


func _csv_rows(text: String) -> Array:
	var rows: Array = []
	var header: Array = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		var cols := _csv_split(line)
		if header.is_empty():
			header = cols
			continue
		var row := {}
		for i in cols.size():
			if i < header.size():
				row[str(header[i])] = cols[i]
		rows.append(row)
	return rows


func _csv_split(line: String) -> Array:
	var out: Array = []
	var cur := ""
	var quoted := false
	for i in line.length():
		var ch := line.substr(i, 1)
		if ch == "\"":
			quoted = not quoted
			continue
		if ch == "," and not quoted:
			out.append(cur)
			cur = ""
			continue
		cur += ch
	out.append(cur)
	return out


func _import_flag(res_path: String, field: String) -> String:
	var abs_path := ProjectSettings.globalize_path(res_path) + ".import"
	if not FileAccess.file_exists(abs_path):
		return "missing"
	for line in FileAccess.get_file_as_string(abs_path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with(field + "="):
			return trimmed.substr(field.length() + 1).strip_edges()
	return "absent"


func _ogg_peak_db(abs_path: String) -> float:
	var out: Array = []
	var code := OS.execute("ffmpeg", [
		"-hide_banner", "-nostats", "-i", abs_path,
		"-af", "astats=metadata=1:reset=0",
		"-f", "null", "-",
	], out, true)
	var peak := -120.0
	var found := false
	for line_v in out:
		for line in str(line_v).split("\n"):
			var mark := "Peak level dB:"
			var at := line.find(mark)
			if at < 0:
				continue
			var num := line.substr(at + mark.length()).strip_edges().split(" ")[0]
			if num.is_empty() or num.contains("inf"):
				continue
			var v := float(num)
			if not found or v > peak:
				peak = v
				found = true
	if not found:
		push_warning("HeadlessAudio2Test: peak unread code=%s %s" % [str(code), abs_path])
		return 99.0
	return peak


func _seam(abs_path: String) -> Dictionary:
	# ffmpeg writes a non-monotonic-dts note on stderr for the longer peace loop.
	# OS.execute with read_stderr mixes that into stdout and JSON.parse_string
	# then sees "[f32le ..." as a broken token. The numbers go to a file instead.
	var py := """
import struct, subprocess, sys
path = sys.argv[1]
out_path = sys.argv[2]
raw = subprocess.check_output(["ffmpeg","-v","error","-i",path,"-f","f32le","-ac","1","-ar","44100","pipe:1"], stderr=subprocess.DEVNULL)
n = len(raw)//4
if n < 8:
    raise SystemExit(2)
s = struct.unpack("<%df" % n, raw[:n*4])
thr = 10 ** (-45.0/20.0)
def run(seq):
    c = 0
    for v in seq:
        if abs(v) < thr:
            c += 1
        else:
            break
    return c / 44100.0
lead = run(s)
trail = run(reversed(s))
edge = abs(s[-1] - s[0])
audible = 0.0 if (abs(s[0]) < thr and abs(s[-1]) < thr) else edge
with open(out_path, "w", encoding="utf-8") as fh:
    fh.write("%.8f %.8f %.8f\\n" % (lead, trail, audible))
"""
	var script := ProjectSettings.globalize_path("user://audio2_seam.py")
	var result_path := ProjectSettings.globalize_path("user://audio2_seam.txt")
	var f := FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		return {}
	f.store_string(py)
	f.close()
	DirAccess.remove_absolute(result_path)
	var out: Array = []
	var code := OS.execute("python3", [script, abs_path, result_path], out, false)
	if code != 0 or not FileAccess.file_exists(result_path):
		return {}
	var parts := FileAccess.get_file_as_string(result_path).strip_edges().split(" ", false)
	if parts.size() != 3:
		return {}
	if not parts[0].is_valid_float() or not parts[1].is_valid_float() or not parts[2].is_valid_float():
		return {}
	return {"lead": float(parts[0]), "trail": float(parts[1]), "audible": float(parts[2])}
