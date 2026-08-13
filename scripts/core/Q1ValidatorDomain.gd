# scripts/core/Q1ValidatorDomain.gd
## G0.1 — q1_validator_primary package state.
class_name Q1ValidatorDomain
extends RefCounted

static func default_state() -> Dictionary:
	return {"applied": [], "majors_done": {}, "tick": 0, "last_live_api": "", "last_step": ""}


static func apply_primary_step(peace_state: Dictionary, step: String, live_api: String, major: String) -> Dictionary:
	var st: Dictionary = {}
	if peace_state.has("q1_validator_primary") and peace_state["q1_validator_primary"] is Dictionary:
		st = (peace_state["q1_validator_primary"] as Dictionary).duplicate(true)
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
	peace_state["q1_validator_primary"] = st.duplicate(true)
	var ticks := int(peace_state.get("q1_validator_primary_ticks", 0)) + 1
	peace_state["q1_validator_primary_ticks"] = ticks
	return {
		"ok": true, "live": true, "step": s, "major": major, "live_api": live_api,
		"applied_n": applied.size(), "q1_validator_primary_ticks": ticks, "manager": "Q1ValidatorDomain",
	}


static func majors_ok_count(peace_state: Dictionary) -> int:
	if not peace_state.has("q1_validator_primary") or not (peace_state["q1_validator_primary"] is Dictionary):
		return 0
	var md: Dictionary = (peace_state["q1_validator_primary"] as Dictionary).get("majors_done", {}) as Dictionary
	var n := 0
	for k in ["q1_primary_balance", "q1_primary_estimate", "q1_primary_sample", "q1_primary_honesty", "q1_primary_close"]:
		if int(md.get(k, 0)) > 0:
			n += 1
	return n
