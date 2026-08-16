# scripts/combat/BattleManager.gd
## Main-loop province assault orchestration: formations → phased combat → capture → map refresh.
extends Node

signal battle_started(context: Dictionary)
signal battle_resolved(result: Dictionary)
signal battle_day_ticked(battle: Dictionary)

const DEFAULT_GARRISON_TEMPLATE := "german_infantry_division_1943_mixed"
const ATTACKER_INITIATIVE := 0.15
const BATTLE_ORG_BREAK := 0.22
const BATTLE_ATT_STR_FLOOR := 0.35
## Pre-clamp break threshold (both sides). Clamp floors: att 0.35 / def 0.30 after break test.
const BATTLE_STR_BREAK := 0.30
const BATTLE_DEF_STR_BREAK := BATTLE_STR_BREAK
const BATTLE_ATT_STR_BREAK := BATTLE_STR_BREAK
const BATTLE_MAX_DAYS := 12
const BATTLE_TICK_BUDGET := 8
const MARCH_DEFAULT_HOURS_PER_HEX := 24.0
const MARCH_MAX_HOPS := 48

var _resolver: CombatResolver
## battle_id -> Battle dict (multi-day player path). execute_province_assault stays one-shot.
var _battles: Dictionary = {}
var _battle_seq: int = 0
var _battle_day_hooked: bool = false
## Round-robin cursor so budgeted ticks never starve battles.
var _battle_tick_rr: int = 0
## fid -> MarchOrder dict.
var _marches: Dictionary = {}
var _march_order_seq: int = 0## Round-robin cursor so budgeted ticks never starve battles beyond the first N keys.
var _battle_tick_rr: int = 0

func _ready() -> void:
	_resolver = CombatResolver.new()
	_resolver.name = "CombatResolver"
	add_child(_resolver)
	_ensure_battle_day_hook()
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_signal("game_day_advanced"):
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced_marches):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced_marches)


func _ensure_battle_day_hook() -> void:
	if _battle_day_hooked:
		return
	if typeof(TimeManager) == TYPE_NIL or not TimeManager.has_signal("game_day_advanced"):
		return
	if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced_battles):
		TimeManager.game_day_advanced.connect(_on_game_day_advanced_battles)
	_battle_day_hooked = true


func _on_game_day_advanced_battles(_year: int, _month: int, _day: int) -> void:
	tick_battles_for_day()


func _on_game_day_advanced_marches(_year: int, _month: int, _day: int) -> void:
	tick_marches_for_day()


## Multi-phase combat estimate pilot (approach/engage/disengage) — pure via MapPolishFormatters.
func estimate_multi_phase_combat(
	attacker_power: float,
	defender_power: float,
	attacker_supply: float = 1.0,
	weather_mult: float = 1.0,
) -> Dictionary:
	if typeof(MapPolishFormatters) != TYPE_NIL:
		return MapPolishFormatters.estimate_multi_phase_combat(
			attacker_power, defender_power, attacker_supply, weather_mult
		)
	return {
		"phases": [],
		"overall_attacker_win_chance": 0.5,
		"summary": "multi-phase unavailable",
		"empty": true,
	}


## Phase ribbon UI labels for multi-phase estimate pilot.
func format_combat_phase_ribbon(
	attacker_power: float = 100.0,
	defender_power: float = 80.0,
) -> Dictionary:
	var est := estimate_multi_phase_combat(attacker_power, defender_power)
	if typeof(MapPolishFormatters) != TYPE_NIL:
		return MapPolishFormatters.format_phase_ribbon(est)
	return {"ribbon_plain": str(est.get("summary", "")), "empty": bool(est.get("empty", true))}



## Assault estimate card pilot (power + phase ribbon + recommendation).
func build_assault_estimate_card(
	attacker_power: float,
	defender_power: float,
	attacker_supply: float = 1.0,
	weather_mult: float = 1.0,
	province_name: String = "",
) -> Dictionary:
	var est := estimate_multi_phase_combat(attacker_power, defender_power, attacker_supply, weather_mult)
	var ribbon := format_combat_phase_ribbon(attacker_power, defender_power)
	var overall := float(est.get("overall_attacker_win_chance", 0.0))
	var rec := "Marginal — wait for supply/reinforce"
	if overall >= 0.65:
		rec = "Favorable — press assault"
	elif overall < 0.45:
		rec = "Unfavorable — avoid or soften first"
	var plain := ""
	if typeof(MapPolishFormatters) != TYPE_NIL:
		plain = MapPolishFormatters.format_assault_estimate_card_plain(
			attacker_power, defender_power, overall, str(ribbon.get("ribbon_plain", "")), rec, province_name
		)
	return {
		"overall": overall,
		"recommendation": rec,
		"ribbon": ribbon,
		"estimate": est,
		"plain": plain,
		"favorable": overall >= 0.65,
		"empty": bool(est.get("empty", false)),
	}


## Weather-aware assault estimate: pulls combat weather mult for defender province when available.
func build_weather_aware_assault_estimate_card(
	attacker_power: float,
	defender_power: float,
	defender_province_id: int = -1,
	attacker_supply: float = 1.0,
	province_name: String = "",
) -> Dictionary:
	var wmult := 1.0
	if defender_province_id >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_combat_weather_multiplier"):
		wmult = float(WeatherManager.get_combat_weather_multiplier(defender_province_id))
	return build_assault_estimate_card(attacker_power, defender_power, attacker_supply, wmult, province_name)


## Weather-aware multi-phase combat ribbon (estimate × weather mult).
func build_weather_phase_ribbon(
	attacker_power: float,
	defender_power: float,
	defender_province_id: int = -1,
) -> Dictionary:
	var wmult := 1.0
	if defender_province_id >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_combat_weather_multiplier"):
		wmult = float(WeatherManager.get_combat_weather_multiplier(defender_province_id))
	return MapPolishFormatters.format_weather_phase_ribbon(attacker_power, defender_power, wmult)


## Weather combat briefing package (card + ribbon + wx mult; beyond ribbon alone).
func build_weather_combat_briefing(
	attacker_power: float,
	defender_power: float,
	defender_province_id: int = -1,
	attacker_supply: float = 1.0,
	province_name: String = "",
) -> Dictionary:
	var wmult := 1.0
	if defender_province_id >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_combat_weather_multiplier"):
		wmult = float(WeatherManager.get_combat_weather_multiplier(defender_province_id))
	return MapPolishFormatters.build_weather_combat_briefing(
		attacker_power, defender_power, wmult, attacker_supply, province_name
	)


## Assault follow-on loop: readiness → press/hold/soften.
func build_assault_follow_on_loop(
	target_specs: Array,
	attacker_power: float = 100.0,
	attacker_supply: float = 1.0,
	weather_province_id: int = -1,
) -> Dictionary:
	var vis := 1.0
	var precip := 0.0
	var ground := "dry"
	var wind := 0.2
	if weather_province_id >= 0 and typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_combat_weather_multiplier"):
			var cm := float(WeatherManager.get_combat_weather_multiplier(weather_province_id))
			precip = clampf(1.0 - cm, 0.0, 0.95)
			vis = clampf(cm + 0.15, 0.1, 1.0)
		if WeatherManager.has_method("get_supply_weather_multiplier"):
			var sm := float(WeatherManager.get_supply_weather_multiplier(weather_province_id))
			if sm < 0.75:
				ground = "mud"
	return MapPolishFormatters.assault_follow_on_loop(
		target_specs, attacker_power, attacker_supply, vis, precip, ground, wind
	)


## Reinforced assault: readiness × daylight × choke.
func build_reinforced_assault_loop(
	target_specs: Array,
	attacker_power: float = 100.0,
	attacker_supply: float = 1.0,
	weather_province_id: int = -1,
) -> Dictionary:
	var vis := 1.0
	var precip := 0.0
	var ground := "dry"
	var wind := 0.2
	var month := 1
	var is_choke := false
	if weather_province_id >= 0 and typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_combat_weather_multiplier"):
			var cm := float(WeatherManager.get_combat_weather_multiplier(weather_province_id))
			precip = clampf(1.0 - cm, 0.0, 0.95)
			vis = clampf(cm + 0.15, 0.1, 1.0)
	if typeof(TimeManager) != TYPE_NIL and "current_month" in TimeManager:
		month = int(TimeManager.current_month)
	if weather_province_id >= 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
		is_choke = bool(MapManager.has_strategic_chokepoint(weather_province_id))
	return MapPolishFormatters.reinforced_assault_loop(
		target_specs, attacker_power, attacker_supply, vis, precip, ground, wind, month, is_choke, true
	)


## Assault readiness compose: multi-front + supply wx + morale wx (combat+supply+weather).
func build_assault_readiness_compose(
	target_specs: Array,
	attacker_power: float = 100.0,
	attacker_supply: float = 1.0,
	weather_province_id: int = -1,
) -> Dictionary:
	var vis := 1.0
	var precip := 0.0
	var ground := "dry"
	var wind := 0.2
	if weather_province_id >= 0 and typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_combat_weather_multiplier"):
			var cm := float(WeatherManager.get_combat_weather_multiplier(weather_province_id))
			precip = clampf(1.0 - cm, 0.0, 0.95)
			vis = clampf(cm + 0.15, 0.1, 1.0)
		if WeatherManager.has_method("get_supply_weather_multiplier"):
			var sm := float(WeatherManager.get_supply_weather_multiplier(weather_province_id))
			if sm < 0.75:
				ground = "mud"
	return MapPolishFormatters.assault_readiness_compose(
		target_specs, attacker_power, attacker_supply, vis, precip, ground, wind
	)


## Multi-front assault priority: rank candidate targets (power + weather).
func rank_multi_front_assault_targets(
	target_specs: Array,
	attacker_power: float = 100.0,
	attacker_supply: float = 1.0,
) -> Dictionary:
	var enriched: Array = []
	for t in target_specs:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = t.duplicate()
		var pid := int(row.get("province_id", row.get("id", -1)))
		if pid >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_combat_weather_multiplier"):
			row["weather_mult"] = float(WeatherManager.get_combat_weather_multiplier(pid))
		# Morale weather drag applied as soft attacker_supply hit
		if pid >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_combat_morale_weather_mult"):
			var morale := float(WeatherManager.get_combat_morale_weather_mult(pid))
			row["attacker_supply_eff"] = attacker_supply * morale
		enriched.append(row)
	return MapPolishFormatters.rank_assault_targets(enriched, attacker_power, attacker_supply, 5)

func can_assault_province(
	attacker_tag: String,
	target_province_id: int,
	from_province_id: int = -1,
	formation_id: String = "",
) -> Dictionary:
	var tag := attacker_tag.strip_edges().to_upper()
	if tag.is_empty():
		return {"ok": false, "reason": "No attacker country"}
	if typeof(MapManager) == TYPE_NIL:
		return {"ok": false, "reason": "MapManager unavailable"}

	var target: Province = MapManager.get_province(target_province_id)
	if target == null:
		return {"ok": false, "reason": "Target province not found"}

	var defender_tag := _province_defender_tag(target)
	if defender_tag.is_empty():
		return {"ok": false, "reason": "Target has no owner"}
	if defender_tag == tag:
		return {"ok": false, "reason": "Cannot attack your own province"}

	var fid := formation_id.strip_edges()
	var from_pid := int(from_province_id)
	# Named unit: station is authority; no fallback to another division.
	if not fid.is_empty() and from_pid < 0 and typeof(LeaderManager) != TYPE_NIL:
		var fo: Formation = LeaderManager.get_formation(fid)
		if fo != null and "stationed_province_id" in fo:
			from_pid = int(fo.stationed_province_id)

	# Named unit already engaging: preview/strip match start_province_battle (no false "ready").
	if not fid.is_empty() and is_formation_in_battle(fid):
		return {
			"ok": false,
			"reason": "Formation already in battle",
			"formation_id": fid,
			"target_province_id": target_province_id,
		}
	# Target hex already has an engaging multi-day battle (1v1 theater; no double-defend).
	if not get_battle_at(target_province_id).is_empty():
		return {
			"ok": false,
			"reason": "Province already under assault",
			"target_province_id": target_province_id,
		}

	var source: Dictionary
	if not fid.is_empty():
		source = _validate_attack_source(tag, from_pid, target_province_id, fid)
	elif from_pid >= 0:
		# Hex-only: no adjacent-hex fallback (fixes Berlin can=true for Maginot).
		source = _validate_attack_source(tag, from_pid, target_province_id)
	else:
		# AI / Fronts: find any adjacent division.
		source = find_attack_source(tag, target_province_id, -1)
	if not bool(source.get("ok", false)):
		return source

	source["target_province_id"] = target_province_id
	source["target_name"] = target.name
	source["defender_tag"] = defender_tag
	source["attacker_tag"] = tag
	# Carry air dominance from ProvinceInsight for battle context (used in result merge + logs + AAR)
	if typeof(ProvinceInsight) != TYPE_NIL and typeof(MapManager) != TYPE_NIL:
		var resolved_from := int(source.get("from_province_id", from_pid))
		var from_p: Province = MapManager.get_province(resolved_from) if resolved_from >= 0 else target
		if from_p:
			var bprev := ProvinceInsight.get_battle_preview(from_p, target)
			source["air_dominance_level"] = bprev.get("air_dominance_level", "none")
			source["air_power_ratio"] = bprev.get("air_power_ratio", 1.0)
			source["air_superiority_attacker"] = bprev.get("air_superiority", false)
	return source


func find_attack_source(
	attacker_tag: String,
	target_province_id: int,
	preferred_from_id: int = -1,
) -> Dictionary:
	var tag := attacker_tag.strip_edges().to_upper()
	if preferred_from_id >= 0:
		var preferred := _validate_attack_source(tag, preferred_from_id, target_province_id)
		if bool(preferred.get("ok", false)):
			return preferred

	if typeof(MapManager) == TYPE_NIL:
		return {"ok": false, "reason": "MapManager unavailable"}

	var best: Dictionary = {"ok": false, "reason": "No friendly division adjacent to target"}
	var best_power := -1.0
	for nid in MapManager.get_adjacent_provinces(target_province_id):
		var check := _validate_attack_source(tag, int(nid), target_province_id)
		if not bool(check.get("ok", false)):
			continue
		var power := float(check.get("attack_power", 0.0))
		if power > best_power:
			best_power = power
			best = check
	return best


