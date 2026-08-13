# scripts/core/CampaignAlphaDomain.gd
## Pack B (G0.1) — first GameData domain extraction: Campaign Alpha / Stream α state helpers.
## GameData keeps public method names; this RefCounted owns pure state transitions.
class_name CampaignAlphaDomain
extends RefCounted

static func default_state() -> Dictionary:
	return {
		"max_expanded": 1,
		"max_actions": 8,
		"dead_n": 0,
		"last_recommended": "",
		"board_set": false,
		"recommend_set": false,
		"audit_set": false,
	}


static func apply_step(peace_state: Dictionary, step: String, product: Dictionary, province_id: int = 1) -> Dictionary:
	var st: Dictionary = {}
	if peace_state.has("campaign_alpha") and peace_state["campaign_alpha"] is Dictionary:
		st = (peace_state["campaign_alpha"] as Dictionary).duplicate(true)
	else:
		st = default_state()
	var s := step.strip_edges().to_lower().replace("campaign_alpha_", "")
	if s.begins_with("rec"):
		st["recommend_set"] = true
		s = "recommend"
	elif s.begins_with("aud") or s.begins_with("dead"):
		st["audit_set"] = true
		s = "audit"
	else:
		st["board_set"] = true
		st["max_expanded"] = 1
		s = "board"
	st["dead_n"] = int(product.get("dead_n", 0))
	st["max_actions"] = int(product.get("max_actions", 8))
	var rec: Dictionary = product.get("recommendation", {})
	if rec is Dictionary:
		st["last_recommended"] = str(rec.get("action_id", ""))
	peace_state["campaign_alpha"] = st.duplicate(true)
	var ticks := int(peace_state.get("campaign_alpha_tick_count", 0)) + 1
	peace_state["campaign_alpha_tick_count"] = ticks
	return {
		"ok": bool(product.get("dead_ok", true)),
		"live": true,
		"step": s,
		"province_id": province_id,
		"dead_n": int(st.get("dead_n", 0)),
		"max_expanded": int(st.get("max_expanded", 1)),
		"last_recommended": str(st.get("last_recommended", "")),
		"campaign_alpha_tick_count": ticks,
		"manager": "CampaignAlphaDomain",
	}
