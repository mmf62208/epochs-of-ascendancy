# scripts/combat/LandBattleAi.gd
## Budgeted AI start_land_battle planner. Mirrors land_battle_ai_init_product.
## Campaign slice: plan_marches (enqueue_own_land_march) + plan_follow_on (start_land_battle).
## Interactive F5 only — never one-tick execute_province_assault, never full daily combat.
class_name LandBattleAi
extends RefCounted

const HARD_MAX_STARTS_PER_DAY := 1
const HARD_MAX_MARCHES_PER_DAY := 1
const HARD_MAX_FOLLOW_ON := 1
const HARD_MAX_OPEN_PER_TAG := 2
const MIN_AGGRESSION_TO_START := 0.50
const MIN_AGGRESSION_VS_PLAYER := 0.40
const SCAN_TAGS_PER_DAY := 2

const PERSONALITY_AGGRESSION := {
	"GER": 0.88,
	"SOV": 0.70,
	"USA": 0.55,
	"ENG": 0.50,
	"FRA": 0.45,
	"ITA": 0.60,
	"JAP": 0.75,
	"POL": 0.52,
}

const PREFERRED_FOES := {
	"GER": ["FRA", "POL", "SOV"],
	"FRA": ["GER", "ITA"],
	"SOV": ["POL", "GER"],
	"JAP": ["CHI", "SOV"],
	"USA": ["JAP"],
	"ITA": ["FRA"],
	"ENG": ["GER"],
	"POL": ["GER", "SOV"],
}


static func personality_aggression(tag: String) -> float:
	var t := tag.strip_edges().to_upper()
	if PERSONALITY_AGGRESSION.has(t):
		return float(PERSONALITY_AGGRESSION[t])
	return 0.5


static func score_opportunity(opp: Dictionary, player_tag: String = "") -> float:
	var tag := str(opp.get("tag", opp.get("att_tag", ""))).strip_edges().to_upper()
	var foe := str(opp.get("defender_tag", opp.get("def_tag", ""))).strip_edges().to_upper()
	var player := player_tag.strip_edges().to_upper()
	var score := personality_aggression(tag) * 10.0
	var prefs: Array = PREFERRED_FOES.get(tag, [])
	if not foe.is_empty() and prefs.has(foe):
		score += 2.5
	if not player.is_empty() and foe == player:
		score += 4.0
	if bool(opp.get("has_formation", false)):
		score += 3.0
	var dfn := float(opp.get("defender_power", 80.0))
	if dfn <= 60.0:
		score += 1.5
	elif dfn <= 75.0:
		score += 0.8
	return score


static func should_initiate(
	opp: Dictionary,
	player_tag: String = "",
	open_for_tag: int = 0,
	max_open: int = HARD_MAX_OPEN_PER_TAG,
) -> bool:
	if open_for_tag >= max_open:
		return false
	if not bool(opp.get("has_formation", false)):
		return false
	var tag := str(opp.get("tag", opp.get("att_tag", ""))).strip_edges().to_upper()
	var foe := str(opp.get("defender_tag", opp.get("def_tag", ""))).strip_edges().to_upper()
	var player := player_tag.strip_edges().to_upper()
	if not tag.is_empty() and tag == player:
		return false
	var agr := personality_aggression(tag)
	var vs_player := not player.is_empty() and foe == player
	if vs_player:
		if agr < MIN_AGGRESSION_VS_PLAYER:
			return false
		return float(opp.get("score", 0.0)) >= 6.0
	if agr < MIN_AGGRESSION_TO_START:
		return false
	return float(opp.get("score", 0.0)) >= 7.0


