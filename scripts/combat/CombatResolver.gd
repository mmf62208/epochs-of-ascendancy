class_name CombatResolver
extends Node

## Central place for resolving battles. Equipment stats, leaders, terrain, and width.


func get_effective_combat_power(
	division_template_id: String,
	unit_id: String = "",
	army_id: String = "",
	terrain: String = "plains",
	province_id: int = -1,
	province_dev: int = -1,
	province_infra: int = -1,
) -> Dictionary:
	var base_stats := ProductionManager.get_division_final_combat_stats(division_template_id, unit_id)

	if base_stats.is_empty():
		return {}

	var leader: Leader = null
	var leader_id := ""
	var terrain_bonus := 0.0
	if not army_id.is_empty() and typeof(LeaderManager) != TYPE_NIL:
		leader = LeaderManager.get_leader_for_army(army_id)
		if leader != null:
			leader_id = leader.leader_id

	if leader != null and typeof(LeaderManager) != TYPE_NIL:
		var nat_mods := LeaderManager.get_national_combat_modifiers(leader.country_tag)
		base_stats = _apply_national_combat_modifiers_to_base_stats(base_stats, nat_mods)

	var combat_stats := base_stats
	if not leader_id.is_empty():
		combat_stats = apply_training_path_modifiers(leader_id, base_stats)

	var final_soft := float(combat_stats.get("soft_attack", 0.0))
	var final_hard := float(combat_stats.get("hard_attack", 0.0))
	var final_readiness := float(combat_stats.get("readiness", 1.0))
	var final_org := float(combat_stats.get("organization", 1.0))

	if leader != null and not leader.is_injured and not leader.is_captured:
		final_soft += leader.get_attack_modifier() * 10.0
		final_hard += leader.get_attack_modifier() * 6.0
		final_org += leader.get_organization_modifier()
		final_readiness += leader.get_logistics_modifier() * 0.5

		terrain_bonus = leader.get_terrain_modifier(terrain)
		final_soft += terrain_bonus * 8.0

	# ============================================================
	# UNIT TYPE SPECIALTY MODIFIERS (HoI4-style detailed % terrain/unit factors, visible in previews/tests/logs)
	# Marines (amphib + vs coast), Paratroop (airdrop bonus, high org loss risk), SF (flanking/sabotage pre-battle), Mountain/Ski (terrain specific), space variants (orbital support).
	# Guided munitions multiplier for advanced units (high impact on soft troops *1.5, less vs armor ~*1.22). Stacks with orbital.
	# ============================================================
	var unit_type := _detect_unit_type(division_template_id)
	var unit_mod_factors: Dictionary = {}
	var guided_mult_soft := 1.0
	var guided_mult_hard := 1.0

	# Detect guided eligibility (space designer + precision rule or special templates)
	var owner_for_tech := (leader.country_tag if leader != null else "player")
	var is_guided_eligible := false
	if typeof(TechnologyManager) != TYPE_NIL:
		if TechnologyManager.has_rule_flag(owner_for_tech, "space_designer_unlocked") or TechnologyManager.has_rule_flag(owner_for_tech, "precision_guided") or TechnologyManager.has_rule_flag(owner_for_tech, "guided_munitions"):
			is_guided_eligible = true
	if unit_type in ["space", "sf"] or "cyber" in division_template_id.to_lower() or "advanced" in division_template_id.to_lower():
		is_guided_eligible = true

	if unit_type == "marine":
		var tlow := terrain.to_lower()
		var is_coastal := tlow in ["coast", "coastal", "beach", "river", "marsh", "island", "delta"]
		if province_for_effects != null:
			var pt := str(province_for_effects.get("terrain", "")).to_lower() if typeof(province_for_effects) == TYPE_DICTIONARY else (province_for_effects.terrain.to_lower() if province_for_effects != null and "terrain" in province_for_effects else "")
			if "coast" in pt or "river" in pt or "beach" in pt:
				is_coastal = true
		if is_coastal:
			final_soft *= 1.28
			final_readiness *= 1.12
			final_org *= 1.06
			unit_mod_factors["marine_amphib_coastal"] = 28
			unit_mod_factors["marine_readiness_coast"] = 12
		else:
			final_soft *= 1.05
			unit_mod_factors["marine_general"] = 5
	elif unit_type == "paratroop":
		final_soft *= 1.18
		final_org *= 0.82
		final_readiness *= 0.90
		unit_mod_factors["paratroop_airdrop_bonus"] = 18
		unit_mod_factors["paratroop_org_risk"] = -18
	elif unit_type == "sf":
		final_soft *= 1.22
		final_hard *= 1.15
		final_readiness *= 1.10
		unit_mod_factors["sf_flanking_sabotage"] = 22
		unit_mod_factors["sf_sabotage_def_org_hit"] = -0.15  # applied in resolve
	elif unit_type == "mountain":
		var tlow := terrain.to_lower()
		if tlow in ["mountains", "hills", "snow_capped", "alpine"]:
			final_soft *= 1.32
			final_readiness *= 1.18
			final_org *= 1.10
			unit_mod_factors["mountain_terrain_bonus"] = 32
		else:
			final_soft *= 0.95
			unit_mod_factors["mountain_off_terrain"] = -5
	elif unit_type == "ski":
		var tlow := terrain.to_lower()
		if tlow in ["snow_capped", "snow", "frozen", "tundra"]:
			final_soft *= 1.35
			final_readiness *= 1.25
			final_org *= 1.08
			unit_mod_factors["ski_winter_terrain"] = 35
	elif unit_type == "space":
		final_soft *= 1.20
		final_hard *= 1.20
		unit_mod_factors["space_orbital_support"] = 20

	# Guided munitions (precision on advanced/space/sf/cyber)
	if is_guided_eligible:
		guided_mult_soft = 1.5
		guided_mult_hard = 1.22
		final_soft *= guided_mult_soft
		final_hard *= guided_mult_hard
		unit_mod_factors["guided_munitions_soft"] = 50
		unit_mod_factors["guided_munitions_hard"] = 22
		has_guided = true  # for downstream

	# Space combat to ground: orbital strikes and guided munitions (from space designer assets).
	# Greater impacts on troops (precision strikes, morale/ org hits for infantry). Costly to maintain.
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(leader.country_tag if leader else "player", "space_designer_unlocked"):
		var space_bonus := 0.15  # base for space support
		# Fixed: use national or later computed guided/strike for condition (preview ref removed - not in scope)
		var has_guided := false
		if typeof(NationalModifierManager) != TYPE_NIL:
			var ncm2 := NationalModifierManager.get_combat_modifiers(leader.country_tag if leader else "")
			has_guided = float(ncm2.get("orbital_guided_munitions", 0.0)) > 0.0
		if has_guided:
			space_bonus = 0.3  # greater for advanced guided
		final_soft += space_bonus * 5.0
		final_hard += space_bonus * 3.0
		# Greater org loss for enemy if space strike (use global space strike state if present)
		if has_guided:
			final_org *= 0.85  # extra org hit from orbital guided on troops
		final_hard += terrain_bonus * 5.0

	# Province infrastructure & development effects (Deeper Combat integration - Phase 1 item 2)
	# Prefer passed dev/infra, then lookup by province_id via ScenarioLoader, else light proxy.
	var prov_dev := province_dev
	var prov_infra := province_infra
	var province_for_effects: Province = null
	if prov_dev < 0 or prov_infra < 0:
		# Prefer MapManager (central, fast)
		var p: Province = null
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			p = MapManager.get_province(province_id)
		if p == null:
			var loader := _find_scenario_loader()
			if loader != null and province_id >= 0 and loader.provinces.has(province_id):
				p = loader.provinces[province_id]
		if p != null:
			province_for_effects = p
			if prov_dev < 0:
				prov_dev = p.development_level
			if prov_infra < 0:
				prov_infra = p.infrastructure
			if terrain.is_empty() or terrain == "plains":
				terrain = p.terrain if p.terrain != "" else terrain

	if prov_dev < 0:
		prov_dev = 0
	if prov_infra < 0:
		prov_infra = 0

	# Use Province getter or ProvinceEffects for accurate org/recovery/readiness in this province
	var org_mod := 1.0
	var attrition_mod := 1.0
	var has_province_context := province_id >= 0 or province_for_effects != null
	if has_province_context:
		if province_for_effects != null and typeof(ProvinceEffects) != TYPE_NIL:
			# Country tag optional for national layer; empty falls back to pure province dev/infra
			var owner_tag := ""
			if typeof(LeaderManager) != TYPE_NIL and not army_id.is_empty():
				var lid := LeaderManager.get_leader_id_for_army(army_id)
				if lid != "" and LeaderManager.leaders.has(lid):
					owner_tag = LeaderManager.leaders[lid].country_tag
			var pe := _get_effects_for_province(province_for_effects, owner_tag)
			org_mod = pe.get_effective_organization_recovery() if pe != null else 1.0
			attrition_mod = pe.get_effective_attrition_multiplier() if pe != null else 1.0
		elif province_for_effects != null:
			org_mod = province_for_effects.get_organization_recovery_modifier()
			attrition_mod = province_for_effects.get_attrition_modifier()
		else:
			# Fallback: scale from raw dev/infra (matches Province.gd formulas lightly)
			org_mod = 0.6 + (float(prov_infra) * 0.025) + (float(prov_dev) * 0.015)
			attrition_mod = maxf(0.6, 1.0 - (float(prov_dev) * 0.015))

		# Apply: higher org_mod = better recovery/readiness; lower attrition_mod = less org/readiness loss
		final_org += (org_mod - 1.0) * 6.0
		final_readiness += (org_mod - 1.0) * 3.0
		# Attrition in province reduces effective readiness/org (defensive penalty in bad terrain)
		if attrition_mod < 1.0:
			final_readiness *= attrition_mod
			final_org *= lerp(1.0, attrition_mod, 0.6)

	# Note: For full battle resolution paths (resolve_battle_aftermath etc.), pass province_id/dev
	# so casualty rolls and post-battle org can also respect province stats via similar getters.

	var national_combat := {}

	# === Light National Spirit / Temporary Modifier Integration (Combat) ===
	# One step further from the national_bonuses integration in LeaderManager.
	if leader != null and typeof(LeaderManager) != TYPE_NIL:
		national_combat = LeaderManager.get_national_combat_modifiers(leader.country_tag)

	# Secret fleet wiring: apply peace_state secret_fleet_combat_bonus (from secret_space_programs) for naval/space/special formations (small +% edge)
	if leader != null and typeof(GameData) != TYPE_NIL and GameData.has_method("get_secret_fleet_combat_bonus"):
		var sec_bonus := GameData.get_secret_fleet_combat_bonus(leader.country_tag)
		if sec_bonus > 0.0:
			national_combat["secret_fleet"] = sec_bonus
			print("[SECRET FLEET] +%.0f%% combat bonus applied for %s (naval/space or secret tag; vs conventional; exposure risk in events)" % [sec_bonus*100, leader.country_tag])

	# Apply organization/attack bonuses from national (de-indented, always for leader; was broken under secret if + modified ref)
	if leader != null and typeof(LeaderManager) != TYPE_NIL:
		# Apply organization bonus from national spirits/modifiers
		var org_bonus := float(national_combat.get("army_org_factor", 0.0))
		if org_bonus != 0.0:
			final_org += org_bonus * 5.0   # Scale to match other combat stat units

		# Apply attack bonus (if present)
		var attack_bonus := float(national_combat.get("attack_factor", 0.0))
		if attack_bonus != 0.0:
			final_soft += attack_bonus * 8.0
			final_hard += attack_bonus * 5.0


	# === Space strike + guided munitions + unit specialization wiring (task: orbital strikes as air/ground support, space on ground impacts, unit mods for marines/paras/SF/mtn/ski/space) ===
	var space_strike_b := 0.0
	var orb_guided := 0.0
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_space_strike_bonus"):
		space_strike_b = GameData.get_space_strike_bonus(leader.country_tag if leader else "")
	if typeof(NationalModifierManager) != TYPE_NIL:
		var ncm := NationalModifierManager.get_combat_modifiers(leader.country_tag if leader else "")
		space_strike_b = max(space_strike_b, float(ncm.get("space_strike_bonus", 0.0)))
		orb_guided = float(ncm.get("orbital_guided_munitions", 0.0))
	# Apply national space strike to base attacks (designer space support)
	if space_strike_b > 0.0:
		final_soft += space_strike_b * 15.0
		final_hard += space_strike_b * 12.0
		final_org += space_strike_b * 3.0
		print("[SPACE GROUND] +%.0f%% strike_bonus from orbital assets applied to attacks (guided munitions / recon support)" % (space_strike_b * 100.0))
	# Unit specialization (marine etc + space_capable enhanced by orbital)
	var spec_mods := {}
	if leader != null and typeof(SupplyManager) != TYPE_NIL:
		# note: get_effective uses division_template_id param; for live use template from division
		var dt: DivisionTemplate = null
		if division_template_id and SupplyManager.division_templates:
			dt = SupplyManager.division_templates.get_division(division_template_id)
		if dt and dt.has_method("get_specialization_modifiers"):
			var has_ss := space_strike_b > 0.0 or orb_guided > 0.0
			spec_mods = dt.get_specialization_modifiers(terrain, has_ss, space_strike_b)
			if spec_mods.get("special", "") != "":
				final_soft += float(spec_mods.get("soft_attack_mod", 0.0)) * 10.0
				final_hard += float(spec_mods.get("hard_attack_mod", 0.0)) * 8.0
				final_readiness += float(spec_mods.get("readiness_mod", 0.0))
				final_org += float(spec_mods.get("org_mod", 0.0)) * 5.0
				if spec_mods.get("special") == "space_capable" and has_ss:
					print("[SPACE UNIT] space_capable unit +orbital support: precision guided edge vs classic (soft+%.1f hard+%.1f)" % [spec_mods.get("soft_attack_mod",0), spec_mods.get("hard_attack_mod",0)])

		# Apply defence bonus (maps to readiness/org in this context)
		var def_bonus := float(national_combat.get("defence_factor", 0.0))
		if def_bonus != 0.0:
			final_readiness += def_bonus * 3.0
			final_org += def_bonus * 2.0

	var training_path_bonus := float(combat_stats.get("training_path_soft_bonus", 0.0))

	return {
		"soft_attack": final_soft,
		"hard_attack": final_hard,
		"readiness": clampf(final_readiness, 0.3, 1.8),
		"organization": clampf(final_org, 0.4, 1.5),
		"supply_consumption": float(combat_stats.get("supply_consumption", 1.0)),
		"has_shortages": bool(base_stats.get("has_shortages", false)),
		"leader_name": leader.name if leader != null else "No Leader",
		"leader_id": leader_id,
		"leader_attack_bonus": leader.get_attack_modifier() if leader != null else 0.0,
		"training_path_soft_bonus": training_path_bonus,
		"unit_type": unit_type,
		"unit_mod_factors": unit_mod_factors,
		"guided_munitions_applied": is_guided_eligible,
		"guided_soft_mult": guided_mult_soft,
		"training_path_modifiers": combat_stats.get("training_path_modifiers", {}),
		"terrain": terrain,
		"terrain_bonus_applied": terrain_bonus,
		"national_combat_modifiers": national_combat if leader != null else {},
		# space wiring evidence + new strike/orbital + unit spec
		"space_wiring": {"secret_fleet": national_combat.get("secret_fleet", 0.0), "shields": national_combat.get("defensive_shielding",0.0) if national_combat else 0.0, "strike": space_strike_b, "guided": orb_guided, "unit_spec": spec_mods.get("special","") if spec_mods else "" },
		"space_strike_bonus": space_strike_b,
		"orbital_guided_munitions": orb_guided,
	}


