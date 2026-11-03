extends SceneTree

## VICTORY-PATHS-1. Flag default off. Paths, thresholds, and the end screen
## come from data/campaign/victory_paths.json through VictoryPathsDomain.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessVictoryPaths1Test.gd

const OFF_SEED := "20fe9063de285f19d4f9b8a105abfd31"

var _vp: GDScript
var _failures: int = 0
var _rules: Dictionary = {}
var _total: int = 0
var _held_at: int = -1
var _atomic_need: int = 0
var _arsenal_need: int = 0
var _arsenal_factories: int = -1
var _world: int = 100
var _end_date: String = ""


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessVictoryPaths1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessVictoryPaths1Test: ", msg)


func _run() -> void:
	var gd := root.get_node_or_null("GameData")
	_vp = load("res://scripts/core/VictoryPathsDomain.gd") as GDScript
	if gd == null or _vp == null or not _vp.has_method("reset_for_test"):
		_fail("GameData or VictoryPathsDomain missing")
		_finish()
		return
	_test_accessor(gd)
	_test_flag_off(gd)
	if not _load_rules():
		_finish()
		return
	_test_thresholds()
	_test_data_change()
	_test_screens(gd)
	_test_save(gd)
	_test_readout(gd)
	OS.set_environment("EOA_VICTORY_PATHS", "")
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessVictoryPaths1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessVictoryPaths1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _on() -> void:
	OS.set_environment("EOA_VICTORY_PATHS", "1")


func _off() -> void:
	OS.set_environment("EOA_VICTORY_PATHS", "")


func _test_accessor(gd: Node) -> void:
	for bad in ["", "0", "true", "yes", "on", "TRUE"]:
		OS.set_environment("EOA_VICTORY_PATHS", bad)
		if bool(gd.call("victory_paths_enabled")):
			_fail("flag on for value '%s'" % bad)
			return
	_on()
	if not bool(gd.call("victory_paths_enabled")):
		_fail("flag stayed off for EOA_VICTORY_PATHS=1")
		return
	_pass("accessor is on only for EOA_VICTORY_PATHS=1")


func _test_flag_off(gd: Node) -> void:
	_off()
	_vp.call("reset_for_test")
	if bool(gd.call("victory_paths_enabled")):
		_fail("flag off check left the accessor on")
		return
	var forced := {
		"date": "1949-01-01",
		"elapsed": 999,
		"player_tag": "GER",
		"world_factories": 10,
		"tags": {
			"GER": {
				"controlled_targets": 8,
				"target_total": 8,
				"factories": 10,
				"atomic_ready": true,
				"territory": 8,
				"industry": 10,
				"wars_won": 3,
				"major_enemies": ["FRA"],
				"capitulated_enemies": ["FRA"],
			},
		},
	}
	_vp.call("set_snapshot_override", forced)
	var tick: Dictionary = gd.call("victory_paths_tick_day")
	if not bool(tick.get("skipped", false)) or bool(tick.get("created", false)) or bool(tick.get("presented", false)):
		_fail("flag off tick was not a skip: %s" % str(tick))
		return
	if bool(_vp.call("has_state")) or bool(gd.peace_state.has("victory_paths")):
		_fail("flag off created victory path state")
		return
	var save: Dictionary = gd.call("get_save_data")
	if save.has("victory_paths"):
		_fail("flag off save gained victory_paths")
		return
	if str(gd.call("victory_paths_progress_text")) != "":
		_fail("flag off progress text is not empty")
		return
	var seed_line := str(_vp.get("OFF_SEED_BASELINE"))
	print("HeadlessVictoryPaths1Test: seed_line=%s" % seed_line)
	if seed_line != OFF_SEED:
		_fail("seed line %s != OFF baseline %s" % [seed_line, OFF_SEED])
		return
	var menu := _make_menu()
	if menu == null:
		_fail("flag off Command Center failed to build")
		return
	if menu.find_child("VictoryPathsReadout", true, false) != null:
		_fail("flag off Command Center created VictoryPathsReadout")
		menu.free()
		return
	menu.free()
	_pass("flag off: no path state, no readout, seed line %s" % seed_line)


