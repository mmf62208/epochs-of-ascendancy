# scripts/combat/BattleManager.gd
## Main-loop province assault orchestration: formations → phased combat → capture → map refresh.
extends Node

signal battle_started(context: Dictionary)
signal battle_resolved(result: Dictionary)

const DEFAULT_GARRISON_TEMPLATE := "german_infantry_division_1943_mixed"

var _resolver: CombatResolver


func _ready() -> void:
	_resolver = CombatResolver.new()
	_resolver.name = "CombatResolver"
	add_child(_resolver)


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

	var source := find_attack_source(tag, target_province_id, from_province_id)
	if not bool(source.get("ok", false)):
		return source

	source["target_province_id"] = target_province_id
	source["target_name"] = target.name
	source["defender_tag"] = defender_tag
	source["attacker_tag"] = tag
	# Carry air dominance from ProvinceInsight for battle context (used in result merge + logs + AAR)
	if typeof(ProvinceInsight) != TYPE_NIL and typeof(MapManager) != TYPE_NIL:
		var from_p: Province = MapManager.get_province(from_province_id) if from_province_id >= 0 else target
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


func execute_province_assault(
	attacker_tag: String,
	target_province_id: int,
	from_province_id: int = -1,
	attacker_formation_id: String = "",
) -> Dictionary:
	var preview: Dictionary = can_assault_province(attacker_tag, target_province_id, from_province_id)
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
## FormationMovement→SupplyManager may fail under headless/-s (no network, no division template
## for OOB fids); LeaderManager.stationed_province_id is the combat OOB source of truth and
## must still advance.
func _station_attacker_on_captured_province(
	attacker_formation_id: String,
	target_pid: int,
	attacker_tag: String,
) -> void:
	if attacker_formation_id.is_empty() or target_pid < 0:
		return
	var tag := attacker_tag.strip_edges().to_upper()
	var moved := false
	if typeof(FormationMovement) != TYPE_NIL:
		var res: Dictionary = FormationMovement.move_formation_to_province(
			attacker_formation_id, target_pid, tag,
		)
		moved = bool(res.get("ok", false))
	elif typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("move_formation_to_province"):
		var res2: Dictionary = SupplyManager.move_formation_to_province(
			attacker_formation_id, target_pid, tag,
		)
		moved = bool(res2.get("ok", false))
	if typeof(LeaderManager) != TYPE_NIL:
		var f: Formation = LeaderManager.get_formation(attacker_formation_id)
		if f != null:
			f.stationed_province_id = target_pid
	# Keep SupplyManager deployment registry aligned when move pipeline could not run fully.
	if not moved and typeof(SupplyManager) != TYPE_NIL:
		SupplyManager.division_deployments[attacker_formation_id] = {
			"province_id": target_pid,
			"country_tag": tag,
			"order_type": "move_to_province",
		}


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
) -> Dictionary:
	if typeof(MapManager) == TYPE_NIL:
		return {"ok": false, "reason": "MapManager unavailable"}

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

	var best := _pick_strongest_division(divisions, from_prov, attacker_tag)
	return {
		"ok": true,
		"from_province_id": from_province_id,
		"from_province_name": from_prov.name,
		"formation_id": str(best.get("formation_id", "")),
		"division_name": str(best.get("display_name", "")),
		"attack_power": float(best.get("attack_power", 0.0)),
	}

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
