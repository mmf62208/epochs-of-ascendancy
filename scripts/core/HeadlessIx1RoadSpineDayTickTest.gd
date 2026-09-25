extends SceneTree

## Prove the F5 day clock advances with an IX-1 Road Spine in progress
## past the live freeze (~day 7–9 / ~17–20%), and that a short automated
## path can complete the spine. Does not require the 3520 board.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessIx1RoadSpineDayTickTest.gd

const SRC_IDM := "res://scripts/map/InfrastructureDevelopmentManager.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_SAVE := "res://scripts/autoload/SaveLoadManager.gd"
const SRC_TM := "res://scripts/autoload/TimeManager.gd"
const SRC_TR := "res://scripts/core/TestRunner.gd"
const SRC_AGENT := "res://scripts/agents/AgentManager.gd"
const SRC_TOAST := "res://scripts/ui/LeaderEventUI.gd"
const SRC_MAPMODE := "res://scripts/ui/map/MapModeToolbar.gd"
const SRC_TITLE := "res://scripts/ui/LivingTitleBoot.gd"
const SRC_CC := "res://scripts/ui/MainMenu.gd"
const SRC_SCENE := "res://scenes/TestScenario.tscn"
const HUB_ID := 710417
const FREEZE_PROGRESS := 20.0
const LIVE_DAY_BUDGET_MS := 18000
const LIVE_SOAK_DAYS := 8

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessIx1RoadSpineDayTickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessIx1RoadSpineDayTickTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessIx1RoadSpineDayTickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessIx1RoadSpineDayTickTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _run() -> void:
	_test_source_gates_full_board_ai_invest()
	_test_source_live_f5_path_cannot_full_board_scan()
	_test_source_progress_does_not_renotify()
	_test_clock_advances_past_freeze()
	_test_spine_can_complete()
	_test_live_f5_equivalent_day_advance()
	_test_play_begin_clock_controls_leave_midnight()
	_test_live_f5_softpipe_past_plus6_soak()
	_test_smoke_advance_past_plus6_after_hatch()
	_test_smoke_advance_chunked_live_path()
	_test_smoke_advance_softpipe_starvation_catchup()
	_test_smoke_advance_softpipe_stay_alive_after_past7()
	_test_mandate_cost_still_zero()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt := src.find("\nfunc ", i + needle.length())
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _test_source_gates_full_board_ai_invest() -> void:
	var idm := _read(SRC_IDM)
	if idm.is_empty():
		_fail("InfrastructureDevelopmentManager.gd missing")
		return
	var gate := _slice_func(idm, "_should_run_full_board_ai_invest")
	var adv := _slice_func(idm, "advance_daily_projects")
	if "is_interactive_light_sim" not in gate:
		_fail("_should_run_full_board_ai_invest must gate on F5 light sim")
		return
	if "_should_run_full_board_ai_invest" not in adv:
		_fail("advance_daily_projects must consult the light-sim AI-invest gate")
		return
	if "ai_consider_daily_invests" not in adv:
		_fail("advance_daily_projects lost ai_consider_daily_invests (harness path)")
		return
	var save := _read(SRC_SAVE)
	if "_deferred_calendar_autosave" not in save:
		_fail("calendar autosave must be deferred off day_emit")
		return
	var autosave_hook := _slice_func(save, "_on_day_advanced_for_autosave")
	if "is_live_f5_play_path" not in autosave_hook and "_should_skip_live_f5_calendar_autosave" not in autosave_hook:
		_fail("calendar autosave must skip live F5 / softpipe (day +5/+6 OOM)")
		return
	if "is_live_f5_play_path" not in gate and "DisplayServer.get_name()" not in gate:
		_fail("full-board AI gate must also skip graphical editor/export Play, not only light_sim")
		return
	_pass("F5 light sim skips full-board AI invest; autosave deferred")