# ============================================
# TRAINING PATH - COMBAT INTEGRATION
# ============================================

## Applies training path combat bonuses to a leader's core combat stat dictionary (additive).
func apply_training_path_combat_bonuses(leader_id: String, stats: Dictionary) -> Dictionary:
	if leader_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return stats

	var modifiers := LeaderManager.get_leader_training_path_combat_modifiers(leader_id)
	if modifiers.is_empty():
		return stats

	var modified_stats := stats.duplicate()

	if modifiers.has("attack") and modified_stats.has("attack"):
		modified_stats["attack"] = float(modified_stats["attack"]) + float(modifiers["attack"])
	if modifiers.has("defense") and modified_stats.has("defense"):
		modified_stats["defense"] = float(modified_stats["defense"]) + float(modifiers["defense"])
	if modifiers.has("initiative") and modified_stats.has("initiative"):
		modified_stats["initiative"] = float(modified_stats["initiative"]) + float(modifiers["initiative"])
	if modifiers.has("breakthrough") and modified_stats.has("breakthrough"):
		modified_stats["breakthrough"] = float(modified_stats["breakthrough"]) + float(modifiers["breakthrough"])
	if modifiers.has("planning") and modified_stats.has("planning"):
		modified_stats["planning"] = float(modified_stats["planning"]) + float(modifiers["planning"])

	return modified_stats


