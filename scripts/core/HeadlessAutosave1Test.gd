extends SceneTree

## AUTOSAVE-1. Rotator, last_played, session lock, idle pause, settings cfg,
## load-list signal. Seed and TimeManager tick order must stay untouched.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAutosave1Test.gd

const LAST_PLAYED := "last_played"
const BADGE := "LAST PLAYED"
const FENCED := [
	"res://scripts/autoload/GameData.gd",
	"res://scripts/core/AutosaveSessionDomain.gd",
]

var _failures: int = 0
var _signal_hits: int = 0


func _init() -> void:
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "")
	call_deferred("_start")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAutosave1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAutosave1Test: ", msg)


func _start() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessAutosave1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAutosave1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _sl() -> Node:
	return root.get_node_or_null("SaveLoadManager")


func _tm() -> Node:
	return root.get_node_or_null("TimeManager")


func _run() -> void:
	var sl := _sl()
	if sl == null:
		_fail("SaveLoadManager missing")
		return
	_test_fence()
	_test_badge_and_protected_slot(sl)
	_test_settings_cfg(sl)
	_test_n2_redirect(sl)
	_test_rotator_and_session(sl)
	_test_last_played_survives(sl)
	_test_month_year_hooks(sl)
	_test_load_list_signal(sl)
	_test_idle_pause(sl)
	_test_idle_pause_against_tib_watchdog(sl)
	_test_product_day_retired(sl)


func _write_probe(sl: Node, slot: String, unix: int, game_date: String, locked: bool = false, marker: String = "") -> void:
	if sl.has_method("_ensure_save_dir"):
		sl.call("_ensure_save_dir")
	var data := {
		"save_version": 2,
		"metadata": {
			"timestamp_unix": unix,
			"timestamp": "1936-01-01T00:00:00",
			"game_date": game_date,
			"last_played": "1936-01-01T00:00:00",
			"save_kind": str(sl.call("slot_kind", slot)),
			"session_locked": locked,
			"player_tag": "GER",
			"marker": marker,
		},
		"land_war": {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}},
	}
	var path := str(sl.call("get_save_path", slot))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("probe write failed for %s" % slot)
		return
	f.store_string(JSON.stringify(data))
	f.close()


func _read_marker(sl: Node, slot: String) -> String:
	var path := str(sl.call("get_save_path", slot))
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var meta: Dictionary = (parsed as Dictionary).get("metadata", {})
	return str(meta.get("marker", ""))


func _test_fence() -> void:
	for p in FENCED:
		if not FileAccess.file_exists(p):
			_fail("fence missing %s" % p)
			return
	var gd := FileAccess.get_file_as_string("res://scripts/autoload/GameData.gd")
	var domain := FileAccess.get_file_as_string("res://scripts/core/AutosaveSessionDomain.gd")
	if gd.find("pick_rotator_slot") >= 0 or gd.find("LAST_PLAYED_BADGE") >= 0:
		_fail("GameData rewritten for AUTOSAVE-1")
		return
	if domain.find("last_played") >= 0 or domain.find("autosave_1") >= 0:
		_fail("AutosaveSessionDomain touched")
		return
	_pass("fence: GameData and AutosaveSessionDomain untouched")


func _test_badge_and_protected_slot(sl: Node) -> void:
	if str(sl.get("LAST_PLAYED_BADGE")) != BADGE:
		_fail("badge constant is %s" % str(sl.get("LAST_PLAYED_BADGE")))
		return
	if str(sl.call("slot_kind", LAST_PLAYED)) != "auto":
		_fail("last_played slot_kind is not auto")
		return
	if str(sl.call("kind_badge", "auto", LAST_PLAYED)) != BADGE:
		_fail("last_played badge is %s" % str(sl.call("kind_badge", "auto", LAST_PLAYED)))
		return
	var row: Dictionary = sl.call("_format_slot_ui_row", LAST_PLAYED, true, {
		"save_kind": "auto",
		"player_tag": "GER",
		"game_date": "1938-02-14",
		"timestamp": "2026-11-09T19:51:00",
		"timestamp_unix": 1794253860,
	})
	if bool(row.get("can_save", true)):
		_fail("last_played can_save is true")
		return
	if str(row.get("kind_badge", "")) != BADGE:
		_fail("row badge %s" % str(row.get("kind_badge", "")))
		return
	if str(row.get("label", "")).find("Last played") < 0:
		_fail("label missing Last played: %s" % str(row.get("label", "")))
		return
	_pass("N3: last_played is protected auto, badge LAST PLAYED")


