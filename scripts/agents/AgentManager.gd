# scripts/agents/AgentManager.gd
extends Node

## Core manager for the espionage and agent system (MVP).

signal agent_recruited(agent_id: String, country_tag: String)
signal agent_assigned_to_mission(agent_id: String, mission_id: String)
signal mission_completed(agent_id: String, mission_id: String, outcome: String)
signal agent_captured(agent_id: String, country_tag: String)
signal agent_killed(agent_id: String, country_tag: String)

const MISSIONS_PATH := "res://data/agents/mission_definitions.json"
const MAX_MISSION_HISTORY_PER_AGENT := 12
const MISSION_HISTORY_UI_LIMIT := 6
const RECENT_OPERATIONS_UI_LIMIT := 10

## MVP target list until diplomacy exposes valid operation theaters.
const DEFAULT_TARGET_COUNTRY_TAGS: Array[String] = [
	"USA", "GER", "ENG", "FRA", "SOV", "JAP", "ITA", "CHI",
]

## Daily network sabotage tuning (light but strategic pressure).
## BASE/MAX control the scale of national debuffs + depot sabotage_level accumulation.
## DURATION is used as the "months" value when applying short-lived national debuffs via NMM.
##   While a supply_disruption network is active it re-applies/refresh the effect daily (keeps debuff up).
##   When the network is removed (counter-intel or dismantled), the last-applied effect lingers up to this many
##   "NMM months" (decayed only on monthly ticks). Not a true 4-day timer — see clear_daily_sabotage_effects for instant relief.
## Tuned 2026-04/05 for meaningful daily pressure without instant collapse.
const DAILY_NETWORK_SABOTAGE_BASE := 0.028
const DAILY_NETWORK_SABOTAGE_MAX := 0.12
const DAILY_NETWORK_SABOTAGE_DURATION_DAYS := 4

var agents: Dictionary[String, Array] = {}                    # country_tag -> Array[Agent]
var networks: Dictionary[int, AgentNetwork] = {}                    # province_id (int) -> AgentNetwork
var mission_definitions: Dictionary = {}

var _current_year: int = 1936
var _last_year_ticked: int = -1              # Dedup guard: both TM and Leader year signals may fire during clock migration
var _agent_screen_cache: Dictionary = {}       # country_tag -> AgentScreenData


func _ready() -> void:
	_load_mission_definitions()
	print("AgentManager: Loaded %d mission definitions" % mission_definitions.size())

	# Prefer central TimeManager when available (migration path).
	if typeof(TimeManager) != TYPE_NIL:
		_current_year = TimeManager.get_current_year()
	elif typeof(LeaderManager) != TYPE_NIL:
		_current_year = LeaderManager.get_current_year()

	# Primary listener: central TimeManager
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(_on_game_year_advanced):
			TimeManager.game_year_advanced.connect(_on_game_year_advanced)
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)

	# Agent polish note (high-value remaining): lobby_domestic_law (and future welfare/social) missions use duration_months from JSON (8mo example). Agent unavailable during (enforced by advance_missions). Real assign via AgentAssignmentScreen + Time advance triggers signal -> GameData.resolve. Test without demo button for full trade-off feel. Expand specific missions (e.g. "lobby_welfare_optimization") next if prioritized.

	# Backward-compat during transition
	if typeof(LeaderManager) != TYPE_NIL:
		if not LeaderManager.game_year_advanced.is_connected(_on_game_year_advanced):
			LeaderManager.game_year_advanced.connect(_on_game_year_advanced)


func _on_game_year_advanced(year: int) -> void:
	if year == _last_year_ticked:
		return
	_last_year_ticked = year
	set_current_year(year)
	_release_expired_compromised_agents()
	# Advance missions by 12 months per year for MVP (research/mission cadence is still yearly-batched).
	# Daily network growth + sabotage is handled separately via game_day_advanced (preferred path).
	advance_missions(12)
	# Yearly passive agent national impacts (in addition to daily for cumulative nation effects).
	apply_agent_national_impacts()

func _on_game_day_advanced(_year: int, _month: int, _day: int) -> void:
	# Daily updates for persistent agent networks + real sabotage effects (supply/infra).
	# Primary path (TimeManager central clock). Legacy monthly/yearly paths still exist for missions.
	advance_networks_daily()


func _load_mission_definitions() -> void:
	if not FileAccess.file_exists(MISSIONS_PATH):
		push_error("AgentManager: Could not find mission definitions at %s" % MISSIONS_PATH)
		return

	var file := FileAccess.open(MISSIONS_PATH, FileAccess.READ)
	var json_text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) == TYPE_DICTIONARY:
		mission_definitions = parsed
	else:
		push_error("AgentManager: Failed to parse mission_definitions.json")


# === Core API ===

func get_agents_for_country(country_tag: String) -> Array[Agent]:
	var tag := country_tag.strip_edges().to_upper()
	if not agents.has(tag):
		return [] as Array[Agent]
	var raw: Array = agents[tag]
	var result: Array[Agent] = []
	for item in raw:
		if item is Agent:
			result.append(item)
	return result


func get_agent(agent_id: String) -> Agent:
	for country_agents in agents.values():
		for agent in country_agents as Array[Agent]:
			if agent.agent_id == agent_id:
				return agent
	return null


func recruit_agent(country_tag: String) -> Agent:
	var tag := country_tag.strip_edges().to_upper()
	var new_agent := AgentGenerator.generate_agent(tag, _current_year)

	if not agents.has(tag):
		agents[tag] = [] as Array[Agent]

	agents[tag].append(new_agent)
	invalidate_agent_cache(tag)
	agent_recruited.emit(new_agent.agent_id, tag)
	print("AgentManager: Recruited %s for %s" % [new_agent.name, tag])
	return new_agent


func assign_agent_to_mission(
	agent_id: String,
	mission_id: String,
	target_tag: String = "",
	target_tech_id: String = "",
) -> bool:
	var agent := get_agent(agent_id)
	if agent == null or not agent.is_available():
		return false

	if not mission_definitions.has(mission_id):
		push_warning("AgentManager: Unknown mission '%s'" % mission_id)
		return false

	var mission: Dictionary = mission_definitions[mission_id]
	var skill_req: String = str(mission.get("skill_requirement", "intelligence"))
	var min_skill: int = int(mission.get("min_skill_level", 1))

	if agent.get_skill(skill_req) < min_skill:
		print("Agent %s does not meet the skill requirement for %s" % [agent.name, mission_id])
		return false

	var target := target_tag.strip_edges().to_upper()
	var allow_home := _mission_allows_home_target(mission)
	if target.is_empty() and allow_home:
		target = agent.country_tag
	if target.is_empty() or (target == agent.country_tag and not allow_home):
		push_warning("AgentManager: Invalid mission target '%s'" % target_tag)
		return false

	var tech_target := target_tech_id.strip_edges()
	if typeof(TechnologyManager) != TYPE_NIL:
		if TechnologyManager.mission_requires_tech_target(mission_id) and tech_target.is_empty():
			push_warning("AgentManager: Mission '%s' requires a technology target" % mission_id)
			return false
	else:
		if mission_id == "steal_research" and tech_target.is_empty():
			push_warning("AgentManager: steal_research requires target_tech_id")
			return false

	agent.assigned_target_tag = target
	agent.assigned_target_tech_id = tech_target
	agent.current_mission_id = mission_id
	agent.mission_progress = 0.0
	agent.status = "on_mission"

	invalidate_agent_cache(agent.country_tag)
	agent_assigned_to_mission.emit(agent_id, mission_id)
	var tech_note := ""
	if not tech_target.is_empty() and typeof(TechnologyManager) != TYPE_NIL:
		tech_note = " → %s" % TechnologyManager.get_tech_display_name(tech_target)
	print(
		"Agent %s assigned to %s against %s%s"
		% [agent.name, mission.get("name", mission_id), target, tech_note]
	)
	return true


func _mission_allows_home_target(mission: Dictionary) -> bool:
	return bool(mission.get("allow_self_target", false))


func advance_missions(months: int = 1) -> void:
	for country_tag in agents.keys():
		var country_agents: Array = agents[country_tag]
		for agent in country_agents as Array[Agent]:
			if not agent.is_on_mission():
				continue

			agent.mission_progress += float(months) / 12.0   # crude for now; missions use months

			if agent.mission_progress >= 1.0:
				_resolve_mission(agent)

	# Advance persistent province networks
	advance_networks(months)