## Applies training path bonuses to division combat stats (before trait-based leader modifiers).
func apply_training_path_modifiers(leader_id: String, base_stats: Dictionary) -> Dictionary:
	if leader_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return base_stats

	var modifiers := LeaderManager.get_leader_training_path_combat_modifiers(leader_id)
	if modifiers.is_empty():
		return base_stats

	var modified := apply_training_path_combat_bonuses(leader_id, base_stats)
	var soft_bonus := 0.0
	var hard_bonus := 0.0

	if modifiers.has("attack"):
		var attack_levels := float(modifiers["attack"])
		soft_bonus += attack_levels * 1.5
		hard_bonus += attack_levels * 0.9

	if modifiers.has("defense"):
		var defense_levels := float(modifiers["defense"])
		modified["organization"] = float(modified.get("organization", 1.0)) + defense_levels * 0.05

	if modifiers.has("initiative"):
		var init_levels := float(modifiers["initiative"])
		modified["readiness"] = float(modified.get("readiness", 1.0)) + init_levels * 0.04

	if modifiers.has("planning"):
		var plan_levels := float(modifiers["planning"])
		modified["readiness"] = float(modified.get("readiness", 1.0)) + plan_levels * 0.03

	if modifiers.has("breakthrough"):
		var breakthrough := float(modifiers["breakthrough"])
		soft_bonus += breakthrough * 8.0
		hard_bonus += breakthrough * 5.0

	if modifiers.has("combined_arms_sync"):
		var sync := float(modifiers["combined_arms_sync"])
		soft_bonus += sync * 8.0
		hard_bonus += sync * 5.0
		modified["combined_arms_sync"] = float(modified.get("combined_arms_sync", 0.0)) + sync

	if modifiers.has("organization_recovery"):
		var recovery := float(modifiers["organization_recovery"])
		modified["organization"] = float(modified.get("organization", 1.0)) + recovery * 0.5
		modified["organization_recovery"] = float(modified.get("organization_recovery", 0.0)) + recovery

	modified["soft_attack"] = float(modified.get("soft_attack", 0.0)) + soft_bonus
	modified["hard_attack"] = float(modified.get("hard_attack", 0.0)) + hard_bonus
	modified["training_path_soft_bonus"] = soft_bonus
	modified["training_path_modifiers"] = modifiers
	return modified