static func plan_day(
	opportunities: Array,
	player_tag: String = "GER",
	day_index: int = 0,
	open_hexes: Array = [],
	open_per_tag: Dictionary = {},
	max_starts: int = HARD_MAX_STARTS_PER_DAY,
) -> Dictionary:
	var player := player_tag.strip_edges().to_upper()
	if player.is_empty():
		player = "GER"
	var cap := clampi(int(max_starts), 1, 2)
	var busy: Dictionary = {}
	for hx in open_hexes:
		var pid := int(hx)
		if pid > 0:
			busy[pid] = true
	var scored: Array = []
	for raw in opportunities:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = raw
		var tag := str(src.get("tag", src.get("att_tag", ""))).strip_edges().to_upper()
		if tag.is_empty() or tag == player:
			continue
		var to_id := int(src.get("to_id", src.get("province_id", 0)))
		var from_id := int(src.get("from_id", src.get("from_province_id", 0)))
		if to_id <= 0 or from_id <= 0:
			continue
		if busy.has(to_id) or busy.has(from_id):
			continue
		var fid := str(src.get("formation_id", src.get("att_fid", ""))).strip_edges()
		var row := {
			"tag": tag,
			"from_id": from_id,
			"to_id": to_id,
			"defender_tag": str(src.get("defender_tag", src.get("def_tag", ""))).strip_edges().to_upper(),
			"formation_id": fid,
			"has_formation": bool(src.get("has_formation", false)) or not fid.is_empty(),
			"defender_power": float(src.get("defender_power", 80.0)),
			"live_api": "start_land_battle",
		}
		row["score"] = score_opportunity(row, player)
		var already := int(open_per_tag.get(tag, 0))
		if not should_initiate(row, player, already):
			continue
		scored.append(row)
	scored.sort_custom(func(a, b):
		var ds := float(b.get("score", 0.0)) - float(a.get("score", 0.0))
		if absf(ds) > 0.0001:
			return ds > 0.0
		return str(a.get("tag", "")) < str(b.get("tag", ""))
	)
	if scored.size() > 1:
		var top := float((scored[0] as Dictionary).get("score", 0.0))
		var ties: Array = []
		var rest: Array = []
		for item in scored:
			var row2: Dictionary = item
			if top - float(row2.get("score", 0.0)) <= 2.0:
				ties.append(row2)
			else:
				rest.append(row2)
		if ties.size() > 1:
			var start := int(day_index) % ties.size()
			var rotated: Array = []
			for i in range(ties.size()):
				rotated.append(ties[(start + i) % ties.size()])
			scored = rotated + rest
	var picks: Array = []
	for i in range(mini(cap, scored.size())):
		picks.append(scored[i])
	return {
		"ok": true,
		"picks": picks,
		"started_n": picks.size(),
		"eligible_n": scored.size(),
		"player_tag": player,
		"day_index": int(day_index),
		"max_starts": cap,
		"live_api": "start_land_battle",
		"never_instant": true,
	}


static func score_march_to_front(opp: Dictionary, player_tag: String = "") -> float:
	var tag := str(opp.get("tag", opp.get("att_tag", ""))).strip_edges().to_upper()
	var foe := str(opp.get("defender_tag", opp.get("def_tag", ""))).strip_edges().to_upper()
	var player := player_tag.strip_edges().to_upper()
	var score := personality_aggression(tag) * 10.0
	var prefs: Array = PREFERRED_FOES.get(tag, [])
	if not foe.is_empty() and prefs.has(foe):
		score += 2.5
	if not player.is_empty() and foe == player:
		score += 4.0
	if bool(opp.get("at_rear", false)) or bool(opp.get("at_capital", false)):
		score += 2.0
	if bool(opp.get("has_own_path", false)):
		score += 3.0
	if bool(opp.get("dest_is_own_land", true)):
		score += 1.0
	return score


static func should_enqueue_march(
	opp: Dictionary,
	player_tag: String = "",
	marches_today: int = 0,
	max_marches: int = HARD_MAX_MARCHES_PER_DAY,
) -> bool:
	if marches_today >= max_marches:
		return false
	var tag := str(opp.get("tag", opp.get("att_tag", ""))).strip_edges().to_upper()
	var player := player_tag.strip_edges().to_upper()
	if not tag.is_empty() and not player.is_empty() and tag == player:
		return false
	if bool(opp.get("already_marching", false)) or bool(opp.get("is_marching", false)):
		return false
	if bool(opp.get("in_combat", false)) or bool(opp.get("is_in_combat", false)):
		return false
	if opp.has("dest_is_own_land") and not bool(opp.get("dest_is_own_land", false)):
		return false
	var dest := int(opp.get("dest_id", 0))
	if dest <= 0:
		return false
	if not bool(opp.get("has_own_path", false)):
		return false
	var fid := str(opp.get("formation_id", opp.get("fid", ""))).strip_edges()
	if fid.is_empty():
		return false
	return true


static func should_follow_on(
	aar: Dictionary,
	player_tag: String = "",
	open_hexes: Array = [],
	follow_ons_today: int = 0,
	max_follow_on: int = HARD_MAX_FOLLOW_ON,
) -> bool:
	if aar.is_empty():
		return false
	if follow_ons_today >= max_follow_on:
		return false
	if str(aar.get("winner", "")).strip_edges().to_lower() != "attacker":
		return false
	var next_pid := int(aar.get("next_pid", 0))
	if next_pid <= 0:
		return false
	var fid := str(aar.get("fid", aar.get("formation_id", aar.get("att_fid", "")))).strip_edges()
	if fid.is_empty():
		return false
	var tag := str(aar.get("tag", aar.get("att_tag", ""))).strip_edges().to_upper()
	var player := player_tag.strip_edges().to_upper()
	if not tag.is_empty() and not player.is_empty() and tag == player:
		return false
	var busy: Dictionary = {}
	for hx in open_hexes:
		var pid := int(hx)
		if pid > 0:
			busy[pid] = true
	if busy.has(next_pid):
		return false
	return true


