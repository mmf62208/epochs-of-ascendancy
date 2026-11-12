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
	await _run()
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
	await _test_s3_quicksave_apply_row(sl)
	await _test_s3_heavy_quicksave_apply_live_budget(sl)
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
	var sl_src := FileAccess.get_file_as_string("res://scripts/autoload/SaveLoadManager.gd")
	if sl_src.find("call_deferred(\"_emit_save_list_changed\")") < 0:
		_fail("save_list_changed still emits synchronously from notify")
		return
	sl.call("_notify_save_list_refresh")
	if sl.has_method("_emit_save_list_changed"):
		sl.call("_emit_save_list_changed")
	if _signal_hits < 1:
		_fail("save_list_changed did not fire")
		return
	var mm_src := FileAccess.get_file_as_string("res://scripts/ui/MainMenu.gd")
	var ltb_src := FileAccess.get_file_as_string("res://scripts/ui/LivingTitleBoot.gd")
	var ocp_src := FileAccess.get_file_as_string("res://scripts/ui/OrderCommandPanel.gd")
	if mm_src.find("save_list_changed") < 0:
		_fail("S1 MainMenu does not listen to save_list_changed")
		return
	if mm_src.find("CONNECT_DEFERRED") < 0:
		_fail("S1 MainMenu save_list_changed is not CONNECT_DEFERRED")
		return
	if ltb_src.find("save_list_changed") < 0:
		_fail("S2 LivingTitleBoot does not listen to save_list_changed")
		return
	if ocp_src.find("save_list_changed") < 0:
		_fail("S3 OrderCommandPanel does not listen to save_list_changed")
		return
	if ocp_src.find("CONNECT_DEFERRED") < 0:
		_fail("S3 OrderCommandPanel save_list_changed is not CONNECT_DEFERRED")
		return
	if ocp_src.find("call_deferred(\"_rebuild_all_sections\")") < 0:
		_fail("S3 still rebuilds all sections mid-Apply pressed")
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


func _test_s3_quicksave_apply_row(sl: Node) -> void:
	## ITEM 6 S3: Quicksave Apply must not free() the emitting button, and the
	## visible row must pick up the new game date after the deferred rebuild.
	_write_probe(sl, "quicksave", 100, "1936-07-19", false, "old-qs")
	var packed: PackedScene = load("res://scenes/ui/OrderCommandPanel.tscn") as PackedScene
	if packed == null:
		_fail("S3 OrderCommandPanel.tscn missing")
		return
	var ocp: Node = packed.instantiate()
	ocp.name = "OrderCommandPanel"
	root.add_child(ocp)
	if ocp.has_method("_rebuild_saves_section"):
		ocp.call("_rebuild_saves_section")
	var stale := _find_s3_quicksave_row_label(ocp)
	if stale == null or str(stale.text).find("19 Jul") < 0:
		_fail("S3 quicksave probe row missing: %s" % (str(stale.text) if stale != null else "none"))
		ocp.queue_free()
		return
	var apply_btn := _find_s3_quicksave_apply_button(ocp)
	if apply_btn == null:
		_fail("S3 Quicksave Apply/Save button missing")
		ocp.queue_free()
		return
	var close_btn: Node = ocp.get("_close_btn")
	apply_btn.pressed.emit()
	if not is_instance_valid(apply_btn):
		_fail("S3 Apply freed the button while pressed")
		return
	if close_btn != null and not is_instance_valid(close_btn):
		_fail("S3 Close died during Apply")
		return
	await process_frame
	await process_frame
	var fresh := _find_s3_quicksave_row_label(ocp)
	if fresh == null:
		_fail("S3 quicksave row missing after Apply")
		ocp.queue_free()
		return
	if str(fresh.text).find("19 Jul") >= 0:
		_fail("S3 quicksave row still stale after Apply: %s" % str(fresh.text))
		ocp.queue_free()
		return
	if ocp.has_method("refresh"):
		ocp.call("refresh")
	fresh = _find_s3_quicksave_row_label(ocp)
	if fresh == null or str(fresh.text).find("19 Jul") >= 0:
		_fail("S3 Refresh still stale: %s" % (str(fresh.text) if fresh != null else "none"))
		ocp.queue_free()
		return
	close_btn = ocp.get("_close_btn")
	if close_btn == null or not is_instance_valid(close_btn):
		_fail("S3 Close unresponsive after Apply")
		ocp.queue_free()
		return
	ocp.queue_free()
	_pass("S3 Quicksave Apply updates the row without freeing mid-pressed")


