# scripts/core/WarStateDomain.gd
## Pairwise campaign wars for the 1936 loop. State lives in
## GameData.peace_state["campaign_wars"]. Inactive unless the killswitch is
## off, the scenario year is 1936, and campaign_rules_1936.json loads.
class_name WarStateDomain
extends RefCounted

const RULES_PATH := "res://data/scenarios/campaign_rules_1936.json"
const KILL_ENV := "EOA_CAMPAIGN_LOOP"
const EARLY_ENV := "EOA_SCENARIO_EARLY_WARS"

static var _file_cache: Dictionary = {}
static var _file_loaded: bool = false
static var _override: Dictionary = {}
static var _booting: bool = false


static func loop_enabled() -> bool:
	if OS.get_environment(KILL_ENV).strip_edges() == "0":
		return false
	if typeof(TimeManager) != TYPE_NIL and int(TimeManager.scenario_start_year) != 1936:
		return false
	return not _file_rules().is_empty()


static func set_rule_overrides(overrides: Dictionary) -> void:
	_override = overrides.duplicate(true)


static func clear_rule_overrides() -> void:
	_override = {}


static func rules() -> Dictionary:
	var merged: Dictionary = _file_rules().duplicate(true)
	for k in _override.keys():
		merged[k] = _override[k]
	return merged


static func _file_rules() -> Dictionary:
	if _file_loaded:
		return _file_cache
	_file_loaded = true
	_file_cache = {}
	if not FileAccess.file_exists(RULES_PATH):
		return _file_cache
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		return _file_cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_file_cache = parsed
	return _file_cache


static func _state() -> Dictionary:
	if typeof(GameData) == TYPE_NIL:
		return {}
	var raw: Variant = GameData.peace_state.get("campaign_wars", {})
	if not (raw is Dictionary):
		raw = {}
	var st: Dictionary = raw
	if not (st.get("wars") is Dictionary):
		st["wars"] = {}
	if not (st.get("truces") is Dictionary):
		st["truces"] = {}
	if not (st.get("log") is Array):
		st["log"] = []
	if not (st.get("justifies") is Dictionary):
		st["justifies"] = {}
	GameData.peace_state["campaign_wars"] = st
	return st


static func _wars() -> Dictionary:
	return _state().get("wars", {}) as Dictionary


static func _truces() -> Dictionary:
	return _state().get("truces", {}) as Dictionary


static func _justifies() -> Dictionary:
	return _state().get("justifies", {}) as Dictionary


static func _tag(raw: String) -> String:
	return raw.strip_edges().to_upper()


static func pair_key(a: String, b: String) -> String:
	var x := _tag(a)
	var y := _tag(b)
	if x.is_empty() or y.is_empty() or x == y:
		return ""
	if x > y:
		var swap := x
		x = y
		y = swap
	return "%s|%s" % [x, y]


static func _day() -> int:
	if typeof(TimeManager) != TYPE_NIL and "total_days_elapsed" in TimeManager:
		return int(TimeManager.total_days_elapsed)
	return 0


static func _player() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var t := _tag(str(LeaderManager.get_player_country_tag()))
		if not t.is_empty():
			return t
	return "GER"


static func tag_name(tag: String) -> String:
	var names: Variant = rules().get("tag_names", {})
	var t := _tag(tag)
	if names is Dictionary and (names as Dictionary).has(t):
		return str((names as Dictionary)[t])
	return t


static func ensure_booted() -> void:
	if not loop_enabled():
		return
	var st := _state()
	if bool(st.get("booted", false)) or _booting:
		return
	_booting = true
	st["booted"] = true
	_apply_configured_wars()
	_booting = false


static func reload_start_wars() -> void:
	if not loop_enabled():
		return
	var st := _state()
	st["booted"] = true
	_booting = true
	_apply_configured_wars()
	_booting = false


static func reset_for_test() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	GameData.peace_state["campaign_wars"] = {
		"wars": {},
		"truces": {},
		"log": [],
		"justifies": {},
		"booted": false,
	}
	_booting = false


