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

# For future: personal traits, special abilities, loyalty, etc.
var traits: Array[String] = []


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

	# Compromised agents are much less effective
	if status == "compromised":
		final_chance *= 0.6

	return clampf(final_chance, 0.05, 0.95)