func _test_source_live_f5_path_cannot_full_board_scan() -> void:
	var idm := _read(SRC_IDM)
	var pick := _slice_func(idm, "_pick_ai_infra_province")
	if pick.is_empty():
		_fail("_pick_ai_infra_province missing")
		return
	if "get_all_provinces(" in pick or "get_provinces_by_owner(" in pick:
		_fail("live AI infra pick still walks get_all_provinces / get_provinces_by_owner")
		return
	if "AI_INFRA_PICK_CAP" not in pick:
		_fail("live AI infra pick must cap candidates")
		return
	var start := _slice_func(idm, "start_infrastructure_project")
	if "_should_quiet_ai_infra_start" not in start:
		_fail("AI infra start must quiet toast/notify on live F5")
		return
	var sim := _slice_func(idm, "simulate_live_f5_day_advance")
	if sim.is_empty() or "advance_live_f5_equivalent_days" not in sim:
		_fail("simulate_live_f5_day_advance must drive live-equiv days (not playtest clock)")
		return
	if "advance_live_f5_equivalent_hours" not in sim or "past_hour_plus6" not in sim:
		_fail("simulate_live_f5_day_advance must drive TopInfoBar hour clock (not days-only)")
		return
	if "past_plus6" not in sim or "calendar_autosave_gathers" not in sim:
		_fail("simulate_live_f5_day_advance must prove past +6 and skip calendar autosave")
		return
	if "living_playtest_clock" in sim and "advance_living_playtest_days" in sim:
		_fail("live-equiv sim must not use advance_living_playtest_days")
		return
	var tm := _read(SRC_TM)
	var live := _slice_func(tm, "advance_live_f5_equivalent_days")
	if live.is_empty() or "_living_playtest_clock = true" in live:
		_fail("advance_live_f5_equivalent_days must not set _living_playtest_clock")
		return
	if "_live_f5_equiv_clock = true" not in live:
		_fail("advance_live_f5_equivalent_days must set _live_f5_equiv_clock")
		return
	var hours := _slice_func(tm, "advance_live_f5_equivalent_hours")
	if hours.is_empty() or "advance_real_time" not in hours:
		_fail("advance_live_f5_equivalent_hours must drive advance_real_time (TopInfoBar path)")
		return
	var live_path := _slice_func(tm, "is_live_f5_play_path")
	if "DisplayServer.get_name()" not in live_path:
		_fail("is_live_f5_play_path must use DisplayServer (windowed Play, not equiv-flag only)")
		return
	if "return is_interactive_light_sim()" in live_path:
		_fail("is_live_f5_play_path must not defer to light_sim (headless-only paper-over)")
		return
	var rings := _slice_func(_read(SRC_REN), "_refresh_feature_progress_rings")
	if "is_interactive_light_sim" not in rings:
		_fail("feature-ring day walk must early-out on F5 light sim")
		return
	if "is_live_f5_play_path" not in rings:
		_fail("feature-ring day walk must early-out on is_live_f5_play_path")
		return
	var day_emit := _slice_func(_read(SRC_REN), "_on_game_day_advanced_legend")
	if "is_live_f5_play_path" not in day_emit:
		_fail("MapRenderer day_emit must gate on is_live_f5_play_path (DisplayServer Play)")
		return
	var top_click := _slice_func(_read(SRC_REN), "_top_bar_owns_click")
	if top_click.is_empty() or "get_global_rect" not in top_click:
		_fail("_top_bar_owns_click must rect-test TopInfoBar (softpipe hover miss)")
		return
	var input_fn := _slice_func(_read(SRC_REN), "_input")
	if "_top_bar_owns_click" not in input_fn or "_top_bar_owns_click()" not in input_fn:
		_fail("MapRenderer._input must early-out on TopInfoBar before leftover pick swallow")
		return
	var tr := _read(SRC_TR)
	var boot_closed := _slice_func(tr, "_on_living_title_boot_closed")
	if "mark_living_title_closed" not in boot_closed or "release_play_clock_input_blockers" not in boot_closed:
		_fail("living title Begin must mark clock runnable and clear leftover pick-block")
		return
	var ensure := _slice_func(tr, "_ensure_game_interactive")
	if "should_force_playtest_start_pause" not in ensure and "eoa_living_title_closed" not in ensure:
		_fail("_ensure_game_interactive must not force-pause after living title Begin")
		return
	var begin_clock := _slice_func(tm, "simulate_play_begin_clock_controls")
	if begin_clock.is_empty() or "should_force_playtest_start_pause" not in begin_clock:
		_fail("simulate_play_begin_clock_controls must prove Begin+4x is not re-paused")
		return
	if "advance_real_time" not in begin_clock or "past_hour_plus6" not in begin_clock:
		_fail("simulate_play_begin_clock_controls must drive advance_real_time past +6")
		return
	var soak := _slice_func(tm, "simulate_live_f5_softpipe_past_plus6")
	if soak.is_empty() or "past_7_jan" not in soak or "advance_real_time" not in soak:
		_fail("simulate_live_f5_softpipe_past_plus6 must drive hour clock past 7 Jan")
		return
	if "Province captured" not in soak or "toast_mouse_ignore" not in soak:
		_fail("softpipe soak must exercise capture toasts + input ignore")
		return
	var agent_day := _slice_func(_read(SRC_AGENT), "_on_game_day_advanced")
	if "is_live_f5_play_path" not in agent_day:
		_fail("AgentManager day tick must skip networks on live F5 (day-6 pulse)")
		return
	var toast_src := _read(SRC_TOAST)
	if "live_f5_toast_stack_cannot_steal_top_bar" not in toast_src:
		_fail("LeaderEventUI must expose toast-stack cannot steal TopInfoBar")
		return
	if "MOUSE_FILTER_IGNORE" not in toast_src:
		_fail("toast container must IGNORE empty chrome (layer 90 swallow)")
		return
	var mapmode := _read(SRC_MAPMODE)
	if "live_f5_cannot_steal_top_bar" not in mapmode or "MOUSE_FILTER_IGNORE" not in mapmode:
		_fail("MapModeToolbar must IGNORE + clip so it cannot steal TopInfoBar")
		return
	var scene := _read(SRC_SCENE)
	if "layer = 110" not in scene:
		_fail("TestScenario UILayer must be 110 (above Map Mode 20 and toasts 90)")
		return
	var title_src := _read(SRC_TITLE)
	if "LIVING_TITLE_LAYER := 120" not in title_src and "layer = 120" not in title_src:
		_fail("LivingTitleBoot must sit above UILayer 110 so Begin is not buried")
		return
	var cc_src := _read(SRC_CC)
	if "COMMAND_CENTER_LAYER := 130" not in cc_src and "layer = 130" not in cc_src:
		_fail("Command Center must sit above UILayer 110 so Esc→CC is visible")
		return
	if "ui_layer.layer = 20" in tr:
		_fail("TestRunner must not smash UILayer back to 20 (buries bar under toasts, fights title/CC)")
		return
	if "_living_title_boot_is_up" not in _read(SRC_REN):
		_fail("MapRenderer must route Esc/map clicks around living title (no inspector swallow / window-exit)")
		return
	if "_living_title_owns_click" not in _read(SRC_REN):
		_fail("MapRenderer must rect-first living title clicks (live Begin cannot depend on hover)")
		return
	if "is_live_escape_event" not in _read(SRC_TITLE) or "handle_live_begin" not in _read(SRC_TITLE):
		_fail("LivingTitleBoot must own live Esc/Begin input (not layer-only)")
		return
	var smoke_tm := _slice_func(tm, "apply_smoke_advance_past_plus6")
	var smoke_sync := _slice_func(tm, "_run_smoke_advance_sync")
	if smoke_tm.is_empty() or "should_chunk_smoke_advance" not in smoke_tm:
		_fail("apply_smoke_advance_past_plus6 must dispatch live chunked vs headless sync")
		return
	if smoke_sync.is_empty() or "advance_real_time" not in smoke_sync or "past_7_jan" not in tm:
		_fail("headless sync smoke must still drive advance_real_time past 7 Jan")
		return
	if "func step_smoke_advance_chunk" not in tm or "window_stay" not in tm:
		_fail("live smoke past-+6 must chunk per frame with window_stay (no sync ×48)")
		return
	if "func smoke_advance_should_defer_combat" not in tm:
		_fail("live smoke must defer combat load while chunking")
		return
	if "func nudge_smoke_advance_chunk" not in tm or "func smoke_advance_should_catchup_on_arm" not in tm:
		_fail("live smoke must catch-up when softpipe idle frames are scarce")
		return
	if "softpipe_catchup" not in tm or "nudge_starve" not in tm:
		_fail("live smoke must log softpipe_catchup (Play 8129648 starve)")
		return
	var catchup := _slice_func(tm, "_smoke_chunk_catchup")
	if catchup.is_empty() or "pump_smoke_advance_chunk_until_past7" not in catchup:
		_fail("softpipe catch-up must reuse the chunked pump (no sync ×48 flush)")
		return
	if "_flush_sim_events" in catchup or "_drain_living_f5_flush" in catchup or "_run_smoke_advance_sync" in catchup:
		_fail("softpipe catch-up must not flush combat / re-enter sync ×48")
		return
	var start_fn := _slice_func(tm, "_start_smoke_advance_chunked")
	if "smoke_advance_should_catchup_on_arm" not in start_fn:
		_fail("live chunked start must catch-up on arm under softpipe")
		return
	if "initialize_from_scenario_start_date" in smoke_tm or "initialize_from_scenario_start_date" in smoke_sync:
		_fail("smoke advance must not reset the live calendar (not a soak reset)")
		return
	if "NOT product clock" not in tm and "product_clock_pass" not in tm:
		_fail("smoke advance must stay labeled as not product clock PASS")
		return
	var smoke_bar := _slice_func(_read("res://scripts/ui/TopInfoBar.gd"), "apply_smoke_advance_past_plus6")
	if smoke_bar.is_empty() or "_set_game_speed(4)" not in smoke_bar:
		_fail("TopInfoBar smoke advance must use _set_game_speed(4) owner path")
		return
	if "chunked_pending" not in smoke_bar:
		_fail("TopInfoBar must poll chunked smoke until past7 (not cache pending)")
		return
	if "func smoke_advance_past_plus6_enabled" not in _read(SRC_TITLE):
		_fail("LivingTitleBoot must expose smoke_advance_past_plus6_enabled")
		return
	if "_smoke_advance_past_plus6_after_hatch" not in tr:
		_fail("TestRunner must hook smoke past-+6 after hatch")
		return
	if "_poll_smoke_advance_past_plus6" not in tr or "window_stay" not in tr:
		_fail("TestRunner must poll chunked live smoke and log window_stay")
		return
	if "_nudge_smoke_advance_past_plus6" not in tr or "nudge_smoke_advance_chunk" not in tr:
		_fail("TestRunner poller must nudge the chunker (not sit on pending)")
		return
	if "func smoke_advance_should_stay_alive" not in tm or "EOA_SMOKE_STAYALIVE" not in tm:
		_fail("TimeManager must arm smoke stay-alive after past7 (Play 9625020 window death)")
		return
	if "func _drop_smoke_deferred_load" not in tm:
		_fail("stay-alive must drop queued day_emit/day_ai/day_battles (not battles-only)")
		return
	var adv_days := _slice_func(tm, "advance_days")
	if "_tick_live_construction_on_calendar_day" not in adv_days:
		_fail("light-sim advance_days must tick IDM construction (stay-alive drops day_emit)")
		return
	if "func _tick_live_construction_on_calendar_day" not in tm:
		_fail("_tick_live_construction_on_calendar_day missing")
		return
	var idm_day := _slice_func(_read(SRC_IDM), "_on_game_day_advanced")
	if "eoa_idm_calendar_tick_elapsed" not in idm_day:
		_fail("IDM must skip a second tick when the calendar already advanced projects")
		return
	var stay_defer := _slice_func(tm, "smoke_advance_should_defer_combat")
	if "_smoke_stay_alive" not in stay_defer:
		_fail("combat must stay deferred after past7 stay-alive")
		return
	var stay_proc := _slice_func(tm, "_process")
	if "_smoke_stay_alive" not in stay_proc:
		_fail("TimeManager._process must not 4x self-drive during stay-alive")
		return
	var after_hatch := _slice_func(tr, "_finish_smoke_advance_after_hatch")
	if after_hatch.is_empty() or "get_tree().quit" in after_hatch:
		_fail("TestRunner.after_hatch must not quit after past7")
		return
	if "EOA_SMOKE_STAYALIVE" not in after_hatch or "no_quit" not in after_hatch:
		_fail("TestRunner.after_hatch must log stay-alive / no_quit")
		return
	if "_restore_live_search_chrome_after_stay_alive" not in tr or "EOA_SMOKE_SEARCH_CHROME" not in tr:
		_fail("TestRunner must restore live Search chrome after stay-alive (not headless-only)")
		return
	if "EOA_SMOKE_SEARCH_CHROME_PIXEL" not in tr or "search_chrome_pixel_report" not in tr:
		_fail("TestRunner must log EOA_SMOKE_SEARCH_CHROME_PIXEL and use pixel report")
		return
	if "ensure_live_search_chrome" not in after_hatch and "ensure_live_search_chrome" not in _slice_func(tr, "_restore_live_search_chrome_after_stay_alive"):
		_fail("stay-alive after_hatch must call MapRenderer.ensure_live_search_chrome")
		return
	if "_smoke_search_chrome_sticky_after_reflow" not in tr or "layout_settle" not in tr:
		_fail("stay-alive must PIXEL-check Search after TopInfoBar layout settle (sticky, not first-paint)")
		return
	if "_smoke_should_gate_post_hatch_heavy" not in tr or "skip_front_chips" not in tr:
		_fail("TestRunner must gate post-hatch unit-icon flood under stay-alive")
		return
	_pass("live F5 path cannot full-board AI scan; toast quiet; ring/day_emit/hour clock gated")


