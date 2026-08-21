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

	# Wire new art-batch agent portraits
	var agent_portraits: Array[String] = [
		"res://assets/graphics/portraits/agents/double_agent.png",
		"res://assets/graphics/portraits/agents/elite_spy.png",
		"res://assets/graphics/portraits/agents/visionary_scientist.png",
		"res://assets/graphics/portraits/agents/agent_male.png",
		"res://assets/graphics/portraits/agents/agent_female.png",
		"res://assets/graphics/portraits/agents/agent_italian.png",
	]
	agent.portrait_path = agent_portraits[randi() % agent_portraits.size()]

	return agent


static func _generate_name() -> String:
	var first: String = POSSIBLE_FIRST_NAMES[randi() % POSSIBLE_FIRST_NAMES.size()]
	var last: String = POSSIBLE_LAST_NAMES[randi() % POSSIBLE_LAST_NAMES.size()]
	return "%s %s" % [first, last]
