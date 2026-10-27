extends SceneTree

## SAVE-FULL-1 long-war round trip.
## cont: declare the four wars, save at day 400, trace 120 days, save at day 600, trace 120 days.
## load: fresh boot, load one of those slots, trace the same 120 days.
## The traced window plants one officer and one replacement request after a day reseed.

const _Hash = preload("res://scripts/core/SaveStateHash.gd")
const RUN_SEED := 193601
const TRACE_DAYS := 120
const DAY_400 := 400
const DAY_600 := 600

var _failures := 0
var _sl: Node
var _tm: Node
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _move: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveFull1LongWarTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveFull1LongWarTest: ", msg)


func _run() -> void:
	_sl = get_root().get_node_or_null("SaveLoadManager")
	_tm = get_root().get_node_or_null("TimeManager")
	if not _load_domains():
		_fail("campaign domain scripts failed to load")
		print("HeadlessSaveFull1LongWarTest: RESULT=FAIL failures=%d" % _failures)
		quit(1)
		return
	var mode := OS.get_environment("SF1_MODE").strip_edges()
	if mode.is_empty():
		mode = "cont"
	if mode == "cont":
		_mode_cont()
	elif mode == "load":
		_mode_load()
	elif mode == "probe":
		if _boot_wars():
			_save_slot("sf1_probe", 0)
	else:
		_fail("unknown SF1_MODE %s" % mode)
	if _failures > 0:
		print("HeadlessSaveFull1LongWarTest: RESULT=FAIL failures=%d" % _failures)
	else:
		print("HeadlessSaveFull1LongWarTest: RESULT=PASS")
	quit(1 if _failures > 0 else 0)


func _mode_cont() -> void:
	if not _boot_wars():
		return
	if not _advance_to(DAY_400):
		_fail("clock did not reach day %d" % DAY_400)
		return
	if not _save_slot("sf1_d400", DAY_400):
		return
	var trace_400 := _trace_window(DAY_400)
	_write_trace(OS.get_environment("SF1_TRACE_400"), trace_400)
	if not _advance_to(DAY_600):
		_fail("clock did not reach day %d" % DAY_600)
		return
	if not _save_slot("sf1_d600", DAY_600):
		return
	var trace_600 := _trace_window(DAY_600)
	_write_trace(OS.get_environment("SF1_TRACE_600"), trace_600)
	_pass("cont traces written")


func _mode_load() -> void:
	var slot := OS.get_environment("SF1_SLOT").strip_edges()
	var save_day := int(OS.get_environment("SF1_SAVE_DAY"))
	if slot.is_empty() or save_day <= 0:
		_fail("load mode needs SF1_SLOT and SF1_SAVE_DAY")
		return
	if not _boot_empty():
		return
	var t_load := Time.get_ticks_usec()
	var loaded: Dictionary = _sl.load_game_detailed(slot)
	var load_ms := float(Time.get_ticks_usec() - t_load) / 1000.0
	if not bool(loaded.get("ok", false)):
		_fail("load %s failed: %s" % [slot, str(loaded.get("error", ""))])
		return
	var load_bytes := 0
	var load_path := str(loaded.get("path", ""))
	if not load_path.is_empty() and FileAccess.file_exists(load_path):
		load_bytes = FileAccess.get_file_as_bytes(load_path).size()
	print("LOAD_METRIC day=%d ms=%.1f bytes=%d" % [save_day, load_ms, load_bytes])
	if not _roundtrip_hash(load_path):
		return
	_tm.paused = false
	_tm.run_seed = RUN_SEED
	var text := _trace_window(save_day)
	_write_trace(OS.get_environment("SF1_TRACE"), text)
	_pass("load trace day=%d" % save_day)


func _load_domains() -> bool:
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	_move = load("res://scripts/formations/FormationMovement.gd") as GDScript
	return _war != null and _cap != null and _end != null and _move != null and _war.has_method("declare_war")


func _boot_wars() -> bool:
	if not _boot_empty():
		return false
	var pairs := [["GER", "POL"], ["FRA", "ITA"], ["SOV", "POL"], ["JAP", "CHI"]]
	for pair in pairs:
		var declared: Variant = _war.call("declare_war", str(pair[0]), str(pair[1]), "sf1")
		print("SF1_WAR %s-%s %s" % [pair[0], pair[1], str(declared)])
		if typeof(declared) != TYPE_DICTIONARY or not bool((declared as Dictionary).get("ok", false)):
			_fail("declare %s-%s failed: %s" % [pair[0], pair[1], str(declared)])
			return false
		if not bool(_war.call("is_at_war", str(pair[0]), str(pair[1]))):
			_fail("war %s-%s missing after declare" % [pair[0], pair[1]])
			return false
	_pass("four wars declared")
	return true


func _boot_empty() -> bool:
	if _sl == null or _tm == null:
		_fail("save or time manager missing")
		return false
	_war.call("reset_for_test")
	_cap.call("reset_for_test")
	_end.call("reset_for_test")
	var gd := get_root().get_node_or_null("GameData")
	if gd != null and gd.has_method("clear_for_load"):
		gd.call("clear_for_load")
	_move.call("apply_save_data", {})
	var bm := get_root().get_node_or_null("BattleManager")
	if bm != null:
		var open: Variant = bm.get("_open_land_battles")
		if open is Array:
			(open as Array).clear()
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if boot == null or mm == null or not bool(boot.boot(mm, sm, "GER")):
		_fail("boot failed")
		return false
	_tm.run_seed = RUN_SEED
	_tm.paused = false
	_cap.call("apply_economy_factories_to_map")
	return true


