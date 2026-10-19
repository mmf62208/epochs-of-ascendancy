# scripts/core/AiWarPlannerDomain.gd
## Scored justify / declare guards and AI peace. Uses WarStateDomain's
## justify → declare and make_peace APIs. No RNG. Ties break on the tag string.
class_name AiWarPlannerDomain
extends RefCounted

static var _cache_day: int = -999999
static var _cache: Dictionary = {}


static func reset_cache() -> void:
	_cache_day = -999999
	_cache = {}


static func strength(tag: String, day: int) -> float:
	if day != _cache_day:
		_cache = {}
		_cache_day = day
	var t := tag.strip_edges().to_upper()
	if _cache.has(t):
		return float(_cache[t])
	var v := 1.0
	if typeof(WarStateDomain) != TYPE_NIL:
		v = float(WarStateDomain.military_strength(t))
	_cache[t] = v
	return v


static func pick_target(
	tag: String,
	player: String,
	may_player: bool,
	min_ratio: float,
	day: int,
) -> Dictionary:
	var attacker := tag.strip_edges().to_upper()
	var blocked := _existing_war_block(attacker, day)
	if bool(blocked.get("blocking", false)):
		return {
			"target": "",
			"reason": "losing_war",
			"ratio": float(blocked.get("ratio", 0.0)),
			"score": 0.0,
			"terms": "losing ratio=%.3f progress=%.3f" % [float(blocked.get("ratio", 0.0)), float(blocked.get("progress", 0.0))],
		}
	var goals := AiCredibleDomain.goals_for(attacker)
	var counts := _neighbour_counts(attacker)
	var foes: Array = counts.keys()
	foes.sort()
	var best_target := ""
	var best_score := -1.0e12
	var best := {}
	var mine := strength(attacker, day)
	var aggr := 0.5
	if typeof(LandBattleAi) != TYPE_NIL:
		aggr = float(LandBattleAi.personality_aggression(attacker))
	var wars := 0
	if typeof(WarStateDomain) != TYPE_NIL:
		wars = WarStateDomain.war_count(attacker)
	for foe_v in foes:
		var foe := str(foe_v)
		var row := _evaluate_target(attacker, foe, player, may_player, min_ratio, day, goals, mine, int(counts[foe]), wars)
		if str(row.get("target", "")).is_empty():
			continue
		var score := float(row.get("score", 0.0))
		if best_target.is_empty() or score > best_score + 0.0000001 or (absf(score - best_score) <= 0.0000001 and foe < best_target):
			best_target = foe
			best_score = score
			best = row
			best["aggression"] = aggr
	if best_target.is_empty():
		return {"target": "", "reason": "none", "score": 0.0, "terms": ""}
	best["terms"] = _terms(best)
	return best


static func still_valid(attacker: String, defender: String, day: int, min_ratio: float) -> Dictionary:
	var a := attacker.strip_edges().to_upper()
	var d := defender.strip_edges().to_upper()
	var player := AiCredibleDomain.player_tag()
	var may := true
	if typeof(WarStateDomain) != TYPE_NIL:
		may = bool(WarStateDomain.rules().get("ai_may_declare_on_player", true))
	var goals := AiCredibleDomain.goals_for(a)
	var counts := _neighbour_counts(a)
	if not counts.has(d):
		return {"ok": false, "reason": "not_neighbour"}
	var wars := 0
	if typeof(WarStateDomain) != TYPE_NIL:
		wars = WarStateDomain.war_count(a)
	var blocked := _existing_war_block(a, day)
	if bool(blocked.get("blocking", false)):
		return {"ok": false, "reason": "losing_war", "ratio": float(blocked.get("ratio", 0.0))}
	return _evaluate_target(a, d, player, may, min_ratio, day, goals, strength(a, day), int(counts[d]), wars)


static func cancel_stale(day: int) -> Array:
	var events: Array = []
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return events
	var min_ratio := float(WarStateDomain.rules().get("ai_declare_min_ratio", 1.5))
	var rows: Array = WarStateDomain.justify_rows()
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		if str(row.get("kind", "")) == "player":
			continue
		var attacker := str(row.get("attacker", "")).strip_edges().to_upper()
		var defender := str(row.get("defender", "")).strip_edges().to_upper()
		if attacker.is_empty() or defender.is_empty():
			continue
		if WarStateDomain.is_human_nation(attacker):
			continue
		var verdict := still_valid(attacker, defender, day, min_ratio)
		if bool(verdict.get("ok", false)) and not str(verdict.get("target", "")).is_empty():
			continue
		var why := str(verdict.get("reason", "stale"))
		var res: Dictionary = WarStateDomain.cancel_ai_justify(attacker, defender, why, day)
		if not bool(res.get("ok", false)):
			continue
		var line := "CANCEL day=%d att=%s def=%s reason=%s" % [day, attacker, defender, why]
		print("AiCredible: cancel %s -> %s day=%d reason=%s" % [attacker, defender, day, why])
		AiCredibleDomain.trace_line(line)
		events.append({"action": "cancel", "attacker": attacker, "defender": defender, "day": day, "reason": why})
	return events


