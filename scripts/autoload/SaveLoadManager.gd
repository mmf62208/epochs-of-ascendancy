# scripts/autoload/SaveLoadManager.gd
## Foundational Save / Load system for Epochs of Ascendancy.
##
## This is the first implementation (v1, pragmatic scope). It provides a working
## save/load loop for the most critical runtime state so that play sessions can
## be persisted and resumed. It is explicitly designed to be extended.
##
## === SAVE FORMAT (JSON, human-readable for debugging) ===
## Root dictionary:
## {
##   "save_version": 2,                    # Integer. Bump on breaking changes.
##   "metadata": {
##     "timestamp": "2026-05-18T14:30:00", # ISO-ish from Time.get_datetime_string_from_system
##     "scenario_id": "1936",              # Future: ScenarioLoader scenario identifier
##     "player_tag": "USA",
##     "play_time_seconds": 0              # Future: accumulated real play time
##   },
##   "time": {
##     "current_date": { "year": 1937, "month": 3, "day": 12, "date_string": "..." },
##     "scenario_start_date": "1936-01-01",
##     "paused": false,
##     "time_scale": 1.0
##   },
##   "technology": {
##     "country_state": { "USA": { "completed": {...}, "active": [...], ... }, ... }
##     # Mirrors TechnologyManager.country_state exactly for now.
##   },
##   "agents": {
##     "agents": { "USA": [ {agent dicts with @export + runtime fields}, ... ], ... },
##     "networks": { "123": { network dict }, ... }   # keyed by province_id string
##   },
##   "map": {
##     "provinces": [
##       { "id": 42, "owner_tag": "GER", "controller_tag": "GER",
##         "development_level": 5, "infrastructure": 8, ... }
##     ]
##   },
##   "supply": {
##     "depots": { "42": { "stockpile": ..., "sabotage_level": ... } },
##     "division_deployments": { "german_infantry_...": { "province_id": 5, "country_tag": "GER" } }
##   },
##   "national_modifiers": {
##     "country_modifiers": { "GER": [ {effect dicts with remaining_months etc.}, ... ] }
##   },
##   "misc": {},   # Future expansion
##   "infrastructure_projects": { "version": 1, "active_projects": { "42": {project dict}, ... } }
##   "land_war": { "version": 1, "open_battles": [ battle dicts ], "marches": { fid: order },
##                 "next_seq": 1, "last_aar": {} }
## }
## }
##
## === EXTENSIBILITY CONTRACT (how other managers participate - REQUIRED READING) ===
## Any manager with runtime state worth persisting should implement:
##
##   func get_save_data() -> Dictionary:
##       return { "my_mutable_thing": my_state.duplicate(true), "version": 1, ... }
##
##   func apply_save_data(data: Dictionary) -> void:
##       if data.has("my_mutable_thing"):
##           my_state = data["my_mutable_thing"].duplicate(true)
##       # Rebuild any caches, re-emit signals so UI reacts, re-wire listeners if needed.
##       print("MyManager: state restored")
##
##   (optional) func clear_for_load() -> void:  # if you want SaveLoad to call a full reset first
##
## Then SaveLoadManager will automatically call them (see _gather_save_data and _apply).
## Put a comment in *your* file header describing exactly what your section contains.
##
## Example for a brand new manager "FooManager":
##   - Add the two funcs above.
##   - In SaveLoadManager _gather, it will be picked up if you also add a "foo" key
##     or let the manager put whatever it wants under a conventional key.
##   - Document the dict shape in FooManager.gd so future developers know what to expect.
##
## This pattern keeps SaveLoadManager small and delegates all per-system knowledge
## to the owning manager.
##
## Current implementation mixes direct access (for speed on core singletons) with the
## method pattern. All accesses are guarded.
##
## === LOAD BEHAVIOR ===
## - Assumes a compatible scenario is already loaded (Map/Supply hubs/provinces exist).
## - Performs targeted clears on mutable runtime state before applying.
## - Applies in a deliberate order: Time → Map provinces → Supply depots → NMM effects
##   → Technology → Agents (networks reference provinces + agents).
## - Existing signals (province_data_changed, research_state_changed, etc.) are used
##   so UI, overlays, and daily ticks react correctly after load.
## - Does NOT re-advance time or fire daily ticks during load (avoids double-processing).
##
## === WHAT IS SAVED (current full state) ===
## - Time (date, start date, pause/scale)
## - Technology (full country research state + active progress)
## - Agents + Networks (full resources + daily effect trackers)
## - Map provinces (owner/controller, development, infrastructure, factories)
## - Supply depots (stockpile, throughput, sabotage_level) + division_deployments
## - Leader formations (stationed_province_id per division)
## - NationalModifierManager temporary effects
## - Scenario metadata (scenario_id captured on save via ScenarioLoader.get_current_scenario_name(); richer metadata added in 0.2-dev: last_played, game_version)
## - Production (stance, national stockpiles/equipment, per-line progress/retooling/shortage state)
## - Factories (full Factory resources: damage, owner, retooling, assigned lines, efficiencies)
## - Leaders (full Leader resources + XP/status/assignments/traits, national positions, officer training, pending retirements/replacements)
## - Design lifecycle (if DesignManager provides it)
## - InfrastructureDevelopmentManager (active provincial investment projects only; dev/infra levels live under "map")
## - Land war loop (open multi-day battles + FormationMovement own-land march queues + last AAR)
##
## Metadata structure (in every save root["metadata"]):
##   timestamp, scenario_id, player_tag, last_played, game_version, play_time_seconds (0 for now)
##
## === LIMITATIONS / WHAT IS NOT SAVED YET ===
## - Combat presence beyond open land battles / march queues (intel caches, air/naval in-flight)
## - Most NationalSpirit / doctrine beyond Tech
## - UI caches, camera, selection state
## - Mod or highly transient data
## - Comprehensive migration for very old saves (basic stub exists; see _migrate_save_data)
## - (Note: "design_lifecycle" section is opportunistically saved if DesignManager provides it)
##
## These can (and should) be added by implementing the two methods below on the manager.
##
## File location: user://saves/<slot>.json  (persistent, cross-session)
## Slots are simple names (quicksave, slot1, autosave_1937-03, etc.).
##
## Usage from code / debug:
##   SaveLoadManager.save_game("quicksave")
##   SaveLoadManager.load_game("quicksave")
##   var saves := SaveLoadManager.list_saves()   # Rich data for future menu
##
## Future Save Menu UI should rely on:
##   - list_saves() → rich [{slot, path, metadata: {timestamp, scenario_id, last_played, game_version, ...}}]
##   - delete_save(slot), rename_save(old, new) for management
##   - save_game_detailed / load_game_detailed for error objects + consistent toasts
##   - get_saved_scenario_id(slot) / check_scenario_compatibility(slot) for validation
##   - get_save_path, quicksave/quickload for convenience
##   - _migrate_save_data hook for version upgrades
##
## The existing TopInfoBar code-driven "Save Manager" popup already demonstrates
## these APIs (list + load + delete).
##
## Authoring note: Keep this file relatively small. Heavy per-system logic belongs
## in the managers' get/apply methods.

extends Node

## Fired after a save actually applies. Same-frame duplicate deliveries and
## failed reads do not emit. Defeat / victory overlays listen and dismiss.
signal load_completed(slot_name: String)

const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 2
const SAVE_GAME_VERSION := "0.2-dev"   # Bumped for richer metadata support
const DEFAULT_SLOT := "quicksave"

var _last_save_path: String = ""
## Real load applications. A same-frame second delivery of the same slot does not count.
var eoa_load_apply_count: int = 0
## total_days_elapsed at the last successful save. -1 means this session has not saved.
var _last_saved_elapsed: int = -1
var _tag_names: Dictionary = {}
var _tag_names_loaded: bool = false
const _MONTHS: PackedStringArray = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var _load_apply_frame: int = -1
var _load_apply_slot: String = ""
var _calendar_autosave_pending: bool = false
var _calendar_autosave_gathers: int = 0
var _calendar_autosave_live_f5_skips: int = 0
var _calendar_autosave_lean_live: bool = false
var _calendar_autosave_rss_mid_kb: int = -1
var _calendar_autosave_hwm_mid_kb: int = -1
var _calendar_autosave_serial: int = 0
var _calendar_autosave_ran_serial: int = 0
var _calendar_autosave_queued_elapsed: int = -1
var _calendar_autosave_last_ms: float = -1.0
var _calendar_autosave_last_json_bytes: int = -1
var _calendar_autosave_last_lean: bool = false
var _calendar_autosave_last_rearmed: bool = false
## Elapsed day of the last gather. A year boundary on that same day does not
## gather again. -1 means this process has not gathered yet.
var _calendar_autosave_gathered_elapsed: int = -1
## True when the queued write is a year boundary that is not a multiple of 7.
var _calendar_autosave_queued_off_interval: bool = false
## One deferred slot. If day 7 and a different year morning both want a write
## in the same drain, the second waits here and runs after the first.
var _calendar_autosave_followup_elapsed: int = -1
var _calendar_autosave_followup_off_interval: bool = false


func _ready() -> void:
	_ensure_save_dir()
	print("SaveLoadManager: Initialized (JSON format v%d, user://saves/)" % SAVE_VERSION)

	# Year boundary + every 7 calendar days (20–60d 1936 never hits a year tick).
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(_on_year_advanced_for_autosave):
			TimeManager.game_year_advanced.connect(_on_year_advanced_for_autosave)
		if TimeManager.has_signal("game_day_advanced") \
				and not TimeManager.game_day_advanced.is_connected(_on_day_advanced_for_autosave):
			TimeManager.game_day_advanced.connect(_on_day_advanced_for_autosave)


func _on_day_advanced_for_autosave(_year: int = 0, _month: int = 0, _day: int = 0) -> void:
	if OS.get_environment("EOA_CALENDAR_AUTOSAVE").strip_edges() == "0":
		return
	if typeof(TimeManager) != TYPE_NIL and bool(TimeManager.get("_living_playtest_clock")):
		# Compact 20d Maginot clock: save_game_detailed every 7d hung the -s harness.
		return
	# Live editor/export Play used to return here. The old gather dumped the
	# hierarchy and OOMed (~10 GB RSS) at day +5/+6. SAVE-FULL-1 omits that
	# dump, so a normal day roll on a positive multiple of 7 writes autosave.
	# The predicate stays true on this path: quit still skips, and the gather
	# stays lean (empty hierarchy, no map-ui blob). Days off the interval
	# still write nothing. Player Ctrl+S is unchanged.
	var lean_live_gather := _should_skip_live_f5_calendar_autosave()
	_calendar_autosave_lean_live = lean_live_gather
	var elapsed := 0
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		elapsed = int(TimeManager.get_total_days_elapsed())
	# A batched light-sim drain emits each day only after total_days_elapsed
	# is already the final value. The signal still carries that day's date.
	# An 8-day advance from elapsed 0 must still see day 7, not only day 8.
	var emitted := _elapsed_for_emitted_calendar(_year, _month, _day)
	if emitted > 0 and emitted < elapsed:
		elapsed = emitted
	if elapsed <= 0 or (elapsed % 7) != 0:
		return
	# Isolate the gather from day_emit so the F5 hour clock can keep moving
	# (day-7 save_game_detailed used to freeze the spine session at 20:00).
	if _calendar_autosave_pending:
		# A year-boundary write already holds the slot. Keep this interval day
		# so it still gathers after that write. A second interval day in the
		# same batch still does not queue.
		if _calendar_autosave_queued_off_interval and _calendar_autosave_queued_elapsed != elapsed:
			_calendar_autosave_followup_elapsed = elapsed
			_calendar_autosave_followup_off_interval = false
		return
	_queue_deferred_calendar_autosave(elapsed, false)


