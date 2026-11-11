# scripts/core/TutorialGuideDomain.gd
## Pure first-session guide step machine. No node access. Headless-testable.
class_name TutorialGuideDomain
extends RefCounted

const SPEC_PATH := "res://data/tutorial/first_session_1936.json"
const CFG_PATH := "user://first_session.cfg"
const CFG_SECTION := "guide"
const ENV_KEY := "EOA_TUTORIAL"
const DEFAULT_TARGET := "POL"
const DEFAULT_TARGET_NAME := "Poland"
const STEP_COUNT := 12
const SAVE_FALLBACK_MINUTES := 15.0
const FIGHT_WAIT_BODY := "Keep marching to the border"
const WAR_SKIP_TITLE := "You are at war with %s"
const QA_ENVS: PackedStringArray = [
	"EOA_SKIP_TITLE",
	"EOA_UNIT_ORDER_QA",
	"EOA_UI_SMOKE",
	"EOA_YEAR_MULTI_AI",
	"EOA_RUN_50_TURN_SIM",
	"EOA_RUN_LONG_SIM",
	"EOA_HEADLESS_EVIDENCE",
	"EOA_FAST_TEST",
	"EOA_TEST_SAVE_LOAD",
	"EOA_RUN_SIM_CYCLES",
]

static var _spec_cache: Dictionary = {}
static var _spec_loaded: bool = false


static func spec() -> Dictionary:
	if _spec_loaded:
		return _spec_cache
	_spec_loaded = true
	_spec_cache = {}
	if not FileAccess.file_exists(SPEC_PATH):
		return _spec_cache
	var f := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if f == null:
		return _spec_cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_spec_cache = parsed
	return _spec_cache


static func steps() -> Array:
	var raw: Variant = spec().get("steps", [])
	if raw is Array:
		return raw
	return []


static func step_by_id(step_id: String) -> Dictionary:
	for raw in steps():
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == step_id:
			return raw
	return {}


static func empty_progress() -> Dictionary:
	return {
		"answered": false,
		"enabled": false,
		"completed": false,
		"done_steps": [],
		"skipped_steps": [],
		"version": 1,
		"reshow_welcome": false,
		"target_tag": DEFAULT_TARGET,
	}


static func env_tutorial() -> int:
	var raw := OS.get_environment(ENV_KEY).strip_edges()
	if raw == "1":
		return 1
	if raw == "0":
		return 0
	return -1


static func is_headless_runtime(snapshot: Dictionary = {}) -> bool:
	if snapshot.has("headless"):
		return bool(snapshot.get("headless", false))
	if DisplayServer.get_name() == "headless":
		return true
	if OS.has_feature("dedicated_server"):
		return true
	return false


static func is_qa_or_harness(snapshot: Dictionary = {}) -> bool:
	if snapshot.has("qa_run"):
		return bool(snapshot.get("qa_run", false))
	if is_headless_runtime(snapshot):
		return true
	for k in QA_ENVS:
		if OS.get_environment(k).strip_edges() == "1":
			return true
	if not OS.get_environment("EOA_PLAYER_TAG").strip_edges().is_empty():
		return true
	var year := OS.get_environment("EOA_START_YEAR").strip_edges()
	if year == "1918" or year == "1936" or year == "2026":
		return true
	return false


static func user_has_saves(snapshot: Dictionary = {}) -> bool:
	if snapshot.has("has_saves"):
		return bool(snapshot.get("has_saves", false))
	var dir := DirAccess.open("user://saves")
	if dir == null:
		return false
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var lower := name.to_lower()
			if lower.ends_with(".json") or lower.ends_with(".save") or lower.ends_with(".tres"):
				dir.list_dir_end()
				return true
		name = dir.get_next()
	dir.list_dir_end()
	return false


static func should_show_prompt(snapshot: Dictionary, progress: Dictionary) -> bool:
	if env_tutorial() == 1:
		return false
	if env_tutorial() == 0:
		return false
	if bool(progress.get("answered", false)):
		return false
	if bool(snapshot.get("loaded_save", false)):
		return false
	if not bool(snapshot.get("title_closed", false)):
		return false
	if not bool(snapshot.get("world_map_present", false)):
		return false
	if bool(snapshot.get("campaign_end_open", false)):
		return false
	if is_headless_runtime(snapshot):
		return false
	if is_qa_or_harness(snapshot) and env_tutorial() != 1:
		return false
	if user_has_saves(snapshot):
		return false
	var tag := str(snapshot.get("player_tag", "")).strip_edges().to_upper()
	var year := int(snapshot.get("start_year", 0))
	if tag != "GER" or year != 1936:
		return false
	return true