## Unit-formula assault preview for map toast (not ProvinceInsight hex 100+infra*3).
## power = (soft + 1.6*hard) * org * str * xp_mult + initiative; attacker initiative 0.15.
func preview_assault(
	attacker_tag: String,
	target_province_id: int,
	from_province_id: int = -1,
	formation_id: String = "",
) -> Dictionary:
	var can: Dictionary = can_assault_province(
		attacker_tag, target_province_id, from_province_id, formation_id
	)
	var tag := str(can.get("attacker_tag", attacker_tag)).strip_edges().to_upper()
	var from_pid := int(can.get("from_province_id", from_province_id))
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		fid = str(can.get("formation_id", ""))
	var target: Province = null
	if typeof(MapManager) != TYPE_NIL:
		target = MapManager.get_province(target_province_id)
	var from_prov: Province = null
	if typeof(MapManager) != TYPE_NIL and from_pid >= 0:
		from_prov = MapManager.get_province(from_pid)

	var att_power := 0.0
	var def_power := 0.0
	var att_soft := 0.0
	var att_hard := 0.0
	var def_soft := 0.0
	var def_hard := 0.0
	var att_org := 1.0
	var att_str := 1.0
	var att_xp := 48.0
	var def_org := 1.0
	var def_str := 1.0
	var def_xp := 48.0

	if not fid.is_empty() and from_prov != null:
		att_power = _unit_preview_power(fid, from_prov, tag, ATTACKER_INITIATIVE)
		var att_stats := _unit_preview_components(fid, from_prov, tag)
		att_soft = float(att_stats.get("soft", 0.0))
		att_hard = float(att_stats.get("hard", 0.0))
		att_org = float(att_stats.get("org", 1.0))
		att_str = float(att_stats.get("str", 1.0))
		att_xp = float(att_stats.get("xp", 48.0))
	elif bool(can.get("ok", false)):
		att_power = float(can.get("attack_power", 0.0)) + ATTACKER_INITIATIVE

	var def_tag := str(can.get("defender_tag", ""))
	if def_tag.is_empty() and target != null:
		def_tag = _province_defender_tag(target)
	if target != null:
		var def_divs := get_divisions_at_province(target_province_id, def_tag)
		var def_fid := ""
		if not def_divs.is_empty():
			def_fid = str(def_divs[0].get("formation_id", ""))
		if not def_fid.is_empty():
			def_power = _unit_preview_power(def_fid, target, def_tag, 0.0)
			var def_stats := _unit_preview_components(def_fid, target, def_tag)
			def_soft = float(def_stats.get("soft", 0.0))
			def_hard = float(def_stats.get("hard", 0.0))
			def_org = float(def_stats.get("org", 1.0))
			def_str = float(def_stats.get("str", 1.0))
			def_xp = float(def_stats.get("xp", 48.0))
		else:
			# Empty hex: synthetic garrison at full org/str, soft/hard from template estimate.
			var g_id := _garrison_template_for_country(def_tag)
			def_power = _unit_preview_power(g_id, target, def_tag, 0.0)
			if def_power <= 0.0:
				def_power = _estimate_attack_power(g_id, target, def_tag)

	var odds := 0.0
	var total := att_power + def_power
	if total > 0.0:
		odds = clampf((att_power / total) * 100.0, 5.0, 95.0)

	var out := can.duplicate()
	out["attack_power"] = att_power
	out["defense_power"] = def_power
	out["attacker_soft"] = att_soft
	out["attacker_hard"] = att_hard
	out["attacker_org"] = att_org
	out["attacker_strength"] = att_str
	out["attacker_xp"] = att_xp
	out["defender_soft"] = def_soft
	out["defender_hard"] = def_hard
	out["defender_org"] = def_org
	out["defender_strength"] = def_str
	out["defender_xp"] = def_xp
	out["attacker_initiative"] = ATTACKER_INITIATIVE
	out["odds_attacker_win"] = odds
	out["formation_id"] = fid if not fid.is_empty() else str(can.get("formation_id", ""))
	out["from_province_id"] = from_pid if from_pid >= 0 else int(can.get("from_province_id", -1))
	out["target_province_id"] = target_province_id
	out["preview_source"] = "unit_formula"
	return out


func execute_province_assault(
	attacker_tag: String,
	target_province_id: int,
	from_province_id: int = -1,
	attacker_formation_id: String = "",
) -> Dictionary:
	# Re-validate with the same named fid — no silent swap to another division.
	var preview: Dictionary = can_assault_province(
		attacker_tag, target_province_id, from_province_id, attacker_formation_id
	)
	if not bool(preview.get("ok", false)):
		return {"success": false, "reason": preview.get("reason", "Cannot assault")}

	var tag := str(preview.get("attacker_tag", attacker_tag)).strip_edges().to_upper()
	var from_pid := int(preview.get("from_province_id", from_province_id))
	var fid := attacker_formation_id.strip_edges()
	if fid.is_empty():
		fid = str(preview.get("formation_id", ""))
	if fid.is_empty():
		return {"success": false, "reason": "No attacker formation"}

	var target: Province = MapManager.get_province(target_province_id)
	if target == null:
		return {"success": false, "reason": "Target province missing"}

	var attacker := _build_attacker_formation(fid, tag, from_pid)
	var defender := _build_defender_formation(target, str(preview.get("defender_tag", "")))

	# Deeper combat integration for playtest (loyalty/foreign + settlement from relocation/policies).
	# Settlement in target province gives defender bonus (org/readiness/attrition resistance — "our people defend their land").
	# Mixed armies: loyalty_factor scales attacker power; also passed to resolver for org/readiness.
	# Province settlement_level (from demographic engineering) now explicitly factors here and in Resolver.
	var loyalty_factor := 1.0
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_military_loyalty_multiplier"):
		loyalty_factor = GameData.get_military_loyalty_multiplier(tag)
	if "attack_power" in preview:
		preview["attack_power"] = float(preview.get("attack_power", 0)) * loyalty_factor

	# Settlement defender bonus – refined for world-class balance (inspired by HOI4 terrain/fort defensive favors ~15-50% situational total, Vic3 gradual state dev giving 5-15% throughput/defense, EU4/CK3 holding bonuses stacking to ~20-40% optimized but counterable).
	# Flavorful "Homeland Resolve / Repopulation Resilience": Our settled/repopulated lands give defender edge (motivation, local knowledge, supply from our people).
	# Smart level: ~2.5% per settlement_level (user feedback: 5%+ felt powerful). Max ~25% uplift at high investment. Conditional: +extra if high public cohesion or primary culture match (flavorful cultural fit); reduced if foreign troops or low cohesion (integration friction).
	# Fun & flavorful: Player investment in relocation/pro-natal pays off in "our land is worth more to defend", but not invincible – agents, tech, or poor cohesion can negate. Opposites: Cheap foreign settlement gives less bonus.
	var settlement_def_bonus: float = 1.0
	if target and target.settlement_level > 0.05:
		var base_bonus: float = target.settlement_level * 0.025  # 2.5% per level – balanced, not OP
		var coh: int = 50
		if typeof(GameData) != TYPE_NIL:
			coh = GameData.get_pillar(tag, "cohesion")  # proxy for public will
		var culture_match: float = 1.0
		# Simple flavor: if primary culture matches settlement vibe (high settled_areas for "our people")
		var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
		if ps.has("settled_areas") and ps["settled_areas"].size() > 0:
			culture_match = 1.1  # slight extra for cultural cohesion
		var conditional: float = 1.0 + (max(0, coh - 50) * 0.001) * culture_match  # cohesion/culture amplifier
		settlement_def_bonus = clampf(1.0 + (base_bonus * conditional), 1.0, 1.25)  # max 25% flavorful uplift
		if "defense_power" in preview:
			preview["defense_power"] = float(preview.get("defense_power", 0)) * settlement_def_bonus

	# River natural border defense (from real layers inference / demo sample apply river_aware children for 82 etc.)
	# High value: map data (rivers as borders) drives combat (defensive positions, crossing penalty for attacker).
	# Stacks with settlement/terrain/snow. Demo apply makes it live for testing without full 471 swap.
	var river_def_bonus: float = 1.0
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_river_border") and MapManager.has_river_border(target_province_id):
		river_def_bonus = 1.05  # 5% defender edge for river lines (historical e.g. Rhine defenses)
		if "defense_power" in preview:
			preview["defense_power"] = float(preview.get("defense_power", 0)) * river_def_bonus

	var context := {
		"attacker_tag": tag,
		"defender_tag": preview.get("defender_tag", ""),
		"target_province_id": target_province_id,
		"from_province_id": from_pid,
		"attacker_formation_id": fid,
		"defender_formation_id": defender.formation_id,
		"loyalty_factor": loyalty_factor,
		"settlement_def_bonus": settlement_def_bonus,
		"target_settlement_level": target.settlement_level if target else 0.0,
		"river_def_bonus": river_def_bonus,
	}
	battle_started.emit(context)

	var result: Dictionary = _resolver.resolve_combat(
		attacker,
		defender,
		target,
		fid,
		defender.formation_id,
	)
	result.merge(context)
	result["aftermath"] = _resolver.resolve_battle_aftermath(
		fid,
		defender.formation_id,
		result,
		1.0,
		from_pid,
		target_province_id,
	)

	# Balance + AAR data: numeric casualties estimates (margin based) + power details for modifiers/leader display
	var att_sc := float(result.get("attacker_score", 100.0))
	var def_sc := float(result.get("defender_score", 100.0))
	var margin_c := absf(att_sc - def_sc) / maxf(maxf(att_sc, def_sc), 1.0)
	var base_cas := int(25 + margin_c * 140 + randf() * 25)
	result["attacker_casualties"] = int(base_cas * (0.6 + randf()*0.5)) if str(result.get("winner","")) == "defender" else int(base_cas * (0.35 + randf()*0.25))
	result["defender_casualties"] = int(base_cas * (0.65 + randf()*0.5)) if str(result.get("winner","")) == "attacker" else int(base_cas * (0.3 + randf()*0.25))
	# Attach fresh power details (leader/space/nat/terrain bonuses) for full AAR modifiers list
	if _resolver != null:
		var t_terr := target.terrain if target != null and not target.terrain.is_empty() else "plains"
		var t_id := target.id if target != null else -1
		var t_dev := target.development_level if target != null else 0
		var t_inf := target.infrastructure if target != null else 0
		var def_fid_detail := str(result.get("defender_formation_id", ""))
		var att_fid_detail := str(attacker.formation_id if attacker else fid)
		# Pass unit_id so equipment-aware combat stats (has_shortages) match estimate/assault path.
		result["attacker_power_detail"] = _resolver.get_effective_combat_power(
			att_fid_detail, att_fid_detail, att_fid_detail, t_terr, t_id, t_dev, t_inf
		)
		result["defender_power_detail"] = _resolver.get_effective_combat_power(
			def_fid_detail, def_fid_detail, def_fid_detail, t_terr, t_id, t_dev, t_inf
		)

	apply_combat_outcome(result, fid, from_pid)
	battle_resolved.emit(result)

	# Unit combat log BEFORE AAR (so logs populated when panel pulls from Formation); space note
	# Space ground integration note for AAR/tips
	if result.get("space_strike_bonus", 0.0) > 0.05:
		print("[BATTLEMANAGER SPACE] Orbital strike active in assault: guided munitions edge applied (costly to maintain, not instant win)")
	# Unit combat log: record for involved units (like leaders). Only most important factors.
	_log_unit_combat(fid, from_pid, target_province_id, result, "attacker")
	if result.has("defender_formation_id"):
		_log_unit_combat(str(result.get("defender_formation_id", "")), target_province_id, from_pid, result, "defender")

	# Snapshot logs into result for AAR (even if deferred timing)
	var logs_snap := {}
	if typeof(LeaderManager) != TYPE_NIL:
		var fa := LeaderManager.get_formation(fid) if not fid.is_empty() else null
		if fa != null and "combat_log" in fa:
			logs_snap["attacker"] = fa.combat_log.duplicate()
		var fdid := str(result.get("defender_formation_id", ""))
		var fd := LeaderManager.get_formation(fdid) if not fdid.is_empty() else null
		if fd != null and "combat_log" in fd:
			logs_snap["defender"] = fd.combat_log.duplicate()
	result["combat_logs"] = logs_snap

	# Auto AAR for player if involved (accessible panel) - now after logs
	if str(result.get("attacker_tag","")) == "player" or str(result.get("defender_tag","")) == "player":
		var debug_aar: Node = get_tree().get_first_node_in_group("debug_overlay") if get_tree() else null
		if debug_aar != null and debug_aar.has_method("show_battle_aar"):
			debug_aar.call_deferred("show_battle_aar", result)

	return {"success": true, "result": result}


## ---------------------------------------------------------------------------
## Multi-day battles (player / play-strip / map confirm). execute stays one-shot.
## ---------------------------------------------------------------------------

## LeaderManager-first station write (capture + hops). Not SupplyManager alone.
func station_formation_on_province(
	formation_id: String,
	province_id: int,
	country_tag: String,
) -> Dictionary:
	if formation_id.is_empty() or province_id < 0:
		return {"ok": false, "reason": "bad args"}
	var tag := country_tag.strip_edges().to_upper()
	var moved := false
	if typeof(FormationMovement) != TYPE_NIL:
		var res: Dictionary = FormationMovement.move_formation_to_province(
			formation_id, province_id, tag,
		)
		moved = bool(res.get("ok", false))
	elif typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("move_formation_to_province"):
		var res2: Dictionary = SupplyManager.move_formation_to_province(
			formation_id, province_id, tag,
		)
		moved = bool(res2.get("ok", false))
	if typeof(LeaderManager) != TYPE_NIL:
		var f: Formation = LeaderManager.get_formation(formation_id)
		if f != null:
			f.stationed_province_id = province_id
		else:
			return {"ok": false, "reason": "unknown formation", "moved_primitive": moved}
	if not moved and typeof(SupplyManager) != TYPE_NIL:
		SupplyManager.division_deployments[formation_id] = {
			"province_id": province_id,
			"country_tag": tag,
			"order_type": "move_to_province",
		}
	return {
		"ok": true,
		"formation_id": formation_id,
		"province_id": province_id,
		"moved_primitive": moved,
	}