func _load_rules() -> bool:
	_on()
	_vp.call("reset_for_test")
	var loaded: Variant = _vp.call("load_rules")
	if not (loaded is Dictionary) or (loaded as Dictionary).is_empty():
		_fail("victory_paths.json did not load")
		return false
	_rules = (loaded as Dictionary).duplicate(true)
	_total = _count_targets(_rules)
	_end_date = str(_rules.get("end_date", "")).strip_edges()
	var atomic := _path("atomic")
	var arsenal := _path("arsenal")
	_atomic_need = int(atomic.get("hold_days", 0))
	_arsenal_need = int(arsenal.get("sustain_days", 0))
	if _total <= 0 or _end_date.is_empty() or _atomic_need <= 0 or _arsenal_need <= 0:
		_fail("rules missing targets, end date, or hold days")
		return false
	var satellite := _path("satellite")
	if bool(satellite.get("enabled", true)) or not bool(satellite.get("disabled", false)):
		_fail("satellite stub is not disabled")
		return false
	_pass("loaded victory paths (%d targets, end %s)" % [_total, _end_date])
	return true


func _test_thresholds() -> void:
	_on()
	_vp.call("reset_for_test")
	_held_at = -1
	for held in range(0, _total + 1):
		var found: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 3, {"controlled_targets": held}), _rules, {})
		if bool(found.get("won", false)) and str(found.get("path_id", "")) == "conquest" and str(found.get("winner", "")) == "GER":
			_held_at = held
			break
	if _held_at <= 0:
		_fail("conquest did not trigger for the player at any held count")
		return
	var below: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 3, {"controlled_targets": _held_at - 1}), _rules, {})
	if bool(below.get("won", false)):
		_fail("conquest triggered below the data ratio at %d/%d" % [_held_at - 1, _total])
		return
	print("HeadlessVictoryPaths1Test: conquest held_at=%d below=%d total=%d" % [_held_at, _held_at - 1, _total])

	var both: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 4, {"controlled_targets": _held_at}, {"FRA": {"controlled_targets": _held_at}}), _rules, {})
	if str(both.get("winner", "")) != "GER" or str(both.get("path_id", "")) != "conquest":
		_fail("same-day conquest did not prefer the player: %s" % str(both.get("winner", "")))
		return

	var caps: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 5, {
		"controlled_targets": 0,
		"major_enemies": ["FRA", "ENG"],
		"capitulated_enemies": ["FRA", "ENG"],
	}), _rules, {})
	if not bool(caps.get("won", false)) or str(caps.get("path_id", "")) != "conquest" or str(caps.get("winner", "")) != "GER":
		_fail("all major enemies capitulated did not win conquest")
		return
	var partial: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 5, {
		"controlled_targets": 0,
		"major_enemies": ["FRA", "ENG"],
		"capitulated_enemies": ["FRA"],
	}), _rules, {})
	if bool(partial.get("won", false)):
		_fail("a partial capitulation won conquest")
		return
	var no_enemies: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 5, {
		"controlled_targets": 0,
		"major_enemies": [],
		"capitulated_enemies": [],
	}), _rules, {})
	if bool(no_enemies.get("won", false)):
		_fail("an empty enemy list won conquest")
		return

	var atomic_prog := {}
	for _i in range(_atomic_need - 1):
		var step: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 6, {"atomic_ready": true}), _rules, atomic_prog)
		if bool(step.get("won", false)):
			_fail("atomic won before hold_days (%d)" % _atomic_need)
			return
		atomic_prog = _dict(step.get("progress", {}))
	if int(_counter(atomic_prog, "atomic_hold", "GER")) != _atomic_need - 1:
		_fail("atomic hold stopped at %d, want %d" % [int(_counter(atomic_prog, "atomic_hold", "GER")), _atomic_need - 1])
		return
	var atomic_win: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 6, {"atomic_ready": true}), _rules, atomic_prog)
	if not bool(atomic_win.get("won", false)) or str(atomic_win.get("path_id", "")) != "atomic" or str(atomic_win.get("winner", "")) != "GER":
		_fail("atomic did not win on the hold day: %s" % str(atomic_win))
		return
	var cold := {}
	for _j in range(_atomic_need):
		var idle: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 6, {"atomic_ready": false}), _rules, cold)
		if bool(idle.get("won", false)):
			_fail("atomic won without the project")
			return
		cold = _dict(idle.get("progress", {}))
	print("HeadlessVictoryPaths1Test: atomic hold_days=%d" % _atomic_need)

	_arsenal_factories = -1
	for factories in range(0, _world + 1):
		var probe: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 7, {"factories": factories}, {}, _world), _rules, {})
		if int(_counter(_dict(probe.get("progress", {})), "arsenal_streak", "GER")) == 1:
			_arsenal_factories = factories
			break
	if _arsenal_factories <= 0:
		_fail("arsenal share never started a streak inside %d factories" % _world)
		return
	var shy: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 7, {"factories": _arsenal_factories - 1}, {}, _world), _rules, {})
	if bool(shy.get("won", false)) or int(_counter(_dict(shy.get("progress", {})), "arsenal_streak", "GER")) != 0:
		_fail("arsenal streak started below the data share")
		return
	var zero_world: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 7, {"factories": 5}, {}, 0), _rules, {})
	if bool(zero_world.get("won", false)) or int(_counter(_dict(zero_world.get("progress", {})), "arsenal_streak", "GER")) != 0:
		_fail("zero world factories counted as a full industry share")
		return
	var arsenal_prog := {}
	for _k in range(_arsenal_need - 1):
		var day: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 8, {"factories": _arsenal_factories}, {}, _world), _rules, arsenal_prog)
		if bool(day.get("won", false)):
			_fail("arsenal won before sustain_days (%d)" % _arsenal_need)
			return
		arsenal_prog = _dict(day.get("progress", {}))
	var arsenal_win: Dictionary = _vp.call("evaluate", _snap("1936-06-01", 8, {"factories": _arsenal_factories}, {}, _world), _rules, arsenal_prog)
	if not bool(arsenal_win.get("won", false)) or str(arsenal_win.get("path_id", "")) != "arsenal" or str(arsenal_win.get("winner", "")) != "GER":
		_fail("arsenal did not win on the sustain day: %s" % str(arsenal_win))
		return
	print("HeadlessVictoryPaths1Test: arsenal factories=%d/%d sustain=%d" % [_arsenal_factories, _world, _arsenal_need])

	var year := int(_end_date.substr(0, 4))
	var before_date := "%04d%s" % [year - 1, _end_date.substr(4)]
	var early: Dictionary = _vp.call("evaluate", _snap(before_date, 9, {"wars_won": 1, "territory": 0, "industry": 0}), _rules, {})
	if bool(early.get("won", false)):
		_fail("score won before the end date %s" % _end_date)
		return
	var tied: Dictionary = _vp.call("evaluate", _snap(_end_date, 9, {}), _rules, {})
	if bool(tied.get("won", false)):
		_fail("an all-zero score tie crowned a winner")
		return
	var scored: Dictionary = _vp.call("evaluate", _snap(_end_date, 9, {"wars_won": 1, "territory": 0, "industry": 0}), _rules, {})
	if not bool(scored.get("won", false)) or str(scored.get("path_id", "")) != "score" or str(scored.get("winner", "")) != "GER":
		_fail("unique high score did not win on %s: %s" % [_end_date, str(scored)])
		return
	if str(scored.get("path_id", "")) == "satellite":
		_fail("satellite won a path")
		return
	var second: Dictionary = _vp.call("evaluate", _snap(_end_date, 9, {"wars_won": 1, "territory": 0, "industry": 0}, {"FRA": {"wars_won": 2, "territory": 0, "industry": 0, "factories": 0, "controlled_targets": 0}}), _rules, {})
	if str(second.get("winner", "")) != "FRA" or str(second.get("outcome", "")) != "loss" or str(second.get("path_id", "")) != "score":
		_fail("a lower score won: %s" % str(second.get("winner", "")))
		return
	print("HeadlessVictoryPaths1Test: score end_date=%s" % _end_date)
	_pass("conquest, atomic, arsenal, and score match the data thresholds")