static func tick_peace(day: int) -> Dictionary:
	var out := {"offers": 0, "peaces": 0, "skipped": false}
	if not AiCredibleDomain.enabled():
		out["skipped"] = true
		return out
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled() or not WarStateDomain.any_war():
		return out
	var rows: Array = WarStateDomain.war_rows()
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var a := str(row.get("a", "")).strip_edges().to_upper()
		var b := str(row.get("b", "")).strip_edges().to_upper()
		if a.is_empty() or b.is_empty():
			continue
		if not WarStateDomain.is_at_war(a, b):
			continue
		var loser := _loser_of(a, b, day)
		if str(loser.get("tag", "")).is_empty():
			_clear_quiet("%s|%s" % [a, b])
			continue
		out["offers"] = int(out["offers"]) + 1
		var pair := "%s|%s" % [a, b]
		var progress := float(loser.get("progress", 0.0))
		var quiet := _quiet_days(pair, day, progress)
		var age := maxi(0, day - int(row.get("start_day", day)))
		var goal_met := progress + 0.0000001 >= AiCredibleDomain.tune_float("peace_goal_met_progress", 0.35)
		var stalemate := age >= AiCredibleDomain.tune_int("peace_stalemate_days", 730)
		var quiet_need := AiCredibleDomain.tune_int("peace_quiet_days", 45)
		var quiet_ok := quiet_need <= 0 or quiet >= quiet_need
		var accept := quiet_ok and (goal_met or stalemate)
		var human := WarStateDomain.is_human_nation(a) or WarStateDomain.is_human_nation(b)
		var terms := "loser=%s progress=%.4f ratio=%.3f quiet=%d age=%d goal=%s" % [
			str(loser.get("tag", "")), progress, float(loser.get("ratio", 0.0)), quiet, age, str(goal_met),
		]
		if human:
			if _declined_recent(pair, day):
				continue
			_store_player_offer(a, b, day, terms, str(loser.get("reason", "")))
			continue
		if not accept:
			continue
		var res: Dictionary = WarStateDomain.make_peace(a, b, "ai_peace")
		if bool(res.get("ok", false)):
			out["peaces"] = int(out["peaces"]) + 1
			var line := "PEACE day=%d a=%s b=%s reason=ai_peace %s" % [day, a, b, terms]
			print("AiCredible: peace %s-%s day=%d %s" % [a, b, day, terms])
			AiCredibleDomain.trace_line(line)
			_clear_quiet(pair)
	return out


static func _evaluate_target(
	attacker: String,
	foe: String,
	player: String,
	may_player: bool,
	min_ratio: float,
	day: int,
	goals: Dictionary,
	mine: float,
	border_n: int,
	wars: int,
) -> Dictionary:
	if foe == player and not may_player:
		return {"target": "", "reason": "player_blocked"}
	if typeof(WarStateDomain) != TYPE_NIL:
		if WarStateDomain.is_at_war(attacker, foe) or WarStateDomain.in_truce(attacker, foe) or WarStateDomain.are_allied(attacker, foe):
			return {"target": "", "reason": "blocked_pair"}
	var goal := _goal_row(goals, foe)
	var listed_only := bool(goals.get("offensive_only_listed", str(goals.get("posture", "defensive")) == "defensive"))
	var goal_w := 0.0
	if not goal.is_empty() and _goal_applies(goal, day):
		goal_w = float(goal.get("weight", 0.0))
	if listed_only and goal_w <= 0.0:
		return {"target": "", "reason": "not_a_goal"}
	if not goal.is_empty() and not _goal_applies(goal, day):
		return {"target": "", "reason": "goal_day"}
	var coal := _coalition_strength(attacker, foe, day)
	var ratio := mine / maxf(coal, 0.0001)
	var need := min_ratio
	if not goal.is_empty():
		need = maxf(need, float(goal.get("min_strength_ratio", min_ratio)))
	if ratio + 0.0000001 < need:
		return {"target": "", "reason": "ratio", "ratio": ratio, "coalition": coal}
	if bool(goals.get("no_stronger_major", false)) and _is_major(foe) and strength(foe, day) > mine:
		return {"target": "", "reason": "stronger_major", "ratio": ratio}
	if wars >= 1:
		var margin := AiCredibleDomain.tune_float("second_front_ratio", 2.25)
		if ratio + 0.0000001 < margin:
			return {"target": "", "reason": "second_front", "ratio": ratio}
	var aggr := 0.5
	if typeof(LandBattleAi) != TYPE_NIL:
		aggr = float(LandBattleAi.personality_aggression(attacker))
	var score := goal_w * 10.0 + minf(ratio, 4.0) * 0.35 + float(border_n) * 0.02 + aggr
	return {
		"ok": true,
		"target": foe,
		"reason": "scored",
		"score": score,
		"ratio": ratio,
		"coalition": coal,
		"mine": mine,
		"goal": goal_w,
		"border": border_n,
		"aggression": aggr,
		"second": wars,
	}