func _test_settings_cfg(sl: Node) -> void:
	sl.call("set_autosave_cadence", "yearly")
	sl.call("set_idle_minutes", 5)
	sl.call("reload_autosave_settings")
	if str(sl.call("get_autosave_cadence")) != "yearly":
		_fail("cadence did not persist yearly")
		return
	if int(sl.call("get_idle_minutes")) != 5:
		_fail("idle minutes did not persist 5")
		return
	if not FileAccess.file_exists("user://autosave.cfg"):
		_fail("user://autosave.cfg missing")
		return
	sl.call("set_autosave_cadence", "monthly")
	sl.call("set_idle_minutes", 10)
	_pass("settings persist cadence + idle in user://autosave.cfg")


func _test_n2_redirect(sl: Node) -> void:
	var dest: String = str(sl.call("_redirect_autosave_slot", "autosave"))
	if dest == "autosave" or dest.find("autosave_") != 0:
		_fail("autosave redirect is %s" % dest)
		return
	if str(sl.call("_redirect_autosave_slot", "quicksave")) != "quicksave":
		_fail("quicksave was redirected")
		return
	if str(sl.call("_redirect_autosave_slot", LAST_PLAYED)) != LAST_PLAYED:
		_fail("last_played was redirected")
		return
	_write_probe(sl, "autosave", 10, "1936-01-15", false, "legacy")
	sl.call("pick_rotator_slot")
	if FileAccess.file_exists(str(sl.call("get_save_path", "autosave"))):
		_fail("bare autosave.json still present after migrate")
		return
	if _read_marker(sl, "autosave_1") != "legacy":
		_fail("legacy autosave did not migrate into autosave_1")
		return
	_pass("N2: bare autosave redirects to rotator; migrate-on-write")


func _test_rotator_and_session(sl: Node) -> void:
	sl.call("begin_autosave_session")
	_write_probe(sl, "autosave_1", 100, "1936-02-01", false, "m1")
	_write_probe(sl, "autosave_2", 200, "1936-03-01", false, "m2")
	_write_probe(sl, "autosave_3", 300, "1936-04-01", false, "m3")
	var first: String = str(sl.call("pick_rotator_slot"))
	if first != "autosave_1":
		_fail("oldest unlocked should be autosave_1, got %s" % first)
		return
	_write_probe(sl, "autosave_1", 400, "1936-05-01", false, "m4")
	var row: Dictionary = sl.call("_format_slot_ui_row", "autosave_1", true, {
		"game_date": "1936-05-01",
		"save_kind": "auto",
		"timestamp_unix": 400,
		"timestamp": "1936-05-01T00:00:00",
		"player_tag": "GER",
	})
	if str(row.get("game_date_label", "")).find("1 May 1936") < 0:
		_fail("month date label %s" % str(row.get("game_date_label", "")))
		return
	sl.call("_note_session_lock_after_rotator", "autosave_2")
	if not bool(sl.call("slot_session_locked", "autosave_2")):
		_fail("session lock did not stick")
		return
	var skip_locked: String = str(sl.call("pick_rotator_slot"))
	if skip_locked == "autosave_2":
		_fail("rotator overwrote session-locked slot")
		return
	sl.call("begin_autosave_session")
	if bool(sl.call("slot_session_locked", "autosave_2")):
		_fail("new session did not clear lock")
		return
	sl.call("_note_session_lock_after_rotator", "autosave_3")
	if not bool(sl.call("slot_session_locked", "autosave_3")):
		_fail("new session did not lock the next first autosave")
		return
	if bool(sl.call("slot_session_locked", "autosave_2")):
		_fail("previous lock survived a new session")
		return
	_pass("rotator fills then overwrites oldest; session lock lifecycle")


func _test_last_played_survives(sl: Node) -> void:
	_write_probe(sl, LAST_PLAYED, 50, "1938-02-14", false, "keep-me")
	var before := FileAccess.get_file_as_bytes(str(sl.call("get_save_path", LAST_PLAYED)))
	for i in range(4):
		var slot: String = str(sl.call("pick_rotator_slot"))
		_write_probe(sl, slot, 1000 + i, "1936-0%d-01" % (i + 2), false, "rot%d" % i)
	var after := FileAccess.get_file_as_bytes(str(sl.call("get_save_path", LAST_PLAYED)))
	if before != after or _read_marker(sl, LAST_PLAYED) != "keep-me":
		_fail("last_played was overwritten by rotator")
		return
	if str(sl.call("pick_rotator_slot")) == LAST_PLAYED:
		_fail("rotator picked last_played")
		return
	_pass("last_played survives rotator overwrites")


