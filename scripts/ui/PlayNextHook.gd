# scripts/ui/PlayNextHook.gd
## One recommended next beat for the play-strip / map chip.
## War first, then organize-ready, dry fuel, steel shortage — idle unpause last.
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
		var eco := str(aar.get("economy", "")).strip_edges()
		if not eco.is_empty():
			return {
				"ok": true,
				"action": "unpause",
				"label": eco.trim_suffix("."),
				"hint": str(aar.get("line", eco)),
				"fid": str(aar.get("fid", "")),
				"to_id": int(aar.get("from_id", -1)),
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
	var org := _recommend_organize(tag)
	if not org.is_empty():
		return org
	var fuel := _recommend_fuel(tag)
	if not fuel.is_empty():
		return fuel
	var short := _recommend_shortage(tag)
	if not short.is_empty():
		return short
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
	if action == "refuel" and typeof(ProductionManager) != TYPE_NIL \
			and ProductionManager.has_method("refuel_formation_from_stockpile") and not fid.is_empty():
		var rf: Dictionary = ProductionManager.refuel_formation_from_stockpile(fid, 0.10)
		return {
			"ok": bool(rf.get("ok", false)),
			"action": "refuel",
			"summary": str(r.get("hint", "Refuel")),
		}
	if action == "send_trained" and typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(false)
		return {"ok": true, "action": "send_trained", "summary": str(r.get("hint", "Training ready"))}
	if action == "shortage" and typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(false)
		return {"ok": true, "action": "shortage", "summary": str(r.get("hint", "Shortage"))}
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
		"send_trained":
			return "Training ready tomorrow"
		"refuel":
			return "Refuel tanks"
		"shortage":
			return "Steel short — produce / develop"
		_:
			return "Unpause a day"


static func _training_days_left(formation: Object) -> float:
	if formation == null:
		return 99.0
	var need := 14.0
	if formation.has_meta("organize_days"):
		need = float(formation.get_meta("organize_days"))
	var prog := float(formation.get("training_progress")) if "training_progress" in formation else 0.0
	return maxf(0.0, need - prog)


static func _recommend_organize(tag: String) -> Dictionary:
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return {}
	var forms: Variant = LeaderManager.formations
	if typeof(forms) != TYPE_DICTIONARY:
		return {}
	var scanned := 0
	for fid in forms:
		if scanned >= 48:
			break
		scanned += 1
		var f: Object = (forms as Dictionary)[fid]
		if f == null:
			continue
		if str(f.get("country_tag")).strip_edges().to_upper() != tag:
			continue
		if not ("is_training" in f) or not bool(f.get("is_training")):
			continue
		if _training_days_left(f) > 1.001:
			continue
		return {
			"ok": true,
			"action": "send_trained",
			"label": "Training ready tomorrow",
			"hint": "Division ready — send to the front",
			"fid": str(f.get("formation_id")) if "formation_id" in f else str(fid),
			"to_id": int(f.get("stationed_province_id")) if "stationed_province_id" in f else -1,
			"source": "organize",
		}
	return {}


static func _recommend_fuel(tag: String) -> Dictionary:
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return {}
	var forms: Variant = LeaderManager.formations
	if typeof(forms) != TYPE_DICTIONARY:
		return {}
	var scanned := 0
	for fid in forms:
		if scanned >= 48:
			break
		scanned += 1
		var f: Object = (forms as Dictionary)[fid]
		if f == null:
			continue
		if str(f.get("country_tag")).strip_edges().to_upper() != tag:
			continue
		if "is_training" in f and bool(f.get("is_training")):
			continue
		var use := 0.0
		if typeof(LandCombatPower) != TYPE_NIL:
			var comp: Dictionary = LandCombatPower.composition_from_formation(f)
			use = float(comp.get("fuel_use", 0.0))
		if use <= 1e-9:
			continue
		var fl := 1.0
		if "fuel_level" in f:
			fl = float(f.get("fuel_level"))
		if fl >= 0.35:
			continue
		var stock_fuel := 0.0
		var stock_oil := 0.0
		if typeof(ProductionManager) != TYPE_NIL and "national_stockpile" in ProductionManager:
			var st: Dictionary = ProductionManager.national_stockpile
			stock_fuel = float(st.get("fuel", 0.0))
			stock_oil = float(st.get("oil", 0.0))
		var empty := stock_fuel + stock_oil <= 0.001
		return {
			"ok": true,
			"action": "refuel",
			"label": "Tanks dry" if empty else "Refuel tanks",
			"hint": "Empty fuel stock — take oil or develop a well" if empty else "National fuel can refill",
			"fid": str(f.get("formation_id")) if "formation_id" in f else str(fid),
			"to_id": int(f.get("stationed_province_id")) if "stationed_province_id" in f else -1,
			"source": "fuel",
		}
	return {}


static func _recommend_shortage(tag: String) -> Dictionary:
	if typeof(ProductionManager) == TYPE_NIL or not ("national_stockpile" in ProductionManager):
		return {}
	var st: Dictionary = ProductionManager.national_stockpile
	if float(st.get("steel", 99.0)) >= 1.0:
		return {}
	var has_vehicle := false
	if typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
		var forms: Variant = LeaderManager.formations
		if typeof(forms) == TYPE_DICTIONARY:
			var n := 0
			for fid in forms:
				if n >= 24:
					break
				n += 1
				var f: Object = (forms as Dictionary)[fid]
				if f == null:
					continue
				if str(f.get("country_tag")).strip_edges().to_upper() != tag:
					continue
				if typeof(LandCombatPower) != TYPE_NIL:
					var comp: Dictionary = LandCombatPower.composition_from_formation(f)
					if float(comp.get("fuel_use", 0.0)) > 1e-9:
						has_vehicle = true
						break
	if not has_vehicle:
		return {}
	return {
		"ok": true,
		"action": "shortage",
		"label": "Steel short — produce / develop",
		"hint": "TOE lines cannot pay steel",
		"fid": "",
		"to_id": -1,
		"source": "industry",
	}
