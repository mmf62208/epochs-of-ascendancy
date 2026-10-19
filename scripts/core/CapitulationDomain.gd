# scripts/core/CapitulationDomain.gd
## Surrender progress against the day-0 ownership snapshot.
## State: GameData.peace_state["campaign_capitulation"].
class_name CapitulationDomain
extends RefCounted

const SCENARIO_PATH := "res://data/scenarios/world_accurate.json"
const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const ECON_PATH := "res://data/provinces_world_accurate/province_economy_layer.json"

static var _scenario: Dictionary = {}
static var _scenario_loaded: bool = false
static var _city_capitals: Dictionary = {}
static var _city_loaded: bool = false
static var _econ: Dictionary = {}
static var _econ_loaded: bool = false
static var _last_check_ms: float = 0.0
static var _last_annex_ms: float = 0.0


static func _cap() -> Dictionary:
	if typeof(GameData) == TYPE_NIL:
		return {}
	var raw: Variant = GameData.peace_state.get("campaign_capitulation", {})
	if not (raw is Dictionary):
		raw = {}
	var st: Dictionary = raw
	if not (st.get("start_owned") is Dictionary):
		st["start_owned"] = {}
	if not (st.get("weights") is Dictionary):
		st["weights"] = {}
	if not (st.get("capitals") is Dictionary):
		st["capitals"] = {}
	if not (st.get("capitulated") is Dictionary):
		st["capitulated"] = {}
	if not (st.get("pending_sheet") is Dictionary):
		st["pending_sheet"] = {}
	GameData.peace_state["campaign_capitulation"] = st
	return st


static func reset_for_test() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	GameData.peace_state["campaign_capitulation"] = {}
	_last_check_ms = 0.0
	_last_annex_ms = 0.0


static func last_check_ms() -> float:
	return _last_check_ms


static func last_annex_ms() -> float:
	return _last_annex_ms


static func _load_scenario() -> Dictionary:
	if _scenario_loaded:
		return _scenario
	_scenario_loaded = true
	_scenario = {}
	if not FileAccess.file_exists(SCENARIO_PATH):
		return _scenario
	var f := FileAccess.open(SCENARIO_PATH, FileAccess.READ)
	if f == null:
		return _scenario
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_scenario = parsed
	return _scenario


static func _scenario_country(tag: String) -> Dictionary:
	var countries: Variant = _load_scenario().get("countries", [])
	if not (countries is Array):
		return {}
	var t := tag.strip_edges().to_upper()
	for raw in countries:
		if raw is Dictionary and str((raw as Dictionary).get("tag", "")).strip_edges().to_upper() == t:
			return raw
	return {}


