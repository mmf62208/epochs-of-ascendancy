extends SceneTree

## SR1 test C. Scripted mid-war facts survive save and load.
const _Hash = preload("res://scripts/core/SaveStateHash.gd")
const _Io = preload("res://scripts/core/SaveReload1Io.gd")

var _failures := 0
var _sl
var _tm
var _gd
var _sm
var _mm
var _bm
var _lm
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _created: Array[String] = []


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveReload1MidWarTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveReload1MidWarTest: ", msg)


func _run() -> void:
	_sl = get_root().get_node_or_null("SaveLoadManager")
	_tm = get_root().get_node_or_null("TimeManager")
	_gd = get_root().get_node_or_null("GameData")
	_sm = get_root().get_node_or_null("SupplyManager")
	_mm = get_root().get_node_or_null("MapManager")
	_bm = get_root().get_node_or_null("BattleManager")
	_lm = get_root().get_node_or_null("LeaderManager")
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if _sl == null or _tm == null or _war == null or _cap == null or _end == null:
		_fail("autoloads missing")
		_finish()
		return
	var mw := load("res://scripts/core/SaveReload1Mw200.gd") as GDScript
	if mw == null:
		_fail("MW200 helper failed to compile")
		_finish()
		return
	var built: Dictionary = mw.build("sr1test_c_pristine")
	_track("sr1test_c_pristine")
	print("MW200 ", built)
	if not bool(built.get("ok", false)):
		_fail("MW200 fixture: %s" % str(built.get("error", built)))
		_finish()
		return
	if not _save_ok("sr1test_c_mw"):
		_finish()
		return
	_check_justify(str(built.get("justify_tag", "")))
	_reload_mw()
	_check_battle()
	_reload_mw()
	_check_truce_and_progress()
	_reload_mw()
	_check_capitulation_day()
	_reload_mw()
	_check_defeat_and_keep_playing()
	_check_killswitch()
	_check_v1_over_war()
	_cleanup()
	_finish()


func _check_justify(tag: String) -> void:
	if tag.is_empty():
		_fail("MW200 did not name a justify tag")
		return
	var left := int(_war.player_justify_days_left(tag))
	if left != 8:
		_fail("justify %s has %d days left (want 8 of 14)" % [tag, left])
		return
	var ready := int(_tm.get_total_days_elapsed()) + left
	if not _save_ok("sr1test_c_just"):
		return
	_tm.paused = false
	_tm.advance_live_f5_equivalent_days(2)
	if not _load_ok("sr1test_c_just"):
		return
	if int(_war.player_justify_days_left(tag)) != 8:
		_fail("justify days left changed across load")
		return
	_tm.paused = false
	for i in range(left - 1):
		var adv: Dictionary = _tm.advance_live_f5_equivalent_days(1)
		if not bool(adv.get("ok", false)):
			_fail("justify advance failed")
			return
		if bool(_war.player_justify_is_ready_for(tag)):
			_fail("justify %s became ready on day %d (want %d)" % [tag, int(_tm.get_total_days_elapsed()), ready])
			return
	_tm.paused = false
	var last: Dictionary = _tm.advance_live_f5_equivalent_days(1)
	if not bool(last.get("ok", false)):
		_fail("justify ready-day advance failed")
		return
	if int(_tm.get_total_days_elapsed()) != ready or not bool(_war.player_justify_is_ready_for(tag)):
		_fail("justify %s ready=%s day=%s want %s" % [tag, str(_war.player_justify_is_ready_for(tag)), str(_tm.get_total_days_elapsed()), str(ready)])
		return
	var pid := _pid_owned(tag)
	var declared: Dictionary = _war.player_declare_from_province(pid)
	if not bool(declared.get("ok", false)) or not bool(_war.is_at_war("GER", tag)):
		_fail("declare %s failed %s" % [tag, str(declared)])
		return
	_pass("justify %s completed on day %d and declared" % [tag, ready])


func _check_battle() -> void:
	if not _save_ok("sr1test_c_battle"):
		return
	var control := _play_battle(4)
	if control.is_empty():
		return
	if not _load_ok("sr1test_c_battle"):
		return
	var again := _play_battle(4)
	if again != control:
		_fail("battle result diverged after load")
		print("BATTLE_A ", control.substr(0, 500))
		print("BATTLE_B ", again.substr(0, 500))
		return
	_pass("open battle result, AAR and casualties match after load")