## Call once when a battle concludes (not during power previews).
func resolve_combat_experience(
	attacker_army_id: String = "",
	defender_army_id: String = "",
	intensity: float = 1.0,
	battle_result: Dictionary = {},
) -> Dictionary:
	return resolve_battle_aftermath(attacker_army_id, defender_army_id, battle_result, intensity, -1, -1)


## Awards combat XP, rolls leader casualties, returns summary for UI/debug.
## Phase 1: province_* ids allow accurate org/casualty scaling via dev/infra (no more pure proxy).
func resolve_battle_aftermath(
	attacker_army_id: String = "",
	defender_army_id: String = "",
	battle_result: Dictionary = {},
	intensity: float = 1.0,
	attacker_province_id: int = -1,
	defender_province_id: int = -1,
) -> Dictionary:
	var results := {
		"attacker_casualty": {},
		"defender_casualty": {},
		"attacker_xp": 0,
		"defender_xp": 0,
	}
	if typeof(LeaderManager) == TYPE_NIL:
		return results

	var xp_context := battle_result.duplicate()
	if not xp_context.has("intensity"):
		xp_context["intensity"] = intensity

	var attacker_leader_id := LeaderManager.get_leader_id_for_army(attacker_army_id)
	var defender_leader_id := LeaderManager.get_leader_id_for_army(defender_army_id)

	if not xp_context.is_empty() or attacker_leader_id != "" or defender_leader_id != "":
		var normalized := _normalize_battle_result(xp_context, intensity)
		award_xp_from_combat(attacker_leader_id, defender_leader_id, normalized)
		if attacker_leader_id != "":
			results["attacker_xp"] = _total_combat_xp_for_leader(attacker_leader_id, normalized, 1.0)
		if defender_leader_id != "":
			var defender_scale := 1.0
			if str(normalized.get("outcome", "")) != "heroic_defense":
				defender_scale = 0.85
			results["defender_xp"] = _total_combat_xp_for_leader(
				defender_leader_id,
				normalized,
				defender_scale,
			)
	elif not attacker_army_id.is_empty() or not defender_army_id.is_empty():
		# Legacy fallback when no battle_result dict is provided.
		if not attacker_army_id.is_empty():
			LeaderManager.award_combat_experience_for_army(attacker_army_id, intensity)
		if not defender_army_id.is_empty():
			LeaderManager.award_combat_experience_for_army(defender_army_id, intensity * 0.65)

	# Province dev/infra affects casualty rates (high dev = lower losses, better recovery)
	var attacker_casualty_mult := _get_province_casualty_multiplier(attacker_province_id)
	var defender_casualty_mult := _get_province_casualty_multiplier(defender_province_id)

	if not attacker_army_id.is_empty():
		results["attacker_casualty"] = LeaderManager.roll_combat_battle_casualty(
			attacker_army_id,
			intensity * attacker_casualty_mult,
		)
	if not defender_army_id.is_empty():
		results["defender_casualty"] = LeaderManager.roll_combat_battle_casualty(
			defender_army_id,
			intensity * 0.65 * defender_casualty_mult,
		)
	return results


## Call when a formation is eliminated; ~30% chance of leader death or capture.
func resolve_formation_destroyed(formation_id: String) -> Dictionary:
	if typeof(LeaderManager) == TYPE_NIL or formation_id.is_empty():
		return {"type": "none", "leader_id": ""}
	return LeaderManager.handle_formation_destroyed(formation_id)


func get_combat_width_for_battle(
	attacker_province_id: int,
	defender_province_id: int,
	terrain: String = "",
) -> float:
	var attacker_infra := 2
	var defender_infra := 2
	var attacker_dev := 1
	var defender_dev := 1
	var battle_terrain := terrain

	# Use centralized MapManager when possible (preferred after MapManager introduction)
	var attacker: Province = _get_province_safe(attacker_province_id)
	if attacker != null:
		attacker_infra = attacker.infrastructure
		attacker_dev = attacker.development_level
		if battle_terrain.is_empty():
			battle_terrain = attacker.terrain

	var defender: Province = _get_province_safe(defender_province_id)
	if defender != null:
		defender_infra = defender.infrastructure
		defender_dev = defender.development_level
		if battle_terrain.is_empty():
			battle_terrain = defender.terrain

	if battle_terrain.is_empty():
		battle_terrain = "plains"

	var calculator := CombatWidthCalculator.new()
	var width := calculator.get_effective_combat_width(attacker_infra, defender_infra, battle_terrain)
	calculator.free()

	# Development level gives a small bonus to effective combat width (better C3, roads, etc.)
	var dev_bonus := (float(attacker_dev) + float(defender_dev)) * 0.015
	width *= (1.0 + dev_bonus)

	# Apply per-province combat width modifiers (infrastructure/development effects)
	# Uses already-fetched attacker/defender Provinces (prefer MapManager path)
	var prov_mod := 1.0
	var mod_count := 0
	if attacker != null:
		prov_mod *= attacker.get_combat_width_modifier()
		mod_count += 1
	if defender != null:
		prov_mod *= defender.get_combat_width_modifier()
		mod_count += 1
	if mod_count == 2:
		width *= sqrt(prov_mod)
	elif mod_count == 1:
		width *= prov_mod

	return width


## UI-friendly battle location summary (rules width + province getters).
func get_province_battle_preview(attacker: Province, defender: Province) -> Dictionary:
	if attacker == null or defender == null:
		return {}
	return ProvinceInsight.get_battle_preview(attacker, defender)


func _find_scenario_loader() -> ScenarioLoader:
	# Preferred path: go through MapManager (centralized, no tree walks)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
		# MapManager doesn't expose the full legacy ScenarioLoader object.
		# Callers should prefer the MapManager / ProvinceEffects paths.
		pass

	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	var loader_node: Node = tree.root.find_child("ScenarioLoader", true, false)
	return loader_node as ScenarioLoader

