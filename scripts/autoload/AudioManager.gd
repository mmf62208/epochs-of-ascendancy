# scripts/autoload/AudioManager.gd
## AUDIO-1 playback. One pool, Master → UI / SFX.
## Pitch uses a private RandomNumberGenerator. Do not call the global RNG.
extends Node

const MANIFEST_PATH := "res://data/audio_manifest.json"
const CFG_PATH := "user://audio.cfg"
const POOL_SIZE := 16
## 80 ms between hovers. The CC0 hover file is 457 ms, so its polyphony is 6
## and this gap stays the limit (Audio1 retries at 90 ms).
const HOVER_GAP_MS := 80
const UI_DEFAULT_DB := -12.0
const SFX_DEFAULT_DB := 0.0
const MASTER_DEFAULT_DB := 0.0
const DB_MIN := -40.0
const DB_MAX := 0.0
const MUSIC_DEFAULT_DB := -6.0
const MUSIC_FADE_SEC := 2.0
const MUSIC_DUCK_DB := -8.0
const MUSIC_SILENT_DB := -80.0
const WAV_FALLBACK := {
	"ui_click": "res://audio/sfx/ui/ui_click.wav",
	"ui_hover": "res://audio/sfx/ui/ui_hover.wav",
	"combat_clash": "res://audio/sfx/combat/combat_clash.wav",
	"end_victory_sting": "res://audio/sfx/end/end_victory_sting.wav",
	"end_defeat_sting": "res://audio/sfx/end/end_defeat_sting.wav",
	"order_issued": "res://audio/sfx/ui/confirm.wav",
}

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
var _music_db: float = MUSIC_DEFAULT_DB
var _music_linear: float = 0.5011872336272722
var _music_mode: String = ""
var _mus_in: AudioStreamPlayer = null
var _mus_out: AudioStreamPlayer = null
var _key_in: String = ""
var _key_out: String = ""
var _fade_t: float = 1.0
var _fading: bool = false
var _gain_in: float = 0.0
var _gain_out: float = 0.0
var _gain_trace: Array = []
var _music_duck_db: float = 0.0
var _music_duck_until_ms: int = 0
var _music_duck_span_ms: int = 0


func _init() -> void:
	_pitch_rng.seed = 0x41554431
	_music_linear = db_to_linear(MUSIC_DEFAULT_DB)


func _ready() -> void:
	set_process(false)
	_load_manifest()
	_build_pool()
	_build_music()
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


func get_music_db() -> float:
	return _music_db


func get_music_linear() -> float:
	return _music_linear


## 0 is silent and stops the music players. 1 is unity on the Music bus.
func set_music_linear(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	var was := _music_mode
	if v <= 0.0000001:
		_music_linear = 0.0
		_music_db = MUSIC_SILENT_DB
		_music_halt()
	else:
		_music_linear = v
		_music_db = linear_to_db(v)
	_apply_buses()
	_save_settings()
	if v > 0.0000001 and not was.is_empty() and _key_in.is_empty():
		note_presentation(was)


func note_presentation(mode: String) -> void:
	var m := mode.strip_edges().to_lower()
	if m != "menu" and m != "game":
		return
	_music_mode = m
	if m == "menu":
		_music_request("music_menu")
		return
	_music_request("" if _player_at_war() else "music_peace")


func notify_mv1_move_committed() -> void:
	play("order_move")


func notify_assault_ordered() -> void:
	play("order_attack")


func notify_province_outcome(winner: String, line: String) -> void:
	var key := "map"
	if typeof(LandBattleSfx) != TYPE_NIL:
		key = str(LandBattleSfx.key_for_aar(winner, line))
	if key.is_empty():
		return
	play(key)


func music_incoming_key() -> String:
	return _key_in


func music_outgoing_key() -> String:
	return _key_out


func music_incoming_playing() -> bool:
	return _mus_in != null and _mus_in.playing


func music_outgoing_playing() -> bool:
	return _mus_out != null and _mus_out.playing


func music_incoming_gain() -> float:
	return _gain_in


func music_outgoing_gain() -> float:
	return _gain_out


func music_gain_trace() -> Array:
	return _gain_trace.duplicate()


func music_duck_db() -> float:
	return _music_duck_db


func music_duck_span_ms() -> int:
	return _music_duck_span_ms


func music_bus_db() -> float:
	var idx := AudioServer.get_bus_index("Music")
	if idx < 0:
		return 99.0
	return AudioServer.get_bus_volume_db(idx)


func service_music(delta: float) -> void:
	if _fading:
		var step := 0.0
		if MUSIC_FADE_SEC > 0.0:
			step = maxf(0.0, delta) / MUSIC_FADE_SEC
		_fade_t = minf(1.0, _fade_t + step)
		_apply_music_gains()
		_gain_trace.append({"in": _gain_in, "out": _gain_out, "key": _key_in})
		if _gain_trace.size() > 240:
			_gain_trace.pop_front()
		if _fade_t >= 1.0:
			_finish_fade()
	_tick_music_duck(Time.get_ticks_msec())
	if not _fading and _music_duck_until_ms <= 0:
		set_process(false)


func forget_cached_stream(key: String) -> void:
	_streams.erase(key)


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
	_music_linear = clampf(float(cf.get_value("audio", "music_linear", db_to_linear(MUSIC_DEFAULT_DB))), 0.0, 1.0)
	if _music_linear <= 0.0000001:
		_music_linear = 0.0
		_music_db = MUSIC_SILENT_DB
		_music_halt()
	else:
		_music_db = linear_to_db(_music_linear)
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
	var entry := _entry(key)
	if not entry.is_empty() and str(entry.get("bus", "")) == "Music":
		return _music_request(key)
	_remember(key)
	if _muted:
		return false
	var now := Time.get_ticks_msec()
	if key == "ui_hover":
		if now - _last_hover_ms < HOVER_GAP_MS:
			return false
		_last_hover_ms = now
	if entry.is_empty():
		_warn_once(key)
		return false
	var stream := _resolve_stream(key, entry)
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
	if key == "end_victory_sting" or key == "end_defeat_sting":
		_arm_music_duck(stream)
	return true


func _on_game_day(_year: int, _month: int, _day: int) -> void:
	_music_sync_war()
	if not day_tick_allowed():
		return
	play("day_tick")


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node as BaseButton)
	if str(node.name) == "WorldMap":
		call_deferred("_refresh_music_scene")