func _test_month_year_hooks(sl: Node) -> void:
	var gathers0 := int(sl.get("_calendar_autosave_gathers"))
	sl.call("set_autosave_cadence", "off")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "")
	sl.call("_on_month_advanced_for_autosave", 1936, 2)
	if sl.has_method("settle_deferred_calendar_autosave"):
		sl.call("settle_deferred_calendar_autosave")
	if int(sl.get("_calendar_autosave_gathers")) != gathers0:
		_fail("cadence off still gathered")
		return
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	sl.call("set_autosave_cadence", "monthly")
	sl.call("_on_month_advanced_for_autosave", 1936, 3)
	if sl.has_method("settle_deferred_calendar_autosave"):
		sl.call("settle_deferred_calendar_autosave")
	if int(sl.get("_calendar_autosave_gathers")) != gathers0:
		_fail("killswitch still gathered")
		return
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "")
	sl.call("set_autosave_cadence", "yearly")
	var year_src := FileAccess.get_file_as_string("res://scripts/autoload/SaveLoadManager.gd")
	var ybody := year_src.substr(year_src.find("func _on_year_advanced_for_autosave"))
	ybody = ybody.substr(0, ybody.find("func _notification"))
	if ybody.find("save_game_detailed") >= 0:
		_fail("year hook still writes save_game_detailed inline")
		return
	sl.call("set_autosave_cadence", "monthly")
	_pass("cadence off + killswitch quiet; year hook is deferred")


func _on_list_changed() -> void:
	_signal_hits += 1


func _test_load_list_signal(sl: Node) -> void:
	_signal_hits = 0
	if not sl.has_signal("save_list_changed"):
		_fail("save_list_changed missing")
		return
	if not sl.save_list_changed.is_connected(_on_list_changed):
		sl.save_list_changed.connect(_on_list_changed)
	sl.call("_notify_save_list_refresh")
	if _signal_hits < 1:
		_fail("save_list_changed did not fire")
		return
	var mm_src := FileAccess.get_file_as_string("res://scripts/ui/MainMenu.gd")
	var ltb_src := FileAccess.get_file_as_string("res://scripts/ui/LivingTitleBoot.gd")
	var ocp_src := FileAccess.get_file_as_string("res://scripts/ui/OrderCommandPanel.gd")
	if mm_src.find("save_list_changed") < 0:
		_fail("S1 MainMenu does not listen to save_list_changed")
		return
	if ltb_src.find("save_list_changed") < 0:
		_fail("S2 LivingTitleBoot does not listen to save_list_changed")
		return
	if ocp_src.find("save_list_changed") < 0:
		_fail("S3 OrderCommandPanel does not listen to save_list_changed")
		return
	_pass("load list signal reaches S1/S2/S3")


func _test_idle_pause(sl: Node) -> void:
	var tm := _tm()
	if tm == null:
		_fail("TimeManager missing")
		return
	if tm.has_method("mark_living_title_closed"):
		tm.call("mark_living_title_closed")
	tm.call("set_paused", false)
	sl.call("set_idle_minutes", 10)
	sl.call("inject_idle_clock_msec", 1000)
	sl.call("note_qualifying_input_for_test")
	sl.call("poll_idle_for_test")
	if bool(tm.call("is_paused")):
		_fail("idle armed before N minutes")
		return
	if bool(sl.call("is_away_overlay_visible")):
		_fail("away overlay shown before idle")
		return
	sl.call("inject_idle_clock_msec", 1000 + 10 * 60 * 1000 + 5)
	sl.call("poll_idle_for_test")
	if not bool(tm.call("is_paused")):
		_fail("idle did not pause the clock")
		return
	if not bool(sl.call("is_away_overlay_visible")):
		_fail("away overlay missing")
		return
	if not bool(sl.call("slot_is_occupied", LAST_PLAYED)):
		_fail("last_played was not written on idle")
		return
	sl.call("note_qualifying_input_for_test")
	if bool(sl.call("is_away_overlay_visible")):
		_fail("away overlay did not dismiss")
		return
	if not bool(tm.call("is_paused")):
		_fail("dismiss auto-resumed the clock")
		return
	tm.call("set_paused", true)
	sl.call("inject_idle_clock_msec", 1000)
	sl.call("note_qualifying_input_for_test")
	sl.call("inject_idle_clock_msec", 1000 + 10 * 60 * 1000 + 5)
	var overlay_was := bool(sl.call("is_away_overlay_visible"))
	sl.call("poll_idle_for_test")
	if bool(sl.call("is_away_overlay_visible")) and not overlay_was:
		_fail("idle armed from a deliberate pause")
		return
	_pass("idle writes last_played then pauses; dismiss leaves paused")