## Preferred helper for new code: returns Province via MapManager when available
func _get_province_safe(province_id: int) -> Province:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
		var p := MapManager.get_province(province_id)
		if p != null:
			return p
	# Fallback to old loader walk (kept for compatibility during transition)
	var loader := _find_scenario_loader()
	if loader != null and loader.provinces.has(province_id):
		return loader.provinces[province_id] as Province
	return null


## Returns casualty multiplier from province dev (high dev/infra = lower casualties due to better med/logistics).
## >1.0 means higher losses (bad province), <1.0 means reduced losses (good province).
func _get_province_casualty_multiplier(province_id: int) -> float:
	if province_id < 0:
		return 1.0
	var p: Province = _get_province_safe(province_id)
	if p == null:
		return 1.0
	# Reuse attrition_modifier logic (higher dev = lower mult) + slight infra help
	var dev := float(clampi(p.development_level, 0, 50))
	var infra := float(clampi(p.infrastructure, 0, 50))
	var base := maxf(0.65, 1.0 - (dev * 0.018) + (infra * 0.005))
	# Also respect ProvinceEffects national layer if present (e.g. medic spirits, agent sabotage on infra)
	if typeof(ProvinceEffects) != TYPE_NIL:
		var pe := _get_effects_for_province(p, p.controller_tag if p.controller_tag != "" else p.owner_tag)
		if pe != null:
			var eff_attr := pe.get_effective_attrition_multiplier()
			base = lerp(base, eff_attr, 0.5)
	return clampf(base, 0.55, 1.35)


## Internal helper — prefers MapManager for ProvinceEffects (centralized national + dev/infra)
func _get_effects_for_province(p: Province, tag: String) -> ProvinceEffects:
	if p == null:
		return null
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_effects"):
		var fx := MapManager.get_province_effects(p.id, tag)
		if fx != null:
			return fx
	if typeof(ProvinceEffects) != TYPE_NIL:
		return ProvinceEffects.for_country_province(p, tag)
	return null


# ============================================
# XP SYSTEM - Combat Integration
# ============================================

## Awards XP to leaders after a battle has resolved. Call after combat is finalized.
func award_xp_from_combat(
	attacker_leader_id: String,
	defender_leader_id: String,
	battle_result: Dictionary,
) -> void:
	if typeof(LeaderManager) == TYPE_NIL:
		return

	if not attacker_leader_id.is_empty():
		_apply_combat_xp_to_leader(attacker_leader_id, battle_result, 1.0)

	if not defender_leader_id.is_empty():
		var defender_scale := 1.0
		if str(battle_result.get("outcome", "")) != "heroic_defense":
			defender_scale = 0.85
		_apply_combat_xp_to_leader(defender_leader_id, battle_result, defender_scale)


func _apply_combat_xp_to_leader(
	leader_id: String,
	battle_result: Dictionary,
	scale: float = 1.0,
) -> int:
	var xp_data := _calculate_combat_xp(battle_result, leader_id)
	var total := int(xp_data.get("total_xp", 12))
	total = maxi(int(float(total) * clampf(scale, 0.25, 4.0)), 1)
	xp_data["total_xp"] = total
	LeaderManager.award_combat_xp(leader_id, xp_data)
	return total


func _total_combat_xp_for_leader(
	leader_id: String,
	battle_result: Dictionary,
	scale: float = 1.0,
) -> int:
	var xp_data := _calculate_combat_xp(battle_result, leader_id)
	var total := int(xp_data.get("total_xp", 12))
	return maxi(int(float(total) * clampf(scale, 0.25, 4.0)), 1)


## Calculates how much XP should be awarded based on battle outcome.
func _calculate_combat_xp(battle_result: Dictionary, leader_id: String = "") -> Dictionary:
	var base_xp := 12
	var bonus := 0

	var outcome: String = str(battle_result.get("outcome", "defeat"))

	match outcome:
		"major_victory":
			bonus = 60
		"heroic_defense":
			bonus = 80
		"high_risk_success":
			bonus = 40
		"minor_victory", "delay_success":
			bonus = 20
		"defeat":
			bonus = 0
		"crushing_defeat":
			bonus = 0

	var battle_scale: float = float(battle_result.get("battle_scale", 1.0))
	bonus = int(float(bonus) * clampf(battle_scale, 0.25, 4.0))

	var defeat_bonus := 0
	if outcome in ["defeat", "crushing_defeat"] and not leader_id.is_empty():
		defeat_bonus = _get_defeat_learning_bonus(leader_id)

	return {
		"base_xp": base_xp,
		"bonus_xp": bonus,
		"defeat_learning_bonus": defeat_bonus,
		"total_xp": base_xp + bonus + defeat_bonus,
	}


## Trait-based bonus XP when a leader fights through a defeat.
func _get_defeat_learning_bonus(leader_id: String) -> int:
	if leader_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return 0

	var leader := LeaderManager.get_leader(leader_id)
	if leader == null:
		return 0

	var bonus := 0
	if int(leader.trait_levels.get("methodical", 0)) > 0:
		bonus += 8
	if int(leader.trait_levels.get("iron_will", 0)) > 0:
		bonus += 10
	if int(leader.trait_levels.get("cautious", 0)) > 0:
		bonus += 6
	return bonus


func _normalize_battle_result(battle_result: Dictionary, intensity: float = 1.0) -> Dictionary:
	var result := battle_result.duplicate()
	if not result.has("intensity"):
		result["intensity"] = intensity
	if result.has("outcome"):
		return result
	if bool(result.get("is_major_victory", false)):
		result["outcome"] = "major_victory"
	elif bool(result.get("is_heroic_defense", false)):
		result["outcome"] = "heroic_defense"
	elif bool(result.get("was_high_risk", false)) and bool(result.get("success", false)):
		result["outcome"] = "high_risk_success"
	elif bool(result.get("success", false)):
		result["outcome"] = "minor_victory"
	else:
		result["outcome"] = "defeat"
	return result


