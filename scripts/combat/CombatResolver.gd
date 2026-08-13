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
	# Prefer explicit unit_id; BattleManager often passes formation_id as division_template_id.
	var resolve_unit := unit_id if not unit_id.is_empty() else army_id
	if resolve_unit.is_empty():
		resolve_unit = division_template_id
	var base_stats := ProductionManager.get_division_final_combat_stats(division_template_id, resolve_unit)
	if base_stats.is_empty() and typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("get_formation_equipment_combat_stats"):
		base_stats = ProductionManager.get_formation_equipment_combat_stats(resolve_unit)

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

	# Rule flag wiring for new weapon techs (sonic/CB/bio from land_equipment; phaser from strategic_future)
	# Balance: high dmg but tradeoffs (indiscriminate for sonic, uncontrollable/ethics for CB, power/heat for energy; prior engines reuse mod/flag checks like radio)
	# Enhanced chem/bio by tech level (early low area, mid terror, advanced persistent high impact + morale), support equipment/gear (sustainment/support in templates) reduces effect (masks, suits, protective gear represented by support equipment).
	var owner_tag := ""
	if leader != null:
		owner_tag = leader.country_tag
	if not owner_tag.is_empty() and typeof(TechnologyManager) != TYPE_NIL:
		var att_mod := 0.0
		var own_risk := 0.0
		if TechnologyManager.has_rule_flag(owner_tag, "sonic_weapons"):
			att_mod += 0.12  # area soft control bonus
			own_risk += 0.05  # indiscriminate hearing/own troop affect
		# Chem/bio by tech level (high-leverage for prolonged attrit like Verdun/Marne historical)
		var chem_level := 0
		var chem_mod := 0.0
		var chem_risk := 0.0
		if TechnologyManager.has_rule_flag(owner_tag, "chemical_weapons_early") or TechnologyManager.has_rule_flag(owner_tag, "gas_weapons_1915"):
			chem_level = 1
			chem_mod = 0.15
			chem_risk = 0.08
		if TechnologyManager.has_rule_flag(owner_tag, "cb_weapons"):
			chem_level = 2
			chem_mod = 0.22
			chem_risk = 0.12
		if TechnologyManager.has_rule_flag(owner_tag, "advanced_cb_weapons") or TechnologyManager.has_rule_flag(owner_tag, "chemical_biological_weapons_1960"):
			chem_level = 3
			chem_mod = 0.30
			chem_risk = 0.18
		if chem_mod > 0.0:
			att_mod += chem_mod
			own_risk += chem_risk
			# Area denial terror on defender soft/org too if using (prolonged effect)
			if base_stats.has("soft_attack"):
				base_stats["soft_attack"] = float(base_stats["soft_attack"]) * (1.0 + chem_mod * 0.5)
		if TechnologyManager.has_rule_flag(owner_tag, "phaser_torpedo"):
			att_mod += 0.18  # scalable energy precise
			own_risk += 0.08  # power hog, overkill ethics
		if att_mod > 0.0:
			if base_stats.has("soft_attack"):
				base_stats["soft_attack"] = float(base_stats["soft_attack"]) * (1.0 + att_mod)
			if base_stats.has("hard_attack"):
				base_stats["hard_attack"] = float(base_stats["hard_attack"]) * (1.0 + att_mod * 0.7)
		if own_risk > 0.0 and base_stats.has("readiness"):
			base_stats["readiness"] = float(base_stats["readiness"]) * (1.0 - own_risk * 0.5)  # self risk trade-off
		# Support equipment / gear reduction for chem (represented in sustainment/support equipment in div templates or formation)
		if chem_level > 0 and (base_stats.has("support_equipment") or (division_template_id and ("support" in division_template_id.to_lower() or "sustainment" in division_template_id.to_lower()))):
			var gear_reduction := 0.4  # 40% reduction if gear present (masks, suits, protective equip)
			own_risk *= (1.0 - gear_reduction)
			# Less penalty to readiness
			if own_risk > 0.0 and base_stats.has("readiness"):
				base_stats["readiness"] = float(base_stats["readiness"]) * (1.0 + own_risk * 0.3)
			print("[CHEM WARFARE] Tech level %d impact (mod %.2f risk %.2f) - support gear reduced effect" % [chem_level, chem_mod, chem_risk])
		# Also feed to ethics risk system indirectly via higher terror if used (caller can check)
		if (TechnologyManager.has_rule_flag(owner_tag, "cb_weapons") or TechnologyManager.has_rule_flag(owner_tag, "sonic_weapons")) and typeof(GameData) != TYPE_NIL and GameData.has_method("apply_agent_pillar_influence"):
			# Light ongoing ethics pressure when fielded (balance for bio/sonic backlash)
			GameData.call("apply_agent_pillar_influence", owner_tag, "cohesion", -1, "cb_sonic_field_use")

	var combat_stats := base_stats
	if not leader_id.is_empty():
		combat_stats = apply_training_path_modifiers(leader_id, base_stats)

	var final_soft := float(combat_stats.get("soft_attack", 0.0))
	var final_hard := float(combat_stats.get("hard_attack", 0.0))
	var final_readiness := float(combat_stats.get("readiness", 1.0))
	var final_org := float(combat_stats.get("organization", 1.0))
	# Trained formation bonus (from full daily train advance + leader): better baseline for combat (roadmap).
	if bool(combat_stats.get("is_trained", false)):
		final_readiness = min(1.95, final_readiness * 1.12)
		final_org = min(1.95, final_org * 1.08)

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
	# Declared early: used by marine/coastal blocks before province lookup below (Godot 4.7 strict order).
	var province_for_effects: Province = null
	var has_guided := false
	var air_power_ratio: float = 1.0
	var cas_mult: float = 1.0
	var def_power: Variant = null

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
			var pt := str(province_for_effects.terrain).to_lower()
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
		var space_bonus: float = 0.15
		final_soft += space_bonus * 5.0
		final_hard += space_bonus * 3.0
		final_org *= 0.92

	# Province infrastructure & development effects (Deeper Combat integration - Phase 1 item 2)
	# Prefer passed dev/infra, then lookup by province_id via ScenarioLoader, else light proxy.
	var prov_dev := province_dev
	var prov_infra := province_infra
	# province_for_effects declared earlier for marine/coastal unit blocks
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

	# Lookup formation (via army_id which callers often pass as formation_id, or template) for mission mods (ASSAULT etc intensity, attach, radio/counter-battery/proximity, land/air).
	var formation_for_effects: Variant = null
	if not army_id.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		formation_for_effects = LeaderManager.get_formation(army_id)
	if formation_for_effects == null and not division_template_id.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		formation_for_effects = LeaderManager.get_formation(division_template_id)

	var pid_for_weather := province_id if province_id >= 0 else (province_for_effects.id if province_for_effects else -1)

	# World-class full weather/terrain/air integration (expanded stubs): snow/mud/rain/precip/visibility/storm real penalties + CAS/interdict + full tie.
	# Uses clean WeatherManager queries (get_province_snow + get_movement_multiplier for mud/snow/ground + get_air...); complements ProvinceEffects.
	# Full weather tie: affects resolve_combat scores/phases + get_effective (used in preview/estimate too).
	# Air CAS/interdiction: stronger bonus from air_mission, intensity, air effectiveness; interdiction drags defender.
	if province_id >= 0 or province_for_effects != null:
		var wm = null
		if typeof(WeatherManager) != TYPE_NIL:
			if Engine.has_singleton("WeatherManager"):
				wm = Engine.get_singleton("WeatherManager")
			if wm == null:
				var tree := Engine.get_main_loop() as SceneTree
				if tree and tree.root:
					wm = tree.root.get_node_or_null("/root/WeatherManager")
			if wm == null and typeof(ProvinceEffects) != TYPE_NIL:
				# reuse safe getter pattern if available
				wm = ProvinceEffects._get_weather_manager()
		if pid_for_weather >= 0 and wm != null:
			# Snow full
			if wm.has_method("get_province_snow"):
				var snow_cov := float(wm.call("get_province_snow", pid_for_weather))
				if snow_cov > 0.2:
					final_soft *= clampf(1.0 - (snow_cov * 0.18), 0.65, 1.0)  # stronger real
					final_hard *= clampf(1.0 - (snow_cov * 0.14), 0.7, 1.0)
					final_readiness *= clampf(1.0 - (snow_cov * 0.1), 0.75, 1.0)
					if terrain == "snow_capped" or (province_for_effects and str(province_for_effects.terrain if "terrain" in province_for_effects else "") == "snow_capped"):
						final_readiness *= 1.06
						final_org *= 1.04
					var sp_source := ""
					if province_for_effects != null and "source" in province_for_effects:
						sp_source = str(province_for_effects.source)
					if terrain == "snow_capped" and sp_source == "real_layers_inference":
						final_readiness *= 1.03
			# Mud/rain/ground/visibility full real (from WM movement + direct state; rain->mud penalties on attacker mobility/readiness)
			if wm.has_method("get_movement_multiplier"):
				var move_mult := float(wm.call("get_movement_multiplier", pid_for_weather))
				if move_mult < 0.85:
					final_soft *= clampf(move_mult * 0.9 + 0.1, 0.6, 1.0)  # mud/rain/snow mobility hit to attack
					final_readiness *= clampf(move_mult * 0.85 + 0.15, 0.5, 1.0)
					final_org *= clampf(0.7 + move_mult * 0.3, 0.75, 1.0)
			# Safe full precip/vis/ground/mud from WM public summary parse only (no crashing wm.has or internal _ access on Node). Completes full weather from WM in resolver for mud/snow/precip penalties + air tie already present.
			var wstate: Dictionary = {}
			if wm.has_method("get_conditions_summary"):
				var summ: String = str(wm.call("get_conditions_summary", pid_for_weather))
				if "mud" in summ: wstate["ground_state"] = "mud"
				elif "snow" in summ: wstate["ground_state"] = "snow_covered"
				elif "frozen" in summ: wstate["ground_state"] = "frozen"
				if "vis " in summ and "%" in summ:
					var vs = summ.split("vis ", false)[1].split("%", false)[0].strip_edges()
					wstate["visibility"] = clampf(float(vs)/100.0, 0.0, 1.0)
				if "rain" in summ or "storm" in summ: wstate["precip_intensity"] = 0.55
			var precip := float(wstate.get("precip_intensity", 0.0))
			var vis := float(wstate.get("visibility", 1.0))
			var gstate := str(wstate.get("ground_state", ""))
			if precip > 0.4 or gstate in ["mud", "wet"]:
				final_soft *= 0.88
				final_readiness *= 0.82
				final_org *= 0.9
			if vis < 0.5:
				final_soft *= clampf(0.6 + vis * 0.5, 0.55, 0.95)
				final_readiness *= clampf(0.7 + vis * 0.35, 0.65, 0.98)
			if gstate in ["snow_covered", "frozen", "ice"]:
				final_hard *= 0.92  # slight

	# River natural border from real layers inference / demo sample apply (river-cross children): slight defender edge (river lines as prepared defensive features).
	# High value for map data driving combat (Rhine, etc. historical). Uses has_river_border from demo or geo flag.
	if pid_for_weather >= 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_river_border"):
		if MapManager.has_river_border(pid_for_weather):
			# Attacker crossing penalty, defender prepared (small but stacks with terrain/snow/fort/settlement).
			final_soft *= 0.96
			final_hard *= 0.95
			final_readiness *= 1.04
			terrain_bonus += 0.04
			# If demo children, note in preview that sub-terrain/river used conceptually.
			if MapManager.has_method("get_demo_subdiv_children"):
				var dkids = MapManager.get_demo_subdiv_children(pid_for_weather)
				if dkids.size() > 0:
					# log or carry for preview
					pass
	# Next-level naval chokepoints (Danish, Gibraltar etc from special sites): extra defender edge or crossing penalty for attacker (control of narrows).
	if pid_for_weather >= 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
		if MapManager.has_strategic_chokepoint(pid_for_weather):
			final_soft *= 0.94
			final_hard *= 0.93
			final_readiness *= 1.06
			terrain_bonus += 0.06

	# Air support / interdiction from attached air (CAS, interdiction intensity from formation air missions).
	# Boosts attacker soft/hard or reduces defender org/readiness if interdict.
	# Uses formation air_mission data if present (set by AirMission system); simple for now, scales with intensity.
	if formation_for_effects != null:
		var air_int := 0.0
		var air_type := ""
		if typeof(formation_for_effects) == TYPE_DICTIONARY:
			air_int = float(formation_for_effects.get("air_mission_intensity", 0.0))
			air_type = str(formation_for_effects.get("air_mission_type", "")).to_upper()
		elif formation_for_effects is Object:
			# Formation is a Resource — use `in` / property access, not Dictionary.has
			if "air_mission_intensity" in formation_for_effects:
				air_int = float(formation_for_effects.air_mission_intensity)
			if "air_mission_type" in formation_for_effects:
				air_type = str(formation_for_effects.air_mission_type).to_upper()
			elif "current_air_mission" in formation_for_effects:
				air_type = str(formation_for_effects.current_air_mission).to_upper()
		if air_type in ["CAS", "CLOSE_AIR_SUPPORT"]:
			final_soft *= (1.0 + clampf(air_int * 0.12, 0.0, 0.25))
			final_hard *= (1.0 + clampf(air_int * 0.08, 0.0, 0.18))
		elif air_type in ["INT", "INTERDICTION"]:
			final_readiness *= (1.0 - clampf(air_int * 0.10, 0.0, 0.20))
			final_org *= (1.0 - clampf(air_int * 0.07, 0.0, 0.15))

	if prov_dev < 0:
		prov_dev = 0
	if prov_infra < 0:
		prov_infra = 0

	# Naval resolver func moved to class level below get_effective (was incorrectly nested during prior edit, causing scope/return path errors).

	var national_combat := {}

	# === Light National Spirit / Temporary Modifier Integration (Combat) ===
	# One step further from the national_bonuses integration in LeaderManager.
	if leader != null and typeof(LeaderManager) != TYPE_NIL:
		national_combat = LeaderManager.get_national_combat_modifiers(leader.country_tag)

	# Secret fleet wiring: apply peace_state secret_fleet_combat_bonus (from secret_space_programs) for naval/space/special formations (small +% edge)
	if leader != null and typeof(GameData) != TYPE_NIL and GameData.has_method("get_secret_fleet_combat_bonus"):
		var sec_bonus: float = GameData.get_secret_fleet_combat_bonus(leader.country_tag)
		if sec_bonus > 0.0:
			national_combat["secret_fleet"] = sec_bonus
			print("[SECRET FLEET] +%.0f%% combat bonus applied for %s (naval/space or secret tag; vs conventional; exposure risk in events)" % [sec_bonus*100, leader.country_tag])

		# Apply organization bonus from national spirits/modifiers
		var org_bonus := float(national_combat.get("army_org_factor", 0.0))
		if org_bonus != 0.0:
			final_org += org_bonus * 5.0   # Scale to match other combat stat units

		# Apply attack bonus (if present)
		var attack_bonus := float(national_combat.get("attack_factor", 0.0))
		if attack_bonus != 0.0:
			final_soft += attack_bonus * 8.0
			final_hard += attack_bonus * 5.0

		# Apply defence bonus (maps to readiness/org in this context)
		var def_bonus := float(national_combat.get("defence_factor", 0.0))
		if def_bonus != 0.0:
			final_readiness += def_bonus * 3.0
			final_org += def_bonus * 2.0

	var training_path_bonus := float(combat_stats.get("training_path_soft_bonus", 0.0))

	# === Transplanted logic (was stray after nested naval): demo river subdiv terrain, ProvinceEffects org/attrition, loyalty/foreign, settlement, regional control, land/air missions+intensity+doctrines, winter regional. ===
	# Demo sample river subdiv: use child terrain for calc to sim "sub-battle" on the split children (carried inference like "coastal" for river kids)
	if province_id >= 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_effective_terrain_for_demo"):
		var demo_terr: String = ""
		var _dt := MapManager.get_effective_terrain_for_demo(province_id)
		if typeof(_dt) == TYPE_STRING:
			demo_terr = _dt
		if demo_terr != terrain and demo_terr != "plains":
			terrain = demo_terr
			# re-apply terrain bonus if changed
			terrain_bonus = 0.0
			if leader != null:
				terrain_bonus = leader.get_terrain_modifier(terrain)
			final_soft += terrain_bonus * 8.0
			final_hard += terrain_bonus * 5.0

	# Use Province getter or ProvinceEffects for accurate org/recovery/readiness in this province
	var org_mod: float = 1.0
	var attrition_mod: float = 1.0
	if owner_tag.is_empty() and typeof(LeaderManager) != TYPE_NIL and not army_id.is_empty():
		var lid: String = LeaderManager.get_leader_id_for_army(army_id)
		if lid != "" and LeaderManager.leaders.has(lid):
			owner_tag = LeaderManager.leaders[lid].country_tag
	var has_province_context: bool = province_id >= 0 or province_for_effects != null
	if has_province_context:
		if province_for_effects != null and typeof(ProvinceEffects) != TYPE_NIL:
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

	# Deeper combat integration: Loyalty/foreign military penalty on effective power (high foreign % or low loyalty reduces org/readiness in battle, models integration/morale issues for mixed forces).
	# Settlement from relocation now explicitly gives defender (or local) bonus here too (passed via context or direct Province).
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_military_loyalty_multiplier"):
		var loy: float = 1.0
		var _l: float = GameData.get_military_loyalty_multiplier(owner_tag if owner_tag else "player")
		if typeof(_l) in [TYPE_FLOAT, TYPE_INT]:
			loy = float(_l)
		var foreign_pct: float = 0.0
		var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
		if ps.has("foreign_military_pct"):
			foreign_pct = float( ps.get("foreign_military_pct", {}).get(owner_tag if owner_tag else "player", 0.0) )
		var loyalty_factor: float = clampf(loy * (1.0 - foreign_pct * 0.3), 0.5, 1.2)  # Penalty scales with foreign reliance
		org_mod *= loyalty_factor
		final_readiness *= loyalty_factor
		final_org *= loyalty_factor

	# Settlement bonus in resolver – refined (matches BattleManager: 2.5% base per level, conditional on cohesion/culture for flavorful "our people defend home" payoff).
	# World-class: Like HOI4 forts/terrain giving defender edge without breaking attacker agency; Vic3 gradual % from developed states. Fun: Settlement from relocation policies feels powerful in defense but situational (high cohesion amplifies, low or foreign dilutes).
	if province_for_effects and province_for_effects.settlement_level > 0.05:
		var base_s: float = province_for_effects.settlement_level * 0.025
		var coh_bonus: float = 1.0
		if typeof(GameData) != TYPE_NIL:
			var coh: int = 50
			var _c: int = GameData.get_pillar(owner_tag if owner_tag else "player", "cohesion")
			if typeof(_c) in [TYPE_INT, TYPE_FLOAT]:
				coh = int(_c)
			coh_bonus = 1.0 + max(0, (coh - 50) * 0.002)
		var s_bonus: float = clampf(1.0 + (base_s * coh_bonus), 1.0, 1.25)
		org_mod *= s_bonus
		final_readiness *= s_bonus
		final_org *= lerp(1.0, s_bonus, 0.7)  # partial on final org

	# Regional control defense bonus (next logical wiring after scenario connections + full control demo + snow in power): if the battle province's region is fully controlled by its owner (home pride + prepared defenses from table e.g. "mountain_defense" for Alps/Italy), boost the side that matches the controller (typically defender in home full region gets readiness/org edge).
	if province_for_effects != null and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
		var prov_owner: String = province_for_effects.owner_tag if province_for_effects else ""
		var reg_b: Dictionary = MapManager.get_active_regional_control_bonuses(prov_owner)
		var def_b: float = float(reg_b.get("defense_factor", reg_b.get("mountain_defense", 0.0)))
		var ctrl: String = province_for_effects.controller_tag if province_for_effects else ""
		var side_tag: String = owner_tag if owner_tag else (province_for_effects.owner_tag if province_for_effects else "")
		if def_b > 0.0:
			if side_tag == prov_owner or side_tag == ctrl:
				final_readiness *= (1.0 + def_b)
				final_org *= (1.0 + def_b * 0.5)
		# Strategic depth penalty for attacker invading full controlled deep region (e.g. Western Russia; higher losses for invader)
		var depth: float = float(reg_b.get("strategic_depth", 0.0))
		if depth > 0.0 and side_tag != prov_owner and side_tag != ctrl:
			final_readiness *= (1.0 - depth * 0.1)
			final_org *= (1.0 - depth * 0.05)

	# Land unit missions (overarching orders like ASSAULT, DEFEND, ARTILLERY_PREP, PATROL) + intensity/aggressiveness.
	# Doctrines/tech: radio for higher org in move/attack/defend; counter-battery/precalc defensive fire planning for defenders (quick artillery assign).
	# Proximity shells example for AA (if air involved).
	if formation_for_effects != null and formation_for_effects.has_method("get_mission_mods"):
		var land_mods: Dictionary = formation_for_effects.get_mission_mods()
		final_soft *= (1.0 + float(land_mods.get("combat_bonus", 0.0)))
		final_readiness *= (1.0 + float(land_mods.get("org_mod", 0.0)) * 0.5)
		# Counter-battery: if DEFEND or ARTILLERY_PREP and doctrine/tech, bonus.
		if formation_for_effects.current_land_mission in [Formation.LAND_MISSION_DEFEND, Formation.LAND_MISSION_ARTILLERY_PREP]:
			final_readiness *= 1.05  # preplanned fire planning.
	# Air fully integrated (expanded stub): CAS/interdiction + intensity + effectiveness + AA.
	# Uses AirMissionProfile/formation air_mission + WM air effectiveness + mission_intensity for CAS bonus to attacker/soft, interdiction drag on defender org/readiness (models supply interdiction in battle).
	if formation_for_effects != null:
		var air_bonus := 0.0
		var interdict_drag := 0.0
		if formation_for_effects.has_method("get_mission_mods"):
			var air_mods: Dictionary = formation_for_effects.get_mission_mods()
			air_bonus = float(air_mods.get("combat_bonus", 0.0))
			# AA vs enemy air (defenders damage aircraft, reduce air effect, attrition to enemy air presence)
			var aa_vs := float(air_mods.get("aa_vs_air", 0.0))
			if aa_vs > 0.0 or (def_power and float(def_power.get("aa_factor", 0.0)) > 0.0):
				aa_vs = max(aa_vs, float(def_power.get("aa_factor", 0.15)) if def_power else 0.15)
				# Reduce enemy air effectiveness / cas if defender AA
				if air_power_ratio < 1.0:  # enemy air
					air_power_ratio *= max(0.5, 1.0 - aa_vs * 0.3)
				final_readiness *= (1.0 + aa_vs * 0.15)
				# Simulate defender AA damaging aircraft (reduce future air or log attrition)
				if air_power_ratio < 0.9:
					cas_mult *= 0.88  # AA disrupts CAS
				print("[AA] Defender AA (%.2f) damaged/reduced enemy air effect, ratio now %.2f" % [aa_vs, air_power_ratio])
		var am := ""
		if formation_for_effects.has_method("get_air_mission"):
			am = str(formation_for_effects.call("get_air_mission"))
		elif "current_air_mission" in formation_for_effects:
			am = str(formation_for_effects.current_air_mission)
		if am in ["CLOSE_AIR_SUPPORT", "CAS", "SUPPORT"]:
			air_bonus += 0.25
		elif am in ["INTERDICTION"]:
			interdict_drag += 0.18
		var intens := 1.0
		if "mission_intensity" in formation_for_effects:
			intens = float(formation_for_effects.mission_intensity)
		elif formation_for_effects.has_method("get_mission_intensity"):
			intens = float(formation_for_effects.call("get_mission_intensity"))
		air_bonus *= clampf(intens, 0.8, 1.8)
		# Weather air effectiveness tie (full)
		var air_eff := 1.0
		if pid_for_weather >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_air_mission_effectiveness"):
			air_eff = float(WeatherManager.call("get_air_mission_effectiveness", pid_for_weather))
		air_bonus *= air_eff
		if air_bonus > 0.01:
			final_soft *= (1.0 + air_bonus * 0.9)  # strong CAS to soft/hard for land battle
			final_hard *= (1.0 + air_bonus * 0.6)
		if interdict_drag > 0.01:
			final_readiness *= (1.0 - interdict_drag * 0.6)  # defender supply/org hit from interdiction
			final_org *= (1.0 - interdict_drag * 0.4)

	# ECM/jamming and electronic countermeasures (field jamming impact on combat/defense, per Ukraine/contemporary).
	# Reduces guided/air/space effectiveness unless countered.
	var ecm_drag := 0.0
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(owner_for_tech, "ecm_jamming"):
		ecm_drag = 0.15
	if def_power and float(def_power.get("ecm_factor", 0.0)) > 0.0:
		ecm_drag = max(ecm_drag, float(def_power.get("ecm_factor", 0.1)))
	if ecm_drag > 0.01:
		final_soft *= (1.0 - ecm_drag * 0.4)
		if has_guided:
			final_soft *= (1.0 - ecm_drag * 0.3)  # jamming hurts guided more
		final_org *= (1.0 - ecm_drag * 0.1)
		print("[ECM/JAMMING] Reduced soft/guided/org by jamming factor")

	# Anti-drone tech (like anti-air for drones; contemporary, reduces air/drone effect).
	var anti_drone := 0.0
	if unit_type == "anti_drone" or (def_power and "drone" in str(def_power.get("special", ""))):
		anti_drone = 0.2
	if anti_drone > 0:
		if air_power_ratio > 0.5:  # if enemy air/drone
			air_power_ratio *= (1.0 - anti_drone)
		print("[ANTI_DRONE] Reduced enemy air/drone effect")

	# Anti-tank for infantry (tools help infantry hold vs armor, like Javelin in Ukraine; infantry vs hard attack bonus).
	if unit_type == "infantry" or "inf" in division_template_id.to_lower():
		var at_bonus := 0.0
		if "at_support" in str(division_template_id).to_lower() or (formation_for_effects and "anti_tank" in str(formation_for_effects)):
			at_bonus = 0.15
		if at_bonus > 0 and float(base_stats.get("hard_attack", 0)) > float(final_soft) * 0.5:  # vs armor heavy
			final_soft *= (1.0 + at_bonus)
			print("[ANTI_TANK] Infantry AT bonus vs armor")

	# Wire-guided munitions: overcome jamming (ignore ecm_drag), but higher production costs (modeled as supply/ readiness cost or note for prod).
	if has_guided and typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(owner_for_tech, "wire_guided_munitions"):
		ecm_drag = 0.0  # counters jamming
		final_soft *= 1.1  # slightly better vs jammed
		final_org *= 0.95  # higher cost -> slight org/readiness penalty (slower sustain)
		print("[WIRE_GUIDED] Overcomes jamming but higher cost (readiness penalty)")

	# Radio/tech for org in high intensity missions (move/attack/defend).
	if formation_for_effects != null:
		var mi := 1.0
		if "mission_intensity" in formation_for_effects:
			mi = float(formation_for_effects.mission_intensity)
		if mi > 1.2:
			final_org *= 1.06  # radio coordination.

	# Winter warfare regional bonus (next logical: mitigates snow penalties in full controlled regions with "winter_warfare" e.g. Western Russia; ties snow + regional control for realistic winter combat on map)
	if province_for_effects != null and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
		var prov_owner2: String = province_for_effects.owner_tag
		var reg_b2: Dictionary = MapManager.get_active_regional_control_bonuses(prov_owner2)
		var ww: float = float(reg_b2.get("winter_warfare", 0.0))
		var snow_cov2: float = 0.0
		if typeof(WeatherManager) != TYPE_NIL:
			var wm2 = null
			if Engine.has_singleton("WeatherManager"): wm2 = Engine.get_singleton("WeatherManager")
			if wm2 == null:
				var tree2 := Engine.get_main_loop() as SceneTree
				if tree2 and tree2.root: wm2 = tree2.root.get_node_or_null("/root/WeatherManager")
			if wm2 and wm2.has_method("get_province_snow"):
				snow_cov2 = float(wm2.get_province_snow(province_id if province_id >= 0 else province_for_effects.id))
		if ww > 0.0 and snow_cov2 > 0.2:
			# Reduce snow penalties or boost for defender in winter-hardy full region
			final_soft *= (1.0 + ww * 0.1)
			final_readiness *= (1.0 + ww * 0.15)
			final_org *= (1.0 + ww * 0.08)

	# Note: For full battle resolution paths (resolve_battle_aftermath etc.), pass province_id/dev
	# so casualty rolls and post-battle org can also respect province stats via similar getters.

	# Apply persistent formation strength (casualties from prior battles reduce effective combat power).
	# Strength <1.0 from unreplaced losses makes units less effective until reinforced from stock (Supply daily).
	var formation_strength := 1.0
	var formation_xp := 48.0
	var experience_mult := 1.0
	if not army_id.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		var form := LeaderManager.get_formation(army_id)
		if form != null and "strength" in form:
			formation_strength = clampf(float(form.strength), 0.4, 1.0)
			if formation_strength < 0.95:
				# Exhausted/depleted units suffer extra org/readiness friction
				final_org *= lerp(1.0, formation_strength, 0.4)
				final_readiness *= lerp(1.0, formation_strength, 0.6)
		if form != null and "combat_experience" in form:
			formation_xp = clampf(float(form.combat_experience), 0.0, 100.0)
	# RF1: greens are not veterans — experience band multiplies combat power.
	var reinf_calc = load("res://scripts/production/ReinforcementLogisticsCalculator.gd")
	if reinf_calc != null and reinf_calc.has_method("experience_combat_mult"):
		experience_mult = float(reinf_calc.experience_combat_mult(formation_xp))
	else:
		experience_mult = clampf(0.78 + formation_xp * 0.0042, 0.78, 1.2)
	# CP5: production/design reliability soft mult (breakdown / loss amplification path).
	var reliability := clampf(float(base_stats.get("reliability", 0.9)), 0.4, 1.0)
	var prod_rel := clampf(float(base_stats.get("production_reliability", 1.0)), 0.5, 1.0)
	var reliability_mult := clampf(0.72 + reliability * 0.28, 0.72, 1.0) * clampf(0.9 + prod_rel * 0.1, 0.9, 1.0)
	final_soft *= formation_strength * experience_mult * reliability_mult
	final_hard *= formation_strength * experience_mult * reliability_mult
	if experience_mult < 0.95:
		final_org *= lerpf(1.0, experience_mult, 0.35)
		final_readiness *= lerpf(1.0, experience_mult, 0.25)
	if reliability_mult < 0.95:
		final_org *= lerpf(1.0, reliability_mult, 0.4)
		final_readiness *= lerpf(1.0, reliability_mult, 0.35)

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
		"formation_strength": formation_strength,
		"formation_combat_experience": formation_xp,
		"experience_combat_mult": experience_mult,
		"reliability": reliability,
		"production_reliability": prod_rel,
		"reliability_combat_mult": reliability_mult,
	}


