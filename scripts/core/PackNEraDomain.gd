# scripts/core/PackNEraDomain.gd
## G0.1 — Pack N thin era primary package state.
class_name PackNEraDomain
extends RefCounted

static func default_state() -> Dictionary:
	return {"applied": [], "majors_done": {}, "tick": 0, "last_live_api": "", "last_step": "", "eras": []}


static func apply_primary_step(peace_state: Dictionary, step: String, live_api: String, major: String, era: int = 0) -> Dictionary:
	var st: Dictionary = {}
	if peace_state.has("pack_n_era_primary") and peace_state["pack_n_era_primary"] is Dictionary:
		st = (peace_state["pack_n_era_primary"] as Dictionary).duplicate(true)
	else:
		st = default_state()
	var s := step.strip_edges().to_lower()
	st["last_step"] = s
	st["last_live_api"] = live_api
	if era > 0:
		var eras: Array = (st.get("eras", []) as Array).duplicate() if st.get("eras") is Array else []
		if not eras.has(era):
			eras.append(era)
		st["eras"] = eras
	var applied: Array = (st.get("applied", []) as Array).duplicate() if st.get("applied") is Array else []
	if not applied.has(s):
		applied.append(s)
	st["applied"] = applied
	st["tick"] = int(st.get("tick", 0)) + 1
	var md: Dictionary = (st.get("majors_done", {}) as Dictionary).duplicate(true)
	if not major.is_empty():
		md[major] = int(md.get(major, 0)) + 1
	st["majors_done"] = md
	peace_state["pack_n_era_primary"] = st.duplicate(true)
	var ticks := int(peace_state.get("pack_n_era_primary_ticks", 0)) + 1
	peace_state["pack_n_era_primary_ticks"] = ticks
	return {
		"ok": true, "live": true, "step": s, "major": major, "live_api": live_api,
		"applied_n": applied.size(), "pack_n_era_primary_ticks": ticks,
		"era_n": (st.get("eras", []) as Array).size() if st.get("eras") is Array else 0,
		"manager": "PackNEraDomain",
	}


static func majors_ok_count(peace_state: Dictionary) -> int:
	if not peace_state.has("pack_n_era_primary") or not (peace_state["pack_n_era_primary"] is Dictionary):
		return 0
	var md: Dictionary = (peace_state["pack_n_era_primary"] as Dictionary).get("majors_done", {}) as Dictionary
	var n := 0
	for k in [
		"pne_primary_catalog",
		"pne_primary_era1936",
		"pne_primary_era1918",
		"pne_primary_equip",
		"pne_primary_close",
	]:
		if int(md.get(k, 0)) > 0:
			n += 1
	return n