func _test_data_change() -> void:
	if _held_at <= 0:
		_fail("skipped the data-threshold change because conquest never fired")
		return
	var mutated: Dictionary = _rules.duplicate(true)
	var paths: Dictionary = _dict(mutated.get("paths", {}))
	var conquest: Dictionary = _dict(paths.get("conquest", {}))
	var raised := float(_held_at + 0.5) / float(_total)
	conquest["capital_ratio"] = raised
	paths["conquest"] = conquest
	mutated["paths"] = paths
	var snap := _snap("1936-06-01", 11, {"controlled_targets": _held_at})
	var still: Dictionary = _vp.call("evaluate", snap, _rules, {})
	var blocked: Dictionary = _vp.call("evaluate", snap, mutated, {})
	if not bool(still.get("won", false)) or str(still.get("path_id", "")) != "conquest":
		_fail("the file ratio stopped winning after a rules copy was built")
		return
	if bool(blocked.get("won", false)):
		_fail("raising capital_ratio to %.4f still won" % raised)
		return
	_vp.call("reset_for_test")
	var reloaded: Dictionary = _dict(_vp.call("load_rules"))
	var file_ratio := float(_dict(_dict(reloaded.get("paths", {})).get("conquest", {})).get("capital_ratio", -1))
	var original := float(_path("conquest").get("capital_ratio", -2))
	if not is_equal_approx(file_ratio, original):
		_fail("data change wrote victory_paths.json (%.4f vs %.4f)" % [file_ratio, original])
		return
	_rules = reloaded.duplicate(true)
	print("HeadlessVictoryPaths1Test: raised capital_ratio=%.4f blocked held=%d/%d" % [raised, _held_at, _total])
	_pass("a higher capital_ratio in data blocks the same snapshot")