func _elapsed_for_emitted_calendar(year: int, month: int, day: int) -> int:
	# Days from the scenario start to this signal date. Elapsed 0 is the start
	# date itself, matching TimeManager.total_days_elapsed after N rollovers.
	if typeof(TimeManager) == TYPE_NIL or year < 1 or month < 1 or day < 1:
		return -1
	var start := str(TimeManager.get("scenario_start_date"))
	if start.is_empty():
		start = "1936-01-01"
	var parts := start.split("-")
	var y := 1936
	var m := 1
	var d := 1
	if parts.size() >= 1 and parts[0].is_valid_int():
		y = int(parts[0])
	if parts.size() >= 2 and parts[1].is_valid_int():
		m = clampi(int(parts[1]), 1, 12)
	if parts.size() >= 3 and parts[2].is_valid_int():
		d = clampi(int(parts[2]), 1, 31)
	var n := 0
	while n < 20000:
		if y == year and m == month and d == day:
			return n
		if y > year or (y == year and (m > month or (m == month and d > day))):
			return -1
		d += 1
		var dim := 31
		if TimeManager.has_method("_get_days_in_month"):
			dim = int(TimeManager.call("_get_days_in_month", m, y))
		if d > dim:
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
		n += 1
	return -1


## Headless soaks sample gathers before the idle frame. Run the queued day-7
## write now. The deferred call that is already queued sees the same serial
## and does not gather a second time.
func settle_deferred_calendar_autosave() -> void:
	if not _calendar_autosave_pending:
		return
	_deferred_calendar_autosave(_calendar_autosave_queued_elapsed)


## File on disk after the day-7 gather. hier_keys 0 is the empty lean blob.
## -1 means the key is absent. A positive count is the hierarchy dump.
func calendar_autosave_file_report() -> Dictionary:
	var path := get_save_path_global("autosave")
	var nbytes := 0
	var hier := -1
	var parsed_ok := false
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			nbytes = int(f.get_length())
			var text := f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary:
				parsed_ok = true
				var gd: Variant = (parsed as Dictionary).get("game_data", null)
				if gd is Dictionary and (gd as Dictionary).has("hierarchy_membership_live"):
					var h: Variant = (gd as Dictionary).get("hierarchy_membership_live")
					hier = (h as Dictionary).size() if h is Dictionary else 999999
	return {
		"path": path,
		"bytes": nbytes,
		"parsed": parsed_ok,
		"hier_keys": hier,
		"ms": _calendar_autosave_last_ms,
		"json_bytes": _calendar_autosave_last_json_bytes,
		"lean_gather": _calendar_autosave_last_lean,
		"rearmed": _calendar_autosave_last_rearmed,
		"gathers": _calendar_autosave_gathers,
	}


func _should_skip_live_f5_calendar_autosave() -> bool:
	if typeof(TimeManager) == TYPE_NIL:
		return false
	if TimeManager.has_method("is_live_f5_play_path") and bool(TimeManager.is_live_f5_play_path()):
		return true
	return false


func _deferred_calendar_autosave(elapsed: int) -> void:
	var serial := _calendar_autosave_serial
	if serial > 0 and serial == _calendar_autosave_ran_serial:
		_calendar_autosave_pending = false
		return
	_calendar_autosave_pending = false
	if serial > 0:
		_calendar_autosave_ran_serial = serial
	if OS.get_environment("EOA_CALENDAR_AUTOSAVE").strip_edges() == "0":
		_calendar_autosave_followup_elapsed = -1
		_calendar_autosave_queued_off_interval = false
		return
	if typeof(TimeManager) != TYPE_NIL and bool(TimeManager.get("_living_playtest_clock")):
		_calendar_autosave_followup_elapsed = -1
		_calendar_autosave_queued_off_interval = false
		return
	var off_interval := _calendar_autosave_queued_off_interval
	_calendar_autosave_queued_off_interval = false
	# Day 7 requires a positive multiple of 7. A year morning that is not on
	# that interval still writes when it was queued with the off-interval flag.
	if elapsed <= 0 or ((elapsed % 7) != 0 and not off_interval):
		_chain_calendar_autosave_followup()
		return
	# Live F5 no longer skips this write. advance_live_f5_equivalent_days
	# clears `_live_f5_equiv_clock` before this deferred frame. Put it back
	# for the gather so GameData still omits the hierarchy dump, then restore.
	# Quit stays on _skip_quit_autosave. A headless run that never took the
	# live path leaves the flag alone and keeps today's gather.
	var rearmed := false
	if _calendar_autosave_lean_live and typeof(TimeManager) != TYPE_NIL:
		if not bool(TimeManager.get("_live_f5_equiv_clock")):
			TimeManager.set("_live_f5_equiv_clock", true)
			rearmed = true
	var lean_now := _should_skip_live_f5_calendar_autosave()
	_calendar_autosave_last_lean = lean_now
	_calendar_autosave_last_rearmed = rearmed
	_calendar_autosave_gathered_elapsed = elapsed
	_calendar_autosave_gathers += 1
	var rss_before := _vm_status_kb("VmRSS")
	var hwm_before := _vm_status_kb("VmHWM")
	var t0 := Time.get_ticks_usec()
	var res := save_game_detailed("autosave")
	var save_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_calendar_autosave_last_ms = save_ms
	_calendar_autosave_last_json_bytes = int(res.get("bytes", -1))
	if rearmed and typeof(TimeManager) != TYPE_NIL:
		TimeManager.set("_live_f5_equiv_clock", false)
	var rss_after := _vm_status_kb("VmRSS")
	var hwm_after := _vm_status_kb("VmHWM")
	if res.get("ok", false):
		var toast_line := "Autosaved · day %d" % elapsed
		print("SaveLoadManager: Calendar autosave day=%d -> autosave.json" % elapsed)
		print("SaveLoadManager: %s" % toast_line)
		print(
			"SAVEFULL1FIX4_METRIC ms=%.1f bytes=%d rss_before=%d rss_mid=%d rss_after=%d hwm_before=%d hwm_mid=%d hwm_after=%d lean_day=%s lean_gather=%s rearmed=%s"
			% [
				save_ms,
				int(res.get("bytes", 0)),
				rss_before,
				_calendar_autosave_rss_mid_kb,
				rss_after,
				hwm_before,
				_calendar_autosave_hwm_mid_kb,
				hwm_after,
				str(_calendar_autosave_lean_live),
				str(lean_now),
				str(rearmed),
			]
		)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(toast_line, 2.0)
	else:
		push_warning("SaveLoadManager: Calendar autosave failed: %s" % res.get("error", "unknown"))
	_chain_calendar_autosave_followup()


func _vm_status_kb(key: String) -> int:
	# FileAccess on /proc/self is sandboxed in this export. cat the Godot pid.
	var pid := OS.get_process_id()
	var out: Array = []
	var code := OS.execute("/usr/bin/cat", PackedStringArray(["/proc/%d/status" % pid]), out, true, false)
	if code != 0 or out.is_empty():
		return -1
	var text := ""
	for item in out:
		text += str(item)
		if not str(item).ends_with("\n"):
			text += "\n"
	var prefix := key + ":"
	for line in text.split("\n"):
		if not line.begins_with(prefix):
			continue
		var parts := line.replace("\t", " ").split(" ", false)
		for p in parts:
			if p.is_valid_int():
				return int(p)
	return -1


func _queue_deferred_calendar_autosave(elapsed: int, off_interval: bool) -> void:
	# Do not latch this on the day-7 path. A later soak can rewind the
	# calendar to elapsed 0 and must still gather its own day 7. The year
	# hook is what skips an elapsed day that already gathered.
	if elapsed <= 0:
		return
	if _calendar_autosave_pending:
		return
	_calendar_autosave_serial += 1
	_calendar_autosave_queued_elapsed = elapsed
	_calendar_autosave_queued_off_interval = off_interval
	_calendar_autosave_pending = true
	call_deferred("_deferred_calendar_autosave", elapsed)


func _chain_calendar_autosave_followup() -> void:
	if _calendar_autosave_followup_elapsed <= 0:
		return
	var elapsed := _calendar_autosave_followup_elapsed
	var off := _calendar_autosave_followup_off_interval
	_calendar_autosave_followup_elapsed = -1
	_calendar_autosave_followup_off_interval = false
	if elapsed == _calendar_autosave_gathered_elapsed:
		return
	_queue_deferred_calendar_autosave(elapsed, off)


