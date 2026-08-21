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
## 0–23. 1× clock advances hours first (not whole days per wall second).
var current_hour: int = 0

var scenario_start_date: String = "1936-01-01"
var scenario_start_year: int = 1936

var paused: bool = false
var time_scale: float = 1.0   # Interactive: multipliers on hours/wall-sec (1×, 2×, 3×, 4×)

## Monotonic day counter since scenario start (incremented in advance_days).
var total_days_elapsed: int = 0

# Internal accumulator for real-time driven simulation (in game days)
var _accumulated_game_days: float = 0.0
## Fractional hour accumulator (1.0 = one game hour).
var _accumulated_game_hours: float = 0.0

## Interactive F5: calendar advances immediately; day/month *signals* flush on later frames
## so a heavy listener cannot freeze the clock at Feb 28 (main thread never returns to TopInfoBar).
var _pending_sim_events: Array = []
var _sim_flush_scheduled: bool = false
## Soft budget (ms) for deferred sim work per frame — keeps pan/hover live past month ends.
const INTERACTIVE_SIM_FLUSH_BUDGET_MS := 10

func _ready() -> void:
	print("TimeManager: Initialized (default 1936-01-01)")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	# Safety net: if deferred flush stalled (e.g. pause race), keep draining the queue.
	if not paused and not _pending_sim_events.is_empty() and not _sim_flush_scheduled:
		_schedule_sim_flush()

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

	current_hour = 0
	_accumulated_game_hours = 0.0
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
		"hour": current_hour,
		"date_string": "%04d-%02d-%02d %02d:00" % [current_year, current_month, current_day, current_hour],
		"date_day_only": "%04d-%02d-%02d" % [current_year, current_month, current_day],
	}


func get_current_hour() -> int:
	return current_hour

func get_scenario_start_date() -> String:
	return scenario_start_date

func is_paused() -> bool:
	return paused

func set_paused(p: bool) -> void:
	if paused != p:
		paused = p
		print("TimeManager: Paused = %s" % paused)
	# Flush deferred month boundary that landed while paused (Feb→Mar safety).
	if not paused and has_meta("pending_month_boundary"):
		var pending: Dictionary = get_meta("pending_month_boundary")
		remove_meta("pending_month_boundary")
		_pending_sim_events.append({
			"kind": "month",
			"year": int(pending.get("year", current_year)),
			"month": int(pending.get("month", current_month)),
			"crossed_year": bool(pending.get("crossed_year", false)),
		})
	if not paused and not _pending_sim_events.is_empty():
		_schedule_sim_flush()

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
##
## Interactive F5 (is_interactive_light_sim): calendar fields update *immediately* so the top bar
## never freezes on Feb 28 while listeners run. Day/month signals are queued and flushed across
## frames with a time budget (see _flush_sim_events).
func advance_days(days: float) -> void:
	if paused or days <= 0.0:
		return

	_accumulated_game_days += days

	var days_to_advance := int(_accumulated_game_days)
	if days_to_advance <= 0:
		return

	_accumulated_game_days -= days_to_advance

	var light := is_interactive_light_sim()
	for i in days_to_advance:
		current_day += 1

		# Normalize BEFORE emit so all daily listeners always receive a valid calendar date.
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

		total_days_elapsed += 1

		if light:
			# Calendar already on the new day — queue sim so TopInfoBar can return instantly.
			_pending_sim_events.append({
				"kind": "day",
				"year": current_year,
				"month": current_month,
				"day": current_day,
			})
			if crossed_month:
				_pending_sim_events.append({
					"kind": "month",
					"year": current_year,
					"month": current_month,
					"crossed_year": crossed_year,
				})
				print(
					"TimeManager: calendar → %04d-%02d-%02d (month rollover queued, interactive)"
					% [current_year, current_month, current_day]
				)
			continue

		# Headless / harness: synchronous path (evidence needs ordered listeners in one step).
		game_day_advanced.emit(current_year, current_month, current_day)
		_tick_own_land_marches()
		_tick_open_land_battles()
		_tick_out_of_combat_recovery()
		_tick_organize_queue()
		if _should_run_daily_ai_combat():
			if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("simulate_daily_ai_combat"):
				BattleManager.simulate_daily_ai_combat()
		if crossed_month:
			_emit_month_year_boundary(current_year, current_month, crossed_year)

	if light and not _pending_sim_events.is_empty():
		_schedule_sim_flush()


