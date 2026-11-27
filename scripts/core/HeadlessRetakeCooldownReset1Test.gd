extends SceneTree

## RETAKE-COOLDOWN-RESET-1. Product new-game and load paths.
## A leftover absolute retake until-day must not survive a new game, or a
## load whose blob has no land_war dictionary. A blob that has land_war
## still restores the saved absolute days.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessRetakeCooldownReset1Test.gd

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRetakeCooldownReset1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRetakeCooldownReset1Test: ", msg)


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessRetakeCooldownReset1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRetakeCooldownReset1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _seed_leftover(bm: Node, until_day: int, pid: int) -> void:
	var key := str(pid)
	bm._retake_cooldown = {key: until_day}
	bm._retake_blocked = {key: ["POL", "GER"]}
	bm._ai_stall = {"POL": {"last_progress_day": 400}}
	bm._attack_reject = {"retake_cooldown": 3}


func _run() -> void:
	var bm := get_root().get_node_or_null("BattleManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var sl := get_root().get_node_or_null("SaveLoadManager")
	if bm == null or tm == null or sl == null:
		_fail("autoloads missing")
		_finish()
		return
	if not bm.has_method("reset_ai_war1"):
		_fail("product reset_ai_war1 missing")
		_finish()
		return
	if not bm.has_method("reset_ai_war1_for_test"):
		_fail("reset_ai_war1_for_test missing")
		_finish()
		return
	_test_new_game(bm, tm)
	_test_load_without_land_war(bm, tm, sl)
	_test_load_with_land_war_restores(bm, tm, sl)
	_finish()


func _test_new_game(bm: Node, tm: Node) -> void:
	tm.total_days_elapsed = 120
	_seed_leftover(bm, 127, 710173)
	if int(bm._retake_cooldown.get("710173", 0)) <= int(tm.total_days_elapsed):
		_fail("new-game fixture until-day is not in the future")
		return
	var end := load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if end == null or not end.has_method("reset_session_for_new_game"):
		_fail("CampaignEndDomain.reset_session_for_new_game missing")
		return
	if not tm.has_method("boot_living_era"):
		_fail("boot_living_era missing")
		return
	# Empty-slot Begin: LivingTitleBoot calls these two, in this order.
	end.call("reset_session_for_new_game")
	tm.call("boot_living_era", 1936)
	if int(tm.total_days_elapsed) != 0:
		_fail("new-game clock is %d, want 0" % int(tm.total_days_elapsed))
		return
	if not (bm._retake_cooldown as Dictionary).is_empty():
		_fail("new-game left retake_cooldown %s" % str(bm._retake_cooldown))
		return
	if not (bm._retake_blocked as Dictionary).is_empty():
		_fail("new-game left retake_blocked %s" % str(bm._retake_blocked))
		return
	if not (bm._attack_reject as Dictionary).is_empty():
		_fail("new-game left attack_reject %s" % str(bm._attack_reject))
		return
	_pass("new-game after a war keeps no future until-days (clock 0)")


func _test_load_without_land_war(bm: Node, tm: Node, sl: Node) -> void:
	tm.total_days_elapsed = 200
	_seed_leftover(bm, 207, 711086)
	if int(bm._retake_cooldown.get("711086", 0)) <= int(tm.total_days_elapsed):
		_fail("load fixture until-day is not in the future")
		return
	sl._apply_save_data({
		"time": {
			"current_date": {"year": 1936, "month": 6, "day": 1},
			"total_days_elapsed": 152,
		},
	})
	if not (bm._retake_cooldown as Dictionary).is_empty() or not (bm._retake_blocked as Dictionary).is_empty():
		_fail("load without land_war left cooldown %s blocked %s" % [str(bm._retake_cooldown), str(bm._retake_blocked)])
		return
	if not (bm._attack_reject as Dictionary).is_empty():
		_fail("load without land_war left attack_reject %s" % str(bm._attack_reject))
		return
	_seed_leftover(bm, 300, 710430)
	sl._apply_save_data({
		"time": {"total_days_elapsed": 10},
		"land_war": "not-a-dict",
	})
	if not (bm._retake_cooldown as Dictionary).is_empty() or not (bm._retake_blocked as Dictionary).is_empty():
		_fail("non-dict land_war left cooldown %s blocked %s" % [str(bm._retake_cooldown), str(bm._retake_blocked)])
		return
	_pass("load without land_war clears until-days")


func _test_load_with_land_war_restores(bm: Node, tm: Node, sl: Node) -> void:
	tm.total_days_elapsed = 50
	_seed_leftover(bm, 999, 710001)
	bm._attack_reject = {"scan_miss": 4}
	var saved_until := 159
	sl._apply_save_data({
		"time": {
			"current_date": {"year": 1936, "month": 6, "day": 1},
			"total_days_elapsed": 152,
		},
		"land_war": {
			"version": 1,
			"open_battles": [],
			"marches": {},
			"next_seq": 1,
			"last_aar": {},
			"retake_cooldown": {"711086": saved_until},
			"retake_blocked": {"711086": ["POL"]},
			"ai_stall": {"POL": {"last_progress_day": 140}},
		},
	})
	if int(tm.total_days_elapsed) != 152:
		_fail("consistent load clock is %d, want 152" % int(tm.total_days_elapsed))
		return
	if int(bm._retake_cooldown.get("711086", -1)) != saved_until:
		_fail("consistent load did not restore until-day, got %s" % str(bm._retake_cooldown))
		return
	if (bm._retake_cooldown as Dictionary).has("710001"):
		_fail("leftover until-day survived a consistent land_war load")
		return
	var blocked: Variant = bm._retake_blocked.get("711086", [])
	if not (blocked is Array) or not (blocked as Array).has("POL"):
		_fail("consistent load did not restore retake_blocked %s" % str(bm._retake_blocked))
		return
	if saved_until <= int(tm.total_days_elapsed):
		_fail("restored until-day %d is not ahead of clock %d" % [saved_until, int(tm.total_days_elapsed)])
		return
	# apply_save_data does not persist or clear _attack_reject. A reset here would.
	if int(bm._attack_reject.get("scan_miss", 0)) != 4:
		_fail("consistent load touched attack_reject %s" % str(bm._attack_reject))
		return
	_pass("consistent land_war load restores absolute until-days")