func _on_year_advanced_for_autosave(year: int) -> void:
	# Autosave to a fixed slot; keeps only the latest autosave for simplicity.
	# Headless (not the live path) still writes immediately.
	# Live F5 used to return here, so a session that crossed into 1937 never
	# wrote. 1936 is not a leap year: 1937-01-01 is elapsed 365, and 365 % 7
	# is 1, so the day-7 hook does not write that morning. Queue the same
	# deferred lean gather as day 7. If that elapsed day already gathered, or
	# is already queued, do not gather again. Quit stays on _skip_quit_autosave.
	if OS.get_environment("EOA_CALENDAR_AUTOSAVE").strip_edges() == "0":
		return
	if typeof(TimeManager) != TYPE_NIL and bool(TimeManager.get("_living_playtest_clock")):
		return
	if not _should_skip_live_f5_calendar_autosave():
		var res := save_game_detailed("autosave")
		if res.get("ok", false):
			print("SaveLoadManager: Autosaved on year change -> autosave.json")
		else:
			push_warning("SaveLoadManager: Autosave failed: %s" % res.get("error", "unknown"))
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Autosave failed", 2.0, true)
		return
	var elapsed := _elapsed_for_emitted_calendar(year, 1, 1)
	if elapsed <= 0 and typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		elapsed = int(TimeManager.get_total_days_elapsed())
	if elapsed <= 0:
		return
	# A rewound clock is a new timeline. Elapsed 7 gathered before the rewind
	# must not suppress a later year morning, and must not suppress day 7.
	if _calendar_autosave_gathered_elapsed >= 0 and elapsed < _calendar_autosave_gathered_elapsed:
		_calendar_autosave_gathered_elapsed = -1
	if elapsed == _calendar_autosave_gathered_elapsed:
		return
	if _calendar_autosave_pending and _calendar_autosave_queued_elapsed == elapsed:
		return
	_calendar_autosave_lean_live = true
	if _calendar_autosave_pending:
		_calendar_autosave_followup_elapsed = elapsed
		_calendar_autosave_followup_off_interval = true
		return
	_queue_deferred_calendar_autosave(elapsed, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		# Light autosave on quit / exit to main menu (non-intrusive, best-effort).
		# Guard against double-fire during shutdown.
		if not has_meta("autosave_on_quit_done"):
			set_meta("autosave_on_quit_done", true)
			if _skip_quit_autosave():
				return
			var res := save_game_detailed("autosave")
			if res.get("ok", false):
				print("SaveLoadManager: Autosaved on exit/quit -> autosave.json")
			else:
				push_warning("SaveLoadManager: Quit autosave failed: %s" % res.get("error", "unknown"))
				# No toast on shutdown to avoid UI issues
		# Do not block exit


func _skip_quit_autosave() -> bool:
	# Maginot -s / year multi-AI: save_game_detailed on EXIT_TREE hung after RESULT=PASS.
	# Live F5 / softpipe: same gather OOMs after a +6d soak — skip automatic quit write.
	# Explicit Ctrl+S still uses save_game_detailed.
	if OS.get_environment("EOA_CALENDAR_AUTOSAVE").strip_edges() == "0":
		return true
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return true
	if _should_skip_live_f5_calendar_autosave():
		return true
	return false


## PLAYTEST §0b 13 on the living Maginot 20d clock: gather time+land_war+map via
## the shipped save blob, mutate elapsed/AAR, apply. Never execute_province_assault.
func living_playtest_saveload_roundtrip() -> Dictionary:
	var blob: Dictionary = _gather_save_data()
	if blob.is_empty() or not blob.has("land_war") or not blob.has("time"):
		return {"ok": false, "reason": "gather incomplete", "never_execute": true}
	var t: Dictionary = blob["time"] as Dictionary
	var saved_elapsed := int(t.get("total_days_elapsed", 0))
	var lw: Dictionary = blob["land_war"] as Dictionary
	var saved_aar: Dictionary = {}
	if lw.get("last_aar") is Dictionary:
		saved_aar = (lw["last_aar"] as Dictionary).duplicate()
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.total_days_elapsed = 0
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("clear_last_land_aar"):
		BattleManager.clear_last_land_aar()
	_apply_save_data(blob)
	var restored := 0
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		restored = int(TimeManager.get_total_days_elapsed())
	var aar_now: Dictionary = {}
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("peek_last_land_aar"):
		aar_now = BattleManager.peek_last_land_aar()
	var aar_ok := saved_aar.is_empty() or not aar_now.is_empty()
	return {
		"ok": restored == saved_elapsed and saved_elapsed > 0 and aar_ok,
		"elapsed_saved": saved_elapsed,
		"elapsed_restored": restored,
		"aar_saved": not saved_aar.is_empty(),
		"aar_restored": not aar_now.is_empty(),
		"land_war": true,
		"never_execute": true,
	}

## OS absolute path for user://saves/ (DirAccess absolute APIs are flaky with user:// alone).
func get_saves_dir_global() -> String:
	return ProjectSettings.globalize_path(SAVE_DIR)


func _ensure_save_dir() -> void:
	var global_dir := get_saves_dir_global()
	# Prefer user:// relative open; fall back to globalized absolute.
	var exists := DirAccess.dir_exists_absolute(SAVE_DIR) or DirAccess.dir_exists_absolute(global_dir)
	if not exists:
		var err := DirAccess.make_dir_recursive_absolute(global_dir)
		if err != OK:
			# Second try with user:// form
			err = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			push_error("SaveLoadManager: Failed to create saves dir: %s (global=%s err=%d)" % [SAVE_DIR, global_dir, err])
		else:
			print("SaveLoadManager: Created saves dir → %s" % global_dir)
	# Verify we can open it
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		push_error("SaveLoadManager: Cannot open saves dir after ensure: %s" % SAVE_DIR)


func get_save_path(slot_name: String) -> String:
	var safe := _sanitize_slot(slot_name)
	return SAVE_DIR + safe + ".json"


func get_save_path_global(slot_name: String) -> String:
	return ProjectSettings.globalize_path(get_save_path(slot_name))


func _sanitize_slot(slot_name: String) -> String:
	var safe := slot_name.strip_edges().to_lower()
	safe = safe.replace(" ", "_").replace("/", "_").replace("\\", "_").replace(":", "_")
	var cleaned := ""
	for i in safe.length():
		var ch := safe[i]
		var code := ch.unicode_at(0)
		var is_alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if is_alnum or ch == "_" or ch == "-":
			cleaned += ch
	if cleaned.is_empty():
		cleaned = DEFAULT_SLOT
	return cleaned

## Returns rich data for a future save menu UI:
##   [{ "slot": "quicksave", "path": "...", "metadata": {
##        "timestamp": "...", "scenario_id": "1936", "player_tag": "USA",
##        "last_played": "...", "game_version": "0.2-dev", "play_time_seconds": 0, ...
##   }}]
## Sorted newest first by timestamp/last_played.
## Future menu should use this + delete_save/rename_save + detailed save/load for errors/toasts.
func list_saves() -> Array[Dictionary]:
	_ensure_save_dir()
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		# Fallback: absolute path
		dir = DirAccess.open(get_saves_dir_global())
	if dir == null:
		push_warning("SaveLoadManager: list_saves — cannot open %s" % SAVE_DIR)
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full := SAVE_DIR + file_name
			var slot := file_name.get_basename()
			var inspected := _inspect_save_file(full)
			result.append({
				"slot": slot,
				"path": full,
				"metadata": inspected.get("metadata", {}),
				"unreadable": not bool(inspected.get("readable", false)),
			})
		file_name = dir.get_next()
	dir.list_dir_end()
	# Sort by timestamp desc if present
	result.sort_custom(func(a, b):
		var ta := str(a.get("metadata", {}).get("timestamp", ""))
		var tb := str(b.get("metadata", {}).get("timestamp", ""))
		return ta > tb
	)
	return result


## Fixed browser slots always shown in Save Manager (empty vs occupied).
const BROWSER_SLOTS: PackedStringArray = [
	"quicksave", "autosave", "slot1", "slot2", "slot3", "slot4", "slot5"
]


## Slot kind from the name. Old saves omit metadata.save_kind and use this.
func slot_kind(slot_name: String) -> String:
	var s := str(slot_name).strip_edges().to_lower()
	if s == "quicksave" or s.begins_with("quick"):
		return "quick"
	if s == "autosave" or s.begins_with("autosave"):
		return "auto"
	return "manual"


func kind_badge(kind: String) -> String:
	match kind:
		"quick":
			return "QUICK"
		"auto":
			return "AUTO"
		_:
			return "MANUAL"


func slot_is_occupied(slot_name: String) -> bool:
	return FileAccess.file_exists(get_save_path(slot_name))


## Days of game time since the last save in this session. Never saved counts
## from day 0, so day 1 already warns. Not a wall-clock threshold.
func unsaved_in_game_days() -> int:
	if typeof(TimeManager) == TYPE_NIL:
		return 0
	var elapsed := int(TimeManager.total_days_elapsed)
	if TimeManager.has_method("get_total_days_elapsed"):
		elapsed = int(TimeManager.get_total_days_elapsed())
	if _last_saved_elapsed < 0:
		return maxi(0, elapsed)
	return maxi(0, elapsed - _last_saved_elapsed)


## Autosave loads do not warn. Any other slot warns after one unsaved day.
func load_confirm_required(slot_name: String) -> bool:
	if slot_kind(slot_name) == "auto":
		return false
	return unsaved_in_game_days() >= 1


func nation_display_name(tag: String) -> String:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return ""
	_ensure_tag_names()
	if _tag_names.has(t):
		return str(_tag_names[t])
	return t


func nation_card_line(tag: String) -> String:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return "—"
	var name := nation_display_name(t)
	if name.is_empty() or name == t:
		return t
	return "%s (%s)" % [name, t]


func format_game_date_display(iso: String) -> String:
	var s := str(iso).strip_edges()
	if s.length() < 10:
		return "—"
	var month := int(s.substr(5, 2))
	var day := int(s.substr(8, 2))
	if month < 1 or month > 12 or day < 1:
		return "—"
	return "%d %s %s" % [day, _MONTHS[month - 1], s.substr(0, 4)]


## Wall-clock save time in the player's local timezone. Never the UTC ISO with T.
func format_save_time_display(ts: String, unix: float = -1.0) -> String:
	if unix >= 1.0:
		return _format_unix_local(int(unix))
	var s := str(ts).strip_edges()
	if s.is_empty():
		return "—"
	var iso := s.replace(" ", "T")
	if iso.length() >= 16 and iso[10] == "T":
		var parsed := Time.get_unix_time_from_datetime_string(iso)
		if parsed > 0:
			# Datetime strings without Z were stored as local wall time.
			return _format_datetime_parts(iso)
	return s if s.length() <= 19 else s.substr(0, 19)


func _format_unix_local(unix: int) -> String:
	var tz: Dictionary = Time.get_time_zone_from_system()
	var bias := int(tz.get("bias", 0))
	var local_unix := unix + bias * 60
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(local_unix)
	return _format_datetime_dict(d)


func _format_datetime_parts(iso: String) -> String:
	if iso.length() < 16:
		return "—"
	var d := {
		"year": int(iso.substr(0, 4)),
		"month": int(iso.substr(5, 2)),
		"day": int(iso.substr(8, 2)),
		"hour": int(iso.substr(11, 2)),
		"minute": int(iso.substr(14, 2)),
	}
	return _format_datetime_dict(d)


func _format_datetime_dict(d: Dictionary) -> String:
	var month := int(d.get("month", 0))
	if month < 1 or month > 12:
		return "—"
	return "%d %s %04d %02d:%02d" % [
		int(d.get("day", 1)),
		_MONTHS[month - 1],
		int(d.get("year", 0)),
		int(d.get("hour", 0)),
		int(d.get("minute", 0)),
	]


func slot_replace_blurb(slot_name: String) -> String:
	var meta := _peek_metadata(get_save_path(slot_name))
	var tag := str(meta.get("player_tag", "")).strip_edges().to_upper()
	var nation := nation_display_name(tag) if not tag.is_empty() else "this nation"
	var date := format_game_date_display(str(meta.get("game_date", "")))
	if date == "—":
		date = "unknown date"
	return "'%s' (%s · %s) will be replaced. This can't be undone." % [slot_name, nation, date]


func _ensure_tag_names() -> void:
	if _tag_names_loaded:
		return
	_tag_names_loaded = true
	var path := "res://data/scenarios/campaign_rules_1936.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var names: Variant = (parsed as Dictionary).get("tag_names", {})
	if names is Dictionary:
		_tag_names = (names as Dictionary).duplicate(true)


func _current_game_date_iso() -> String:
	if typeof(TimeManager) == TYPE_NIL:
		return ""
	var y := int(TimeManager.current_year)
	if y <= 0:
		return ""
	return "%04d-%02d-%02d" % [y, int(TimeManager.current_month), int(TimeManager.current_day)]


func _stamp_slot_metadata(data: Dictionary, slot_name: String) -> void:
	if typeof(data.get("metadata", null)) != TYPE_DICTIONARY:
		data["metadata"] = {}
	var meta: Dictionary = data["metadata"]
	meta["save_kind"] = slot_kind(slot_name)
	var game_date := _current_game_date_iso()
	if not game_date.is_empty():
		meta["game_date"] = game_date
	meta["timestamp"] = Time.get_datetime_string_from_system(false)
	meta["timestamp_unix"] = Time.get_unix_time_from_system()
	meta["last_played"] = str(meta.get("timestamp", ""))
	# play_time_seconds stays 0. The card does not show it.
	data["metadata"] = meta


func _note_save_elapsed() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	if TimeManager.has_method("get_total_days_elapsed"):
		_last_saved_elapsed = int(TimeManager.get_total_days_elapsed())
	else:
		_last_saved_elapsed = int(TimeManager.total_days_elapsed)


func _adopt_loaded_elapsed() -> void:
	_note_save_elapsed()
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("note_overlay_clock_from_current"):
		if TimeManager.has_method("overlay_holds_clock") and bool(TimeManager.overlay_holds_clock()):
			TimeManager.note_overlay_clock_from_current()


## Successful apply only. Duplicate same-frame deliveries and failed reads return earlier.
func _emit_load_completed(slot_name: String) -> void:
	load_completed.emit(str(slot_name))


func _notify_top_bar_speed_resync() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for n in tree.get_nodes_in_group("top_info_bar"):
		if n != null and is_instance_valid(n) and n.has_method("resync_speed_from_time_manager"):
			n.call("resync_speed_from_time_manager")


func _notify_save_list_refresh() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var menu := tree.root.get_node_or_null("MainMenu")
	if menu != null and is_instance_valid(menu) and menu.has_method("_refresh_save_list"):
		menu.call_deferred("_refresh_save_list")


## Player-facing slot list: fixed empty slots + occupied files from list_saves().
## Each row: slot, occupied, status, label, can_load, can_save, api_save, api_load, metadata.
## Load/save actions must use save_game_detailed / load_game_detailed (not reimplemented).
func list_slots_for_ui() -> Array[Dictionary]:
	var occupied: Dictionary = {}  # slot -> entry from list_saves
	for e in list_saves():
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var s := str(e.get("slot", "")).strip_edges()
		if s.is_empty():
			continue
		occupied[s] = e
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	for slot in BROWSER_SLOTS:
		var name := str(slot).strip_edges()
		if name.is_empty() or seen.has(name):
			continue
		seen[name] = true
		if occupied.has(name):
			rows.append(_format_slot_ui_row(
				name,
				true,
				occupied[name].get("metadata", {}),
				bool(occupied[name].get("unreadable", false))
			))
		else:
			rows.append(_format_slot_ui_row(name, false, {}))
	# Extra discovered slots
	var extras: Array = []
	for s in occupied.keys():
		if seen.has(str(s)):
			continue
		extras.append(occupied[s])
	extras.sort_custom(func(a, b):
		var ta := str(a.get("metadata", {}).get("timestamp", a.get("metadata", {}).get("last_played", "")))
		var tb := str(b.get("metadata", {}).get("timestamp", b.get("metadata", {}).get("last_played", "")))
		return ta > tb
	)
	for e in extras:
		var sn := str(e.get("slot", ""))
		rows.append(_format_slot_ui_row(
			sn,
			true,
			e.get("metadata", {}),
			bool(e.get("unreadable", false))
		))
	return rows


func _format_slot_ui_row(slot: String, occupied: bool, metadata: Variant, unreadable: bool = false) -> Dictionary:
	var meta: Dictionary = metadata if typeof(metadata) == TYPE_DICTIONARY else {}
	var name := slot.strip_edges()
	if name.is_empty():
		name = "unnamed"
	var label := ""
	var status := "empty"
	var kind := str(meta.get("save_kind", "")).strip_edges().to_lower()
	if kind.is_empty():
		kind = slot_kind(name)
	var player := str(meta.get("player_tag", "")).strip_edges().to_upper()
	var nation_line := nation_card_line(player) if occupied else "—"
	var game_date_label := "—"
	if occupied and not unreadable:
		game_date_label = format_game_date_display(str(meta.get("game_date", "")))
	var ts := str(meta.get("timestamp", meta.get("last_played", "")))
	var unix := float(meta.get("timestamp_unix", -1))
	var saved_short := format_save_time_display(ts, unix) if occupied and not unreadable else "—"
	var when_line := ""
	if unreadable:
		status = "unreadable"
		nation_line = "Save unreadable"
		game_date_label = "Save unreadable"
		saved_short = "Save unreadable"
		label = "%s · unreadable" % name
		when_line = "Save unreadable"
	elif occupied:
		status = "occupied"
		var bits: PackedStringArray = [name]
		var scenario := str(meta.get("scenario_id", "")).strip_edges()
		if not scenario.is_empty():
			bits.append(scenario)
		if not player.is_empty():
			bits.append(player)
		if not saved_short.is_empty() and saved_short != "—":
			bits.append(saved_short)
		label = " · ".join(bits)
		when_line = "%s · Saved %s" % [game_date_label, saved_short]
	else:
		label = "%s · empty" % name
		when_line = "Empty slot"
	# Playtime is intentionally absent. Old files may still store play_time_seconds.
	return {
		"slot": name,
		"occupied": occupied,
		"status": status,
		"label": label,
		"metadata": meta.duplicate(true) if not meta.is_empty() else {},
		"can_load": occupied,
		"can_save": kind != "auto",
		"api_save": "save_game_detailed",
		"api_load": "load_game_detailed",
		"kind": kind,
		"kind_badge": kind_badge(kind),
		"nation_line": nation_line,
		"game_date_label": game_date_label,
		"when_line": when_line,
		"playtime_hidden": true,
		"unreadable": unreadable,
	}

func _peek_metadata(path: String) -> Dictionary:
	return _inspect_save_file(path).get("metadata", {}) as Dictionary


func _inspect_save_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"readable": false, "metadata": {}, "error": "missing"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"readable": false, "metadata": {}, "error": "cannot open"}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"readable": false, "metadata": {}, "error": "unreadable"}
	var d: Dictionary = parsed
	if not _blob_looks_like_save(d):
		return {"readable": false, "metadata": {}, "error": "unreadable"}
	var meta: Dictionary = {}
	if d.get("metadata") is Dictionary:
		meta = (d.get("metadata", {}) as Dictionary).duplicate(true)
	if str(meta.get("game_date", "")).strip_edges().is_empty() and d.get("time") is Dictionary:
		var time_blob: Dictionary = d.get("time", {})
		var date_v: Variant = time_blob.get("current_date", {})
		if date_v is Dictionary:
			var cd: Dictionary = date_v
			var y := int(cd.get("year", 0))
			var mo := int(cd.get("month", 0))
			var da := int(cd.get("day", 0))
			if y > 0 and mo > 0 and da > 0:
				meta["game_date"] = "%04d-%02d-%02d" % [y, mo, da]
	return {"readable": true, "metadata": meta, "error": ""}