static func _apply_configured_wars() -> void:
	var r := rules()
	var pairs: Array = r.get("start_wars", []) as Array if r.get("start_wars") is Array else []
	if OS.get_environment(EARLY_ENV).strip_edges() == "1":
		var early: Variant = r.get("early_wars", [])
		if early is Array:
			pairs = early
	for raw in pairs:
		if not (raw is Array):
			continue
		var row: Array = raw
		if row.size() < 2:
			continue
		declare_war(str(row[0]), str(row[1]), "start")


static func declare_war(attacker: String, defender: String, goal: String = "") -> Dictionary:
	if not loop_enabled():
		return {"ok": false, "reason": "campaign loop inactive"}
	ensure_booted()
	if ai_stopped() and goal != "start" and goal != "call_to_arms":
		return {"ok": false, "reason": "campaign over"}
	var a := _tag(attacker)
	var b := _tag(defender)
	var key := pair_key(a, b)
	if key.is_empty():
		return {"ok": false, "reason": "bad pair"}
	if _wars().has(key):
		return {"ok": true, "already": true, "pair": key}
	if in_truce(a, b):
		return {"ok": false, "reason": "truce", "truce": true, "pair": key}
	if _formal_allies(a, b):
		return {"ok": false, "reason": "allied", "pair": key}
	var day := _day()
	var x := key.split("|")[0]
	var y := key.split("|")[1]
	var row := {
		"a": x,
		"b": y,
		"attacker": a,
		"defender": b,
		"start_day": day,
		"goal": goal,
	}
	var wars := _wars()
	wars[key] = row
	_state()["wars"] = wars
	_append_log("declare", a, b, day, goal)
	_sync_at_war(a)
	_sync_at_war(b)
	invalidate_fronts()
	var called: Array = []
	if goal != "call_to_arms":
		called = _call_to_arms(a, b)
	_note_war_audio()
	return {"ok": true, "pair": key, "called": called, "day": day}


static func _note_war_audio() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var root := (loop as SceneTree).root
	if root == null:
		return
	var am := root.get_node_or_null("AudioManager")
	if am != null and am.has_method("play"):
		am.call("play", "alert")


## Debug-build search line only. Release builds ignore it. No diplomacy button.
##   declare war POL
##   declare war on POL
static func debug_console_declare(line: String) -> Dictionary:
	if not OS.is_debug_build():
		return {"handled": false, "ok": false, "reason": "release"}
	var raw := line.strip_edges()
	var low := raw.to_lower()
	var rest := ""
	if low.begins_with("declare war on "):
		rest = raw.substr("declare war on ".length()).strip_edges()
	elif low.begins_with("declare war "):
		rest = raw.substr("declare war ".length()).strip_edges()
	else:
		return {"handled": false}
	var defender := ""
	if not rest.is_empty():
		defender = rest.split(" ", false)[0].strip_edges().to_upper()
	if defender.is_empty():
		return {"handled": true, "ok": false, "reason": "missing defender"}
	var attacker := _player()
	var result := declare_war(attacker, defender, "debug")
	result["handled"] = true
	result["attacker"] = attacker
	result["defender"] = defender
	print("EOA_DEBUG_DECLARE_WAR attacker=%s defender=%s ok=%s" % [attacker, defender, str(bool(result.get("ok", false)))])
	return result


static func _call_to_arms(attacker: String, defender: String) -> Array:
	var joined: Array = []
	for raw in _relation_tags():
		var x := _tag(str(raw))
		if x.is_empty() or x == attacker or x == defender:
			continue
		if not _backs_defender(defender, x):
			continue
		var res: Dictionary = declare_war(attacker, x, "call_to_arms")
		if bool(res.get("ok", false)):
			joined.append(x)
	joined.sort()
	return joined