## Full phased naval engagement resolver (WWI 1916 Jutland gunline/haze -> 1942 Midway carrier/intel -> 1982 Falklands Exocet/ASW -> 2026 CSG sat/jam/missile).
## Inspired by history (spotting failures, ECM/jam reduce guided, weather/night favor stealth/ambush/subs, screening, fuel/endurance limits not total annihilation, disengage common, leader doctrine matter) + HoI4 patterns (spot task vs strike, org, repair separate, not doomstack binary).
## Phases: search (dynamic recon/spot from assets + weather/jam/tech), detect, (ASW subphase), engage (screen/guided/air/gun), disengage (leader init/org/damage/intel based).
## Era/tech gating: pre-1938 visual/poor radar -> radar/sonar boost -> ECM/missile counter -> sat recon/unlimited nuke endurance.
## Spotting: air (NAVAL_STRIKE/RECON attached), surface detection_contrib + order, sub stealth, chokepoint, later sat. Jamming from context/ECM modules reduces enemy spot + guided eff.
## Fuel/endurance: caller/Supply passes low_fuel_mult; affects power. Low org + damage -> higher disengage.
## Not annihilation: disengage rolls allow withdraw with reduced further cas. Screening (escort order) protects vs torp/sub/air.
## Leader: naval_combat + carrier_admiral (strike), sea_wolf (sub/ambush), initiative (disengage/ambush). National chief bonus via context.
## Returns rich AAR: phases, spotting values, key_factors, retreat_chances, est cas, engagement_type for logs/ProvinceInsight/TestRunner summary.
## Callers (BM) enrich context with orders, weather, sub_heavy, choke, leader_bonuses, jamming, fuel_state, tech_year, formations proxy.
func resolve_naval_engagement(context: Dictionary, atk_power: float, def_power: float) -> Dictionary:
	var res := {"ok": true, "type": "naval", "phases": [], "spotting": {}, "asw": {}, "engagement": {}, "disengage": {}, "key_factors": [], "winner": "", "naval_casualties_est": 0.0, "attacker_casualties": 0.0, "defender_casualties": 0.0, "context": context}
	var vis : float = float(context.get("weather_vis", 1.0))
	var choke : bool = bool(context.get("chokepoint", false))
	var subh : bool = bool(context.get("sub_heavy", false))
	var range_mod : float = float(context.get("range_mod", 1.0))
	var closer : bool = bool(context.get("closer_engagement", false))
	var a_order : String = str(context.get("attacker_order", "")).to_upper()
	var d_order : String = str(context.get("defender_order", "")).to_upper()
	var atk_tag : String = str(context.get("attacker", "ATK"))
	var def_tag : String = str(context.get("defender", "DEF"))
	var sea_pid : int = int(context.get("sea_pid", -1))

	# Era / tech gating (from Time or context; defaults allow full sim across 1918-2026)
	var year := 1942
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
		year = int(TimeManager.get_current_year())
	elif context.has("year"):
		year = int(context["year"])
	var has_radar : bool = year >= 1938
	var has_sonar : bool = year >= 1938
	var has_ecm : bool = year >= 1965 or "ecm" in str(context.get("jamming_tech", "")).to_lower()
	var has_sat : bool = year >= 1975 or "sat" in str(context.get("recon_tech", "")).to_lower()
	var has_jet_carrier : bool = year >= 1955
	var has_missile : bool = year >= 1960
	var has_nuke_prop : bool = year >= 1958  # unlimited endurance proxy for subs/carriers

	res["phases"].append("search")

	# === DYNAMIC SPOTTING PHASE (realistic recon stack: air/surface/sub/sat + mods; history Jutland haze missed, Midway JP recon fail + weather; modern sat/P8) ===
	# Base from formations (get_naval_detection_contrib + visibility inverse for enemy stealth) + orders
	var base_spot_atk : float = float(context.get("atk_detection", 1.0))
	var base_spot_def : float = float(context.get("def_detection", 1.0))
	# Enhance with order (Formation methods already good)
	if a_order in ["SEARCH_PATROL", "SEARCH_AND_DESTROY", "STRIKE"]:
		base_spot_atk *= 1.35
	if d_order in ["SEARCH_PATROL", "SEARCH_AND_DESTROY", "STRIKE"]:
		base_spot_def *= 1.35
	if a_order == "AMBUSH":
		base_spot_atk *= 0.75  # stealthy search
	if d_order == "ASW":
		base_spot_def *= 1.2
	# Air recon contrib (NAVAL_STRIKE/RECON attached or presence; carrier heavy early)
	var air_recon_atk := float(context.get("air_recon_atk", 0.0)) + (0.8 if "carrier" in str(context.get("atk_assets","")).to_lower() else 0.0)
	var air_recon_def := float(context.get("air_recon_def", 0.0))
	if has_jet_carrier:
		air_recon_atk *= 1.3
		air_recon_def *= 1.3
	base_spot_atk += air_recon_atk * 0.6
	base_spot_def += air_recon_def * 0.6
	# Sub contrib (stealthy detect but low profile)
	if subh:
		base_spot_def += 0.4  # subs help own side spot? or for ambusher
	# Sat / advanced recon (post 1975 or tech)
	if has_sat:
		base_spot_atk += 0.7
		base_spot_def += 0.7
	# Weather + choke (choke = straits hard to hide; low vis = sub favor per history)
	var weather_spot_mult : float = clamp(vis * (1.0 if has_radar else 0.7), 0.15, 1.15)
	if choke:
		weather_spot_mult *= 1.4  # harder hide
	if vis < 0.5 and not has_radar:
		weather_spot_mult *= 0.6  # visual era haze/smoke penalty (Jutland)
	base_spot_atk *= weather_spot_mult
	base_spot_def *= weather_spot_mult
	# Jamming / ECM: reduces enemy spotting + guided later (EA-6B, Growler, modern; post WWII)
	var jam_atk : float = float(context.get("jam_atk", 0.0))  # jamming applied by defender vs attacker spot
	var jam_def : float = float(context.get("jam_def", 0.0))
	if has_ecm:
		jam_atk = max(jam_atk, float(context.get("ecm_level", 0.3)))
		jam_def = max(jam_def, float(context.get("ecm_level", 0.3)))
	base_spot_atk *= clamp(1.0 - jam_def * 0.65, 0.3, 1.0)
	base_spot_def *= clamp(1.0 - jam_atk * 0.65, 0.3, 1.0)
	# Sub stealth bonus in conditions (AMBUSH order + low vis + no sonar early)
	var sub_stealth_mult : float = 1.0
	if subh and (vis < 0.55 or a_order == "AMBUSH" or d_order == "AMBUSH"):
		sub_stealth_mult = 0.55 if has_sonar else 0.35
		base_spot_atk *= sub_stealth_mult if subh else 1.0  # harder for non-sub side to spot subs
	# Final spot values
	var spot_atk : float = clamp(base_spot_atk, 0.1, 3.5)
	var spot_def : float = clamp(base_spot_def, 0.1, 3.5)
	res["spotting"] = {
		"attacker_spot": spot_atk, "defender_spot": spot_def,
		"vis": vis, "choke": choke, "weather_mult": weather_spot_mult,
		"jam_applied": [jam_atk, jam_def], "has_radar": has_radar, "has_sat": has_sat, "sub_stealth": sub_stealth_mult
	}
	# Detect if either spots well or sub ambush forces
	var detect_threshold : float = 0.65
	var detected : bool = (spot_atk > detect_threshold or spot_def > detect_threshold) or (subh and (a_order == "AMBUSH" or d_order == "AMBUSH" or vis < 0.5))
	if not detected:
		res["winner"] = "none"
		res["outcome"] = "no_contact_spotting_failed"
		res["key_factors"].append("missed_searches_weather_or_recon_fail")
		res["naval_casualties_est"] = 0.0
		print("  [NAVAL RESOLVER] search phase: no detection (spot_atk=%.2f def=%.2f vis=%.2f jam=%.2f subh=%s year=%d) -> no engagement" % [spot_atk, spot_def, vis, jam_atk, subh, year])
		return res
	res["phases"].append("detect")

	# === ASW / SUB PHASE (if subs; sonar/depth/helos vs stealth; history Falklands RN ASW effort vs San Luis, Midway sub pickets missed) ===
	var asw_mod : float = 1.0
	if subh:
		res["phases"].append("asw")
		if (d_order == "ASW" or a_order == "ASW") and has_sonar:
			asw_mod = 1.25
			res["asw"] = {"sonar_active": true, "mod": asw_mod}
		# Sub advantage in stealth conditions already applied to spot; now combat power
		if vis < 0.5 or closer or choke:
			if a_order in ["AMBUSH", "SEARCH_AND_DESTROY"] or subh:
				def_power *= 1.2  # sub side power if ambushing (or swap logic)
		# ASW counters sub power
		if d_order == "ASW":
			def_power *= asw_mod
			atk_power *= 0.9 if subh else 1.0  # assume atk sub heavy for simplicity in call
		res["asw"]["final_mod"] = asw_mod

	# === ENGAGE PHASE (screening, guided/ECM, air strike, gunnery range, order/leader, carrier) ===
	res["phases"].append("engage")
	# Order mods (full use of Formation logic + extras)
	if a_order == "AMBUSH" and (range_mod < 0.6 or closer or vis < 0.5):
		def_power *= 0.82  # surprise
	if a_order == "STRIKE" and (range_mod > 0.9 or has_jet_carrier):
		atk_power *= 1.22 if has_radar else 1.12
	if d_order == "ASW" and subh:
		def_power *= 1.18
	if choke:
		atk_power *= 0.88  # narrow favors defender or brawl
		def_power *= 1.1
	# Screening: escort/CONVOY orders protect capitals from sub/torp/air strikes (DDs/CLs screen)
	if d_order in ["ESCORT", "CONVOY_DUTY"]:
		def_power *= 1.12  # reduced effective loss to strike
	# Guided weapons (missiles/torps wire/guided) vulnerable to ECM/jam; post missile era
	if has_missile:
		var guided_mult := 1.15
		if has_ecm or jam_atk > 0.1:
			guided_mult *= clamp(1.0 - jam_atk * 0.55, 0.5, 1.1)
		atk_power *= guided_mult if "missile" in str(context.get("atk_assets","")).to_lower() or year > 1955 else 1.0
	# Air / carrier strike (Midway decisive; Leyte air kills BBs without air cover)
	var carrier_bonus := 0.0
	if a_order == "STRIKE" or "carrier" in str(context.get("atk_assets","")).to_lower():
		carrier_bonus = 0.35 if has_jet_carrier else 0.22
		if has_ecm:
			carrier_bonus *= 0.85  # CAP/jam defense
	atk_power += carrier_bonus * def_power * 0.4  # relative

	# Leader / doctrine (sea_wolf, carrier_admiral, initiative from traits + chief navy)
	var leader_atk := float(context.get("leader_atk_bonus", 0.0))
	var leader_def := float(context.get("leader_def_bonus", 0.0))
	# Extra specific: carrier_admiral boosts strike, sea_wolf sub/ambush
	if "carrier_admiral" in str(context.get("atk_traits", "")) and a_order == "STRIKE":
		leader_atk += 0.15
	if "sea_wolf" in str(context.get("atk_traits", "")) and (subh or a_order == "AMBUSH"):
		leader_atk += 0.18
	if "carrier_admiral" in str(context.get("def_traits", "")) and d_order == "STRIKE":
		leader_def += 0.15
	if "sea_wolf" in str(context.get("def_traits", "")) and (subh or d_order == "AMBUSH"):
		leader_def += 0.18
	atk_power += leader_atk
	def_power += leader_def

	# Fuel/endurance state (from Supply; low = reduced power/speed, vuln; nuke late unlimited)
	var fuel_mult_atk : float = clamp(float(context.get("fuel_atk", 1.0)), 0.4, 1.1)
	var fuel_mult_def : float = clamp(float(context.get("fuel_def", 1.0)), 0.4, 1.1)
	if has_nuke_prop:
		fuel_mult_atk = 1.0
		fuel_mult_def = 1.0
	atk_power *= fuel_mult_atk
	def_power *= fuel_mult_def

	# Final power roll (margin for outcome)
	var total : float = atk_power + def_power + 0.01
	var atk_win_chance : float = atk_power / total
	var atk_wins : bool = randf() < atk_win_chance
	var winner_tag : String = atk_tag if atk_wins else def_tag
	res["winner"] = winner_tag
	res["attacker_wins"] = atk_wins
	var margin : float = absf(atk_power - def_power) / maxf(total, 1.0)
	res["engagement"] = {
		"atk_power_final": atk_power, "def_power_final": def_power,
		"margin": margin, "range_mod": range_mod, "fuel_mults": [fuel_mult_atk, fuel_mult_def],
		"leader_bonuses": [leader_atk, leader_def], "carrier_bonus": carrier_bonus,
		"screening": d_order in ["ESCORT", "CONVOY_DUTY"]
	}

	# Casualties (abstract est % + detailed; not total kill; damage to org/readiness/strength fed back by caller)
	var base_cas : float = 0.08 + margin * 0.22 + (0.05 if closer or choke else 0.0)
	res["naval_casualties_est"] = clamp(base_cas, 0.05, 0.45)
	res["attacker_casualties"] = res["naval_casualties_est"] * (0.7 if atk_wins else 1.3)
	res["defender_casualties"] = res["naval_casualties_est"] * (1.3 if atk_wins else 0.7)

	# === DISENGAGE / WITHDRAW PHASE (history: Jutland Germans smoke/turn away, not fight to last; Midway JP withdraw after carrier loss; modern task forces RTB if outspotted; not annihilation) ===
	res["phases"].append("disengage")
	var init_atk : float = float(context.get("initiative_atk", 0.5)) + (0.1 if "initiative" in str(context.get("atk_traits","")) else 0.0)
	var init_def : float = float(context.get("initiative_def", 0.5)) + (0.1 if "initiative" in str(context.get("def_traits","")) else 0.0)
	var org_atk : float = clamp(float(context.get("org_atk", 0.9)), 0.3, 1.2)
	var org_def : float = clamp(float(context.get("org_def", 0.9)), 0.3, 1.2)
	# Disengage higher if took heavy damage, low org, outspotted, good leader init; lower if winning decisively or orders aggressive
	var dis_base_atk : float = 0.25 + (1.0 - org_atk) * 0.4 + init_atk * 0.3
	if spot_def > spot_atk * 1.3: dis_base_atk += 0.3
	if atk_wins: dis_base_atk -= margin * 0.2
	else: dis_base_atk += 0.1
	var dis_chance_atk : float = clamp(dis_base_atk, 0.1, 0.85)
	var dis_base_def : float = 0.25 + (1.0 - org_def) * 0.4 + init_def * 0.3
	if spot_atk > spot_def * 1.3: dis_base_def += 0.3
	if not atk_wins: dis_base_def -= margin * 0.2
	else: dis_base_def += 0.1
	var dis_chance_def : float = clamp(dis_base_def, 0.1, 0.85)
	var dis_atk := randf() < dis_chance_atk
	var dis_def := randf() < dis_chance_def
	res["disengage"] = {
		"attacker_disengaged": dis_atk, "defender_disengaged": dis_def,
		"chances": [dis_chance_atk, dis_chance_def],
		"initiative": [init_atk, init_def], "orgs": [org_atk, org_def]
	}
	if dis_atk or dis_def:
		res["naval_casualties_est"] *= 0.55  # broke contact, less slaughter (key for fun/historical not binary)
		res["key_factors"].append("disengage_successful_leaders_org_intel")
	# Outcome flavor
	if margin > 0.25:
		res["outcome"] = "major_victory" if (atk_wins and not dis_atk) else "minor_with_withdraw"
	else:
		res["outcome"] = "indecisive_withdraw"

	# Key factors for AAR / logs / summary.md (history accurate)
	var kf : Array = _collect_naval_key_factors(context, vis, choke, subh, range_mod, year, has_radar, has_sonar, has_ecm, has_sat, spot_atk, spot_def, jam_atk, a_order, d_order, dis_atk or dis_def, margin)
	res["key_factors"] = kf  # explicit typed Array to satisfy godot strict inference in project settings
	res["engagement_type"] = "close_ambush_sub" if (subh and (range_mod < 0.6 or closer or vis<0.5)) else ("chokepoint_brawl" if choke else ("stand_off_carrier" if (a_order=="STRIKE" or has_jet_carrier) else "surface_gunnery"))

	# Rich print for evidence harness
	print("  [NAVAL RESOLVER] %s | phases=%s winner=%s (atk_win=%.2f) cas=%.2f margin=%.2f vis=%.2f spot(%.2f/%.2f) jam(%.2f/%.2f) fuel(%.2f/%.2f) dis(a=%s d=%s) orders(%s/%s) year=%d radar=%s ecm=%s sub=%s" % [
		res["engagement_type"], str(res["phases"]), res["winner"], atk_win_chance, res["naval_casualties_est"], margin, vis, spot_atk, spot_def, jam_atk, jam_def, fuel_mult_atk, fuel_mult_def, dis_atk, dis_def, a_order, d_order, year, has_radar, has_ecm, subh
	])
	return res