func _resolve_mission(agent: Agent) -> void:
	var mission_id := agent.current_mission_id
	if not mission_definitions.has(mission_id):
		_reset_agent_after_mission(agent)
		return

	var mission: Dictionary = mission_definitions[mission_id]
	var success_chance := agent.get_success_chance_for_mission(mission)
	var roll := randf()

	var outcome := "failure"
	if roll < success_chance * 0.55:
		outcome = "success"
	elif roll < success_chance:
		outcome = "partial"

	# === Detection Risk ===
	var detection_chance := float(mission.get("detection_risk", 0.3))
	if outcome == "failure":
		detection_chance *= 1.6   # Failures are much riskier
	if outcome == "success":
		detection_chance *= 0.7

	# Mission record affects spotting: high success builds "fame/profile" (more targeted), but good counter/stealth traits + record allow defending/staying active/hidden.
	# "big part of the agent game is them being spotted and targeted and their ability to defend themselves or stay active and learn and grow."
	var record_mod := agent.get_detection_risk_modifier()
	detection_chance += record_mod  # Can be negative (defensive growth reduces risk)

	# Encryption from radio_iii (national tech) reduces detection risk for this country's operations
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mods: Dictionary = NationalModifierManager.get_combat_modifiers(agent.country_tag)
		var enc := float(mods.get("encryption", 0.0))
		if enc > 0.0:
			detection_chance *= maxf(0.4, 1.0 - enc * 0.35)   # +1.0 encryption → ~35% lower detection chance
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(agent.country_tag, "advanced_sensors"):
		detection_chance *= 0.8  # scanners/sensors tech improves counter-intel and detection (trade-off: emissions reveal position)
	# Extend scanners to full nat mod: use detection_range/stealth from NMM for variable effect in space/agent intel
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mods := NationalModifierManager.get_combat_modifiers(agent.country_tag)
		var det := float(mods.get("detection_range", 0.0))
		var sdet := float(mods.get("stealth_detection", 0.0))
		if det > 0.0 or sdet > 0.0:
			detection_chance *= maxf(0.5, 1.0 - (det + sdet) * 0.6)
			if OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1":
				print("[SPACE WIRING] scanner mod applied in agent detection for %s: det=%.2f sdet=%.2f" % [agent.country_tag, det, sdet])

	var detected := randf() < detection_chance

	_apply_mission_outcome(agent, mission, outcome, detected)

	agent.total_missions_completed += 1
	if outcome in ["success", "partial"]:
		agent.successful_missions += 1
		agent.add_experience(90 if outcome == "success" else 45)

		# Hone skills from missions - "missions agents go on to matter and help them hone their skills"
		var skill_req := str(mission.get("skill_requirement", "intelligence"))
		var hone_amt := 0.25 if outcome == "success" else 0.1
		agent.hone_skill_from_mission(skill_req, hone_amt)

		# Fun trait gain for world-class replay (agents evolve with role experience) - ties specialists to big projects/Ascendancy
		_give_role_trait_from_mission(agent, mission_id, outcome)

		# Mission record + high success on influence missions: extra internal Ascendancy pillar impact + story connection.
		# "key agents and their impact and connection to your story. Along with their abilities to help with internal ascendancy."
		var mission_cat: String = str(mission.get("category", ""))
		if mission_cat == "influence" and agent.get_mission_record_bonus() > 0.1:
			if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_agent_pillar_influence"):
				var extra := int(2 * agent.get_mission_record_bonus() * 10)  # Scale with record
				GameData.apply_agent_pillar_influence(agent.country_tag, "ascendancy", extra, "veteran_agent_influence")
				print("  -> Veteran agent %s boosts internal Ascendancy by %d (mission record matters)" % [agent.name, extra])

	mission_completed.emit(agent.agent_id, mission_id, outcome)

	# Handle post-mission agent state (risk & consequences)
	_handle_post_mission_risk(agent, detected, outcome)

	_append_mission_history(agent, mission_id, outcome, detected)

	_reset_agent_after_mission(agent)
	invalidate_agent_cache(agent.country_tag)


func _apply_mission_outcome(agent: Agent, mission: Dictionary, outcome: String, detected: bool = false) -> void:
	var outcomes: Dictionary = mission.get("outcomes", {})
	var result: Dictionary = outcomes.get(outcome, {})

	var mission_name: String = str(mission.get("name", mission.get("id")))
	var country := agent.country_tag

	# === Prestige (applied via NationalModifierManager when available) ===
	var prestige := int(result.get("prestige_gain", 0))
	if prestige != 0:
		if typeof(NationalModifierManager) != TYPE_NIL:
			NationalModifierManager.apply_influence_effect(
				country,
				0.0,                    # stability_change
				float(prestige),        # prestige_change
				24,                     # duration_months
				"agent_mission",        # source
				mission_name            # source_detail
			)
		else:
			# Legacy national_prestige tracking has been removed.
			# NationalModifierManager is now the single source of truth for prestige/influence.
			push_warning("AgentManager: Prestige gain skipped — legacy national_prestige fallback is no longer supported.")

	# === Real Effect Application ===
	var effect := str(result.get("effect", ""))
	var magnitude := float(result.get("magnitude", 0.0))

	match effect:
		"production_delay":
			_apply_production_delay(agent, mission, outcome, magnitude)
		"supply_disruption":
			_apply_supply_disruption(agent, mission, outcome, magnitude)
		"production_boost":
			_apply_production_boost(agent, mission, outcome, magnitude)
		"resource_discovery":
			_apply_resource_discovery(agent, mission, outcome, magnitude)
		"stability_damage":
			_apply_stability_damage(country, magnitude)
		"research_progress":
			_apply_research_theft(agent, mission, outcome, magnitude, detected)
		"long_term_tech_intel":
			_establish_long_term_tech_intel(agent, mission, outcome)
		"temporary_intel_bonus":
			_apply_intel_bonus(country, magnitude)
		"secret_space_funding":
			_apply_secret_space_funding(agent, mission, outcome, magnitude, detected)
		"enemy_agent_disruption":
			_apply_enemy_agent_disruption(country, magnitude)
		"enemy_intel_degradation":
			_apply_enemy_intel_degradation(country, magnitude)
		"policy_shift":
			# High-value wiring for domestic policy/law missions (pro-natal, borders, fiat, sovereign wealth, etc.).
			# Calls GameData to enact the change. Agent time was the cost (unavailable for other missions).
			if typeof(GameData) != TYPE_NIL and GameData.has_method("resolve_agent_policy_mission"):
				var policy_type := str(result.get("policy_type", mission.get("id", "").replace("lobby_", "")))
				GameData.resolve_agent_policy_mission(agent.agent_id, policy_type, country, outcome, int(magnitude))
		"police_type_shift":
			if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_police_type"):
				GameData.apply_police_type(country, "secret" if outcome == "success" else "local")
			_degrade_enemy_intel(country, magnitude)
		"tech_theft_protection":
			_apply_tech_protection(agent, mission, magnitude)
		# === New 1918 Diplomacy / Peace Conference effects (Phase 1) ===
		"inclusion_leverage":
			_apply_inclusion_leverage(agent, magnitude)
		"minister_compromised":
			_apply_minister_compromised(agent, magnitude)
		"narrative_shift":
			_apply_narrative_shift(country, magnitude)
		"bargaining_leverage":
			_apply_bargaining_leverage(agent, magnitude)
		"enemy_leverage_blocked":
			_apply_enemy_leverage_blocked(country, magnitude)
		"grievance_backlash":
			_apply_grievance_backlash(agent, magnitude)
		"scandal_backlash":
			_apply_scandal_backlash(agent, magnitude)
		"term_modifier":
			_apply_term_modifier(agent, magnitude)
		# === Biotech agent missions (steal/sabotage/scanner for cloning, genetic, future sensors) ===
		"clone_sabotage":
			_apply_clone_sabotage(agent, mission, outcome, magnitude, detected)
		"scanner_detection_bonus":
			_apply_scanner_detection_bonus(country, magnitude)

	# Intelligence missions populate intel cache
	var intel_type := str(result.get("intel_type", ""))
	if intel_type != "":
		_record_intelligence(country, intel_type, outcome)

	print("Mission '%s' for %s resolved as %s (detected: %s)" % [mission_name, agent.name, outcome, detected])


# === New Diplomacy / 1918 Peace Conference effect handlers (Phase 1) ===
# These update GameData.peace_state and apply mechanical effects via NationalModifierManager
# where appropriate. Conference-specific missions are the primary way Central Powers players
# can change history (inclusion at the table, softened terms, etc.).

func _apply_inclusion_leverage(agent: Agent, magnitude: float) -> void:
	if typeof(GameData) != TYPE_NIL:
		GameData.add_inclusion_leverage(agent.country_tag, int(magnitude), "agent_mission:" + agent.current_mission_id)
	# Also give a small direct prestige/stability bump via NMM for the owning country
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mod := {
			"effect_id": "peace_inclusion_%s_%d" % [agent.country_tag, Time.get_unix_time_from_system()],
			"source": "agent_mission",
			"source_detail": "Diplomatic success — peace table leverage",
			"modifiers": {"prestige": 4.0, "stability": 2.0},
			"duration_months": 36
		}
		NationalModifierManager.apply_national_effect(agent.country_tag, mod)


func _apply_minister_compromised(agent: Agent, magnitude: float) -> void:
	if typeof(GameData) != TYPE_NIL:
		GameData.add_inclusion_leverage(agent.country_tag, 18, "honeypot:" + agent.current_mission_id)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mod := {
			"effect_id": "peace_minister_compromised_%s" % agent.country_tag,
			"source": "agent_mission",
			"source_detail": "Honeypot / compromise operation",
			"modifiers": {"prestige": 6.0},
			"duration_months": 24
		}
		NationalModifierManager.apply_national_effect(agent.country_tag, mod)
	print("Peace: Minister compromised by %s — strong conference influence generated." % agent.name)


func _apply_narrative_shift(country: String, magnitude: float) -> void:
	if typeof(GameData) != TYPE_NIL:
		# Narrative shifts reduce grievance for our side or increase for targets
		GameData.add_grievance(country, -int(magnitude * 0.5), "narrative_influence")
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mod := {
			"effect_id": "peace_narrative_%s" % country,
			"source": "agent_mission",
			"source_detail": "Public narrative operation",
			"modifiers": {"stability": 1.5},
			"duration_months": 18
		}
		NationalModifierManager.apply_national_effect(country, mod)


func _apply_bargaining_leverage(agent: Agent, magnitude: float) -> void:
	if typeof(GameData) != TYPE_NIL:
		GameData.add_inclusion_leverage(agent.country_tag, int(magnitude), "leak_operation")
	print("Peace: Bargaining leverage generated by leak from %s." % agent.name)


func _apply_enemy_leverage_blocked(country: String, magnitude: float) -> void:
	if typeof(GameData) != TYPE_NIL:
		# Reduce enemy inclusion if we can identify (for simplicity, small global effect or log)
		# In full system we'd have target_tag on the mission.
		GameData.add_inclusion_leverage(country, -int(magnitude * 0.6), "counter_conference")
	print("Peace: Enemy conference leverage blocked for operations from %s." % country)


func _apply_grievance_backlash(agent: Agent, magnitude: float) -> void:
	if typeof(GameData) != TYPE_NIL:
		GameData.add_grievance(agent.country_tag, int(magnitude), "failed_inclusion_attempt")
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mod := {
			"effect_id": "peace_backlash_%s" % agent.country_tag,
			"source": "agent_mission",
			"source_detail": "Exposed or failed diplomatic push",
			"modifiers": {"stability": -3.0},
			"duration_months": 12
		}
		NationalModifierManager.apply_national_effect(agent.country_tag, mod)


func _apply_scandal_backlash(agent: Agent, magnitude: float) -> void:
	if typeof(GameData) != TYPE_NIL:
		GameData.add_grievance(agent.country_tag, int(magnitude * 0.7), "honeypot_scandal")
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mod := {
			"effect_id": "peace_scandal_%s" % agent.country_tag,
			"source": "agent_mission",
			"source_detail": "Honeypot operation exposed",
			"modifiers": {"prestige": -5.0, "stability": -4.0},
			"duration_months": 18
		}
		NationalModifierManager.apply_national_effect(agent.country_tag, mod)
	print("Peace: Scandal backlash from failed honeypot by %s." % agent.name)


