# scripts/agents/Agent.gd
class_name Agent
extends Resource

@export var agent_id: String = ""
@export var name: String = ""
@export var country_tag: String = ""

@export var level: int = 1
@export var experience: int = 0

# Core agent skills (0-10 scale)
@export var intelligence: int = 4
@export var sabotage: int = 4
@export var influence: int = 4
@export var technology: int = 4
@export var counter_intelligence: int = 3   # For future defensive operations

@export var status: String = "available"   # available, on_mission, compromised, captured, killed, retired

var compromised_until_year: int = 0  # Used when status == "compromised"
var assigned_province_id: int = 0    # Used when the agent is running a province network
@export var assigned_target_tag: String = ""
@export var assigned_target_tech_id: String = ""
@export var current_mission_id: String = ""
@export var mission_progress: float = 0.0  # 0.0 to 1.0

@export var birth_year: int = 1900
@export var start_year: int = 1930
@export var portrait_path: String = ""  # res://assets/graphics/portraits/agents/xxx.png for UI (AgentAssignment, detail)

var total_missions_completed: int = 0
var successful_missions: int = 0

## Recent operations for the assignment UI (newest first). Each entry is a Dictionary.
var mission_history: Array = []

# Traits: personal specializations that provide bonuses (implemented for agent-driven projects, Ascendancy, missions).
# Examples: "master_researcher", "ghost_operator", "diplomatic_visionary", "saboteur_expert", "counter_intel_specialist", "loyal_handler"
var traits: Array[String] = []

# Get bonus for specific contexts (e.g. tech projects, Ascendancy initiatives, mission categories)
func get_trait_bonus(context: String) -> float:
	var bonus: float = 0.0
	for t in traits:
		match t.to_lower():
			"master_researcher", "tech_specialist":
				if context in ["technology", "research_project", "tech_steal"]:
					bonus += 0.20  # +20% to research/project progress or success
			"ghost_operator", "stealth_expert":
				if context in ["counter_intelligence", "stay_hidden", "detection_risk", "sabotage"]:
					bonus += 0.15  # lower detection, better hidden ops
			"diplomatic_visionary", "influence_specialist":
				if context in ["influence", "ascendancy", "policy_lobby", "diplomacy", "vision_sponsor"]:
					bonus += 0.20  # better Ascendancy initiatives, policy missions
			"saboteur_expert":
				if context in ["sabotage", "disrupt", "production_delay"]:
					bonus += 0.18
			"counter_intel_specialist", "turncoat_handler":
				if context in ["counter_intelligence", "turn_agent", "secure", "enemy_disrupt"]:
					bonus += 0.20
			"loyal_handler":
				if context in ["loyalty", "network_strength", "agent_retention"]:
					bonus += 0.10
			"industrial_specialist", "production_expert":
				if context in ["production", "factory", "industrial"]:
					bonus += 0.15
			"resource_explorer", "prospector":
				if context in ["resource", "exploration", "gathering"]:
					bonus += 0.12
	return bonus

# For diffusion interaction: visionary agents can "seed" or accelerate personal access to widespread tech (simulates acquiring samples/intel).
func get_diffusion_boost_for_tech() -> float:
	for t in traits:
		if t.to_lower() in ["breakthrough_visionary", "master_researcher", "tech_specialist", "visionary_researcher"]:
			return 0.05  # extra 5% effective discount when this agent is on the tech
	return 0.0

# National impact bonuses from attributes/traits – agents as extension of player's will, their skills/traits passively or when active impact the nation (Ascendancy, production, etc.).
# Called by AgentManager for active agents to apply ongoing national effects.
func get_national_impact_bonus(impact_type: String) -> float:
	var bonus: float = 0.0
	var base_skill: float = 0.0
	match impact_type.to_lower():
		"ascendancy", "prestige", "mandate", "influence":
			base_skill = get_skill("influence")
			bonus += (base_skill - 5) * 0.01
			for t in traits:
				if t.to_lower() in ["diplomatic_visionary", "influence_specialist"]:
					bonus += 0.03
		"production", "industrial", "factory":
			base_skill = max(get_skill("technology"), get_skill("influence"))
			bonus += (base_skill - 5) * 0.008
			for t in traits:
				if t.to_lower() in ["industrial_specialist", "production_expert"]:
					bonus += 0.04
		"resource", "supply", "exploration":
			base_skill = get_skill("intelligence")
			bonus += (base_skill - 5) * 0.008
			for t in traits:
				if t.to_lower() in ["resource_explorer", "prospector"]:
					bonus += 0.03
		"research", "tech", "development":
			base_skill = get_skill("technology")
			bonus += (base_skill - 5) * 0.01
			for t in traits:
				if t.to_lower() in ["master_researcher", "tech_specialist", "breakthrough_visionary"]:
					bonus += 0.04
		"military", "doctrine", "combat":
			base_skill = max(get_skill("sabotage"), get_skill("intelligence"))  # or add military skill later
			bonus += (base_skill - 5) * 0.005
			for t in traits:
				if t.to_lower() in ["saboteur_expert"]:
					bonus += 0.02
	return bonus


func get_skill(skill_name: String) -> int:
	match skill_name.to_lower():
		"intelligence":
			return intelligence
		"sabotage":
			return sabotage
		"influence":
			return influence
		"technology":
			return technology
		"counter_intelligence":
			return counter_intelligence
		_:
			return 3  # default


