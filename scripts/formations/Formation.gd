# scripts/formations/Formation.gd
class_name Formation
extends Resource

const TYPE_DIVISION := "division"
const TYPE_ARMY := "army"
const TYPE_ARMY_GROUP := "army_group"
const TYPE_GARRISON := "garrison"
const TYPE_BRIGADE := "brigade"
const TYPE_FLEET := "fleet"
const TYPE_TASK_FORCE := "task_force"
const TYPE_SHIP := "ship"
const TYPE_AIR_WING := "air_wing"
const TYPE_AIR_SQUADRON := "air_squadron"
const TYPE_AIR_GROUP := "air_group"
const TYPE_SPACE_WING := "space_wing"
const TYPE_ORBITAL_GROUP := "orbital_group"

const CATEGORY_LAND := "land"
const CATEGORY_NAVAL := "naval"
const CATEGORY_AIR := "air"
const CATEGORY_SPACE := "space"

@export var formation_id: String = ""
@export var name: String = ""
@export var formation_type: String = TYPE_DIVISION
@export var country_tag: String = ""
@export var leader_id: String = ""
@export var parent_formation_id: String = ""
@export var is_training: bool = false
@export var is_in_combat: bool = false
## Map province where this formation is stationed (division movement / engineer repair).
@export var stationed_province_id: int = -1

## For air formations: current range/loadout config chosen by player (Ferry_Long_Range, Combat_Load, Escort_Balanced).
## Used by AircraftDesignSystem for effective range calculations.
@export var air_range_config: String = "COMBAT_LOAD"

## Links air formation to a specific design in AircraftDesignSystem for range/reliability/prototyping effects.
@export var air_design_id: String = ""

var assigned_leader: Leader = null


func has_leader() -> bool:
	return not leader_id.is_empty()


func assign_leader(leader: Leader) -> bool:
	if leader == null:
		return false
	leader_id = leader.leader_id
	assigned_leader = leader
	return true


func remove_leader() -> void:
	leader_id = ""
	assigned_leader = null


func get_category() -> String:
	match formation_type:
		TYPE_FLEET, TYPE_TASK_FORCE, TYPE_SHIP:
			return CATEGORY_NAVAL
		TYPE_AIR_WING, TYPE_AIR_SQUADRON, TYPE_AIR_GROUP:
			return CATEGORY_AIR
		TYPE_SPACE_WING, TYPE_ORBITAL_GROUP:
			return CATEGORY_SPACE
		_:
			return CATEGORY_LAND


static func from_division_template(
	division_id: String,
	div_template: DivisionTemplate,
	country: String,
) -> Formation:
	var formation := Formation.new()
	formation.formation_id = division_id
	formation.name = div_template.display_name if not div_template.display_name.is_empty() else division_id
	formation.formation_type = TYPE_DIVISION
	formation.country_tag = country
	return formation

## Helper for air range config (used by AircraftDesignSystem and mission planning).
func get_air_range_config_enum() -> int:
	# Matches AircraftDesignSystem.RangeConfig
	match air_range_config:
		"FERRY_LONG_RANGE", "ferry": return 0
		"ESCORT_BALANCED", "escort": return 2
		_: return 1  # COMBAT_LOAD default

func set_air_range_config_from_string(cfg: String) -> void:
	air_range_config = cfg.to_upper() if cfg else "COMBAT_LOAD"

func get_air_design_id() -> String:
	return air_design_id

func set_air_design_id(did: String) -> void:
	air_design_id = did