func _test_screens(gd: Node) -> void:
	_on()
	if _held_at <= 0 or _arsenal_factories <= 0:
		_fail("skipped end-screen checks because a threshold was not found")
		return
	_clear_screens()
	var ink: GDScript = load("res://scripts/ui/CampaignInkEndScreen.gd") as GDScript
	if ink == null:
		_fail("CampaignInkEndScreen missing")
		return
	var plain: Node = ink.call("present_win", "GER", "kept playing")
	if _label(plain, "OutcomeTitle") != "VICTORY" or plain.find_child("PathTitle", true, false) != null:
		_fail("two-arg victory no longer shows VICTORY without a path title")
		return
	if not _label(plain, "OutcomeStats").begins_with("Day "):
		_fail("two-arg victory replaced the default stats line")
		return
	_clear_screens()
	var loss: Node = ink.call("present_loss", "GER", "capitulated")
	if _label(loss, "OutcomeTitle") != "DEFEAT" or loss.find_child("PathTitle", true, false) != null:
		_fail("two-arg defeat no longer shows DEFEAT without a path title")
		return
	_clear_screens()

	var builds := _owner_builds()
	var wars_before := JSON.stringify(gd.peace_state.get("campaign_wars", null))
	var caps_before := JSON.stringify(gd.peace_state.get("campaign_capitulation", null))
	if not _present_case(gd, _snap("1936-06-01", 21, {"controlled_targets": _held_at}), {}, "win"):
		return
	if JSON.stringify(gd.peace_state.get("campaign_wars", null)) != wars_before:
		_fail("conquest tick wrote campaign_wars")
		return
	if JSON.stringify(gd.peace_state.get("campaign_capitulation", null)) != caps_before:
		_fail("conquest tick wrote campaign_capitulation")
		return
	if _owner_builds() != builds:
		_fail("victory tick rebuilt the owner index (%s -> %s)" % [str(builds), str(_owner_builds())])
		return
	var again: Dictionary = gd.call("victory_paths_tick_day")
	if not bool(again.get("duplicate", false)) or bool(again.get("presented", false)):
		_fail("same-day tick presented twice: %s" % str(again))
		return
	_pass("conquest end screen")

	var atomic_prev := {"last_elapsed": 30}
	if _atomic_need > 1:
		atomic_prev["atomic_hold"] = {"GER": _atomic_need - 1}
	_vp.call("reset_for_test")
	_vp.call("import_save_blob", atomic_prev)
	if not _present_case(gd, _snap("1936-07-01", 31, {"atomic_ready": true}), atomic_prev, "win"):
		return
	_pass("atomic end screen")

	var arsenal_prev := {"last_elapsed": 40}
	if _arsenal_need > 1:
		arsenal_prev["arsenal_streak"] = {"GER": _arsenal_need - 1}
	_vp.call("reset_for_test")
	_vp.call("import_save_blob", arsenal_prev)
	if not _present_case(gd, _snap("1936-08-01", 41, {"factories": _arsenal_factories}, {}, _world), arsenal_prev, "win"):
		return
	_pass("arsenal end screen")

	_vp.call("reset_for_test")
	if not _present_case(gd, _snap(_end_date, 51, {"wars_won": 1, "territory": 0, "industry": 0}), {}, "win"):
		return
	_pass("score end screen")

	_vp.call("reset_for_test")
	if not _present_case(gd, _snap("1936-09-01", 61, {}, {"FRA": {"controlled_targets": _held_at}}), {}, "loss"):
		return
	ink.call("_on_any_load_completed", "victory-paths-defeat")
	if _ink_screen() != null:
		_fail("loading from the path defeat screen left it open")
		return
	_pass("AI conquest is DEFEAT and a load closes the screen")


