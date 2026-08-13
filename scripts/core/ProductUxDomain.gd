# scripts/core/ProductUxDomain.gd
## G0.1 — Product UX primary package state extracted from GameData.
class_name ProductUxDomain
extends RefCounted

static func default_state() -> Dictionary:
	return {"applied": [], "majors_done": {}, "tick": 0, "last_live_api": "", "last_step": ""}


static func apply_primary_step(peace_state: Dictionary, step: String, live_api: String, major: String) -> Dictionary:
	var st: Dictionary = {}
	if peace_state.has("product_ux_primary") and peace_state["product_ux_primary"] is Dictionary:
		st = (peace_state["product_ux_primary"] as Dictionary).duplicate(true)
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
	peace_state["product_ux_primary"] = st.duplicate(true)
	var ticks := int(peace_state.get("product_ux_primary_ticks", 0)) + 1
	peace_state["product_ux_primary_ticks"] = ticks
	return {
		"ok": true, "live": true, "step": s, "major": major, "live_api": live_api,
		"applied_n": applied.size(), "product_ux_primary_ticks": ticks,
		"manager": "ProductUxDomain",
	}


static func majors_ok_count(peace_state: Dictionary) -> int:
	if not peace_state.has("product_ux_primary") or not (peace_state["product_ux_primary"] is Dictionary):
		return 0
	var md: Dictionary = (peace_state["product_ux_primary"] as Dictionary).get("majors_done", {}) as Dictionary
	var n := 0
	for k in ["ux_primary_compact", "ux_primary_chips", "ux_primary_hotkeys", "ux_primary_product", "ux_primary_close"]:
		if int(md.get(k, 0)) > 0:
			n += 1
	return n
