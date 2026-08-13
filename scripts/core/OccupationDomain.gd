# scripts/core/OccupationDomain.gd
## G0.1 — Occupation primary package state extracted from GameData.
class_name OccupationDomain
extends RefCounted

static func default_state() -> Dictionary:
	return {
		"applied": [], "complete": false, "tick": 0,
		"mapmode": {"history": []}, "law": {"history": []}, "garrison": {"history": []},
		"pulse": {"history": []}, "close": {"history": []},
		"occupation_history": [], "majors_done": {}, "last_live_api": "", "last_step": "",
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
		for req in ["mapmode_surface", "set_law", "garrison", "resistance_compliance_pulse", "occupation_close"]:
			if not applied.has(req):
				complete = false
				break
	st["complete"] = complete
	peace_state["occupation_primary"] = st.duplicate(true)
	var ticks := int(peace_state.get("occupation_primary_ticks", 0)) + 1
	peace_state["occupation_primary_ticks"] = ticks
	return {
		"ok": true, "live": true, "step": s, "major": major, "live_api": live_api,
		"applied_n": applied.size(), "complete": complete, "occupation_primary_ticks": ticks,
		"manager": "OccupationDomain",
	}


static func majors_ok_count(peace_state: Dictionary) -> int:
	if not peace_state.has("occupation_primary") or not (peace_state["occupation_primary"] is Dictionary):
		return 0
	var md: Dictionary = (peace_state["occupation_primary"] as Dictionary).get("majors_done", {}) as Dictionary
	var n := 0
	for k in ["occupation_primary_mapmode", "occupation_primary_law", "occupation_primary_garrison", "occupation_primary_rc_pulse", "occupation_primary_close"]:
		if int(md.get(k, 0)) > 0:
			n += 1
	return n
