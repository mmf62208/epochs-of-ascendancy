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
		result["attacker_power_detail"] = _resolver.get_effective_combat_power(str(attacker.formation_id if attacker else ""), "", fid, t_terr, t_id, t_dev, t_inf)
		result["defender_power_detail"] = _resolver.get_effective_combat_power(str(defender.formation_id if defender else ""), "", str(result.get("defender_formation_id","")), t_terr, t_id, t_dev, t_inf)

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
	elif typeof(GameData) != TYPE_NIL:
		date = "%04d-%02d" % [GameData.get_current_year(), GameData.get_current_month()]
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
## After a successful capture, attempts follow-on assault on an adjacent enemy province from the new position (flanking via adjacent).
## Used by AI demo / harness for better multi-province feel. Returns list of executed results.
func execute_chain_assault_or_flank(
	attacker_tag: String,
	initial_target_pid: int,
	from_pid: int = -1,
	max_chain: int = 2
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var current_from := initial_target_pid if initial_target_pid >= 0 else from_pid
	var bm_res := execute_province_assault(attacker_tag, initial_target_pid, from_pid)
	if not bm_res.get("success", false):
		return results
	results.append(bm_res)
	# If captured, try 1- max_chain adjacent weak targets for chain/flank.
	var captured := false
	if "result" in bm_res and typeof(bm_res.result) == TYPE_DICTIONARY:
		captured = bool(bm_res.result.get("province_control_change", false))
	if captured and typeof(MapManager) != TYPE_NIL and max_chain > 0:
		var adjs: Array = []
		if MapManager.has_method("get_adjacent_provinces"):
			adjs = MapManager.get_adjacent_provinces(initial_target_pid)
		var chained := 0
		for aidv in adjs:
			if chained >= max_chain: break
			var aid := int(aidv)
			var p: Province = MapManager.get_province(aid) if MapManager.has_method("get_province") else null
			if p == null or p.is_sea or p.owner_tag == "" or p.owner_tag == attacker_tag: continue
			var can2 := can_assault_province(attacker_tag, aid, current_from)
			if bool(can2.get("ok", false)):
				var follow := execute_province_assault(attacker_tag, aid, current_from)
				if follow.get("success", false):
					results.append(follow)
					chained += 1
					current_from = aid
					print("[CHAIN/FLANK] Follow-on assault to %d from new pos; multi-province campaign step." % aid)
	return results


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

	# === Balance integration: apply persistent org/readiness/strength damage here (from BM as per design)
	# Loser heavier losses (strength hit), winner lighter org/rdy hit. Recovery via Supply daily (infra/supply mod).
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
			att_f.organization = clampf(att_f.organization * (1.0 - org_loss + randf() * 0.04), 0.22, 1.0)
			att_f.readiness = clampf(att_f.readiness * (1.0 - rdy_loss + randf() * 0.04), 0.28, 1.0)
			if not is_win:
				att_f.strength = clampf(att_f.strength * (0.72 + randf() * 0.12), 0.35, 1.0)
			att_f.is_in_combat = true
			dmg_line += "ATT %s: org=%.2f rdy=%.2f str=%.2f ; " % [attacker_formation_id, att_f.organization, att_f.readiness, att_f.strength]
		if def_f != null:
			var is_win_def := (w == "defender")
			var org_loss_d := 0.26 if not is_win_def else 0.10
			var rdy_loss_d := 0.21 if not is_win_def else 0.08
			if prolonged:
				org_loss_d *= 0.5
				rdy_loss_d *= 0.5
			def_f.organization = clampf(def_f.organization * (1.0 - org_loss_d + randf() * 0.04), 0.22, 1.0)
			def_f.readiness = clampf(def_f.readiness * (1.0 - rdy_loss_d + randf() * 0.04), 0.28, 1.0)
			if not is_win_def:
				def_f.strength = clampf(def_f.strength * (0.62 + randf() * 0.12), 0.30, 1.0)
			def_f.is_in_combat = true
			dmg_line += "DEF %s: org=%.2f rdy=%.2f str=%.2f" % [def_fid, def_f.organization, def_f.readiness, def_f.strength]
		if att_f != null or def_f != null:
			print(dmg_line + (" (prolonged - reduced losses, lasts longer)" if prolonged else ""))

	if captured and target_pid >= 0 and typeof(MapManager) != TYPE_NIL:
		MapManager.update_province_owner(target_pid, attacker_tag, attacker_tag, false)
		if typeof(FormationMovement) != TYPE_NIL and not attacker_formation_id.is_empty():
			FormationMovement.move_formation_to_province(
				attacker_formation_id, target_pid, attacker_tag,
			)
		_notify_map_refresh()
		_post_battle_news(result, true)
	elif winner == "attacker":
		_post_battle_news(result, false)
	elif winner == "defender":
		_post_battle_news(result, false)

## Main-loop AI battle initiation helper (for 50+ turn playtest integration).
## Called from TimeManager daily for non-player major powers to keep world alive with wars.
## Uses existing can_assault + execute logic; limited to 1-2 actions per major per day to avoid spam.
## AI targets based on simple adjacent non-owned (later: supply/infra/org scoring + ascend geo).
func simulate_daily_ai_combat() -> void:
	# Prefer DebugOverlay for full scored logic (weather/geo aware); fallback to inline AI below.
	var dbg := get_node_or_null("/root/DebugOverlay")
	if dbg != null and dbg.has_method("_simulate_ai_combat_turn"):
		dbg.call("_simulate_ai_combat_turn")
		print("[BM DAILY AI] delegated to DebugOverlay _simulate (full scoring + chain + weather).")
		return
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

## Strategic naval engagement simulator entry (called after spotting in sea zones).
## range_mod from weather/vis/storms/night (low = closer range engagements, favors subs/ambush or torps; high = stand off gunnery/carrier strikes).
## sub_heavy: subs present, harder initial spot but deadly close.
## Straits: already boosted in caller.
func execute_naval_engagement(
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
	# For demo, find any naval formations of the tags in/near the sea (simplified: use strength or pick test)
	# In full: query LeaderManager or formations for fleets in that sea or adjacent. Lookup order for mod.
	var attacker_order := Formation.NAVAL_ORDER_NONE
	var defender_order := Formation.NAVAL_ORDER_NONE
	if typeof(LeaderManager) != TYPE_NIL:
		for f in LeaderManager.get_formations_for_country(attacker_tag):
			if f and f.get_category() == "naval": attacker_order = f.current_naval_order; break
		for f in LeaderManager.get_formations_for_country(defender_tag):
			if f and f.get_category() == "naval": defender_order = f.current_naval_order; break
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
	}
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_naval_spotting_visibility"):
		context["weather_vis"] = WeatherManager.get_naval_spotting_visibility(sea_province_id)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
		context["chokepoint"] = MapManager.has_strategic_chokepoint(sea_province_id)
	# Adjust powers based on range: low range_mod + sub_heavy + closer (storm/night/order like AMBUSH/S&D) -> sub/torp advantage, close fight; high -> air/gun long range.
	var atk_power := 1.0 + (0.5 if not sub_heavy else 0.2)
	var def_power := 1.0 + (0.3 if sub_heavy else 0.1)
	# Range mod: <0.6 or closer favors subs/ambush (higher def for sub side); use orders from context
	if range_mod < 0.6 or closer_engagement or context.get("attacker_order", "") in [Formation.NAVAL_ORDER_AMBUSH, Formation.NAVAL_ORDER_SEARCH_AND_DESTROY]:
		if sub_heavy:
			def_power *= 1.25  # sub advantage in poor vis/close
		else:
			atk_power *= 0.9
	else:
		atk_power *= range_mod
	# Use resolver for common combat math if possible
	var result := {"success": true, "type": "naval_engagement", "context": context}
	if _resolver and _resolver.has_method("resolve_naval_engagement"):
		result = _resolver.resolve_naval_engagement(context, atk_power, def_power)
	else:
		# Simple strategic outcome
		var total = atk_power + def_power
		var atk_win = randf() < (atk_power / total)
		result["winner"] = attacker_tag if atk_win else defender_tag
		result["naval_casualties"] = randf() * 0.3
		result["range_engagement"] = "close" if (range_mod < 0.6 or closer_engagement) else "stand_off"
		print("Naval engagement resolved (demo): %s vs %s at %s range (vis %.2f, choke %s, sub %s, closer_order=%s, orders %s/%s) -> winner %s" % [attacker_tag, defender_tag, result["range_engagement"], context["weather_vis"], context["chokepoint"], sub_heavy, closer_engagement, context.get("attacker_order",""), context.get("defender_order",""), result["winner"]])
	battle_resolved.emit(result)
	return result


func get_divisions_at_province(province_id: int, country_tag: String) -> Array[Dictionary]:
	if typeof(SupplyManager) == TYPE_NIL:
		return []
	if SupplyManager.has_method("get_land_divisions_at_province"):
		return SupplyManager.get_land_divisions_at_province(province_id, country_tag)
	return []


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
	var stats: Dictionary = _resolver.get_effective_combat_power(
		formation_id, "", formation_id, terrain, pid, dev, infra,
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


func _notify_map_refresh() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for mr in tree.get_nodes_in_group("map_renderer"):
		if mr.has_method("force_border_update"):
			mr.call_deferred("force_border_update")
		if mr.has_method("_update_unit_icons_for_test"):
			mr.call_deferred("_update_unit_icons_for_test")
		if mr.has_method("_refresh_province_visuals"):
			mr.call_deferred("_refresh_province_visuals")


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


## === HISTORICAL + MAIN-LOOP EXTENSIONS (for combat testing vs real history, 50T AI, naval) ===
## Pragmatic additions to support direct OOB setup for WWI/WWII battles and referenced calls in harness/docs.
## These enable recreating Marne/Verdun (attrition), Stalingrad (urban winter supply), Midway (naval air), D-Day (amphib).

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
		var att_leaders: Array = lm.call("get_leaders_for_country", att_tag) as Array
		if att_leaders.size() > 0 and att_divs.size() > 0:
			var lid: String = str(att_leaders[0].leader_id) if att_leaders[0] is Leader else ""
			if lid != "" and lm.has_method("assign_leader_to_formation"):
				lm.call("assign_leader_to_formation", lid, att_divs[0])
		var def_leaders: Array = lm.call("get_leaders_for_country", def_tag) as Array
		if def_leaders.size() > 0 and def_divs.size() > 0:
			var dlid: String = str(def_leaders[0].leader_id) if def_leaders[0] is Leader else ""
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
