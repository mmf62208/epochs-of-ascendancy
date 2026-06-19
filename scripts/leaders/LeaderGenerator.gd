# scripts/leaders/LeaderGenerator.gd
class_name LeaderGenerator
extends Node

const SPECIAL_TRAITS: Array[String] = [
	"desert_fox",
	"arctic_bear",
	"sea_wolf",
	"jungle_panther",
	"mountain_specialist",
	"logistics_wizard",
]


static func create_leader_from_data(leader_data: Dictionary) -> Leader:
	var leader := Leader.new()

	leader.leader_id = str(leader_data.get("leader_id", ""))
	leader.name = str(leader_data.get("name", "Unknown"))
	leader.leader_type = str(leader_data.get("leader_type", "general"))
	leader.country_tag = str(leader_data.get("country_tag", ""))

	leader.attack_skill = clampi(int(leader_data.get("attack_skill", 5)), 0, 10)
	leader.defense_skill = clampi(int(leader_data.get("defense_skill", 5)), 0, 10)
	leader.organization_skill = clampi(int(leader_data.get("organization_skill", 5)), 0, 10)
	leader.logistics_skill = clampi(int(leader_data.get("logistics_skill", 5)), 0, 10)
	leader.planning_skill = clampi(int(leader_data.get("planning_skill", 5)), 0, 10)
	leader.initiative_skill = clampi(int(leader_data.get("initiative_skill", 5)), 0, 10)

	leader.experience = int(leader_data.get("experience", 0))
	leader.total_experience_earned = int(
		leader_data.get("total_experience_earned", leader.experience)
	)
	leader.battles_fought = int(leader_data.get("battles_fought", 0))
	leader.is_injured = bool(leader_data.get("is_injured", false))
	leader.is_captured = bool(leader_data.get("is_captured", false))
	leader.assigned_army_id = str(leader_data.get("assigned_army_id", ""))

	leader.birth_year = int(leader_data.get("birth_year", 1900))
	leader.start_year = int(leader_data.get("start_year", 1914))
	leader.end_year = int(leader_data.get("end_year", 0))
	leader.health = clampf(float(leader_data.get("health", 1.0)), 0.1, 1.0)
	leader.duty_post = str(leader_data.get("duty_post", "active"))
	leader.is_in_officer_training = bool(leader_data.get("is_in_officer_training", false))

	_apply_traits_from_data(leader, leader_data)
	leader.training_path_id = str(leader_data.get("training_path_id", ""))
	leader.training_path_level = clampi(int(leader_data.get("training_path_level", 0)), 0, 3)
	leader.previous_training_path_id = str(leader_data.get("previous_training_path_id", ""))
	leader.portrait_path = str(leader_data.get("portrait", leader_data.get("portrait_path", "")))
	return leader


static func _apply_traits_from_data(leader: Leader, leader_data: Dictionary) -> void:
	leader.trait_levels.clear()
	leader.traits.clear()

	if leader_data.has("trait_levels"):
		var trait_levels_block: Variant = leader_data.get("trait_levels")
		if typeof(trait_levels_block) == TYPE_DICTIONARY:
			for trait_id in (trait_levels_block as Dictionary).keys():
				leader.add_trait_unchecked(
					str(trait_id),
					int((trait_levels_block as Dictionary)[trait_id]),
				)
	elif leader_data.has("traits"):
		var traits_block: Variant = leader_data.get("traits")
		if typeof(traits_block) == TYPE_ARRAY:
			for trait_id in traits_block as Array:
				leader.add_trait_unchecked(str(trait_id), 1)


func generate_leader(country_tag: String, leader_type: String = "general") -> Leader:
	var leader_data := {
		"leader_id": "%s_gen_%d" % [country_tag, Time.get_unix_time_from_system()],
		"name": _generate_name(country_tag),
		"country_tag": country_tag,
		"leader_type": leader_type,
		"attack_skill": randi_range(1, 6),
		"defense_skill": randi_range(1, 6),
		"organization_skill": randi_range(2, 7),
		"logistics_skill": randi_range(1, 6),
		"planning_skill": randi_range(1, 6),
		"initiative_skill": randi_range(3, 6),
		"birth_year": randi_range(1895, 1910),
		"start_year": LeaderManager.get_current_year() if typeof(LeaderManager) != TYPE_NIL else 1936,
	}
	var leader := create_leader_from_data(leader_data)

	if randf() < 0.15:
		var trait_id: String = SPECIAL_TRAITS[randi() % SPECIAL_TRAITS.size()]
		LeaderManager.try_add_trait_to_leader(leader, trait_id, 1)

	if randf() < 0.08:
		LeaderManager.try_add_trait_to_leader(leader, "reckless", 1)

	return leader


func _generate_name(country_tag: String) -> String:
	return "%s Commander %d" % [country_tag, randi_range(100, 999)]