static func allies_called(attacker: String, defender: String) -> Array:
	## Tags currently at war with attacker because they back defender.
	## Used after declare; also returns the join list stored on the log.
	var out: Array = []
	for raw in _relation_tags():
		var x := _tag(str(raw))
		if x.is_empty() or x == attacker or x == defender:
			continue
		if _backs_defender(defender, x) and is_at_war(attacker, x):
			out.append(x)
	out.sort()
	return out


static func _backs_defender(defender: String, other: String) -> bool:
	if typeof(RelationsManager) == TYPE_NIL or not RelationsManager.has_method("is_formal_ally_or_guaranteed"):
		return false
	return bool(RelationsManager.is_formal_ally_or_guaranteed(defender, other))


static func _formal_allies(a: String, b: String) -> bool:
	if typeof(RelationsManager) == TYPE_NIL or not RelationsManager.has_method("is_allied"):
		return false
	return bool(RelationsManager.is_allied(a, b))


static func _relation_tags() -> Array:
	var found: Dictionary = {}
	if typeof(RelationsManager) != TYPE_NIL and "_pairs" in RelationsManager:
		var pairs: Variant = RelationsManager._pairs
		if pairs is Dictionary:
			for k in (pairs as Dictionary).keys():
				for part in str(k).split("|"):
					var t := _tag(part)
					if not t.is_empty():
						found[t] = true
	var keys: Array = found.keys()
	keys.sort()
	return keys


static func is_at_war(a: String, b: String) -> bool:
	if not loop_enabled():
		return false
	ensure_booted()
	var key := pair_key(a, b)
	if key.is_empty():
		return false
	return _wars().has(key)


static func enemies_of(tag: String) -> Array:
	if not loop_enabled():
		return []
	ensure_booted()
	var t := _tag(tag)
	var out: Array = []
	var wars := _wars()
	var keys: Array = wars.keys()
	keys.sort()
	for k in keys:
		var row_v: Variant = wars[k]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var aa := _tag(str(row.get("a", "")))
		var bb := _tag(str(row.get("b", "")))
		if aa == t and not bb.is_empty():
			out.append(bb)
		elif bb == t and not aa.is_empty():
			out.append(aa)
	out.sort()
	return out


static func war_count(tag: String) -> int:
	return enemies_of(tag).size()


static func any_war() -> bool:
	if not loop_enabled():
		return false
	ensure_booted()
	return not _wars().is_empty()


static func in_truce(a: String, b: String) -> bool:
	if not loop_enabled():
		return false
	var key := pair_key(a, b)
	if key.is_empty() or not _truces().has(key):
		return false
	return _day() < int(_truces()[key])


static func make_peace(a: String, b: String, reason: String = "") -> Dictionary:
	if not loop_enabled():
		return {"ok": false, "reason": "campaign loop inactive"}
	ensure_booted()
	var key := pair_key(a, b)
	if key.is_empty() or not _wars().has(key):
		return {"ok": false, "reason": "not at war", "pair": key}
	var wars := _wars()
	wars.erase(key)
	_state()["wars"] = wars
	var until := _day() + int(rules()["truce_days"])
	var truces := _truces()
	truces[key] = until
	_state()["truces"] = truces
	_append_log("peace", _tag(a), _tag(b), _day(), reason)
	_sync_at_war(_tag(a))
	_sync_at_war(_tag(b))
	invalidate_fronts()
	return {"ok": true, "pair": key, "until_day": until, "reason": reason}


static func _sync_at_war(tag: String) -> void:
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("set_country_at_war"):
		return
	LeaderManager.set_country_at_war(tag, not enemies_of(tag).is_empty())


static func _append_log(action: String, a: String, b: String, day: int, reason: String) -> void:
	var log: Array = _state().get("log", []) as Array
	log.append({
		"action": action,
		"a": a,
		"b": b,
		"day": day,
		"reason": reason,
	})
	_state()["log"] = log