func _schedule_sim_flush() -> void:
	if _sim_flush_scheduled:
		return
	_sim_flush_scheduled = true
	call_deferred("_flush_sim_events")


func _flush_sim_events() -> void:
	_sim_flush_scheduled = false
	if paused:
		# Keep queue; resume via set_paused(false) / _process.
		return
	if _pending_sim_events.is_empty():
		return

	# Exactly one event per frame — never chain day+month in the same frame (Mar 1936 monthly
	# used to freeze the main thread for so long the clock looked stuck at Feb 28).
	var ev: Dictionary = _pending_sim_events.pop_front() as Dictionary
	var kind := str(ev.get("kind", ""))
	if kind == "day":
		game_day_advanced.emit(int(ev.get("year", 0)), int(ev.get("month", 0)), int(ev.get("day", 0)))
		# Budgeted non-player major AI (production/soft) — not full simulate_daily_ai_combat.
		_maybe_run_interactive_multi_ai()
		_maybe_run_ai_infra_invest()
		_maybe_run_ai_land_battle_starts()
		_tick_own_land_marches()
		_tick_open_land_battles()
		_tick_out_of_combat_recovery()
		_tick_organize_queue()
	elif kind == "month":
		var y := int(ev.get("year", 0))
		var m := int(ev.get("month", 0))
		print("TimeManager: flushing month boundary %04d-%02d (interactive, isolated frame)" % [y, m])
		_emit_month_year_boundary(y, m, bool(ev.get("crossed_year", false)))

	if not _pending_sim_events.is_empty():
		_schedule_sim_flush()


func _emit_month_year_boundary(year: int, month: int, crossed_year: bool) -> void:
	# Emit monthly tick whenever we cross into a new month (fires on day 1 of the new month).
	game_month_advanced.emit(year, month)
	if not crossed_year:
		return
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("advance_game_year"):
		LeaderManager.advance_game_year()
	game_year_advanced.emit(year)
	print("TimeManager: Year boundary crossed → %d (driven by central clock)" % year)


func _emit_month_year_boundary_deferred(year: int, month: int, crossed_year: bool) -> void:
	# Legacy entry: route through the same queue as interactive day ticks.
	if paused:
		if not has_meta("pending_month_boundary"):
			set_meta("pending_month_boundary", {"year": year, "month": month, "crossed_year": crossed_year})
		return
	_pending_sim_events.append({
		"kind": "month",
		"year": year,
		"month": month,
		"crossed_year": crossed_year,
	})
	_schedule_sim_flush()

func _should_run_daily_ai_combat() -> bool:
	return not is_interactive_light_sim()


## Light interactive multi-AI: budgeted major production on F5 day ticks.
## Default ON under interactive light sim. Killswitch: EOA_INTERACTIVE_MULTI_AI=0.
## Never runs full BattleManager.simulate_daily_ai_combat (OOM history).
func _should_run_interactive_multi_ai() -> bool:
	if OS.get_environment("EOA_INTERACTIVE_MULTI_AI").strip_edges() == "0":
		return false
	if OS.get_environment("EOA_YEAR_MULTI_AI").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_UI_SMOKE").strip_edges() == "1":
		return false
	# Explicit opt-out of all interactive extras
	if not is_interactive_light_sim():
		return false
	return true


func _maybe_run_interactive_multi_ai() -> void:
	if not _should_run_interactive_multi_ai():
		return
	if typeof(GameData) == TYPE_NIL:
		return
	if not GameData.has_method("apply_interactive_multi_ai_day_live"):
		return
	GameData.call("apply_interactive_multi_ai_day_live", 1)