func _test_source_progress_does_not_renotify() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var prog := _slice_func(ren, "_on_infra_progress_for_inspector")
	if prog.is_empty():
		_fail("_on_infra_progress_for_inspector missing")
		return
	if "notify_province_changed(" in prog:
		_fail("progress handler still notify_province_changed (inspector rebuild loop)")
		return
	var changed := _slice_func(ren, "_on_map_province_data_changed")
	if "selected_province_id" not in changed or "infrastructure_project" not in changed:
		_fail("province_data_changed must light-refresh only the selected spine hex")
		return
	_pass("spine progress no longer re-enters show_info_panel via notify")


func _test_clock_advances_past_freeze() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("simulate_ix1_spine_days"):
		_fail("simulate_ix1_spine_days missing")
		return
	if idm.has_method("initialize_with_time"):
		idm.call("initialize_with_time")
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = idm.call("simulate_ix1_spine_days", 12)
	var ms := Time.get_ticks_msec() - t0
	var elapsed := int(result.get("elapsed_delta", 0))
	var after := float(result.get("progress_after", 0.0))
	var before := float(result.get("progress_before", 0.0))
	if elapsed < 12:
		_fail("clock did not advance 12 days with spine active (elapsed_delta=%d) %s" % [elapsed, str(result)])
		return
	if after <= before and not bool(result.get("completed", false)):
		_fail("spine progress did not increase: %.1f → %.1f" % [before, after])
		return
	if after <= FREEZE_PROGRESS and not bool(result.get("past_freeze", false)):
		_fail("spine still at freeze point (%.1f%%)" % after)
		return
	if ms > 20000:
		_fail("12-day spine tick took %dms (still wedged)" % ms)
		return
	_pass(
		"clock +12d spine %.1f%% → %.1f%% past_freeze=%s (%dms)"
		% [before, after, str(result.get("past_freeze")), ms]
	)