static func invalidate_fronts() -> void:
	if typeof(MapManager) == TYPE_NIL:
		return
	if "_live_fronts_precompute" in MapManager:
		MapManager._live_fronts_precompute = {}


static func ai_stopped() -> bool:
	if typeof(GameData) == TYPE_NIL:
		return false
	var end: Variant = GameData.peace_state.get("campaign_end", {})
	if end is Dictionary and not (end as Dictionary).is_empty() and (end as Dictionary).has("outcome"):
		return true
	return false


static func player_enemies_line() -> String:
	if not loop_enabled():
		return ""
	var enemies := enemies_of(_player())
	if enemies.is_empty():
		return ""
	var names: PackedStringArray = PackedStringArray()
	for e in enemies:
		names.append(tag_name(str(e)))
	return "At war: " + ", ".join(names)


static func begin_player_justify_from_province(province_id: int) -> Dictionary:
	if not loop_enabled():
		return {"ok": false, "reason": "campaign loop inactive"}
	ensure_booted()
	var defender := _owner_of(province_id)
	var attacker := _player()
	if defender.is_empty() or defender == attacker:
		return {"ok": false, "reason": "no foreign target"}
	return _begin_justify(attacker, defender, _day() + int(rules()["player_justify_days"]), "player")


## Debug/test helper. Writes one player justify that is ready today.
## Does not advance the clock, roll RNG, or declare the war.
## GER uses the Maginot border pid 710739 when that hex is still French.
static func grant_ready_player_justify(defender: String = "") -> Dictionary:
	if not loop_enabled():
		return {"ok": false, "reason": "campaign loop inactive"}
	var attacker := _player()
	var b := _tag(defender)
	var pid := -1
	if b.is_empty() and attacker == "GER" and _owner_of(710739) == "FRA" and borders_tag(710739, "GER"):
		b = "FRA"
		pid = 710739
	if b.is_empty():
		var suggested := suggest_player_target()
		b = _tag(str(suggested.get("tag", "")))
		pid = int(suggested.get("pid", -1))
	if b.is_empty() or b == attacker:
		return {"ok": false, "reason": "no target", "attacker": attacker}
	if pid <= 0:
		pid = _border_pid(attacker, b)
	var day := _day()
	var key := "%s>%s" % [attacker, b]
	var just := _justifies()
	just[key] = {
		"attacker": attacker,
		"defender": b,
		"ready_day": day,
		"kind": "player",
		"start_day": day,
	}
	_state()["justifies"] = just
	print(
		"EOA_AUDIO1_READY_WAR attacker=%s defender=%s ready_day=%d pid=%d"
		% [attacker, b, day, pid]
	)
	return {
		"ok": true,
		"attacker": attacker,
		"defender": b,
		"ready_day": day,
		"pid": pid,
		"kind": "player",
	}


static func player_declare_from_province(province_id: int) -> Dictionary:
	if not loop_enabled():
		return {"ok": false, "reason": "campaign loop inactive"}
	ensure_booted()
	var defender := _owner_of(province_id)
	var attacker := _player()
	if defender.is_empty():
		return {"ok": false, "reason": "no target"}
	if is_at_war(attacker, defender):
		return {"ok": true, "already": true}
	if not _justify_ready(attacker, defender, _day()):
		return {"ok": false, "reason": "justifying", "defender": defender}
	var res: Dictionary = declare_war(attacker, defender, "player")
	if bool(res.get("ok", false)):
		var just := _justifies()
		just.erase("%s>%s" % [attacker, defender])
		_state()["justifies"] = just
	return res


static func player_justify_is_ready() -> bool:
	if not loop_enabled():
		return false
	var attacker := _player()
	var day := _day()
	var just := _justifies()
	for k in just.keys():
		var row_v: Variant = just[k]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		if _tag(str(row.get("attacker", ""))) != attacker:
			continue
		if str(row.get("kind", "")) != "player":
			continue
		if int(row.get("ready_day", 999999)) <= day:
			var defender := _tag(str(row.get("defender", "")))
			if not defender.is_empty() and not is_at_war(attacker, defender):
				return true
	return false


