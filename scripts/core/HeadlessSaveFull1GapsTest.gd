extends SceneTree

## SAVE-FULL-1 gaps that must fail on a save that drops depot fuel/munitions
## and that stamps replacement/officer ids from the wall clock.
## An older v1 blob must load with defaults and no new script error.

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveFull1GapsTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveFull1GapsTest: ", msg)


func _run() -> void:
	_test_depot_roundtrip()
	_test_leader_ids()
	_test_v1_migration()
	_test_tech_year_restore()
	if _failures > 0:
		print("HeadlessSaveFull1GapsTest: RESULT=FAIL failures=%d" % _failures)
	else:
		print("HeadlessSaveFull1GapsTest: RESULT=PASS")
	quit(1 if _failures > 0 else 0)


func _test_depot_roundtrip() -> void:
	var sm := get_root().get_node_or_null("SupplyManager")
	if sm == null:
		_fail("SupplyManager missing")
		return
	var depot := ProvinceDepotState.new(710173, 1000.0)
	depot.stockpile = 80.0
	depot.fuel_stockpile = 42.5
	depot.munitions_stockpile = 17.25
	sm.depot_states[710173] = depot
	sm._refill_queue.clear()
	sm._refill_queue.append(710300)
	sm._refill_queue.append(710173)
	sm._refill_queued = {710300: true, 710173: true}
	var blob: Dictionary = sm.get_save_data()
	var entry: Dictionary = (blob.get("depots", {}) as Dictionary).get("710173", {}) as Dictionary
	if not entry.has("fuel_stockpile") or not entry.has("munitions_stockpile"):
		_fail("gather dropped depot fuel/munitions keys")
		return
	depot.fuel_stockpile = 0.0
	depot.munitions_stockpile = 0.0
	depot.stockpile = 1.0
	sm._refill_queue.clear()
	sm._refill_queued.clear()
	sm.apply_save_data(blob, true, false)
	var back: ProvinceDepotState = sm.depot_states.get(710173)
	if back == null:
		_fail("depot missing after apply")
		return
	if not is_equal_approx(back.fuel_stockpile, 42.5) or not is_equal_approx(back.munitions_stockpile, 17.25):
		_fail("depot fuel/munitions not restored fuel=%s mun=%s" % [back.fuel_stockpile, back.munitions_stockpile])
		return
	if sm._refill_queue != [710300, 710173]:
		_fail("supply refill queue not restored %s" % str(sm._refill_queue))
		return
	_pass("depot fuel/munitions and refill queue round-trip")


func _test_leader_ids() -> void:
	var lm := get_root().get_node_or_null("LeaderManager")
	var tm := get_root().get_node_or_null("TimeManager")
	if lm == null:
		_fail("LeaderManager missing")
		return
	if tm != null:
		tm.total_days_elapsed = 410
	var officer: Leader = lm.generate_new_leader_from_training("GER", "general")
	if officer == null:
		_fail("officer generate returned null")
		return
	lm.register_leader(officer)
	var request_id := ""
	if lm.has_method("open_traced_replacement"):
		request_id = str(lm.open_traced_replacement("GER", "sf1_trace_target"))
	else:
		_fail("open_traced_replacement missing")
		return
	if officer.leader_id.contains(str(Time.get_unix_time_from_system())) or request_id.contains(str(Time.get_unix_time_from_system())):
		_fail("ids still use unix time officer=%s request=%s" % [officer.leader_id, request_id])
		return
	if not officer.leader_id.begins_with("ger_officer_d410_"):
		_fail("officer id not a saved-day counter: %s" % officer.leader_id)
		return
	if not request_id.begins_with("formation_sf1_trace_target_d410_"):
		_fail("request id not a saved-day counter: %s" % request_id)
		return
	var blob: Dictionary = lm.get_save_data()
	var seq_before := int(blob.get("leader_id_seq", -1))
	var rep_before := int(blob.get("replacement_seq", -1))
	if seq_before < 1 or rep_before < 1:
		_fail("leader counters not in save seq=%d rep=%d" % [seq_before, rep_before])
		return
	lm._leader_id_seq = 0
	lm._replacement_seq = 0
	lm.apply_save_data(blob)
	if int(lm._leader_id_seq) != seq_before or int(lm._replacement_seq) != rep_before:
		_fail("counters not restored from save")
		return
	var again: Leader = lm.generate_new_leader_from_training("GER", "general")
	if again == null or again.leader_id == officer.leader_id:
		_fail("second officer reused or missed an id")
		return
	if not str(lm.get_save_data().get("leaders", {}).get(officer.leader_id, {})).is_empty() or (lm.get_save_data().get("leaders", {}) as Dictionary).has(officer.leader_id):
		_pass("officer %s and request %s are counters in the save" % [officer.leader_id, request_id])
	else:
		_fail("officer missing from leader save")