# Helper: collect rich factors for AAR (used in TestRunner naval summary vs history)
func _collect_naval_key_factors(ctx: Dictionary, vis: float, choke: bool, subh: bool, rmod: float, yr: int, radar: bool, sonar: bool, ecm: bool, sat: bool, spat: float, spdf: float, jam: float, ao: String, do: String, disengaged: bool, marg: float) -> Array:
	var factors: Array[String] = []
	if vis < 0.5: factors.append("poor_visibility_favors_stealth_ambush_subs")
	if choke: factors.append("chokepoint_strait_forces_closer_brawl")
	if subh: factors.append("submarine_factor_stealth_wolfpack_or_ambush")
	if radar: factors.append("radar_era_enhanced_detection")
	if not radar and yr < 1938: factors.append("visual_spotting_era_haze_smoke_limits")
	if sat: factors.append("satellite_recon_global_spotting")
	if ecm or jam > 0.15: factors.append("ecm_jamming_degrades_enemy_spot_guided_missiles")
	if ao == "STRIKE" or "carrier" in str(ctx.get("atk_assets","")).to_lower(): factors.append("carrier_air_strike_decisive")
	if do in ["ESCORT", "CONVOY_DUTY"]: factors.append("screening_protects_capitals")
	if disengaged: factors.append("disengage_withdraw_common_historical_not_annihilation")
	if marg > 0.3: factors.append("decisive_margin_one_sided")
	if ctx.get("fuel_atk",1.0) < 0.6 or ctx.get("fuel_def",1.0) < 0.6: factors.append("fuel_endurance_critical_long_deployment")
	if ao in ["AMBUSH", "SEARCH_AND_DESTROY"] and subh: factors.append("sea_wolf_doctrine_sub_advantage")
	if ao == "STRIKE": factors.append("carrier_admiral_air_power")
	factors.append("intel_recon_weather_jam_leader_key_per_Jutland_Midway_Falklands")
	return factors