static func player_justify_is_ready_for(defender: String) -> bool:
	if not loop_enabled():
		return false
	var d := _tag(defender)
	if d.is_empty():
		return false
	var attacker := _player()
	if is_at_war(attacker, d):
		return false
	return _justify_ready(attacker, d, _day())


static func player_has_justify(defender: String) -> bool:
	var key := "%s>%s" % [_player(), _tag(defender)]
	return _justifies().has(key)


static func player_justify_days_left(defender: String) -> int:
	var key := "%s>%s" % [_player(), _tag(defender)]
	if not _justifies().has(key):
		return int(rules()["player_justify_days"]) if loop_enabled() else 0
	return maxi(0, int((_justifies()[key] as Dictionary).get("ready_day", 0)) - _day())


static func suggest_player_target() -> Dictionary:
	var tag := _player()
	var neighbours := land_neighbours(tag)
	var preferred: Array = []
	if typeof(LandBattleAi) != TYPE_NIL:
		var prefs: Variant = LandBattleAi.PREFERRED_FOES.get(tag, [])
		if prefs is Array:
			preferred = prefs
	var target := ""
	for p in preferred:
		var pt := _tag(str(p))
		if neighbours.has(pt) and not is_at_war(tag, pt) and not in_truce(tag, pt):
			target = pt
			break
	if target.is_empty():
		for n in neighbours:
			var nt := _tag(str(n))
			if not is_at_war(tag, nt) and not in_truce(tag, nt):
				target = nt
				break
	return {"tag": target, "pid": _border_pid(tag, target), "name": tag_name(target)}


static func _owner_of(province_id: int) -> String:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return ""
	var p: Province = MapManager.get_province(province_id)
	if p == null:
		return ""
	return _tag(str(p.owner_tag))


static func _border_pid(tag: String, foe: String) -> int:
	if foe.is_empty() or typeof(MapManager) == TYPE_NIL:
		return -1
	if not MapManager.has_method("get_provinces_by_owner"):
		return -1
	var best := -1
	for pid_v in MapManager.get_provinces_by_owner(tag):
		var pid := int(pid_v)
		for nid_v in MapManager.get_adjacent_provinces(pid, true):
			var n: Province = MapManager.get_province(int(nid_v))
			if n == null or bool(n.is_sea):
				continue
			if _tag(str(n.owner_tag)) != foe:
				continue
			var nid := int(nid_v)
			if best < 0 or nid < best:
				best = nid
	return best


static func land_neighbours(tag: String) -> Array:
	var t := _tag(tag)
	var found: Dictionary = {}
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_provinces_by_owner"):
		return []
	for pid_v in MapManager.get_provinces_by_owner(t):
		for nid_v in MapManager.get_adjacent_provinces(int(pid_v), true):
			var n: Province = MapManager.get_province(int(nid_v))
			if n == null or bool(n.is_sea):
				continue
			var ot := _tag(str(n.owner_tag))
			if ot.is_empty() or ot == t:
				continue
			found[ot] = true
	var keys: Array = found.keys()
	keys.sort()
	return keys


static func borders_tag(province_id: int, tag: String) -> bool:
	if typeof(MapManager) == TYPE_NIL:
		return false
	var p: Province = MapManager.get_province(province_id)
	if p == null or bool(p.is_sea):
		return false
	var owner := _tag(str(p.owner_tag))
	var t := _tag(tag)
	if owner.is_empty() or owner == t:
		return false
	for nid_v in MapManager.get_adjacent_provinces(province_id, true):
		var n: Province = MapManager.get_province(int(nid_v))
		if n == null or bool(n.is_sea):
			continue
		if _tag(str(n.owner_tag)) == t:
			return true
	return false


