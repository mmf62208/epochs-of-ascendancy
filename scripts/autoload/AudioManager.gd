# scripts/autoload/AudioManager.gd
## AUDIO-1 playback. One pool, Master → UI / SFX.
## Pitch uses a private RandomNumberGenerator. Do not call the global RNG.
extends Node

const MANIFEST_PATH := "res://data/audio_manifest.json"
const CFG_PATH := "user://audio.cfg"
const POOL_SIZE := 16
const HOVER_GAP_MS := 80
const UI_DEFAULT_DB := -12.0
const SFX_DEFAULT_DB := 0.0
const MASTER_DEFAULT_DB := 0.0
const DB_MIN := -40.0
const DB_MAX := 0.0

var _entries: Dictionary = {}
var _streams: Dictionary = {}
var _warned: Dictionary = {}
var _voices: Dictionary = {}
var _requests: Array[String] = []
var _pool: Array[AudioStreamPlayer] = []
var _pool_busy_until: Array[int] = []
var _pitch_rng := RandomNumberGenerator.new()
var _last_hover_ms: int = -100000
var _master_db: float = MASTER_DEFAULT_DB
var _ui_db: float = UI_DEFAULT_DB
var _sfx_db: float = SFX_DEFAULT_DB
var _muted: bool = false
var _time: Node = null


func _init() -> void:
	_pitch_rng.seed = 0x41554431


func _ready() -> void:
	_load_manifest()
	_build_pool()
	_preload_streams()
	load_settings()
	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	if tree != null and tree.root != null:
		_wire_tree(tree.root)
	_connect_day()


func get_master_db() -> float:
	return _master_db


func get_ui_db() -> float:
	return _ui_db


func get_sfx_db() -> float:
	return _sfx_db


func is_muted() -> bool:
	return _muted


func set_master_db(db: float) -> void:
	_master_db = clampf(db, DB_MIN, DB_MAX)
	_apply_buses()
	_save_settings()


func set_ui_db(db: float) -> void:
	_ui_db = clampf(db, DB_MIN, DB_MAX)
	_apply_buses()
	_save_settings()


func set_sfx_db(db: float) -> void:
	_sfx_db = clampf(db, DB_MIN, DB_MAX)
	_apply_buses()
	_save_settings()


func set_muted(on: bool) -> void:
	_muted = on
	_apply_buses()
	_save_settings()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		_apply_buses()
		return
	_master_db = clampf(float(cf.get_value("audio", "master_db", MASTER_DEFAULT_DB)), DB_MIN, DB_MAX)
	_ui_db = clampf(float(cf.get_value("audio", "ui_db", UI_DEFAULT_DB)), DB_MIN, DB_MAX)
	_sfx_db = clampf(float(cf.get_value("audio", "sfx_db", SFX_DEFAULT_DB)), DB_MIN, DB_MAX)
	_muted = bool(cf.get_value("audio", "muted", false))
	_apply_buses()


func request_log() -> Array:
	return _requests.duplicate()


func clear_request_log() -> void:
	_requests.clear()


func warning_count(key: String) -> int:
	return int(_warned.get(key, 0))


func active_voice_count(key: String) -> int:
	return _active(key, Time.get_ticks_msec()).size()


func voice_pitches(key: String) -> Array:
	var out: Array = []
	var rows: Array = _active(key, Time.get_ticks_msec())
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		out.append(float((row_v as Dictionary).get("pitch", 1.0)))
	return out


func day_tick_allowed() -> bool:
	if _muted:
		return false
	if _time == null or not is_instance_valid(_time):
		return false
	if bool(_time.get("paused")):
		return false
	return absf(float(_time.get("time_scale")) - 1.0) <= 0.2


func play(key: String) -> bool:
	return _play(key, false)


func play_forced(key: String) -> bool:
	return _play(key, true)


func _play(key: String, force_pin: bool) -> bool:
	_remember(key)
	if _muted:
		return false
	var now := Time.get_ticks_msec()
	if key == "ui_hover":
		if now - _last_hover_ms < HOVER_GAP_MS:
			return false
		_last_hover_ms = now
	var entry := _entry(key)
	if entry.is_empty():
		_warn_once(key)
		return false
	var stream := _streams.get(key) as AudioStream
	if stream == null:
		_warn_once(key)
		return false
	var bus := str(entry.get("bus", "SFX"))
	var vol := float(entry.get("volume_db", 0.0))
	if key == "pin_focus":
		var prefs := _pin_prefs()
		if not force_pin and bool(prefs.get("muted", false)):
			return false
		var pref_bus := str(prefs.get("bus", ""))
		if not pref_bus.is_empty():
			bus = pref_bus
		if bool(prefs.get("has_db", false)):
			vol = float(prefs.get("db", vol))
	var cap := int(entry.get("max_polyphony", 4))
	if cap < 1:
		cap = 1
	if _active(key, now).size() >= cap:
		return false
	var slot := _acquire(now)
	if slot < 0:
		return false
	var jitter := float(entry.get("pitch_jitter", 0.0))
	var pitch := 1.0
	if jitter > 0.0:
		pitch = clampf(1.0 + _pitch_rng.randf_range(-jitter, jitter), 1.0 - jitter, 1.0 + jitter)
	var until := now + _length_ms(stream)
	_pool_busy_until[slot] = until
	var player := _pool[slot]
	if AudioServer.get_bus_index(bus) < 0:
		bus = "Master"
	player.bus = bus
	player.volume_db = vol
	player.pitch_scale = pitch
	player.stream = stream
	player.play()
	var rows: Array = _voices.get(key, [])
	rows.append({"until_ms": until, "pitch": pitch, "slot": slot})
	_voices[key] = rows
	return true