## Player-path multi-day battle. Capture only on break/retreat via apply_province_capture.
func start_province_battle(
	attacker_tag: String,
	target_province_id: int,
	from_province_id: int = -1,
	formation_id: String = "",
) -> Dictionary:
	_ensure_battle_day_hook()
	var can: Dictionary = can_assault_province(
		attacker_tag, target_province_id, from_province_id, formation_id
	)
	if not bool(can.get("ok", false)):
		return {"success": false, "reason": can.get("reason", "Cannot assault")}

	var tag := str(can.get("attacker_tag", attacker_tag)).strip_edges().to_upper()
	var from_pid := int(can.get("from_province_id", from_province_id))
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		fid = str(can.get("formation_id", ""))
	if fid.is_empty():
		return {"success": false, "reason": "No attacker formation"}
	var target: Province = MapManager.get_province(target_province_id) if typeof(MapManager) != TYPE_NIL else null
	if target == null:
		return {"success": false, "reason": "Target province missing"}
	var def_tag := str(can.get("defender_tag", "")).strip_edges().to_upper()
	if def_tag.is_empty():
		def_tag = _province_defender_tag(target)

	# 1v1 theater: block same edge, same target hex, attacker fid, or live defender fid already engaged.
	# Prevents double org/str ticks on a shared Formation and sticky is_in_combat clears.
	if not get_battle_at(target_province_id).is_empty():
		return {"success": false, "reason": "Province already under assault"}
	for bid_v in _battles.keys():
		var existing: Dictionary = _battles[bid_v] as Dictionary
		if str(existing.get("status", "")) != "engaging":
			continue
		if int(existing.get("from_pid", -1)) == from_pid and int(existing.get("target_pid", -1)) == target_province_id:
			return {"success": false, "reason": "Battle already engaging on this edge", "battle_id": str(bid_v)}
		if _battle_lists_fid(existing, fid):
			return {"success": false, "reason": "Formation already in battle", "battle_id": str(bid_v)}

	var att_form: Formation = null
	if typeof(LeaderManager) != TYPE_NIL:
		att_form = LeaderManager.get_formation(fid)
	if att_form == null:
		att_form = _build_attacker_formation(fid, tag, from_pid)
	# Keep station on from_pid during engage.
	if "stationed_province_id" in att_form:
		att_form.stationed_province_id = from_pid

	var def_form: Formation = _build_defender_formation(target, def_tag)
	var def_is_synthetic := true
	var def_fid := ""
	if typeof(LeaderManager) != TYPE_NIL and not str(def_form.formation_id).is_empty():
		var live_def: Formation = LeaderManager.get_formation(str(def_form.formation_id))
		if live_def != null:
			def_form = live_def
			def_is_synthetic = false
			def_fid = str(live_def.formation_id)
	if def_is_synthetic:
		# Battle-local garrison — do not register on LeaderManager; keep on defender_forms.
		def_fid = ""
	# Live defender already in another battle → no shared Form ref double-damage.
	if not def_fid.is_empty():
		for bid2 in _battles.keys():
			var ex2: Dictionary = _battles[bid2] as Dictionary
			if str(ex2.get("status", "")) != "engaging":
				continue
			if _battle_lists_fid(ex2, def_fid):
				return {
					"success": false,
					"reason": "Defender already in battle",
					"battle_id": str(bid2),
					"defender_formation_id": def_fid,
				}

	var start_day := 0
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		start_day = int(TimeManager.get_total_days_elapsed())

	_battle_seq += 1
	var battle_id := "b_%d_%d_%s_%d" % [from_pid, target_province_id, fid, _battle_seq]
	var att_fids: PackedStringArray = PackedStringArray([fid])
	var def_fids: PackedStringArray = PackedStringArray()
	if not def_fid.is_empty():
		def_fids.append(def_fid)

	var battle := {
		"battle_id": battle_id,
		"attacker_tag": tag,
		"defender_tag": def_tag,
		"attacker_fids": att_fids,
		"defender_fids": def_fids,
		"attacker_forms": [att_form],
		"defender_forms": [def_form],
		"from_pid": from_pid,
		"target_pid": target_province_id,
		"start_day": start_day,
		"days_elapsed": 0,
		"status": "engaging",
		"last_slice": {},
		"defender_is_synthetic": def_is_synthetic,
		"attacker_formation_id": fid,
		"defender_formation_id": def_fid,
	}
	_battles[battle_id] = battle

	if "is_in_combat" in att_form:
		att_form.is_in_combat = true
	if not def_is_synthetic and def_form != null and "is_in_combat" in def_form:
		def_form.is_in_combat = true

	var context := {
		"battle_id": battle_id,
		"attacker_tag": tag,
		"defender_tag": def_tag,
		"target_province_id": target_province_id,
		"from_province_id": from_pid,
		"attacker_formation_id": fid,
		"defender_formation_id": def_fid,
		"multi_day": true,
	}
	battle_started.emit(context)
	print(
		"[BATTLE START] id=%s %s %s@%d → %s@%d (synthetic_def=%s)"
		% [battle_id, fid, tag, from_pid, def_tag, target_province_id, str(def_is_synthetic)]
	)
	return {
		"success": true,
		"battle_id": battle_id,
		"status": "engaging",
		"battle": battle,
		"result": {
			"winner": "",
			"outcome": "engaging",
			"province_control_change": false,
			"attacker_tag": tag,
			"defender_tag": def_tag,
			"target_province_id": target_province_id,
			"from_province_id": from_pid,
			"attacker_formation_id": fid,
			"defender_formation_id": def_fid,
			"multi_day": true,
		},
	}


func get_battle_at(target_pid: int) -> Dictionary:
	for bid in _battles.keys():
		var b: Dictionary = _battles[bid] as Dictionary
		if str(b.get("status", "")) != "engaging":
			continue
		if int(b.get("target_pid", -1)) == target_pid:
			return b.duplicate(true)
	return {}


func get_battle_for_formation(formation_id: String) -> Dictionary:
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		return {}
	for bid in _battles.keys():
		var b: Dictionary = _battles[bid] as Dictionary
		if str(b.get("status", "")) != "engaging":
			continue
		if _battle_lists_fid(b, fid):
			return b.duplicate(true)
	return {}


func is_formation_in_battle(formation_id: String) -> bool:
	return not get_battle_for_formation(formation_id).is_empty()


## Owner flip + station + displace + notify. No damage / equip write-off.
func apply_province_capture(
	result: Dictionary,
	attacker_formation_id: String,
	from_province_id: int,
) -> void:
	var target_pid := int(result.get("target_province_id", result.get("province_id", -1)))
	var attacker_tag := str(result.get("attacker_tag", "")).strip_edges().to_upper()
	if target_pid < 0 or attacker_tag.is_empty() or typeof(MapManager) == TYPE_NIL:
		return
	result["province_control_change"] = true
	result["winner"] = "attacker"
	MapManager.update_province_owner(target_pid, attacker_tag, attacker_tag, false)
	if not attacker_formation_id.is_empty():
		station_formation_on_province(attacker_formation_id, target_pid, attacker_tag)
	_displace_defender_from_captured_province(result, target_pid)
	_notify_map_refresh(
		target_pid,
		int(result.get("from_province_id", from_province_id)),
		int(result.get("retreat_province_id", -1)),
	)
	_post_battle_news(result, true)


func withdraw_from_battle(formation_id: String) -> Dictionary:
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		return {"ok": false, "reason": "no formation"}
	var battle_id := ""
	var battle: Dictionary = {}
	for bid in _battles.keys():
		var b: Dictionary = _battles[bid] as Dictionary
		if str(b.get("status", "")) != "engaging":
			continue
		if _battle_lists_fid(b, fid):
			battle_id = str(bid)
			battle = b
			break
	if battle_id.is_empty():
		return {"ok": false, "reason": "not in battle"}
	_end_battle(battle_id, "retreat")
	print("[BATTLE END] id=%s status=retreat (withdraw %s)" % [battle_id, fid])
	return {
		"ok": true,
		"battle_id": battle_id,
		"status": "retreat",
		"formation_id": fid,
		"captured": false,
		"from_pid": int(battle.get("from_pid", -1)),
		"target_pid": int(battle.get("target_pid", -1)),
	}


func tick_battles_for_day() -> Dictionary:
	if _battles.is_empty():
		_battle_tick_rr = 0
		return {"ok": true, "ticked": 0, "ended": 0, "active": 0}
	var ticked := 0
	var ended := 0
	# Collect engaging ids (stable sort) then round-robin so budget never starves a row forever.
	var ids: Array = []
	var end_ids: Array[String] = []
	for bid_v in _battles.keys():
		var bid0 := str(bid_v)
		var b0: Dictionary = _battles[bid0] as Dictionary
		if str(b0.get("status", "")) != "engaging":
			end_ids.append(bid0)
		else:
			ids.append(bid0)
	ids.sort()
	var n := ids.size()
	if n == 0:
		for eid in end_ids:
			if _battles.has(eid):
				_battles.erase(eid)
		return {"ok": true, "ticked": 0, "ended": 0, "active": 0}
	# When few battles, tick all; otherwise budget with rotating start index.
	var budget := n if n <= BATTLE_TICK_BUDGET else BATTLE_TICK_BUDGET
	if _battle_tick_rr < 0 or _battle_tick_rr >= n:
		_battle_tick_rr = 0
	var start_i := _battle_tick_rr
	for k in range(n):
		if ticked >= budget:
			break
		var i := (start_i + k) % n
		var battle_id := str(ids[i])
		if not _battles.has(battle_id):
			continue
		var battle: Dictionary = _battles[battle_id] as Dictionary
		if str(battle.get("status", "")) != "engaging":
			continue
		ticked += 1
		var term := _tick_one_battle(battle_id, battle)
		if not term.is_empty():
			ended += 1
	# Advance RR so next day starts after this window (fairness when n > budget).
	_battle_tick_rr = (start_i + budget) % maxi(n, 1)
	for eid in end_ids:
		if _battles.has(eid) and str((_battles[eid] as Dictionary).get("status", "")) != "engaging":
			_battles.erase(eid)
	return {
		"ok": true,
		"ticked": ticked,
		"ended": ended,
		"active": _battles.size(),
		"rr": _battle_tick_rr,
	}


func _tick_one_battle(battle_id: String, battle: Dictionary) -> String:
	var from_pid := int(battle.get("from_pid", -1))
	var target_pid := int(battle.get("target_pid", -1))
	var att_forms: Array = battle.get("attacker_forms", []) as Array
	var def_forms: Array = battle.get("defender_forms", []) as Array
	var att_form: Formation = att_forms[0] as Formation if not att_forms.is_empty() else null
	var def_form: Formation = def_forms[0] as Formation if not def_forms.is_empty() else null
	var tag := str(battle.get("attacker_tag", "")).strip_edges().to_upper()
	var def_tag := str(battle.get("defender_tag", "")).strip_edges().to_upper()
	var fid := str(battle.get("attacker_formation_id", ""))
	var def_fid := str(battle.get("defender_formation_id", ""))
	var def_synth := bool(battle.get("defender_is_synthetic", false))

	# Attacker left the edge → retreat, no capture.
	if att_form == null or not is_instance_valid(att_form):
		_end_battle(battle_id, "retreat")
		return "retreat"
	var att_station := int(att_form.stationed_province_id) if "stationed_province_id" in att_form else -1
	if att_station != from_pid and att_station != target_pid:
		_end_battle(battle_id, "retreat")
		return "retreat"
	if not _provinces_adjacent(from_pid, target_pid) and att_station != target_pid:
		_end_battle(battle_id, "retreat")
		return "retreat"

	# Empty defender (displaced) → capture.
	if def_form == null or not is_instance_valid(def_form):
		var empty_res := _battle_capture_result(battle, "retreat")
		apply_province_capture(empty_res, fid, from_pid)
		_end_battle(battle_id, "captured")
		return "captured"
	if not def_synth:
		var def_station := int(def_form.stationed_province_id) if "stationed_province_id" in def_form else -1
		if def_station != target_pid:
			var left_res := _battle_capture_result(battle, "retreat")
			apply_province_capture(left_res, fid, from_pid)
			_end_battle(battle_id, "captured")
			return "captured"

	var from_prov: Province = MapManager.get_province(from_pid) if typeof(MapManager) != TYPE_NIL else null
	var target: Province = MapManager.get_province(target_pid) if typeof(MapManager) != TYPE_NIL else null
	var att_power := _slice_power_from_form(att_form, from_prov if from_prov else target, ATTACKER_INITIATIVE)
	var def_power := _slice_power_from_form(def_form, target, 0.0)
	# Optional weather/settlement flavor only — never use resolve_combat province_control_change.
	if target != null and target.settlement_level > 0.05:
		def_power *= clampf(1.0 + target.settlement_level * 0.025, 1.0, 1.25)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_river_border") and MapManager.has_river_border(target_pid):
		def_power *= 1.05

	var hi := maxf(att_power, def_power)
	var m := 0.0
	if hi > 0.0:
		m = absf(att_power - def_power) / hi
	var att_wins_slice := att_power >= def_power

	var loser_org := 0.12 + 0.08 * m
	var winner_org := 0.04 + 0.02 * (1.0 - m)
	var loser_str := 0.10 + 0.06 * m
	var winner_str := 0.03 + 0.02 * (1.0 - m)

	var att_org_before := float(att_form.organization) if "organization" in att_form else 1.0
	var att_str_before := float(att_form.strength) if "strength" in att_form else 1.0
	var def_org_before := float(def_form.organization) if "organization" in def_form else 1.0
	var def_str_before := float(def_form.strength) if "strength" in def_form else 1.0

	if att_wins_slice:
		att_form.organization = att_org_before - winner_org
		att_form.strength = att_str_before - winner_str
		def_form.organization = def_org_before - loser_org
		def_form.strength = def_str_before - loser_str
	else:
		att_form.organization = att_org_before - loser_org
		att_form.strength = att_str_before - loser_str
		def_form.organization = def_org_before - winner_org
		def_form.strength = def_str_before - winner_str

	# Pre-clamp break tests.
	var att_org_raw := float(att_form.organization)
	var att_str_raw := float(att_form.strength)
	var def_org_raw := float(def_form.organization)
	var def_str_raw := float(def_form.strength)

	var days := int(battle.get("days_elapsed", 0)) + 1
	battle["days_elapsed"] = days
	battle["last_slice"] = {
		"day": days,
		"att_power": att_power,
		"def_power": def_power,
		"m": m,
		"att_org": att_org_raw,
		"def_org": def_org_raw,
		"att_str": att_str_raw,
		"def_str": def_str_raw,
		"att_wins_slice": att_wins_slice,
	}
	_battles[battle_id] = battle

	print(
		"[BATTLE TICK] id=%s day=%d att_org=%.3f def_org=%.3f att=%.2f def=%.2f"
		% [battle_id, days, att_org_raw, def_org_raw, att_power, def_power]
	)
	battle_day_ticked.emit(battle)
	_notify_battle_day_ui(from_pid, target_pid, battle)

	# Live fids only: light equipment write-off from strength drop.
	if not fid.is_empty():
		_apply_combat_equipment_loss_for_formation(fid, att_str_before, maxf(att_str_raw, 0.01), att_wins_slice, false)
	if not def_synth and not def_fid.is_empty():
		_apply_combat_equipment_loss_for_formation(def_fid, def_str_before, maxf(def_str_raw, 0.01), not att_wins_slice, false)

	var terminal := ""
	if def_org_raw <= BATTLE_ORG_BREAK or def_str_raw <= BATTLE_STR_BREAK:
		terminal = "defender_broke"
	elif att_org_raw <= BATTLE_ORG_BREAK or att_str_raw <= BATTLE_ATT_STR_BREAK:
		terminal = "attacker_broke"
	elif days >= BATTLE_MAX_DAYS:
		terminal = "prolonged_stalemate"

	# Clamp survivors after break test (att str floor 0.35; def break floor 0.30).
	att_form.organization = clampf(att_org_raw, BATTLE_ORG_BREAK, 1.0)
	att_form.strength = clampf(att_str_raw, BATTLE_ATT_STR_FLOOR, 1.0)
	def_form.organization = clampf(def_org_raw, BATTLE_ORG_BREAK, 1.0)
	def_form.strength = clampf(def_str_raw, BATTLE_DEF_STR_BREAK, 1.0)
	if "readiness" in att_form:
		att_form.readiness = clampf(float(att_form.readiness) - (0.03 if att_wins_slice else 0.06), 0.28, 1.0)
	if "readiness" in def_form:
		def_form.readiness = clampf(float(def_form.readiness) - (0.06 if att_wins_slice else 0.03), 0.28, 1.0)

	if terminal == "defender_broke":
		var cap := _battle_capture_result(battle, "defender_broke")
		apply_province_capture(cap, fid, from_pid)
		_end_battle(battle_id, "defender_broke")
		return "defender_broke"
	if terminal == "attacker_broke":
		_end_battle(battle_id, "attacker_broke")
		return "attacker_broke"
	if terminal == "prolonged_stalemate":
		_end_battle(battle_id, "prolonged_stalemate")
		return "prolonged_stalemate"
	return ""


