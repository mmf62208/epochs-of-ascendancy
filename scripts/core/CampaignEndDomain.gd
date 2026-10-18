# scripts/core/CampaignEndDomain.gd
## Victory, defeat, and the 1949 time-limit latch.
## State: GameData.peace_state["campaign_end"].
class_name CampaignEndDomain
extends RefCounted


static func _end() -> Dictionary:
	if typeof(GameData) == TYPE_NIL:
		return {}
	var raw: Variant = GameData.peace_state.get("campaign_end", {})
	if raw is Dictionary:
		return raw
	return {}


static func _store(model: Dictionary) -> void:
	GameData.peace_state["campaign_end"] = model


static func reset_for_test() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	GameData.peace_state["campaign_end"] = {}


static func latched() -> bool:
	return _end().has("outcome")


static func clock_locked() -> bool:
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return false
	var end := _end()
	if not end.has("outcome"):
		return false
	return not bool(end.get("keep_playing", false))


static func set_keep_playing() -> void:
	var end := _end()
	if not end.has("outcome"):
		return
	if not bool(WarStateDomain.rules().get("allow_keep_playing", true)):
		return
	end["keep_playing"] = true
	_store(end)
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.paused = false


static func view_model() -> Dictionary:
	return _end().duplicate(true)


static func date_string() -> String:
	if typeof(TimeManager) == TYPE_NIL:
		return ""
	return "%04d-%02d-%02d" % [int(TimeManager.current_year), int(TimeManager.current_month), int(TimeManager.current_day)]


static func evaluate_and_latch(day_index: int) -> Dictionary:
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return {}
	if latched():
		return _end()
	var player := _player()
	var defeat := _defeat_model(player, day_index)
	if not defeat.is_empty():
		return _latch(defeat)
	var victory := _victory_model(player, day_index)
	if not victory.is_empty():
		return _latch(victory)
	if _time_reached():
		return _latch(_time_model(player, day_index))
	return {}


static func latch_defeat(tag: String, day_index: int) -> Dictionary:
	if latched():
		return _end()
	var player := _player()
	if tag.strip_edges().to_upper() != player:
		return {}
	return _latch(_defeat_model(player, day_index))


static func _latch(model: Dictionary) -> Dictionary:
	if model.is_empty():
		return {}
	model["keep_playing"] = false
	_store(model)
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.paused = true
	if typeof(CampaignEndScreen) != TYPE_NIL:
		CampaignEndScreen.present(model)
	return model


static func _player() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var t := str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
		if not t.is_empty():
			return t
	return "GER"


static func _defeat_model(player: String, day_index: int) -> Dictionary:
	if typeof(CapitulationDomain) == TYPE_NIL or not CapitulationDomain.is_capitulated(player):
		return {}
	var date := date_string()
	var name := WarStateDomain.tag_name(player)
	var reason := "%s capitulated on %s" % [name, date]
	return _pack("defeat", "defeat", player, day_index, "Defeat", reason, reason)


static func _victory_model(player: String, day_index: int) -> Dictionary:
	var r := WarStateDomain.rules()
	var need := int(r["victory_min_majors_defeated"])
	var count_minors := bool(r["victory_count_minors"])
	if _at_war_with_uncapitulated_major(player):
		return {}
	var beaten := _capitulated_by_side(player, count_minors)
	var majors_beaten := 0
	for tag in beaten:
		if CapitulationDomain.is_scenario_major(str(tag)) or (count_minors and not CapitulationDomain.is_scenario_major(str(tag))):
			if CapitulationDomain.is_scenario_major(str(tag)) or count_minors:
				majors_beaten += 1
	# Count scenario majors always. Count minors only when the override says so.
	var scored := 0
	for tag2 in beaten:
		var t := str(tag2)
		if CapitulationDomain.is_scenario_major(t):
			scored += 1
		elif count_minors:
			scored += 1
	if scored < need:
		return {}
	if beaten.is_empty():
		return {}
	var reason := "Decisive victory. %d nations capitulated." % scored
	return _pack("victory", "decisive", player, day_index, "Victory", reason, reason)


