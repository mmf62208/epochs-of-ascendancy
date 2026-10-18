extends SceneTree

## SR1 test A. Full-state hash is unchanged across save, mutate, and load.
const _Hash = preload("res://scripts/core/SaveStateHash.gd")
const _Manifest = preload("res://scripts/core/SaveCoverageManifest.gd")

var _failures := 0
var _sl
var _tm
var _sm
var _gd
var _created: Array[String] = []


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveReload1RoundTripTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveReload1RoundTripTest: ", msg)


func _run() -> void:
	_sl = get_root().get_node_or_null("SaveLoadManager")
	_tm = get_root().get_node_or_null("TimeManager")
	_sm = get_root().get_node_or_null("SupplyManager")
	_gd = get_root().get_node_or_null("GameData")
	var mm := get_root().get_node_or_null("MapManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if _sl == null or _tm == null or mm == null or boot == null:
		_fail("autoloads missing")
		_finish()
		return
	if not bool(boot.boot(mm, _sm, "GER")):
		_fail("boot failed")
		_finish()
		return
	_roundtrip("sr1test_a_d0", "day0")
	_tm.paused = false
	_advance_to(60)
	_roundtrip("sr1test_a_d60", "day60")
	_check_manifest()
	# load() after autoloads exist. A preload of this helper cannot see them.
	var mw := load("res://scripts/core/SaveReload1Mw200.gd") as GDScript
	if mw == null:
		_fail("MW200 helper failed to compile")
		_finish()
		return
	var built: Dictionary = mw.build("sr1test_a_pristine")
	_track_slot("sr1test_a_pristine")
	print("MW200 ", built)
	if not bool(built.get("ok", false)):
		_fail("MW200 fixture: %s" % str(built.get("error", built)))
		_finish()
		return
	_pass("MW200 day=%s wars=%s/%s justify_left=%s battles=%s marches=%s truces=%s settlements=%s" % [
		str(built.get("day", 0)), str(built.get("player_wars", 0)), str(built.get("ai_wars", 0)),
		str(built.get("justify_left", -1)), str(built.get("battles", 0)), str(built.get("marches", 0)),
		str(built.get("truces", 0)), str(built.get("settlements", 0)),
	])
	var h0 := _roundtrip("sr1test_a_mw", "mw200")
	if h0.is_empty():
		_finish()
		return
	var mw_before: Dictionary = _sl._gather_save_data()
	_tm.paused = false
	_advance_to(260)
	_sm.player_tag = "ZZZ"
	_tm.current_hour = 3
	var loaded: Dictionary = _sl.load_game_detailed("sr1test_a_mw")
	var h1 := _hash()
	if not bool(loaded.get("ok", false)):
		_fail("dirtier load failed: %s" % str(loaded.get("error", "")))
	elif h1 != h0:
		_fail("dirtier hash mismatch")
		print("FIRST_DIFF ", _Hash.first_diff(_Hash._strip(mw_before), _Hash._strip(_sl._gather_save_data())))
		print("SECTION_BEFORE ", _Hash.section_hashes(mw_before))
		print("SECTION_AFTER ", _Hash.section_hashes(_sl._gather_save_data()))
	else:
		_pass("dirtier world load restored day-200 hash")
	_load_stripped_v1()
	_cleanup()
	_finish()


func _roundtrip(slot: String, label: String) -> String:
	_tm.current_hour = 7
	var before: Dictionary = _sl._gather_save_data()
	var h0 := str(_Hash.state_hash(before))
	var t0 := Time.get_ticks_usec()
	var saved: Dictionary = _sl.save_game_detailed(slot)
	var save_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_track_slot(slot)
	if not bool(saved.get("ok", false)):
		_fail("%s save failed: %s" % [label, str(saved.get("error", ""))])
		return ""
	var status: Dictionary = _sl.slot_status(slot)
	var meta: Dictionary = status.get("metadata", {}) if status.get("metadata") is Dictionary else {}
	if str(meta.get("player_tag", "")) != "GER":
		_fail("%s metadata player_tag=%s" % [label, str(meta.get("player_tag", ""))])
	if str(meta.get("game_date", "")).is_empty() or str(meta.get("campaign_status", "")).is_empty():
		_fail("%s metadata missing date/status %s" % [label, str(meta)])
	_tm.current_hour = 3
	_sm.player_tag = "ZZZ"
	_tm.paused = false
	var adv: Dictionary = _tm.advance_live_f5_equivalent_days(5)
	if not bool(adv.get("ok", false)):
		_fail("%s mutate advance failed %s" % [label, str(adv)])
		return ""
	var t1 := Time.get_ticks_usec()
	var loaded: Dictionary = _sl.load_game_detailed(slot)
	var load_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	if not bool(loaded.get("ok", false)):
		_fail("%s load failed: %s" % [label, str(loaded.get("error", ""))])
		return ""
	if int(_tm.current_hour) != 7:
		_fail("%s current_hour=%s want 7" % [label, str(_tm.current_hour)])
		return ""
	var h1 := _hash()
	var bytes := int(saved.get("bytes", 0))
	print("PERF %s save_ms=%.1f load_ms=%.1f bytes=%d" % [label, save_ms, load_ms, bytes])
	if h1 != h0:
		_fail("%s hash mismatch" % label)
		print("FIRST_DIFF ", _Hash.first_diff(_Hash._strip(before), _Hash._strip(_sl._gather_save_data())))
		print("SECTION_BEFORE ", _Hash.section_hashes(before))
		print("SECTION_AFTER ", _Hash.section_hashes(_sl._gather_save_data()))
		return ""
	var lm := get_root().get_node_or_null("LeaderManager")
	var want := str(lm.get_player_country_tag()) if lm != null else ""
	if str(_sm.player_tag) != want or want != "GER":
		_fail("%s player tag supply=%s leader=%s" % [label, str(_sm.player_tag), want])
		return ""
	_pass("%s hash matched (%d bytes)" % [label, bytes])
	return h0


func _advance_to(target: int) -> void:
	var guard := 0
	while int(_tm.get_total_days_elapsed()) < target and guard < 40:
		guard += 1
		_tm.paused = false
		var step := mini(20, target - int(_tm.get_total_days_elapsed()))
		_tm.advance_live_f5_equivalent_days(step)


func _check_manifest() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	var in_auto := false
	var missing: PackedStringArray = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("["):
			in_auto = trimmed == "[autoload]"
			continue
		if not in_auto or not trimmed.contains("=\""):
			continue
		var name := trimmed.split("=")[0].strip_edges()
		if _Manifest.autoload_row(name).is_empty():
			missing.append(name)
	if not missing.is_empty():
		_fail("manifest missing autoloads %s" % ", ".join(missing))
	else:
		_pass("manifest covers project autoloads")
	var ps: Dictionary = _gd.peace_state if _gd != null else {}
	var stray: PackedStringArray = []
	for k in ps.keys():
		if _Manifest.peace_row(str(k)).is_empty():
			stray.append(str(k))
	if not stray.is_empty():
		_fail("peace keys missing from manifest: %s" % ", ".join(stray))
	else:
		_pass("manifest covers %d peace keys" % ps.size())


func _load_stripped_v1() -> void:
	var src := "/home/featherstone/save1_evidence/v1_fixtures/sr1test_v1_day0.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(src))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("stripped v1 fixture unreadable")
		return
	var root: Dictionary = parsed
	var gd: Dictionary = root.get("game_data", {}) if root.get("game_data") is Dictionary else {}
	for key in ["campaign_wars", "campaign_capitulation", "campaign_end", "peace_settlements", "peace_settlement_count", "peace_last_settlement", "war_goals", "war_goal_tick_count"]:
		gd.erase(key)
	root["game_data"] = gd
	var slot := "sr1test_a_v1strip"
	var path := ProjectSettings.globalize_path(_sl.get_save_path(slot))
	_created.append(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write stripped v1")
		return
	f.store_string(JSON.stringify(root))
	f.close()
	var loaded: Dictionary = _sl.load_game_detailed(slot)
	if not bool(loaded.get("ok", false)):
		_fail("stripped v1 load failed: %s" % str(loaded.get("error", "")))
		return
	var wars := {}
	var raw: Variant = _gd.peace_state.get("campaign_wars", {})
	if raw is Dictionary:
		var w: Variant = (raw as Dictionary).get("wars", {})
		if w is Dictionary:
			wars = w
	if not (wars as Dictionary).is_empty():
		_fail("stripped v1 left %d stale wars" % (wars as Dictionary).size())
	else:
		_pass("stripped v1 cleared a running war")


func _hash() -> String:
	return str(_Hash.state_hash(_sl._gather_save_data()))


func _print_diff(_h0: String, _h1: String) -> void:
	var now: Dictionary = _sl._gather_save_data()
	print("SECTION_HASHES ", _Hash.section_hashes(now))
	print("HASH now=", _Hash.state_hash(now))


func _track_slot(slot: String) -> void:
	var path := str(ProjectSettings.globalize_path(_sl.get_save_path_v2(slot)))
	if path not in _created:
		_created.append(path)


func _cleanup() -> void:
	if _sl != null:
		for slot in ["sr1test_a_d0", "sr1test_a_d60", "sr1test_a_mw", "sr1test_a_pristine", "sr1test_a_v1strip"]:
			var v2 := ProjectSettings.globalize_path(_sl.get_save_path_v2(slot))
			var v1 := ProjectSettings.globalize_path(_sl.get_save_path(slot))
			for path in [v2, v2 + ".bak", v2 + ".tmp", v1, v1 + ".bak", v1 + ".tmp"]:
				if FileAccess.file_exists(path):
					DirAccess.remove_absolute(path)


func _finish() -> void:
	_cleanup()
	var ok := _failures == 0
	print("HeadlessSaveReload1RoundTripTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSaveReload1RoundTripTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