func _write_heavy_probe(sl: Node, slot: String, unix: int, game_date: String, marker: String) -> int:
	## Mid-campaign-weight fixture (~2.6 MB). Live S3 overwrote a 2626853-byte
	## quicksave; the tiny `_write_probe` used by `_test_s3_quicksave_apply_row`
	## cannot see that hang.
	if sl.has_method("_ensure_save_dir"):
		sl.call("_ensure_save_dir")
	var provinces: Array = []
	for i in range(800):
		provinces.append({
			"id": 710000 + i,
			"owner_tag": "GER",
			"controller_tag": "GER",
			"development_level": 4,
			"infrastructure": 6,
			"factories": 2,
			"name": "HeavyProbeProvince_%d" % i,
			"manpower": 12000 + i,
			"victory_points": 1,
		})
	var data := {
		"save_version": 2,
		"metadata": {
			"timestamp_unix": unix,
			"timestamp": "1936-01-01T00:00:00",
			"game_date": game_date,
			"last_played": "1936-01-01T00:00:00",
			"save_kind": str(sl.call("slot_kind", slot)),
			"session_locked": false,
			"player_tag": "GER",
			"marker": marker,
		},
		"land_war": {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}},
		"map": {"provinces": provinces},
	}
	var text := JSON.stringify(data)
	var want := 2626853
	if text.length() < want:
		data["pad"] = "x".repeat(want - text.length())
		text = JSON.stringify(data)
	var path := str(sl.call("get_save_path", slot))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("heavy probe write failed for %s" % slot)
		return 0
	f.store_string(text)
	f.close()
	return text.length()


func _pump_frames_until(pred: Callable, budget_ms: int, label: String) -> bool:
	var t0 := Time.get_ticks_msec()
	if pred.call():
		return true
	while Time.get_ticks_msec() - t0 <= budget_ms:
		var frame_start := Time.get_ticks_msec()
		await process_frame
		var frame_ms := Time.get_ticks_msec() - frame_start
		if frame_ms > budget_ms:
			_fail("%s: process_frame stalled %dms (budget %dms)" % [label, frame_ms, budget_ms])
			return false
		if pred.call():
			return true
	if pred.call():
		return true
	_fail("%s: still not done after %dms" % [label, Time.get_ticks_msec() - t0])
	return false


func _panel_is_closed(ocp: Node) -> bool:
	if ocp == null:
		return true
	if not is_instance_valid(ocp):
		return true
	if ocp.is_queued_for_deletion():
		return true
	if ocp is CanvasItem and not (ocp as CanvasItem).visible:
		return true
	return false


func _make_ocp(node_name: String = "OrderCommandPanel") -> Node:
	var packed: PackedScene = load("res://scenes/ui/OrderCommandPanel.tscn") as PackedScene
	if packed == null:
		return null
	var ocp: Node = packed.instantiate()
	ocp.name = node_name
	# Set before add_child: _ready schedules _deferred_first_refresh, which
	# would otherwise rebuild the whole Orders catalogue on the next
	# process_frame (dedicated runs hung here after the heavy probe print).
	ocp.set_meta("eoa_skip_first_refresh", true)
	root.add_child(ocp)
	return ocp


func _populate_orders_like_first_open(ocp: Node) -> Node:
	## Live hang: Orders already populated then Apply. Build the saves rows
	## only — do not await process_frame (that ran the deferred full catalogue).
	if ocp.has_method("_rebuild_saves_section"):
		ocp.call("_rebuild_saves_section")
	var body: Node = ocp.get("_body")
	if body != null:
		for i in range(400):
			var dummy := Label.new()
			dummy.name = "Autosave2Catalog_%d" % i
			dummy.text = "catalog_row_%d" % i
			body.add_child(dummy)
		var marker := Label.new()
		marker.name = "AUTOSAVE2_BODY_MARKER"
		marker.text = "keep-me"
		body.add_child(marker)
	return body.get_node_or_null("AUTOSAVE2_BODY_MARKER") if body != null else null


