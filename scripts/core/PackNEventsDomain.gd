# scripts/core/PackNEventsDomain.gd
## G0.1 — pack_n_events_primary package state.
class_name PackNEventsDomain
extends RefCounted

static func default_state() -> Dictionary:
	return {"applied": [], "majors_done": {}, "tick": 0, "last_live_api": "", "last_step": ""}


static func apply_primary_step(peace_state: Dictionary, step: String, live_api: String, major: String) -> Dictionary:
	var st: Dictionary = {}
	if peace_state.has("pack_n_events_primary") and peace_state["pack_n_events_primary"] is Dictionary:
		st = (peace_state["pack_n_events_primary"] as Dictionary).duplicate(true)
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
	peace_state["pack_n_events_primary"] = st.duplicate(true)
	var ticks := int(peace_state.get("pack_n_events_primary_ticks", 0)) + 1
	peace_state["pack_n_events_primary_ticks"] = ticks
	return {
		"ok": true, "live": true, "step": s, "major": major, "live_api": live_api,
		"applied_n": applied.size(), "pack_n_events_primary_ticks": ticks, "manager": "PackNEventsDomain",
	}


static func majors_ok_count(peace_state: Dictionary) -> int:
	if not peace_state.has("pack_n_events_primary") or not (peace_state["pack_n_events_primary"] is Dictionary):
		return 0
	var md: Dictionary = (peace_state["pack_n_events_primary"] as Dictionary).get("majors_done", {}) as Dictionary
	var n := 0
	for k in ["pnevt_primary_catalog", "pnevt_primary_path", "pnevt_primary_war_pick", "pnevt_primary_commit", "pnevt_primary_close"]:
		if int(md.get(k, 0)) > 0:
			n += 1
	return n