func _test_spine_can_complete() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	# Continue the same Köln project (already past 20%) on the cheap daily tick.
	# A second F5 flush of 30d OOMs air/day listeners; complete does not need that path.
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = idm.call("simulate_ix1_spine_days", 30, false)
	var ms := Time.get_ticks_msec() - t0
	var completed := bool(result.get("completed", false))
	var after := float(result.get("progress_after", 0.0))
	if not completed and after < 99.0:
		_fail("spine did not complete on short path: %s" % str(result))
		return
	if ms > 45000:
		_fail("complete path took %dms" % ms)
		return
	_pass("spine complete=%s progress=%.1f elapsed_delta=%s (%dms)" % [
		str(completed or after >= 99.0), after, str(result.get("elapsed_delta")), ms
	])


func _test_live_f5_equivalent_day_advance() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("simulate_live_f5_day_advance"):
		_fail("simulate_live_f5_day_advance missing")
		return
	if idm.has_method("initialize_with_time"):
		idm.call("initialize_with_time")
	var tm: Node = _autoload("TimeManager")
	if tm != null and tm.has_method("is_live_f5_play_path"):
		# Before the run, headless without the equiv flag is not Play.
		pass
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = idm.call("simulate_live_f5_day_advance", LIVE_SOAK_DAYS)
	var ms := Time.get_ticks_msec() - t0
	var elapsed := int(result.get("elapsed_delta", 0))
	var consider := int(result.get("full_board_ai_invest_calls", -1))
	var gate_on := bool(result.get("full_board_ai_invest", true))
	var considered := int(result.get("provinces_considered", 9999))
	var gathers := int(result.get("calendar_autosave_gathers", -1))
	var mem_delta := int(result.get("memory_delta_bytes", -1))
	if not bool(result.get("ok", false)):
		_fail("live-F5-equiv day advance not ok: %s" % str(result))
		return
	if elapsed < LIVE_SOAK_DAYS:
		_fail("live-F5-equiv clock did not advance %d days (elapsed_delta=%d) %s" % [LIVE_SOAK_DAYS, elapsed, str(result)])
		return
	if not bool(result.get("past_plus2", false)):
		_fail("live-F5-equiv did not prove past day +2: %s" % str(result))
		return
	if not bool(result.get("past_plus6", false)):
		_fail("live-F5-equiv did not prove past day +6: %s" % str(result))
		return
	if not bool(result.get("past_hour_plus6", false)):
		_fail("live-F5-equiv did not prove TopInfoBar hour clock past +6: %s" % str(result))
		return
	if consider != 0:
		_fail("full-board ai_consider_daily_invests ran %d times on live-equiv path" % consider)
		return
	if gate_on:
		_fail("live-equiv still enables _should_run_full_board_ai_invest")
		return
	if considered > 16:
		_fail("live AI infra pick considered %d provinces (cap 16)" % considered)
		return
	if gathers != 0:
		_fail("calendar autosave gathered %d times on live-equiv path (must skip)" % gathers)
		return
	if mem_delta > 48 * 1024 * 1024:
		_fail("live-F5-equiv memory grew %d bytes (unbounded)" % mem_delta)
		return
	if ms > LIVE_DAY_BUDGET_MS:
		_fail("live-F5-equiv %dd took %dms (wedged)" % [LIVE_SOAK_DAYS, ms])
		return
	if bool(result.get("living_playtest_clock", true)):
		_fail("live-equiv result must not claim living_playtest_clock")
		return
	_pass(
		"live-F5-equiv +%dd past+6 hour+6 consider=%d pick=%d autosave=0 mem=%d (%dms)"
		% [elapsed, consider, considered, mem_delta, ms]
	)


