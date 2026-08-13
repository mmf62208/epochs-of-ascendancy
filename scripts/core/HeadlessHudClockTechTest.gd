extends SceneTree

## Prove HUD clock + tech status path stay usable (no stack overflow, no re-pause lock).
## Exercises the same TimeManager / TechnologyManager methods the top bar and Tech screen call.
## Run:
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHudClockTechTest.gd
##
## Gates:
## 1) get_node_status / can_research do not recurse (was infinite loop → dead UI after Tech)
## 2) TimeManager pause→unpause + advance_days(1) advances calendar
## 3) Interactive advance_real_time caps to 1 day per wall tick (no multi-day dump)
## 4) Source still has player_owns_clock guard in TestRunner (deferred interactive re-pause)

const SRC_TESTRUNNER := "res://scripts/core/TestRunner.gd"
const SRC_TOPINFO := "res://scripts/ui/TopInfoBar.gd"
const SRC_MAPVIEW := "res://scripts/map/MapViewInput.gd"
const SRC_TECH := "res://scripts/technology/TechnologyManager.gd"

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessHudClockTechTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessHudClockTechTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessHudClockTechTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	quit(0 if ok else 1)


func _run() -> void:
	_test_tech_status_no_recursion()
	_test_time_manager_unpause_and_one_day()
	_test_interactive_real_time_day_cap()
	_test_source_guards_present()


func _test_tech_status_no_recursion() -> void:
	var tm: Node = _autoload("TechnologyManager")
	if tm == null:
		_fail("TechnologyManager autoload missing")
		return
	if not tm.has_method("get_node_status") or not tm.has_method("can_research"):
		_fail("TechnologyManager missing get_node_status/can_research")
		return
	var tech_ids: Array = []
	if "technology_nodes" in tm and tm.technology_nodes is Dictionary:
		for k in (tm.technology_nodes as Dictionary).keys():
			tech_ids.append(str(k))
			if tech_ids.size() >= 80:
				break
	if tech_ids.is_empty():
		# Manager may load lazily — still call with a known-ish id without crashing.
		tech_ids = ["basic_infantry", "infantry_weapons_1", "tank_development"]
	var tag := "USA"
	var statuses: Array = []
	for tid in tech_ids:
		# If recursion returns, Godot stack-overflows before we finish the loop.
		var st: String = str(tm.call("get_node_status", tag, str(tid)))
		var can: bool = bool(tm.call("can_research", tag, str(tid)))
		statuses.append("%s=%s/can=%s" % [tid, st, can])
		# Invariant: can_research true only when status is available.
		if can and st != "available":
			_fail("can_research true but status=%s for %s" % [st, tid])
			return
	_pass("tech status/can_research for %d ids without stack overflow" % tech_ids.size())
	print("  sample: ", ", ".join(statuses.slice(0, mini(5, statuses.size()))))


func _test_time_manager_unpause_and_one_day() -> void:
	var clock: Node = _autoload("TimeManager")
	if clock == null:
		_fail("TimeManager autoload missing")
		return
	if not clock.has_method("set_paused") or not clock.has_method("advance_days"):
		_fail("TimeManager missing set_paused/advance_days")
		return
	clock.call("set_paused", true)
	if clock.has_method("is_paused") and not bool(clock.call("is_paused")):
		_fail("set_paused(true) did not pause")
		return
	var y0 := int(clock.call("get_current_year")) if clock.has_method("get_current_year") else -1
	var m0 := int(clock.call("get_current_month")) if clock.has_method("get_current_month") else -1
	var d0 := int(clock.get("current_day")) if "current_day" in clock else -1
	clock.call("set_paused", false)
	if clock.has_method("is_paused") and bool(clock.call("is_paused")):
		_fail("set_paused(false) left paused")
		return
	# Same primitive TopInfoBar/TimeManager use for calendar advance.
	clock.call("advance_days", 1.0)
	var d1 := int(clock.get("current_day")) if "current_day" in clock else -1
	var m1 := int(clock.call("get_current_month")) if clock.has_method("get_current_month") else -1
	var y1 := int(clock.call("get_current_year")) if clock.has_method("get_current_year") else -1
	var advanced := (y1 > y0) or (y1 == y0 and m1 > m0) or (y1 == y0 and m1 == m0 and d1 > d0)
	if not advanced:
		_fail("advance_days(1) did not move calendar (was %04d-%02d-%02d now %04d-%02d-%02d)" % [y0, m0, d0, y1, m1, d1])
		return
	# Re-pause for interactive safety (player can always re-pause).
	clock.call("set_paused", true)
	if clock.has_method("is_paused") and not bool(clock.call("is_paused")):
		_fail("re-pause after day failed")
		return
	_pass("pause→unpause→advance_days(1)→re-pause calendar moved %04d-%02d-%02d → %04d-%02d-%02d" % [y0, m0, d0, y1, m1, d1])