func _play_battle(days: int) -> String:
	_tm.paused = false
	for _i in days:
		var adv: Dictionary = _tm.advance_live_f5_equivalent_days(1)
		if not bool(adv.get("ok", false)):
			_fail("battle advance failed %s" % str(adv))
			return ""
	var battles: Array = _bm.get_open_land_battles() if _bm != null and _bm.has_method("get_open_land_battles") else []
	var aar: Dictionary = {}
	if _bm != null and _bm.has_method("peek_last_land_aar"):
		var raw: Variant = _bm.peek_last_land_aar()
		if raw is Dictionary:
			aar = raw
	return "%s|%s|%s|%s" % [
		_canon(battles),
		_canon(aar),
		_strength("sr1_ger_att"),
		_strength("sr1_pol_def"),
	]


func _check_truce_and_progress() -> void:
	var wars: Dictionary = _wars()
	var truces: Dictionary = wars.get("truces", {}) if wars.get("truces") is Dictionary else {}
	var key := "FIN|SOV"
	if not truces.has(key):
		_fail("truce %s missing" % key)
		return
	var until := int(truces[key])
	var prog := float(_cap.progress("POL"))
	if not _save_ok("sr1test_c_truce"):
		return
	_sm.player_tag = "ZZZ"
	_tm.current_hour = 3
	if not _load_ok("sr1test_c_truce"):
		return
	var truces2: Dictionary = _wars().get("truces", {}) if _wars().get("truces") is Dictionary else {}
	var prog2 := float(_cap.progress("POL"))
	if int(truces2.get(key, -1)) != until or absf(prog2 - prog) > 0.000001:
		_fail("truce/progress changed until %s->%s progress %s->%s" % [str(until), str(truces2.get(key, -1)), str(prog), str(prog2)])
		return
	_pass("truce until_day=%d and POL progress %.4f survived load" % [until, prog])


func _check_capitulation_day() -> void:
	var tag := _minor_target()
	if tag.is_empty():
		_fail("no minor left to capitulate")
		return
	var declared: Dictionary = _war.declare_war("GER", tag, "sr1-cap")
	if not bool(declared.get("ok", false)):
		_fail("declare %s failed %s" % [tag, str(declared)])
		return
	_tm.paused = false
	if not bool(_tm.advance_live_f5_equivalent_days(1).get("ok", false)):
		_fail("snapshot day failed")
		return
	if bool(_cap.is_capitulated(tag)):
		_fail("%s capitulated before the scheduled day" % tag)
		return
	if not _save_ok("sr1test_c_cap"):
		return
	var control := _cross_threshold(tag)
	if control.is_empty():
		return
	if not _load_ok("sr1test_c_cap"):
		return
	var again := _cross_threshold(tag)
	if again != control:
		_fail("capitulation day diverged %s vs %s" % [control, again])
		return
	var caps: Array = _cap.capitulated_tags()
	var settlements := _settlement_losers()
	if settlements.size() != caps.size():
		_fail("settlements %d != capitulations %d" % [settlements.size(), caps.size()])
		return
	_pass("capitulation of %s fired on the same day and settlements match (%d)" % [tag, settlements.size()])


func _cross_threshold(tag: String) -> String:
	_tm.paused = false
	if not bool(_tm.advance_live_f5_equivalent_days(2).get("ok", false)):
		_fail("pre-threshold advance failed")
		return ""
	if bool(_cap.is_capitulated(tag)):
		_fail("%s capitulated before the crossing day" % tag)
		return ""
	_occupy(tag, "GER")
	var before := int(_tm.get_total_days_elapsed())
	_tm.paused = false
	if not bool(_tm.advance_live_f5_equivalent_days(1).get("ok", false)):
		_fail("threshold day failed")
		return ""
	if not bool(_cap.is_capitulated(tag)):
		_fail("%s did not capitulate on day %d progress=%.3f" % [tag, int(_tm.get_total_days_elapsed()), float(_cap.progress(tag))])
		return ""
	if int(_tm.get_total_days_elapsed()) != before + 1:
		_fail("threshold day moved by more than 1")
		return ""
	return "%s@%d:%s" % [tag, int(_tm.get_total_days_elapsed()), ",".join(_settlement_losers())]