func _test_play_begin_clock_controls_leave_midnight() -> void:
	var tm: Node = _autoload("TimeManager")
	if tm == null:
		_fail("TimeManager autoload missing")
		return
	if not tm.has_method("simulate_play_begin_clock_controls"):
		_fail("simulate_play_begin_clock_controls missing (stuck-paused after Begin would pass)")
		return
	if not tm.has_method("should_force_playtest_start_pause"):
		_fail("should_force_playtest_start_pause missing")
		return
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-01")
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if tm.has_meta("eoa_living_title_closed"):
		tm.remove_meta("eoa_living_title_closed")
	if not bool(tm.call("should_force_playtest_start_pause")):
		_fail("should_force_playtest_start_pause must be true before living title Begin")
		return
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = tm.call("simulate_play_begin_clock_controls", 8)
	var ms := Time.get_ticks_msec() - t0
	if bool(result.get("would_force_repause_after_begin", true)):
		_fail("Begin must leave clock runnable (TestRunner would re-pause 4x): %s" % str(result))
		return
	if bool(result.get("stuck_paused", true)):
		_fail("4x after Begin left TimeManager paused: %s" % str(result))
		return
	if not bool(result.get("ok", false)):
		_fail("play-begin clock controls not ok: %s" % str(result))
		return
	if not bool(result.get("left_00", false)):
		_fail("play-begin 4x did not leave 1 Jan 00:00: %s" % str(result))
		return
	if not bool(result.get("past_hour_plus6", false)):
		_fail("play-begin 4x did not prove past hour +6: %s" % str(result))
		return
	if int(result.get("hour_delta", 0)) < 6:
		_fail("play-begin hour_delta=%s (need ≥6)" % str(result.get("hour_delta")))
		return
	_pass(
		"play-begin 4x left 00:00 hour_delta=%s past+6 paused=%s (%dms)"
		% [str(result.get("hour_delta")), str(result.get("paused")), ms]
	)