func _apply_term_modifier(agent: Agent, magnitude: float) -> void:
	if typeof(GameData) != TYPE_NIL:
		GameData.add_inclusion_leverage(agent.country_tag, int(magnitude), "bribe_or_influence")
	print("Peace: Direct term modifier influence from %s (%.0f)." % [agent.name, magnitude])


func set_current_year(year: int) -> void:
	_current_year = year


func get_current_year() -> int:
	return _current_year


func get_available_agents(country_tag: String) -> Array[Agent]:
	var result: Array[Agent] = []
	for agent in get_agents_for_country(country_tag):
		if agent.is_available():
			result.append(agent)
	return result


func get_mission_definition(mission_id: String) -> Dictionary:
	return mission_definitions.get(mission_id, {}).duplicate(true)


# === Province Network / Resistance Ring System ===

func get_network(province_id: int) -> AgentNetwork:
	return networks.get(province_id) as AgentNetwork


func get_networks_for_country(country_tag: String) -> Array[AgentNetwork]:
	var tag := country_tag.strip_edges().to_upper()
	var result: Array[AgentNetwork] = []
	for net in networks.values():
		if net is AgentNetwork and net.controlling_country == tag:
			result.append(net)
	return result


func establish_network(lead_agent_id: String, province_id: int, focus: String = "intelligence") -> bool:
	var agent := get_agent(lead_agent_id)
	if agent == null or not agent.is_available():
		return false

	if networks.has(province_id):
		print("AgentManager: Network already exists in province %d" % province_id)
		return false

	var net := AgentNetwork.new()
	net.network_id = "%s_net_%d" % [agent.country_tag.to_lower(), province_id]
	net.province_id = province_id
	net.controlling_country = agent.country_tag
	net.lead_agent_id = lead_agent_id
	net.focus = focus
	net.strength = 15.0 + (agent.get_skill("intelligence") * 2.5)
	net.local_operatives = 2

	networks[province_id] = net

	# Assign the agent to running this network
	agent.status = "on_mission"
	agent.current_mission_id = "network_lead"
	agent.assigned_province_id = province_id   # We may need to add this field to Agent later

	print("AgentManager: %s established a %s network in province %d" % [agent.name, focus, province_id])
	return true


func advance_networks(months: int = 1) -> void:
	for province_id in networks.keys():
		var net: AgentNetwork = networks[province_id]
		if net == null or not net.is_active():
			continue

		# Grow the network slowly over time (recruiting locals)
		var growth := 1.5 + (randf() * 1.5)
		net.strength = clampf(net.strength + growth * months, 0.0, 100.0)
		if randf() < 0.35 * months:
			net.local_operatives += 1

		# Perform the network's focus action
		_process_network_action(net, months)

## Lightweight daily update for agent networks + province sabotage effects.
## Called by the central TimeManager via game_day_advanced (the preferred integration point).
## Much smaller increments than the legacy monthly version for smooth map presence.
## NOTE: advance_networks(months) legacy path (from missions/year) still grows networks but does not apply sabotage "teeth".
func advance_networks_daily() -> void:
	for province_id in networks.keys():
		var net: AgentNetwork = networks[province_id]
		if net == null or not net.is_active():
			continue

		net.last_daily_note = ""
		net.last_daily_effect = ""
		net.last_daily_effect_scalar = 0.0
		var prev_strength := net.strength
		var prev_ops := net.local_operatives

		# Very slow daily growth (roughly 1/30th of monthly rate for smoothness)
		var daily_growth := 0.05 + (randf() * 0.05)
		net.strength = clampf(net.strength + daily_growth, 0.0, 100.0)

		# Small daily chance to recruit a new operative
		if randf() < 0.012:  # ~1.2% per day → roughly 30-40% chance per month
			net.local_operatives += 1

		# Daily focus action (very light version of the monthly logic)
		var action_note := _process_network_action_daily(net)
		var effect_note := _apply_daily_network_province_effects(net)
		if action_note == "detected":
			net.last_daily_note = "detected"
		elif net.local_operatives > prev_ops:
			net.last_daily_note = "recruit"
		elif not action_note.is_empty():
			net.last_daily_note = action_note
		elif not effect_note.is_empty():
			net.last_daily_note = effect_note
		elif net.strength > prev_strength + 0.001:
			net.last_daily_note = "growth"


func _process_network_action(net: AgentNetwork, months: int) -> void:
	var lead := get_agent(net.lead_agent_id)
	if lead == null:
		return

	var enemy_pressure := _estimate_enemy_pressure(net.province_id)

	# Effectiveness reduced by enemy presence and counter-intel
	var effectiveness := net.get_effectiveness() * (1.0 - enemy_pressure * 0.6)
	effectiveness = clampf(effectiveness, 0.1, 1.8)

	var detection_chance := 0.12 * enemy_pressure

	# Encryption (from radio_iii etc.) reduces network detection risk for the owning country
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mods: Dictionary = NationalModifierManager.get_combat_modifiers(net.controlling_country)
		var enc := float(mods.get("encryption", 0.0))
		if enc > 0.0:
			detection_chance *= maxf(0.5, 1.0 - enc * 0.4)

	match net.focus:
		"intelligence":
			if randf() < 0.7 * months:
				var intel := int(4 + effectiveness * 6)
				net.total_intel_gathered += intel
				print("Network in province %d gathered %d intel (effectiveness: %.2f)" % [net.province_id, intel, effectiveness])

		"supply_disruption":
			var disruption := effectiveness * 0.08 * months
			net.total_disruption_caused += disruption
			# TODO: Apply actual province-level supply penalty here (reduce throughput, increase interdiction in this province)
			print("Network in province %d disrupted supply by %.2f (effectiveness: %.2f)" % [net.province_id, disruption, effectiveness])

		"infrastructure_sabotage":
			# Future: damage infrastructure or increase movement cost in province
			pass

	# Detection roll
	if randf() < detection_chance * months:
		_handle_network_detection(net)


## Very light daily version of network focus actions and detection.
func _process_network_action_daily(net: AgentNetwork) -> String:
	var lead := get_agent(net.lead_agent_id)
	if lead == null:
		return ""

	var enemy_pressure := _estimate_enemy_pressure(net.province_id)
	var effectiveness := net.get_effectiveness() * (1.0 - enemy_pressure * 0.6)
	effectiveness = clampf(effectiveness, 0.1, 1.8)

	var detection_chance := 0.12 * enemy_pressure

	# Apply encryption reduction (same as monthly path)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mods: Dictionary = NationalModifierManager.get_combat_modifiers(net.controlling_country)
		var enc := float(mods.get("encryption", 0.0))
		if enc > 0.0:
			detection_chance *= maxf(0.5, 1.0 - enc * 0.4)

	var action_note := ""
	match net.focus:
		"intelligence":
			# Daily intel gathering (much smaller than monthly)
			if randf() < 0.08:  # ~8% chance per day
				var intel := int(0.2 + effectiveness * 0.3)
				net.total_intel_gathered += max(0, intel)
				action_note = "intel"

		"supply_disruption":
			var disruption := effectiveness * 0.003   # very small daily
			net.total_disruption_caused += disruption
			if disruption > 0.0001:
				action_note = "disrupt"
			# TODO: Apply actual small daily province supply impact here

		"infrastructure_sabotage":
			if randf() < 0.04:
				action_note = "sabotage"

	# Daily detection accumulation (much more granular than monthly)
	net.detection_risk_accumulated += detection_chance * 0.08

	# Roll for detection (daily chance is low but accumulates over time)
	if randf() < detection_chance * 0.08:
		_handle_network_detection(net)
		return "detected"
	return action_note


## Applies small, scaled daily province-level effects for active networks (new in this session).
##
## Daily "teeth" for agent networks driven by TimeManager.game_day_advanced (primary path):
##
## 1. supply_disruption focus:
##    - Refreshes a temporary national debuff (via NMM, tagged with DAILY_..._DURATION_DAYS as "months" units).
##      Refreshed every day while network lives → constant pressure. When network dies, lingers until
##      NMM monthly decay or explicit clear_daily_sabotage_effects (counter-intel).
##    - Direct per-province sabotage on ProvinceDepotState: immediate stockpile hit + accumulation of
##      `sabotage_level` (0-0.9). Produces *targeted* multi-day throughput reduction in pull_outflow
##      (up to ~55% penalty) + slow daily decay (0.13) in SupplyManager. Clearable instantly via counter-intel.
##    - SupplyManager daily gen also applies a generation penalty via get_supply_disruption_in_province().
##
## 2. infrastructure_sabotage focus:
##    - Small daily chipping of infrastructure (affects movement cost + future supply gen).
##    - Recovers via automatic daily repair in MapManager (low base 0.08 + infra pride + stability + engineer formation bonuses + "infrastructure_repair" tech/focus modifier).
##      Full breakdown exposed via get_infrastructure_repair_breakdown() for UI/strategy.
##
## Effects refresh daily while network active. province_data_changed emitted for reactivity (map tints/rings update).
##
## Repair / counter-play:
## - Automatic slow infra repair (MapManager daily).
## - clear_daily_sabotage_effects(province_id) removes the NMM debuff + zeros depot sabotage_level immediately.
## - Counter-intel missions actively call it for enemy networks in your territory (real response to daily pressure).
## - ProductionManager + Supply + Map + AgentNetworkLayer all wired to the same TimeManager.game_day_advanced.
##
## NOTE: The legacy monthly advance_networks() path (still called from advance_missions/yearly) does growth
## and focus actions but NO sabotage application (TODOs remain). Daily is the source of truth for "teeth".
## Dual growth on year boundary is mitigated by last_year_ticked guards + daily being the smooth path.
##
## Scaling: DAILY_NETWORK_SABOTAGE_BASE/MAX + effectiveness. See consts at top for tuning.
func _apply_daily_network_province_effects(net: AgentNetwork) -> String:
	if net == null or not net.is_active():
		return ""

	var pid := net.province_id
	var effectiveness := net.get_effectiveness()  # 0.1 - 1.5+
	var magnitude := clampf(effectiveness * DAILY_NETWORK_SABOTAGE_BASE, 0.004, DAILY_NETWORK_SABOTAGE_MAX)
	net.last_daily_effect_scalar = magnitude

	match net.focus:
		"supply_disruption":
			net.last_daily_effect = "supply_disruption"
			# Apply short (3-day) temporary supply pressure debuff on the controlling country
			if typeof(NationalModifierManager) != TYPE_NIL:
				var effect_id := "agent_net_supply_%d" % pid
				var effect := {
					"effect_id": effect_id,
					"source": "agent_network",
					"source_detail": "Daily sabotage from network in province %d" % pid,
					"modifiers": {
						"supply_consumption": magnitude * 0.9,
						"attrition": magnitude * 0.35
					},
					"duration_months": DAILY_NETWORK_SABOTAGE_DURATION_DAYS,
					"remaining_months": DAILY_NETWORK_SABOTAGE_DURATION_DAYS,
					"is_debuff": true
				}
				NationalModifierManager.apply_national_effect(net.controlling_country, effect)

			# Direct per-province sabotage on the local depot: stock hit + persistent "sabotaged" state.
			# sabotage_level provides targeted, multi-day throughput reduction (see ProvinceDepotState.pull_outflow
			# and SupplyManager daily advance for decay). Clearable via counter-intel.
			if typeof(SupplyManager) != TYPE_NIL:
				var depot = SupplyManager.depot_states.get(pid)
				if depot != null:
					var sabotage := 8.0 * effectiveness
					# Hit stockpile (immediate loss) — use correct field name
					depot.stockpile = max(0.0, depot.stockpile - sabotage * 0.3)
					# Accumulate sabotaged state for ongoing targeted throughput penalty (more meaningful than one-frame temp hit)
					var add_level := clampf(0.10 + effectiveness * 0.22, 0.05, 0.55)
					depot.sabotage_level = clampf(depot.sabotage_level + add_level, 0.0, 0.9)

			if typeof(MapManager) != TYPE_NIL:
				MapManager.notify_province_changed(pid, "effects")
			return "disrupt"

		"infrastructure_sabotage":
			net.last_daily_effect = "infrastructure_sabotage"
			var damaged := false
			# Chip infrastructure (permanent until repaired; affects movement cost and future supply)
			if typeof(MapManager) != TYPE_NIL:
				var p := MapManager.get_province(pid)
				if p != null:
					var damage := int(0.5 + effectiveness * 0.35)
					if damage > 0 and p.infrastructure > 0:
						damaged = true
					var new_infra: int = max(0, p.infrastructure - damage)
					MapManager.update_province_infrastructure(pid, new_infra)

				MapManager.notify_province_changed(pid, "infrastructure")
			if damaged:
				return "sabotage"
			return "infra_pressure"

	return ""


