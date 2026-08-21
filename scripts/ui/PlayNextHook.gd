# scripts/ui/PlayNextHook.gd
## One recommended next beat for the play-strip / map chip.
## War first, then organize-ready, dry fuel, steel shortage, completing
## research/focus — idle unpause last.
class_name PlayNextHook
extends RefCounted


static func recommend(player_tag: String = "GER") -> Dictionary:
	return rank_from_snapshot(_gather_facts(player_tag))


## Same ranker as tools/map_generation/lib/play_next_hook_product.rank_next_beat.
static func rank_from_snapshot(facts: Dictionary = {}) -> Dictionary:
	var f: Dictionary = facts
	var aar_pid := int(f.get("aar_next_pid", -1))
	if aar_pid > 0:
		var place := str(f.get("aar_place", "")).strip_edges()
		if place.is_empty():
			place = "the next hex"
		return {
			"ok": true,
			"action": "next_hex",
			"label": "Press %s next" % place,
			"hint": str(f.get("aar_line", "Take the next hex")),
			"fid": str(f.get("aar_fid", "")),
			"to_id": aar_pid,
			"source": "aar",
		}
	var eco := str(f.get("aar_economy", "")).strip_edges()
	if not eco.is_empty():
		return {
			"ok": true,
			"action": "unpause",
			"label": eco.trim_suffix("."),
			"hint": str(f.get("aar_line", eco)),
			"fid": str(f.get("aar_fid", "")),
			"to_id": int(f.get("aar_from_id", -1)),
			"source": "aar",
		}
	var hook := str(f.get("battle_hook", ""))
	if not hook.is_empty() or bool(f.get("has_open_battle", false)):
		var action := "unpause"
		var low := hook.to_lower()
		if "arrives tomorrow" in low:
			action = "hold"
		elif "break tomorrow" in low or "one day from breaking" in low:
			action = "press"
		elif "river/fort" in low:
			action = "hold"
		elif bool(f.get("has_open_battle", false)):
			action = "press"
		return {
			"ok": true,
			"action": action,
			"label": _action_label(action),
			"hint": hook if not hook.is_empty() else "Open fight — Press or Hold",
			"fid": str(f.get("battle_fid", "")),
			"to_id": int(f.get("battle_to_id", -1)),
			"source": "land_battle",
		}
	for row in f.get("training", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if float(row.get("days_left", 99.0)) > 1.001:
			continue
		return {
			"ok": true,
			"action": "send_trained",
			"label": "Training ready tomorrow",
			"hint": "Division ready — send to the front",
			"fid": str(row.get("fid", "")),
			"to_id": int(row.get("to_id", -1)),
			"source": "organize",
		}
	var dry: Variant = f.get("dry_fuel", [])
	if typeof(dry) == TYPE_ARRAY and not (dry as Array).is_empty():
		var first: Dictionary = dry[0] if typeof(dry[0]) == TYPE_DICTIONARY else {}
		var fuel_stock := float(f.get("fuel_stock", 0.0)) + float(f.get("oil_stock", 0.0))
		var empty := fuel_stock <= 0.001
		return {
			"ok": true,
			"action": "refuel",
			"label": "Tanks dry" if empty else "Refuel tanks",
			"hint": "Empty fuel stock — take oil or develop a well" if empty else "National fuel can refill",
			"fid": str(first.get("fid", "")),
			"to_id": int(first.get("to_id", -1)),
			"source": "fuel",
		}
	var steel_v := 99.0
	if f.has("steel_stock") and f.get("steel_stock") != null:
		steel_v = float(f.get("steel_stock"))
	if steel_v < 1.0 and bool(f.get("has_vehicle", false)):
		return {
			"ok": true,
			"action": "shortage",
			"label": "Steel short — produce / develop",
			"hint": "TOE lines cannot pay steel",
			"fid": "",
			"to_id": -1,
			"source": "industry",
		}
	if _days_left(f, "research_days_left") <= 1.001:
		var rname := str(f.get("research_name", "")).strip_edges()
		return {
			"ok": true,
			"action": "tech_done",
			"label": "Research completes tomorrow",
			"hint": rname if not rname.is_empty() else "Research completes tomorrow",
			"fid": str(f.get("research_id", "")),
			"to_id": -1,
			"source": "research",
		}
	if _days_left(f, "focus_days_left") <= 1.001:
		var fname := str(f.get("focus_name", "")).strip_edges()
		return {
			"ok": true,
			"action": "focus_done",
			"label": "Focus completes tomorrow",
			"hint": fname if not fname.is_empty() else "Focus completes tomorrow",
			"fid": str(f.get("focus_id", "")),
			"to_id": -1,
			"source": "focus",
		}
	if bool(f.get("paused", false)):
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
	if action in ["tech_done", "focus_done"] and typeof(TimeManager) != TYPE_NIL \
			and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(false)
		return {"ok": true, "action": action, "summary": str(r.get("hint", r.get("label", action)))}
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
		"tech_done":
			return "Research completes tomorrow"
		"focus_done":
			return "Focus completes tomorrow"
		_:
			return "Unpause a day"


static func _days_left(facts: Dictionary, key: String) -> float:
	if not facts.has(key) or facts.get(key) == null:
		return 99.0
	return float(facts.get(key, 99.0))


static func _gather_facts(player_tag: String) -> Dictionary:
	var tag := player_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = "GER"
	var facts: Dictionary = {"player_tag": tag}
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("peek_last_land_aar"):
		var aar: Dictionary = BattleManager.peek_last_land_aar()
		if not aar.is_empty():
			facts["aar_next_pid"] = int(aar.get("next_pid", -1))
			facts["aar_place"] = str(aar.get("next_place", ""))
			facts["aar_line"] = str(aar.get("line", ""))
			facts["aar_economy"] = str(aar.get("economy", ""))
			facts["aar_fid"] = str(aar.get("fid", ""))
			facts["aar_from_id"] = int(aar.get("from_id", -1))
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
			facts["has_open_battle"] = true
			facts["battle_hook"] = hook
			facts["battle_fid"] = str(b.get("att_fid", ""))
			facts["battle_to_id"] = int(b.get("to_id", -1))
			break
	facts["training"] = _training_rows(tag)
	facts["dry_fuel"] = _dry_fuel_rows(tag)
	if typeof(ProductionManager) != TYPE_NIL and "national_stockpile" in ProductionManager:
		var st: Dictionary = ProductionManager.national_stockpile
		facts["steel_stock"] = float(st.get("steel", 99.0))
		facts["fuel_stock"] = float(st.get("fuel", 0.0))
		facts["oil_stock"] = float(st.get("oil", 0.0))
	facts["has_vehicle"] = _has_vehicle(tag)
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_paused"):
		facts["paused"] = bool(TimeManager.is_paused())
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("completing_snapshot"):
		var snap: Dictionary = TechnologyManager.completing_snapshot(tag)
		facts["research_days_left"] = float(snap.get("research_days_left", 99.0))
		facts["research_id"] = str(snap.get("tech_id", ""))
		facts["research_name"] = str(snap.get("name", ""))
		facts["focus_days_left"] = float(snap.get("focus_days_left", 99.0))
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_focus_content_state"):
		var foc: Dictionary = GameData.get_focus_content_state(tag)
		if foc.has("days_left") or foc.has("days_remaining"):
			facts["focus_days_left"] = float(foc.get("days_left", foc.get("days_remaining", 99.0)))
			facts["focus_id"] = str(foc.get("focus_id", ""))
			facts["focus_name"] = str(foc.get("focus_id", ""))
	if typeof(ResourceHarvestCalculator) != TYPE_NIL:
		var dleft := float(ResourceHarvestCalculator.develop_days_remaining())
		if dleft >= 0.0:
			facts["develop_days_left"] = dleft
	return facts


static func _training_days_left(formation: Object) -> float:
	if formation == null:
		return 99.0
	var need := 14.0
	if formation.has_meta("organize_days"):
		need = float(formation.get_meta("organize_days"))
	var prog := float(formation.get("training_progress")) if "training_progress" in formation else 0.0
	return maxf(0.0, need - prog)


static func _training_rows(tag: String) -> Array:
	var rows: Array = []
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return rows
	var forms: Variant = LeaderManager.formations
	if typeof(forms) != TYPE_DICTIONARY:
		return rows
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
		rows.append({
			"fid": str(f.get("formation_id")) if "formation_id" in f else str(fid),
			"days_left": _training_days_left(f),
			"to_id": int(f.get("stationed_province_id")) if "stationed_province_id" in f else -1,
		})
	return rows


static func _dry_fuel_rows(tag: String) -> Array:
	var rows: Array = []
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return rows
	var forms: Variant = LeaderManager.formations
	if typeof(forms) != TYPE_DICTIONARY:
		return rows
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
		rows.append({
			"fid": str(f.get("formation_id")) if "formation_id" in f else str(fid),
			"to_id": int(f.get("stationed_province_id")) if "stationed_province_id" in f else -1,
		})
	return rows


static func _has_vehicle(tag: String) -> bool:
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return false
	var forms: Variant = LeaderManager.formations
	if typeof(forms) != TYPE_DICTIONARY:
		return false
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
				return true
	return false


static func _recommend_organize(tag: String) -> Dictionary:
	var facts := {"training": _training_rows(tag)}
	var rec := rank_from_snapshot(facts)
	if str(rec.get("source", "")) != "organize":
		return {}
	return rec


static func _recommend_fuel(tag: String) -> Dictionary:
	var facts: Dictionary = {"dry_fuel": _dry_fuel_rows(tag)}
	if typeof(ProductionManager) != TYPE_NIL and "national_stockpile" in ProductionManager:
		var st: Dictionary = ProductionManager.national_stockpile
		facts["fuel_stock"] = float(st.get("fuel", 0.0))
		facts["oil_stock"] = float(st.get("oil", 0.0))
	var rec := rank_from_snapshot(facts)
	if str(rec.get("source", "")) != "fuel":
		return {}
	return rec


static func _recommend_shortage(tag: String) -> Dictionary:
	var facts: Dictionary = {"has_vehicle": _has_vehicle(tag)}
	if typeof(ProductionManager) != TYPE_NIL and "national_stockpile" in ProductionManager:
		var st: Dictionary = ProductionManager.national_stockpile
		facts["steel_stock"] = float(st.get("steel", 99.0))
	var rec := rank_from_snapshot(facts)
	if str(rec.get("source", "")) != "industry":
		return {}
	return rec