## Applies national combat modifiers (from spirits + temporary effects) to base division stats.
## This is the deeper integration at the division info level.
func _apply_national_combat_modifiers_to_base_stats(stats: Dictionary, nat_mods: Dictionary) -> Dictionary:
	if nat_mods.is_empty() or stats.is_empty():
		return stats

	var modified := stats.duplicate()

	# Apply attack / soft / hard bonuses
	var attack_mod := float(nat_mods.get("attack_factor", 0.0))
	if attack_mod != 0.0:
		if modified.has("soft_attack"):
			modified["soft_attack"] = float(modified["soft_attack"]) * (1.0 + attack_mod * 0.5)
		if modified.has("hard_attack"):
			modified["hard_attack"] = float(modified["hard_attack"]) * (1.0 + attack_mod * 0.5)

	# Apply defence / readiness / org
	var def_mod := float(nat_mods.get("defence_factor", 0.0))
	if def_mod != 0.0:
		if modified.has("readiness"):
			modified["readiness"] = float(modified["readiness"]) * (1.0 + def_mod)
		if modified.has("organization"):
			modified["organization"] = float(modified["organization"]) * (1.0 + def_mod * 0.5)

	# Army org factor (often from spirits)
	var org_mod := float(nat_mods.get("army_org_factor", 0.0))
	if org_mod != 0.0 and modified.has("organization"):
		modified["organization"] = float(modified["organization"]) * (1.0 + org_mod)

	# Manpower / replacement related
	var mp_mod := float(nat_mods.get("manpower_factor", 0.0))
	if mp_mod != 0.0 and modified.has("manpower"):
		modified["manpower"] = float(modified["manpower"]) * (1.0 + mp_mod)

	# === Space full wiring + advanced combat: deflector_shields_1995 defensive_shielding % absorb/pre-readiness dmg reduction
	var shield := float(nat_mods.get("defensive_shielding", 0.0))
	if shield > 0.0:
		if modified.has("readiness"):
			modified["readiness"] = float(modified["readiness"]) * (1.0 + shield * 0.4)  # pre dmg readiness
		# % absorb note: applied in phased resolution as score reduction for defender/attacker if shielded
		modified["shield_absorb"] = shield
		print("[SPACE WIRING] defensive_shielding %.0f%% absorb/pre-readiness applied (deflector 1995 + nat_mod)" % (shield*100))
	# energy_weapon_dmg / phasers from DEW 2030 (boost hard for energy flavor)
	var ewd := float(nat_mods.get("energy_weapon_dmg", 0.0))
	if ewd > 0.0 and modified.has("hard_attack"):
		modified["hard_attack"] = float(modified["hard_attack"]) * (1.0 + ewd * 0.6)
		print("[SPACE WIRING] energy_weapon_dmg / phasers_torpedoes +%.0f%% hard (DEW variable stun/kill flavor)" % (ewd*100))
	# precision_strike / drone from nat (already in some, boost soft)
	var prec := float(nat_mods.get("precision_strike", 0.0))
	if prec > 0.0 and modified.has("soft_attack"):
		modified["soft_attack"] = float(modified["soft_attack"]) * (1.0 + prec * 0.5)
	# Power battle armor 1970 / infantry_enhance: soft/hard + readiness/org , mobility trade (small org penalty)
	var inf_enh := float(nat_mods.get("infantry_enhancement", 0.0)) + float(nat_mods.get("soldier_enhancement", 0.0))
	if inf_enh > 0.0 or (typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.is_tech_completed(nat_mods.get("tag",""), "battle_power_armor_1970") if nat_mods.has("tag") else false):
		if modified.has("soft_attack"): modified["soft_attack"] = float(modified.get("soft_attack",0)) * (1.0 + inf_enh * 0.3 + 0.08)
		if modified.has("hard_attack"): modified["hard_attack"] = float(modified.get("hard_attack",0)) * (1.0 + inf_enh * 0.25 + 0.06)
		if modified.has("readiness"): modified["readiness"] = float(modified.get("readiness",1)) * (1.0 + inf_enh * 0.15)
		if modified.has("organization"):
			modified["organization"] = float(modified.get("organization",1)) * (1.0 + inf_enh * 0.1)
			modified["organization"] = float(modified.get("organization",1)) * 0.97  # mobility trade
		print("[SPACE WIRING] power_battle_armor / infantry_enh +soft/hard/readiness/org (mobility trade)")

	return modified


# ============================================
# PHASED BATTLE RESOLUTION
# ============================================

signal combat_phase_advanced(phase: String, data: Dictionary)
signal combat_resolved(result: Dictionary)

const PHASE_POSITIONING := "POSITIONING"
const PHASE_ENGAGEMENT := "ENGAGEMENT"
const PHASE_ATTRITION := "ATTRITION"
const PHASE_RESOLUTION := "RESOLUTION"