## One ui_click per control per frame. Live-pointer code calls this, and
## `pressed` calls it again; the second call in that frame does not play.
var _ui_click_latch: Dictionary = {}


func play_ui_click(source: Object = null) -> bool:
	var frame := Engine.get_process_frames()
	var sid := 0
	if source != null and is_instance_valid(source):
		sid = source.get_instance_id()
	var key := "%d:%d" % [sid, frame]
	if bool(_ui_click_latch.get(key, false)):
		return false
	if _ui_click_latch.size() > 48:
		_ui_click_latch.clear()
	_ui_click_latch[key] = true
	return play("ui_click")


## Live-pointer activation. Emits `pressed` once per control per frame and
## plays one click even when that emit also reaches `_on_ui_pressed`.
func activate_button(btn: BaseButton) -> bool:
	if btn == null or not is_instance_valid(btn) or btn.disabled:
		return false
	var frame := Engine.get_process_frames()
	if int(btn.get_meta("_eoa_live_press_frame", -999999)) == frame:
		return false
	btn.set_meta("_eoa_live_press_frame", frame)
	play_ui_click(btn)
	btn.pressed.emit()
	return true


func _on_ui_pressed(btn: BaseButton = null) -> void:
	play_ui_click(btn)


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
	var press_cb := _on_ui_pressed.bind(btn)
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
		if str(_entry(key).get("bus", "")) == "Music":
			continue
		var path := str(_entry(key).get("path", ""))
		if path.is_empty() or not _res_exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		_arm_loop(key, stream)
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
	var music_db := _music_db
	if _music_linear <= 0.0000001:
		music_db = MUSIC_SILENT_DB
	else:
		music_db = _music_db + _music_duck_db
	_set_bus("Music", music_db, false)


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
	cf.set_value("audio", "music_linear", _music_linear)
	cf.set_value("audio", "music_db", _music_db)
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


func _process(delta: float) -> void:
	service_music(delta)


func _resolve_stream(key: String, entry: Dictionary) -> AudioStream:
	var cached := _streams.get(key) as AudioStream
	if cached != null:
		return cached
	var path := str(entry.get("path", ""))
	if not path.is_empty() and _res_exists(path):
		var loaded := load(path) as AudioStream
		if loaded != null:
			_arm_loop(key, loaded)
			_streams[key] = loaded
			return loaded
	var fb := str(WAV_FALLBACK.get(key, ""))
	if fb.is_empty() or not _res_exists(fb):
		return null
	_warn_once(key)
	var wav := load(fb) as AudioStream
	if wav == null:
		return null
	_streams[key] = wav
	return wav


func _arm_loop(key: String, stream: AudioStream) -> void:
	if not (stream is AudioStreamOggVorbis):
		return
	var ogg := stream as AudioStreamOggVorbis
	if str(_entry(key).get("bus", "")) == "Music":
		ogg.loop = true
	elif key.begins_with("end_"):
		ogg.loop = false


func _build_music() -> void:
	_mus_in = AudioStreamPlayer.new()
	_mus_in.name = "MusicIn"
	_mus_in.bus = "Music"
	add_child(_mus_in)
	_mus_out = AudioStreamPlayer.new()
	_mus_out.name = "MusicOut"
	_mus_out.bus = "Music"
	add_child(_mus_out)