static func military_strength(tag: String) -> float:
	## Division count × average land_combat_power (sum of per-division power).
	## When the tag has no divisions, fall back to the sum of
	## (province_base_weight + factories) on land it owns. Headless boards
	## often have no OOB, so the declare test overrides ai_declare_min_ratio to 0.
	var t := _tag(tag)
	var sum := 0.0
	var n := 0
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formations_for_country"):
		for f in LeaderManager.get_formations_for_country(t):
			if f == null:
				continue
			var ftype := str(f.formation_type) if "formation_type" in f else ""
			if ftype != "division":
				continue
			n += 1
			if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("land_combat_power"):
				sum += float(BattleManager.land_combat_power(f))
			else:
				sum += 1.0
	if n > 0:
		return sum
	return _factory_weight(t)


static func _factory_weight(tag: String) -> float:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_provinces_by_owner"):
		return 1.0
	var base_w := float(rules().get("province_base_weight", 1))
	var total := 0.0
	for pid_v in MapManager.get_provinces_by_owner(tag):
		var p: Province = MapManager.get_province(int(pid_v))
		if p == null or bool(p.is_sea):
			continue
		total += base_w + float(p.factories)
	return maxf(total, 1.0)


static func _begin_justify(attacker: String, defender: String, ready_day: int, kind: String) -> Dictionary:
	var a := _tag(attacker)
	var b := _tag(defender)
	if a.is_empty() or b.is_empty():
		return {"ok": false, "reason": "bad pair"}
	var key := "%s>%s" % [a, b]
	var just := _justifies()
	if just.has(key):
		return (just[key] as Dictionary).duplicate()
	just[key] = {
		"attacker": a,
		"defender": b,
		"ready_day": ready_day,
		"kind": kind,
		"start_day": _day(),
	}
	_state()["justifies"] = just
	return {"ok": true, "attacker": a, "defender": b, "ready_day": ready_day, "kind": kind}


static func _justify_ready(attacker: String, defender: String, day: int) -> bool:
	var key := "%s>%s" % [_tag(attacker), _tag(defender)]
	if not _justifies().has(key):
		return false
	return int((_justifies()[key] as Dictionary).get("ready_day", 999999)) <= day


static func _has_pending_justify(attacker: String) -> bool:
	var a := _tag(attacker)
	for k in _justifies().keys():
		var row_v: Variant = _justifies()[k]
		if row_v is Dictionary and _tag(str((row_v as Dictionary).get("attacker", ""))) == a:
			return true
	return false


static func try_ai_declare_wars(day_index: int) -> Array:
	if not loop_enabled():
		return []
	if ai_stopped():
		return []
	ensure_booted()
	var r := rules()
	var day := int(day_index)
	var min_day := int(r["ai_declare_min_day"])
	if day < min_day and not _any_justify():
		return []
	var events: Array = _complete_ready_justifies(day)
	if day < min_day:
		return events
	var checks := int(r["ai_declare_checks_per_day"])
	if checks <= 0:
		return events
	var majors := _declare_candidates()
	if majors.is_empty():
		return events
	var rot := day % majors.size()
	var min_aggr := float(r["ai_declare_min_aggression"])
	var max_wars := int(r["ai_max_wars"])
	var min_ratio := float(r["ai_declare_min_ratio"])
	var may_player := bool(r["ai_may_declare_on_player"])
	var justify_days := int(r["ai_justify_days"])
	var player := _player()
	for i in range(checks):
		var m := str(majors[(rot + i) % majors.size()])
		if war_count(m) >= max_wars:
			continue
		if typeof(LandBattleAi) == TYPE_NIL:
			continue
		if LandBattleAi.personality_aggression(m) < min_aggr:
			continue
		if _has_pending_justify(m):
			continue
		var target := _pick_declare_target(m, player, may_player, min_ratio)
		if target.is_empty():
			continue
		_begin_justify(m, target, day + justify_days, "ai")
		events.append({"action": "justify", "attacker": m, "defender": target, "day": day, "ready_day": day + justify_days})
	return events


static func _any_justify() -> bool:
	return not _justifies().is_empty()