static func should_auto_start(snapshot: Dictionary, progress: Dictionary) -> bool:
	if bool(snapshot.get("loaded_save", false)):
		return false
	if bool(snapshot.get("title_open", false)) or not bool(snapshot.get("title_closed", false)):
		return false
	if not bool(snapshot.get("world_map_present", false)):
		return false
	if bool(snapshot.get("campaign_end_open", false)):
		return false
	if env_tutorial() == 0:
		return false
	if env_tutorial() == 1:
		return true
	if is_qa_or_harness(snapshot):
		return false
	if is_headless_runtime(snapshot):
		return false
	if not bool(progress.get("enabled", false)):
		return false
	if bool(progress.get("completed", false)):
		return false
	return true


static func load_cfg() -> Dictionary:
	var out := empty_progress()
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return out
	if not cfg.has_section(CFG_SECTION):
		return out
	out["answered"] = bool(cfg.get_value(CFG_SECTION, "answered", false))
	out["enabled"] = bool(cfg.get_value(CFG_SECTION, "enabled", false))
	out["completed"] = bool(cfg.get_value(CFG_SECTION, "completed", false))
	out["version"] = int(cfg.get_value(CFG_SECTION, "version", 1))
	out["done_steps"] = _as_string_array(cfg.get_value(CFG_SECTION, "done_steps", []))
	out["skipped_steps"] = _as_string_array(cfg.get_value(CFG_SECTION, "skipped_steps", []))
	return out