func _estimate_enemy_pressure(province_id: int) -> float:
	# Polished: query real forces if available (Battle/CombatPresence or Map forces), fallback rand for detection risk
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_owner"):
		var owner := str(MapManager.get_province_owner(province_id))
		var player := ""
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
			player = LeaderManager.get_player_country_tag()
		if owner != "" and owner != player:
			# Higher pressure if enemy owned (more counter-intel)
			return randf_range(0.45, 0.85)
	# Try combat registry stub if present (for stationed enemy)
	if typeof(Engine) != TYPE_NIL and Engine.has_singleton("CombatPresenceRegistry") or (get_tree() and get_tree().root.get_node_or_null("/root/CombatPresenceRegistry")):
		return randf_range(0.3, 0.7)
	return randf_range(0.15, 0.65)  # baseline for neutral/owned


## Returns the effectiveness (0.0 - 1.5+) of an active supply_disruption network in the given province, if any.
## Used by SupplyManager to apply targeted per-province penalties on local generation.
func get_supply_disruption_in_province(pid: int) -> float:
	var net: AgentNetwork = networks.get(pid)
	if net == null or not net.is_active() or net.focus != "supply_disruption":
		return 0.0
	return net.get_effectiveness()


func _handle_network_detection(net: AgentNetwork) -> void:
	var lead := get_agent(net.lead_agent_id)
	if lead == null:
		return

	net.strength *= 0.6
	net.local_operatives = max(0, net.local_operatives - 2)

	var roll := randf()
	var owner := net.controlling_country
	if roll < 0.25:
		lead.status = "captured"
		print("Network in province %d was compromised — lead agent %s captured!" % [net.province_id, lead.name])
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.post_news("Agent Network Compromised", "%s network in pid %d detected & lead captured. Persistent effects ended." % [owner, net.province_id], "espionage")
			LeaderEventUI.show_toast("Enemy agents captured in network (pid %d)" % net.province_id, 4.0)
	elif roll < 0.55:
		net.strength *= 0.5
		print("Network in province %d suffered major losses from detection." % net.province_id)
		if typeof(LeaderEventUI) != TYPE_NIL and owner == (LeaderManager.get_player_country_tag() if typeof(LeaderManager)!=TYPE_NIL else ""):
			LeaderEventUI.post_news("Network Losses", "Your network in pid %d suffered detection losses. Strength halved." % net.province_id, "espionage")
	else:
		print("Network in province %d was detected but survived with reduced strength." % net.province_id)
		if typeof(LeaderEventUI) != TYPE_NIL and owner == (LeaderManager.get_player_country_tag() if typeof(LeaderManager)!=TYPE_NIL else ""):
			LeaderEventUI.show_toast("Network detected but active (pid %d, reduced)." % net.province_id, 3.0)

	if net.strength < 8.0:
		networks.erase(net.province_id)
		print("Network in province %d has been dismantled." % net.province_id)
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.post_news("Network Dismantled", "Agent network in pid %d fully dismantled by detection/counter-intel." % net.province_id, "espionage")


func get_target_countries_for(country_tag: String) -> Array[String]:
	var owner := country_tag.strip_edges().to_upper()
	var targets: Array[String] = [owner]
	for tag in DEFAULT_TARGET_COUNTRY_TAGS:
		if tag != owner:
			targets.append(tag)
	return targets


func get_mission_categories() -> Array[String]:
	var categories: Dictionary = {}
	for mission in mission_definitions.values():
		if typeof(mission) != TYPE_DICTIONARY:
			continue
		var cat: String = str((mission as Dictionary).get("category", "")).strip_edges().to_lower()
		if not cat.is_empty():
			categories[cat] = true
	var result: Array[String] = []
	for cat in categories.keys():
		result.append(str(cat))
	result.sort()
	return result


func get_eligible_missions_for_agent(
	agent_id: String,
	category_filter: String = "",
) -> Array[Dictionary]:
	var agent := get_agent(agent_id)
	if agent == null:
		return []

	var category_needle := category_filter.strip_edges().to_lower()
	var rows: Array[Dictionary] = []
	for mission_id in mission_definitions.keys():
		var mission: Dictionary = mission_definitions[mission_id] as Dictionary
		var mission_category := str(mission.get("category", "")).to_lower()
		if not category_needle.is_empty() and mission_category != category_needle:
			continue
		var skill_req := str(mission.get("skill_requirement", "intelligence"))
		var min_skill := int(mission.get("min_skill_level", 1))
		var agent_skill := agent.get_skill(skill_req)
		if agent_skill < min_skill:
			continue

		# Respect tech-unlocked agent missions (e.g. "infiltrate_research_lab" from radio_iii)
		if typeof(TechnologyManager) != TYPE_NIL:
			if mission_id == "infiltrate_research_lab":
				if not TechnologyManager.has_tech_unlock(agent.country_tag, "agent_mission", "infiltrate_research_lab"):
					continue
			if mission_id == "fund_secret_space_program":
				if not TechnologyManager.has_rule_flag(agent.country_tag, "secret_funding") and not TechnologyManager.has_tech_unlock(agent.country_tag, "rule_flag", "secret_funding"):
					continue
			if mission_id == "steal_space_intel":
				if not (TechnologyManager.has_tech_unlock(agent.country_tag, "rule_flag", "allow_satellites") or TechnologyManager.is_tech_completed(agent.country_tag, "v2_rocket") or TechnologyManager.is_tech_completed(agent.country_tag, "sputnik_satellite")):
					continue
			if mission_id == "steal_genetic" or mission_id == "sabotage_clone_vat":
				if not (TechnologyManager.has_tech_unlock(agent.country_tag, "rule_flag", "cloning") or TechnologyManager.is_tech_completed(agent.country_tag, "cloning_tech_1980") or TechnologyManager.is_tech_completed(agent.country_tag, "genetic_engineering_1970")):
					continue
			if mission_id == "scanner_intel":
				if not (TechnologyManager.has_tech_unlock(agent.country_tag, "rule_flag", "advanced_sensors") or TechnologyManager.is_tech_completed(agent.country_tag, "scanners_sensors_1975")):
					continue

		# Respect 1918 conference pre/during window missions (Phase 1/2): only available in ~1918-early1919 window for high-stakes diplomacy leverage.
		# Outside window, conference_window_only missions are hidden (prevents polluting normal agent picker; special get_diplomacy... still usable if forced).
		var conf_only := bool(mission.get("conference_window_only", false))
		if conf_only and typeof(self) != TYPE_NIL and has_method("is_1918_conference_window_active"):
			if not is_1918_conference_window_active():
				continue

		rows.append(_mission_row_for_agent(agent, str(mission_id), mission))

	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var cat_a := str(a.get("category", ""))
			var cat_b := str(b.get("category", ""))
			if cat_a != cat_b:
				return cat_a < cat_b
			return float(b.get("success_chance", 0.0)) < float(a.get("success_chance", 0.0))
	)
	return rows


func get_agent_screen_data(country_tag: String, use_cache: bool = true) -> AgentScreenData:
	var tag := country_tag.strip_edges().to_upper()
	if use_cache and _agent_screen_cache.has(tag):
		return _agent_screen_cache[tag] as AgentScreenData
	var data := _build_agent_screen_data(tag)
	_agent_screen_cache[tag] = data
	return data


func invalidate_agent_cache(country_tag: String = "") -> void:
	if country_tag.is_empty():
		_agent_screen_cache.clear()
	else:
		_agent_screen_cache.erase(country_tag.strip_edges().to_upper())


func get_agent_summary(agent_id: String) -> Dictionary:
	var agent := get_agent(agent_id)
	if agent == null:
		return {}
	return _agent_to_summary(agent)