static func _at_war_with_uncapitulated_major(player: String) -> bool:
	for e in WarStateDomain.enemies_of(player):
		var et := str(e)
		if CapitulationDomain.is_scenario_major(et) and not CapitulationDomain.is_capitulated(et):
			return true
	return false


static func _capitulated_by_side(player: String, _count_minors: bool) -> Array:
	var out: Array = []
	if typeof(CapitulationDomain) == TYPE_NIL:
		return out
	var side := {player: true}
	if typeof(RelationsManager) != TYPE_NIL and RelationsManager.has_method("is_formal_ally_or_guaranteed"):
		var caps: Dictionary = {}
		if typeof(GameData) != TYPE_NIL:
			var raw: Variant = GameData.peace_state.get("campaign_capitulation", {})
			if raw is Dictionary:
				var craw: Variant = (raw as Dictionary).get("capitulated", {})
				if craw is Dictionary:
					caps = craw
		for tag_v in caps.keys():
			var tag := str(tag_v)
			var row_v: Variant = caps[tag_v]
			if not (row_v is Dictionary):
				continue
			var enemies: Variant = (row_v as Dictionary).get("enemies", [])
			if not (enemies is Array):
				continue
			var on_side := false
			for e in enemies:
				var et := str(e).strip_edges().to_upper()
				if et == player or bool(side.get(et, false)):
					on_side = true
				elif RelationsManager.is_formal_ally_or_guaranteed(player, et):
					on_side = true
			if on_side:
				out.append(tag)
	else:
		for tag2 in CapitulationDomain.capitulated_tags():
			out.append(str(tag2))
	out.sort()
	return out


static func time_limit_due() -> bool:
	if typeof(TimeManager) == TYPE_NIL or typeof(WarStateDomain) == TYPE_NIL:
		return false
	if not WarStateDomain.loop_enabled():
		return false
	if int(TimeManager.current_year) < WarStateDomain.end_year():
		return false
	return _time_reached()


static func _time_reached() -> bool:
	var end := str(WarStateDomain.rules().get("end_date", ""))
	if end.is_empty():
		return false
	return date_string() >= end


static func _time_model(player: String, day_index: int) -> Dictionary:
	var ranked := factory_rank()
	var rank := 1
	for i in range(ranked.size()):
		if str(ranked[i]) == player:
			rank = i + 1
			break
	var share := factory_share(player)
	if rank == 1:
		var reason := "Victory: Ascendant. Factory share %.1f%%." % (share * 100.0)
		var model := _pack("victory", "time", player, day_index, "Victory: Ascendant", reason, reason)
		model["rank"] = rank
		return model
	var reason2 := "Defeat: Eclipsed (rank %d)." % rank
	var model2 := _pack("defeat", "time", player, day_index, "Defeat: Eclipsed (rank %d)" % rank, reason2, reason2)
	model2["rank"] = rank
	return model2


static func factory_rank() -> Array:
	var shares := _factory_totals()
	var countries: Array = []
	var raw: Variant = WarStateDomain.rules().get("scenario_countries", [])
	if raw is Array:
		for c in raw:
			countries.append(str(c).strip_edges().to_upper())
	var order: Dictionary = {}
	for i in range(countries.size()):
		order[str(countries[i])] = i
	countries.sort_custom(func(a, b):
		var fa := float(shares.get(str(a), 0.0))
		var fb := float(shares.get(str(b), 0.0))
		if not is_equal_approx(fa, fb):
			return fa > fb
		return int(order.get(str(a), 99)) < int(order.get(str(b), 99))
	)
	return countries


static func factory_share(tag: String) -> float:
	var totals := _factory_totals()
	var world := float(totals.get("_world", 0.0))
	if world <= 0.0:
		return 0.0
	return float(totals.get(tag.strip_edges().to_upper(), 0.0)) / world