static func plan_marches(
	opportunities: Array,
	player_tag: String = "GER",
	day_index: int = 0,
	marching_fids: Array = [],
	combat_fids: Array = [],
	max_marches: int = HARD_MAX_MARCHES_PER_DAY,
) -> Dictionary:
	var player := player_tag.strip_edges().to_upper()
	if player.is_empty():
		player = "GER"
	var cap := clampi(int(max_marches), 0, HARD_MAX_MARCHES_PER_DAY)
	var marching: Dictionary = {}
	for raw_m in marching_fids:
		var mid := str(raw_m).strip_edges()
		if not mid.is_empty():
			marching[mid] = true
	var combat: Dictionary = {}
	for raw_c in combat_fids:
		var cid := str(raw_c).strip_edges()
		if not cid.is_empty():
			combat[cid] = true
	var scored: Array = []
	for raw in opportunities:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = raw
		var tag := str(src.get("tag", src.get("att_tag", ""))).strip_edges().to_upper()
		if tag.is_empty() or tag == player:
			continue
		var dest := int(src.get("dest_id", 0))
		var station := int(src.get("from_id", src.get("station_id", 0)))
		var fid := str(src.get("formation_id", src.get("fid", ""))).strip_edges()
		if dest <= 0 or fid.is_empty():
			continue
		if marching.has(fid) or combat.has(fid):
			continue
		var row := {
			"tag": tag,
			"from_id": station,
			"dest_id": dest,
			"to_id": int(src.get("to_id", src.get("province_id", 0))),
			"defender_tag": str(src.get("defender_tag", src.get("def_tag", ""))).strip_edges().to_upper(),
			"formation_id": fid,
			"has_own_path": bool(src.get("has_own_path", false)),
			"at_rear": bool(src.get("at_rear", false)) or bool(src.get("at_capital", false)),
			"at_capital": bool(src.get("at_capital", false)),
			"dest_is_own_land": bool(src.get("dest_is_own_land", true)),
			"already_marching": bool(src.get("already_marching", false)) or bool(src.get("is_marching", false)),
			"in_combat": bool(src.get("in_combat", false)) or bool(src.get("is_in_combat", false)),
			"live_api": "enqueue_own_land_march",
		}
		row["score"] = score_march_to_front(row, player)
		if not should_enqueue_march(row, player, 0, cap):
			continue
		scored.append(row)
	scored.sort_custom(func(a, b):
		var ds := float(b.get("score", 0.0)) - float(a.get("score", 0.0))
		if absf(ds) > 0.0001:
			return ds > 0.0
		return str(a.get("tag", "")) < str(b.get("tag", ""))
	)
	var picks: Array = []
	for i in range(mini(cap, scored.size())):
		picks.append(scored[i])
	return {
		"ok": true,
		"picks": picks,
		"marched_n": picks.size(),
		"eligible_n": scored.size(),
		"player_tag": player,
		"day_index": int(day_index),
		"max_marches": cap,
		"live_api": "enqueue_own_land_march",
		"never_instant": true,
	}


static func plan_follow_on(
	aar: Dictionary,
	player_tag: String = "",
	open_hexes: Array = [],
	max_follow_on: int = HARD_MAX_FOLLOW_ON,
) -> Dictionary:
	var cap := clampi(int(max_follow_on), 0, HARD_MAX_FOLLOW_ON)
	var empty := {
		"ok": true,
		"picks": [],
		"started_n": 0,
		"player_tag": player_tag.strip_edges().to_upper(),
		"max_follow_on": cap,
		"live_api": "start_land_battle",
		"never_instant": true,
	}
	if cap <= 0 or not should_follow_on(aar, player_tag, open_hexes, 0, cap):
		return empty
	var fid := str(aar.get("fid", aar.get("formation_id", aar.get("att_fid", "")))).strip_edges()
	var pick := {
		"tag": str(aar.get("tag", aar.get("att_tag", ""))).strip_edges().to_upper(),
		"to_id": int(aar.get("next_pid", 0)),
		"from_id": int(aar.get("from_id", aar.get("stage", 0))),
		"formation_id": fid,
		"live_api": "start_land_battle",
	}
	return {
		"ok": true,
		"picks": [pick],
		"started_n": 1,
		"player_tag": player_tag.strip_edges().to_upper(),
		"max_follow_on": cap,
		"live_api": "start_land_battle",
		"never_instant": true,
	}