func _build_agent_screen_data(country_tag: String) -> AgentScreenData:
	var data := AgentScreenData.new()
	data.country_tag = country_tag

	var summaries: Array[Dictionary] = []
	for agent in get_agents_for_country(country_tag):
		summaries.append(_agent_to_summary(agent))

	data.agents = summaries
	data.total_agents = summaries.size()
	for summary in summaries:
		var group := str(summary.get("status_group", ""))
		match group:
			"available":
				data.available_agents += 1
			"on_mission":
				data.on_mission_agents += 1
			"compromised":
				data.compromised_agents += 1
			"inactive":
				data.inactive_agents += 1

	data.target_countries = get_target_countries_for(country_tag)
	data.mission_categories = get_mission_categories()
	data.intel_reports = get_intel_reports(country_tag)
	data.recent_operations = get_recent_operations(country_tag, RECENT_OPERATIONS_UI_LIMIT)
	if typeof(NationalSpiritManager) != TYPE_NIL:
		data.national_effects = NationalSpiritManager.get_national_effects_snippet(country_tag, 5)
	return data


func _agent_to_summary(agent: Agent) -> Dictionary:
	var mission_name := ""
	var mission_category := ""
	if not agent.current_mission_id.is_empty():
		var mission := get_mission_definition(agent.current_mission_id)
		mission_name = str(mission.get("name", agent.current_mission_id))
		mission_category = str(mission.get("category", ""))

	var history_slice: Array[Dictionary] = []
	var limit := mini(agent.mission_history.size(), MISSION_HISTORY_UI_LIMIT)
	for i in range(limit):
		var entry: Variant = agent.mission_history[i]
		if typeof(entry) == TYPE_DICTIONARY:
			history_slice.append((entry as Dictionary).duplicate())

	var summary := {
		"agent_id": agent.agent_id,
		"country_tag": agent.country_tag,
		"name": agent.name,
		"status": agent.status,
		"status_group": agent.get_status_group(),
		"status_detail": _format_agent_status_detail(agent),
		"level": agent.level,
		"experience": agent.experience,
		"intelligence": agent.intelligence,
		"sabotage": agent.sabotage,
		"influence": agent.influence,
		"technology": agent.technology,
		"counter_intelligence": agent.counter_intelligence,
		"skills_text": (
			"INT %d  SAB %d  INF %d  TECH %d"
			% [agent.intelligence, agent.sabotage, agent.influence, agent.technology]
		),
		"assigned_target_tag": agent.assigned_target_tag,
		"assigned_target_tech_id": agent.assigned_target_tech_id,
		"assigned_target_tech_name": (
			TechnologyManager.get_tech_display_name(agent.assigned_target_tech_id)
			if typeof(TechnologyManager) != TYPE_NIL and not agent.assigned_target_tech_id.is_empty()
			else ""
		),
		"current_mission_id": agent.current_mission_id,
		"mission_name": mission_name,
		"mission_category": mission_category,
		"mission_progress": agent.mission_progress,
		"missions_completed": agent.total_missions_completed,
		"successful_missions": agent.successful_missions,
		"compromised_until_year": agent.compromised_until_year,
		"portrait_path": agent.portrait_path,
		"mission_history": history_slice,
		"record_bonus": agent.get_mission_record_bonus(),  # World-class: record hones performance, affects Ascendancy/story impact
		"veteran_status": "Legendary" if agent.get_mission_record_bonus() > 0.2 else ("Veteran" if agent.total_missions_completed > 5 else "Rookie"),
		"can_assign_mission": agent.is_available(),
		"is_compromised": agent.status == "compromised",
		"is_inactive": agent.is_inactive(),
		"status_badge": _status_badge_for(agent),
		"recovery_years_remaining": _recovery_years_remaining(agent),
		"inactive_kind": agent.status if agent.is_inactive() else "",
	}

	if agent.is_on_mission() and not agent.current_mission_id.is_empty():
		var active_mission := get_mission_definition(agent.current_mission_id)
		summary["active_mission_impact"] = AgentMissionImpact.describe_mission_outcome(
			active_mission,
			"success",
		)

	return summary


func _mission_row_for_agent(agent: Agent, mission_id: String, mission: Dictionary) -> Dictionary:
	var skill_req := str(mission.get("skill_requirement", "intelligence"))
	var impact_preview := AgentMissionImpact.get_impact_preview(mission)
	return {
		"mission_id": mission_id,
		"name": str(mission.get("name", mission_id)),
		"category": str(mission.get("category", "")),
		"description": str(mission.get("description", "")),
		"duration_months": int(mission.get("duration_months", 3)),
		"detection_risk": float(mission.get("detection_risk", 0.3)),
		"skill_requirement": skill_req,
		"min_skill_level": int(mission.get("min_skill_level", 1)),
		"agent_skill": agent.get_skill(skill_req),
		"success_chance": agent.get_success_chance_for_mission(mission),
		"impact_preview": impact_preview,
		"impact_success": impact_preview.get("success", ""),
		"impact_partial": impact_preview.get("partial", ""),
		"impact_failure": impact_preview.get("failure", ""),
	}


func clear_all_agents() -> void:
	agents.clear()
	invalidate_agent_cache()
	print("AgentManager: All agents cleared.")


func _reset_agent_after_mission(agent: Agent) -> void:
	agent.assigned_target_tag = ""
	agent.assigned_target_tech_id = ""
	agent.current_mission_id = ""
	agent.mission_progress = 0.0
	if agent.status not in ["compromised", "captured", "killed"]:
		agent.status = "available"
	invalidate_agent_cache(agent.country_tag)


func _handle_post_mission_risk(agent: Agent, detected: bool, outcome: String) -> void:
	if not detected:
		return

	var country := agent.country_tag
	var roll := randf()

	if outcome == "success":
		# Even on success, high detection can compromise the agent
		if roll < 0.35:
			_set_agent_compromised(agent, 2)  # compromised for ~2 years
			print("  -> %s was compromised after a successful but detected mission." % agent.name)
		return

	# Failure or partial + detection
	if roll < 0.25:
		# Defend/stay active: Good mission record + stealth traits give chance to avoid worst (learn/grow even if targeted).
		var defend := agent.get_mission_record_bonus() + agent.get_trait_bonus("stay_hidden") + agent.get_trait_bonus("counter_intelligence") * 0.5
		if randf() < defend * 0.5:
			print("  -> %s defended/stayed active despite detection (record + traits saved them)." % agent.name)
			_set_agent_compromised(agent, 1)
		else:
			agent.status = "killed"
			print("  -> %s was killed during the mission." % agent.name)
			agent_killed.emit(agent.agent_id, country)
	elif roll < 0.55:
		agent.status = "captured"
		print("  -> %s was captured." % agent.name)
		agent_captured.emit(agent.agent_id, country)
	else:
		_set_agent_compromised(agent, 3)
		print("  -> %s returned compromised." % agent.name)


func _set_agent_compromised(agent: Agent, years: int) -> void:
	agent.status = "compromised"
	agent.compromised_until_year = _current_year + years
	agent.assigned_target_tag = ""
	agent.current_mission_id = ""
	agent.mission_progress = 0.0
	invalidate_agent_cache(agent.country_tag)


func _release_expired_compromised_agents() -> void:
	for country_agents in agents.values():
		for agent in country_agents as Array[Agent]:
			if agent.status != "compromised":
				continue
			if _current_year < agent.compromised_until_year:
				continue
			agent.status = "available"
			agent.compromised_until_year = 0
			invalidate_agent_cache(agent.country_tag)
			print("AgentManager: %s recovered from compromise." % agent.name)

# Role trait gain on success (makes specialists evolve and become more valuable for big projects/Ascendancy)
func _give_role_trait_from_mission(agent: Agent, mission_id: String, outcome: String) -> void:
	if not mission_definitions.has(mission_id) or outcome == "failure":
		return
	var mission: Dictionary = mission_definitions[mission_id]
	var cat: String = str(mission.get("category", ""))
	var skill_req := str(mission.get("skill_requirement", "")).to_lower()

	var possible_trait := ""
	match [cat, skill_req]:
		["technology", "technology"]:
			possible_trait = "master_researcher"
		["sabotage", "sabotage"]:
			possible_trait = "saboteur_expert"
		["intelligence", "intelligence"]:
			possible_trait = "ghost_operator" if randf() > 0.5 else "master_researcher"
		["influence", _]:
			possible_trait = "diplomatic_visionary"
		["counter_intelligence", "counter_intelligence"]:
			possible_trait = "counter_intel_specialist"
		["influence", "influence"]:
			possible_trait = "industrial_specialist" if randf() > 0.4 else "production_expert"
		["intelligence", _]:
			possible_trait = "resource_explorer" if randf() > 0.5 else "prospector"
		["technology", _]:
			possible_trait = "production_expert" if randf() > 0.6 else "industrial_specialist"

	if possible_trait != "" and possible_trait not in agent.traits and randf() < 0.25:  # rare, earned
		agent.traits.append(possible_trait)
		print("Agent %s earned trait: %s (role mastery from missions)" % [agent.name, possible_trait])


