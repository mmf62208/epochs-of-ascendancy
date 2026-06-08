# scripts/air/AirMissionProfile.gd
class_name AirMissionProfile
extends Resource

## Basic skeleton for air mission planning, integrating with AircraftDesignSystem.
## Can be used by formations, Supply, Combat for range, payload, effectiveness modifiers.
## Builds on ADS for prototyping/reliability/range tradeoffs.
## Human can create instances or extend for full mission UI/planning.

@export var formation_id: String = ""
@export var design_id: String = ""
@export var range_config: String = "COMBAT_LOAD"  # Ferry, Combat, Escort

var _ads: Node = null  # AircraftDesignSystem ref

func _init(f_id: String = "", d_id: String = "", cfg: String = "COMBAT_LOAD") -> void:
	formation_id = f_id
	design_id = d_id
	range_config = cfg
	_ads = _find_ads()

func _find_ads() -> Node:
	# Try to find ADS (created in Debug or root)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var debug := tree.get_first_node_in_group("debug_overlay")
		if debug and debug.has_method("_get_or_create_aircraft_design_system"):
			return debug.call("_get_or_create_aircraft_design_system")
	return null

## Compute effective range for this profile (uses ADS if available).
func get_effective_range(base_range: float = 1000.0, base_province: int = -1) -> float:
	if _ads and _ads.has_method("get_effective_range"):
		var cfg_enum := _range_config_to_enum()
		return _ads.get_effective_range(base_range, design_id, cfg_enum, base_province)
	return base_range

func _range_config_to_enum() -> int:
	match range_config:
		"FERRY_LONG_RANGE", "ferry": return 0
		"ESCORT_BALANCED", "escort": return 2
		_: return 1

## Rough mission effectiveness modifier (range + reliability from ADS).
func get_mission_modifier() -> float:
	if _ads and _ads.has_method("get_formation_air_modifier"):
		# Create temp formation-like for demo
		var temp_form := {
			"get_air_design_id": func(): return design_id,
			"get_air_range_config_enum": func(): return _range_config_to_enum()
		}
		return _ads.get_formation_air_modifier(temp_form)
	return 1.0

## Example: payload penalty based on config (for bombing missions etc).
func get_payload_multiplier() -> float:
	match range_config:
		"FERRY_LONG_RANGE", "ferry": return 0.4
		"ESCORT_BALANCED", "escort": return 0.8
		_: return 1.0

## Can be extended for full mission: fuel cost, abort chance (from reliability), etc.
## Integrate with Supply for air cargo/fuel, Combat for strike effectiveness.