static func _is_player_or_human_nation(tag: String) -> bool:
	var t := _tag(tag)
	if t.is_empty():
		return false
	if t == _player():
		return true
	if typeof(SessionPlayers) == TYPE_NIL:
		return false
	if not SessionPlayers.has_method("get_human_tags"):
		return false
	for h in SessionPlayers.get_human_tags():
		if _tag(str(h)) == t:
			return true
	return false


static func _complete_ready_justifies(day: int) -> Array:
	var events: Array = []
	var just := _justifies()
	var keys: Array = just.keys()
	keys.sort()
	var done: Array = []
	for k in keys:
		var row_v: Variant = just[k]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		if int(row.get("ready_day", 999999)) > day:
			continue
		var attacker := _tag(str(row.get("attacker", "")))
		var defender := _tag(str(row.get("defender", "")))
		if attacker.is_empty() or defender.is_empty():
			done.append(str(k))
			continue
		# Player / human slots stay at "ready" until they click Declare.
		if _is_player_or_human_nation(attacker):
			if is_at_war(attacker, defender) or in_truce(attacker, defender):
				done.append(str(k))
			continue
		done.append(str(k))
		if is_at_war(attacker, defender) or in_truce(attacker, defender):
			continue
		var res: Dictionary = declare_war(attacker, defender, str(row.get("kind", "ai")))
		events.append({
			"action": "declare",
			"attacker": attacker,
			"defender": defender,
			"day": day,
			"ok": bool(res.get("ok", false)),
		})
	if not done.is_empty():
		just = _justifies()
		for k2 in done:
			just.erase(k2)
		_state()["justifies"] = just
	return events


static func _declare_candidates() -> Array:
	var r := rules()
	var raw: Variant = r.get("ai_declare_tags", [])
	var tags: Array = raw if raw is Array else []
	var player := _player()
	var majors: Array = []
	for t in tags:
		var tag := _tag(str(t))
		if tag.is_empty() or tag == player:
			continue
		majors.append(tag)
	majors.sort_custom(func(a, b):
		return LandBattleAi.personality_aggression(str(a)) > LandBattleAi.personality_aggression(str(b))
	)
	return majors


static func _pick_declare_target(tag: String, player: String, may_player: bool, min_ratio: float) -> String:
	var neighbours := land_neighbours(tag)
	var ordered: Array = []
	if typeof(LandBattleAi) != TYPE_NIL:
		var prefs: Variant = LandBattleAi.PREFERRED_FOES.get(tag, [])
		if prefs is Array:
			for p in prefs:
				var pt := _tag(str(p))
				if neighbours.has(pt):
					ordered.append(pt)
	for n in neighbours:
		var nt := _tag(str(n))
		if not ordered.has(nt):
			ordered.append(nt)
	var mine := military_strength(tag)
	for foe in ordered:
		var f := str(foe)
		if f == player and not may_player:
			continue
		if is_at_war(tag, f) or in_truce(tag, f) or _formal_allies(tag, f):
			continue
		var theirs := military_strength(f)
		var ratio := mine / maxf(theirs, 0.0001)
		if ratio + 0.0000001 < min_ratio:
			continue
		return f
	return ""


static func end_year() -> int:
	var end := ""
	if _override.has("end_date"):
		end = str(_override["end_date"])
	else:
		end = str(_file_rules().get("end_date", "1949-01-01"))
	if end.length() >= 4:
		return int(end.substr(0, 4))
	return 1949


static func note_province_owner_changed() -> void:
	if not loop_enabled():
		return
	# A captured hex is no longer a front. The precompute cache would keep
	# offering it, and the next enemy hex would never be scanned.
	invalidate_fronts()
	var days: Variant = _override["stalemate_white_peace_days"] if _override.has("stalemate_white_peace_days") else _file_rules().get("stalemate_white_peace_days", null)
	if days == null:
		return
	_state()["front_change_day"] = _day()
