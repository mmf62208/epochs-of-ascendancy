# scripts/ui/PlayNextHook.gd
## One recommended next beat for the play-strip / map chip.
## War-loop first (stance / tomorrow), then unpause. Not Campaign Alpha leftovers.
class_name PlayNextHook
extends RefCounted


static func recommend(player_tag: String = "GER") -> Dictionary:
	var tag := player_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = "GER"
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("peek_last_land_aar"):
		var aar: Dictionary = BattleManager.peek_last_land_aar()
		if not aar.is_empty() and int(aar.get("next_pid", -1)) > 0:
			return {
				"ok": true,
				"action": "next_hex",
				"label": "Press %s next" % str(aar.get("next_place", "the next hex")),
				"hint": str(aar.get("line", "Take the next hex")),
				"fid": str(aar.get("fid", "")),
				"to_id": int(aar.get("next_pid", -1)),
				"source": "aar",
			}
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("get_open_land_battles"):
		var battles: Array = BattleManager.get_open_land_battles()
		for raw in battles:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var b: Dictionary = raw
			if str(b.get("att_tag", "")).to_upper() != tag:
				continue
			var hook := str(b.get("next_hook", ""))
			if hook.is_empty() and BattleManager.has_method("land_battle_next_hook"):
				hook = str(BattleManager.land_battle_next_hook(b))
			var action := "unpause"
			var low := hook.to_lower()
			if "arrives tomorrow" in low:
				action = "hold"
			elif "break tomorrow" in low or "one day from breaking" in low:
				action = "press"
			elif "river/fort" in low:
				action = "hold"
			return {
				"ok": true,
				"action": action,
				"label": _action_label(action),
				"hint": hook if not hook.is_empty() else "Open fight — Press or Hold",
				"fid": str(b.get("att_fid", "")),
				"to_id": int(b.get("to_id", -1)),
				"source": "land_battle",
			}
	var eta := 99
	if typeof(FormationMovement) != TYPE_NIL and FormationMovement.has_method("soonest_calendar_eta_to"):
		# Any incoming march for the player (dest unknown): scan via capital-ish 0 skip.
		pass
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_paused") and bool(TimeManager.is_paused()):
		return {
			"ok": true,
			"action": "unpause",
			"label": "Unpause a day",
			"hint": "Advance the clock — marches and fights tick",
			"fid": "",
			"to_id": -1,
			"source": "clock",
		}
	return {
		"ok": true,
		"action": "unpause",
		"label": "One more day",
		"hint": "Keep the clock running",
		"fid": "",
		"to_id": -1,
		"source": "idle",
	}


static func apply(rec: Dictionary = {}) -> Dictionary:
	var r: Dictionary = rec
	if r.is_empty():
		r = recommend()
	var action := str(r.get("action", "unpause"))
	var fid := str(r.get("fid", ""))
	if action == "next_hex" and typeof(BattleManager) != TYPE_NIL \
			and BattleManager.has_method("apply_last_land_aar_next"):
		var nx: Dictionary = BattleManager.apply_last_land_aar_next()
		return {
			"ok": bool(nx.get("ok", false)),
			"action": "next_hex",
			"summary": str(nx.get("summary", r.get("hint", "Next hex"))),
		}
	if action in ["press", "hold"] and typeof(BattleManager) != TYPE_NIL \
			and BattleManager.has_method("set_land_battle_stance") and not fid.is_empty():
		var st: Dictionary = BattleManager.set_land_battle_stance(fid, action)
		return {
			"ok": bool(st.get("ok", false)),
			"action": action,
			"summary": str(st.get("next_hook", r.get("hint", action))),
		}
	if action == "unpause" and typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(false)
		return {"ok": true, "action": "unpause", "summary": str(r.get("hint", "Unpause"))}
	return {"ok": false, "action": action, "summary": "Nothing to apply"}


static func _action_label(action: String) -> String:
	match action:
		"press":
			return "Press the front"
		"hold":
			return "Hold for tomorrow"
		"next_hex":
			return "Press the next hex"
		_:
			return "Unpause a day"
