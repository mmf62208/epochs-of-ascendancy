# scripts/autoload/TimeManager.gd
## Central source of truth for game calendar date, scenario start date, pause state, and time progression.
## 
## Architecture (as of this session):
## - Real-time simulation is driven by `TopInfoBar` (or other timers) calling `advance_real_time(real_seconds)`.
## - `advance_days()` and `advance_real_time()` are the core primitives. They emit:
##     • game_day_advanced(year, month, day) on every day
##     • game_month_advanced(year, month) on month boundaries
##     • game_year_advanced(year) on year boundaries (which triggers LeaderManager's heavy simulation)
## - TimeManager is the single source of truth for the calendar and controls when each tick granularity fires.
## - Pause and `time_scale` are respected at the TimeManager level.
##
## Migration goal: Daily, monthly, and yearly logic continues to move into (or be driven by) TimeManager.
## Other systems should be pure listeners to the appropriate signals.
##
## Signal usage (preferred integration pattern):
##   - game_day_advanced(year, month, day)   → Daily simulation steps (supply generation, agent network growth + real province effects like supply disruption/infra sabotage, light production, etc.)
##     IMPORTANT: day is ALWAYS valid (1-31). Listeners must not assume they receive normalized dates on month boundaries (fixed 2026-05).
##   - game_month_advanced(year, month)      → Monthly updates (temporary modifier decay, etc.)
##   - game_year_advanced(year)              → Heavy yearly simulation (Leader events, research progress, mission resolution, etc.)
##     Emitted reliably from the central rollover path (in addition to LeaderManager's legacy signal).
##
## Other systems should connect to the most appropriate signal rather than polling dates.
##
## Usage:
##   var year := TimeManager.get_current_year()
##   var month := TimeManager.get_current_month()
##   var date := TimeManager.get_current_date()  # {year, month, day}
##   if not TimeManager.is_paused():
##       ...
##   TimeManager.set_paused(true)
##
##   # Systems should connect to the appropriate signal:
##   TimeManager.game_month_advanced.connect(my_monthly_tick)
##   TimeManager.game_year_advanced.connect(my_yearly_tick)
##
## Initialization:
##   Called from ScenarioLoader after parsing scenario "start_date".

extends Node

# NOTE: We intentionally do NOT declare `class_name TimeManager`.
# This script is registered as an autoload singleton named "TimeManager".
# Using class_name on an autoload causes Godot's GDScript analyzer to emit
# "Class 'TimeManager' hides an autoload singleton" + "Cannot find member 'game_day_advanced'"
# errors in this file and in every other script that does the standard defensive pattern:
#     if typeof(TimeManager) != TYPE_NIL:
#         TimeManager.game_day_advanced.connect(...)
#
# Removing class_name makes the static analyzer happy while runtime behavior is unchanged.

signal game_year_advanced(year: int)
signal game_month_advanced(year: int, month: int)  # For monthly ticks
signal game_day_advanced(year: int, month: int, day: int)   # For daily ticks

var current_year: int = 1936
var current_month: int = 1
var current_day: int = 1

var scenario_start_date: String = "1936-01-01"
var scenario_start_year: int = 1936

var paused: bool = false
var time_scale: float = 1.0   # Future use for simulation speed (1.0, 2.0, 5.0, etc.)

## Monotonic day counter since scenario start (incremented in advance_days).
var total_days_elapsed: int = 0

# Internal accumulator for real-time driven simulation (in game days)
var _accumulated_game_days: float = 0.0

func _ready() -> void:
	print("TimeManager: Initialized (default 1936-01-01)")