static func _existing_war_block(tag: String, day: int) -> Dictionary:
	if typeof(WarStateDomain) == TYPE_NIL:
		return {"blocking": false, "ratio": 99.0, "progress": 0.0}
	var enemies: Array = WarStateDomain.enemies_of(tag)
	if enemies.is_empty():
		return {"blocking": false, "ratio": 99.0, "progress": 0.0}
	var mine := strength(tag, day)
	var worst := 99.0
	for e in enemies:
		var r := mine / maxf(strength(str(e), day), 0.0001)
		if r < worst:
			worst = r
	var prog := 0.0
	if typeof(CapitulationDomain) != TYPE_NIL:
		prog = float(CapitulationDomain.progress(tag))
	var losing := worst + 0.0000001 < AiCredibleDomain.tune_float("losing_ratio", 1.05)
	losing = losing or prog + 0.0000001 >= AiCredibleDomain.tune_float("losing_progress", 0.15)
	return {"blocking": losing, "ratio": worst, "progress": prog}


static func _coalition_strength(attacker: String, defender: String, day: int) -> float:
	var total := strength(defender, day)
	var seen: Dictionary = {}
	for raw in _backers(defender):
		var x := str(raw).strip_edges().to_upper()
		if x.is_empty() or x == attacker or x == defender or seen.has(x):
			continue
		seen[x] = true
		total += strength(x, day)
	return total


static func _backers(defender: String) -> Array:
	var found: Dictionary = {}
	if typeof(RelationsManager) == TYPE_NIL or not RelationsManager.has_method("is_formal_ally_or_guaranteed"):
		return []
	var pool: Array = AiCredibleDomain.majors()
	if typeof(WarStateDomain) != TYPE_NIL:
		for n in WarStateDomain.relation_tags():
			pool.append(str(n))
	for raw in pool:
		var x := str(raw).strip_edges().to_upper()
		if x.is_empty() or x == defender or found.has(x):
			continue
		if bool(RelationsManager.is_formal_ally_or_guaranteed(defender, x)):
			found[x] = true
	var keys: Array = found.keys()
	keys.sort()
	return keys


static func _neighbour_counts(tag: String) -> Dictionary:
	var counts: Dictionary = {}
	var t := tag.strip_edges().to_upper()
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_provinces_by_owner"):
		return counts
	for pid_v in MapManager.get_provinces_by_owner(t):
		for nid_v in MapManager.get_adjacent_provinces(int(pid_v), true):
			var n: Province = MapManager.get_province(int(nid_v))
			if n == null or bool(n.is_sea):
				continue
			var ot := str(n.owner_tag).strip_edges().to_upper()
			if ot.is_empty() or ot == t:
				continue
			counts[ot] = int(counts.get(ot, 0)) + 1
	return counts


static func _goal_row(goals: Dictionary, foe: String) -> Dictionary:
	var targets: Variant = goals.get("targets", [])
	if not (targets is Array):
		return {}
	for raw in targets:
		if raw is Dictionary and str((raw as Dictionary).get("tag", "")).strip_edges().to_upper() == foe:
			return raw
	return {}


static func _goal_applies(row: Dictionary, day: int) -> bool:
	if row.is_empty():
		return false
	var gate := int(row.get("min_day", 0))
	if gate <= 0 or day >= gate:
		return true
	var rule_min := AiCredibleDomain.HISTORICAL_MIN_DAY
	if typeof(WarStateDomain) != TYPE_NIL:
		rule_min = int(WarStateDomain.rules().get("ai_declare_min_day", AiCredibleDomain.HISTORICAL_MIN_DAY))
	# A test that pulls the campaign clock earlier than 1936's 180-day floor
	# also lifts the goal calendar, so CL1's day-0 JAP–CHI golden still holds.
	if rule_min < AiCredibleDomain.HISTORICAL_MIN_DAY:
		return true
	return false


static func _is_major(tag: String) -> bool:
	if typeof(WarStateDomain) == TYPE_NIL:
		return false
	var majors: Variant = WarStateDomain.rules().get("scenario_majors", [])
	return majors is Array and (majors as Array).has(tag)