func _present_case(gd: Node, snap: Dictionary, prev: Dictionary, want_outcome: String) -> bool:
	_clear_screens()
	var preview: Dictionary = _vp.call("evaluate", snap, _rules, prev)
	if not bool(preview.get("won", false)):
		_fail("screen setup did not win: %s" % str(preview))
		return false
	if str(preview.get("outcome", "")) != want_outcome:
		_fail("outcome %s, want %s (%s)" % [str(preview.get("outcome", "")), want_outcome, str(preview.get("path_id", ""))])
		return false
	if str(preview.get("path_id", "")) == "satellite":
		_fail("satellite reached the end screen")
		return false
	_vp.call("set_snapshot_override", snap)
	var tick: Dictionary = gd.call("victory_paths_tick_day")
	if not bool(tick.get("presented", false)):
		_fail("tick did not present %s: %s" % [str(preview.get("path_id", "")), str(tick)])
		return false
	var screen := _ink_screen()
	if screen == null:
		_fail("end screen missing after %s" % str(preview.get("path_id", "")))
		return false
	var want_title := "VICTORY" if want_outcome == "win" else "DEFEAT"
	if _label(screen, "OutcomeTitle") != want_title:
		_fail("OutcomeTitle '%s' for %s" % [_label(screen, "OutcomeTitle"), str(preview.get("path_id", ""))])
		return false
	if _label(screen, "PathTitle") != str(preview.get("title", "")):
		_fail("PathTitle '%s' want '%s'" % [_label(screen, "PathTitle"), str(preview.get("title", ""))])
		return false
	if _label(screen, "OutcomeWinner") != str(preview.get("winner", "")):
		_fail("OutcomeWinner '%s' want '%s'" % [_label(screen, "OutcomeWinner"), str(preview.get("winner", ""))])
		return false
	if _label(screen, "OutcomeReason") != str(preview.get("reason", "")):
		_fail("OutcomeReason '%s' want '%s'" % [_label(screen, "OutcomeReason"), str(preview.get("reason", ""))])
		return false
	var stats := _label(screen, "OutcomeStats")
	if stats != str(preview.get("stats", "")) or stats.begins_with("Day ") or stats.is_empty():
		_fail("OutcomeStats '%s' want '%s'" % [stats, str(preview.get("stats", ""))])
		return false
	print("HeadlessVictoryPaths1Test: screen %s %s winner=%s" % [want_title, str(preview.get("path_id", "")), str(preview.get("winner", ""))])
	return true