func _row_is_fresh(ocp: Node, stale_date: String, fresh_date: String) -> bool:
	var row := _find_s3_quicksave_row_label(ocp)
	if row == null:
		return false
	var txt := str(row.text)
	if txt.find(stale_date) >= 0:
		return false
	return txt.find(fresh_date) >= 0


func _resume_is_fresh(ocp: Node, stale_date: String, fresh_date: String) -> bool:
	var resume: Node = ocp.find_child("ResumeLineLabel", true, false)
	if resume == null or not (resume is Label):
		return true
	var txt := str((resume as Label).text)
	if txt.is_empty():
		return true
	if txt.find(stale_date) >= 0:
		return false
	return txt.find(fresh_date) >= 0


func _emit_escape(ocp: Node) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.key_label = KEY_ESCAPE
	ev.unicode = 27
	if ocp.has_method("_input"):
		ocp.call("_input", ev)
	if not _panel_is_closed(ocp) and ocp.has_method("_unhandled_input"):
		ocp.call("_unhandled_input", ev)


func _test_s3_heavy_quicksave_apply_live_budget(sl: Node) -> void:
	## AUTOSAVE-2: wall-clock budget, real Close, real Esc, mid-campaign weight.
	## The existing S3 case waits two frames on a tiny 19 Jul probe and never
	## clicks Close. This case must FAIL on the 4565db63 product tree because
	## Apply still call_deferred("_rebuild_all_sections") and drops the body
	## marker / leaves the ⚡ row stale until that rebuild finishes.
	var bytes := _write_heavy_probe(sl, "quicksave", 100, "1936-01-01", "old-heavy")
	if bytes < 2500000:
		_fail("heavy probe too small (%d bytes); need mid-campaign ~2.6MB" % bytes)
		return
	print("  HeadlessAutosave1Test: heavy probe %d bytes" % bytes)
	var tm := _tm()
	if tm != null:
		tm.current_year = 1936
		tm.current_month = 1
		tm.current_day = 16
		tm.total_days_elapsed = 15
		if tm.has_method("set_paused"):
			tm.call("set_paused", true)
	var lm := root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	var stale_date := "1 Jan 1936"
	var fresh_date := "16 Jan 1936"

	var ocp := _make_ocp()
	if ocp == null:
		_fail("heavy Close: OrderCommandPanel.tscn missing")
		return
	var marker: Node = await _populate_orders_like_first_open(ocp)
	var stale := _find_s3_quicksave_row_label(ocp)
	if stale == null or str(stale.text).find(stale_date) < 0:
		_fail("heavy Close: stale ⚡ row missing 1 Jan 1936: %s" % (str(stale.text) if stale != null else "none"))
		ocp.queue_free()
		return
	var apply_btn := _find_s3_quicksave_apply_button(ocp)
	if apply_btn == null:
		_fail("heavy Close: Quicksave Apply/Save button missing")
		ocp.queue_free()
		return
	apply_btn.pressed.emit()
	if not is_instance_valid(apply_btn):
		_fail("heavy Close: Apply freed the button while pressed")
		return
	var row_ok := await _pump_frames_until(
		func() -> bool: return _row_is_fresh(ocp, stale_date, fresh_date),
		2000,
		"heavy Close: ⚡ row within 2s"
	)
	if not row_ok:
		ocp.queue_free()
		return
	if not _resume_is_fresh(ocp, stale_date, fresh_date):
		var resume_n: Node = ocp.find_child("ResumeLineLabel", true, false)
		_fail("heavy Close: Resume line still stale: %s" % (str((resume_n as Label).text) if resume_n is Label else "missing"))
		ocp.queue_free()
		return
	var result_lbl: Label = ocp.get("_result") as Label
	if result_lbl == null or str(result_lbl.text).find("save_slot:quicksave") < 0 or str(result_lbl.text).find("OK") < 0:
		_fail("heavy Close: Last result missing save_slot:quicksave → OK: %s" % (str(result_lbl.text) if result_lbl != null else "none"))
		ocp.queue_free()
		return
	if marker == null or not is_instance_valid(marker) or marker.is_queued_for_deletion():
		_fail("heavy Close: Apply rebuilt the whole Orders body (marker gone)")
		ocp.queue_free()
		return
	var close_btn: Node = ocp.get("_close_btn")
	if close_btn == null or not (close_btn is BaseButton):
		_fail("heavy Close: Close button missing after Apply")
		ocp.queue_free()
		return
	(close_btn as BaseButton).pressed.emit()
	var closed := await _pump_frames_until(
		func() -> bool: return _panel_is_closed(ocp),
		1000,
		"heavy Close: Close within 1s"
	)
	if not closed:
		if is_instance_valid(ocp):
			ocp.queue_free()
		return
	_pass("heavy Quicksave Apply: ⚡/Resume within 2s, Close within 1s, no full-body rebuild")

	_write_heavy_probe(sl, "quicksave", 100, "1936-01-01", "old-heavy-esc")
	var ocp_esc := _make_ocp("OrderCommandPanel_esc")
	if ocp_esc == null:
		_fail("heavy Esc: OrderCommandPanel.tscn missing")
		return
	await _populate_orders_like_first_open(ocp_esc)
	var stale_esc := _find_s3_quicksave_row_label(ocp_esc)
	if stale_esc == null or str(stale_esc.text).find(stale_date) < 0:
		_fail("heavy Esc: stale ⚡ row missing 1 Jan 1936")
		ocp_esc.queue_free()
		return
	var apply_esc := _find_s3_quicksave_apply_button(ocp_esc)
	if apply_esc == null:
		_fail("heavy Esc: Quicksave Apply/Save button missing")
		ocp_esc.queue_free()
		return
	apply_esc.pressed.emit()
	var row_esc_ok := await _pump_frames_until(
		func() -> bool: return _row_is_fresh(ocp_esc, stale_date, fresh_date),
		2000,
		"heavy Esc: ⚡ row within 2s"
	)
	if not row_esc_ok:
		ocp_esc.queue_free()
		return
	_emit_escape(ocp_esc)
	var esc_closed := await _pump_frames_until(
		func() -> bool: return _panel_is_closed(ocp_esc),
		1000,
		"heavy Esc: Esc within 1s"
	)
	if not esc_closed:
		if is_instance_valid(ocp_esc):
			ocp_esc.queue_free()
		return
	_pass("heavy Quicksave Apply: Esc dismisses the panel within 1s")