# (Internal helper stub for spot calc if needed; logic in main for simplicity)


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

	# CP5: munitions/drone stock burn + reliability-amplified losses + troop XP gain.
	results["attacker_munitions"] = apply_combat_munitions_consume(attacker_army_id, intensity, {"role": "attacker"})
	results["defender_munitions"] = apply_combat_munitions_consume(defender_army_id, intensity * 0.65, {"role": "defender"})
	results["attacker_troop_xp"] = apply_formation_combat_experience_gain(attacker_army_id, intensity, battle_result)
	results["defender_troop_xp"] = apply_formation_combat_experience_gain(defender_army_id, intensity * 0.65, battle_result)
	results["attacker_reliability"] = get_formation_reliability_snapshot(attacker_army_id)
	results["defender_reliability"] = get_formation_reliability_snapshot(defender_army_id)
	results["combat_consume_ok"] = true
	results["model"] = "equipment_flow_compact_ledger"
	return results


## CP5: burn missile/drone/munition stock for a side after combat intensity.
func apply_combat_munitions_consume(
	formation_id: String,
	intensity: float = 1.0,
	opts: Dictionary = {},
) -> Dictionary:
	var out := {"ok": false, "consumed": 0, "formation_id": formation_id, "events": []}
	if formation_id.is_empty() or typeof(LeaderManager) == TYPE_NIL or typeof(ProductionManager) == TYPE_NIL:
		return out
	if not ProductionManager.has_method("consume_munitions_from_stockpile"):
		return out
	var f = LeaderManager.get_formation(formation_id)
	if f == null:
		return out
	var tag := str(f.country_tag).strip_edges().to_upper() if "country_tag" in f else ""
	if tag.is_empty():
		return out
	var inten := clampf(intensity, 0.25, 3.0)
	var design := str(f.design_id).strip_edges() if "design_id" in f else ""
	var candidates: Array = []
	# Prefer explicit munitions/drone stock keys, then formation design if missile/drone class.
	if ProductionManager.has_method("get_country_equipment_stockpile"):
		var stock: Dictionary = ProductionManager.get_country_equipment_stockpile(tag)
		for eid in stock.keys():
			var id_l := str(eid).to_lower()
			if "missile" in id_l or "drone" in id_l or "munition" in id_l or "rocket" in id_l:
				if int(stock[eid]) > 0:
					candidates.append(str(eid))
	if candidates.is_empty() and not design.is_empty():
		var dclass := ""
		if ProductionManager.has_method("resolve_design_class_for_stock"):
			dclass = str(ProductionManager.resolve_design_class_for_stock(design))
		if dclass in ["missile", "drone_swarm", "drone", "munition", "rocket_artillery"]:
			candidates.append(design)
	if candidates.is_empty():
		out["ok"] = true  # no munitions to burn is still a valid path
		out["skipped"] = true
		return out
	var total := 0
	var events: Array = []
	for eid in candidates:
		var dclass2 := "missile"
		if ProductionManager.has_method("resolve_design_class_for_stock"):
			dclass2 = str(ProductionManager.resolve_design_class_for_stock(str(eid)))
		var volleys := maxi(1, int(ceil(inten)))
		var hit: Dictionary = ProductionManager.consume_munitions_from_stockpile(
			tag, str(eid), volleys, inten, {"design_class": dclass2},
		)
		if bool(hit.get("ok", false)):
			total += int(hit.get("consumed", 0))
			events.append(hit)
			# One munitions type per resolve is enough for ledger honesty
			break
	out["ok"] = true
	out["consumed"] = total
	out["events"] = events
	out["country_tag"] = tag
	return out


