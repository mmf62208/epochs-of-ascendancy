# scripts/core/PeaceConferenceDomain.gd
## G0.1 — Peace conference primary package state extracted from GameData.
class_name PeaceConferenceDomain
extends RefCounted

static func default_state() -> Dictionary:
	return {
		"applied": [], "complete": false, "tick": 0,
		"open": {"history": []}, "claim": {"history": []}, "cede": {"history": []},
		"puppet": {"history": []}, "close": {"history": []},
		"peace_history": [], "majors_done": {}, "last_live_api": "", "last_step": "",
	}


static func commit_state(peace_state: Dictionary, st: Dictionary, step: String, live_api: String, major: String) -> Dictionary:
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
	var complete := applied.size() >= 5
	if complete:
		for req in ["open_conference", "claim_province", "cede_province", "puppet_tag", "close_conference"]:
			if not applied.has(req):
				complete = false
				break
	st["complete"] = complete
	peace_state["peace_conference_primary"] = st.duplicate(true)
	var ticks := int(peace_state.get("peace_conference_primary_ticks", 0)) + 1
	peace_state["peace_conference_primary_ticks"] = ticks
	return {
		"ok": true, "live": true, "step": s, "major": major, "live_api": live_api,
		"applied_n": applied.size(), "complete": complete, "peace_conference_primary_ticks": ticks,
		"manager": "PeaceConferenceDomain",
	}


static func majors_ok_count(peace_state: Dictionary) -> int:
	if not peace_state.has("peace_conference_primary") or not (peace_state["peace_conference_primary"] is Dictionary):
		return 0
	var md: Dictionary = (peace_state["peace_conference_primary"] as Dictionary).get("majors_done", {}) as Dictionary
	var n := 0
	for k in ["peace_primary_open", "peace_primary_claim", "peace_primary_cede", "peace_primary_puppet", "peace_primary_close"]:
		if int(md.get(k, 0)) > 0:
			n += 1
	return n