static func _loser_of(a: String, b: String, day: int) -> Dictionary:
	var la := _is_losing_war(a, b, day)
	var lb := _is_losing_war(b, a, day)
	if bool(la.get("losing", false)) and not bool(lb.get("losing", false)):
		la["tag"] = a
		return la
	if bool(lb.get("losing", false)) and not bool(la.get("losing", false)):
		lb["tag"] = b
		return lb
	if bool(la.get("losing", false)) and bool(lb.get("losing", false)):
		if float(la.get("progress", 0.0)) >= float(lb.get("progress", 0.0)):
			la["tag"] = a
			return la
		lb["tag"] = b
		return lb
	return {}


static func _is_losing_war(tag: String, foe: String, day: int) -> Dictionary:
	var ratio := strength(tag, day) / maxf(strength(foe, day), 0.0001)
	var prog := 0.0
	if typeof(CapitulationDomain) != TYPE_NIL:
		prog = float(CapitulationDomain.progress(tag))
	var loss_cut := AiCredibleDomain.tune_float("peace_loss_fraction", 0.35)
	if prog + 0.0000001 >= loss_cut:
		return {"losing": true, "reason": "progress", "progress": prog, "ratio": ratio}
	var threatened := false
	if typeof(AiDefenceDomain) != TYPE_NIL:
		threatened = AiDefenceDomain.enemy_borders_capital(tag)
	var ratio_cut := AiCredibleDomain.tune_float("peace_threatened_ratio", 0.5)
	var need_days := AiCredibleDomain.tune_int("peace_threatened_days", 60)
	var st := AiCredibleDomain.state()
	var since: Dictionary = st.get("threatened_since", {}) as Dictionary
	if threatened and ratio + 0.0000001 < ratio_cut:
		if not since.has(tag):
			since[tag] = day
			st["threatened_since"] = since
		var held := day - int(since.get(tag, day))
		if held >= need_days:
			return {"losing": true, "reason": "capital", "progress": prog, "ratio": ratio}
	else:
		if since.has(tag):
			since.erase(tag)
			st["threatened_since"] = since
	return {"losing": false, "progress": prog, "ratio": ratio}


static func _quiet_days(pair: String, day: int, progress: float) -> int:
	var st := AiCredibleDomain.state()
	var quiet: Dictionary = st.get("quiet", {}) as Dictionary
	var prev: Variant = quiet.get(pair, {})
	if not (prev is Dictionary) or not (prev as Dictionary).has("progress"):
		quiet[pair] = {"day": day, "progress": progress}
		st["quiet"] = quiet
		return 0
	var row: Dictionary = prev
	if absf(float(row.get("progress", 0.0)) - progress) > 0.0000001:
		quiet[pair] = {"day": day, "progress": progress}
		st["quiet"] = quiet
		return 0
	return maxi(0, day - int(row.get("day", day)))


static func _clear_quiet(pair: String) -> void:
	var st := AiCredibleDomain.state()
	var quiet: Dictionary = st.get("quiet", {}) as Dictionary
	quiet.erase(pair)
	st["quiet"] = quiet


static func _declined_recent(pair: String, day: int) -> bool:
	var declined: Variant = AiCredibleDomain.state().get("declined", {})
	if not (declined is Dictionary) or not (declined as Dictionary).has(pair):
		return false
	var when := int((declined as Dictionary).get(pair, -99999))
	return day - when < AiCredibleDomain.tune_int("peace_reoffer_days", 14)


static func _store_player_offer(a: String, b: String, day: int, terms: String, why: String) -> void:
	var st := AiCredibleDomain.state()
	var offer := {
		"a": a,
		"b": b,
		"day": day,
		"reason": why,
		"terms": terms,
	}
	var prev: Variant = st.get("player_offer", {})
	var same := prev is Dictionary and str((prev as Dictionary).get("a", "")) == a and str((prev as Dictionary).get("b", "")) == b
	st["player_offer"] = offer
	if not same:
		var line := "OFFER day=%d a=%s b=%s %s" % [day, a, b, terms]
		print("AiCredible: offer %s-%s day=%d %s" % [a, b, day, terms])
		AiCredibleDomain.trace_line(line)
	if DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server"):
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			AiPeaceNotice.present((loop as SceneTree).root, offer)


static func _terms(row: Dictionary) -> String:
	return "goal=%.2f ratio=%.3f coal=%.1f mine=%.1f border=%d aggr=%.2f second=%d" % [
		float(row.get("goal", 0.0)),
		float(row.get("ratio", 0.0)),
		float(row.get("coalition", 0.0)),
		float(row.get("mine", 0.0)),
		int(row.get("border", 0)),
		float(row.get("aggression", 0.0)),
		int(row.get("second", 0)),
	]