## CP5: surviving combat slowly raises formation combat_experience (troop band, not leaders).
func apply_formation_combat_experience_gain(
	formation_id: String,
	intensity: float = 1.0,
	battle_result: Dictionary = {},
) -> Dictionary:
	var out := {"ok": false, "formation_id": formation_id, "xp_before": 0.0, "xp_after": 0.0, "gained": 0.0}
	if formation_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return out
	var f = LeaderManager.get_formation(formation_id)
	if f == null or not ("combat_experience" in f):
		return out
	var before := clampf(float(f.combat_experience), 0.0, 100.0)
	var inten := clampf(intensity, 0.1, 3.0)
	var outcome := str(battle_result.get("outcome", ""))
	var outcome_mult := 1.0
	if outcome in ["victory", "breakthrough", "heroic_defense"]:
		outcome_mult = 1.25
	elif outcome in ["defeat", "rout"]:
		outcome_mult = 0.7
	# Slow gain — mass slaughter replacement is the main XP story; combat is gradual.
	var gained := clampf(1.2 * inten * outcome_mult, 0.4, 4.5)
	var after := clampf(before + gained, 0.0, 100.0)
	f.combat_experience = after
	out["ok"] = true
	out["xp_before"] = before
	out["xp_after"] = after
	out["gained"] = after - before
	return out