func _test_idle_pause_against_tib_watchdog(sl: Node) -> void:
	## Live ITEM 3 (log 3526–3527): TIB `_step_live_clock` unpaused TimeManager
	## on the next tick because is_paused stayed false while 1x was selected.
	var tm := _tm()
	if tm == null:
		_fail("TimeManager missing")
		return
	if tm.has_method("mark_living_title_closed"):
		tm.call("mark_living_title_closed")
	var bar := _make_bar()
	if bar == null:
		_fail("TopInfoBar missing for idle watchdog test")
		return
	bar.set_meta("player_owns_clock", true)
	bar.set("is_paused", false)
	bar.set("current_speed", 1)
	tm.call("set_paused", false)
	sl.call("set_idle_minutes", 10)
	sl.call("inject_idle_clock_msec", 2000)
	sl.call("note_qualifying_input_for_test")
	sl.call("poll_idle_for_test")
	if bool(tm.call("is_paused")):
		_fail("tib idle: armed before N minutes")
		return
	sl.call("inject_idle_clock_msec", 2000 + 10 * 60 * 1000 + 5)
	sl.call("poll_idle_for_test")
	if not bool(sl.call("slot_is_occupied", LAST_PLAYED)):
		_fail("tib idle: last_played was not written before pause")
		return
	if not bool(sl.call("is_away_overlay_visible")):
		_fail("tib idle: away overlay missing")
		return
	if not bool(bar.get("is_paused")):
		_fail("tib idle: bar is_paused stayed false (watchdog will unpause)")
		return
	if not bool(tm.call("is_paused")):
		_fail("tib idle: TimeManager not paused after idle")
		return
	if not bar.has_method("_step_live_clock"):
		_fail("tib idle: _step_live_clock missing")
		return
	bar.call("_step_live_clock")
	if not bool(tm.call("is_paused")):
		_fail("tib idle: TimeManager unpaused on next _step_live_clock")
		return
	sl.call("note_qualifying_input_for_test")
	if bool(sl.call("is_away_overlay_visible")):
		_fail("tib idle: overlay did not dismiss")
		return
	bar.call("_step_live_clock")
	if not bool(tm.call("is_paused")):
		_fail("tib idle: dismiss left TimeManager running")
		return
	if not bool(bar.get("is_paused")):
		_fail("tib idle: dismiss cleared bar is_paused")
		return
	_pass("idle pause sticks against TopInfoBar _step_live_clock; dismiss stays paused")


func _make_bar() -> Node:
	var existing := root.find_child("TopInfoBar", true, false)
	if existing is Control:
		return existing
	var packed: PackedScene = load("res://scenes/ui/TopInfoBar.tscn") as PackedScene
	if packed == null:
		return null
	var bar: Node = packed.instantiate()
	bar.name = "TopInfoBar"
	root.add_child(bar)
	return bar


func _test_product_day_retired(sl: Node) -> void:
	var tm := _tm()
	var gathers0 := int(sl.get("_calendar_autosave_gathers"))
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE_TEST_INTERVAL", "")
	if tm != null:
		tm.set("_live_f5_equiv_clock", false)
		tm.set("_living_playtest_clock", false)
		tm.set("total_days_elapsed", 14)
	sl.call("_on_day_advanced_for_autosave", 1936, 1, 15)
	if sl.has_method("settle_deferred_calendar_autosave"):
		sl.call("settle_deferred_calendar_autosave")
	if int(sl.get("_calendar_autosave_gathers")) != gathers0:
		_fail("product path still 7-day autosaves")
		return
	_pass("product 7-day day-advanced cadence is retired")
