extends SceneTree

## SR1 test D. Corrupt and missing saves fail closed: hash unchanged, no apply.
const _Fmt = preload("res://scripts/core/SaveFormat.gd")
const _Hash = preload("res://scripts/core/SaveStateHash.gd")

var _failures := 0
var _boot: GDScript
var _created: Array[String] = []
var _sl
var _tm


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveReload1CorruptTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveReload1CorruptTest: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_sl = get_root().get_node_or_null("SaveLoadManager")
	_tm = get_root().get_node_or_null("TimeManager")
	if mm == null or _boot == null or _sl == null or _tm == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.boot(mm, sm, "GER"):
		_fail("boot failed")
		_finish()
		return
	var good := _gather()
	var encoded: Dictionary = _Fmt.encode(good, {"kind": "manual"})
	if not bool(encoded.get("ok", false)):
		_fail("encode baseline failed: %s" % str(encoded.get("error", "")))
		_finish()
		return
	var blob: PackedByteArray = encoded.get("bytes", PackedByteArray())
	_pass("baseline envelope %d bytes" % blob.size())
	_expect_reject("sr1test_d_missing", PackedByteArray(), true)
	_write_user("sr1test_d_zero", PackedByteArray())
	_expect_reject("sr1test_d_zero", PackedByteArray(), false)
	_write_user("sr1test_d_trunc", blob.slice(0, maxi(1, int(blob.size() / 2))))
	_expect_reject("sr1test_d_trunc", PackedByteArray(), false)
	var flipped := blob.duplicate()
	flipped[flipped.size() - 1] = flipped[flipped.size() - 1] ^ 0xFF
	_write_user("sr1test_d_flip", flipped)
	_expect_reject("sr1test_d_flip", PackedByteArray(), false)
	var magic := blob.duplicate()
	magic[0] = 88
	_write_user("sr1test_d_magic", magic)
	_expect_reject("sr1test_d_magic", PackedByteArray(), false)
	_write_user("sr1test_d_ver", _with_version(blob, 99))
	_expect_reject("sr1test_d_ver", PackedByteArray(), false)
	_write_user("sr1test_d_header", _bad_header())
	_expect_reject("sr1test_d_header", PackedByteArray(), false)
	var no_map := good.duplicate(true)
	no_map.erase("map")
	_write_encoded("sr1test_d_nomap", no_map)
	_expect_reject("sr1test_d_nomap", PackedByteArray(), false)
	var bad_lw := good.duplicate(true)
	bad_lw["land_war"] = "not-a-dict"
	_write_encoded("sr1test_d_lw", bad_lw)
	_expect_reject("sr1test_d_lw", PackedByteArray(), false)
	var scen := good.duplicate(true)
	if typeof(scen.get("metadata", null)) != TYPE_DICTIONARY:
		scen["metadata"] = {}
	scen["metadata"]["scenario_id"] = "1936"
	_write_encoded("sr1test_d_scenario", scen)
	_sl.scenario_guard = "not-the-running-scenario"
	_expect_reject("sr1test_d_scenario", PackedByteArray(), false)
	_sl.scenario_guard = ""
	_write_json("sr1test_d_array", "[1, 2, 3]")
	_expect_reject("sr1test_d_array", PackedByteArray(), false)
	_expect_quickload_reject("sr1test_d_lw")
	_expect_quickload_reject("sr1test_d_array")
	_expect_write_failure(good)
	_expect_crash_mid_write(good)
	_expect_v1_fixture_loads()
	_cleanup()
	_finish()


func _expect_reject(slot: String, _unused: PackedByteArray, missing: bool) -> void:
	var before := _hash()
	var res: Dictionary = _sl.load_game_detailed(slot)
	var after := _hash()
	if bool(res.get("ok", false)):
		_fail("%s load returned ok" % slot)
		return
	if str(res.get("error", "")).strip_edges().is_empty():
		_fail("%s empty error" % slot)
		return
	if before != after:
		_fail("%s hash changed %s -> %s" % [slot, before, after])
		return
	var status: Dictionary = _sl.slot_status(slot)
	if missing:
		if not bool(status.get("missing", false)):
			_fail("%s should be missing" % slot)
			return
	elif not bool(status.get("damaged", false)):
		_fail("%s should be damaged (%s)" % [slot, str(status)])
		return
	var adv: Dictionary = _tm.advance_live_f5_equivalent_days(2)
	if not bool(adv.get("ok", false)) and not bool(adv.get("locked", false)):
		_fail("%s did not keep running: %s" % [slot, str(adv)])
		return
	_pass("%s rejected (%s)" % [slot, str(res.get("error", ""))])


func _expect_quickload_reject(slot: String) -> void:
	var before := _hash()
	_sl.quickload_slot_override = slot
	var ok := bool(_sl.quickload())
	var after := _hash()
	if ok:
		_fail("quickload %s returned ok" % slot)
		return
	if before != after:
		_fail("quickload %s hash changed" % slot)
		return
	var err := str(_sl.last_load_result.get("error", ""))
	if slot.ends_with("_lw") and not err.contains("land_war"):
		_fail("quickload %s error missing land_war: %s" % [slot, err])
		return
	if err.strip_edges().is_empty():
		_fail("quickload %s empty error" % slot)
		return
	_pass("quickload %s rejected (%s)" % [slot, err])


