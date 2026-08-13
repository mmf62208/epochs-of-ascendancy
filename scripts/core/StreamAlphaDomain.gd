# scripts/core/StreamAlphaDomain.gd
## G0.1 — Stream α primary package state extracted from GameData.
class_name StreamAlphaDomain
extends RefCounted

const STEP_N := 14

static func default_state() -> Dictionary:
	return {
		"applied": [],
		"complete": false,
		"tick": 0,
		"combat": {"phase": "idle", "ribbon": false, "history": []},
		"medium": {"scanned": false, "horizon_d": 0, "units_projected": 0, "history": []},
		"save": {"slots": [], "resume_slot": "", "checkpoint": false, "history": []},
		"hh": {"faction": "", "months": 0, "trail": [], "history": []},
		"majors_done": {},
		"last_live_api": "",
		"last_step": "",
	}


static func apply_primary_step(peace_state: Dictionary, step: String, live_api: String, major: String) -> Dictionary:
	var st: Dictionary = {}
	if peace_state.has("stream_alpha_primary") and peace_state["stream_alpha_primary"] is Dictionary:
		st = (peace_state["stream_alpha_primary"] as Dictionary).duplicate(true)
	else:
		st = default_state()
	var s := step.strip_edges().to_lower()
	st["last_step"] = s
	st["last_live_api"] = live_api
	var applied: Array = (st.get("applied", []) as Array).duplicate() if st.get("applied") is Array else []
	if not applied.has(s):
		applied.append(s)
	st["applied"] = applied
	st["tick"] = int(st.get("tick", 0)) + 1
	var md: Dictionary = (st.get("majors_done", {}) as Dictionary).duplicate(true)
	if not major.is_empty():
		md[major] = int(md.get(major, 0)) + 1
	st["majors_done"] = md
	var complete := applied.size() >= STEP_N
	st["complete"] = complete
	peace_state["stream_alpha_primary"] = st.duplicate(true)
	var ticks := int(peace_state.get("stream_alpha_primary_ticks", 0)) + 1
	peace_state["stream_alpha_primary_ticks"] = ticks
	return {
		"ok": true, "live": true, "step": s, "major": major, "live_api": live_api,
		"applied_n": applied.size(), "complete": complete, "stream_alpha_primary_ticks": ticks,
		"manager": "StreamAlphaDomain",
	}


static func majors_ok_count(peace_state: Dictionary) -> int:
	if not peace_state.has("stream_alpha_primary") or not (peace_state["stream_alpha_primary"] is Dictionary):
		return 0
	var md: Dictionary = (peace_state["stream_alpha_primary"] as Dictionary).get("majors_done", {}) as Dictionary
	var n := 0
	for k in ["combat_primary_ribbon", "oob_primary_honesty", "save_primary_browser", "hh_primary_agenda"]:
		if int(md.get(k, 0)) > 0:
			n += 1
	return n