func _battle_capture_result(battle: Dictionary, outcome: String) -> Dictionary:
	return {
		"province_control_change": true,
		"winner": "attacker",
		"attacker_tag": str(battle.get("attacker_tag", "")),
		"defender_tag": str(battle.get("defender_tag", "")),
		"attacker_formation_id": str(battle.get("attacker_formation_id", "")),
		"defender_formation_id": str(battle.get("defender_formation_id", "")),
		"target_province_id": int(battle.get("target_pid", -1)),
		"from_province_id": int(battle.get("from_pid", -1)),
		"retreat_province_id": -1,
		"outcome": outcome,
	}


func _end_battle(battle_id: String, status: String) -> void:
	if not _battles.has(battle_id):
		return
	var battle: Dictionary = _battles[battle_id] as Dictionary
	battle["status"] = status
	# Erase first so _formation_still_in_other_battle does not see this row.
	_battles.erase(battle_id)
	_clear_battle_combat_flags(battle, battle_id)
	var toast_status := status
	var target_pid := int(battle.get("target_pid", -1))
	var from_pid := int(battle.get("from_pid", -1))
	print("[BATTLE END] id=%s status=%s day=%d" % [battle_id, status, int(battle.get("days_elapsed", 0))])
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		var msg := "Battle ended · %s" % toast_status
		if status == "defender_broke" or status == "captured":
			msg = "Province taken · defender broke"
		elif status == "attacker_broke":
			msg = "Assault broken · regroup"
		elif status == "retreat":
			msg = "Forces withdrew · no capture"
		elif status == "prolonged_stalemate":
			msg = "Stalemate · assault stalled"
		LeaderEventUI.show_toast(msg, 3.5, false, true)
	battle_resolved.emit({
		"battle_id": battle_id,
		"status": status,
		"target_province_id": target_pid,
		"from_province_id": from_pid,
		"multi_day": true,
		"province_control_change": status in ["defender_broke", "captured"],
	})


## Clear is_in_combat only when the formation is not still listed in another engaging row.
func _clear_battle_combat_flags(battle: Dictionary, ended_battle_id: String = "") -> void:
	var fids: Array[String] = []
	for key in ["attacker_formation_id", "defender_formation_id"]:
		var id := str(battle.get(key, "")).strip_edges()
		if not id.is_empty() and not fids.has(id):
			fids.append(id)
	for arr_key in ["attacker_fids", "defender_fids"]:
		for x in battle.get(arr_key, []):
			var sid := str(x).strip_edges()
			if not sid.is_empty() and not fids.has(sid):
				fids.append(sid)
	for arr_key2 in ["attacker_forms", "defender_forms"]:
		for f_any in battle.get(arr_key2, []):
			var f: Formation = f_any as Formation
			if f == null or not is_instance_valid(f):
				continue
			var ffid := str(f.formation_id) if "formation_id" in f else ""
			if not ffid.is_empty() and not fids.has(ffid):
				fids.append(ffid)
			# Synthetic battle-local forms: always clear (not shared across rows).
			if ffid.is_empty() and "is_in_combat" in f:
				f.is_in_combat = false
	for id2 in fids:
		if _formation_still_in_other_battle(id2, ended_battle_id):
			continue
		if typeof(LeaderManager) != TYPE_NIL:
			var lf: Formation = LeaderManager.get_formation(id2)
			if lf != null and "is_in_combat" in lf:
				lf.is_in_combat = false
		# Also clear any in-memory form refs on this ended battle that match.
		for arr_key3 in ["attacker_forms", "defender_forms"]:
			for f_any2 in battle.get(arr_key3, []):
				var f2: Formation = f_any2 as Formation
				if f2 == null or not is_instance_valid(f2):
					continue
				var f2id := str(f2.formation_id) if "formation_id" in f2 else ""
				if f2id == id2 and "is_in_combat" in f2:
					f2.is_in_combat = false


func _formation_still_in_other_battle(formation_id: String, exclude_battle_id: String = "") -> bool:
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		return false
	for bid in _battles.keys():
		if str(bid) == exclude_battle_id:
			continue
		var b: Dictionary = _battles[bid] as Dictionary
		if str(b.get("status", "")) != "engaging":
			continue
		if _battle_lists_fid(b, fid):
			return true
	return false


func _battle_lists_fid(battle: Dictionary, formation_id: String) -> bool:
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		return false
	if str(battle.get("attacker_formation_id", "")) == fid:
		return true
	if str(battle.get("defender_formation_id", "")) == fid:
		return true
	for x in battle.get("attacker_fids", []):
		if str(x) == fid:
			return true
	for y in battle.get("defender_fids", []):
		if str(y) == fid:
			return true
	return false


func _slice_power_from_form(form: Formation, province: Province, initiative: float) -> float:
	if form == null:
		return 0.0
	var fid := str(form.formation_id) if "formation_id" in form else ""
	var tag := str(form.country_tag).strip_edges().to_upper() if "country_tag" in form else ""
	var soft := 0.0
	var hard := 0.0
	if _resolver != null and not fid.is_empty():
		var terrain: String = province.terrain if province != null and province.terrain != "" else "plains"
		var pid := province.id if province != null else -1
		var dev := province.development_level if province != null else -1
		var infra := province.infrastructure if province != null else -1
		var stats: Dictionary = _resolver.get_effective_combat_power(
			fid, fid, fid, terrain, pid, dev, infra,
		)
		soft = float(stats.get("soft_attack", 0.0))
		hard = float(stats.get("hard_attack", 0.0))
	if soft <= 0.0 and hard <= 0.0:
		# Synthetic garrison fallback so empty-hex defenders still resist.
		soft = 0.7
		hard = 0.05
	var org := float(form.organization) if "organization" in form else 1.0
	var strength := float(form.strength) if "strength" in form else 1.0
	var xp := float(form.combat_experience) if "combat_experience" in form else 48.0
	var xp_mult := lerpf(0.85, 1.15, clampf(xp / 100.0, 0.0, 1.0))
	return (soft + 1.6 * hard) * maxf(org, 0.0) * maxf(strength, 0.0) * xp_mult + initiative