func _test_live_f5_softpipe_past_plus6_soak() -> void:
	var tm: Node = _autoload("TimeManager")
	if tm == null:
		_fail("TimeManager autoload missing")
		return
	if not tm.has_method("simulate_live_f5_softpipe_past_plus6"):
		_fail("simulate_live_f5_softpipe_past_plus6 missing (6 Jan 20:00 wedge would PASS)")
		return
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-01")
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = tm.call("simulate_live_f5_softpipe_past_plus6")
	var ms := Time.get_ticks_msec() - t0
	if bool(result.get("paused", true)):
		_fail("softpipe soak left TimeManager paused: %s" % str(result))
		return
	if bool(result.get("stuck_at_6_jan", true)):
		_fail("softpipe soak stuck at 6 Jan: %s" % str(result))
		return
	if not bool(result.get("past_7_jan", false)):
		_fail("softpipe soak did not pass 7 Jan: %s" % str(result))
		return
	if not bool(result.get("past_plus6", false)):
		_fail("softpipe soak did not prove past day +6: %s" % str(result))
		return
	if not bool(result.get("harvest_day5", false)):
		_fail("softpipe soak never crossed day +5 harvest cadence: %s" % str(result))
		return
	if int(result.get("calendar_autosave_gathers", 1)) != 0:
		_fail("softpipe soak gathered calendar autosave: %s" % str(result))
		return
	if not bool(result.get("toast_mouse_ignore", false)):
		_fail("toast stack still steals TopInfoBar: %s" % str(result))
		return
	if not bool(result.get("ok", false)):
		_fail("softpipe past-+6 soak not ok: %s" % str(result))
		return
	if ms > LIVE_DAY_BUDGET_MS:
		_fail("softpipe soak took %dms (wedged)" % ms)
		return
	_pass(
		"softpipe soak past 7 Jan day=%s elapsed=%s paused=%s autosave=0 toast_ignore=1 (%dms)"
		% [str(result.get("day")), str(result.get("elapsed_delta")), str(result.get("paused")), ms]
	)


func _test_smoke_advance_past_plus6_after_hatch() -> void:
	var tm: Node = _autoload("TimeManager")
	if tm == null:
		_fail("TimeManager autoload missing")
		return
	if not tm.has_method("apply_smoke_advance_past_plus6"):
		_fail("apply_smoke_advance_past_plus6 missing (smoke softpipe would stay 1 Jan)")
		return
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-01")
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if tm.has_method("set_time_scale"):
		tm.call("set_time_scale", 1.0)
	if tm.has_meta("eoa_smoke_advance_applied"):
		tm.remove_meta("eoa_smoke_advance_applied")
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
	var skipped: Dictionary = tm.call("apply_smoke_advance_past_plus6") as Dictionary
	if bool(skipped.get("ok", true)) or str(skipped.get("reason", "")) != "flag_off":
		_fail("smoke advance must no-op when flags are unset: %s" % str(skipped))
		return
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "1")
	if tm.has_meta("eoa_smoke_advance_applied"):
		tm.remove_meta("eoa_smoke_advance_applied")
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = tm.call("apply_smoke_advance_past_plus6") as Dictionary
	var ms := Time.get_ticks_msec() - t0
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
	if bool(result.get("product_clock_pass", false)):
		_fail("smoke advance must not claim product clock PASS")
		return
	if bool(result.get("paused", true)):
		_fail("smoke advance left TimeManager paused: %s" % str(result))
		return
	if not bool(result.get("past_7_jan", false)):
		_fail("smoke advance did not pass 7 Jan: %s" % str(result))
		return
	if not bool(result.get("past_plus6", false)):
		_fail("smoke advance did not prove past day +6: %s" % str(result))
		return
	if not bool(result.get("ok", false)):
		_fail("smoke advance not ok: %s" % str(result))
		return
	if int(result.get("day", 0)) <= 7 and int(result.get("month", 1)) == 1:
		_fail("smoke advance calendar still on/before 7 Jan: %s" % str(result))
		return
	if ms > LIVE_DAY_BUDGET_MS:
		_fail("smoke advance took %dms (wedged)" % ms)
		return
	_pass(
		"smoke advance past 7 Jan day=%s elapsed=%s paused=%s (NOT product clock PASS) (%dms)"
		% [str(result.get("day")), str(result.get("elapsed_delta")), str(result.get("paused")), ms]
	)


func _test_smoke_advance_chunked_live_path() -> void:
	var tm: Node = _autoload("TimeManager")
	if tm == null:
		_fail("TimeManager autoload missing")
		return
	if not tm.has_method("step_smoke_advance_chunk") or not tm.has_method("pump_smoke_advance_chunk_until_past7"):
		_fail("chunked live smoke stepper missing (sync ×48 would kill the window)")
		return
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-01")
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if tm.has_method("set_time_scale"):
		tm.call("set_time_scale", 1.0)
	if tm.has_meta("eoa_smoke_advance_applied"):
		tm.remove_meta("eoa_smoke_advance_applied")
	if tm.has_meta("eoa_smoke_force_chunk"):
		tm.remove_meta("eoa_smoke_force_chunk")
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "1")
	tm.set_meta("eoa_smoke_force_chunk", true)
	var pending: Dictionary = tm.call("apply_smoke_advance_past_plus6") as Dictionary
	if str(pending.get("reason", "")) != "chunked_pending":
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		_fail("force-chunk must return chunked_pending (not sync ×48): %s" % str(pending))
		return
	if bool(pending.get("product_clock_pass", false)):
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		_fail("chunked smoke must not claim product clock PASS")
		return
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = tm.call("pump_smoke_advance_chunk_until_past7", 64) as Dictionary
	var ms := Time.get_ticks_msec() - t0
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
	tm.remove_meta("eoa_smoke_force_chunk")
	if bool(result.get("product_clock_pass", false)):
		_fail("chunked smoke must not claim product clock PASS")
		return
	if not bool(result.get("past_7_jan", false)):
		_fail("chunked smoke did not pass 7 Jan: %s" % str(result))
		return
	if not bool(result.get("window_stay", false)):
		_fail("chunked smoke must prove window_stay: %s" % str(result))
		return
	if not bool(result.get("chunked", false)):
		_fail("chunked smoke result must stay labeled chunked: %s" % str(result))
		return
	if int(result.get("day", 0)) <= 7 and int(result.get("month", 1)) == 1:
		_fail("chunked smoke calendar still on/before 7 Jan: %s" % str(result))
		return
	if ms > LIVE_DAY_BUDGET_MS:
		_fail("chunked smoke took %dms (wedged)" % ms)
		return
	_pass(
		"chunked smoke past 7 Jan day=%s ticks=%s window_stay=1 (NOT product clock PASS) (%dms)"
		% [str(result.get("day")), str(result.get("ticks")), ms]
	)


