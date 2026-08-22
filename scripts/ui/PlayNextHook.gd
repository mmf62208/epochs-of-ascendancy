# scripts/ui/PlayNextHook.gd
## One recommended next beat for the play-strip / map chip.
## War first, then organize-ready, dry fuel, steel shortage, completing
## research/focus. Empty sit-down shows the first-session WarLoop path.
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
	var choke_v: Variant = f.get("fleet_choke", {})
	if choke_v is Dictionary and int((choke_v as Dictionary).get("pid", 0)) > 0:
		var ch: Dictionary = choke_v as Dictionary
		var sentence := str(ch.get("sentence", "")).strip_edges()
		if sentence.is_empty():
			sentence = "Channel choke flagged"
		return {
			"ok": true,
			"action": "choke_flag",
			"label": sentence,
			"hint": sentence,
			"fid": str(ch.get("fid", "")),
			"to_id": int(ch.get("pid", -1)),
			"source": "choke",
		}
	var peace_pid := int(f.get("peace_pid", -1))
	if peace_pid > 0:
		return {
			"ok": true,
			"action": "settle_peace",
			"label": "Settle the peace",
			"hint": "Annex the captured province at the conference",
			"fid": str(f.get("aar_fid", "")),
			"to_id": peace_pid,
			"source": "peace",
			"winner": str(f.get("peace_winner", "")),
			"loser": str(f.get("peace_loser", "")),
		}
	var occ_v: Variant = f.get("occupation", {})
	if occ_v is Dictionary and int((occ_v as Dictionary).get("pid", 0)) > 0:
		var occ: Dictionary = occ_v as Dictionary
		var resist := float(occ.get("resistance", 0.0))
		var place := str(occ.get("place", "occupied land")).strip_edges()
		if place.is_empty():
			place = "occupied land"
		var occ_line := "Occupied %s · resistance %.0f%%" % [place, resist * 100.0]
		return {
			"ok": true,
			"action": "occupation_unrest",
			"label": occ_line,
			"hint": occ_line,
			"fid": "",
			"to_id": int(occ.get("pid", -1)),
			"source": "occupation",
		}
	var wpid := int(f.get("war_goal_pid", -1))
	if wpid > 0:
		if not bool(f.get("war_justified", false)):
			return {
				"ok": true,
				"action": "justify",
				"label": "Justify the war goal",
				"hint": "Justify a claim before declaring war",
				"fid": "",
				"to_id": wpid,
				"source": "war_goal",
			}
		if not bool(f.get("war_declared", false)):
			return {
				"ok": true,
				"action": "declare",
				"label": "Declare war",
				"hint": "War goal justified — declare",
				"fid": "",
				"to_id": wpid,
				"source": "war_goal",
			}
	if bool(f.get("any_open_battle", false)) or bool(f.get("has_open_battle", false)):
		return {
			"ok": true,
			"action": "unpause",
			"label": "Open fight",
			"hint": "A land battle is live — completing bars / fights outrank WarLoop copy",
			"fid": str(f.get("battle_fid", "")),
			"to_id": int(f.get("battle_to_id", -1)),
			"source": "land_battle",
		}
	return {
		"ok": true,
		"action": "show_war_loop",
		"label": "WarLoop · B Fronts · Ctrl+click",
		"hint": "First-session path: chip · B · G · Ctrl+click assault",
		"fid": "",
		"to_id": -1,
		"source": "first_session",
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
	if action == "shortage":
		return _open_living_surface("production", r)
	if action == "tech_done":
		return _open_living_surface("research", r)
	if action == "focus_done":
		return _open_living_surface("focus", r)
	if action == "show_war_loop":
		var tree := Engine.get_main_loop() as SceneTree
		var mr: Node = null
		if tree != null:
			mr = tree.get_first_node_in_group("map_renderer")
			if mr == null and tree.current_scene != null:
				mr = tree.current_scene.find_child("MapRenderer", true, false)
		if mr != null and mr.has_method("show_first_session_war_path"):
			var wp: Dictionary = mr.call("show_first_session_war_path")
			return {
				"ok": true,
				"action": "show_war_loop",
				"summary": str(wp.get("toast", r.get("hint", "WarLoop"))),
			}
		return {"ok": true, "action": "show_war_loop", "summary": str(r.get("hint", "WarLoop"))}
	if action == "justify" and typeof(GameData) != TYPE_NIL and GameData.has_method("apply_war_goal_justify"):
		var jpid := int(r.get("to_id", 1))
		var justified: Dictionary = GameData.apply_war_goal_justify(jpid)
		return {
			"ok": bool(justified.get("ok", false)),
			"action": "justify",
			"summary": str(justified.get("summary", r.get("hint", "Justify the war goal"))),
		}
	if action == "declare" and typeof(GameData) != TYPE_NIL and GameData.has_method("apply_war_goal_execute"):
		var dpid := int(r.get("to_id", 1))
		var declared: Dictionary = GameData.apply_war_goal_execute(dpid)
		return {
			"ok": bool(declared.get("ok", false)),
			"action": "declare",
			"summary": str(declared.get("summary", r.get("hint", "Declare war"))),
		}
	if action == "settle_peace" and typeof(GameData) != TYPE_NIL \
			and GameData.has_method("apply_peace_conference_settlement_live"):
		var pid := int(r.get("to_id", -1))
		var winner := str(r.get("winner", "")).strip_edges().to_upper()
		var loser := str(r.get("loser", "")).strip_edges().to_upper()
		if winner.is_empty():
			winner = "GER"
		if loser.is_empty():
			loser = "FRA"
		if pid > 0:
			var settled: Dictionary = GameData.apply_peace_conference_settlement_live(
				winner, loser, pid, true, false, 0.0, true
			)
			_show_occupation_overlay()
			return {
				"ok": bool(settled.get("ok", false)),
				"action": "settle_peace",
				"summary": str(settled.get("summary", "Peace annex applied")),
			}
	if action == "occupation_unrest":
		_show_occupation_overlay()
		return {
			"ok": true,
			"action": "occupation_unrest",
			"summary": str(r.get("hint", r.get("label", "Occupation unrest"))),
		}
	if action == "unpause" and typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(false)
		return {"ok": true, "action": "unpause", "summary": str(r.get("hint", "Unpause"))}
	return {"ok": false, "action": action, "summary": "Nothing to apply"}


## NEXT chip: open the living research / focus / production surface (not unpause-only).
## Headless has no TopInfoBar — still reports the same panel the F5 chip would open.
static func _open_living_surface(kind: String, rec: Dictionary) -> Dictionary:
	var k := kind.strip_edges().to_lower()
	if k == "shortage":
		k = "production"
	if k == "tech_done" or k == "technology":
		k = "research"
	if k == "focus_done":
		k = "focus"
	var ui_opened := false
	var tree := Engine.get_main_loop() as SceneTree
	var bar: Node = null
	if tree != null:
		bar = tree.get_first_node_in_group("top_info_bar")
	if bar != null and bar.has_method("open_living_surface"):
		var ui: Dictionary = bar.call("open_living_surface", k)
		ui_opened = bool(ui.get("ok", false))
	return {
		"ok": true,
		"action": str(rec.get("action", k)),
		"panel": k,
		"opened": k,
		"surface": k,
		"unpause_only": false,
		"ui_opened": ui_opened,
		"summary": "Open %s" % k,
	}


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
		"choke_flag":
			return "Channel choke flagged"
		"settle_peace":
			return "Settle the peace"
		"occupation_unrest":
			return "Occupation unrest"
		"justify":
			return "Justify the war goal"
		"declare":
			return "Declare war"
		"show_war_loop":
			return "WarLoop · B Fronts · Ctrl+click"
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
			facts["any_open_battle"] = true
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
	if ProductionManager != null:
		var raw = ProductionManager.get("national_stockpile")
		if raw is Dictionary:
			var st: Dictionary = raw
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
	facts["fleet_choke"] = _fleet_choke_row(tag)
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("peek_last_land_aar"):
		var peace_aar: Dictionary = BattleManager.peek_last_land_aar()
		if not peace_aar.is_empty():
			facts["peace_pid"] = int(peace_aar.get("peace_pid", -1))
			facts["peace_winner"] = str(peace_aar.get("peace_winner", tag))
			facts["peace_loser"] = str(peace_aar.get("peace_loser", ""))
	facts["occupation"] = _occupation_row(tag)
	var wg: Dictionary = _war_goal_row(tag)
	facts["war_goal_pid"] = int(wg.get("pid", -1))
	facts["war_justified"] = bool(wg.get("justified", false))
	facts["war_declared"] = bool(wg.get("declared", false))
	return facts


static func _show_occupation_overlay() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var mr: Node = null
	if tree != null:
		mr = tree.get_first_node_in_group("map_renderer")
		if mr == null and tree.current_scene != null:
			mr = tree.current_scene.find_child("MapRenderer", true, false)
	if mr != null and mr.has_method("set_occupation_overlay_visible"):
		mr.call("set_occupation_overlay_visible", true)
		if mr.get("_occupation_layer") != null:
			var layer: Object = mr.get("_occupation_layer")
			if layer != null and "include_non_contested_heatmap" in layer:
				layer.include_non_contested_heatmap = true
			if layer != null and layer.has_method("set_mapmode"):
				layer.call("set_mapmode", "resistance")


static func _occupation_row(tag: String) -> Dictionary:
	var empty := {}
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return empty
	# Known living theaters only — never walk the 3520 board.
	var pids: Array = [710739, 902598]
	var store: Dictionary = {}
	if typeof(GameData) != TYPE_NIL and GameData.get("peace_state") is Dictionary:
		var ps: Dictionary = GameData.peace_state
		if ps.get("occupation_province") is Dictionary:
			store = ps["occupation_province"]
	for raw in pids:
		var pid := int(raw)
		var p: Object = MapManager.get_province(pid)
		if p == null:
			continue
		var owner := str(p.get("owner_tag")).strip_edges().to_upper()
		var ctrl := str(p.get("controller_tag")).strip_edges().to_upper()
		var seeded := store.has(str(pid))
		var occupied := not owner.is_empty() and not ctrl.is_empty() and owner != ctrl
		if not occupied and not seeded:
			continue
		if ctrl != tag and owner != tag:
			continue
		var resist := 0.55
		if seeded and store[str(pid)] is Dictionary:
			resist = float((store[str(pid)] as Dictionary).get("resistance_level", resist))
		elif occupied and typeof(GameData) != TYPE_NIL and GameData.has_method("get_occupation_province_state"):
			var st: Dictionary = GameData.get_occupation_province_state(pid)
			resist = float(st.get("resistance_level", resist))
		var place := str(p.get("name")).strip_edges()
		if place.is_empty():
			place = "#%d" % pid
		return {"pid": pid, "resistance": resist, "place": place, "owner": owner, "controller": ctrl}
	return empty


static func _war_goal_row(tag: String) -> Dictionary:
	var out := {"pid": -1, "justified": false, "declared": false}
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_war_goal_state"):
		var st: Dictionary = GameData.get_war_goal_state()
		out["justified"] = bool(st.get("justified", false))
		out["declared"] = int(st.get("pushes", 0)) > 0
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return out
	var target := 710739 if tag == "GER" else (902598 if tag == "JAP" else -1)
	if target <= 0:
		return out
	var p: Object = MapManager.get_province(target)
	if p == null:
		return out
	var owner := str(p.get("owner_tag")).strip_edges().to_upper()
	if owner.is_empty() or owner == tag:
		return out
	out["pid"] = target
	return out


static func _fleet_choke_row(tag: String) -> Dictionary:
	var empty := {}
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return empty
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("has_strategic_chokepoint"):
		return empty
	var forms: Variant = LeaderManager.formations
	if typeof(forms) != TYPE_DICTIONARY:
		return empty
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
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft != "fleet" and ft != "task_force" and ft != "ship":
			continue
		var pid := int(f.get("stationed_province_id")) if "stationed_province_id" in f else -1
		if pid <= 0 or not MapManager.has_strategic_chokepoint(pid):
			continue
		var sentence := "Channel choke flagged"
		if MapManager.has_method("flag_naval_choke"):
			var fl: Dictionary = MapManager.flag_naval_choke(pid)
			if bool(fl.get("ok", false)):
				sentence = str(fl.get("sentence", sentence))
		return {
			"fid": str(f.get("formation_id")) if "formation_id" in f else str(fid),
			"pid": pid,
			"sentence": sentence,
		}
	return empty


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
	if ProductionManager != null:
		var raw = ProductionManager.get("national_stockpile")
		if raw is Dictionary:
			var st: Dictionary = raw
			facts["fuel_stock"] = float(st.get("fuel", 0.0))
			facts["oil_stock"] = float(st.get("oil", 0.0))
	var rec := rank_from_snapshot(facts)
	if str(rec.get("source", "")) != "fuel":
		return {}
	return rec


static func _recommend_shortage(tag: String) -> Dictionary:
	var facts: Dictionary = {"has_vehicle": _has_vehicle(tag)}
	if ProductionManager != null:
		var raw = ProductionManager.get("national_stockpile")
		if raw is Dictionary:
			var st: Dictionary = raw
			facts["steel_stock"] = float(st.get("steel", 99.0))
	var rec := rank_from_snapshot(facts)
	if str(rec.get("source", "")) != "industry":
		return {}
	return rec