## CP5: reliability snapshot for combat (production stamp + design base).
func get_formation_reliability_snapshot(formation_id: String) -> Dictionary:
	var out := {"ok": false, "reliability": 1.0, "production_reliability": 1.0, "breakdown_risk": 0.0}
	if formation_id.is_empty() or typeof(ProductionManager) == TYPE_NIL:
		return out
	if not ProductionManager.has_method("get_formation_equipment_combat_stats"):
		return out
	var stats: Dictionary = ProductionManager.get_formation_equipment_combat_stats(formation_id)
	if stats.is_empty():
		return out
	var rel := clampf(float(stats.get("reliability", 0.9)), 0.4, 1.0)
	var prod := clampf(float(stats.get("production_reliability", 1.0)), 0.5, 1.0)
	# Low reliability → higher breakdown risk (loss amplification signal)
	var breakdown := clampf((1.0 - rel) * 0.55 + (1.0 - prod) * 0.25, 0.0, 0.55)
	out["ok"] = true
	out["reliability"] = rel
	out["production_reliability"] = prod
	out["breakdown_risk"] = breakdown
	out["combat_mult"] = clampf(0.7 + rel * 0.3, 0.7, 1.0)
	return out


## Call when a formation is eliminated; ~30% chance of leader death or capture.
func resolve_formation_destroyed(formation_id: String) -> Dictionary:
	if typeof(LeaderManager) == TYPE_NIL or formation_id.is_empty():
		return {"type": "none", "leader_id": ""}
	return LeaderManager.handle_formation_destroyed(formation_id)


## CP6: optional deep combat mode — equipment-type weighted resolve (not default grand map).
## Uses on-hand stock composition + reliability + XP; still formation-level (not RTS 1:1).
func resolve_deep_combat(
	attacker_formation_id: String,
	defender_formation_id: String,
	opts: Dictionary = {},
) -> Dictionary:
	var out := {
		"ok": false,
		"deep_ok": false,
		"mode": "deep_equipment_weighted",
		"model": "equipment_flow_compact_ledger",
		"attacker": {},
		"defender": {},
		"outcome": "stalemate",
		"intensity": float(opts.get("intensity", 1.0)),
	}
	var inten := clampf(float(opts.get("intensity", 1.0)), 0.25, 3.0)
	var terrain := str(opts.get("terrain", "plains"))
	var att_power := get_effective_combat_power("", attacker_formation_id, attacker_formation_id, terrain)
	var def_power := get_effective_combat_power("", defender_formation_id, defender_formation_id, terrain)
	if att_power.is_empty() and def_power.is_empty():
		return out
	# Equipment composition weights (deep path): on-hand types shift soft/hard further.
	var att_w := _deep_equipment_weight(attacker_formation_id)
	var def_w := _deep_equipment_weight(defender_formation_id)
	var att_soft := float(att_power.get("soft_attack", 0.5)) * float(att_w.get("soft_mult", 1.0))
	var att_hard := float(att_power.get("hard_attack", 0.1)) * float(att_w.get("hard_mult", 1.0))
	var def_soft := float(def_power.get("soft_attack", 0.5)) * float(def_w.get("soft_mult", 1.0))
	var def_hard := float(def_power.get("hard_attack", 0.1)) * float(def_w.get("hard_mult", 1.0))
	var att_score := (att_soft * 0.65 + att_hard * 0.35) * inten
	var def_score := (def_soft * 0.55 + def_hard * 0.45) * (0.9 + 0.1 * float(def_power.get("organization", 1.0)))
	var ratio := att_score / maxf(def_score, 0.05)
	var outcome := "stalemate"
	if ratio >= 1.35:
		outcome = "attacker_breakthrough"
	elif ratio >= 1.1:
		outcome = "attacker_victory"
	elif ratio <= 0.72:
		outcome = "defender_victory"
	elif ratio <= 0.9:
		outcome = "defender_holds"
	# Munitions consume + troop XP always run on deep resolve
	var mun_a := apply_combat_munitions_consume(attacker_formation_id, inten, {"role": "attacker", "deep": true})
	var mun_d := apply_combat_munitions_consume(defender_formation_id, inten * 0.7, {"role": "defender", "deep": true})
	var xp_a := apply_formation_combat_experience_gain(attacker_formation_id, inten, {"outcome": outcome})
	var xp_d := apply_formation_combat_experience_gain(defender_formation_id, inten * 0.7, {"outcome": outcome})
	out["ok"] = true
	out["deep_ok"] = true
	out["outcome"] = outcome
	out["ratio"] = ratio
	out["attacker"] = {
		"soft": att_soft, "hard": att_hard, "score": att_score, "weights": att_w,
		"reliability": att_power.get("reliability", 1.0),
		"experience_mult": att_power.get("experience_combat_mult", 1.0),
		"munitions": mun_a, "troop_xp": xp_a,
	}
	out["defender"] = {
		"soft": def_soft, "hard": def_hard, "score": def_score, "weights": def_w,
		"reliability": def_power.get("reliability", 1.0),
		"experience_mult": def_power.get("experience_combat_mult", 1.0),
		"munitions": mun_d, "troop_xp": xp_d,
	}
	out["plain"] = "Deep combat: %s (ratio %.2f) — equipment-weighted, not vehicle RTS." % [outcome, ratio]
	return out