## Called by ScenarioLoader when a scenario is loaded.
## Parses "YYYY-MM-DD" (falls back gracefully to year-only).
func initialize_from_scenario_start_date(start_date_str: String) -> void:
	scenario_start_date = start_date_str.strip_edges()
	if scenario_start_date.is_empty():
		scenario_start_date = "1936-01-01"

	var parts := scenario_start_date.split("-")
	if parts.size() >= 1 and parts[0].is_valid_int():
		scenario_start_year = int(parts[0])
		current_year = scenario_start_year
	else:
		scenario_start_year = 1936
		current_year = 1936

	if parts.size() >= 2 and parts[1].is_valid_int():
		current_month = clampi(int(parts[1]), 1, 12)
	else:
		current_month = 1

	if parts.size() >= 3 and parts[2].is_valid_int():
		current_day = clampi(int(parts[2]), 1, 31)
	else:
		current_day = 1

	total_days_elapsed = 0

	print("TimeManager: Scenario start date set to %s (year %d)" % [scenario_start_date, current_year])

func get_current_year() -> int:
	return current_year

func get_current_month() -> int:
	return current_month

func get_current_day() -> int:
	return current_day


func get_total_days_elapsed() -> int:
	return total_days_elapsed

## Returns true if we are currently on day 1 of the month (simple proxy for "just entered a new day cycle" in some contexts).
## Most systems should connect to the `game_day_advanced` signal instead of polling.
func is_new_day() -> bool:
	return current_day == 1

## Convenience: advance exactly one day (primarily for testing/manual use).
func advance_one_day() -> void:
	advance_days(1.0)

## Returns true if the most recent day advance caused us to enter a new month.
## (Useful for systems that want to react only on month boundaries.)
func is_new_month() -> bool:
	# Simple heuristic: if day == 1, we are on the first day of the current month.
	return current_day == 1

## Convenience: advance exactly one month (primarily for testing/manual use).
func advance_one_month() -> void:
	advance_days(30.0)  # Approximate; real rollover handled inside advance_days()

## Returns a dictionary with the current date for easy consumption by UI/overlays.
func get_current_date() -> Dictionary:
	return {
		"year": current_year,
		"month": current_month,
		"day": current_day,
		"date_string": "%04d-%02d-%02d" % [current_year, current_month, current_day]
	}

func get_scenario_start_date() -> String:
	return scenario_start_date

func is_paused() -> bool:
	return paused

func set_paused(p: bool) -> void:
	if paused != p:
		paused = p
		print("TimeManager: Paused = %s" % paused)

func set_time_scale(scale: float) -> void:
	time_scale = maxf(0.1, scale)   # Safety clamp
	# Future: this can affect advance rates when we have a real simulation loop.

## Convenience helper: advance exactly one full year (primarily for testing/manual use).
func advance_one_year() -> void:
	advance_days(365.0)

## Increments the year (and handles basic month/day rollover for future daily use).
## Emits game_year_advanced for compatibility with LeaderManager listeners etc.
## Call this from a central loop or have LeaderManager delegate to it.
func advance_year() -> void:
	if paused:
		return

	current_year += 1
	# Simple rollover: reset to Jan 1 of new year (can be made more sophisticated later)
	current_month = 1
	current_day = 1

	# Drive full yearly simulation
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("advance_game_year"):
		LeaderManager.advance_game_year()
	else:
		game_year_advanced.emit(current_year)

	print("TimeManager: Year advanced to %d (via advance_year)" % current_year)

## Convenience for systems that still want to drive the year tick themselves.
## (Used during the transition period.)
func sync_year_from_external(year: int) -> void:
	if year > current_year:
		current_year = year
		# Keep month/day as-is or reset if desired.

