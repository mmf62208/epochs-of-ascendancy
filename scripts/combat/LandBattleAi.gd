# scripts/combat/LandBattleAi.gd
## Budgeted AI start_land_battle planner. Mirrors land_battle_ai_init_product.
## Interactive F5 only — never one-tick execute_province_assault, never full daily combat.
class_name LandBattleAi
extends RefCounted

const HARD_MAX_STARTS_PER_DAY := 1
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