func _test_save(gd: Node) -> void:
	_on()
	_vp.call("reset_for_test")
	if _arsenal_factories <= 0 or _arsenal_need <= 1:
		_fail("arsenal sustain is too short for a mid-progress save")
		return
	_vp.call("set_snapshot_override", _snap("1936-02-01", 2, {}, {}, _world))
	var idle: Dictionary = gd.call("victory_paths_tick_day")
	var idle_save: Dictionary = gd.call("get_save_data")
	if bool(idle.get("created", false)) or bool(_vp.call("has_state")) or idle_save.has("victory_paths"):
		_fail("a quiet day created victory path state")
		return
	_vp.call("reset_for_test")
	_vp.call("set_snapshot_override", _snap("1936-02-02", 3, {"factories": _arsenal_factories}, {}, _world))
	var started: Dictionary = gd.call("victory_paths_tick_day")
	if bool(started.get("presented", false)) or not bool(_vp.call("has_state")):
		_fail("one arsenal day did not store mid-progress: %s" % str(started))
		return
	var blob: Dictionary = _dict(gd.peace_state.get("victory_paths", {}))
	if int(_counter(blob, "arsenal_streak", "GER")) != 1:
		_fail("mid-progress streak is %d" % int(_counter(blob, "arsenal_streak", "GER")))
		return
	var elapsed := int(blob.get("last_elapsed", -1))
	var save: Dictionary = gd.call("get_save_data")
	if not (save.get("victory_paths") is Dictionary):
		_fail("flag on save missing victory_paths")
		return
	_vp.call("clear_state")
	if bool(_vp.call("has_state")):
		_fail("clear_state left victory path state")
		return
	gd.call("apply_save_data", save)
	var loaded: Dictionary = _dict(gd.peace_state.get("victory_paths", {}))
	if int(_counter(loaded, "arsenal_streak", "GER")) != 1 or int(loaded.get("last_elapsed", -2)) != elapsed:
		_fail("roundtrip streak/elapsed %s vs 1/%d" % [str(loaded), elapsed])
		return
	_vp.call("set_snapshot_override", _snap("1936-02-02", elapsed, {"factories": _arsenal_factories}, {}, _world))
	var duplicate: Dictionary = gd.call("victory_paths_tick_day")
	var after: Dictionary = _dict(gd.peace_state.get("victory_paths", {}))
	if not bool(duplicate.get("duplicate", false)) or int(_counter(after, "arsenal_streak", "GER")) != 1:
		_fail("same-elapsed load tick changed the streak: %s" % str(duplicate))
		return
	_vp.call("set_snapshot_override", _snap("1936-02-03", elapsed + 1, {"factories": _arsenal_factories}, {}, _world))
	gd.call("victory_paths_tick_day")
	var next: Dictionary = _dict(gd.peace_state.get("victory_paths", {}))
	if int(_counter(next, "arsenal_streak", "GER")) != 2:
		_fail("the day after a load did not continue the streak (%d)" % int(_counter(next, "arsenal_streak", "GER")))
		return
	gd.call("apply_save_data", {"version": 1})
	if bool(_vp.call("has_state")) or bool(gd.peace_state.has("victory_paths")):
		_fail("pre-flag load kept victory path state")
		return
	var bare: Dictionary = gd.call("get_save_data")
	if bare.has("victory_paths"):
		_fail("pre-flag load saved a victory_paths key")
		return
	_pass("mid-progress save/load and a pre-flag load")