func _deep_equipment_weight(formation_id: String) -> Dictionary:
	var w := {"soft_mult": 1.0, "hard_mult": 1.0, "types": {}, "ok": false}
	if formation_id.is_empty() or typeof(ProductionManager) == TYPE_NIL:
		return w
	if not ProductionManager.has_method("get_unit_equipment_stock"):
		return w
	var stock: Dictionary = ProductionManager.get_unit_equipment_stock(formation_id)
	if stock.is_empty():
		return w
	var soft_n := 0
	var hard_n := 0
	var total := 0
	for eid in stock.keys():
		var n := int(stock[eid])
		if n <= 0:
			continue
		total += n
		var id_l := str(eid).to_lower()
		var dclass := ""
		if ProductionManager.has_method("resolve_design_class_for_stock"):
			dclass = str(ProductionManager.resolve_design_class_for_stock(str(eid)))
		w["types"][str(eid)] = n
		if dclass in ["tank", "missile"] or "tank" in id_l or "armor" in id_l or "missile" in id_l:
			hard_n += n
		elif dclass in ["drone_swarm", "fighter"] or "drone" in id_l or "fighter" in id_l:
			soft_n += int(n * 0.7)
			hard_n += int(n * 0.3)
		else:
			soft_n += n
	if total <= 0:
		return w
	var hard_frac := float(hard_n) / float(total)
	var soft_frac := float(soft_n) / float(total)
	w["soft_mult"] = clampf(0.85 + soft_frac * 0.35, 0.85, 1.25)
	w["hard_mult"] = clampf(0.85 + hard_frac * 0.45, 0.85, 1.35)
	w["ok"] = true
	w["hard_frac"] = hard_frac
	w["soft_frac"] = soft_frac
	return w


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
	# Snow increases casualties (harsh conditions); regional winter_warfare mitigates for full controlled winter regions (ties to map layers + regional wiring)
	var snow_m := 0.0
	if typeof(WeatherManager) != TYPE_NIL:
		var wm3 = null
		if Engine.has_singleton("WeatherManager"): wm3 = Engine.get_singleton("WeatherManager")
		if wm3 == null:
			var tree3 := Engine.get_main_loop() as SceneTree
			if tree3 and tree3.root: wm3 = tree3.root.get_node_or_null("/root/WeatherManager")
		if wm3 and wm3.has_method("get_province_snow"):
			snow_m = float(wm3.get_province_snow(province_id))
	if snow_m > 0.2:
		base = min(1.4, base * (1.0 + snow_m * 0.25))
	var reg_b3 := {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
		reg_b3 = MapManager.get_active_regional_control_bonuses(p.owner_tag if p.owner_tag else "")
	var ww_m := float(reg_b3.get("winter_warfare", 0.0))
	if ww_m > 0.0 and snow_m > 0.1:
		base = max(0.6, base * (1.0 - ww_m * 0.2))
	# strategic_depth wiring (next: defender advantage in deep territory like Western Russia reduces casualties for controller side)
	var depth := float(reg_b3.get("strategic_depth", 0.0))
	if depth > 0.0:
		base = max(0.5, base * (1.0 - depth * 0.12))  # lower mult = fewer losses for defender in depth
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

	# Biotech enhancements (cloning cyber genetic human enhancement techs): boost infantry perf, soldier quality
	var inf_enh := float(nat_mods.get("infantry_enhancement", 0.0))
	if inf_enh != 0.0:
		if modified.has("soft_attack"):
			modified["soft_attack"] = float(modified["soft_attack"]) * (1.0 + inf_enh * 0.6)
		if modified.has("readiness"):
			modified["readiness"] = float(modified["readiness"]) * (1.0 + inf_enh * 0.4)
	var sol_enh := float(nat_mods.get("soldier_enhancement", 0.0))
	if sol_enh != 0.0:
		if modified.has("organization"):
			modified["organization"] = float(modified["organization"]) * (1.0 + sol_enh * 0.5)
		if modified.has("hard_attack"):
			modified["hard_attack"] = float(modified["hard_attack"]) * (1.0 + sol_enh * 0.3)

	# Precision, shielding, energy dmg from drones/scanners/shields/phasers (crossed with prior combat engines)
	var prec := float(nat_mods.get("precision_strike", 0.0))
	if prec != 0.0 and modified.has("hard_attack"):
		modified["hard_attack"] = float(modified["hard_attack"]) * (1.0 + prec * 0.8)
	var def_sh := float(nat_mods.get("defensive_shielding", 0.0))
	if def_sh != 0.0:
		if modified.has("readiness"):
			modified["readiness"] = float(modified["readiness"]) * (1.0 + def_sh * 0.4)
		if modified.has("organization"):
			modified["organization"] = float(modified["organization"]) * (1.0 + def_sh * 0.2)
	var en_dmg := float(nat_mods.get("energy_weapon_dmg", 0.0))
	if en_dmg != 0.0:
		if modified.has("hard_attack"):
			modified["hard_attack"] = float(modified["hard_attack"]) * (1.0 + en_dmg * 0.7)

	# Manpower replacement from cloning techs (affects effective manpower in combat context if present)
	var mp_rep := float(nat_mods.get("manpower_replacement", 0.0))
	if mp_rep != 0.0 and modified.has("manpower"):
		modified["manpower"] = float(modified["manpower"]) * (1.0 + mp_rep)

	# VR training efficiency (virtual_reality_1990): boosts readiness/org (sim training per flavor)
	var train_eff := float(nat_mods.get("training_efficiency", 0.0))
	if train_eff != 0.0:
		if modified.has("readiness"):
			modified["readiness"] = min(1.95, float(modified["readiness"]) * (1.0 + train_eff * 0.7))
		if modified.has("organization"):
			modified["organization"] = float(modified["organization"]) * (1.0 + train_eff * 0.3)

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
	# unit_id = army/formation id so on-hand equipment shortages feed soft/hard/has_shortages in resolve.
	var att_power := get_effective_combat_power(
		att_template, attacker_army_id, attacker_army_id, terrain,
		battle_province.id, battle_province.development_level, battle_province.infrastructure,
	)
	var def_power := get_effective_combat_power(
		def_template, defender_army_id, defender_army_id, terrain,
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
			# Defenders AA damage aircraft / disrupt air (in battle context)
			var def_aa := float(def_power.get("aa_factor", 0.0)) if def_power else 0.0
			if def_aa > 0.05:
				air_power_ratio *= max(0.5, 1.0 - def_aa * 0.25)
				if air_power_ratio < 1.0:
					cas_mult *= 0.9
				print("[AA IN BATTLE] Defender AA %.2f reduced air ratio to %.2f, disrupted CAS")
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

	# === DYNAMIC RECON / SORTIE INTEGRATION ===
	# Air recon bonus from registry (RECON missions) improves intel -> slight CAS/odds edge or defender penalty reduction.
	# (sorties already reflected in air_power_ratio via dynamic registry presence updates in Supply)
	var recon_b := 0.0
	var sm_recon = null
	var tree_r := Engine.get_main_loop()
	if tree_r:
		sm_recon = tree_r.root.get_node_or_null("SupplyManager")
	if sm_recon and sm_recon.has_method("get_combat_presence_registry"):
		var reg_r = sm_recon.call("get_combat_presence_registry")
		if reg_r:
			var rpt_r = reg_r.get_report(battle_province.id)
			if rpt_r and rpt_r.has_method("get_air_recon_bonus"):
				recon_b = float(rpt_r.get_air_recon_bonus(att_tag))  # attacker view
	if recon_b > 0.05:
		cas_mult *= (1.0 + recon_b * 0.35)  # recon lets air find better targets, coordinate
		print("[AIR RECON] +%.2f bonus to CAS from dedicated recon sorties (intel/spotting)" % recon_b)
	elif recon_b < -0.05:
		cas_mult *= (1.0 + recon_b * 0.2)  # enemy recon hurts
		print("[AIR RECON] enemy recon penalty to CAS")

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
	return result


func _phase_positioning(battle_province: Province, side_state: Dictionary) -> Dictionary:
	var infra_bonus := clampf(float(battle_province.infrastructure) * 0.04, 0.0, 0.25)
	side_state["defender"]["org"] *= 1.0 + infra_bonus
	var terr := battle_province.terrain if battle_province else "plains"
	if terr in ["mountains", "jungle", "urban", "marsh", "snow_capped"]:
		side_state["defender"]["soft"] *= 1.09
		side_state["defender"]["readiness"] *= 1.04  # terrain defender edge
	# Urban centers and difficult terrain help defenders last longer (HoI4-like, stacks with fort)
	if terr in ["urban", "mountains", "jungle", "hills", "marsh", "snow_capped"]:
		side_state["defender"]["org"] *= 1.08
		side_state["defender"]["readiness"] *= 1.06
	# Weather terrain synergy in positioning (mud/snow amplifies bad terrain penalty for attacker)
	var pid := battle_province.id if battle_province != null else -1
	if pid >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_movement_multiplier"):
		var wm := float(WeatherManager.call("get_movement_multiplier", pid))
		if wm < 0.8 and terr in ["marsh", "mountains", "jungle"]:
			side_state["attacker"]["soft"] *= clampf(wm, 0.65, 0.92)
			side_state["attacker"]["readiness"] *= clampf(wm * 0.8, 0.55, 0.9)
	return {"terrain": terr, "infra_bonus": infra_bonus}


func _phase_engagement(
	battle_province: Province,
	side_state: Dictionary,
	_att_power: Dictionary,
	_def_power: Dictionary,
) -> Dictionary:
	var terr := battle_province.terrain if battle_province else "plains"
	var width := get_combat_width_for_battle(battle_province.id if battle_province else -1, battle_province.id if battle_province else -1, terr)
	var width_scale := clampf(width / 10.0, 0.35, 1.35)
	side_state["attacker"]["soft"] *= width_scale
	side_state["defender"]["soft"] *= clampf(width_scale * 1.05, 0.4, 1.4)
	# Air CAS in engagement: extra soft if air present in att_power context
	if _att_power and float(_att_power.get("air_cas", _att_power.get("combat_bonus", 0.0))) > 0.1:
		side_state["attacker"]["soft"] *= 1.12
	# Weather full: low vis/precip in engagement reduces effective width/engagement for both but attacker more
	var pid := battle_province.id if battle_province != null else -1
	if pid >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_air_mission_effectiveness"):
		var vis_eff := float(WeatherManager.call("get_air_mission_effectiveness", pid))
		if vis_eff < 0.7:
			side_state["attacker"]["soft"] *= (0.8 + vis_eff * 0.25)
			side_state["defender"]["soft"] *= (0.85 + vis_eff * 0.2)
	return {
		"width": width,
		"attacker_strength": _side_strength(side_state["attacker"]),
		"defender_strength": _side_strength(side_state["defender"]),
	}


func _phase_attrition(
	battle_province: Province,
	side_state: Dictionary,
	att_power: Dictionary,
	def_power: Dictionary,
) -> Dictionary:
	var att_supply := 1.0
	var def_supply := 1.0
	var air_dominance_level := str(side_state.get("air_dominance_level", "none"))
	if bool(att_power.get("has_shortages", false)):
		att_supply = 0.82
	if bool(def_power.get("has_shortages", false)):
		def_supply = 0.88
	# Full weather tie in attrition phase (mud/rain/snow/precip reduce readiness/org beyond base supply)
	var pid := battle_province.id if battle_province != null else -1
	if pid >= 0 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_movement_multiplier"):
		var wmult := float(WeatherManager.call("get_movement_multiplier", pid))
		if wmult < 0.8:
			att_supply *= clampf(wmult * 0.7 + 0.3, 0.55, 0.95)
			def_supply *= clampf(wmult * 0.75 + 0.25, 0.6, 0.97)
	side_state["attacker"]["readiness"] *= att_supply
	side_state["defender"]["readiness"] *= def_supply
	side_state["attacker"]["org"] *= lerpf(1.0, att_supply, 0.5)
	side_state["defender"]["org"] *= lerpf(1.0, def_supply, 0.55)
	# Air interdiction extra drag in phase (if air present in powers or mission context)
	if float(att_power.get("air_interdict", 0.0)) > 0.05:
		side_state["defender"]["readiness"] *= 0.9
		side_state["defender"]["org"] *= 0.92

	# Attrition during active combat increased by enemy air superiority (full/partial), shore bombardment, orbital bombardment.
	# Attrition losses/disruption from enemy air support/interceptors (scales with dominance).
	if air_dominance_level == "full":
		side_state["defender"]["org"] *= 0.85
		side_state["defender"]["readiness"] *= 0.88
		print("[AIR SUP ATTRITION] Full air sup increased defender attrition")
	elif air_dominance_level == "partial":
		side_state["defender"]["org"] *= 0.92
		side_state["defender"]["readiness"] *= 0.95
	# Shore bombardment (from naval/attacker special)
	if float(att_power.get("shore_bombard", 0.0)) > 0.05 or "shore" in str(att_power.get("special", "")):
		side_state["defender"]["org"] *= 0.9
		side_state["defender"]["readiness"] *= 0.92
		print("[SHORE BOMBARD ATTRITION] Naval shore support increased defender attrition")
	# Orbital bombardment (space strike)
	if float(att_power.get("space_strike", 0.0)) > 0.05 or "orbital" in str(att_power.get("special", "")):
		side_state["defender"]["org"] *= 0.88
		side_state["defender"]["readiness"] *= 0.9
		print("[ORBITAL ATTRITION] Space/orbital increased defender attrition")

	# Explicit SUPPLY INTERDICT MOD in resolver phase (high-leverage from combat history recs for endurance).
	# Uses SupplyInterdictionEstimator or presence registry to apply battle-level org/readiness drain based on enemy control/air/land around province.
	# Makes prolonged fights (similar strength) and weaker attacks last longer/attrit more if interdicted.
	# Defender less affected (local supply), attacker more (extended lines).
	if typeof(SupplyManager) != TYPE_NIL:
		var sm = SupplyManager
		var inter_chance := 0.0
		if sm.has_method("get_combat_presence_registry"):
			var reg = sm.call("get_combat_presence_registry")
			if reg and reg.has_method("get_report"):
				var rpt = reg.get_report(battle_province.id) if battle_province != null else null
				if rpt != null:
					# ProvinceForceReport is a RefCounted object, not a Dictionary — avoid Object.get(key, default).
					var interdict_v := 0.0
					var enemy_ctrl_v := 0.0
					var enemy_air_v := 0.0
					if typeof(rpt) == TYPE_DICTIONARY:
						interdict_v = float(rpt.get("interdict_chance", 0.0))
						enemy_ctrl_v = float(rpt.get("enemy_control", 0.0))
						enemy_air_v = float(rpt.get("enemy_air", 0.0))
					else:
						if "interdict_chance" in rpt:
							interdict_v = float(rpt.interdict_chance)
						if "enemy_control" in rpt:
							enemy_ctrl_v = float(rpt.enemy_control)
						if "enemy_air" in rpt:
							enemy_air_v = float(rpt.enemy_air)
					inter_chance = clampf(interdict_v + enemy_ctrl_v * 0.15 + enemy_air_v * 0.08, 0.0, 0.6)
		if inter_chance > 0.01:
			var inter_mod := 1.0 - clampf(inter_chance * 0.35, 0.0, 0.45)
			side_state["attacker"]["org"] *= inter_mod
			side_state["attacker"]["readiness"] *= max(0.55, inter_mod)
			side_state["defender"]["org"] *= max(0.65, inter_mod * 0.85)
			print("[SUPPLY INTERDICT MOD] Applied in resolver phase: chance=%.2f mod=%.2f (endurance for prolonged/weaker attacks)" % [inter_chance, inter_mod])

	return {"attacker_supply": att_supply, "defender_supply": def_supply, "weather_mod": 1.0}


func _phase_resolution(
	battle_province: Province,
	side_state: Dictionary,
	attacker_tag: String,
	defender_tag: String,
) -> Dictionary:
	var leader = null  # optional attacker leader for breakthrough traits
	if typeof(LeaderManager) != TYPE_NIL and not attacker_tag.is_empty() and LeaderManager.has_method("get_leader_for_country"):
		leader = LeaderManager.get_leader_for_country(attacker_tag) if LeaderManager.has_method("get_leader_for_country") else null
	var att_power: Dictionary = side_state.get("attacker_power", {}) if side_state.has("attacker_power") else {}
	var def_power: Dictionary = side_state.get("defender_power", {}) if side_state.has("defender_power") else {}
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
		var sec_d: float = GameData.get_secret_fleet_combat_bonus(def_tag_for_space) if GameData.has_method("get_secret_fleet_combat_bonus") else 0.0
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
	# High org + position defending with supplies = far less likely to fold quickly (HoI4-like staying power, puts up fight)
	# Urban/difficult terrain/fortifications help defenders last longer (stacks with org/supply bias)
	var def_org := float(side_state["defender"].get("org", 1.0))
	var def_rdy := float(side_state["defender"].get("readiness", 1.0))
	var def_supply := float(def_power.get("supply_mod", 1.0)) if def_power else 1.0
	var org_def_bias := clampf( (def_org - 0.4) * 0.8, 0.0, 0.55)
	if def_supply > 0.75:
		org_def_bias *= 1.25  # supplied defenders hold much longer
	def_score *= (1.0 + org_def_bias)
	var terr := battle_province.terrain if battle_province else "plains"
	var fort_mod := 1.0
	if battle_province:
		var fort_lv := 0.0
		if "fortification_level" in battle_province:
			fort_lv = float(battle_province.fortification_level)
		else:
			fort_lv = float(battle_province.development_level) * 0.08 + (1.0 if "fort" in str(battle_province.special_features) else 0.0)
		fort_mod = fort_lv
	if terr in ["urban", "mountains", "jungle", "hills", "marsh", "snow_capped"] or fort_mod > 1.15:
		def_score *= 1.12 + clampf(fort_mod - 1.0, 0.0, 0.35)
		if def_org > 0.65:
			def_score *= 1.1  # entrenched high org in urban/fort/terrain holds longer (prolonged fight)

	# Chance breakthroughs (based on leader initiative/breakthrough trait, margin, org diff, terrain).
	var leader_break := 0.0
	if leader != null and "trait_levels" in leader and "breakthrough" in str(leader.trait_levels):
		leader_break = 0.1
	if leader != null and "initiative_skill" in leader:
		leader_break += float(leader.initiative_skill) / 30.0
	if leader_break > 0 and randf() < leader_break:
		att_score *= 1.15
		print("[BREAKTHROUGH CHANCE] Leader trait/initiative caused breakthrough (extra score)")

	# Winner / capture from **final** scores (after defender org/terrain/fort bias + breakthrough).
	var winner := "attacker" if att_score >= def_score else "defender"
	var margin := absf(att_score - def_score) / maxf(def_score, 0.01)
	var outcome := "minor_victory" if margin < 0.12 else "major_victory"
	if winner == "defender" and margin >= 0.2:
		outcome = "heroic_defense"
	elif winner == "defender":
		outcome = "delay_success"
	# Similar strength fights last longer (close scores + high org -> prolonged_attrition, less quick fold)
	if abs(att_score - def_score) / max(def_score, 1.0) < 0.18 and min(def_org, float(side_state["attacker"].get("org", 1.0))) > 0.55:
		outcome = "prolonged_attrition"
		margin *= 0.6  # smaller margin for less decisive immediate outcome
		print("[BATTLE DURATION] Similar strength + high org -> prolonged fight (lasts 'days' via repeated assaults, attrit)")
	# Weaker force attacking stronger: calculate longer time / higher attrition if defender high org/supply/fort
	if att_score < def_score * 0.65 and def_org > 0.6 and def_supply > 0.7:
		outcome = "prolonged_stalemate" if margin < 0.25 else outcome
		margin *= 0.7
		print("[BATTLE DURATION] Weaker attack vs strong org/supplied defender -> prolonged (time to break higher, more attrit)")

	var captured := winner == "attacker" and attacker_tag != defender_tag and not attacker_tag.is_empty()
	var result_dict := {
		"winner": winner,
		"outcome": outcome,
		"attacker_score": att_score,
		"defender_score": def_score,
		"province_control_change": captured,
		"attacker_tag": attacker_tag,
		"defender_tag": defender_tag,
		"province_id": battle_province.id,
	}
	# Add duration estimate for preview/AAR (how long battle "takes" based on org/power diff, terrain)
	var org_diff := def_org - float(side_state["attacker"].get("org", 1.0))
	var duration_est := 1 + clampf( (1.0 - margin) * 4.0 + org_diff * 2.5 + (fort_mod - 1.0) * 2.0 , 0.0, 12.0)
	if terr in ["urban", "mountains"]:
		duration_est += 2.0
	result_dict["estimated_prolongation_days"] = int(duration_est)
	if duration_est > 3:
		print("[BATTLE DURATION] Estimated %d days of attrit (org/supply/terrain/fort bias applied; similar or weaker attacks last longer)" % int(duration_est))
	return result_dict


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