func _advance_to(target: int) -> bool:
	var guard := 0
	while int(_tm.get_total_days_elapsed()) < target and guard < 80:
		guard += 1
		if not _unlock_clock():
			_fail("campaign clock stayed locked at day %d" % int(_tm.get_total_days_elapsed()))
			return false
		var step := mini(20, target - int(_tm.get_total_days_elapsed()))
		var adv: Dictionary = _tm.advance_live_f5_equivalent_days(step)
		print("SF1_PROGRESS day=%d target=%d ok=%s" % [int(_tm.get_total_days_elapsed()), target, str(adv.get("ok", false))])
		if bool(adv.get("ok", false)):
			continue
		if bool(adv.get("locked", false)) and _unlock_clock():
			continue
		_fail("advance failed at day %d %s" % [int(_tm.get_total_days_elapsed()), str(adv)])
		return false
	return int(_tm.get_total_days_elapsed()) >= target


func _unlock_clock() -> bool:
	if _end == null or not bool(_end.call("clock_locked")):
		return true
	_end.call("set_keep_playing")
	_tm.paused = false
	return not bool(_end.call("clock_locked"))


func _save_slot(slot: String, day: int) -> bool:
	var t_save := Time.get_ticks_usec()
	var saved: Dictionary = _sl.save_game_detailed(slot)
	var save_ms := float(Time.get_ticks_usec() - t_save) / 1000.0
	if not bool(saved.get("ok", false)):
		_fail("save %s failed: %s" % [slot, str(saved.get("error", ""))])
		return false
	var live_hash := str(_Hash.state_hash(_sl._gather_save_data()))
	print("SAVE_METRIC day=%d ms=%.1f bytes=%d hash=%s" % [day, save_ms, int(saved.get("bytes", 0)), live_hash])
	return true


func _roundtrip_hash(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		_fail("save file missing for round-trip hash")
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("save file is not an object")
		return false
	var live_text := JSON.stringify(_sl._gather_save_data())
	var live_parsed: Variant = JSON.parse_string(live_text)
	if typeof(live_parsed) != TYPE_DICTIONARY:
		_fail("live gather did not round-trip through JSON")
		return false
	var file_hash := str(_Hash.state_hash(parsed))
	var live_hash := str(_Hash.state_hash(live_parsed))
	print("START_HASH file=%s live=%s" % [file_hash, live_hash])
	if file_hash == live_hash:
		_pass("load gather matches the save file")
		return true
	var diff := str(_Hash.first_diff(_Hash._strip(parsed), _Hash._strip(live_parsed)))
	print("START_DIFF %s" % diff.substr(0, 800))
	_fail("load gather diverged from the save file")
	return false


func _trace_window(save_day: int) -> String:
	var lines: PackedStringArray = []
	for i in TRACE_DAYS:
		if not _unlock_clock():
			_fail("clock locked in trace at i=%d" % i)
			break
		_tm.paused = false
		var adv: Dictionary = _tm.advance_live_f5_equivalent_days(1)
		if not bool(adv.get("ok", false)):
			_fail("trace advance failed at i=%d %s" % [i, str(adv)])
			break
		if i == 0:
			_plant_ids()
		lines.append(_row())
		if (i + 1) % 10 == 0:
			print("SF1_TRACE save_day=%d step=%d elapsed=%d" % [save_day, i + 1, int(_tm.get_total_days_elapsed())])
	return "\n".join(lines) + "\n"


func _plant_ids() -> void:
	var day := int(_tm.get_total_days_elapsed())
	if _tm.has_method("_reseed_sim_day"):
		_tm._reseed_sim_day(day)
	var lm := get_root().get_node_or_null("LeaderManager")
	if lm == null:
		_fail("LeaderManager missing for id fixture")
		return
	var officer: Leader = lm.generate_new_leader_from_training("GER", "general")
	if officer == null:
		_fail("officer fixture returned null")
		return
	lm.register_leader(officer)
	var request_id := str(lm.open_traced_replacement("GER", "sf1_trace_target"))
	var unix := str(Time.get_unix_time_from_system())
	print("FIXTURE day=%d officer=%s request=%s" % [day, officer.leader_id, request_id])
	if officer.leader_id.contains(unix) or request_id.contains(unix):
		_fail("fixture ids still contain unix time")
		return
	if not officer.leader_id.begins_with("ger_officer_d%d_" % day):
		_fail("fixture officer id %s" % officer.leader_id)
		return
	if not request_id.begins_with("formation_sf1_trace_target_d%d_" % day):
		_fail("fixture request id %s" % request_id)


func _row() -> String:
	var elapsed := int(_tm.get_total_days_elapsed())
	var wars := ""
	var gd := get_root().get_node_or_null("GameData")
	if gd != null:
		var peace: Variant = gd.get("peace_state")
		if peace is Dictionary:
			var raw: Variant = (peace as Dictionary).get("campaign_wars", {})
			if raw is Dictionary:
				var table: Variant = (raw as Dictionary).get("wars", {})
				if table is Dictionary:
					var keys: Array = (table as Dictionary).keys()
					keys.sort()
					wars = str(keys)
	var end := ""
	if _end != null:
		var model: Variant = _end.call("view_model")
		if model is Dictionary:
			end = str((model as Dictionary).get("outcome", ""))
	return "d=%d wars=%s end=%s hash=%s" % [elapsed, wars, end, str(_Hash.state_hash(_sl._gather_save_data()))]


func _write_trace(path: String, text: String) -> void:
	var out := path.strip_edges()
	if out.is_empty():
		_fail("trace path empty")
		return
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		_fail("cannot write trace %s" % out)
		return
	f.store_string(text)
	f.close()
	print("TRACE_FILE %s bytes=%d" % [out, text.length()])
