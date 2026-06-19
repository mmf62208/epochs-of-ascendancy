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
	var preview := can_assault_province(attacker_tag, target_province_id, from_province_id)
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

	var context := {
		"attacker_tag": tag,
		"defender_tag": preview.get("defender_tag", ""),
		"target_province_id": target_province_id,
		"from_province_id": from_pid,
		"attacker_formation_id": fid,
		"defender_formation_id": defender.formation_id,
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
	if typeof(DebugOverlay) != TYPE_NIL and (str(result.get("attacker_tag","")) == "player" or str(result.get("defender_tag","")) == "player"):
		DebugOverlay.call_deferred("show_battle_aar", result)

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


func apply_combat_outcome(
	result: Dictionary,
	attacker_formation_id: String,
	from_province_id: int,
) -> void:
	var target_pid := int(result.get("target_province_id", result.get("province_id", -1)))
	var attacker_tag := str(result.get("attacker_tag", "")).strip_edges().to_upper()
	var captured := bool(result.get("province_control_change", false))
	var winner := str(result.get("winner", ""))

	# === Balance integration: apply persistent org/readiness/strength damage here (from BM as per design)
	# Loser heavier losses (strength hit), winner lighter org/rdy hit. Recovery via Supply daily (infra/supply mod).
	# This makes combat "have teeth", feeds AAR logs + inspector stationed units state.
	if typeof(LeaderManager) != TYPE_NIL:
		var att_f: Formation = LeaderManager.get_formation(attacker_formation_id) if not attacker_formation_id.is_empty() else null
		var def_fid := str(result.get("defender_formation_id", ""))
		var def_f: Formation = LeaderManager.get_formation(def_fid) if not def_fid.is_empty() else null
		var w := winner
		var dmg_line := "[COMBAT DAMAGE] "
		if att_f != null:
			var is_win := (w == "attacker")
			var org_loss := 0.09 if is_win else 0.27
			var rdy_loss := 0.07 if is_win else 0.22
			att_f.organization = clampf(float(att_f.get("organization", 1.0)) * (1.0 - org_loss + randf() * 0.04), 0.22, 1.0)
			att_f.readiness = clampf(float(att_f.get("readiness", 1.0)) * (1.0 - rdy_loss + randf() * 0.04), 0.28, 1.0)
			if not is_win:
				att_f.strength = clampf(float(att_f.get("strength", 1.0)) * (0.72 + randf() * 0.12), 0.35, 1.0)
			att_f.is_in_combat = true
			dmg_line += "ATT %s: org=%.2f rdy=%.2f str=%.2f ; " % [attacker_formation_id, att_f.organization, att_f.readiness, att_f.strength]
		if def_f != null:
			var is_win_def := (w == "defender")
			var org_loss_d := 0.26 if not is_win_def else 0.10
			var rdy_loss_d := 0.21 if not is_win_def else 0.08
			def_f.organization = clampf(float(def_f.get("organization", 1.0)) * (1.0 - org_loss_d + randf() * 0.04), 0.22, 1.0)
			def_f.readiness = clampf(float(def_f.get("readiness", 1.0)) * (1.0 - rdy_loss_d + randf() * 0.04), 0.28, 1.0)
			if not is_win_def:
				def_f.strength = clampf(float(def_f.get("strength", 1.0)) * (0.62 + randf() * 0.12), 0.30, 1.0)
			def_f.is_in_combat = true
			dmg_line += "DEF %s: org=%.2f rdy=%.2f str=%.2f" % [def_fid, def_f.organization, def_f.readiness, def_f.strength]
		if att_f != null or def_f != null:
			print(dmg_line)

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
	else:
		_post_battle_news(result, false)


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
	var terrain := province.terrain if province != null and province.terrain != "" else "plains"
	var pid := province.id if province != null else -1
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

func execute_chain_assault_or_flank(attacker_tag: String, initial_target: int, staging_from: int = -1, max_depth: int = 2) -> Array:
	"""Chain/flank support for multi-province ops and AI (historical flanking like Manstein or D-Day lodgement expansion)."""
	var results: Array = []
	var current_from := staging_from
	var target := initial_target
	for d in range(max(1, max_depth)):
		var can := can_assault_province(attacker_tag, target, current_from)
		if not bool(can.get("ok", false)):
			break
		var res := execute_province_assault(attacker_tag, target, current_from)
		results.append(res)
		if not bool(res.get("success", false)):
			break
		var rdict := res.get("result", {}) if res.has("result") and typeof(res.get("result",{})) == TYPE_DICTIONARY else res
		if bool(rdict.get("province_control_change", false)):
			current_from = target
			# Flank/chain: pick next adjacent enemy if possible (for historical deep battle or exploitation)
			if typeof(MapManager) != TYPE_NIL:
				var adjs := MapManager.get_adjacent_provinces(target)
				var found_next := false
				for aidv in adjs:
					var aid := int(aidv)
					var ap: Province = MapManager.get_province(aid)
					if ap != null and not ap.is_sea and ap.owner_tag != "" and ap.owner_tag != attacker_tag:
						target = aid
						found_next = true
						break
				if not found_next:
					break  # no easy flank
		else:
			break
	return results

func simulate_daily_ai_combat() -> void:
	"""Main-loop autonomous AI combat for 50+ turn integrated playtests (promoted from harness; scored on supply/infra/low-org + weather + chain)."""
	# Prefer DebugOverlay for full scored logic (weather/geo aware); fallback simple.
	var dbg := get_node_or_null("/root/DebugOverlay")
	if dbg != null and dbg.has_method("_simulate_ai_combat_turn"):
		dbg.call("_simulate_ai_combat_turn")
		print("[BM DAILY AI] delegated to DebugOverlay _simulate (full scoring + chain + weather).")
		return
	# Fallback direct (for pure BM headless without UI)
	print("[BM DAILY AI] fallback simple AI assaults (limited). Extend via TestRunner historical harness for full OOB realism.")
	var mm := get_node_or_null("/root/MapManager")
	if mm == null or not mm.has_method("get_provinces_by_owner"):
		return
	var ai_tags := ["GER", "SOV", "JAP", "ITA"]
	for tag in ai_tags:
		var owned: Array = mm.call("get_provinces_by_owner", tag)
		if owned.size() < 1: continue
		var fromp := int(owned[0])
		var adjs := mm.call("get_adjacent_provinces", fromp)
		for aidv in adjs:
			var aid := int(aidv)
			var p: Province = mm.call("get_province", aid) if mm.has_method("get_province") else null
			if p == null or p.owner_tag == tag or p.owner_tag == "": continue
			var can: Dictionary = can_assault_province(tag, aid, fromp)
			if bool(can.get("ok", false)):
				var cres := execute_chain_assault_or_flank(tag, aid, fromp, 1)
				print("[BM DAILY AI FALLBACK] %s chain assault on %d -> %d results" % [tag, aid, cres.size()])
				break

func execute_naval_engagement(attacker_tag: String, defender_tag: String, sea_province_id: int, intensity: float = 0.5, has_submarines: bool = false, bad_weather: bool = false) -> Dictionary:
	"""Deeper naval integration stub for Midway 1942 etc. Uses registry air/ship presence, weather, subs for carrier/sub battles. Logs factors for AAR."""
	var sm := get_node_or_null("/root/SupplyManager")
	var att_air := 5.0
	var def_air := 3.0
	var att_naval := 12.0
	var def_naval := 9.0
	if sm != null and sm.has_method("get_combat_presence_registry"):
		var reg := sm.call("get_combat_presence_registry")
		if reg != null:
			var rpt := reg.get_report(sea_province_id)
			if rpt != null:
				att_air = float(rpt.total_air(attacker_tag) if rpt.has_method("total_air") else att_air)
				def_air = 0.0
				if "air_by_tag" in rpt:
					for tg in rpt.air_by_tag.keys():
						if str(tg) != attacker_tag:
							def_air += float(rpt.air_by_tag[tg])
				att_naval = float(rpt.navy_total if "navy_total" in rpt else att_naval) * (1.4 if "JAP" in attacker_tag or "USA" in attacker_tag else 1.0)  # carrier weight
				if "naval_strength" in rpt:
					for tg in rpt.naval_strength.keys():
						if str(tg) != attacker_tag:
							def_naval += float(rpt.naval_strength[tg])
	var w_mult := 0.65 if bad_weather else 1.0
	var sub_mult := 1.25 if has_submarines else 1.0
	var att_score := (att_air * 1.8 + att_naval * 0.9) * intensity * w_mult * sub_mult
	var def_score := (def_air * 1.8 + def_naval * 0.9) * intensity * w_mult
	var winner_tag := attacker_tag if att_score >= def_score else defender_tag
	var margin := absf(att_score - def_score) / maxf(max(att_score, def_score), 1.0)
	var result := {
		"winner": winner_tag,
		"attacker_tag": attacker_tag,
		"defender_tag": defender_tag,
		"sea_province_id": sea_province_id,
		"attacker_score": att_score,
		"defender_score": def_score,
		"air_ratio": att_air / maxf(def_air, 0.01),
		"has_submarines": has_submarines,
		"bad_weather": bad_weather,
		"intensity": intensity,
		"outcome": "major_victory" if margin > 0.25 else "minor_victory",
		"key_factors": ["carrier_air_dominance" if att_air > def_air * 1.5 else "surface_gunnery", "submarine_ambush" if has_submarines else "no_sub_factor", "storm_degrades_air" if bad_weather else "clear_skies"],
		"casualties": { "attacker": int(120 + randf() * 180), "defender": int(90 + randf() * 220) },  # planes + ships abstract
		"notes": "Proxy naval/air for historical (Midway: US dive bombers + intel key vs IJN). Expand with full ship templates + task groups."
	}
	print("[BM NAVAL ENGAGEMENT] %s vs %s @sea%d | winner=%s att_score=%.1f def=%.1f airR=%.1f subs=%s storm=%s" % [
		attacker_tag, defender_tag, sea_province_id, winner_tag, att_score, def_score, result["air_ratio"], has_submarines, bad_weather
	])
	# Attach to combat logs if formations involved (future)
	return result

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
		var att_leaders := lm.call("get_leaders_for_country", att_tag)
		if att_leaders.size() > 0 and att_divs.size() > 0:
			var lid := att_leaders[0].leader_id if "leader_id" in att_leaders[0] else ""
			if lid != "" and lm.has_method("assign_leader_to_formation"):
				lm.call("assign_leader_to_formation", lid, att_divs[0])
		var def_leaders := lm.call("get_leaders_for_country", def_tag)
		if def_leaders.size() > 0 and def_divs.size() > 0:
			var dlid := def_leaders[0].leader_id if "leader_id" in def_leaders[0] else ""
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