## Advances the calendar by a number of game days.
## Handles simple month/year rollover (no leap years in MVP).
## When a year boundary is crossed, calls LeaderManager.advance_game_year() (the heavy simulation)
## and ensures `game_year_advanced(year)` is emitted.
## This is the main method the game clock uses to drive yearly progression.
func advance_days(days: float) -> void:
	if paused or days <= 0.0:
		return

	_accumulated_game_days += days

	var days_to_advance := int(_accumulated_game_days)
	if days_to_advance <= 0:
		return

	_accumulated_game_days -= days_to_advance

	for i in days_to_advance:
		current_day += 1

		# Normalize BEFORE emit so all daily listeners (Supply, Agent, Map, Production, UI) always receive a valid calendar date.
		# Previously emitted e.g. day=32 on 31-day month rollovers — polluted trackers, pulses, and date logic.
		var crossed_month := false
		var crossed_year := false
		var days_in_month := _get_days_in_month(current_month, current_year)
		if current_day > days_in_month:
			current_day = 1
			current_month += 1
			crossed_month = true
			if current_month > 12:
				current_month = 1
				current_year += 1
				crossed_year = true

		# Emit daily tick for every day advanced (guaranteed valid day 1-31)
		total_days_elapsed += 1
		game_day_advanced.emit(current_year, current_month, current_day)

		# Main-loop AI combat for non-player majors (world-class: scored targets on supply/infra/low-org + weather mud/snow avoid + ascend geo stub + chain/flank; promoted from F10 harness base).
		# Wired to daily for autonomous AI battle initiation (not debug-only) -- enables integrated 50+ turn playtesting with wars, captures, recovery, econ/peace ties.
		# Uses BattleManager.simulate_daily_ai_combat (limited actions, real execute_province_assault + chain path, weather/infra/org aware).
		# Polish: caps + player skip prevent spam; full weather/air/terrain in resolver feeds outcomes.
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("simulate_daily_ai_combat"):
			BattleManager.simulate_daily_ai_combat()

		if crossed_month:
			# Emit monthly tick signal whenever we cross into a new month (fires on day 1 of the new month)
			game_month_advanced.emit(current_year, current_month)

			if crossed_year:
				# Drive the full yearly simulation through LeaderManager (the heavy work)
				if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("advance_game_year"):
					LeaderManager.advance_game_year()
				# (No else emit here — we always emit the central TM year signal below for consistency.)

				# Central TM year signal — this is what makes TimeManager the single source of truth
				# for year events per its own documentation. Dual listeners protected by guards.
				game_year_advanced.emit(current_year)

				print("TimeManager: Year boundary crossed → %d (driven by central clock)" % current_year)

## Called by real-time timers (e.g. TopInfoBar) to advance simulation based on wall time.
## `real_seconds` is real elapsed time since last call.
## Respects `time_scale` and `paused`.
## This is what makes "press Play and watch the world move" work.
func advance_real_time(real_seconds: float) -> void:
	if paused:
		return

	# Base rate: 1 real second = 1 game day at speed 1.0 (tunable later)
	var game_days_this_tick := real_seconds * time_scale
	advance_days(game_days_this_tick)

## Returns number of days in the given month (MVP: no leap years).
func _get_days_in_month(month: int, year: int) -> int:
	match month:
		2:
			return 28  # Simplified
		4, 6, 9, 11:
			return 30
		_:
			return 31

## === Save/Load support (SaveLoadManager contract) ===
## Returns a compact snapshot of mutable runtime calendar state.
func get_save_data() -> Dictionary:
	return {
		"current_date": get_current_date(),
		"scenario_start_date": scenario_start_date,
		"paused": paused,
		"time_scale": time_scale,
		"total_days_elapsed": total_days_elapsed,
	}

## Applies previously saved calendar state. Does NOT emit day/month/year signals
## (we are restoring, not simulating forward).
func apply_save_data(data: Dictionary) -> void:
	if data.has("current_date"):
		var d: Dictionary = data["current_date"]
		current_year = int(d.get("year", 1936))
		current_month = int(d.get("month", 1))
		current_day = int(d.get("day", 1))
	if data.has("scenario_start_date"):
		scenario_start_date = str(data["scenario_start_date"])
	if data.has("paused"):
		set_paused(bool(data["paused"]))
	if data.has("time_scale"):
		set_time_scale(float(data.get("time_scale", 1.0)))
	if data.has("total_days_elapsed"):
		total_days_elapsed = maxi(0, int(data.get("total_days_elapsed", 0)))