static func _factory_totals() -> Dictionary:
	var out := {"_world": 0.0}
	if typeof(MapManager) == TYPE_NIL or not ("_provinces" in MapManager):
		return out
	var keys: Array = MapManager._provinces.keys()
	keys.sort()
	for pid_v in keys:
		var p: Province = MapManager._provinces[pid_v]
		if p == null or bool(p.is_sea):
			continue
		var ctrl := str(p.controller_tag).strip_edges().to_upper()
		if ctrl.is_empty():
			ctrl = str(p.owner_tag).strip_edges().to_upper()
		var fac := float(p.factories)
		out["_world"] = float(out["_world"]) + fac
		out[ctrl] = float(out.get(ctrl, 0.0)) + fac
	return out


static func _pack(outcome: String, kind: String, player: String, day_index: int, title: String, reason: String, summary: String) -> Dictionary:
	var stats := _stats(player)
	return {
		"outcome": outcome,
		"kind": kind,
		"day": day_index,
		"date": date_string(),
		"player_tag": player,
		"summary": summary,
		"title": title,
		"reason": reason,
		"stats": stats,
		"allow_continuation": bool(WarStateDomain.rules().get("allow_continuation", false)) and outcome == "defeat" and kind == "defeat",
		"allow_keep_playing": bool(WarStateDomain.rules().get("allow_keep_playing", true)),
	}


static func _stats(player: String) -> Dictionary:
	var start_n := 0
	var end_n := 0
	if typeof(GameData) != TYPE_NIL:
		var cap: Variant = GameData.peace_state.get("campaign_capitulation", {})
		if cap is Dictionary:
			var owned: Variant = (cap as Dictionary).get("start_owned", {})
			if owned is Dictionary:
				var row: Variant = (owned as Dictionary).get(player, [])
				if row is Array:
					start_n = row.size()
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
		end_n = MapManager.get_provinces_by_owner(player).size()
	var wars := 0
	if typeof(GameData) != TYPE_NIL:
		var ws: Variant = GameData.peace_state.get("campaign_wars", {})
		if ws is Dictionary:
			var log: Variant = (ws as Dictionary).get("log", [])
			if log is Array:
				for ev in log:
					if ev is Dictionary and str((ev as Dictionary).get("action", "")) == "declare":
						var a := str((ev as Dictionary).get("a", ""))
						var b := str((ev as Dictionary).get("b", ""))
						if a == player or b == player:
							wars += 1
	var beaten: Array = []
	if typeof(CapitulationDomain) != TYPE_NIL:
		beaten = _side_tags(player)
	return {
		"days": int(TimeManager.total_days_elapsed) if typeof(TimeManager) != TYPE_NIL else 0,
		"provinces_start": start_n,
		"provinces_end": end_n,
		"wars_fought": wars,
		"capitulated_by_side": beaten.size(),
		"capitulated_tags": beaten,
		"factory_share": factory_share(player),
	}


static func _side_tags(player: String) -> Array:
	var out: Array = []
	if typeof(GameData) == TYPE_NIL or typeof(CapitulationDomain) == TYPE_NIL:
		return out
	var raw: Variant = GameData.peace_state.get("campaign_capitulation", {})
	if not (raw is Dictionary):
		return out
	var caps: Variant = (raw as Dictionary).get("capitulated", {})
	if not (caps is Dictionary):
		return out
	var keys: Array = (caps as Dictionary).keys()
	keys.sort()
	for k in keys:
		var row_v: Variant = (caps as Dictionary)[k]
		if not (row_v is Dictionary):
			continue
		var enemies: Variant = (row_v as Dictionary).get("enemies", [])
		if not (enemies is Array):
			continue
		for e in enemies:
			var et := str(e).strip_edges().to_upper()
			if et == player:
				out.append(str(k))
				break
			if typeof(RelationsManager) != TYPE_NIL and RelationsManager.has_method("is_formal_ally_or_guaranteed"):
				if RelationsManager.is_formal_ally_or_guaranteed(player, et):
					out.append(str(k))
					break
	return out