func _on_game_day(_year: int, _month: int, _day: int) -> void:
	if not day_tick_allowed():
		return
	play("day_tick")


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node as BaseButton)


func _on_ui_pressed() -> void:
	play("ui_click")


func _on_ui_hover() -> void:
	play("ui_hover")


func _connect_day() -> void:
	_time = get_node_or_null("/root/TimeManager")
	if _time == null:
		return
	var cb := Callable(self, "_on_game_day")
	if _time.has_signal("game_day_advanced") and not _time.is_connected("game_day_advanced", cb):
		_time.connect("game_day_advanced", cb)


func _wire_tree(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node as BaseButton)
	for child in node.get_children():
		_wire_tree(child)


func _wire_button(btn: BaseButton) -> void:
	if btn.has_meta("_eoa_audio_wired"):
		return
	btn.set_meta("_eoa_audio_wired", true)
	var press_cb := Callable(self, "_on_ui_pressed")
	var hover_cb := Callable(self, "_on_ui_hover")
	if not btn.pressed.is_connected(press_cb):
		btn.pressed.connect(press_cb)
	if not btn.mouse_entered.is_connected(hover_cb):
		btn.mouse_entered.connect(hover_cb)


func _load_manifest() -> void:
	_entries.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		_warn_once("manifest")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_warn_once("manifest")
		return
	var keys: Variant = (parsed as Dictionary).get("keys", {})
	if typeof(keys) == TYPE_DICTIONARY:
		_entries = keys


func _preload_streams() -> void:
	for key_v in _entries.keys():
		var key := str(key_v)
		var path := str(_entry(key).get("path", ""))
		if path.is_empty() or not _res_exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream != null:
			_streams[key] = stream


func _build_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Pool%d" % i
		add_child(player)
		_pool.append(player)
		_pool_busy_until.append(0)


func _apply_buses() -> void:
	_set_bus("Master", _master_db, _muted)
	_set_bus("UI", _ui_db, false)
	_set_bus("SFX", _sfx_db, false)


func _set_bus(bus_name: String, db: float, mute_bus: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, mute_bus)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master_db", _master_db)
	cf.set_value("audio", "ui_db", _ui_db)
	cf.set_value("audio", "sfx_db", _sfx_db)
	cf.set_value("audio", "muted", _muted)
	cf.save(CFG_PATH)


func _entry(key: String) -> Dictionary:
	var raw: Variant = _entries.get(key, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


func _pin_prefs() -> Dictionary:
	var out := {"muted": false, "has_db": false, "db": 0.0, "bus": ""}
	var tree := get_tree()
	if tree == null:
		return out
	var mr := tree.get_first_node_in_group("map_renderer")
	if mr == null:
		return out
	if mr.has_method("get_pin_focus_sfx_enabled"):
		out["muted"] = not bool(mr.call("get_pin_focus_sfx_enabled"))
	if mr.has_method("get_pin_focus_sfx_volume_db"):
		out["has_db"] = true
		out["db"] = float(mr.call("get_pin_focus_sfx_volume_db"))
	if mr.has_method("get_pin_focus_sfx_bus"):
		out["bus"] = str(mr.call("get_pin_focus_sfx_bus"))
	return out


func _active(key: String, now_ms: int) -> Array:
	var live: Array = []
	var rows: Array = _voices.get(key, [])
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("until_ms", 0)) > now_ms:
			live.append(row)
	_voices[key] = live
	return live


func _acquire(now_ms: int) -> int:
	for i in _pool.size():
		if _pool_busy_until[i] <= now_ms:
			return i
	return -1


func _length_ms(stream: AudioStream) -> int:
	var sec := stream.get_length()
	if sec <= 0.0:
		sec = 0.05
	return maxi(40, ceili(sec * 1000.0))


func _warn_once(key: String) -> void:
	if int(_warned.get(key, 0)) > 0:
		return
	_warned[key] = 1
	push_warning("AudioManager: missing audio '%s'" % key)


func _remember(key: String) -> void:
	_requests.append(key)
	if _requests.size() > 48:
		_requests.pop_front()


func _res_exists(path: String) -> bool:
	if FileAccess.file_exists(path):
		return true
	return FileAccess.file_exists(ProjectSettings.globalize_path(path))