func _test_smoke_advance_softpipe_starvation_catchup() -> void:
	## Play 8129648: chunked start armed, then TestRunner deferred load starved
	## _process — clock stuck 1 Jan 16:00, never past7. Prove catch-up completes
	## without idle frames and without sync ×48 + combat flush.
	var tm: Node = _autoload("TimeManager")
	if tm == null:
		_fail("TimeManager autoload missing")
		return
	if not tm.has_method("nudge_smoke_advance_chunk") or not tm.has_method("smoke_advance_should_catchup_on_arm"):
		_fail("softpipe catch-up APIs missing")
		return
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-01")
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if tm.has_method("set_time_scale"):
		tm.call("set_time_scale", 1.0)
	if tm.has_meta("eoa_smoke_advance_applied"):
		tm.remove_meta("eoa_smoke_advance_applied")
	if tm.has_meta("eoa_smoke_force_chunk"):
		tm.remove_meta("eoa_smoke_force_chunk")
	if tm.has_meta("eoa_smoke_force_softpipe_starve"):
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "1")
	tm.set_meta("eoa_smoke_force_chunk", true)
	tm.set_meta("eoa_smoke_force_softpipe_starve", true)
	var t0 := Time.get_ticks_msec()
	var armed: Dictionary = tm.call("apply_smoke_advance_past_plus6") as Dictionary
	var ms := Time.get_ticks_msec() - t0
	# No SceneTree idle / _process / pump_until from this test — arm catch-up only.
	if str(armed.get("reason", "")) == "chunked_pending":
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
		_fail("softpipe starve catch-up must complete on arm (not wait idle): %s" % str(armed))
		return
	if bool(armed.get("product_clock_pass", false)):
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
		_fail("starve catch-up must not claim product clock PASS")
		return
	if not bool(armed.get("past_7_jan", false)):
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
		_fail("starve catch-up did not pass 7 Jan: %s" % str(armed))
		return
	if not bool(armed.get("window_stay", false)):
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
		_fail("starve catch-up must prove window_stay: %s" % str(armed))
		return
	if not bool(armed.get("chunked", false)) or not bool(armed.get("catchup", false)):
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
		_fail("starve catch-up must stay labeled chunked+catchup: %s" % str(armed))
		return
	if int(armed.get("day", 0)) <= 7 and int(armed.get("month", 1)) == 1:
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
		_fail("starve catch-up calendar still on/before 7 Jan: %s" % str(armed))
		return
	if ms > LIVE_DAY_BUDGET_MS:
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
		_fail("starve catch-up took %dms (wedged)" % ms)
		return
	# Path B: no arm-catch-up — pending then nudge (poller under starvation).
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-01")
	if tm.has_meta("eoa_smoke_advance_applied"):
		tm.remove_meta("eoa_smoke_advance_applied")
	if tm.has_meta("eoa_smoke_force_softpipe_starve"):
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
	tm.set_meta("eoa_smoke_force_chunk", true)
	var pending: Dictionary = tm.call("apply_smoke_advance_past_plus6") as Dictionary
	if str(pending.get("reason", "")) != "chunked_pending":
		OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
		tm.remove_meta("eoa_smoke_force_chunk")
		_fail("force-chunk without starve meta must stay pending: %s" % str(pending))
		return
	var nudged: Dictionary = tm.call("nudge_smoke_advance_chunk") as Dictionary
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
	tm.remove_meta("eoa_smoke_force_chunk")
	if tm.has_meta("eoa_smoke_force_softpipe_starve"):
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
	if not bool(nudged.get("past_7_jan", false)) or not bool(nudged.get("catchup", false)):
		_fail("nudge under starve must catch-up past7: %s" % str(nudged))
		return
	if bool(nudged.get("product_clock_pass", false)):
		_fail("nudge catch-up must not claim product clock PASS")
		return
	_pass(
		"softpipe starve catch-up past 7 Jan day=%s ticks=%s catchup=1 window_stay=1 (NOT product clock PASS) (%dms)"
		% [str(armed.get("day")), str(armed.get("ticks")), ms]
	)