func _s3_quicksave_core(text: String) -> String:
	## Occupied quicksave flair is "⚡ quicksave · …". Strip an optional leading
	## mark + whitespace so the slot name still has to start with quicksave.
	var t := str(text).strip_edges().to_lower()
	var i := 0
	while i < t.length():
		var code := t.unicode_at(i)
		if code == 32 or code == 9:
			i += 1
			continue
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			break
		i += 1
		while i < t.length():
			var follow := t.unicode_at(i)
			if follow != 32 and follow != 9:
				break
			i += 1
		break
	return t.substr(i)


func _is_s3_quicksave_row_text(text: String) -> bool:
	var raw := str(text)
	if raw.find(" · ") < 0:
		return false
	return _s3_quicksave_core(raw).begins_with("quicksave")


func _find_s3_quicksave_row_label(n: Node) -> Label:
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		return null
	if n is Label and _is_s3_quicksave_row_text((n as Label).text):
		return n as Label
	for c in n.get_children():
		var found := _find_s3_quicksave_row_label(c)
		if found != null:
			return found
	return null


func _find_s3_quicksave_apply_button(n: Node) -> BaseButton:
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		return null
	if n is BaseButton:
		var txt := str((n as BaseButton).text)
		if txt == "Save" or txt == "Apply":
			var row := n.get_parent()
			if row != null:
				for sib in row.get_children():
					if sib is Label and _s3_quicksave_core((sib as Label).text).begins_with("quicksave"):
						return n as BaseButton
	for c in n.get_children():
		var found := _find_s3_quicksave_apply_button(c)
		if found != null:
			return found
	return null


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