static func _city_capital_for(tag: String) -> int:
	if not _city_loaded:
		_city_loaded = true
		_city_capitals = {}
		if FileAccess.file_exists(CITY_PATH):
			var f := FileAccess.open(CITY_PATH, FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				f.close()
				var rows: Variant = parsed.get("provinces", parsed) if parsed is Dictionary else {}
				if rows is Dictionary:
					for pid_s in (rows as Dictionary).keys():
						var row_v: Variant = (rows as Dictionary)[pid_s]
						if not (row_v is Dictionary):
							continue
						var row: Dictionary = row_v
						if not bool(row.get("capital", false)) and not bool(row.get("is_capital", false)):
							continue
						var ct := str(row.get("tag", "")).strip_edges().to_upper()
						if ct.is_empty():
							continue
						var pid := int(pid_s)
						if not _city_capitals.has(ct) or pid < int(_city_capitals[ct]):
							_city_capitals[ct] = pid
	var t := tag.strip_edges().to_upper()
	return int(_city_capitals.get(t, -1))


static func economy_factories(province_id: int) -> int:
	if not _econ_loaded:
		_econ_loaded = true
		_econ = {}
		if FileAccess.file_exists(ECON_PATH):
			var f := FileAccess.open(ECON_PATH, FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				f.close()
				var rows: Variant = parsed.get("provinces", parsed) if parsed is Dictionary else {}
				if rows is Dictionary:
					_econ = rows
	var row_v: Variant = _econ.get(str(province_id), {})
	if row_v is Dictionary:
		return int((row_v as Dictionary).get("factories", 0))
	return 0


static func apply_economy_factories_to_map() -> int:
	## Test helper: perf-boot overwrites factories. Golden weights use the economy layer.
	if typeof(MapManager) == TYPE_NIL:
		return 0
	var n := 0
	for pid_v in MapManager._provinces.keys():
		var p: Province = MapManager._provinces[pid_v]
		if p == null or bool(p.is_sea):
			continue
		p.factories = economy_factories(int(pid_v))
		n += 1
	return n


static func ensure_snapshot() -> void:
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return
	var st := _cap()
	if bool(st.get("snapshotted", false)):
		return
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("_ensure_owner_index"):
		return
	MapManager._ensure_owner_index()
	var owned_by: Dictionary = {}
	var index: Dictionary = MapManager._owner_index
	var tags: Array = index.keys()
	tags.sort()
	for tag_v in tags:
		var tag := str(tag_v).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var pids: Array = []
		var raw: Variant = index.get(tag_v, [])
		if raw is Array:
			for pid_v in raw:
				var p: Province = MapManager.get_province(int(pid_v))
				if p == null or bool(p.is_sea):
					continue
				pids.append(int(pid_v))
		pids.sort()
		if pids.is_empty():
			continue
		owned_by[tag] = pids
	var weight_rows: Dictionary = {}
	var capitals: Dictionary = {}
	for tag2 in owned_by.keys():
		var plist: Array = owned_by[tag2]
		var by_pid: Dictionary = {}
		var total := 0.0
		var cap := resolve_capital(str(tag2), plist)
		capitals[str(tag2)] = cap
		for pid in plist:
			var w := province_weight(int(pid), str(tag2), cap)
			by_pid[int(pid)] = w
			total += w
		weight_rows[str(tag2)] = {"total": total, "by_pid": by_pid}
	st["start_owned"] = owned_by
	st["weights"] = weight_rows
	st["capitals"] = capitals
	st["snapshotted"] = true
	_cap_store(st)


static func _cap_store(st: Dictionary) -> void:
	GameData.peace_state["campaign_capitulation"] = st


static func resolve_capital(tag: String, owned: Array = []) -> int:
	var t := tag.strip_edges().to_upper()
	var mine: Array = owned
	if mine.is_empty():
		var st := _cap()
		var raw: Variant = (st.get("start_owned", {}) as Dictionary).get(t, [])
		if raw is Array:
			mine = raw
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			for pid_v in MapManager.get_provinces_by_owner(t):
				mine.append(int(pid_v))
	var country := _scenario_country(t)
	var scenario_cap := int(country.get("capital_province_id", -1))
	if scenario_cap > 0 and _list_has(mine, scenario_cap):
		return scenario_cap
	var city_cap := _city_capital_for(t)
	if city_cap > 0 and _list_has(mine, city_cap):
		return city_cap
	var best_pid := -1
	var best_fac := -1
	for pid_v in mine:
		var pid := int(pid_v)
		var fac := 0
		if typeof(MapManager) != TYPE_NIL:
			var p: Province = MapManager.get_province(pid)
			if p != null:
				fac = int(p.factories)
		if fac > best_fac or (fac == best_fac and (best_pid < 0 or pid < best_pid)):
			best_fac = fac
			best_pid = pid
	return best_pid


static func _list_has(rows: Array, pid: int) -> bool:
	for v in rows:
		if int(v) == pid:
			return true
	return false


static func province_weight(province_id: int, tag: String, capital_pid: int) -> float:
	var r := WarStateDomain.rules()
	var w := float(r["province_base_weight"])
	var fac := 0
	if typeof(MapManager) != TYPE_NIL:
		var p: Province = MapManager.get_province(province_id)
		if p != null:
			fac = int(p.factories)
	w += float(fac)
	var country := _scenario_country(tag)
	var keys: Variant = country.get("key_provinces", [])
	if keys is Array:
		for k in keys:
			if int(k) == province_id:
				w += float(r["key_weight"])
				break
	if capital_pid == province_id and capital_pid > 0:
		w += float(r["capital_weight"])
	return w


static func progress(tag: String) -> float:
	if typeof(WarStateDomain) == TYPE_NIL or WarStateDomain.enemies_of(tag).is_empty():
		return 0.0
	var st := _cap()
	var t := tag.strip_edges().to_upper()
	var weight_row_v: Variant = (st.get("weights", {}) as Dictionary).get(t, {})
	if not (weight_row_v is Dictionary):
		return 0.0
	var weight_row: Dictionary = weight_row_v
	var total := float(weight_row.get("total", 0.0))
	if total <= 0.0:
		return 0.0
	var by_pid: Dictionary = weight_row.get("by_pid", {}) as Dictionary
	var held := 0.0
	var owned: Array = (st.get("start_owned", {}) as Dictionary).get(t, [])
	for pid_v in owned:
		var pid := int(pid_v)
		if _held_by_enemy(t, pid):
			held += float(by_pid.get(pid, 0.0))
	var ratio := held / total
	var bonus := float(WarStateDomain.rules()["capital_loss_bonus"])
	if bonus > 0.0:
		var cap := int((st.get("capitals", {}) as Dictionary).get(t, -1))
		if cap > 0 and _held_by_enemy(t, cap):
			ratio += bonus
	return ratio


static func _held_by_enemy(tag: String, province_id: int) -> bool:
	if typeof(MapManager) == TYPE_NIL:
		return false
	var p: Province = MapManager.get_province(province_id)
	if p == null:
		return false
	var owner := str(p.owner_tag).strip_edges().to_upper()
	var ctrl := str(p.controller_tag).strip_edges().to_upper()
	if ctrl.is_empty():
		ctrl = owner
	if not owner.is_empty() and owner != tag and WarStateDomain.is_at_war(tag, owner):
		return true
	if not ctrl.is_empty() and ctrl != tag and WarStateDomain.is_at_war(tag, ctrl):
		return true
	return false


static func threshold(tag: String) -> float:
	var r := WarStateDomain.rules()
	var t := tag.strip_edges().to_upper()
	var countries: Variant = r.get("scenario_countries", [])
	var listed := false
	if countries is Array:
		for c in countries:
			if str(c).strip_edges().to_upper() == t:
				listed = true
				break
	if not listed:
		return float(r["threshold_minor"])
	var country := _scenario_country(t)
	var stability := float(country.get("stability", 0.0))
	var raw := float(r["threshold_base"]) + float(r["threshold_stability_coef"]) * stability / 100.0
	return clampf(raw, float(r["threshold_min"]), float(r["threshold_max"]))


static func is_scenario_major(tag: String) -> bool:
	var r := WarStateDomain.rules()
	var t := tag.strip_edges().to_upper()
	var majors: Variant = r.get("scenario_majors", [])
	if not (majors is Array):
		return false
	for m in majors:
		if str(m).strip_edges().to_upper() == t:
			return true
	return false


static func is_capitulated(tag: String) -> bool:
	var t := tag.strip_edges().to_upper()
	return (_cap().get("capitulated", {}) as Dictionary).has(t)


static func has_capitulated() -> bool:
	if typeof(GameData) == TYPE_NIL:
		return false
	var raw: Variant = GameData.peace_state.get("campaign_capitulation", {})
	if not (raw is Dictionary):
		return false
	var cap: Variant = (raw as Dictionary).get("capitulated", {})
	return cap is Dictionary and not (cap as Dictionary).is_empty()


static func capitulated_tags() -> Array:
	var keys: Array = (_cap().get("capitulated", {}) as Dictionary).keys()
	keys.sort()
	return keys


static func check_all(day_index: int) -> Array:
	var t0 := Time.get_ticks_usec()
	var fresh: Array = []
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		_last_check_ms = 0.0
		return fresh
	if not WarStateDomain.any_war():
		_last_check_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		return fresh
	ensure_snapshot()
	var st := _cap()
	var tags: Array = (st.get("start_owned", {}) as Dictionary).keys()
	tags.sort()
	var due: Array = []
	for tag_v in tags:
		var tag := str(tag_v).strip_edges().to_upper()
		if tag.is_empty() or is_capitulated(tag):
			continue
		if WarStateDomain.enemies_of(tag).is_empty():
			continue
		if progress(tag) + 0.0000001 < threshold(tag):
			continue
		due.append(tag)
	# Scan only. Annex time is last_annex_ms (its own bar).
	_last_check_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	for due_tag in due:
		_capitulate(str(due_tag), int(day_index))
		fresh.append(str(due_tag))
	return fresh


static func _capitulate(tag: String, day_index: int) -> void:
	var enemies := WarStateDomain.enemies_of(tag)
	var leader := war_leader(tag, enemies)
	var outcome := default_outcome(tag)
	var st := _cap()
	var caps: Dictionary = st.get("capitulated", {})
	caps[tag] = {
		"tag": tag,
		"day": day_index,
		"date": _date_string(),
		"enemies": enemies.duplicate(),
		"war_leader": leader,
		"outcome": outcome,
	}
	st["capitulated"] = caps
	_cap_store(st)
	_close_fights(tag)
	for e in enemies:
		WarStateDomain.make_peace(tag, str(e), "capitulation")
	var player := ""
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		player = str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	var player_wins := enemies.has(player)
	var player_loses := player == tag
	var headless := DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")
	if player_wins and not player_loses and not headless:
		st = _cap()
		st["pending_sheet"] = {
			"loser": tag,
			"leader": leader,
			"outcome": outcome,
			"enemies": enemies.duplicate(),
		}
		_cap_store(st)
		_open_sheet(leader, tag, outcome)
	else:
		apply_outcome(tag, leader, outcome)
	_post_capitulation_news(tag, leader, outcome, player_wins and not player_loses)
	if player_loses and typeof(CampaignEndDomain) != TYPE_NIL:
		CampaignEndDomain.latch_defeat(tag, day_index)


static func default_outcome(tag: String) -> String:
	var spec: Variant = WarStateDomain.rules().get("peace_outcome_default", {})
	var key := "major" if is_scenario_major(tag) else "minor"
	if spec is Dictionary:
		return str((spec as Dictionary).get(key, "annex_all"))
	return "annex_all"


static func war_leader(tag: String, enemies: Array) -> String:
	var best := ""
	var best_w := -1.0
	var st := _cap()
	var by_pid: Dictionary = {}
	var wrow: Variant = (st.get("weights", {}) as Dictionary).get(tag, {})
	if wrow is Dictionary:
		var raw: Variant = (wrow as Dictionary).get("by_pid", {})
		if raw is Dictionary:
			by_pid = raw
	var owned: Array = (st.get("start_owned", {}) as Dictionary).get(tag, [])
	for e in enemies:
		var et := str(e).strip_edges().to_upper()
		var w := 0.0
		for pid_v in owned:
			var pid := int(pid_v)
			if typeof(MapManager) == TYPE_NIL:
				continue
			var p: Province = MapManager.get_province(pid)
			if p == null:
				continue
			var owner := str(p.owner_tag).strip_edges().to_upper()
			var ctrl := str(p.controller_tag).strip_edges().to_upper()
			if owner == et or ctrl == et:
				w += float(by_pid.get(pid, 0.0))
		if w > best_w or (is_equal_approx(w, best_w) and (best.is_empty() or et < best)):
			best_w = w
			best = et
	if best.is_empty() and not enemies.is_empty():
		var copy: Array = enemies.duplicate()
		copy.sort()
		best = str(copy[0])
	return best


static func apply_outcome(loser: String, leader: String, outcome: String) -> Dictionary:
	var moved: Array = []
	if outcome == "annex_all" and not leader.is_empty():
		moved = _annex_remaining(loser, leader)
		_deactivate_formations(loser)
	_append_settlement(leader, loser, outcome, moved)
	var st := _cap()
	st["pending_sheet"] = {}
	_cap_store(st)
	print(
		"MAIN_FIX1_PEACE_BTN who=CapitulationDomain.apply_outcome outcome=%s leader=%s loser=%s moved=%d"
		% [outcome, leader, loser, moved.size()]
	)
	return {"ok": true, "outcome": outcome, "moved": moved.size(), "leader": leader, "loser": loser}


static func arm_pending_sheet(leader: String, loser: String, outcome: String) -> void:
	var st := _cap()
	st["pending_sheet"] = {
		"loser": loser.strip_edges().to_upper(),
		"leader": leader.strip_edges().to_upper(),
		"outcome": outcome.strip_edges(),
	}
	_cap_store(st)


static func apply_player_choice(outcome: String) -> Dictionary:
	var pending: Dictionary = _cap().get("pending_sheet", {})
	print(
		"MAIN_FIX1_PEACE_BTN who=CapitulationDomain.apply_player_choice outcome=%s pending=%s"
		% [outcome, str(pending)]
	)
	if pending.is_empty():
		return {"ok": false, "reason": "no sheet"}
	var loser := str(pending.get("loser", ""))
	var leader := str(pending.get("leader", ""))
	return apply_outcome(loser, leader, outcome)


static func _annex_remaining(loser: String, leader: String) -> Array:
	var t0 := Time.get_ticks_usec()
	var moved: Array = []
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_provinces_by_owner"):
		_last_annex_ms = 0.0
		return moved
	var pids: Array = []
	for pid_v in MapManager.get_provinces_by_owner(loser):
		pids.append(int(pid_v))
	pids.sort()
	var batched := false
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("begin_control_batch"):
		SupplyManager.begin_control_batch()
		batched = true
	for pid in pids:
		MapManager.update_province_owner(int(pid), leader, leader, false, true)
		moved.append(int(pid))
	if batched:
		SupplyManager.end_control_batch()
	_last_annex_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return moved


static func _append_settlement(winner: String, loser: String, outcome: String, moved: Array) -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var first := int(moved[0]) if not moved.is_empty() else -1
	var settlement := {
		"winner_tag": winner,
		"loser_tag": loser,
		"province_id": first,
		"items": [{
			"type": "annex" if outcome == "annex_all" else "occupation_zone",
			"province_id": first,
			"province_ids": moved.duplicate(),
			"outcome": outcome,
		}],
		"applied": true,
		"live": true,
		"manager": "GameData.peace_settlement",
		"ok": true,
		"membership": {},
		"membership_live": false,
		"campaign_outcome": outcome,
	}
	if not GameData.peace_state.has("peace_settlements") or not (GameData.peace_state["peace_settlements"] is Array):
		GameData.peace_state["peace_settlements"] = []
	var trail: Array = GameData.peace_state["peace_settlements"]
	trail.append(settlement)
	if trail.size() > 32:
		trail = trail.slice(trail.size() - 32, trail.size())
	GameData.peace_state["peace_settlements"] = trail
	GameData.peace_state["peace_last_settlement"] = settlement.duplicate(true)
	GameData.peace_state["peace_settlement_count"] = int(GameData.peace_state.get("peace_settlement_count", 0)) + 1


static func _close_fights(tag: String) -> void:
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("close_land_battles_for_tag"):
		BattleManager.close_land_battles_for_tag(tag)
	if typeof(FormationMovement) != TYPE_NIL:
		for raw in FormationMovement.list_marches():
			if not (raw is Dictionary):
				continue
			var fid := str((raw as Dictionary).get("formation_id", ""))
			if fid.is_empty() or typeof(LeaderManager) == TYPE_NIL:
				continue
			var f: Formation = LeaderManager.get_formation(fid) if LeaderManager.has_method("get_formation") else null
			if f != null and str(f.country_tag).strip_edges().to_upper() == tag:
				FormationMovement.clear_march(fid)
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return
	var forms: Variant = LeaderManager.formations
	if not (forms is Dictionary):
		return
	for fid_v in (forms as Dictionary).keys():
		var f2: Variant = (forms as Dictionary)[fid_v]
		if f2 == null:
			continue
		if str(f2.country_tag).strip_edges().to_upper() != tag:
			continue
		if "is_in_combat" in f2:
			f2.is_in_combat = false


static func _deactivate_formations(tag: String) -> void:
	if typeof(LeaderManager) == TYPE_NIL or not ("formations" in LeaderManager):
		return
	var forms: Variant = LeaderManager.formations
	if not (forms is Dictionary):
		return
	for fid_v in (forms as Dictionary).keys():
		var f: Variant = (forms as Dictionary)[fid_v]
		if f == null:
			continue
		if str(f.country_tag).strip_edges().to_upper() != tag:
			continue
		f.campaign_inactive = true
		if "is_in_combat" in f:
			f.is_in_combat = false
		if typeof(FormationMovement) != TYPE_NIL:
			FormationMovement.clear_march(str(f.formation_id))


static func _open_sheet(leader: String, loser: String, outcome: String) -> void:
	if typeof(PeaceConferenceWindow) == TYPE_NIL:
		return
	PeaceConferenceWindow.open_living_sheet(leader, loser, -1, {
		"campaign": true,
		"outcome_default": outcome,
		"loser": loser,
		"leader": leader,
	})


static func _post_capitulation_news(tag: String, leader: String, outcome: String, player_sheet: bool) -> void:
	if typeof(LeaderEventUI) == TYPE_NIL or not LeaderEventUI.has_method("post_news"):
		return
	var name := WarStateDomain.tag_name(tag)
	var body := "%s capitulated. %s" % [name, outcome]
	if player_sheet:
		body = "%s capitulated. Choose annex or keep occupied." % name
	elif not leader.is_empty():
		body = "%s capitulated. %s settles by %s." % [name, WarStateDomain.tag_name(leader), outcome]
	LeaderEventUI.post_news("Capitulation", body, "war")


static func _date_string() -> String:
	if typeof(TimeManager) == TYPE_NIL:
		return ""
	return "%04d-%02d-%02d" % [int(TimeManager.current_year), int(TimeManager.current_month), int(TimeManager.current_day)]


static func derived_capitals() -> Dictionary:
	ensure_snapshot()
	var caps: Dictionary = _cap().get("capitals", {})
	var out: Dictionary = {}
	var keys: Array = caps.keys()
	keys.sort()
	for k in keys:
		out[str(k)] = int(caps[k])
	return out