func is_available() -> bool:
	return status == "available" and current_mission_id.is_empty()


func is_inactive() -> bool:
	return status in ["captured", "killed", "retired"]


func get_status_group() -> String:
	if is_on_mission():
		return "on_mission"
	if status == "compromised":
		return "compromised"
	if is_inactive():
		return "inactive"
	if is_available():
		return "available"
	return status


func is_on_mission() -> bool:
	return status == "on_mission" and not current_mission_id.is_empty()


func is_compromised(year: int) -> bool:
	return status == "compromised" and year < compromised_until_year


func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	experience += amount

	# Simple leveling
	var xp_needed := level * 150
	while experience >= xp_needed and level < 10:
		experience -= xp_needed
		level += 1
		xp_needed = level * 150
		print("%s has reached agent level %d!" % [name, level])


func get_success_chance_for_mission(mission_data: Dictionary) -> float:
	if mission_data.is_empty():
		return 0.3

	var skill_req: String = str(mission_data.get("skill_requirement", "intelligence"))
	var min_level: int = int(mission_data.get("min_skill_level", 1))

	var agent_skill := get_skill(skill_req)
	var base_chance := float(mission_data.get("base_success_chance", 0.5))

	# Skill bonus
	var skill_bonus := (agent_skill - min_level) * 0.04
	var final_chance := clampf(base_chance + skill_bonus, 0.1, 0.95)

	# Level bonus
	final_chance += (level - 1) * 0.015

	# Trait bonuses (e.g. ghost for lower effective detection, but here for success)
	var trait_ctx := skill_req
	if "sabotage" in skill_req.to_lower():
		trait_ctx = "sabotage"
	final_chance += get_trait_bonus(trait_ctx) * 0.5  # half weight on chance

	# Mission record / veteran bonus: honed agents from successful missions perform better. "missions matter... mission record should also be a part of it."
	final_chance += get_mission_record_bonus() * 0.6  # Record directly boosts chance (learn/grow from history)

	# Compromised agents are much less effective
	if status == "compromised":
		final_chance *= 0.6

	return clampf(final_chance, 0.05, 0.95)

# Bonus for sponsoring / assigned to big tech projects or Ascendancy initiatives
# Called by TechnologyManager or Ascendancy system when agent is assigned (via target_tech_id or equivalent)
func get_project_sponsor_bonus(project_kind: String = "technology") -> float:
	var ctx: String = "technology"
	if "ascend" in project_kind.to_lower() or "initiative" in project_kind.to_lower():
		ctx = "ascendancy"
	elif "doctrine" in project_kind.to_lower():
		ctx = "influence"  # or specific
	return get_trait_bonus(ctx) + (get_skill("technology") - 4) * 0.02 + get_mission_record_bonus() * 0.3 + get_national_impact_bonus("research") * 0.5  # record + attributes boost project sponsorship - agents extend player will into nation/tech

# Early unlock / breakthrough bonus from special traits (user requested: agent trait can allow tech to unlock sooner, not hard lock).
# E.g. master_researcher or new visionary trait reduces effective era_min or ahead penalty for sponsored tech.
# Allows interesting games where right agent enables plausible alt-history early adoption.
func get_early_unlock_years_bonus() -> int:
	var bonus: int = 0
	for t in traits:
		match t.to_lower():
			"master_researcher", "tech_specialist", "visionary_researcher", "breakthrough_visionary":
				bonus += 2  # e.g. 2 years earlier effective
			"polymath":
				bonus += 1
	return bonus

# Mission record impact: Veteran agents perform better, lower risk. Key for "missions matter, learn/grow, record part of it".
# success_ratio helps hone edge + story (high record = "legendary" agent for Ascendancy narrative/impact).
func get_mission_record_bonus() -> float:
	var total: int = max(1, total_missions_completed) as int
	var ratio: float = float(successful_missions) / float(total)
	# Veteran bonus: up to +15% from 100% success record. Scales with volume too (more missions = more "honed").
	var volume_bonus: float = clampf(float(total_missions_completed) * 0.005, 0.0, 0.10)
	return ratio * 0.15 + volume_bonus

# Hone skill from mission (small permanent growth on success; "missions help them hone their skills").
# Called from AgentManager on good outcomes.
func hone_skill_from_mission(skill_name: String, amount: float = 0.2) -> void:
	match skill_name.to_lower():
		"intelligence":
			intelligence = min(10, intelligence + amount)
		"sabotage":
			sabotage = min(10, sabotage + amount)
		"influence":
			influence = min(10, influence + amount)
		"technology":
			technology = min(10, technology + amount)
		"counter_intelligence":
			counter_intelligence = min(10, counter_intelligence + amount)
		_:
			# Default to intelligence for general growth
			intelligence = min(10, intelligence + amount * 0.5)

# Detection modifier from record (high profile fame increases risk unless stealth traits counter).
# "Big part of agent game is them being spotted and targeted" + "ability to defend or stay active".
func get_detection_risk_modifier() -> float:
	var total: int = max(1, total_missions_completed) as int
	var fame: float = float(successful_missions) / float(total) * 0.3  # Success builds "reputation/fame" = higher profile.
	var stealth_defense: float = get_trait_bonus("counter_intelligence") + get_trait_bonus("stay_hidden") + (get_skill("counter_intelligence") - 5) * 0.02
	return fame - stealth_defense  # Net: positive = higher risk, negative = better hidden.