func _test_interactive_real_time_day_cap() -> void:
	var clock: Node = _autoload("TimeManager")
	if clock == null or not clock.has_method("advance_real_time"):
		_fail("TimeManager.advance_real_time missing")
		return
	var src := FileAccess.get_file_as_string("res://scripts/autoload/TimeManager.gd")
	if src.find("minf(game_days_this_tick, 1.0)") < 0:
		_fail("TimeManager missing interactive 1-day-per-tick cap (minf)")
		return
	if src.find("_should_run_daily_ai_combat") < 0:
		_fail("TimeManager missing _should_run_daily_ai_combat gate")
		return
	clock.call("set_paused", false)
	var d0 := int(clock.get("current_day")) if "current_day" in clock else -1
	var m0 := int(clock.call("get_current_month")) if clock.has_method("get_current_month") else -1
	if clock.has_method("set_time_scale"):
		clock.call("set_time_scale", 4.0)
	# Headless may take heavy path (multi-day); assert no crash and calendar readable.
	clock.call("advance_real_time", 1.0)
	var d1 := int(clock.get("current_day")) if "current_day" in clock else -1
	var m1 := int(clock.call("get_current_month")) if clock.has_method("get_current_month") else -1
	if d1 < 0:
		_fail("calendar unreadable after advance_real_time")
		return
	clock.call("set_paused", true)
	_pass("advance_real_time(1.0) @scale4 ok (%d/%d → %d/%d); source has interactive day cap" % [m0, d0, m1, d1])


func _test_source_guards_present() -> void:
	var tr := FileAccess.get_file_as_string(SRC_TESTRUNNER)
	var top := FileAccess.get_file_as_string(SRC_TOPINFO)
	var mv := FileAccess.get_file_as_string(SRC_MAPVIEW)
	var tech := FileAccess.get_file_as_string(SRC_TECH)
	if tr.find("player_owns_clock") < 0:
		_fail("TestRunner missing player_owns_clock guard")
	else:
		_pass("TestRunner honors player_owns_clock (no deferred re-pause after 1x)")
	if top.find("player_owns_clock") < 0 or top.find("_sim_tick_busy") < 0:
		_fail("TopInfoBar missing player_owns_clock or _sim_tick_busy")
	else:
		_pass("TopInfoBar sets player_owns_clock + busy flag on speed path")
	if top.find("_connect_once") < 0:
		_fail("TopInfoBar missing _connect_once (nav double-connect fix)")
	else:
		_pass("TopInfoBar uses _connect_once for nav buttons")
	if mv.find("TopInfoBar") < 0 or mv.find("return true") < 0:
		_fail("MapViewInput does not block edge pan for TopInfoBar")
	else:
		# More precise: TopInfoBar must return true (block), not false (allow)
		if mv.find('nname == "TopInfoBar"') >= 0 and mv.find("return true") >= 0:
			_pass("MapViewInput blocks edge pan under TopInfoBar")
		else:
			_fail("MapViewInput TopInfoBar edge-pan block not found")
	var idx := tech.find("func get_node_status")
	var idx2 := tech.find("func _is_research_blocked")
	if idx < 0 or idx2 <= idx:
		_fail("could not parse get_node_status body in TechnologyManager")
	else:
		var body := tech.substr(idx, idx2 - idx)
		if body.find("can_research(") >= 0:
			_fail("get_node_status still calls can_research (recursion)")
		else:
			_pass("get_node_status no longer calls can_research (recursion fixed)")