func _blob_looks_like_save(data: Dictionary) -> bool:
	if not data.has("save_version"):
		return false
	if not (data.get("metadata") is Dictionary):
		return false
	return true


func _unreadable_load_error() -> String:
	return "This save is unreadable."

func save_game(slot_name: String = DEFAULT_SLOT) -> bool:
	var path := get_save_path(slot_name)
	var data := _gather_save_data()
	_stamp_slot_metadata(data, slot_name)
	var json_text := JSON.stringify(data, "\t")   # Pretty for human debugging

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var err_msg = "Save failed: cannot write " + path
		push_error("SaveLoadManager: " + err_msg)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(err_msg, 3.0, true)  # error style if supported
		return false
	f.store_string(json_text)
	f.close()

	_last_save_path = path
	_note_save_elapsed()
	print("SaveLoadManager: Game saved → %s (v%d, %d bytes)" % [path, SAVE_VERSION, json_text.length()])
	_notify_save_list_refresh()

	# Consistent non-intrusive feedback
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Game saved (" + slot_name + ")", 2.0)

	return true

func load_game(slot_name: String = DEFAULT_SLOT) -> bool:
	var path := get_save_path(slot_name)
	if not FileAccess.file_exists(path):
		var err_msg = "Load failed: file not found " + path
		push_error("SaveLoadManager: " + err_msg)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(err_msg, 3.0, true)
		return false

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SaveLoadManager: Cannot open %s for reading" % path)
		return false
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveLoadManager: This save is unreadable.")
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(_unreadable_load_error(), 3.0, true)
		return false

	var data: Dictionary = parsed
	if not _blob_looks_like_save(data):
		push_error("SaveLoadManager: This save is unreadable.")
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(_unreadable_load_error(), 3.0, true)
		return false
	var file_version := int(data.get("save_version", 0))
	if file_version > SAVE_VERSION:
		push_warning("SaveLoadManager: Save is v%d (current v%d). Best-effort load may drop fields." % [file_version, SAVE_VERSION])

	_apply_save_data(data)
	_adopt_loaded_elapsed()
	_notify_top_bar_speed_resync()
	print("SaveLoadManager: Game loaded ← %s (v%d)" % [path, file_version])

	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Game loaded (" + slot_name + ")", 2.5)
	_emit_load_completed(slot_name)
	return true

## === INTERNAL GATHER / APPLY ===

func _find_scenario_loader() -> ScenarioLoader:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var loader_node: Node = tree.root.find_child("ScenarioLoader", true, false)
	return loader_node as ScenarioLoader