func _check_defeat_and_keep_playing() -> void:
	_occupy("GER", "POL")
	var elapsed := int(_tm.get_total_days_elapsed())
	_tm.paused = false
	var adv: Dictionary = _tm.advance_live_f5_equivalent_days(1)
	if not bool(_cap.is_capitulated("GER")) or not bool(_end.latched()):
		_fail("GER defeat did not latch (advanced=%s cap=%s end=%s)" % [str(adv), str(_cap.is_capitulated("GER")), str(_end.view_model())])
		return
	var model := str(_end.view_model())
	if not _save_ok("sr1test_c_defeat"):
		return
	var locked_elapsed := int(_tm.get_total_days_elapsed())
	_tm.paused = false
	var blocked: Dictionary = _tm.advance_live_f5_equivalent_days(20)
	if int(_tm.get_total_days_elapsed()) != locked_elapsed or not bool(_end.clock_locked()):
		_fail("defeat clock advanced %s -> %s blocked=%s" % [str(locked_elapsed), str(_tm.get_total_days_elapsed()), str(blocked)])
		return
	if not _load_ok("sr1test_c_defeat"):
		return
	var loaded_model := str(_end.view_model())
	if loaded_model != model or not bool(_end.clock_locked()) or not bool(_tm.paused):
		_fail("loaded defeat model/lock mismatch locked=%s paused=%s model_eq=%s" % [str(_end.clock_locked()), str(_tm.paused), str(loaded_model == model)])
		return
	if bool(_war.ai_stopped()) != true:
		_fail("AI did not stop on a latched defeat")
		return
	var after_load := int(_tm.get_total_days_elapsed())
	_tm.paused = false
	_tm.advance_live_f5_equivalent_days(20)
	if int(_tm.get_total_days_elapsed()) != after_load:
		_fail("loaded defeat clock ran")
		return
	_pass("latched defeat stayed locked across load (from day %d)" % elapsed)
	_end.set_keep_playing()
	if not _save_ok("sr1test_c_keep"):
		return
	if not _load_ok("sr1test_c_keep"):
		return
	if bool(_end.clock_locked()):
		_fail("keep_playing load left the clock locked")
		return
	var keep_day := int(_tm.get_total_days_elapsed())
	_tm.paused = false
	var ran: Dictionary = _tm.advance_live_f5_equivalent_days(1)
	if not bool(ran.get("ok", false)) or int(_tm.get_total_days_elapsed()) != keep_day + 1:
		_fail("keep_playing clock did not run %s" % str(ran))
		return
	_pass("keep_playing clock runs after load")


func _check_killswitch() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "0")
	_war.reset_for_test()
	_cap.reset_for_test()
	_end.reset_for_test()
	if not _save_ok("sr1test_c_off"):
		OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
		return
	_gd.peace_state["campaign_wars"] = {"wars": {"GER|POL": {"a": "GER", "b": "POL"}}, "truces": {}, "log": [], "justifies": {}}
	if not _load_ok("sr1test_c_off"):
		OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
		return
	var wars: Dictionary = _wars().get("wars", {}) if _wars().get("wars") is Dictionary else {}
	var end: Dictionary = _gd.peace_state.get("campaign_end", {}) if _gd.peace_state.get("campaign_end") is Dictionary else {}
	var caps: Dictionary = {}
	var raw_c: Variant = _gd.peace_state.get("campaign_capitulation", {})
	if raw_c is Dictionary:
		var raw_caps: Variant = (raw_c as Dictionary).get("capitulated", {})
		if raw_caps is Dictionary:
			caps = raw_caps
	if not wars.is_empty() or end.has("outcome") or not caps.is_empty():
		_fail("killswitch load kept campaign state wars=%d end=%s caps=%d" % [wars.size(), str(end.get("outcome", "")), caps.size()])
	else:
		_pass("killswitch save/load left campaign sections empty")
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")