# Apply passive national impacts from active agents' attributes (skills + traits).
# This makes agents an extension of the player's will: their different attributes (e.g. high influence boosts Ascendancy/mandate, industrial boosts production, tech boosts research) have direct ongoing impact to the nation.
# Called daily; small scaled effects to avoid overpower. Uses NMM for persistence.
func apply_agent_national_impacts() -> void:
	if typeof(NationalModifierManager) == TYPE_NIL:
		return
	for country_tag in agents.keys():
		var tag: String = country_tag.strip_edges().to_upper()
		var active_agents: Array[Agent] = []
		for a in get_agents_for_country(tag):
			if a.is_available() or a.is_on_mission():  # active if not captured/killed
				active_agents.append(a)
		if active_agents.is_empty():
			continue
		# Aggregate impacts
		var ascend_bonus: float = 0.0
		var prod_bonus: float = 0.0
		var res_bonus: float = 0.0
		var research_bonus: float = 0.0
		var mil_bonus: float = 0.0
		for a in active_agents:
			ascend_bonus += a.get_national_impact_bonus("ascendancy") * (1.0 + (a.level - 1) * 0.1 + a.get_mission_record_bonus() * 0.5)
			prod_bonus += a.get_national_impact_bonus("production") * (1.0 + (a.level - 1) * 0.1 + a.get_mission_record_bonus() * 0.5)
			res_bonus += a.get_national_impact_bonus("resource") * (1.0 + (a.level - 1) * 0.1 + a.get_mission_record_bonus() * 0.5)
			research_bonus += a.get_national_impact_bonus("research") * (1.0 + (a.level - 1) * 0.1 + a.get_mission_record_bonus() * 0.5)
			mil_bonus += a.get_national_impact_bonus("military") * (1.0 + (a.level - 1) * 0.1 + a.get_mission_record_bonus() * 0.5)
		# Apply small daily scaled (will be monthly in tick, but here daily for responsiveness)
		var daily_scale := 0.033  # ~1/30 for monthly equivalent if called daily
		if ascend_bonus > 0.001:
			NationalModifierManager.apply_national_effect(tag, {
				"effect_id": "%s_agent_national_influence" % tag,
				"source": "agent_national_influence",
				"source_detail": "Active agents' influence attributes",
				"modifiers": {"ascendancy": ascend_bonus * daily_scale, "prestige": ascend_bonus * daily_scale * 0.5},
				"duration_months": 1,
				"remaining_months": 1
			})
		if prod_bonus > 0.001:
			NationalModifierManager.apply_national_effect(tag, {
				"effect_id": "%s_agent_industrial_support" % tag,
				"source": "agent_industrial_support",
				"source_detail": "Active agents' industrial traits/skills",
				"modifiers": {"output_multiplier": prod_bonus * daily_scale},
				"duration_months": 1,
				"remaining_months": 1
			})
		if res_bonus > 0.001:
			NationalModifierManager.apply_national_effect(tag, {
				"effect_id": "%s_agent_resource_influence" % tag,
				"source": "agent_resource_influence",
				"source_detail": "Active agents' exploration/resource traits",
				"modifiers": {"resource_output_multiplier": res_bonus * daily_scale},
				"duration_months": 1,
				"remaining_months": 1
			})
		if research_bonus > 0.001:
			# Boost research via tech or direct (could feed to TM)
			if typeof(TechnologyManager) != TYPE_NIL:
				TechnologyManager.apply_tech_intel_bonus(tag, research_bonus * 0.5, "agent_research_influence")
		if mil_bonus > 0.001:
			NationalModifierManager.apply_national_effect(tag, {
				"effect_id": "%s_agent_military_influence" % tag,
				"source": "agent_military_influence",
				"source_detail": "Active agents' military attributes",
				"modifiers": {"army_org_factor": mil_bonus * daily_scale * 0.5},
				"duration_months": 1,
				"remaining_months": 1
			})


func get_recent_operations(country_tag: String, limit: int = RECENT_OPERATIONS_UI_LIMIT) -> Array[Dictionary]:
	var tag := country_tag.strip_edges().to_upper()
	var ops: Array[Dictionary] = []

	for agent in get_agents_for_country(tag):
		if agent.is_on_mission():
			var mission := get_mission_definition(agent.current_mission_id)
			var progress_pct := int(agent.mission_progress * 100.0)
			ops.append({
				"sort_key": float(_current_year) + 0.99,
				"year": _current_year,
				"agent_id": agent.agent_id,
				"agent_name": agent.name,
				"mission_name": str(mission.get("name", agent.current_mission_id)),
				"target_tag": agent.assigned_target_tag,
				"target_tech_id": agent.assigned_target_tech_id,
				"target_tech_name": (
					TechnologyManager.get_tech_display_name(agent.assigned_target_tech_id)
					if typeof(TechnologyManager) != TYPE_NIL and not agent.assigned_target_tech_id.is_empty()
					else ""
				),
				"outcome": "in_progress",
				"detected": false,
				"progress": agent.mission_progress,
				"status_line": "%d%% underway" % progress_pct,
				"impact_text": "If successful: %s"
				% AgentMissionImpact.describe_mission_outcome(mission, "success"),
				"agent_fate": "",
			})

		for entry_variant in agent.mission_history:
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var entry := (entry_variant as Dictionary).duplicate()
			if not entry.has("agent_name"):
				entry["agent_name"] = agent.name
			if not entry.has("agent_id"):
				entry["agent_id"] = agent.agent_id
			entry["sort_key"] = float(entry.get("year", _current_year))
			ops.append(entry)

	ops.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("sort_key", 0.0)) > float(b.get("sort_key", 0.0))
	)

	var result: Array[Dictionary] = []
	for i in range(mini(ops.size(), limit)):
		result.append(ops[i])
	return result


func describe_mission_outcome(mission_id: String, outcome_key: String) -> String:
	return AgentMissionImpact.describe_mission_outcome(get_mission_definition(mission_id), outcome_key)


func _append_mission_history(
	agent: Agent,
	mission_id: String,
	outcome: String,
	detected: bool,
) -> void:
	var mission := get_mission_definition(mission_id)
	var target_tag := agent.assigned_target_tag
	var fate := _agent_fate_after_mission(agent)

	var impact_text := AgentMissionImpact.describe_mission_outcome(mission, outcome)
	if (
		not agent.assigned_target_tech_id.is_empty()
		and typeof(TechnologyManager) != TYPE_NIL
	):
		impact_text += " · Target: %s" % TechnologyManager.get_tech_display_name(
			agent.assigned_target_tech_id
		)

	var entry := {
		"year": _current_year,
		"agent_id": agent.agent_id,
		"mission_id": mission_id,
		"mission_name": str(mission.get("name", mission_id)),
		"category": str(mission.get("category", "")),
		"target_tag": target_tag,
		"target_tech_id": agent.assigned_target_tech_id,
		"target_tech_name": (
			TechnologyManager.get_tech_display_name(agent.assigned_target_tech_id)
			if typeof(TechnologyManager) != TYPE_NIL and not agent.assigned_target_tech_id.is_empty()
			else ""
		),
		"outcome": outcome,
		"detected": detected,
		"agent_name": agent.name,
		"impact_text": impact_text,
		"agent_fate": fate,
		"status_line": _format_history_status_line(outcome, detected, fate),
		"sort_key": float(_current_year),
	}
	agent.mission_history.insert(0, entry)
	while agent.mission_history.size() > MAX_MISSION_HISTORY_PER_AGENT:
		agent.mission_history.pop_back()
	invalidate_agent_cache(agent.country_tag)


func _agent_fate_after_mission(agent: Agent) -> String:
	match agent.status:
		"killed", "captured", "compromised":
			return agent.status
		_:
			return ""


func _format_history_status_line(outcome: String, detected: bool, fate: String) -> String:
	var parts: PackedStringArray = [outcome.capitalize()]
	if detected:
		parts.append("detected")
	match fate:
		"killed":
			parts.append("agent KIA")
		"captured":
			parts.append("agent captured")
		"compromised":
			parts.append("agent compromised")
	return " · ".join(parts)


func _status_badge_for(agent: Agent) -> String:
	match agent.get_status_group():
		"on_mission":
			return "DEPLOYED"
		"compromised":
			return "COMPROMISED"
		"inactive":
			if agent.status == "killed":
				return "KIA"
			if agent.status == "captured":
				return "CAPTURED"
			return "INACTIVE"
		_:
			return ""


func _recovery_years_remaining(agent: Agent) -> int:
	if agent.status != "compromised":
		return 0
	return maxi(0, agent.compromised_until_year - _current_year)


func _format_agent_status_detail(agent: Agent) -> String:
	match agent.status:
		"compromised":
			var years_left := _recovery_years_remaining(agent)
			if agent.compromised_until_year > _current_year:
				if years_left <= 1:
					return "Lying low — recovery expected %d" % agent.compromised_until_year
				return "Compromised — %d yrs until %d" % [years_left, agent.compromised_until_year]
			return "Compromised (clearing cover)"
		"on_mission":
			if not agent.assigned_target_tag.is_empty():
				var pct := int(agent.mission_progress * 100.0)
				return "Deployed in %s (%d%%)" % [agent.assigned_target_tag, pct]
			return "On active mission"
		"captured":
			return "Captured — network severed"
		"killed":
			return "KIA — out of operations"
		_:
			return agent.status.capitalize()


func get_intel_reports(country_tag: String) -> Array[Dictionary]:
	var intel := get_intel_for_country(country_tag)
	if intel.is_empty():
		return []

	var rows: Array[Dictionary] = []
	for intel_type in intel.keys():
		var value := int(intel.get(intel_type, 0))
		rows.append({
			"intel_type": str(intel_type),
			"label": str(intel_type).capitalize(),
			"value": value,
			"tier": _intel_tier_label(value),
		})
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(b.get("value", 0)) < int(a.get("value", 0))
	)
	return rows


func _intel_tier_label(value: int) -> String:
	if value <= 0:
		return "None"
	if value < 10:
		return "Low"
	if value < 20:
		return "Moderate"
	return "High"


# === Effect Application Helpers (MVP) ===

func _apply_production_delay(agent: Agent, mission: Dictionary, outcome: String, base_magnitude: float) -> void:
	var target_country := agent.country_tag
	var sabotage_skill := agent.get_skill("sabotage")

	# Calculate effective magnitude and duration based on skill + success level
	var sabotage_result: Array = _calculate_sabotage_effect(base_magnitude, sabotage_skill, outcome, agent)
	var final_magnitude: float = sabotage_result[0]
	var duration_months: int = sabotage_result[1]
	var is_critical: bool = sabotage_result[2]

	print("  [EFFECT] %s suffers sabotage-induced production disruption (magnitude: %.2f, duration: %d mo, critical: %s)" % [
		target_country, final_magnitude, duration_months, is_critical
	])

	if is_critical and typeof(LeaderEventUI) != TYPE_NIL:
		LeaderEventUI.post_news(
			"Critical Sabotage Success",
			"%s's operatives have dealt a devastating blow to %s industry. Production and logistics have been severely disrupted." % [
				agent.country_tag, target_country
			],
			"sabotage"
		)

	# Apply the (possibly critical) temporary debuff
	_apply_sabotage_production_debuff(target_country, final_magnitude, duration_months, is_critical)

	# Immediate factory damage (stronger on critical success)
	if typeof(FactoryManager) == TYPE_NIL:
		return

	var damage_multiplier := 1.0
	if is_critical:
		damage_multiplier = 2.2   # Much heavier immediate damage on crit

	var damaged := 0
	var damage_amount := clampf(final_magnitude * 35.0 * damage_multiplier, 15.0, 120.0)

	for fid in FactoryManager.factories.keys():
		var factory = FactoryManager.get_factory(fid)
		if factory == null:
			continue
		if factory.owner_tag != target_country:
			continue
		if randf() < (0.45 if is_critical else 0.35):
			FactoryManager.apply_damage_to_factory(fid, damage_amount)
			damaged += 1
			if damaged >= (3 if is_critical else 2):
				break

	if damaged > 0:
		var msg := "    -> Damaged %d factories belonging to %s" % [damaged, target_country]
		if is_critical:
			msg += " (CRITICAL SABOTAGE)"
		print(msg)


