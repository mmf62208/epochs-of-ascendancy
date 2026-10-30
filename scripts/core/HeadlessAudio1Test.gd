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
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAudio1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAudio1Test: ", msg)


func _run() -> void:
	print("HeadlessAudio1Test: display=", DisplayServer.get_name())
	var am := _audio()
	if am == null:
		_fail("AudioManager autoload missing")
		_finish()
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
	_finish()


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