func _check_v1_over_war() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	_gd.peace_state["campaign_wars"] = {
		"wars": {"GER|POL": {"a": "GER", "b": "POL"}},
		"truces": {},
		"log": [],
		"justifies": {},
		"booted": true,
	}
	var src := _Io.V1_DAY0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(src))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("v1 fixture unreadable")
		return
	var root: Dictionary = parsed
	var game: Dictionary = root.get("game_data", {}) if root.get("game_data") is Dictionary else {}
	for key in ["campaign_wars", "campaign_capitulation", "campaign_end", "peace_settlements", "peace_settlement_count", "peace_last_settlement", "war_goals", "war_goal_tick_count"]:
		game.erase(key)
	root["game_data"] = game
	var path := ProjectSettings.globalize_path("user://saves/sr1test_c_v1strip.json")
	_created.append(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write stripped v1")
		return
	f.store_string(JSON.stringify(root))
	f.close()
	if not _load_ok("sr1test_c_v1strip"):
		return
	var wars: Dictionary = _wars().get("wars", {}) if _wars().get("wars") is Dictionary else {}
	if not wars.is_empty():
		_fail("stripped v1 left %d wars" % wars.size())
		return
	_tm.paused = false
	var adv: Dictionary = _tm.advance_live_f5_equivalent_days(2)
	if not bool(adv.get("ok", false)):
		_fail("post-v1 advance failed %s" % str(adv))
		return
	_pass("stripped v1 cleared a running war")


func _reload_mw() -> bool:
	return _load_ok("sr1test_c_mw")


func _save_ok(slot: String) -> bool:
	var saved: Dictionary = _sl.save_game_detailed(slot)
	_track(slot)
	if not bool(saved.get("ok", false)):
		_fail("save %s failed: %s" % [slot, str(saved.get("error", ""))])
		return false
	return true


func _load_ok(slot: String) -> bool:
	var loaded: Dictionary = _sl.load_game_detailed(slot)
	if not bool(loaded.get("ok", false)):
		_fail("load %s failed: %s" % [slot, str(loaded.get("error", ""))])
		return false
	return true


func _wars() -> Dictionary:
	var raw: Variant = _gd.peace_state.get("campaign_wars", {})
	if raw is Dictionary:
		return raw
	return {}


func _minor_target() -> String:
	for tag in ["DEN", "BEL", "HOL", "SWI", "LIT", "EST", "LAT"]:
		if bool(_war.is_at_war("GER", tag)) or bool(_war.in_truce("GER", tag)):
			continue
		if _pid_owned(tag) > 0:
			return tag
	return ""


func _pid_owned(tag: String) -> int:
	if _mm == null or not _mm.has_method("get_provinces_by_owner"):
		return -1
	var pids: Array = _mm.call("get_provinces_by_owner", tag)
	pids.sort()
	if pids.is_empty():
		return -1
	return int(pids[0])


func _occupy(tag: String, holder: String) -> void:
	if _mm == null:
		return
	var pids: Array = _mm.call("get_provinces_by_owner", tag)
	pids.sort()
	if _sm != null and _sm.has_method("begin_control_batch"):
		_sm.call("begin_control_batch")
	for pid_v in pids:
		var pid := int(pid_v)
		var p: Object = _mm.call("get_province", pid)
		if p == null:
			continue
		_mm.call("update_province_owner", pid, holder, holder, true, true)
	if _sm != null and _sm.has_method("end_control_batch"):
		_sm.call("end_control_batch")


func _strength(fid: String) -> String:
	if _lm == null or not _lm.has_method("get_formation"):
		return ""
	var f: Variant = _lm.get_formation(fid)
	if f == null:
		return "missing"
	return "%.6f" % float(f.strength)


func _settlement_losers() -> PackedStringArray:
	var out: PackedStringArray = []
	var raw: Variant = _gd.peace_state.get("peace_settlements", [])
	if not (raw is Array):
		return out
	for row in raw:
		if row is Dictionary:
			out.append(str((row as Dictionary).get("loser_tag", "")))
	return out


func _canon(v: Variant) -> String:
	var t := typeof(v)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = d.keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		var parts: PackedStringArray = []
		for k in keys:
			parts.append("%s=%s" % [str(k), _canon(d[k])])
		return "{" + ",".join(parts) + "}"
	if t == TYPE_ARRAY:
		var parts2: PackedStringArray = []
		for item in v:
			parts2.append(_canon(item))
		return "[" + ",".join(parts2) + "]"
	if t == TYPE_FLOAT:
		return "%.6f" % float(v)
	return str(v)


func _track(slot: String) -> void:
	_created.append(ProjectSettings.globalize_path("user://saves/%s.eoasave" % slot))
	_created.append(ProjectSettings.globalize_path("user://saves/%s.eoasave.bak" % slot))
	_created.append(ProjectSettings.globalize_path("user://saves/%s.eoasave.tmp" % slot))
	_created.append(ProjectSettings.globalize_path("user://saves/%s.json" % slot))


func _cleanup() -> void:
	for path in _created:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _finish() -> void:
	if _failures == 0:
		print("HeadlessSaveReload1MidWarTest: RESULT=PASS")
		quit(0)
	else:
		print("HeadlessSaveReload1MidWarTest: RESULT=FAIL")
		quit(1)