func _apply_supply_disruption(agent: Agent, mission: Dictionary, outcome: String, base_magnitude: float) -> void:
	var target_country := agent.country_tag
	var sabotage_skill := agent.get_skill("sabotage")

	var sabotage_result: Array = _calculate_sabotage_effect(base_magnitude, sabotage_skill, outcome, agent)
	var final_magnitude: float = sabotage_result[0]
	var duration_months: int = sabotage_result[1]
	var is_critical: bool = sabotage_result[2]

	print("  [EFFECT] %s supply lines disrupted by sabotage (magnitude: %.2f, duration: %d mo, critical: %s)" % [
		target_country, final_magnitude, duration_months, is_critical
	])

	if is_critical and typeof(LeaderEventUI) != TYPE_NIL:
		LeaderEventUI.post_news(
			"Critical Sabotage Success",
			"%s agents have crippled %s supply infrastructure in a major operation." % [
				agent.country_tag, target_country
			],
			"sabotage"
		)

	_apply_sabotage_supply_debuff(target_country, final_magnitude, duration_months, is_critical)


# === Deeper Sabotage Calculation & Helpers ===

## Calculates final magnitude, duration, and whether this was a critical success.
## Returns: (final_magnitude, duration_months, is_critical)
func _calculate_sabotage_effect(base_magnitude: float, sabotage_skill: int, outcome: String, agent: Agent) -> Array:
	var magnitude := base_magnitude
	var duration := 8
	var is_critical := false

	# Success level modifier
	if outcome == "success":
		magnitude *= 1.0
		duration = 9
	elif outcome == "partial":
		magnitude *= 0.65
		duration = 5
	else:
		magnitude *= 0.4
		duration = 3

	# Agent skill scaling (skill 1-10)
	var skill_factor := 0.7 + (float(sabotage_skill) * 0.045)   # 0.745 → 1.15
	magnitude *= skill_factor
	duration = int(duration * (0.8 + float(sabotage_skill) * 0.04))

	# Critical success roll (rare, higher with skilled agents on full success)
	if outcome == "success":
		var crit_chance := 0.07 + (float(sabotage_skill) * 0.008)   # 7% base + up to +8%
		crit_chance = clampf(crit_chance, 0.07, 0.16)

		if randf() < crit_chance:
			is_critical = true
			magnitude *= 1.85
			duration = max(duration + 10, 18)

	return [magnitude, duration, is_critical]


func _apply_sabotage_production_debuff(target_country: String, magnitude: float, duration_months: int, is_critical: bool = false) -> void:
	if typeof(NationalModifierManager) == TYPE_NIL:
		print("    -> (No NationalModifierManager) Sabotage would have applied production debuff")
		return

	var penalty := clampf(magnitude, 0.05, 0.38)  # up to ~38% on crit

	var source_detail := "Industrial sabotage"
	if is_critical:
		source_detail = "Critical industrial sabotage"

	var effect := {
		"source": "agent_sabotage",
		"source_detail": source_detail,
		"modifiers": {
			"output_multiplier": -penalty,
			"production_speed": -penalty * 0.6
		},
		"duration_months": duration_months,
		"remaining_months": duration_months,
		"is_debuff": true
	}

	NationalModifierManager.apply_national_effect(target_country, effect)

	var msg := "    -> Applied temporary production debuff to %s (%.0f%% for %d months)" % [target_country, penalty * 100, duration_months]
	if is_critical:
		msg += " [CRITICAL]"
	print(msg)


func _apply_sabotage_supply_debuff(target_country: String, magnitude: float, duration_months: int, is_critical: bool = false) -> void:
	if typeof(NationalModifierManager) == TYPE_NIL:
		print("    -> (No NationalModifierManager) Sabotage would have applied supply debuff")
		return

	var penalty := clampf(magnitude * 0.9, 0.04, 0.28)

	var source_detail := "Logistics sabotage"
	if is_critical:
		source_detail = "Critical logistics sabotage"

	var effect := {
		"source": "agent_sabotage",
		"source_detail": source_detail,
		"modifiers": {
			"supply_consumption": +penalty
		},
		"duration_months": duration_months,
		"remaining_months": duration_months,
		"is_debuff": true
	}

	NationalModifierManager.apply_national_effect(target_country, effect)

	var msg := "    -> Applied temporary supply consumption debuff to %s (+%.0f%% for %d months)" % [target_country, penalty * 100, duration_months]
	if is_critical:
		msg += " [CRITICAL]"
	print(msg)


func _apply_stability_damage(target_country: String, magnitude: float) -> void:
	if typeof(NationalModifierManager) != TYPE_NIL:
		NationalModifierManager.apply_influence_effect(
			target_country,
			-magnitude,             # stability_change
			0.0,                    # prestige_change
			12,                     # duration_months
			"agent_mission",        # source
			"Influence operation"   # source_detail
		)
	else:
		print("  [EFFECT] %s internal stability damaged by %.1f (Influence) — NationalModifierManager not available" % [target_country, magnitude])


func _apply_production_boost(agent: Agent, mission: Dictionary, outcome: String, base_magnitude: float) -> void:
	if typeof(NationalModifierManager) == TYPE_NIL:
		print("    -> (No NationalModifierManager) Production boost would have applied")
		return

	var magnitude: float = base_magnitude
	if outcome == "success":
		magnitude *= 1.0
	elif outcome == "partial":
		magnitude *= 0.6
	else:
		return

	# Skill scaling: influence or tech for production focus
	var skill: int = max(agent.get_skill("influence"), agent.get_skill("technology"))
	var skill_factor: float = 0.8 + (float(skill) * 0.03)
	magnitude *= skill_factor

	# Trait bonus for production/resource agents
	magnitude += (agent.get_trait_bonus("production") * 0.5 if agent.has_method("get_trait_bonus") else 0.0)

	var bonus: float = clampf(magnitude, 0.05, 0.30)
	var duration: int = 6 if outcome == "success" else 4

	var effect := {
		"source": "agent_production_boost",
		"source_detail": "Industrial optimization / espionage",
		"modifiers": {
			"output_multiplier": bonus,
			"production_speed": bonus * 0.7,
			"factory_output": bonus * 0.5
		},
		"duration_months": duration,
		"remaining_months": duration,
		"is_debuff": false
	}

	NationalModifierManager.apply_national_effect(agent.country_tag, effect)

	var msg := "    -> Applied production boost to %s (+%.0f%% output/speed for %d months)" % [agent.country_tag, bonus * 100, duration]
	print(msg)


func _apply_resource_discovery(agent: Agent, mission: Dictionary, outcome: String, base_magnitude: float) -> void:
	if typeof(NationalModifierManager) == TYPE_NIL:
		print("    -> (No NationalModifierManager) Resource discovery would have applied")
		return

	var magnitude: float = base_magnitude
	if outcome == "success":
		magnitude *= 1.0
	elif outcome == "partial":
		magnitude *= 0.5
	else:
		return

	var skill: int = agent.get_skill("intelligence")
	var skill_factor: float = 0.85 + (float(skill) * 0.025)
	magnitude *= skill_factor

	var bonus: float = clampf(magnitude, 0.05, 0.25)
	var duration: int = 8 if outcome == "success" else 5

	var effect := {
		"source": "agent_resource_exploration",
		"source_detail": "Prospecting / resource intelligence",
		"modifiers": {
			"resource_output": bonus,  # Assuming this mod exists or falls to general output
			"supply_efficiency": bonus * 0.4
		},
		"duration_months": duration,
		"remaining_months": duration,
		"is_debuff": false
	}

	NationalModifierManager.apply_national_effect(agent.country_tag, effect)

	var msg := "    -> Applied resource discovery boost to %s (+%.0f%% for %d months)" % [agent.country_tag, bonus * 100, duration]
	print(msg)


func _apply_research_theft(
	agent: Agent,
	mission: Dictionary,
	outcome: String,
	magnitude: float,
	detected: bool,
) -> void:
	if typeof(TechnologyManager) == TYPE_NIL:
		print(
			"  [EFFECT] %s stole %.0f research progress (TechnologyManager unavailable)"
			% [agent.country_tag, magnitude]
		)
		return
	var scale := 1.0 if outcome == "success" else 0.45 if outcome == "partial" else 0.0
	if scale <= 0.0:
		return
	var result: Dictionary = TechnologyManager.apply_research_theft_from_mission(
		agent.country_tag,
		agent.assigned_target_tag,
		agent.assigned_target_tech_id,
		magnitude * scale,
		detected,
		str(mission.get("name", "")),
	)
	print(
		"  [EFFECT] %s stole %.0f days on '%s' from %s (victim lost %.0f, compromised: %s)"
		% [
			agent.country_tag,
			float(result.get("actor_days_applied", 0.0)),
			result.get("tech_name", ""),
			agent.assigned_target_tag,
			float(result.get("victim_days_lost", 0.0)),
			result.get("compromised", false),
		]
	)


func _establish_long_term_tech_intel(agent: Agent, mission: Dictionary, outcome: String) -> void:
	if outcome == "failure":
		return
	var bonus := 0.15 if outcome == "success" else 0.06
	if typeof(TechnologyManager) != TYPE_NIL:
		TechnologyManager.apply_tech_intel_bonus(
			agent.country_tag,
			bonus,
			str(mission.get("name", "")),
		)
	print(
		"  [EFFECT] %s established long-term technology intel (+%.0f RP/day)"
		% [agent.country_tag, bonus]
	)


func _apply_intel_bonus(actor_country: String, magnitude: float) -> void:
	print("  [EFFECT] %s gained temporary intelligence bonus (+%.0f)" % [actor_country, magnitude])