func resolve_combat(
	attacker: Formation,
	defender: Formation,
	battle_province: Province,
	attacker_army_id: String = "",
	defender_army_id: String = "",
) -> Dictionary:
	if battle_province == null:
		return {"winner": "", "outcome": "invalid", "province_control_change": false}

	var att_tag := attacker.country_tag if attacker != null else ""
	var def_tag := battle_province.owner_tag
	if def_tag.is_empty() and defender != null:
		def_tag = defender.country_tag

	var att_template := attacker.formation_id if attacker != null else "us_infantry_div_ww2"
	var def_template := defender.formation_id if defender != null else "german_infantry_division_1943"
	if attacker_army_id.is_empty() and attacker != null:
		attacker_army_id = attacker.formation_id
	if defender_army_id.is_empty() and defender != null:
		defender_army_id = defender.formation_id

	var terrain := battle_province.terrain if battle_province.terrain != "" else "plains"
	var att_power := get_effective_combat_power(
		att_template, "", attacker_army_id, terrain,
		battle_province.id, battle_province.development_level, battle_province.infrastructure,
	)
	var def_power := get_effective_combat_power(
		def_template, "", defender_army_id, terrain,
		battle_province.id, battle_province.development_level, battle_province.infrastructure,
	)
	if att_power.is_empty() or def_power.is_empty():
		return {"winner": "", "outcome": "invalid", "province_control_change": false}

	var side_state := {
		"attacker": {
			"soft": float(att_power.get("soft_attack", 1.0)),
			"hard": float(att_power.get("hard_attack", 0.0)),
			"org": float(att_power.get("organization", 1.0)),
			"readiness": float(att_power.get("readiness", 1.0)),
		},
		"defender": {
			"soft": float(def_power.get("soft_attack", 1.0)),
			"hard": float(def_power.get("hard_attack", 0.0)),
			"org": float(def_power.get("organization", 1.0)),
			"readiness": float(def_power.get("readiness", 1.0)),
		},
	}

	combat_phase_advanced.emit(PHASE_POSITIONING, _phase_positioning(battle_province, side_state))

	# SF pre-battle sabotage (from unit_mod_factors in power calc; applies org/readiness hit to defender)
	if def_power.get("unit_mod_factors", {}).has("sf_sabotage_def_org_hit"):
		var sabo := float(def_power["unit_mod_factors"]["sf_sabotage_def_org_hit"])
		if "org" in side_state["defender"]:
			side_state["defender"]["org"] *= max(0.6, 1.0 + sabo)
		if "readiness" in side_state["defender"]:
			side_state["defender"]["readiness"] *= max(0.7, 1.0 + sabo * 0.5)
		print("[SF SABOTAGE] Pre-battle special forces hit defender org/readiness by ", sabo)

	combat_phase_advanced.emit(PHASE_POSITIONING, _phase_positioning(battle_province, side_state))

	# === AIR SUPERIORITY (continuous scale) ===
	# CAS bonus scales with air_power_ratio (from assets + missions via Profile in preview, here registry assets + weather/night).
	# Overwhelming (4:1+) for full effect in large provinces. Slight adv not enough to ground enemy.
	# Night/weather heavily penalize air (interact).
	# Also drains supply for disadv side (handled in Supply calc, reflected in readiness if low).
	var air_power_ratio := 1.0
	var air_dominance_level := "none"
	var cas_mult := 1.0
	var sm = null
	var tree := Engine.get_main_loop()
	if tree:
		sm = tree.root.get_node_or_null("SupplyManager")
	if sm and sm.has_method("get_combat_presence_registry"):
		var reg = sm.call("get_combat_presence_registry")
		if reg:
			var rpt = reg.get_report(battle_province.id)
			var aa := 0.0
			var ea := 0.0
			if att_tag != "":
				aa = rpt.total_air(att_tag)
			for tg in rpt.air_by_tag:
				if str(tg) != att_tag:
					ea += rpt.total_air(tg)
			if aa + ea > 0.01:
				air_power_ratio = aa / maxf(ea, 0.01)
			if air_power_ratio >= 4.0:
				air_dominance_level = "full"
				cas_mult = 1.35
			elif air_power_ratio >= 1.8:
				air_dominance_level = "partial"
				cas_mult = 1.12 + clampf((air_power_ratio - 1.8) * 0.08, 0.0, 0.2)
			else:
				air_dominance_level = "none"
				cas_mult = maxf(0.65, 0.75 + air_power_ratio * 0.15)
	# Weather + night interact with air (big penalty)
	var air_weather := 1.0
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_air_mission_effectiveness"):
			air_weather = WeatherManager.get_air_mission_effectiveness(battle_province.id)
		cas_mult *= air_weather
	var is_night := false
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("game_hour"):
		var hr = TimeManager.game_hour
		is_night = (hr < 6 or hr > 20)
	if is_night:
		cas_mult *= 0.62  # night hurts air CAS more
	# Apply CAS to attacker (scales continuously)
	side_state["attacker"]["soft"] *= cas_mult
	side_state["attacker"]["hard"] *= cas_mult * 0.85
	# Disadv air also reduces readiness slightly (cost bleed modeled)
	if air_power_ratio < 1.0:
		side_state["attacker"]["readiness"] *= clampf(0.72 + air_power_ratio * 0.2, 0.55, 0.95)

	combat_phase_advanced.emit(PHASE_ENGAGEMENT, _phase_engagement(battle_province, side_state, att_power, def_power))
	combat_phase_advanced.emit(PHASE_ATTRITION, _phase_attrition(battle_province, side_state, att_power, def_power))
	var result := _phase_resolution(battle_province, side_state, att_tag, def_tag)

	combat_phase_advanced.emit(PHASE_RESOLUTION, result)
	combat_resolved.emit(result)
	# attach air computed in this scope
	result["air_power_ratio"] = air_power_ratio
	result["air_dominance_level"] = air_dominance_level
	result["air_superiority_attacker"] = (air_power_ratio >= 1.8)
	result["cas_mult"] = cas_mult
	result["is_night"] = is_night
	result["air_weather_mod"] = air_weather
	return result


func _phase_positioning(battle_province: Province, side_state: Dictionary) -> Dictionary:
	var infra_bonus := clampf(float(battle_province.infrastructure) * 0.04, 0.0, 0.25)
	side_state["defender"]["org"] *= 1.0 + infra_bonus
	if battle_province.terrain in ["mountains", "jungle", "urban", "marsh"]:
		side_state["defender"]["soft"] *= 1.08
	return {"terrain": battle_province.terrain, "infra_bonus": infra_bonus}


func _phase_engagement(
	battle_province: Province,
	side_state: Dictionary,
	_att_power: Dictionary,
	_def_power: Dictionary,
) -> Dictionary:
	var width := get_combat_width_for_battle(battle_province.id, battle_province.id, battle_province.terrain)
	var width_scale := clampf(width / 10.0, 0.35, 1.35)
	side_state["attacker"]["soft"] *= width_scale
	side_state["defender"]["soft"] *= clampf(width_scale * 1.05, 0.4, 1.4)
	# Space flavor: if phaser or drone, small extra in engagement (reuse power passed? but for live add via NMM)
	# (smallest: log if evidence, actual dmg via power pre-apply)
	return {
		"width": width,
		"attacker_strength": _side_strength(side_state["attacker"]),
		"defender_strength": _side_strength(side_state["defender"]),
	}


func _phase_attrition(
	_battle_province: Province,
	side_state: Dictionary,
	att_power: Dictionary,
	def_power: Dictionary,
) -> Dictionary:
	var att_supply := 1.0
	var def_supply := 1.0
	if bool(att_power.get("has_shortages", false)):
		att_supply = 0.82
	if bool(def_power.get("has_shortages", false)):
		def_supply = 0.88
	side_state["attacker"]["readiness"] *= att_supply
	side_state["defender"]["readiness"] *= def_supply
	side_state["attacker"]["org"] *= lerpf(1.0, att_supply, 0.5)
	side_state["defender"]["org"] *= lerpf(1.0, def_supply, 0.55)
	return {"attacker_supply": att_supply, "defender_supply": def_supply}


