# scripts/core/TutorialSessionDomain.gd
## G0.1 — Tutorial / first-session primary state transitions extracted from GameData.
## GameData keeps public method names; this RefCounted owns package state.
class_name TutorialSessionDomain
extends RefCounted

static func default_state() -> Dictionary:
	return {
		"applied": [],
		"majors_done": {},
		"tick": 0,
		"brief_done": false,
		"guide_done": false,
		"checkpoint_done": false,
		"last_live_api": "",
	}


static func apply_primary_step(peace_state: Dictionary, step: String, live_api: String, major: String) -> Dictionary:
	var st: Dictionary = {}
	if peace_state.has("tutorial_first_session_primary") and peace_state["tutorial_first_session_primary"] is Dictionary:
		st = (peace_state["tutorial_first_session_primary"] as Dictionary).duplicate(true)
	else:
		st = default_state()
	var s := step.strip_edges().to_lower()
	if s.contains("brief"):
		st["brief_done"] = true
	elif s.contains("guide"):
		st["guide_done"] = true
	elif s.contains("checkpoint"):
		st["checkpoint_done"] = true
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
	peace_state["tutorial_first_session_primary"] = st.duplicate(true)
	var ticks := int(peace_state.get("tutorial_first_session_primary_ticks", 0)) + 1
	peace_state["tutorial_first_session_primary_ticks"] = ticks
	return {
		"ok": true,
		"live": true,
		"step": s,
		"major": major,
		"live_api": live_api,
		"applied_n": applied.size(),
		"tutorial_first_session_primary_ticks": ticks,
		"manager": "TutorialSessionDomain",
	}


static func majors_ok_count(peace_state: Dictionary) -> int:
	if not peace_state.has("tutorial_first_session_primary") or not (peace_state["tutorial_first_session_primary"] is Dictionary):
		return 0
	var md: Dictionary = (peace_state["tutorial_first_session_primary"] as Dictionary).get("majors_done", {}) as Dictionary
	var n := 0
	for k in ["tutorial_primary_brief", "tutorial_primary_guide", "tutorial_primary_checkpoint", "tutorial_primary_product", "tutorial_primary_close"]:
		if int(md.get(k, 0)) > 0:
			n += 1
	return n