func _apply_secret_space_funding(agent: Agent, mission: Dictionary, outcome: String, magnitude: float, detected: bool = false) -> void:
	if outcome == "failure":
		if detected and typeof(TechnologyManager) != TYPE_NIL:
			# Scandal risk if secret program exposed
			if TechnologyManager.has_rule_flag(agent.country_tag, "secret_funding"):
				print("  [SCANDAL] Secret space funding exposed for %s" % agent.country_tag)
		return
	var bonus := magnitude
	var effective_mult := 1.0
	if typeof(TechnologyManager) != TYPE_NIL:
		# Apply as tech intel bonus, stronger if secret_funding flag present
		effective_mult = 1.5 if TechnologyManager.has_rule_flag(agent.country_tag, "secret_funding") or TechnologyManager.has_tech_unlock(agent.country_tag, "rule_flag", "secret_funding") else 1.0
		TechnologyManager.apply_tech_intel_bonus(
			agent.country_tag,
			bonus * effective_mult,
			"secret_space_funding:" + str(mission.get("id", "black_budget")),
		)
		# Also unlock clandestine flag if not already via tech path
		if TechnologyManager.has_method("grant_temporary_rule_flag"):
			TechnologyManager.grant_temporary_rule_flag(agent.country_tag, "allow_clandestine_space_assets", 180)
	print(
		"  [SECRET SPACE] %s black-funded space progress +%.2f (mult %.1f) via %s"
		% [agent.country_tag, bonus, effective_mult, agent.name]
	)


# Simple intelligence cache for future systems (Supply, Combat, Diplomacy)
var intel_cache: Dictionary = {}  # country_tag -> { "economic": value, "military": value, ... }

func _record_intelligence(country: String, intel_type: String, outcome: String) -> void:
	if not intel_cache.has(country):
		intel_cache[country] = {}

	var cache: Dictionary = intel_cache[country]
	var value := 10 if outcome == "success" else 4
	cache[intel_type] = int(cache.get(intel_type, 0)) + value

	print("  [INTEL] %s gained %d %s intelligence (total: %d)" % [
		country, value, intel_type, int(cache.get(intel_type, 0))
	])


func get_intel_for_country(country_tag: String, intel_type: String = "") -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	if not intel_cache.has(tag):
		return {}
	if intel_type.is_empty():
		return intel_cache[tag].duplicate()
	return {intel_type: intel_cache[tag].get(intel_type, 0)}


## Returns a multiplier (e.g. 0.9 = 10% better intel) based on accumulated agent-gathered intelligence.
## Other systems (Supply, Combat) can call this.
func get_intelligence_modifier(country_tag: String, intel_type: String) -> float:
	var tag := country_tag.strip_edges().to_upper()
	var cache := intel_cache.get(tag, {}) as Dictionary
	var value := int(cache.get(intel_type, 0))

	if value <= 0:
		return 1.0

	# Soft cap: every 25 points of intel gives ~5% better information
	var bonus := minf(value / 500.0, 0.25)   # Max +25% bonus for MVP
	return 1.0 - bonus   # Lower number = better for the player (e.g. less enemy presence hidden)


## Consumes some intel (e.g. when used for a major operation).
func consume_intel(country_tag: String, intel_type: String, amount: int) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	if not intel_cache.has(tag):
		return false

	var cache: Dictionary = intel_cache[tag]
	var current := int(cache.get(intel_type, 0))
	if current < amount:
		return false

	cache[intel_type] = current - amount
	return true


# === Counter-Intelligence Effect Helpers ===

func _apply_enemy_agent_disruption(target_country: String, magnitude: float) -> void:
	var tag := target_country.strip_edges().to_upper()
	var disrupted := 0
	var cleared_effects := 0

	# Real counter-play: enemy networks operating inside (or against) the target's territory
	# are weakened, and their active daily sabotage effects are immediately cleared.
	# This is the basic "repair / counter-intel path" — successful sweeps give direct relief
	# from supply disruption debuffs and hurt the source networks.
	for pid in networks.keys():
		var net: AgentNetwork = networks[pid]
		if net == null or not net.is_active():
			continue
		if net.controlling_country == tag:
			continue  # own network, not enemy

		# Check if network is operating in target's territory (owner or controller)
		var in_target_territory := false
		if typeof(MapManager) != TYPE_NIL:
			var p := MapManager.get_province(int(pid))
			if p != null:
				var owner := p.owner_tag.strip_edges().to_upper()
				var controller := p.controller_tag.strip_edges().to_upper()
				if owner == tag or controller == tag:
					in_target_territory = true
		else:
			# Fallback: treat any foreign-controlled network as potential target for sweep
			in_target_territory = true

		if not in_target_territory:
			continue

		# Weaken the enemy network (scaled by sweep magnitude)
		var weaken := 0.65 if magnitude >= 2.0 else 0.78
		net.strength = maxf(3.0, net.strength * weaken)
		net.local_operatives = max(0, net.local_operatives - int(magnitude) - 1)
		net.detection_risk_accumulated += 0.6 + (magnitude * 0.2)

		# Immediate repair: clear the daily sabotage effects (removes national debuff for this province)
		if typeof(MapManager) != TYPE_NIL:
			MapManager.clear_daily_sabotage_effects(int(pid))
			cleared_effects += 1

		disrupted += 1

	print("  [COUNTER-INTEL] %s sweep: disrupted %d enemy networks, cleared effects in %d provinces (mag %.1f)" % [tag, disrupted, cleared_effects, magnitude])


func _apply_enemy_intel_degradation(actor_country: String, magnitude: float) -> void:
	_degrade_enemy_intel(actor_country, magnitude)


func _degrade_enemy_intel(actor_country: String, magnitude: float) -> void:
	# This is an offensive counter-intel success — degrade the *enemy's* intel on us
	var enemies = []  # In a real game we'd have a list of relevant opponents
	# For MVP, just log a strong effect
	print("  [COUNTER-INTEL] %s successfully degraded enemy intelligence by %d" % [actor_country, int(magnitude)])


func _apply_tech_protection(agent: Agent, mission: Dictionary, magnitude: float) -> void:
	var years := int(magnitude) if int(magnitude) > 0 else 3
	if typeof(TechnologyManager) != TYPE_NIL:
		TechnologyManager.apply_tech_theft_protection(
			agent.country_tag,
			years,
			str(mission.get("name", "")),
		)
	print(
		"  [COUNTER-INTEL] %s research protected until %d"
		% [agent.country_tag, _current_year + years]
	)


# === Biotech mission effect handlers (via NMM/direct for tech progress steal, coh sabotage, detection bonus) ===
# Wired to _on_mission_completed signal flow via _apply + GameData handler extension.
func _apply_clone_sabotage(agent: Agent, mission: Dictionary, outcome: String, magnitude: float, detected: bool = false) -> void:
	var country := agent.country_tag
	var target := "player"  # for demo; in full would resolve from mission or network
	if typeof(GameData) != TYPE_NIL:
		# Direct coh sabotage on target + small ethics/backlash
		GameData.add_grievance(target, int(magnitude * 8), "clone_sabotage")
		if GameData.has_method("apply_pillar_shift"):
			GameData.apply_pillar_shift(target, "cohesion", -int(magnitude * 5), "biotech_sabotage")
		# Drag any cloning tech progress if active
		if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
			if TechnologyManager.is_tech_completed(target, "cloning_tech_1980") or TechnologyManager.has_rule_flag(target, "cloning"):
				# slow progress or force a setback flag
				TechnologyManager.call("edit_tech_progress", target, "cloning_tech_1980", -0.1, false)
		print("[BIOTECH SABOTAGE] Clone vat op by %s on %s: outcome=%s magnitude=%.2f (coh/grievance drag + cloning setback)" % [agent.name, target, outcome, magnitude])
	if detected and typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Clone sabotage " + ("succeeded" if outcome=="success" else outcome) + " by " + agent.name, 4.0)

func _apply_scanner_detection_bonus(country: String, magnitude: float) -> void:
	var tag := country.strip_edges().to_upper()
	if typeof(NationalModifierManager) != TYPE_NIL:
		var mod := {
			"effect_id": "scanner_intel_%s_%d" % [tag, Time.get_unix_time_from_system()],
			"source": "agent_mission",
			"source_detail": "Scanner network intel",
			"modifiers": {"detection_range": magnitude * 0.8, "recon_bonus": magnitude * 0.6},
			"duration_months": 18
		}
		NationalModifierManager.apply_national_effect(tag, mod)
	# Also direct to agent detection in GameData if avail
	if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_agent_pillar_influence"):
		GameData.apply_agent_pillar_influence(tag, "ascendancy", int(magnitude * 3), "scanner_intel")
	print("[SCANNER INTEL] %s gained detection/recon bonus %.2f via agent scanner mission (NMM + pillar)" % [tag, magnitude])


# === Public Peace / Conference API (Phase 1) ===
# These are called by future PeaceConferenceScreen, ScenarioLoader 1918 hook,
# and debug tools. They leverage the GameData.peace_state we just wired.

func is_1918_conference_window_active() -> bool:
	# Simple time-based gate for 1918 start. Real version will use PeaceState + scenario.
	if typeof(TimeManager) != TYPE_NIL:
		var y := TimeManager.get_current_year()
		return y <= 1919
	return true  # fallback for early testing

func get_diplomacy_missions_for_conference(agent_id: String) -> Array[Dictionary]:
	# Returns only diplomacy / conference-relevant missions for the picker.
	var all := get_eligible_missions_for_agent(agent_id)
	var filtered := []
	for m in all:
		var cat: String = str(m.get("category", "")).to_lower()
		if cat in ["diplomacy", "influence"] or m.get("conference_window_only", false):
			filtered.append(m)
	return filtered

func apply_1918_conference_resolution(player_country: String, term_choices: Dictionary) -> Dictionary:
	var leverage := 0
	if typeof(GameData) != TYPE_NIL:
		leverage = GameData.get_inclusion_leverage(player_country)
	# Add delegation score simulation for Phase 1 (real UI will pass real score)
	var summary := {}
	if typeof(GameData) != TYPE_NIL:
		summary = GameData.apply_conference_resolution_1918(player_country, term_choices, leverage)
	return summary

func get_peace_summary_snippet(country_tag: String) -> String:
	if typeof(GameData) != TYPE_NIL:
		var ps: Dictionary = GameData.get_peace_state()
		var lev: int = GameData.get_inclusion_leverage(country_tag)
		if ps.get("conference_1918_completed", false):
			return "1918 Peace resolved (leverage used: %d)" % lev
		return "Pre-conference / leverage: %d" % lev
	return "No peace state"