func _gather_save_data() -> Dictionary:
	var data := {
		"save_version": SAVE_VERSION,
		"metadata": {
			"timestamp": Time.get_datetime_string_from_system(false),
			"timestamp_unix": Time.get_unix_time_from_system(),
			# Live scenario name and player tag. Empty stays empty — never a USA/1936 placeholder.
			"scenario_id": "",
			"player_tag": "",
			"play_time_seconds": 0,
			"game_version": SAVE_GAME_VERSION,
			"game_date": "",
			"save_kind": "",
		},
		"time": {},
		"technology": {},
		"agents": {},
		"map": {},
		"supply": {},
		"national_modifiers": {},
		"leaders": {},
		"infrastructure_projects": {},
		"land_war": {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}},
		"production": {},
		"misc": {},
	}

	# --- TimeManager ---
	if typeof(TimeManager) != TYPE_NIL:
		var date := TimeManager.get_current_date()
		date.erase("hour")
		date.erase("date_string")
		data["time"] = {
			"current_date": date,
			"scenario_start_date": TimeManager.get_scenario_start_date(),
			"paused": TimeManager.is_paused(),
			"time_scale": TimeManager.time_scale,
			"total_days_elapsed": TimeManager.get_total_days_elapsed(),
			"current_hour": TimeManager.current_hour,
			"run_seed": int(TimeManager.run_seed) if "run_seed" in TimeManager else 0,
			"accumulated_days": float(TimeManager._accumulated_game_days),
			"accumulated_hours": float(TimeManager._accumulated_game_hours),
		}

	# --- TechnologyManager ---
	if typeof(TechnologyManager) != TYPE_NIL:
		if TechnologyManager.has_method("get_save_data"):
			data["technology"] = TechnologyManager.get_save_data()
		else:
			data["technology"] = {
				"country_state": TechnologyManager.country_state.duplicate(true)
			}

	# --- AgentManager ---
	if typeof(AgentManager) != TYPE_NIL:
		data["agents"] = _serialize_agent_state()

	# --- MapManager ---
	if typeof(MapManager) != TYPE_NIL:
		data["map"] = _serialize_map_state()

	# --- WeatherManager (snow coverage from layers + sim, ground_state, events, power blackouts; snow_potential on provinces is in map state) ---
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_save_state"):
			data["weather"] = WeatherManager.get_save_state()
		else:
			data["weather"] = {}

	# --- SupplyManager ---
	if typeof(SupplyManager) != TYPE_NIL:
		data["supply"] = _serialize_supply_state()

	# --- NationalModifierManager ---
	if typeof(NationalModifierManager) != TYPE_NIL:
		data["national_modifiers"] = {
			"country_modifiers": NationalModifierManager.country_modifiers.duplicate(true),
			"effect_seq": int(NationalModifierManager._effect_seq),
		}

	if typeof(NationalSpiritManager) != TYPE_NIL and NationalSpiritManager.has_method("get_save_data"):
		data["national_spirits"] = NationalSpiritManager.get_save_data()

	# --- Scenario metadata ---
	var scenario_name := ""
	var loader := _find_scenario_loader()
	if loader != null:
		scenario_name = loader.get_current_scenario_name()
	data["metadata"]["scenario_id"] = scenario_name
	# The field itself, not get_player_country_tag()'s USA default when the field is empty.
	var player_tag := ""
	if typeof(LeaderManager) != TYPE_NIL:
		player_tag = str(LeaderManager.player_country_tag).strip_edges().to_upper()
	data["metadata"]["player_tag"] = player_tag
	data["metadata"]["game_date"] = _current_game_date_iso()

	# Richer metadata for future save menu (timestamp already set above, scenario captured)
	data["metadata"]["last_played"] = Time.get_datetime_string_from_system(false)
	data["metadata"]["timestamp"] = str(data["metadata"].get("timestamp", Time.get_datetime_string_from_system(false)))
	data["metadata"]["timestamp_unix"] = Time.get_unix_time_from_system()
	data["metadata"]["game_version"] = SAVE_GAME_VERSION
	# play_time_seconds left as 0 for now (future: accumulate in _ready or day ticks)

	# --- Production + Factories ---
	if typeof(ProductionManager) != TYPE_NIL:
		if ProductionManager.has_method("get_save_data"):
			data["production"] = ProductionManager.get_save_data()
		else:
			data["production"] = {}

	if typeof(FactoryManager) != TYPE_NIL:
		if FactoryManager.has_method("get_save_data"):
			data["factories"] = FactoryManager.get_save_data()
		else:
			data["factories"] = {}

	if typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("get_save_data"):
		data["design_lifecycle"] = DesignManager.get_save_data()

	if typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_save_data"):
		data["trade"] = TradeManager.get_save_data()

	if typeof(SpaceLayerManager) != TYPE_NIL and SpaceLayerManager.has_method("get_save_data"):
		data["space_layer"] = SpaceLayerManager.get_save_data()

	# --- GameData (demographic/policy state for Ascendancy Initiatives, Policy/Law screen, Trust Erosion, manpower, relocation/settlement) ---
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_save_data"):
		data["game_data"] = GameData.get_save_data()
		# Live F5 / softpipe: hierarchy dump is 3×3520 string-key maps and is
		# era-reseedable. Drop it so Ctrl+S cannot spike RSS after a soak.
		if _should_skip_live_f5_calendar_autosave() and data["game_data"] is Dictionary:
			var gd_blob: Dictionary = data["game_data"]
			gd_blob["hierarchy_membership_live"] = {}
			data["game_data"] = gd_blob

	# --- Leaders ---
	if typeof(LeaderManager) != TYPE_NIL:
		if LeaderManager.has_method("get_save_data"):
			data["leaders"] = LeaderManager.get_save_data()
		else:
			data["leaders"] = {}

	# --- Infrastructure Development (active projects only; levels are in "map") ---
	if typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		if InfrastructureDevelopmentManager.has_method("get_save_data"):
			data["infrastructure_projects"] = InfrastructureDevelopmentManager.get_save_data()
		else:
			data["infrastructure_projects"] = {}

	# --- Open land battles + own-land march queues (L1 war loop continuity) ---
	var land_war := {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}}
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("get_save_data"):
		var bm_blob: Dictionary = BattleManager.get_save_data()
		land_war["open_battles"] = bm_blob.get("open_battles", [])
		land_war["next_seq"] = int(bm_blob.get("next_seq", 1))
		land_war["last_aar"] = bm_blob.get("last_aar", {})
	if typeof(FormationMovement) != TYPE_NIL:
		var fm_blob: Dictionary = FormationMovement.get_save_data()
		land_war["marches"] = fm_blob.get("marches", {})
	data["land_war"] = land_war

	# --- Province Editor (in-game map design tool - debug only, persists drawn provinces across saves) ---
	# Uses the get_save_data/apply interface like other managers.
	var pe := get_tree().get_first_node_in_group("province_editor")
	if pe and pe.has_method("get_save_data"):
		data["province_editor"] = pe.get_save_data()

	# --- Pass 22: MapRenderer UI (compare slots, tint intensities, last mapmode) ---
	# Live F5: skip route-history / minimap blob (grows every day_emit).
	if not _should_skip_live_f5_calendar_autosave():
		var mr_save := get_tree().get_first_node_in_group("map_renderer") if get_tree() != null else null
		if mr_save and mr_save.has_method("get_save_data"):
			data["map_ui"] = mr_save.get_save_data()

	# --- Pass 24: RelationsManager (formal alliances / guarantees / CRS pairs) ---
	if typeof(RelationsManager) != TYPE_NIL and RelationsManager.has_method("get_save_data"):
		data["relations"] = RelationsManager.get_save_data()

	return data


func _apply_save_data(data: Dictionary) -> void:
	# Deliberate order matters because of cross-references and signal side-effects.

	# 1. Time (affects many yearly/monthly trackers)
	if data.has("time") and typeof(TimeManager) != TYPE_NIL:
		_apply_time_state(data["time"])

	# 2. Map provinces (owner/controller/dev/infra + now settlement/built_road/rail for Phase 3 persistence) — triggers province_data_changed + MapRenderer tints/inspector/layers
	if data.has("map") and typeof(MapManager) != TYPE_NIL:
		var map_check: Dictionary = validate_map_save_payload(data["map"] as Dictionary, data)
		if not bool(map_check.get("ok", false)):
			push_warning("SaveLoad: map payload missing keys %s (continuing best-effort)" % str(map_check.get("missing", [])))
		_apply_map_state(data["map"])
		# Re-init hook for MapManager/MapRenderer on load (per WORLD_CLASS_MAP_ROADMAP Phase 3): force full refresh so runtime province state (settlement_level, built_* from actions) + owner changes survive roundtrip and drive live visuals on 460-prov map. Uses existing force + emit listeners.
		var mr_refresh := get_tree().get_first_node_in_group("map_renderer") if get_tree() != null else null
		if mr_refresh == null:
			mr_refresh = get_node_or_null("/root/WorldMap")
		var headless_load := (
			DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")
		)
		if not headless_load:
			if mr_refresh and mr_refresh.has_method("force_full_map_refresh"):
				mr_refresh.call_deferred("force_full_map_refresh")
			elif mr_refresh and mr_refresh.has_method("_refresh_province_fill_colors"):
				mr_refresh.call_deferred("_refresh_province_fill_colors")
			# Also nudge MapManager for pick/centroid if needed post heavy apply (safe no-op if no method)
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("_recompute_centroids_and_bounds"):
				MapManager.call("_recompute_centroids_and_bounds")
		# Headless Maginot -s: deferred full-board refresh hung quit after RESULT=PASS.

	# Weather after map (provinces) + time; restores dynamic snow/ground/events from save (layer snow_potential re-applied via provinces on load)
	if data.has("weather") and typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("load_save_state"):
			WeatherManager.load_save_state(data["weather"])

	# Re-apply regional control bonuses (full control effects on supply throughput, production output via factory_output etc.) after owners/provinces restored
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
		SupplyManager._apply_regional_control_throughput_bonuses()
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("clear_all_caches"):
		ProductionManager.clear_all_caches()

	# 2b. Active infrastructure / development projects (must be after map provinces exist)
	var infra_data := _get_infrastructure_save_data(data)
	if not infra_data.is_empty() and typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		if InfrastructureDevelopmentManager.has_method("apply_loaded_data"):
			InfrastructureDevelopmentManager.apply_loaded_data(infra_data)
		# Explicit visual refresh pass after load (as requested for map overlays / InfoPanel)
		if InfrastructureDevelopmentManager.has_method("refresh_all_project_visuals"):
			InfrastructureDevelopmentManager.refresh_all_project_visuals()
		if InfrastructureDevelopmentManager.has_method("initialize_with_time"):
			InfrastructureDevelopmentManager.initialize_with_time()

	# 3. Supply depots only (deployments after leaders — step 7b)
	if data.has("supply") and typeof(SupplyManager) != TYPE_NIL:
		_apply_supply_depots_state(data["supply"])

	# 4. National modifiers (daily agent sabotage effects etc.)
	if data.has("national_modifiers") and typeof(NationalModifierManager) != TYPE_NIL:
		_apply_national_modifier_state(data["national_modifiers"])

	if data.has("national_spirits") and typeof(NationalSpiritManager) != TYPE_NIL and NationalSpiritManager.has_method("apply_save_data"):
		NationalSpiritManager.apply_save_data(data["national_spirits"])

	# 5. Technology research state + unlocks
	if data.has("technology") and typeof(TechnologyManager) != TYPE_NIL:
		_apply_technology_state(data["technology"])

	# 6. Agents + Networks (reference provinces + lead agents)
	if data.has("agents") and typeof(AgentManager) != TYPE_NIL:
		_apply_agent_state(data["agents"])

	# 7. Leaders (formations include stationed_province_id)
	if data.has("leaders") and typeof(LeaderManager) != TYPE_NIL:
		_apply_leader_state(data["leaders"])

	# 7b. Division map deployments (after leaders; syncs CombatPresenceRegistry engineers)
	if data.has("supply") and typeof(SupplyManager) != TYPE_NIL:
		_apply_supply_deployments_state(data["supply"])

	# 7c. Open land battles + march queues (after formations exist)
	if data.has("land_war") and data["land_war"] is Dictionary:
		var lw: Dictionary = data["land_war"]
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("apply_save_data"):
			BattleManager.apply_save_data({
				"open_battles": lw.get("open_battles", []),
				"next_seq": int(lw.get("next_seq", 1)),
				"last_aar": lw.get("last_aar", {}),
			})
		if typeof(FormationMovement) != TYPE_NIL:
			FormationMovement.apply_save_data({"marches": lw.get("marches", {})})

	# 8. Production + Factories (factories feed lines; apply after map provinces)
	if data.has("factories") and typeof(FactoryManager) != TYPE_NIL:
		_apply_factory_state(data["factories"])
		if FactoryManager.has_method("reconcile_factory_owners_with_map"):
			FactoryManager.reconcile_factory_owners_with_map()
	if data.has("production") and typeof(ProductionManager) != TYPE_NIL:
		_apply_production_state(data["production"])

	if data.has("design_lifecycle") and typeof(DesignManager) != TYPE_NIL:
		if DesignManager.has_method("apply_save_data"):
			DesignManager.apply_save_data(data["design_lifecycle"])

	if data.has("trade") and typeof(TradeManager) != TYPE_NIL:
		if TradeManager.has_method("apply_save_data"):
			TradeManager.apply_save_data(data["trade"])
		# Re-apply regional convoy bonuses to trade flows post-load (full control may have changed; re-assign routes for updated risk)
		if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
			SupplyManager._apply_regional_control_throughput_bonuses()
		if typeof(TradeManager) != TYPE_NIL:
			for f in TradeManager.get_active_trade_flows():
				if f and TradeManager.has_method("_try_assign_supply_route_to_flow"):
					TradeManager._try_assign_supply_route_to_flow(f)

	if data.has("space_layer") and typeof(SpaceLayerManager) != TYPE_NIL:
		if SpaceLayerManager.has_method("apply_save_data"):
			SpaceLayerManager.apply_save_data(data["space_layer"])

	# --- GameData demographic/policy state (after core managers) ---
	if data.has("game_data") and typeof(GameData) != TYPE_NIL:
		if GameData.has_method("clear_for_load"):
			GameData.clear_for_load()
		if GameData.has_method("apply_save_data"):
			GameData.apply_save_data(data["game_data"])

	# --- Province Editor (debug map design persistence) ---
	if data.has("province_editor"):
		var pe := get_tree().get_first_node_in_group("province_editor")
		if pe and pe.has_method("apply_save_data"):
			pe.apply_save_data(data["province_editor"])

	# --- Pass 22: MapRenderer UI (compare slots / intensities / mapmode) ---
	if data.has("map_ui"):
		var mr_load := get_tree().get_first_node_in_group("map_renderer") if get_tree() != null else null
		if mr_load and mr_load.has_method("apply_save_data"):
			mr_load.apply_save_data(data["map_ui"])

	# --- Pass 24: RelationsManager alliances / guarantees ---
	if data.has("relations") and typeof(RelationsManager) != TYPE_NIL:
		if RelationsManager.has_method("apply_save_data"):
			RelationsManager.apply_save_data(data["relations"])

	# Leader / agent / modifier years are not their own calendar. The next
	# year boundary increments them, so a load must leave them on the restored clock.
	_sync_sim_years_from_clock()

	# Future: after all core state, allow other managers to react
	# e.g. if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("on_game_loaded"):
	#     ProductionManager.on_game_loaded()