func _notify_battle_day_ui(from_pid: int, target_pid: int, battle: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for mr in tree.get_nodes_in_group("map_renderer"):
		if mr.has_method("flash_battle_day"):
			mr.call_deferred("flash_battle_day", [from_pid, target_pid], battle)
		elif mr.has_method("push_map_assault_marker"):
			mr.call_deferred("push_map_assault_marker", target_pid, "engage", 0.75)


func get_save_data() -> Dictionary:
	var battles_arr: Array = []
	for bid in _battles.keys():
		var b: Dictionary = _battles[bid] as Dictionary
		if str(b.get("status", "")) != "engaging":
			continue
		var def_org := 1.0
		var def_str := 1.0
		var def_rdy := 1.0
		var def_forms: Array = b.get("defender_forms", []) as Array
		if not def_forms.is_empty() and def_forms[0] is Formation:
			var df: Formation = def_forms[0] as Formation
			if df != null:
				def_org = float(df.organization) if "organization" in df else 1.0
				def_str = float(df.strength) if "strength" in df else 1.0
				def_rdy = float(df.readiness) if "readiness" in df else 1.0
		var att_fids_arr: Array = []
		for x in b.get("attacker_fids", []):
			att_fids_arr.append(str(x))
		var def_fids_arr: Array = []
		for y in b.get("defender_fids", []):
			def_fids_arr.append(str(y))
		battles_arr.append({
			"battle_id": str(b.get("battle_id", bid)),
			"attacker_tag": str(b.get("attacker_tag", "")),
			"defender_tag": str(b.get("defender_tag", "")),
			"attacker_fids": att_fids_arr,
			"defender_fids": def_fids_arr,
			"from_pid": int(b.get("from_pid", -1)),
			"target_pid": int(b.get("target_pid", -1)),
			"start_day": int(b.get("start_day", 0)),
			"days_elapsed": int(b.get("days_elapsed", 0)),
			"status": str(b.get("status", "engaging")),
			"attacker_formation_id": str(b.get("attacker_formation_id", "")),
			"defender_formation_id": str(b.get("defender_formation_id", "")),
			"defender_is_synthetic": bool(b.get("defender_is_synthetic", false)),
			"defender_org": def_org,
			"defender_str": def_str,
			"defender_rdy": def_rdy,
		})
	return {
		"battles": battles_arr,
		"battle_seq": _battle_seq,
	}


func apply_save_data(data: Dictionary) -> void:
	_battles.clear()
	_marches.clear()
	if data.is_empty():
		return
	_ensure_battle_day_hook()
	_battle_seq = int(data.get("battle_seq", 0))
	var arr: Array = data.get("battles", []) as Array
	for row_v in arr:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		var battle_id := str(row.get("battle_id", "")).strip_edges()
		if battle_id.is_empty():
			continue
		if str(row.get("status", "engaging")) != "engaging":
			continue
		var att_fid := str(row.get("attacker_formation_id", "")).strip_edges()
		if att_fid.is_empty():
			var af: Array = row.get("attacker_fids", []) as Array
			if not af.is_empty():
				att_fid = str(af[0])
		if att_fid.is_empty():
			continue
		# Missing live attacker fid → drop battle.
		var att_form: Formation = null
		if typeof(LeaderManager) != TYPE_NIL:
			att_form = LeaderManager.get_formation(att_fid)
		if att_form == null:
			continue
		var def_fid := str(row.get("defender_formation_id", "")).strip_edges()
		var def_synth := bool(row.get("defender_is_synthetic", false))
		var def_form: Formation = null
		if not def_synth and not def_fid.is_empty() and typeof(LeaderManager) != TYPE_NIL:
			def_form = LeaderManager.get_formation(def_fid)
			if def_form == null:
				# Live defender gone — drop.
				continue
		if def_form == null:
			def_synth = true
			def_form = Formation.new()
			def_form.formation_id = _garrison_template_for_country(str(row.get("defender_tag", "")))
			def_form.country_tag = str(row.get("defender_tag", "")).strip_edges().to_upper()
			def_form.formation_type = Formation.TYPE_GARRISON
			def_form.name = "%s Garrison" % def_form.country_tag
			def_form.stationed_province_id = int(row.get("target_pid", -1))
			def_form.organization = float(row.get("defender_org", 1.0))
			def_form.strength = float(row.get("defender_str", 1.0))
			def_form.readiness = float(row.get("defender_rdy", 1.0))
			def_fid = ""
		if "is_in_combat" in att_form:
			att_form.is_in_combat = true
		if not def_synth and def_form != null and "is_in_combat" in def_form:
			def_form.is_in_combat = true
		var att_fids: PackedStringArray = PackedStringArray([att_fid])
		var def_fids: PackedStringArray = PackedStringArray()
		if not def_fid.is_empty():
			def_fids.append(def_fid)
		_battles[battle_id] = {
			"battle_id": battle_id,
			"attacker_tag": str(row.get("attacker_tag", "")).strip_edges().to_upper(),
			"defender_tag": str(row.get("defender_tag", "")).strip_edges().to_upper(),
			"attacker_fids": att_fids,
			"defender_fids": def_fids,
			"attacker_forms": [att_form],
			"defender_forms": [def_form],
			"from_pid": int(row.get("from_pid", -1)),
			"target_pid": int(row.get("target_pid", -1)),
			"start_day": int(row.get("start_day", 0)),
			"days_elapsed": int(row.get("days_elapsed", 0)),
			"status": "engaging",
			"last_slice": {},
			"defender_is_synthetic": def_synth,
			"attacker_formation_id": att_fid,
			"defender_formation_id": def_fid,
		}


	var march_list: Array = data.get("marches", [])
	if march_list is Array:
		for item in march_list:
			if not (item is Dictionary):
				continue
			var row: Dictionary = item
			var fid := str(row.get("formation_id", ""))
			if fid.is_empty():
				continue
			_marches[fid] = row.duplicate(true)
	_march_order_seq = int(data.get("march_order_seq", _march_order_seq))

func _log_unit_combat(formation_id: String, province: int, other_province: int, result: Dictionary, role: String) -> void:
	if formation_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return
	var fm = LeaderManager.get_formation(formation_id) if LeaderManager.has_method("get_formation") else null
	if fm == null or not fm.has_method("log_combat"):
		return
	var date := ""
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_date_string"):
		date = TimeManager.call("get_current_date_string")
	elif typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
		var mo := int(TimeManager.get_current_month()) if TimeManager.has_method("get_current_month") else 1
		date = "%04d-%02d" % [int(TimeManager.get_current_year()), mo]
	elif typeof(GameData) != TYPE_NIL and GameData.has_method("get_current_year"):
		var gmo := int(GameData.get_current_month()) if GameData.has_method("get_current_month") else 1
		date = "%04d-%02d" % [int(GameData.get_current_year()), gmo]
	else:
		date = "1936-01"
	var winner := str(result.get("winner", ""))
	var res_str := "win" if winner == (result.get("attacker_tag", "") if role=="attacker" else result.get("defender_tag", "")) else "loss"
	var captured := bool(result.get("province_control_change", false))
	if captured:
		res_str = "captured" if role == "defender" else "victory"
	# Key impactful factors only (clear, not overwhelming)
	var factors: Array[String] = []
	if float(result.get("attacker_power", 0)) < float(result.get("defender_power", 0)) * 0.7:
		factors.append("our_forces_outnumbered" if role=="attacker" else "enemy_outnumbered")
	if bool(result.get("encircled", false)):
		factors.append("forces_encircled" if role=="attacker" else "enemy_surrounded")
	if float(result.get("supply_mod", 1.0)) < 0.6:
		factors.append("out_of_supply")
	if bool(result.get("air_superiority_attacker", false)):
		factors.append("we_have_air_superiority" if role=="attacker" else "enemy_air_supremacy")
	var adl := str(result.get("air_dominance_level", ""))
	if adl == "full":
		factors.append("overwhelming_air_superiority" if role=="attacker" else "enemy_air_dominance_full")
	elif adl == "partial":
		factors.append("partial_air_advantage" if role=="attacker" else "enemy_partial_air_advantage")
	elif result.get("enemy_air", false) or adl == "none":
		factors.append("enemy_air_presence_limits_ops")
	if result.get("space_strike_bonus", 0.0) > 0.0 or "space" in str(result.get("special","")) or result.get("space_support_active", false):
		factors.append("orbital_strike_support" if role=="attacker" else "enemy_orbital_strike")
		factors.append("space_guided_munitions_precision")
	if "space_capable" in str(result.get("space_wiring", {})):
		factors.append("space_capable_unit_enhanced_by_orbital")
	if "amphib" in str(result.get("special", "")):
		factors.append("amphibious_assault_extra_org_loss")
	if float(result.get("fort_mod", 1.0)) > 1.1:
		factors.append("enemy_fortified" if role=="attacker" else "we_are_fortified_dug_in")
	if result.get("counterattack", false):
		factors.append("enemy_counterattacking")
	# Leader impact
	var ldr := str(result.get("leader_bonus", ""))
	if not ldr.is_empty():
		factors.append("leader_impact_" + ldr.to_lower().replace(" ", "_"))
	var outcome := "Casualties: %s vs %s" % [result.get("attacker_casualties", "?"), result.get("defender_casualties", "?")]
	fm.log_combat(date, province, res_str, factors, str(result.get("leader_name", "")), outcome)
	print("[UNIT COMBAT LOG] %s logged combat at %d: %s factors=%s" % [formation_id, province, res_str, factors])


## World-class enhancement: chain/flanking assault helper for multi-province operations.
## After a successful capture, attempts follow-on assault on an adjacent enemy province from the
## **captured** staging province (attacker station / control after post-capture station update).
## Used by AI demo / harness for better multi-province feel. Returns list of executed results.
func execute_chain_assault_or_flank(
	attacker_tag: String,
	initial_target_pid: int,
	from_pid: int = -1,
	max_chain: int = 2
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var tag := attacker_tag.strip_edges().to_upper()
	var bm_res := execute_province_assault(tag, initial_target_pid, from_pid)
	if not bool(bm_res.get("success", false)):
		return results
	results.append(bm_res)
	# If captured, try up to max_chain adjacent enemy targets from the new (captured) position.
	var first_result: Dictionary = {}
	var captured := false
	if bm_res.has("result") and typeof(bm_res.get("result")) == TYPE_DICTIONARY:
		first_result = bm_res["result"] as Dictionary
		captured = bool(first_result.get("province_control_change", false))
	if not captured or typeof(MapManager) == TYPE_NIL or max_chain <= 0:
		return results
	# Stage follow-ons from the captured province id (post-capture station), not the old border.
	var current_from := int(first_result.get("target_province_id", initial_target_pid))
	if current_from < 0:
		current_from = initial_target_pid
	var adjs: Array = []
	if MapManager.has_method("get_adjacent_provinces"):
		adjs = MapManager.get_adjacent_provinces(current_from, true)
	var chained := 0
	for aidv in adjs:
		if chained >= max_chain:
			break
		var aid := int(aidv)
		if aid == current_from or aid < 0:
			continue
		var p: Province = MapManager.get_province(aid) if MapManager.has_method("get_province") else null
		if p == null or p.is_sea:
			continue
		# Enemy-controlled land only (controller preferred after occupation updates).
		var ctrl := _province_controller_tag(p)
		if ctrl.is_empty() or ctrl == tag:
			continue
		var can2 := can_assault_province(tag, aid, current_from)
		if not bool(can2.get("ok", false)):
			continue
		# Prefer formation already identified at the captured staging (OOB / post-capture station).
		var follow_fid := str(can2.get("formation_id", "")).strip_edges()
		var follow: Dictionary = execute_province_assault(tag, aid, current_from, follow_fid)
		if not bool(follow.get("success", false)):
			continue
		results.append(follow)
		chained += 1
		# If follow-on also captured, advance staging for further chain steps.
		var follow_res: Dictionary = {}
		if follow.has("result") and typeof(follow.get("result")) == TYPE_DICTIONARY:
			follow_res = follow["result"] as Dictionary
		if bool(follow_res.get("province_control_change", false)):
			current_from = aid
		print(
			"[CHAIN/FLANK] Follow-on assault to %d from captured staging %d (step %d); multi-province campaign."
			% [aid, int(first_result.get("target_province_id", initial_target_pid)), chained]
		)
	return results


func _apply_combat_damage_to_formations(_result: Dictionary, _attacker_formation_id: String) -> void:
	# Damage application lives inline in apply_combat_outcome (org/rdy/strength).
	# Kept as a named hook so call sites / future extraction compile under strict Godot 4.7.
	pass


## Write off unit equipment after strength/org damage (ProductionManager unit stockpile).
## Losers take heavier equipment loss; winners light wear only if strength dropped.
func _apply_combat_equipment_loss_for_formation(
	formation_id: String,
	strength_before: float,
	strength_after: float,
	is_winner: bool,
	prolonged: bool = false,
) -> Dictionary:
	if formation_id.is_empty():
		return {}
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("apply_combat_equipment_loss"):
		return {}
	var before := maxf(strength_before, 0.01)
	var after := clampf(strength_after, 0.0, 1.0)
	var drop_frac := clampf(1.0 - (after / before), 0.0, 1.0)
	var severity := 0.0
	if is_winner:
		# Winners: light equipment wear only when strength actually dropped.
		severity = drop_frac * 0.35
		if severity < 0.08:
			return {}
	else:
		# Losers: meaningful write-off even if strength clamp softens the drop.
		severity = maxf(drop_frac, 0.4)
		severity = clampf(severity, 0.35, 0.95)
	if prolonged:
		severity *= 0.7
	return ProductionManager.apply_combat_equipment_loss(formation_id, severity)


func apply_combat_outcome(
	result: Dictionary,
	attacker_formation_id: String,
	from_province_id: int,
) -> void:
	var target_pid := int(result.get("target_province_id", result.get("province_id", -1)))
	var attacker_tag := str(result.get("attacker_tag", "")).strip_edges().to_upper()
	var captured := bool(result.get("province_control_change", false))
	var winner := str(result.get("winner", ""))
	# Assault/capture leaves the march path; cancel so next day hop does not yank the unit.
	if not attacker_formation_id.is_empty():
		cancel_march_order(attacker_formation_id)
	var def_fid_cancel := str(result.get("defender_formation_id", "")).strip_edges()
	if not def_fid_cancel.is_empty():
		cancel_march_order(def_fid_cancel)
	# Apply persistent org/readiness damage to the actual live formations (main loop combat now has lasting effects).
	_apply_combat_damage_to_formations(result, attacker_formation_id)

	# === Balance integration: apply persistent org/readiness/strength damage here (from BM as per design)
	# Loser heavier losses (strength hit), winner lighter org/rdy hit. Recovery via Supply daily (infra/supply mod).
	# Unit equipment on hand is also written off with damage (equip→fight→loss→stockpile rebuild loop).
	# This makes combat "have teeth", feeds AAR logs + inspector stationed units state.
	if typeof(LeaderManager) != TYPE_NIL:
		var att_f: Formation = LeaderManager.get_formation(attacker_formation_id) if not attacker_formation_id.is_empty() else null
		var def_fid := str(result.get("defender_formation_id", ""))
		var def_f: Formation = LeaderManager.get_formation(def_fid) if not def_fid.is_empty() else null
		var w := winner
		var prolonged := "prolonged" in str(result.get("outcome", "")).to_lower() or str(result.get("outcome", "")) in ["prolonged_attrition", "prolonged_stalemate"]
		var dmg_line := "[COMBAT DAMAGE] "
		if att_f != null:
			var is_win := (w == "attacker")
			var org_loss := 0.09 if is_win else 0.27
			var rdy_loss := 0.07 if is_win else 0.22
			if prolonged:
				org_loss *= 0.55  # prolonged fights (high org def, similar strength, urban/fort) last longer, less quick decisive damage
				rdy_loss *= 0.55
			var att_str_before := float(att_f.strength) if "strength" in att_f else 1.0
			att_f.organization = clampf(att_f.organization * (1.0 - org_loss + randf() * 0.04), 0.22, 1.0)
			att_f.readiness = clampf(att_f.readiness * (1.0 - rdy_loss + randf() * 0.04), 0.28, 1.0)
			if not is_win:
				att_f.strength = clampf(att_f.strength * (0.72 + randf() * 0.12), 0.35, 1.0)
			att_f.is_in_combat = true
			_apply_combat_equipment_loss_for_formation(
				attacker_formation_id, att_str_before, float(att_f.strength), is_win, prolonged
			)
			dmg_line += "ATT %s: org=%.2f rdy=%.2f str=%.2f ; " % [attacker_formation_id, att_f.organization, att_f.readiness, att_f.strength]
		if def_f != null:
			var is_win_def := (w == "defender")
			var org_loss_d := 0.26 if not is_win_def else 0.10
			var rdy_loss_d := 0.21 if not is_win_def else 0.08
			if prolonged:
				org_loss_d *= 0.5
				rdy_loss_d *= 0.5
			var def_str_before := float(def_f.strength) if "strength" in def_f else 1.0
			def_f.organization = clampf(def_f.organization * (1.0 - org_loss_d + randf() * 0.04), 0.22, 1.0)
			def_f.readiness = clampf(def_f.readiness * (1.0 - rdy_loss_d + randf() * 0.04), 0.28, 1.0)
			if not is_win_def:
				def_f.strength = clampf(def_f.strength * (0.62 + randf() * 0.12), 0.30, 1.0)
			def_f.is_in_combat = true
			_apply_combat_equipment_loss_for_formation(
				def_fid, def_str_before, float(def_f.strength), is_win_def, prolonged
			)
			dmg_line += "DEF %s: org=%.2f rdy=%.2f str=%.2f" % [def_fid, def_f.organization, def_f.readiness, def_f.strength]
		if att_f != null or def_f != null:
			print(dmg_line + (" (prolonged - reduced losses, lasts longer)" if prolonged else ""))
		# One-shot path: combat is over immediately — clear sticky is_in_combat.
		if att_f != null:
			att_f.is_in_combat = false
		if def_f != null:
			def_f.is_in_combat = false

	if captured and target_pid >= 0 and typeof(MapManager) != TYPE_NIL:
		MapManager.update_province_owner(target_pid, attacker_tag, attacker_tag, false)
		# Capture advances the attacker's land station onto the taken province so OOB /
		# can_assault / get_land_divisions see them on the new border (not still on from_pid).
		_station_attacker_on_captured_province(attacker_formation_id, target_pid, attacker_tag)
		# Defenders cannot remain stationed on a province they just lost.
		_displace_defender_from_captured_province(result, target_pid)
		_notify_map_refresh(
			int(result.get("target_province_id", target_pid)),
			int(result.get("from_province_id", from_province_id)),
			int(result.get("retreat_province_id", -1)),
		)
		_post_battle_news(result, true)
	elif winner == "attacker":
		_post_battle_news(result, false)
	elif winner == "defender":
		_post_battle_news(result, false)


## After ownership flips, station the assaulting land formation on the captured province.
func _station_attacker_on_captured_province(
	attacker_formation_id: String,
	target_pid: int,
	attacker_tag: String,
) -> void:
	# External station off the march edge — drop order before hop ticks re-path.
	cancel_march_order(attacker_formation_id)
	station_formation_on_province(attacker_formation_id, target_pid, attacker_tag)


func issue_march_order(
	formation_id: String,
	dest_pid: int,
	country_tag: String,
	instant: bool = false,
) -> Dictionary:
	var fid := formation_id.strip_edges()
	var tag := country_tag.strip_edges().to_upper()
	if fid.is_empty() or dest_pid < 0 or tag.is_empty():
		return {"ok": false, "reason": "bad args"}
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formation"):
		return {"ok": false, "reason": "LeaderManager unavailable"}
	var f: Formation = LeaderManager.get_formation(fid)
	if f == null:
		return {"ok": false, "reason": "unknown formation"}
	var f_tag := str(f.country_tag).strip_edges().to_upper() if "country_tag" in f else ""
	if not f_tag.is_empty() and f_tag != tag:
		return {"ok": false, "reason": "not your unit"}
	var from_pid := int(f.stationed_province_id) if "stationed_province_id" in f else -1
	if from_pid < 0:
		return {"ok": false, "reason": "no station"}
	if from_pid == dest_pid:
		return {"ok": true, "reason": "already there", "formation_id": fid, "path": [from_pid], "days_total": 0, "order_id": ""}
	if not _province_controlled_by(dest_pid, tag):
		return {"ok": false, "reason": "dest not controlled"}
	# Cancel re-issue to same dest.
	if _marches.has(fid):
		var existing: Dictionary = _marches[fid] as Dictionary
		if int(existing.get("dest_pid", -1)) == dest_pid:
			cancel_march_order(fid)
			return {"ok": true, "reason": "cancelled", "formation_id": fid, "cancelled": true}
	if _formation_in_active_battle(fid):
		return {"ok": false, "reason": "in battle"}
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("find_land_path"):
		return {"ok": false, "reason": "MapManager unavailable"}
	var path: Array = MapManager.find_land_path(from_pid, dest_pid, tag, MARCH_MAX_HOPS, true)
	if path.is_empty() or path.size() < 2:
		return {"ok": false, "reason": "no land path"}
	var path_ids: Array[int] = []
	for p in path:
		path_ids.append(int(p))
	if instant:
		var prev := from_pid
		for i in range(1, path_ids.size()):
			var hop_pid := path_ids[i]
			station_formation_on_province(fid, hop_pid, tag)
			_notify_map_refresh(hop_pid, prev)
			prev = hop_pid
		_marches.erase(fid)
		print("[MARCH] instant fid=%s path=%s" % [fid, str(path_ids)])
		return {
			"ok": true,
			"reason": "instant",
			"formation_id": fid,
			"path": path_ids,
			"days_total": 0,
			"order_id": "",
			"instant": true,
		}
	_march_order_seq += 1
	var order_id := "march_%d" % _march_order_seq
	var hours := _hours_per_hex_for_pid(path_ids[1] if path_ids.size() > 1 else dest_pid)
	var days_est := _estimate_march_days(path_ids)
	var order := {
		"order_id": order_id,
		"formation_id": fid,
		"tag": tag,
		"path": path_ids,
		"idx": 0,
		"dest_pid": dest_pid,
		"hours_per_hex": hours,
		"hours_acc": 0.0,
		"visual_t": 0.0,
	}
	_marches[fid] = order
	print("[MARCH] fid=%s path=%s days=%.1f order=%s" % [fid, str(path_ids), days_est, order_id])
	return {
		"ok": true,
		"reason": "marching",
		"formation_id": fid,
		"path": path_ids,
		"days_total": days_est,
		"order_id": order_id,
		"hexes": maxi(path_ids.size() - 1, 0),
	}


func cancel_march_order(formation_id: String) -> Dictionary:
	var fid := formation_id.strip_edges()
	if fid.is_empty() or not _marches.has(fid):
		return {"ok": false, "reason": "no march"}
	_marches.erase(fid)
	return {"ok": true, "formation_id": fid, "cancelled": true}


func get_march_order(formation_id: String) -> Dictionary:
	var fid := formation_id.strip_edges()
	if fid.is_empty() or not _marches.has(fid):
		return {}
	return (_marches[fid] as Dictionary).duplicate(true)


## Live view of active marches (fid → order). Read-only for callers except set_march_visual_t.
## Avoids deep-copy every renderer frame.
func get_active_marches() -> Dictionary:
	return _marches


func has_active_marches() -> bool:
	return not _marches.is_empty()


## Advance visual_t on an active march (renderer cosmetic; sim hops are day-authoritative).
func set_march_visual_t(formation_id: String, t: float) -> void:
	var fid := formation_id.strip_edges()
	if not _marches.has(fid):
		return
	var o: Dictionary = _marches[fid] as Dictionary
	o["visual_t"] = clampf(t, 0.0, 1.0)
	_marches[fid] = o


func tick_marches_for_day() -> Dictionary:
	if _marches.is_empty():
		return {"ok": true, "hops": 0, "arrived": 0, "active": 0, "cancelled": 0}
	var hops_n := 0
	var arrived_n := 0
	var cancelled_n := 0
	var done_fids: Array[String] = []
	for fid_v in _marches.keys():
		var fid := str(fid_v)
		var order: Dictionary = _marches[fid] as Dictionary
		var path: Array = order.get("path", []) as Array
		if path.size() < 2:
			done_fids.append(fid)
			continue
		var idx := int(order.get("idx", 0))
		if idx >= path.size() - 1:
			done_fids.append(fid)
			continue
		var tag := str(order.get("tag", "")).strip_edges().to_upper()
		# External station (capture, displace) left the path edge — drop order.
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
			var live: Formation = LeaderManager.get_formation(fid)
			if live != null and "stationed_province_id" in live:
				var live_pid := int(live.stationed_province_id)
				if live_pid != int(path[idx]):
					done_fids.append(fid)
					cancelled_n += 1
					print("[MARCH] cancel desync fid=%s station=%d path_idx=%d" % [fid, live_pid, int(path[idx])])
					continue
		var hours_acc := float(order.get("hours_acc", 0.0)) + 24.0
		var hours_need := float(order.get("hours_per_hex", MARCH_DEFAULT_HOURS_PER_HEX))
		if hours_need <= 0.0:
			hours_need = MARCH_DEFAULT_HOURS_PER_HEX
		order["hours_acc"] = hours_acc
		# May hop more than once if hours_per_hex is very low.
		var aborted := false
		while hours_acc >= hours_need and idx < path.size() - 1:
			hours_acc -= hours_need
			var old_pid := int(path[idx])
			idx += 1
			var new_pid := int(path[idx])
			# Own-land re-check: control may flip mid-march (AI capture, ownership change).
			if not _province_controlled_by(new_pid, tag):
				done_fids.append(fid)
				cancelled_n += 1
				aborted = true
				print("[MARCH] cancel lost-control fid=%s pid=%d tag=%s" % [fid, new_pid, tag])
				break
			station_formation_on_province(fid, new_pid, tag)
			# Pid-scoped icon update only — never full-board rebuild.
			_notify_map_refresh(new_pid, old_pid)
			hops_n += 1
			order["idx"] = idx
			order["visual_t"] = 0.0
			if idx >= path.size() - 1:
				arrived_n += 1
				done_fids.append(fid)
				print("[MARCH] arrived fid=%s pid=%d" % [fid, new_pid])
				break
			hours_need = _hours_per_hex_for_pid(int(path[idx + 1]))
			order["hours_per_hex"] = hours_need
		if aborted:
			continue
		order["hours_acc"] = hours_acc
		order["idx"] = idx
		if not done_fids.has(fid):
			_marches[fid] = order
	for df in done_fids:
		_marches.erase(df)
	return {
		"ok": true,
		"hops": hops_n,
		"arrived": arrived_n,
		"cancelled": cancelled_n,
		"active": _marches.size(),
	}


func _formation_in_active_battle(formation_id: String) -> bool:
	# No _battles rows yet (PR 5) → never block on this path alone.
	if _battles.is_empty():
		return false
	var fid := formation_id.strip_edges()
	for bid in _battles.keys():
		var b: Dictionary = _battles[bid] as Dictionary
		var status := str(b.get("status", "active")).to_lower()
		if status in ["ended", "resolved", "cancelled", "done"]:
			continue
		var atk: Array = b.get("attacker_fids", []) as Array
		var def: Array = b.get("defender_fids", []) as Array
		for x in atk:
			if str(x) == fid:
				return true
		for y in def:
			if str(y) == fid:
				return true
		# Single-fid fields
		if str(b.get("attacker_formation_id", "")) == fid:
			return true
		if str(b.get("defender_formation_id", "")) == fid:
			return true
	return false


func _hours_per_hex_for_pid(province_id: int) -> float:
	var h := MARCH_DEFAULT_HOURS_PER_HEX
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return h
	var p: Province = MapManager.get_province(province_id)
	if p == null:
		return h
	var terr := str(p.terrain).to_lower() if "terrain" in p else ""
	if terr in ["forest", "woods", "mountain", "mountains", "mtn", "hills", "alpine"]:
		h *= 1.5
	var infra := int(p.infrastructure) if "infrastructure" in p else 0
	if infra >= 6:
		h *= 0.75
	return h


func _estimate_march_days(path_ids: Array) -> float:
	if path_ids.size() < 2:
		return 0.0
	var total_h := 0.0
	for i in range(1, path_ids.size()):
		total_h += _hours_per_hex_for_pid(int(path_ids[i]))
	return total_h / 24.0



## After capture, defender land formations leave the lost province. Prefer adjacent friendly
## land still controlled by the defender; else any remaining friendly land; else clear station (-1).
func _displace_defender_from_captured_province(result: Dictionary, captured_pid: int) -> void:
	if captured_pid < 0 or typeof(LeaderManager) == TYPE_NIL:
		return
	var def_tag := str(result.get("defender_tag", "")).strip_edges().to_upper()
	var def_fid := str(result.get("defender_formation_id", "")).strip_edges()
	var retreat_pid := _pick_defender_retreat_province(captured_pid, def_tag)
	result["retreat_province_id"] = retreat_pid

	var seen: Dictionary = {}
	var to_move: Array[Formation] = []
	if not def_fid.is_empty():
		var combat_def: Formation = LeaderManager.get_formation(def_fid)
		if combat_def != null:
			to_move.append(combat_def)
			seen[def_fid] = true
	if not def_tag.is_empty() and LeaderManager.has_method("get_formations_for_country"):
		var country_forms: Array = LeaderManager.get_formations_for_country(def_tag)
		for f_any in country_forms:
			var f: Formation = f_any as Formation
			if f == null:
				continue
			var fid := str(f.formation_id) if "formation_id" in f else ""
			if fid.is_empty() or seen.has(fid):
				continue
			if "stationed_province_id" in f and int(f.stationed_province_id) == captured_pid:
				if f.has_method("get_category") and str(f.get_category()) != "land":
					continue
				to_move.append(f)
				seen[fid] = true

	for f2 in to_move:
		if f2 == null or not ("stationed_province_id" in f2):
			continue
		# Only displace if still on the lost province (or combat defender always leaves capture).
		var was_on_capture := int(f2.stationed_province_id) == captured_pid
		var is_combat_def := not def_fid.is_empty() and str(f2.formation_id) == def_fid
		if not was_on_capture and not is_combat_def:
			continue
		f2.stationed_province_id = retreat_pid
		var move_fid := str(f2.formation_id) if "formation_id" in f2 else ""
		if move_fid.is_empty():
			continue
		if retreat_pid >= 0 and not def_tag.is_empty():
			var moved := false
			if typeof(FormationMovement) != TYPE_NIL:
				var res: Dictionary = FormationMovement.move_formation_to_province(
					move_fid, retreat_pid, def_tag,
				)
				moved = bool(res.get("ok", false))
			if not moved and typeof(SupplyManager) != TYPE_NIL:
				SupplyManager.division_deployments[move_fid] = {
					"province_id": retreat_pid,
					"country_tag": def_tag,
					"order_type": "move_to_province",
				}
				# Station already set above; move may fail without templates.
				f2.stationed_province_id = retreat_pid
		elif typeof(SupplyManager) != TYPE_NIL and SupplyManager.division_deployments.has(move_fid):
			SupplyManager.division_deployments.erase(move_fid)
		print(
			"[CAPTURE RETREAT] %s (%s) leaves province %d → station=%d"
			% [move_fid, def_tag, captured_pid, retreat_pid]
		)


## Pick a remaining friendly land province for a defender forced off a captured id.
## Prefer land-adjacent still controlled by def_tag; else any controlled land; else -1.
func _pick_defender_retreat_province(captured_pid: int, defender_tag: String) -> int:
	var tag := defender_tag.strip_edges().to_upper()
	if tag.is_empty() or typeof(MapManager) == TYPE_NIL:
		return -1
	# Adjacent friendly land first (after capture ownership already flipped).
	if MapManager.has_method("get_adjacent_provinces"):
		var adj: Array = MapManager.get_adjacent_provinces(captured_pid, true)
		for apid_v in adj:
			var apid := int(apid_v)
			if apid == captured_pid or apid < 0:
				continue
			if _province_controlled_by(apid, tag):
				var p: Province = MapManager.get_province(apid) if MapManager.has_method("get_province") else null
				if p != null and p.is_sea:
					continue
				return apid
	# Any remaining friendly-controlled land (non-captured).
	if MapManager.has_method("get_provinces_by_controller"):
		var owned: Array = MapManager.get_provinces_by_controller(tag)
		for pid_v in owned:
			var pid := int(pid_v)
			if pid == captured_pid or pid < 0:
				continue
			var p2: Province = MapManager.get_province(pid) if MapManager.has_method("get_province") else null
			if p2 != null and p2.is_sea:
				continue
			return pid
	elif MapManager.has_method("get_provinces_by_owner"):
		var owned2: Array = MapManager.get_provinces_by_owner(tag)
		for pid_v2 in owned2:
			var pid2 := int(pid_v2)
			if pid2 == captured_pid or pid2 < 0:
				continue
			var p3: Province = MapManager.get_province(pid2) if MapManager.has_method("get_province") else null
			if p3 != null and p3.is_sea:
				continue
			return pid2
	return -1


func _province_controlled_by(province_id: int, tag: String) -> bool:
	if typeof(MapManager) == TYPE_NIL or tag.is_empty():
		return false
	if MapManager.has_method("get_province_controller"):
		return str(MapManager.get_province_controller(province_id)).strip_edges().to_upper() == tag
	var p: Province = MapManager.get_province(province_id) if MapManager.has_method("get_province") else null
	if p == null:
		return false
	var c := str(p.controller_tag).strip_edges().to_upper()
	if c.is_empty():
		c = str(p.owner_tag).strip_edges().to_upper()
	return c == tag

## Main-loop AI battle initiation helper (for 50+ turn playtest integration).
## Called from TimeManager daily for non-player major powers to keep world alive with wars.
## Uses existing can_assault + execute logic; limited to 1-2 actions per major per day to avoid spam.
## AI targets based on simple adjacent non-owned (later: supply/infra/org scoring + ascend geo).
func simulate_daily_ai_combat() -> void:
	# World-class main-loop AI battle initiation (promoted from F10 harness _simulate_ai_combat_turn base).
	# Called daily by TimeManager for 50+ turn integrated playtesting (auto wars for AI nations, not debug-only).
	# Uses real BattleManager paths (can/execute + chain/flank) + supply/infra/org + weather-aware target choice.
	# Limited actions to keep balanced (no spam); respects player; logs for harness evidence.
	if typeof(MapManager) == TYPE_NIL or typeof(LeaderManager) == TYPE_NIL:
		return
	var majors := ["GER", "SOV", "USA", "ENG", "FRA", "ITA", "JAP", "POL"]
	var player_tag := "USA"
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var pt := str(LeaderManager.call("get_player_country_tag"))
		if not pt.is_empty():
			player_tag = pt
	var actions := 0
	var max_actions := 3  # polish cap for 50+ turn stability
	for tag in majors:
		if tag == player_tag or actions >= max_actions:
			continue
		var owned: Array = MapManager.call("get_provinces_by_owner", tag) if MapManager.has_method("get_provinces_by_owner") else []
		if owned.is_empty():
			continue
		var did_one := false
		for pidv in owned:
			if did_one or actions >= max_actions: break
			var pid := int(pidv)
			var adjs: Array = MapManager.call("get_adjacent_provinces", pid) if MapManager.has_method("get_adjacent_provinces") else []
			# World-class AI target choice: score based on supply/infra/org (low = attractive/weak) + weather (avoid mud/snow for attacker) + ascend geo stub.
			var scored_targets: Array = []
			for aidv in adjs:
				var aid := int(aidv)
				var p: Province = MapManager.get_province(aid) if MapManager.has_method("get_province") else null
				if p == null or p.is_sea or p.owner_tag == tag or p.owner_tag == "": continue
				var score := 1.0
				# Infra/supply/dev low = easier target or valuable weak hold
				if p.infrastructure < 3: score += 0.8
				if p.development_level < 2: score += 0.6
				if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_depot_state"):
					var dep = SupplyManager.call("get_depot_state", aid)
					if dep and "current_stock" in dep and "throughput_capacity" in dep and dep.throughput_capacity > 0:
						if float(dep.current_stock) / dep.throughput_capacity < 0.3: score += 0.7
				# Low org/strength defender formations
				if typeof(LeaderManager) != TYPE_NIL:
					var defs := LeaderManager.get_formations_for_country(p.owner_tag)
					for df in defs:
						if df and ("stationed_province_id" in df) and int(df.stationed_province_id if "stationed_province_id" in df else (df.get("stationed_province_id") if df.has_method("get") else -1)) == aid:
							var o := float(df.organization if "organization" in df else (df.get("organization") if df.has_method("get") else 1.0))
							var s := float(df.strength if "strength" in df else (df.get("strength") if df.has_method("get") else 1.0))
							if o < 0.6: score += 1.2
							if s < 0.7: score += 0.9
							break
				# Weather-aware: penalize if mud/snow heavy for attacker mobility (full tie)
				if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_movement_multiplier"):
					var move_mult := float(WeatherManager.call("get_movement_multiplier", aid))
					if move_mult < 0.7: score -= 0.8  # avoid bad weather for this assault decision
				# Ascendancy geo stub tie (from DESIGN/MAP): slight score for high geo value (river/choke/full region) if method
				if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_geo_ascendancy_mod"):
					var geo_b := float(MapManager.call("get_geo_ascendancy_mod", aid, tag))
					if geo_b > 1.0: score += (geo_b - 1.0) * 0.5
				scored_targets.append({"pid": aid, "from": pid, "score": score})
			scored_targets.sort_custom(func(a, b): return a.score > b.score)
			for st in scored_targets:
				if did_one or actions >= max_actions: break
				var aid := int(st.pid)
				var fromp := int(st.from)
				var can: Dictionary = can_assault_province(tag, aid, fromp)
				if bool(can.get("ok", false)):
					var chain_results: Array = []
					if has_method("execute_chain_assault_or_flank"):
						chain_results = execute_chain_assault_or_flank(tag, aid, fromp, 1)
					else:
						var res: Dictionary = execute_province_assault(tag, aid, fromp)
						chain_results = [res] if res.get("success", false) else []
					for r in chain_results:
						print("[AI DAILY COMBAT] %s assaulted (chain/flank, score=%.1f) pid %d from %d -> success=%s capture=%s (weather/infra/org aware; main-loop auto for 50+ turns)" % [
							tag, st.score, aid, fromp, r.get("success", false), (r.get("result", {}) if typeof(r.get("result",{}))==TYPE_DICTIONARY else {}).get("province_control_change", false)
						])
						actions += 1
					did_one = true
					break
	if actions > 0:
		print("[AI DAILY COMBAT] Total AI assaults this daily tick: %d (promoted/polished for integrated playtest; non-debug main loop)" % actions)

## Internal strategic impl (rich context + full resolver phases). Public wrappers delegate.
func _do_naval_engagement(
	attacker_tag: String,
	defender_tag: String,
	sea_province_id: int,
	range_mod: float = 1.0,
	sub_heavy: bool = false,
	closer_engagement: bool = false,
) -> Dictionary:
	if typeof(MapManager) == TYPE_NIL:
		return {"success": false, "reason": "no map"}
	var sea_p: Province = MapManager.get_province(sea_province_id)
	if sea_p == null or not sea_p.is_sea:
		return {"success": false, "reason": "not sea province"}
	# Query real formations for orders, assets, leaders (full integration)
	var attacker_order := Formation.NAVAL_ORDER_NONE
	var defender_order := Formation.NAVAL_ORDER_NONE
	var atk_leader_bonus := 0.0
	var def_leader_bonus := 0.0
	var atk_traits := ""
	var def_traits := ""
	var atk_fuel := 0.85  # proxy; Supply will pass real
	var def_fuel := 0.85
	var atk_org := 0.9
	var def_org := 0.9
	var init_atk := 0.5
	var init_def := 0.5
	var atk_assets := ""
	var def_assets := ""
	var air_recon_atk := 0.0
	var air_recon_def := 0.0
	var jam_atk := 0.0  # defender jamming vs atk
	var jam_def := 0.0
	if typeof(LeaderManager) != TYPE_NIL:
		for f in LeaderManager.get_formations_for_country(attacker_tag):
			if f and f.get_category() == "naval":
				attacker_order = f.current_naval_order
				atk_assets = str(f.name) + " " + str(f.naval_design_id)
				if f.has_leader() and typeof(LeaderManager) != TYPE_NIL:
					var lid := f.leader_id
					var l := LeaderManager.get_leader(lid)
					if l:
						atk_leader_bonus = l.get_attack_modifier() * 0.8 + l.get_terrain_modifier("sea")
						atk_traits = str(l.traits if "traits" in l else "")
						init_atk = l.get_initiative_modifier() * 5.0 + 0.5
				if "fuel" in f or f.has_method("get"):
					atk_fuel = clamp(float(f.get("fuel_level") if f.has("fuel_level") else 0.85), 0.3, 1.1)
				atk_org = float(f.organization) if "organization" in f else 0.9
				# Air attached for recon/strike
				if f.attached_air_formation_id != "":
					air_recon_atk += 0.9
				break
		for f in LeaderManager.get_formations_for_country(defender_tag):
			if f and f.get_category() == "naval":
				defender_order = f.current_naval_order
				def_assets = str(f.name) + " " + str(f.naval_design_id)
				if f.has_leader() and typeof(LeaderManager) != TYPE_NIL:
					var lid := f.leader_id
					var l := LeaderManager.get_leader(lid)
					if l:
						def_leader_bonus = l.get_attack_modifier() * 0.8 + l.get_terrain_modifier("sea")
						def_traits = str(l.traits if "traits" in l else "")
						init_def = l.get_initiative_modifier() * 5.0 + 0.5
				if "fuel" in f or f.has_method("get"):
					def_fuel = clamp(float(f.get("fuel_level") if f.has("fuel_level") else 0.85), 0.3, 1.1)
				def_org = float(f.organization) if "organization" in f else 0.9
				if f.attached_air_formation_id != "":
					air_recon_def += 0.9
				break
	# National chief navy bonus (from LeaderManager)
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_national_bonuses"):
		var nb := LeaderManager.get_national_bonuses(attacker_tag)
		atk_leader_bonus += float(nb.get("naval_combat", 0.0))
		nb = LeaderManager.get_national_bonuses(defender_tag)
		def_leader_bonus += float(nb.get("naval_combat", 0.0))
	var context := {
		"attacker": attacker_tag,
		"defender": defender_tag,
		"sea_pid": sea_province_id,
		"range_mod": range_mod,
		"sub_heavy": sub_heavy,
		"weather_vis": 1.0,
		"chokepoint": false,
		"attacker_order": attacker_order,
		"defender_order": defender_order,
		"leader_atk_bonus": atk_leader_bonus,
		"leader_def_bonus": def_leader_bonus,
		"atk_traits": atk_traits,
		"def_traits": def_traits,
		"fuel_atk": atk_fuel,
		"fuel_def": def_fuel,
		"org_atk": atk_org,
		"org_def": def_org,
		"initiative_atk": init_atk,
		"initiative_def": init_def,
		"atk_assets": atk_assets,
		"def_assets": def_assets,
		"air_recon_atk": air_recon_atk,
		"air_recon_def": air_recon_def,
		"jam_atk": jam_atk,
		"jam_def": jam_def,
		"year": (TimeManager.get_current_year() if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year") else 1942),
	}
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_naval_spotting_visibility"):
			context["weather_vis"] = WeatherManager.get_naval_spotting_visibility(sea_province_id)
		# Pure naval spot mult also stored for resolver/UI (weather expand live path).
		if WeatherManager.has_method("get_naval_spot_weather_multiplier"):
			context["naval_spot_weather_mult"] = float(WeatherManager.get_naval_spot_weather_multiplier(sea_province_id))
			# Blend pure mult into weather_vis when spotting API missing pure base.
			if not context.has("weather_vis"):
				context["weather_vis"] = float(context["naval_spot_weather_mult"])
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
		context["chokepoint"] = MapManager.has_strategic_chokepoint(sea_province_id)
	# Adjust base powers (orders + sub/range will be re-applied richer in resolver)
	var atk_power := 1.0 + (0.4 if not sub_heavy else 0.15)
	var def_power := 1.0 + (0.25 if sub_heavy else 0.08)
	# Range/order proxy pre-mod (resolver does full)
	if range_mod < 0.6 or closer_engagement or attacker_order in [Formation.NAVAL_ORDER_AMBUSH, Formation.NAVAL_ORDER_SEARCH_AND_DESTROY]:
		if sub_heavy:
			def_power *= 1.22
		else:
			atk_power *= 0.92
	else:
		atk_power *= range_mod
	# Enrich from Supply combat presence if avail (air/naval totals for recon/strike power)
	var sm := get_node_or_null("/root/SupplyManager")
	if sm != null and sm.has_method("get_combat_presence_registry"):
		var reg: Variant = sm.call("get_combat_presence_registry")
		if reg != null:
			var rpt: Variant = reg.get_report(sea_province_id)
			if rpt != null:
				# Add air for recon/strike
				var att_air := float(rpt.air_by_tag.get(attacker_tag, 0.0)) if "air_by_tag" in rpt else 0.0
				var def_air := 0.0
				if "air_by_tag" in rpt:
					for tg in rpt.air_by_tag.keys():
						if str(tg) != attacker_tag: def_air += float(rpt.air_by_tag[tg])
				context["air_recon_atk"] = max(float(context.get("air_recon_atk",0)), att_air * 0.08)
				context["air_recon_def"] = max(float(context.get("air_recon_def",0)), def_air * 0.08)
				# Naval strength proxy
				var n_atk := float(rpt.naval_strength.get(attacker_tag, 0.0)) if "naval_strength" in rpt else 0.0
				var n_def := float(rpt.naval_strength.get(defender_tag, 0.0)) if "naval_strength" in rpt else 0.0
				atk_power += n_atk * 0.06
				def_power += n_def * 0.06
	# Use resolver (now full phased)
	var result := {"success": true, "type": "naval_engagement", "context": context}
	if _resolver and _resolver.has_method("resolve_naval_engagement"):
		result = _resolver.resolve_naval_engagement(context, atk_power, def_power)
	else:
		# Fallback simple
		var total = atk_power + def_power
		var atk_win = randf() < (atk_power / total)
		result["winner"] = attacker_tag if atk_win else defender_tag
		result["naval_casualties"] = randf() * 0.3
		result["range_engagement"] = "close" if (range_mod < 0.6 or closer_engagement) else "stand_off"
		print("Naval engagement resolved (demo): %s vs %s at %s range (vis %.2f, choke %s, sub %s, closer_order=%s, orders %s/%s) -> winner %s" % [attacker_tag, defender_tag, result["range_engagement"], context["weather_vis"], context["chokepoint"], sub_heavy, closer_engagement, context.get("attacker_order",""), context.get("defender_order",""), result["winner"]])
	battle_resolved.emit(result)
	return result

## Public 6-param strategic entry (for code calling with range/sub/closer). Delegates to rich internal.
func execute_naval_engagement(
	attacker_tag: String,
	defender_tag: String,
	sea_province_id: int,
	range_mod: float = 1.0,
	sub_heavy: bool = false,
	closer_engagement: bool = false,
) -> Dictionary:
	return _do_naval_engagement(attacker_tag, defender_tag, sea_province_id, range_mod, sub_heavy, closer_engagement)


func get_divisions_at_province(province_id: int, country_tag: String) -> Array[Dictionary]:
	## Prefer SupplyManager deployments (template-backed), then world_full OOB land stations
	## on LeaderManager (formation_id like GER_formation_0 without DivisionTemplate).
	var out: Array[Dictionary] = []
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_land_divisions_at_province"):
		out = SupplyManager.get_land_divisions_at_province(province_id, country_tag)
	if not out.is_empty():
		return out
	return _land_formations_stationed_at(province_id, country_tag)


## Land divisions/garrisons stationed via Formation.stationed_province_id (scenario OOB path).
func _land_formations_stationed_at(province_id: int, country_tag: String) -> Array[Dictionary]:
	var tag := country_tag.strip_edges().to_upper()
	var out: Array[Dictionary] = []
	if province_id <= 0 or tag.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return out
	if not LeaderManager.has_method("get_formations_for_country"):
		return out
	for f in LeaderManager.get_formations_for_country(tag):
		if f == null:
			continue
		var ftype := str(f.formation_type) if "formation_type" in f else ""
		if ftype != Formation.TYPE_DIVISION and ftype != Formation.TYPE_GARRISON:
			continue
		var sid := int(f.stationed_province_id) if "stationed_province_id" in f else -1
		if sid != province_id:
			continue
		var fid := str(f.formation_id) if "formation_id" in f else ""
		if fid.is_empty():
			continue
		var display := str(f.name) if "name" in f and not str(f.name).is_empty() else fid
		out.append({
			"formation_id": fid,
			"display_name": display,
			"country_tag": tag,
			"stationed_province_id": province_id,
		})
	return out


func _validate_attack_source(
	attacker_tag: String,
	from_province_id: int,
	target_province_id: int,
	formation_id: String = "",
) -> Dictionary:
	if typeof(MapManager) == TYPE_NIL:
		return {"ok": false, "reason": "MapManager unavailable"}

	if from_province_id < 0:
		return {"ok": false, "reason": "No staging province"}

	if from_province_id == target_province_id:
		return {"ok": false, "reason": "Same province"}

	var from_prov: Province = MapManager.get_province(from_province_id)
	if from_prov == null:
		return {"ok": false, "reason": "Staging province not found"}

	if _province_controller_tag(from_prov) != attacker_tag:
		return {"ok": false, "reason": "Staging province not controlled by attacker"}

	if not _provinces_adjacent(from_province_id, target_province_id):
		return {"ok": false, "reason": "Target not adjacent to staging province"}

	var divisions := get_divisions_at_province(from_province_id, attacker_tag)
	if divisions.is_empty():
		return {"ok": false, "reason": "No division at staging province %d" % from_province_id}

	var want_fid := formation_id.strip_edges()
	var chosen: Dictionary = {}
	if not want_fid.is_empty():
		# Named unit must sit at from_pid — never swap to a different division.
		for entry in divisions:
			if str(entry.get("formation_id", "")) == want_fid:
				chosen = entry
				break
		if chosen.is_empty():
			return {
				"ok": false,
				"reason": "Formation %s not stationed at staging province %d" % [want_fid, from_province_id],
			}
		var power := _estimate_attack_power(want_fid, from_prov, attacker_tag)
		chosen["attack_power"] = power
		return {
			"ok": true,
			"from_province_id": from_province_id,
			"from_province_name": from_prov.name,
			"formation_id": want_fid,
			"division_name": str(chosen.get("display_name", want_fid)),
			"attack_power": power,
		}

	var best := _pick_strongest_division(divisions, from_prov, attacker_tag)
	return {
		"ok": true,
		"from_province_id": from_province_id,
		"from_province_name": from_prov.name,
		"formation_id": str(best.get("formation_id", "")),
		"division_name": str(best.get("display_name", "")),
		"attack_power": float(best.get("attack_power", 0.0)),
	}


## Live Formation org/str/xp × equipment soft/hard (not ProductionManager shortage org 1.0/0.82).
func _unit_preview_components(formation_id: String, province: Province, country_tag: String) -> Dictionary:
	var soft := 0.0
	var hard := 0.0
	if _resolver != null:
		var terrain: String = province.terrain if province != null and province.terrain != "" else "plains"
		var pid := province.id if province != null else -1
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_effective_terrain_for_demo"):
			var eff := MapManager.get_effective_terrain_for_demo(pid)
			if eff != terrain:
				terrain = eff
		var dev := province.development_level if province != null else -1
		var infra := province.infrastructure if province != null else -1
		var stats: Dictionary = _resolver.get_effective_combat_power(
			formation_id, formation_id, formation_id, terrain, pid, dev, infra,
		)
		soft = float(stats.get("soft_attack", 0.0))
		hard = float(stats.get("hard_attack", 0.0))
	var org := 1.0
	var strength := 1.0
	var xp := 48.0
	if typeof(LeaderManager) != TYPE_NIL:
		var fo: Formation = LeaderManager.get_formation(formation_id)
		if fo != null:
			if "organization" in fo:
				org = maxf(0.0, float(fo.organization))
			if "strength" in fo:
				strength = maxf(0.0, float(fo.strength))
			if "combat_experience" in fo:
				xp = float(fo.combat_experience)
	return {"soft": soft, "hard": hard, "org": org, "str": strength, "xp": xp}


func _unit_preview_power(
	formation_id: String,
	province: Province,
	country_tag: String,
	initiative: float = 0.0,
) -> float:
	var c := _unit_preview_components(formation_id, province, country_tag)
	var soft := float(c.get("soft", 0.0))
	var hard := float(c.get("hard", 0.0))
	var org := float(c.get("org", 1.0))
	var strength := float(c.get("str", 1.0))
	var xp := float(c.get("xp", 48.0))
	var xp_mult := lerpf(0.85, 1.15, clampf(xp / 100.0, 0.0, 1.0))
	return (soft + 1.6 * hard) * org * strength * xp_mult + initiative

func _pick_strongest_division(
	divisions: Array[Dictionary],
	from_prov: Province,
	attacker_tag: String,
) -> Dictionary:
	var best: Dictionary = divisions[0]
	var best_power := -1.0
	for entry in divisions:
		var fid := str(entry.get("formation_id", ""))
		var power := _estimate_attack_power(fid, from_prov, attacker_tag)
		entry["attack_power"] = power
		if power > best_power:
			best_power = power
			best = entry
	return best


func _estimate_attack_power(formation_id: String, province: Province, country_tag: String) -> float:
	if _resolver == null:
		return 0.0
	var terrain: String = province.terrain if province != null and province.terrain != "" else "plains"
	var pid := province.id if province != null else -1
	# Demo: use effective child terrain if sample subdiv applied
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_effective_terrain_for_demo"):
		var eff := MapManager.get_effective_terrain_for_demo(pid)
		if eff != terrain:
			terrain = eff
	var dev := province.development_level if province != null else -1
	var infra := province.infrastructure if province != null else -1
	# unit_id + army_id both = formation_id so on-hand equipment shortages apply (same as assault resolve).
	var stats: Dictionary = _resolver.get_effective_combat_power(
		formation_id, formation_id, formation_id, terrain, pid, dev, infra,
	)
	return float(stats.get("soft_attack", 0.0)) + float(stats.get("hard_attack", 0.0)) * 1.6


func _build_attacker_formation(formation_id: String, country_tag: String, from_pid: int) -> Formation:
	var formation := _formation_from_id(formation_id, country_tag)
	formation.stationed_province_id = from_pid
	formation.name = formation.name if not formation.name.is_empty() else "Attacker"
	return formation


func _build_defender_formation(target: Province, defender_tag: String) -> Formation:
	var tag := defender_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = _province_defender_tag(target)

	var deployed := get_divisions_at_province(target.id, tag)
	if not deployed.is_empty():
		var pick := _pick_strongest_division(deployed, target, tag)
		var fid := str(pick.get("formation_id", ""))
		var formation := _formation_from_id(fid, tag)
		formation.stationed_province_id = target.id
		formation.name = formation.name if not formation.name.is_empty() else "Defender"
		return formation

	var garrison_id := _garrison_template_for_country(tag)
	var garrison := Formation.new()
	garrison.formation_id = garrison_id
	garrison.country_tag = tag
	garrison.formation_type = Formation.TYPE_GARRISON
	garrison.name = "%s Garrison" % tag
	garrison.stationed_province_id = target.id
	garrison.organization = 1.0
	garrison.readiness = 1.0
	garrison.strength = 1.0
	return garrison


func _formation_from_id(formation_id: String, country_tag: String) -> Formation:
	if typeof(LeaderManager) != TYPE_NIL:
		var existing := LeaderManager.get_formation(formation_id)
		if existing != null:
			return existing
	var created := Formation.new()
	created.formation_id = formation_id
	created.country_tag = country_tag
	created.formation_type = Formation.TYPE_DIVISION
	created.name = formation_id
	created.organization = 1.0
	created.readiness = 1.0
	created.strength = 1.0
	return created


func _garrison_template_for_country(country_tag: String) -> String:
	match country_tag.strip_edges().to_upper():
		"GER":
			return "german_infantry_division_1943"
		"USA":
			return "us_infantry_div_ww2"
		"SRB", "CRO", "YUG", "SLO", "HUN", "BGR":
			return "german_infantry_division_1943_mixed"
		_:
			return DEFAULT_GARRISON_TEMPLATE


func _provinces_adjacent(a: int, b: int) -> bool:
	if typeof(MapManager) == TYPE_NIL:
		return false
	for nid in MapManager.get_adjacent_provinces(a):
		if int(nid) == b:
			return true
	return false


func _province_controller_tag(province: Province) -> String:
	if province == null:
		return ""
	var ctrl := province.controller_tag.strip_edges().to_upper()
	if not ctrl.is_empty():
		return ctrl
	return province.owner_tag.strip_edges().to_upper()


func _province_defender_tag(province: Province) -> String:
	return _province_controller_tag(province)


func _notify_map_refresh(target_pid: int = -1, from_pid: int = -1, retreat_pid: int = -1) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var pid := int(target_pid)
	var from := int(from_pid)
	var retreat := int(retreat_pid)
	for mr in tree.get_nodes_in_group("map_renderer"):
		# Prefer light capture refresh — full-board rebuild freezes world_accurate.
		if mr.has_method("refresh_after_capture_light"):
			mr.call_deferred("refresh_after_capture_light", pid, from, retreat)
		elif mr.has_method("_update_unit_icons_for_pids"):
			mr.call_deferred("_update_unit_icons_for_pids", [pid, from, retreat])


func _post_battle_news(result: Dictionary, captured: bool) -> void:
	if typeof(LeaderEventUI) == TYPE_NIL or not LeaderEventUI.has_method("post_news"):
		return
	var attacker := str(result.get("attacker_tag", "?"))
	var defender := str(result.get("defender_tag", "?"))
	var outcome := str(result.get("outcome", result.get("winner", "battle")))
	var target_name := ""
	var pid := int(result.get("target_province_id", result.get("province_id", -1)))
	if typeof(MapManager) != TYPE_NIL and pid >= 0:
		var p: Province = MapManager.get_province(pid)
		if p != null:
			target_name = p.name
	var title := "Province captured" if captured else "Battle: %s" % outcome
	var body := "%s vs %s at %s" % [attacker, defender, target_name if not target_name.is_empty() else str(pid)]
	LeaderEventUI.post_news(title, body, "combat")

## === HISTORICAL OOB (TestRunner / harness) ===
func force_historical_oob_for_battle(battle_key: String, year: int = 1942, custom_pids: Dictionary = {}) -> Dictionary:
	"""Force realistic OOB at representative provinces for history testing (called by TestRunner sims). Updates owners, deploys formations from templates, assigns historical leaders, seeds air/naval presence, sets weather proxy."""
	print("[BM HIST OOB] Forcing OOB for battle=%s year=%d" % [battle_key, year])
	if typeof(MapManager) == TYPE_NIL or typeof(SupplyManager) == TYPE_NIL or typeof(LeaderManager) == TYPE_NIL:
		return {"ok": false, "reason": "Managers unavailable"}
	var mm := MapManager
	var sm := SupplyManager
	var lm := LeaderManager

	# Defaults / overrides via custom_pids e.g. {"staging": 3, "target": 4}
	var staging := int(custom_pids.get("staging", 3))
	var target := int(custom_pids.get("target", 4))
	var sea := int(custom_pids.get("sea", 999))

	var att_tag := "GER"
	var def_tag := "FRA"
	var att_divs := ["german_infantry_division_1943", "german_infantry_division_1943_mixed"]
	var def_divs := ["us_infantry_div_ww2"]  # proxy; use FRA if templates have country filter
	var air_att := 8.0
	var air_def := 2.0
	var use_subs := false
	var stormy := false

	match battle_key.to_lower():
		"marne", "marne_1914":
			att_tag = "GER"; def_tag = "FRA"
			att_divs = ["german_infantry_division_1943_mixed", "german_infantry_division_1943"]
			def_divs = ["us_infantry_div_ww2"]
			air_att = 0.5; air_def = 0.2  # early air limited
			# 1914 leaders proxy via 1918
		"verdun", "verdun_1916":
			att_tag = "GER"; def_tag = "FRA"
			att_divs = ["german_infantry_division_1943_mixed"]
			def_divs = ["us_infantry_div_ww2"]
			air_att = 1.0; air_def = 0.8
		"stalingrad", "stalingrad_1942":
			att_tag = "GER"; def_tag = "SOV"
			att_divs = ["german_infantry_division_1943_mixed", "german_infantry_division_1943"]
			def_divs = ["us_infantry_div_ww2"]
			air_att = 6.0; air_def = 4.0
			staging = int(custom_pids.get("staging", 31)) # Volgograd proxy
			target = int(custom_pids.get("target", 31))
			stormy = true
		"midway", "midway_1942":
			att_tag = "JAP"; def_tag = "USA"
			att_divs = []
			def_divs = []
			air_att = 15.0; air_def = 12.0
			use_subs = true
			sea = int(custom_pids.get("sea", 999))
			staging = sea; target = sea
		"dday", "d_day", "normandy", "overlord":
			att_tag = "USA"; def_tag = "GER"
			att_divs = ["us_infantry_div_ww2"]
			def_divs = ["german_infantry_division_1943_mixed"]
			air_att = 18.0; air_def = 3.0
			# coastal from custom or default
			staging = int(custom_pids.get("staging", 5)) # proxy coast/ENG
			target = int(custom_pids.get("target", 4)) # Paris area coast proxy

	# Force owners (attacker staging friendly, target enemy)
	if mm.has_method("update_province_owner"):
		mm.call("update_province_owner", staging, att_tag, att_tag, true)
		mm.call("update_province_owner", target, def_tag, def_tag, true)
		if sea != staging:
			mm.call("update_province_owner", sea, "SEA", "SEA", true)  # neutral sea

	# Deploy land forces (use div templates)
	sm.call("ensure_division_formations_for_country", att_tag)
	sm.call("ensure_division_formations_for_country", def_tag)
	for d in att_divs:
		sm.call("move_formation_to_province", d, staging, att_tag)
	for d in def_divs:
		sm.call("move_formation_to_province", d, target, def_tag)

	# Air presence for preview/resolver CAS
	sm.call("clear_force_registry") if sm.has_method("clear_force_registry") else null
	var reg = sm.call("get_combat_presence_registry") if sm.has_method("get_combat_presence_registry") else null
	if reg:
		reg.add_air_presence(target, att_tag, air_att)
		reg.add_air_presence(target, def_tag, air_def)
		if battle_key.to_lower() in ["midway", "dday"]:
			reg.add_naval_presence(sea, att_tag, 12.0 if att_tag=="USA" or att_tag=="JAP" else 8.0, false)
			reg.add_naval_presence(sea, def_tag, 10.0 if def_tag=="USA" or def_tag=="JAP" else 7.0, use_subs)

	# Historical leader assign (use available historical; match era loosely)
	if lm.has_method("get_leaders_for_country"):
		var att_leaders: Variant = lm.call("get_leaders_for_country", att_tag)
		if att_leaders.size() > 0 and att_divs.size() > 0:
			var lid: String = str(att_leaders[0].get("leader_id", "")) if typeof(att_leaders[0]) == TYPE_DICTIONARY else (str(att_leaders[0].leader_id) if "leader_id" in att_leaders[0] else "")
			if lid != "" and lm.has_method("assign_leader_to_formation"):
				lm.call("assign_leader_to_formation", lid, att_divs[0])
		var def_leaders: Variant = lm.call("get_leaders_for_country", def_tag)
		if def_leaders.size() > 0 and def_divs.size() > 0:
			var dlid: String = str(def_leaders[0].get("leader_id", "")) if typeof(def_leaders[0]) == TYPE_DICTIONARY else (str(def_leaders[0].leader_id) if "leader_id" in def_leaders[0] else "")
			if dlid != "" and lm.has_method("assign_leader_to_formation"):
				lm.call("assign_leader_to_formation", dlid, def_divs[0])

	# Weather proxy via Time or WM if settable
	if stormy and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("force_event_for_test"):
		WeatherManager.call("force_event_for_test", target, "blizzard")  # or mud/rain for WWI

	# Time set for leader/tech gating
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("set_current_year"):
		TimeManager.call("set_current_year", year)

	print("[BM HIST OOB] Deployed: %s@%d (%s divs + air %.1f) vs %s@%d (%s divs + air %.1f) sea=%d subs=%s storm=%s" % [att_tag, staging, att_divs, air_att, def_tag, target, def_divs, air_def, sea, use_subs, stormy])
	return {"ok": true, "att_tag": att_tag, "def_tag": def_tag, "staging": staging, "target": target, "sea": sea, "year": year}


## ---------------------------------------------------------------------------
## Multi-phase combat product surface (major #1)
## ---------------------------------------------------------------------------

func build_multi_phase_combat_product(
	attacker_power: float = 100.0,
	defender_power: float = 80.0,
	attacker_supply: float = 0.85,
	weather_mult: float = 1.0,
	province_id: int = 1,
) -> Dictionary:
	if typeof(MapPolishFormatters) != TYPE_NIL:
		return MapPolishFormatters.multi_phase_combat_product(
			attacker_power, defender_power, attacker_supply, weather_mult, province_id
		)
	return {"empty": true, "phase_rows": [], "apply_queue": []}


func apply_combat_phase(
	phase: String,
	province_id: int = 1,
	attacker_power: float = 100.0,
	defender_power: float = 80.0,
	attacker_supply: float = 0.85,
	weather_mult: float = 1.0,
) -> Dictionary:
	var plan: Dictionary = {}
	if typeof(MapPolishFormatters) != TYPE_NIL:
		plan = MapPolishFormatters.execute_combat_phase_plan(
			phase, province_id, attacker_power, defender_power, attacker_supply, weather_mult
		)
	else:
		return {"ok": false, "reason": "no formatters"}
	return {
		"ok": bool(plan.get("ok", plan.get("enabled", false))),
		"plan": plan,
		"phase": str(plan.get("phase", phase)),
		"leaf_action": str(plan.get("leaf_action", "")),
		"score": float(plan.get("score", 0.0)),
		"summary": str(plan.get("summary", "")),
		"empty": false,
	}