func _test_smoke_advance_softpipe_stay_alive_after_past7() -> void:
	## Play 9625020: after_hatch ok=true past7=true then Godot exited before
	## Search. Combat re-armed (AI battles + air) + deferred 252 unit icons +
	## 4x self-drive. Prove stay-alive drops the queue, keeps combat deferred,
	## pauses AFTER the ok/past7 dict, and never quits.
	var tm: Node = _autoload("TimeManager")
	if tm == null:
		_fail("TimeManager autoload missing")
		return
	if not tm.has_method("smoke_advance_should_stay_alive") or not tm.has_method("reset_smoke_stay_alive_for_tests"):
		_fail("stay-alive APIs missing")
		return
	if tm.has_method("initialize_from_scenario_start_date"):
		tm.call("initialize_from_scenario_start_date", "1936-01-01")
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if tm.has_method("set_time_scale"):
		tm.call("set_time_scale", 1.0)
	if tm.has_meta("eoa_smoke_advance_applied"):
		tm.remove_meta("eoa_smoke_advance_applied")
	if tm.has_meta("eoa_smoke_force_chunk"):
		tm.remove_meta("eoa_smoke_force_chunk")
	if tm.has_meta("eoa_smoke_force_softpipe_starve"):
		tm.remove_meta("eoa_smoke_force_softpipe_starve")
	if tm.has_meta("eoa_smoke_force_stay_alive"):
		tm.remove_meta("eoa_smoke_force_stay_alive")
	tm.call("reset_smoke_stay_alive_for_tests")
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "")
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "1")
	tm.set_meta("eoa_smoke_force_chunk", true)
	tm.set_meta("eoa_smoke_force_softpipe_starve", true)
	tm.set_meta("eoa_smoke_force_stay_alive", true)
	var queued: Array = []
	queued.append({"kind": "day_emit", "year": 1936, "month": 1, "day": 7})
	queued.append({"kind": "day_ai", "year": 1936, "month": 1, "day": 7})
	queued.append({"kind": "day_battles", "year": 1936, "month": 1, "day": 7})
	tm.set("_pending_sim_events", queued)
	var t0 := Time.get_ticks_msec()
	var armed: Dictionary = tm.call("apply_smoke_advance_past_plus6") as Dictionary
	var ms := Time.get_ticks_msec() - t0
	var left: Array = tm.get("_pending_sim_events") as Array
	var tm_paused := bool(tm.get("paused"))
	var defer_on := bool(tm.call("smoke_advance_should_defer_combat"))
	var stay_on := bool(tm.call("smoke_stay_alive_active"))
	OS.set_environment("EOA_SMOKE_ADVANCE_PAST_PLUS6", "")
	tm.remove_meta("eoa_smoke_force_chunk")
	tm.remove_meta("eoa_smoke_force_softpipe_starve")
	tm.remove_meta("eoa_smoke_force_stay_alive")
	tm.call("reset_smoke_stay_alive_for_tests")
	if tm.has_method("set_paused"):
		tm.call("set_paused", true)
	if bool(armed.get("product_clock_pass", false)):
		_fail("stay-alive must not claim product clock PASS")
		return
	if not bool(armed.get("past_7_jan", false)) or not bool(armed.get("catchup", false)):
		_fail("stay-alive must keep catch-up past7: %s" % str(armed))
		return
	if bool(armed.get("paused", true)):
		_fail("finish dict paused must stay false (ok/past7 claim): %s" % str(armed))
		return
	if not bool(armed.get("ok", false)):
		_fail("stay-alive must keep after_hatch ok=true: %s" % str(armed))
		return
	if not bool(armed.get("stay_alive", false)) or not bool(armed.get("no_quit", false)):
		_fail("finish dict must label stay_alive + no_quit: %s" % str(armed))
		return
	if not left.is_empty():
		_fail("stay-alive must drop queued day_emit/day_ai/day_battles: %s" % str(left))
		return
	if not defer_on:
		_fail("stay-alive must keep combat deferred after past7")
		return
	if not stay_on:
		_fail("stay-alive flag must arm on force-stay path")
		return
	if not tm_paused:
		_fail("live stay-alive must pause AFTER ok so 4x does not self-drive")
		return
	if not bool(armed.get("window_stay", false)):
		_fail("stay-alive must keep window_stay: %s" % str(armed))
		return
	if ms > LIVE_DAY_BUDGET_MS:
		_fail("stay-alive catch-up took %dms (wedged)" % ms)
		return
	_pass(
		"softpipe stay-alive after past7 day=%s catchup=1 stay_alive=1 no_quit=1 queued=0 paused_after_ok=1 (NOT product clock PASS) (%dms)"
		% [str(armed.get("day")), ms]
	)


func _test_mandate_cost_still_zero() -> void:
	var idm: Node = _autoload("InfrastructureDevelopmentManager")
	if idm == null:
		_fail("InfrastructureDevelopmentManager autoload missing")
		return
	if not idm.has_method("get_ix1_road_spine_mandate_cost"):
		_fail("get_ix1_road_spine_mandate_cost missing")
		return
	var cost := int(idm.call("get_ix1_road_spine_mandate_cost"))
	if cost != 0:
		_fail("Mandate front door regress: cost=%d" % cost)
		return
	var gate: Dictionary = idm.call("ix1_day0_mandate_can_start", "GER")
	if not bool(gate.get("ok", false)):
		_fail("GER 1936 day-0 Mandate gate failed after day-tick FIX: %s" % str(gate))
		return
	_pass("Mandate front door still 0 / day-0 gate ok")
