# scripts/agents/AgentGenerator.gd
class_name AgentGenerator
extends Node

const POSSIBLE_FIRST_NAMES: Array[String] = [
	"Alexei", "Elena", "Marcus", "Sofia", "Johan", "Lila", "Victor", "Anya",
	"Thomas", "Isabelle", "Klaus", "Freya", "Hiroshi", "Mei", "Dmitri", "Natasha"
]

const POSSIBLE_LAST_NAMES: Array[String] = [
	"Voss", "Kovacs", "Lang", "Moreau", "Schmidt", "Petrov", "Tanaka", "Rossi",
	"Bauer", "Dubois", "Kowalski", "Santos", "Yamamoto", "Ivanov", "Laurent"
]


static func generate_agent(country_tag: String, year: int = 1936) -> Agent:
	var agent := Agent.new()

	agent.agent_id = "%s_agent_%d" % [country_tag.to_lower(), Time.get_unix_time_from_system()]
	agent.country_tag = country_tag
	agent.name = _generate_name()
	agent.birth_year = year - randi_range(25, 42)
	agent.start_year = year
	agent.level = randi_range(1, 3)
	agent.experience = randi_range(50, 250) * agent.level

	# Generate varied skill profiles
	agent.intelligence = randi_range(3, 8)
	agent.sabotage = randi_range(2, 7)
	agent.influence = randi_range(3, 8)
	agent.technology = randi_range(2, 7)
	agent.counter_intelligence = randi_range(2, 6)

	# Give some agents a specialty (enhanced for role diversity: diplomacy ~ influence, research/tech, spying/intel, sabotage, counter/stealth, hidden ops)
	var specialty := randi() % 6
	match specialty:
		0:
			agent.intelligence = min(10, agent.intelligence + 3)  # Master Spy / Intel
		1:
			agent.sabotage = min(10, agent.sabotage + 3)  # Saboteur
		2:
			agent.influence = min(10, agent.influence + 3)  # Diplomat / Influencer (Ascendancy lobbying, policy)
		3:
			agent.technology = min(10, agent.technology + 3)  # Researcher / Tech Specialist (projects, steal research)
		4:
			agent.counter_intelligence = min(10, agent.counter_intelligence + 3)  # Counter-Intel / Security (stay hidden, turn agents, secure)
		5:
			# Hybrid "Ghost" - balanced stealth boost + minor to intel/counter
			agent.intelligence = min(10, agent.intelligence + 1)
			agent.counter_intelligence = min(10, agent.counter_intelligence + 2)

	agent.status = "available"
	agent.current_mission_id = ""
	agent.mission_progress = 0.0

	# Assign agent portrait from assets (male/female alternate for visual polish in AssignmentScreen)
	if (randi() % 2) == 0:
		agent.portrait_path = "res://assets/graphics/portraits/agents/agent_male.png"
	else:
		agent.portrait_path = "res://assets/graphics/portraits/agents/agent_female.png"

	# Seed initial trait based on specialty for world-class role differentiation (fun, replay via unique agents)
	match specialty:
		0:
			if randf() > 0.4:
				agent.traits.append("master_researcher")
			else:
				agent.traits.append("tech_specialist")
		1:
			agent.traits.append("saboteur_expert")
		2:
			agent.traits.append("diplomatic_visionary")
		3:
			agent.traits.append("master_researcher")
		4:
			if randf() > 0.5:
				agent.traits.append("counter_intel_specialist")
			else:
				agent.traits.append("ghost_operator")
		5:
			agent.traits.append("ghost_operator")

	# Rare "visionary/breakthrough" trait for early tech unlock (per user feedback): allows certain techs to complete sooner via agent sponsorship, not hard era locks.
	# Makes games interesting/different: right agent + good luck = plausible early adoption of key 1930s tech in 1930 or alt paths.
	if randf() < 0.08:  # ~8% chance for a rare visionary agent
		if "technology" in agent.traits or randf() > 0.5:
			agent.traits.append("breakthrough_visionary")
		else:
			agent.traits.append("visionary_researcher")

	# Production and resource agent traits (expanding per user: positive production impacts, resource gathering/exploration boosts based on type).
	if randf() < 0.12:
		if randf() > 0.5:
			agent.traits.append("industrial_specialist")
		else:
			agent.traits.append("production_expert")
	if randf() < 0.10:
		if randf() > 0.6:
			agent.traits.append("resource_explorer")
		else:
			agent.traits.append("prospector")

	return agent


static func _generate_name() -> String:
	var first: String = POSSIBLE_FIRST_NAMES[randi() % POSSIBLE_FIRST_NAMES.size()]
	var last: String = POSSIBLE_LAST_NAMES[randi() % POSSIBLE_LAST_NAMES.size()]
	return "%s %s" % [first, last]