static func save_cfg(progress: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value(CFG_SECTION, "answered", bool(progress.get("answered", false)))
	cfg.set_value(CFG_SECTION, "enabled", bool(progress.get("enabled", false)))
	cfg.set_value(CFG_SECTION, "completed", bool(progress.get("completed", false)))
	cfg.set_value(CFG_SECTION, "version", int(progress.get("version", 1)))
	cfg.set_value(CFG_SECTION, "done_steps", PackedStringArray(_as_string_array(progress.get("done_steps", []))))
	cfg.set_value(CFG_SECTION, "skipped_steps", PackedStringArray(_as_string_array(progress.get("skipped_steps", []))))
	cfg.save(CFG_PATH)


static func mark_answered(progress: Dictionary, enabled: bool) -> Dictionary:
	var out := progress.duplicate(true)
	out["answered"] = true
	out["enabled"] = enabled
	if not enabled:
		out["completed"] = bool(out.get("completed", false))
	return out


static func reset_for_replay(progress: Dictionary) -> Dictionary:
	var out := progress.duplicate(true)
	out["enabled"] = true
	out["completed"] = false
	out["done_steps"] = []
	out["skipped_steps"] = []
	out["reshow_welcome"] = true
	out["target_tag"] = DEFAULT_TARGET
	if not bool(out.get("answered", false)):
		out["answered"] = true
	return out


static func evaluate(snapshot: Dictionary, progress: Dictionary) -> Dictionary:
	var hidden := _hidden_result()
	if bool(snapshot.get("campaign_end_open", false)):
		return hidden
	if bool(snapshot.get("title_open", false)):
		return hidden
	if not bool(snapshot.get("title_closed", snapshot.get("world_map_present", false))):
		return hidden
	if not bool(snapshot.get("world_map_present", false)):
		return hidden
	if bool(snapshot.get("loaded_save", false)):
		return hidden
	if not should_auto_start(snapshot, progress) and env_tutorial() != 1:
		if not bool(progress.get("enabled", false)):
			return hidden
	if env_tutorial() == 0:
		return hidden
	if not bool(progress.get("enabled", false)) and env_tutorial() != 1:
		return hidden
	var rows: Array = steps()
	if rows.is_empty():
		return hidden
	var done: Array = _as_string_array(progress.get("done_steps", []))
	var reshow_welcome := bool(progress.get("reshow_welcome", false))
	var prev_done := true
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var step: Dictionary = raw
		var sid := str(step.get("id", ""))
		if sid.is_empty():
			continue
		var already := done.has(sid)
		if sid == "welcome" and reshow_welcome:
			already = false
		if already:
			continue
		var trigger := str(step.get("trigger", "")).strip_edges()
		var complete := str(step.get("complete", "")).strip_edges()
		if not complete.is_empty() and _pred(complete, snapshot, progress, done):
			return _card_result(step, snapshot, "done", "", true)
		var skip_if := str(step.get("skip_if", "")).strip_edges()
		var player := str(snapshot.get("player_tag", "")).strip_edges().to_upper()
		var war_sid := sid == "justify" or sid == "justify_wait" or sid == "declare"
		if war_sid and player != "GER":
			return _auto_skip_result(step, snapshot, progress, done)
		if not skip_if.is_empty() and _pred(skip_if, snapshot, progress, done):
			return _auto_skip_result(step, snapshot, progress, done)
		var trig_ok := trigger.is_empty() or _pred(trigger, snapshot, progress, done)
		if not trig_ok:
			if sid == "fight" and float(snapshot.get("minutes_since_begin", 0.0)) >= SAVE_FALLBACK_MINUTES:
				continue
			if sid == "fight" and done.has("march"):
				return _card_result(step, snapshot, "waiting", FIGHT_WAIT_BODY, false)
			if prev_done:
				return _card_result(step, snapshot, "waiting", "", false)
			continue
		var state := "active"
		if str(step.get("kind", "")) == "wait":
			state = "waiting"
		return _card_result(step, snapshot, state, "", false)
	return hidden


static func fill_copy(text: String, snapshot: Dictionary) -> String:
	var name := str(snapshot.get("target_name", "")).strip_edges()
	if name.is_empty():
		name = DEFAULT_TARGET_NAME
	var out := text.replace("$target_name", name)
	out = out.replace("$target", name)
	if name != DEFAULT_TARGET_NAME:
		out = out.replace("a Polish province", "a %s province" % name)
		out = out.replace("Polish troops", "%s troops" % name)
		out = out.replace("Poland", name)
	return out


static func _hidden_result() -> Dictionary:
	return {
		"visible": false,
		"step_id": "",
		"n": 0,
		"kind": "",
		"state": "hidden",
		"title": "",
		"body": "",
		"status_text": "",
		"category": "",
		"accent": "cyan",
		"keys": [],
		"spotlight": false,
		"progress": {},
		"target": {},
		"done_title": "",
		"done_body": "",
		"auto_skip_ids": [],
		"show_dont_show_again": false,
		"show_skip_step": false,
	}


static func _card_result(
	step: Dictionary,
	snapshot: Dictionary,
	state: String,
	body_override: String,
	complete: bool
) -> Dictionary:
	var accent := str(step.get("accent", "cyan"))
	var body := body_override
	if body.is_empty():
		if str(step.get("id", "")) == "justify" and not bool(snapshot.get("inspector_on_target", false)):
			body = str(step.get("body_no_inspector", step.get("body", "")))
		else:
			body = str(step.get("body", ""))
	var title := str(step.get("title", ""))
	var done_title := str(step.get("done_title", ""))
	var done_body := str(step.get("done_body", ""))
	if state == "done":
		if not done_title.is_empty():
			title = done_title
		if not done_body.is_empty():
			body = done_body
		accent = "success"
	title = fill_copy(title, snapshot)
	body = fill_copy(body, snapshot)
	done_title = fill_copy(done_title, snapshot)
	done_body = fill_copy(done_body, snapshot)
	var status := str(step.get("status", ""))
	if state == "waiting" and status.is_empty() and not body_override.is_empty():
		status = "Waiting for you: " + body_override.to_lower()
	var keys: Array = []
	var raw_keys: Variant = step.get("keys", [])
	if raw_keys is Array:
		for k in raw_keys:
			keys.append(fill_copy(str(k), snapshot))
	var progress_row := {}
	var spec_prog: Variant = step.get("progress", {})
	if spec_prog is Dictionary and not (spec_prog as Dictionary).is_empty():
		var total := int(snapshot.get("player_justify_days", 14))
		var left := int(snapshot.get("player_justify_days_left", total))
		var current := clampi(total - left, 0, total)
		var label_fmt := str((spec_prog as Dictionary).get("label", "%d of %d days"))
		progress_row = {
			"current": current,
			"total": total,
			"label": label_fmt % [current, total],
		}
	var kind := str(step.get("kind", "action"))
	return {
		"visible": true,
		"step_id": str(step.get("id", "")),
		"n": int(step.get("n", 0)),
		"kind": kind,
		"state": state,
		"title": title,
		"body": body,
		"status_text": fill_copy(status, snapshot),
		"category": str(step.get("category", "")),
		"accent": accent,
		"keys": keys,
		"spotlight": bool(step.get("spotlight", false)) and state != "done" and body_override.is_empty(),
		"progress": progress_row,
		"target": step.get("target", {}) if state != "waiting" or body_override.is_empty() else {},
		"done_title": done_title,
		"done_body": done_body,
		"auto_skip_ids": [],
		"show_dont_show_again": bool(step.get("show_dont_show_again", false)),
		"show_skip_step": kind == "action" or kind == "wait",
		"complete": complete,
	}


static func _auto_skip_result(
	step: Dictionary,
	snapshot: Dictionary,
	_progress: Dictionary,
	_done: Array
) -> Dictionary:
	var sid := str(step.get("id", ""))
	var ids: Array = [sid]
	var at_war := bool(snapshot.get("at_war_any", false)) or bool(snapshot.get("at_war_with_target", false))
	var player := str(snapshot.get("player_tag", "")).strip_edges().to_upper()
	if (at_war or player != "GER") and (sid == "justify" or sid == "justify_wait" or sid == "declare"):
		ids = ["justify", "justify_wait", "declare"]
	var enemy := str(snapshot.get("war_enemy_name", snapshot.get("target_name", DEFAULT_TARGET_NAME))).strip_edges()
	if enemy.is_empty():
		enemy = DEFAULT_TARGET_NAME
	var title := str(step.get("title", ""))
	var body := str(step.get("body", ""))
	if at_war:
		title = WAR_SKIP_TITLE % enemy
		body = ""
	var result := _card_result(step, snapshot, "auto_skip", "", true)
	result["auto_skip_ids"] = ids
	result["title"] = title
	result["body"] = body
	result["accent"] = "success"
	return result


static func _pred(expr: String, snapshot: Dictionary, progress: Dictionary, done: Array) -> bool:
	var e := expr.strip_edges()
	if e.is_empty():
		return true
	var or_parts := e.split(" OR ", false)
	if or_parts.size() > 1:
		for part in or_parts:
			if _pred(str(part), snapshot, progress, done):
				return true
		return false
	var and_parts := e.split(" AND ", false)
	if and_parts.size() > 1:
		for part in and_parts:
			if not _pred(str(part), snapshot, progress, done):
				return false
		return true
	return _atom(e, snapshot, progress, done)


static func _atom(atom: String, snapshot: Dictionary, _progress: Dictionary, done: Array) -> bool:
	var a := atom.strip_edges()
	if a.begins_with("step_done:"):
		return done.has(a.substr("step_done:".length()))
	if a.begins_with("cue:"):
		var cue := a.substr("cue:".length())
		return bool(snapshot.get("cue_%s" % cue, false))
	if a.begins_with("minutes_since_begin>="):
		var need := float(a.substr("minutes_since_begin>=".length()))
		return float(snapshot.get("minutes_since_begin", 0.0)) >= need
	match a:
		"guide_active":
			return bool(snapshot.get("guide_active", false)) or env_tutorial() == 1
		"day_advanced_then_paused":
			return bool(snapshot.get("day_advanced_then_paused", false))
		"map_mode_changed":
			return bool(snapshot.get("map_mode_changed", false))
		"inspector_visible":
			return bool(snapshot.get("inspector_visible", false))
		"own_unit_card_visible":
			return bool(snapshot.get("own_unit_card_visible", false))
		"not_at_war_with_target":
			return not bool(snapshot.get("at_war_with_target", false)) and not bool(snapshot.get("at_war_any", false))
		"no_player_justify":
			return not bool(snapshot.get("player_has_justify", false))
		"player_has_justify_any":
			return bool(snapshot.get("player_has_justify", false))
		"already_at_war_or_justifying":
			return bool(snapshot.get("at_war_any", false)) or bool(snapshot.get("at_war_with_target", false)) or bool(snapshot.get("player_has_justify", false))
		"player_justify_ready_for_target":
			return bool(snapshot.get("player_justify_ready", false))
		"at_war_with_target":
			return bool(snapshot.get("at_war_with_target", false))
		"player_unit_adjacent_enemy":
			return bool(snapshot.get("player_unit_adjacent_enemy", false))
		"battle_started_player":
			return bool(snapshot.get("battle_started_player", false))
		"press_next":
			return bool(snapshot.get("press_next", false))
		"press_got_it":
			return bool(snapshot.get("press_got_it", false))
		_:
			return bool(snapshot.get(a, false))


static func string_ids(raw: Variant) -> Array:
	return _as_string_array(raw)


static func _as_string_array(raw: Variant) -> Array:
	var out: Array = []
	if raw is PackedStringArray:
		for s in raw:
			out.append(str(s))
		return out
	if raw is Array:
		for s in raw:
			out.append(str(s))
	return out