## --- Time ---

func _apply_time_state(t: Dictionary) -> void:
	if t.has("current_date"):
		var d: Dictionary = t["current_date"]
		TimeManager.current_year = int(d.get("year", 1936))
		TimeManager.current_month = int(d.get("month", 1))
		TimeManager.current_day = int(d.get("day", 1))
		if d.has("hour") and not t.has("current_hour"):
			TimeManager.current_hour = clampi(int(d.get("hour", 0)), 0, 23)
	if t.has("current_hour"):
		TimeManager.current_hour = clampi(int(t.get("current_hour", 0)), 0, 23)
	if t.has("scenario_start_date"):
		TimeManager.scenario_start_date = str(t["scenario_start_date"])
	if t.has("paused"):
		TimeManager.set_paused(bool(t["paused"]))
	if t.has("time_scale"):
		TimeManager.set_time_scale(float(t.get("time_scale", 1.0)))
	if t.has("total_days_elapsed"):
		TimeManager.total_days_elapsed = maxi(0, int(t.get("total_days_elapsed", 0)))
	if t.has("run_seed") and "run_seed" in TimeManager:
		TimeManager.run_seed = int(t.get("run_seed", 0))
	if t.has("accumulated_days"):
		TimeManager._accumulated_game_days = float(t.get("accumulated_days", 0.0))
	if t.has("accumulated_hours"):
		TimeManager._accumulated_game_hours = float(t.get("accumulated_hours", 0.0))
	# Do not fire game_day_advanced etc. here — we are restoring state, not simulating.


## Leader, agent, and modifier years follow TimeManager during play via year
## signals. They are not stored on their own. Restoring only the clock leaves
## them at the boot year, so the next 1 January increments a stale counter.
func _sync_sim_years_from_clock() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	var year := int(TimeManager.get_current_year())
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("set_current_year"):
		LeaderManager.set_current_year(year)
	if typeof(AgentManager) != TYPE_NIL and AgentManager.has_method("set_current_year"):
		AgentManager.set_current_year(year)
		AgentManager._last_year_ticked = year
	if typeof(NationalModifierManager) != TYPE_NIL and NationalModifierManager.has_method("set_current_year"):
		NationalModifierManager.set_current_year(year)
		NationalModifierManager._last_year_ticked = year


## --- Agents (most complex because of Resource instances) ---

func _serialize_agent_state() -> Dictionary:
	var out := { "agents": {}, "networks": {}, "agent_seq": int(AgentManager._agent_seq) }

	# Agents
	for ctag in AgentManager.agents.keys():
		var list: Array = []
		for a in (AgentManager.agents[ctag] as Array):
			if a is Agent:
				list.append(_agent_to_dict(a))
		out["agents"][ctag] = list

	# Networks
	for pid in AgentManager.networks.keys():
		var net: AgentNetwork = AgentManager.networks[pid]
		if net != null:
			out["networks"][str(pid)] = _network_to_dict(net)

	return out

func _agent_to_dict(a: Agent) -> Dictionary:
	# Use inst_to_dict for all @export fields, then add runtime non-exported ones
	var d: Dictionary = inst_to_dict(a)
	d["compromised_until_year"] = a.compromised_until_year
	d["assigned_province_id"] = a.assigned_province_id
	d["total_missions_completed"] = a.total_missions_completed
	d["successful_missions"] = a.successful_missions
	d["mission_history"] = (a.mission_history as Array).duplicate(true)
	d["traits"] = (a.traits as Array).duplicate()
	return d

func _dict_to_agent(d: Dictionary) -> Agent:
	var a := Agent.new()
	# Core identity / stats (@export + runtime)
	a.agent_id = str(d.get("agent_id", ""))
	a.name = str(d.get("name", ""))
	a.country_tag = str(d.get("country_tag", ""))
	a.level = int(d.get("level", 1))
	a.experience = int(d.get("experience", 0))
	a.intelligence = int(d.get("intelligence", 4))
	a.sabotage = int(d.get("sabotage", 4))
	a.influence = int(d.get("influence", 4))
	a.technology = int(d.get("technology", 4))
	a.counter_intelligence = int(d.get("counter_intelligence", 3))
	a.status = str(d.get("status", "available"))
	a.current_mission_id = str(d.get("current_mission_id", ""))
	a.mission_progress = float(d.get("mission_progress", 0.0))
	a.assigned_target_tag = str(d.get("assigned_target_tag", ""))
	a.assigned_target_tech_id = str(d.get("assigned_target_tech_id", ""))
	a.birth_year = int(d.get("birth_year", 1900))
	a.start_year = int(d.get("start_year", 1930))
	a.portrait_path = str(d.get("portrait_path", ""))

	# Runtime
	a.compromised_until_year = int(d.get("compromised_until_year", 0))
	a.assigned_province_id = int(d.get("assigned_province_id", 0))
	a.total_missions_completed = int(d.get("total_missions_completed", 0))
	a.successful_missions = int(d.get("successful_missions", 0))
	a.mission_history = (d.get("mission_history", []) as Array).duplicate(true)
	var raw_t = d.get("traits", [])
	a.traits = []
	if raw_t is Array:
		for t in raw_t:
			a.traits.append(str(t))

	return a

func _network_to_dict(net: AgentNetwork) -> Dictionary:
	var d: Dictionary = inst_to_dict(net)
	# Add runtime daily trackers
	d["total_intel_gathered"] = net.total_intel_gathered
	d["total_disruption_caused"] = net.total_disruption_caused
	d["last_daily_note"] = net.last_daily_note
	d["last_daily_effect"] = net.last_daily_effect
	d["last_daily_effect_scalar"] = net.last_daily_effect_scalar
	return d

func _dict_to_network(d: Dictionary) -> AgentNetwork:
	var net := AgentNetwork.new()
	net.network_id = str(d.get("network_id", ""))
	net.province_id = int(d.get("province_id", 0))
	net.controlling_country = str(d.get("controlling_country", ""))
	net.lead_agent_id = str(d.get("lead_agent_id", ""))
	net.strength = float(d.get("strength", 0.0))
	net.local_operatives = int(d.get("local_operatives", 0))
	net.focus = str(d.get("focus", "intelligence"))
	net.last_activity_month = int(d.get("last_activity_month", 0))
	net.detection_risk_accumulated = float(d.get("detection_risk_accumulated", 0.0))

	# Runtime
	net.total_intel_gathered = int(d.get("total_intel_gathered", 0))
	net.total_disruption_caused = float(d.get("total_disruption_caused", 0.0))
	net.last_daily_note = str(d.get("last_daily_note", ""))
	net.last_daily_effect = str(d.get("last_daily_effect", ""))
	net.last_daily_effect_scalar = float(d.get("last_daily_effect_scalar", 0.0))
	return net

func _apply_agent_state(a: Dictionary) -> void:
	# Clear existing runtime agent state
	AgentManager.agents.clear()
	AgentManager.networks.clear()
	AgentManager._agent_screen_cache.clear()

	# Restore agents
	var agents_by_country: Dictionary = a.get("agents", {}) as Dictionary
	for ctag in agents_by_country.keys():
		var arr: Array = []
		for entry in (agents_by_country[ctag] as Array):
			if typeof(entry) == TYPE_DICTIONARY:
				arr.append(_dict_to_agent(entry))
		AgentManager.agents[ctag] = arr

	# Restore networks
	var nets: Dictionary = a.get("networks", {}) as Dictionary
	for pid_str in nets.keys():
		var pid := int(pid_str)
		var entry: Dictionary = nets[pid_str] as Dictionary
		if typeof(entry) == TYPE_DICTIONARY:
			AgentManager.networks[pid] = _dict_to_network(entry)

	# Note: We do not re-emit every signal here; UI that cares can refresh on demand
	# or we can emit a single "agents_state_restored" if we add the signal later.
	AgentManager._agent_seq = int(a.get("agent_seq", 0))
	for ctag2 in AgentManager.agents.keys():
		var restored: Variant = AgentManager.agents[ctag2]
		if restored is Array:
			for agent_v in restored as Array:
				if agent_v is Agent:
					AgentManager.note_agent_id((agent_v as Agent).agent_id)
	print("SaveLoad: Restored %d agent countries + %d networks" % [agents_by_country.size(), nets.size()])

## --- Map (provinces) ---

func _serialize_map_state() -> Dictionary:
	var out := { "provinces": [] }
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_all_provinces"):
		return out

	# Use the public query API (added/strengthened during Save/Load work)
	var provinces_dict: Dictionary = MapManager.get_all_provinces()
	for pid in provinces_dict.keys():
		var p: Province = provinces_dict[pid]
		if p == null:
			continue
		out["provinces"].append({
			"id": p.id,
			"owner_tag": p.owner_tag,
			"controller_tag": p.controller_tag,
			"development_level": p.development_level,
			"infrastructure": p.infrastructure,
			"factories": int(p.factories),
			"settlement_level": p.settlement_level,
			"built_road_neighbors": p.built_road_neighbors.duplicate(),
			"built_rail_neighbors": p.built_rail_neighbors.duplicate(),
			"special_sites": _serialize_special_sites(p),
			# Optional. Old saves omit this key and keep the live deposit table.
			"resources": p.resources.duplicate(true) if p.resources is Dictionary else {},
		})
	return out


## Required keys per province entry in save["map"] (audit / unit tests / load hardening).
static func map_province_required_keys() -> PackedStringArray:
	return PackedStringArray([
		"id",
		"owner_tag",
		"controller_tag",
		"development_level",
		"infrastructure",
		"settlement_level",
		"built_road_neighbors",
		"built_rail_neighbors",
	])


## Validate a map save blob: provinces array + required keys + optional infrastructure_projects sibling.
## Pure structure check — used by tests and can be called after serialize/before apply.
static func validate_map_save_payload(map_data: Dictionary, full_save: Dictionary = {}) -> Dictionary:
	var missing: Array[String] = []
	if not map_data.has("provinces"):
		return {"ok": false, "missing": ["map.provinces"], "province_count": 0}
	var list: Array = map_data.get("provinces", []) as Array
	var req := map_province_required_keys()
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			missing.append("non_dict_province_entry")
			continue
		var e: Dictionary = entry
		for k in req:
			if not e.has(k):
				missing.append("province.%s" % k)
				break
	# Full save should also carry active infra projects when InfrastructureDevelopmentManager exists
	if not full_save.is_empty() and not full_save.has("infrastructure_projects"):
		missing.append("infrastructure_projects")
	return {
		"ok": missing.is_empty(),
		"missing": missing,
		"province_count": list.size(),
	}