func _expect_write_failure(good: Dictionary) -> void:
	var slot := "sr1test_d_atomic"
	var first: Dictionary = _sl.save_game_detailed(slot)
	if not bool(first.get("ok", false)):
		_fail("atomic baseline save failed: %s" % str(first.get("error", "")))
		return
	var path := ProjectSettings.globalize_path(str(first.get("path", "")))
	_created.append(path)
	var before := FileAccess.get_file_as_bytes(path)
	_Fmt.test_fail_write = true
	var second: Dictionary = _sl.save_game_detailed(slot)
	_Fmt.test_fail_write = false
	var after := FileAccess.get_file_as_bytes(path)
	var tmp := path + ".tmp"
	if bool(second.get("ok", false)):
		_fail("injected write failure returned ok")
		return
	if before != after:
		_fail("write failure changed the previous save")
		return
	if FileAccess.file_exists(tmp):
		_fail("write failure left a tmp")
		return
	_pass("write failure kept previous bytes")


func _expect_crash_mid_write(good: Dictionary) -> void:
	var slot := "sr1test_d_crash"
	var first: Dictionary = _sl.save_game_detailed(slot)
	if not bool(first.get("ok", false)):
		_fail("crash baseline save failed")
		return
	var path := ProjectSettings.globalize_path(str(first.get("path", "")))
	_created.append(path)
	var before := FileAccess.get_file_as_bytes(path)
	_Fmt.test_stop_after_tmp = true
	var crashed: Dictionary = _sl.save_game_detailed(slot)
	_Fmt.test_stop_after_tmp = false
	if bool(crashed.get("ok", false)) or not bool(crashed.get("crashed_after_tmp", false)):
		_fail("crash hook did not stop after tmp: %s" % str(crashed))
		return
	if FileAccess.get_file_as_bytes(path) != before:
		_fail("crash hook changed the previous save")
		return
	var loaded: Dictionary = _sl.read_save_body(slot)
	if loaded.has("ok") and not bool(loaded.get("ok", false)):
		_fail("previous save unreadable after crash hook")
		return
	if not FileAccess.file_exists(path + ".tmp"):
		_fail("crash hook removed the tmp")
		return
	var nxt: Dictionary = _sl.save_game_detailed(slot)
	if not bool(nxt.get("ok", false)):
		_fail("save after crash hook failed: %s" % str(nxt.get("error", "")))
		return
	if FileAccess.file_exists(path + ".tmp"):
		_fail("next save left a tmp")
		return
	_pass("crash mid-write kept the old save")
	good.size()


func _expect_v1_fixture_loads() -> void:
	var src := "/home/featherstone/save1_evidence/v1_fixtures/sr1test_v1_day0.json"
	if not FileAccess.file_exists(src):
		_fail("v1 day0 fixture missing")
		return
	var slot := "sr1test_d_v1ok"
	var dest := ProjectSettings.globalize_path(_sl.get_save_path(slot))
	_created.append(dest)
	var bytes := FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		_fail("cannot copy v1 fixture")
		return
	f.store_buffer(bytes)
	f.close()
	var res: Dictionary = _sl.load_game_detailed(slot)
	if not bool(res.get("ok", false)):
		_fail("fine v1 failed to load: %s" % str(res.get("error", "")))
		return
	var status: Dictionary = _sl.slot_status(slot)
	if not bool(status.get("old_format", false)):
		_fail("fine v1 not marked old format")
		return
	_tm.paused = false
	var adv: Dictionary = _tm.advance_live_f5_equivalent_days(2)
	if not bool(adv.get("ok", false)):
		_fail("game did not run after v1 load")
		return
	_pass("fine v1 loaded")


func _gather() -> Dictionary:
	return _sl._gather_save_data()


func _hash() -> String:
	return str(_Hash.state_hash(_gather()))


func _write_user(slot: String, bytes: PackedByteArray) -> void:
	var path := ProjectSettings.globalize_path(_sl.get_save_path_v2(slot))
	_created.append(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write %s" % path)
		return
	f.store_buffer(bytes)
	f.close()


func _write_json(slot: String, text: String) -> void:
	var path := ProjectSettings.globalize_path(_sl.get_save_path(slot))
	_created.append(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write %s" % path)
		return
	f.store_string(text)
	f.close()


func _write_encoded(slot: String, body: Dictionary) -> void:
	var encoded: Dictionary = _Fmt.encode(body, {"kind": "manual", "player_tag": "GER", "scenario_id": "1936"})
	if not bool(encoded.get("ok", false)):
		_fail("encode %s failed: %s" % [slot, str(encoded.get("error", ""))])
		return
	_write_user(slot, encoded.get("bytes", PackedByteArray()))


func _with_version(blob: PackedByteArray, ver: int) -> PackedByteArray:
	var header_len := int(blob.decode_u32(8))
	var header: Dictionary = JSON.parse_string(blob.slice(12, 12 + header_len).get_string_from_utf8())
	header["save_version"] = ver
	var header_bytes := JSON.stringify(header).to_utf8_buffer()
	var body := blob.slice(12 + header_len, blob.size())
	var out := PackedByteArray()
	out.append_array("EOASAVE2".to_utf8_buffer())
	var len_bytes := PackedByteArray()
	len_bytes.resize(4)
	len_bytes.encode_u32(0, header_bytes.size())
	out.append_array(len_bytes)
	out.append_array(header_bytes)
	out.append_array(body)
	return out


func _bad_header() -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("EOASAVE2".to_utf8_buffer())
	var len_bytes := PackedByteArray()
	len_bytes.resize(4)
	len_bytes.encode_u32(0, 4)
	out.append_array(len_bytes)
	out.append_array("{{{{".to_utf8_buffer())
	return out


func _cleanup() -> void:
	_Fmt.test_fail_write = false
	_Fmt.test_stop_after_tmp = false
	if _sl != null:
		_sl.scenario_guard = ""
		_sl.quickload_slot_override = ""
	for path in _created:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		if FileAccess.file_exists(path + ".tmp"):
			DirAccess.remove_absolute(path + ".tmp")


func _finish() -> void:
	_cleanup()
	var ok := _failures == 0
	print("HeadlessSaveReload1CorruptTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSaveReload1CorruptTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