func _test_readout(gd: Node) -> void:
	_on()
	_vp.call("reset_for_test")
	_vp.call("set_snapshot_override", _snap("1936-03-01", 70, {"controlled_targets": 1, "factories": 1}, {}, _world))
	var text := str(gd.call("victory_paths_progress_text"))
	if text.is_empty():
		_fail("flag on progress text is empty")
		return
	var menu := _make_menu()
	if menu == null:
		_fail("flag on Command Center failed to build")
		return
	var label := menu.find_child("VictoryPathsReadout", true, false)
	if not (label is Label):
		_fail("flag on Command Center has no VictoryPathsReadout")
		menu.free()
		return
	var shown := str((label as Label).text)
	if (label as Label).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("victory readout is not read-only")
		menu.free()
		return
	for pid in ["conquest", "atomic", "arsenal", "score"]:
		var title := str(_path(pid).get("title", "")).strip_edges()
		if title.is_empty() or title not in shown:
			_fail("readout missing %s title '%s'" % [pid, title])
			menu.free()
			return
	var deferred := str(_path("satellite").get("progress_label", "")).strip_edges()
	if deferred.is_empty() or deferred not in shown:
		_fail("readout missing the satellite stub '%s'" % deferred)
		menu.free()
		return
	menu.free()
	_pass("Command Center readout lists every path")


func _snap(date: String, elapsed: int, ger: Dictionary, others: Dictionary = {}, world: int = -1) -> Dictionary:
	var tags := {}
	for tag_v in _tag_list():
		var tag := str(tag_v)
		var row := _quiet_row()
		if tag == "GER":
			row = _merge(row, ger)
		elif others.has(tag):
			row = _merge(row, _dict(others[tag]))
		row["tag"] = tag
		tags[tag] = row
	var factories := _world if world < 0 else world
	return {
		"date": date,
		"elapsed": elapsed,
		"player_tag": "GER",
		"world_factories": factories,
		"tags": tags,
	}


func _quiet_row() -> Dictionary:
	return {
		"controlled_targets": 0,
		"target_total": _total if _total > 0 else 8,
		"factories": 0,
		"territory": 0,
		"industry": 0,
		"wars_won": 0,
		"atomic_ready": false,
		"major_enemies": [],
		"capitulated_enemies": [],
	}


func _merge(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in extra.keys():
		out[k] = extra[k]
	return out


func _tag_list() -> Array:
	var out: Array = []
	var raw: Variant = _rules.get("tags", [])
	if raw is Array:
		for item in raw as Array:
			var tag := str(item).strip_edges().to_upper()
			if not tag.is_empty() and tag not in out:
				out.append(tag)
	if out.is_empty():
		out = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"]
	return out


func _path(pid: String) -> Dictionary:
	return _dict(_paths().get(pid, {}))


func _paths() -> Dictionary:
	return _dict(_rules.get("paths", {}))


func _count_targets(rules: Dictionary) -> int:
	var n := 0
	var raw: Variant = rules.get("targets", [])
	if raw is Array:
		for item in raw as Array:
			if item is Dictionary and int((item as Dictionary).get("id", 0)) > 0:
				n += 1
	return n


func _dict(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		return raw as Dictionary
	return {}


func _counter(progress: Dictionary, bucket: String, tag: String) -> int:
	var raw := _dict(progress.get(bucket, {}))
	return int(raw.get(tag, 0))


func _owner_builds() -> int:
	var mm := root.get_node_or_null("MapManager")
	if mm == null or not ("owner_index_build_count" in mm):
		return -1
	return int(mm.get("owner_index_build_count"))


func _clear_screens() -> void:
	for n in get_nodes_in_group("campaign_ink_end_screen"):
		if n != null and is_instance_valid(n):
			n.remove_from_group("campaign_ink_end_screen")
			n.queue_free()


func _ink_screen() -> Node:
	for n in get_nodes_in_group("campaign_ink_end_screen"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and not str(n.name).ends_with("_dying"):
			return n
	return null


func _label(screen: Node, node_name: String) -> String:
	if screen == null:
		return ""
	var found := screen.find_child(node_name, true, false)
	if found is Label:
		return str((found as Label).text)
	return ""


func _make_menu() -> Node:
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)
	return menu