func _apply_map_state(m: Dictionary) -> void:
	var list: Array = m.get("provinces", []) as Array
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		var pid := int(e.get("id", -1))
		if pid < 0:
			continue

		# Use the public mutation helpers so signals fire and overlays react
		if e.has("owner_tag") or e.has("controller_tag"):
			var owner := str(e.get("owner_tag", ""))
			var ctrl := str(e.get("controller_tag", ""))
			MapManager.update_province_owner(pid, owner, ctrl, true)

		if e.has("development_level"):
			MapManager.update_province_development(pid, int(e["development_level"]))

		if e.has("infrastructure"):
			MapManager.update_province_infrastructure(pid, int(e["infrastructure"]))

		# Factory counts feed military_strength when a tag has no divisions.
		# The boot map uses a different count than a mid-war economy, so a
		# load that skips this field starts wars the uninterrupted run does not.
		if e.has("factories"):
			var p_fac: Province = MapManager.get_province(pid)
			if p_fac != null:
				p_fac.factories = int(e["factories"])

		if e.has("settlement_level"):
			var sl := float(e.get("settlement_level", 0.0))
			if MapManager.has_method("update_province_settlement"):
				MapManager.update_province_settlement(pid, sl)
			else:
				# fallback direct + emit (preserves Province getter data for combat/preview)
				var pp: Province = MapManager.get_province(pid)
				if pp != null:
					pp.settlement_level = clampf(sl, 0.0, 5.0)
					MapManager.notify_province_changed(pid, "settlement")

		if e.has("built_road_neighbors"):
			var p_road: Province = MapManager.get_province(pid)
			if p_road != null:
				p_road.built_road_neighbors = Array(e.get("built_road_neighbors", []), TYPE_INT, "", null)
				MapManager.notify_province_changed(pid, "infrastructure")
		if e.has("built_rail_neighbors"):
			var p_rail: Province = MapManager.get_province(pid)
			if p_rail != null:
				p_rail.built_rail_neighbors = Array(e.get("built_rail_neighbors", []), TYPE_INT, "", null)
				MapManager.notify_province_changed(pid, "infrastructure")

		if e.has("special_sites"):
			_apply_special_sites(pid, e["special_sites"])

		# Missing key: leave the province's current deposits (old saves).
		if e.has("resources") and e["resources"] is Dictionary:
			var p_res: Province = MapManager.get_province(pid)
			if p_res != null:
				p_res.resources = (e["resources"] as Dictionary).duplicate(true)

	print("SaveLoad: Applied province state to %d provinces (signals emitted)" % list.size())

	# Re-seed weather from (possibly updated) provinces snow_potential after map restore (preserves layer-driven high elev snow on reload)
	var wm := get_node_or_null("/root/WeatherManager") if get_tree() else null
	if wm == null and Engine.has_singleton("WeatherManager"):
		wm = Engine.get_singleton("WeatherManager")
	if wm and wm.has_method("initialize_province") and typeof(MapManager) != TYPE_NIL:
		var allp := MapManager.get_all_provinces() if MapManager.has_method("get_all_provinces") else {}
		for pidv in allp:
			var p: Province = allp[pidv]
			if p and p.snow_potential > 0.0:
				wm.initialize_province(pidv, {"is_northern": p.snow_potential > 0.05, "lat": 55.0, "high_ground_fraction": p.snow_potential, "snow_potential": p.snow_potential})


## Helper to serialize special sites on a province
func _serialize_special_sites(p: Province) -> Array:
	var out := []
	if p == null or p.special_sites.is_empty():
		return out
	for site in p.special_sites:
		if site == null:
			continue
		out.append({
			"id": site.id,
			"site_type": int(site.site_type),
			"tier": site.tier,
			"construction_state": int(site.construction_state),
			"construction_progress": site.construction_progress,
			"damage_level": site.damage_level,
			"owner_tag": site.owner_tag,
			"upgrade_target_id": site.upgrade_target_id if site.has_method("get_upgrade_target_id") or "upgrade_target_id" in site else ""
		})
	return out

func _apply_special_sites(pid: int, sites_data: Array) -> void:
	var province: Province = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
	if province == null:
		return

	province.special_sites.clear()

	for sdata in sites_data:
		if typeof(sdata) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = sdata

		var site := SpecialSite.new()
		site.id = d.get("id", "")
		site.site_type = SpecialSite.SiteType.values()[int(d.get("site_type", 0))]
		site.tier = int(d.get("tier", 1))
		site.construction_state = SpecialSite.ConstructionState.values()[int(d.get("construction_state", 2))]
		site.construction_progress = float(d.get("construction_progress", 1.0))
		site.damage_level = int(d.get("damage_level", 0))
		site.owner_tag = d.get("owner_tag", "")
		site.upgrade_target_id = d.get("upgrade_target_id", "")

		province.special_sites.append(site)

	if not sites_data.is_empty():
		MapManager.notify_province_changed(pid, "special_site")


## --- Supply depots ---

func _serialize_supply_state() -> Dictionary:
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_save_data"):
		return SupplyManager.get_save_data()
	var out := { "depots": {}, "division_deployments": {} }
	if typeof(SupplyManager) == TYPE_NIL:
		return out

	for pid in SupplyManager.depot_states.keys():
		var depot: ProvinceDepotState = SupplyManager.depot_states[pid]
		if depot == null:
			continue
		out["depots"][str(pid)] = {
			"stockpile": depot.stockpile,
			"throughput_capacity": depot.throughput_capacity,
			"sabotage_level": depot.sabotage_level,
			# inbound/outbound are transient; usually not worth persisting
		}
	if "division_deployments" in SupplyManager:
		for fid in SupplyManager.division_deployments.keys():
			out["division_deployments"][str(fid)] = (
				SupplyManager.division_deployments[fid] as Dictionary
			).duplicate(true)
	return out

func _apply_supply_depots_state(s: Dictionary) -> void:
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("apply_save_data"):
		SupplyManager.apply_save_data(s, true, false)
		return
	_apply_supply_depots_legacy(s)


func _apply_supply_deployments_state(s: Dictionary) -> void:
	if typeof(SupplyManager) == TYPE_NIL:
		return
	var slice: Dictionary = s as Dictionary
	if not slice.has("division_deployments"):
		return
	if SupplyManager.has_method("apply_save_data"):
		SupplyManager.apply_save_data(slice, false, true)
		return
	SupplyManager.division_deployments = (
		slice.get("division_deployments", {}) as Dictionary
	).duplicate(true)
	if SupplyManager.has_method("resync_division_deployments_to_registry"):
		SupplyManager.resync_division_deployments_to_registry()


func _apply_supply_depots_legacy(s: Dictionary) -> void:
	var depots: Dictionary = s.get("depots", {}) as Dictionary
	var restored := 0
	for pid_str in depots.keys():
		var pid := int(pid_str)
		var entry: Dictionary = depots[pid_str] as Dictionary
		var depot: ProvinceDepotState = SupplyManager.depot_states.get(pid)
		if depot != null and typeof(entry) == TYPE_DICTIONARY:
			depot.stockpile = float(entry.get("stockpile", depot.stockpile))
			if entry.has("throughput_capacity"):
				depot.throughput_capacity = float(entry["throughput_capacity"])
			if entry.has("sabotage_level"):
				depot.sabotage_level = float(entry["sabotage_level"])
			restored += 1
	print("SaveLoad: Restored %d depot states (stock/sabotage/throughput)" % restored)

## --- NationalModifierManager ---

func _apply_national_modifier_state(n: Dictionary) -> void:
	if typeof(NationalModifierManager) == TYPE_NIL:
		return
	# Replace wholesale — tick_modifiers will continue decaying on next monthly tick
	NationalModifierManager.country_modifiers = (n.get("country_modifiers", {}) as Dictionary).duplicate(true)
	if NationalModifierManager.has_method("apply_saved_effect_seq"):
		NationalModifierManager.apply_saved_effect_seq(int(n.get("effect_seq", 0)))
	print("SaveLoad: National modifier effects restored")

## --- Technology ---

func _apply_technology_state(t: Dictionary) -> void:
	if typeof(TechnologyManager) == TYPE_NIL:
		return

	if TechnologyManager.has_method("apply_save_data"):
		var payload := t.duplicate(true)
		# A stub or empty country_state must not wipe scenario research.
		var cs: Variant = payload.get("country_state", {})
		if not (cs is Dictionary) or (cs as Dictionary).is_empty():
			payload.erase("country_state")
		TechnologyManager.apply_save_data(payload)
	else:
		var legacy: Dictionary = t.get("country_state", {}) as Dictionary
		if not legacy.is_empty():
			TechnologyManager.country_state = legacy.duplicate(true)
		if TechnologyManager.has_method("_rebuild_unlock_indices"):
			TechnologyManager._rebuild_unlock_indices()

	# Old blobs omit the year. Follow the clock already restored above.
	if not t.has("current_year") and typeof(TimeManager) != TYPE_NIL and TechnologyManager.has_method("set_current_year"):
		TechnologyManager.set_current_year(int(TimeManager.get_current_year()))
	if TechnologyManager.has_method("get_current_year"):
		TechnologyManager._last_year_ticked = int(TechnologyManager.get_current_year())

	print("SaveLoad: Technology country_state restored for %d countries (year %d)" % [
		TechnologyManager.country_state.size(),
		int(TechnologyManager.get_current_year()) if TechnologyManager.has_method("get_current_year") else 0,
	])

## Convenience / debug helpers

func quicksave() -> bool:
	return save_game(DEFAULT_SLOT)

func quickload() -> bool:
	return load_game(DEFAULT_SLOT)

func get_last_save_path() -> String:
	return _last_save_path

## === Save Menu / Scenario helpers (foundation for future UI) ===

## Returns the scenario_id stored in the save (or "" if not present).
func get_saved_scenario_id(slot_name: String) -> String:
	var meta := _peek_metadata(get_save_path(slot_name))
	return str(meta.get("scenario_id", ""))

## Lightweight compatibility check. Returns { "compatible": bool, "saved_scenario": "...", "current_scenario": "..." }
## Future menu can use this to warn or offer to load the matching scenario first.
func check_scenario_compatibility(slot_name: String) -> Dictionary:
	var saved := get_saved_scenario_id(slot_name)
	var current := ""
	var loader := _find_scenario_loader()
	if loader != null:
		current = loader.get_current_scenario_name()
	return {
		"compatible": saved.is_empty() or current.is_empty() or saved == current,
		"saved_scenario": saved,
		"current_scenario": current
	}

## === New apply helpers for expanded state ===

func _apply_leader_state(l: Dictionary) -> void:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("apply_save_data"):
		LeaderManager.apply_save_data(l)
		return
	# Fallback direct (if no method yet)
	print("SaveLoad: Leader state present but no apply_save_data on LeaderManager (direct apply limited)")

func _apply_factory_state(f: Dictionary) -> void:
	if typeof(FactoryManager) != TYPE_NIL and FactoryManager.has_method("apply_save_data"):
		FactoryManager.apply_save_data(f)
		return
	print("SaveLoad: Factory state present but no apply on FactoryManager")

func _apply_production_state(p: Dictionary) -> void:
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("apply_save_data"):
		ProductionManager.apply_save_data(p)
		return
	print("SaveLoad: Production state present but no apply on ProductionManager")

## === Robustness: version migration stub + improved error handling ===

## Called for old save versions to upgrade data in-place before _apply.
## Add cases here as SAVE_VERSION increases (e.g. key renames, default sections, data shape fixes).
## This is the central place for forward/backward compat.
func _migrate_save_data(data: Dictionary) -> void:
	var v := int(data.get("save_version", 0))
	if v >= SAVE_VERSION:
		return
	print("SaveLoad: Migrating save from v%d to v%d" % [v, SAVE_VERSION])
	if v < 2:
		_migrate_save_v1_to_v2(data)
	data["save_version"] = SAVE_VERSION


