# scripts/core/AiCredibleDomain.gd
## Killswitch, tuning, trace, and the one daily credible-AI hook.
## Persistent memory is GameData.peace_state["ai_credible_state"] only,
## so SR1 can whitelist that key. Derived from world state + day where it can be.
class_name AiCredibleDomain
extends RefCounted

const KILL_ENV := "EOA_AI_CREDIBLE"
const GOALS_PATH := "res://data/scenarios/ai_goals_1936.json"
const STATE_KEY := "ai_credible_state"
const HISTORICAL_MIN_DAY := 180

static var _goals: Dictionary = {}
static var _goals_loaded: bool = false
static var _tuning: Dictionary = {}


static func enabled() -> bool:
	return OS.get_environment(KILL_ENV).strip_edges() != "0"


static func reset_for_test() -> void:
	_tuning = {}
	_goals_loaded = false
	_goals = {}
	AiWarPlannerDomain.reset_cache()
	if typeof(GameData) == TYPE_NIL:
		return
	GameData.peace_state.erase(STATE_KEY)


static func set_tuning(overrides: Dictionary) -> void:
	_tuning = overrides.duplicate(true)


static func tuning() -> Dictionary:
	var merged: Dictionary = _file_goals().duplicate(true)
	for k in _tuning.keys():
		merged[str(k)] = _tuning[k]
	return merged


static func tune_int(key: String, default_value: int) -> int:
	return int(tuning().get(key, default_value))


static func tune_float(key: String, default_value: float) -> float:
	return float(tuning().get(key, default_value))


static func majors() -> Array:
	var raw: Variant = tuning().get("majors", [])
	if raw is Array and not (raw as Array).is_empty():
		var out: Array = []
		for item in raw:
			var tag := str(item).strip_edges().to_upper()
			if not tag.is_empty():
				out.append(tag)
		out.sort()
		return out
	return ["ENG", "FRA", "GER", "ITA", "JAP", "POL", "SOV", "USA"]


static func goals_for(tag: String) -> Dictionary:
	var all: Variant = tuning().get("goals", {})
	if not (all is Dictionary):
		return {}
	var row: Variant = (all as Dictionary).get(tag.strip_edges().to_upper(), {})
	return (row as Dictionary).duplicate(true) if row is Dictionary else {}


static func player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var t := str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
		if not t.is_empty():
			return t
	return "GER"


static func state() -> Dictionary:
	if typeof(GameData) == TYPE_NIL:
		return {}
	var raw: Variant = GameData.peace_state.get(STATE_KEY, {})
	if not (raw is Dictionary):
		raw = {}
	var st: Dictionary = raw
	for key in [
		"last_research_day", "last_production_day", "seen_day", "axes",
		"threatened_since", "quiet", "bias", "air", "declined", "counters",
	]:
		if not (st.get(key) is Dictionary):
			st[key] = {}
	if not (st.get("trace") is Array):
		st["trace"] = []
	GameData.peace_state[STATE_KEY] = st
	return st


static func trace_line(line: String) -> void:
	var st := state()
	if st.is_empty() and typeof(GameData) == TYPE_NIL:
		return
	var rows: Array = st.get("trace", []) as Array
	rows.append(line)
	if rows.size() > 8000:
		var trimmed: Array = []
		var start := rows.size() - 4000
		for i in range(start, rows.size()):
			trimmed.append(rows[i])
		rows = trimmed
	st["trace"] = rows


static func trace_text() -> String:
	var rows: Variant = state().get("trace", [])
	var parts: PackedStringArray = PackedStringArray()
	if rows is Array:
		for r in rows:
			parts.append(str(r))
	return "\n".join(parts)


static func counter_add(key: String, amount: int = 1) -> void:
	var st := state()
	var counters: Dictionary = st.get("counters", {}) as Dictionary
	counters[key] = int(counters.get(key, 0)) + amount
	st["counters"] = counters


static func counter_get(key: String) -> int:
	var counters: Variant = state().get("counters", {})
	if counters is Dictionary:
		return int((counters as Dictionary).get(key, 0))
	return 0


static func player_offer() -> Dictionary:
	var raw: Variant = state().get("player_offer", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


static func accept_player_offer() -> Dictionary:
	var offer := player_offer()
	if offer.is_empty():
		return {"ok": false, "reason": "no offer"}
	var res: Dictionary = {}
	if typeof(WarStateDomain) != TYPE_NIL:
		res = WarStateDomain.make_peace(str(offer.get("a", "")), str(offer.get("b", "")), "ai_peace_accept")
	var st := state()
	st.erase("player_offer")
	trace_line(
		"PEACE day=%d a=%s b=%s reason=player_accept ok=%s"
		% [int(offer.get("day", 0)), str(offer.get("a", "")), str(offer.get("b", "")), str(bool(res.get("ok", false)))]
	)
	return res


static func decline_player_offer() -> Dictionary:
	var offer := player_offer()
	if offer.is_empty():
		return {"ok": false, "reason": "no offer"}
	var st := state()
	var declined: Dictionary = st.get("declined", {}) as Dictionary
	var key := "%s|%s" % [str(offer.get("a", "")), str(offer.get("b", ""))]
	declined[key] = int(offer.get("day", 0))
	st["declined"] = declined
	st.erase("player_offer")
	trace_line("PEACE_DECLINE day=%d a=%s b=%s" % [int(offer.get("day", 0)), str(offer.get("a", "")), str(offer.get("b", ""))])
	return {"ok": true, "declined": true}


static func clear_player_offer() -> void:
	state().erase("player_offer")


static func tick_day(day_index: int) -> Dictionary:
	if not enabled():
		return {"ok": true, "skipped": true, "reason": "killswitch"}
	var day := int(day_index)
	var defence: Dictionary = AiDefenceDomain.tick(day)
	var border: Dictionary = AiBorderFillDomain.tick(day)
	var economy: Dictionary = AiEconomyDomain.tick(day)
	var peace: Dictionary = AiWarPlannerDomain.tick_peace(day)
	var front: Dictionary = AiFrontPlanDomain.tick(day)
	return {
		"ok": true,
		"skipped": false,
		"day": day,
		"defence": defence,
		"border": border,
		"economy": economy,
		"peace": peace,
		"front": front,
	}


static func _file_goals() -> Dictionary:
	if _goals_loaded:
		return _goals
	_goals_loaded = true
	_goals = _defaults()
	if not FileAccess.file_exists(GOALS_PATH):
		return _goals
	var f := FileAccess.open(GOALS_PATH, FileAccess.READ)
	if f == null:
		return _goals
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var loaded: Dictionary = parsed
		for k in loaded.keys():
			_goals[str(k)] = loaded[k]
	return _goals


static func _defaults() -> Dictionary:
	return {
		"majors": ["ENG", "FRA", "GER", "ITA", "JAP", "POL", "SOV", "USA"],
		"goals": {},
		"losing_ratio": 1.05,
		"losing_progress": 0.15,
		"second_front_ratio": 2.25,
		"peace_loss_fraction": 0.35,
		"peace_threatened_ratio": 0.5,
		"peace_threatened_days": 60,
		"peace_goal_met_progress": 0.35,
		"peace_stalemate_days": 730,
		"peace_quiet_days": 45,
		"peace_reoffer_days": 14,
		"defence_marches_per_day": 2,
		"defence_path_probes": 6,
		"at_war_starts_per_day": 2,
		"axis_stable_days": 10,
		"axis_scan_cap": 32,
		"air_assign_within_days": 7,
		"research_starts_per_day": 2,
		"research_scan_cap": 32,
		"production_idle_days": 7,
	}
