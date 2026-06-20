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
		var space_bonus: float = 0.15
		final_soft += space_bonus * 5.0
		final_hard += space_bonus * 3.0
		final_org *= 0.92

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
					if province_for_effects:
						if typeof(province_for_effects) == TYPE_DICTIONARY and province_for_effects.has("source"):
							sp_source = str(province_for_effects["source"])
						elif province_for_effects is Object and province_for_effects.has_method("get"):
							sp_source = str(province_for_effects.get("source"))
						elif "source" in province_for_effects:
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
		if typeof(formation_for_effects) == TYPE_DICTIONARY:
			air_int = float(formation_for_effects.get("air_mission_intensity", 0.0)) if formation_for_effects.has("air_mission_intensity") else 0.0
			if formation_for_effects.has("air_mission_type") and str(formation_for_effects.get("air_mission_type","")).to_upper() in ["CAS", "CLOSE_AIR_SUPPORT"]:
				final_soft *= (1.0 + clampf(air_int * 0.12, 0.0, 0.25))
				final_hard *= (1.0 + clampf(air_int * 0.08, 0.0, 0.18))
			elif str(formation_for_effects.get("air_mission_type","")).to_upper() in ["INT", "INTERDICTION"]:
				final_readiness *= (1.0 - clampf(air_int * 0.10, 0.0, 0.20))
				final_org *= (1.0 - clampf(air_int * 0.07, 0.0, 0.15))
		elif formation_for_effects is Object and formation_for_effects.has_method("get"):
			air_int = float(formation_for_effects.call("get", "air_mission_intensity") if formation_for_effects.has("air_mission_intensity") else 0.0)
			# similar for type...

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
	if not army_id.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		var form := LeaderManager.get_formation(army_id)
		if form != null and "strength" in form:
			formation_strength = clampf(float(form.strength), 0.4, 1.0)
			if formation_strength < 0.95:
				# Exhausted/depleted units suffer extra org/readiness friction
				final_org *= lerp(1.0, formation_strength, 0.4)
				final_readiness *= lerp(1.0, formation_strength, 0.6)
	final_soft *= formation_strength
	final_hard *= formation_strength

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
	}


## Stub for naval strategic engagement resolution (called from BattleManager naval path).
## In full sim would use ship class templates, weapon ranges (torp/gun/missile), air cover, etc.
## For now, applies range/ vis / sub / choke mods to outcome. (Moved out of get_effective for proper class scope.)
func resolve_naval_engagement(context: Dictionary, atk_power: float, def_power: float) -> Dictionary:
	var res := {"ok": true, "type": "naval"}
	var vis = float(context.get("weather_vis", 1.0))
	var choke = bool(context.get("chokepoint", false))
	var subh = bool(context.get("sub_heavy", false))
	var range_mod = float(context.get("range_mod", 1.0))
	var closer = bool(context.get("closer_engagement", false))  # from order/storm
	var a_order = str(context.get("attacker_order", ""))
	var d_order = str(context.get("defender_order", ""))
	# Mods (orders amplify: S&D/AMBUSH closer in low vis)
	if subh and (range_mod < 0.6 or closer or a_order in ["AMBUSH", "SEARCH_AND_DESTROY"] or d_order in ["AMBUSH", "SEARCH_AND_DESTROY"]):
		def_power *= 1.3
	if choke:
		atk_power *= 0.85
	# Order specific full resolution (inspired by games: torp surprise for AMBUSH close subs, guns for STRIKE stand-off, air for carriers, ASW counters subs)
	if a_order == "AMBUSH" and (range_mod < 0.6 or closer):
		def_power *= 0.85  # surprise torp/sub bonus for attacker in ambush/closer
	if a_order == "STRIKE" and range_mod > 1.0:
		atk_power *= 1.2  # carrier air/gun at stand off
	if d_order == "ASW" and subh:
		def_power *= 1.15  # ASW counters subs
	# Simple roll
	var total = atk_power + def_power + 0.01
	var atk_win_chance = atk_power / total
	res["winner"] = "attacker" if randf() < atk_win_chance else "defender"
	res["naval_casualties_est"] = randf() * 0.3 + 0.1
	res["engagement_type"] = "close_ambush" if (range_mod < 0.6 or closer) else ("chokepoint_brawl" if choke else "stand_off")
	res["context"] = context
	print("  [NAVAL RESOLVER] %s engagement: vis=%.2f choke=%s sub=%s range_mod=%.2f closer=%s orders(%s/%s) -> %s" % [res["engagement_type"], vis, choke, subh, range_mod, closer, a_order, d_order, res["winner"]])
	return res


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
	# Full weather tie in attrition phase (mud/rain/snow/precip reduce readiness/org beyond base supply)
	var pid := _battle_province.id if _battle_province != null else -1
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
				var rpt = reg.get_report(battle_province.id) if battle_province else null
				if rpt:
					inter_chance = clampf(float(rpt.get("interdict_chance", 0.0)) + float(rpt.get("enemy_control", 0.0)) * 0.15 + float(rpt.get("enemy_air", 0.0)) * 0.08, 0.0, 0.6)
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
	var winner := "attacker" if att_score >= def_score else "defender"
	var margin := absf(att_score - def_score) / maxf(def_score, 0.01)
	var outcome := "minor_victory" if margin < 0.12 else "major_victory"
	if winner == "defender" and margin >= 0.2:
		outcome = "heroic_defense"
	elif winner == "defender":
		outcome = "delay_success"

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
		fort_mod = float(battle_province.get("fortification_level", battle_province.development_level * 0.08 + (1.0 if "fort" in str(battle_province.special_features) else 0.0)))
	if terr in ["urban", "mountains", "jungle", "hills", "marsh", "snow_capped"] or fort_mod > 1.15:
		def_score *= 1.12 + clampf(fort_mod - 1.0, 0.0, 0.35)
		if def_org > 0.65:
			def_score *= 1.1  # entrenched high org in urban/fort/terrain holds longer (prolonged fight)
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