func _music_request(key: String) -> bool:
	if key == _key_in and (key.is_empty() or (_mus_in != null and _mus_in.playing)):
		return _music_linear > 0.0 and not _muted
	if not key.is_empty():
		_remember(key)
	if _muted or _music_linear <= 0.0000001:
		if _music_linear <= 0.0000001:
			_music_halt()
		return false
	var stream: AudioStream = null
	if not key.is_empty():
		stream = _resolve_stream(key, _entry(key))
		if stream == null:
			_warn_once(key)
			return false
	if _mus_in == null or _mus_out == null:
		_build_music()
	var prev := _mus_in
	_mus_in = _mus_out
	_mus_out = prev
	_key_out = _key_in
	_key_in = key
	if stream != null:
		_mus_in.stream = stream
		_mus_in.bus = "Music"
		_mus_in.play()
	else:
		_mus_in.stop()
		_mus_in.stream = null
	_fade_t = 0.0
	_fading = true
	_gain_trace.clear()
	_apply_music_gains()
	_gain_trace.append({"in": _gain_in, "out": _gain_out, "key": _key_in})
	set_process(true)
	return true


func _apply_music_gains() -> void:
	var inn := 1.0
	var outg := 0.0
	if _fading:
		inn = _fade_t
		outg = 1.0 - _fade_t
	_gain_in = inn
	_gain_out = outg
	_set_music_gain(_mus_in, _key_in, inn)
	_set_music_gain(_mus_out, _key_out, outg)


func _set_music_gain(player: AudioStreamPlayer, key: String, gain: float) -> void:
	if player == null:
		return
	var trim := -6.0
	if not key.is_empty():
		trim = float(_entry(key).get("volume_db", -6.0))
	var gdb := MUSIC_SILENT_DB
	if gain > 0.0001:
		gdb = linear_to_db(gain)
	player.volume_db = trim + gdb


func _finish_fade() -> void:
	_fading = false
	_fade_t = 1.0
	if _mus_out != null:
		_mus_out.stop()
		_mus_out.stream = null
	_key_out = ""
	if _key_in.is_empty() and _mus_in != null:
		_mus_in.stop()
		_mus_in.stream = null
	_apply_music_gains()


func _music_halt() -> void:
	_fading = false
	_fade_t = 1.0
	_key_in = ""
	_key_out = ""
	_gain_in = 0.0
	_gain_out = 0.0
	if _mus_in != null:
		_mus_in.stop()
		_mus_in.stream = null
	if _mus_out != null:
		_mus_out.stop()
		_mus_out.stream = null
	_music_duck_db = 0.0
	_music_duck_until_ms = 0


func _arm_music_duck(stream: AudioStream) -> void:
	if _music_linear <= 0.0000001:
		return
	var span := _length_ms(stream)
	_music_duck_span_ms = span
	_music_duck_until_ms = Time.get_ticks_msec() + span
	_music_duck_db = MUSIC_DUCK_DB
	_apply_buses()
	set_process(true)


func _tick_music_duck(now_ms: int) -> void:
	if _music_duck_until_ms <= 0:
		return
	if now_ms < _music_duck_until_ms:
		return
	_music_duck_db = 0.0
	_music_duck_until_ms = 0
	_apply_buses()


func _music_sync_war() -> void:
	if _music_mode != "game" or _music_linear <= 0.0000001:
		return
	var want := "" if _player_at_war() else "music_peace"
	if want == _key_in:
		return
	_music_request(want)


## Read campaign_wars only when it already exists. Do not call WarStateDomain._state().
func _player_at_war() -> bool:
	if typeof(GameData) == TYPE_NIL:
		return false
	var peace: Variant = GameData.peace_state
	if typeof(peace) != TYPE_DICTIONARY:
		return false
	var pd: Dictionary = peace
	if not pd.has("campaign_wars"):
		return false
	var cw: Variant = pd.get("campaign_wars")
	if typeof(cw) != TYPE_DICTIONARY:
		return false
	var wars: Variant = (cw as Dictionary).get("wars", null)
	if typeof(wars) != TYPE_DICTIONARY or (wars as Dictionary).is_empty():
		return false
	var tag := ""
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		tag = str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	if tag.is_empty():
		return false
	var wd: Dictionary = wars
	for k in wd.keys():
		var row: Variant = wd[k]
		if typeof(row) == TYPE_DICTIONARY:
			var rd: Dictionary = row
			if str(rd.get("a", "")).to_upper() == tag or str(rd.get("b", "")).to_upper() == tag:
				return true
			if str(rd.get("attacker", "")).to_upper() == tag or str(rd.get("defender", "")).to_upper() == tag:
				return true
		elif tag in str(k).to_upper():
			return true
	return false


func _refresh_music_scene() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var open_title := false
	var closed_title := false
	var menu := false
	var map := false
	for c in tree.root.get_children():
		var n := str(c.name)
		if n.begins_with("LivingTitleBoot") and ("_closed" in c):
			if bool(c.get("_closed")):
				closed_title = true
			else:
				open_title = true
		elif n == "MainMenu":
			menu = true
		elif n == "WorldMap":
			map = true
	if open_title or menu:
		note_presentation("menu")
	elif closed_title and map:
		note_presentation("game")
	elif map and _music_mode.is_empty():
		note_presentation("game")