## v1 blobs omitted depot fuel/munitions, id counters, and the supply cursors.
## Missing keys get defaults. National spirits are left untouched so a missing
## section still reloads the definition list.
func _migrate_save_v1_to_v2(data: Dictionary) -> void:
	var supply: Variant = data.get("supply", {})
	if supply is Dictionary:
		var depots: Variant = (supply as Dictionary).get("depots", {})
		if depots is Dictionary:
			for pid_str in (depots as Dictionary).keys():
				var entry: Variant = (depots as Dictionary)[pid_str]
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				var row: Dictionary = entry
				if not row.has("fuel_stockpile"):
					row["fuel_stockpile"] = 0.0
				if not row.has("munitions_stockpile"):
					row["munitions_stockpile"] = float(row.get("stockpile", 0.0)) * 0.35
				(depots as Dictionary)[pid_str] = row
			(supply as Dictionary)["depots"] = depots
		if not (supply as Dictionary).has("refill_queue"):
			(supply as Dictionary)["refill_queue"] = []
		if not (supply as Dictionary).has("supply_day_jobs"):
			(supply as Dictionary)["supply_day_jobs"] = []
		if not (supply as Dictionary).has("attrition"):
			(supply as Dictionary)["attrition"] = {"losses": {}, "leaders": {}}
		data["supply"] = supply
	var leaders: Variant = data.get("leaders", {})
	if leaders is Dictionary:
		if not (leaders as Dictionary).has("replacement_seq"):
			(leaders as Dictionary)["replacement_seq"] = 0
		if not (leaders as Dictionary).has("leader_id_seq"):
			(leaders as Dictionary)["leader_id_seq"] = 0
		if not (leaders as Dictionary).has("fielded_seq"):
			(leaders as Dictionary)["fielded_seq"] = 0
		if not (leaders as Dictionary).has("officer_training_quality"):
			(leaders as Dictionary)["officer_training_quality"] = {}
		if not (leaders as Dictionary).has("months_in_training"):
			(leaders as Dictionary)["months_in_training"] = {}
		if not (leaders as Dictionary).has("officer_training_debuff_months"):
			(leaders as Dictionary)["officer_training_debuff_months"] = {}
		data["leaders"] = leaders
	var production: Variant = data.get("production", {})
	if production is Dictionary and not (production as Dictionary).has("family_units_produced"):
		(production as Dictionary)["family_units_produced"] = {}
		data["production"] = production
	var agents: Variant = data.get("agents", {})
	if agents is Dictionary and not (agents as Dictionary).has("agent_seq"):
		(agents as Dictionary)["agent_seq"] = 0
		data["agents"] = agents
	var modifiers: Variant = data.get("national_modifiers", {})
	if modifiers is Dictionary and not (modifiers as Dictionary).has("effect_seq"):
		(modifiers as Dictionary)["effect_seq"] = 0
		data["national_modifiers"] = modifiers

## === Infrastructure migration support (added May 2026) ===
## Handles old saves that pre-date the "infrastructure_projects" section.
## Supports:
##   - Modern key "infrastructure_projects"
##   - Legacy key "infrastructure" (user sketch format or early experiments)
##   - Per-province "active_project" entries
func _get_infrastructure_save_data(save_root: Dictionary) -> Dictionary:
	if save_root.is_empty():
		return {}

	# Preferred modern format
	if save_root.has("infrastructure_projects"):
		var d: Dictionary = save_root["infrastructure_projects"]
		if typeof(d) == TYPE_DICTIONARY and d.has("active_projects"):
			return d

	# Legacy top-level "infrastructure" key (user's original sketch or early saves)
	if save_root.has("infrastructure"):
		var legacy: Dictionary = save_root["infrastructure"]
		if typeof(legacy) == TYPE_DICTIONARY:
			# Convert user's example shape into the real manager shape if needed
			var converted := { "version": 1, "active_projects": {} }
			for pid_str in legacy.keys():
				var entry: Dictionary = legacy[pid_str] as Dictionary
				if entry == null:
					continue
				var proj_data: Variant = entry.get("active_project", null)
				if proj_data != null and typeof(proj_data) == TYPE_DICTIONARY:
					converted["active_projects"][pid_str] = proj_data
				elif entry.has("project"):  # alternative legacy shape
					converted["active_projects"][pid_str] = entry["project"]
			if not converted["active_projects"].is_empty():
				print("SaveLoad: Migrated legacy 'infrastructure' section to infrastructure_projects format.")
				return converted

	# Also check inside "map" for any stray per-province project data (very old experiments)
	if save_root.has("map"):
		var map_section: Dictionary = save_root["map"]
		if map_section.has("provinces") and typeof(map_section["provinces"]) == TYPE_ARRAY:
			var converted2 := { "version": 1, "active_projects": {} }
			for p in map_section["provinces"]:
				if typeof(p) != TYPE_DICTIONARY:
					continue
				var pid := str(p.get("id", ""))
				var proj: Variant = p.get("active_infra_project", null)
				if proj == null:
					proj = p.get("active_project", null)
				if proj != null and typeof(proj) == TYPE_DICTIONARY:
					converted2["active_projects"][pid] = proj
			if not converted2["active_projects"].is_empty():
				print("SaveLoad: Found stray per-province project data in map section — migrated.")
				return converted2

	return {}

## Enhanced save with better error object (for future UI).
func save_game_detailed(slot_name: String = DEFAULT_SLOT) -> Dictionary:
	_ensure_save_dir()
	var safe_slot := _sanitize_slot(slot_name)
	var path := get_save_path(safe_slot)
	var abs_path := get_save_path_global(safe_slot)
	print("SaveLoadManager: Saving slot=%s → %s" % [safe_slot, abs_path])

	var data: Dictionary = {}
	# Guard: gather can be heavy on world_accurate; never let a script error leave silent UI.
	data = _gather_save_data()
	if data.is_empty():
		var empty_msg := "Save data empty (gather failed)"
		push_error("SaveLoadManager: %s" % empty_msg)
		return {"ok": false, "error": empty_msg, "path": path, "absolute_path": abs_path}
	# Never write a partial mid-war blob: refuse a missing land_war key.
	# Always emit the land_war {} shape (empty open_battles / marches are valid).
	if not data.has("land_war") or typeof(data["land_war"]) != TYPE_DICTIONARY:
		var missing_lw := "Save data missing land_war key (gather incomplete)"
		push_error("SaveLoadManager: %s" % missing_lw)
		return {"ok": false, "error": missing_lw, "path": path, "absolute_path": abs_path}
	var lw_out: Dictionary = data["land_war"]
	if not lw_out.has("open_battles") or typeof(lw_out["open_battles"]) != TYPE_ARRAY:
		lw_out["open_battles"] = []
	if not lw_out.has("marches") or typeof(lw_out["marches"]) != TYPE_DICTIONARY:
		lw_out["marches"] = {}
	if not lw_out.has("next_seq"):
		lw_out["next_seq"] = 1
	if not lw_out.has("last_aar") or typeof(lw_out.get("last_aar", null)) != TYPE_DICTIONARY:
		lw_out["last_aar"] = {}
	data["land_war"] = lw_out
	_stamp_slot_metadata(data, safe_slot)

	# Autosave / live F5: compact JSON (no tab indent). Pretty-print of the
	# 3520-province blob doubled peak RSS on llvmpipe Play soaks.
	var indent := "" if (safe_slot == "autosave" or _should_skip_live_f5_calendar_autosave()) else "\t"
	var json_text := JSON.stringify(data, indent)
	if safe_slot == "autosave":
		# Sample while the JSON string is still live so the day-7 peak is not
		# hidden by freeing it before the after-read.
		_calendar_autosave_rss_mid_kb = _vm_status_kb("VmRSS")
		_calendar_autosave_hwm_mid_kb = _vm_status_kb("VmHWM")
	if json_text.is_empty() or json_text == "null":
		var jmsg := "JSON stringify failed"
		push_error("SaveLoadManager: %s" % jmsg)
		return {"ok": false, "error": jmsg, "path": path, "absolute_path": abs_path}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		# Retry with absolute path
		f = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		var msg := "Cannot write save (error %d) — path %s" % [err, abs_path]
		push_error("SaveLoadManager: %s" % msg)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("Save failed: " + msg, 4.0, true)
		return {"ok": false, "error": msg, "path": path, "absolute_path": abs_path, "code": err}

	f.store_string(json_text)
	f.close()
	_last_save_path = path
	_note_save_elapsed()
	var bytes := json_text.length()
	print("SaveLoadManager: Game saved → %s (v%d, %d bytes, slot=%s)" % [abs_path, SAVE_VERSION, bytes, safe_slot])
	_notify_save_list_refresh()
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Saved %s (%d KB)" % [safe_slot, int(bytes / 1024)], 2.5)
	return {
		"ok": true,
		"path": path,
		"absolute_path": abs_path,
		"slot": safe_slot,
		"bytes": bytes,
		"version": SAVE_VERSION,
	}

## Enhanced load with migration + feedback.
func load_game_detailed(slot_name: String = DEFAULT_SLOT) -> Dictionary:
	var slot_key := str(slot_name)
	var frame_now := Engine.get_process_frames()
	if frame_now == _load_apply_frame and slot_key == _load_apply_slot:
		print("EOA_LOAD_APPLY skip duplicate slot=%s" % slot_key)
		return {"ok": true, "duplicate": true, "path": get_save_path(slot_name), "slot": slot_key}
	var path := get_save_path(slot_name)
	if not FileAccess.file_exists(path):
		var msg := "File not found: " + path
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("Load failed: " + msg, 3.0, true)
		return {"ok": false, "error": msg, "path": path}

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Cannot open for read", "path": path}

	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		var unread := _unreadable_load_error()
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(unread, 3.0, true)
		return {"ok": false, "error": unread, "path": path}

	var data: Dictionary = parsed
	if not _blob_looks_like_save(data):
		var unread2 := _unreadable_load_error()
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(unread2, 3.0, true)
		return {"ok": false, "error": unread2, "path": path}
	_migrate_save_data(data)  # upgrades in place if old

	var file_version := int(data.get("save_version", 0))
	if file_version > SAVE_VERSION:
		push_warning("SaveLoadManager: Save v%d > current v%d; best-effort only" % [file_version, SAVE_VERSION])

	# Claim the frame before apply so a re-entrant second call cannot apply again.
	_load_apply_frame = frame_now
	_load_apply_slot = slot_key
	_apply_save_data(data)
	_adopt_loaded_elapsed()
	_notify_top_bar_speed_resync()
	eoa_load_apply_count += 1
	print("EOA_LOAD_APPLY n=%d slot=%s" % [eoa_load_apply_count, slot_key])
	_emit_load_completed(slot_key)
	return {"ok": true, "path": path, "version": file_version, "slot": slot_key}

## === UX helpers (delete, rename) for save menu ===

func delete_save(slot_name: String) -> bool:
	var path := get_save_path(slot_name)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_error("SaveLoadManager: Failed to delete %s (err %d)" % [path, err])
		return false
	print("SaveLoadManager: Deleted save %s" % slot_name)
	return true

func rename_save(old_slot: String, new_slot: String) -> bool:
	var old_path := get_save_path(old_slot)
	var new_path := get_save_path(new_slot)
	if not FileAccess.file_exists(old_path):
		return false
	if FileAccess.file_exists(new_path):
		push_warning("SaveLoadManager: Target name already exists: %s" % new_slot)
		return false

	var content := FileAccess.get_file_as_string(old_path)
	var f := FileAccess.open(new_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(content)
	f.close()

	DirAccess.remove_absolute(old_path)
	print("SaveLoadManager: Renamed %s -> %s" % [old_slot, new_slot])
	return true