func _phase_resolution(
	battle_province: Province,
	side_state: Dictionary,
	attacker_tag: String,
	defender_tag: String,
) -> Dictionary:
	var att_score: float = (
		_side_strength(side_state["attacker"])
		* float(side_state["attacker"]["org"])
		* float(side_state["attacker"]["readiness"])
	)
	var def_score: float = (
		_side_strength(side_state["defender"])
		* float(side_state["defender"]["org"])
		* float(side_state["defender"]["readiness"])
		* 1.06
	)

	# Deflector shields % absorb / pre-readiness dmg red in resolution (reuse nat_mod defensive_shielding)
	# Also apply secret_fleet if present in powers (passed via att_power etc but use tag)
	var att_tag_for_space := attacker_tag
	var def_tag_for_space := defender_tag
	if typeof(GameData) != TYPE_NIL:
		# secret edge
		var sec_a := 0.0
		if GameData.has_method("get_secret_fleet_combat_bonus"):
			sec_a = GameData.get_secret_fleet_combat_bonus(att_tag_for_space)
		if sec_a > 0.0:
			att_score *= (1.0 + sec_a)
			print("[SECRET FLEET] +%.0f%% applied in resolution for attacker %s" % [sec_a*100, att_tag_for_space])
		var sec_d := GameData.get_secret_fleet_combat_bonus(def_tag_for_space) if GameData.has_method("get_secret_fleet_combat_bonus") else 0.0
		if sec_d > 0.0:
			def_score *= (1.0 + sec_d)
			print("[SECRET FLEET] +%.0f%% applied in resolution for defender %s" % [sec_d*100, def_tag_for_space])
		# shields absorb for defender (space hab or ground shield)
		# In real, would come from power dict, here proxy if rule or from passed (simplest check via GameData? but use mod via leader no, assume nat in side)
		# For live, since pre power may have set shield_absorb on power but not side, recheck via NMM if avail
		if typeof(NationalModifierManager) != TYPE_NIL:
			var dsh := float(NationalModifierManager.get_combat_modifiers(def_tag_for_space).get("defensive_shielding", 0.0))
			if dsh > 0.0:
				def_score *= (1.0 + dsh * 0.25)  # absorb reduces effective incoming, boost def score
				print("[SPACE WIRING] deflector_shields %.0f%% absorb applied in _phase_resolution for %s" % [dsh*100, def_tag_for_space])
			# phaser/dew space flavor in text (no full var stun here, but dmg already in power)
			var ewd_d := float(NationalModifierManager.get_combat_modifiers(def_tag_for_space).get("energy_weapon_dmg", 0.0))
			if ewd_d > 0.0:
				print("[SPACE WIRING] phasers_torpedoes_2030 DEW flavor active for %s (variable setting stun/kill energy)" % def_tag_for_space)

		# === NEW: space strike / orbital guided munitions on ground troops (high prec +soft/hard for space_capable/advanced; area denial, morale hits) ===
		var att_ncm := {} if typeof(NationalModifierManager) == TYPE_NIL else NationalModifierManager.get_combat_modifiers(att_tag_for_space)
		var def_ncm := {} if typeof(NationalModifierManager) == TYPE_NIL else NationalModifierManager.get_combat_modifiers(def_tag_for_space)
		var att_strike := float(att_ncm.get("space_strike_bonus", 0.0)) + (GameData.get_space_strike_bonus(att_tag_for_space) if typeof(GameData) != TYPE_NIL and GameData.has_method("get_space_strike_bonus") else 0.0)
		var def_strike := float(def_ncm.get("space_strike_bonus", 0.0)) + (GameData.get_space_strike_bonus(def_tag_for_space) if typeof(GameData) != TYPE_NIL and GameData.has_method("get_space_strike_bonus") else 0.0)
		var att_guided := float(att_ncm.get("orbital_guided_munitions", 0.0))
		var def_guided := float(def_ncm.get("orbital_guided_munitions", 0.0))
		if att_strike > 0.0:
			att_score *= (1.0 + att_strike * 0.4)
			print("[ORBITAL STRIKE] Attacker %.0f%% space strike bonus devastating defender troops (guided precision + area)" % (att_strike*100))
		if def_strike > 0.0:
			def_score *= (1.0 + def_strike * 0.35)
			print("[ORBITAL STRIKE] Defender %.0f%% space strike active (counter orbital support)" % (def_strike*100))
		# Guided extra vs non-space, morale/area denial (sim via score/org side effects)
		if att_guided > 0.0:
			att_score *= (1.0 + att_guided * 0.25)
			# simulate defender morale/org hit from precision strikes
			if "org" in side_state.get("defender", {}):
				side_state["defender"]["org"] *= max(0.7, 1.0 - att_guided * 0.15)
			print("[GUIDED MUNITIONS] Attacker orbital guided +%.0f%% hard impact; defender org/morale suppressed" % (att_guided*100))
		if def_guided > 0.0:
			def_score *= (1.0 + def_guided * 0.22)
			if "org" in side_state.get("attacker", {}):
				side_state["attacker"]["org"] *= max(0.75, 1.0 - def_guided * 0.12)

	var winner := "attacker" if att_score >= def_score else "defender"
	var margin := absf(att_score - def_score) / maxf(def_score, 0.01)
	var outcome := "minor_victory" if margin < 0.12 else "major_victory"
	if winner == "defender" and margin >= 0.2:
		outcome = "heroic_defense"
	elif winner == "defender":
		outcome = "delay_success"
	var captured := winner == "attacker" and attacker_tag != defender_tag and not attacker_tag.is_empty()
	return {
		"winner": winner,
		"outcome": outcome,
		"attacker_score": att_score,
		"defender_score": def_score,
		"province_control_change": captured,
		"attacker_tag": attacker_tag,
		"defender_tag": defender_tag,
		"province_id": battle_province.id,
	}


func _side_strength(side: Dictionary) -> float:
	return float(side.get("soft", 0.0)) + float(side.get("hard", 0.0)) * 1.6


func _detect_unit_type(division_template_id: String) -> String:
	var t := division_template_id.to_lower()
	if "marine" in t or "amphib" in t:
		return "marine"
	if "paratroop" in t or "airborne" in t:
		return "paratroop"
	if "sf_" in t or "special_forces" in t or ("special" in t and "force" in t):
		return "sf"
	if "mountain" in t:
		return "mountain"
	if "ski" in t or ("winter" in t and "troop" in t):
		return "ski"
	if "space" in t or "orbital" in t or "recon_asset" in t:
		return "space"
	return "standard"