## Budgeted AI infra invest (max 1 new project/day). Same F5 light-sim gate as multi-AI.
## Killswitch: EOA_AI_INFRA=0 (also skipped when interactive multi-AI is off).
func _maybe_run_ai_infra_invest() -> void:
	if OS.get_environment("EOA_AI_INFRA").strip_edges() == "0":
		return
	if not _should_run_interactive_multi_ai():
		return
	if typeof(InfrastructureDevelopmentManager) == TYPE_NIL:
		return
	if not InfrastructureDevelopmentManager.has_method("try_ai_start_infra_project"):
		return
	var day_i := 0
	if has_method("get_total_days_elapsed"):
		day_i = int(get_total_days_elapsed())
	InfrastructureDevelopmentManager.try_ai_start_infra_project("", day_i)


## Budgeted AI start_land_battle (max 1/day). Same F5 light-sim gate as multi-AI.
## Killswitch: EOA_AI_LAND_BATTLES=0 (also skipped when interactive multi-AI is off).
func _maybe_run_ai_land_battle_starts() -> void:
	if OS.get_environment("EOA_AI_LAND_BATTLES").strip_edges() == "0":
		return
	if not _should_run_interactive_multi_ai():
		return
	if typeof(BattleManager) == TYPE_NIL:
		return
	if not BattleManager.has_method("try_ai_start_land_battles"):
		return
	var day_i := 0
	if has_method("get_total_days_elapsed"):
		day_i = int(get_total_days_elapsed())
	BattleManager.try_ai_start_land_battles(day_i)


func _tick_own_land_marches() -> void:
	if typeof(FormationMovement) == TYPE_NIL:
		return
	var moved: Array = FormationMovement.tick_all_marches(1.0)
	if moved.is_empty():
		return
	var arrived_n := 0
	for mv in moved:
		if mv is Dictionary and bool(mv.get("arrived", false)):
			arrived_n += 1
	if arrived_n > 0:
		print("TimeManager: own-land march arrived=%d hops=%d" % [arrived_n, moved.size()])


func _tick_open_land_battles() -> void:
	if typeof(BattleManager) == TYPE_NIL:
		return
	if not BattleManager.has_method("tick_open_land_battles"):
		return
	var resolved: Array = BattleManager.tick_open_land_battles(1.0)
	if resolved.is_empty():
		return
	var n := 0
	for ev in resolved:
		if ev is Dictionary and bool(ev.get("resolved", false)):
			n += 1
	if n > 0:
		print("TimeManager: open land battles resolved=%d" % n)


func _tick_organize_queue() -> void:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("tick_organize_day"):
		LeaderManager.tick_organize_day()