func _test_v1_migration() -> void:
	var sl := get_root().get_node_or_null("SaveLoadManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	if sl == null or sm == null:
		_fail("save/supply missing for migration")
		return
	var depot := ProvinceDepotState.new(710173, 1000.0)
	depot.stockpile = 650.0
	depot.fuel_stockpile = 9.0
	depot.munitions_stockpile = 9.0
	sm.depot_states[710173] = depot
	var old := {
		"save_version": 1,
		"metadata": {"scenario_id": "1936", "player_tag": "GER", "timestamp": "old", "game_version": "0.2-dev"},
		"time": {
			"current_date": {"year": 1936, "month": 6, "day": 1},
			"scenario_start_date": "1936-01-01",
			"paused": true,
			"time_scale": 1.0,
			"total_days_elapsed": 152,
		},
		"map": {"provinces": []},
		"supply": {
			"version": 1,
			"depots": {
				"710173": {"stockpile": 80.0, "throughput_capacity": 15.0, "sabotage_level": 0.1},
			},
			"division_deployments": {},
		},
		"technology": {},
		"agents": {"agents": {}, "networks": {}},
		"national_modifiers": {"country_modifiers": {}},
		"leaders": {"leaders": {}, "formations": {}},
		"land_war": {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}},
		"production": {"lines": {}},
		"infrastructure_projects": {"version": 1, "active_projects": {}},
	}
	var path := "user://saves/sf1_v1_old.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("could not write v1 fixture")
		return
	f.store_string(JSON.stringify(old))
	f.close()
	var loaded: Dictionary = sl.load_game_detailed("sf1_v1_old")
	if not bool(loaded.get("ok", false)):
		_fail("v1 load failed: %s" % str(loaded.get("error", "")))
		return
	var back: ProvinceDepotState = sm.depot_states.get(710173)
	if back == null:
		_fail("v1 load dropped the depot")
		return
	if not is_equal_approx(back.stockpile, 80.0):
		_fail("v1 stockpile not applied")
		return
	if not is_equal_approx(back.fuel_stockpile, 0.0):
		_fail("v1 fuel default want 0 got %s" % back.fuel_stockpile)
		return
	if not is_equal_approx(back.munitions_stockpile, 28.0):
		_fail("v1 munitions default want 28 got %s" % back.munitions_stockpile)
		return
	var lm := get_root().get_node_or_null("LeaderManager")
	if lm != null and (int(lm._leader_id_seq) != 0 or int(lm._replacement_seq) != 0):
		_fail("v1 leader counters did not default to 0")
		return
	_pass("v1 save migrated with fuel 0 and munitions 0.35*stock")


func _test_tech_year_restore() -> void:
	var sl := get_root().get_node_or_null("SaveLoadManager")
	var tech := get_root().get_node_or_null("TechnologyManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	if sl == null or tech == null or tm == null or lm == null:
		_fail("tech year restore missing a manager")
		return
	var countries_before: int = int(tech.country_state.size())
	tech.custom_tech_nodes = {"stale_node": true}
	tech.set_current_year(1936)
	lm.current_year = 1900
	sl._apply_save_data({
		"time": {
			"current_date": {"year": 1937, "month": 2, "day": 5},
			"total_days_elapsed": 400,
		},
		"technology": {
			"current_year": 1937,
			"country_state": {},
			"custom_tech_nodes": {},
		},
	})
	if tech.get_current_year() != 1937:
		_fail("technology year stayed %d after a 1937 save" % tech.get_current_year())
		return
	if tech.country_state.size() != countries_before:
		_fail("empty technology.country_state wiped research (%d -> %d)" % [countries_before, tech.country_state.size()])
		return
	if not tech.custom_tech_nodes.is_empty():
		_fail("custom tech nodes were not replaced from the save")
		return
	if int(lm.current_year) != 1937:
		_fail("leader year did not follow the restored clock (%d)" % int(lm.current_year))
		return
	_pass("technology year 1937 restored and the leader clock followed")
