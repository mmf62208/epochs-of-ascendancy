# scripts/core/CampaignInkEndDomain.gd
## Data-driven campaign win check. Reads data/campaign/victory_conditions.json.
## The daily hook only reads the clock and, when wars already exist, capital
## controllers. It does not boot WarStateDomain or write peace_state.
class_name CampaignInkEndDomain
extends RefCounted

const RULES_PATH := "res://data/campaign/victory_conditions.json"

static var _rules_cache: Dictionary = {}
static var _rules_loaded: bool = false
static var _keep_playing: bool = false


static func reset_for_test() -> void:
	_rules_loaded = false
	_rules_cache = {}
	_keep_playing = false


static func note_keep_playing() -> void:
	_keep_playing = true


static func load_rules() -> Dictionary:
	if _rules_loaded:
		return _rules_cache
	_rules_loaded = true
	_rules_cache = {}
	if not FileAccess.file_exists(RULES_PATH):
		return _rules_cache
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		return _rules_cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_rules_cache = parsed
	return _rules_cache


## Pure. snapshot keys: date (YYYY-MM-DD), player_tag, enemies (Array),
## enemy_capital_controllers (tag -> controller), victory_points (int).
## Zero enemies is not a win. Missing fields never count as success.
static func evaluate_rules(snapshot: Dictionary, rules: Dictionary) -> Dictionary:
	var reasons: Array[String] = []
	if not bool(rules.get("enabled", false)):
		return {"win": false, "reasons": reasons}
	if bool(rules.get("win_if_end_date_reached", false)):
		var end := str(rules.get("end_date", "")).strip_edges()
		var today := str(snapshot.get("date", "")).strip_edges()
		if not end.is_empty() and not today.is_empty() and today >= end:
			reasons.append("end_date")
	if bool(rules.get("win_if_all_enemy_capitals_controlled", false)):
		if _all_enemy_capitals_held(snapshot):
			reasons.append("enemy_capitals")
	var vp_rules: Dictionary = {}
	if rules.get("victory_points") is Dictionary:
		vp_rules = rules.get("victory_points", {})
	if bool(vp_rules.get("enabled", false)):
		var threshold := int(vp_rules.get("threshold", 0))
		var have := int(snapshot.get("victory_points", 0))
		if threshold > 0 and have >= threshold:
			reasons.append("victory_points")
	return {
		"win": not reasons.is_empty(),
		"reasons": reasons,
		"victory_points": int(snapshot.get("victory_points", 0)),
	}


static func evaluate_day() -> Dictionary:
	if _keep_playing:
		return {"win": false, "kept_playing": true}
	var rules := load_rules()
	var result := evaluate_rules(_live_snapshot(rules), rules)
	if not bool(result.get("win", false)):
		return result
	if _campaign_end_latched():
		result["skipped_present"] = true
		return result
	_present_win(result)
	return result


static func present_forced_victory(reason: String = "debug") -> void:
	_present_win({"win": true, "reasons": [reason], "forced": true})


static func _all_enemy_capitals_held(snapshot: Dictionary) -> bool:
	var enemies: Array = snapshot.get("enemies", []) as Array
	if enemies.is_empty():
		return false
	var player := str(snapshot.get("player_tag", "")).strip_edges().to_upper()
	if player.is_empty():
		return false
	var caps: Dictionary = {}
	if snapshot.get("enemy_capital_controllers") is Dictionary:
		caps = snapshot.get("enemy_capital_controllers", {})
	for e in enemies:
		var tag := str(e).strip_edges().to_upper()
		if tag.is_empty():
			return false
		var ctrl := str(caps.get(tag, "")).strip_edges().to_upper()
		if ctrl != player:
			return false
	return true


static func _live_snapshot(rules: Dictionary) -> Dictionary:
	var snap := {
		"date": _today_iso(),
		"player_tag": _player_tag(),
		"enemies": [],
		"enemy_capital_controllers": {},
		"victory_points": 0,
	}
	if bool(rules.get("win_if_all_enemy_capitals_controlled", false)):
		_fill_existing_war_capitals(snap)
	var vp_rules: Dictionary = {}
	if rules.get("victory_points") is Dictionary:
		vp_rules = rules.get("victory_points", {})
	if bool(vp_rules.get("enabled", false)):
		snap["victory_points"] = _controlled_victory_points(str(snap.get("player_tag", "")))
	return snap


static func _today_iso() -> String:
	if typeof(TimeManager) == TYPE_NIL:
		return ""
	return "%04d-%02d-%02d" % [
		int(TimeManager.current_year),
		int(TimeManager.current_month),
		int(TimeManager.current_day),
	]


static func _player_tag() -> String:
	if typeof(LeaderManager) == TYPE_NIL:
		return ""
	return str(LeaderManager.player_country_tag).strip_edges().to_upper()


## Read wars only when GameData already has them. Never create the dict.
static func _fill_existing_war_capitals(snap: Dictionary) -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var raw: Variant = GameData.peace_state.get("campaign_wars", null)
	if not (raw is Dictionary):
		return
	var wars_v: Variant = (raw as Dictionary).get("wars", null)
	if not (wars_v is Dictionary):
		return
	var player := str(snap.get("player_tag", "")).strip_edges().to_upper()
	if player.is_empty():
		return
	var enemies: Array = []
	for k in (wars_v as Dictionary).keys():
		var parts := str(k).split("|")
		if parts.size() != 2:
			continue
		var a := parts[0].strip_edges().to_upper()
		var b := parts[1].strip_edges().to_upper()
		if a == player and not b.is_empty() and b != player:
			enemies.append(b)
		elif b == player and not a.is_empty() and a != player:
			enemies.append(a)
	snap["enemies"] = enemies
	if enemies.is_empty() or typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_country"):
		return
	var caps := {}
	for e in enemies:
		var tag := str(e)
		var country: Variant = MapManager.get_country(tag)
		var cap := -1
		if country is Dictionary:
			cap = int((country as Dictionary).get("capital_province_id", -1))
		elif country != null and "capital_province_id" in country:
			cap = int(country.capital_province_id)
		var ctrl := ""
		if cap > 0 and MapManager.has_method("get_province"):
			var prov: Variant = MapManager.get_province(cap)
			if prov != null and "controller_tag" in prov:
				ctrl = str(prov.controller_tag).strip_edges().to_upper()
		caps[tag] = ctrl
	snap["enemy_capital_controllers"] = caps


static func _controlled_victory_points(player: String) -> int:
	if player.is_empty() or typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_all_provinces"):
		return 0
	var total := 0
	var provinces: Dictionary = MapManager.get_all_provinces()
	for pid in provinces.keys():
		var prov: Variant = provinces[pid]
		if prov == null:
			continue
		var ctrl := str(prov.controller_tag).strip_edges().to_upper() if "controller_tag" in prov else ""
		if ctrl != player:
			continue
		total += int(prov.victory_points) if "victory_points" in prov else 0
	return total


static func _campaign_end_latched() -> bool:
	if typeof(CampaignEndDomain) == TYPE_NIL:
		return false
	return CampaignEndDomain.latched()


static func _present_win(result: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for n in tree.get_nodes_in_group("campaign_ink_end_screen"):
			if is_instance_valid(n):
				return
	var scr: Script = load("res://scripts/ui/CampaignInkEndScreen.gd") as Script
	if scr != null and scr.has_method("present_win"):
		var why := ", ".join(result.get("reasons", []))
		scr.call("present_win", _player_tag(), why)
		return
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.set_paused(true)