func _tick_out_of_combat_recovery() -> void:
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return
	var forms: Variant = LeaderManager.formations
	if typeof(forms) != TYPE_DICTIONARY:
		return
	var n: int = (forms as Dictionary).size()
	var budgeted := n > 400
	for fid in forms:
		var f: Formation = forms[fid] as Formation
		if f == null:
			continue
		if "is_training" in f and bool(f.is_training):
			continue
		if "is_in_combat" in f and bool(f.is_in_combat):
			continue
		if "fuel_level" in f:
			var marching := false
			if typeof(FormationMovement) != TYPE_NIL:
				marching = bool(FormationMovement.has_march(str(fid)))
			if not marching:
				var fuel_need := float(LandCombatPower.composition_from_formation(f).get("fuel_use", 0.0))
				if fuel_need > 1e-9:
					if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("refuel_formation_from_stockpile"):
						var rfid := str(f.formation_id) if "formation_id" in f else str(fid)
						ProductionManager.refuel_formation_from_stockpile(rfid, 0.10)
					else:
						LandCombatPower.apply_fuel_resupply(f, 0.10)
		var org := float(f.organization) if "organization" in f else 1.0
		var plan := float(f.planning) if "planning" in f else 1.0
		var strn := float(f.strength) if "strength" in f else 1.0
		if budgeted and org >= 0.99 and plan >= 1.0 and strn >= 0.99:
			continue
		if "strength" in f and strn < 1.0:
			var new_s := clampf(strn + 0.03, 0.0, 1.0)
			var gain := new_s - strn
			f.strength = new_s
			if gain > 0.0001 and "combat_experience" in f:
				f.combat_experience = LandCombatPower.dilute_xp_replacements(
					float(f.combat_experience), gain, new_s, 22.0
				)
		var rec := 0.06
		var pid := int(f.stationed_province_id) if "stationed_province_id" in f else -1
		if pid >= 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			var p: Province = MapManager.get_province(pid)
			if p != null and p.has_method("get_organization_recovery_modifier"):
				rec = 0.06 * float(p.get_organization_recovery_modifier())
		if "organization" in f:
			f.organization = clampf(org + rec, 0.0, 1.0)
		if "readiness" in f:
			f.readiness = clampf(float(f.readiness) + 0.04, 0.0, 1.0)
		var defend := "current_land_mission" in f and str(f.current_land_mission) == Formation.LAND_MISSION_DEFEND
		if defend and "entrenchment" in f:
			f.entrenchment = clampf(float(f.entrenchment) + 0.06, 0.0, 1.0)
		if "planning" in f:
			f.planning = clampf(plan + 0.08, 0.0, 1.0)


## True for normal graphical F5 play — keep day ticks light so HUD/map stay responsive.
func is_interactive_light_sim() -> bool:
	if OS.get_environment("EOA_UI_SMOKE").strip_edges() == "1":
		return true
	if OS.get_environment("EOA_HEAVY_DAILY").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_RUN_SIM_CYCLES").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_RUN_50_TURN_SIM").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_RUN_LONG_SIM").strip_edges() == "1":
		return false
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return false
	return true


## Called by real-time timers (e.g. TopInfoBar) to advance simulation based on wall time.
## `real_seconds` is real elapsed time since last call.
## Respects `time_scale` and `paused`.
## 1× rate: **1 wall second ≈ 1 game hour** (not 1 day). 2×/3×/4× scale hours.
## Full day handlers only fire when the calendar day rolls (after 24 hours).
func advance_real_time(real_seconds: float) -> void:
	if paused:
		return
	if real_seconds <= 0.0:
		return
	# Hours this tick: 1.0 wall-sec * scale = hours at 1×…4×.
	var hours_this_tick := real_seconds * maxf(time_scale, 0.1)
	# Cap: never more than 6 game hours per wall tick (keeps UI live at high speed).
	if not _should_run_daily_ai_combat():
		hours_this_tick = minf(hours_this_tick, 6.0)
	advance_hours(hours_this_tick)


## Advance fractional game hours. Rolls into advance_days when 24h accumulate.
func advance_hours(hours: float) -> void:
	if paused or hours <= 0.0:
		return
	_accumulated_game_hours += hours
	var whole := int(_accumulated_game_hours)
	if whole <= 0:
		return
	_accumulated_game_hours -= float(whole)
	var days_crossed := 0
	for _i in whole:
		current_hour += 1
		if current_hour >= 24:
			current_hour = 0
			days_crossed += 1
	if days_crossed > 0:
		# Advance whole days (emits day signals / multi-AI once per day, not per hour).
		advance_days(float(days_crossed))

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
		"current_hour": current_hour,
	}

## Applies previously saved calendar state. Does NOT emit day/month/year signals
## (we are restoring, not simulating forward).
func apply_save_data(data: Dictionary) -> void:
	if data.has("current_hour"):
		current_hour = clampi(int(data.get("current_hour", 0)), 0, 23)
	if data.has("current_date"):
		var d: Dictionary = data["current_date"]
		current_year = int(d.get("year", 1936))
		if d.has("hour"):
			current_hour = clampi(int(d.get("hour", current_hour)), 0, 23)
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
