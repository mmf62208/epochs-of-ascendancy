# Headless: prove calendar advances past Feb 28 under interactive-light day handlers.
# Run:
#   EOA_UI_SMOKE=1 godot --headless --path . res://scenes/TestScenario.tscn --quit-after 90
# Or attach via TestRunner when EOA_FEB_CLOCK=1.
extends Node

const START_Y := 1936
const START_M := 2
const START_D := 25
const TARGET_DAYS := 10  # Feb 25 → Mar 6 (crosses Feb 28 → Mar 1)


func _ready() -> void:
	if OS.get_environment("EOA_FEB_CLOCK").strip_edges() != "1" and OS.get_environment("EOA_UI_SMOKE").strip_edges() != "1":
		return
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	if typeof(TimeManager) == TYPE_NIL:
		push_error("HeadlessFebClockAdvanceTest: no TimeManager")
		return
	# Force light path (same as F5 graphical) even if DisplayServer is headless.
	# is_interactive_light_sim already true under EOA_UI_SMOKE=1.
	TimeManager.set_paused(false)
	TimeManager.set_time_scale(1.0)
	TimeManager.current_year = START_Y
	TimeManager.current_month = START_M
	TimeManager.current_day = START_D
	TimeManager.total_days_elapsed = 55
	TimeManager._accumulated_game_days = 0.0
	print(
		"HeadlessFebClockAdvanceTest: start %04d-%02d-%02d light=%s"
		% [
			TimeManager.current_year,
			TimeManager.current_month,
			TimeManager.current_day,
			str(TimeManager.is_interactive_light_sim()),
		]
	)
	var t0 := Time.get_ticks_msec()
	var max_day_ms := 0
	for i in TARGET_DAYS:
		var before := "%04d-%02d-%02d" % [TimeManager.current_year, TimeManager.current_month, TimeManager.current_day]
		var d0 := Time.get_ticks_msec()
		TimeManager.advance_days(1.0)
		# Flush deferred month boundary (interactive defers Feb→Mar work).
		await get_tree().process_frame
		await get_tree().process_frame
		var d1 := Time.get_ticks_msec() - d0
		max_day_ms = maxi(max_day_ms, d1)
		var after := "%04d-%02d-%02d" % [TimeManager.current_year, TimeManager.current_month, TimeManager.current_day]
		print("HeadlessFebClockAdvanceTest: day %d  %s → %s  (%dms)" % [i + 1, before, after, d1])
		if before == after:
			push_error("HeadlessFebClockAdvanceTest: FAIL stuck at %s" % after)
			print("HeadlessFebClockAdvanceTest: RESULT=FAIL stuck")
			return
	var total := Time.get_ticks_msec() - t0
	var final := "%04d-%02d-%02d" % [TimeManager.current_year, TimeManager.current_month, TimeManager.current_day]
	var crossed_mar := TimeManager.current_month >= 3
	if not crossed_mar:
		push_error("HeadlessFebClockAdvanceTest: FAIL did not reach March (final=%s)" % final)
		print("HeadlessFebClockAdvanceTest: RESULT=FAIL no_march final=%s" % final)
		return
	print(
		"HeadlessFebClockAdvanceTest: RESULT=PASS final=%s total_ms=%d max_day_ms=%d"
		% [final, total, max_day_ms]
	)
